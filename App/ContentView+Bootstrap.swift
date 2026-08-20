import SwiftUI
import UIKit
import CoreFoundation
import Darwin
import Contacts

extension ContentView {
    static func editionDateText(from rawValue: String?) -> String? {
        guard let rawValue,
            rawValue.count >= 8 else {
            return nil
        }

        let yearPart = rawValue.prefix(4)
        let monthPart = rawValue.dropFirst(4).prefix(2)
        let dayPart = rawValue.dropFirst(6).prefix(2)

        guard let month = Int(monthPart),
            let day = Int(dayPart) else {
            return nil
        }

        return "\(yearPart)-\(month)-\(day)"
    }

    static func normalizedContactReading(_ text: String) -> String {
        var normalized = ""

        for character in text {
            let source = String(character).precomposedStringWithCanonicalMapping
            let converted = source.applyingTransform(.hiraganaToKatakana, reverse: true) ?? source

            guard converted.count == 1,
                let scalar = converted.unicodeScalars.first else {
                continue
            }

            let isHiragana = (0x3040...0x309F).contains(scalar.value)
            let isLongVowelMark = scalar.value == 0x30FC

            guard isHiragana || isLongVowelMark,
                let normalizedCharacter = converted.first else {
                continue
            }

            normalized.append(normalizedCharacter)
        }

        return normalized
    }

    static func contactNameCandidates(
        primaryName: String,
        fullName: String,
        includeFullName: Bool
    ) -> [String] {
        guard !primaryName.isEmpty else {
            return []
        }

        guard includeFullName,
            !fullName.isEmpty,
            fullName != primaryName else {
            return [primaryName]
        }

        return [primaryName, fullName]
    }

    static func appendContactCandidates(
        _ candidates: [String],
        forReadingText readingText: String,
        to dictionary: inout [String: [String]]
    ) {
        let normalizedReading = normalizedContactReading(readingText)

        guard !normalizedReading.isEmpty else {
            return
        }

        var existingCandidates = dictionary[normalizedReading] ?? []

        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmed.isEmpty,
                !existingCandidates.contains(trimmed) else {
                continue
            }

            existingCandidates.append(trimmed)
        }

        if !existingCandidates.isEmpty {
            dictionary[normalizedReading] = Array(existingCandidates.prefix(48))
        }
    }

    static func shouldUseOrganizationNameReadingFallback(_ organizationName: String) -> Bool {
        let source = organizationName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !source.isEmpty else {
            return false
        }

        var hasKana = false

        for scalar in source.precomposedStringWithCanonicalMapping.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                continue
            }

            if scalar.value == 0x30FB || scalar.value == 0xFF65 {
                continue
            }

            let normalized = normalizedContactReading(String(scalar))

            if !normalized.isEmpty {
                hasKana = true
                continue
            }

            return false
        }

        return hasKana
    }

    static func buildContactCandidatesByReading(
        displayMode: ContactCandidateDisplayModeOption
    ) -> [String: [String]] {
        let includeFullNameForNameMatches = displayMode == .namesPlusFullName
        let store = CNContactStore()
        let request = CNContactFetchRequest(keysToFetch: contactFetchKeys)
        var dictionary: [String: [String]] = [:]

        do {
            try store.enumerateContacts(with: request) { contact, _ in
                let familyName = contact.familyName.trimmingCharacters(in: .whitespacesAndNewlines)
                let givenName = contact.givenName.trimmingCharacters(in: .whitespacesAndNewlines)
                let middleName = contact.middleName.trimmingCharacters(in: .whitespacesAndNewlines)
                let nickname = contact.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
                let organizationName = contact.organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
                let phoneticOrganizationName = contact.phoneticOrganizationName.trimmingCharacters(in: .whitespacesAndNewlines)
                let fullName = [familyName, givenName, middleName]
                    .filter { !$0.isEmpty }
                    .joined()

                let phoneticFamily = contact.phoneticFamilyName.trimmingCharacters(in: .whitespacesAndNewlines)
                let phoneticGiven = contact.phoneticGivenName.trimmingCharacters(in: .whitespacesAndNewlines)
                let phoneticMiddle = contact.phoneticMiddleName.trimmingCharacters(in: .whitespacesAndNewlines)
                let fullNamePhonetic = [phoneticFamily, phoneticGiven, phoneticMiddle].joined()

                var readingCandidates: [(String, [String])] = [
                    (
                        phoneticFamily,
                        contactNameCandidates(
                            primaryName: familyName,
                            fullName: fullName,
                            includeFullName: includeFullNameForNameMatches
                        )
                    ),
                    (
                        phoneticGiven,
                        contactNameCandidates(
                            primaryName: givenName,
                            fullName: fullName,
                            includeFullName: includeFullNameForNameMatches
                        )
                    ),
                    (
                        phoneticMiddle,
                        contactNameCandidates(
                            primaryName: middleName,
                            fullName: fullName,
                            includeFullName: includeFullNameForNameMatches
                        )
                    ),
                    (fullNamePhonetic, [fullName]),
                    (
                        familyName,
                        contactNameCandidates(
                            primaryName: familyName,
                            fullName: fullName,
                            includeFullName: includeFullNameForNameMatches
                        )
                    ),
                    (
                        givenName,
                        contactNameCandidates(
                            primaryName: givenName,
                            fullName: fullName,
                            includeFullName: includeFullNameForNameMatches
                        )
                    ),
                    (
                        middleName,
                        contactNameCandidates(
                            primaryName: middleName,
                            fullName: fullName,
                            includeFullName: includeFullNameForNameMatches
                        )
                    ),
                    (fullName, [fullName]),
                    (nickname, [nickname]),
                    (phoneticOrganizationName, [organizationName])
                ]

                if shouldUseOrganizationNameReadingFallback(organizationName) {
                    readingCandidates.append((organizationName, [organizationName]))
                }

                for (readingText, candidates) in readingCandidates {
                    appendContactCandidates(candidates, forReadingText: readingText, to: &dictionary)
                }
            }
        } catch {
            return [:]
        }

        return dictionary
    }

    func migrateLegacyFlickGuideSettingIfNeeded() {
        guard let defaults = Self.sharedDefaults else {
            return
        }

        let modifierGuideModeKey = SettingsKeys.modifierFlickGuideDisplayMode
        let guideModeKeys = [
            SettingsKeys.kanaFlickGuideDisplayMode,
            SettingsKeys.latinFlickGuideDisplayMode,
            SettingsKeys.numberFlickGuideDisplayMode,
            modifierGuideModeKey
        ]

        let hasStoredNewGuideMode = guideModeKeys.contains { key in
            defaults.object(forKey: key) != nil
        }

        if !hasStoredNewGuideMode,
            let legacyShowsGuide = defaults.object(forKey: SettingsKeys.showsFlickGuideCharacters) as? Bool {
            let migratedMode = legacyShowsGuide
                ? FlickGuideDisplayOption.fourDirections.rawValue
                : FlickGuideDisplayOption.off.rawValue

            guideModeKeys.forEach { key in
                defaults.set(migratedMode, forKey: key)
            }
        }

        if defaults.object(forKey: modifierGuideModeKey) == nil {
            let migratedModifierMode = defaults.string(forKey: SettingsKeys.kanaFlickGuideDisplayMode)
                ?? {
                    guard let legacyShowsGuide = defaults.object(forKey: SettingsKeys.showsFlickGuideCharacters) as? Bool else {
                        return FlickGuideDisplayOption.fourDirections.rawValue
                    }

                    return legacyShowsGuide
                        ? FlickGuideDisplayOption.fourDirections.rawValue
                        : FlickGuideDisplayOption.off.rawValue
                }()
            defaults.set(migratedModifierMode, forKey: modifierGuideModeKey)
        }
    }

    func buildInitialDataSnapshot() -> InitialDataSnapshot {
        return InitialDataSnapshot(
            userDictionaryEntries: userDictionaryEntriesSnapshot(),
            learnedDictionaryEntries: learnedDictionaryEntriesSnapshot(),
            suppressionDictionaryEntries: suppressionDictionaryEntriesSnapshot(),
            shortcutDictionaryEntries: shortcutDictionaryEntriesSnapshot()
        )
    }

    // 反映は @State の書き換えなので、値が同じでも SwiftUI は設定画面を作り直す。
    // 起動時は snapshot 段と migration 段で2回呼ばれ、移行が済んでいる再インストールでは
    // 2回目の中身が1回目と完全に同じになる(実測 user=427/suppression=59/shortcut=21 が
    // 両方同一)。この空振りの再構築だけで約2.4秒使っていたので、同値なら書かない(2587)。
    // 戻り値は「実際に書き換えたか」。
    @discardableResult
    func applyInitialDataSnapshot(_ snapshot: InitialDataSnapshot) -> Bool {
        let current = InitialDataSnapshot(
            userDictionaryEntries: userDictionaryEntries,
            learnedDictionaryEntries: learnedDictionaryEntries,
            suppressionDictionaryEntries: suppressionDictionaryEntries,
            shortcutDictionaryEntries: shortcutDictionaryEntries
        )
        guard current != snapshot else {
            return false
        }

        userDictionaryEntries = snapshot.userDictionaryEntries
        learnedDictionaryEntries = snapshot.learnedDictionaryEntries
        suppressionDictionaryEntries = snapshot.suppressionDictionaryEntries
        shortcutDictionaryEntries = snapshot.shortcutDictionaryEntries
        return true
    }

    func loadInitialDataSnapshotInBackground() async -> InitialDataSnapshot {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let snapshot = buildInitialDataSnapshot()
                continuation.resume(returning: snapshot)
            }
        }
    }

    func performInitialMigrationsInBackground() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                migrateInitialUserDictionaryIfNeeded()
                cleanupLegacyMiscEraAjoutResidueIfNeeded()
                migrateInitialShortcutVocabularyIfNeeded()
                migrateInitialSuppressionDictionaryIfNeeded()
                migrateLearningVocabularySeparationIfNeeded()
                continuation.resume()
            }
        }
    }

    func startInitialSnapshotLoadInBackground(
        logEventPrefix: String,
        onCompleted: (() -> Void)? = nil
    ) {
        // Loading 表示が長い件の内訳計測(2585)。段を分けて出す:
        //   waitMs  = Task が main actor を取れるまでの待ち(直前の描画が塞いでいる時間)
        //   loadMs  = ファイル I/O + JSON デコード(バックグラウンド)
        //   applyMs = @State 反映(SwiftUI の再構築を誘発する。戻り値後の描画は次の段の waitMs に出る)
        let queuedAt = CFAbsoluteTimeGetCurrent()
        Task { @MainActor in
            let snapshotStartedAt = CFAbsoluteTimeGetCurrent()
            let waitMs = containerDiagnosticsElapsedMilliseconds(since: queuedAt)
            let snapshot = await loadInitialDataSnapshotInBackground()
            let loadMs = containerDiagnosticsElapsedMilliseconds(since: snapshotStartedAt)
            let applyStartedAt = CFAbsoluteTimeGetCurrent()
            applyInitialDataSnapshot(snapshot)
            let applyMs = containerDiagnosticsElapsedMilliseconds(since: applyStartedAt)
            didCompleteInitialDataSnapshot = true

            recordBootstrapTimingPart("snapWaitMs=\(waitMs) snapLoadMs=\(loadMs) snapApplyMs=\(applyMs)")
            appendContainerDiagnosticsLog(
                "\(logEventPrefix) snapshot反映完了 elapsedMs=\(containerDiagnosticsElapsedMilliseconds(since: snapshotStartedAt)) waitMs=\(waitMs) loadMs=\(loadMs) applyMs=\(applyMs) user=\(snapshot.userDictionaryEntries.count) learned=\(snapshot.learnedDictionaryEntries.count) suppression=\(snapshot.suppressionDictionaryEntries.count) shortcut=\(snapshot.shortcutDictionaryEntries.count)"
            )
            loadKeyboardDiagnosticsState()
            onCompleted?()
        }
    }

    func startInitialMigrationsAndRefreshSnapshotInBackground(onCompleted: (() -> Void)? = nil) {
        // 段の内訳は snapshot 側と同じ意味(2585)。waitMs が大きければ直前の SwiftUI 描画が
        // main actor を占有しているということで、移行処理そのものは犯人ではない。
        let queuedAt = CFAbsoluteTimeGetCurrent()
        Task { @MainActor in
            let migrationStartedAt = CFAbsoluteTimeGetCurrent()
            let waitMs = containerDiagnosticsElapsedMilliseconds(since: queuedAt)
            await performInitialMigrationsInBackground()
            let migrateMs = containerDiagnosticsElapsedMilliseconds(since: migrationStartedAt)

            let reloadStartedAt = CFAbsoluteTimeGetCurrent()
            let migratedSnapshot = await loadInitialDataSnapshotInBackground()
            let reloadMs = containerDiagnosticsElapsedMilliseconds(since: reloadStartedAt)
            let applyStartedAt = CFAbsoluteTimeGetCurrent()
            let didApply = applyInitialDataSnapshot(migratedSnapshot)
            let applyMs = containerDiagnosticsElapsedMilliseconds(since: applyStartedAt)

            recordBootstrapTimingPart("migWaitMs=\(waitMs) migMs=\(migrateMs) migApplyMs=\(applyMs) migChanged=\(didApply)")
            appendContainerDiagnosticsLog(
                "コンテナ初回表示 migration反映完了 elapsedMs=\(containerDiagnosticsElapsedMilliseconds(since: migrationStartedAt)) waitMs=\(waitMs) migrateMs=\(migrateMs) reloadMs=\(reloadMs) applyMs=\(applyMs) changed=\(didApply) user=\(migratedSnapshot.userDictionaryEntries.count) learned=\(migratedSnapshot.learnedDictionaryEntries.count) suppression=\(migratedSnapshot.suppressionDictionaryEntries.count) shortcut=\(migratedSnapshot.shortcutDictionaryEntries.count)"
            )
            loadKeyboardDiagnosticsState()
            SettingsSyncNotification.postSettingsDidChange()
            onCompleted?()
        }
    }

    func shouldAutoLoadSystemVocabularyOnAppear() -> Bool {
        false
    }

    func loadFirstSystemVocabularyEntriesInBackground() async -> [VocabularyEntry] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: firstSystemVocabularyEntriesSnapshot())
            }
        }
    }

    func loadSecondSystemVocabularyEntriesInBackground() async -> [VocabularyEntry] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: secondSystemVocabularyEntriesSnapshot())
            }
        }
    }

    func requestFirstSystemVocabularyEntriesLoadIfNeeded(force: Bool = false) {
        guard !isLoadingFirstVocabularyEntries else {
            return
        }

        guard force || !didLoadFirstVocabularyEntries else {
            return
        }

        isLoadingFirstVocabularyEntries = true
        let loadStartedAt = CFAbsoluteTimeGetCurrent()
        appendContainerDiagnosticsLog("コンテナで第1語彙ロード開始 force=\(force)")

        Task { @MainActor in
            let firstEntries = await loadFirstSystemVocabularyEntriesInBackground()
            firstVocabularyEntries = firstEntries
            didLoadFirstVocabularyEntries = true
            isLoadingFirstVocabularyEntries = false
            finishBootstrappingIfNeeded()

            appendContainerDiagnosticsLog(
                "コンテナで第1語彙ロード完了 count=\(firstEntries.count) elapsedMs=\(containerDiagnosticsElapsedMilliseconds(since: loadStartedAt))"
            )
            loadKeyboardDiagnosticsState()
        }
    }

    func requestSecondSystemVocabularyEntriesLoadIfNeeded(force: Bool = false) {
        guard !isLoadingSecondVocabularyEntries else {
            return
        }

        guard force || !didLoadSecondVocabularyEntries else {
            return
        }

        isLoadingSecondVocabularyEntries = true
        let loadStartedAt = CFAbsoluteTimeGetCurrent()
        appendContainerDiagnosticsLog("コンテナで第2語彙ロード開始 force=\(force)")

        Task { @MainActor in
            let secondEntries = await loadSecondSystemVocabularyEntriesInBackground()
            secondVocabularyEntries = secondEntries
            didLoadSecondVocabularyEntries = true
            isLoadingSecondVocabularyEntries = false
            finishBootstrappingIfNeeded()

            appendContainerDiagnosticsLog(
                "コンテナで第2語彙ロード完了 count=\(secondEntries.count) elapsedMs=\(containerDiagnosticsElapsedMilliseconds(since: loadStartedAt))"
            )
            loadKeyboardDiagnosticsState()
        }
    }

    func requestContactsAccessIfNeeded() async {
        guard shouldUseContactCandidates else {
            appendContainerDiagnosticsLog("連絡先アクセス許可リクエスト中止 reason=contactCandidatesDisabled")
            return
        }

        let usageDescription = (Bundle.main.object(forInfoDictionaryKey: "NSContactsUsageDescription") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""

        guard !usageDescription.isEmpty else {
            appendContainerDiagnosticsLog("連絡先アクセス許可リクエスト中止 reason=missingUsageDescription")
            return
        }

        let statusStartedAt = CFAbsoluteTimeGetCurrent()
        let status = CNContactStore.authorizationStatus(for: .contacts)
        let statusMs = containerDiagnosticsElapsedMilliseconds(since: statusStartedAt)

        switch status {
        case .authorized, .limited:
            appendContainerDiagnosticsLog("連絡先アクセス状態 status=authorized statusMs=\(statusMs)")
        case .denied, .restricted:
            appendContainerDiagnosticsLog("連絡先アクセス状態 status=deniedOrRestricted")
        case .notDetermined:
            appendContainerDiagnosticsLog("連絡先アクセス許可リクエスト開始")
            let granted = await withCheckedContinuation { continuation in
                CNContactStore().requestAccess(for: .contacts) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
            appendContainerDiagnosticsLog("連絡先アクセス許可リクエスト完了 granted=\(granted)")
        @unknown default:
            appendContainerDiagnosticsLog("連絡先アクセス状態 status=unknown")
        }

        // 連絡先の読み出しとキャッシュ生成は main actor 上で同期実行される。件数次第で
        // 重くなりうる箇所なので単独で計測する(2586)。
        let syncStartedAt = CFAbsoluteTimeGetCurrent()
        syncContactCandidatesCacheFromContainerApp()
        appendContainerDiagnosticsLog(
            "連絡先キャッシュ同期完了 elapsedMs=\(containerDiagnosticsElapsedMilliseconds(since: syncStartedAt))"
        )
    }

    func syncContactCandidatesCacheFromContainerApp() {
        guard let defaults = Self.sharedDefaults else {
            return
        }

        let cacheKey = SettingsKeys.contactCandidatesByReadingCache
        let mode = ContactCandidateDisplayModeOption(rawValue: contactCandidateDisplayModeRawValue) ?? .namesOnly

        guard mode != .off else {
            if defaults.object(forKey: cacheKey) != nil {
                defaults.removeObject(forKey: cacheKey)
                SettingsSyncNotification.postSettingsDidChange()
            }
            return
        }

        let status = CNContactStore.authorizationStatus(for: .contacts)

        guard hasGrantedContactsAccess(status) else {
            if defaults.object(forKey: cacheKey) != nil {
                defaults.removeObject(forKey: cacheKey)
                SettingsSyncNotification.postSettingsDidChange()
            }
            return
        }

        DispatchQueue.global(qos: .utility).async {
            let dictionary = Self.buildContactCandidatesByReading(displayMode: mode)

            DispatchQueue.main.async {
                guard let defaults = Self.sharedDefaults else {
                    return
                }

                let previous = defaults.dictionary(forKey: cacheKey) as? [String: [String]] ?? [:]

                guard previous != dictionary else {
                    return
                }

                defaults.set(dictionary, forKey: cacheKey)
                SettingsSyncNotification.postSettingsDidChange()
            }
        }
    }

    func hasGrantedContactsAccess(_ status: CNAuthorizationStatus) -> Bool {
        if #available(iOS 18.0, *) {
            return status == .authorized || status == .limited
        }

        return status == .authorized
    }

    func requestContactsAccessIfNeededInBackground() {
        // Loading が長い件の切り分け(2586)。連絡先のログが待ち時間の終わりに来ていたが、
        // 「連絡先が5秒かかった」のか「5秒待たされた末に動いた」のかが区別できなかった。
        // Task 入場時の待ちを出せば、main actor を塞いでいるのが連絡先か別か(SwiftUI の
        // 設定画面構築か)が確定する。
        let queuedAt = CFAbsoluteTimeGetCurrent()
        Task { @MainActor in
            let contactsWaitMs = containerDiagnosticsElapsedMilliseconds(since: queuedAt)
            appendContainerDiagnosticsLog("連絡先タスク入場 waitMs=\(contactsWaitMs)")
            let startedAt = CFAbsoluteTimeGetCurrent()
            await requestContactsAccessIfNeeded()
            let contactsMs = containerDiagnosticsElapsedMilliseconds(since: startedAt)
            recordBootstrapTimingPart("contactsWaitMs=\(contactsWaitMs) contactsMs=\(contactsMs)")
            appendContainerDiagnosticsLog("連絡先タスク完了 elapsedMs=\(contactsMs)")
        }
    }

    func finishBootstrappingIfNeeded() {
        guard !isLoadingFirstVocabularyEntries,
            !isLoadingSecondVocabularyEntries else {
            return
        }

        guard isBootstrappingInitialData else {
            return
        }

        isBootstrappingInitialData = false
        containerBootstrapFailSafeWorkItem?.cancel()
        containerBootstrapFailSafeWorkItem = nil
    }

    func scheduleContainerBootstrapFailSafe(timeoutSeconds: TimeInterval = 15) {
        containerBootstrapFailSafeWorkItem?.cancel()

        let workItem = DispatchWorkItem {
            guard isContainerBusy else {
                return
            }

            appendContainerDiagnosticsLog(
                "コンテナbootstrapフェイルセーフ発動 busy解除 timeoutSeconds=\(Int(timeoutSeconds))"
            )
            isLoadingFirstVocabularyEntries = false
            isLoadingSecondVocabularyEntries = false
            isBootstrappingInitialData = false
            didCompleteInitialDataSnapshot = true
            loadKeyboardDiagnosticsState()
        }

        containerBootstrapFailSafeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds, execute: workItem)
    }

    // 削除同期導入(2338)以前に sacoche から撤回済みの播種エントリ。播種はマージ専用だったため
    // 撤回が実機に届かず残留していた(にほん→2本 が 2本ビール を作り続けた事件)。播種記録
    // (AppliedSeed)が無い端末の初回削除同期でのみ使う既知リスト(手動追加語彙は対象外)。
    // 抑制側と違い「現状=全て播種由来」とは見なせない(ユーザはUIで手動追加語彙を使う)ため、
    // 撤回済みと確定しているペアだけを列挙する。
    static let legacyRetractedInitialUserDictionaryEntries: [String: [String]] = [
        "にほん": ["2本"],
        "まいくろ": ["µ"],
        "いちえんだま": ["1円玉"], "いちじ": ["1次"], "いちだい": ["1台"], "いちまい": ["1枚"],
        "いっかげつ": ["1か月"], "いっけん": ["1軒"], "いっしゅうかん": ["1週間"], "いっぽん": ["1本"],
        "ごえんだま": ["5円玉"], "ごじゅうえんだま": ["50円玉"], "ごひゃくえんだま": ["500円玉"],
        "さんかげつ": ["3か月"], "さんけん": ["3軒"], "さんしゅうかん": ["3週間"], "さんだい": ["3台"],
        "さんぼん": ["3本"], "さんまい": ["3枚"], "じゅうえんだま": ["10円玉"],
        "だいいちせだい": ["第1世代"], "だいさんせだい": ["第3世代"], "だいにせだい": ["第2世代"],
        "にかげつ": ["2か月"], "にけん": ["2軒"], "にじ": ["2次"], "にしゅうかん": ["2週間"],
        "にだい": ["2台"], "にまい": ["2枚"], "ひとつ": ["1つ"], "ひゃくえんだま": ["100円玉"],
        "ふたつ": ["2つ"], "みっつ": ["3つ"], "よんしゅうかん": ["4週間"]
    ]

    // misc 分離以前に Ajout(追加語彙)として播種され、削除同期(2338)導入時の既知リスト
    // (34ペア)に含まれず実機に残留していた残骸。現在は misc(68件=現行 misc と同一ペア)や
    // エンジン生成(すう+助数詞)に置き換わっており、除去しても変換は変わらない。誤植
    // (カ行変格活用変/サ行変格活用変)と誤登録(きょうにんかん→杏仁豆腐)も同梱。
    // 実機の seed外診断(2389)で特定した確定ペアのみ列挙(手動追加語彙13件は sacoche へ
    // フィードバック済みで対象外)。
    static let legacyMiscEraAjoutResidueEntries: [String: [String]] = [
        "あうん": ["あ・うん"],
        "あのへん": ["あの辺"],
        "いらっと": ["いらっと"],
        "うつりこむ": ["写り込む", "写りこむ"],
        "かぎょうへんかくかつよう": ["カ行変格活用変"],
        "きがあう": ["気が合う"],
        "きがある": ["気がある"],
        "きがきく": ["気が利く"],
        "きがする": ["気がする"],
        "きがちる": ["気が散る"],
        "きがつく": ["気が付く", "気がつく"],
        "きがながい": ["気が長い"],
        "きがはやい": ["気が早い"],
        "きがむく": ["気が向く"],
        "きにいる": ["気に入る"],
        "きにかかる": ["気にかかる"],
        "きにかける": ["気に掛ける", "気にかける"],
        "きにくわない": ["気に食わない", "気にくわない"],
        "きにする": ["気にする"],
        "きにとめる": ["気に留める", "気にとめる"],
        "きになる": ["気になる"],
        "きにやむ": ["気に病む"],
        "きょうにんかん": ["杏仁豆腐"],
        "きをうしなう": ["気を失う"],
        "きをきかせる": ["気を利かせる"],
        "きをくばる": ["気を配る"],
        "きをつかう": ["気を遣う", "気を使う", "気をつかう"],
        "きをつける": ["気を付ける", "気をつける"],
        "きをひく": ["気を引く"],
        "きをまわす": ["気を回す"],
        "きをもむ": ["気を揉む", "気をもむ"],
        "きをよくする": ["気を良くする", "気をよくする"],
        "このへん": ["この辺"],
        "ございました": ["ございました"],
        "ございます": ["ございます"],
        "ございません": ["ございません"],
        "ございませんでした": ["ございませんでした"],
        "さえら": ["さ・え・ら"],
        "さぎょうへんかくかつよう": ["サ行変格活用変"],
        "じがじさん": ["自画自賛"],
        "すうかい": ["数回"],
        "すうかげつ": ["数か月"],
        "すうかしょ": ["数か所"],
        "すうけん": ["数件"],
        "すうこ": ["数個"],
        "すうしゅうかん": ["数週間"],
        "すうじかん": ["数時間"],
        "すうじつ": ["数日"],
        "すうだい": ["数台"],
        "すうにん": ["数人"],
        "すうねん": ["数年"],
        "すうびょう": ["数秒"],
        "すうふん": ["数分"],
        "すうほん": ["数本"],
        "すうまい": ["数枚"],
        "ぜんかいいっち": ["全会一致"],
        "そのへん": ["その辺"],
        "だが": ["だが"],
        "てにはいる": ["手に入る"],
        "できる": ["できる"],
        "どのへん": ["どの辺"],
        "なのだ": ["なのだ"],
        "なので": ["なので"],
        "なのです": ["なのです"],
        "なのに": ["なのに"],
        "なのよね": ["なのよね"],
        "にした": ["にした"],
        "にして": ["にして"],
        "にしよう": ["にしよう"],
        "にする": ["にする"],
        "ねおち": ["寝落ち"],
        "ぱるる": ["ぱ・る・る"],
        "まかいぞう": ["魔改造"],
        "もやしいため": ["もやし炒め"],
        "やくにたつ": ["役に立つ"],
        "やって": ["やって"]
    ]

    // misc 分離残骸の one-shot 清掃。AppliedSeed 記録済みの端末には通常の削除同期が
    // 届かない(現行 seed 基準の差分しか見ない)ため、確定リストで一度だけ除去する。
    func cleanupLegacyMiscEraAjoutResidueIfNeeded() {
        guard let defaults = Self.sharedDefaults,
            !defaults.bool(forKey: SettingsKeys.kanaKanjiMiscEraAjoutResidueCleanupCompleted) else {
            return
        }
        var currentDictionary = normalizedDictionaryEntries(
            loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiAjoutVocabulary)
        )
        var removedCount = 0
        for (reading, candidates) in Self.legacyMiscEraAjoutResidueEntries {
            let retracted = Set(candidates)
            let kept = (currentDictionary[reading] ?? []).filter { !retracted.contains($0) }
            removedCount += (currentDictionary[reading]?.count ?? 0) - kept.count
            if kept.isEmpty {
                currentDictionary.removeValue(forKey: reading)
            } else {
                currentDictionary[reading] = kept
            }
        }
        if removedCount > 0 {
            saveDictionaryEntries(currentDictionary, forKey: SettingsKeys.kanaKanjiAjoutVocabulary)
        }
        defaults.set(true, forKey: SettingsKeys.kanaKanjiMiscEraAjoutResidueCleanupCompleted)
    }

    func migrateInitialUserDictionaryIfNeeded() {
        guard let defaults = Self.sharedDefaults else {
            return
        }

        let initialDictionary = loadBundledInitialUserDictionaryEntries()

        guard !initialDictionary.isEmpty else {
            return
        }

        let initialSignature = dictionarySignature(initialDictionary)
        let appliedSignature = defaults.string(
            forKey: SettingsKeys.kanaKanjiInitialUserDictionaryAppliedSignature
        )

        // 播種記録(AppliedSeed)が無い端末では、署名が一致していても一度だけ削除同期を実行する
        // (削除同期導入前に撤回済みエントリが残留しているのを回収するため。抑制側 1889 と同機構)。
        let hasAppliedSeed = defaults.object(
            forKey: SettingsKeys.kanaKanjiInitialUserDictionaryAppliedSeed
        ) != nil
        guard appliedSignature != initialSignature || !hasAppliedSeed else {
            return
        }

        var currentDictionary = normalizedDictionaryEntries(
            loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiAjoutVocabulary)
        )

        // 削除同期: 過去に播種したもののうち新バンドルに無いペアを端末からも除去する。
        // 初回(播種記録なし)は手動追加語彙と区別できないため、撤回済みと確定している
        // 既知リスト(legacyRetracted…)だけをベースラインにする。
        let previouslySeeded = normalizedDictionaryEntries(
            loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiInitialUserDictionaryAppliedSeed)
        )
        let removalBaseline = previouslySeeded.isEmpty
            ? Self.legacyRetractedInitialUserDictionaryEntries
            : previouslySeeded
        for (reading, candidates) in removalBaseline {
            let retracted = Set(candidates).subtracting(Set(initialDictionary[reading] ?? []))
            guard !retracted.isEmpty else { continue }
            let kept = (currentDictionary[reading] ?? []).filter { !retracted.contains($0) }
            if kept.isEmpty {
                currentDictionary.removeValue(forKey: reading)
            } else {
                currentDictionary[reading] = kept
            }
        }

        let merged = mergedDictionary(preferred: currentDictionary, fallback: initialDictionary)

        if merged != normalizedDictionaryEntries(
            loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiAjoutVocabulary)
        ) {
            saveDictionaryEntries(merged, forKey: SettingsKeys.kanaKanjiAjoutVocabulary)
        }

        saveDictionaryEntries(
            initialDictionary,
            forKey: SettingsKeys.kanaKanjiInitialUserDictionaryAppliedSeed
        )
        defaults.set(true, forKey: SettingsKeys.kanaKanjiInitialUserDictionaryMigrated)
        defaults.set(
            initialSignature,
            forKey: SettingsKeys.kanaKanjiInitialUserDictionaryAppliedSignature
        )
    }

    func migrateInitialSuppressionDictionaryIfNeeded() {
        guard let defaults = Self.sharedDefaults else {
            return
        }

        let initialDictionary = loadBundledInitialSuppressionDictionaryEntries()

        guard !initialDictionary.isEmpty else {
            return
        }

        let initialSignature = dictionarySignature(initialDictionary)
        let appliedSignature = defaults.string(
            forKey: SettingsKeys.kanaKanjiInitialSuppressionDictionaryAppliedSignature
        )

        // 播種記録(AppliedSeed)が無い端末では、署名が一致していても一度だけ削除同期を
        // 実行する(削除同期導入前に撤回済みエントリが残留しているのを回収するため)。
        let hasAppliedSeed = defaults.object(
            forKey: SettingsKeys.kanaKanjiInitialSuppressionDictionaryAppliedSeed
        ) != nil
        guard appliedSignature != initialSignature || !hasAppliedSeed else {
            return
        }

        var currentDictionary = normalizedDictionaryEntries(
            loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiSuppressionVocabulary)
        )

        // 削除同期: 過去にバンドルから播種した抑制のうち、新しいバンドルに無くなったものは
        // 端末からも取り除く(撤回が実機に届くように)。初回(播種記録なし)は「現状は全て
        // 播種由来」とみなす — 抑制は plist→バンドル経由でのみ運用しており、アプリUIでの
        // 手動抑制は使っていない前提。
        let previouslySeeded = normalizedDictionaryEntries(
            loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiInitialSuppressionDictionaryAppliedSeed)
        )
        let removalBaseline = previouslySeeded.isEmpty ? currentDictionary : previouslySeeded
        for (reading, candidates) in removalBaseline {
            let retracted = Set(candidates).subtracting(Set(initialDictionary[reading] ?? []))
            guard !retracted.isEmpty else { continue }
            let kept = (currentDictionary[reading] ?? []).filter { !retracted.contains($0) }
            if kept.isEmpty {
                currentDictionary.removeValue(forKey: reading)
            } else {
                currentDictionary[reading] = kept
            }
        }

        let merged = mergedDictionary(preferred: currentDictionary, fallback: initialDictionary)

        if merged != normalizedDictionaryEntries(
            loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiSuppressionVocabulary)
        ) {
            saveDictionaryEntries(merged, forKey: SettingsKeys.kanaKanjiSuppressionVocabulary)
        }

        saveDictionaryEntries(
            initialDictionary,
            forKey: SettingsKeys.kanaKanjiInitialSuppressionDictionaryAppliedSeed
        )
        defaults.set(true, forKey: SettingsKeys.kanaKanjiInitialSuppressionDictionaryMigrated)
        defaults.set(
            initialSignature,
            forKey: SettingsKeys.kanaKanjiInitialSuppressionDictionaryAppliedSignature
        )
    }

    func migrateInitialShortcutVocabularyIfNeeded() {
        guard let defaults = Self.sharedDefaults else {
            return
        }

        let initialCandidates = loadBundledInitialShortcutVocabularyEntries()

        guard !initialCandidates.isEmpty else {
            return
        }

        let currentCandidates = loadShortcutVocabularyCandidates()
        // Keep initial shortcut order authoritative while preserving existing entries.
        let mergedCandidates = uniqueShortcutCandidatesPreservingOrder(initialCandidates + currentCandidates)

        if mergedCandidates != currentCandidates {
            saveShortcutVocabularyCandidates(mergedCandidates)
        }

        defaults.set(true, forKey: SettingsKeys.kanaKanjiInitialShortcutVocabularyMigrated)
    }

    func migrateLearningVocabularySeparationIfNeeded() {
        guard let defaults = Self.sharedDefaults,
            !defaults.bool(forKey: SettingsKeys.kanaKanjiLearningVocabularyMigrationCompleted) else {
            return
        }

        let currentUserDictionary = normalizedDictionaryEntries(
            loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiAjoutVocabulary)
        )
        let currentLearnedDictionary = normalizedDictionaryEntries(
            loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiLearnedVocabulary)
        )

        var learnedFromScores: [String: [String]] = [:]

        for (key, score) in loadLearningScores() where score > 0 {
            guard let entry = parseLearningKey(key) else {
                continue
            }

            // Legacy mixed data cannot be distinguished reliably. Keep ambiguous items on manual side.
            if currentUserDictionary[entry.reading]?.contains(entry.candidate) == true {
                continue
            }

            var candidates = learnedFromScores[entry.reading] ?? []

            if let existingIndex = candidates.firstIndex(of: entry.candidate) {
                candidates.remove(at: existingIndex)
            }

            candidates.insert(entry.candidate, at: 0)
            learnedFromScores[entry.reading] = Array(candidates.prefix(32))
        }

        let mergedLearnedDictionary = mergedDictionary(
            preferred: currentLearnedDictionary,
            fallback: learnedFromScores
        )

        if mergedLearnedDictionary != currentLearnedDictionary {
            saveDictionaryEntries(mergedLearnedDictionary, forKey: SettingsKeys.kanaKanjiLearnedVocabulary)
        }

        defaults.set(true, forKey: SettingsKeys.kanaKanjiLearningVocabularyMigrationCompleted)
    }

    func handleContainerAppAppear() {
        if didRunFirstAppearanceBootstrap {
            guard !isBootstrappingInitialData else {
                return
            }

            isBootstrappingInitialData = true
            scheduleContainerBootstrapFailSafe()

            Task { @MainActor in
                let refreshStartedAt = CFAbsoluteTimeGetCurrent()
                requestContactsAccessIfNeededInBackground()
                clearKeyboardDiagnosticsIfInstallChanged()
                recordKeyboardExtensionRegistrationState()
                loadKeyboardDiagnosticsState()
                appendContainerDiagnosticsLog("コンテナ再表示 refresh開始")
                startInitialSnapshotLoadInBackground(logEventPrefix: "コンテナ再表示") {
                    finishBootstrappingIfNeeded()
                }
                let shouldAutoLoadSystemVocabulary = shouldAutoLoadSystemVocabularyOnAppear()

                if didLoadFirstVocabularyEntries {
                    requestFirstSystemVocabularyEntriesLoadIfNeeded(force: true)
                } else if shouldAutoLoadSystemVocabulary {
                    requestFirstSystemVocabularyEntriesLoadIfNeeded()
                }

                if didLoadSecondVocabularyEntries {
                    requestSecondSystemVocabularyEntriesLoadIfNeeded(force: true)
                } else if shouldAutoLoadSystemVocabulary {
                    requestSecondSystemVocabularyEntriesLoadIfNeeded()
                }

                appendContainerDiagnosticsLog(
                    "コンテナ再表示 refresh完了 elapsedMs=\(containerDiagnosticsElapsedMilliseconds(since: refreshStartedAt)) user=\(userDictionaryEntries.count) learned=\(learnedDictionaryEntries.count) suppression=\(suppressionDictionaryEntries.count) shortcut=\(shortcutDictionaryEntries.count)"
                )
                loadKeyboardDiagnosticsState()
            }
            return
        }

        didRunFirstAppearanceBootstrap = true
        containerDiagnosticsSessionID = UUID().uuidString
        isBootstrappingInitialData = true
        scheduleContainerBootstrapFailSafe()

        Task { @MainActor in
            let bootstrapStartedAt = CFAbsoluteTimeGetCurrent()
            // Let SwiftUI present the first frame before expensive file I/O and JSON decode.
            await Task.yield()
            let firstFrameMs = containerDiagnosticsElapsedMilliseconds(since: bootstrapStartedAt)

            requestContactsAccessIfNeededInBackground()

            let preludeStartedAt = CFAbsoluteTimeGetCurrent()
            clearLegacyKeyboardDebugLogKeysIfNeeded()
            migrateLegacyFlickGuideSettingIfNeeded()
            clearKeyboardDiagnosticsIfInstallChanged()
            recordKeyboardExtensionRegistrationState()
            loadKeyboardDiagnosticsState()
            // firstFrameMs = 初回フレームを譲るのに掛かった時間(ここが大きいと ContentView
            // 本体の構築が重い)。preludeMs = 診断の読み書き等の前処理(2585)
            recordBootstrapTimingPart("firstFrameMs=\(firstFrameMs)")
            appendContainerDiagnosticsLog(
                "コンテナ初回表示 bootstrap開始 firstFrameMs=\(firstFrameMs) preludeMs=\(containerDiagnosticsElapsedMilliseconds(since: preludeStartedAt))"
            )
            startInitialSnapshotLoadInBackground(logEventPrefix: "コンテナ初回表示") {
                startInitialMigrationsAndRefreshSnapshotInBackground {
                    let totalMs = containerDiagnosticsElapsedMilliseconds(since: bootstrapStartedAt)
                    appendContainerDiagnosticsLog("コンテナ初回表示 bootstrap完了 elapsedMs=\(totalMs)")
                    flushBootstrapTimingHistory(totalMs: totalMs)
                    loadKeyboardDiagnosticsState()
                    finishBootstrappingIfNeeded()
                }
            }

            if shouldAutoLoadSystemVocabularyOnAppear() {
                requestFirstSystemVocabularyEntriesLoadIfNeeded()
                requestSecondSystemVocabularyEntriesLoadIfNeeded()
            }
        }
    }
}
