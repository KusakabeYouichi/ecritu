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

    // applyScriptVariantCandidateModes へ活用派生集合を渡すための一時置き場(candidates() 内のみ使用)
    var inflectionDerivedCandidatesForScriptVariant: Set<String> = []
    var historicalKanaSurfaceAllowed: Bool = false
    // 仮名踊り字(ゝ/ゞ/ヽ/ヾ)。旧仮名遣い(ゐゑヰヱ)とは独立に制御する。
    var iterationMarkSurfaceAllowed: Bool = false
    // カタカナ強調表記(ウマイ/ばかリ 等=表層のひらがな化が読みと一致)と
    // 交ぜ書き(まん延/作ひん 等=常用漢字外を嫌ったかな開き)の扱い。既定は抑制。
    var katakanaEmphasisCandidateMode: ScriptVariantCandidateMode = .suppress
    var mazegakiCandidateMode: ScriptVariantCandidateMode = .suppress

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

    func setIterationMarkSurfaceAllowed(_ allowed: Bool) {
        stateQueue.sync {
            guard iterationMarkSurfaceAllowed != allowed else {
                return
            }

            iterationMarkSurfaceAllowed = allowed
            invalidateCandidateCache()
        }
    }

    func setKatakanaEmphasisCandidateMode(_ mode: ScriptVariantCandidateMode) {
        stateQueue.sync {
            guard katakanaEmphasisCandidateMode != mode else {
                return
            }
            katakanaEmphasisCandidateMode = mode
            invalidateCandidateCache()
        }
    }

    func setMazegakiCandidateMode(_ mode: ScriptVariantCandidateMode) {
        stateQueue.sync {
            guard mazegakiCandidateMode != mode else {
                return
            }
            mazegakiCandidateMode = mode
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
        // 算用数字+助数詞(2本/第1回)。漢数字複合(360)より上・辞書(1200)より下=にほんは日本が
        // 勝つが 2本 も候補に出し、漢数字 二本 より前に置く(ユーザ方針: 算用優先)。
        static let numericArabicCompound = 400
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
        inflectionDerivedCandidatesForScriptVariant = Set(inflectionDerivedCandidates)
        applySuppressionsAndDecorativeFilter(context, to: &scores)
        inflectionDerivedCandidatesForScriptVariant = []

        var finalCandidates = finalizeSortedCandidates(context, scores: scores)
        // 助数詞+付属語(かい+しか 等)の合成をレア語合成(芥子か 等)より前へ(先頭候補の直後)。
        finalCandidates = Self.counterKanaTailPromotedCandidates(finalCandidates, reading: normalizedReading)
        // 合成中の読みが数字接頭(4まんえん 等。normalizedReading は数字を落とすため元の reading で
        // 判定)なら、確定済み数字直後と同じ助数詞ブーストを適用して 万円/本 等を先頭へ。
        if let digit = reading.first, ("0"..."9").contains(String(digit)) || ("０"..."９").contains(String(digit)) {
            finalCandidates = Self.digitContextCounterBoostedCandidates(
                finalCandidates,
                reading: normalizedReading,
                precedingCharacter: digit
            )
        }

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
            arabicNumericCompoundCandidates(for: reading),
            baseScore: CandidateScore.numericArabicCompound,
            to: &scores
        )

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
        applyRegionalProduceBoost(for: context.reading, to: &scores)
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
        ) || isComposedSuppressed(
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

        applyScriptVariantCandidateModes(
            context,
            inflectionDerivedCandidates: inflectionDerivedCandidatesForScriptVariant,
            to: &scores
        )
    }

    // カタカナ強調表記(ウマイ/ばかリ 等)と交ぜ書き(まん延/作ひん 等)へ、コンテナ設定の
    // [抑制/候補リスト後方/同列] を適用する。ユーザ明示登録(追加語彙/手動)は常に尊重して対象外。
    // 外来語(パン/アンケート 等)は LM 基準で保護する — カタカナ側が unigram 優位なら強調ではない。
    private func applyScriptVariantCandidateModes(
        _ context: CandidateGenerationContext,
        inflectionDerivedCandidates: Set<String>,
        to scores: inout [String: Int]
    ) {
        let katakanaMode = katakanaEmphasisCandidateMode
        let mazegakiMode = mazegakiCandidateMode
        guard katakanaMode != .normal || mazegakiMode != .normal else {
            return
        }

        let reading = context.reading
        // ユーザ明示(追加語彙)・学習(明示タップ)・完全一致専用seed(抑制→末尾再供給の二段構え)
        // は対象外
        var exemptCandidates = context.userCandidateSet.union(context.learnedCandidates)
        exemptCandidates.formUnion(KanaKanjiSeedDictionary.exactReadingOnlySeed[reading] ?? [])
        var katakanaTargets: [String] = []
        var mazegakiTargets: [String] = []
        var kanjiAlternatives: [String] = []
        var allKanjiSameReading: [String] = []

        for candidate in scores.keys where !exemptCandidates.contains(candidate) {
            if katakanaMode != .normal,
                candidate != reading,
                let hira = Self.hiraganizedKanaOnlySurface(candidate),
                hira == reading,
                // seed 掲載(イカ 等の人手選別)と、seed 掲載カタカナ連のみの混在(イカの 等)は
                // 正当なカタカナ語として対象外
                !(KanaKanjiSeedDictionary.seed[reading]?.contains(candidate) ?? false),
                !Self.katakanaRunsAreSeedProtected(candidate) {
                katakanaTargets.append(candidate)
            }
            if Self.isAllKanjiSurface(candidate) {
                allKanjiSameReading.append(candidate)
            }
        }
        for candidate in context.systemCandidates where Self.isAllKanjiSurface(candidate) {
            if !allKanjiSameReading.contains(candidate) {
                allKanjiSameReading.append(candidate)
            }
        }
        kanjiAlternatives = allKanjiSameReading

        if mazegakiMode != .normal {
            // 全漢字側は LM unigram 実在(蔓延/作品 等の常用語)を要求 — 名前収穫(中野/夏羽 等)を
            // 「開かれた元」と誤認して正当な合成を巻き込まない
            let fullKanjiUni = store.wordLMUnigramCosts(for: allKanjiSameReading)
            // 活用派生(勝って/切って 等のて形)は 勝手/切手 と構造衝突するため対象外
            for candidate in scores.keys
            where !exemptCandidates.contains(candidate)
                && !inflectionDerivedCandidates.contains(candidate) {
                guard let kanjiPart = Self.mazegakiKanjiPart(candidate, reading: reading) else { continue }
                if allKanjiSameReading.contains(where: { full in
                    full != candidate
                        && fullKanjiUni[full] != nil
                        && kanjiPart.count < full.count
                        && Self.isSubsequence(kanjiPart, of: full)
                }) {
                    mazegakiTargets.append(candidate)
                }
            }
        }

        guard !katakanaTargets.isEmpty || !mazegakiTargets.isEmpty else {
            return
        }

        // 外来語保護: カタカナ表層に unigram があり、かな識別・漢字側のどれよりも安ければ
        // 正当な外来語表記(パン/アンケート)とみなして対象から外す。
        if !katakanaTargets.isEmpty {
            let probes = katakanaTargets + kanjiAlternatives + [reading]
            let uni = store.wordLMUnigramCosts(for: probes)
            let altBest = (kanjiAlternatives.compactMap { uni[$0] } + [uni[reading]].compactMap { $0 }).min()
            katakanaTargets = katakanaTargets.filter { candidate in
                guard let kataUni = uni[candidate] else {
                    // LM未収録のカタカナ化は、かな/漢字の代替が存在する限り強調とみなす
                    return altBest != nil || !kanjiAlternatives.isEmpty
                }
                if let altBest { return altBest < kataUni }
                return false
            }
        }

        for candidate in katakanaTargets + mazegakiTargets {
            let mode = katakanaTargets.contains(candidate) ? katakanaMode : mazegakiMode
            switch mode {
            case .suppress:
                scores.removeValue(forKey: candidate)
            case .demote:
                // 完全一致専用(300)よりさらに下=リスト末尾へ
                scores[candidate] = min(scores[candidate] ?? 0, CandidateScore.exactReadingOnly - 50)
            case .normal:
                break
            }
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

    // かな正書の副詞の末尾(いまだ/まだ)。これで終わる読みは提示層でかな識別を先頭維持する
    // 根拠にする(これはいまだ/これはまだ)。連濁・同音の漢字(未だ)が繰り上がるのを防ぐ。
    static let kanaOrthographyAdverbTails: [String] = ["いまだ", "まだ"]
    // 上記副詞の直前に来て「副詞」と判定できる助詞(しまだ→島田 の誤爆回避のためのゲート)。
    static let kanaOrthographyAdverbBoundaryParticles: Set<Character> = ["は", "も", "が", "で", "に"]

    // かな識別を変換候補の先頭に残すべき読みか。かなが正書とみなせる根拠(辞書に実在する
    // かな語=ちゃんと/そして、追加語彙のかな語=だが/なのに、学習済み)がある場合のみ true。
    // 活用+postfix の合成で組み上がったかな全文一致(かってみようかな 等)は変換意図の
    // 入力なので対象外(末尾のかなチップに一本化する)。
    // て/で 形+授受補助動詞(くれ/あげ)+任意のひらがな連鎖で終わる読みか。
    // してくれて/してくれないかな/してくれてるのね 等を列挙なしで一般判定する。
    static func hasTeBenefactiveKanaTail(_ reading: String) -> Bool {
        for marker in ["てくれ", "でくれ", "てあげ", "であげ"] {
            guard let range = reading.range(of: marker, options: .backwards),
                range.lowerBound != reading.startIndex else {
                continue
            }
            let tail = reading[range.upperBound...]
            if tail.unicodeScalars.allSatisfy({ (0x3041...0x3096).contains($0.value) }) {
                return true
            }
        }
        return false
    }

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
        // 逆接の接続助詞・接続詞(だけど/けど/けれど/けれども)で終わる読みは、かなが正書
        // (だけど 単独/行くけど 等)。ダけど/打けど 等の漢字混じり誤変換が繰り上がるのを防ぐ。
        // 単独(==suffix)も対象にするため hasSuffix のみで判定する。
        for suffix in ["だけど", "だけれど", "けれども", "けれど", "けど"]
        where normalized.hasSuffix(suffix) {
            return true
        }
        // 複合助詞(では/には/とは/でも 等)そのものはかなが正書。デは/出は/手は 等の漢字混じり
        // 誤変換が提示層で繰り上がるのを防ぐ(単独入力=複合助詞の話題断片)。
        if Self.multiClauseCompoundParticles.contains(normalized) {
            return true
        }
        // 長音化した終助詞クラスタそのもの(かなー/よねー/なー 等、会話の詠嘆・疑問)はかなが正書。
        // か(過/花/夏…)+なー 等の1字漢字合成が提示層で繰り上がるのを防ぐ。
        if normalized.hasSuffix("ー"), Self.multiClauseFinalParticleReadings.contains(normalized) {
            return true
        }
        // 丁寧の ます(常にかな。マス/升/増す 等の漢字・カタカナ化は不自然)+終助詞/助動詞
        // (ね/よ/か/ました…)で終わる読み。ますね→マスね 等の繰り上がりを防ぐ。
        for suffix in ["ますね", "ますよ", "ますか", "ますが", "ますし", "ますよね", "ますねー", "ますよー",
                       "ました", "まして", "ませんか", "ません", "ましょう", "ましょ", "ます"]
        where normalized.hasSuffix(suffix) {
            return true
        }
        // 終助詞(よ/ね/な/わ/ぞ/さ)を1つ剥がした語幹が「辞書のかな語そのもの」(いい/だめ/やだ/むり 等)
        // なら根拠あり(いいよ→いい: 良いよ/イイよ/唯々よ の繰り上がりを防ぐ)。※systemCandidates 直接判定に
        // 限定し、活用連鎖(かってみよう 等=辞書かな語でない)では誤発火しない。
        // そう は文末の推量・指示(ほとんどそう/たぶんそう)。の は連体の言いさし
        // (それぞれの/ひとりひとりの)。いずれもかな語幹+終端はかなが正書
        // なあ/ねえ 系(詠嘆の長形。すごいなあ 等)も同型 — な の1字剥がしでは語幹が
        // すごいな になり不成立のため、長形を明示する(2403)。
        for particle in ["よ", "ね", "な", "わ", "ぞ", "さ", "そう", "の", "なあ", "なぁ", "ねえ", "ねぇ"]
        where normalized.count > particle.count && normalized.hasSuffix(particle) {
            let stem = String(normalized.dropLast(particle.count))
            if stem.count >= 2, systemCandidates(for: stem, mode: .lesDeux).contains(stem) {
                return true
            }
            // curated かな識別(misc の だっけ 等=かな正書の明示登録)も語幹の根拠と認める。
            // ダッケ suppr 後の だっけ は辞書エントリが空で systemCandidates では拾えず、
            // keepKana=false → 提示層がかな最良(だっけな)を退避して候補なしになる。
            if stem.count >= 2,
                (store.initialUserDictionary()[stem] ?? []).contains(stem)
                    || (store.userDictionary()[stem] ?? []).contains(stem) {
                return true
            }
            // い形容詞のかな過去(よかった/すごかった 等)は活用形なので辞書エントリでは拾えない。
            // Xかった→基底 X+い に脱活用して基底が辞書のかな語なら根拠あり(よかったな→よかった→
            // よい)。keepKana は「既にかな先頭の候補を維持するだけ」で昇格はしないため、漢字正書の
            // 形容詞(高かったな 等=エンジンが漢字先頭)に発火しても実害はない。
            if stem.count >= 4, stem.hasSuffix("かった") {
                let adjectiveBase = String(stem.dropLast(3)) + "い"
                if systemCandidates(for: adjectiveBase, mode: .lesDeux).contains(adjectiveBase) {
                    return true
                }
            }
        }
        // 存在・進行の かな動詞(ある/いる)を剥がして再帰(やつにはある→やつには→(は/に 剥がし)→やつ)。
        // かな正書の語(やつ/ひび 等)+ 助詞 + ある/いる の全かな句が提示層で漢字化(奴にはある)に
        // 繰り上がるのを防ぐ。剥がした語幹が最終的にかな正書の識別に落ちる時だけ true。
        for verb in ["ある", "いる", "あった", "いた"]
        where normalized.count > verb.count && normalized.hasSuffix(verb) {
            let stem = String(normalized.dropLast(verb.count))
            if stem.count >= 2, computeShouldKeepKanaIdentityLeading(normalized: stem) {
                return true
            }
        }
        // 形式名詞(こと/とき/もの/ため/だけ)で終わる名詞化節は かな が正書(することがある→
        // ある/が を剥がした することが→すること、見るとき 等)。前に述語相当(2文字以上)がある
        // 全かな句は提示層で先頭かなを維持する(することがある→する事がある への繰り上がりを防ぐ)。
        // 疑問・引用の終端(かと/かな/か 等)は剥がしてから照合する(ってことかと→ってこと。
        // エンジンはかな最良なのに keepKana 不成立で って事かと が繰り上がるのを防ぐ)。
        var formalNounProbe = normalized
        for interrogativeTail in ["かと", "かな", "か"]
        where formalNounProbe.count > interrogativeTail.count
            && formalNounProbe.hasSuffix(interrogativeTail) {
            formalNounProbe = String(formalNounProbe.dropLast(interrogativeTail.count))
            break
        }
        // 格助詞 で は1字だけ剥がしてから照合(ってやつで→ってやつ)。で の一般再帰剥がしは
        // 名詞+で(ずかんで)や ので の厳格ゲート(たべるので)を迂回してしまうため行わない(2404)。
        if formalNounProbe.count > 1, formalNounProbe.hasSuffix("で") {
            formalNounProbe = String(formalNounProbe.dropLast())
        }
        for noun in KanaKanjiConverter.multiClauseFormalNounKanaReadings
        where formalNounProbe.count > noun.count && formalNounProbe.hasSuffix(noun) {
            let stem = String(formalNounProbe.dropLast(noun.count))
            if stem.count >= 2 {
                return true
            }
        }
        // て形+授受補助動詞で終わる読み(してくれて/教えてあげて/してくれてるのね 等)は
        // かなが正書 — エンジンの授受クランプ(isTeBenefactiveAuxiliaryReading)と同じ発想の
        // 一般判定。マーカ(て/で+くれ/あげ)以降が全ひらがなで文末まで続けば、活用形や
        // 終助詞クラスタが何であっても根拠あり(列挙リストは くれてる 等の漏れが続いたため廃止)。
        // かな最良が提示層で退避され して暮れてるのね 等が繰り上がるのを防ぐ(維持のみで昇格しない)。
        if Self.hasTeBenefactiveKanaTail(normalized) {
            return true
        }
        // 疑問・説明の のか に長音 ー が付く読み(なのかー/そうなのかー 等)は口語終端で
        // かなが正書。名詞漢字+のかー(名/菜+のかー 等)の無意味分割より かな全文を先頭へ。
        // 長音なしの なのか(=七日)は辞書語を守るため対象外(ー 付きに限定)。
        if normalized.count > 3, normalized.hasSuffix("のかー") {
            return true
        }
        if (store.initialUserDictionary()[normalized] ?? []).contains(normalized) {
            return true
        }
        // curated かな識別(やって/やってみる 等の misc 登録)で終わり、前半が辞書のかな語
        // (とにかく 等)なら根拠あり(とにかくやってみる)。前半+curated末尾 の全かな句は
        // かなが正書とみなす。
        if normalized.count >= 5 {
            let initialDictionary = store.initialUserDictionary()
            let manualDictionary = store.userDictionary()
            let maxSuffix = min(8, normalized.count - 2)
            for suffixLength in 3...maxSuffix {
                let suffix = String(normalized.suffix(suffixLength))
                guard (initialDictionary[suffix] ?? []).contains(suffix)
                    || (manualDictionary[suffix] ?? []).contains(suffix) else { continue }
                let prefix = String(normalized.dropLast(suffixLength))
                if prefix.count >= 2,
                    systemCandidates(for: prefix, mode: .lesDeux).contains(prefix)
                        || store.wordCosts(for: prefix)[prefix] != nil {
                    return true
                }
            }
        }
        if (store.userDictionary()[normalized] ?? []).contains(normalized) {
            return true
        }
        if systemCandidates(for: normalized, mode: .lesDeux).contains(normalized) {
            return true
        }
        // 形容詞化の ない 系を剥がした語幹が「辞書のかな語」かつ「LM でかな優位」なら
        // かなが正書(もったいない: もったい 7272<勿体 7715。読み全体は辞書/LM に無い)。
        // 知らない 等は語幹の漢字(白/知ら…)が LM 優位なので発火しない(2406)。
        for tail in ["なかった", "なくて", "ない"]
        where normalized.count > tail.count + 1 && normalized.hasSuffix(tail) {
            let stem = String(normalized.dropLast(tail.count))
            let stemCandidates = systemCandidates(for: stem, mode: .lesDeux)
            guard stemCandidates.contains(stem) else { continue }
            let kanjiOthers = stemCandidates.filter { $0 != stem && Self.containsKanjiCandidate($0) }
            if !kanjiOthers.isEmpty, isLMKanaPreferred(reading: stem, among: kanjiOthers) {
                return true
            }
        }
        // 辞書に読みエントリが無い派生専用のかな語(もったいない 等=勿体+ない の合成のみ)は、
        // LM unigram にかな表層が実在すれば かなが正書の証拠とする。Wikipedia は漢字寄りの
        // コーパスなので、かな表層が収録されている時点で強いシグナル。辞書エントリがある読み
        // (ばあい=場合 等)は対象外(2406)。
        if normalized.count >= 4,
            store.wordCosts(for: normalized).isEmpty,
            store.wordLMUnigramCosts(for: [normalized])[normalized] != nil {
            return true
        }
        // 理由の ので 付きの読みは、剥がした語幹が seed でかな先頭に固定された正書のかな語
        // (ある/いる 等)のときだけ根拠ありとする(いるので/あるので: かなを #2 位置維持で残す)。
        // たべる/みる 等は dict rank2 に かな harvest があり systemCandidates.contains では拾えて
        // しまうため、より厳しい「seed かな先頭 or 学習済みかな識別」で判定する(食べるので/見るので
        // にかなが混ざるのを防ぐ)。
        if normalized.count > 2, normalized.hasSuffix("ので") {
            let stem = String(normalized.dropLast(2))
            if stem.count >= 2,
                (KanaKanjiSeedDictionary.seed[stem]?.first == stem || hasLearnedKanaIdentity(for: stem)) {
                return true
            }
        }
        // 理由のコピュラ だから を剥がした語幹が辞書のかな語(ばかり=副助詞 等)なら根拠あり
        // (ばかりだから→ばかり)。ばかり は candidate_sources のモードタグで systemCandidates に
        // かな識別が出ないため、word_costs のかな識別(ばかり=5598 実在)でも根拠と認める。
        // 名詞+だから(学生だから=漢字正書)に発火しても keepKana は維持のみで実害なし。
        if normalized.count > 3, normalized.hasSuffix("だから") {
            let stem = String(normalized.dropLast(3))
            if stem.count >= 2,
                systemCandidates(for: stem, mode: .lesDeux).contains(stem)
                    || store.wordCosts(for: stem)[stem] != nil {
                return true
            }
        }
        // 言いさし終止の から を剥がして再帰(じゃないから→じゃない: コピュラ否定末尾で true)。
        // ので は既存の厳格ゲート(seedかな先頭/学習のみ。たべるので を素通りさせない)を迂回
        // しないよう汎用剥がしにせず、じゃない系の複合末尾だけ下で明示する。
        if normalized.count > 3, normalized.hasSuffix("から") {
            let stem = String(normalized.dropLast(2))
            if stem.count >= 2, computeShouldKeepKanaIdentityLeading(normalized: stem) {
                return true
            }
        }
        // 疑問・推量の終端(かなあ/かも/かな/かと/か)を剥がした語幹が「辞書のかな語そのもの」
        // (いくつか→いくつ)か「かな語+ある/いる」(いくつあるかも→いくつある→いくつ)か
        // 「て/で形+授受補助動詞」(してくれないかな→してくれない)なら根拠あり。エンジンが
        // かな最良の疑問句が提示層で退避され 幾つあるかも/して暮れないかな 等が繰り上がるのを
        // 防ぐ。全面再帰にはしない — かってみようかな(活用連鎖の防護ケース)へ かってみよう の
        // 別根拠が伝播して退行した(2375)ため、限定列挙の狭い根拠にとどめる。
        for tail in ["かなあ", "かも", "かな", "かと", "か"]
        where normalized.count > tail.count && normalized.hasSuffix(tail) {
            let stem = String(normalized.dropLast(tail.count))
            guard stem.count >= 2 else { continue }
            if systemCandidates(for: stem, mode: .lesDeux).contains(stem) {
                return true
            }
            for verb in ["ある", "いる"]
            where stem.count > verb.count && stem.hasSuffix(verb) {
                let subStem = String(stem.dropLast(verb.count))
                if subStem.count >= 2, systemCandidates(for: subStem, mode: .lesDeux).contains(subStem) {
                    return true
                }
            }
            // コピュラ推量末尾(どこだろうか→どこだろう、そうでしょうかも 等)も根拠あり
            // (先頭のコピュラ末尾規則と同じ語彙。か 等が付くと届かないのをここで補う)
            for cop in ["だろう", "でしょう", "でしょ", "じゃない", "じゃん"]
            where stem.count > cop.count && stem.hasSuffix(cop) {
                return true
            }
        }
        // コピュラ否定(じゃない/じゃなくて/じゃなかった)で終わる全かな句はかなが正書
        // (じゃ+無かった 等の分割漢字化より かな全文)。keepKana は維持のみで昇格しないため、
        // 名詞部が漢字正書の句(嘘じゃない=エンジンが漢字先頭)に発火しても実害はない。
        for tail in ["じゃなかった", "じゃなかったか", "じゃなかったの", "じゃなくて", "じゃない", "じゃないので", "じゃないんで"] where normalized.hasSuffix(tail) {
            return true
        }
        // コピュラ だ+終助詞(だよ/だね…)と でしょ(でしょう縮約)もかなが正書。終助詞剥がし規則は
        // 語幹2文字以上を要求するため単独 だ では発火しない — 明示末尾で補う。
        for tail in ["だよ", "だね", "だな", "だわ", "だぞ", "だぜ", "だっけ", "でしょ"] where normalized.hasSuffix(tail) {
            return true
        }
        // なる系縮約(〜なってる/〜なっちゃう)で終わる読みはかなが正書(成ってる/為ってる/
        // 綯ってる の漢字化は不自然)。misc curated なってる/なっちゃう と対の提示層維持。
        for tail in ["なってる", "なっちゃう"] where normalized.count > tail.count && normalized.hasSuffix(tail) {
            return true
        }
        // 〜でいい(これでいい/それでいい/ままでいい)の いい はかなが正書(良い は suppr 済みの方針)。
        if normalized.count > 3, normalized.hasSuffix("でいい") {
            return true
        }
        // コピュラ だ(+活用尾 だった/だったら/だし/だって)を剥がした語幹のかな識別が辞書先頭
        // (どう/そう 等のかな正書語)なら根拠あり(どうだ→どう=rank0かな、そうだった→そう)。
        // 純カタカナ識別(ソウ 等)は漢字正書の根拠ではないので除いて先頭判定する。
        // 学生だ/学生だった 等は語幹の辞書先頭が漢字なので発火しない。
        for tail in KanaKanjiConverter.copulaDaTails
        where normalized.count > tail.count && normalized.hasSuffix(tail) {
            let stem = String(normalized.dropLast(tail.count))
            if stem.count >= 2,
                systemCandidates(for: stem, mode: .lesDeux)
                    .first(where: { !KanaKanjiConverter.isPureKatakanaCandidate($0) }) == stem {
                return true
            }
        }
        // 説明の んで(=ので 縮約)付きで、語幹が存在動詞のかな過去(あった/いた)の読みはかなが正書
        // (あったんで/いたんで)。エンジン側(2328)は文節先頭の あった をかな最良にするが、提示層の
        // かな降格が false のままだと先頭かなが末尾チップへ退避され実機だけ 会ったんで 先頭になる。
        if normalized.hasSuffix("んで"),
            KanaKanjiConverter.multiClauseClauseInitialKanaExistentialPasts.contains(String(normalized.dropLast(2))) {
            return true
        }
        // 名詞化節(のは/のが 等)・説明の のね/のよ 付きの読みは、剥がした語幹が辞書の
        // かな語(ひらがな/ある 等)なら根拠ありとする(ひらがなのは/あるのね: 合成でかな
        // 全文一致になるが、かなが正書の語幹+かなが唯一の正書の節、なので変換としてのかなを
        // 候補に残す。提示層は 2122 の位置維持で上位2件ならその位置を保つ)。
        // のだ/んだ/のです/んです(説明のコピュラ)も同型: うまいのだ→うまい(辞書のかな語)。
        for suffix in ["のは", "のが", "のも", "のを", "のに", "のね", "のよ", "のです", "んです", "のだ", "んだ"] where normalized.hasSuffix(suffix) {
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
            // 五段る動詞の過去(なった 等)は活用形なので辞書エントリでは拾えない。った→基底 る に
            // 脱活用して基底が辞書のかな語なら根拠あり(なったのは→なった→なる=rank0かな)。
            // 買った(かう基底)等で かる に誤マッチしても keepKana は維持のみで実害なし。
            if stem.count >= 3, stem.hasSuffix("った") {
                let ruBase = String(stem.dropLast(2)) + "る"
                if systemCandidates(for: ruBase, mode: .lesDeux).first == ruBase {
                    return true
                }
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
        // 指示代名詞+で(これで/それで/ここで 等)はかなが正書。で の一般剥がしは
        // 名詞+で(ずかんで)を巻き込むため、かな正書の指示代名詞語幹に限定する(2406)。
        if normalized.count > 1, normalized.hasSuffix("で"),
            KanaKanjiConverter.kanaOrthographyDemonstrativePronounStems.contains(String(normalized.dropLast())) {
            return true
        }
        // 指示連体詞(この/その/あの/どの)で終わる読みは、剥がした語幹がかな正書の識別なら
        // 根拠あり(みんなこの→みんな: エンジンはかな最良なのに keepKana 不成立で 皆この が
        // 繰り上がるのを防ぐ。2404)。
        for demonstrative in ["この", "その", "あの", "どの"]
        where normalized.count > demonstrative.count && normalized.hasSuffix(demonstrative) {
            let stem = String(normalized.dropLast(demonstrative.count))
            if stem.count >= 2, computeShouldKeepKanaIdentityLeading(normalized: stem) {
                return true
            }
        }
        // 文末のかな終助詞クラスタのうち長音化(ー付き=話し言葉)のもの(かなー/よねー/なー 等)を
        // 剥がした語幹がかな正書の識別なら根拠ありとする(ぐらいかなー→ぐらい: 副助詞 ぐらい は
        // かなが正書。連濁でしか ぐらい と読まない 暗い が繰り上がるのを防ぐ)。ー無しの素の かな
        // (かってみようかな 等の活用連鎖)は対象外=従来どおり末尾チップへ退避する。
        for suffix in Self.multiClauseFinalParticleReadings
        where suffix.hasSuffix("ー") && normalized.count > suffix.count && normalized.hasSuffix(suffix) {
            let stem = String(normalized.dropLast(suffix.count))
            if stem.count >= 2, computeShouldKeepKanaIdentityLeading(normalized: stem) {
                return true
            }
        }
        // かな正書の副詞(いまだ/まだ)で終わる読みは、末尾クラスタがかな正書(これはいまだ/
        // これはまだ: 未だ は漢字だが会話ではかな)。ただし しまだ→島田 の誤爆を避けるため、
        // 読み全体が副詞そのものか、直前が助詞(は/も/が/で/に)の時だけ根拠とする。
        for tail in Self.kanaOrthographyAdverbTails
        where normalized.hasSuffix(tail) {
            if normalized == tail {
                return true
            }
            let before = normalized.dropLast(tail.count).last
            if let before, Self.kanaOrthographyAdverbBoundaryParticles.contains(before) {
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
