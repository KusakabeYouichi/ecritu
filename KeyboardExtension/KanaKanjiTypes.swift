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
    static let initialShortcutVocabularyResourceName = "InitialShortcutVocabMigration"
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

// MARK: - Kana-Kanji inflection definitions split from KanaKanjiConverter.swift
extension KanaKanjiConverter {
    enum InflectionClass {
        static let adjectiveI = "adjective-i"
        static let ichidan = "ichidan"
        static let godanU = "godan-u"
        static let godanKu = "godan-ku"
        static let godanGu = "godan-gu"
        static let godanSu = "godan-su"
        static let godanTsu = "godan-tsu"
        static let godanNu = "godan-nu"
        static let godanBu = "godan-bu"
        static let godanMu = "godan-mu"
        static let godanRu = "godan-ru"
        static let suru = "suru"
        static let kuru = "kuru"
    }

    struct InflectionRule {
        let readingSuffix: String
        let baseReadingSuffix: String
        let baseCandidateSuffixes: [String]
        let outputCandidateSuffix: String
        let allowedClasses: Set<String>

        init(
            readingSuffix: String,
            baseReadingSuffix: String,
            baseCandidateSuffixes: [String]? = nil,
            outputCandidateSuffix: String? = nil,
            allowedClasses: Set<String>
        ) {
            self.readingSuffix = readingSuffix
            self.baseReadingSuffix = baseReadingSuffix
            self.baseCandidateSuffixes = baseCandidateSuffixes ?? [baseReadingSuffix]
            self.outputCandidateSuffix = outputCandidateSuffix ?? readingSuffix
            self.allowedClasses = allowedClasses
        }
    }

    struct GodanPattern {
        let dictionaryEnding: String
        let inflectionClass: String
        let aForm: String
        let iForm: String
        let eForm: String
        let oForm: String
        let teForm: String
        let taForm: String
    }

    static let adjectiveInflectionRules: [InflectionRule] = [
        InflectionRule(readingSuffix: "いです", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "のだ", baseReadingSuffix: "", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "のです", baseReadingSuffix: "", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くない", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなく", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くないです", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなかった", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなかったです", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "かった", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "かったり", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "かったです", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くありません", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くありませんでした", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くて", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "ければ", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "く", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くする", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなり", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなる", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなります", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなりました", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなりません", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなった", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなって", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなってる", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなっている", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなってた", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなっていた", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなってくる", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなってきた", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなってきて", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなってきます", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "すぎ", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "すぎる", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "すぎない", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "すぎなかった", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "すぎて", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "すぎた", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "すぎます", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "すぎました", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "すぎません", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "すぎれば", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "さ", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI])
    ]

    static let ichidanInflectionRules: [InflectionRule] = [
        InflectionRule(readingSuffix: "ない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ず", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "なかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "なかったら", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ます", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ました", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ません", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たい", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たく", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たくて", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たくない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たくなくて", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たくなかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たくありません", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たければ", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "にくい", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "にくく", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "にくくない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "にくかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "すぎ", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "すぎる", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "すぎない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "すぎなかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "すぎて", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "すぎた", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "すぎます", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "すぎました", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "すぎません", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "すぎれば", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "て", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てある", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てくる", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てきた", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てきて", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てこない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てこなかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てきます", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てきました", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てきません", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てる", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ている", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てて", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ていて", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てた", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ていた", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ていない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てなかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ていなかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てます", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ています", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てました", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ていました", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てません", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ていません", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ておく", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ておいた", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ておいて", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ておかない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ておかなかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ておきます", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ておきました", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ておきません", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "とく", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "といた", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "といて", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "とかない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "とかなかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ときます", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ときました", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ときません", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てみる", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てみた", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てみて", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てみない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てみなかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てみます", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てみました", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てみません", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てみたい", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てみたく", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てみたくて", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てみたくない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てみたくなくて", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てみたくなかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てみたくありません", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てみたかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てみたければ", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てしまう", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てしまわない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てしまわなかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てしまいます", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てしまいました", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てしまい", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てしまいません", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てしまった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てしまって", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ちゃう", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ちゃわない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ちゃわなかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ちゃいます", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ちゃいました", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ちゃいません", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ちゃった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ちゃって", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ちゃ", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "かた", baseReadingSuffix: "る", outputCandidateSuffix: "方", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "た", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たら", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たり", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たりする", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たりしない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たりしなかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たりします", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たりしますか", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たりしました", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たりしません", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たりしませんか", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たりするのですか", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "よう", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "れば", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "られ", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "られる", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "られない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "させる", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "させない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "させられる", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "させられない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "やすい", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "やすく", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "やすくない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "やすかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan])
    ]

    static let godanPatterns: [GodanPattern] = [
        GodanPattern(dictionaryEnding: "う", inflectionClass: InflectionClass.godanU, aForm: "わ", iForm: "い", eForm: "え", oForm: "お", teForm: "って", taForm: "った"),
        GodanPattern(dictionaryEnding: "く", inflectionClass: InflectionClass.godanKu, aForm: "か", iForm: "き", eForm: "け", oForm: "こ", teForm: "いて", taForm: "いた"),
        GodanPattern(dictionaryEnding: "ぐ", inflectionClass: InflectionClass.godanGu, aForm: "が", iForm: "ぎ", eForm: "げ", oForm: "ご", teForm: "いで", taForm: "いだ"),
        GodanPattern(dictionaryEnding: "す", inflectionClass: InflectionClass.godanSu, aForm: "さ", iForm: "し", eForm: "せ", oForm: "そ", teForm: "して", taForm: "した"),
        GodanPattern(dictionaryEnding: "つ", inflectionClass: InflectionClass.godanTsu, aForm: "た", iForm: "ち", eForm: "て", oForm: "と", teForm: "って", taForm: "った"),
        GodanPattern(dictionaryEnding: "ぬ", inflectionClass: InflectionClass.godanNu, aForm: "な", iForm: "に", eForm: "ね", oForm: "の", teForm: "んで", taForm: "んだ"),
        GodanPattern(dictionaryEnding: "ぶ", inflectionClass: InflectionClass.godanBu, aForm: "ば", iForm: "び", eForm: "べ", oForm: "ぼ", teForm: "んで", taForm: "んだ"),
        GodanPattern(dictionaryEnding: "む", inflectionClass: InflectionClass.godanMu, aForm: "ま", iForm: "み", eForm: "め", oForm: "も", teForm: "んで", taForm: "んだ"),
        GodanPattern(dictionaryEnding: "る", inflectionClass: InflectionClass.godanRu, aForm: "ら", iForm: "り", eForm: "れ", oForm: "ろ", teForm: "って", taForm: "った")
    ]

    static func teShimauInflectionSuffixes(for teForm: String) -> [String] {
        guard !teForm.isEmpty else {
            return []
        }

        var suffixes = [
            teForm + "しまう",
            teForm + "しまわない",
            teForm + "しまわなかった",
            teForm + "しまいます",
            teForm + "しまいました",
            teForm + "しまい",
            teForm + "しまいません",
            teForm + "しまった",
            teForm + "しまって"
        ]
        suffixes.append(contentsOf: taiAdjectiveFamilyInflectionSuffixes(for: teForm + "しまい"))

        if teForm.hasSuffix("て") {
            let contractionStem = String(teForm.dropLast())
            suffixes.append(contractionStem + "ちゃ")
            suffixes.append(contractionStem + "ちゃう")
            suffixes.append(contractionStem + "ちゃわない")
            suffixes.append(contractionStem + "ちゃわなかった")
            suffixes.append(contractionStem + "ちゃいます")
            suffixes.append(contractionStem + "ちゃいました")
            suffixes.append(contractionStem + "ちゃいません")
            suffixes.append(contractionStem + "ちゃった")
            suffixes.append(contractionStem + "ちゃって")
            suffixes.append(contentsOf: taiAdjectiveFamilyInflectionSuffixes(for: contractionStem + "ちゃい"))
        } else if teForm.hasSuffix("で") {
            let contractionStem = String(teForm.dropLast())
            suffixes.append(contractionStem + "じゃ")
            suffixes.append(contractionStem + "じゃう")
            suffixes.append(contractionStem + "じゃわない")
            suffixes.append(contractionStem + "じゃわなかった")
            suffixes.append(contractionStem + "じゃいます")
            suffixes.append(contractionStem + "じゃいました")
            suffixes.append(contractionStem + "じゃいません")
            suffixes.append(contractionStem + "じゃった")
            suffixes.append(contractionStem + "じゃって")
            suffixes.append(contentsOf: taiAdjectiveFamilyInflectionSuffixes(for: contractionStem + "じゃい"))
        }

        return suffixes
    }

    static func teOkuInflectionSuffixes(for teForm: String) -> [String] {
        guard !teForm.isEmpty else {
            return []
        }

        var suffixes = [
            teForm + "おく",
            teForm + "おいた",
            teForm + "おいて",
            teForm + "おかない",
            teForm + "おかなかった",
            teForm + "おきます",
            teForm + "おきました",
            teForm + "おきません"
        ]
        suffixes.append(contentsOf: taiAdjectiveFamilyInflectionSuffixes(for: teForm + "おき"))

        if teForm.hasSuffix("て") {
            let contractionStem = String(teForm.dropLast())
            suffixes.append(contractionStem + "とく")
            suffixes.append(contractionStem + "といた")
            suffixes.append(contractionStem + "といて")
            suffixes.append(contractionStem + "とかない")
            suffixes.append(contractionStem + "とかなかった")
            suffixes.append(contractionStem + "ときます")
            suffixes.append(contractionStem + "ときました")
            suffixes.append(contractionStem + "ときません")
            suffixes.append(contentsOf: taiAdjectiveFamilyInflectionSuffixes(for: contractionStem + "とき"))
        } else if teForm.hasSuffix("で") {
            let contractionStem = String(teForm.dropLast())
            suffixes.append(contractionStem + "どく")
            suffixes.append(contractionStem + "どいた")
            suffixes.append(contractionStem + "どいて")
            suffixes.append(contractionStem + "どかない")
            suffixes.append(contractionStem + "どかなかった")
            suffixes.append(contractionStem + "どきます")
            suffixes.append(contractionStem + "どきました")
            suffixes.append(contractionStem + "どきません")
            suffixes.append(contentsOf: taiAdjectiveFamilyInflectionSuffixes(for: contractionStem + "どき"))
        }

        return suffixes
    }

    static func taiAdjectiveFamilyInflectionSuffixes(for iStem: String) -> [String] {
        guard !iStem.isEmpty else {
            return []
        }

        return [
            iStem + "たい",
            iStem + "たく",
            iStem + "たくて",
            iStem + "たくない",
            iStem + "たくなくて",
            iStem + "たくなかった",
            iStem + "たくありません",
            iStem + "たかった",
            iStem + "たければ"
        ]
    }

    static func teMiruInflectionSuffixes(for teForm: String) -> [String] {
        guard !teForm.isEmpty else {
            return []
        }

        return [
            teForm + "みる",
            teForm + "みた",
            teForm + "みて",
            teForm + "みない",
            teForm + "みなかった",
            teForm + "みます",
            teForm + "みました",
            teForm + "みません"
        ] + taiAdjectiveFamilyInflectionSuffixes(for: teForm + "み")
    }

    static func teAruInflectionSuffixes(for teForm: String) -> [String] {
        guard !teForm.isEmpty else {
            return []
        }

        return [
            teForm + "ある",
            teForm + "あった"
        ]
    }

    static func teKuruInflectionSuffixes(for teForm: String) -> [String] {
        guard !teForm.isEmpty else {
            return []
        }

        return [
            teForm + "くる",
            teForm + "きた",
            teForm + "きて",
            teForm + "こない",
            teForm + "こなかった",
            teForm + "きます",
            teForm + "きました",
            teForm + "きません"
        ] + taiAdjectiveFamilyInflectionSuffixes(for: teForm + "き")
    }

    static func teIkuInflectionSuffixes(for teForm: String) -> [String] {
        guard !teForm.isEmpty else {
            return []
        }

        return [
            teForm + "いく",
            teForm + "く",
            teForm + "け",
            teForm + "いった",
            teForm + "いって",
            teForm + "いかない",
            teForm + "いかなかった",
            teForm + "いきます",
            teForm + "いきました",
            teForm + "いきません",
            teForm + "って"
        ] + taiAdjectiveFamilyInflectionSuffixes(for: teForm + "いき")
    }

    static func taiGaruInflectionSuffixes(for iForm: String) -> [String] {
        guard !iForm.isEmpty else {
            return []
        }

        return [
            iForm + "たがる",
            iForm + "たがった",
            iForm + "たがって",
            iForm + "たがらない",
            iForm + "たがらなかった",
            iForm + "たがります",
            iForm + "たがりました",
            iForm + "たがりません"
        ]
    }

    static func makuInflectionSuffixes(for renyouForm: String) -> [String] {
        guard !renyouForm.isEmpty else {
            return []
        }

        return [
            renyouForm + "まくる",
            renyouForm + "まくらない",
            renyouForm + "まくらなかった",
            renyouForm + "まくり",
            renyouForm + "まくります",
            renyouForm + "まくりました",
            renyouForm + "まくりません",
            renyouForm + "まくれ",
            renyouForm + "まくれば",
            renyouForm + "まくろう",
            renyouForm + "まくった",
            renyouForm + "まくって"
        ]
    }

    static let adjectiveGaruInflectionForms: [(readingSuffix: String, outputSuffix: String)] = [
        ("がらなかった", "がらなかった"),
        ("がりました", "がりました"),
        ("がりません", "がりません"),
        ("がらない", "がらない"),
        ("がり", "がり"),
        ("がった", "がった"),
        ("がって", "がって"),
        ("がる", "がる")
    ]

    static func taRiSuruInflectionSuffixes(for taForm: String) -> [String] {
        guard !taForm.isEmpty else {
            return []
        }

        let tari = taForm + "り"

        return [
            tari,
            tari + "する",
            tari + "しない",
            tari + "しなかった",
            tari + "します",
            tari + "しますか",
            tari + "しました",
            tari + "しません",
            tari + "しませんか",
            tari + "するのですか"
        ]
    }

    static func teAspectInflectionSuffixes(for teForm: String) -> [String] {
        guard !teForm.isEmpty else {
            return []
        }

        return [
            teForm,
            teForm + "る",
            teForm + "いる",
            teForm + "て",
            teForm + "いて",
            teForm + "た",
            teForm + "いた",
            teForm + "ない",
            teForm + "いない",
            teForm + "なかった",
            teForm + "いなかった",
            teForm + "ます",
            teForm + "います",
            teForm + "ました",
            teForm + "いました",
            teForm + "ません",
            teForm + "いません"
        ]
            + taiAdjectiveFamilyInflectionSuffixes(for: teForm + "い")
            + taiAdjectiveFamilyInflectionSuffixes(for: teForm)
    }

    static let godanInflectionRules: [InflectionRule] = {
        var rules: [InflectionRule] = []

        for pattern in godanPatterns {
            let passiveTeForm = pattern.aForm + "れて"

            var suffixes = [
                pattern.aForm + "ない",
                pattern.aForm + "なかった",
                pattern.aForm + "なかったら",
                pattern.aForm + "ねば",
                pattern.aForm + "ず",
                pattern.aForm + "れる",
                pattern.aForm + "れない",
                pattern.aForm + "せる",
                pattern.aForm + "せて",
                pattern.aForm + "せない",
                pattern.aForm + "せられる",
                pattern.aForm + "せられない",
                pattern.aForm + "れた",
                pattern.aForm + "れ",
                pattern.iForm + "ます",
                pattern.iForm + "ました",
                pattern.iForm + "ません",
                pattern.iForm + "たい",
                pattern.iForm + "たく",
                pattern.iForm + "たくて",
                pattern.iForm + "たくない",
                pattern.iForm + "たくなくて",
                pattern.iForm + "たくなかった",
                pattern.iForm + "たくありません",
                pattern.iForm + "たかった",
                pattern.iForm + "たければ",
                pattern.iForm + "にくい",
                pattern.iForm + "にくく",
                pattern.iForm + "にくくない",
                pattern.iForm + "にくかった",
                pattern.iForm + "すぎ",
                pattern.iForm + "すぎる",
                pattern.iForm + "すぎない",
                pattern.iForm + "すぎなかった",
                pattern.iForm + "すぎて",
                pattern.iForm + "すぎた",
                pattern.iForm + "すぎます",
                pattern.iForm + "すぎました",
                pattern.iForm + "すぎません",
                pattern.iForm + "すぎれば",
                pattern.eForm,
                pattern.eForm + "ば",
                pattern.oForm + "う",
                pattern.taForm,
                pattern.taForm + "ら"
            ]

            suffixes.append(contentsOf: KanaKanjiConverter.taRiSuruInflectionSuffixes(for: pattern.taForm))
            suffixes.append(contentsOf: KanaKanjiConverter.taiGaruInflectionSuffixes(for: pattern.iForm))
            suffixes.append(contentsOf: KanaKanjiConverter.makuInflectionSuffixes(for: pattern.iForm))
            suffixes.append(contentsOf: KanaKanjiConverter.teAspectInflectionSuffixes(for: pattern.teForm))
            suffixes.append(contentsOf: KanaKanjiConverter.teAspectInflectionSuffixes(for: passiveTeForm))
            suffixes.append(contentsOf: KanaKanjiConverter.teAruInflectionSuffixes(for: pattern.teForm))
            suffixes.append(contentsOf: KanaKanjiConverter.teKuruInflectionSuffixes(for: pattern.teForm))
            suffixes.append(contentsOf: KanaKanjiConverter.teIkuInflectionSuffixes(for: pattern.teForm))
            suffixes.append(contentsOf: KanaKanjiConverter.teOkuInflectionSuffixes(for: pattern.teForm))
            suffixes.append(contentsOf: KanaKanjiConverter.teMiruInflectionSuffixes(for: pattern.teForm))
            suffixes.append(contentsOf: KanaKanjiConverter.teShimauInflectionSuffixes(for: pattern.teForm))

            for suffix in suffixes {
                rules.append(
                    InflectionRule(
                        readingSuffix: suffix,
                        baseReadingSuffix: pattern.dictionaryEnding,
                        allowedClasses: [pattern.inflectionClass]
                    )
                )
            }

            rules.append(
                InflectionRule(
                    readingSuffix: pattern.iForm + "かた",
                    baseReadingSuffix: pattern.dictionaryEnding,
                    outputCandidateSuffix: pattern.iForm + "方",
                    allowedClasses: [pattern.inflectionClass]
                )
            )
        }

        return rules
    }()

    static let suruInflectionRules: [InflectionRule] = [
        InflectionRule(readingSuffix: "しない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しなかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "します", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しました", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しません", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したい", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したく", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したくて", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したくない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したくなくて", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したくなかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したくありません", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したければ", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しにくい", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しにくく", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しにくくない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しにくかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎ", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎる", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎなかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎて", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎた", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎます", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎました", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎません", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎれば", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "して", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してる", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "している", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してて", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していて", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してた", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していた", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してなかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していなかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してます", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しています", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してました", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していました", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してません", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していません", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しておく", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しておいた", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しておいて", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しておかない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しておかなかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しておきます", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しておきました", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しておきません", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しとく", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しといた", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しといて", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しとかない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しとかなかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しときます", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しときました", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しときません", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみる", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみた", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみて", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみなかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみます", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみました", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみません", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみたい", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみたく", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみたくて", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみたくない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみたくなくて", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみたくなかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみたくありません", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみたかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみたければ", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまう", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまわない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまわなかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまいます", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまいました", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまい", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまいません", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまって", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しちゃう", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しちゃわない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しちゃわなかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しちゃいます", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しちゃいました", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しちゃいません", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しちゃった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しちゃって", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しちゃ", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "した", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したら", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したり", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したりする", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したりしない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したりしなかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したりします", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したりしますか", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したりしました", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したりしません", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したりしませんか", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したりするのですか", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しよう", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "すれば", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "され", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "される", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "された", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されて", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されてる", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されている", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されてた", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されていた", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されます", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されました", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されません", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されなかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されませんでした", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させる", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させた", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させて", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させている", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させてる", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させます", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させました", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させません", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させなかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられる", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられた", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられて", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられている", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられます", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられました", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられません", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられなかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru])
    ]

    static let sahenNounSuruInflectionRules: [InflectionRule] = [
        InflectionRule(readingSuffix: "する", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できる", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できます", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できてる", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できている", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できてて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できていて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できた", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できていた", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できてない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できていない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できてなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できていなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できてます", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できています", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できてました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できていました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できてません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できていません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できれば", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "します", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したい", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したく", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したくて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したくない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したくなくて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したくなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したくありません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したければ", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しにくい", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しにくく", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しにくくない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しにくかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎ", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎる", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎた", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎます", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎれば", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "して", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してる", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "している", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してた", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していた", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してます", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しています", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しておく", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しておいた", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しておいて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しておかない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しておかなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しておきます", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しておきました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しておきません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しとく", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しといた", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しといて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しとかない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しとかなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しときます", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しときました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しときません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみる", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみた", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみます", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみたい", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみたく", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみたくて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみたくない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみたくなくて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみたくなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみたくありません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみたかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみたければ", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまう", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまわない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまわなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまいます", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまいました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまい", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまいません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまって", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しちゃう", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しちゃわない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しちゃわなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しちゃいます", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しちゃいました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しちゃいません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しちゃった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しちゃって", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しちゃ", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "した", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したら", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したり", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したりする", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したりしない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したりしなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したりします", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したりしますか", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したりしました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したりしません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したりしませんか", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したりするのですか", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しよう", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "すれば", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "され", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "される", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "された", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されてる", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されている", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されてた", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されていた", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されます", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されませんでした", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させる", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させた", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させている", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させてる", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させます", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられる", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられた", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられている", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられます", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru])
    ]

    static let kuruInflectionForms: [(readingSuffix: String, kanjiOutputSuffix: String)] = [
        ("こない", "来ない"),
        ("こなかった", "来なかった"),
        ("こい", "来い"),
        ("きます", "来ます"),
        ("きました", "来ました"),
        ("きません", "来ません"),
        ("きたい", "来たい"),
        ("きたく", "来たく"),
        ("きたくて", "来たくて"),
        ("きたくない", "来たくない"),
        ("きたくなくて", "来たくなくて"),
        ("きたくなかった", "来たくなかった"),
        ("きたくありません", "来たくありません"),
        ("きたかった", "来たかった"),
        ("きたければ", "来たければ"),
        ("きにくい", "来にくい"),
        ("きにくく", "来にくく"),
        ("きにくくない", "来にくくない"),
        ("きにくかった", "来にくかった"),
        ("きすぎ", "来すぎ"),
        ("きすぎる", "来すぎる"),
        ("きすぎない", "来すぎない"),
        ("きすぎなかった", "来すぎなかった"),
        ("きすぎて", "来すぎて"),
        ("きすぎた", "来すぎた"),
        ("きすぎます", "来すぎます"),
        ("きすぎました", "来すぎました"),
        ("きすぎません", "来すぎません"),
        ("きすぎれば", "来すぎれば"),
        ("きて", "来て"),
        ("きてる", "来てる"),
        ("きている", "来ている"),
        ("きてて", "来てて"),
        ("きていて", "来ていて"),
        ("きてた", "来てた"),
        ("きていた", "来ていた"),
        ("きてない", "来てない"),
        ("きていない", "来ていない"),
        ("きてなかった", "来てなかった"),
        ("きていなかった", "来ていなかった"),
        ("きてます", "来てます"),
        ("きています", "来ています"),
        ("きてました", "来てました"),
        ("きていました", "来ていました"),
        ("きてません", "来てません"),
        ("きていません", "来ていません"),
        ("きておく", "来ておく"),
        ("きておいた", "来ておいた"),
        ("きておいて", "来ておいて"),
        ("きておかない", "来ておかない"),
        ("きておかなかった", "来ておかなかった"),
        ("きておきます", "来ておきます"),
        ("きておきました", "来ておきました"),
        ("きておきません", "来ておきません"),
        ("きとく", "来とく"),
        ("きといた", "来といた"),
        ("きといて", "来といて"),
        ("きとかない", "来とかない"),
        ("きとかなかった", "来とかなかった"),
        ("きときます", "来ときます"),
        ("きときました", "来ときました"),
        ("きときません", "来ときません"),
        ("きてみる", "来てみる"),
        ("きてみた", "来てみた"),
        ("きてみて", "来てみて"),
        ("きてみない", "来てみない"),
        ("きてみなかった", "来てみなかった"),
        ("きてみます", "来てみます"),
        ("きてみました", "来てみました"),
        ("きてみません", "来てみません"),
        ("きてみたい", "来てみたい"),
        ("きてみたく", "来てみたく"),
        ("きてみたくて", "来てみたくて"),
        ("きてみたくない", "来てみたくない"),
        ("きてみたくなくて", "来てみたくなくて"),
        ("きてみたくなかった", "来てみたくなかった"),
        ("きてみたくありません", "来てみたくありません"),
        ("きてみたかった", "来てみたかった"),
        ("きてみたければ", "来てみたければ"),
        ("きてしまう", "来てしまう"),
        ("きてしまわない", "来てしまわない"),
        ("きてしまわなかった", "来てしまわなかった"),
        ("きてしまいます", "来てしまいます"),
        ("きてしまいました", "来てしまいました"),
        ("きてしまい", "来てしまい"),
        ("きてしまいません", "来てしまいません"),
        ("きてしまった", "来てしまった"),
        ("きてしまって", "来てしまって"),
        ("きちゃう", "来ちゃう"),
        ("きちゃわない", "来ちゃわない"),
        ("きちゃわなかった", "来ちゃわなかった"),
        ("きちゃいます", "来ちゃいます"),
        ("きちゃいました", "来ちゃいました"),
        ("きちゃいません", "来ちゃいません"),
        ("きちゃった", "来ちゃった"),
        ("きちゃって", "来ちゃって"),
        ("きちゃ", "来ちゃ"),
        ("きた", "来た"),
        ("きたら", "来たら"),
        ("きたり", "来たり"),
        ("きたりする", "来たりする"),
        ("きたりしない", "来たりしない"),
        ("きたりしなかった", "来たりしなかった"),
        ("きたりします", "来たりします"),
        ("きたりしますか", "来たりしますか"),
        ("きたりしました", "来たりしました"),
        ("きたりしません", "来たりしません"),
        ("きたりしませんか", "来たりしませんか"),
        ("きたりするのですか", "来たりするのですか"),
        ("こよう", "来よう"),
        ("くれば", "来れば"),
        ("こられ", "来られ"),
        ("こられる", "来られる"),
        ("こられない", "来られない")
    ]

    static let kuruInflectionRules: [InflectionRule] = {
        var rules: [InflectionRule] = []

        for form in kuruInflectionForms {
            rules.append(
                InflectionRule(
                    readingSuffix: form.readingSuffix,
                    baseReadingSuffix: "くる",
                    baseCandidateSuffixes: ["くる"],
                    outputCandidateSuffix: form.readingSuffix,
                    allowedClasses: [InflectionClass.kuru]
                )
            )
            rules.append(
                InflectionRule(
                    readingSuffix: form.readingSuffix,
                    baseReadingSuffix: "くる",
                    baseCandidateSuffixes: ["来る"],
                    outputCandidateSuffix: form.kanjiOutputSuffix,
                    allowedClasses: [InflectionClass.kuru]
                )
            )
        }

        return rules
    }()

    static let allInflectionRules: [InflectionRule] =
        adjectiveInflectionRules
        + ichidanInflectionRules
        + godanInflectionRules
        + sahenNounSuruInflectionRules
        + suruInflectionRules
        + kuruInflectionRules

    static let emptyStemAllowedBaseReadingSuffixes: Set<String> = [
        "する",
        "くる"
    ]

    static let inflectionRankingSuffixes: [String] = [
        "させられない", "させられる", "せられない", "せられる", "こられない", "こられる", "られない", "られる",
        "こられ", "され", "られ",
        "くありませんでした", "くなかったです", "くないです", "かったです", "くありません",
        "くなりません", "くなりました", "くなります",
        "すぎなかった", "すぎました", "すぎません", "にくくない", "すぎない", "すぎます", "にくかった",
        "させない", "させる", "せない", "せる", "やすくない", "たがらなかった", "たがりました", "たがりません", "がらなかった", "がりました", "がりません", "たくない", "なかったら", "たら", "なかった", "やすかった", "たかった", "くなかった",
        "すぎて", "すぎれば", "すぎた", "すぎる", "にくい", "にくく", "いです", "すぎ",
        "していなかった", "きていなかった", "でいなかった", "ていなかった", "してなかった", "きてなかった", "でなかった", "てなかった",
        "していません", "きていません", "でいません", "ていません", "していました", "きていました", "でいました", "ていました",
        "しています", "きています", "でいます", "ています", "してません", "きてません", "でません", "てません",
        "してました", "きてました", "でました", "てました", "してます", "きてます", "でます", "てます",
        "していない", "きていない", "でいない", "ていない", "してない", "きてない", "でない", "てない",
        "していた", "きていた", "でいた", "ていた", "してた", "きてた", "でた", "てた",
        "たりするのですか", "たりしませんか", "たりしますか", "たりしなかった", "たりしません", "たりしました", "たりします", "たりしない", "たりする",
        "したり", "きたり", "んだり", "いだり", "いたり", "ったり", "たり", "だり",
        "てしまわなかった", "でしまわなかった", "てしまいません", "でしまいません", "てしまいました", "でしまいました", "てしまいます", "でしまいます", "てしまわない", "でしまわない",
        "てしまい", "でしまい",
        "ちゃわなかった", "じゃわなかった", "ちゃいません", "じゃいません", "ちゃいました", "じゃいました", "ちゃいます", "じゃいます", "ちゃわない", "じゃわない",
        "ておかなかった", "でおかなかった", "とかなかった", "どかなかった", "ておきません", "でおきません", "ときません", "どきません", "ておきました", "でおきました", "ときました", "どきました",
        "ておきます", "でおきます", "ときます", "どきます", "ておかない", "でおかない", "とかない", "どかない", "ておいた", "でおいた", "といた", "どいた", "ておいて", "でおいて", "といて", "どいて",
        "てみなかった", "でみなかった", "てみません", "でみません", "てみました", "でみました", "てみます", "でみます", "てみない", "でみない", "ておく", "でおく", "とく", "どく", "てみた", "でみた", "てみて", "でみて", "てみる", "でみる",
        "てしまって", "でしまって", "ちゃって", "じゃって",
        "てしまった", "でしまった", "ちゃった", "じゃった",
        "てしまう", "でしまう", "ちゃう", "じゃう",
        "ちゃ", "じゃ",
        "している", "きている", "でいる", "ている", "してる", "きてる", "でる", "てる",
        "きました", "しました", "きません", "しません", "ました", "ます",
        "だったら", "だった", "だ", "なら", "から",
        "んですけれど", "んですけど", "んだけれど", "んだけど", "けれど", "けど",
        "んです", "んだ",
        "くない", "かったり", "かった", "ければ", "くれば", "くなり", "くする", "やすい", "やすく", "よう", "こよう", "こい", "たがらない", "たがります", "がらない", "たい", "れば", "ねば", "ず",
        "がり",
        "たがった", "たがって", "たがる", "がった", "がって", "がる",
        "って", "った", "いて", "いた", "いで", "いだ", "んで", "んだ", "して", "した",
        "ない", "きて", "きた", "くて", "て", "た"
    ]

    static let ikuIrregularInflectionSuffixes: [String] = {
        var suffixes = ["った", "ったら"]
        suffixes.append(contentsOf: KanaKanjiConverter.taRiSuruInflectionSuffixes(for: "った"))
        suffixes.append(contentsOf: KanaKanjiConverter.teAspectInflectionSuffixes(for: "って"))
        suffixes.append(contentsOf: KanaKanjiConverter.teAruInflectionSuffixes(for: "って"))
        suffixes.append(contentsOf: KanaKanjiConverter.teKuruInflectionSuffixes(for: "って"))
        suffixes.append(contentsOf: KanaKanjiConverter.teIkuInflectionSuffixes(for: "って"))
        suffixes.append(contentsOf: KanaKanjiConverter.teOkuInflectionSuffixes(for: "って"))
        suffixes.append(contentsOf: KanaKanjiConverter.teMiruInflectionSuffixes(for: "って"))
        suffixes.append(contentsOf: KanaKanjiConverter.teShimauInflectionSuffixes(for: "って"))
        return suffixes
    }()

    static let postfixPassthroughSuffixes: [String] = [
        "ほうがいい", "ほうがよい", "ほうが", "ようになる", "ようにする", "ようにして", "ように", "よう", "ような", "ようだ", "ようです", "です", "んですけれど", "んですけど", "んだけれど", "んだけど", "のだ", "んです", "んだ", "だろう", "だったら", "だった", "なければ", "なく", "ない", "だ", "けれど", "けど", "ください", "だけだ", "こと", "など", "だけ", "では", "には", "とは", "まで", "なら", "から", "へ", "は", "を", "に", "で", "と", "が", "も", "の", "し", "ね", "よ", "な", "か", "や", "ぞ", "ぜ", "さ"
    ]
    static let postfixPassthroughPrefixReplacements: [(from: String, to: String)] = [
        ("ほう", "方")
    ]
}
