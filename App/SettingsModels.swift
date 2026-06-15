import SwiftUI
import CoreFoundation
import UIKit

enum SettingsKeys {
    private static func fallbackAppGroupID() -> String {
        guard let bundleID = Bundle.main.bundleIdentifier,
            !bundleID.isEmpty else {
            return "group.com.kusakabe.ecritu"
        }

        return "group.\(bundleID)"
    }

    static let appGroupID: String = {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: "EcrituAppGroupIdentifier") as? String,
            !value.isEmpty
        else {
            return fallbackAppGroupID()
        }
        return value
    }()
    static let directionProfile = "flickDirectionProfile"
    static let kanaLayoutMode = "kanaLayoutMode"
    static let kanaModifierPlacement = "kanaModifierPlacement"
    static let latinLayoutMode = "latinLayoutMode"
    static let numberLayoutMode = "numberLayoutMode"
    static let basicSymbolOrder = "basicSymbolOrder"
    static let accentPalette = "accentPalette"
    static let keyboardBackgroundTheme = "keyboardBackgroundTheme"
    static let kanaFlickGuideDisplayMode = "flickGuideDisplayModeKana"
    static let latinFlickGuideDisplayMode = "flickGuideDisplayModeLatin"
    static let numberFlickGuideDisplayMode = "flickGuideDisplayModeNumber"
    static let modifierFlickGuideDisplayMode = "flickGuideDisplayModeModifier"
    static let showsFlickGuideCharacters = "showsFlickGuideCharacters"
    static let keyRepeatInitialDelay = "keyRepeatInitialDelay"
    static let keyRepeatInterval = "keyRepeatInterval"
    static let kanaModeSwitcherTapAction = "kanaModeSwitcherTapAction"
    static let kanaModeSwitcherRightFlickAction = "kanaModeSwitcherRightFlickAction"
    static let kanaModeSwitcherUpFlickAction = "kanaModeSwitcherUpFlickAction"
    static let kanaPostModifierEmptyTapAction = "kanaPostModifierEmptyTapAction"
    static let kanaPostModifierEmptyTapKaomojiCategory = "kanaPostModifierEmptyTapKaomojiCategory"
    static let kanaPostModifierEmptyTapEmojiCategory = "kanaPostModifierEmptyTapEmojiCategory"
    static let kanaPostModifierEmptyTapSymbolCategory = "kanaPostModifierEmptyTapSymbolCategory"
    static let delimiterAutoCommitCandidate = "delimiterAutoCommitCandidate"
    static let landscapeCandidateSide = "landscapeCandidateSide"
    static let landscapeNumberPaneSide = "landscapeNumberPaneSide"
    static let landscapeLatinSuggestionMode = "landscapeLatinSuggestionMode"
    static let kanaKanjiAjoutVocabulary = "ÉcrituAjoutVocab"
    static let kanaKanjiInitialUserDictionaryMigrated = "kanaKanjiInitialUserDictionaryMigrated"
    static let kanaKanjiInitialUserDictionaryAppliedSignature = "kanaKanjiInitialUserDictionaryAppliedSignature"
    static let kanaKanjiLearnedVocabulary = "kanaKanjiLearnedVocabulary"
    static let kanaKanjiLearningVocabularyMigrationCompleted = "kanaKanjiLearningVocabularyMigrationCompleted"
    static let kanaKanjiShortcutVocabulary = "ÉcrituShortcutVocab"
    static let kanaKanjiInitialShortcutVocabularyMigrated = "kanaKanjiInitialShortcutVocabularyMigrated"
    static let kanaKanjiInitialSuppressionDictionaryMigrated = "kanaKanjiInitialSuppressionDictionaryMigrated"
    static let kanaKanjiInitialSuppressionDictionaryAppliedSignature = "kanaKanjiInitialSuppressionDictionaryAppliedSignature"
    static let kanaKanjiSuppressionVocabulary = "ÉcrituSuppr_Vocab"
    static let kanaKanjiCandidateSourceMode = "kanaKanjiCandidateSourceMode"
    static let historicalKanaCandidatesEnabled = "historicalKanaCandidatesEnabled"
    static let userDictionaryCandidateDisplayMode = "userDictionaryCandidateDisplayMode"
    static let contactCandidateDisplayMode = "contactCandidateDisplayMode"
    static let emojiCandidateDisplayEnabled = "emojiCandidateDisplayEnabled"
    static let kaomojiCandidateDisplayEnabled = "kaomojiCandidateDisplayEnabled"
    static let contactCandidatesByReadingCache = "contactCandidatesByReadingCache"
    static let kanaKanjiLearningScores = "kanaKanjiLearningScores"
    static let legacyKeyboardDebugLogCleanupCompleted = "legacyKeyboardDebugLogCleanupCompleted"
    static let keyboardDiagnosticsLogLines = "keyboardDiagnosticsLogLines"
    static let keyboardDiagnosticsInstallMarker = "keyboardDiagnosticsInstallMarker"
    static let keyboardDiagnosticsSessionActive = "keyboardDiagnosticsSessionActive"
    static let keyboardDiagnosticsSessionOwnerToken = "keyboardDiagnosticsSessionOwnerToken"
    static let keyboardDiagnosticsLastHeartbeat = "keyboardDiagnosticsLastHeartbeat"
    static let keyboardDiagnosticsLastEvent = "keyboardDiagnosticsLastEvent"
    static let keyboardDiagnosticsLastSessionID = "keyboardDiagnosticsLastSessionID"
    static let keyboardDiagnosticsFailSafeProfile = "keyboardDiagnosticsFailSafeProfile"
    static let keyboardDiagnosticsFlightRecorderEvents = "keyboardDiagnosticsFlightRecorderEvents"
}

enum RepeatSettings {
    static let initialDelayDefault = 0.5
    static let initialDelayRange: ClosedRange<Double> = 0.1...0.8
    static let intervalDefault = 0.1
    static let intervalRange: ClosedRange<Double> = 0.05...0.2
    static let snapThreshold = 0.01
}

enum KanaLayoutOption: String, CaseIterable, Identifiable {
    case fiveByTwo
    case threeByThreePlusWa

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fiveByTwo: return "5x2"
        case .threeByThreePlusWa: return "3x3+わ"
        }
    }
}

enum KanaModifierPlacementOption: String, CaseIterable, Identifiable {
    case prefix
    case postfix

    var id: String { rawValue }

    var title: String {
        switch self {
        case .prefix: return "前置修飾"
        case .postfix: return "後置修飾"
        }
    }
}

enum DirectionOption: String, CaseIterable, Identifiable {
    case apple
    case ecritu

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: return "Apple"
        case .ecritu: return "écritu"
        }
    }
}

enum LatinLayoutOption: String, CaseIterable, Identifiable {
    case azerty
    case qwerty
    case flick

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flick: return "3x3"
        case .qwerty: return "qwerty"
        case .azerty: return "azerty"
        }
    }
}

enum NumberLayoutOption: String, CaseIterable, Identifiable {
    case calculette
    case telephone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calculette: return "calculette"
        case .telephone: return "téléphone"
        }
    }
}

enum BasicSymbolOrderOption: String, CaseIterable, Identifiable {
    case ascii
    case ebcdic
    case ansi

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ascii: return "ASCII"
        case .ebcdic: return "EBCDIC"
        case .ansi: return "ANSI"
        }
    }
}

enum FlickGuideDisplayOption: String, CaseIterable, Identifiable {
    case off
    case fourDirections
    case down

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "オフ"
        case .fourDirections: return "4方向"
        case .down: return "下"
        }
    }
}

enum KanaKanjiCandidateSourceModeOption: String, CaseIterable, Identifiable {
    case normalise
    case surface
    case lesDeux

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normalise: return "normalisé"
        case .surface: return "surface"
        case .lesDeux: return "les deux"
        }
    }
}

enum UserDictionaryCandidateDisplayModeOption: String, CaseIterable, Identifiable {
    case off
    case on

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:
            return "使わない"
        case .on:
            return "使う"
        }
    }
}

enum ContactCandidateDisplayModeOption: String, CaseIterable, Identifiable {
    case off
    case namesOnly
    case namesPlusFullName

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:
            return "連絡先候補を使わない"
        case .namesOnly:
            return "一致した名前だけ候補にする"
        case .namesPlusFullName:
            return "姓/名一致でフルネームも候補にする"
        }
    }

    var subtitle: String {
        switch self {
        case .off:
            return "連絡先由来の候補を表示しません。"
        case .namesOnly:
            return "姓・名・ニックネームなど、一致した項目のみ表示します。(既定)"
        case .namesPlusFullName:
            return "姓または名が一致したときにフルネームも表示します。"
        }
    }
}

enum KanaModeSwitcherActionOption: String, CaseIterable, Identifiable {
    case emoji
    case kaomoji
    case symbols

    var id: String { rawValue }

    var title: String {
        switch self {
        case .emoji: return "絵文字"
        case .kaomoji: return "顔文字"
        case .symbols: return "記号"
        }
    }

    var keyLabel: String {
        switch self {
        case .emoji: return "☺︎"
        case .kaomoji: return "^_^"
        case .symbols: return "⌘"
        }
    }
}

enum KanaPostModifierEmptyTapActionOption: String, CaseIterable, Identifiable {
    case kaomoji
    case emoji
    case symbols

    var id: String { rawValue }

    var title: String {
        switch self {
        case .kaomoji: return "顔文字入力モード"
        case .emoji: return "絵文字入力モード"
        case .symbols: return "記号入力モード"
        }
    }

    var iconLabel: String {
        switch self {
        case .kaomoji: return "^_^"
        case .emoji: return "☺︎"
        case .symbols: return "⌘"
        }
    }

    static let `default`: KanaPostModifierEmptyTapActionOption = .kaomoji
}

struct CategoryChoiceDescriptor: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
}

enum KaomojiCategoryChoice {
    // Mirrored from KeyboardExtension/KeyboardRootViewSupportTypes.swift (KaomojiCategory)
    // and KeyboardExtension/KaomojiCatalog.swift (importedCategoryOrder).
    static let defaultID = "existing"

    static let all: [CategoryChoiceDescriptor] = {
        var entries: [CategoryChoiceDescriptor] = [
            CategoryChoiceDescriptor(id: "existing", title: "基本", icon: "🙂"),
            CategoryChoiceDescriptor(id: "shortcut", title: "ショートカット", icon: "⚡️"),
            CategoryChoiceDescriptor(id: "search", title: "検索", icon: "🔎")
        ]

        let importedCategories: [(name: String, icon: String)] = [
            ("キャラ", "🧑"),
            ("ライン", "💬"),
            ("挨拶", "🙋"),
            ("キモい", "🤪"),
            ("特殊", "✨"),
            ("笑", "😂"),
            ("焦り", "💦"),
            ("かわいい", "🥰"),
            ("驚き", "😲"),
            ("怒", "😠"),
            ("しょぼん", "😔"),
            ("ラブ", "❤️"),
            ("激しい", "💥"),
            ("照れ", "😊"),
            ("くそねみ", "😴"),
            ("悲", "😢"),
            ("うごき", "🏃")
        ]

        entries.append(contentsOf: importedCategories.map {
            CategoryChoiceDescriptor(id: "imported:\($0.name)", title: $0.name, icon: $0.icon)
        })

        return entries
    }()
}

enum EmojiCategoryChoice {
    // Mirrored from KeyboardExtension/KeyboardRootViewSupportTypes.swift (EmojiCategory).
    static let defaultID = "0"

    static let all: [CategoryChoiceDescriptor] = [
        CategoryChoiceDescriptor(id: "0", title: "ひと", icon: "😀"),
        CategoryChoiceDescriptor(id: "1", title: "動物・自然", icon: "🐻"),
        CategoryChoiceDescriptor(id: "2", title: "食べもの・飲みもの", icon: "🍔"),
        CategoryChoiceDescriptor(id: "3", title: "アクティビティ", icon: "🏀"),
        CategoryChoiceDescriptor(id: "4", title: "旅行・場所", icon: "🚗"),
        CategoryChoiceDescriptor(id: "5", title: "もの", icon: "💡"),
        CategoryChoiceDescriptor(id: "6", title: "記号", icon: "❤️"),
        CategoryChoiceDescriptor(id: "7", title: "国旗", icon: "🇫🇷")
    ]
}

enum SymbolCategoryChoice {
    // Mirrored from KeyboardExtension/KeyboardRootViewSupportTypes.swift (SymbolCategory).
    static let defaultID = "0"

    static let all: [CategoryChoiceDescriptor] = [
        CategoryChoiceDescriptor(id: "0", title: "基本記号", icon: "!?"),
        CategoryChoiceDescriptor(id: "1", title: "括弧・引用符", icon: "『』"),
        CategoryChoiceDescriptor(id: "2", title: "通貨", icon: "€"),
        CategoryChoiceDescriptor(id: "3", title: "単位", icon: "℃"),
        CategoryChoiceDescriptor(id: "4", title: "数学", icon: "∑"),
        CategoryChoiceDescriptor(id: "5", title: "矢印", icon: "↗"),
        CategoryChoiceDescriptor(id: "6", title: "囲み文字", icon: "⓪")
    ]
}

enum DelimiterAutoCommitCandidateOption: String, CaseIterable, Identifiable {
    case zero
    case one

    var id: String { rawValue }

    var title: String {
        switch self {
        case .zero: return "第0候補"
        case .one: return "第1候補"
        }
    }
}

enum LandscapeCandidateSideOption: String, CaseIterable, Identifiable {
    case left
    case right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: return "左"
        case .right: return "右"
        }
    }
}

enum LandscapeLatinSuggestionModeOption: String, CaseIterable, Identifiable {
    case sidebar
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sidebar: return "使う"
        case .off: return "使わない"
        }
    }
}

enum AccentColorOption: String, CaseIterable, Identifiable {
    case tuile
    case emeraude

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tuile: return "tuilé"
        case .emeraude: return "émeraude"
        }
    }

    var color: Color {
        switch self {
        case .tuile:
            return Color(red: 136.0 / 255.0, green: 63.0 / 255.0, blue: 53.0 / 255.0)
        case .emeraude:
            return Color(red: 0.06, green: 0.73, blue: 0.56)
        }
    }
}

enum KeyboardBackgroundThemeOption: String, CaseIterable, Identifiable {
    case bleu
    case sakura

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bleu: return "bleu ciel brumeux"
        case .sakura: return "rose sakura poudré"
        }
    }

    var subtitle: String {
        switch self {
        case .bleu: return "brume douce et lumière du ciel"
        case .sakura: return "rose poudré inspiré des fleurs"
        }
    }

    var gradientColors: [Color] {
        switch self {
        case .bleu:
            return [
                Color(red: 0.86, green: 0.91, blue: 1.0),
                Color(red: 0.95, green: 0.97, blue: 1.0)
            ]
        case .sakura:
            return [
                Color(red: 1.0, green: 0.88, blue: 0.93),
                Color(red: 1.0, green: 0.95, blue: 0.97)
            ]
        }
    }
}

struct VocabularyEntry: Identifiable {
    let reading: String
    let candidate: String

    var id: String { reading + "\t" + candidate }
}

enum SettingsSyncNotification {
    static var darwinNotificationName: String {
        "com.kusakabe.ecritu.settings-changed.\(SettingsKeys.appGroupID)"
    }

    static func postSettingsDidChange() {
        let notificationName = CFNotificationName(darwinNotificationName as CFString)

        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            notificationName,
            nil,
            nil,
            true
        )
    }
}

enum AppTheme {
    static let screenBackground = Color(uiColor: .systemGroupedBackground)
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let cardInnerBackground = Color(uiColor: .tertiarySystemGroupedBackground)
    static let controlBackground = Color(uiColor: .tertiarySystemBackground)
    static let selectedControlBackground = Color(uiColor: .secondarySystemBackground)
    static let listRowBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let indexBadgeBackground = Color(uiColor: .tertiarySystemFill)
    static let subtleBorder = Color(uiColor: .separator).opacity(0.35)
    static let emphasisBorder = Color(uiColor: .separator).opacity(0.6)
    static let subduedIcon = Color(uiColor: .tertiaryLabel)
}

extension View {
    func settingsCardStyle() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.cardBackground)
            )
    }
}
