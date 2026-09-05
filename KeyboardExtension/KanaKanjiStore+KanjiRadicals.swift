import CoreText
import Foundation

// 漢字1文字ピッカーの索引。KanjiRadicalIndex.txt(部首番号→総画数→部首内画数→コードポイント順に
// バイト順ソート済み。1行 = "NNN\tSS\t字\t区点\t読み\tTT"、TT=総画数)を Data(mappedIfSafe) のまま保持し、
// 行頭 "NNN\t" のバイナリサーチで部首ブロックだけを切り出す。欧文語彙
// (GenericLatinLexiconFileIndex)と同じ方式で、常駐フットプリントを持たない。
struct KanjiRadicalFileIndex {
    struct Entry {
        let character: String
        let residualStrokes: Int
        let kuten: String
        let readings: String
        // 総画数(Unihan kTotalStrokes)。字グリッドの画数区切りに使う。0 は不明(区切りを出さない)
        let totalStrokes: Int
    }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    var isEmpty: Bool { data.isEmpty }

    // 部首番号(1〜214)に属する字を、ファイル順(総画数→部首内画数→コードポイント)で返す。
    func entries(radical: Int) -> [Entry] {
        guard 1...214 ~= radical, !data.isEmpty else {
            return []
        }
        let key = Array(String(format: "%03d\t", radical).utf8)
        var results: [Entry] = []
        // キーはタブ込みの完全一致なので keyEndsAtTab=false(SortedTSVBlob の定義コメント参照)
        SortedTSVBlob.forEachLine(in: data, withKeyPrefix: key, keyEndsAtTab: false) { bytes, cursor, lineEnd in
            // フィールド分解: radical \t strokes \t 字 \t 区点 \t 読み \t 総画数
            var fieldStarts: [Int] = [cursor]
            var scan = cursor
            while scan < lineEnd {
                if bytes[scan] == 0x09 {
                    fieldStarts.append(scan + 1)
                }
                scan += 1
            }
            guard fieldStarts.count >= 5 else {
                return
            }
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
                        readings: field(4),
                        totalStrokes: fieldStarts.count >= 6 ? (Int(field(5)) ?? 0) : 0
                    )
                )
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
