import SwiftUI
import IMECore

/// 設定頁（FR-A04）。修改後立即存到 App Group，鍵盤下次出現時套用。
struct SettingsPage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            Form {
                if !model.settingsWritable {
                    Section {
                        StatusRow(
                            title: "設定檔比這版 App 新", detail: "為了不弄壞新版的設定，這裡只能檢視、不能修改。請更新 App。",
                            level: .warning)
                    }
                }

                Section("按鍵回饋") {
                    Toggle("按鍵音", isOn: $model.settings.keySound)
                    Toggle("按鍵震動", isOn: $model.settings.haptics)
                }

                Section {
                    Toggle("英文自動大寫", isOn: $model.settings.autoCapitalize)
                    Toggle("雙空白句點", isOn: $model.settings.doubleSpacePeriod)
                    Toggle("中文模式標點轉全形", isOn: $model.settings.fullWidthPunctuation)
                } header: {
                    Text("輸入")
                } footer: {
                    Text("雙空白句點：英文輸入「. 」，中文輸入「。」。")
                }

                Section {
                    Toggle("空白鍵上滑直輸英文", isOn: $model.settings.spaceSwipeUpEnglish)
                    Toggle("送出英文後自動補空格", isOn: $model.settings.spaceSwipeUpAppendSpace)
                    Toggle("送出的英文套用自動大寫", isOn: $model.settings.autoCapitalizeEnglishSend)
                } header: {
                    Text("中英混打")
                } footer: {
                    Text("組字時在空白鍵上快速上滑，或點候選列最後一格，就能把打的字母當英文送出，不用切換鍵盤。")
                }

                Section {
                    Toggle("數字列選字", isOn: $model.settings.numberRow)
                    Picker("組字顯示位置", selection: $model.settings.composingDisplay) {
                        Text("鍵盤上方").tag(ComposingDisplay.bar)
                        Text("輸入框內").tag(ComposingDisplay.inline)
                    }
                    Stepper(
                        model.settings.candidateCount == 0 ? "候選字數：自動" : "候選字數：\(model.settings.candidateCount)",
                        value: $model.settings.candidateCount, in: 0...12)
                } header: {
                    Text("候選字")
                } footer: {
                    Text("組字顯示在輸入框內時，少數 App 可能顯示異常；有問題請改回「鍵盤上方」。")
                }

                Section {
                    Toggle("記錄常用詞", isOn: $model.settings.phraseLearning)
                } header: {
                    Text("常用詞")
                } footer: {
                    Text("只用來在你打完一個字後建議常接的詞，不會改變碼表的候選字順序。關閉後不再記錄，也不再顯示建議。")
                }
            }
            .navigationTitle("設定")
            .onChange(of: model.settings) { _, _ in model.saveSettings() }
        }
    }
}
