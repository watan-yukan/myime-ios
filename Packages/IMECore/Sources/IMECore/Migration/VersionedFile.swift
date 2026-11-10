import Foundation

/// 帶版本號的 JSON 檔案讀寫：載入時自動升級，並保護原檔（FR-D06）。
///
/// 日誌只記錄結果種類，**不記錄檔案內容**（內容可能含使用者輸入，NFR-06）。
public enum VersionedFile {
    public enum LoadResult {
        /// 檔案不存在（首次使用，呼叫端用預設值）。
        case missing
        /// 已是目前版本。
        case loaded(JSONObject)
        /// 已升級並寫回；升級前的原檔備份在 `backup`。
        case migrated(JSONObject, backup: URL)
        /// 檔案比 App 新：可讀、**不可寫**。
        case readOnlyNewer(JSONObject, version: Int)
        /// 升級失敗：原檔完全沒動，呼叫端用預設值並提示可從備份還原。
        case migrationFailed(Error)
        /// 不是合法 JSON 物件：原檔已改名保留（`movedTo`），呼叫端用預設值。
        case corrupt(movedTo: URL?)
    }

    public static func load(
        from url: URL,
        migrator: JSONMigrator,
        fileManager: FileManager = .default
    ) -> LoadResult {
        guard fileManager.fileExists(atPath: url.path) else { return .missing }

        let data: Data
        do { data = try Data(contentsOf: url) } catch { return .migrationFailed(error) }

        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? JSONObject else {
            return .corrupt(movedTo: quarantine(url, fileManager: fileManager))
        }

        do {
            switch try migrator.migrate(object) {
            case .current(let current):
                return .loaded(current)
            case .newer(let newer, let version):
                return .readOnlyNewer(newer, version: version)
            case .migrated(let migrated, let from):
                // 先備份原檔，再原子性寫入新內容；任何一步失敗，原檔都不會被改動
                let backup = url.appendingPathExtension("v\(from).bak")
                if fileManager.fileExists(atPath: backup.path) { try fileManager.removeItem(at: backup) }
                try fileManager.copyItem(at: url, to: backup)
                try save(migrated, to: url)
                return .migrated(migrated, backup: backup)
            }
        } catch {
            return .migrationFailed(error)
        }
    }

    /// 以「暫存檔 → 原子性取代」寫入，避免 App 與鍵盤同時寫入造成損毀。
    public static func save(_ object: JSONObject, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    /// 把壞掉的檔案改名為 `.corrupt`（已存在時加上編號，不覆蓋先前保留的檔案）。
    private static func quarantine(_ url: URL, fileManager: FileManager) -> URL? {
        var candidate = url.appendingPathExtension("corrupt")
        var number = 1
        while fileManager.fileExists(atPath: candidate.path) {
            number += 1
            candidate = url.appendingPathExtension("corrupt\(number)")
        }
        do {
            try fileManager.moveItem(at: url, to: candidate)
            return candidate
        } catch {
            return nil
        }
    }
}
