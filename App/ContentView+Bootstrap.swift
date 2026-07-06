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

    func applyInitialDataSnapshot(_ snapshot: InitialDataSnapshot) {
        userDictionaryEntries = snapshot.userDictionaryEntries
        learnedDictionaryEntries = snapshot.learnedDictionaryEntries
        suppressionDictionaryEntries = snapshot.suppressionDictionaryEntries
        shortcutDictionaryEntries = snapshot.shortcutDictionaryEntries
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
        Task { @MainActor in
            let snapshotStartedAt = CFAbsoluteTimeGetCurrent()
            let snapshot = await loadInitialDataSnapshotInBackground()
            applyInitialDataSnapshot(snapshot)
            didCompleteInitialDataSnapshot = true

            appendContainerDiagnosticsLog(
                "\(logEventPrefix) snapshot反映完了 elapsedMs=\(containerDiagnosticsElapsedMilliseconds(since: snapshotStartedAt)) user=\(snapshot.userDictionaryEntries.count) learned=\(snapshot.learnedDictionaryEntries.count) suppression=\(snapshot.suppressionDictionaryEntries.count) shortcut=\(snapshot.shortcutDictionaryEntries.count)"
            )
            loadKeyboardDiagnosticsState()
            onCompleted?()
        }
    }

    func startInitialMigrationsAndRefreshSnapshotInBackground(onCompleted: (() -> Void)? = nil) {
        Task { @MainActor in
            let migrationStartedAt = CFAbsoluteTimeGetCurrent()
            await performInitialMigrationsInBackground()

            let migratedSnapshot = await loadInitialDataSnapshotInBackground()
            applyInitialDataSnapshot(migratedSnapshot)

            appendContainerDiagnosticsLog(
                "コンテナ初回表示 migration反映完了 elapsedMs=\(containerDiagnosticsElapsedMilliseconds(since: migrationStartedAt)) user=\(migratedSnapshot.userDictionaryEntries.count) learned=\(migratedSnapshot.learnedDictionaryEntries.count) suppression=\(migratedSnapshot.suppressionDictionaryEntries.count) shortcut=\(migratedSnapshot.shortcutDictionaryEntries.count)"
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

        let status = CNContactStore.authorizationStatus(for: .contacts)

        switch status {
        case .authorized, .limited:
            appendContainerDiagnosticsLog("連絡先アクセス状態 status=authorized")
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

        syncContactCandidatesCacheFromContainerApp()
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
        Task { @MainActor in
            await requestContactsAccessIfNeeded()
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

        guard appliedSignature != initialSignature else {
            return
        }

        let currentDictionary = normalizedDictionaryEntries(
            loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiAjoutVocabulary)
        )

        let merged = mergedDictionary(preferred: currentDictionary, fallback: initialDictionary)

        if merged != currentDictionary {
            saveDictionaryEntries(merged, forKey: SettingsKeys.kanaKanjiAjoutVocabulary)
        }

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

            requestContactsAccessIfNeededInBackground()

            clearLegacyKeyboardDebugLogKeysIfNeeded()
            migrateLegacyFlickGuideSettingIfNeeded()
            clearKeyboardDiagnosticsIfInstallChanged()
            loadKeyboardDiagnosticsState()
            appendContainerDiagnosticsLog("コンテナ初回表示 bootstrap開始")
            startInitialSnapshotLoadInBackground(logEventPrefix: "コンテナ初回表示") {
                startInitialMigrationsAndRefreshSnapshotInBackground {
                    appendContainerDiagnosticsLog(
                        "コンテナ初回表示 bootstrap完了 elapsedMs=\(containerDiagnosticsElapsedMilliseconds(since: bootstrapStartedAt))"
                    )
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
