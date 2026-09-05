import Foundation
import UIKit

// メモリ内訳(census)の静的診断: malloc ゾーン統計・サイズ階級ヒストグラム・生存ブロックの正体推定と、
// 重い診断を許す閾値。すべて static(プロセス単位)で、didReceiveMemoryWarning から呼ばれる。
// KeyboardViewController.swift 本体(2084 行)から純移動(2805 リファクタ)
extension KeyboardViewController {
    // 静的カタログ(顔文字/絵文字)の概算バイト(census v3、2575)。キャッシュ空でも残る
    // ベースライン(mallocUsed 約40MB)の内訳特定用。測定自体が materialize を誘発するが、
    // メモリ警告時にしか呼ばないので通常動作には影響しない。
    static func diagnosticsStaticCatalogBytesSummary() -> String {
        func listBytes(_ list: [String]) -> Int {
            list.reduce(0) { $0 + $1.utf8.count + 32 }
        }
        func dictBytes(_ dict: [String: [String]]) -> Int {
            dict.reduce(0) { $0 + $1.key.utf8.count + 32 + listBytes($1.value) + 16 }
        }
        func kb(_ value: Int) -> String { String(value / 1024) }
        let kaomoji = listBytes(KaomojiCatalog.entries)
            + dictBytes(KaomojiCatalog.importedEntriesByCategory)
            + dictBytes(KaomojiCatalog.importedEntriesByReading)
        let emoji = listBytes(AppleEmojiCatalog.people) + listBytes(AppleEmojiCatalog.nature)
        return "staticKB: kaomoji=\(kb(kaomoji)) emojiPartial=\(kb(emoji))"
    }

    // 全 malloc ゾーンの used/alloc を列挙する(census v2、2570)。
    // malloc_zone_statistics(nil) はデフォルトゾーンのみで、Nano ゾーン(≤256Bの小粒)が
    // 見えないため、スラックの居場所(小粒か中粒か)を特定できるようにする。
    static func diagnosticsAllMallocZonesSummary() -> String {
        var zoneAddresses: UnsafeMutablePointer<vm_address_t>?
        var zoneCount: UInt32 = 0
        guard malloc_get_all_zones(mach_task_self_, nil, &zoneAddresses, &zoneCount) == KERN_SUCCESS,
            let zoneAddresses else {
            return "zones=?"
        }
        var parts: [String] = []
        for index in 0..<Int(zoneCount) {
            guard let rawZone = UnsafeMutableRawPointer(bitPattern: UInt(zoneAddresses[index])) else {
                continue
            }
            let zone = rawZone.assumingMemoryBound(to: malloc_zone_t.self)
            let name = malloc_get_zone_name(zone).map { String(cString: $0) } ?? "?"
            var stats = malloc_statistics_t()
            malloc_zone_statistics(zone, &stats)
            let usedMB = Double(stats.size_in_use) / 1_048_576
            let allocMB = Double(stats.size_allocated) / 1_048_576
            parts.append("\(name)=\(String(format: "%.1f", usedMB))/\(String(format: "%.1f", allocMB))")
        }
        return "zones(used/allocMB)[\(parts.joined(separator: " "))]"
    }

    // DefaultMallocZone の生存ブロックをサイズ階級別に数える。alloc と used の差
    // (実測 69MB vs 40MB = 29MB のスラック)がどのサイズ帯で生じているかを見るため。
    // 小さいブロックが大量に散っているなら確保回数そのものを減らす方向、大きいブロックが
    // 残っているなら mmap へ移す方向、と打ち手が変わる(2564)。
    // malloc_zone_enumerate の recorder はプロセス外からも呼べるC関数である必要があるため、
    // 集計先はファイルスコープのグローバルに置く。
    static func diagnosticsMallocSizeHistogram() -> String {
        var zoneAddresses: UnsafeMutablePointer<vm_address_t>?
        var zoneCount: UInt32 = 0
        guard malloc_get_all_zones(mach_task_self_, nil, &zoneAddresses, &zoneCount) == KERN_SUCCESS,
            let zoneAddresses else {
            return "hist=?"
        }
        diagnosticsMallocHistogramBuckets = Array(repeating: 0, count: diagnosticsMallocHistogramBounds.count + 1)
        diagnosticsMallocHistogramBytes = Array(repeating: 0, count: diagnosticsMallocHistogramBounds.count + 1)
        diagnosticsMallocSamples = Array(repeating: [], count: diagnosticsMallocHistogramBounds.count + 1)
        diagnosticsMallocClassCounts = Array(
            // malloc ゾーンを列挙している最中に辞書が拡張すると、ロックを保持したまま
            // 確保することになりデッドロックしうる。実在クラス数を十分上回る容量を
            // 先に確保して、列挙中は絶対に拡張させない。
            repeating: [UInt: Int](minimumCapacity: 4096),
            count: diagnosticsMallocHistogramBounds.count + 1
        )
        // 名前の表はここで作っておく(列挙中に初めて触ると、ゾーンを列挙しながら
        // objc_copyClassList を呼ぶことになる)。
        _ = diagnosticsClassNamesByPointer
        for index in 0..<Int(zoneCount) {
            guard let rawZone = UnsafeMutableRawPointer(bitPattern: UInt(zoneAddresses[index])) else {
                continue
            }
            let zone = rawZone.assumingMemoryBound(to: malloc_zone_t.self)
            let name = malloc_get_zone_name(zone).map { String(cString: $0) } ?? ""
            guard name == "DefaultMallocZone" else {
                continue
            }
            guard let introspect = zone.pointee.introspect,
                let enumerator = introspect.pointee.enumerator else {
                continue
            }
            _ = enumerator(
                mach_task_self_,
                nil,
                UInt32(MALLOC_PTR_IN_USE_RANGE_TYPE),
                vm_address_t(UInt(bitPattern: rawZone)),
                nil
            ) { _, _, _, ranges, count in
                guard let ranges else { return }
                for index in 0..<Int(count) {
                    let size = Int(ranges[index].size)
                    var bucket = KeyboardViewController.diagnosticsMallocHistogramBounds.count
                    for (boundIndex, bound) in KeyboardViewController.diagnosticsMallocHistogramBounds.enumerated()
                    where size <= bound {
                        bucket = boundIndex
                        break
                    }
                    KeyboardViewController.diagnosticsMallocHistogramBuckets[bucket] += 1
                    KeyboardViewController.diagnosticsMallocHistogramBytes[bucket] += size
                    // 階級ごとに先頭数ブロックだけ中身を覗いて正体の手がかりにする。
                    // Swift の String/Array の内部確保には印を埋め込めないので、代わりに
                    // 実データを読んで「日本語文字列か/ポインタ列か」を判別する(2564)
                    KeyboardViewController.recordMallocSampleIfNeeded(
                        bucket: bucket,
                        address: UInt(ranges[index].address),
                        size: size
                    )
                    KeyboardViewController.recordMallocClassIfNeeded(
                        bucket: bucket,
                        address: UInt(ranges[index].address),
                        size: size
                    )
                }
            }
        }
        var parts: [String] = []
        for (index, count) in diagnosticsMallocHistogramBuckets.enumerated() where count > 0 {
            let label = index < diagnosticsMallocHistogramBounds.count
                ? "≤\(diagnosticsMallocHistogramBounds[index])"
                : ">\(diagnosticsMallocHistogramBounds.last ?? 0)"
            let mb = Double(diagnosticsMallocHistogramBytes[index]) / 1_048_576
            let samples = index < diagnosticsMallocSamples.count && !diagnosticsMallocSamples[index].isEmpty
                ? "{" + diagnosticsMallocSamples[index].joined(separator: ",") + "}"
                : ""
            // クラス別の上位3種を件数付きで添える。ここで初めて名前を解決する。
            var classes = ""
            if index < diagnosticsMallocClassCounts.count, !diagnosticsMallocClassCounts[index].isEmpty {
                let top = diagnosticsMallocClassCounts[index]
                    .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                    .prefix(3)
                    .map { "\(diagnosticsClassNamesByPointer[$0.key] ?? "?")×\($0.value)" }
                classes = "<" + top.joined(separator: ",") + ">"
            }
            parts.append("\(label):\(count)/\(String(format: "%.1f", mb))MB\(samples)\(classes)")
        }
        return "hist(count/MB)[\(parts.joined(separator: " "))]"
    }

    static let diagnosticsMallocHistogramBounds = [64, 256, 1024, 4096, 16384, 65536, 262_144, 1_048_576]
    static var diagnosticsMallocHistogramBuckets: [Int] = []
    static var diagnosticsMallocHistogramBytes: [Int] = []
    // 階級ごとに保持する中身サンプル。1階級あたり数件で足りる(傾向が分かればよい)
    static var diagnosticsMallocSamples: [[String]] = []
    static let diagnosticsMallocSamplesPerBucket = 3
    // 階級ごとの「Objective-C クラス別の件数」。3件のサンプルでは 16万件の正体が分からず、
    // 4.8万件の増分が何なのか特定できなかった(2602)。全ブロックを数えて名前で出す。
    // 値はクラスポインタ→件数。名前の解決(String 生成)は列挙が終わってから行う —
    // malloc ゾーンを列挙中のコールバック内で余計な確保をしないため。
    static var diagnosticsMallocClassCounts: [[UInt: Int]] = []
    // メモリ内訳の採取間隔。連続警告のたびに全ブロックを列挙すると main を塞ぐ。
    static var lastMemoryCensusAt: CFAbsoluteTime = 0
    static let memoryCensusMinimumInterval: CFAbsoluteTime = 10
    // 重い診断(census2〜4)を許す footprint の上限(2654)。per-process 上限 77MB に対し
    // 22MB の余裕を残す。8/25 の死2件は警告時 fp59.6 → census2 計算中に 77MB 到達。
    static let memoryHeavyCensusMaxFootprintMB: Double = 55
    // 測定(2721): census2〜4 は 2667 で全ブロック列挙を撤去済み(統計読みと自前構造の概算だけ)なので、
    // 55MB 超でもプロセスにつき1回だけ 70MB 未満なら採る。警告が来るのは常に fp≈60 で、
    // 55 の門番のままでは高水位の中身が一度も記録されなかった
    static let memoryHeavyCensusOnceMaxFootprintMB: Double = 70
    static var didRunHeavyCensusAbovePressureThreshold = false
    static func allowsHeavyCensus(footprintMB: Double) -> Bool {
        if footprintMB < memoryHeavyCensusMaxFootprintMB { return true }
        if !didRunHeavyCensusAbovePressureThreshold, footprintMB < memoryHeavyCensusOnceMaxFootprintMB {
            didRunHeavyCensusAbovePressureThreshold = true
            return true
        }
        return false
    }
    // 非表示個体を強制解放しはじめる警告回数(2658、ユーザ指定の段階制)。
    // 予防スリム化(常時)で足りないときの次の手
    static let aggressiveInactiveReleaseWarningCount = 3
    // 登録済み Objective-C クラスの「ポインタ→名前」。任意のメモリの先頭ワードを
    // class_getName に渡すのは危険(オブジェクトでなければクラッシュする)なので、
    // この表に在るポインタだけ名前を引く。Swift のクラスも Apple 環境では登録される。
    static let diagnosticsClassNamesByPointer: [UInt: String] = {
        let declared = objc_getClassList(nil, 0)
        guard declared > 0 else { return [:] }
        // AnyClass 経由の要素アクセス(objc_copyClassList の list[i])は swift_dynamicCast を
        // 挟み、NSObject 系メソッドを実装しない内部クラス(__NSGenericDeallocHandler 等)で
        // forwarding abort する(2611でテスト実測)。生ポインタのまま受け取り、
        // 名前取得はメッセージ送信しない class_getName(メタデータ直読み)だけに留める。
        var raw = [UnsafeRawPointer?](repeating: nil, count: Int(declared))
        let filled = raw.withUnsafeMutableBufferPointer { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return 0 }
            return base.withMemoryRebound(to: AnyClass.self, capacity: buffer.count) { rebound in
                objc_getClassList(AutoreleasingUnsafeMutablePointer(rebound), declared)
            }
        }
        var names = [UInt: String](minimumCapacity: Int(filled))
        for index in 0..<Int(min(filled, declared)) {
            guard let pointer = raw[index] else { continue }
            names[UInt(bitPattern: pointer)] = String(cString: class_getName(unsafeBitCast(pointer, to: AnyClass.self)))
        }
        return names
    }()

    // ブロックの先頭を読んで正体の手がかりを作る。UTF-8 として読めれば文字列データ、
    // 上位バイトがポインタらしければ参照の配列、と当たりを付ける。入力内容が混じりうるので
    // 開発ビルド限定(診断ログ自体が #if !DEBUG で無効)。
    static func recordMallocSampleIfNeeded(bucket: Int, address: UInt, size: Int) {
        #if !DEBUG
        return
        #else
        guard bucket < diagnosticsMallocSamples.count,
            diagnosticsMallocSamples[bucket].count < diagnosticsMallocSamplesPerBucket,
            size >= 16,
            let base = UnsafeRawPointer(bitPattern: address) else {
            return
        }
        let peekCount = min(size, 48)
        let bytes = UnsafeRawBufferPointer(start: base, count: peekCount)
        // Swift のヒープオブジェクトは先頭にメタデータポインタを持つ。0x0000_0001_.... 帯なら
        // クラスインスタンス/バッファ、それ以外は生データの可能性が高い
        let head = bytes.loadUnaligned(fromByteOffset: 0, as: UInt64.self)
        let looksLikePointer = head > 0x1_0000 && head < 0x0002_0000_0000_0000
        // 文字列らしさ: 可読 UTF-8(日本語含む)がある程度続くか
        let tail = Array(bytes.dropFirst(8).prefix(32))
        let text = String(decoding: tail.prefix(while: { $0 != 0 }), as: UTF8.self)
        let printable = text.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7F }.count
        let kind: String
        if printable >= 4 && printable * 2 >= text.unicodeScalars.count {
            kind = "text:\(text.prefix(12))"
        } else if looksLikePointer {
            kind = "obj"
        } else {
            kind = "raw"
        }
        diagnosticsMallocSamples[bucket].append(kind)
        #endif
    }

    // 階級ごとに Objective-C クラス別の件数を数える(2602)。3件のサンプルでは
    // 16万件の内訳が分からなかったため、全ブロックの先頭ワードを見て集計する。
    // 安全のため、登録済みクラスの表に在るポインタだけを対象にする(任意のメモリを
    // class_getName に渡すとクラッシュしうる)。名前の解決は列挙後に行う —
    // malloc ゾーンの列挙中に String を作らないため、ここではポインタのまま数える。
    static func recordMallocClassIfNeeded(bucket: Int, address: UInt, size: Int) {
        #if !DEBUG
        return
        #else
        guard bucket < diagnosticsMallocClassCounts.count,
            size >= 16,
            let base = UnsafeRawPointer(bitPattern: address) else {
            return
        }
        let head = UInt(UnsafeRawBufferPointer(start: base, count: 8).loadUnaligned(as: UInt64.self))
        // Swift/ObjC のインスタンスは先頭に isa(クラスポインタ)を持つ。下位ビットに
        // タグが載る実装があるので素の値で引けなければ諦める(推測で剥がさない)。
        guard diagnosticsClassNamesByPointer[head] != nil else {
            return
        }
        diagnosticsMallocClassCounts[bucket][head, default: 0] += 1
        #endif
    }
}
