import XCTest
@testable import IMECore

/// 日文假名輸入（Issue #10，FR-J01~J05）。
///
/// 假名由碼表直接提供（FR-J02），引擎只要能正確查表、組字、連續輸入。
/// 這裡用**虛構**的假名碼表（羅馬拼音 + `,` 平假名、`.` 片假名），不含任何真實碼表資料。
final class KanaTests: XCTestCase {

    private let kanaTable = """
    %ename KanaDemo
    %cname 假名測試
    %selkey 0123456789
    %chardef begin
    a, あ
    i, い
    u, う
    e, え
    o, お
    ka, か
    ga, が
    kya, きゃ
    tsu, つ
    xtsu, っ
    xa, ぁ
    nn, ん
    a. ア
    i. イ
    ka. カ
    kya. キャ
    xtsu. ッ
    ,, 、
    ,. 。
    a 一
    a 二
    ka 三
    %chardef end
    """

    private func makeComposer() throws -> Composer {
        let table = try CinParser.parse(data: Data(kanaTable.utf8)).0
        let index = try TableIndex(data: TableIndexBuilder.build(from: table))
        return Composer(source: index)
    }

    /// 輸入一串按鍵，並在每個字之間按空白送出；回傳送出的所有文字。
    private func typeWords(_ words: [String], _ c: inout Composer) -> [String] {
        var sent: [String] = []
        for word in words {
            word.forEach { c.handle(.key($0)) }
            for action in c.handle(.space) {
                if case .insert(let text) = action { sent.append(text) }
            }
        }
        return sent
    }

    // MARK: - 平假名（FR-J01）

    func testHiraganaConsecutiveInput() throws {
        var c = try makeComposer()
        // i, o, e, o, → いおえお
        let sent = typeWords(["i,", "o,", "e,", "o,"], &c)
        XCTAssertEqual(sent.joined(), "いおえお")
    }

    func testHiraganaWordWithSokuonAndHatsuon() throws {
        var c = try makeComposer()
        let sent = typeWords(["ka,", "xtsu,", "ka,", "nn,"], &c)
        XCTAssertEqual(sent.joined(), "かっかん")
    }

    func testVoicedYouonAndSmallKana() throws {
        var c = try makeComposer()
        XCTAssertEqual(typeWords(["ga,", "kya,", "xa,"], &c).joined(), "がきゃぁ")
    }

    // MARK: - 片假名（FR-J04）

    func testKatakanaWithPeriodSuffix() throws {
        var c = try makeComposer()
        XCTAssertEqual(typeWords(["a.", "i.", "ka.", "kya.", "xtsu."], &c).joined(), "アイカキャッ")
    }

    func testMixedHiraganaKatakanaAndChinese() throws {
        var c = try makeComposer()
        XCTAssertEqual(typeWords(["ka,", "ka.", "a"], &c).joined(), "かカ一")
    }

    // MARK: - 組字狀態（FR-J05：`,` `.` 是字根，候選與選字流程同一般中文字）

    func testPrefixOfKanaCodeIsIncompleteNotInvalid() throws {
        var c = try makeComposer()
        "ky".forEach { c.handle(.key($0)) }
        XCTAssertEqual(c.state.status, .incomplete, "ky 還沒打完，不算錯碼")
        c.handle(.key("a"))
        XCTAssertEqual(c.state.status, .incomplete, "kya 本身沒有字，只有 kya, 與 kya.")
        c.handle(.key(","))
        XCTAssertEqual(c.state.status, .matched)
        XCTAssertEqual(c.state.candidates, ["きゃ"])
    }

    func testPlainCodeAndKanaCodeCoexist() throws {
        var c = try makeComposer()
        "ka".forEach { c.handle(.key($0)) }
        XCTAssertEqual(c.state.candidates, ["三"], "ka 是中文字根，不被 ka, 影響")
        c.handle(.key(","))
        XCTAssertEqual(c.state.candidates, ["か"])
        c.handle(.backspace)
        XCTAssertEqual(c.state.candidates, ["三"], "⌫ 回到 ka")
    }

    func testCommaAndPeriodAloneAreCodeKeys() throws {
        var c = try makeComposer()
        c.handle(.key(","))
        XCTAssertEqual(c.state.status, .incomplete, "單按 , 是 ,, 與 ,. 的前綴")
        c.handle(.key(","))
        XCTAssertEqual(c.state.candidates, ["、"])
        XCTAssertEqual(c.handle(.space), [.insert("、")])
    }

    /// 碼表沒有 %keyname 區段時，索引檔仍記得 `,` `.` 是字根鍵，假名碼才打得出來。
    func testCodeKeysComeFromCodesNotOnlyFromKeyname() throws {
        let table = try CinParser.parse(data: Data(kanaTable.utf8)).0
        XCTAssertTrue(table.keyNames.isEmpty, "這份虛構碼表沒有 %keyname")
        let index = try TableIndex(data: TableIndexBuilder.build(from: table))
        XCTAssertEqual(index.meta.extraCodeKeys, ",.")
        XCTAssertEqual(index.extraCodeKeys, [",", "."])
    }

    func testMaxCodeLengthCoversLongestKanaCode() throws {
        let table = try CinParser.parse(data: Data(kanaTable.utf8)).0
        let index = try TableIndex(data: TableIndexBuilder.build(from: table))
        XCTAssertEqual(index.maxCodeLength, 5, "xtsu, 與 kya. 等共 5 碼")
        var c = Composer(source: index)
        "xtsu,".forEach { c.handle(.key($0)) }
        XCTAssertEqual(c.state.status, .matched)
        XCTAssertNotEqual(c.state.status, .overLength)
    }

    func testKanaCodesAreFoundByPrefixAndReverseLookup() throws {
        let table = try CinParser.parse(data: Data(kanaTable.utf8)).0
        let index = try TableIndex(data: TableIndexBuilder.build(from: table))
        XCTAssertEqual(index.codes(withPrefix: "ka"), ["ka", "ka,", "ka."])
        XCTAssertEqual(index.codes(for: "か"), ["ka,"])
        XCTAssertEqual(index.codes(for: "カ"), ["ka."])
    }

    func testEnglishOptionStillAvailableForKanaCodes() throws {
        var c = try makeComposer()
        "ka,".forEach { c.handle(.key($0)) }
        XCTAssertEqual(c.state.englishOption, "ka,")
    }
}
