import Foundation

/// 從自身 bundle 內的 embedded.mobileprovision 讀出「實際簽進去」的資訊。
///
/// 側載工具（Sideloadly 等）重簽時，可能改寫 Bundle ID 或 App Group ID，
/// 寫死的 `AppConstants.appGroupID` 就會對不上。這裡改為以描述檔為準。
/// 描述檔只含 Team ID、Bundle ID、權限，不含使用者輸入；可安全顯示。
struct SigningInfo {
    var teamID: String?
    var applicationIdentifier: String?
    var appGroups: [String]
    var expirationDate: Date?

    static let current: SigningInfo? = load(from: Bundle.main)

    static func load(from bundle: Bundle) -> SigningInfo? {
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let plist = extractPlist(from: data) else {
            return nil
        }
        let entitlements = plist["Entitlements"] as? [String: Any] ?? [:]
        return SigningInfo(
            teamID: (plist["TeamIdentifier"] as? [String])?.first,
            applicationIdentifier: entitlements["application-identifier"] as? String,
            appGroups: entitlements["com.apple.security.application-groups"] as? [String] ?? [],
            expirationDate: plist["ExpirationDate"] as? Date
        )
    }

    /// 描述檔是 CMS 簽章包住的 XML plist，直接擷取 `<?xml ... </plist>` 這段解析即可。
    private static func extractPlist(from data: Data) -> [String: Any]? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else {
            return nil
        }
        let xml = data.subdata(in: start.lowerBound..<end.upperBound)
        return try? PropertyListSerialization.propertyList(from: xml, format: nil) as? [String: Any]
    }
}

enum AppGroupResolver {
    /// 優先使用原本設定的 ID；重簽後被改名時，改用描述檔裡含 myime 的群組，再退回第一個。
    static let resolvedID: String = {
        let groups = SigningInfo.current?.appGroups ?? []
        if groups.isEmpty || groups.contains(AppConstants.appGroupID) {
            return AppConstants.appGroupID
        }
        return groups.first { $0.lowercased().contains("myime") } ?? groups[0]
    }()
}
