import Foundation

final class KanaKanjiConverter {
    private struct CandidateCacheKey: Hashable {
        let reading: String
        let limit: Int
        let modeRawValue: String
    }

    private enum InflectionClass {
        static let adjectiveI = "adjective-i"
        static let ichidan = "ichidan"
        static let godanU = "godan-u"
        static let godanKu = "godan-ku"
        static let godanGu = "godan-gu"
        static let godanSu = "godan-su"
        static let godanTsu = "godan-tsu"
        static let godanNu = "godan-nu"
        static let godanBu = "godan-bu"
        static let godanMu = "godan-mu"
        static let godanRu = "godan-ru"
        static let suru = "suru"
        static let kuru = "kuru"
    }

    private struct InflectionRule {
        let readingSuffix: String
        let baseReadingSuffix: String
        let baseCandidateSuffixes: [String]
        let outputCandidateSuffix: String
        let allowedClasses: Set<String>

        init(
            readingSuffix: String,
            baseReadingSuffix: String,
            baseCandidateSuffixes: [String]? = nil,
            outputCandidateSuffix: String? = nil,
            allowedClasses: Set<String>
        ) {
            self.readingSuffix = readingSuffix
            self.baseReadingSuffix = baseReadingSuffix
            self.baseCandidateSuffixes = baseCandidateSuffixes ?? [baseReadingSuffix]
            self.outputCandidateSuffix = outputCandidateSuffix ?? readingSuffix
            self.allowedClasses = allowedClasses
        }
    }

    private struct GodanPattern {
        let dictionaryEnding: String
        let inflectionClass: String
        let aForm: String
        let iForm: String
        let eForm: String
        let oForm: String
        let teForm: String
        let taForm: String
    }

    private static let adjectiveInflectionRules: [InflectionRule] = [
        InflectionRule(readingSuffix: "くない", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなかった", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "かった", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くて", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "ければ", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "く", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "さ", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI])
    ]

    private static let ichidanInflectionRules: [InflectionRule] = [
        InflectionRule(readingSuffix: "ない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "なかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ます", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ました", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ません", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たい", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たくない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "て", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "た", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "よう", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "れば", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "られる", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "られない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "させる", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "させない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "させられる", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "させられない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan])
    ]

    private static let godanPatterns: [GodanPattern] = [
        GodanPattern(dictionaryEnding: "う", inflectionClass: InflectionClass.godanU, aForm: "わ", iForm: "い", eForm: "え", oForm: "お", teForm: "って", taForm: "った"),
        GodanPattern(dictionaryEnding: "く", inflectionClass: InflectionClass.godanKu, aForm: "か", iForm: "き", eForm: "け", oForm: "こ", teForm: "いて", taForm: "いた"),
        GodanPattern(dictionaryEnding: "ぐ", inflectionClass: InflectionClass.godanGu, aForm: "が", iForm: "ぎ", eForm: "げ", oForm: "ご", teForm: "いで", taForm: "いだ"),
        GodanPattern(dictionaryEnding: "す", inflectionClass: InflectionClass.godanSu, aForm: "さ", iForm: "し", eForm: "せ", oForm: "そ", teForm: "して", taForm: "した"),
        GodanPattern(dictionaryEnding: "つ", inflectionClass: InflectionClass.godanTsu, aForm: "た", iForm: "ち", eForm: "て", oForm: "と", teForm: "って", taForm: "った"),
        GodanPattern(dictionaryEnding: "ぬ", inflectionClass: InflectionClass.godanNu, aForm: "な", iForm: "に", eForm: "ね", oForm: "の", teForm: "んで", taForm: "んだ"),
        GodanPattern(dictionaryEnding: "ぶ", inflectionClass: InflectionClass.godanBu, aForm: "ば", iForm: "び", eForm: "べ", oForm: "ぼ", teForm: "んで", taForm: "んだ"),
        GodanPattern(dictionaryEnding: "む", inflectionClass: InflectionClass.godanMu, aForm: "ま", iForm: "み", eForm: "め", oForm: "も", teForm: "んで", taForm: "んだ"),
        GodanPattern(dictionaryEnding: "る", inflectionClass: InflectionClass.godanRu, aForm: "ら", iForm: "り", eForm: "れ", oForm: "ろ", teForm: "って", taForm: "った")
    ]

    private static let godanInflectionRules: [InflectionRule] = {
        var rules: [InflectionRule] = []

        for pattern in godanPatterns {
            let suffixes = [
                pattern.aForm + "ない",
                pattern.aForm + "なかった",
                pattern.iForm + "ます",
                pattern.iForm + "ました",
                pattern.iForm + "ません",
                pattern.iForm + "たい",
                pattern.iForm + "たくない",
                pattern.iForm + "たかった",
                pattern.eForm,
                pattern.eForm + "ば",
                pattern.oForm + "う",
                pattern.teForm,
                pattern.taForm
            ]

            for suffix in suffixes {
                rules.append(
                    InflectionRule(
                        readingSuffix: suffix,
                        baseReadingSuffix: pattern.dictionaryEnding,
                        allowedClasses: [pattern.inflectionClass]
                    )
                )
            }
        }

        return rules
    }()

    private static let suruInflectionRules: [InflectionRule] = [
        InflectionRule(readingSuffix: "しない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しなかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "します", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しました", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しません", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したい", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したくない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "して", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "した", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しよう", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "すれば", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "される", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させる", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられる", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru])
    ]

    private static let kuruInflectionForms: [(readingSuffix: String, kanjiOutputSuffix: String)] = [
        ("こない", "来ない"),
        ("こなかった", "来なかった"),
        ("こい", "来い"),
        ("きます", "来ます"),
        ("きました", "来ました"),
        ("きません", "来ません"),
        ("きたい", "来たい"),
        ("きたくない", "来たくない"),
        ("きたかった", "来たかった"),
        ("きて", "来て"),
        ("きた", "来た"),
        ("こよう", "来よう"),
        ("くれば", "来れば"),
        ("こられる", "来られる"),
        ("こられない", "来られない")
    ]

    private static let kuruInflectionRules: [InflectionRule] = {
        var rules: [InflectionRule] = []

        for form in kuruInflectionForms {
            rules.append(
                InflectionRule(
                    readingSuffix: form.readingSuffix,
                    baseReadingSuffix: "くる",
                    baseCandidateSuffixes: ["くる"],
                    outputCandidateSuffix: form.readingSuffix,
                    allowedClasses: [InflectionClass.kuru]
                )
            )
            rules.append(
                InflectionRule(
                    readingSuffix: form.readingSuffix,
                    baseReadingSuffix: "くる",
                    baseCandidateSuffixes: ["来る"],
                    outputCandidateSuffix: form.kanjiOutputSuffix,
                    allowedClasses: [InflectionClass.kuru]
                )
            )
        }

        return rules
    }()

    private static let allInflectionRules: [InflectionRule] =
        adjectiveInflectionRules
        + ichidanInflectionRules
        + godanInflectionRules
        + suruInflectionRules
        + kuruInflectionRules

    private static let emptyStemAllowedBaseReadingSuffixes: Set<String> = [
        "する",
        "くる"
    ]

    private static let inflectionRankingSuffixes: [String] = [
        "させられない", "させられる", "こられない", "こられる", "られない", "られる",
        "させない", "させる", "たくない", "なかった", "たかった", "くなかった",
        "きました", "しました", "きません", "しません", "ました", "ます",
        "くない", "かった", "ければ", "くれば", "よう", "こよう", "こい", "たい", "れば",
        "って", "った", "いて", "いた", "いで", "いだ", "んで", "んだ", "して", "した",
        "ない", "きて", "きた", "くて", "て", "た"
    ]

    private static let postfixPassthroughSuffixes: [String] = [
        "では", "には", "とは", "へ", "は", "を", "に", "で", "と", "が", "も", "の", "ね", "よ", "な", "か", "や", "ぞ", "ぜ", "さ"
    ]

    private static let maxPostfixPassthroughDepth = 3

    private static let kuruKanjiCandidateBoost = 1450
    private static let godanImperativeCandidateBoost = 320

    private static let iVowelKanaBeforeRu: Set<Character> = [
        "い", "き", "ぎ", "し", "じ", "ち", "ぢ", "に", "ひ", "び", "ぴ", "み", "り", "ゐ"
    ]

    private static let eVowelKanaBeforeRu: Set<Character> = [
        "え", "け", "げ", "せ", "ぜ", "て", "で", "ね", "へ", "べ", "ぺ", "め", "れ", "ゑ"
    ]

    private let store: KanaKanjiStore
    private let stateQueue = DispatchQueue(label: "com.kusakabe.ecritu.kana-kanji.converter-state")
    private var candidateCache: [CandidateCacheKey: [String]] = [:]
    private var candidateCacheOrder: [CandidateCacheKey] = []

    private let candidateCacheLimit = 96

    init(store: KanaKanjiStore) {
        self.store = store
    }

    func preloadSystemDictionaryIfNeeded(onLoaded: (() -> Void)? = nil) {
        store.prepareSystemDictionaryIfNeeded(onLoaded: onLoaded)
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

        let userDictionary = store.userDictionary()
        let initialUserDictionary = store.initialUserDictionary()
        let learningScoresForReading = store.learningScores(for: normalizedReading)
        let suppressedCandidatesByReading = store.suppressedCandidatesByReading()
        var scores: [String: Int] = [:]
        let systemCandidates = systemCandidates(
            for: normalizedReading,
            mode: systemCandidateMode
        )
        let userCandidates = uniqueCandidates(
            from: (userDictionary[normalizedReading] ?? [])
                + (initialUserDictionary[normalizedReading] ?? [])
        )

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
            inflectionCandidates(
                for: normalizedReading,
                userDictionary: userDictionary,
                initialUserDictionary: initialUserDictionary,
                systemCandidateMode: systemCandidateMode,
                limit: limit * 3
            ),
            baseScore: 980,
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
            to: &scores
        )

        applyLearning(
            learningScoresForReading,
            to: &scores
        )

        if let suppressedCandidates = suppressedCandidatesByReading[normalizedReading],
            !suppressedCandidates.isEmpty {
            for candidate in suppressedCandidates {
                scores.removeValue(forKey: candidate)
            }
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

        let finalCandidates = Array(sortedCandidates.prefix(limit))

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

        return finalCandidates
    }

    func learn(reading: String, candidate: String) {
        let normalizedReading = KanaTextNormalizer.normalizedReading(reading)
        let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedReading.isEmpty,
                !trimmedCandidate.isEmpty else {
            return
        }

        store.addUserEntry(reading: normalizedReading, candidate: trimmedCandidate)
        store.incrementLearning(reading: normalizedReading, candidate: trimmedCandidate)

        stateQueue.sync {
            invalidateCandidateCache()
        }
    }

    private func addCandidates(
        _ candidates: [String],
        baseScore: Int,
        to scores: inout [String: Int]
    ) {
        for (index, candidate) in uniqueCandidates(from: candidates).enumerated() {
            scores[candidate, default: 0] += max(1, baseScore - index)
        }
    }

    private func applyLearning(
        _ learningScoresForReading: [String: Int],
        to scores: inout [String: Int]
    ) {
        for (candidate, count) in learningScoresForReading {
            scores[candidate, default: 0] += count * 64
        }
    }

    private func invalidateCandidateCache() {
        candidateCache.removeAll(keepingCapacity: true)
        candidateCacheOrder.removeAll(keepingCapacity: true)
    }

    private func quickPostfixCandidatesUsingCachedStem(
        for reading: String,
        limit: Int,
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        guard reading.count >= 2,
                limit > 0 else {
            return []
        }

        for passthrough in Self.postfixPassthroughSuffixes where reading.hasSuffix(passthrough) {
            let stem = String(reading.dropLast(passthrough.count))

            guard !stem.isEmpty else {
                continue
            }

            let stemKey = CandidateCacheKey(
                reading: stem,
                limit: limit,
                modeRawValue: systemCandidateMode.rawValue
            )

            guard let stemCandidates = stateQueue.sync(execute: { candidateCache[stemKey] }),
                    !stemCandidates.isEmpty else {
                continue
            }

            let derived = stemCandidates.map { $0 + passthrough }
            return Array(uniqueCandidates(from: derived).prefix(limit))
        }

        return []
    }

    private func applyInflectionRankingHeuristics(
        for reading: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode,
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
            return
        }

        for candidate in Array(scores.keys) {
            var delta = 0

            if candidate.hasSuffix(matchedSuffix) {
                delta += 220
            } else if !containsHiragana(candidate) {
                // Readings that look inflected should not prioritize pure-kanji name-like entries.
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
    }

    private func applyGodanImperativeBoost(
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

    private func applyKuruCandidateBoost(
        for reading: String,
        to scores: inout [String: Int]
    ) {
        for form in Self.kuruInflectionForms where reading.hasSuffix(form.readingSuffix) {
            for candidate in Array(scores.keys) where candidate.hasSuffix(form.kanjiOutputSuffix) {
                scores[candidate, default: 0] += Self.kuruKanjiCandidateBoost
            }
        }
    }

    private func matchingInflectionRankingSuffix(for reading: String) -> String? {
        for suffix in Self.inflectionRankingSuffixes where reading.hasSuffix(suffix) {
            return suffix
        }

        return nil
    }

    private func containsHiragana(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            if (0x3040...0x309F).contains(scalar.value) || scalar.value == 0x30FC {
                return true
            }
        }

        return false
    }

    private func inflectionCandidates(
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

    private func postfixPassthroughCandidates(
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
        var queue: [(stem: String, suffix: String, depth: Int)] = [(reading, "", 0)]
        var visited = Set<String>()

        while !queue.isEmpty {
            let current = queue.removeFirst()

            guard current.depth < Self.maxPostfixPassthroughDepth else {
                continue
            }

            for passthrough in Self.postfixPassthroughSuffixes where current.stem.hasSuffix(passthrough) {
                let nextStem = String(current.stem.dropLast(passthrough.count))

                guard !nextStem.isEmpty else {
                    continue
                }

                let nextSuffix = passthrough + current.suffix
                let visitKey = nextStem + "\u{1}" + nextSuffix

                guard visited.insert(visitKey).inserted else {
                    continue
                }

                let stemCandidates = uniqueCandidates(
                    from: candidatesForReading(
                        nextStem,
                        userDictionary: userDictionary,
                        initialUserDictionary: initialUserDictionary,
                        systemCandidateMode: systemCandidateMode
                    ) + inflectionCandidates(
                        for: nextStem,
                        userDictionary: userDictionary,
                        initialUserDictionary: initialUserDictionary,
                        systemCandidateMode: systemCandidateMode,
                        limit: limit
                    )
                )

                for candidate in stemCandidates {
                    derived.append(candidate + nextSuffix)
                }

                queue.append((nextStem, nextSuffix, current.depth + 1))
            }
        }

        return Array(uniqueCandidates(from: derived).prefix(limit))
    }

    private func deriveIkuIrregularCandidates(
        for reading: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        var results: [String] = []

        if let stem = removingSuffix(reading, suffix: "った") {
            let baseReading = stem + "く"
            for candidate in candidatesForReading(
                baseReading,
                userDictionary: userDictionary,
                initialUserDictionary: initialUserDictionary,
                systemCandidateMode: systemCandidateMode
            ) where candidate.hasSuffix("行く") {
                let prefix = String(candidate.dropLast("行く".count))
                results.append(prefix + "行った")
            }
        }

        if let stem = removingSuffix(reading, suffix: "って") {
            let baseReading = stem + "く"
            for candidate in candidatesForReading(
                baseReading,
                userDictionary: userDictionary,
                initialUserDictionary: initialUserDictionary,
                systemCandidateMode: systemCandidateMode
            ) where candidate.hasSuffix("行く") {
                let prefix = String(candidate.dropLast("行く".count))
                results.append(prefix + "行って")
            }
        }

        return results
    }

    private func derivedCandidates(
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

        let baseCandidates = candidatesForReading(
            baseReading,
            userDictionary: userDictionary,
            initialUserDictionary: initialUserDictionary,
            systemCandidateMode: systemCandidateMode
        )

        guard !baseCandidates.isEmpty else {
            return []
        }

        let metadata = inflectionMetadata(for: baseReading)
        let userCandidateSet = Set(
            (userDictionary[baseReading] ?? []) + (initialUserDictionary[baseReading] ?? [])
        )
        var results: [String] = []

        for candidate in baseCandidates {
            guard let matchedSuffix = rule.baseCandidateSuffixes.first(where: { candidate.hasSuffix($0) }) else {
                continue
            }

            guard let inflectionClass = resolvedInflectionClass(
                for: candidate,
                baseReading: baseReading,
                systemClassMap: metadata.classMap,
                hasSystemMetadata: metadata.hasMetadata,
                userCandidateSet: userCandidateSet
            ), rule.allowedClasses.contains(inflectionClass) else {
                continue
            }

            let stem = String(candidate.dropLast(matchedSuffix.count))
            results.append(stem + rule.outputCandidateSuffix)
        }

        return results
    }

    private func inflectionMetadata(for reading: String) -> (classMap: [String: String], hasMetadata: Bool) {
        store.systemInflectionMetadata(for: reading)
    }

    private func resolvedInflectionClass(
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

    private func inferredInflectionClass(for candidate: String, baseReading: String) -> String? {
        if candidate.hasSuffix("する") {
            return InflectionClass.suru
        }

        if candidate.hasSuffix("来る") || candidate.hasSuffix("くる") {
            return InflectionClass.kuru
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

    private func isLikelyIchidanBaseReading(_ reading: String) -> Bool {
        guard reading.hasSuffix("る"),
                reading.count >= 2 else {
            return false
        }

        let chars = Array(reading)
        let preRu = chars[chars.count - 2]

        return Self.iVowelKanaBeforeRu.contains(preRu)
            || Self.eVowelKanaBeforeRu.contains(preRu)
    }

    private func systemCandidates(
        for reading: String,
        mode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        let storeCandidates = store.systemCandidates(for: reading, mode: mode)

        if storeCandidates.isEmpty {
            return KanaKanjiSeedDictionary.seed[reading] ?? []
        }

        return uniqueCandidates(
            from: storeCandidates + (KanaKanjiSeedDictionary.seed[reading] ?? [])
        )
    }

    private func candidatesForReading(
        _ reading: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        uniqueCandidates(
            from: (userDictionary[reading] ?? [])
                + (initialUserDictionary[reading] ?? [])
                + systemCandidates(for: reading, mode: systemCandidateMode)
        )
    }

    private func removingSuffix(_ text: String, suffix: String) -> String? {
        guard !suffix.isEmpty,
                text.hasSuffix(suffix) else {
            return nil
        }

        return String(text.dropLast(suffix.count))
    }

    private func uniqueCandidates(from candidates: [String]) -> [String] {
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
