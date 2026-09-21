import Foundation
import UIKit

// メモリ内訳(census)の静的診断: malloc ゾーン統計と重い診断を許す閾値。サイズ階級ヒストグラム・生存ブロックの
// 正体推定(2564/2602 の調査用)は用済みで撤去(2822)。すべて static(プロセス単位)で、didReceiveMemoryWarning から呼ばれる。
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
}
