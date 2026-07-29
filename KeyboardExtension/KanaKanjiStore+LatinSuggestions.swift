import Foundation

// ラテン(英字)入力のサジェスト。読み検索キーの正規化・二分探索・候補判定を担う。
// 索引 latinSuggestionEntries は起動時に一度構築してキャッシュする。
extension KanaKanjiStore {
    // 語句全体(空白込みトークン)で一致ゼロのときは、空白/改行の直後から検索を
    // やり直して段階的に縮める(grand ch→ch)。空白入りentry(追加語彙のワイン語句等)の
    // 最長一致補完を優先しつつ、1語entryしか無い汎用リストも2語目以降で効くようにする。
    func latinSuggestions(prefix: String, limit: Int) -> [String] {
        var query = prefix

        while true {
            let results = latinSuggestionsForToken(prefix: query, limit: limit)

            if !results.isEmpty {
                return results
            }

            guard let boundary = query.rangeOfCharacter(from: .whitespacesAndNewlines) else {
                return []
            }

            query = String(query[boundary.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !query.isEmpty else {
                return []
            }
        }
    }

    private func latinSuggestionsForToken(prefix: String, limit: Int) -> [String] {
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

    // 汎用Latinサジェスト語彙(同梱 LatinSuggestionLexicon_{lang}.txt)から接頭辞一致を
    // 頻度順で返す。言語別のキー順ソート済みリストをそれぞれ二分探索し、rank で合流する。
    func genericLatinLexiconSuggestions(
        normalizedPrefix: String,
        limit: Int,
        excludedSearchKeys: Set<String>
    ) -> [String] {
        guard limit > 0 else {
            return []
        }

        let enabledLanguages = withCacheLock { genericLatinLexiconEnabledLanguages }

        guard !enabledLanguages.isEmpty else {
            return []
        }

        var matched: [GenericLatinLexiconEntry] = []

        for language in enabledLanguages.sorted() {
            let entries = genericLatinLexiconEntries(language: language)

            guard !entries.isEmpty else {
                continue
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

            var index = low

            while index < entries.count, entries[index].searchKey.hasPrefix(normalizedPrefix) {
                // 追加語彙が既に出したキーは出さない(rouge 等は追加語彙側が勝つ)。入力と同じ
                // 表記そのものの除外は提示層が行う(polizei→Polizei の大文字矯正は残したい)。
                if !excludedSearchKeys.contains(entries[index].searchKey) {
                    matched.append(entries[index])
                }
                index += 1
            }
        }

        // 言語間で同綴りの語(en/fr/de 共通の information 等)は最良 rank の1件に畳む
        var bestRankByCandidate: [String: Int] = [:]

        for entry in matched {
            if let existing = bestRankByCandidate[entry.candidate], existing <= entry.rank {
                continue
            }
            bestRankByCandidate[entry.candidate] = entry.rank
        }

        return bestRankByCandidate
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value < rhs.value
            }
            .prefix(limit)
            .map(\.key)
    }

    func setGenericLatinLexiconEnabledLanguages(_ languages: Set<String>) {
        withCacheLock {
            guard genericLatinLexiconEnabledLanguages != languages else {
                return
            }
            genericLatinLexiconEnabledLanguages = languages
            // OFF→ONの反映は遅延ロードが担う。ONで積んだ言語のOFF時は解放する。
            cachedGenericLatinLexiconEntriesByLanguage = cachedGenericLatinLexiconEntriesByLanguage
                .filter { languages.contains($0.key) }
        }
    }

    // 言語別の同梱頻度リストを読み込んでキャッシュする。ファイルはビルド時に
    // 検索キー(実行時と同一のSwift折り畳み)順へソート済み(key\tword\trank)なので、
    // 実行時は行分割だけで索引になる(折り畳み・ソートの実行時コストゼロ)。
    func genericLatinLexiconEntries(language: String) -> [GenericLatinLexiconEntry] {
        if let cached = withCacheLock({ cachedGenericLatinLexiconEntriesByLanguage[language] }) {
            return cached
        }

        let filename = "LatinSuggestionLexicon_\(language)"
        let url = genericLatinLexiconDirectoryURLOverride?
            .appendingPathComponent("\(filename).txt")
            ?? Bundle(for: KanaKanjiStore.self).url(forResource: filename, withExtension: "txt")

        guard let url,
            let content = try? String(contentsOf: url, encoding: .utf8) else {
            withCacheLock { cachedGenericLatinLexiconEntriesByLanguage[language] = [] }
            return []
        }

        // String.split(grapheme単位)や自前バイト走査は Debug ビルド(⌘R実機)でMB級に
        // 秒単位かかる。NSString.components(ObjC実装)は Debug でも C 速度で走る。
        var entries: [GenericLatinLexiconEntry] = []
        let lines = (content as NSString).components(separatedBy: "\n")
        entries.reserveCapacity(lines.count)

        for line in lines {
            let fields = (line as NSString).components(separatedBy: "\t")

            guard fields.count == 3, let rank = Int(fields[2]) else {
                continue
            }

            entries.append(
                GenericLatinLexiconEntry(
                    searchKey: fields[0],
                    candidate: fields[1],
                    rank: rank
                )
            )
        }

        withCacheLock { cachedGenericLatinLexiconEntriesByLanguage[language] = entries }
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
