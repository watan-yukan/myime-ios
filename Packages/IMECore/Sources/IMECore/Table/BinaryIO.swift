import Foundation

/// 索引檔共用的 little-endian 讀寫與 CRC32。
enum BinaryIO {
    static func append(_ value: UInt8, to data: inout Data) {
        data.append(value)
    }

    static func append(_ value: UInt16, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    static func append(_ value: UInt32, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    /// UInt16 長度前綴 + UTF-8。
    static func appendString(_ string: String, to data: inout Data) {
        let bytes = Array(string.utf8.prefix(Int(UInt16.max)))
        append(UInt16(bytes.count), to: &data)
        data.append(contentsOf: bytes)
    }

    static func put(_ value: UInt32, at offset: Int, in data: inout Data) {
        let base = data.startIndex + offset
        withUnsafeBytes(of: value.littleEndian) { raw in
            for (i, byte) in raw.enumerated() { data[base + i] = byte }
        }
    }

    // MARK: - CRC32（IEEE 802.3）

    private static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
        }
        return c
    }

    /// 直接掃描連續記憶體，不經過泛型迭代器（大檔案時快很多，也包含未最佳化的 debug 編譯）。
    static func crc32(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> UInt32 in
            crcTable.withUnsafeBufferPointer { table -> UInt32 in
                var crc: UInt32 = 0xFFFF_FFFF
                for byte in raw {
                    crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
                }
                return crc ^ 0xFFFF_FFFF
            }
        }
    }
}

/// 以位移讀取 `Data`（不論 `startIndex` 是否為 0）。
struct ByteReader {
    let data: Data

    var count: Int { data.count }

    func u8(_ offset: Int) -> UInt8 {
        data[data.startIndex + offset]
    }

    func u16(_ offset: Int) -> UInt16 {
        UInt16(u8(offset)) | UInt16(u8(offset + 1)) << 8
    }

    func u32(_ offset: Int) -> UInt32 {
        UInt32(u8(offset))
            | UInt32(u8(offset + 1)) << 8
            | UInt32(u8(offset + 2)) << 16
            | UInt32(u8(offset + 3)) << 24
    }

    func bytes(_ offset: Int, _ length: Int) -> Data {
        let start = data.startIndex + offset
        return data[start..<(start + length)]
    }

    /// UInt16 長度前綴字串；回傳字串與下一個位移。
    func string(_ offset: Int) -> (String, Int) {
        let length = Int(u16(offset))
        let text = String(decoding: bytes(offset + 2, length), as: UTF8.self)
        return (text, offset + 2 + length)
    }
}
