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

    // 候補スコアの基礎点。生成経路ごとの優先順位をここで一元管理する。
    // 大小関係の意図: 追加語彙 > 学習語彙 > 辞書 > quick postfix > 丁寧接頭辞 > 序数
    //   > 数値単位 > BFS postfix > 名詞漢字接辞 > 活用 > ガル形。
    // 補正(ブースト/ペナルティ)は +RankingHeuristics の定数を参照。
    enum CandidateScore {
        static let userDictionary = 2400        // 追加語彙(手動+初期)
        static let learnedDictionary = 2280     // 学習語彙
        static let systemDictionary = 1200      // 辞書(sqlite/seed)
        static let quickPostfix = 1120          // postfix(語幹キャッシュ利用)
        static let politePrefix = 1100          // お/ご 丁寧接頭辞派生
        static let ordinalMeFallback = 1080     // 序数(〜つ目)
        static let numericUnitFallback = 1070   // 数値+単位
        static let bfsPostfix = 1040            // postfix(BFS完全探索)
        static let nounKanjiAffix = 1000        // 名詞+漢字接辞(課/可/別 等)
        static let inflection = 980             // 活用形派生
        static let adjectiveGaru = 970          // ガル形派生
        // 歴史的経緯: 数詞複合はブースト値(360)を基礎点として流用してきた。
        // 辞書語より大きく下に置く意図はそのまま名前だけ明示する。
        static let numericCounterCompound = 360
    }

    // candidates() のステージ間で共有する読み・辞書・直接候補のスナップショット。
    struct CandidateGenerationContext {
        let reading: String
        let limit: Int
        let mode: KanaKanjiCandidateSourceMode
        let userDictionary: [String: [String]]
        let learnedDictionary: [String: [String]]
        let initialUserDictionary: [String: [String]]
        let learningScoresForReading: [String: Int]
        let suppressedCandidatesByReading: [String: Set<String>]
        let systemCandidates: [String]
        let userCandidates: [String]
        let userCandidateSet: Set<String>
        let learnedCandidates: [String]
        let hasDirectCandidates: Bool
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

        let context = makeGenerationContext(
            reading: normalizedReading,
            limit: limit,
            mode: systemCandidateMode
        )

        var scores: [String: Int] = [:]
        collectDirectCandidates(context, into: &scores)
        let inflectionDerivedCandidates = collectDerivedCandidates(context, into: &scores)
        applyRankingAdjustments(
            context,
            inflectionDerivedCandidates: inflectionDerivedCandidates,
            to: &scores
        )
        applySuppressionsAndDecorativeFilter(context, to: &scores)

        let finalCandidates = finalizeSortedCandidates(context, scores: scores)

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

    // ステージ0: 辞書スナップショットと直接候補(辞書/追加語彙/学習語彙)の収集。
    private func makeGenerationContext(
        reading: String,
        limit: Int,
        mode: KanaKanjiCandidateSourceMode
    ) -> CandidateGenerationContext {
        let manualUserDictionary = store.userDictionary()
        let learnedDictionary = store.learnedDictionary()
        let initialUserDictionary = store.initialUserDictionary()

        let systemCandidates = systemCandidates(for: reading, mode: mode)
        let userCandidates = uniqueCandidates(
            from: (manualUserDictionary[reading] ?? [])
                + (initialUserDictionary[reading] ?? [])
        )
        let userCandidateSet = Set(userCandidates)
        let learnedCandidates = uniqueCandidates(
            from: (learnedDictionary[reading] ?? []).filter {
                !userCandidateSet.contains($0)
            }
        )

        return CandidateGenerationContext(
            reading: reading,
            limit: limit,
            mode: mode,
            userDictionary: manualUserDictionary,
            learnedDictionary: learnedDictionary,
            initialUserDictionary: initialUserDictionary,
            learningScoresForReading: store.learningScores(for: reading),
            suppressedCandidatesByReading: store.suppressedCandidatesByReading(),
            systemCandidates: systemCandidates,
            userCandidates: userCandidates,
            userCandidateSet: userCandidateSet,
            learnedCandidates: learnedCandidates,
            hasDirectCandidates: !systemCandidates.isEmpty
                || !userCandidates.isEmpty
                || !learnedCandidates.isEmpty
        )
    }

    // ステージ1: 直接候補(辞書/追加語彙/学習語彙)を基礎点で登録する。
    private func collectDirectCandidates(
        _ context: CandidateGenerationContext,
        into scores: inout [String: Int]
    ) {
        addCandidates(context.systemCandidates, baseScore: CandidateScore.systemDictionary, to: &scores)
        addCandidates(context.userCandidates, baseScore: CandidateScore.userDictionary, to: &scores)
        addCandidates(context.learnedCandidates, baseScore: CandidateScore.learnedDictionary, to: &scores)
    }

    // ステージ2: 派生候補(活用/ガル形/丁寧接頭辞/序数/数値/名詞接辞/postfix)を登録する。
    // 戻り値は活用派生の集合(ランキング補正で正規活用形を優遇するために使う)。
    private func collectDerivedCandidates(
        _ context: CandidateGenerationContext,
        into scores: inout [String: Int]
    ) -> [String] {
        let reading = context.reading
        let limit = context.limit

        let inflectionDerivedCandidates = inflectionCandidates(
            for: reading,
            userDictionary: context.userDictionary,
            initialUserDictionary: context.initialUserDictionary,
            systemCandidateMode: context.mode,
            limit: limit * 3
        )
        addCandidates(inflectionDerivedCandidates, baseScore: CandidateScore.inflection, to: &scores)

        addCandidates(
            adjectiveGaruCandidates(
                for: reading,
                userDictionary: context.userDictionary,
                initialUserDictionary: context.initialUserDictionary,
                systemCandidateMode: context.mode,
                limit: limit * 3
            ),
            baseScore: CandidateScore.adjectiveGaru,
            to: &scores
        )

        addCandidates(
            politePrefixPassthroughCandidates(
                for: reading,
                userDictionary: context.userDictionary,
                initialUserDictionary: context.initialUserDictionary,
                systemCandidateMode: context.mode,
                limit: limit * 2
            ),
            baseScore: CandidateScore.politePrefix,
            to: &scores
        )

        addCandidates(
            ordinalMeFallbackCandidates(
                for: reading,
                hasDirectCandidates: context.hasDirectCandidates,
                userDictionary: context.userDictionary,
                initialUserDictionary: context.initialUserDictionary,
                systemCandidateMode: context.mode,
                limit: limit * 2
            ),
            baseScore: CandidateScore.ordinalMeFallback,
            to: &scores
        )

        let numericUnitFallback = numericUnitFallbackCandidates(
            for: reading,
            limit: limit * 2
        )
        addCandidates(numericUnitFallback, baseScore: CandidateScore.numericUnitFallback, to: &scores)

        addCandidates(
            numericCounterCompoundCandidates(
                for: reading,
                userDictionary: context.userDictionary,
                initialUserDictionary: context.initialUserDictionary,
                systemCandidateMode: context.mode,
                limit: limit * 2
            ),
            baseScore: CandidateScore.numericCounterCompound,
            to: &scores
        )

        applyNumericUnitFallbackPriorityBoost(
            for: reading,
            fallbackCandidates: numericUnitFallback,
            to: &scores
        )

        addCandidates(
            nounKanjiAffixCandidates(
                for: reading,
                userDictionary: context.userDictionary,
                initialUserDictionary: context.initialUserDictionary,
                systemCandidateMode: context.mode,
                limit: limit * 2
            ),
            baseScore: CandidateScore.nounKanjiAffix,
            to: &scores
        )

        let quickPostfixCandidates = quickPostfixCandidatesUsingCachedStem(
            for: reading,
            limit: limit,
            systemCandidateMode: context.mode
        )

        if !quickPostfixCandidates.isEmpty {
            addCandidates(quickPostfixCandidates, baseScore: CandidateScore.quickPostfix, to: &scores)
        } else {
            addCandidates(
                postfixPassthroughCandidates(
                    for: reading,
                    userDictionary: context.userDictionary,
                    initialUserDictionary: context.initialUserDictionary,
                    systemCandidateMode: context.mode,
                    limit: limit * 3
                ),
                baseScore: CandidateScore.bfsPostfix,
                to: &scores
            )
        }

        return inflectionDerivedCandidates
    }

    // ステージ3: ランキング補正(活用/学習/スクリプト種/単漢字seed)。
    private func applyRankingAdjustments(
        _ context: CandidateGenerationContext,
        inflectionDerivedCandidates: [String],
        to scores: inout [String: Int]
    ) {
        applyInflectionRankingHeuristics(
            for: context.reading,
            userDictionary: context.userDictionary,
            initialUserDictionary: context.initialUserDictionary,
            systemCandidateMode: context.mode,
            systemCandidates: context.systemCandidates,
            inflectionDerivedCandidates: Set(inflectionDerivedCandidates),
            to: &scores
        )
        applyLearning(context.learningScoresForReading, to: &scores)
        applySameReadingScriptPreference(
            for: context.reading,
            systemCandidates: context.systemCandidates,
            to: &scores
        )
        applySeedSingleKanjiPriorityBoost(for: context.reading, to: &scores)
    }

    // ステージ4: 抑制語彙(直接+脱活用)と装飾表記の除去。
    private func applySuppressionsAndDecorativeFilter(
        _ context: CandidateGenerationContext,
        to scores: inout [String: Int]
    ) {
        if let suppressedCandidates = context.suppressedCandidatesByReading[context.reading],
            !suppressedCandidates.isEmpty {
            for candidate in suppressedCandidates {
                scores.removeValue(forKey: candidate)
            }
        }

        for candidate in Array(scores.keys) where isDeinflectedSuppressed(
            candidate: candidate,
            reading: context.reading,
            suppressedByReading: context.suppressedCandidatesByReading
        ) {
            scores.removeValue(forKey: candidate)
        }

        // 装飾表記(ちゃ〜んと/ち・ゃ・んと 等)はどの生成経路(学習含む)から入っても
        // 最終段で除去する。ただしユーザ明示登録(追加語彙/手動)は尊重して残す
        // (あ・うん/ぱ・る・る 等、実在固有名の復活経路)。
        for candidate in Array(scores.keys)
        where !context.userCandidateSet.contains(candidate)
            && Self.isDecorativeVariantSurface(candidate, reading: context.reading) {
            scores.removeValue(forKey: candidate)
        }
    }

    // ステージ5: スコア降順に整列し、旧形容詞/旧仮名フィルタを通して確定する。
    private func finalizeSortedCandidates(
        _ context: CandidateGenerationContext,
        scores: [String: Int]
    ) -> [String] {
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
            for: context.reading,
            candidates: sortedCandidates,
            userDictionary: context.userDictionary,
            learnedDictionary: context.learnedDictionary,
            initialUserDictionary: context.initialUserDictionary
        )

        let filteredSortedCandidates = filterHistoricalKanaSurfaceCandidates(
            for: context.reading,
            candidates: archaicAdjectiveFiltered
        )

        return Array(filteredSortedCandidates.prefix(context.limit))
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
