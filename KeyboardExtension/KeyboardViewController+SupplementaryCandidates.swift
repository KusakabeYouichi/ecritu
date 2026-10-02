import SwiftUI
import UIKit
import CoreFoundation
import Darwin

extension KeyboardViewController {
    func refreshSupplementaryLexiconIfNeeded(force: Bool) {
        guard Self.isSupplementaryExternalCandidatesEnabled else {
            supplementaryLexiconCandidatesByReading = .empty
            supplementaryMergedCandidatesCacheByKey = [:]
            return
        }

        // 「iOS のユーザ辞書の単語」が「使わない」なら、取得も保存もしない(3305)。以前は設定に関係なく
        // UILexicon(iOS のユーザ辞書の語。iOS はここに連絡先の姓名も含める)を取得して、読み→候補の表を
        // 共有領域の UserDefaults に平文で残していた(2026-10-02 のセキュリティー検査で検出。連絡先キャッシュ側は
        // 暗号化・バックアップ除外・オフ時削除まで整っていたのに、こちらだけ素通しだった)。設定が「使う」の
        // ときだけ下へ進み、「使わない」なら残っている表も消す
        guard currentUserDictionaryCandidateDisplayMode(from: sharedDefaults).usesUserDictionaryCandidates else {
            supplementaryLexiconCandidatesByReading = .empty
            supplementaryMergedCandidatesCacheByKey = [:]
            removePersistedSupplementaryLexiconIndex()
            return
        }

        hydrateSupplementaryLexiconCandidatesFromPersistentCacheIfNeeded()

        // レキシコン生取得は24時間に1回だけ(2623)。requestSupplementaryLexicon の完了直後に
        // Apple フレームワーク内の巨大スパイクで per-process-limit 即死する事象が
        // 2026-08-22 に5連続した(fp26〜30MBでの死。contactsd も同日 per-process-limit 死、
        // 端末再起動でも再発)ため、一度は全面停止(2622)した上で低頻度取得に切り替えた。
        // 仕様: 「ここ24時間以内に iOS のユーザ辞書へ追加した語は反映されない」(ユーザ合意)。
        // タイムスタンプは取得の**前**に書く — 取得が原因で死んでも次の24時間は再試行せず、
        // 死のループにならない(被害は最悪でも24時間に1回)。
        let lexiconFetchStampKey = "supplementaryLexiconLastFetchAttemptAt"
        let lastFetchAttempt = sharedDefaults?.double(forKey: lexiconFetchStampKey) ?? 0
        // ☻ 語のショートカット取り込み予約(3244)があるか一度も取り込んでいなくて、
        // 設定が「使う」のときは 24 時間待たずに取得する。
        let shortcutImportRequested = (sharedDefaults?.bool(
            forKey: KanaKanjiStorageKeys.userDictionaryShortcutImportPending
        ) ?? false)
            || !(sharedDefaults?.bool(forKey: KanaKanjiStorageKeys.userDictionaryShortcutImportedOnce) ?? false)
        let shortcutImportPending = shortcutImportRequested
            && currentUserDictionaryCandidateDisplayMode(from: sharedDefaults).usesUserDictionaryCandidates
        if !shortcutImportPending,
            Date().timeIntervalSince1970 - lastFetchAttempt < 24 * 3600 {
            isRefreshingSupplementaryLexicon = false
            return
        }

        if !force,
            isRefreshingSupplementaryLexicon {
            return
        }

        if !force,
            let lastRefreshAt = supplementaryLexiconLastRefreshAt,
            Date().timeIntervalSince(lastRefreshAt) < 30 {
            return
        }

        // 取得スパイクは数十MB級(2026-08-22 の5連続即死は fp26〜30MB からでも死んだ)。
        // 高水位で走らせると即死の最後の一押しになるため、footprint が低いときだけ取得する。
        // 見送り時はタイムスタンプを書かない=次のセッションで再判定(取得しない限り無害)(2641)
        if let footprintMB = currentFootprintMB(), footprintMB >= 30 {
            isRefreshingSupplementaryLexicon = false
            updateKeyboardDiagnosticsHeartbeat(
                event: "レキシコン取得を見送り(高水位) footprintMB=\(String(format: "%.1f", footprintMB))",
                appendLog: true
            )
            return
        }

        isRefreshingSupplementaryLexicon = true
        sharedDefaults?.set(Date().timeIntervalSince1970, forKey: lexiconFetchStampKey)
        // 予約はタイムスタンプと同じく取得の**前**に消す(取得が原因で死んでも再試行ループにしない)。
        if shortcutImportPending {
            sharedDefaults?.removeObject(forKey: KanaKanjiStorageKeys.userDictionaryShortcutImportPending)
            sharedDefaults?.set(true, forKey: KanaKanjiStorageKeys.userDictionaryShortcutImportedOnce)
        }

        // MEMFORENSICS(時限計測 2641): 取得スパイクの実数(1.2s=取得中、5s=index構築込み)
        MemoryForensics.noteSpikeWindow("レキシコン取得")
        MemoryForensics.noteSpikeWindow("レキシコン取得+5s", delaySeconds: 5.0)

        requestSupplementaryLexicon { [weak self] lexicon in
            guard let self else {
                return
            }

            let lexiconEntries: [(userInput: String, candidate: String)] = lexicon.entries.map { entry in
                (entry.userInput, entry.documentText)
            }

            if shortcutImportPending {
                let shortcutCandidates = KanaKanjiStore.shortcutCandidatesFromUserDictionaryEntries(lexiconEntries)
                let addedCount = self.kanaKanjiStore.prependNewShortcutCandidates(shortcutCandidates)
                DispatchQueue.main.async { [weak self] in
                    self?.updateKeyboardDiagnosticsHeartbeat(
                        event: "ユーザ辞書の☻語をショートカットへ 対象=\(shortcutCandidates.count) 追加=\(addedCount)",
                        appendLog: true
                    )
                }
            }

            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self else {
                    return
                }

                let signature = self.supplementaryLexiconEntriesSignature(fromEntries: lexiconEntries)
                let mergedCandidates: SupplementalVocabCompactStore
                let usedPersistentIndex: Bool

                // 署名が一致するなら hydrate 済みの in-memory の表をそのまま使う
                // (永続キャッシュの読み直しを毎セッション2回→hit時0回に。2415)。
                // in-memory が空のとき(メモリ解放直後 等)だけ永続キャッシュ(mmap のファイル。3318)を読む。
                if self.persistedSupplementaryLexiconIndexSignature() == signature,
                    let hydrated = self.hydratedSupplementaryLexiconCandidatesIfAvailable() {
                    mergedCandidates = hydrated
                    usedPersistentIndex = true
                } else if let cachedCandidates = self.cachedSupplementaryLexiconIndex(signature: signature) {
                    mergedCandidates = cachedCandidates
                    usedPersistentIndex = true
                } else {
                    // 辞書は畳むまでの一時物。畳んだ表をファイルに書き、以後は mmap で開く
                    mergedCandidates = SupplementalVocabCompactStore(
                        dictionary: self.buildSupplementaryLexiconCandidates(fromEntries: lexiconEntries)
                    )
                    usedPersistentIndex = false
                    self.storeSupplementaryLexiconIndex(
                        signature: signature,
                        store: mergedCandidates
                    )
                }

                let entryCount = mergedCandidates.readingCount

                DispatchQueue.main.async {
                    if self.view.window == nil {
                        self.clearSupplementaryLexiconCandidatesForMemoryTrim()
                        return
                    }

                    self.isRefreshingSupplementaryLexicon = false
                    self.supplementaryLexiconLastRefreshAt = Date()

                    let previousCandidates = self.supplementaryLexiconCandidatesByReading
                    self.supplementaryLexiconCandidatesByReading = mergedCandidates
                    self.supplementaryMergedCandidatesCacheByKey = [:]

                    self.updateKeyboardDiagnosticsHeartbeat(
                        event: "補助語彙を更新 entries=\(entryCount) indexCache=\(usedPersistentIndex ? "hit" : "miss")",
                        appendLog: true
                    )

                    if previousCandidates != mergedCandidates {
                        self.refreshKeyboardStateAsync()
                    }
                }
            }
        }
    }

    func clearSupplementaryLexiconCandidatesForMemoryTrim() {
        isRefreshingSupplementaryLexicon = false
        supplementaryLexiconLastRefreshAt = Date()
        supplementaryLexiconCandidatesByReading = .empty
        supplementaryMergedCandidatesCacheByKey = [:]
    }

    func hydrateSupplementaryLexiconCandidatesFromPersistentCacheIfNeeded() {
        guard supplementaryLexiconCandidatesByReading.isEmpty else {
            return
        }

        guard let defaults = sharedDefaults else {
            return
        }
        // 旧版(3317 以前)が UserDefaults に置いた平文の辞書は、見つけたら消すだけ(3318)。表はファイルから作り直す。
        // 端末ごと 1 回の後片づけ。**撤去予定: 2026-10-23 以降**(連絡先の後片づけ 3317 と同時)
        if defaults.object(forKey: SharedDefaultsKeys.supplementaryLexiconIndexCacheByReading) != nil {
            defaults.removeObject(forKey: SharedDefaultsKeys.supplementaryLexiconIndexCacheByReading)
        }

        // 保存されている signature が現行スキーマ(v3 接頭辞付き)でない表は、索引化の論理が古い可能性が
        // あるので破棄する。これがないと旧スキームの表が起動ごとに in-memory へ復活し続ける
        let storedSignature = defaults.string(forKey: SharedDefaultsKeys.supplementaryLexiconIndexSignature) ?? ""
        guard storedSignature.hasPrefix("v3:") else {
            removePersistedSupplementaryLexiconIndex()
            return
        }

        // 連絡先の対応表と同じ App Group のファイル(保護クラス付き・バックアップ除外)を mmap で開く(3318)。
        // 壊れていれば nil(SupplementalVocabCompactStore の検証 3306)→ 次の取得で作り直す
        guard let mapped = ContactCacheCipher.openCompactFile(
            appGroupID: SharedDefaultsKeys.appGroupID,
            fileName: ContactCacheCipher.userLexiconCompactFileName
        ), !mapped.isEmpty else {
            return
        }
        supplementaryLexiconCandidatesByReading = mapped
    }

    func buildSupplementaryLexiconCandidates(
        fromEntries entries: [(userInput: String, candidate: String)]
    ) -> [String: [String]] {
        var dictionary: [String: [String]] = [:]
        var seenCandidatesByReading: [String: Set<String>] = [:]
        let maxCandidatesPerReading = 128

        for entry in entries {
            let candidate = entry.candidate.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !candidate.isEmpty,
                candidate.count <= 64 else {
                continue
            }

            let userInput = entry.userInput.trimmingCharacters(in: .whitespacesAndNewlines)
            var readingKeys = supplementaryReadingKeys(userInput: userInput)

            guard !readingKeys.isEmpty else {
                continue
            }

            var seenReadings = Set<String>()
            readingKeys = readingKeys.filter { seenReadings.insert($0).inserted }

            for reading in readingKeys {
                let existingCount = dictionary[reading]?.count ?? 0

                guard existingCount < maxCandidatesPerReading else {
                    continue
                }

                var seenCandidates = seenCandidatesByReading[reading] ?? Set(dictionary[reading] ?? [])

                guard seenCandidates.insert(candidate).inserted else {
                    seenCandidatesByReading[reading] = seenCandidates
                    continue
                }

                seenCandidatesByReading[reading] = seenCandidates
                var candidates = dictionary[reading] ?? []
                candidates.append(candidate)
                dictionary[reading] = candidates
            }
        }

        return dictionary
    }

    func supplementaryLexiconEntriesSignature(
        fromEntries entries: [(userInput: String, candidate: String)]
    ) -> String {
        var aggregateHash: UInt64 = 1469598103934665603
        var entryCount = 0

        for entry in entries {
            let userInput = entry.userInput.trimmingCharacters(in: .whitespacesAndNewlines)
            let candidate = entry.candidate.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !candidate.isEmpty,
                candidate.count <= 64 else {
                continue
            }

            let pairHash = stableSupplementaryHash(userInput) ^ (stableSupplementaryHash(candidate) &* 1099511628211)
            // 順序非依存の合成(XOR のみ)。UILexicon のエントリ順は取得ごとに保証されず、
            // 旧実装(XOR→乗算の順序依存)では同一内容でも署名が毎回変わり、永続
            // インデックスキャッシュが常に miss →毎セッション再構築(+8〜16MB のスパイク)
            // でメモリ警告の主因になっていた(2413)。
            aggregateHash ^= pairHash &* 1099511628211
            entryCount += 1
        }

        // v3: 署名を順序非依存化。インデックス化ロジックを変更したら必ずバージョンを上げて
        // キャッシュ無効化する。
        return "v3:\(entryCount):\(String(aggregateHash, radix: 16))"
    }

    func stableSupplementaryHash(_ value: String) -> UInt64 {
        var hash: UInt64 = 1469598103934665603

        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }

        return hash
    }

    // 永続キャッシュの署名だけを読む(辞書本体のデコードなし)。
    func persistedSupplementaryLexiconIndexSignature() -> String? {
        sharedDefaults?
            .string(forKey: SharedDefaultsKeys.supplementaryLexiconIndexSignature)
    }

    // hydrate 済みの in-memory 辞書(空なら nil)。utility キューから読むため main 経由で取る。
    // main から呼ばれたときは同期待ちせず直接読む(3312)。DispatchQueue.main.sync を main で呼ぶと
    // デッドロックする。今の呼び出し元は utility キューだけだが、将来の呼び出しに備える
    func hydratedSupplementaryLexiconCandidatesIfAvailable() -> SupplementalVocabCompactStore? {
        let read: () -> SupplementalVocabCompactStore? = {
            self.supplementaryLexiconCandidatesByReading.isEmpty
                ? nil
                : self.supplementaryLexiconCandidatesByReading
        }
        if Thread.isMainThread {
            return read()
        }
        var result: SupplementalVocabCompactStore?
        DispatchQueue.main.sync {
            result = read()
        }
        return result
    }

    // 署名が一致するときだけ、永続キャッシュ(mmap のファイル)を開く(3318)
    func cachedSupplementaryLexiconIndex(signature: String) -> SupplementalVocabCompactStore? {
        guard let defaults = sharedDefaults,
            defaults.string(forKey: SharedDefaultsKeys.supplementaryLexiconIndexSignature) == signature,
            let mapped = ContactCacheCipher.openCompactFile(
                appGroupID: SharedDefaultsKeys.appGroupID,
                fileName: ContactCacheCipher.userLexiconCompactFileName
            ),
            !mapped.isEmpty else {
            return nil
        }

        return mapped
    }

    // 畳んだ表を App Group のファイルに書く(3318。保護クラス付き・バックアップ除外・atomic。連絡先の対応表と同じ)。
    // 署名(ハッシュ文字列。語の中身は含まない)だけ UserDefaults に残す。書けなければ署名も残さない
    // (署名だけ新しくて表が古い、という不整合を作らない)
    func storeSupplementaryLexiconIndex(
        signature: String,
        store: SupplementalVocabCompactStore
    ) {
        guard let defaults = sharedDefaults else {
            return
        }
        guard ContactCacheCipher.writeCompactFile(
            store,
            appGroupID: SharedDefaultsKeys.appGroupID,
            fileName: ContactCacheCipher.userLexiconCompactFileName
        ) else {
            defaults.removeObject(forKey: SharedDefaultsKeys.supplementaryLexiconIndexSignature)
            return
        }
        defaults.set(signature, forKey: SharedDefaultsKeys.supplementaryLexiconIndexSignature)
    }

    // 共有領域に残した UILexicon の表(ファイルと署名。旧版の平文キーも)を消す(3305/3318)。
    // 設定を「使わない」にしたときに呼ぶ(アプリ側も同じものを消す)
    func removePersistedSupplementaryLexiconIndex() {
        guard let defaults = sharedDefaults else {
            return
        }
        ContactCacheCipher.removeCompactFile(
            appGroupID: SharedDefaultsKeys.appGroupID,
            fileName: ContactCacheCipher.userLexiconCompactFileName
        )
        defaults.removeObject(forKey: SharedDefaultsKeys.supplementaryLexiconIndexCacheByReading)
        defaults.removeObject(forKey: SharedDefaultsKeys.supplementaryLexiconIndexSignature)
    }

    func refreshContactCandidatesIfNeeded(force: Bool) {
        guard Self.isSupplementaryExternalCandidatesEnabled else {
            contactCandidatesByReading = .empty
            supplementaryMergedCandidatesCacheByKey = [:]
            return
        }

        let displayMode = currentContactCandidateDisplayModeFromSharedDefaults()

        guard displayMode.usesContacts else {
            clearContactCandidatesIfNeeded(refreshKeyboardState: true)
            return
        }

        // 読込はプロセス共有(2655)なので、force でも走行中なら合流する(設定変更通知は
        // 生存個体すべてに届き、以前は個体数ぶんの読込が同時に走っていた)。
        if isRefreshingContactCandidates {
            return
        }

        if !force,
            let lastRefreshAt = contactCandidatesLastRefreshAt,
            Date().timeIntervalSince(lastRefreshAt) < 30 {
            return
        }

        isRefreshingContactCandidates = true
        loadCachedContactCandidatesInBackground { [weak self] cachedCandidates in
            // 共有フラグは読込を始めた個体が消えていても必ず戻す(戻さないと全個体の
            // 再読込が永久に止まる)。
            KeyboardViewController.sharedIsRefreshingContactCandidates = false
            guard let self else {
                return
            }

            let currentDisplayMode = self.currentContactCandidateDisplayModeFromSharedDefaults()

            guard currentDisplayMode.usesContacts else {
                self.clearContactCandidatesIfNeeded(refreshKeyboardState: true)
                return
            }

            if !cachedCandidates.isEmpty {
                self.isRefreshingContactCandidates = false
                self.contactCandidatesLastRefreshAt = Date()

                let previous = self.contactCandidatesByReading
                self.contactCandidatesByReading = cachedCandidates
                self.supplementaryMergedCandidatesCacheByKey = [:]

                if previous != self.contactCandidatesByReading {
                    self.refreshKeyboardStateAsync()
                }
                return
            }

            // ★拡張プロセスからの Contacts 接触を全面停止(2624)。レキシコン停止(2622)後も
            // per-process-limit 即死が再発し、直前指紋はやはり Contacts 初期化(AB通知登録の
            // 0.45秒後に死)だった。CNContactStore.authorizationStatus / enumerateContacts とも
            // Apple フレームワーク内の巨大スパイクを誘発しうるため、拡張では一切呼ばない。
            // 連絡先候補はコンテナーアプリが書く共有キャッシュ(cachedContactCandidates…)専用。
            // キャッシュが空のときは候補なしで妥協する(App を開けば更新される)。
            self.isRefreshingContactCandidates = false
            self.contactCandidatesLastRefreshAt = Date()
        }
    }

    func loadCachedContactCandidatesInBackground(
        completion: @escaping (SupplementalVocabCompactStore) -> Void
    ) {
        // 復号済みの印と共有表は main で読んでから背景へ渡す(共有状態のアクセスは main に限る)
        let knownStamp = Self.sharedContactCandidatesStamp
        let sharedStore = Self.sharedContactCandidatesByReading
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else {
                // 個体が消えても completion は必ず呼ぶ(共有の読込中フラグを戻すため。2655)
                DispatchQueue.main.async {
                    completion(.empty)
                }
                return
            }
            // 印(コンテナーが畳んだ封緘版を書くたびに更新する UUID)が復号済みのものと同じなら、blob を読まず
            // 復号もしない(3080)。個体が作られるたびの force 読込で同じ blob を復号し直し、約 1MB の Data の
            // 確保が malloc の領域を 1 つ開けていた(実機 48→52)。印が無い(コンテナー未更新)なら従来どおり復号
            let stamp = self.sharedDefaults?.string(
                forKey: SharedDefaultsKeys.contactCandidatesByReadingCacheCompactSealedStamp
            )
            if let stamp, stamp == knownStamp, !sharedStore.isEmpty {
                DispatchQueue.main.async {
                    completion(sharedStore)
                }
                return
            }

            // 測定(2725): 共有 defaults の連絡先キャッシュ(約1.6万読み)を毎 bootstrap で復号している。
            // 8/30 10:43 Safari の警告は bootstrap 直後 1.2 秒で used +4.4MB(latin/補助語彙は未ロード)で、
            // この復号(NSDictionary→Swift 辞書のブリッジ二重化)が有力候補。復号前後を必ず記録する
            let decodeSnapshot = MemoryForensics.snapshot()
            // mmap のファイル(3260)があれば復号もヒープ確保もしない
            if let mapped = ContactCacheCipher.openCompactFile(appGroupID: SharedDefaultsKeys.appGroupID) {
                MemoryForensics.noteSyncDelta(
                    "連絡先キャッシュ mmap readings=\(mapped.readingCount)",
                    since: decodeSnapshot,
                    minDeltaMB: -1
                )
                DispatchQueue.main.async {
                    KeyboardViewController.sharedContactCandidatesStamp = stamp
                    completion(mapped)
                }
                return
            }
            // ファイルが無ければ空(3317)。旧版の保存物(封緘した畳んだ版 3020 / 封緘・平文の JSON 辞書)を
            // 読むフォールバックは外した。アプリが次回の同期でファイル方式へ置き換えるので、残っていても
            // 「アプリを開くまで連絡先候補が出ない」だけ。旧形式を持つのは TestFlight の 7 人の端末だけで、
            // App Store には旧形式の版が出ていない(セキュリティー検査 2026-10-02)
            MemoryForensics.noteSyncDelta("連絡先キャッシュ なし", since: decodeSnapshot, minDeltaMB: -1)
            DispatchQueue.main.async {
                completion(.empty)
            }
        }
    }

    func clearContactCandidatesIfNeeded(refreshKeyboardState: Bool) {
        let hadContactCandidates = !contactCandidatesByReading.isEmpty
        isRefreshingContactCandidates = false
        contactCandidatesLastRefreshAt = Date()
        contactCandidatesByReading = .empty
        supplementaryMergedCandidatesCacheByKey = [:]

        if refreshKeyboardState,
            hadContactCandidates {
            refreshKeyboardStateAsync()
        }
    }




    func supplementaryReadingKeys(userInput: String) -> [String] {
        var readingKeys: [String] = []

        let normalizedUserInput = KanaTextNormalizer.normalizedReading(userInput)
        if !normalizedUserInput.isEmpty {
            readingKeys.append(normalizedUserInput)
        }

        let tokenSource = userInput.replacingOccurrences(of: "・", with: " ")
        let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        let userInputTokens = tokenSource
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }

        for token in userInputTokens {
            let normalizedToken = KanaTextNormalizer.normalizedReading(token)

            if !normalizedToken.isEmpty {
                readingKeys.append(normalizedToken)
            }
        }

        // 候補側からカナ部分を抽出してキー化することは行わない。
        // (例: ワイン検定 から「わいん」を派生キーにすると「わいん」入力時に
        //  ワイン検定 が候補に紛れる、という UX 上の混入を避ける。)
        // 部分プレフィックスマッチが必要になった場合は、別のサジェスト機構として実装する。

        return readingKeys
    }

    // 合流器の連絡先窓(4番目前出し)用: 連絡先由来の候補だけを返す。設定オフなら空
    func contactCandidatesForMergeWindow(reading: String) -> [String] {
        guard Self.isSupplementaryExternalCandidatesEnabled else {
            return []
        }

        let normalizedReading = KanaTextNormalizer.normalizedReading(reading)

        guard !normalizedReading.isEmpty,
            currentContactCandidateDisplayMode(from: sharedDefaults).usesContacts else {
            return []
        }

        return contactCandidatesByReading.candidates(for: normalizedReading)
    }

    func supplementaryLexiconCandidates(for reading: String) -> [String] {
        guard Self.isSupplementaryExternalCandidatesEnabled else {
            return []
        }

        let normalizedReading = KanaTextNormalizer.normalizedReading(reading)

        guard !normalizedReading.isEmpty else {
            return []
        }

        let defaults = sharedDefaults
        let usesContacts = currentContactCandidateDisplayMode(from: defaults).usesContacts
        let usesUserDictionaryCandidates = currentUserDictionaryCandidateDisplayMode(from: defaults)
            .usesUserDictionaryCandidates
        let showsEmojiCandidates = currentEmojiCandidateDisplayEnabled(from: defaults)
        let showsKaomojiCandidates = currentKaomojiCandidateDisplayEnabled(from: defaults)

        let cacheKey = "\(normalizedReading)|c:\(usesContacts ? 1 : 0)|u:\(usesUserDictionaryCandidates ? 1 : 0)|e:\(showsEmojiCandidates ? 1 : 0)|k:\(showsKaomojiCandidates ? 1 : 0)"

        if let cachedCandidates = supplementaryMergedCandidatesCacheByKey[cacheKey] {
            return cachedCandidates
        }

        let contactCandidates: [String]

        if usesContacts {
            contactCandidates = contactCandidatesByReading.candidates(for: normalizedReading)
        } else {
            contactCandidates = []
        }

        let lexiconCandidates: [String]

        if usesUserDictionaryCandidates {
            lexiconCandidates = supplementaryLexiconCandidatesByReading.candidates(for: normalizedReading)
        } else {
            lexiconCandidates = []
        }

        let emojiCandidates: [String]

        if showsEmojiCandidates {
            emojiCandidates = Self.emojiReadingCandidatesByReading[normalizedReading] ?? []
        } else {
            emojiCandidates = []
        }

        let kaomojiCandidates: [String]

        if showsKaomojiCandidates {
            let catalogCandidates = KaomojiCatalog.entries(forReading: normalizedReading)
            let legacyCandidates = Self.kaomojiReadingCandidatesByReading[normalizedReading] ?? []

            if catalogCandidates.isEmpty {
                kaomojiCandidates = legacyCandidates
            } else if legacyCandidates.isEmpty {
                kaomojiCandidates = catalogCandidates
            } else {
                var mergedKaomojiCandidates = catalogCandidates
                var seenKaomojiCandidates = Set(catalogCandidates)

                for candidate in legacyCandidates where seenKaomojiCandidates.insert(candidate).inserted {
                    mergedKaomojiCandidates.append(candidate)
                }

                kaomojiCandidates = mergedKaomojiCandidates
            }
        } else {
            kaomojiCandidates = []
        }

        if contactCandidates.isEmpty,
            lexiconCandidates.isEmpty,
            emojiCandidates.isEmpty {
            supplementaryMergedCandidatesCacheByKey[cacheKey] = kaomojiCandidates

            if supplementaryMergedCandidatesCacheByKey.count > Self.maximumSupplementaryMergedCandidateCacheEntries {
                supplementaryMergedCandidatesCacheByKey.removeAll(keepingCapacity: true)
            }

            return kaomojiCandidates
        }

        var mergedCandidates: [String] = []
        var seenCandidates = Set<String>()

        for candidate in contactCandidates + lexiconCandidates + emojiCandidates + kaomojiCandidates {
            if seenCandidates.insert(candidate).inserted {
                mergedCandidates.append(candidate)
            }
        }

        supplementaryMergedCandidatesCacheByKey[cacheKey] = mergedCandidates

        if supplementaryMergedCandidatesCacheByKey.count > Self.maximumSupplementaryMergedCandidateCacheEntries {
            supplementaryMergedCandidatesCacheByKey.removeAll(keepingCapacity: true)
        }

        return mergedCandidates
    }
}
