import Foundation

/// 內建詞庫的查詢介面（FR-S02）：讓 `PhraseStore` 不必知道詞庫怎麼存，測試時也能換成假的。
public protocol PhraseLexicon: AnyObject {
    /// 以 `prefix` 開頭、且比 `prefix` 長的詞，依次數由高到低，最多 `limit` 個。
    func phrases(withPrefix prefix: String, limit: Int) -> [(text: String, count: Int)]
}

/// 內建開源詞庫（McBopomofo `phrase.occ`，MIT；由 `Tools/build_lexicon.pl` 轉成 `lexicon.txt`）。
///
/// 檔案格式：每行「詞<TAB>次數」，同一個開頭字的詞連在一起。
/// 鍵盤擴充程式記憶體很少，所以**不把 10 萬個詞展開成字串**：整個檔案以記憶體對應方式讀入
/// （約 1 MB），只建「開頭字 → 位元組範圍」的索引，查詢時才解碼那一小段。
public final class Lexicon: PhraseLexicon {
    private let data: Data
    private var index: [String: Range<Int>]?

    public init(data: Data) {
        self.data = data
    }

    public convenience init?(url: URL) {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return nil }
        self.init(data: data)
    }

    /// 索引在第一次查詢時才建立，不拖慢鍵盤出現的速度。
    private func buildIndex() -> [String: Range<Int>] {
        var result: [String: Range<Int>] = [:]
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let bytes = raw.bindMemory(to: UInt8.self)
            let total = bytes.count
            var groupKey: [UInt8] = []
            var groupStart = 0
            var lineStart = 0
            while lineStart < total {
                // 開頭字的 UTF-8 長度由第一個位元組決定
                let lead = bytes[lineStart]
                let length = lead < 0x80 ? 1 : (lead < 0xE0 ? 2 : (lead < 0xF0 ? 3 : 4))
                let keyEnd = min(lineStart + length, total)
                let key = Array(bytes[lineStart..<keyEnd])
                if key != groupKey {
                    if !groupKey.isEmpty, let text = String(bytes: groupKey, encoding: .utf8) {
                        result[text] = groupStart..<lineStart
                    }
                    groupKey = key
                    groupStart = lineStart
                }
                var next = lineStart
                while next < total, bytes[next] != 0x0A { next += 1 }
                lineStart = next + 1
            }
            if !groupKey.isEmpty, let text = String(bytes: groupKey, encoding: .utf8) {
                result[text] = groupStart..<min(lineStart, total)
            }
        }
        return result
    }

    public func phrases(withPrefix prefix: String, limit: Int) -> [(text: String, count: Int)] {
        guard let first = prefix.first, limit > 0 else { return [] }
        if index == nil { index = buildIndex() }
        guard let range = index?[String(first)],
              let block = String(data: data.subdata(in: range), encoding: .utf8) else { return [] }
        var found: [(text: String, count: Int)] = []
        for line in block.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t")
            guard parts.count == 2 else { continue }
            let text = String(parts[0])
            guard text.count > prefix.count, text.hasPrefix(prefix), let count = Int(parts[1]) else { continue }
            found.append((text, count))
        }
        found.sort { $0.count != $1.count ? $0.count > $1.count : $0.text < $1.text }
        return Array(found.prefix(limit))
    }
}
