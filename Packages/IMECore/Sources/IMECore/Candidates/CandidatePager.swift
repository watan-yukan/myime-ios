import Foundation

/// 帶有全域位置的候選（選字時用 `index` 交給 `Composer` 的 `.selectCandidate`）。
public struct IndexedCandidate: Equatable, Sendable {
    /// 在完整候選清單中的位置（0 起算），也就是碼表原始順序。
    public var index: Int
    public var text: String
}

/// 展開候選表的分頁（FR-K06）。
///
/// 分頁只決定「顯示哪些」，候選順序永遠是碼表原始順序（FR-K05）。
public struct CandidatePager: Equatable, Sendable {
    public let candidates: [String]
    public let pageSize: Int
    public private(set) var pageIndex: Int = 0

    /// - Parameter pageSize: 每頁筆數，至少 1。
    public init(candidates: [String], pageSize: Int) {
        self.candidates = candidates
        self.pageSize = max(1, pageSize)
    }

    public var pageCount: Int {
        candidates.isEmpty ? 0 : (candidates.count + pageSize - 1) / pageSize
    }

    public var hasPrevious: Bool { pageIndex > 0 }
    public var hasNext: Bool { pageIndex + 1 < pageCount }

    /// 目前這一頁的候選。
    public var currentPage: [IndexedCandidate] {
        guard !candidates.isEmpty else { return [] }
        let start = pageIndex * pageSize
        let end = min(start + pageSize, candidates.count)
        return (start..<end).map { IndexedCandidate(index: $0, text: candidates[$0]) }
    }

    /// 本頁第 `offset` 個候選的全域位置；超出本頁回傳 nil。
    public func globalIndex(forPageOffset offset: Int) -> Int? {
        let page = currentPage
        guard page.indices.contains(offset) else { return nil }
        return page[offset].index
    }

    public mutating func next() {
        if hasNext { pageIndex += 1 }
    }

    public mutating func previous() {
        if hasPrevious { pageIndex -= 1 }
    }

    /// 跳到指定頁，超出範圍時夾到第一頁或最後一頁。
    public mutating func go(toPage page: Int) {
        guard pageCount > 0 else { pageIndex = 0; return }
        pageIndex = min(max(0, page), pageCount - 1)
    }

    /// 跳到含有全域位置 `index` 的那一頁。
    public mutating func reveal(index: Int) {
        go(toPage: index / pageSize)
    }
}
