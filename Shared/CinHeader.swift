import Foundation

/// .cin 碼表的檔頭資訊。Spike 只讀檔頭，不載入整份碼表（記憶體限制 L2）。
struct CinHeader {
    var ename: String?
    var cname: String?
    var selkey: String?
    var encoding: String
    var byteSize: Int

    var displayName: String {
        cname ?? ename ?? "（未命名碼表）"
    }
}

enum CinHeaderReader {
    /// 只讀前 16 KB，足以涵蓋 %chardef 之前的檔頭。
    private static let headerBytes = 16 * 1024

    static func read(url: URL) throws -> CinHeader {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: headerBytes) ?? Data()

        let (text, encoding) = decode(data)
        var header = CinHeader(ename: nil, cname: nil, selkey: nil, encoding: encoding, byteSize: size)

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("%chardef") { break }
            let parts = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count == 2 else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            switch parts[0] {
            case "%ename": header.ename = value
            case "%cname": header.cname = value
            case "%selkey": header.selkey = value
            default: break
            }
        }
        return header
    }

    /// 先試 UTF-8，再試 Big5。截斷在多位元組字元中間時，丟掉結尾幾個位元組再試。
    private static func decode(_ data: Data) -> (String, String) {
        let big5 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.big5.rawValue)))
        let candidates: [(String.Encoding, String)] = [(.utf8, "UTF-8"), (big5, "Big5")]

        for (encoding, name) in candidates {
            var slice = data
            for _ in 0..<4 {
                if let text = String(data: slice, encoding: encoding) {
                    return (text, name)
                }
                guard !slice.isEmpty else { break }
                slice = slice.dropLast()
            }
        }
        return (String(decoding: data, as: UTF8.self), "未知")
    }
}
