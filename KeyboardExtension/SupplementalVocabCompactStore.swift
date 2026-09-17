import Foundation

// 補助語彙(SecondVocab: vin/it/ryukyu/personnalites/drapeaux/monnaies/astronomique)の常駐用コンパクト表。
// [String: [String]] だと Swift 辞書+String ヒープのオーバーヘッドで約6.8MB常駐する
// (15,901読み。初回変換の used +6.8MB の主因 — 高水位台帳 2615 で実測)。
// 消費点は「読み単位の点引き」(候補マージ/昇格判定/カタカナ化抑止免除)と
// 「一度きりの全走査」(欧文サジェスト索引の構築)だけなので、全文字列を1本の UTF8 ブロブに
// 詰め、読みはバイト列ソート+二分探索で引く。
//
// 3031: 内部表現を「配列 4 本」から「直列化形式(ECCS1)そのものを 1 本の Data として参照」に
// 変えた。ビルド時に畳んだ ÉcrituSecondVocab.eccs を mmap で開けば、ブロブもオフセット表も
// heap に一切乗らない(配列版は復元時に約 1.5MB を確保し、malloc アリーナを 4MB 広げていた。
// 実機の区間計測 3030)。連絡先キャッシュ(復号した Data)も同じ型で持つ。
//
// 形式: "ECCS1" + 読みオフセット数・表層リスト開始数・表層オフセット数・blob 長(各 UInt32 LE)
//       + 読みオフセット表 + 表層リスト開始表 + 表層オフセット表(各 UInt32 LE)+ blob
//   読み i のバイト範囲   = blob[readingOffsets[i] ..< 次に始まるもの](読みはバイト列昇順)
//   読み i の表層スロット = surfaceListStarts[i] ..< surfaceListStarts[i+1]
//   表層スロット j       = blob[surfaceOffsets[j] ..< 次に始まるもの]
//   blob の配置は [読みi][表層i0][表層i1]…[読みi+1][表層(i+1)0]… の交互
struct SupplementalVocabCompactStore: Equatable {
    // 直列化形式そのもの。ファイル由来なら mmap(Data(contentsOf:options:.mappedIfSafe))、
    // 辞書から畳んだ/復号した場合は in-memory。等値はバイト列の一致で見る
    private let buffer: Data
    // ヘッダーから読んだ寸法(バイト位置は buffer 先頭からの相対)
    private let readingOffsetCount: Int
    private let surfaceListStartCount: Int
    private let surfaceOffsetCount: Int
    private let blobCount: Int
    private let readingOffsetsPosition: Int
    private let surfaceListStartsPosition: Int
    private let surfaceOffsetsPosition: Int
    private let blobPosition: Int

    private static let serializationMagic: [UInt8] = Array("ECCS1".utf8)
    private static var headerLength: Int { serializationMagic.count + 16 }

    static let empty = SupplementalVocabCompactStore(dictionary: [:])

    var readingCount: Int { max(0, readingOffsetCount - 1) }
    var isEmpty: Bool { readingCount == 0 }
    // 表の実サイズ(mmap 由来なら heap には乗っていない)
    var estimatedBytes: Int { buffer.count }

    static func == (lhs: SupplementalVocabCompactStore, rhs: SupplementalVocabCompactStore) -> Bool {
        lhs.buffer == rhs.buffer
    }

    init(dictionary: [String: [String]]) {
        let sortedReadings = dictionary.keys.sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
        var blob: [UInt8] = []
        var readingOffsets: [UInt32] = []
        var surfaceListStarts: [UInt32] = []
        var surfaceOffsets: [UInt32] = []
        blob.reserveCapacity(dictionary.count * 24)
        readingOffsets.reserveCapacity(sortedReadings.count + 1)
        surfaceListStarts.reserveCapacity(sortedReadings.count + 1)
        for reading in sortedReadings {
            readingOffsets.append(UInt32(blob.count))
            blob.append(contentsOf: reading.utf8)
            surfaceListStarts.append(UInt32(surfaceOffsets.count))
            for surface in dictionary[reading] ?? [] {
                surfaceOffsets.append(UInt32(blob.count))
                blob.append(contentsOf: surface.utf8)
            }
        }
        readingOffsets.append(UInt32(blob.count))
        surfaceListStarts.append(UInt32(surfaceOffsets.count))

        var bytes: [UInt8] = []
        bytes.reserveCapacity(
            Self.headerLength
                + (readingOffsets.count + surfaceListStarts.count + surfaceOffsets.count) * 4
                + blob.count
        )
        bytes.append(contentsOf: Self.serializationMagic)
        func appendUInt32(_ value: Int) {
            withUnsafeBytes(of: UInt32(value).littleEndian) { bytes.append(contentsOf: $0) }
        }
        appendUInt32(readingOffsets.count)
        appendUInt32(surfaceListStarts.count)
        appendUInt32(surfaceOffsets.count)
        appendUInt32(blob.count)
        for array in [readingOffsets, surfaceListStarts, surfaceOffsets] {
            for value in array {
                withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) }
            }
        }
        bytes.append(contentsOf: blob)
        // 自分で組んだ形式なので必ず通る
        self.init(serialized: Data(bytes))!
    }

    // 直列化形式そのもの(mmap 由来ならコピーせずそのまま返す)
    func serializedData() -> Data {
        buffer
    }

    // 検証してそのまま保持する(コピーしない)。壊れた入力・別形式は nil
    init?(serialized data: Data) {
        let magic = Self.serializationMagic
        let headerLength = Self.headerLength
        guard data.count >= headerLength else {
            return nil
        }
        let header: (Bool, Int, Int, Int, Int) = data.withUnsafeBytes { raw in
            for index in 0..<magic.count where raw[index] != magic[index] {
                return (false, 0, 0, 0, 0)
            }
            func readUInt32(_ position: Int) -> Int {
                Int(UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: position, as: UInt32.self)))
            }
            return (
                true,
                readUInt32(magic.count),
                readUInt32(magic.count + 4),
                readUInt32(magic.count + 8),
                readUInt32(magic.count + 12)
            )
        }
        guard header.0 else {
            return nil
        }
        let readingOffsetCount = header.1
        let surfaceListStartCount = header.2
        let surfaceOffsetCount = header.3
        let blobCount = header.4
        let expected = headerLength + (readingOffsetCount + surfaceListStartCount + surfaceOffsetCount) * 4 + blobCount
        guard data.count == expected,
            readingOffsetCount == surfaceListStartCount else {
            return nil
        }
        self.buffer = data
        self.readingOffsetCount = readingOffsetCount
        self.surfaceListStartCount = surfaceListStartCount
        self.surfaceOffsetCount = surfaceOffsetCount
        self.blobCount = blobCount
        self.readingOffsetsPosition = headerLength
        self.surfaceListStartsPosition = readingOffsetsPosition + readingOffsetCount * 4
        self.surfaceOffsetsPosition = surfaceListStartsPosition + surfaceListStartCount * 4
        self.blobPosition = surfaceOffsetsPosition + surfaceOffsetCount * 4
    }

    // ── 以下、buffer 上の生バイトを直接読む。点引き 1 回を 1 つの withUnsafeBytes に収め、
    //    Data の橋渡しコストを二分探索の回数ぶん払わないようにする

    private struct Cursor {
        let raw: UnsafeRawBufferPointer
        let store: SupplementalVocabCompactStore

        func readingOffset(_ index: Int) -> Int {
            uint32(at: store.readingOffsetsPosition + index * 4)
        }
        func surfaceListStart(_ index: Int) -> Int {
            uint32(at: store.surfaceListStartsPosition + index * 4)
        }
        func surfaceOffset(_ slot: Int) -> Int {
            uint32(at: store.surfaceOffsetsPosition + slot * 4)
        }
        private func uint32(at position: Int) -> Int {
            Int(UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: position, as: UInt32.self)))
        }

        // 読み index のバイト範囲(blob 内)。読みの直後にその表層列が続くため、終端は
        // 「最初の表層の開始」(表層が無ければ次の読みの開始)
        func readingBytes(_ index: Int) -> UnsafeRawBufferPointer {
            let start = readingOffset(index)
            let firstSlot = surfaceListStart(index)
            let lastSlotExclusive = surfaceListStart(index + 1)
            let end = firstSlot < lastSlotExclusive ? surfaceOffset(firstSlot) : readingOffset(index + 1)
            return blobSlice(start, end)
        }

        func surfaceBytes(slot: Int, ownerReadingIndex: Int) -> UnsafeRawBufferPointer {
            let start = surfaceOffset(slot)
            let lastSlotOfOwner = surfaceListStart(ownerReadingIndex + 1) - 1
            let end = slot < lastSlotOfOwner ? surfaceOffset(slot + 1) : readingOffset(ownerReadingIndex + 1)
            return blobSlice(start, end)
        }

        private func blobSlice(_ start: Int, _ end: Int) -> UnsafeRawBufferPointer {
            let base = store.blobPosition
            return UnsafeRawBufferPointer(rebasing: raw[(base + start)..<(base + end)])
        }

        func indexOfReading(_ target: [UInt8]) -> Int? {
            var low = 0
            var high = store.readingCount - 1
            while low <= high {
                let mid = (low + high) / 2
                let bytes = readingBytes(mid)
                if bytes.elementsEqual(target) {
                    return mid
                }
                if bytes.lexicographicallyPrecedes(target) {
                    low = mid + 1
                } else {
                    high = mid - 1
                }
            }
            return nil
        }
    }

    private func withCursor<T>(_ body: (Cursor) -> T) -> T {
        buffer.withUnsafeBytes { raw in
            body(Cursor(raw: raw, store: self))
        }
    }

    func candidates(for reading: String) -> [String] {
        let target = Array(reading.utf8)
        return withCursor { cursor in
            guard let index = cursor.indexOfReading(target) else {
                return []
            }
            var result: [String] = []
            for slot in cursor.surfaceListStart(index)..<cursor.surfaceListStart(index + 1) {
                result.append(String(decoding: cursor.surfaceBytes(slot: slot, ownerReadingIndex: index), as: UTF8.self))
            }
            return result
        }
    }

    func contains(reading: String, surface: String) -> Bool {
        let readingTarget = Array(reading.utf8)
        let surfaceTarget = Array(surface.utf8)
        return withCursor { cursor in
            guard let index = cursor.indexOfReading(readingTarget) else {
                return false
            }
            for slot in cursor.surfaceListStart(index)..<cursor.surfaceListStart(index + 1)
            where cursor.surfaceBytes(slot: slot, ownerReadingIndex: index).elementsEqual(surfaceTarget) {
                return true
            }
            return false
        }
    }
}
