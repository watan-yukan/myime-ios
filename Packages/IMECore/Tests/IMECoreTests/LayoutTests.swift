import XCTest
@testable import IMECore

/// 版面資料與版面引擎（Issue #13）。
///
/// 以 `Shared/Layouts/iphone.json` 實際算出的位置，對照 docs/04_UI規格.md 量測的原生鍵盤數值。
final class LayoutTests: XCTestCase {

    // MARK: - 載入

    private func repoFile(_ path: String, _ line: UInt = #line) -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }  // 測試檔 → IMECoreTests → Tests → IMECore → Packages → 專案根
        return url.appendingPathComponent(path)
    }

    private func loadIPhone() throws -> KeyboardLayoutFile {
        try KeyboardLayoutFile.load(contentsOf: repoFile("Shared/Layouts/iphone.json"))
    }

    private func frames(
        _ layout: KeyboardLayoutFile, page: String = "alpha", variant: String? = nil,
        width: CGFloat = 430, landscape: Bool = false
    ) throws -> PageFrames {
        let page = try XCTUnwrap(layout.page(page, variant: variant))
        let metrics = layout.metrics.metrics(landscape: landscape)
        return LayoutEngine.frames(for: page, metrics: metrics, containerWidth: width, landscape: landscape)
    }

    private func find(_ frames: PageFrames, row: Int, _ matches: (LayoutKey) -> Bool) throws -> CGRect {
        try XCTUnwrap(frames.frames.first { $0.id.row == row && matches($0.key) }, "找不到按鍵").rect
    }

    func testLoadsIPhoneLayout() throws {
        let layout = try loadIPhone()
        XCTAssertEqual(layout.device, "iphone")
        XCTAssertEqual(Set(layout.pages.keys), ["alpha", "numbers", "symbols"])
        XCTAssertEqual(layout.pages["alpha"]?.rows.count, 4)
        XCTAssertEqual(layout.pages["alpha"]?.rows[0].keys.count, 10)
        XCTAssertEqual(layout.pages["alpha"]?.rows[1].inset, 0.5)
    }

    func testStringShorthandAndObjectKeys() throws {
        let data = Data(#"""
        { "schemaVersion": 1, "device": "t",
          "metrics": { "portrait": { "sideMargin": 0, "keyGap": 0, "rowGap": 0, "keyHeight": 10 },
                       "landscape": { "sideMargin": 0, "keyGap": 0, "rowGap": 0, "keyHeight": 10 } },
          "pages": { "p": { "rows": [ { "keys": [
            "a",
            { "output": ",", "shiftOutput": "!", "secondary": "1", "alternates": ["é", "è"], "width": 1.5 },
            { "type": "return", "label": "前往" }
          ] } ] } } }
        """#.utf8)
        let layout = try KeyboardLayoutFile.load(from: data)
        let keys = try XCTUnwrap(layout.pages["p"]?.rows.first?.keys)
        XCTAssertEqual(keys[0], LayoutKey(char: "a"))
        XCTAssertEqual(keys[1].shiftOutput, "!")
        XCTAssertEqual(keys[1].secondary, "1")
        XCTAssertEqual(keys[1].alternates, ["é", "è"])
        XCTAssertEqual(keys[1].width, 1.5)
        XCTAssertEqual(keys[2].type, .returnKey)
        XCTAssertEqual(keys[2].displayLabel, "前往")
        XCTAssertEqual(keys[0].displayLabel, "a")
    }

    func testRejectsUnsupportedSchemaAndUnknownPageTarget() {
        let metrics = #""metrics": { "portrait": { "sideMargin": 0, "keyGap": 0, "rowGap": 0, "keyHeight": 1 }, "landscape": { "sideMargin": 0, "keyGap": 0, "rowGap": 0, "keyHeight": 1 } }"#
        let wrongVersion = Data(#"{ "schemaVersion": 9, "device": "t", \#(metrics), "pages": {} }"#.utf8)
        XCTAssertThrowsError(try KeyboardLayoutFile.load(from: wrongVersion)) {
            XCTAssertEqual($0 as? LayoutError, .unsupportedSchema(9))
        }

        let badTarget = Data(#"""
        { "schemaVersion": 1, "device": "t", \#(metrics),
          "pages": { "a": { "rows": [ { "keys": [ { "type": "page", "target": "nowhere" } ] } ] } } }
        """#.utf8)
        XCTAssertThrowsError(try KeyboardLayoutFile.load(from: badTarget)) {
            XCTAssertEqual($0 as? LayoutError, .unknownPageTarget(page: "a", target: "nowhere"))
        }
    }

    func testRejectsUnknownKeyType() {
        let data = Data(#"""
        { "schemaVersion": 1, "device": "t",
          "metrics": { "portrait": { "sideMargin": 0, "keyGap": 0, "rowGap": 0, "keyHeight": 1 },
                       "landscape": { "sideMargin": 0, "keyGap": 0, "rowGap": 0, "keyHeight": 1 } },
          "pages": { "a": { "rows": [ { "keys": [ { "type": "banana" } ] } ] } } }
        """#.utf8)
        XCTAssertThrowsError(try KeyboardLayoutFile.load(from: data))
    }

    // MARK: - iPhone 直向（430 pt）對照原生量測

    func testPortraitMatchesNativeMeasurements() throws {
        let layout = try loadIPhone()
        let f = try frames(layout)

        XCTAssertEqual(f.unit, 36.3, accuracy: 0.01)
        let expectedHeight: CGFloat = 8 + 180 + 33 + 4  // 上留白 + 4 列 × 45 + 3 個列間距 × 11 + 下留白
        XCTAssertEqual(f.size.height, expectedHeight, accuracy: 0.01)

        let q = try find(f, row: 0) { $0.output == "q" }
        XCTAssertEqual(q.minX, 6.5, accuracy: 0.01)
        XCTAssertEqual(q.width, 36.3, accuracy: 0.05)  // 量測 36.3
        XCTAssertEqual(q.height, 45)
        XCTAssertEqual(q.minY, 8)

        let a = try find(f, row: 1) { $0.output == "a" }
        XCTAssertEqual(a.minX, 27.7, accuracy: 0.3)  // 量測 27.7
        XCTAssertEqual(a.minY, 8 + 56)

        let shift = try find(f, row: 2) { $0.type == .shift }
        XCTAssertEqual(shift.width, 48.7, accuracy: 0.5)  // 量測 48.7
        let z = try find(f, row: 2) { $0.output == "z" }
        XCTAssertEqual(z.minX, 70.0, accuracy: 0.6)  // 量測 70.0（含 spacer 的間距 14.7）
        XCTAssertEqual(z.minX - shift.maxX, 14.7, accuracy: 0.4)

        // 底排（FR-U26，UI 規格 4.5）：123、表情維持原生寬度；, . Return 與字母鍵同寬；空白鍵用剩下的寬度
        let page = try find(f, row: 3) { $0.type == .page }
        XCTAssertEqual(page.width, 47.1, accuracy: 0.6)  // 量測 47.1
        let space = try find(f, row: 3) { $0.type == .space }
        XCTAssertEqual(space.width, 184.7, accuracy: 1.0)
        let ret = try find(f, row: 3) { $0.type == .returnKey }
        XCTAssertEqual(ret.width, 36.3, accuracy: 0.3)
        XCTAssertEqual(ret.maxX, 430 - 6.5, accuracy: 0.01)
    }

    func testCommaPeriodAndReturnAreLetterWidthAtAllWidths() throws {
        let layout = try loadIPhone()
        for landscape in [false, true] {
            let widths: [CGFloat] = landscape ? [667, 844, 932] : [320, 375, 390, 393, 402, 430, 440]
            for width in widths {
                let f = try frames(layout, width: width, landscape: landscape)
                let letter = try find(f, row: 2) { $0.output == "n" }
                let message = "寬 \(width)\(landscape ? " 橫向" : "")"
                let matchers: [(LayoutKey) -> Bool] = [{ $0.output == "," }, { $0.output == "." }, { $0.type == .returnKey }]
                for matches in matchers {
                    let rect = try find(f, row: 3, matches)
                    XCTAssertEqual(rect.width, letter.width, accuracy: 1.0, message)
                }
                let comma = try find(f, row: 3) { $0.output == "," }
                let space = try find(f, row: 3) { $0.type == .space }
                XCTAssertEqual(comma.minX - space.maxX, 6, accuracy: 0.01, "空白鍵緊接著逗號：\(message)")
            }
        }
    }

    func testCommaAndPeriodKeysOutputAndFlick() throws {
        let row = try XCTUnwrap(try loadIPhone().page("alpha")?.rows[3])
        let comma = try XCTUnwrap(row.keys.first { $0.output == "," })
        let period = try XCTUnwrap(row.keys.first { $0.output == "." })
        XCTAssertEqual(comma.secondary, "!")
        XCTAssertEqual(comma.shiftOutput, "!")
        XCTAssertEqual(period.secondary, "?")
        XCTAssertEqual(period.shiftOutput, "?")
    }

    func testIPhoneLettersHaveIPadSecondaryCharacters() throws {
        let rows = try XCTUnwrap(try loadIPhone().page("alpha")?.rows)
        func secondaries(_ row: Int) -> String {
            rows[row].keys.filter { $0.output?.first?.isLetter == true }.compactMap(\.secondary).joined()
        }
        XCTAssertEqual(secondaries(0), "1234567890")
        XCTAssertEqual(secondaries(1), "@#$&*()'\"")
        XCTAssertEqual(secondaries(2), "%-+=/;:")
    }

    func testAlignWithMissingTargetFallsBackToNormalLayout() throws {
        let page = LayoutPage(rows: [
            LayoutRow(keys: [LayoutKey(char: "a"), LayoutKey(char: "b")]),
            LayoutRow(keys: [LayoutKey(type: .space, width: 1), LayoutKey(type: .char, output: ".", alignWith: "zzz")]),
        ])
        let metrics = OrientationMetrics(sideMargin: 0, keyGap: 10, rowGap: 0, keyHeight: 10)
        let f = LayoutEngine.frames(for: page, metrics: metrics, containerWidth: 210, landscape: false)
        let period = try find(f, row: 1) { $0.output == "." }
        XCTAssertEqual(period.minX, 110, accuracy: 0.01, "找不到對齊目標時照一般比例排")
        XCTAssertEqual(period.width, 100, accuracy: 0.01)
    }

    func testLandscapeMatchesNativeMeasurements() throws {
        let layout = try loadIPhone()
        let f = try frames(layout, width: 932, landscape: true)

        let expectedHeight: CGFloat = 6 + 128 + 25.5 + 4  // 上留白 + 4 列 × 32 + 3 個列間距 × 8.5 + 下留白
        XCTAssertEqual(f.size.height, expectedHeight, accuracy: 0.01)
        let q = try find(f, row: 0) { $0.output == "q" }
        XCTAssertEqual(q.minX, 121, accuracy: 0.01, "按鍵區 690 pt 置中於 932 pt")
        XCTAssertEqual(q.width, 63.7, accuracy: 0.3)
        XCTAssertEqual(q.height, 32)

        let a = try find(f, row: 1) { $0.output == "a" }
        XCTAssertEqual(a.minX, 156, accuracy: 1.0)  // 量測 156

        let space = try find(f, row: 3) { $0.type == .space }
        XCTAssertEqual(space.width, 341.7, accuracy: 1.5)  // , . Return 與字母鍵同寬
        let ret = try find(f, row: 3) { $0.type == .returnKey }
        XCTAssertEqual(ret.width, 63.6, accuracy: 0.5)
    }

    // MARK: - 每一列都左右切齊（任何螢幕寬度）

    func testEveryRowIsJustifiedAtCommonWidths() throws {
        let layout = try loadIPhone()
        let variants: [String?] = [nil, "email", "url"]

        for landscape in [false, true] {
            let widths: [CGFloat] = landscape ? [667, 844, 932] : [320, 375, 390, 393, 402, 430, 440]
            let metrics = layout.metrics.metrics(landscape: landscape)
            for width in widths {
                for pageName in layout.pages.keys.sorted() {
                    for variant in variants where variant == nil || pageName == "alpha" {
                        let f = try frames(layout, page: pageName, variant: variant, width: width, landscape: landscape)
                        let available = metrics.contentWidth.map { min(CGFloat($0), width) } ?? width
                        let left = (width - available) / 2 + CGFloat(metrics.sideMargin)
                        let right = left + available - CGFloat(metrics.sideMargin) * 2

                        for row in Set(f.frames.map(\.id.row)) {
                            let rects = f.frames.filter { $0.id.row == row }.map(\.rect)
                            let minX = try XCTUnwrap(rects.map(\.minX).min())
                            let maxX = try XCTUnwrap(rects.map(\.maxX).max())
                            let message = "\(pageName) variant=\(variant ?? "-") 寬 \(width) 第 \(row) 列"
                            XCTAssertEqual(minX - left, right - maxX, accuracy: 0.01, "左右不對稱：\(message)")
                            XCTAssertLessThan(minX - left, 0.5 * (right - left), message)
                            // 沒有縮排的列要貼齊兩側
                            if row != 1 || pageName != "alpha" {
                                XCTAssertEqual(minX, left, accuracy: 0.01, message)
                                XCTAssertEqual(maxX, right, accuracy: 0.01, message)
                            }
                        }
                    }
                }
            }
        }
    }

    func testRowsNeverOverlapAndStayInsideContainer() throws {
        let layout = try loadIPhone()
        for pageName in layout.pages.keys.sorted() {
            let f = try frames(layout, page: pageName)
            for row in Set(f.frames.map(\.id.row)) {
                let rects = f.frames.filter { $0.id.row == row }.map(\.rect).sorted { $0.minX < $1.minX }
                for pair in zip(rects, rects.dropFirst()) {
                    XCTAssertGreaterThanOrEqual(pair.1.minX - pair.0.maxX, 5.99, "\(pageName) 第 \(row) 列有按鍵重疊")
                }
            }
            for frame in f.frames {
                XCTAssertGreaterThanOrEqual(frame.rect.minX, 0)
                XCTAssertLessThanOrEqual(frame.rect.maxX, 430)
                XCTAssertLessThanOrEqual(frame.rect.maxY, f.size.height)
            }
        }
    }

    func testSpacersAreNotFrames() throws {
        let f = try frames(try loadIPhone())
        XCTAssertFalse(f.frames.contains { $0.key.type == .spacer })
        // 第 3 列：shift + 7 字母 + backspace
        XCTAssertEqual(f.frames.filter { $0.id.row == 2 }.count, 9)
        // KeyID 的 index 對應 JSON 順序（含 spacer）
        let z = try XCTUnwrap(f.frames.first { $0.key.output == "z" })
        XCTAssertEqual(z.id, KeyID(row: 2, index: 2))
    }

    // MARK: - 情境變化（FR-U11）

    func testEmailAndURLVariantsReplaceBottomRow() throws {
        let layout = try loadIPhone()
        let normal = try XCTUnwrap(layout.page("alpha"))
        let email = try XCTUnwrap(layout.page("alpha", variant: "email"))
        let url = try XCTUnwrap(layout.page("alpha", variant: "url"))

        XCTAssertEqual(email.rows.count, 4)
        XCTAssertEqual(email.rows[0], normal.rows[0], "其他列不變")
        XCTAssertTrue(email.rows[3].keys.contains { $0.output == "@" })
        XCTAssertTrue(email.landscapeRows?[3].keys.contains { $0.output == "@" } == true, "橫向也套用")
        // 網址欄位比照 iOS 26：只多一顆「.」，沒有 / 與 .com
        XCTAssertEqual(url.rows[3].keys.compactMap(\.output), ["."])
        XCTAssertFalse(url.rows[3].keys.contains { $0.output == ".com" || $0.output == "/" })
        XCTAssertEqual(layout.page("alpha", variant: "nonexistent"), normal, "沒有這個情境就用預設版面")
        XCTAssertNil(layout.page("missing"))
    }

    // MARK: - 邊界

    func testEmptyPageAndContainerSmallerThanContent() {
        let empty = LayoutEngine.frames(
            for: LayoutPage(rows: []),
            metrics: OrientationMetrics(sideMargin: 0, keyGap: 0, rowGap: 0, keyHeight: 10),
            containerWidth: 300, landscape: false)
        XCTAssertTrue(empty.frames.isEmpty)
        XCTAssertEqual(empty.size, .zero)

        let page = LayoutPage(rows: [LayoutRow(keys: [LayoutKey(char: "a"), LayoutKey(char: "b")])])
        let narrow = LayoutEngine.frames(
            for: page,
            metrics: OrientationMetrics(sideMargin: 0, keyGap: 4, rowGap: 0, keyHeight: 10, contentWidth: 690),
            containerWidth: 200, landscape: false)
        XCTAssertEqual(narrow.frames.last?.rect.maxX ?? 0, 200, accuracy: 0.01, "contentWidth 大於容器時以容器為準")
    }
}
