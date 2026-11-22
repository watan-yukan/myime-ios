import SwiftUI
import IMECore

/// 主題頁：預覽與套用（FR-A10、FR-T05）。
struct ThemesPage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            Form {
                Section("外觀") {
                    Picker("深淺色", selection: $model.settings.theme.appearance) {
                        Text("跟隨系統").tag(AppearanceSetting.system)
                        Text("固定淺色").tag(AppearanceSetting.light)
                        Text("固定深色").tag(AppearanceSetting.dark)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    ForEach(ThemeCatalog.all, id: \.id) { theme in
                        Button {
                            model.settings.theme.id = theme.id
                        } label: {
                            row(for: theme)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("主題")
                } footer: {
                    Text("也可以在鍵盤的候選列按調色盤圖示，直接循環切換。")
                }
            }
            .navigationTitle("主題")
            .onChange(of: model.settings) { _, _ in model.saveSettings() }
        }
    }

    private func row(for theme: Theme) -> some View {
        HStack(spacing: 12) {
            ThemePreview(palette: theme.light, metrics: theme.metrics)
            ThemePreview(palette: theme.dark, metrics: theme.metrics)
            VStack(alignment: .leading, spacing: 2) {
                Text(theme.name).font(.body)
                Text(subtitle(for: theme)).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            if model.settings.theme.id == theme.id {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(model.settings.theme.id == theme.id ? .isSelected : [])
    }

    private func subtitle(for theme: Theme) -> String {
        switch theme.id {
        case "native": return "仿 iOS 內建鍵盤"
        case "morandi": return "低彩度暖灰與霧綠"
        case "high-contrast": return "粗邊框，對比 7:1 以上"
        case "oled": return "全黑背景，OLED 省電"
        default: return ""
        }
    }
}

/// 主題縮圖：鍵盤背景加三列按鍵。
struct ThemePreview: View {
    let palette: ThemePalette
    let metrics: ThemeMetrics

    var body: some View {
        VStack(spacing: 3) {
            keyRow(count: 5)
            keyRow(count: 4)
            HStack(spacing: 3) {
                key(width: 8, action: false)
                key(width: 22, action: false)
                key(width: 9, action: true)
            }
        }
        .padding(5)
        .frame(width: 58, height: 44)
        .background(Color(uiColor: palette[.keyboardBackground].uiColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
        .accessibilityHidden(true)
    }

    private func keyRow(count: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<count, id: \.self) { _ in key(width: 7, action: false) }
        }
    }

    private func key(width: CGFloat, action: Bool) -> some View {
        let fill = action ? palette[.actionKeyBackground] : palette[.keyBackground]
        let border = palette[.keyBorder]
        return RoundedRectangle(cornerRadius: 1.5)
            .fill(Color(uiColor: fill.uiColor))
            .overlay(
                RoundedRectangle(cornerRadius: 1.5)
                    .stroke(Color(uiColor: border.uiColor), lineWidth: border.alpha > 0 && metrics.keyBorderWidth > 0 ? 0.8 : 0)
            )
            .frame(width: width, height: 8)
    }
}
