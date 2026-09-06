import Foundation

// 送り仮名の許容形(終る/申込む/届 など)の扱い(2820)。『送り仮名の付け方』(1973 年内閣告示、1981 改正)の
// 許容をグループに分け、グループごとに 本則だけ / 本則を先に許容も / 許容を先に を選ぶ。両ターゲットに同梱。
enum OkuriganaVariantGroup: String, CaseIterable, Identifiable {
    // 通則1・2 の許容: 活用語尾の前の音を送る/省く(終わる⇄終る、行う⇄行なう)
    case stemInternal = "stem"
    // 通則6 の許容: 複合語の前部要素の送り仮名を省く(取り扱う⇄取扱う、申し込む⇄申込む)
    case compoundFront = "compound"
    // 通則4 の許容: 連用形から転じた名詞の送り仮名を省く(届け⇄届、願い⇄願)
    case nominalized = "noun"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stemInternal: return "語幹の中の送り仮名"
        case .compoundFront: return "複合語の前部要素"
        case .nominalized: return "名詞化の省略"
        }
    }

    var examples: String {
        switch self {
        case .stemInternal: return "終わる⇄終る、変わる⇄変る、起こる⇄起る、行う⇄行なう、表す⇄表わす"
        case .compoundFront: return "取り扱う⇄取扱う、申し込む⇄申込む、打ち合わせ⇄打合せ、乗り換え⇄乗換え"
        case .nominalized: return "届け⇄届、願い⇄願、曇り⇄曇、答え⇄答"
        }
    }
}

enum OkuriganaVariantMode: String, CaseIterable, Identifiable {
    case standardOnly = "standardOnly"     // 本則だけ(許容形は候補に出さない)
    case standardFirst = "standardFirst"   // 本則を先に、許容形も出す
    case permittedFirst = "permittedFirst" // 許容形を先に

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standardOnly: return "本則だけ"
        case .standardFirst: return "本則を先に"
        case .permittedFirst: return "許容を先に"
        }
    }
}

struct OkuriganaVariantPreference: Equatable {
    var modes: [OkuriganaVariantGroup: OkuriganaVariantMode]

    // 戦略的初期設定(ユーザ指定 2820): 許容形は全グループ出さない。保守的初期設定(作者の実運用)は本則を先に許容も出す
    static let `default` = OkuriganaVariantPreference(modes: [
        .stemInternal: .standardOnly, .compoundFront: .standardOnly, .nominalized: .standardOnly
    ])
    static let conservative = OkuriganaVariantPreference(modes: [
        .stemInternal: .standardFirst, .compoundFront: .standardFirst, .nominalized: .standardFirst
    ])

    func mode(for group: OkuriganaVariantGroup) -> OkuriganaVariantMode {
        modes[group] ?? .standardOnly
    }

    // 永続形式: "stem:standardFirst,compound:standardFirst,noun:standardFirst"
    var encoded: String {
        OkuriganaVariantGroup.allCases.map { "\($0.rawValue):\(mode(for: $0).rawValue)" }.joined(separator: ",")
    }

    static func decode(_ encoded: String?) -> OkuriganaVariantPreference {
        guard let encoded, !encoded.isEmpty else {
            return .default
        }
        var modes = OkuriganaVariantPreference.default.modes
        for token in encoded.split(separator: ",") {
            let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                let group = OkuriganaVariantGroup(rawValue: parts[0]),
                let mode = OkuriganaVariantMode(rawValue: parts[1]) else {
                continue
            }
            modes[group] = mode
        }
        return OkuriganaVariantPreference(modes: modes)
    }
}
