import Foundation

/// 內建主題的後備：App bundle 找不到主題檔時，至少還有「原生」可用，鍵盤不會因此壞掉。
///
/// 內容必須與 `Shared/Themes/native.json` 完全一致，由測試確認。
public enum BuiltinThemes {
    public static let nativeJSON = #"""
    {
      "schemaVersion": 1,
      "id": "native",
      "name": "原生",
      "builtin": true,
      "metrics": { "cornerRadiusScale": 1.0, "fontScale": 1.0, "spacingScale": 1.0, "keyBorderWidth": 0 },
      "light": {
        "keyboardBackground": "#E3E4E8",
        "keyBackground": "#FFFFFF",
        "keyBackgroundPressed": "#E3E4E8",
        "keyText": "#000000",
        "keyTextPressed": "#000000",
        "keySecondaryText": "#8E8E93",
        "keyBorder": "#00000000",
        "keyShadow": "#0000001A",
        "actionKeyBackground": "#3478F5",
        "actionKeyText": "#FFFFFF",
        "disabledKeyBackground": "#C0C1C5",
        "candidateBarBackground": "#E3E4E8",
        "candidateText": "#000000",
        "candidateHighlight": "#3478F5",
        "candidateSeparator": "#0000001A",
        "composingBackground": "#D1D3D9",
        "composingText": "#000000",
        "popupBackground": "#FFFFFF",
        "popupText": "#000000"
      },
      "dark": {
        "keyboardBackground": "#1F1F1F",
        "keyBackground": "#444444",
        "keyBackgroundPressed": "#6E6F69",
        "keyText": "#FFFFFF",
        "keyTextPressed": "#FFFFFF",
        "keySecondaryText": "#9A9A9F",
        "keyBorder": "#00000000",
        "keyShadow": "#00000000",
        "actionKeyBackground": "#3478F5",
        "actionKeyText": "#FFFFFF",
        "disabledKeyBackground": "#797979",
        "candidateBarBackground": "#1F1F1F",
        "candidateText": "#FFFFFF",
        "candidateHighlight": "#64A0FF",
        "candidateSeparator": "#FFFFFF26",
        "composingBackground": "#5E5E5E",
        "composingText": "#FFFFFF",
        "popupBackground": "#555756",
        "popupText": "#FFFFFF"
      }
    }
    """#

    /// 「原生」主題（內建後備版本）。
    public static func native() -> Theme {
        // 內容是固定的內建資料，解析失敗代表程式本身有錯，讓測試第一時間抓到
        guard let theme = try? Theme.load(from: Data(nativeJSON.utf8)) else {
            preconditionFailure("內建原生主題解析失敗")
        }
        return theme
    }
}
