import UIKit
import IMECore

/// 候選列：永遠佔位，鍵盤高度不因開始組字而跳動（FR-U21）。
///
/// - 組字中：左邊是組字區（字根，點一下送出英文字母，FR-E01），接著是候選字，放不下時有展開鈕（FR-K06）
/// - 沒在組字：顯示工具按鈕（切換主題、收起鍵盤）；表情符號改由左下角的表情鍵開啟
/// - 錯碼時顯示「無此字」（FR-K07）
final class CandidateBarView: UIView {
    enum Tool {
        case theme
        case dismiss
    }

    var onSelectCandidate: ((Int) -> Void)?
    var onSelectEnglish: (() -> Void)?
    var onExpand: (() -> Void)?
    var onTool: ((Tool) -> Void)?
    var onSelectSuggestion: ((Int) -> Void)?

    /// 目前這一列顯示的候選數（展開候選表從這裡之後接續）。
    private(set) var visibleCandidateCount = 0

    private var palette: ThemePalette?
    private var themeMetrics = ThemeMetrics.standard
    private var state = ComposerState.idle
    private var hint: String?
    private var candidateLimit = 0

    private let codeLabel = UILabel()
    private let messageLabel = UILabel()
    private let expandButton = UIButton(type: .system)
    private let separator = UIView()
    private var candidateButtons: [UIButton] = []
    private var suggestionButtons: [UIButton] = []
    private var suggestions: [PhraseSuggestion] = []
    private var toolButtons: [(tool: Tool, button: UIButton)] = []

    private let candidateFont = UIFont.systemFont(ofSize: 20)
    private let codeFont = UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)
    private let sideInset: CGFloat = 8

    override init(frame: CGRect) {
        super.init(frame: frame)

        codeLabel.font = codeFont
        codeLabel.textAlignment = .center
        codeLabel.layer.cornerRadius = 6
        codeLabel.layer.masksToBounds = true
        // 點組字區直接送出打的英文字母
        codeLabel.isUserInteractionEnabled = true
        codeLabel.accessibilityTraits = .button
        codeLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(codeTapped)))
        addSubview(codeLabel)

        messageLabel.font = UIFont.systemFont(ofSize: 14)
        addSubview(messageLabel)

        expandButton.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        expandButton.accessibilityLabel = "展開候選字"
        expandButton.addAction(UIAction { [weak self] _ in self?.onExpand?() }, for: .touchUpInside)
        addSubview(expandButton)

        addSubview(separator)

        let tools: [(Tool, String, String)] = [
            (.theme, "paintpalette", "切換主題"),
            (.dismiss, "keyboard.chevron.compact.down", "收起鍵盤"),
        ]
        for (tool, symbol, label) in tools {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: symbol), for: .normal)
            button.accessibilityLabel = label
            button.addAction(UIAction { [weak self] _ in self?.onTool?(tool) }, for: .touchUpInside)
            addSubview(button)
            toolButtons.append((tool, button))
        }
        render()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func codeTapped() {
        guard state.isComposing else { return }
        onSelectEnglish?()
    }

    // MARK: - 更新

    func applyTheme(palette: ThemePalette, metrics: ThemeMetrics) {
        self.palette = palette
        self.themeMetrics = metrics
        render()
    }

    /// - Parameters:
    ///   - hint: 沒在組字時顯示的提示（例如尚未匯入碼表）。
    ///   - candidateLimit: 設定的候選字數上限；0 表示依寬度自動。
    func update(state: ComposerState, hint: String?, candidateLimit: Int, suggestions: [PhraseSuggestion] = []) {
        self.state = state
        self.hint = hint
        self.candidateLimit = candidateLimit
        self.suggestions = suggestions
        render()
    }

    private func render() {
        guard let palette else { return }
        backgroundColor = palette[.candidateBarBackground].uiColor
        separator.backgroundColor = palette[.candidateSeparator].uiColor
        let text = palette[.candidateText].uiColor
        let accent = palette[.candidateHighlight].uiColor

        let composing = state.isComposing
        codeLabel.isHidden = !composing
        codeLabel.text = state.code
        codeLabel.backgroundColor = palette[.composingBackground].uiColor
        codeLabel.textColor = palette[.composingText].uiColor

        codeLabel.accessibilityLabel = composing ? "送出英文 (state.code)" : nil

        messageLabel.textColor = text.withAlphaComponent(0.6)
        switch (composing, state.status) {
        case (true, .invalid): messageLabel.text = "無此字"
        case (false, _): messageLabel.text = hint
        default: messageLabel.text = nil
        }
        messageLabel.isHidden = messageLabel.text == nil

        for (_, button) in toolButtons {
            button.isHidden = composing
            button.tintColor = text.withAlphaComponent(0.75)
        }
        expandButton.tintColor = text

        for button in suggestionButtons { button.removeFromSuperview() }
        suggestionButtons.removeAll()
        if !composing {
            for (index, suggestion) in suggestions.enumerated() {
                let button = UIButton(type: .system)
                button.titleLabel?.font = candidateFont
                button.setTitle(suggestion.text, for: .normal)
                button.setTitleColor(text, for: .normal)
                button.accessibilityLabel = "建議：\(suggestion.phrase)"
                button.addAction(UIAction { [weak self] _ in self?.onSelectSuggestion?(index) }, for: .touchUpInside)
                button.isHidden = true
                addSubview(button)
                suggestionButtons.append(button)
            }
        }

        for button in candidateButtons { button.removeFromSuperview() }
        candidateButtons.removeAll()
        if composing, state.status == .matched {
            for (index, candidate) in state.candidates.enumerated() {
                let button = UIButton(type: .system)
                button.titleLabel?.font = candidateFont
                button.setTitle(candidate, for: .normal)
                button.setTitleColor(index == 0 ? accent : text, for: .normal)
                button.addAction(UIAction { [weak self] _ in self?.onSelectCandidate?(index) }, for: .touchUpInside)
                button.isHidden = true
                addSubview(button)
                candidateButtons.append(button)
            }
        }
        setNeedsLayout()
    }

    // MARK: - 排版

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        let height = bounds.height
        separator.frame = CGRect(x: 0, y: height - 0.5, width: width, height: 0.5)

        if state.isComposing {
            layoutComposing(width: width, height: height)
        } else {
            layoutIdle(width: width, height: height)
        }
    }

    private func textWidth(_ text: String, font: UIFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    private func layoutComposing(width: CGFloat, height: CGFloat) {
        for (_, button) in toolButtons { button.isHidden = true }

        let codeWidth = textWidth(state.code, font: codeFont) + 20
        codeLabel.frame = CGRect(x: sideInset, y: (height - 28) / 2, width: codeWidth, height: 28)

        let rightEdge = width - sideInset

        let left = codeLabel.frame.maxX + 6
        messageLabel.frame = CGRect(x: left, y: 0, width: max(0, rightEdge - left), height: height)

        let candidates = state.candidates
        var available = rightEdge - left - 4
        var fit = CandidateLayout.fittingCount(
            candidates, availableWidth: available, itemPadding: 16, minItemWidth: 36,
            textWidth: { textWidth($0, font: candidateFont) })
        let needsExpand = !candidates.isEmpty && fit < candidates.count
        expandButton.isHidden = !needsExpand
        if needsExpand {
            expandButton.frame = CGRect(x: rightEdge - 36, y: 0, width: 36, height: height)
            available -= 36
            fit = CandidateLayout.fittingCount(
                candidates, availableWidth: available, itemPadding: 16, minItemWidth: 36,
                textWidth: { textWidth($0, font: candidateFont) })
        }
        if candidateLimit > 0 { fit = min(fit, candidateLimit) }
        visibleCandidateCount = candidateButtons.isEmpty ? 0 : fit

        var x = left
        for (index, button) in candidateButtons.enumerated() {
            if index < visibleCandidateCount {
                let candidateWidth = max(36, textWidth(candidates[index], font: candidateFont) + 16)
                button.frame = CGRect(x: x, y: 0, width: candidateWidth, height: height)
                button.isHidden = false
                x += candidateWidth
            } else {
                button.isHidden = true
            }
        }
    }

    private func layoutIdle(width: CGFloat, height: CGFloat) {
        expandButton.isHidden = true
        visibleCandidateCount = 0

        let buttonWidth: CGFloat = 44
        var x = width - sideInset
        // 有常用詞建議時，右邊只留「收起鍵盤」，空間讓給建議
        let hasSuggestions = !suggestionButtons.isEmpty
        for (tool, button) in toolButtons.reversed() {
            if hasSuggestions, tool != .dismiss {
                button.isHidden = true
                continue
            }
            x -= buttonWidth
            button.frame = CGRect(x: x, y: 0, width: buttonWidth, height: height)
            button.isHidden = false
        }

        var left = sideInset
        for button in suggestionButtons {
            let title = button.title(for: .normal) ?? ""
            let buttonWidth = max(44, textWidth(title, font: candidateFont) + 24)
            guard left + buttonWidth <= x else {
                button.isHidden = true
                continue
            }
            button.frame = CGRect(x: left, y: 0, width: buttonWidth, height: height)
            button.isHidden = false
            left += buttonWidth
        }
        messageLabel.frame = CGRect(x: sideInset + 4, y: 0, width: max(0, x - sideInset - 8), height: height)
        messageLabel.isHidden = messageLabel.isHidden || hasSuggestions
    }
}

/// 展開的候選表：覆蓋在按鍵區上，可翻頁（FR-K06）。順序永遠照碼表（FR-K05）。
final class CandidatePanelView: UIView {
    var onSelect: ((Int) -> Void)?
    var onClose: (() -> Void)?

    private var pager = CandidatePager(candidates: [], pageSize: 1)
    private var cellButtons: [UIButton] = []
    private let previousButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let pageLabel = UILabel()
    private var palette: ThemePalette?
    private var startIndex = 0

    private let columns = 5
    private let controlWidth: CGFloat = 56

    override init(frame: CGRect) {
        super.init(frame: frame)
        previousButton.setImage(UIImage(systemName: "chevron.up"), for: .normal)
        nextButton.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        previousButton.accessibilityLabel = "上一頁"
        nextButton.accessibilityLabel = "下一頁"
        closeButton.accessibilityLabel = "收起候選表"
        previousButton.addAction(UIAction { [weak self] _ in self?.turn(-1) }, for: .touchUpInside)
        nextButton.addAction(UIAction { [weak self] _ in self?.turn(1) }, for: .touchUpInside)
        closeButton.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .touchUpInside)
        pageLabel.font = UIFont.systemFont(ofSize: 12)
        pageLabel.textAlignment = .center
        [previousButton, nextButton, closeButton, pageLabel].forEach { addSubview($0) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyTheme(palette: ThemePalette) {
        self.palette = palette
        backgroundColor = palette[.keyboardBackground].uiColor
        let text = palette[.candidateText].uiColor
        [previousButton, nextButton, closeButton].forEach { $0.tintColor = text }
        pageLabel.textColor = text.withAlphaComponent(0.6)
        rebuild()
    }

    /// - Parameter startIndex: 從哪個候選開始（候選列已顯示的不重複列出）。
    func show(candidates: [String], startIndex: Int) {
        self.startIndex = startIndex
        let rest = Array(candidates.dropFirst(startIndex))
        pager = CandidatePager(candidates: rest, pageSize: max(1, pageSize))
        rebuild()
    }

    private var rows: Int { max(1, Int((bounds.height / 44).rounded(.down))) }
    private var pageSize: Int { rows * columns }

    private func turn(_ delta: Int) {
        if delta > 0 { pager.next() } else { pager.previous() }
        rebuild()
    }

    private func rebuild() {
        for button in cellButtons { button.removeFromSuperview() }
        cellButtons.removeAll()
        guard let palette else { return }
        let text = palette[.candidateText].uiColor
        for item in pager.currentPage {
            let button = UIButton(type: .system)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 20)
            button.setTitle(item.text, for: .normal)
            button.setTitleColor(text, for: .normal)
            let globalIndex = item.index + startIndex
            button.addAction(UIAction { [weak self] _ in self?.onSelect?(globalIndex) }, for: .touchUpInside)
            addSubview(button)
            cellButtons.append(button)
        }
        previousButton.isEnabled = pager.hasPrevious
        nextButton.isEnabled = pager.hasNext
        pageLabel.text = pager.pageCount > 0 ? "\(pager.pageIndex + 1)/\(pager.pageCount)" : nil
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let gridWidth = bounds.width - controlWidth
        let cellWidth = gridWidth / CGFloat(columns)
        let cellHeight = bounds.height / CGFloat(rows)
        for (index, button) in cellButtons.enumerated() {
            let row = index / columns
            let column = index % columns
            button.frame = CGRect(x: CGFloat(column) * cellWidth, y: CGFloat(row) * cellHeight, width: cellWidth, height: cellHeight)
        }
        let controlX = bounds.width - controlWidth
        let third = bounds.height / 4
        closeButton.frame = CGRect(x: controlX, y: 0, width: controlWidth, height: third)
        previousButton.frame = CGRect(x: controlX, y: third, width: controlWidth, height: third)
        pageLabel.frame = CGRect(x: controlX, y: third * 2, width: controlWidth, height: third * 0.5)
        nextButton.frame = CGRect(x: controlX, y: third * 2.5, width: controlWidth, height: third * 1.5)
    }
}
