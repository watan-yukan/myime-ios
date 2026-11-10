import Foundation

/// 由 `CinTable` 建立碼表索引檔（主 App 匯入時使用，Issue #3）。
public enum TableIndexBuilder {

    /// - Parameter sourceFingerprint: 來源 `.cin` 的指紋（App 端用 SHA-256 前 16 bytes）；可省略。
    public static func build(from table: CinTable, sourceFingerprint: [UInt8] = []) -> Data {
        // 1. 依字根分組，組內保留碼表原始順序（FR-K05），移除同字根下完全重複的候選
        var order: [String] = []
        var groups: [String: [String]] = [:]
        for entry in table.entries {
            if groups[entry.code] == nil {
                groups[entry.code] = []
                order.append(entry.code)
            }
            if !(groups[entry.code]!.contains(entry.value)) {
                groups[entry.code]!.append(entry.value)
            }
        }

        // 2. 字根依 8 bytes 形式排序，供二分搜尋
        let sortedCodes = order.sorted {
            TableIndexFormat.codeBytes($0).lexicographicallyPrecedes(TableIndexFormat.codeBytes($1))
        }

        // 3. 依排序後的字根依序配發候選編號
        var values: [String] = []
        var codeRecords: [(code: String, start: Int, count: Int)] = []
        var valueCode: [Int] = []  // valueIndex → codeIndex
        for (codeIndex, code) in sortedCodes.enumerated() {
            let list = groups[code]!
            codeRecords.append((code, values.count, list.count))
            values.append(contentsOf: list)
            valueCode.append(contentsOf: repeatElement(codeIndex, count: list.count))
        }

        // 4. 組各區段
        let meta = buildMeta(table)
        let codesSection = buildCodes(codeRecords)
        let valuesSection = buildValues(values)
        let reverseSection = buildReverse(values: values, valueCode: valueCode, codes: sortedCodes)

        var data = Data(count: TableIndexFormat.headerSize)
        let metaOffset = data.count
        data.append(meta)
        let codesOffset = data.count
        data.append(codesSection)
        let valuesOffset = data.count
        data.append(valuesSection)
        let reverseOffset = data.count
        data.append(reverseSection)

        // 5. Header
        var header = Data()
        header.append(contentsOf: TableIndexFormat.magic)
        BinaryIO.append(IMECore.tableFormatVersion, to: &header)
        BinaryIO.append(UInt16(0), to: &header)
        BinaryIO.append(UInt32(sortedCodes.count), to: &header)
        BinaryIO.append(UInt32(values.count), to: &header)
        BinaryIO.append(UInt8(min(table.maxCodeLength, Int(UInt8.max))), to: &header)
        header.append(contentsOf: [0, 0, 0])
        for (offset, length) in [
            (metaOffset, meta.count), (codesOffset, codesSection.count),
            (valuesOffset, valuesSection.count), (reverseOffset, reverseSection.count),
        ] {
            BinaryIO.append(UInt32(offset), to: &header)
            BinaryIO.append(UInt32(length), to: &header)
        }
        var fingerprint = Array(sourceFingerprint.prefix(16))
        fingerprint.append(contentsOf: repeatElement(0, count: 16 - fingerprint.count))
        header.append(contentsOf: fingerprint)
        header.append(Data(count: TableIndexFormat.headerSize - header.count))
        data.replaceSubrange(0..<TableIndexFormat.headerSize, with: header)

        // 6. Footer CRC32
        BinaryIO.append(BinaryIO.crc32(data), to: &data)
        return data
    }

    private static func buildMeta(_ table: CinTable) -> Data {
        var data = Data()
        BinaryIO.appendString(table.ename ?? "", to: &data)
        BinaryIO.appendString(table.cname ?? "", to: &data)
        BinaryIO.appendString(table.selkey ?? "", to: &data)
        BinaryIO.append(UInt16(min(table.keyNames.count, Int(UInt16.max))), to: &data)
        for keyName in table.keyNames.prefix(Int(UInt16.max)) {
            BinaryIO.appendString(keyName.key, to: &data)
            BinaryIO.appendString(keyName.label, to: &data)
        }
        return data
    }

    private static func buildCodes(_ records: [(code: String, start: Int, count: Int)]) -> Data {
        var data = Data(capacity: records.count * TableIndexFormat.codeRecordSize)
        for record in records {
            data.append(contentsOf: TableIndexFormat.codeBytes(record.code))
            BinaryIO.append(UInt32(record.start), to: &data)
            BinaryIO.append(UInt16(min(record.count, Int(UInt16.max))), to: &data)
            BinaryIO.append(UInt16(0), to: &data)
        }
        return data
    }

    /// 位移表 + 字串池；相同字串只存一次。
    private static func buildValues(_ values: [String]) -> Data {
        var pool = Data()
        var poolOffsets: [String: Int] = [:]
        var offsets: [Int] = []
        offsets.reserveCapacity(values.count)
        for value in values {
            if let existing = poolOffsets[value] {
                offsets.append(existing)
            } else {
                poolOffsets[value] = pool.count
                offsets.append(pool.count)
                BinaryIO.appendString(value, to: &pool)
            }
        }
        let tableSize = values.count * 4
        var data = Data(capacity: tableSize + pool.count)
        for offset in offsets {
            BinaryIO.append(UInt32(tableSize + offset), to: &data)
        }
        data.append(pool)
        return data
    }

    /// 依「字 → 字根長度 → 字根順序」排序，反查時短碼在前。
    private static func buildReverse(values: [String], valueCode: [Int], codes: [String]) -> Data {
        let valueBytes = values.map { Array($0.utf8) }
        let order = values.indices.sorted { a, b in
            if valueBytes[a] != valueBytes[b] {
                return valueBytes[a].lexicographicallyPrecedes(valueBytes[b])
            }
            let codeA = codes[valueCode[a]], codeB = codes[valueCode[b]]
            if codeA.count != codeB.count { return codeA.count < codeB.count }
            return valueCode[a] < valueCode[b]
        }
        var data = Data(capacity: order.count * TableIndexFormat.reverseRecordSize)
        for valueIndex in order {
            BinaryIO.append(UInt32(valueIndex), to: &data)
            BinaryIO.append(UInt32(valueCode[valueIndex]), to: &data)
        }
        return data
    }
}
