import Foundation

/// 匯入完成後給畫面顯示的摘要（碼表名稱、字數、編碼等）。
public struct ImportSummary: Equatable, Sendable {
    public var name: String
    public var selkey: String
    /// 候選字總數（同一字根的重碼各算一個）。
    public var entryCount: Int
    /// 不重複的字根數。
    public var codeCount: Int
    public var maxCodeLength: Int
    public var encoding: String
    /// 格式錯誤而略過的行數。
    public var skippedLines: Int
    /// 字根中實際出現的非字母字元（例如 `,` `.`）。
    public var extraCodeKeys: String
}

public struct ImportResult: Equatable {
    public var indexData: Data
    public var summary: ImportSummary
}

public enum TableImportError: Error, Equatable {
    /// 檔案太大，不像是碼表。
    case tooLarge
    case parse(CinParseError)
    /// 建好的索引讀不回來（不應發生；發生時不會覆蓋現有碼表）。
    case invalidResult
}

/// 匯入 `.cin`：解析 → 建立索引 → 讀回驗證（FR-A03）。純邏輯，不碰檔案；寫檔由主 App 負責。
public enum TableImporter {
    /// 超過這個大小不當作碼表（一般碼表不到 1 MB）。
    public static let maxFileSize = 20_000_000

    public static func build(from data: Data) throws -> ImportResult {
        guard data.count <= maxFileSize else { throw TableImportError.tooLarge }

        let table: CinTable
        let report: CinParseReport
        do {
            (table, report) = try CinParser.parse(data: data)
        } catch let error as CinParseError {
            throw TableImportError.parse(error)
        }

        let indexData = TableIndexBuilder.build(from: table, sourceFingerprint: SourceFingerprint.compute(data))

        // 讀回驗證：完整檢查碼、確認筆數一致，才算匯入成功
        guard let index = try? TableIndex(data: indexData), index.checksumIsValid(),
              index.meta.valueCount > 0 else {
            throw TableImportError.invalidResult
        }
        let summary = ImportSummary(
            name: index.meta.displayName,
            selkey: index.meta.selkey,
            entryCount: index.meta.valueCount,
            codeCount: index.meta.codeCount,
            maxCodeLength: index.meta.maxCodeLength,
            encoding: table.encoding.rawValue,
            skippedLines: report.skippedCount,
            extraCodeKeys: index.meta.extraCodeKeys)
        return ImportResult(indexData: indexData, summary: summary)
    }
}

/// 來源檔指紋（16 bytes）：用來判斷索引是不是由目前這份 `.cin` 建出來的。
/// 兩組不同種子的 FNV-1a 64 位元，**不是密碼學雜湊**，只用於偵測變動。
public enum SourceFingerprint {
    public static func compute(_ data: Data) -> [UInt8] {
        var first: UInt64 = 0xcbf29ce484222325
        var second: UInt64 = 0x84222325cbf29ce4
        let prime: UInt64 = 0x100000001b3
        for byte in data {
            first = (first ^ UInt64(byte)) &* prime
            second = (second ^ UInt64(byte) ^ 0x5a) &* prime
        }
        return bytes(first) + bytes(second)
    }

    private static func bytes(_ value: UInt64) -> [UInt8] {
        (0..<8).map { UInt8((value >> (UInt64($0) * 8)) & 0xFF) }
    }
}
