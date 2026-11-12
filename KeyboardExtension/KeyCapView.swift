import UIKit
import IMECore

/// 鍵帽內容：文字或 SF Symbol。
struct KeyContent: Equatable {
    var text: String?
    var symbol: String?
    /// 動作鍵（藍色 Return 等）。
    var isAction = false
    /// 功能鍵文字（123、中）字級較小。
    var isFunctionText = false
    /// 鍵帽上緣的淺灰小字（下滑輸入的字元，FR-U25）。
    var secondary: String? = nil
    /// 提示用的小圖示（空白鍵上滑提示，FR-U27）：較小、用次要文字色。
    var isHint = false
}

/// 單一按鍵外觀：顏色、圓角、邊框、陰影全部來自主題（FR-T01），元件內不寫死任何顏色。
final class KeyCapView: UIView {
    private let label = UILabel()
    private let secondaryLabel = UILabel()
    private let imageView = UIImageView()
    private var content = KeyContent()
    private var palette: ThemePalette?
    private var themeMetrics = ThemeMetrics.standard
    private(set) var isPressed = false
    private var labelsHidden = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 0

        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        addSubview(label)

        imageView.contentMode = .center  // 圖示保持固定大小置中，不被拉伸填滿按鍵
        addSubview(imageView)

        secondaryLabel.textAlignment = .center
        secondaryLabel.isHidden = true
        addSubview(secondaryLabel)
    }

    private var symbolName: String?
    private var symbolSize: CGFloat = 0

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func set(content newContent: KeyContent) {
        content = newContent
        label.text = newContent.text
        symbolName = newContent.symbol
        symbolSize = 0  // 下次排版時依按鍵大小重新產生圖示
        label.isHidden = newContent.text == nil || labelsHidden
        imageView.isHidden = newContent.symbol == nil || labelsHidden
        secondaryLabel.text = newContent.secondary
        secondaryLabel.isHidden = newContent.secondary == nil || labelsHidden
        updateColors()
        setNeedsLayout()
    }

    func apply(palette: ThemePalette, metrics: ThemeMetrics) {
        self.palette = palette
        self.themeMetrics = metrics
        updateColors()
        setNeedsLayout()
    }

    func setPressed(_ pressed: Bool) {
        guard pressed != isPressed else { return }
        isPressed = pressed
        updateColors()
    }

    /// 觸控板模式：鍵帽文字隱藏（FR-U04）。
    func setLabelsHidden(_ hidden: Bool) {
        labelsHidden = hidden
        label.isHidden = content.text == nil || hidden
        imageView.isHidden = content.symbol == nil || hidden
        secondaryLabel.isHidden = content.secondary == nil || hidden
    }

    private func updateColors() {
        guard let palette else { return }
        let background: RGBAColor
        let foreground: RGBAColor
        if isPressed {
            background = content.isAction ? palette[.actionKeyBackground] : palette[.keyBackgroundPressed]
            foreground = content.isAction ? palette[.actionKeyText] : palette[.keyTextPressed]
        } else {
            background = content.isAction ? palette[.actionKeyBackground] : palette[.keyBackground]
            foreground = content.isAction ? palette[.actionKeyText] : palette[.keyText]
        }
        backgroundColor = background.uiColor
        label.textColor = foreground.uiColor
        imageView.tintColor = content.isHint ? palette[.keySecondaryText].uiColor : foreground.uiColor
        secondaryLabel.textColor = palette[.keySecondaryText].uiColor

        let border = palette[.keyBorder]
        layer.borderColor = border.uiColor.cgColor
        layer.borderWidth = border.alpha > 0 ? CGFloat(themeMetrics.keyBorderWidth) : 0

        let shadow = palette[.keyShadow]
        layer.shadowColor = shadow.uiColor.cgColor
        layer.shadowOpacity = shadow.alpha > 0 ? 1 : 0
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // 圓角隨鍵高：直向 45 pt 約 7 pt、橫向 32 pt 約 5 pt（量測 5～8.5 pt）
        let base = min(max(bounds.height * 0.16, 5), 8.5)
        layer.cornerRadius = base * CGFloat(themeMetrics.cornerRadiusScale)

        let fontSize: CGFloat
        if content.isFunctionText {
            fontSize = min(16, bounds.height * 0.36)
        } else {
            fontSize = min(26, bounds.height * 0.5)
        }
        label.font = UIFont.systemFont(ofSize: fontSize * CGFloat(themeMetrics.fontScale))
        if content.secondary != nil {
            // 上緣小字約 10 pt，字母往下移一點避免重疊（UI 規格 4.5）
            let smallSize = min(11, max(8, bounds.height * 0.23)) * CGFloat(themeMetrics.fontScale)
            secondaryLabel.font = UIFont.systemFont(ofSize: smallSize)
            secondaryLabel.frame = CGRect(x: 0, y: 2, width: bounds.width, height: smallSize + 2)
            label.frame = bounds.insetBy(dx: 2, dy: 2).offsetBy(dx: 0, dy: bounds.height * 0.07)
        } else {
            label.frame = bounds.insetBy(dx: 2, dy: 2)
        }
        imageView.frame = bounds

        // 圖示大小隨鍵高：iPhone 直向約 20 pt、橫向 16 pt、iPad 最大 24 pt
        let fullSize = min(max(bounds.height * 0.44, 16), 24)
        let size = (content.isHint ? min(13, fullSize) : fullSize) * CGFloat(themeMetrics.fontScale)
        if size != symbolSize {
            symbolSize = size
            imageView.image = symbolName.flatMap {
                UIImage(systemName: $0, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: .regular))
            }
        }
    }
}
