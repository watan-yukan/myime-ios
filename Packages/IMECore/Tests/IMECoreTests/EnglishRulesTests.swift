import XCTest
@testable import IMECore

/// 英文自動大寫、雙空白句點、Shift 狀態（Issue #9，FR-U07~U09）。全部使用虛構文字。
final class EnglishRulesTests: XCTestCase {

    // MARK: - 自動大寫（FR-U07）

    func testSentencesCapitalizeAtStart() {
        XCTAssertTrue(AutoCapitalization.shouldCapitalize(textBeforeCursor: nil, type: .sentences))
        XCTAssertTrue(AutoCapitalization.shouldCapitalize(textBeforeCursor: "", type: .sentences))
    }

    func testSentencesCapitalizeAfterTerminatorAndSpace() {
        for text in ["Hi. ", "Hi! ", "Hi? ", "你好。 ", "Hi.  ", "Hi.\n", "Hi\n", "   "] {
            XCTAssertTrue(
                AutoCapitalization.shouldCapitalize(textBeforeCursor: text, type: .sentences), "text=\(text)")
        }
    }

    func testSentencesDoNotCapitalizeMidSentence() {
        for text in ["Hi", "Hi ", "Hi, ", "Hi.", "end.x", "a b "] {
            XCTAssertFalse(
                AutoCapitalization.shouldCapitalize(textBeforeCursor: text, type: .sentences), "text=\(text)")
        }
    }

    func testWordsCapitalizeAfterWhitespace() {
        XCTAssertTrue(AutoCapitalization.shouldCapitalize(textBeforeCursor: nil, type: .words))
        XCTAssertTrue(AutoCapitalization.shouldCapitalize(textBeforeCursor: "hello ", type: .words))
        XCTAssertTrue(AutoCapitalization.shouldCapitalize(textBeforeCursor: "hello\n", type: .words))
        XCTAssertFalse(AutoCapitalization.shouldCapitalize(textBeforeCursor: "hello", type: .words))
    }

    func testAllCharactersAndNone() {
        XCTAssertTrue(AutoCapitalization.shouldCapitalize(textBeforeCursor: "abc", type: .allCharacters))
        XCTAssertFalse(AutoCapitalization.shouldCapitalize(textBeforeCursor: nil, type: .none))
        XCTAssertFalse(AutoCapitalization.shouldCapitalize(textBeforeCursor: "Hi. ", type: .none))
    }

    // MARK: - 雙空白句點（FR-U08）

    func testDoubleSpaceInEnglishInsertsPeriodAndSpace() {
        XCTAssertEqual(
            DoubleSpace.result(textBeforeCursor: "hello ", mode: .english),
            .replace(deleteCount: 1, insert: ". "))
    }

    func testDoubleSpaceInChineseInsertsFullStop() {
        XCTAssertEqual(
            DoubleSpace.result(textBeforeCursor: "你好 ", mode: .chinese),
            .replace(deleteCount: 1, insert: "。"))
    }

    func testDoubleSpaceIgnoredWhenNotApplicable() {
        for text in [nil, "", " ", "hi", "hi.  ", "hi, ", "hi.\n ", "  ", "你好。 "] as [String?] {
            XCTAssertEqual(
                DoubleSpace.result(textBeforeCursor: text, mode: .english), .insertSpace, "text=\(String(describing: text))")
        }
    }

    func testComposerAppliesDoubleSpaceWhenIdle() {
        var c = Composer(source: DictionaryCandidateSource(["a": ["一"]]))
        c.textBeforeCursor = "你好 "
        XCTAssertEqual(c.handle(.space), [.deleteBackward, .insert("。")])

        c.handle(.toggleInputMode)
        c.textBeforeCursor = "hello "
        XCTAssertEqual(c.handle(.space), [.deleteBackward, .insert(". ")])
    }

    func testComposerDoubleSpaceCanBeDisabledAndNeedsContext() {
        var c = Composer(source: DictionaryCandidateSource(["a": ["一"]]))
        c.textBeforeCursor = "你好 "
        c.doubleSpacePeriod = false
        XCTAssertEqual(c.handle(.space), [.insert(" ")])

        c.doubleSpacePeriod = true
        c.textBeforeCursor = nil
        XCTAssertEqual(c.handle(.space), [.insert(" ")], "沒有上下文時不猜")
    }

    func testSpaceWhileComposingStillCommitsCandidate() {
        var c = Composer(source: DictionaryCandidateSource(["a": ["一"]]))
        c.textBeforeCursor = "你好 "
        c.handle(.key("a"))
        XCTAssertEqual(c.handle(.space), [.insert("一")], "組字中的空白是送字，不是句點")
    }

    // MARK: - Shift 狀態（FR-U09）

    func testSingleTapIsOneShot() {
        var shift = ShiftState()
        shift.tap(at: 0)
        XCTAssertEqual(shift.mode, .once)
        XCTAssertTrue(shift.isUppercase)
        shift.didTypeCharacter()
        XCTAssertEqual(shift.mode, .off)
        XCTAssertFalse(shift.isUppercase)
    }

    func testDoubleTapLocksUntilTappedAgain() {
        var shift = ShiftState()
        shift.tap(at: 0)
        shift.tap(at: 0.2)
        XCTAssertEqual(shift.mode, .locked)
        shift.didTypeCharacter()
        shift.didTypeCharacter()
        XCTAssertEqual(shift.mode, .locked, "鎖定時打字不會解除")
        shift.tap(at: 5)
        XCTAssertEqual(shift.mode, .off)
    }

    func testSlowSecondTapTurnsOffInsteadOfLocking() {
        var shift = ShiftState()
        shift.tap(at: 0)
        shift.tap(at: 1.0)
        XCTAssertEqual(shift.mode, .off)
    }

    func testTypingBetweenTapsPreventsAccidentalLock() {
        var shift = ShiftState()
        shift.tap(at: 0)
        shift.didTypeCharacter()
        shift.tap(at: 0.1)
        XCTAssertEqual(shift.mode, .once, "中間有打字，不算雙擊")
    }

    func testAutoCapitalizationOnlyAppliesWhenOff() {
        var shift = ShiftState()
        shift.applyAutoCapitalization(true)
        XCTAssertEqual(shift.mode, .once)

        var locked = ShiftState()
        locked.tap(at: 0)
        locked.tap(at: 0.1)
        locked.applyAutoCapitalization(true)
        XCTAssertEqual(locked.mode, .locked, "不覆蓋鎖定")

        var off = ShiftState()
        off.applyAutoCapitalization(false)
        XCTAssertEqual(off.mode, .off)
        off.reset()
        XCTAssertEqual(off.mode, .off)
    }
}
