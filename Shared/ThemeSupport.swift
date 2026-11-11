import UIKit
import IMECore

extension RGBAColor {
    var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

/// 內建主題的載入（主題檔在 bundle 內，App 與鍵盤擴充共用）。
enum ThemeCatalog {
    static let builtinIDs = ["native", "morandi", "high-contrast", "oled"]

    private static var cache: [String: Theme] = [:]

    /// 依 id 取得主題；找不到時退回「原生」，絕不讓鍵盤因為主題壞掉而無法使用。
    static func theme(id: String, bundle: Bundle = .main) -> Theme {
        if let cached = cache[id] { return cached }
        let loaded = load(id, bundle: bundle)
            ?? (id == "native" ? nil : load("native", bundle: bundle))
            ?? BuiltinThemes.native()
        cache[id] = loaded
        return loaded
    }

    static var all: [Theme] {
        all(bundle: .main)
    }

    static func all(bundle: Bundle) -> [Theme] {
        builtinIDs.map { theme(id: $0, bundle: bundle) }
    }

    private static func load(_ id: String, bundle: Bundle) -> Theme? {
        guard let url = bundle.url(forResource: id, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? Theme.load(from: data)
    }
}

/// 鍵盤版面檔的載入。
enum LayoutCatalog {
    static func iphone(bundle: Bundle = .main) -> KeyboardLayoutFile? {
        load("iphone", bundle: bundle)
    }

    static func ipad(bundle: Bundle = .main) -> KeyboardLayoutFile? {
        load("ipad", bundle: bundle)
    }

    /// 依裝置取得版面；iPad 版面檔缺少時退回 iPhone 版面，鍵盤仍可使用。
    static func layout(isPad: Bool, bundle: Bundle = .main) -> KeyboardLayoutFile? {
        isPad ? (ipad(bundle: bundle) ?? iphone(bundle: bundle)) : iphone(bundle: bundle)
    }

    private static func load(_ name: String, bundle: Bundle) -> KeyboardLayoutFile? {
        guard let url = bundle.url(forResource: name, withExtension: "json") else { return nil }
        return try? KeyboardLayoutFile.load(contentsOf: url)
    }
}
