import Foundation

// 連文節の判定の小さな関数(語の種類・字種の見分け)と、語をつなぐ処理。
// KanaKanjiConverter+MultiClause.swift の末尾にあったものを分けた(3843。中身は変えていない)
extension KanaKanjiConverter {
    // 仮定「なら」の直前が述語(動詞辞書形/形容詞/タ形、または活用派生)か。
    // 述語+なら=かな正書(買うなら)、体言+と+奈良=地名 の区別に使う。
    // 読みが た/だ で終わる全漢字の表層(円田=えんだ、三田=みた)。述語の た形ではなく名詞(3555)
    static func isAllKanjiNounWithTaDaReadingTail(surface: String, reading: String?) -> Bool {
        guard let last = reading?.last, last == "た" || last == "だ" else { return false }
        return isAllKanjiSurface(surface)
    }

    static func isPredicateLikePrevForConditional(_ prev: MultiClauseNode) -> Bool {
        if prev.isInflectionDerived {
            return true
        }
        // かなの の/なの/ん(説明・名詞化: だめなの+なら、行くん+なら)と、かな正書の代名詞(それ+なら)の直後も
        // 仮定の なら(3494。ぜんぶだめなのなら が 全部だめなの奈良 だった、ユーザ報告)
        if prev.isKanaIdentity,
            prev.reading.hasSuffix("の") || prev.reading.hasSuffix("ん")
                || multiClauseConditionalNaraKanaPrevReadings.contains(prev.reading) {
            return true
        }
        return prev.surface.last.map { multiClausePredicateTailCharacters.contains($0) } ?? false
    }

    // 語形(かな・漢字・ラテン字を含む)か。絵文字/記号のみなら false。curated 優遇の対象判定に使う。
    static func isWordLikeSurface(_ text: String) -> Bool {
        // 温度の単位記号(°C/°F)はラテン字を含むが記号として扱う。misc の せっし/かし→°C/°F を
        // 語形扱いすると連文節で curated 床(1500)が付き、かし を含む読み(貸した/化した)を
        // °F が乗っ取る(すりむかした→スリム°Fた。2777)
        if text == "\u{00B0}C" || text == "\u{00B0}F" {
            return false
        }
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if (0x3041...0x3096).contains(value)      // ひらがな
                || (0x30A1...0x30FA).contains(value)  // カタカナ
                || value == 0x30FC                    // 長音符
                || (0x4E00...0x9FFF).contains(value)  // CJK 統合漢字
                || (0x3400...0x4DBF).contains(value)  // CJK 拡張A
                || (0x0041...0x005A).contains(value)  // A-Z
                || (0x0061...0x007A).contains(value) { // a-z
                return true
            }
        }
        return false
    }

    // タイブレーク用: カタカナのみ、またはラテン字のみの表層(かな入力に対する
    // 非ネイティブ表記)。同コストならこれらでない表層(漢字/かな)を優先する。
    static func isNonNativeScriptSurface(_ text: String) -> Bool {
        if isKatakanaString(text) {
            return true
        }
        guard !text.isEmpty else {
            return false
        }
        return text.unicodeScalars.allSatisfy { scalar in
            (0x0041...0x005A).contains(scalar.value)
                || (0x0061...0x007A).contains(scalar.value)
        }
    }

    // 期間を表す数量名詞か(数分/3時間/2週間/数か月/五年間 等。2772)。数詞(算用/漢数字/数/何)+期間の助数詞。
    // 日/月/年 単独は時点(3日=三日目)と両義なので入れない(日間/年間 は入れる)
    static func isDurationNounSurface(_ surface: String) -> Bool {
        guard let counter = multiClauseDurationCounterSuffixes.first(where: { surface.hasSuffix($0) }) else {
            return false
        }
        let numeral = surface.dropLast(counter.count)
        guard !numeral.isEmpty else { return false }
        return numeral.allSatisfy { multiClauseNumeralCharacters.contains($0) }
    }

    // 国旗の絵文字(地域指標 2 文字)か。drapeaux 由来の国名判定に使う(3537)
    static func isFlagEmojiSurface(_ text: String) -> Bool {
        let scalars = text.unicodeScalars
        guard scalars.count == 2 else { return false }
        return scalars.allSatisfy { (0x1F1E6...0x1F1FF).contains($0.value) }
    }

    static func isKatakanaString(_ text: String) -> Bool {
        guard !text.isEmpty else {
            return false
        }
        for scalar in text.unicodeScalars {
            // カタカナ(ァ U+30A1 〜 ヺ U+30FA)と長音符(ー U+30FC)。
            if (0x30A1...0x30FA).contains(scalar.value) || scalar.value == 0x30FC {
                continue
            }
            return false
        }
        return true
    }

    func readingLooksLikeLoanword(_ reading: String) -> Bool {
        for character in reading where Self.multiClauseLoanwordMarkers.contains(character) {
            return true
        }
        return false
    }
}

extension Sequence where Element == String {
    // 連文節の語をつなぐ。ラテン文字で終わる語とラテン文字で始まる語の間には空白を 1 つ入れる(Beaujolais-Villages+Nouveau が
    // Beaujolais-VillagesNouveau だった。欧文は語の間を空ける。3815、ユーザ指定)。どちらかが日本語の字・数字・記号なら詰める
    func joinedMultiClauseSurfaces() -> String {
        var result = ""
        for surface in self {
            if let last = result.last, let first = surface.first,
                KanaKanjiConverter.isLatinLetterForWordSpacing(last), KanaKanjiConverter.isLatinLetterForWordSpacing(first) {
                result.append(" ")
            }
            result.append(surface)
        }
        return result
    }
}

extension KanaKanjiConverter {
    // ラテン文字(基本・拡張 A/B のアクセント付きを含む)の字か
    static func isLatinLetterForWordSpacing(_ character: Character) -> Bool {
        guard character.isLetter, let scalar = character.unicodeScalars.first else { return false }
        return scalar.value < 0x0250
    }
}
