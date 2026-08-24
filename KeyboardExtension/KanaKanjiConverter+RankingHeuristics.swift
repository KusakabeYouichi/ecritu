import Foundation

// ランキング補正群: 活用形・命令形/意志形・来る・スクリプト種・単漢字seed・数値単位の
// 各ブーストとスコア加算の共通ヘルパ。candidates() のスコア確定段から呼ばれる。
extension KanaKanjiConverter {
    static let kuruKanjiCandidateBoost = 1450

    static let godanImperativeCandidateBoost = 320

    static let godanVolitionalCandidateBoost = 320

    // 注意: normalizedReading が数字を除去するため、この関数の hasLeadingNumberPrefix 判定は
    // candidates() 経由では発火しない(実効は candidates() 最終段の digitContext ブースト側)。
    static let numericUnitFallbackCandidateBoost = 320

    // 連濁助数詞複合の昇格幅。算用(400)→1300、漢数字(360)→1260 で辞書(1200)を超え、
    // 追加語彙(2400)/学習語彙(2280)には届かない = ユーザ意図は常に優先される。
    static let voicedCounterNumericCompoundBoost = 900

    static let numericCounterCompoundCandidateBoost = 360

    static let sameReadingPureKatakanaPenalty = 128

    static let seedLeadingKanjiCandidateBoost = 1600

    static let seedSingleKanjiPriorityBaseBoost = 220

    static let seedSingleKanjiPriorityStep = 12
    static let seedOrderedKanjiCompoundStep = 40

    func addCandidates(
        _ candidates: [String],
        baseScore: Int,
        to scores: inout [String: Int]
    ) {
        for (index, candidate) in uniqueCandidates(from: candidates).enumerated() {
            scores[candidate, default: 0] += max(1, baseScore - index)
        }
    }

    func applyLearning(
        _ learningScoresForReading: [String: Int],
        to scores: inout [String: Int]
    ) {
        for (candidate, count) in learningScoresForReading {
            scores[candidate, default: 0] += count * 64
        }
    }

    func applySameReadingScriptPreference(
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

        // かな識別が同読みグループ内で LM 優位(ここ4556 vs 個々/ココ…)なら、
        // グループ首位へ引き上げる(此処/個々 等の辞書順よりかな正書を優先)。
        // 今日(LM優位)vs きょう のような漢字正書の読みでは発火しない。
        if let identityScore = scores[reading] {
            // グループは辞書の同読みリスト全体(systemCandidates)で組む。表層から読みを
            // 判定するかな/カタカナ限定だと、成る程 のような漢字表記が比較対象から漏れて
            // boost がタイ止まりになり、タイブレーク(短い方優先)で漢字が勝ってしまう。
            // seed 宣言のある読みで かな が seed 非掲載なら、人手の並び宣言を尊重して
            // かな識別を同読みグループ末尾へ降格する(あきの: 辞書にかな人名収穫があり
            // 識別供給と二重加算されて#4へ浮上していた。しない/ただの/どうだ 等かなを
            // 出したい読みは seed にかなを掲載済みなので発火しない)。
            let seedDeclared = KanaKanjiSeedDictionary.seed[reading]
            let kanaSkippedBySeed = seedDeclared != nil && !(seedDeclared?.contains(reading) ?? false)
            // 派生読み(とっていて 等)は、基底 seed がかな非掲載(とる {取る,…})なら
            // 同じ人手宣言としてかな識別を全候補の末尾へ降格する。辞書直候補ゼロの
            // 派生専用読みなので systemCandidates 基準では others が空になり、
            // 全 scores 基準で降格する(かな とって+いて の quickPostfix 合成(1120)が
            // 活用チャネル(980)より高スコアで先頭化していた。2644)
            // 降格先は「最上位の直下」: 先頭は譲るがかなは2位に残す(知って/しって の
            // 既存期待と両立。末尾送りは しって の退行になった)
            if seedDeclared == nil, derivationBaseSeedSkipsKanaLead(for: reading) {
                let allOthers = scores.keys.filter { $0 != reading }
                if let top = allOthers.compactMap({ scores[$0] }).max() {
                    scores[reading] = min(identityScore, top - 1)
                }
            }
            let others = uniqueCandidates(from: systemCandidates).filter { $0 != reading }
            if kanaSkippedBySeed {
                let otherScores = others.compactMap { scores[$0] }
                if let lowest = otherScores.min() {
                    scores[reading] = min(identityScore, lowest - 1)
                }
            } else if !others.isEmpty, isLMKanaPreferred(reading: reading, among: others),
                !derivationBaseSeedSkipsKanaLead(for: reading) {
                let maxOther = others.map { scores[$0, default: 0] }.max() ?? 0
                scores[reading] = max(identityScore, maxOther + 1)
            }
        }

        // 保護カタカナ(辞書先頭からカタカナが連なる=外来語・固有名: アメリカ/セミナー/
        // コーヒー 等)がある読みでは、かな識別をその直下に降格する(2645)。かな識別の
        // エコーが79読みで外来語カタカナを差し置いて先頭化していた(せみなー 型の一般是正)。
        // かな正書の読み(やっぱり 等)は辞書先頭がかななので保護カタカナが空=不発。
        // seed 宣言のある読みは人手の並び(まま/たい 等)に任せる。
        if let identityScore = scores[reading],
            KanaKanjiSeedDictionary.seed[reading] == nil {
            let protectedScores = protectedKatakanaCandidates.compactMap { scores[$0] }
            if let topProtected = protectedScores.max(), identityScore >= topProtected {
                scores[reading] = topProtected - 1
            }
        }

        // かな識別(読みそのもの)が居る場合、非保護カタカナは「かなの直後」に置く
        // (やっぱり→ヤッパリ の順。従来の lowest-1 だと当て字群より下に沈みすぎる)。
        let kanaIdentityScore = scores[reading]

        for candidate in matchingCandidates where Self.isPureKatakanaCandidate(candidate) {
            if protectedKatakanaCandidates.contains(candidate) {
                continue
            }

            if let kanaIdentityScore {
                scores[candidate] = min(scores[candidate, default: 0], kanaIdentityScore - 1)
            } else {
                let penalizedScore = scores[candidate, default: 0] - Self.sameReadingPureKatakanaPenalty
                scores[candidate] = min(penalizedScore, lowestNonKatakanaScore - 1)
            }
        }
    }

    // 派生読み(とっていて 等)のかな首位化の抑止判定(2644): 派生の基底読みの seed が
    // かな非掲載(=漢字正書の人手宣言。とる {取る,…} 等)なら、corpus 優位のかな識別が
    // 派生形で先頭化するのを防ぐ。基底 seed にかなを掲載した族(ある/うまい 等)は不発。
    func derivationBaseSeedSkipsKanaLead(for reading: String) -> Bool {
        for rule in Self.allInflectionRules {
            guard let stem = removingSuffix(reading, suffix: rule.readingSuffix),
                !stem.isEmpty else {
                continue
            }
            let base = stem + rule.baseReadingSuffix
            if let seedOrder = KanaKanjiSeedDictionary.seed[base], !seedOrder.contains(base) {
                return true
            }
        }
        return false
    }

    // コピュラ だ の活用尾。keepKana(だ剥がし)で使う。長い方を先にマッチさせる
    // (だった を だ+った と誤剥がししない)。エンジン側は合成経由で既にかな最良を
    // 選べている(そうだった 等)ため昇格はせず、提示層の先頭維持だけを担う。
    static let copulaDaTails: [String] = ["だったら", "だった", "だって", "だし", "だ"]

    // 同読みグループ内で「かな表記が LM 優位」か(ここ4556 vs 個々/ココ、やる vs 殺る 等)。
    // LM 未収録は +∞ 扱い。かな首位化(1908)と活用基底の並び(かいてある対策)で共用する。
    func isLMKanaPreferred(reading: String, among others: [String]) -> Bool {
        guard !others.isEmpty else {
            return true
        }
        let costs = store.wordLMUnigramCosts(for: [reading] + others)
        guard let kanaCost = costs[reading] else {
            return false
        }
        return others.allSatisfy { (costs[$0] ?? Int.max) > kanaCost }
    }

    // 派生基底のLM優位昇格の例外読み(ユーザレビュー 2639: 現状の辞書順が正)。
    // 商談/閉廷/棲息/沈澱 が先頭のままで良い(LM最良の 昇段/平定/生息/沈殿 を上げない)
    static let derivationLMPromotionDeniedReadings: Set<String> = [
        "ちんでん", "しょうだん", "へいてい", "せいそく"
    ]

    // 派生(活用基底・postfix語幹)の候補並びを整える(かいてある対策の一般化):
    // (1) seed の並び(書く/描く…)を先頭へ — 派生が正書から出るように。
    // (2) 生の辞書順が LM 実勢と大きく乖離している読みは LM 最良の辞書語を先頭へ
    //     (2545 の派生版: 出演しちゃう が 出捐しちゃう の下に沈む型の構造対応。
    //     スイープ真性90件の一掃。ガードは 2545 と同じ gap/主読み/ユーザ矯正済み除外。2639)
    // (3) かな識別(候補==読み)は LM 優位なら先頭へ(ある/やる 等)、劣位で先頭に居る
    //     場合は末尾へ(かく 等)。生の辞書順は 書く rank15・有る先頭 等の歪みがある。
    func orderedDerivationBaseCandidates(_ candidates: [String], reading: String) -> [String] {
        var ordered = candidates
        if let seedOrder = KanaKanjiSeedDictionary.seed[reading] {
            let seedSet = Set(seedOrder)
            let seeded = seedOrder.filter { ordered.contains($0) }
            ordered = seeded + ordered.filter { !seedSet.contains($0) }
        } else if !Self.derivationLMPromotionDeniedReadings.contains(reading),
            store.userDictionary()[reading] == nil,
            store.learnedDictionary()[reading] == nil,
            let currentFirst = ordered.first {
            let kanjiCandidates = ordered.filter { $0 != reading && Self.containsKanjiCandidate($0) }
            let costs = store.wordLMUnigramCosts(for: kanjiCandidates)
            if let best = kanjiCandidates.min(by: { (costs[$0] ?? Int.max) < (costs[$1] ?? Int.max) }),
                let bestUni = costs[best],
                best != currentFirst,
                (costs[currentFirst] ?? Int.max) - bestUni >= Self.lmDominantDictBoostMinGap {
                // 読み跨ぎの誤昇格防止(2545と同じ主読みガード。word_cost 記録なしは主読み扱い)
                let isMainReading: Bool
                if let wc = store.wordCosts(for: reading)[best],
                    let minWc = store.candidateMinWordCosts(for: [best])[best] {
                    isMainReading = wc - minWc <= Self.lmDominantDictBoostMaxReadingGap
                } else {
                    isMainReading = true
                }
                if isMainReading {
                    ordered.removeAll { $0 == best }
                    ordered.insert(best, at: 0)
                }
            }
        }
        guard ordered.contains(reading) else {
            return ordered
        }
        // seed のある読みは人手の並びが最終決定(2644)。かな識別の LM 昇格が seed の
        // 漢字先頭を覆す(とる: かな とる が corpus 優位で、seed {取る,…} を差し置いて
        // とっていて 等の派生でかなが先頭化)のを防ぐ。かな先頭にしたい読みは seed の
        // 先頭にかなを書けばよい(うまい 等の既存流儀)。
        if KanaKanjiSeedDictionary.seed[reading] != nil {
            return ordered
        }
        let others = ordered.filter { $0 != reading }
        guard !others.isEmpty else {
            return ordered
        }
        if isLMKanaPreferred(reading: reading, among: others) {
            return [reading] + others
        }
        if ordered.first == reading {
            return others + [reading]
        }
        return ordered
    }

    func preferredLeadingKatakanaCandidates(
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

        // LM(コーパス)でかな表記が優位な語(やっぱり: かな6438/カタカナ未収録)は
        // native のかなが正書なので、辞書先頭がカタカナでも保護しない。
        // 外来語(パン/アンケート等)はカタカナ側が LM 優位なので保護が維持される。
        if !protectedCandidates.isEmpty {
            let costs = store.wordLMUnigramCosts(for: [reading] + Array(protectedCandidates))
            if let kanaCost = costs[reading],
                protectedCandidates.allSatisfy({ (costs[$0] ?? Int.max) > kanaCost }) {
                return []
            }
        }

        return protectedCandidates
    }

    // 地域接尾(県/道/府/都/市/町/村/州/郡/国)で終わる語幹+産(産地表記)は、敬称さん
    // 合成(愛知県さん=bfsPostfix 1040)より優先する(愛知県産/北海道産 等。2410)。
    // 人名(田中さん)は語幹末尾が地域接尾でないため対象外。
    static let regionalSuffixCharactersBeforeSan: Set<Character> = [
        "県", "道", "府", "都", "市", "町", "村", "州", "郡", "国"
    ]
    static let regionalProduceBoost = 200

    func applyRegionalProduceBoost(
        for reading: String,
        to scores: inout [String: Int]
    ) {
        guard reading.hasSuffix("さん") else {
            return
        }
        for candidate in scores.keys
        where candidate.count >= 3 && candidate.hasSuffix("産") {
            let beforeSan = candidate[candidate.index(candidate.endIndex, offsetBy: -2)]
            if Self.regionalSuffixCharactersBeforeSan.contains(beforeSan) {
                scores[candidate, default: 0] += Self.regionalProduceBoost
            }
        }
    }

    func applySeedSingleKanjiPriorityBoost(
        for reading: String,
        to scores: inout [String: Int]
    ) {
        guard let seedCandidates = KanaKanjiSeedDictionary.seed[reading],
            !seedCandidates.isEmpty else {
            return
        }

        for (index, candidate) in uniqueCandidates(from: seedCandidates).enumerated() {
            // seed 先頭は最強ブースト。かな正書の seed(これ/それ/あなた 等、先頭がかな)でも
            // 先頭を持ち上げる。以前は index0 が漢字の時だけで、先頭かな+2番目漢字の seed
            // (これ:[これ,此れ])だと 2番目の熟語ブーストに先頭かなが逆転されていた。
            if index == 0 {
                scores[candidate, default: 0] += Self.seedLeadingKanjiCandidateBoost
            }

            if Self.isSingleKanjiCandidate(candidate) {
                let boost = max(
                    24,
                    Self.seedSingleKanjiPriorityBaseBoost - (index * Self.seedSingleKanjiPriorityStep)
                )
                scores[candidate, default: 0] += boost
            } else if index > 0,
                Self.containsKanjiCandidate(candidate) || candidate == reading
                    || KanaKanjiConverter.hiraganizedKanaOnlySurface(candidate) == reading {
                // 複数字の熟語 seed(高校/孝行, 描く 等)を seed 順で辞書ベースの上へ。
                // 先頭は上の leading ブーストで既に持ち上がるため index>0 のみ対象。
                // SudachiDict の rank で「々」形容動詞群が頻出熟語を埋める歪みを是正する。
                // 非漢字(カタカナ/かな語)への一般拡張は 山田>やまだ 等の序列を崩すため
                // 不採用(2098で検証済み)だが、かな識別(候補==読み)と seed 掲載の
                // カタカナ識別(オス/メス 等=ひらがな化が読みと一致する人手選別)は対象 —
                // 元クラス抑制対象のカタカナは素点が最下位級で、seed 再割当(持ち点の
                // 並べ替え)だけでは浮上できない。
                let boost = max(
                    200,
                    Self.seedLeadingKanjiCandidateBoost - (index * Self.seedOrderedKanjiCompoundStep)
                )
                scores[candidate, default: 0] += boost
            }
        }
    }

    // seed 掲載語同士の相対順を seed 順に固定する(スコア値の集合はそのままに再割当)。
    // ブースト絶対量の調整では、かな識別が別経路の加点(識別ボーナス等)を拾って seed
    // 先頭(平仮名)を追い越したり、合成の二重加点(平がな=辞書+postfix)に届かなかったり、
    // 読みごとに過不足が変わって安定しない。順序だけを保証すれば非 seed 候補との相対
    // 位置は保たれる。学習済み候補は除外(学習 > seed の序列を維持)。
    func applySeedOrderNormalization(
        for reading: String,
        learningScoresForReading: [String: Int],
        to scores: inout [String: Int]
    ) {
        guard let seedCandidates = KanaKanjiSeedDictionary.seed[reading] else {
            return
        }
        let present = uniqueCandidates(from: seedCandidates).filter {
            scores[$0] != nil && learningScoresForReading[$0] == nil
        }
        guard present.count >= 2 else {
            return
        }
        let values = present.compactMap { scores[$0] }.sorted(by: >)
        for (index, candidate) in present.enumerated() {
            scores[candidate] = values[index]
        }
    }

    func applyInflectionRankingHeuristics(
        for reading: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode,
        systemCandidates: [String],
        inflectionDerivedCandidates: Set<String>,
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
            applyGodanVolitionalBoost(
                for: reading,
                userDictionary: userDictionary,
                initialUserDictionary: initialUserDictionary,
                systemCandidateMode: systemCandidateMode,
                to: &scores
            )
            applyStativeSouBoost(
                for: reading,
                inflectionDerivedCandidates: inflectionDerivedCandidates,
                to: &scores
            )
            applyAdjectiveSaBoost(
                for: reading,
                inflectionDerivedCandidates: inflectionDerivedCandidates,
                to: &scores
            )
            return
        }

        let trustedDirectCandidates = Set(systemCandidates.prefix(3))

        for candidate in Array(scores.keys) {
            var delta = 0

            if inflectionDerivedCandidates.contains(candidate) {
                // 正規の活用形(書かない/食べない 等)は、語幹+ない の分解ゴミ(呵々ない/田部ない)
                // や辞書の別候補より確実に上位へ。postfix(1120)+語尾(220) を超える強めのブースト。
                delta += 500
            } else if hasMatchingInflectionRankingSuffix(candidate, readingSuffix: matchedSuffix) {
                // 読み全体が1語として辞書に実在する suffix 一致語(少ない/危ない 等)は、
                // 派生の +500(酸くない/漉くない)に逆転されないよう同等のブーストを与える。
                // かな識別(すくない 等)は 220 のままにして辞書順(漢字先頭)を保つ。
                if candidate != reading, systemCandidates.contains(candidate) {
                    delta += 500
                } else {
                    delta += 220
                }
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
        applyGodanVolitionalBoost(
            for: reading,
            userDictionary: userDictionary,
            initialUserDictionary: initialUserDictionary,
            systemCandidateMode: systemCandidateMode,
            to: &scores
        )
    }

    // 様態そう(連用形+そう=「買いそう/降りそう/来そう」looks like ~ing)は活用派生スコア
    // (980)のまま辞書名詞群に沈み候補に出ない。控えめなブーストで top 圏へ出す(名詞を
    // 完全に押しのけない中庸値。#1 独占ではなく「出てくる」ことを狙う)。読み末尾が
    // 様態そう系のときだけ、そう系で終わる活用派生候補に加点する。
    static let stativeSouBoost = 220
    static let multiClauseStativeSouReadingSuffixes = ["そうです", "そうだ", "そうな", "そうに", "そうで", "そう"]
    func applyStativeSouBoost(
        for reading: String,
        inflectionDerivedCandidates: Set<String>,
        to scores: inout [String: Int]
    ) {
        guard let suffix = Self.multiClauseStativeSouReadingSuffixes.first(where: { reading.hasSuffix($0) }),
            reading.count > suffix.count else {
            return
        }
        for candidate in inflectionDerivedCandidates where candidate.hasSuffix(suffix) {
            // かな識別(買いそう が かな のまま=かいそう)は素通りと同じなので対象外。
            guard candidate != reading, containsKanji(candidate) else {
                continue
            }
            scores[candidate, default: 0] += Self.stativeSouBoost
        }
    }

    // 形容詞の さ 名詞化(辛い→辛さ)。Sudachi は「形容詞+さ」を生産的な派生として扱い、
    // core_lex 86万行のうち さ で終わる名詞は40件しかない(寒さ/暑さ/高さ/長さ 等の慣用形のみ)。
    // そのため 辛さ/甘さ/苦さ/弱さ/優しさ は辞書に存在せず活用派生(980)でしか出ない一方、
    // 終助詞さ の postfix 素通り(1120)が から+さ を全候補に付けるため、レア人名(嘉良さ/迦羅さ/
    // 佳羅さ…)が20件並んで 辛さ を押し下げる。読み末尾が さ で、語幹+い が adjective-i と
    // して実在するときだけ、その派生候補を辞書語と同じ 1200 相当まで持ち上げる。
    // ゲートを「候補の語幹+い が adjective-i」に置くことで、五段サ行の未然形(話す→話さ)や
    // 単なる名詞は対象外になる。
    // LM 圧倒的最良の辞書候補を rank0 の上へ出す一般機構(2544)のゲート値。
    // 一括スイープ(tools/audit_lm_rank_mismatch.py)で、常用語(行動/思想/更新/解放 等
    // 1218読み)がレア語の辞書 rank 順に埋もれたままと判明した。従来は げんかい/いがい/
    // いしょく 等を1件ずつ seed 矯正していた氷山の一角問題の構造対応。
    // - 最良候補の unigram がこの値以下(=会話でも使う常用語)
    static let lmDominantDictBoostMaxBestUnigram = 6800
    // - rank0 の unigram との差がこの値以上(または rank0 が LM 未収録)
    static let lmDominantDictBoostMinGap = 1200
    // - 読み跨ぎの誤昇格(宇宙=たかおき 等)を防ぐ: この読みの word_cost が
    //   表層の全読み最安からこの値以内(=主読み)であること
    static let lmDominantDictBoostMaxReadingGap = 500
    static let adjectiveSaBoost = 220
    // 形容動詞さ名詞化のブースト。語幹の word_cost 差(検挙6498 vs 謙虚7798 等)を
    // 跨いで非文法のサ変名詞+さ を確実に下へ送る(い形の220は同族間の並び用で小さい)。
    static let naAdjectiveSaBoost = 600
    // LM 圧倒的最良の辞書候補を rank0 の上へ(ゲート定数のコメント参照)。
    // 辞書層(1200)内での並び替えなので、curated(2400)/学習(2280)のユーザー明示矯正には
    // 勝たない。seed 掲載読みは人手の並び指定を尊重して対象外。かな識別は既存の
    // かな首位化(applySameReadingScriptPreference)が担当するため対象外。
    func applyLMDominantDictCandidateBoost(
        for reading: String,
        systemCandidates: [String],
        to scores: inout [String: Int]
    ) {
        guard reading.count >= 2,
            systemCandidates.count >= 2,
            KanaKanjiSeedDictionary.seed[reading] == nil else {
            return
        }

        let rank0 = systemCandidates[0]
        let unigrams = store.wordLMUnigramCosts(for: systemCandidates)
        var best: (surface: String, uni: Int)?
        for candidate in systemCandidates where candidate != reading {
            guard let uni = unigrams[candidate] else { continue }
            if best == nil || uni < best!.uni {
                best = (candidate, uni)
            }
        }
        guard let best,
            best.surface != rank0,
            best.uni <= Self.lmDominantDictBoostMaxBestUnigram else {
            return
        }
        if let rank0Uni = unigrams[rank0],
            rank0Uni - best.uni < Self.lmDominantDictBoostMinGap {
            return
        }
        // 読み跨ぎの誤昇格(宇宙=たかおき 等、別読みの主表層が LM を持ち込む)を防ぐ:
        // この読みの word_cost が表層の全読み最安に近い(=主読み)場合だけ昇格する。
        // word_cost 記録なし(こうげん の 光源 型=データ欠落)は主読みとみなす。
        if let wc = store.wordCosts(for: reading)[best.surface],
            let minWc = store.candidateMinWordCosts(for: [best.surface])[best.surface],
            wc - minWc > Self.lmDominantDictBoostMaxReadingGap {
            return
        }

        // アンカーは rank0 でなく辞書候補群の現最高スコア(rank0 が調整で2位以下に居る
        // 読み=こうしん の 香信 等でも、確実に辞書層の先頭へ出すため)。
        let dictTop = systemCandidates.compactMap { scores[$0] }.max() ?? 0
        let target = dictTop + 40
        if scores[best.surface, default: 0] < target {
            scores[best.surface] = target
        }
    }

    // 「単漢字+ない」の素通り合成断片(件ない/券ない/千ない 等)が複数チャネルの累積で
    // 読み全体の辞書語(県内 uni5537/圏内)を追い越す構造の是正(2618)。
    // 断片は「辞書に無い 1漢字+ない」に限定 — 切ない/危ない は辞書掲載なので対象外、
    // 濃くない 等の活用合成(語幹2字以上)も対象外。LM unigram 実在の辞書語だけを
    // 断片群の直上へ持ち上げる(相対順は維持)。せんない の 詮ない(1699)のような
    // 高スコアの正当語は跨がない(断片 top 基準の底上げのみ)。
    func applyDictOverNaiFragmentBoost(
        for reading: String,
        systemCandidates: [String],
        to scores: inout [String: Int]
    ) {
        guard reading.count >= 3, reading.hasSuffix("ない"),
            !systemCandidates.isEmpty else {
            return
        }
        let dictSet = Set(systemCandidates)
        // 断片クラスタ: 辞書非掲載の「1文字(かな以外)+ない」
        var fragmentTop = 0
        for (candidate, score) in scores where candidate.count == 3 && candidate.hasSuffix("ない") {
            guard !dictSet.contains(candidate),
                let head = candidate.first,
                !("ぁ"..."ん").contains(head), !("ァ"..."ヶ").contains(head) else {
                continue
            }
            fragmentTop = max(fragmentTop, score)
        }
        guard fragmentTop > 0 else {
            return
        }
        // LM unigram 実在の辞書語(読み全体が1語)を、断片群の直上へ。相対順維持のため
        // 上位から降順の下駄を履かせる。既に断片より上の語(線内 2495 等)は触らない
        let unigrams = store.wordLMUnigramCosts(for: systemCandidates)
        let lifted = systemCandidates.filter { unigrams[$0] != nil && $0 != reading }
        for (index, candidate) in lifted.enumerated() {
            let target = fragmentTop + 40 + (lifted.count - index)
            if scores[candidate, default: 0] < target {
                scores[candidate] = target
            }
        }
    }

    // 「多字語+末尾1かな」の素通り合成断片(実業か/演算し 等)が読み全体の
    // 辞書語(実業家/演算子)を追い越す構造の是正(2637、〜家問題の一般対応)。
    // applyDictOverNaiFragmentBoost の同型で、断片は「辞書非掲載の 漢字含み+読み末尾の
    // 1かな」に限定。対象末尾は か/し のみ(scoped): だ/は/が は 来たんだ/夏は 等の
    // 正当な助詞・縮約合成が同じ形になり、レア辞書語(木反田/夏羽)の誤昇格を招くため
    // 対象外(全スイートで実証済み)。だ/は 系の実害読みは seed で個別是正する。
    // 持ち上げは LM unigram 実在の辞書語を先(相対順維持)、次いでその他の辞書候補
    // (実業科/実業課 等のレア複合)— 断片より辞書語が下に居る状態だけを直す。
    static let tailKanaFragmentBoostTails: Set<Character> = ["か", "し"]

    func applyDictOverTailKanaFragmentBoost(
        for reading: String,
        systemCandidates: [String],
        to scores: inout [String: Int]
    ) {
        guard reading.count >= 3,
            let tail = reading.last,
            Self.tailKanaFragmentBoostTails.contains(tail),
            !systemCandidates.isEmpty else {
            return
        }
        let dictSet = Set(systemCandidates)
        // 断片クラスタ: 辞書非掲載の「漢字含み(2文字以上)+末尾1かな」
        var fragmentTop = 0
        for (candidate, score) in scores where candidate.count >= 3 && candidate.last == tail {
            guard !dictSet.contains(candidate) else { continue }
            let stem = String(candidate.dropLast())
            guard Self.containsKanjiCandidate(stem) else { continue }
            fragmentTop = max(fragmentTop, score)
        }
        guard fragmentTop > 0 else {
            return
        }
        let unigrams = store.wordLMUnigramCosts(for: systemCandidates)
        let lmBacked = systemCandidates.filter { unigrams[$0] != nil && $0 != reading }
        let others = systemCandidates.filter { unigrams[$0] == nil && $0 != reading }
        let lifted = lmBacked + others
        for (index, candidate) in lifted.enumerated() {
            let target = fragmentTop + 40 + (lifted.count - index)
            if scores[candidate, default: 0] < target {
                scores[candidate] = target
            }
        }
    }

    func applyAdjectiveSaBoost(
        for reading: String,
        inflectionDerivedCandidates: Set<String>,
        to scores: inout [String: Int]
    ) {
        guard reading.count >= 3, reading.hasSuffix("さ") else {
            return
        }

        var boosted = false

        // い形容詞の連用さ名詞化(辛さ/弱さ 等)。
        let adjectiveReading = String(reading.dropLast()) + "い"
        let adjectiveClassMap = store.systemInflectionMetadata(for: adjectiveReading).classMap
        if !adjectiveClassMap.isEmpty {
            for candidate in inflectionDerivedCandidates where candidate.hasSuffix("さ") {
                // かな識別(からさ のまま)は素通りと同じなので対象外。
                guard candidate != reading, containsKanji(candidate) else {
                    continue
                }
                let adjectiveCandidate = String(candidate.dropLast()) + "い"
                guard adjectiveClassMap[adjectiveCandidate] == InflectionClass.adjectiveI else {
                    continue
                }
                scores[candidate, default: 0] += Self.adjectiveSaBoost
                boosted = true
            }
        }

        // 形容動詞語幹+さ(謙虚さ/便利さ)。い形容詞と違い活用メタデータでは判定できない
        // ため、連文節の様態そうクランプと同じ prev→な の bigram 実績ゲート(2120)で
        // 形容動詞性を判定する。サ変名詞+さ(検挙さ 等の非文法)は な が続かないので
        // 昇格せず沈む(けんきょさ→検挙さ 対策。2543)。
        let stemReading = String(reading.dropLast())
        let kanjiStems = systemCandidates(for: stemReading, mode: .lesDeux).filter { containsKanji($0) }
        if !kanjiStems.isEmpty {
            let naCosts = store.wordLMBigramCosts(for: kanjiStems.map { ($0, "な") })
            for stem in kanjiStems {
                let candidate = stem + "さ"
                guard let naCost = naCosts["\(stem)\tな"],
                    naCost <= KanaKanjiConverter.multiClauseNaAdjectiveBigramThreshold,
                    scores[candidate] != nil else {
                    continue
                }
                scores[candidate, default: 0] += Self.naAdjectiveSaBoost
                boosted = true
            }
        }

        // かな識別(からさ)は末尾へ。から は LM で 嘉良/唐 等より低コスト(2848)なため派生の
        // 基底として最優先され、からさ が先頭に居座る。さ 名詞化が成立する読みでは かな は
        // 求められないので、他候補の最小点より下へ落として末尾に置く(消さずに残す)。
        guard boosted, scores[reading] != nil else {
            return
        }
        let otherScores = scores.filter { $0.key != reading }.values
        if let minimum = otherScores.min() {
            scores[reading] = minimum - 1
        }
    }

    func hasMatchingInflectionRankingSuffix(
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

    func applyNumericUnitFallbackPriorityBoost(
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

    // 連濁・促音便形の助数詞読み(ぼん/ぽん/びき/ぴき/ぷん/ぱつ/ぱい)+数詞 の複合を辞書級へ。
    // 連濁形は数詞に付いた時にしか現れない(単独で ぼん と読む助数詞は無い)ので、同読みの
    // レア辞書語(さんぼん の 三盆/山本/上鳳)より 3本/三本 を上に置ける。清音形(ほん/ひき)は
    // にほん→日本 のような一般語と衝突するため対象にしない(算用優先の並びは基礎点差で維持)。
    func applyVoicedCounterNumericCompoundBoost(
        for reading: String,
        candidates: [String],
        to scores: inout [String: Int]
    ) {
        guard !candidates.isEmpty, Self.hasVoicedCounterSuffixReading(reading) else {
            return
        }
        for candidate in candidates {
            scores[candidate, default: 0] += Self.voicedCounterNumericCompoundBoost
        }
    }

    // 読みが「数詞+連濁/促音便形の助数詞」か。清音形も助数詞マップに在ることを条件にして、
    // 濁点付きの一般語(ぶん=分 等、清音側に助数詞が無い読み)を巻き込まない。
    static func hasVoicedCounterSuffixReading(_ reading: String) -> Bool {
        for counterReading in numericCounterSuffixCandidatesByReading.keys
        where reading.count > counterReading.count && reading.hasSuffix(counterReading) {
            guard let first = counterReading.first,
                let devoiced = rendakuDevoicedKanaCharacter[first] else {
                continue
            }
            let devoicedReading = String(devoiced) + counterReading.dropFirst()
            guard numericCounterSuffixCandidatesByReading[devoicedReading] != nil else {
                continue
            }
            let numberReading = String(reading.dropLast(counterReading.count))
            if japaneseNumberReadingValue(numberReading) != nil {
                return true
            }
        }
        return false
    }

    func hasLeadingNumberPrefix(in text: String) -> Bool {
        let trimmed = trimmingLeadingNumberPrefix(from: text)
        return !trimmed.isEmpty && trimmed != text
    }

    func applyGodanImperativeBoost(
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

    // 五段の意志形(行こう/書こう/読もう…=oForm+う)は活用ゴミではなく実在動詞の派生。
    // 「いこう→意向/移行/以降…」のような同音異義の名詞群(辞書1200)に埋もれて最下位に
    // 落ちるのを防ぐため、基本形(行く 等)が辞書にあることを確認したうえでブーストする。
    // 一段/カ変/サ変の意志形(よう/こよう/しよう)は inflectionRankingSuffixes 側で +500 され
    // るため対象外。ここは godan(oForm≠よ)専用。
    func applyGodanVolitionalBoost(
        for reading: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode,
        to scores: inout [String: Int]
    ) {
        for pattern in Self.godanPatterns {
            let volitionalEnding = pattern.oForm + "う"

            guard reading.hasSuffix(volitionalEnding),
                let stem = removingSuffix(reading, suffix: volitionalEnding) else {
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

            // サ変名詞の五段化(解す=解する/会す=会する 等)の意向形はまれ。真正五段(話す→
            // 話そう)だけを優先したいので、基底の語幹がサ変名詞(〜する が成立)の時は
            // 意向ブーストを外す(かいそう→解そう/会そう/介そう が名詞・様態を押しのける対策)。
            let stemIsSahenNoun: Bool = {
                guard pattern.dictionaryEnding == "す" else { return false }
                let suruReading = stem + "する"
                let suruCandidates = candidatesForReading(
                    suruReading,
                    userDictionary: userDictionary,
                    initialUserDictionary: initialUserDictionary,
                    systemCandidateMode: systemCandidateMode
                )
                return !suruCandidates.isEmpty
            }()

            for candidate in Array(scores.keys) where candidate.hasSuffix(volitionalEnding) {
                let candidateStem = String(candidate.dropLast(volitionalEnding.count))
                let baseCandidate = candidateStem + pattern.dictionaryEnding

                guard baseCandidates.contains(baseCandidate) else {
                    continue
                }
                // サ変名詞語幹(解/会/介)+する が成立し、その漢字語幹の場合は五段化意向の
                // ブーストを外す(解そう 等)。真正五段(話す)の 話そう は suruReading=はなする が
                // 成立しないので従来どおりブーストされる。
                if stemIsSahenNoun, containsKanji(candidateStem) {
                    continue
                }

                scores[candidate, default: 0] += Self.godanVolitionalCandidateBoost
            }
        }
    }

    func applyKuruCandidateBoost(
        for reading: String,
        to scores: inout [String: Int]
    ) {
        for form in Self.kuruInflectionForms where reading.hasSuffix(form.readingSuffix) {
            for candidate in Array(scores.keys) where candidate.hasSuffix(form.kanjiOutputSuffix) {
                scores[candidate, default: 0] += Self.kuruKanjiCandidateBoost
            }
        }
    }

    func matchingInflectionRankingSuffix(for reading: String) -> String? {
        for suffix in Self.inflectionRankingSuffixes where reading.hasSuffix(suffix) {
            return suffix
        }

        return nil
    }
}
