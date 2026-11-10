import Foundation

/// 解析後的 `.cin` 碼表（FR-K01）。只存在記憶體中，供建立索引檔使用（#3）。
public struct CinTable: Equatable, Sendable {
    /// `%ename`，例如 `liu57`。
    public var ename: String?
    /// `%cname`，例如顯示名稱。
    public var cname: String?
    /// `%selkey`，例如 `0123456789`。
    public var selkey: String?
    /// 其他檔頭（`%encoding`、`%gen_inp` 等），key 不含 `%`。
    public var otherHeaders: [String: String]
    /// `%keyname`：字根鍵 → 顯示標籤，依檔案順序。
    public var keyNames: [CinKeyName]
    /// `%chardef`：依檔案原始順序（候選字順序不得改變，FR-K05）。
    public var entries: [CinEntry]
    /// 偵測到的檔案編碼。
    public var encoding: CinEncoding

    /// 最長字根長度（以字元計）；嘸蝦米含假名碼實測為 5。
    public var maxCodeLength: Int {
        entries.reduce(0) { max($0, $1.code.count) }
    }

    /// 顯示名稱：`%cname` 優先，其次 `%ename`。
    public var displayName: String {
        cname ?? ename ?? "未命名碼表"
    }
}

public struct CinKeyName: Equatable, Sendable {
    public var key: String
    public var label: String
}

public struct CinEntry: Equatable, Sendable {
    /// 字根（已轉小寫）。
    public var code: String
    /// 候選字或詞。
    public var value: String

    public init(code: String, value: String) {
        self.code = code
        self.value = value
    }
}

public enum CinEncoding: String, Equatable, Sendable {
    case utf8 = "UTF-8"
    case utf8BOM = "UTF-8 (BOM)"
    case big5 = "Big5"
}

/// 解析時略過的行；只記錄行號與原因，**不記錄行內容**（可能含碼表資料）。
public struct CinParseIssue: Equatable, Sendable {
    public enum Reason: String, Equatable, Sendable {
        /// 區段內的行沒有「字根 + 空白 + 字」。
        case missingValue
        /// 字根超過索引檔上限（8 bytes）。
        case codeTooLong
        /// 字根含空白以外的控制字元或非 ASCII。
        case invalidCode
        /// 在任何區段之外、又不是 `%` 檔頭的行。
        case outsideSection
    }

    public var line: Int
    public var reason: Reason
}

public struct CinParseReport: Equatable, Sendable {
    /// 被略過的行數。
    public var skippedCount: Int
    /// 前 50 筆略過的行（行號與原因），用於在 App 顯示摘要。
    public var issues: [CinParseIssue]
}

public enum CinParseError: Error, Equatable {
    /// 檔案是空的。
    case empty
    /// 不是 UTF-8，且此平台無法以 Big5 解碼。
    case unsupportedEncoding
    /// 找不到任何 `%chardef` 資料。
    case noCharDef
}
