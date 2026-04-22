import Foundation

enum KanaKanjiStorageKeys {
    static let userDictionary = "ÉcrituAjoutVocab"
    static let suppressionVocabulary = "ÉcrituSuppr_Vocab"
    static let learningScores = "kanaKanjiLearningScores"
    static let systemDictionaryFilename = "ÉcrituPremierVocab.json"
    static let systemCandidateSourcesFilename = "kana_kanji_candidate_sources.json"
    static let inflectionDictionaryFilename = "kana_kanji_inflection_dictionary.json"
    static let initialUserDictionaryResourceName = "InitialAjoutVocabMigration"
}

enum KanaKanjiCandidateSourceMode: String {
    case normalise
    case surface
    case lesDeux

    var requiredSystemSources: Set<String>? {
        switch self {
        case .normalise:
            return ["normalized"]
        case .surface:
            return ["surface"]
        case .lesDeux:
            return nil
        }
    }
}
