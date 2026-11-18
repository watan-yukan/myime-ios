import SwiftUI
import IMECore

/// 首頁：啟用引導、狀態面板（FR-A01、A11）、測試輸入框（FR-A02）。
struct HomePage: View {
    @EnvironmentObject private var model: AppModel
    @State private var testText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("啟用步驟") {
                    Text("1. 設定 → 一般 → 鍵盤 → 鍵盤 → 新增鍵盤 → MyIME")
                    Text("2. 點「MyIME」→ 開啟「允許完整取用」（震動與碼表快取需要）")
                    Text("3. 保留 Apple 內建鍵盤，簽章到期時才有備援")
                    Button("開啟 iOS 設定") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }

                Section("狀態") {
                    keyboardRow
                    fullAccessRow
                    tableRow
                    signingRow
                    containerRow
                }

                Section {
                    TextField("切換到 MyIME 鍵盤，在這裡試打", text: $testText, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("測試輸入")
                } footer: {
                    Text("先到「碼表」匯入你的 .cin，鍵盤才能打中文。")
                }

                Section("版本") {
                    Text(versionText)
                }
            }
            .navigationTitle("MyIME")
        }
    }

    // MARK: - 狀態列

    private var keyboardRow: some View {
        if let heartbeat = model.heartbeat {
            return StatusRow(
                title: "鍵盤", detail: "最近使用：\(heartbeat.lastSeen.formatted(.relative(presentation: .named)))",
                level: model.keyboardSeen ? .good : .warning)
        }
        return StatusRow(title: "鍵盤", detail: "尚未偵測到。請依上面的步驟新增鍵盤，並切換到 MyIME 打幾個字。", level: .warning)
    }

    private var fullAccessRow: some View {
        guard let heartbeat = model.heartbeat else {
            return StatusRow(title: "完整取用", detail: "鍵盤使用後才會知道", level: .neutral)
        }
        return heartbeat.hasFullAccess
            ? StatusRow(title: "完整取用", detail: "已開啟", level: .good)
            : StatusRow(title: "完整取用", detail: "未開啟：沒有按鍵震動，也無法更新碼表快取", level: .warning)
    }

    private var tableRow: some View {
        if let meta = model.tableMeta {
            return StatusRow(
                title: "碼表", detail: "\(meta.name)，\(meta.entryCount) 字，匯入於 \(meta.importedAt.formatted(date: .abbreviated, time: .omitted))",
                level: .good)
        }
        return StatusRow(title: "碼表", detail: "尚未匯入。請到「碼表」頁匯入 .cin 檔。", level: .bad)
    }

    private var signingRow: some View {
        guard let expiry = model.signingExpiry, let days = model.daysUntilExpiry else {
            return StatusRow(title: "簽章到期", detail: "讀不到簽章資訊", level: .neutral)
        }
        let date = expiry.formatted(date: .abbreviated, time: .shortened)
        if days < 0 {
            return StatusRow(title: "簽章到期", detail: "已過期（\(date)）。請用 AltStore 重新安裝。", level: .bad)
        }
        if days <= 2 {
            return StatusRow(title: "簽章到期", detail: "還剩 \(days) 天（\(date)）。請盡快用 AltStore 重新簽署。", level: .warning)
        }
        return StatusRow(title: "簽章到期", detail: "還剩 \(days) 天（\(date)）", level: .good)
    }

    private var containerRow: some View {
        model.containerAvailable
            ? StatusRow(title: "共用容器", detail: "可使用", level: .good)
            : StatusRow(title: "共用容器", detail: "無法使用：App Group 沒有簽進去，請用 AltStore 安裝", level: .bad)
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version)（build \(build)）"
    }
}
