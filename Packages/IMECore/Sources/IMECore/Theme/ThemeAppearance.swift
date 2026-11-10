import Foundation

/// 使用者在主 App 選的外觀：跟隨系統（預設）、固定淺色、固定深色（FR-T03）。
public enum AppearanceSetting: String, Decodable, Equatable, Sendable {
    case system
    case light
    case dark
}

/// 輸入框要求的鍵盤外觀（對應 `UIKeyboardAppearance`；部分 App 會強制深色鍵盤，FR-U23）。
public enum HostKeyboardAppearance: Equatable, Sendable {
    /// 沒有指定（`.default`）。
    case unspecified
    case light
    case dark
}

public enum ThemeAppearance {
    /// 決定這次要用淺色還是深色。
    ///
    /// 優先順序（FR-U23）：App 指定的 `keyboardAppearance` → 使用者的外觀設定 → 系統深淺色。
    public static func isDark(
        setting: AppearanceSetting,
        systemIsDark: Bool,
        host: HostKeyboardAppearance = .unspecified
    ) -> Bool {
        switch host {
        case .dark: return true
        case .light: return false
        case .unspecified: break
        }
        switch setting {
        case .system: return systemIsDark
        case .light: return false
        case .dark: return true
        }
    }
}

/// 對比度檢查（FR-T11）。
public struct ContrastWarning: Equatable, Sendable {
    public let foreground: ThemeColorKey
    public let background: ThemeColorKey
    public let ratio: Double
    public let required: Double
}

public enum ContrastChecker {
    public enum Level: Sendable {
        /// 文字 ≥ 4.5、圖示 ≥ 3（WCAG AA）。
        case standard
        /// 全部 ≥ 7（WCAG AAA，高對比主題）。
        case enhanced
    }

    /// 文字與背景的配對；`isIcon` 的配對只需 3:1（Return 鍵的圖示）。
    private static let pairs: [(fg: ThemeColorKey, bg: ThemeColorKey, isIcon: Bool)] = [
        (.keyText, .keyBackground, false),
        (.candidateText, .candidateBarBackground, false),
        (.composingText, .composingBackground, false),
        (.popupText, .popupBackground, false),
        (.actionKeyText, .actionKeyBackground, true),
    ]

    /// 回傳對比度不足的配對；空陣列代表通過。
    public static func warnings(for palette: ThemePalette, level: Level = .standard) -> [ContrastWarning] {
        let canvas = palette[.keyboardBackground].composited(over: RGBAColor(red: 1, green: 1, blue: 1))
        var result: [ContrastWarning] = []
        for pair in pairs {
            let background = palette[pair.bg].composited(over: canvas)
            let foreground = palette[pair.fg].composited(over: background)
            let ratio = foreground.contrastRatio(with: background)
            let required: Double = level == .enhanced ? 7 : (pair.isIcon ? 3 : 4.5)
            if ratio < required {
                result.append(ContrastWarning(foreground: pair.fg, background: pair.bg, ratio: ratio, required: required))
            }
        }
        return result
    }
}
