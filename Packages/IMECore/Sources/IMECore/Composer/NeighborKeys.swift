import Foundation

/// 鄰鍵容錯（FR-K15）：打的碼查不到字時，把其中一碼換成鍵盤上相鄰的鍵再查碼表。
///
/// 只處理「按到隔壁鍵」這種錯誤（一次只換一碼），不猜漏打或多打。
public enum NeighborKeys {
    /// QWERTY 字母鍵的鄰鍵：同一排左右兩鍵，加上上、下排斜對角的鍵（iPhone 與 iPad 字母排列相同）。
    public static let table: [Character: [Character]] = [
        "q": ["w", "a"],
        "w": ["q", "e", "a", "s"],
        "e": ["w", "r", "s", "d"],
        "r": ["e", "t", "d", "f"],
        "t": ["r", "y", "f", "g"],
        "y": ["t", "u", "g", "h"],
        "u": ["y", "i", "h", "j"],
        "i": ["u", "o", "j", "k"],
        "o": ["i", "p", "k", "l"],
        "p": ["o", "l"],
        "a": ["s", "q", "w", "z"],
        "s": ["a", "d", "w", "e", "z", "x"],
        "d": ["s", "f", "e", "r", "x", "c"],
        "f": ["d", "g", "r", "t", "c", "v"],
        "g": ["f", "h", "t", "y", "v", "b"],
        "h": ["g", "j", "y", "u", "b", "n"],
        "j": ["h", "k", "u", "i", "n", "m"],
        "k": ["j", "l", "i", "o", "m"],
        "l": ["k", "o", "p"],
        "z": ["x", "a", "s"],
        "x": ["z", "c", "s", "d"],
        "c": ["x", "v", "d", "f"],
        "v": ["c", "b", "f", "g"],
        "b": ["v", "n", "g", "h"],
        "n": ["b", "m", "h", "j"],
        "m": ["n", "j", "k"],
    ]

    /// 最多回傳幾個容錯候選（避免候選列太長）。
    public static let limit = 20

    /// 依序把每一碼換成鄰鍵，收集查得到字的碼。
    ///
    /// 排序：先列出每個容錯碼的**第一個**候選（讓不同的猜測都能出現在候選列前面），
    /// 再列出其餘候選；同一個字只出現一次。
    public static func candidates(for code: String, source: any CandidateSource) -> [String] {
        let characters = Array(code)
        var lists: [[String]] = []
        for (position, original) in characters.enumerated() {
            for neighbor in table[original] ?? [] {
                var replaced = characters
                replaced[position] = neighbor
                let found = source.candidates(for: String(replaced))
                if !found.isEmpty { lists.append(found) }
            }
        }
        var result: [String] = []
        var seen: Set<String> = []
        let rounds = lists.map(\.count).max() ?? 0
        for round in 0..<rounds {
            for list in lists where round < list.count {
                let candidate = list[round]
                guard seen.insert(candidate).inserted else { continue }
                result.append(candidate)
                if result.count >= limit { return result }
            }
        }
        return result
    }
}
