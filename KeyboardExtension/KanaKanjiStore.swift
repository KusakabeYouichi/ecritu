import Foundation
import SQLite3

private struct KanaKanjiInflectionEntry: Codable {
    let candidate: String
    let inflectionClass: String
}

final class KanaKanjiStore {
    private let appGroupID: String
    let defaults: UserDefaults?
    private let fileManager = FileManager.default
    private let systemDictionaryQueue = DispatchQueue(
        label: "com.kusakabe.ecritu.kana-kanji.system-dictionary"
    )
    // キャッシュ保護ロック。変換は通常 candidateGenerationQueue(直列)で走るが、
    // 変換キーの同期変換(main)とメモリ警告時のキャッシュ解放(main)が並行し得るため、
    // 可変キャッシュへのアクセスはすべてこのロック越しに行う。sqlite クエリや JSON
    // デコード等の重い処理はロックの外で行うこと(二重計算は無害、競合変異は未定義)。
    private let cacheLock = NSLock()

    // 学習データ永続化用のバックグラウンドキュー。確定(learn)のたびに学習辞書・学習スコア
    // 全体を JSONEncoder で再エンコードして UserDefaults へ書くのは、学習データの成長に
    // 比例して確定タップを重くするため、メモリ内キャッシュだけ同期更新し永続化は非同期で
    // 行う(直列キューなので最終書き込みが必ず勝つ)。手動の追加語彙(addUserEntry)は
    // 頻度が低くテストが直後にフレッシュな store で読むため同期のまま。
    let learningPersistQueue = DispatchQueue(
        label: "com.kusakabe.ecritu.kana-kanji.learning-persist",
        qos: .utility
    )

    func withCacheLock<T>(_ body: () -> T) -> T {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return body()
    }
    // かな識別(候補==読み)の学習を許可する読みの最大長。ちゃんと/そして/ありがとう 等の
    // 単語相当は許可し、文丸ごと(きょうはいいてんきですね 等)は拒否して連文節の
    // 最安素通りブロック事故(かな確定学習の事故時代の汚染含む)を防ぐ。
    static let kanaIdentityLearnableMaxReadingCount = 6
    static let initialLearningScores: [String: Int] = [
        "かった\t交った": -1_000_000_000,
        "かった\t支った": -1_000_000_000
    ]
    struct LatinSuggestionEntry {
        let searchKey: String
        let candidate: String
    }
    // 汎用Latinサジェスト語彙(同梱の頻度リスト。追加語彙とは別レイヤー)のエントリ。
    // rank はリスト内の頻度順位(小さいほど高頻度)。
    struct GenericLatinLexiconEntry {
        let searchKey: String
        let candidate: String
        let rank: Int
    }
    private var sqliteIndex: KanaKanjiSQLiteIndex?
    private var didAttemptSQLiteIndexLoad = false
    // メモリ圧迫でのアンロード後は再オープンを禁止する(スティッキー)。以前は
    // clearSystemDictionaryCaches が didAttemptSQLiteIndexLoad をリセットするため
    // 次の変換で即再オープンされ、最終手段のアンロードが close→reopen の空回りに
    // なっていた。辞書ファイル差し替え(reopenSystemDictionary)では解除する。
    private var isSQLiteReopenSuppressed = false
    private var cachedSystemDictionary: [String: [String]]?
    private var cachedSupplementalSystemDictionary: SupplementalVocabCompactStore?
    var cachedLatinSuggestionEntries: [LatinSuggestionEntry]?
    // 汎用Latinサジェスト語彙のmmap索引キャッシュ(言語別)と有効言語
    // (既定は全言語OFF。設定で言語別にON)。索引は Data(mappedIfSafe) 保持のみで
    // 常駐フットプリントを持たない(GenericLatinLexiconFileIndex 定義コメント参照)。
    var cachedGenericLatinLexiconIndexByLanguage: [String: GenericLatinLexiconFileIndex] = [:]
    var genericLatinLexiconEnabledLanguages: Set<String> = []
    // 欧文サジェスト構築を高水位で見送った状態(削除キー薄ピンクの可視化用。2664)。
    // 構築が成功したら false に戻る
    var didSkipLatinSuggestionBuildForPressure = false
    // テスト用: bundle 未同梱の環境(unit test)でリポジトリのtxtを直接読ませるディレクトリ
    var genericLatinLexiconDirectoryURLOverride: URL?
    // 漢字1文字ピッカーの索引(mmap)。テスト用に読み込み元を差し替えられるようにする。
    var cachedKanjiRadicalIndex: KanjiRadicalFileIndex?
    var kanjiRadicalIndexDirectoryURLOverride: URL?
    private var cachedSystemCandidateSources: [String: [String: Set<String>]]?
    private var cachedInflectionDictionary: [String: [String: String]]?
    // 読み別の inflection_classes キャッシュ(連文節の辞書形述語判定用)
    private var cachedInflectionClassMapsByReading: [String: [String: String]] = [:]
    // 連文節 DP の LM 点引きキャッシュ。前置き入力ではスパン/ペアの大半が毎キーストロークで
    // 再出現するため、点クエリ(1変換あたり unigram 数百+bigram 千超)を初出のみに抑える。
    // 「未観測」も番兵(-1)で覚える — LM のヒット率は低く、negative キャッシュが本体。
    // 上限超過時は全消去(まれな一括再クエリで済ませ、LRU 管理のオーバーヘッドを避ける)。
    // LM 点引きキャッシュは長寿命のためキーを64bitハッシュ化し、POD 辞書
    // ([UInt64: Int]=キー・値とも単一連続バッファに内蔵)へ集約する。エントリ毎の
    // String がヒープに散在して malloc アリーナを断片化させるのを防ぐ(2566)。
    // Hasher はプロセス内で安定(キャッシュはプロセス内限り)。64bit 衝突(〜10^-10)は
    // コスト近似として許容。
    private var cachedWordLMUnigram: [UInt64: Int] = [:]
    private var cachedWordLMBigram: [UInt64: Int] = [:]
    private static func lmCacheKey(_ a: String) -> UInt64 {
        var hasher = Hasher()
        hasher.combine(a)
        return UInt64(bitPattern: Int64(hasher.finalize()))
    }
    private static func lmCacheKey(_ a: String, _ b: String) -> UInt64 {
        var hasher = Hasher()
        hasher.combine(a)
        hasher.combine(b)
        return UInt64(bitPattern: Int64(hasher.finalize()))
    }
    // 表層→全読み最安 word_cost(読み跨ぎ unigram 借用の遮断用。未収録は番兵)
    private var cachedCandidateMinWordCosts: [String: Int] = [:]
    // 8192 で通常の入力セッションには十分(1変換あたりの点クエリは数百〜千件強で、
    // negative キャッシュのヒット率は上限縮小の影響をほぼ受けない)。32768 時代は
    // 最悪ケースで両テーブル合計 ~8MB 級に育ち得た(メモリ監査 2026-07 の残項目)。
    private static let wordLMCacheLimit = 8192
    private static let wordLMCacheLimitConstrained = 2048
    private static let wordLMMissingSentinel = -1
    // 読み別 word_costs キャッシュ(連文節のノード列挙が span ごとに引く)
    private var cachedWordCostsByReading: [String: [String: Int]] = [:]
    private static let wordCostsCacheLimit = 4096
    private static let wordCostsCacheLimitConstrained = 1024
    // メモリ警告が続くときの縮小モード(cacheLock 保護)。キャッシュ上限を下げて再成長を
    // 抑える — sqlite クローズ(節約約2MB・変換品質全損)より割の良い中間手段。
    private var isConstrainedMemoryCacheMode = false
    private var activeWordLMCacheLimit: Int {
        isConstrainedMemoryCacheMode ? Self.wordLMCacheLimitConstrained : Self.wordLMCacheLimit
    }
    private var activeWordCostsCacheLimit: Int {
        isConstrainedMemoryCacheMode ? Self.wordCostsCacheLimitConstrained : Self.wordCostsCacheLimit
    }
    private var cachedInitialUserDictionary: [String: [String]]?
    private var cachedInitialShortcutVocabulary: [String]?
    var cachedUserDictionary: [String: [String]]?
    var cachedLearnedDictionary: [String: [String]]?
    private var cachedSuppressedCandidatesByReading: [String: Set<String>]?
    private var cachedShortcutVocabulary: [String]?
    private var cachedBundledHiddenSuppression: [String: [String]]?
    var cachedLearningScores: [String: Int]?
    var cachedLearningScoresByReading: [String: [String: Int]]?
    // 学習の永続化デバウンス(2715): 確定ごとの全量コピー+全量 JSON 化をやめ、数秒まとめて1回書く
    var learningPersistDirtyLearned = false
    var learningPersistDirtyScores = false
    var learningPersistWorkItem: DispatchWorkItem?

    init(appGroupID: String) {
        self.appGroupID = appGroupID
        self.defaults = UserDefaults(suiteName: appGroupID)
    }

    // バンドル優先で辞書ファイルを解決する。以前は app-group 優先だったが、正当な更新経路の
    // 無い遺物(旧仕組みで実機の app group に残った古い辞書)が半永久的に新しいバンドル辞書を
    // 覆い隠し、鴣う 等の旧ハーベストのジャンクや修正済みの誤り(のめる→飲む)が実機だけで
    // 再発し続けていた。バンドルは毎ビルド tmp から最新が入るため、実体があればバンドルを使い、
    // その際 app-group 側の同名遺物は削除して容量も回収する。app-group はバンドルに実体が
    // 無い場合のフォールバックとしてのみ残す。
    // テスト用: App Group コンテナの代わりに使うディレクトリー。テスト環境の偽 group ID での
    // containerURL(forSecurityApplicationGroupIdentifier:) はプロセス初回に約40秒かかる
    // (containermanagerd の解決/作成)ため、テストはローカルディレクトリーで代替する(2515)。
    static var sharedContainerURLOverride: URL?

    private func sharedOrBundledDictionaryURL(filename: String) -> URL? {
        let sharedURL: URL? = (Self.sharedContainerURLOverride
            ?? fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        ).map { $0.appendingPathComponent(filename) }

        func isUsableFile(_ url: URL) -> Bool {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                values.isRegularFile == true,
                let size = values.fileSize,
                size > 0 else {
                return false
            }
            return true
        }

        let bundle = Bundle(for: KanaKanjiStore.self)
        let nsFilename = filename as NSString
        let resourceName = nsFilename.deletingPathExtension
        let resourceExtension = nsFilename.pathExtension

        let resourceURLs: [URL?] = [
            bundle.url(forResource: filename, withExtension: nil),
            resourceExtension.isEmpty
                ? nil
                : bundle.url(forResource: resourceName, withExtension: resourceExtension)
        ]

        for resourceURL in resourceURLs.compactMap({ $0 }) where isUsableFile(resourceURL) {
            if let sharedURL, isUsableFile(sharedURL) {
                try? fileManager.removeItem(at: sharedURL)
            }
            return resourceURL
        }

        if let sharedURL, isUsableFile(sharedURL) {
            return sharedURL
        }

        return nil
    }

    // JSONフォールバックのサイズ上限。キーボード拡張の footprint 予算(60〜80MB)に対し、
    // JSON時代(edition 1829以前)の App Group に残った巨大辞書JSON(30〜54MB、デコード後
    // 実メモリ3〜5倍)を丸ごとデコードすると jetsam 確実なため、デコード自体を拒否して
    // seed フォールバックに劣化させる。現行のバンドル同梱はプレースホルダ(数バイト)。
    private static let dictionaryDataMaxByteCount = 4 * 1024 * 1024

    private func sharedOrBundledDictionaryData(filename: String) -> Data? {
        guard let resourceURL = sharedOrBundledDictionaryURL(filename: filename),
            let values = try? resourceURL.resourceValues(forKeys: [.fileSizeKey]),
            let size = values.fileSize,
            size <= Self.dictionaryDataMaxByteCount,
            let data = try? Data(contentsOf: resourceURL),
            !data.isEmpty else {
            return nil
        }

        return data
    }

    private func sqliteIndexIfAvailable() -> KanaKanjiSQLiteIndex? {
        systemDictionaryQueue.sync {
            if let sqliteIndex {
                return sqliteIndex
            }

            guard !isSQLiteReopenSuppressed else {
                return nil
            }

            guard let databaseURL = sharedOrBundledDictionaryURL(
                filename: KanaKanjiStorageKeys.systemDictionarySQLiteFilename
            ) else {
                // Keep retry enabled so a later App Group install can be picked up.
                didAttemptSQLiteIndexLoad = false
                return nil
            }

            guard !didAttemptSQLiteIndexLoad else {
                return nil
            }

            didAttemptSQLiteIndexLoad = true

            guard let sqliteIndex = KanaKanjiSQLiteIndex(databaseURL: databaseURL) else {
                // Allow retry in case the database is still being copied.
                didAttemptSQLiteIndexLoad = false
                return nil
            }

            self.sqliteIndex = sqliteIndex
            return sqliteIndex
        }
    }

    func isSystemDictionaryFallback() -> Bool {
        guard let sqliteIndex = sqliteIndexIfAvailable() else {
            return true
        }

        return !sqliteIndex.hasAnyEntries
    }

    func prepareSystemDictionaryIfNeeded(onLoaded: (() -> Void)? = nil) {
        guard onLoaded != nil else {
            _ = sqliteIndexIfAvailable()
            return
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            _ = self?.sqliteIndexIfAvailable()

            DispatchQueue.main.async {
                onLoaded?()
            }
        }
    }

    func systemCandidates(
        for reading: String,
        mode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        let normalizedReading = KanaTextNormalizer.normalizedReading(reading)

        guard !normalizedReading.isEmpty else {
            return []
        }

        if let sqliteIndex = sqliteIndexIfAvailable() {
            return sqliteIndex.candidates(
                for: normalizedReading,
                requiredSources: mode.requiredSystemSources
            )
        }

        let supplementalCandidates = loadSupplementalSystemDictionary().candidates(for: normalizedReading)
        let dictionary = loadSystemDictionary()
        let baseCandidates = dictionary[normalizedReading] ?? []

        guard let requiredSources = mode.requiredSystemSources else {
            return mergedSystemCandidates(
                primary: baseCandidates,
                supplemental: supplementalCandidates
            )
        }

        let sourceMap = loadSystemCandidateSources()[normalizedReading] ?? [:]

        guard !sourceMap.isEmpty else {
            return mergedSystemCandidates(
                primary: baseCandidates,
                supplemental: supplementalCandidates
            )
        }

        let filteredPrimaryCandidates = baseCandidates.filter { candidate in
            guard let candidateSources = sourceMap[candidate],
                !candidateSources.isEmpty else {
                // Keep fallback candidates even when no source metadata exists.
                return true
            }

            return !requiredSources.isDisjoint(with: candidateSources)
        }

        return mergedSystemCandidates(
            primary: filteredPrimaryCandidates,
            supplemental: supplementalCandidates
        )
    }

    // inflection_classes(活用クラス表)自体を持っているか。読み単位の有無ではない点が
    // systemInflectionMetadata との違いで、「表はあるのにこの読みには行が無い」=用言ではない、
    // という判断に使う(クラス推論の暴発防止)。
    var hasSystemInflectionMetadataTable: Bool {
        if let sqliteIndex = sqliteIndexIfAvailable() {
            return sqliteIndex.hasInflectionMetadata
        }
        return !loadInflectionDictionary().isEmpty
    }

    // 辞書(Sudachi)の品詞・活用クラス誤りの否認(2639)。既存 は suru(サ変可能)が
    // 付くが 既存する は規範的でなく、既存しちゃう 等の派生ゴミの源になる(ユーザ指摘)。
    // 源泉は references/grammaire.plist(バンドル直読み・同期不要)。phrase=表層/
    // shortcut=読み で、語自体は候補に残し活用クラスだけ否認する
    nonisolated(unsafe) private static var cachedInflectionClassDeniedSurfaces: [String: Set<String>]?
    nonisolated(unsafe) private static let inflectionClassDeniedLock = NSLock()

    static func inflectionClassDeniedSurfacesByReading() -> [String: Set<String>] {
        inflectionClassDeniedLock.lock()
        defer { inflectionClassDeniedLock.unlock() }
        if let cached = cachedInflectionClassDeniedSurfaces {
            return cached
        }
        var denied: [String: Set<String>] = [:]
        let bundle = Bundle(for: KanaKanjiStore.self)
        if let url = bundle.url(forResource: "grammaire", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let entries = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
            ) as? [[String: String]] {
            for entry in entries {
                guard let phrase = entry["phrase"], let shortcut = entry["shortcut"],
                    !phrase.isEmpty, !shortcut.isEmpty else { continue }
                denied[shortcut, default: []].insert(phrase)
            }
        }
        cachedInflectionClassDeniedSurfaces = denied
        return denied
    }

    func systemInflectionMetadata(for reading: String) -> (classMap: [String: String], hasMetadata: Bool) {
        let normalizedReading = KanaTextNormalizer.normalizedReading(reading)

        guard !normalizedReading.isEmpty else {
            return ([:], false)
        }

        var classMap: [String: String]
        if let sqliteIndex = sqliteIndexIfAvailable() {
            classMap = sqliteIndex.inflectionClassMap(for: normalizedReading)
        } else {
            classMap = loadInflectionDictionary()[normalizedReading] ?? [:]
        }
        if let denied = Self.inflectionClassDeniedSurfacesByReading()[normalizedReading] {
            classMap = classMap.filter { !denied.contains($0.key) }
        }
        return (classMap, !classMap.isEmpty)
    }

    // 連文節の辞書形述語判定(短spanレア読み床の免除)。読み単位のインデックス付きクエリ+
    // キャッシュで引く。以前の「length(reading)<=2 の一括ロード」はインデックスが効かず
    // inflection_classes 全行スキャンになり、キーボード起動ごと(=アプリ切替ごと)の
    // 初回変換を遅くしていた。呼び出し側の形状ゲート(かな終止形尾+漢字)でクエリ回数
    // 自体も span あたり高々1回に抑えている。
    func isShortReadingDictionaryFormPredicate(reading: String, candidate: String) -> Bool {
        if let cached = withCacheLock({ cachedInflectionClassMapsByReading[reading] }) {
            return cached[candidate] != nil
        }
        let classMap: [String: String]
        if let sqliteIndex = sqliteIndexIfAvailable() {
            classMap = sqliteIndex.inflectionClassMap(for: reading)
        } else {
            classMap = loadInflectionDictionary()[reading] ?? [:]
        }
        withCacheLock { cachedInflectionClassMapsByReading[reading] = classMap }
        return classMap[candidate] != nil
    }

    // 案A(連文節ビタビ)用: 読みに対する語コスト(Sudachi由来, 小さいほど高頻度)。
    // sqlite の word_costs 由来。無ければ空(= 呼び出し側で既定コストにフォールバック)。
    func wordCosts(for reading: String) -> [String: Int] {
        let normalizedReading = KanaTextNormalizer.normalizedReading(reading)
        guard !normalizedReading.isEmpty,
            let sqliteIndex = sqliteIndexIfAvailable() else {
            return [:]
        }
        if let cached = withCacheLock({ cachedWordCostsByReading[normalizedReading] }) {
            return cached
        }
        let costMap = sqliteIndex.wordCostMap(for: normalizedReading)
        withCacheLock {
            if cachedWordCostsByReading.count >= activeWordCostsCacheLimit {
                cachedWordCostsByReading.removeAll(keepingCapacity: true)
            }
            cachedWordCostsByReading[normalizedReading] = costMap
        }
        return costMap
    }

    // 連文節 DP(案1: 自前単語 n-gram LM)が利用可能か。
    var hasWordLMMetadata: Bool {
        sqliteIndexIfAvailable()?.hasWordLMMetadata ?? false
    }

    // 連文節 DP 用: 表層集合の unigram コストをまとめて取得(点引きキャッシュ経由)。
    func wordLMUnigramCosts(for surfaces: [String]) -> [String: Int] {
        guard let sqliteIndex = sqliteIndexIfAvailable() else {
            return [:]
        }
        var result: [String: Int] = [:]
        var uncached: [String] = []
        withCacheLock {
            for surface in surfaces {
                if let cached = cachedWordLMUnigram[Self.lmCacheKey(surface)] {
                    if cached != Self.wordLMMissingSentinel {
                        result[surface] = cached
                    }
                } else {
                    uncached.append(surface)
                }
            }
        }
        guard !uncached.isEmpty else {
            return result
        }
        let fetched = sqliteIndex.wordLMUnigramCosts(for: uncached)
        withCacheLock {
            if cachedWordLMUnigram.count + uncached.count > activeWordLMCacheLimit {
                cachedWordLMUnigram.removeAll(keepingCapacity: true)
            }
            for surface in uncached {
                if let cost = fetched[surface] {
                    cachedWordLMUnigram[Self.lmCacheKey(surface)] = cost
                    result[surface] = cost
                } else {
                    cachedWordLMUnigram[Self.lmCacheKey(surface)] = Self.wordLMMissingSentinel
                }
            }
        }
        return result
    }

    // 読み跨ぎ借用遮断用: 表層集合の全読み最安 word_cost をまとめて取得(点引きキャッシュ経由)。
    // 旧形式 DB(表なし)では常に空=機能オフ。
    func candidateMinWordCosts(for candidates: [String]) -> [String: Int] {
        guard let sqliteIndex = sqliteIndexIfAvailable(),
            sqliteIndex.hasCandidateMinWordCostMetadata else {
            return [:]
        }
        var result: [String: Int] = [:]
        var uncached: [String] = []
        withCacheLock {
            for candidate in candidates {
                if let cached = cachedCandidateMinWordCosts[candidate] {
                    if cached != Self.wordLMMissingSentinel {
                        result[candidate] = cached
                    }
                } else {
                    uncached.append(candidate)
                }
            }
        }
        guard !uncached.isEmpty else {
            return result
        }
        let fetched = sqliteIndex.candidateMinWordCosts(for: uncached)
        withCacheLock {
            if cachedCandidateMinWordCosts.count + uncached.count > activeWordLMCacheLimit {
                cachedCandidateMinWordCosts.removeAll(keepingCapacity: true)
            }
            for candidate in uncached {
                if let cost = fetched[candidate] {
                    cachedCandidateMinWordCosts[candidate] = cost
                    result[candidate] = cost
                } else {
                    cachedCandidateMinWordCosts[candidate] = Self.wordLMMissingSentinel
                }
            }
        }
        return result
    }

    // 連文節 DP 用: (prev, cur) 対の bigram コストをまとめて取得(キー "prev\tcur"、点引きキャッシュ経由)。
    func wordLMBigramCosts(for pairs: [(String, String)]) -> [String: Int] {
        guard let sqliteIndex = sqliteIndexIfAvailable() else {
            return [:]
        }
        var result: [String: Int] = [:]
        var uncached: [(String, String)] = []
        withCacheLock {
            for (prev, cur) in pairs {
                if let cached = cachedWordLMBigram[Self.lmCacheKey(prev, cur)] {
                    if cached != Self.wordLMMissingSentinel {
                        result[prev + "\t" + cur] = cached
                    }
                } else {
                    uncached.append((prev, cur))
                }
            }
        }
        guard !uncached.isEmpty else {
            return result
        }
        let fetched = sqliteIndex.wordLMBigramCosts(for: uncached)
        withCacheLock {
            if cachedWordLMBigram.count + uncached.count > activeWordLMCacheLimit {
                cachedWordLMBigram.removeAll(keepingCapacity: true)
            }
            for (prev, cur) in uncached {
                let key = prev + "\t" + cur
                let hashedKey = Self.lmCacheKey(prev, cur)
                if let cost = fetched[key] {
                    cachedWordLMBigram[hashedKey] = cost
                    result[key] = cost
                } else {
                    cachedWordLMBigram[hashedKey] = Self.wordLMMissingSentinel
                }
            }
        }
        return result
    }

    func systemCandidates(
        for reading: String,
        taggedWith sourceTag: String
    ) -> (candidates: Set<String>, hasMetadata: Bool) {
        let normalizedReading = KanaTextNormalizer.normalizedReading(reading)

        guard !normalizedReading.isEmpty else {
            return ([], false)
        }

        var candidates = Set<String>()
        let sqliteIndex = sqliteIndexIfAvailable()
        let hasSQLiteSourceMetadata = sqliteIndex?.hasSourceMetadata == true

        if let sqliteIndex,
            sqliteIndex.hasSourceMetadata {
            candidates.formUnion(
                sqliteIndex.candidates(
                    withExactSource: sourceTag,
                    for: normalizedReading
                )
            )
        }

        let sourceMapByCandidate: [String: Set<String>]

        if hasSQLiteSourceMetadata {
            sourceMapByCandidate = [:]
        } else {
            sourceMapByCandidate = loadSystemCandidateSources()[normalizedReading] ?? [:]
        }

        for (candidate, sources) in sourceMapByCandidate where sources.contains(sourceTag) {
            candidates.insert(candidate)
        }

        var hasMetadata = !sourceMapByCandidate.isEmpty
            || (sqliteIndex?.hasSourceMetadata == true)

        if sourceTag == KanaKanjiCandidateSourceTag.adjectiveGaru,
            let seedCandidates = KanaKanjiSemanticSeed.adjectiveGaruCandidatesByReading[normalizedReading],
            !seedCandidates.isEmpty {
            candidates.formUnion(seedCandidates)
            hasMetadata = true
        }

        return (candidates, hasMetadata)
    }

    func loadSystemDictionary() -> [String: [String]] {
        if let cached = withCacheLock({ cachedSystemDictionary }) {
            return cached
        }

        guard let data = sharedOrBundledDictionaryData(
            filename: KanaKanjiStorageKeys.systemDictionaryFilename
        ),
                let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            return [:]
        }

        guard !decoded.isEmpty else {
            // Do not pin an empty placeholder; allow retry after dictionary install.
            return [:]
        }

        // The generated Sudachi index is already normalized to hiragana readings.
        withCacheLock { cachedSystemDictionary = decoded }
        return decoded
    }

    func loadSupplementalSystemDictionary() -> SupplementalVocabCompactStore {
        if let cached = withCacheLock({ cachedSupplementalSystemDictionary }) {
            return cached
        }

        guard let data = sharedOrBundledDictionaryData(
            filename: KanaKanjiStorageKeys.supplementalSystemDictionaryFilename
        ),
            let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            // 失敗もキャッシュする。以前は「後からのデプロイを拾うため」毎回リトライしていたが、
            // candidates() 毎回の呼び出し(2497)でファイル探索+デコード試行が変換ごとに走り、
            // テストスイートを数十秒遅くしていた(実機でも無駄)。後からのデプロイは
            // 設定変更世代カウンタ→clearSharedDataCaches 経由でこのキャッシュも破棄して拾う(2515)
            withCacheLock { cachedSupplementalSystemDictionary = SupplementalVocabCompactStore.empty }
            return .empty
        }

        // [String: [String]] のまま常駐させると約6.8MB食う(実測: 初回変換の used +6.8MB の主因、
        // 高水位台帳 2615)。使い道は読み単位の点引きと一度きりの全走査だけなので、
        // UTF8ブロブ+オフセット表へ詰め直して常駐を約1/7にする。decode結果は使い捨て。
        let packed = SupplementalVocabCompactStore(dictionary: normalizeDictionary(decoded))
        withCacheLock { cachedSupplementalSystemDictionary = packed }
        return packed
    }

    func loadSystemCandidateSources() -> [String: [String: Set<String>]] {
        if let cached = withCacheLock({ cachedSystemCandidateSources }) {
            return cached
        }

        guard let data = sharedOrBundledDictionaryData(
            filename: KanaKanjiStorageKeys.systemCandidateSourcesFilename
        ),
                let decoded = try? JSONDecoder().decode([String: [String: [String]]].self, from: data) else {
            return [:]
        }

        var normalized: [String: [String: Set<String>]] = [:]

        for (reading, candidateMap) in decoded {
            var sourceMap: [String: Set<String>] = [:]

            for (candidate, rawSources) in candidateMap {
                var sources: Set<String> = []

                for source in rawSources {
                    if source == KanaKanjiCandidateSourceTag.normalized
                        || source == KanaKanjiCandidateSourceTag.surface
                        || source == KanaKanjiCandidateSourceTag.adjectiveGaru {
                        sources.insert(source)
                    }
                }

                if !sources.isEmpty {
                    sourceMap[candidate] = sources
                }
            }

            if !sourceMap.isEmpty {
                normalized[reading] = sourceMap
            }
        }

        guard !normalized.isEmpty else {
            // Do not cache empty source metadata from placeholder resources.
            return [:]
        }

        withCacheLock { cachedSystemCandidateSources = normalized }
        return normalized
    }

    func loadInflectionDictionary() -> [String: [String: String]] {
        if let cached = withCacheLock({ cachedInflectionDictionary }) {
            return cached
        }

        guard let data = sharedOrBundledDictionaryData(
            filename: KanaKanjiStorageKeys.inflectionDictionaryFilename
        ) else {
            return [:]
        }

        if let decodedMap = try? JSONDecoder().decode([String: [String: String]].self, from: data) {
            var normalizedMap: [String: [String: String]] = [:]

            for (reading, candidateMap) in decodedMap {
                let normalizedReading = KanaTextNormalizer.normalizedReading(reading)

                guard !normalizedReading.isEmpty else {
                    continue
                }

                var filteredMap: [String: String] = [:]

                for (candidate, inflectionClass) in candidateMap {
                    let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedInflectionClass = inflectionClass.trimmingCharacters(in: .whitespacesAndNewlines)

                    guard !trimmedCandidate.isEmpty,
                        !trimmedInflectionClass.isEmpty else {
                        continue
                    }

                    filteredMap[trimmedCandidate] = trimmedInflectionClass
                }

                if !filteredMap.isEmpty {
                    normalizedMap[normalizedReading] = filteredMap
                }
            }

            guard !normalizedMap.isEmpty else {
                return [:]
            }

            withCacheLock { cachedInflectionDictionary = normalizedMap }
            return normalizedMap
        }

        guard let decoded = try? JSONDecoder().decode([String: [KanaKanjiInflectionEntry]].self, from: data) else {
            return [:]
        }

        var inflectionMap: [String: [String: String]] = [:]

        for (reading, entries) in decoded {
            var candidateClassMap: [String: String] = inflectionMap[reading] ?? [:]

            for entry in entries {
                let candidate = entry.candidate.trimmingCharacters(in: .whitespacesAndNewlines)

                guard !candidate.isEmpty,
                        !entry.inflectionClass.isEmpty else {
                    continue
                }

                candidateClassMap[candidate] = entry.inflectionClass
            }

            if !candidateClassMap.isEmpty {
                inflectionMap[reading] = candidateClassMap
            }
        }

        guard !inflectionMap.isEmpty else {
            return [:]
        }

        withCacheLock { cachedInflectionDictionary = inflectionMap }
        return inflectionMap
    }

    // メモリ内訳census用: 常駐辞書構造の概算バイト数(文字実体のみ、下限値)を1行で返す。
    // ベースライン固定費(キャッシュ空でも残る mallocUsed 約35MB)の正体特定に使う(2570)。
    // 読み込み済みの構造だけ集計する(census がロードを誘発しないよう nil はスキップ)。
    func diagnosticsStructureBytesSummary() -> String {
        func dictBytes(_ dict: [String: [String]]?) -> Int {
            guard let dict else { return -1 }
            var total = 0
            for (key, values) in dict {
                total += key.utf8.count + 32
                for value in values {
                    total += value.utf8.count + 32
                }
                total += 16
            }
            return total
        }
        // 活用辞書([String: [String: String]])はコピーせずその場で集計する
        // (警告時に22k件の一時辞書を作らないため)
        func inflectionBytes(_ dict: [String: [String: String]]?) -> Int {
            guard let dict else { return -1 }
            var total = 0
            for (key, inner) in dict {
                total += key.utf8.count + 32
                for (surface, className) in inner {
                    total += surface.utf8.count + className.utf8.count + 64
                }
                total += 16
            }
            return total
        }
        func kb(_ bytes: Int) -> String {
            bytes < 0 ? "-" : String(bytes / 1024)
        }
        return withCacheLock {
            "structKB: suppl=\(kb(cachedSupplementalSystemDictionary?.estimatedBytes ?? -1))"
                + " sysDict=\(kb(dictBytes(cachedSystemDictionary)))"
                + " initialUser=\(kb(dictBytes(cachedInitialUserDictionary)))"
                + " user=\(kb(dictBytes(cachedUserDictionary)))"
                + " learned=\(kb(dictBytes(cachedLearnedDictionary)))"
                + " infl=\(kb(inflectionBytes(cachedInflectionDictionary)))"
        }
    }

    // メモリ内訳census用: 主要キャッシュの件数を1行で返す(メモリ警告時の診断ログ向け)。
    // footprint 高止まりの正体切り分け(自前キャッシュ vs malloc外の常駐)に使う。
    func diagnosticsCacheCountsSummary() -> String {
        withCacheLock {
            "sysDict=\(cachedSystemDictionary?.count ?? -1)"
                + " suppl=\(cachedSupplementalSystemDictionary?.readingCount ?? -1)"
                + " latin=\(cachedLatinSuggestionEntries?.count ?? -1)"
                + " latinIdx=\(cachedGenericLatinLexiconIndexByLanguage.count)"
                + " lmUni=\(cachedWordLMUnigram.count)"
                + " lmBi=\(cachedWordLMBigram.count)"
                + " wc=\(cachedWordCostsByReading.count)"
                + " infl=\(cachedInflectionDictionary?.count ?? -1)"
                + " inflMap=\(cachedInflectionClassMapsByReading.count)"
        }
    }

    // JSON フォールバック辞書のキャッシュのみ破棄する。sqlite インデックスは保持する。
    // sqlite は mmap 未使用(PRAGMA mmap_size 未設定)で 400MB は常駐せず、close しても
    // 解放されるのはごく小さいページキャッシュのみ。一方 close すると hasWordLMMetadata が
    // false になり連文節が丸ごと停止して劣化変換(しゃしん→者芯 等)になるため、
    // メモリ対策では sqlite を落とさない。
    func clearSystemDictionaryJSONCaches() {
        withCacheLock {
            cachedSystemDictionary = nil
            cachedSupplementalSystemDictionary = nil
            cachedLatinSuggestionEntries = nil
            cachedGenericLatinLexiconIndexByLanguage = [:]
            cachedKanjiRadicalIndex = nil
            cachedSystemCandidateSources = nil
            cachedInflectionDictionary = nil
            cachedInflectionClassMapsByReading = [:]
            cachedWordLMUnigram = [:]
            cachedWordLMBigram = [:]
            cachedWordCostsByReading = [:]
        }
    }

    // sqlite インデックスも含めて完全に閉じる(辞書ファイル差し替え時の再オープン用)。
    // メモリ対策では使わない — unloadSQLiteIndexForMemoryPressure を使うこと。
    func clearSystemDictionaryCaches() {
        clearSystemDictionaryJSONCaches()

        systemDictionaryQueue.sync {
            sqliteIndex = nil
            didAttemptSQLiteIndexLoad = false
            isSQLiteReopenSuppressed = false
        }
    }

    // メモリ圧迫の最終手段: sqlite を閉じ、再オープンをスティッキーに禁止する
    // (連文節は単文節フォールバックへ劣化)。JSONフォールバックへ落ちないよう、JSON側の
    // キャッシュも合わせて破棄+サイズゲートで巨大JSONのデコードは常時拒否済み。
    // 抑止の解除は次のキーボード表示(viewWillAppear→allowSQLiteReopenAfterMemoryPressure)。
    func unloadSQLiteIndexForMemoryPressure() {
        clearSystemDictionaryJSONCaches()

        systemDictionaryQueue.sync {
            sqliteIndex = nil
            didAttemptSQLiteIndexLoad = false
            isSQLiteReopenSuppressed = true
        }
    }

    // キーボードの新しい表示セッションで sqlite 再オープン抑止を解除する。抑止を
    // プロセス生涯スティッキーにすると、警告2回で辞書が永久停止する(拡張プロセスは
    // アプリ切替をまたいで長生きする)。同一表示中の close→reopen 空回り防止は維持される。
    func allowSQLiteReopenAfterMemoryPressure() {
        systemDictionaryQueue.sync {
            isSQLiteReopenSuppressed = false
        }
    }

    // メモリ警告が続くときの縮小モード: LM/word_costs キャッシュを破棄した上で上限を
    // 下げ、再成長を抑える(sqlite クローズと違い変換品質は維持される)。
    func enterConstrainedMemoryCacheMode() {
        withCacheLock {
            isConstrainedMemoryCacheMode = true
            cachedWordLMUnigram.removeAll(keepingCapacity: false)
            cachedWordLMBigram.removeAll(keepingCapacity: false)
            cachedCandidateMinWordCosts.removeAll(keepingCapacity: false)
            cachedWordCostsByReading.removeAll(keepingCapacity: false)
        }
    }

    // 新しい表示セッションで縮小モードを解除する(圧迫エピソードは表示単位で区切る)。
    func exitConstrainedMemoryCacheMode() {
        withCacheLock { isConstrainedMemoryCacheMode = false }
    }

    func clearSharedDataCaches() {
        // 未保存の学習をキャッシュ破棄前に書き出す(デバウンス中のデータを失わない)
        flushPendingLearningPersists()
        withCacheLock {
            cachedUserDictionary = nil
            cachedLearnedDictionary = nil
            cachedSuppressedCandidatesByReading = nil
            cachedLearningScores = nil
            cachedLearningScoresByReading = nil
            cachedShortcutVocabulary = nil
            // 補助語彙は失敗(未デプロイ)もキャッシュするため、後からのデプロイはここで拾う
            cachedSupplementalSystemDictionary = nil
        }
    }

    func userDictionary() -> [String: [String]] {
        if let cached = withCacheLock({ cachedUserDictionary }) {
            return cached
        }

        guard let decoded = decodedStringArrayDictionary(forKey: KanaKanjiStorageKeys.userDictionary) else {
            withCacheLock { cachedUserDictionary = [:] }
            return [:]
        }

        let normalized = normalizeDictionary(decoded)
        withCacheLock { cachedUserDictionary = normalized }
        return normalized
    }

    func learnedDictionary() -> [String: [String]] {
        if let cached = withCacheLock({ cachedLearnedDictionary }) {
            return cached
        }

        guard let decoded = decodedStringArrayDictionary(forKey: KanaKanjiStorageKeys.learnedDictionary) else {
            withCacheLock { cachedLearnedDictionary = [:] }
            return [:]
        }

        let normalized = normalizeDictionary(decoded)
        // かな識別(候補==読み)は原則「変換」ではない。文丸ごとの誤学習(かな確定を学習して
        // いた時代の汚染)は読み込み時に除外し、連文節の最安素通りブロックを防ぐ。
        // ただし単語相当の短い読み(ちゃんと/そして 等。かな候補チップの明示タップで学習)は
        // 許可し、変換候補側にも出せるようにする。
        var cleaned: [String: [String]] = [:]
        cleaned.reserveCapacity(normalized.count)
        for (reading, candidates) in normalized {
            let allowsIdentity = reading.count <= Self.kanaIdentityLearnableMaxReadingCount
            let filtered = allowsIdentity ? candidates : candidates.filter { $0 != reading }
            if !filtered.isEmpty {
                cleaned[reading] = filtered
            }
        }
        withCacheLock { cachedLearnedDictionary = cleaned }
        return cleaned
    }

    func initialUserDictionary() -> [String: [String]] {
        if let cached = withCacheLock({ cachedInitialUserDictionary }) {
            return cached
        }

        // 追加語彙(sacoche=InitialAjout)と変換対策語(misc=InitialMisc)を統合してラティスの
        // curated 供給に使う。どちらも変換には効かせるが、コンテナアプリの「追加語彙」への
        // 初期表示は sacoche(InitialAjout)側のみ(App 側のマイグレーションが分離管理)。
        let bundle = Bundle(for: KanaKanjiStore.self)

        func loadBundled(_ resourceName: String) -> [String: [String]] {
            guard let url = bundle.url(forResource: resourceName, withExtension: "json"),
                let data = try? Data(contentsOf: url),
                let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
                return [:]
            }
            return decoded
        }

        var combined = loadBundled(KanaKanjiStorageKeys.initialUserDictionaryResourceName)
        for (reading, candidates) in loadBundled(KanaKanjiStorageKeys.initialMiscDictionaryResourceName) {
            combined[reading, default: []].append(contentsOf: candidates)
        }

        let normalized = normalizeDictionary(combined)
        withCacheLock { cachedInitialUserDictionary = normalized }
        return normalized
    }

    func shortcutVocabulary() -> [String] {
        if let cached = withCacheLock({ cachedShortcutVocabulary }) {
            return cached
        }
        let resolved = resolveShortcutVocabulary()
        withCacheLock { cachedShortcutVocabulary = resolved }
        return resolved
    }

    // makeRenderConfiguration が打鍵ごとに呼ぶため、JSON デコードは初回のみにする
    // (設定変更時は clearSharedDataCaches で破棄)。
    private func resolveShortcutVocabulary() -> [String] {
        let userCandidates = decodedStringArray(forKey: KanaKanjiStorageKeys.shortcutVocabulary) ?? []

        if !userCandidates.isEmpty {
            return uniqueShortcutCandidates(
                from: initialShortcutVocabulary() + userCandidates
            )
        }

        if let legacyDictionary = decodedStringArrayDictionary(forKey: KanaKanjiStorageKeys.shortcutVocabulary) {
            let legacyCandidates = legacyDictionary["☻"] ?? legacyDictionary
                .keys
                .sorted()
                .flatMap { legacyDictionary[$0] ?? [] }

            if !legacyCandidates.isEmpty {
                return uniqueShortcutCandidates(
                    from: initialShortcutVocabulary() + legacyCandidates
                )
            }
        }

        return initialShortcutVocabulary()
    }

    func initialShortcutVocabulary() -> [String] {
        if let cached = withCacheLock({ cachedInitialShortcutVocabulary }) {
            return cached
        }

        let bundle = Bundle(for: KanaKanjiStore.self)

        guard let initialDictionaryURL = bundle.url(
            forResource: KanaKanjiStorageKeys.initialShortcutVocabularyResourceName,
            withExtension: "json"
        ),
            let data = try? Data(contentsOf: initialDictionaryURL) else {
            withCacheLock { cachedInitialShortcutVocabulary = [] }
            return []
        }

        if let decodedArray = try? JSONDecoder().decode([String].self, from: data) {
            let normalized = uniqueShortcutCandidates(from: decodedArray)
            withCacheLock { cachedInitialShortcutVocabulary = normalized }
            return normalized
        }

        if let decodedDictionary = try? JSONDecoder().decode([String: [String]].self, from: data) {
            let candidates = decodedDictionary["☻"] ?? decodedDictionary
                .keys
                .sorted()
                .flatMap { decodedDictionary[$0] ?? [] }
            let normalized = uniqueShortcutCandidates(from: candidates)
            withCacheLock { cachedInitialShortcutVocabulary = normalized }
            return normalized
        }

        withCacheLock { cachedInitialShortcutVocabulary = [] }
        return []
    }

    // suppr.plist 由来の抑制(バンドル同梱、UI非表示)。poubelle の UserDefaults 経路とは別に
    // キーボードが直接読む。実機/バンドル解決は追加語彙(initialUserDictionary)と同じ仕組み。
    private func bundledHiddenSuppressionDictionary() -> [String: [String]] {
        if let cached = withCacheLock({ cachedBundledHiddenSuppression }) {
            return cached
        }
        let bundle = Bundle(for: KanaKanjiStore.self)
        guard let url = bundle.url(
            forResource: KanaKanjiStorageKeys.initialSuppressionHiddenResourceName,
            withExtension: "json"
        ),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            withCacheLock { cachedBundledHiddenSuppression = [:] }
            return [:]
        }
        withCacheLock { cachedBundledHiddenSuppression = decoded }
        return decoded
    }

    func suppressedCandidatesByReading() -> [String: Set<String>] {
        if let cached = withCacheLock({ cachedSuppressedCandidatesByReading }) {
            return cached
        }

        // UserDefaults(poubelle=アプリ移行分+アプリUIでの手動抑制)と、バンドル直読みの
        // hidden(suppr.plist 由来=変換対策で非表示)を統合する。変換時は両者を対等に抑制。
        var decodedDictionary = decodedStringArrayDictionary(
            forKey: KanaKanjiStorageKeys.suppressionVocabulary
        ) ?? [:]
        for (reading, candidates) in bundledHiddenSuppressionDictionary() {
            decodedDictionary[reading, default: []].append(contentsOf: candidates)
        }

        guard !decodedDictionary.isEmpty else {
            withCacheLock { cachedSuppressedCandidatesByReading = [:] }
            return [:]
        }

        var result: [String: Set<String>] = [:]

        for (reading, candidates) in decodedDictionary {
            let normalizedReading = KanaTextNormalizer.normalizedReading(reading)

            guard !normalizedReading.isEmpty else {
                continue
            }

            var filteredCandidates = result[normalizedReading] ?? []

            for candidate in candidates {
                let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

                guard !trimmed.isEmpty else {
                    continue
                }

                filteredCandidates.insert(trimmed)
            }

            if !filteredCandidates.isEmpty {
                result[normalizedReading] = filteredCandidates
            }
        }

        withCacheLock { cachedSuppressedCandidatesByReading = result }
        return result
    }

    private func decodedStringArray(forKey key: String) -> [String]? {
        guard let defaults else {
            return nil
        }

        if let arrayData = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode([String].self, from: arrayData) {
            return decoded
        }

        if let rawArray = defaults.array(forKey: key) {
            return rawArray.compactMap { $0 as? String }
        }

        return nil
    }

    func decodedStringArrayDictionary(forKey key: String) -> [String: [String]]? {
        guard let defaults else {
            return nil
        }

        if let dictionaryData = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode([String: [String]].self, from: dictionaryData) {
            return decoded
        }

        guard let rawDictionary = defaults.dictionary(forKey: key) else {
            return nil
        }

        var decoded: [String: [String]] = [:]

        for (reading, rawCandidates) in rawDictionary {
            if let candidates = rawCandidates as? [String] {
                decoded[reading] = candidates
            } else if let candidates = rawCandidates as? [Any] {
                decoded[reading] = candidates.compactMap { $0 as? String }
            }
        }

        return decoded
    }

    func normalizeDictionary(_ dictionary: [String: [String]]) -> [String: [String]] {
        var normalized: [String: [String]] = [:]

        for (reading, candidates) in dictionary {
            let normalizedReading = KanaTextNormalizer.normalizedReading(reading)

            guard !normalizedReading.isEmpty else {
                continue
            }

            let mergedCandidates = (normalized[normalizedReading] ?? []) + candidates
            normalized[normalizedReading] = uniqueCandidates(from: mergedCandidates)
        }

        return normalized
    }

    private func uniqueCandidates(from candidates: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmed.isEmpty,
                    !seen.contains(trimmed) else {
                continue
            }

            seen.insert(trimmed)
            result.append(trimmed)
        }

        return result
    }

    private func uniqueShortcutCandidates(from candidates: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for candidate in candidates {
            let normalized = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !normalized.isEmpty,
                    !seen.contains(normalized) else {
                continue
            }

            seen.insert(normalized)
            result.append(candidate)
        }

        return result
    }

    private func mergedSystemCandidates(primary: [String], supplemental: [String]) -> [String] {
        guard !supplemental.isEmpty else {
            return primary
        }

        return uniqueCandidates(from: primary + supplemental)
    }

}

// 補助語彙(SecondVocab: vin/it/ryukyu/personnalites/drapeaux/monnaies)の常駐用コンパクト表。
// [String: [String]] だと Swift 辞書+String ヒープのオーバーヘッドで約6.8MB常駐する
// (15,901読み。初回変換の used +6.8MB の主因 — 高水位台帳 2615 で実測)。
// 消費点は「読み単位の点引き」(候補マージ/昇格判定/カタカナ化抑止免除)と
// 「一度きりの全走査」(欧文サジェスト索引の構築)だけなので、全文字列を1本の UTF8 ブロブに
// 詰め、読みはバイト列ソート+二分探索で引く。実測で常駐 約1MB 弱まで下がる。
struct SupplementalVocabCompactStore: Equatable {
    // 全読み・全表層の UTF8 を連結したブロブ。個々の文字列はオフセット表で参照する。
    private let blob: [UInt8]
    // 読み i のバイト範囲 = blob[readingOffsets[i]..<readingOffsets[i+1]](読みはバイト列昇順)
    private let readingOffsets: [UInt32]
    // 読み i の表層は表層スロット surfaceListStarts[i]..<surfaceListStarts[i+1]
    private let surfaceListStarts: [UInt32]
    // 表層スロット j のバイト範囲 = blob[surfaceOffsets[j]..<surfaceOffsets[j+1]]
    private let surfaceOffsets: [UInt32]

    static let empty = SupplementalVocabCompactStore(dictionary: [:])

    var readingCount: Int { max(0, readingOffsets.count - 1) }
    var isEmpty: Bool { readingCount == 0 }
    var estimatedBytes: Int {
        blob.count + (readingOffsets.count + surfaceListStarts.count + surfaceOffsets.count) * 4
    }

    init(dictionary: [String: [String]]) {
        let sortedReadings = dictionary.keys.sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
        var blob: [UInt8] = []
        var readingOffsets: [UInt32] = []
        var surfaceListStarts: [UInt32] = []
        var surfaceOffsets: [UInt32] = []
        blob.reserveCapacity(dictionary.count * 24)
        readingOffsets.reserveCapacity(sortedReadings.count + 1)
        surfaceListStarts.reserveCapacity(sortedReadings.count + 1)
        // 表層の総数は不明なので append 主体で構築(初回ロード時の一度きり)
        var surfaceCursorOffsets: [UInt32] = []
        for reading in sortedReadings {
            readingOffsets.append(UInt32(blob.count))
            blob.append(contentsOf: reading.utf8)
            surfaceListStarts.append(UInt32(surfaceCursorOffsets.count))
            for surface in dictionary[reading] ?? [] {
                surfaceCursorOffsets.append(UInt32(blob.count))
                blob.append(contentsOf: surface.utf8)
            }
        }
        readingOffsets.append(UInt32(blob.count))
        surfaceListStarts.append(UInt32(surfaceCursorOffsets.count))
        // blob の配置は [読みi][表層i0][表層i1]…[読みi+1][表層(i+1)0]… の交互。
        // 各要素の終端は「次に始まるものの開始」で求まる(readingBytes/surfaceBytes 参照)。
        self.surfaceOffsets = surfaceCursorOffsets
        self.blob = blob
        self.readingOffsets = readingOffsets
        self.surfaceListStarts = surfaceListStarts
    }

    private func readingBytes(_ index: Int) -> ArraySlice<UInt8> {
        // 読み index のバイト範囲。読みの直後にその表層列が続くため、終端は
        // 「最初の表層の開始」(表層が無ければ次の読みの開始)。
        let start = Int(readingOffsets[index])
        let firstSurfaceSlot = Int(surfaceListStarts[index])
        let lastSurfaceSlotExclusive = Int(surfaceListStarts[index + 1])
        let end: Int
        if firstSurfaceSlot < lastSurfaceSlotExclusive {
            end = Int(surfaceOffsets[firstSurfaceSlot])
        } else {
            end = Int(readingOffsets[index + 1])
        }
        return blob[start..<end]
    }

    private func surfaceBytes(slot: Int, ownerReadingIndex: Int) -> ArraySlice<UInt8> {
        let start = Int(surfaceOffsets[slot])
        let lastSlotOfOwner = Int(surfaceListStarts[ownerReadingIndex + 1]) - 1
        let end = slot < lastSlotOfOwner
            ? Int(surfaceOffsets[slot + 1])
            : Int(readingOffsets[ownerReadingIndex + 1])
        return blob[start..<end]
    }

    private func indexOfReading(_ reading: String) -> Int? {
        let target = Array(reading.utf8)
        var low = 0
        var high = readingCount - 1
        while low <= high {
            let mid = (low + high) / 2
            let bytes = readingBytes(mid)
            if bytes.elementsEqual(target) {
                return mid
            }
            if bytes.lexicographicallyPrecedes(target) {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return nil
    }

    func candidates(for reading: String) -> [String] {
        guard let index = indexOfReading(reading) else {
            return []
        }
        var result: [String] = []
        for slot in Int(surfaceListStarts[index])..<Int(surfaceListStarts[index + 1]) {
            result.append(String(decoding: surfaceBytes(slot: slot, ownerReadingIndex: index), as: UTF8.self))
        }
        return result
    }

    func contains(reading: String, surface: String) -> Bool {
        guard let index = indexOfReading(reading) else {
            return false
        }
        let target = Array(surface.utf8)
        for slot in Int(surfaceListStarts[index])..<Int(surfaceListStarts[index + 1])
        where surfaceBytes(slot: slot, ownerReadingIndex: index).elementsEqual(target) {
            return true
        }
        return false
    }

    // 欧文サジェスト索引の構築用: 全表層を一度だけ列挙する
    func forEachCandidate(_ body: (String) -> Void) {
        for index in 0..<readingCount {
            for slot in Int(surfaceListStarts[index])..<Int(surfaceListStarts[index + 1]) {
                body(String(decoding: surfaceBytes(slot: slot, ownerReadingIndex: index), as: UTF8.self))
            }
        }
    }
}
