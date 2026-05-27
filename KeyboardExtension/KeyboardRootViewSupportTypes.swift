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

extension KeyboardRootView {
    enum EmojiCategory: Int, CaseIterable, Identifiable {
        case people
        case animals
        case food
        case activities
        case travel
        case objects
        case symbols
        case flags

        var id: Int { rawValue }

        var icon: String {
            switch self {
            case .people: return "😀"
            case .animals: return "🐻"
            case .food: return "🍔"
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
                switch basicOrder {
                case .ascii:
                    return Self.basicSymbolsASCII
                case .ebcdic:
                    return Self.basicSymbolsEBCDIC
                case .ansi:
                    return Self.basicSymbolsANSI
                }
            case .brackets:
                return Self.bracketAndQuoteSymbols
            case .currency:
                return Self.currencySymbols
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
            "", "⌘", "☻", "・", "「", "」", "『", "』"
        ]

        private static let basicSymbolsEBCDIC: [String] = [
            ".", "<", "(", "+", "|", "&", "!", "$", "*", ")", ";", "-", "/", ",", "%", "_",
            ">", "?", "`", ":", "#", "@", "'", "=", "\"", "~", "^", "[", "]", "{", "}", "\\",
            "", "⌘", "☻", "・", "「", "」", "『", "』"
        ]

        private static let basicSymbolsANSI: [String] = [
            "!", "@", "#", "$", "%", "^", "&", "*",
            "(", ")", "-", "_", "=", "+", "[", "]",
            "{", "}", ";", ":", "'", "\"", ",", ".",
            "<", ">", "/", "?", "\\", "|", "`", "~",
            "", "⌘", "☻", "・", "「", "」", "『", "』"
        ]

        private static let bracketAndQuoteSymbols: [String] = [
            "(", ")", "[", "]", "{", "}", "<", ">",
            "『", "』", "「", "」", "【", "】", "〔", "〕", "〈", "〉", "《", "》",
            "“", "”", "‘", "’", "«", "»", "‹", "›", "〝", "〟"
        ]

        private static let currencySymbols: [String] = [
            "€", "$", "¢", "£", "¥", "₩", "₹", "₽", "₺", "฿", "₫", "₴", "₦", "₱", "₡", "₲", "₵", "₭", "₸", "₮", "₳", "₰"
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
