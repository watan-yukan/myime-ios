import XCTest
@testable import IMECore

/// 全部使用虛構資料（R-LIU-4）。
final class CinParserTests: XCTestCase {

    private func parse(_ text: String) throws -> (CinTable, CinParseReport) {
        try CinParser.parse(data: Data(text.utf8))
    }

    // MARK: - 測試碼表 Fixtures/sample.cin

    func testParsesSampleFixture() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "sample", withExtension: "cin", subdirectory: "Fixtures")
        )
        let (table, report) = try CinParser.parse(contentsOf: url)

        XCTAssertEqual(table.ename, "SampleTable")
        XCTAssertEqual(table.cname, "測試碼表")
        XCTAssertEqual(table.selkey, "0123456789")
        XCTAssertEqual(table.otherHeaders["encoding"], "UTF-8")
        XCTAssertEqual(table.otherHeaders["gen_inp"], "")
        XCTAssertEqual(table.encoding, .utf8)
        XCTAssertEqual(table.displayName, "測試碼表")

        XCTAssertEqual(table.keyNames.count, 6)
        XCTAssertEqual(table.keyNames.first, CinKeyName(key: "a", label: "甲"))
        XCTAssertEqual(table.keyNames.last, CinKeyName(key: ".", label: "。"))

        XCTAssertEqual(table.entries.count, 15)
        XCTAssertEqual(table.maxCodeLength, 5)  // xtsu,
        XCTAssertEqual(report.skippedCount, 0)
    }

    func testKeepsOriginalCandidateOrder() throws {
        let (table, _) = try parse("""
        %chardef begin
        a 二
        b 六
        a 一
        a 三
        %chardef end
        """)
        let forA = table.entries.filter { $0.code == "a" }.map(\.value)
        XCTAssertEqual(forA, ["二", "一", "三"], "候選字順序必須照碼表原始順序（FR-K05）")
    }

    func testKanaCodesWithCommaAndPeriod() throws {
        let (table, _) = try parse("""
        %chardef begin
        ka, か
        ka. カ
        xtsu, っ
        %chardef end
        """)
        XCTAssertEqual(table.entries, [
            CinEntry(code: "ka,", value: "か"),
            CinEntry(code: "ka.", value: "カ"),
            CinEntry(code: "xtsu,", value: "っ"),
        ])
    }

    // MARK: - 容錯

    func testHandlesCRLFTabsCommentsAndBlankLines() throws {
        let text = "# 註解\r\n\r\n%ename  Demo \r\n%chardef begin\r\n\ta\t\t一\r\n  b   二  \r\n# 區段內註解\r\n%chardef end\r\n"
        let (table, report) = try parse(text)
        XCTAssertEqual(table.ename, "Demo")
        XCTAssertEqual(table.entries, [CinEntry(code: "a", value: "一"), CinEntry(code: "b", value: "二")])
        XCTAssertEqual(report.skippedCount, 0)
    }

    func testLowercasesCodes() throws {
        let (table, _) = try parse("%chardef begin\nAB 一\n%chardef end\n")
        XCTAssertEqual(table.entries.first?.code, "ab")
    }

    func testSectionKeywordsAreCaseInsensitive() throws {
        let (table, _) = try parse("%CHARDEF BEGIN\na 一\n%CHARDEF END\n")
        XCTAssertEqual(table.entries.count, 1)
    }

    func testAcceptsUnterminatedSection() throws {
        let (table, _) = try parse("%chardef begin\na 一\nb 二")
        XCTAssertEqual(table.entries.count, 2)
    }

    func testValueMayContainSpaces() throws {
        let (table, _) = try parse("%chardef begin\nab Hello World\n%chardef end\n")
        XCTAssertEqual(table.entries.first?.value, "Hello World")
    }

    func testSkipsMalformedLinesAndReportsThem() throws {
        let text = """
        stray line
        %chardef begin
        a 一
        novalue
        toolongcode 二
        b 三
        %chardef end
        """
        let (table, report) = try parse(text)
        XCTAssertEqual(table.entries.map(\.value), ["一", "三"])
        XCTAssertEqual(report.skippedCount, 3)
        XCTAssertEqual(report.issues, [
            CinParseIssue(line: 1, reason: .outsideSection),
            CinParseIssue(line: 4, reason: .missingValue),
            CinParseIssue(line: 5, reason: .codeTooLong),
        ])
    }

    func testRejectsNonASCIICode() throws {
        let (table, report) = try parse("%chardef begin\n字 一\na 二\n%chardef end\n")
        XCTAssertEqual(table.entries.count, 1)
        XCTAssertEqual(report.issues.first?.reason, .invalidCode)
    }

    func testLimitsRecordedIssues() throws {
        let junk = Array(repeating: "x", count: 80).joined(separator: "\n")
        let (_, report) = try parse("%chardef begin\n\(junk)\na 一\n%chardef end\n")
        XCTAssertEqual(report.skippedCount, 80)
        XCTAssertEqual(report.issues.count, CinParser.maxRecordedIssues)
    }

    // MARK: - 錯誤

    func testEmptyDataThrows() {
        XCTAssertThrowsError(try CinParser.parse(data: Data())) {
            XCTAssertEqual($0 as? CinParseError, .empty)
        }
    }

    func testMissingCharDefThrows() {
        XCTAssertThrowsError(try parse("%ename Demo\n%keyname begin\na 甲\n%keyname end\n")) {
            XCTAssertEqual($0 as? CinParseError, .noCharDef)
        }
    }

    // MARK: - 編碼

    func testUTF8WithBOM() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data("%chardef begin\na 一\n%chardef end\n".utf8))
        let (table, _) = try CinParser.parse(data: data)
        XCTAssertEqual(table.encoding, .utf8BOM)
        XCTAssertEqual(table.entries.first?.value, "一")
    }

    func testBig5Fallback() throws {
        // "中" 的 Big5 編碼為 A4 A4，不是合法 UTF-8
        var data = Data("%chardef begin\na ".utf8)
        data.append(contentsOf: [0xA4, 0xA4])
        data.append(Data("\n%chardef end\n".utf8))

        #if canImport(Darwin)
        let (table, _) = try CinParser.parse(data: data)
        XCTAssertEqual(table.encoding, .big5)
        XCTAssertEqual(table.entries.first?.value, "中")
        #else
        XCTAssertThrowsError(try CinParser.parse(data: data)) {
            XCTAssertEqual($0 as? CinParseError, .unsupportedEncoding)
        }
        #endif
    }

    // MARK: - 效能（NFR-01 的前置：匯入 3 萬筆應在合理時間內完成）

    func testParsesThirtyThousandLinesQuickly() throws {
        var lines = ["%chardef begin"]
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        for i in 0..<30_000 {
            let code = String(letters[i % 26]) + String(letters[(i / 26) % 26]) + String(letters[(i / 676) % 26])
            lines.append("\(code) 字\(i)")
        }
        lines.append("%chardef end")
        let data = Data(lines.joined(separator: "\n").utf8)

        let start = Date()
        let (table, _) = try CinParser.parse(data: data)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(table.entries.count, 30_000)
        XCTAssertLessThan(elapsed, 5.0, "解析 3 萬筆花了 \(elapsed) 秒")
    }
}
