import Foundation

/// 鍵帽顯示：英文字母，或碼表的字根標籤（`%keyname`）。FR-A04。
public enum KeycapLabel: String, Codable, Equatable, Sendable {
    case letter
    case radical
}

public struct ClipboardSettings: Equatable, Sendable, Codable {
    public var enabled = true
    public var maxItems = 20
    public var maxDays = 7

    public init() {}

    private enum CodingKeys: String, CodingKey { case enabled, maxItems, maxDays }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ClipboardSettings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        maxItems = try c.decodeIfPresent(Int.self, forKey: .maxItems) ?? d.maxItems
        maxDays = try c.decodeIfPresent(Int.self, forKey: .maxDays) ?? d.maxDays
    }
}

public struct ThemeSelection: Equatable, Sendable, Codable {
    public var id = "native"
    public var appearance = AppearanceSetting.system

    public init(id: String = "native", appearance: AppearanceSetting = .system) {
        self.id = id
        self.appearance = appearance
    }

    private enum CodingKeys: String, CodingKey { case id, appearance }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ThemeSelection()
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? d.id
        appearance = try c.decodeIfPresent(AppearanceSetting.self, forKey: .appearance) ?? d.appearance
    }
}

public struct BackupSettings: Equatable, Sendable, Codable {
    public var enabled = true
    public var keep = 10

    public init() {}

    private enum CodingKeys: String, CodingKey { case enabled, keep }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BackupSettings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        keep = try c.decodeIfPresent(Int.self, forKey: .keep) ?? d.keep
    }
}

/// 使用者設定（`settings.json`，docs/06_資料格式.md 3.1）。缺少的欄位一律使用預設值，舊檔仍可載入。
public struct KeyboardSettings: Equatable, Sendable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion = KeyboardSettings.currentSchemaVersion
    /// 按鍵音（`playInputClick`）。
    public var keySound = true
    /// 按鍵震動，需完整取用（FR-U14）。
    public var haptics = true
    /// 英文自動大寫（FR-U07）。
    public var autoCapitalize = true
    /// 雙空白句點（FR-U08）。
    public var doubleSpacePeriod = true
    /// 空白鍵上滑直輸英文（FR-E03、E04）。
    public var spaceSwipeUpEnglish = true
    /// 以上滑或英文選項送出英文後自動補空格（FR-E04）。
    public var spaceSwipeUpAppendSpace = false
    /// 送出的英文套用自動大寫（FR-E07）。
    public var autoCapitalizeEnglishSend = true
    /// 中文模式的半形符號轉全形（FR-K09）。
    public var fullWidthPunctuation = true
    /// 可選的數字列（FR-U22）。
    public var numberRow = false
    public var keycapLabel = KeycapLabel.letter
    /// 組字顯示位置（FR-K13）。
    public var composingDisplay = ComposingDisplay.bar
    /// 候選列字數，0 表示依寬度自動。
    public var candidateCount = 0
    /// 記錄常用詞（FR-S05）。
    public var phraseLearning = true
    public var clipboard = ClipboardSettings()
    public var theme = ThemeSelection()
    public var backup = BackupSettings()

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, keySound, haptics, autoCapitalize, doubleSpacePeriod
        case spaceSwipeUpEnglish, spaceSwipeUpAppendSpace, autoCapitalizeEnglishSend
        case fullWidthPunctuation, numberRow, keycapLabel, composingDisplay, candidateCount
        case phraseLearning, clipboard, theme, backup
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = KeyboardSettings()
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? d.schemaVersion
        keySound = try c.decodeIfPresent(Bool.self, forKey: .keySound) ?? d.keySound
        haptics = try c.decodeIfPresent(Bool.self, forKey: .haptics) ?? d.haptics
        autoCapitalize = try c.decodeIfPresent(Bool.self, forKey: .autoCapitalize) ?? d.autoCapitalize
        doubleSpacePeriod = try c.decodeIfPresent(Bool.self, forKey: .doubleSpacePeriod) ?? d.doubleSpacePeriod
        spaceSwipeUpEnglish = try c.decodeIfPresent(Bool.self, forKey: .spaceSwipeUpEnglish) ?? d.spaceSwipeUpEnglish
        spaceSwipeUpAppendSpace =
            try c.decodeIfPresent(Bool.self, forKey: .spaceSwipeUpAppendSpace) ?? d.spaceSwipeUpAppendSpace
        autoCapitalizeEnglishSend =
            try c.decodeIfPresent(Bool.self, forKey: .autoCapitalizeEnglishSend) ?? d.autoCapitalizeEnglishSend
        fullWidthPunctuation = try c.decodeIfPresent(Bool.self, forKey: .fullWidthPunctuation) ?? d.fullWidthPunctuation
        numberRow = try c.decodeIfPresent(Bool.self, forKey: .numberRow) ?? d.numberRow
        keycapLabel = try c.decodeIfPresent(KeycapLabel.self, forKey: .keycapLabel) ?? d.keycapLabel
        composingDisplay = try c.decodeIfPresent(ComposingDisplay.self, forKey: .composingDisplay) ?? d.composingDisplay
        candidateCount = try c.decodeIfPresent(Int.self, forKey: .candidateCount) ?? d.candidateCount
        phraseLearning = try c.decodeIfPresent(Bool.self, forKey: .phraseLearning) ?? d.phraseLearning
        clipboard = try c.decodeIfPresent(ClipboardSettings.self, forKey: .clipboard) ?? d.clipboard
        theme = try c.decodeIfPresent(ThemeSelection.self, forKey: .theme) ?? d.theme
        backup = try c.decodeIfPresent(BackupSettings.self, forKey: .backup) ?? d.backup
    }
}

/// 設定檔的讀寫：載入時自動升級，壞檔或較新的檔案都不會被覆蓋（FR-D06）。
public struct SettingsStore {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    private var migrator: JSONMigrator {
        JSONMigrator(currentVersion: KeyboardSettings.currentSchemaVersion)
    }

    /// 讀取設定；`writable` 為 false 代表檔案比這版 App 新，App 只讀不寫以免洗掉新欄位。
    public func load() -> (settings: KeyboardSettings, writable: Bool) {
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
            return (KeyboardSettings(), true)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let settings = try? JSONDecoder().decode(KeyboardSettings.self, from: data) else {
            return (KeyboardSettings(), writable)
        }
        return (settings, writable)
    }

    public func save(_ settings: KeyboardSettings) throws {
        let data = try JSONEncoder().encode(settings)
        guard let object = try JSONSerialization.jsonObject(with: data) as? JSONObject else { return }
        try VersionedFile.save(object, to: url)
    }
}
