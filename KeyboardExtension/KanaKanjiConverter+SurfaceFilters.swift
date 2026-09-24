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

    // か+ない で始まる素通り連鎖(空士かない/石かない/医師かない)は名詞にも用言にも付かない形
    // (否定の 書かない は活用規則、食うしかない は しか+ない が担う)。BFS は長い語幹を先に
    // 処理するため 空士(くうし)+かない が 食う+しか+ない より前に出ていた(2723)。
    // あるかないか(か+ない+か)は正当なので かないか… は対象外
    static func isImpossibleKaNaiPostfixChain(_ suffix: String) -> Bool {
        guard suffix.hasPrefix("かな") else { return false }
        if suffix.hasPrefix("かないか") { return false }
        return suffix.hasPrefix("かない") || suffix.hasPrefix("かなかった") || suffix.hasPrefix("かなく")
            || suffix.hasPrefix("かなければ") || suffix.hasPrefix("かなきゃ")
    }

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

    // 格助詞・係助詞。用言に付く場合は連用形(一段の 立て/五段の 立ち)が受け皿で、
    // 五段のえ段(命令形・仮定形の語幹)には付かない。
    static let caseParticlePostfixSuffixes: Set<String> = [
        "に", "を", "が", "へ", "で", "と", "は", "も", "の", "から", "まで", "より", "には", "では", "とは"
    ]

    // 読みの末尾がえ段か(五段のえ段判定の前段)。
    private static func endsWithEDanKana(_ reading: String) -> Bool {
        guard let last = reading.last else {
            return false
        }
        return "えけげせぜてでねへべぺめれ".contains(last)
    }

    // 五段動詞のえ段(命令形・仮定形の語幹)に格助詞を付ける合成を弾く。
    //
    // たて の候補には 経て/断て/裁て/佇て/絶て/截て(いずれも五段カ行/タ行のえ段)が
    // 単独候補として供給されており、接尾機構が素通しで に を付けて 経てに/断てに… を
    // 作っていた。同じ理由で うてに→打てに/撃てに/討てに も出る系統的な誤活用
    // (ユーザ報告 2755)。え段+ば(たてば→断てば)は仮定形として正しいので触らない。
    //
    // 一段動詞の連用形は同じ表層でも正当(立てる→立てに行く)なので、候補ごとに
    // 「一段の基底(語幹+る)が辞書にあるか」で判定する。
    func filterGodanEDanStemsForCaseParticle(
        _ candidates: [String],
        stemReading: String,
        nextSuffix: String
    ) -> [String] {
        guard Self.caseParticlePostfixSuffixes.contains(nextSuffix),
            Self.endsWithEDanKana(stemReading) else {
            return candidates
        }

        // 語幹読みに対応する五段の辞書形(たて→たつ)と一段の辞書形(たて→たてる)。
        let godanBaseReading = String(stemReading.dropLast()) + Self.uDanForEDan(stemReading.last!)
        let ichidanBaseReading = stemReading + "る"
        let godanMetadata = inflectionMetadata(for: godanBaseReading)
        let ichidanMetadata = inflectionMetadata(for: ichidanBaseReading)
        guard godanMetadata.hasMetadata else {
            return candidates
        }

        return candidates.filter { candidate in
            // その表層が五段の活用形として説明できるか(断て→断つ)。
            // え段の1文字を辞書形のう段へ置き換える(追加ではない)。
            guard !candidate.isEmpty else {
                return true
            }
            let godanBase = String(candidate.dropLast()) + Self.dictionaryFormTail(for: stemReading)
            let isGodanEDan = godanMetadata.classMap[godanBase]?.hasPrefix("godan-") == true
            guard isGodanEDan else {
                return true
            }
            // 同じ表層が一段の連用形としても説明できるなら正当(立て→立てる)
            let ichidanBase = candidate + "る"
            return ichidanMetadata.classMap[ichidanBase] == InflectionClass.ichidan
        }
    }

    // え段かなに対応するう段かな(五段の辞書形末尾)。
    private static func uDanForEDan(_ character: Character) -> String {
        switch character {
        case "え": return "う"
        case "け": return "く"
        case "げ": return "ぐ"
        case "せ": return "す"
        case "ぜ": return "ず"
        case "て": return "つ"
        case "で": return "づ"
        case "ね": return "ぬ"
        case "へ": return "ふ"
        case "べ": return "ぶ"
        case "ぺ": return "ぷ"
        case "め": return "む"
        case "れ": return "る"
        default: return ""
        }
    }

    // 表層を五段の辞書形に戻すための末尾(断て→断つ の つ)。
    private static func dictionaryFormTail(for stemReading: String) -> String {
        guard let last = stemReading.last else {
            return ""
        }
        return uDanForEDan(last)
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
    // 値はルールのコピーでなく allInflectionRules の添字(構造体の3重保持を避ける。2719)
    static let deinflectionRulesByReadingLastCharacter: [Character: [Int]] = {
        var buckets: [Character: [Int]] = [:]
        for (index, rule) in allInflectionRules.enumerated() {
            guard let last = rule.readingSuffix.last else {
                continue
            }
            buckets[last, default: []].append(index)
        }
        return buckets
    }()
    static let deinflectionRulesWithEmptyReadingSuffix: [InflectionRule] =
        allInflectionRules.filter { $0.readingSuffix.isEmpty }
    static let deinflectionRuleIndicesWithEmptyReadingSuffix: [Int] =
        allInflectionRules.indices.filter { allInflectionRules[$0].readingSuffix.isEmpty }

    // 読みに適用し得る活用ルールの添字列(定義順を保存)。readingSuffix の末尾文字が読みの末尾と
    // 一致するルールと、空 readingSuffix のルール(どの読みにも掛かる)を添字昇順に併合する。
    // 全ルール(約850件)の線形走査は removingSuffix(hasSuffix)が支配的で、連文節は span ごとに
    // 呼ぶため活用派生が処理時間の6割を占めていた(2805 プロファイル)。結果は全走査と同一
    // 併合済みの添字列を末尾文字ごとに前計算しておく(3201)。入力が Character だけの純関数なので
    // 呼ぶたびに作る必要が無い。ここは連文節の span ごとに呼ばれ、確保センサスで打鍵 1 回あたり
    // 4KB 超の確保 3 個(=アリーナが 4MB 刻みで伸びる側の大きさ)を占めていた
    static let mergedInflectionRuleIndicesByReadingLastCharacter: [Character: [Int]] = {
        let empty = deinflectionRuleIndicesWithEmptyReadingSuffix
        var table: [Character: [Int]] = [:]
        table.reserveCapacity(deinflectionRulesByReadingLastCharacter.count)
        for (last, matched) in deinflectionRulesByReadingLastCharacter {
            if empty.isEmpty {
                table[last] = matched
                continue
            }
            var merged: [Int] = []
            merged.reserveCapacity(matched.count + empty.count)
            var i = 0, j = 0
            while i < matched.count || j < empty.count {
                if j >= empty.count || (i < matched.count && matched[i] < empty[j]) {
                    merged.append(matched[i]); i += 1
                } else {
                    merged.append(empty[j]); j += 1
                }
            }
            table[last] = merged
        }
        return table
    }()

    static func candidateInflectionRuleIndices(forReadingEndingWith last: Character?) -> [Int] {
        guard let last, let merged = mergedInflectionRuleIndicesByReadingLastCharacter[last] else {
            return deinflectionRuleIndicesWithEmptyReadingSuffix
        }
        return merged
    }
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
        // 候補ごとに呼ばれるので確保を避ける(3096): 読みを Array にせず String.Index で切り、末尾一致は
        // Substring 同士で見る。読み前方の String 化(辞書の鍵)と候補先頭の String 化は一致したときだけ
        let readingCount = reading.count
        guard readingCount >= 2 else {
            return false
        }
        let candidateCount = candidate.count
        var splitIndex = reading.index(after: reading.startIndex)
        var prefixLength = 1
        while prefixLength < readingCount {
            let tail = reading[splitIndex...]
            let tailCount = readingCount - prefixLength
            if candidateCount > tailCount, candidate.hasSuffix(tail),
                let suppressedSet = suppressedByReading[String(reading[..<splitIndex])] {
                let headEnd = candidate.index(candidate.endIndex, offsetBy: -tailCount)
                if suppressedSet.contains(String(candidate[..<headEnd])) {
                    return true
                }
            }
            splitIndex = reading.index(after: splitIndex)
            prefixLength += 1
        }
        return false
    }

    // 読み側で決まる部分(どの活用ルールが読みに掛かり、その基底読みに抑制があるか)を先に絞った探針。
    // 候補ごとの判定は探針列に対する hasSuffix と Set 参照だけになる。以前は候補 1 件ごとに
    // 末尾文字バケット(る/た 等で百件規模)を全部なめ直していて、単文節候補取得の 2 割を占めた(2805)
    struct DeinflectionSuppressionProbe {
        let candidateSuffix: String        // 候補側の末尾(outputCandidateSuffix or 可能動詞の readingSuffix)
        let suppressedSet: Set<String>     // 基底読みの抑制集合
        let baseCandidateSuffixes: [String] // 候補語幹に付けて抑制集合を引く接尾(可能動詞は baseReadingSuffix 1 本)
    }

    func deinflectionSuppressionProbes(
        reading: String,
        suppressedByReading: [String: Set<String>]
    ) -> [DeinflectionSuppressionProbe] {
        guard !suppressedByReading.isEmpty, let readingLastCharacter = reading.last else {
            return []
        }
        var probes: [DeinflectionSuppressionProbe] = []

        func addProbe(for rule: InflectionRule) {
            guard reading.hasSuffix(rule.readingSuffix) else { return }
            let readingStem = String(reading.dropLast(rule.readingSuffix.count))
            if readingStem.isEmpty,
                !Self.emptyStemAllowedBaseReadingSuffixes.contains(rule.baseReadingSuffix) {
                return
            }
            guard let suppressedSet = suppressedByReading[readingStem + rule.baseReadingSuffix],
                !suppressedSet.isEmpty else {
                return
            }
            var suffixes: [String] = []
            rule.forEachBaseCandidateSuffix { suffixes.append($0) }
            probes.append(DeinflectionSuppressionProbe(
                candidateSuffix: rule.outputCandidateSuffix,
                suppressedSet: suppressedSet,
                baseCandidateSuffixes: suffixes
            ))
        }

        for index in Self.deinflectionRulesByReadingLastCharacter[readingLastCharacter] ?? [] {
            addProbe(for: Self.allInflectionRules[index])
        }
        for rule in Self.deinflectionRulesWithEmptyReadingSuffix {
            addProbe(for: rule)
        }
        for mapping in Self.godanPotentialDeinflectionMappingsByReadingLastCharacter[readingLastCharacter] ?? [] {
            guard reading.hasSuffix(mapping.readingSuffix) else { continue }
            let readingStem = String(reading.dropLast(mapping.readingSuffix.count))
            guard !readingStem.isEmpty,
                let suppressedSet = suppressedByReading[readingStem + mapping.baseReadingSuffix] else {
                continue
            }
            probes.append(DeinflectionSuppressionProbe(
                candidateSuffix: mapping.readingSuffix,
                suppressedSet: suppressedSet,
                baseCandidateSuffixes: [mapping.baseReadingSuffix]
            ))
        }
        return probes
    }

    func isDeinflectedSuppressed(candidate: String, probes: [DeinflectionSuppressionProbe]) -> Bool {
        for probe in probes where candidate.hasSuffix(probe.candidateSuffix) {
            let candidateStem = String(candidate.dropLast(probe.candidateSuffix.count))
            for suffix in probe.baseCandidateSuffixes where probe.suppressedSet.contains(candidateStem + suffix) {
                return true
            }
        }
        return false
    }


    // 否定の助動詞 ない 系(ない/なく/なかった/なくて/なければ/なきゃ)は用言の終止形には付かない
    // (動詞は未然形+ない=活用規則が担う、形容詞は 高くない)。postfix 素通り合成が 酸く+なく/漉く+なく
    // (五段カ行の終止形)を組み、すくなく で 少なく(形容詞 少ない の連用形)より前に並んでいた(2731)。
    // 活用クラスを持つ語幹(動詞・形容詞)を除外し、名詞(問題ない/仕方なく)とかな識別は残す。
    // サ変名詞(勉強)はクラス suru を持つが名詞なので除外しない
    static func isNegativeAuxiliaryPostfixSuffix(_ suffix: String) -> Bool {
        guard suffix.hasPrefix("な") else { return false }
        return suffix.hasPrefix("ない") || suffix.hasPrefix("なく") || suffix.hasPrefix("なかっ")
            || suffix.hasPrefix("なけれ") || suffix.hasPrefix("なきゃ")
    }

    func filterConjugableStemsForNegativeAuxiliaryPostfix(
        _ candidates: [String],
        stemReading: String,
        nextSuffix: String
    ) -> [String] {
        guard Self.isNegativeAuxiliaryPostfixSuffix(nextSuffix) else {
            return candidates
        }
        let metadata = inflectionMetadata(for: stemReading)
        guard metadata.hasMetadata else {
            return candidates
        }
        return candidates.filter { candidate in
            guard candidate != stemReading else { return true }
            if let className = metadata.classMap[candidate] {
                return className == InflectionClass.suru
            }
            // クラス表に無くても「漢字+活用語尾かな」の表層(酸く=酸い の連用形、漉く 等の収穫)は用言形。
            // 名詞(問題/仕方/例外)は末尾が漢字なので対象外
            if let last = candidate.last, containsKanji(candidate),
                Self.predicateStemEndingKana.contains(last) {
                return false
            }
            return true
        }
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
            combinedUserCandidates(for: stemReading, ajoutVocabulary: store.ajoutVocabulary())
        ).union(store.initialAjoutVocabulary()[normalizedStemReading] ?? [])

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
    // 助詞で始まる読みを持つ稀な動詞(煮含む=にふくむ/賭する=とする)が、文頭や述語直後で
    // 助詞ごと飲み込む問題(2879、抜き取り検査)。「にふくまれる」が 煮含まれる、
    // 「〜だとされています」が 〜だ賭されています になっていた。活用派生は OOV 定額なので
    // 1 ノードで span を覆うほうが 助詞+動詞 の 2 ノードより安くなる。
    // 「頭の漢字が助詞1字として読めるか」で機械判定すると 似た/煮た/出ない まで巻き込む
    // (どれも 似=に/煮=に/出=で が word_costs にある)。基底が LM 未収録かで切りたいが
    // DP 側から基底が引けないため、実害のあった語幹だけを列挙する
    // 徒渉/渡渉(としょう=と+称 を飲む。としょうされています→徒渉されています。2884、抜き取り検査)
    static let multiClauseParticleSwallowingVerbSurfacePrefixes: Set<String> = [
        "煮含", "煮ふく", "賭し", "賭さ", "賭す", "賭せ", "徒渉", "渡渉"
    ]

    func isParticleHeadedRareVerb(surface: String, reading: String, isInflectionDerived: Bool) -> Bool {
        guard isInflectionDerived, surface.count >= 2, reading.count >= 2,
            let particleChar = reading.first,
            KanaKanjiConverter.multiClauseParticleReadingsForClauseHeadGuard.contains(String(particleChar)) else {
            return false
        }
        return KanaKanjiConverter.multiClauseParticleSwallowingVerbSurfacePrefixes.contains {
            surface.hasPrefix($0)
        }
    }

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
    // 拗音の小書きかなは前のかなと1モーラを成す。文字数で数えると ぎょう(経)が3字となり
    // 「読み3字以上は複合語の後部」の判定をすり抜ける(行変える→経変える。2879)
    static let smallKanaCharacters: Set<Character> = [
        "ゃ", "ゅ", "ょ", "ぁ", "ぃ", "ぅ", "ぇ", "ぉ",
        "ャ", "ュ", "ョ", "ァ", "ィ", "ゥ", "ェ", "ォ"
    ]

    static func moraCount(of reading: String) -> Int {
        reading.count { !smallKanaCharacters.contains($0) }
    }

    func isRendakuHarvestSurface(
        _ surface: String,
        reading: String,
        includingMultiCharacterSurfaces: Bool = false
    ) -> Bool {
        // ラティス供給側(既定)は「読みが2字以下」の連濁だけ弾く(2879、ユーザー指摘)。
        // 危ないのは 歯(ば)/墓(ばか)/口(ぐち)/棚(だな)/種(だね) のように読みが短く、
        // 助詞・終助詞・口語と正面衝突するもの(単漢字531件のうち397件が読み2字)。
        // 読み3字以上(畑=ばたけ/桜=ざくら/柱=ばしら/頭=がしら、134件)は複合語の後部そのもので、
        // 弾くと ぶどう畑/山桜/電信柱 が組めない。表層が単漢字かどうかは本質ではなかった
        guard reading.count >= 2,
            includingMultiCharacterSurfaces
                ? Self.containsKanjiCandidate(surface)
                : (Self.isSingleKanjiCandidate(surface) && Self.moraCount(of: reading) <= 2),
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

    // 漢字だけで構成される表層(漢語の複合判定用)。空文字は false
    static func isKanjiOnlyString(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        return text.unicodeScalars.allSatisfy {
            (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value)
        }
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

    // 旧字体・異体字 → 現代の標準字体。小分類ごとにコンテナー設定でオン/オフする(2991)。
    // 抑制は「同じ読みに標準字体版の候補が実在するとき」だけで、標準字体版が無い固有名詞
    // (和氣あず未/國場組/守禮門/魚香肉絲 等)はそのまま残る。人名(Sudachi の姓/名)は
    // 分類に関わらず常に対象外(小野澤/千惠/眞子)。
    struct ScriptVariantMapping {
        let standard: Character
        let category: ScriptVariantSuppressionCategory
        init(_ standard: Character, _ category: ScriptVariantSuppressionCategory) {
            self.standard = standard
            self.category = category
        }
    }

    static let scriptVariantToStandard: [Character: ScriptVariantMapping] = [
        // 旧字体(康熙字体)
        "亞": .init("亜", .kyujitai), "惡": .init("悪", .kyujitai), "壓": .init("圧", .kyujitai), "圍": .init("囲", .kyujitai), "醫": .init("医", .kyujitai), "飮": .init("飲", .kyujitai), "隱": .init("隠", .kyujitai), "榮": .init("栄", .kyujitai),
        "營": .init("営", .kyujitai), "衞": .init("衛", .kyujitai), "驛": .init("駅", .kyujitai), "圓": .init("円", .kyujitai), "緣": .init("縁", .kyujitai), "應": .init("応", .kyujitai), "歐": .init("欧", .kyujitai), "毆": .init("殴", .kyujitai),
        "穩": .init("穏", .kyujitai), "假": .init("仮", .kyujitai), "價": .init("価", .kyujitai), "畫": .init("画", .kyujitai), "會": .init("会", .kyujitai), "壞": .init("壊", .kyujitai), "懷": .init("懐", .kyujitai), "樂": .init("楽", .kyujitai),
        "學": .init("学", .kyujitai), "陷": .init("陥", .kyujitai), "勸": .init("勧", .kyujitai), "卷": .init("巻", .kyujitai), "寬": .init("寛", .kyujitai), "歡": .init("歓", .kyujitai), "關": .init("関", .kyujitai), "氣": .init("気", .kyujitai),
        "歸": .init("帰", .kyujitai), "犧": .init("犠", .kyujitai), "舊": .init("旧", .kyujitai), "據": .init("拠", .kyujitai), "擧": .init("挙", .kyujitai), "峽": .init("峡", .kyujitai), "狹": .init("狭", .kyujitai), "鄕": .init("郷", .kyujitai),
        "曉": .init("暁", .kyujitai), "區": .init("区", .kyujitai), "驅": .init("駆", .kyujitai), "軀": .init("躯", .kyujitai),"勳": .init("勲", .kyujitai), "徑": .init("径", .kyujitai), "惠": .init("恵", .kyujitai), "經": .init("経", .kyujitai), "繼": .init("継", .kyujitai),
        "莖": .init("茎", .kyujitai), "螢": .init("蛍", .kyujitai), "輕": .init("軽", .kyujitai), "藝": .init("芸", .kyujitai), "缺": .init("欠", .kyujitai), "儉": .init("倹", .kyujitai), "劍": .init("剣", .kyujitai), "圈": .init("圏", .kyujitai),
        "檢": .init("検", .kyujitai), "權": .init("権", .kyujitai), "獻": .init("献", .kyujitai), "縣": .init("県", .kyujitai), "險": .init("険", .kyujitai), "顯": .init("顕", .kyujitai), "驗": .init("験", .kyujitai), "嚴": .init("厳", .kyujitai),
        "效": .init("効", .kyujitai), "廣": .init("広", .kyujitai), "鑛": .init("鉱", .kyujitai), "號": .init("号", .kyujitai), "國": .init("国", .kyujitai), "濟": .init("済", .kyujitai), "碎": .init("砕", .kyujitai), "齋": .init("斎", .kyujitai),
        "齊": .init("斉", .kyujitai), "雜": .init("雑", .kyujitai), "參": .init("参", .kyujitai), "慘": .init("惨", .kyujitai), "棧": .init("桟", .kyujitai), "贊": .init("賛", .kyujitai), "殘": .init("残", .kyujitai), "齒": .init("歯", .kyujitai),
        "兒": .init("児", .kyujitai), "辭": .init("辞", .kyujitai), "濕": .init("湿", .kyujitai), "實": .init("実", .kyujitai), "舍": .init("舎", .kyujitai), "寫": .init("写", .kyujitai), "釋": .init("釈", .kyujitai), "壽": .init("寿", .kyujitai),
        "收": .init("収", .kyujitai), "從": .init("従", .kyujitai), "澁": .init("渋", .kyujitai), "獸": .init("獣", .kyujitai), "縱": .init("縦", .kyujitai), "肅": .init("粛", .kyujitai), "處": .init("処", .kyujitai), "燒": .init("焼", .kyujitai),
        "將": .init("将", .kyujitai), "稱": .init("称", .kyujitai), "證": .init("証", .kyujitai), "乘": .init("乗", .kyujitai), "剩": .init("剰", .kyujitai), "壤": .init("壌", .kyujitai), "孃": .init("嬢", .kyujitai), "條": .init("条", .kyujitai),
        "淨": .init("浄", .kyujitai), "疊": .init("畳", .kyujitai), "讓": .init("譲", .kyujitai), "釀": .init("醸", .kyujitai), "囑": .init("嘱", .kyujitai), "觸": .init("触", .kyujitai), "寢": .init("寝", .kyujitai), "愼": .init("慎", .kyujitai),
        "眞": .init("真", .kyujitai), "盡": .init("尽", .kyujitai), "圖": .init("図", .kyujitai), "粹": .init("粋", .kyujitai), "醉": .init("酔", .kyujitai), "隨": .init("随", .kyujitai), "髓": .init("髄", .kyujitai), "數": .init("数", .kyujitai),
        "樞": .init("枢", .kyujitai), "瀨": .init("瀬", .kyujitai), "靜": .init("静", .kyujitai), "攝": .init("摂", .kyujitai), "竊": .init("窃", .kyujitai), "專": .init("専", .kyujitai), "戰": .init("戦", .kyujitai), "淺": .init("浅", .kyujitai),
        "潛": .init("潜", .kyujitai), "纖": .init("繊", .kyujitai), "踐": .init("践", .kyujitai), "錢": .init("銭", .kyujitai), "禪": .init("禅", .kyujitai), "雙": .init("双", .kyujitai), "壯": .init("壮", .kyujitai), "搜": .init("捜", .kyujitai),
        "插": .init("挿", .kyujitai), "巢": .init("巣", .kyujitai), "爭": .init("争", .kyujitai), "總": .init("総", .kyujitai), "莊": .init("荘", .kyujitai), "裝": .init("装", .kyujitai), "藏": .init("蔵", .kyujitai), "臟": .init("臓", .kyujitai),
        "屬": .init("属", .kyujitai), "續": .init("続", .kyujitai), "墮": .init("堕", .kyujitai), "體": .init("体", .kyujitai), "對": .init("対", .kyujitai), "帶": .init("帯", .kyujitai), "滯": .init("滞", .kyujitai), "臺": .init("台", .kyujitai),
        "擇": .init("択", .kyujitai), "澤": .init("沢", .kyujitai), "擔": .init("担", .kyujitai), "單": .init("単", .kyujitai), "團": .init("団", .kyujitai), "彈": .init("弾", .kyujitai), "斷": .init("断", .kyujitai), "癡": .init("痴", .kyujitai),
        "遲": .init("遅", .kyujitai), "晝": .init("昼", .kyujitai), "蟲": .init("虫", .kyujitai), "鑄": .init("鋳", .kyujitai), "廳": .init("庁", .kyujitai), "徵": .init("徴", .kyujitai), "聽": .init("聴", .kyujitai), "鎭": .init("鎮", .kyujitai),
        "轉": .init("転", .kyujitai), "傳": .init("伝", .kyujitai), "燈": .init("灯", .kyujitai), "當": .init("当", .kyujitai), "黨": .init("党", .kyujitai), "盜": .init("盗", .kyujitai), "稻": .init("稲", .kyujitai), "德": .init("徳", .kyujitai),
        "獨": .init("独", .kyujitai), "讀": .init("読", .kyujitai), "屆": .init("届", .kyujitai), "繩": .init("縄", .kyujitai), "拜": .init("拝", .kyujitai), "賣": .init("売", .kyujitai), "髮": .init("髪", .kyujitai), "拔": .init("抜", .kyujitai),
        "蠻": .init("蛮", .kyujitai), "濱": .init("浜", .kyujitai), "佛": .init("仏", .kyujitai), "拂": .init("払", .kyujitai), "變": .init("変", .kyujitai), "辨": .init("弁", .kyujitai), "瓣": .init("弁", .kyujitai), "辯": .init("弁", .kyujitai),
        "寶": .init("宝", .kyujitai), "豐": .init("豊", .kyujitai), "萬": .init("万", .kyujitai), "滿": .init("満", .kyujitai), "麥": .init("麦", .kyujitai), "默": .init("黙", .kyujitai), "藥": .init("薬", .kyujitai), "譯": .init("訳", .kyujitai),
        "豫": .init("予", .kyujitai), "餘": .init("余", .kyujitai), "與": .init("与", .kyujitai), "譽": .init("誉", .kyujitai), "搖": .init("揺", .kyujitai), "樣": .init("様", .kyujitai), "謠": .init("謡", .kyujitai), "來": .init("来", .kyujitai),
        "賴": .init("頼", .kyujitai), "亂": .init("乱", .kyujitai), "覽": .init("覧", .kyujitai), "兩": .init("両", .kyujitai), "獵": .init("猟", .kyujitai), "綠": .init("緑", .kyujitai), "淚": .init("涙", .kyujitai), "壘": .init("塁", .kyujitai),
        "勵": .init("励", .kyujitai), "禮": .init("礼", .kyujitai), "靈": .init("霊", .kyujitai), "齡": .init("齢", .kyujitai), "曆": .init("暦", .kyujitai), "歷": .init("歴", .kyujitai), "戀": .init("恋", .kyujitai), "爐": .init("炉", .kyujitai),
        "勞": .init("労", .kyujitai), "樓": .init("楼", .kyujitai), "灣": .init("湾", .kyujitai), "惱": .init("悩", .kyujitai), "腦": .init("脳", .kyujitai), "廢": .init("廃", .kyujitai),
        // 異体字(印刷標準字体レベルの差)
        "揭": .init("掲", .itaiji), "溪": .init("渓", .itaiji), "恆": .init("恒", .itaiji), "絲": .init("糸", .itaiji), "緖": .init("緒", .itaiji), "奬": .init("奨", .itaiji), "敕": .init("勅", .itaiji), "祕": .init("秘", .itaiji),
        "舖": .init("舗", .itaiji), "步": .init("歩", .itaiji), "夛": .init("多", .itaiji), "沒": .init("没", .itaiji), "飜": .init("翻", .itaiji), "每": .init("毎", .itaiji), "晚": .init("晩", .itaiji), "顏": .init("顔", .itaiji), "卽": .init("即", .itaiji),
        "狀": .init("状", .itaiji),
        // 略字
        "仝": .init("同", .ryakuji), "卆": .init("卒", .ryakuji),
        // 紛らわしい別字
        "聯": .init("連", .confusable), "聨": .init("連", .confusable),
        // 人名で生きている異体字(初期設定はオフ)
        "邊": .init("辺", .personNameVariant), "邉": .init("辺", .personNameVariant), "龍": .init("竜", .personNameVariant), "瀧": .init("滝", .personNameVariant), "嶋": .init("島", .personNameVariant), "嶌": .init("島", .personNameVariant), "曾": .init("曽", .personNameVariant), "彌": .init("弥", .personNameVariant),
        "髙": .init("高", .personNameVariant), "﨑": .init("崎", .personNameVariant), "栁": .init("柳", .personNameVariant), "濵": .init("浜", .personNameVariant), "桒": .init("桑", .personNameVariant), "槇": .init("槙", .personNameVariant), "籔": .init("藪", .personNameVariant)
    ]

    // 新字体版が辞書にあっても残す旧字体(固有名詞・原語表記)。plist 登録(補助語彙/追加語彙)や
    // seed で守れないものだけをここに置く
    static let scriptVariantKeepSurfaces: Set<String> = [
        // 台灣: 繁体字の国名表記。台湾 が辞書にあるため一括抑制の対象になるが、原語表記として残す(2529/2531 の並びを維持)
        "台灣"
    ]

    // 有効な分類の旧字体・異体字を含むなら標準字体へ写した表層、含まないなら nil
    static func standardizedScriptVariantSurface(
        _ surface: String,
        categories: Set<ScriptVariantSuppressionCategory>
    ) -> String? {
        func mapped(_ character: Character) -> Character? {
            guard let mapping = scriptVariantToStandard[character],
                categories.contains(mapping.category) else {
                return nil
            }
            return mapping.standard
        }
        guard surface.contains(where: { mapped($0) != nil }) else {
            return nil
        }
        return String(surface.map { mapped($0) ?? $0 })
    }
    // かな踊り字(繰り返し記号)。ゝ/ゞ(ひらがな)・ヽ/ヾ(カタカナ)。設定「仮名の踊り字の候補を含める」で
    // 制御(旧仮名遣いとは独立)。※漢字の 々(人々/時々 等で正当)は除外。
    static let iterationMarkScalars: Set<Character> = ["ゝ", "ゞ", "ヽ", "ヾ"]

    func filterHistoricalKanaSurfaceCandidates(
        for reading: String,
        candidates: [String]
    ) -> [String] {
        let (historicalAllowed, iterationAllowed) = withStateLock {
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
            ajoutVocabulary: nil,
            learnedDictionary: nil,
            initialAjoutVocabulary: nil
        )
    }

    func filterArchaicAdjectiveSurfaceCandidates(
        for reading: String,
        candidates: [String],
        ajoutVocabulary: [String: [String]]?,
        learnedDictionary: [String: [String]]?,
        initialAjoutVocabulary: [String: [String]]?
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
        let userBaseCandidates = ajoutVocabulary?[baseReading] ?? []
        let learnedBaseCandidates = learnedDictionary?[baseReading] ?? []
        let initialBaseCandidates = initialAjoutVocabulary?[baseReading] ?? []
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
        if (store.ajoutVocabulary()[reading] ?? []).contains(candidate)
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
        // 比較対象はかな識別だけでなく、同読みの漢字を含む表層(気持ち 等の送り仮名付き
        // 標準表記)も含める(単文節側と同基準。2987)
        let kanjiBearingAlternatives = readingWordCosts.keys.filter { Self.containsKanjiCandidate($0) }
        let uni = store.wordLMUnigramCosts(for: [candidate, reading] + kanjiBearingAlternatives)
        if let kataUni = uni[candidate] {
            // カタカナ側が LM 収録: かな識別・漢字表記のどれよりも安ければ正当な外来語表記(パン 等)
            let altBest = (kanjiBearingAlternatives.compactMap { uni[$0] } + [uni[reading]].compactMap { $0 }).min()
            guard let altBest else {
                return false
            }
            return altBest < kataUni
        }
        // LM 未収録のカタカナ化は、かな/漢字の代替が実在する限り強調(単語単位と同基準)
        return uni[reading] != nil
            || store.wordCosts(for: reading).keys.contains { Self.containsKanjiCandidate($0) }
    }
    // 定着した交ぜ書き(常用漢字外回避ではなく主流表記になっているもの)。分類から除外する。
    // 交ぜ書き判定の許可リスト。漢字+かな混在だが現代の標準表記であるもの。
    // 今まで は 今迄(旧表記・全漢字)が辞書にあるため交ぜ書き扱いで抑制されていた(2455)。
    static let mazegakiAllowlistedSurfaces: Set<String> = [
        "子ども", "子どもたち", "子どもの日", "今まで",
        // 正当な送り仮名語が同読み全漢字語の部分列に誤マッチしていた(2637):
        // 長らく←長楽、向かい←向井
        "長らく", "向かい"
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
