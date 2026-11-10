import Foundation

/// 鍵盤送進引擎的事件（docs/03_架構設計.md 3.2）。
/// 狀態機本身於 Issue #4 實作；這裡先固定介面，讓 UI 與引擎可以分頭開發。
public enum InputEvent: Equatable, Sendable {
    /// 字母與 `,` `.` `'` 等字根鍵。
    case key(Character)
    /// Shift + 字母：直輸大寫英文（FR-E02）。
    case shiftedKey(Character)
    case space
    case returnKey
    case backspace
    /// 點選候選列第 n 個（0 起算）。
    case selectCandidate(Int)
    /// 空白鍵上滑：組字內容當英文送出（FR-E03）。
    case swipeUpSpace
    /// 游標移動、切換欄位、收起鍵盤（FR-K14）。
    case contextChanged
    /// 中 / 英切換鍵（FR-K08）。
    case toggleInputMode
    /// 點選候選列最後一格的英文選項，把組字內容當英文送出（FR-E01）。
    case selectEnglishOption
}

/// 輸入模式（FR-K08）。
public enum InputMode: Equatable, Sendable {
    /// 嘸蝦米組字。
    case chinese
    /// 標準英文，按鍵直接輸出。
    case english
}

/// 引擎要求鍵盤對輸入框做的動作；只有鍵盤的 TextOutput 會實際執行。
public enum OutputAction: Equatable, Sendable {
    /// 送出文字。若輸入框有 marked text，以此文字**取代**它並確定（同 `insertText`）。
    case insert(String)
    case deleteBackward
    /// 以此文字取代目前的 marked text（組字顯示於輸入框模式，FR-K13）。
    case setMarked(String)
    /// 移除 marked text，不送出任何文字。
    case clearMarked
}
