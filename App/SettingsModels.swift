import SwiftUI

enum SettingsKeys {
    static let appGroupID = "group.com.kusakabe.ecritu"
    static let directionProfile = "flickDirectionProfile"
    static let kanaLayoutMode = "kanaLayoutMode"
    static let kanaModifierPlacement = "kanaModifierPlacement"
    static let latinLayoutMode = "latinLayoutMode"
    static let numberLayoutMode = "numberLayoutMode"
    static let accentPalette = "accentPalette"
    static let keyboardBackgroundTheme = "keyboardBackgroundTheme"
    static let kanaFlickGuideDisplayMode = "flickGuideDisplayModeKana"
    static let latinFlickGuideDisplayMode = "flickGuideDisplayModeLatin"
    static let numberFlickGuideDisplayMode = "flickGuideDisplayModeNumber"
    static let showsFlickGuideCharacters = "showsFlickGuideCharacters"
    static let keyRepeatInitialDelay = "keyRepeatInitialDelay"
    static let keyRepeatInterval = "keyRepeatInterval"
    static let kanaKanjiAjoutVocabulary = "ÉcrituAjoutVocab"
    static let kanaKanjiInitialUserDictionaryMigrated = "kanaKanjiInitialUserDictionaryMigrated"
    static let kanaKanjiInitialSuppressionDictionaryMigrated = "kanaKanjiInitialSuppressionDictionaryMigrated"
    static let kanaKanjiSuppressionVocabulary = "ÉcrituSuppr_Vocab"
    static let kanaKanjiCandidateSourceMode = "kanaKanjiCandidateSourceMode"
    static let kanaKanjiLearningScores = "kanaKanjiLearningScores"
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
