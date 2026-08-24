import SwiftUI
import UIKit
import CoreFoundation
import Darwin
import Contacts

// 診断まわりの帳簿状態。VC本体の状態肥大を防ぐため分離(挙動不変の移動)。
extension KeyboardViewController {
    final class DiagnosticsState {
        var diagnosticsSessionID = UUID().uuidString
        var diagnosticsSessionStartedAt = Date()
        let diagnosticsControllerID = UUID().uuidString
        var diagnosticsFlightRecorderLastObservedAt: [String: TimeInterval] = [:]
        // 診断のメモリ内バッファ(毎打鍵の UserDefaults JSON ラウンドトリップ回避)。
        // nil=未ロード。永続化は2秒スロットル+重要イベント即時+ライフサイクルでフラッシュ。
        var diagnosticsFlightRecorderBuffer: [DiagnosticsFlightRecorderEvent]?
        var diagnosticsFlightRecorderLastPersistedAt: TimeInterval = 0
        var diagnosticsLogLinesBuffer: [String]?
        var diagnosticsHeartbeatLastPersistedAt: TimeInterval = 0
        var diagnosticsLastPersistedFailSafeProfile: MemoryFailSafeProfile?
        // 診断: 押下表示残留(赤キー)を watchdog が強制解除した回数(セッション累計)。
        var stuckTouchForceClearCount = 0
        // 診断: このセッションで受けたメモリ警告の回数。2回目以降は最終手段として
        // 連文節LM(sqlite)もアンロードする(初回は ef56d52 の方針どおり保持)。
        var memoryWarningCountThisSession = 0
    }
}

extension KeyboardViewController {
    func physicalMemoryGBText() -> String {
        let physicalMemoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        return String(format: "%.1f", physicalMemoryGB)
    }

    func diagnosticsProcessLabel() -> String {
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown.keyboard.bundle"
        let processName = ProcessInfo.processInfo.processName
        return "\(bundleID)(\(processName))"
    }

    func diagnosticsProcessID() -> Int32 {
        getpid()
    }

    func diagnosticsSessionOwnerToken() -> String {
        "\(diagnosticsProcessID()):\(diagnosticsState.diagnosticsControllerID)"
    }

    func currentResidentMemoryBytes() -> UInt64? {
        var info = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<integer_t>.size
        )

        let result: kern_return_t = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), intPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }

        return UInt64(info.resident_size)
    }

    // iOS の jetsam 判定に使われる phys_footprint。RSS(resident_size)と違い
    // 共有/クリーンページや mmap を含まないため、実際の強制終了圧の指標になる。
    func currentFootprintBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )

        let result: kern_return_t = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }

        return UInt64(info.phys_footprint)
    }

    func currentFootprintMB() -> Double? {
        guard let bytes = currentFootprintBytes() else {
            return nil
        }

        return Double(bytes) / 1_048_576
    }

    func diagnosticsFootprintMBText() -> String {
        guard let bytes = currentFootprintBytes() else {
            return "unknown"
        }

        let mb = Double(bytes) / 1_048_576
        return String(format: "%.1f", mb)
    }

    func diagnosticsResidentMemoryMBText() -> String {
        guard let bytes = currentResidentMemoryBytes() else {
            return "unknown"
        }

        let mb = Double(bytes) / 1_048_576
        return String(format: "%.1f", mb)
    }

    func currentResidentMemoryMB() -> Double? {
        guard let bytes = currentResidentMemoryBytes() else {
            return nil
        }

        return Double(bytes) / 1_048_576
    }

    // 今この瞬間、別インスタンスがセッションのオーナーかどうか。lostActiveOwnershipAt は
    // 降格時に立つ一度きりのフラグなので、破壊的な解放の直前には現在値を取り直す。
    func isConfirmedNonOwnerSession() -> Bool {
        guard let sharedDefaults,
            let activeOwnerToken = sharedDefaults.string(
                forKey: SharedDefaultsKeys.keyboardDiagnosticsSessionOwnerToken
            ),
            !activeOwnerToken.isEmpty else {
            return false
        }

        return activeOwnerToken != diagnosticsSessionOwnerToken()
    }

    func shouldSuppressHeavyOperations(reason: String) -> Bool {
        guard let sharedDefaults,
            let activeOwnerToken = sharedDefaults.string(
                forKey: SharedDefaultsKeys.keyboardDiagnosticsSessionOwnerToken
            ),
            !activeOwnerToken.isEmpty else {
            didApplyInactiveSessionMitigation = false
            return false
        }

        let currentOwnerToken = diagnosticsSessionOwnerToken()

        guard activeOwnerToken != currentOwnerToken else {
            didApplyInactiveSessionMitigation = false
            return false
        }

        let now = CFAbsoluteTimeGetCurrent()

        if now - lastInactiveSessionSuppressionLogAt >= 1.0 {
            appendKeyboardDiagnosticsLog(
                "多重生存中の非アクティブインスタンスで重い更新を抑止 reason=\(reason) activeOwner=\(activeOwnerToken) currentOwner=\(currentOwnerToken)",
                file: #fileID,
                line: #line,
                function: #function
            )
            lastInactiveSessionSuppressionLogAt = now
        }

        if !didApplyInactiveSessionMitigation {
            performHiddenKeyboardMemoryTrim(
                reason: "inactiveSession-\(reason)",
                releaseHostingView: view.window == nil,
                includeSystemCaches: true
            )
            // 非アクティブ(ゾンビ)側は通知の受信そのものを止めて不活性化する。iOS が旧
            // インスタンスを保持し続ける間(数分に及ぶことがある)、共有設定変更通知や
            // watchdog で無駄に起こされないように。再アクティブ化時は viewWillAppear が
            // observer を再登録する(2411)。
            stopObservingSettingsDidChange()
            stopMarkedTextWatchdog()
            // オーナー権を得ていた間に予約した起動処理(bootstrap/辞書プリロード)も取り消す。
            // 双子起動の敗者が遅延実行で重い処理を走らせない(オーナー復帰時は viewWillAppear→
            // viewDidAppear が bootstrap を再予約する)。
            keyboardBootstrapWorkItem?.cancel()
            keyboardBootstrapWorkItem = nil
            dictionaryPreloadWorkItem?.cancel()
            dictionaryPreloadWorkItem = nil
            if lostActiveOwnershipAt == 0 {
                lostActiveOwnershipAt = CFAbsoluteTimeGetCurrent()
                logLiveControllerCensus(trigger: "inactive-\(reason)")
                scheduleZombieSurvivalCanary()
            }
            didApplyInactiveSessionMitigation = true
        }

        return true
    }

    // ──── 多重生存センサス(原因特定用のでばぐ計測)────
    // 生存インスタンス一覧を UIKit アンカー付きでログする。window/superview/parent が全て無く
    // 当方保持(hosting/observer/watchdog)も無いのに CF参照数が残っていれば、保持者は
    // プロセス外=UIKit/システム側と確定できる。
    func instanceAnchorSummary() -> String {
        let v = viewIfLoaded
        let age = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - controllerCreatedAt)
        let zombieSec = lostActiveOwnershipAt > 0
            ? String(format: "%.1f", CFAbsoluteTimeGetCurrent() - lostActiveOwnershipAt)
            : "-"
        return "id=\(diagnosticsState.diagnosticsControllerID.prefix(8)) age=\(age)s zombie=\(zombieSec)s"
            + " window=\(v?.window != nil) superview=\(v?.superview != nil)"
            + " parentVC=\(parent != nil) hosting=\(hostingController != nil)"
            + " observing=\(isObservingSettingsDidChange)"
            + " retain=\(CFGetRetainCount(self))"
    }

    func logLiveControllerCensus(trigger: String) {
        let controllers = KeyboardViewController.liveControllerCensus.allObjects
        guard controllers.count >= 2 else {
            return
        }
        let summaries = controllers.map { $0.instanceAnchorSummary() }.joined(separator: " | ")
        appendKeyboardDiagnosticsLog(
            "多重生存センサス alive=\(controllers.count) trigger=\(trigger) [\(summaries)]",
            critical: true,
            file: #fileID,
            line: #line,
            function: #function
        )
    }

    // ゾンビ・カナリア: 降格から一定時間後に弱参照で生存確認し、まだ生きていれば
    // アンカーを再ダンプする(何も強参照しないので延命はしない)。
    // 併せてビュー階層の解放を再試行する: 降格時点の一度きりの解放判定
    // (shouldSuppressHeavyOperations の releaseHostingView: view.window == nil)は、
    // その瞬間まだ window に載っていると false になり、didApplyInactiveSessionMitigation
    // により二度と試されない。実測(2570 census)でゾンビ2体が80分/97分ビュー階層を
    // 抱えたまま生存しており、footprint 固定費の主因だった(2574)。
    func scheduleZombieSurvivalCanary() {
        // 30s は window から外れたゾンビだけを穏当に回収する。それでも生き残る個体は
        // window に載ったままなので、120s 以降は window 条件を外して解放する。
        for delay in [30.0, 120.0, 300.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.lostActiveOwnershipAt > 0 else {
                    return
                }
                self.appendKeyboardDiagnosticsLog(
                    "ゾンビ生存確認 +\(Int(delay))s \(self.instanceAnchorSummary())",
                    critical: true,
                    file: #fileID,
                    line: #line,
                    function: #function
                )
                self.releaseHostingViewIfZombie(
                    reason: "zombieCanary+\(Int(delay))s",
                    ignoringWindowAttachment: delay >= 120.0
                )
            }
        }
    }

    // 非表示のゾンビが抱えるビュー階層(UIHostingController+SwiftUI階層)を解放する。
    // 表示中(window あり)やオーナー復帰後は何もしない。再表示時は
    // ensureKeyboardViewIfNeeded が再構築する。
    func releaseHostingViewIfZombie(reason: String, ignoringWindowAttachment: Bool = false) {
        guard lostActiveOwnershipAt > 0, let host = hostingController else {
            return
        }
        if ignoringWindowAttachment {
            // 長期滞留カナリアからの再試行。window に載ったままのゾンビも対象にする。
            // 実測(2582 census)で zombie=109.8s のインスタンスが window=true のため
            // 上の条件で毎回弾かれ、SwiftUI 階層を抱えたまま生存していた。旧入力
            // ウィンドウに載り続けること自体が漏れなので window は判断材料にしない。
            // 誤爆(表示中のキーボードを消す)を防ぐため、代わりに二つ確認する:
            //   - viewWillAppear を通っていない(observer 未登録=再表示されていない)
            //   - 今この瞬間も別インスタンスがオーナーである
            // オーナートークンが「不在」の場合も解放する(2601)。降格させた側の
            // インスタンスが破棄されるとき releaseKeyboardSessionOwnershipIfHeld() が
            // トークンを消すため、降格済みインスタンスから見ると不在が普通に起きる。
            // isConfirmedNonOwnerSession() は不在を false(=確認できない)として扱うので、
            // それだけを条件にすると解放が永久に走らなかった(実測: 2601 で
            // ゾンビ生存確認 +120s/+300s が発火しても hosting=true のまま23分滞留)。
            // 不在は「誰もオーナーを主張していない」状態で、表示中なら viewWillAppear が
            // 必ず主張するので、不在かつ observer 未登録なら表示中ではないと判断できる。
            // 「トークン不在なら解放してよい」は危険だった(2604で撤回)。表示中の A が
            // 投機生成の B に一瞬オーナーを奪われ、B が破棄されてトークンを消すと、
            // 画面に出たままの A が解放対象になってしまう(=表示中のキーボードを壊す)。
            // 代わりに「他に生きて表示中のインスタンスが実在するか」を直接見る。
            // これなら自分が唯一の表示インスタンスのときは絶対に解放しない。
            let hasOtherActiveController = KeyboardViewController.liveControllerCensus.allObjects
                .contains { other in
                    other !== self
                        && other.lostActiveOwnershipAt == 0
                        && other.isObservingSettingsDidChange
                }
            guard !isObservingSettingsDidChange,
                isConfirmedNonOwnerSession() || hasOtherActiveController else {
                // 弾いた理由を残す。ログに「ゾンビ生存確認」だけが並んで解放が来ないとき、
                // どちらのゲートで止まったのかが分からず調査が遠回りになった(2601)。
                appendKeyboardDiagnosticsLog(
                    "ゾンビ解放を見送り reason=\(reason)"
                        + " observing=\(isObservingSettingsDidChange)"
                        + " confirmedNonOwner=\(isConfirmedNonOwnerSession())"
                        + " otherActive=\(hasOtherActiveController)",
                    critical: true,
                    file: #fileID,
                    line: #line,
                    function: #function
                )
                return
            }
        } else {
            guard view.window == nil, host.view.window == nil else {
                return
            }
        }
        let beforeMB = currentFootprintMB()
        host.willMove(toParent: nil)
        host.view.removeFromSuperview()
        host.removeFromParent()
        hostingController = nil
        lastRenderConfiguration = nil
        let beforeText = beforeMB.map { String(format: "%.1f", $0) } ?? "?"
        appendKeyboardDiagnosticsLog(
            "ゾンビのビュー階層を解放 reason=\(reason) footprintMB=\(beforeText)→\(diagnosticsFootprintMBText())",
            critical: true,
            file: #fileID,
            line: #line,
            function: #function
        )
    }

    // honorsSlimmingToggle: 通常の非表示時(viewWillDisappear/viewDidDisappear)だけ true。
    // メモリ警告・ゾンビ不活性化・attach失敗の後始末は生存機構なのでトグルに関係なく実行する(2640)
    func performHiddenKeyboardMemoryTrim(
        reason: String,
        releaseHostingView: Bool,
        includeSystemCaches: Bool,
        honorsSlimmingToggle: Bool = false
    ) {
        let slimmingActive = !honorsSlimmingToggle || isSuspendMemorySlimmingEnabled
        pendingRefreshKeyboardStateRequests = 0
        isRefreshKeyboardStateAsyncScheduled = false
        activeConversion = nil
        // 診断バッファ(ログ最大320行+フライトレコーダ)はインスタンスごとに持つ。
        // ゾンビが増えるほど積み上がるので、降格時に書き出して手放す(2603)。
        // 実測: alive=10→37.0MB / 12→40.6MB / 15→46.7MB と1体あたり約1.3MB増えていた。
        // 再表示されたら次の追記時に defaults から読み直される(nil=未ロード)。
        persistBufferedKeyboardDiagnostics()
        diagnosticsState.diagnosticsLogLinesBuffer = nil
        diagnosticsState.diagnosticsFlightRecorderBuffer = nil
        clearComposingState()
        clearRecentKanaPlainCommitUpgradeContext()
        lastSynchronizedContextBeforeInputTail = ""
        lastSynchronizedContextBeforeInputLength = 0
        invalidateTextContextCache()

        keyboardHeightLockReleaseWorkItem?.cancel()
        keyboardHeightLockReleaseWorkItem = nil
        keyboardHeightLockValue = nil
        keyboardHeightLockReleaseTime = 0

        dictionaryPreloadWorkItem?.cancel()
        dictionaryPreloadWorkItem = nil

        keyboardBootstrapWorkItem?.cancel()
        keyboardBootstrapWorkItem = nil

        sharedDataPrewarmWorkItem?.cancel()
        sharedDataPrewarmWorkItem = nil

        clearSupplementaryLexiconCandidatesForMemoryTrim()
        clearContactCandidatesIfNeeded(refreshKeyboardState: false)

        // 変換キャッシュ破棄はスリム化設定に従う(オフ=調査時など、破棄も返却もしない)
        if slimmingActive {
            if includeSystemCaches {
                kanaKanjiConverter.clearAllCaches()
            } else {
                kanaKanjiConverter.clearSharedDataCaches()
            }
        }

        if releaseHostingView,
            let host = hostingController {
            host.willMove(toParent: nil)
            host.view.removeFromSuperview()
            host.removeFromParent()
            hostingController = nil
        }

        lastRenderConfiguration = nil

        // free済みdirtyページをOSへ返す(2640)。キャッシュ解放だけでは malloc が
        // ページを抱えたままで footprint が下がらず(実測: 退出後も alloc 68MB 据え置き)、
        // 長寝プロセスが高水位のまま叩き起こされて per-process-limit 即死→
        // 再起動ペナルティ(40秒→141秒とエスカレート)→Apple KB 化していた。
        // 寝る瞬間に返却しておけば起床時の最初の変換(+4MB)に耐えられる。
        if slimmingActive {
            malloc_zone_pressure_relief(nil, 0)
            // MEMFORENSICS(時限計測 2640): スリム化の返却量(1MB以上動いたときだけ記録)
            MemoryForensics.noteSpikeWindow("スリム化(\(reason))")
        }

        updateKeyboardDiagnosticsHeartbeat(
            event: "キーボード非表示でメモリ解放 reason=\(reason) releaseView=\(releaseHostingView) clearSystem=\(includeSystemCaches)"
                + " slim=\(slimmingActive ? "on" : "off") profile=\(memoryFailSafeProfile.rawValue)",
            appendLog: true
        )
    }

    func updateMemoryFailSafeProfile(trigger: String) {
        guard let footprintMB = currentFootprintMB() else {
            return
        }

        let nextProfile = nextMemoryFailSafeProfile(for: footprintMB)

        guard nextProfile != memoryFailSafeProfile else {
            return
        }

        let previousProfile = memoryFailSafeProfile
        memoryFailSafeProfile = nextProfile
        persistKeyboardDiagnosticsFailSafeProfile()

        appendKeyboardDiagnosticsLog(
            "メモリフェイルセーフ遷移 \(previousProfile.rawValue) -> \(nextProfile.rawValue) trigger=\(trigger) footprintMB=\(String(format: "%.1f", footprintMB))",
            critical: true,
            file: #fileID,
            line: #line,
            function: #function
        )

        switch nextProfile {
        case .normal:
            break
        case .elevated:
            kanaKanjiConverter.clearSharedDataCaches()
        case .critical:
            kanaKanjiConverter.clearAllCaches()
        }

        if previousProfile == .critical,
            nextProfile != .critical {
            applyDeferredSharedSettingsCatchUpIfNeeded(trigger: trigger)
        }
    }

    func applyDeferredSharedSettingsCatchUpIfNeeded(trigger: String) {
        guard hasDeferredSharedSettingsCatchUp,
            memoryFailSafeProfile != .critical else {
            return
        }

        guard view.window != nil || hostingController != nil else {
            return
        }

        hasDeferredSharedSettingsCatchUp = false

        appendKeyboardDiagnosticsLog(
            "critical中に保留した共有設定反映を再開 trigger=\(trigger) profile=\(memoryFailSafeProfile.rawValue)",
            file: #fileID,
            line: #line,
            function: #function
        )

        kanaKanjiConverter.clearSharedDataCaches()
        refreshContactCandidatesIfNeeded(force: true)
        refreshKeyboardStateAsync()
    }

    func nextMemoryFailSafeProfile(for footprintMB: Double) -> MemoryFailSafeProfile {
        let elevatedStart = Self.memoryFailSafeElevatedStartMB
        let criticalStart = Self.memoryFailSafeCriticalStartMB
        let recoverDelta = Self.memoryFailSafeRecoverDeltaMB

        switch memoryFailSafeProfile {
        case .normal:
            if footprintMB >= criticalStart {
                return .critical
            }

            if footprintMB >= elevatedStart {
                return .elevated
            }

            return .normal
        case .elevated:
            if footprintMB >= criticalStart {
                return .critical
            }

            if footprintMB < elevatedStart - recoverDelta {
                return .normal
            }

            return .elevated
        case .critical:
            if footprintMB >= criticalStart - recoverDelta {
                return .critical
            }

            if footprintMB >= elevatedStart - recoverDelta {
                return .elevated
            }

            return .normal
        }
    }

    func diagnosticsRuntimeContext() -> String {
        "process=\(diagnosticsProcessLabel()) pid=\(diagnosticsProcessID()) controllerID=\(diagnosticsState.diagnosticsControllerID) rssMB=\(diagnosticsResidentMemoryMBText()) footprintMB=\(diagnosticsFootprintMBText()) failSafe=\(memoryFailSafeProfile.rawValue)"
    }

    func persistKeyboardDiagnosticsFailSafeProfile(in defaults: UserDefaults? = nil) {
        // 毎ハートビートで同値を書き直さない(変化時のみ)。
        guard memoryFailSafeProfile != diagnosticsState.diagnosticsLastPersistedFailSafeProfile else {
            return
        }
        let targetDefaults = defaults ?? sharedDefaults
        targetDefaults?.set(
            memoryFailSafeProfile.rawValue,
            forKey: SharedDefaultsKeys.keyboardDiagnosticsFailSafeProfile
        )
        diagnosticsState.diagnosticsLastPersistedFailSafeProfile = memoryFailSafeProfile
    }

    func diagnosticsLogLines(
        from defaults: UserDefaults,
        key: String = SharedDefaultsKeys.keyboardDiagnosticsLogLines
    ) -> [String] {
        if let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode([String].self, from: data) {
            return decoded
        }

        if let raw = defaults.array(forKey: key) {
            return raw.compactMap { $0 as? String }
        }

        return []
    }

    func saveDiagnosticsLogLines(
        _ lines: [String],
        to defaults: UserDefaults,
        key: String = SharedDefaultsKeys.keyboardDiagnosticsLogLines
    ) {
        if let encoded = try? JSONEncoder().encode(lines) {
            defaults.set(encoded, forKey: key)
            return
        }

        defaults.set(lines, forKey: key)
    }

    // 表示未到達の監視: viewDidLoad後この秒数以内にviewWillAppearが来なければ、
    // 「iOSがリモートビューを取り付けずシステムキーボードへフォールバックした疑い」として
    // critical logへ累積カウント付きで記録する(2521)。プロセス内の遅延ではなく
    // ホスト側の接続失敗を数えるのが目的(2518事象: viewDidLoad 4ms完了後29秒未表示)。
    // 正常時のviewDidLoad→viewWillAppearは数百ms以内なので5秒は誤検知しない余裕。
    static let keyboardAttachWatchdogDelaySec: TimeInterval = 5
    // 遅延発火の許容幅。asyncAfterのタイマーはプロセスsuspend中は進まないため、
    // キーボード退場直後にiOSが投機生成した未表示VCの分が、次回resume時にまとめて
    // 遅延発火する(2528実測: viewDidLoad後21.6秒)。真性のattach失敗はほぼ定刻
    // (実測5.0〜5.3秒)に発火するので、これを超える遅れは失敗として数えない。
    static let keyboardAttachWatchdogLateFireToleranceSec: TimeInterval = 5

    func startKeyboardAttachWatchdog() {
        guard let sharedDefaults else {
            return
        }
        let launchCount =
            sharedDefaults.integer(forKey: SharedDefaultsKeys.keyboardDiagnosticsLaunchCount) + 1
        sharedDefaults.set(launchCount, forKey: SharedDefaultsKeys.keyboardDiagnosticsLaunchCount)

        let scheduledAt = CFAbsoluteTimeGetCurrent()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }
            self.keyboardAttachWatchdogWorkItem = nil
            let elapsedSec = CFAbsoluteTimeGetCurrent() - scheduledAt
            if elapsedSec > Self.keyboardAttachWatchdogDelaySec + Self.keyboardAttachWatchdogLateFireToleranceSec {
                self.appendKeyboardDiagnosticsLog(
                    "表示未到達watchdogの遅延発火を偽陽性として除外(suspend跨ぎ・投機生成VCの疑い) 実経過\(String(format: "%.1f", elapsedSec))秒",
                    critical: true
                )
                self.releaseNeverDisplayedKeyboardResources(reason: "lateFire")
                return
            }
            // 監視開始より後に別インスタンスが表示されていれば、ユーザーは écritu を見ている
            // (2531実測: 同一プロセスで2秒差の連続発火)。iOS の投機生成VCであって attach
            // 失敗ではないので数えない。
            if KeyboardViewController.lastAttachedViewWillAppearAt > scheduledAt {
                self.appendKeyboardDiagnosticsLog(
                    "表示未到達watchdogを偽陽性として除外(同一プロセスで別インスタンスが表示済み=投機生成VC) 実経過\(String(format: "%.1f", elapsedSec))秒",
                    critical: true
                )
                self.releaseNeverDisplayedKeyboardResources(reason: "otherInstanceAttached")
                return
            }
            guard let defaults = self.sharedDefaults else {
                self.releaseNeverDisplayedKeyboardResources(reason: "noDefaults")
                return
            }
            let failureCount =
                defaults.integer(forKey: SharedDefaultsKeys.keyboardDiagnosticsAttachFailureCount) + 1
            defaults.set(failureCount, forKey: SharedDefaultsKeys.keyboardDiagnosticsAttachFailureCount)
            let totalLaunchCount =
                defaults.integer(forKey: SharedDefaultsKeys.keyboardDiagnosticsLaunchCount)
            self.appendKeyboardDiagnosticsLog(
                "表示未到達(attach失敗の疑い) viewDidLoad後\(Int(Self.keyboardAttachWatchdogDelaySec))秒viewWillAppear未到達 累計\(failureCount)回/起動\(totalLaunchCount)回",
                critical: true
            )
            // 遅延復帰の判定用に「未到達と数えた」ことを覚えておく。ホスト接続の再確立に
            // 数秒かかるケース(実測6.5秒)では、この後 viewWillAppear が来る。真の失敗と
            // 区別できないと統計が実態からずれる(2564)
            self.keyboardAttachWatchdogFiredAt = CFAbsoluteTimeGetCurrent()
            self.releaseNeverDisplayedKeyboardResources(reason: "attachFailure")
        }
        keyboardAttachWatchdogWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.keyboardAttachWatchdogDelaySec,
            execute: workItem
        )
    }

    func cancelKeyboardAttachWatchdog() {
        keyboardAttachWatchdogWorkItem?.cancel()
        keyboardAttachWatchdogWorkItem = nil
    }

    // watchdog が「表示未到達」と数えた後に viewWillAppear が来たケース。ホスト接続の
    // 再確立が遅かっただけで attach は最終的に成立しているので、失敗カウントを取り消して
    // 遅延復帰として記録する。ユーザー体験としては「その待ち時間だけ純正キーボードが出る」
    // という別の問題なので、遅延そのものは残す(2564)。
    func recordKeyboardAttachLateRecoveryIfNeeded() {
        guard let firedAt = keyboardAttachWatchdogFiredAt else {
            return
        }
        keyboardAttachWatchdogFiredAt = nil
        let lateSec = CFAbsoluteTimeGetCurrent() - firedAt
        guard let defaults = sharedDefaults else {
            return
        }
        let failureCount = defaults.integer(forKey: SharedDefaultsKeys.keyboardDiagnosticsAttachFailureCount)
        if failureCount > 0 {
            defaults.set(failureCount - 1, forKey: SharedDefaultsKeys.keyboardDiagnosticsAttachFailureCount)
        }
        let lateCount =
            defaults.integer(forKey: SharedDefaultsKeys.keyboardDiagnosticsAttachLateRecoveryCount) + 1
        defaults.set(lateCount, forKey: SharedDefaultsKeys.keyboardDiagnosticsAttachLateRecoveryCount)
        let totalDelaySec = Self.keyboardAttachWatchdogDelaySec + lateSec
        appendKeyboardDiagnosticsLog(
            "表示未到達から遅延復帰(attach失敗ではない) viewDidLoad→viewWillAppear=\(String(format: "%.1f", totalDelaySec))秒"
                + " 累計遅延復帰\(lateCount)回 / 未到達\(max(failureCount - 1, 0))回",
            critical: true
        )
    }

    // 表示されたインスタンスがオーナー権(重い処理を担う権利)を主張する。viewWillAppear から
    // 呼ぶ。オーナー権を viewDidLoad で主張しないのは startKeyboardDiagnosticsSession の
    // コメント参照(投機生成VCによる横取りを防ぐ)。
    func claimKeyboardSessionOwnership() {
        guard let sharedDefaults else {
            return
        }
        let token = diagnosticsSessionOwnerToken()
        let storedToken = sharedDefaults.string(
            forKey: SharedDefaultsKeys.keyboardDiagnosticsSessionOwnerToken
        )
        guard storedToken != token else {
            return
        }
        sharedDefaults.set(token, forKey: SharedDefaultsKeys.keyboardDiagnosticsSessionOwnerToken)
        didApplyInactiveSessionMitigation = false
        appendKeyboardDiagnosticsLog(
            "表示インスタンスがオーナー権を取得 previousOwner=\(storedToken ?? "none") currentOwner=\(token)"
        )
    }

    // オーナー権を手放す(未表示のまま解放されるインスタンス用)。保持したままだと
    // 表示中のインスタンスが抑止分岐に落ち続ける。
    func releaseKeyboardSessionOwnershipIfHeld() {
        guard let sharedDefaults else {
            return
        }
        let token = diagnosticsSessionOwnerToken()
        guard sharedDefaults.string(
            forKey: SharedDefaultsKeys.keyboardDiagnosticsSessionOwnerToken
        ) == token else {
            return
        }
        sharedDefaults.removeObject(forKey: SharedDefaultsKeys.keyboardDiagnosticsSessionOwnerToken)
    }

    // 表示に至らなかったインスタンスの保持物を解放する(2532)。
    // iOS が取り付けなかった VC は自分がセッションのオーナーだと思っているため、
    // 非アクティブ降格経路(shouldSuppressHeavyOperations)の trim が発動せず、
    // hostingController(SwiftUIビュー階層)と Darwin observer を抱えたまま滞留する
    // (2531実測: 未表示のまま683秒/655秒生存、同時4インスタンスでメモリ警告5回・
    // フェイルセーフcritical昇格2回・LMキャッシュ縮小に至っていた)。
    // 後から iOS が同じ VC を表示する可能性は残るため、破棄ではなく解放に留める
    // (viewWillAppear が observer を再登録し、hostingController は setupKeyboardView が再生成)。
    func releaseNeverDisplayedKeyboardResources(reason: String) {
        guard viewIfLoaded?.window == nil else {
            return
        }

        releaseKeyboardSessionOwnershipIfHeld()
        performHiddenKeyboardMemoryTrim(
            reason: "neverDisplayed-\(reason)",
            releaseHostingView: true,
            includeSystemCaches: true
        )
        stopObservingSettingsDidChange()
        stopMarkedTextWatchdog()

        appendKeyboardDiagnosticsLog(
            "表示未到達インスタンスの保持物を解放 reason=\(reason) \(instanceAnchorSummary())",
            critical: true
        )
    }

    // 重大イベント(メモリ警告/最終手段アンロード/フェイルセーフ遷移)の保護ログ追記。
    // 通常ログの320行ローテーションと install 変更リセットの対象外に別キーで残す
    // (2026-07: 辞書永久停止事件の証拠行がローテで流れて検証不能だった対策)。
    // 発生はまれなので都度デコード/エンコードでよい。
    static let diagnosticsCriticalLogMaxLineCount = 60
    func appendKeyboardDiagnosticsCriticalLog(_ entry: String, to defaults: UserDefaults) {
        // 開発ビルド専用(appendKeyboardDiagnosticsLog と同方針)
        #if !DEBUG
        return
        #endif
        var lines = diagnosticsLogLines(
            from: defaults,
            key: SharedDefaultsKeys.keyboardDiagnosticsCriticalLogLines
        )
        lines.append(entry)
        if lines.count > Self.diagnosticsCriticalLogMaxLineCount {
            lines.removeFirst(lines.count - Self.diagnosticsCriticalLogMaxLineCount)
        }
        saveDiagnosticsLogLines(
            lines,
            to: defaults,
            key: SharedDefaultsKeys.keyboardDiagnosticsCriticalLogLines
        )
    }

    // メモリ内バッファの永続化スロットル。クラッシュ時に失われ得るのは最大この秒数分だが、
    // メモリ警告等の重要イベント(forceRecord/appendLog)は即時永続化される。
    static let diagnosticsBufferPersistIntervalSec: TimeInterval = 2

    func flightRecorderEvents(from defaults: UserDefaults) -> [DiagnosticsFlightRecorderEvent] {
        guard
            let data = defaults.data(forKey: SharedDefaultsKeys.keyboardDiagnosticsFlightRecorderEvents),
            let decoded = try? JSONDecoder().decode([DiagnosticsFlightRecorderEvent].self, from: data)
        else {
            return []
        }

        return decoded
    }

    func saveFlightRecorderEvents(_ events: [DiagnosticsFlightRecorderEvent], to defaults: UserDefaults) {
        if let encoded = try? JSONEncoder().encode(events) {
            defaults.set(encoded, forKey: SharedDefaultsKeys.keyboardDiagnosticsFlightRecorderEvents)
            return
        }

        defaults.removeObject(forKey: SharedDefaultsKeys.keyboardDiagnosticsFlightRecorderEvents)
    }

    func trimmedFlightRecorderEvents(
        _ events: [DiagnosticsFlightRecorderEvent],
        anchorTimestamp: TimeInterval
    ) -> [DiagnosticsFlightRecorderEvent] {
        let minimumTimestamp = anchorTimestamp - Self.diagnosticsFlightRecorderWindowSec
        var filtered = events.filter { $0.timestamp >= minimumTimestamp }

        if filtered.count > Self.diagnosticsFlightRecorderMaxEventCount {
            filtered.removeFirst(filtered.count - Self.diagnosticsFlightRecorderMaxEventCount)
        }

        return filtered
    }

    func clearFlightRecorderEvents(in defaults: UserDefaults) {
        defaults.removeObject(forKey: SharedDefaultsKeys.keyboardDiagnosticsFlightRecorderEvents)
        diagnosticsState.diagnosticsFlightRecorderLastObservedAt.removeAll(keepingCapacity: true)
        diagnosticsState.diagnosticsFlightRecorderBuffer = nil
    }

    func observeKeyboardDiagnosticsEvent(
        _ event: String,
        file: String = #fileID,
        line: Int = #line,
        function: String = #function,
        forceRecord: Bool = false
    ) {
        guard let sharedDefaults else {
            return
        }

        let now = Date().timeIntervalSince1970
        let sourceFile = (file as NSString).lastPathComponent
        let source = "\(sourceFile):\(line) \(function)"
        let dedupeKey = "\(event)|\(source)"

        if !forceRecord,
            let previous = diagnosticsState.diagnosticsFlightRecorderLastObservedAt[dedupeKey],
            now - previous < Self.diagnosticsFlightRecorderMinRecordIntervalSec {
            return
        }

        var events = diagnosticsState.diagnosticsFlightRecorderBuffer ?? flightRecorderEvents(from: sharedDefaults)
        events.append(
            DiagnosticsFlightRecorderEvent(
                timestamp: now,
                event: event,
                source: source
            )
        )

        let anchorTimestamp = events.last?.timestamp ?? now
        events = trimmedFlightRecorderEvents(events, anchorTimestamp: anchorTimestamp)
        diagnosticsState.diagnosticsFlightRecorderBuffer = events
        diagnosticsState.diagnosticsFlightRecorderLastObservedAt[dedupeKey] = now
        // 毎打鍵の JSON エンコード+defaults 書き込みを避け、スロットル付きで永続化する。
        // forceRecord(メモリ警告等)は即時。クラッシュ時の欠損は最大2秒分。
        if forceRecord || now - diagnosticsState.diagnosticsFlightRecorderLastPersistedAt >= Self.diagnosticsBufferPersistIntervalSec {
            saveFlightRecorderEvents(events, to: sharedDefaults)
            diagnosticsState.diagnosticsFlightRecorderLastPersistedAt = now
        }
    }

    // メモリ内バッファを defaults へ確定させる(終了・警告・バックグラウンド遷移時)。
    func persistBufferedKeyboardDiagnostics() {
        guard let sharedDefaults else {
            return
        }
        if let buffer = diagnosticsState.diagnosticsFlightRecorderBuffer {
            saveFlightRecorderEvents(buffer, to: sharedDefaults)
            diagnosticsState.diagnosticsFlightRecorderLastPersistedAt = Date().timeIntervalSince1970
        }
    }

    func flushFlightRecorderEventsIfPresent(reason: String) {
        guard let sharedDefaults else {
            return
        }

        let events = flightRecorderEvents(from: sharedDefaults)
        guard !events.isEmpty else {
            return
        }

        let anchorTimestamp = events.last?.timestamp ?? Date().timeIntervalSince1970
        let trimmed = trimmedFlightRecorderEvents(events, anchorTimestamp: anchorTimestamp)

        appendKeyboardDiagnosticsLog(
            "終了直前の高頻度イベントを退避 count=\(trimmed.count) windowSec=\(Int(Self.diagnosticsFlightRecorderWindowSec)) reason=\(reason)",
            file: #fileID,
            line: #line,
            function: #function
        )

        for item in trimmed {
            let timestampText = Self.diagnosticsTimestampFormatter.string(
                from: Date(timeIntervalSince1970: item.timestamp)
            )
            appendKeyboardDiagnosticsLog(
                "直前イベント \(timestampText) \(item.event) @ \(item.source)",
                file: #fileID,
                line: #line,
                function: #function
            )
        }

        clearFlightRecorderEvents(in: sharedDefaults)
    }

    func keyboardDiagnosticsCurrentInstallMarker() -> String {
        let bundle = Bundle.main
        let bundleID = bundle.bundleIdentifier ?? "unknown.keyboard.bundle"
        let buildNumber = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "?"
        return "\(bundleID)|\(buildNumber)|build"
    }

    func clearKeyboardDiagnosticsStorage(
        in defaults: UserDefaults,
        preservingInstallMarker installMarker: String
    ) {
        defaults.removeObject(forKey: SharedDefaultsKeys.keyboardDiagnosticsLogLines)
        defaults.removeObject(forKey: SharedDefaultsKeys.keyboardDiagnosticsFlightRecorderEvents)
        // criticalLogLines は意図的に消さない(install 変更をまたいで重大イベントの
        // 証拠を残す。明示クリアはコンテナアプリの診断クリア操作から行う)
        diagnosticsState.diagnosticsLogLinesBuffer = nil
        diagnosticsState.diagnosticsFlightRecorderBuffer = nil
        defaults.removeObject(forKey: SharedDefaultsKeys.keyboardDiagnosticsSessionActive)
        defaults.removeObject(forKey: SharedDefaultsKeys.keyboardDiagnosticsSessionOwnerToken)
        defaults.removeObject(forKey: SharedDefaultsKeys.keyboardDiagnosticsLastHeartbeat)
        defaults.removeObject(forKey: SharedDefaultsKeys.keyboardDiagnosticsLastEvent)
        defaults.removeObject(forKey: SharedDefaultsKeys.keyboardDiagnosticsLastSessionID)
        defaults.removeObject(forKey: SharedDefaultsKeys.keyboardDiagnosticsFailSafeProfile)
        defaults.set(installMarker, forKey: SharedDefaultsKeys.keyboardDiagnosticsInstallMarker)
    }

    func resetKeyboardDiagnosticsIfInstallChanged() {
        guard let sharedDefaults else {
            return
        }

        let currentMarker = keyboardDiagnosticsCurrentInstallMarker()
        let previousMarker = sharedDefaults.string(forKey: SharedDefaultsKeys.keyboardDiagnosticsInstallMarker)

        guard previousMarker != currentMarker else {
            return
        }

        clearKeyboardDiagnosticsStorage(
            in: sharedDefaults,
            preservingInstallMarker: currentMarker
        )

        let previousMarkerDescription = previousMarker ?? "none"
        appendKeyboardDiagnosticsLog(
            "診断ログをインストール単位で初期化 previous=\(previousMarkerDescription) current=\(currentMarker)",
            file: #fileID,
            line: #line,
            function: #function
        )
    }

    // ---- 落ちても残る診断(ファイル・フライトレコーダ) ----
    // jetsam 死の直前は cfprefsd(UserDefaults)への書き込みが失われることがあり、
    // 「診断が何も残らない」事態になる(iPhone 16 Pro の赤キー落ち事件)。
    // App Group コンテナ内のファイルへ同期追記して確実に残す。
    static let diagnosticsFlightFileName = "keyboard_diagnostics_flight.log"
    private static let diagnosticsFlightFileMaxBytes: UInt64 = 262_144
    private static let diagnosticsFlightFileKeepBytes = 131_072
    private static var diagnosticsFlightFileLastHeartbeatWriteAt: CFAbsoluteTime = 0

    func diagnosticsFlightFileURL() -> URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedDefaultsKeys.appGroupID
        )?.appendingPathComponent(Self.diagnosticsFlightFileName)
    }

    func appendKeyboardDiagnosticsFlightFileLine(_ line: String) {
        // 開発ビルド専用(appendKeyboardDiagnosticsLog と同方針)
        #if !DEBUG
        return
        #endif
        guard let url = diagnosticsFlightFileURL() else {
            return
        }

        let data = Data((line + "\n").utf8)
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: url.path) {
            try? data.write(to: url, options: [.atomic])
            return
        }

        guard let handle = try? FileHandle(forWritingTo: url) else {
            return
        }

        let endOffset = (try? handle.seekToEnd()) ?? 0
        try? handle.write(contentsOf: data)
        try? handle.close()

        if endOffset > Self.diagnosticsFlightFileMaxBytes {
            trimDiagnosticsFlightFile(at: url)
        }
    }

    private func trimDiagnosticsFlightFile(at url: URL) {
        guard let contents = try? Data(contentsOf: url),
            contents.count > Self.diagnosticsFlightFileKeepBytes else {
            return
        }

        var tail = contents.suffix(Self.diagnosticsFlightFileKeepBytes)

        // 行の途中で切れないよう、最初の改行までを捨てる。
        if let newlineIndex = tail.firstIndex(of: 0x0A) {
            tail = tail[tail.index(after: newlineIndex)...]
        }

        try? Data(tail).write(to: url, options: [.atomic])
    }

    // appendLog なしの高頻度ハートビート(textDidChange 等)向けの節流付きファイルミラー。
    func mirrorKeyboardDiagnosticsHeartbeatToFlightFile(_ summary: String) {
        let now = CFAbsoluteTimeGetCurrent()

        guard now - Self.diagnosticsFlightFileLastHeartbeatWriteAt >= 5 else {
            return
        }

        Self.diagnosticsFlightFileLastHeartbeatWriteAt = now
        let timestamp = Self.diagnosticsTimestampFormatter.string(from: Date())
        appendKeyboardDiagnosticsFlightFileLine("\(timestamp) [\(diagnosticsState.diagnosticsSessionID)] HB \(summary)")
    }

    // App Group への書き込み健全性を起動時に1回記録する(コンテナURL到達性と
    // defaults の書き戻し確認)。書けない環境では診断が空になるため、その事実自体を残す。
    func recordKeyboardDiagnosticsAppGroupHealth() {
        let containerReachable = diagnosticsFlightFileURL() != nil
        var defaultsRoundTrip = "nil"

        if let sharedDefaults {
            let probeKey = "keyboardDiagnosticsWriteProbe"
            let probeValue = "\(diagnosticsState.diagnosticsSessionID)-\(Int(Date().timeIntervalSince1970))"
            sharedDefaults.set(probeValue, forKey: probeKey)
            defaultsRoundTrip = sharedDefaults.string(forKey: probeKey) == probeValue ? "ok" : "mismatch"
        }

        appendKeyboardDiagnosticsLog(
            "AppGroup健全性 group=\(SharedDefaultsKeys.appGroupID) containerURL=\(containerReachable ? "ok" : "nil") defaults=\(defaultsRoundTrip)"
        )
    }

    // ---- 押下表示残留(赤キー)の証拠収集 ----
    func recordStuckTouchForceClear(_ detail: String) {
        diagnosticsState.stuckTouchForceClearCount += 1
        appendKeyboardDiagnosticsLog(
            "押下残留をwatchdogが強制解除 \(detail) 累計=\(diagnosticsState.stuckTouchForceClearCount)"
        )
    }

    func appendKeyboardDiagnosticsLog(
        _ event: String,
        critical: Bool = false,
        file: String = #fileID,
        line: Int = #line,
        function: String = #function
    ) {
        // 診断ログは開発ビルド専用(App Store ガイドライン4.4.2: キーボードの
        // 入力周辺情報を保存しない)。リリースでは一切書き込まない。
        #if !DEBUG
        return
        #endif
        let sourceFile = (file as NSString).lastPathComponent
        let timestamp = Self.diagnosticsTimestampFormatter.string(from: Date())
        let entry =
            "\(timestamp) [\(diagnosticsState.diagnosticsSessionID)] \(event) {\(diagnosticsRuntimeContext())} (\(sourceFile):\(line) \(function))"

        // defaults が使えない環境でもファイル側には必ず残す。
        appendKeyboardDiagnosticsFlightFileLine(entry)

        guard let sharedDefaults else {
            return
        }

        // 320行の JSON デコードを毎回やり直さない(メモリ内バッファ)。保存自体は
        // まれなイベントかつクラッシュ保全のため即時のまま。
        var lines = diagnosticsState.diagnosticsLogLinesBuffer ?? diagnosticsLogLines(from: sharedDefaults)
        lines.append(entry)

        let maxLineCount = 320
        if lines.count > maxLineCount {
            lines.removeFirst(lines.count - maxLineCount)
        }

        diagnosticsState.diagnosticsLogLinesBuffer = lines
        saveDiagnosticsLogLines(lines, to: sharedDefaults)
        if critical {
            appendKeyboardDiagnosticsCriticalLog(entry, to: sharedDefaults)
        }
        sharedDefaults.set(entry, forKey: SharedDefaultsKeys.keyboardDiagnosticsLastEvent)
        sharedDefaults.set(Date().timeIntervalSince1970, forKey: SharedDefaultsKeys.keyboardDiagnosticsLastHeartbeat)
        sharedDefaults.set(diagnosticsState.diagnosticsSessionID, forKey: SharedDefaultsKeys.keyboardDiagnosticsLastSessionID)
    }

    func updateKeyboardDiagnosticsHeartbeat(
        event: String,
        file: String = #fileID,
        line: Int = #line,
        function: String = #function,
        appendLog: Bool = false,
        criticalLog: Bool = false
    ) {
        guard let sharedDefaults else {
            return
        }

        observeKeyboardDiagnosticsEvent(event, file: file, line: line, function: function)
        persistKeyboardDiagnosticsFailSafeProfile(in: sharedDefaults)

        // ここから先はログ書き込み(開発ビルド専用)。failSafe の永続化は機能なので残す。
        #if !DEBUG
        return
        #endif
        let sourceFile = (file as NSString).lastPathComponent
        let summary = "\(event) [\(diagnosticsRuntimeContext())] @ \(sourceFile):\(line) \(function)"

        // ハートビートのスカラー書き込みもスロットル(粒度2秒で生存確認には十分)。
        // appendLog 付き(メモリ警告/ライフサイクル等の重要イベント)は即時。
        let now = Date().timeIntervalSince1970
        if appendLog || now - diagnosticsState.diagnosticsHeartbeatLastPersistedAt >= Self.diagnosticsBufferPersistIntervalSec {
            sharedDefaults.set(now, forKey: SharedDefaultsKeys.keyboardDiagnosticsLastHeartbeat)
            sharedDefaults.set(summary, forKey: SharedDefaultsKeys.keyboardDiagnosticsLastEvent)
            sharedDefaults.set(diagnosticsState.diagnosticsSessionID, forKey: SharedDefaultsKeys.keyboardDiagnosticsLastSessionID)
            diagnosticsState.diagnosticsHeartbeatLastPersistedAt = now
        }

        if appendLog {
            appendKeyboardDiagnosticsLog(event, critical: criticalLog, file: file, line: line, function: function)
        } else {
            mirrorKeyboardDiagnosticsHeartbeatToFlightFile(summary)
        }
    }

    func startKeyboardDiagnosticsSession() {
        resetKeyboardDiagnosticsIfInstallChanged()

        guard let sharedDefaults else {
            return
        }

        diagnosticsState.diagnosticsFlightRecorderLastObservedAt.removeAll(keepingCapacity: true)

        let previousSessionWasActive = sharedDefaults.bool(
            forKey: SharedDefaultsKeys.keyboardDiagnosticsSessionActive
        )
        let previousOwnerToken = sharedDefaults.string(
            forKey: SharedDefaultsKeys.keyboardDiagnosticsSessionOwnerToken
        ) ?? "unknown"

        if previousSessionWasActive {
            let previousSessionID = sharedDefaults.string(
                forKey: SharedDefaultsKeys.keyboardDiagnosticsLastSessionID
            ) ?? "unknown"
            let previousEvent = sharedDefaults.string(
                forKey: SharedDefaultsKeys.keyboardDiagnosticsLastEvent
            ) ?? "unknown"
            let previousHeartbeat = sharedDefaults.double(
                forKey: SharedDefaultsKeys.keyboardDiagnosticsLastHeartbeat
            )
            let elapsed: String = {
                guard previousHeartbeat > 0 else {
                    return "unknown"
                }

                let delta = max(0, Date().timeIntervalSince(Date(timeIntervalSince1970: previousHeartbeat)))
                return String(format: "%.1f", delta)
            }()

            let activeOwnerPrefix = "\(diagnosticsProcessID()):"
            let looksLikeControllerOverlap = previousOwnerToken.hasPrefix(activeOwnerPrefix)
                && previousOwnerToken != diagnosticsSessionOwnerToken()
            let reason = looksLikeControllerOverlap
                ? "前回セッション継続中の可能性(多重生存)"
                : "前回セッションが非正常終了の可能性"

            appendKeyboardDiagnosticsLog(
                "\(reason) session=\(previousSessionID) owner=\(previousOwnerToken) lastEvent=\(previousEvent) elapsedSec=\(elapsed)",
                file: #fileID,
                line: #line,
                function: #function
            )
            flushFlightRecorderEventsIfPresent(reason: reason)
        } else {
            clearFlightRecorderEvents(in: sharedDefaults)
        }

        diagnosticsState.diagnosticsSessionID = UUID().uuidString
        diagnosticsState.diagnosticsSessionStartedAt = Date()
        sharedDefaults.set(true, forKey: SharedDefaultsKeys.keyboardDiagnosticsSessionActive)
        // オーナー権(=重い処理を担う権利)はここでは主張しない。viewDidLoad 時点で主張すると
        // 「最後にロードされたインスタンス」がオーナーになり、iOS が表示中キーボードの後に
        // 投機生成した未表示VCがオーナー権を奪ってしまう。奪われた表示中インスタンスは
        // textDidChange/viewWillAppear で抑止分岐に落ち、observer 解除・bootstrap 取消まで
        // 受けるため、固まる/空白になる。オーナー権は viewWillAppear で主張する(2532)。
        sharedDefaults.set(diagnosticsState.diagnosticsSessionID, forKey: SharedDefaultsKeys.keyboardDiagnosticsLastSessionID)
        persistKeyboardDiagnosticsFailSafeProfile(in: sharedDefaults)
        appendKeyboardDiagnosticsLog(
            "キーボード拡張セッション開始",
            file: #fileID,
            line: #line,
            function: #function
        )
        // footprint 高止まり調査(2541): 誕生→50MB級への登り区間が320行ローテで消えて
        // 観測できなかったため、セッション開始ごとに malloc ヒープと自前キャッシュ件数を
        // 1行記録する(どのセッションで何が積んだかの標本化)。
        do {
            var stats = malloc_statistics_t()
            malloc_zone_statistics(nil, &stats)
            let usedMB = Double(stats.size_in_use) / 1_048_576
            appendKeyboardDiagnosticsLog(
                "メモリ内訳census mallocUsedMB=\(String(format: "%.1f", usedMB))"
                    + " \(kanaKanjiConverter.diagnosticsCacheCountsSummary())",
                file: #fileID,
                line: #line,
                function: #function
            )
        }
    }

    func finishKeyboardDiagnosticsSession(
        reason: String,
        file: String = #fileID,
        line: Int = #line,
        function: String = #function
    ) {
        guard let sharedDefaults else {
            return
        }

        let elapsedSec = max(0, Date().timeIntervalSince(diagnosticsState.diagnosticsSessionStartedAt))

        appendKeyboardDiagnosticsLog(
            "キーボード拡張セッション終了 reason=\(reason) elapsedSec=\(String(format: "%.1f", elapsedSec))",
            file: file,
            line: line,
            function: function
        )

        let currentOwnerToken = diagnosticsSessionOwnerToken()
        let storedOwnerToken = sharedDefaults.string(
            forKey: SharedDefaultsKeys.keyboardDiagnosticsSessionOwnerToken
        )

        if storedOwnerToken == nil || storedOwnerToken == currentOwnerToken {
            sharedDefaults.set(false, forKey: SharedDefaultsKeys.keyboardDiagnosticsSessionActive)
            sharedDefaults.removeObject(forKey: SharedDefaultsKeys.keyboardDiagnosticsSessionOwnerToken)
            sharedDefaults.set(
                Date().timeIntervalSince1970,
                forKey: SharedDefaultsKeys.keyboardDiagnosticsLastHeartbeat
            )
            clearFlightRecorderEvents(in: sharedDefaults)
        } else {
            appendKeyboardDiagnosticsLog(
                "終了時owner不一致のためactive更新を見送り currentOwner=\(currentOwnerToken) storedOwner=\(storedOwnerToken ?? "none")",
                file: file,
                line: line,
                function: function
            )
        }
    }

    func appendKeyboardDiagnosticsLogFromInputHandling(_ event: String) {
        appendKeyboardDiagnosticsLog(event)
    }

    func performanceElapsedMilliseconds(since startedAt: CFAbsoluteTime) -> Int {
        max(0, Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000))
    }
}
