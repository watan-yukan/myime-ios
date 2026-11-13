import XCTest
@testable import IMECore

/// 主題引擎的純邏輯：解析、補值、內建主題、對比度、深淺色決定（Issue #25、#26，FR-T01~T03、T11、U23）。
final class ThemeTests: XCTestCase {

    private func themeData(_ name: String) throws -> Data {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return try Data(contentsOf: url.appendingPathComponent("Shared/Themes/\(name).json"))
    }

    private func loadBuiltin(_ name: String) throws -> Theme {
        try Theme.load(from: themeData(name))
    }

    private let builtinNames = ["native", "morandi", "high-contrast", "oled"]

    // MARK: - 顏色

    func testHexParsingAndFormatting() throws {
        let color = try XCTUnwrap(RGBAColor(hex: "#3478F5"))
        XCTAssertEqual(color.hex, "#3478F5")
        XCTAssertEqual(color.alpha, 1)
        XCTAssertEqual(try XCTUnwrap(RGBAColor(hex: "3478f5")).hex, "#3478F5", "可省略 # 且不分大小寫")

        let translucent = try XCTUnwrap(RGBAColor(hex: "#FFFFFF26"))
        XCTAssertEqual(translucent.alpha, 0x26 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(translucent.hex, "#FFFFFF26")
        XCTAssertEqual(RGBAColor.clear.hex, "#00000000")

        for bad in ["", "#12345", "#GGGGGG", "#1234567", "red"] {
            XCTAssertNil(RGBAColor(hex: bad), bad)
        }
    }

    func testContrastRatioMatchesWCAGReferenceValues() throws {
        let black = RGBAColor(red: 0, green: 0, blue: 0)
        let white = RGBAColor(red: 1, green: 1, blue: 1)
        XCTAssertEqual(black.contrastRatio(with: white), 21, accuracy: 0.001)
        XCTAssertEqual(white.contrastRatio(with: white), 1, accuracy: 0.001)
        // #767676 對白色是 WCAG 公認剛好達到 4.5:1 的灰
        let gray = try XCTUnwrap(RGBAColor(hex: "#767676"))
        XCTAssertEqual(gray.contrastRatio(with: white), 4.54, accuracy: 0.02)
    }

    func testAlphaCompositing() {
        let half = RGBAColor(red: 1, green: 1, blue: 1, alpha: 0.5)
        let result = half.composited(over: RGBAColor(red: 0, green: 0, blue: 0))
        XCTAssertEqual(result.red, 0.5, accuracy: 0.0001)
        XCTAssertEqual(result.alpha, 1)
    }

    // MARK: - 內建主題（FR-T03）

    func testAllBuiltinThemesLoadWithEveryColor() throws {
        for name in builtinNames {
            let theme = try loadBuiltin(name)
            XCTAssertTrue(theme.isBuiltin, name)
            XCTAssertEqual(theme.id, name)
            for key in ThemeColorKey.allCases {
                // 所有項目都有定義（不會落到 .clear 的預設值以外的意外）
                _ = theme.light[key]
                _ = theme.dark[key]
            }
        }
        XCTAssertEqual(try loadBuiltin("native").name, "原生")
        XCTAssertEqual(try loadBuiltin("morandi").name, "莫蘭迪")
        XCTAssertEqual(try loadBuiltin("high-contrast").name, "高對比")
        XCTAssertEqual(try loadBuiltin("oled").name, "純黑 OLED")
    }

    func testNativeMatchesMeasuredColors() throws {
        let native = try loadBuiltin("native")
        XCTAssertEqual(native.light[.keyboardBackground].hex, "#E3E4E8")
        XCTAssertEqual(native.light[.keyBackground].hex, "#FFFFFF")
        XCTAssertEqual(native.dark[.keyboardBackground].hex, "#1F1F1F")
        XCTAssertEqual(native.dark[.keyBackground].hex, "#444444")
        XCTAssertEqual(native.dark[.keyBackgroundPressed].hex, "#6E6F69")
        XCTAssertEqual(native.light[.actionKeyBackground].hex, "#3478F5")
        XCTAssertEqual(native.metrics, .standard)
    }

    func testOLEDSharesOnePaletteForLightAndDark() throws {
        let oled = try loadBuiltin("oled")
        XCTAssertEqual(oled.light, oled.dark, "只提供 light 時，深色模式共用同一組")
        XCTAssertEqual(oled.palette(isDark: false)[.keyboardBackground].hex, "#000000")
        XCTAssertEqual(oled.palette(isDark: true)[.keyboardBackground].hex, "#000000")
    }

    func testHighContrastHasBorderAndLargerFont() throws {
        let theme = try loadBuiltin("high-contrast")
        XCTAssertEqual(theme.metrics.keyBorderWidth, 2)
        XCTAssertEqual(theme.metrics.fontScale, 1.1, accuracy: 0.0001)
        XCTAssertEqual(theme.light[.keyBorder].hex, "#000000")
        XCTAssertEqual(theme.dark[.keyBorder].hex, "#FFFFFF")
        XCTAssertEqual(theme.dark[.keyBackgroundPressed].hex, "#FFFFFF", "按下時反白")
        XCTAssertEqual(theme.dark[.keyTextPressed].hex, "#000000")
    }

    // MARK: - 對比度（FR-T11）

    func testBuiltinThemesPassContrastChecks() throws {
        for name in builtinNames {
            let theme = try loadBuiltin(name)
            for isDark in [false, true] {
                let warnings = ContrastChecker.warnings(for: theme.palette(isDark: isDark))
                XCTAssertTrue(warnings.isEmpty, "\(name) \(isDark ? "深" : "淺")色對比不足：\(warnings)")
            }
        }
    }

    func testHighContrastThemePassesEnhancedLevel() throws {
        let theme = try loadBuiltin("high-contrast")
        for isDark in [false, true] {
            let warnings = ContrastChecker.warnings(for: theme.palette(isDark: isDark), level: .enhanced)
            XCTAssertTrue(warnings.isEmpty, "高對比主題應達 7:1，\(isDark ? "深" : "淺")色：\(warnings)")
        }
    }

    func testContrastCheckerFlagsLowContrast() throws {
        let native = try loadBuiltin("native")
        let bad = try Theme.load(from: Data(#"""
        { "schemaVersion": 1, "id": "bad", "name": "壞",
          "light": { "keyText": "#F0F0F0", "keyBackground": "#FFFFFF" } }
        """#.utf8), fallback: native)
        let warnings = ContrastChecker.warnings(for: bad.light)
        XCTAssertEqual(warnings.map(\.foreground), [.keyText])
        XCTAssertEqual(warnings.first?.background, .keyBackground)
        XCTAssertLessThan(warnings[0].ratio, 1.2)
        XCTAssertEqual(warnings[0].required, 4.5)
    }

    func testContrastUsesActualBackgroundForTranslucentColors() {
        // 半透明白字疊在白底上看不見：不能只比較顏色值本身
        var colors: [ThemeColorKey: RGBAColor] = [:]
        for key in ThemeColorKey.allCases { colors[key] = RGBAColor(red: 1, green: 1, blue: 1) }
        colors[.keyText] = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0.05)
        let warnings = ContrastChecker.warnings(for: ThemePalette(values: colors))
        XCTAssertTrue(warnings.contains { $0.foreground == .keyText })
    }

    // MARK: - 解析與補值（FR-T02、T06）

    func testMissingColorsFallBackToBaseTheme() throws {
        let native = try loadBuiltin("native")
        let custom = try Theme.load(from: Data(#"""
        { "schemaVersion": 1, "id": "mine", "name": "我的",
          "light": { "keyBackground": "#FFF8E7" }, "dark": { "keyBackground": "#202020" } }
        """#.utf8), fallback: native)
        XCTAssertFalse(custom.isBuiltin)
        XCTAssertEqual(custom.light[.keyBackground].hex, "#FFF8E7")
        XCTAssertEqual(custom.light[.keyText], native.light[.keyText], "沒寫的沿用原生淺色")
        XCTAssertEqual(custom.dark[.keyBackground].hex, "#202020")
        XCTAssertEqual(custom.dark[.keyText], native.dark[.keyText], "沒寫的沿用原生深色")
        XCTAssertEqual(custom.metrics, native.metrics)
    }

    func testOnlyLightWithFallbackDoesNotPullInBaseDark() throws {
        let native = try loadBuiltin("native")
        let custom = try Theme.load(from: Data(#"""
        { "schemaVersion": 1, "id": "mine", "name": "我的", "light": { "keyText": "#112233" } }
        """#.utf8), fallback: native)
        XCTAssertEqual(custom.dark, custom.light, "沒有 dark 就與 light 共用（與內建 OLED 規則一致）")
    }

    func testUnknownKeysAreIgnoredButBadValuesAreRejected() throws {
        let native = try loadBuiltin("native")
        _ = try Theme.load(from: Data(#"""
        { "schemaVersion": 1, "id": "a", "name": "a", "light": { "futureColor": "#123456" } }
        """#.utf8), fallback: native)

        XCTAssertThrowsError(try Theme.load(from: Data(#"""
        { "schemaVersion": 1, "id": "a", "name": "a", "light": { "keyText": "blue" } }
        """#.utf8), fallback: native)) {
            XCTAssertEqual($0 as? ThemeError, .invalidColor(key: "keyText", value: "blue"))
        }
    }

    func testBaseLessThemeMustDefineEveryColor() {
        XCTAssertThrowsError(try Theme.load(from: Data(#"""
        { "schemaVersion": 1, "id": "a", "name": "a", "light": { "keyText": "#000000" } }
        """#.utf8))) {
            XCTAssertEqual($0 as? ThemeError, .missingColor("keyboardBackground"))
        }
    }

    func testSchemaAndIDValidation() {
        XCTAssertThrowsError(try Theme.load(from: Data(#"{ "schemaVersion": 5, "id": "a", "name": "a", "light": {} }"#.utf8))) {
            XCTAssertEqual($0 as? ThemeError, .unsupportedSchema(5))
        }
        XCTAssertThrowsError(try Theme.load(from: Data(#"{ "schemaVersion": 1, "id": "", "name": "a", "light": {} }"#.utf8))) {
            XCTAssertEqual($0 as? ThemeError, .emptyID)
        }
    }

    func testMetricsAreClamped() {
        let extreme = ThemeMetrics(cornerRadiusScale: 99, fontScale: 0.1, spacingScale: -3, keyBorderWidth: 50)
        XCTAssertEqual(extreme.cornerRadiusScale, 2)
        XCTAssertEqual(extreme.fontScale, 0.8, accuracy: 0.0001)
        XCTAssertEqual(extreme.spacingScale, 0.5, accuracy: 0.0001)
        XCTAssertEqual(extreme.keyBorderWidth, 4)
    }

    // MARK: - 深淺色決定（FR-T03、U23）

    func testAppearanceFollowsSystemByDefault() {
        XCTAssertFalse(ThemeAppearance.isDark(setting: .system, systemIsDark: false))
        XCTAssertTrue(ThemeAppearance.isDark(setting: .system, systemIsDark: true))
    }

    func testFixedSettingsIgnoreSystem() {
        XCTAssertFalse(ThemeAppearance.isDark(setting: .light, systemIsDark: true))
        XCTAssertTrue(ThemeAppearance.isDark(setting: .dark, systemIsDark: false))
    }

    func testHostKeyboardAppearanceWinsOverEverything() {
        XCTAssertTrue(ThemeAppearance.isDark(setting: .light, systemIsDark: false, host: .dark))
        XCTAssertFalse(ThemeAppearance.isDark(setting: .dark, systemIsDark: true, host: .light))
        XCTAssertTrue(ThemeAppearance.isDark(setting: .system, systemIsDark: true, host: .unspecified))
    }
}
