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

    /// 隱形 view 上下貼齊 root、高度為期望值；系統以內容計算自訂鍵盤高度時會採用。
    private func setupSizer(in root: UIView) {
        sizerView.isUserInteractionEnabled = false
        sizerView.translatesAutoresizingMaskIntoConstraints = false
        root.insertSubview(sizerView, at: 0)
        let height = sizerView.heightAnchor.constraint(equalToConstant: 281)
        height.priority = UILayoutPriority(999)  // 不和系統的必要約束硬碰，避免被剔除
        height.identifier = "myime.sizer.height"
        NSLayoutConstraint.activate([
            sizerView.topAnchor.constraint(equalTo: root.topAnchor),
            sizerView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sizerView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sizerView.widthAnchor.constraint(equalToConstant: 1),
            height,
        ])
        sizerHeight = height
    }
    /// 撐開鍵盤高度用的隱形 view：上下貼齊 root，高度 = 期望高度。
    /// `allowsSelfSizing` 的鍵盤由「內容」決定高度，直接約束 root 的高度會被系統剔除。
    private let sizerView = UIView()
    /// 非原生主題的底色：上方兩角圓角（一定看得到）。
    private let backgroundView = UIView()
    /// 往鍵盤上方延伸的同色圓角底：系統沒有裁切時，可蓋住系統外框上緣那一段（實驗，FR-T）。
    private let backgroundExtensionView = UIView()
    private let backgroundCornerRadius: CGFloat = 16
    private let backgroundExtensionHeight: CGFloat = 24
    private var sizerHeight: NSLayoutConstraint?
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
        // 候選列不放收合鍵：iPhone 比照原生沒有收合鍵，改用最上面那條快速下滑；iPad 右下角另有收合鍵
        candidateBar.showsDismissTool = false

        let root: UIView = rootView
        root.addSubview(candidateBar)
        root.addSubview(keysView)
        setupSizer(in: root)
        for background in [backgroundExtensionView, backgroundView] {
            background.isUserInteractionEnabled = false
            background.isHidden = true
            background.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            root.insertSubview(background, at: 0)
        }
        root.insertSubview(backgroundExtensionView, belowSubview: backgroundView)
        root.clipsToBounds = false  // 讓延伸的底色有機會畫到鍵盤上方
        setupGlobeButton()
        root.addSubview(candidatePanel)
        root.addSubview(emojiPanel)
        candidatePanel.isHidden = true
        emojiPanel.isHidden = true
        addSwipeDownToDismiss(to: candidateBar)
        addSwipeDownToDismiss(to: emojiPanel)

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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Apple 文件：自訂鍵盤的高度要在畫面出現之後調整，系統才會套用。重新啟用一次高度約束。
        if let sizerHeight {
            sizerHeight.isActive = false
            sizerHeight.isActive = true
        }
        rootView.setNeedsLayout()
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
        keysView.flickEnabled = settings.flickSecondary
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
        keysView.onSecondaryArmed = { [weak self] in
            // 下滑跨過門檻：震一下（只震動、不再發按鍵音）
            guard let self, self.settings.haptics, self.hasFullAccess else { return }
            self.haptic.impactOccurred()
            self.haptic.prepare()
        }
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

    /// 表情頁比照原生佔滿整個鍵盤（蓋住候選列），表情可以更大。
    private var emojiPanelFrame: CGRect {
        CGRect(x: 0, y: 0, width: keysView.frame.width, height: keysView.frame.maxY)
    }

    private func showEmojiPanel() {
        emojiPanel.frame = emojiPanelFrame
        emojiPanel.applyTheme(palette: theme.palette(isDark: isDark))
        emojiPanel.reload()
        emojiPanel.isHidden = false
    }

    private func hidePanels() {
        candidatePanel.isHidden = true
        emojiPanel.isHidden = true
    }

    // MARK: - 主題與外觀

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
        // 原生主題用系統鍵盤底色（透明），和系統容器上方的圓角區域一致；其他主題才自己塗底色
        let usesSystemBackground = theme.id == "native"
        // 底色改由兩塊上方圓角的 view 畫（候選列透明），非原生主題的鍵盤上緣才會是圓角
        rootView.backgroundColor = .clear
        candidateBar.usesSystemBackground = true
        let backgroundColor = palette[.keyboardBackground].uiColor
        for background in [backgroundView, backgroundExtensionView] {
            background.backgroundColor = backgroundColor
            background.isHidden = usesSystemBackground
        }
        // 表情頁會蓋住候選列，也要有同樣的圓角
        emojiPanel.layer.cornerRadius = usesSystemBackground ? 0 : backgroundCornerRadius
        emojiPanel.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
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
            // 下滑輸入的小字（FR-U25）；設定關閉時不顯示
            let secondary = settings.flickSecondary ? key.secondary : nil
            return KeyContent(text: key.label ?? text, secondary: secondary)
        case .shift:
            switch session.shift.mode {
            case .off: return KeyContent(symbol: "shift")
            case .once: return KeyContent(symbol: "shift.fill")
            case .locked: return KeyContent(symbol: "capslock.fill")
            }
        case .backspace: return KeyContent(symbol: "delete.left")
        case .space:
            // 組字中顯示雙折線，提示可上滑送出英文（FR-U27）
            if session.composerState.isComposing, settings.spaceSwipeUpEnglish {
                return KeyContent(symbol: "chevron.up.2", isHint: true)
            }
            return KeyContent()
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

    /// 依輸入框的 `returnKeyType` 改變 Return 鍵（FR-U10）。iOS 26 原生只顯示圖示、不顯示文字
    /// （UI 規格 2.2；完成、傳送與少見類型的圖示為推測，待實機對照）。
    private func returnKeyContent() -> KeyContent {
        switch textDocumentProxy.returnKeyType ?? .default {
        case .go, .join, .route, .continue, .emergencyCall:
            return KeyContent(symbol: "arrow.right", isAction: true)
        case .search, .google, .yahoo: return KeyContent(symbol: "magnifyingglass", isAction: true)
        case .send: return KeyContent(symbol: "arrow.up", isAction: true)
        case .done: return KeyContent(symbol: "checkmark", isAction: true)
        case .next: return KeyContent(symbol: "chevron.right")
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
        // 向系統要求的永遠是「完整」高度，不是縮放後的高度；
        // 否則第一次拿到較小的預設高度後，就會一直要求那個小高度。
        let requested = candidateBarHeight + keysHeightRequested

        (root as? KeyboardRootView)?.desiredHeight = requested
        if let sizerHeight, abs(sizerHeight.constant - requested) > 0.5 {
            sizerHeight.constant = requested
        }

        // 底色：一塊貼齊鍵盤（上方圓角），一塊往上延伸（系統沒裁切時蓋住系統外框上緣）
        backgroundView.frame = root.bounds
        backgroundView.layer.cornerRadius = backgroundCornerRadius
        backgroundExtensionView.frame = CGRect(
            x: 0, y: -backgroundExtensionHeight,
            width: width, height: backgroundExtensionHeight + backgroundCornerRadius * 2)
        backgroundExtensionView.layer.cornerRadius = backgroundCornerRadius + 4

        candidateBar.frame = CGRect(x: 0, y: 0, width: width, height: candidateBarHeight)
        keysView.frame = CGRect(x: 0, y: candidateBarHeight, width: width, height: keysHeight)
        candidatePanel.frame = keysView.frame
        emojiPanel.frame = emojiPanelFrame

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

// MARK: - 由上往下快速滑動收起鍵盤

extension KeyboardViewController: UIGestureRecognizerDelegate {
    /// 只認鍵盤最上面這一條（候選列高度）；按鍵區的手勢留給打字與之後的下滑輸入。
    private var dismissStripHeight: CGFloat { 56 }

    fileprivate func addSwipeDownToDismiss(to view: UIView) {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan(_:)))
        pan.delegate = self
        pan.cancelsTouchesInView = true  // 認定是下滑後，取消候選字或表情的點選
        view.addGestureRecognizer(pan)
    }

    @objc private func handleDismissPan(_ pan: UIPanGestureRecognizer) {
        guard pan.state == .ended, let view = pan.view else { return }
        let translation = pan.translation(in: view)
        let velocity = pan.velocity(in: view)
        // 要「快速」往下：位移超過 30pt、速度超過 500pt/s，且明顯是垂直方向
        if translation.y > 30, velocity.y > 500, translation.y > abs(translation.x) * 1.5 {
            dismissKeyboard()
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let view = pan.view,
              view === candidateBar || view === emojiPanel else { return true }
        let start = pan.location(in: view)
        guard start.y - pan.translation(in: view).y <= dismissStripHeight else { return false }
        let velocity = pan.velocity(in: view)
        return velocity.y > 0 && velocity.y > abs(velocity.x)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
