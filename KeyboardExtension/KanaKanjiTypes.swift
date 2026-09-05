import Foundation

enum KanaKanjiStorageKeys {
    static let ajoutVocabulary = "ÉcrituAjoutVocab"
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
    static let initialAjoutVocabularyResourceName = "InitialAjoutVocabMigration"
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

}

extension Array where Element == String {
    // 前後空白を除いた表層で重複を畳み、空文字を捨てる(出現順を保つ)。
    // keepingOriginalText=true なら比較だけ trimmed で行い、返す要素は元の文字列(ショートカット語彙の表示用)。
    // 以前は converter/store/merger/RootView に同じループが 5 本あった(2805 リファクタで集約)
    func uniquedTrimmedCandidates(keepingOriginalText: Bool = false) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        result.reserveCapacity(count)
        for candidate in self {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else {
                continue
            }
            result.append(keepingOriginalText ? candidate : trimmed)
        }
        return result
    }
}
