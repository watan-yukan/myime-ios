import XCTest
@testable import IMECore

/// 組字狀態機測試（Issue #4）。全部使用虛構資料（R-LIU-4）。
final class ComposerTests: XCTestCase {

    /// 虛構碼表：a→一二、ab→三、abc→四、abcd→五、ka,→か、tsu,→つ（tsu 本身無字）
    private let source = DictionaryCandidateSource([
        "a": ["一", "二"],
        "ab": ["三"],
        "abc": ["四"],
        "abcd": ["五"],
        "b": ["六"],
        "ka,": ["か"],
        "tsu,": ["つ"],
        ",": ["，"],
    ], maxCodeLength: 5)

    private func composer(_ display: ComposingDisplay = .bar) -> Composer {
        Composer(source: source, display: display)
    }

    /// 依序輸入字串中的每個字元，回傳所有輸出動作。
    @discardableResult
    private func type(_ text: String, into composer: inout Composer) -> [OutputAction] {
        text.flatMap { composer.handle(.key($0)) }
    }

    // MARK: - 打字根、出候選

    func testTypingCodeShowsCandidates() {
        var c = composer()
        XCTAssertEqual(type("a", into: &c), [])
        XCTAssertEqual(c.state.code, "a")
        XCTAssertEqual(c.state.candidates, ["一", "二"])
        XCTAssertEqual(c.state.status, .matched)

        type("b", into: &c)
        XCTAssertEqual(c.state.code, "ab")
        XCTAssertEqual(c.state.candidates, ["三"])
    }

    func testUppercaseKeysAreTreatedAsCodes() {
        var c = composer()
        type("AB", into: &c)
        XCTAssertEqual(c.state.code, "ab")
    }

    func testKanaCodeIsIncompleteUntilSuffixTyped() {
        var c = composer()
        type("tsu", into: &c)
        XCTAssertEqual(c.state.status, .incomplete, "tsu 沒有字，但 tsu, 有，不算錯碼")
        XCTAssertEqual(c.state.candidates, [])
        type(",", into: &c)
        XCTAssertEqual(c.state.candidates, ["つ"])
    }

    func testCommaAloneIsACodeKey() {
        var c = composer()
        type(",", into: &c)
        XCTAssertEqual(c.state.candidates, ["，"])
    }

    // MARK: - 送字

    func testSpaceCommitsFirstCandidate() {
        var c = composer()
        type("a", into: &c)
        XCTAssertEqual(c.handle(.space), [.insert("一")])
        XCTAssertEqual(c.state, .idle)
    }

    func testSelectCandidateCommitsThatCandidate() {
        var c = composer()
        type("a", into: &c)
        XCTAssertEqual(c.handle(.selectCandidate(1)), [.insert("二")])
        XCTAssertEqual(c.state, .idle)
    }

    func testSelectCandidateOutOfRangeIsIgnored() {
        var c = composer()
        type("a", into: &c)
        XCTAssertEqual(c.handle(.selectCandidate(5)), [])
        XCTAssertEqual(c.state.code, "a")
        var idle = composer()
        XCTAssertEqual(idle.handle(.selectCandidate(0)), [])
    }

    func testSpaceWhenIdleInsertsSpace() {
        var c = composer()
        XCTAssertEqual(c.handle(.space), [.insert(" ")])
    }

    func testConsecutiveCharacters() {
        var c = composer()
        var output: [OutputAction] = []
        output += type("ab", into: &c)
        output += c.handle(.space)
        output += type("b", into: &c)
        output += c.handle(.space)
        XCTAssertEqual(output, [.insert("三"), .insert("六")])
    }

    // MARK: - 錯碼（FR-K07）

    func testInvalidCodeIsKeptAndSpaceDoesNothing() {
        var c = composer()
        type("az", into: &c)
        XCTAssertEqual(c.state.status, .invalid)
        XCTAssertEqual(c.state.candidates, [])
        XCTAssertEqual(c.handle(.space), [], "錯碼時空白不送字")
        XCTAssertEqual(c.state.code, "az", "保留字根讓使用者修正")
    }

    func testBackspaceFixesInvalidCode() {
        var c = composer()
        type("az", into: &c)
        c.handle(.backspace)
        XCTAssertEqual(c.state.code, "a")
        XCTAssertEqual(c.state.status, .matched)
    }

    // MARK: - 最長碼長

    func testBeyondMaxCodeLengthIsNotInvalid() {
        var c = composer()
        type("abcdab", into: &c)  // 6 碼 > 5
        XCTAssertEqual(c.state.status, .overLength)
        XCTAssertEqual(c.state.code, "abcdab", "保留字母供送出英文（FR-E05）")
    }

    func testBufferHasHardLimit() {
        var c = composer()
        type(String(repeating: "a", count: Composer.maxBufferLength + 5), into: &c)
        XCTAssertEqual(c.state.code.count, Composer.maxBufferLength)
    }

    func testMaxCodeLengthComesFromTable() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "sample", withExtension: "cin", subdirectory: "Fixtures")
        )
        let index = try TableIndex(data: TableIndexBuilder.build(from: CinParser.parse(contentsOf: url).0))
        XCTAssertEqual(index.maxCodeLength, 5, "測試碼表含 xtsu, 共 5 碼，不能寫死 4")

        var c = Composer(source: index)
        type("xtsu,", into: &c)
        XCTAssertEqual(c.state.candidates, ["っ"])
        XCTAssertEqual(c.handle(.space), [.insert("っ")])
    }

    // MARK: - Backspace

    func testBackspaceRemovesLastCodeKey() {
        var c = composer()
        type("abc", into: &c)
        XCTAssertEqual(c.handle(.backspace), [])
        XCTAssertEqual(c.state.code, "ab")
        XCTAssertEqual(c.state.candidates, ["三"])
    }

    func testBackspaceOnLastKeyReturnsToIdle() {
        var c = composer()
        type("a", into: &c)
        c.handle(.backspace)
        XCTAssertEqual(c.state, .idle)
    }

    func testBackspaceWhenIdleDeletesText() {
        var c = composer()
        XCTAssertEqual(c.handle(.backspace), [.deleteBackward])
    }

    // MARK: - 非字根鍵

    func testDigitCommitsCompositionThenInsertsDigit() {
        var c = composer()
        type("a", into: &c)
        XCTAssertEqual(c.handle(.key("3")), [.insert("一"), .insert("3")])
        XCTAssertEqual(c.state, .idle)
    }

    func testNonCodeKeyWithInvalidCodeSendsRawLetters() {
        var c = composer()
        type("az", into: &c)
        XCTAssertEqual(c.handle(.key("!")), [.insert("az"), .insert("！")], "中文模式符號轉全形（#6）")
    }

    // MARK: - 其他事件的基本行為（#7、#8 再細化）

    func testReturnWhileComposingSendsRawLetters() {
        var c = composer()
        type("ab", into: &c)
        XCTAssertEqual(c.handle(.returnKey), [.insert("ab")])
        XCTAssertEqual(c.handle(.returnKey), [.insert("\n")])
    }

    func testContextChangeClearsComposition() {
        var c = composer()
        type("ab", into: &c)
        XCTAssertEqual(c.handle(.contextChanged), [])
        XCTAssertEqual(c.state, .idle)
    }

    func testShiftedKeyCommitsThenInsertsUppercase() {
        var c = composer()
        XCTAssertEqual(c.handle(.shiftedKey("h")), [.insert("H")])
        type("a", into: &c)
        XCTAssertEqual(c.handle(.shiftedKey("h")), [.insert("一"), .insert("H")])
    }

    // MARK: - 組字顯示於輸入框（FR-K13）

    func testInlineDisplayUsesMarkedText() {
        var c = composer(.inline)
        XCTAssertEqual(c.handle(.key("a")), [.setMarked("a")])
        XCTAssertEqual(c.handle(.key("b")), [.setMarked("ab")])
        XCTAssertEqual(c.handle(.backspace), [.setMarked("a")])
        XCTAssertEqual(c.handle(.space), [.insert("一")], "insert 會取代 marked text")
    }

    func testInlineBackspaceToEmptyClearsMarkedText() {
        var c = composer(.inline)
        c.handle(.key("a"))
        XCTAssertEqual(c.handle(.backspace), [.setMarked("")])
        c.handle(.key("a"))
        XCTAssertEqual(c.handle(.contextChanged), [.clearMarked])
    }
}
