import SwiftUI
import UniformTypeIdentifiers
import IMECore

/// 更多：常用詞管理、備份與還原、關於。
struct MorePage: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    PhrasesPage()
                } label: {
                    Label("常用詞", systemImage: "text.quote")
                }
                NavigationLink {
                    BackupPage()
                } label: {
                    Label("備份與還原", systemImage: "externaldrive.badge.icloud")
                }
                NavigationLink {
                    AboutPage()
                } label: {
                    Label("關於與授權", systemImage: "info.circle")
                }
            }
            .navigationTitle("更多")
        }
    }
}

/// 常用詞管理（FR-A06）：檢視、刪除、清空學來的詞、手動新增。
struct PhrasesPage: View {
    @EnvironmentObject private var model: AppModel
    @State private var newPhrase = ""
    @State private var showInvalid = false
    @State private var confirmClear = false

    var body: some View {
        List {
            Section {
                Toggle("記錄常用詞", isOn: $model.settings.phraseLearning)
            } footer: {
                Text("常用詞只用來建議你打完一個字後常接的詞，不會改變碼表的候選字順序，也不會離開這台裝置。")
            }

            Section {
                HStack {
                    TextField("例如：嘸蝦米", text: $newPhrase)
                        .submitLabel(.done)
                        .onSubmit(add)
                    Button("新增", action: add)
                        .disabled(newPhrase.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("手動新增")
            } footer: {
                Text("至少兩個中文字。手動新增的詞會優先建議，也不會被自動淘汰。")
            }

            Section("已記錄（\(model.phrases.count)）") {
                if model.phrases.isEmpty {
                    Text("還沒有常用詞。多打一些字之後，常接的詞會出現在這裡。")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.phrases, id: \.text) { record in
                    HStack {
                        Text(record.text)
                        Spacer()
                        if record.source == .manual {
                            Text("手動").font(.caption).foregroundStyle(.tint)
                        } else {
                            Text("\(record.count) 次").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("刪除", role: .destructive) { model.removePhrase(record.text) }
                    }
                }
            }

            if model.phrases.contains(where: { $0.source == .learned }) {
                Section {
                    Button("清除學來的詞", role: .destructive) { confirmClear = true }
                } footer: {
                    Text("手動新增的詞會保留。")
                }
            }
        }
        .navigationTitle("常用詞")
        .onChange(of: model.settings) { _, _ in model.saveSettings() }
        .alert("這不是有效的詞", isPresented: $showInvalid) {
            Button("好") {}
        } message: {
            Text("請輸入至少兩個中文字。")
        }
        .confirmationDialog("清除所有學來的詞？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清除", role: .destructive) { model.clearLearnedPhrases() }
            Button("取消", role: .cancel) {}
        }
    }

    private func add() {
        let text = newPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if model.addPhrase(text) {
            newPhrase = ""
        } else {
            showInvalid = true
        }
    }
}

/// 備份與還原（FR-A12、D04、D05）。
struct BackupPage: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var backup: BackupService

    @State private var showFolderPicker = false
    @State private var showRestorePicker = false
    @State private var shareURL: URL?
    @State private var pendingRestore: RestoreResult?
    @State private var resultMessage: String?

    var body: some View {
        Form {
            Section {
                Toggle("開啟 App 時自動備份", isOn: $model.settings.backup.enabled)
                LabeledContent("備份資料夾", value: backup.folderName ?? "尚未選擇")
                Button("選擇資料夾…") { showFolderPicker = true }
                if backup.folderName != nil {
                    Button("立即備份") { backup.backupNow(model: model) }
                    Button("不再使用這個資料夾", role: .destructive) { backup.clearFolder() }
                }
                Stepper("保留最近 \(model.settings.backup.keep) 份", value: $model.settings.backup.keep, in: 1...30)
            } header: {
                Text("自動備份")
            } footer: {
                Text("備份存在你在「檔案」App 選的資料夾（例如 iCloud Drive），重裝後可以一鍵還原。備份內容是設定與常用詞，**不含碼表**，也不含剪貼簿。")
            }

            if !backup.backups.isEmpty {
                Section("資料夾內的備份") {
                    ForEach(backup.backups, id: \.self) { name in
                        Button {
                            if let result = backup.readBackup(named: name) {
                                pendingRestore = result
                            } else {
                                resultMessage = "無法讀取這份備份。"
                            }
                        } label: {
                            Text(name).font(.footnote)
                        }
                    }
                }
            }

            Section {
                Button("匯出備份檔…") {
                    do {
                        shareURL = try backup.exportFile(from: model)
                    } catch {
                        resultMessage = "匯出失敗：\(error.localizedDescription)"
                    }
                }
                Button("從檔案還原…") { showRestorePicker = true }
            } header: {
                Text("手動")
            } footer: {
                Text("還原會用備份取代目前的設定與常用詞。")
            }
        }
        .navigationTitle("備份與還原")
        .onChange(of: model.settings) { _, _ in model.saveSettings() }
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { backup.chooseFolder(url) }
        }
        .fileImporter(isPresented: $showRestorePicker, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                do {
                    pendingRestore = try backup.readBackup(from: url)
                } catch BackupError.notABackup {
                    resultMessage = "這不是 MyIME 的備份檔。"
                } catch BackupError.newerVersion {
                    resultMessage = "這份備份來自更新版本的 MyIME，請先更新 App。"
                } catch {
                    resultMessage = "無法讀取：\(error.localizedDescription)"
                }
            case .failure(let error):
                resultMessage = "選取失敗：\(error.localizedDescription)"
            }
        }
        .sheet(isPresented: Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } })) {
            if let shareURL { ShareSheet(url: shareURL) }
        }
        .confirmationDialog(
            "還原會取代目前的設定與常用詞", isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
            titleVisibility: .visible
        ) {
            Button("還原", role: .destructive) {
                if let result = pendingRestore { resultMessage = backup.apply(result, to: model) }
                pendingRestore = nil
            }
            Button("取消", role: .cancel) { pendingRestore = nil }
        }
        .alert("備份與還原", isPresented: Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })) {
            Button("好") {}
        } message: {
            Text(resultMessage ?? "")
        }
        .onChange(of: backup.message) { _, message in
            if let message { resultMessage = message; backup.message = nil }
        }
    }
}

/// 關於與授權（FR-A08）。
struct AboutPage: View {
    var body: some View {
        List {
            Section("MyIME") {
                Text("個人用的 iOS / iPadOS 形碼輸入法，相容 .cin 碼表。")
                Text("版權所有 © 2026 watan_yukan。保留一切權利（All Rights Reserved）。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("本 App 與其原始碼**不包含任何商業輸入法碼表**。碼表需由你自行合法取得，並由你在「碼表」頁匯入；匯入的碼表只存在這台裝置上，不會上傳，也不會放進備份。")
            } header: {
                Text("關於碼表")
            }

            Section {
                Text("MyIME 不連網，不收集你輸入的內容。日誌只記錄事件與數量，絕不記錄你打的字或剪貼簿內容。")
            } header: {
                Text("隱私")
            }

            Section {
                Text("目前沒有隨 App 內建的第三方資料。日後加入的開源資料（如注音讀音、詞庫）會在這裡列出授權聲明。")
                    .foregroundStyle(.secondary)
            } header: {
                Text("第三方授權")
            }
        }
        .navigationTitle("關於與授權")
    }
}
