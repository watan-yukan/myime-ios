import SwiftUI
import IMECore

struct RootView: View {
    @StateObject private var model = AppModel()
    @StateObject private var backup = BackupService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            HomePage()
                .tabItem { Label("狀態", systemImage: "checkmark.seal") }
            TablePage()
                .tabItem { Label("碼表", systemImage: "tablecells") }
            SettingsPage()
                .tabItem { Label("設定", systemImage: "gearshape") }
            ThemesPage()
                .tabItem { Label("主題", systemImage: "paintpalette") }
            MorePage()
                .tabItem { Label("更多", systemImage: "ellipsis.circle") }
        }
        .environmentObject(model)
        .environmentObject(backup)
        .task {
            model.refresh()
            backup.refreshList()
            backup.runAutoBackupIfNeeded(model: model)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            model.refresh()
            backup.refreshList()
            backup.runAutoBackupIfNeeded(model: model)
        }
    }
}

/// 狀態列：標題、說明文字與一個狀態圖示。
struct StatusRow: View {
    enum Level {
        case good, warning, bad, neutral

        var symbol: String {
            switch self {
            case .good: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .bad: return "xmark.octagon.fill"
            case .neutral: return "circle.dashed"
            }
        }

        var color: Color {
            switch self {
            case .good: return .green
            case .warning: return .orange
            case .bad: return .red
            case .neutral: return .secondary
            }
        }
    }

    let title: String
    let detail: String
    let level: Level

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: level.symbol)
                .foregroundStyle(level.color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
