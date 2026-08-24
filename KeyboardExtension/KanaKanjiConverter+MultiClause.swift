import Foundation

// 連文節変換(案A1: 語コスト版ビタビ)。単語 n-gram LM(unigram/bigram+backoff)で
// ラティスを組み、Viterbi 最尤経路を候補にする。コスト定数・読み集合・連語表などの
// 静的テーブル群は KanaKanjiConverter+MultiClauseTables.swift に分離(2026-08-17)。
extension KanaKanjiConverter {
    struct MultiClauseNode {
        let start: Int
        let end: Int
        let surface: String
        let reading: String
        let isDictWord: Bool   // 辞書/変換で得た語(true) or かな素通り(false)
        let isCurated: Bool    // 追加語彙/学習語彙(sacoche/misc.plist 等の手動キュレーション or 学習)由来
        let isInflectionDerived: Bool  // (b2) 活用エンジン供給ノード(買った/断線しやすい 等)
        let wordCost: Int?     // word_costs(読み+表層)のコスト。(b) 由来のみ。レア読み床上げに使う
        // inflection_classes に登録された辞書形述語(炊く/書く 等)。Sudachi の word_cost は
        // 動詞が単漢字名詞より系統的に高く、短spanレア読み床が動詞を過剰に床上げする
        // (炊く: uni7666→wc9118)ため、床上げを免除する。読み跨ぎの頻出表層
        // (良く(いく)等)はクラス未登録なので免除されず、床の保護は維持される。
        var isDictionaryFormPredicate: Bool = false
    }

    // minReadingCountOverride: 通常は4かな以上だが、単文節が候補ゼロの読み(のいみ 等の
    // 助詞始まり断片)は短くても連文節に断片解釈(の+意味)をさせる(呼び出し側の
    // フォールバック専用。2642)
    func multiClauseCandidates(
        for reading: String,
        systemCandidateMode: KanaKanjiCandidateSourceMode,
        minReadingCountOverride: Int? = nil
    ) -> [String] {
        guard store.hasWordLMMetadata else {
            return []
        }
        let normalized = KanaTextNormalizer.normalizedReading(reading)
        let chars = Array(normalized)
        let n = chars.count
        guard n >= (minReadingCountOverride ?? Self.multiClauseMinReadingCount),
            n <= Self.multiClauseMaxReadingCount else {
            return []
        }

        let suppressedByReading = store.suppressedCandidatesByReading()
        // 補助語彙(ryukyu/vin/it 等の手選別リスト=SecondVocab)。LM未収録カタカナへの
        // 「何でもカタカナ化抑止」ペナルティから免除するために引く(ジャングリア 対策)。
        let supplementalSystemDictionary = store.loadSupplementalSystemDictionary()
        // 追加語彙(sacoche/misc.plist 等の手動キュレーション)と学習語彙。どちらもユーザ意図なので優遇する。
        let initialUserDictionary = store.initialUserDictionary()
        let learnedDictionary = store.learnedDictionary()
        let manualUserDictionary = store.userDictionary()

        // --- 1. ラティスのノード列挙 ---
        var nodes: [MultiClauseNode] = []
        // b2 活用供給の各スパン先頭(orderedDerivationBaseCandidates=seed/辞書順で最優先)の
        // 活用形ノードのキー("start-end-surface")。連文節でも seed の並び意図を効かせるため、
        // DP でこのノードに軽いボーナスを与える(単文節の seed leading boost の連文節版)。
        // 同音の活用(使えた/仕えた/支えた)が僅差 LM で沈むのを、人手の並びで是正する。
        var preferredInflectedNodeKeys = Set<String>()
        // 名詞 seed 順 opt-in の読み別ボーナス(multiClauseSeedOrderNounBonusesByReading)
        var seedOrderNounNodeBonuses: [String: Int] = [:]
        // (b5) 連用形+に(目的)ノードのキー。直後の移動動詞(来る/行く)を優先するのに使う。
        var renyouNiNodeKeys = Set<String>()
        // スパン別の活用派生表層(キー "start-end")。かな て の連用形接続判定に使う。
        var inflectedSurfacesBySpan: [String: Set<String>] = [:]
        // 短い追加語彙断片(ろー→ロー/raw 等)のうち、同じ開始位置により長い辞書語(ろーぬ→ローヌ)が
        // 実在するものは「長語を分断する断片」とみなし、conn/床(1500)を与えないノードのキー。
        var shortCuratedFragmentNodeKeys = Set<String>()
        // 連語文脈でかなを優先するノードのキー(ひび+入る=ひびが入る 等)。日々 でなく ひび を勝たせる。
        var collocationPreferredKanaNodeKeys = Set<String>()
        var collocationPreferredVerbNodeKeys = Set<String>()
        var collocationDemotedNodeKeys = Set<String>()
        // 連体詞(こういう 等)+準体助詞 の の直後(=活用派生が述語として自然な位置)。
        var prenominalNoInflectionStarts = Set<Int>()
        // 連語の動詞側表層選好(虫がないてる→鳴いてる 等)。連語検出時に動詞区間の開始位置と
        // 優先表層プレフィクスを記録し、その位置から始まる合致表層に連語クランプを与える。
        var collocationPreferredVerbSurfacePrefixesByStart = [Int: [String]]()
        // 連語の名詞スパン("start-end")。変種列挙で名詞表記の変種(めど/メド)の
        // delta 上限を緩和するのに使う(2559)
        var collocationNounSpans = Set<String>()
        // カタカナ強調/交ぜ書きの対象ノード(供給後の一括分類パスで印付け)。
        // suppressed=+100000(事実上不採用)、demoted=+6000(後方)。
        var scriptVariantSuppressedNodeKeys = Set<String>()
        var scriptVariantDemotedNodeKeys = Set<String>()
        // 丁寧接頭辞合成ノードの後置対象(同スパンに実辞書語があるもの。定数コメント参照)
        var politeSupplementDemotedNodeKeys = Set<String>()
        // 補助語彙由来のカタカナ語ノード(ジャングリア 等)。手選別語なので
        // カタカナ化ペナルティ(multiClauseKatakanaNativeCost)を免除する
        var supplementalKatakanaExemptNodeKeys = Set<String>()
        var nodesEndingAt: [[Int]] = Array(repeating: [], count: n + 1)
        var nodesStartingAt: [[Int]] = Array(repeating: [], count: n)

        for start in 0..<n {
            let maxLen = min(Self.multiClauseMaxSegmentReadingCount, n - start)
            for len in 1...maxLen {
                let end = start + len
                let segmentReading = String(chars[start..<end])
                let suppressed = suppressedByReading[segmentReading]

                var surfaces: [(surface: String, isDictWord: Bool, isCurated: Bool, isInflectionDerived: Bool, wordCost: Int?, isDictionaryFormPredicate: Bool)] = []
                var seenSurfaces = Set<String>()
                func add(
                    _ surface: String,
                    isDictWord: Bool,
                    isCurated: Bool,
                    exemptDecorative: Bool = false,
                    isInflectionDerived: Bool = false,
                    wordCost: Int? = nil,
                    isDictionaryFormPredicate: Bool = false
                ) {
                    if let suppressed, suppressed.contains(surface) {
                        return
                    }
                    // 抑制の同一かな末尾合成(まったく→全く なら 全くありません も)を
                    // ラティスにも載せない(単文節ステージ4と同じ規則)。
                    if isComposedSuppressed(
                        candidate: surface,
                        reading: segmentReading,
                        suppressedByReading: suppressedByReading
                    ) {
                        return
                    }
                    if !exemptDecorative, Self.isDecorativeVariantSurface(surface, reading: segmentReading) {
                        return
                    }
                    // 連濁収穫(墓(ばか)等)もラティスに載せない(ばかすぎる→墓すぎる 対策)
                    if !exemptDecorative, isRendakuHarvestSurface(surface, reading: segmentReading) {
                        return
                    }
                    // かな正書の述語(ある 等)はどの供給経路(curated/seed/word_costs)でも
                    // 辞書形述語として扱う。curated(追加語彙 ある→ある)が先着すると dfp=false で
                    // 入り、後続 a2 seed の dfp=true が dedup で失われ、のね/のよ クランプが
                    // 効かず 有るのね に負ける(あるのね 事件)。供給元に依らず確定させる。
                    var resolvedDFP = isDictionaryFormPredicate
                    if surface == segmentReading,
                        Self.multiClauseKanaPredicateIdentities.contains(segmentReading) {
                        resolvedDFP = true
                    }
                    if seenSurfaces.insert(surface).inserted {
                        surfaces.append((surface, isDictWord, isCurated, isInflectionDerived, wordCost, resolvedDFP))
                    } else if resolvedDFP,
                        let index = surfaces.firstIndex(where: { $0.surface == surface }),
                        !surfaces[index].isDictionaryFormPredicate {
                        // 既に dfp=false で入っている かな述語を後続供給で dfp=true に格上げ。
                        surfaces[index].isDictionaryFormPredicate = true
                    } else if isInflectionDerived,
                        surface == segmentReading,
                        let index = surfaces.firstIndex(where: { $0.surface == surface }),
                        !surfaces[index].isInflectionDerived,
                        let existingWordCost = surfaces[index].wordCost,
                        existingWordCost >= KanaKanjiConverter.CandidateScore.harvestTierWordCostFloor {
                        // かな識別の活用形(います 等)は (b) word_costs の収穫底値
                        // (います wc13367→一律9500)が先着し、(b2) の安い活用派生コピー
                        // (7200)が dedupe で死ぬと、かな正書の活用形が漢字派生(居ます)に
                        // 系統的に負ける。派生フラグだけ合流させる(a2 seed の先着 dedupe
                        // 対策と同族)。unigram/wc が実勢の表層(たく 等)は正直な値付けを
                        // 尊重するため対象外(底値帯のみ)。漢字表層も対象外。
                        surfaces[index].isInflectionDerived = true
                    } else if isInflectionDerived,
                        let index = surfaces.firstIndex(where: { $0.surface == surface }),
                        surfaces[index].isCurated,
                        !surfaces[index].isInflectionDerived {
                        // curated(misc の きた→来た 等)が先着すると b2 活用コピーが dedupe で
                        // 死に、後続の述語直後ボーナス(準体助詞 ん 等)が効かない。実機だけ
                        // きたんだが→着たんだが になった真因(テストは misc を読まないため
                        // 再現しなかった)。派生フラグを合流させる(2514)
                        surfaces[index].isInflectionDerived = true
                    }
                }

                // (a) 追加語彙/学習語彙(curated)を常に列挙する。分割・素通りに確実に勝たせるため。
                //     追加語彙はかな識別(ございます/だが 等、かなが正書の登録)も含めて列挙する
                //     — 手動キュレーションの単語であり、かな文丸ごとの学習汚染(ですね事件)とは
                //     異なる。学習語彙側のかな識別スキップは維持。
                //     追加語彙はユーザ明示登録なので装飾フィルタも免除(あ・うん 等の実在固有名)。
                for surface in initialUserDictionary[segmentReading] ?? [] {
                    add(surface, isDictWord: true, isCurated: true, exemptDecorative: true)
                }
                // 手動追加語彙(アプリの語彙管理から登録)も同格の curated として列挙する
                // (従来は連文節に載らない既存ギャップだった)。
                for surface in manualUserDictionary[segmentReading] ?? [] {
                    add(surface, isDictWord: true, isCurated: true, exemptDecorative: true)
                }
                for surface in learnedDictionary[segmentReading] ?? [] where surface != segmentReading {
                    add(surface, isDictWord: true, isCurated: true)
                }

                // 短い追加語彙断片が同じ開始位置のより長い辞書語を分断するのを防ぐ。読み≤2モーラで
                // curated を含み、[start, start+longer] (longer>len) に辞書語が実在する時だけ、その
                // curated ノードを「断片」と印付けし、後段の transitionCost で床(1500)を外す。
                // ろー(ロー/raw)は ろーぬ→ローヌ が実在=断片印。やつ/気を は長い辞書語が無く床維持。
                if segmentReading.count <= 3,
                    surfaces.contains(where: { $0.isCurated && Self.isWordLikeSurface($0.surface) }) {
                    // 「より長い語」は常用語(word_cost が harvest 底値=レア人名 未満)に限る。
                    // ろーぬ→ローヌ(4577)は常用で断片印を付けるが、かおな→華音樹(10000=底値)の
                    // ようなレア人名では 顔(かお)を誤って断片扱いしない。
                    var hasLongerCommonWord = false
                    var probeLen = len + 1
                    while probeLen <= maxLen {
                        let longerReading = String(chars[start..<start + probeLen])
                        let longerCosts = store.wordCosts(for: longerReading)
                        if longerCosts.values.contains(where: {
                            $0 < KanaKanjiConverter.CandidateScore.harvestTierWordCostFloor
                        }) {
                            hasLongerCommonWord = true
                            break
                        }
                        probeLen += 1
                    }
                    // 跨ぎ常用語: 断片の接頭部が指示副詞(こう/そう/どう/ああ)か準体助詞の の で、
                    // その直後から断片の末尾を跨ぐ常用語がある(香茹(こうこ)の中の こう+こたえる、
                    // のか(curated)の中の の+かいじょう=会場 等)ときも分断とみなす。
                    // 接頭を限定するのは、してる(ルナ跨ぎ)/明日(あした)等の正当な curated
                    // かな識別・名詞を巻き込まないため。文末の のか(行くのか)は跨ぐ先が無く床維持。
                    if !hasLongerCommonWord, len >= 2 {
                        outer: for adverb in ["こう", "そう", "どう", "ああ", "の"] {
                            guard segmentReading.hasPrefix(adverb), adverb.count < len else { continue }
                            let crossStart = start + adverb.count
                            var crossLen = (end - crossStart) + 1
                            while crossStart + crossLen <= min(n, crossStart + 6) {
                                let crossReading = String(chars[crossStart..<crossStart + crossLen])
                                let crossCosts = store.wordCosts(for: crossReading)
                                if crossCosts.values.contains(where: {
                                    $0 < KanaKanjiConverter.CandidateScore.harvestTierWordCostFloor
                                }) {
                                    hasLongerCommonWord = true
                                    break outer
                                }
                                crossLen += 1
                            }
                        }
                    }
                    if hasLongerCommonWord {
                        for entry in surfaces where entry.isCurated && Self.isWordLikeSurface(entry.surface) {
                            shortCuratedFragmentNodeKeys.insert("\(start)-\(end)-\(entry.surface)")
                        }
                    }
                }

                // 連語で特定表層を優先(ひび+入る=ひびが入る、さいど+あげる=彩度上げる 等)。
                // 文脈限定=この区間の直後(助詞 は/が/を 任意)が指定動詞の活用のときだけ。
                // 日々を大切に/再度確認 等の非連語文脈は無影響。
                if let collocation = Self.multiClauseNounBeforeVerbCollocations[segmentReading] {
                    var afterIdx = end
                    if afterIdx < n, chars[afterIdx] == "は" || chars[afterIdx] == "が" || chars[afterIdx] == "を"
                        || chars[afterIdx] == "に" {
                        afterIdx += 1
                    }
                    if afterIdx < n {
                        let rest = String(chars[afterIdx..<n])
                        if collocation.verbPrefixes.contains(where: { rest.hasPrefix($0) }) {
                            collocationPreferredKanaNodeKeys.insert("\(start)-\(end)-\(collocation.surface)")
                            collocationNounSpans.insert("\(start)-\(end)")
                            for demoted in collocation.demotedSurfaces {
                                collocationDemotedNodeKeys.insert("\(start)-\(end)-\(demoted)")
                            }
                            if !collocation.preferredVerbSurfacePrefixes.isEmpty {
                                collocationPreferredVerbSurfacePrefixesByStart[afterIdx] = collocation.preferredVerbSurfacePrefixes
                            }
                        }
                    }
                }

                // 連体詞+の の直後を記録(こういうのみかけたら)。の のクランプだけでは、
                // 丸ごと活用(飲み掛けたら=のみかけたら)との OOV 同点で の のノード代分だけ
                // 構造的に負けるため、直後の活用派生も連語選好(prevひらがな限定クランプ)にする。
                if segmentReading == "の", start >= 4,
                    Self.multiClausePrenominalAdjectivalSurfaces.contains(String(chars[(start - 4)..<start])) {
                    prenominalNoInflectionStarts.insert(end)
                }

                let segmentEndsWithSokuon = segmentReading.hasSuffix("っ")
                let costMap = store.wordCosts(for: segmentReading)

                // (b2) の供給ゲートと同条件。a2 の派生形判定でも使うため先に評価する。
                let inflectionSupplyGateSatisfied = len >= 2
                    && len <= Self.multiClauseInflectionMaxSegmentReadingCount
                    && segmentReading.last.map { Self.inflectionRuleSuffixLastCharacters.contains($0) } == true
                // 活用エンジン供給の候補(b2 と a2 で共有。キャッシュは systemCandidateMode 込み)
                func cachedInflectedCandidates() -> [String] {
                    let inflectionCacheKey = "\(systemCandidateMode)|\(segmentReading)"
                    if let cached = stateQueue.sync(execute: { multiClauseInflectionCache[inflectionCacheKey] }) {
                        return cached
                    }
                    // かな識別の除外(b2 の where 相当)後に topK 件を確保できるよう、
                    // 取得は topK の2倍にする(limit ちょうどだと かな が枠を潰し、
                    // かって の 勝って(4番目)が入れない)。
                    let inflected = inflectionCandidates(
                        for: segmentReading,
                        userDictionary: manualUserDictionary,
                        initialUserDictionary: initialUserDictionary,
                        systemCandidateMode: systemCandidateMode,
                        limit: Self.multiClauseInflectionTopK * 2
                    )
                    stateQueue.sync {
                        if multiClauseInflectionCache.count >= multiClauseInflectionCacheLimit {
                            multiClauseInflectionCache.removeAll(keepingCapacity: true)
                        }
                        multiClauseInflectionCache[inflectionCacheKey] = inflected
                    }
                    return inflected
                }

                // (a2) seed(人手の並び矯正/供給)もラティスに載せる。辞書に無い正書
                //      (中の/柚花 等)を連文節でも組めるようにし、コスト同値帯
                //      (名前群は一律 dictUnknown/wc10000 等)のタイブレークを seed 順で
                //      押さえる(ノード列挙順が同 delta 変種の表示順になるため)。
                for surface in KanaKanjiSeedDictionary.seed[segmentReading] ?? [] {
                    if segmentEndsWithSokuon, containsKanji(surface) {
                        continue
                    }
                    // (b) と同じ辞書形述語判定を付ける。無いと seed 掲載の動詞(書く 等)が
                    // 床免除を失って床上げされ、同読みの別動詞(描く)に逆転される。
                    var seedIsDictionaryFormPredicate = false
                    if let lastChar = surface.last,
                        Self.multiClauseDictionaryFormTailCharacters.contains(lastChar),
                        containsKanji(surface) {
                        seedIsDictionaryFormPredicate = store.isShortReadingDictionaryFormPredicate(
                            reading: segmentReading,
                            candidate: surface
                        )
                    }
                    // かな正書の述語(ある/いる 等、かな表記が主の動詞)は inflection_classes に
                    // (かな, かな)で登録が無く上の判定が false になるが、辞書形述語として扱う
                    // (のね/のよ クランプや床免除の対象=あるのね→有るのね 逆転の防止)。
                    if surface == segmentReading,
                        Self.multiClauseKanaPredicateIdentities.contains(segmentReading) {
                        seedIsDictionaryFormPredicate = true
                    }
                    // 辞書に無い活用派生形の seed(読んだ/呼んだ 等の並び矯正)は b2 と同じ
                    // 活用派生フラグを付ける。付けないと dictUnknown(8700)の seed ノードが
                    // 先着 dedupe で b2 の安い活用OOVコピーを潰し、seed 外の同活用
                    // (喚んだ)だけが安く残って逆転する(ほんをよんだ→本を喚んだ)。
                    // 収穫底値(wc>=10000)の表層も対象に含める — 鳴らせる は word_costs に
                    // 底値10302で実在するため costMap==nil 条件を外れ、素の辞書ノード(8700・
                    // 助詞後割引なし)になって 成らせる(活用OOV=助詞後5000)に負けていた(2519)
                    var seedIsInflectionDerived = false
                    if costMap[surface] == nil
                        || (costMap[surface] ?? 0) >= KanaKanjiConverter.CandidateScore.harvestTierWordCostFloor,
                        inflectionSupplyGateSatisfied,
                        cachedInflectedCandidates().contains(surface) {
                        seedIsInflectionDerived = true
                    }
                    add(
                        surface,
                        isDictWord: true,
                        isCurated: false,
                        isInflectionDerived: seedIsInflectionDerived,
                        wordCost: costMap[surface],
                        isDictionaryFormPredicate: seedIsDictionaryFormPredicate
                    )
                    // 名詞 seed 順の opt-in(にほん→日本 等)は先頭候補ノードにボーナスを与え、
                    // 数量詞複合(2本/二本)や分割に連文節でも勝たせる(値は読み別)。
                    if let bonus = Self.multiClauseSeedOrderNounBonusesByReading[segmentReading],
                        surface == KanaKanjiSeedDictionary.seed[segmentReading]?.first {
                        seedOrderNounNodeBonuses["\(start)-\(end)-\(surface)"] = bonus
                    }
                }

                // (b) word_costs(Sudachi 由来)から top-K を列挙。抑制語彙は除外。
                //     促音「っ」で終わる読みは日本語の語として自立しない断片(かっ/きっ 等)で、
                //     Sudachi の複合語内読み(核=カッ 等)由来の漢字ノードがジャンク合成
                //     (いきだけかったぜ→行きだけ核たぜ)を作るため、漢字含み表層は弾く。
                if !costMap.isEmpty {
                    let ordered = costMap.sorted { lhs, rhs in
                        lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key < rhs.key
                    }
                    var dictCount = 0
                    for (surface, cost) in ordered {
                        if segmentEndsWithSokuon, containsKanji(surface) {
                            continue
                        }
                        // 辞書形述語判定(ノード定義コメント参照)。床免除(読み≤2)に加えて
                        // のね/のよ の述語直後クランプでも使うため、長さゲートは置かず
                        // 「漢字+かな活用尾(炊く/書く/重い)」の形状だけで問い合わせを絞る
                        // (読み別キャッシュ済み)。
                        var isDictionaryFormPredicate = false
                        if let lastChar = surface.last,
                            Self.multiClauseDictionaryFormTailCharacters.contains(lastChar),
                            containsKanji(surface) {
                            isDictionaryFormPredicate = store.isShortReadingDictionaryFormPredicate(
                                reading: segmentReading,
                                candidate: surface
                            )
                        }
                        add(
                            surface,
                            isDictWord: true,
                            isCurated: false,
                            wordCost: cost,
                            isDictionaryFormPredicate: isDictionaryFormPredicate
                        )
                        if Self.isKatakanaString(surface),
                            supplementalSystemDictionary.contains(reading: segmentReading, surface: surface) {
                            supplementalKatakanaExemptNodeKeys.insert("\(start)-\(end)-\(surface)")
                        }
                        dictCount += 1
                        if dictCount >= Self.multiClauseTopK {
                            break
                        }
                    }
                }

                // 連語の優先表層(見/自信 等)が word_cost 順の TopK から漏れると、クランプ対象
                // ノード自体が立たない(みにいきたい→ミニ行きたい)。明示供給する(先着 dedupe
                // により (b) が既に足していれば no-op)。
                if let collocation = Self.multiClauseNounBeforeVerbCollocations[segmentReading],
                    collocationPreferredKanaNodeKeys.contains("\(start)-\(end)-\(collocation.surface)") {
                    add(
                        collocation.surface,
                        isDictWord: true,
                        isCurated: false,
                        wordCost: costMap[collocation.surface]
                    )
                }

                // (b2) 活用派生ノード: 活用形(買った/行ける 等)は辞書に収穫しない設計のため、
                //      活用エンジンから供給する。表層は LM 未収録が普通で dictUnknown(8700)が
                //      付くが、断片合成(核+た)や素通りよりは安く、「いきだけかったぜ→
                //      行きだけ買ったぜ」型の分割を可能にする。コスト抑制のため span 長 2〜8、
                //      活用ルール末尾文字に一致する読みのみ、上位3件に限定。
                if inflectionSupplyGateSatisfied {
                    let inflected = cachedInflectedCandidates()
                    // 「直前ノード+て」が連用形接続かの判定に使う(定数コメント参照)
                    inflectedSurfacesBySpan["\(start)-\(end)"] = Set(inflected)
                    // このスパンを脱活用した基底読みが seed順ボーナス allowlist に含まれるか。
                    // (つかえた/つかえ→つかえる 等。含まれる時だけ先頭活用形にボーナス)
                    let spanBaseInSeedOrderAllowlist: Bool = {
                        guard let lastChar = segmentReading.last,
                            let rules = Self.deinflectionRulesByReadingLastCharacter[lastChar] else {
                            return false
                        }
                        for rule in rules where !rule.readingSuffix.isEmpty && segmentReading.hasSuffix(rule.readingSuffix) {
                            let stem = segmentReading.dropLast(rule.readingSuffix.count)
                            guard !stem.isEmpty else { continue }
                            if Self.multiClauseSeedOrderInflectionBaseReadings.contains(stem + rule.baseReadingSuffix) {
                                return true
                            }
                        }
                        return false
                    }()
                    // かな識別(surface==読み)は原則除外(かなエコー防止)。ただし活用エンジンが
                    // かなを第1候補に据えた場合=基底並べ替えが isLMKanaPreferred でかな基底を
                    // 先頭化した場合(なる 3405≪成る/ある/いる/できる 等、かなが LM 優位な動詞)は、
                    // かなが正書なので活用形もかなを供給する。除外したままだと なった が捨てられ
                    // 成った/為った だけが残る(べんりにはなったな→便利には成ったな)。LM 劣位の
                    // 動詞(食べる/見る=たべる/みる が非優位)は依然として漢字が第1候補=かな除外。
                    // かな識別の除外(下記 where 条件)を prefix の後にやると、除外された
                    // かなが枠を潰して次点(かって の 勝って 等)が入れない。先に除外してから
                    // topK 件を採る。
                    var suppliedInflectionCount = 0
                    var suppliedInflectionSurfaces = Set<String>()
                    for (offset, surface) in inflected.enumerated() {
                        if surface == segmentReading, offset != 0 {
                            continue
                        }
                        add(surface, isDictWord: true, isCurated: false, isInflectionDerived: true)
                        suppliedInflectionSurfaces.insert(surface)
                        // スパン先頭(seed/辞書順で最優先)の漢字活用形を連文節ボーナス対象に
                        // 記録。ただし基底読みが allowlist の時のみ(見た/呼んだ 等への波及回避)。
                        if suppliedInflectionCount == 0, surface != segmentReading,
                            spanBaseInSeedOrderAllowlist {
                            preferredInflectedNodeKeys.insert("\(start)-\(end)-\(surface)")
                        }
                        suppliedInflectionCount += 1
                        if suppliedInflectionCount >= Self.multiClauseInflectionTopK {
                            break
                        }
                    }
                    // (b2b) 未代表族の追加供給: 同じ活用形が複数の基底読みから導出できるとき
                    // (はったら=はう系/はる系 等)、先行族が topK を占有すると後続族
                    // (貼ったら/張ったら)はノード自体が立たず LM 競争にすら参加できない
                    // (基底読み間順序の5例目)。topK に代表がいない族のうち、寄与基底の
                    // unigram 最小値が既代表族より明確に優勢(小さい)なものだけ先頭2件を
                    // 追加供給する — 供給の追加のみで既存の並び・ボーナスには触れない。
                    // 優劣ゲートが無いと、借用統計に乗るジャンク族(充て(みて)←あて 等、
                    // 基底が LM 未収録の文語)まで入って既存の最良を壊す。
                    if suppliedInflectionCount >= Self.multiClauseInflectionTopK {
                        let families = inflectionCandidateFamilies(
                            for: segmentReading,
                            userDictionary: manualUserDictionary,
                            initialUserDictionary: initialUserDictionary,
                            systemCandidateMode: systemCandidateMode,
                            perFamilyLimit: 2
                        )
                        let representedBestKey = families
                            .filter { $0.items.contains(where: { suppliedInflectionSurfaces.contains($0) }) }
                            .map(\.familyKey)
                            .min() ?? Int.max
                        for family in families
                        where !family.items.contains(where: { suppliedInflectionSurfaces.contains($0) })
                            && family.familyKey < representedBestKey {
                            for (offset, surface) in family.items.enumerated() where surface != segmentReading {
                                add(surface, isDictWord: true, isCurated: false, isInflectionDerived: true)
                                // 追加は後着列挙のため、OOV同点(全候補LM未収録=7200)の
                                // タイブレーク(列挙順)で既存族に必ず負ける。先行ボーナス(800)は
                                // 無差別に与えると22件退行(2424検証)するため、既存の
                                // seed順allowlist(opt-in)に掲載された基底読みの族に限定する
                                // (はる → ろぐはったら=ログ貼ったら)。
                                if offset == 0,
                                    Self.multiClauseInflectionFamilyPreferenceBaseReadings
                                        .contains(family.baseReading) {
                                    preferredInflectedNodeKeys.insert("\(start)-\(end)-\(surface)")
                                }
                            }
                        }
                    }
                }

                // (b3) 丁寧接頭辞派生ノード: お/ご+連用形(お渡し/お預かり/お届け 等)は
                //      Sudachi に1語で収穫されないことが多く(お願い/お知らせ は例外的に有る)、
                //      おわた+し のような断片合成に負ける。politePrefix 経路から上位を供給する。
                //      コストは dictUnknown(8700)扱い(isInflectionDerived を付けない)。派生の
                //      7200 だと Sudachi 実在の お店(unigram 7099+500)を お見せ が逆転してしまう。
                //      断片合成(苧綿+視 ≈16000)には 8700 でも十分勝てる。
                if len >= 3,
                    let firstChar = segmentReading.first,
                    firstChar == "お" || firstChar == "ご" {
                    let polite = politePrefixPassthroughCandidates(
                        for: segmentReading,
                        userDictionary: manualUserDictionary,
                        initialUserDictionary: initialUserDictionary,
                        systemCandidateMode: systemCandidateMode,
                        limit: Self.multiClauseInflectionTopK
                    )
                    // 同スパンに実辞書語(収穫底値未満)があれば合成ノードを後置(定数コメント参照)
                    let spanHasRealDictWord = costMap.values.contains {
                        $0 < KanaKanjiConverter.CandidateScore.harvestTierWordCostFloor
                    }
                    for surface in polite.prefix(Self.multiClauseInflectionTopK)
                    where surface != segmentReading {
                        add(surface, isDictWord: true, isCurated: false)
                        if spanHasRealDictWord {
                            politeSupplementDemotedNodeKeys.insert("\(start)-\(end)-\(surface)")
                        }
                    }
                }

                // (b4) 数量詞複合ノード: 何件/何軒/何本/何枚/数台 等はロジック生成で
                //      word_costs に無いため、連文節では 何県 分割や 軟堅 に負ける。
                //      単文節と同じ numericCounterCompoundCandidates を供給する。
                //      コストは活用派生と同じ(7200)= 分割ゴミには勝つが なんかい→難解
                //      のような実在の非数量語には基本負ける穏当な強さ。
                if len >= 2 {
                    // 算用数字+助数詞(2本/第1回)を漢数字より先に供給(ユーザ方針: 算用優先)。
                    for surface in arabicNumericCompoundCandidates(for: segmentReading)
                    where surface != segmentReading {
                        add(surface, isDictWord: true, isCurated: false, isInflectionDerived: true)
                    }
                    let numeric = numericCounterCompoundCandidates(
                        for: segmentReading,
                        userDictionary: manualUserDictionary,
                        initialUserDictionary: initialUserDictionary,
                        systemCandidateMode: systemCandidateMode,
                        limit: Self.multiClauseInflectionTopK
                    )
                    for surface in numeric.prefix(Self.multiClauseInflectionTopK)
                    where surface != segmentReading {
                        add(surface, isDictWord: true, isCurated: false, isInflectionDerived: true)
                    }
                }

                // (b4) 名詞化節(のが/のは 等)と説明の のね/のよ のかな単位ノードを常設する。
                //      辞書にレア名前(野賀 wc10000 等)だけがあると (c) の素通り補完が走らず、
                //      述語直後クランプの対象ノード自体が立たない(たくのがすき→宅のが好き)。
                if Self.multiClauseNominalizerSurfaces.contains(segmentReading)
                    || Self.multiClauseExplanatoryFinalSurfaces.contains(segmentReading)
                    // 口語終止クラスタ(かなー 等)も常設 — 辞書/wc に無い読みはノード自体が立たず、
                    // クランプ(4000)が適用できない(こんないろかなー→色香なー 対策)
                    || Self.multiClauseColloquialExplanatoryTailReadings.contains(segmentReading)
                    // 授受補助動詞(あげて/くれてる 等)も常設 — 基底LM順(挙げる5399<上げる<
                    // あげる)で b2 のかな供給が落ち、て形直後クランプの対象ノード自体が立たない
                    // (教えてあげて→教えて挙げて 対策。て/で 直後以外では素通りコストのまま)
                    || Self.isTeBenefactiveAuxiliaryReading(segmentReading) {
                    add(segmentReading, isDictWord: false, isCurated: false)
                }

                // (b4c) カ変「来る」の活用形。活用供給順で 着る/衣る/著る(一段)の後に回り
                //      来た/来て 等が topK から漏れて連文節に載らず、食べに来た鳥→食べに北鳥 等の
                //      名詞化(北)に負ける。来〜 を明示ノードで供給(北 とは競合させ LM に委ねる)。
                if let kuruSurface = Self.multiClauseKuruFormSurfaces[segmentReading] {
                    add(kuruSurface, isDictWord: true, isCurated: false, isInflectionDerived: true)
                }

                // (b5) 連用形+に(目的: 食べに来る/飲みに行く)ノード。動詞の連用形は活用
                //      エンジンの終点でないため 食べ 単独ノードが立たず、たべにきたとり→た部に…
                //      のような断片合成に落ちる。連用形+に を1単位で供給する(食べに/飲みに)。
                //      名詞+に(机に 等)は連用形が導出できず空になるので誤爆しない。
                if len >= 3, segmentReading.hasSuffix("に") {
                    let renyouReading = String(segmentReading.dropLast())
                    let renyouNi = verbRenyouPlusSuffixCandidates(
                        renyouReading: renyouReading,
                        trailingSuffix: "に",
                        userDictionary: manualUserDictionary,
                        initialUserDictionary: initialUserDictionary,
                        systemCandidateMode: systemCandidateMode
                    )
                    for surface in renyouNi.prefix(Self.multiClauseInflectionTopK)
                    where surface != segmentReading {
                        add(surface, isDictWord: true, isCurated: false, isInflectionDerived: true)
                        renyouNiNodeKeys.insert("\(start)-\(end)-\(surface)")
                    }
                }

                // (c) word_costs にも無ければかな素通り(最後の手段)。ローンワード的読みはカタカナ表記。
                //     ※以前は candidates() で補完していたが、多字 span に dictUnknown 一律コストの
                //       blob(例: てんきです→天気です)を作り、正しい細分割(天気+です)を大域的に
                //       上回って DP を歪めていた(はいい→配意 等)。活用形は (b2) の活用エンジン
                //       供給(限定的・8700)で拾う。
                if surfaces.isEmpty {
                    let passthrough: String
                    if readingLooksLikeLoanword(segmentReading),
                        len <= Self.multiClauseSupplementMaxLen {
                        passthrough = Self.hiraganaToKatakana(segmentReading)
                    } else {
                        passthrough = segmentReading
                    }
                    add(passthrough, isDictWord: false, isCurated: false)
                }

                for (surface, isDictWord, isCurated, isInflectionDerived, wordCost, isDictionaryFormPredicate) in surfaces {
                    // 連語の動詞側表層選好(虫がないてる→鳴いてる)。外側ループは start 昇順なので、
                    // 名詞区間の検出(連語キー登録)は動詞区間のノード生成より必ず先に済んでいる。
                    if let preferredVerbPrefixes = collocationPreferredVerbSurfacePrefixesByStart[start],
                        preferredVerbPrefixes.contains(where: { surface.hasPrefix($0) }) {
                        collocationPreferredVerbNodeKeys.insert("\(start)-\(end)-\(surface)")
                    }
                    if isInflectionDerived, prenominalNoInflectionStarts.contains(start) {
                        collocationPreferredVerbNodeKeys.insert("\(start)-\(end)-\(surface)")
                    }
                    let index = nodes.count
                    nodes.append(MultiClauseNode(
                        start: start,
                        end: end,
                        surface: surface,
                        reading: segmentReading,
                        isDictWord: isDictWord,
                        isCurated: isCurated,
                        isInflectionDerived: isInflectionDerived,
                        wordCost: wordCost,
                        isDictionaryFormPredicate: isDictionaryFormPredicate
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
        // 読み跨ぎ unigram 借用の遮断用(定数コメント参照)。旧形式 DB では空=機能オフ。
        let candidateMinWordCosts = store.candidateMinWordCosts(for: Array(unigramSurfaces))

        // カタカナ強調表記/交ぜ書きのモード適用(供給後の一括分類。単文節側と同じ述語)。
        // curated(ユーザ明示)は対象外。外来語(パン 等)は「カタカナ側が unigram 優位」で保護。
        // suppress は +100000(事実上不採用)、demote は +6000(後方)を transitionCost で加える。
        if katakanaEmphasisCandidateMode != .normal || mazegakiCandidateMode != .normal {
            // LM未収録カタカナの「代替が存在する限り強調」判定(単文節側と同義)用: 同スパンに
            // 漢字ノード(辞書/活用派生。成った 等)が居るか。代替ゼロの外来語(サジェスチョン=
            // 辞書唯一・LM未収録)まで抑制すると、LM実在の断片(さ+ジェス+チョン)がジャンク
            // 最良になるため、そこだけ保護する。
            var spanHasKanjiSurface = Set<String>()
            for node in nodes where containsKanji(node.surface) {
                spanHasKanjiSurface.insert("\(node.start)-\(node.end)")
            }
            for node in nodes where !node.isCurated {
                let key = "\(node.start)-\(node.end)-\(node.surface)"
                if katakanaEmphasisCandidateMode != .normal,
                    node.surface != node.reading,
                    let hira = KanaKanjiConverter.hiraganizedKanaOnlySurface(node.surface),
                    hira == node.reading,
                    !(KanaKanjiSeedDictionary.seed[node.reading]?.contains(node.surface) ?? false),
                    !(KanaKanjiSeedDictionary.exactReadingOnlySeed[node.reading]?.contains(node.surface) ?? false),
                    !KanaKanjiConverter.katakanaRunsAreSeedProtected(node.surface) {
                    let kataUni = unigramCosts[node.surface]
                    let altUni = unigramCosts[node.reading]
                    let isEmphasis: Bool
                    if let kataUni {
                        isEmphasis = (altUni != nil && altUni! < kataUni)
                    } else {
                        isEmphasis = altUni != nil
                            || spanHasKanjiSurface.contains("\(node.start)-\(node.end)")
                    }
                    if isEmphasis {
                        if katakanaEmphasisCandidateMode == .suppress {
                            scriptVariantSuppressedNodeKeys.insert(key)
                        } else {
                            scriptVariantDemotedNodeKeys.insert(key)
                        }
                        continue
                    }
                }
                if mazegakiCandidateMode != .normal,
                    !node.isInflectionDerived,
                    let kanjiPart = KanaKanjiConverter.mazegakiKanjiPart(node.surface, reading: node.reading) {
                    let sameReadingCosts = store.wordCosts(for: node.reading)
                    let fullKanjiExists = sameReadingCosts.keys.contains { full in
                        full != node.surface
                            && KanaKanjiConverter.isAllKanjiSurface(full)
                            && unigramCosts[full] != nil
                            && kanjiPart.count < full.count
                            && KanaKanjiConverter.isSubsequence(kanjiPart, of: full)
                    }
                    if fullKanjiExists {
                        if mazegakiCandidateMode == .suppress {
                            scriptVariantSuppressedNodeKeys.insert(key)
                        } else {
                            scriptVariantDemotedNodeKeys.insert(key)
                        }
                    }
                }
            }
        }

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
                    let prevNode = nodes[prevIdx]
                    let auxTail = Self.auxTailForBigramBorrow(of: prevNode)
                    for curIdx in nodesStartingAt[boundary] {
                        addPair(prevNode.surface, nodes[curIdx].surface)
                        if let auxTail {
                            addPair(auxTail, nodes[curIdx].surface)
                        }
                    }
                }
            }
        }
        for idx in nodesEndingAt[n] {
            addPair(nodes[idx].surface, Self.multiClauseEOSMarker)
            if let auxTail = Self.auxTailForBigramBorrow(of: nodes[idx]) {
                addPair(auxTail, Self.multiClauseEOSMarker)
            }
        }
        let bigramCosts = store.wordLMBigramCosts(for: bigramPairs)

        // 複合動詞の前部要素になる連用形ノード(定数コメント参照)。列挙後に一度だけ走査する。
        var compoundVerbRenyouNodeKeys = Set<String>()
        for node in nodes
        where Self.multiClauseCompoundVerbRenyouStemReadings.contains(node.reading)
            && node.surface != node.reading
            && node.surface.hasSuffix("り") {
            compoundVerbRenyouNodeKeys.insert("\(node.start)-\(node.end)-\(node.surface)")
        }

        // --- 3. コスト関数(sim_lm.py と一致): bigram / unigram+backoff / 辞書OOV / 素通りper-char ---
        func transitionCost(
            prev: String,
            prevAuxTail: String?,
            surface: String,
            reading: String,
            isDictWord: Bool,
            isCurated: Bool,
            isInflectionDerived: Bool,
            wordCost: Int? = nil,
            isDictionaryFormPredicate: Bool = false,
            prevIsDictionaryFormPredicate: Bool = false,
            prevIsInflectionDerived: Bool = false,
            isShortCuratedFragment: Bool = false,
            isCollocationPreferredKana: Bool = false,
            isCollocationPreferredVerb: Bool = false,
            scriptVariantPenalty: Int = 0,
            prevDeniesOutgoingBigram: Bool = false,
            isSupplementalKatakanaExempt: Bool = false
        ) -> Int {
            var base: Int
            var penaltyForNounHoshii = 0
            // 読み跨ぎ bigram 借用の遮断(定数コメント参照。人(にん/じん)/頭(ず) 等)。
            // 一般則(2423): bigram は表層単位の統計なので、この読みの word_cost が
            // 収穫底値(>=10000)または表層の最安読みから大きく乖離(>=2500)している場合は
            // 主読みの実績とみなして信用しない(ない→曲 4185(きょく用途)を 曲(くせ wc10067)が
            // 借用して やらない曲に を作る穴 — unigram側の底値降格/乖離床(2078/2126/2386)を
            // bigram分岐だけが素通りしていた)。seed 掲載語は人手選別のため免除。
            let crossReadingBigramDenied: Bool = {
                // かな識別(表層==読み)は表層統計がそのまま自分の統計なので借用があり得ない
                // (かな識別の wc は収穫底値(>=10000)が多く、除外しないと できた/してる 等の
                // かな bigram を没収して漢字側に負ける)。seed 掲載語も人手選別のため免除。
                guard let wordCost,
                    surface != reading,
                    !(KanaKanjiSeedDictionary.seed[reading]?.contains(surface) ?? false) else {
                    return false
                }
                if wordCost >= KanaKanjiConverter.CandidateScore.harvestTierWordCostFloor {
                    return true
                }
                if let minWordCost = candidateMinWordCosts[surface],
                    wordCost - minWordCost >= Self.multiClauseCrossReadingUnigramGapThreshold {
                    return true
                }
                return false
            }()
            let deniesBigramBorrow = (Self.multiClauseBigramBorrowDeniedReadingsBySurface[surface]?
                .contains(reading) ?? false) || prevDeniesOutgoingBigram || crossReadingBigramDenied
            // BOS bigram は使わない: LMコーパス(Wikipedia)の「文頭に来やすい語」統計は
            // キーボードの断片入力(文中から打ち始めることが多い)と系統的に食い違い、
            // かくのが→各のが(BOS→各 3715 ≪ BOS→書く 6265)のような歪みを生むため、
            // 文頭は unigram+バックオフで評価する。文中の bigram は従来どおり。
            // EOS bigram は半分に圧縮して使う: 「文末に来やすい語」統計は断片入力と
            // 系統的に食い違う(記事は 〜の勝ち。で終わるが 〜の価値 は文中に続く:
            // 勝ち→EOS 1253 vs 価値→EOS 2399 の差1146が、の→価値 4234 ≪ の→勝ち 5150
            // の正しい優位916を逆転)。ただし全面無効はやり過ぎで、観測 EOS の正しい信号
            // (層2489<そう2945 が 学生層 を守る、さん2020<三3455 が 柚香さん を守る)まで
            // 消える(2094/2101/今回の全面無効で三度検証済み)。フォールバック(2119)との
            // 中間へ圧縮することで、過大な文末選好だけを弱める。
            // ペアキーは1回だけ連結して両判定で使い回す(エッジ毎に呼ばれるため、
            // 二重連結は DP 全体で数千個の一時 String になる。アリーナ肥大対策 2560)
            let bigramPairKey = prev + "\t" + surface
            if prev != Self.multiClauseBOSMarker,
                !deniesBigramBorrow,
                !Self.multiClauseBigramPairDenied.contains(bigramPairKey),
                let bigram = bigramCosts[bigramPairKey] {
                if surface == Self.multiClauseEOSMarker {
                    let fallback = (unigramCosts[Self.multiClauseEOSMarker] ?? 1619)
                        + Self.multiClauseBackoffCost
                    base = fallback + (bigram - fallback) / 2
                    // 言いさし・話題断片のかな助詞終わり(〜出すと、/〜だから 等)は Wikipedia の
                    // 「この語は文末に来ない」統計(と→EOS 3879 等)が断片入力と系統的に食い違い、
                    // 半減圧縮でも 出すと が ダスト(EOS1648)に負ける。かな助詞 prev の観測 EOS は
                    // fallback より重くしない(よ→EOS 等、安い側の観測信号は保つ)。
                    if Self.multiClauseCaseParticleSurfaces.contains(prev)
                        || Self.multiClauseFinalParticleReadings.contains(prev) {
                        base = min(base, fallback)
                    }
                } else {
                    base = bigram
                }
            } else if !deniesBigramBorrow,
                let prevAuxTail,
                let auxBigram = bigramCosts["\(prevAuxTail)\t\(surface)"] {
                // 活用派生ノードの末尾助動詞トークンで bigram を代用(買わない→よ を ない→よ で評価)
                if surface == Self.multiClauseEOSMarker {
                    let fallback = (unigramCosts[Self.multiClauseEOSMarker] ?? 1619)
                        + Self.multiClauseBackoffCost
                    base = fallback + (auxBigram - fallback) / 2
                } else {
                    base = auxBigram
                }
            } else if let unigram = unigramCosts[surface] {
                base = unigram + Self.multiClauseBackoffCost
                // 短spanレア読み床上げ(定数コメント参照): 表層 unigram はコーパスA単位分割の
                // 影響で語幹断片(見=4181)や別読みの頻出表層(店=みせ用途)、補助動詞由来の
                // かな断片(み)を過小評価する。短spanの漢字表層とかな識別(助詞類は除外)は
                // Sudachi の読み別コストとの max で評価して断片連鎖を防ぐ。
                // 辞書形述語(inflection_classes 登録)は床上げを免除(ノード定義コメント参照)。
                // 床上げの opt-in 免除(定数コメント参照)。seed 全体の免除は退行するため語別。
                if let wordCost,
                    !isDictionaryFormPredicate,
                    !(Self.multiClauseRareReadingFloorExemptSurfacesByReading[reading]?
                        .contains(surface) ?? false),
                    reading.count <= Self.multiClauseRareReadingFloorMaxReadingCount,
                    containsKanji(surface)
                        || (surface == reading
                            && !isCurated
                            && !Self.multiClauseKanaIdentityFloorExemptReadings.contains(reading)) {
                    base = max(base, wordCost)
                }
                // 会話的時相名詞の unigram キャップ(定数コメント参照)。観測 bigram
                // (機能→が/細菌→が 等)には及ばない水準なので が 文脈は同音側が保たれる。
                if let temporalCap = Self.multiClauseConversationalTemporalNounUnigramCaps[surface] {
                    base = min(base, temporalCap)
                }
                // 収穫底値(wc>=10000)の表層は unigram があっても信頼しない — その unigram
                // は別の主読みの統計で、レア読みがタダ乗りする(田中(でんちゅう12670)が
                // たなか 用途の4821、方面(かたも11000)が ほうめん 用途の4792 に乗って
                // 正解の区切りを奪う)。dictUnknown 分岐の底値降格と同じ水準へ床上げする。
                // seed 掲載語は人手選別のため免除(他の降格と同条件)。
                if let wordCost,
                    wordCost >= KanaKanjiConverter.CandidateScore.harvestTierWordCostFloor,
                    !(KanaKanjiSeedDictionary.seed[reading]?.contains(surface) ?? false) {
                    base = max(base, Self.multiClauseHarvestTierUnknownCost)
                }
                // 読み跨ぎ unigram 借用の一般遮断(定数コメント参照): この読みの word_cost が
                // 表層の全読み最安より大きく乖離していたら unigram は主読みの実績とみなし、
                // word_cost を下限にする(後(うしろ)→後ろ 等。読み3字以上のみ=≤2は短span床
                // 適用済み。単一読みの正直な高コスト語(解像度)は乖離0で無傷)。
                if let wordCost,
                    reading.count >= 3,
                    let minWordCost = candidateMinWordCosts[surface],
                    wordCost - minWordCost >= Self.multiClauseCrossReadingUnigramGapThreshold,
                    !(KanaKanjiSeedDictionary.seed[reading]?.contains(surface) ?? false) {
                    base = max(base, wordCost)
                }
            } else if isInflectionDerived {
                // 格助詞・複合助詞(には/では 等)の直後は述語が続くのが自然なので割引する。
                let prevAllowsInflectionDiscount =
                    Self.multiClauseCaseParticleSurfaces.contains(prev)
                    || Self.multiClauseCompoundParticles.contains(prev)
                base = prevAllowsInflectionDiscount
                    ? Self.multiClauseInflectionAfterParticleCost
                    : Self.multiClauseInflectionDerivedOOVCost
            } else if isDictWord {
                base = Self.multiClauseDictUnknownCost
                // 収穫底値ノードはさらに重く(定数コメント参照)。seed 掲載語(柚香 等、
                // wc が底値でも人手で代表に選んだ語)は単文節の降格と同様に免除する。
                if let wordCost,
                    wordCost >= KanaKanjiConverter.CandidateScore.harvestTierWordCostFloor,
                    !(KanaKanjiSeedDictionary.seed[reading]?.contains(surface) ?? false) {
                    base = Self.multiClauseHarvestTierUnknownCost
                }
            } else {
                base = Self.multiClausePassthroughPerCharCost * reading.count
            }
            // 活用派生ノードは OOV 信頼水準を上限にする。LM unigram に「実在するが高い」表層
            // (付けよう=7743)が、未収録の同族(着けよう=OOV 7200)より高く付いて基底順が
            // 逆転するのを防ぐ(きをつけよう→気を着けよう対策)。bigram が安ければそちらを尊重。
            if isInflectionDerived {
                let prevAllowsInflectionDiscount =
                    Self.multiClauseCaseParticleSurfaces.contains(prev)
                    || Self.multiClauseCompoundParticles.contains(prev)
                base = min(
                    base,
                    prevAllowsInflectionDiscount
                        ? Self.multiClauseInflectionAfterParticleCost
                        : Self.multiClauseInflectionDerivedOOVCost
                )
            }
            // 追加語彙/学習語彙は強い下限で優遇(自然な LM コストがより安ければそちらを尊重)。
            // ただし絵文字/記号のみの表層(sacoche の €/🇮🇳/₿ 等)は本文へ割り込ませないため優遇せず、
            // 列挙のみ(単文節候補としては到達可)。語形(かな/漢字/ラテン字を含む)だけ強化する。
            // 追加語彙は床(1500)で優遇するが、「短い断片が同じ開始位置のより長い辞書語を分断する」
            // ノード(ろー→ロー/raw。ろーぬ→ローヌ を分断)は床を与えず自然コスト(辞書/LM実勢、
            // 未収録=高コスト)にする。個別語ではなく断片の性質(供給側で判定)で ろーぬげんさん→
            // ロー脱げんさん 等の誤分割を抑止する。長い辞書語が無い正当な短語(やつ/気を)は床維持。
            // 単文節(ろー だけ入力→ロー/raw)は別経路なので従来どおり先頭に出る。
            if isCurated, Self.isWordLikeSurface(surface), !isShortCuratedFragment {
                base = min(base, Self.multiClauseCuratedWordCost)
            }
            // 複合助詞(かな表層)を単位ノードとして安価にクランプ。ただし基底の格助詞
            // (には→に/では→で)が直前語からの bigram で期待される時だけに限定する。
            // 便利→に は強 bigram(1427)なので には をクランプして 便利にはなった を通す一方、
            // たにた→で は bigram 未観測(unigram 2597)なので では はクランプせず、
            // で+はかったら(計ったら)の は始まり動詞分割を潰さない(たにたではかったら対策)。
            // 文頭(BOS 直後)も除外し でも→デモ/では→出は 等の巻き添えを防ぐ。
            if prev != Self.multiClauseBOSMarker,
                surface == reading,
                Self.multiClauseCompoundParticles.contains(surface),
                bigramCosts["\(prev)\t\(String(surface.dropLast()))"] != nil {
                base = min(base, Self.multiClauseCompoundParticleCost)
            }
            // 名詞化節 のが/のは/のを/のも/のに は述語形直後のみ安価にクランプ(定数コメント参照)。
            if prev != Self.multiClauseBOSMarker,
                surface == reading,
                Self.multiClauseNominalizerSurfaces.contains(surface),
                prev.last.map({ Self.multiClausePredicateTailCharacters.contains($0) }) ?? false {
                base = min(base, Self.multiClauseNominalizerAfterPredicateCost)
            }
            // 連体詞(こういう/そういう 等)直後の準体助詞 の(こういうの+見かけたら)。
            // のみ(飲み)始まりの別分割が bigram で先行するため、の を名詞化節と同じ水準に
            // クランプして正しい区切りを通す(こういうのみかけたら 対策。2535)。
            // こういう は単一ノードでなく こう+いう の2ノードで来るため、prev は いう も対象
            // (X+いう+の の言い回し「〜というの」も同じ名詞化で正当)。
            if prev != Self.multiClauseBOSMarker,
                surface == "の",
                reading == "の",
                prev == "いう" || Self.multiClausePrenominalAdjectivalSurfaces.contains(prev) {
                base = min(base, Self.multiClauseNominalizerAfterPredicateCost)
            }
            // 願望の ほしい/欲しい は て形等の述語直後が正書(買ってほしい)。名詞直後
            // (勝手ほしい)は「が」の脱落形でしか成立せず不自然なので減点する
            // (かってほしい の変種枠を 勝手ほしい が潰し、勝ってほしい が入れない対策)。
            if reading == "ほしい",
                prev != Self.multiClauseBOSMarker,
                !prevIsInflectionDerived,
                !prevIsDictionaryFormPredicate,
                !(prev.last.map { Self.multiClausePredicateTailCharacters.contains($0) } ?? false) {
                penaltyForNounHoshii = Self.multiClauseNounHoshiiPenalty
            }
            // て形直後の授受補助動詞(使ってくれない/してくれてる 等)はかなが正書。紅(名詞
            // くれない)や 暮れてる が繰り上がるのを、かな識別を安価にして防ぐ。prev が て/で
            // 終わり(て形)限定。
            if surface == reading,
                Self.isTeBenefactiveAuxiliaryReading(reading),
                prev != Self.multiClauseBOSMarker,
                (prev.hasSuffix("て") || prev.hasSuffix("で")) {
                base = min(base, Self.multiClauseKanaAdverbCost)
            }
            // 様態の そう(かな)は形容動詞語幹の直後が正書(便利そう/元気そう/静かそう)。
            // 形容動詞かどうかは LM の分布で判定する: prev→な の bigram コストが十分低い
            // (便利→な491/静か→な425/元気→な1129 等、強い連体接続)ことが「形容動詞語幹」の
            // 証拠。単なる名詞の偶発的 →な(馬→な2944 等)は閾値で除外する — でないと
            // 馬+そう が誤クランプされ 旨そう(い形容詞派生)を潰す(うまそうではある→馬そう…)。
            // な はラティスの隣接ペア先読みに載らないため store の点クエリ(キャッシュ済み)で引く。
            if surface == reading,
                reading == "そう",
                prev != Self.multiClauseBOSMarker,
                let naCost = store.wordLMBigramCosts(for: [(prev, "な")])["\(prev)\tな"],
                naCost <= Self.multiClauseNaAdjectiveBigramThreshold {
                base = min(base, Self.multiClauseNominalizerAfterPredicateCost)
            }
            // 名詞化の さ も同じゲート(謙虚さ/便利さ)。形容動詞語幹+さ は正書だが、
            // サ変名詞+さ(検挙さ 等)は非文法。prev→な の実績がある語幹の直後だけ
            // さ を安価化して、けんきょさ→検挙さ の乗っ取りを防ぐ(2543)。
            // さ は元から安い(1200のクランプでは語幹の unigram 差 検挙6325 vs 謙虚7005 を
            // 跨げない)ため専用の強い値を使う。
            if surface == "さ",
                reading == "さ",
                prev != Self.multiClauseBOSMarker,
                let naCost = store.wordLMBigramCosts(for: [(prev, "な")])["\(prev)\tな"],
                naCost <= Self.multiClauseNaAdjectiveBigramThreshold {
                base = min(base, Self.multiClauseNaAdjectiveSaCost)
            }
            // 説明・詠嘆の のね/のよ は辞書形述語(ノードフラグ)直後のみ安価にクランプ
            // (定数コメント参照)。表層末尾文字では名詞 思い と形容詞 重い を区別できない
            // ため、こちらは inflection_classes 由来のフラグでゲートする。
            if surface == reading,
                Self.multiClauseExplanatoryFinalSurfaces.contains(surface),
                prevIsDictionaryFormPredicate || prevIsInflectionDerived {
                // 活用派生(た形/て形: 置いたのよ/食べたのね)直後も説明・詠嘆の正書。
                // 名詞(思い 等)は活用派生ノードにならないため誤爆しない(2434)
                base = min(base, Self.multiClauseNominalizerAfterPredicateCost)
            }
            var penalty = 0
            // 命令形(え段)+格助詞 込みの活用供給ノード(嗅げに 等)は非文なので減点(2644)。
            // OOV定額(7200)がスパン長に依らず、嗅げに が 影+に(7296)を僅差で跨いでいた。
            // base 側だと直後のOOV上限クランプで消されるため penalty で加算する。
            // 連用形+に(買いに)は い段なので無傷。引用の と(読めと)は文法的なので対象外。
            if isInflectionDerived, surface != reading, reading.count >= 3,
                let impTail = reading.last,
                Self.multiClauseImperativeBannedTailParticles.contains(impTail),
                let impMora = reading.dropLast().last,
                Self.multiClauseERowKanaCharacters.contains(impMora) {
                penalty += Self.multiClauseImperativeParticlePenalty
            }
            // bigram 未観測ペアの補完(定数コメント参照)。観測が無いと unigram 差だけで
            // 決まり、文として成立しない組み合わせが勝つ(柔らかくて農耕 等。2564)
            if let bonus = Self.multiClauseBigramPairBonuses[prev + "\t" + surface] {
                penalty -= bonus
            }
            penalty += penaltyForNounHoshii
            // 係助詞「は」(では/には/とは 等の複合助詞末尾含む)直後の ある は漢字化しない=
            // かな正書(定数コメント参照)。変種生成(pairCost)も本関数を通るため 有る/在る/或る を
            // 変種枠から落とす(うまそうでは有る 対策)。格助詞 が/を の後(在庫がある 等)は対象外。
            if reading == "ある",
                surface != "ある",
                containsKanji(surface),
                prev != Self.multiClauseBOSMarker,
                prev.hasSuffix("は") {
                penalty += Self.multiClauseAruKanjiAfterWaPenalty
            }
            // 接頭辞「お」(かな)+ そい は おそい(遅い)の誤分割。お添い/お沿い を変種から落とす。
            if reading == "そい", prev == "お" {
                penalty += Self.multiClauseHonorificOsoiSplitPenalty
            }
            // おそい の お接頭漢字表層(お添い/お沿い=お+添う/沿う連用の誤合成)も同様に減点する。
            // 遅い/おそい 以外で お始まりの漢字表層はこの読みでは不要。
            if reading == "おそい", surface != "おそい", surface.hasPrefix("お"), containsKanji(surface) {
                penalty += Self.multiClauseHonorificOsoiSplitPenalty
            }
            // かな正書の副詞(いまだに 等)・口語終止クラスタ(んだが/んです…)はかな識別を安価にして
            // 漢字/レア語/分割より上位にする。
            if surface == reading,
                Self.multiClauseKanaAdverbReadings.contains(reading)
                    || Self.multiClauseColloquialExplanatoryTailReadings.contains(reading) {
                base = min(base, Self.multiClauseKanaAdverbCost)
            }
            // オノマトペ「〜っと」(4文字以上の全かな。ぱしゃっと/ばたっと/ふわっと 等)はかなが正書。
            // ぱ+シャット のような かな断片+カタカナ語 の合成に勝たせる。きっと/ずっと/もっと(3文字)
            // は文字数条件で対象外(既存の価格付けを尊重)。かな副詞が末尾に埋まった区間
            // (〜はもっと 等)はオノマトペではないので除外(定数コメント参照)。
            if surface == reading,
                reading.count >= 4,
                reading.hasSuffix("っと"),
                !Self.multiClauseSokuonToAdverbTails.contains(where: {
                    reading != $0 && reading.hasSuffix($0)
                }) {
                base = min(base, Self.multiClauseKanaAdverbCost)
            }
            // 文節先頭(直前=BOS)の存在動詞かな過去(あった/いた)はかな正書を優先(あったんで→
            // かな先頭)。文節先頭に限定するので 気があった/目があった/サイズが合った 等(あった の
            // 直前が が/に で prev≠BOS)は無影響=「連文節でないときだけ」というユーザ指定を満たす。
            // かな副詞(もう/まだ)直後も文節先頭同等に扱う(もうあった/まだいた のかな正書。
            // 気があった 等の が/に 直後は従来どおり対象外)
            if surface == reading,
                prev == Self.multiClauseBOSMarker || prev == "もう" || prev == "まだ",
                Self.multiClauseClauseInitialKanaExistentialPasts.contains(reading) {
                base = min(base, Self.multiClauseKanaAdverbCost)
            }
            // 連語文脈でかな名詞を優先(ひび+入る=罅が入る)。かな ひび を 日々(LM5616)より安くする。
            if isCollocationPreferredKana {
                base = min(base, Self.multiClauseKanaAdverbCost)
            }
            // 連語の動詞側表層選好(見に行きたい の 行きたい、虫が鳴く の 鳴いてる 等)。
            // 直前がひらがなノード(助詞/かな名詞)の時だけ安価化する — 無条件だと同じ開始
            // 位置の別分割(ミニ+行きたい)まで恩恵を受け、連語側が149差で負けていた(2535)。
            if isCollocationPreferredVerb,
                prev != Self.multiClauseBOSMarker,
                prev.allSatisfy({ ("ぁ"..."ゖ").contains($0) || $0 == "ー" }) {
                base = min(base, Self.multiClauseKanaAdverbCost)
            }
            // 単漢字名詞→動詞の無助詞接続の減点(定数コメント参照)。prev が単漢字の
            // 漢字表層で、現ノードが動詞(活用派生 or 辞書形述語)のとき。
            if prev.count == 1,
                containsKanji(prev),
                !prevIsInflectionDerived,
                isInflectionDerived || isDictionaryFormPredicate {
                penalty += Self.multiClauseSingleKanjiNounBeforeVerbPenalty
            }
            // 辞書形動詞(終止形。描く/走る 等)+ して/する/した は非文法(正しくは て形)。誤合成を減点。
            if prevIsDictionaryFormPredicate,
                reading == "して" || reading == "する" || reading == "した" || reading == "します" {
                penalty += Self.multiClauseDictionaryFormPlusSuruPenalty
            }
            // コピュラ終止「だ」直後の動詞(定数コメント参照)。さいやくだけおとして→災厄だ蹴落として
            // のような だ|け 誤分割を、だけ(副助詞)+動詞 の正しい区切りに負けさせる。
            if prev == "だ",
                isInflectionDerived || isDictionaryFormPredicate {
                penalty += Self.multiClauseCopulaDaBeforeVerbPenalty
            }
            // 並列助詞「や」直後の敬称さん(定数コメント参照)。薬屋さん/花屋さん の 屋 分断を排除。
            if prev == "や", reading == "さん" {
                penalty += Self.multiClauseParallelYaBeforeSanPenalty
            }
            // カタカナ化ペナルティ(何でもカタカナ化の抑止)。ただし LM unigram を持つ表層は
            // コーパス実在の外来語(サイズ/ゲスト 等、長音なしで readingLooksLikeLoanword に
            // 引っかからない語)なので対象外 — LM が既に価格付けしており二重減点は不当。
            if Self.isKatakanaString(surface),
                !readingLooksLikeLoanword(reading),
                unigramCosts[surface] == nil,
                !isSupplementalKatakanaExempt {
                penalty += Self.multiClauseKatakanaNativeCost
            }
            // を 跨ぎ文節の防止。ただし curated(気をつけて/気が合う 等、を/が 含みで明示登録
            // された慣用句)は正当な1文節なので免除する — でないと misc の 気を〜 慣用句群が
            // 連文節に一切乗れず、きをつけて→機をつけて 等の分割に負ける。
            if reading.count > 1, reading.contains("を"), !isCurated {
                penalty += Self.multiClauseForbiddenPenaltyCost
            }
            // 1字かな素通りの連鎖(さ+ら 等)の遮断(2642): さ/ら のような1字トークンは
            // corpus の字単位 bigram で不当に安く繋がり、白いさらの が 白い+さ+ら+の の
            // バブル経路で最良化していた(皿 が居るのに)。cur 側が機能モーラ(助詞・助動詞・
            // 活用断片: の/た/だ/か/れ/て 等)や活用派生ノード・curated のときは正当な文法連鎖
            // (し+た/の+だ+が/公開+さ+れ+て)なので対象外。
            if surface == reading, reading.count == 1, !isCurated, !isInflectionDerived,
                let scalar = reading.unicodeScalars.first,
                (0x3041...0x3096).contains(scalar.value),
                !Self.multiClauseCaseParticleSurfaces.contains(surface),
                !Self.multiClauseFinalParticleReadings.contains(reading),
                !Self.multiClauseNominalizerSurfaces.contains(surface),
                !Self.multiClauseFunctionalSingleKanaSurfaces.contains(surface),
                prev.count == 1,
                let prevScalar = prev.unicodeScalars.first,
                (0x3041...0x3096).contains(prevScalar.value) {
                penalty += Self.multiClauseKanaMoraChainPenalty
            }
            // seed 供給表層の連文節床(定数コメント参照)。
            if let floor = Self.multiClauseSeedSupplyCostFloors[reading]?[surface] {
                base = max(base, floor)
            }
            // 格助詞直後の でも は副助詞(定数コメント参照)。
            if reading == "でも",
                surface != reading,
                Self.multiClauseCaseParticleSurfaces.contains(prev) {
                penalty += Self.multiClauseParticleContextDemoPenalty
            }
            // 比較の ほうが は連体形接続(定数コメント参照)。
            if reading == "ほうが" || reading == "ほうがいい",
                !prevIsInflectionDerived,
                !prevIsDictionaryFormPredicate,
                prev != "の", prev != "な",
                !(prev != Self.multiClauseBOSMarker
                    && (prev.last.map(Self.multiClausePredicateTailCharacters.contains) ?? false)) {
                penalty += Self.multiClauseHougaAfterNonPredicatePenalty
            }
            // 文頭のかな くらい/ぐらい(副助詞は文頭に立たない。定数コメント参照)。
            if prev == Self.multiClauseBOSMarker,
                surface == reading,
                reading == "くらい" || reading == "ぐらい" {
                penalty += Self.multiClauseSentenceInitialKuraiPenalty
            }
            // 文頭のカ変(来た/来て)を同形の一段(着た/着て)より優先(定数コメント参照)。
            if prev == Self.multiClauseBOSMarker,
                isInflectionDerived,
                Self.multiClauseKuruFormSurfaces[reading] == surface {
                penalty -= Self.multiClauseSentenceInitialKuruBonus
            }
            // 撥音「ん」等の語頭禁止。単独「ん」は準体助詞(切る+ん+だ/行った+ん=のだ縮約)だが、
            // これは述語の連体形直後にのみ立てる。直前文節の末尾が述語末尾文字
            // (multiClausePredicateTailCharacters=う/く/…/る/い/た/だ)のときだけ免除し、
            // 脱げ+ん のような非述語直後の偽準体助詞は禁止する — ろーぬげんさん→ロー脱げんさん の
            // ような「ん始まり文節」の誤分割を個別語ではなく汎用ルールで排除する。
            // って/っていう(引用・話題)は従来どおり無条件免除。
            if let first = reading.first,
                Self.multiClauseForbiddenInitials.contains(first) {
                let isForbiddenInitialExempt: Bool
                if reading == "ん" {
                    isForbiddenInitialExempt = prev != Self.multiClauseBOSMarker
                        && (prev.last.map(Self.multiClausePredicateTailCharacters.contains) ?? false)
                } else {
                    isForbiddenInitialExempt = Self.multiClauseForbiddenInitialExemptReadings.contains(reading)
                }
                if !isForbiddenInitialExempt {
                    penalty += Self.multiClauseForbiddenPenaltyCost
                }
            }
            // 促音「っ」で終わる読みの文節(かっ/カッ 等)は日本語の自立語として成立しない断片。
            // LM コーパスが活用形を A単位(買っ+た)で分割する影響で断片チェーンが不当に安く
            // なり、正しい活用ノード(買った 7200)を阻むため強く減点する。
            // (あっ/えっ 等の感動詞の単独入力は単文節経路が扱うので影響しない)
            if reading.count >= 2, reading.hasSuffix("っ"), !isCurated {
                penalty += Self.multiClauseForbiddenPenaltyCost
            }
            // 助動詞「た」の単独ノードは格助詞直後・文頭に立てない(非文法)。A単位分割由来の
            // 安い unigram/bigram(に→た 等)が断片チェーン(に+た+やつ=にたやつ、
            // た+分+最初=たぶん最初 等)を不当に安くし、正しいノード(似た/たぶん)を
            // 阻むため遮断する(2404/2407)。
            if reading == "た", surface == "た",
                prev == Self.multiClauseBOSMarker || Self.multiClauseCaseParticleSurfaces.contains(prev) {
                penalty += Self.multiClauseForbiddenPenaltyCost
            }
            // 文頭の裸の格助詞/係助詞は非文(定数コメント参照)。禁止ではなく減点で拮抗を覆す。
            if prev == Self.multiClauseBOSMarker, surface == reading,
                Self.multiClauseBOSPenalizedParticles.contains(surface) {
                penalty += Self.multiClauseBOSParticlePenalty
            }
            // 述語直後の終助詞かなクラスタはクランプ(定数コメント参照。2628)。
            // 1字(な/ね/し 等)は対象外 — 来ん(派生)+な が こんな を乗っ取る(検証で2件退行)。
            // のね/のよ も対象外 — 名詞除外付きの既存厳格ゲート(ExplanatoryFinal)に委譲
            if surface == reading, reading.count >= 2,
                Self.multiClauseFinalParticleReadings.contains(reading),
                !Self.multiClauseExplanatoryFinalSurfaces.contains(reading),
                prev != Self.multiClauseBOSMarker,
                (prevIsInflectionDerived || prevIsDictionaryFormPredicate
                    || (prev.last.map(Self.multiClausePredicateTailCharacters.contains) ?? false)) {
                base = min(base, Self.multiClauseFinalParticleAfterPredicateCost)
            }
            // 動詞て形(活用派生)直後の いって(定数コメント参照。2628)
            if reading == "いって", prevIsInflectionDerived,
                prev.hasSuffix("て") || prev.hasSuffix("で") {
                if surface == "行って" {
                    base = min(base, Self.multiClauseTeIkuAuxiliaryCost)
                } else if surface == "一手" {
                    penalty += Self.multiClauseTeNounItteAfterTeFormPenalty
                }
            }
            // 動詞て形(活用派生)直後の短いカタカナ化ノード(≤2かな)は減点(2642)。
            // さがっちゃってるね→下がっちゃて+ルネ(人名)のように、てる/るね/みて 等の
            // 補助・終助詞領域をカタカナ人名がLMバイアスで乗っ取る。て形直後に無空白で
            // カタカナ固有名が続く日本語は不自然なので一般則で沈める(curated は除外)。
            if !isCurated, surface != reading, reading.count <= 2,
                prevIsInflectionDerived,
                prev.hasSuffix("て") || prev.hasSuffix("で"),
                Self.isNonNativeScriptSurface(surface) {
                penalty += Self.multiClauseTeKatakanaShortNounPenalty
            }
            // コピュラ だ の直後の追加語彙の短い非かな断片(ろー→raw/ロー 等)は
            // だろー クラスタの乗っ取り(すごいだろー→すごいだraw)。だ+外来語の
            // 無空白連結は非文なので減点する(ユーザー報告 2618)。
            if prev == "だ", isCurated, surface != reading, reading.count <= 2 {
                penalty += Self.multiClauseKanaShiAfterNonPredicatePenalty
            }
            // 表外訓はかな正書が実勢(定数コメント参照)。連文節でだけ漢字表層を減点する。
            if surface != reading, !isCurated,
                Self.multiClauseKanaOrthodoxReadings.contains(reading) {
                penalty += Self.multiClauseKanaOrthodoxKanjiPenalty
            }
            // カタカナ強調/交ぜ書きモードのノード別ペナルティ(suppress=100000/demote=6000)
            penalty += scriptVariantPenalty
            return base + penalty
        }

        // --- 4. Viterbi DP(ノード = (span, 表層)) ---
        let infinity = Int.max / 4
        var best = Array(repeating: infinity, count: nodes.count)
        var backPointer = Array(repeating: -1, count: nodes.count)

        for boundary in 1...n {
            for idx in nodesEndingAt[boundary] {
                let node = nodes[idx]
                // スパン先頭(seed/辞書順で最優先)の活用形へのボーナス(定数コメント参照)。
                // 読み末尾が名詞化の さ のとき、形容動詞語幹(語幹→な の bigram 実績)ノードへ
                // ボーナス。される 分割由来の安い bigram(検挙→さ532 等)を持つサ変名詞は
                // さ側のクランプだけでは勝てない(語幹差+bigram差 > クランプ余地)ための補完。
                // 読み途中の さ(けんきょされた 等の受身)は末尾条件で対象外(2543)。
                let naAdjectiveSaStemBonus: Int
                if normalized.hasSuffix("さ"),
                    node.end == n - 1,
                    containsKanji(node.surface),
                    let naCost = store.wordLMBigramCosts(for: [(node.surface, "な")])["\(node.surface)\tな"],
                    naCost <= Self.multiClauseNaAdjectiveBigramThreshold {
                    naAdjectiveSaStemBonus = Self.multiClauseNaAdjectiveSaStemBonus
                } else {
                    naAdjectiveSaStemBonus = 0
                }
                // ノードキーは1回だけ生成して使い回す(以前は判定ごとに再生成しており、
                // DP 全体で数千個の一時 String を作っていた。アリーナ肥大対策 2560)
                let nodeKeySV = "\(node.start)-\(node.end)-\(node.surface)"
                let preferredInflectionBonus = (preferredInflectedNodeKeys.contains(nodeKeySV)
                    ? Self.multiClausePreferredInflectionBonus
                    : 0)
                    + (seedOrderNounNodeBonuses[nodeKeySV] ?? 0)
                    + naAdjectiveSaStemBonus
                let nodeIsShortCuratedFragment = shortCuratedFragmentNodeKeys.contains(nodeKeySV)
                let nodeIsCollocationPreferredKana = collocationPreferredKanaNodeKeys.contains(nodeKeySV)
                let nodeIsCollocationPreferredVerb = collocationPreferredVerbNodeKeys.contains(nodeKeySV)
                let nodeScriptVariantPenalty = (scriptVariantSuppressedNodeKeys.contains(nodeKeySV) ? 100000
                    : (scriptVariantDemotedNodeKeys.contains(nodeKeySV) ? 6000 : 0))
                    + (politeSupplementDemotedNodeKeys.contains(nodeKeySV)
                        ? Self.multiClausePoliteSupplementDemotion
                        : 0)
                    + (collocationDemotedNodeKeys.contains(nodeKeySV)
                        ? Self.multiClauseCollocationDemotionPenalty
                        : 0)
                let nodeIsSupplementalKatakanaExempt = supplementalKatakanaExemptNodeKeys.contains(nodeKeySV)
                // 〜ったん の丸ごと語 vs コピュラ過去+準体助詞(定数コメント参照)
                let nodeTanContractionPenalty: Int = {
                    guard node.reading.hasSuffix("ったん"),
                        node.surface != node.reading,
                        !node.isInflectionDerived,
                        node.end < n else {
                        return 0
                    }
                    let rest = String(chars[node.end...])
                    for follower in ["だろう", "だろ", "でしょう", "でしょ"] where rest.hasPrefix(follower) {
                        return Self.multiClauseTanContractionSplitPenalty
                    }
                    return 0
                }()
                if node.start == 0 {
                    // 文頭の形式名詞読みは実質名詞(定数コメント参照)。かな側に減点して漢字を優先
                    // こと は直後に格助詞・係助詞が続く形(ことがある/ことでもなく/ことになる)が
                    // 形式名詞用法でかなが正書。実質名詞は「事の起こり」(の+名詞)や
                    // 「事あるごとに」(助詞なしで述語が続く)なので、直後が の または
                    // 助詞以外なら実質名詞として扱う。とき は文頭で接尾辞用法になることが
                    // 稀なので無条件に漢字を優先する(2459)
                    let isFormalKotoUsage: Bool = {
                        guard node.reading == "こと", node.end < n else {
                            return false
                        }
                        let next = chars[node.end]
                        if next == "の" {
                            return false
                        }
                        return Self.multiClauseCaseParticleSurfaces.contains(String(next))
                    }()
                    let substantivePenalty = (
                        Self.multiClauseSubstantiveNounReadings.contains(node.reading)
                            && node.surface == node.reading
                            && !isFormalKotoUsage
                    ) ? Self.multiClauseSubstantiveNounKanaPenalty : 0
                    let cost = transitionCost(
                        prev: Self.multiClauseBOSMarker,
                        prevAuxTail: nil,
                        surface: node.surface,
                        reading: node.reading,
                        isDictWord: node.isDictWord,
                        isCurated: node.isCurated,
                        isInflectionDerived: node.isInflectionDerived,
                        wordCost: node.wordCost,
                        isDictionaryFormPredicate: node.isDictionaryFormPredicate,
                        isShortCuratedFragment: nodeIsShortCuratedFragment,
                        isCollocationPreferredKana: nodeIsCollocationPreferredKana,
                        isCollocationPreferredVerb: nodeIsCollocationPreferredVerb,
                        scriptVariantPenalty: nodeScriptVariantPenalty,
                        isSupplementalKatakanaExempt: nodeIsSupplementalKatakanaExempt
                    ) - preferredInflectionBonus + substantivePenalty + nodeTanContractionPenalty
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
                    let prevNode = nodes[prevIdx]
                    let prevDeniesOutgoingBigram = Self.multiClauseOutgoingBigramBorrowDeniedReadingsBySurface[prevNode.surface]?
                        .contains(prevNode.reading) ?? false
                    var cost = prevCost + transitionCost(
                        prev: prevNode.surface,
                        prevAuxTail: Self.auxTailForBigramBorrow(of: prevNode),
                        surface: node.surface,
                        reading: node.reading,
                        isDictWord: node.isDictWord,
                        isCurated: node.isCurated,
                        isInflectionDerived: node.isInflectionDerived,
                        wordCost: node.wordCost,
                        isDictionaryFormPredicate: node.isDictionaryFormPredicate,
                        prevIsDictionaryFormPredicate: prevNode.isDictionaryFormPredicate,
                        prevIsInflectionDerived: prevNode.isInflectionDerived,
                        isShortCuratedFragment: nodeIsShortCuratedFragment,
                        isCollocationPreferredKana: nodeIsCollocationPreferredKana,
                        isCollocationPreferredVerb: nodeIsCollocationPreferredVerb,
                        scriptVariantPenalty: nodeScriptVariantPenalty,
                        prevDeniesOutgoingBigram: prevDeniesOutgoingBigram,
                        isSupplementalKatakanaExempt: nodeIsSupplementalKatakanaExempt
                    ) - preferredInflectionBonus + nodeTanContractionPenalty
                    // 連用形+に(目的)は移動動詞が続くときの用法。文末でも格助詞直後の活用割引
                    // (5000)が効くと 千島を裂きに が 千島を先に(を→先4557+先→に532)を
                    // 89 差で押し切るため、文末に限り割引を取り消して素の OOV 値に戻す。
                    if node.end == n, renyouNiNodeKeys.contains(nodeKeySV),
                        Self.multiClauseCaseParticleSurfaces.contains(prevNode.surface) {
                        cost += Self.multiClauseInflectionDerivedOOVCost
                            - Self.multiClauseInflectionAfterParticleCost
                    }
                    // 名詞直後の裸のかな「な」は形容動詞語幹にしか付かない(定数コメント参照)。
                    // ただし直後が の/ん(なので/なのは/なのに/なんです)は断定の助動詞 な
                    // (だ の連体形)で全名詞に付くため対象外 ─ 除外しないと
                    // ひらがななのは→平仮名夏乃波 のように名前へ流れる。
                    if node.surface == "な", node.reading == "な",
                        !(node.end < n && (chars[node.end] == "の" || chars[node.end] == "ん")),
                        !prevNode.isInflectionDerived,
                        !prevNode.isDictionaryFormPredicate,
                        !(prevNode.surface.last.map(Self.multiClausePredicateTailCharacters.contains) ?? false),
                        (bigramCosts[prevNode.surface + "\tな"] ?? Int.max)
                            > Self.multiClauseNaAdjectiveBigramThreshold {
                        cost += Self.multiClauseNaAfterNonNaAdjectivePenalty
                    }
                    // 終端の単独母音読みの漢字ノードは、直前ノード読み末尾と同母音なら
                    // 引き伸ばし表記の乗っ取り(いいねえ→いいね画。定数コメント参照)。
                    if node.end == n, node.surface != node.reading,
                        node.reading.count == 1,
                        let nodeVowel = node.reading.first.flatMap({ Self.multiClauseVowelByKana[$0] }),
                        let prevLastKana = prevNode.reading.last,
                        Self.multiClauseVowelByKana[prevLastKana] == nodeVowel {
                        cost += Self.multiClauseProlongedVowelKanjiPenalty
                    }
                    // 入力末尾の裸の接続助詞「し」は述語直後にしか立てない(定数コメント参照)。
                    // 文中の し はサ変の連用形(勉強し+まくり)なので対象外にする。
                    if node.end == n, node.reading == "し", node.surface == "し",
                        !(prevNode.surface.last.map(Self.multiClausePredicateTailCharacters.contains) ?? false) {
                        cost += Self.multiClauseKanaShiAfterNonPredicatePenalty
                    }
                    // 述語(活用派生・辞書形)直後の形式名詞・副助詞はかな表記が正書
                    // (行ったとき/貸し出すだけ 等)。漢字表記に減点。
                    if prevNode.isInflectionDerived || prevNode.isDictionaryFormPredicate,
                        Self.multiClauseFormalNounKanaReadings.contains(node.reading),
                        node.surface != node.reading {
                        cost += Self.multiClauseFormalNounKanjiPenalty
                    }
                    // 連用形+に(目的)の直後は移動動詞(来る/行く 系)が来る(食べに来た/飲みに行く)。
                    // 前ノードが b5 の 連用形+に なら、移動動詞にボーナスを与え 北 等の名詞化を退ける。
                    if renyouNiNodeKeys.contains("\(prevNode.start)-\(prevNode.end)-\(prevNode.surface)"),
                        Self.isMotionVerbSurface(node.surface) {
                        cost -= Self.multiClauseRenyouNiMotionVerbBonus
                    }
                    // のだ縮約の準体助詞 ん(定数コメント参照)。述語(活用派生)の直後に限る。
                    if node.reading == "ん", node.surface == "ん", prevNode.isInflectionDerived {
                        cost -= Self.multiClauseNominalizerNContractionBonus
                    }
                    // のだ縮約の継続(ん の直後の だ 始まりかな: だ/だが/だけど。定数コメント参照)。
                    // 単独 ん ノードは語頭禁止の免除条件により述語直後にしか生き残らない
                    if prevNode.surface == "ん", prevNode.reading == "ん",
                        node.surface == node.reading,
                        node.reading.first == "だ" {
                        cost -= Self.multiClauseNominalizerNDaContinuationBonus
                    }
                    // かな て(接続助詞・補助動詞)は連用形接続(定数コメント参照)。
                    if node.reading.first == "て", node.surface == node.reading,
                        !node.isInflectionDerived,
                        !prevNode.isInflectionDerived,
                        !prevNode.isDictionaryFormPredicate,
                        let derivedForExtendedSpan =
                            inflectedSurfacesBySpan["\(prevNode.start)-\(prevNode.end + 1)"],
                        containsKanji(prevNode.surface),
                        !derivedForExtendedSpan.contains(prevNode.surface + "て") {
                        cost += Self.multiClauseKanaTeAfterNonPredicatePenalty
                    }
                    // 複合動詞の前部要素(連用形)+動詞(定数コメント参照)。取り/撮り忘れている を
                    // 鳥忘れている に勝たせる。
                    if compoundVerbRenyouNodeKeys.contains("\(prevNode.start)-\(prevNode.end)-\(prevNode.surface)"),
                        node.isInflectionDerived || node.isDictionaryFormPredicate {
                        cost -= Self.multiClauseCompoundVerbRenyouBonus
                    }
                    // 格助詞 に 直後のカ変(来る)活用は移動の到着点用法で最頻(職場に来て/こっちに来た)。
                    // 同読みの一段 着る はを格が普通(服を着て)なので、に 直後に限り来る側を押し上げる。
                    // カ変明示供給ノード(kuru map 一致)に限定し、来手 等の辞書同音や 行/言(いって)には
                    // 触れない。上に着て(重ね着)は稀用法として許容する。連用形+に(飲みに)の直後にも
                    // 等しく与え、のみ+に+来た が 飲みに+来た を新ボーナス差で逆転しないようにする。
                    if (prevNode.surface == "に" && prevNode.reading == "に")
                        || renyouNiNodeKeys.contains("\(prevNode.start)-\(prevNode.end)-\(prevNode.surface)"),
                        node.isInflectionDerived,
                        Self.multiClauseKuruFormSurfaces[node.reading] == node.surface {
                        cost -= Self.multiClauseNiKuruArrivalBonus
                    }
                    // 同音異義 あう の出し分け(best-effort): 現ノードが あう活用(会う/合う)で
                    // 直前が「に」なら、その前の名詞の人物性で優先を決める。人物→会う、
                    // それ以外→合う。非優先側の表層に減点(前の名詞は backPointer で辿る)。
                    if let auKanji = Self.auVerbLeadingKanji(of: node.surface),
                        Self.multiClauseAuVerbReadings.contains(node.reading),
                        prevNode.reading == "に" || prevNode.reading == "が" {
                        let nounIsPerson: Bool
                        if backPointer[prevIdx] >= 0 {
                            nounIsPerson = Self.isPersonLikeNounSurface(nodes[backPointer[prevIdx]].surface)
                        } else {
                            nounIsPerson = false
                        }
                        // 人物なら 合(=非会)に減点、非人物なら 会 に減点。
                        if nounIsPerson, auKanji == "合" {
                            cost += Self.multiClauseAuPersonMismatchPenalty
                        } else if !nounIsPerson, auKanji == "会" {
                            cost += Self.multiClauseAuPersonMismatchPenalty
                        }
                    }
                    // 敬称 さん/さま は数字の後以外では 山/三/桟 等の漢字接尾にならない。
                    // 名前+さん(かな敬称)を優先するため漢字表層に減点(数字直後は免除)。
                    // 例外: 地域接尾(県/道/府/都 等)直後の 産 は産地表記(愛知県産)なので
                    // 減点せず、逆に かな敬称(愛知県さん)より優先するボーナスを与える(2410)。
                    if Self.multiClauseHonorificSuffixReadings.contains(node.reading),
                        containsKanji(node.surface),
                        !Self.isNumericContextForHonorific(prevSurface: prevNode.surface, prevReading: prevNode.reading) {
                        if node.surface == "産",
                            let prevLast = prevNode.surface.last,
                            KanaKanjiConverter.regionalSuffixCharactersBeforeSan.contains(prevLast) {
                            cost -= Self.multiClauseRegionalProduceBonus
                        } else {
                            cost += Self.multiClauseHonorificKanjiPenalty
                        }
                    }
                    // 地域接尾(県/道/府/都/市 等)直後の 人(じん) は住人表記(京都人/大阪人)。
                    // 人(にん/じん) は読み跨ぎ借用の遮断で unigram+床評価になり、同音の
                    // 陣/尽/腎 等に負けるため、産 と同じボーナスで是正する(2434)
                    if node.reading == "じん", node.surface == "人",
                        let prevLastForJin = prevNode.surface.last,
                        KanaKanjiConverter.regionalSuffixCharactersBeforeSan.contains(prevLastForJin) {
                        cost -= Self.multiClauseRegionalProduceBonus
                    }
                    // 述語(活用派生/辞書形)直後の かち は「〜する価値ない」等の形式名詞的
                    // 用法が主。短span床の僅差(価値7191 vs 勝6795)で 勝/勝ち に負けるため
                    // 価値 にボーナス(行く価値ないね 対策。2434)
                    // 連体の の 直後の いち は 位置 が主(定数コメント参照。2525)
                    if node.reading == "いち", node.surface == "位置",
                        prevNode.surface == "の" {
                        cost -= Self.multiClauseNoIchiPositionBonus
                    }
                    if node.reading == "かち", node.surface == "価値",
                        prevNode.isInflectionDerived || prevNode.isDictionaryFormPredicate {
                        cost -= Self.multiClausePredicateKachiValueBonus
                    }
                    // 文末の終助詞「な」直前が非述語(地名/名詞)なら減点(三田な を避け 見た+な を優先)。
                    // 助詞(から/まで 等)直後の な は正当(遅いからな)なので免除する。
                    if node.end == n,
                        node.reading == "な",
                        node.surface == "な",
                        !Self.isPredicateLikePrevForConditional(prevNode),
                        !Self.multiClauseCaseParticleSurfaces.contains(prevNode.surface) {
                        cost += Self.multiClauseSentenceFinalNaAfterNounPenalty
                    }
                    // 述語直後の 人(にん/じん) は文法として接続しない(定数コメント参照)。
                    if node.surface == "人",
                        Self.multiClausePersonSuffixSinoReadings.contains(node.reading),
                        Self.isPredicateLikePrevForConditional(prevNode) {
                        cost += Self.multiClauseForbiddenPenaltyCost
                    }
                    // 連体詞直後の かんじ→漢字 に小減点(定数コメント参照。こんな感じ を最良に)。
                    if node.reading == "かんじ",
                        node.surface == "漢字",
                        Self.multiClauseDemonstrativeSurfaces.contains(prevNode.surface) {
                        cost += Self.multiClauseDemonstrativeKanjiPenalty
                    }
                    // 時間経過の名詞(時間/月日 等。助詞 が/も/は 任意)直後の たつ 活用は
                    // 経つ が正書。経 以外の たつ 族表層(立/建 等)に減点(あう の人物性
                    // 判定と同型。時間が経ってたら を最良に)(2408)。
                    if let tatsuKanji = Self.tatsuVerbLeadingKanji(of: node.surface),
                        tatsuKanji != "経",
                        node.reading.hasPrefix("たっ") || node.reading.hasPrefix("たつ") || node.reading.hasPrefix("たち") {
                        let nounSurface: String?
                        if prevNode.surface == "が" || prevNode.surface == "も" || prevNode.surface == "は" {
                            nounSurface = backPointer[prevIdx] >= 0 ? nodes[backPointer[prevIdx]].surface : nil
                        } else {
                            nounSurface = prevNode.surface
                        }
                        if let nounSurface, Self.multiClauseTemporalElapseNounSurfaces.contains(nounSurface) {
                            cost += Self.multiClauseAuPersonMismatchPenalty
                        }
                    }
                    if cost < best[idx] {
                        best[idx] = cost
                        backPointer[idx] = prevIdx
                    } else if cost == best[idx],
                        backPointer[idx] >= 0,
                        Self.isNonNativeScriptSurface(nodes[backPointer[idx]].surface),
                        !Self.isNonNativeScriptSurface(prevNode.surface) {
                        // 完全同コストのタイブレークは非ネイティブ表層(カタカナのみ/ラテン字のみ)
                        // でない経路を優先する。かな入力に対して同じ証拠の強さならカタカナ・
                        // ラテン字化しない方が自然(法律かえるのは: 変える経路 6024+1810 と
                        // カエル経路 6927+907 が 7834 で完全タイ → 変える を採る。かれらは:
                        // curated 彼ら/カレラ/Carrera が 1500 で完全タイ → 彼ら を採る。
                        // 従来はノード列挙順で先に処理された方が勝っていた)。
                        backPointer[idx] = prevIdx
                    }
                }
            }
        }

        // --- 5. EOS 込みで最良の終端ノードを選ぶ ---
        var bestTotal = infinity
        var bestEndIndex = -1
        // 同点タイブレーク: 文末が助詞(かな)の経路を優先する。EOS は unigram を持つため
        // 文末実績のない名詞も uni+バックオフで文を終えられ、助詞終わりと完全同点になる
        // ことがある(あめのひも: 紐+EOS と 日+も+EOS が同点で、列挙順により名詞側が
        // 勝っていた)。同点時のみの介入なので他の均衡には影響しない。
        var bestIsParticleFinal = false
        for idx in nodesEndingAt[n] {
            if best[idx] >= infinity {
                continue
            }
            var eosCost = transitionCost(
                prev: nodes[idx].surface,
                prevAuxTail: Self.auxTailForBigramBorrow(of: nodes[idx]),
                surface: Self.multiClauseEOSMarker,
                reading: "",
                isDictWord: true,
                isCurated: false,
                isInflectionDerived: false
            )
            // curated ノードは EOS 遷移を上限クランプ(定数コメント参照)。
            if nodes[idx].isCurated {
                eosCost = min(eosCost, Self.multiClauseCuratedEOSCost)
            }
            var total = best[idx] + eosCost
            // 文末終助詞クラスタの最長一致ボーナス: かなー(3字) を なー(2字) より優先する
            // (こんないろかなー→色香+なー でなく 色+かなー。文末クラスタは最長で切るのが自然)。
            // 長さ×400 の差分なので、辞書語が明確に安い場合(ばか+なー 等)は逆転しない。
            if nodes[idx].surface == nodes[idx].reading,
                Self.multiClauseFinalParticleReadings.contains(nodes[idx].reading) {
                total -= nodes[idx].reading.count * 400
            }
            // 文末が終助詞クラスタ読み(かな/かも 等)なのに漢字表層(仮名/哉/鴨)なのは不自然。
            if Self.multiClauseFinalParticleReadings.contains(nodes[idx].reading),
                nodes[idx].surface != nodes[idx].reading,
                !nodes[idx].isCurated {
                total += Self.multiClauseFinalParticleKanjiPenalty
            }
            // 文末 そう の全漢字表層(層/僧/草)への減点(定数コメント参照)。直前ノードの
            // 表層がひらがな終わり(ほとんど/たぶん/これも 等)に限定 — 漢字名詞直後は
            // 学生層/富裕層 等の生産的な複合なので減点しない(がくせいそう の防護)。
            if Self.multiClauseSentenceFinalAllKanjiPenaltyReadings.contains(nodes[idx].reading),
                KanaKanjiConverter.isAllKanjiSurface(nodes[idx].surface),
                !nodes[idx].isCurated,
                backPointer[idx] >= 0,
                let prevLast = nodes[backPointer[idx]].surface.unicodeScalars.last,
                (0x3041...0x3096).contains(prevLast.value) {
                total += Self.multiClauseFinalParticleKanjiPenalty
            }
            let isParticleFinal = nodes[idx].surface == nodes[idx].reading
                && (Self.multiClauseCaseParticleSurfaces.contains(nodes[idx].surface)
                    || Self.multiClauseFinalParticleReadings.contains(nodes[idx].reading))
            if total < bestTotal || (total == bestTotal && isParticleFinal && !bestIsParticleFinal) {
                bestTotal = total
                bestEndIndex = idx
                bestIsParticleFinal = isParticleFinal
            }
        }
        guard bestEndIndex >= 0 else {
            return []
        }

        // --- 6. バックトラック(ノード列を保持) ---
        var pathIndices: [Int] = []
        var idx = bestEndIndex
        while idx >= 0 {
            pathIndices.append(idx)
            idx = backPointer[idx]
        }
        pathIndices.reverse()
        #if DEBUG
        // 時限トレース(2642): MULTI_TRACE=1 のときだけ、全ノードの累積コストと選択経路を吐く
        if ProcessInfo.processInfo.environment["MULTI_TRACE"] != nil {
            print("MULTITRACE reading=\(normalized) bestTotal=\(bestTotal)")
            for (i, node) in nodes.enumerated() where best[i] < infinity {
                let bp = backPointer[i] >= 0 ? nodes[backPointer[i]].surface : "BOS"
                print("MULTITRACE node[\(i)] \(node.reading)→\(node.surface) cum=\(best[i]) prev=\(bp)\(pathIndices.contains(i) ? " *PATH" : "")")
            }
        }
        #endif
        guard pathIndices.count >= 2 else {
            return []   // 単文節は既存の単文節経路に任せる
        }

        var segments = pathIndices.map { nodes[$0].surface }
        // 仮定の接続助詞「なら」が述語直後で 奈良/楢/ナラ に漢字・カタカナ化した場合は
        // かな なら に是正する(買う奈良→買うなら)。連文節の best 分節は動詞を正しく取れて
        // いる(買う+奈良)ので、助詞区間の表層だけ差し替える。元の漢字版は変種に温存する。
        var conditionalNaraKanjiVariant: String? = nil
        if pathIndices.count >= 2 {
            let lastNode = nodes[pathIndices[pathIndices.count - 1]]
            let prevNode = nodes[pathIndices[pathIndices.count - 2]]
            if Self.multiClauseConditionalParticleReadings.contains(lastNode.reading),
                lastNode.surface != lastNode.reading,
                !lastNode.isCurated,
                Self.isPredicateLikePrevForConditional(prevNode) {
                conditionalNaraKanjiVariant = segments.joined()
                segments[segments.count - 1] = lastNode.reading
            }
        }

        let joined = segments.joined()
        // 全かな結果は原則返さない(素通りの丸ごとエコー防止)。ただし経路に curated ノード
        // (やって/にした 等、かなが正書として明示登録された語)を含む場合は、かな結果が
        // 正規の変換なので返す(やってそうな が候補なしになるのを防ぐ)。
        // 最良が全かなでも変種(そっちはつながる→そっちは繋がる 等の漢字混じり)は正当な
        // 変換なので捨てない — ここで即 return [] すると候補なしになる。
        // 文末が終助詞クラスタのかな表層(いるなー/だなー 等)なら、全かなでも正当な変換
        // (終助詞はかなが正書)なのでエコー抑制の対象外。抑制すると「なー→ナー にしただけ」の
        // 変種(いるナー)が最小 delta で最良に繰り上がってしまう。
        let lastNode = nodes[pathIndices[pathIndices.count - 1]]
        let lastPrevNode = pathIndices.count >= 2 ? nodes[pathIndices[pathIndices.count - 2]] : nil
        // 述語直後のかな「なら」(仮定: 買うなら/するなら)も全かなエコー抑制の対象外。
        let lastIsKanaConditionalNara = Self.multiClauseConditionalParticleReadings.contains(lastNode.reading)
            && lastNode.surface == lastNode.reading
            && (lastPrevNode.map { Self.isPredicateLikePrevForConditional($0) } ?? false)
        // 文末がかなの格助詞/複合助詞(ここでは/そこには 等の話題断片)や名詞化節
        // (ひらがなのは 等)も対象外 — これらはかなが唯一の正書で、抑制すると変種の
        // 漢字化(個々では)が最良に繰り上がってしまう。
        let lastIsKanaCaseParticle = lastNode.surface == lastNode.reading
            && (Self.multiClauseCaseParticleSurfaces.contains(lastNode.surface)
                || Self.multiClauseCompoundParticles.contains(lastNode.surface)
                || Self.multiClauseNominalizerSurfaces.contains(lastNode.surface)
                || Self.multiClauseExplanatoryFinalSurfaces.contains(lastNode.surface))
        let lastIsKanaFinalParticle = (Self.multiClauseFinalParticleReadings.contains(lastNode.reading)
            && lastNode.surface == lastNode.reading)
            || lastIsKanaConditionalNara
            || lastIsKanaCaseParticle
        // 末尾が「漢字語 + 単独の素通りかな1字(非助詞・非辞書・非活用)」は誤分割の余りモーラ
        // (学習した 酒造所(しゅぞうじょ)+ う → 酒造所う が しゅぞうじょう で最良化する等)。
        // このゴミ経路を返さず単文節(seed の 酒造場 等 丸ごと候補)に委ねる。
        // 末尾が「漢字語 + 単独バラ母音1字(あいうえお)」は余りモーラの誤分割(学習した
        // 酒造所(しゅぞうじょ)+ う → 酒造所う が しゅぞうじょう で最良化する等。う は辞書語でも
        // あるため isDictWord では弾けない)。単文節(seed の 酒造場 等 丸ごと候補)に委ねる。
        // 助詞(か/わ/の…)・助動詞(た/て/だ)は母音でないため対象外。
        if lastNode.surface == lastNode.reading,
            !lastNode.isCurated,
            Self.multiClauseDanglingVowelKana.contains(lastNode.reading),
            let prevNode = lastPrevNode,
            containsKanji(prevNode.surface) {
            return []
        }
        // 経路の全ノードが辞書語(素通り無し)の全かな=LM が変換候補の中から かな表記を
        // 選んだ結果(の+こと+です 等、かなが正書の機能語句)。素通りエコーではないので
        // 抑制しない(のことです が の事です に負けて最良を失うのを防ぐ)。
        let allNodesAreDictWords = !pathIndices.contains(where: { !nodes[$0].isDictWord })
        let suppressAllKanaBest = joined == normalized
            && !pathIndices.contains(where: { nodes[$0].isCurated })
            && !lastIsKanaFinalParticle
            && !allNodesAreDictWords
            // て/で+授受補助動詞のかな連鎖で終わる全かな(してくれないかな 等)はかなが正書。
            // b4 常設ノードが くれないかな を1スパン化すると末尾ノードの終助詞免除が
            // 外れるため、joined 全体の一般判定で免除する(keepKana 側と同じ述語)
            && !KanaKanjiConverter.hasTeBenefactiveKanaTail(normalized)

        // --- 7. Nベスト風バリアント: 最良経路の1文節だけを同区間の別表層に差し替えた変種を
        //        コスト差の小さい順に付ける。bigram が拮抗する読み(しかくとらないと→
        //        視覚/資格/四角…)で第2候補以降を提示するため。1文字区間(助詞等)は対象外。
        var variants: [(delta: Int, order: Int, joined: String)] = []
        var variantOrder = 0
        for (pos, nodeIdx) in pathIndices.enumerated() {
            let chosen = nodes[nodeIdx]
            guard chosen.reading.count >= 2 else {
                continue
            }
            let prevSurface = pos > 0 ? nodes[pathIndices[pos - 1]].surface : Self.multiClauseBOSMarker
            let nextNode: MultiClauseNode? = pos + 1 < pathIndices.count ? nodes[pathIndices[pos + 1]] : nil

            func pairCost(_ node: MultiClauseNode, asCurated: Bool = true) -> Int {
                let prevAuxTail: String? = pos > 0
                    ? Self.auxTailForBigramBorrow(of: nodes[pathIndices[pos - 1]])
                    : nil
                let prevIsDictionaryFormPredicate = pos > 0
                    ? nodes[pathIndices[pos - 1]].isDictionaryFormPredicate
                    : false
                let incoming = transitionCost(
                    prev: prevSurface,
                    prevAuxTail: prevAuxTail,
                    surface: node.surface,
                    reading: node.reading,
                    isDictWord: node.isDictWord,
                    isCurated: node.isCurated && asCurated,
                    isInflectionDerived: node.isInflectionDerived,
                    wordCost: node.wordCost,
                    isDictionaryFormPredicate: node.isDictionaryFormPredicate,
                    prevIsDictionaryFormPredicate: prevIsDictionaryFormPredicate,
                    prevIsInflectionDerived: pos > 0
                        ? nodes[pathIndices[pos - 1]].isInflectionDerived
                        : false,
                    isShortCuratedFragment: shortCuratedFragmentNodeKeys.contains("\(node.start)-\(node.end)-\(node.surface)"),
                    isCollocationPreferredKana: collocationPreferredKanaNodeKeys.contains("\(node.start)-\(node.end)-\(node.surface)"),
                    isCollocationPreferredVerb: collocationPreferredVerbNodeKeys.contains("\(node.start)-\(node.end)-\(node.surface)"),
                    scriptVariantPenalty: (scriptVariantSuppressedNodeKeys.contains("\(node.start)-\(node.end)-\(node.surface)") ? 100000
                        : (scriptVariantDemotedNodeKeys.contains("\(node.start)-\(node.end)-\(node.surface)") ? 6000 : 0))
                        + (collocationDemotedNodeKeys.contains("\(node.start)-\(node.end)-\(node.surface)")
                            ? Self.multiClauseCollocationDemotionPenalty
                            : 0)
                )
                let outgoing: Int
                if let nextNode {
                    outgoing = transitionCost(
                        prev: node.surface,
                        prevAuxTail: Self.auxTailForBigramBorrow(of: node),
                        surface: nextNode.surface,
                        reading: nextNode.reading,
                        isDictWord: nextNode.isDictWord,
                        isCurated: nextNode.isCurated,
                        isInflectionDerived: nextNode.isInflectionDerived,
                        wordCost: nextNode.wordCost,
                        isDictionaryFormPredicate: nextNode.isDictionaryFormPredicate,
                        prevIsDictionaryFormPredicate: node.isDictionaryFormPredicate,
                        prevIsInflectionDerived: node.isInflectionDerived,
                        isShortCuratedFragment: shortCuratedFragmentNodeKeys.contains("\(nextNode.start)-\(nextNode.end)-\(nextNode.surface)"),
                        isCollocationPreferredKana: collocationPreferredKanaNodeKeys.contains("\(nextNode.start)-\(nextNode.end)-\(nextNode.surface)"),
                        isCollocationPreferredVerb: collocationPreferredVerbNodeKeys.contains("\(nextNode.start)-\(nextNode.end)-\(nextNode.surface)"),
                        scriptVariantPenalty: (scriptVariantSuppressedNodeKeys.contains("\(nextNode.start)-\(nextNode.end)-\(nextNode.surface)") ? 100000
                            : (scriptVariantDemotedNodeKeys.contains("\(nextNode.start)-\(nextNode.end)-\(nextNode.surface)") ? 6000 : 0))
                            + (collocationDemotedNodeKeys.contains("\(nextNode.start)-\(nextNode.end)-\(nextNode.surface)")
                                ? Self.multiClauseCollocationDemotionPenalty
                                : 0)
                    )
                } else {
                    var eosCost = transitionCost(
                        prev: node.surface,
                        prevAuxTail: Self.auxTailForBigramBorrow(of: node),
                        surface: Self.multiClauseEOSMarker,
                        reading: "",
                        isDictWord: true,
                        isCurated: false,
                        isInflectionDerived: false
                    )
                    // curated ノードは EOS 遷移を上限クランプ(定数コメント参照)。
                    if node.isCurated {
                        eosCost = min(eosCost, Self.multiClauseCuratedEOSCost)
                    }
                    outgoing = eosCost
                }
                return incoming + outgoing
            }

            // 基準コストは curated 床(1500)を外した自然コストで取る。curated の激安を
            // 基準にすると同区間の代替(殺って 等)のコスト差が常に巨大になり、変種として
            // 表示されなくなるため(経路選択には影響しない=表示順位のみの調整)。
            let baseCost = pairCost(chosen, asCurated: false)
            // ただし curated かな識別(やってる 等、かなが正書の明示登録)の区間では、活用派生の
            // 漢字化(遣ってる/演ってる/犯ってる 等の俗字)だけ curated 床込みの実コスト差で
            // 評価する。natural 基準だと delta≈0 で他区間の正当な変種(皆やってる 等)より
            // 常に上位を占拠してしまう(2404)。単文節経路では従来どおり列挙される。
            let baseCostCurated = (chosen.isCurated && chosen.surface == chosen.reading)
                ? pairCost(chosen, asCurated: true)
                : baseCost
            for altIdx in nodesStartingAt[chosen.start] {
                let alt = nodes[altIdx]
                guard alt.end == chosen.end,
                    alt.surface != chosen.surface else {
                    continue
                }
                // 終助詞クラスタ区間の非かな表層(なー→ナー/名/菜 等)は変種として出さない
                // (終助詞はかなが正書。カタカナ・漢字化は不自然)。
                if Self.multiClauseFinalParticleReadings.contains(alt.reading),
                    alt.surface != alt.reading {
                    continue
                }
                // 敬称区間(さん/さま)の漢字表層(三/讃/様 等)も変種として出さない。
                // 数字直後(だい3 等)と地域接尾直後の 産(愛知県産)は従来どおり許す(2410)。
                if Self.multiClauseHonorificSuffixReadings.contains(alt.reading),
                    containsKanji(alt.surface),
                    !(alt.surface == "産"
                        && prevSurface.last.map(KanaKanjiConverter.regionalSuffixCharactersBeforeSan.contains) == true),
                    !Self.isNumericContextForHonorific(
                        prevSurface: prevSurface,
                        prevReading: pos > 0 ? nodes[pathIndices[pos - 1]].reading : ""
                    ) {
                    continue
                }
                // かな正書の代名詞区間で best がかなを選んでいる場合、旧表記・カタカナへの
                // 差し替え変種は出さない(定数コメント参照)。
                if Self.multiClauseKanaOrthodoxPronounReadings.contains(alt.reading),
                    chosen.surface == chosen.reading,
                    alt.surface != alt.reading {
                    continue
                }
                // 機能語(かな識別免除リスト=助詞/助動詞類)の区間で best がかなを選んで
                // いる場合、カタカナ/ラテン表層への差し替え変種は出さない。Sudachi の
                // カタカナ人名収穫(テル wc3788 等)が安く、してるなあ→しテルなあ のような
                // 人名が文中に割り込む変種を作るため。漢字表層(照る 等)は対象外のまま。
                if Self.multiClauseKanaIdentityFloorExemptReadings.contains(alt.reading),
                    chosen.surface == chosen.reading,
                    Self.isNonNativeScriptSurface(alt.surface) {
                    continue
                }
                // 連語クランプ区間(めどが立つ 等)では、非選好の漢字動詞変種
                // (経った/建った/足った)は使いものにならないので出さない。
                // かな変種(たったら)は残す(2559)。
                if collocationPreferredVerbNodeKeys.contains("\(chosen.start)-\(chosen.end)-\(chosen.surface)"),
                    !collocationPreferredVerbNodeKeys.contains("\(alt.start)-\(alt.end)-\(alt.surface)"),
                    containsKanji(alt.surface) {
                    continue
                }
                let effectiveBase = (alt.isInflectionDerived && containsKanji(alt.surface))
                    ? baseCostCurated
                    : baseCost
                let delta = pairCost(alt) - effectiveBase
                // 連語の名詞スパンの表記変種(めど/メド 等、かな識別か seed 掲載)は
                // 変種枠の主役なので delta 上限を緩和する(2559)
                let isCollocationNounScriptVariant = collocationNounSpans.contains("\(chosen.start)-\(chosen.end)")
                    && (alt.surface == alt.reading
                        || KanaKanjiSeedDictionary.seed[alt.reading]?.contains(alt.surface) == true)
                let variantMaxDelta = isCollocationNounScriptVariant
                    ? Self.multiClauseVariantMaxDelta * 2
                    : Self.multiClauseVariantMaxDelta
                var altSegments = segments
                altSegments[pos] = alt.surface
                let variantJoined = altSegments.joined()
                if variantJoined == joined {
                    continue
                }
                // 入力全体にかな正書の根拠(keepKana)がある全かな変種は delta 上限を免除
                // (かな素通りノードは意図的に高コストで、上限内に入らない。2561)
                let isSanctionedFullKanaVariant = variantJoined == normalized
                    && alt.surface == alt.reading
                    && shouldKeepKanaIdentityLeading(for: normalized)
                guard delta <= variantMaxDelta || isSanctionedFullKanaVariant else {
                    continue
                }
                // 入力そのままの全かな変種は原則捨てる(エコー防止)が、経路に curated ノード
                // を含む(やめるべし: べし が curated)か、末尾がかなの助詞/名詞化節
                // (ひらがなのは: 語幹かな差し替え+のは)なら、かな結果が正書の変換なので
                // 許す(best 経路の抑制ルールと同じ例外)。
                if variantJoined == normalized {
                    let variantHasCurated = alt.isCurated
                        || pathIndices.enumerated().contains(where: {
                            $0.offset != pos && nodes[$0.element].isCurated
                        })
                    let lastVariantNode = pos == pathIndices.count - 1
                        ? alt
                        : nodes[pathIndices[pathIndices.count - 1]]
                    let variantEndsWithKanaParticle = lastVariantNode.surface == lastVariantNode.reading
                        && (Self.multiClauseFinalParticleReadings.contains(lastVariantNode.reading)
                            || Self.multiClauseCaseParticleSurfaces.contains(lastVariantNode.surface)
                            || Self.multiClauseCompoundParticles.contains(lastVariantNode.surface)
                            || Self.multiClauseNominalizerSurfaces.contains(lastVariantNode.surface)
                            || Self.multiClauseExplanatoryFinalSurfaces.contains(lastVariantNode.surface)
                            // seed でかな先頭指定した句(ですもんね/ですかね 等)もかなが正書
                            || KanaKanjiSeedDictionary.seed[lastVariantNode.reading]?.first == lastVariantNode.reading)
                    // 入力全体にかな正書の根拠(keepKana=表示層と同じ述語)があるなら全かな
                    // 変種は正規の変換。できないですもんね は経路が丸ごと1ノードで、末尾
                    // ノード基準の例外に掛からず落ちていた(実機バーに 出来ない〜 しか
                    // 出ない。2561)
                    if !variantHasCurated && !variantEndsWithKanaParticle,
                        !shouldKeepKanaIdentityLeading(for: normalized) {
                        continue
                    }
                }
                variants.append((delta, variantOrder, variantJoined))
                variantOrder += 1
            }
        }

        // 同 delta のタイブレークはノード列挙順(=seed/base優先順)。文字コード順だと
        // 採<撮 で 採れてる が 撮れてる を不当に上回る(でとれてる→で採れてる が先)。
        variants.sort { lhs, rhs in
            lhs.delta != rhs.delta ? lhs.delta < rhs.delta : lhs.order < rhs.order
        }
        var results = suppressAllKanaBest ? [] : [joined]
        for variant in variants where !results.contains(variant.joined) {
            results.append(variant.joined)
            if results.count >= 1 + Self.multiClauseVariantLimit {
                break
            }
        }
        // かなに是正した「なら」の元の漢字版(買う奈良 等)は候補として温存する(#2以降)。
        if let kanjiVariant = conditionalNaraKanjiVariant, !results.contains(kanjiVariant) {
            results.append(kanjiVariant)
        }
        // 読み全体キーの抑制(suppr の つれていって→連れて言って 等)を結合結果にも適用する。
        // 従来はセグメント単位の直接surfaceチェックのみで、複数ノードの結合が抑制表層と
        // 一致するケースをすり抜けていた(2628)。
        if let directSuppressed = suppressedByReading[normalized], !directSuppressed.isEmpty {
            results.removeAll { directSuppressed.contains($0) }
        }
        // 旧仮名遣い(ゐゑヰヱ 等)の抑制は単文節と同じく連文節にも適用する(ぐらゐかなー 等)。
        return filterHistoricalKanaSurfaceCandidates(for: normalized, candidates: results)
    }

    // 仮定「なら」の直前が述語(動詞辞書形/形容詞/タ形、または活用派生)か。
    // 述語+なら=かな正書(買うなら)、体言+と+奈良=地名 の区別に使う。
    static func isPredicateLikePrevForConditional(_ prev: MultiClauseNode) -> Bool {
        if prev.isInflectionDerived {
            return true
        }
        return prev.surface.last.map { multiClausePredicateTailCharacters.contains($0) } ?? false
    }

    // 語形(かな・漢字・ラテン字を含む)か。絵文字/記号のみなら false。curated 優遇の対象判定に使う。
    static func isWordLikeSurface(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if (0x3041...0x3096).contains(value)      // ひらがな
                || (0x30A1...0x30FA).contains(value)  // カタカナ
                || value == 0x30FC                    // 長音符
                || (0x4E00...0x9FFF).contains(value)  // CJK 統合漢字
                || (0x3400...0x4DBF).contains(value)  // CJK 拡張A
                || (0x0041...0x005A).contains(value)  // A-Z
                || (0x0061...0x007A).contains(value) { // a-z
                return true
            }
        }
        return false
    }

    // タイブレーク用: カタカナのみ、またはラテン字のみの表層(かな入力に対する
    // 非ネイティブ表記)。同コストならこれらでない表層(漢字/かな)を優先する。
    static func isNonNativeScriptSurface(_ text: String) -> Bool {
        if isKatakanaString(text) {
            return true
        }
        guard !text.isEmpty else {
            return false
        }
        return text.unicodeScalars.allSatisfy { scalar in
            (0x0041...0x005A).contains(scalar.value)
                || (0x0061...0x007A).contains(scalar.value)
        }
    }

    static func isKatakanaString(_ text: String) -> Bool {
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

    func readingLooksLikeLoanword(_ reading: String) -> Bool {
        for character in reading where Self.multiClauseLoanwordMarkers.contains(character) {
            return true
        }
        return false
    }
}
