import Foundation

/// App 與鍵盤擴充共用的常數。Bundle ID / App Group ID 開始側載後不可再改。
enum AppConstants {
    static let appGroupID = "group.com.watanyukan.myime"
    static let logSubsystem = "com.watanyukan.myime"
}

/// 鍵盤每次出現時回報給主 App 的狀態（FR-A11 狀態面板的雛形）。
struct KeyboardHeartbeat: Codable {
    var hasFullAccess: Bool
    var lastSeen: Date
}

/// 主 App 寫入、鍵盤讀取，用來驗證 App Group 共用（Spike 0.9）。
struct SpikePing: Codable {
    var writtenAt: Date
}

/// 首次啟動時建立，重簽後檢查是否仍在，用來驗證資料保留（Spike 0.16）。
struct PersistMarker: Codable {
    var id: UUID
    var createdAt: Date
}

enum StorageError: LocalizedError {
    case containerUnavailable

    var errorDescription: String? {
        switch self {
        case .containerUnavailable:
            return "App Group 共用容器無法使用"
        }
    }
}

/// App Group 共用容器的讀寫。只存設定與狀態，絕不存使用者輸入的文字（NFR-06）。
enum SharedStorage {
    enum FileName {
        static let heartbeat = "keyboard_heartbeat.json"
        static let ping = "spike_ping.json"
        static let marker = "persist_marker.json"
        static let importedTable = "imported_table.cin"
        static let settings = "settings.json"
        /// 碼表索引（鍵盤只讀，docs/06_資料格式.md 第 2 章）。
        static let tableIndex = "table.idx"
        /// 匯入碼表的名稱、筆數、匯入時間。
        static let tableMeta = "table_meta.json"
        /// 匯入的原始 .cin 副本：索引格式升版時用來重建；不進備份、不上傳（R-LIU-1）。
        static let tableSource = "table_source.cin"
        static let phrases = "phrases.json"
    }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroupResolver.resolvedID)
    }

    static func url(_ name: String) -> URL? {
        containerURL?.appendingPathComponent(name)
    }

    static func write<T: Encodable>(_ value: T, to name: String) throws {
        guard let url = url(name) else { throw StorageError.containerUnavailable }
        try write(value, toURL: url)
    }

    static func read<T: Decodable>(_ type: T.Type, from name: String) throws -> T {
        guard let url = url(name) else { throw StorageError.containerUnavailable }
        return try read(type, fromURL: url)
    }

    static func write<T: Encodable>(_ value: T, toURL url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    static func read<T: Decodable>(_ type: T.Type, fromURL url: URL) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(contentsOf: url))
    }
}
