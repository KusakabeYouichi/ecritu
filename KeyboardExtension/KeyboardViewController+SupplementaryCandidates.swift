import SwiftUI
import UIKit
import CoreFoundation
import Darwin
import Contacts

extension KeyboardViewController {
    func refreshSupplementaryLexiconIfNeeded(force: Bool) {
        guard Self.isSupplementaryExternalCandidatesEnabled else {
            supplementaryLexiconCandidatesByReading = [:]
            supplementaryMergedCandidatesCacheByKey = [:]
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
        if Date().timeIntervalSince1970 - lastFetchAttempt < 24 * 3600 {
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

            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self else {
                    return
                }

                let signature = self.supplementaryLexiconEntriesSignature(fromEntries: lexiconEntries)
                let mergedCandidates: [String: [String]]
                let usedPersistentIndex: Bool

                // 署名が一致するなら hydrate 済みの in-memory 辞書をそのまま使う
                // (defaults からの辞書デコードを毎セッション2回→hit時0回に。2415)。
                // in-memory が空のとき(メモリ解放直後 等)だけ永続キャッシュを読む。
                if self.persistedSupplementaryLexiconIndexSignature() == signature,
                    let hydrated = self.hydratedSupplementaryLexiconCandidatesIfAvailable() {
                    mergedCandidates = hydrated
                    usedPersistentIndex = true
                } else if let cachedCandidates = self.cachedSupplementaryLexiconIndex(signature: signature) {
                    mergedCandidates = cachedCandidates
                    usedPersistentIndex = true
                } else {
                    mergedCandidates = self.buildSupplementaryLexiconCandidates(
                        fromEntries: lexiconEntries
                    )
                    usedPersistentIndex = false
                    self.storeSupplementaryLexiconIndex(
                        signature: signature,
                        dictionary: mergedCandidates
                    )
                }

                let entryCount = mergedCandidates.values.reduce(0) { partialResult, candidates in
                    partialResult + candidates.count
                }

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
        supplementaryLexiconCandidatesByReading = [:]
        supplementaryMergedCandidatesCacheByKey = [:]
    }

    func hydrateSupplementaryLexiconCandidatesFromPersistentCacheIfNeeded() {
        guard supplementaryLexiconCandidatesByReading.isEmpty else {
            return
        }

        guard let defaults = UserDefaults(suiteName: SharedDefaultsKeys.appGroupID),
            let cachedDictionary = defaults.dictionary(forKey: SharedDefaultsKeys.supplementaryLexiconIndexCacheByReading)
                as? [String: [String]],
            !cachedDictionary.isEmpty else {
            return
        }

        // 保存されている signature が現行スキーマ(v2 接頭辞付き)でないキャッシュは
        // インデックス化ロジックが古い可能性があるので破棄する。これがないと、
        // 旧スキームで生成された「候補側カナ抽出キー」混入キャッシュが
        // 起動毎に in-memory へ復活し続けてしまう。
        let storedSignature = defaults.string(forKey: SharedDefaultsKeys.supplementaryLexiconIndexSignature) ?? ""
        guard storedSignature.hasPrefix("v3:") else {
            defaults.removeObject(forKey: SharedDefaultsKeys.supplementaryLexiconIndexCacheByReading)
            defaults.removeObject(forKey: SharedDefaultsKeys.supplementaryLexiconIndexSignature)
            return
        }

        supplementaryLexiconCandidatesByReading = cachedDictionary
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
            var readingKeys = supplementaryReadingKeys(userInput: userInput, candidate: candidate)

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
        UserDefaults(suiteName: SharedDefaultsKeys.appGroupID)?
            .string(forKey: SharedDefaultsKeys.supplementaryLexiconIndexSignature)
    }

    // hydrate 済みの in-memory 辞書(空なら nil)。utility キューから読むため main 経由で取る。
    func hydratedSupplementaryLexiconCandidatesIfAvailable() -> [String: [String]]? {
        var result: [String: [String]]?
        DispatchQueue.main.sync {
            result = self.supplementaryLexiconCandidatesByReading.isEmpty
                ? nil
                : self.supplementaryLexiconCandidatesByReading
        }
        return result
    }

    func cachedSupplementaryLexiconIndex(signature: String) -> [String: [String]]? {
        guard let defaults = UserDefaults(suiteName: SharedDefaultsKeys.appGroupID),
            defaults.string(forKey: SharedDefaultsKeys.supplementaryLexiconIndexSignature) == signature,
            let dictionary = defaults.dictionary(forKey: SharedDefaultsKeys.supplementaryLexiconIndexCacheByReading)
                as? [String: [String]],
            !dictionary.isEmpty else {
            return nil
        }

        return dictionary
    }

    func storeSupplementaryLexiconIndex(
        signature: String,
        dictionary: [String: [String]]
    ) {
        guard let defaults = UserDefaults(suiteName: SharedDefaultsKeys.appGroupID) else {
            return
        }

        defaults.set(signature, forKey: SharedDefaultsKeys.supplementaryLexiconIndexSignature)
        defaults.set(dictionary, forKey: SharedDefaultsKeys.supplementaryLexiconIndexCacheByReading)
    }

    func refreshContactCandidatesIfNeeded(force: Bool) {
        guard Self.isSupplementaryExternalCandidatesEnabled else {
            contactCandidatesByReading = [:]
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

                if previous != cachedCandidates {
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
        completion: @escaping ([String: [String]]) -> Void
    ) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else {
                // 個体が消えても completion は必ず呼ぶ(共有の読込中フラグを戻すため。2655)
                DispatchQueue.main.async {
                    completion([:])
                }
                return
            }

            let cachedCandidates = self.limitContactCandidateDictionary(
                self.cachedContactCandidatesFromSharedDefaults()
            )

            DispatchQueue.main.async {
                completion(cachedCandidates)
            }
        }
    }

    func cachedContactCandidatesFromSharedDefaults() -> [String: [String]] {
        guard let sharedDefaults = UserDefaults(suiteName: SharedDefaultsKeys.appGroupID),
            let dictionary = sharedDefaults.dictionary(forKey: SharedDefaultsKeys.contactCandidatesByReadingCache)
                as? [String: [String]] else {
            return [:]
        }

        return dictionary
    }

    func clearContactCandidatesIfNeeded(refreshKeyboardState: Bool) {
        let hadContactCandidates = !contactCandidatesByReading.isEmpty
        isRefreshingContactCandidates = false
        contactCandidatesLastRefreshAt = Date()
        contactCandidatesByReading = [:]
        supplementaryMergedCandidatesCacheByKey = [:]

        if refreshKeyboardState,
            hadContactCandidates {
            refreshKeyboardStateAsync()
        }
    }

    func loadContactCandidates(displayMode: ContactCandidateDisplayMode) {
        isRefreshingContactCandidates = true

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else {
                return
            }

            let store = CNContactStore()
            let request = CNContactFetchRequest(keysToFetch: [
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactMiddleNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactNicknameKey as CNKeyDescriptor,
                CNContactOrganizationNameKey as CNKeyDescriptor,
                CNContactPhoneticOrganizationNameKey as CNKeyDescriptor,
                CNContactPhoneticGivenNameKey as CNKeyDescriptor,
                CNContactPhoneticMiddleNameKey as CNKeyDescriptor,
                CNContactPhoneticFamilyNameKey as CNKeyDescriptor
            ])

            var dictionary: [String: [String]] = [:]
            var totalCandidateCount = 0
            var didReachLimit = false

            do {
                try store.enumerateContacts(with: request) { contact, stop in
                    self.appendContactCandidates(
                        from: contact,
                        displayMode: displayMode,
                        to: &dictionary,
                        totalCandidateCount: &totalCandidateCount
                    )

                    if self.hasReachedContactCandidateBuildLimit(
                        readingCount: dictionary.count,
                        totalCandidateCount: totalCandidateCount
                    ) {
                        didReachLimit = true
                        stop.pointee = true
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.clearContactCandidatesIfNeeded(refreshKeyboardState: true)
                }
                return
            }

            DispatchQueue.main.async {
                if self.view.window == nil {
                    self.clearContactCandidatesIfNeeded(refreshKeyboardState: false)
                    return
                }

                guard self.currentContactCandidateDisplayModeFromSharedDefaults() == displayMode else {
                    self.isRefreshingContactCandidates = false
                    self.refreshContactCandidatesIfNeeded(force: true)
                    return
                }

                self.isRefreshingContactCandidates = false
                self.contactCandidatesLastRefreshAt = Date()

                let previous = self.contactCandidatesByReading
                self.contactCandidatesByReading = dictionary
                self.supplementaryMergedCandidatesCacheByKey = [:]

                if didReachLimit {
                    self.updateKeyboardDiagnosticsHeartbeat(
                        event: "連絡先候補を上限で打ち切り readings=\(dictionary.count) entries=\(totalCandidateCount)",
                        appendLog: true
                    )
                }

                if previous != dictionary {
                    self.refreshKeyboardStateAsync()
                }
            }
        }
    }

    func appendContactCandidates(
        from contact: CNContact,
        displayMode: ContactCandidateDisplayMode,
        to dictionary: inout [String: [String]],
        totalCandidateCount: inout Int
    ) {
        let familyName = contact.familyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let givenName = contact.givenName.trimmingCharacters(in: .whitespacesAndNewlines)
        let middleName = contact.middleName.trimmingCharacters(in: .whitespacesAndNewlines)
        let nickname = contact.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let organizationName = contact.organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phoneticOrganizationName = contact.phoneticOrganizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullName = [familyName, givenName, middleName].filter { !$0.isEmpty }.joined()

        let phoneticFamily = contact.phoneticFamilyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phoneticGiven = contact.phoneticGivenName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phoneticMiddle = contact.phoneticMiddleName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullNamePhonetic = [phoneticFamily, phoneticGiven, phoneticMiddle].joined()
        let includeFullNameForNameMatches = displayMode.includesFullNameForNameMatches

        let readingCandidates: [(String, [String])] = [
            (
                phoneticFamily,
                contactNameCandidates(
                    primaryName: familyName,
                    fullName: fullName,
                    includeFullName: includeFullNameForNameMatches
                )
            ),
            (
                phoneticGiven,
                contactNameCandidates(
                    primaryName: givenName,
                    fullName: fullName,
                    includeFullName: includeFullNameForNameMatches
                )
            ),
            (
                phoneticMiddle,
                contactNameCandidates(
                    primaryName: middleName,
                    fullName: fullName,
                    includeFullName: includeFullNameForNameMatches
                )
            ),
            (fullNamePhonetic, [fullName]),
            (
                familyName,
                contactNameCandidates(
                    primaryName: familyName,
                    fullName: fullName,
                    includeFullName: includeFullNameForNameMatches
                )
            ),
            (
                givenName,
                contactNameCandidates(
                    primaryName: givenName,
                    fullName: fullName,
                    includeFullName: includeFullNameForNameMatches
                )
            ),
            (
                middleName,
                contactNameCandidates(
                    primaryName: middleName,
                    fullName: fullName,
                    includeFullName: includeFullNameForNameMatches
                )
            ),
            (fullName, [fullName]),
            (nickname, [nickname])
        ]

        for (readingText, candidates) in readingCandidates {
            appendCandidates(
                candidates,
                forReadingText: readingText,
                to: &dictionary,
                totalCandidateCount: &totalCandidateCount
            )
        }

        if !organizationName.isEmpty {
            let organizationReadingKeys = companyReadingKeys(
                organizationName: organizationName,
                phoneticOrganizationName: phoneticOrganizationName
            )

            for readingKey in organizationReadingKeys {
                appendCandidates(
                    [organizationName],
                    forReadingText: readingKey,
                    to: &dictionary,
                    totalCandidateCount: &totalCandidateCount
                )
            }
        }
    }

    func companyReadingKeys(
        organizationName: String,
        phoneticOrganizationName: String
    ) -> [String] {
        var keys: [String] = []
        var seen = Set<String>()

        func appendKey(_ reading: String) {
            let normalized = KanaTextNormalizer.normalizedReading(reading)

            guard !normalized.isEmpty,
                seen.insert(normalized).inserted else {
                return
            }

            keys.append(normalized)

            let trimmed = trimmingOrganizationPrefix(from: normalized)

            guard !trimmed.isEmpty,
                trimmed != normalized,
                seen.insert(trimmed).inserted else {
                return
            }

            keys.append(trimmed)
        }

        if shouldUseOrganizationNameReadingFallback(organizationName) {
            appendKey(organizationName)
        }
        appendKey(phoneticOrganizationName)

        return keys
    }

    func shouldUseOrganizationNameReadingFallback(_ organizationName: String) -> Bool {
        let source = organizationName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !source.isEmpty else {
            return false
        }

        var hasKana = false

        for scalar in source.precomposedStringWithCanonicalMapping.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                continue
            }

            if scalar.value == 0x30FB || scalar.value == 0xFF65 {
                continue
            }

            let normalized = KanaTextNormalizer.normalizedReading(String(scalar))

            if !normalized.isEmpty {
                hasKana = true
                continue
            }

            return false
        }

        return hasKana
    }

    func trimmingOrganizationPrefix(from normalizedReading: String) -> String {
        var reading = normalizedReading

        while true {
            var matched = false

            for prefix in Self.organizationPrefixReadingsToTrim where reading.hasPrefix(prefix) {
                reading = String(reading.dropFirst(prefix.count))
                matched = true
                break
            }

            guard matched else {
                return reading
            }
        }
    }

    func contactNameCandidates(
        primaryName: String,
        fullName: String,
        includeFullName: Bool
    ) -> [String] {
        guard !primaryName.isEmpty else {
            return []
        }

        guard includeFullName,
            !fullName.isEmpty,
            fullName != primaryName else {
            return [primaryName]
        }

        return [primaryName, fullName]
    }

    func appendCandidates(
        _ candidates: [String],
        forReadingText readingText: String,
        to dictionary: inout [String: [String]],
        totalCandidateCount: inout Int
    ) {
        let normalizedReading = KanaTextNormalizer.normalizedReading(readingText)

        guard !normalizedReading.isEmpty else {
            return
        }

        if dictionary[normalizedReading] == nil,
            dictionary.count >= Self.maximumContactCandidateReadings {
            return
        }

        guard totalCandidateCount < Self.maximumContactCandidateTotalEntries else {
            return
        }

        var existingCandidates = dictionary[normalizedReading] ?? []
        var existingCandidateSet = Set(existingCandidates)

        for candidate in candidates {
            if existingCandidates.count >= Self.maximumContactCandidatesPerReading
                || totalCandidateCount >= Self.maximumContactCandidateTotalEntries {
                break
            }

            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmed.isEmpty,
                existingCandidateSet.insert(trimmed).inserted else {
                continue
            }

            existingCandidates.append(trimmed)
            totalCandidateCount += 1
        }

        if !existingCandidates.isEmpty {
            dictionary[normalizedReading] = existingCandidates
        }
    }

    func hasReachedContactCandidateBuildLimit(
        readingCount: Int,
        totalCandidateCount: Int
    ) -> Bool {
        readingCount >= Self.maximumContactCandidateReadings
            || totalCandidateCount >= Self.maximumContactCandidateTotalEntries
    }

    func limitContactCandidateDictionary(
        _ source: [String: [String]]
    ) -> [String: [String]] {
        guard !source.isEmpty else {
            return [:]
        }

        var limited: [String: [String]] = [:]
        var totalCandidateCount = 0

        for (reading, candidates) in source {
            if hasReachedContactCandidateBuildLimit(
                readingCount: limited.count,
                totalCandidateCount: totalCandidateCount
            ) {
                break
            }

            appendCandidates(
                candidates,
                forReadingText: reading,
                to: &limited,
                totalCandidateCount: &totalCandidateCount
            )
        }

        return limited
    }

    func supplementaryReadingKeys(userInput: String, candidate: String) -> [String] {
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
            contactCandidates = contactCandidatesByReading[normalizedReading] ?? []
        } else {
            contactCandidates = []
        }

        let lexiconCandidates: [String]

        if usesUserDictionaryCandidates {
            lexiconCandidates = supplementaryLexiconCandidatesByReading[normalizedReading] ?? []
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
