import SwiftUI
import IMECore

/// 碼表頁：從「檔案」匯入 `.cin`（FR-A03）。
///
/// 碼表只存在這台裝置上，不上傳、不進備份（R-LIU-1）。
struct TablePage: View {
    @EnvironmentObject private var model: AppModel
    @State private var showImporter = false
    @State private var confirmRemove = false

    var body: some View {
        NavigationStack {
            Form {
                currentSection
                importSection
                resultSection
                if model.tableMeta != nil {
                    Section {
                        Button("移除碼表", role: .destructive) { confirmRemove = true }
                    } footer: {
                        Text("移除後鍵盤無法輸入中文，直到重新匯入。你的原始 .cin 檔不受影響。")
                    }
                }
            }
            .navigationTitle("碼表")
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item]) { result in
                switch result {
                case .success(let url):
                    Task { await model.importTable(from: url) }
                case .failure(let error):
                    model.importState = .failed("選取失敗：\(error.localizedDescription)")
                }
            }
            .confirmationDialog("確定要移除碼表嗎？", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("移除碼表", role: .destructive) { model.removeTable() }
                Button("取消", role: .cancel) {}
            }
        }
    }

    private var currentSection: some View {
        Section("目前的碼表") {
            if let meta = model.tableMeta {
                LabeledContent("名稱", value: meta.name)
                LabeledContent("候選字", value: "\(meta.entryCount)")
                LabeledContent("字根數", value: "\(meta.codeCount)")
                LabeledContent("最長碼長", value: "\(meta.maxCodeLength)")
                LabeledContent("編碼", value: meta.encoding)
                LabeledContent("來源檔", value: meta.sourceFileName)
                LabeledContent("匯入時間", value: meta.importedAt.formatted(date: .abbreviated, time: .shortened))
                if meta.skippedLines > 0 {
                    LabeledContent("略過的格式錯誤行", value: "\(meta.skippedLines)")
                }
            } else {
                Text("尚未匯入")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var importSection: some View {
        Section {
            Button {
                showImporter = true
            } label: {
                Label("從「檔案」匯入 .cin 碼表", systemImage: "square.and.arrow.down")
            }
            .disabled(model.importState == .working)
        } footer: {
            Text("支援標準 .cin 格式（UTF-8 或 Big5）。匯入失敗時，原本的碼表不會被改動。")
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        switch model.importState {
        case .idle:
            EmptyView()
        case .working:
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("正在建立索引…")
                }
            }
        case .succeeded(let summary):
            Section("匯入完成") {
                StatusRow(title: summary.name, detail: "\(summary.entryCount) 個候選字，\(summary.codeCount) 個字根", level: .good)
                if summary.skippedLines > 0 {
                    StatusRow(title: "略過 \(summary.skippedLines) 行", detail: "這些行格式不正確，已略過，其餘內容正常匯入。", level: .warning)
                }
                if !summary.extraCodeKeys.isEmpty {
                    LabeledContent("特殊字根鍵", value: summary.extraCodeKeys)
                }
            }
        case .failed(let message):
            Section("匯入失敗") {
                StatusRow(title: "沒有匯入", detail: message, level: .bad)
            }
        }
    }
}
