import Foundation

// 汎用Latin語彙のmmap索引。バイト順ソート済みtxt(key\tword\trank\n)を Data(mappedIfSafe)
// のまま保持し、バイナリサーチで前方一致行だけをパースする。UTF-8のバイト前方一致は
// スカラ前方一致と等価(スカラ先頭バイトと継続バイトの領域が重ならないため)。
struct GenericLatinLexiconFileIndex {
    let data: Data
    let entryCount: Int

    init(data: Data) {
        self.data = data
        var count = 0
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard var cursor = buffer.baseAddress else { return }
            var remaining = buffer.count
            while remaining > 0 {
                guard let found = memchr(cursor, 0x0A, remaining) else {
                    count += 1  // 改行なしの最終行
                    break
                }
                count += 1
                let consumed = UnsafeRawPointer(found) - cursor + 1
                cursor += consumed
                remaining -= consumed
            }
        }
        entryCount = count
    }

    func matchedEntries(
        normalizedPrefix: String,
        excludedSearchKeys: Set<String>
    ) -> [KanaKanjiStore.GenericLatinLexiconEntry] {
        let prefix = Array(normalizedPrefix.utf8)
        guard !prefix.isEmpty, !data.isEmpty else {
            return []
        }
        var results: [KanaKanjiStore.GenericLatinLexiconEntry] = []
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            let bytes = buffer.bindMemory(to: UInt8.self)
            let n = bytes.count

            // offset を含む行の先頭(直前の改行の次)
            func lineStart(atOrBefore offset: Int) -> Int {
                var i = offset
                while i > 0, bytes[i - 1] != 0x0A {
                    i -= 1
                }
                return i
            }
            // 行頭 start のキー(\tまで)と prefix のバイト辞書式比較: キーが小さければ true
            func keyIsLess(lineStart start: Int) -> Bool {
                var i = start
                var j = 0
                while j < prefix.count {
                    if i >= n || bytes[i] == 0x09 || bytes[i] == 0x0A {
                        return true  // キーが prefix より短い(=prefix の途中で尽きた)
                    }
                    if bytes[i] != prefix[j] {
                        return bytes[i] < prefix[j]
                    }
                    i += 1
                    j += 1
                }
                return false  // キー >= prefix(prefix を含む)
            }

            // 下限探索: キー >= prefix となる最初の行頭
            var low = 0
            var high = n
            while low < high {
                let mid = (low + high) / 2
                let start = lineStart(atOrBefore: mid)
                if keyIsLess(lineStart: start) {
                    // この行の終端+1 へ
                    var end = mid
                    while end < n, bytes[end] != 0x0A {
                        end += 1
                    }
                    low = end + 1
                } else {
                    high = start
                }
            }

            // 前方一致する行を順に収集
            var cursor = low
            while cursor < n {
                // prefix 照合
                var i = cursor
                var j = 0
                var isPrefix = true
                while j < prefix.count {
                    if i >= n || bytes[i] != prefix[j] {
                        isPrefix = false
                        break
                    }
                    i += 1
                    j += 1
                }
                guard isPrefix else {
                    break
                }
                // フィールド分解: key \t candidate \t rank \n
                var tab1 = i
                while tab1 < n, bytes[tab1] != 0x09, bytes[tab1] != 0x0A {
                    tab1 += 1
                }
                var lineEnd = tab1
                while lineEnd < n, bytes[lineEnd] != 0x0A {
                    lineEnd += 1
                }
                if tab1 < n, bytes[tab1] == 0x09 {
                    var tab2 = tab1 + 1
                    while tab2 < lineEnd, bytes[tab2] != 0x09 {
                        tab2 += 1
                    }
                    if tab2 < lineEnd {
                        var rank = 0
                        var hasDigits = false
                        var k = tab2 + 1
                        while k < lineEnd, bytes[k] >= 0x30, bytes[k] <= 0x39 {
                            rank = rank * 10 + Int(bytes[k] - 0x30)
                            hasDigits = true
                            k += 1
                        }
                        if hasDigits, k == lineEnd {
                            let searchKey = String(decoding: bytes[cursor..<tab1], as: UTF8.self)
                            if !excludedSearchKeys.contains(searchKey) {
                                results.append(
                                    KanaKanjiStore.GenericLatinLexiconEntry(
                                        searchKey: searchKey,
                                        candidate: String(decoding: bytes[(tab1 + 1)..<tab2], as: UTF8.self),
                                        rank: rank
                                    )
                                )
                            }
                        }
                    }
                }
                cursor = lineEnd + 1
            }
        }
        return results
    }
}


// ラテン(英字)入力のサジェスト。読み検索キーの正規化・二分探索・候補判定を担う。
// 索引は2層とも同梱ファイルの mmap(追加語彙由来 LatinSuggestionSupplemental.txt と
// 汎用レキシコン LatinSuggestionLexicon_{lang}.txt)で、実行時構築は行わない。
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

        var results: [String] = []
        var seenCandidates = Set<String>()
        var seenSearchKeys = Set<String>()

        // 追加語彙由来(前計算ファイルの mmap 索引)。キー順+同キー内は候補の大小文字無視順
        if let supplementalIndex = latinSupplementalIndex() {
            for entry in supplementalIndex.matchedEntries(
                normalizedPrefix: normalizedPrefix,
                excludedSearchKeys: []
            ) where results.count < limit {
                if seenCandidates.insert(entry.candidate).inserted {
                    results.append(entry.candidate)
                    seenSearchKeys.insert(entry.searchKey)
                }
            }
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
            guard let index = genericLatinLexiconIndex(language: language) else {
                continue
            }
            // 追加語彙が既に出したキーは出さない(rouge 等は追加語彙側が勝つ)。入力と同じ
            // 表記そのものの除外は提示層が行う(polizei→Polizei の大文字矯正は残したい)。
            matched.append(contentsOf: index.matchedEntries(
                normalizedPrefix: normalizedPrefix,
                excludedSearchKeys: excludedSearchKeys
            ))
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
            cachedGenericLatinLexiconIndexByLanguage = cachedGenericLatinLexiconIndexByLanguage
                .filter { languages.contains($0.key) }
        }
    }

    // 言語別の同梱頻度リストのmmap索引を返す。ファイルはビルド時に検索キー(実行時と
    // 同一のSwift折り畳み)のバイト順へソート済み(key\tword\trank)なので、
    // Data(mappedIfSafe)のままバイト単位バイナリサーチで前方一致行だけをパースする。
    // 10.5万語のSwift文字列配列化(常駐約10MB+パーススパイク)を廃止: ファイル裏付きの
    // クリーンページは footprint に乗らず、メモリ警告での解放・再ロードも実質ゼロコスト(2422)。
    func genericLatinLexiconIndex(language: String) -> GenericLatinLexiconFileIndex? {
        if let cached = withCacheLock({ cachedGenericLatinLexiconIndexByLanguage[language] }) {
            return cached
        }

        let filename = "LatinSuggestionLexicon_\(language)"
        let url = genericLatinLexiconDirectoryURLOverride?
            .appendingPathComponent("\(filename).txt")
            ?? Bundle(for: KanaKanjiStore.self).url(forResource: filename, withExtension: "txt")

        let data = url.flatMap { try? Data(contentsOf: $0, options: .mappedIfSafe) } ?? Data()
        let index = GenericLatinLexiconFileIndex(data: data)
        withCacheLock { cachedGenericLatinLexiconIndexByLanguage[language] = index }
        return index
    }

    // 追加語彙(補助語彙 SecondVocab)由来の欧文サジェスト索引。ビルド時に
    // tools/build_latin_suggestion_supplemental.swift が実行時と同一のフィルタ・折り畳みで前計算した
    // LatinSuggestionSupplemental.txt(key\tcandidate\t0、キーのバイト順)を Data(mappedIfSafe) で保持する。
    // 以前は起動後に補助語彙 15k 件を走査して配列を組んでいた(fp +8MB の瞬間ピーク、alloc の
    // ラチェット成長、8/26 の jetsam 死のトドメ)。前計算でピークも常駐もヒープ外になり、
    // 高水位の見送りゲート(52MB)と削除キーの薄ピンク表示は不要になった(2770)。
    // 読み込み元は補助語彙 JSON と同じ(App Group の共有コンテナ→バンドル。テストは override)
    func latinSupplementalIndex() -> GenericLatinLexiconFileIndex? {
        if let cached = withCacheLock({ cachedLatinSupplementalIndex }) {
            return cached
        }
        let filename = KanaKanjiStorageKeys.latinSuggestionSupplementalFilename
        let url = genericLatinLexiconDirectoryURLOverride?.appendingPathComponent(filename)
            ?? sharedOrBundledDictionaryURL(filename: filename)
        guard let url, let data = try? Data(contentsOf: url, options: .mappedIfSafe), !data.isEmpty else {
            return nil
        }
        let index = GenericLatinLexiconFileIndex(data: data)
        withCacheLock { cachedLatinSupplementalIndex = index }
        return index
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
    // 候補のフィルタ(欧文字を含む/許容文字だけ)はビルド時の tools/build_latin_suggestion_supplemental.swift に移した
}
