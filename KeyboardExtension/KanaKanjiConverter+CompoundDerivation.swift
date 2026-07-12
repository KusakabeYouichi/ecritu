import Foundation

// 複合語派生: 数詞+助数詞・大数位・分数・序数(〜つ目)・名詞+漢字接辞(課/可/別 等)。
extension KanaKanjiConverter {
    static let numericUnitFallbackCandidatesByReading: [String: [String]] = [
        "せんえん": ["千円"],
        "まんえん": ["万円"],
        "おくえん": ["億円"],
        "ちょうえん": ["兆円"]
    ]

    static let numericCounterPrefixCandidatesByReading: [String: [String]] = [
        "いっ": ["一"],
        "きゅう": ["九"],
        "ご": ["五"],
        "さん": ["三"],
        "じっ": ["十"],
        "じゅっ": ["十"],
        "に": ["二"],
        "なな": ["七"],
        "なん": ["何"],
        "はっ": ["八"],
        "よん": ["四"],
        "ろっ": ["六"],
        "すう": ["数"]
    ]

    static let numericCounterSuffixCandidatesByReading: [String: [String]] = [
        "こ": ["個"],
        "えん": ["円"],
        "かい": ["回"],
        "かげつ": ["か月", "カ月", "ヶ月", "ヵ月", "箇月"],
        "かしょ": ["か所", "箇所", "カ所", "ヶ所", "ヵ所"],
        "けん": ["軒", "件"],
        "しゅうかん": ["週間"],
        "じかん": ["時間"],
        "じつ": ["日"],
        "にち": ["日"],
        "だい": ["台"],
        "にん": ["人"],
        "ねん": ["年"],
        "ほん": ["本"],
        "びょう": ["秒"],
        "ふん": ["分"],
        "ぷん": ["分"],
        "ひき": ["匹"],
        "ぼん": ["本"],
        "びき": ["匹"],
        "まい": ["枚"],
        "ぽん": ["本"],
        "ぴき": ["匹"],
        "はい": ["倍", "杯"],
        "ばい": ["倍"],
        "はつ": ["発"],
        "ぱつ": ["発"]
    ]

    static let numericCounterAllowedSuffixReadingsByPrefixReading: [String: Set<String>] = [
        "いっ": ["ぽん", "ぴき"],
        "きゅう": ["ほん", "ひき"],
        "ご": ["ほん", "ひき"],
        "さん": ["ぼん", "びき"],
        "じっ": ["ぽん", "ぴき"],
        "じゅっ": ["ぽん", "ぴき"],
        "に": ["ほん", "ひき"],
        "なな": ["ほん", "ひき"],
        "なん": [
            "こ", "かい", "かげつ", "かしょ", "けん", "しゅうかん", "じかん", "にち", "だい", "にん", "ねん",
            "はい", "ばい", "はつ", "ぱつ", "びょう", "ぷん", "ぼん", "びき", "まい"
        ],
        "はっ": ["ぽん", "ぴき"],
        "よん": ["ほん", "ひき"],
        "ろっ": ["ぽん", "ぴき"],
        "すう": [
            "こ", "かい", "かげつ", "かしょ", "けん", "しゅうかん", "じかん", "じつ", "だい", "にん", "ねん",
            "はい", "ばい", "はつ", "ぱつ", "びょう", "ふん", "ひき", "ほん", "まい"
        ]
    ]

    // 大数位(桁). 接頭(数/何/数字)と助数詞の間に挟まる「千・百・万…」を表す。
    // 連濁・促音の読み(ぜん/びゃく/ぴゃく等)も含め、読み一致で正しい組のみ生成する。
    static let numericMagnitudeCandidatesByReading: [(reading: String, candidate: String)] = [
        ("せん", "千"), ("ぜん", "千"),
        ("ひゃく", "百"), ("びゃく", "百"), ("ぴゃく", "百"),
        ("まん", "万"),
        ("おく", "億"),
        ("ちょう", "兆"),
        ("じゅう", "十")
    ]

    // 「分の一」等の分数末尾。助数詞の「分(ふん/ぷん)」とは読み(ぶん)で区別される。
    static let numericFractionSuffixCandidatesByReading: [String: [String]] = [
        "ぶんのいち": ["分の一"]
    ]

    // 名詞に付く生産的な漢字接尾辞(種類別・色別・国別…)。語幹(名詞)+接尾辞漢字。
    // か: 予約課/入場可/自動化/情報科/管理下 のような複合は SudachiDict に単語として
    //     載らないことが多いため、ここで派生させる(家/歌/価 は既存語が辞書にあり非生産的)。
    static let nounKanjiSuffixAffixCandidatesByReading: [(reading: String, candidate: String)] = [
        ("べつ", "別"),
        ("か", "課"),
        ("か", "可"),
        ("か", "化"),
        ("か", "科"),
        ("か", "下")
    ]

    // 名詞に付く生産的な漢字接頭辞(別会社・別人物・別商品…)。接頭辞漢字+語幹(名詞)。
    static let nounKanjiPrefixAffixCandidatesByReading: [(reading: String, candidate: String)] = [
        ("べつ", "別")
    ]

    func ordinalMeFallbackCandidates(
        for reading: String,
        hasDirectCandidates: Bool,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode,
        limit: Int
    ) -> [String] {
        guard !hasDirectCandidates,
            reading.count >= 2,
            reading.hasSuffix("め"),
            limit > 0 else {
            return []
        }

        let stem = String(reading.dropLast(1))

        guard !stem.isEmpty else {
            return []
        }

        var stemCandidates = uniqueCandidates(
            from: candidatesForReading(
                stem,
                userDictionary: userDictionary,
                initialUserDictionary: initialUserDictionary,
                systemCandidateMode: systemCandidateMode
            ) + inflectionCandidates(
                for: stem,
                userDictionary: userDictionary,
                initialUserDictionary: initialUserDictionary,
                systemCandidateMode: systemCandidateMode,
                limit: limit
            )
        )

        if stemCandidates.isEmpty {
            let trimmedStem = trimmingLeadingNumberPrefix(from: stem)

            if !trimmedStem.isEmpty,
                trimmedStem != stem {
                stemCandidates = uniqueCandidates(
                    from: candidatesForReading(
                        trimmedStem,
                        userDictionary: userDictionary,
                        initialUserDictionary: initialUserDictionary,
                        systemCandidateMode: systemCandidateMode
                    ) + inflectionCandidates(
                        for: trimmedStem,
                        userDictionary: userDictionary,
                        initialUserDictionary: initialUserDictionary,
                        systemCandidateMode: systemCandidateMode,
                        limit: limit
                    )
                )
            }
        }

        guard !stemCandidates.isEmpty else {
            return []
        }

        let kanjiStemCandidates = stemCandidates.filter(containsKanji)
        let nonKanjiStemCandidates = stemCandidates.filter { !containsKanji($0) }

        guard !kanjiStemCandidates.isEmpty else {
            return []
        }

        var derived: [String] = []

        for candidate in kanjiStemCandidates {
            derived.append(candidate + "め")
        }

        for candidate in nonKanjiStemCandidates {
            derived.append(candidate + "め")
        }

        // Keep kanji+"目" candidates available, but behind kanji+"め".
        for candidate in kanjiStemCandidates {
            derived.append(candidate + "目")
        }

        return Array(uniqueCandidates(from: derived).prefix(limit))
    }

    func numericUnitFallbackCandidates(
        for reading: String,
        limit: Int
    ) -> [String] {
        guard limit > 0 else {
            return []
        }

        var lookupKeys = [reading]
        let trimmedReading = trimmingLeadingNumberPrefix(from: reading)

        if !trimmedReading.isEmpty,
            trimmedReading != reading {
            lookupKeys.append(trimmedReading)
        }

        var derived: [String] = []

        for key in lookupKeys {
            if let fallbackCandidates = Self.numericUnitFallbackCandidatesByReading[key] {
                derived.append(contentsOf: fallbackCandidates)
            }
        }

        return Array(uniqueCandidates(from: derived).prefix(limit))
    }

    func numericCounterCompoundCandidates(
        for reading: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode,
        limit: Int
    ) -> [String] {
        guard limit > 0 else {
            return []
        }

        var derived: [String] = []

        for (prefixReading, allowedPrefixes) in Self.numericCounterPrefixCandidatesByReading {
            guard reading.hasPrefix(prefixReading) else {
                continue
            }

            let suffixReading = String(reading.dropFirst(prefixReading.count))

            guard !suffixReading.isEmpty else {
                continue
            }

            if let allowedSuffixReadings = Self.numericCounterAllowedSuffixReadingsByPrefixReading[prefixReading],
                !allowedSuffixReadings.contains(suffixReading) {
                continue
            }

            guard let allowedSuffixes = Self.numericCounterSuffixCandidatesByReading[suffixReading] else {
                continue
            }

            let prefixCandidates = uniqueCandidates(
                from: candidatesForReading(
                    prefixReading,
                    userDictionary: userDictionary,
                    initialUserDictionary: initialUserDictionary,
                    systemCandidateMode: systemCandidateMode
                )
            ).filter { allowedPrefixes.contains($0) }

            let resolvedPrefixCandidates = prefixCandidates.isEmpty
                ? allowedPrefixes
                : prefixCandidates

            let suffixCandidates = uniqueCandidates(
                from: candidatesForReading(
                    suffixReading,
                    userDictionary: userDictionary,
                    initialUserDictionary: initialUserDictionary,
                    systemCandidateMode: systemCandidateMode
                )
            ).filter { allowedSuffixes.contains($0) }

            let resolvedSuffixCandidates = suffixCandidates.isEmpty
                ? allowedSuffixes
                : suffixCandidates

            for prefixCandidate in resolvedPrefixCandidates {
                for suffixCandidate in resolvedSuffixCandidates {
                    derived.append(prefixCandidate + suffixCandidate)
                }
            }
        }

        // 桁(千/百/万…)を挟む汎用パス: 接頭 + 桁+ + (助数詞 | 分の一 | ∅)。
        // 例: すうせんねん→数千年, なんびゃくねん→何百年, すうせんぶんのいち→数千分の一。
        // 接頭直結の助数詞(数年・三本等)は上の既存パスが拗音・連濁制約付きで担当し、
        // ここは必ず桁を1つ以上含む組(または接頭+分の一)のみを生成する。
        for (prefixReading, allowedPrefixes) in Self.numericCounterPrefixCandidatesByReading {
            guard reading.hasPrefix(prefixReading) else {
                continue
            }

            let afterPrefix = String(reading.dropFirst(prefixReading.count))

            guard !afterPrefix.isEmpty else {
                continue
            }

            let prefixCandidates = uniqueCandidates(
                from: candidatesForReading(
                    prefixReading,
                    userDictionary: userDictionary,
                    initialUserDictionary: initialUserDictionary,
                    systemCandidateMode: systemCandidateMode
                )
            ).filter { allowedPrefixes.contains($0) }

            let resolvedPrefixCandidates = prefixCandidates.isEmpty
                ? allowedPrefixes
                : prefixCandidates

            var tailCandidates: [String] = []

            // 桁始まり: 桁+ (助数詞 | 分の一 | ∅)
            for magnitude in Self.numericMagnitudeCandidatesByReading
                where afterPrefix.hasPrefix(magnitude.reading) {
                let afterMagnitude = String(afterPrefix.dropFirst(magnitude.reading.count))

                for tail in numericMagnitudeTailCandidates(for: afterMagnitude) {
                    tailCandidates.append(magnitude.candidate + tail)
                }
            }

            // 桁なしの分数: 接頭 + 分の一 (例: すうぶんのいち→数分の一)
            if let fractions = Self.numericFractionSuffixCandidatesByReading[afterPrefix] {
                tailCandidates.append(contentsOf: fractions)
            }

            for prefixCandidate in resolvedPrefixCandidates {
                for tail in tailCandidates {
                    derived.append(prefixCandidate + tail)
                }
            }
        }

        return Array(uniqueCandidates(from: derived).prefix(limit))
    }

    // 桁の連なりと末尾(助数詞 | 分の一 | ∅)を読みから分解し、漢字列候補を返す。
    // ∅(空文字)は桁を1つ以上消費済みの場合のみ許可し、「数千」等の助数詞なしを表す。
    func numericMagnitudeTailCandidates(
        for reading: String,
        magnitudeConsumed: Bool = true
    ) -> [String] {
        if reading.isEmpty {
            return magnitudeConsumed ? [""] : []
        }

        var results: [String] = []

        if let counters = Self.numericCounterSuffixCandidatesByReading[reading] {
            results.append(contentsOf: counters)
        }

        if let fractions = Self.numericFractionSuffixCandidatesByReading[reading] {
            results.append(contentsOf: fractions)
        }

        for magnitude in Self.numericMagnitudeCandidatesByReading
            where reading.hasPrefix(magnitude.reading) {
            let rest = String(reading.dropFirst(magnitude.reading.count))

            for tail in numericMagnitudeTailCandidates(for: rest, magnitudeConsumed: true) {
                results.append(magnitude.candidate + tail)
            }
        }

        return results
    }

    // 名詞に付く生産的な漢字接辞を組み合わせる: 語幹(名詞)+別(種類別)、別+語幹(別会社)。
    // 語幹は漢字を含む候補に限り、1モーラ語幹(区別/差別等の誤分割)は除外する。
    // 辞書語(餞別等)は system 候補が上位に来るため、補完として低めのスコアで併置する。
    func nounKanjiAffixCandidates(
        for reading: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode,
        limit: Int
    ) -> [String] {
        guard reading.count >= 4,
            limit > 0 else {
            return []
        }

        func kanjiStemCandidates(for stemReading: String) -> [String] {
            uniqueCandidates(
                from: candidatesForReading(
                    stemReading,
                    userDictionary: userDictionary,
                    initialUserDictionary: initialUserDictionary,
                    systemCandidateMode: systemCandidateMode
                )
            ).filter { containsKanji($0) }
        }

        var derived: [String] = []

        for affix in Self.nounKanjiSuffixAffixCandidatesByReading
            where reading.hasSuffix(affix.reading) {
            let stem = String(reading.dropLast(affix.reading.count))

            guard stem.count >= 2 else {
                continue
            }

            for candidate in kanjiStemCandidates(for: stem).prefix(6) {
                derived.append(candidate + affix.candidate)
            }
        }

        for affix in Self.nounKanjiPrefixAffixCandidatesByReading
            where reading.hasPrefix(affix.reading) {
            let stem = String(reading.dropFirst(affix.reading.count))

            guard stem.count >= 2 else {
                continue
            }

            for candidate in kanjiStemCandidates(for: stem).prefix(6) {
                derived.append(affix.candidate + candidate)
            }
        }

        return Array(uniqueCandidates(from: derived).prefix(limit))
    }

    func trimmingLeadingNumberPrefix(from text: String) -> String {
        String(text.drop(while: { $0.isNumber }))
    }
}
