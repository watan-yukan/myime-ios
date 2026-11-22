import UIKit

/// 鍵盤中間的送字預覽（FR-U29）：疊在按鍵區中上方。
///
/// - 組字時：淡淡顯示「按空白會送出的字」（第一候選），當作送出前的預覽。
/// - 按空白送出：這個字放大並淡出。
///
/// 範圍只有按鍵區（放大到最後超出的部分裁掉），不會蓋到候選列；不接收觸控，照常打字。
final class CommitFlashView: UIView {
    private let label = UILabel()
    private let duration: TimeInterval = 1.0
    private let fontSize: CGFloat = 88
    /// 預覽的不透明度：看得出來，又不會擋住底下的按鍵。
    private let previewAlpha: CGFloat = 0.45
    /// 字的中心在按鍵區由上往下 28% 的位置（中上方）。
    private let centerYRatio: CGFloat = 0.28
    /// 停手多久才顯示預覽：連續快打時不出現，畫面比較安靜。
    private let previewDelay: TimeInterval = 0.4
    private let previewFadeIn: TimeInterval = 0.2
    /// 目前預覽（含等待中）對應的字根；nil 表示沒有預覽。
    private var previewCode: String?
    private var previewWork: DispatchWorkItem?
    /// 有預覽（已顯示或等待顯示），不是放大淡出動畫。
    var isPreviewing: Bool { previewCode != nil }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        backgroundColor = .clear
        label.font = UIFont.systemFont(ofSize: fontSize)
        label.textAlignment = .center
        // 長詞時縮小字級塞進一行，不顯示「…」
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.3
        label.alpha = 0
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 組字中的預覽：字根一改變就先藏起來，停手 `previewDelay` 秒後才淡入（半透明、靜態）。
    /// 同一組字根重複呼叫（例如其他畫面更新）不會重新計時。
    func showPreview(_ text: String, code: String, color: UIColor) {
        guard code != previewCode else { return }
        previewCode = code
        previewWork?.cancel()
        label.layer.removeAllAnimations()
        label.alpha = 0
        label.transform = .identity
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.previewCode == code else { return }
            self.label.text = text
            self.label.textColor = color
            UIView.animate(withDuration: self.previewFadeIn, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                self.label.alpha = self.previewAlpha
            }
        }
        previewWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + previewDelay, execute: work)
    }

    /// 按空白送出：從預覽的位置放大並淡出（預覽還沒出現也照樣播）；前一個還沒淡完就直接換成新的字。
    func flash(_ text: String, color: UIColor) {
        clearPreviewState()
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

    /// 立刻清掉（預覽或動畫都一樣）。
    func cancel() {
        clearPreviewState()
        guard label.alpha > 0 || label.layer.animationKeys() != nil else { return }
        label.layer.removeAllAnimations()
        label.alpha = 0
        label.transform = .identity
    }

    private func clearPreviewState() {
        previewWork?.cancel()
        previewWork = nil
        previewCode = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // 用 bounds + center，放大動畫進行中重新排版也不會跑位
        label.bounds = CGRect(x: 0, y: 0, width: bounds.width, height: fontSize * 1.3)
        label.center = CGPoint(x: bounds.midX, y: bounds.height * centerYRatio)
    }
}
