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
    private var selectCandidatesWithExactSourceStatement: OpaquePointer?
    private var selectInflectionStatement: OpaquePointer?
    private var selectWordCostStatement: OpaquePointer?
    private var selectWordLMUnigramStatement: OpaquePointer?
    private var selectWordLMBigramStatement: OpaquePointer?
    private(set) var hasSourceMetadata = false
    private(set) var hasInflectionMetadata = false
    private(set) var hasWordCostMetadata = false
    private(set) var hasWordLMMetadata = false
    private(set) var hasAnyEntries = false

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
            selectCandidatesWithExactSourceStatement = prepareStatement(
                sql: "SELECT e.candidate FROM dictionary_entries e INNER JOIN candidate_sources s ON s.reading = e.reading AND s.candidate = e.candidate WHERE e.reading = ? AND s.source = ? ORDER BY e.rank ASC"
            )
        }

        hasInflectionMetadata = tableExists("inflection_classes")
        if hasInflectionMetadata {
            selectInflectionStatement = prepareStatement(
                sql: "SELECT candidate, inflection_class FROM inflection_classes WHERE reading = ?"
            )
        }

        hasWordCostMetadata = tableExists("word_costs")
        if hasWordCostMetadata {
            selectWordCostStatement = prepareStatement(
                sql: "SELECT candidate, cost FROM word_costs WHERE reading = ?"
            )
        }

        // 連文節変換(案1: 自前単語 n-gram LM)。unigram/bigram の両テーブルが揃って初めて有効。
        hasWordLMMetadata = tableExists("word_lm_unigram") && tableExists("word_lm_bigram")
        if hasWordLMMetadata {
            selectWordLMUnigramStatement = prepareStatement(
                sql: "SELECT cost FROM word_lm_unigram WHERE surface = ?"
            )
            selectWordLMBigramStatement = prepareStatement(
                sql: "SELECT cost FROM word_lm_bigram WHERE prev = ? AND cur = ?"
            )
        }

        if let probeStatement = prepareStatement(
            sql: "SELECT 1 FROM dictionary_entries LIMIT 1"
        ) {
            hasAnyEntries = sqlite3_step(probeStatement) == SQLITE_ROW
            sqlite3_finalize(probeStatement)
        }
    }

    deinit {
        if let selectCandidatesStatement {
            sqlite3_finalize(selectCandidatesStatement)
        }

        if let selectCandidatesBySourceStatement {
            sqlite3_finalize(selectCandidatesBySourceStatement)
        }

        if let selectCandidatesWithExactSourceStatement {
            sqlite3_finalize(selectCandidatesWithExactSourceStatement)
        }

        if let selectInflectionStatement {
            sqlite3_finalize(selectInflectionStatement)
        }

        if let selectWordCostStatement {
            sqlite3_finalize(selectWordCostStatement)
        }

        if let selectWordLMUnigramStatement {
            sqlite3_finalize(selectWordLMUnigramStatement)
        }

        if let selectWordLMBigramStatement {
            sqlite3_finalize(selectWordLMBigramStatement)
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

    func candidates(withExactSource source: String, for reading: String) -> [String] {
        queryQueue.sync {
            guard hasSourceMetadata,
                let statement = selectCandidatesWithExactSourceStatement else {
                return []
            }

            return fetchCandidates(reading: reading, source: source, statement: statement)
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

    func wordCostMap(for reading: String) -> [String: Int] {
        queryQueue.sync {
            guard hasWordCostMetadata,
                let statement = selectWordCostStatement else {
                return [:]
            }

            resetStatement(statement)

            let bindResult = reading.withCString { readingCString in
                sqlite3_bind_text(statement, 1, readingCString, -1, sqliteTransientDestructor)
            }

            guard bindResult == SQLITE_OK else {
                return [:]
            }

            var result: [String: Int] = [:]

            while sqlite3_step(statement) == SQLITE_ROW {
                guard let candidateCString = sqlite3_column_text(statement, 0) else {
                    continue
                }

                let candidate = String(cString: candidateCString)
                guard !candidate.isEmpty else {
                    continue
                }

                result[candidate] = Int(sqlite3_column_int(statement, 1))
            }

            return result
        }
    }

    // 連文節 DP 用: 与えた表層集合の unigram コストをまとめて引く(1 回の sync 内で完結)。
    func wordLMUnigramCosts(for surfaces: [String]) -> [String: Int] {
        queryQueue.sync {
            guard hasWordLMMetadata,
                let statement = selectWordLMUnigramStatement else {
                return [:]
            }

            var result: [String: Int] = [:]
            result.reserveCapacity(surfaces.count)

            for surface in surfaces where result[surface] == nil {
                resetStatement(statement)
                let bindResult = surface.withCString { surfaceCString in
                    sqlite3_bind_text(statement, 1, surfaceCString, -1, sqliteTransientDestructor)
                }
                guard bindResult == SQLITE_OK else {
                    continue
                }
                if sqlite3_step(statement) == SQLITE_ROW {
                    result[surface] = Int(sqlite3_column_int(statement, 0))
                }
            }

            return result
        }
    }

    // 連文節 DP 用: 与えた (prev, cur) 対の bigram コストをまとめて引く。キーは "prev\tcur"。
    func wordLMBigramCosts(for pairs: [(String, String)]) -> [String: Int] {
        queryQueue.sync {
            guard hasWordLMMetadata,
                let statement = selectWordLMBigramStatement else {
                return [:]
            }

            var result: [String: Int] = [:]
            result.reserveCapacity(pairs.count)

            for (prev, cur) in pairs {
                let key = "\(prev)\t\(cur)"
                if result[key] != nil {
                    continue
                }
                resetStatement(statement)
                let prevBind = prev.withCString { prevCString in
                    sqlite3_bind_text(statement, 1, prevCString, -1, sqliteTransientDestructor)
                }
                let curBind = cur.withCString { curCString in
                    sqlite3_bind_text(statement, 2, curCString, -1, sqliteTransientDestructor)
                }
                guard prevBind == SQLITE_OK, curBind == SQLITE_OK else {
                    continue
                }
                if sqlite3_step(statement) == SQLITE_ROW {
                    result[key] = Int(sqlite3_column_int(statement, 0))
                }
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
    // かな識別(候補==読み)の学習を許可する読みの最大長。ちゃんと/そして/ありがとう 等の
    // 単語相当は許可し、文丸ごと(きょうはいいてんきですね 等)は拒否して連文節の
    // 最安素通りブロック事故(かな確定学習の事故時代の汚染含む)を防ぐ。
    static let kanaIdentityLearnableMaxReadingCount = 6
    private static let initialLearningScores: [String: Int] = [
        "かった\t交った": -1_000_000_000,
        "かった\t支った": -1_000_000_000
    ]
    private struct LatinSuggestionEntry {
        let searchKey: String
        let candidate: String
    }
    private var sqliteIndex: KanaKanjiSQLiteIndex?
    private var didAttemptSQLiteIndexLoad = false
    private var cachedSystemDictionary: [String: [String]]?
    private var cachedSupplementalSystemDictionary: [String: [String]]?
    private var cachedLatinSuggestionEntries: [LatinSuggestionEntry]?
    private var cachedSystemCandidateSources: [String: [String: Set<String>]]?
    private var cachedInflectionDictionary: [String: [String: String]]?
    private var cachedInitialUserDictionary: [String: [String]]?
    private var cachedInitialShortcutVocabulary: [String]?
    private var cachedUserDictionary: [String: [String]]?
    private var cachedLearnedDictionary: [String: [String]]?
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

            guard let databaseURL = sharedOrBundledDictionaryURL(
                filename: KanaKanjiStorageKeys.systemDictionarySQLiteFilename
            ) else {
                // Keep retry enabled so a later App Group install can be picked up.
                didAttemptSQLiteIndexLoad = false
                return nil
            }

            guard !didAttemptSQLiteIndexLoad else {
                return nil
            }

            didAttemptSQLiteIndexLoad = true

            guard let sqliteIndex = KanaKanjiSQLiteIndex(databaseURL: databaseURL) else {
                // Allow retry in case the database is still being copied.
                didAttemptSQLiteIndexLoad = false
                return nil
            }

            self.sqliteIndex = sqliteIndex
            return sqliteIndex
        }
    }

    func isSystemDictionaryFallback() -> Bool {
        guard let sqliteIndex = sqliteIndexIfAvailable() else {
            return true
        }

        return !sqliteIndex.hasAnyEntries
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

        if let sqliteIndex = sqliteIndexIfAvailable() {
            return sqliteIndex.candidates(
                for: normalizedReading,
                requiredSources: mode.requiredSystemSources
            )
        }

        let supplementalCandidates = loadSupplementalSystemDictionary()[normalizedReading] ?? []
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
            let classMap = sqliteIndex.inflectionClassMap(for: normalizedReading)
            return (classMap, !classMap.isEmpty)
        }

        let inflectionDictionary = loadInflectionDictionary()
        let classMap = inflectionDictionary[normalizedReading] ?? [:]
        return (classMap, !classMap.isEmpty)
    }

    // 案A(連文節ビタビ)用: 読みに対する語コスト(Sudachi由来, 小さいほど高頻度)。
    // sqlite の word_costs 由来。無ければ空(= 呼び出し側で既定コストにフォールバック)。
    func wordCosts(for reading: String) -> [String: Int] {
        let normalizedReading = KanaTextNormalizer.normalizedReading(reading)
        guard !normalizedReading.isEmpty,
            let sqliteIndex = sqliteIndexIfAvailable() else {
            return [:]
        }
        return sqliteIndex.wordCostMap(for: normalizedReading)
    }

    // 連文節 DP(案1: 自前単語 n-gram LM)が利用可能か。
    var hasWordLMMetadata: Bool {
        sqliteIndexIfAvailable()?.hasWordLMMetadata ?? false
    }

    // 連文節 DP 用: 表層集合の unigram コストをまとめて取得。
    func wordLMUnigramCosts(for surfaces: [String]) -> [String: Int] {
        guard let sqliteIndex = sqliteIndexIfAvailable() else {
            return [:]
        }
        return sqliteIndex.wordLMUnigramCosts(for: surfaces)
    }

    // 連文節 DP 用: (prev, cur) 対の bigram コストをまとめて取得(キー "prev\tcur")。
    func wordLMBigramCosts(for pairs: [(String, String)]) -> [String: Int] {
        guard let sqliteIndex = sqliteIndexIfAvailable() else {
            return [:]
        }
        return sqliteIndex.wordLMBigramCosts(for: pairs)
    }

    func systemCandidates(
        for reading: String,
        taggedWith sourceTag: String
    ) -> (candidates: Set<String>, hasMetadata: Bool) {
        let normalizedReading = KanaTextNormalizer.normalizedReading(reading)

        guard !normalizedReading.isEmpty else {
            return ([], false)
        }

        var candidates = Set<String>()
        let sqliteIndex = sqliteIndexIfAvailable()
        let hasSQLiteSourceMetadata = sqliteIndex?.hasSourceMetadata == true

        if let sqliteIndex,
            sqliteIndex.hasSourceMetadata {
            candidates.formUnion(
                sqliteIndex.candidates(
                    withExactSource: sourceTag,
                    for: normalizedReading
                )
            )
        }

        let sourceMapByCandidate: [String: Set<String>]

        if hasSQLiteSourceMetadata {
            sourceMapByCandidate = [:]
        } else {
            sourceMapByCandidate = loadSystemCandidateSources()[normalizedReading] ?? [:]
        }

        for (candidate, sources) in sourceMapByCandidate where sources.contains(sourceTag) {
            candidates.insert(candidate)
        }

        var hasMetadata = !sourceMapByCandidate.isEmpty
            || (sqliteIndex?.hasSourceMetadata == true)

        if sourceTag == KanaKanjiCandidateSourceTag.adjectiveGaru,
            let seedCandidates = KanaKanjiSemanticSeed.adjectiveGaruCandidatesByReading[normalizedReading],
            !seedCandidates.isEmpty {
            candidates.formUnion(seedCandidates)
            hasMetadata = true
        }

        return (candidates, hasMetadata)
    }

    func latinSuggestions(prefix: String, limit: Int) -> [String] {
        guard limit > 0 else {
            return []
        }

        let normalizedPrefix = latinSuggestionSearchKey(prefix, preservesSpaces: true)

        guard !normalizedPrefix.isEmpty else {
            return []
        }

        let entries = latinSuggestionEntries()

        guard !entries.isEmpty else {
            return []
        }

        let startIndex = lowerBoundLatinSuggestionEntryIndex(
            entries: entries,
            for: normalizedPrefix
        )
        var results: [String] = []
        var seenCandidates = Set<String>()
        var index = startIndex

        while index < entries.count,
            entries[index].searchKey.hasPrefix(normalizedPrefix),
            results.count < limit {
            let candidate = entries[index].candidate

            if seenCandidates.insert(candidate).inserted {
                results.append(candidate)
            }

            index += 1
        }

        return results
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

        guard !decoded.isEmpty else {
            // Do not pin an empty placeholder; allow retry after dictionary install.
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
            return [:]
        }

        let normalized = normalizeDictionary(decoded)

        guard !normalized.isEmpty else {
            // Keep retry enabled for late dictionary deployment.
            return [:]
        }

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
                    if source == KanaKanjiCandidateSourceTag.normalized
                        || source == KanaKanjiCandidateSourceTag.surface
                        || source == KanaKanjiCandidateSourceTag.adjectiveGaru {
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

        guard !normalized.isEmpty else {
            // Do not cache empty source metadata from placeholder resources.
            return [:]
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

            guard !normalizedMap.isEmpty else {
                return [:]
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

        guard !inflectionMap.isEmpty else {
            return [:]
        }

        cachedInflectionDictionary = inflectionMap
        return inflectionMap
    }

    func clearSystemDictionaryCaches() {
        cachedSystemDictionary = nil
        cachedSupplementalSystemDictionary = nil
        cachedLatinSuggestionEntries = nil
        cachedSystemCandidateSources = nil
        cachedInflectionDictionary = nil

        systemDictionaryQueue.sync {
            sqliteIndex = nil
            didAttemptSQLiteIndexLoad = false
        }
    }

    func clearSharedDataCaches() {
        cachedUserDictionary = nil
        cachedLearnedDictionary = nil
        cachedSuppressedCandidatesByReading = nil
        cachedLearningScores = nil
        cachedLearningScoresByReading = nil
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

    func learnedDictionary() -> [String: [String]] {
        if let cachedLearnedDictionary {
            return cachedLearnedDictionary
        }

        guard let decoded = decodedStringArrayDictionary(forKey: KanaKanjiStorageKeys.learnedDictionary) else {
            cachedLearnedDictionary = [:]
            return [:]
        }

        let normalized = normalizeDictionary(decoded)
        // かな識別(候補==読み)は原則「変換」ではない。文丸ごとの誤学習(かな確定を学習して
        // いた時代の汚染)は読み込み時に除外し、連文節の最安素通りブロックを防ぐ。
        // ただし単語相当の短い読み(ちゃんと/そして 等。かな候補チップの明示タップで学習)は
        // 許可し、変換候補側にも出せるようにする。
        var cleaned: [String: [String]] = [:]
        cleaned.reserveCapacity(normalized.count)
        for (reading, candidates) in normalized {
            let allowsIdentity = reading.count <= Self.kanaIdentityLearnableMaxReadingCount
            let filtered = allowsIdentity ? candidates : candidates.filter { $0 != reading }
            if !filtered.isEmpty {
                cleaned[reading] = filtered
            }
        }
        cachedLearnedDictionary = cleaned
        return cleaned
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

    func shortcutVocabulary() -> [String] {
        let userCandidates = decodedStringArray(forKey: KanaKanjiStorageKeys.shortcutVocabulary) ?? []

        if !userCandidates.isEmpty {
            return uniqueShortcutCandidates(
                from: initialShortcutVocabulary() + userCandidates
            )
        }

        if let legacyDictionary = decodedStringArrayDictionary(forKey: KanaKanjiStorageKeys.shortcutVocabulary) {
            let legacyCandidates = legacyDictionary["☻"] ?? legacyDictionary
                .keys
                .sorted()
                .flatMap { legacyDictionary[$0] ?? [] }

            if !legacyCandidates.isEmpty {
                return uniqueShortcutCandidates(
                    from: initialShortcutVocabulary() + legacyCandidates
                )
            }
        }

        return initialShortcutVocabulary()
    }

    func initialShortcutVocabulary() -> [String] {
        if let cachedInitialShortcutVocabulary {
            return cachedInitialShortcutVocabulary
        }

        let bundle = Bundle(for: KanaKanjiStore.self)

        guard let initialDictionaryURL = bundle.url(
            forResource: KanaKanjiStorageKeys.initialShortcutVocabularyResourceName,
            withExtension: "json"
        ),
            let data = try? Data(contentsOf: initialDictionaryURL) else {
            cachedInitialShortcutVocabulary = []
            return []
        }

        if let decodedArray = try? JSONDecoder().decode([String].self, from: data) {
            let normalized = uniqueShortcutCandidates(from: decodedArray)
            cachedInitialShortcutVocabulary = normalized
            return normalized
        }

        if let decodedDictionary = try? JSONDecoder().decode([String: [String]].self, from: data) {
            let candidates = decodedDictionary["☻"] ?? decodedDictionary
                .keys
                .sorted()
                .flatMap { decodedDictionary[$0] ?? [] }
            let normalized = uniqueShortcutCandidates(from: candidates)
            cachedInitialShortcutVocabulary = normalized
            return normalized
        }

        cachedInitialShortcutVocabulary = []
        return []
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

    func addLearnedEntry(reading: String, candidate: String, allowKanaIdentity: Bool = false) {
        let normalizedReading = KanaTextNormalizer.normalizedReading(reading)
        let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedReading.isEmpty,
                !trimmedCandidate.isEmpty else {
            return
        }

        // かな識別(候補==読み)は原則学習しない(全経路での最終防波堤)。学習すると連文節DP
        // で最安の素通り単スパンになり、その読みが変換不能になる。例外はかな候補チップの
        // 明示タップ(allowKanaIdentity)かつ単語相当の短い読みのみ。
        if trimmedCandidate == normalizedReading {
            guard allowKanaIdentity,
                normalizedReading.count <= Self.kanaIdentityLearnableMaxReadingCount else {
                return
            }
        }

        var dictionary = learnedDictionary()
        var candidates = dictionary[normalizedReading] ?? []

        if let existingIndex = candidates.firstIndex(of: trimmedCandidate) {
            candidates.remove(at: existingIndex)
        }

        candidates.insert(trimmedCandidate, at: 0)
        dictionary[normalizedReading] = Array(candidates.prefix(32))
        cachedLearnedDictionary = dictionary
        saveLearnedDictionary(dictionary)
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

    private func saveLearnedDictionary(_ dictionary: [String: [String]]) {
        guard let defaults,
                let encoded = try? JSONEncoder().encode(dictionary) else {
            return
        }

        defaults.set(encoded, forKey: KanaKanjiStorageKeys.learnedDictionary)
    }

    private func decodedStringArray(forKey key: String) -> [String]? {
        guard let defaults else {
            return nil
        }

        if let arrayData = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode([String].self, from: arrayData) {
            return decoded
        }

        if let rawArray = defaults.array(forKey: key) {
            return rawArray.compactMap { $0 as? String }
        }

        return nil
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

    private func uniqueShortcutCandidates(from candidates: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for candidate in candidates {
            let normalized = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !normalized.isEmpty,
                    !seen.contains(normalized) else {
                continue
            }

            seen.insert(normalized)
            result.append(candidate)
        }

        return result
    }

    private func latinSuggestionEntries() -> [LatinSuggestionEntry] {
        if let cachedLatinSuggestionEntries {
            return cachedLatinSuggestionEntries
        }

        let supplementalDictionary = loadSupplementalSystemDictionary()

        guard !supplementalDictionary.isEmpty else {
            return []
        }

        var seenCandidates = Set<String>()
        var entries: [LatinSuggestionEntry] = []

        for candidates in supplementalDictionary.values {
            for candidate in candidates {
                let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

                guard !trimmedCandidate.isEmpty,
                    seenCandidates.insert(trimmedCandidate).inserted,
                    isLatinSuggestionCandidate(trimmedCandidate) else {
                    continue
                }

                let searchKey = latinSuggestionSearchKey(trimmedCandidate)

                guard !searchKey.isEmpty else {
                    continue
                }

                entries.append(
                    LatinSuggestionEntry(
                        searchKey: searchKey,
                        candidate: trimmedCandidate
                    )
                )
            }
        }

        guard !entries.isEmpty else {
            return []
        }

        entries.sort { lhs, rhs in
            if lhs.searchKey == rhs.searchKey {
                return lhs.candidate.localizedCaseInsensitiveCompare(rhs.candidate) == .orderedAscending
            }

            return lhs.searchKey < rhs.searchKey
        }

        cachedLatinSuggestionEntries = entries
        return entries
    }

    private func latinSuggestionSearchKey(
        _ text: String,
        preservesSpaces: Bool = false
    ) -> String {
        let trimmed: String

        if preservesSpaces {
            trimmed = text.trimmingCharacters(in: .newlines)
        } else {
            trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !trimmed.isEmpty else {
            return ""
        }

        return trimmed
            .folding(
                options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
                locale: Locale(identifier: "fr_FR")
            )
            .lowercased()
    }

    private func isLatinSuggestionCandidate(_ candidate: String) -> Bool {
        guard candidate.range(of: #"[\p{Latin}0-9]"#, options: .regularExpression) != nil else {
            return false
        }

        return candidate.range(
            of: #"^[\p{Latin}\p{M}0-9 \-\.&'’/,+:;()!?]+$"#,
            options: .regularExpression
        ) != nil
    }

    private func lowerBoundLatinSuggestionEntryIndex(
        entries: [LatinSuggestionEntry],
        for key: String
    ) -> Int {
        var low = 0
        var high = entries.count

        while low < high {
            let mid = (low + high) / 2

            if entries[mid].searchKey < key {
                low = mid + 1
            } else {
                high = mid
            }
        }

        return low
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
