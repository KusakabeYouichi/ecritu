import Foundation
import SQLite3

private struct KanaKanjiInflectionEntry: Codable {
    let candidate: String
    let inflectionClass: String
}

private let sqliteTransientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private final class KanaKanjiSQLiteIndex {
    private let queryQueue = DispatchQueue(label: "com.kusakabe.ecritu.kana-kanji.sqlite-index")
    private var database: OpaquePointer?
    private var selectCandidatesStatement: OpaquePointer?
    private var selectCandidatesBySourceStatement: OpaquePointer?
    private var selectInflectionStatement: OpaquePointer?
    private(set) var hasSourceMetadata = false
    private(set) var hasInflectionMetadata = false

    init?(databaseURL: URL) {
        var openedDatabase: OpaquePointer?
        let openResult = databaseURL.path.withCString { pathCString in
            sqlite3_open_v2(
                pathCString,
                &openedDatabase,
                SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
                nil
            )
        }

        guard openResult == SQLITE_OK,
            let openedDatabase else {
            if let openedDatabase {
                sqlite3_close(openedDatabase)
            }
            return nil
        }

        database = openedDatabase

        guard let candidateStatement = prepareStatement(
            sql: "SELECT candidate FROM dictionary_entries WHERE reading = ? ORDER BY rank ASC"
        ) else {
            return nil
        }
        selectCandidatesStatement = candidateStatement

        hasSourceMetadata = tableExists("candidate_sources")
        if hasSourceMetadata {
            selectCandidatesBySourceStatement = prepareStatement(
                sql: "SELECT e.candidate FROM dictionary_entries e WHERE e.reading = ? AND (NOT EXISTS (SELECT 1 FROM candidate_sources s_any WHERE s_any.reading = e.reading AND s_any.candidate = e.candidate) OR EXISTS (SELECT 1 FROM candidate_sources s WHERE s.reading = e.reading AND s.candidate = e.candidate AND s.source = ?)) ORDER BY e.rank ASC"
            )
        }

        hasInflectionMetadata = tableExists("inflection_classes")
        if hasInflectionMetadata {
            selectInflectionStatement = prepareStatement(
                sql: "SELECT candidate, inflection_class FROM inflection_classes WHERE reading = ?"
            )
        }
    }

    deinit {
        if let selectCandidatesStatement {
            sqlite3_finalize(selectCandidatesStatement)
        }

        if let selectCandidatesBySourceStatement {
            sqlite3_finalize(selectCandidatesBySourceStatement)
        }

        if let selectInflectionStatement {
            sqlite3_finalize(selectInflectionStatement)
        }

        if let database {
            sqlite3_close(database)
        }
    }

    func candidates(for reading: String, requiredSources: Set<String>?) -> [String] {
        queryQueue.sync {
            if let requiredSources,
                requiredSources.count == 1,
                hasSourceMetadata,
                let source = requiredSources.first,
                let statement = selectCandidatesBySourceStatement {
                return fetchCandidates(reading: reading, source: source, statement: statement)
            }

            guard let statement = selectCandidatesStatement else {
                return []
            }

            return fetchCandidates(reading: reading, source: nil, statement: statement)
        }
    }

    func inflectionClassMap(for reading: String) -> [String: String] {
        queryQueue.sync {
            guard hasInflectionMetadata,
                let statement = selectInflectionStatement else {
                return [:]
            }

            resetStatement(statement)

            let bindResult = reading.withCString { readingCString in
                sqlite3_bind_text(statement, 1, readingCString, -1, sqliteTransientDestructor)
            }

            guard bindResult == SQLITE_OK else {
                return [:]
            }

            var result: [String: String] = [:]

            while sqlite3_step(statement) == SQLITE_ROW {
                guard let candidateCString = sqlite3_column_text(statement, 0),
                    let inflectionClassCString = sqlite3_column_text(statement, 1) else {
                    continue
                }

                let candidate = String(cString: candidateCString)
                let inflectionClass = String(cString: inflectionClassCString)

                guard !candidate.isEmpty,
                    !inflectionClass.isEmpty else {
                    continue
                }

                result[candidate] = inflectionClass
            }

            return result
        }
    }

    private func fetchCandidates(
        reading: String,
        source: String?,
        statement: OpaquePointer
    ) -> [String] {
        resetStatement(statement)

        let readingBindResult = reading.withCString { readingCString in
            sqlite3_bind_text(statement, 1, readingCString, -1, sqliteTransientDestructor)
        }

        guard readingBindResult == SQLITE_OK else {
            return []
        }

        if let source {
            let sourceBindResult = source.withCString { sourceCString in
                sqlite3_bind_text(statement, 2, sourceCString, -1, sqliteTransientDestructor)
            }

            guard sourceBindResult == SQLITE_OK else {
                return []
            }
        }

        var results: [String] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let candidateCString = sqlite3_column_text(statement, 0) else {
                continue
            }

            let candidate = String(cString: candidateCString)

            if !candidate.isEmpty {
                results.append(candidate)
            }
        }

        return results
    }

    private func resetStatement(_ statement: OpaquePointer) {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
    }

    private func prepareStatement(sql: String) -> OpaquePointer? {
        guard let database else {
            return nil
        }

        var statement: OpaquePointer?
        let prepareResult = sql.withCString { sqlCString in
            sqlite3_prepare_v2(database, sqlCString, -1, &statement, nil)
        }

        guard prepareResult == SQLITE_OK,
            let statement else {
            return nil
        }

        return statement
    }

    private func tableExists(_ tableName: String) -> Bool {
        guard database != nil,
            let statement = prepareStatement(
                sql: "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1"
            ) else {
            return false
        }

        defer {
            sqlite3_finalize(statement)
        }

        let bindResult = tableName.withCString { tableNameCString in
            sqlite3_bind_text(statement, 1, tableNameCString, -1, sqliteTransientDestructor)
        }

        guard bindResult == SQLITE_OK else {
            return false
        }

        return sqlite3_step(statement) == SQLITE_ROW
    }
}

final class KanaKanjiStore {
    private let appGroupID: String
    private let defaults: UserDefaults?
    private let fileManager = FileManager.default
    private let systemDictionaryQueue = DispatchQueue(
        label: "com.kusakabe.ecritu.kana-kanji.system-dictionary"
    )
    private static let initialLearningScores: [String: Int] = [
        "かった\t交った": -1_000_000_000,
        "かった\t支った": -1_000_000_000
    ]
    private var sqliteIndex: KanaKanjiSQLiteIndex?
    private var didAttemptSQLiteIndexLoad = false
    private var cachedSystemDictionary: [String: [String]]?
    private var cachedSupplementalSystemDictionary: [String: [String]]?
    private var cachedSystemCandidateSources: [String: [String: Set<String>]]?
    private var cachedInflectionDictionary: [String: [String: String]]?
    private var cachedInitialUserDictionary: [String: [String]]?
    private var cachedUserDictionary: [String: [String]]?
    private var cachedSuppressedCandidatesByReading: [String: Set<String>]?
    private var cachedLearningScores: [String: Int]?
    private var cachedLearningScoresByReading: [String: [String: Int]]?

    init(appGroupID: String) {
        self.appGroupID = appGroupID
        self.defaults = UserDefaults(suiteName: appGroupID)
    }

    private func sharedOrBundledDictionaryURL(filename: String) -> URL? {
        if let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) {
            let sharedURL = containerURL.appendingPathComponent(filename)

            if let values = try? sharedURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                values.isRegularFile == true,
                let size = values.fileSize,
                size > 0 {
                return sharedURL
            }
        }

        let bundle = Bundle(for: KanaKanjiStore.self)
        let nsFilename = filename as NSString
        let resourceName = nsFilename.deletingPathExtension
        let resourceExtension = nsFilename.pathExtension

        let resourceURLs: [URL?] = [
            bundle.url(forResource: filename, withExtension: nil),
            resourceExtension.isEmpty
                ? nil
                : bundle.url(forResource: resourceName, withExtension: resourceExtension)
        ]

        for resourceURL in resourceURLs.compactMap({ $0 }) {
            if let values = try? resourceURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                values.isRegularFile == true,
                let size = values.fileSize,
                size > 0 {
                return resourceURL
            }
        }

        return nil
    }

    private func sharedOrBundledDictionaryData(filename: String) -> Data? {
        guard let resourceURL = sharedOrBundledDictionaryURL(filename: filename),
            let data = try? Data(contentsOf: resourceURL),
            !data.isEmpty else {
            return nil
        }

        return data
    }

    private func sqliteIndexIfAvailable() -> KanaKanjiSQLiteIndex? {
        systemDictionaryQueue.sync {
            if let sqliteIndex {
                return sqliteIndex
            }

            guard !didAttemptSQLiteIndexLoad else {
                return nil
            }

            didAttemptSQLiteIndexLoad = true

            guard let databaseURL = sharedOrBundledDictionaryURL(
                filename: KanaKanjiStorageKeys.systemDictionarySQLiteFilename
            ),
                let sqliteIndex = KanaKanjiSQLiteIndex(databaseURL: databaseURL) else {
                return nil
            }

            self.sqliteIndex = sqliteIndex
            return sqliteIndex
        }
    }

    func prepareSystemDictionaryIfNeeded(onLoaded: (() -> Void)? = nil) {
        guard onLoaded != nil else {
            _ = sqliteIndexIfAvailable()
            return
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            _ = self?.sqliteIndexIfAvailable()

            DispatchQueue.main.async {
                onLoaded?()
            }
        }
    }

    func systemCandidates(
        for reading: String,
        mode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        let normalizedReading = KanaTextNormalizer.normalizedReading(reading)

        guard !normalizedReading.isEmpty else {
            return []
        }

        let supplementalCandidates = loadSupplementalSystemDictionary()[normalizedReading] ?? []

        if let sqliteIndex = sqliteIndexIfAvailable() {
            let sqliteCandidates = sqliteIndex.candidates(
                for: normalizedReading,
                requiredSources: mode.requiredSystemSources
            )

            return mergedSystemCandidates(
                primary: sqliteCandidates,
                supplemental: supplementalCandidates
            )
        }

        let dictionary = loadSystemDictionary()
        let baseCandidates = dictionary[normalizedReading] ?? []

        guard let requiredSources = mode.requiredSystemSources else {
            return mergedSystemCandidates(
                primary: baseCandidates,
                supplemental: supplementalCandidates
            )
        }

        let sourceMap = loadSystemCandidateSources()[normalizedReading] ?? [:]

        guard !sourceMap.isEmpty else {
            return mergedSystemCandidates(
                primary: baseCandidates,
                supplemental: supplementalCandidates
            )
        }

        let filteredPrimaryCandidates = baseCandidates.filter { candidate in
            guard let candidateSources = sourceMap[candidate],
                !candidateSources.isEmpty else {
                // Keep fallback candidates even when no source metadata exists.
                return true
            }

            return !requiredSources.isDisjoint(with: candidateSources)
        }

        return mergedSystemCandidates(
            primary: filteredPrimaryCandidates,
            supplemental: supplementalCandidates
        )
    }

    func systemInflectionMetadata(for reading: String) -> (classMap: [String: String], hasMetadata: Bool) {
        let normalizedReading = KanaTextNormalizer.normalizedReading(reading)

        guard !normalizedReading.isEmpty else {
            return ([:], false)
        }

        if let sqliteIndex = sqliteIndexIfAvailable() {
            return (
                sqliteIndex.inflectionClassMap(for: normalizedReading),
                sqliteIndex.hasInflectionMetadata
            )
        }

        let inflectionDictionary = loadInflectionDictionary()
        return (inflectionDictionary[normalizedReading] ?? [:], !inflectionDictionary.isEmpty)
    }

    func loadSystemDictionary() -> [String: [String]] {
        if let cachedSystemDictionary {
            return cachedSystemDictionary
        }

        guard let data = sharedOrBundledDictionaryData(
            filename: KanaKanjiStorageKeys.systemDictionaryFilename
        ),
                let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            return [:]
        }

        // The generated Sudachi index is already normalized to hiragana readings.
        cachedSystemDictionary = decoded
        return decoded
    }

    func loadSupplementalSystemDictionary() -> [String: [String]] {
        if let cachedSupplementalSystemDictionary {
            return cachedSupplementalSystemDictionary
        }

        guard let data = sharedOrBundledDictionaryData(
            filename: KanaKanjiStorageKeys.supplementalSystemDictionaryFilename
        ),
            let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            cachedSupplementalSystemDictionary = [:]
            return [:]
        }

        let normalized = normalizeDictionary(decoded)
        cachedSupplementalSystemDictionary = normalized
        return normalized
    }

    func loadSystemCandidateSources() -> [String: [String: Set<String>]] {
        if let cachedSystemCandidateSources {
            return cachedSystemCandidateSources
        }

        guard let data = sharedOrBundledDictionaryData(
            filename: KanaKanjiStorageKeys.systemCandidateSourcesFilename
        ),
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

        guard let data = sharedOrBundledDictionaryData(
            filename: KanaKanjiStorageKeys.inflectionDictionaryFilename
        ) else {
            return [:]
        }

        if let decodedMap = try? JSONDecoder().decode([String: [String: String]].self, from: data) {
            var normalizedMap: [String: [String: String]] = [:]

            for (reading, candidateMap) in decodedMap {
                let normalizedReading = KanaTextNormalizer.normalizedReading(reading)

                guard !normalizedReading.isEmpty else {
                    continue
                }

                var filteredMap: [String: String] = [:]

                for (candidate, inflectionClass) in candidateMap {
                    let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedInflectionClass = inflectionClass.trimmingCharacters(in: .whitespacesAndNewlines)

                    guard !trimmedCandidate.isEmpty,
                        !trimmedInflectionClass.isEmpty else {
                        continue
                    }

                    filteredMap[trimmedCandidate] = trimmedInflectionClass
                }

                if !filteredMap.isEmpty {
                    normalizedMap[normalizedReading] = filteredMap
                }
            }

            cachedInflectionDictionary = normalizedMap
            return normalizedMap
        }

        guard let decoded = try? JSONDecoder().decode([String: [KanaKanjiInflectionEntry]].self, from: data) else {
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

    func clearSystemDictionaryCaches() {
        cachedSystemDictionary = nil
        cachedSupplementalSystemDictionary = nil
        cachedSystemCandidateSources = nil
        cachedInflectionDictionary = nil

        systemDictionaryQueue.sync {
            sqliteIndex = nil
            didAttemptSQLiteIndexLoad = false
        }
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
        if let cachedSuppressedCandidatesByReading {
            return cachedSuppressedCandidatesByReading
        }

        guard let decodedDictionary = decodedStringArrayDictionary(
            forKey: KanaKanjiStorageKeys.suppressionVocabulary
        ) else {
            cachedSuppressedCandidatesByReading = [:]
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

        cachedSuppressedCandidatesByReading = result
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
            cachedLearningScoresByReading = nil
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
        cachedLearningScoresByReading = nil

        if let encoded = try? JSONEncoder().encode(scores) {
            defaults.set(encoded, forKey: KanaKanjiStorageKeys.learningScores)
        }

        return scores
    }

    func learningScores(for reading: String) -> [String: Int] {
        let normalizedReading = KanaTextNormalizer.normalizedReading(reading)

        guard !normalizedReading.isEmpty else {
            return [:]
        }

        return learningScoresByReading()[normalizedReading] ?? [:]
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

        if var indexedScores = cachedLearningScoresByReading {
            var candidateScores = indexedScores[normalizedReading] ?? [:]
            candidateScores[trimmedCandidate] = scores[key, default: 0]
            indexedScores[normalizedReading] = candidateScores
            cachedLearningScoresByReading = indexedScores
        }

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

    private func mergedSystemCandidates(primary: [String], supplemental: [String]) -> [String] {
        guard !supplemental.isEmpty else {
            return primary
        }

        return uniqueCandidates(from: primary + supplemental)
    }

    private func learningKey(reading: String, candidate: String) -> String {
        reading + "\t" + candidate
    }

    private func learningScoresByReading() -> [String: [String: Int]] {
        if let cachedLearningScoresByReading {
            return cachedLearningScoresByReading
        }

        var indexedScores: [String: [String: Int]] = [:]

        for (key, score) in learningScores() {
            guard let parsed = parseLearningKey(key) else {
                continue
            }

            var candidateScores = indexedScores[parsed.reading] ?? [:]
            candidateScores[parsed.candidate] = score
            indexedScores[parsed.reading] = candidateScores
        }

        cachedLearningScoresByReading = indexedScores
        return indexedScores
    }

    private func parseLearningKey(_ key: String) -> (reading: String, candidate: String)? {
        guard let separatorIndex = key.firstIndex(of: "\t") else {
            return nil
        }

        let reading = String(key[..<separatorIndex])
        let candidateStartIndex = key.index(after: separatorIndex)
        let candidate = String(key[candidateStartIndex...])

        guard !reading.isEmpty,
                !candidate.isEmpty else {
            return nil
        }

        return (reading, candidate)
    }
}
