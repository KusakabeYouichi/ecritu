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
            data.count <= maxLogDataBytes,
            let decoded = try? JSONDecoder().decode([String].self, from: data) {
            return Array(decoded.suffix(maxLogLineCount))
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

    func loadBundledInitialUserDictionaryEntries() -> [String: [String]] {
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

        let legacyDictionary = loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiShortcutVocabulary)

        if !legacyDictionary.isEmpty {
            let candidates = legacyDictionary["☻"] ?? legacyDictionary
                .keys
                .sorted()
                .flatMap { legacyDictionary[$0] ?? [] }
            return uniqueShortcutCandidatesPreservingOrder(candidates)
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

    func userDictionaryEntriesSnapshot() -> [VocabularyEntry] {
        let dictionary = normalizedDictionaryEntries(
            loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiAjoutVocabulary)
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

        return dictionary
            .keys
            .sorted()
            .flatMap { reading in
                (dictionary[reading] ?? []).map { candidate in
                    VocabularyEntry(reading: reading, candidate: candidate)
                }
            }
    }

    func shortcutDictionaryEntriesSnapshot() -> [VocabularyEntry] {
        loadShortcutVocabularyCandidates().map { candidate in
            VocabularyEntry(reading: "☻", candidate: candidate)
        }
    }

    func loadUserDictionaryEntries() {
        userDictionaryEntries = userDictionaryEntriesSnapshot()
    }

    func loadLearnedDictionaryEntries() {
        learnedDictionaryEntries = learnedDictionaryEntriesSnapshot()
    }

    func saveUserDictionary(_ entriesByReading: [String: [String]]) {
        saveDictionaryEntries(entriesByReading, forKey: SettingsKeys.kanaKanjiAjoutVocabulary)
    }

    func saveLearnedDictionary(_ entriesByReading: [String: [String]]) {
        saveDictionaryEntries(entriesByReading, forKey: SettingsKeys.kanaKanjiLearnedVocabulary)
    }

    func addUserDictionaryEntry() {
        let reading = normalizedKanaReading(from: userDictionaryReadingInput)
        let candidate = userDictionaryCandidateInput.trimmingCharacters(in: .whitespacesAndNewlines)

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
        saveUserDictionary(dictionary)

        userDictionaryReadingInput = ""
        userDictionaryCandidateInput = ""
        loadUserDictionaryEntries()
    }

    func updateUserDictionaryEntry(_ originalEntry: VocabularyEntry) {
        let reading = normalizedKanaReading(from: userDictionaryReadingInput)
        let candidate = userDictionaryCandidateInput.trimmingCharacters(in: .whitespacesAndNewlines)

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

        saveUserDictionary(dictionary)
        userDictionaryReadingInput = ""
        userDictionaryCandidateInput = ""
        loadUserDictionaryEntries()
    }

    func removeUserDictionaryEntry(_ entry: VocabularyEntry) {
        var dictionary = loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiAjoutVocabulary)

        var candidates = dictionary[entry.reading] ?? []
        candidates.removeAll { $0 == entry.candidate }

        if candidates.isEmpty {
            dictionary.removeValue(forKey: entry.reading)
        } else {
            dictionary[entry.reading] = candidates
        }

        saveUserDictionary(dictionary)
        loadUserDictionaryEntries()
    }

    func removeAllUserDictionaryEntries() {
        saveUserDictionary([:])
        loadUserDictionaryEntries()
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

    func reimportInitialUserDictionaryEntries() {
        guard let defaults = Self.sharedDefaults else {
            return
        }

        defaults.removeObject(forKey: SettingsKeys.kanaKanjiInitialUserDictionaryMigrated)
        defaults.removeObject(forKey: SettingsKeys.kanaKanjiInitialUserDictionaryAppliedSignature)
        migrateInitialUserDictionaryIfNeeded()
        loadUserDictionaryEntries()
        SettingsSyncNotification.postSettingsDidChange()
    }

    func resetKanaKanjiLearning() {
        Self.sharedDefaults?.removeObject(forKey: SettingsKeys.kanaKanjiLearningScores)
        Self.sharedDefaults?.removeObject(forKey: SettingsKeys.kanaKanjiLearnedVocabulary)
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

    func removeShortcutDictionaryEntry(_ entry: VocabularyEntry) {
        var candidates = loadShortcutVocabularyCandidates()
        candidates.removeAll { $0 == entry.candidate }
        saveShortcutVocabularyCandidates(candidates)
        loadShortcutDictionaryEntries()
    }
}
