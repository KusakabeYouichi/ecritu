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
            if KanaKanjiConverter.multiClauseInflectionFamilyPreferenceBaseReadings.contains(baseReading) {
                // かな識別は昇格させない(先頭に乗ると b2 の「かなは先頭のときだけ供給」を
                // 誤発動させ、はったら のかなが 貼ったら を抑えてしまう)。かなの扱いは
                // 従来位置(other側)のまま既存規則に委ねる
                preferredDerived.append(contentsOf: items.filter { $0 != reading })
                otherDerived.append(contentsOf: items.filter { $0 == reading })
            } else {
                otherDerived.append(contentsOf: items)
            }
        }
        derived.append(contentsOf: preferredDerived)
        derived.append(contentsOf: otherDerived)

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
    func derivedCandidates(
        for reading: String,
        rule: InflectionRule,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> (items: [String], familyKey: Int) {
        guard let readingStem = removingSuffix(reading, suffix: rule.readingSuffix) else {
            return ([], Int.max)
        }

        if readingStem.isEmpty,
            !Self.emptyStemAllowedBaseReadingSuffixes.contains(rule.baseReadingSuffix) {
            return ([], Int.max)
        }

        let baseReading = readingStem + rule.baseReadingSuffix

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

            // 補助クラス(いる=一段 等、sqlite が1クラスしか持てない同表記多クラス語の補完)
            // も許可判定に含める。
            let supplementaryClasses = Self.supplementaryInflectionClassesByReading[baseReading]?[candidate] ?? []
            guard let inflectionClass,
                rule.allowedClasses.contains(inflectionClass)
                    || !rule.allowedClasses.isDisjoint(with: supplementaryClasses) else {
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

            let stem = String(candidate.dropLast(matchedSuffix.count))
            results.append(stem + rule.outputCandidateSuffix)
            contributingBases.append(candidate)
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
        guard rule.allowedClasses.contains(InflectionClass.suru),
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
