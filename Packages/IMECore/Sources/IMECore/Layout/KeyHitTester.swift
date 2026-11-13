import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// 觸點 → 按鍵：按鍵之間的縫隙、鍵盤邊緣都歸屬最近的鍵（FR-U20）。
public struct KeyHitTester {
    public let frames: [KeyFrame]
    /// 按鍵區範圍。範圍內的觸點一律歸屬最近的鍵（FR-U20：鍵盤內不能有按了沒反應的位置）。
    public let bounds: CGRect?
    /// 範圍外的觸點，離最近的鍵超過這個距離（pt）就視為沒按到任何鍵。
    public let maxDistance: CGFloat

    public init(frames: [KeyFrame], bounds: CGRect? = nil, maxDistance: CGFloat = 24) {
        self.frames = frames.filter { $0.key.isTouchable }
        self.bounds = bounds
        self.maxDistance = maxDistance
    }

    public func key(at point: CGPoint) -> KeyFrame? {
        var best: KeyFrame?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        var bestCenter = CGFloat.greatestFiniteMagnitude

        for frame in frames {
            let rect = frame.rect
            let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
            let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
            let distance = dx * dx + dy * dy
            let center = abs(point.x - rect.midX)

            // 距離相同（例如正好在縫隙中央）時，取水平中心較近的鍵
            let closer = distance < bestDistance - 0.0001
            let tie = abs(distance - bestDistance) <= 0.0001 && center < bestCenter
            if closer || tie {
                best = frame
                bestDistance = distance
                bestCenter = center
            }
        }

        guard let hit = best else { return nil }
        let inside = bounds?.contains(point) ?? false
        guard inside || bestDistance <= maxDistance * maxDistance else { return nil }
        return hit
    }
}
