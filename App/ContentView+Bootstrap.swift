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

    // 連絡先のふりがなを読みに直す(カタカナはひらがなに)。かな・長音以外の文字が混ざっていれば読みとして使わない(空を返す)。
    // 空白と中黒は読みの区切りとして読み飛ばす。以前はかな以外の文字を黙って捨てており、表記を読みにする予備の経路で
    // フルネイム「内海えみこ」が読み「えみこ」になり、「一致した名前だけ」の設定でも えみこ → 内海えみこ が出ていた(ユーザ報告 3679)
    static func normalizedContactReading(_ text: String) -> String {
        var normalized = ""

        for character in text.precomposedStringWithCanonicalMapping {
            if character.isWhitespace || character == "・" {
                continue
            }
            // ひらがなに対応する字の無い小書きの ヵ/ヶ は か/け に(ふりがなはひらがなでもカタカナでも、混ざっていてもよい。3679)
            if character == "ヵ" || character == "ヶ" {
                normalized.append(character == "ヵ" ? "か" : "け")
                continue
            }
            let source = String(character)
            let converted = source.applyingTransform(.hiraganaToKatakana, reverse: true) ?? source

            guard converted.count == 1,
                let scalar = converted.unicodeScalars.first,
                (0x3040...0x309F).contains(scalar.value) || scalar.value == 0x30FC,
                let normalizedCharacter = converted.first else {
                return ""
            }

            normalized.append(normalizedCharacter)
        }

        return normalized
    }

    // 連絡先 1 件の項目から 読み→候補 の組を作る(3679、ユーザ指定)。読みは iOS の連絡先の「ふりがな」の項目だけを使い、
    // 表記とふりがながそろっている項目だけ組にする(どちらか片方しかない項目は使わない。表記を読みにする予備の経路は廃止)。
    // ・姓/名/ミドルネーム/会社名: その項目のふりがな → その項目の表記(どの設定でも)
    // ・フルネイム(includeFullName = [フルネイムも候補にする]のとき): 姓と名のどちらも表記とふりがながそろい、ミドルネームは
    //   あるなら表記とふりがながそろっているときだけ。姓/名/ミドルネームそれぞれのふりがなと、続けたふりがなで フルネイムを出す
    // ・ニックネームは iOS にふりがなの項目が無いので使わない
    struct ContactNameFields {
        var familyName = "", phoneticFamilyName = ""
        var givenName = "", phoneticGivenName = ""
        var middleName = "", phoneticMiddleName = ""
        var organizationName = "", phoneticOrganizationName = ""
    }

    static func contactReadingPairs(_ fields: ContactNameFields, includeFullName: Bool) -> [(reading: String, candidates: [String])] {
        func pair(_ surface: String, _ phonetic: String) -> (surface: String, reading: String)? {
            let surface = surface.trimmingCharacters(in: .whitespacesAndNewlines)
            let reading = normalizedContactReading(phonetic)
            guard !surface.isEmpty, !reading.isEmpty else { return nil }
            return (surface, reading)
        }
        let family = pair(fields.familyName, fields.phoneticFamilyName)
        let given = pair(fields.givenName, fields.phoneticGivenName)
        let middle = pair(fields.middleName, fields.phoneticMiddleName)
        let organization = pair(fields.organizationName, fields.phoneticOrganizationName)
        let middleIsConsistent = middle != nil
            || (fields.middleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && normalizedContactReading(fields.phoneticMiddleName).isEmpty)

        var pairs: [(reading: String, candidates: [String])] = []
        for part in [family, given, middle, organization].compactMap({ $0 }) {
            pairs.append((part.reading, [part.surface]))
        }
        if includeFullName, let family, let given, middleIsConsistent {
            let parts = [family, given] + (middle.map { [$0] } ?? [])
            let fullName = parts.map(\.surface).joined()
            let fullReading = parts.map(\.reading).joined()
            for part in parts {
                pairs.append((part.reading, [fullName]))
            }
            pairs.append((fullReading, [fullName]))
        }
        return pairs
    }

    static func appendContactCandidates(
        _ candidates: [String],
        forReading normalizedReading: String,
        to dictionary: inout [String: [String]]
    ) {
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

    static func buildContactCandidatesByReading(
        displayMode: ContactCandidateDisplayModeOption
    ) -> [String: [String]] {
        let includeFullName = displayMode == .namesPlusFullName
        let store = CNContactStore()
        let request = CNContactFetchRequest(keysToFetch: contactFetchKeys)
        var dictionary: [String: [String]] = [:]

        do {
            try store.enumerateContacts(with: request) { contact, _ in
                let fields = ContactNameFields(
                    familyName: contact.familyName, phoneticFamilyName: contact.phoneticFamilyName,
                    givenName: contact.givenName, phoneticGivenName: contact.phoneticGivenName,
                    middleName: contact.middleName, phoneticMiddleName: contact.phoneticMiddleName,
                    organizationName: contact.organizationName, phoneticOrganizationName: contact.phoneticOrganizationName
                )
                for (reading, candidates) in contactReadingPairs(fields, includeFullName: includeFullName) {
                    appendContactCandidates(candidates, forReading: reading, to: &dictionary)
                }
            }
        } catch {
            return [:]
        }

        return dictionary
    }

    func buildInitialDataSnapshot() -> InitialDataSnapshot {
        return InitialDataSnapshot(
            ajoutVocabularyEntries: ajoutVocabularyEntriesSnapshot(),
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
            ajoutVocabularyEntries: ajoutVocabularyEntries,
            learnedDictionaryEntries: learnedDictionaryEntries,
            suppressionDictionaryEntries: suppressionDictionaryEntries,
            shortcutDictionaryEntries: shortcutDictionaryEntries
        )
        guard current != snapshot else {
            return false
        }

        ajoutVocabularyEntries = snapshot.ajoutVocabularyEntries
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
                migrateInitialAjoutVocabularyIfNeeded()
                backfillUserRegisteredAjoutVocabularyIfNeeded()
                migrateInitialShortcutVocabularyIfNeeded()
                migrateShortcutCursorMarkerIfNeeded()
                deliverNewInitialShortcutVocabularyIfNeeded()
                migrateInitialSuppressionDictionaryIfNeeded()
                backfillUserRegisteredSuppressionVocabularyIfNeeded()
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

            recordBootstrapTimingPart("snapAtMs=\(containerBootstrapOffsetMilliseconds()) snapWaitMs=\(waitMs) snapLoadMs=\(loadMs) snapApplyMs=\(applyMs)")
            appendContainerDiagnosticsLog(
                "\(logEventPrefix) snapshot反映完了 elapsedMs=\(containerDiagnosticsElapsedMilliseconds(since: snapshotStartedAt)) waitMs=\(waitMs) loadMs=\(loadMs) applyMs=\(applyMs) user=\(snapshot.ajoutVocabularyEntries.count) learned=\(snapshot.learnedDictionaryEntries.count) suppression=\(snapshot.suppressionDictionaryEntries.count) shortcut=\(snapshot.shortcutDictionaryEntries.count)"
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

            recordBootstrapTimingPart("migAtMs=\(containerBootstrapOffsetMilliseconds()) migWaitMs=\(waitMs) migMs=\(migrateMs) migApplyMs=\(applyMs) migChanged=\(didApply)")
            appendContainerDiagnosticsLog(
                "コンテナ初回表示 migration反映完了 elapsedMs=\(containerDiagnosticsElapsedMilliseconds(since: migrationStartedAt)) waitMs=\(waitMs) migrateMs=\(migrateMs) reloadMs=\(reloadMs) applyMs=\(applyMs) changed=\(didApply) user=\(migratedSnapshot.ajoutVocabularyEntries.count) learned=\(migratedSnapshot.learnedDictionaryEntries.count) suppression=\(migratedSnapshot.suppressionDictionaryEntries.count) shortcut=\(migratedSnapshot.shortcutDictionaryEntries.count)"
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
        guard Self.sharedDefaults != nil else {
            return
        }

        let mode = ContactCandidateDisplayModeOption(rawValue: contactCandidateDisplayModeRawValue) ?? .off

        let stampKey = SettingsKeys.contactCandidatesByReadingCacheCompactSealedStamp
        let appGroupID = SettingsKeys.appGroupID

        guard mode != .off else {
            removeContactCandidatesCacheIfPresent()
            return
        }

        let status = CNContactStore.authorizationStatus(for: .contacts)

        guard hasGrantedContactsAccess(status) else {
            removeContactCandidatesCacheIfPresent()
            return
        }

        DispatchQueue.global(qos: .utility).async {
            let dictionary = Self.buildContactCandidatesByReading(displayMode: mode)

            DispatchQueue.main.async {
                guard let defaults = Self.sharedDefaults else {
                    return
                }

                // 対応表は App Group のファイルに畳んだ形で置き、iOS のファイル保護(初回ロック解除まで読めない暗号化)を掛け、
                // バックアップ対象外にする(3260)。以前の自前 AES 封緘+Keychain 鍵(2026-08-31〜)はやめた:
                // App Group に入れるのは本体と拡張だけで、端末の保存領域は iOS が暗号化しており、封緘が上乗せしていたのは
                // 暗号化なしのローカルバックアップへの対策だけ(ファイルはバックアップ対象外で同じ効果)。
                // 封緘をやめると拡張が mmap で開けるので、開くたびの復号でヒープを 4MB 確保する問題も消える
                let compactStore = SupplementalVocabCompactStore(dictionary: ContactCacheCipher.limited(dictionary))
                let existing = ContactCacheCipher.openCompactFile(appGroupID: appGroupID)
                if existing == compactStore {
                    if defaults.string(forKey: stampKey) == nil {
                        defaults.set(UUID().uuidString, forKey: stampKey)
                    }
                    return
                }
                guard ContactCacheCipher.writeCompactFile(compactStore, appGroupID: appGroupID) else {
                    appendContainerDiagnosticsLog("連絡先の対応表のファイル書き込みに失敗")
                    return
                }
                defaults.set(UUID().uuidString, forKey: stampKey)
                SettingsSyncNotification.postSettingsDidChange()
            }
        }
    }

    // 連絡先の対応表のファイルが残っていれば消し、拡張に知らせる
    func removeContactCandidatesCacheIfPresent() {
        guard let defaults = Self.sharedDefaults else {
            return
        }
        let appGroupID = SettingsKeys.appGroupID
        guard ContactCacheCipher.compactFileExists(appGroupID: appGroupID) else {
            return
        }
        ContactCacheCipher.removeCompactFile(appGroupID: appGroupID)
        defaults.set(UUID().uuidString, forKey: SettingsKeys.contactCandidatesByReadingCacheCompactSealedStamp)
        SettingsSyncNotification.postSettingsDidChange()
    }

    // 前面復帰のたびに呼ぶ(3310)。設定アプリで連絡先の許可を取り消して戻ってきたとき、以前はアプリを
    // 開き直す(起動時の同期)まで対応表が残り、拡張が候補に出し続けていた(セキュリティー検査 2026-10-02)。
    // 許可があるときは何もしない(対応表の作り直しは連絡先の読み直しを伴うので、起動時と設定変更時だけ)
    func removeContactCandidatesCacheIfAccessRevoked() {
        let mode = ContactCandidateDisplayModeOption(rawValue: contactCandidateDisplayModeRawValue) ?? .off
        guard mode != .off else {
            return
        }
        let status = CNContactStore.authorizationStatus(for: .contacts)
        guard !hasGrantedContactsAccess(status) else {
            return
        }
        removeContactCandidatesCacheIfPresent()
        appendContainerDiagnosticsLog("連絡先の許可が取り消されていたため対応表を削除 status=\(status.rawValue)")
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
            recordBootstrapTimingPart("contactsAtMs=\(containerBootstrapOffsetMilliseconds()) contactsWaitMs=\(contactsWaitMs) contactsMs=\(contactsMs)")
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
    static let legacyRetractedInitialAjoutVocabularyEntries: [String: [String]] = [
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

    func migrateInitialAjoutVocabularyIfNeeded() {
        migrateSeededDictionaryIfNeeded(
            bundled: loadBundledInitialAjoutVocabularyEntries(),
            vocabularyKey: SettingsKeys.kanaKanjiAjoutVocabulary,
            appliedSeedKey: SettingsKeys.kanaKanjiInitialAjoutVocabularyAppliedSeed,
            appliedSignatureKey: SettingsKeys.kanaKanjiInitialAjoutVocabularyAppliedSignature,
            migratedFlagKey: SettingsKeys.kanaKanjiInitialAjoutVocabularyMigrated,
            // 初回(播種記録なし)は手動追加語彙と区別できないため、撤回済みと確定している
            // 既知リスト(legacyRetracted…)だけをベースラインにする
            firstRunRemovalBaseline: { _ in Self.legacyRetractedInitialAjoutVocabularyEntries }
        )
    }

    func migrateInitialSuppressionDictionaryIfNeeded() {
        migrateSeededDictionaryIfNeeded(
            bundled: loadBundledInitialSuppressionDictionaryEntries(),
            vocabularyKey: SettingsKeys.kanaKanjiSuppressionVocabulary,
            appliedSeedKey: SettingsKeys.kanaKanjiInitialSuppressionDictionaryAppliedSeed,
            appliedSignatureKey: SettingsKeys.kanaKanjiInitialSuppressionDictionaryAppliedSignature,
            migratedFlagKey: SettingsKeys.kanaKanjiInitialSuppressionDictionaryMigrated,
            // 初回(播種記録なし)は「現状は全て播種由来」とみなす — 抑制は plist→バンドル経由でのみ
            // 運用しており、アプリUIでの手動抑制は使っていない前提
            firstRunRemovalBaseline: { current in current }
        )
    }

    // バンドル同梱の初期語彙(追加語彙/抑制語彙)を端末の語彙へ播種する共通手順(2805 で 2 本を統合)。
    // 署名(バンドル内容のハッシュ)が前回適用時と同じなら何もしない。ただし播種記録(AppliedSeed)が無い
    // 端末では、署名が一致していても一度だけ削除同期を実行する(削除同期導入前に撤回済みエントリが
    // 残留しているのを回収するため。抑制側 1889 と同機構)。
    // 削除同期: 過去に播種したもののうち新バンドルに無いペアを端末からも除去する(撤回が実機に届くように)。
    // 初回のベースラインは呼び出し側が決める(firstRunRemovalBaseline)。
    private func migrateSeededDictionaryIfNeeded(
        bundled initialDictionary: [String: [String]],
        vocabularyKey: String,
        appliedSeedKey: String,
        appliedSignatureKey: String,
        migratedFlagKey: String,
        firstRunRemovalBaseline: ([String: [String]]) -> [String: [String]]
    ) {
        guard let defaults = Self.sharedDefaults else {
            return
        }

        guard !initialDictionary.isEmpty else {
            return
        }

        let initialSignature = dictionarySignature(initialDictionary)
        let appliedSignature = defaults.string(forKey: appliedSignatureKey)
        let hasAppliedSeed = defaults.object(forKey: appliedSeedKey) != nil
        guard appliedSignature != initialSignature || !hasAppliedSeed else {
            return
        }

        var currentDictionary = normalizedDictionaryEntries(
            loadDictionaryEntries(forKey: vocabularyKey)
        )

        let previouslySeeded = normalizedDictionaryEntries(
            loadDictionaryEntries(forKey: appliedSeedKey)
        )
        let removalBaseline = previouslySeeded.isEmpty
            ? firstRunRemovalBaseline(currentDictionary)
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

        if merged != normalizedDictionaryEntries(loadDictionaryEntries(forKey: vocabularyKey)) {
            saveDictionaryEntries(merged, forKey: vocabularyKey)
        }

        saveDictionaryEntries(initialDictionary, forKey: appliedSeedKey)
        defaults.set(true, forKey: migratedFlagKey)
        defaults.set(initialSignature, forKey: appliedSignatureKey)
    }

    // 初回起動時に 1 回だけ: 保存一覧に無い初期ショートカット(InitialShortcutVocabMigration.json)を末尾へ足す(3243)。
    // 保存一覧の順が表示順(並べ替え・確定した絵文字の先頭追加はキーボード側と共有)なので、初期一覧を前に置かない。
    // 2 回目以降は動かさない(ユーザが消した初期項目を戻さない)
    func migrateInitialShortcutVocabularyIfNeeded() {
        guard let defaults = Self.sharedDefaults,
            !defaults.bool(forKey: SettingsKeys.kanaKanjiInitialShortcutVocabularyMigrated) else {
            return
        }

        // 初回起動: iOS のユーザ辞書の ☻ 語をショートカットへ取り込む予約(3244)。
        // アプリからはユーザ辞書を読めないので、拡張の次回レキシコン取得に任せる。
        defaults.set(true, forKey: SettingsKeys.kanaKanjiUserDictionaryShortcutImportPending)

        let initialCandidates = loadBundledInitialShortcutVocabularyEntries()

        guard !initialCandidates.isEmpty else {
            return
        }

        let currentCandidates = loadShortcutVocabularyCandidates()
        let mergedCandidates = uniqueShortcutCandidatesPreservingOrder(currentCandidates + initialCandidates)

        if mergedCandidates != currentCandidates {
            saveShortcutVocabularyCandidates(mergedCandidates)
        }

        defaults.set(true, forKey: SettingsKeys.kanaKanjiInitialShortcutVocabularyMigrated)
        // ここで配った初期項目を覚える(あとから初期一覧に足した項目だけを配るため。下の deliverNewInitialShortcutVocabularyIfNeeded)
        defaults.set(initialCandidates, forKey: SettingsKeys.kanaKanjiInitialShortcutVocabularyOffered)
    }

    // 初期一覧(InitialShortcutVocabMigration.json)にあとから足した項目を、初回の取り込みが済んだ端末にも配る(3769、ユーザ指定)。
    // 「一度配った初期項目」を覚えておき、初期一覧にあってまだ配っていない項目だけを足す。配ったあとにユーザが消した項目は
    // 戻さない。この仕組みの前から使っている端末には記録が無いので、仕組みを入れた時点で足した 2 件を除いた初期一覧を
    // 配り済みとみなす(今後は json に足すだけで、次の起動で全端末に入る)
    static let initialShortcutEntriesAddedWithDelivery = ["[設定]-[一般]-[‸]-[]", "[設定]-[アプリ]-[‸]-[]"]

    // 足す位置は、初期一覧で前にある項目のうち、今の一覧に残っている最も近いものの直後(無ければ末尾)
    static func shortcutCandidatesAddingNewInitialEntries(current: [String], bundled: [String], offered: [String]) -> [String] {
        var updated = current
        let offeredSet = Set(offered)
        for (index, entry) in bundled.enumerated() where !offeredSet.contains(entry) && !updated.contains(entry) {
            if let anchor = bundled[..<index].last(where: { updated.contains($0) }),
                let anchorIndex = updated.firstIndex(of: anchor) {
                updated.insert(entry, at: anchorIndex + 1)
            } else {
                updated.append(entry)
            }
        }
        return updated
    }

    func deliverNewInitialShortcutVocabularyIfNeeded() {
        // 初回の取り込みがまだの端末は、そちらが初期一覧を丸ごと入れて記録する
        guard let defaults = Self.sharedDefaults,
            defaults.bool(forKey: SettingsKeys.kanaKanjiInitialShortcutVocabularyMigrated) else {
            return
        }
        let bundled = loadBundledInitialShortcutVocabularyEntries()
        guard !bundled.isEmpty else {
            return
        }
        let offered = defaults.stringArray(forKey: SettingsKeys.kanaKanjiInitialShortcutVocabularyOffered)
            ?? bundled.filter { !Self.initialShortcutEntriesAddedWithDelivery.contains($0) }
        guard offered != bundled else {
            return
        }
        let currentCandidates = loadShortcutVocabularyCandidates()
        let updatedCandidates = uniqueShortcutCandidatesPreservingOrder(
            Self.shortcutCandidatesAddingNewInitialEntries(current: currentCandidates, bundled: bundled, offered: offered)
        )
        if updatedCandidates != currentCandidates {
            saveShortcutVocabularyCandidates(updatedCandidates)
        }
        defaults.set(bundled, forKey: SettingsKeys.kanaKanjiInitialShortcutVocabularyOffered)
    }

    // 初期ショートカットにカーソル位置の印 ‸ を入れた(3735、ユーザ指定)のを、すでに入っている端末にも 1 回だけ当てる。
    // 置き換えるのは以前の初期項目と同じ文字列だけ(ユーザが書いた語は触らない)。新しい初期項目 『‸』 は (‸) の直後
    // (無ければ末尾)へ足す。新しい端末は上の初期登録で印つきが入るので、ここでは何も変わらない
    static let shortcutCursorMarkerReplacements: [String: String] = [
        "()": "(‸)", "[設定]-[]-[]": "[設定]-[‸]-[]", "-[]": "-[‸]",
    ]
    static let shortcutCursorMarkerAddedEntry = "『‸』"

    static func shortcutCandidatesApplyingCursorMarker(_ candidates: [String]) -> [String] {
        var updated = candidates.map { shortcutCursorMarkerReplacements[$0] ?? $0 }
        if !updated.contains(shortcutCursorMarkerAddedEntry) {
            if let index = updated.firstIndex(of: "(‸)") {
                updated.insert(shortcutCursorMarkerAddedEntry, at: index + 1)
            } else {
                updated.append(shortcutCursorMarkerAddedEntry)
            }
        }
        return updated
    }

    func migrateShortcutCursorMarkerIfNeeded() {
        guard let defaults = Self.sharedDefaults,
            !defaults.bool(forKey: SettingsKeys.kanaKanjiShortcutCursorMarkerMigrated) else {
            return
        }

        let currentCandidates = loadShortcutVocabularyCandidates()
        let updatedCandidates = uniqueShortcutCandidatesPreservingOrder(
            Self.shortcutCandidatesApplyingCursorMarker(currentCandidates)
        )
        if updatedCandidates != currentCandidates {
            saveShortcutVocabularyCandidates(updatedCandidates)
        }

        defaults.set(true, forKey: SettingsKeys.kanaKanjiShortcutCursorMarkerMigrated)
    }

    func migrateLearningVocabularySeparationIfNeeded() {
        guard let defaults = Self.sharedDefaults,
            !defaults.bool(forKey: SettingsKeys.kanaKanjiLearningVocabularyMigrationCompleted) else {
            return
        }

        let currentAjoutVocabulary = normalizedDictionaryEntries(
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
            if currentAjoutVocabulary[entry.reading]?.contains(entry.candidate) == true {
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

            let reappearQueuedAt = CFAbsoluteTimeGetCurrent()
            Task { @MainActor in
                let refreshStartedAt = CFAbsoluteTimeGetCurrent()
                // 再表示も履歴に残す。初回表示だけ記録していたので、サスペンドからの
                // 復帰が遅かった回を取り逃がしていた(ユーザ報告: 普通に開いても遅いときがある。2590)
                containerBootstrapStartedAt = reappearQueuedAt
                containerBootstrapPageEventsAtStart = containerTaskPageEvents()
                recordBootstrapTimingPart("kind=reappear")
                recordBootstrapTimingPart(
                    "reappearWaitMs=\(containerDiagnosticsElapsedMilliseconds(since: reappearQueuedAt))"
                )
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

                flushBootstrapTimingHistory(
                    totalMs: containerDiagnosticsElapsedMilliseconds(since: reappearQueuedAt)
                )
                appendContainerDiagnosticsLog(
                    "コンテナ再表示 refresh完了 elapsedMs=\(containerDiagnosticsElapsedMilliseconds(since: refreshStartedAt)) user=\(ajoutVocabularyEntries.count) learned=\(learnedDictionaryEntries.count) suppression=\(suppressionDictionaryEntries.count) shortcut=\(shortcutDictionaryEntries.count)"
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
            // 各事象が起動から何ms後に起きたかを出すための基準(2589)。所要時間だけだと
            // 「早い時点の426ms」なのか「7.9秒後の426ms」なのか区別できず、待たせている
            // 側を特定できなかった。
            // Let SwiftUI present the first frame before expensive file I/O and JSON decode.
            await Task.yield()
            let firstFrameMs = containerDiagnosticsElapsedMilliseconds(since: bootstrapStartedAt)

            // 連絡先の許可要求は起動時にはしない(設定をオンにした操作の onChange だけ。2785)。
            // 既に許可済みならキャッシュ同期は finish 側の syncContactCandidatesCacheFromContainerApp が担う

            let preludeStartedAt = CFAbsoluteTimeGetCurrent()
            // 初回インストールなら現代的初期設定に(語彙の初期投入=migration より先に判定する。3406)
            applyInitialPresetIfFreshInstall()
            applyKakikaeDefaultForExistingInstallIfNeeded()
            applyKakikaeEverydayExceptionDefaultForExistingInstallIfNeeded()
            applyLateStandardizedRewriteDefaultForExistingInstallIfNeeded()
            applyNumeralStyleDefaultForExistingInstallIfNeeded()
            applyFormalNounMeDefaultForExistingInstallIfNeeded()
            applyCompactKeyboardSwitchKeyAssignmentsForExistingInstallIfNeeded()
            normalizeLegacyKanaYaBracketValueIfNeeded()
            applyBasePresetDefaultIfNeeded()
            refreshSettingsStashSavedAt()
            clearKeyboardDiagnosticsIfInstallChanged()
            recordKeyboardExtensionRegistrationState()
            loadKeyboardDiagnosticsState()
            // firstFrameMs = 初回フレームを譲るのに掛かった時間(ここが大きいと ContentView
            // 本体の構築が重い)。preludeMs = 診断の読み書き等の前処理(2585)
            containerBootstrapStartedAt = bootstrapStartedAt
            containerBootstrapPageEventsAtStart = containerTaskPageEvents()
            recordBootstrapTimingPart("kind=firstAppear")
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
