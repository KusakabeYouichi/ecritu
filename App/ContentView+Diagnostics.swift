import SwiftUI
import UIKit
import CoreFoundation
import Darwin
import Contacts

extension ContentView {
    func clearLegacyKeyboardDebugLogKeysIfNeeded() {
        guard let defaults = Self.sharedDefaults,
            !defaults.bool(forKey: SettingsKeys.legacyKeyboardDebugLogCleanupCompleted) else {
            return
        }

        let legacyKeys = [
            "keyboardLayoutDebugLines",
            "keyboardLayoutDebugHeartbeat",
            "keyboardLayoutDebugReporterBundleID",
            "keyboardLayoutDebugReporterAppGroupID",
            "keyboardLayoutDebugLastEvent",
            "keyboardInputProbeCount",
            "keyboardInputProbeHeartbeat",
            "keyboardInputProbeLastEvent",
            "keyboardInputProbeLastText"
        ]

        for key in legacyKeys {
            defaults.removeObject(forKey: key)
        }

        defaults.set(true, forKey: SettingsKeys.legacyKeyboardDebugLogCleanupCompleted)
    }

    func keyboardExtensionBundleForDiagnostics() -> Bundle? {
        guard let pluginsURL = Bundle.main.builtInPlugInsURL,
            let pluginURLs = try? FileManager.default.contentsOfDirectory(
                at: pluginsURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
            return nil
        }

        for pluginURL in pluginURLs where pluginURL.pathExtension == "appex" {
            guard let bundle = Bundle(url: pluginURL),
                let bundleID = bundle.bundleIdentifier else {
                continue
            }

            if bundleID.hasSuffix(".keyboard") {
                return bundle
            }
        }

        guard let firstPluginURL = pluginURLs.first(where: { $0.pathExtension == "appex" }) else {
            return nil
        }

        return Bundle(url: firstPluginURL)
    }

    func keyboardDiagnosticsInstallMarkerForCurrentBuild() -> String {
        let bundle = keyboardExtensionBundleForDiagnostics() ?? Bundle.main
        let bundleID = bundle.bundleIdentifier ?? "unknown.keyboard.bundle"
        let buildNumber = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "?"
        return "\(bundleID)|\(buildNumber)|build"
    }

    func clearKeyboardDiagnosticsIfInstallChanged() {
        guard let defaults = Self.sharedDefaults else {
            return
        }

        let currentMarker = keyboardDiagnosticsInstallMarkerForCurrentBuild()
        let savedMarker = defaults.string(forKey: SettingsKeys.keyboardDiagnosticsInstallMarker)

        if savedMarker != currentMarker {
            // criticalLogLines は消さない(installをまたいで重大イベントの証拠を残す)
            defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsLogLines)
            defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsFlightRecorderEvents)
            defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsSessionActive)
            defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsSessionOwnerToken)
            defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsLastHeartbeat)
            defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsLastEvent)
            defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsLastSessionID)
            defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsFailSafeProfile)
            defaults.set(currentMarker, forKey: SettingsKeys.keyboardDiagnosticsInstallMarker)
        }

        keyboardDiagnosticsInstallMarker = currentMarker
    }

    // 設定>一般>キーボード の登録状態を毎回記録する。
    // 「écritu 以外のキーボードが出る」事象には3種類あり、うち2つは拡張側にログが残らない。
    // ①attach失敗=viewDidLoadは走るので未到達としてcriticalに残る。②署名失効=拡張が起動不可。
    // ③iOSが登録一覧から外す=痕跡なし。実測(2026-08-13)では地球儀キーすら出ておらず、
    // iOSが「有効キーボードは1つだけ」と認識していた=écritu が一覧から外れていた。
    // Personal Team のプロファイルは7日で失効し、失効すると登録が外れるため③が起きる。
    // 事後に設定を見ても手遅れなので、アプリ起動ごとに登録の有無を残す。
    static let keyboardRegistrationHistoryLimit = 24

    func keyboardExtensionBundleIdentifierForDiagnostics() -> String {
        if let identifier = keyboardExtensionBundleForDiagnostics()?.bundleIdentifier {
            return identifier
        }
        let base = Bundle.main.bundleIdentifier ?? "unknown"
        return "\(base).keyboard"
    }

    func isKeyboardExtensionRegistered() -> Bool? {
        // AppleKeyboards はアプリ自身の defaults ドメインに現れる有効キーボード一覧。
        // 非公開キーだが読み取りのみで、取得できない場合は nil(判定不能)を返す。
        guard let enabled = UserDefaults.standard.object(forKey: "AppleKeyboards") as? [String] else {
            return nil
        }
        let identifier = keyboardExtensionBundleIdentifierForDiagnostics()
        return enabled.contains { $0 == identifier || $0.hasPrefix("\(identifier).") }
    }

    func recordKeyboardExtensionRegistrationState() {
        guard let defaults = Self.sharedDefaults else {
            return
        }

        let state: String
        switch isKeyboardExtensionRegistered() {
        case .some(true): state = "registered"
        case .some(false): state = "MISSING"
        case .none: state = "unknown"
        }

        var history = decodeStringArray(
            forKey: SettingsKeys.keyboardDiagnosticsRegistrationHistory,
            defaults: defaults
        )
        // 状態が変わったときだけ積む(毎起動で埋まって履歴が流れるのを防ぐ)。
        if let last = history.last, last.hasSuffix(" \(state)") {
            return
        }
        let stamp = ISO8601DateFormatter().string(from: Date())
        history.append("\(stamp) \(state)")
        if history.count > Self.keyboardRegistrationHistoryLimit {
            history.removeFirst(history.count - Self.keyboardRegistrationHistoryLimit)
        }
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: SettingsKeys.keyboardDiagnosticsRegistrationHistory)
        }
    }

    func loadKeyboardDiagnosticsState() {
        guard let defaults = Self.sharedDefaults else {
            keyboardDiagnosticsLogLines = []
            keyboardDiagnosticsCriticalLogLines = []
            keyboardDiagnosticsInstallMarker = ""
            keyboardDiagnosticsSessionActive = false
            keyboardDiagnosticsLastHeartbeatDate = nil
            keyboardDiagnosticsLastEvent = ""
            keyboardDiagnosticsLastSessionID = ""
            keyboardDiagnosticsFailSafeProfile = "normal"
            keyboardDiagnosticsLaunchCount = 0
            keyboardDiagnosticsAttachFailureCount = 0
            keyboardConversionLastTrace = ""
            return
        }

        keyboardDiagnosticsLogLines = decodeStringArray(
            forKey: SettingsKeys.keyboardDiagnosticsLogLines,
            defaults: defaults
        )
        keyboardDiagnosticsCriticalLogLines = decodeStringArray(
            forKey: SettingsKeys.keyboardDiagnosticsCriticalLogLines,
            defaults: defaults
        )
        keyboardDiagnosticsInstallMarker = defaults.string(
            forKey: SettingsKeys.keyboardDiagnosticsInstallMarker
        ) ?? ""
        keyboardDiagnosticsSessionActive = defaults.bool(
            forKey: SettingsKeys.keyboardDiagnosticsSessionActive
        )

        let heartbeatRawValue = defaults.double(forKey: SettingsKeys.keyboardDiagnosticsLastHeartbeat)
        keyboardDiagnosticsLastHeartbeatDate = heartbeatRawValue > 0
            ? Date(timeIntervalSince1970: heartbeatRawValue)
            : nil

        keyboardDiagnosticsLastEvent = defaults.string(
            forKey: SettingsKeys.keyboardDiagnosticsLastEvent
        ) ?? ""
        keyboardDiagnosticsLastSessionID = defaults.string(
            forKey: SettingsKeys.keyboardDiagnosticsLastSessionID
        ) ?? ""
        keyboardConversionLastTrace = defaults.string(
            forKey: SettingsKeys.keyboardConversionLastTrace
        ) ?? ""

        let failSafeRawValue = defaults.string(
            forKey: SettingsKeys.keyboardDiagnosticsFailSafeProfile
        ) ?? "normal"
        keyboardDiagnosticsFailSafeProfile = normalizedKeyboardDiagnosticsFailSafeProfile(
            failSafeRawValue
        )
        keyboardDiagnosticsLaunchCount = defaults.integer(
            forKey: SettingsKeys.keyboardDiagnosticsLaunchCount
        )
        keyboardDiagnosticsAttachFailureCount = defaults.integer(
            forKey: SettingsKeys.keyboardDiagnosticsAttachFailureCount
        )
        keyboardDiagnosticsAttachLateRecoveryCount = defaults.integer(
            forKey: SettingsKeys.keyboardDiagnosticsAttachLateRecoveryCount
        )
    }

    func clearKeyboardDiagnosticsState() {
        guard let defaults = Self.sharedDefaults else {
            return
        }

        defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsLogLines)
        defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsCriticalLogLines)
        defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsFlightRecorderEvents)
        defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsSessionActive)
        defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsSessionOwnerToken)
        defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsLastHeartbeat)
        defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsLastEvent)
        defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsLastSessionID)
        defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsFailSafeProfile)
        defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsLaunchCount)
        defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsAttachFailureCount)

        if let flightFileURL = keyboardDiagnosticsFlightFileURL() {
            try? FileManager.default.removeItem(at: flightFileURL)
        }

        loadKeyboardDiagnosticsState()
    }

    func normalizedKeyboardDiagnosticsFailSafeProfile(_ rawValue: String) -> String {
        switch rawValue {
        case "normal", "elevated", "critical":
            return rawValue
        default:
            return "normal"
        }
    }

    func keyboardDiagnosticsLastHeartbeatText() -> String {
        guard let keyboardDiagnosticsLastHeartbeatDate else {
            return "記録なし"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: keyboardDiagnosticsLastHeartbeatDate)
    }

    // キーボード拡張が書く「落ちても残る」フライトレコーダファイル。
    // ファイル名は KeyboardViewController+Diagnostics.swift 側の定義と一致させること。
    static let keyboardDiagnosticsFlightFileName = "keyboard_diagnostics_flight.log"

    // 診断ログは開発ビルド専用(#if !DEBUG で早期 return)なので、ログが空のときに
    // 「Release だから出ていない」のか「Debug なのに出ていない=異常」のかを区別できる
    // ようにビルド構成を明示する。⌘R しただけでは構成が分からないという指摘への対応(2564)
    static var buildConfigurationLabel: String {
        #if DEBUG
        return "Debug(診断ログ有効)"
        #else
        return "Release(診断ログ無効)"
        #endif
    }

    func keyboardDiagnosticsFlightFileURL() -> URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SettingsKeys.appGroupID
        )?.appendingPathComponent(Self.keyboardDiagnosticsFlightFileName)
    }

    func keyboardDiagnosticsFlightFileTailLines(maxLines: Int = 200) -> [String] {
        guard let url = keyboardDiagnosticsFlightFileURL(),
            let data = try? Data(contentsOf: url),
            !data.isEmpty,
            let text = String(data: data, encoding: .utf8) else {
            return []
        }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        return lines.suffix(maxLines).map(String.init)
    }

    // コンパクトコピーで省く定型行(解決済み調査の常設ログ: メモリ解放/プリロード/
    // 補助語彙更新 等)。記録自体は従来どおり全部残す — 問題が起きてから採れない情報を
    // 失わないため、間引くのはエクスポート時のみ。全文は「詳細コピー」で取得できる。
    static func isRoutineKeyboardDiagnosticsLine(_ line: String) -> Bool {
        // ライフサイクルの定型(セッション開始/終了・viewDidLoad・viewWillAppear は
        // attach失敗調査に必要なので残す)
        if line.contains(" viewDidAppear {") || line.contains(" viewWillDisappear {")
            || line.contains(" viewDidDisappear {") {
            return true
        }
        // 非表示時の定型メモリ解放(failSafe が normal 以外の解放は異常系なので残す)
        if line.contains("キーボード非表示でメモリ解放"), line.contains("profile=normal") {
            return true
        }
        if line.contains("システム辞書プリロードを遅延予定")
            || line.contains("システム辞書プリロード開始")
            || line.contains("システム辞書プリロード完了")
            || line.contains("キーボード非表示のため辞書プリロード予約をキャンセル") {
            return true
        }
        // 補助語彙の定常更新(indexCache=miss は再構築=要調査なので残す)
        if line.contains("補助語彙を更新"), line.contains("indexCache=hit") {
            return true
        }
        if line.contains("共有データプリウォーム遅延") || line.contains("HB textDidChange") {
            return true
        }
        // refreshKeyboardState は恒常的に 28-45ms 出る。80ms 以上だけ異常として残す
        if line.contains("refreshKeyboardState遅延"),
            let range = line.range(of: #"elapsedMs=(\d+)"#, options: .regularExpression),
            let elapsedMs = Int(line[range].dropFirst("elapsedMs=".count)),
            elapsedMs < 80 {
            return true
        }
        return false
    }

    func keyboardDiagnosticsExportText(detail: Bool = false) -> String {
        var sections: [String] = []
        sections.append("installMarker: \(keyboardDiagnosticsInstallMarker)")
        sections.append("buildConfiguration: \(Self.buildConfigurationLabel)")
        sections.append("sessionActive: \(keyboardDiagnosticsSessionActive ? "true" : "false")")
        sections.append("failSafeProfile: \(keyboardDiagnosticsFailSafeProfile)")
        sections.append("lastHeartbeat: \(keyboardDiagnosticsLastHeartbeatText())")
        sections.append("lastSessionID: \(keyboardDiagnosticsLastSessionID)")
        sections.append("lastEvent: \(keyboardDiagnosticsLastEvent)")
        sections.append(
            "起動\(keyboardDiagnosticsLaunchCount)回 / 表示未到達(attach失敗の疑い)\(keyboardDiagnosticsAttachFailureCount)回"
                + " / 遅延復帰\(keyboardDiagnosticsAttachLateRecoveryCount)回"
        )
        let registrationState: String
        switch isKeyboardExtensionRegistered() {
        case .some(true): registrationState = "登録あり"
        case .some(false): registrationState = "登録なし(iOSの有効キーボード一覧に不在)"
        case .none: registrationState = "判定不能"
        }
        sections.append("キーボード登録: \(registrationState)")
        let registrationHistory = Self.sharedDefaults.map {
            decodeStringArray(forKey: SettingsKeys.keyboardDiagnosticsRegistrationHistory, defaults: $0)
        } ?? []
        sections.append("登録状態の履歴(変化時のみ): \(registrationHistory.isEmpty ? "(記録なし)" : registrationHistory.joined(separator: ", "))")
        sections.append("--- 最終変換トレース(デバッグ) ---")
        sections.append(keyboardConversionLastTrace.isEmpty ? "(記録なし)" : keyboardConversionLastTrace)
        sections.append("--- critical events (ローテ保護) ---")
        if keyboardDiagnosticsCriticalLogLines.isEmpty {
            sections.append("(記録なし)")
        } else {
            sections.append(contentsOf: keyboardDiagnosticsCriticalLogLines)
        }
        sections.append("--- 追加語彙のseed外エントリ(手動追加+過去播種の残骸) ---")
        sections.append(contentsOf: ajoutVocabularyNonSeedDiagnosticsLines())
        sections.append("--- logs ---")
        if detail {
            sections.append(contentsOf: keyboardDiagnosticsLogLines)
        } else {
            let filtered = keyboardDiagnosticsLogLines.filter { !Self.isRoutineKeyboardDiagnosticsLine($0) }
            sections.append(contentsOf: filtered)
            let omitted = keyboardDiagnosticsLogLines.count - filtered.count
            if omitted > 0 {
                sections.append("(定型行\(omitted)件を省略 — 全文は詳細コピー)")
            }
        }
        sections.append("--- flight file (crash-safe) ---")
        var flightLines = keyboardDiagnosticsFlightFileTailLines()
        if !detail {
            // logs と重複する行と定型行を除き、クラッシュ時にしか意味を持たない差分だけ残す
            let knownLines = Set(keyboardDiagnosticsLogLines)
            flightLines = flightLines.filter {
                !knownLines.contains($0) && !Self.isRoutineKeyboardDiagnosticsLine($0)
            }
        }
        if flightLines.isEmpty {
            sections.append(detail ? "(記録なし)" : "(logsとの差分なし)")
        } else {
            sections.append(contentsOf: flightLines)
        }
        return sections.joined(separator: "\n")
    }

    // 追加語彙のうち現行 seed(appex バンドルの InitialAjoutVocabMigration.json)に無い
    // (読み, 候補) ペアを列挙する。手動追加分と、播種の削除同期(2338)導入以前に
    // plist から撤回されて実機に残った残骸の切り分け用。
    func ajoutVocabularyNonSeedDiagnosticsLines() -> [String] {
        let current = loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiAjoutVocabulary)
        guard let bundle = keyboardExtensionBundleForDiagnostics(),
            let seedURL = bundle.url(forResource: "InitialAjoutVocabMigration", withExtension: "json"),
            let seedData = try? Data(contentsOf: seedURL),
            let decodedSeed = try? JSONDecoder().decode([String: [String]].self, from: seedData) else {
            return ["(seed JSON をバンドルから読めませんでした)"]
        }
        var seed: [String: Set<String>] = [:]
        for (reading, candidates) in decodedSeed {
            seed[reading] = Set(candidates)
        }
        var nonSeedLines: [String] = []
        var totalCount = 0
        for reading in current.keys.sorted() {
            for candidate in current[reading] ?? [] {
                totalCount += 1
                if !(seed[reading]?.contains(candidate) ?? false) {
                    nonSeedLines.append("\(reading) → \(candidate)")
                }
            }
        }
        var lines = ["総数 \(totalCount) 件 / seed \(totalCount - nonSeedLines.count) 件 / seed外 \(nonSeedLines.count) 件"]
        lines.append(contentsOf: nonSeedLines.isEmpty ? ["(seed外なし)"] : nonSeedLines)
        return lines
    }

    func copyKeyboardDiagnosticsToPasteboard(detail: Bool = false) {
#if os(iOS)
        // 表示用stateは最後のload時点のスナップショットで、その後に拡張が書いた
        // カウント/ログが反映されない(2528: 実カウント53/10に対し2.5h前の18/2を
        // エクスポートした事故)。コピーはflight fileと同時点の値を出すべきなので
        // 直前に必ず再読込する。
        loadKeyboardDiagnosticsState()
        UIPasteboard.general.string = keyboardDiagnosticsExportText(detail: detail)
#endif
    }

    func containerDiagnosticsProcessLabel() -> String {
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown.container.bundle"
        let processName = ProcessInfo.processInfo.processName
        return "\(bundleID)(\(processName))"
    }

    func containerCurrentResidentMemoryBytes() -> UInt64? {
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

    func containerResidentMemoryMBText() -> String {
        guard let bytes = containerCurrentResidentMemoryBytes() else {
            return "unknown"
        }

        let mb = Double(bytes) / 1_048_576
        return String(format: "%.1f", mb)
    }

    func appendContainerDiagnosticsLog(
        _ event: String,
        file: String = #fileID,
        line: Int = #line,
        function: String = #function
    ) {
        guard let defaults = Self.sharedDefaults else {
            return
        }

        let sourceFile = (file as NSString).lastPathComponent
        let timestamp = Self.diagnosticsTimestampFormatter.string(from: Date())
        let context =
            "process=\(containerDiagnosticsProcessLabel()) rssMB=\(containerResidentMemoryMBText())"
        let entry =
            "\(timestamp) [container:\(containerDiagnosticsSessionID)] \(event) {\(context)} (\(sourceFile):\(line) \(function))"

        var lines = decodeStringArray(
            forKey: SettingsKeys.keyboardDiagnosticsLogLines,
            defaults: defaults
        )
        lines.append(entry)

        let maxLineCount = 320
        if lines.count > maxLineCount {
            lines.removeFirst(lines.count - maxLineCount)
        }

        saveStringArray(lines, forKey: SettingsKeys.keyboardDiagnosticsLogLines, defaults: defaults)
    }

    func containerDiagnosticsElapsedMilliseconds(since start: CFAbsoluteTime) -> Int {
        max(0, Int((CFAbsoluteTimeGetCurrent() - start) * 1000))
    }

    // 設定カード群の末尾が画面に載った時点で1回だけ記録する(2587)。
    // didRenderInitialFrame を立ててからここまでが、カード群の構築+レイアウトの実コスト。
    func logSettingsCardsRenderedIfNeeded() {
        guard !didLogSettingsCardsRendered, settingsCardsBuildStartedAt > 0 else {
            return
        }

        didLogSettingsCardsRendered = true
        let buildMs = containerDiagnosticsElapsedMilliseconds(since: settingsCardsBuildStartedAt)
        let startOffset = max(0, containerBootstrapOffsetMilliseconds() - buildMs)
        recordBootstrapTimingPart("cardsAtMs=\(startOffset) cardsBuildMs=\(buildMs)")
        appendContainerDiagnosticsLog("設定カード群の描画完了 buildMs=\(buildMs)")
    }

    // 起動計測の断片を溜める。段の順序どおりに並ぶよう、計測した側から呼ぶ。
    func recordBootstrapTimingPart(_ part: String) {
        bootstrapTimingParts.append(part)
    }

    // 起動からの経過(ms)。所要時間だけでは事象の位置が分からないため併記する。
    func containerBootstrapOffsetMilliseconds() -> Int {
        guard containerBootstrapStartedAt > 0 else {
            return -1
        }

        return containerDiagnosticsElapsedMilliseconds(since: containerBootstrapStartedAt)
    }

    // 1起動を1行にまとめて専用キーへ残す。共有ログと違い拡張側の書き込みで流れないので、
    // 遅い回と速い回を後から比べられる(起動時間はばらつくため単発の計測では判断できない)。
    func flushBootstrapTimingHistory(totalMs: Int) {
        guard let defaults = Self.sharedDefaults else {
            return
        }

        let timestamp = Self.diagnosticsTimestampFormatter.string(from: Date())
        let entry = "\(timestamp) totalMs=\(totalMs) "
            + bootstrapTimingParts.joined(separator: " ")
            + " rssMB=\(containerResidentMemoryMBText())"
        bootstrapTimingParts = []

        var history = decodeStringArray(
            forKey: SettingsKeys.containerBootstrapTimingHistory,
            defaults: defaults
        )
        history.append(entry)

        let maxEntryCount = 40
        if history.count > maxEntryCount {
            history.removeFirst(history.count - maxEntryCount)
        }

        saveStringArray(
            history,
            forKey: SettingsKeys.containerBootstrapTimingHistory,
            defaults: defaults
        )
    }
}
