import Foundation

/// 雙空白句點（FR-U08）：連按兩下空白，把前一個空白改成句點。
public enum DoubleSpace {
    public enum Result: Equatable, Sendable {
        /// 一般空白。
        case insertSpace
        /// 先刪除 `deleteCount` 個字元，再輸入 `insert`。
        case replace(deleteCount: Int, insert: String)
    }

    /// 不在這些字元後面補句點。
    private static let noPeriodAfter: Set<Character> = [
        ".", "!", "?", ",", ";", ":", "。", "！", "？", "，", "；", "：", "、", "\n",
    ]

    /// - Parameters:
    ///   - textBeforeCursor: 游標前的文字，**已包含**使用者剛才輸入的第一個空白。
    ///   - mode: 英文輸入「. 」；中文輸入「。」。
    public static func result(textBeforeCursor: String?, mode: InputMode) -> Result {
        guard let text = textBeforeCursor, text.count >= 2, text.last == " " else {
            return .insertSpace
        }
        let previous = text[text.index(text.endIndex, offsetBy: -2)]
        guard !previous.isWhitespace, !noPeriodAfter.contains(previous) else {
            return .insertSpace
        }
        switch mode {
        case .english: return .replace(deleteCount: 1, insert: ". ")
        case .chinese: return .replace(deleteCount: 1, insert: "。")
        }
    }
}
