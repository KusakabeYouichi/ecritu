import Foundation

// 連絡先キャッシュ(氏名・読みの対応表)の保存と読み出し。App Group のファイルに置き、保護は iOS の
// ファイル保護(completeUntilFirstUserAuthentication)に委ね、バックアップ対象外にする(3260)。
// アプリ自身は暗号化を行なわない。2026-08-31〜3259 の自前 AES-GCM 封緘+Keychain 鍵はやめ、旧版の
// 封緘物を読む移行は 3317、旧版の保存物と Keychain 鍵の後片づけは 3375 で撤去した。
// 以前はアプリ側(ContentView+Bootstrap.swift)と拡張側(KanaKanjiTypes.swift)に同じ enum を
// 2 重に持っていた。両ターゲットに同梱する 1 ファイルへ集約(2805 リファクタ)
enum ContactCacheCipher {
    // 連絡先キャッシュの上限(拡張の常駐量を抑えるための頭打ち)。以前は拡張側だけが持ち、
    // 復号した辞書を拡張で切り詰めていた。畳んだ表で渡す方式(3020)ではコンテナー側が
    // 同じ規則で切ってから畳む必要があるため、両ターゲットが使うこのファイルへ移した
    enum Limits {
        static let maximumReadings = 4096
        static let maximumTotalEntries = 16384
        static let maximumCandidatesPerReading = 48
    }

    // 読みの正規化・前後空白の除去・重複排除・上限の適用。読みの昇順で切るので、
    // 上限に掛かったときにどれが落ちるかが決まる(以前は辞書の反復順で不定だった)
    static func limited(_ source: [String: [String]]) -> [String: [String]] {
        guard !source.isEmpty else {
            return [:]
        }
        var limited: [String: [String]] = [:]
        var totalCandidateCount = 0
        for reading in source.keys.sorted() {
            if limited.count >= Limits.maximumReadings
                || totalCandidateCount >= Limits.maximumTotalEntries {
                break
            }
            let normalizedReading = KanaTextNormalizer.normalizedReading(reading)
            guard !normalizedReading.isEmpty else {
                continue
            }
            if limited[normalizedReading] == nil, limited.count >= Limits.maximumReadings {
                continue
            }
            var candidates = limited[normalizedReading] ?? []
            var seen = Set(candidates)
            for candidate in source[reading] ?? [] {
                if candidates.count >= Limits.maximumCandidatesPerReading
                    || totalCandidateCount >= Limits.maximumTotalEntries {
                    break
                }
                let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, seen.insert(trimmed).inserted else {
                    continue
                }
                candidates.append(trimmed)
                totalCandidateCount += 1
            }
            if !candidates.isEmpty {
                limited[normalizedReading] = candidates
            }
        }
        return limited
    }

    // 畳んだ表のファイル(3260)。自前の AES 封緘(seal/open/sealCompact/openCompact と Keychain の鍵作成)はやめ、
    // このファイルだけにした。封緘系の読み書きは 3317 で撤去した。
    // 封緘版は拡張が開くたびに復号でヒープへ展開し、捨てて作り直すたびに
    // malloc の新しい領域(4MB)を確保して footprint のラチェットの引き金になっていた(実機 2026-09-27 03:25 の警告)。
    // iOS のファイル保護(初回ロック解除まで読めない暗号化)を掛けた App Group のファイルにし、拡張は
    // mmap(mappedIfSafe)で開く。ページは読み取り専用のクリーンページで footprint にほぼ数えられず、
    // 捨てても開き直してもヒープを確保しない。App Group に入れるのは écritu 本体と拡張だけ。
    // バックアップ対象外(連絡先から作り直せる派生データ)
    static let compactFileName = "ContactCandidatesCompact.eccs"

    // iOS のユーザ辞書(UILexicon)から拡張が作る 読み→候補 の表も同じ方式・同じ場所に置く(3318)。以前は App Group の
    // UserDefaults に平文の辞書で置き、バックアップにも入っていた(セキュリティー検査 2026-10-02)。
    // fileName 引数の既定は連絡先(呼び出し側を変えないため)
    static let userLexiconCompactFileName = "UserLexiconCompact.eccs"

    static func compactFileURL(appGroupID: String, fileName: String = compactFileName) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    @discardableResult
    static func writeCompactFile(
        _ store: SupplementalVocabCompactStore,
        appGroupID: String,
        fileName: String = compactFileName
    ) -> Bool {
        guard var url = compactFileURL(appGroupID: appGroupID, fileName: fileName) else {
            return false
        }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try store.serializedData().write(
                to: url,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
            return true
        } catch {
            return false
        }
    }

    static func openCompactFile(appGroupID: String, fileName: String = compactFileName) -> SupplementalVocabCompactStore? {
        guard let url = compactFileURL(appGroupID: appGroupID, fileName: fileName),
            let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return nil
        }
        return SupplementalVocabCompactStore(serialized: data)
    }

    static func removeCompactFile(appGroupID: String, fileName: String = compactFileName) {
        guard let url = compactFileURL(appGroupID: appGroupID, fileName: fileName) else {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }

    static func compactFileExists(appGroupID: String, fileName: String = compactFileName) -> Bool {
        guard let url = compactFileURL(appGroupID: appGroupID, fileName: fileName) else {
            return false
        }
        return FileManager.default.fileExists(atPath: url.path)
    }
}
