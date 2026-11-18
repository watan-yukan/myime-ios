import XCTest
@testable import IMECore

/// iPad 版面（Issue #24）：對照 docs/04_UI規格.md 的 iPad Pro 11 吋量測值。
final class IPadLayoutTests: XCTestCase {

    private func load() throws -> KeyboardLayoutFile {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return try KeyboardLayoutFile.load(contentsOf: url.appendingPathComponent("Shared/Layouts/ipad.json"))
    }

    private func frames(
        _ layout: KeyboardLayoutFile, page: String = "alpha", width: CGFloat, landscape: Bool
    ) throws -> PageFrames {
        let page = try XCTUnwrap(layout.page(page))
        return LayoutEngine.frames(
            for: page, metrics: layout.metrics.metrics(landscape: landscape),
            containerWidth: width, landscape: landscape)
    }

    private func rect(_ frames: PageFrames, row: Int, _ matches: (LayoutKey) -> Bool) throws -> CGRect {
        try XCTUnwrap(frames.frames.first { $0.id.row == row && matches($0.key) }, "找不到按鍵").rect
    }

    func testLoadsAllPagesAndHasGlobeEverywhere() throws {
        let layout = try load()
        XCTAssertEqual(layout.device, "ipad")
        XCTAssertEqual(Set(layout.pages.keys), ["alpha", "numbers", "symbols"])
        for (name, page) in layout.pages {
            XCTAssertEqual(page.rows.count, 4, name)
            XCTAssertTrue(page.rows[3].keys.contains { $0.type == .globe }, "FR-U16：iPad 每一頁都要有地球鍵（\(name)）")
            XCTAssertTrue(page.rows[3].keys.contains { $0.type == .dismiss }, "\(name) 要有收鍵盤")
            XCTAssertTrue(page.rows[1].keys.contains { $0.type == .emoji }, "原生「注音」位置放表情鍵（\(name)）")
        }
    }

    func testLandscapeMatchesMeasurements() throws {
        let f = try frames(try load(), width: 1194, landscape: true)
        let q = try rect(f, row: 0) { $0.output == "q" }
        XCTAssertEqual(q.minX, 132.7, accuracy: 1.0)  // 量測 132.7
        XCTAssertEqual(q.width, 80.4, accuracy: 0.8)
        XCTAssertEqual(q.height, 75)

        let tab = try rect(f, row: 0) { $0.type == .tab }
        XCTAssertEqual(tab.minX, 14.8, accuracy: 0.01)
        XCTAssertEqual(tab.width, 104.6, accuracy: 1.0)

        let lang = try rect(f, row: 1) { $0.type == .emoji }
        XCTAssertEqual(lang.width, 132.7, accuracy: 1.5)  // 「注音」鍵位置
        let ret = try rect(f, row: 1) { $0.type == .returnKey }
        XCTAssertEqual(ret.width, 170.9, accuracy: 1.5)

        let shift = try rect(f, row: 2) { $0.type == .shift }
        XCTAssertEqual(shift.width, 174.8, accuracy: 1.5)

        let space = try rect(f, row: 3) { $0.type == .space }
        XCTAssertEqual(space.width, 695.5, accuracy: 2.0)  // 麥克風位置的鍵移除，寬度併入空白鍵
        let globe = try rect(f, row: 3) { $0.type == .globe }
        XCTAssertEqual(globe.width, 81.9, accuracy: 1.5)
        XCTAssertEqual(globe.minX, 14.8, accuracy: 0.01)
    }

    func testPortraitMatchesMeasurements() throws {
        let f = try frames(try load(), width: 834, landscape: false)
        let q = try rect(f, row: 0) { $0.output == "q" }
        XCTAssertEqual(q.minX, 91.3, accuracy: 1.0)
        XCTAssertEqual(q.width, 56.6, accuracy: 0.8)
        XCTAssertEqual(q.height, 56)

        let ret = try rect(f, row: 1) { $0.type == .returnKey }
        XCTAssertEqual(ret.width, 120.1, accuracy: 1.5)
        let space = try rect(f, row: 3) { $0.type == .space }
        XCTAssertEqual(space.width, 409.6 + 55.4 + 9.4, accuracy: 4.0)  // 麥克風位置的鍵移除，寬度併入空白鍵
        let backspace = try rect(f, row: 0) { $0.type == .backspace }
        XCTAssertEqual(backspace.width, 73.3, accuracy: 1.0)
    }

    func testEveryRowIsJustifiedAtIPadWidths() throws {
        let layout = try load()
        for landscape in [false, true] {
            let widths: [CGFloat] = landscape ? [1024, 1080, 1112, 1194, 1366] : [744, 768, 810, 820, 834, 1024]
            let metrics = layout.metrics.metrics(landscape: landscape)
            for width in widths {
                for pageName in layout.pages.keys.sorted() {
                    let f = try frames(layout, page: pageName, width: width, landscape: landscape)
                    let left = CGFloat(metrics.sideMargin)
                    let right = width - CGFloat(metrics.sideMargin)
                    for row in Set(f.frames.map { $0.id.row }) {
                        let rects = f.frames.filter { $0.id.row == row }.map { $0.rect }
                        let minX = try XCTUnwrap(rects.map { $0.minX }.min())
                        let maxX = try XCTUnwrap(rects.map { $0.maxX }.max())
                        XCTAssertEqual(minX, left, accuracy: 0.01, "\(pageName) 寬 \(width) 第 \(row) 列左側")
                        XCTAssertEqual(maxX, right, accuracy: 0.01, "\(pageName) 寬 \(width) 第 \(row) 列右側")
                    }
                }
            }
        }
    }

    func testCommaKeyShiftOutputAndSecondaryLabels() throws {
        let page = try XCTUnwrap(try load().page("alpha"))
        let comma = try XCTUnwrap(page.rows[2].keys.first { $0.output == "," })
        XCTAssertEqual(comma.shiftOutput, "!")
        let period = try XCTUnwrap(page.rows[2].keys.first { $0.output == "." })
        XCTAssertEqual(period.shiftOutput, "?")
        let q = try XCTUnwrap(page.rows[0].keys.first { $0.output == "q" })
        XCTAssertEqual(q.secondary, "1", "FR-U25：字母鍵上方的小字（v1.1 實作下滑輸入）")
    }

    func testNumbersAndSymbolsPagesMatchNativeContent() throws {
        let layout = try load()
        let numbers = try XCTUnwrap(layout.page("numbers"))
        XCTAssertEqual(numbers.rows[1].keys.compactMap { $0.output }.joined(), "@#$&*()'\"")
        XCTAssertEqual(numbers.rows[2].keys.compactMap { $0.output }.joined(), "%-+=/;:!?")
        let symbols = try XCTUnwrap(layout.page("symbols"))
        XCTAssertEqual(symbols.rows[1].keys.compactMap { $0.output }.joined(), "€£¥_^[]{}")
        XCTAssertEqual(symbols.rows[2].keys.compactMap { $0.output }.joined(), "§|~…\\<>!?")
    }

    // MARK: - Session：shiftOutput

    func testShiftChangesCommaToExclamationOnlyWhenPressedByUser() throws {
        let page = try XCTUnwrap(try load().page("alpha"))
        let comma = try XCTUnwrap(page.rows[2].keys.first { $0.output == "," })

        var settings = KeyboardSettings()
        settings.fullWidthPunctuation = false
        settings.autoCapitalize = false
        let session = KeyboardSession(source: DictionaryCandidateSource([:]), settings: settings)
        let output = MockOutput()
        session.output = output
        session.tap(LayoutKey(type: .langToggle))  // 英文模式

        session.tap(comma)
        XCTAssertEqual(output.visibleText, ",")

        session.tap(LayoutKey(type: .shift))  // 使用者自己按 Shift
        session.tap(comma)
        XCTAssertEqual(output.visibleText, ",!")

        session.tap(comma)
        XCTAssertEqual(output.visibleText, ",!,", "Shift 一次性，用完就恢復")
    }

    func testAutoCapitalizationDoesNotTurnCommaIntoExclamation() throws {
        let page = try XCTUnwrap(try load().page("alpha"))
        let comma = try XCTUnwrap(page.rows[2].keys.first { $0.output == "," })
        let session = KeyboardSession(source: DictionaryCandidateSource([:]))
        let output = MockOutput()
        session.output = output
        session.tap(LayoutKey(type: .langToggle))
        session.contextChanged()  // 句首：自動大寫
        XCTAssertTrue(session.showsUppercase)
        XCTAssertTrue(session.shift.isAutomatic)

        session.tap(comma)
        XCTAssertEqual(output.visibleText, ",", "自動大寫只影響字母")
    }

    func testShiftStateTracksAutomaticOrigin() {
        var shift = ShiftState()
        shift.applyAutoCapitalization(true)
        XCTAssertTrue(shift.isAutomatic)
        shift.tap(at: 0)  // 使用者按下：一次性大寫被關掉，且不再算自動
        XCTAssertFalse(shift.isAutomatic)
        XCTAssertEqual(shift.mode, .off)
        shift.tap(at: 5)
        XCTAssertEqual(shift.mode, .once)
        XCTAssertFalse(shift.isAutomatic)
        shift.didTypeCharacter()
        XCTAssertEqual(shift.mode, .off)
        shift.applyAutoCapitalization(true)
        shift.reset()
        XCTAssertFalse(shift.isAutomatic)
    }
}
