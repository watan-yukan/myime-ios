import Foundation
import IMECore

/// 碼表索引的載入。
///
/// 鍵盤擴充有自己的容器：有「完整取用」時，把 App Group 內較新的索引複製過來，
/// 之後即使沒開完整取用也能打字（NFR-07）。
enum TableProvider {
    private static var cacheURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(SharedStorage.FileName.tableIndex)
    }

    /// 鍵盤用：載入索引（略過整檔 CRC，避免冷啟動掃過整個檔案，NFR-15）。
    static func loadForKeyboard(hasFullAccess: Bool) -> TableIndex? {
        let fileManager = FileManager.default
        guard let cache = cacheURL else { return nil }
        try? fileManager.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)

        if hasFullAccess, let shared = SharedStorage.url(SharedStorage.FileName.tableIndex),
           fileManager.fileExists(atPath: shared.path), needsCopy(from: shared, to: cache) {
            let temporary = cache.appendingPathExtension("tmp")
            try? fileManager.removeItem(at: temporary)
            if (try? fileManager.copyItem(at: shared, to: temporary)) != nil {
                _ = try? fileManager.replaceItemAt(cache, withItemAt: temporary)
            }
        }
        return try? TableIndex(contentsOf: cache, verifyChecksum: false)
    }

    /// 主 App 用：載入 App Group 內的索引並完整驗證檢查碼。
    static func loadForApp() -> TableIndex? {
        guard let url = SharedStorage.url(SharedStorage.FileName.tableIndex) else { return nil }
        return try? TableIndex(contentsOf: url)
    }

    private static func needsCopy(from source: URL, to destination: URL) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: destination.path) else { return true }
        let sourceInfo = try? fileManager.attributesOfItem(atPath: source.path)
        let destinationInfo = try? fileManager.attributesOfItem(atPath: destination.path)
        let sourceDate = sourceInfo?[.modificationDate] as? Date ?? .distantFuture
        let destinationDate = destinationInfo?[.modificationDate] as? Date ?? .distantPast
        let sourceSize = sourceInfo?[.size] as? NSNumber
        let destinationSize = destinationInfo?[.size] as? NSNumber
        // 快取是複製出來的，修改時間會比來源新；只有「來源之後又更新」或大小不同才需要重新複製
        return sourceDate > destinationDate || sourceSize != destinationSize
    }
}

/// 匯入的碼表摘要（`table_meta.json`），主 App 顯示用。
struct TableMeta: Codable, Equatable {
    var name: String
    var entryCount: Int
    var codeCount: Int
    var maxCodeLength: Int
    var encoding: String
    var importedAt: Date
    var sourceFileName: String
    /// 匯入時略過的格式錯誤行數。
    var skippedLines: Int
}

extension TableProvider {
    /// 鍵盤自己容器內索引的修改時間；用來判斷碼表是否被主 App 重新匯入。
    static var cacheStamp: Date? {
        guard let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(SharedStorage.FileName.tableIndex) else { return nil }
        return (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
