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
            if index == 0 {
                return KaCounterOccurrence(variantIndex: index, coversWholeCandidate: 1 + baseLength == chars.count)
            }
        }
        return nil
    }

    func applyKaCounterVariantPreference(reading: String, to candidates: [String]) -> [String] {
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
                    coversWholeCandidate: occurrence.coversWholeCandidate
                )
            }
            membership.append(key)
            touched = true
        }
        guard touched else {
            return candidates
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
