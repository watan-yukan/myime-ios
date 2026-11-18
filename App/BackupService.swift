import SwiftUI
import IMECore
import OSLog

/// 備份與還原（FR-D04、D05）：手動匯出入，以及每次開啟 App 時自動備份到「檔案」App 中選定的資料夾。
///
/// 備份**不含碼表**（授權因素，R-LIU-1）。日誌只記事件，不記錄備份內容（NFR-06）。
@MainActor
final class BackupService: ObservableObject {
    @Published private(set) var folderName: String?
    @Published private(set) var backups: [String] = []
    @Published var message: String?

    private let logger = Logger(subsystem: AppConstants.logSubsystem, category: "backup")
    private let bookmarkKey = "autoBackupFolderBookmark"
    private let lastRunKey = "autoBackupLastRun"
    /// 太頻繁開啟 App 時不重複備份。
    private let minimumInterval: TimeInterval = 10 * 60

    private var defaults: UserDefaults { .standard }

    // MARK: - 資料夾

    /// 使用者在「檔案」選了資料夾：存成書籤，之後才能再度存取。
    func chooseFolder(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try url.bookmarkData()
            defaults.set(bookmark, forKey: bookmarkKey)
            folderName = url.lastPathComponent
            refreshList()
            message = "已選擇備份資料夾：\(url.lastPathComponent)"
        } catch {
            message = "無法使用這個資料夾：\(error.localizedDescription)"
        }
    }

    func clearFolder() {
        defaults.removeObject(forKey: bookmarkKey)
        folderName = nil
        backups = []
    }

    private func withFolder<T>(_ body: (URL) throws -> T) -> T? {
        guard let bookmark = defaults.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale) else { return nil }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        if stale, let fresh = try? url.bookmarkData() { defaults.set(fresh, forKey: bookmarkKey) }
        return try? body(url)
    }

    func refreshList() {
        guard defaults.data(forKey: bookmarkKey) != nil else {
            folderName = nil
            backups = []
            return
        }
        let result: (name: String, files: [String])? = withFolder { folder in
            let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            return (folder.lastPathComponent, names.filter(BackupCodec.isBackupFileName).sorted(by: >))
        }
        folderName = result?.name
        backups = result?.files ?? []
    }

    // MARK: - 建立備份

    func makeBackupFile(from model: AppModel) -> BackupFile {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let hint = model.tableMeta.map {
            BackupFile.TableHint(name: $0.name, sourceFileName: $0.sourceFileName, importedAt: $0.importedAt)
        }
        return BackupFile(
            appVersion: version, createdAt: Date(), settings: model.settings,
            phrases: model.allPhraseRecords, tableHint: hint)
    }

    /// 寫一份到暫存資料夾，供分享（匯出）。
    func exportFile(from model: AppModel) throws -> URL {
        let data = try BackupCodec.encode(makeBackupFile(from: model))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(BackupCodec.fileName(for: Date()))
        try data.write(to: url, options: .atomic)
        return url
    }

    /// 立即備份到選定的資料夾，並依設定保留最近 N 份。
    @discardableResult
    func backupNow(model: AppModel) -> Bool {
        guard defaults.data(forKey: bookmarkKey) != nil else {
            message = "請先選擇備份資料夾"
            return false
        }
        let keep = model.settings.backup.keep
        let file = makeBackupFile(from: model)
        let written: Bool? = withFolder { folder in
            let data = try BackupCodec.encode(file)
            try data.write(to: folder.appendingPathComponent(BackupCodec.fileName(for: file.createdAt)), options: .atomic)
            let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            for name in BackupCodec.filesToDelete(existing: names, keep: keep) {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
            }
            return true
        }
        defaults.set(Date(), forKey: lastRunKey)
        refreshList()
        if written == true {
            message = "已備份到「\(folderName ?? "資料夾")」"
            logger.info("backup written")
            return true
        }
        message = "備份失敗：無法寫入資料夾，請重新選擇。"
        return false
    }

    /// 每次開啟 App 時呼叫：有開啟自動備份、選好資料夾、距離上次夠久才會備份。
    func runAutoBackupIfNeeded(model: AppModel) {
        guard model.settings.backup.enabled, defaults.data(forKey: bookmarkKey) != nil else { return }
        if let last = defaults.object(forKey: lastRunKey) as? Date, Date().timeIntervalSince(last) < minimumInterval { return }
        // 設定尚未載入完成時不備份，避免把預設值備份成最新的一份
        guard model.containerAvailable else { return }
        backupNow(model: model)
        message = nil
    }

    // MARK: - 還原

    func readBackup(from url: URL) throws -> RestoreResult {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        return try BackupCodec.restore(from: Data(contentsOf: url))
    }

    func readBackup(named name: String) -> RestoreResult? {
        withFolder { folder in
            try BackupCodec.restore(from: Data(contentsOf: folder.appendingPathComponent(name)))
        }
    }

    /// 套用還原結果；回傳給使用者看的摘要。
    func apply(_ result: RestoreResult, to model: AppModel) -> String {
        var restored: [String] = []
        if let settings = result.settings {
            model.settings = settings
            model.saveSettings()
            restored.append("設定")
        }
        if let phrases = result.phrases {
            model.replacePhrases(with: phrases)
            restored.append("常用詞")
        }
        var lines = [restored.isEmpty ? "沒有可還原的內容。" : "已還原：" + restored.joined(separator: "、") + "。"]
        if !result.skippedSections.isEmpty {
            lines.append("無法讀取而略過：" + result.skippedSections.joined(separator: "、") + "。")
        }
        if let hint = result.tableHint {
            lines.append("碼表不在備份內，請重新匯入「\(hint.name)」（\(hint.sourceFileName)）。")
        }
        return lines.joined(separator: "\n")
    }
}

/// 系統分享面板（匯出備份用）。
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
