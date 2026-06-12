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
        "かい": ["回"],
        "かげつ": ["か月", "カ月", "ヶ月", "ヵ月", "箇月"],
        "かしょ": ["か所", "箇所", "カ所", "ヶ所", "ヵ所"],
        "けん": ["件"],
        "しゅうかん": ["週間"],
        "じかん": ["時間"],
        "じつ": ["日"],
        "だい": ["台"],
        "にん": ["人"],
        "ねん": ["年"],
        "ほん": ["本"],
        "びょう": ["秒"],
        "ふん": ["分"],
        "ひき": ["匹"],
        "ぼん": ["本"],
        "びき": ["匹"],
        "まい": ["枚"],
        "ぽん": ["本"],
        "ぴき": ["匹"],
        "はい": ["倍"],
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
        "なん": ["はい", "ばい", "はつ", "ぱつ", "ぼん", "びき"],
        "はっ": ["ぽん", "ぴき"],
        "よん": ["ほん", "ひき"],
        "ろっ": ["ぽん", "ぴき"],
        "すう": [
            "こ", "かい", "かげつ", "かしょ", "けん", "しゅうかん", "じかん", "じつ", "だい", "にん", "ねん",
            "はい", "ばい", "はつ", "ぱつ", "びょう", "ふん", "ひき", "ほん", "まい"
        ]
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

    init(store: KanaKanjiStore) {
        self.store = store
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

        let filteredSortedCandidates = filterArchaicAdjectiveSurfaceCandidates(
            for: normalizedReading,
            candidates: sortedCandidates,
            userDictionary: userDictionary,
            learnedDictionary: learnedDictionary,
            initialUserDictionary: initialUserDictionary
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
            fromSystemCandidates: systemCandidates
        )

        for candidate in matchingCandidates where Self.isPureKatakanaCandidate(candidate) {
            if protectedKatakanaCandidates.contains(candidate) {
                continue
            }

            let penalizedScore = scores[candidate, default: 0] - Self.sameReadingPureKatakanaPenalty
            scores[candidate] = min(penalizedScore, lowestNonKatakanaScore - 1)
        }
    }

    private func preferredLeadingKatakanaCandidates(fromSystemCandidates candidates: [String]) -> Set<String> {
        let uniqueSystemCandidates = uniqueCandidates(from: candidates)

        guard !uniqueSystemCandidates.isEmpty else {
            return []
        }

        var protectedCandidates = Set<String>()

        for candidate in uniqueSystemCandidates {
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

            let stemKey = CandidateCacheKey(
                reading: stem,
                limit: limit,
                modeRawValue: systemCandidateMode.rawValue
            )

            guard let stemCandidates = stateQueue.sync(execute: { candidateCache[stemKey] }),
                    !stemCandidates.isEmpty else {
                continue
            }

            let suffixVariants = Self.postfixOutputSuffixVariants(for: passthrough)
            let derived = stemCandidates.flatMap { candidate in
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

        for candidate in Array(scores.keys) {
            var delta = 0

            if hasMatchingInflectionRankingSuffix(candidate, readingSuffix: matchedSuffix) {
                delta += 220
            } else if !containsHiragana(candidate) {
                // Readings that look inflected should not prioritize pure-kanji name-like entries.
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

                for candidate in stemCandidates {
                    for outputSuffix in Self.postfixOutputSuffixVariants(for: nextSuffix) {
                        derived.append(candidate + outputSuffix)
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
        let userCandidateSet = Set(
            combinedUserCandidates(
                for: baseReading,
                userDictionary: userDictionary
            ) + (initialUserDictionary[baseReading] ?? [])
        )
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
                userCandidateSet: userCandidateSet
            )

            let inflectionClass = resolvedClass
                ?? inferredSahenInflectionClass(
                    for: candidate,
                    baseReading: baseReading,
                    rule: rule
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
        rule: InflectionRule
    ) -> String? {
        guard rule.baseReadingSuffix.isEmpty,
            rule.allowedClasses == [InflectionClass.suru],
            !candidate.hasSuffix("する"),
            !candidate.hasSuffix("くる"),
            !candidate.hasSuffix("来る"),
            containsKanjiOrKatakana(candidate) else {
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

        return filterArchaicAdjectiveSurfaceCandidates(
            for: reading,
            candidates: mergedCandidates
        )
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

        guard let suppressedCandidates = suppressedByReading[normalizedReading],
            !suppressedCandidates.isEmpty else {
            return candidates
        }

        return candidates.filter { !suppressedCandidates.contains($0) }
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
