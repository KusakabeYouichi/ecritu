import Foundation

// 連文節の候補の並べ替えの後処理(ラテン文字とカタカナの対、文脈で決まる同音語の差し替え、かなの 2 番め、
// め/目、書きかえ など)。変換の本体(ラティスと最良経路)が返した候補の列に、順に当てる。
// KanaKanjiConverter+MultiClause.swift の前半にあったものを分けた(3843。中身は変えていない)
extension KanaKanjiConverter {
    // 先頭にラテン文字の表記があるとき、そのラテン文字を全部カタカナにした形を 2 番目へ(ユーザ指定 3658:
    // ラテン文字とカタカナの両方があればラテン文字が先、カタカナが 2 位)。かーねろすはなぱ で CarnerosはNapa の次が
    // カーネロスはNapa/Carnerosはナパ の混ぜ書きで、カーネロスはナパ は 4 番目だった。
    // 対応の判定は、ラテン文字もカタカナも除いた残り(助詞・漢字)が先頭と同じで、ラテン文字を含まない候補
    // 読み全体が「ラテン文字の表記を持つ登録語+助詞」のとき(てすとふらいと+に)は、ラテン文字の形を先頭にする
    // (ユーザ指定 3845)。読みだけなら TestFlight が先頭なのに、助詞を付けると テストフライトに が先頭で、TestFlightに は
    // 2 番めだった(連文節は テスト+フライト の 2 語が安く、ラテン文字は latinCounterpartOfKatakanaTop が 2 番めに足すだけ)。
    // 文の途中のカタカナ語(正解はバーデンです)は今までどおり 2 番め。先頭の候補が カタカナの語+助詞 で始まるときだけ動かす
    // (助詞の後ろに語が続いてもよい: てすとふらいとにあげる→TestFlightに挙げる)
    static let registeredWordTrailingParticles: [String] = [
        "には", "では", "から", "まで", "より", "とは", "は", "が", "を", "に", "の", "も", "で", "と", "へ", "や",
    ]
    func latinFirstForRegisteredWordPlusParticle(reading: String, candidates: [String]) -> [String] {
        guard let top = candidates.first else { return candidates }
        // 先頭の候補の頭の カタカナ(と ー・中黒)の語
        let characters = Array(top)
        var end = 0
        while end < characters.count, ("ァ"..."ヺ").contains(characters[end]) || characters[end] == "ー" || characters[end] == "・" {
            end += 1
        }
        guard end >= 2, end < characters.count else { return candidates }
        // その語の読み(カタカナをひらがなに。ー はそのまま、中黒は読まない)
        let stem = String(characters[..<end].filter { $0 != "・" }.map { character -> Character in
            guard character != "ー", let scalar = character.unicodeScalars.first, let hiragana = Unicode.Scalar(scalar.value - 0x60) else {
                return character
            }
            return Character(hiragana)
        })
        // 語の直後が助詞であること(文の頭の 登録語+助詞。後ろに語が続いてもよい: てすとふらいとにあげる。ユーザ指定 3845)。
        // 読みもその形で始まること(カタカナの語が読みの頭と対応していることの確認)
        let rest = String(characters[end...])
        let normalized = KanaTextNormalizer.normalizedReading(reading)
        guard Self.registeredWordTrailingParticles.contains(where: { rest.hasPrefix($0) && normalized.hasPrefix(stem + $0) }),
            let latin = scriptCounterpartSurface(for: stem, wantsLatin: true, plainKatakana: nil),
            // IT の語(references/it.plist。TestFlight/iPhone)に限る(ユーザ指定 3846)。ワインの語(Merlot/Riesling/Málaga)は
            // 文の中ではカタカナを先にする以前の指定(3661 ほか)があり、ワインを飲む/フランスのワイン も動かさない
            ITTermTable.readingAndLatinSurfaces.contains(stem + "\t" + latin) else {
            return candidates
        }
        // ラテン文字の形を先頭、元の先頭(カタカナの形)を 2 番めに
        let latinForm = latin + rest
        return [latinForm, top] + candidates.filter { $0 != latinForm && $0 != top }
    }

    // 読みに対する ラテン文字だけ/カタカナだけ の表記(seed → 補助語彙 → 辞書 の順)。カタカナは語彙の表記(グラン・クリュ の中黒)を優先し、
    // 無ければ plainKatakana(かなをそのままカタカナにしたもの)が辞書・seed にあるときだけそれを返す(3677)
    func scriptCounterpartSurface(for reading: String, wantsLatin: Bool, plainKatakana: String?) -> String? {
        func matches(_ surface: String) -> Bool {
            if wantsLatin {
                return surface.unicodeScalars.contains(where: Self.isLatinLetterScalar)
                    && !surface.contains(where: { ("ぁ"..."ゖ").contains($0) || ("ァ"..."ヺ").contains($0) || Self.isKanjiCharacter($0) })
            }
            return !surface.isEmpty && surface.allSatisfy { ("ァ"..."ヺ").contains($0) || $0 == "ー" || $0 == "・" }
        }
        let pools: [[String]] = [
            KanaKanjiSeedDictionary.seed[reading] ?? [],
            store.loadSupplementalSystemDictionary().candidates(for: reading),
            store.wordCosts(for: reading).sorted { $0.value < $1.value }.map(\.key)
        ]
        // カタカナは中黒つきの語彙の表記(グラン・クリュ)を中黒なし(グランクリュ)より先に
        if !wantsLatin, let dotted = pools.lazy.compactMap({ $0.first(where: { matches($0) && $0.contains("・") }) }).first {
            return dotted
        }
        for pool in pools {
            if let hit = pool.first(where: matches) { return hit }
        }
        return nil
    }

    // 先頭の候補のカタカナの語に語彙でラテン文字の表記があれば、ラテン文字に替えた形を 2 番目に(ユーザ指定 3677:
    // 正解はバーデンです → 正解はBadenです を 2 番目に)。既に 2 番目までにラテン文字の形があれば触らない
    static func latinCounterpartOfKatakanaTop(_ candidates: [String], latinFor: (_ reading: String) -> String?) -> [String] {
        guard let top = candidates.first, top.contains(where: { ("ァ"..."ヺ").contains($0) }) else { return candidates }
        if candidates.prefix(2).contains(where: { $0.unicodeScalars.contains(where: isLatinLetterScalar) }) { return candidates }
        let characters = Array(top)
        var index = 0
        while index < characters.count {
            guard ("ァ"..."ヺ").contains(characters[index]) else { index += 1; continue }
            var end = index
            while end < characters.count, ("ァ"..."ヺ").contains(characters[end]) || characters[end] == "ー" || characters[end] == "・" { end += 1 }
            let run = characters[index..<end].filter { $0 != "・" }
            // 前後が漢字の語の中のカタカナ(赤ワイン用/タイ料理)は 1 語の一部なので作らない(赤Wine用/Tai料理 になっていた)
            let kanjiBefore = index > 0 && isKanjiCharacter(characters[index - 1])
            // 後ろの漢字が 等/種/地方/地区/地域 なら語の切れ目(ソーヴィニヨン等/ミッション種/プロヴァンス地方)なので作る
            let rest = String(characters[end...])
            let kanjiAfter = end < characters.count && isKanjiCharacter(characters[end])
                && !Self.latinCounterpartAllowedKanjiFollowers.contains(where: { rest.hasPrefix($0) })
            if run.count >= 2, !kanjiBefore, !kanjiAfter {
                let reading = String(run.map { character -> Character in
                    guard character != "ー", let scalar = character.unicodeScalars.first, let hiragana = Unicode.Scalar(scalar.value - 0x60) else {
                        return character
                    }
                    return Character(hiragana)
                })
                if let latin = latinFor(reading) {
                    let variant = String(characters[..<index]) + latin + String(characters[end...])
                    var result = candidates.filter { $0 != variant }
                    result.insert(variant, at: min(1, result.count))
                    return result
                }
            }
            index = end
        }
        return candidates
    }

    static let latinCounterpartAllowedKanjiFollowers: [String] = ["等", "種", "地方", "地区", "地域"]

    // 先頭がラテン文字の語で始まり(Appleの株)、2 番目がそのカタカナの形でないとき、読みの頭からその語を引いて
    // カタカナの表記に替えた形(アップルの株)を 2 番目に置く(ユーザ報告 3687: あっぷるのかぶ が Appleの株、Appleのカブ で、
    // アップルの株 は別解の上位に入っていなかった)。カタカナは語彙の表記(scriptCounterpartSurface)だけを使う
    func leadingLatinKatakanaCounterpart(reading: String, candidates: [String]) -> [String] {
        guard let top = candidates.first,
            top.unicodeScalars.first.map(Self.isLatinLetterScalar) == true else { return candidates }
        if candidates.count >= 2, Self.isScriptCounterpartPair(top, candidates[1]) { return candidates }
        let characters = Array(top)
        var end = 0
        while end < characters.count,
            characters[end].unicodeScalars.allSatisfy({ Self.isLatinLetterScalar($0) || " '’-.&".unicodeScalars.contains($0) }) {
            end += 1
        }
        guard end < characters.count else { return candidates }
        let latin = String(characters[..<end]).trimmingCharacters(in: .whitespaces)
        let normalized = Array(KanaTextNormalizer.normalizedReading(reading))
        let supplemental = store.loadSupplementalSystemDictionary()
        for length in stride(from: min(normalized.count - 1, 24), through: 2, by: -1) {
            let prefix = String(normalized[..<length])
            guard supplemental.candidates(for: prefix).contains(latin)
                || (KanaKanjiSeedDictionary.seed[prefix]?.contains(latin) ?? false) else { continue }
            // 抑制した表記(まっくおーえす→マックオーエス)は作らない
            guard let katakana = scriptCounterpartSurface(for: prefix, wantsLatin: false, plainKatakana: nil),
                !(store.suppressedCandidatesByReading()[prefix]?.contains(katakana) ?? false) else {
                return candidates
            }
            let variant = katakana + String(characters[end...])
            var result = candidates.filter { $0 != variant }
            result.insert(variant, at: min(1, result.count))
            return result
        }
        return candidates
    }

    // 先頭でカタカナの直後にラテン文字が続く(スタートLINE)とき、ラテン文字を含まない同じ形(スタートライン)が上位にあれば
    // 先頭へ(3720: らいん に LINE を足したら すたーとらいん が スタートLINE になった)。カタカナの語に続けて書くのは
    // カタカナの語(複合語)。ラテン文字が先の形(iPhoneケース)と、助詞などを挟む形(ゼミはLINEで)は対象外
    static func katakanaCompoundOverKatakanaLatinTop(_ candidates: [String]) -> [String] {
        guard candidates.count >= 2, let top = candidates.first else { return candidates }
        func isKatakana(_ c: Character) -> Bool { ("ァ"..."ヺ").contains(c) || c == "ー" }
        let characters = Array(top)
        guard characters.indices.dropFirst().contains(where: { index in
            isKatakana(characters[index - 1]) && characters[index].unicodeScalars.contains(where: isLatinLetterScalar)
        }) else { return candidates }
        func skeleton(_ text: String) -> String {
            String(text.filter { !isKatakana($0) && $0 != "・" && !$0.unicodeScalars.contains(where: isLatinLetterScalar) && $0 != " " })
        }
        let topSkeleton = skeleton(top)
        guard let index = candidates.indices.dropFirst().prefix(5).first(where: { index in
            let candidate = candidates[index]
            return !candidate.unicodeScalars.contains(where: isLatinLetterScalar) && skeleton(candidate) == topSkeleton
        }) else { return candidates }
        var result = candidates
        let katakana = result.remove(at: index)
        result.insert(katakana, at: 0)
        return result
    }

    // 先頭がカタカナとラテン文字の混ぜ書き(シェリーがApera/ビンゲンはRheinhessen)で、候補に全部ラテン文字の形があれば先頭へ
    // (このあと promoteKatakanaCounterpartOfLatinTop が全部カタカナの形を 2 番目に置く。learningBOX 検査 3684、ユーザ指定:
    // ラテン文字が先、カタカナが 2 番目)。漢字に続くカタカナ(赤ワイン/タイ料理)は語の一部なので、それがあれば触らない
    static func allLatinOverMixedTop(_ candidates: [String]) -> [String] {
        guard candidates.count >= 2, let top = candidates.first,
            top.unicodeScalars.contains(where: isLatinLetterScalar) else { return candidates }
        func isKatakana(_ c: Character) -> Bool { ("ァ"..."ヺ").contains(c) || c == "ー" || c == "・" }
        func isLatin(_ c: Character) -> Bool {
            c.unicodeScalars.allSatisfy { isLatinLetterScalar($0) || " '’-.&®!".unicodeScalars.contains($0) }
        }
        let characters = Array(top)
        guard characters.contains(where: { ("ァ"..."ヺ").contains($0) }) else { return candidates }
        for (index, character) in characters.enumerated() where isKatakana(character) {
            if index > 0, isKanjiCharacter(characters[index - 1]) { return candidates }
            if index + 1 < characters.count, isKanjiCharacter(characters[index + 1]) { return candidates }
        }
        let rest = String(top.filter { !isLatin($0) && !isKatakana($0) })
        guard let index = candidates.indices.dropFirst().first(where: { index in
            let candidate = candidates[index]
            return !candidate.contains(where: isKatakana)
                && candidate.unicodeScalars.contains(where: isLatinLetterScalar)
                && String(candidate.filter { !isLatin($0) }) == rest
        }) else { return candidates }
        var result = candidates
        let latin = result.remove(at: index)
        result.insert(latin, at: 0)
        return result
    }

    // 先頭と 2 番目がラテン文字とカタカナの表記違い(Portは/ポートは)か。候補欄で単文節の 1 位を連文節の 2 番目に
    // 差し込むとき、この組なら 3 番目にする(learningBOX 検査 3684: ぽーとは の Portは が ポーとは に押されて 3 番目だった)
    static func isScriptCounterpartPair(_ first: String, _ second: String) -> Bool {
        func isKatakana(_ c: Character) -> Bool { ("ァ"..."ヺ").contains(c) || c == "ー" || c == "・" }
        func isLatin(_ c: Character) -> Bool {
            c.unicodeScalars.allSatisfy { isLatinLetterScalar($0) || " '’-.&®!".unicodeScalars.contains($0) }
        }
        let firstHasLatin = first.contains(where: { $0.unicodeScalars.contains(where: isLatinLetterScalar) })
        let secondHasLatin = second.contains(where: { $0.unicodeScalars.contains(where: isLatinLetterScalar) })
        guard firstHasLatin != secondHasLatin else { return false }
        let (latinSide, katakanaSide) = firstHasLatin ? (first, second) : (second, first)
        guard katakanaSide.contains(where: isKatakana) else { return false }
        return String(latinSide.filter { !isLatin($0) && !isKatakana($0) }) == String(katakanaSide.filter { !isKatakana($0) })
    }

    // 連文節の後処理が 2 番目に置いた表記違い(何か/なんか・のたれ/のタレ・のたびに/の度に。どれもユーザ指定 3710)。
    // 候補欄で単文節の 1 位を差し込むときは、この組も 3 番目にする(3711、ユーザ報告: なんかいってや で 単文節の 1 位
    // 何回ってや が 2 番目に入り、なんか言ってや が 3 番目だった)
    static let pinnedSecondSubstitutions: [(String, String)] = [("何か", "なんか"), ("のたれ", "のタレ"), ("のたびに", "の度に")]
    public static func keepsSecondAgainstSingleBest(_ first: String, _ second: String) -> Bool {
        isScriptCounterpartPair(first, second) || isKanaScriptVariantPair(first, second) || pinnedSecondSubstitutions.contains {
            first.contains($0.0) && first.replacingOccurrences(of: $0.0, with: $0.1) == second
        }
    }

    // 単文節: 先頭がカタカナだけならラテン文字だけの候補を、ラテン文字だけならカタカナだけの候補を 2 番目に(3677)
    static func scriptCounterpartSecond(_ candidates: [String]) -> [String] {
        guard candidates.count >= 3, let top = candidates.first else { return candidates }
        func isKatakanaOnly(_ s: String) -> Bool { !s.isEmpty && s.allSatisfy { ("ァ"..."ヺ").contains($0) || $0 == "ー" || $0 == "・" } }
        func isLatinOnly(_ s: String) -> Bool {
            s.unicodeScalars.contains(where: isLatinLetterScalar)
                && s.unicodeScalars.allSatisfy { isLatinLetterScalar($0) || " '’-.&".unicodeScalars.contains($0) || ("0"..."9").contains(Character($0)) }
        }
        let wanted: (String) -> Bool
        let alreadyMixed: (String) -> Bool
        if isKatakanaOnly(top) {
            wanted = isLatinOnly
            alreadyMixed = { $0.unicodeScalars.contains(where: isLatinLetterScalar) }
        } else if isLatinOnly(top) {
            wanted = isKatakanaOnly
            alreadyMixed = { $0.contains(where: { ("ァ"..."ヺ").contains($0) }) }
        } else {
            return candidates
        }
        // 2 番目がもう一方の文字を含んでいれば触らない(ベライヒSaar/マスカット・ベイリーA を別の書き方で押し出さない)。
        // 2 番目が先頭の大文字・®/™ 違いだけ(VINOTERAS/ジップロック®)のときも、指定の並び(3289/2698)を守る
        // ラテン文字の形が先頭から複数続くとき(Beaujolais-Villages/Beaujolais Villages)は、それを全部先に残し、カタカナを
        // その直後に入れる(3816、ユーザ指定。3677 の『ラテン文字が先・カタカナが 2 番め』をラテン文字が複数の場合に広げた)
        if isLatinOnly(top) {
            // 大文字・小文字だけの違い(Seasoning/seasoning)は別の形と数えない(3661 の指定: Seasoning の次は シーズニング)
            let latinRunEnd = candidates.indices.dropFirst().first(where: {
                !isLatinOnly(candidates[$0]) || candidates[$0].lowercased() == top.lowercased()
            }) ?? candidates.endIndex
            if latinRunEnd > 1 {
                guard latinRunEnd < candidates.endIndex, !wanted(candidates[latinRunEnd]), !alreadyMixed(candidates[latinRunEnd]),
                    let index = candidates.indices.dropFirst(latinRunEnd + 1).first(where: { wanted(candidates[$0]) }) else {
                    return candidates
                }
                var result = candidates
                let moved = result.remove(at: index)
                result.insert(moved, at: latinRunEnd)
                return result
            }
        }
        let second = candidates[1]
        let strippedSecond = second.replacingOccurrences(of: "®", with: "").replacingOccurrences(of: "™", with: "")
        // 大文字・小文字の違いは、全部大文字の商標の書き方(VINOTERAS)だけ同じ語とみなす(Méthode ancestrale/seasoning は別扱い)
        let isAllCapsVariant = second == second.uppercased() && second != top && second.uppercased() == top.uppercased()
        if wanted(second) || alreadyMixed(second) || strippedSecond == top || isAllCapsVariant {
            return candidates
        }
        guard let index = candidates.indices.dropFirst(2).first(where: { wanted(candidates[$0]) }) else { return candidates }
        var result = candidates
        let moved = result.remove(at: index)
        result.insert(moved, at: 1)
        return result
    }

    static func promoteKatakanaCounterpartOfLatinTop(
        _ candidates: [String], isKnownKatakana: (_ reading: String, _ katakana: String) -> String? = { _, _ in nil }
    ) -> [String] {
        guard candidates.count > 2, let top = candidates.first,
            top.unicodeScalars.contains(where: isLatinLetterScalar) else {
            return candidates
        }
        func isKatakana(_ c: Character) -> Bool { ("ァ"..."ヺ").contains(c) || c == "ー" || c == "・" }
        func isLatinRunCharacter(_ c: Character) -> Bool {
            c.unicodeScalars.allSatisfy { isLatinLetterScalar($0) || " '’-.&®!".unicodeScalars.contains($0) }
        }
        let topRest = String(top.filter { !isLatinRunCharacter($0) && !isKatakana($0) })
        func isCounterpart(_ candidate: String) -> Bool {
            !candidate.unicodeScalars.contains(where: isLatinLetterScalar)
                && candidate.contains(where: isKatakana)
                && String(candidate.filter { !isKatakana($0) }) == topRest
        }
        // 中黒つき(グラン・クリュは)が候補にあれば中黒なし(グランクリュは)より先に選ぶ(3677)
        let dottedIndices = candidates.indices.dropFirst(1).filter { isCounterpart(candidates[$0]) && candidates[$0].contains("・") }
        // 中黒つきが 2 つ以上あれば、カタカナの部分が語彙の表記と同じものを先に(learningBOX 検査 3684: Cinque Terreとは の
        // 2 番目が辞書の チンクェ・テッレとは で、語彙の チンクエ・テッレとは は 3 番目だった)
        func isVocabularySpelling(_ candidate: String) -> Bool {
            let run = String(candidate.filter(isKatakana))
            let reading = String(run.filter { $0 != "・" }.map { character -> Character in
                guard character != "ー", let scalar = character.unicodeScalars.first, let hiragana = Unicode.Scalar(scalar.value - 0x60) else {
                    return character
                }
                return Character(hiragana)
            })
            return isKnownKatakana(reading, run) == run
        }
        let dottedIndex = dottedIndices.count >= 2
            ? (dottedIndices.first(where: { isVocabularySpelling(candidates[$0]) }) ?? dottedIndices.first)
            : dottedIndices.first
        if dottedIndex == 1 {
            return candidates
        }
        guard let index = dottedIndex ?? candidates.dropFirst(2).firstIndex(where: isCounterpart) else {
            return synthesizedKatakanaCounterpartOfLatinTop(
                candidates, isKatakana: isKatakana, isLatinRunCharacter: isLatinRunCharacter, isKnownKatakana: isKnownKatakana)
        }
        var result = candidates
        let katakana = result.remove(at: index)
        result.insert(katakana, at: 1)
        return result
    }

    // カタカナの形が候補に無いとき、ラテン文字の部分だけがひらがなの候補(Cruが集中している ⇔ くりゅが集中している)から
    // カタカナの形(クリュが集中している)を作って 2 番目に置く(learningBOX 検査 3667。Crus が 2 番目で クリュ が無かった)
    private static func synthesizedKatakanaCounterpartOfLatinTop(
        _ candidates: [String], isKatakana: (Character) -> Bool, isLatinRunCharacter: (Character) -> Bool,
        isKnownKatakana: (_ reading: String, _ katakana: String) -> String?
    ) -> [String] {
        guard let top = candidates.first else { return candidates }
        let topCharacters = Array(top)
        for candidate in candidates.dropFirst() where !candidate.unicodeScalars.contains(where: isLatinLetterScalar) {
            let other = Array(candidate)
            var prefix = 0
            while prefix < min(topCharacters.count, other.count), topCharacters[prefix] == other[prefix] { prefix += 1 }
            var suffix = 0
            while suffix < min(topCharacters.count, other.count) - prefix,
                topCharacters[topCharacters.count - 1 - suffix] == other[other.count - 1 - suffix] { suffix += 1 }
            let latinPart = topCharacters[prefix..<(topCharacters.count - suffix)]
            let kanaPart = other[prefix..<(other.count - suffix)]
            guard !latinPart.isEmpty, !kanaPart.isEmpty, latinPart.allSatisfy(isLatinRunCharacter),
                kanaPart.allSatisfy({ ("ぁ"..."ゖ").contains($0) || $0 == "ー" }) else { continue }
            let katakanaPart = kanaPart.map { character -> Character in
                guard let scalar = character.unicodeScalars.first, ("ぁ"..."ゖ").contains(character),
                    let converted = Unicode.Scalar(scalar.value + 0x60) else { return character }
                return Character(converted)
            }
            // 辞書・seed・補助語彙にあるカタカナ語だけ(macOS⇔まっくおーえす から マックオーエス を作らない)。語彙の表記(グラン・クリュ)を使う
            guard let known = isKnownKatakana(String(kanaPart), String(katakanaPart)) else { continue }
            let synthesized = String(topCharacters[..<prefix]) + known + String(topCharacters[(topCharacters.count - suffix)...])
            var result = candidates.filter { $0 != synthesized }
            result.insert(synthesized, at: 1)
            return result
        }
        return candidates
    }

    // 酒税の分類の話(発泡性酒類/醸造酒類/酒税法による酒類/酒類ごとのアルコール分)では しゅるい を 酒類 に(ユーザ指定 3669)。
    // 一般の文は 種類 が先(ワインの種類 は 種類 のまま。酒類 は元から 2 番目)。読みに分類の語があるときだけ、
    // 先頭の候補の 種類 を 酒類 に替えた形を先頭に置く
    static let liquorCategoryContextReadings: [String] = [
        "しゅぜい", "はっぽうせい", "じょうぞうしゅ", "じょうりゅうしゅ", "こんせいしゅ", "あるこーるぶん"
    ]
    static func liquorCategoryOrdered(reading: String, candidates: [String]) -> [String] {
        guard reading.contains("しゅるい"), let top = candidates.first, top.contains("種類"),
            liquorCategoryContextReadings.contains(where: { reading.contains($0) }) else {
            return candidates
        }
        let replaced = top.replacingOccurrences(of: "種類", with: "酒類")
        return [replaced] + candidates.filter { $0 != replaced }
    }

    // 醸造の工程・原料の話の つくる も 造る(learningBOX 検査 3693 の [直す] 約 40 行。教材は 造ら 727:作ら 63)。
    // 酒の語がある文は下の brewingMakeOrthographyOrdered(3675)が受け持つ。ここはそれに無い語を補う:
    // 蒸溜/醗酵/混醸 は工程そのものなのでどの つくる でも。乳・チーズ・熟成 等は一般の料理(牛乳でプリンを作る/
    // チーズケーキを作る)があるので、受身(つくられ)か が/で/から/も/は の直後に限る。小麦/果物/ハーブ は
    // パンやジャム(小麦から作られる)と区別できないので入れない。カクテルは混ぜて作るものなので 作る のまま(ユーザ指定 3716。
    // 3695 は かくてる を手掛かりにしていた)。ワインの語があっても カクテル の文は 造 にしない(brewingCocktailReading)
    static let brewingProcessContextReadings: [String] = [
        "じょうりゅう", "はっこう", "こんじょう"
    ]
    static let brewingCocktailReading = "かくてる"
    static let brewingProductContextReadings: [String] = [
        "じゅくせい", "ぎゅうにゅう", "ようにゅう", "やぎにゅう", "ばくが", "ちーず", "しーどる", "ろぜ",
        "あまくち", "からくち", "しゃるどね"
    ]
    static func brewingTsukuruOrdered(reading: String, candidates: [String]) -> [String] {
        guard reading.contains("つく"), !reading.contains(brewingCocktailReading), let top = candidates.first, top.contains("作") else {
            return candidates
        }
        let readingChars = Array(reading)
        let conjugationTails: Set<Character> = ["ら", "り", "る", "れ", "ろ", "っ"]
        let strong = brewingProcessContextReadings.contains(where: { reading.contains($0) })
        let product = brewingProductContextReadings.contains(where: { reading.contains($0) })
        guard strong || product else { return candidates }
        var qualifies = strong
        if !qualifies {
            var index = 0
            while index + 2 < readingChars.count {
                if readingChars[index] == "つ", readingChars[index + 1] == "く", conjugationTails.contains(readingChars[index + 2]) {
                    let passive = index + 3 < readingChars.count && readingChars[index + 2] == "ら" && readingChars[index + 3] == "れ"
                    let before = String(readingChars[max(0, index - 2)..<index])
                    if passive || ["が", "で", "も", "は"].contains(where: { before.hasSuffix($0) }) || before == "から" {
                        qualifies = true
                        break
                    }
                }
                index += 1
            }
        }
        guard qualifies else { return candidates }
        var characters = Array(top)
        var changed = false
        for index in characters.indices.dropLast() where characters[index] == "作" && conjugationTails.contains(characters[index + 1]) {
            characters[index] = "造"
            changed = true
        }
        guard changed else { return candidates }
        let rewritten = String(characters)
        return [rewritten] + candidates.filter { $0 != rewritten }
    }

    // 前後の語の読みで決まる専門語の同音語(3696、learningBOX 検査 3684 の [直す])。読みに手掛かりの語があり、
    // 置き換える語の読みもあるときだけ、先頭の候補の表記を差し替える(造る と同じ作り。全体の順位は動かさない。
    // feedback: 専門語は前後の語で)。離れた語の組はラティスの組の加点(隣か 1 字助詞を挟むだけ)では届かない
    // (落下させる+病害、首席+として+析出、鮮明 と 船積みされた)
    static let contextCuedHomophoneRewrites: [(cue: String, targetReading: String, from: String, to: String)] = [
        ("びょうがい", "らっか", "落下", "落果"),
        // 文の頭の よぶんだ/よぶんです は 余分(よぶんだよね が 呼ぶんだよね だった。呼ぶんだ は 2 番め。名前を呼ぶんだよね のように
        // 前に語があれば 呼ぶ のまま。ラティスの加点では を の後ろまで 余分 になった。3850、ユーザ指定)
        ("よぶんだ", "よぶんだ", "^呼ぶんだ", "余分だ"), ("よぶんです", "よぶんです", "^呼ぶんです", "余分です"),
        // はなっとく+です/でした/だ は は納得(放っとく は動詞の辞書形で、です/だ は付かない。はなっとくです が 放っとくです だった。
        // 数字の直後の 1は納得です。放っとくよ/放っとくね はそのまま。3851、ユーザ指定)
        ("はなっとくです", "はなっとくです", "^放っとくです", "は納得です"), ("はなっとくでし", "はなっとくでし", "^放っとくでし", "は納得でし"),
        ("はなっとくだ", "はなっとくだ", "^放っとくだ", "は納得だ"),
        // 文の頭の そうはさせ… は かな(そうはさせない/そうはさせまい が 走破させない/走破させまい だった。走破 にサ変の させる が
        // 付いた 1 語が安い。走破させる は 2 番めに残る。3852、ユーザ指定)
        ("そうはさせ", "そうはさせ", "^走破させ", "そうはさせ"),
        // 文の終わりの 〜はなんだい は 何だい(それはなんだい が それは何台 だった。何台 は 2 番め。何+だい の組の加点では
        // なんだいもある/くるまはなんだいありますか まで 何だい になった。3852、ユーザ指定)
        ("はなんだい", "はなんだい", "は何台$", "は何だい"),
        // 文の頭の あさって+助詞 は 明後日(あさっての が 漁っての、あさってから が 漁ってから だった。漁る は目的語が前に要るので、
        // 文の頭では 明後日。ごみをあさっては は頭が 漁って でないので変えない。あさっている/あさってみる は対象外。3863、ユーザ指定)
        ("あさっての", "あさっての", "^漁っての", "明後日の"), ("あさっては", "あさっては", "^漁っては", "明後日は"), ("あさってから", "あさってから", "^漁ってから", "明後日から"), ("あさってに", "あさってに", "^漁ってに", "明後日に"), ("あさってが", "あさってが", "^漁ってが", "明後日が"), ("あさっても", "あさっても", "^漁っても", "明後日も"), ("あさってで", "あさってで", "^漁ってで", "明後日で"), ("あさってだ", "あさってだ", "^漁ってだ", "明後日だ"), ("あさってです", "あさってです", "^漁ってです", "明後日です"),
        // かといって は かと言って(かと行って が先頭だった)。またのきかい は またの機会(またの機械 が先頭だった)。3865、ユーザ指定
        // 文の頭の あしたから は 明日から(かなの あした→から の連接が 明日→から より 61 安く、あしたからいく が あしたから行く だった。
        // きょうから は 今日から が出ている。3867、ユーザ指定。当時「組の加点が辺の点数に届かない」と見たのは、加点を
        // 別の表(助詞をまたぐ連語の表)に書いていた私の間違いで、組の加点の仕組みは正常(3875 で判明))
        ("あしたから", "あしたから", "^あしたから", "明日から"),
        // 文の中の ほうすい は 放水(そとからほうすい が 外から豊水、外から放水 の順だった。語 LM では 豊水 が 放水 より 182 安い。
        // 1 語だけの ほうすい は辞書の順で 放水 が先頭。3870、ユーザ指定)
        // 文末の なの は断定+の でかな(10+ねんなの が 年ナノ だった。ナノ は単位の前に付く語で、文末には立たない。
        // ナノメートル/ナノです は末尾でないので変えない。3872、ユーザ指定)
        ("なの", "なの", "ナノ$", "なの"),
        // 梨の 豊水 は戻す(ほうすいのなし)
        ("ほうすい", "ほうすい", "豊水", "放水"), ("ほうすいのなし", "ほうすいのなし", "放水のなし", "豊水のなし"),
        // 文の中でも 振袖/留袖(送り仮名なし)を先に(ふりそでをきる が 振り袖を着る だった。ユーザ指定 3879)
        ("ふりそで", "ふりそで", "振り袖", "振袖"), ("とめそで", "とめそで", "留め袖", "留袖"),
        // いきたくなる は 行きたくなる(みんながいきたくなる が みんなが生きたくなる だった。いきたい は seed で 行きたい が先頭。ユーザ指定 3881)
        ("いきたくな", "いきたくな", "生きたくな", "行きたくな"),
        // 文の頭の よんだり は 読んだり、本を〜 も(友達を呼んだり はそのまま。ユーザ指定 3883)
        ("よんだり", "よんだり", "^呼んだり", "読んだり"), ("ほんをよんだり", "ほんをよんだり", "本を呼んだり", "本を読んだり"),
        // 切る の直後の はさみ は道具(かみをきるはさみ が 髪を切る挟み だった。ユーザ指定 3883)
        ("きるはさみ", "きるはさみ", "切る挟み", "切るハサミ"),
        // 人数の直後の いた はかな(さんにんいた が 3人板。板 を下げると 3人居た が先頭で、かなの 3人いた が無かった。ユーザ指定 3885)
        ("にんいた", "にんいた", "人居た", "人いた"), ("にんいた", "にんいた", "人板", "人いた"),
        // ごにん/じゅうにん/よにん は 誤認/住人/よ任意 が先に立つ(ごにんいた が 誤認板、じゅうにんいた が 住人いた、よにんいた が よ任意た。
        // 後ろに いた/いる が続くときは人数。ユーザ指定 3887)
        ("ごにんいた", "ごにんいた", "誤認板", "5人いた"), ("ごにんいた", "ごにんいた", "誤認いた", "5人いた"),
        ("ごにんいる", "ごにんいる", "誤認居る", "5人いる"), ("ごにんいる", "ごにんいる", "誤認いる", "5人いる"),
        ("じゅうにんいた", "じゅうにんいた", "住人いた", "10人いた"), ("じゅうにんいる", "じゅうにんいる", "住人居る", "10人いる"),
        ("じゅうにんいる", "じゅうにんいる", "住人いる", "10人いる"),
        ("よにんいた", "よにんいた", "よ任意た", "4人いた"),
        // 板の間(いたのまにすわる が いたの間に座る だった。3887)
        ("いたのま", "いたのま", "^いたの間", "板の間"),
        ("かといって", "かといって", "かと行って", "かと言って"), ("またのきかい", "またのきかい", "またの機械", "またの機会"),
        // 体や気持ちの具合が すぐれない はかな(文の途中でも。きょうはたいちょうがすぐれない。文の頭の並びは
        // leadingSurfaceOrdersByReadingPrefix で 3 つ並べる。3864、ユーザ指定)
        ("たいちょうがすぐれ", "たいちょうがすぐれ", "体調が優れ", "体調がすぐれ"), ("きぶんがすぐれ", "きぶんがすぐれ", "気分が優れ", "気分がすぐれ"),
        ("かおいろがすぐれ", "かおいろがすぐれ", "顔色が優れ", "顔色がすぐれ"), ("けんこうがすぐれ", "けんこうがすぐれ", "健康が優れ", "健康がすぐれ"),
        ("きげんがすぐれ", "きげんがすぐれ", "機嫌が優れ", "機嫌がすぐれ"), ("ぐあいがすぐれ", "ぐあいがすぐれ", "具合が優れ", "具合がすぐれ"),
        // 似る は状態の動詞で、勧める・命じる言い方には付かない(にるといいよ が 似るといいよ。煮る が先。3819、ユーザ指定)
        ("にるといい", "にるといい", "似るといい", "煮るといい"), ("にればいい", "にればいい", "似ればいい", "煮ればいい"),
        ("にたらいい", "にたらいい", "似たらいい", "煮たらいい"), ("になさい", "になさい", "似なさい", "煮なさい"),
        ("にるとよい", "にるとよい", "似るとよい", "煮るとよい"), ("にるほうがいい", "にるほうがいい", "似るほうがいい", "煮るほうがいい"),
        // なんでしたっけ/なんでしたか は 何 を先頭に(かなの なんでした が 1 語で安く立ち、何でしたっけ が候補に出なかった。
        // かなの形は 2 番め、ナンでしたっけ を 3 番め(contextCuedThirdCandidates)。なんでしたら(よろしければ)はかなのまま。3823、ユーザ指定)
        ("なんでしたっけ", "なんでしたっけ", "なんでしたっけ", "何でしたっけ"), ("なんでしたか", "なんでしたか", "なんでしたか", "何でしたか"),
        // よく似ている(欲+にている だった。3819)
        ("よくにている", "よくにている", "欲にている", "よく似ている"), ("よくにてる", "よくにてる", "欲にてる", "よく似てる"),
        // を+よく+にて… は 煮る(人参をよく煮ている。似る は を を取らない。上の差し替えの後に当てる。3820)
        ("をよくにてい", "をよくにてい", "似てい", "煮てい"), ("をよくにてる", "をよくにてる", "似てる", "煮てる"),
        // 押す+場所(雄+場所 だった。3819、ユーザ指定)
        ("おすばしょ", "おすばしょ", "雄場所", "押す場所"),
        // 先代+の+社長/当主 ほか(せんだい を 仙台 先頭にした副作用で 仙台の社長 だった。3817)
        ("せんだいのしゃちょう", "せんだい", "仙台", "先代"), ("せんだいのとうしゅ", "せんだい", "仙台", "先代"),
        ("せんだいのかいちょう", "せんだい", "仙台", "先代"), ("せんだいのいえもと", "せんだい", "仙台", "先代"),
        ("せんだいのおかみ", "せんだい", "仙台", "先代"), ("せんだいのしゅじん", "せんだい", "仙台", "先代"),
        ("せんだいからの", "せんだい", "仙台から", "先代から"), ("せんだいがきずいた", "せんだい", "仙台", "先代"),
        // 面積の話は 最小(面積・生産量最小 が 生産量+最少。生産量だけなら 最少 のまま。3812、ユーザ指摘)
        ("めんせき", "さいしょう", "最少", "最小"),
        // 一括検査 3801 の確認表の [直す](3804、ユーザ判定)。前後の語が決め手になる同音語と、区切りが崩れていた句
        ("こうちをたがや", "こうち", "高地", "耕地"),
        ("つけこむ", "かひ", "可否", "果皮"), ("るもんたーじゅ", "かひ", "可否", "果皮"), ("かにくかひ", "かひしゅくき", "か脾腫茎", "果皮種茎"),
        ("びんを", "ふる", "降る", "振る"),
        ("まっしろなきじ", "きじ", "記事", "生地"),
        ("こなじょうのほうし", "ほうし", "奉仕", "胞子"),
        ("かび", "きんは", "金は", "菌は"),
        ("さわやかなしゅしつ", "たんれい", "端麗", "淡麗"),
        ("ねずのみ", "ねずのみ", "寝ずの実", "杜松の実"),
        ("げんりょうとなるにゅうしゅ", "にゅうしゅ", "入手", "乳種"),
        ("そうしゅん", "しょとう", "初等", "初冬"), ("しょとうからしんねん", "しょとう", "諸島", "初冬"), ("しょとうからしんねん", "しんねん", "信念", "新年"),
        ("かつれつ", "こうしないし", "抗しないし", "仔牛ないし"), ("かつれつ", "こうしないしは", "こうしないしは", "仔牛ないしは"),
        ("ぱぷりか", "こうし", "行使", "仔牛"), ("こうしすねにく", "こうしすね", "こうしスネ", "仔牛すね"),
        ("たいようからのしょうしゃ", "しょうしゃ", "勝者", "照射"),
        ("きょうかいをさだめ", "きょうかい", "教会", "境界"),
        ("ぶんめいをはんえい", "はんえい", "反映", "繁栄"),
        ("ちほうでのこしょう", "こしょう", "故障", "呼称"),
        ("ていきてきにほしゅ", "ほしゅ", "保守", "補酒"),
        ("だんじょうにつみあげ", "だんじょう", "壇上", "段状"),
        ("ざんとうぶんや", "ざんとうぶんや", "残党分野", "残糖分や"),
        ("たいがいにはいしゅつ", "たいがい", "たい街", "体外"),
        ("ひきのばすせいほう", "せいほう", "西方", "製法"),
        ("こぶじょうのかたまり", "こぶじょう", "鼓舞上", "こぶ状"),
        ("ついたぼうで", "ついたぼう", "つい多忙", "ついた棒"),
        ("かじつをおかし", "おかし", "お菓子", "侵し"),
        ("なんぶとされ", "なんぶとされ", "何部賭され", "南部とされ"),
        ("さゆうとうがん", "さゆうとうがん", "左右東岸", "左右と右岸"),
        ("かじつこうやさん", "かじつこうやさん", "果実高野山", "果実香や酸"),
        ("かこうとそうかいなあじ", "かこうとそうかいなあじ", "加工賭そうか否味", "花香と爽快な味"),
        ("どじょうにもつよい", "どじょうにもつよい", "土壌荷物よい", "土壌にも強い"),
        ("つかむような", "つかむよう", "塚無用", "掴むよう"), ("かめるような", "かめるよう", "カメルよう", "噛めるよう"),
        ("していぎむはなし", "していぎむはなし", "指定義務話", "指定義務は無し"),
        ("みやみずはなだ", "みやみずはなだ", "宮水花田", "宮水は灘"),
        ("じょうぞうしゅるいにはせいしゅ", "にはせいしゅ", "に派生種", "には清酒"),
        ("みなみはたん", "みなみはたん", "南破綻", "南はタン"),
        ("きゃべつにはむ", "にはむ", "には無", "にハム"),
        ("におけるはぶ", "はぶ", "は部", "ハブ"),
        ("くしのはさん", "くしのはさん", "駆使のは酸", "クシノは酸"),
        ("なすのすらいす", "なす", "成す", "ナス"),
        ("ぱくちーやしょうが", "やしょうが", "弥正が", "やショウガ"),
        ("きれのよいさん", "きれのよいさん", "斬れのよ遺産", "キレのよい酸"),
        ("きなのきのかわ", "きなのきのかわ", "希なの紀ノ川", "キナの木の皮"),
        ("ちゃのはやくきから", "ちゃのはやくきから", "茶のは訳記から", "チャの葉や茎から"),
        ("ちーずのぱい", "ぱい", "牌", "パイ"),
        ("をようします", "どうろ", "道路", "ドウロ"), ("どうろをようします", "ようします", "要します", "擁します"), ("がいとうするわいん", "どうろ", "道路", "ドウロ"),
        ("さいとうにいち", "さいとう", "さいとう", "最東"), ("さいとうのちほう", "さいとう", "さいとう", "最東"), ("どいつさいとう", "さいとう", "斎藤", "最東"),
        ("えいこくのさいなん", "さいなん", "災難", "最南"), ("さいなんはまるごー", "さいなん", "災難", "最南"),
        ("しろっぽい", "しろ", "城っぽい", "白っぽい"),
        ("ぜんぶどうひんしゅ", "ぜんぶどう", "前ぶどう", "全ぶどう"),
        ("かつぬまちょうない", "ちょうない", "町ない", "町内"),
        ("あまみあるこーる", "あまみ", "奄美", "甘み"),
        ("かぶなんぶのいりえ", "かぶなんぶ", "株南部", "下部南部"),
        ("かいそううみのかおり", "かいそう", "階層", "海藻"),
        ("きってぜんさい", "きってぜんさい", "切手前妻", "切って前菜"),
        ("をふくんだ", "ふくんだ", "吹くんだ", "含んだ"),
        ("つかいかため", "つかいかため", "遣い方目", "使い固め"),
        ("ただしいないようです", "ないよう", "ないよう", "内容"),
        ("がなされ", "なされ", "為され", "なされ"),
        ("おさえておきたい", "おさえて", "抑えて", "押さえて"),
        ("したのち", "したのち", "したの地", "したのち"),
        ("ごなのか", "ごなのか", "語名のか", "語なのか"),
        ("のしやすさ", "のしやすさ", "伸しやすさ", "のしやすさ"),
        ("ひとごこちはながの", "ひとごこち", "人心地", "ひとごこち"),
        ("たるやたんく", "たるや", "樽屋", "樽や"),
        ("ぼなるだしゅや", "しゅや", "主夜", "種や"),
        ("いちばんちゃです", "いちばんちゃです", "1番チャデス", "一番茶です"),
        ("かっしょくはぶらんです", "ぶらんです", "ブランデス", "Brunです"),
        ("りょうりにかすれ", "かすれ", "掠れ", "Cassoulet"),
        ("りーすりんぐとうから", "とうから", "党から", "等から"),
        ("はたのかてごりー", "はたの", "はたの", "は他の"),
        ("せいいくにてきす", "にてきす", "にて記す", "に適す"),
        ("にあるぴこで", "にあるぴこ", "にアルピコ", "にあるピコ"),
        ("とすかーなたいこう", "たいこう", "対抗", "大公"),
        ("それぞれのこうはい", "こうはい", "後輩", "交配"),
        ("からちかく", "ちかく", "ちかく", "近く"),
        ("がめいぶつの", "がめいぶつ", "^Gamay物", "が名物"), ("がめいしょうに", "がめいしょう", "^Gamay省", "が名称"),
        ("あわもちをよくし", "よくし", "抑止", "良くし"),
        // 〜に+とみ で終わる句は 富み(変化に富み/芳香性に非常に富み。富 で止まっていた。に の後ろは動詞。ユーザ指定 3806)。
        // 富む の連用形 富み は格子に立たない(名詞 富 と同じ読みの連用形は作らない)ので、末尾だけ差し替える
        ("にとみ", "にとみ", "に富$", "に富み"),
        // 数字+年にかけて(1968年にかけて が 年に欠けて/年に掛けて。3806)
        ("ねんにかけて", "ねんにかけて", "年に欠けて", "年にかけて"), ("ねんにかけて", "ねんにかけて", "年に掛けて", "年にかけて"),
        ("きたがめどっく", "きたが", "^来たが", "北が"), ("きたがららんど", "きたが", "^来たが", "北が"), ("せんたくしはきたから", "きたから", "来たから", "北から"),
        ("しっとりしあがる", "しあがる", "し上がる", "仕上がる"),
        ("はじめのとしは", "とし", "都市", "年"),
        ("みずからがいったいを", "いったい", "一体", "一帯"),
        ("しょうちくのめいしょう", "しょうちく", "松竹", "小地区"),
        ("りょうしゅうにまたがる", "りょうしゅう", "領収", "両州"),
        ("わらがまいてある", "まいてある", "まいてある", "巻いてある"),
        ("ゔぁっはうにならって", "ならって", "習って", "倣って"),
        ("ゔぁれーとよんでいる", "よんでいる", "読んでいる", "呼んでいる"),
        ("しゅうとみらのはこうぎょう", "こうぎょう", "興行", "工業"),
        ("ぴーくのさんちのはたけ", "さんち", "産地", "山地"),
        ("つぎきしてしんしょく", "しんしょく", "侵蝕", "新植"), ("つぎきしてしんしょく", "しんしょく", "侵食", "新植"),
        ("せんようのほぞんし", "ほぞんし", "保存し", "保存紙"),
        ("おゆをかけて", "かけて", "欠けて", "かけて"), ("ねってひきのば", "ひきのば", "引き延ば", "引き伸ば"),
        ("ゔぇねとしゅうさん", "しゅうさん", "蓚酸", "州産"),
        ("がりあじん", "がりあじん", "ガリアジン", "ガリア人"),
        ("たんしょくであることがおおい", "たんしょく", "単色", "淡色"),
        ("しゅにちかいことがはんめい", "しゅに", "^酒に", "種に"),
        ("ざくせんさん", "ざくせんさん", "ザクセンさん", "ザクセン産"),
        ("せきしゅつ", "しゅせき", "首席", "酒石"), ("せきしゅつ", "しゅせき", "主席", "酒石"), ("せきしゅつ", "しゅせき", "酒席", "酒石"),
        ("ふなづみ", "せんめい", "鮮明", "船名"), ("ふなづみ", "せんめい", "宣明", "船名"),
        ("とくゆうな", "ほうこう", "方向", "芳香"),
        // しようがない の活用形(しようがなかった/しようがなく)。misc の登録語 しようがない は終止形だけ先頭になり、活用形は
        // 使用+が+なかった が先頭だった(ユーザ指定 3801)。使用がなかった は 2 番め
        ("しようがなか", "しようがなか", "使用がなか", "しようがなか"), ("しようがなく", "しようがなく", "使用がなく", "しようがなく"),
        ("かじゅう", "かひ", "可否", "果皮"), ("かじゅう", "かひ", "歌碑", "果皮"),
        // 北から+冷たい(風/空気)。来たから+冷たい はまれ(きたからつめたいかぜ が 来たから冷たい風 だった。ユーザ報告 3697)。
        // かぜ だけ(台風が来たから風が強い)は手掛かりにしない。の が続く形(来たからの)は連文節の規則(3697)で直る
        ("きたからつめたい", "きたから", "来たから", "北から"),
        // learningBOX 検査 3697 の確認表の [直す](3715)。展葉は英語で Leaf growth/Feuillaison(転用)、磁器で有名なマイセン(時期)、
        // マラリアに効用(紅葉)、耐病性が高いぶどう種(葡萄酒)、型に入れホエイ(方)、華吹雪は青森県(花吹雪)、商人によって交易(承認)、
        // ジュニパー/穀類 の ジン(陣)、酵母によって代謝(公募)、Bouchage は打栓(出せん)、内陸ほど暑く(厚く)、海流の寒流(環流)、
        // 黒海と接する東部(頭部)、pH の中性(中世)、越冬できる厳寒(玄関)、品種の改植(会食)、麦芽の糖化(投下)、人気が広まり(任期)、
        // ルーマニアと接する北(来た)
        ("りーふぐろーす", "てんよう", "転用", "展葉"), ("ふいえぞん", "てんよう", "転用", "展葉"),
        ("まいせん", "じきでゆうめい", "時期", "磁器"),
        ("まらりあ", "こうよう", "紅葉", "効用"),
        ("たいびょう", "ぶどうしゅ", "葡萄酒", "ぶどう種"),
        ("ほえい", "かたにいれ", "方に入れ", "型に入れ"),
        ("はなふぶきはあおもりけん", "はなふぶき", "花吹雪", "華吹雪"),
        ("こうえきされ", "しょうにん", "承認", "商人"),
        ("じゅにぱー", "じん", "陣", "ジン"), ("こくるい", "じん", "陣", "ジン"),
        ("たいしゃされ", "こうぼ", "公募", "酵母"),
        ("ぶしゃーじゅ", "だせん", "出せん", "打栓"),
        ("ないりくにはいるほど", "あつく", "厚く", "暑く"),
        ("かいりゅう", "かんりゅう", "環流", "寒流"),
        ("こっかい", "とうぶ", "頭部", "東部"),
        ("ぴーえいち", "ちゅうせい", "中世", "中性"), ("あるかり", "ちゅうせい", "中世", "中性"),
        ("えっとう", "げんかん", "玄関", "厳寒"),
        ("ひんしゅ", "かいしょく", "会食", "改植"),
        ("ばくが", "とうか", "投下", "糖化"),
        ("にんきはせかいじゅうにひろま", "にんき", "任期", "人気"),
        ("せっする", "きたが", "^来たが", "北が"),
        // 最東(さいとう)は 最+東 に割れ、人名 斎藤 に 6000 近く負ける(組の加点では届かない)。位置/産地 が続くときだけ。
        // 豪州ワイン: 江州(令制国の別称、compenser の curated 1500)が強い
        ("さいとうにいちし", "さいとう", "斎藤", "最東"), ("さいとうにいちし", "さいとう", "債等", "最東"),
        ("さいとうのさんち", "さいとう", "斎藤", "最東"), ("さいとうのさんち", "さいとう", "さいとう", "最東"),
        ("ごうしゅうわいん", "ごうしゅう", "江州", "豪州"),
        // カテキンやタンニン(勝て金)、麦芽や酵素剤(夜行素材)、殺菌や清掃(痩せいそう)。読みの区切りごと違うので組の加点が届かない
        ("たんにん", "かてきん", "勝て金", "カテキン"),
        ("ばくが", "やこうそざい", "夜行素材", "や酵素剤"),
        ("さっきん", "やせいそう", "痩せいそう", "や清掃"),
        // 生育に適し(敵視)、赤湯町(待ち。町名の後ろの 待ち)
        ("せいいくにてきし", "てきし", "敵視", "適し"),
        ("あかゆまち", "あかゆまち", "赤湯待ち", "赤湯町"),
        // 地方にある都市(とし。ある+都市 の組にすると ある年 が ある都市 になる)、しっかりと付き(月)
        ("ちほうにあるとし", "あるとし", "あるとし", "ある都市"),
        ("しっかりとつき", "しっかりとつき", "しっかりと月", "しっかりと付き"),
        // learningBOX 検査 3697 の確認表の 4 回めの回答の [直す](3773、2026-11-12)。教材の専門語が一般語の同音語に負ける行を、
        // 前後の読みを手掛かりに差し替える(手掛かりは狭く。定期的に保守を行なう のような一般の文と区別できない行は入れていない)
        // 栽培: 新梢(心象/心証/神将)・短梢(単勝)・長梢(嘲笑)・主幹(主管/主観)は、固定/伸ばす/剪定/針金 などが続くとき
        ("しんしょうのこてい", "しんしょう", "心象", "新梢"), ("しんしょうのこてい", "しんしょう", "心証", "新梢"), ("しんしょうをのばし", "しんしょう", "心象", "新梢"),
        ("しんしょうをはりがね", "しんしょう", "心象", "新梢"), ("ことしのしんしょう", "しんしょう", "心象", "新梢"), ("しんしょうやぼうのかんり", "しんしょうやぼう", "心象野望", "新梢や房"),
        ("しんしょうがかじょうにのび", "しんしょう", "心証", "新梢"), ("しんしょうがかじょうにのび", "しんしょう", "心象", "新梢"), ("しんしょうはことし", "しんしょう", "心象", "新梢"),
        ("しんしょうはことし", "しんしょう", "神将", "新梢"), ("はりがねやぼうにこてい", "やぼう", "野望", "や棒"), ("たんしょうにせんてい", "たんしょう", "単勝", "短梢"),
        ("たんしょうをすう", "たんしょう", "単勝", "短梢"), ("ちょうしょうをとり", "ちょうしょうをと", "嘲笑を取", "長梢をと"), ("しゅかんからさゆうにえだ", "しゅかん", "主管", "主幹"),
        ("しゅかんじょうぶ", "しゅかん", "主管", "主幹"), ("しゅかんにちかいじゅうじつしたえだ", "しゅかん", "主観", "主幹"), ("たんしょうをすうぽんのこし", "すうぽんのこし", "数歩んの腰", "数本残し"),
        // 原水(元帥)・溶解(妖怪)・口中(校注)・果粒(下流)・果房(果帽)・清澄(成長)・補酒(保守)・貴腐(寄付)・蒸きょう(状況)・雹(表)・酵母(公募)・過熟(家塾)・酸化(参加)
        ("げんすいがちかすい", "げんすい", "元帥", "原水"), ("げんすいをこんわ", "げんすい", "元帥", "原水"), ("ようかいがひかくてきすくないげんすい", "げんすい", "元帥", "原水"),
        ("むきえんるいのようかい", "ようかい", "妖怪", "溶解"), ("こうちゅうにのこる", "こうちゅう", "校注", "口中"), ("こうちゅうにのこる", "こうちゅう", "鋼中", "口中"),
        ("かりゅうのおおきさ", "かりゅう", "下流", "果粒"), ("かりゅうのひょうひ", "かりゅう", "下流", "果粒"), ("かりゅうのみいらか", "かりゅう", "下流", "果粒"),
        ("ぶどうのかりゅう", "かりゅう", "下流", "果粒"), ("こさやかりゅう", "やかりゅう", "屋嘉流", "や果粒"), ("かぼうにつくかりゅう", "かぼうにつくかりゅう", "果帽に就くか竜", "果房につく果粒"),
        ("かぼうにはいいろのかび", "かぼう", "果帽", "果房"), ("かびがしょうじ", "しょうじ", "が商事", "が生じ"), ("かびをしょうじ", "しょうじ", "を商事", "を生じ"),
        ("せいちょうはこらーじゅ", "せいちょうはこらーじゅ", "成長はコラージュ", "清澄はCollage"), ("ふぃにんぐはせいちょう", "せいちょう", "成長", "清澄"), ("せいちょうにしようされ", "せいちょう", "成長", "清澄"),
        ("ういやーじゅはほしゅ", "ほしゅ", "保守", "補酒"), ("せいかいはほしゅです", "ほしゅ", "保守", "補酒"), ("きふやたるこう", "きふ", "寄付", "貴腐"),
        ("きふきんをしょうじ", "きふきん", "寄付金", "貴腐菌"), ("きふきんであるぼとりてぃす", "きふきん", "寄付金", "貴腐菌"), ("じょうきょうはげんりょうまい", "じょうきょう", "状況", "蒸きょう"),
        ("ひょうによるひがい", "ひょう", "表", "雹"), ("ひょうのひがい", "ひょう", "表", "雹"), ("こうぼがせいせいするかおり", "こうぼ", "公募", "酵母"),
        ("でんとうてきなこうぼ", "こうぼ", "公募", "酵母"), ("ごとうはいずれも", "ごとう", "後藤", "誤答"), ("かじゅくまたはきふ", "かじゅく", "家塾", "過熟"),
        ("かじゅくによるあまくち", "かじゅく", "家塾", "過熟"), ("さんかじゅくせい", "さんか", "参加", "酸化"), ("もれやさんかのおそれ", "さんか", "参加", "酸化"),
        ("じゅうぶんにさんかさせ", "さんか", "参加", "酸化"),
        // 樹/木(気)・滓(おり/折/オリゴ)
        ("きがこし", "きがこし", "気が枯死", "樹が枯死"), ("きをこし", "きをこし", "気を枯死", "樹を枯死"), ("きのきずからかんせん", "きのきず", "気の傷", "樹の傷"),
        ("きのせいちょうをうながす", "きのせいちょう", "気のせい長", "樹の成長"), ("きかんにきのせいぶん", "きのせいぶん", "気のせい分", "木の成分"), ("しちゅうにきをからませ", "きをからませ", "気を絡ませ", "木を絡ませ"),
        ("きにつるをからませ", "きにつる", "気に鶴", "木につる"), ("しらーずのきがげんそん", "きがげんそん", "木が現存", "樹が現存"), ("はっせいしたおりを", "おりを", "したおりを", "した滓を"),
        ("ちんでんしたおりを", "おりを", "したおりを", "した滓を"), ("しょうじるおりをちんでん", "おりを", "生じるおりを", "生じる滓を"), ("おりをびんくちにあつめる", "おりを", "^おりを", "滓を"),
        ("おりのかくはん", "おりのかくはん", "おりの各藩", "滓の撹拌"), ("おりとははたらきおえたこうぼ", "おりとは", "^おりとは", "滓とは"), ("こうぼのしがい", "しがい", "市街", "死骸"),
        ("おりからうまみ", "おりから", "折から", "滓から"), ("おりからのうまみ", "おりから", "折から", "滓から"), ("たるのなかのおりをかくはん", "おりを", "の折を", "の滓を"),
        ("おりごとこおらせ", "おりごと", "オリゴと", "滓ごと"), ("こおらせばっせんし", "ばっせんし", "抜栓市", "抜栓し"),
        // 料理・醸造・地理のその他(確認表 4 回めの回答)
        ("しちょうそんめい", "しちょうそん", "視聴村", "市町村"), ("とにこんだ", "にこんだ", "2個んだ", "煮込んだ"), ("などでにこんだ", "にこんだ", "2個んだ", "煮込んだ"),
        ("くりーむにこみりょうり", "にこみ", "煮込料理", "煮込み料理"), ("しろわいんむしに", "むしに", "蒸しに", "蒸し煮"), ("しろわいんむしに", "むしに", "蒸し二", "蒸し煮"),
        ("こうがんさよう", "こうがん", "高岩", "抗ガン"), ("さしきのさいにねがで", "さしきのさいにね", "さ式の際に値", "挿し木の際に根"), ("おおうのはげんきん", "げんきん", "現金", "厳禁"),
        ("おおうのはげんきん", "おおう", "おおうのは", "覆うのは"), ("でぶーるまんはほうが", "ほうが", "はほうが", "は萌芽"), ("ばっどばーすとはほうが", "ほうが", "はほうが", "は萌芽"),
        ("たんれいでそふと", "たんれい", "端麗", "淡麗"), ("たんれいでおだやかなうまみ", "たんれい", "端麗", "淡麗"), ("そふとなのみくち", "なのみくち", "ソフト名飲み口", "ソフトな飲み口"),
        ("せいかいはてんようです", "てんよう", "転用", "展葉"), ("せいかいはしょうちくです", "しょうちく", "松竹", "小地区"), ("にっしょうのすくなかったとし", "とし", "都市", "年"),
        ("とくちょうてきなとし", "とし", "都市", "年"), ("かんそうしてあつい", "あつい", "厚い", "暑い"), ("くちにふくんだ", "ふくんだ", "吹くんだ", "含んだ"),
        ("えきたいをてんかし", "てんか", "転化", "添加"), ("ちをはうような", "ちをはう", "血を這う", "地を這う"), ("せっしょくをふやし", "ふやし", "不夜し", "増やし"),
        ("しゅうりょうはおおめ", "おおめ", "大眼", "多め"), ("ふぃろきせらのがいがなく", "がいがなく", "街が無く", "害がなく"), ("きびしいさむさ", "さむさ", "サムさ", "寒さ"),
        ("しだいにしじをえて", "しじ", "指示", "支持"), ("ほぞんりょうのらべる", "ほぞんりょう", "保存量", "保存料"), ("うまみやしおあじ", "うまみやしおあじ", "馬宮塩味", "旨味や塩味"),
        ("さんちやしゅんも", "しゅんもちゅうし", "駿も中止", "旬も注視"), ("どうこくさいほくとうぶ", "どうこくさい", "同国際", "同国最"), ("とうどのたかいかじゅう", "かじゅう", "か中", "果汁"),
        ("だせんはぶしゃーじゅ", "だせん", "打線", "打栓"), ("くりとともに", "くりと", "繰りと", "栗と"), ("くりのはにつつんで", "くりのは", "繰りのは", "栗の葉"),
        ("ねがあさめ", "ねが", "ネガ", "根が"), ("ねやはにきせいして", "ねやはにきせいして", "値や歯に規制して", "根や葉に寄生して"), ("じゅえきをすい", "すい", "樹液を水", "樹液を吸い"),
        ("りょうりのかくをさげ", "かく", "角", "格"), ("なしのじょうぞうしゅ", "なしの", "なしの醸造酒", "梨の醸造酒"), ("じてんがしゃすら", "じてん", "時点", "次点"),
        ("ただしいちめいをえら", "ただしいちめい", "ただし一命", "正しい地名"), ("ざいりょうをそそぎ", "そそぎ", "曽々木", "注ぎ"), ("さんぎょうがかっせいかしはじめ", "かっせいかし", "渇せ生かし", "活性化し"),
        ("かぼうぜんたいにえきを", "えきを", "駅を", "液を"), ("けいこくないにやかん", "けいこくない", "系国内", "渓谷内"), ("じゅえきのいっしゅつ", "いっしゅつ", "一種つ", "溢出"),
        ("たまねぎをいため", "いため", "痛め", "炒め"), ("むぎしょうちゅう", "むぎしょうちゅう", "麦小中", "麦焼酎"), ("えだをふゆのあいだにもやし", "もやし", "にもやし", "に燃やし"),
        ("かきのかせき", "かき", "下記", "牡蠣"), ("つちかったぎじゅつをいかし", "いかし", "異化し", "生かし"), ("あかわいんのみのせいさん", "せいさん", "せいサン", "生産"),
        ("げんりょうやさんちなどのしゅるい", "さんち", "山地", "産地"), ("しろっぽいいろをした", "しろっぽいいろをした", "城っぽい色を下", "白っぽい色をした"), ("れもんのかわでつくる", "かわ", "川", "皮"),
        ("さとうつけのあんず", "さとうつけ", "佐藤付け", "砂糖漬け"), ("てんちゃをいしうす", "てんちゃ", "甜茶", "碾茶"), ("いしうすなどでひく", "ひく", "弾く", "挽く"),
        ("はるとあきにあめ", "あき", "飽き", "秋"), ("いろをかじゅうにうつし", "うつし", "写し", "移し"), ("せかいだいなんいか", "だいなんい", "大南緯", "第何位"),
        ("しょうめいとうのじょうけん", "しょうめいとう", "照明塔", "照明等"), ("かるくあらいしゅしつ", "あらい", "新井", "粗い"), ("ざんとうがせっく", "ざんとう", "残党", "残糖"),
        ("こうぼがとうをえちる", "とうを", "唐を", "糖を"), ("ひだいせずこつぶ", "ひだい", "日題", "肥大"), ("まんぷくのいをしげき", "のいを", "の意を", "の胃を"),
        ("こうしののうみそ", "のうみそ", "能見そ", "脳みそ"), ("ふようど", "ふようど", "不要ど", "腐葉土"), ("かるきしゅう", "かるきしゅう", "カルキ州", "カルキ臭"),
        ("よごれおとし", "よごれ", "ヨゴレ", "汚れ"), ("かいかはえいごで", "かいかは", "開化派", "開花は"), ("かいかはふろれぞん", "かいかは", "開化派", "開花は"),
        ("ほうこうせいにひじょうにとみ", "ほうこうせい", "方向性", "芳香性"), ("めとめとのあいだ", "めとめと", "目と目と", "芽と芽と"), ("つばきかにぞくするのはちゃです", "ちゃです", "チャデス", "茶です"),
        ("あらちゃかこうでむしじかん", "むしじかん", "無視時間", "蒸し時間"), ("むしせいほう", "むしせいほう", "虫西方", "蒸し製法"), ("もくせいのそう", "もくせいのそう", "木星の層", "木製の槽"),
        ("やぎにゅうせいの", "やぎにゅうせいの", "山羊乳清野", "山羊乳製の"), ("いちけんあたりのめんせき", "いちけん", "一件", "一軒"), ("かんぜいりつのていげん", "ていげん", "低減", "逓減"),
        ("かくめぞん", "かくめぞん", "描くメゾン", "各メゾン"), ("かくせいさんしゃが", "かくせいさんしゃ", "核生産者", "各生産者"), ("おなじくぶんのさんち", "おなじくぶん", "おなじく分", "同じ区分"),
        ("きょうかいのみさよう", "きょうかいのみさよう", "協会のみ作用", "教会のミサ用"), ("かきまぜてかくはん", "かくはん", "書く反", "撹拌"), ("つぶえりつみ", "つみ", "積み", "摘み"),
        ("ところもつめるてん", "つめるてん", "積め流転", "摘める点"), ("つつじょうのあげたきじ", "あげたきじ", "上げた記事", "揚げた生地"), ("ぼんちにひらかれ", "ひらかれ", "開かれ", "拓かれ"),
        ("じょうぞうかたちが", "じょうぞうかたち", "醸造形", "醸造家たち"), ("じょうきゅうひんで", "じょうきゅうひん", "上級干ん", "上級品"), ("こうぎょうてきにしきをとおして", "しきをとおして", "し気を通して", "四季を通して"),
        ("じょうぞうをかのうにし", "かのうにし", "可能西", "可能にし"), ("とってつきのそこ", "とってつき", "とって付き", "取っ手付き"), ("しようりょうをさいしょうげん", "しようりょう", "使用料", "使用量"),
        ("おうしのち", "おうしのち", "牡牛の地", "雄牛の血"), ("こううをさけ", "をさけ", "を酒", "を避け"), ("みずぶくれをさけ", "をさけ", "を酒", "を避け"),
        ("しょくごしゅにてきし", "てきし", "敵視", "適し"), ("いせきとうから", "いせきとう", "い石塔", "遺跡等"), ("げんていはされていません", "げんていは", "弦停波", "限定は"),
        ("きりはあさひとともに", "きりは", "切り羽", "霧は"), ("こいかのさかな", "こいか", "来いか", "鯉科"), ("かものこんふぃ", "かもの", "化物", "鴨の"),
        ("かもやはとなど", "かもやはと", "加茂谷は徒", "鴨や鳩"), ("こうみやしきたく", "こうみや", "光宮", "香味や"), ("ちゃばをせいちし", "せいち", "整地", "静置"),
        ("さんがつよく", "さんがつよく", "三月よく", "酸が強く"),
        // 一括検査 3765 の再検査で見つかった退行(3774): 川の名+がわ が 側(ドナウ側/ラ・プラタ側/ロワール側)、ボルドー液 が 駅、
        // 緑の心臓 が ミドリ(リキュールの名)、ぶどう樹は が ぶどう入破、展示品 が 転じひん
        ("どなうがわ", "どなうがわ", "ドナウ側", "ドナウ川"), ("らぷらたがわ", "らぷらたがわ", "ラ・プラタ側", "ラ・プラタ川"),
        ("ろわーるがわ", "ろわーるがわ", "ロワール側", "ロワール川"), ("ぼるどーえき", "ぼるどーえき", "ボルドー駅", "ボルドー液"),
        ("みどりのしんぞう", "みどり", "ミドリの心臓", "緑の心臓"), ("ぶどうじゅは", "ぶどうじゅは", "ぶどう入破", "ぶどう樹は"),
        // 確認表 3697 の 5 回めの回答(固有名詞の節の [直す] 243 行。3776)のうち、語の上限や チリ の扱いで直らなかった行。
        // 行の読みそのものを手掛かりにして、カタカナで書くか原語で書くか以外の違い(区切り・同音語・かな/漢字)だけを差し替える
        // (tools/conversion_audit の near_match.py で『ほぼ一致』になることが目標。scratchpad の gen.py で生成)
        ("ねるそんのまちからないりくにはいり", "ねるそんのまちからないりくにはいり", "には入", "に入"), ("はぷすぶるくていこくのしはいかにはいり", "はぷすぶるくていこくのしはいかにはいり", "には入", "に入"),
        ("れまんこをけいゆしてふらんすにはいり", "れまんこをけいゆしてふらんすにはいり", "には入", "に入"), ("あーるはどいつせいぶにおけるさいほくのちいき", "あーるはどいつせいぶにおけるさいほくのちいき", "るさ以北", "る最北"),
        ("あいはゔぁれどらまるぬちく", "あいはゔぁれどらまるぬちく", "^愛は", "Aÿは"), ("あいはゔぁれどらまるぬちくです", "あいはゔぁれどらまるぬちくです", "^愛は", "Aÿは"),
        ("どーるはおなじくゔぁれーしゅうでつくられる", "どーるはおなじくゔぁれーしゅうでつくられる", "で作ら", "で造ら"), ("ぎずぼーんはきたじまのとうぶ", "ぎずぼーんはきたじまのとうぶ", "の頭部", "の東部"),
        ("ごぶれはみなみふらんす", "ごぶれはみなみふらんす", "^後ブレは", "Gobeletは"), ("こなはあめりかはわいとう", "こなはあめりかはわいとう", "はアメリカハワイ島", "はアメリカ・ハワイ島"),
        ("やまなしけんはこうしゅう", "やまなしけんはこうしゅう", "は甲州", "はKoshu"), ("こうしゅうはやまなしけん", "こうしゅうはやまなしけん", "^高周波山", "Koshuは山"),
        ("りぞんはたい", "りぞんはたい", "は体", "はタイ"), ("ねるそんはみなみじまほくぶのさんちです", "ねるそんはみなみじまほくぶのさんちです", "の山地", "の産地"),
        ("ぴあーゔぇはゔぇねとしゅうさんです", "ぴあーゔぇはゔぇねとしゅうさんです", "州さんで", "州産で"), ("ざくせんはどいつさいひがしにあり", "ざくせんはどいつさいひがしにあり", "ツ際東", "ツ最東"),
        ("どいつではとろっけん", "どいつではとろっけん", "はと6件", "はTrocken"), ("とりのけんはしゅうととりののあるけん", "とりのけんはしゅうととりののあるけん", "の歩けん", "のある県"),
        ("しゃんぱーにゅにせんさいさとしんせんあじをあたえ", "しゃんぱーにゅにせんさいさとしんせんあじをあたえ", "さ都心線味", "さと新鮮味"), ("のちのりゅうけん", "のちのりゅうけん", "^後の", "のちの"),
        ("のちのりゅうけん", "のちのりゅうけん", "龍拳", "龍憲"), ("あかねかにぞくするのはこーひーのきです", "あかねかにぞくするのはこーひーのきです", "ーノキで", "ーの木で"),
        ("ふんぼるとかいりゅうはちりおきのかんりゅうです", "ふんぼるとかいりゅうはちりおきのかんりゅうです", "流八LEO木の", "流はチリ沖の"), ("せいかいはまでらとうです", "せいかいはまでらとうです", "a等で", "a島で"),
        ("せいかいはしりべしちほうです", "せいかいはしりべしちほうです", "解走りべし地", "解は後志地"), ("にっぽんではかずすくない", "にっぽんではかずすくない", "で吐かず少", "では数少"),
        ("みやまにしきはたんれいですっきりしたあじわい", "みやまにしきはたんれいですっきりしたあじわい", "錦破綻例で", "錦は淡麗で"), ("やまがたはせいしゅでははじめてとどうふけんたんいで", "やまがたはせいしゅでははじめてとどうふけんたんいで", "形派生種で", "形は清酒で"),
        ("まいせんはじきでゆうめいなとしです", "まいせんはじきでゆうめいなとしです", "ン弾き出有", "ンは磁器で有"), ("さゔぉいあおうけのもととういつをとげ", "さゔぉいあおうけのもととういつをとげ", "の元統", "のもと統"),
        ("さゔぉいあおうけのもととういつをとげ", "さゔぉいあおうけのもととういつをとげ", "を研げ", "を遂げ"), ("こうしゅうやますかっとべいりーえいは", "こうしゅうやますかっとべいりーえいは", "州屋Muscat Bailey A", "州やマスカット・ベイリーA"),
        ("かるゔぁどすのげんりょうはりんごとなしで", "かるゔぁどすのげんりょうはりんごとなしで", "は林ご", "はりんご"), ("かるゔぁどすのげんりょうはりんごとなしで", "かるゔぁどすのげんりょうはりんごとなしで", "となしで", "と梨で"),
        ("じょーじあさいにしのさんちである", "じょーじあさいにしのさんちである", "ジ浅井西", "ジア最西"), ("うばはすりらんかとうぶさんがくたいでつくられ", "うばはすりらんかとうぶさんがくたいでつくられ", "^乳母は", "ウバは"),
        ("うばはすりらんかとうぶさんがくたいでつくられ", "うばはすりらんかとうぶさんがくたいでつくられ", "はスリランカ東", "はスリランカ・東"), ("うばはすりらんかとうぶさんがくたいでつくられ", "うばはすりらんかとうぶさんがくたいでつくられ", "で作ら", "で造ら"),
        ("えすかはかびのびょうがいのいっしゅで", "えすかはかびのびょうがいのいっしゅで", "^江須賀は", "エスカは"), ("えすかはかびゆらいのびょうがいです", "えすかはかびゆらいのびょうがいです", "^江須賀は", "エスカは"),
        ("せいかいはえすかです", "せいかいはえすかです", "は江須賀で", "はエスカで"), ("きなのじゅひ", "きなのじゅひ", "^規那の", "キナの"),
        ("きなのじゅひをつけこみ", "きなのじゅひをつけこみ", "^規那の", "キナの"), ("ぶるごーにゅのぶどうはたけとくりま", "ぶるごーにゅのぶどうはたけとくりま", "と来間", "とクリマ"),
        ("ぶるごーにゅのぶどうはたけのくりま", "ぶるごーにゅのぶどうはたけのくりま", "の来間", "のクリマ"), ("くりーむはきゅうしょうしぇりーにふくまれるとうきゅう", "くりーむはきゅうしょうしぇりーにふくまれるとうきゅう", "る東急", "る等級"),
        ("りゃてぃこでくれたとうのひんしゅです", "りゃてぃこでくれたとうのひんしゅです", "でくれたとうの", "でクレタ島の"), ("くれたとうでとうじのわいんつくりをしょうめいする", "くれたとうでとうじのわいんつくりをしょうめいする", "^くれ多糖で", "クレタ島で"),
        ("えーげかいからくれたとうへとせいりょくをかくだいし", "えーげかいからくれたとうへとせいりょくをかくだいし", "ら繰れ多糖へ", "らクレタ島へ"), ("せいかいはくれたとうです", "せいかいはくれたとうです", "は繰れ多糖で", "はクレタ島で"),
        ("だふねはくれたとう", "だふねはくれたとう", "は繰れ多糖", "はクレタ島"), ("けるなーのほか", "けるなーのほか", "のほか", "の他"),
        ("ことなりでさんするあまくちわいんがゆうめいです", "ことなりでさんするあまくちわいんがゆうめいです", "^異なりで", "コトナリで"), ("せいかいはことなりです", "せいかいはことなりです", "は異なりで", "はコトナリで"),
        ("しえなはとすかーなしゅうのとし", "しえなはとすかーなしゅうのとし", "^しえ那覇ト", "シエナはト"), ("おらんだじんともよばれるじゅねば", "おらんだじんともよばれるじゅねば", "ダ人と", "ダジンと"),
        ("おらんだじんともよばれるじゅねば", "おらんだじんともよばれるじゅねば", "も呼ば", "もよば"), ("すてぃるわいんにやくそう", "すてぃるわいんにやくそう", "に訳そう", "に薬草"),
        ("すれでぃしゅにゃ", "すれでぃしゅにゃ", "^すれデ", "スレデ"), ("すれでぃしゅにゃ", "すれでぃしゅにゃ", "ィ呪にゃ", "ィシュニャ"),
        ("せれさはえいごでちぇりーのいみで", "せれさはえいごでちぇりーのいみで", "でchellyの", "でチェリーの"), ("くりあでらとそれらのしすてむ", "くりあでらとそれらのしすてむ", "とそれらの", "とソレラの"),
        ("くりあでらとそれらのしすてむではなく", "くりあでらとそれらのしすてむではなく", "とそれらの", "とソレラの"), ("それらからわいんをしゅっかすることを", "それらからわいんをしゅっかすることを", "^それらか", "ソレラか"),
        ("それらはしぇりーのじゅくせいしすてむ", "それらはしぇりーのじゅくせいしすてむ", "^それらは", "ソレラは"), ("せいかいはそんだです", "せいかいはそんだです", "はそんだで", "はソンダで"),
        ("そんだというきょうふうがふく", "そんだというきょうふうがふく", "^損だと", "ソンダと"), ("そんだは", "そんだは", "^損だは", "ソンダは"),
        ("そんだはあるぜんちん", "そんだはあるぜんちん", "^損だは", "ソンダは"), ("しゅようひんしゅはたなです", "しゅようひんしゅはたなです", "は棚で", "はタナで"),
        ("せいさんかのうたいぷはたなしゅたいのあかのみ", "せいさんかのうたいぷはたなしゅたいのあかのみ", "は棚主", "はタナ主"), ("たなしゅたいです", "たなしゅたいです", "^棚主", "タナ主"),
        ("かきのちりのちずで", "かきのちりのちずで", "の塵の", "のチリの"), ("ふらんすからちりにしょうへいされ", "ふらんすからちりにしょうへいされ", "ら散りに", "らチリに"),
        ("ちりなどがあげられます", "ちりなどがあげられます", "が挙げ", "があげ"), ("ちりおきはふんぼるとかいりゅうがながれています", "ちりおきはふんぼるとかいりゅうがながれています", "^地LEO木は", "チリ沖は"),
        ("ふるゔぁつか", "ふるゔぁつか", "ァ塚", "ァツカ"), ("ふるゔぁつこ", "ふるゔぁつこ", "ァつこ", "ァツコ"),
        ("てるすは", "てるすは", "^て留守は", "テルスは"), ("とかいでは", "とかいでは", "^と嗅いで", "トカイで"),
        ("とかいのきふわいんつくり", "とかいのきふわいんつくり", "^都会の", "トカイの"), ("とかいのきふわいんを", "とかいのきふわいんを", "^都会の", "トカイの"),
        ("どうろはすてぃるわいんのこしょうです", "どうろはすてぃるわいんのこしょうです", "^道路は", "ドウロは"), ("どうろはすてぃるわいんのこしょうです", "どうろはすてぃるわいんのこしょうです", "の故障で", "の呼称で"),
        ("なんとしをちゅうしんとするさんちで", "なんとしをちゅうしんとするさんちで", "^何年を", "ナント市を"), ("なんとしをちゅうしんとするちくです", "なんとしをちゅうしんとするちくです", "^何年を", "ナント市を"),
        ("はんぎとはなんか", "はんぎとはなんか", "^版木と", "ハンギと"), ("はんぎりょうりはせんじゅうみんまおりぞくのでんとうしょくで", "はんぎりょうりはせんじゅうみんまおりぞくのでんとうしょくで", "^版木料", "ハンギ料"),
        ("はんせんはこうぼのじゅんすいばいようほう", "はんせんはこうぼのじゅんすいばいようほう", "^帆船は", "ハンセンは"), ("びんげんとぼんのあいだ", "びんげんとぼんのあいだ", "とぼんの", "とボンの"),
        ("ぽどぅなゔぃえ", "ぽどぅなゔぃえ", "^歩どぅナ", "ポドゥナ"), ("ぽどぅなゔぃえ", "ぽどぅなゔぃえ", "ィ画", "ィエ"),
        ("までらのさんちです", "までらのさんちです", "^までらの", "マデラの"), ("までらのじゅくせいにおいて", "までらのじゅくせいにおいて", "^までらの", "マデラの"),
        ("までらとう", "までらとう", "a等", "a島"), ("までらとうのほとんどのちいきでさいばいされ", "までらとうのほとんどのちいきでさいばいされ", "a等の", "a島の"),
        ("るいぱすとぅーるがようしょうきからすごし", "るいぱすとぅーるがようしょうきからすごし", "ら数越", "ら過ごし"), ("おもにだんちほうでさいばいされ", "おもにだんちほうでさいばいされ", "^おもに", "主に"),
        ("おもにだんちほうでさいばいされ", "おもにだんちほうでさいばいされ", "に段地", "にダン地"), ("さんとりーにないで", "さんとりーにないで", "ーニないで", "ー二内で"),
        ("すぺいんた", "すぺいんた", "ンた", "ン他"), ("じょうりゅうのさくしからかりゅうのなかのしにいちし", "じょうりゅうのさくしからかりゅうのなかのしにいちし", "の作詞か", "の佐久市か"),
        ("じょうりゅうのさくしからかりゅうのなかのしにいちし", "じょうりゅうのさくしからかりゅうのなかのしにいちし", "中の死に", "中野市に"), ("せいかいはさがです", "せいかいはさがです", "は差がで", "は佐賀で"),
        ("すぺいんをしんこうしていたいすらむきょうとが", "すぺいんをしんこうしていたいすらむきょうとが", "を進行し", "を侵攻し"), ("きたがららんどどぽむろーるです", "きたがららんどどぽむろーるです", "^来たが", "北が"),
        ("にーむはなんたんとされています", "にーむはなんたんとされています", "は何端", "は南端"), ("にーむはなんたんとされています", "にーむはなんたんとされています", "端賭さ", "端とさ"),
        ("かくひんしゅのしゅようさんちはこんこーどはながのけん", "かくひんしゅのしゅようさんちはこんこーどはながのけん", "^核品", "各品"), ("にっぽんのきこうにあったしたてほうとして", "にっぽんのきこうにあったしたてほうとして", "にあっ", "に合っ"),
        ("おなじくなんべいのちりです", "おなじくなんべいのちりです", "^おなじ", "同じ"), ("おなじくなんべいのちりです", "おなじくなんべいのちりです", "の地理で", "のチリで"),
        ("りおはのなは", "りおはのなは", "の那覇", "の名は"), ("さんみがかずらかくなる", "さんみがかずらかくなる", "が数等核な", "が和らかくな"),
        ("うぃーんしゅうをかこうようにそんざいする", "うぃーんしゅうをかこうようにそんざいする", "を加工用に", "を囲うように"), ("ひがしとみなみにうくらいなにかこまれたくに", "ひがしとみなみにうくらいなにかこまれたくに", "たくに", "た国"),
        ("せいかいはきゅうそれんけんです", "せいかいはきゅうそれんけんです", "連県で", "連圏で"), ("きゅうそれんけん", "きゅうそれんけん", "連県", "連圏"),
        ("かたからだしかしおをしたあと", "かたからだしかしおをしたあと", "^方体しか", "型か"), ("かたからだしかしおをしたあと", "かたからだしかしおをしたあと", "か塩", "から出し加塩"),
        ("こうふぼんちのほくとうにいちしえんざんちく", "こうふぼんちのほくとうにいちしえんざんちく", "し演算地", "し塩山地"), ("ほかのせんたくしであるいき", "ほかのせんたくしであるいき", "る息", "る壱岐"),
        ("ゆいいつめどっくちくがいからえらばれており", "ゆいいつめどっくちくがいからえらばれており", "区買いか", "区外か"), ("おーすとらりあだいぶんすいれい", "おーすとらりあだいぶんすいれい", "ア第分", "ア大分"),
        ("たくまのりひさ", "たくまのりひさ", "^詫間", "宅間"), ("かんせいしたしゃんぱーにゅをこうにゅうし", "かんせいしたしゃんぱーにゅをこうにゅうし", "^管制下シ", "完成したシ"),
        ("ほかにほくとしもかいようせいきこうにぶんるいされます", "ほかにほくとしもかいようせいきこうにぶんるいされます", "斗下海", "斗市も海"), ("ろーまのこくもつことよばれていた", "ろーまのこくもつことよばれていた", "物こと", "物庫と"),
        ("ろーまのこくもつこ", "ろーまのこくもつこ", "物子", "物庫"), ("あとのりゅうけん", "あとのりゅうけん", "龍拳", "龍憲"),
        ("くろあちあとせっし", "くろあちあとせっし", "と摂氏", "と接し"), ("ふらんすこっきょうにせっし", "ふらんすこっきょうにせっし", "に摂氏", "に接し"),
        ("ふらんすとこっきょうをせっし", "ふらんすとこっきょうをせっし", "を摂氏", "を接し"), ("おれんじのかひがしゅはらりょうです", "おれんじのかひがしゅはらりょうです", "原量で", "原料で"),
        ("しんぎりしゃわいんさばいばる", "しんぎりしゃわいんさばいばる", "^芯ギ", "新ギ"), ("しんぎりしゃわいんさばいばる", "しんぎりしゃわいんさばいばる", "ンサ", "ン・サ"),
        ("しんぎりしゃわいんりめいく", "しんぎりしゃわいんりめいく", "^芯ギ", "新ギ"), ("しんぎりしゃわいんりめいく", "しんぎりしゃわいんりめいく", "ンリ", "ン・リ"),
        ("しんぎりしゃわいんるねっさんす", "しんぎりしゃわいんるねっさんす", "^芯ギ", "新ギ"), ("しんぎりしゃわいんるねっさんす", "しんぎりしゃわいんるねっさんす", "ンル", "ン・ル"),
        ("むろまちじだいににっぽんとみん", "むろまちじだいににっぽんとみん", "本都民", "本と明"), ("せいかいはあけのです", "せいかいはあけのです", "は空けので", "は明野で"),
        ("じろんどがわさいかりゅうにいちします", "じろんどがわさいかりゅうにいちします", "川際下", "川最下"), ("じろんどがわのさいかりゅうにいちします", "じろんどがわのさいかりゅうにいちします", "の際下", "の最下"),
        ("ぷろゔぁんすちほうさいにしにいちします", "ぷろゔぁんすちほうさいにしにいちします", "方裁に死に", "方最西に"), ("いたりあさいにしのしゅうである", "いたりあさいにしのしゅうである", "ア際に死の", "ア最西の"),
        ("ほくべいだいぎにつぎきしてしんしょくすることもある", "ほくべいだいぎにつぎきしてしんしょくすることもある", "接ぎ木", "接木"), ("ほくべいだいぎにつぎきしてしんしょくすることもある", "ほくべいだいぎにつぎきしてしんしょくすることもある", "て侵蝕す", "て新植す"),
        ("じぇんしあんのね", "じぇんしあんのね", "のね", "の根"), ("すーずのげんりょうはじぇんしあんのね", "すーずのげんりょうはじぇんしあんのね", "のね", "の根"),
        ("ついでけるなーです", "ついでけるなーです", "^継い", "次い"), ("ついでけるなーです", "ついでけるなーです", "でけるなー", "でケルナー"),
        ("あらんさんどらんすし", "あらんさんどらんすし", "ス市", "ス氏"), ("すぺいんのわいんほうがはっこうされたとしを", "すぺいんのわいんほうがはっこうされたとしを", "ン方が", "ン法が"),
        ("すぺいんのわいんほうがはっこうされたとしを", "すぺいんのわいんほうがはっこうされたとしを", "発行さ", "発効さ"), ("すぺいんのわいんほうがはっこうされたとしを", "すぺいんのわいんほうがはっこうされたとしを", "た都市を", "た年を"),
        ("ぶどうのみなとぼるどー", "ぶどうのみなとぼるどー", "のみなとボ", "の港ボ"), ("ほしのみなとぼるどー", "ほしのみなとぼるどー", "のみなとボ", "の港ボ"),
        ("わいんのみなとぼるどー", "わいんのみなとぼるどー", "のみなとボ", "の港ボ"), ("かんそうこうていでぴーとをもやし", "かんそうこうていでぴーとをもやし", "をもや", "を燃や"),
        ("けいどをふくむねんどしつどじょうをもち", "けいどをふくむねんどしつどじょうをもち", "^経度を", "珪土を"), ("げんとみのおかわいなりー", "げんとみのおかわいなりー", "^弦登", "現登"),
        ("ざくせんさんがただしいくみあわせです", "ざくせんさんがただしいくみあわせです", "ンさんが", "ン産が"), ("にっぽんさんのちゃを", "にっぽんさんのちゃを", "本さんの", "本産の"),
        ("せいかいはとうきょうさんぶどうしようわいんです", "せいかいはとうきょうさんぶどうしようわいんです", "京三部ど", "京産ぶど"), ("せいかいはとうきょうさんぶどうしようわいんです", "せいかいはとうきょうさんぶどうしようわいんです", "うしようワ", "う使用ワ"),
        ("とうきょうさんぶどうしよう", "とうきょうさんぶどうしよう", "京三部ど", "京産ぶど"), ("とうきょうさんぶどうしよう", "とうきょうさんぶどうしよう", "うしよう", "う使用"),
        ("とうきょうさんぶどうしようは", "とうきょうさんぶどうしようは", "京三部ど", "京産ぶど"), ("とうきょうさんぶどうしようは", "とうきょうさんぶどうしようは", "うしようは", "う使用は"),
        ("とうきょうさんぶどうしようわいん", "とうきょうさんぶどうしようわいん", "京三部ど", "京産ぶど"), ("とうきょうさんぶどうしようわいん", "とうきょうさんぶどうしようわいん", "うしようワ", "う使用ワ"),
        ("うめださんぶどうしよう", "うめださんぶどうしよう", "田山武ど", "田産ぶど"), ("うめださんぶどうしよう", "うめださんぶどうしよう", "うしよう", "う使用"),
        ("せっこうしょうのしょうこうでじょうぞうされるほあんちゅう", "せっこうしょうのしょうこうでじょうぞうされるほあんちゅう", "の将校で", "の紹興で"), ("かこうとそうかいなあじをもちます", "かこうとそうかいなあじをもちます", "^書こうと", "花香と"),
        ("かこうとそうかいなあじをもちます", "かこうとそうかいなあじをもちます", "と総会な", "と爽快な"), ("かこうとそうかいなあじをもちます", "かこうとそうかいなあじをもちます", "なあ時を", "な味を"),
        ("かこうとそうかいなあじをもちます", "かこうとそうかいなあじをもちます", "を持ち", "をもち"), ("かこうとそうかいなあじをもつこうちゃです", "かこうとそうかいなあじをもつこうちゃです", "^書こうと", "花香と"),
        ("かこうとそうかいなあじをもつこうちゃです", "かこうとそうかいなあじをもつこうちゃです", "と総会な", "と爽快な"), ("かこうとそうかいなあじをもつこうちゃです", "かこうとそうかいなあじをもつこうちゃです", "なあ時を", "な味を"),
        ("かこうとそうかいなあじをもつこうちゃです", "かこうとそうかいなあじをもつこうちゃです", "を持つ", "をもつ"), ("へらくれすのち", "へらくれすのち", "の地", "の血"),
        ("やぎにゅうせいちーずのしぇーゔるは", "やぎにゅうせいちーずのしぇーゔるは", "乳清チ", "乳製チ"), ("ほうじゅんなあじわいのひょうごけんでうまれたこめです", "ほうじゅんなあじわいのひょうごけんでうまれたこめです", "^芳醇な", "豊潤な"),
        ("あすてぃをつくるけん", "あすてぃをつくるけん", "を作る", "を造る"), ("ろーぬけいこくちほうのみなみにあるとしです", "ろーぬけいこくちほうのみなみにあるとしです", "るとしで", "る都市で"),
        ("しずおかのしゅしつはそうじてさんがすくなく", "しずおかのしゅしつはそうじてさんがすくなく", "てさんが", "て酸が"), ("すずかおろし", "すずかおろし", "^スズカ下し", "鈴鹿おろし"),
        ("ごぜんちゅうのらせれなはきりにおおわれ", "ごぜんちゅうのらせれなはきりにおおわれ", "は切りに", "は霧に"), ("ごぜんちゅうのらせれなはきりにおおわれ", "ごぜんちゅうのらせれなはきりにおおわれ", "におおわ", "に覆わ"),
        ("こうじをつくるためににほんしゅづくりのこうていで", "こうじをつくるためににほんしゅづくりのこうていで", "^工事を", "麹を"), ("もるどゔぁなどをとおりこっかいへつづくかわです", "もるどゔぁなどをとおりこっかいへつづくかわです", "り国会へ", "り黒海へ"),
        // は+ルエダ が人名の 春枝(はるえだ)に割れる(番はRueda が ばん春枝 だった。3777、ユーザ指定: 瑠江/春枝 より ルエダ)
        ("ばんはるえだ", "はるえだ", "春枝", "はRueda"),  // 3846 からは最後のワインの語の並べ替えで はルエダ になる
        // ワインの酸(単独の 酸 の規則から の を外したぶん。3784)、象の鼻は長い
        ("わいんのさんを", "のさんを", "のサンを", "の酸を"), ("わいんのさんで", "のさんで", "のサンで", "の酸で"),
        ("わいんのさんを", "のさんを", "のさんを", "の酸を"), ("わいんのさんで", "のさんで", "のさんで", "の酸で"),
        ("ぞうのはなはなが", "ぞうのはなは", "像のは那覇長", "象の鼻は長"),
        // きげん は連文節でも 期限 を先にして(multiClauseSeedOrderNounBonusesByReading)、打っている途中で 期限/起源 が
        // 入れ替わらないようにした(3843、ユーザ指摘: あ・あっ で 起源、あった で 期限 と入れ替わっていた)。3840 で入れた
        // 「きげんがあった で終われば 期限、のか が続けば 起源」という名指しの規則は外した(入れ替わりの原因。文法上の根拠も無い)
        // 機嫌(きげんがわるい は 起源が悪い だった。期限 を先にしても 期限が悪い になるので、気分の言い回しは名指しで 機嫌 に。3843)
        ("きげんがわる", "きげんがわる", "期限が悪", "機嫌が悪"), ("きげんがいい", "きげんがいい", "期限がいい", "機嫌がいい"),
        ("きげんがよ", "きげんがよ", "期限が良", "機嫌が良"), ("きげんがよ", "きげんがよ", "期限がよ", "機嫌がよ"),
        ("きげんがなお", "きげんがなお", "期限が直", "機嫌が直"), ("きげんをなお", "きげんをなお", "期限を直", "機嫌を直"),
        ("きげんをそこ", "きげんをそこ", "期限を損", "機嫌を損"), ("きげんをと", "きげんをと", "期限を取", "機嫌を取"),
        ("きげんをうかが", "きげんをうかが", "期限を伺", "機嫌を伺"), ("きげんがななめ", "きげんがななめ", "期限が斜め", "機嫌が斜め"),
        // 店の開店(みせのかいてん が 店の回転 だった。ユーザ指定 3841)。店の回転率/回転数/回転寿司 はそのまま(文の終わりと、
        // 助詞・時・前・日 が続くときだけ)
        ("みせのかいてん", "みせのかいてん", "店の回転$", "店の開店"), ("みせのかいてんは", "みせのかいてん", "店の回転は", "店の開店は"),
        ("みせのかいてんが", "みせのかいてん", "店の回転が", "店の開店が"), ("みせのかいてんを", "みせのかいてん", "店の回転を", "店の開店を"),
        ("みせのかいてんに", "みせのかいてん", "店の回転に", "店の開店に"), ("みせのかいてんじ", "みせのかいてん", "店の回転時", "店の開店時"),
        ("みせのかいてんまえ", "みせのかいてん", "店の回転前", "店の開店前"), ("みせのかいてんび", "みせのかいてん", "店の回転日", "店の開店日"),
        // ひどい目に遭う(酷い目 でなく かな。単独の ひどい は かな が先頭。3788、ユーザ指定)
        ("ひどいめにあ", "ひどいめ", "酷い目", "ひどい目"),
        // チリ(国名)を連文節でも通常の語にした(3776)ので、塵/地理 の言い回しを守る
        ("ちりもつも", "ちりも", "チリも積も", "塵も積も"), ("ちりがつも", "ちりが", "チリが積も", "塵が積も"), ("ちりひとつ", "ちりひとつ", "チリ1つ", "塵一つ"),
        ("ちりひとつ", "ちりひとつ", "チリ一つ", "塵一つ"), ("ちりにくわし", "ちりに", "チリに詳", "地理に詳"), ("ちりのてすと", "ちりの", "チリのテスト", "地理のテスト"),
        ("ちりをしらべ", "ちりを", "チリを調べ", "地理を調べ"), ("れきしやちり", "やちり", "やチリ", "や地理"), ("ちりとれきし", "ちりと", "チリと歴史", "地理と歴史"),
        ("ちりとほこり", "ちりとほこり", "チリと誇り", "塵と埃"), ("ごみやちり", "やちり", "やチリ", "や塵"), ("ちりのじゅぎょう", "ちりの", "チリの授業", "地理の授業"),
        ("ちりのせんせい", "ちりの", "チリの先生", "地理の先生"), ("ちりをはらう", "ちりを", "チリを払", "塵を払"),
        ("てんじひんとして", "てんじひん", "転じひん", "展示品"), ("みってるらいん", "みってるらいん", "充ってるLINE", "Mittelrhein"),
        // 2 巡め: には+が の規則のあとに残る 歯(葉)、ビン詰めした都市(年)、雄町、杜松、早摘み など
        ("にはがへんしょく", "にはが", "に歯が", "に葉が"), ("にはのいろがへんしょく", "にはの", "に歯の", "に葉の"), ("すいへいにはがひろが", "にはが", "に歯が", "に葉が"),
        ("にはがようりょくそ", "にはが", "に歯が", "に葉が"), ("なまはにはほぞんせい", "なまはには", "生はには", "生葉には"), ("びんづめしたとし", "とし", "した都市", "した年"),
        ("とうろくされたとし", "とし", "された都市", "された年"), ("せいていされたとし", "とし", "された都市", "された年"),
        ("おまちはこんけつ", "おまちは", "お待ち歯", "雄町は"), ("おまちはひんしゅかいりょう", "おまちは", "お待ち歯", "雄町は"), ("おまちはふくよか", "おまちは", "お待ち歯", "雄町は"),
        ("そうがいによりげんしょう", "そうがいによりげんしょう", "窓外により現象", "霜害により減少"), ("さんとたんにんのばらんす", "たんにん", "担任", "タンニン"), ("ねずのみ", "ねずのみ", "寝ずのみ", "杜松の実"),
        ("せいかいはねず", "はねず", "正解跳ねず", "正解は杜松"), ("はやづみぶどう", "はやづみ", "早摘ぶ", "早摘みぶ"), ("はやづみをいみ", "はやづみ", "早摘を", "早摘みを"),
        ("かじゅくしたかりゅう", "かじゅくしたかりゅう", "か熟したか流", "過熟した果粒"), ("てきしたいどをえら", "てきしたいど", "敵視態度", "適した緯度"), ("みはっこうのぶどう", "みはっこう", "未発行", "未醗酵"),
        ("ぶどうのさとなんよう", "さとなんよう", "差と何葉", "里なんよう"), ("きりがながれるいち", "きりがながれるいち", "きりが流れる一", "霧が流れる位置"), ("とりこむせいほう", "せいほう", "西方", "製法"),
        ("かおりゆたかな", "かおり", "かおり豊か", "香り豊か"), ("せいかいはにゅうさんです", "せいかいはにゅうさん", "せいかい羽生さん", "正解は乳酸"), ("こまかいていれ", "ていれ", "ていれ", "手入れ"),
        ("かんするさだめ", "さだめ", "さだめ", "定め"), ("たいするさだめ", "さだめ", "さだめ", "定め"), ("じんりきでかいをつかい", "かいを", "かいを", "櫂を"),
        ("ほしすもものこうみ", "ほしすもものこうみ", "星李の子海", "干しスモモの香味"), ("めのあらいこしき", "あらいこしき", "洗い粉し気", "粗い漉し器"), ("せいなるかわぎし", "せいなるかわぎし", "せいなる河岸", "聖なる川岸"),
        ("ことしはえてきため", "はえてきため", "は得てきた目", "生えてきた芽"), ("しんしょうをのばし", "のばし", "延ばし", "伸ばし"), ("なんばんつけ", "なんばんつけ", "南蛮付け", "南蛮漬け"),
        ("かじゅうにつけたじょうたい", "つけた", "につけた", "に漬けた"), ("あたためてじゅくせい", "あたためて", "暖めて", "温めて"), ("おおくてさぎょうがちゅうしん", "おおくてさぎょう", "多くて作業", "多く手作業"),
    ]

    // 読みそのままのかなの候補を末尾に置く読みの頭(よぶんだよね は 余分だよね、呼ぶんだよね… の後ろ。かなが 2〜3 番めだった。
    // 3850、ユーザ指定)
    static let kanaLastReadingPrefixes: [String] = ["よぶんだ", "よぶんです"]

    // かなを 2 番めに置く並べ替え(kanaSecondVariantOrdered)の後に呼ぶ。単文節では末尾へ移す。連文節では外す
    // (画面は連文節の候補の後ろに単文節の候補を並べるので、連文節の中の末尾では 3 番めに残る)
    static func kanaLastOrdered(reading: String, candidates: [String], removes: Bool = false) -> [String] {
        guard candidates.count >= 2, kanaLastReadingPrefixes.contains(where: { reading.hasPrefix($0) }),
            candidates.contains(reading) else {
            return candidates
        }
        return candidates.filter { $0 != reading } + (removes ? [] : [reading])
    }

    // 文の頭の読みごとの、頭の表記の並び(3855、ユーザ指定)。先頭の候補の頭がこの表記のどれかなら、頭を並びの順に
    // 差し替えた形を先頭から並べる(後ろは先頭の候補のまま)。はしのほうがいいね が 橋の方がいいね、橋野ほうがいいね、
    // 橋のほうがいいね、端の方がいいね… だった(端/箸/橋 のどれか決められず、比べる ほう はかなが先)
    static let leadingSurfaceOrdersByReadingPrefix: [(readingPrefix: String, surfaces: [String])] = [
        ("はしのほう", ["端のほう", "箸のほう", "橋のほう", "端の方", "箸の方", "橋の方"]),
        // 体や気持ちの具合が すぐれない はかなが先(たいちょうがすぐれない が 体調が優れない、隊長が優れない、体調が勝れない の順だった。
        // 3864、ユーザ指定は 体調。同じ言い回しの 気分/顔色/健康/機嫌/具合 も揃える)。性能が優れない などはそのまま
        ("たいちょうがすぐれ", ["体調がすぐれ", "体調が優れ", "体調が勝れ"]),
        ("きぶんがすぐれ", ["気分がすぐれ", "気分が優れ", "気分が勝れ"]),
        ("かおいろがすぐれ", ["顔色がすぐれ", "顔色が優れ", "顔色が勝れ"]),
        ("けんこうがすぐれ", ["健康がすぐれ", "健康が優れ", "健康が勝れ"]),
        ("きげんがすぐれ", ["機嫌がすぐれ", "機嫌が優れ", "機嫌が勝れ"]),
        ("ぐあいがすぐれ", ["具合がすぐれ", "具合が優れ", "具合が勝れ"]),
        // ひとりいた は単独の ひとり の並び(1人、ひとり、一人)に合わせ、居た の形を続ける(一人板、1人板、一人いた、火取り板 だった。
        // ユーザ指定 3885)。いる/いて も頭の並びを揃える
        ("ひとりいた", ["1人いた", "ひとりいた", "一人いた", "1人居た", "ひとり居た", "一人居た"]),
        ("ひとりい", ["1人い", "ひとりい", "一人い"]),
    ] + ["も", "を", "が", "は", "の"].map { particle in
        // 文の頭の さんま+助詞 は魚(さんまもつかうけどな が 三間も使うけどな、三摩も使うけどな で 秋刀魚 が出なかった。
        // 単独の さんま はかなが先頭のまま。ユーザ指定 3886)
        ("さんま" + particle, ["秋刀魚", "サンマ", "さんま", "三間", "三摩"].map { $0 + particle })
    }

    // て形の後ろの ほしい は補助の用法でかなが先(してほしかった/教えてほしいです/やめてほしくない。して欲しかった が先頭だった。
    // 3859、ユーザ指定)。それが欲しかった/水が欲しい のように動詞に付かない 欲しい は漢字のまま。活用したかなの ほしかった は
    // ラティスに語が無く(ほしい だけ)、全部かなの最良(してほしい)は捨てられて 欲しい への差し替えが先頭になるので、
    // 並びの最後で 先頭の候補の て欲し/で欲し を かなに替えた形を先頭に置き、元の先頭を 2 番めに残す
    static func teHoshiiKanaFirstOrdered(_ candidates: [String]) -> [String] {
        guard let top = candidates.first, top.contains("て欲し") || top.contains("で欲し") else {
            return candidates
        }
        let kana = top.replacingOccurrences(of: "て欲し", with: "てほし").replacingOccurrences(of: "で欲し", with: "でほし")
        return [kana, top] + candidates.filter { $0 != kana && $0 != top }
    }

    static func leadingSurfaceOrdered(reading: String, candidates: [String]) -> [String] {
        // 手がかりは、頭が表の表記の最初の候補(単文節は 橋野ほうがいいね が先頭で、表の表記で始まる候補はその後ろにある。
        // 画面は単文節の先頭を連文節の 2 番めに差し込むので、単文節の先頭も揃えておく)
        guard let rule = leadingSurfaceOrdersByReadingPrefix.first(where: { reading.hasPrefix($0.readingPrefix) }),
            let top = candidates.first(where: { candidate in rule.surfaces.contains(where: { candidate.hasPrefix($0) }) }),
            let head = rule.surfaces.first(where: { top.hasPrefix($0) }) else {
            return candidates
        }
        let rest = top.dropFirst(head.count)
        let lead = rule.surfaces.map { $0 + rest }
        return lead + candidates.filter { !lead.contains($0) }
    }

    // from の先頭が ^ の規則は、先頭の候補の頭にあるときだけ差し替える(持って来たが の 来たが を巻き込まない)

    static func contextCuedHomophoneOrdered(reading: String, candidates: [String]) -> [String] {
        guard var rewritten = candidates.first else { return candidates }
        for rule in contextCuedHomophoneRewrites
        where reading.contains(rule.cue) && reading.contains(rule.targetReading) {
            if rule.from.hasPrefix("^") {
                let head = rule.from.dropFirst()
                if rewritten.hasPrefix(head) {
                    rewritten = rule.to + rewritten.dropFirst(head.count)
                }
            } else if rule.from.hasSuffix("$") {
                // 末尾だけを差し替える($ で終わる from。3806)
                let tail = rule.from.dropLast()
                if rewritten.hasSuffix(tail) {
                    rewritten = rewritten.dropLast(tail.count) + rule.to
                }
            } else if let range = rewritten.range(of: rule.from) {
                rewritten.replaceSubrange(range, with: rule.to)
            }
        }
        var ordered = candidates
        if rewritten != candidates.first {
            ordered = [rewritten] + candidates.filter { $0 != rewritten }
        }
        // 2 番めの指定(その読みの文だけ。3783): 先頭の一部を置き換えた形を 2 番めに置く
        for rule in contextCuedSecondCandidates where reading.contains(rule.cue) {
            guard let top = ordered.first, let range = top.range(of: rule.from) else { continue }
            let second = top.replacingCharacters(in: range, with: rule.to)
            ordered = [top, second] + ordered.dropFirst().filter { $0 != second }
        }
        // 3 番めの指定(その読みの文だけ。3823): 先頭の一部を置き換えた形を 3 番めに置く
        for rule in contextCuedThirdCandidates where reading.contains(rule.cue) {
            guard let top = ordered.first, let range = top.range(of: rule.from) else { continue }
            let third = top.replacingCharacters(in: range, with: rule.to)
            var rest = ordered.filter { $0 != third }
            rest.insert(third, at: min(2, rest.count))
            ordered = rest
        }
        // その読みの文では意味をなさない候補を外す(3820)
        for rule in contextCuedDroppedSurfaces where reading.contains(rule.cue) {
            ordered.removeAll { $0.contains(rule.surface) }
        }
        return ordered
    }

    // 読みに cue を含む文では、surface を含む候補を出さない(よくにている の 欲にている: 欲+かなの にている は意味をなさない。
    // 3820、ユーザ指定)
    // 読みに cue を含む文で、先頭の from を to に置き換えた形を 3 番めに置く(何でしたっけ/なんでしたっけ/ナンでしたっけ。3823、ユーザ指定)
    static let contextCuedThirdCandidates: [(cue: String, from: String, to: String)] = [
        ("なんでしたっけ", "何でしたっけ", "ナンでしたっけ"),
        // 目を醒まして の 3 番めは 目をさまして(3840、ユーザ指定)
        ("めをさま", "を醒ま", "をさま"),
    ]

    static let contextCuedDroppedSurfaces: [(cue: String, surface: String)] = [
        ("よくにてい", "欲にてい"), ("よくにてる", "欲にてる"),
        // らくてん の ら句点/ら区点 は使われない(3865、ユーザ指定)
        ("らくてん", "ら句点"), ("らくてん", "ら区点"),
        // 名詞の 明々後日 に る は付かない(しあさってる が 明々後日る だった。3867、ユーザ指定)
        ("しあさってる", "明々後日る"), ("しあさってる", "明明後日る"),
        // 髪を切る の次の かみを切る(名詞だけかな)は要らない(ユーザ指定 3883)
        ("かみをき", "かみを切"),
        // 人数の直後の 板 は出さない(ひとりいた が 一人板、1人板、火取り板 と 板 ばかりだった。ユーザ指定 3885)
        ("ひとりいた", "板"), ("ふたりいた", "板"), ("にんいた", "人板"), ("ごにんいた", "誤認板"),
    ]

    // 読みの手掛かりがあるとき、先頭の from を to に替えた形を 2 番めに置く(ユーザ指定 3783)。
    // ふくすうかいつけられる は 複数回付けられる の次に、同音の字(浸けられる/漬けられる)でなく かなの 複数回つけられる。
    // 付ける の仲間の並び全体は変えない(この文だけ)
    static let contextCuedSecondCandidates: [(cue: String, from: String, to: String)] = [
        ("ふくすうかいつけられる", "複数回付けられる", "複数回つけられる"),
        // よく似ている の 2 番めは よく煮ている(3820、ユーザ指定)
        ("よくにてい", "似てい", "煮てい"), ("よくにてる", "似てる", "煮てる"),
        // 覚えて〜 の 2 番めは 憶えて〜(おぼえておきなさい の 2 番めが 覚えて起きなさい で 憶えて が出なかった。3819、ユーザ指定)
        ("おぼえて", "覚えて", "憶えて"),
        // 目を醒まして の 2 番めは 目を覚まして(3840、ユーザ指定)
        ("めをさま", "を醒ま", "を覚ま"),
        // 明後日〜 の 2 番めは あさって〜(かな。3863、ユーザ指定)
        ("あさって", "明後日", "あさって"),
        // 明日から〜 の 2 番めは あしたから〜(かな。3867)
        ("あしたから", "明日から", "あしたから"),
        // 放水 の 2 番めは 豊水(3870)
        ("ほうすい", "放水", "豊水"),
        // 振袖/留袖 の 2 番めは送り仮名つき(3879)
        ("ふりそで", "振袖", "振り袖"), ("とめそで", "留袖", "留め袖"),
        // 行きたくなる の 2 番めは 生きたくなる(3881)
        ("いきたくな", "行きたくな", "生きたくな"),
        // 読んだり の 2 番めは 呼んだり、切るハサミ の 2 番めは 切る鋏(3883)
        ("よんだり", "読んだり", "呼んだり"), ("きるはさみ", "切るハサミ", "切る鋏"),
        // 3人いた の次に 3人居た(3885)
        ("にんいた", "人いた", "人居た"),
    ]

    // サ変名詞+の+たびに(3710): 先頭が 〜のたびに/〜の度に で 〜の旅に の変種も並ぶとき(DP がサ変名詞の後ろの たび と判断した。
    // multiClauseSuruNounNoTabiTravelPenalty)、〜のたびに・〜の度に を 1・2 番めに置き、旅 はその後ろへ(ユーザ指定)。
    // 変種の評価は DP の辺の規則を見ないので LM の の→旅 の強さで 旅 が前に来て、変種の枠(3 件、1 巡めは文節の位置ごとに 1 件)の
    // たびの位置を 旅 が取り、変換のたびに が枠から落ちていた
    static func suruNounTabiOrdered(_ candidates: [String]) -> [String] {
        // のたびに と の度に が両方ある先頭(〜のたびに…の度に)は、どちらに揃えても先頭と一致せず先頭が消えるので触らない
        guard let top = candidates.first, !top.contains("の旅に"),
            top.contains("のたびに") != top.contains("の度に"),
            candidates.contains(where: { $0.contains("の旅に") }) else {
            return candidates
        }
        let kana = top.replacingOccurrences(of: "の度に", with: "のたびに")
        let kanji = top.replacingOccurrences(of: "のたびに", with: "の度に")
        var rest = candidates.filter { $0 != kana && $0 != kanji }
        let travel = rest.filter { $0.contains("の旅に") }
        rest.removeAll { $0.contains("の旅に") }
        let lastTabi = rest.lastIndex(where: { $0.contains("のたびに") || $0.contains("の度に") }).map { $0 + 1 } ?? 0
        rest.insert(contentsOf: travel, at: lastTabi)
        return [kana, kanji] + rest
    }

    // 調味料の たれ(3710): 先頭に 名詞+の+たれ(助詞か文末が続く)があれば、タレ の形を 2 番めに置く(ユーザ指定: 焼鳥のたれがない・
    // 焼鳥のタレがない の順。変種は 焼き鳥 の形と同点で並びが定まらない)。動詞 垂れる の活用(水のたれる音/目のたれた犬)は
    // たれ の直後が助詞でないので触らない
    static let tareSauceFollowers: Set<Character> = ["が", "を", "は", "も", "に", "で", "と", "の", "や", "、", "。"]
    static func tareSauceSecondOrdered(_ candidates: [String]) -> [String] {
        guard let top = candidates.first, let range = top.range(of: "のたれ") else {
            return candidates
        }
        let after = top[range.upperBound...].first
        guard after == nil || tareSauceFollowers.contains(after!) else {
            return candidates
        }
        let sauce = top.replacingCharacters(in: range, with: "のタレ")
        var result = candidates.filter { $0 != sauce }
        result.insert(sauce, at: min(1, result.count))
        return result
    }

    // なんか と読んだ 何か(3710): 先頭が 何か なら、なんか の形を 2 番めに置く(ユーザ指定: なんかいってや は 何か言ってや・なんか言ってや)。
    // 変種は seed {なんか, 何か, 南下, 軟化} の順(差 100 刻み)で 南下言ってや が先に並び、かなの なんか は seed 順の対象外で後ろだった。
    // 読みに なにか があるときは 何か がどちらの読みか分からないので触らない
    static func nankaKanaSecondOrdered(reading: String, candidates: [String]) -> [String] {
        guard reading.contains("なんか"), !reading.contains("なにか"), let top = candidates.first,
            top.components(separatedBy: "何か").count == 2 else {
            return candidates
        }
        let kana = top.replacingOccurrences(of: "何か", with: "なんか")
        var result = candidates.filter { $0 != kana }
        result.insert(kana, at: min(1, result.count))
        return result
    }

    // 良く/よく(ユーザ指定 3670): 「悪く」に置き換えられる所は 良く、それ以外(よく知られている/よく見る)は よく。
    // 置き換えられるかは前後の字で近似する: 直後が する/なる/ない の類(良くする/良くなる/良くない)、
    // または直前が が/は/も で直後が文の終わりか て/、(日当たりが良く/相性が良く、)。
    // 直前が助詞(が/は/も/を)か文頭のときだけ見る(程よく/仲良く/心地よく/バランスよく は触らない)
    static let yokuGoodFollowers: [String] = [
        "する", "して", "した", "しま", "しな", "しよ", "すれ", "させ", "され", "さな",
        "なる", "なり", "なっ", "なれ", "なろ", "ない", "なかっ", "なく", "なけ"
    ]
    static func yokuOrthographyOrdered(reading: String, candidates: [String]) -> [String] {
        guard reading.contains("よく"), let top = candidates.first, top.contains("よく") || top.contains("良く") else {
            return candidates
        }
        var characters = Array(top)
        var index = 0
        var changed = false
        while index + 1 < characters.count {
            let isKana = characters[index] == "よ" && characters[index + 1] == "く"
            let isKanji = characters[index] == "良" && characters[index + 1] == "く"
            guard isKana || isKanji else { index += 1; continue }
            let previous: Character? = index > 0 ? characters[index - 1] : nil
            let after = String(characters[(index + 2)...])
            guard previous == nil || "がはもを".contains(previous!), !after.hasPrefix("よく"),
                !(index >= 2 && characters[index - 2] == "よ" && characters[index - 1] == "く") else {
                index += 2
                continue
            }
            let good = yokuGoodFollowers.contains(where: { after.hasPrefix($0) })
                || (previous.map { "がはも".contains($0) } ?? false
                    && (after.isEmpty || after.hasPrefix("て") || after.hasPrefix("、") || after.hasPrefix("。")))
            if good != isKanji {
                characters[index] = good ? "良" : "よ"
                changed = true
            }
            index += 2
        }
        guard changed else { return candidates }
        let rewritten = String(characters)
        return [rewritten] + candidates.filter { $0 != rewritten }
    }

    // 甘味/甘み(ユーザ指定 3670): テイスティング用語やスイーツの話では 甘味、それ以外は 甘み。
    // 読みに味わい・ワイン・菓子の語があれば先頭の候補の 甘み/奄美 を 甘味 に、無ければ 甘味 を 甘み に替える。
    // 甘味料/甘味処(かんみ)は触らない
    static let sweetnessTastingContextReadings: [String] = [
        "さんみ", "にがみ", "しぶみ", "うまみ", "えぐみ", "わいん", "てーすてぃんぐ", "あじわい", "ざんとう", "かじつみ",
        "ぼでぃ", "すいーつ", "わがし", "ようがし", "でざーと", "けーき", "あつみ"
    ]
    static func sweetnessOrthographyOrdered(reading: String, candidates: [String]) -> [String] {
        guard reading.contains("あまみ"), let top = candidates.first else { return candidates }
        let tasting = sweetnessTastingContextReadings.contains(where: { reading.contains($0) })
        var rewritten = top
        if tasting {
            rewritten = rewritten.replacingOccurrences(of: "甘み", with: "甘味")
            // 地名の 奄美(奄美大島/奄美群島/奄美市)は残す
            if !["奄美大島", "奄美群島", "奄美諸島", "奄美市"].contains(where: { rewritten.contains($0) }) {
                rewritten = rewritten.replacingOccurrences(of: "奄美", with: "甘味")
            }
        } else {
            var result = ""
            var rest = Substring(rewritten)
            while let range = rest.range(of: "甘味") {
                result += rest[..<range.lowerBound]
                let tail = rest[range.upperBound...]
                result += (tail.hasPrefix("料") || tail.hasPrefix("処")) ? "甘味" : "甘み"
                rest = tail
            }
            rewritten = result + rest
        }
        guard rewritten != top else { return candidates }
        return [rewritten] + candidates.filter { $0 != rewritten }
    }

    // ワインや酒の話では つくる を 造る に(ユーザ指定 3675)。目的語の名詞が無い文(ブランから作るアイス/から作られます)は
    // 連語表(酒の目的語+造る)が効かないので、読みに酒の語があれば先頭の候補の 作+活用語尾 を 造 に替える。
    // 作品/作業/作家 のように 作 の後ろが漢字の語は触らない
    static let brewingContextReadings: [String] = [
        "わいん", "さけ", "にほんしゅ", "せいしゅ", "しゅぞう", "じょうぞう", "びーる", "しょうちゅう", "ういすきー",
        "ぶらんでー", "りきゅーる", "すぴりっつ", "しぇりー", "しゃんぱーにゅ", "ぶどう", "もろみ", "しゅぼ"
    ]
    static func brewingMakeOrthographyOrdered(reading: String, candidates: [String]) -> [String] {
        guard reading.contains("つく"), !reading.contains(brewingCocktailReading), let top = candidates.first, top.contains("作"),
            brewingContextReadings.contains(where: { reading.contains($0) }) else {
            return candidates
        }
        var characters = Array(top)
        var changed = false
        for index in characters.indices where characters[index] == "作" && index + 1 < characters.count
            && "らりるれろっ".contains(characters[index + 1]) {
            characters[index] = "造"
            changed = true
        }
        guard changed else { return candidates }
        let rewritten = String(characters)
        return [rewritten] + candidates.filter { $0 != rewritten }
    }

    // カクテルの話の つくる は 作る(ユーザ指定 3716)。ワイン+で+造る の連語表が連文節の中で 造る を選ぶので(ワインで造るカクテル)、
    // 読みに かくてる があれば先頭の候補の 造+活用語尾 を 作 に戻す
    static func cocktailMakeOrthographyOrdered(reading: String, candidates: [String]) -> [String] {
        guard reading.contains("つく"), reading.contains(brewingCocktailReading), let top = candidates.first, top.contains("造") else {
            return candidates
        }
        var characters = Array(top)
        var changed = false
        for index in characters.indices where characters[index] == "造" && index + 1 < characters.count
            && "らりるれろっ".contains(characters[index + 1]) {
            characters[index] = "作"
            changed = true
        }
        guard changed else { return candidates }
        let rewritten = String(characters)
        return [rewritten] + candidates.filter { $0 != rewritten }
    }

    // 先頭の候補の語をかなに替えた形を 2 番目に置く語(先ほどの設定が → さきほどの設定が を 2 番目、先程 は 3 番目。
    // ユーザ指定 3672)。変種の並びは LM 順(先程 7649 < さきほど 7792)で、seed の順の表は漢字先頭の seed に効かない
    // 薦め→勧め: 人+に+すすめる は 薦める→勧める→進める の順(ユーザ指定 3679)。連語表は同じ読みの動詞を 1 つしか上げられず、
    // 勧める は対抗として 進める と一緒に下がるので、先頭に 薦め があれば 勧め に替えた形を 2 番目に置く
    static let kanaSecondVariantSurfaces: [String: String] = ["先ほど": "さきほど", "薦め": "勧め"]
    // 連文節のラティスで使う seed。単文節の並びだけを決める短い読み(い の 胃/意/威…。ユーザ指定 3686)は除く:
    // 連文節で seed を使うと 居た/いた のような動詞の い の並びまで変わる(そこにいたね が そこに居たね になった)
    static let singleClauseOnlySeedReadings: Set<String> = ["い"]
    static func multiClauseSeed(_ reading: String) -> [String]? {
        singleClauseOnlySeedReadings.contains(reading) ? nil : KanaKanjiSeedDictionary.seed[reading]
    }

    // 先頭と表記だけが違う候補(ひらがな↔カタカナ。正解はまるき葡萄酒です/正解はマルキ葡萄酒です)を 2 番目に上げる。
    // 別の語に替えた候補(政界は…/静海は…)より、同じ語の別の書き方の方が欲しいはず(ユーザ指定 3716)。
    // 違う所が先頭ではひらがな、候補では 3 字以上のカタカナのときだけ。2 番目がすでに表記違いや固定の組なら触らない
    static func kanaScriptVariantSecond(_ candidates: [String]) -> [String] {
        guard candidates.count >= 3, let top = candidates.first,
            !keepsSecondAgainstSingleBest(top, candidates[1]),
            let index = candidates.indices.dropFirst(2).prefix(8).first(where: { isKanaScriptVariantPair(top, candidates[$0]) })
        else { return candidates }
        var result = candidates
        let variant = result.remove(at: index)
        result.insert(variant, at: 1)
        return result
    }

    // top のひらがなの所を 3 字以上カタカナにしただけの候補か(まるき葡萄酒/マルキ葡萄酒)。2 字(柚花さん/柚花サン)は
    // 敬称や助詞のカタカナ化を拾うので除く(ゆずかさん の 2 番めが 柚花サン になった)
    static func isKanaScriptVariantPair(_ top: String, _ candidate: String) -> Bool {
        let topCharacters = Array(top)
        let characters = Array(candidate)
        guard characters.count == topCharacters.count, candidate != top else { return false }
        var differing = 0
        for index in characters.indices where characters[index] != topCharacters[index] {
            guard ("ァ"..."ヶ").contains(characters[index]), ("ぁ"..."ゖ").contains(topCharacters[index]),
                characters[index].unicodeScalars.first!.value - 0x60 == topCharacters[index].unicodeScalars.first!.value else {
                return false
            }
            differing += 1
        }
        return differing >= 3
    }

    static func kanaSecondVariantOrdered(_ candidates: [String]) -> [String] {
        guard candidates.count >= 2, let top = candidates.first else { return candidates }
        for (kanji, kana) in kanaSecondVariantSurfaces where top.contains(kanji) {
            let variant = top.replacingOccurrences(of: kanji, with: kana)
            guard variant != top else { continue }
            var result = candidates.filter { $0 != variant }
            result.insert(variant, at: 1)
            return result
        }
        return candidates
    }

    // 地名の読み+さん の連文節の並び(単文節の applyPlaceNameSanPreference と同じ方針。3661、ユーザ指定)。
    // おかやまさん が 丘やまさん、おおさかさん に 大坂サン が出て、地名+産 は単文節の後ろにしか無かった
    func placeNameSanOrdered(reading: String, candidates: [String], systemCandidateMode: KanaKanjiCandidateSourceMode) -> [String] {
        let normalized = KanaTextNormalizer.normalizedReading(reading)
        // seed で並びを決めた読み(いしきさん: 人名を先に、地名でもある 一色 は後ろ。3853)は、その並びのまま
        guard candidates.count >= 2, normalized.count >= 4, normalized.hasSuffix("さん"),
            Self.multiClauseSeed(normalized) == nil else {
            return candidates
        }
        // 補った地名(区分 登録。琉球の地名など)は名字と同じ表記が多いので、地名+さん の並べ替えには使わない
        // (はなしろさん が 玻名城さん になり 花城さん が後ろへ回った。3789)
        let places = Set(store.placeNameKinds(for: String(normalized.dropLast(2)))
            .filter { $0.value != Self.registeredPlaceNameKind }.keys
            .filter { containsKanji($0) || Self.isKatakanaString($0) })
        guard places.contains(where: { containsKanji($0) }),
            // 読み全体が辞書の一語(たくさん=沢山/けいさん=計算)なら触らない
            !store.wordCosts(for: normalized).keys.contains(where: { !$0.hasSuffix("さん") && !$0.hasSuffix("産") && !$0.hasSuffix("サン") }) else {
            return candidates
        }
        let learned = Set(store.learnedDictionary()[normalized] ?? [])
        func stem(of candidate: String) -> String? {
            if candidate.hasSuffix("さん") { return String(candidate.dropLast(2)) }
            if candidate.hasSuffix("産") { return String(candidate.dropLast()) }
            return nil
        }
        func isRemoved(_ candidate: String) -> Bool {
            guard !learned.contains(candidate) else { return false }
            if candidate.hasSuffix("サン"), containsKanji(String(candidate.dropLast(2))) { return true }
            return candidate.hasSuffix("産") && Self.isKatakanaString(String(candidate.dropLast()))
                && !places.contains(String(candidate.dropLast()))
        }
        func isJunk(_ candidate: String) -> Bool {
            guard !learned.contains(candidate), let stem = stem(of: candidate) else { return false }
            return !places.contains(stem) && containsKanji(stem) && stem.contains(where: { ("ぁ"..."ゖ").contains($0) })
        }
        let kept = candidates.filter { !isRemoved($0) }
        var result = kept.filter { !isJunk($0) } + kept.filter(isJunk)
        var singleCache: [String]?
        func single() -> [String] {
            if let singleCache { return singleCache }
            let list = self.candidates(for: reading, limit: 10, systemCandidateMode: systemCandidateMode)
            singleCache = list
            return list
        }
        // 先頭の語幹が地名でなく(丘山さん)、地名+さん(岡山さん)が後ろか単文節にあれば先頭へ
        let isPlaceSan: (String) -> Bool = { $0.hasSuffix("さん") && places.contains(String($0.dropLast(2))) && self.containsKanji($0) }
        if let top = result.first, !learned.contains(top), let topStem = stem(of: top), containsKanji(topStem), !places.contains(topStem),
            let placeSan = result.first(where: isPlaceSan) ?? single().first(where: isPlaceSan) {
            result.removeAll { $0 == placeSan }
            result.insert(placeSan, at: 0)
        }
        guard let top = result.first, !top.hasSuffix("産") else {
            return result
        }
        let isPlaceProduce: (String) -> Bool = { $0.hasSuffix("産") && places.contains(String($0.dropLast())) }
        let produce = result.first(where: isPlaceProduce) ?? single().first(where: isPlaceProduce)
        guard let produce else {
            return result
        }
        // 姓として さん が続く実績のある語幹(田中)は 4 番目、それ以外は 2 番目(単文節と同じ)
        let rank = store.wordLMBigramCost(prev: String(produce.dropLast()), cur: "さん") == nil ? 1 : 3
        if let current = result.firstIndex(of: produce), current <= rank {
            return result
        }
        result.removeAll { $0 == produce }
        result.insert(produce, at: min(rank, result.count))
        return result
    }

    // 外来の固有名の表層か: カタカナ(中黒・長音を含む)だけ、またはラテン文字(語の中の空白・ハイフン・アポストロフィ・ピリオド
    // を含む)だけ(問題文の型の加点の対象。3738)
    static func isLoanwordProperNounSurface(_ surface: String) -> Bool {
        guard let first = surface.unicodeScalars.first else {
            return false
        }
        if (0x30A1...0x30FA).contains(first.value) {
            return surface.unicodeScalars.allSatisfy { (0x30A1...0x30FC).contains($0.value) }
        }
        return isLatinLetterScalar(first)
            && surface.unicodeScalars.allSatisfy { isLatinLetterScalar($0) || " -'.’".unicodeScalars.contains($0) }
    }

    static func isLatinLetterScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x41...0x5A, 0x61...0x7A, 0xC0...0x24F:
            return scalar.value != 0xD7 && scalar.value != 0xF7
        default:
            return false
        }
    }

    // X.14 のサブ項目 形式名詞化(3790、ユーザ指定)。経験や境遇を表す形式名詞の 目(ひどい目に遭う/痛い目を見る/憂き目)。
    // オン: 目 の形の直後に、目 を め にした形(ひどいめに遭う)を足す(目 が先。上位 2 つの 目 の形まで)。
    // オフ: 目 の形と対になっている め の形を出さない(読みそのままの全部かなは残す)。
    // 体の 目(そんな目で見る/悲しい目をして)と 語が続く 目(目つき)、めでたい の め を巻き込まないよう、
    // 前は下の表の言い回し、後ろは に遭う/を見る の形か候補の末尾だけ。読みに 言い回しの読み+め が無ければ何もしない
    static let formalNounMeHeads: [(surface: String, reading: String)] = [
        ("ひどい", "ひどい"), ("酷い", "ひどい"), ("痛い", "いたい"), ("いたい", "いたい"), ("つらい", "つらい"), ("辛い", "つらい"),
        ("怖い", "こわい"), ("こわい", "こわい"), ("恐ろしい", "おそろしい"), ("危ない", "あぶない"), ("えらい", "えらい"),
        ("苦しい", "くるしい"), ("悲しい", "かなしい"), ("恥ずかしい", "はずかしい"), ("嫌な", "いやな"), ("いやな", "いやな"),
        ("散々な", "さんざんな"), ("さんざんな", "さんざんな"), ("大変な", "たいへんな"), ("惨めな", "みじめな"), ("みじめな", "みじめな"),
        ("こんな", "こんな"), ("そんな", "そんな"), ("あんな", "あんな"), ("どんな", "どんな"), ("同じ", "おなじ"), ("憂き", "うき"),
        ("いい", "いい"), ("良い", "いい"), ("良い", "よい"), ("おいしい", "おいしい"), ("美味しい", "おいしい"),
    ]
    // 読みの門(言い回しの読み+め)。変換のたびに通るので、候補を見る前にここで落とす(変換速度の予算)
    static let formalNounMeGateReadings: [String] = Array(Set(formalNounMeHeads.map { $0.reading + "め" })).sorted()
    // 目/め の後ろに続いてよい形(に遭う/に会う/に合う/を見る と、その かな)。これ以外は体の 目 や別の語
    static let formalNounMeTails: [String] = ["に遭", "に会", "に合", "に逢", "にあ", "にも遭", "にも会", "にもあ", "を見", "をみ"]
    // 語の途中にも現れる かなの言い回し(かわいい の いい、いたい)は、候補の先頭か、直前がひらがなでないときだけ
    static let formalNounMeBoundaryHeads: Set<String> = ["いい", "いたい", "えらい", "こわい", "つらい"]

    // 候補の中の 形式名詞の 目/め の位置を探す。見つからなければ nil
    static func formalNounMeRange(in text: String, me: Character) -> Range<String.Index>? {
        guard text.contains(me) else { return nil }
        for (head, _) in formalNounMeHeads {
            var searchStart = text.startIndex
            while let headRange = text.range(of: head, range: searchStart..<text.endIndex) {
                searchStart = text.index(after: headRange.lowerBound)
                let meIndex = headRange.upperBound
                guard meIndex < text.endIndex, text[meIndex] == me else { continue }
                if formalNounMeBoundaryHeads.contains(head), headRange.lowerBound > text.startIndex {
                    let before = text[text.index(before: headRange.lowerBound)]
                    if ("ぁ"..."ゖ").contains(before) { continue }
                }
                let after = text.index(after: meIndex)
                if after == text.endIndex || formalNounMeTails.contains(where: { text[after...].hasPrefix($0) }) {
                    return meIndex..<after
                }
            }
        }
        return nil
    }

    static func applyFormalNounMeKana(to candidates: [String], reading: String, enabled: Bool) -> [String] {
        guard reading.contains("め"), formalNounMeGateReadings.contains(where: { reading.contains($0) }) else {
            return candidates
        }
        // 目 の形と、その 目 を め にした形の対(上位 2 つまで)
        var kanaFormByKanjiForm: [String: String] = [:]
        var kanaForms = Set<String>()
        for candidate in candidates {
            guard kanaFormByKanjiForm.count < 2, let range = formalNounMeRange(in: candidate, me: "目") else { continue }
            let kanaForm = candidate.replacingCharacters(in: range, with: "め")
            kanaFormByKanjiForm[candidate] = kanaForm
            kanaForms.insert(kanaForm)
        }
        guard !kanaForms.isEmpty else { return candidates }
        var output: [String] = []
        for candidate in candidates {
            // 対になっている め の形は、オンなら 目 の形の直後に置き直し、オフなら出さない。読みそのままは触らない
            if kanaForms.contains(candidate), candidate != reading {
                continue
            }
            output.append(candidate)
            if enabled, let kanaForm = kanaFormByKanjiForm[candidate], kanaForm != reading {
                output.append(kanaForm)
            }
        }
        return output
    }

    // X.14(序数の め)が『ひらがなが先』のとき、連文節の 助数詞+目(10日目の)を 日め に差し替え、目 の形をその後ろに並べる(3750)。
    // 単文節は applyMeSuffixPreferences が並べるが、連文節の結果には効いておらず 10+にちめのきょう が 日目の… だった(ユーザ報告)。
    // 人目/役目 のような語を巻き込まないよう、数字の直後(文頭)か、候補の中で数字の後ろにある 助数詞+目 だけ。
    // 序数として定着した語(番目/代目/丁目 等。ordinalMeEstablishedStemTailCharacters)は触らない
    static let ordinalMeCounterSurfaces: Set<String> = Set(numericCounterSuffixCandidatesByReading.values.joined())
        .filter { surface in surface.last.map { !ordinalMeEstablishedStemTailCharacters.contains($0) } ?? false }
        // つ(4つ目)は助数詞の表に無いので足す(連文節の結果に つ目 が出たときのため。3789)
        .union(["つ"])
    static func applyOrdinalMeKanaFirst(to candidates: [String], digitPrefixed: Bool) -> [String] {
        func rewritten(_ text: String) -> String {
            let chars = Array(text)
            var result = ""
            var index = 0
            while index < chars.count {
                if chars[index] == "目", index > 0 {
                    // 目 の直前の助数詞(1〜3 字)と、その手前が数字か文頭(数字の直後の入力)か
                    var matched = false
                    for length in 1...min(3, index) {
                        let counter = String(chars[(index - length)..<index])
                        guard ordinalMeCounterSurfaces.contains(counter) else { continue }
                        let before = index - length
                        let afterNumber = before == 0 ? digitPrefixed
                            : (chars[before - 1].isNumber || "一二三四五六七八九十百千何".contains(chars[before - 1]))
                        if afterNumber { matched = true; break }
                    }
                    result.append(matched ? "め" : "目")
                } else {
                    result.append(chars[index])
                }
                index += 1
            }
            return result
        }
        var output: [String] = []
        var seen = Set<String>()
        for candidate in candidates {
            for text in [rewritten(candidate), candidate] where seen.insert(text).inserted {
                output.append(text)
            }
        }
        return output
    }

    // 語+助詞 1 字(しゅうまつが)の先頭を、語だけ(しゅうまつ)の単文節の先頭にそろえる(3726、ユーザ報告)。
    // 単文節=辞書順+補正、連文節=LM で並べるため、週末(BOS 7108)/終末(5419)のように 1 字足しただけで先頭が入れ替わっていた
    // (調査で 2993 読み中 1087 読み)。加点(2720、700)は 語→助詞 の bigram が観測済みのときだけで、週末→が は未観測。
    // 連文節の先頭が「語の読みの別表記+助詞」のときだけ差し替える(区切りが違う 秋葉/青砥 は触らない)。
    // ひらがなを含む表記(青い/会う=述語、彼ら)と、時相名詞(昨日/最近。助詞ごとに手調整済み)は対象外
    func singleTopLeadBeforeParticle(reading: String, candidates: [String], systemCandidateMode: KanaKanjiCandidateSourceMode) -> [String] {
        let normalized = KanaTextNormalizer.normalizedReading(reading)
        // 複合助詞 2 字(とは/には/でも 等)も同じ(いぜんとは→以前とは。3734)
        let tail: String
        if normalized.count >= 4, Self.multiClauseCompoundParticles.contains(String(normalized.suffix(2))) {
            tail = String(normalized.suffix(2))
        } else if let last = normalized.last, Self.multiClauseSingleTopParticleTails.contains(last) {
            tail = String(last)
        } else {
            return candidates
        }
        guard normalized.count >= tail.count + 2,
            let first = candidates.first, first.hasSuffix(tail) else {
            return candidates
        }
        let lead = String(normalized.dropLast(tail.count))
        let firstLead = String(first.dropLast(tail.count))
        // 決まった 語+助詞 では連文節の先頭を残す(とうき+には は 冬季には。単文節の seed 2963 は 陶器 先頭。ユーザ指定 3696)
        if Self.multiClauseSingleTopLeadKeptTails[lead]?.contains(tail) ?? false {
            return candidates
        }
        // 語の読みに seed(人手で決めた並び)があり、連文節の先頭がその seed の表記+助詞なら、ひらがなを含んでも seed の順に
        // 語+助詞 を並べる(よもぎを が 蓬生を 先頭だった。3753、ユーザ指定)。区切りが違う候補はその後ろに残す
        if Self.multiClauseSeedOrderParticleLeadReadings.contains(lead), let seedList = KanaKanjiSeedDictionary.seed[lead], seedList.contains(firstLead) {
            let ordered = seedList.map { $0 + tail }
            return ordered + candidates.filter { !ordered.contains($0) }
        }
        let singles = self.candidates(for: lead, limit: 12, systemCandidateMode: systemCandidateMode)
        guard let singleTop = singles.first, singleTop != firstLead, singleTop != lead,
            singles.contains(firstLead),
            // 両方ともひらがなを含まない 1 語に限る。かなを含むと 聞くか+も(きく+かも の区切り)を キク科も に、
            // 彼ら(連文節が正しい)を単文節の カレラ に、いいの+に を 飯野に に差し替えてしまう
            !singleTop.unicodeScalars.contains(where: { (0x3041...0x3096).contains($0.value) }),
            !firstLead.unicodeScalars.contains(where: { (0x3041...0x3096).contains($0.value) }),
            Self.multiClauseConversationalTemporalNounUnigramCaps[singleTop] == nil,
            Self.multiClauseConversationalTemporalNounUnigramCaps[firstLead] == nil else {
            return candidates
        }
        let promoted = singleTop + tail
        return [promoted] + candidates.filter { $0 != promoted }
    }

    // 同音の漢字による書きかえ(KanjiRewriteTable、3422)を連文節の結果に当てる。ラティスでノードを下げると区切りごと
    // 変わる(颱風 は語コストが高く、台風 を禁止すると たいふうのぜんちょう が 大風の全長 になる)ので、区切りは
    // そのままにして表記だけ差し替える。書きかえ前→後(醗酵→発酵)はどこでも、後→前(回転→廻転)は語の終わり
    // (直後が漢字でない)ときだけ(一丁目→一挺目 のような語の中を巻き込まない)。両方を出すときは好む側を先に並べる。
    // X.9 の組は preference、X.10 の組(臆測/憶測)は lateStandardized で選ぶ(nil のグループは触らない。3570)。
    // 先に『だけ』のグループを全部書きかえ、その結果を基準に『両方』のグループの好む形→他方を並べる(出さない表記を漏らさない)
    static func applyKanjiRewrite(
        _ preference: KanjiRewritePreference?,
        lateStandardized: KanjiRewritePreference? = nil,
        toMultiClauseCandidates candidates: [String],
        everydayException: Bool = true
    ) -> [String] {
        func rewritten(_ text: String, toBefore: Bool, late: Bool) -> String {
            let index = late
                ? (toBefore ? KanjiRewriteTable.lateStandardizedPairsByAfterHead : KanjiRewriteTable.lateStandardizedPairsByBeforeHead)
                : (toBefore ? KanjiRewriteTable.switchablePairsByAfterHead : KanjiRewriteTable.switchablePairsByBeforeHead)
            var result = ""
            var rest = Substring(text)
            while let head = rest.first {
                if let pairs = index[head],
                    let pair = pairs.first(where: { rest.hasPrefix(toBefore ? $0.after : $0.before) }) {
                    let from = toBefore ? pair.after : pair.before
                    let to = toBefore ? pair.before : pair.after
                    let following = rest.dropFirst(from.count).first
                    // X.10 の組は前→後も語の終わりだけ(肝腎症候群→肝心症候群 にしない。3570)。
                    // 決まった複合語の後ろの字(蒸留酒/蒸留所)だけは語の途中でも戻す(定数コメント参照。3695)
                    if (!toBefore && !late) || following.map({ !isKanjiCharacter($0) }) ?? true
                        || (toBefore && !late && following.map({ kanjiRewriteCompoundTailsAllowingRewrite[from]?.contains($0) ?? false }) ?? false) {
                        result += to
                        rest = rest.dropFirst(from.count)
                        continue
                    }
                }
                result.append(head)
                rest = rest.dropFirst()
            }
            return result
        }
        var output: [String] = []
        var seen = Set<String>()
        func append(_ text: String) {
            if seen.insert(text).inserted {
                output.append(text)
            }
        }
        for candidate in candidates {
            // 日常語の例外(了解/回復)。X.10 の組も例外の表に載る語(理屈/理窟。3739)だけ同じに扱う
            let groups = [
                (preference: preference?.demotingEverydayPair(for: candidate, enabled: everydayException), late: false),
                (preference: lateStandardized?.demotingEverydayPair(for: candidate, enabled: everydayException), late: true),
            ].compactMap { group in group.preference.map { (preference: $0, late: group.late) } }
            let showsBoth: (KanjiRewritePreference) -> Bool = { $0 == .bothBeforeFirst || $0 == .bothAfterFirst }
            var base = candidate
            for group in groups where !showsBoth(group.preference) {
                base = rewritten(base, toBefore: group.preference.prefersBefore, late: group.late)
            }
            var preferred = base
            for group in groups where showsBoth(group.preference) {
                preferred = rewritten(preferred, toBefore: group.preference.prefersBefore, late: group.late)
            }
            append(preferred)
            if groups.contains(where: { showsBoth($0.preference) }) {
                append(base)
            }
        }
        return output
    }

    // 変換の本体(KanaKanjiConverter+MultiClause.swift)からも使う
    static func isKanjiCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) || $0.value == 0x3005 }
    }
}
