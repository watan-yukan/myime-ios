import Foundation

/// 主題的顏色項目（docs/04_UI規格.md 6.2）。UI 元件只透過這些 token 取色（FR-T01）。
public enum ThemeColorKey: String, CaseIterable, Sendable {
    case keyboardBackground
    case keyBackground
    case keyBackgroundPressed
    case keyText
    case keyTextPressed
    case keySecondaryText
    /// 無邊框時用透明色 `#00000000`。
    case keyBorder
    /// 無陰影時用透明色 `#00000000`。
    case keyShadow
    case actionKeyBackground
    case actionKeyText
    case disabledKeyBackground
    case candidateBarBackground
    case candidateText
    case candidateHighlight
    case candidateSeparator
    case composingBackground
    case composingText
    case popupBackground
    case popupText
}

/// 一組完整的顏色（淺色或深色）。
public struct ThemePalette: Equatable, Sendable {
    private var values: [ThemeColorKey: RGBAColor]

    public subscript(key: ThemeColorKey) -> RGBAColor {
        values[key] ?? .clear
    }

    init(values: [ThemeColorKey: RGBAColor]) {
        self.values = values
    }

    /// 以 `patch` 覆蓋，缺少的項目沿用自己（自訂主題從原生複製後只改部分顏色）。
    func applying(_ patch: [ThemeColorKey: RGBAColor]) -> ThemePalette {
        ThemePalette(values: values.merging(patch) { _, new in new })
    }
}

/// 主題的尺寸倍率（版面尺寸由版面決定，主題只能微調倍率，docs/04 6.1）。
public struct ThemeMetrics: Equatable, Sendable, Decodable {
    public var cornerRadiusScale: Double
    public var fontScale: Double
    public var spacingScale: Double
    /// 按鍵邊框粗細（pt）；0 表示無邊框。
    public var keyBorderWidth: Double

    public static let standard = ThemeMetrics(cornerRadiusScale: 1, fontScale: 1, spacingScale: 1, keyBorderWidth: 0)

    public init(cornerRadiusScale: Double = 1, fontScale: Double = 1, spacingScale: Double = 1, keyBorderWidth: Double = 0) {
        self.cornerRadiusScale = Self.clamp(cornerRadiusScale, 0...2)
        self.fontScale = Self.clamp(fontScale, 0.8...1.4)
        self.spacingScale = Self.clamp(spacingScale, 0.5...1.5)
        self.keyBorderWidth = Self.clamp(keyBorderWidth, 0...4)
    }

    private enum CodingKeys: String, CodingKey {
        case cornerRadiusScale, fontScale, spacingScale, keyBorderWidth
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            cornerRadiusScale: try container.decodeIfPresent(Double.self, forKey: .cornerRadiusScale) ?? 1,
            fontScale: try container.decodeIfPresent(Double.self, forKey: .fontScale) ?? 1,
            spacingScale: try container.decodeIfPresent(Double.self, forKey: .spacingScale) ?? 1,
            keyBorderWidth: try container.decodeIfPresent(Double.self, forKey: .keyBorderWidth) ?? 0)
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

public enum ThemeError: Error, Equatable {
    case unsupportedSchema(Int)
    case emptyID
    case invalidColor(key: String, value: String)
    /// 沒有基底主題可補，而且缺少這個顏色。
    case missingColor(String)
}

public struct Theme: Equatable, Sendable {
    public static let supportedSchemaVersion = 1

    public let id: String
    public let name: String
    public let isBuiltin: Bool
    public let metrics: ThemeMetrics
    public let light: ThemePalette
    public let dark: ThemePalette

    public func palette(isDark: Bool) -> ThemePalette {
        isDark ? dark : light
    }

    private struct Raw: Decodable {
        var schemaVersion: Int
        var id: String
        var name: String
        var builtin: Bool?
        var metrics: ThemeMetrics?
        var light: [String: String]
        var dark: [String: String]?
    }

    /// 解析主題檔（FR-T02）。
    ///
    /// - Parameter fallback: 基底主題；JSON 缺少的顏色以它同模式的值補上（自訂主題的舊檔仍可載入）。
    ///   內建的「原生」主題要完整定義，不用基底。
    /// - 只提供 `light` 時，深色模式共用同一組（例如純黑 OLED）。
    public static func load(from data: Data, fallback: Theme? = nil) throws -> Theme {
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        guard raw.schemaVersion == supportedSchemaVersion else { throw ThemeError.unsupportedSchema(raw.schemaVersion) }
        guard !raw.id.isEmpty else { throw ThemeError.emptyID }

        let light = try resolve(raw.light, base: fallback?.light)
        let dark = try raw.dark.map { try resolve($0, base: fallback?.dark) } ?? light
        return Theme(
            id: raw.id, name: raw.name, isBuiltin: raw.builtin ?? false,
            metrics: raw.metrics ?? fallback?.metrics ?? .standard, light: light, dark: dark)
    }

    private static func resolve(_ texts: [String: String], base: ThemePalette?) throws -> ThemePalette {
        var patch: [ThemeColorKey: RGBAColor] = [:]
        for (name, text) in texts {
            guard let key = ThemeColorKey(rawValue: name) else { continue }  // 不認得的項目略過（向前相容）
            guard let color = RGBAColor(hex: text) else { throw ThemeError.invalidColor(key: name, value: text) }
            patch[key] = color
        }
        if let base { return base.applying(patch) }
        for key in ThemeColorKey.allCases where patch[key] == nil {
            throw ThemeError.missingColor(key.rawValue)
        }
        return ThemePalette(values: patch)
    }
}
