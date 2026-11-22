import Foundation

/// 中文模式的全形標點（FR-K09）。
///
/// 只套用在「不是字根鍵」的符號上：碼表把 `,` `.` 當字根時，它們照組字處理
/// （使用者決定：比照原生嘸蝦米，2026-11-10）。
/// `"` 不轉換、照打半形（2026-11-22 改；原本自動配對成「」，要打「」請用 `[` `]` 或 Shift 下滑）。
public enum Punctuation {
    /// 半形 → 全形對照。
    public static let fullWidth: [Character: String] = [
        "!": "！", "?": "？", ":": "：", ";": "；",
        ",": "，", ".": "。",
        "(": "（", ")": "）",
        "[": "「", "]": "」", "{": "『", "}": "』",
        "<": "《", ">": "》",
        "~": "～", "\\": "、",
    ]

    /// 轉換一個符號；不在對照表中的字元（數字、`@`、`"` 等）原樣輸出。
    public static func convert(_ character: Character) -> String {
        fullWidth[character] ?? String(character)
    }
}
