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

    // 抑制(読みr→表層s)を「同じかな末尾tを伴う r+t → s+t」の形にも適用する。
    // 全くありません は文語形容詞 全い(まったい)の活用として生成されるため、
    // まったく→全く の抑制(基底読みが異なる)を脱活用照合がすり抜ける。
    // 読みの前方一致+同一末尾なら表層先頭を抑制表層と照合して除去する(2418)。
    func isComposedSuppressed(
        candidate: String,
        reading: String,
        suppressedByReading: [String: Set<String>]
    ) -> Bool {
        guard !suppressedByReading.isEmpty else {
            return false
        }
        let readingChars = Array(reading)
        guard readingChars.count >= 2 else {
            return false
        }
        for prefixLength in 1..<readingChars.count {
            let tail = String(readingChars[prefixLength...])
            guard candidate.count > tail.count, candidate.hasSuffix(tail) else {
                continue
            }
            guard let suppressedSet = suppressedByReading[String(readingChars[0..<prefixLength])] else {
                continue
            }
            if suppressedSet.contains(String(candidate.dropLast(tail.count))) {
                return true
            }
        }
        return false
    }

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

            var matched = false
            rule.forEachBaseCandidateSuffix { baseCandidateSuffix in
                if !matched, suppressedSet.contains(candidateStem + baseCandidateSuffix) {
                    matched = true
                }
            }
            if matched {
                return true
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

    // SudachiDict の促音/長音の水増し表記(イヤっ/嫌ー/あーっ 等)を弾く。台詞・感動詞の
    // 溜め表記の収穫で、読みに無い「っ」「ー」が表層に足されている。読み側にその文字が
    // あるユーザ入力(いやっ/いやー を打った場合)は対象外。合成の種になると
    // いやで→イヤっで/嫌ーで のようなジャンクを作る(2450)。
    // 表層がカタカナ語のとき促音は「ッ」だが読みは「っ」なので、かなの種を揃えて突き合わせる。
    // 素朴な文字一致にしていたため、リッター/ヘット/ネット/チケット のような促音カタカナ語
    // (辞書に13,348エントリ)を一律で水増し表記と誤判定して候補から消していた(2466)。
    static func hasSokuonOrChoonPadding(_ surface: String, reading: String) -> Bool {
        for (surfaceCharacter, readingCharacter) in [("っ", "っ"), ("ッ", "っ"), ("ー", "ー")]
        where surface.contains(surfaceCharacter) {
            if !reading.contains(readingCharacter) {
                return true
            }
        }
        return false
    }

    // 装飾表記(〜水増し・中黒散らし・…溜め・っ/ー水増し)の総合判定。候補列挙の各段で共通に使う。
    static func isDecorativeVariantSurface(_ surface: String, reading: String) -> Bool {
        hasWaveDashElongation(surface, reading: reading)
            || hasNakaguroDecorationSpelling(surface, reading: reading)
            || hasEllipsisElongation(surface, reading: reading)
            || hasSokuonOrChoonPadding(surface, reading: reading)
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
    // 連濁収穫の動詞基底(どる→取る/づく→付く 等)。複合語後部の連濁読みが Sudachi 収穫で
    // 独立エントリ化したもので、連濁は複合語内でのみ生じ文節頭には立たない。活用派生
    // (どれ→取れ/どれば→取れば)の基底から除く(おおいのはどれ→多いのは取れ 対策)。
    // 判定は単漢字連濁(墓/ばか)と同じ「清音読みに同表層がより安く実在する」コスト比較 —
    // 出る/出す 等の正当な濁音動詞は清音読みエントリ自体が無いため対象外。
    func isRendakuHarvestVerbBase(_ surface: String, baseReading: String) -> Bool {
        guard surface != baseReading,
            let firstChar = baseReading.first,
            let devoicedFirst = Self.rendakuDevoicedKanaCharacter[firstChar] else {
            return false
        }
        let devoicedReading = String(devoicedFirst) + baseReading.dropFirst()
        guard let devoicedCost = store.wordCosts(for: devoicedReading)[surface] else {
            return false
        }
        let voicedCost = store.wordCosts(for: baseReading)[surface] ?? Int.max
        return voicedCost > devoicedCost
    }

    // includingMultiCharacterSurfaces: 単漢字以外(手間/手本/聞き 等の2文字以上)も対象にする。
    // 連濁形は複合語の内部でしか現れないので、単独入力の候補(単文節の最終段)では多字表層も
    // 弾くのが正しい(でま→手間 は誤り)。一方ラティス/合成の供給では 人+込み(ひとごみ)の
    // ような複合語内の連濁が要るため、既定は従来どおり単漢字だけに絞る(2485)。
    func isRendakuHarvestSurface(
        _ surface: String,
        reading: String,
        includingMultiCharacterSurfaces: Bool = false
    ) -> Bool {
        guard reading.count >= 2,
            includingMultiCharacterSurfaces
                ? Self.containsKanjiCandidate(surface)
                : Self.isSingleKanjiCandidate(surface),
            let firstChar = reading.first,
            let devoicedFirst = Self.rendakuDevoicedKanaCharacter[firstChar] else {
            return false
        }
        // seed 掲載の表層は正当な濁音変種(ぎたない→汚い 等)なので免除
        // (カタカナ強調の katakanaRunsAreSeedProtected と同じ流儀。2636)
        if KanaKanjiSeedDictionary.seed[reading]?.contains(surface) ?? false {
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

    // 旧仮名遣い専用の仮名。ゐ/ゑ(ひらがな)・ヰ/ヱ(カタカナ)。設定「旧仮名遣いの候補を含める」で制御。
    static let historicalKanaScalars: Set<Character> = ["ゐ", "ゑ", "ヰ", "ヱ"]
    // かな踊り字(繰り返し記号)。ゝ/ゞ(ひらがな)・ヽ/ヾ(カタカナ)。設定「仮名の踊り字の候補を含める」で
    // 制御(旧仮名遣いとは独立)。※漢字の 々(人々/時々 等で正当)は除外。
    static let iterationMarkScalars: Set<Character> = ["ゝ", "ゞ", "ヽ", "ヾ"]

    func filterHistoricalKanaSurfaceCandidates(
        for reading: String,
        candidates: [String]
    ) -> [String] {
        let (historicalAllowed, iterationAllowed) = stateQueue.sync {
            (historicalKanaSurfaceAllowed, iterationMarkSurfaceAllowed)
        }

        guard !historicalAllowed || !iterationAllowed else {
            return candidates
        }

        return candidates.filter { candidate in
            // 旧仮名文字(ゐゑヰヱ)を含む表層(ぐらゐ/ゐる/ウヰスキー 等)は旧仮名遣い。
            if !historicalAllowed, candidate.contains(where: { Self.historicalKanaScalars.contains($0) }) {
                return false
            }
            // かな踊り字(ゝゞヽヾ)を含む表層(いゝ/こゝ 等)。
            if !iterationAllowed, candidate.contains(where: { Self.iterationMarkScalars.contains($0) }) {
                return false
            }
            // える動詞の へる 旧仮名活用(給へる/覚へる 等)。読みが える 終わりの時のみ(旧仮名側)。
            if !historicalAllowed, reading.hasSuffix("える"), candidate.count >= 2, candidate.hasSuffix("へる") {
                return false
            }
            return true
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

            // 純ひらがな表層は文語形容詞の表記ゆらぎではないので対象外。
            // ばかり(副助詞)が 基底ばい(倍)経由で誤って全滅していた(2398)。
            guard containsKanjiOrKatakana(candidate) else {
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

// MARK: - カタカナ強調表記/交ぜ書きの分類(コンテナ設定 [抑制/後方/同列] の対象判定)
extension KanaKanjiConverter {
    // 語幹単位のカタカナ強調判定(postfix 合成前フィルタ用)。単語単位の
    // applyScriptVariantCandidateModes は合成後の全長読み(うまいのだ 等)に対して働くが、
    // 合成読みには全漢字の代替候補が存在し得ないため外来語保護が誤作動し、ウマい+のだ の
    // ようなカタカナ化語幹の合成が素通りしていた(2402)。語幹の段階で単語単位と同じ
    // 判定(seed/学習/追加語彙は対象外、LM でカタカナ側が最安なら外来語として保護)を行う。
    func isKatakanaEmphasisBaseCandidate(_ candidate: String, reading: String) -> Bool {
        guard katakanaEmphasisCandidateMode == .suppress,
            candidate != reading,
            let hira = Self.hiraganizedKanaOnlySurface(candidate),
            hira == reading,
            !(KanaKanjiSeedDictionary.seed[reading]?.contains(candidate) ?? false),
            !(KanaKanjiSeedDictionary.exactReadingOnlySeed[reading]?.contains(candidate) ?? false),
            !Self.katakanaRunsAreSeedProtected(candidate) else {
            return false
        }
        if (store.userDictionary()[reading] ?? []).contains(candidate)
            || (store.learnedDictionary()[reading] ?? []).contains(candidate) {
            return false
        }
        // 辞書コストによる外来語保護(単語単位と同基準。CandidateScore のコメント参照)
        let readingWordCosts = store.wordCosts(for: reading)
        if let katakanaWordCost = readingWordCosts[candidate],
            let nonKatakanaBestWordCost = readingWordCosts
                .filter({ !Self.isKatakanaString($0.key) })
                .values
                .min(),
            nonKatakanaBestWordCost - katakanaWordCost
                >= KanaKanjiConverter.CandidateScore.loanwordKatakanaWordCostGap {
            return false
        }
        let uni = store.wordLMUnigramCosts(for: [candidate, reading])
        if let kataUni = uni[candidate] {
            // カタカナ側が LM 収録: かな識別より安ければ正当な外来語表記(パン 等)
            guard let kanaUni = uni[reading] else {
                return false
            }
            return kanaUni < kataUni
        }
        // LM 未収録のカタカナ化は、かな/漢字の代替が実在する限り強調(単語単位と同基準)
        return uni[reading] != nil
            || store.wordCosts(for: reading).keys.contains { Self.containsKanjiCandidate($0) }
    }
    // 定着した交ぜ書き(常用漢字外回避ではなく主流表記になっているもの)。分類から除外する。
    // 交ぜ書き判定の許可リスト。漢字+かな混在だが現代の標準表記であるもの。
    // 今まで は 今迄(旧表記・全漢字)が辞書にあるため交ぜ書き扱いで抑制されていた(2455)。
    static let mazegakiAllowlistedSurfaces: Set<String> = [
        "子ども", "子どもたち", "子どもの日", "今まで"
    ]

    // 表層をひらがな化する。かな(ひらがな/カタカナ/ー)以外を含む場合は nil。
    static func hiraganizedKanaOnlySurface(_ surface: String) -> String? {
        var result = ""
        for scalar in surface.unicodeScalars {
            switch scalar.value {
            case 0x3041...0x3096, 0x30FC: // ひらがな・長音
                result.unicodeScalars.append(scalar)
            case 0x30A1...0x30F6: // カタカナ→ひらがな
                guard let mapped = Unicode.Scalar(scalar.value - 0x60) else { return nil }
                result.unicodeScalars.append(mapped)
            default:
                return nil
            }
        }
        return result.isEmpty ? nil : result
    }

    static func isAllKanjiSurface(_ surface: String) -> Bool {
        !surface.isEmpty && surface.unicodeScalars.allSatisfy {
            (0x4E00...0x9FFF).contains($0.value) || $0.value == 0x3005 // 々
        }
    }

    // 交ぜ書き判定(LM文脈なしの構造部分): 漢字+ひらがな混在で、かな部分が読みの一部、
    // 漢字部分がより漢字数の多い同読み全漢字候補の部分列(まん延←蔓延/作ひん←作品)。
    // 申し込み(漢字部分==申込 で同数)や送り仮名違いは対象外。
    static func mazegakiKanjiPart(_ surface: String, reading: String) -> String? {
        guard !mazegakiAllowlistedSurfaces.contains(surface) else { return nil }
        var kanji = ""
        var kana = ""
        for scalar in surface.unicodeScalars {
            switch scalar.value {
            case 0x4E00...0x9FFF, 0x3005:
                kanji.unicodeScalars.append(scalar)
            case 0x3041...0x3096, 0x30FC:
                kana.unicodeScalars.append(scalar)
            default:
                return nil // カタカナ・記号混在は対象外
            }
        }
        // かな部分1文字は 中の/夏は/何の 等の正当な 漢字+助詞・送り仮名 合成と区別できないため対象外
        guard !kanji.isEmpty, kana.count >= 2, reading.contains(kana) else { return nil }
        return kanji
    }

    // 混在表層のカタカナ連が seed 掲載の正当カタカナ語(イカ 等)なら強調ではない(イカの 保護)。
    static func katakanaRunsAreSeedProtected(_ surface: String) -> Bool {
        var run = ""
        var sawRun = false
        func flush() -> Bool {
            guard !run.isEmpty else { return true }
            sawRun = true
            guard let hira = hiraganizedKanaOnlySurface(run) else { return false }
            let protected_ = KanaKanjiSeedDictionary.seed[hira]?.contains(run) ?? false
            run = ""
            return protected_
        }
        for scalar in surface.unicodeScalars {
            if (0x30A1...0x30F6).contains(scalar.value) {
                run.unicodeScalars.append(scalar)
            } else {
                if !flush() { return false }
            }
        }
        if !flush() { return false }
        return sawRun
    }

    static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var it = haystack.unicodeScalars.makeIterator()
        outer: for n in needle.unicodeScalars {
            while let h = it.next() {
                if h == n { continue outer }
            }
            return false
        }
        return true
    }
}
