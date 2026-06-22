import SwiftUI
import Darwin
import Contacts
#if os(iOS)
import UIKit
#endif

struct ContentView: View {
    private static let sharedDefaults = UserDefaults(suiteName: SettingsKeys.appGroupID)
    private static let editionUpdatedAtRaw: String = "20260622174105"
    private static let diagnosticsTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let contactFetchKeys: [CNKeyDescriptor] = [
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactMiddleNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactNicknameKey as CNKeyDescriptor,
        CNContactOrganizationNameKey as CNKeyDescriptor,
        CNContactPhoneticOrganizationNameKey as CNKeyDescriptor,
        CNContactPhoneticGivenNameKey as CNKeyDescriptor,
        CNContactPhoneticMiddleNameKey as CNKeyDescriptor,
        CNContactPhoneticFamilyNameKey as CNKeyDescriptor
    ]

    private static func editionDateText(from rawValue: String?) -> String? {
        guard let rawValue,
            rawValue.count >= 8 else {
            return nil
        }

        let yearPart = rawValue.prefix(4)
        let monthPart = rawValue.dropFirst(4).prefix(2)
        let dayPart = rawValue.dropFirst(6).prefix(2)

        guard let month = Int(monthPart),
            let day = Int(dayPart) else {
            return nil
        }

        return "\(yearPart)-\(month)-\(day)"
    }

    private static let editionNumberText: String = {
        let info = Bundle.main.infoDictionary ?? [:]
        let editionNumber = (info["CFBundleVersion"] as? String) ?? "?"

        if let dateText = editionDateText(from: editionUpdatedAtRaw) {
            return "édition n°\(editionNumber) (\(dateText))"
        }

        return "édition n°\(editionNumber)"
    }()

    private static func normalizedContactReading(_ text: String) -> String {
        var normalized = ""

        for character in text {
            let source = String(character).precomposedStringWithCanonicalMapping
            let converted = source.applyingTransform(.hiraganaToKatakana, reverse: true) ?? source

            guard converted.count == 1,
                let scalar = converted.unicodeScalars.first else {
                continue
            }

            let isHiragana = (0x3040...0x309F).contains(scalar.value)
            let isLongVowelMark = scalar.value == 0x30FC

            guard isHiragana || isLongVowelMark,
                let normalizedCharacter = converted.first else {
                continue
            }

            normalized.append(normalizedCharacter)
        }

        return normalized
    }

    private static func contactNameCandidates(
        primaryName: String,
        fullName: String,
        includeFullName: Bool
    ) -> [String] {
        guard !primaryName.isEmpty else {
            return []
        }

        guard includeFullName,
            !fullName.isEmpty,
            fullName != primaryName else {
            return [primaryName]
        }

        return [primaryName, fullName]
    }

    private static func appendContactCandidates(
        _ candidates: [String],
        forReadingText readingText: String,
        to dictionary: inout [String: [String]]
    ) {
        let normalizedReading = normalizedContactReading(readingText)

        guard !normalizedReading.isEmpty else {
            return
        }

        var existingCandidates = dictionary[normalizedReading] ?? []

        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmed.isEmpty,
                !existingCandidates.contains(trimmed) else {
                continue
            }

            existingCandidates.append(trimmed)
        }

        if !existingCandidates.isEmpty {
            dictionary[normalizedReading] = Array(existingCandidates.prefix(48))
        }
    }

    private static func shouldUseOrganizationNameReadingFallback(_ organizationName: String) -> Bool {
        let source = organizationName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !source.isEmpty else {
            return false
        }

        var hasKana = false

        for scalar in source.precomposedStringWithCanonicalMapping.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                continue
            }

            if scalar.value == 0x30FB || scalar.value == 0xFF65 {
                continue
            }

            let normalized = normalizedContactReading(String(scalar))

            if !normalized.isEmpty {
                hasKana = true
                continue
            }

            return false
        }

        return hasKana
    }

    private static func buildContactCandidatesByReading(
        displayMode: ContactCandidateDisplayModeOption
    ) -> [String: [String]] {
        let includeFullNameForNameMatches = displayMode == .namesPlusFullName
        let store = CNContactStore()
        let request = CNContactFetchRequest(keysToFetch: contactFetchKeys)
        var dictionary: [String: [String]] = [:]

        do {
            try store.enumerateContacts(with: request) { contact, _ in
                let familyName = contact.familyName.trimmingCharacters(in: .whitespacesAndNewlines)
                let givenName = contact.givenName.trimmingCharacters(in: .whitespacesAndNewlines)
                let middleName = contact.middleName.trimmingCharacters(in: .whitespacesAndNewlines)
                let nickname = contact.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
                let organizationName = contact.organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
                let phoneticOrganizationName = contact.phoneticOrganizationName.trimmingCharacters(in: .whitespacesAndNewlines)
                let fullName = [familyName, givenName, middleName]
                    .filter { !$0.isEmpty }
                    .joined()

                let phoneticFamily = contact.phoneticFamilyName.trimmingCharacters(in: .whitespacesAndNewlines)
                let phoneticGiven = contact.phoneticGivenName.trimmingCharacters(in: .whitespacesAndNewlines)
                let phoneticMiddle = contact.phoneticMiddleName.trimmingCharacters(in: .whitespacesAndNewlines)
                let fullNamePhonetic = [phoneticFamily, phoneticGiven, phoneticMiddle].joined()

                var readingCandidates: [(String, [String])] = [
                    (
                        phoneticFamily,
                        contactNameCandidates(
                            primaryName: familyName,
                            fullName: fullName,
                            includeFullName: includeFullNameForNameMatches
                        )
                    ),
                    (
                        phoneticGiven,
                        contactNameCandidates(
                            primaryName: givenName,
                            fullName: fullName,
                            includeFullName: includeFullNameForNameMatches
                        )
                    ),
                    (
                        phoneticMiddle,
                        contactNameCandidates(
                            primaryName: middleName,
                            fullName: fullName,
                            includeFullName: includeFullNameForNameMatches
                        )
                    ),
                    (fullNamePhonetic, [fullName]),
                    (
                        familyName,
                        contactNameCandidates(
                            primaryName: familyName,
                            fullName: fullName,
                            includeFullName: includeFullNameForNameMatches
                        )
                    ),
                    (
                        givenName,
                        contactNameCandidates(
                            primaryName: givenName,
                            fullName: fullName,
                            includeFullName: includeFullNameForNameMatches
                        )
                    ),
                    (
                        middleName,
                        contactNameCandidates(
                            primaryName: middleName,
                            fullName: fullName,
                            includeFullName: includeFullNameForNameMatches
                        )
                    ),
                    (fullName, [fullName]),
                    (nickname, [nickname]),
                    (phoneticOrganizationName, [organizationName])
                ]

                if shouldUseOrganizationNameReadingFallback(organizationName) {
                    readingCandidates.append((organizationName, [organizationName]))
                }

                for (readingText, candidates) in readingCandidates {
                    appendContactCandidates(candidates, forReadingText: readingText, to: &dictionary)
                }
            }
        } catch {
            return [:]
        }

        return dictionary
    }

    @AppStorage(
        SettingsKeys.directionProfile,
        store: Self.sharedDefaults
    )
    private var directionProfileRawValue: String = DirectionOption.ecritu.rawValue

    @AppStorage(
        SettingsKeys.kanaLayoutMode,
        store: Self.sharedDefaults
    )
    private var kanaLayoutModeRawValue: String = KanaLayoutOption.fiveByTwo.rawValue

    @AppStorage(
        SettingsKeys.landscapeCandidateSide,
        store: Self.sharedDefaults
    )
    private var landscapeCandidateSideRawValue: String = LandscapeCandidateSideOption.left.rawValue

    @AppStorage(
        SettingsKeys.landscapeNumberPaneSide,
        store: Self.sharedDefaults
    )
    private var landscapeNumberPaneSideRawValue: String = LandscapeCandidateSideOption.left.rawValue

    @AppStorage(
        SettingsKeys.landscapeLatinSuggestionMode,
        store: Self.sharedDefaults
    )
    private var landscapeLatinSuggestionModeRawValue: String = LandscapeLatinSuggestionModeOption.sidebar.rawValue

    @AppStorage(
        SettingsKeys.kanaModifierPlacement,
        store: Self.sharedDefaults
    )
    private var kanaModifierPlacementRawValue: String = KanaModifierPlacementOption.prefix.rawValue

    @AppStorage(
        SettingsKeys.latinLayoutMode,
        store: Self.sharedDefaults
    )
    private var latinLayoutModeRawValue: String = LatinLayoutOption.azerty.rawValue

    @AppStorage(
        SettingsKeys.numberLayoutMode,
        store: Self.sharedDefaults
    )
    private var numberLayoutModeRawValue: String = NumberLayoutOption.calculette.rawValue

    @AppStorage(
        SettingsKeys.basicSymbolOrder,
        store: Self.sharedDefaults
    )
    private var basicSymbolOrderRawValue: String = BasicSymbolOrderOption.ascii.rawValue

    @AppStorage(
        SettingsKeys.accentPalette,
        store: Self.sharedDefaults
    )
    private var accentPaletteRawValue: String = AccentColorOption.emeraude.rawValue

    @AppStorage(
        SettingsKeys.keyboardBackgroundTheme,
        store: Self.sharedDefaults
    )
    private var keyboardBackgroundThemeRawValue: String = KeyboardBackgroundThemeOption.bleu.rawValue

    @AppStorage(
        SettingsKeys.kanaFlickGuideDisplayMode,
        store: Self.sharedDefaults
    )
    private var kanaFlickGuideDisplayModeRawValue: String = FlickGuideDisplayOption.fourDirections.rawValue

    @AppStorage(
        SettingsKeys.latinFlickGuideDisplayMode,
        store: Self.sharedDefaults
    )
    private var latinFlickGuideDisplayModeRawValue: String = FlickGuideDisplayOption.fourDirections.rawValue

    @AppStorage(
        SettingsKeys.numberFlickGuideDisplayMode,
        store: Self.sharedDefaults
    )
    private var numberFlickGuideDisplayModeRawValue: String = FlickGuideDisplayOption.fourDirections.rawValue

    @AppStorage(
        SettingsKeys.modifierFlickGuideDisplayMode,
        store: Self.sharedDefaults
    )
    private var modifierFlickGuideDisplayModeRawValue: String = FlickGuideDisplayOption.fourDirections.rawValue

    @AppStorage(
        SettingsKeys.keyRepeatInitialDelay,
        store: Self.sharedDefaults
    )
    private var keyRepeatInitialDelay: Double = RepeatSettings.initialDelayDefault

    @AppStorage(
        SettingsKeys.keyRepeatInterval,
        store: Self.sharedDefaults
    )
    private var keyRepeatInterval: Double = RepeatSettings.intervalDefault

    @AppStorage(
        SettingsKeys.kanaModeSwitcherTapAction,
        store: Self.sharedDefaults
    )
    private var kanaModeSwitcherTapActionRawValue: String = KanaModeSwitcherActionOption.emoji.rawValue

    @AppStorage(
        SettingsKeys.kanaModeSwitcherRightFlickAction,
        store: Self.sharedDefaults
    )
    private var kanaModeSwitcherRightFlickActionRawValue: String = KanaModeSwitcherActionOption.kaomoji.rawValue

    @AppStorage(
        SettingsKeys.kanaModeSwitcherUpFlickAction,
        store: Self.sharedDefaults
    )
    private var kanaModeSwitcherUpFlickActionRawValue: String = KanaModeSwitcherActionOption.symbols.rawValue

    @AppStorage(
        SettingsKeys.kanaPostModifierEmptyTapAction,
        store: Self.sharedDefaults
    )
    private var kanaPostModifierEmptyTapActionRawValue: String = KanaPostModifierEmptyTapActionOption.default.rawValue

    @AppStorage(
        SettingsKeys.kanaPostModifierEmptyTapKaomojiCategory,
        store: Self.sharedDefaults
    )
    private var kanaPostModifierEmptyTapKaomojiCategoryID: String = KaomojiCategoryChoice.defaultID

    @AppStorage(
        SettingsKeys.kanaPostModifierEmptyTapEmojiCategory,
        store: Self.sharedDefaults
    )
    private var kanaPostModifierEmptyTapEmojiCategoryID: String = EmojiCategoryChoice.defaultID

    @AppStorage(
        SettingsKeys.kanaPostModifierEmptyTapSymbolCategory,
        store: Self.sharedDefaults
    )
    private var kanaPostModifierEmptyTapSymbolCategoryID: String = SymbolCategoryChoice.defaultID

    @AppStorage(
        SettingsKeys.kanaPostModifierFlickDakutenEnabled,
        store: Self.sharedDefaults
    )
    private var kanaPostModifierFlickDakutenEnabled = true

    @AppStorage(
        SettingsKeys.delimiterAutoCommitCandidate,
        store: Self.sharedDefaults
    )
    private var delimiterAutoCommitCandidateRawValue: String = DelimiterAutoCommitCandidateOption.zero.rawValue

    @AppStorage(
        SettingsKeys.kanaKanjiCandidateSourceMode,
        store: Self.sharedDefaults
    )
    private var kanaKanjiCandidateSourceModeRawValue: String = KanaKanjiCandidateSourceModeOption.surface.rawValue

    @AppStorage(
        SettingsKeys.userDictionaryCandidateDisplayMode,
        store: Self.sharedDefaults
    )
    private var userDictionaryCandidateDisplayModeRawValue: String = UserDictionaryCandidateDisplayModeOption.on.rawValue

    @AppStorage(
        SettingsKeys.contactCandidateDisplayMode,
        store: Self.sharedDefaults
    )
    private var contactCandidateDisplayModeRawValue: String = ContactCandidateDisplayModeOption.namesOnly.rawValue

    @AppStorage(
        SettingsKeys.emojiCandidateDisplayEnabled,
        store: Self.sharedDefaults
    )
    private var emojiCandidateDisplayEnabled = true

    @AppStorage(
        SettingsKeys.kaomojiCandidateDisplayEnabled,
        store: Self.sharedDefaults
    )
    private var kaomojiCandidateDisplayEnabled = true

    @AppStorage(
        SettingsKeys.historicalKanaCandidatesEnabled,
        store: Self.sharedDefaults
    )
    private var historicalKanaCandidatesEnabled = false

    @State private var userDictionaryEntries: [VocabularyEntry] = []
    @State private var userDictionaryReadingInput = ""
    @State private var userDictionaryCandidateInput = ""
    @State private var isUserDictionaryRegistrationVisible = false
    @State private var userDictionaryScrollIndexTitle = ""
    @State private var isUserDictionaryScrollIndexVisible = false
    @State private var learnedDictionaryEntries: [VocabularyEntry] = []
    @State private var learnedDictionaryScrollIndexTitle = ""
    @State private var isLearnedDictionaryScrollIndexVisible = false
    @State private var suppressionDictionaryEntries: [VocabularyEntry] = []
    @State private var suppressionDictionaryReadingInput = ""
    @State private var suppressionDictionaryCandidateInput = ""
    @State private var isSuppressionDictionaryRegistrationVisible = false
    @State private var suppressionDictionaryScrollIndexTitle = ""
    @State private var isSuppressionDictionaryScrollIndexVisible = false
    @State private var shortcutDictionaryEntries: [VocabularyEntry] = []
    @State private var shortcutDictionaryCandidateInput = ""
    @State private var isShortcutDictionaryRegistrationVisible = false
    @State private var firstVocabularyEntries: [VocabularyEntry] = []
    @State private var firstVocabularyScrollIndexTitle = ""
    @State private var isFirstVocabularyScrollIndexVisible = false
    @State private var secondVocabularyEntries: [VocabularyEntry] = []
    @State private var secondVocabularyScrollIndexTitle = ""
    @State private var isSecondVocabularyScrollIndexVisible = false
    @State private var didLoadFirstVocabularyEntries = false
    @State private var isLoadingFirstVocabularyEntries = false
    @State private var didLoadSecondVocabularyEntries = false
    @State private var isLoadingSecondVocabularyEntries = false
    @State private var keyboardDiagnosticsLogLines: [String] = []
    @State private var keyboardDiagnosticsInstallMarker = ""
    @State private var keyboardDiagnosticsSessionActive = false
    @State private var keyboardDiagnosticsLastHeartbeatDate: Date?
    @State private var keyboardDiagnosticsLastEvent = ""
    @State private var keyboardDiagnosticsLastSessionID = ""
    @State private var keyboardDiagnosticsFailSafeProfile = "normal"
    @State private var containerDiagnosticsSessionID = UUID().uuidString
    @State private var didRunFirstAppearanceBootstrap = false
    @State private var didCompleteInitialDataSnapshot = false
    @State private var isBootstrappingInitialData = true
    @State private var containerBootstrapFailSafeWorkItem: DispatchWorkItem?
    @GestureState private var isEditionNumberPressed = false
    @Environment(\.scenePhase) private var scenePhase

    private let setupSteps: [String] = [
        "設定 > 一般 > キーボード > キーボード > 新しいキーボードを追加",
        "作成したキーボードを有効化",
        "入力画面で地球儀キーから切り替え"
    ]

    private var isContainerBusy: Bool {
        isBootstrappingInitialData || isLoadingFirstVocabularyEntries || isLoadingSecondVocabularyEntries
    }

    private var settingsSyncSignature: String {
        [
            directionProfileRawValue,
            kanaLayoutModeRawValue,
            landscapeCandidateSideRawValue,
            landscapeNumberPaneSideRawValue,
            landscapeLatinSuggestionModeRawValue,
            kanaModifierPlacementRawValue,
            latinLayoutModeRawValue,
            numberLayoutModeRawValue,
            basicSymbolOrderRawValue,
            accentPaletteRawValue,
            keyboardBackgroundThemeRawValue,
            kanaFlickGuideDisplayModeRawValue,
            latinFlickGuideDisplayModeRawValue,
            numberFlickGuideDisplayModeRawValue,
            modifierFlickGuideDisplayModeRawValue,
            String(keyRepeatInitialDelay),
            String(keyRepeatInterval),
            kanaModeSwitcherTapActionRawValue,
            kanaModeSwitcherRightFlickActionRawValue,
            kanaModeSwitcherUpFlickActionRawValue,
            delimiterAutoCommitCandidateRawValue,
            kanaKanjiCandidateSourceModeRawValue,
            userDictionaryCandidateDisplayModeRawValue,
            contactCandidateDisplayModeRawValue,
            String(emojiCandidateDisplayEnabled),
            String(kaomojiCandidateDisplayEnabled),
            String(historicalKanaCandidatesEnabled)
        ]
            .joined(separator: "|")
    }

    private func rawValueSelection<Option: RawRepresentable>(
        from rawValue: String,
        default fallback: Option,
        onUpdate: @escaping (String) -> Void
    ) -> Binding<Option> where Option.RawValue == String {
        Binding(
            get: { Option(rawValue: rawValue) ?? fallback },
            set: { onUpdate($0.rawValue) }
        )
    }

    private var directionSelection: Binding<DirectionOption> {
        rawValueSelection(from: directionProfileRawValue, default: .ecritu) {
            directionProfileRawValue = $0
        }
    }

    private var kanaLayoutSelection: Binding<KanaLayoutOption> {
        rawValueSelection(from: kanaLayoutModeRawValue, default: .fiveByTwo) {
            kanaLayoutModeRawValue = $0
        }
    }

    private var landscapeCandidateSideSelection: Binding<LandscapeCandidateSideOption> {
        rawValueSelection(from: landscapeCandidateSideRawValue, default: .left) {
            landscapeCandidateSideRawValue = $0
        }
    }

    private var landscapeNumberPaneSideSelection: Binding<LandscapeCandidateSideOption> {
        rawValueSelection(from: landscapeNumberPaneSideRawValue, default: .left) {
            landscapeNumberPaneSideRawValue = $0
        }
    }

    private var landscapeLatinSuggestionModeSelection: Binding<LandscapeLatinSuggestionModeOption> {
        rawValueSelection(from: landscapeLatinSuggestionModeRawValue, default: .sidebar) {
            landscapeLatinSuggestionModeRawValue = $0
        }
    }

    private var kanaModifierPlacementSelection: Binding<KanaModifierPlacementOption> {
        rawValueSelection(from: kanaModifierPlacementRawValue, default: .prefix) {
            kanaModifierPlacementRawValue = $0
        }
    }

    private var latinLayoutSelection: Binding<LatinLayoutOption> {
        rawValueSelection(from: latinLayoutModeRawValue, default: .azerty) {
            latinLayoutModeRawValue = $0
        }
    }

    private var numberLayoutSelection: Binding<NumberLayoutOption> {
        rawValueSelection(from: numberLayoutModeRawValue, default: .calculette) {
            numberLayoutModeRawValue = $0
        }
    }

    private var basicSymbolOrderSelection: Binding<BasicSymbolOrderOption> {
        rawValueSelection(from: basicSymbolOrderRawValue, default: .ascii) {
            basicSymbolOrderRawValue = $0
        }
    }

    private var kanaFlickGuideDisplayModeSelection: Binding<FlickGuideDisplayOption> {
        rawValueSelection(from: kanaFlickGuideDisplayModeRawValue, default: .fourDirections) {
            kanaFlickGuideDisplayModeRawValue = $0
        }
    }

    private var latinFlickGuideDisplayModeSelection: Binding<FlickGuideDisplayOption> {
        rawValueSelection(from: latinFlickGuideDisplayModeRawValue, default: .fourDirections) {
            latinFlickGuideDisplayModeRawValue = $0
        }
    }

    private var numberFlickGuideDisplayModeSelection: Binding<FlickGuideDisplayOption> {
        rawValueSelection(from: numberFlickGuideDisplayModeRawValue, default: .fourDirections) {
            numberFlickGuideDisplayModeRawValue = $0
        }
    }

    private var modifierFlickGuideDisplayModeSelection: Binding<FlickGuideDisplayOption> {
        rawValueSelection(from: modifierFlickGuideDisplayModeRawValue, default: .fourDirections) {
            modifierFlickGuideDisplayModeRawValue = $0
        }
    }

    private var isLatinFlickLayoutSelected: Bool {
        (LatinLayoutOption(rawValue: latinLayoutModeRawValue) ?? .azerty) == .flick
    }

    private var kanaKanjiCandidateSourceModeSelection: Binding<KanaKanjiCandidateSourceModeOption> {
        rawValueSelection(from: kanaKanjiCandidateSourceModeRawValue, default: .surface) {
            kanaKanjiCandidateSourceModeRawValue = $0
        }
    }

    private var contactCandidateDisplayModeSelection: Binding<ContactCandidateDisplayModeOption> {
        rawValueSelection(from: contactCandidateDisplayModeRawValue, default: .namesOnly) {
            contactCandidateDisplayModeRawValue = $0
        }
    }

    private var userDictionaryCandidateDisplayModeSelection: Binding<UserDictionaryCandidateDisplayModeOption> {
        rawValueSelection(from: userDictionaryCandidateDisplayModeRawValue, default: .on) {
            userDictionaryCandidateDisplayModeRawValue = $0
        }
    }

    private var shouldUseContactCandidates: Bool {
        (ContactCandidateDisplayModeOption(rawValue: contactCandidateDisplayModeRawValue) ?? .namesOnly) != .off
    }

    private var accentPaletteSelection: Binding<AccentColorOption> {
        rawValueSelection(from: accentPaletteRawValue, default: .emeraude) {
            accentPaletteRawValue = $0
        }
    }

    private var keyboardBackgroundThemeSelection: Binding<KeyboardBackgroundThemeOption> {
        rawValueSelection(from: keyboardBackgroundThemeRawValue, default: .bleu) {
            keyboardBackgroundThemeRawValue = $0
        }
    }

    private func snappedRepeatValue(_ value: Double, to defaultValue: Double) -> Double {
        abs(value - defaultValue) <= RepeatSettings.snapThreshold ? defaultValue : value
    }

    private func migrateLegacyFlickGuideSettingIfNeeded() {
        guard let defaults = Self.sharedDefaults else {
            return
        }

        let modifierGuideModeKey = SettingsKeys.modifierFlickGuideDisplayMode
        let guideModeKeys = [
            SettingsKeys.kanaFlickGuideDisplayMode,
            SettingsKeys.latinFlickGuideDisplayMode,
            SettingsKeys.numberFlickGuideDisplayMode,
            modifierGuideModeKey
        ]

        let hasStoredNewGuideMode = guideModeKeys.contains { key in
            defaults.object(forKey: key) != nil
        }

        if !hasStoredNewGuideMode,
            let legacyShowsGuide = defaults.object(forKey: SettingsKeys.showsFlickGuideCharacters) as? Bool {
            let migratedMode = legacyShowsGuide
                ? FlickGuideDisplayOption.fourDirections.rawValue
                : FlickGuideDisplayOption.off.rawValue

            guideModeKeys.forEach { key in
                defaults.set(migratedMode, forKey: key)
            }
        }

        if defaults.object(forKey: modifierGuideModeKey) == nil {
            let migratedModifierMode = defaults.string(forKey: SettingsKeys.kanaFlickGuideDisplayMode)
                ?? {
                    guard let legacyShowsGuide = defaults.object(forKey: SettingsKeys.showsFlickGuideCharacters) as? Bool else {
                        return FlickGuideDisplayOption.fourDirections.rawValue
                    }

                    return legacyShowsGuide
                        ? FlickGuideDisplayOption.fourDirections.rawValue
                        : FlickGuideDisplayOption.off.rawValue
                }()
            defaults.set(migratedModifierMode, forKey: modifierGuideModeKey)
        }
    }

    private var keyRepeatInitialDelayBinding: Binding<Double> {
        Binding(
            get: { keyRepeatInitialDelay },
            set: { keyRepeatInitialDelay = snappedRepeatValue($0, to: RepeatSettings.initialDelayDefault) }
        )
    }

    private var keyRepeatIntervalBinding: Binding<Double> {
        Binding(
            get: { keyRepeatInterval },
            set: { keyRepeatInterval = snappedRepeatValue($0, to: RepeatSettings.intervalDefault) }
        )
    }

    private var kanaModeSwitcherTapActionSelection: Binding<KanaModeSwitcherActionOption> {
        rawValueSelection(from: kanaModeSwitcherTapActionRawValue, default: .emoji) {
            kanaModeSwitcherTapActionRawValue = $0
        }
    }

    private var kanaModeSwitcherRightFlickActionSelection: Binding<KanaModeSwitcherActionOption> {
        rawValueSelection(from: kanaModeSwitcherRightFlickActionRawValue, default: .kaomoji) {
            kanaModeSwitcherRightFlickActionRawValue = $0
        }
    }

    private var kanaModeSwitcherUpFlickActionSelection: Binding<KanaModeSwitcherActionOption> {
        rawValueSelection(from: kanaModeSwitcherUpFlickActionRawValue, default: .symbols) {
            kanaModeSwitcherUpFlickActionRawValue = $0
        }
    }

    private var kanaPostModifierEmptyTapActionSelection: Binding<KanaPostModifierEmptyTapActionOption> {
        rawValueSelection(from: kanaPostModifierEmptyTapActionRawValue, default: .default) {
            kanaPostModifierEmptyTapActionRawValue = $0
        }
    }

    private var kanaPostModifierEmptyTapKaomojiCategoryBinding: Binding<String> {
        Binding(
            get: { kanaPostModifierEmptyTapKaomojiCategoryID },
            set: { kanaPostModifierEmptyTapKaomojiCategoryID = $0 }
        )
    }

    private var kanaPostModifierEmptyTapEmojiCategoryBinding: Binding<String> {
        Binding(
            get: { kanaPostModifierEmptyTapEmojiCategoryID },
            set: { kanaPostModifierEmptyTapEmojiCategoryID = $0 }
        )
    }

    private var kanaPostModifierEmptyTapSymbolCategoryBinding: Binding<String> {
        Binding(
            get: { kanaPostModifierEmptyTapSymbolCategoryID },
            set: { kanaPostModifierEmptyTapSymbolCategoryID = $0 }
        )
    }

    private var delimiterAutoCommitCandidateSelection: Binding<DelimiterAutoCommitCandidateOption> {
        rawValueSelection(from: delimiterAutoCommitCandidateRawValue, default: .zero) {
            delimiterAutoCommitCandidateRawValue = $0
        }
    }

    private var canAddUserDictionaryEntry: Bool {
        !normalizedKanaReading(from: userDictionaryReadingInput).isEmpty
            && !userDictionaryCandidateInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canAddSuppressionDictionaryEntry: Bool {
        !normalizedKanaReading(from: suppressionDictionaryReadingInput).isEmpty
            && !suppressionDictionaryCandidateInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canAddShortcutDictionaryEntry: Bool {
        !shortcutDictionaryCandidateInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var userVocabularyListMaxHeight: CGFloat {
        // Give section-index titles more vertical breathing room.
        336
    }

    private var userVocabularyListMinHeight: CGFloat {
        // Keep this above the custom-index top/bottom insets to avoid layout conflicts.
        40
    }

    private var userVocabularyListRowHeight: CGFloat {
        30
    }

    private func userVocabularyListHeight(for entryCount: Int) -> CGFloat {
        let contentHeight = CGFloat(max(entryCount, 1)) * userVocabularyListRowHeight
        return min(userVocabularyListMaxHeight, max(userVocabularyListMinHeight, contentHeight))
    }

    private func clearLegacyKeyboardDebugLogKeysIfNeeded() {
        guard let defaults = Self.sharedDefaults,
            !defaults.bool(forKey: SettingsKeys.legacyKeyboardDebugLogCleanupCompleted) else {
            return
        }

        let legacyKeys = [
            "keyboardLayoutDebugLines",
            "keyboardLayoutDebugHeartbeat",
            "keyboardLayoutDebugReporterBundleID",
            "keyboardLayoutDebugReporterAppGroupID",
            "keyboardLayoutDebugLastEvent",
            "keyboardInputProbeCount",
            "keyboardInputProbeHeartbeat",
            "keyboardInputProbeLastEvent",
            "keyboardInputProbeLastText"
        ]

        for key in legacyKeys {
            defaults.removeObject(forKey: key)
        }

        defaults.set(true, forKey: SettingsKeys.legacyKeyboardDebugLogCleanupCompleted)
    }

    private func normalizedKanaReading(from text: String) -> String {
        var result = ""

        for character in text {
            let source = String(character)
            let normalized = source.applyingTransform(.hiraganaToKatakana, reverse: true) ?? source

            guard normalized.count == 1,
                    let first = normalized.first,
                    let scalar = String(first).unicodeScalars.first else {
                continue
            }

            if (0x3040...0x309F).contains(scalar.value) || scalar.value == 0x30FC {
                result.append(first)
            }
        }

        return result
    }

    private func loadDictionaryEntries(forKey key: String) -> [String: [String]] {
        guard let defaults = Self.sharedDefaults else {
            return [:]
        }

        if let dictionaryData = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode([String: [String]].self, from: dictionaryData) {
            return decoded
        }

        guard let rawDictionary = defaults.dictionary(forKey: key) else {
            return [:]
        }

        var decoded: [String: [String]] = [:]

        for (reading, rawCandidates) in rawDictionary {
            if let candidates = rawCandidates as? [String] {
                decoded[reading] = candidates
            } else if let candidates = rawCandidates as? [Any] {
                decoded[reading] = candidates.compactMap { $0 as? String }
            }
        }

        return decoded
    }

    private func decodeStringArray(forKey key: String, defaults: UserDefaults) -> [String] {
        let maxLogDataBytes = 262_144
        let maxLogLineCount = 320

        if let data = defaults.data(forKey: key),
            data.count <= maxLogDataBytes,
            let decoded = try? JSONDecoder().decode([String].self, from: data) {
            return Array(decoded.suffix(maxLogLineCount))
        }

        if let data = defaults.data(forKey: key),
            data.count > maxLogDataBytes {
            defaults.removeObject(forKey: key)
            return []
        }

        if let raw = defaults.array(forKey: key) {
            return Array(raw.compactMap { $0 as? String }.suffix(maxLogLineCount))
        }

        return []
    }

    private func keyboardExtensionBundleForDiagnostics() -> Bundle? {
        guard let pluginsURL = Bundle.main.builtInPlugInsURL,
            let pluginURLs = try? FileManager.default.contentsOfDirectory(
                at: pluginsURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
            return nil
        }

        for pluginURL in pluginURLs where pluginURL.pathExtension == "appex" {
            guard let bundle = Bundle(url: pluginURL),
                let bundleID = bundle.bundleIdentifier else {
                continue
            }

            if bundleID.hasSuffix(".keyboard") {
                return bundle
            }
        }

        guard let firstPluginURL = pluginURLs.first(where: { $0.pathExtension == "appex" }) else {
            return nil
        }

        return Bundle(url: firstPluginURL)
    }

    private func keyboardDiagnosticsInstallMarkerForCurrentBuild() -> String {
        let bundle = keyboardExtensionBundleForDiagnostics() ?? Bundle.main
        let bundleID = bundle.bundleIdentifier ?? "unknown.keyboard.bundle"
        let buildNumber = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "?"
        return "\(bundleID)|\(buildNumber)|build"
    }

    private func clearKeyboardDiagnosticsIfInstallChanged() {
        guard let defaults = Self.sharedDefaults else {
            return
        }

        let currentMarker = keyboardDiagnosticsInstallMarkerForCurrentBuild()
        let savedMarker = defaults.string(forKey: SettingsKeys.keyboardDiagnosticsInstallMarker)

        if savedMarker != currentMarker {
            defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsLogLines)
            defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsFlightRecorderEvents)
            defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsSessionActive)
            defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsSessionOwnerToken)
            defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsLastHeartbeat)
            defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsLastEvent)
            defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsLastSessionID)
            defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsFailSafeProfile)
            defaults.set(currentMarker, forKey: SettingsKeys.keyboardDiagnosticsInstallMarker)
        }

        keyboardDiagnosticsInstallMarker = currentMarker
    }

    private func loadKeyboardDiagnosticsState() {
        guard let defaults = Self.sharedDefaults else {
            keyboardDiagnosticsLogLines = []
            keyboardDiagnosticsInstallMarker = ""
            keyboardDiagnosticsSessionActive = false
            keyboardDiagnosticsLastHeartbeatDate = nil
            keyboardDiagnosticsLastEvent = ""
            keyboardDiagnosticsLastSessionID = ""
            keyboardDiagnosticsFailSafeProfile = "normal"
            return
        }

        keyboardDiagnosticsLogLines = decodeStringArray(
            forKey: SettingsKeys.keyboardDiagnosticsLogLines,
            defaults: defaults
        )
        keyboardDiagnosticsInstallMarker = defaults.string(
            forKey: SettingsKeys.keyboardDiagnosticsInstallMarker
        ) ?? ""
        keyboardDiagnosticsSessionActive = defaults.bool(
            forKey: SettingsKeys.keyboardDiagnosticsSessionActive
        )

        let heartbeatRawValue = defaults.double(forKey: SettingsKeys.keyboardDiagnosticsLastHeartbeat)
        keyboardDiagnosticsLastHeartbeatDate = heartbeatRawValue > 0
            ? Date(timeIntervalSince1970: heartbeatRawValue)
            : nil

        keyboardDiagnosticsLastEvent = defaults.string(
            forKey: SettingsKeys.keyboardDiagnosticsLastEvent
        ) ?? ""
        keyboardDiagnosticsLastSessionID = defaults.string(
            forKey: SettingsKeys.keyboardDiagnosticsLastSessionID
        ) ?? ""

        let failSafeRawValue = defaults.string(
            forKey: SettingsKeys.keyboardDiagnosticsFailSafeProfile
        ) ?? "normal"
        keyboardDiagnosticsFailSafeProfile = normalizedKeyboardDiagnosticsFailSafeProfile(
            failSafeRawValue
        )
    }

    private func clearKeyboardDiagnosticsState() {
        guard let defaults = Self.sharedDefaults else {
            return
        }

        defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsLogLines)
        defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsFlightRecorderEvents)
        defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsSessionActive)
        defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsSessionOwnerToken)
        defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsLastHeartbeat)
        defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsLastEvent)
        defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsLastSessionID)
        defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsFailSafeProfile)
        loadKeyboardDiagnosticsState()
    }

    private func normalizedKeyboardDiagnosticsFailSafeProfile(_ rawValue: String) -> String {
        switch rawValue {
        case "normal", "elevated", "critical":
            return rawValue
        default:
            return "normal"
        }
    }

    private func keyboardDiagnosticsLastHeartbeatText() -> String {
        guard let keyboardDiagnosticsLastHeartbeatDate else {
            return "記録なし"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: keyboardDiagnosticsLastHeartbeatDate)
    }

    private func keyboardDiagnosticsExportText() -> String {
        var sections: [String] = []
        sections.append("installMarker: \(keyboardDiagnosticsInstallMarker)")
        sections.append("sessionActive: \(keyboardDiagnosticsSessionActive ? "true" : "false")")
        sections.append("failSafeProfile: \(keyboardDiagnosticsFailSafeProfile)")
        sections.append("lastHeartbeat: \(keyboardDiagnosticsLastHeartbeatText())")
        sections.append("lastSessionID: \(keyboardDiagnosticsLastSessionID)")
        sections.append("lastEvent: \(keyboardDiagnosticsLastEvent)")
        sections.append("--- logs ---")
        sections.append(contentsOf: keyboardDiagnosticsLogLines)
        return sections.joined(separator: "\n")
    }

    private func copyKeyboardDiagnosticsToPasteboard() {
#if os(iOS)
        UIPasteboard.general.string = keyboardDiagnosticsExportText()
#endif
    }

    private func loadLearningScores() -> [String: Int] {
        guard let defaults = Self.sharedDefaults,
            let learningData = defaults.data(forKey: SettingsKeys.kanaKanjiLearningScores),
            let decoded = try? JSONDecoder().decode([String: Int].self, from: learningData) else {
            return [:]
        }

        return decoded
    }

    private func parseLearningKey(_ key: String) -> VocabularyEntry? {
        guard let separatorIndex = key.firstIndex(of: "\t") else {
            return nil
        }

        let readingRaw = String(key[..<separatorIndex])
        let candidateStartIndex = key.index(after: separatorIndex)
        let candidateRaw = String(key[candidateStartIndex...])
        let reading = normalizedKanaReading(from: readingRaw)
        let candidate = candidateRaw.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !reading.isEmpty,
            !candidate.isEmpty else {
            return nil
        }

        return VocabularyEntry(reading: reading, candidate: candidate)
    }

    private func uniqueCandidatesPreservingOrder(_ candidates: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmed.isEmpty,
                    seen.insert(trimmed).inserted else {
                continue
            }

            result.append(trimmed)
        }

        return result
    }

    private func uniqueShortcutCandidatesPreservingOrder(_ candidates: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for candidate in candidates {
            guard !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                seen.insert(candidate).inserted else {
                continue
            }

            result.append(candidate)
        }

        return result
    }

    private func normalizedDictionaryEntries(_ dictionary: [String: [String]]) -> [String: [String]] {
        var normalized: [String: [String]] = [:]

        for (reading, candidates) in dictionary {
            let normalizedReading = normalizedKanaReading(from: reading)

            guard !normalizedReading.isEmpty else {
                continue
            }

            let mergedCandidates = uniqueCandidatesPreservingOrder(
                (normalized[normalizedReading] ?? []) + candidates
            )

            if !mergedCandidates.isEmpty {
                normalized[normalizedReading] = mergedCandidates
            }
        }

        return normalized
    }

    private func mergedDictionary(
        preferred: [String: [String]],
        fallback: [String: [String]]
    ) -> [String: [String]] {
        var merged = fallback

        for (reading, preferredCandidates) in preferred {
            let combined = uniqueCandidatesPreservingOrder(
                preferredCandidates + (fallback[reading] ?? [])
            )

            if combined.isEmpty {
                merged.removeValue(forKey: reading)
            } else {
                merged[reading] = combined
            }
        }

        return merged
    }

    private func dictionarySignature(_ dictionary: [String: [String]]) -> String {
        let normalized = normalizedDictionaryEntries(dictionary)

        guard !normalized.isEmpty else {
            return "empty"
        }

        guard let data = try? JSONSerialization.data(
            withJSONObject: normalized,
            options: [.sortedKeys]
        ) else {
            return "encoding-error"
        }

        var hash: UInt64 = 0xcbf29ce484222325

        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }

        return String(format: "%016llx", hash)
    }

    private func loadBundledInitialDictionaryEntries(filename: String) -> [String: [String]] {
        let fileExtension = "json"

        if let resourceURL = Bundle.main.url(forResource: filename, withExtension: fileExtension),
            let data = try? Data(contentsOf: resourceURL),
            let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            return normalizedDictionaryEntries(decoded)
        }

        if let pluginsURL = Bundle.main.builtInPlugInsURL,
            let pluginURLs = try? FileManager.default.contentsOfDirectory(
                at: pluginsURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
            for pluginURL in pluginURLs where pluginURL.pathExtension == "appex" {
                let resourceURL = pluginURL.appendingPathComponent("\(filename).\(fileExtension)")

                guard FileManager.default.fileExists(atPath: resourceURL.path),
                        let data = try? Data(contentsOf: resourceURL),
                        let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
                    continue
                }

                return normalizedDictionaryEntries(decoded)
            }
        }

        return [:]
    }

    private func loadBundledInitialUserDictionaryEntries() -> [String: [String]] {
        loadBundledInitialDictionaryEntries(filename: "InitialAjoutVocabMigration")
    }

    private func loadBundledInitialSuppressionDictionaryEntries() -> [String: [String]] {
        loadBundledInitialDictionaryEntries(filename: "InitialSupprVocabMigration")
    }

    private func loadBundledInitialShortcutVocabularyEntries() -> [String] {
        let fileExtension = "json"
        let filename = "InitialShortcutVocabMigration"

        if let resourceURL = Bundle.main.url(forResource: filename, withExtension: fileExtension),
            let data = try? Data(contentsOf: resourceURL),
            let decoded = try? JSONDecoder().decode([String].self, from: data) {
            return uniqueShortcutCandidatesPreservingOrder(decoded)
        }

        if let pluginsURL = Bundle.main.builtInPlugInsURL,
            let pluginURLs = try? FileManager.default.contentsOfDirectory(
                at: pluginsURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
            for pluginURL in pluginURLs where pluginURL.pathExtension == "appex" {
                let resourceURL = pluginURL.appendingPathComponent("\(filename).\(fileExtension)")

                guard FileManager.default.fileExists(atPath: resourceURL.path),
                    let data = try? Data(contentsOf: resourceURL),
                    let decoded = try? JSONDecoder().decode([String].self, from: data) else {
                    continue
                }

                return uniqueShortcutCandidatesPreservingOrder(decoded)
            }
        }

        return []
    }

    private func loadShortcutVocabularyCandidates() -> [String] {
        guard let defaults = Self.sharedDefaults else {
            return []
        }

        if let shortcutData = defaults.data(forKey: SettingsKeys.kanaKanjiShortcutVocabulary),
            let decoded = try? JSONDecoder().decode([String].self, from: shortcutData) {
            return uniqueShortcutCandidatesPreservingOrder(decoded)
        }

        if let rawArray = defaults.array(forKey: SettingsKeys.kanaKanjiShortcutVocabulary) {
            return uniqueShortcutCandidatesPreservingOrder(rawArray.compactMap { $0 as? String })
        }

        let legacyDictionary = loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiShortcutVocabulary)

        if !legacyDictionary.isEmpty {
            let candidates = legacyDictionary["☻"] ?? legacyDictionary
                .keys
                .sorted()
                .flatMap { legacyDictionary[$0] ?? [] }
            return uniqueShortcutCandidatesPreservingOrder(candidates)
        }

        return []
    }

    private func saveShortcutVocabularyCandidates(_ candidates: [String]) {
        guard let defaults = Self.sharedDefaults,
            let encoded = try? JSONEncoder().encode(candidates) else {
            return
        }

        defaults.set(encoded, forKey: SettingsKeys.kanaKanjiShortcutVocabulary)
        SettingsSyncNotification.postSettingsDidChange()
    }

    private func loadAppGroupDictionaryEntries(filename: String) -> [String: [String]] {
        guard
            let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: SettingsKeys.appGroupID
            )
        else {
            return [:]
        }

        let fileURL = containerURL.appendingPathComponent(filename)

        guard
            let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode([String: [String]].self, from: data)
        else {
            return [:]
        }

        return normalizedDictionaryEntries(decoded)
    }

    private func sortedVocabularyEntries(from dictionary: [String: [String]]) -> [VocabularyEntry] {
        dictionary
            .keys
            .sorted()
            .flatMap { reading in
                (dictionary[reading] ?? []).map { candidate in
                    VocabularyEntry(reading: reading, candidate: candidate)
                }
            }
    }

    private struct InitialDataSnapshot {
        let userDictionaryEntries: [VocabularyEntry]
        let learnedDictionaryEntries: [VocabularyEntry]
        let suppressionDictionaryEntries: [VocabularyEntry]
        let shortcutDictionaryEntries: [VocabularyEntry]
    }

    private func firstSystemVocabularyEntriesSnapshot() -> [VocabularyEntry] {
        let firstFromAppGroup = loadAppGroupDictionaryEntries(filename: "ÉcrituPremierVocab.json")
        let firstDictionary = firstFromAppGroup.isEmpty
            ? loadBundledInitialDictionaryEntries(filename: "ÉcrituPremierVocab")
            : firstFromAppGroup

        return sortedVocabularyEntries(from: firstDictionary)
    }

    private func secondSystemVocabularyEntriesSnapshot() -> [VocabularyEntry] {
        let secondFromAppGroup = loadAppGroupDictionaryEntries(filename: "ÉcrituSecondVocab.json")
        let secondDictionary = secondFromAppGroup.isEmpty
            ? loadBundledInitialDictionaryEntries(filename: "ÉcrituSecondVocab")
            : secondFromAppGroup

        return sortedVocabularyEntries(from: secondDictionary)
    }

    private func buildInitialDataSnapshot() -> InitialDataSnapshot {
        return InitialDataSnapshot(
            userDictionaryEntries: userDictionaryEntriesSnapshot(),
            learnedDictionaryEntries: learnedDictionaryEntriesSnapshot(),
            suppressionDictionaryEntries: suppressionDictionaryEntriesSnapshot(),
            shortcutDictionaryEntries: shortcutDictionaryEntriesSnapshot()
        )
    }

    private func applyInitialDataSnapshot(_ snapshot: InitialDataSnapshot) {
        userDictionaryEntries = snapshot.userDictionaryEntries
        learnedDictionaryEntries = snapshot.learnedDictionaryEntries
        suppressionDictionaryEntries = snapshot.suppressionDictionaryEntries
        shortcutDictionaryEntries = snapshot.shortcutDictionaryEntries
    }

    private func loadInitialDataSnapshotInBackground() async -> InitialDataSnapshot {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let snapshot = buildInitialDataSnapshot()
                continuation.resume(returning: snapshot)
            }
        }
    }

    private func performInitialMigrationsInBackground() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                migrateInitialUserDictionaryIfNeeded()
                migrateInitialShortcutVocabularyIfNeeded()
                migrateInitialSuppressionDictionaryIfNeeded()
                migrateLearningVocabularySeparationIfNeeded()
                continuation.resume()
            }
        }
    }

    private func startInitialSnapshotLoadInBackground(
        logEventPrefix: String,
        onCompleted: (() -> Void)? = nil
    ) {
        Task { @MainActor in
            let snapshotStartedAt = CFAbsoluteTimeGetCurrent()
            let snapshot = await loadInitialDataSnapshotInBackground()
            applyInitialDataSnapshot(snapshot)
            didCompleteInitialDataSnapshot = true

            appendContainerDiagnosticsLog(
                "\(logEventPrefix) snapshot反映完了 elapsedMs=\(containerDiagnosticsElapsedMilliseconds(since: snapshotStartedAt)) user=\(snapshot.userDictionaryEntries.count) learned=\(snapshot.learnedDictionaryEntries.count) suppression=\(snapshot.suppressionDictionaryEntries.count) shortcut=\(snapshot.shortcutDictionaryEntries.count)"
            )
            loadKeyboardDiagnosticsState()
            onCompleted?()
        }
    }

    private func startInitialMigrationsAndRefreshSnapshotInBackground(onCompleted: (() -> Void)? = nil) {
        Task { @MainActor in
            let migrationStartedAt = CFAbsoluteTimeGetCurrent()
            await performInitialMigrationsInBackground()

            let migratedSnapshot = await loadInitialDataSnapshotInBackground()
            applyInitialDataSnapshot(migratedSnapshot)

            appendContainerDiagnosticsLog(
                "コンテナ初回表示 migration反映完了 elapsedMs=\(containerDiagnosticsElapsedMilliseconds(since: migrationStartedAt)) user=\(migratedSnapshot.userDictionaryEntries.count) learned=\(migratedSnapshot.learnedDictionaryEntries.count) suppression=\(migratedSnapshot.suppressionDictionaryEntries.count) shortcut=\(migratedSnapshot.shortcutDictionaryEntries.count)"
            )
            loadKeyboardDiagnosticsState()
            SettingsSyncNotification.postSettingsDidChange()
            onCompleted?()
        }
    }

    private func shouldAutoLoadSystemVocabularyOnAppear() -> Bool {
        false
    }

    private func saveStringArray(_ values: [String], forKey key: String, defaults: UserDefaults) {
        if let encoded = try? JSONEncoder().encode(values) {
            defaults.set(encoded, forKey: key)
            return
        }

        defaults.set(values, forKey: key)
    }

    private func containerDiagnosticsProcessLabel() -> String {
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown.container.bundle"
        let processName = ProcessInfo.processInfo.processName
        return "\(bundleID)(\(processName))"
    }

    private func containerCurrentResidentMemoryBytes() -> UInt64? {
        var info = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<integer_t>.size
        )

        let result: kern_return_t = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), intPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }

        return UInt64(info.resident_size)
    }

    private func containerResidentMemoryMBText() -> String {
        guard let bytes = containerCurrentResidentMemoryBytes() else {
            return "unknown"
        }

        let mb = Double(bytes) / 1_048_576
        return String(format: "%.1f", mb)
    }

    private func appendContainerDiagnosticsLog(
        _ event: String,
        file: String = #fileID,
        line: Int = #line,
        function: String = #function
    ) {
        guard let defaults = Self.sharedDefaults else {
            return
        }

        let sourceFile = (file as NSString).lastPathComponent
        let timestamp = Self.diagnosticsTimestampFormatter.string(from: Date())
        let context =
            "process=\(containerDiagnosticsProcessLabel()) rssMB=\(containerResidentMemoryMBText())"
        let entry =
            "\(timestamp) [container:\(containerDiagnosticsSessionID)] \(event) {\(context)} (\(sourceFile):\(line) \(function))"

        var lines = decodeStringArray(
            forKey: SettingsKeys.keyboardDiagnosticsLogLines,
            defaults: defaults
        )
        lines.append(entry)

        let maxLineCount = 320
        if lines.count > maxLineCount {
            lines.removeFirst(lines.count - maxLineCount)
        }

        saveStringArray(lines, forKey: SettingsKeys.keyboardDiagnosticsLogLines, defaults: defaults)
    }

    private func containerDiagnosticsElapsedMilliseconds(since start: CFAbsoluteTime) -> Int {
        max(0, Int((CFAbsoluteTimeGetCurrent() - start) * 1000))
    }

    private func loadFirstSystemVocabularyEntriesInBackground() async -> [VocabularyEntry] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: firstSystemVocabularyEntriesSnapshot())
            }
        }
    }

    private func loadSecondSystemVocabularyEntriesInBackground() async -> [VocabularyEntry] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: secondSystemVocabularyEntriesSnapshot())
            }
        }
    }

    private func requestFirstSystemVocabularyEntriesLoadIfNeeded(force: Bool = false) {
        guard !isLoadingFirstVocabularyEntries else {
            return
        }

        guard force || !didLoadFirstVocabularyEntries else {
            return
        }

        isLoadingFirstVocabularyEntries = true
        let loadStartedAt = CFAbsoluteTimeGetCurrent()
        appendContainerDiagnosticsLog("コンテナで第1語彙ロード開始 force=\(force)")

        Task { @MainActor in
            let firstEntries = await loadFirstSystemVocabularyEntriesInBackground()
            firstVocabularyEntries = firstEntries
            didLoadFirstVocabularyEntries = true
            isLoadingFirstVocabularyEntries = false
            finishBootstrappingIfNeeded()

            appendContainerDiagnosticsLog(
                "コンテナで第1語彙ロード完了 count=\(firstEntries.count) elapsedMs=\(containerDiagnosticsElapsedMilliseconds(since: loadStartedAt))"
            )
            loadKeyboardDiagnosticsState()
        }
    }

    private func requestSecondSystemVocabularyEntriesLoadIfNeeded(force: Bool = false) {
        guard !isLoadingSecondVocabularyEntries else {
            return
        }

        guard force || !didLoadSecondVocabularyEntries else {
            return
        }

        isLoadingSecondVocabularyEntries = true
        let loadStartedAt = CFAbsoluteTimeGetCurrent()
        appendContainerDiagnosticsLog("コンテナで第2語彙ロード開始 force=\(force)")

        Task { @MainActor in
            let secondEntries = await loadSecondSystemVocabularyEntriesInBackground()
            secondVocabularyEntries = secondEntries
            didLoadSecondVocabularyEntries = true
            isLoadingSecondVocabularyEntries = false
            finishBootstrappingIfNeeded()

            appendContainerDiagnosticsLog(
                "コンテナで第2語彙ロード完了 count=\(secondEntries.count) elapsedMs=\(containerDiagnosticsElapsedMilliseconds(since: loadStartedAt))"
            )
            loadKeyboardDiagnosticsState()
        }
    }

    private func requestContactsAccessIfNeeded() async {
        guard shouldUseContactCandidates else {
            appendContainerDiagnosticsLog("連絡先アクセス許可リクエスト中止 reason=contactCandidatesDisabled")
            return
        }

        let usageDescription = (Bundle.main.object(forInfoDictionaryKey: "NSContactsUsageDescription") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""

        guard !usageDescription.isEmpty else {
            appendContainerDiagnosticsLog("連絡先アクセス許可リクエスト中止 reason=missingUsageDescription")
            return
        }

        let status = CNContactStore.authorizationStatus(for: .contacts)

        switch status {
        case .authorized, .limited:
            appendContainerDiagnosticsLog("連絡先アクセス状態 status=authorized")
        case .denied, .restricted:
            appendContainerDiagnosticsLog("連絡先アクセス状態 status=deniedOrRestricted")
        case .notDetermined:
            appendContainerDiagnosticsLog("連絡先アクセス許可リクエスト開始")
            let granted = await withCheckedContinuation { continuation in
                CNContactStore().requestAccess(for: .contacts) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
            appendContainerDiagnosticsLog("連絡先アクセス許可リクエスト完了 granted=\(granted)")
        @unknown default:
            appendContainerDiagnosticsLog("連絡先アクセス状態 status=unknown")
        }

        syncContactCandidatesCacheFromContainerApp()
    }

    private func syncContactCandidatesCacheFromContainerApp() {
        guard let defaults = Self.sharedDefaults else {
            return
        }

        let cacheKey = SettingsKeys.contactCandidatesByReadingCache
        let mode = ContactCandidateDisplayModeOption(rawValue: contactCandidateDisplayModeRawValue) ?? .namesOnly

        guard mode != .off else {
            if defaults.object(forKey: cacheKey) != nil {
                defaults.removeObject(forKey: cacheKey)
                SettingsSyncNotification.postSettingsDidChange()
            }
            return
        }

        let status = CNContactStore.authorizationStatus(for: .contacts)

        guard hasGrantedContactsAccess(status) else {
            if defaults.object(forKey: cacheKey) != nil {
                defaults.removeObject(forKey: cacheKey)
                SettingsSyncNotification.postSettingsDidChange()
            }
            return
        }

        DispatchQueue.global(qos: .utility).async {
            let dictionary = Self.buildContactCandidatesByReading(displayMode: mode)

            DispatchQueue.main.async {
                guard let defaults = Self.sharedDefaults else {
                    return
                }

                let previous = defaults.dictionary(forKey: cacheKey) as? [String: [String]] ?? [:]

                guard previous != dictionary else {
                    return
                }

                defaults.set(dictionary, forKey: cacheKey)
                SettingsSyncNotification.postSettingsDidChange()
            }
        }
    }

    private func hasGrantedContactsAccess(_ status: CNAuthorizationStatus) -> Bool {
        if #available(iOS 18.0, *) {
            return status == .authorized || status == .limited
        }

        return status == .authorized
    }

    private func requestContactsAccessIfNeededInBackground() {
        Task { @MainActor in
            await requestContactsAccessIfNeeded()
        }
    }

    private func finishBootstrappingIfNeeded() {
        guard !isLoadingFirstVocabularyEntries,
            !isLoadingSecondVocabularyEntries else {
            return
        }

        guard isBootstrappingInitialData else {
            return
        }

        isBootstrappingInitialData = false
        containerBootstrapFailSafeWorkItem?.cancel()
        containerBootstrapFailSafeWorkItem = nil
    }

    private func scheduleContainerBootstrapFailSafe(timeoutSeconds: TimeInterval = 15) {
        containerBootstrapFailSafeWorkItem?.cancel()

        let workItem = DispatchWorkItem {
            guard isContainerBusy else {
                return
            }

            appendContainerDiagnosticsLog(
                "コンテナbootstrapフェイルセーフ発動 busy解除 timeoutSeconds=\(Int(timeoutSeconds))"
            )
            isLoadingFirstVocabularyEntries = false
            isLoadingSecondVocabularyEntries = false
            isBootstrappingInitialData = false
            didCompleteInitialDataSnapshot = true
            loadKeyboardDiagnosticsState()
        }

        containerBootstrapFailSafeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds, execute: workItem)
    }

    private func migrateInitialUserDictionaryIfNeeded() {
        guard let defaults = Self.sharedDefaults else {
            return
        }

        let initialDictionary = loadBundledInitialUserDictionaryEntries()

        guard !initialDictionary.isEmpty else {
            return
        }

        let initialSignature = dictionarySignature(initialDictionary)
        let appliedSignature = defaults.string(
            forKey: SettingsKeys.kanaKanjiInitialUserDictionaryAppliedSignature
        )

        guard appliedSignature != initialSignature else {
            return
        }

        let currentDictionary = normalizedDictionaryEntries(
            loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiAjoutVocabulary)
        )

        let merged = mergedDictionary(preferred: currentDictionary, fallback: initialDictionary)

        if merged != currentDictionary {
            saveDictionaryEntries(merged, forKey: SettingsKeys.kanaKanjiAjoutVocabulary)
        }

        defaults.set(true, forKey: SettingsKeys.kanaKanjiInitialUserDictionaryMigrated)
        defaults.set(
            initialSignature,
            forKey: SettingsKeys.kanaKanjiInitialUserDictionaryAppliedSignature
        )
    }

    private func migrateInitialSuppressionDictionaryIfNeeded() {
        guard let defaults = Self.sharedDefaults else {
            return
        }

        let initialDictionary = loadBundledInitialSuppressionDictionaryEntries()

        guard !initialDictionary.isEmpty else {
            return
        }

        let initialSignature = dictionarySignature(initialDictionary)
        let appliedSignature = defaults.string(
            forKey: SettingsKeys.kanaKanjiInitialSuppressionDictionaryAppliedSignature
        )

        guard appliedSignature != initialSignature else {
            return
        }

        let currentDictionary = normalizedDictionaryEntries(
            loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiSuppressionVocabulary)
        )

        let merged = mergedDictionary(preferred: currentDictionary, fallback: initialDictionary)

        if merged != currentDictionary {
            saveDictionaryEntries(merged, forKey: SettingsKeys.kanaKanjiSuppressionVocabulary)
        }

        defaults.set(true, forKey: SettingsKeys.kanaKanjiInitialSuppressionDictionaryMigrated)
        defaults.set(
            initialSignature,
            forKey: SettingsKeys.kanaKanjiInitialSuppressionDictionaryAppliedSignature
        )
    }

    private func migrateInitialShortcutVocabularyIfNeeded() {
        guard let defaults = Self.sharedDefaults else {
            return
        }

        let initialCandidates = loadBundledInitialShortcutVocabularyEntries()

        guard !initialCandidates.isEmpty else {
            return
        }

        let currentCandidates = loadShortcutVocabularyCandidates()
        // Keep initial shortcut order authoritative while preserving existing entries.
        let mergedCandidates = uniqueShortcutCandidatesPreservingOrder(initialCandidates + currentCandidates)

        if mergedCandidates != currentCandidates {
            saveShortcutVocabularyCandidates(mergedCandidates)
        }

        defaults.set(true, forKey: SettingsKeys.kanaKanjiInitialShortcutVocabularyMigrated)
    }

    private func migrateLearningVocabularySeparationIfNeeded() {
        guard let defaults = Self.sharedDefaults,
            !defaults.bool(forKey: SettingsKeys.kanaKanjiLearningVocabularyMigrationCompleted) else {
            return
        }

        let currentUserDictionary = normalizedDictionaryEntries(
            loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiAjoutVocabulary)
        )
        let currentLearnedDictionary = normalizedDictionaryEntries(
            loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiLearnedVocabulary)
        )

        var learnedFromScores: [String: [String]] = [:]

        for (key, score) in loadLearningScores() where score > 0 {
            guard let entry = parseLearningKey(key) else {
                continue
            }

            // Legacy mixed data cannot be distinguished reliably. Keep ambiguous items on manual side.
            if currentUserDictionary[entry.reading]?.contains(entry.candidate) == true {
                continue
            }

            var candidates = learnedFromScores[entry.reading] ?? []

            if let existingIndex = candidates.firstIndex(of: entry.candidate) {
                candidates.remove(at: existingIndex)
            }

            candidates.insert(entry.candidate, at: 0)
            learnedFromScores[entry.reading] = Array(candidates.prefix(32))
        }

        let mergedLearnedDictionary = mergedDictionary(
            preferred: currentLearnedDictionary,
            fallback: learnedFromScores
        )

        if mergedLearnedDictionary != currentLearnedDictionary {
            saveDictionaryEntries(mergedLearnedDictionary, forKey: SettingsKeys.kanaKanjiLearnedVocabulary)
        }

        defaults.set(true, forKey: SettingsKeys.kanaKanjiLearningVocabularyMigrationCompleted)
    }

    private func saveDictionaryEntries(_ entriesByReading: [String: [String]], forKey key: String) {
        guard let defaults = Self.sharedDefaults,
                let encoded = try? JSONEncoder().encode(entriesByReading) else {
            return
        }

        defaults.set(encoded, forKey: key)
        SettingsSyncNotification.postSettingsDidChange()
    }

    private func userDictionaryEntriesSnapshot() -> [VocabularyEntry] {
        let dictionary = normalizedDictionaryEntries(
            loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiAjoutVocabulary)
        )

        return dictionary
            .keys
            .sorted()
            .flatMap { reading in
                (dictionary[reading] ?? []).map { candidate in
                    VocabularyEntry(reading: reading, candidate: candidate)
                }
            }
    }

    private func learnedDictionaryEntriesSnapshot() -> [VocabularyEntry] {
        let dictionary = normalizedDictionaryEntries(
            loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiLearnedVocabulary)
        )

        return dictionary
            .keys
            .sorted()
            .flatMap { reading in
                (dictionary[reading] ?? []).map { candidate in
                    VocabularyEntry(reading: reading, candidate: candidate)
                }
            }
    }

    private func suppressionDictionaryEntriesSnapshot() -> [VocabularyEntry] {
        let dictionary = loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiSuppressionVocabulary)

        return dictionary
            .keys
            .sorted()
            .flatMap { reading in
                (dictionary[reading] ?? []).map { candidate in
                    VocabularyEntry(reading: reading, candidate: candidate)
                }
            }
    }

    private func shortcutDictionaryEntriesSnapshot() -> [VocabularyEntry] {
        loadShortcutVocabularyCandidates().map { candidate in
            VocabularyEntry(reading: "☻", candidate: candidate)
        }
    }

    private func loadUserDictionaryEntries() {
        userDictionaryEntries = userDictionaryEntriesSnapshot()
    }

    private func loadLearnedDictionaryEntries() {
        learnedDictionaryEntries = learnedDictionaryEntriesSnapshot()
    }

    private func saveUserDictionary(_ entriesByReading: [String: [String]]) {
        saveDictionaryEntries(entriesByReading, forKey: SettingsKeys.kanaKanjiAjoutVocabulary)
    }

    private func saveLearnedDictionary(_ entriesByReading: [String: [String]]) {
        saveDictionaryEntries(entriesByReading, forKey: SettingsKeys.kanaKanjiLearnedVocabulary)
    }

    private func addUserDictionaryEntry() {
        let reading = normalizedKanaReading(from: userDictionaryReadingInput)
        let candidate = userDictionaryCandidateInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !reading.isEmpty,
                !candidate.isEmpty else {
            return
        }

        var dictionary = loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiAjoutVocabulary)

        var candidates = dictionary[reading] ?? []

        if let existingIndex = candidates.firstIndex(of: candidate) {
            candidates.remove(at: existingIndex)
        }

        candidates.insert(candidate, at: 0)
        dictionary[reading] = Array(candidates.prefix(32))
        saveUserDictionary(dictionary)

        userDictionaryReadingInput = ""
        userDictionaryCandidateInput = ""
        loadUserDictionaryEntries()
    }

    private func updateUserDictionaryEntry(_ originalEntry: VocabularyEntry) {
        let reading = normalizedKanaReading(from: userDictionaryReadingInput)
        let candidate = userDictionaryCandidateInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !reading.isEmpty,
            !candidate.isEmpty else {
            return
        }

        var dictionary = loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiAjoutVocabulary)

        var originalCandidates = dictionary[originalEntry.reading] ?? []
        originalCandidates.removeAll { $0 == originalEntry.candidate }

        if originalCandidates.isEmpty {
            dictionary.removeValue(forKey: originalEntry.reading)
        } else {
            dictionary[originalEntry.reading] = originalCandidates
        }

        var targetCandidates = dictionary[reading] ?? []

        if let existingIndex = targetCandidates.firstIndex(of: candidate) {
            targetCandidates.remove(at: existingIndex)
        }

        targetCandidates.insert(candidate, at: 0)
        dictionary[reading] = Array(targetCandidates.prefix(32))

        saveUserDictionary(dictionary)
        userDictionaryReadingInput = ""
        userDictionaryCandidateInput = ""
        loadUserDictionaryEntries()
    }

    private func removeUserDictionaryEntry(_ entry: VocabularyEntry) {
        var dictionary = loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiAjoutVocabulary)

        var candidates = dictionary[entry.reading] ?? []
        candidates.removeAll { $0 == entry.candidate }

        if candidates.isEmpty {
            dictionary.removeValue(forKey: entry.reading)
        } else {
            dictionary[entry.reading] = candidates
        }

        saveUserDictionary(dictionary)
        loadUserDictionaryEntries()
    }

    private func removeAllUserDictionaryEntries() {
        saveUserDictionary([:])
        loadUserDictionaryEntries()
    }

    private func removeLearnedDictionaryEntry(_ entry: VocabularyEntry) {
        var dictionary = loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiLearnedVocabulary)
        var candidates = dictionary[entry.reading] ?? []
        candidates.removeAll { $0 == entry.candidate }

        if candidates.isEmpty {
            dictionary.removeValue(forKey: entry.reading)
        } else {
            dictionary[entry.reading] = candidates
        }

        saveLearnedDictionary(dictionary)
        loadLearnedDictionaryEntries()
    }

    private func removeAllLearnedDictionaryEntries() {
        saveLearnedDictionary([:])
        loadLearnedDictionaryEntries()
    }

    private func reimportInitialUserDictionaryEntries() {
        guard let defaults = Self.sharedDefaults else {
            return
        }

        defaults.removeObject(forKey: SettingsKeys.kanaKanjiInitialUserDictionaryMigrated)
        defaults.removeObject(forKey: SettingsKeys.kanaKanjiInitialUserDictionaryAppliedSignature)
        migrateInitialUserDictionaryIfNeeded()
        loadUserDictionaryEntries()
        SettingsSyncNotification.postSettingsDidChange()
    }

    private func resetKanaKanjiLearning() {
        Self.sharedDefaults?.removeObject(forKey: SettingsKeys.kanaKanjiLearningScores)
        Self.sharedDefaults?.removeObject(forKey: SettingsKeys.kanaKanjiLearnedVocabulary)
        loadLearnedDictionaryEntries()
        SettingsSyncNotification.postSettingsDidChange()
    }

    private func loadSuppressionDictionaryEntries() {
        suppressionDictionaryEntries = suppressionDictionaryEntriesSnapshot()
    }

    private func saveSuppressionDictionary(_ entriesByReading: [String: [String]]) {
        saveDictionaryEntries(entriesByReading, forKey: SettingsKeys.kanaKanjiSuppressionVocabulary)
    }

    private func addSuppressionDictionaryEntry() {
        let reading = normalizedKanaReading(from: suppressionDictionaryReadingInput)
        let candidate = suppressionDictionaryCandidateInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !reading.isEmpty,
                !candidate.isEmpty else {
            return
        }

        var dictionary = loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiSuppressionVocabulary)
        var candidates = dictionary[reading] ?? []

        if let existingIndex = candidates.firstIndex(of: candidate) {
            candidates.remove(at: existingIndex)
        }

        candidates.insert(candidate, at: 0)
        dictionary[reading] = Array(candidates.prefix(128))
        saveSuppressionDictionary(dictionary)

        suppressionDictionaryReadingInput = ""
        suppressionDictionaryCandidateInput = ""
        loadSuppressionDictionaryEntries()
    }

    private func updateSuppressionDictionaryEntry(_ originalEntry: VocabularyEntry) {
        let reading = normalizedKanaReading(from: suppressionDictionaryReadingInput)
        let candidate = suppressionDictionaryCandidateInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !reading.isEmpty,
            !candidate.isEmpty else {
            return
        }

        var dictionary = loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiSuppressionVocabulary)

        var originalCandidates = dictionary[originalEntry.reading] ?? []
        originalCandidates.removeAll { $0 == originalEntry.candidate }

        if originalCandidates.isEmpty {
            dictionary.removeValue(forKey: originalEntry.reading)
        } else {
            dictionary[originalEntry.reading] = originalCandidates
        }

        var targetCandidates = dictionary[reading] ?? []

        if let existingIndex = targetCandidates.firstIndex(of: candidate) {
            targetCandidates.remove(at: existingIndex)
        }

        targetCandidates.insert(candidate, at: 0)
        dictionary[reading] = Array(targetCandidates.prefix(128))

        saveSuppressionDictionary(dictionary)
        suppressionDictionaryReadingInput = ""
        suppressionDictionaryCandidateInput = ""
        loadSuppressionDictionaryEntries()
    }

    private func removeSuppressionDictionaryEntry(_ entry: VocabularyEntry) {
        var dictionary = loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiSuppressionVocabulary)
        var candidates = dictionary[entry.reading] ?? []
        candidates.removeAll { $0 == entry.candidate }

        if candidates.isEmpty {
            dictionary.removeValue(forKey: entry.reading)
        } else {
            dictionary[entry.reading] = candidates
        }

        saveSuppressionDictionary(dictionary)
        loadSuppressionDictionaryEntries()
    }

    private func loadShortcutDictionaryEntries() {
        shortcutDictionaryEntries = shortcutDictionaryEntriesSnapshot()
    }

    private func addShortcutDictionaryEntry() {
        let candidate = shortcutDictionaryCandidateInput

        guard !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        var candidates = loadShortcutVocabularyCandidates()

        if let existingIndex = candidates.firstIndex(of: candidate) {
            candidates.remove(at: existingIndex)
        }

        candidates.insert(candidate, at: 0)
        saveShortcutVocabularyCandidates(Array(candidates.prefix(128)))

        shortcutDictionaryCandidateInput = ""
        loadShortcutDictionaryEntries()
    }

    private func updateShortcutDictionaryEntry(_ originalEntry: VocabularyEntry) {
        let candidate = shortcutDictionaryCandidateInput

        guard !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        var candidates = loadShortcutVocabularyCandidates()
        candidates.removeAll { $0 == originalEntry.candidate }

        if let existingIndex = candidates.firstIndex(of: candidate) {
            candidates.remove(at: existingIndex)
        }

        candidates.insert(candidate, at: 0)
        saveShortcutVocabularyCandidates(Array(candidates.prefix(128)))

        shortcutDictionaryCandidateInput = ""
        loadShortcutDictionaryEntries()
    }

    private func removeShortcutDictionaryEntry(_ entry: VocabularyEntry) {
        var candidates = loadShortcutVocabularyCandidates()
        candidates.removeAll { $0 == entry.candidate }
        saveShortcutVocabularyCandidates(candidates)
        loadShortcutDictionaryEntries()
    }

    private func handleContainerAppAppear() {
        if didRunFirstAppearanceBootstrap {
            guard !isBootstrappingInitialData else {
                return
            }

            isBootstrappingInitialData = true
            scheduleContainerBootstrapFailSafe()

            Task { @MainActor in
                let refreshStartedAt = CFAbsoluteTimeGetCurrent()
                requestContactsAccessIfNeededInBackground()
                clearKeyboardDiagnosticsIfInstallChanged()
                loadKeyboardDiagnosticsState()
                appendContainerDiagnosticsLog("コンテナ再表示 refresh開始")
                startInitialSnapshotLoadInBackground(logEventPrefix: "コンテナ再表示") {
                    finishBootstrappingIfNeeded()
                }
                let shouldAutoLoadSystemVocabulary = shouldAutoLoadSystemVocabularyOnAppear()

                if didLoadFirstVocabularyEntries {
                    requestFirstSystemVocabularyEntriesLoadIfNeeded(force: true)
                } else if shouldAutoLoadSystemVocabulary {
                    requestFirstSystemVocabularyEntriesLoadIfNeeded()
                }

                if didLoadSecondVocabularyEntries {
                    requestSecondSystemVocabularyEntriesLoadIfNeeded(force: true)
                } else if shouldAutoLoadSystemVocabulary {
                    requestSecondSystemVocabularyEntriesLoadIfNeeded()
                }

                appendContainerDiagnosticsLog(
                    "コンテナ再表示 refresh完了 elapsedMs=\(containerDiagnosticsElapsedMilliseconds(since: refreshStartedAt)) user=\(userDictionaryEntries.count) learned=\(learnedDictionaryEntries.count) suppression=\(suppressionDictionaryEntries.count) shortcut=\(shortcutDictionaryEntries.count)"
                )
                loadKeyboardDiagnosticsState()
            }
            return
        }

        didRunFirstAppearanceBootstrap = true
        containerDiagnosticsSessionID = UUID().uuidString
        isBootstrappingInitialData = true
        scheduleContainerBootstrapFailSafe()

        Task { @MainActor in
            let bootstrapStartedAt = CFAbsoluteTimeGetCurrent()
            // Let SwiftUI present the first frame before expensive file I/O and JSON decode.
            await Task.yield()

            requestContactsAccessIfNeededInBackground()

            clearLegacyKeyboardDebugLogKeysIfNeeded()
            migrateLegacyFlickGuideSettingIfNeeded()
            clearKeyboardDiagnosticsIfInstallChanged()
            loadKeyboardDiagnosticsState()
            appendContainerDiagnosticsLog("コンテナ初回表示 bootstrap開始")
            startInitialSnapshotLoadInBackground(logEventPrefix: "コンテナ初回表示") {
                startInitialMigrationsAndRefreshSnapshotInBackground {
                    appendContainerDiagnosticsLog(
                        "コンテナ初回表示 bootstrap完了 elapsedMs=\(containerDiagnosticsElapsedMilliseconds(since: bootstrapStartedAt))"
                    )
                    loadKeyboardDiagnosticsState()
                    finishBootstrappingIfNeeded()
                }
            }

            if shouldAutoLoadSystemVocabularyOnAppear() {
                requestFirstSystemVocabularyEntriesLoadIfNeeded()
                requestSecondSystemVocabularyEntriesLoadIfNeeded()
            }
        }
    }

    private var loadingToastMessage: String {
        if isLoadingFirstVocabularyEntries && isLoadingSecondVocabularyEntries {
            return "Loading... 第1/第2語彙を読み込み中"
        }

        if isLoadingFirstVocabularyEntries {
            return "Loading... 第1語彙を読み込み中"
        }

        if isLoadingSecondVocabularyEntries {
            return "Loading... 第2語彙を読み込み中"
        }

        if isBootstrappingInitialData {
            return "Loading... 起動準備中"
        }

        return "Loading... 語彙データを読み込み中"
    }

    private var loadingToastLabel: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)

            Text(loadingToastMessage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }

    @ViewBuilder
    private var initialLoadingToast: some View {
        if isContainerBusy,
            didCompleteInitialDataSnapshot {
            VStack {
                loadingToastLabel
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, 24)
            .allowsHitTesting(false)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.screenBackground
                    .ignoresSafeArea()

                if !didCompleteInitialDataSnapshot {
                    VStack {
                        loadingToastLabel
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(.horizontal, 24)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Spacer(minLength: 0)

                                VStack(spacing: 4) {
                                    Image("AppLogoDisplay")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 92, height: 92)
                                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                        .shadow(color: Color.black.opacity(0.12), radius: 5, y: 2)

                                    Text(Self.editionNumberText)
                                        .font(.system(size: 4, weight: .regular, design: .monospaced))
                                        .foregroundStyle(.secondary.opacity(0.9))
                                        .lineLimit(1)
                                        .scaleEffect(isEditionNumberPressed ? 6.0 : 1.0, anchor: .top)
                                        .animation(.easeOut(duration: 0.08), value: isEditionNumberPressed)
                                        .contentShape(Rectangle())
                                        .simultaneousGesture(
                                            DragGesture(minimumDistance: 0)
                                                .updating($isEditionNumberPressed) { _, state, _ in
                                                    state = true
                                                }
                                        )
                                        .zIndex(1)
                                        .accessibilityHidden(true)
                                }

                                Spacer(minLength: 0)
                            }

                        Text("このアプリはカスタムキーボード拡張の設定・管理を行うコンテナー・アプリ (Containing App) です。キーボード本体は拡張ターゲット側で実装されています。")
                            .font(.body)
                            .foregroundStyle(.secondary)

                        DirectionSettingsSection(selection: directionSelection)

                        KanaModifierSettingsSection(selection: kanaModifierPlacementSelection)

                        KanaLayoutSettingsSection(selection: kanaLayoutSelection)

                        LandscapeCandidateSideSettingsSection(
                            selection: landscapeCandidateSideSelection,
                            latinSuggestionMode: landscapeLatinSuggestionModeSelection
                        )

                        LandscapeNumberPaneSideSettingsSection(selection: landscapeNumberPaneSideSelection)

                        LatinLayoutSettingsSection(selection: latinLayoutSelection)

                        NumberLayoutSettingsSection(selection: numberLayoutSelection)

                        BasicSymbolOrderSettingsSection(selection: basicSymbolOrderSelection)

                        AccentColorSettingsSection(selection: accentPaletteSelection)

                        ThemeColorSettingsSection(selection: keyboardBackgroundThemeSelection)

                        FlickGuideDisplaySettingsSection(
                            kanaSelection: kanaFlickGuideDisplayModeSelection,
                            latinSelection: latinFlickGuideDisplayModeSelection,
                            numberSelection: numberFlickGuideDisplayModeSelection,
                            modifierSelection: modifierFlickGuideDisplayModeSelection,
                            isLatinGuideAvailable: isLatinFlickLayoutSelected
                        )

                        KeyRepeatSettingsSection(
                            keyRepeatInitialDelay: keyRepeatInitialDelayBinding,
                            keyRepeatInterval: keyRepeatIntervalBinding
                        )

                        KanaModeSwitcherAssignmentSection(
                            tapSelection: kanaModeSwitcherTapActionSelection,
                            rightFlickSelection: kanaModeSwitcherRightFlickActionSelection,
                            upFlickSelection: kanaModeSwitcherUpFlickActionSelection
                        )

                        KanaPostModifierEmptyTapAssignmentSection(
                            actionSelection: kanaPostModifierEmptyTapActionSelection,
                            kaomojiCategoryID: kanaPostModifierEmptyTapKaomojiCategoryBinding,
                            emojiCategoryID: kanaPostModifierEmptyTapEmojiCategoryBinding,
                            symbolCategoryID: kanaPostModifierEmptyTapSymbolCategoryBinding
                        )

                        KanaPostModifierFlickDakutenSettingsSection(
                            isEnabled: $kanaPostModifierFlickDakutenEnabled
                        )

                        DelimiterAutoCommitCandidateSettingsSection(
                            selection: delimiterAutoCommitCandidateSelection
                        )

                        VStack(alignment: .leading, spacing: 10) {
                            Text("かな漢字候補モード")
                                .font(.headline)

                            Picker("かな漢字候補モード", selection: kanaKanjiCandidateSourceModeSelection) {
                                ForEach(KanaKanjiCandidateSourceModeOption.allCases) { option in
                                    Text(option.title).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)

                            Text("システム辞書候補の採用基準を切り替えます。surface(既定) / normalisé / les deux を選べます。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .settingsCardStyle()

                        HistoricalKanaCandidatesSettingsSection(
                            isEnabled: $historicalKanaCandidatesEnabled
                        )

                        EmojiKaomojiCandidateSettingsSection(
                            enablesEmojiCandidates: $emojiCandidateDisplayEnabled,
                            enablesKaomojiCandidates: $kaomojiCandidateDisplayEnabled
                        )

                        ContactCandidateDisplaySettingsSection(
                            selection: contactCandidateDisplayModeSelection
                        )

                        UserDictionaryCandidateDisplaySettingsSection(
                            selection: userDictionaryCandidateDisplayModeSelection
                        )

                        UserDictionarySettingsSection(
                            entries: $userDictionaryEntries,
                            readingInput: $userDictionaryReadingInput,
                            candidateInput: $userDictionaryCandidateInput,
                            isRegistrationVisible: $isUserDictionaryRegistrationVisible,
                            scrollIndexTitle: $userDictionaryScrollIndexTitle,
                            isScrollIndexVisible: $isUserDictionaryScrollIndexVisible,
                            canAddEntry: canAddUserDictionaryEntry,
                            listHeight: userVocabularyListHeight(for: userDictionaryEntries.count),
                            onAddEntry: addUserDictionaryEntry,
                            onUpdateEntry: updateUserDictionaryEntry,
                            onDeleteEntry: removeUserDictionaryEntry,
                            onDeleteAll: removeAllUserDictionaryEntries,
                            onReimportInitialEntries: reimportInitialUserDictionaryEntries
                        )

                        LearnedDictionarySettingsSection(
                            entries: $learnedDictionaryEntries,
                            scrollIndexTitle: $learnedDictionaryScrollIndexTitle,
                            isScrollIndexVisible: $isLearnedDictionaryScrollIndexVisible,
                            listHeight: userVocabularyListHeight(for: learnedDictionaryEntries.count),
                            onDeleteEntry: removeLearnedDictionaryEntry,
                            onDeleteAll: removeAllLearnedDictionaryEntries,
                            onResetLearning: resetKanaKanjiLearning
                        )

                        SuppressionDictionarySettingsSection(
                            entries: $suppressionDictionaryEntries,
                            readingInput: $suppressionDictionaryReadingInput,
                            candidateInput: $suppressionDictionaryCandidateInput,
                            isRegistrationVisible: $isSuppressionDictionaryRegistrationVisible,
                            scrollIndexTitle: $suppressionDictionaryScrollIndexTitle,
                            isScrollIndexVisible: $isSuppressionDictionaryScrollIndexVisible,
                            canAddEntry: canAddSuppressionDictionaryEntry,
                            listHeight: userVocabularyListHeight(for: suppressionDictionaryEntries.count),
                            onAddEntry: addSuppressionDictionaryEntry,
                            onUpdateEntry: updateSuppressionDictionaryEntry,
                            onDeleteEntry: removeSuppressionDictionaryEntry
                        )

                        ShortcutDictionarySettingsSection(
                            entries: $shortcutDictionaryEntries,
                            candidateInput: $shortcutDictionaryCandidateInput,
                            isRegistrationVisible: $isShortcutDictionaryRegistrationVisible,
                            canAddEntry: canAddShortcutDictionaryEntry,
                            listHeight: userVocabularyListHeight(for: shortcutDictionaryEntries.count),
                            onAddEntry: addShortcutDictionaryEntry,
                            onUpdateEntry: updateShortcutDictionaryEntry,
                            onDeleteEntry: removeShortcutDictionaryEntry
                        )

                        ReadOnlyDictionarySettingsSection(
                            title: "第1語彙",
                            entries: firstVocabularyEntries,
                            scrollIndexTitle: $firstVocabularyScrollIndexTitle,
                            isScrollIndexVisible: $isFirstVocabularyScrollIndexVisible,
                            listHeight: userVocabularyListHeight(for: firstVocabularyEntries.count),
                            emptyMessage: isLoadingFirstVocabularyEntries
                                ? "第1語彙を読み込み中..."
                                : "第1語彙はまだ読み込まれていません。",
                            description: "Dictionnaire système premier (読み取り専用) 追加や削除はできません。",
                            actionButtonTitle: didLoadFirstVocabularyEntries
                                ? "第1語彙を再読み込み"
                                : "第1語彙を読み込む",
                            actionButtonLoadingTitle: "第1語彙を読み込み中...",
                            isActionLoading: isLoadingFirstVocabularyEntries,
                            isActionDisabled: isLoadingSecondVocabularyEntries,
                            onAction: {
                                requestFirstSystemVocabularyEntriesLoadIfNeeded(force: true)
                            }
                        )

                        ReadOnlyDictionarySettingsSection(
                            title: "第2語彙",
                            entries: secondVocabularyEntries,
                            scrollIndexTitle: $secondVocabularyScrollIndexTitle,
                            isScrollIndexVisible: $isSecondVocabularyScrollIndexVisible,
                            listHeight: userVocabularyListHeight(for: secondVocabularyEntries.count),
                            emptyMessage: isLoadingSecondVocabularyEntries
                                ? "第2語彙を読み込み中..."
                                : "第2語彙はまだ読み込まれていません。",
                            description: "Dictionnaire système secondaire (読み取り専用) 追加や削除はできません。",
                            actionButtonTitle: didLoadSecondVocabularyEntries
                                ? "第2語彙を再読み込み"
                                : "第2語彙を読み込む",
                            actionButtonLoadingTitle: "第2語彙を読み込み中...",
                            isActionLoading: isLoadingSecondVocabularyEntries,
                            isActionDisabled: isLoadingFirstVocabularyEntries,
                            onAction: {
                                requestSecondSystemVocabularyEntriesLoadIfNeeded(force: true)
                            }
                        )

                        SetupStepsSection(steps: setupSteps)

                        ThirdPartyLicensesSection()

                        KeyboardDiagnosticsSection(
                            isSessionActive: keyboardDiagnosticsSessionActive,
                            failSafeProfile: keyboardDiagnosticsFailSafeProfile,
                            lastHeartbeatText: keyboardDiagnosticsLastHeartbeatText(),
                            lastEvent: keyboardDiagnosticsLastEvent,
                            lastSessionID: keyboardDiagnosticsLastSessionID,
                            installMarker: keyboardDiagnosticsInstallMarker,
                            logLines: keyboardDiagnosticsLogLines,
                            onReload: {
                                clearKeyboardDiagnosticsIfInstallChanged()
                                loadKeyboardDiagnosticsState()
                            },
                            onCopy: copyKeyboardDiagnosticsToPasteboard,
                            onClear: clearKeyboardDiagnosticsState
                        )

                        Text("フリック入力に加えて、かな漢字変換・追加単語・抑制単語に対応しています。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                        .padding(20)
                    }
                    .disabled(isBootstrappingInitialData)
                }

                initialLoadingToast
            }
            .onAppear {
                handleContainerAppAppear()
            }
            .onChange(of: settingsSyncSignature) { _ in
                SettingsSyncNotification.postSettingsDidChange()
            }
            .onChange(of: contactCandidateDisplayModeRawValue) { newValue in
                let mode = ContactCandidateDisplayModeOption(rawValue: newValue) ?? .namesOnly

                guard mode != .off else {
                    syncContactCandidatesCacheFromContainerApp()
                    return
                }

                requestContactsAccessIfNeededInBackground()
                syncContactCandidatesCacheFromContainerApp()
            }
            .onChange(of: scenePhase) { newPhase in
                guard newPhase == .active else {
                    return
                }

                if shouldUseContactCandidates {
                    syncContactCandidatesCacheFromContainerApp()
                    SettingsSyncNotification.postSettingsDidChange()
                }
            }
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("écritu")
                        .font(.custom("SnellRoundhand-Bold", size: 34))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
            }
#endif
        }
    }
}

#Preview {
    ContentView()
}
