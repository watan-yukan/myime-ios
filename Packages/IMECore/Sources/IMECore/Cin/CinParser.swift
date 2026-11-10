import Foundation

/// `.cin` 碼表解析器（FR-K01、Issue #2）。
///
/// - 編碼：UTF-8（含 BOM）為主；不是合法 UTF-8 時，在 Apple 平台改以 Big5 解碼。
/// - 容錯：註解（`#`）、空行、CRLF、Tab / 多個空白分隔、未結束的區段都可接受；
///   格式錯誤的行略過並記入 `CinParseReport`，不中斷解析。
/// - 順序：`%chardef` 依檔案原始順序保留（FR-K05）。
public enum CinParser {
    /// 字根上限（bytes），對應索引檔 `code[8]`（docs/06_資料格式.md 2.1）。
    public static let maxCodeBytes = 8
    static let maxRecordedIssues = 50

    public static func parse(contentsOf url: URL) throws -> (CinTable, CinParseReport) {
        try parse(data: Data(contentsOf: url))
    }

    public static func parse(data: Data) throws -> (CinTable, CinParseReport) {
        guard !data.isEmpty else { throw CinParseError.empty }
        let (text, encoding) = try decode(data)
        return try parse(text: text, encoding: encoding)
    }

    // MARK: - 解碼

    static func decode(_ data: Data) throws -> (String, CinEncoding) {
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        if data.count >= 3, Array(data.prefix(3)) == bom {
            guard let text = String(data: data.dropFirst(3), encoding: .utf8) else {
                throw CinParseError.unsupportedEncoding
            }
            return (text, .utf8BOM)
        }
        if let text = String(data: data, encoding: .utf8) {
            return (text, .utf8)
        }
        if let text = decodeBig5(data) {
            return (text, .big5)
        }
        throw CinParseError.unsupportedEncoding
    }

    static func decodeBig5(_ data: Data) -> String? {
        #if canImport(Darwin)
        let cfEncoding = CFStringEncoding(CFStringEncodings.big5_HKSCS_1999.rawValue)
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        return String(data: data, encoding: String.Encoding(rawValue: nsEncoding))
        #else
        // Linux / Windows 的 Foundation 不保證支援 Big5；實際使用者碼表為 UTF-8（Spike 0.13）。
        return nil
        #endif
    }

    // MARK: - 解析

    private enum Section {
        case none, keyname, chardef
    }

    static func parse(text: String, encoding: CinEncoding) throws -> (CinTable, CinParseReport) {
        var table = CinTable(
            ename: nil, cname: nil, selkey: nil,
            otherHeaders: [:], keyNames: [], entries: [], encoding: encoding
        )
        var report = CinParseReport(skippedCount: 0, issues: [])
        var section = Section.none

        func skip(_ line: Int, _ reason: CinParseIssue.Reason) {
            report.skippedCount += 1
            if report.issues.count < maxRecordedIssues {
                report.issues.append(CinParseIssue(line: line, reason: reason))
            }
        }

        var lineNumber = 0
        // Swift 把 "\r\n" 視為單一 Character，所以要分別比對三種換行
        let lines = text.split(omittingEmptySubsequences: false) {
            $0 == "\n" || $0 == "\r\n" || $0 == "\r"
        }
        for rawLine in lines {
            lineNumber += 1
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }

            if line.hasPrefix("%") {
                let (key, value) = splitFirstWhitespace(String(line.dropFirst()))
                let lowerKey = key.lowercased()
                let lowerValue = value.lowercased()
                if lowerKey == "keyname" || lowerKey == "chardef" {
                    if lowerValue.hasPrefix("begin") {
                        section = lowerKey == "keyname" ? .keyname : .chardef
                        continue
                    }
                    if lowerValue.hasPrefix("end") {
                        section = .none
                        continue
                    }
                }
                // 區段內以 % 開頭的行（例如字根本身是 %）仍當作資料處理
                if section == .none {
                    switch lowerKey {
                    case "ename": table.ename = value
                    case "cname": table.cname = value
                    case "selkey": table.selkey = value
                    default: table.otherHeaders[lowerKey] = value
                    }
                    continue
                }
            }

            switch section {
            case .none:
                skip(lineNumber, .outsideSection)
            case .keyname:
                let (key, label) = splitFirstWhitespace(line)
                guard !label.isEmpty else { skip(lineNumber, .missingValue); continue }
                table.keyNames.append(CinKeyName(key: key.lowercased(), label: label))
            case .chardef:
                let (code, value) = splitFirstWhitespace(line)
                guard !value.isEmpty else { skip(lineNumber, .missingValue); continue }
                let lowerCode = code.lowercased()
                guard isValidCode(lowerCode) else { skip(lineNumber, .invalidCode); continue }
                guard lowerCode.utf8.count <= maxCodeBytes else { skip(lineNumber, .codeTooLong); continue }
                table.entries.append(CinEntry(code: lowerCode, value: value))
            }
        }

        guard !table.entries.isEmpty else { throw CinParseError.noCharDef }
        return (table, report)
    }

    /// 以第一段空白（空格或 Tab，可連續）切成兩半；後半去頭尾空白。
    static func splitFirstWhitespace(_ line: String) -> (String, String) {
        guard let index = line.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
            return (line, "")
        }
        let head = String(line[..<index])
        let tail = line[index...].trimmingCharacters(in: .whitespaces)
        return (head, tail)
    }

    /// 字根只允許可見的 ASCII（字母、數字、標點），不含空白與控制字元。
    static func isValidCode(_ code: String) -> Bool {
        !code.isEmpty && code.unicodeScalars.allSatisfy { $0.value > 0x20 && $0.value < 0x7F }
    }
}
