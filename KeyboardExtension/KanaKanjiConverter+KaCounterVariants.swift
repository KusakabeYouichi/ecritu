import Foundation

// 助数詞「か」の表記(1か所/数か月/何か国 …)の表示制御(2816)。
// 候補列の文字列に対する後段の並べ替えで、接頭(算用数字/数/何/幾、または漢数字)+{か,カ,ヶ,ヵ,箇,個,ケ}+基底(月/国/所/条/年…)
// の組を検出し、同じ接頭+基底の表記ゆれをコンテナー設定の順に並べ直す(オフの表記は候補から外し、無い表記は補生成する)。
// 区切りを変えないので単文節・連文節・表示層のどの経路の文字列にも一様に効く。DP のコスト(数カ国 の LM 統計)は触らない。
// 学習済みの表層はユーザの選択なので並べ替えの対象外(位置を保つ)。
extension KanaKanjiConverter {
    // か の後ろに続く基底(月/国/所/条/村/年/日/郷 …)。助数詞表(本表・数字文脈限定表)の「か」始まりの表層
    // から導出するので、表に か〜 の助数詞を足せば自動で対象になる。か 以外の字で始まる表層(個目/カ浦/箇夜)は
    // 表記ゆれの基底にしない(個目 の 個 は数量の 個 であって か の表記ではない)
    static let kaCounterBases: Set<String> = {
        var bases = Set<String>()
        for table in [numericCounterSuffixCandidatesByReading, digitContextAdditionalCounterSurfacesByReading] {
            for surfaces in table.values {
                for surface in surfaces where surface.first == "か" && surface.count >= 2 {
                    bases.insert(String(surface.dropFirst()))
                }
            }
        }
        return bases
    }()
    static let kaCounterBaseMaxLength: Int = kaCounterBases.map(\.count).max() ?? 1

    private static let kaCounterArabicPrefixCharacters: Set<Character> = Set("0123456789０１２３４５６７８９数何幾")
    private static let kaCounterKanjiNumeralCharacters: Set<Character> = Set("一二三四五六七八九十百千万")

    struct KaCounterOccurrence {
        let variantIndex: Int        // か の位置(Character 配列の添字)
        let coversWholeCandidate: Bool  // 接頭+か+基底 が候補全体(1か所/数か月/三か所)か、文中の一部(数か月前の話)か
        var hasPrefix = true         // 数字・数・何・幾・漢数字の接頭があるか(か条 単独は false)
    }

    // 候補文字列中の「接頭+か+基底」を 1 つ見つける。
    // - 接頭が算用数字/数/何/幾 なら文字列中のどこでも(連文節の 数か月前 等)
    // - 接頭が漢数字なら候補全体が 接頭+か+基底 のときだけ(六ヶ所村 のような地名を巻き込まない)
    // - 接頭なし(か月 単独)は候補先頭のときだけ
    static func kaCounterOccurrence(in chars: [Character]) -> KaCounterOccurrence? {
        for index in chars.indices where KaCounterVariant.allCharacters.contains(chars[index]) {
            // 基底(長い順に照合)
            var matchedBase: Int? = nil
            for length in stride(from: min(kaCounterBaseMaxLength, chars.count - index - 1), through: 1, by: -1) {
                if kaCounterBases.contains(String(chars[(index + 1)..<(index + 1 + length)])) {
                    matchedBase = length
                    break
                }
            }
            guard let baseLength = matchedBase else {
                continue
            }
            // 接頭の判定
            var start = index
            while start > 0, kaCounterArabicPrefixCharacters.contains(chars[start - 1]) {
                start -= 1
            }
            if start < index {
                // 算用/数/何/幾 の接頭。数字列の直前が漢数字なら地名等の一部とみなして対象外
                if start > 0, kaCounterKanjiNumeralCharacters.contains(chars[start - 1]) {
                    continue
                }
                return KaCounterOccurrence(
                    variantIndex: index,
                    coversWholeCandidate: start == 0 && index + 1 + baseLength == chars.count
                )
            }
            var kanjiStart = index
            while kanjiStart > 0, kaCounterKanjiNumeralCharacters.contains(chars[kanjiStart - 1]) {
                kanjiStart -= 1
            }
            if kanjiStart < index {
                // 漢数字接頭は候補全体が一致するときだけ(三か所)
                if kanjiStart == 0, index + 1 + baseLength == chars.count {
                    return KaCounterOccurrence(variantIndex: index, coversWholeCandidate: true)
                }
                continue
            }
            // 接頭なしは候補全体が か+基底(か条/か月 単独)のときだけ。箇条書き のような語の一部は表記ゆれにしない
            // (か条書き が先頭になっていた。ユーザ報告 3435)
            if index == 0, 1 + baseLength == chars.count {
                return KaCounterOccurrence(variantIndex: index, coversWholeCandidate: true, hasPrefix: false)
            }
        }
        return nil
    }

    func applyKaCounterVariantPreference(reading: String, to candidates: [String], precedingCharacter: Character? = nil) -> [String] {
        guard candidates.count >= 1 else {
            return candidates
        }
        let preference = kaCounterVariantPreference
        let enabledOrder = preference.enabledInOrder
        guard !enabledOrder.isEmpty else {
            return candidates
        }
        let normalizedReading = KanaTextNormalizer.normalizedReading(reading)
        let learned = Set(store.learnedDictionary()[normalizedReading] ?? [])

        // skeleton(か を置換した骨格)→ 出現順。学習済みは骨格を持たせず位置固定
        struct Slot {
            let skeleton: [Character]
            let variantIndex: Int
            let coversWholeCandidate: Bool
            let hasPrefix: Bool
        }
        var slots: [String: Slot] = [:]
        var membership: [String] = []  // 各候補が属する骨格キー(空なら独立)
        var touched = false
        for candidate in candidates {
            let chars = Array(candidate)
            guard !learned.contains(candidate), let occurrence = Self.kaCounterOccurrence(in: chars) else {
                membership.append("")
                continue
            }
            var skeleton = chars
            skeleton[occurrence.variantIndex] = "\u{0}"
            let key = String(skeleton)
            if slots[key] == nil {
                slots[key] = Slot(
                    skeleton: skeleton, variantIndex: occurrence.variantIndex,
                    coversWholeCandidate: occurrence.coversWholeCandidate,
                    hasPrefix: occurrence.hasPrefix
                )
            }
            membership.append(key)
            touched = true
        }
        guard touched else {
            return candidates
        }
        // 接頭なし(か条/か国 単独)の組は、後ろにその組より語LMの頻度が高い別の語(過剰/過酷)があれば、その語の後ろへ回す
        // (3435、ユーザ指定: 数字の後ろでないなら 過剰 が先頭)。組の頻度は 箇+基底(箇条/箇所/箇国)で見る。
        // か条/カ国 のような仮名の形は数字とともに使う形で、単独の語としての頻度の目安にならない。
        // 入力欄の直前が数字・数・何・幾(確定済みの 3 の後に かこく)なら回さない(ユーザ指定)
        var candidates = candidates
        let followsCounterPrefix = precedingCharacter.map { Self.kaCounterArabicPrefixCharacters.contains($0) } ?? false
        for (key, slot) in slots where !slot.hasPrefix && !followsCounterPrefix {
            guard let first = membership.firstIndex(of: key) else {
                continue
            }
            var kaForm = slot.skeleton
            kaForm[slot.variantIndex] = "箇"
            let independent = candidates.indices.filter { $0 > first && membership[$0].isEmpty }
            guard !independent.isEmpty else {
                continue
            }
            let unigrams = store.wordLMUnigramCosts(for: [String(kaForm)] + independent.map { candidates[$0] })
            let threshold = unigrams[String(kaForm)] ?? Int.max
            guard let target = independent.first(where: { (unigrams[candidates[$0]] ?? Int.max) < threshold }) else {
                continue
            }
            // 組の要素を target の直後へ移す(相対順は保つ)
            let groupIndices = membership.indices.filter { membership[$0] == key && $0 < target }
            let moved = groupIndices.map { (candidates[$0], membership[$0]) }
            for index in groupIndices.reversed() {
                candidates.remove(at: index)
                membership.remove(at: index)
            }
            let insertAt = target - groupIndices.count + 1
            candidates.insert(contentsOf: moved.map(\.0), at: insertAt)
            membership.insert(contentsOf: moved.map(\.1), at: insertAt)
        }

        var result: [String] = []
        var emittedSlots = Set<String>()
        var seen = Set<String>()
        for (candidate, key) in zip(candidates, membership) {
            if key.isEmpty {
                if seen.insert(candidate).inserted {
                    result.append(candidate)
                }
                continue
            }
            guard emittedSlots.insert(key).inserted, let slot = slots[key] else {
                continue
            }
            // 候補全体が 接頭+か+基底 の組(1か所/六か所/数か月)と、連文節の最良(最初の骨格)は全表記を設定順で出す
            // (無い表記は補生成、オフは出さない)。文中に埋まった 2 つめ以降の骨格(数か月前のはなし 等)は
            // 先頭表記だけにして、表記ゆれで候補欄を埋め尽くさない
            let variantsToEmit = (slot.coversWholeCandidate || emittedSlots.count == 1)
                ? enabledOrder
                : Array(enabledOrder.prefix(1))
            for variant in variantsToEmit {
                var chars = slot.skeleton
                chars[slot.variantIndex] = variant.character
                let form = String(chars)
                if seen.insert(form).inserted {
                    result.append(form)
                }
            }
        }
        return result
    }
}
