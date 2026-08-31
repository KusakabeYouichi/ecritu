import Foundation

enum ExternalCandidateLimits {
    static let lookupMultiplier = 2
    static let minimumConverterSlots = 8
    static let preferredConverterSharePercent = 67
    static let shortReadingMaximumLength = 2
    static let shortReadingMinimumConverterSlots = 20
}

enum SupplementaryCandidateMerger {
    // 連絡先候補の「窓」: エンジン候補3つの直後(4番目)に連絡先由来の先頭1件を前出しする
    // (2026-08-31 ユーザ要望: 登録済みの名前が17番目では遠い)。学習等で既に4番目以内に
    // 居る場合は動かさない。2件目以降の連絡先は従来の補完位置のまま。
    static let contactWindowIndex = 3

    static func mergeSupplementaryAndConverterCandidates(
        reading: String,
        supplementaryCandidates: [String],
        converterCandidates: [String],
        contactCandidates: [String] = [],
        limit: Int
    ) -> [String] {
        // コアには早期return(limit到達)が複数あるため、窓の適用は必ずこのラッパーで行う
        var merged = mergeCoreWithoutContactWindow(
            reading: reading,
            supplementaryCandidates: supplementaryCandidates,
            converterCandidates: converterCandidates,
            limit: limit
        )
        applyContactWindow(to: &merged, contactCandidates: contactCandidates, limit: limit)
        return merged
    }

    private static func mergeCoreWithoutContactWindow(
        reading: String,
        supplementaryCandidates: [String],
        converterCandidates: [String],
        limit: Int
    ) -> [String] {
        guard limit > 0 else {
            return []
        }

        let uniqueConverterCandidates = uniqueTrimmedCandidates(from: converterCandidates)

        guard !supplementaryCandidates.isEmpty else {
            return Array(uniqueConverterCandidates.prefix(limit))
        }

        let normalizedReading = KanaTextNormalizer.normalizedReading(reading)
        let preliminaryMinimumConverterSlots: Int

        if normalizedReading.count <= ExternalCandidateLimits.shortReadingMaximumLength {
            preliminaryMinimumConverterSlots = max(
                ExternalCandidateLimits.minimumConverterSlots,
                ExternalCandidateLimits.shortReadingMinimumConverterSlots
            )
        } else {
            preliminaryMinimumConverterSlots = ExternalCandidateLimits.minimumConverterSlots
        }

        // 補完候補(連絡先・ユーザ辞書 等)が一切表示されなくなる事態を防ぐため、
        // limit に対して最低限の補完スロットを確保する。
        // 例: limit=14 で短い読み(≤2文字)の場合、preliminary が 20 だと supplementaryLimit=0 となり
        // 連絡先「麻理(まり)」のようなユーザー指定候補が完全に消える。
        let supplementaryReserveSlots = min(
            supplementaryCandidates.count,
            max(2, limit / 4)
        )
        let minimumConverterSlots = min(
            preliminaryMinimumConverterSlots,
            max(0, limit - supplementaryReserveSlots)
        )

        let converterSlotTarget = min(
            uniqueConverterCandidates.count,
            max(
                minimumConverterSlots,
                (limit * ExternalCandidateLimits.preferredConverterSharePercent) / 100
            )
        )
        let supplementaryLimit = max(0, limit - converterSlotTarget)
        let prioritizedSupplementary = prioritizedSupplementaryCandidates(
            from: supplementaryCandidates,
            limit: supplementaryLimit
        )

        var mergedCandidates: [String] = []
        var seenCandidates = Set<String>()

        for candidate in uniqueConverterCandidates.prefix(converterSlotTarget) {
            guard seenCandidates.insert(candidate).inserted else {
                continue
            }

            mergedCandidates.append(candidate)

            if mergedCandidates.count >= limit {
                break
            }
        }

        guard mergedCandidates.count < limit else {
            return mergedCandidates
        }

        for candidate in prioritizedSupplementary {
            guard seenCandidates.insert(candidate).inserted else {
                continue
            }

            mergedCandidates.append(candidate)

            if mergedCandidates.count >= limit {
                break
            }
        }

        guard mergedCandidates.count < limit else {
            return mergedCandidates
        }

        for candidate in uniqueConverterCandidates.dropFirst(converterSlotTarget) {
            guard seenCandidates.insert(candidate).inserted else {
                continue
            }

            mergedCandidates.append(candidate)

            if mergedCandidates.count >= limit {
                break
            }
        }

        return mergedCandidates
    }

    private static func applyContactWindow(
        to mergedCandidates: inout [String],
        contactCandidates: [String],
        limit: Int
    ) {
        guard let firstContact = contactCandidates.first(where: { !$0.isEmpty }) else {
            return
        }

        if let currentIndex = mergedCandidates.firstIndex(of: firstContact) {
            guard currentIndex > contactWindowIndex else {
                return
            }
            mergedCandidates.remove(at: currentIndex)
            mergedCandidates.insert(firstContact, at: min(contactWindowIndex, mergedCandidates.count))
            return
        }

        mergedCandidates.insert(firstContact, at: min(contactWindowIndex, mergedCandidates.count))

        if mergedCandidates.count > limit {
            mergedCandidates.removeLast()
        }
    }

    private static func prioritizedSupplementaryCandidates(
        from candidates: [String],
        limit: Int
    ) -> [String] {
        guard limit > 0 else {
            return []
        }

        let normalizedCandidates = uniqueTrimmedCandidates(from: candidates)

        guard normalizedCandidates.count > limit else {
            return normalizedCandidates
        }

        let tailQuota = min(max(1, limit / 3), max(0, limit - 1))
        let headQuota = max(0, limit - tailQuota)

        var prioritizedCandidates: [String] = Array(normalizedCandidates.prefix(headQuota))
        var seenCandidates = Set(prioritizedCandidates)

        for candidate in normalizedCandidates.suffix(tailQuota) {
            guard seenCandidates.insert(candidate).inserted else {
                continue
            }

            prioritizedCandidates.append(candidate)
        }

        if prioritizedCandidates.count >= limit {
            return Array(prioritizedCandidates.prefix(limit))
        }

        for candidate in normalizedCandidates {
            guard seenCandidates.insert(candidate).inserted else {
                continue
            }

            prioritizedCandidates.append(candidate)

            if prioritizedCandidates.count >= limit {
                break
            }
        }

        return prioritizedCandidates
    }

    // やる の当て表記(Sudachi 収穫)。かな正書を先頭にするための降格対象。
    static let yaruKanjiSurfaces = ["演", "犯", "飲", "行", "遣", "殺", "姦"]
    // やる の活用語尾の頭文字(やって/やった/やり/やら/やれ/やろ)。
    static let yaruInflectionHeads: Set<Character> = ["っ", "り", "ら", "れ", "ろ", "る"]

    // 漢字表層をかなへ置換した版が同一リストにあるとき、その置換版を返す。置換対象の直後が
    // 活用語尾の頭文字であることを要求し、複合語(出来事/行方 等)への誤爆を防ぐ。
    private static func kanaCounterpartByReplacement(
        of candidate: String,
        kanji: String,
        kana: String,
        inflectionHeads: Set<Character>,
        candidateSet: Set<String>
    ) -> String? {
        guard let range = candidate.range(of: kanji) else { return nil }
        guard range.upperBound < candidate.endIndex,
            inflectionHeads.contains(candidate[range.upperBound]) else {
            return nil
        }
        let replaced = candidate.replacingOccurrences(of: kanji, with: kana)
        return (replaced != candidate && candidateSet.contains(replaced)) ? replaced : nil
    }

    // ユーザ方針: 「出来る」系は候補に出してよいが、必ず「できる」系より後ろ。
    // 「出来」の直後がひらがな(できる活用の頭 る/た/て/ま/な/ち/れ)で、同一リストに
    // 「でき」へ置換した版が存在する場合のみ、漢字版をかな版の直後へ回す。
    // 出来事/出来高/出来上がる 等(直後が漢字 or 「あ」等)は対象外。
    static func demotingDekiKanjiBelowKana(_ candidates: [String]) -> [String] {
        let dekiInflectionHeads: Set<Character> = ["る", "た", "て", "ま", "な", "ち", "れ"]
        let candidateSet = Set(candidates)

        func kanaCounterpart(of candidate: String) -> String? {
            if let kana = kanaCounterpartByReplacement(
                of: candidate,
                kanji: "出来",
                kana: "でき",
                inflectionHeads: dekiInflectionHeads,
                candidateSet: candidateSet
            ) {
                return kana
            }
            // やる も同じ扱い(ユーザ方針: やる系はかなが先頭)。演る/犯る/飲る/行る/遣る/殺る
            // といった当て表記は候補に残してよいが、必ず かな版の後ろ。基底を抑制すると活用形の
            // 生成元ごと消えて候補ゼロになるため、抑制ではなく並べ替えで対処する(2564)。
            for kanji in Self.yaruKanjiSurfaces {
                if let kana = kanaCounterpartByReplacement(
                    of: candidate,
                    kanji: kanji,
                    kana: "や",
                    inflectionHeads: Self.yaruInflectionHeads,
                    candidateSet: candidateSet
                ) {
                    return kana
                }
            }
            return nil
        }

        var result: [String] = []
        var deferred: [String: [String]] = [:]  // かな版 -> その直後に置く漢字版群

        for candidate in candidates {
            if let kana = kanaCounterpart(of: candidate), !result.contains(kana) {
                deferred[kana, default: []].append(candidate)
                continue
            }
            result.append(candidate)
            if let pending = deferred.removeValue(forKey: candidate) {
                result.append(contentsOf: pending)
            }
        }
        // かな版は必ず候補集合に存在する(kanaCounterpart のガード)ため保留は全て解消される。
        // 念のため未解消分があれば元順で末尾に戻し、候補欠落を防ぐ。
        for pending in deferred.values.flatMap({ $0 }) where !result.contains(pending) {
            result.append(pending)
        }
        return result
    }

    private static func uniqueTrimmedCandidates(from candidates: [String]) -> [String] {
        var result: [String] = []
        var seen = Set<String>()

        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmed.isEmpty,
                seen.insert(trimmed).inserted else {
                continue
            }

            result.append(trimmed)
        }

        return result
    }
}
