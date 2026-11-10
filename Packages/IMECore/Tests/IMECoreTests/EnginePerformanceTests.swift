import XCTest
@testable import IMECore

/// 引擎效能（Issue #12，NFR-01、NFR-15）。全部使用程式產生的虛構碼表。
///
/// 門檻刻意訂得比需求寬鬆（CI 的共用機器可能忽快忽慢），目的是抓出「慢了一個數量級」的退步，
/// 而不是量測絕對速度。
final class EnginePerformanceTests: XCTestCase {

    /// 固定種子的簡單亂數，讓每次產生的碼表都一樣。
    private struct SeededRandom {
        var state: UInt64
        mutating func next(_ upper: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(upper))
        }
    }

    /// 約 26,000 個字根、1～5 碼，含 `,` `.` 結尾的假名碼；規模與真實碼表相近。
    private func makeLargeTable() throws -> (table: CinTable, sampleCodes: [String]) {
        var random = SeededRandom(state: 42)
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        var lines = ["%chardef begin"]
        var seen = Set<String>()
        var codes: [String] = []
        while codes.count < 26_000 {
            let length = 1 + random.next(4)
            var code = String((0..<length).map { _ in letters[random.next(26)] })
            if random.next(20) == 0 { code += random.next(2) == 0 ? "," : "." }
            guard seen.insert(code).inserted else { continue }
            codes.append(code)
            lines.append("\(code) 字\(codes.count)")
            if random.next(6) == 0 { lines.append("\(code) 詞\(codes.count)") }  // 重碼
        }
        lines.append("%chardef end")
        let table = try CinParser.parse(data: Data(lines.joined(separator: "\n").utf8)).0
        return (table, codes)
    }

    // MARK: - 每個按鍵事件的處理時間（NFR-01：候選字查詢 < 30 ms）

    func testKeyEventLatency() throws {
        let (table, codes) = try makeLargeTable()
        let index = try TableIndex(data: TableIndexBuilder.build(from: table))
        var composer = Composer(source: index)

        var durations: [Double] = []
        for i in 0..<2_500 {
            let code = codes[(i * 13) % codes.count]
            for character in code {
                let start = ProcessInfo.processInfo.systemUptime
                composer.handle(.key(character))
                durations.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            }
            composer.handle(.space)
        }

        durations.sort()
        let average = durations.reduce(0, +) / Double(durations.count)
        let p99 = durations[Int(Double(durations.count) * 0.99)]
        XCTAssertLessThan(average, 3, "平均每個按鍵 \(average) ms")
        XCTAssertLessThan(p99, 30, "P99 為 \(p99) ms，目標 < 30 ms（NFR-01）")
    }

    // MARK: - 冷啟動：開檔後第一次查詢（NFR-15：< 100 ms，不整表預載）

    func testColdStartFirstLookup() throws {
        let (table, codes) = try makeLargeTable()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("imecore-perf-\(UUID().uuidString).idx")
        defer { try? FileManager.default.removeItem(at: url) }
        try TableIndexBuilder.build(from: table).write(to: url)

        let start = ProcessInfo.processInfo.systemUptime
        let index = try TableIndex(contentsOf: url)
        var composer = Composer(source: index)
        composer.handle(.key(Array(codes[0])[0]))
        let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000

        XCTAssertLessThan(elapsed, 100, "開啟索引並處理第一個按鍵花了 \(elapsed) ms（NFR-15）")
        XCTAssertTrue(composer.state.isComposing)
    }

    // MARK: - 匯入（建立索引）與大小

    func testBuildTimeAndFileSize() throws {
        let (table, _) = try makeLargeTable()
        let start = Date()
        let data = TableIndexBuilder.build(from: table)
        let seconds = Date().timeIntervalSince(start)

        XCTAssertLessThan(seconds, 10, "建立索引花了 \(seconds) 秒")
        XCTAssertLessThan(data.count, 2_000_000, "索引檔 \(data.count) bytes")
        XCTAssertEqual(try TableIndex(data: data).meta.maxCodeLength, 5)
    }

    // MARK: - 反查與前綴（鍵盤輔助功能不得拖慢）

    func testReverseAndPrefixLookupSpeed() throws {
        let (table, codes) = try makeLargeTable()
        let index = try TableIndex(data: TableIndexBuilder.build(from: table))

        let start = ProcessInfo.processInfo.systemUptime
        for i in 0..<2_000 {
            _ = index.codes(for: "字\(1 + (i * 7) % 20_000)")
            _ = index.codes(withPrefix: String(codes[(i * 11) % codes.count].prefix(1)), limit: 20)
        }
        let perPair = (ProcessInfo.processInfo.systemUptime - start) * 1000 / 2_000
        XCTAssertLessThan(perPair, 5, "反查 + 前綴平均 \(perPair) ms")
    }

    // MARK: - 解析（匯入時一次性）

    func testParseLargeTable() throws {
        var lines = ["%chardef begin"]
        for i in 0..<60_000 { lines.append("ab\(i % 9000) 字\(i)") }
        lines.append("%chardef end")
        let data = Data(lines.joined(separator: "\n").utf8)

        let start = Date()
        let parsed = try CinParser.parse(data: data).0
        let seconds = Date().timeIntervalSince(start)
        XCTAssertEqual(parsed.entries.count, 60_000)
        XCTAssertLessThan(seconds, 10, "解析 6 萬筆花了 \(seconds) 秒")
    }
}
