import UIKit
import OSLog

/// Spike 鍵盤：驗證側載、啟用、快打、地球鍵、共用容器、剪貼簿、碼表匯入。
/// 日誌只記事件與數量，絕不記錄使用者輸入或剪貼簿內容（NFR-06）。
final class KeyboardViewController: UIInputViewController {
    private let logger = Logger(subsystem: AppConstants.logSubsystem, category: "keyboard")

    private let statusLabel = UILabel()
    private let keyboardView = KeyboardView()

    private let statusBarHeight: CGFloat = 44   // 候選列位置永遠保留（FR-U21）
    private var containerStatus = ""
    private var clipboardStatus = "📋 測試剪貼簿"
    private var keyCount = 0
    private var rolloverCount = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        logger.info("keyboard viewDidLoad")
        setupViews()

        keyboardView.onKey = { [weak self] key, byRollover in
            self?.handle(key, byRollover: byRollover)
        }
        keyboardView.globeButton.addTarget(
            self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        writeHeartbeat()
        containerStatus = readContainerStatus()
        updateStatusLabel()
    }

    // MARK: - Setup

    private func setupViews() {
        guard let inputView else { return }

        statusLabel.numberOfLines = 2
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabel
        statusLabel.adjustsFontSizeToFitWidth = true
        statusLabel.minimumScaleFactor = 0.7
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        keyboardView.translatesAutoresizingMaskIntoConstraints = false

        inputView.addSubview(statusLabel)
        inputView.addSubview(keyboardView)

        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let keysHeight: CGFloat = isPad ? 300 : 216
        let height = inputView.heightAnchor.constraint(equalToConstant: statusBarHeight + keysHeight)
        height.priority = .defaultHigh   // 避免與系統約束衝突

        NSLayoutConstraint.activate([
            height,
            statusLabel.topAnchor.constraint(equalTo: inputView.topAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: inputView.leadingAnchor, constant: 8),
            statusLabel.trailingAnchor.constraint(equalTo: inputView.trailingAnchor, constant: -8),
            statusLabel.heightAnchor.constraint(equalToConstant: statusBarHeight),

            keyboardView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor),
            keyboardView.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: inputView.bottomAnchor),
        ])
    }

    // MARK: - Keys

    private func handle(_ key: Key, byRollover: Bool) {
        switch key {
        case .character(let text):
            textDocumentProxy.insertText(text)
        case .space:
            textDocumentProxy.insertText(" ")
        case .backspace:
            textDocumentProxy.deleteBackward()
        case .returnKey:
            textDocumentProxy.insertText("\n")
        case .globe:
            // 觸控落在地球鍵附近縫隙時才會走到這裡；正常點地球鍵由 globeButton 處理
            advanceToNextInputMode()
            return
        case .clipboardTest:
            testClipboard()
            updateStatusLabel()
            return
        }

        keyCount += 1
        if byRollover {
            rolloverCount += 1
        }
        updateStatusLabel()
    }

    private func updateStatusLabel() {
        statusLabel.text = """
        \(containerStatus)
        按鍵 \(keyCount)｜重疊提早送出 \(rolloverCount)｜\(clipboardStatus)
        """
    }

    // MARK: - Spike checks

    /// Spike 0.10：完整取用下讀取剪貼簿，只顯示字數，不顯示內容。
    private func testClipboard() {
        guard hasFullAccess else {
            clipboardStatus = "剪貼簿：需開啟完整取用"
            return
        }
        let pasteboard = UIPasteboard.general
        if pasteboard.hasStrings {
            let count = pasteboard.string?.count ?? 0
            clipboardStatus = "剪貼簿：讀到 \(count) 字"
            logger.info("clipboard read ok, length=\(count)")
        } else {
            clipboardStatus = "剪貼簿：沒有文字"
            logger.info("clipboard has no strings")
        }
    }

    /// Spike 0.9 / 0.11：讀取主 App 寫入的測試資料與匯入的碼表檔頭。
    private func readContainerStatus() -> String {
        let access = hasFullAccess ? "完整取用:開" : "完整取用:關"
        guard SharedStorage.containerURL != nil else {
            logger.error("app group container unavailable")
            let groups = SigningInfo.current.map { "描述檔群組 \($0.appGroups.count) 個" } ?? "讀不到描述檔"
            return "\(access)｜共用容器:無法使用（\(groups)）"
        }

        var parts = [access]
        do {
            let ping = try SharedStorage.read(SpikePing.self, from: SharedStorage.FileName.ping)
            parts.append("App 寫入 \(ping.writtenAt.formatted(date: .omitted, time: .standard))")
        } catch {
            parts.append("讀不到 App 測試資料")
            logger.error("read ping failed: \(error.localizedDescription, privacy: .public)")
        }

        if let tableURL = SharedStorage.url(SharedStorage.FileName.importedTable),
           FileManager.default.fileExists(atPath: tableURL.path) {
            do {
                let header = try CinHeaderReader.read(url: tableURL)
                parts.append("碼表:\(header.displayName)(\(header.encoding), \(header.byteSize / 1024)KB)")
            } catch {
                parts.append("碼表讀取失敗")
                logger.error("read table header failed: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            parts.append("未匯入碼表")
        }
        return parts.joined(separator: "｜")
    }

    private func writeHeartbeat() {
        do {
            try SharedStorage.write(
                KeyboardHeartbeat(hasFullAccess: hasFullAccess, lastSeen: Date()),
                to: SharedStorage.FileName.heartbeat)
        } catch {
            logger.error("write heartbeat failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
