import Foundation

/// JSON 物件（設定、常用詞、剪貼簿、主題等使用者資料檔的最外層）。
public typealias JSONObject = [String: Any]

public enum MigrationError: Error, Equatable {
    /// 最外層沒有整數的 `schemaVersion`。
    case missingSchemaVersion
    /// 缺少從這個版本往上升級的步驟。
    case missingStep(from: Int)
}

/// 使用者資料格式升級（FR-D06，docs/06_資料格式.md 第 6 章）。
///
/// 每個步驟負責「版本 N → N + 1」，依序執行；升級只在記憶體中進行，不碰檔案。
public struct JSONMigrator {
    public typealias Step = (inout JSONObject) throws -> Void

    public enum Outcome {
        /// 已是目前版本。
        case current(JSONObject)
        /// 由舊版升級而來。
        case migrated(JSONObject, from: Int)
        /// 檔案比這個 App 新：只能讀、不可寫（避免降版把新欄位洗掉）。
        case newer(JSONObject, version: Int)
    }

    public let currentVersion: Int
    private let steps: [Int: Step]

    /// - Parameter steps: key 是「來源版本」，執行後 `schemaVersion` 自動加 1。
    public init(currentVersion: Int, steps: [Int: Step] = [:]) {
        self.currentVersion = currentVersion
        self.steps = steps
    }

    public func migrate(_ object: JSONObject) throws -> Outcome {
        guard let version = object["schemaVersion"] as? Int else {
            throw MigrationError.missingSchemaVersion
        }
        if version > currentVersion { return .newer(object, version: version) }
        if version == currentVersion { return .current(object) }

        var result = object
        for from in version..<currentVersion {
            guard let step = steps[from] else { throw MigrationError.missingStep(from: from) }
            try step(&result)
            result["schemaVersion"] = from + 1
        }
        return .migrated(result, from: version)
    }
}
