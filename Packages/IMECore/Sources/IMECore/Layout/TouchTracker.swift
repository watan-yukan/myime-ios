import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// 觸控層要求畫面做的事。
public enum TouchAction: Equatable {
    /// 按下或滑入：高亮按鍵、顯示放大預覽。
    case highlight(KeyFrame)
    /// 取消高亮（滑開、取消）。
    case unhighlight(KeyFrame)
    /// 確定輸出這個鍵，同時結束高亮。`byRollover` 為 true 代表因為另一根手指按下而提早送出。
    case commit(KeyFrame, byRollover: Bool)
}

/// 多指觸控與快打（Issue #14，FR-U19、U20、NFR-16；Spike 0.15 已驗證的規則）。
///
/// - 每根手指獨立追蹤；第二根手指按下時，先把前面還沒送出的鍵依順序送出（`byRollover: true`），
///   即使第一根手指還沒抬起，字也不會漏、不會亂序。
/// - 手指在按下期間滑到別的鍵，改為那個鍵；滑出鍵盤範圍則取消。
/// - 手指抬起時，才送出目前高亮的鍵。
public struct TouchTracker {
    private let hitTester: KeyHitTester
    private var pending: [Int: KeyFrame] = [:]
    private var order: [Int] = []

    public init(hitTester: KeyHitTester) {
        self.hitTester = hitTester
    }

    /// 目前還沒送出的觸點數。
    public var activeTouchCount: Int { pending.count }

    public mutating func began(id: Int, at point: CGPoint) -> [TouchAction] {
        var actions = flushPending()
        if let frame = hitTester.key(at: point) {
            pending[id] = frame
            order.append(id)
            actions.append(.highlight(frame))
        }
        return actions
    }

    public mutating func moved(id: Int, to point: CGPoint) -> [TouchAction] {
        guard let current = pending[id] else { return [] }
        let next = hitTester.key(at: point)
        if next?.id == current.id { return [] }
        if let next {
            pending[id] = next
            return [.unhighlight(current), .highlight(next)]
        }
        pending[id] = nil
        order.removeAll { $0 == id }
        return [.unhighlight(current)]
    }

    public mutating func ended(id: Int) -> [TouchAction] {
        guard let frame = pending.removeValue(forKey: id) else { return [] }
        order.removeAll { $0 == id }
        return [.commit(frame, byRollover: false)]
    }

    public mutating func cancelled(id: Int) -> [TouchAction] {
        guard let frame = pending.removeValue(forKey: id) else { return [] }
        order.removeAll { $0 == id }
        return [.unhighlight(frame)]
    }

    /// 鍵盤消失或換頁時呼叫：取消所有高亮，不送出。
    public mutating func reset() -> [TouchAction] {
        let actions = order.compactMap { id in pending[id].map(TouchAction.unhighlight) }
        pending.removeAll()
        order.removeAll()
        return actions
    }

    private mutating func flushPending() -> [TouchAction] {
        let actions = order.compactMap { id in
            pending[id].map { TouchAction.commit($0, byRollover: true) }
        }
        pending.removeAll()
        order.removeAll()
        return actions
    }
}
