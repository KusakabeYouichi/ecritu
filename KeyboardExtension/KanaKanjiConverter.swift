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

    // 連文節の span 別活用派生キャッシュ(キー "mode|読み")。前置き入力ではスパンの大半が
    // 毎キーストロークで再出現し、活用派生はルール全走査×基底候補取得で最も高くつくため。
    // 学習・抑制・設定変更時は invalidateCandidateCache で一緒に消える。
    var multiClauseInflectionCache: [String: [String]] = [:]
    let multiClauseInflectionCacheLimit = 1024

    // shouldKeepKanaIdentityLeading のメモ(結果適用のたび main で全ルール走査+sqlite点
    // クエリが走っていた)。学習・抑制・設定変更で invalidateCandidateCache と一緒に消える。
    var kanaIdentityLeadingCache: [String: Bool] = [:]
    let kanaIdentityLeadingCacheLimit = 256

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

    // メモリ対策用の全キャッシュ破棄。sqlite インデックス(連文節LM)は保持する
    // (close しても解放量はごく僅かなのに連文節が停止して劣化変換になるため)。
    func clearAllCaches() {
        store.clearSystemDictionaryJSONCaches()
        store.clearSharedDataCaches()

        stateQueue.sync {
            invalidateCandidateCache()
        }
    }

    // メモリ警告が繰り返されるときの最終手段。連文節は単文節フォールバックに劣化するが、
    // jetsam で拡張ごと落ちるよりよい(初回警告では呼ばない = LM保持の方針を維持)。
    // 再オープンはセッション中スティッキーに禁止される(以前は次の変換で即再オープンされ
    // 空回りだった)。
    func unloadSystemDictionarySQLiteForMemoryPressure() {
        store.unloadSQLiteIndexForMemoryPressure()

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
        // 収穫底値(word_cost>=10000)の辞書丸ごとエントリ。Sudachi のレア名前・表記ゆれ
        // 収穫がほぼ全てで、高頻度語の合成(夏+は/水+は 等)より下に置く。ただし bfs 合成
        // (1040)の直下に留め、深いジャンク合成(侑瞳か 等の名前+かな断片)よりは上に
        // 残す(ゆずか の 柚佳 等、名前入力の受け皿として選択可能な位置を保つ)。
        static let harvestTierDictionary = 1030
        static let harvestTierWordCostFloor = 10000
        // 完全一致専用候補(踊り字 等)。辞書語より下位に置き、末尾寄りに出す。
        static let exactReadingOnly = 300
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
        // 収穫底値(wc>=10000)の丸ごとエントリはレア名前・表記ゆれ収穫がほとんどで、
        // 放置すると 夏羽/捺葉…(なつは)のような名前群が 夏+は の合成より先に並ぶ
        // (なつは/みずは/からだが 型)。合成チャネルより下の帯へ一般降格する。
        // 読みに正規の語(wc<10000)しか無い通常ケースや、全候補が収穫底値の読み
        // (相対順維持)は無影響。
        let wordCosts = store.wordCosts(for: context.reading)
        // seed 掲載語は人手の選別済みなので降格しない(柚香 等、wc が収穫底値でも
        // 正規の代表候補として seed に載せた語を守る)。
        let seedExempt = Set(KanaKanjiSeedDictionary.seed[context.reading] ?? [])
        var normalSystemCandidates: [String] = []
        var harvestTierCandidates: [String] = []
        for candidate in context.systemCandidates {
            if let cost = wordCosts[candidate],
                cost >= CandidateScore.harvestTierWordCostFloor,
                !seedExempt.contains(candidate) {
                harvestTierCandidates.append(candidate)
            } else {
                normalSystemCandidates.append(candidate)
            }
        }
        addCandidates(normalSystemCandidates, baseScore: CandidateScore.systemDictionary, to: &scores)
        addCandidates(harvestTierCandidates, baseScore: CandidateScore.harvestTierDictionary, to: &scores)
        addCandidates(context.userCandidates, baseScore: CandidateScore.userDictionary, to: &scores)
        addCandidates(context.learnedCandidates, baseScore: CandidateScore.learnedDictionary, to: &scores)
        // 完全一致専用候補(踊り字 等)。入力全体がこの読みと一致した単文節でのみ供給する。
        // systemCandidates には入れていないので、語幹合成・連文節には現れない。
        if let exactOnly = KanaKanjiSeedDictionary.exactReadingOnlySeed[context.reading] {
            addCandidates(exactOnly, baseScore: CandidateScore.exactReadingOnly, to: &scores)
        }
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
        // 抑制語彙はステージ4で除去されるが、スクリプト種の比較グループ(LM首位化・
        // カタカナ保護)には抑制前のジャンク(市市 等)が混ざると誤判定するため先に除く。
        let suppressed = context.suppressedCandidatesByReading[context.reading] ?? []
        applySameReadingScriptPreference(
            for: context.reading,
            systemCandidates: suppressed.isEmpty
                ? context.systemCandidates
                : context.systemCandidates.filter { !suppressed.contains($0) },
            to: &scores
        )
        applySeedSingleKanjiPriorityBoost(for: context.reading, to: &scores)
        applySeedOrderNormalization(
            for: context.reading,
            learningScoresForReading: context.learningScoresForReading,
            to: &scores
        )
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
            // suppr+exactReadingOnlySeed の二段構え(坐す/在す(います)、ここ のレア人名 等):
            // 辞書からは抑制して合成・連文節を守りつつ、完全一致の単文節でのみ末尾
            // (exactReadingOnly 級)に再供給する。除去後に入れ直すことで、辞書スコアと
            // 合流して上位に残ることも防ぐ。
            let resupplied = (KanaKanjiSeedDictionary.exactReadingOnlySeed[context.reading] ?? [])
                .filter { suppressedCandidates.contains($0) }
            if !resupplied.isEmpty {
                addCandidates(resupplied, baseScore: CandidateScore.exactReadingOnly, to: &scores)
            }
        }

        for candidate in Array(scores.keys) where isDeinflectedSuppressed(
            candidate: candidate,
            reading: context.reading,
            suppressedByReading: context.suppressedCandidatesByReading
        ) {
            scores.removeValue(forKey: candidate)
        }

        // 装飾表記(ちゃ〜んと/ち・ゃ・んと 等)と連濁収穫(墓(ばか)等)はどの生成経路
        // (学習含む)から入っても最終段で除去する。ただしユーザ明示登録(追加語彙/手動)は
        // 尊重して残す(あ・うん/ぱ・る・る 等、実在固有名の復活経路)。
        for candidate in Array(scores.keys)
        where !context.userCandidateSet.contains(candidate)
            && (Self.isDecorativeVariantSurface(candidate, reading: context.reading)
                || isRendakuHarvestSurface(candidate, reading: context.reading)) {
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
            // 学習は派生基底(かう→かった 等)経由で任意の読みに波及するため、読みで絞る
            // 部分無効化は stale 候補(学習が効かない)の温床になる。全無効化のままとし、
            // 再計算コストは store 層の LM/wordCosts キャッシュ(learn では無効化されない)
            // が吸収する。
            invalidateCandidateCache()
        }
    }

    // かな識別を変換候補の先頭に残すべき読みか。かなが正書とみなせる根拠(辞書に実在する
    // かな語=ちゃんと/そして、追加語彙のかな語=だが/なのに、学習済み)がある場合のみ true。
    // 活用+postfix の合成で組み上がったかな全文一致(かってみようかな 等)は変換意図の
    // 入力なので対象外(末尾のかなチップに一本化する)。
    func shouldKeepKanaIdentityLeading(for reading: String) -> Bool {
        let normalized = KanaTextNormalizer.normalizedReading(reading)
        guard !normalized.isEmpty else {
            return false
        }
        if let cached = stateQueue.sync(execute: { kanaIdentityLeadingCache[normalized] }) {
            return cached
        }
        let result = computeShouldKeepKanaIdentityLeading(normalized: normalized)
        stateQueue.sync {
            if kanaIdentityLeadingCache.count >= kanaIdentityLeadingCacheLimit {
                kanaIdentityLeadingCache.removeAll(keepingCapacity: true)
            }
            kanaIdentityLeadingCache[normalized] = result
        }
        return result
    }

    private func computeShouldKeepKanaIdentityLeading(normalized: String) -> Bool {
        if hasLearnedKanaIdentity(for: normalized) {
            return true
        }
        // 口語の否定コピュラ・断定(じゃない/じゃん/だろう/でしょ 等)で終わる読みは、かなが
        // 正書の話し言葉(そうじゃないか/きれいじゃない 等)。連文節は全語彙経路として これらを
        // 最良に選べる(allNodesAreDictWords 非抑制)ので、提示層でも先頭かなを保持する根拠とする。
        // 名詞+助詞(ずかんで 等)はこの語尾を持たないので影響しない。
        for suffix in ["じゃない", "じゃないか", "じゃん", "だろう", "でしょう", "でしょ", "じゃないの"]
        where normalized.count > suffix.count && normalized.hasSuffix(suffix) {
            return true
        }
        if (store.initialUserDictionary()[normalized] ?? []).contains(normalized) {
            return true
        }
        if (store.userDictionary()[normalized] ?? []).contains(normalized) {
            return true
        }
        if systemCandidates(for: normalized, mode: .lesDeux).contains(normalized) {
            return true
        }
        // 名詞化節(のは/のが 等)・説明の のね/のよ 付きの読みは、剥がした語幹が辞書の
        // かな語(ひらがな/ある 等)なら根拠ありとする(ひらがなのは/あるのね: 合成でかな
        // 全文一致になるが、かなが正書の語幹+かなが唯一の正書の節、なので変換としてのかなを
        // 候補に残す。提示層は 2122 の位置維持で上位2件ならその位置を保つ)。
        for suffix in ["のは", "のが", "のも", "のを", "のに", "のね", "のよ"] where normalized.hasSuffix(suffix) {
            var stem = String(normalized.dropLast(suffix.count))
            // コピュラ「な」を挟む形(ひらがなな+のは=ひらがな+な+のは)は な も剥がす。
            if stem.count >= 3, stem.hasSuffix("な") {
                let withoutCopula = String(stem.dropLast())
                if systemCandidates(for: withoutCopula, mode: .lesDeux).contains(withoutCopula) {
                    return true
                }
            }
            if stem.count >= 2, systemCandidates(for: stem, mode: .lesDeux).contains(stem) {
                return true
            }
        }
        // 格助詞・係助詞を1つ剥がした語幹がかな正書の識別なら根拠ありとする
        // (あったが→あった→ある: ある過去のかな あった を候補に残す)。買ったが→かった→
        // 買う(漢字先頭)は false のまま。剥がしは1回のみ(語幹に助詞は残らない)。
        for particle in ["が", "は", "も", "を", "に", "へ", "と"]
        where normalized.count > particle.count && normalized.hasSuffix(particle) {
            let stem = String(normalized.dropLast(particle.count))
            if stem.count >= 2, computeShouldKeepKanaIdentityLeading(normalized: stem) {
                return true
            }
        }
        // 活用形の読み(やってそうな 等)は、脱活用した基本形の辞書先頭(抑制適用後)が
        // かな identity(やる 等「かなが正書」の動詞)なら根拠ありとする。
        // かう→買う のように漢字が先頭の基本形は対象外(かってみようかな は末尾のまま)。
        let suppressedByReading = store.suppressedCandidatesByReading()
        let candidateRules = normalized.last
            .flatMap { Self.deinflectionRulesByReadingLastCharacter[$0] } ?? []
        for rule in candidateRules where normalized.hasSuffix(rule.readingSuffix) {
            guard !rule.readingSuffix.isEmpty else { continue }
            let stem = String(normalized.dropLast(rule.readingSuffix.count))
            guard !stem.isEmpty else { continue }
            let baseReading = stem + rule.baseReadingSuffix
            guard baseReading != normalized else { continue }
            let suppressed = suppressedByReading[baseReading] ?? []
            let first = systemCandidates(for: baseReading, mode: .lesDeux)
                .first { !suppressed.contains($0) }
            if first == baseReading {
                return true
            }
        }
        return false
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
        multiClauseInflectionCache.removeAll(keepingCapacity: true)
        kanaIdentityLeadingCache.removeAll(keepingCapacity: true)
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

        // 装飾表記(〜水増し・中黒散らし)と連濁収穫(墓(ばか)等)はここで一括除去する。
        // candidates() の直接列挙のほか、postfix 語幹・活用基底(candidatesForReading)も
        // 本関数を通るため、ち・ゃ・ん+と→ち・ゃ・んと/墓+すぎる のような合成前に断てる。
        return filterHistoricalKanaSurfaceCandidates(
            for: reading,
            candidates: archaicAdjectiveFiltered
        ).filter {
            !Self.isDecorativeVariantSurface($0, reading: reading)
                && !isRendakuHarvestSurface($0, reading: reading)
        }
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
