import Foundation

/// 長按按鍵出現的替代字元（FR-U06）：`e → é è ê ë ē`、`.` → `… · •`。
public enum AlternateCharacters {
    private static let letters: [Character: String] = [
        "a": "àáâäæãåā", "c": "çćč", "e": "èéêëēėę", "i": "îïíīįì", "l": "ł",
        "n": "ñń", "o": "ôöòóœøōõ", "s": "ßśš", "u": "ûüùúū", "y": "ÿ", "z": "žźż",
    ]

    private static let symbols: [Character: String] = [
        ".": "…·•", "-": "–—•", "?": "¿", "!": "¡", "'": "‘’`", "\"": "“”„«»",
        "$": "€£¥¢₩", "&": "§", "0": "°", "/": "\\", "%": "‰",
    ]

    /// - Parameters:
    ///   - output: 按鍵輸出的字元。
    ///   - uppercase: 字母是否顯示大寫（Shift）。
    /// - Returns: 替代字元清單；沒有則為空陣列。
    public static func options(for output: String, uppercase: Bool = false) -> [String] {
        guard output.count == 1, let character = output.first else { return [] }
        let lower = character.lowercased().first ?? character
        if character.isLetter {
            guard let text = letters[lower] else { return [] }
            return text.map { uppercase ? String($0).uppercased() : String($0) }
        }
        return (symbols[character] ?? "").map { String($0) }
    }
}
