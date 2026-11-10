import Foundation

/// 組字狀態機查詢候選字的來源。正式使用 `TableIndex`；測試可用 `DictionaryCandidateSource`。
public protocol CandidateSource {
    /// 字根完全相符的候選，依碼表原始順序。
    func candidates(for code: String) -> [String]
    /// 是否有字根以 `prefix` 開頭（判斷錯碼用）。
    func hasCode(withPrefix prefix: String) -> Bool
    /// 碼表最長字根長度（嘸蝦米含假名實測為 5）。
    var maxCodeLength: Int { get }
    /// 可作為字根的按鍵（a–z 以外，例如 `,` `.` `'` `[` `]`）。
    var extraCodeKeys: Set<Character> { get }
}

extension TableIndex: CandidateSource {
    public var maxCodeLength: Int { meta.maxCodeLength }

    public var extraCodeKeys: Set<Character> {
        Set(meta.keyNames.compactMap { $0.key.count == 1 ? $0.key.first : nil }.filter { !$0.isLetter })
    }
}

/// 以字典實作的候選來源，給測試與簡單情境使用。
public struct DictionaryCandidateSource: CandidateSource {
    public var table: [String: [String]]
    public var maxCodeLength: Int
    public var extraCodeKeys: Set<Character>

    public init(_ table: [String: [String]], maxCodeLength: Int? = nil, extraCodeKeys: Set<Character> = [",", "."]) {
        self.table = table
        self.maxCodeLength = maxCodeLength ?? table.keys.map(\.count).max() ?? 0
        self.extraCodeKeys = extraCodeKeys
    }

    public func candidates(for code: String) -> [String] {
        table[code] ?? []
    }

    public func hasCode(withPrefix prefix: String) -> Bool {
        table.keys.contains { $0.hasPrefix(prefix) }
    }
}
