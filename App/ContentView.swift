import SwiftUI
import Darwin
import Contacts
#if os(iOS)
import UIKit
#endif

struct ContentView: View {
    static let sharedDefaults = UserDefaults(suiteName: SettingsKeys.appGroupID)
    private static let editionUpdatedAtRaw: String = "20260824161713"
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
        SettingsKeys.formattedNumberKeypadLayout,
        store: Self.sharedDefaults
    )
    private var formattedNumberKeypadLayoutRawValue: String = FormattedNumberKeypadOption.calculette.rawValue

    @AppStorage(
        SettingsKeys.dateFormatStyle,
        store: Self.sharedDefaults
    )
    private var dateFormatStyleRawValue: String = DateFormatStyleOption.japanese.rawValue

    @AppStorage(
        SettingsKeys.numberThousandsSeparator,
        store: Self.sharedDefaults
    )
    private var numberThousandsSeparatorRawValue: String = ThousandsSeparatorOption.space.rawValue

    @AppStorage(
        SettingsKeys.numberDecimalSeparator,
        store: Self.sharedDefaults
    )
    private var numberDecimalSeparatorRawValue: String = DecimalSeparatorOption.dot.rawValue

    @AppStorage(
        SettingsKeys.numberGroupFourDigits,
        store: Self.sharedDefaults
    )
    private var numberGroupFourDigits: Bool = false

    @AppStorage(
        SettingsKeys.numberUnitProductSeparator,
        store: Self.sharedDefaults
    )
    private var numberUnitProductSeparatorRawValue: String = UnitProductSeparatorOption.middleDot.rawValue

    @AppStorage(
        SettingsKeys.calendarWeekStart,
        store: Self.sharedDefaults
    )
    private var calendarWeekStartRawValue: String = CalendarWeekStartOption.monday.rawValue

    @AppStorage(
        SettingsKeys.calendarWeekdayLanguage,
        store: Self.sharedDefaults
    )
    private var calendarWeekdayLanguageRawValue: String = CalendarWeekdayLanguageOption.french.rawValue

    @AppStorage(
        SettingsKeys.calendarSundayColor,
        store: Self.sharedDefaults
    )
    private var calendarSundayColorRawValue: String = CalendarDayColorOption.dic156.rawValue

    @AppStorage(
        SettingsKeys.calendarFridayColor,
        store: Self.sharedDefaults
    )
    private var calendarFridayColorRawValue: String = CalendarDayColorOption.off.rawValue

    @AppStorage(
        SettingsKeys.calendarSaturdayColor,
        store: Self.sharedDefaults
    )
    private var calendarSaturdayColorRawValue: String = CalendarDayColorOption.off.rawValue

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
        SettingsKeys.radicalStrokeCountStyle,
        store: Self.sharedDefaults
    )
    private var radicalStrokeCountStyleRawValue: String = ""

    @AppStorage(
        SettingsKeys.ordinalMeKanjiPreferred,
        store: Self.sharedDefaults
    )
    private var ordinalMeKanjiPreferred = true

    @AppStorage(
        SettingsKeys.adjectiveMeKanjiCandidatesEnabled,
        store: Self.sharedDefaults
    )
    private var adjectiveMeKanjiCandidatesEnabled = false

    @AppStorage(
        SettingsKeys.suspendMemorySlimmingEnabled,
        store: Self.sharedDefaults
    )
    private var suspendMemorySlimmingEnabled = true

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

    @AppStorage(
        SettingsKeys.iterationMarkCandidatesEnabled,
        store: Self.sharedDefaults
    )
    private var iterationMarkCandidatesEnabled = false

    @AppStorage(
        SettingsKeys.latinLexiconEnglishEnabled,
        store: Self.sharedDefaults
    )
    private var latinLexiconEnglishEnabled = false

    @AppStorage(
        SettingsKeys.latinLexiconFrenchEnabled,
        store: Self.sharedDefaults
    )
    private var latinLexiconFrenchEnabled = false

    @AppStorage(
        SettingsKeys.latinLexiconGermanEnabled,
        store: Self.sharedDefaults
    )
    private var latinLexiconGermanEnabled = false

    @AppStorage(
        SettingsKeys.latinLexiconItalianEnabled,
        store: Self.sharedDefaults
    )
    private var latinLexiconItalianEnabled = false

    @AppStorage(
        SettingsKeys.katakanaEmphasisCandidateMode,
        store: Self.sharedDefaults
    )
    private var katakanaEmphasisCandidateModeRawValue: String = ScriptVariantModeOption.suppress.rawValue

    @AppStorage(
        SettingsKeys.mazegakiCandidateMode,
        store: Self.sharedDefaults
    )
    private var mazegakiCandidateModeRawValue: String = ScriptVariantModeOption.suppress.rawValue

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
    @State var keyboardDiagnosticsCriticalLogLines: [String] = []
    @State var keyboardDiagnosticsInstallMarker = ""
    @State var keyboardDiagnosticsSessionActive = false
    @State var keyboardDiagnosticsLastHeartbeatDate: Date?
    @State var keyboardDiagnosticsLastEvent = ""
    @State var keyboardDiagnosticsLastSessionID = ""
    @State var keyboardDiagnosticsFailSafeProfile = "normal"
    @State var keyboardDiagnosticsLaunchCount = 0
    @State var keyboardDiagnosticsAttachFailureCount = 0
    @State var keyboardDiagnosticsAttachLateRecoveryCount = 0
    @State var keyboardConversionLastTrace = ""
    @State var containerDiagnosticsSessionID = UUID().uuidString
    @State var didRunFirstAppearanceBootstrap = false
    @State var didCompleteInitialDataSnapshot = false
    @State var isBootstrappingInitialData = true
    @State var containerBootstrapFailSafeWorkItem: DispatchWorkItem?
    @GestureState private var isEditionNumberPressed = false
    @State private var showsSettingsYAMLCopiedToast = false
    // 初回フレーム軽量化: 設定カード群は最初の描画後に構築する(起動直後の白背景 Loading 対策)。
    @State private var didRenderInitialFrame = false
    // 設定カード群の構築計測(2587)。didRenderInitialFrame を立てた時刻と、カード群の
    // 最後の要素が画面に載った時刻の差が構築コストそのもの。
    @State var settingsCardsBuildStartedAt: CFAbsoluteTime = 0
    @State var didLogSettingsCardsRendered = false
    // 1起動ぶんの計測断片。bootstrap完了で1行にまとめて履歴キーへ流す。
    @State var bootstrapTimingParts: [String] = []
    // 各事象が起動から何ms後に起きたかを出すための基準時刻。
    @State var containerBootstrapStartedAt: CFAbsoluteTime = 0
    // 起動開始時点のページイン/フォールト数(完了時に差分を取る)。
    @State var containerBootstrapPageEventsAtStart: (faults: Int, pageins: Int)?
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
            formattedNumberKeypadLayoutRawValue,
            dateFormatStyleRawValue,
            numberThousandsSeparatorRawValue,
            numberDecimalSeparatorRawValue,
            String(numberGroupFourDigits),
            numberUnitProductSeparatorRawValue,
            calendarWeekStartRawValue,
            calendarWeekdayLanguageRawValue,
            calendarSundayColorRawValue,
            calendarFridayColorRawValue,
            calendarSaturdayColorRawValue,
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
            radicalStrokeCountStyleRawValue,
            String(ordinalMeKanjiPreferred),
            String(adjectiveMeKanjiCandidatesEnabled),
            String(suspendMemorySlimmingEnabled),
            String(kaomojiCandidateDisplayEnabled),
            String(historicalKanaCandidatesEnabled),
            String(iterationMarkCandidatesEnabled),
            katakanaEmphasisCandidateModeRawValue,
            mazegakiCandidateModeRawValue,
            String(latinLexiconEnglishEnabled),
            String(latinLexiconFrenchEnabled),
            String(latinLexiconGermanEnabled),
            String(latinLexiconItalianEnabled)
        ]
            .joined(separator: "|")
    }

    // 設定内容の YAML エクスポート(ロゴ長押しでクリップボードへ)。項目は設定画面の
    // グループ・表示順に合わせ、コメントにアプリ内のタイトルを付ける。
    private func settingsYAMLExportText() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var lines: [String] = [
            "# écritu 設定 (YAML エクスポート)",
            "# \(Self.editionNumberText)",
            "# \(formatter.string(from: Date()))"
        ]

        func group(_ title: String) {
            lines.append("")
            lines.append("# ──── \(title) ────")
        }
        func str(_ key: String, _ raw: String, _ comment: String) {
            lines.append("\(key): \"\(raw)\" # \(comment)")
        }
        func bool(_ key: String, _ value: Bool, _ comment: String) {
            lines.append("\(key): \(value) # \(comment)")
        }
        func num(_ key: String, _ value: Double, _ comment: String) {
            lines.append("\(key): \(String(format: "%g", value)) # \(comment)")
        }

        group("キー配列")
        str(SettingsKeys.kanaLayoutMode, kanaLayoutModeRawValue, "かな配列")
        str(SettingsKeys.latinLayoutMode, latinLayoutModeRawValue, "ラテン文字配列")
        str(SettingsKeys.numberLayoutMode, numberLayoutModeRawValue, "数字配列: 数字入力")
        str(SettingsKeys.formattedNumberKeypadLayout, formattedNumberKeypadLayoutRawValue, "数字配列: 書式化数値入力")
        str(SettingsKeys.basicSymbolOrder, basicSymbolOrderRawValue, "基本記号の並び順")
        str(SettingsKeys.kanaModifierPlacement, kanaModifierPlacementRawValue, "かな修飾")

        group("入力")
        str(SettingsKeys.directionProfile, directionProfileRawValue, "フリック方向")
        num(SettingsKeys.keyRepeatInitialDelay, keyRepeatInitialDelay, "削除キーリピート: リピート開始までの時間(秒)")
        num(SettingsKeys.keyRepeatInterval, keyRepeatInterval, "削除キーリピート: リピート速度(間隔)(秒)")
        bool(SettingsKeys.idleCommitEnabled, idleCommitEnabled, "自動確定(アイドル): 入力が止まったら未確定を自動確定")
        num(SettingsKeys.idleCommitInterval, idleCommitInterval, "自動確定(アイドル): 確定までの待ち時間(秒)")
        str(SettingsKeys.kanaModeSwitcherTapAction, kanaModeSwitcherTapActionRawValue, "かな左下キー割り当て: タップ")
        str(SettingsKeys.kanaModeSwitcherRightFlickAction, kanaModeSwitcherRightFlickActionRawValue, "かな左下キー割り当て: 右フリック")
        str(SettingsKeys.kanaModeSwitcherUpFlickAction, kanaModeSwitcherUpFlickActionRawValue, "かな左下キー割り当て: 上フリック")
        str(SettingsKeys.kanaPostModifierEmptyTapAction, kanaPostModifierEmptyTapActionRawValue, "タップ (後置修飾、未確定なし)")
        str(SettingsKeys.kanaPostModifierEmptyTapKaomojiCategory, kanaPostModifierEmptyTapKaomojiCategoryID, "タップ (後置修飾、未確定なし): 切替時に開くカテゴリー(顔文字)")
        str(SettingsKeys.kanaPostModifierEmptyTapEmojiCategory, kanaPostModifierEmptyTapEmojiCategoryID, "タップ (後置修飾、未確定なし): 切替時に開くカテゴリー(絵文字)")
        str(SettingsKeys.kanaPostModifierEmptyTapSymbolCategory, kanaPostModifierEmptyTapSymbolCategoryID, "タップ (後置修飾、未確定なし): 切替時に開くカテゴリー(記号)")
        bool(SettingsKeys.kanaPostModifierFlickDakutenEnabled, kanaPostModifierFlickDakutenEnabled, "後置修飾キーのフリックで濁点・半濁点")
        str(SettingsKeys.numberThousandsSeparator, numberThousandsSeparatorRawValue, "format numérique: Séparateur de milliers")
        bool(SettingsKeys.numberGroupFourDigits, numberGroupFourDigits, "format numérique: que quatre")
        str(SettingsKeys.numberDecimalSeparator, numberDecimalSeparatorRawValue, "format numérique: Séparateur décimal")
        str(SettingsKeys.numberUnitProductSeparator, numberUnitProductSeparatorRawValue, "format numérique: 単位の積の記号")
        str(SettingsKeys.calendarWeekStart, calendarWeekStartRawValue, "カレンダー: 週開始")
        str(SettingsKeys.calendarWeekdayLanguage, calendarWeekdayLanguageRawValue, "カレンダー: 曜日表記")
        str(SettingsKeys.calendarSundayColor, calendarSundayColorRawValue, "カレンダー: 日曜列の色")
        str(SettingsKeys.calendarSaturdayColor, calendarSaturdayColorRawValue, "カレンダー: 土曜列の色")
        str(SettingsKeys.calendarFridayColor, calendarFridayColorRawValue, "カレンダー: 金曜列の色")
        str(SettingsKeys.dateFormatStyle, dateFormatStyleRawValue, "カレンダー: 日付書式")
        bool(SettingsKeys.latinLexiconFrenchEnabled, latinLexiconFrenchEnabled, "欧文サジェスチョンの言語: français (フランス語)")
        bool(SettingsKeys.latinLexiconItalianEnabled, latinLexiconItalianEnabled, "欧文サジェスチョンの言語: italiano (イタリア語)")
        bool(SettingsKeys.latinLexiconGermanEnabled, latinLexiconGermanEnabled, "欧文サジェスチョンの言語: Deutsch (ドイツ語)")
        bool(SettingsKeys.latinLexiconEnglishEnabled, latinLexiconEnglishEnabled, "欧文サジェスチョンの言語: anglais (英語)")

        group("キー表示")
        str(SettingsKeys.kanaFlickGuideDisplayMode, kanaFlickGuideDisplayModeRawValue, "ガイド文字表示: かな入力")
        str(SettingsKeys.latinFlickGuideDisplayMode, latinFlickGuideDisplayModeRawValue, "ガイド文字表示: ラテン文字入力")
        str(SettingsKeys.numberFlickGuideDisplayMode, numberFlickGuideDisplayModeRawValue, "ガイド文字表示: 数字入力")
        str(SettingsKeys.modifierFlickGuideDisplayMode, modifierFlickGuideDisplayModeRawValue, "ガイド文字表示: 濁点・半濁点・小文字キー")

        group("表示")
        str(SettingsKeys.landscapeLatinSuggestionMode, landscapeLatinSuggestionModeRawValue, "ラテン文字候補ペイン (horizontal): 横向きラテン文字入力で候補ペインを使う")
        str(SettingsKeys.landscapeCandidateSide, landscapeCandidateSideRawValue, "ラテン文字候補ペイン (horizontal): 並び順")
        str(SettingsKeys.landscapeNumberPaneSide, landscapeNumberPaneSideRawValue, "数字ペイン配列 (horizontal)")
        str(SettingsKeys.accentPalette, accentPaletteRawValue, "アクセントカラー")
        str(SettingsKeys.keyboardBackgroundTheme, keyboardBackgroundThemeRawValue, "テーマカラー")

        group("変換")
        str(SettingsKeys.delimiterAutoCommitCandidate, delimiterAutoCommitCandidateRawValue, "句読点入力時の自動確定候補")
        str(SettingsKeys.kanaKanjiCandidateSourceMode, kanaKanjiCandidateSourceModeRawValue, "かな漢字候補モード")
        bool(SettingsKeys.historicalKanaCandidatesEnabled, historicalKanaCandidatesEnabled, "旧仮名遣い候補")
        bool(SettingsKeys.iterationMarkCandidatesEnabled, iterationMarkCandidatesEnabled, "仮名の踊り字候補")
        str(SettingsKeys.katakanaEmphasisCandidateMode, katakanaEmphasisCandidateModeRawValue, "カタカナ強調表記の候補")
        str(SettingsKeys.mazegakiCandidateMode, mazegakiCandidateModeRawValue, "交ぜ書きの候補")
        bool(SettingsKeys.emojiCandidateDisplayEnabled, emojiCandidateDisplayEnabled, "emojis & les émoticônes: emoji 😀")
        str(SettingsKeys.radicalStrokeCountStyle, radicalStrokeCountStyleRawValue, "部首の画数の数え方")
        bool(SettingsKeys.ordinalMeKanjiPreferred, ordinalMeKanjiPreferred, "première…: 順序の『目』を漢字で先に")
        bool(SettingsKeys.adjectiveMeKanjiCandidatesEnabled, adjectiveMeKanjiCandidatesEnabled, "un peu …: 形容詞語幹の『目』候補も出す")
        bool(SettingsKeys.suspendMemorySlimmingEnabled, suspendMemorySlimmingEnabled, "キーボードが閉じたときにメモリを整理")
        bool(SettingsKeys.kaomojiCandidateDisplayEnabled, kaomojiCandidateDisplayEnabled, "emojis & les émoticônes: émoticône (^_^)")
        str(SettingsKeys.contactCandidateDisplayMode, contactCandidateDisplayModeRawValue, "iOSの連絡先の姓、名、会社名")
        str(SettingsKeys.userDictionaryCandidateDisplayMode, userDictionaryCandidateDisplayModeRawValue, "iOSのユーザ辞書の単語")

        return lines.joined(separator: "\n") + "\n"
    }

    private func copySettingsYAMLToPasteboard() {
#if os(iOS)
        UIPasteboard.general.string = settingsYAMLExportText()
#endif
        withAnimation(.easeOut(duration: 0.15)) {
            showsSettingsYAMLCopiedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeIn(duration: 0.3)) {
                showsSettingsYAMLCopiedToast = false
            }
        }
    }

    @ViewBuilder
    private var settingsYAMLCopiedToast: some View {
        if showsSettingsYAMLCopiedToast {
            VStack {
                Text("設定を YAML 形式でコピーしました")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
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

    private var formattedNumberKeypadSelection: Binding<FormattedNumberKeypadOption> {
        rawValueSelection(from: formattedNumberKeypadLayoutRawValue, default: .calculette) {
            formattedNumberKeypadLayoutRawValue = $0
        }
    }

    private var dateFormatStyleSelection: Binding<DateFormatStyleOption> {
        rawValueSelection(from: dateFormatStyleRawValue, default: .japanese) {
            dateFormatStyleRawValue = $0
        }
    }

    // 桁区切りと小数点は同じ記号(, または .)にできない。衝突する変更をしたら、もう一方を
    // 自動で反対の記号に切り替える(espace は記号ではないので衝突しない)。
    private var numberThousandsSeparatorSelection: Binding<ThousandsSeparatorOption> {
        Binding(
            get: { ThousandsSeparatorOption(rawValue: numberThousandsSeparatorRawValue) ?? .space },
            set: { newValue in
                if newValue == .comma, numberDecimalSeparatorRawValue == DecimalSeparatorOption.comma.rawValue {
                    numberDecimalSeparatorRawValue = DecimalSeparatorOption.dot.rawValue
                } else if newValue == .dot, numberDecimalSeparatorRawValue == DecimalSeparatorOption.dot.rawValue {
                    numberDecimalSeparatorRawValue = DecimalSeparatorOption.comma.rawValue
                }
                numberThousandsSeparatorRawValue = newValue.rawValue
            }
        )
    }

    private var numberUnitProductSeparatorSelection: Binding<UnitProductSeparatorOption> {
        rawValueSelection(from: numberUnitProductSeparatorRawValue, default: .middleDot) {
            numberUnitProductSeparatorRawValue = $0
        }
    }

    private var numberDecimalSeparatorSelection: Binding<DecimalSeparatorOption> {
        Binding(
            get: { DecimalSeparatorOption(rawValue: numberDecimalSeparatorRawValue) ?? .dot },
            set: { newValue in
                if newValue == .comma, numberThousandsSeparatorRawValue == ThousandsSeparatorOption.comma.rawValue {
                    numberThousandsSeparatorRawValue = ThousandsSeparatorOption.dot.rawValue
                } else if newValue == .dot, numberThousandsSeparatorRawValue == ThousandsSeparatorOption.dot.rawValue {
                    numberThousandsSeparatorRawValue = ThousandsSeparatorOption.comma.rawValue
                }
                numberDecimalSeparatorRawValue = newValue.rawValue
            }
        )
    }

    private var calendarWeekStartSelection: Binding<CalendarWeekStartOption> {
        rawValueSelection(from: calendarWeekStartRawValue, default: .monday) {
            calendarWeekStartRawValue = $0
        }
    }

    private var calendarSundayColorSelection: Binding<CalendarDayColorOption> {
        rawValueSelection(from: calendarSundayColorRawValue, default: .off) {
            calendarSundayColorRawValue = $0
        }
    }

    private var calendarFridayColorSelection: Binding<CalendarDayColorOption> {
        rawValueSelection(from: calendarFridayColorRawValue, default: .off) {
            calendarFridayColorRawValue = $0
        }
    }

    private var calendarSaturdayColorSelection: Binding<CalendarDayColorOption> {
        rawValueSelection(from: calendarSaturdayColorRawValue, default: .off) {
            calendarSaturdayColorRawValue = $0
        }
    }

    private var calendarWeekdayLanguageSelection: Binding<CalendarWeekdayLanguageOption> {
        rawValueSelection(from: calendarWeekdayLanguageRawValue, default: .japanese) {
            calendarWeekdayLanguageRawValue = $0
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

    struct InitialDataSnapshot: Equatable {
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
        if isContainerBusy || !didCompleteInitialDataSnapshot {
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

                // UI は初期化(snapshot/migration)完了を待たず即表示する。初期化中は下の
                // initialLoadingToast(小さいトースト)を重ね、.disabled で操作だけ止める
                // (白背景の全画面 Loading で待たせない。ユーザ方針)。
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
                                        // ロゴ長押し=設定内容を YAML でクリップボードへコピー。
                                        .onLongPressGesture(minimumDuration: 0.5) {
                                            copySettingsYAMLToPasteboard()
                                        }
                                        .accessibilityLabel("アプリロゴ")
                                        .accessibilityHint("長押しで設定内容を YAML 形式でコピーします")

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

                        // 設定カード群は初回フレーム描画後に遅延構築する(下の .task が1フレーム後に
                        // フラグを立てる)。起動直後はロゴ+ヘッダーだけを即描画し、白背景の
                        // Loading 表示が長引かないようにする。
                        if didRenderInitialFrame {

                        // ──── キー配列 ────

                        KanaLayoutSettingsSection(selection: kanaLayoutSelection)

                        LatinLayoutSettingsSection(selection: latinLayoutSelection)

                        NumberLayoutSettingsSection(
                            selection: numberLayoutSelection,
                            formattedNumberKeypad: formattedNumberKeypadSelection
                        )

                        BasicSymbolOrderSettingsSection(selection: basicSymbolOrderSelection)

                        KanaModifierSettingsSection(selection: kanaModifierPlacementSelection)

                        // ──── 入力 ────

                        DirectionSettingsSection(selection: directionSelection)

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

                        FormatNumeriqueSettingsSection(
                            thousandsSeparator: numberThousandsSeparatorSelection,
                            groupFourDigits: $numberGroupFourDigits,
                            decimalSeparator: numberDecimalSeparatorSelection,
                            unitProductSeparator: numberUnitProductSeparatorSelection
                        )

                        CalendarSettingsGroupSection(
                            weekStart: calendarWeekStartSelection,
                            weekdayLanguage: calendarWeekdayLanguageSelection,
                            sundayColor: calendarSundayColorSelection,
                            fridayColor: calendarFridayColorSelection,
                            saturdayColor: calendarSaturdayColorSelection,
                            dateFormatStyle: dateFormatStyleSelection
                        )

                        LatinLexiconSettingsSection(
                            enablesEnglish: $latinLexiconEnglishEnabled,
                            enablesFrench: $latinLexiconFrenchEnabled,
                            enablesGerman: $latinLexiconGermanEnabled,
                            enablesItalian: $latinLexiconItalianEnabled
                        )

                        // ──── キー表示 ────

                        FlickGuideDisplaySettingsSection(
                            kanaSelection: kanaFlickGuideDisplayModeSelection,
                            latinSelection: latinFlickGuideDisplayModeSelection,
                            numberSelection: numberFlickGuideDisplayModeSelection,
                            modifierSelection: modifierFlickGuideDisplayModeSelection,
                            isLatinGuideAvailable: isLatinFlickLayoutSelected
                        )

                        // ──── 表示 ────

                        LandscapeCandidateSideSettingsSection(
                            selection: landscapeCandidateSideSelection,
                            latinSuggestionMode: landscapeLatinSuggestionModeSelection
                        )

                        LandscapeNumberPaneSideSettingsSection(selection: landscapeNumberPaneSideSelection)

                        AccentColorSettingsSection(selection: accentPaletteSelection)

                        ThemeColorSettingsSection(selection: keyboardBackgroundThemeSelection)

                        // ──── 変換 ────

                        DelimiterAutoCommitCandidateSettingsSection(
                            selection: delimiterAutoCommitCandidateSelection
                        )

                        KanaKanjiCandidateSourceModeSettingsSection(
                            selection: kanaKanjiCandidateSourceModeSelection
                        )

                        HistoricalKanaCandidatesSettingsSection(
                            isEnabled: $historicalKanaCandidatesEnabled
                        )

                        IterationMarkCandidatesSettingsSection(
                            isEnabled: $iterationMarkCandidatesEnabled
                        )

                        ScriptVariantModeSettingsSection(
                            title: "カタカナ強調表記の候補",
                            selectionRawValue: $katakanaEmphasisCandidateModeRawValue,
                            footnote: "辞書が収穫した『ウマイ/コレ/ばかリ』のような読みのカタカナ化表記の扱いです。抑制=候補に出さない(初期設定)、リスト後方=候補の末尾に回す、同列に使う=通常の順位。パンやアンケートのような外来語のカタカナは対象外です。"
                        )

                        ScriptVariantModeSettingsSection(
                            title: "交ぜ書きの候補",
                            selectionRawValue: $mazegakiCandidateModeRawValue,
                            footnote: "『まん延(蔓延)』『作ひん(作品)』のような、漢字の一部をかなに開いた交ぜ書き表記の扱いです。抑制=候補に出さない(初期設定)、リスト後方=候補の末尾に回す、同列に使う=通常の順位。『子ども』など定着した表記は対象外です。"
                        )

                        RadicalStrokeCountSettingsSection(
                            rawValue: $radicalStrokeCountStyleRawValue
                        )

                        MeSuffixCandidateSettingsSection(
                            ordinalKanjiPreferred: $ordinalMeKanjiPreferred,
                            adjectiveKanjiEnabled: $adjectiveMeKanjiCandidatesEnabled
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

                        // ──── 語彙管理 ────

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

                        // ──── アプリ情報 ────

                        SetupStepsSection(steps: setupSteps)

                        ThirdPartyLicensesSection()

                        // ──── 診断 ────

                        ConversionCacheSettingsSection(
                            suspendMemorySlimmingEnabled: $suspendMemorySlimmingEnabled
                        )

                        // キーボード診断ログは開発ビルド専用(キーボード側の記録も
                        // DEBUG 専用のため、リリースでは常に空。審査ガイドライン2.2対策)
                        #if DEBUG
                        KeyboardDiagnosticsSection(
                            isSessionActive: keyboardDiagnosticsSessionActive,
                            failSafeProfile: keyboardDiagnosticsFailSafeProfile,
                            lastHeartbeatText: keyboardDiagnosticsLastHeartbeatText(),
                            lastEvent: keyboardDiagnosticsLastEvent,
                            lastSessionID: keyboardDiagnosticsLastSessionID,
                            installMarker: keyboardDiagnosticsInstallMarker,
                            logLines: keyboardDiagnosticsLogLines,
                            launchCount: keyboardDiagnosticsLaunchCount,
                            attachFailureCount: keyboardDiagnosticsAttachFailureCount,
                            attachLateRecoveryCount: keyboardDiagnosticsAttachLateRecoveryCount,
                            onReload: {
                                clearKeyboardDiagnosticsIfInstallChanged()
                                loadKeyboardDiagnosticsState()
                            },
                            onCopy: { copyKeyboardDiagnosticsToPasteboard() },
                            onCopyDetail: { copyKeyboardDiagnosticsToPasteboard(detail: true) },
                            onClear: clearKeyboardDiagnosticsState
                        )
                        #endif

                        Text("フリック入力に加えて、かな漢字変換・追加単語・抑制単語に対応しています。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            // Loading が長い件の切り分け(2587)。段別計測で「実作業は約100ms、
                            // 残りは main actor の待ち」と分かったが、塞いでいるのが本当に
                            // 設定カード群の構築なのかは未確認だった。カード群の最後の要素が
                            // 画面に載った時刻を出せば、構築に何ms掛かったかが直接分かる。
                            .onAppear { logSettingsCardsRenderedIfNeeded() }

                        } // didRenderInitialFrame
                        }
                        .padding(20)
                    }
                    .disabled(isBootstrappingInitialData)
            }
            .task {
                guard !didRenderInitialFrame else {
                    return
                }
                // 1フレーム分だけ譲ってヘッダーを先に描画してから、カード群を構築する。
                await Task.yield()
                settingsCardsBuildStartedAt = CFAbsoluteTimeGetCurrent()
                didRenderInitialFrame = true
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

                // バックグラウンド滞在中に拡張が書いた診断(起動/未到達カウント・
                // ログ行)を表示へ反映する。onAppearは復帰では再発火しないため、
                // ここで再読込しないと診断セクションが古いスナップショットのまま残る。
                clearKeyboardDiagnosticsIfInstallChanged()
                recordKeyboardExtensionRegistrationState()
                loadKeyboardDiagnosticsState()

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
        .overlay {
            settingsYAMLCopiedToast
        }
    }
}

#Preview {
    ContentView()
}
