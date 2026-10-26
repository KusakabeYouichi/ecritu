import Foundation

// 同音の漢字による書きかえ(醗酵⇄発酵、廻転⇄回転、衣裳⇄衣装)の扱い(3422)。表は KakikaeTable(生成)。
// 両ターゲットに同梱。値は共有 UserDefaults の kakikaePreference に rawValue で保存する
enum KakikaePreference: String, CaseIterable, Identifiable {
    case beforeOnly = "beforeOnly"           // 本来の漢字だけ(臆測/醗酵)
    case afterOnly = "afterOnly"             // 常用漢字だけ(憶測/発酵)
    case bothBeforeFirst = "bothBeforeFirst" // 両方、本来の漢字を先に
    case bothAfterFirst = "bothAfterFirst"   // 両方、常用漢字を先に

    var id: String { rawValue }

    var title: String {
        switch self {
        case .beforeOnly: return "本来の漢字だけ"
        case .afterOnly: return "常用漢字だけ"
        case .bothBeforeFirst: return "両方(本来の漢字を先に)"
        case .bothAfterFirst: return "両方(常用漢字を先に)"
        }
    }

    // 戦略的初期設定(組み込みの標準値。ユーザ指定 3422)
    static let strategicDefault: KakikaePreference = .beforeOnly
    // 値がまだ無い端末(この設定より前から使っている人)に 1 回だけ書き込む値。キーボードが値を読めないときもこれ。
    // 以前から本来の漢字を先頭にしていた語(醗酵/日蝕/棲息。ユーザ指定)を変えない(ユーザ指定 3422)
    static let existingInstallDefault: KakikaePreference = .bothBeforeFirst

    static func decode(_ rawValue: String?) -> KakikaePreference {
        rawValue.flatMap(KakikaePreference.init(rawValue:)) ?? existingInstallDefault
    }

    var showsBefore: Bool { self != .afterOnly }
    var showsAfter: Bool { self != .beforeOnly }
    var prefersBefore: Bool { self == .beforeOnly || self == .bothBeforeFirst }

    // 例外グループ(日常語): 日常ではほぼ常用漢字側だけを使う組。設定(本来の漢字だけ/本来の漢字を先に)にかかわらず
    // 常用漢字を先にして本来の漢字も後ろに出す(了解 が 諒解 の下になる報告 3611、回復/恢復 3635、連想/聯想 3644)。
    // スイッチ kakikaeEverydayException がオフなら例外にせず、設定どおり(戦略的初期設定はオフ)
    static let everydayAfterFirstPairs: Set<String> = ["了解", "了承", "諒解", "諒承", "回復", "恢復", "連想", "聯想", "制御", "制禦", "制馭", "生姜", "生薑", "区画", "区劃",
                                                           "連絡", "聯絡", "台風", "颱風", "抜粋", "抜萃", "注文", "註文"]  // 区画/区劃(ユーザ指定 3747)、連絡/台風/抜粋(ユーザ指定 3778)、注文(ユーザ指定 3573)

    func demotingEverydayPair(for surface: String, enabled: Bool = true) -> KakikaePreference {
        guard enabled, self == .bothBeforeFirst || self == .beforeOnly,
            Self.everydayAfterFirstPairs.contains(where: { surface.contains($0) }) else {
            return self
        }
        return .bothAfterFirst
    }
}
