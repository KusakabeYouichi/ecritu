import Foundation

// キーのバイト順にソート済みの TSV(1 行 = 1 エントリ、先頭フィールドがキー)を、mmap した Data のまま
// 二分探索して「キーが prefix で始まる行」を先頭から順に列挙する。ロードも検索もヒープを使わない。
// 部首索引(KanjiRadicalIndex.txt)と欧文サジェスト索引(LatinSuggestion*.txt)で同じ手続きを 2 重に
// 持っていたのを集約した(2805)。
//
// keyEndsAtTab: キー比較で 0x09(タブ)をキーの終端とみなすか。欧文索引は prefix がキーの途中で
// 尽きる前方一致なので true。部首索引は prefix("NNN\t")にタブ自体を含めて完全一致させるので false
// (true にすると "001\t" の行を「キーが短い=小さい」と誤判定して下限探索が行を跨ぐ)。
enum SortedTSVBlob {
    // 行頭 cursor と行末 lineEnd(改行位置、または n)を受け取る。false を返すと列挙を打ち切る
    typealias LineVisitor = (_ bytes: UnsafeBufferPointer<UInt8>, _ cursor: Int, _ lineEnd: Int) -> Void

    static func forEachLine(
        in data: Data,
        withKeyPrefix prefix: [UInt8],
        keyEndsAtTab: Bool,
        _ visit: LineVisitor
    ) {
        guard !prefix.isEmpty, !data.isEmpty else {
            return
        }
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            let bytes = buffer.bindMemory(to: UInt8.self)
            let n = bytes.count

            // offset を含む行の先頭(直前の改行の次)
            func lineStart(atOrBefore offset: Int) -> Int {
                var i = offset
                while i > 0, bytes[i - 1] != 0x0A {
                    i -= 1
                }
                return i
            }
            // 行頭 start のキーと prefix のバイト辞書式比較: キーが小さければ true
            func keyIsLess(lineStart start: Int) -> Bool {
                var i = start
                var j = 0
                while j < prefix.count {
                    if i >= n || bytes[i] == 0x0A || (keyEndsAtTab && bytes[i] == 0x09) {
                        return true  // キーが prefix より短い(=prefix の途中で尽きた)
                    }
                    if bytes[i] != prefix[j] {
                        return bytes[i] < prefix[j]
                    }
                    i += 1
                    j += 1
                }
                return false  // キー >= prefix(prefix を含む)
            }

            // 下限探索: キー >= prefix となる最初の行頭
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

            // 前方一致する行を順に列挙
            var cursor = low
            while cursor < n {
                var i = cursor
                var isPrefix = true
                for byte in prefix {
                    if i >= n || bytes[i] != byte {
                        isPrefix = false
                        break
                    }
                    i += 1
                }
                guard isPrefix else {
                    break
                }
                var lineEnd = cursor
                while lineEnd < n, bytes[lineEnd] != 0x0A {
                    lineEnd += 1
                }
                visit(bytes, cursor, lineEnd)
                cursor = lineEnd + 1
            }
        }
    }
}
