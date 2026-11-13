import SwiftUI
import IMECore
import OSLog

/// 主 App 的狀態與資料操作：設定、碼表匯入、狀態面板、常用詞、備份。
/// 日誌只記事件與數量，不記錄碼表內容或使用者輸入（NFR-06）。
@MainActor
final class AppModel: ObservableObject {
    enum ImportState: Equatable {
        case idle
        case working
        case succeeded(ImportSummary)
        case failed(String)
    }

    private let logger = Logger(subsystem: AppConstants.logSubsystem, category: "app")

    @Published var settings = KeyboardSettings()
    @Published private(set) var settingsWritable = true
    @Published private(set) var tableMeta: TableMeta?
    @Published private(set) var heartbeat: KeyboardHeartbeat?
    @Published private(set) var containerAvailable = false
    @Published var importState = ImportState.idle
    @Published private(set) var phrases: [PhraseRecord] = []

    private var phraseStore = PhraseStore()
    private var phrasesWritable = true
    private var settingsLoaded = false

    // MARK: - 載入

    func refresh() {
        containerAvailable = SharedStorage.containerURL != nil
        loadSettings()
        loadTableMeta()
        loadHeartbeat()
        loadPhrases()
    }

    private func loadSettings() {
        guard let url = SharedStorage.url(SharedStorage.FileName.settings) else { return }
        let loaded = SettingsStore(url: url).load()
        settingsWritable = loaded.writable
        if loaded.settings != settings { settings = loaded.settings }
        settingsLoaded = true
    }

    func saveSettings() {
        guard settingsLoaded, settingsWritable,
              let url = SharedStorage.url(SharedStorage.FileName.settings) else { return }
        do {
            try SettingsStore(url: url).save(settings)
        } catch {
            logger.error("save settings failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadTableMeta() {
        tableMeta = try? SharedStorage.read(TableMeta.self, from: SharedStorage.FileName.tableMeta)
    }

    private func loadHeartbeat() {
        heartbeat = try? SharedStorage.read(KeyboardHeartbeat.self, from: SharedStorage.FileName.heartbeat)
    }

    // MARK: - 碼表匯入（FR-A03）

    /// 匯入 `.cin`：成功才覆蓋現有碼表，失敗時原本的碼表完全不動。
    func importTable(from url: URL) async {
        guard containerAvailable else {
            importState = .failed("共用容器無法使用，請確認 App 是用 AltStore 安裝的（App Group 需要簽章包含）。")
            return
        }
        importState = .working

        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            importState = .failed("讀不到這個檔案：\(error.localizedDescription)")
            return
        }
        let fileName = url.lastPathComponent

        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try TableImporter.build(from: data)
            }.value
            try writeTable(result, sourceData: data, fileName: fileName)
            loadTableMeta()
            importState = .succeeded(result.summary)
            logger.info("table imported, entries=\(result.summary.entryCount)")
        } catch let error as TableImportError {
            importState = .failed(Self.message(for: error))
        } catch {
            importState = .failed("匯入失敗：\(error.localizedDescription)")
        }
    }

    private func writeTable(_ result: ImportResult, sourceData: Data, fileName: String) throws {
        guard let indexURL = SharedStorage.url(SharedStorage.FileName.tableIndex),
              let sourceURL = SharedStorage.url(SharedStorage.FileName.tableSource) else {
            throw StorageError.containerUnavailable
        }
        try result.indexData.write(to: indexURL, options: .atomic)
        try sourceData.write(to: sourceURL, options: .atomic)  // 索引格式升版時用來重建；不進備份、不上傳
        let summary = result.summary
        let meta = TableMeta(
            name: summary.name, entryCount: summary.entryCount, codeCount: summary.codeCount,
            maxCodeLength: summary.maxCodeLength, encoding: summary.encoding, importedAt: Date(),
            sourceFileName: fileName, skippedLines: summary.skippedLines)
        try SharedStorage.write(meta, to: SharedStorage.FileName.tableMeta)
    }

    static func message(for error: TableImportError) -> String {
        switch error {
        case .tooLarge:
            return "這個檔案太大了，不像是輸入法碼表。"
        case .parse(.empty):
            return "這是一個空的檔案。"
        case .parse(.noCharDef):
            return "找不到 %chardef 區段，這不像是 .cin 碼表。"
        case .parse(.unsupportedEncoding):
            return "無法辨識檔案編碼，請先轉存成 UTF-8。"
        case .invalidResult:
            return "建立索引後驗證失敗，原本的碼表沒有被改動。請再試一次。"
        }
    }

    /// 移除碼表（含 .cin 副本與索引）。
    func removeTable() {
        for name in [SharedStorage.FileName.tableIndex, SharedStorage.FileName.tableSource, SharedStorage.FileName.tableMeta] {
            if let url = SharedStorage.url(name) { try? FileManager.default.removeItem(at: url) }
        }
        tableMeta = nil
        importState = .idle
    }

    // MARK: - 常用詞（FR-A06）

    private func loadPhrases() {
        guard let url = SharedStorage.url(SharedStorage.FileName.phrases) else { return }
        let loaded = PhraseFileStore(url: url).load()
        phrasesWritable = loaded.writable
        phraseStore = loaded.store
        phrases = phraseStore.sortedRecords()
    }

    func addPhrase(_ text: String) -> Bool {
        guard phrasesWritable else { return false }
        let added = phraseStore.add(manual: text.trimmingCharacters(in: .whitespacesAndNewlines))
        if added { commitPhraseChanges() }
        return added
    }

    func removePhrase(_ text: String) {
        guard phrasesWritable else { return }
        phraseStore.remove(text)
        commitPhraseChanges()
    }

    func clearLearnedPhrases() {
        guard phrasesWritable else { return }
        phraseStore.removeAllLearned()
        commitPhraseChanges()
    }

    private func commitPhraseChanges() {
        phrases = phraseStore.sortedRecords()
        guard let url = SharedStorage.url(SharedStorage.FileName.phrases) else { return }
        try? PhraseFileStore(url: url).save(phraseStore)
    }

    /// 備份用：目前所有常用詞記錄。
    var allPhraseRecords: [PhraseRecord] {
        phraseStore.sortedRecords()
    }

    /// 還原用：以備份的記錄取代目前的常用詞。
    func replacePhrases(with records: [PhraseRecord]) {
        phraseStore = PhraseStore(records: records)
        phrasesWritable = true
        commitPhraseChanges()
    }

    // MARK: - 狀態面板（FR-A11）

    var keyboardSeen: Bool {
        guard let heartbeat else { return false }
        return Date().timeIntervalSince(heartbeat.lastSeen) < 60 * 60 * 24 * 30
    }

    /// 簽章到期日（免費 Apple ID 為 7 天）。
    var signingExpiry: Date? {
        SigningInfo.current?.expirationDate
    }

    var daysUntilExpiry: Int? {
        guard let expiry = signingExpiry else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: expiry).day
    }
}
