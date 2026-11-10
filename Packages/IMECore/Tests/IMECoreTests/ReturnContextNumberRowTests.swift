import XCTest
@testable import IMECore

/// Return、情境改變、數字列選字（Issue #7）。全部使用虛構資料。
final class ReturnContextNumberRowTests: XCTestCase {

    private let twelve = (1...12).map { "字\($0)" }

    private func composer(numberRow: Bool = false, display: ComposingDisplay = .bar) -> Composer {
        var c = Composer(source: DictionaryCandidateSource([
            "a": twelve,
            "ab": ["三"],
            "b": ["六", "七"],
        ], maxCodeLength: 5), display: display)
        c.numberRowSelection = numberRow
        return c
    }

    // MARK: - Return（FR-K12、TBD-17）

    func testReturnWhileComposingSendsRawLettersWithoutNewline() {
        var c = composer()
        c.handle(.key("a"))
        c.handle(.key("b"))
        XCTAssertEqual(c.handle(.returnKey), [.insert("ab")])
        XCTAssertEqual(c.state, .idle)
    }

    func testReturnKeepsTypedCase() {
        // 字根一律小寫；Return 送出的是組字區顯示的小寫字母
        var c = composer()
        c.handle(.key("A"))
        XCTAssertEqual(c.handle(.returnKey), [.insert("a")])
    }

    func testReturnWithInvalidCodeSendsRawLetters() {
        var c = composer()
        "azz".forEach { c.handle(.key($0)) }
        XCTAssertEqual(c.handle(.returnKey), [.insert("azz")])
    }

    func testReturnWhenIdleInsertsNewline() {
        var c = composer()
        XCTAssertEqual(c.handle(.returnKey), [.insert("\n")])
    }

    func testReturnInInlineModeReplacesMarkedText() {
        var c = composer(display: .inline)
        c.handle(.key("a"))
        XCTAssertEqual(c.handle(.returnKey), [.insert("a")], "insert 會取代 marked text")
    }

    // MARK: - 情境改變（FR-K14、TBD-18）

    func testContextChangeClearsWithoutSending() {
        var c = composer()
        c.handle(.key("a"))
        XCTAssertEqual(c.handle(.contextChanged), [])
        XCTAssertEqual(c.state, .idle)
        XCTAssertEqual(c.handle(.space), [.insert(" ")], "清除後空白是一般空白，不會送出舊字")
    }

    func testContextChangeWhenIdleDoesNothing() {
        var c = composer()
        XCTAssertEqual(c.handle(.contextChanged), [])
    }

    func testContextChangeInInlineModeRemovesMarkedText() {
        var c = composer(display: .inline)
        c.handle(.key("a"))
        XCTAssertEqual(c.handle(.contextChanged), [.clearMarked])
    }

    // MARK: - 數字列選字（FR-U22、TBD-14）

    func testDigitOneSelectsFirstCandidate() {
        var c = composer(numberRow: true)
        c.handle(.key("a"))
        XCTAssertEqual(c.handle(.key("1")), [.insert("字1")])
        XCTAssertEqual(c.state, .idle)
    }

    func testDigitZeroSelectsTenthCandidate() {
        var c = composer(numberRow: true)
        c.handle(.key("a"))
        XCTAssertEqual(c.handle(.key("0")), [.insert("字10")])
    }

    func testDigitBeyondCandidatesDoesNothing() {
        var c = composer(numberRow: true)
        c.handle(.key("b"))  // 只有 2 個候選
        XCTAssertEqual(c.handle(.key("5")), [], "沒有第 5 個候選時不動作，也不送出數字")
        XCTAssertEqual(c.state.code, "b")
    }

    func testDigitWhenIdleInsertsDigit() {
        var c = composer(numberRow: true)
        XCTAssertEqual(c.handle(.key("3")), [.insert("3")])
    }

    func testDigitWithNumberRowOffCommitsThenInsertsDigit() {
        var c = composer(numberRow: false)
        c.handle(.key("a"))
        XCTAssertEqual(c.handle(.key("2")), [.insert("字1"), .insert("2")])
    }

    func testSelectionWindowFollowsExpandedPage() {
        var c = composer(numberRow: true)
        c.handle(.key("a"))
        c.selectionWindowStart = 10  // 展開候選表翻到第二頁（每頁 10 個）
        XCTAssertEqual(c.handle(.key("2")), [.insert("字12")])
    }

    func testSelectionWindowResetsWhenCodeChanges() {
        var c = composer(numberRow: true)
        c.handle(.key("a"))
        c.selectionWindowStart = 10
        c.handle(.key("b"))
        XCTAssertEqual(c.selectionWindowStart, 0)
        XCTAssertEqual(c.handle(.key("1")), [.insert("三")])
    }

    func testSelectionWindowResetsAfterCommit() {
        var c = composer(numberRow: true)
        c.handle(.key("a"))
        c.selectionWindowStart = 10
        c.handle(.space)
        XCTAssertEqual(c.selectionWindowStart, 0)
    }
}
