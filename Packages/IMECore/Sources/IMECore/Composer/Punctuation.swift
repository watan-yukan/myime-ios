import Foundation

/// 中文模式的全形標點（FR-K09）。
///
/// 只套用在「不是字根鍵」的符號上：碼表把 `,` `.` 當字根時，它們照組字處理
/// （使用者決定：比照原生嘸蝦米，2026-11-10）。
public struct Punctuation: Equatable, Sendable {
    /// 半形 → 全形對照。成對引號另外處理。
    public static let fullWidth: [Character: String] = [
        "!": "！", "?": "？", ":": "：", ";": "；",
        ",": "，", ".": "。",
        "(": "（", ")": "）",
        "[": "「", "]": "」", "{": "『", "}": "』",
        "<": "《", ">": "》",
        "~": "～", "\\": "、",
    ]

    /// 下一個 `"` 是否為開引號「。
    private var nextQuoteOpens = true

    public init() {}

    /// 轉換一個符號；不在對照表中的字元（數字、`@` 等）原樣輸出。
    public mutating func convert(_ character: Character) -> String {
        if character == "\"" {
            defer { nextQuoteOpens.toggle() }
            return nextQuoteOpens ? "「" : "」"
        }
        return Self.fullWidth[character] ?? String(character)
    }

    /// 換輸入欄位時重設引號配對。
    public mutating func reset() {
        nextQuoteOpens = true
    }
}
