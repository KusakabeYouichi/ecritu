import Foundation

// 数詞+助数詞(にまい/ひとけた/だいにかい)の表記の出し方(コンテナー設定 X.18。3702)。
// アラビア数字(2枚)と漢数字(二枚)のどちらを先に出すか、片方だけにするか。
// 辞書に語としてある 一枚/三本 は設定に関わらず出る(生成でなく辞書語)
enum NumeralStylePreference: String, CaseIterable {
    case arabicFirst
    case kanjiFirst
    case arabicOnly
    case kanjiOnly

    // 戦略的初期設定=アラビア数字だけ、保守的=漢数字が先、現代的=アラビア数字が先(ユーザ指定 3702)
    static let strategicDefault: NumeralStylePreference = .arabicOnly
    static let conservativeDefault: NumeralStylePreference = .kanjiFirst
    static let contemporaryDefault: NumeralStylePreference = .arabicFirst

    static func decode(_ raw: String?) -> NumeralStylePreference {
        raw.flatMap(NumeralStylePreference.init(rawValue:)) ?? strategicDefault
    }

    var includesArabic: Bool { self != .kanjiOnly }
    var includesKanji: Bool { self != .arabicOnly }
    var kanjiBeforeArabic: Bool { self == .kanjiFirst || self == .kanjiOnly }

    var title: String {
        switch self {
        case .arabicFirst: return "アラビア数字が先"
        case .kanjiFirst: return "漢数字が先"
        case .arabicOnly: return "アラビア数字だけ"
        case .kanjiOnly: return "漢数字だけ"
        }
    }
}
