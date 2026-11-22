import XCTest
@testable import IMECore

/// 內建詞庫（FR-S02）：索引、查詢與接進常用詞建議。
final class LexiconTests: XCTestCase {

    /// 虛構的小詞庫（格式同 lexicon.txt：依碼位排序、同開頭字連在一起）。
    private let sample = Lexicon(data: Data("""
        午餐\t30
        午餐會\t2
        午睡\t12
        天氣\t50
        天氣預報\t8
        天空\t20
        𠀋一\t1

        """.utf8))

    func testPhrasesWithPrefixAreSortedByCount() {
        XCTAssertEqual(sample.phrases(withPrefix: "天", limit: 10).map(\.text), ["天氣", "天空", "天氣預報"])
        XCTAssertEqual(sample.phrases(withPrefix: "天氣", limit: 10).map(\.text), ["天氣預報"], "只回傳比前綴長的詞")
        XCTAssertEqual(sample.phrases(withPrefix: "午", limit: 1).map(\.text), ["午餐"])
        XCTAssertEqual(sample.phrases(withPrefix: "𠀋", limit: 5).map(\.text), ["𠀋一"], "4 位元組的開頭字也能查")
        XCTAssertEqual(sample.phrases(withPrefix: "雨", limit: 5).count, 0)
        XCTAssertEqual(sample.phrases(withPrefix: "", limit: 5).count, 0)
    }

    func testCRLFLinesAreAccepted() {
        let lexicon = Lexicon(data: Data("天氣\t5\r\n天空\t9\r\n".utf8))
        XCTAssertEqual(lexicon.phrases(withPrefix: "天", limit: 5).map(\.text), ["天空", "天氣"])
    }

    func testLexiconSuggestionsComeAfterUserPhrasesAndRespectHidden() {
        let store = PhraseStore(records: [PhraseRecord(text: "天空", count: 3, lastUsed: Date())])
        store.lexicon = sample
        let suggestions = store.suggestions(afterText: "今天", limit: 8)
        XCTAssertEqual(suggestions.map(\.phrase), ["天空", "天氣", "天氣預報"], "自己用過的在前，詞庫依詞頻接在後面，不重複")
        XCTAssertEqual(suggestions[1], PhraseSuggestion(text: "氣", phrase: "天氣"))

        store.hide("天氣")
        XCTAssertEqual(store.suggestions(afterText: "天", limit: 8).map(\.phrase), ["天空", "天氣預報"], "隱藏的詞庫詞不再建議")

        store.lexiconEnabled = false
        XCTAssertEqual(store.suggestions(afterText: "天", limit: 8).map(\.phrase), ["天空"])
    }

    func testLexiconWorksWhenLearningIsOff() {
        let store = PhraseStore(records: [PhraseRecord(text: "天空", count: 3, lastUsed: Date())])
        store.lexicon = sample
        store.isEnabled = false
        XCTAssertTrue(store.providesSuggestions)
        XCTAssertEqual(store.suggestions(afterText: "天", limit: 8).map(\.phrase), ["天氣", "天空", "天氣預報"],
                       "關閉記錄常用詞後只剩詞庫建議")
    }

    func testSessionPassesLexiconToStoreAndSettingTurnsItOff() {
        var settings = KeyboardSettings()
        let session = KeyboardSession(source: DictionaryCandidateSource(["a": ["天"]]), settings: settings)
        let output = MockOutput()
        session.output = output
        session.phraseStore = PhraseStore()
        session.lexicon = sample
        session.tap(LayoutKey(char: "a"))
        session.tap(LayoutKey(type: .space))
        XCTAssertEqual(session.suggestions.first?.phrase, "天氣")

        settings.builtinLexicon = false
        session.settings = settings
        session.contextChanged()
        XCTAssertEqual(session.suggestions, [])
    }

    /// 實際打包的詞庫檔（repo 內的 Shared/Lexicon/lexicon.txt）：格式正確、查得到、夠快。
    func testBundledLexiconFile() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Shared/Lexicon/lexicon.txt")
        let lexicon = try XCTUnwrap(Lexicon(url: url), "找不到 \(url.path)")
        let start = Date()
        let results = lexicon.phrases(withPrefix: "廁", limit: 3)
        XCTAssertEqual(results.first?.text, "廁所")
        XCTAssertLessThan(Date().timeIntervalSince(start), 2.0, "第一次查詢（含建索引）")
        let again = Date()
        for prefix in ["的", "我", "台", "電"] { XCTAssertFalse(lexicon.phrases(withPrefix: prefix, limit: 8).isEmpty) }
        XCTAssertLessThan(Date().timeIntervalSince(again), 0.5)
    }
}
