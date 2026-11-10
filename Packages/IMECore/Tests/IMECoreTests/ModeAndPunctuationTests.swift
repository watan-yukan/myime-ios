import XCTest
@testable import IMECore

/// 中英模式切換與標點規則（Issue #6）。全部使用虛構資料。
final class ModeAndPunctuationTests: XCTestCase {

    /// `,` `.` 是字根鍵（比照使用者的嘸蝦米碼表）；`[` `]` 不是。
    private let source = DictionaryCandidateSource([
        "a": ["一", "二"],
        ",": ["，", "、"],
        ".": ["。"],
        "ka,": ["か"],
    ], maxCodeLength: 5, extraCodeKeys: [",", "."])

    private func composer() -> Composer {
        Composer(source: source)
    }

    // MARK: - 中英切換（FR-K08）

    func testStartsInChineseMode() {
        XCTAssertEqual(composer().mode, .chinese)
    }

    func testEnglishModeOutputsKeysDirectly() {
        var c = composer()
        c.handle(.toggleInputMode)
        XCTAssertEqual(c.mode, .english)
        XCTAssertEqual(c.handle(.key("a")), [.insert("a")])
        XCTAssertEqual(c.handle(.shiftedKey("b")), [.insert("B")])
        XCTAssertEqual(c.handle(.key(",")), [.insert(",")], "英文模式標點維持半形")
        XCTAssertEqual(c.handle(.key("!")), [.insert("!")])
        XCTAssertEqual(c.handle(.space), [.insert(" ")])
        XCTAssertEqual(c.handle(.returnKey), [.insert("\n")])
        XCTAssertEqual(c.handle(.backspace), [.deleteBackward])
        XCTAssertEqual(c.state, .idle, "英文模式不組字")
    }

    func testToggleBackToChinese() {
        var c = composer()
        c.handle(.toggleInputMode)
        c.handle(.toggleInputMode)
        XCTAssertEqual(c.mode, .chinese)
        c.handle(.key("a"))
        XCTAssertEqual(c.state.candidates, ["一", "二"])
    }

    func testToggleWhileComposingCommitsFirstCandidate() {
        var c = composer()
        c.handle(.key("a"))
        XCTAssertEqual(c.handle(.toggleInputMode), [.insert("一")])
        XCTAssertEqual(c.state, .idle)
        XCTAssertEqual(c.mode, .english)
    }

    func testToggleWithInvalidCodeCommitsRawLetters() {
        var c = composer()
        c.handle(.key("a"))
        c.handle(.key("z"))
        XCTAssertEqual(c.handle(.toggleInputMode), [.insert("az")])
    }

    // MARK: - `,` `.` 當字根（使用者決定，2026-11-10）

    func testCommaAndPeriodAreCodeKeysInChineseMode() {
        var c = composer()
        XCTAssertEqual(c.handle(.key(",")), [], "單獨按 , 進入組字，不直接送出")
        XCTAssertEqual(c.state.candidates, ["，", "、"])
        XCTAssertEqual(c.handle(.space), [.insert("，")])

        c.handle(.key("."))
        XCTAssertEqual(c.handle(.space), [.insert("。")])
    }

    func testCommaInsideKanaCodeStillComposes() {
        var c = composer()
        "ka,".forEach { c.handle(.key($0)) }
        XCTAssertEqual(c.state.candidates, ["か"])
    }

    // MARK: - 全形標點（FR-K09）

    func testNonCodePunctuationBecomesFullWidth() {
        var c = composer()
        XCTAssertEqual(c.handle(.key("!")), [.insert("！")])
        XCTAssertEqual(c.handle(.key("?")), [.insert("？")])
        XCTAssertEqual(c.handle(.key("[")), [.insert("「")])
        XCTAssertEqual(c.handle(.key("]")), [.insert("」")])
        XCTAssertEqual(c.handle(.key("\\")), [.insert("、")])
        XCTAssertEqual(c.handle(.key("7")), [.insert("7")], "數字維持半形")
        XCTAssertEqual(c.handle(.key("@")), [.insert("@")], "不在對照表的符號原樣輸出")
    }

    func testQuotesAlternateOpenAndClose() {
        var c = composer()
        XCTAssertEqual(c.handle(.key("\"")), [.insert("「")])
        XCTAssertEqual(c.handle(.key("\"")), [.insert("」")])
        XCTAssertEqual(c.handle(.key("\"")), [.insert("「")])
        c.handle(.contextChanged)
        XCTAssertEqual(c.handle(.key("\"")), [.insert("「")], "換欄位後重新從開引號開始")
    }

    func testFullWidthCanBeTurnedOff() {
        var c = composer()
        c.fullWidthPunctuation = false
        XCTAssertEqual(c.handle(.key("!")), [.insert("!")])
    }

    func testPunctuationAfterCompositionCommitsFirst() {
        var c = composer()
        c.handle(.key("a"))
        XCTAssertEqual(c.handle(.key("?")), [.insert("一"), .insert("？")])
    }

    func testPunctuationTableCoversCommonSymbols() {
        var p = Punctuation()
        let converted = "!?:;()[]{}<>~\\".map { p.convert($0) }.joined()
        XCTAssertEqual(converted, "！？：；（）「」『』《》～、")
    }
}
