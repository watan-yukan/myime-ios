import XCTest
@testable import IMECore

/// 全部使用虛構資料（R-LIU-4）。
final class TableIndexTests: XCTestCase {

    private func sampleTable() throws -> CinTable {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "sample", withExtension: "cin", subdirectory: "Fixtures")
        )
        return try CinParser.parse(contentsOf: url).0
    }

    private func index(_ text: String) throws -> TableIndex {
        let table = try CinParser.parse(data: Data(text.utf8)).0
        return try TableIndex(data: TableIndexBuilder.build(from: table))
    }

    // MARK: - 建立與讀回

    func testRoundTripsSampleFixture() throws {
        let table = try sampleTable()
        let index = try TableIndex(data: TableIndexBuilder.build(from: table))

        XCTAssertEqual(index.meta.ename, "SampleTable")
        XCTAssertEqual(index.meta.cname, "測試碼表")
        XCTAssertEqual(index.meta.selkey, "0123456789")
        XCTAssertEqual(index.meta.keyNames, table.keyNames)
        XCTAssertEqual(index.meta.maxCodeLength, 5)
        XCTAssertEqual(index.meta.valueCount, 15)
        XCTAssertEqual(index.meta.displayName, "測試碼表")

        XCTAssertEqual(index.candidates(for: "a"), ["一", "二"])
        XCTAssertEqual(index.candidates(for: "abcd"), ["五"])
        XCTAssertEqual(index.candidates(for: "ka,"), ["か"])
        XCTAssertEqual(index.candidates(for: "ka."), ["カ"])
        XCTAssertEqual(index.candidates(for: "xtsu,"), ["っ"])
        XCTAssertEqual(index.candidates(for: "zz"), [])
        XCTAssertEqual(index.candidates(for: ""), [])
    }

    func testLookupIsCaseInsensitive() throws {
        let index = try TableIndex(data: TableIndexBuilder.build(from: sampleTable()))
        XCTAssertEqual(index.candidates(for: "AB"), ["三"])
    }

    func testKeepsCandidateOrderAndRemovesExactDuplicates() throws {
        let index = try index("""
        %chardef begin
        a 二
        b 六
        a 一
        a 二
        a 三
        %chardef end
        """)
        XCTAssertEqual(index.candidates(for: "a"), ["二", "一", "三"])
    }

    func testMatchesNaiveLookupForEveryCode() throws {
        var lines = ["%chardef begin"]
        var expected: [String: [String]] = [:]
        let letters = Array("abcdefghij,.")
        for i in 0..<3_000 {
            let length = 1 + i % 5
            let code = String((0..<length).map { letters[(i / (1 + $0)) % letters.count] })
            let value = "字\(i % 700)"
            lines.append("\(code) \(value)")
            if !(expected[code, default: []].contains(value)) { expected[code, default: []].append(value) }
        }
        lines.append("%chardef end")
        let index = try index(lines.joined(separator: "\n"))

        XCTAssertEqual(index.meta.codeCount, expected.count)
        for (code, values) in expected {
            XCTAssertEqual(index.candidates(for: code), values, "code=\(code)")
        }
    }

    // MARK: - 前綴

    func testPrefixQueries() throws {
        let index = try TableIndex(data: TableIndexBuilder.build(from: sampleTable()))
        XCTAssertEqual(index.codes(withPrefix: "ab"), ["ab", "abc", "abcd"])
        XCTAssertEqual(index.codes(withPrefix: "b"), ["b", "ba", "bad"])
        XCTAssertEqual(index.codes(withPrefix: "b", limit: 2), ["b", "ba"])
        XCTAssertEqual(index.codes(withPrefix: "ka"), ["ka,", "ka."])
        XCTAssertTrue(index.hasCode(withPrefix: "ca"))
        XCTAssertFalse(index.hasCode(withPrefix: "cc"))
        XCTAssertFalse(index.hasCode(withPrefix: "toolongprefix"))
    }

    // MARK: - 反查字根

    func testReverseLookupReturnsShortestCodeFirst() throws {
        let index = try index("""
        %chardef begin
        abcd 米
        ab 米
        abc 米
        c 九
        %chardef end
        """)
        XCTAssertEqual(index.codes(for: "米"), ["ab", "abc", "abcd"])
        XCTAssertEqual(index.codes(for: "九"), ["c"])
        XCTAssertEqual(index.codes(for: "無"), [])
    }

    // MARK: - 檔案

    func testLoadsFromMemoryMappedFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("imecore-\(UUID().uuidString).idx")
        defer { try? FileManager.default.removeItem(at: url) }
        try TableIndexBuilder.build(from: sampleTable()).write(to: url)

        let index = try TableIndex(contentsOf: url)
        XCTAssertEqual(index.candidates(for: "cab"), ["十"])
    }

    func testStoresSourceFingerprint() throws {
        let fingerprint: [UInt8] = Array(1...16)
        let data = TableIndexBuilder.build(from: try sampleTable(), sourceFingerprint: fingerprint)
        XCTAssertEqual(try TableIndex(data: data).meta.sourceFingerprint, fingerprint)
    }

    func testLongValuesSurvive() throws {
        let long = String(repeating: "長", count: 200)  // 600 bytes，超過 UInt8
        let index = try index("%chardef begin\nab \(long)\n%chardef end\n")
        XCTAssertEqual(index.candidates(for: "ab"), [long])
    }

    // MARK: - 損壞檔案

    func testRejectsCorruptedByte() throws {
        var data = TableIndexBuilder.build(from: try sampleTable())
        data[TableIndexFormat.headerSize + 3] ^= 0xFF
        XCTAssertThrowsError(try TableIndex(data: data)) {
            XCTAssertEqual($0 as? TableIndexError, .checksumMismatch)
        }
    }

    func testRejectsBadMagic() throws {
        var data = TableIndexBuilder.build(from: try sampleTable())
        data[0] = UInt8(ascii: "X")
        XCTAssertThrowsError(try TableIndex(data: data)) {
            XCTAssertEqual($0 as? TableIndexError, .badMagic)
        }
    }

    func testRejectsTruncatedFile() throws {
        let data = TableIndexBuilder.build(from: try sampleTable())
        XCTAssertThrowsError(try TableIndex(data: data.prefix(40))) {
            XCTAssertEqual($0 as? TableIndexError, .truncated)
        }
        XCTAssertThrowsError(try TableIndex(data: data.prefix(data.count - 10))) {
            XCTAssertEqual($0 as? TableIndexError, .checksumMismatch)
        }
    }

    func testRejectsOtherFormatVersion() throws {
        var data = TableIndexBuilder.build(from: try sampleTable())
        data[TableIndexFormat.HeaderOffset.formatVersion] = 99
        XCTAssertThrowsError(try TableIndex(data: data)) {
            XCTAssertEqual($0 as? TableIndexError, .unsupportedVersion(99))
        }
    }

    // MARK: - 效能（NFR-01：查詢 < 30 ms）

    func testLookupPerformanceOnThirtyThousandCodes() throws {
        var lines = ["%chardef begin"]
        var codes: [String] = []
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        for i in 0..<30_000 {
            let code = String(letters[i % 26]) + String(letters[(i / 26) % 26])
                + String(letters[(i / 676) % 26]) + String(letters[(i / 17_576) % 26])
            codes.append(code)
            lines.append("\(code) 字\(i)")
        }
        lines.append("%chardef end")
        let table = try CinParser.parse(data: Data(lines.joined(separator: "\n").utf8)).0

        let buildStart = Date()
        let data = TableIndexBuilder.build(from: table)
        let buildTime = Date().timeIntervalSince(buildStart)
        let index = try TableIndex(data: data)

        let lookups = 10_000
        let start = Date()
        for i in 0..<lookups {
            XCTAssertFalse(index.candidates(for: codes[(i * 7) % codes.count]).isEmpty)
        }
        let perLookupMs = Date().timeIntervalSince(start) / Double(lookups) * 1000

        XCTAssertLessThan(buildTime, 10, "建立索引花了 \(buildTime) 秒")
        XCTAssertLessThan(perLookupMs, 1, "平均每次查詢 \(perLookupMs) ms，目標遠低於 30 ms")
        XCTAssertLessThan(data.count, 1_500_000, "索引檔 \(data.count) bytes")
    }
}
