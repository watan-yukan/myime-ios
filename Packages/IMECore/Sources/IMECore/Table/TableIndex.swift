import Foundation

/// 唯讀碼表索引（鍵盤執行時使用，Issue #3、NFR-15）。
///
/// 以 memory-map 開啟，不把整張表載入記憶體；查詢用二分搜尋。
public struct TableIndex: Sendable {
    public struct Meta: Equatable, Sendable {
        public var ename: String
        public var cname: String
        public var selkey: String
        public var keyNames: [CinKeyName]
        public var maxCodeLength: Int
        public var codeCount: Int
        public var valueCount: Int
        public var sourceFingerprint: [UInt8]

        public var displayName: String {
            !cname.isEmpty ? cname : (!ename.isEmpty ? ename : "未命名碼表")
        }
    }

    public let meta: Meta

    private let reader: ByteReader
    private let codesOffset: Int
    private let valuesOffset: Int
    private let reverseOffset: Int

    /// 以 memory-map 開啟索引檔。
    public init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .alwaysMapped))
    }

    public init(data: Data) throws {
        let reader = ByteReader(data: data)
        let headerSize = TableIndexFormat.headerSize
        guard reader.count >= headerSize + TableIndexFormat.footerSize else { throw TableIndexError.truncated }
        guard Array(reader.bytes(0, 4)) == TableIndexFormat.magic else { throw TableIndexError.badMagic }

        let version = reader.u16(TableIndexFormat.HeaderOffset.formatVersion)
        guard version == IMECore.tableFormatVersion else { throw TableIndexError.unsupportedVersion(version) }

        let bodyLength = reader.count - TableIndexFormat.footerSize
        let storedCRC = reader.u32(bodyLength)
        guard BinaryIO.crc32(reader.bytes(0, bodyLength)) == storedCRC else { throw TableIndexError.checksumMismatch }

        func section(_ at: Int) throws -> (Int, Int) {
            let offset = Int(reader.u32(at)), length = Int(reader.u32(at + 4))
            guard offset >= headerSize, offset + length <= bodyLength else { throw TableIndexError.truncated }
            return (offset, length)
        }
        let (metaOffset, _) = try section(TableIndexFormat.HeaderOffset.metaOffset)
        let (codesOffset, codesLength) = try section(TableIndexFormat.HeaderOffset.codesOffset)
        let (valuesOffset, _) = try section(TableIndexFormat.HeaderOffset.valuesOffset)
        let (reverseOffset, reverseLength) = try section(TableIndexFormat.HeaderOffset.reverseOffset)

        let codeCount = Int(reader.u32(TableIndexFormat.HeaderOffset.codeCount))
        let valueCount = Int(reader.u32(TableIndexFormat.HeaderOffset.valueCount))
        guard codesLength == codeCount * TableIndexFormat.codeRecordSize,
              reverseLength == valueCount * TableIndexFormat.reverseRecordSize else {
            throw TableIndexError.truncated
        }

        var cursor = metaOffset
        func nextString() -> String {
            let (text, next) = reader.string(cursor)
            cursor = next
            return text
        }
        let ename = nextString()
        let cname = nextString()
        let selkey = nextString()
        let keyNameCount = Int(reader.u16(cursor))
        cursor += 2
        var keyNames: [CinKeyName] = []
        keyNames.reserveCapacity(keyNameCount)
        for _ in 0..<keyNameCount {
            let key = nextString()
            let label = nextString()
            keyNames.append(CinKeyName(key: key, label: label))
        }

        self.reader = reader
        self.codesOffset = codesOffset
        self.valuesOffset = valuesOffset
        self.reverseOffset = reverseOffset
        self.meta = Meta(
            ename: ename, cname: cname, selkey: selkey, keyNames: keyNames,
            maxCodeLength: Int(reader.u8(TableIndexFormat.HeaderOffset.maxCodeLength)),
            codeCount: codeCount, valueCount: valueCount,
            sourceFingerprint: Array(reader.bytes(TableIndexFormat.HeaderOffset.fingerprint, 16))
        )
    }

    // MARK: - 查詢

    /// 字根完全相符的候選，依碼表原始順序（FR-K03、K05）。
    public func candidates(for code: String) -> [String] {
        let key = TableIndexFormat.codeBytes(code.lowercased())
        guard code.utf8.count <= TableIndexFormat.codeFieldSize else { return [] }
        let index = lowerBound(key)
        guard index < meta.codeCount, compareCode(at: index, with: key) == 0 else { return [] }
        return values(ofCodeAt: index)
    }

    /// 是否有任何字根以 `prefix` 開頭（組字時判斷是否為錯碼，FR-K07）。
    public func hasCode(withPrefix prefix: String) -> Bool {
        !codes(withPrefix: prefix, limit: 1).isEmpty
    }

    /// 以 `prefix` 開頭的字根，依排序，最多 `limit` 個（預覽、萬用字元查碼 FR-K11）。
    public func codes(withPrefix prefix: String, limit: Int = .max) -> [String] {
        let prefixBytes = Array(prefix.lowercased().utf8)
        guard prefixBytes.count <= TableIndexFormat.codeFieldSize, limit > 0 else { return [] }
        var index = lowerBound(TableIndexFormat.codeBytes(prefix.lowercased()))
        var result: [String] = []
        while index < meta.codeCount, result.count < limit {
            let code = codeBytes(at: index)
            guard code.starts(with: prefixBytes) else { break }
            result.append(String(decoding: code.prefix { $0 != 0 }, as: UTF8.self))
            index += 1
        }
        return result
    }

    /// 反查字根：某個字的所有拆碼，短碼在前（FR-S07）。
    public func codes(for value: String) -> [String] {
        let target = Array(value.utf8)
        var low = 0, high = meta.valueCount
        while low < high {
            let mid = (low + high) / 2
            if reverseValueBytes(at: mid).lexicographicallyPrecedes(target) { low = mid + 1 } else { high = mid }
        }
        var result: [String] = []
        var index = low
        while index < meta.valueCount, reverseValueBytes(at: index) == target {
            let codeIndex = Int(reader.u32(reverseOffset + index * TableIndexFormat.reverseRecordSize + 4))
            result.append(String(decoding: codeBytes(at: codeIndex).prefix { $0 != 0 }, as: UTF8.self))
            index += 1
        }
        return result
    }

    // MARK: - 內部

    private func codeBytes(at index: Int) -> [UInt8] {
        Array(reader.bytes(codesOffset + index * TableIndexFormat.codeRecordSize, TableIndexFormat.codeFieldSize))
    }

    private func compareCode(at index: Int, with key: [UInt8]) -> Int {
        let code = codeBytes(at: index)
        if code == key { return 0 }
        return code.lexicographicallyPrecedes(key) ? -1 : 1
    }

    /// 第一個 >= key 的紀錄位置。
    private func lowerBound(_ key: [UInt8]) -> Int {
        var low = 0, high = meta.codeCount
        while low < high {
            let mid = (low + high) / 2
            if compareCode(at: mid, with: key) < 0 { low = mid + 1 } else { high = mid }
        }
        return low
    }

    private func values(ofCodeAt index: Int) -> [String] {
        let record = codesOffset + index * TableIndexFormat.codeRecordSize
        let start = Int(reader.u32(record + TableIndexFormat.codeFieldSize))
        let count = Int(reader.u16(record + TableIndexFormat.codeFieldSize + 4))
        return (start..<(start + count)).map { value(at: $0) }
    }

    private func value(at valueIndex: Int) -> String {
        let offset = Int(reader.u32(valuesOffset + valueIndex * 4))
        return reader.string(valuesOffset + offset).0
    }

    private func reverseValueBytes(at index: Int) -> [UInt8] {
        let valueIndex = Int(reader.u32(reverseOffset + index * TableIndexFormat.reverseRecordSize))
        let offset = valuesOffset + Int(reader.u32(valuesOffset + valueIndex * 4))
        return Array(reader.bytes(offset + 2, Int(reader.u16(offset))))
    }
}
