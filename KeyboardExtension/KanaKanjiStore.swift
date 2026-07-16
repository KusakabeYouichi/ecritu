import Foundation
import SQLite3

private struct KanaKanjiInflectionEntry: Codable {
    let candidate: String
    let inflectionClass: String
}

final class KanaKanjiStore {
    private let appGroupID: String
    let defaults: UserDefaults?
    private let fileManager = FileManager.default
    private let systemDictionaryQueue = DispatchQueue(
        label: "com.kusakabe.ecritu.kana-kanji.system-dictionary"
    )
    // かな識別(候補==読み)の学習を許可する読みの最大長。ちゃんと/そして/ありがとう 等の
    // 単語相当は許可し、文丸ごと(きょうはいいてんきですね 等)は拒否して連文節の
    // 最安素通りブロック事故(かな確定学習の事故時代の汚染含む)を防ぐ。
    static let kanaIdentityLearnableMaxReadingCount = 6
    static let initialLearningScores: [String: Int] = [
        "かった\t交った": -1_000_000_000,
        "かった\t支った": -1_000_000_000
    ]
    struct LatinSuggestionEntry {
        let searchKey: String
        let candidate: String
    }
    private var sqliteIndex: KanaKanjiSQLiteIndex?
    private var didAttemptSQLiteIndexLoad = false
    private var cachedSystemDictionary: [String: [String]]?
    private var cachedSupplementalSystemDictionary: [String: [String]]?
    var cachedLatinSuggestionEntries: [LatinSuggestionEntry]?
    private var cachedSystemCandidateSources: [String: [String: Set<String>]]?
    private var cachedInflectionDictionary: [String: [String: String]]?
    // 読み別の inflection_classes キャッシュ(連文節の辞書形述語判定用)
    private var cachedInflectionClassMapsByReading: [String: [String: String]] = [:]
    // 連文節 DP の LM 点引きキャッシュ。前置き入力ではスパン/ペアの大半が毎キーストロークで
    // 再出現するため、点クエリ(1変換あたり unigram 数百+bigram 千超)を初出のみに抑える。
    // 「未観測」も番兵(-1)で覚える — LM のヒット率は低く、negative キャッシュが本体。
    // 上限超過時は全消去(まれな一括再クエリで済ませ、LRU 管理のオーバーヘッドを避ける)。
    private var cachedWordLMUnigram: [String: Int] = [:]
    private var cachedWordLMBigram: [String: Int] = [:]
    private static let wordLMCacheLimit = 32768
    private static let wordLMMissingSentinel = -1
    // 読み別 word_costs キャッシュ(連文節のノード列挙が span ごとに引く)
    private var cachedWordCostsByReading: [String: [String: Int]] = [:]
    private static let wordCostsCacheLimit = 4096
    private var cachedInitialUserDictionary: [String: [String]]?
    private var cachedInitialShortcutVocabulary: [String]?
    var cachedUserDictionary: [String: [String]]?
    var cachedLearnedDictionary: [String: [String]]?
    private var cachedSuppressedCandidatesByReading: [String: Set<String>]?
    private var cachedBundledHiddenSuppression: [String: [String]]?
    var cachedLearningScores: [String: Int]?
    var cachedLearningScoresByReading: [String: [String: Int]]?

    init(appGroupID: String) {
        self.appGroupID = appGroupID
        self.defaults = UserDefaults(suiteName: appGroupID)
    }

    // バンドル優先で辞書ファイルを解決する。以前は app-group 優先だったが、正当な更新経路の
    // 無い遺物(旧仕組みで実機の app group に残った古い辞書)が半永久的に新しいバンドル辞書を
    // 覆い隠し、鴣う 等の旧ハーベストのジャンクや修正済みの誤り(のめる→飲む)が実機だけで
    // 再発し続けていた。バンドルは毎ビルド tmp から最新が入るため、実体があればバンドルを使い、
    // その際 app-group 側の同名遺物は削除して容量も回収する。app-group はバンドルに実体が
    // 無い場合のフォールバックとしてのみ残す。
    private func sharedOrBundledDictionaryURL(filename: String) -> URL? {
        let sharedURL: URL? = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ).map { $0.appendingPathComponent(filename) }

        func isUsableFile(_ url: URL) -> Bool {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                values.isRegularFile == true,
                let size = values.fileSize,
                size > 0 else {
                return false
            }
            return true
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

        for resourceURL in resourceURLs.compactMap({ $0 }) where isUsableFile(resourceURL) {
            if let sharedURL, isUsableFile(sharedURL) {
                try? fileManager.removeItem(at: sharedURL)
            }
            return resourceURL
        }

        if let sharedURL, isUsableFile(sharedURL) {
            return sharedURL
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

    // 連文節の辞書形述語判定(短spanレア読み床の免除)。読み単位のインデックス付きクエリ+
    // キャッシュで引く。以前の「length(reading)<=2 の一括ロード」はインデックスが効かず
    // inflection_classes 全行スキャンになり、キーボード起動ごと(=アプリ切替ごと)の
    // 初回変換を遅くしていた。呼び出し側の形状ゲート(かな終止形尾+漢字)でクエリ回数
    // 自体も span あたり高々1回に抑えている。
    func isShortReadingDictionaryFormPredicate(reading: String, candidate: String) -> Bool {
        if let cached = cachedInflectionClassMapsByReading[reading] {
            return cached[candidate] != nil
        }
        let classMap: [String: String]
        if let sqliteIndex = sqliteIndexIfAvailable() {
            classMap = sqliteIndex.inflectionClassMap(for: reading)
        } else {
            classMap = loadInflectionDictionary()[reading] ?? [:]
        }
        cachedInflectionClassMapsByReading[reading] = classMap
        return classMap[candidate] != nil
    }

    // 案A(連文節ビタビ)用: 読みに対する語コスト(Sudachi由来, 小さいほど高頻度)。
    // sqlite の word_costs 由来。無ければ空(= 呼び出し側で既定コストにフォールバック)。
    func wordCosts(for reading: String) -> [String: Int] {
        let normalizedReading = KanaTextNormalizer.normalizedReading(reading)
        guard !normalizedReading.isEmpty,
            let sqliteIndex = sqliteIndexIfAvailable() else {
            return [:]
        }
        if let cached = cachedWordCostsByReading[normalizedReading] {
            return cached
        }
        let costMap = sqliteIndex.wordCostMap(for: normalizedReading)
        if cachedWordCostsByReading.count >= Self.wordCostsCacheLimit {
            cachedWordCostsByReading.removeAll(keepingCapacity: true)
        }
        cachedWordCostsByReading[normalizedReading] = costMap
        return costMap
    }

    // 連文節 DP(案1: 自前単語 n-gram LM)が利用可能か。
    var hasWordLMMetadata: Bool {
        sqliteIndexIfAvailable()?.hasWordLMMetadata ?? false
    }

    // 連文節 DP 用: 表層集合の unigram コストをまとめて取得(点引きキャッシュ経由)。
    func wordLMUnigramCosts(for surfaces: [String]) -> [String: Int] {
        guard let sqliteIndex = sqliteIndexIfAvailable() else {
            return [:]
        }
        var result: [String: Int] = [:]
        var uncached: [String] = []
        for surface in surfaces {
            if let cached = cachedWordLMUnigram[surface] {
                if cached != Self.wordLMMissingSentinel {
                    result[surface] = cached
                }
            } else {
                uncached.append(surface)
            }
        }
        guard !uncached.isEmpty else {
            return result
        }
        let fetched = sqliteIndex.wordLMUnigramCosts(for: uncached)
        if cachedWordLMUnigram.count + uncached.count > Self.wordLMCacheLimit {
            cachedWordLMUnigram.removeAll(keepingCapacity: true)
        }
        for surface in uncached {
            if let cost = fetched[surface] {
                cachedWordLMUnigram[surface] = cost
                result[surface] = cost
            } else {
                cachedWordLMUnigram[surface] = Self.wordLMMissingSentinel
            }
        }
        return result
    }

    // 連文節 DP 用: (prev, cur) 対の bigram コストをまとめて取得(キー "prev\tcur"、点引きキャッシュ経由)。
    func wordLMBigramCosts(for pairs: [(String, String)]) -> [String: Int] {
        guard let sqliteIndex = sqliteIndexIfAvailable() else {
            return [:]
        }
        var result: [String: Int] = [:]
        var uncached: [(String, String)] = []
        for (prev, cur) in pairs {
            let key = prev + "\t" + cur
            if let cached = cachedWordLMBigram[key] {
                if cached != Self.wordLMMissingSentinel {
                    result[key] = cached
                }
            } else {
                uncached.append((prev, cur))
            }
        }
        guard !uncached.isEmpty else {
            return result
        }
        let fetched = sqliteIndex.wordLMBigramCosts(for: uncached)
        if cachedWordLMBigram.count + uncached.count > Self.wordLMCacheLimit {
            cachedWordLMBigram.removeAll(keepingCapacity: true)
        }
        for (prev, cur) in uncached {
            let key = prev + "\t" + cur
            if let cost = fetched[key] {
                cachedWordLMBigram[key] = cost
                result[key] = cost
            } else {
                cachedWordLMBigram[key] = Self.wordLMMissingSentinel
            }
        }
        return result
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

    // JSON フォールバック辞書のキャッシュのみ破棄する。sqlite インデックスは保持する。
    // sqlite は mmap 未使用(PRAGMA mmap_size 未設定)で 400MB は常駐せず、close しても
    // 解放されるのはごく小さいページキャッシュのみ。一方 close すると hasWordLMMetadata が
    // false になり連文節が丸ごと停止して劣化変換(しゃしん→者芯 等)になるため、
    // メモリ対策では sqlite を落とさない。
    func clearSystemDictionaryJSONCaches() {
        cachedSystemDictionary = nil
        cachedSupplementalSystemDictionary = nil
        cachedLatinSuggestionEntries = nil
        cachedSystemCandidateSources = nil
        cachedInflectionDictionary = nil
        cachedInflectionClassMapsByReading = [:]
        cachedWordLMUnigram = [:]
        cachedWordLMBigram = [:]
        cachedWordCostsByReading = [:]
    }

    // sqlite インデックスも含めて完全に閉じる(辞書ファイル差し替え時の再オープン用)。
    // メモリ対策では使わない — clearSystemDictionaryJSONCaches を使うこと。
    func clearSystemDictionaryCaches() {
        clearSystemDictionaryJSONCaches()

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

        // 追加語彙(sacoche=InitialAjout)と変換対策語(misc=InitialMisc)を統合してラティスの
        // curated 供給に使う。どちらも変換には効かせるが、コンテナアプリの「追加語彙」への
        // 初期表示は sacoche(InitialAjout)側のみ(App 側のマイグレーションが分離管理)。
        let bundle = Bundle(for: KanaKanjiStore.self)

        func loadBundled(_ resourceName: String) -> [String: [String]] {
            guard let url = bundle.url(forResource: resourceName, withExtension: "json"),
                let data = try? Data(contentsOf: url),
                let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
                return [:]
            }
            return decoded
        }

        var combined = loadBundled(KanaKanjiStorageKeys.initialUserDictionaryResourceName)
        for (reading, candidates) in loadBundled(KanaKanjiStorageKeys.initialMiscDictionaryResourceName) {
            combined[reading, default: []].append(contentsOf: candidates)
        }

        let normalized = normalizeDictionary(combined)
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

    // suppr.plist 由来の抑制(バンドル同梱、UI非表示)。poubelle の UserDefaults 経路とは別に
    // キーボードが直接読む。実機/バンドル解決は追加語彙(initialUserDictionary)と同じ仕組み。
    private func bundledHiddenSuppressionDictionary() -> [String: [String]] {
        if let cachedBundledHiddenSuppression {
            return cachedBundledHiddenSuppression
        }
        let bundle = Bundle(for: KanaKanjiStore.self)
        guard let url = bundle.url(
            forResource: KanaKanjiStorageKeys.initialSuppressionHiddenResourceName,
            withExtension: "json"
        ),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            cachedBundledHiddenSuppression = [:]
            return [:]
        }
        cachedBundledHiddenSuppression = decoded
        return decoded
    }

    func suppressedCandidatesByReading() -> [String: Set<String>] {
        if let cachedSuppressedCandidatesByReading {
            return cachedSuppressedCandidatesByReading
        }

        // UserDefaults(poubelle=アプリ移行分+アプリUIでの手動抑制)と、バンドル直読みの
        // hidden(suppr.plist 由来=変換対策で非表示)を統合する。変換時は両者を対等に抑制。
        var decodedDictionary = decodedStringArrayDictionary(
            forKey: KanaKanjiStorageKeys.suppressionVocabulary
        ) ?? [:]
        for (reading, candidates) in bundledHiddenSuppressionDictionary() {
            decodedDictionary[reading, default: []].append(contentsOf: candidates)
        }

        guard !decodedDictionary.isEmpty else {
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

    func decodedStringArrayDictionary(forKey key: String) -> [String: [String]]? {
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

    func normalizeDictionary(_ dictionary: [String: [String]]) -> [String: [String]] {
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

    private func mergedSystemCandidates(primary: [String], supplemental: [String]) -> [String] {
        guard !supplemental.isEmpty else {
            return primary
        }

        return uniqueCandidates(from: primary + supplemental)
    }

}
