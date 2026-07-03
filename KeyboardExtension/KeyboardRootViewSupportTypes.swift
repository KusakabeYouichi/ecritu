import Foundation
import SwiftUI
import UIKit

enum KeyboardThemePalette {
    static let keyLabel = Color(uiColor: .label)
    static let keyLabelSecondary = Color(uiColor: .secondaryLabel)
    static let keyLabelTertiary = Color(uiColor: .tertiaryLabel)

    static let keyBackground = Color(uiColor: .secondarySystemBackground).opacity(0.92)
    static let keyBackgroundDisabled = Color(uiColor: .tertiarySystemFill).opacity(0.92)
    static let keyBorder = Color(uiColor: .separator).opacity(0.42)
    static let keyBorderEmphasis = Color(uiColor: .separator).opacity(0.62)
    static let keyStrokeOnAccent = Color.white.opacity(0.32)

    static let categoryButtonBackground = Color(uiColor: .tertiarySystemBackground).opacity(0.9)
    static let categoryButtonBackgroundSelected = Color(uiColor: .secondarySystemBackground)

    static let candidateHeaderChipBackground = Color(uiColor: .secondarySystemBackground).opacity(0.82)
    static let candidateHeaderSubtleBackground = Color(uiColor: .secondarySystemBackground).opacity(0.68)
    static let candidateHeaderPlaceholderBackground = Color(uiColor: .tertiarySystemFill).opacity(0.9)
    static let candidateHeaderBorder = Color(uiColor: .separator).opacity(0.38)

    static let longPressPanelText = Color(uiColor: .label)
    static let longPressPanelCellBackground = Color(uiColor: .tertiarySystemBackground)
    static let longPressPanelCellHighlight = Color(
        uiColor: UIColor { trait in
            if trait.userInterfaceStyle == .dark {
                return UIColor(red: 0.24, green: 0.33, blue: 0.49, alpha: 1.0)
            }

            return UIColor(red: 0.84, green: 0.89, blue: 1.0, alpha: 1.0)
        }
    )
    static let longPressPanelBackground = Color(uiColor: .secondarySystemBackground)
    static let longPressPanelBorder = Color(uiColor: .separator).opacity(0.45)
    static let longPressPanelShadow = Color.black.opacity(0.18)

    static let pressFeedbackCircle = Color(
        uiColor: UIColor { trait in
            if trait.userInterfaceStyle == .dark {
                return UIColor.white.withAlphaComponent(0.18)
            }

            return UIColor.black.withAlphaComponent(0.15)
        }
    )
    static let pressFeedbackRounded = Color(
        uiColor: UIColor { trait in
            if trait.userInterfaceStyle == .dark {
                return UIColor.white.withAlphaComponent(0.14)
            }

            return UIColor.black.withAlphaComponent(0.12)
        }
    )
    static let pressFeedbackRoundedBorder = Color(
        uiColor: UIColor { trait in
            if trait.userInterfaceStyle == .dark {
                return UIColor.white.withAlphaComponent(0.2)
            }

            return UIColor.black.withAlphaComponent(0.16)
        }
    )
    static let thinDivider = Color(uiColor: .separator).opacity(0.5)

    static let iconHighlight = Color(uiColor: .systemBackground)
}

// iOS17+ でのみ ScrollView のクリップを無効化する(iOS16では従来どおりクリップ)。
private struct SymbolScrollClipDisabledModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.scrollClipDisabled()
        } else {
            content
        }
    }
}

extension KeyboardRootView {
    // 宣言順=カテゴリボタンの表示順(顔→食べ物→動物→行動→オブジェクト→乗り物→国旗→シンボル)。
    // rawValue は設定(kanaPostModifierEmptyTapEmojiCategoryID)に永続化されているため、
    // 並べ替えても歴史的な値を明示指定して互換を維持する。
    enum EmojiCategory: Int, CaseIterable, Identifiable {
        case people = 0
        case food = 2
        case animals = 1
        case activities = 3
        case objects = 5
        case travel = 4
        case flags = 7
        case symbols = 6

        var id: Int { rawValue }

        var icon: String {
            switch self {
            case .people: return "😀"
            case .animals: return "🦆"
            case .food: return "🍷"
            case .activities: return "🏀"
            case .travel: return "🚗"
            case .objects: return "💡"
            case .symbols: return "❤️"
            case .flags: return "🇫🇷"
            }
        }

        var frenchName: String {
            switch self {
            case .people: return "Personnes"
            case .animals: return "Animaux et nature"
            case .food: return "Nourriture et boissons"
            case .activities: return "Activités"
            case .travel: return "Voyages et lieux"
            case .objects: return "Objets"
            case .symbols: return "Symboles"
            case .flags: return "Drapeaux"
            }
        }

        var emojis: [String] {
            switch self {
            case .people:
                return AppleEmojiCatalog.people
            case .animals:
                return AppleEmojiCatalog.nature
            case .food:
                return AppleEmojiCatalog.foodAndDrink
            case .activities:
                return AppleEmojiCatalog.activity
            case .travel:
                return AppleEmojiCatalog.travelAndPlaces
            case .objects:
                return AppleEmojiCatalog.objects
            case .symbols:
                return AppleEmojiCatalog.symbols
            case .flags:
                return AppleEmojiCatalog.flags
            }
        }

        // サブグループ(区切り線で仕切る)。単一セクションのカテゴリは区切り線なし。
        // 国旗は動的分割(国→領土→その他)のため emojiScrollContent 側で特別扱い。
        var sections: [[String]] {
            switch self {
            case .people:
                return AppleEmojiCatalog.peopleSections
            case .animals:
                return AppleEmojiCatalog.natureSections
            case .food:
                return AppleEmojiCatalog.foodAndDrinkSections
            case .activities:
                return AppleEmojiCatalog.activitySections
            case .travel:
                return AppleEmojiCatalog.travelAndPlacesSections
            case .objects, .symbols, .flags:
                return [emojis]
            }
        }
    }

    struct KaomojiCategory: Identifiable, Hashable {
        enum Kind: Hashable {
            case shortcut
            case existing
            case imported(String)
            case search
        }

        let kind: Kind

        var id: String {
            switch kind {
            case .shortcut:
                return "shortcut"
            case .existing:
                return "existing"
            case .imported(let name):
                return "imported:\(name)"
            case .search:
                return "search"
            }
        }

        var title: String {
            switch kind {
            case .shortcut:
                return "ショートカット"
            case .existing:
                return "基本"
            case .imported(let name):
                switch name {
                case "笑":
                    return "Sourire / Rire (笑顔)"
                case "かわいい":
                    return "Kawaii / Chou (かわいい)"
                case "照れ":
                    return "Timide (照れ・恥ずかしがり)"
                case "焦り":
                    return "Stress / Panique (焦り・緊張・パニック)"
                case "しょぼん":
                    return "Dé çu Dé primé (がっかり・しょぼん)"
                case "悲":
                    return "Triste (悲しい)"
                case "怒":
                    return "En colè re (怒り)"
                case "驚き":
                    return "Surprise (驚き)"
                case "くそねみ":
                    return "Dodo (くそねみ・超眠い・ねんね)"
                case "挨拶":
                    return "Coucou (やあ!・親しい挨拶)"
                case "ラブ":
                    return "Amour (ラブ・愛)"
                case "激しい":
                    return "Excité / Crazy (激しい・狂気)"
                case "うごき":
                    return "Action (アクシオン・動き)"
                case "キモい":
                    return "Bizarre (奇妙・キモい)"
                case "キャラ":
                    return "Hé ros (主人公・キャラ)"
                case "特殊":
                    return "Spé cial (特殊)"
                case "ライン":
                    return "Lignes (区切り線)"
                default:
                    return name
                }
            case .search:
                return "検索"
            }
        }

        var icon: String {
            switch kind {
            case .shortcut:
                return "⚡️"
            case .existing:
                return "🙂"
            case .imported(let name):
                switch name {
                case "キャラ":
                    return "🧑"
                case "ライン":
                    return "💬"
                case "挨拶":
                    return "🙋"
                case "キモい":
                    return "🤪"
                case "特殊":
                    return "✨"
                case "笑":
                    return "😂"
                case "焦り":
                    return "💦"
                case "かわいい":
                    return "🥰"
                case "驚き":
                    return "😲"
                case "怒":
                    return "😠"
                case "しょぼん":
                    return "😔"
                case "ラブ":
                    return "❤️"
                case "激しい":
                    return "💥"
                case "照れ":
                    return "😊"
                case "くそねみ":
                    return "😴"
                case "悲":
                    return "😢"
                case "うごき":
                    return "🏃"
                default:
                    return "🗂️"
                }
            case .search:
                return "🔎"
            }
        }
    }

    enum BasicSymbolOrder: String {
        case ascii
        case ebcdic
        case ansi
    }

    enum SymbolCategory: Int, CaseIterable, Identifiable {
        case basic
        case brackets
        case currency
        case units
        case math
        case arrows
        case enclosed

        var id: Int { rawValue }

        func icon(temperatureUnit: TemperatureUnitPreference) -> String {
            switch self {
            case .basic: return "!?"
            case .brackets: return "『』"
            case .currency: return "€"
            case .units: return temperatureUnit.primarySymbol
            case .math: return "∑"
            case .arrows: return "↗"
            case .enclosed: return "⓪"
            }
        }

        var frenchName: String {
            switch self {
            case .basic: return "Symboles de base"
            case .brackets: return "Parenthèses et guillemets"
            case .currency: return "Monnaies"
            case .units: return "Unités"
            case .math: return "Mathématiques"
            case .arrows: return "Flèches"
            case .enclosed: return "Caractères entourés"
            }
        }

        var tintColor: Color {
            switch self {
            case .basic:
                return Color(red: 0.16, green: 0.40, blue: 0.86)
            case .brackets:
                return Color(red: 0.08, green: 0.60, blue: 0.48)
            case .currency:
                return Color(red: 0.10, green: 0.66, blue: 0.32)
            case .units:
                return Color(red: 0.92, green: 0.50, blue: 0.14)
            case .math:
                return Color(red: 0.77, green: 0.30, blue: 0.23)
            case .arrows:
                return Color(red: 0.48, green: 0.36, blue: 0.87)
            case .enclosed:
                return Color(red: 0.88, green: 0.26, blue: 0.57)
            }
        }

        func symbols(
            basicOrder: BasicSymbolOrder,
            temperatureUnit: TemperatureUnitPreference
        ) -> [String] {
            switch self {
            case .basic:
                let baseSymbols: [String]
                switch basicOrder {
                case .ascii:
                    baseSymbols = Self.basicSymbolsASCII
                case .ebcdic:
                    baseSymbols = Self.basicSymbolsEBCDIC
                case .ansi:
                    baseSymbols = Self.basicSymbolsANSI
                }
                return baseSymbols + Self.basicSymbolsExtras
            case .brackets:
                return Self.bracketAndQuoteSymbols
            case .currency:
                return Self.currencySymbols + Self.bitcoinSymbols + Self.cryptoAlternativeSymbols
            case .units:
                return Self.unitSymbols(for: temperatureUnit)
            case .math:
                return Self.mathSymbols
            case .arrows:
                return Self.arrowSymbols
            case .enclosed:
                return Self.enclosedSymbols
            }
        }

        // ASCII punctuation in code point order.
        private static let basicSymbolsASCII: [String] = [
            "!", "\"", "#", "$", "%", "&", "'", "(", ")", "*", "+", ",", "-", ".", "/",
            ":", ";", "<", "=", ">", "?", "@", "[", "\\", "]", "^", "_", "`", "{", "|", "}", "~",
            "", "⌘", "☻", "・", "←", "↑", "→", "↓", "「", "」", "『", "』"
        ]

        private static let basicSymbolsEBCDIC: [String] = [
            ".", "<", "(", "+", "|", "&", "!", "$", "*", ")", ";", "-", "/", ",", "%", "_",
            ">", "?", "`", ":", "#", "@", "'", "=", "\"", "~", "^", "[", "]", "{", "}", "\\",
            "", "⌘", "☻", "・", "←", "↑", "→", "↓", "「", "」", "『", "』"
        ]

        private static let basicSymbolsANSI: [String] = [
            "!", "@", "#", "$", "%", "^", "&", "*",
            "(", ")", "-", "_", "=", "+", "[", "]",
            "{", "}", ";", ":", "'", "\"", ",", ".",
            "<", ">", "/", "?", "\\", "|", "`", "~",
            "", "⌘", "☻", "・", "←", "↑", "→", "↓", "「", "」", "『", "』"
        ]

        // basicカテゴリーの末尾に区切り線を挟んで配置する図形記号(16個)。
        static let basicSymbolsExtras: [String] = [
            "○", "●", "△", "▲", "▽", "▼", "□", "■",
            "◇", "◆", "☆", "★", "◎", "×", "※", "✓"
        ]

        private static let bracketAndQuoteSymbols: [String] = [
            "(", ")", "[", "]", "{", "}", "<", ">",
            "『", "』", "「", "」", "【", "】", "〔", "〕", "〈", "〉", "《", "》",
            "“", "”", "‘", "’", "«", "»", "‹", "›", "〝", "〟"
        ]

        private static let currencySymbols: [String] = [
            "€", "$", "¢", "£", "¥", "₩", "₹", "₽", "₺", "฿", "₫", "₴", "₦", "₱", "₡", "₲", "₵", "₭", "₸", "₮", "₰", "₪", "₾", "﷼"
        ]

        // 通貨カテゴリー末尾に区切り線を挟んで配置する暗号資産記号。
        static let bitcoinSymbols: [String] = ["₿"]

        // 専用記号を持たない暗号資産の代替表記。
        static let cryptoAlternativeSymbols: [String] = [
            "Ξ", "⟠", "Ł", "Ð", "₳", "₮", "✕"
        ]

        // 長押し中に吹き出し表示する通貨コード(ISO-4217)。¢・₰はISOコードを持たないため割り当てない。
        static let currencyISOCodes: [String: String] = [
            "€": "EUR", "$": "USD", "£": "GBP", "¥": "JPY", "₩": "KRW",
            "₹": "INR", "₽": "RUB", "₺": "TRY", "฿": "THB", "₫": "VND",
            "₴": "UAH", "₦": "NGN", "₱": "PHP", "₡": "CRC", "₲": "PYG",
            "₵": "GHS", "₭": "LAK", "₸": "KZT", "₮": "MNT", "₪": "ILS",
            "₾": "GEL", "﷼": "SAR"
        ]

        // 長押し中に吹き出し表示する暗号資産のティッカーシンボル。
        static let cryptoTickerSymbols: [String: String] = [
            "₿": "BTC", "Ξ": "ETH", "⟠": "ETH", "Ł": "LTC",
            "Ð": "DOGE", "₳": "ADA", "₮": "USDT", "✕": "XRP"
        ]

        // 補助単位(ISO通貨コードを持たない)。吹き出しは別色・コードでなく名称を表示する。
        static let currencySubunitLabels: [String: String] = [
            "¢": "cent", "₰": "Pfennig"
        ]

        private static let unitSymbolsTail: [String] = [
            "°", "′", "″", "%", "‰", "μ", "Ω", "ℓ", "㎜", "㎝", "㎞", "㎡", "㎢", "㎥", "㎎", "㎏", "㏄", "㎖", "㎗", "㎐", "㎑", "㎒", "㎓"
        ]

        private static func unitSymbols(for temperatureUnit: TemperatureUnitPreference) -> [String] {
            switch temperatureUnit {
            case .celsius:
                return ["℃", "℉"] + unitSymbolsTail
            case .fahrenheit:
                return ["℉", "℃"] + unitSymbolsTail
            }
        }

        private static let mathSymbols: [String] = [
            "+", "-", "±", "×", "÷", "=", "≠", "≈", "≡", "<", ">", "≤", "≥", "¬", "∧", "∨", "⊻",
            "∀", "∃", "∞", "√", "∛", "∜", "∑", "∏", "∫", "∬", "∮", "∂", "∇",
            "∈", "∉", "∋", "∌", "∩", "∪", "⊂", "⊃", "⊆", "⊇", "⊄", "⊅", "∝", "∴", "∵", "⊥", "∠"
        ]

        private static let arrowSymbols: [String] = [
            "←", "↑", "→", "↓", "↔", "↕", "↖", "↗", "↘", "↙",
            "⇐", "⇑", "⇒", "⇓", "⇔", "⇕", "↩", "↪",
            "➔", "➜", "➝", "➞", "➟", "➠"
        ]

        private static let enclosedSymbols: [String] = [
            "©", "®", "⓪", "①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩", "⑪", "⑫", "⑬", "⑭", "⑮", "⑯", "⑰", "⑱", "⑲", "⑳",
            "㉑", "㉒", "㉓", "㉔", "㉕", "㉖", "㉗", "㉘", "㉙", "㉚",
            "Ⓐ", "Ⓑ", "Ⓒ", "Ⓓ", "Ⓔ", "Ⓕ", "Ⓖ", "Ⓗ", "Ⓘ", "Ⓙ", "Ⓚ", "Ⓛ", "Ⓜ", "Ⓝ", "Ⓞ", "Ⓟ", "Ⓠ", "Ⓡ", "Ⓢ", "Ⓣ", "Ⓤ", "Ⓥ", "Ⓦ", "Ⓧ", "Ⓨ", "Ⓩ",
            "ⓐ", "ⓑ", "ⓒ", "ⓓ", "ⓔ", "ⓕ", "ⓖ", "ⓗ", "ⓘ", "ⓙ", "ⓚ", "ⓛ", "ⓜ", "ⓝ", "ⓞ", "ⓟ", "ⓠ", "ⓡ", "ⓢ", "ⓣ", "ⓤ", "ⓥ", "ⓦ", "ⓧ", "ⓨ", "ⓩ"
        ]
    }

    enum KanaModeSwitcherAction: String {
        case emoji
        case kaomoji
        case symbols

        var keyLabel: String {
            switch self {
            case .emoji:
                return "☺︎"
            case .kaomoji:
                return "^_^"
            case .symbols:
                return "⌘"
            }
        }
    }

    enum LandscapeCandidateSide: String {
        case left
        case right
    }

    enum LandscapeLatinSuggestionMode: String {
        case sidebar
        case off
    }

    enum AccentPalette: String {
        case tuile
        case emeraude

        var color: Color {
            switch self {
            case .tuile:
                return Color(red: 136.0 / 255.0, green: 63.0 / 255.0, blue: 53.0 / 255.0)
            case .emeraude:
                return Color(red: 0.06, green: 0.73, blue: 0.56)
            }
        }
    }

    enum KeyboardBackgroundTheme: String {
        case bleu
        case sakura

        func gradientStops(for colorScheme: ColorScheme) -> [Gradient.Stop] {
            switch self {
            case .bleu:
                if colorScheme == .dark {
                    return [
                        .init(color: Color(red: 0.12, green: 0.14, blue: 0.18), location: 0.0),
                        .init(color: Color(red: 0.12, green: 0.21, blue: 0.30), location: 0.34),
                        .init(color: Color(red: 0.10, green: 0.17, blue: 0.25), location: 1.0)
                    ]
                }

                return [
                    .init(color: Color(red: 0.89, green: 0.90, blue: 0.92), location: 0.0),
                    .init(color: Color(red: 0.8, green: 0.86, blue: 0.95), location: 0.34),
                    .init(color: Color(red: 0.9, green: 0.95, blue: 1.0), location: 1.0)
                ]
            case .sakura:
                if colorScheme == .dark {
                    return [
                        .init(color: Color(red: 0.13, green: 0.13, blue: 0.16), location: 0.0),
                        .init(color: Color(red: 0.24, green: 0.18, blue: 0.23), location: 0.34),
                        .init(color: Color(red: 0.18, green: 0.14, blue: 0.20), location: 1.0)
                    ]
                }

                return [
                    .init(color: Color(red: 0.89, green: 0.90, blue: 0.92), location: 0.0),
                    .init(color: Color(red: 0.95, green: 0.84, blue: 0.88), location: 0.34),
                    .init(color: Color(red: 1.0, green: 0.94, blue: 0.96), location: 1.0)
                ]
            }
        }
    }

    struct KaomojiRowLayout {
        let items: [String]
        let spacing: CGFloat
    }
}

    struct KeyboardRootEmojiKeyboardSectionView: View {
        @Binding var selectedEmojiCategory: KeyboardRootView.EmojiCategory
        let keyboardRowSpacing: CGFloat
        let emojiGridColumns: [GridItem]
        let emojiGridSpacing: CGFloat
        let compactEmojiKeyHeight: CGFloat
        let mainFlickKeyHeight: CGFloat
        let fourRowAlignedTopContentHeight: CGFloat
        let fourRowAlignedClusterHeight: CGFloat
        let keyRepeatInitialDelay: TimeInterval
        let keyRepeatInterval: TimeInterval
        let onTextInput: (String) -> Void
        let onSwitchToKana: () -> Void
        let onDeleteBackward: () -> Void

        var body: some View {
            VStack(spacing: keyboardRowSpacing) {
                ScrollView(.vertical, showsIndicators: false) {
                    emojiScrollContent
                        .padding(.vertical, 2)
                }
                .frame(height: fourRowAlignedTopContentHeight)
                // 国旗の長押し吹き出しが最上段で見切れないようクリップを解除(iOS17+)。
                .modifier(SymbolScrollClipDisabledModifier())

                HStack(spacing: keyboardRowSpacing) {
                    ActionKeyButton(
                        title: "あい",
                        fixedWidth: 56,
                        action: onSwitchToKana
                    )
                    .frame(height: mainFlickKeyHeight)

                    ForEach(KeyboardRootView.EmojiCategory.allCases, id: \.self) { category in
                        EmojiCategoryKeyButton(
                            icon: category.icon,
                            isSelected: selectedEmojiCategory == category,
                            action: { selectedEmojiCategory = category }
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: mainFlickKeyHeight)
                    }

                    ActionKeyButton(
                        title: "⌫",
                        accessibilityLabel: "削除",
                        fontSize: 26,
                        fixedWidth: 56,
                        repeatsWhileHolding: true,
                        repeatInitialDelay: keyRepeatInitialDelay,
                        repeatInterval: keyRepeatInterval,
                        action: onDeleteBackward
                    )
                    .frame(height: mainFlickKeyHeight)
                }
                .frame(height: mainFlickKeyHeight)
            }
            .frame(height: fourRowAlignedClusterHeight, alignment: .top)
        }

        // 複数セクションのカテゴリー(顔/食べ物/動物/行動/乗り物)は、サブグループの間に
        // 区切り線を挟む。国旗は動的分割(国→領土→その他)のため特別扱い。
        @ViewBuilder
        private var emojiScrollContent: some View {
            let sections = selectedEmojiCategory.sections
            if selectedEmojiCategory != .flags, sections.count > 1 {
                LazyVStack(alignment: .leading, spacing: keyboardRowSpacing) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                        if index > 0 {
                            emojiSectionDivider
                        }
                        emojiGrid(section)
                    }
                }
            } else if selectedEmojiCategory == .flags {
                let territorySet = AppleEmojiCatalog.flagOverseasTerritories
                let nonCountrySet = Set(AppleEmojiCatalog.flagNonCountryNames.keys)
                let all = selectedEmojiCategory.emojis
                // {普通の国 → 海外領土・属領 → その他の旗} の順に区切り線で分ける。
                let countryFlags = all.filter { !territorySet.contains($0) && !nonCountrySet.contains($0) }
                let territoryFlags = all.filter { territorySet.contains($0) }
                let otherFlags = all.filter { nonCountrySet.contains($0) }
                LazyVStack(alignment: .leading, spacing: keyboardRowSpacing) {
                    emojiGrid(countryFlags)
                    if !territoryFlags.isEmpty {
                        emojiSectionDivider
                        emojiGrid(territoryFlags)
                    }
                    if !otherFlags.isEmpty {
                        emojiSectionDivider
                        emojiGrid(otherFlags)
                    }
                }
            } else {
                emojiGrid(selectedEmojiCategory.emojis)
            }
        }

        private var emojiSectionDivider: some View {
            Rectangle()
                .fill(KeyboardThemePalette.thinDivider)
                .frame(height: 1)
                .padding(.vertical, 2)
        }

        private func emojiGrid(_ emojis: [String]) -> some View {
            LazyVGrid(columns: emojiGridColumns, spacing: emojiGridSpacing) {
                ForEach(Array(emojis.enumerated()), id: \.offset) { _, emoji in
                    let isFlags = selectedEmojiCategory == .flags
                    let countryName = isFlags ? AppleEmojiCatalog.flagOfficialNames[emoji] : nil
                    let nonCountryName = isFlags ? AppleEmojiCatalog.flagNonCountryNames[emoji] : nil
                    EmojiKeyButton(
                        emoji: emoji,
                        longPressLabel: countryName ?? nonCountryName,
                        longPressLabelKind: (countryName == nil && nonCountryName != nil) ? .alternate : .standard
                    ) {
                        onTextInput(emoji)
                    }
                    .frame(height: compactEmojiKeyHeight)
                }
            }
        }
    }

    struct KeyboardRootSymbolKeyboardSectionView: View {
        @Binding var selectedSymbolCategory: KeyboardRootView.SymbolCategory
        let basicSymbolOrder: KeyboardRootView.BasicSymbolOrder
        let temperatureUnit: TemperatureUnitPreference
        let keyboardRowSpacing: CGFloat
        let symbolGridColumns: [GridItem]
        let emojiGridSpacing: CGFloat
        let compactEmojiKeyHeight: CGFloat
        let mainFlickKeyHeight: CGFloat
        let fourRowAlignedTopContentHeight: CGFloat
        let fourRowAlignedClusterHeight: CGFloat
        let keyRepeatInitialDelay: TimeInterval
        let keyRepeatInterval: TimeInterval
        let onTextInput: (String) -> Void
        let onSwitchToKana: () -> Void
        let onDeleteBackward: () -> Void

        var body: some View {
            VStack(spacing: keyboardRowSpacing) {
                ScrollView(.vertical, showsIndicators: false) {
                    symbolCategoryContentView
                        .padding(.vertical, 2)
                }
                .frame(height: fourRowAlignedTopContentHeight)
                // 通貨記号の長押し吹き出しが最上段で見切れないようクリップを解除(iOS17+)。
                .modifier(SymbolScrollClipDisabledModifier())

                HStack(spacing: keyboardRowSpacing) {
                    ActionKeyButton(
                        title: "あい",
                        fixedWidth: 56,
                        action: onSwitchToKana
                    )
                    .frame(height: mainFlickKeyHeight)

                    ForEach(KeyboardRootView.SymbolCategory.allCases, id: \.self) { category in
                        SymbolCategoryKeyButton(
                            icon: category.icon(temperatureUnit: temperatureUnit),
                            tintColor: category.tintColor,
                            isSelected: selectedSymbolCategory == category,
                            accessibilityLabel: category.frenchName,
                            action: { selectedSymbolCategory = category }
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: mainFlickKeyHeight)
                    }

                    ActionKeyButton(
                        title: "⌫",
                        accessibilityLabel: "削除",
                        fontSize: 26,
                        fixedWidth: 56,
                        repeatsWhileHolding: true,
                        repeatInitialDelay: keyRepeatInitialDelay,
                        repeatInterval: keyRepeatInterval,
                        action: onDeleteBackward
                    )
                    .frame(height: mainFlickKeyHeight)
                }
                .frame(height: mainFlickKeyHeight)
            }
            .frame(height: fourRowAlignedClusterHeight, alignment: .top)
        }

        @ViewBuilder
        private var symbolCategoryContentView: some View {
            let symbols = selectedSymbolCategory.symbols(
                basicOrder: basicSymbolOrder,
                temperatureUnit: temperatureUnit
            )

            switch selectedSymbolCategory {
            case .basic:
                let extrasCount = KeyboardRootView.SymbolCategory.basicSymbolsExtras.count
                let middleCount = 12  // ⌘ ☻ ・ ←↑→↓ 「」『』 などの第2セクション
                let extrasStart = max(0, symbols.count - extrasCount)
                let middleStart = max(0, extrasStart - middleCount)
                let leadingSymbols = Array(symbols.prefix(middleStart))
                let middleSymbols = Array(symbols[middleStart..<extrasStart])
                let trailingSymbols = Array(symbols.suffix(extrasCount))
                symbolGridSections([leadingSymbols, middleSymbols, trailingSymbols])

            case .currency:
                let cryptoCount = KeyboardRootView.SymbolCategory.cryptoAlternativeSymbols.count
                let bitcoinCount = KeyboardRootView.SymbolCategory.bitcoinSymbols.count
                let cryptoStart = max(0, symbols.count - cryptoCount)
                let bitcoinStart = max(0, cryptoStart - bitcoinCount)
                let fiatSymbols = Array(symbols.prefix(bitcoinStart))
                let bitcoinSymbols = Array(symbols[bitcoinStart..<cryptoStart])
                let cryptoSymbols = Array(symbols.suffix(cryptoCount))
                let isoCodes = KeyboardRootView.SymbolCategory.currencyISOCodes
                let subunits = KeyboardRootView.SymbolCategory.currencySubunitLabels
                let fiatLabels = isoCodes.merging(subunits) { current, _ in current }
                let tickers = KeyboardRootView.SymbolCategory.cryptoTickerSymbols
                symbolGridSectionsLabeled([
                    (fiatSymbols, fiatLabels),
                    (bitcoinSymbols, tickers),
                    (cryptoSymbols, tickers)
                ])

            case .enclosed:
                let numberStart = symbols.firstIndex(of: "⓪")
                let upperStart = symbols.firstIndex(of: "Ⓐ")
                let lowerStart = symbols.firstIndex(of: "ⓐ")

                if let numberStart,
                    let upperStart,
                    let lowerStart,
                    numberStart < upperStart,
                    upperStart < lowerStart {
                    let markSymbols = Array(symbols[..<numberStart])
                    let numberSymbols = Array(symbols[numberStart..<upperStart])
                    let upperSymbols = Array(symbols[upperStart..<lowerStart])
                    let lowerSymbols = Array(symbols[lowerStart...])
                    symbolGridSections([markSymbols, numberSymbols, upperSymbols, lowerSymbols])
                } else {
                    symbolGridSection(symbols)
                }

            default:
                symbolGridSection(symbols)
            }
        }

        @ViewBuilder
        private func symbolGridSections(_ sections: [[String]]) -> some View {
            LazyVStack(alignment: .leading, spacing: keyboardRowSpacing) {
                ForEach(Array(sections.enumerated()), id: \.offset) { index, sectionSymbols in
                    symbolGridSection(sectionSymbols)

                    if index + 1 < sections.count {
                        let nextSectionSymbols = sections[index + 1]
                        if !sectionSymbols.isEmpty && !nextSectionSymbols.isEmpty {
                            symbolSectionDivider
                        }
                    }
                }
            }
        }

        @ViewBuilder
        private func symbolGridSectionsLabeled(
            _ sections: [(symbols: [String], labels: [String: String])]
        ) -> some View {
            LazyVStack(alignment: .leading, spacing: keyboardRowSpacing) {
                ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                    symbolGridSection(section.symbols, labels: section.labels)

                    if index + 1 < sections.count {
                        let nextSectionSymbols = sections[index + 1].symbols
                        if !section.symbols.isEmpty && !nextSectionSymbols.isEmpty {
                            symbolSectionDivider
                        }
                    }
                }
            }
        }

        private func symbolGridSection(
            _ symbols: [String],
            labels: [String: String]? = nil
        ) -> some View {
            let symbolFont: Font = selectedSymbolCategory == .enclosed
                ? .custom("HiraginoSans-W6", size: 24)
                : .system(size: 24, weight: .semibold, design: .rounded)

            return LazyVGrid(columns: symbolGridColumns, spacing: emojiGridSpacing) {
                ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                    let kind: SymbolInspectBubbleKind = KeyboardRootView.SymbolCategory.currencySubunitLabels[symbol] != nil
                        ? .subunit
                        : .standard
                    SymbolKeyButton(
                        symbol: symbol,
                        font: symbolFont,
                        longPressLabel: labels?[symbol],
                        longPressLabelKind: kind
                    ) {
                        onTextInput(symbol)
                    }
                    .frame(height: compactEmojiKeyHeight)
                }
            }
        }

        private var symbolSectionDivider: some View {
            Rectangle()
                .fill(KeyboardThemePalette.thinDivider)
                .frame(height: 1)
                .padding(.vertical, 2)
        }
    }

    struct KeyboardRootKanaCandidateHeaderView: View {
        let showsParenthesesWrapper: Bool
        let composingText: String
        let conversionStateLabel: String
        let conversionStateIconName: String
        let conversionStateColor: Color
        let candidateStateFontSize: CGFloat
        let candidateTextFontSize: CGFloat
        let canTapComposingTextToCommit: Bool
        let showsKatakanaCommitFeedback: Bool
        let accentColor: Color
        let keyLabelColor: Color
        let conversionCandidates: [String]
        let selectedConversionCandidateIndex: Int?
        let kanaCandidateHeaderTopPadding: CGFloat
        let onSelectConversionCandidate: (Int) -> Void
        let onComposingTextCommitTap: () -> Void
        let onComposingTextCommitLongPress: () -> Void

        @ViewBuilder private var conversionCandidateChips: some View {
            if conversionCandidates.isEmpty {
                if !(showsParenthesesWrapper && composingText.isEmpty) {
                    // 変換候補が入力かなのみ=「候補なし」。文字ラベルでなく空集合アイコンで示す。
                    Image(systemName: "circle.slash")
                        .font(.system(size: candidateTextFontSize, weight: .regular))
                        .foregroundStyle(keyLabelColor.opacity(0.6))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(KeyboardThemePalette.candidateHeaderPlaceholderBackground)
                        )
                        .accessibilityLabel("候補なし")
                }
            }

            ForEach(Array(conversionCandidates.enumerated()), id: \.offset) { index, candidate in
                let isSelected = selectedConversionCandidateIndex == index

                Button {
                    onSelectConversionCandidate(index)
                } label: {
                    if showsParenthesesWrapper {
                        HStack(spacing: 0) {
                            Text("(")
                                .foregroundStyle(isSelected ? Color.white : accentColor)
                            Text(candidate)
                                .foregroundStyle(isSelected ? Color.white : keyLabelColor)
                            Text(")")
                                .foregroundStyle(isSelected ? Color.white : accentColor)
                        }
                        .font(.system(size: candidateTextFontSize, weight: .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(
                                    isSelected
                                        ? accentColor.opacity(0.9)
                                        : KeyboardThemePalette.candidateHeaderChipBackground
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(
                                    KeyboardThemePalette.candidateHeaderBorder,
                                    lineWidth: isSelected ? 0 : 1
                                )
                        )
                    } else {
                        Text(candidate)
                            .font(.system(size: candidateTextFontSize, weight: .semibold))
                            .foregroundStyle(isSelected ? Color.white : keyLabelColor)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(
                                        isSelected
                                            ? accentColor.opacity(0.9)
                                            : KeyboardThemePalette.candidateHeaderChipBackground
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(
                                        KeyboardThemePalette.candidateHeaderBorder,
                                        lineWidth: isSelected ? 0 : 1
                                    )
                            )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(candidate)
            }
        }

        // 末尾に「かなのみの候補」として出す(変換候補と同じチップ体裁)。タップで確定、
        // ロングタップでカタカナ確定。カタカナ確定フィードバック時はハイライト。
        @ViewBuilder private func composingKanaChip(_ text: String) -> some View {
            Text(text)
                .font(.system(size: candidateTextFontSize, weight: .semibold))
                .foregroundStyle(showsKatakanaCommitFeedback ? Color.white : keyLabelColor)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(
                            showsKatakanaCommitFeedback
                                ? accentColor.opacity(0.9)
                                : KeyboardThemePalette.candidateHeaderChipBackground
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(
                            KeyboardThemePalette.candidateHeaderBorder,
                            lineWidth: showsKatakanaCommitFeedback ? 0 : 1
                        )
                )
        }

        var body: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    let showsWrapperOnly = showsParenthesesWrapper && composingText.isEmpty

                    if !composingText.isEmpty || showsWrapperOnly {
                        // 状態はアイコンのミニカプセルで示す(鉛筆=未確定/循環矢印=変換中)。
                        Group {
                            if showsWrapperOnly {
                                Text("()")
                            } else {
                                Image(systemName: conversionStateIconName)
                            }
                        }
                        .font(.system(size: candidateStateFontSize, weight: .bold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(conversionStateColor.opacity(0.95))
                        )
                        .accessibilityLabel(conversionStateLabel)
                    }

                    conversionCandidateChips

                    if !composingText.isEmpty {
                        let kanaChipText = showsParenthesesWrapper ? "(\(composingText))" : composingText
                        if canTapComposingTextToCommit {
                            Button {
                                onComposingTextCommitTap()
                            } label: {
                                composingKanaChip(kanaChipText)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(composingText)を確定")
                            .accessibilityHint("通常タップで変換せずに確定。ロングタップでカタカナ確定")
                            .simultaneousGesture(
                                LongPressGesture(minimumDuration: 0.4)
                                    .onEnded { _ in
                                        onComposingTextCommitLongPress()
                                    }
                            )
                        } else {
                            composingKanaChip(kanaChipText)
                        }
                    } else if showsWrapperOnly {
                        composingKanaChip("()")
                    }

                }
                .padding(.horizontal, 2)
                .padding(.top, kanaCandidateHeaderTopPadding)
                .padding(.bottom, 0)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }

    struct KeyboardRootLatinSuggestionHeaderView: View {
        let latinSuggestions: [String]
        let candidateTextFontSize: CGFloat
        let keyLabelColor: Color
        let kanaCandidateHeaderTopPadding: CGFloat
        let onSelectConversionCandidate: (Int) -> Void

        var body: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if latinSuggestions.isEmpty {
                        // かな側と同じ空集合アイコン(候補なし)。
                        Image(systemName: "circle.slash")
                            .font(.system(size: candidateTextFontSize, weight: .regular))
                            .foregroundStyle(keyLabelColor.opacity(0.6))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(KeyboardThemePalette.candidateHeaderPlaceholderBackground)
                            )
                            .accessibilityLabel("候補なし")
                    }

                    ForEach(Array(latinSuggestions.enumerated()), id: \.offset) { index, candidate in
                        Button {
                            onSelectConversionCandidate(index)
                        } label: {
                            Text(candidate)
                                .font(.system(size: candidateTextFontSize, weight: .semibold))
                                .foregroundStyle(keyLabelColor)
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(KeyboardThemePalette.candidateHeaderChipBackground)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(KeyboardThemePalette.candidateHeaderBorder, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(candidate)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.top, kanaCandidateHeaderTopPadding)
                .padding(.bottom, 0)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }
