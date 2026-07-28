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
        let startIndex = lowerBoundLatinSuggestionEntryIndex(
            entries: entries,
            for: normalizedPrefix
        )
        var results: [String] = []
        var seenCandidates = Set<String>()
        var seenSearchKeys = Set<String>()
        var index = startIndex

        while index < entries.count,
            entries[index].searchKey.hasPrefix(normalizedPrefix),
            results.count < limit {
            let candidate = entries[index].candidate

            if seenCandidates.insert(candidate).inserted {
                results.append(candidate)
                seenSearchKeys.insert(entries[index].searchKey)
            }

            index += 1
        }

        // 汎用語彙(別レイヤー)は追加語彙の後ろへ頻度順で合流する。追加語彙と同キー
        // (ワイン用語の rouge と汎用 rouge 等)は追加語彙が勝つ(先勝ちdedupe)。
        if results.count < limit {
            for suggestion in genericLatinLexiconSuggestions(
                normalizedPrefix: normalizedPrefix,
                limit: limit - results.count,
                excludedSearchKeys: seenSearchKeys
            ) where seenCandidates.insert(suggestion).inserted {
                results.append(suggestion)
            }
        }

        return results
    }

    // 汎用Latinサジェスト語彙(同梱 LatinSuggestionLexicon.json)から接頭辞一致を頻度順で返す。
    func genericLatinLexiconSuggestions(
        normalizedPrefix: String,
        limit: Int,
        excludedSearchKeys: Set<String>
    ) -> [String] {
        guard limit > 0 else {
            return []
        }

        let entries = genericLatinLexiconEntries()

        guard !entries.isEmpty else {
            return []
        }

        var low = 0
        var high = entries.count

        while low < high {
            let mid = (low + high) / 2

            if entries[mid].searchKey < normalizedPrefix {
                low = mid + 1
            } else {
                high = mid
            }
        }

        var matched: [GenericLatinLexiconEntry] = []
        var index = low

        while index < entries.count, entries[index].searchKey.hasPrefix(normalizedPrefix) {
            // 追加語彙が既に出したキーは出さない(rouge 等は追加語彙側が勝つ)。入力と同じ
            // 表記そのものの除外は提示層が行う(polizei→Polizei の大文字矯正は残したい)。
            if !excludedSearchKeys.contains(entries[index].searchKey) {
                matched.append(entries[index])
            }
            index += 1
        }

        matched.sort { lhs, rhs in
            if lhs.rank == rhs.rank {
                return lhs.candidate < rhs.candidate
            }
            return lhs.rank < rhs.rank
        }

        return matched.prefix(limit).map(\.candidate)
    }

    func setGenericLatinLexiconEnabledLanguages(_ languages: Set<String>) {
        withCacheLock {
            guard genericLatinLexiconEnabledLanguages != languages else {
                return
            }
            genericLatinLexiconEnabledLanguages = languages
            cachedGenericLatinLexiconEntries = nil
        }
    }

    // 同梱の頻度リストから有効言語分のソート済み索引を構築してキャッシュする。
    // 言語間で同綴りの語(en/fr/de 共通の information 等)は最良 rank の1件に畳む。
    func genericLatinLexiconEntries() -> [GenericLatinLexiconEntry] {
        if let cached = withCacheLock({ cachedGenericLatinLexiconEntries }) {
            return cached
        }

        let enabledLanguages = withCacheLock { genericLatinLexiconEnabledLanguages }

        let url = genericLatinLexiconFileURLOverride
            ?? Bundle(for: KanaKanjiStore.self).url(
                forResource: "LatinSuggestionLexicon", withExtension: "json"
            )

        guard !enabledLanguages.isEmpty,
            let url,
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            withCacheLock { cachedGenericLatinLexiconEntries = [] }
            return []
        }

        var bestByCandidate: [String: GenericLatinLexiconEntry] = [:]

        for (language, words) in decoded where enabledLanguages.contains(language) {
            for (rank, word) in words.enumerated() {
                let searchKey = latinSuggestionSearchKey(word)

                guard !searchKey.isEmpty else {
                    continue
                }

                if let existing = bestByCandidate[word], existing.rank <= rank {
                    continue
                }

                bestByCandidate[word] = GenericLatinLexiconEntry(
                    searchKey: searchKey,
                    candidate: word,
                    rank: rank
                )
            }
        }

        var entries = Array(bestByCandidate.values)
        entries.sort { lhs, rhs in
            if lhs.searchKey == rhs.searchKey {
                return lhs.rank < rhs.rank
            }
            return lhs.searchKey < rhs.searchKey
        }

        withCacheLock { cachedGenericLatinLexiconEntries = entries }
        return entries
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
