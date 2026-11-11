import Foundation

public struct PhraseRecord: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable {
        /// 從使用者實際輸入自動記錄。
        case learned
        /// 使用者手動新增，不會被自動淘汰。
        case manual
    }

    public var text: String
    public var count: Int
    public var lastUsed: Date?
    public var source: Source

    public init(text: String, count: Int = 0, lastUsed: Date? = nil, source: Source = .learned) {
        self.text = text
        self.count = count
        self.lastUsed = lastUsed
        self.source = source
    }
}

/// 一則常用詞建議：點選後輸入 `text`（接在已輸入文字後面的部分）。
public struct PhraseSuggestion: Equatable, Sendable {
    /// 要輸入的後續文字，例如已輸入「信」、詞為「信義」→ `義`。
    public var text: String
    /// 完整的詞。
    public var phrase: String
}

/// 常用詞記錄與建議（FR-S01~S05）。
///
/// - 只影響「聯想建議」，**不影響碼表候選順序**（FR-S03、FR-K05）。
/// - 記錄的是「連續送出的中文字組成的詞」；標點、英文、數字會中斷。
/// - 學來的詞要出現至少 `minLearnedCount` 次才會建議，避免只打過一次的組合干擾。
public final class PhraseStore {
    public static let maxRecords = 5000
    public static let minLearnedCount = 2
    /// 詞長範圍。
    public static let phraseLengths = 2...4
    /// 分數半衰期（天）。
    public static let halfLifeDays = 30.0
    /// 手動新增的詞排在所有學來的詞前面。
    private static let manualBonus = 1_000_000.0

    public private(set) var records: [String: PhraseRecord] = [:]
    /// 關閉時不記錄、也不提供建議（FR-S05）。
    public var isEnabled = true
    private var recent = ""

    public init(records: [PhraseRecord] = []) {
        for record in records { self.records[record.text] = record }
    }

    // MARK: - 記錄

    /// 送出了一段文字。只有中文字會被記錄；其他字元會中斷目前的詞。
    public func recordCommit(_ text: String, now: Date = Date()) {
        guard isEnabled else { return }
        guard !text.isEmpty, text.allSatisfy(Self.isCJK) else {
            recent = ""
            return
        }
        recent += text
        if recent.count > 8 { recent = String(recent.suffix(8)) }

        let characters = Array(recent)
        for length in Self.phraseLengths where length <= characters.count {
            let phrase = String(characters.suffix(length))
            // 單次送出的字詞本身（如從碼表選出的詞）或跨越兩次送出的組合都記錄
            bump(phrase, now: now)
        }
        // 單次送出就是一個詞（2 字以上）時，也記錄完整詞（可能長於 phraseLengths）
        if text.count >= 2, text.count <= 6, !Self.phraseLengths.contains(text.count) {
            bump(text, now: now)
        }
        prune()
    }

    /// 換欄位、游標移動等：中斷目前的詞。
    public func resetContext() {
        recent = ""
    }

    private func bump(_ phrase: String, now: Date) {
        if var existing = records[phrase] {
            existing.count += 1
            existing.lastUsed = now
            records[phrase] = existing
        } else {
            records[phrase] = PhraseRecord(text: phrase, count: 1, lastUsed: now, source: .learned)
        }
    }

    // MARK: - 建議

    /// - Parameter textBeforeCursor: 游標前的文字；取結尾連續的中文字當作前綴。
    public func suggestions(afterText textBeforeCursor: String?, limit: Int = 8, now: Date = Date()) -> [PhraseSuggestion] {
        guard isEnabled, let text = textBeforeCursor, limit > 0 else { return [] }

        var tail: [Character] = []
        for character in text.reversed() {
            guard Self.isCJK(character) else { break }
            tail.append(character)
            if tail.count == 3 { break }
        }
        tail.reverse()
        guard !tail.isEmpty else { return [] }

        var results: [(suggestion: PhraseSuggestion, prefixLength: Int, score: Double)] = []
        var seen = Set<String>()
        for prefixLength in stride(from: tail.count, through: 1, by: -1) {
            let prefix = String(tail.suffix(prefixLength))
            for record in records.values where record.text.count > prefix.count && record.text.hasPrefix(prefix) {
                if record.source == .learned, record.count < Self.minLearnedCount { continue }
                let suffix = String(record.text.dropFirst(prefix.count))
                guard seen.insert(suffix).inserted else { continue }
                results.append((PhraseSuggestion(text: suffix, phrase: record.text), prefixLength, score(of: record, now: now)))
            }
        }
        results.sort {
            if $0.prefixLength != $1.prefixLength { return $0.prefixLength > $1.prefixLength }
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.suggestion.phrase < $1.suggestion.phrase
        }
        return results.prefix(limit).map { $0.suggestion }
    }

    func score(of record: PhraseRecord, now: Date) -> Double {
        let days = max(0, now.timeIntervalSince(record.lastUsed ?? now) / 86_400)
        let decayed = Double(record.count) * pow(0.5, days / Self.halfLifeDays)
        return record.source == .manual ? Self.manualBonus + decayed : decayed
    }

    // MARK: - 管理（FR-A06）

    /// 手動新增常用詞；回傳是否新增成功（至少 2 個字，全是中文字）。
    @discardableResult
    public func add(manual text: String) -> Bool {
        guard text.count >= 2, text.allSatisfy(Self.isCJK) else { return false }
        var record = records[text] ?? PhraseRecord(text: text)
        record.source = .manual
        records[text] = record
        return true
    }

    public func remove(_ text: String) {
        records[text] = nil
    }

    /// 清除所有學來的詞；手動新增的保留。
    public func removeAllLearned() {
        records = records.filter { $0.value.source == .manual }
    }

    public func removeAll() {
        records.removeAll()
    }

    /// 依分數由高到低（管理頁顯示用）。
    public func sortedRecords(now: Date = Date()) -> [PhraseRecord] {
        records.values.sorted {
            let a = score(of: $0, now: now), b = score(of: $1, now: now)
            return a != b ? a > b : $0.text < $1.text
        }
    }

    /// 超過上限時淘汰分數最低的學來的詞。
    private func prune() {
        guard records.count > Self.maxRecords else { return }
        let now = Date()
        let learned = records.values.filter { $0.source == .learned }.sorted {
            score(of: $0, now: now) < score(of: $1, now: now)
        }
        for record in learned.prefix(records.count - Self.maxRecords) {
            records[record.text] = nil
        }
    }

    static func isCJK(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1, let value = character.unicodeScalars.first?.value else { return false }
        return (0x3400...0x4DBF).contains(value) || (0x4E00...0x9FFF).contains(value)
            || (0xF900...0xFAFF).contains(value) || (0x20000...0x2FA1F).contains(value)
    }
}

/// `phrases.json` 的讀寫（docs/06_資料格式.md 3.2）：載入時自動升級，壞檔與較新的檔案都不會被覆蓋。
public struct PhraseFileStore {
    public static let currentSchemaVersion = 1

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    private struct File: Codable {
        var schemaVersion: Int
        var items: [PhraseRecord]
    }

    private var migrator: JSONMigrator {
        JSONMigrator(currentVersion: Self.currentSchemaVersion)
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// `writable` 為 false 代表檔案比這版 App 新，只讀不寫。
    public func load() -> (store: PhraseStore, writable: Bool) {
        let object: JSONObject
        let writable: Bool
        switch VersionedFile.load(from: url, migrator: migrator) {
        case .loaded(let value), .migrated(let value, _):
            object = value
            writable = true
        case .readOnlyNewer(let value, _):
            object = value
            writable = false
        case .missing, .migrationFailed, .corrupt:
            return (PhraseStore(), true)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let file = try? Self.decoder().decode(File.self, from: data) else {
            return (PhraseStore(), writable)
        }
        return (PhraseStore(records: file.items), writable)
    }

    public func save(_ store: PhraseStore) throws {
        let file = File(schemaVersion: Self.currentSchemaVersion, items: store.sortedRecords())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(file)
        guard let object = try JSONSerialization.jsonObject(with: data) as? JSONObject else { return }
        try VersionedFile.save(object, to: url)
    }
}
