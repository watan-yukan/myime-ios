import Foundation

/// 嘸蝦米組字狀態機（Issue #4，FR-K02~K07）。
///
/// 純邏輯：輸入 `InputEvent`，更新 `state` 並回傳要對輸入框做的 `OutputAction`，
/// 不接觸 UIKit，所有行為都能單元測試。
///
/// 本 Issue 之外的事件先提供合理的基本行為，之後的 Issue 會再細化：
/// - Return、情境改變、數字選字：#7
/// - Shift 直輸大寫、候選列英文選項、空白上滑：#8
public struct Composer {
    /// 組字內容最長保留的字母數（超過碼長仍保留，供送出英文，FR-E05）。
    public static let maxBufferLength = 32

    public private(set) var state: ComposerState = .idle
    public var display: ComposingDisplay
    /// 目前輸入模式（FR-K08），以 `.toggleInputMode` 切換。
    public private(set) var mode: InputMode = .chinese
    /// 中文模式下，非字根的半形符號轉成全形（FR-K09）。
    public var fullWidthPunctuation = true

    private let source: any CandidateSource
    private let codeKeys: Set<Character>
    private var punctuation = Punctuation()

    public init(source: any CandidateSource, display: ComposingDisplay = .bar) {
        self.source = source
        self.display = display
        self.codeKeys = Set("abcdefghijklmnopqrstuvwxyz").union(source.extraCodeKeys)
    }

    /// 處理一個事件，回傳要對輸入框執行的動作（依序執行）。
    @discardableResult
    public mutating func handle(_ event: InputEvent) -> [OutputAction] {
        if mode == .english, event != .toggleInputMode {
            return handleEnglish(event)
        }
        switch event {
        case .toggleInputMode:
            // 切換前先送出組字中的內容，避免字根殘留
            let output = commitForPassthrough()
            mode = mode == .chinese ? .english : .chinese
            return output
        case .key(let character):
            return handleKey(character)
        case .shiftedKey(let character):
            // 暫定（#8 細化）：先送出組字中的內容，再直輸大寫
            return commitForPassthrough() + [.insert(String(character).uppercased())]
        case .space:
            return handleSpace()
        case .backspace:
            return handleBackspace()
        case .selectCandidate(let index):
            guard state.isComposing, state.candidates.indices.contains(index) else { return [] }
            return commit(state.candidates[index])
        case .returnKey:
            // 組字中按 Return 送出原始字母，不換行（FR-K12，#7 再補測試與設定）
            guard state.isComposing else { return [.insert("\n")] }
            return commit(state.code)
        case .swipeUpSpace:
            guard state.isComposing else { return [.insert(" ")] }
            return commit(state.code)
        case .contextChanged:
            // 游標移動或切換欄位：清除組字，不送出（FR-K14）
            punctuation.reset()
            guard state.isComposing else { return [] }
            state = .idle
            return display == .inline ? [.clearMarked] : []
        }
    }

    // MARK: - 事件處理

    /// 英文模式：按鍵直接輸出，不組字（FR-K08）。
    private mutating func handleEnglish(_ event: InputEvent) -> [OutputAction] {
        switch event {
        case .key(let character): return [.insert(String(character))]
        case .shiftedKey(let character): return [.insert(String(character).uppercased())]
        case .space, .swipeUpSpace: return [.insert(" ")]
        case .returnKey: return [.insert("\n")]
        case .backspace: return [.deleteBackward]
        case .selectCandidate, .contextChanged, .toggleInputMode: return []
        }
    }

    private mutating func handleKey(_ character: Character) -> [OutputAction] {
        let key = character.lowercased().first ?? character
        guard codeKeys.contains(key) else {
            // 非字根鍵（數字、其他符號）：送出組字中的內容後直接輸入；符號轉全形（FR-K09）
            let text = fullWidthPunctuation ? punctuation.convert(character) : String(character)
            return commitForPassthrough() + [.insert(text)]
        }
        guard state.code.count < Self.maxBufferLength else { return [] }
        update(code: state.code + String(key))
        return markedAction()
    }

    private mutating func handleSpace() -> [OutputAction] {
        guard state.isComposing else { return [.insert(" ")] }
        guard let first = state.candidates.first else {
            // 錯碼或尚未打完：不送出，保留字根讓使用者修正（FR-K07）
            return []
        }
        return commit(first)
    }

    private mutating func handleBackspace() -> [OutputAction] {
        guard state.isComposing else { return [.deleteBackward] }
        let shorter = String(state.code.dropLast())
        if shorter.isEmpty {
            state = .idle
            return display == .inline ? [.setMarked("")] : []
        }
        update(code: shorter)
        return markedAction()
    }

    // MARK: - 共用

    private mutating func update(code: String) {
        let candidates = source.candidates(for: code)
        let status: ComposerState.Status
        if !candidates.isEmpty {
            status = .matched
        } else if code.count > source.maxCodeLength {
            status = .overLength
        } else if source.hasCode(withPrefix: code) {
            status = .incomplete
        } else {
            status = .invalid
        }
        state = ComposerState(code: code, candidates: candidates, status: status)
    }

    private mutating func commit(_ text: String) -> [OutputAction] {
        state = .idle
        return [.insert(text)]
    }

    /// 遇到非字根輸入時，先把組字內容送出：有候選送第一候選，否則送原始字母。
    private mutating func commitForPassthrough() -> [OutputAction] {
        guard state.isComposing else { return [] }
        return commit(state.candidates.first ?? state.code)
    }

    private func markedAction() -> [OutputAction] {
        display == .inline ? [.setMarked(state.code)] : []
    }
}
