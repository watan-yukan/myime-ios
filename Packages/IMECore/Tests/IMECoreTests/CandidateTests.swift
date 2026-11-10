import XCTest
@testable import IMECore

/// 候選分頁、候選列排版、選字鍵（Issue #5）。全部使用虛構資料。
final class CandidateTests: XCTestCase {

    /// 假的文字寬度：每個字元 10 pt。
    private let tenPerCharacter: (String) -> Double = { Double($0.count) * 10 }

    private let twelve = (1...12).map { "字\($0)" }

    // MARK: - 候選列排版

    func testFittingCountUsesMinimumItemWidth() {
        // 單字 10 + 內距 16 = 26 < 最小 36 → 每格 36；360 寬放 10 個
        let singles = Array(repeating: "一", count: 20)
        XCTAssertEqual(
            CandidateLayout.fittingCount(singles, availableWidth: 360, textWidth: tenPerCharacter), 10)
    }

    func testFittingCountWithLongerWordsAndReservedWidth() {
        let words = ["一二三四", "五六", "七八九十", "百"]  // 寬 56, 36, 56, 36
        XCTAssertEqual(
            CandidateLayout.fittingCount(words, availableWidth: 200, textWidth: tenPerCharacter), 4)
        XCTAssertEqual(
            CandidateLayout.fittingCount(words, availableWidth: 200, reservedWidth: 44, textWidth: tenPerCharacter), 3)
    }

    func testFittingCountIncludesSpacing() {
        let singles = Array(repeating: "一", count: 5)
        // 每格 36，間距 10：36 + 46 + 46 = 128 ≤ 130，第 4 個要 174
        XCTAssertEqual(
            CandidateLayout.fittingCount(singles, availableWidth: 130, spacing: 10, textWidth: tenPerCharacter), 3)
    }

    func testFittingCountShowsAtLeastOne() {
        let huge = [String(repeating: "長", count: 100)]
        XCTAssertEqual(
            CandidateLayout.fittingCount(huge, availableWidth: 100, textWidth: tenPerCharacter), 1)
        XCTAssertEqual(
            CandidateLayout.fittingCount([], availableWidth: 100, textWidth: tenPerCharacter), 0)
    }

    // MARK: - 分頁

    func testPagesKeepOriginalOrder() {
        var pager = CandidatePager(candidates: twelve, pageSize: 5)
        XCTAssertEqual(pager.pageCount, 3)
        XCTAssertEqual(pager.currentPage.map(\.text), ["字1", "字2", "字3", "字4", "字5"])
        XCTAssertFalse(pager.hasPrevious)
        XCTAssertTrue(pager.hasNext)

        pager.next()
        XCTAssertEqual(pager.currentPage.map(\.index), [5, 6, 7, 8, 9])

        pager.next()
        XCTAssertEqual(pager.currentPage.map(\.text), ["字11", "字12"], "最後一頁可以不滿")
        XCTAssertFalse(pager.hasNext)

        pager.next()
        XCTAssertEqual(pager.pageIndex, 2, "最後一頁再往後不動")
    }

    func testPreviousAndClampedJump() {
        var pager = CandidatePager(candidates: twelve, pageSize: 5)
        pager.previous()
        XCTAssertEqual(pager.pageIndex, 0)
        pager.go(toPage: 99)
        XCTAssertEqual(pager.pageIndex, 2)
        pager.go(toPage: -3)
        XCTAssertEqual(pager.pageIndex, 0)
    }

    func testRevealJumpsToPageContainingIndex() {
        var pager = CandidatePager(candidates: twelve, pageSize: 5)
        pager.reveal(index: 7)
        XCTAssertEqual(pager.pageIndex, 1)
        XCTAssertEqual(pager.globalIndex(forPageOffset: 2), 7)
        XCTAssertNil(pager.globalIndex(forPageOffset: 5))
    }

    func testEmptyAndInvalidPageSize() {
        let empty = CandidatePager(candidates: [], pageSize: 5)
        XCTAssertEqual(empty.pageCount, 0)
        XCTAssertEqual(empty.currentPage, [])
        XCTAssertFalse(empty.hasNext)

        let zero = CandidatePager(candidates: twelve, pageSize: 0)
        XCTAssertEqual(zero.pageSize, 1)
        XCTAssertEqual(zero.pageCount, 12)
    }

    // MARK: - 選字鍵

    func testSelectionKeysFollowSelkeyOrder() {
        let fromZero = SelectionKeys("0123456789")
        XCTAssertEqual(fromZero.pageOffset(for: "0"), 0)
        XCTAssertEqual(fromZero.pageOffset(for: "9"), 9)

        let fromOne = SelectionKeys.digitsFromOne
        XCTAssertEqual(fromOne.pageOffset(for: "1"), 0)
        XCTAssertEqual(fromOne.pageOffset(for: "0"), 9)
        XCTAssertNil(fromOne.pageOffset(for: "a"))
        XCTAssertEqual(fromOne.label(forPageOffset: 0), "1")
        XCTAssertNil(fromOne.label(forPageOffset: 10))
    }

    func testSelectionKeysIgnoreDuplicatesAndWhitespace() {
        let keys = SelectionKeys(" a s d a f ")
        XCTAssertEqual(keys.keys, ["a", "s", "d", "f"])
        XCTAssertEqual(keys.pageOffset(for: "D"), 2)
    }

    func testEmptySelkeyFallsBackToDigits() {
        XCTAssertEqual(SelectionKeys(nil), .digitsFromOne)
        XCTAssertEqual(SelectionKeys(""), .digitsFromOne)
    }

    /// 分頁 + 選字鍵 + 組字狀態機：翻到第二頁按選字鍵，送出的是正確的候選。
    func testSelectionOnSecondPageCommitsCorrectCandidate() {
        let source = DictionaryCandidateSource(["a": twelve])
        var composer = Composer(source: source)
        composer.handle(.key("a"))

        var pager = CandidatePager(candidates: composer.state.candidates, pageSize: 5)
        pager.next()
        let keys = SelectionKeys.digitsFromOne
        let offset = try? XCTUnwrap(keys.pageOffset(for: "3"))
        let index = pager.globalIndex(forPageOffset: offset ?? -1)

        XCTAssertEqual(index, 7)
        XCTAssertEqual(composer.handle(.selectCandidate(index ?? -1)), [.insert("字8")])
    }
}
