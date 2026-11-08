import SwiftUI
import UniformTypeIdentifiers

/// Spike 主 App：啟用說明、狀態、共用資料寫入、碼表匯入、重簽資料保留檢查、測試輸入框。
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var containerText = ""
    @State private var heartbeatText = ""
    @State private var pingText = "尚未寫入"
    @State private var tableText = "尚未匯入"
    @State private var groupMarkerText = ""
    @State private var localMarkerText = ""
    @State private var markersChecked = false
    @State private var isImporting = false
    @State private var testInput = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("啟用步驟") {
                    Text("1. 設定 → 一般 → 鍵盤 → 鍵盤 → 新增鍵盤 → MyIME")
                    Text("2. 點「MyIME」→ 開啟「允許完整取用」")
                    Text("3. 保留 Apple 內建鍵盤，作為簽章到期時的備援")
                }

                Section("狀態") {
                    LabeledContent("共用容器", value: containerText)
                    LabeledContent("鍵盤回報", value: heartbeatText)
                }

                Section {
                    Button("寫入測試資料", action: writePing)
                    Text(pingText)
                } header: {
                    Text("0.9 共用資料")
                } footer: {
                    Text("寫入後到任一 App 叫出 MyIME 鍵盤，鍵盤上方應顯示「App 寫入 時間」。")
                }

                Section {
                    Button("從「檔案」匯入 .cin 碼表") { isImporting = true }
                    Text(tableText)
                } header: {
                    Text("0.11 碼表匯入")
                } footer: {
                    Text("碼表只存在這台裝置上，不會上傳。匯入後鍵盤上方應顯示碼表名稱。")
                }

                Section {
                    LabeledContent("共用容器", value: groupMarkerText)
                    LabeledContent("App 自身", value: localMarkerText)
                } header: {
                    Text("0.16 重簽資料保留")
                } footer: {
                    Text("記下 ID。重簽重裝後若顯示「保留中」且 ID 相同，代表資料有保留。")
                }

                Section("測試輸入") {
                    TextField("切到 MyIME 鍵盤在這裡試打", text: $testInput, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("版本") {
                    Text(versionText)
                }
            }
            .navigationTitle("MyIME Spike")
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.item]) { result in
                handleImport(result)
            }
            .onAppear(perform: refresh)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refresh() }
            }
        }
    }

    // MARK: - Actions

    private func refresh() {
        containerText = SharedStorage.containerURL == nil ? "❌ 無法使用（App Group 未生效）" : "✅ 可使用"
        heartbeatText = readHeartbeat()
        tableText = readTableStatus()
        // 每次啟動只檢查一次，避免首次建立後立刻又顯示成「保留中」
        if !markersChecked {
            groupMarkerText = checkMarker(at: SharedStorage.url(SharedStorage.FileName.marker))
            localMarkerText = checkMarker(at: localMarkerURL)
            markersChecked = true
        }
    }

    private func writePing() {
        do {
            let now = Date()
            try SharedStorage.write(SpikePing(writtenAt: now), to: SharedStorage.FileName.ping)
            pingText = "✅ 已寫入 \(now.formatted(date: .omitted, time: .standard))"
        } catch {
            pingText = "❌ 寫入失敗：\(error.localizedDescription)"
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let sourceURL):
            let didAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didAccess { sourceURL.stopAccessingSecurityScopedResource() }
            }
            do {
                guard let destination = SharedStorage.url(SharedStorage.FileName.importedTable) else {
                    throw StorageError.containerUnavailable
                }
                let fileManager = FileManager.default
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.copyItem(at: sourceURL, to: destination)
                tableText = readTableStatus()
            } catch {
                tableText = "❌ 匯入失敗：\(error.localizedDescription)"
            }
        case .failure(let error):
            tableText = "❌ 選取失敗：\(error.localizedDescription)"
        }
    }

    // MARK: - Status helpers

    private func readHeartbeat() -> String {
        guard let heartbeat = try? SharedStorage.read(
            KeyboardHeartbeat.self, from: SharedStorage.FileName.heartbeat) else {
            return "尚無回報（未啟用鍵盤或未開完整取用）"
        }
        let access = heartbeat.hasFullAccess ? "完整取用已開" : "完整取用未開"
        return "\(access)，\(heartbeat.lastSeen.formatted(date: .abbreviated, time: .shortened))"
    }

    private func readTableStatus() -> String {
        guard let url = SharedStorage.url(SharedStorage.FileName.importedTable),
              FileManager.default.fileExists(atPath: url.path) else {
            return "尚未匯入"
        }
        do {
            let header = try CinHeaderReader.read(url: url)
            let selkey = header.selkey.map { "，選字鍵 \($0)" } ?? ""
            return "✅ \(header.displayName)（\(header.encoding)，\(header.byteSize / 1024) KB\(selkey)）"
        } catch {
            return "❌ 讀取失敗：\(error.localizedDescription)"
        }
    }

    private var localMarkerURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(SharedStorage.FileName.marker)
    }

    /// 已存在 → 顯示「保留中」；不存在 → 建立新的並顯示「首次建立」。
    private func checkMarker(at url: URL?) -> String {
        guard let url else { return "❌ 位置無法使用" }
        if let marker = try? SharedStorage.read(PersistMarker.self, fromURL: url) {
            return "保留中 \(shortID(marker.id))（\(marker.createdAt.formatted(date: .abbreviated, time: .shortened))）"
        }
        let marker = PersistMarker(id: UUID(), createdAt: Date())
        do {
            try SharedStorage.write(marker, toURL: url)
            return "首次建立 \(shortID(marker.id))"
        } catch {
            return "❌ 建立失敗：\(error.localizedDescription)"
        }
    }

    private func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version)（build \(build)）"
    }
}
