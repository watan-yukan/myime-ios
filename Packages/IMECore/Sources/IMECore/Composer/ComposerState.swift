import Foundation

/// 組字狀態（鍵盤 UI 依此畫組字區與候選列）。
public struct ComposerState: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        /// 沒有在組字。
        case idle
        /// 有完全相符的候選字。
        case matched
        /// 還沒有完全相符的字，但仍有字根以此開頭（繼續打即可，例如假名碼打到一半）。
        case incomplete
        /// 錯碼：沒有任何字根以此開頭，候選列顯示「無此字」（FR-K07）。
        case invalid
        /// 超過碼表最長碼長：不判錯碼，保留字母供送出英文（FR-E05）。
        case overLength
    }

    /// 目前的字根（小寫）。
    public var code: String
    /// 完全相符的候選，依碼表原始順序（FR-K05）。
    public var candidates: [String]
    public var status: Status

    public var isComposing: Bool { !code.isEmpty }

    /// 候選列最後固定的英文選項（FR-E01）：目前已輸入的原始字母；沒在組字時為 nil。
    public var englishOption: String? { isComposing ? code : nil }

    public static let idle = ComposerState(code: "", candidates: [], status: .idle)
}

/// 組字內容顯示位置（FR-K13）。
public enum ComposingDisplay: String, Codable, Equatable, Sendable {
    /// 顯示在鍵盤上方組字區（預設）；不對輸入框送 marked text。
    case bar
    /// 顯示在輸入框游標處（`setMarkedText`）。
    case inline
}
