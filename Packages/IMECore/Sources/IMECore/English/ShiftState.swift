import Foundation

/// Shift 鍵狀態（FR-U09）：單擊一次性大寫、雙擊鎖定（Caps Lock）。
///
/// 純邏輯；時間由呼叫端傳入，方便測試。
public struct ShiftState: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        case off
        /// 只影響下一個字母。
        case once
        /// 鎖定，直到再按 Shift。
        case locked
    }

    /// 兩次點擊算雙擊的最大間隔（秒）。
    public static let doubleTapWindow: TimeInterval = 0.35

    public private(set) var mode: Mode = .off
    private var lastTapTime: TimeInterval?

    public init() {}

    /// 下一個字母是否要大寫。
    public var isUppercase: Bool { mode != .off }

    /// 點一下 Shift。
    public mutating func tap(at time: TimeInterval) {
        if let last = lastTapTime, time - last <= Self.doubleTapWindow {
            // 雙擊：鎖定大寫
            mode = .locked
            lastTapTime = nil
            return
        }
        switch mode {
        case .off: mode = .once
        case .once, .locked: mode = .off
        }
        lastTapTime = time
    }

    /// 輸入一個字元後呼叫：一次性大寫用完即關閉，鎖定維持。
    public mutating func didTypeCharacter() {
        if mode == .once { mode = .off }
        lastTapTime = nil
    }

    /// 自動大寫（句首）：只在目前是關閉時打開一次性大寫，不覆蓋使用者的操作。
    public mutating func applyAutoCapitalization(_ shouldCapitalize: Bool) {
        if shouldCapitalize, mode == .off { mode = .once }
    }

    public mutating func reset() {
        mode = .off
        lastTapTime = nil
    }
}
