import Foundation

/// 鍵盤對輸入框的操作（鍵盤擴充以 `UITextDocumentProxy` 實作；測試以假的輸入框實作）。
public protocol TextOutput: AnyObject {
    func insertText(_ text: String)
    func deleteBackward()
    /// 顯示（或更新）輸入框中的組字底線文字；傳空字串代表清掉。
    func setMarkedText(_ text: String)
    /// 把目前的組字文字確定下來。
    func unmarkText()
    /// 游標前的文字（`documentContextBeforeInput`）。
    var textBeforeCursor: String? { get }
}

/// 長按 ⌫ 時「先刪字、再刪詞」（FR-U09）。
public enum BackspaceWord {
    /// 連續刪除幾次之後，改為一次刪一個詞。
    public static let wordThreshold = 8

    /// 目前這一次要刪除幾個字元：句尾的空白，加上前面的一個「詞」。
    /// 中日文每次只刪一個字（沒有空白分詞，整段刪太危險）；英文與數字刪整個詞；符號刪一個。
    public static func deleteCount(textBeforeCursor: String?) -> Int {
        guard let text = textBeforeCursor, !text.isEmpty else { return 1 }
        let characters = Array(text)
        var index = characters.count - 1
        var count = 0

        while index >= 0, characters[index] == " " || characters[index] == "\t" {
            count += 1
            index -= 1
        }
        guard index >= 0 else { return max(count, 1) }

        let last = characters[index]
        if last.isNewline { return count + 1 }
        if isCJK(last) || !(last.isLetter || last.isNumber) { return count + 1 }

        while index >= 0, characters[index].isLetter || characters[index].isNumber, !isCJK(characters[index]) {
            count += 1
            index -= 1
        }
        return count
    }

    private static func isCJK(_ character: Character) -> Bool {
        guard let value = character.unicodeScalars.first?.value else { return false }
        return (0x2E80...0x9FFF).contains(value) || (0xF900...0xFAFF).contains(value)
            || (0x20000...0x2FA1F).contains(value)
    }
}
