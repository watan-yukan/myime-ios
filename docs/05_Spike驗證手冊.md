# 階段 0 Spike 驗證手冊

| 項目 | 內容 |
|---|---|
| 對應文件 | [02_開發流程規劃.md](02_開發流程規劃.md) 階段 0 |
| 目標 | 證明「Windows → GitHub Actions 編譯 → 側載 → 手機上能用」可行，並驗證高風險技術點 |
| 產出 | 本文件第 6 章的驗證結果表（填好後回報） |

Spike 版的 App 叫 **MyIME**，鍵盤只有英文字母、⌫、空白、return、🌐、📋 幾個鍵，上方兩行是測試狀態列：

```
完整取用:開｜App 寫入 14:03:12｜碼表:XXX(UTF-8, 1234KB)
按鍵 52｜重疊提早送出 7｜剪貼簿：讀到 12 字
```

---

## 1. Windows 一次性準備

| # | 工具 | 用途 | 取得方式 |
|---|---|---|---|
| 1 | **Git for Windows** | 版本控制、推送到 GitHub | git-scm.com |
| 2 | **GitHub 帳號** | 放原始碼、跑雲端編譯 | github.com |
| 3 | **iTunes** 與 **iCloud**（Apple 官網版） | 讓 Windows 認得 iPhone / iPad；**不要裝 Microsoft Store 版** | apple.com 下載頁 |
| 4 | **AltServer**（含 AltStore） | 用 Apple ID 簽章並安裝 .ipa；**會註冊 App Group** | `winget install --id RileyTestut.AltServer --exact`（需系統管理員） |
| — | ~~Sideloadly~~ | 免費帳號重簽時**不會註冊 App Group**，共用容器無法使用，不適用本專案 | — |
| — | Apple Mobile Device Support | 讓 Windows 與 iPhone 溝通；若 iTunes 未一併裝上需另裝 | `winget install --id Apple.AppleMobileDeviceSupport --exact`（需系統管理員） |
| 5 | （選用）libimobiledevice for Windows | 用 `idevicesyslog` 看鍵盤日誌（0.12） | 第三方編譯版 |

> **Apple ID 提醒**：AltServer 需要輸入 Apple ID 登入 Apple 的開發者服務。若有顧慮，可另外申請一個專用 Apple ID（需開啟雙重認證）。Apple ID 密碼只在 AltServer 視窗內輸入，**不要寫進任何檔案或 repo**。
>
> **只用一種側載工具**：Sideloadly 與 AltServer 各自申請開發憑證，交替使用會互相撤銷，導致「無法信任」。

---

## 2. 建立 GitHub repo 並推送

1. 在 GitHub 網頁建立 **Public** repo，名稱建議 `myime-ios`（不要用「嘸蝦米」等商標字樣，R-LIU-5），**不要**勾選自動產生 README / LICENSE / .gitignore。
2. 在專案資料夾開 PowerShell，依序執行：

```bash
git init
```

```bash
git add .
```

```bash
git status
```

> 確認清單中**沒有任何 `.cin` 檔**，也沒有 `.ipa`、`.p12`。

```bash
git commit -m "chore: add stage 0 spike skeleton"
```

```bash
git branch -M main
```

```bash
git remote add origin https://github.com/<你的帳號>/myime-ios.git
```

```bash
git push -u origin main
```

3. 推送後到 repo 的 **Actions** 頁，`build` 工作會自動開始（約 5～10 分鐘）。

---

## 3. 取得安裝檔

1. Actions → 點最新一次 `build` → 頁面最下方 **Artifacts** → 下載 `MyIME-ipa-<編號>`。
2. 解壓縮得到 `MyIME.ipa`。

> 若 `build` 失敗，把失敗步驟的紅字錯誤訊息貼給我。

---

## 4. 安裝到 iPhone / iPad

1. 用 USB 線連接裝置，裝置上點「信任這部電腦」。
2. 從「開始」選單開啟 **AltServer**（只會出現在右下角系統匣，菱形圖示）。
3. **第一次**：點 AltServer 圖示 →「Install AltStore」→ 選裝置 → 輸入 Apple ID 與密碼（及雙重認證碼）。
4. iOS 16 以上第一次側載：「設定 → 隱私權與安全性 → **開發者模式**」開啟並重新開機。
5. 「設定 → 一般 → **VPN 與裝置管理**」→ 點你的 Apple ID → **信任**（需連網；公司 Wi-Fi / VPN 可能擋住驗證，可改用行動網路）。
6. **安裝 MyIME**：按住 **Shift** 再點 AltServer 圖示 →「Install AltStore」→ 選裝置 → 選 `MyIME.ipa`。
7. 打開 MyIME App，「簽章資訊」的「描述檔群組」應顯示 `group.com.watanyukan.myime.<Team ID>`，「共用容器」為 ✅。

> AltStore 會把 Bundle ID 與 App Group 加上 Team ID 後綴，App 會從描述檔自動讀取實際的群組名稱（`Shared/SigningInfo.swift`）。
>
> **7 天續簽**：電腦開著 AltServer、手機與電腦在同一 Wi-Fi（或接 USB）→ 手機開 AltStore →「My Apps」→「Refresh All」。

iPhone 與 iPad 都要裝。

---

## 5. 驗證步驟

### 0.8 啟用鍵盤、打字
1. 「設定 → 一般 → 鍵盤 → 鍵盤 → 新增鍵盤」→ 選 **MyIME**。
2. 點「MyIME」→ 開啟「**允許完整取用**」。
3. 打開備忘錄，按地球鍵切到 MyIME，打幾個字。

**預期**：鍵盤出現、字能打進備忘錄。

### 0.9 App Group 共用資料
1. MyIME App →「0.9 共用資料」→ 按「寫入測試資料」。
2. 回備忘錄叫出 MyIME 鍵盤（若鍵盤已開著，先切走再切回來）。

**預期**：狀態列第一行顯示「App 寫入 時:分:秒」，且與 App 顯示的時間一致。
**若顯示「共用容器:無法使用」或「讀不到 App 測試資料」**：先看 MyIME App 的「簽章資訊」區塊：
- 「描述檔群組」**有值**：App 會自動改用該群組 ID（側載工具重簽時改了名）。重開 App 與鍵盤再測一次。
- 「描述檔群組」顯示「**（無）**」：側載工具簽章時沒有包含 App Group。確認是用 **AltStore** 安裝（Sideloadly 不會註冊 App Group），且 CI 的「App Group entitlements 檢查通過」。

### 0.10 剪貼簿
1. 在任一處複製一段文字。
2. 在 MyIME 鍵盤按 📋。

**預期**：狀態列顯示「剪貼簿：讀到 N 字」。
**同時記錄**：系統有沒有跳出「允許貼上」的提示（風險 R7）。

### 0.11 碼表匯入
1. 把自己的 `.cin` 放到 iPhone「檔案」App 可存取的位置（例如用 Windows 版 iCloud 放進 iCloud Drive）。
2. MyIME App →「0.11 碼表匯入」→ 選檔。
3. 回到鍵盤，切走再切回。

**預期**：App 顯示碼表名稱、編碼、大小、選字鍵；鍵盤狀態列也顯示碼表名稱。

### 0.12 裝置日誌（選用）
裝好 libimobiledevice 後，連接裝置執行：

```bash
idevicesyslog -m com.watanyukan.myime
```

**預期**：叫出鍵盤時看到 `keyboard viewDidLoad`；按 📋 時看到 `clipboard read ok, length=N`（只有字數，沒有內容）。

### 0.13 檢查碼表格式（Windows 本機）
碼表**不要**放進專案資料夾。在專案資料夾執行：

```bash
powershell -ExecutionPolicy Bypass -File Tools\Inspect-Cin.ps1 -Path "D:\你放碼表的位置\檔名.cin"
```

**預期**：顯示編碼、`%selkey`、字數、最長碼長、平 / 片假名筆數。只有統計數字，不會印出碼表內容。

### 0.14 地球鍵
1. 在 MyIME 鍵盤**點**地球鍵 → 應切到下一個鍵盤。
2. **長按**地球鍵 → 應跳出系統鍵盤清單，滑到目標放開即切換。

iPhone 與 iPad 都測。**預期**：與 Apple 鍵盤的地球鍵行為一樣。

### 0.15 快打（多指重疊）
1. 打開 MyIME App 的「測試輸入」框，切到 MyIME 鍵盤。
2. 用兩根拇指盡量快速打一句固定的英文（例如 `the quick brown fox jumps over the lazy dog`），重複 5 次。

**預期**：
- 打出來的字**沒有漏字、沒有順序顛倒**。
- 狀態列「重疊提早送出」數字有增加（代表確實發生多指重疊並被正確處理）。
- 按到按鍵之間的縫隙或鍵盤邊緣，也會打出最近的那個鍵。

### 0.16 重簽後資料是否保留
1. 打開 MyIME App，記下「0.16 重簽資料保留」兩個 ID（共用容器、App 自身），並確認已匯入碼表。
2. 在手機 AltStore →「My Apps」→ 對 MyIME 按「Refresh」，或用 AltServer（Shift + Install）再安裝一次同一個 `MyIME.ipa`（模擬 7 天重簽）。
3. 再打開 MyIME App。

**預期**：兩個都顯示「保留中」且 ID 與步驟 1 相同；碼表仍在。
**若變成「首次建立」或 ID 不同**：重簽會清除資料 → 風險 R13 成立，自動備份（FR-D05）是必要的。

---

## 6. 驗證結果表（填好後回報）

| # | 項目 | iPhone | iPad | 備註 |
|---|---|---|---|---|
| 0.6 | GitHub Actions 編譯成功 | ✅ | — | build #3 起含 App Group 檢查 |
| 0.7 | AltStore 安裝成功 | ✅ | | Sideloadly 可裝但不註冊 App Group |
| 0.8 | 鍵盤可啟用、可打字 | | | |
| 0.9 | 鍵盤讀得到 App 寫入的資料 | | | |
| 0.10 | 剪貼簿讀取成功 | | | 是否跳出「允許貼上」 |
| 0.11 | 碼表匯入，App 與鍵盤都看得到 | | | 編碼 / 選字鍵 |
| 0.12 | 看得到裝置日誌（選用） | | | |
| 0.13 | 碼表格式檢查 | — | — | 編碼、最長碼長、假名筆數 |
| 0.14 | 地球鍵點擊 / 長按同原生 | | | |
| 0.15 | 快打不掉字、不亂序 | | | 重疊提早送出次數 |
| 0.16 | 重簽後資料保留 | | | 兩個 ID 是否相同 |

**Gate 0 判定**：0.8 通過，且 0.9 / 0.11 通過（或決定採用備案：剪貼簿匯入碼表 / 升級付費帳號），即可進入階段 1。
