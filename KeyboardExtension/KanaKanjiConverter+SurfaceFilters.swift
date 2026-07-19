import Foundation

// 表層フィルタ群: 装飾表記(〜/中黒)・旧仮名/旧形容詞・動詞語幹断片・脱活用抑制、
// および文字種判定ユーティリティ。候補列挙の各段から共通に使う。
extension KanaKanjiConverter {
    static let predicateRequiredExplanatorySuffixes: [String] = [
        "んですけれど", "んですけど", "んだけれど", "んだけど", "んです", "んだ", "のです", "のだ"
    ]

    static let predicateStemEndingKana: Set<Character> = [
        "う", "く", "ぐ", "す", "ず", "つ", "づ", "ぬ", "ふ", "ぶ", "ぷ", "む", "ゆ", "る",
        "い", "た", "だ"
    ]

    static func explanatorySuffixRequiresPredicateStem(_ suffix: String) -> Bool {
        for restricted in predicateRequiredExplanatorySuffixes where suffix.hasPrefix(restricted) {
            return true
        }
        return false
    }

    static func isPredicateLikeStemReading(_ reading: String) -> Bool {
        guard let last = reading.last else { return false }
        return predicateStemEndingKana.contains(last)
    }

    static func suffixFormsVerbConjugationWithNEnding(_ suffix: String) -> Bool {
        suffix.hasPrefix("だ") || suffix.hasPrefix("で")
    }

    static let verbalStemRequiredPostfixPrefixes: [String] = [
        "よう"
    ]

    static func postfixSuffixRequiresVerbalStem(_ suffix: String, stemReading: String) -> Bool {
        for required in verbalStemRequiredPostfixPrefixes where suffix.hasPrefix(required) {
            return true
        }
        // 否定テ形は用言にしか付かない(名詞は じゃなくて)。ただし ない形容詞
        // (勿体ない/仕方ない/申し訳ない 等)は辞書に基底が無く 名詞+なくて 合成が唯一の
        // 供給のため、短い語幹(イカ/凧 等の読み2文字以下)だけを動詞要求の対象にする。
        if suffix.hasPrefix("なくて"), stemReading.count <= 2 {
            return true
        }
        return false
    }

    func normalizedTaggedCandidates(for reading: String) -> Set<String> {
        store.systemCandidates(
            for: reading,
            taggedWith: KanaKanjiCandidateSourceTag.normalized
        ).candidates
    }

    func filterVerbStemFragmentCandidatesIfNeeded(
        _ candidates: [String],
        stemReading: String,
        nextSuffix: String
    ) -> [String] {
        guard Self.suffixFormsVerbConjugationWithNEnding(nextSuffix) else {
            return candidates
        }

        let normalizedSet = normalizedTaggedCandidates(for: stemReading)
        return candidates.filter { candidate in
            guard candidate.hasSuffix("ん") else { return true }
            return normalizedSet.contains(candidate)
        }
    }

    static let godanPotentialConjugationSuffixes: [String] = [
        "る",
        "ない", "なかった",
        "た", "たら", "たり",
        "て",
        "ます", "ました", "ません", "ませんでした",
        "れば",
        "よう",
        "たい", "たく", "たくて", "たくない", "たくなかった", "たかった", "たければ"
    ]

    static let godanPotentialDeinflectionMappings: [(readingSuffix: String, baseReadingSuffix: String)] = {
        var mappings: [(readingSuffix: String, baseReadingSuffix: String)] = []
        for pattern in godanPatterns {
            for conjugation in godanPotentialConjugationSuffixes {
                mappings.append(
                    (
                        readingSuffix: pattern.eForm + conjugation,
                        baseReadingSuffix: pattern.dictionaryEnding
                    )
                )
            }
        }
        return mappings
    }()

    // isDeinflectedSuppressed 用の事前バケット: readingSuffix 末尾文字→ルール群。
    // 全ルール(約1000件)の線形走査が candidatesForReading の候補ごとに乗算的に呼ばれる
    // ため、読み末尾が一致し得るルールだけ照合する。readingSuffix が空のルールは
    // どの読みにもマッチし得るので別枠で常に照合する。
    static let deinflectionRulesByReadingLastCharacter: [Character: [InflectionRule]] = {
        var buckets: [Character: [InflectionRule]] = [:]
        for rule in allInflectionRules {
            guard let last = rule.readingSuffix.last else {
                continue
            }
            buckets[last, default: []].append(rule)
        }
        return buckets
    }()
    static let deinflectionRulesWithEmptyReadingSuffix: [InflectionRule] =
        allInflectionRules.filter { $0.readingSuffix.isEmpty }
    static let godanPotentialDeinflectionMappingsByReadingLastCharacter: [Character: [(readingSuffix: String, baseReadingSuffix: String)]] = {
        var buckets: [Character: [(readingSuffix: String, baseReadingSuffix: String)]] = [:]
        for mapping in godanPotentialDeinflectionMappings {
            guard let last = mapping.readingSuffix.last else {
                continue
            }
            buckets[last, default: []].append(mapping)
        }
        return buckets
    }()

    func isDeinflectedSuppressed(
        candidate: String,
        reading: String,
        suppressedByReading: [String: Set<String>]
    ) -> Bool {
        guard !suppressedByReading.isEmpty else {
            return false
        }

        guard let readingLastCharacter = reading.last else {
            return false
        }
        let bucketedRules = Self.deinflectionRulesByReadingLastCharacter[readingLastCharacter] ?? []

        for rule in bucketedRules + Self.deinflectionRulesWithEmptyReadingSuffix {
            guard reading.hasSuffix(rule.readingSuffix),
                candidate.hasSuffix(rule.outputCandidateSuffix) else {
                continue
            }

            let readingStem = String(reading.dropLast(rule.readingSuffix.count))
            let candidateStem = String(candidate.dropLast(rule.outputCandidateSuffix.count))

            if readingStem.isEmpty,
                !Self.emptyStemAllowedBaseReadingSuffixes.contains(rule.baseReadingSuffix) {
                continue
            }

            let baseReading = readingStem + rule.baseReadingSuffix

            guard let suppressedSet = suppressedByReading[baseReading],
                !suppressedSet.isEmpty else {
                continue
            }

            for baseCandidateSuffix in rule.baseCandidateSuffixes {
                let baseCandidate = candidateStem + baseCandidateSuffix

                if suppressedSet.contains(baseCandidate) {
                    return true
                }
            }
        }

        let bucketedMappings = Self.godanPotentialDeinflectionMappingsByReadingLastCharacter[readingLastCharacter] ?? []

        for mapping in bucketedMappings {
            guard reading.hasSuffix(mapping.readingSuffix),
                candidate.hasSuffix(mapping.readingSuffix) else {
                continue
            }

            let readingStem = String(reading.dropLast(mapping.readingSuffix.count))
            let candidateStem = String(candidate.dropLast(mapping.readingSuffix.count))

            guard !readingStem.isEmpty else {
                continue
            }

            let baseReading = readingStem + mapping.baseReadingSuffix
            let baseCandidate = candidateStem + mapping.baseReadingSuffix

            if let suppressedSet = suppressedByReading[baseReading],
                suppressedSet.contains(baseCandidate) {
                return true
            }
        }

        return false
    }

    func filterNonVerbalCandidatesForVerbalPostfix(
        _ candidates: [String],
        stemReading: String,
        nextSuffix: String
    ) -> [String] {
        guard Self.postfixSuffixRequiresVerbalStem(nextSuffix, stemReading: stemReading) else {
            return candidates
        }

        let metadata = inflectionMetadata(for: stemReading)
        // 追加語彙・学習語彙の動詞はシステム辞書の活用クラスメタデータを持たないため、
        // 活用候補生成と同じ推論(resolvedInflectionClass)で動詞性を判定する。
        // これにより「使った/読んだ」等と同様に「よう/ように/ような」も導出できる。
        // 品詞が明示(systemClassMap)されている語はそちらが優先される。
        let normalizedStemReading = KanaTextNormalizer.normalizedReading(stemReading)
        let userCandidateSet = Set(
            combinedUserCandidates(for: stemReading, userDictionary: store.userDictionary())
        ).union(store.initialUserDictionary()[normalizedStemReading] ?? [])

        return candidates.filter { candidate in
            if candidate.hasSuffix("する")
                || candidate.hasSuffix("くる")
                || candidate.hasSuffix("来る") {
                return true
            }

            guard let className = resolvedInflectionClass(
                for: candidate,
                baseReading: stemReading,
                systemClassMap: metadata.classMap,
                hasSystemMetadata: metadata.hasMetadata,
                userCandidateSet: userCandidateSet
            ) else {
                return false
            }

            return className == InflectionClass.ichidan
                || className.hasPrefix("godan-")
                || className == InflectionClass.kuru
        }
    }

    // SudachiDict の「〜」水増し表記(ちゃ〜んと/あの〜/アンケ〜ト/う〜ん 等 ~228件)を弾く。
    // 波ダッシュ(U+301C)や全角チルダ(U+FF5E)は母音を伸ばす砕けた強調表記で、既定変換には
    // 不要。読み自体に波ダッシュを含む場合(ユーザが〜を打った)は除外しない。
    // 連文節では OOV(コーパス未収録)扱いになり一律 dictUnknownCost で正規のレア語(例:
    // ちゃんと=unigram 6550)を下回って逆転するため、列挙段階で落とす。
    static func hasWaveDashElongation(_ surface: String, reading: String) -> Bool {
        func containsWaveDash(_ text: String) -> Bool {
            text.unicodeScalars.contains { $0.value == 0x301C || $0.value == 0xFF5E }
        }
        return containsWaveDash(surface) && !containsWaveDash(reading)
    }

    // SudachiDict の中黒装飾表記を弾く。
    // (a) 中黒を除くと読みそのもの: ち・ゃ・ん/そ・し・て 等(postfix 合成形 ち・ゃ・んと も一致)
    // (b) 中黒を除くと読みのカタカナ化かつ全セグメント1文字: ア・リ・ガ・ト/ヒ・ミ・ツ 等
    // アイ・アール/チャン・クアン・ハー等の正当な外国名・社名区切り(セグメント複数文字)は
    // (b) の per-char 条件で残る。読み自体に中黒を含む場合(ユーザが・を打った)は除外しない。
    static func hasNakaguroDecorationSpelling(_ surface: String, reading: String) -> Bool {
        guard surface.contains("・"), !reading.contains("・") else {
            return false
        }
        let stripped = surface.replacingOccurrences(of: "・", with: "")
        if stripped == reading {
            return true
        }
        let segments = surface.split(separator: "・", omittingEmptySubsequences: false)
        return segments.allSatisfy { $0.count == 1 }
            && stripped == Self.hiraganaToKatakana(reading)
    }

    // SudachiDict の三点リーダ水増し表記(な…ん/シャ…ァァン の2件)を弾く。台詞の
    // 溜め表記の収穫で、合成の種になると な…ん+の→な…んの 等のジャンクを作る。
    // 読み自体に…を含む場合(ユーザが…を打った)は除外しない。
    static func hasEllipsisElongation(_ surface: String, reading: String) -> Bool {
        surface.contains("…") && !reading.contains("…")
    }

    // 装飾表記(〜水増し・中黒散らし・…溜め)の総合判定。候補列挙の各段で共通に使う。
    static func isDecorativeVariantSurface(_ surface: String, reading: String) -> Bool {
        hasWaveDashElongation(surface, reading: reading)
            || hasNakaguroDecorationSpelling(surface, reading: reading)
            || hasEllipsisElongation(surface, reading: reading)
    }

    // 連濁の清音化マップ(濁音/半濁音→清音)。連濁収穫フィルタ用。
    static let rendakuDevoicedKanaCharacter: [Character: Character] = [
        "が": "か", "ぎ": "き", "ぐ": "く", "げ": "け", "ご": "こ",
        "ざ": "さ", "じ": "し", "ず": "す", "ぜ": "せ", "ぞ": "そ",
        "だ": "た", "ぢ": "ち", "づ": "つ", "で": "て", "ど": "と",
        "ば": "は", "び": "ひ", "ぶ": "ふ", "べ": "へ", "ぼ": "ほ",
        "ぱ": "は", "ぴ": "ひ", "ぷ": "ふ", "ぺ": "へ", "ぽ": "ほ"
    ]

    // 連濁収穫フィルタ: 墓(ばか)/蓋(ぶた)/口(ぐち) 等、Sudachi が複合語内の連濁読み
    // (新墓=にいばか、入り口=いりぐち 等)で収穫した単漢字表層を弾く。連濁は複合語
    // 境界でしか起きない現象で、単独入力・合成の読みとしては使わない。
    // 判定: 単漢字+濁音始まりの読み(2文字以上)で、清音化した読みに同じ表層が
    // より安く実在する場合。音読で濁側が主の語(分=ぶん5285/ふん10220、台=だい のみ)
    // は濁側が安い/清音側に無いので誤爆しない。読み別 word_costs は store がキャッシュ。
    func isRendakuHarvestSurface(_ surface: String, reading: String) -> Bool {
        guard reading.count >= 2,
            Self.isSingleKanjiCandidate(surface),
            let firstChar = reading.first,
            let devoicedFirst = Self.rendakuDevoicedKanaCharacter[firstChar] else {
            return false
        }
        let devoicedReading = String(devoicedFirst) + reading.dropFirst()
        guard let devoicedCost = store.wordCosts(for: devoicedReading)[surface] else {
            return false
        }
        let voicedCost = store.wordCosts(for: reading)[surface] ?? Int.max
        return voicedCost > devoicedCost
    }

    static func isSingleKanjiCandidate(_ candidate: String) -> Bool {
        guard candidate.count == 1,
            let scalar = candidate.unicodeScalars.first else {
            return false
        }

        return (0x3400...0x4DBF).contains(scalar.value)
            || (0x4E00...0x9FFF).contains(scalar.value)
            || (0xF900...0xFAFF).contains(scalar.value)
    }

    static func containsKanjiCandidate(_ candidate: String) -> Bool {
        for scalar in candidate.unicodeScalars {
            if (0x3400...0x4DBF).contains(scalar.value)
                || (0x4E00...0x9FFF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value) {
                return true
            }
        }

        return false
    }

    static func isPureKatakanaCandidate(_ candidate: String) -> Bool {
        guard !candidate.isEmpty else {
            return false
        }

        for scalar in candidate.unicodeScalars {
            if scalar.value == 0x30FB || scalar.value == 0x30FC
                || scalar.value == 0xFF65 || scalar.value == 0xFF70
                || scalar.value == 0xFF9E || scalar.value == 0xFF9F {
                continue
            }

            if (0x30A0...0x30FF).contains(scalar.value)
                || (0x31F0...0x31FF).contains(scalar.value)
                || (0xFF66...0xFF9D).contains(scalar.value) {
                continue
            }

            return false
        }

        return true
    }

    func containsHiragana(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            if (0x3040...0x309F).contains(scalar.value) || scalar.value == 0x30FC {
                return true
            }
        }

        return false
    }

    func containsKanjiOrKatakana(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            if (0x30A0...0x30FF).contains(scalar.value)
                || (0x3400...0x9FFF).contains(scalar.value) {
                return true
            }
        }

        return false
    }

    func containsKanji(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            if (0x3400...0x9FFF).contains(scalar.value) {
                return true
            }
        }

        return false
    }

    func filterHistoricalKanaSurfaceCandidates(
        for reading: String,
        candidates: [String]
    ) -> [String] {
        let allowed = stateQueue.sync { historicalKanaSurfaceAllowed }

        guard !allowed,
            reading.hasSuffix("える") else {
            return candidates
        }

        return candidates.filter { candidate in
            guard candidate.count >= 2,
                candidate.hasSuffix("へる") else {
                return true
            }

            return false
        }
    }

    func filterArchaicAdjectiveSurfaceCandidates(
        for reading: String,
        candidates: [String]
    ) -> [String] {
        filterArchaicAdjectiveSurfaceCandidates(
            for: reading,
            candidates: candidates,
            userDictionary: nil,
            learnedDictionary: nil,
            initialUserDictionary: nil
        )
    }

    func filterArchaicAdjectiveSurfaceCandidates(
        for reading: String,
        candidates: [String],
        userDictionary: [String: [String]]?,
        learnedDictionary: [String: [String]]?,
        initialUserDictionary: [String: [String]]?
    ) -> [String] {
        guard reading.hasSuffix("かる") || reading.hasSuffix("かり") else {
            return candidates
        }

        guard let baseReadingStem = removingSuffix(reading, suffix: "かる")
            ?? removingSuffix(reading, suffix: "かり"),
            !baseReadingStem.isEmpty else {
            return candidates
        }

        let baseReading = baseReadingStem + "い"
        let userBaseCandidates = userDictionary?[baseReading] ?? []
        let learnedBaseCandidates = learnedDictionary?[baseReading] ?? []
        let initialBaseCandidates = initialUserDictionary?[baseReading] ?? []
        let storeBaseCandidates = store.systemCandidates(
            for: baseReading,
            mode: .lesDeux
        )
        let seedBaseCandidates = KanaKanjiSeedDictionary.seed[baseReading] ?? []
        let baseCandidates = Set(
            uniqueCandidates(
                from: userBaseCandidates
                    + learnedBaseCandidates
                    + initialBaseCandidates
                    + storeBaseCandidates
                    + seedBaseCandidates
            )
        )

        guard !baseCandidates.isEmpty else {
            return candidates
        }

        var filtered: [String] = []

        for candidate in candidates {
            guard candidate.hasSuffix("かる") || candidate.hasSuffix("かり") else {
                filtered.append(candidate)
                continue
            }

            guard candidate.count > 2 else {
                filtered.append(candidate)
                continue
            }

            let stem = String(candidate.dropLast(2))
            let modernIAdjective = stem + "い"

            if baseCandidates.contains(modernIAdjective) {
                continue
            }

            filtered.append(candidate)
        }

        return filtered
    }
}
