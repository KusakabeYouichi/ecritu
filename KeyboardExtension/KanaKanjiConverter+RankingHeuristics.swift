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
            let others = uniqueCandidates(from: systemCandidates).filter { $0 != reading }
            if !others.isEmpty, isLMKanaPreferred(reading: reading, among: others) {
                let maxOther = others.map { scores[$0, default: 0] }.max() ?? 0
                scores[reading] = max(identityScore, maxOther + 1)
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

    // 派生(活用基底・postfix語幹)の候補並びを整える(かいてある対策の一般化):
    // (1) seed の並び(書く/描く…)を先頭へ — 派生が正書から出るように。
    // (2) かな識別(候補==読み)は LM 優位なら先頭へ(ある/やる 等)、劣位で先頭に居る
    //     場合は末尾へ(かく 等)。生の辞書順は 書く rank15・有る先頭 等の歪みがある。
    func orderedDerivationBaseCandidates(_ candidates: [String], reading: String) -> [String] {
        var ordered = candidates
        if let seedOrder = KanaKanjiSeedDictionary.seed[reading] {
            let seedSet = Set(seedOrder)
            let seeded = seedOrder.filter { ordered.contains($0) }
            ordered = seeded + ordered.filter { !seedSet.contains($0) }
        }
        guard ordered.contains(reading) else {
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
            } else if index > 0, Self.containsKanjiCandidate(candidate) {
                // 複数字の熟語 seed(高校/孝行, 描く 等)を seed 順で辞書ベースの上へ。
                // 先頭は上の leading ブーストで既に持ち上がるため index>0 のみ対象。
                // SudachiDict の rank で「々」形容動詞群が頻出熟語を埋める歪みを是正する。
                let boost = max(
                    200,
                    Self.seedLeadingKanjiCandidateBoost - (index * Self.seedOrderedKanjiCompoundStep)
                )
                scores[candidate, default: 0] += boost
            }
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
