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

    func derivedCandidates(
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

        var baseCandidates = candidatesForReading(
            baseReading,
            userDictionary: userDictionary,
            initialUserDictionary: initialUserDictionary,
            systemCandidateMode: systemCandidateMode
        )

        guard !baseCandidates.isEmpty else {
            return []
        }

        // 基底候補の並びを整える(seed順+かな識別のLM昇格/降格。postfix語幹と共通ヘルパ)。
        baseCandidates = orderedDerivationBaseCandidates(baseCandidates, reading: baseReading)

        let metadata = inflectionMetadata(for: baseReading)
        // 追加語彙(void.plist 等=initialUserDictionary)も手動追加と同様にサ変推論の対象に
        // 含める。以前は「本当の手動追加分のみ」に絞っていたが、まかいぞうしてる→魔改造してる
        // のような void 由来サ変名詞の活用が導出できず、し→市 等の誤分割だけが残っていた。
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

            guard let inflectionClass,
                rule.allowedClasses.contains(inflectionClass) else {
                continue
            }

            let stem = String(candidate.dropLast(matchedSuffix.count))
            results.append(stem + rule.outputCandidateSuffix)
        }

        return results
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

        // Keep inference only as fallback for user dictionary entries.
        guard !hasSystemMetadata || userCandidateSet.contains(candidate) else {
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
