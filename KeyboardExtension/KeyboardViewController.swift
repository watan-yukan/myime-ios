import UIKit
import OSLog
import IMECore

/// 鍵盤擴充的根 view：宣告支援按鍵音（`playInputClick` 需要）。
final class KeyboardRootView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }

    /// 鍵盤希望的高度；`allowsSelfSizing` 為 true 時系統會參考 intrinsic size。
    var desiredHeight: CGFloat = 0 {
        didSet { if oldValue != desiredHeight { invalidateIntrinsicContentSize() } }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric,
               height: desiredHeight > 0 ? desiredHeight : UIView.noIntrinsicMetric)
    }
}

/// 把 `UITextDocumentProxy` 包成引擎看得懂的輸入框；記錄最後一次自己改動輸入框的時間，
/// 用來分辨 `textDidChange` 是自己造成的還是使用者移動了游標。
final class ProxyTextOutput: TextOutput {
    weak var proxy: UITextDocumentProxy?
    private(set) var lastEditTime: TimeInterval = 0

    private func touch() {
        lastEditTime = ProcessInfo.processInfo.systemUptime
    }

    func insertText(_ text: String) {
        touch()
        proxy?.insertText(text)
    }

    func deleteBackward() {
        touch()
        proxy?.deleteBackward()
    }

    func setMarkedText(_ text: String) {
        touch()
        proxy?.setMarkedText(text, selectedRange: NSRange(location: text.utf16.count, length: 0))
    }

    func unmarkText() {
        touch()
        proxy?.unmarkText()
    }

    var textBeforeCursor: String? {
        proxy?.documentContextBeforeInput
    }
}

/// MyIME 鍵盤：嘸蝦米輸入（碼表由主 App 匯入）。
/// 日誌只記事件與數量，絕不記錄使用者輸入或剪貼簿內容（NFR-06）。
final class KeyboardViewController: UIInputViewController {
    private let logger = Logger(subsystem: AppConstants.logSubsystem, category: "keyboard")

    private let candidateBar = CandidateBarView()
    private let keysView = KeyboardKeysView()
    private let candidatePanel = CandidatePanelView()
    private let emojiPanel = EmojiPanelView()
    private let output = ProxyTextOutput()
    private let haptic = UIImpactFeedbackGenerator(style: .light)
    private let globeButton = UIButton(type: .system)

    private var layoutFile: KeyboardLayoutFile?
    private var session: KeyboardSession?
    private var phraseStore = PhraseStore()
    private var savedPhraseRevision = 0
    private var phrasesWritable = true
    private var settings = KeyboardSettings()
    private var theme = BuiltinThemes.native()
    private var isDark = false
    private var tableStamp: Date?
    private var tableHint: String? = "請先在 MyIME App 匯入碼表"

    /// 開發期間：在鍵盤最上緣顯示高度數字（只有高度，沒有任何輸入內容）。正式版改為 false 或刪除。
    private static let showHeightDebug = true
    private let heightDebugLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 9)
        label.textColor = .systemYellow
        label.isUserInteractionEnabled = false
        label.numberOfLines = 0
        label.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        return label
    }()

    /// 開發期間：列出影響鍵盤高度的約束（只有系統類別名稱與數值，沒有輸入內容）。
    private func heightDiagnostics(_ root: UIView) -> String {
        func name(_ item: AnyObject?) -> String {
            guard let item else { return "nil" }
            if item === root { return "root" }
            if item === root.superview { return "super" }
            return String(describing: type(of: item))
        }
        let superName = root.superview.map { String(describing: type(of: $0)) } ?? "nil"
        let superHeight = root.superview?.bounds.height ?? -1
        var lines = [String(
            format: "view==input %@ / tamic %@ / selfSizing %@ / super %@ %.0f",
            (inputView === view) ? "Y" : "N",
            root.translatesAutoresizingMaskIntoConstraints ? "Y" : "N",
            ((root as? UIInputView)?.allowsSelfSizing ?? false) ? "Y" : "N",
            superName, superHeight)]
        let heightConstraints = root.constraintsAffectingLayout(for: .vertical)
            .filter { $0.firstAttribute == .height || $0.secondAttribute == .height }
        for c in heightConstraints.prefix(4) {
            lines.append(String(
                format: "%@ %@ c=%.0f p=%.0f %@ act=%@",
                name(c.firstItem), name(c.secondItem), c.constant, c.priority.rawValue,
                c.identifier ?? "-", c.isActive ? "Y" : "N"))
        }
        return lines.joined(separator: "\n")
    }
    private var heightConstraint: NSLayoutConstraint?
    private var configuredKey = ""
    private var pageForcedByKeyboardType = false
    private let candidateBarHeight: CGFloat = 56  // 比原生高 12pt，讓第一排的放大預覽有完整空間

    /// 鍵盤的主 view（`inputView`；取不到時退回 `view`）。
    private var rootView: UIView { inputView ?? view }

    // MARK: - 生命週期

    override func loadView() {
        let root = KeyboardRootView(frame: .zero, inputViewStyle: .keyboard)
        root.allowsSelfSizing = true
        inputView = root
        if !isViewLoaded { view = root }  // 後備：指派沒有成為主 view 時，直接設定 view
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        logger.info("keyboard viewDidLoad")
        output.proxy = textDocumentProxy
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        layoutFile = LayoutCatalog.layout(isPad: isPad)
        keysView.showsPreview = !isPad  // iPad 沒有按下放大預覽（比照原生）

        let root: UIView = rootView
        root.addSubview(candidateBar)
        root.addSubview(keysView)
        setupGlobeButton()
        root.addSubview(candidatePanel)
        root.addSubview(emojiPanel)
        candidatePanel.isHidden = true
        emojiPanel.isHidden = true

        wireCallbacks()
        loadSettings()
        loadSession()
        applyTheme()

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: KeyboardViewController, _: UITraitCollection) in
            self.applyTheme()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        writeHeartbeat()
        loadSettings()
        loadSession()
        loadPhrases()
        applyTheme()
        hidePanels()
        session?.autocapitalizationType = autocapitalizationType()
        session?.contextChanged()
        applyKeyboardTypeDefaults()
        refreshEverything()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        keysView.cancelAllTouches()
        session?.contextChanged()
        savePhrasesIfNeeded(force: true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutKeyboard()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        configuredKey = ""
        rootView.setNeedsLayout()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        // 自己剛改過輸入框時，系統也會通知；只有使用者移動游標、換欄位才需要清除組字
        let sinceOwnEdit = ProcessInfo.processInfo.systemUptime - output.lastEditTime
        if sinceOwnEdit > 0.3 {
            session?.autocapitalizationType = autocapitalizationType()
            session?.contextChanged()
            applyKeyboardTypeDefaults()
            refreshEverything()
        }
    }

    // MARK: - 載入

    private func loadSettings() {
        guard let url = SharedStorage.url(SharedStorage.FileName.settings) else { return }
        settings = SettingsStore(url: url).load().settings
        session?.settings = settings
    }

    /// 載入碼表與引擎；碼表沒有變動時沿用現有引擎，不會讓使用者的中 / 英模式被重置。
    private func loadSession() {
        let index = TableProvider.loadForKeyboard(hasFullAccess: hasFullAccess)
        let stamp = TableProvider.cacheStamp
        if session != nil, stamp == tableStamp { return }
        tableStamp = stamp

        let source: any CandidateSource
        if let index {
            source = index
            tableHint = nil
        } else {
            source = DictionaryCandidateSource([:])
            tableHint = hasFullAccess ? "請先在 MyIME App 匯入碼表" : "請開啟完整取用並在 App 匯入碼表"
        }
        let newSession = KeyboardSession(source: source, settings: settings)
        newSession.output = output
        newSession.phraseStore = phraseStore
        newSession.onChange = { [weak self] in self?.refreshEverything() }
        session = newSession
        configuredKey = ""
        logger.info("session loaded, hasTable=\(index != nil)")
    }

    /// 地球鍵：疊一個系統按鈕在版面中的地球鍵上，取得與原生相同的點擊切換與長按鍵盤清單（FR-U12、U16）。
    private func setupGlobeButton() {
        globeButton.backgroundColor = .clear
        globeButton.accessibilityLabel = "下一個鍵盤"
        globeButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        globeButton.isHidden = true
        keysView.addSubview(globeButton)
        keysView.onLayout = { [weak self] in self?.positionGlobeButton() }
    }

    private func positionGlobeButton() {
        guard let frame = keysView.globeFrame else {
            globeButton.isHidden = true
            return
        }
        globeButton.frame = frame
        globeButton.isHidden = false
        keysView.bringSubviewToFront(globeButton)
    }

    /// 常用詞記錄存在 App Group；每次鍵盤出現時重新讀取，才看得到主 App 管理頁的修改。
    private func loadPhrases() {
        guard let url = SharedStorage.url(SharedStorage.FileName.phrases) else { return }
        let loaded = PhraseFileStore(url: url).load()
        phraseStore = loaded.store
        phrasesWritable = loaded.writable
        savedPhraseRevision = phraseStore.revision
        session?.phraseStore = phraseStore
    }

    private func savePhrasesIfNeeded(force: Bool = false) {
        guard phrasesWritable, phraseStore.revision != savedPhraseRevision,
              force || phraseStore.revision - savedPhraseRevision >= 20,
              let url = SharedStorage.url(SharedStorage.FileName.phrases) else { return }
        do {
            try PhraseFileStore(url: url).save(phraseStore)
            savedPhraseRevision = phraseStore.revision
        } catch {
            logger.error("save phrases failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func wireCallbacks() {
        keysView.onTap = { [weak self] key, _ in self?.handleTap(key) }
        keysView.onKeyDown = { [weak self] _ in self?.keyFeedback() }
        keysView.onSpaceSwipeUp = { [weak self] in self?.session?.swipeUpSpace() }
        keysView.onBackspaceRepeat = { [weak self] count in self?.session?.repeatBackspace(count: count) }
        keysView.onTrackpadMove = { [weak self] steps in self?.moveCursor(by: steps) }
        keysView.onAlternateSelected = { [weak self] text in self?.insertAlternate(text) }
        keysView.contentProvider = { [weak self] key in self?.content(for: key) ?? KeyContent() }
        keysView.alternatesProvider = { [weak self] key in self?.alternates(for: key) ?? [] }
        keysView.previewHeadroom = candidateBarHeight

        candidateBar.onSelectCandidate = { [weak self] index in self?.session?.selectCandidate(index) }
        candidateBar.onSelectEnglish = { [weak self] in self?.session?.selectEnglishOption() }
        candidateBar.onExpand = { [weak self] in self?.showCandidatePanel() }
        candidateBar.onTool = { [weak self] tool in self?.handleTool(tool) }
        candidateBar.onSelectSuggestion = { [weak self] index in self?.session?.acceptSuggestion(index) }

        candidatePanel.onSelect = { [weak self] index in
            self?.session?.selectCandidate(index)
            self?.candidatePanel.isHidden = true
        }
        candidatePanel.onClose = { [weak self] in self?.candidatePanel.isHidden = true }

        emojiPanel.onInsert = { [weak self] emoji in
            self?.keyFeedback()
            self?.textDocumentProxy.insertText(emoji)
        }
        emojiPanel.onBackspace = { [weak self] in
            self?.keyFeedback()
            self?.textDocumentProxy.deleteBackward()
        }
        emojiPanel.onClose = { [weak self] in self?.emojiPanel.isHidden = true }
    }

    // MARK: - 按鍵處理

    private func handleTap(_ key: LayoutKey) {
        switch key.type {
        case .globe:
            advanceToNextInputMode()
        case .dismiss:
            dismissKeyboard()
        case .emoji:
            showEmojiPanel()
        case .tab:
            textDocumentProxy.insertText("\t")
        default:
            session?.tap(key)
        }
    }

    private func handleTool(_ tool: CandidateBarView.Tool) {
        switch tool {
        case .emoji: showEmojiPanel()
        case .theme: cycleTheme()
        case .dismiss: dismissKeyboard()
        }
    }

    private func keyFeedback() {
        if settings.haptics, hasFullAccess {
            haptic.impactOccurred()
            haptic.prepare()
        }
        if settings.keySound {
            UIDevice.current.playInputClick()
        }
    }

    private func moveCursor(by steps: Int) {
        if session?.composerState.isComposing == true { session?.contextChanged() }
        textDocumentProxy.adjustTextPosition(byCharacterOffset: steps)
    }

    private func insertAlternate(_ text: String) {
        textDocumentProxy.insertText(text)
        session?.refreshAutoCapitalization()
        refreshEverything()
    }

    private func alternates(for key: LayoutKey) -> [String] {
        guard let session, key.type == .char, let output = key.output else { return [] }
        // 字母在中文模式是字根，不出替代字元；符號任何模式都可以
        let isLetter = output.first?.isLetter == true
        if isLetter, session.mode == .chinese { return [] }
        return AlternateCharacters.options(for: output, uppercase: session.showsUppercase)
    }

    // MARK: - 面板

    private func showCandidatePanel() {
        guard let session else { return }
        let keysFrame = keysView.frame
        candidatePanel.frame = keysFrame
        candidatePanel.applyTheme(palette: theme.palette(isDark: isDark))
        candidatePanel.layoutIfNeeded()
        candidatePanel.show(candidates: session.composerState.candidates, startIndex: candidateBar.visibleCandidateCount)
        candidatePanel.isHidden = false
    }

    private func showEmojiPanel() {
        emojiPanel.frame = keysView.frame
        emojiPanel.applyTheme(palette: theme.palette(isDark: isDark))
        emojiPanel.reload()
        emojiPanel.isHidden = false
    }

    private func hidePanels() {
        candidatePanel.isHidden = true
        emojiPanel.isHidden = true
    }

    // MARK: - 主題與外觀

    private func cycleTheme() {
        let ids = ThemeCatalog.builtinIDs
        let current = ids.firstIndex(of: settings.theme.id) ?? 0
        settings.theme.id = ids[(current + 1) % ids.count]
        if let url = SharedStorage.url(SharedStorage.FileName.settings) {
            try? SettingsStore(url: url).save(settings)
        }
        session?.settings = settings
        applyTheme()
    }

    private func hostAppearance() -> HostKeyboardAppearance {
        switch textDocumentProxy.keyboardAppearance {
        case .dark: return .dark
        case .light: return .light
        default: return .unspecified
        }
    }

    private func applyTheme() {
        theme = ThemeCatalog.theme(id: settings.theme.id)
        isDark = ThemeAppearance.isDark(
            setting: settings.theme.appearance,
            systemIsDark: traitCollection.userInterfaceStyle == .dark,
            host: hostAppearance())
        let palette = theme.palette(isDark: isDark)
        rootView.backgroundColor = palette[.keyboardBackground].uiColor
        keysView.applyTheme(palette: palette, metrics: theme.metrics)
        candidateBar.applyTheme(palette: palette, metrics: theme.metrics)
        candidatePanel.applyTheme(palette: palette)
        emojiPanel.applyTheme(palette: palette)
        keysView.refreshContent()
    }

    // MARK: - 輸入框情境

    private func autocapitalizationType() -> AutocapitalizationType {
        switch textDocumentProxy.autocapitalizationType {
        case .some(.none): return .none
        case .some(.words): return .words
        case .some(.allCharacters): return .allCharacters
        default: return .sentences
        }
    }

    private var layoutVariant: String? {
        switch textDocumentProxy.keyboardType {
        case .some(.emailAddress): return "email"
        case .some(.URL): return "url"
        default: return nil
        }
    }

    /// 數字、電話鍵盤欄位一開始就顯示數字頁（FR-U11）。
    private func applyKeyboardTypeDefaults() {
        switch textDocumentProxy.keyboardType {
        case .some(.numberPad), .some(.decimalPad), .some(.phonePad), .some(.asciiCapableNumberPad):
            session?.switchPage(to: "numbers")
            pageForcedByKeyboardType = true
        default:
            // 離開數字欄位後，回到字母頁
            if pageForcedByKeyboardType {
                session?.switchPage(to: "alpha")
                pageForcedByKeyboardType = false
            }
        }
    }

    // MARK: - 畫面

    private func content(for key: LayoutKey) -> KeyContent {
        guard let session else { return KeyContent() }
        switch key.type {
        case .char:
            let base = key.output ?? ""
            let isLetter = base.first?.isLetter == true
            let text = isLetter ? (session.showsUppercase ? base.uppercased() : base.lowercased()) : base
            return KeyContent(text: key.label ?? text)
        case .shift:
            switch session.shift.mode {
            case .off: return KeyContent(symbol: "shift")
            case .once: return KeyContent(symbol: "shift.fill")
            case .locked: return KeyContent(symbol: "capslock.fill")
            }
        case .backspace: return KeyContent(symbol: "delete.left")
        case .space: return KeyContent()
        case .returnKey: return returnKeyContent()
        case .page: return KeyContent(text: key.label, isFunctionText: true)
        case .langToggle: return KeyContent(text: session.mode == .chinese ? "中" : "英", isFunctionText: true)
        case .globe: return KeyContent(symbol: "globe")
        case .emoji: return KeyContent(symbol: "face.smiling")
        case .dismiss: return KeyContent(symbol: "keyboard.chevron.compact.down")
        case .tab: return KeyContent(symbol: "arrow.right.to.line")
        case .spacer: return KeyContent()
        }
    }

    /// 依輸入框的 `returnKeyType` 改變 Return 鍵（FR-U10）。
    private func returnKeyContent() -> KeyContent {
        switch textDocumentProxy.returnKeyType ?? .default {
        case .go: return KeyContent(text: "前往", isAction: true, isFunctionText: true)
        case .search, .google, .yahoo: return KeyContent(symbol: "magnifyingglass", isAction: true)
        case .send: return KeyContent(text: "傳送", isAction: true, isFunctionText: true)
        case .done: return KeyContent(text: "完成", isAction: true, isFunctionText: true)
        case .next: return KeyContent(text: "下一項", isAction: true, isFunctionText: true)
        case .join: return KeyContent(text: "加入", isAction: true, isFunctionText: true)
        case .route: return KeyContent(text: "路線", isAction: true, isFunctionText: true)
        case .continue: return KeyContent(text: "繼續", isAction: true, isFunctionText: true)
        case .emergencyCall: return KeyContent(text: "緊急", isAction: true, isFunctionText: true)
        default: return KeyContent(symbol: "return")
        }
    }

    private func refreshEverything() {
        guard let session else { return }
        candidateBar.update(
            state: session.composerState, hint: tableHint, candidateLimit: settings.candidateCount,
            suggestions: session.suggestions)
        keysView.refreshContent()
        savePhrasesIfNeeded()
        // 頁面切換（或情境變化）需要重新排版
        if configuredKey != currentConfigKey() {
            rootView.setNeedsLayout()
        }
    }

    private func currentConfigKey() -> String {
        guard let session else { return "" }
        let width = Int(rootView.bounds.width)
        return "\(session.page)|\(layoutVariant ?? "-")|\(isLandscape)|\(width)|\(showsNumberRow)"
    }

    /// 可選的數字列（FR-U22）：設定開啟時，字母頁最上方多一列數字；組字中按數字直接選字。
    private var showsNumberRow: Bool {
        settings.numberRow && session?.page == "alpha"
    }

    private static func insertingNumberRow(into page: LayoutPage) -> LayoutPage {
        let digits = LayoutRow(keys: "1234567890".map { LayoutKey(char: String($0)) })
        var result = page
        result.rows.insert(digits, at: 0)
        result.landscapeRows?.insert(digits, at: 0)
        return result
    }

    private var isLandscape: Bool {
        UIScreen.main.bounds.width > UIScreen.main.bounds.height
    }

    private func layoutKeyboard() {
        let root = rootView
        guard let layoutFile, let session else { return }
        let width = root.bounds.width
        guard width > 0 else { return }

        let landscape = isLandscape
        var metrics = layoutFile.metrics.metrics(landscape: landscape)
        guard let basePage = layoutFile.page(session.page, variant: layoutVariant) else { return }
        let page = showsNumberRow ? Self.insertingNumberRow(into: basePage) : basePage

        var keysHeight = keysView.requiredHeight(for: page, metrics: metrics, width: width, landscape: landscape)
        let keysHeightRequested = keysHeight
        // 有些 App（例如備忘錄的格式工具列）會把鍵盤高度壓得比期望小；
        // 系統給的高度不夠時，等比縮小按鍵高度與間距，避免最下面一列被切掉。
        let available = root.bounds.height - candidateBarHeight
        if available > 120, keysHeight > available + 0.5 {
            let scale = available / keysHeight
            metrics.keyHeight *= scale
            metrics.rowGap *= scale
            metrics.topInset *= scale
            metrics.bottomInset *= scale
            keysHeight = keysView.requiredHeight(for: page, metrics: metrics, width: width, landscape: landscape)
        }
        let total = candidateBarHeight + keysHeight
        // 向系統要求的永遠是「完整」高度，不是縮放後的高度；
        // 否則第一次拿到較小的預設高度後，就會一直要求那個小高度。
        let requested = candidateBarHeight + keysHeightRequested

        (root as? KeyboardRootView)?.desiredHeight = requested
        if heightConstraint == nil {
            let constraint = root.heightAnchor.constraint(equalToConstant: requested)
            // 實驗：999 時系統固定給 224pt；改成必要（1000）看系統是否接受
            constraint.priority = .required
            constraint.identifier = "myime.height"
            constraint.isActive = true
            heightConstraint = constraint
        } else if heightConstraint?.constant != requested {
            heightConstraint?.constant = requested
        }

        if Self.showHeightDebug {
            let origin = root.superview.map { root.convert(CGPoint.zero, to: $0).y } ?? -1
            heightDebugLabel.text = String(
                format: "要求 %.0f / 實際 %.0f / 縮放後 %.0f / 頂端偏移 %.0f / 螢幕 %.0f",
                requested, root.bounds.height, total, origin,
                UIScreen.main.bounds.height)
                + "\n" + heightDiagnostics(root)
            heightDebugLabel.frame = CGRect(x: 4, y: 0, width: width - 8, height: 60)
            if heightDebugLabel.superview == nil { root.addSubview(heightDebugLabel) }
            root.bringSubviewToFront(heightDebugLabel)
        }

        candidateBar.frame = CGRect(x: 0, y: 0, width: width, height: candidateBarHeight)
        keysView.frame = CGRect(x: 0, y: candidateBarHeight, width: width, height: keysHeight)
        candidatePanel.frame = keysView.frame
        emojiPanel.frame = keysView.frame

        let key = currentConfigKey() + String(format: "|%.1f", metrics.keyHeight)
        if key != configuredKey {
            configuredKey = key
            keysView.configure(page: page, metrics: metrics, landscape: landscape)
        }
    }

    // MARK: - 狀態回報（主 App 狀態面板用，FR-A11）

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
