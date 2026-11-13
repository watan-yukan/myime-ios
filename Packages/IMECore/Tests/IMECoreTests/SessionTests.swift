import XCTest
@testable import IMECore

/// 假的輸入框：模擬游標前文字與 marked text。
final class MockOutput: TextOutput {
    private(set) var committed = ""
    private(set) var marked = ""

    var textBeforeCursor: String? { committed + marked }
    var visibleText: String { committed + marked }

    func insertText(_ text: String) { committed += text }

    func deleteBackward() {
        if !marked.isEmpty { marked.removeLast() } else if !committed.isEmpty { committed.removeLast() }
    }

    func setMarkedText(_ text: String) { marked = text }

    func unmarkText() {
        committed += marked
        marked = ""
    }

    func preload(_ text: String) { committed = text }
}

/// 組字、Shift、頁面、自動大寫、雙空白句點等整體行為（Issue #13~#18 的鍵盤「大腦」）。全部使用虛構資料。
final class SessionTests: XCTestCase {

    private let source = DictionaryCandidateSource([
        "a": ["一", "二", "三"],
        "ab": ["四"],
        "b": ["五"],
        ",": ["，"],
    ], maxCodeLength: 5)

    private func make(
        _ configure: (inout KeyboardSettings) -> Void = { _ in }
    ) -> (KeyboardSession, MockOutput) {
        var settings = KeyboardSettings()
        configure(&settings)
        let session = KeyboardSession(source: source, settings: settings)
        let output = MockOutput()
        session.output = output
        return (session, output)
    }

    private func tap(_ session: KeyboardSession, _ text: String) {
        for character in text { session.tap(LayoutKey(char: String(character))) }
    }

    private let space = LayoutKey(type: .space)
    private let backspace = LayoutKey(type: .backspace)
    private let returnKey = LayoutKey(type: .returnKey)
    private let shiftKey = LayoutKey(type: .shift)
    private let langKey = LayoutKey(type: .langToggle)

    // MARK: - 中文輸入

    func testTypingCodeThenSpaceCommitsFirstCandidate() {
        let (session, output) = make()
        tap(session, "ab")
        XCTAssertEqual(session.composerState.code, "ab")
        XCTAssertEqual(output.visibleText, "", "組字顯示在鍵盤上方，不進輸入框")
        session.tap(space)
        XCTAssertEqual(output.visibleText, "四")
        XCTAssertFalse(session.composerState.isComposing)
    }

    func testSelectCandidateAndEnglishOption() {
        let (session, output) = make()
        tap(session, "a")
        session.selectCandidate(2)
        tap(session, "a")
        session.selectEnglishOption()
        XCTAssertEqual(output.visibleText, "三a")
    }

    func testSwipeUpSendsEnglishAndRespectsSetting() {
        let (session, output) = make()
        tap(session, "hello")
        session.swipeUpSpace()
        XCTAssertEqual(output.visibleText, "Hello", "空白輸入框是句首，送出的英文自動大寫（FR-E07）")

        let (off, offOutput) = make { $0.spaceSwipeUpEnglish = false }
        tap(off, "hello")
        off.swipeUpSpace()
        XCTAssertEqual(offOutput.visibleText, "")
        XCTAssertEqual(off.composerState.code, "hello")
    }

    func testReturnSendsRawLettersWhileComposingElseNewline() {
        let (session, output) = make()
        tap(session, "ab")
        session.tap(returnKey)
        session.tap(returnKey)
        XCTAssertEqual(output.visibleText, "ab\n")
    }

    func testBackspaceEditsCompositionThenText() {
        let (session, output) = make()
        output.preload("你好")
        tap(session, "ab")
        session.tap(backspace)
        XCTAssertEqual(session.composerState.code, "a")
        session.tap(backspace)
        session.tap(backspace)
        XCTAssertEqual(output.visibleText, "你", "組字清空後，⌫ 才刪輸入框的字")
    }

    func testContextChangeClearsComposition() {
        let (session, output) = make()
        tap(session, "ab")
        session.contextChanged()
        XCTAssertFalse(session.composerState.isComposing)
        XCTAssertEqual(output.visibleText, "")
    }

    // MARK: - 中英模式與 Shift

    func testLanguageToggleSwitchesToDirectEnglish() {
        let (session, output) = make { $0.autoCapitalize = false }
        session.tap(langKey)
        XCTAssertEqual(session.mode, .english)
        tap(session, "ab")
        XCTAssertEqual(output.visibleText, "ab")
        session.tap(langKey)
        XCTAssertEqual(session.mode, .chinese)
    }

    func testShiftOnceUppercasesNextLetterOnly() {
        let (session, output) = make { $0.autoCapitalize = false }
        session.tap(langKey)
        session.tap(shiftKey)
        XCTAssertTrue(session.showsUppercase)
        tap(session, "ab")
        XCTAssertEqual(output.visibleText, "Ab")
        XCTAssertFalse(session.showsUppercase)
    }

    func testShiftLockedByDoubleTap() {
        let (session, output) = make { $0.autoCapitalize = false }
        session.tap(langKey)
        session.tap(shiftKey, now: 0)
        session.tap(shiftKey, now: 0.1)
        tap(session, "abc")
        XCTAssertEqual(output.visibleText, "ABC")
        session.tap(shiftKey, now: 5)
        tap(session, "d")
        XCTAssertEqual(output.visibleText, "ABCd")
    }

    func testShiftLetterInChineseModeTypesUppercaseDirectly() {
        let (session, output) = make { $0.autoCapitalize = false }
        session.tap(shiftKey)
        tap(session, "a")
        XCTAssertEqual(output.visibleText, "A", "FR-E02：Shift + 字母直接輸出大寫，不進入組字")
        XCTAssertFalse(session.composerState.isComposing)
    }

    // MARK: - 自動大寫（FR-U07）

    func testAutoCapitalizationInEnglishMode() {
        let (session, output) = make()
        session.tap(langKey)
        session.contextChanged()  // 文件開頭
        XCTAssertTrue(session.showsUppercase)
        tap(session, "hi")
        XCTAssertEqual(output.visibleText, "Hi")
        XCTAssertFalse(session.showsUppercase)

        tap(session, ".")
        session.tap(space)
        XCTAssertTrue(session.showsUppercase, "句號加空白後下一個字母自動大寫")
        tap(session, "a")
        XCTAssertEqual(output.visibleText, "Hi. A")
    }

    func testSwitchingBackToChineseClearsShift() {
        let (session, output) = make()
        session.tap(langKey)  // 空白輸入框：英文模式自動 Shift
        XCTAssertTrue(session.showsUppercase)
        session.tap(langKey)
        XCTAssertFalse(session.showsUppercase)
        tap(session, "a")
        session.tap(space)
        XCTAssertEqual(output.visibleText, "一", "字根沒有被 Shift 變成大寫英文")
    }

    func testChineseModeNeverAutoShifts() {
        let (session, output) = make()
        session.contextChanged()
        XCTAssertFalse(session.showsUppercase)
        tap(session, "a")
        session.tap(space)
        XCTAssertEqual(output.visibleText, "一", "中文模式的字根不會被自動大寫")
    }

    func testAutoCapitalizationCanBeDisabledAndRespectsFieldType() {
        let (session, _) = make { $0.autoCapitalize = false }
        session.tap(langKey)
        session.contextChanged()
        XCTAssertFalse(session.showsUppercase)

        let (field, _) = make()
        field.autocapitalizationType = .none
        field.tap(langKey)
        field.contextChanged()
        XCTAssertFalse(field.showsUppercase, "輸入框要求不自動大寫（如帳號欄位）")
    }

    func testEnglishSentOverSwipeUpIsCapitalizedAtSentenceStart() {
        let (session, output) = make()
        tap(session, "hello")
        session.swipeUpSpace()
        XCTAssertEqual(output.visibleText, "Hello", "FR-E07")
    }

    // MARK: - 雙空白句點（FR-U08）

    func testDoubleSpaceInEnglishAndChinese() {
        let (session, output) = make()
        session.tap(langKey)
        tap(session, "hello")
        session.tap(space)
        session.tap(space)
        XCTAssertEqual(output.visibleText.lowercased(), "hello. ")

        let (zh, zhOutput) = make()
        zhOutput.preload("你好")
        zh.tap(space)
        zh.tap(space)
        XCTAssertEqual(zhOutput.visibleText, "你好。")
    }

    func testDoubleSpaceCanBeDisabled() {
        let (session, output) = make { $0.doubleSpacePeriod = false }
        output.preload("你好")
        session.tap(space)
        session.tap(space)
        XCTAssertEqual(output.visibleText, "你好  ")
    }

    // MARK: - 頁面與符號

    func testPageSwitching() {
        let (session, output) = make()
        let toNumbers = LayoutKey(type: .page, label: "123", target: "numbers")
        session.tap(toNumbers)
        XCTAssertEqual(session.page, "numbers")
        session.tap(LayoutKey(char: "7"))
        XCTAssertEqual(output.visibleText, "7")
        session.tap(LayoutKey(type: .page, label: "ABC", target: "alpha"))
        XCTAssertEqual(session.page, "alpha")
    }

    func testPunctuationFullWidthInChineseAndHalfWidthInEnglish() {
        let (session, output) = make()
        session.tap(LayoutKey(char: "?"))
        session.tap(langKey)
        session.tap(LayoutKey(char: "?"))
        XCTAssertEqual(output.visibleText, "？?")
    }

    func testNumberRowSelectionSetting() {
        let (session, output) = make { $0.numberRow = true }
        tap(session, "a")
        session.tap(LayoutKey(char: "2"))
        XCTAssertEqual(output.visibleText, "二")
    }

    func testGlobeAndEmojiKeysAreLeftToTheView() {
        let (session, output) = make()
        for type in [KeyType.globe, .emoji, .dismiss, .tab] { session.tap(LayoutKey(type: type)) }
        XCTAssertEqual(output.visibleText, "")
        XCTAssertEqual(session.page, "alpha")
    }

    // MARK: - 輸入框顯示組字（FR-K13）

    func testInlineCompositionUsesMarkedText() {
        let (session, output) = make { $0.composingDisplay = .inline }
        tap(session, "ab")
        XCTAssertEqual(output.marked, "ab")
        XCTAssertEqual(output.committed, "")
        session.tap(backspace)
        XCTAssertEqual(output.marked, "a")
        session.tap(space)
        XCTAssertEqual(output.marked, "")
        XCTAssertEqual(output.committed, "一")
    }

    func testInlineCompositionClearedOnContextChange() {
        let (session, output) = make { $0.composingDisplay = .inline }
        tap(session, "ab")
        session.contextChanged()
        XCTAssertEqual(output.marked, "")
        XCTAssertEqual(output.committed, "", "切換欄位時清掉組字，不送出")
    }

    // MARK: - 長按 ⌫（FR-U09）

    func testHoldBackspaceDeletesCharactersThenWords() {
        let (session, output) = make()
        output.preload("one two three")
        for count in 1..<BackspaceWord.wordThreshold { session.repeatBackspace(count: count) }
        XCTAssertEqual(output.visibleText, "one two three".dropLast(BackspaceWord.wordThreshold - 1).description)

        let (words, wordsOutput) = make()
        wordsOutput.preload("one two three")
        words.repeatBackspace(count: BackspaceWord.wordThreshold)
        XCTAssertEqual(wordsOutput.visibleText, "one two ")
        words.repeatBackspace(count: BackspaceWord.wordThreshold + 1)
        XCTAssertEqual(wordsOutput.visibleText, "one ")
    }

    func testBackspaceWordCounts() {
        XCTAssertEqual(BackspaceWord.deleteCount(textBeforeCursor: "hello world"), 5)
        XCTAssertEqual(BackspaceWord.deleteCount(textBeforeCursor: "hello world  "), 7, "句尾空白一起刪")
        XCTAssertEqual(BackspaceWord.deleteCount(textBeforeCursor: "你好世界"), 1, "中文一次刪一字")
        XCTAssertEqual(BackspaceWord.deleteCount(textBeforeCursor: "abc你好"), 1)
        XCTAssertEqual(BackspaceWord.deleteCount(textBeforeCursor: "hello!"), 1, "符號一次一個")
        XCTAssertEqual(BackspaceWord.deleteCount(textBeforeCursor: "a\n"), 1)
        XCTAssertEqual(BackspaceWord.deleteCount(textBeforeCursor: ""), 1)
        XCTAssertEqual(BackspaceWord.deleteCount(textBeforeCursor: nil), 1)
        XCTAssertEqual(BackspaceWord.deleteCount(textBeforeCursor: "   "), 3)
        XCTAssertEqual(BackspaceWord.deleteCount(textBeforeCursor: "abc123"), 6)
    }

    func testRepeatBackspaceWhileComposingOnlyEditsComposition() {
        let (session, output) = make()
        output.preload("keep me")
        tap(session, "ab")
        session.repeatBackspace(count: 20)
        XCTAssertEqual(session.composerState.code, "a")
        XCTAssertEqual(output.visibleText, "keep me")
    }

    // MARK: - 設定

    func testSettingsChangesApplyToTheComposer() {
        let (session, output) = make()
        session.settings.fullWidthPunctuation = false
        session.tap(LayoutKey(char: "?"))
        XCTAssertEqual(output.visibleText, "?")
    }

    func testOnChangeFires() {
        let (session, _) = make()
        var count = 0
        session.onChange = { count += 1 }
        tap(session, "a")
        XCTAssertGreaterThan(count, 0)
    }
}

final class SettingsTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("imecore-settings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var file: URL { directory.appendingPathComponent("settings.json") }

    func testDefaultsMatchRequirements() {
        let s = KeyboardSettings()
        XCTAssertTrue(s.keySound && s.haptics && s.autoCapitalize && s.doubleSpacePeriod)
        XCTAssertTrue(s.spaceSwipeUpEnglish, "FR-E04：預設開啟")
        XCTAssertFalse(s.spaceSwipeUpAppendSpace)
        XCTAssertFalse(s.numberRow, "FR-U22：預設關閉")
        XCTAssertTrue(s.flickSecondary, "FR-U25：下滑輸入預設開啟")
        XCTAssertEqual(s.composingDisplay, .bar, "FR-K13：預設顯示在鍵盤上方")
        XCTAssertEqual(s.theme, ThemeSelection(id: "native", appearance: .system))
        XCTAssertEqual(s.clipboard.maxItems, 20)
        XCTAssertEqual(s.clipboard.maxDays, 7)
        XCTAssertEqual(s.backup.keep, 10)
    }

    func testMissingFileGivesDefaults() {
        let result = SettingsStore(url: file).load()
        XCTAssertEqual(result.settings, KeyboardSettings())
        XCTAssertTrue(result.writable)
    }

    func testSaveAndLoadRoundTrip() throws {
        var settings = KeyboardSettings()
        settings.numberRow = true
        settings.composingDisplay = .inline
        settings.keycapLabel = .radical
        settings.theme = ThemeSelection(id: "morandi", appearance: .dark)
        settings.clipboard.maxItems = 50
        let store = SettingsStore(url: file)
        try store.save(settings)
        XCTAssertEqual(store.load().settings, settings)
    }

    func testPartialFileUsesDefaultsForMissingFields() throws {
        try Data(#"{ "schemaVersion": 1, "numberRow": true, "theme": { "id": "oled" } }"#.utf8).write(to: file)
        let s = SettingsStore(url: file).load().settings
        XCTAssertTrue(s.numberRow)
        XCTAssertEqual(s.theme.id, "oled")
        XCTAssertEqual(s.theme.appearance, .system)
        XCTAssertTrue(s.haptics)
        XCTAssertTrue(s.flickSecondary, "舊設定檔沒有這個欄位時用預設值")
    }

    func testCorruptFileFallsBackToDefaultsAndKeepsTheOldFile() throws {
        try Data("{ nope".utf8).write(to: file)
        let result = SettingsStore(url: file).load()
        XCTAssertEqual(result.settings, KeyboardSettings())
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("settings.json.corrupt").path))
    }

    func testNewerFileIsReadOnly() throws {
        try Data(#"{ "schemaVersion": 9, "numberRow": true }"#.utf8).write(to: file)
        let result = SettingsStore(url: file).load()
        XCTAssertFalse(result.writable)
        XCTAssertTrue(result.settings.numberRow)
    }
}

final class AlternateCharacterTests: XCTestCase {
    func testLetterAlternates() {
        XCTAssertEqual(AlternateCharacters.options(for: "e").prefix(4), ["è", "é", "ê", "ë"])
        XCTAssertTrue(AlternateCharacters.options(for: "e").contains("ē"))
        XCTAssertEqual(AlternateCharacters.options(for: "n"), ["ñ", "ń"])
        XCTAssertEqual(AlternateCharacters.options(for: "q"), [], "沒有替代字元的字母")
    }

    func testUppercaseFollowsShift() {
        XCTAssertEqual(AlternateCharacters.options(for: "e", uppercase: true).first, "È")
        XCTAssertEqual(AlternateCharacters.options(for: "E").first, "è", "輸出是大寫字母時仍以小寫對照，顯示依 uppercase 參數")
    }

    func testSymbolAlternates() {
        XCTAssertEqual(AlternateCharacters.options(for: "."), ["…", "·", "•"])
        XCTAssertEqual(AlternateCharacters.options(for: "-"), ["–", "—", "•"])
        XCTAssertEqual(AlternateCharacters.options(for: "$").first, "€")
        XCTAssertEqual(AlternateCharacters.options(for: "?"), ["¿"])
    }

    func testNonSingleCharactersHaveNone() {
        XCTAssertEqual(AlternateCharacters.options(for: ""), [])
        XCTAssertEqual(AlternateCharacters.options(for: ".com"), [])
        XCTAssertEqual(AlternateCharacters.options(for: "中"), [])
    }
}

/// 常用詞建議接進鍵盤大腦（FR-S01~S05）。
final class SessionSuggestionTests: XCTestCase {

    private let source = DictionaryCandidateSource(["a": ["信"], "b": ["義"]], maxCodeLength: 5)

    private func make(learning: Bool = true) -> (KeyboardSession, MockOutput, PhraseStore) {
        var settings = KeyboardSettings()
        settings.phraseLearning = learning
        let session = KeyboardSession(source: source, settings: settings)
        let output = MockOutput()
        let store = PhraseStore()
        session.output = output
        session.phraseStore = store
        return (session, output, store)
    }

    private func typeWord(_ session: KeyboardSession) {
        for code in ["a", "b"] {
            session.tap(LayoutKey(char: code))
            session.tap(LayoutKey(type: .space))
        }
    }

    func testLearnedPhraseIsSuggestedAfterTheFirstCharacter() {
        let (session, output, _) = make()
        for _ in 0..<2 {
            output.preload("")
            session.contextChanged()
            typeWord(session)
        }
        output.preload("")
        session.contextChanged()
        session.tap(LayoutKey(char: "a"))
        session.tap(LayoutKey(type: .space))
        XCTAssertEqual(output.visibleText, "信")
        XCTAssertEqual(session.suggestions, [PhraseSuggestion(text: "義", phrase: "信義")])

        session.acceptSuggestion(0)
        XCTAssertEqual(output.visibleText, "信義")
        XCTAssertEqual(session.suggestions, [], "整個詞已輸入完，沒有更多建議")
    }

    func testNoSuggestionsWhileComposingOrInEnglishMode() {
        let (session, output, store) = make()
        store.add(manual: "信義")
        output.preload("信")
        session.contextChanged()
        XCTAssertEqual(session.suggestions.count, 1)

        session.tap(LayoutKey(char: "a"))
        XCTAssertEqual(session.suggestions, [], "組字中候選列留給候選字")

        session.contextChanged()
        session.tap(LayoutKey(type: .langToggle))
        XCTAssertEqual(session.suggestions, [], "英文模式不提供中文詞建議")
    }

    func testTurningLearningOffStopsRecordingAndSuggesting() {
        let (session, output, store) = make(learning: false)
        for _ in 0..<3 {
            output.preload("")
            session.contextChanged()
            typeWord(session)
        }
        XCTAssertTrue(store.records.isEmpty)

        store.add(manual: "信義")
        output.preload("信")
        session.contextChanged()
        XCTAssertEqual(session.suggestions, [], "FR-S05：整個關閉")

        session.settings.phraseLearning = true
        session.contextChanged()
        XCTAssertEqual(session.suggestions.count, 1)
    }

    func testPunctuationBreaksLearning() {
        let (session, output, store) = make()
        for _ in 0..<3 {
            output.preload("")
            session.contextChanged()
            session.tap(LayoutKey(char: "a"))
            session.tap(LayoutKey(type: .space))
            session.tap(LayoutKey(char: "!"))
            session.tap(LayoutKey(char: "b"))
            session.tap(LayoutKey(type: .space))
        }
        XCTAssertNil(store.records["信義"])
    }
}
