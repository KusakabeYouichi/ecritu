import Foundation

enum KanaKanjiStorageKeys {
    static let userDictionary = "ÉcrituAjoutVocab"
    static let learnedDictionary = "kanaKanjiLearnedVocabulary"
    static let shortcutVocabulary = "ÉcrituShortcutVocab"
    static let suppressionVocabulary = "ÉcrituSuppr_Vocab"
    static let learningScores = "kanaKanjiLearningScores"
    static let systemDictionarySQLiteFilename = "kana_kanji_dictionary.sqlite"
    static let systemDictionaryFilename = "ÉcrituPremierVocab.json"
    static let supplementalSystemDictionaryFilename = "ÉcrituSecondVocab.json"
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
