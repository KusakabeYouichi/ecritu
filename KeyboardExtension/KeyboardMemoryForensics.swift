import Darwin
import Foundation
import SQLite3

// ============================================================================
// ★時限デバッグ装置(2611)— メモリ切迫の根本原因調査用の計測パッケージ。
//
// 原因解明・対策完了後は綺麗に剥がすこと:
//   1. `grep -rn "MEMFORENSICS" KeyboardExtension Tests` で呼び出し点を列挙して削除
//      (viewDidLoad の sink 設定 / 変換完了 note / 絵文字切替 note / census4)
//   2. 本ファイルと Tests/MemoryForensicsTests.swift を削除
//   3. pbxproj から両ファイルの登録を削除
// 本体コードへの依存はゼロ(このファイルは他から参照されるだけ)。
//
// 計測の狙い(playbook 既知原因5=malloc アリーナ保持、の帰属を取る):
//   A. 高水位台帳 noteOperation — 「どの操作が alloc 高水位を育てたか」の帰属
//   C. sqlite 自己申告      — sqlite ヒープと自前ヒープの切り分け
//   D. footprint 内訳       — internal/compressed(dirty がどこに計上されているか)
//   解剖 heapAnatomy        — ページ占有×dirty で「free済みdirtyの居場所」と
//                             「何バイトの生き残りが16KBページを釘付けにしているか」を定量化
// ============================================================================
enum MemoryForensics {
    // 台帳イベントの出力先(診断ログへ)。viewDidLoad で1回だけ設定される。
    // 変換キュー等の非 main からも呼ばれるため、設定側で main へディスパッチすること。
    nonisolated(unsafe) static var logSink: ((String) -> Void)?

    // ──────────────────────────────────────────────
    // A. 高水位台帳
    // ──────────────────────────────────────────────
    private static let ledgerLock = NSLock()
    nonisolated(unsafe) private static var allocHighWaterBytes = 0
    nonisolated(unsafe) private static var ledgerEventCount = 0

    /// 操作の終端で呼ぶ。DefaultMallocZone の alloc(dirty 高水位)が前回記録から
    /// 1MB 以上育っていたら、操作タグ付きで台帳に刻む。コストは数μs(統計読み1回)。
    /// 初回呼び出しはベースラインとして必ず1件出る。
    static func noteOperation(_ tag: @autoclosure () -> String) {
        #if DEBUG
        var stats = malloc_statistics_t()
        malloc_zone_statistics(nil, &stats)
        let alloc = Int(stats.size_allocated)
        ledgerLock.lock()
        let previous = allocHighWaterBytes
        guard alloc - previous >= 1_048_576 else {
            ledgerLock.unlock()
            return
        }
        allocHighWaterBytes = alloc
        ledgerEventCount += 1
        let eventNumber = ledgerEventCount
        ledgerLock.unlock()
        let grewMB = Double(alloc - previous) / 1_048_576
        let line = "MEMFORENSICS高水位#\(eventNumber)"
            + (previous == 0 ? "(ベースライン)" : " +\(String(format: "%.1f", grewMB))MB")
            + " op=\(tag())"
            + " alloc=\(String(format: "%.1f", Double(alloc) / 1_048_576))"
            + " used=\(String(format: "%.1f", Double(stats.size_in_use) / 1_048_576))"
            + " fp=\(String(format: "%.1f", currentPhysFootprintMB() ?? -1))"
        logSink?(line)
        // ★高水位時の自動解剖は停止(2626)。実機で「alloc が初めて48MBに達した高水位
        // イベントの直後に警告→per-process-limit 即死」が4回一致した(17:00/20:17/20:38 他)。
        // 解剖の釘の正体集計が objc_getClassList で全クラスを realize し、①数十MBの
        // メモリスパイク ②Contacts 系クラスの実体化(distnoted の AB 登録=誤認の元)を
        // 起こしていた疑いが濃厚 — 診断自体が死因になっては本末転倒(2603の教訓の再演)。
        // 解剖は summaryLine(軽量)だけ残し、フル解剖は必要時に手動ビルドで行う。
        if previous != 0, alloc >= 48 * 1_048_576 {
            logSink?("MEMFORENSICS概況@高水位#\(eventNumber) \(summaryLine())")
            // vmTags(タグ別のdirty集計)は region 走査のみで安全(数ms・確保ゼロ・
            // クラス表不使用)。凶器だったのは heapAnatomy のクラス表(objc_getClassList=
            // 全クラスrealize)で、そちらは停止のまま。malloc外 internal 約45MB の帰属を
            // 名指しするための本命データ(2629)
            logSink?("MEMFORENSICS帰属@高水位#\(eventNumber) \(vmRegionSummaryByTag())")
        }
        #endif
    }

    // ──────────────────────────────────────────────
    // C+D. sqlite 自己申告 + footprint 内訳(census4 の1行目)
    // ──────────────────────────────────────────────
    static func summaryLine() -> String {
        #if DEBUG
        // C: sqlite が malloc から借りている量(mmap は含まれない=含まれないこと自体が情報)
        let sqliteUsedMB = Double(sqlite3_memory_used()) / 1_048_576
        let sqliteHighMB = Double(sqlite3_memory_highwater(0)) / 1_048_576
        // D: footprint の内訳。internal=アプリ由来 dirty、compressed=圧縮器に居る分。
        // free済みdirtyページは internal に居座り、圧迫が進むと compressed へ移る。
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let kern = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        let vmPart: String
        if kern == KERN_SUCCESS {
            func mb(_ value: UInt64) -> String { String(format: "%.1f", Double(value) / 1_048_576) }
            vmPart = "fp=\(mb(info.phys_footprint))"
                + " internal=\(mb(UInt64(max(0, info.internal))))"
                + " compressed=\(mb(UInt64(max(0, info.compressed))))"
        } else {
            vmPart = "fp=?"
        }
        return "sqliteMB=\(String(format: "%.1f", sqliteUsedMB))"
            + "(hw=\(String(format: "%.1f", sqliteHighMB)))"
            + " \(vmPart)"
        #else
        return "off"
        #endif
    }

    private static func currentPhysFootprintMB() -> Double? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let kern = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        guard kern == KERN_SUCCESS else { return nil }
        return Double(info.phys_footprint) / 1_048_576
    }

    // ──────────────────────────────────────────────
    // ヒープ解剖(census4 の2行目)
    // ──────────────────────────────────────────────
    // 列挙コールバックは C 関数ポインタでコンテキストを持てないため、集計先は
    // static に置く(既存 census2 と同じ流儀)。列挙中は一切確保しない —
    // 全バッファをフェーズ間(コールバック外)で確保する。
    private static let anatomyMaxRegions = 4096
    nonisolated(unsafe) private static var anatomyRegionStarts = [UInt](repeating: 0, count: anatomyMaxRegions)
    nonisolated(unsafe) private static var anatomyRegionEnds = [UInt](repeating: 0, count: anatomyMaxRegions)
    nonisolated(unsafe) private static var anatomyRegionPageBase = [Int](repeating: 0, count: anatomyMaxRegions + 1)
    nonisolated(unsafe) private static var anatomyRegionCount = 0
    nonisolated(unsafe) private static var anatomyRegionOverflow = false
    nonisolated(unsafe) private static var anatomyPageLiveBytes: UnsafeMutablePointer<UInt32>?
    nonisolated(unsafe) private static var anatomyTotalPages = 0
    nonisolated(unsafe) private static var anatomyBlockCount = 0
    nonisolated(unsafe) private static var anatomyLiveBytes = 0
    private static let anatomyPageSize = 16384

    // 釘ページ(dirty かつ生存≤1KB)の住人の正体調べ。ページ特定後にもう一周列挙し、
    // そこに住む生存ブロックを isa(クラス)別/サイズ別に数える。SwiftUI ランタイムの
    // 小ノードが犯人なら SwiftUI 内部クラス群か raw 小ブロックが上位に並ぶはず(仮説検証)。
    nonisolated(unsafe) private static var anatomyPinnedFlags: UnsafeMutablePointer<Bool>?
    nonisolated(unsafe) private static var anatomyPinnedClassCounts = [UInt: Int](minimumCapacity: 4096)
    nonisolated(unsafe) private static var anatomyPinnedRawCountBySize = [Int: Int](minimumCapacity: 64)
    nonisolated(unsafe) private static let anatomyClassNamesByPointer: [UInt: String] = {
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

    // 解剖の間隔ガード(全ブロック列挙+ページクエリで100ms級。連続警告で繰り返さない)
    nonisolated(unsafe) private static var lastAnatomyAt: CFAbsoluteTime = 0
    private static let anatomyMinimumInterval: CFAbsoluteTime = 60

    /// DefaultMallocZone の全リージョンをページ単位で解剖する。
    /// 出力: dirty ページの内訳 [生存0(返却可能な屑) / 生存≤1KB(釘付け) / 使用中]。
    static func heapAnatomySummary(ignoreThrottle: Bool = false) -> String {
        #if DEBUG
        let now = CFAbsoluteTimeGetCurrent()
        if !ignoreThrottle, now - lastAnatomyAt < anatomyMinimumInterval {
            return "anatomy=throttled"
        }
        lastAnatomyAt = now

        var zoneAddresses: UnsafeMutablePointer<vm_address_t>?
        var zoneCount: UInt32 = 0
        guard malloc_get_all_zones(mach_task_self_, nil, &zoneAddresses, &zoneCount) == KERN_SUCCESS,
            let zoneAddresses else {
            return "anatomy=noZones"
        }
        var defaultZone: UnsafeMutableRawPointer?
        for index in 0..<Int(zoneCount) {
            guard let rawZone = UnsafeMutableRawPointer(bitPattern: UInt(zoneAddresses[index])) else {
                continue
            }
            let zone = rawZone.assumingMemoryBound(to: malloc_zone_t.self)
            let name = malloc_get_zone_name(zone).map { String(cString: $0) } ?? ""
            if name == "DefaultMallocZone" {
                defaultZone = rawZone
                break
            }
        }
        guard let defaultZone else {
            return "anatomy=noDefaultZone"
        }
        let zone = defaultZone.assumingMemoryBound(to: malloc_zone_t.self)
        guard let introspect = zone.pointee.introspect,
            let enumerator = introspect.pointee.enumerator else {
            return "anatomy=noEnumerator"
        }

        // ── フェーズ1: リージョン(ゾーンが OS から借りている VM 範囲)を列挙 ──
        anatomyRegionCount = 0
        anatomyRegionOverflow = false
        _ = enumerator(
            mach_task_self_,
            nil,
            UInt32(MALLOC_PTR_REGION_RANGE_TYPE),
            vm_address_t(UInt(bitPattern: defaultZone)),
            nil
        ) { _, _, _, ranges, count in
            guard let ranges else { return }
            for index in 0..<Int(count) {
                let slot = MemoryForensics.anatomyRegionCount
                guard slot < MemoryForensics.anatomyMaxRegions else {
                    MemoryForensics.anatomyRegionOverflow = true
                    return
                }
                MemoryForensics.anatomyRegionStarts[slot] = UInt(ranges[index].address)
                MemoryForensics.anatomyRegionEnds[slot] = UInt(ranges[index].address) + UInt(ranges[index].size)
                MemoryForensics.anatomyRegionCount = slot + 1
            }
        }
        guard anatomyRegionCount > 0 else {
            return "anatomy=noRegions"
        }

        // ── フェーズ間処理(ここでは確保してよい): リージョンをソートしページ表を確保 ──
        do {
            var pairs: [(UInt, UInt)] = []
            pairs.reserveCapacity(anatomyRegionCount)
            for index in 0..<anatomyRegionCount {
                pairs.append((anatomyRegionStarts[index], anatomyRegionEnds[index]))
            }
            pairs.sort { $0.0 < $1.0 }
            for (index, pair) in pairs.enumerated() {
                anatomyRegionStarts[index] = pair.0
                anatomyRegionEnds[index] = pair.1
            }
        }
        anatomyTotalPages = 0
        for index in 0..<anatomyRegionCount {
            anatomyRegionPageBase[index] = anatomyTotalPages
            anatomyTotalPages += Int(anatomyRegionEnds[index] - anatomyRegionStarts[index]) / anatomyPageSize
        }
        anatomyRegionPageBase[anatomyRegionCount] = anatomyTotalPages
        guard anatomyTotalPages > 0, anatomyTotalPages < 4_000_000 else {
            return "anatomy=pageCountOutOfRange(\(anatomyTotalPages))"
        }
        let pageTable = UnsafeMutablePointer<UInt32>.allocate(capacity: anatomyTotalPages)
        pageTable.initialize(repeating: 0, count: anatomyTotalPages)
        defer {
            pageTable.deallocate()
            anatomyPageLiveBytes = nil
        }
        anatomyPageLiveBytes = pageTable
        anatomyBlockCount = 0
        anatomyLiveBytes = 0

        // ── フェーズ2: 生存ブロックを列挙し、ページ別の生存バイトへ配分 ──
        _ = enumerator(
            mach_task_self_,
            nil,
            UInt32(MALLOC_PTR_IN_USE_RANGE_TYPE),
            vm_address_t(UInt(bitPattern: defaultZone)),
            nil
        ) { _, _, _, ranges, count in
            guard let ranges, let table = MemoryForensics.anatomyPageLiveBytes else { return }
            let pageSize = UInt(MemoryForensics.anatomyPageSize)
            for index in 0..<Int(count) {
                let start = UInt(ranges[index].address)
                let size = UInt(ranges[index].size)
                // 二分探索: start を含むリージョン
                var low = 0
                var high = MemoryForensics.anatomyRegionCount - 1
                var found = -1
                while low <= high {
                    let mid = (low + high) / 2
                    if start < MemoryForensics.anatomyRegionStarts[mid] {
                        high = mid - 1
                    } else if start >= MemoryForensics.anatomyRegionEnds[mid] {
                        low = mid + 1
                    } else {
                        found = mid
                        break
                    }
                }
                guard found >= 0 else { continue }
                MemoryForensics.anatomyBlockCount += 1
                MemoryForensics.anatomyLiveBytes += Int(size)
                // ブロックをページ境界で分割して配分
                let regionStart = MemoryForensics.anatomyRegionStarts[found]
                let regionEnd = MemoryForensics.anatomyRegionEnds[found]
                var cursor = start
                let blockEnd = min(start + size, regionEnd)
                while cursor < blockEnd {
                    let pageIndex = MemoryForensics.anatomyRegionPageBase[found]
                        + Int((cursor - regionStart) / pageSize)
                    guard pageIndex < MemoryForensics.anatomyTotalPages else { break }
                    let pageEnd = regionStart + (UInt((cursor - regionStart) / pageSize) + 1) * pageSize
                    let portion = min(blockEnd, pageEnd) - cursor
                    table[pageIndex] &+= UInt32(portion)
                    cursor += portion
                }
            }
        }

        // ── フェーズ3: 各ページの disposition(present/dirty/圧縮済み)を照会して集計 ──
        let pinnedFlags = UnsafeMutablePointer<Bool>.allocate(capacity: anatomyTotalPages)
        pinnedFlags.initialize(repeating: false, count: anatomyTotalPages)
        defer {
            pinnedFlags.deallocate()
            anatomyPinnedFlags = nil
        }
        anatomyPinnedFlags = pinnedFlags
        var dirtyEmptyPages = 0          // dirty かつ 生存0 = 返却可能なのに居座る屑
        var dirtyPinnedPages = 0         // dirty かつ 生存≤1KB = 少量の生き残りが釘付け
        var dirtyPinnedLiveBytes = 0
        var dirtyUsedPages = 0           // dirty かつ 生存>1KB = 正当に使用中
        var compressedPages = 0          // 圧縮器へ退避済み(footprint には残る)
        var notResidentPages = 0
        var queryFailed = false
        for regionIndex in 0..<anatomyRegionCount {
            let regionStart = anatomyRegionStarts[regionIndex]
            let pageCount = Int(anatomyRegionEnds[regionIndex] - regionStart) / anatomyPageSize
            for page in 0..<pageCount {
                let address = mach_vm_offset_t(regionStart) + mach_vm_offset_t(page * anatomyPageSize)
                var disposition: Int32 = 0
                var refCount: Int32 = 0
                let kern = ecritu_mach_vm_page_query(mach_task_self_, address, &disposition, &refCount)
                let live = Int(pageTable[anatomyRegionPageBase[regionIndex] + page])
                guard kern == KERN_SUCCESS else {
                    queryFailed = true
                    continue
                }
                let present = disposition & 0x1 != 0        // VM_PAGE_QUERY_PAGE_PRESENT
                let dirty = disposition & 0x8 != 0          // VM_PAGE_QUERY_PAGE_DIRTY
                let pagedOut = disposition & 0x10 != 0      // VM_PAGE_QUERY_PAGE_PAGED_OUT(圧縮含む)
                if pagedOut {
                    compressedPages += 1
                } else if !present {
                    notResidentPages += 1
                } else if dirty {
                    if live == 0 {
                        dirtyEmptyPages += 1
                    } else if live <= 1024 {
                        dirtyPinnedPages += 1
                        dirtyPinnedLiveBytes += live
                        pinnedFlags[anatomyRegionPageBase[regionIndex] + page] = true
                    } else {
                        dirtyUsedPages += 1
                    }
                }
            }
        }
        // ── フェーズ4: 釘ページの住人の正体調べ(もう一周列挙し、該当ページの
        // 生存ブロックだけ isa 別/サイズ別に数える。表は事前確保済みで列挙中は拡張しない)──
        anatomyPinnedClassCounts.removeAll(keepingCapacity: true)
        anatomyPinnedRawCountBySize.removeAll(keepingCapacity: true)
        if dirtyPinnedPages > 0 {
            _ = anatomyClassNamesByPointer  // 名前表は列挙前に構築しておく
            _ = enumerator(
                mach_task_self_,
                nil,
                UInt32(MALLOC_PTR_IN_USE_RANGE_TYPE),
                vm_address_t(UInt(bitPattern: defaultZone)),
                nil
            ) { _, _, _, ranges, count in
                guard let ranges, let flags = MemoryForensics.anatomyPinnedFlags else { return }
                let pageSize = UInt(MemoryForensics.anatomyPageSize)
                for index in 0..<Int(count) {
                    let start = UInt(ranges[index].address)
                    let size = Int(ranges[index].size)
                    var low = 0
                    var high = MemoryForensics.anatomyRegionCount - 1
                    var found = -1
                    while low <= high {
                        let mid = (low + high) / 2
                        if start < MemoryForensics.anatomyRegionStarts[mid] {
                            high = mid - 1
                        } else if start >= MemoryForensics.anatomyRegionEnds[mid] {
                            low = mid + 1
                        } else {
                            found = mid
                            break
                        }
                    }
                    guard found >= 0 else { continue }
                    let pageIndex = MemoryForensics.anatomyRegionPageBase[found]
                        + Int((start - MemoryForensics.anatomyRegionStarts[found]) / pageSize)
                    guard pageIndex < MemoryForensics.anatomyTotalPages, flags[pageIndex] else { continue }
                    // isa 判定: 先頭ワードが登録済みクラスならクラス別、でなければ raw サイズ別
                    var classified = false
                    if size >= 16, let base = UnsafeRawPointer(bitPattern: start) {
                        let head = UInt(UnsafeRawBufferPointer(start: base, count: 8).loadUnaligned(as: UInt64.self))
                        if MemoryForensics.anatomyClassNamesByPointer[head] != nil {
                            MemoryForensics.anatomyPinnedClassCounts[head, default: 0] += 1
                            classified = true
                        }
                    }
                    if !classified {
                        MemoryForensics.anatomyPinnedRawCountBySize[size, default: 0] += 1
                    }
                }
            }
        }
        var pinnedResidents = ""
        if !anatomyPinnedClassCounts.isEmpty || !anatomyPinnedRawCountBySize.isEmpty {
            let classTop = anatomyPinnedClassCounts
                .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .prefix(6)
                .map { "\(anatomyClassNamesByPointer[$0.key] ?? "?")×\($0.value)" }
            let rawTop = anatomyPinnedRawCountBySize
                .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .prefix(6)
                .map { "raw\($0.key)B×\($0.value)" }
            pinnedResidents = " | 釘の正体<\((classTop + rawTop).joined(separator: ","))>"
        }
        func mb(_ pages: Int) -> String {
            String(format: "%.1f", Double(pages * anatomyPageSize) / 1_048_576)
        }
        return "anatomy regions=\(anatomyRegionCount)\(anatomyRegionOverflow ? "(溢れ)" : "")"
            + " spanMB=\(mb(anatomyTotalPages))"
            + " blocks=\(anatomyBlockCount)"
            + " liveMB=\(String(format: "%.1f", Double(anatomyLiveBytes) / 1_048_576))"
            + " | dirty内訳: 空=\(mb(dirtyEmptyPages))MB"
            + " 釘≤1KB=\(mb(dirtyPinnedPages))MB(生存\(String(format: "%.2f", Double(dirtyPinnedLiveBytes) / 1_048_576))MB)"
            + " 使用中=\(mb(dirtyUsedPages))MB"
            + " | 圧縮済=\(mb(compressedPages))MB 非常駐=\(mb(notResidentPages))MB"
            + pinnedResidents
            + (queryFailed ? " pageQuery=部分失敗" : "")
        #else
        return "off"
        #endif
    }
}

extension MemoryForensics {
    // ──────────────────────────────────────────────
    // 設定化けの監視(2624)— レイアウト系設定が勝手に変わる事象の証拠採取
    // ──────────────────────────────────────────────
    // 2026-08-22 に保存済みの配列設定(かな/ラテン/数字)が1日に3回、別々の歴史的状態へ
    // 飛んだ(qwerty/telephone/fiveByTwo/キー欠落)。écritu には配列設定を書くコードが
    // App の Picker 以外に無く、cfprefsd の plist 巻き戻り(iOS 側)を疑っている。
    // 変化の瞬間を時刻+旧新値で criticalLog に残し、次回の発生を帰属する。
    nonisolated(unsafe) private static var lastObservedLayoutSnapshot: String?

    static func noteLayoutSettingsSnapshot(_ snapshot: String) {
        #if DEBUG
        ledgerLock.lock()
        let previous = lastObservedLayoutSnapshot
        lastObservedLayoutSnapshot = snapshot
        ledgerLock.unlock()
        guard let previous, previous != snapshot else {
            return
        }
        logSink?("MEMFORENSICS設定変化 \(previous) → \(snapshot)")
        #endif
    }

    // ──────────────────────────────────────────────
    // VM リージョン走査: malloc 外の internal dirty の帰属
    // ──────────────────────────────────────────────
    // 実機解剖(2620)で footprint 71.9MB のうち malloc ヒープの dirty は約23MB しかなく、
    // 残り約45MB が malloc 外の internal と判明した。AttributeGraph(SwiftUI の依存グラフ)は
    // malloc ゾーンでなく自前の vm_allocate を使うため malloc 解剖に写らない。
    // 全リージョンを user_tag 別に dirty+swapped で集計して帰属を名指しする。
    static func vmRegionSummaryByTag() -> String {
        #if DEBUG
        var totalsByTag: [UInt32: (dirtyPages: Int, regions: Int)] = [:]
        var address: mach_vm_address_t = 0
        var iterations = 0
        while iterations < 8192 {
            iterations += 1
            var size: mach_vm_size_t = 0
            var info = vm_region_submap_info_64()
            var count = mach_msg_type_number_t(
                MemoryLayout<vm_region_submap_info_64>.size / MemoryLayout<Int32>.size
            )
            var depth: natural_t = 0
            let kern = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: Int32.self, capacity: Int(count)) { rebound in
                    ecritu_mach_vm_region_recurse(mach_task_self_, &address, &size, &depth, rebound, &count)
                }
            }
            guard kern == KERN_SUCCESS else { break }
            if info.is_submap != 0 {
                // submap は潜らず(深さ0集計で共有キャッシュ等は除外側に落ちる)、次へ
                address += size
                continue
            }
            // internal(アプリ由来 dirty)+ 圧縮器へ退避済み(どちらも footprint に計上)
            let dirty = Int(info.pages_dirtied) + Int(info.pages_swapped_out)
            if dirty > 0 {
                totalsByTag[info.user_tag, default: (0, 0)].dirtyPages += dirty
                totalsByTag[info.user_tag, default: (0, 0)].regions += 1
            }
            address += size
        }
        // 主要タグ名(mach/vm_statistics.h の VM_MEMORY_*)
        func tagName(_ tag: UInt32) -> String {
            switch tag {
            case 0: return "untagged"
            case 1...9: return "malloc"
            case 10: return "malloc_huge"
            case 11: return "sbrk"
            case 12: return "realloc"
            case 13: return "malloc_tiny"
            case 30: return "stack"
            case 31: return "guard"
            case 32: return "shared_pmap"
            case 33: return "dylib"
            case 34: return "objc_dispatchers"
            case 35: return "unshared_pmap"
            case 40: return "appkit"
            case 41: return "foundation"
            case 42: return "coregraphics"
            case 43: return "corservices"
            case 44: return "java"
            case 46: return "ats"
            case 53: return "cgimage"
            case 54: return "tcmalloc"
            case 63: return "iokit"
            case 66: return "libdispatch"
            case 70: return "os_alloc_once"
            case 71: return "libdispatch"
            case 72: return "accelerate"
            case 73: return "coreui"
            case 74: return "coreuifile"
            case 75: return "genealogy"
            case 76: return "rawcamera"
            case 80: return "swift_metadata"
            case 84: return "cm_regwarehouse"
            case 87: return "coreanimation(CA)"
            case 88: return "coreanimation_layer"
            case 89: return "coreanimation_render"
            case 90: return "coreanimation_backing"
            case 96: return "objc_runtime"
            case 98: return "os_log"
            case 99: return "descriptive"
            case 100: return "graphics_misc"
            case 240: return "AttributeGraph?"
            case 241: return "AttributeGraph?"
            default: return "tag\(tag)"
            }
        }
        let sorted = totalsByTag.sorted { $0.value.dirtyPages > $1.value.dirtyPages }.prefix(12)
        let parts = sorted.map { entry in
            let mb = Double(entry.value.dirtyPages) * 16384 / 1_048_576
            return "\(tagName(entry.key))=\(String(format: "%.1f", mb))MB(\(entry.value.regions)r)"
        }
        return "vmTags[\(parts.joined(separator: " "))]"
        #else
        return "off"
        #endif
    }
}

// mach_vm_region_recurse も同様に直接束ねる(自タスクへの照会は entitlement 不要)。
@_silgen_name("mach_vm_region_recurse")
private func ecritu_mach_vm_region_recurse(
    _ targetTask: mach_port_name_t,
    _ address: UnsafeMutablePointer<mach_vm_address_t>,
    _ size: UnsafeMutablePointer<mach_vm_size_t>,
    _ nestingDepth: UnsafeMutablePointer<natural_t>,
    _ info: UnsafeMutablePointer<Int32>,
    _ infoCount: UnsafeMutablePointer<mach_msg_type_number_t>
) -> kern_return_t

// mach_vm_page_query は SDK ヘッダに在るが Swift へ露出しない環境があるため直接束ねる。
// 自タスクへの照会は entitlement 不要。
@_silgen_name("mach_vm_page_query")
private func ecritu_mach_vm_page_query(
    _ targetMap: mach_port_name_t,
    _ offset: mach_vm_offset_t,
    _ disposition: UnsafeMutablePointer<Int32>,
    _ refCount: UnsafeMutablePointer<Int32>
) -> kern_return_t
