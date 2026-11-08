import UIKit

enum Key: Equatable {
    case character(String)
    case space
    case backspace
    case returnKey
    case globe
    case clipboardTest
}

struct KeySpec {
    let key: Key
    let label: String
    let widthUnits: CGFloat
    var isFunctionKey: Bool {
        if case .character = key { return false }
        return key != .space
    }
}

/// Spike 用鍵盤版面 + 自訂觸控層。
///
/// 驗證重點：
/// - FR-U19 快打防掉字：按鍵在放開時送出；但另一根手指按下時，立即送出所有尚未送出的鍵（保持順序）。
/// - FR-U20 觸控範圍：觸控點一律對應到「距離最近」的按鍵，縫隙與邊緣都有反應。
/// - 地球鍵用系統 UIButton + handleInputModeList，取得與原生相同的點擊 / 長按行為（FR-U12）。
final class KeyboardView: UIView {
    /// (按鍵, 是否因多指重疊而提早送出)
    var onKey: ((Key, Bool) -> Void)?

    let globeButton = UIButton(type: .system)

    private let rows: [[KeySpec]] = {
        func letters(_ s: String) -> [KeySpec] {
            s.map { KeySpec(key: .character(String($0)), label: String($0), widthUnits: 1) }
        }
        return [
            letters("qwertyuiop"),
            letters("asdfghjkl"),
            letters("zxcvbnm") + [KeySpec(key: .backspace, label: "⌫", widthUnits: 1.5)],
            [
                KeySpec(key: .globe, label: "", widthUnits: 1.25),
                KeySpec(key: .clipboardTest, label: "📋", widthUnits: 1.25),
                KeySpec(key: .space, label: "space", widthUnits: 5),
                KeySpec(key: .returnKey, label: "return", widthUnits: 2.5),
            ],
        ]
    }()

    private lazy var specs: [KeySpec] = rows.flatMap { $0 }
    private var keyFrames: [CGRect] = []
    private var capViews: [KeyCapView] = []

    private struct ActiveTouch {
        var index: Int
        var committed: Bool
    }

    private var activeTouches: [ObjectIdentifier: ActiveTouch] = [:]
    /// 觸控按下的先後順序，用於多指重疊時依序送出。
    private var touchOrder: [ObjectIdentifier] = []

    private let unitsPerRow: CGFloat = 10
    private let keySpacing: CGFloat = 6
    private let rowSpacing: CGFloat = 10
    private let edgeInset: CGFloat = 3

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear

        for spec in specs {
            let cap = KeyCapView(label: spec.label, isFunctionKey: spec.isFunctionKey)
            cap.isUserInteractionEnabled = false
            cap.isHidden = spec.key == .globe
            addSubview(cap)
            capViews.append(cap)
        }

        globeButton.setImage(UIImage(systemName: "globe"), for: .normal)
        globeButton.tintColor = .label
        globeButton.backgroundColor = KeyCapView.functionColor
        globeButton.layer.cornerRadius = 5
        globeButton.accessibilityLabel = "下一個鍵盤"
        addSubview(globeButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let unit = (bounds.width - edgeInset * 2) / unitsPerRow
        let rowHeight = (bounds.height - rowSpacing * CGFloat(rows.count)) / CGFloat(rows.count)

        var frames: [CGRect] = []
        for (rowIndex, row) in rows.enumerated() {
            let totalUnits = row.reduce(0) { $0 + $1.widthUnits }
            var x = edgeInset + (unitsPerRow - totalUnits) / 2 * unit
            let y = rowSpacing / 2 + CGFloat(rowIndex) * (rowHeight + rowSpacing)
            for spec in row {
                let width = spec.widthUnits * unit
                frames.append(CGRect(x: x + keySpacing / 2, y: y, width: width - keySpacing, height: rowHeight))
                x += width
            }
        }
        keyFrames = frames

        for (index, cap) in capViews.enumerated() {
            cap.frame = frames[index]
        }
        if let globeIndex = specs.firstIndex(where: { $0.key == .globe }) {
            globeButton.frame = frames[globeIndex]
        }
    }

    // MARK: - Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            // 多指重疊：新手指按下時，先依序送出所有還按著、尚未送出的鍵
            flushPendingTouches()

            guard let index = nearestKeyIndex(to: touch.location(in: self)) else { continue }
            let id = ObjectIdentifier(touch)
            activeTouches[id] = ActiveTouch(index: index, committed: false)
            touchOrder.append(id)
            capViews[index].isHighlighted = true
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        // 尚未送出前可滑到旁邊的鍵修正
        for touch in touches {
            let id = ObjectIdentifier(touch)
            guard var active = activeTouches[id], !active.committed,
                  let index = nearestKeyIndex(to: touch.location(in: self)),
                  index != active.index else { continue }
            capViews[active.index].isHighlighted = false
            active.index = index
            capViews[index].isHighlighted = true
            activeTouches[id] = active
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let active = removeTouch(touch) else { continue }
            if !active.committed {
                commit(index: active.index, byRollover: false)
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            _ = removeTouch(touch)
        }
    }

    private func flushPendingTouches() {
        for id in touchOrder {
            guard var active = activeTouches[id], !active.committed else { continue }
            commit(index: active.index, byRollover: true)
            active.committed = true
            activeTouches[id] = active
        }
    }

    private func removeTouch(_ touch: UITouch) -> ActiveTouch? {
        let id = ObjectIdentifier(touch)
        guard let active = activeTouches.removeValue(forKey: id) else { return nil }
        touchOrder.removeAll { $0 == id }
        let stillPressed = activeTouches.values.contains { $0.index == active.index }
        if !stillPressed {
            capViews[active.index].isHighlighted = false
        }
        return active
    }

    private func commit(index: Int, byRollover: Bool) {
        onKey?(specs[index].key, byRollover)
    }

    /// 觸控點到各按鍵矩形的距離取最小者：縫隙、邊緣都會對應到最近的鍵。
    private func nearestKeyIndex(to point: CGPoint) -> Int? {
        var best: (index: Int, distance: CGFloat)?
        for (index, frame) in keyFrames.enumerated() {
            let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
            let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
            let distance = dx * dx + dy * dy
            if best == nil || distance < best!.distance {
                best = (index, distance)
            }
        }
        return best?.index
    }
}

/// 單一按鍵外觀（Spike 先用接近原生的簡單樣式，正式版改由主題 token 控制）。
final class KeyCapView: UIView {
    static let characterColor = UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 0.42, alpha: 1) : .white
    }
    static let functionColor = UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 0.27, alpha: 1) : UIColor(white: 0.68, alpha: 1)
    }
    static let pressedColor = UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 0.55, alpha: 1) : UIColor(white: 0.82, alpha: 1)
    }

    private let label = UILabel()
    private let normalColor: UIColor

    var isHighlighted = false {
        didSet { backgroundColor = isHighlighted ? Self.pressedColor : normalColor }
    }

    init(label text: String, isFunctionKey: Bool) {
        normalColor = isFunctionKey ? Self.functionColor : Self.characterColor
        super.init(frame: .zero)
        backgroundColor = normalColor
        layer.cornerRadius = 5
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 0

        label.text = text
        label.textAlignment = .center
        label.textColor = .label
        label.font = .systemFont(ofSize: text.count > 1 ? 16 : 22)
        label.adjustsFontSizeToFitWidth = true
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.insetBy(dx: 2, dy: 2)
    }
}
