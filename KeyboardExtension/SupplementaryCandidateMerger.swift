import Foundation

enum ExternalCandidateLimits {
    static let lookupMultiplier = 2
    static let minimumConverterSlots = 8
    static let preferredConverterSharePercent = 67
    static let shortReadingMaximumLength = 2
    static let shortReadingMinimumConverterSlots = 20
}

enum SupplementaryCandidateMerger {
    static func mergeSupplementaryAndConverterCandidates(
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

        // 補完候補(連絡先・ユーザー辞書 等)が一切表示されなくなる事態を防ぐため、
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

    // ユーザ方針: 「出来る」系は候補に出してよいが、必ず「できる」系より後ろ。
    // 「出来」の直後がひらがな(できる活用の頭 る/た/て/ま/な/ち/れ)で、同一リストに
    // 「でき」へ置換した版が存在する場合のみ、漢字版をかな版の直後へ回す。
    // 出来事/出来高/出来上がる 等(直後が漢字 or 「あ」等)は対象外。
    static func demotingDekiKanjiBelowKana(_ candidates: [String]) -> [String] {
        let dekiInflectionHeads: Set<Character> = ["る", "た", "て", "ま", "な", "ち", "れ"]
        let candidateSet = Set(candidates)

        func kanaCounterpart(of candidate: String) -> String? {
            guard let range = candidate.range(of: "出来") else { return nil }
            guard range.upperBound < candidate.endIndex,
                dekiInflectionHeads.contains(candidate[range.upperBound]) else {
                return nil
            }
            let kana = candidate.replacingOccurrences(of: "出来", with: "でき")
            return (kana != candidate && candidateSet.contains(kana)) ? kana : nil
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
