import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// 按鍵在版面中的位置（列、列內第幾個項目；`spacer` 也佔一個編號，對應 JSON 順序）。
public struct KeyID: Hashable, Sendable {
    public let row: Int
    public let index: Int

    public init(row: Int, index: Int) {
        self.row = row
        self.index = index
    }
}

public struct KeyFrame: Equatable {
    public let id: KeyID
    public let key: LayoutKey
    public let rect: CGRect

    public init(id: KeyID, key: LayoutKey, rect: CGRect) {
        self.id = id
        self.key = key
        self.rect = rect
    }
}

public struct PageFrames: Equatable {
    /// 所有可按的鍵（不含 `spacer`）。
    public let frames: [KeyFrame]
    /// 按鍵區大小（含上下留白）。
    public let size: CGSize
    /// 1 個「字母鍵寬」換算成幾 pt。
    public let unit: CGFloat

    public init(frames: [KeyFrame], size: CGSize, unit: CGFloat) {
        self.frames = frames
        self.size = size
        self.unit = unit
    }

    /// 按鍵區範圍，供 `KeyHitTester` 判斷「鍵盤內」。
    public var bounds: CGRect { CGRect(origin: .zero, size: size) }

    /// 這一頁的觸控判斷器。
    public func hitTester(maxDistance: CGFloat = 24) -> KeyHitTester {
        KeyHitTester(frames: frames, bounds: bounds, maxDistance: maxDistance)
    }
}

/// 版面引擎：依容器寬度與尺寸參數，算出每個鍵的位置（Issue #13，FR-U13、NFR-11）。
///
/// 算法（驗算見 docs/06_資料格式.md 1.2）：
/// - 每一列各自解出 1 個字母鍵寬：`(可用寬度 − 間距總和) ÷ 單位總和`，讓每列左右切齊；
///   `PageFrames.unit` 回傳第一列的值
/// - 列內的鍵由左而右排列，真正的鍵之間固定留 `keyGap`；`spacer` 的寬度加在相鄰兩鍵的間距上
/// - `inset` 為左右縮排：每側 `inset × (unit + keyGap)`
public enum LayoutEngine {
    public static func frames(
        for page: LayoutPage,
        metrics: OrientationMetrics,
        containerWidth: CGFloat,
        landscape: Bool
    ) -> PageFrames {
        let rows = landscape ? (page.landscapeRows ?? page.rows) : page.rows
        guard let reference = rows.first else {
            return PageFrames(frames: [], size: .zero, unit: 0)
        }

        let sideMargin = CGFloat(metrics.sideMargin)
        let gap = CGFloat(metrics.keyGap)
        let rowGap = CGFloat(metrics.rowGap)
        let keyHeight = CGFloat(metrics.keyHeight)
        let topInset = CGFloat(metrics.topInset)

        let available = metrics.contentWidth.map { min(CGFloat($0), containerWidth) } ?? containerWidth
        let originX = (containerWidth - available) / 2 + sideMargin
        let inner = available - sideMargin * 2
        let unit = solveUnit(reference, inner: inner, gap: gap)

        var frames: [KeyFrame] = []
        for (rowIndex, row) in rows.enumerated() {
            let y = topInset + CGFloat(rowIndex) * (keyHeight + rowGap)
            // 有 `alignWith` 的列：對齊鍵照抄上方鍵的位置，其餘鍵分段填滿（FR-U26）
            if let aligned = alignedRow(
                row, rowIndex: rowIndex, y: y, keyHeight: keyHeight,
                left: originX, right: originX + inner, gap: gap, placed: frames
            ) {
                frames.append(contentsOf: aligned)
                continue
            }
            // 每一列各自解出鍵寬，任何螢幕寬度下每列都左右切齊（各列字母鍵寬相差 < 0.1 pt）
            let rowUnit = solveUnit(row, inner: inner, gap: gap)
            var x = originX + CGFloat(row.inset) * (rowUnit + gap)
            var pendingSpacer: CGFloat = 0
            var placedAny = false

            for (index, key) in row.keys.enumerated() {
                if key.type == .spacer {
                    pendingSpacer += CGFloat(key.width) * rowUnit
                    continue
                }
                if placedAny { x += gap }
                x += pendingSpacer
                pendingSpacer = 0
                let width = CGFloat(key.width) * rowUnit
                frames.append(KeyFrame(
                    id: KeyID(row: rowIndex, index: index),
                    key: key,
                    rect: CGRect(x: x, y: y, width: width, height: keyHeight)
                ))
                x += width
                placedAny = true
            }
        }

        let rowCount = CGFloat(rows.count)
        let height = topInset + rowCount * keyHeight + max(rowCount - 1, 0) * rowGap + CGFloat(metrics.bottomInset)
        return PageFrames(frames: frames, size: CGSize(width: containerWidth, height: height), unit: unit)
    }

    /// 排有對齊鍵的列：對齊鍵的 x 與寬度照抄上方同 `output` 的鍵；對齊鍵把這一列切成幾段，
    /// 每段裡的鍵依 `width` 比例填滿該段（段與段、鍵與鍵之間仍留 `keyGap`）。
    /// 找不到要對齊的鍵時回傳 nil，改用一般排法。
    static func alignedRow(
        _ row: LayoutRow, rowIndex: Int, y: CGFloat, keyHeight: CGFloat,
        left: CGFloat, right: CGFloat, gap: CGFloat, placed: [KeyFrame]
    ) -> [KeyFrame]? {
        var anchors: [(index: Int, rect: CGRect)] = []
        for (index, key) in row.keys.enumerated() {
            guard let target = key.alignWith else { continue }
            guard let match = placed.first(where: { $0.key.output == target }) else { return nil }
            anchors.append((index, match.rect))
        }
        guard !anchors.isEmpty else { return nil }

        var result: [KeyFrame] = []
        func fill(_ range: Range<Int>, from start: CGFloat, to end: CGFloat) {
            let items = range.map { (index: $0, key: row.keys[$0]) }
            let realCount = items.filter { $0.key.isTouchable }.count
            guard realCount > 0 else { return }
            let units = items.reduce(0.0) { $0 + $1.key.width }
            guard units > 0 else { return }
            let unit = max(0, (end - start - CGFloat(realCount - 1) * gap) / CGFloat(units))
            var x = start
            var pendingSpacer: CGFloat = 0
            var placedAny = false
            for (index, key) in items {
                if key.type == .spacer {
                    pendingSpacer += CGFloat(key.width) * unit
                    continue
                }
                if placedAny { x += gap }
                x += pendingSpacer
                pendingSpacer = 0
                let width = CGFloat(key.width) * unit
                result.append(KeyFrame(
                    id: KeyID(row: rowIndex, index: index), key: row.keys[index],
                    rect: CGRect(x: x, y: y, width: width, height: keyHeight)))
                x += width
                placedAny = true
            }
        }

        var segmentStart = 0
        var segmentLeft = left
        for anchor in anchors {
            fill(segmentStart..<anchor.index, from: segmentLeft, to: anchor.rect.minX - gap)
            result.append(KeyFrame(
                id: KeyID(row: rowIndex, index: anchor.index), key: row.keys[anchor.index],
                rect: CGRect(x: anchor.rect.minX, y: y, width: anchor.rect.width, height: keyHeight)))
            segmentStart = anchor.index + 1
            segmentLeft = anchor.rect.maxX + gap
        }
        fill(segmentStart..<row.keys.count, from: segmentLeft, to: right)
        return result
    }

    /// 由參考列解出 1 個字母鍵寬。
    static func solveUnit(_ row: LayoutRow, inner: CGFloat, gap: CGFloat) -> CGFloat {
        let realKeys = row.keys.filter(\.isTouchable).count
        guard realKeys > 0 else { return 0 }
        let units = row.keys.reduce(0.0) { $0 + $1.width } + row.inset * 2
        let gaps = CGFloat(realKeys - 1) + CGFloat(row.inset) * 2
        guard units > 0 else { return 0 }
        return max(0, (inner - gaps * gap) / CGFloat(units))
    }
}
