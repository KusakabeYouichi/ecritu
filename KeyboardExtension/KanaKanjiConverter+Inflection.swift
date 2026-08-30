import Foundation

// 活用派生: 活用ルール適用(inflectionCandidates/derivedCandidates)と活用クラス解決
// (サ変/一段推定・ガル形・行く不規則)。
extension KanaKanjiConverter {
    static let mixedScriptSahenOptInReadings: Set<String> = [
        "ねおち"
    ]

    static let sahenPhraseParticleSuffixes: [String] = [
        "には", "では", "とは", "へは",
        "が", "を", "に", "で", "と", "へ", "は", "も", "の", "や"
    ]

    static let godanRuKanjiSuffixOverrides: [String] = [
        "入る",
        "減る"
    ]

    static let iVowelKanaBeforeRu: Set<Character> = [
        "い", "き", "ぎ", "し", "じ", "ち", "ぢ", "に", "ひ", "び", "ぴ", "み", "り", "ゐ"
    ]

    static let eVowelKanaBeforeRu: Set<Character> = [
        "え", "け", "げ", "せ", "ぜ", "て", "で", "ね", "へ", "べ", "ぺ", "め", "れ", "ゑ"
    ]

    func inflectionCandidates(
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

        // 基底読み族のopt-in昇格(おく/はる 等 multiClauseInflectionFamilyPreferenceBaseReadings)。
        // ルール定義順だと同形の別族(おいた=老いる系>置く系)が先行するため、指定族の
        // ブロックを行く不規則の直後・他ルールの前へ(族内の並びは維持)。
        // おいた/おいてある 等の単文節順に効く(2434)
        var preferredDerived: [String] = []
        var otherDerived: [String] = []
        // 基底読みの漢字表層がすべて収穫底値(wc>=10000)のレア動詞族(あやまつ→過つ 10750 等)は、
        // ルール定義順(godanPatterns の つ が る より先)で常用族(あやまる→謝る/誤る)より前に出て
        // あやまった→過った/あやまっている→過っている になっていた。族ごと後方へ(2731)。
        // 常用表層を1つでも持つ読み(える=選る 10096/得る)は対象外
        var rareBaseDerived: [String] = []
        for rule in Self.allInflectionRules {
            let items = derivedCandidates(
                for: reading,
                rule: rule,
                userDictionary: userDictionary,
                initialUserDictionary: initialUserDictionary,
                systemCandidateMode: systemCandidateMode
            ).items
            guard !items.isEmpty else {
                continue
            }
            let baseReading = removingSuffix(reading, suffix: rule.readingSuffix)
                .map { $0 + rule.baseReadingSuffix } ?? ""
            let baseCosts = store.wordCosts(for: baseReading)
            let kanjiBaseCosts = baseCosts.filter { $0.key != baseReading }
            let isRareBaseReading = !kanjiBaseCosts.isEmpty
                && kanjiBaseCosts.values.allSatisfy { $0 >= CandidateScore.harvestTierWordCostFloor }
            if KanaKanjiConverter.multiClauseInflectionFamilyPreferenceBaseReadings.contains(baseReading) {
                // かな識別は昇格させない(先頭に乗ると b2 の「かなは先頭のときだけ供給」を
                // 誤発動させ、はったら のかなが 貼ったら を抑えてしまう)。かなの扱いは
                // 従来位置(other側)のまま既存規則に委ねる
                preferredDerived.append(contentsOf: items.filter { $0 != reading })
                otherDerived.append(contentsOf: items.filter { $0 == reading })
            } else if isRareBaseReading {
                rareBaseDerived.append(contentsOf: items)
            } else {
                otherDerived.append(contentsOf: items)
            }
        }
        derived.append(contentsOf: preferredDerived)
        derived.append(contentsOf: otherDerived)
        derived.append(contentsOf: rareBaseDerived)

        return Array(uniqueCandidates(from: derived).prefix(limit))
    }

    // 基底読み族(=活用ルール)単位のグループ列。並びは inflectionCandidates と同一
    // (行く不規則→ルール定義順、族内は orderedDerivationBaseCandidates の seed/辞書順)で、
    // 族をまたぐ重複は先着に寄せる。連文節 b2 の「未代表族の追加供給」(はったら=はう系が
    // TopK を占有して はる系(貼った/張った)が供給されない、基底読み間順序の5例目)にだけ
    // 使う — 単文節の並び(既存の語別調整が乗っている)には影響させない(2423)。
    func inflectionCandidateFamilies(
        for reading: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode,
        perFamilyLimit: Int
    ) -> [(items: [String], familyKey: Int, baseReading: String)] {
        guard reading.count >= 2, perFamilyLimit > 0 else {
            return []
        }
        var families: [(items: [String], familyKey: Int, baseReading: String)] = []
        var seen = Set<String>()

        let iku = deriveIkuIrregularCandidates(
            for: reading,
            userDictionary: userDictionary,
            initialUserDictionary: initialUserDictionary,
            systemCandidateMode: systemCandidateMode
        ).filter { seen.insert($0).inserted }
        if !iku.isEmpty {
            // 行く不規則は LM 代表値を 行く の unigram で測る
            let ikuKey = store.wordLMUnigramCosts(for: ["行く"])["行く"] ?? Int.max
            families.append((items: Array(iku.prefix(perFamilyLimit)), familyKey: ikuKey, baseReading: "いく"))
        }

        for rule in Self.allInflectionRules {
            let (rawItems, familyKey) = derivedCandidates(
                for: reading,
                rule: rule,
                userDictionary: userDictionary,
                initialUserDictionary: initialUserDictionary,
                systemCandidateMode: systemCandidateMode
            )
            // かな識別は除外(b2b の追加供給はかなを扱わないため、枠(perFamilyLimit)を
            // かなが潰して 貼ったら が切られるのを防ぐ)
            let items = rawItems.filter { $0 != reading && seen.insert($0).inserted }
            if !items.isEmpty {
                let baseReading = removingSuffix(reading, suffix: rule.readingSuffix)
                    .map { $0 + rule.baseReadingSuffix } ?? ""
                families.append((
                    items: Array(items.prefix(perFamilyLimit)),
                    familyKey: familyKey,
                    baseReading: baseReading
                ))
            }
        }
        return families
    }

    func adjectiveGaruCandidates(
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

    func deriveIkuIrregularCandidates(
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

    // 戻り値の familyKey = 実際に派生へ寄与した基底表層の LM unigram 最小値(かな識別も
    // 寄与すれば含む)。連文節 b2b の「未代表族の追加供給」の優劣ゲートにだけ使う。
    // 関西弁・口語の否定縮約(する→せん 系)。文語サ変ゲート(derivedCandidates)で参照
    static let kansaiContractionReadingSuffixes: Set<String> = ["せん", "せんかった", "せんかったら", "せんで"]
    // 関西弁の否定縮約(ん/んかった/んかったら、サ変 せん系)の全読み接尾辞。稀な読みの動詞には組まない
    // ゲート(derivedCandidates)で参照する。ユーザ指摘(2721): 選る/彫る(える)の 選らん/彫らん は
    // 書き言葉で使わず、えらん 等で常用語(選ぶ)の候補列を汚すだけ。知る/分かる 等の常用動詞は残す
    static let kansaiNegativeContractionSuffixes: Set<String> = {
        var set = kansaiContractionReadingSuffixes
        for pattern in godanPatterns {
            for tail in ["ん", "んかった", "んかったら"] {
                set.insert(pattern.aForm + tail)
            }
        }
        return set
    }()

    // ウ音便の五段う動詞(促音便形 った/って を作らず、うた/うて が正)。
    // 現代語で頻出の 問う/請う/乞う を中心に、辞書に載る同型のみ
    static let uOnbinGodanUSurfaces: Set<String> = ["問う", "請う", "乞う", "訪う", "厭う", "恋う"]

    func derivedCandidates(
        for reading: String,
        rule: InflectionRule,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> (items: [String], familyKey: Int) {
        // 空の readingSuffix は「読み全体が語幹」を意味する(一段の連用形: たべ→食べる の 食べ)。
        // removingSuffix は空文字を弾くのでここで分ける(2026-08-27)
        let readingStem: String
        if rule.readingSuffix.isEmpty {
            // 一段の連用形は opt-in の基底読みだけ(全一段に開くと 溜め/占め 等が
            // 既存の並びを崩す。ため→為 が 溜め に、買い占めよね が 買いしめよね に退行した)
            guard Self.ichidanRenyouNounBaseReadings.contains(reading + rule.baseReadingSuffix) else {
                return ([], Int.max)
            }
            readingStem = reading
        } else if let stem = removingSuffix(reading, suffix: rule.readingSuffix) {
            readingStem = stem
        } else {
            return ([], Int.max)
        }

        if readingStem.isEmpty,
            !Self.emptyStemAllowedBaseReadingSuffixes.contains(rule.baseReadingSuffix) {
            return ([], Int.max)
        }

        let baseReading = readingStem + rule.baseReadingSuffix
        // 一段命令形(ろ/よ)の除外(2026-08-27): 居ろ/射ろ 等は同音語(色/意呂)を跨ぐ実害が
        // 命令形の利便を上回る
        if (rule.readingSuffix == "ろ" || rule.readingSuffix == "よ"),
            rule.baseReadingSuffix == "る",
            Self.ichidanImperativeDeniedBaseReadings.contains(baseReading) {
            return ([], Int.max)
        }

        // 関西弁の否定縮約は、この読みでは稀な動詞(word_cost が収穫底値 10000 以上:
        // える→選る 10096 / 彫る 11052。知る 7155 / 分かる 6927 は常用)には組まない(2721)
        let isKansaiNegativeContraction = Self.kansaiNegativeContractionSuffixes.contains(rule.readingSuffix)
        let baseWordCostsForKansaiGate = isKansaiNegativeContraction ? store.wordCosts(for: baseReading) : [:]
        var baseCandidates = candidatesForReading(
            baseReading,
            userDictionary: userDictionary,
            initialUserDictionary: initialUserDictionary,
            systemCandidateMode: systemCandidateMode
        ).filter {
            // カタカナ強調の語幹(ウマい 等)は合成前に弾く(postfix 語幹と同じ判定。2402)
            !isKatakanaEmphasisBaseCandidate($0, reading: baseReading)
                // 連濁収穫の動詞基底(どる→取る 等)も派生させない(定義コメント参照。2419)
                && !isRendakuHarvestVerbBase($0, baseReading: baseReading)
                // 稀な読みの動詞には関西弁縮約を組まない(上の定義コメント参照。2721)
                && !(isKansaiNegativeContraction
                    && (baseWordCostsForKansaiGate[$0] ?? 0) >= CandidateScore.harvestTierWordCostFloor)
                // 関西弁縮約(せん/せんで 等)は文語調の漢語一字サ変(有する/科する/幽する)とは
                // 組まない — ゆうせんで→有せんで が 優先で を乗っ取っていた(2614)。
                // 勉強する 等の語幹2字以上はそのまま(掃除せんで は自然な口語)
                && !(Self.kansaiContractionReadingSuffixes.contains(rule.readingSuffix)
                    && rule.baseReadingSuffix == "する"
                    && $0.hasSuffix("する") && $0.count == 3
                    && ($0.first.map { !("ぁ"..."ん").contains($0) && !("ァ"..."ヶ").contains($0) } ?? false))
        }

        guard !baseCandidates.isEmpty else {
            return ([], Int.max)
        }

        // 基底候補の並びを整える(seed順+かな識別のLM昇格/降格。postfix語幹と共通ヘルパ)。
        baseCandidates = orderedDerivationBaseCandidates(baseCandidates, reading: baseReading)

        let metadata = inflectionMetadata(for: baseReading)
        // 追加語彙(sacoche/misc.plist 等=initialUserDictionary)も手動追加と同様にサ変推論の対象に
        // 含める。以前は「本当の手動追加分のみ」に絞っていたが、まかいぞうしてる→魔改造してる
        // のような追加語彙由来サ変名詞の活用が導出できず、し→市 等の誤分割だけが残っていた。
        // 暴発は inferredSahen 側のゲート(isLikelySahenPhraseStem 等)で抑えられており、
        // そもそも該当読み(Xしてる)を打った時しか発動しない。
        let initialCandidatesForBase = Set(initialUserDictionary[baseReading] ?? [])
        let initialOrUserCandidateSet = Set(
            combinedUserCandidates(
                for: baseReading,
                userDictionary: userDictionary
            )
        ).union(initialCandidatesForBase)
        let userOwnCandidateSet = initialOrUserCandidateSet
        var results: [String] = []
        var contributingBases: [String] = []

        for candidate in baseCandidates {
            guard let matchedSuffix = rule.firstBaseCandidateSuffix(where: { candidate.hasSuffix($0) }) else {
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

            // 補助クラス(いる=一段 等、sqlite が1クラスしか持てない同表記多クラス語の補完)
            // も許可判定に含める。
            let supplementaryClasses = Self.supplementaryInflectionClassesByReading[baseReading]?[candidate] ?? []
            guard let inflectionClass,
                rule.allowedClasses.contains(className: inflectionClass)
                    || rule.allowedClasses.intersects(classNames: supplementaryClasses) else {
                continue
            }

            // い形容詞「いい」は語幹活用しない(連用・過去は よ- 系: よく/よかった)。
            // いい 基底からの派生(良く/善く(いく)、良かった(いかった) 等の非標準形)は
            // 作らない — いくかちないね に 善く勝ないね が混ざる誤供給の一般対策(2434)
            if baseReading == "いい", inflectionClass == InflectionClass.adjectiveI {
                continue
            }
            // 得る/獲る の うる 読みは文語(現代語は える)。一段として登録されているため語幹「う」
            // から 得てる/獲てる/得て のような現代語では使わない活用が作られ、うてる→打てる を
            // 押し下げていた(いい 基底の除外と同型の一般対策。2494)。
            // える 読みの 得る/獲る は無傷なので 得られる/得ています 等は従来どおり作れる。
            if baseReading == "うる", inflectionClass == InflectionClass.ichidan {
                continue
            }
            // ウ音便動詞(問う/請う/乞う/訪う/厭う/恋う)は促音便形を作らない。
            // 正しくは 問うた/問うて(ウ音便)で、godan-u の機械適用が 問った/問って を
            // 誤生成し とった/とって系の上位に紛れ込んでいた(ユーザ報告 2643)
            if inflectionClass == InflectionClass.godanU,
                rule.outputCandidateSuffix.hasPrefix("っ"),
                Self.uOnbinGodanUSurfaces.contains(candidate) {
                continue
            }

            let stem = String(candidate.dropLast(matchedSuffix.count))
            results.append(stem + rule.outputCandidateSuffix)
            contributingBases.append(candidate)
        }

        // サ変名詞の派生順を辞書形(基底+する)の LM 頻度で揃える(2731)。基底名詞の順(てき: 的/敵/適)は
        // 名詞としての頻度で、サ変としての頻度(適する 6641 は LM 既知、敵する は未収録)と食い違う。
        // てきする は 適する の unigram で 適 が先頭になるのに てきしている/てきした は 敵 先頭だった。
        // 辞書形の unigram を持つ基底を安い順に前へ、持たない基底とかな識別は従来順のまま後ろに。
        // seed のある基底読みは人手の並びを優先して触らない
        // する単独動詞の規則群(基底読み Xする、基底候補 適する/敵する)と、サ変名詞の規則群(基底読み X、
        // 基底候補 適/敵)の両方に効かせる(定義順で前者が先に並び、先着 dedupe で順が決まる)
        // 文語サ変(基底 Xす: 敵す/適す、五段サ行の規則)も同じ語なので 現代語の Xする の頻度で並べる。
        // 定義順では五段サ行の規則(した/す)が する の規則より先に並び、てきした→敵した が先着していた
        let isSuruDictionaryFormBase = rule.baseReadingSuffix == "する"
        let isClassicalSuBase = rule.baseReadingSuffix == "す"
        // seed の有無は名詞語幹(なんとか)でも見る: する単独動詞群の基底読み(なんとかする)には seed が無いため、
        // 名詞側の seed(なんとか→かな先頭)を無視して 何とかしろ が先頭になっていた(2739)
        let sahenNounReading: String = isSuruDictionaryFormBase ? String(baseReading.dropLast(2))
            : (isClassicalSuBase && baseReading.hasSuffix("す") ? String(baseReading.dropLast()) : baseReading)
        if rule.baseReadingSuffix.isEmpty || isSuruDictionaryFormBase || isClassicalSuBase,
            isClassicalSuBase || rule.allowedClasses.contains(className: InflectionClass.suru),
            results.count >= 2,
            KanaKanjiSeedDictionary.seed[baseReading] == nil,
            KanaKanjiSeedDictionary.seed[sahenNounReading] == nil {
            func dictionaryForm(_ base: String) -> String {
                if isSuruDictionaryFormBase { return base }
                if isClassicalSuBase { return base.hasSuffix("す") ? String(base.dropLast()) + "する" : base }
                return base + "する"
            }
            let dictionaryForms = contributingBases.filter { $0 != baseReading }.map(dictionaryForm)
            let unigramCosts = store.wordLMUnigramCosts(for: dictionaryForms)
            var known: [(cost: Int, index: Int)] = []
            var others: [Int] = []
            for (index, base) in contributingBases.enumerated() {
                if base != baseReading, let cost = unigramCosts[dictionaryForm(base)] {
                    known.append((cost, index))
                } else {
                    others.append(index)
                }
            }
            if !known.isEmpty {
                let order = known.sorted { $0.cost != $1.cost ? $0.cost < $1.cost : $0.index < $1.index }.map(\.index) + others
                if order != Array(results.indices) {
                    results = order.map { results[$0] }
                    contributingBases = order.map { contributingBases[$0] }
                }
            }
        }

        // 文語サ変(基底 Xす)の派生順は、対応する Xする の seed に従わせる(2740)。そうしちゃう は す 群(奏す/そうす)が
        // する 群(seed: そうする/奏する)より先に走って 奏しちゃう が先着していた
        if isClassicalSuBase, results.count >= 2,
            let suruSeed = KanaKanjiSeedDictionary.seed[sahenNounReading + "する"] {
            func seedIndex(_ base: String) -> Int {
                guard base.hasSuffix("す") else { return Int.max }
                return suruSeed.firstIndex(of: String(base.dropLast()) + "する") ?? Int.max
            }
            let order = contributingBases.indices.sorted { lhs, rhs in
                let li = seedIndex(contributingBases[lhs]), ri = seedIndex(contributingBases[rhs])
                return li != ri ? li < ri : lhs < rhs
            }
            if order != Array(results.indices) {
                results = order.map { results[$0] }
                contributingBases = order.map { contributingBases[$0] }
            }
        }

        let familyKey = contributingBases.isEmpty
            ? Int.max
            : (store.wordLMUnigramCosts(for: contributingBases).values.min() ?? Int.max)
        return (results, familyKey)
    }

    func inflectionMetadata(for reading: String) -> (classMap: [String: String], hasMetadata: Bool) {
        store.systemInflectionMetadata(for: reading)
    }

    func adjectiveGaruMetadata(
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

    func resolvedInflectionClass(
        for candidate: String,
        baseReading: String,
        systemClassMap: [String: String],
        hasSystemMetadata: Bool,
        userCandidateSet: Set<String>
    ) -> String? {
        if let inflectionClass = systemClassMap[candidate] {
            return inflectionClass
        }

        // クラス推論はユーザ追加/追加語彙の救済用に留める。システム辞書候補に推論を許すと
        // 「その読みの用言が実在しない」読みで誤活用が生まれる — かわう(カワウ/河鵜/河う)の
        // 河う を五段う動詞と推論して 河って/河ってきて を作り、変わってきてる を逆転していた
        // (音の借用による誤活用の温床)。inflection_classes テーブルを持つ辞書では、読みに行が
        // 無いこと自体が「この読みの用言は無い」証拠なので推論しない(2465)。
        _ = hasSystemMetadata
        guard userCandidateSet.contains(candidate) || !store.hasSystemInflectionMetadataTable else {
            return nil
        }

        return inferredInflectionClass(for: candidate, baseReading: baseReading)
    }

    func inferredSahenInflectionClass(
        for candidate: String,
        baseReading: String,
        rule: InflectionRule,
        userCandidateSet: Set<String>
    ) -> String? {
        guard rule.baseReadingSuffix.isEmpty,
            rule.allowedClasses == .suru,
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

    func isLikelySahenPhraseStem(_ candidate: String) -> Bool {
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

    func inferredExplicitSuruInflectionClass(
        for candidate: String,
        rule: InflectionRule
    ) -> String? {
        guard rule.allowedClasses.contains(.suru),
            candidate.hasSuffix("する") else {
            return nil
        }

        return InflectionClass.suru
    }

    func inferredInflectionClass(for candidate: String, baseReading: String) -> String? {
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
                // く 終わりは い形容詞の連用形収穫(多く/近く/早く 等、クラス無しエントリ)と
                // 衝突する。同語幹の い形(おおい→多い)が adjective-i で実在するなら連用形と
                // みなし、五段く動詞の推論をしない(多く→多いた 型の非文法合成の温床)。
                if pattern.dictionaryEnding == "く" {
                    let adjectiveReading = String(baseReading.dropLast()) + "い"
                    let adjectiveCandidate = String(candidate.dropLast()) + "い"
                    let adjectiveClassMap = store.systemInflectionMetadata(for: adjectiveReading).classMap
                    if adjectiveClassMap[adjectiveCandidate] == InflectionClass.adjectiveI {
                        return nil
                    }
                }
                return pattern.inflectionClass
            }
        }

        if baseReading.hasSuffix("い") && candidate.hasSuffix("い") {
            return InflectionClass.adjectiveI
        }

        return nil
    }

    func isLikelyIchidanBaseReading(_ reading: String) -> Bool {
        guard reading.hasSuffix("る"),
                reading.count >= 2 else {
            return false
        }

        let chars = Array(reading)
        let preRu = chars[chars.count - 2]

        return Self.iVowelKanaBeforeRu.contains(preRu)
            || Self.eVowelKanaBeforeRu.contains(preRu)
    }
}
