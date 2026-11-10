import Foundation

/// 對應 UIKit 的 `UITextAutocapitalizationType`（引擎不 import UIKit，由鍵盤層轉換）。
public enum AutocapitalizationType: Equatable, Sendable {
    case none
    case words
    case sentences
    case allCharacters
}

/// 英文自動大寫判斷（FR-U07）：依輸入框指定的類型與游標前的文字，決定下一個字母是否自動大寫。
public enum AutoCapitalization {
    /// 句尾符號（含全形）；換行也視為新句開頭。
    private static let sentenceEnders: Set<Character> = [".", "!", "?", "。", "！", "？", "\n"]

    /// - Parameter textBeforeCursor: 游標前的文字（`documentContextBeforeInput`）；nil 或空字串代表在最前面。
    public static func shouldCapitalize(
        textBeforeCursor: String?,
        type: AutocapitalizationType
    ) -> Bool {
        switch type {
        case .none:
            return false
        case .allCharacters:
            return true
        case .words:
            guard let last = textBeforeCursor?.last else { return true }
            return last.isWhitespace
        case .sentences:
            guard let text = textBeforeCursor, !text.isEmpty else { return true }
            if text.last == "\n" { return true }
            // 句尾符號後要先有空白，才是新的一句（"end." 後面直接接字不算）
            let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
            guard trimmed.count < text.count else { return false }
            guard let last = trimmed.last else { return true }  // 全是空白：視為句首
            return sentenceEnders.contains(last)
        }
    }
}
