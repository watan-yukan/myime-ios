import Foundation

/// 嘸蝦米組字狀態機（Issue #4、#6、#7，FR-K02~K14、U22）。
///
/// 純邏輯：輸入 `InputEvent`，更新 `state` 並回傳要對輸入框做的 `OutputAction`，
/// 不接觸 UIKit，所有行為都能單元測試。
///
/// 中英混打（#8）：候選列英文選項、Shift 直輸大寫、空白上滑、超過碼長不判錯碼。
public struct Composer {
    /// 組字內容最長保留的字母數（超過碼長仍保留，供送出英文，FR-E05）。
    public static let maxBufferLength = 32

    public private(set) var state: ComposerState = .idle
    /// 最近一次 `handle` 送出的候選字（空白、點選、數字選字、遇到非字根時送出第一候選）；
    /// 送出英文字母或沒有送出時為 nil。每次 `handle` 開始時清除。
    public private(set) var lastCommittedCandidate: String?
    public var display: ComposingDisplay
    /// 目前輸入模式（FR-K08），以 `.toggleInputMode` 切換。
    public private(set) var mode: InputMode = .chinese
    /// 中文模式下，非字根的半形符號轉成全形（FR-K09）。
    public var fullWidthPunctuation = true
    /// 數字列開啟時，組字中的數字鍵直接選字（FR-U22，預設關閉）。
    public var numberRowSelection = false
    /// 數字選字的對應：`1` 選第一個…`0` 選第十個（TBD-14，依原生規則決定）。
    public var selectionKeys = SelectionKeys.digitsFromOne
    /// 候選列目前顯示的第一個候選位置（展開候選表翻頁時由 UI 設定）；數字選字以此為起點。
    /// 每次字根改變都會歸零。
    public var selectionWindowStart = 0
    /// 空白鍵上滑直輸英文（FR-E03）；關閉時 `.swipeUpSpace` 不動作（FR-E04，預設開啟）。
    public var spaceSwipeUpEnglish = true
    /// 以英文選項或空白上滑送出英文後，自動補一個空格（FR-E04，預設關閉）。
    public var appendSpaceAfterEnglish = false
    /// 送出英文時把第一個字母轉大寫（由 UI 依 `AutoCapitalization` 判斷後設定，FR-E07）。
    public var capitalizeEnglishSend = false
    /// 雙空白句點（FR-U08，預設開啟）。需要 `textBeforeCursor` 才能判斷。
    public var doubleSpacePeriod = true
    /// 游標前的文字；鍵盤每次事件前以 `documentContextBeforeInput` 更新。
    public var textBeforeCursor: String?

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
        lastCommittedCandidate = nil
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
            // Shift + 字母：先送出組字中的內容，再直輸大寫，不進入組字（FR-E02）
            return commitForPassthrough() + [.insert(String(character).uppercased())]
        case .space:
            return handleSpace()
        case .backspace:
            return handleBackspace()
        case .selectCandidate(let index):
            guard state.isComposing, state.candidates.indices.contains(index) else { return [] }
            return commit(state.candidates[index])
        case .returnKey:
            // 組字中按 Return 送出原始字母，不換行（FR-K12、TBD-17）
            guard state.isComposing else { return [.insert("\n")] }
            return commit(state.code)
        case .swipeUpSpace:
            guard spaceSwipeUpEnglish else { return [] }
            guard state.isComposing else { return [.insert(" ")] }
            return sendEnglish()
        case .selectEnglishOption:
            guard state.isComposing else { return [] }
            return sendEnglish()
        case .contextChanged:
            // 游標移動或切換欄位：清除組字，不送出（FR-K14）
            punctuation.reset()
            selectionWindowStart = 0
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
        case .space: return idleSpace(mode: .english)
        case .swipeUpSpace: return [.insert(" ")]
        case .returnKey: return [.insert("\n")]
        case .backspace: return [.deleteBackward]
        case .selectCandidate, .selectEnglishOption, .contextChanged, .toggleInputMode: return []
        }
    }

    /// 把組字內容當英文送出（FR-E01、E03、E04、E07）。
    private mutating func sendEnglish() -> [OutputAction] {
        var text = state.code
        if capitalizeEnglishSend, let first = text.first {
            text = first.uppercased() + text.dropFirst()
        }
        if appendSpaceAfterEnglish { text += " " }
        return commit(text)
    }

    private mutating func handleKey(_ character: Character) -> [OutputAction] {
        let key = character.lowercased().first ?? character
        if numberRowSelection, state.isComposing, !codeKeys.contains(key),
           let offset = selectionKeys.pageOffset(for: key) {
            // 數字列選字（FR-U22）：該位置沒有候選時不動作，避免誤送數字
            let index = selectionWindowStart + offset
            guard state.candidates.indices.contains(index) else { return [] }
            return commit(state.candidates[index])
        }
        guard codeKeys.contains(key) else {
            // 非字根鍵（數字、其他符號）：送出組字中的內容後直接輸入；符號轉全形（FR-K09）
            let text = fullWidthPunctuation ? punctuation.convert(character) : String(character)
            return commitForPassthrough() + [.insert(text)]
        }
        guard state.code.count < Self.maxBufferLength else { return [] }
        update(code: state.code + String(key))
        return markedAction()
    }

    /// 沒在組字時的空白：依雙空白句點規則決定輸出（FR-U08）。
    private func idleSpace(mode: InputMode) -> [OutputAction] {
        guard doubleSpacePeriod else { return [.insert(" ")] }
        switch DoubleSpace.result(textBeforeCursor: textBeforeCursor, mode: mode) {
        case .insertSpace:
            return [.insert(" ")]
        case .replace(let deleteCount, let text):
            return Array(repeating: OutputAction.deleteBackward, count: deleteCount) + [.insert(text)]
        }
    }

    private mutating func handleSpace() -> [OutputAction] {
        guard state.isComposing else { return idleSpace(mode: .chinese) }
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
        selectionWindowStart = 0
    }

    private mutating func commit(_ text: String) -> [OutputAction] {
        // 送出的是候選字（不是英文字母）時記下來，讓 UI 顯示「剛送出的字」提示
        lastCommittedCandidate = state.candidates.contains(text) ? text : nil
        state = .idle
        selectionWindowStart = 0
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
