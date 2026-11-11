import Foundation

/// 鍵盤的「大腦」：把按鍵、Shift、頁面、中英模式與組字引擎串在一起。
///
/// 畫面層（UIKit）只負責「畫」與「收觸控」，按下哪個鍵之後該做什麼全部在這裡，
/// 所以大部分行為都能用假的輸入框在 Linux 上自動測試。
public final class KeyboardSession {
    public private(set) var composer: Composer
    /// 目前頁面：`alpha`、`numbers`、`symbols`。
    public private(set) var page = "alpha"
    public private(set) var shift = ShiftState()

    public var settings: KeyboardSettings {
        didSet { applySettings() }
    }
    /// 輸入框指定的自動大寫類型（`UITextAutocapitalizationType`）。
    public var autocapitalizationType = AutocapitalizationType.sentences
    public weak var output: TextOutput?
    /// 狀態改變（組字、Shift、頁面、模式）時通知畫面更新。
    public var onChange: (() -> Void)?

    /// 常用詞記錄；設定後會依 `settings.phraseLearning` 開關（FR-S05）。
    public var phraseStore: PhraseStore? {
        didSet { phraseStore?.isEnabled = settings.phraseLearning }
    }
    /// 沒在組字時，候選列顯示的常用詞建議（FR-S01）。
    public private(set) var suggestions: [PhraseSuggestion] = []

    private var markedActive = false

    public init(source: any CandidateSource, settings: KeyboardSettings = KeyboardSettings()) {
        self.composer = Composer(source: source, display: settings.composingDisplay)
        self.settings = settings
        applySettings()
    }

    // MARK: - 畫面查詢

    /// 字母鍵是否顯示大寫（英文模式的 Shift 狀態；中文模式字根永遠顯示小寫）。
    public var showsUppercase: Bool {
        shift.isUppercase
    }

    public var mode: InputMode { composer.mode }
    public var composerState: ComposerState { composer.state }

    // MARK: - 按鍵

    /// 一個鍵被確定按下（放開，或因多指快打而提早送出）。
    public func tap(_ key: LayoutKey, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        switch key.type {
        case .char:
            typeCharacter(key)
        case .shift:
            shift.tap(at: now)
            changed()
        case .space:
            perform(.space)
        case .backspace:
            perform(.backspace)
        case .returnKey:
            perform(.returnKey)
        case .langToggle:
            perform(.toggleInputMode)
            if composer.mode == .chinese {
                shift.reset()  // 中文模式的字根不分大小寫，避免殘留的 Shift 讓字根變成大寫英文
            } else {
                refreshAutoCapitalization()
            }
            changed()
        case .page:
            if let target = key.target { switchPage(to: target) }
        case .globe, .emoji, .dismiss, .tab, .spacer:
            break  // 由畫面層處理
        }
    }

    public func switchPage(to name: String) {
        page = name
        changed()
    }

    /// 空白鍵上滑：把組字內容當英文送出（FR-E03）。
    public func swipeUpSpace() {
        perform(.swipeUpSpace)
    }

    /// 點選常用詞建議：輸入後續文字（FR-S01）。
    public func acceptSuggestion(_ index: Int) {
        guard suggestions.indices.contains(index), let output else { return }
        let text = suggestions[index].text
        output.insertText(text)
        phraseStore?.recordCommit(text)
        refreshSuggestions()
        refreshAutoCapitalization()
        changed()
    }

    public func selectCandidate(_ index: Int) {
        perform(.selectCandidate(index))
    }

    public func selectEnglishOption() {
        perform(.selectEnglishOption)
    }

    /// 長按 ⌫ 的第 `count` 次重複（從 1 起算）：先刪字，之後改刪詞（FR-U09）。
    public func repeatBackspace(count: Int) {
        guard count >= BackspaceWord.wordThreshold, !composer.state.isComposing, let output else {
            perform(.backspace)
            return
        }
        for _ in 0..<BackspaceWord.deleteCount(textBeforeCursor: output.textBeforeCursor) {
            output.deleteBackward()
        }
        refreshAutoCapitalization()
        changed()
    }

    /// 切換輸入欄位、游標移動、鍵盤出現或收起：清除組字（FR-K14）。
    public func contextChanged() {
        phraseStore?.resetContext()
        perform(.contextChanged)
        shift.reset()
        refreshAutoCapitalization()
        changed()
    }

    /// 依輸入框內容重新判斷是否要自動大寫（FR-U07）。
    public func refreshAutoCapitalization() {
        guard settings.autoCapitalize, page == "alpha", composer.mode == .english else { return }
        shift.applyAutoCapitalization(
            AutoCapitalization.shouldCapitalize(textBeforeCursor: output?.textBeforeCursor, type: autocapitalizationType))
    }

    // MARK: - 內部

    private func typeCharacter(_ key: LayoutKey) {
        guard let character = (key.output ?? "").first else { return }
        let event: InputEvent = (character.isLetter && shift.isUppercase) ? .shiftedKey(character) : .key(character)
        perform(event)
        shift.didTypeCharacter()
        refreshAutoCapitalization()
        changed()
    }

    private func perform(_ event: InputEvent) {
        let before = output?.textBeforeCursor
        composer.textBeforeCursor = before
        composer.capitalizeEnglishSend = settings.autoCapitalizeEnglishSend
            && AutoCapitalization.shouldCapitalize(textBeforeCursor: before, type: autocapitalizationType)
        execute(composer.handle(event))
        if event == .space || event == .backspace || event == .returnKey { refreshAutoCapitalization() }
        refreshSuggestions()
        changed()
    }

    /// 只在中文模式、沒有組字時提供建議；組字中候選列要留給候選字。
    private func refreshSuggestions() {
        guard composer.mode == .chinese, !composer.state.isComposing, let store = phraseStore, store.isEnabled else {
            suggestions = []
            return
        }
        suggestions = store.suggestions(afterText: output?.textBeforeCursor, limit: 8)
    }

    private func execute(_ actions: [OutputAction]) {
        guard let output else { return }
        for action in actions {
            switch action {
            case .insert(let text):
                phraseStore?.recordCommit(text)  // 非中文字會中斷目前的詞
                if markedActive {
                    output.setMarkedText(text)  // 取代組字文字再確定，等同 insertText 取代 marked text
                    output.unmarkText()
                    markedActive = false
                } else {
                    output.insertText(text)
                }
            case .deleteBackward:
                output.deleteBackward()
            case .setMarked(let text):
                if text.isEmpty {
                    clearMarked(output)
                } else {
                    output.setMarkedText(text)
                    markedActive = true
                }
            case .clearMarked:
                clearMarked(output)
            }
        }
    }

    private func clearMarked(_ output: TextOutput) {
        guard markedActive else { return }
        output.setMarkedText("")
        output.unmarkText()
        markedActive = false
    }

    private func applySettings() {
        composer.display = settings.composingDisplay
        composer.fullWidthPunctuation = settings.fullWidthPunctuation
        composer.doubleSpacePeriod = settings.doubleSpacePeriod
        composer.spaceSwipeUpEnglish = settings.spaceSwipeUpEnglish
        composer.appendSpaceAfterEnglish = settings.spaceSwipeUpAppendSpace
        composer.numberRowSelection = settings.numberRow
        phraseStore?.isEnabled = settings.phraseLearning
    }

    private func changed() {
        onChange?()
    }
}
