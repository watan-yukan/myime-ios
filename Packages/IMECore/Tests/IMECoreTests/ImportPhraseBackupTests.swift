import XCTest
@testable import IMECore

/// 匯入碼表、常用詞、備份（Issue #27、#30、#35、#36 的引擎端）。全部使用虛構資料。
final class TableImporterTests: XCTestCase {

    private func fixtureData() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "sample", withExtension: "cin", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    func testImportsFixtureAndReportsSummary() throws {
        let result = try TableImporter.build(from: fixtureData())
        let summary = result.summary
        XCTAssertEqual(summary.name, "測試碼表")
        XCTAssertEqual(summary.selkey, "0123456789")
        XCTAssertEqual(summary.entryCount, 15)
        XCTAssertEqual(summary.maxCodeLength, 5)
        XCTAssertEqual(summary.encoding, "UTF-8")
        XCTAssertEqual(summary.skippedLines, 0)
        XCTAssertEqual(summary.extraCodeKeys, ",.")

        let index = try TableIndex(data: result.indexData)
        XCTAssertTrue(index.checksumIsValid())
        XCTAssertEqual(index.candidates(for: "ka,"), ["か"])
    }

    func testSkippedLinesAreCounted() throws {
        let text = "%chardef begin\na 一\nbroken\nb 二\n%chardef end\n"
        XCTAssertEqual(try TableImporter.build(from: Data(text.utf8)).summary.skippedLines, 1)
    }

    func testFingerprintChangesWithContent() throws {
        let first = try TableImporter.build(from: Data("%chardef begin\na 一\n%chardef end\n".utf8))
        let second = try TableImporter.build(from: Data("%chardef begin\na 二\n%chardef end\n".utf8))
        let a = try TableIndex(data: first.indexData).meta.sourceFingerprint
        let b = try TableIndex(data: second.indexData).meta.sourceFingerprint
        XCTAssertEqual(a.count, 16)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(SourceFingerprint.compute(Data("x".utf8)), SourceFingerprint.compute(Data("x".utf8)))
    }

    func testErrorsForBadFiles() {
        XCTAssertThrowsError(try TableImporter.build(from: Data())) {
            XCTAssertEqual($0 as? TableImportError, .parse(.empty))
        }
        XCTAssertThrowsError(try TableImporter.build(from: Data("hello world".utf8))) {
            XCTAssertEqual($0 as? TableImportError, .parse(.noCharDef))
        }
        let huge = Data(count: TableImporter.maxFileSize + 1)
        XCTAssertThrowsError(try TableImporter.build(from: huge)) {
            XCTAssertEqual($0 as? TableImportError, .tooLarge)
        }
    }
}

final class PhraseStoreTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func learn(_ store: PhraseStore, _ commits: [String], times: Int = 1) {
        for _ in 0..<times {
            store.resetContext()
            for commit in commits { store.recordCommit(commit, now: now) }
        }
    }

    func testLearnedPhraseNeedsTwoOccurrencesBeforeItIsSuggested() {
        let store = PhraseStore()
        learn(store, ["信", "義"])
        XCTAssertEqual(store.suggestions(afterText: "信", now: now), [], "只出現一次不建議")
        learn(store, ["信", "義"])
        XCTAssertEqual(store.suggestions(afterText: "信", now: now), [PhraseSuggestion(text: "義", phrase: "信義")])
    }

    func testSuggestsRemainderForLongerPhrasesAndPrefersLongerPrefix() {
        let store = PhraseStore()
        learn(store, ["信", "義", "房", "屋"], times: 3)
        // 已輸入「信義」→ 建議「房」「房屋」依前綴長度與分數
        let suggestions = store.suggestions(afterText: "你好信義", now: now)
        XCTAssertTrue(suggestions.contains(PhraseSuggestion(text: "房屋", phrase: "信義房屋")))
        XCTAssertEqual(suggestions.first?.phrase.hasPrefix("信義"), true, "較長的前綴符合優先")
    }

    func testPunctuationEnglishAndDigitsBreakAPhrase() {
        let store = PhraseStore()
        learn(store, ["信", "，", "義"], times: 3)
        XCTAssertEqual(store.suggestions(afterText: "信", now: now), [], "標點會中斷，不會把『信義』記成詞")
        learn(store, ["信", "a", "義"], times: 3)
        XCTAssertEqual(store.suggestions(afterText: "信", now: now), [])
    }

    func testSuggestionUsesOnlyTrailingChineseCharacters() {
        let store = PhraseStore()
        learn(store, ["信", "義"], times: 2)
        XCTAssertEqual(store.suggestions(afterText: "hello 信", now: now).count, 1)
        XCTAssertEqual(store.suggestions(afterText: "信。", now: now), [], "游標前是標點，不建議")
        XCTAssertEqual(store.suggestions(afterText: nil, now: now), [])
        XCTAssertEqual(store.suggestions(afterText: "", now: now), [])
    }

    func testCommittedWordIsRecordedAsAPhrase() {
        let store = PhraseStore()
        learn(store, ["嘸蝦米"], times: 2)
        XCTAssertEqual(store.suggestions(afterText: "嘸", now: now).first?.phrase, "嘸蝦米")
    }

    func testManualPhrasesAreSuggestedImmediatelyAndRankFirst() {
        let store = PhraseStore()
        learn(store, ["信", "用"], times: 5)
        XCTAssertTrue(store.add(manual: "信義"))
        let suggestions = store.suggestions(afterText: "信", now: now)
        XCTAssertEqual(suggestions.first, PhraseSuggestion(text: "義", phrase: "信義"), "手動新增的排最前面")
        XCTAssertFalse(store.add(manual: "信"), "至少兩個字")
        XCTAssertFalse(store.add(manual: "ab"), "要是中文字")
    }

    func testRecentUseOutranksOldUse() {
        let store = PhraseStore(records: [
            PhraseRecord(text: "信義", count: 10, lastUsed: now.addingTimeInterval(-90 * 86_400)),
            PhraseRecord(text: "信用", count: 6, lastUsed: now),
        ])
        XCTAssertEqual(store.suggestions(afterText: "信", now: now).map(\.phrase), ["信用", "信義"])
    }

    func testDisabledStoreNeitherLearnsNorSuggests() {
        let store = PhraseStore()
        store.isEnabled = false
        learn(store, ["信", "義"], times: 3)
        XCTAssertTrue(store.records.isEmpty)
        store.isEnabled = true
        learn(store, ["信", "義"], times: 3)
        store.isEnabled = false
        XCTAssertEqual(store.suggestions(afterText: "信", now: now), [])
    }

    func testRemoveAndClearKeepManual() {
        let store = PhraseStore()
        learn(store, ["信", "義"], times: 2)
        store.add(manual: "嘸蝦米")
        store.remove("信義")
        XCTAssertNil(store.records["信義"])
        learn(store, ["信", "用"], times: 2)
        store.removeAllLearned()
        XCTAssertEqual(Set(store.records.keys), ["嘸蝦米"])
        store.removeAll()
        XCTAssertTrue(store.records.isEmpty)
    }

    func testPruneKeepsManualAndDropsLowestScoreLearned() {
        var records = (0..<PhraseStore.maxRecords).map {
            PhraseRecord(text: "詞\($0)", count: 10, lastUsed: now, source: .learned)
        }
        records.append(PhraseRecord(text: "手動", count: 0, lastUsed: nil, source: .manual))
        records.append(PhraseRecord(text: "冷門", count: 1, lastUsed: now.addingTimeInterval(-365 * 86_400), source: .learned))
        let store = PhraseStore(records: records)
        store.recordCommit("新", now: now)
        store.recordCommit("詞", now: now)  // 觸發 prune
        XCTAssertLessThanOrEqual(store.records.count, PhraseStore.maxRecords)
        XCTAssertNotNil(store.records["手動"], "手動新增的不被淘汰")
        XCTAssertNil(store.records["冷門"], "分數最低的先被淘汰")
    }

    // MARK: - 檔案

    func testFileRoundTripKeepsDatesAndSources() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("imecore-phrases-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("phrases.json")

        let store = PhraseStore()
        learn(store, ["信", "義"], times: 2)
        store.add(manual: "嘸蝦米")
        try PhraseFileStore(url: url).save(store)

        let loaded = PhraseFileStore(url: url).load()
        XCTAssertTrue(loaded.writable)
        XCTAssertEqual(loaded.store.records["信義"]?.count, 2)
        XCTAssertEqual(loaded.store.records["信義"]?.lastUsed, now)
        XCTAssertEqual(loaded.store.records["嘸蝦米"]?.source, .manual)
    }

    func testMissingCorruptAndNewerFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("imecore-phrases-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("phrases.json")

        XCTAssertTrue(PhraseFileStore(url: url).load().store.records.isEmpty)

        try Data("not json".utf8).write(to: url)
        XCTAssertTrue(PhraseFileStore(url: url).load().store.records.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathExtension("corrupt").path))

        try Data(#"{ "schemaVersion": 9, "items": [ { "text": "信義", "count": 3, "source": "learned" } ] }"#.utf8).write(to: url)
        let newer = PhraseFileStore(url: url).load()
        XCTAssertFalse(newer.writable)
        XCTAssertEqual(newer.store.records["信義"]?.count, 3)
    }
}

final class BackupTests: XCTestCase {

    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeBackup() -> BackupFile {
        var settings = KeyboardSettings()
        settings.numberRow = true
        settings.theme = ThemeSelection(id: "oled", appearance: .dark)
        return BackupFile(
            appVersion: "1.0.0", createdAt: date, settings: settings,
            phrases: [PhraseRecord(text: "信義", count: 3, lastUsed: date, source: .manual)],
            tableHint: BackupFile.TableHint(name: "測試碼表", sourceFileName: "sample.cin", importedAt: date))
    }

    func testRoundTrip() throws {
        let data = try BackupCodec.encode(makeBackup())
        let result = try BackupCodec.restore(from: data)
        XCTAssertEqual(result.settings?.numberRow, true)
        XCTAssertEqual(result.settings?.theme.id, "oled")
        XCTAssertEqual(result.phrases, makeBackup().phrases)
        XCTAssertEqual(result.tableHint?.sourceFileName, "sample.cin")
        XCTAssertEqual(result.createdAt, date)
        XCTAssertEqual(result.appVersion, "1.0.0")
        XCTAssertTrue(result.skippedSections.isEmpty)
    }

    func testBackupNeverContainsTableContent() throws {
        let text = String(decoding: try BackupCodec.encode(makeBackup()), as: UTF8.self)
        XCTAssertFalse(text.contains("%chardef"))
        XCTAssertTrue(text.contains("tableHint"), "只留下要重新匯入哪個檔的提示")
    }

    func testBrokenSectionIsSkippedOthersRestored() throws {
        let json = #"""
        { "app": "MyIME", "schemaVersion": 1, "appVersion": "1.0", "createdAt": "2027-01-15T08:00:00Z",
          "settings": { "numberRow": "oops-not-a-bool" },
          "phrases": [ { "text": "信義", "count": 2, "source": "learned" } ] }
        """#
        let result = try BackupCodec.restore(from: Data(json.utf8))
        XCTAssertNil(result.settings)
        XCTAssertEqual(result.skippedSections, ["settings"])
        XCTAssertEqual(result.phrases?.first?.text, "信義", "壞掉的區段不影響其他區段")
    }

    func testRejectsForeignAndNewerFiles() {
        XCTAssertThrowsError(try BackupCodec.restore(from: Data("[]".utf8))) {
            XCTAssertEqual($0 as? BackupError, .notABackup)
        }
        XCTAssertThrowsError(try BackupCodec.restore(from: Data(#"{ "app": "Other", "schemaVersion": 1 }"#.utf8))) {
            XCTAssertEqual($0 as? BackupError, .notABackup)
        }
        XCTAssertThrowsError(try BackupCodec.restore(from: Data(#"{ "app": "MyIME", "schemaVersion": 9 }"#.utf8))) {
            XCTAssertEqual($0 as? BackupError, .newerVersion(9))
        }
    }

    func testFileNamesSortByTime() {
        let earlier = BackupCodec.fileName(for: date)
        let later = BackupCodec.fileName(for: date.addingTimeInterval(3600))
        XCTAssertEqual(earlier, "MyIME-backup-20270115-080000.json")
        XCTAssertLessThan(earlier, later)
        XCTAssertTrue(BackupCodec.isBackupFileName(earlier))
        XCTAssertFalse(BackupCodec.isBackupFileName("notes.json"))
    }

    func testPruningKeepsNewestAndNeverTouchesOtherFiles() {
        let names = (1...5).map { "MyIME-backup-2027010\($0)-000000.json" } + ["notes.txt", "photo.jpg"]
        XCTAssertEqual(BackupCodec.filesToDelete(existing: names, keep: 3), [
            "MyIME-backup-20270102-000000.json", "MyIME-backup-20270101-000000.json",
        ])
        XCTAssertEqual(BackupCodec.filesToDelete(existing: names, keep: 10), [])
        XCTAssertEqual(BackupCodec.filesToDelete(existing: names, keep: 0).count, 4, "至少保留 1 份")
    }
}
