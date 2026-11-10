import Foundation

/// 選字鍵與「本頁第幾個候選」的對應（FR-K04、FR-U22）。
///
/// 依碼表 `%selkey` 的順序：字串中第 n 個字元選本頁第 n 個候選。
/// 例如 `%selkey 1234567890` → `1` 選第一個；`%selkey 0123456789` → `0` 選第一個。
/// 數字列開啟時才會把數字鍵當選字鍵（#7 接上 `Composer`）。
public struct SelectionKeys: Equatable, Sendable {
    /// 去重後的選字鍵，依順序。
    public let keys: [Character]

    /// 嘸蝦米常見的「1 選第一個」排列。
    public static let digitsFromOne = SelectionKeys("1234567890")

    /// - Parameter selkey: 碼表的 `%selkey`；空字串或 nil 時用 `digitsFromOne`。
    public init(_ selkey: String?) {
        var seen = Set<Character>()
        var keys: [Character] = []
        for character in (selkey ?? "") where !character.isWhitespace {
            let key = character.lowercased().first ?? character
            if seen.insert(key).inserted { keys.append(key) }
        }
        self.keys = keys.isEmpty ? Array("1234567890") : keys
    }

    /// 每頁最多能用選字鍵選的數量。
    public var count: Int { keys.count }

    /// 按下 `key` 對應本頁第幾個候選（0 起算）；不是選字鍵回傳 nil。
    public func pageOffset(for key: Character) -> Int? {
        let lower = key.lowercased().first ?? key
        return keys.firstIndex(of: lower)
    }

    /// 本頁第 `offset` 個候選要顯示的選字鍵標籤。
    public func label(forPageOffset offset: Int) -> Character? {
        keys.indices.contains(offset) ? keys[offset] : nil
    }
}
