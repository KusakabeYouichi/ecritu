import Foundation

// 補助語彙(SecondVocab: vin/it/ryukyu/personnalites/drapeaux/monnaies/astronomique)の常駐用コンパクト表。
// [String: [String]] だと Swift 辞書+String ヒープのオーバーヘッドで約6.8MB常駐する
// (15,901読み。初回変換の used +6.8MB の主因 — 高水位台帳 2615 で実測)。
// 消費点は「読み単位の点引き」(候補マージ/昇格判定/カタカナ化抑止免除)と
// 「一度きりの全走査」(欧文サジェスト索引の構築)だけなので、全文字列を1本の UTF8 ブロブに
// 詰め、読みはバイト列ソート+二分探索で引く。実測で常駐 約1MB 弱まで下がる。
struct SupplementalVocabCompactStore: Equatable {
    // 全読み・全表層の UTF8 を連結したブロブ。個々の文字列はオフセット表で参照する。
    private let blob: [UInt8]
    // 読み i のバイト範囲 = blob[readingOffsets[i]..<readingOffsets[i+1]](読みはバイト列昇順)
    private let readingOffsets: [UInt32]
    // 読み i の表層は表層スロット surfaceListStarts[i]..<surfaceListStarts[i+1]
    private let surfaceListStarts: [UInt32]
    // 表層スロット j のバイト範囲 = blob[surfaceOffsets[j]..<surfaceOffsets[j+1]]
    private let surfaceOffsets: [UInt32]

    static let empty = SupplementalVocabCompactStore(dictionary: [:])

    var readingCount: Int { max(0, readingOffsets.count - 1) }
    var isEmpty: Bool { readingCount == 0 }
    var estimatedBytes: Int {
        blob.count + (readingOffsets.count + surfaceListStarts.count + surfaceOffsets.count) * 4
    }

    init(dictionary: [String: [String]]) {
        let sortedReadings = dictionary.keys.sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
        var blob: [UInt8] = []
        var readingOffsets: [UInt32] = []
        var surfaceListStarts: [UInt32] = []
        blob.reserveCapacity(dictionary.count * 24)
        readingOffsets.reserveCapacity(sortedReadings.count + 1)
        surfaceListStarts.reserveCapacity(sortedReadings.count + 1)
        // 表層の総数は不明なので append 主体で構築(初回ロード時の一度きり)
        var surfaceCursorOffsets: [UInt32] = []
        for reading in sortedReadings {
            readingOffsets.append(UInt32(blob.count))
            blob.append(contentsOf: reading.utf8)
            surfaceListStarts.append(UInt32(surfaceCursorOffsets.count))
            for surface in dictionary[reading] ?? [] {
                surfaceCursorOffsets.append(UInt32(blob.count))
                blob.append(contentsOf: surface.utf8)
            }
        }
        readingOffsets.append(UInt32(blob.count))
        surfaceListStarts.append(UInt32(surfaceCursorOffsets.count))
        // blob の配置は [読みi][表層i0][表層i1]…[読みi+1][表層(i+1)0]… の交互。
        // 各要素の終端は「次に始まるものの開始」で求まる(readingBytes/surfaceBytes 参照)。
        self.surfaceOffsets = surfaceCursorOffsets
        self.blob = blob
        self.readingOffsets = readingOffsets
        self.surfaceListStarts = surfaceListStarts
    }

    // 畳んだ状態のまま保存・受け渡しするための直列化(3020)。連絡先キャッシュは
    // 「封緘 JSON → [String: [String]](4,126 読み)→ コンパクト化」という順で復元しており、
    // 途中の辞書が一瞬で消えるのに malloc アリーナを 4MB 広げて戻さなかった(実機計測)。
    // コンテナー側で畳んでからこの形式で渡せば、拡張側は配列 4 本を作るだけで済む。
    // 形式: "ECCS1" + 各配列の要素数(UInt32 LE)×3 + blob 長 + 各配列 + blob
    private static let serializationMagic: [UInt8] = Array("ECCS1".utf8)

    func serializedData() -> Data {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(
            Self.serializationMagic.count + 16
                + (readingOffsets.count + surfaceListStarts.count + surfaceOffsets.count) * 4
                + blob.count
        )
        bytes.append(contentsOf: Self.serializationMagic)
        func appendUInt32(_ value: Int) {
            let raw = UInt32(value).littleEndian
            withUnsafeBytes(of: raw) { bytes.append(contentsOf: $0) }
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
        return Data(bytes)
    }

    init?(serialized data: Data) {
        let magic = Self.serializationMagic
        let headerLength = magic.count + 16
        guard data.count >= headerLength else {
            return nil
        }
        let bytes = [UInt8](data)
        guard Array(bytes[0..<magic.count]) == magic else {
            return nil
        }
        func readUInt32(at offset: Int) -> Int {
            var value: UInt32 = 0
            withUnsafeMutableBytes(of: &value) { destination in
                for index in 0..<4 {
                    destination[index] = bytes[offset + index]
                }
            }
            return Int(UInt32(littleEndian: value))
        }
        let readingCount = readUInt32(at: magic.count)
        let listStartCount = readUInt32(at: magic.count + 4)
        let surfaceCount = readUInt32(at: magic.count + 8)
        let blobCount = readUInt32(at: magic.count + 12)
        let expected = headerLength + (readingCount + listStartCount + surfaceCount) * 4 + blobCount
        guard data.count == expected else {
            return nil
        }
        var cursor = headerLength
        func readArray(_ count: Int) -> [UInt32] {
            var array: [UInt32] = []
            array.reserveCapacity(count)
            for _ in 0..<count {
                array.append(UInt32(readUInt32(at: cursor)))
                cursor += 4
            }
            return array
        }
        self.readingOffsets = readArray(readingCount)
        self.surfaceListStarts = readArray(listStartCount)
        self.surfaceOffsets = readArray(surfaceCount)
        self.blob = Array(bytes[cursor..<(cursor + blobCount)])
    }

    private func readingBytes(_ index: Int) -> ArraySlice<UInt8> {
        // 読み index のバイト範囲。読みの直後にその表層列が続くため、終端は
        // 「最初の表層の開始」(表層が無ければ次の読みの開始)。
        let start = Int(readingOffsets[index])
        let firstSurfaceSlot = Int(surfaceListStarts[index])
        let lastSurfaceSlotExclusive = Int(surfaceListStarts[index + 1])
        let end: Int
        if firstSurfaceSlot < lastSurfaceSlotExclusive {
            end = Int(surfaceOffsets[firstSurfaceSlot])
        } else {
            end = Int(readingOffsets[index + 1])
        }
        return blob[start..<end]
    }

    private func surfaceBytes(slot: Int, ownerReadingIndex: Int) -> ArraySlice<UInt8> {
        let start = Int(surfaceOffsets[slot])
        let lastSlotOfOwner = Int(surfaceListStarts[ownerReadingIndex + 1]) - 1
        let end = slot < lastSlotOfOwner
            ? Int(surfaceOffsets[slot + 1])
            : Int(readingOffsets[ownerReadingIndex + 1])
        return blob[start..<end]
    }

    private func indexOfReading(_ reading: String) -> Int? {
        let target = Array(reading.utf8)
        var low = 0
        var high = readingCount - 1
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

    func candidates(for reading: String) -> [String] {
        guard let index = indexOfReading(reading) else {
            return []
        }
        var result: [String] = []
        for slot in Int(surfaceListStarts[index])..<Int(surfaceListStarts[index + 1]) {
            result.append(String(decoding: surfaceBytes(slot: slot, ownerReadingIndex: index), as: UTF8.self))
        }
        return result
    }

    func contains(reading: String, surface: String) -> Bool {
        guard let index = indexOfReading(reading) else {
            return false
        }
        let target = Array(surface.utf8)
        for slot in Int(surfaceListStarts[index])..<Int(surfaceListStarts[index + 1])
        where surfaceBytes(slot: slot, ownerReadingIndex: index).elementsEqual(target) {
            return true
        }
        return false
    }
}
