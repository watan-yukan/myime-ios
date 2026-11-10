import XCTest
@testable import IMECore

/// 觸控核心：最近的鍵、多指快打（Issue #14，FR-U19、U20）。
final class TouchTests: XCTestCase {

    /// 一列四個 40×40 的鍵，間距 10：a[0,40] b[50,90] c[100,140] d[150,190]；下面一列 e[0,40]。
    private func makeFrames() -> [KeyFrame] {
        func frame(_ row: Int, _ index: Int, _ char: String, x: CGFloat, y: CGFloat) -> KeyFrame {
            KeyFrame(
                id: KeyID(row: row, index: index), key: LayoutKey(char: char),
                rect: CGRect(x: x, y: y, width: 40, height: 40))
        }
        return [
            frame(0, 0, "a", x: 0, y: 0), frame(0, 1, "b", x: 50, y: 0),
            frame(0, 2, "c", x: 100, y: 0), frame(0, 3, "d", x: 150, y: 0),
            frame(1, 0, "e", x: 0, y: 50),
        ]
    }

    private func hitTester(maxDistance: CGFloat = 24) -> KeyHitTester {
        KeyHitTester(frames: makeFrames(), maxDistance: maxDistance)
    }

    private func output(_ frame: KeyFrame?) -> String? { frame?.key.output }

    // MARK: - 最近的鍵（FR-U20）

    func testPointInsideKey() {
        XCTAssertEqual(output(hitTester().key(at: CGPoint(x: 20, y: 20))), "a")
        XCTAssertEqual(output(hitTester().key(at: CGPoint(x: 120, y: 10))), "c")
    }

    func testGapBelongsToNearestKey() {
        let tester = hitTester()
        XCTAssertEqual(output(tester.key(at: CGPoint(x: 43, y: 20))), "a", "縫隙偏左 → a")
        XCTAssertEqual(output(tester.key(at: CGPoint(x: 47, y: 20))), "b", "縫隙偏右 → b")
        XCTAssertEqual(output(tester.key(at: CGPoint(x: 20, y: 46))), "e", "列間縫隙偏下 → e")
        XCTAssertEqual(output(tester.key(at: CGPoint(x: 20, y: 43))), "a", "列間縫隙偏上 → a")
    }

    func testExactMiddleOfGapUsesHorizontalCenterTieBreak() {
        // 正好在 a、b 中間（x = 45）：到兩鍵距離相同，取水平中心較近的鍵
        let tester = hitTester()
        XCTAssertNotNil(tester.key(at: CGPoint(x: 45, y: 20)))
        XCTAssertEqual(output(tester.key(at: CGPoint(x: 45, y: 20))), "a", "距離與中心都相同時取先出現的鍵，結果要穩定")
    }

    func testEdgesExtendToNearestKey() {
        let tester = hitTester()
        XCTAssertEqual(output(tester.key(at: CGPoint(x: -10, y: 20))), "a", "左邊緣外 → 最左的鍵")
        XCTAssertEqual(output(tester.key(at: CGPoint(x: 200, y: 20))), "d", "右邊緣外 → 最右的鍵")
        XCTAssertEqual(output(tester.key(at: CGPoint(x: 20, y: -10))), "a", "上方 → 第一列")
        XCTAssertEqual(output(tester.key(at: CGPoint(x: 20, y: 100))), "e", "下方 → 最下列")
    }

    func testTooFarIsNotAKey() {
        XCTAssertNil(hitTester(maxDistance: 24).key(at: CGPoint(x: 400, y: 400)))
        XCTAssertNil(hitTester(maxDistance: 5).key(at: CGPoint(x: -10, y: 20)))
    }

    func testSpacersAreNeverHit() {
        let spacer = KeyFrame(
            id: KeyID(row: 0, index: 9), key: LayoutKey(type: .spacer),
            rect: CGRect(x: 300, y: 0, width: 40, height: 40))
        let tester = KeyHitTester(frames: makeFrames() + [spacer], maxDistance: 1000)
        XCTAssertNotEqual(tester.key(at: CGPoint(x: 320, y: 20))?.key.type, .spacer)
    }

    func testRealLayoutHasNoDeadZoneInsideKeyboard() throws {
        // 以真實版面掃過整個鍵盤範圍，任何一點都要能歸屬到某個鍵
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        let layout = try KeyboardLayoutFile.load(contentsOf: url.appendingPathComponent("Shared/Layouts/iphone.json"))
        let page = try XCTUnwrap(layout.page("alpha"))
        let metrics = layout.metrics.metrics(landscape: false)
        let f = LayoutEngine.frames(for: page, metrics: metrics, containerWidth: 430, landscape: false)
        let tester = f.hitTester()

        var misses = 0
        var x: CGFloat = 0
        while x < 430 {
            var y: CGFloat = 0
            while y < f.size.height {
                if tester.key(at: CGPoint(x: x, y: y)) == nil { misses += 1 }
                y += 2
            }
            x += 2
        }
        XCTAssertEqual(misses, 0, "鍵盤範圍內不應有按了沒反應的位置（FR-U20）")

        // 第 2 列最左邊的縮排區（離 A 鍵 27 pt）也要按得到 A，而不是沒反應
        let leftInset = tester.key(at: CGPoint(x: 1, y: 8 + 56 + 22))
        XCTAssertEqual(leftInset?.key.output, "a")
        // 範圍外太遠則不算
        XCTAssertNil(tester.key(at: CGPoint(x: -100, y: 80)))
    }

    func testBoundsOverrideMaxDistanceOnlyInside() {
        let frames = makeFrames()
        let inside = KeyHitTester(frames: frames, bounds: CGRect(x: 0, y: 0, width: 500, height: 500), maxDistance: 5)
        XCTAssertNotNil(inside.key(at: CGPoint(x: 400, y: 400)), "範圍內即使很遠也歸屬最近的鍵")
        XCTAssertNil(inside.key(at: CGPoint(x: 600, y: 400)), "超出範圍則受 maxDistance 限制")
    }

    // MARK: - 多指快打（FR-U19）

    private func tracker() -> TouchTracker {
        TouchTracker(hitTester: hitTester())
    }

    private func key(_ id: Int) -> KeyFrame { makeFrames()[id] }

    func testSingleTapCommitsOnRelease() {
        var t = tracker()
        XCTAssertEqual(t.began(id: 1, at: CGPoint(x: 20, y: 20)), [.highlight(key(0))])
        XCTAssertEqual(t.activeTouchCount, 1)
        XCTAssertEqual(t.ended(id: 1), [.commit(key(0), byRollover: false)])
        XCTAssertEqual(t.activeTouchCount, 0)
    }

    func testSecondFingerCommitsFirstImmediatelyInOrder() {
        var t = tracker()
        _ = t.began(id: 1, at: CGPoint(x: 20, y: 20))           // 按住 a
        let actions = t.began(id: 2, at: CGPoint(x: 70, y: 20))  // 第二指按 b
        XCTAssertEqual(actions, [.commit(key(0), byRollover: true), .highlight(key(1))],
                       "a 先送出，再高亮 b，順序不亂")
        XCTAssertEqual(t.ended(id: 1), [], "a 已送出，抬起時不重複")
        XCTAssertEqual(t.ended(id: 2), [.commit(key(1), byRollover: false)])
    }

    func testThreeFingersKeepArrivalOrder() {
        var t = tracker()
        _ = t.began(id: 1, at: CGPoint(x: 20, y: 20))
        _ = t.began(id: 2, at: CGPoint(x: 70, y: 20))
        let actions = t.began(id: 3, at: CGPoint(x: 120, y: 20))
        XCTAssertEqual(actions, [.commit(key(1), byRollover: true), .highlight(key(2))])
        XCTAssertEqual(t.ended(id: 3), [.commit(key(2), byRollover: false)])
    }

    func testFastTypingNeverLosesOrReordersKeys() {
        // 模擬快打：每個手指在下一指按下後才抬起，輸出順序必須等於按下順序
        var t = tracker()
        var committed: [String] = []
        func apply(_ actions: [TouchAction]) {
            for case .commit(let frame, _) in actions { committed.append(frame.key.output ?? "") }
        }
        let sequence: [(Int, CGPoint)] = [
            (1, CGPoint(x: 20, y: 20)), (2, CGPoint(x: 70, y: 20)), (3, CGPoint(x: 120, y: 20)),
            (4, CGPoint(x: 170, y: 20)), (5, CGPoint(x: 20, y: 70)),
        ]
        for (id, point) in sequence {
            apply(t.began(id: id, at: point))
            if id >= 2 { apply(t.ended(id: id - 1)) }
        }
        apply(t.ended(id: 5))
        XCTAssertEqual(committed, ["a", "b", "c", "d", "e"])
    }

    // MARK: - 滑動與取消

    func testSlidingToAnotherKeyRetargets() {
        var t = tracker()
        _ = t.began(id: 1, at: CGPoint(x: 20, y: 20))
        XCTAssertEqual(t.moved(id: 1, to: CGPoint(x: 70, y: 20)), [.unhighlight(key(0)), .highlight(key(1))])
        XCTAssertEqual(t.moved(id: 1, to: CGPoint(x: 75, y: 25)), [], "還在同一個鍵")
        XCTAssertEqual(t.ended(id: 1), [.commit(key(1), byRollover: false)], "送出滑到的那個鍵")
    }

    func testSlidingOutsideCancels() {
        var t = tracker()
        _ = t.began(id: 1, at: CGPoint(x: 20, y: 20))
        XCTAssertEqual(t.moved(id: 1, to: CGPoint(x: 500, y: 500)), [.unhighlight(key(0))])
        XCTAssertEqual(t.ended(id: 1), [])
        XCTAssertEqual(t.activeTouchCount, 0)
    }

    func testCancelledTouchDoesNotCommit() {
        var t = tracker()
        _ = t.began(id: 1, at: CGPoint(x: 20, y: 20))
        XCTAssertEqual(t.cancelled(id: 1), [.unhighlight(key(0))])
        XCTAssertEqual(t.ended(id: 1), [])
    }

    func testTouchOutsideKeyboardIsIgnored() {
        var t = tracker()
        XCTAssertEqual(t.began(id: 1, at: CGPoint(x: 900, y: 900)), [])
        XCTAssertEqual(t.activeTouchCount, 0)
        XCTAssertEqual(t.ended(id: 1), [])
    }

    func testOutsideTouchStillFlushesPendingKeys() {
        var t = tracker()
        _ = t.began(id: 1, at: CGPoint(x: 20, y: 20))
        XCTAssertEqual(t.began(id: 2, at: CGPoint(x: 900, y: 900)), [.commit(key(0), byRollover: true)])
    }

    func testResetUnhighlightsEverythingWithoutCommitting() {
        var t = tracker()
        _ = t.began(id: 1, at: CGPoint(x: 20, y: 20))
        _ = t.began(id: 2, at: CGPoint(x: 70, y: 20))  // a 已送出，只剩 b
        XCTAssertEqual(t.reset(), [.unhighlight(key(1))])
        XCTAssertEqual(t.activeTouchCount, 0)
        XCTAssertEqual(t.ended(id: 2), [])
    }

    func testUnknownTouchIdsAreHarmless() {
        var t = tracker()
        XCTAssertEqual(t.moved(id: 99, to: .zero), [])
        XCTAssertEqual(t.ended(id: 99), [])
        XCTAssertEqual(t.cancelled(id: 99), [])
    }
}
