import Foundation

/// 備份檔（docs/06_資料格式.md 第 5 章，FR-D04、D05）。
///
/// **不含碼表**（授權因素，R-LIU-1），只有提示要重新匯入哪個檔；
/// 也不含沒釘選的剪貼簿（可能有敏感內容）。
public struct BackupFile: Codable, Equatable {
    public static let currentSchemaVersion = 1
    public static let appName = "MyIME"

    public struct TableHint: Codable, Equatable {
        public var name: String
        public var sourceFileName: String
        public var importedAt: Date

        public init(name: String, sourceFileName: String, importedAt: Date) {
            self.name = name
            self.sourceFileName = sourceFileName
            self.importedAt = importedAt
        }
    }

    public var schemaVersion: Int
    public var app: String
    public var appVersion: String
    public var createdAt: Date
    public var settings: KeyboardSettings
    public var phrases: [PhraseRecord]
    public var tableHint: TableHint?

    public init(
        appVersion: String, createdAt: Date, settings: KeyboardSettings,
        phrases: [PhraseRecord], tableHint: TableHint? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.app = Self.appName
        self.appVersion = appVersion
        self.createdAt = createdAt
        self.settings = settings
        self.phrases = phrases
        self.tableHint = tableHint
    }
}

public enum BackupError: Error, Equatable {
    /// 不是 MyIME 的備份檔。
    case notABackup
    /// 備份檔比這版 App 新。
    case newerVersion(Int)
}

/// 還原時逐區段驗證：某一區段壞了就略過該區段並提示，不影響其他區段（FR-D06）。
public struct RestoreResult: Equatable {
    public var settings: KeyboardSettings?
    public var phrases: [PhraseRecord]?
    public var tableHint: BackupFile.TableHint?
    public var createdAt: Date?
    public var appVersion: String
    /// 無法讀取而略過的區段名稱。
    public var skippedSections: [String]
}

public enum BackupCodec {
    private static let prefix = "MyIME-backup-"
    private static let suffix = ".json"

    public static func encode(_ file: BackupFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }

    public static func restore(from data: Data) throws -> RestoreResult {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? JSONObject,
              root["app"] as? String == BackupFile.appName,
              let version = root["schemaVersion"] as? Int else {
            throw BackupError.notABackup
        }
        guard version <= BackupFile.currentSchemaVersion else { throw BackupError.newerVersion(version) }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var skipped: [String] = []

        func section<T: Decodable>(_ key: String, as type: T.Type) -> T? {
            guard let value = root[key] else { return nil }
            guard JSONSerialization.isValidJSONObject(value),
                  let bytes = try? JSONSerialization.data(withJSONObject: value),
                  let decoded = try? decoder.decode(type, from: bytes) else {
                skipped.append(key)
                return nil
            }
            return decoded
        }

        let settings = section("settings", as: KeyboardSettings.self)
        let phrases = section("phrases", as: [PhraseRecord].self)
        let hint = section("tableHint", as: BackupFile.TableHint.self)
        let created = (root["createdAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }

        return RestoreResult(
            settings: settings, phrases: phrases, tableHint: hint, createdAt: created,
            appVersion: root["appVersion"] as? String ?? "", skippedSections: skipped)
    }

    /// `MyIME-backup-20261110-083000.json`（UTC，檔名排序即時間排序）。
    public static func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return prefix + formatter.string(from: date) + suffix
    }

    public static func isBackupFileName(_ name: String) -> Bool {
        name.hasPrefix(prefix) && name.hasSuffix(suffix)
    }

    /// 只保留最新的 `keep` 份，回傳要刪除的檔名；不是備份檔名的檔案一律不動。
    public static func filesToDelete(existing: [String], keep: Int) -> [String] {
        let backups = existing.filter(isBackupFileName).sorted(by: >)
        return Array(backups.dropFirst(max(keep, 1)))
    }
}
