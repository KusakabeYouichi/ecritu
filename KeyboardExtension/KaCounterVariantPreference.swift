import Foundation

// 助数詞の「か」の表記(1か所/数か月/何か国 の か・カ・ヶ・ヵ・箇・個・ケ)をどれを出し、どの順で並べるかの設定。
// コンテナーアプリで並べ替え+オン/オフし、キーボード拡張は共有 UserDefaults の文字列を読む。
// 両ターゲットに同梱する(2816)。
enum KaCounterVariant: String, CaseIterable, Identifiable, Codable {
    case hiragana = "か"
    case katakana = "カ"
    case smallKe = "ヶ"
    case smallKa = "ヵ"
    case kanji = "箇"
    case ko = "個"
    case ke = "ケ"

    var id: String { rawValue }
    var character: Character { rawValue.first! }

    var title: String {
        switch self {
        case .hiragana: return "か(1か所)"
        case .katakana: return "カ(1カ所)"
        case .smallKe: return "ヶ(1ヶ所)"
        case .smallKa: return "ヵ(1ヵ所)"
        case .kanji: return "箇(1箇所)"
        case .ko: return "個(1個所)"
        case .ke: return "ケ(1ケ所)"
        }
    }

    static let allCharacters: Set<Character> = Set(allCases.map(\.character))
}

struct KaCounterVariantPreference: Equatable {
    // 全 7 表記の並び(オフのものも位置を保つ)
    var order: [KaCounterVariant]
    var enabled: Set<KaCounterVariant>

    // 初期設定(戦略的初期設定。ユーザ指定 2817): か だけを出す。並びは か → 箇 → ヶ → カ → ヵ → 個 → ケ
    // (公用文の か/箇 が先。個所/ケ所 は現代の一般的な表記ではなく、ケ は地名(六ケ所)に残る)。
    // 保守的初期設定(作者の実運用)は か・箇・ヶ・カ をオン(ContentView+LogoMenu の conservativePresetValues)
    static let `default` = KaCounterVariantPreference(
        order: [.hiragana, .kanji, .smallKe, .katakana, .smallKa, .ko, .ke],
        enabled: [.hiragana]
    )
    static let conservative = KaCounterVariantPreference(
        order: KaCounterVariantPreference.default.order,
        enabled: [.hiragana, .kanji, .smallKe, .katakana]
    )

    // オンの表記だけを設定順に
    var enabledInOrder: [KaCounterVariant] {
        order.filter { enabled.contains($0) }
    }

    // 永続形式: "か,カ,ヶ,ヵ,箇,-個,-ケ"(- 接頭がオフ)。欠けた表記は末尾にオフで補う
    var encoded: String {
        order.map { (enabled.contains($0) ? "" : "-") + $0.rawValue }.joined(separator: ",")
    }

    init(order: [KaCounterVariant], enabled: Set<KaCounterVariant>) {
        self.order = order
        self.enabled = enabled
    }

    init(encoded: String) {
        var order: [KaCounterVariant] = []
        var enabled = Set<KaCounterVariant>()
        for token in encoded.split(separator: ",") {
            let isDisabled = token.hasPrefix("-")
            let raw = isDisabled ? String(token.dropFirst()) : String(token)
            guard let variant = KaCounterVariant(rawValue: raw), !order.contains(variant) else {
                continue
            }
            order.append(variant)
            if !isDisabled {
                enabled.insert(variant)
            }
        }
        for variant in KaCounterVariant.allCases where !order.contains(variant) {
            order.append(variant)
        }
        self.order = order
        self.enabled = enabled
    }

    static func decode(_ encoded: String?) -> KaCounterVariantPreference {
        guard let encoded, !encoded.isEmpty else {
            return .default
        }
        return KaCounterVariantPreference(encoded: encoded)
    }
}
