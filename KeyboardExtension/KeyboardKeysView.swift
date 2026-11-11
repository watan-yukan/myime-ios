import UIKit
import IMECore

/// 按鍵區：依版面引擎排列按鍵，並處理所有觸控與手勢。
///
/// - 多指快打、縫隙 / 邊緣歸屬最近鍵：交給 `TouchTracker`（IMECore，已有自動測試）
/// - 按下放大預覽（FR-U03）、長按空白鍵觸控板（FR-U04）、空白鍵上滑直輸英文（FR-E03）、
///   ⌫ 長按連續刪除（FR-U09）、長按字母出替代字元（FR-U06）：在這裡依每根手指各自處理
final class KeyboardKeysView: UIView {

    // MARK: - 回呼

    /// 一個鍵確定按下；第二個參數代表因多指快打而提早送出。
    var onTap: ((LayoutKey, Bool) -> Void)?
    /// 手指按下一個鍵（觸覺回饋與按鍵音用）。
    var onKeyDown: ((LayoutKey) -> Void)?
    var onSpaceSwipeUp: (() -> Void)?
    var onBackspaceRepeat: ((Int) -> Void)?
    /// 觸控板模式：游標往右（正）或往左（負）移動幾個字元。
    var onTrackpadMove: ((Int) -> Void)?
    var onAlternateSelected: ((String) -> Void)?
    var contentProvider: (LayoutKey) -> KeyContent = { _ in KeyContent() }
    var alternatesProvider: (LayoutKey) -> [String] = { _ in [] }
    /// 排版完成後通知（控制器用來把地球鍵按鈕對齊到版面中的地球鍵）。
    var onLayout: (() -> Void)?

    /// 版面中地球鍵的位置；沒有地球鍵（iPhone）時為 nil。
    var globeFrame: CGRect? {
        pageFrames.frames.first { $0.key.type == .globe }?.rect
    }

    /// 放大預覽可往上超出按鍵區的高度（候選列的高度）。
    var previewHeadroom: CGFloat = 44
    var showsPreview = true

    // MARK: - 版面狀態

    private(set) var pageFrames = PageFrames(frames: [], size: .zero, unit: 0)
    private var page: LayoutPage?
    private var metrics = OrientationMetrics(sideMargin: 6.5, keyGap: 6, rowGap: 11, keyHeight: 45)
    private var isLandscape = false
    private var needsRebuild = true
    private var caps: [KeyID: KeyCapView] = [:]
    private var palette: ThemePalette?
    private var themeMetrics = ThemeMetrics.standard

    private var tracker = TouchTracker(hitTester: KeyHitTester(frames: []))
    private var touchIDs: [ObjectIdentifier: Int] = [:]
    private var nextTouchID = 1
    private var locations: [Int: CGPoint] = [:]
    private var gestures: [Int: Gesture] = [:]
    private(set) var isTrackpadActive = false

    private let previewView = UIView()
    private let previewLabel = UILabel()

    private let longPressDelay: TimeInterval = 0.45
    private let backspaceDelay: TimeInterval = 0.4
    private let backspaceInterval: TimeInterval = 0.08
    private let swipeUpDistance: CGFloat = 28
    private let trackpadStep: CGFloat = 9

    // MARK: - 初始化

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear

        previewView.isHidden = true
        previewView.isUserInteractionEnabled = false
        previewView.layer.cornerRadius = 10
        previewView.layer.shadowOffset = CGSize(width: 0, height: 1)
        previewView.layer.shadowRadius = 3
        previewLabel.textAlignment = .center
        previewLabel.font = UIFont.systemFont(ofSize: 40)
        previewView.addSubview(previewLabel)
        addSubview(previewView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - 設定

    func configure(page: LayoutPage, metrics: OrientationMetrics, landscape: Bool) {
        self.page = page
        self.metrics = metrics
        self.isLandscape = landscape
        needsRebuild = true
        setNeedsLayout()
    }

    func applyTheme(palette: ThemePalette, metrics: ThemeMetrics) {
        self.palette = palette
        self.themeMetrics = metrics
        for cap in caps.values { cap.apply(palette: palette, metrics: metrics) }
        previewView.backgroundColor = palette[.popupBackground].uiColor
        previewView.layer.shadowColor = UIColor.black.cgColor
        previewView.layer.shadowOpacity = 0.25
        previewLabel.textColor = palette[.popupText].uiColor
    }

    /// 狀態改變（Shift、中英模式、頁面）後更新鍵帽文字。
    func refreshContent() {
        for frame in pageFrames.frames {
            caps[frame.id]?.set(content: contentProvider(frame.key))
        }
    }

    /// 依寬度算出按鍵區需要的高度（控制器用來設定鍵盤總高度）。
    func requiredHeight(for page: LayoutPage, metrics: OrientationMetrics, width: CGFloat, landscape: Bool) -> CGFloat {
        LayoutEngine.frames(for: page, metrics: metrics, containerWidth: width, landscape: landscape).size.height
    }

    // MARK: - 排版

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let page, bounds.width > 0 else { return }
        let frames = LayoutEngine.frames(for: page, metrics: metrics, containerWidth: bounds.width, landscape: isLandscape)

        let newIDs = frames.frames.map { $0.id }
        let oldIDs = pageFrames.frames.map { $0.id }
        if needsRebuild || newIDs != oldIDs {
            pageFrames = frames
            rebuildCaps()
            resetTouches()
        } else if frames != pageFrames {
            pageFrames = frames
            for frame in frames.frames { caps[frame.id]?.frame = frame.rect }
            resetTouches()
        }
        needsRebuild = false
        onLayout?()
    }

    private func rebuildCaps() {
        for cap in caps.values { cap.removeFromSuperview() }
        caps.removeAll()
        for frame in pageFrames.frames {
            let cap = KeyCapView()
            cap.frame = frame.rect
            if let palette { cap.apply(palette: palette, metrics: themeMetrics) }
            cap.set(content: contentProvider(frame.key))
            insertSubview(cap, belowSubview: previewView)
            caps[frame.id] = cap
        }
        isTrackpadActive = false
    }

    private func resetTouches() {
        for gesture in gestures.values { gesture.cancel() }
        gestures.removeAll()
        touchIDs.removeAll()
        locations.removeAll()
        for cap in caps.values { cap.setPressed(false) }
        previewView.isHidden = true
        tracker = TouchTracker(hitTester: pageFrames.hitTester())
    }

    /// 截圖測試用：模擬手指按住某個鍵（顯示按下效果與放大預覽），不送出。
    func simulatePress(ofKeyWithOutput output: String) {
        guard let frame = pageFrames.frames.first(where: { $0.key.output == output }) else { return }
        beginPress(frame, touch: 9_999)
    }

    /// 鍵盤消失時取消所有進行中的觸控（不送出）。
    func cancelAllTouches() {
        _ = tracker.reset()
        resetTouches()
        setTrackpadMode(false)
    }

    // MARK: - 觸控

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let id = nextTouchID
            nextTouchID += 1
            touchIDs[ObjectIdentifier(touch)] = id
            let point = touch.location(in: self)
            locations[id] = point
            apply(tracker.began(id: id, at: point))
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let id = touchIDs[ObjectIdentifier(touch)] else { continue }
            let point = touch.location(in: self)
            locations[id] = point
            if let gesture = gestures[id] {
                handleMove(gesture, to: point)
                if gesture.locksKey { continue }  // 空白、⌫、替代字元選單：手指移動不改變目標鍵
            }
            apply(tracker.moved(id: id, to: point))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let id = touchIDs.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            apply(tracker.ended(id: id))
            locations[id] = nil
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let id = touchIDs.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            apply(tracker.cancelled(id: id))
            locations[id] = nil
        }
    }

    private func apply(_ actions: [TouchAction]) {
        for action in actions {
            switch action {
            case .highlight(let frame, let touch):
                beginPress(frame, touch: touch)
            case .unhighlight(let frame, let touch):
                endPress(frame, touch: touch, committed: false, byRollover: false)
            case .commit(let frame, let touch, let byRollover):
                endPress(frame, touch: touch, committed: true, byRollover: byRollover)
            }
        }
    }

    // MARK: - 單根手指的按下與手勢

    private final class Gesture {
        let frame: KeyFrame
        let start: CGPoint
        var last: CGPoint
        var consumed = false
        var repeatCount = 0
        var work: DispatchWorkItem?
        var timer: Timer?
        var trackpadAnchor: CGFloat = 0
        var isTrackpad = false
        var alternates: AlternatesPopupView?

        init(frame: KeyFrame, start: CGPoint) {
            self.frame = frame
            self.start = start
            self.last = start
        }

        var locksKey: Bool {
            frame.key.type == .space || frame.key.type == .backspace || alternates != nil
        }

        func cancelTimers() {
            work?.cancel()
            work = nil
            timer?.invalidate()
            timer = nil
        }

        func cancel() {
            cancelTimers()
            alternates?.removeFromSuperview()
            alternates = nil
        }
    }

    private func beginPress(_ frame: KeyFrame, touch: Int) {
        gestures[touch]?.cancel()
        let gesture = Gesture(frame: frame, start: locations[touch] ?? CGPoint(x: frame.rect.midX, y: frame.rect.midY))
        gestures[touch] = gesture

        caps[frame.id]?.setPressed(true)
        showPreview(for: frame)
        onKeyDown?(frame.key)

        switch frame.key.type {
        case .backspace:
            schedule(gesture, after: backspaceDelay) { [weak self] in self?.startBackspaceRepeat(gesture) }
        case .space:
            schedule(gesture, after: longPressDelay) { [weak self] in self?.startTrackpad(gesture) }
        case .char where !alternatesProvider(frame.key).isEmpty:
            schedule(gesture, after: longPressDelay) { [weak self] in self?.showAlternates(gesture) }
        default:
            break
        }
    }

    private func endPress(_ frame: KeyFrame, touch: Int, committed: Bool, byRollover: Bool) {
        guard let gesture = gestures.removeValue(forKey: touch) else { return }
        gesture.cancelTimers()
        previewView.isHidden = true

        if !gestures.values.contains(where: { $0.frame.id == frame.id }) {
            caps[frame.id]?.setPressed(false)
        }
        if gesture.isTrackpad { setTrackpadMode(false) }

        if let popup = gesture.alternates {
            let selected = popup.selectedOption
            popup.removeFromSuperview()
            gesture.alternates = nil
            if committed, let selected { onAlternateSelected?(selected) }
            return
        }
        if committed, !gesture.consumed {
            onTap?(frame.key, byRollover)
        }
    }

    private func schedule(_ gesture: Gesture, after delay: TimeInterval, _ block: @escaping () -> Void) {
        let item = DispatchWorkItem(block: block)
        gesture.work = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func handleMove(_ gesture: Gesture, to point: CGPoint) {
        gesture.last = point
        switch gesture.frame.key.type {
        case .space:
            if gesture.isTrackpad {
                let steps = Int(((point.x - gesture.trackpadAnchor) / trackpadStep).rounded(.towardZero))
                if steps != 0 {
                    gesture.trackpadAnchor += CGFloat(steps) * trackpadStep
                    onTrackpadMove?(steps)
                }
            } else if !gesture.consumed {
                if gesture.start.y - point.y > swipeUpDistance {
                    gesture.consumed = true
                    gesture.cancelTimers()
                    caps[gesture.frame.id]?.setPressed(false)
                    onSpaceSwipeUp?()
                } else if hypot(point.x - gesture.start.x, point.y - gesture.start.y) > 12 {
                    gesture.work?.cancel()  // 手指在動，不是長按
                }
            }
        case .char:
            gesture.alternates?.updateSelection(atX: point.x)
        default:
            break
        }
    }

    private func startBackspaceRepeat(_ gesture: Gesture) {
        guard gestures.values.contains(where: { $0 === gesture }) else { return }
        gesture.consumed = true
        gesture.repeatCount = 1
        onBackspaceRepeat?(1)
        gesture.timer = Timer.scheduledTimer(withTimeInterval: backspaceInterval, repeats: true) { [weak self, weak gesture] _ in
            guard let self, let gesture else { return }
            gesture.repeatCount += 1
            self.onBackspaceRepeat?(gesture.repeatCount)
        }
    }

    private func startTrackpad(_ gesture: Gesture) {
        guard gestures.values.contains(where: { $0 === gesture }) else { return }
        gesture.isTrackpad = true
        gesture.consumed = true
        gesture.trackpadAnchor = gesture.last.x
        setTrackpadMode(true)
    }

    private func setTrackpadMode(_ on: Bool) {
        guard on != isTrackpadActive else { return }
        isTrackpadActive = on
        for cap in caps.values { cap.setLabelsHidden(on) }
    }

    // MARK: - 放大預覽與替代字元

    private func showPreview(for frame: KeyFrame) {
        guard showsPreview, frame.key.type == .char,
              let text = contentProvider(frame.key).text, !text.isEmpty else {
            previewView.isHidden = true
            return
        }
        let rect = frame.rect
        let width = max(rect.width * 1.65, 40)
        let x = min(max(rect.midX - width / 2, 0), max(bounds.width - width, 0))
        // 預覽高度所有列一致：以第一列能往上伸展的極限為準（不能超出鍵盤範圍）
        let bottom = rect.minY + 2
        let height: CGFloat = 62
        let top = max(bottom - height, -previewHeadroom + 2)
        guard bottom - top >= 36 else {
            previewView.isHidden = true
            return
        }
        previewView.frame = CGRect(x: x, y: top, width: width, height: bottom - top)
        previewLabel.frame = previewView.bounds
        previewLabel.text = text
        previewView.isHidden = false
        bringSubviewToFront(previewView)
    }

    private func showAlternates(_ gesture: Gesture) {
        guard gestures.values.contains(where: { $0 === gesture }) else { return }
        let options = alternatesProvider(gesture.frame.key)
        guard !options.isEmpty else { return }

        previewView.isHidden = true
        let popup = AlternatesPopupView(options: options, palette: palette)
        let size = popup.preferredSize
        let rect = gesture.frame.rect
        let x = min(max(rect.midX - size.width / 2, 0), max(bounds.width - size.width, 0))
        popup.frame = CGRect(x: x, y: max(rect.minY - 4 - size.height, -previewHeadroom + 2), width: size.width, height: size.height)
        addSubview(popup)
        gesture.alternates = popup
        gesture.consumed = true
        popup.updateSelection(atX: gesture.last.x)
    }
}

/// 長按字母時的替代字元選單：左右滑動選取，放開輸入（FR-U06）。
final class AlternatesPopupView: UIView {
    private let options: [String]
    private var labels: [UILabel] = []
    private let palette: ThemePalette?
    private(set) var selectedIndex = 0

    private let cellWidth: CGFloat = 38
    private let cellHeight: CGFloat = 52

    var preferredSize: CGSize {
        CGSize(width: cellWidth * CGFloat(options.count) + 8, height: cellHeight)
    }

    var selectedOption: String? {
        options.indices.contains(selectedIndex) ? options[selectedIndex] : nil
    }

    init(options: [String], palette: ThemePalette?) {
        self.options = options
        self.palette = palette
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        layer.cornerRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 3
        layer.shadowOpacity = 0.25
        backgroundColor = palette?[.popupBackground].uiColor ?? .secondarySystemBackground

        for option in options {
            let label = UILabel()
            label.text = option
            label.textAlignment = .center
            label.font = UIFont.systemFont(ofSize: 26)
            label.textColor = palette?[.popupText].uiColor ?? .label
            label.layer.cornerRadius = 6
            label.layer.masksToBounds = true
            addSubview(label)
            labels.append(label)
        }
        updateHighlight()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for (index, label) in labels.enumerated() {
            label.frame = CGRect(x: 4 + cellWidth * CGFloat(index), y: 4, width: cellWidth, height: bounds.height - 8)
        }
    }

    /// `x` 是按鍵區座標；換算成選項編號並高亮。
    func updateSelection(atX x: CGFloat) {
        let local = x - frame.minX - 4
        let index = Int((local / cellWidth).rounded(.down))
        selectedIndex = min(max(index, 0), options.count - 1)
        updateHighlight()
    }

    private func updateHighlight() {
        for (index, label) in labels.enumerated() {
            let selected = index == selectedIndex
            label.backgroundColor = selected ? (palette?[.actionKeyBackground].uiColor ?? .systemBlue) : .clear
            label.textColor = selected
                ? (palette?[.actionKeyText].uiColor ?? .white)
                : (palette?[.popupText].uiColor ?? .label)
        }
    }
}
