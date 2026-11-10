import Foundation

/// 碼表索引檔 `table.idx` 的版面定義（docs/06_資料格式.md 第 2 章，ADR-01）。
///
/// ```
/// Header (80 bytes)
///   0  magic "MYIX"
///   4  formatVersion   UInt16
///   6  flags           UInt16 (保留，0)
///   8  codeCount       UInt32  不重複字根數
///  12  valueCount      UInt32  候選總數
///  16  maxCodeLength   UInt8   + 3 bytes 保留
///  20  meta     offset/length  UInt32 × 2
///  28  codes    offset/length  UInt32 × 2
///  36  values   offset/length  UInt32 × 2
///  44  reverse  offset/length  UInt32 × 2
///  52  sourceFingerprint 16 bytes（App 端以 SHA-256 前 16 bytes 填入；可全 0）
///  68  保留 12 bytes
/// Meta     ename / cname / selkey（UInt16 長度前綴 UTF-8）、keyName 數 UInt16、(key, label) × N
/// Codes    依字根 bytes 排序的 16 bytes 紀錄：code[8] | valueStart UInt32 | valueCount UInt16 | 保留 UInt16
/// Values   UInt32 位移表 × valueCount（相對 Values 區段起點的字串位置）＋ 字串池（UInt16 長度前綴 UTF-8）
/// Reverse  依候選字 bytes 排序的 8 bytes 紀錄：valueIndex UInt32 | codeIndex UInt32
/// Footer   CRC32 UInt32（涵蓋 footer 之前所有 bytes）
/// ```
enum TableIndexFormat {
    static let magic: [UInt8] = Array("MYIX".utf8)
    static let headerSize = 80
    static let codeRecordSize = 16
    static let reverseRecordSize = 8
    static let codeFieldSize = 8
    static let footerSize = 4

    enum HeaderOffset {
        static let formatVersion = 4
        static let codeCount = 8
        static let valueCount = 12
        static let maxCodeLength = 16
        static let metaOffset = 20
        static let codesOffset = 28
        static let valuesOffset = 36
        static let reverseOffset = 44
        static let fingerprint = 52
    }

    /// 把字根轉成 8 bytes（不足補 0），排序與比較都用這個形式。
    static func codeBytes(_ code: String) -> [UInt8] {
        var bytes = Array(code.utf8.prefix(codeFieldSize))
        if bytes.count < codeFieldSize {
            bytes.append(contentsOf: repeatElement(0, count: codeFieldSize - bytes.count))
        }
        return bytes
    }
}

public enum TableIndexError: Error, Equatable {
    /// 檔案太短或區段位移超出範圍。
    case truncated
    /// 不是 MyIME 索引檔。
    case badMagic
    /// 格式版本與目前程式不符，需以 `.cin` 重建。
    case unsupportedVersion(UInt16)
    /// 檢查碼不符：檔案損壞，需重新匯入。
    case checksumMismatch
}
