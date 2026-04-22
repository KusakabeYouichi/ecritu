import Foundation

private struct KanaKanjiInflectionEntry: Codable {
    let candidate: String
    let inflectionClass: String
}

final class KanaKanjiStore {
    private let appGroupID: String
    private let defaults: UserDefaults?
    private let fileManager = FileManager.default
    private static let initialLearningScores: [String: Int] = [
        "かった\t交った": -1_000_000_000,
        "かった\t支った": -1_000_000_000
    ]
    private var cachedSystemDictionary: [String: [String]]?
    private var cachedSystemCandidateSources: [String: [String: Set<String>]]?
    private var cachedInflectionDictionary: [String: [String: String]]?
    private var cachedInitialUserDictionary: [String: [String]]?
    private var cachedUserDictionary: [String: [String]]?
    private var cachedLearningScores: [String: Int]?

    init(appGroupID: String) {
        self.appGroupID = appGroupID
        self.defaults = UserDefaults(suiteName: appGroupID)
    }

    func loadSystemDictionary() -> [String: [String]] {
        if let cachedSystemDictionary {
            return cachedSystemDictionary
        }

        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            return [:]
        }

        let systemDictionaryURL = containerURL
            .appendingPathComponent(KanaKanjiStorageKeys.systemDictionaryFilename)

        guard let data = try? Data(contentsOf: systemDictionaryURL),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            return [:]
        }

        // The generated Sudachi index is already normalized to hiragana readings.
        cachedSystemDictionary = decoded
        return decoded
    }

    func loadSystemCandidateSources() -> [String: [String: Set<String>]] {
        if let cachedSystemCandidateSources {
            return cachedSystemCandidateSources
        }

        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            return [:]
        }

        let sourceDictionaryURL = containerURL
            .appendingPathComponent(KanaKanjiStorageKeys.systemCandidateSourcesFilename)

        guard let data = try? Data(contentsOf: sourceDictionaryURL),
              let decoded = try? JSONDecoder().decode([String: [String: [String]]].self, from: data) else {
            return [:]
        }

        var normalized: [String: [String: Set<String>]] = [:]

        for (reading, candidateMap) in decoded {
            var sourceMap: [String: Set<String>] = [:]

            for (candidate, rawSources) in candidateMap {
                var sources: Set<String> = []

                for source in rawSources {
                    if source == "normalized" || source == "surface" {
                        sources.insert(source)
                    }
                }

                if !sources.isEmpty {
                    sourceMap[candidate] = sources
                }
            }

            if !sourceMap.isEmpty {
                normalized[reading] = sourceMap
            }
        }

        cachedSystemCandidateSources = normalized
        return normalized
    }

    func loadInflectionDictionary() -> [String: [String: String]] {
        if let cachedInflectionDictionary {
            return cachedInflectionDictionary
        }

        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            return [:]
        }

        let inflectionDictionaryURL = containerURL
            .appendingPathComponent(KanaKanjiStorageKeys.inflectionDictionaryFilename)

        guard let data = try? Data(contentsOf: inflectionDictionaryURL),
              let decoded = try? JSONDecoder().decode([String: [KanaKanjiInflectionEntry]].self, from: data) else {
            return [:]
        }

        var inflectionMap: [String: [String: String]] = [:]

        for (reading, entries) in decoded {
            var candidateClassMap: [String: String] = inflectionMap[reading] ?? [:]

            for entry in entries {
                let candidate = entry.candidate.trimmingCharacters(in: .whitespacesAndNewlines)

                guard !candidate.isEmpty,
                      !entry.inflectionClass.isEmpty else {
                    continue
                }

                candidateClassMap[candidate] = entry.inflectionClass
            }

            if !candidateClassMap.isEmpty {
                inflectionMap[reading] = candidateClassMap
            }
        }

        cachedInflectionDictionary = inflectionMap
        return inflectionMap
    }

    func userDictionary() -> [String: [String]] {
        if let cachedUserDictionary {
            return cachedUserDictionary
        }

        guard let decoded = decodedStringArrayDictionary(forKey: KanaKanjiStorageKeys.userDictionary) else {
            cachedUserDictionary = [:]
            return [:]
        }

        let normalized = normalizeDictionary(decoded)
        cachedUserDictionary = normalized
        return normalized
    }

    func initialUserDictionary() -> [String: [String]] {
        if let cachedInitialUserDictionary {
            return cachedInitialUserDictionary
        }

        let bundle = Bundle(for: KanaKanjiStore.self)

        guard let initialDictionaryURL = bundle.url(
            forResource: KanaKanjiStorageKeys.initialUserDictionaryResourceName,
            withExtension: "json"
        ),
            let data = try? Data(contentsOf: initialDictionaryURL),
            let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            cachedInitialUserDictionary = [:]
            return [:]
        }

        let normalized = normalizeDictionary(decoded)
        cachedInitialUserDictionary = normalized
        return normalized
    }

    func suppressedCandidatesByReading() -> [String: Set<String>] {
        guard let decodedDictionary = decodedStringArrayDictionary(
            forKey: KanaKanjiStorageKeys.suppressionVocabulary
        ) else {
            return [:]
        }

        var result: [String: Set<String>] = [:]

        for (reading, candidates) in decodedDictionary {
            let normalizedReading = KanaTextNormalizer.normalizedReading(reading)

            guard !normalizedReading.isEmpty else {
                continue
            }

            var filteredCandidates = result[normalizedReading] ?? []

            for candidate in candidates {
                let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

                guard !trimmed.isEmpty else {
                    continue
                }

                filteredCandidates.insert(trimmed)
            }

            if !filteredCandidates.isEmpty {
                result[normalizedReading] = filteredCandidates
            }
        }

        return result
    }

    func addUserEntry(reading: String, candidate: String) {
        let normalizedReading = KanaTextNormalizer.normalizedReading(reading)
        let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedReading.isEmpty,
              !trimmedCandidate.isEmpty else {
            return
        }

        var dictionary = userDictionary()
        var candidates = dictionary[normalizedReading] ?? []

        if let existingIndex = candidates.firstIndex(of: trimmedCandidate) {
            candidates.remove(at: existingIndex)
        }

        candidates.insert(trimmedCandidate, at: 0)
        dictionary[normalizedReading] = Array(candidates.prefix(32))
        cachedUserDictionary = dictionary
        saveUserDictionary(dictionary)
    }

    func learningScores() -> [String: Int] {
        if let cachedLearningScores {
            return cachedLearningScores
        }

        guard let defaults,
              let learningData = defaults.data(forKey: KanaKanjiStorageKeys.learningScores),
              let decoded = try? JSONDecoder().decode([String: Int].self, from: learningData) else {
            cachedLearningScores = Self.initialLearningScores
            return Self.initialLearningScores
        }

        var scores = decoded

        // Ensure rare candidates stay at the very bottom even when old learning data exists.
        for (key, value) in Self.initialLearningScores {
            if let existing = scores[key] {
                scores[key] = min(existing, value)
            } else {
                scores[key] = value
            }
        }

        cachedLearningScores = scores

        if let encoded = try? JSONEncoder().encode(scores) {
            defaults.set(encoded, forKey: KanaKanjiStorageKeys.learningScores)
        }

        return scores
    }

    func incrementLearning(reading: String, candidate: String) {
        let normalizedReading = KanaTextNormalizer.normalizedReading(reading)
        let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedReading.isEmpty,
              !trimmedCandidate.isEmpty else {
            return
        }

        var scores = learningScores()
        let key = learningKey(reading: normalizedReading, candidate: trimmedCandidate)
        scores[key, default: 0] += 1
        cachedLearningScores = scores

        guard let defaults,
              let encoded = try? JSONEncoder().encode(scores) else {
            return
        }

        defaults.set(encoded, forKey: KanaKanjiStorageKeys.learningScores)
    }

    private func saveUserDictionary(_ dictionary: [String: [String]]) {
        guard let defaults,
              let encoded = try? JSONEncoder().encode(dictionary) else {
            return
        }

        defaults.set(encoded, forKey: KanaKanjiStorageKeys.userDictionary)
    }

    private func decodedStringArrayDictionary(forKey key: String) -> [String: [String]]? {
        guard let defaults else {
            return nil
        }

        if let dictionaryData = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: [String]].self, from: dictionaryData) {
            return decoded
        }

        guard let rawDictionary = defaults.dictionary(forKey: key) else {
            return nil
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

    private func normalizeDictionary(_ dictionary: [String: [String]]) -> [String: [String]] {
        var normalized: [String: [String]] = [:]

        for (reading, candidates) in dictionary {
            let normalizedReading = KanaTextNormalizer.normalizedReading(reading)

            guard !normalizedReading.isEmpty else {
                continue
            }

            let mergedCandidates = (normalized[normalizedReading] ?? []) + candidates
            normalized[normalizedReading] = uniqueCandidates(from: mergedCandidates)
        }

        return normalized
    }

    private func uniqueCandidates(from candidates: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmed.isEmpty,
                  !seen.contains(trimmed) else {
                continue
            }

            seen.insert(trimmed)
            result.append(trimmed)
        }

        return result
    }

    private func learningKey(reading: String, candidate: String) -> String {
        reading + "\t" + candidate
    }
}
