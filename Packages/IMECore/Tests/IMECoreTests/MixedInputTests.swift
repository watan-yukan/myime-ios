import XCTest
@testable import IMECore

/// 中英混打（Issue #8，FR-E01~E07）。全部使用虛構資料。
final class MixedInputTests: XCTestCase {

    private func composer() -> Composer {
        Composer(source: DictionaryCandidateSource([
            "a": ["一", "二"],
            "he": ["賀"],
            "hel": ["赫"],
        ], maxCodeLength: 5))
    }

    private func type(_ text: String, _ c: inout Composer) {
        text.forEach { c.handle(.key($0)) }
    }

    // MARK: - 英文選項（FR-E01）

    func testEnglishOptionShowsRawLetters() {
        var c = composer()
        XCTAssertNil(c.state.englishOption, "沒在組字時沒有英文選項")
        type("hello", &c)
        XCTAssertEqual(c.state.englishOption, "hello")
    }

    func testEnglishOptionIsAvailableEvenWithCandidatesOrInvalidCode() {
        var c = composer()
        type("a", &c)
        XCTAssertEqual(c.state.candidates, ["一", "二"])
        XCTAssertEqual(c.state.englishOption, "a")
        type("zz", &c)
        XCTAssertEqual(c.state.status, .invalid)
        XCTAssertEqual(c.state.englishOption, "azz")
    }

    func testSelectEnglishOptionSendsRawLetters() {
        var c = composer()
        type("hello", &c)
        XCTAssertEqual(c.handle(.selectEnglishOption), [.insert("hello")])
        XCTAssertEqual(c.state, .idle)
    }

    func testSelectEnglishOptionWhenIdleDoesNothing() {
        var c = composer()
        XCTAssertEqual(c.handle(.selectEnglishOption), [])
    }

    // MARK: - 超過碼長（FR-E05）

    func testOverLengthIsNotInvalidAndCanBeSentAsEnglish() {
        var c = composer()
        type("keyboard", &c)  // 8 碼 > 5
        XCTAssertEqual(c.state.status, .overLength)
        XCTAssertEqual(c.handle(.selectEnglishOption), [.insert("keyboard")])
    }

    // MARK: - 空白上滑（FR-E03、E04）

    func testSwipeUpSendsEnglishInsteadOfCandidate() {
        var c = composer()
        type("a", &c)
        XCTAssertEqual(c.handle(.swipeUpSpace), [.insert("a")], "不選中文字「一」")
    }

    func testSwipeUpCanBeDisabled() {
        var c = composer()
        c.spaceSwipeUpEnglish = false
        type("hello", &c)
        XCTAssertEqual(c.handle(.swipeUpSpace), [])
        XCTAssertEqual(c.state.code, "hello", "關閉時組字保持不變")
    }

    func testAppendSpaceAfterEnglishApplies() {
        var c = composer()
        c.appendSpaceAfterEnglish = true
        type("hello", &c)
        XCTAssertEqual(c.handle(.swipeUpSpace), [.insert("hello ")])
        type("hi", &c)
        XCTAssertEqual(c.handle(.selectEnglishOption), [.insert("hi ")])
    }

    func testAppendSpaceDoesNotAffectReturnOrSpace() {
        var c = composer()
        c.appendSpaceAfterEnglish = true
        type("hel", &c)
        XCTAssertEqual(c.handle(.returnKey), [.insert("hel")])
        type("a", &c)
        XCTAssertEqual(c.handle(.space), [.insert("一")])
    }

    // MARK: - Shift 直輸大寫（FR-E02）

    func testShiftedLetterIsInsertedUppercaseWithoutComposing() {
        var c = composer()
        XCTAssertEqual(c.handle(.shiftedKey("h")), [.insert("H")])
        XCTAssertEqual(c.state, .idle)
    }

    func testMixedSentence() {
        var c = composer()
        var out: [OutputAction] = []
        out += c.handle(.shiftedKey("h"))      // H
        "ello".forEach { out += c.handle(.key($0)) }
        out += c.handle(.selectEnglishOption)  // ello
        out += c.handle(.space)                // 空白
        out += c.handle(.key("a"))
        out += c.handle(.space)                // 一
        XCTAssertEqual(out, [.insert("H"), .insert("ello"), .insert(" "), .insert("一")])
    }

    // MARK: - 送出英文套用自動大寫（FR-E07）

    func testCapitalizeEnglishSendUpperCasesFirstLetterOnly() {
        var c = composer()
        c.capitalizeEnglishSend = true
        type("hello", &c)
        XCTAssertEqual(c.handle(.selectEnglishOption), [.insert("Hello")])
        type("he", &c)
        XCTAssertEqual(c.handle(.space), [.insert("賀")], "選中文字不受影響")
    }
}
