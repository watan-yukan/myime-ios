# MyIME — 個人用 iOS / iPadOS 形碼輸入法

相容 `.cin` 碼表的 iOS 第三方鍵盤，外觀與操作比照原生鍵盤。在 **Windows（無 Mac）** 環境下開發、透過 GitHub Actions macOS 編譯、側載安裝到自己的 iPhone / iPad。

> 本 repo 與發佈的 `.ipa` **不包含任何商業輸入法碼表**，碼表需由使用者自行合法取得並在 App 中匯入。

## 文件
| 文件 | 說明 |
|---|---|
| [docs/01_需求規格書.md](docs/01_需求規格書.md) | 目標、iOS 限制、功能 / 非功能需求、風險、驗收標準、待確認事項 |
| [docs/02_開發流程規劃.md](docs/02_開發流程規劃.md) | 開發階段、專案結構、分支策略、CI/CD、品質管理、里程碑 |
| [docs/03_架構設計.md](docs/03_架構設計.md) | 模組結構、IMECore 狀態機、儲存位置、開源資料評估 |
| [docs/04_UI規格.md](docs/04_UI規格.md) | 原生鍵盤量測（iPhone / iPad）、主題格式與內建配色 |
| [docs/05_Spike驗證手冊.md](docs/05_Spike驗證手冊.md) | 階段 0：Windows 準備、推送、下載 .ipa、側載、逐項驗證與結果表 |
| [docs/06_資料格式.md](docs/06_資料格式.md) | 版面 JSON、碼表索引檔、設定 / 常用詞 / 剪貼簿 / 備份格式 |

## 專案結構（目前）
| 路徑 | 內容 |
|---|---|
| `project.yml` | XcodeGen 專案定義（CI 上產生 Xcode 專案） |
| `App/` | 主 App（SwiftUI） |
| `KeyboardExtension/` | 鍵盤擴充（UIKit，自訂觸控層） |
| `Shared/` | App 與鍵盤共用：App Group 存取、.cin 檔頭讀取 |
| `Tools/` | `package_ipa.sh`（CI 打包）、`Inspect-Cin.ps1`（本機檢查碼表格式） |
| `.github/workflows/build.yml` | 碼表防護檢查 → 編譯 → 產出 .ipa |

## 授權
All Rights Reserved — 本 repo 公開僅供瀏覽，未授予任何使用權，詳見 [LICENSE](LICENSE)。

## 目前狀態
- [x] 需求與流程文件草案（v0.7）
- [x] 階段 0：Spike 程式碼、CI、驗證手冊
- [x] 階段 0：推送到 GitHub、側載、完成驗證結果表（Gate 0 通過，2026-11-10）
- [ ] 階段 1：IMECore 引擎架構與 .cin 解析
