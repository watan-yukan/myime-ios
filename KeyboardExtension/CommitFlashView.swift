import UIKit

/// 按空白送出的字：疊在按鍵區正中央放大並淡出（FR-U29）。
///
/// 範圍只有按鍵區（超出的部分裁掉），不會蓋到候選列；不接收觸控，動畫進行中照常打字。
final class CommitFlashView: UIView {
    private let label = UILabel()
    private let duration: TimeInterval = 1.0
    private let fontSize: CGFloat = 64

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        backgroundColor = .clear
        label.font = UIFont.systemFont(ofSize: fontSize)
        label.textAlignment = .center
        label.alpha = 0
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 前一個還沒淡完就直接換成新的字。
    func flash(_ text: String, color: UIColor) {
        label.layer.removeAllAnimations()
        label.text = text
        label.textColor = color
        label.transform = .identity
        label.alpha = 1
        UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            self.label.alpha = 0
            self.label.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
        }
    }

    /// 開始打下一個字根時立刻消失。
    func cancel() {
        guard label.alpha > 0 || label.layer.animationKeys() != nil else { return }
        label.layer.removeAllAnimations()
        label.alpha = 0
        label.transform = .identity
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // 用 bounds + center，放大動畫進行中重新排版也不會跑位
        label.bounds = CGRect(x: 0, y: 0, width: bounds.width, height: fontSize * 1.3)
        label.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }
}
