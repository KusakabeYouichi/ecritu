import Foundation

// 数詞+助数詞(にまい/ひとけた/だいにかい)の表記の出し方(コンテナー設定 X.13。3702)。
// アラビア数字(2枚)と漢数字(二枚)のどちらを先に出すか、片方だけにするか。
// 辞書・seed に語としてある 一枚/三人 も同じ組(1枚/3人)として設定に従う。数える意味でない語(一杯/一層/一門 など)は対象外
// (KanaKanjiConverter.numeralStyleExcludedKanjiForms)
public enum NumeralStylePreference: String, CaseIterable {
    case arabicFirst
    case kanjiFirst
    case arabicOnly
    case kanjiOnly

    // 戦略的初期設定=アラビア数字だけ、保守的=漢数字が先、現代的=アラビア数字が先(ユーザ指定 3702)
    public static let strategicDefault: NumeralStylePreference = .arabicOnly
    public static let conservativeDefault: NumeralStylePreference = .kanjiFirst
    public static let contemporaryDefault: NumeralStylePreference = .arabicFirst

    public static func decode(_ raw: String?) -> NumeralStylePreference {
        raw.flatMap(NumeralStylePreference.init(rawValue:)) ?? strategicDefault
    }

    public var includesArabic: Bool { self != .kanjiOnly }
    public var includesKanji: Bool { self != .arabicOnly }
    public var kanjiBeforeArabic: Bool { self == .kanjiFirst || self == .kanjiOnly }

    public var title: String {
        switch self {
        case .arabicFirst: return "アラビア数字が先"
        case .kanjiFirst: return "漢数字が先"
        case .arabicOnly: return "アラビア数字だけ"
        case .kanjiOnly: return "漢数字だけ"
        }
    }
}
