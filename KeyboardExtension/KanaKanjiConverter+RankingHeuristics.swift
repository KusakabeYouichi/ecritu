import Foundation

// ランキング補正群: 活用形・命令形/意志形・来る・スクリプト種・単漢字seed・数値単位の
// 各ブーストとスコア加算の共通ヘルパ。candidates() のスコア確定段から呼ばれる。
extension KanaKanjiConverter {
    static let kuruKanjiCandidateBoost = 1450

    static let godanImperativeCandidateBoost = 320

    static let godanVolitionalCandidateBoost = 320

    static let numericUnitFallbackCandidateBoost = 320

    static let numericCounterCompoundCandidateBoost = 360

    static let sameReadingPureKatakanaPenalty = 128

    static let seedLeadingKanjiCandidateBoost = 1600

    static let seedSingleKanjiPriorityBaseBoost = 220

    static let seedSingleKanjiPriorityStep = 12

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

        for candidate in matchingCandidates where Self.isPureKatakanaCandidate(candidate) {
            if protectedKatakanaCandidates.contains(candidate) {
                continue
            }

            let penalizedScore = scores[candidate, default: 0] - Self.sameReadingPureKatakanaPenalty
            scores[candidate] = min(penalizedScore, lowestNonKatakanaScore - 1)
        }
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

        return protectedCandidates
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
            if index == 0,
                Self.containsKanjiCandidate(candidate) {
                scores[candidate, default: 0] += Self.seedLeadingKanjiCandidateBoost
            }

            guard Self.isSingleKanjiCandidate(candidate) else {
                continue
            }

            let boost = max(
                24,
                Self.seedSingleKanjiPriorityBaseBoost - (index * Self.seedSingleKanjiPriorityStep)
            )
            scores[candidate, default: 0] += boost
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
                delta += 220
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

            for candidate in Array(scores.keys) where candidate.hasSuffix(volitionalEnding) {
                let candidateStem = String(candidate.dropLast(volitionalEnding.count))
                let baseCandidate = candidateStem + pattern.dictionaryEnding

                guard baseCandidates.contains(baseCandidate) else {
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
