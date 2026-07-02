import Foundation

final class KanaKanjiConverter {
    private struct CandidateCacheKey: Hashable {
        let reading: String
        let limit: Int
        let modeRawValue: String
    }

    private static let politePrefixPassthroughPrefixes: [String] = ["お", "ご"]

    private static func honorificOSuruInflectionSuffixes() -> [String] {
        var suffixes = ["する"]
        suffixes.append(contentsOf: KanaKanjiConverter.suruInflectionRules.map(\.readingSuffix))

        var seen = Set<String>()
        var unique: [String] = []

        for suffix in suffixes where !suffix.isEmpty {
            guard seen.insert(suffix).inserted else {
                continue
            }

            unique.append(suffix)
        }

        return unique.sorted {
            if $0.count != $1.count {
                return $0.count > $1.count
            }

            return $0 > $1
        }
    }

    private static let honorificONaruInflectionSuffixes: [String] = [
        "になりません",
        "になりました",
        "になります",
        "にならない",
        "になった",
        "になって",
        "になり",
        "になる"
    ]

    private static let honorificOSoftRequestSuffixes: [String] = [
        "なきように",
        "なきよう",
        "なく"
    ]

    private static let maxPostfixPassthroughDepth = 3

    private static let predicateRequiredExplanatorySuffixes: [String] = [
        "んですけれど", "んですけど", "んだけれど", "んだけど", "んです", "んだ", "のです", "のだ"
    ]

    private static let predicateStemEndingKana: Set<Character> = [
        "う", "く", "ぐ", "す", "ず", "つ", "づ", "ぬ", "ふ", "ぶ", "ぷ", "む", "ゆ", "る",
        "い", "た", "だ"
    ]

    private static func explanatorySuffixRequiresPredicateStem(_ suffix: String) -> Bool {
        for restricted in predicateRequiredExplanatorySuffixes where suffix.hasPrefix(restricted) {
            return true
        }
        return false
    }

    private static func isPredicateLikeStemReading(_ reading: String) -> Bool {
        guard let last = reading.last else { return false }
        return predicateStemEndingKana.contains(last)
    }

    private static func suffixFormsVerbConjugationWithNEnding(_ suffix: String) -> Bool {
        suffix.hasPrefix("だ") || suffix.hasPrefix("で")
    }

    private static let verbalStemRequiredPostfixPrefixes: [String] = [
        "よう"
    ]

    private static func postfixSuffixRequiresVerbalStem(_ suffix: String) -> Bool {
        for required in verbalStemRequiredPostfixPrefixes where suffix.hasPrefix(required) {
            return true
        }
        return false
    }

    private func normalizedTaggedCandidates(for reading: String) -> Set<String> {
        store.systemCandidates(
            for: reading,
            taggedWith: KanaKanjiCandidateSourceTag.normalized
        ).candidates
    }

    private func filterVerbStemFragmentCandidatesIfNeeded(
        _ candidates: [String],
        stemReading: String,
        nextSuffix: String
    ) -> [String] {
        guard Self.suffixFormsVerbConjugationWithNEnding(nextSuffix) else {
            return candidates
        }

        let normalizedSet = normalizedTaggedCandidates(for: stemReading)
        return candidates.filter { candidate in
            guard candidate.hasSuffix("ん") else { return true }
            return normalizedSet.contains(candidate)
        }
    }

    private static let godanPotentialConjugationSuffixes: [String] = [
        "る",
        "ない", "なかった",
        "た", "たら", "たり",
        "て",
        "ます", "ました", "ません", "ませんでした",
        "れば",
        "よう",
        "たい", "たく", "たくて", "たくない", "たくなかった", "たかった", "たければ"
    ]

    private static let godanPotentialDeinflectionMappings: [(readingSuffix: String, baseReadingSuffix: String)] = {
        var mappings: [(readingSuffix: String, baseReadingSuffix: String)] = []
        for pattern in godanPatterns {
            for conjugation in godanPotentialConjugationSuffixes {
                mappings.append(
                    (
                        readingSuffix: pattern.eForm + conjugation,
                        baseReadingSuffix: pattern.dictionaryEnding
                    )
                )
            }
        }
        return mappings
    }()

    private func isDeinflectedSuppressed(
        candidate: String,
        reading: String,
        suppressedByReading: [String: Set<String>]
    ) -> Bool {
        guard !suppressedByReading.isEmpty else {
            return false
        }

        for rule in Self.allInflectionRules {
            guard reading.hasSuffix(rule.readingSuffix),
                candidate.hasSuffix(rule.outputCandidateSuffix) else {
                continue
            }

            let readingStem = String(reading.dropLast(rule.readingSuffix.count))
            let candidateStem = String(candidate.dropLast(rule.outputCandidateSuffix.count))

            if readingStem.isEmpty,
                !Self.emptyStemAllowedBaseReadingSuffixes.contains(rule.baseReadingSuffix) {
                continue
            }

            let baseReading = readingStem + rule.baseReadingSuffix

            guard let suppressedSet = suppressedByReading[baseReading],
                !suppressedSet.isEmpty else {
                continue
            }

            for baseCandidateSuffix in rule.baseCandidateSuffixes {
                let baseCandidate = candidateStem + baseCandidateSuffix

                if suppressedSet.contains(baseCandidate) {
                    return true
                }
            }
        }

        for mapping in Self.godanPotentialDeinflectionMappings {
            guard reading.hasSuffix(mapping.readingSuffix),
                candidate.hasSuffix(mapping.readingSuffix) else {
                continue
            }

            let readingStem = String(reading.dropLast(mapping.readingSuffix.count))
            let candidateStem = String(candidate.dropLast(mapping.readingSuffix.count))

            guard !readingStem.isEmpty else {
                continue
            }

            let baseReading = readingStem + mapping.baseReadingSuffix
            let baseCandidate = candidateStem + mapping.baseReadingSuffix

            if let suppressedSet = suppressedByReading[baseReading],
                suppressedSet.contains(baseCandidate) {
                return true
            }
        }

        return false
    }

    private func filterNonVerbalCandidatesForVerbalPostfix(
        _ candidates: [String],
        stemReading: String,
        nextSuffix: String
    ) -> [String] {
        guard Self.postfixSuffixRequiresVerbalStem(nextSuffix) else {
            return candidates
        }

        let metadata = inflectionMetadata(for: stemReading)
        // 追加語彙・学習語彙の動詞はシステム辞書の活用クラスメタデータを持たないため、
        // 活用候補生成と同じ推論(resolvedInflectionClass)で動詞性を判定する。
        // これにより「使った/読んだ」等と同様に「よう/ように/ような」も導出できる。
        // 品詞が明示(systemClassMap)されている語はそちらが優先される。
        let normalizedStemReading = KanaTextNormalizer.normalizedReading(stemReading)
        let userCandidateSet = Set(
            combinedUserCandidates(for: stemReading, userDictionary: store.userDictionary())
        ).union(store.initialUserDictionary()[normalizedStemReading] ?? [])

        return candidates.filter { candidate in
            if candidate.hasSuffix("する")
                || candidate.hasSuffix("くる")
                || candidate.hasSuffix("来る") {
                return true
            }

            guard let className = resolvedInflectionClass(
                for: candidate,
                baseReading: stemReading,
                systemClassMap: metadata.classMap,
                hasSystemMetadata: metadata.hasMetadata,
                userCandidateSet: userCandidateSet
            ) else {
                return false
            }

            return className == InflectionClass.ichidan
                || className.hasPrefix("godan-")
                || className == InflectionClass.kuru
        }
    }

    private static let kuruKanjiCandidateBoost = 1450
    private static let godanImperativeCandidateBoost = 320
    private static let numericUnitFallbackCandidateBoost = 320
    private static let numericCounterCompoundCandidateBoost = 360
    private static let sameReadingPureKatakanaPenalty = 128
    private static let seedLeadingKanjiCandidateBoost = 1600
    private static let seedSingleKanjiPriorityBaseBoost = 220
    private static let seedSingleKanjiPriorityStep = 12

    private static let numericUnitFallbackCandidatesByReading: [String: [String]] = [
        "せんえん": ["千円"],
        "まんえん": ["万円"],
        "おくえん": ["億円"],
        "ちょうえん": ["兆円"]
    ]

    private static let numericCounterPrefixCandidatesByReading: [String: [String]] = [
        "いっ": ["一"],
        "きゅう": ["九"],
        "ご": ["五"],
        "さん": ["三"],
        "じっ": ["十"],
        "じゅっ": ["十"],
        "に": ["二"],
        "なな": ["七"],
        "なん": ["何"],
        "はっ": ["八"],
        "よん": ["四"],
        "ろっ": ["六"],
        "すう": ["数"]
    ]

    private static let numericCounterSuffixCandidatesByReading: [String: [String]] = [
        "こ": ["個"],
        "えん": ["円"],
        "かい": ["回"],
        "かげつ": ["か月", "カ月", "ヶ月", "ヵ月", "箇月"],
        "かしょ": ["か所", "箇所", "カ所", "ヶ所", "ヵ所"],
        "けん": ["件"],
        "しゅうかん": ["週間"],
        "じかん": ["時間"],
        "じつ": ["日"],
        "にち": ["日"],
        "だい": ["台"],
        "にん": ["人"],
        "ねん": ["年"],
        "ほん": ["本"],
        "びょう": ["秒"],
        "ふん": ["分"],
        "ぷん": ["分"],
        "ひき": ["匹"],
        "ぼん": ["本"],
        "びき": ["匹"],
        "まい": ["枚"],
        "ぽん": ["本"],
        "ぴき": ["匹"],
        "はい": ["倍", "杯"],
        "ばい": ["倍"],
        "はつ": ["発"],
        "ぱつ": ["発"]
    ]

    private static let numericCounterAllowedSuffixReadingsByPrefixReading: [String: Set<String>] = [
        "いっ": ["ぽん", "ぴき"],
        "きゅう": ["ほん", "ひき"],
        "ご": ["ほん", "ひき"],
        "さん": ["ぼん", "びき"],
        "じっ": ["ぽん", "ぴき"],
        "じゅっ": ["ぽん", "ぴき"],
        "に": ["ほん", "ひき"],
        "なな": ["ほん", "ひき"],
        "なん": [
            "こ", "かい", "かげつ", "かしょ", "けん", "しゅうかん", "じかん", "にち", "だい", "にん", "ねん",
            "はい", "ばい", "はつ", "ぱつ", "びょう", "ぷん", "ぼん", "びき", "まい"
        ],
        "はっ": ["ぽん", "ぴき"],
        "よん": ["ほん", "ひき"],
        "ろっ": ["ぽん", "ぴき"],
        "すう": [
            "こ", "かい", "かげつ", "かしょ", "けん", "しゅうかん", "じかん", "じつ", "だい", "にん", "ねん",
            "はい", "ばい", "はつ", "ぱつ", "びょう", "ふん", "ひき", "ほん", "まい"
        ]
    ]

    // 大数位(桁). 接頭(数/何/数字)と助数詞の間に挟まる「千・百・万…」を表す。
    // 連濁・促音の読み(ぜん/びゃく/ぴゃく等)も含め、読み一致で正しい組のみ生成する。
    private static let numericMagnitudeCandidatesByReading: [(reading: String, candidate: String)] = [
        ("せん", "千"), ("ぜん", "千"),
        ("ひゃく", "百"), ("びゃく", "百"), ("ぴゃく", "百"),
        ("まん", "万"),
        ("おく", "億"),
        ("ちょう", "兆"),
        ("じゅう", "十")
    ]

    // 「分の一」等の分数末尾。助数詞の「分(ふん/ぷん)」とは読み(ぶん)で区別される。
    private static let numericFractionSuffixCandidatesByReading: [String: [String]] = [
        "ぶんのいち": ["分の一"]
    ]

    // 名詞に付く生産的な漢字接尾辞(種類別・色別・国別…)。語幹(名詞)+接尾辞漢字。
    private static let nounKanjiSuffixAffixCandidatesByReading: [(reading: String, candidate: String)] = [
        ("べつ", "別")
    ]

    // 名詞に付く生産的な漢字接頭辞(別会社・別人物・別商品…)。接頭辞漢字+語幹(名詞)。
    private static let nounKanjiPrefixAffixCandidatesByReading: [(reading: String, candidate: String)] = [
        ("べつ", "別")
    ]

    private static let mixedScriptSahenOptInReadings: Set<String> = [
        "ねおち"
    ]

    private static let sahenPhraseParticleSuffixes: [String] = [
        "には", "では", "とは", "へは",
        "が", "を", "に", "で", "と", "へ", "は", "も", "の", "や"
    ]

    private static let godanRuKanjiSuffixOverrides: [String] = [
        "入る",
        "減る"
    ]

    private static func postfixOutputSuffixVariants(for suffix: String) -> [String] {
        var variants = [suffix]

        for replacement in Self.postfixPassthroughPrefixReplacements where suffix.hasPrefix(replacement.from) {
            let tail = String(suffix.dropFirst(replacement.from.count))
            let converted = replacement.to + tail

            if !variants.contains(converted) {
                variants.append(converted)
            }
        }

        return variants
    }

    private static let iVowelKanaBeforeRu: Set<Character> = [
        "い", "き", "ぎ", "し", "じ", "ち", "ぢ", "に", "ひ", "び", "ぴ", "み", "り", "ゐ"
    ]

    private static let eVowelKanaBeforeRu: Set<Character> = [
        "え", "け", "げ", "せ", "ぜ", "て", "で", "ね", "へ", "べ", "ぺ", "め", "れ", "ゑ"
    ]

    private let store: KanaKanjiStore
    private let stateQueue = DispatchQueue(label: "com.kusakabe.ecritu.kana-kanji.converter-state")
    private var candidateCache: [CandidateCacheKey: [String]] = [:]
    private var candidateCacheOrder: [CandidateCacheKey] = []

    private let candidateCacheLimit = 96

    private var historicalKanaSurfaceAllowed: Bool = false

    init(store: KanaKanjiStore) {
        self.store = store
    }

    func setHistoricalKanaSurfaceAllowed(_ allowed: Bool) {
        stateQueue.sync {
            guard historicalKanaSurfaceAllowed != allowed else {
                return
            }

            historicalKanaSurfaceAllowed = allowed
            invalidateCandidateCache()
        }
    }

    func preloadSystemDictionaryIfNeeded(onLoaded: (() -> Void)? = nil) {
        store.prepareSystemDictionaryIfNeeded { [weak self] in
            guard let self else {
                onLoaded?()
                return
            }

            self.stateQueue.sync {
                self.invalidateCandidateCache()
            }

            onLoaded?()
        }
    }

    func clearSharedDataCaches() {
        store.clearSharedDataCaches()

        stateQueue.sync {
            invalidateCandidateCache()
        }
    }

    func clearAllCaches() {
        store.clearSystemDictionaryCaches()
        store.clearSharedDataCaches()

        stateQueue.sync {
            invalidateCandidateCache()
        }
    }

    func preloadSharedDataCachesIfNeeded() {
        _ = store.userDictionary()
        _ = store.learnedDictionary()
        _ = store.initialUserDictionary()
        _ = store.suppressedCandidatesByReading()
        _ = store.learningScores(for: "あ")
    }

    func candidates(
        for reading: String,
        limit: Int,
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        let normalizedReading = KanaTextNormalizer.normalizedReading(reading)

        guard !normalizedReading.isEmpty,
                limit > 0 else {
            return []
        }

        let cacheKey = CandidateCacheKey(
            reading: normalizedReading,
            limit: limit,
            modeRawValue: systemCandidateMode.rawValue
        )

        if let cachedCandidates = stateQueue.sync(execute: { candidateCache[cacheKey] }) {
            return cachedCandidates
        }

        let manualUserDictionary = store.userDictionary()
        let learnedDictionary = store.learnedDictionary()
        let userDictionary = manualUserDictionary
        let initialUserDictionary = store.initialUserDictionary()
        let learningScoresForReading = store.learningScores(for: normalizedReading)
        let suppressedCandidatesByReading = store.suppressedCandidatesByReading()
        var scores: [String: Int] = [:]
        let systemCandidates = systemCandidates(
            for: normalizedReading,
            mode: systemCandidateMode
        )
        let userCandidates = uniqueCandidates(
            from: (manualUserDictionary[normalizedReading] ?? [])
                + (initialUserDictionary[normalizedReading] ?? [])
        )
        let userCandidateSet = Set(userCandidates)
        let learnedCandidates = uniqueCandidates(
            from: (learnedDictionary[normalizedReading] ?? []).filter {
                !userCandidateSet.contains($0)
            }
        )
        let hasDirectCandidates = !systemCandidates.isEmpty
            || !userCandidates.isEmpty
            || !learnedCandidates.isEmpty

        addCandidates(
            systemCandidates,
            baseScore: 1200,
            to: &scores
        )
        addCandidates(
            userCandidates,
            baseScore: 2400,
            to: &scores
        )
        addCandidates(
            learnedCandidates,
            baseScore: 2280,
            to: &scores
        )

        addCandidates(
            inflectionCandidates(
                for: normalizedReading,
                userDictionary: userDictionary,
                initialUserDictionary: initialUserDictionary,
                systemCandidateMode: systemCandidateMode,
                limit: limit * 3
            ),
            baseScore: 980,
            to: &scores
        )

        addCandidates(
            adjectiveGaruCandidates(
                for: normalizedReading,
                userDictionary: userDictionary,
                initialUserDictionary: initialUserDictionary,
                systemCandidateMode: systemCandidateMode,
                limit: limit * 3
            ),
            baseScore: 970,
            to: &scores
        )

        addCandidates(
            politePrefixPassthroughCandidates(
                for: normalizedReading,
                userDictionary: userDictionary,
                initialUserDictionary: initialUserDictionary,
                systemCandidateMode: systemCandidateMode,
                limit: limit * 2
            ),
            baseScore: 1100,
            to: &scores
        )

        addCandidates(
            ordinalMeFallbackCandidates(
                for: normalizedReading,
                hasDirectCandidates: hasDirectCandidates,
                userDictionary: userDictionary,
                initialUserDictionary: initialUserDictionary,
                systemCandidateMode: systemCandidateMode,
                limit: limit * 2
            ),
            baseScore: 1080,
            to: &scores
        )

        let numericUnitFallback = numericUnitFallbackCandidates(
            for: normalizedReading,
            limit: limit * 2
        )

        let numericCounterCompoundFallback = numericCounterCompoundCandidates(
            for: normalizedReading,
            userDictionary: userDictionary,
            initialUserDictionary: initialUserDictionary,
            systemCandidateMode: systemCandidateMode,
            limit: limit * 2
        )

        addCandidates(
            numericUnitFallback,
            baseScore: 1070,
            to: &scores
        )

        addCandidates(
            numericCounterCompoundFallback,
            baseScore: Self.numericCounterCompoundCandidateBoost,
            to: &scores
        )

        applyNumericUnitFallbackPriorityBoost(
            for: normalizedReading,
            fallbackCandidates: numericUnitFallback,
            to: &scores
        )

        addCandidates(
            nounKanjiAffixCandidates(
                for: normalizedReading,
                userDictionary: userDictionary,
                initialUserDictionary: initialUserDictionary,
                systemCandidateMode: systemCandidateMode,
                limit: limit * 2
            ),
            baseScore: 1000,
            to: &scores
        )

        let quickPostfixCandidates = quickPostfixCandidatesUsingCachedStem(
            for: normalizedReading,
            limit: limit,
            systemCandidateMode: systemCandidateMode
        )

        if !quickPostfixCandidates.isEmpty {
            addCandidates(
                quickPostfixCandidates,
                baseScore: 1120,
                to: &scores
            )
        } else {
            addCandidates(
                postfixPassthroughCandidates(
                    for: normalizedReading,
                    userDictionary: userDictionary,
                    initialUserDictionary: initialUserDictionary,
                    systemCandidateMode: systemCandidateMode,
                    limit: limit * 3
                ),
                baseScore: 1040,
                to: &scores
            )
        }

        applyInflectionRankingHeuristics(
            for: normalizedReading,
            userDictionary: userDictionary,
            initialUserDictionary: initialUserDictionary,
            systemCandidateMode: systemCandidateMode,
            systemCandidates: systemCandidates,
            to: &scores
        )

        applyLearning(
            learningScoresForReading,
            to: &scores
        )

        applySameReadingScriptPreference(
            for: normalizedReading,
            systemCandidates: systemCandidates,
            to: &scores
        )

        applySeedSingleKanjiPriorityBoost(
            for: normalizedReading,
            to: &scores
        )

        if let suppressedCandidates = suppressedCandidatesByReading[normalizedReading],
            !suppressedCandidates.isEmpty {
            for candidate in suppressedCandidates {
                scores.removeValue(forKey: candidate)
            }
        }

        for candidate in Array(scores.keys) where isDeinflectedSuppressed(
            candidate: candidate,
            reading: normalizedReading,
            suppressedByReading: suppressedCandidatesByReading
        ) {
            scores.removeValue(forKey: candidate)
        }

        let sortedCandidates = scores.keys.sorted { lhs, rhs in
            let lhsScore = scores[lhs, default: 0]
            let rhsScore = scores[rhs, default: 0]

            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }

            if lhs.count != rhs.count {
                return lhs.count < rhs.count
            }

            return lhs < rhs
        }

        let archaicAdjectiveFiltered = filterArchaicAdjectiveSurfaceCandidates(
            for: normalizedReading,
            candidates: sortedCandidates,
            userDictionary: userDictionary,
            learnedDictionary: learnedDictionary,
            initialUserDictionary: initialUserDictionary
        )

        let filteredSortedCandidates = filterHistoricalKanaSurfaceCandidates(
            for: normalizedReading,
            candidates: archaicAdjectiveFiltered
        )

        let finalCandidates = Array(filteredSortedCandidates.prefix(limit))

        if !finalCandidates.isEmpty {
            stateQueue.sync {
                if candidateCache[cacheKey] == nil {
                    candidateCacheOrder.append(cacheKey)
                }

                candidateCache[cacheKey] = finalCandidates

                while candidateCacheOrder.count > candidateCacheLimit {
                    let removedKey = candidateCacheOrder.removeFirst()
                    candidateCache.removeValue(forKey: removedKey)
                }
            }
        }

        return finalCandidates
    }

    // MARK: - 連文節変換(案A1: 語コスト版ビタビ)
    //
    // 読み全体を文節ラティスに分割し、Sudachi 語コスト最小の経路を DP(ビタビ)で選ぶ。
    // 連接コスト(matrix.def)は未導入(=案A2)。連接が無いため各文節は「最安の変換」を
    // 独立に選べば最適で、経路コスト = Σ(語コスト) + 文節数ペナルティ。
    //   - 語コストは store.wordCosts(word_costs テーブル, Sudachi連接エントリ由来)。
    //   - コスト不明な文節(活用形・追加語彙・かな素通り)は candidates() の top1 を
    //     既定コストで補完。かな素通りは強く減点。
    // 呼び出し側でフラグ(isMultiClauseConversionEnabled)により on/off する。
    private static let multiClauseMinReadingCount = 4
    private static let multiClauseMaxReadingCount = 40      // これを超える長文は連文節DPを回さない(計算量抑制)
    private static let multiClauseMaxSegmentReadingCount = 12
    private static let multiClauseSupplementMaxLen = 8
    private static let multiClauseTopK = 8                  // 1文節あたり列挙する変換候補数(sim: TOPK)
    private static let multiClauseBOSMarker = "<BOS>"
    private static let multiClauseEOSMarker = "<EOS>"
    // LM コスト定数(cost = -logP × scale, scale=500 で学習)。sim_lm.py で検証した値と一致させる。
    private static let multiClauseBackoffCost = 500         // bigram 未観測・unigram 既知
    private static let multiClauseDictUnknownCost = 6000    // 辞書/変換にあるがコーパス未知(=そこそこレア)
    private static let multiClausePassthroughPerCharCost = 7000 // 未変換かな 1文字あたり(点1: 余りを強く減点)
    private static let multiClauseKatakanaNativeCost = 3000 // native 読みなのにカタカナ実体(何でもカタカナ化の抑止)
    // 語頭(文節頭)に来られない文字で始まる分割は日本語としてほぼあり得ないため強く減点。撥音ん・
    // 長音ー・促音っ・小書きかな等。「を」も現代仮名遣いでは目的格助詞専用なので語中に含めない。
    private static let multiClauseForbiddenPenaltyCost = 100000
    private static let multiClauseForbiddenInitials: Set<Character> = [
        "ん", "ー", "っ", "ぁ", "ぃ", "ぅ", "ぇ", "ぉ",
        "ゃ", "ゅ", "ょ", "ゎ", "ゕ", "ゖ", "ゝ", "ゞ", "・"
    ]
    // ローンワード的な読みの指標(長音・小書き母音)。これらを含む読みはカタカナ表記が
    // 妥当なので、カタカナ素通りを減点しない(例: らんてぃーゆ→ランティーユ は許容)。
    private static let multiClauseLoanwordMarkers: Set<Character> = [
        "ー", "ぁ", "ぃ", "ぅ", "ぇ", "ぉ", "ゎ"
    ]

    // ラティスのノード(1 つの文節候補)。同じ span でも表層ごとに別ノードを立て、bigram の
    // 文脈(直前の表層)を DP でつなぐ。
    private struct MultiClauseNode {
        let start: Int
        let end: Int
        let surface: String
        let reading: String
        let isDictWord: Bool   // 辞書/変換で得た語(true) or かな素通り(false)
    }

    func multiClauseCandidates(
        for reading: String,
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        guard store.hasWordLMMetadata else {
            return []
        }
        let normalized = KanaTextNormalizer.normalizedReading(reading)
        let chars = Array(normalized)
        let n = chars.count
        guard n >= Self.multiClauseMinReadingCount,
            n <= Self.multiClauseMaxReadingCount else {
            return []
        }

        let suppressedByReading = store.suppressedCandidatesByReading()

        // --- 1. ラティスのノード列挙 ---
        var nodes: [MultiClauseNode] = []
        var nodesEndingAt: [[Int]] = Array(repeating: [], count: n + 1)
        var nodesStartingAt: [[Int]] = Array(repeating: [], count: n)

        for start in 0..<n {
            let maxLen = min(Self.multiClauseMaxSegmentReadingCount, n - start)
            for len in 1...maxLen {
                let end = start + len
                let segmentReading = String(chars[start..<end])

                var surfaces: [(surface: String, isDictWord: Bool)] = []

                // (a) word_costs(Sudachi 由来)から top-K を列挙。抑制語彙は除外。
                let costMap = store.wordCosts(for: segmentReading)
                if !costMap.isEmpty {
                    let suppressed = suppressedByReading[segmentReading]
                    let ordered = costMap.sorted { lhs, rhs in
                        lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key < rhs.key
                    }
                    for (surface, _) in ordered {
                        if let suppressed, suppressed.contains(surface) {
                            continue
                        }
                        surfaces.append((surface, true))
                        if surfaces.count >= Self.multiClauseTopK {
                            break
                        }
                    }
                }

                // (b) word_costs に無ければ candidates() で補完(活用形・追加語彙など)。
                //     実変換(かな素通りでない)のときだけ辞書語ノードとして採用。
                if surfaces.isEmpty, len <= Self.multiClauseSupplementMaxLen,
                    let top = candidates(
                        for: segmentReading,
                        limit: 1,
                        systemCandidateMode: systemCandidateMode
                    ).first,
                    KanaTextNormalizer.normalizedReading(top) != segmentReading {
                    surfaces.append((top, true))
                }

                // (c) それでも無ければかな素通り(最後の手段)。ローンワード的読みはカタカナ表記。
                if surfaces.isEmpty {
                    let passthrough: String
                    if readingLooksLikeLoanword(segmentReading),
                        len <= Self.multiClauseSupplementMaxLen {
                        passthrough = Self.hiraganaToKatakana(segmentReading)
                    } else {
                        passthrough = segmentReading
                    }
                    surfaces.append((passthrough, false))
                }

                for (surface, isDictWord) in surfaces {
                    let index = nodes.count
                    nodes.append(MultiClauseNode(
                        start: start,
                        end: end,
                        surface: surface,
                        reading: segmentReading,
                        isDictWord: isDictWord
                    ))
                    nodesEndingAt[end].append(index)
                    nodesStartingAt[start].append(index)
                }
            }
        }

        // --- 2. LM コスト(unigram/bigram)を一括ロード(sqlite アクセスを最小化) ---
        var unigramSurfaces = Set<String>()
        unigramSurfaces.insert(Self.multiClauseEOSMarker)
        for node in nodes {
            unigramSurfaces.insert(node.surface)
        }
        let unigramCosts = store.wordLMUnigramCosts(for: Array(unigramSurfaces))

        var bigramPairs: [(String, String)] = []
        var seenPairs = Set<String>()
        func addPair(_ prev: String, _ cur: String) {
            if seenPairs.insert("\(prev)\t\(cur)").inserted {
                bigramPairs.append((prev, cur))
            }
        }
        for idx in nodesStartingAt[0] {
            addPair(Self.multiClauseBOSMarker, nodes[idx].surface)
        }
        if n >= 1 {
            for boundary in 1..<n {
                for prevIdx in nodesEndingAt[boundary] {
                    for curIdx in nodesStartingAt[boundary] {
                        addPair(nodes[prevIdx].surface, nodes[curIdx].surface)
                    }
                }
            }
        }
        for idx in nodesEndingAt[n] {
            addPair(nodes[idx].surface, Self.multiClauseEOSMarker)
        }
        let bigramCosts = store.wordLMBigramCosts(for: bigramPairs)

        // --- 3. コスト関数(sim_lm.py と一致): bigram / unigram+backoff / 辞書OOV / 素通りper-char ---
        func transitionCost(prev: String, surface: String, reading: String, isDictWord: Bool) -> Int {
            var base: Int
            if let bigram = bigramCosts["\(prev)\t\(surface)"] {
                base = bigram
            } else if let unigram = unigramCosts[surface] {
                base = unigram + Self.multiClauseBackoffCost
            } else if isDictWord {
                base = Self.multiClauseDictUnknownCost
            } else {
                base = Self.multiClausePassthroughPerCharCost * reading.count
            }
            var penalty = 0
            if Self.isKatakanaString(surface), !readingLooksLikeLoanword(reading) {
                penalty += Self.multiClauseKatakanaNativeCost
            }
            if reading.count > 1, reading.contains("を") {
                penalty += Self.multiClauseForbiddenPenaltyCost
            }
            if let first = reading.first, Self.multiClauseForbiddenInitials.contains(first) {
                penalty += Self.multiClauseForbiddenPenaltyCost
            }
            return base + penalty
        }

        // --- 4. Viterbi DP(ノード = (span, 表層)) ---
        let infinity = Int.max / 4
        var best = Array(repeating: infinity, count: nodes.count)
        var backPointer = Array(repeating: -1, count: nodes.count)

        for boundary in 1...n {
            for idx in nodesEndingAt[boundary] {
                let node = nodes[idx]
                if node.start == 0 {
                    let cost = transitionCost(
                        prev: Self.multiClauseBOSMarker,
                        surface: node.surface,
                        reading: node.reading,
                        isDictWord: node.isDictWord
                    )
                    if cost < best[idx] {
                        best[idx] = cost
                        backPointer[idx] = -1
                    }
                }
                for prevIdx in nodesEndingAt[node.start] {
                    let prevCost = best[prevIdx]
                    if prevCost >= infinity {
                        continue
                    }
                    let cost = prevCost + transitionCost(
                        prev: nodes[prevIdx].surface,
                        surface: node.surface,
                        reading: node.reading,
                        isDictWord: node.isDictWord
                    )
                    if cost < best[idx] {
                        best[idx] = cost
                        backPointer[idx] = prevIdx
                    }
                }
            }
        }

        // --- 5. EOS 込みで最良の終端ノードを選ぶ ---
        var bestTotal = infinity
        var bestEndIndex = -1
        for idx in nodesEndingAt[n] {
            if best[idx] >= infinity {
                continue
            }
            let total = best[idx] + transitionCost(
                prev: nodes[idx].surface,
                surface: Self.multiClauseEOSMarker,
                reading: "",
                isDictWord: true
            )
            if total < bestTotal {
                bestTotal = total
                bestEndIndex = idx
            }
        }
        guard bestEndIndex >= 0 else {
            return []
        }

        // --- 6. バックトラック ---
        var segments: [String] = []
        var idx = bestEndIndex
        while idx >= 0 {
            segments.append(nodes[idx].surface)
            idx = backPointer[idx]
        }
        segments.reverse()
        guard segments.count >= 2 else {
            return []   // 単文節は既存の単文節経路に任せる
        }

        let joined = segments.joined()
        if joined == normalized {
            return []
        }
        return [joined]
    }

    private static func hiraganaToKatakana(_ text: String) -> String {
        text.applyingTransform(.hiraganaToKatakana, reverse: false) ?? text
    }

    private static func isKatakanaString(_ text: String) -> Bool {
        guard !text.isEmpty else {
            return false
        }
        for scalar in text.unicodeScalars {
            // カタカナ(ァ U+30A1 〜 ヺ U+30FA)と長音符(ー U+30FC)。
            if (0x30A1...0x30FA).contains(scalar.value) || scalar.value == 0x30FC {
                continue
            }
            return false
        }
        return true
    }

    private func readingLooksLikeLoanword(_ reading: String) -> Bool {
        for character in reading where Self.multiClauseLoanwordMarkers.contains(character) {
            return true
        }
        return false
    }

    func learn(reading: String, candidate: String) {
        let normalizedReading = KanaTextNormalizer.normalizedReading(reading)
        let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedReading.isEmpty,
                !trimmedCandidate.isEmpty else {
            return
        }

        store.addLearnedEntry(reading: normalizedReading, candidate: trimmedCandidate)
        store.incrementLearning(reading: normalizedReading, candidate: trimmedCandidate)

        stateQueue.sync {
            invalidateCandidateCache()
        }
    }

    private func addCandidates(
        _ candidates: [String],
        baseScore: Int,
        to scores: inout [String: Int]
    ) {
        for (index, candidate) in uniqueCandidates(from: candidates).enumerated() {
            scores[candidate, default: 0] += max(1, baseScore - index)
        }
    }

    private func applyLearning(
        _ learningScoresForReading: [String: Int],
        to scores: inout [String: Int]
    ) {
        for (candidate, count) in learningScoresForReading {
            scores[candidate, default: 0] += count * 64
        }
    }

    private func applySameReadingScriptPreference(
        for reading: String,
        systemCandidates: [String],
        to scores: inout [String: Int]
    ) {
        var matchingCandidates: [String] = []

        for candidate in scores.keys {
            if KanaTextNormalizer.normalizedReading(candidate) == reading {
                matchingCandidates.append(candidate)
            }
        }

        guard !matchingCandidates.isEmpty else {
            return
        }

        let nonKatakanaCandidates = matchingCandidates.filter {
            !Self.isPureKatakanaCandidate($0)
        }

        guard !nonKatakanaCandidates.isEmpty else {
            return
        }

        let lowestNonKatakanaScore = nonKatakanaCandidates
            .map { scores[$0, default: 0] }
            .min() ?? 0

        let protectedKatakanaCandidates = preferredLeadingKatakanaCandidates(
            fromSystemCandidates: systemCandidates,
            reading: reading
        )

        for candidate in matchingCandidates where Self.isPureKatakanaCandidate(candidate) {
            if protectedKatakanaCandidates.contains(candidate) {
                continue
            }

            let penalizedScore = scores[candidate, default: 0] - Self.sameReadingPureKatakanaPenalty
            scores[candidate] = min(penalizedScore, lowestNonKatakanaScore - 1)
        }
    }

    private func preferredLeadingKatakanaCandidates(
        fromSystemCandidates candidates: [String],
        reading: String
    ) -> Set<String> {
        let uniqueSystemCandidates = uniqueCandidates(from: candidates)

        guard !uniqueSystemCandidates.isEmpty else {
            return []
        }

        var protectedCandidates = Set<String>()

        // 読みと一致する候補をシステム順に走査し、最初に non-katakana が
        // 現れるまでに登場した katakana を保護対象にする。
        // 読みと無関係な kanji 候補(例: 「かっと」に対する 褐土 が rank0)で
        // 早期 break しないよう、 mismatch する候補は単にスキップする。
        for candidate in uniqueSystemCandidates {
            if KanaTextNormalizer.normalizedReading(candidate) != reading {
                continue
            }
            if !Self.isPureKatakanaCandidate(candidate) {
                break
            }
            protectedCandidates.insert(candidate)
        }

        return protectedCandidates
    }

    private func applySeedSingleKanjiPriorityBoost(
        for reading: String,
        to scores: inout [String: Int]
    ) {
        guard let seedCandidates = KanaKanjiSeedDictionary.seed[reading],
            !seedCandidates.isEmpty else {
            return
        }

        for (index, candidate) in uniqueCandidates(from: seedCandidates).enumerated() {
            if index == 0,
                Self.containsKanjiCandidate(candidate) {
                scores[candidate, default: 0] += Self.seedLeadingKanjiCandidateBoost
            }

            guard Self.isSingleKanjiCandidate(candidate) else {
                continue
            }

            let boost = max(
                24,
                Self.seedSingleKanjiPriorityBaseBoost - (index * Self.seedSingleKanjiPriorityStep)
            )
            scores[candidate, default: 0] += boost
        }
    }

    private static func isSingleKanjiCandidate(_ candidate: String) -> Bool {
        guard candidate.count == 1,
            let scalar = candidate.unicodeScalars.first else {
            return false
        }

        return (0x3400...0x4DBF).contains(scalar.value)
            || (0x4E00...0x9FFF).contains(scalar.value)
            || (0xF900...0xFAFF).contains(scalar.value)
    }

    private static func containsKanjiCandidate(_ candidate: String) -> Bool {
        for scalar in candidate.unicodeScalars {
            if (0x3400...0x4DBF).contains(scalar.value)
                || (0x4E00...0x9FFF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value) {
                return true
            }
        }

        return false
    }

    private static func isPureKatakanaCandidate(_ candidate: String) -> Bool {
        guard !candidate.isEmpty else {
            return false
        }

        for scalar in candidate.unicodeScalars {
            if scalar.value == 0x30FB || scalar.value == 0x30FC
                || scalar.value == 0xFF65 || scalar.value == 0xFF70
                || scalar.value == 0xFF9E || scalar.value == 0xFF9F {
                continue
            }

            if (0x30A0...0x30FF).contains(scalar.value)
                || (0x31F0...0x31FF).contains(scalar.value)
                || (0xFF66...0xFF9D).contains(scalar.value) {
                continue
            }

            return false
        }

        return true
    }

    private func invalidateCandidateCache() {
        candidateCache.removeAll(keepingCapacity: true)
        candidateCacheOrder.removeAll(keepingCapacity: true)
    }

    private func quickPostfixCandidatesUsingCachedStem(
        for reading: String,
        limit: Int,
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        guard reading.count >= 2,
                limit > 0 else {
            return []
        }

        var weightedDerivedCandidates: [(stemLength: Int, derived: [String])] = []

        for passthrough in Self.postfixPassthroughSuffixes where reading.hasSuffix(passthrough) {
            let stem = String(reading.dropLast(passthrough.count))

            guard !stem.isEmpty else {
                continue
            }

            if Self.explanatorySuffixRequiresPredicateStem(passthrough),
                !Self.isPredicateLikeStemReading(stem) {
                continue
            }

            let stemKey = CandidateCacheKey(
                reading: stem,
                limit: limit,
                modeRawValue: systemCandidateMode.rawValue
            )

            guard let stemCandidates = stateQueue.sync(execute: { candidateCache[stemKey] }),
                    !stemCandidates.isEmpty else {
                continue
            }

            let nEndingFiltered = filterVerbStemFragmentCandidatesIfNeeded(
                stemCandidates,
                stemReading: stem,
                nextSuffix: passthrough
            )
            let filteredStemCandidates = filterNonVerbalCandidatesForVerbalPostfix(
                nEndingFiltered,
                stemReading: stem,
                nextSuffix: passthrough
            )

            guard !filteredStemCandidates.isEmpty else {
                continue
            }

            let suffixVariants = Self.postfixOutputSuffixVariants(for: passthrough)
            let derived = filteredStemCandidates.flatMap { candidate in
                suffixVariants.map { candidate + $0 }
            }

            guard !derived.isEmpty else {
                continue
            }

            weightedDerivedCandidates.append((stemLength: stem.count, derived: derived))
        }

        guard !weightedDerivedCandidates.isEmpty else {
            return []
        }

        let prioritized = weightedDerivedCandidates.sorted { lhs, rhs in
            if lhs.stemLength != rhs.stemLength {
                return lhs.stemLength > rhs.stemLength
            }

            return lhs.derived.count > rhs.derived.count
        }

        let merged = prioritized.flatMap(\.derived)

        return Array(uniqueCandidates(from: merged).prefix(limit))

    }

    private func applyInflectionRankingHeuristics(
        for reading: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode,
        systemCandidates: [String],
        to scores: inout [String: Int]
    ) {
        guard let matchedSuffix = matchingInflectionRankingSuffix(for: reading) else {
            applyGodanImperativeBoost(
                for: reading,
                userDictionary: userDictionary,
                initialUserDictionary: initialUserDictionary,
                systemCandidateMode: systemCandidateMode,
                to: &scores
            )
            return
        }

        let trustedDirectCandidates = Set(systemCandidates.prefix(3))

        for candidate in Array(scores.keys) {
            var delta = 0

            if hasMatchingInflectionRankingSuffix(candidate, readingSuffix: matchedSuffix) {
                delta += 220
            } else if !containsHiragana(candidate),
                !trustedDirectCandidates.contains(candidate) {
                // Readings that look inflected should not prioritize pure-kanji name-like entries,
                // except for top-ranked direct dictionary candidates which are trusted common words.
                delta -= 260
            }

            if delta != 0 {
                scores[candidate, default: 0] += delta
            }
        }

        applyKuruCandidateBoost(for: reading, to: &scores)
        applyGodanImperativeBoost(
            for: reading,
            userDictionary: userDictionary,
            initialUserDictionary: initialUserDictionary,
            systemCandidateMode: systemCandidateMode,
            to: &scores
        )
    }

    private func hasMatchingInflectionRankingSuffix(
        _ candidate: String,
        readingSuffix: String
    ) -> Bool {
        if candidate.hasSuffix(readingSuffix) {
            return true
        }

        guard let katakanaSuffix = readingSuffix.applyingTransform(
            .hiraganaToKatakana,
            reverse: false
        ),
            katakanaSuffix != readingSuffix else {
            return false
        }

        return candidate.hasSuffix(katakanaSuffix)
    }

    private func applyNumericUnitFallbackPriorityBoost(
        for reading: String,
        fallbackCandidates: [String],
        to scores: inout [String: Int]
    ) {
        guard hasLeadingNumberPrefix(in: reading),
            !fallbackCandidates.isEmpty else {
            return
        }

        for candidate in fallbackCandidates {
            scores[candidate, default: 0] += Self.numericUnitFallbackCandidateBoost
        }
    }

    private func hasLeadingNumberPrefix(in text: String) -> Bool {
        let trimmed = trimmingLeadingNumberPrefix(from: text)
        return !trimmed.isEmpty && trimmed != text
    }

    private func applyGodanImperativeBoost(
        for reading: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode,
        to scores: inout [String: Int]
    ) {
        for pattern in Self.godanPatterns where reading.hasSuffix(pattern.eForm) {
            guard let stem = removingSuffix(reading, suffix: pattern.eForm) else {
                continue
            }

            let baseReading = stem + pattern.dictionaryEnding
            let baseCandidates = Set(
                candidatesForReading(
                    baseReading,
                    userDictionary: userDictionary,
                    initialUserDictionary: initialUserDictionary,
                    systemCandidateMode: systemCandidateMode
                )
            )

            guard !baseCandidates.isEmpty else {
                continue
            }

            for candidate in Array(scores.keys) where candidate.hasSuffix(pattern.eForm) {
                let candidateStem = String(candidate.dropLast(pattern.eForm.count))
                let baseCandidate = candidateStem + pattern.dictionaryEnding

                guard baseCandidates.contains(baseCandidate) else {
                    continue
                }

                scores[candidate, default: 0] += Self.godanImperativeCandidateBoost
            }
        }
    }

    private func applyKuruCandidateBoost(
        for reading: String,
        to scores: inout [String: Int]
    ) {
        for form in Self.kuruInflectionForms where reading.hasSuffix(form.readingSuffix) {
            for candidate in Array(scores.keys) where candidate.hasSuffix(form.kanjiOutputSuffix) {
                scores[candidate, default: 0] += Self.kuruKanjiCandidateBoost
            }
        }
    }

    private func matchingInflectionRankingSuffix(for reading: String) -> String? {
        for suffix in Self.inflectionRankingSuffixes where reading.hasSuffix(suffix) {
            return suffix
        }

        return nil
    }

    private func containsHiragana(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            if (0x3040...0x309F).contains(scalar.value) || scalar.value == 0x30FC {
                return true
            }
        }

        return false
    }

    private func inflectionCandidates(
        for reading: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode,
        limit: Int
    ) -> [String] {
        guard reading.count >= 2,
                limit > 0 else {
            return []
        }

        var derived: [String] = []

        // "行く" is irregular in te/ta forms (行って/行った), so place it first.
        derived.append(
            contentsOf: deriveIkuIrregularCandidates(
                for: reading,
                userDictionary: userDictionary,
                initialUserDictionary: initialUserDictionary,
                systemCandidateMode: systemCandidateMode
            )
        )

        for rule in Self.allInflectionRules {
            derived.append(
                contentsOf: derivedCandidates(
                    for: reading,
                    rule: rule,
                    userDictionary: userDictionary,
                    initialUserDictionary: initialUserDictionary,
                    systemCandidateMode: systemCandidateMode
                )
            )
        }

        return Array(uniqueCandidates(from: derived).prefix(limit))
    }

    private func adjectiveGaruCandidates(
        for reading: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode,
        limit: Int
    ) -> [String] {
        guard reading.count >= 3,
            limit > 0 else {
            return []
        }

        var derived: [String] = []

        for form in Self.adjectiveGaruInflectionForms where reading.hasSuffix(form.readingSuffix) {
            guard let readingStem = removingSuffix(reading, suffix: form.readingSuffix),
                !readingStem.isEmpty else {
                continue
            }

            let baseReading = readingStem + "い"
            let baseCandidates = candidatesForReading(
                baseReading,
                userDictionary: userDictionary,
                initialUserDictionary: initialUserDictionary,
                systemCandidateMode: systemCandidateMode
            )

            guard !baseCandidates.isEmpty else {
                continue
            }

            let metadata = inflectionMetadata(for: baseReading)
            let semanticMetadata = adjectiveGaruMetadata(for: baseReading)

            guard semanticMetadata.hasMetadata,
                !semanticMetadata.allowedCandidates.isEmpty else {
                continue
            }

            let userCandidateSet = Set(
                combinedUserCandidates(
                    for: baseReading,
                    userDictionary: userDictionary
                ) + (initialUserDictionary[baseReading] ?? [])
            )

            for candidate in baseCandidates {
                let resolvedClass = resolvedInflectionClass(
                    for: candidate,
                    baseReading: baseReading,
                    systemClassMap: metadata.classMap,
                    hasSystemMetadata: metadata.hasMetadata,
                    userCandidateSet: userCandidateSet
                )

                guard resolvedClass == InflectionClass.adjectiveI,
                    semanticMetadata.allowedCandidates.contains(candidate),
                    candidate.hasSuffix("い") else {
                    continue
                }

                let candidateStem = String(candidate.dropLast(1))
                derived.append(candidateStem + form.outputSuffix)
            }
        }

        return Array(uniqueCandidates(from: derived).prefix(limit))
    }

    private func postfixPassthroughCandidates(
        for reading: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode,
        limit: Int
    ) -> [String] {
        guard reading.count >= 2,
                limit > 0 else {
            return []
        }

        var derived: [String] = []
        var queue: [(stem: String, suffix: String, depth: Int)] = [(reading, "", 0)]
        var visited = Set<String>()

        while !queue.isEmpty {
            let current = queue.removeFirst()

            guard current.depth < Self.maxPostfixPassthroughDepth else {
                continue
            }

            for passthrough in Self.postfixPassthroughSuffixes where current.stem.hasSuffix(passthrough) {
                let nextStem = String(current.stem.dropLast(passthrough.count))

                guard !nextStem.isEmpty else {
                    continue
                }

                let nextSuffix = passthrough + current.suffix
                let visitKey = nextStem + "\u{1}" + nextSuffix

                guard visited.insert(visitKey).inserted else {
                    continue
                }

                let allowAttachment = !Self.explanatorySuffixRequiresPredicateStem(nextSuffix)
                    || Self.isPredicateLikeStemReading(nextStem)

                if allowAttachment {
                    let stemCandidates = uniqueCandidates(
                        from: candidatesForReading(
                            nextStem,
                            userDictionary: userDictionary,
                            initialUserDictionary: initialUserDictionary,
                            systemCandidateMode: systemCandidateMode
                        ) + inflectionCandidates(
                            for: nextStem,
                            userDictionary: userDictionary,
                            initialUserDictionary: initialUserDictionary,
                            systemCandidateMode: systemCandidateMode,
                            limit: limit
                        )
                    )

                    let nEndingFiltered = filterVerbStemFragmentCandidatesIfNeeded(
                        stemCandidates,
                        stemReading: nextStem,
                        nextSuffix: nextSuffix
                    )
                    let filteredStemCandidates = filterNonVerbalCandidatesForVerbalPostfix(
                        nEndingFiltered,
                        stemReading: nextStem,
                        nextSuffix: nextSuffix
                    )

                    for candidate in filteredStemCandidates {
                        for outputSuffix in Self.postfixOutputSuffixVariants(for: nextSuffix) {
                            derived.append(candidate + outputSuffix)
                        }
                    }
                }

                queue.append((nextStem, nextSuffix, current.depth + 1))
            }
        }

        return Array(uniqueCandidates(from: derived).prefix(limit))
    }

    private func politePrefixPassthroughCandidates(
        for reading: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode,
        limit: Int
    ) -> [String] {
        guard reading.count >= 2,
            limit > 0 else {
            return []
        }

        var derived: [String] = []

        for prefix in Self.politePrefixPassthroughPrefixes where reading.hasPrefix(prefix) {
            let stem = String(reading.dropFirst(prefix.count))

            guard !stem.isEmpty else {
                continue
            }

            derived.append(
                contentsOf: politePrefixSuruCandidates(
                    prefix: prefix,
                    stemReading: stem,
                    userDictionary: userDictionary,
                    initialUserDictionary: initialUserDictionary,
                    systemCandidateMode: systemCandidateMode
                )
            )

            derived.append(
                contentsOf: politePrefixRenyouCandidates(
                    prefix: prefix,
                    stemReading: stem,
                    userDictionary: userDictionary,
                    initialUserDictionary: initialUserDictionary,
                    systemCandidateMode: systemCandidateMode
                )
            )

            derived.append(
                contentsOf: politePrefixSoftRequestCandidates(
                    prefix: prefix,
                    stemReading: stem,
                    userDictionary: userDictionary,
                    initialUserDictionary: initialUserDictionary,
                    systemCandidateMode: systemCandidateMode
                )
            )

            let stemCandidates = candidatesForReading(
                stem,
                userDictionary: userDictionary,
                initialUserDictionary: initialUserDictionary,
                systemCandidateMode: systemCandidateMode
            )

            guard !stemCandidates.isEmpty else {
                continue
            }

            let metadata = inflectionMetadata(for: stem)
            let userCandidateSet = Set(
                combinedUserCandidates(
                    for: stem,
                    userDictionary: userDictionary
                ) + (initialUserDictionary[stem] ?? [])
            )

            for candidate in stemCandidates {
                let resolvedClass = resolvedInflectionClass(
                    for: candidate,
                    baseReading: stem,
                    systemClassMap: metadata.classMap,
                    hasSystemMetadata: metadata.hasMetadata,
                    userCandidateSet: userCandidateSet
                )

                guard !shouldSkipPolitePrefixCandidate(
                    prefix,
                    candidate: candidate,
                    resolvedClass: resolvedClass
                ) else {
                    continue
                }

                guard shouldApplyPolitePrefix(prefix, to: candidate) else {
                    continue
                }

                derived.append(prefix + candidate)
            }
        }

        return Array(uniqueCandidates(from: derived).prefix(limit))
    }

    private func politePrefixSoftRequestCandidates(
        prefix: String,
        stemReading: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        guard prefix == "お" else {
            return []
        }

        var derived: [String] = []

        for requestSuffix in Self.honorificOSoftRequestSuffixes where stemReading.hasSuffix(requestSuffix) {
            guard let baseStemReading = removingSuffix(stemReading, suffix: requestSuffix),
                !baseStemReading.isEmpty else {
                continue
            }

            derived.append(
                contentsOf: politePrefixDirectStemCandidates(
                    prefix: prefix,
                    stemReading: baseStemReading,
                    trailingSuffix: requestSuffix,
                    userDictionary: userDictionary,
                    initialUserDictionary: initialUserDictionary,
                    systemCandidateMode: systemCandidateMode
                )
            )

            derived.append(
                contentsOf: politePrefixRenyouCandidates(
                    prefix: prefix,
                    trailingSuffix: requestSuffix,
                    renyouReading: baseStemReading,
                    userDictionary: userDictionary,
                    initialUserDictionary: initialUserDictionary,
                    systemCandidateMode: systemCandidateMode
                )
            )
        }

        return uniqueCandidates(from: derived)
    }

    private func politePrefixDirectStemCandidates(
        prefix: String,
        stemReading: String,
        trailingSuffix: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        guard !stemReading.isEmpty else {
            return []
        }

        let stemCandidates = candidatesForReading(
            stemReading,
            userDictionary: userDictionary,
            initialUserDictionary: initialUserDictionary,
            systemCandidateMode: systemCandidateMode
        )

        guard !stemCandidates.isEmpty else {
            return []
        }

        let metadata = inflectionMetadata(for: stemReading)
        var derived: [String] = []

        for candidate in stemCandidates {
            let resolvedClass = metadata.classMap[candidate]

            guard !shouldSkipPolitePrefixCandidate(
                prefix,
                candidate: candidate,
                resolvedClass: resolvedClass
            ) else {
                continue
            }

            guard shouldApplyPolitePrefix(prefix, to: candidate) else {
                continue
            }

            derived.append(prefix + candidate + trailingSuffix)
        }

        return uniqueCandidates(from: derived)
    }

    private func politePrefixRenyouCandidates(
        prefix: String,
        stemReading: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        guard prefix == "お" else {
            return []
        }

        var derived: [String] = []

        derived.append(
            contentsOf: politePrefixRenyouCandidates(
                prefix: prefix,
                trailingSuffix: "",
                renyouReading: stemReading,
                userDictionary: userDictionary,
                initialUserDictionary: initialUserDictionary,
                systemCandidateMode: systemCandidateMode
            )
        )

        for naruSuffix in Self.honorificONaruInflectionSuffixes where stemReading.hasSuffix(naruSuffix) {
            guard let renyouReading = removingSuffix(stemReading, suffix: naruSuffix),
                !renyouReading.isEmpty else {
                continue
            }

            derived.append(
                contentsOf: politePrefixRenyouCandidates(
                    prefix: prefix,
                    trailingSuffix: naruSuffix,
                    renyouReading: renyouReading,
                    userDictionary: userDictionary,
                    initialUserDictionary: initialUserDictionary,
                    systemCandidateMode: systemCandidateMode
                )
            )
        }

        return uniqueCandidates(from: derived)
    }

    private func politePrefixRenyouCandidates(
        prefix: String,
        trailingSuffix: String,
        renyouReading: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        guard !renyouReading.isEmpty else {
            return []
        }

        var derived: [String] = []

        derived.append(
            contentsOf: politePrefixRenyouCandidates(
                prefix: prefix,
                trailingSuffix: trailingSuffix,
                baseReading: renyouReading + "る",
                expectedInflectionClass: InflectionClass.ichidan,
                dictionaryEnding: "る",
                renyouEnding: "",
                userDictionary: userDictionary,
                initialUserDictionary: initialUserDictionary,
                systemCandidateMode: systemCandidateMode
            )
        )

        for pattern in Self.godanPatterns where renyouReading.hasSuffix(pattern.iForm) {
            guard let readingStem = removingSuffix(renyouReading, suffix: pattern.iForm) else {
                continue
            }

            let baseReading = readingStem + pattern.dictionaryEnding

            derived.append(
                contentsOf: politePrefixRenyouCandidates(
                    prefix: prefix,
                    trailingSuffix: trailingSuffix,
                    baseReading: baseReading,
                    expectedInflectionClass: pattern.inflectionClass,
                    dictionaryEnding: pattern.dictionaryEnding,
                    renyouEnding: pattern.iForm,
                    userDictionary: userDictionary,
                    initialUserDictionary: initialUserDictionary,
                    systemCandidateMode: systemCandidateMode
                )
            )
        }

        return uniqueCandidates(from: derived)
    }

    private func politePrefixRenyouCandidates(
        prefix: String,
        trailingSuffix: String,
        baseReading: String,
        expectedInflectionClass: String,
        dictionaryEnding: String,
        renyouEnding: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        guard !baseReading.isEmpty,
            !dictionaryEnding.isEmpty else {
            return []
        }

        let baseCandidates = candidatesForReading(
            baseReading,
            userDictionary: userDictionary,
            initialUserDictionary: initialUserDictionary,
            systemCandidateMode: systemCandidateMode
        )

        guard !baseCandidates.isEmpty else {
            return []
        }

        let metadata = inflectionMetadata(for: baseReading)
        let userCandidateSet = Set(
            combinedUserCandidates(
                for: baseReading,
                userDictionary: userDictionary
            ) + (initialUserDictionary[baseReading] ?? [])
        )
        var derived: [String] = []

        for candidate in baseCandidates {
            let resolvedClass = resolvedInflectionClass(
                for: candidate,
                baseReading: baseReading,
                systemClassMap: metadata.classMap,
                hasSystemMetadata: metadata.hasMetadata,
                userCandidateSet: userCandidateSet
            )

            guard resolvedClass == expectedInflectionClass,
                candidate.hasSuffix(dictionaryEnding) else {
                continue
            }

            let stem = String(candidate.dropLast(dictionaryEnding.count))
            let renyouCandidate = stem + renyouEnding

            guard shouldApplyPolitePrefix(prefix, to: renyouCandidate) else {
                continue
            }

            derived.append(prefix + renyouCandidate + trailingSuffix)
        }

        return uniqueCandidates(from: derived)
    }

    private func politePrefixSuruCandidates(
        prefix: String,
        stemReading: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        guard prefix == "お" else {
            return []
        }

        var derived: [String] = []

        for suruSuffix in Self.honorificOSuruInflectionSuffixes() where stemReading.hasSuffix(suruSuffix) {
            guard let renyouReading = removingSuffix(stemReading, suffix: suruSuffix),
                !renyouReading.isEmpty else {
                continue
            }

            derived.append(
                contentsOf: politePrefixSuruCandidates(
                    prefix: prefix,
                    suruSuffix: suruSuffix,
                    baseReading: renyouReading + "る",
                    expectedInflectionClass: InflectionClass.ichidan,
                    dictionaryEnding: "る",
                    renyouEnding: "",
                    userDictionary: userDictionary,
                    initialUserDictionary: initialUserDictionary,
                    systemCandidateMode: systemCandidateMode
                )
            )

            for pattern in Self.godanPatterns where renyouReading.hasSuffix(pattern.iForm) {
                guard let readingStem = removingSuffix(renyouReading, suffix: pattern.iForm) else {
                    continue
                }

                let baseReading = readingStem + pattern.dictionaryEnding

                derived.append(
                    contentsOf: politePrefixSuruCandidates(
                        prefix: prefix,
                        suruSuffix: suruSuffix,
                        baseReading: baseReading,
                        expectedInflectionClass: pattern.inflectionClass,
                        dictionaryEnding: pattern.dictionaryEnding,
                        renyouEnding: pattern.iForm,
                        userDictionary: userDictionary,
                        initialUserDictionary: initialUserDictionary,
                        systemCandidateMode: systemCandidateMode
                    )
                )
            }
        }

        return uniqueCandidates(from: derived)
    }

    private func politePrefixSuruCandidates(
        prefix: String,
        suruSuffix: String,
        baseReading: String,
        expectedInflectionClass: String,
        dictionaryEnding: String,
        renyouEnding: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        guard !baseReading.isEmpty,
            !dictionaryEnding.isEmpty else {
            return []
        }

        let baseCandidates = candidatesForReading(
            baseReading,
            userDictionary: userDictionary,
            initialUserDictionary: initialUserDictionary,
            systemCandidateMode: systemCandidateMode
        )

        guard !baseCandidates.isEmpty else {
            return []
        }

        let metadata = inflectionMetadata(for: baseReading)
        let userCandidateSet = Set(
            combinedUserCandidates(
                for: baseReading,
                userDictionary: userDictionary
            ) + (initialUserDictionary[baseReading] ?? [])
        )
        var derived: [String] = []

        for candidate in baseCandidates {
            let resolvedClass = resolvedInflectionClass(
                for: candidate,
                baseReading: baseReading,
                systemClassMap: metadata.classMap,
                hasSystemMetadata: metadata.hasMetadata,
                userCandidateSet: userCandidateSet
            )

            guard resolvedClass == expectedInflectionClass,
                candidate.hasSuffix(dictionaryEnding) else {
                continue
            }

            let stem = String(candidate.dropLast(dictionaryEnding.count))
            let renyouCandidate = stem + renyouEnding

            guard shouldApplyPolitePrefix(prefix, to: renyouCandidate) else {
                continue
            }

            derived.append(prefix + renyouCandidate + suruSuffix)
        }

        return uniqueCandidates(from: derived)
    }

    private func shouldSkipPolitePrefixCandidate(
        _ prefix: String,
        candidate: String,
        resolvedClass: String?
    ) -> Bool {
        guard let resolvedClass else {
            return false
        }

        // Allow honorific-go for sahen nouns like "相談" that may be tagged as suru-capable.
        if prefix == "ご",
            resolvedClass == InflectionClass.suru,
            !candidate.hasSuffix("する") {
            return false
        }

        return true
    }

    private func ordinalMeFallbackCandidates(
        for reading: String,
        hasDirectCandidates: Bool,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode,
        limit: Int
    ) -> [String] {
        guard !hasDirectCandidates,
            reading.count >= 2,
            reading.hasSuffix("め"),
            limit > 0 else {
            return []
        }

        let stem = String(reading.dropLast(1))

        guard !stem.isEmpty else {
            return []
        }

        var stemCandidates = uniqueCandidates(
            from: candidatesForReading(
                stem,
                userDictionary: userDictionary,
                initialUserDictionary: initialUserDictionary,
                systemCandidateMode: systemCandidateMode
            ) + inflectionCandidates(
                for: stem,
                userDictionary: userDictionary,
                initialUserDictionary: initialUserDictionary,
                systemCandidateMode: systemCandidateMode,
                limit: limit
            )
        )

        if stemCandidates.isEmpty {
            let trimmedStem = trimmingLeadingNumberPrefix(from: stem)

            if !trimmedStem.isEmpty,
                trimmedStem != stem {
                stemCandidates = uniqueCandidates(
                    from: candidatesForReading(
                        trimmedStem,
                        userDictionary: userDictionary,
                        initialUserDictionary: initialUserDictionary,
                        systemCandidateMode: systemCandidateMode
                    ) + inflectionCandidates(
                        for: trimmedStem,
                        userDictionary: userDictionary,
                        initialUserDictionary: initialUserDictionary,
                        systemCandidateMode: systemCandidateMode,
                        limit: limit
                    )
                )
            }
        }

        guard !stemCandidates.isEmpty else {
            return []
        }

        let kanjiStemCandidates = stemCandidates.filter(containsKanji)
        let nonKanjiStemCandidates = stemCandidates.filter { !containsKanji($0) }

        guard !kanjiStemCandidates.isEmpty else {
            return []
        }

        var derived: [String] = []

        for candidate in kanjiStemCandidates {
            derived.append(candidate + "め")
        }

        for candidate in nonKanjiStemCandidates {
            derived.append(candidate + "め")
        }

        // Keep kanji+"目" candidates available, but behind kanji+"め".
        for candidate in kanjiStemCandidates {
            derived.append(candidate + "目")
        }

        return Array(uniqueCandidates(from: derived).prefix(limit))
    }

    private func numericUnitFallbackCandidates(
        for reading: String,
        limit: Int
    ) -> [String] {
        guard limit > 0 else {
            return []
        }

        var lookupKeys = [reading]
        let trimmedReading = trimmingLeadingNumberPrefix(from: reading)

        if !trimmedReading.isEmpty,
            trimmedReading != reading {
            lookupKeys.append(trimmedReading)
        }

        var derived: [String] = []

        for key in lookupKeys {
            if let fallbackCandidates = Self.numericUnitFallbackCandidatesByReading[key] {
                derived.append(contentsOf: fallbackCandidates)
            }
        }

        return Array(uniqueCandidates(from: derived).prefix(limit))
    }

    private func numericCounterCompoundCandidates(
        for reading: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode,
        limit: Int
    ) -> [String] {
        guard limit > 0 else {
            return []
        }

        var derived: [String] = []

        for (prefixReading, allowedPrefixes) in Self.numericCounterPrefixCandidatesByReading {
            guard reading.hasPrefix(prefixReading) else {
                continue
            }

            let suffixReading = String(reading.dropFirst(prefixReading.count))

            guard !suffixReading.isEmpty else {
                continue
            }

            if let allowedSuffixReadings = Self.numericCounterAllowedSuffixReadingsByPrefixReading[prefixReading],
                !allowedSuffixReadings.contains(suffixReading) {
                continue
            }

            guard let allowedSuffixes = Self.numericCounterSuffixCandidatesByReading[suffixReading] else {
                continue
            }

            let prefixCandidates = uniqueCandidates(
                from: candidatesForReading(
                    prefixReading,
                    userDictionary: userDictionary,
                    initialUserDictionary: initialUserDictionary,
                    systemCandidateMode: systemCandidateMode
                )
            ).filter { allowedPrefixes.contains($0) }

            let resolvedPrefixCandidates = prefixCandidates.isEmpty
                ? allowedPrefixes
                : prefixCandidates

            let suffixCandidates = uniqueCandidates(
                from: candidatesForReading(
                    suffixReading,
                    userDictionary: userDictionary,
                    initialUserDictionary: initialUserDictionary,
                    systemCandidateMode: systemCandidateMode
                )
            ).filter { allowedSuffixes.contains($0) }

            let resolvedSuffixCandidates = suffixCandidates.isEmpty
                ? allowedSuffixes
                : suffixCandidates

            for prefixCandidate in resolvedPrefixCandidates {
                for suffixCandidate in resolvedSuffixCandidates {
                    derived.append(prefixCandidate + suffixCandidate)
                }
            }
        }

        // 桁(千/百/万…)を挟む汎用パス: 接頭 + 桁+ + (助数詞 | 分の一 | ∅)。
        // 例: すうせんねん→数千年, なんびゃくねん→何百年, すうせんぶんのいち→数千分の一。
        // 接頭直結の助数詞(数年・三本等)は上の既存パスが拗音・連濁制約付きで担当し、
        // ここは必ず桁を1つ以上含む組(または接頭+分の一)のみを生成する。
        for (prefixReading, allowedPrefixes) in Self.numericCounterPrefixCandidatesByReading {
            guard reading.hasPrefix(prefixReading) else {
                continue
            }

            let afterPrefix = String(reading.dropFirst(prefixReading.count))

            guard !afterPrefix.isEmpty else {
                continue
            }

            let prefixCandidates = uniqueCandidates(
                from: candidatesForReading(
                    prefixReading,
                    userDictionary: userDictionary,
                    initialUserDictionary: initialUserDictionary,
                    systemCandidateMode: systemCandidateMode
                )
            ).filter { allowedPrefixes.contains($0) }

            let resolvedPrefixCandidates = prefixCandidates.isEmpty
                ? allowedPrefixes
                : prefixCandidates

            var tailCandidates: [String] = []

            // 桁始まり: 桁+ (助数詞 | 分の一 | ∅)
            for magnitude in Self.numericMagnitudeCandidatesByReading
                where afterPrefix.hasPrefix(magnitude.reading) {
                let afterMagnitude = String(afterPrefix.dropFirst(magnitude.reading.count))

                for tail in numericMagnitudeTailCandidates(for: afterMagnitude) {
                    tailCandidates.append(magnitude.candidate + tail)
                }
            }

            // 桁なしの分数: 接頭 + 分の一 (例: すうぶんのいち→数分の一)
            if let fractions = Self.numericFractionSuffixCandidatesByReading[afterPrefix] {
                tailCandidates.append(contentsOf: fractions)
            }

            for prefixCandidate in resolvedPrefixCandidates {
                for tail in tailCandidates {
                    derived.append(prefixCandidate + tail)
                }
            }
        }

        return Array(uniqueCandidates(from: derived).prefix(limit))
    }

    // 桁の連なりと末尾(助数詞 | 分の一 | ∅)を読みから分解し、漢字列候補を返す。
    // ∅(空文字)は桁を1つ以上消費済みの場合のみ許可し、「数千」等の助数詞なしを表す。
    private func numericMagnitudeTailCandidates(
        for reading: String,
        magnitudeConsumed: Bool = true
    ) -> [String] {
        if reading.isEmpty {
            return magnitudeConsumed ? [""] : []
        }

        var results: [String] = []

        if let counters = Self.numericCounterSuffixCandidatesByReading[reading] {
            results.append(contentsOf: counters)
        }

        if let fractions = Self.numericFractionSuffixCandidatesByReading[reading] {
            results.append(contentsOf: fractions)
        }

        for magnitude in Self.numericMagnitudeCandidatesByReading
            where reading.hasPrefix(magnitude.reading) {
            let rest = String(reading.dropFirst(magnitude.reading.count))

            for tail in numericMagnitudeTailCandidates(for: rest, magnitudeConsumed: true) {
                results.append(magnitude.candidate + tail)
            }
        }

        return results
    }

    // 名詞に付く生産的な漢字接辞を組み合わせる: 語幹(名詞)+別(種類別)、別+語幹(別会社)。
    // 語幹は漢字を含む候補に限り、1モーラ語幹(区別/差別等の誤分割)は除外する。
    // 辞書語(餞別等)は system 候補が上位に来るため、補完として低めのスコアで併置する。
    private func nounKanjiAffixCandidates(
        for reading: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode,
        limit: Int
    ) -> [String] {
        guard reading.count >= 4,
            limit > 0 else {
            return []
        }

        func kanjiStemCandidates(for stemReading: String) -> [String] {
            uniqueCandidates(
                from: candidatesForReading(
                    stemReading,
                    userDictionary: userDictionary,
                    initialUserDictionary: initialUserDictionary,
                    systemCandidateMode: systemCandidateMode
                )
            ).filter { containsKanji($0) }
        }

        var derived: [String] = []

        for affix in Self.nounKanjiSuffixAffixCandidatesByReading
            where reading.hasSuffix(affix.reading) {
            let stem = String(reading.dropLast(affix.reading.count))

            guard stem.count >= 2 else {
                continue
            }

            for candidate in kanjiStemCandidates(for: stem).prefix(6) {
                derived.append(candidate + affix.candidate)
            }
        }

        for affix in Self.nounKanjiPrefixAffixCandidatesByReading
            where reading.hasPrefix(affix.reading) {
            let stem = String(reading.dropFirst(affix.reading.count))

            guard stem.count >= 2 else {
                continue
            }

            for candidate in kanjiStemCandidates(for: stem).prefix(6) {
                derived.append(affix.candidate + candidate)
            }
        }

        return Array(uniqueCandidates(from: derived).prefix(limit))
    }

    private func shouldApplyPolitePrefix(_ prefix: String, to candidate: String) -> Bool {
        guard !candidate.hasPrefix(prefix),
            !candidate.hasPrefix("御"),
            let firstScalar = candidate.unicodeScalars.first else {
            return false
        }

        if (0x4E00...0x9FFF).contains(firstScalar.value)
            || (0x3400...0x4DBF).contains(firstScalar.value)
            || firstScalar.value == 0x3005 {
            return true
        }

        return false
    }

    private func deriveIkuIrregularCandidates(
        for reading: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        var results: [String] = []

        for irregularSuffix in Self.ikuIrregularInflectionSuffixes {
            guard let stem = removingSuffix(reading, suffix: irregularSuffix) else {
                continue
            }

            let baseReading = stem + "く"
            for candidate in candidatesForReading(
                baseReading,
                userDictionary: userDictionary,
                initialUserDictionary: initialUserDictionary,
                systemCandidateMode: systemCandidateMode
            ) where candidate.hasSuffix("行く") {
                let prefix = String(candidate.dropLast("行く".count))
                results.append(prefix + "行" + irregularSuffix)
            }
        }

        return results
    }

    private func derivedCandidates(
        for reading: String,
        rule: InflectionRule,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        guard let readingStem = removingSuffix(reading, suffix: rule.readingSuffix) else {
            return []
        }

        if readingStem.isEmpty,
            !Self.emptyStemAllowedBaseReadingSuffixes.contains(rule.baseReadingSuffix) {
            return []
        }

        let baseReading = readingStem + rule.baseReadingSuffix

        let baseCandidates = candidatesForReading(
            baseReading,
            userDictionary: userDictionary,
            initialUserDictionary: initialUserDictionary,
            systemCandidateMode: systemCandidateMode
        )

        guard !baseCandidates.isEmpty else {
            return []
        }

        let metadata = inflectionMetadata(for: baseReading)
        // resolvedInflectionClass の「user 候補は inference 許可」用には initialUserDictionary 等も含めるが、
        // inferredSahenInflectionClass の「user 自身が追加したものだけ救済」用は
        // initialUserDictionary(references plist 由来。migration で userDictionary にもマージされる)
        // と一致する候補を除いた、本当の手動追加分のみに絞る。
        let initialCandidatesForBase = Set(initialUserDictionary[baseReading] ?? [])
        let initialOrUserCandidateSet = Set(
            combinedUserCandidates(
                for: baseReading,
                userDictionary: userDictionary
            )
        ).union(initialCandidatesForBase)
        let userOwnCandidateSet = Set(
            combinedUserCandidates(
                for: baseReading,
                userDictionary: userDictionary
            )
        ).subtracting(initialCandidatesForBase)
        var results: [String] = []

        for candidate in baseCandidates {
            guard let matchedSuffix = rule.baseCandidateSuffixes.first(where: { candidate.hasSuffix($0) }) else {
                continue
            }

            let resolvedClass = resolvedInflectionClass(
                for: candidate,
                baseReading: baseReading,
                systemClassMap: metadata.classMap,
                hasSystemMetadata: metadata.hasMetadata,
                userCandidateSet: initialOrUserCandidateSet
            )

            let inflectionClass = resolvedClass
                ?? inferredSahenInflectionClass(
                    for: candidate,
                    baseReading: baseReading,
                    rule: rule,
                    userCandidateSet: userOwnCandidateSet
                )
                ?? inferredExplicitSuruInflectionClass(
                    for: candidate,
                    rule: rule
                )

            guard let inflectionClass,
                rule.allowedClasses.contains(inflectionClass) else {
                continue
            }

            let stem = String(candidate.dropLast(matchedSuffix.count))
            results.append(stem + rule.outputCandidateSuffix)
        }

        return results
    }

    private func inflectionMetadata(for reading: String) -> (classMap: [String: String], hasMetadata: Bool) {
        store.systemInflectionMetadata(for: reading)
    }

    private func adjectiveGaruMetadata(
        for reading: String
    ) -> (allowedCandidates: Set<String>, hasMetadata: Bool) {
        let metadata = store.systemCandidates(
            for: reading,
            taggedWith: KanaKanjiCandidateSourceTag.adjectiveGaru
        )

        return (
            allowedCandidates: metadata.candidates,
            hasMetadata: metadata.hasMetadata
        )
    }

    private func resolvedInflectionClass(
        for candidate: String,
        baseReading: String,
        systemClassMap: [String: String],
        hasSystemMetadata: Bool,
        userCandidateSet: Set<String>
    ) -> String? {
        if let inflectionClass = systemClassMap[candidate] {
            return inflectionClass
        }

        // Keep inference only as fallback for user dictionary entries.
        guard !hasSystemMetadata || userCandidateSet.contains(candidate) else {
            return nil
        }

        return inferredInflectionClass(for: candidate, baseReading: baseReading)
    }

    private func inferredSahenInflectionClass(
        for candidate: String,
        baseReading: String,
        rule: InflectionRule,
        userCandidateSet: Set<String>
    ) -> String? {
        guard rule.baseReadingSuffix.isEmpty,
            rule.allowedClasses == [InflectionClass.suru],
            !candidate.hasSuffix("する"),
            !candidate.hasSuffix("くる"),
            !candidate.hasSuffix("来る"),
            containsKanjiOrKatakana(candidate) else {
            return nil
        }

        // システム辞書がサ変クラス情報を持っている前提では、明示的に classMap に
        // 載っていない候補(りんご→林檎、ぶどう→葡萄 等)は「辞書がサ変ではないと判定」
        // とみなして推論しない。ユーザ追加の候補のみ推論で救済する。
        guard userCandidateSet.contains(candidate) else {
            return nil
        }

        if !containsHiragana(candidate) {
            return InflectionClass.suru
        }

        if isLikelySahenPhraseStem(candidate) {
            return InflectionClass.suru
        }

        guard Self.mixedScriptSahenOptInReadings.contains(baseReading) else {
            return nil
        }

        return InflectionClass.suru
    }

    private func isLikelySahenPhraseStem(_ candidate: String) -> Bool {
        guard containsKanji(candidate) else {
            return false
        }

        for suffix in Self.sahenPhraseParticleSuffixes where candidate.hasSuffix(suffix) {
            let stem = String(candidate.dropLast(suffix.count))

            guard !stem.isEmpty,
                containsKanji(stem) else {
                continue
            }

            return true
        }

        return false
    }

    private func inferredExplicitSuruInflectionClass(
        for candidate: String,
        rule: InflectionRule
    ) -> String? {
        guard rule.allowedClasses.contains(InflectionClass.suru),
            candidate.hasSuffix("する") else {
            return nil
        }

        return InflectionClass.suru
    }

    private func inferredInflectionClass(for candidate: String, baseReading: String) -> String? {
        if candidate.hasSuffix("する") {
            return InflectionClass.suru
        }

        if candidate.hasSuffix("来る") || candidate.hasSuffix("くる") {
            return InflectionClass.kuru
        }

        if Self.godanRuKanjiSuffixOverrides.contains(where: { candidate.hasSuffix($0) }) {
            return InflectionClass.godanRu
        }

        if baseReading.hasSuffix("る") && candidate.hasSuffix("る") {
            if isLikelyIchidanBaseReading(baseReading) {
                return InflectionClass.ichidan
            }

            return InflectionClass.godanRu
        }

        for pattern in Self.godanPatterns where baseReading.hasSuffix(pattern.dictionaryEnding) {
            if candidate.hasSuffix(pattern.dictionaryEnding) {
                return pattern.inflectionClass
            }
        }

        if baseReading.hasSuffix("い") && candidate.hasSuffix("い") {
            return InflectionClass.adjectiveI
        }

        return nil
    }

    private func isLikelyIchidanBaseReading(_ reading: String) -> Bool {
        guard reading.hasSuffix("る"),
                reading.count >= 2 else {
            return false
        }

        let chars = Array(reading)
        let preRu = chars[chars.count - 2]

        return Self.iVowelKanaBeforeRu.contains(preRu)
            || Self.eVowelKanaBeforeRu.contains(preRu)
    }

    private func containsKanjiOrKatakana(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            if (0x30A0...0x30FF).contains(scalar.value)
                || (0x3400...0x9FFF).contains(scalar.value) {
                return true
            }
        }

        return false
    }

    private func containsKanji(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            if (0x3400...0x9FFF).contains(scalar.value) {
                return true
            }
        }

        return false
    }

    private func systemCandidates(
        for reading: String,
        mode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        let storeCandidates = store.systemCandidates(for: reading, mode: mode)
        let seedCandidates = KanaKanjiSeedDictionary.seed[reading] ?? []

        let mergedCandidates: [String]

        if storeCandidates.isEmpty {
            mergedCandidates = seedCandidates
        } else {
            mergedCandidates = uniqueCandidates(
                from: storeCandidates + seedCandidates
            )
        }

        let archaicAdjectiveFiltered = filterArchaicAdjectiveSurfaceCandidates(
            for: reading,
            candidates: mergedCandidates
        )

        return filterHistoricalKanaSurfaceCandidates(
            for: reading,
            candidates: archaicAdjectiveFiltered
        )
    }

    private func filterHistoricalKanaSurfaceCandidates(
        for reading: String,
        candidates: [String]
    ) -> [String] {
        let allowed = stateQueue.sync { historicalKanaSurfaceAllowed }

        guard !allowed,
            reading.hasSuffix("える") else {
            return candidates
        }

        return candidates.filter { candidate in
            guard candidate.count >= 2,
                candidate.hasSuffix("へる") else {
                return true
            }

            return false
        }
    }

    private func filterArchaicAdjectiveSurfaceCandidates(
        for reading: String,
        candidates: [String]
    ) -> [String] {
        filterArchaicAdjectiveSurfaceCandidates(
            for: reading,
            candidates: candidates,
            userDictionary: nil,
            learnedDictionary: nil,
            initialUserDictionary: nil
        )
    }

    private func filterArchaicAdjectiveSurfaceCandidates(
        for reading: String,
        candidates: [String],
        userDictionary: [String: [String]]?,
        learnedDictionary: [String: [String]]?,
        initialUserDictionary: [String: [String]]?
    ) -> [String] {
        guard reading.hasSuffix("かる") || reading.hasSuffix("かり") else {
            return candidates
        }

        guard let baseReadingStem = removingSuffix(reading, suffix: "かる")
            ?? removingSuffix(reading, suffix: "かり"),
            !baseReadingStem.isEmpty else {
            return candidates
        }

        let baseReading = baseReadingStem + "い"
        let userBaseCandidates = userDictionary?[baseReading] ?? []
        let learnedBaseCandidates = learnedDictionary?[baseReading] ?? []
        let initialBaseCandidates = initialUserDictionary?[baseReading] ?? []
        let storeBaseCandidates = store.systemCandidates(
            for: baseReading,
            mode: .lesDeux
        )
        let seedBaseCandidates = KanaKanjiSeedDictionary.seed[baseReading] ?? []
        let baseCandidates = Set(
            uniqueCandidates(
                from: userBaseCandidates
                    + learnedBaseCandidates
                    + initialBaseCandidates
                    + storeBaseCandidates
                    + seedBaseCandidates
            )
        )

        guard !baseCandidates.isEmpty else {
            return candidates
        }

        var filtered: [String] = []

        for candidate in candidates {
            guard candidate.hasSuffix("かる") || candidate.hasSuffix("かり") else {
                filtered.append(candidate)
                continue
            }

            guard candidate.count > 2 else {
                filtered.append(candidate)
                continue
            }

            let stem = String(candidate.dropLast(2))
            let modernIAdjective = stem + "い"

            if baseCandidates.contains(modernIAdjective) {
                continue
            }

            filtered.append(candidate)
        }

        return filtered
    }

    private func candidatesForReading(
        _ reading: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        let normalizedReading = KanaTextNormalizer.normalizedReading(reading)

        guard !normalizedReading.isEmpty else {
            return []
        }

        let candidates = uniqueCandidates(
            from: combinedUserCandidates(
                for: normalizedReading,
                userDictionary: userDictionary
            ) + (initialUserDictionary[normalizedReading] ?? [])
                + systemCandidates(for: normalizedReading, mode: systemCandidateMode)
        )

        let suppressedByReading = store.suppressedCandidatesByReading()

        guard !suppressedByReading.isEmpty else {
            return candidates
        }

        let directSuppressed = suppressedByReading[normalizedReading] ?? []

        return candidates.filter { candidate in
            if directSuppressed.contains(candidate) {
                return false
            }

            return !isDeinflectedSuppressed(
                candidate: candidate,
                reading: normalizedReading,
                suppressedByReading: suppressedByReading
            )
        }
    }

    private func combinedUserCandidates(
        for reading: String,
        userDictionary: [String: [String]]
    ) -> [String] {
        let normalizedReading = KanaTextNormalizer.normalizedReading(reading)

        guard !normalizedReading.isEmpty else {
            return []
        }

        let learnedDictionary = store.learnedDictionary()

        return uniqueCandidates(
            from: (userDictionary[normalizedReading] ?? [])
                + (learnedDictionary[normalizedReading] ?? [])
        )
    }

    private func removingSuffix(_ text: String, suffix: String) -> String? {
        guard !suffix.isEmpty,
                text.hasSuffix(suffix) else {
            return nil
        }

        return String(text.dropLast(suffix.count))
    }

    private func trimmingLeadingNumberPrefix(from text: String) -> String {
        String(text.drop(while: { $0.isNumber }))
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
}
