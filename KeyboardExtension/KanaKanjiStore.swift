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
    // システム辞書 JSON キャッシュの排他。DispatchQueue.sync はジェネリックな sync が呼び出しごとに箱を確保する
    // (供給段で打鍵あたり約 250 回。3096)ので NSLock に。全部 sync 利用だったので意味は同じ
    private let systemDictionaryLock = NSLock()

    @inline(__always)
    private func withSystemDictionaryLock<T>(_ body: () throws -> T) rethrows -> T {
        systemDictionaryLock.lock()
        defer { systemDictionaryLock.unlock() }
        return try body()
    }
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
    // 汎用Latinサジェスト語彙(同梱の頻度リスト。追加語彙とは別レイヤー)のエントリ。
    // rank はリスト内の頻度順位(小さいほど高頻度)。
    struct GenericLatinLexiconEntry {
        let searchKey: String
        let candidate: String
        let rank: Int
    }
    private var sqliteIndex: KanaKanjiSQLiteIndex?
    private var didAttemptSQLiteIndexLoad = false
    private var cachedSystemDictionary: [String: [String]]?
    private var cachedSupplementalSystemDictionary: SupplementalVocabCompactStore?
    // 追加語彙(補助語彙 SecondVocab)由来の欧文サジェスト索引。ビルド時に前計算した
    // LatinSuggestionSupplemental.txt(キーのバイト順ソート済み)を mmap で保持するだけで、
    // 実行時構築(補助語彙 15k 件の走査で fp +8MB のピーク)は無くなった(2770)
    var cachedLatinSupplementalIndex: GenericLatinLexiconFileIndex?
    // 汎用Latinサジェスト語彙のmmap索引キャッシュ(言語別)と有効言語
    // (既定は全言語OFF。設定で言語別にON)。索引は Data(mappedIfSafe) 保持のみで
    // 常駐フットプリントを持たない(GenericLatinLexiconFileIndex 定義コメント参照)。
    var cachedGenericLatinLexiconIndexByLanguage: [String: GenericLatinLexiconFileIndex] = [:]
    var genericLatinLexiconEnabledLanguages: Set<String> = []
    // テスト用: bundle 未同梱の環境(unit test)でリポジトリのtxtを直接読ませるディレクトリ
    var genericLatinLexiconDirectoryURLOverride: URL?
    // 漢字1文字ピッカーの索引(mmap)。テスト用に読み込み元を差し替えられるようにする。
    var cachedKanjiRadicalIndex: KanjiRadicalFileIndex?
    var kanjiRadicalIndexDirectoryURLOverride: URL?
    private var cachedSystemCandidateSources: [String: [String: Set<String>]]?
    private var cachedInflectionDictionary: [String: [String: String]]?
    // 読み別の inflection_classes キャッシュ(連文節の辞書形述語判定用)
    private var cachedInflectionClassMapsByReading: [String: [String: String]] = [:]
    // 読み別の人名区分キャッシュ(連文節の人名判定用。表層→姓/名。空も覚える)
    private var cachedPersonNameKindsByReading: [String: [String: String]] = [:]
    // 連文節 DP の LM 点引きキャッシュ。前置き入力ではスパン/ペアの大半が毎キーストロークで
    // 再出現するため、点クエリ(1変換あたり unigram 数百+bigram 千超)を初出のみに抑える。
    // 「未観測」も番兵(-1)で覚える — LM のヒット率は低く、negative キャッシュが本体。
    // 上限超過時は全消去(まれな一括再クエリで済ませ、LRU 管理のオーバーヘッドを避ける)。
    // LM 点引きキャッシュは長寿命のためキーを64bitハッシュ化し、POD 辞書
    // ([UInt64: Int]=キー・値とも単一連続バッファに内蔵)へ集約する。エントリごとの
    // String がヒープに散在して malloc アリーナを断片化させるのを防ぐ(2566)。
    // Hasher はプロセス内で安定(キャッシュはプロセス内限り)。64bit 衝突(〜10^-10)は
    // コスト近似として許容。
    // 2 世代方式(3038): 以前は上限到達で全消しだったため、1 変換で数百〜千件強の点クエリが続く
    // 連続入力では数変換ごとに全部捨てて sqlite を引き直していた(perf テストの warm 計測で
    // 実行時間の約 18% が sqlite3_step)。半分ずつ世代を送ることで、直近 limit/2 件は必ず残る
    struct TwoGenerationCache<Key: Hashable, Value> {
        private var current: [Key: Value] = [:]
        private var previous: [Key: Value] = [:]
        // 世代の 1 本目だけ reserveCapacity が掛かっていなかった(3201)。空から育つと
        // rehash のたびに一回り大きい塊を確保して前のを捨てる成長列になり、長寿命の
        // キャッシュがアリーナに穴を開ける側に回る。最初から上限ぶんを一度で取る
        private var didReserveCurrent = false
        var count: Int { current.count + previous.count }
        subscript(key: Key) -> Value? {
            current[key] ?? previous[key]
        }
        mutating func set(_ value: Value, for key: Key, limit: Int) {
            if !didReserveCurrent {
                didReserveCurrent = true
                current.reserveCapacity(max(1, limit / 2))
            }
            if current.count >= max(1, limit / 2) {
                previous = current
                current = [:]
                current.reserveCapacity(max(1, limit / 2))
            }
            current[key] = value
        }
        mutating func removeAll(keepingCapacity: Bool) {
            current.removeAll(keepingCapacity: keepingCapacity)
            previous.removeAll(keepingCapacity: false)
            // 容量を手放したなら次の set で取り直す(3201)
            didReserveCurrent = keepingCapacity
        }
    }
    typealias TwoGenerationLMCache = TwoGenerationCache<UInt64, Int>
    private var cachedWordLMUnigram = TwoGenerationLMCache()
    private var cachedWordLMBigram = TwoGenerationLMCache()
    #if DEBUG
    // perf テスト用: bigram 点クエリの要求数と sqlite まで行った数(ヒット率の確認。3038)
    nonisolated(unsafe) static var diagnosticsLMBigramRequested = 0
    nonisolated(unsafe) static var diagnosticsLMBigramFetched = 0
    #endif
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
    // 2 世代方式(3075): 上限で全消しだと数十変換ごとに読み別 word_costs を全部引き直していた(Mac の長セッション模擬で wc=4025→309)
    private var cachedWordCostsByReading = TwoGenerationCache<String, [String: Int]>()
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
    private var cachedInitialAjoutVocabulary: [String: [String]]?
    private var cachedInitialShortcutVocabulary: [String]?
    var cachedAjoutVocabulary: [String: [String]]?
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

    func sharedOrBundledDictionaryURL(filename: String) -> URL? {
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
        withSystemDictionaryLock {
            if let sqliteIndex {
                return sqliteIndex
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
            // かな識別(表層==読み)は常に残す(sqlite 側と同条件。2854)
            if candidate == normalizedReading {
                return true
            }

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
    private static let inflectionClassDeniedLock = NSLock()

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

    // その読みが五段動詞として登録されているか(inflection_classes の godan-*)。
    // 可能動詞の並べ替え(のみほせる→のみほす)を、基底が本物の五段動詞のときだけに絞るために使う(2868)。
    // おさむ のように動詞として登録が無い読み(人名の 修/収/治)を基底と誤認すると、
    // おさめる の並びが人名の辞書順で塗り替えられる。
    func hasGodanVerbClass(reading: String) -> Bool {
        if let cached = withCacheLock({ cachedInflectionClassMapsByReading[reading] }) {
            return cached.values.contains { $0.hasPrefix("godan") }
        }
        let classMap: [String: String]
        if let sqliteIndex = sqliteIndexIfAvailable() {
            classMap = sqliteIndex.inflectionClassMap(for: reading)
        } else {
            classMap = loadInflectionDictionary()[reading] ?? [:]
        }
        withCacheLock { cachedInflectionClassMapsByReading[reading] = classMap }
        return classMap.values.contains { $0.hasPrefix("godan") }
    }

    // サ変名詞(動作名詞。長押し/タップ/操作/削除 = inflection_classes の suru)かどうか。
    // 連文節で「動作名詞+で」(手段の定型)を、助詞を呑んだ外来語1語(長押しデコード)より
    // 優先するために使う(2859)。上と同じ読み単位キャッシュに相乗りする。
    func isSuruNoun(reading: String, candidate: String) -> Bool {
        if let cached = withCacheLock({ cachedInflectionClassMapsByReading[reading] }) {
            return cached[candidate] == "suru"
        }
        let classMap: [String: String]
        if let sqliteIndex = sqliteIndexIfAvailable() {
            classMap = sqliteIndex.inflectionClassMap(for: reading)
        } else {
            classMap = loadInflectionDictionary()[reading] ?? [:]
        }
        withCacheLock { cachedInflectionClassMapsByReading[reading] = classMap }
        return classMap[candidate] == "suru"
    }

    // この読みに辞書(inflection_classes)のサ変名詞が 1 つでも在るか。pos 無しの curated 名詞(香信=椎茸)を
    // サ変と推論するかの門番に使う(3067)
    func hasSuruNoun(reading: String) -> Bool {
        if let cached = withCacheLock({ cachedInflectionClassMapsByReading[reading] }) {
            return cached.values.contains("suru")
        }
        let classMap: [String: String]
        if let sqliteIndex = sqliteIndexIfAvailable() {
            classMap = sqliteIndex.inflectionClassMap(for: reading)
        } else {
            classMap = loadInflectionDictionary()[reading] ?? [:]
        }
        withCacheLock { cachedInflectionClassMapsByReading[reading] = classMap }
        return classMap.values.contains("suru")
    }

    // 連文節用: 辞書形の読み(〜する)に suru クラスで登録された表層の語幹(〜する を外したもの)。
    // misc.plist の pos 付き登録(有する/瓶詰めする)は名詞単体(有/瓶詰め)がノードとして
    // 立たないことがあり、連用中止形(有し)を名詞ノードから作れない。辞書形側から直接引く(2879)
    func suruVerbStems(dictionaryFormReading: String) -> [String] {
        guard dictionaryFormReading.hasSuffix("する") else {
            return []
        }
        let classMap: [String: String]
        if let cached = withCacheLock({ cachedInflectionClassMapsByReading[dictionaryFormReading] }) {
            classMap = cached
        } else if let sqliteIndex = sqliteIndexIfAvailable() {
            classMap = sqliteIndex.inflectionClassMap(for: dictionaryFormReading)
            withCacheLock { cachedInflectionClassMapsByReading[dictionaryFormReading] = classMap }
        } else {
            classMap = loadInflectionDictionary()[dictionaryFormReading] ?? [:]
            withCacheLock { cachedInflectionClassMapsByReading[dictionaryFormReading] = classMap }
        }
        return classMap.compactMap { surface, inflectionClass -> String? in
            guard inflectionClass == "suru", surface.hasSuffix("する"),
                surface != dictionaryFormReading else {
                return nil
            }
            return String(surface.dropLast(2))
        }.sorted()
    }

    // 連文節用: 読みに対する人名候補(表層→姓/名)。sqlite の person_names 表(Sudachi の 名詞,固有名詞,人名)。
    // 表が無い旧 DB やテスト用の JSON 経路では空(2845)
    func personNameKinds(for reading: String) -> [String: String] {
        if let cached = withCacheLock({ cachedPersonNameKindsByReading[reading] }) {
            return cached
        }
        let kinds = sqliteIndexIfAvailable()?.personNameKindMap(for: reading) ?? [:]
        withCacheLock { cachedPersonNameKindsByReading[reading] = kinds }
        return kinds
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
            cachedWordCostsByReading.set(costMap, for: normalizedReading, limit: activeWordCostsCacheLimit)
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
        // 結果辞書と未取得リストの容量を先に取る(3201)。挿入で育つと 2KB 超の rehash が
        // 毎打鍵に数回走り、長寿命キャッシュの隣に穴を作る
        var result: [String: Int] = [:]
        result.reserveCapacity(surfaces.count)
        var uncached: [String] = []
        uncached.reserveCapacity(surfaces.count)
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
            let limit = activeWordLMCacheLimit
            for surface in uncached {
                if let cost = fetched[surface] {
                    cachedWordLMUnigram.set(cost, for: Self.lmCacheKey(surface), limit: limit)
                    result[surface] = cost
                } else {
                    cachedWordLMUnigram.set(Self.wordLMMissingSentinel, for: Self.lmCacheKey(surface), limit: limit)
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
        result.reserveCapacity(candidates.count)
        var uncached: [String] = []
        uncached.reserveCapacity(candidates.count)
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
    // 1 対だけ(遷移コスト内の その場引き用)。配列・辞書・鍵文字列を作らない(3096)
    func wordLMBigramCost(prev: String, cur: String) -> Int? {
        guard let sqliteIndex = sqliteIndexIfAvailable() else {
            return nil
        }
        #if DEBUG
        Self.diagnosticsLMBigramRequested += 1
        #endif
        let hashedKey = Self.lmCacheKey(prev, cur)
        if let cached = withCacheLock({ cachedWordLMBigram[hashedKey] }) {
            return cached == Self.wordLMMissingSentinel ? nil : cached
        }
        #if DEBUG
        Self.diagnosticsLMBigramFetched += 1
        #endif
        let fetched = sqliteIndex.wordLMBigramCost(prev: prev, cur: cur)
        withCacheLock {
            cachedWordLMBigram.set(fetched ?? Self.wordLMMissingSentinel, for: hashedKey, limit: activeWordLMCacheLimit)
        }
        return fetched
    }

    // 入力と同じ並びで返す(鍵文字列を作らない版。連文節の一括引き用。3096)
    func wordLMBigramCostsAligned(for pairs: [(String, String)]) -> [Int?] {
        var result = [Int?](repeating: nil, count: pairs.count)
        guard let sqliteIndex = sqliteIndexIfAvailable() else {
            return result
        }
        #if DEBUG
        Self.diagnosticsLMBigramRequested += pairs.count
        #endif
        // append の成長列(4→8→16…)で中くらいの確保が毎打鍵に散るのを避ける(3201)
        var uncachedIndices: [Int] = []
        uncachedIndices.reserveCapacity(pairs.count)
        withCacheLock {
            for (index, pair) in pairs.enumerated() {
                if let cached = cachedWordLMBigram[Self.lmCacheKey(pair.0, pair.1)] {
                    if cached != Self.wordLMMissingSentinel {
                        result[index] = cached
                    }
                } else {
                    uncachedIndices.append(index)
                }
            }
        }
        guard !uncachedIndices.isEmpty else {
            return result
        }
        #if DEBUG
        Self.diagnosticsLMBigramFetched += uncachedIndices.count
        #endif
        var uncachedPairs: [(String, String)] = []
        uncachedPairs.reserveCapacity(uncachedIndices.count)
        for index in uncachedIndices {
            uncachedPairs.append(pairs[index])
        }
        let fetched = sqliteIndex.wordLMBigramCostsAligned(for: uncachedPairs)
        withCacheLock {
            let limit = activeWordLMCacheLimit
            for (position, index) in uncachedIndices.enumerated() {
                let hashedKey = Self.lmCacheKey(pairs[index].0, pairs[index].1)
                if let cost = fetched[position] {
                    cachedWordLMBigram.set(cost, for: hashedKey, limit: limit)
                    result[index] = cost
                } else {
                    cachedWordLMBigram.set(Self.wordLMMissingSentinel, for: hashedKey, limit: limit)
                }
            }
        }
        return result
    }

    func wordLMBigramCosts(for pairs: [(String, String)]) -> [String: Int] {
        guard let sqliteIndex = sqliteIndexIfAvailable() else {
            return [:]
        }
        #if DEBUG
        Self.diagnosticsLMBigramRequested += pairs.count
        #endif
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
        #if DEBUG
        Self.diagnosticsLMBigramFetched += uncached.count
        #endif
        let fetched = sqliteIndex.wordLMBigramCosts(for: uncached)
        withCacheLock {
            let limit = activeWordLMCacheLimit
            for (prev, cur) in uncached {
                let key = prev + "\t" + cur
                let hashedKey = Self.lmCacheKey(prev, cur)
                if let cost = fetched[key] {
                    cachedWordLMBigram.set(cost, for: hashedKey, limit: limit)
                    result[key] = cost
                } else {
                    cachedWordLMBigram.set(Self.wordLMMissingSentinel, for: hashedKey, limit: limit)
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

        // ビルド時に畳んだ版(3030)があればそれを読む。JSON を [String: [String]](16,226 読み)へ
        // 復元してから畳む従来経路は、その一瞬の辞書が malloc アリーナを +8MB 広げて返さなかった
        // (実機の区間計測: 「直接候補: 補助語彙の読み込み alloc 28→36」)。畳んだ版なら配列 4 本を
        // 作るだけで済む。旧環境向けに JSON 経路は残す
        // mmap で開く(3031): Data(contentsOf:) で読むと heap にコピーが乗り、配列 4 本の復元でも
        // 約 1.5MB を確保して malloc アリーナを 4MB 広げていた。mappedIfSafe なら読み取り専用の
        // ファイルページとして OS が管理し、heap にも phys_footprint にも乗らない
        if let compactURL = sharedOrBundledDictionaryURL(
            filename: KanaKanjiStorageKeys.supplementalSystemDictionaryCompactFilename
        ),
            let compactData = try? Data(contentsOf: compactURL, options: .mappedIfSafe),
            compactData.count <= Self.dictionaryDataMaxByteCount,
            let compact = SupplementalVocabCompactStore(serialized: compactData) {
            withCacheLock { cachedSupplementalSystemDictionary = compact }
            return compact
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
                + " initialUser=\(kb(dictBytes(cachedInitialAjoutVocabulary)))"
                + " user=\(kb(dictBytes(cachedAjoutVocabulary)))"
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
                + " latin=\(cachedLatinSupplementalIndex?.entryCount ?? -1)"
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
            cachedLatinSupplementalIndex = nil
            cachedGenericLatinLexiconIndexByLanguage = [:]
            cachedKanjiRadicalIndex = nil
            cachedSystemCandidateSources = nil
            cachedInflectionDictionary = nil
            cachedInflectionClassMapsByReading = [:]
            cachedPersonNameKindsByReading = [:]
            cachedWordLMUnigram = TwoGenerationLMCache()
            cachedWordLMBigram = TwoGenerationLMCache()
            cachedWordCostsByReading = TwoGenerationCache()
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

    // 学習リセット専用: プロセス内の学習キャッシュを「書き出さずに」捨てる(2968)。
    // 通常の clearSharedDataCaches は捨てる前に書き出すため、コンテナ app が共有領域の
    // 学習を消しても、拡張が持っていたリセット前の学習が書き戻ってリセットが取り消される。
    // dirty フラグも落とし、デバウンス中の書き出し予約も取り消す。
    func discardLearningCachesWithoutPersist() {
        withCacheLock {
            learningPersistWorkItem?.cancel()
            learningPersistWorkItem = nil
            learningPersistDirtyLearned = false
            learningPersistDirtyScores = false
            cachedLearnedDictionary = nil
            cachedLearningScores = nil
            cachedLearningScoresByReading = nil
        }
    }

    func clearSharedDataCaches() {
        // 未保存の学習をキャッシュ破棄前に書き出す(デバウンス中のデータを失わない)。
        // 学習リセット経由のときは呼び出し側が先に discardLearningCachesWithoutPersist を
        // 呼んでいるので、ここで書き戻るものは無い(2968)
        flushPendingLearningPersists()
        withCacheLock {
            cachedAjoutVocabulary = nil
            cachedLearnedDictionary = nil
            cachedSuppressedCandidatesByReading = nil
            cachedLearningScores = nil
            cachedLearningScoresByReading = nil
            cachedShortcutVocabulary = nil
            // 補助語彙は失敗(未デプロイ)もキャッシュするため、後からのデプロイはここで拾う
            cachedSupplementalSystemDictionary = nil
        }
    }

    func ajoutVocabulary() -> [String: [String]] {
        if let cached = withCacheLock({ cachedAjoutVocabulary }) {
            return cached
        }

        guard let decoded = decodedStringArrayDictionary(forKey: KanaKanjiStorageKeys.ajoutVocabulary) else {
            withCacheLock { cachedAjoutVocabulary = [:] }
            return [:]
        }

        let normalized = normalizeDictionary(decoded)
        withCacheLock { cachedAjoutVocabulary = normalized }
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

    func initialAjoutVocabulary() -> [String: [String]] {
        if let cached = withCacheLock({ cachedInitialAjoutVocabulary }) {
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

        var combined = loadBundled(KanaKanjiStorageKeys.initialAjoutVocabularyResourceName)
        for (reading, candidates) in loadBundled(KanaKanjiStorageKeys.initialMiscDictionaryResourceName) {
            combined[reading, default: []].append(contentsOf: candidates)
        }

        let normalized = normalizeDictionary(combined)
        withCacheLock { cachedInitialAjoutVocabulary = normalized }
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
    // キーボードが直接読む。実機/バンドル解決は追加語彙(initialAjoutVocabulary)と同じ仕組み。
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
        candidates.uniquedTrimmedCandidates()
    }

    private func uniqueShortcutCandidates(from candidates: [String]) -> [String] {
        candidates.uniquedTrimmedCandidates(keepingOriginalText: true)
    }

    private func mergedSystemCandidates(primary: [String], supplemental: [String]) -> [String] {
        guard !supplemental.isEmpty else {
            return primary
        }

        return uniqueCandidates(from: primary + supplemental)
    }

}

