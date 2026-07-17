import Foundation

// ラテン(英字)入力のサジェスト。読み検索キーの正規化・二分探索・候補判定を担う。
// 索引 latinSuggestionEntries は起動時に一度構築してキャッシュする。
extension KanaKanjiStore {
    func latinSuggestions(prefix: String, limit: Int) -> [String] {
        guard limit > 0 else {
            return []
        }

        let normalizedPrefix = latinSuggestionSearchKey(prefix, preservesSpaces: true)

        guard !normalizedPrefix.isEmpty else {
            return []
        }

        let entries = latinSuggestionEntries()

        guard !entries.isEmpty else {
            return []
        }

        let startIndex = lowerBoundLatinSuggestionEntryIndex(
            entries: entries,
            for: normalizedPrefix
        )
        var results: [String] = []
        var seenCandidates = Set<String>()
        var index = startIndex

        while index < entries.count,
            entries[index].searchKey.hasPrefix(normalizedPrefix),
            results.count < limit {
            let candidate = entries[index].candidate

            if seenCandidates.insert(candidate).inserted {
                results.append(candidate)
            }

            index += 1
        }

        return results
    }

    func latinSuggestionEntries() -> [LatinSuggestionEntry] {
        if let cached = withCacheLock({ cachedLatinSuggestionEntries }) {
            return cached
        }

        // loadSupplementalSystemDictionary() 自身が cacheLock を取るため、ロックの外で呼ぶ。
        let supplementalDictionary = loadSupplementalSystemDictionary()

        guard !supplementalDictionary.isEmpty else {
            return []
        }

        var seenCandidates = Set<String>()
        var entries: [LatinSuggestionEntry] = []

        for candidates in supplementalDictionary.values {
            for candidate in candidates {
                let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

                guard !trimmedCandidate.isEmpty,
                    seenCandidates.insert(trimmedCandidate).inserted,
                    isLatinSuggestionCandidate(trimmedCandidate) else {
                    continue
                }

                let searchKey = latinSuggestionSearchKey(trimmedCandidate)

                guard !searchKey.isEmpty else {
                    continue
                }

                entries.append(
                    LatinSuggestionEntry(
                        searchKey: searchKey,
                        candidate: trimmedCandidate
                    )
                )
            }
        }

        guard !entries.isEmpty else {
            return []
        }

        entries.sort { lhs, rhs in
            if lhs.searchKey == rhs.searchKey {
                return lhs.candidate.localizedCaseInsensitiveCompare(rhs.candidate) == .orderedAscending
            }

            return lhs.searchKey < rhs.searchKey
        }

        withCacheLock { cachedLatinSuggestionEntries = entries }
        return entries
    }

    func latinSuggestionSearchKey(
        _ text: String,
        preservesSpaces: Bool = false
    ) -> String {
        let trimmed: String

        if preservesSpaces {
            trimmed = text.trimmingCharacters(in: .newlines)
        } else {
            trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !trimmed.isEmpty else {
            return ""
        }

        return trimmed
            .folding(
                options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
                locale: Locale(identifier: "fr_FR")
            )
            .lowercased()
    }

    func isLatinSuggestionCandidate(_ candidate: String) -> Bool {
        guard candidate.range(of: #"[\p{Latin}0-9]"#, options: .regularExpression) != nil else {
            return false
        }

        return candidate.range(
            of: #"^[\p{Latin}\p{M}0-9 \-\.&'’/,+:;()!?]+$"#,
            options: .regularExpression
        ) != nil
    }

    func lowerBoundLatinSuggestionEntryIndex(
        entries: [LatinSuggestionEntry],
        for key: String
    ) -> Int {
        var low = 0
        var high = entries.count

        while low < high {
            let mid = (low + high) / 2

            if entries[mid].searchKey < key {
                low = mid + 1
            } else {
                high = mid
            }
        }

        return low
    }
}
