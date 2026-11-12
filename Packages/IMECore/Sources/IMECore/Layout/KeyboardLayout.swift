import Foundation

/// 鍵盤版面資料模型（docs/06_資料格式.md 第 1 章）。
///
/// 版面只描述「有哪些鍵、相對寬度、輸出什麼」；實際 pt 尺寸由 `LayoutEngine` 依螢幕寬度算出，
/// 顏色由主題決定。純資料與幾何，不依賴 UIKit，可在 Linux 上測試。

public enum KeyType: String, Decodable, Equatable, Sendable {
    case char
    case shift
    case backspace
    case space
    case returnKey = "return"
    case globe
    case emoji
    /// 切換頁面（字母 / 數字 / 符號），目標見 `LayoutKey.target`。
    case page
    /// 中 / 英切換鍵。
    case langToggle
    case tab
    /// 收起鍵盤。
    case dismiss
    /// 只佔位，不是按鍵；寬度加在相鄰兩鍵的間距上。
    case spacer
}

public struct LayoutKey: Equatable, Sendable, Decodable {
    public var type: KeyType
    /// 一般輸出；字元鍵的簡寫 `"q"` 即 `output: "q"`。
    public var output: String?
    /// Shift 時的輸出（例如 `!,` 鍵：`output: ","`、`shiftOutput: "!"`）。
    public var shiftOutput: String?
    /// 鍵帽文字，省略時用 `output`。
    public var label: String?
    /// 鍵上方的小字，往下滑輸入（FR-U25，iPad 與 iPhone）。
    public var secondary: String?
    /// 長按替代字元（FR-U06）。
    public var alternates: [String]
    /// 寬度，單位是「字母鍵寬」。
    public var width: Double
    /// `page` 型按鍵要切到的頁。
    public var target: String?
    /// 對齊上方某個鍵（以那個鍵的 `output` 指定）：位置與寬度和它相同，
    /// 同列其他鍵依各自的寬度比例分配剩下的空間（FR-U26）。
    public var alignWith: String?

    public init(
        type: KeyType = .char,
        output: String? = nil,
        shiftOutput: String? = nil,
        label: String? = nil,
        secondary: String? = nil,
        alternates: [String] = [],
        width: Double = 1,
        target: String? = nil,
        alignWith: String? = nil
    ) {
        self.type = type
        self.output = output
        self.shiftOutput = shiftOutput
        self.label = label
        self.secondary = secondary
        self.alternates = alternates
        self.width = width
        self.target = target
        self.alignWith = alignWith
    }

    /// 字元鍵簡寫。
    public init(char: String) {
        self.init(type: .char, output: char)
    }

    private enum CodingKeys: String, CodingKey {
        case type, output, shiftOutput, label, secondary, alternates, width, target, alignWith
    }

    public init(from decoder: Decoder) throws {
        // 字串簡寫："q" 等同 { "type": "char", "output": "q" }
        if let single = try? decoder.singleValueContainer(), let text = try? single.decode(String.self) {
            self = LayoutKey(char: text)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(KeyType.self, forKey: .type) ?? .char
        output = try container.decodeIfPresent(String.self, forKey: .output)
        shiftOutput = try container.decodeIfPresent(String.self, forKey: .shiftOutput)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        secondary = try container.decodeIfPresent(String.self, forKey: .secondary)
        alternates = try container.decodeIfPresent([String].self, forKey: .alternates) ?? []
        width = try container.decodeIfPresent(Double.self, forKey: .width) ?? 1
        target = try container.decodeIfPresent(String.self, forKey: .target)
        alignWith = try container.decodeIfPresent(String.self, forKey: .alignWith)
    }

    /// 鍵帽上顯示的文字。
    public var displayLabel: String {
        label ?? output ?? ""
    }

    /// 是否為實際可按的鍵（不含 `spacer`）。
    public var isTouchable: Bool {
        type != .spacer
    }
}

public struct LayoutRow: Equatable, Sendable, Decodable {
    public var keys: [LayoutKey]
    /// 左右各縮排幾個「字母鍵寬」（外加同比例的間距）；例如字母頁第 2 列為 0.5。
    public var inset: Double

    public init(keys: [LayoutKey], inset: Double = 0) {
        self.keys = keys
        self.inset = inset
    }

    private enum CodingKeys: String, CodingKey {
        case keys, inset
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keys = try container.decode([LayoutKey].self, forKey: .keys)
        inset = try container.decodeIfPresent(Double.self, forKey: .inset) ?? 0
    }
}

public struct LayoutPage: Equatable, Sendable, Decodable {
    public var rows: [LayoutRow]
    /// 橫向時使用的列；省略時橫向也用 `rows`。（橫向的按鍵寬度比例與直向不同）
    public var landscapeRows: [LayoutRow]?

    public init(rows: [LayoutRow], landscapeRows: [LayoutRow]? = nil) {
        self.rows = rows
        self.landscapeRows = landscapeRows
    }
}

/// 單一方向（直 / 橫）的尺寸參數，單位 pt。
public struct OrientationMetrics: Equatable, Sendable, Decodable {
    public var sideMargin: Double
    public var keyGap: Double
    public var rowGap: Double
    public var keyHeight: Double
    /// 按鍵區寬度；有值時在容器內置中（iPhone 橫向，兩側留給地球鍵與麥克風）。
    public var contentWidth: Double?
    /// 第一列上方的留白。
    public var topInset: Double
    /// 最後一列下方的留白。
    public var bottomInset: Double

    public init(
        sideMargin: Double, keyGap: Double, rowGap: Double, keyHeight: Double,
        contentWidth: Double? = nil, topInset: Double = 0, bottomInset: Double = 0
    ) {
        self.sideMargin = sideMargin
        self.keyGap = keyGap
        self.rowGap = rowGap
        self.keyHeight = keyHeight
        self.contentWidth = contentWidth
        self.topInset = topInset
        self.bottomInset = bottomInset
    }

    private enum CodingKeys: String, CodingKey {
        case sideMargin, keyGap, rowGap, keyHeight, contentWidth, topInset, bottomInset
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sideMargin = try container.decode(Double.self, forKey: .sideMargin)
        keyGap = try container.decode(Double.self, forKey: .keyGap)
        rowGap = try container.decode(Double.self, forKey: .rowGap)
        keyHeight = try container.decode(Double.self, forKey: .keyHeight)
        contentWidth = try container.decodeIfPresent(Double.self, forKey: .contentWidth)
        topInset = try container.decodeIfPresent(Double.self, forKey: .topInset) ?? 0
        bottomInset = try container.decodeIfPresent(Double.self, forKey: .bottomInset) ?? 0
    }
}

public struct LayoutMetrics: Equatable, Sendable, Decodable {
    public var portrait: OrientationMetrics
    public var landscape: OrientationMetrics

    public init(portrait: OrientationMetrics, landscape: OrientationMetrics) {
        self.portrait = portrait
        self.landscape = landscape
    }

    public func metrics(landscape isLandscape: Bool) -> OrientationMetrics {
        isLandscape ? landscape : portrait
    }
}

public enum LayoutError: Error, Equatable {
    case unsupportedSchema(Int)
    /// `page` 型按鍵指向不存在的頁面。
    case unknownPageTarget(page: String, target: String?)
}

public struct KeyboardLayoutFile: Equatable, Sendable, Decodable {
    public static let supportedSchemaVersion = 1

    public var schemaVersion: Int
    public var device: String
    public var metrics: LayoutMetrics
    public var pages: [String: LayoutPage]
    /// 情境變化（Email、網址等）：變化名稱 → 頁面名稱 → 列編號（字串）→ 取代的整列。
    public var variants: [String: [String: [String: LayoutRow]]]?

    public static func load(from data: Data) throws -> KeyboardLayoutFile {
        let file = try JSONDecoder().decode(KeyboardLayoutFile.self, from: data)
        guard file.schemaVersion == supportedSchemaVersion else {
            throw LayoutError.unsupportedSchema(file.schemaVersion)
        }
        try file.validate()
        return file
    }

    public static func load(contentsOf url: URL) throws -> KeyboardLayoutFile {
        try load(from: Data(contentsOf: url))
    }

    private func validate() throws {
        for (name, page) in pages {
            let allRows = page.rows + (page.landscapeRows ?? [])
            for key in allRows.flatMap(\.keys) where key.type == .page {
                guard let target = key.target, pages[target] != nil else {
                    throw LayoutError.unknownPageTarget(page: name, target: key.target)
                }
            }
        }
    }

    /// 取得頁面；指定 `variant` 時，套用該情境對各列的取代。
    public func page(_ name: String, variant: String? = nil) -> LayoutPage? {
        guard var page = pages[name] else { return nil }
        if let variant, let overrides = variants?[variant]?[name] {
            for (indexText, row) in overrides {
                guard let index = Int(indexText) else { continue }
                if page.rows.indices.contains(index) { page.rows[index] = row }
                if let landscape = page.landscapeRows, landscape.indices.contains(index) {
                    page.landscapeRows?[index] = row
                }
            }
        }
        return page
    }
}
