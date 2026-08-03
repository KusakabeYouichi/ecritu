import CoreText
import Foundation

// 漢字1文字ピッカーの索引。KanjiRadicalIndex.txt(部首番号→部首内画数→コードポイント順に
// バイト順ソート済み。1行 = "NNN\tSS\t字\t区点\t読み")を Data(mappedIfSafe) のまま保持し、
// 行頭 "NNN\t" のバイナリサーチで部首ブロックだけを切り出す。欧文語彙
// (GenericLatinLexiconFileIndex)と同じ方式で、常駐フットプリントを持たない。
struct KanjiRadicalFileIndex {
    struct Entry {
        let character: String
        let residualStrokes: Int
        let kuten: String
        let readings: String
    }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    var isEmpty: Bool { data.isEmpty }

    // 部首番号(1〜214)に属する字を、部首内画数→コードポイント順で返す。
    func entries(radical: Int) -> [Entry] {
        guard 1...214 ~= radical, !data.isEmpty else {
            return []
        }
        let key = Array(String(format: "%03d\t", radical).utf8)
        var results: [Entry] = []
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            let bytes = buffer.bindMemory(to: UInt8.self)
            let n = bytes.count

            func lineStart(atOrBefore offset: Int) -> Int {
                var i = offset
                while i > 0, bytes[i - 1] != 0x0A {
                    i -= 1
                }
                return i
            }
            // 行頭 start のキー("NNN\t")が key より小さいか
            func keyIsLess(lineStart start: Int) -> Bool {
                var i = start
                var j = 0
                while j < key.count {
                    if i >= n || bytes[i] == 0x0A {
                        return true
                    }
                    if bytes[i] != key[j] {
                        return bytes[i] < key[j]
                    }
                    i += 1
                    j += 1
                }
                return false
            }

            var low = 0
            var high = n
            while low < high {
                let mid = (low + high) / 2
                let start = lineStart(atOrBefore: mid)
                if keyIsLess(lineStart: start) {
                    var end = mid
                    while end < n, bytes[end] != 0x0A {
                        end += 1
                    }
                    low = end + 1
                } else {
                    high = start
                }
            }

            var cursor = low
            while cursor < n {
                var matches = true
                var i = cursor
                for byte in key {
                    if i >= n || bytes[i] != byte {
                        matches = false
                        break
                    }
                    i += 1
                }
                guard matches else {
                    break
                }
                var lineEnd = cursor
                while lineEnd < n, bytes[lineEnd] != 0x0A {
                    lineEnd += 1
                }
                // フィールド分解: radical \t strokes \t 字 \t 区点 \t 読み
                var fieldStarts: [Int] = [cursor]
                var scan = cursor
                while scan < lineEnd {
                    if bytes[scan] == 0x09 {
                        fieldStarts.append(scan + 1)
                    }
                    scan += 1
                }
                if fieldStarts.count == 5 {
                    func field(_ index: Int) -> String {
                        let start = fieldStarts[index]
                        let end = index + 1 < fieldStarts.count ? fieldStarts[index + 1] - 1 : lineEnd
                        return String(decoding: bytes[start..<end], as: UTF8.self)
                    }
                    let character = field(2)
                    if !character.isEmpty {
                        results.append(
                            Entry(
                                character: character,
                                residualStrokes: Int(field(1)) ?? 0,
                                kuten: field(3),
                                readings: field(4)
                            )
                        )
                    }
                }
                cursor = lineEnd + 1
            }
        }
        return results
    }
}

extension KanaKanjiStore {
    // 索引の mmap は初回参照時に開き、以後キャッシュする(Data 保持のみなので常駐コスト無し)。
    func kanjiRadicalIndex() -> KanjiRadicalFileIndex {
        if let cached = withCacheLock({ cachedKanjiRadicalIndex }) {
            return cached
        }
        let url = kanjiRadicalIndexDirectoryURLOverride?
            .appendingPathComponent("KanjiRadicalIndex.txt")
            ?? Bundle(for: KanaKanjiStore.self).url(forResource: "KanjiRadicalIndex", withExtension: "txt")
        let data = url.flatMap { try? Data(contentsOf: $0, options: .mappedIfSafe) } ?? Data()
        let index = KanjiRadicalFileIndex(data: data)
        withCacheLock { cachedKanjiRadicalIndex = index }
        return index
    }

    // 表示中のセルぶんだけ「ヒラギノ明朝にグリフがあるか」を判定する。無い字は
    // CoreText のフォールバック(PingFang 等)で描かれるため、色を変えて区別する。
    // 1画面100字程度の問い合わせなので事前計算もデータ側の印も持たない(2443)。
    static func hasMinchoGlyph(for character: String, fontName: String = "HiraMinProN-W3") -> Bool {
        guard !character.isEmpty else {
            return false
        }
        let font = CTFontCreateWithName(fontName as CFString, 16, nil)
        var chars = Array(character.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: chars.count)
        guard CTFontGetGlyphsForCharacters(font, &chars, &glyphs, chars.count) else {
            return false
        }
        return glyphs.allSatisfy { $0 != 0 }
    }
}
