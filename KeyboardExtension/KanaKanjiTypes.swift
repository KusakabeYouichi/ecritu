import CryptoKit
import Foundation
import Security


enum KanaKanjiStorageKeys {
    static let userDictionary = "ÉcrituAjoutVocab"
    static let learnedDictionary = "kanaKanjiLearnedVocabulary"
    static let shortcutVocabulary = "ÉcrituShortcutVocab"
    static let suppressionVocabulary = "ÉcrituSuppr_Vocab"
    static let learningScores = "kanaKanjiLearningScores"
    static let systemDictionarySQLiteFilename = "kana_kanji_dictionary.sqlite"
    static let systemDictionaryFilename = "ÉcrituPremierVocab.json"
    static let supplementalSystemDictionaryFilename = "ÉcrituSecondVocab.json"
    // 補助語彙から前計算した欧文サジェスト索引(tools/build_latin_suggestion_supplemental.swift)
    static let latinSuggestionSupplementalFilename = "LatinSuggestionSupplemental.txt"
    static let systemCandidateSourcesFilename = "kana_kanji_candidate_sources.json"
    static let inflectionDictionaryFilename = "kana_kanji_inflection_dictionary.json"
    static let initialUserDictionaryResourceName = "InitialAjoutVocabMigration"
    // 変換対策の単語追加(misc)。変換には注入するが、コンテナアプリの「追加語彙」には表示しない。
    static let initialMiscDictionaryResourceName = "InitialMiscVocabMigration"
    static let initialShortcutVocabularyResourceName = "InitialShortcutVocabMigration"
    // 変換対策の抑制(poubelle と対等に効くが、コンテナアプリの「抑制語彙」には表示しない)。
    // アプリ移行(ÉcrituSuppr_Vocab)を経由せず、キーボードがバンドルから直接読む。
    static let initialSuppressionHiddenResourceName = "InitialSupprHiddenVocabMigration"
}

// カタカナ強調表記/交ぜ書きの扱い(コンテナ設定)。suppress=候補から除去(既定)、
// demote=候補リスト後方、normal=同列(従来どおり)。
enum ScriptVariantCandidateMode: String {
    case suppress
    case demote
    case normal
}

enum KanaKanjiCandidateSourceTag {
    static let normalized = "normalized"
    static let surface = "surface"
    static let adjectiveGaru = "adjective-garu"
}

enum KanaKanjiSemanticSeed {
    static let adjectiveGaruCandidatesByReading: [String: Set<String>] = [
        "あつい": ["暑い"],
        "うれしい": ["嬉しい"],
        "かなしい": ["悲しい"],
        "こわい": ["怖い"],
        "さむい": ["寒い"],
        "さびしい": ["寂しい"],
        "たのしい": ["楽しい"],
        "はずかしい": ["恥ずかしい"],
        "くやしい": ["悔しい"]
    ]
}

enum KanaKanjiCandidateSourceMode: String {
    case normalise
    case surface
    case lesDeux

    var requiredSystemSources: Set<String>? {
        switch self {
        case .normalise:
            return [KanaKanjiCandidateSourceTag.normalized]
        case .surface:
            return [KanaKanjiCandidateSourceTag.surface]
        case .lesDeux:
            return nil
        }
    }
}

enum UserDictionaryCandidateDisplayMode: String {
    case off
    case on

    var usesUserDictionaryCandidates: Bool {
        self == .on
    }
}

enum ContactCandidateDisplayMode: String {
    case off
    case namesOnly
    case namesPlusFullName

    var usesContacts: Bool {
        self != .off
    }

    var includesFullNameForNameMatches: Bool {
        self == .namesPlusFullName
    }
}

// 連絡先キャッシュの暗号化(2026-08-31)。氏名・読みの対応表を共有defaultsへ平文で
// 置かない(端末外送信はもともと無いが、バックアップ等での可読性を断つ)。
// 鍵は両ターゲット共有のKeychain(kSecAttrAccessibleAfterFirstUnlock)に置き、
// 本体は AES-GCM で封緘して App Group defaults に保存する。
enum ContactCacheCipher {
    static let keychainService = "com.kusakabe.ecritu.contactCache"
    static let keychainAccount = "aes-256-key"

    // 純関数部(テスト対象): JSONエンコード→AES-GCM封緘
    static func seal(_ dictionary: [String: [String]], key: SymmetricKey) -> Data? {
        guard let json = try? JSONEncoder().encode(dictionary),
            let sealed = try? AES.GCM.seal(json, using: key).combined else {
            return nil
        }
        return sealed
    }

    static func open(_ data: Data, key: SymmetricKey) -> [String: [String]]? {
        guard let box = try? AES.GCM.SealedBox(combined: data),
            let json = try? AES.GCM.open(box, using: key),
            let dictionary = try? JSONDecoder().decode([String: [String]].self, from: json) else {
            return nil
        }
        return dictionary
    }

    // Keychainの共有鍵。createNew=false(キーボード側)は既存が無ければ nil を返すだけ。
    static func keychainKey(createNew: Bool) -> SymmetricKey? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }
        guard createNew else {
            return nil
        }
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        query.removeValue(forKey: kSecReturnData as String)
        query.removeValue(forKey: kSecMatchLimit as String)
        query[kSecValueData as String] = keyData
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else {
            return nil
        }
        if addStatus == errSecDuplicateItem {
            // 競合で他方が先に作った場合は読み直す
            return keychainKey(createNew: false)
        }
        return key
    }
}

