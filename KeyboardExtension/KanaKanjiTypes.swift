import Foundation

enum KanaKanjiStorageKeys {
    static let ajoutVocabulary = "ÉcrituAjoutVocab"
    static let learnedDictionary = "kanaKanjiLearnedVocabulary"
    static let shortcutVocabulary = "ÉcrituShortcutVocab"
    // iOS のユーザ辞書で読みが ☻ の単語をショートカット語彙へ取り込む予約(3244)。
    // アプリが初回起動時と「iOS のユーザ辞書の単語」を「使う」にしたときに true を書き、
    // 拡張がレキシコン取得時に消費する(アプリ側からはユーザ辞書を読めないため)。
    static let userDictionaryShortcutImportPending = "kanaKanjiUserDictionaryShortcutImportPending"
    // 一度でも取り込んだ印。無ければ予約と同じ扱い(アプリを開かずに使い始めた端末や、
    // 予約の仕組みより前に初回移行が済んだ端末でも、最初にキーボードを開いたとき取り込む)
    static let userDictionaryShortcutImportedOnce = "kanaKanjiUserDictionaryShortcutImportedOnce"
    static let suppressionVocabulary = "ÉcrituSuppr_Vocab"
    static let learningScores = "kanaKanjiLearningScores"
    static let systemDictionarySQLiteFilename = "kana_kanji_dictionary.sqlite"
    static let systemDictionaryFilename = "ÉcrituPremierVocab.json"
    static let supplementalSystemDictionaryFilename = "ÉcrituSecondVocab.json"
    // 補助語彙をビルド時に畳んだもの(SupplementalVocabCompactStore の直列化形式 ECCS1。3030)。
    // あればこちらを読み、無ければ上の JSON へ落ちる
    static let supplementalSystemDictionaryCompactFilename = "ÉcrituSecondVocab.eccs"
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

    // 集合は使い回す(3200)。ここは供給段の最内で、11 かなの打鍵 1 回に 165 回呼ばれる。
    // 毎回 Set を作ると確保だけで打鍵あたり 165 回(実測の _SetStorage.allocate 214 回の大半)になる
    private static let normalisedSources: Set<String> = [KanaKanjiCandidateSourceTag.normalized]
    private static let surfaceSources: Set<String> = [KanaKanjiCandidateSourceTag.surface]

    var requiredSystemSources: Set<String>? {
        switch self {
        case .normalise:
            return Self.normalisedSources
        case .surface:
            return Self.surfaceSources
        case .lesDeux:
            return nil
        }
    }
}

// 旧字体・異体字の抑制の小分類(コンテナー設定で個別にオン/オフ。2991)。
// 人名(Sudachi の姓/名)は分類に関わらず常に対象外 — 小野澤/千惠/眞子 は消さない。
enum ScriptVariantSuppressionCategory: String, CaseIterable {
    case kyujitai          // 旧字体(康熙字体): 氣→気、會→会、變→変
    case itaiji            // 異体字(印刷標準字体レベルの差): 飜→翻、每→毎、步→歩
    case ryakuji           // 略字: 仝→同、卆→卒
    case confusable        // 紛らわしい別字: 聯→連、聨→連
    case personNameVariant // 人名で生きている異体字: 邊→辺、龍→竜、嶋→島(初期設定オフ)

    // 初期設定で抑制する分類(人名で生きている異体字だけオフ)
    static let defaultEnabled: Set<ScriptVariantSuppressionCategory> = [
        .kyujitai, .itaiji, .ryakuji, .confusable
    ]

    var settingsKey: String {
        "scriptVariantSuppress" + rawValue.prefix(1).uppercased() + rawValue.dropFirst()
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
            // 前後に空白が無ければ Foundation の trimming(候補 1 件ごとに NSString を経由して確保)を通さない(3096)
            let needsTrimming = candidate.first.map { $0.isWhitespace || $0.isNewline } ?? false
                || candidate.last.map { $0.isWhitespace || $0.isNewline } ?? false
            let trimmed = needsTrimming ? candidate.trimmingCharacters(in: .whitespacesAndNewlines) : candidate
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else {
                continue
            }
            result.append(keepingOriginalText ? candidate : trimmed)
        }
        return result
    }
}
