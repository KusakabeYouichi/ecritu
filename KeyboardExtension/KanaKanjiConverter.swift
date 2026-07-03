import Foundation

final class KanaKanjiConverter {
    struct CandidateCacheKey: Hashable {
        let reading: String
        let limit: Int
        let modeRawValue: String
    }

    let store: KanaKanjiStore

    let stateQueue = DispatchQueue(label: "com.kusakabe.ecritu.kana-kanji.converter-state")

    var candidateCache: [CandidateCacheKey: [String]] = [:]

    var candidateCacheOrder: [CandidateCacheKey] = []

    let candidateCacheLimit = 96

    var historicalKanaSurfaceAllowed: Bool = false

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

        let inflectionDerivedCandidates = inflectionCandidates(
            for: normalizedReading,
            userDictionary: userDictionary,
            initialUserDictionary: initialUserDictionary,
            systemCandidateMode: systemCandidateMode,
            limit: limit * 3
        )
        addCandidates(
            inflectionDerivedCandidates,
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
            inflectionDerivedCandidates: Set(inflectionDerivedCandidates),
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

        // 装飾表記(ちゃ〜んと/ち・ゃ・んと 等)はどの生成経路(学習含む)から入っても
        // 最終段で除去する。ただしユーザ明示登録(追加語彙/手動)は尊重して残す
        // (あ・うん/ぱ・る・る 等、実在固有名の復活経路)。
        for candidate in Array(scores.keys)
        where !userCandidateSet.contains(candidate)
            && Self.isDecorativeVariantSurface(candidate, reading: normalizedReading) {
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

    static func hiraganaToKatakana(_ text: String) -> String {
        text.applyingTransform(.hiraganaToKatakana, reverse: false) ?? text
    }

    func learn(reading: String, candidate: String, allowKanaIdentity: Bool = false) {
        let normalizedReading = KanaTextNormalizer.normalizedReading(reading)
        let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedReading.isEmpty,
                !trimmedCandidate.isEmpty else {
            return
        }

        // かな識別(変換せず読みのかなのまま確定)は原則学習しない。学習すると連文節DPの
        // 追加/学習語彙優遇で最安の単スパン(素通り)になり、以後その読みが二度と変換でき
        // なくなる(joined==reading で連文節候補が消える)。
        // 例外: かな候補チップの明示タップ(allowKanaIdentity)かつ単語相当の短い読み。
        // ちゃんと/そして 等「かなが正書」の語を変換候補側にも出せるようにする。
        // 連文節側は surface==segmentReading スキップで引き続き防護されるため安全。
        if trimmedCandidate == normalizedReading {
            guard allowKanaIdentity,
                normalizedReading.count <= KanaKanjiStore.kanaIdentityLearnableMaxReadingCount else {
                return
            }
        }

        store.addLearnedEntry(
            reading: normalizedReading,
            candidate: trimmedCandidate,
            allowKanaIdentity: allowKanaIdentity
        )
        store.incrementLearning(reading: normalizedReading, candidate: trimmedCandidate)

        stateQueue.sync {
            invalidateCandidateCache()
        }
    }

    // かな候補チップの明示タップでかな識別を学習済みか(candidatesForPresentation が
    // 変換候補側にもかな識別を表示するかの判定に使う)。
    func hasLearnedKanaIdentity(for reading: String) -> Bool {
        let normalizedReading = KanaTextNormalizer.normalizedReading(reading)
        guard !normalizedReading.isEmpty else {
            return false
        }
        return (store.learnedDictionary()[normalizedReading] ?? []).contains(normalizedReading)
    }

    func invalidateCandidateCache() {
        candidateCache.removeAll(keepingCapacity: true)
        candidateCacheOrder.removeAll(keepingCapacity: true)
    }

    func systemCandidates(
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

        // 装飾表記(〜水増し・中黒散らし)はここで一括除去する。candidates() の直接列挙の
        // ほか、postfix 語幹・活用基底(candidatesForReading)も本関数を通るため、
        // ち・ゃ・ん+と→ち・ゃ・んと のような合成前に断てる。
        return filterHistoricalKanaSurfaceCandidates(
            for: reading,
            candidates: archaicAdjectiveFiltered
        ).filter { !Self.isDecorativeVariantSurface($0, reading: reading) }
    }

    func candidatesForReading(
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

    func combinedUserCandidates(
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

    func removingSuffix(_ text: String, suffix: String) -> String? {
        guard !suffix.isEmpty,
                text.hasSuffix(suffix) else {
            return nil
        }

        return String(text.dropLast(suffix.count))
    }

    func uniqueCandidates(from candidates: [String]) -> [String] {
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
