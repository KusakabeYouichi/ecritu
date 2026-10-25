import SwiftUI
import UIKit
import CoreFoundation
import Darwin
import Contacts

extension ContentView {
    func normalizedKanaReading(from text: String) -> String {
        var result = ""

        for character in text {
            let source = String(character)
            let normalized = source.applyingTransform(.hiraganaToKatakana, reverse: true) ?? source

            guard normalized.count == 1,
                    let first = normalized.first,
                    let scalar = String(first).unicodeScalars.first else {
                continue
            }

            if (0x3040...0x309F).contains(scalar.value) || scalar.value == 0x30FC {
                result.append(first)
            }
        }

        return result
    }

    func loadDictionaryEntries(forKey key: String) -> [String: [String]] {
        guard let defaults = Self.sharedDefaults else {
            return [:]
        }

        if let dictionaryData = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode([String: [String]].self, from: dictionaryData) {
            return decoded
        }

        guard let rawDictionary = defaults.dictionary(forKey: key) else {
            return [:]
        }

        var decoded: [String: [String]] = [:]

        for (reading, rawCandidates) in rawDictionary {
            if let candidates = rawCandidates as? [String] {
                decoded[reading] = candidates
            } else if let candidates = rawCandidates as? [Any] {
                decoded[reading] = candidates.compactMap { $0 as? String }
            }
        }

        return decoded
    }

    func decodeStringArray(forKey key: String, defaults: UserDefaults) -> [String] {
        let maxLogDataBytes = 262_144
        let maxLogLineCount = 320

        if let data = defaults.data(forKey: key),
            data.count <= maxLogDataBytes {
            // 旧 JSON 配列("[" 始まり)と 2707 以降の改行区切りテキストの両形式
            if data.first == UInt8(ascii: "["),
                let decoded = try? JSONDecoder().decode([String].self, from: data) {
                return Array(decoded.suffix(maxLogLineCount))
            }
            let lines = String(decoding: data, as: UTF8.self)
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map(String.init)
            if !lines.isEmpty {
                return Array(lines.suffix(maxLogLineCount))
            }
        }

        if let data = defaults.data(forKey: key),
            data.count > maxLogDataBytes {
            defaults.removeObject(forKey: key)
            return []
        }

        if let raw = defaults.array(forKey: key) {
            return Array(raw.compactMap { $0 as? String }.suffix(maxLogLineCount))
        }

        return []
    }

    func loadLearningScores() -> [String: Int] {
        guard let defaults = Self.sharedDefaults,
            let learningData = defaults.data(forKey: SettingsKeys.kanaKanjiLearningScores),
            let decoded = try? JSONDecoder().decode([String: Int].self, from: learningData) else {
            return [:]
        }

        return decoded
    }

    func parseLearningKey(_ key: String) -> VocabularyEntry? {
        guard let separatorIndex = key.firstIndex(of: "\t") else {
            return nil
        }

        let readingRaw = String(key[..<separatorIndex])
        let candidateStartIndex = key.index(after: separatorIndex)
        let candidateRaw = String(key[candidateStartIndex...])
        let reading = normalizedKanaReading(from: readingRaw)
        let candidate = candidateRaw.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !reading.isEmpty,
            !candidate.isEmpty else {
            return nil
        }

        return VocabularyEntry(reading: reading, candidate: candidate)
    }

    func uniqueCandidatesPreservingOrder(_ candidates: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmed.isEmpty,
                    seen.insert(trimmed).inserted else {
                continue
            }

            result.append(trimmed)
        }

        return result
    }

    func uniqueShortcutCandidatesPreservingOrder(_ candidates: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for candidate in candidates {
            guard !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                seen.insert(candidate).inserted else {
                continue
            }

            result.append(candidate)
        }

        return result
    }

    func normalizedDictionaryEntries(_ dictionary: [String: [String]]) -> [String: [String]] {
        var normalized: [String: [String]] = [:]

        for (reading, candidates) in dictionary {
            let normalizedReading = normalizedKanaReading(from: reading)

            guard !normalizedReading.isEmpty else {
                continue
            }

            let mergedCandidates = uniqueCandidatesPreservingOrder(
                (normalized[normalizedReading] ?? []) + candidates
            )

            if !mergedCandidates.isEmpty {
                normalized[normalizedReading] = mergedCandidates
            }
        }

        return normalized
    }

    func mergedDictionary(
        preferred: [String: [String]],
        fallback: [String: [String]]
    ) -> [String: [String]] {
        var merged = fallback

        for (reading, preferredCandidates) in preferred {
            let combined = uniqueCandidatesPreservingOrder(
                preferredCandidates + (fallback[reading] ?? [])
            )

            if combined.isEmpty {
                merged.removeValue(forKey: reading)
            } else {
                merged[reading] = combined
            }
        }

        return merged
    }

    func dictionarySignature(_ dictionary: [String: [String]]) -> String {
        let normalized = normalizedDictionaryEntries(dictionary)

        guard !normalized.isEmpty else {
            return "empty"
        }

        guard let data = try? JSONSerialization.data(
            withJSONObject: normalized,
            options: [.sortedKeys]
        ) else {
            return "encoding-error"
        }

        var hash: UInt64 = 0xcbf29ce484222325

        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }

        return String(format: "%016llx", hash)
    }

    func loadBundledInitialDictionaryEntries(filename: String) -> [String: [String]] {
        let fileExtension = "json"

        if let resourceURL = Bundle.main.url(forResource: filename, withExtension: fileExtension),
            let data = try? Data(contentsOf: resourceURL),
            let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            return normalizedDictionaryEntries(decoded)
        }

        if let pluginsURL = Bundle.main.builtInPlugInsURL,
            let pluginURLs = try? FileManager.default.contentsOfDirectory(
                at: pluginsURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
            for pluginURL in pluginURLs where pluginURL.pathExtension == "appex" {
                let resourceURL = pluginURL.appendingPathComponent("\(filename).\(fileExtension)")

                guard FileManager.default.fileExists(atPath: resourceURL.path),
                        let data = try? Data(contentsOf: resourceURL),
                        let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
                    continue
                }

                return normalizedDictionaryEntries(decoded)
            }
        }

        return [:]
    }

    func loadBundledInitialAjoutVocabularyEntries() -> [String: [String]] {
        loadBundledInitialDictionaryEntries(filename: "InitialAjoutVocabMigration")
    }

    func loadBundledInitialSuppressionDictionaryEntries() -> [String: [String]] {
        loadBundledInitialDictionaryEntries(filename: "InitialSupprVocabMigration")
    }

    func loadBundledInitialShortcutVocabularyEntries() -> [String] {
        let fileExtension = "json"
        let filename = "InitialShortcutVocabMigration"

        if let resourceURL = Bundle.main.url(forResource: filename, withExtension: fileExtension),
            let data = try? Data(contentsOf: resourceURL),
            let decoded = try? JSONDecoder().decode([String].self, from: data) {
            return uniqueShortcutCandidatesPreservingOrder(decoded)
        }

        if let pluginsURL = Bundle.main.builtInPlugInsURL,
            let pluginURLs = try? FileManager.default.contentsOfDirectory(
                at: pluginsURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
            for pluginURL in pluginURLs where pluginURL.pathExtension == "appex" {
                let resourceURL = pluginURL.appendingPathComponent("\(filename).\(fileExtension)")

                guard FileManager.default.fileExists(atPath: resourceURL.path),
                    let data = try? Data(contentsOf: resourceURL),
                    let decoded = try? JSONDecoder().decode([String].self, from: data) else {
                    continue
                }

                return uniqueShortcutCandidatesPreservingOrder(decoded)
            }
        }

        return []
    }

    func loadShortcutVocabularyCandidates() -> [String] {
        guard let defaults = Self.sharedDefaults else {
            return []
        }

        if let shortcutData = defaults.data(forKey: SettingsKeys.kanaKanjiShortcutVocabulary),
            let decoded = try? JSONDecoder().decode([String].self, from: shortcutData) {
            return uniqueShortcutCandidatesPreservingOrder(decoded)
        }

        if let rawArray = defaults.array(forKey: SettingsKeys.kanaKanjiShortcutVocabulary) {
            return uniqueShortcutCandidatesPreservingOrder(rawArray.compactMap { $0 as? String })
        }

        return []
    }

    func saveShortcutVocabularyCandidates(_ candidates: [String]) {
        guard let defaults = Self.sharedDefaults,
            let encoded = try? JSONEncoder().encode(candidates) else {
            return
        }

        defaults.set(encoded, forKey: SettingsKeys.kanaKanjiShortcutVocabulary)
        SettingsSyncNotification.postSettingsDidChange()
    }

    func loadAppGroupDictionaryEntries(filename: String) -> [String: [String]] {
        guard
            let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: SettingsKeys.appGroupID
            )
        else {
            return [:]
        }

        let fileURL = containerURL.appendingPathComponent(filename)

        guard
            let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode([String: [String]].self, from: data)
        else {
            return [:]
        }

        return normalizedDictionaryEntries(decoded)
    }

    func sortedVocabularyEntries(from dictionary: [String: [String]]) -> [VocabularyEntry] {
        dictionary
            .keys
            .sorted()
            .flatMap { reading in
                (dictionary[reading] ?? []).map { candidate in
                    VocabularyEntry(reading: reading, candidate: candidate)
                }
            }
    }

    func firstSystemVocabularyEntriesSnapshot() -> [VocabularyEntry] {
        let firstFromAppGroup = loadAppGroupDictionaryEntries(filename: "ÉcrituPremierVocab.json")
        let firstDictionary = firstFromAppGroup.isEmpty
            ? loadBundledInitialDictionaryEntries(filename: "ÉcrituPremierVocab")
            : firstFromAppGroup

        return sortedVocabularyEntries(from: firstDictionary)
    }

    func secondSystemVocabularyEntriesSnapshot() -> [VocabularyEntry] {
        let secondFromAppGroup = loadAppGroupDictionaryEntries(filename: "ÉcrituSecondVocab.json")
        let secondDictionary = secondFromAppGroup.isEmpty
            ? loadBundledInitialDictionaryEntries(filename: "ÉcrituSecondVocab")
            : secondFromAppGroup

        return sortedVocabularyEntries(from: secondDictionary)
    }

    func saveStringArray(_ values: [String], forKey key: String, defaults: UserDefaults) {
        if let encoded = try? JSONEncoder().encode(values) {
            defaults.set(encoded, forKey: key)
            return
        }

        defaults.set(values, forKey: key)
    }

    func saveDictionaryEntries(_ entriesByReading: [String: [String]], forKey key: String) {
        guard let defaults = Self.sharedDefaults,
                let encoded = try? JSONEncoder().encode(entriesByReading) else {
            return
        }

        defaults.set(encoded, forKey: key)
        SettingsSyncNotification.postSettingsDidChange()
    }

    func ajoutVocabularyEntriesSnapshot() -> [VocabularyEntry] {
        let dictionary = normalizedDictionaryEntries(
            loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiAjoutVocabulary)
        )
        let userRegistered = userRegisteredAjoutVocabulary()

        return dictionary
            .keys
            .sorted()
            .flatMap { reading in
                (dictionary[reading] ?? []).map { candidate in
                    VocabularyEntry(
                        reading: reading,
                        candidate: candidate,
                        isUserRegistered: userRegistered[reading]?.contains(candidate) == true
                    )
                }
            }
    }

    // 自分で登録した語の記録(追加語彙 3778・抑制語彙 3563。キーの説明は SettingsKeys 参照)
    func userRegisteredEntries(forKey key: String) -> [String: [String]] {
        normalizedDictionaryEntries(loadDictionaryEntries(forKey: key))
    }

    func updateUserRegisteredEntries(forKey key: String, adding added: VocabularyEntry?, removing removed: VocabularyEntry?) {
        var dictionary = userRegisteredEntries(forKey: key)
        if let removed {
            let kept = (dictionary[removed.reading] ?? []).filter { $0 != removed.candidate }
            dictionary[removed.reading] = kept.isEmpty ? nil : kept
        }
        if let added, dictionary[added.reading]?.contains(added.candidate) != true {
            dictionary[added.reading, default: []].append(added.candidate)
        }
        saveDictionaryEntries(dictionary, forKey: key)
    }

    // 記録を始める前から入っていた語の振り分けを 1 回だけ行う。初期語彙(同梱の一覧)に無いものを
    // 自分で登録したものとみなす。初期語彙と同じ語を自分でも登録していた場合は区別できず、初期語彙の側になる
    func backfillUserRegisteredEntriesIfNeeded(
        vocabularyKey: String,
        registeredKey: String,
        backfilledKey: String,
        initial: [String: [String]]
    ) {
        guard let defaults = Self.sharedDefaults,
            !defaults.bool(forKey: backfilledKey) else {
            return
        }
        guard !initial.isEmpty else {
            return
        }
        var dictionary = userRegisteredEntries(forKey: registeredKey)
        let current = normalizedDictionaryEntries(loadDictionaryEntries(forKey: vocabularyKey))
        for (reading, candidates) in current {
            let initialCandidates = Set(initial[reading] ?? [])
            for candidate in candidates where !initialCandidates.contains(candidate)
                && dictionary[reading]?.contains(candidate) != true {
                dictionary[reading, default: []].append(candidate)
            }
        }
        saveDictionaryEntries(dictionary, forKey: registeredKey)
        defaults.set(true, forKey: backfilledKey)
    }

    func userRegisteredAjoutVocabulary() -> [String: [String]] {
        userRegisteredEntries(forKey: SettingsKeys.kanaKanjiUserRegisteredAjoutVocabulary)
    }

    func updateUserRegisteredAjoutVocabulary(adding added: VocabularyEntry?, removing removed: VocabularyEntry?) {
        updateUserRegisteredEntries(forKey: SettingsKeys.kanaKanjiUserRegisteredAjoutVocabulary, adding: added, removing: removed)
    }

    func backfillUserRegisteredAjoutVocabularyIfNeeded() {
        backfillUserRegisteredEntriesIfNeeded(
            vocabularyKey: SettingsKeys.kanaKanjiAjoutVocabulary,
            registeredKey: SettingsKeys.kanaKanjiUserRegisteredAjoutVocabulary,
            backfilledKey: SettingsKeys.kanaKanjiUserRegisteredAjoutVocabularyBackfilled,
            initial: loadBundledInitialAjoutVocabularyEntries()
        )
    }

    func updateUserRegisteredSuppressionVocabulary(adding added: VocabularyEntry?, removing removed: VocabularyEntry?) {
        updateUserRegisteredEntries(forKey: SettingsKeys.kanaKanjiUserRegisteredSuppressionVocabulary, adding: added, removing: removed)
    }

    func backfillUserRegisteredSuppressionVocabularyIfNeeded() {
        backfillUserRegisteredEntriesIfNeeded(
            vocabularyKey: SettingsKeys.kanaKanjiSuppressionVocabulary,
            registeredKey: SettingsKeys.kanaKanjiUserRegisteredSuppressionVocabulary,
            backfilledKey: SettingsKeys.kanaKanjiUserRegisteredSuppressionVocabularyBackfilled,
            initial: loadBundledInitialSuppressionDictionaryEntries()
        )
    }

    func learnedDictionaryEntriesSnapshot() -> [VocabularyEntry] {
        let dictionary = normalizedDictionaryEntries(
            loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiLearnedVocabulary)
        )

        return dictionary
            .keys
            .sorted()
            .flatMap { reading in
                (dictionary[reading] ?? []).map { candidate in
                    VocabularyEntry(reading: reading, candidate: candidate)
                }
            }
    }

    func suppressionDictionaryEntriesSnapshot() -> [VocabularyEntry] {
        let dictionary = loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiSuppressionVocabulary)
        let userRegistered = userRegisteredEntries(forKey: SettingsKeys.kanaKanjiUserRegisteredSuppressionVocabulary)

        return dictionary
            .keys
            .sorted()
            .flatMap { reading in
                let registered = userRegistered[normalizedKanaReading(from: reading)] ?? []
                return (dictionary[reading] ?? []).map { candidate in
                    VocabularyEntry(
                        reading: reading,
                        candidate: candidate,
                        isUserRegistered: registered.contains(candidate)
                    )
                }
            }
    }

    func shortcutDictionaryEntriesSnapshot() -> [VocabularyEntry] {
        loadShortcutVocabularyCandidates().map { candidate in
            VocabularyEntry(reading: "☻", candidate: candidate)
        }
    }

    func loadAjoutVocabularyEntries() {
        ajoutVocabularyEntries = ajoutVocabularyEntriesSnapshot()
    }

    func loadLearnedDictionaryEntries() {
        learnedDictionaryEntries = learnedDictionaryEntriesSnapshot()
    }

    func saveAjoutVocabulary(_ entriesByReading: [String: [String]]) {
        saveDictionaryEntries(entriesByReading, forKey: SettingsKeys.kanaKanjiAjoutVocabulary)
    }

    func saveLearnedDictionary(_ entriesByReading: [String: [String]]) {
        saveDictionaryEntries(entriesByReading, forKey: SettingsKeys.kanaKanjiLearnedVocabulary)
    }

    func addAjoutVocabularyEntry() {
        let reading = normalizedKanaReading(from: ajoutVocabularyReadingInput)
        let candidate = ajoutVocabularyCandidateInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !reading.isEmpty,
                !candidate.isEmpty else {
            return
        }

        var dictionary = loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiAjoutVocabulary)

        var candidates = dictionary[reading] ?? []

        if let existingIndex = candidates.firstIndex(of: candidate) {
            candidates.remove(at: existingIndex)
        }

        candidates.insert(candidate, at: 0)
        dictionary[reading] = Array(candidates.prefix(32))
        saveAjoutVocabulary(dictionary)
        updateUserRegisteredAjoutVocabulary(adding: VocabularyEntry(reading: reading, candidate: candidate), removing: nil)

        ajoutVocabularyReadingInput = ""
        ajoutVocabularyCandidateInput = ""
        loadAjoutVocabularyEntries()
    }

    func updateAjoutVocabularyEntry(_ originalEntry: VocabularyEntry) {
        let reading = normalizedKanaReading(from: ajoutVocabularyReadingInput)
        let candidate = ajoutVocabularyCandidateInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !reading.isEmpty,
            !candidate.isEmpty else {
            return
        }

        var dictionary = loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiAjoutVocabulary)

        var originalCandidates = dictionary[originalEntry.reading] ?? []
        originalCandidates.removeAll { $0 == originalEntry.candidate }

        if originalCandidates.isEmpty {
            dictionary.removeValue(forKey: originalEntry.reading)
        } else {
            dictionary[originalEntry.reading] = originalCandidates
        }

        var targetCandidates = dictionary[reading] ?? []

        if let existingIndex = targetCandidates.firstIndex(of: candidate) {
            targetCandidates.remove(at: existingIndex)
        }

        targetCandidates.insert(candidate, at: 0)
        dictionary[reading] = Array(targetCandidates.prefix(32))

        saveAjoutVocabulary(dictionary)
        // 編集した語は初期語彙だったものでも自分で登録したものとして扱う
        updateUserRegisteredAjoutVocabulary(adding: VocabularyEntry(reading: reading, candidate: candidate), removing: originalEntry)
        ajoutVocabularyReadingInput = ""
        ajoutVocabularyCandidateInput = ""
        loadAjoutVocabularyEntries()
    }

    func removeAjoutVocabularyEntry(_ entry: VocabularyEntry) {
        var dictionary = loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiAjoutVocabulary)

        var candidates = dictionary[entry.reading] ?? []
        candidates.removeAll { $0 == entry.candidate }

        if candidates.isEmpty {
            dictionary.removeValue(forKey: entry.reading)
        } else {
            dictionary[entry.reading] = candidates
        }

        saveAjoutVocabulary(dictionary)
        updateUserRegisteredAjoutVocabulary(adding: nil, removing: entry)
        loadAjoutVocabularyEntries()
    }

    func removeAllAjoutVocabularyEntries() {
        saveAjoutVocabulary([:])
        saveDictionaryEntries([:], forKey: SettingsKeys.kanaKanjiUserRegisteredAjoutVocabulary)
        loadAjoutVocabularyEntries()
    }

    func removeLearnedDictionaryEntry(_ entry: VocabularyEntry) {
        var dictionary = loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiLearnedVocabulary)
        var candidates = dictionary[entry.reading] ?? []
        candidates.removeAll { $0 == entry.candidate }

        if candidates.isEmpty {
            dictionary.removeValue(forKey: entry.reading)
        } else {
            dictionary[entry.reading] = candidates
        }

        saveLearnedDictionary(dictionary)
        loadLearnedDictionaryEntries()
    }

    func removeAllLearnedDictionaryEntries() {
        saveLearnedDictionary([:])
        loadLearnedDictionaryEntries()
    }

    func reimportInitialAjoutVocabularyEntries() {
        guard let defaults = Self.sharedDefaults else {
            return
        }

        defaults.removeObject(forKey: SettingsKeys.kanaKanjiInitialAjoutVocabularyMigrated)
        defaults.removeObject(forKey: SettingsKeys.kanaKanjiInitialAjoutVocabularyAppliedSignature)
        migrateInitialAjoutVocabularyIfNeeded()
        loadAjoutVocabularyEntries()
        SettingsSyncNotification.postSettingsDidChange()
    }

    func resetKanaKanjiLearning() {
        Self.sharedDefaults?.removeObject(forKey: SettingsKeys.kanaKanjiLearningScores)
        Self.sharedDefaults?.removeObject(forKey: SettingsKeys.kanaKanjiLearnedVocabulary)
        // 学習リセット専用の世代を上げる(定数コメント参照。2968)。これを見たキーボードは
        // プロセス内の学習キャッシュを「書き出さずに」捨てる。上げないと、拡張が持っている
        // リセット前の学習が clearSharedDataCaches の書き出しで共有領域へ戻り、リセットが
        // 取り消される(実機ログで拡張プロセスが作り直されないまま復活するのを確認)
        if let defaults = Self.sharedDefaults {
            let next = defaults.integer(forKey: SettingsKeys.learningResetGeneration) &+ 1
            defaults.set(next, forKey: SettingsKeys.learningResetGeneration)
        }
        loadLearnedDictionaryEntries()
        SettingsSyncNotification.postSettingsDidChange()
    }

    func loadSuppressionDictionaryEntries() {
        suppressionDictionaryEntries = suppressionDictionaryEntriesSnapshot()
    }

    func saveSuppressionDictionary(_ entriesByReading: [String: [String]]) {
        saveDictionaryEntries(entriesByReading, forKey: SettingsKeys.kanaKanjiSuppressionVocabulary)
    }

    func addSuppressionDictionaryEntry() {
        let reading = normalizedKanaReading(from: suppressionDictionaryReadingInput)
        let candidate = suppressionDictionaryCandidateInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !reading.isEmpty,
                !candidate.isEmpty else {
            return
        }

        var dictionary = loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiSuppressionVocabulary)
        var candidates = dictionary[reading] ?? []

        if let existingIndex = candidates.firstIndex(of: candidate) {
            candidates.remove(at: existingIndex)
        }

        candidates.insert(candidate, at: 0)
        dictionary[reading] = Array(candidates.prefix(128))
        saveSuppressionDictionary(dictionary)
        updateUserRegisteredSuppressionVocabulary(adding: VocabularyEntry(reading: reading, candidate: candidate), removing: nil)

        suppressionDictionaryReadingInput = ""
        suppressionDictionaryCandidateInput = ""
        loadSuppressionDictionaryEntries()
    }

    func updateSuppressionDictionaryEntry(_ originalEntry: VocabularyEntry) {
        let reading = normalizedKanaReading(from: suppressionDictionaryReadingInput)
        let candidate = suppressionDictionaryCandidateInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !reading.isEmpty,
            !candidate.isEmpty else {
            return
        }

        var dictionary = loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiSuppressionVocabulary)

        var originalCandidates = dictionary[originalEntry.reading] ?? []
        originalCandidates.removeAll { $0 == originalEntry.candidate }

        if originalCandidates.isEmpty {
            dictionary.removeValue(forKey: originalEntry.reading)
        } else {
            dictionary[originalEntry.reading] = originalCandidates
        }

        var targetCandidates = dictionary[reading] ?? []

        if let existingIndex = targetCandidates.firstIndex(of: candidate) {
            targetCandidates.remove(at: existingIndex)
        }

        targetCandidates.insert(candidate, at: 0)
        dictionary[reading] = Array(targetCandidates.prefix(128))

        saveSuppressionDictionary(dictionary)
        // 編集した語は初期語彙だったものでも自分で登録したものとして扱う(追加語彙と同じ)
        updateUserRegisteredSuppressionVocabulary(adding: VocabularyEntry(reading: reading, candidate: candidate), removing: originalEntry)
        suppressionDictionaryReadingInput = ""
        suppressionDictionaryCandidateInput = ""
        loadSuppressionDictionaryEntries()
    }

    func removeSuppressionDictionaryEntry(_ entry: VocabularyEntry) {
        var dictionary = loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiSuppressionVocabulary)
        var candidates = dictionary[entry.reading] ?? []
        candidates.removeAll { $0 == entry.candidate }

        if candidates.isEmpty {
            dictionary.removeValue(forKey: entry.reading)
        } else {
            dictionary[entry.reading] = candidates
        }

        saveSuppressionDictionary(dictionary)
        updateUserRegisteredSuppressionVocabulary(adding: nil, removing: entry)
        loadSuppressionDictionaryEntries()
    }

    func loadShortcutDictionaryEntries() {
        shortcutDictionaryEntries = shortcutDictionaryEntriesSnapshot()
    }

    func addShortcutDictionaryEntry() {
        let candidate = shortcutDictionaryCandidateInput

        guard !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        var candidates = loadShortcutVocabularyCandidates()

        if let existingIndex = candidates.firstIndex(of: candidate) {
            candidates.remove(at: existingIndex)
        }

        candidates.insert(candidate, at: 0)
        saveShortcutVocabularyCandidates(Array(candidates.prefix(128)))

        shortcutDictionaryCandidateInput = ""
        loadShortcutDictionaryEntries()
    }

    func updateShortcutDictionaryEntry(_ originalEntry: VocabularyEntry) {
        let candidate = shortcutDictionaryCandidateInput

        guard !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        var candidates = loadShortcutVocabularyCandidates()
        candidates.removeAll { $0 == originalEntry.candidate }

        if let existingIndex = candidates.firstIndex(of: candidate) {
            candidates.remove(at: existingIndex)
        }

        candidates.insert(candidate, at: 0)
        saveShortcutVocabularyCandidates(Array(candidates.prefix(128)))

        shortcutDictionaryCandidateInput = ""
        loadShortcutDictionaryEntries()
    }

    // 並べ替え(3243)。保存順が表示順なので、動かした瞬間に共有領域へ書く
    func moveShortcutDictionaryEntries(fromOffsets source: IndexSet, toOffset destination: Int) {
        var candidates = loadShortcutVocabularyCandidates()
        candidates.move(fromOffsets: source, toOffset: destination)
        saveShortcutVocabularyCandidates(candidates)
        loadShortcutDictionaryEntries()
    }

    // iOS のユーザ辞書から取り込んだ ☻ 語を外して記録を消す(拡張の KanaKanjiStore と同じ処理)
    func removeImportedUserDictionaryShortcutCandidates() {
        guard let defaults = Self.sharedDefaults,
            let data = defaults.data(forKey: SettingsKeys.kanaKanjiUserDictionaryShortcutImportedCandidates) else {
            return
        }
        defaults.removeObject(forKey: SettingsKeys.kanaKanjiUserDictionaryShortcutImportedCandidates)
        let imported = Set((try? JSONDecoder().decode([String].self, from: data)) ?? [])
        guard !imported.isEmpty else {
            return
        }
        let current = loadShortcutVocabularyCandidates()
        let kept = current.filter { !imported.contains($0) }
        guard kept.count != current.count else {
            return
        }
        saveShortcutVocabularyCandidates(kept)
        loadShortcutDictionaryEntries()
    }

    func removeShortcutDictionaryEntry(_ entry: VocabularyEntry) {
        var candidates = loadShortcutVocabularyCandidates()
        candidates.removeAll { $0 == entry.candidate }
        saveShortcutVocabularyCandidates(candidates)
        loadShortcutDictionaryEntries()
    }
}
