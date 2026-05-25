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
    static let delimiterAutoCommitCandidate = "delimiterAutoCommitCandidate"
    static let landscapeCandidateSide = "landscapeCandidateSide"
    static let landscapeNumberPaneSide = "landscapeNumberPaneSide"
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
    static let kanaKanjiLearningScores = "kanaKanjiLearningScores"
    static let legacyKeyboardDebugLogCleanupCompleted = "legacyKeyboardDebugLogCleanupCompleted"
    static let keyboardDiagnosticsLogLines = "keyboardDiagnosticsLogLines"
    static let keyboardDiagnosticsInstallMarker = "keyboardDiagnosticsInstallMarker"
    static let keyboardDiagnosticsSessionActive = "keyboardDiagnosticsSessionActive"
    static let keyboardDiagnosticsLastHeartbeat = "keyboardDiagnosticsLastHeartbeat"
    static let keyboardDiagnosticsLastEvent = "keyboardDiagnosticsLastEvent"
    static let keyboardDiagnosticsLastSessionID = "keyboardDiagnosticsLastSessionID"
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
