import SwiftUI
import Darwin
import Contacts
#if os(iOS)
import UIKit
#endif

struct ContentView: View {
    static let sharedDefaults = UserDefaults(suiteName: SettingsKeys.appGroupID)
    private static let editionUpdatedAtRaw: String = "20260712233000"
    static let diagnosticsTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let contactFetchKeys: [CNKeyDescriptor] = [
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

    private static let editionNumberText: String = {
        let info = Bundle.main.infoDictionary ?? [:]
        let editionNumber = (info["CFBundleVersion"] as? String) ?? "?"

        if let dateText = editionDateText(from: editionUpdatedAtRaw) {
            return "édition n°\(editionNumber) (\(dateText))"
        }

        return "édition n°\(editionNumber)"
    }()

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
        SettingsKeys.idleCommitEnabled,
        store: Self.sharedDefaults
    )
    private var idleCommitEnabled: Bool = IdleCommitSettings.enabledDefault

    @AppStorage(
        SettingsKeys.idleCommitInterval,
        store: Self.sharedDefaults
    )
    private var idleCommitInterval: Double = IdleCommitSettings.intervalDefault

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
    private var delimiterAutoCommitCandidateRawValue: String = DelimiterAutoCommitCandidateOption.one.rawValue

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
    var contactCandidateDisplayModeRawValue: String = ContactCandidateDisplayModeOption.namesOnly.rawValue

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

    @State var userDictionaryEntries: [VocabularyEntry] = []
    @State var userDictionaryReadingInput = ""
    @State var userDictionaryCandidateInput = ""
    @State private var isUserDictionaryRegistrationVisible = false
    @State private var userDictionaryScrollIndexTitle = ""
    @State private var isUserDictionaryScrollIndexVisible = false
    @State var learnedDictionaryEntries: [VocabularyEntry] = []
    @State private var learnedDictionaryScrollIndexTitle = ""
    @State private var isLearnedDictionaryScrollIndexVisible = false
    @State var suppressionDictionaryEntries: [VocabularyEntry] = []
    @State var suppressionDictionaryReadingInput = ""
    @State var suppressionDictionaryCandidateInput = ""
    @State private var isSuppressionDictionaryRegistrationVisible = false
    @State private var suppressionDictionaryScrollIndexTitle = ""
    @State private var isSuppressionDictionaryScrollIndexVisible = false
    @State var shortcutDictionaryEntries: [VocabularyEntry] = []
    @State var shortcutDictionaryCandidateInput = ""
    @State private var isShortcutDictionaryRegistrationVisible = false
    @State var firstVocabularyEntries: [VocabularyEntry] = []
    @State private var firstVocabularyScrollIndexTitle = ""
    @State private var isFirstVocabularyScrollIndexVisible = false
    @State var secondVocabularyEntries: [VocabularyEntry] = []
    @State private var secondVocabularyScrollIndexTitle = ""
    @State private var isSecondVocabularyScrollIndexVisible = false
    @State var didLoadFirstVocabularyEntries = false
    @State var isLoadingFirstVocabularyEntries = false
    @State var didLoadSecondVocabularyEntries = false
    @State var isLoadingSecondVocabularyEntries = false
    @State var keyboardDiagnosticsLogLines: [String] = []
    @State var keyboardDiagnosticsInstallMarker = ""
    @State var keyboardDiagnosticsSessionActive = false
    @State var keyboardDiagnosticsLastHeartbeatDate: Date?
    @State var keyboardDiagnosticsLastEvent = ""
    @State var keyboardDiagnosticsLastSessionID = ""
    @State var keyboardDiagnosticsFailSafeProfile = "normal"
    @State var containerDiagnosticsSessionID = UUID().uuidString
    @State var didRunFirstAppearanceBootstrap = false
    @State var didCompleteInitialDataSnapshot = false
    @State var isBootstrappingInitialData = true
    @State var containerBootstrapFailSafeWorkItem: DispatchWorkItem?
    @GestureState private var isEditionNumberPressed = false
    @Environment(\.scenePhase) private var scenePhase

    private let setupSteps: [String] = [
        "設定 > 一般 > キーボード > キーボード > 新しいキーボードを追加",
        "作成したキーボードを有効化",
        "入力画面で地球儀キーから切り替え"
    ]

    var isContainerBusy: Bool {
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

    var shouldUseContactCandidates: Bool {
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

    private var idleCommitIntervalBinding: Binding<Double> {
        Binding(
            get: { idleCommitInterval },
            set: {
                idleCommitInterval = abs($0 - IdleCommitSettings.intervalDefault) <= IdleCommitSettings.snapThreshold
                    ? IdleCommitSettings.intervalDefault
                    : $0
            }
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
        rawValueSelection(from: delimiterAutoCommitCandidateRawValue, default: .one) {
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

    struct InitialDataSnapshot {
        let userDictionaryEntries: [VocabularyEntry]
        let learnedDictionaryEntries: [VocabularyEntry]
        let suppressionDictionaryEntries: [VocabularyEntry]
        let shortcutDictionaryEntries: [VocabularyEntry]
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

                        IdleCommitSettingsSection(
                            idleCommitEnabled: $idleCommitEnabled,
                            idleCommitInterval: idleCommitIntervalBinding
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
            // 初期ロード中はナビバーを隠し、ローディング表示を
            // セーフエリア中央(RootLoadingView/LaunchScreenと同じ基準)に置く。
            // ナビバーがあると "écritu" タイトル分だけ下にずれてしまうため。
            .toolbar(didCompleteInitialDataSnapshot ? .visible : .hidden, for: .navigationBar)
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
        // ナビバーの内側ではなくデバイスのセーフエリア中央に乗せ、
        // 起動時の他のローディング表示と縦位置を揃える。
        .overlay {
            initialLoadingToast
        }
    }
}

#Preview {
    ContentView()
}
