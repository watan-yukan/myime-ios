import Foundation

/// 候選列一列放得下幾個候選（FR-K06、FR-U21）。
///
/// 文字寬度由 UI 量測後以閉包傳入，引擎本身不依賴字型與 UIKit。
public enum CandidateLayout {
    /// 從頭開始，回傳能完整放進 `availableWidth` 的候選數。
    ///
    /// - Parameters:
    ///   - reservedWidth: 保留給右側展開鈕、英文選項等的寬度。
    ///   - itemPadding: 每個候選左右內距合計。
    ///   - minItemWidth: 每格最小寬度（單字也至少這麼寬，方便點選）。
    ///   - spacing: 候選之間的間距。
    ///   - textWidth: 量測字串寬度的函式。
    /// - Returns: 至少 1（有候選時第一個一定顯示，過寬時由 UI 截斷）。
    public static func fittingCount(
        _ candidates: [String],
        availableWidth: Double,
        reservedWidth: Double = 0,
        itemPadding: Double = 16,
        minItemWidth: Double = 36,
        spacing: Double = 0,
        textWidth: (String) -> Double
    ) -> Int {
        guard !candidates.isEmpty else { return 0 }
        let usable = availableWidth - reservedWidth
        var used = 0.0
        var count = 0
        for candidate in candidates {
            let width = max(minItemWidth, textWidth(candidate) + itemPadding)
            let next = used + (count == 0 ? 0 : spacing) + width
            if next > usable { break }
            used = next
            count += 1
        }
        return max(count, 1)
    }
}
