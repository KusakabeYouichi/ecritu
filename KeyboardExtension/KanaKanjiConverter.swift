import Foundation

final class KanaKanjiConverter {
    struct CandidateCacheKey: Hashable {
        let reading: String
        let limit: Int
        let modeRawValue: String
        // 数字接頭の有無。正規化読みは数字を落とすため、これをキーに含めないと
        // 「2もん」が先に計算済みの「もん」のキャッシュを引き当て、数字直後の助数詞
        // ブースト(下の digitContextCounterBoostedCandidates)に到達しない。
        // 呼び出し順に依存して助数詞が出る/出ないが変わる状態だった(2596)。
        let hasDigitPrefix: Bool
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
    // 名詞+た の遮断判定(isInflectedTaFormOfKnownVerb)のメモ。DP の遷移ごとに活用エンジンを呼んでいて
    // 連文節の処理時間の約7%を占めていた(2805 プロファイル)。キー "prevReading\tprevSurface"
    var multiClauseTaFormCheckCache: [String: Bool] = [:]

    // shouldKeepKanaIdentityLeading のメモ(結果適用のたび main で全ルール走査+sqlite点
    // クエリが走っていた)。学習・抑制・設定変更で invalidateCandidateCache と一緒に消える。
    var kanaIdentityLeadingCache: [String: Bool] = [:]
    let kanaIdentityLeadingCacheLimit = 256
    // 直近の単文節 finalize の点数内訳(DEBUG の実機トレース用。stateQueue 保護。2732)
    var lastScoreTraceForDiagnostics: String = ""
    var scoreLedgerForDiagnostics: [String: [Int]] = [:]
    func scoreTraceForDiagnostics(reading: String) -> String? {
        let trace = stateQueue.sync { lastScoreTraceForDiagnostics }
        return trace.hasPrefix(reading + ": ") ? String(trace.dropFirst(reading.count + 2)) : nil
    }

    // applyScriptVariantCandidateModes へ活用派生集合を渡すための一時置き場(candidates() 内のみ使用)
    var inflectionDerivedCandidatesForScriptVariant: Set<String> = []
    var historicalKanaSurfaceAllowed: Bool = false
    // 仮名踊り字(ゝ/ゞ/ヽ/ヾ)。旧仮名遣い(ゐゑヰヱ)とは独立に制御する。
    var iterationMarkSurfaceAllowed: Bool = false
    // カタカナ強調表記(ウマイ/ばかリ 等=表層のひらがな化が読みと一致)と
    // 交ぜ書き(まん延/作ひん 等=常用漢字外を嫌ったかな開き)の扱い。既定は抑制。
    var katakanaEmphasisCandidateMode: ScriptVariantCandidateMode = .suppress
    var mazegakiCandidateMode: ScriptVariantCandidateMode = .suppress
    // め終わり読みの『め/目』選好(コンテナー設定。applyMeSuffixPreferences 参照)。
    // 序数(première…): true=漢字『目』を先に(既定。1973年内閣告示第2号 通則4 の表記)。
    // 形容詞語幹(un peu…): true=『目』形も出す(かな『め』が先)。既定はオフ(告示 付表の語1)。
    var ordinalMeKanjiPreferred: Bool = true
    var adjectiveMeKanjiCandidatesEnabled: Bool = false

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

    func setOrdinalMeKanjiPreferred(_ enabled: Bool) {
        stateQueue.sync {
            guard ordinalMeKanjiPreferred != enabled else {
                return
            }
            ordinalMeKanjiPreferred = enabled
            invalidateCandidateCache()
        }
    }

    func setAdjectiveMeKanjiCandidatesEnabled(_ enabled: Bool) {
        stateQueue.sync {
            guard adjectiveMeKanjiCandidatesEnabled != enabled else {
                return
            }
            adjectiveMeKanjiCandidatesEnabled = enabled
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

    // メモリ内訳census用: converter 側キャッシュの件数+store 側の要約を1行で返す。
    func diagnosticsCacheCountsSummary() -> String {
        let converterPart = stateQueue.sync {
            "cand=\(candidateCache.count)"
                + " kanaLead=\(kanaIdentityLeadingCache.count)"
                + " multiInfl=\(multiClauseInflectionCache.count)"
        }
        return converterPart + " " + store.diagnosticsCacheCountsSummary()
    }

    func preloadSharedDataCachesIfNeeded() {
        _ = store.ajoutVocabulary()
        _ = store.learnedDictionary()
        _ = store.initialAjoutVocabulary()
        _ = store.suppressedCandidatesByReading()
        _ = store.learningScores(for: "あ")
    }


    // 候補スコアの基礎点。生成経路ごとの優先順位をここで一元管理する。
    // 大小関係の意図: 追加語彙 > 学習語彙 > 辞書 > quick postfix > 丁寧接頭辞 > 序数
    //   > 数値単位 > BFS postfix > 名詞漢字接辞 > 活用 > ガル形。
    // 補正(ブースト/ペナルティ)は +RankingHeuristics の定数を参照。
    enum CandidateScore {
        static let ajoutVocabulary = 2400        // 追加語彙(手動+初期)
        static let learnedDictionary = 2280     // 学習語彙
        // 補助語彙(ryukyu/vin/it.plist=SecondVocab)。人手で足した語なので辞書より上に置く。
        // 既定 word_cost が高め(3字11000/4字7500)なので、そのままだと同読みの収穫語より後ろに
        // 沈む(いちまん の 糸満 が 一満 の後)。学習(2280)/追加語彙(2400)より下=ユーザーの
        // 直接の意思表示は依然として優先。**同じ読みに語LM実在の一般語がある場合は昇格しない**
        // (び→美 が 日 を、にほん→🇯🇵 が 日本 を押し下げる事故を防ぐ。実測で先頭が入れ替わる
        // 読みは2331件・うち頻出語衝突525件だった。2497)
        static let supplementalVocabulary = 1500
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
        // 外来語のカタカナ保護(辞書コスト基準)。SudachiDict のカタカナ強調収穫は元の語と
        // 同一コストで入る(ウマイ=旨い5415/シテ=仕手4212/バカリ=秤5401/イヤ=嫌3673)一方、
        // 実在の外来語はその読みの主語彙として明確に安い(デマ2137 ≪ 手間9327)。同読みの
        // 非カタカナ候補の最安より この幅以上安いカタカナは外来語とみなし、強調抑止から外す。
        // LM unigram 基準の保護(同音の漢字が安いと外来語でも落ちる。手間6037 < デマ6955)を
        // 補う二段目の判定(2485)。
        static let loanwordKatakanaWordCostGap = 2500
    }

    // candidates() のステージ間で共有する読み・辞書・直接候補のスナップショット。
    struct CandidateGenerationContext {
        let reading: String
        let limit: Int
        let mode: KanaKanjiCandidateSourceMode
        let ajoutVocabulary: [String: [String]]
        let learnedDictionary: [String: [String]]
        let initialAjoutVocabulary: [String: [String]]
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

        let hasDigitPrefix = reading.first.map {
            ("0"..."9").contains(String($0)) || ("０"..."９").contains(String($0))
        } ?? false
        let cacheKey = CandidateCacheKey(
            reading: normalizedReading,
            limit: limit,
            modeRawValue: systemCandidateMode.rawValue,
            hasDigitPrefix: hasDigitPrefix
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
        // め終わり読みの『め/目』選好(序数/形容詞語幹。設定に応じたペア整列・補生成・除去)。
        finalCandidates = applyMeSuffixPreferences(reading: normalizedReading, to: finalCandidates)
        // 助数詞+付属語(かい+しか 等)の合成をレア語合成(芥子か 等)より前へ(先頭候補の直後)。
        finalCandidates = Self.counterKanaTailPromotedCandidates(finalCandidates, reading: normalizedReading)
        // 合成中の読みが数字接頭(4まんえん 等。normalizedReading は数字を落とすため元の reading で
        // 判定)なら、確定済み数字直後と同じ助数詞ブーストを適用して 万円/本 等を先頭へ。
        if hasDigitPrefix, let digit = reading.first {
            finalCandidates = Self.digitContextCounterBoostedCandidates(
                finalCandidates,
                reading: normalizedReading,
                precedingCharacter: digit,
                suppressedCandidates: context.suppressedCandidatesByReading[normalizedReading] ?? []
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
        let manualAjoutVocabulary = store.ajoutVocabulary()
        let learnedDictionary = store.learnedDictionary()
        let initialAjoutVocabulary = store.initialAjoutVocabulary()

        let systemCandidates = systemCandidates(for: reading, mode: mode)
        let userCandidates = uniqueCandidates(
            from: (manualAjoutVocabulary[reading] ?? [])
                + (initialAjoutVocabulary[reading] ?? [])
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
            ajoutVocabulary: manualAjoutVocabulary,
            learnedDictionary: learnedDictionary,
            initialAjoutVocabulary: initialAjoutVocabulary,
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
        // 補助語彙の昇格判定(定数コメント参照)。同読みに語LM実在の一般語があれば昇格しない。
        let supplementalCandidates = Set(
            store.loadSupplementalSystemDictionary().candidates(for: context.reading)
        )
        let promotesSupplemental: Bool = {
            guard !supplementalCandidates.isEmpty else {
                return false
            }
            let others = context.systemCandidates.filter { !supplementalCandidates.contains($0) }
            guard !others.isEmpty else {
                return true
            }
            return store.wordLMUnigramCosts(for: others).isEmpty
        }()
        var normalSystemCandidates: [String] = []
        var harvestTierCandidates: [String] = []
        var supplementalSystemCandidates: [String] = []
        for candidate in context.systemCandidates {
            if promotesSupplemental, supplementalCandidates.contains(candidate) {
                supplementalSystemCandidates.append(candidate)
            } else if let cost = wordCosts[candidate],
                cost >= CandidateScore.harvestTierWordCostFloor,
                !seedExempt.contains(candidate) {
                harvestTierCandidates.append(candidate)
            } else {
                normalSystemCandidates.append(candidate)
            }
        }
        addCandidates(
            supplementalSystemCandidates,
            baseScore: CandidateScore.supplementalVocabulary,
            to: &scores
        )
        addCandidates(normalSystemCandidates, baseScore: CandidateScore.systemDictionary, to: &scores)
        addCandidates(harvestTierCandidates, baseScore: CandidateScore.harvestTierDictionary, to: &scores)
        addCandidates(context.userCandidates, baseScore: CandidateScore.ajoutVocabulary, to: &scores)
        addCandidates(context.learnedCandidates, baseScore: CandidateScore.learnedDictionary, to: &scores)
        // 完全一致専用候補(踊り字 等)。入力全体がこの読みと一致した単文節でのみ供給する。
        // systemCandidates には入れていないので、語幹合成・連文節には現れない。
        if let exactOnly = KanaKanjiSeedDictionary.exactReadingOnlySeed[context.reading] {
            addCandidates(exactOnly, baseScore: CandidateScore.exactReadingOnly, to: &scores)
        }
        // 部首名の完全一致(くさかんむり→艹 等)は字形を末尾供給する(2565)。
        // 名前は bushu.plist 由来(2字以上のみ。の/に 等の1字名は一般語と衝突するため対象外)
        if let radicalForms = KanjiRadicalCatalog.formsByKanaName[context.reading] {
            addCandidates(radicalForms, baseScore: CandidateScore.exactReadingOnly, to: &scores)
        }
        // 末尾を長音で引き伸ばした形(なるほどー)は辞書に無く、単文節では候補が1件も
        // 作れない。keepKana(末尾長音の剥がし)が根拠を認める読みに限り、かな全長を
        // 供給する。keepKana は既にあるかな候補を維持するだけで供給はしないため(2564)
        if shouldKeepKanaIdentityLeading(for: context.reading),
            context.reading.hasSuffix("ー") {
            addCandidates([context.reading], baseScore: CandidateScore.supplementalVocabulary, to: &scores)
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
            ajoutVocabulary: context.ajoutVocabulary,
            initialAjoutVocabulary: context.initialAjoutVocabulary,
            systemCandidateMode: context.mode,
            limit: limit * 3
        )
        addCandidates(inflectionDerivedCandidates, baseScore: CandidateScore.inflection, to: &scores)

        addCandidates(
            adjectiveGaruCandidates(
                for: reading,
                ajoutVocabulary: context.ajoutVocabulary,
                initialAjoutVocabulary: context.initialAjoutVocabulary,
                systemCandidateMode: context.mode,
                limit: limit * 3
            ),
            baseScore: CandidateScore.adjectiveGaru,
            to: &scores
        )

        addCandidates(
            politePrefixPassthroughCandidates(
                for: reading,
                ajoutVocabulary: context.ajoutVocabulary,
                initialAjoutVocabulary: context.initialAjoutVocabulary,
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
                ajoutVocabulary: context.ajoutVocabulary,
                initialAjoutVocabulary: context.initialAjoutVocabulary,
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

        let arabicNumericCompound = arabicNumericCompoundCandidates(for: reading)
        addCandidates(
            arabicNumericCompound,
            baseScore: CandidateScore.numericArabicCompound,
            to: &scores
        )

        let numericCounterCompound = numericCounterCompoundCandidates(
            for: reading,
            ajoutVocabulary: context.ajoutVocabulary,
            initialAjoutVocabulary: context.initialAjoutVocabulary,
            systemCandidateMode: context.mode,
            limit: limit * 2
        )
        addCandidates(
            numericCounterCompound,
            baseScore: CandidateScore.numericCounterCompound,
            to: &scores
        )

        // 連濁・促音便形の助数詞(3ぼん/6ぽん/3びき)は数詞に付いたときにしか現れないため、
        // 数詞複合を辞書級へ引き上げる(さんぼん→三盆/山本 に負けていた)。
        applyVoicedCounterNumericCompoundBoost(
            for: reading,
            candidates: arabicNumericCompound + numericCounterCompound,
            to: &scores
        )

        applyNumericUnitFallbackPriorityBoost(
            for: reading,
            fallbackCandidates: numericUnitFallback,
            to: &scores
        )

        // 名詞+漢字接辞の合成は辞書に無い語の補完なので、既に登録済みの候補(辞書語 表化 rank4 等)には
        // 重ねない(2734)。addCandidates は経路ごとに加算するため、ひょうか で 表化(1196+986=2182)が
        // 評価(1200)を越えていた(候補数 limit≥8 で合成 表化 が届くとき。limit 3 のテストでは見えなかった)
        let affixCandidates = nounKanjiAffixCandidates(
            for: reading,
            ajoutVocabulary: context.ajoutVocabulary,
            initialAjoutVocabulary: context.initialAjoutVocabulary,
            systemCandidateMode: context.mode,
            limit: limit * 2
        )
        addCandidates(
            affixCandidates.filter { scores[$0] == nil },
            baseScore: CandidateScore.nounKanjiAffix,
            to: &scores
        )

        let quickPostfixCandidates = quickPostfixCandidatesUsingCachedStem(
            for: reading,
            limit: limit,
            systemCandidateMode: context.mode
        )

        // かな識別(読みそのもの)が辞書項目として登録済みなら postfix のかなエコーは重ねない(2731)。
        // addCandidates は経路ごとに加算するため、辞書にかな収穫項目がある読み(ひょうか rank5)は
        // エコー(ひょう+か)と合算されて 1195+1036=2231 となり 評価(1200)を常に押しのけていた。
        // 辞書に無い読み(ひとにでも/だよ/いかなくて/うまいのだ)は活用派生のかなエコーとの合算を含め従来どおり
        let postfixCandidates: [String]
        let postfixBaseScore: Int
        if !quickPostfixCandidates.isEmpty {
            postfixCandidates = quickPostfixCandidates
            postfixBaseScore = CandidateScore.quickPostfix
        } else {
            postfixCandidates = postfixPassthroughCandidates(
                for: reading,
                ajoutVocabulary: context.ajoutVocabulary,
                initialAjoutVocabulary: context.initialAjoutVocabulary,
                systemCandidateMode: context.mode,
                limit: limit * 3
            )
            postfixBaseScore = CandidateScore.bfsPostfix
        }
        let skipsKanaEcho = context.systemCandidates.contains(reading)
        addCandidates(
            skipsKanaEcho ? postfixCandidates.filter { $0 != reading } : postfixCandidates,
            baseScore: postfixBaseScore,
            to: &scores
        )

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
            ajoutVocabulary: context.ajoutVocabulary,
            initialAjoutVocabulary: context.initialAjoutVocabulary,
            systemCandidateMode: context.mode,
            systemCandidates: context.systemCandidates,
            inflectionDerivedCandidates: Set(inflectionDerivedCandidates),
            to: &scores
        )
        applyLearning(context.learningScoresForReading, to: &scores)
        // 抑制語彙はステージ4で除去されるが、スクリプト種の比較グループ(LM首位化・
        // カタカナ保護)には抑制前のジャンク(市市 等)が混ざると誤判定するため先に除く。
        let suppressed = context.suppressedCandidatesByReading[context.reading] ?? []
        // LM 圧倒的最良の辞書候補を rank0 の上へ(一般機構 2545。ゲートは定数コメント参照)。
        // 追加語彙/学習語彙がある読みはユーザーの矯正済み(へいき→平気 等)なので触らない —
        // 昇格目標が rank0 の現スコア(curated 2400 込み)基準のため、ここで弾かないと
        // LM 優位の同音語(兵器)が curated を跨いで先頭化してしまう。
        if context.userCandidates.isEmpty, context.learnedCandidates.isEmpty {
            applyLMDominantDictCandidateBoost(
                for: context.reading,
                systemCandidates: suppressed.isEmpty
                    ? context.systemCandidates
                    : context.systemCandidates.filter { !suppressed.contains($0) },
                to: &scores
            )
        }
        // 単漢字+ない断片が辞書語を跨ぐ構造の是正(定義コメント参照。2618)。
        // 追加/学習語彙がある読みはユーザー矯正済みなので触らない(2545と同条件)
        if context.userCandidates.isEmpty, context.learnedCandidates.isEmpty {
            applyDictOverNaiFragmentBoost(
                for: context.reading,
                systemCandidates: suppressed.isEmpty
                    ? context.systemCandidates
                    : context.systemCandidates.filter { !suppressed.contains($0) },
                to: &scores
            )
            // 多字語+末尾1かな断片(実業か/池だ 等)版。〜家問題の一般対応(2637)
            applyDictOverTailKanaFragmentBoost(
                for: context.reading,
                systemCandidates: suppressed.isEmpty
                    ? context.systemCandidates
                    : context.systemCandidates.filter { !suppressed.contains($0) },
                to: &scores
            )
            // 頭1かな断片(あ闊歩句/あ尾っぽ句 等)より活用派生(赤っぽく)を上へ(2650)
            applyDerivedOverHeadKanaFragmentBoost(
                for: context.reading,
                systemCandidates: context.systemCandidates,
                inflectionDerivedCandidates: Set(inflectionDerivedCandidates),
                to: &scores
            )
            // 形容詞連用形(高く/寒く/近く)の順位補正(2026-08-27)
            applyAdjectiveRenyouBoost(
                for: context.reading,
                dictionaryCandidates: context.systemCandidates,
                inflectionDerivedCandidates: Set(inflectionDerivedCandidates),
                to: &scores
            )
            // 形式名詞 とき のかな正書(2690)
            applyFormalNounTokiKanaPreference(for: context.reading, to: &scores)
            // 述語+終助詞クラスタで終助詞を漢字化した合成(菊鹿も)を下へ(2705)
            applyPredicateFinalParticleClusterPreference(for: context.reading, to: &scores)
            // て/で+ください でて形をかなに保たない合成(仕手ください)を下へ(2720)
            applyTeKudasaiKanaPreference(for: context.reading, to: &scores)
            // 辞書の主要語(格下)を活用族(隠した/画した/…/かくした)の先頭直下へ(2657)
            applyDictWordOverInflectionSiblingsBoost(
                for: context.reading,
                systemCandidates: suppressed.isEmpty
                    ? context.systemCandidates
                    : context.systemCandidates.filter { !suppressed.contains($0) },
                inflectionDerivedCandidates: Set(inflectionDerivedCandidates),
                to: &scores
            )
        }
        applySameReadingScriptPreference(
            for: context.reading,
            systemCandidates: suppressed.isEmpty
                ? context.systemCandidates
                : context.systemCandidates.filter { !suppressed.contains($0) },
            to: &scores
        )
        applySeedSingleKanjiPriorityBoost(for: context.reading, to: &scores)
        applyRegionalProduceBoost(for: context.reading, to: &scores)
        applyYoiKanjiBelowKanaPreference(to: &scores)
        applySeedOrderNormalization(
            for: context.reading,
            learningScoresForReading: context.learningScoresForReading,
            to: &scores
        )
        // あった/あって系の単独読みはかな先頭(seed 順正規化の後に置く。RankingHeuristics の isStandaloneAttaReading 参照。2740)
        if Self.isStandaloneAttaReading(context.reading), let identity = scores[context.reading] {
            let maxOther = scores.filter { $0.key != context.reading }.values.max() ?? 0
            scores[context.reading] = max(identity, maxOther + 1)
        }
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

        let deinflectionProbes = deinflectionSuppressionProbes(
            reading: context.reading,
            suppressedByReading: context.suppressedCandidatesByReading
        )
        for candidate in Array(scores.keys) where isDeinflectedSuppressed(
            candidate: candidate,
            probes: deinflectionProbes
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
                // 単独入力の候補列では多字表層の連濁収穫(でま→手間/手ま)も弾く
                || isRendakuHarvestSurface(
                    candidate,
                    reading: context.reading,
                    includingMultiCharacterSurfaces: true
                )) {
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
            // 活用派生(勝って/切って 等のて形)は 勝手/切手 と構造衝突するため対象外。
            // seed 先頭指定(うつ病 等、交ぜ書きが現代の主表記として人手選別された語)も
            // 対象外。先頭以外の seed 掲載(かぶと虫 等の並び指定のみ)は従来どおり抑制対象
            for candidate in scores.keys
            where !exemptCandidates.contains(candidate)
                && !inflectionDerivedCandidates.contains(candidate)
                && KanaKanjiSeedDictionary.seed[reading]?.first != candidate {
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
            // 辞書コストによる外来語保護(定数コメント参照)。同読みの非カタカナ候補の最安と比べる。
            let readingWordCosts = store.wordCosts(for: reading)
            let nonKatakanaBestWordCost = readingWordCosts
                .filter { !Self.isKatakanaString($0.key) }
                .values
                .min()
            katakanaTargets = katakanaTargets.filter { candidate in
                if let katakanaWordCost = readingWordCosts[candidate],
                    let nonKatakanaBestWordCost,
                    nonKatakanaBestWordCost - katakanaWordCost >= CandidateScore.loanwordKatakanaWordCostGap {
                    return false
                }
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
        #if DEBUG
        // 時限トレース(2660): SINGLE_TRACE=1 のときだけ単文節の最終スコア上位を吐く
        // (MULTI_TRACE の単文節版。チャネル基準値 1200/1120/1040/980 からの増減で経路が読める)
        if ProcessInfo.processInfo.environment["SINGLE_TRACE"] != nil {
            for (index, candidate) in sortedCandidates.prefix(14).enumerated() {
                print("SINGLETRACE[\(context.reading)] #\(index) \(candidate) score=\(scores[candidate, default: 0])")
            }
        }
        // 実機の変換トレース(keyboardConversionLastTrace)向けに上位の点数内訳を残す(2732)。
        // 実機では環境変数が使えず、Mac と実機で単文節の並びが違う(ひょうか: 表化/評価)ときの切り分け用
        let ledger = stateQueue.sync { scoreLedgerForDiagnostics }
        let scoreTrace = sortedCandidates.prefix(8).map { candidate in
            let paths = (ledger[candidate] ?? []).map(String.init).joined(separator: "+")
            return "\(candidate)=\(scores[candidate, default: 0])[\(paths)]"
        }.joined(separator: " ")
        stateQueue.sync {
            lastScoreTraceForDiagnostics = "\(context.reading): \(scoreTrace)"
            scoreLedgerForDiagnostics.removeAll(keepingCapacity: true)
        }
        #endif

        let archaicAdjectiveFiltered = filterArchaicAdjectiveSurfaceCandidates(
            for: context.reading,
            candidates: sortedCandidates,
            ajoutVocabulary: context.ajoutVocabulary,
            learnedDictionary: context.learnedDictionary,
            initialAjoutVocabulary: context.initialAjoutVocabulary
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

    func invalidateCandidateCache() {
        candidateCache.removeAll(keepingCapacity: true)
        candidateCacheOrder.removeAll(keepingCapacity: true)
        multiClauseInflectionCache.removeAll(keepingCapacity: true)
        multiClauseTaFormCheckCache.removeAll(keepingCapacity: true)
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
        ajoutVocabulary: [String: [String]],
        initialAjoutVocabulary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        let normalizedReading = KanaTextNormalizer.normalizedReading(reading)

        guard !normalizedReading.isEmpty else {
            return []
        }

        let candidates = uniqueCandidates(
            from: combinedUserCandidates(
                for: normalizedReading,
                ajoutVocabulary: ajoutVocabulary
            ) + (initialAjoutVocabulary[normalizedReading] ?? [])
                + systemCandidates(for: normalizedReading, mode: systemCandidateMode)
        )

        let suppressedByReading = store.suppressedCandidatesByReading()

        guard !suppressedByReading.isEmpty else {
            return candidates
        }

        let directSuppressed = suppressedByReading[normalizedReading] ?? []
        let probes = deinflectionSuppressionProbes(reading: normalizedReading, suppressedByReading: suppressedByReading)

        return candidates.filter { candidate in
            if directSuppressed.contains(candidate) {
                return false
            }

            return !isDeinflectedSuppressed(candidate: candidate, probes: probes)
        }
    }

    func combinedUserCandidates(
        for reading: String,
        ajoutVocabulary: [String: [String]]
    ) -> [String] {
        let normalizedReading = KanaTextNormalizer.normalizedReading(reading)

        guard !normalizedReading.isEmpty else {
            return []
        }

        let learnedDictionary = store.learnedDictionary()

        return uniqueCandidates(
            from: (ajoutVocabulary[normalizedReading] ?? [])
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
        candidates.uniquedTrimmedCandidates()
    }
}
