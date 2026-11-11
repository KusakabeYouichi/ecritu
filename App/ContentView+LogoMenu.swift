import SwiftUI
import Security
#if os(iOS)
import UIKit
#endif

// ロゴのメニュー(2760)。ロゴに触れた途端にロゴ直下にメニューを出し、触れている間だけ表示する
// (3648 で長押し 0.5 秒の待ちをなくした)。指を項目まで滑らせて離すとその項目を実行、
// 動かさずに離せば何もしない(離した時点でメニューは消える)。
// 従来の「ロゴ長押し=設定を YAML でコピー」はメニューの1項目に移した。

enum LogoMenuAction: String, CaseIterable, Identifiable {
    case strategicDefaults
    // メニューの並び順(現代的を保守的の上に。ユーザ指定 3407)
    case contemporaryDefaults
    case conservativeDefaults
    case copyYAML
    case stashSettings
    case restoreStashedSettings
    case openManual
    case openPrivacyPolicy
    case about

    var id: String { rawValue }

    var startsNewGroup: Bool {
        self == .copyYAML || self == .openManual
    }

    var title: String {
        switch self {
        case .strategicDefaults: return "戦略的初期設定"
        case .conservativeDefaults: return "保守的初期設定"
        case .contemporaryDefaults: return "現代的初期設定"
        // 「設定をクリップボードにコピー」は幅 300 で 2 行に折れていた(3591)
        case .copyYAML: return "設定をコピー"
        case .stashSettings: return "現在の設定を退避"
        case .restoreStashedSettings: return "退避した設定を復元"
        case .openManual: return "操作マニュアル"
        case .openPrivacyPolicy: return "プライバシーポリシー"
        case .about: return "écritu について"
        }
    }

    var subtitle: String {
        switch self {
        case .strategicDefaults: return "組み込みの標準値に戻す"
        case .conservativeDefaults: return "3×3+わ・téléphone など従来型の配列にする"
        case .contemporaryDefaults: return "保守的+かなで書く言葉をすべて抑制"
        case .copyYAML: return "YAML 形式でクリップボードへ"
        case .stashSettings: return "再インストール後も残る場所に保存"
        case .restoreStashedSettings: return "退避していた設定に戻す"
        case .openManual: return "Safari で開く(全10章)"
        case .openPrivacyPolicy: return "Safari で開く"
        case .about: return "version・édition と著作権表示"
        }
    }

    // 初期設定の 3 項目は専用アイコン(SVGPathShape.swift。3647)。他は SF Symbols
    var presetIcon: LogoMenuPresetIcon? {
        switch self {
        case .strategicDefaults: return .chessKnight
        case .conservativeDefaults: return .shield
        case .contemporaryDefaults: return .sparkles
        default: return nil
        }
    }

    var systemImage: String {
        switch self {
        case .strategicDefaults: return "arrow.counterclockwise"
        case .conservativeDefaults: return "person.crop.circle"
        case .contemporaryDefaults: return "textformat.alt"
        case .copyYAML: return "doc.on.clipboard"
        case .stashSettings: return "tray.and.arrow.down"
        case .restoreStashedSettings: return "tray.and.arrow.up"
        case .openManual: return "book"
        case .openPrivacyPolicy: return "hand.raised"
        case .about: return "info.circle"
        }
    }

    // 設定を書き換える項目は確認ダイアログを挟む(ユーザ指定)
    var needsConfirmation: Bool {
        switch self {
        case .strategicDefaults, .conservativeDefaults, .contemporaryDefaults, .restoreStashedSettings: return true
        case .copyYAML, .stashSettings, .openManual, .openPrivacyPolicy, .about: return false
        }
    }
}

// 情報表示用のアラート(確認ではなく OK だけ)
struct LogoMenuInfo: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

// 触れている間の進行状態。GestureState なので指を離すと自動で .inactive に戻り、メニューも消える
enum LogoMenuGestureState: Equatable {
    case inactive
    case touching(CGPoint)

    var isActive: Bool { self != .inactive }

    var location: CGPoint? {
        if case .touching(let point) = self { return point }
        return nil
    }
}

// ロゴとメニュー項目の枠を同じ座標空間で集める(指の位置との当たり判定用)
// ロゴの枠の入れ物。書いても再描画を起こさない(メニューを出すときに読むだけ。3756)
final class LogoMenuLogoFrameBox {
    var frame: CGRect = .zero
}

struct LogoMenuFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// 退避先の Keychain(kSecClassGenericPassword)。アプリ削除後も同じ Team ID のアプリから読めるため、
// 入れ直しても設定が残る。iCloud(NSUbiquitousKeyValueStore)は有料の開発者アカウントが要るので使わない。
// Apple は「削除後も残る」ことを保証はしていないが、iOS では長年そう振る舞っている(2760)
enum SettingsStashStore {
    // Keychain 項目のラベル(kSecAttrService)。端末内の不透明なラベルで、誰が読めるかは entitlements の
    // アクセスグループで決まる。バンドル ID から組み立てる(3319。ユーザ指定 jp.or.pleiades.merope.ecritu.settings-stash)
    // ので、次にバンドル ID が変わっても自動で追従し、一括置換に巻き込まれない。テスターが Signing.local で別の
    // バンドル ID を使っていても、その人の端末のその人のアプリにしか関係しない
    private static let serviceSuffix = ".settings-stash"
    private static var service: String {
        (Bundle.main.bundleIdentifier ?? "jp.or.pleiades.merope.ecritu") + serviceSuffix
    }
    private static let account = "settings"

    private static func baseQuery(service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static func save(_ data: Data) -> Bool {
        let base = baseQuery(service: service)
        var query = base
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        // iCloud キーチェーンには同期しない(既定 false だが意図を明示。2785)
        query[kSecAttrSynchronizable as String] = false
        query[kSecValueData as String] = data
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update: [String: Any] = [kSecValueData as String: data]
            return SecItemUpdate(base as CFDictionary, update as CFDictionary) == errSecSuccess
        }
        return status == errSecSuccess
    }

    static func load() -> Data? {
        var query = baseQuery(service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return result as? Data
    }
}

// 退避データ。設定値は String/Bool/Double のいずれか(UserDefaults の設定キーはこの3型だけ)
struct SettingsStash: Codable {
    enum Value: Codable, Equatable {
        case string(String)
        case bool(Bool)
        case number(Double)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let bool = try? container.decode(Bool.self) {
                self = .bool(bool)
            } else if let number = try? container.decode(Double.self) {
                self = .number(number)
            } else {
                self = .string(try container.decode(String.self))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let value): try container.encode(value)
            case .bool(let value): try container.encode(value)
            case .number(let value): try container.encode(value)
            }
        }

        var anyValue: Any {
            switch self {
            case .string(let value): return value
            case .bool(let value): return value
            case .number(let value): return value
            }
        }

        // UserDefaults の値から。Bool は NSNumber と区別が付かないので CFBoolean で見る
        init?(defaultsValue: Any) {
            if let string = defaultsValue as? String {
                self = .string(string)
            } else if let number = defaultsValue as? NSNumber {
                if CFGetTypeID(number) == CFBooleanGetTypeID() {
                    self = .bool(number.boolValue)
                } else {
                    self = .number(number.doubleValue)
                }
            } else {
                return nil
            }
        }
    }

    let editionNumber: String
    let savedAt: Date
    let values: [String: Value]
    // 退避したときの基準の初期設定(SettingsBasePreset の rawValue。3432)。これより前に退避したものには無い
    var basePreset: String?
    var basePresetContactsStartedOff: Bool?
}

extension ContentView {
    static let aboutCopyrightText = "Copyright © 2026 Kusakabe Youichi"
    // App Store/TestFlight に表に出る版(CFBundleShortVersionString=MARKETING_VERSION)。edition(ビルド番号)と別に示す(2899、ユーザ指定)
    static let marketingVersionText: String = {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
        return "version \(version)"
    }()

    // ユーザが変えられる設定のキー(設定画面の全項目)。settingsYAMLExportText と同じ集合を保つこと。
    // 語彙・学習・診断ログなどのデータ系キーは含めない(初期設定に戻しても消えない)
    static let userSettingsKeys: [String] = [
        SettingsKeys.kanaLayoutMode, SettingsKeys.latinLayoutMode, SettingsKeys.numberLayoutMode,
        SettingsKeys.formattedNumberKeypadLayout, SettingsKeys.basicSymbolOrder, SettingsKeys.kanaModifierPlacement,
        SettingsKeys.directionProfile, SettingsKeys.keyRepeatInitialDelay, SettingsKeys.keyRepeatInterval,
        SettingsKeys.idleCommitEnabled, SettingsKeys.idleCommitInterval,
        SettingsKeys.composingTextStyle,
        SettingsKeys.leftModeSwitchNumberKeyRightFlickAction, SettingsKeys.leftModeSwitchLatinKeyRightFlickAction,
        SettingsKeys.leftModeSwitchKanaKeyRightFlickAction,
        SettingsKeys.kanaModeSwitcherTapAction, SettingsKeys.kanaModeSwitcherRightFlickAction,
        SettingsKeys.compactKeyboardSwitchKeyRightFlickAction, SettingsKeys.compactKeyboardSwitchKeyUpFlickAction,
        SettingsKeys.kanaPostModifierEmptyTapAction, SettingsKeys.kanaPostModifierEmptyTapKaomojiCategory,
        SettingsKeys.kanaPostModifierEmptyTapEmojiCategory, SettingsKeys.kanaPostModifierEmptyTapSymbolCategory,
        SettingsKeys.kanaPostModifierFlickDakutenEnabled, SettingsKeys.kanaYaBracketStyle,
        SettingsKeys.numberThousandsSeparator, SettingsKeys.numberGroupFourDigits, SettingsKeys.numberDecimalSeparator,
        SettingsKeys.numberUnitProductSeparator, SettingsKeys.numberLitreSymbol, SettingsKeys.degreeSymbol,
        SettingsKeys.calendarWeekStart, SettingsKeys.calendarWeekdayLanguage, SettingsKeys.calendarSundayColor,
        SettingsKeys.calendarSaturdayColor, SettingsKeys.calendarFridayColor, SettingsKeys.dateFormatStyle,
        SettingsKeys.latinLexiconFrenchEnabled, SettingsKeys.latinLexiconItalianEnabled,
        SettingsKeys.latinLexiconGermanEnabled, SettingsKeys.latinLexiconEnglishEnabled,
        SettingsKeys.kanaFlickGuideDisplayMode, SettingsKeys.latinFlickGuideDisplayMode,
        SettingsKeys.numberFlickGuideDisplayMode, SettingsKeys.modifierFlickGuideDisplayMode,
        SettingsKeys.landscapeLatinSuggestionMode, SettingsKeys.landscapeCandidateSide, SettingsKeys.landscapeNumberPaneSide,
        SettingsKeys.accentPalette, SettingsKeys.keyboardBackgroundTheme, SettingsKeys.candidateFontStyle,
        SettingsKeys.delimiterAutoCommitCandidate, SettingsKeys.kanaKanjiCandidateSourceMode,
        SettingsKeys.historicalKanaCandidatesEnabled, SettingsKeys.iterationMarkCandidatesEnabled,
        SettingsKeys.katakanaEmphasisCandidateMode, SettingsKeys.mazegakiCandidateMode,
        SettingsKeys.scriptVariantSuppressKyujitai, SettingsKeys.scriptVariantSuppressItaiji,
        SettingsKeys.scriptVariantSuppressRyakuji, SettingsKeys.scriptVariantSuppressConfusable, SettingsKeys.scriptVariantSuppressLookalike,
        SettingsKeys.scriptVariantSuppressPersonNameVariant,
        SettingsKeys.kanaGakiSuppressAdverb, SettingsKeys.kanaGakiSuppressConjunction, SettingsKeys.kanaGakiSuppressAuxiliary,
        SettingsKeys.kanaGakiSuppressFormalNoun, SettingsKeys.kanaGakiSuppressDemonstrative, SettingsKeys.kanaGakiSuppressAdverbKanaFirst,
        SettingsKeys.emojiCandidateDisplayEnabled, SettingsKeys.radicalStrokeCountStyle,
        SettingsKeys.ordinalMeKanjiPreferred, SettingsKeys.adjectiveMeKanjiCandidatesEnabled, SettingsKeys.kaCounterVariantPreference,
        SettingsKeys.numeralStylePreference,
        SettingsKeys.okuriganaVariantPreference,
        SettingsKeys.kakikaePreference,
        SettingsKeys.kakikaeEverydayException,
        SettingsKeys.lateStandardizedRewritePreference,
        SettingsKeys.suspendMemorySlimmingEnabled, SettingsKeys.kaomojiCandidateDisplayEnabled,
        SettingsKeys.contactCandidateDisplayMode, SettingsKeys.userDictionaryCandidateDisplayMode,
        SettingsKeys.shortcutVocabularyRecentsFirst
    ]

    // 保守的初期設定 = 従来型の配列の組み合わせ(2026-09-02 の YAML エクスポートから転記。ユーザ指定 2760。3647 で「作者の使用設定」という呼称をやめた: 作者の実運用は現代的に近い)。
    // 書いていないキーは標準の初期設定のまま(適用前に全キーを消してから上書きする)
    // 組み込みの初期値(ContentView の @AppStorage の初期値と同じ式。3242)。初期設定の適用は「全キーを消す」方式なので、
    // 「今の設定と同じか」の判定は保存値でなく実効値(未設定=組み込み初期値)で比べる。以前は未設定と保存値を別物と
    // 見ていたため、保守的初期設定と組み込み初期値が同じ項目(顔文字=ショートカット 等)で判定がずれた
    static let builtInDefaultValues: [String: Any] = [
        SettingsKeys.kanaLayoutMode: KanaLayoutOption.fiveByTwo.rawValue,
        SettingsKeys.latinLayoutMode: LatinLayoutOption.azerty.rawValue,
        SettingsKeys.numberLayoutMode: NumberLayoutOption.calculette.rawValue,
        SettingsKeys.formattedNumberKeypadLayout: FormattedNumberKeypadOption.calculette.rawValue,
        SettingsKeys.basicSymbolOrder: BasicSymbolOrderOption.ascii.rawValue,
        SettingsKeys.kanaModifierPlacement: KanaModifierPlacementOption.prefix.rawValue,
        SettingsKeys.directionProfile: DirectionOption.ecritu.rawValue,
        SettingsKeys.keyRepeatInitialDelay: RepeatSettings.initialDelayDefault,
        SettingsKeys.keyRepeatInterval: RepeatSettings.intervalDefault,
        SettingsKeys.idleCommitEnabled: IdleCommitSettings.enabledDefault,
        SettingsKeys.idleCommitInterval: IdleCommitSettings.intervalDefault,
        SettingsKeys.composingTextStyle: ComposingTextStyleOption.ecritu.rawValue,
        // E.5(3618): 上 3 段の右フリックと最下段の右フリックは 3 つの初期設定で共通。最下段のタップと 🌐 の上は初期設定ごと
        SettingsKeys.leftModeSwitchNumberKeyRightFlickAction: KanaModeSwitcherActionOption.formattedNumber.rawValue,
        SettingsKeys.leftModeSwitchLatinKeyRightFlickAction: KanaModeSwitcherActionOption.emoji.rawValue,
        SettingsKeys.leftModeSwitchKanaKeyRightFlickAction: KanaModeSwitcherActionOption.kanjiRadical.rawValue,
        SettingsKeys.kanaModeSwitcherTapAction: KanaModeSwitcherActionOption.emoji.rawValue,
        SettingsKeys.kanaModeSwitcherRightFlickAction: KanaModeSwitcherActionOption.kaomoji.rawValue,
        SettingsKeys.compactKeyboardSwitchKeyRightFlickAction: KanaModeSwitcherActionOption.kaomoji.rawValue,
        SettingsKeys.compactKeyboardSwitchKeyUpFlickAction: KanaModeSwitcherActionOption.symbols.rawValue,
        SettingsKeys.kanaPostModifierEmptyTapAction: KanaPostModifierEmptyTapActionOption.default.rawValue,
        SettingsKeys.kanaPostModifierEmptyTapKaomojiCategory: KaomojiCategoryChoice.defaultID,
        SettingsKeys.kanaPostModifierEmptyTapEmojiCategory: EmojiCategoryChoice.defaultID,
        SettingsKeys.kanaPostModifierEmptyTapSymbolCategory: SymbolCategoryChoice.defaultID,
        SettingsKeys.kanaPostModifierFlickDakutenEnabled: true,
        SettingsKeys.kanaYaBracketStyle: KanaYaBracketOption.doubleCorner.rawValue,
        SettingsKeys.numberThousandsSeparator: ThousandsSeparatorOption.space.rawValue,
        SettingsKeys.numberGroupFourDigits: false,
        SettingsKeys.numberDecimalSeparator: DecimalSeparatorOption.dot.rawValue,
        SettingsKeys.numberUnitProductSeparator: UnitProductSeparatorOption.middleDot.rawValue,
        SettingsKeys.numberLitreSymbol: LitreSymbolOption.small.rawValue,
        SettingsKeys.degreeSymbol: DegreeSymbolOption.composed.rawValue,
        SettingsKeys.calendarWeekStart: CalendarWeekStartOption.monday.rawValue,
        SettingsKeys.calendarWeekdayLanguage: CalendarWeekdayLanguageOption.french.rawValue,
        SettingsKeys.calendarSundayColor: CalendarDayColorOption.dic156.rawValue,
        SettingsKeys.calendarSaturdayColor: CalendarDayColorOption.off.rawValue,
        SettingsKeys.calendarFridayColor: CalendarDayColorOption.off.rawValue,
        SettingsKeys.dateFormatStyle: DateFormatStyleOption.japanese.rawValue,
        SettingsKeys.latinLexiconFrenchEnabled: false,
        SettingsKeys.latinLexiconItalianEnabled: false,
        SettingsKeys.latinLexiconGermanEnabled: false,
        SettingsKeys.latinLexiconEnglishEnabled: false,
        SettingsKeys.kanaFlickGuideDisplayMode: FlickGuideDisplayOption.fourDirections.rawValue,
        SettingsKeys.latinFlickGuideDisplayMode: FlickGuideDisplayOption.fourDirections.rawValue,
        SettingsKeys.numberFlickGuideDisplayMode: FlickGuideDisplayOption.fourDirections.rawValue,
        SettingsKeys.modifierFlickGuideDisplayMode: FlickGuideDisplayOption.fourDirections.rawValue,
        SettingsKeys.landscapeLatinSuggestionMode: LandscapeLatinSuggestionModeOption.sidebar.rawValue,
        SettingsKeys.landscapeCandidateSide: LandscapeCandidateSideOption.left.rawValue,
        SettingsKeys.landscapeNumberPaneSide: LandscapeCandidateSideOption.left.rawValue,
        SettingsKeys.accentPalette: AccentColorOption.emeraude.rawValue,
        SettingsKeys.keyboardBackgroundTheme: KeyboardBackgroundThemeOption.bleu.rawValue,
        SettingsKeys.candidateFontStyle: CandidateFontStyleOption.semibold16.rawValue,   // 戦略的=16pt(ユーザ指定 3644)
        SettingsKeys.delimiterAutoCommitCandidate: DelimiterAutoCommitCandidateOption.one.rawValue,
        SettingsKeys.kanaKanjiCandidateSourceMode: KanaKanjiCandidateSourceModeOption.surface.rawValue,
        SettingsKeys.historicalKanaCandidatesEnabled: false,
        SettingsKeys.iterationMarkCandidatesEnabled: false,
        SettingsKeys.katakanaEmphasisCandidateMode: ScriptVariantModeOption.suppress.rawValue,
        SettingsKeys.mazegakiCandidateMode: ScriptVariantModeOption.suppress.rawValue,
        SettingsKeys.scriptVariantSuppressKyujitai: true,
        SettingsKeys.scriptVariantSuppressItaiji: true,
        SettingsKeys.scriptVariantSuppressRyakuji: true,
        SettingsKeys.scriptVariantSuppressConfusable: true,
        SettingsKeys.scriptVariantSuppressLookalike: true,
        SettingsKeys.scriptVariantSuppressPersonNameVariant: false,
        // かなで書く言葉は 5 つとも抑制(ユーザ指定 3404)
        SettingsKeys.kanaGakiSuppressAdverb: true,
        SettingsKeys.kanaGakiSuppressConjunction: true,
        SettingsKeys.kanaGakiSuppressAuxiliary: true,
        SettingsKeys.kanaGakiSuppressFormalNoun: true,
        SettingsKeys.kanaGakiSuppressDemonstrative: true,
        SettingsKeys.kanaGakiSuppressAdverbKanaFirst: false,
        SettingsKeys.emojiCandidateDisplayEnabled: true,
        SettingsKeys.radicalStrokeCountStyle: "",
        SettingsKeys.ordinalMeKanjiPreferred: true,
        SettingsKeys.adjectiveMeKanjiCandidatesEnabled: false,
        SettingsKeys.kaCounterVariantPreference: KaCounterVariantPreference.default.encoded,
        SettingsKeys.numeralStylePreference: NumeralStylePreference.strategicDefault.rawValue,   // 戦略的=アラビア数字だけ(3702)
        SettingsKeys.okuriganaVariantPreference: OkuriganaVariantPreference.default.encoded,
        // 同音の漢字による書きかえは 本来の漢字だけ(ユーザ指定 3422)
        SettingsKeys.kakikaePreference: KakikaePreference.strategicDefault.rawValue,
        SettingsKeys.kakikaeEverydayException: false,   // 戦略的=オフ(設定どおり。ユーザ指定 3644)
        SettingsKeys.lateStandardizedRewritePreference: KakikaePreference.strategicDefault.rawValue,  // X.10 も 本来の漢字だけ(ユーザ指定 3570)
        SettingsKeys.suspendMemorySlimmingEnabled: true,
        SettingsKeys.shortcutVocabularyRecentsFirst: true,
        SettingsKeys.kaomojiCandidateDisplayEnabled: true,
        SettingsKeys.contactCandidateDisplayMode: ContactCandidateDisplayModeOption.off.rawValue,
        SettingsKeys.userDictionaryCandidateDisplayMode: UserDictionaryCandidateDisplayModeOption.on.rawValue,
    ]

    static let conservativePresetValues: [String: Any] = [
        SettingsKeys.kanaLayoutMode: KanaLayoutOption.threeByThreePlusWa.rawValue,
        SettingsKeys.latinLayoutMode: LatinLayoutOption.flick.rawValue,
        SettingsKeys.numberLayoutMode: NumberLayoutOption.telephone.rawValue,
        SettingsKeys.formattedNumberKeypadLayout: FormattedNumberKeypadOption.calculette.rawValue,
        SettingsKeys.basicSymbolOrder: BasicSymbolOrderOption.ansi.rawValue,
        SettingsKeys.kanaModifierPlacement: KanaModifierPlacementOption.postfix.rawValue,
        SettingsKeys.directionProfile: DirectionOption.littlebear.rawValue,
        SettingsKeys.keyRepeatInitialDelay: 0.5,
        SettingsKeys.keyRepeatInterval: 0.1,
        SettingsKeys.idleCommitEnabled: false,
        SettingsKeys.idleCommitInterval: 1.2,
        SettingsKeys.composingTextStyle: ComposingTextStyleOption.ecritu.rawValue,
        SettingsKeys.leftModeSwitchNumberKeyRightFlickAction: KanaModeSwitcherActionOption.formattedNumber.rawValue,
        SettingsKeys.leftModeSwitchLatinKeyRightFlickAction: KanaModeSwitcherActionOption.emoji.rawValue,
        SettingsKeys.leftModeSwitchKanaKeyRightFlickAction: KanaModeSwitcherActionOption.kanjiRadical.rawValue,
        SettingsKeys.kanaModeSwitcherTapAction: KanaModeSwitcherActionOption.symbols.rawValue,
        SettingsKeys.kanaModeSwitcherRightFlickAction: KanaModeSwitcherActionOption.kaomoji.rawValue,
        SettingsKeys.compactKeyboardSwitchKeyRightFlickAction: KanaModeSwitcherActionOption.kaomoji.rawValue,
        SettingsKeys.compactKeyboardSwitchKeyUpFlickAction: KanaModeSwitcherActionOption.emoji.rawValue,
        SettingsKeys.kanaPostModifierEmptyTapAction: KanaPostModifierEmptyTapActionOption.kaomoji.rawValue,
        SettingsKeys.kanaPostModifierEmptyTapKaomojiCategory: "shortcut",   // Raccourcis (ショートカット)
        SettingsKeys.kanaPostModifierEmptyTapEmojiCategory: "0",            // Personnes
        SettingsKeys.kanaPostModifierEmptyTapSymbolCategory: "0",           // Symboles de base
        SettingsKeys.kanaPostModifierFlickDakutenEnabled: false,
        SettingsKeys.kanaYaBracketStyle: KanaYaBracketOption.corner.rawValue,   // 保守的=corner(「」。戦略的・現代的は doubleCorner の『』。ユーザ指定 3585)
        SettingsKeys.numberThousandsSeparator: ThousandsSeparatorOption.comma.rawValue,
        SettingsKeys.numberGroupFourDigits: true,
        SettingsKeys.numberDecimalSeparator: DecimalSeparatorOption.dot.rawValue,
        SettingsKeys.numberUnitProductSeparator: UnitProductSeparatorOption.dotOperator.rawValue,
        SettingsKeys.numberLitreSymbol: LitreSymbolOption.small.rawValue,
        SettingsKeys.degreeSymbol: DegreeSymbolOption.compat.rawValue,   // 保守的=℃(日本語環境の慣用)。標準は °C
        SettingsKeys.calendarWeekStart: CalendarWeekStartOption.monday.rawValue,
        SettingsKeys.calendarWeekdayLanguage: CalendarWeekdayLanguageOption.french.rawValue,
        SettingsKeys.calendarSundayColor: CalendarDayColorOption.dic156.rawValue,
        SettingsKeys.calendarSaturdayColor: CalendarDayColorOption.off.rawValue,
        SettingsKeys.calendarFridayColor: CalendarDayColorOption.off.rawValue,
        SettingsKeys.dateFormatStyle: DateFormatStyleOption.japanese.rawValue,
        SettingsKeys.latinLexiconFrenchEnabled: true,
        SettingsKeys.latinLexiconItalianEnabled: true,
        SettingsKeys.latinLexiconGermanEnabled: true,
        SettingsKeys.latinLexiconEnglishEnabled: true,
        SettingsKeys.kanaFlickGuideDisplayMode: FlickGuideDisplayOption.fourDirections.rawValue,  // 保守的=かなのガイドは 4 方向(ユーザ指定 3709。現代的はオフ)
        SettingsKeys.latinFlickGuideDisplayMode: FlickGuideDisplayOption.fourDirections.rawValue,
        SettingsKeys.numberFlickGuideDisplayMode: FlickGuideDisplayOption.down.rawValue,
        SettingsKeys.modifierFlickGuideDisplayMode: FlickGuideDisplayOption.off.rawValue,
        SettingsKeys.landscapeLatinSuggestionMode: LandscapeLatinSuggestionModeOption.sidebar.rawValue,
        SettingsKeys.landscapeCandidateSide: LandscapeCandidateSideOption.right.rawValue,
        SettingsKeys.landscapeNumberPaneSide: LandscapeCandidateSideOption.left.rawValue,
        SettingsKeys.accentPalette: AccentColorOption.emeraude.rawValue,
        SettingsKeys.keyboardBackgroundTheme: KeyboardBackgroundThemeOption.chartreuse.rawValue,   // 保守的=vert chartreuse(ユーザ指定 3612。戦略的=bleu、現代的=sakura)
        SettingsKeys.candidateFontStyle: CandidateFontStyleOption.apple.rawValue,   // 保守的=Apple と同じ(ユーザ指定 3644)
        SettingsKeys.delimiterAutoCommitCandidate: DelimiterAutoCommitCandidateOption.zero.rawValue,   // 保守的=句読点での自動確定は未変換かな(ユーザ指定 3718。戦略的・現代的は先頭の変換候補)
        SettingsKeys.kanaKanjiCandidateSourceMode: KanaKanjiCandidateSourceModeOption.surface.rawValue,
        SettingsKeys.historicalKanaCandidatesEnabled: false,
        SettingsKeys.iterationMarkCandidatesEnabled: false,
        SettingsKeys.katakanaEmphasisCandidateMode: ScriptVariantModeOption.suppress.rawValue,
        SettingsKeys.mazegakiCandidateMode: ScriptVariantModeOption.suppress.rawValue,
        // 旧字体・異体字の抑制は戦略的・保守的とも同じ(人名で生きている異体字だけオフ。ユーザ指定 2991)
        SettingsKeys.scriptVariantSuppressKyujitai: true,
        SettingsKeys.scriptVariantSuppressItaiji: true,
        SettingsKeys.scriptVariantSuppressRyakuji: true,
        SettingsKeys.scriptVariantSuppressConfusable: true,
        SettingsKeys.scriptVariantSuppressLookalike: true,
        SettingsKeys.scriptVariantSuppressPersonNameVariant: false,
        // かなで書く言葉: 形式名詞と指示語・代名詞は抑制せず かな を先頭に(ユーザ指定 3404)
        SettingsKeys.kanaGakiSuppressAdverb: true,
        SettingsKeys.kanaGakiSuppressConjunction: true,
        SettingsKeys.kanaGakiSuppressAuxiliary: true,
        SettingsKeys.kanaGakiSuppressFormalNoun: false,
        SettingsKeys.kanaGakiSuppressDemonstrative: false,
        SettingsKeys.kanaGakiSuppressAdverbKanaFirst: false,
        SettingsKeys.emojiCandidateDisplayEnabled: true,
        SettingsKeys.radicalStrokeCountStyle: "140:4,113:5,184:8",
        SettingsKeys.ordinalMeKanjiPreferred: false,
        SettingsKeys.kaCounterVariantPreference: KaCounterVariantPreference.conservative.encoded,  // 保守的=か・箇・ヶ・カ をオン(標準は か のみ)
        SettingsKeys.numeralStylePreference: NumeralStylePreference.conservativeDefault.rawValue,   // 保守的=漢数字が先(3702)
        SettingsKeys.okuriganaVariantPreference: OkuriganaVariantPreference.conservative.encoded,  // 保守的=本則を先に許容も出す(標準は本則だけ)
        SettingsKeys.kakikaePreference: KakikaePreference.bothAfterFirst.rawValue,  // 保守的=常用漢字を先に前も出す(ユーザ指定 3422)
        SettingsKeys.kakikaeEverydayException: true,   // 保守的=オン(ユーザ指定 3644)
        SettingsKeys.lateStandardizedRewritePreference: KakikaePreference.bothAfterFirst.rawValue,  // 保守的=X.9 と同じ(ユーザ指定 3570)
        SettingsKeys.adjectiveMeKanjiCandidatesEnabled: true,
        SettingsKeys.suspendMemorySlimmingEnabled: true,
        SettingsKeys.shortcutVocabularyRecentsFirst: true,
        SettingsKeys.kaomojiCandidateDisplayEnabled: true,
        SettingsKeys.contactCandidateDisplayMode: ContactCandidateDisplayModeOption.namesOnly.rawValue,  // 保守的=連絡先の名前を使う設定。選択操作起点なので許可要求は 5.1.1 上問題なし
        SettingsKeys.userDictionaryCandidateDisplayMode: UserDictionaryCandidateDisplayModeOption.on.rawValue
    ]

    // 現代的初期設定(contemporary、ユーザ指定 3406)。戦略的・保守的とは別個の完全な集合として定義する
    // (他の初期設定を土台にしない。3613 で保守的の値を引き継いでしまう不具合があった)
    static let contemporaryPresetValues: [String: Any] = [
        SettingsKeys.kanaLayoutMode: KanaLayoutOption.threeByThreePlusWa.rawValue,
        SettingsKeys.latinLayoutMode: LatinLayoutOption.azerty.rawValue,   // 現代的=AZERTY(戦略的と同じ。ユーザ指定 3613)
        SettingsKeys.numberLayoutMode: NumberLayoutOption.clavier.rawValue,   // 現代的=clavier(ユーザ指定 3627。戦略的=calculette、保守的=téléphone)
        SettingsKeys.formattedNumberKeypadLayout: FormattedNumberKeypadOption.calculette.rawValue,
        SettingsKeys.basicSymbolOrder: BasicSymbolOrderOption.ansi.rawValue,
        SettingsKeys.kanaModifierPlacement: KanaModifierPlacementOption.postfix.rawValue,
        SettingsKeys.directionProfile: DirectionOption.littlebear.rawValue,
        SettingsKeys.keyRepeatInitialDelay: 0.5,
        SettingsKeys.keyRepeatInterval: 0.1,
        SettingsKeys.idleCommitEnabled: false,
        SettingsKeys.idleCommitInterval: 1.2,
        SettingsKeys.composingTextStyle: ComposingTextStyleOption.ecritu.rawValue,
        SettingsKeys.leftModeSwitchNumberKeyRightFlickAction: KanaModeSwitcherActionOption.formattedNumber.rawValue,
        SettingsKeys.leftModeSwitchLatinKeyRightFlickAction: KanaModeSwitcherActionOption.emoji.rawValue,
        SettingsKeys.leftModeSwitchKanaKeyRightFlickAction: KanaModeSwitcherActionOption.kanjiRadical.rawValue,
        SettingsKeys.kanaModeSwitcherTapAction: KanaModeSwitcherActionOption.symbols.rawValue,
        SettingsKeys.kanaModeSwitcherRightFlickAction: KanaModeSwitcherActionOption.kaomoji.rawValue,
        SettingsKeys.compactKeyboardSwitchKeyRightFlickAction: KanaModeSwitcherActionOption.kaomoji.rawValue,
        SettingsKeys.compactKeyboardSwitchKeyUpFlickAction: KanaModeSwitcherActionOption.emoji.rawValue,
        SettingsKeys.kanaPostModifierEmptyTapAction: KanaPostModifierEmptyTapActionOption.kaomoji.rawValue,
        SettingsKeys.kanaPostModifierEmptyTapKaomojiCategory: "shortcut",   // Raccourcis (ショートカット)
        SettingsKeys.kanaPostModifierEmptyTapEmojiCategory: "0",            // Personnes
        SettingsKeys.kanaPostModifierEmptyTapSymbolCategory: "0",           // Symboles de base
        SettingsKeys.kanaPostModifierFlickDakutenEnabled: false,
        SettingsKeys.kanaYaBracketStyle: KanaYaBracketOption.doubleCorner.rawValue,   // 現代的=doubleCorner の『』(ユーザ指定 3585)
        SettingsKeys.numberThousandsSeparator: ThousandsSeparatorOption.comma.rawValue,
        SettingsKeys.numberGroupFourDigits: true,
        SettingsKeys.numberDecimalSeparator: DecimalSeparatorOption.dot.rawValue,
        SettingsKeys.numberUnitProductSeparator: UnitProductSeparatorOption.dotOperator.rawValue,
        SettingsKeys.numberLitreSymbol: LitreSymbolOption.small.rawValue,
        SettingsKeys.degreeSymbol: DegreeSymbolOption.compat.rawValue,   // 保守的=℃(日本語環境の慣用)。標準は °C
        SettingsKeys.calendarWeekStart: CalendarWeekStartOption.monday.rawValue,
        SettingsKeys.calendarWeekdayLanguage: CalendarWeekdayLanguageOption.french.rawValue,
        SettingsKeys.calendarSundayColor: CalendarDayColorOption.dic156.rawValue,
        SettingsKeys.calendarSaturdayColor: CalendarDayColorOption.off.rawValue,
        SettingsKeys.calendarFridayColor: CalendarDayColorOption.off.rawValue,
        SettingsKeys.dateFormatStyle: DateFormatStyleOption.japanese.rawValue,
        SettingsKeys.latinLexiconFrenchEnabled: true,
        SettingsKeys.latinLexiconItalianEnabled: true,
        SettingsKeys.latinLexiconGermanEnabled: true,
        SettingsKeys.latinLexiconEnglishEnabled: true,
        SettingsKeys.kanaFlickGuideDisplayMode: FlickGuideDisplayOption.off.rawValue,
        SettingsKeys.latinFlickGuideDisplayMode: FlickGuideDisplayOption.fourDirections.rawValue,
        SettingsKeys.numberFlickGuideDisplayMode: FlickGuideDisplayOption.down.rawValue,
        SettingsKeys.modifierFlickGuideDisplayMode: FlickGuideDisplayOption.off.rawValue,
        SettingsKeys.landscapeLatinSuggestionMode: LandscapeLatinSuggestionModeOption.sidebar.rawValue,
        SettingsKeys.landscapeCandidateSide: LandscapeCandidateSideOption.right.rawValue,
        SettingsKeys.landscapeNumberPaneSide: LandscapeCandidateSideOption.left.rawValue,
        SettingsKeys.accentPalette: AccentColorOption.emeraude.rawValue,
        SettingsKeys.keyboardBackgroundTheme: KeyboardBackgroundThemeOption.sakura.rawValue,   // 現代的=sakura(ユーザ指定 3612)
        SettingsKeys.candidateFontStyle: CandidateFontStyleOption.semibold17_5.rawValue,   // 現代的=17.5pt(ユーザ指定 3644)
        SettingsKeys.delimiterAutoCommitCandidate: DelimiterAutoCommitCandidateOption.one.rawValue,
        SettingsKeys.kanaKanjiCandidateSourceMode: KanaKanjiCandidateSourceModeOption.surface.rawValue,
        SettingsKeys.historicalKanaCandidatesEnabled: false,
        SettingsKeys.iterationMarkCandidatesEnabled: false,
        SettingsKeys.katakanaEmphasisCandidateMode: ScriptVariantModeOption.suppress.rawValue,
        SettingsKeys.mazegakiCandidateMode: ScriptVariantModeOption.suppress.rawValue,
        // 旧字体・異体字の抑制は戦略的・保守的とも同じ(人名で生きている異体字だけオフ。ユーザ指定 2991)
        SettingsKeys.scriptVariantSuppressKyujitai: true,
        SettingsKeys.scriptVariantSuppressItaiji: true,
        SettingsKeys.scriptVariantSuppressRyakuji: true,
        SettingsKeys.scriptVariantSuppressConfusable: true,
        SettingsKeys.scriptVariantSuppressLookalike: true,
        SettingsKeys.scriptVariantSuppressPersonNameVariant: false,
        // かなで書く言葉(X.8): 現代的はすべて抑制(ひらがな側に寄せる。副詞のかな先頭だけオフ。ユーザ指定 3406)
        SettingsKeys.kanaGakiSuppressAdverb: true,
        SettingsKeys.kanaGakiSuppressConjunction: true,
        SettingsKeys.kanaGakiSuppressAuxiliary: true,
        SettingsKeys.kanaGakiSuppressFormalNoun: true,
        SettingsKeys.kanaGakiSuppressDemonstrative: true,
        SettingsKeys.kanaGakiSuppressAdverbKanaFirst: false,
        SettingsKeys.emojiCandidateDisplayEnabled: true,
        SettingsKeys.radicalStrokeCountStyle: "140:4,113:5,184:8",
        SettingsKeys.ordinalMeKanjiPreferred: false,
        SettingsKeys.kaCounterVariantPreference: KaCounterVariantPreference.conservative.encoded,  // 保守的=か・箇・ヶ・カ をオン(標準は か のみ)
        SettingsKeys.numeralStylePreference: NumeralStylePreference.contemporaryDefault.rawValue,   // 現代的=アラビア数字が先(3702)
        SettingsKeys.okuriganaVariantPreference: OkuriganaVariantPreference.contemporary.encoded,  // 現代的=語幹の中だけ本則だけ、ほかは本則を先に(ユーザ指定 3737)
        SettingsKeys.kakikaePreference: KakikaePreference.bothBeforeFirst.rawValue,  // 現代的=本来の漢字を先に前も出す(3422、3431 で変更)
        SettingsKeys.kakikaeEverydayException: true,   // 現代的=オン(ユーザ指定 3644)
        SettingsKeys.lateStandardizedRewritePreference: KakikaePreference.bothBeforeFirst.rawValue,  // 現代的=X.9 と同じ(ユーザ指定 3570)
        SettingsKeys.adjectiveMeKanjiCandidatesEnabled: true,
        SettingsKeys.suspendMemorySlimmingEnabled: true,
        SettingsKeys.shortcutVocabularyRecentsFirst: true,
        SettingsKeys.kaomojiCandidateDisplayEnabled: true,
        SettingsKeys.contactCandidateDisplayMode: ContactCandidateDisplayModeOption.namesPlusFullName.rawValue,  // 現代的=フルネイムも(ユーザ指定 3679)。選択操作起点なので許可要求は 5.1.1 上問題なし
        SettingsKeys.userDictionaryCandidateDisplayMode: UserDictionaryCandidateDisplayModeOption.on.rawValue
    ]

    // ──── ジェスチャー ────

    // 触れた途端にメニューを出し、指を項目まで滑らせて離すと実行(長押しの待ちは無い。3648)。
    // ロゴ枠・メニュー項目枠・ドラッグ座標はすべて .global(ウィンドウ座標)で測る。
    // 名前付き座標系(.named)は overlay の ignoresSafeArea とセーフエリアの絡みで計測が一貫せず、
    // 指より約1項目上(2764)→半項目上(2765)と判定がずれ続けた。ウィンドウ座標なら3者の原点が同じ
    var logoPressAndDragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .updating($logoMenuGesture) { value, state, _ in
                state = .touching(value.location)
            }
            .onEnded { value in
                guard let action = logoMenuAction(at: value.location) else {
                    return
                }
                performLogoMenuAction(action)
            }
    }

    var logoMenuHighlightedAction: LogoMenuAction? {
        logoMenuGesture.location.flatMap(logoMenuAction(at:))
    }

    func logoMenuAction(at point: CGPoint) -> LogoMenuAction? {
        LogoMenuAction.allCases.first {
            isLogoMenuActionEnabled($0) && logoMenuFrames[$0.rawValue]?.contains(point) == true
        }
    }

    // 選んでも設定がどこも変わらない項目は灰色にして選べなくする(ユーザー指定 3177)。
    // 初期設定の 2 項目だけが対象 ─ 他は設定の比較で「変わらない」と言えるものではない
    func isLogoMenuActionEnabled(_ action: LogoMenuAction) -> Bool {
        switch action {
        case .strategicDefaults:
            return !currentSettingsMatch(preset: [:])
        case .conservativeDefaults:
            return !currentSettingsMatch(preset: Self.conservativePresetValues)
        case .contemporaryDefaults:
            return !currentSettingsMatch(preset: Self.contemporaryPresetValues)
        case .restoreStashedSettings:
            // 退避した設定が無ければ選べない(ユーザー指定)
            return settingsStashSavedAt != nil
        default:
            return true
        }
    }

    func refreshSettingsStashSavedAt() {
        settingsStashSavedAt = loadSettingsStash()?.savedAt
    }

    // 復元の項目名の後ろに小さく出す日時。今年なら年を省く(メニュー幅 300 に収める)
    func settingsStashSavedAtLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        let sameYear = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
        formatter.dateFormat = sameYear ? "M/d H:mm" : "yyyy/M/d H:mm"
        return "(\(formatter.string(from: date)))"
    }

    // 「今の設定」が、その初期設定を当てた直後の状態と同じか。初期設定の適用は
    // 「全キーを消してから preset を書く」なので、preset に無いキーは組み込み初期値が期待値(実効値で比較)
    // ──── 基準の初期設定(3432) ────

    // 最後に当てた初期設定。値が無い端末は現代的初期設定とみなす(ユーザ指定)
    static var currentBasePreset: SettingsBasePreset {
        sharedDefaults?.string(forKey: SettingsKeys.settingsBasePreset)
            .flatMap(SettingsBasePreset.init(rawValue:)) ?? .fallback
    }

    // 初期設定を記録する。初めてのインストールの「連絡先は使わないで始めた」印は、初期設定を行なったら消す(3437)
    static func recordBasePreset(_ preset: SettingsBasePreset, contactsStartedOff: Bool = false) {
        sharedDefaults?.set(preset.rawValue, forKey: SettingsKeys.settingsBasePreset)
        sharedDefaults?.set(contactsStartedOff, forKey: SettingsKeys.settingsBaseContactsStartedOff)
    }

    // 初期設定ごとの値(preset に無いキーは組み込みの初期値が期待値)。戦略的初期設定は組み込みの初期値そのもの
    static func presetValues(for base: SettingsBasePreset) -> [String: Any] {
        switch base {
        case .strategic: return [:]
        case .conservative: return conservativePresetValues
        case .contemporary: return contemporaryPresetValues
        }
    }

    // 指定のキーのどれかが、基準の初期設定の値から変わっているか(各項目の「変更済み」の印。3432)
    static func isModifiedFromBasePreset(keys: [String]) -> Bool {
        guard let defaults = sharedDefaults else {
            return false
        }
        let preset = presetValues(for: currentBasePreset)
        for key in keys {
            let effective = defaults.object(forKey: key) ?? builtInDefaultValues[key]
            // 初めてのインストールは現代的初期設定でも連絡先の候補だけ「使わない」で始める(審査ガイドライン 5.1.1)。
            // その端末では次に初期設定を行なうまで「使わない」を基準の値とする(3437。印が最初から付かないように)
            var expected = preset[key] ?? builtInDefaultValues[key]
            if key == SettingsKeys.contactCandidateDisplayMode,
                defaults.bool(forKey: SettingsKeys.settingsBaseContactsStartedOff) {
                expected = ContactCandidateDisplayModeOption.off.rawValue
            }
            guard let effective = effective as? NSObject, let expected = expected as? NSObject else {
                continue
            }
            if !effective.isEqual(expected) {
                return true
            }
        }
        return false
    }

    // 基準の初期設定がまだ記録されていない端末に 1 回だけ現代的初期設定を記録する(3432、ユーザ指定)。
    // 初めてインストールした端末は直前の applyInitialPresetIfFreshInstall が記録しているので素通り
    func applyBasePresetDefaultIfNeeded() {
        // 値が無いか読めない値(3432 の開発中に書いた英語の値 等)なら現代的初期設定を書く
        guard let defaults = Self.sharedDefaults,
            defaults.string(forKey: SettingsKeys.settingsBasePreset).flatMap(SettingsBasePreset.init(rawValue:)) == nil else {
            return
        }
        Self.recordBasePreset(.fallback)
    }

    private func currentSettingsMatch(preset: [String: Any]) -> Bool {
        guard let defaults = Self.sharedDefaults else {
            return false
        }
        for key in Self.userSettingsKeys {
            // 実効値で比べる(未設定は組み込み初期値。3242)。preset に無いキーは初期値が期待値
            let effective = defaults.object(forKey: key) ?? Self.builtInDefaultValues[key]
            let expected = preset[key] ?? Self.builtInDefaultValues[key]
            guard let effective = effective as? NSObject, let expected = expected as? NSObject,
                effective.isEqual(expected) else {
                return false
            }
        }
        return true
    }

    // ──── メニュー表示 ────

    @ViewBuilder
    var logoMenuOverlay: some View {
        if logoMenuGesture.isActive {
            let logoFrame = logoMenuLogoFrameBox.frame
            ZStack(alignment: .top) {
                Color.black.opacity(0.18)
                VStack(spacing: 0) {
                    ForEach(LogoMenuAction.allCases) { action in
                        // まとまりの境目に区切り線(初期設定 / 設定の控え / 案内。ユーザー指定 3591)
                        if action.startsNewGroup {
                            Divider()
                        }
                        logoMenuRowContent(
                            action,
                            isHighlighted: logoMenuHighlightedAction == action,
                            isEnabled: isLogoMenuActionEnabled(action)
                        )
                    }
                }
                .frame(width: 300)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                // ロゴの真下に隙間なく置く(指がロゴにある状態からそのまま下へ滑らせる)。
                // ロゴ枠はウィンドウ座標なので、overlay 全体を ignoresSafeArea にして原点をウィンドウ
                // 上端に揃える(overlay の中身は既定でセーフエリア内側に置かれる)。未取得なら上端
                .padding(.top, max(logoFrame.maxY, 0))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
            .allowsHitTesting(false)   // 指はロゴ上のジェスチャーが追い続ける
            .transition(.opacity)
        }
    }

    private func logoMenuRowContent(
        _ action: LogoMenuAction,
        isHighlighted: Bool,
        isEnabled: Bool
    ) -> some View {
        // 今の設定と同じ初期設定は灰色(定義箇所のコメント参照。3177)
        let labelColor: Color = isEnabled
            ? (isHighlighted ? Color.white : Color.primary)
            : Color.secondary.opacity(0.55)
        let subtitleColor: Color = isEnabled
            ? (isHighlighted ? Color.white.opacity(0.85) : Color.secondary)
            : Color.secondary.opacity(0.45)
        return HStack(spacing: 12) {
            Group {
                if let presetIcon = action.presetIcon {
                    LogoMenuPresetIconView(icon: presetIcon, size: 22)
                } else {
                    Image(systemName: action.systemImage)
                        .font(.system(size: 18, weight: .medium))
                }
            }
            // 基準の初期設定(最後に当てたもの)のアイコンはその初期設定の色(戦略的=青/現代的=ピンク/保守的=緑。3740)。選択中で項目が
            // 灰色のときも、そこから個別に変えて灰色が解けたあともその色のまま ─ どの初期設定を土台にしているかを示す(3649)。
            // 設定画面の ● も同じ色。押して強調色の背景になっている間は白(強調色の地に色で見えにくくなるため)
            .foregroundStyle(
                action == Self.currentBasePreset.menuAction
                    ? (isHighlighted && isEnabled ? Color.white : Self.currentBasePreset.markColor)
                    : labelColor
            )
            .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    // 最後に当てた初期設定に下線(3432)
                    Text(action.title)
                        .font(.body.weight(.semibold))
                        .underline(action == Self.currentBasePreset.menuAction)
                    if action == .restoreStashedSettings, let savedAt = settingsStashSavedAt {
                        Text(settingsStashSavedAtLabel(savedAt))
                            .font(.caption)
                            .foregroundStyle(subtitleColor)
                    }
                }
                Text(action.subtitle)
                    .font(.caption)
                    .foregroundStyle(subtitleColor)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(labelColor)
        .background(isHighlighted && isEnabled ? Color.accentColor : Color.clear)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: LogoMenuFramePreferenceKey.self,
                    value: [action.rawValue: proxy.frame(in: .global)]
                )
            }
        )
    }

    // ──── 実行 ────

    func performLogoMenuAction(_ action: LogoMenuAction) {
        if action.needsConfirmation {
            pendingLogoMenuAction = action
            return
        }
        switch action {
        case .copyYAML:
            copySettingsYAMLToPasteboard()
        case .stashSettings:
            stashCurrentSettings()
            refreshSettingsStashSavedAt()
        case .about:
            logoMenuInfo = LogoMenuInfo(
                title: "écritu",
                message: "\(Self.marketingVersionText)\n\(Self.editionNumberText)\n\(Self.aboutCopyrightText)"
            )
        case .openManual:
            UIApplication.shared.open(Self.manualURL)
        case .openPrivacyPolicy:
            UIApplication.shared.open(Self.privacyPolicyURL)
        case .strategicDefaults, .conservativeDefaults, .contemporaryDefaults, .restoreStashedSettings:
            break
        }
    }

    // 確認ダイアログの本文。復元は退避した日時と édition を見せる
    func logoMenuConfirmationMessage(for action: LogoMenuAction) -> String {
        switch action {
        case .strategicDefaults:
            return "すべての設定を組み込みの標準値(戦略的初期設定)に戻します。語彙・学習内容はそのままです。"
        case .conservativeDefaults:
            return "すべての設定を従来型の組み合わせ(3x3+わ・ラテン文字は 3x3・数字は téléphone・後置修飾・littlebear式のフリック 等)にします。iOS の連絡先の名前も候補に使う設定になり、まだ許可していなければ連絡先へのアクセスの許可を求めます。語彙・学習内容はそのままです。"
        case .contemporaryDefaults:
            return "すべての設定を保守的初期設定と同じにし、かなで書く言葉(所謂・即ち・事・此処 など)は 5 つの仲間すべてで漢字を出さないようにします。iOS の連絡先の名前も候補に使う設定になり、まだ許可していなければ連絡先へのアクセスの許可を求めます。語彙・学習内容はそのままです。"
        case .restoreStashedSettings:
            if let stash = loadSettingsStash() {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "ja_JP")
                formatter.dateFormat = "yyyy-MM-dd HH:mm"
                return "\(formatter.string(from: stash.savedAt)) に退避した設定(édition n°\(stash.editionNumber))に戻します。現在の設定は失われます。"
            }
            return "退避した設定がありません。"
        case .copyYAML, .stashSettings, .openManual, .openPrivacyPolicy, .about:
            return ""
        }
    }

    func confirmLogoMenuAction(_ action: LogoMenuAction) {
        switch action {
        case .strategicDefaults:
            applyStrategicDefaults()
            showSettingsToast("戦略的初期設定にしました")
        case .conservativeDefaults:
            applyConservativePreset()
            showSettingsToast("保守的初期設定にしました")
        case .contemporaryDefaults:
            applyPreset(Self.contemporaryPresetValues)
            Self.recordBasePreset(.contemporary)
            showSettingsToast("現代的初期設定にしました")
        case .restoreStashedSettings:
            if restoreStashedSettings() {
                showSettingsToast("退避した設定を復元しました")
            } else {
                logoMenuInfo = LogoMenuInfo(title: "復元できません", message: "退避した設定がありません。")
            }
            refreshSettingsStashSavedAt()
        case .copyYAML, .stashSettings, .openManual, .openPrivacyPolicy, .about:
            break
        }
    }

    // ──── 設定の書き換え ────

    private func removeAllUserSettings() {
        guard let defaults = Self.sharedDefaults else { return }
        for key in Self.userSettingsKeys {
            defaults.removeObject(forKey: key)
        }
    }

    func applyStrategicDefaults() {
        removeAllUserSettings()
        Self.recordBasePreset(.strategic)
        SettingsSyncNotification.postSettingsDidChange()
    }

    func applyConservativePreset() {
        applyPreset(Self.conservativePresetValues)
        Self.recordBasePreset(.conservative)
    }

    // 初めてインストールしたときは現代的初期設定にする(ユーザ指定 3406)。既存の端末(語彙の初期投入の記録か
    // 設定の保存があるもの)はアップデートしても変えない。連絡先の候補だけは「使わない」のまま: 現代的初期設定の元の
    // 保守的初期設定は 名前のみ だが、それは本人がメニューで選んだときの値。自動で当てると、本人の操作なしに
    // 連絡先を使う設定になる(App Store 審査ガイドライン 5.1.1)
    func applyInitialPresetIfFreshInstall() {
        guard let defaults = Self.sharedDefaults,
            !defaults.bool(forKey: SettingsKeys.initialPresetApplied) else {
            return
        }
        defaults.set(true, forKey: SettingsKeys.initialPresetApplied)
        let isExistingInstall = defaults.object(forKey: SettingsKeys.kanaKanjiInitialAjoutVocabularyAppliedSeed) != nil
            || defaults.object(forKey: SettingsKeys.kanaKanjiInitialAjoutVocabularyMigrated) != nil
            || Self.userSettingsKeys.contains { defaults.object(forKey: $0) != nil }
        guard !isExistingInstall else {
            return
        }
        var preset = Self.contemporaryPresetValues
        preset[SettingsKeys.contactCandidateDisplayMode] = ContactCandidateDisplayModeOption.off.rawValue
        applyPreset(preset)
        Self.recordBasePreset(.contemporary, contactsStartedOff: true)
    }

    // 同音の漢字による書きかえ(3422)の値がまだ無い端末(この設定より前から使っている人)に 1 回だけ 両方(本来の漢字を先に)を書く。
    // 組み込みの標準値(戦略的初期設定)は 本来の漢字だけ なので、書かないとアップデートした途端に 回転→廻転 等になる。
    // 初めてインストールした端末は直前の applyInitialPresetIfFreshInstall が 両方(本来の漢字を先に) を書いているので素通り
    // 数詞の表記(X.19。3702)の値が無い端末は、基準の初期設定ごとの値を書く(戦略的=アラビア数字だけ、保守的=漢数字が先、現代的=アラビア数字が先)
    func applyNumeralStyleDefaultForExistingInstallIfNeeded() {
        guard let defaults = Self.sharedDefaults,
            defaults.object(forKey: SettingsKeys.numeralStylePreference) == nil else {
            return
        }
        let value: NumeralStylePreference
        switch Self.currentBasePreset {
        case .strategic: value = .strategicDefault
        case .conservative: value = .conservativeDefault
        case .contemporary: value = .contemporaryDefault
        }
        defaults.set(value.rawValue, forKey: SettingsKeys.numeralStylePreference)
        SettingsSyncNotification.postSettingsDidChange()
    }

    func applyKakikaeDefaultForExistingInstallIfNeeded() {
        guard let defaults = Self.sharedDefaults,
            defaults.object(forKey: SettingsKeys.kakikaePreference) == nil else {
            return
        }
        defaults.set(KakikaePreference.existingInstallDefault.rawValue, forKey: SettingsKeys.kakikaePreference)
        SettingsSyncNotification.postSettingsDidChange()
    }

    // 例外グループのスイッチ(3644)の値がまだ無い端末は オン(3611 以来、了解 等を常用漢字先にしてきた動作を守る)。
    // 組み込みの標準値(戦略的初期設定)はオフなので、書かないと更新した途端に 諒解 が先頭になる
    func applyKakikaeEverydayExceptionDefaultForExistingInstallIfNeeded() {
        guard let defaults = Self.sharedDefaults,
            defaults.object(forKey: SettingsKeys.kakikaeEverydayException) == nil else {
            return
        }
        defaults.set(true, forKey: SettingsKeys.kakikaeEverydayException)
        SettingsSyncNotification.postSettingsDidChange()
    }

    // 報告の後に常用漢字に加わった字の組(X.10。3570)の値がまだ無い端末は 両方(本来の漢字を先に)。
    // この設定より前は常に両方を出していたので、組み込みの標準値(本来の漢字だけ)にすると 肝心/憶測 が消える
    func applyLateStandardizedRewriteDefaultForExistingInstallIfNeeded() {
        guard let defaults = Self.sharedDefaults,
            defaults.object(forKey: SettingsKeys.lateStandardizedRewritePreference) == nil else {
            return
        }
        defaults.set(KakikaePreference.existingInstallDefault.rawValue, forKey: SettingsKeys.lateStandardizedRewritePreference)
        SettingsSyncNotification.postSettingsDidChange()
    }

    // 🌐 キーの右・上フリックの割り当て(3618)は、3617 まで kanaModeSwitcherRightFlickAction /
    // kanaModeSwitcherUpFlickAction に入っていた。新しいキーが無い端末には旧キーの保存値を 1 回写す。
    // 写さないと組み込みの初期値(上=記号)が見え、保守的・現代的(上=絵文字)の端末で ● の印が付く。
    // 右の旧キーは最下段の右フリックの意味で残るので、そのまま 🌐 の右にも写す
    func applyCompactKeyboardSwitchKeyAssignmentsForExistingInstallIfNeeded() {
        guard let defaults = Self.sharedDefaults else {
            return
        }
        var didWrite = false
        if defaults.object(forKey: SettingsKeys.compactKeyboardSwitchKeyUpFlickAction) == nil,
            let legacyUp = defaults.string(forKey: SettingsKeys.legacyKanaModeSwitcherUpFlickAction),
            KanaModeSwitcherActionOption(rawValue: legacyUp) != nil {
            defaults.set(legacyUp, forKey: SettingsKeys.compactKeyboardSwitchKeyUpFlickAction)
            didWrite = true
        }
        if defaults.object(forKey: SettingsKeys.compactKeyboardSwitchKeyRightFlickAction) == nil,
            let legacyRight = defaults.string(forKey: SettingsKeys.kanaModeSwitcherRightFlickAction),
            KanaModeSwitcherActionOption(rawValue: legacyRight) != nil {
            defaults.set(legacyRight, forKey: SettingsKeys.compactKeyboardSwitchKeyRightFlickAction)
            didWrite = true
        }
        if didWrite {
            SettingsSyncNotification.postSettingsDidChange()
        }
    }

    // 『や』キーの括弧の保存値を、括弧そのもの(3656 より前)から名前へ書き換える。
    // 読むほうは両方を受けるが、初期設定との一致判定(灰色・● の印)は保存値の文字列で比べるため揃えておく。
    // 起動時と、退避した設定の復元のあとに呼ぶ
    func normalizeLegacyKanaYaBracketValueIfNeeded() {
        guard let defaults = Self.sharedDefaults,
            let stored = defaults.string(forKey: SettingsKeys.kanaYaBracketStyle),
            let option = KanaYaBracketOption(rawValue: stored),
            option.rawValue != stored else {
            return
        }
        defaults.set(option.rawValue, forKey: SettingsKeys.kanaYaBracketStyle)
        SettingsSyncNotification.postSettingsDidChange()
    }

    func applyPreset(_ preset: [String: Any]) {
        guard let defaults = Self.sharedDefaults else { return }
        removeAllUserSettings()
        for (key, value) in preset {
            defaults.set(value, forKey: key)
        }
        SettingsSyncNotification.postSettingsDidChange()
    }

    func stashCurrentSettings() {
        guard let defaults = Self.sharedDefaults else { return }
        var values: [String: SettingsStash.Value] = [:]
        for key in Self.userSettingsKeys {
            if let raw = defaults.object(forKey: key), let value = SettingsStash.Value(defaultsValue: raw) {
                values[key] = value
            }
        }
        let editionNumber = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "?"
        let stash = SettingsStash(
            editionNumber: editionNumber, savedAt: Date(), values: values,
            basePreset: Self.currentBasePreset.rawValue,
            basePresetContactsStartedOff: Self.sharedDefaults?.bool(forKey: SettingsKeys.settingsBaseContactsStartedOff) ?? false
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(stash), SettingsStashStore.save(data) else {
            logoMenuInfo = LogoMenuInfo(title: "退避できません", message: "設定の保存(Keychain)に失敗しました。")
            return
        }
        showSettingsToast("現在の設定を退避しました(\(values.count) 項目)")
    }

    func loadSettingsStash() -> SettingsStash? {
        guard let data = SettingsStashStore.load() else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SettingsStash.self, from: data)
    }

    // 退避時に無かったキーは初期設定に戻す(退避時点の状態を丸ごと再現する)
    func restoreStashedSettings() -> Bool {
        guard let stash = loadSettingsStash(), let defaults = Self.sharedDefaults else { return false }
        removeAllUserSettings()
        for (key, value) in stash.values where Self.userSettingsKeys.contains(key) {
            defaults.set(value.anyValue, forKey: key)
        }
        // 基準の初期設定も戻す(3432)。これより前の退避には無いので、そのときは今の記録のまま
        if let base = stash.basePreset.flatMap(SettingsBasePreset.init(rawValue:)) {
            Self.recordBasePreset(base, contactsStartedOff: stash.basePresetContactsStartedOff ?? false)
        }
        normalizeLegacyKanaYaBracketValueIfNeeded()   // 3656 より前に退避した設定の括弧の値
        SettingsSyncNotification.postSettingsDidChange()
        return true
    }

    // ──── トースト ────

    func showSettingsToast(_ message: String, duration: TimeInterval = 1.8, accented: Bool = false) {
        withAnimation(.easeOut(duration: 0.15)) {
            settingsToastAccented = accented
            settingsToastMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            withAnimation(.easeIn(duration: 0.3)) {
                if settingsToastMessage == message {
                    settingsToastMessage = nil
                }
            }
        }
    }
}

// ──── 題字(écritu)のメニュー(3699、ユーザ指定) ────
// 題字に触れた途端に、設定の各項目(L.1〜X.19)へ飛ぶだけのメニューを題字の真下に出す。操作はアイコンのメニューと同じで、
// 指を項目まで滑らせて離すとその項目へスクロールする。項目の外で離せば何もしない。題字の上で離したとき(ふつうのタップ)は
// 従来どおり一番上へ戻る(3205)。項目は 42 あるので、1 行の高さは画面に収まるよう縮め、それでも入らない横画面は 2〜3 列にする。
// 開発ビルド(#if DEBUG。TestFlight の版も Debug 構成でアーカイブしているので含む)では先頭に[学習リセット+変換キャッシュクリア]を置く。
// 題字はツールバーの中(別のホスティング)なので、その .global はウィンドウ座標と原点が違いうる。題字のウィンドウ上の枠を
// UIKit で取り(WindowFrameReader)、指の位置をウィンドウ座標に直してからメニューの行(ルートの overlay の .global)と比べる

struct SettingsJumpMenuItem: Equatable {
    let cardID: String
    let title: String
}

// serial は同じ項目を続けて選んでも onChange が来るようにするための通し番号
struct SettingsJumpRequest: Equatable {
    let item: SettingsJumpMenuItem
    let serial: Int
}

enum SettingsJumpMenuTarget: Equatable {
    case resetLearningAndCache
    case item(SettingsJumpMenuItem)
}

// メニューの 1 行(リセットの項目か、設定の項目)。群は 1 つおきにアクセントカラーの淡い帯を敷き(groupOrdinal が奇数)、
// 群の最初の行の右端に群の名前を出す(ユーザ指定 3700: 区切り線だけでは見づらい、色は増やさない・灰色は使わない)
struct SettingsJumpMenuEntry {
    let target: SettingsJumpMenuTarget
    // 項目番号(L.1 等)と見出し。リセットの項目は番号なし
    let number: String?
    let title: String
    let frameKey: String
    let group: Character
    // 設定の群の通し番号(L=0, E=1, …)。リセットの項目は -1
    let groupOrdinal: Int
    let isDestructive: Bool
}

enum SettingsJumpMenu {
    static let resetFrameKey = "jump:reset"

    static func frameKey(_ cardID: String) -> String {
        "jump:" + cardID
    }

    static func sectionAnchorID(_ cardID: String) -> String {
        "settings-section-" + cardID
    }

    #if DEBUG
    static let showsResetItem = true
    #else
    static let showsResetItem = false
    #endif

    // 画面の並び(キー配列 L → 入力 E → キー表示 G → 表示 V → 書式 F → 変換 X)。見出しの文言と同じ
    static let items: [SettingsJumpMenuItem] = rawItems.map { SettingsJumpMenuItem(cardID: $0.0, title: $0.1) }
    private static let rawItems: [(String, String)] = [
        ("L.1", "かな配列"), ("L.2", "ラテン文字配列"), ("L.3", "数字配列"), ("L.4", "基本記号の並び順"), ("L.5", "かな修飾"),
        ("E.1", "フリック方向"), ("E.2", "削除キーリピート"), ("E.3", "自動確定(アイドル)"), ("E.4", "未確定の方式"),
        ("E.5", "モード切り替えキーの割り当て"), ("E.6", "修飾キーのタップ (後置修飾、未確定なし)"),
        ("E.7", "後置修飾キーのフリックで濁点・半濁点"), ("E.8", "欧文サジェスチョンの言語"), ("E.9", "『や』キーの左右フリックの括弧"),
        ("G.1", "ガイド文字表示"),
        ("V.1", "ラテン文字候補ペイン (horizontal)"), ("V.2", "数字ペイン配列 (horizontal)"), ("V.3", "アクセントカラー"),
        ("V.4", "テーマカラー"), ("V.5", "候補の文字"),
        ("F.1", "format numérique"), ("F.2", "degré"), ("F.3", "カレンダー"),
        ("X.1", "句読点入力時の自動確定候補"), ("X.2", "かな漢字候補モード"), ("X.3", "旧仮名遣い候補"), ("X.4", "仮名の踊り字候補"),
        ("X.5", "カタカナ強調表記の候補"), ("X.6", "交ぜ書きの候補"), ("X.7", "旧字体・異体字の候補"), ("X.8", "かなで書く言葉の候補"),
        ("X.9", "常用漢字による書きかえ"), ("X.10", "常用漢字による書きかえ(後に追加)"), ("X.11", "部首の画数の数え方"),
        ("X.12", "助数詞型suffixe / 数詞類別suffixe – ka"), ("X.13", "送り仮名の許容形 – orthographe"), ("X.14", "序数化suffixe – me"),
        ("X.15", "形状名詞化suffixe / 傾向派生suffixe – me"), ("X.16", "emojis & les émoticônes"),
        ("X.17", "iOSの連絡先の姓、名、会社名"), ("X.18", "iOSのユーザ辞書の単語"), ("X.19", "数詞の表記 – chiffres")
    ]

    // 群の名前(設定の一覧の区分と同じ)
    static let groupNames: [Character: String] = [
        "L": "キー配列", "E": "入力", "G": "キー表示", "V": "表示", "F": "書式", "X": "変換"
    ]

    static let entries: [SettingsJumpMenuEntry] = {
        var list: [SettingsJumpMenuEntry] = []
        if showsResetItem {
            list.append(SettingsJumpMenuEntry(
                target: .resetLearningAndCache, number: nil, title: "学習リセット+変換キャッシュクリア",
                frameKey: resetFrameKey, group: "!", groupOrdinal: -1, isDestructive: true
            ))
        }
        var ordinal = -1
        var previousGroup: Character?
        for item in items {
            let group = item.cardID.first ?? "?"
            if group != previousGroup {
                ordinal += 1
                previousGroup = group
            }
            list.append(SettingsJumpMenuEntry(
                target: .item(item), number: item.cardID, title: item.title,
                frameKey: frameKey(item.cardID), group: group, groupOrdinal: ordinal, isDestructive: false
            ))
        }
        return list
    }()

    // 群の最初の行か(列の先頭も含む。横画面で群が次の列へ続くときも名前を出す)
    static func startsGroup(_ column: [SettingsJumpMenuEntry], at index: Int) -> Bool {
        index == 0 || column[index - 1].group != column[index].group
    }

    struct Layout {
        let columns: [[SettingsJumpMenuEntry]]
        let rowHeight: CGFloat
        let fontSize: CGFloat
        let columnWidth: CGFloat
    }

    // 区切り線はリセットの項目と設定の項目の境目だけ(設定の群どうしは帯で分ける)
    static func showsDivider(_ column: [SettingsJumpMenuEntry], before index: Int) -> Bool {
        index > 0 && (column[index - 1].groupOrdinal < 0) != (column[index].groupOrdinal < 0)
    }

    static func dividerCount(in column: [SettingsJumpMenuEntry]) -> Int {
        column.indices.filter { showsDivider(column, before: $0) }.count
    }

    // 1 列で 1 行 15pt 以上取れればそのまま(上限 26pt)、取れなければ 2 列・3 列にする(横画面)。文字は行の高さ−4pt(9〜13pt)
    static func layout(availableHeight: CGFloat, availableWidth: CGFloat) -> Layout {
        let all = entries
        for columnCount in 1...3 {
            let perColumn = Int((Double(all.count) / Double(columnCount)).rounded(.up))
            let columns = stride(from: 0, to: all.count, by: perColumn).map { Array(all[$0..<min($0 + perColumn, all.count)]) }
            let dividers = CGFloat(columns.map(dividerCount(in:)).max() ?? 0)
            let fitted = floor((availableHeight - dividers - 12) / CGFloat(perColumn))   // 上下の余白 6pt ずつ
            if fitted >= 15 || columnCount == 3 {
                let rowHeight = min(26, max(11, fitted))
                let columnWidth = columnCount == 1
                    ? min(300, availableWidth - 24)
                    : min(250, (availableWidth - 24 - CGFloat(columnCount - 1) * 8) / CGFloat(columnCount))
                return Layout(columns: columns, rowHeight: rowHeight, fontSize: max(9, min(13, rowHeight - 4)), columnWidth: columnWidth)
            }
        }
        return Layout(columns: [all], rowHeight: 13, fontSize: 9, columnWidth: 300)
    }
}

// 飛んで着いたカードを一瞬光らせる(どこへ飛んだかを見せる。ユーザ指定 3704)
final class SettingsJumpHighlight: ObservableObject {
    static let shared = SettingsJumpHighlight()
    @Published var anchorID: String?
}

struct SettingsJumpHighlightOverlay: ViewModifier {
    let anchorID: String
    @ObservedObject private var highlight = SettingsJumpHighlight.shared

    func body(content: Content) -> some View {
        content.overlay {
            // カードの角(settingsCardStyle の 14pt)に合わせたアクセントカラーの枠
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.accentColor, lineWidth: 3)
                .opacity(highlight.anchorID == anchorID ? 1 : 0)
                .allowsHitTesting(false)
        }
    }
}

extension View {
    // 題字のメニューの飛び先の目印(scrollTo の .id と、着いたときに光らせる枠)
    func settingsJumpAnchor(_ anchorID: String) -> some View {
        modifier(SettingsJumpHighlightOverlay(anchorID: anchorID))
            .id(anchorID)
    }
}

#if os(iOS)
// ビューのウィンドウ上の枠を UIKit で知らせる(ツールバーの中の SwiftUI の .global はウィンドウ座標と原点が違いうるため。3699)
struct WindowFrameReader: UIViewRepresentable {
    let onChange: (CGRect) -> Void

    func makeUIView(context: Context) -> WindowFrameReaderView {
        let view = WindowFrameReaderView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.onChange = onChange
        return view
    }

    func updateUIView(_ uiView: WindowFrameReaderView, context: Context) {
        uiView.onChange = onChange
        uiView.report()
    }
}

final class WindowFrameReaderView: UIView {
    var onChange: ((CGRect) -> Void)?
    private var lastReported: CGRect = .null

    override func layoutSubviews() {
        super.layoutSubviews()
        report()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        report()
    }

    // 変わったときだけ、次の周回で知らせる(SwiftUI の更新中に状態を書き換えない)
    func report() {
        guard window != nil else {
            return
        }
        let frame = convert(bounds, to: nil)
        guard frame != lastReported else {
            return
        }
        lastReported = frame
        let onChange = onChange
        DispatchQueue.main.async {
            onChange?(frame)
        }
    }
}

#endif

extension ContentView {
    // 題字のウィンドウ上の枠(UIKit で取れていなければ .global の枠)
    var titleMenuTitleFrameInWindow: CGRect {
        titleMenuTitleWindowFrame.isEmpty ? titleMenuTitleFrame : titleMenuTitleWindowFrame
    }

    // ツールバーの中の .global の点をウィンドウ座標へ(題字の 2 つの枠の原点の差だけずらす)
    func titleMenuWindowPoint(_ point: CGPoint) -> CGPoint {
        guard !titleMenuTitleWindowFrame.isEmpty, !titleMenuTitleFrame.isEmpty else {
            return point
        }
        return CGPoint(
            x: point.x + titleMenuTitleWindowFrame.minX - titleMenuTitleFrame.minX,
            y: point.y + titleMenuTitleWindowFrame.minY - titleMenuTitleFrame.minY
        )
    }

    // 触れた途端にメニューを出し、指を項目まで滑らせて離すと実行(アイコンのメニューと同じ)。指の位置はウィンドウ座標に直して持つ
    var titlePressAndDragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .updating($titleMenuGesture) { value, state, _ in
                state = .touching(titleMenuWindowPoint(value.location))
            }
            .onEnded { value in
                let point = titleMenuWindowPoint(value.location)
                if let target = titleMenuTarget(at: point) {
                    performTitleMenuTarget(target)
                } else if titleMenuTitleFrameInWindow.contains(point) {
                    // 題字の上で離した(ふつうのタップ): 従来どおり一番上へ戻る(3205)
                    scrollToTopTrigger += 1
                }
            }
    }

    func titleMenuTarget(at point: CGPoint) -> SettingsJumpMenuTarget? {
        SettingsJumpMenu.entries
            .first { logoMenuFrames[$0.frameKey]?.contains(point) == true }
            .map(\.target)
    }

    func performTitleMenuTarget(_ target: SettingsJumpMenuTarget) {
        switch target {
        case .resetLearningAndCache:
            // 学習リセット。学習の世代を上げたうえで設定の世代も上げる(=変換キャッシュのクリアと同じ合図)ので、両方が 1 回で済む
            resetKanaKanjiLearning()
            showSettingsToast("学習をリセットし、変換キャッシュをクリアしました", accented: true)
        case .item(let item):
            settingsJumpRequest = SettingsJumpRequest(item: item, serial: (settingsJumpRequest?.serial ?? 0) + 1)
        }
    }

    // 選んだ項目へ飛ぶ(3712)。一覧は全部のカードを作る VStack なので、scrollTo 1 回で正しい位置に着く。素直に
    // スクロールして見せ、着いたカードを 0.8 秒光らせる(3704、ユーザ指定)。
    // 3699〜3709 の LazyVStack ではまだ作っていないカードの高さが見積もりで、1 回の scrollTo では大きく外れた。飛び直し・
    // 薄くする・滑らせるで補っていたが、着いたあとに上下へ動くのが残った(ユーザ指定で素直なスクロールに)。
    // 一覧を作り終える前(起動直後)に選ばれたら、残りの塊を一度に作ってから飛ぶ。作るのは次の描画なので、
    // すぐに飛ぶとまだ無いカードへの scrollTo が空振りする。0.05 秒おく(描画で主スレッドが埋まっている間は待たされる)
    func startSettingsJump(_ request: SettingsJumpRequest, proxy: ScrollViewProxy) {
        SettingsJumpHighlight.shared.anchorID = nil
        guard settingsCardStagesBuilt >= Self.settingsCardStageCount else {
            settingsCardStagesBuilt = Self.settingsCardStageCount
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                guard settingsJumpRequest == request else {
                    return
                }
                startSettingsJump(request, proxy: proxy)
            }
            return
        }
        let targetID = SettingsJumpMenu.sectionAnchorID(request.item.cardID)
        withAnimation(.easeInOut(duration: 0.4)) {
            proxy.scrollTo(targetID, anchor: .top)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard settingsJumpRequest == request else {
                return
            }
            withAnimation(.easeOut(duration: 0.15)) {
                SettingsJumpHighlight.shared.anchorID = targetID
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                guard SettingsJumpHighlight.shared.anchorID == targetID else {
                    return
                }
                withAnimation(.easeOut(duration: 0.4)) {
                    SettingsJumpHighlight.shared.anchorID = nil
                }
            }
        }
    }

    // 画面下端のセーフエリア(ホームインジケーター)。メニューをその上で止める
    private var titleMenuBottomInset: CGFloat {
        #if os(iOS)
        return UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.bottom }
            .first ?? 34
        #else
        return 0
        #endif
    }

    @ViewBuilder
    var titleMenuOverlay: some View {
        if titleMenuGesture.isActive {
            let highlighted = titleMenuGesture.location.flatMap(titleMenuTarget(at:))
            GeometryReader { proxy in
                // overlay は ignoresSafeArea なので proxy の座標はウィンドウ座標(題字のウィンドウ上の枠と同じ)
                let top = max(titleMenuTitleFrameInWindow.maxY + 2, 0)
                let layout = SettingsJumpMenu.layout(
                    availableHeight: proxy.size.height - top - titleMenuBottomInset - 8,
                    availableWidth: proxy.size.width
                )
                ZStack(alignment: .top) {
                    Color.black.opacity(0.18)
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(Array(layout.columns.enumerated()), id: \.offset) { _, column in
                            VStack(spacing: 0) {
                                ForEach(Array(column.enumerated()), id: \.element.frameKey) { index, entry in
                                    if SettingsJumpMenu.showsDivider(column, before: index) {
                                        Divider()
                                    }
                                    titleMenuRow(
                                        entry,
                                        isHighlighted: highlighted == entry.target,
                                        isGroupStart: entry.groupOrdinal >= 0 && SettingsJumpMenu.startsGroup(column, at: index),
                                        layout: layout
                                    )
                                }
                            }
                            .padding(.vertical, 6)
                            .frame(width: layout.columnWidth)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                        }
                    }
                    .padding(.top, top)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)   // 指は題字の上のジェスチャーが追い続ける
            .transition(.opacity)
        }
    }

    // 1 行: 幅をそろえた番号、見出し、群の最初の行だけ右端に群の名前と番号の頭の文字(アクセントカラー)。
    // 群は 1 つおきにアクセントカラーの淡い帯。指の下の行はアクセントカラーの塗りで、文字は白
    private func titleMenuRow(
        _ entry: SettingsJumpMenuEntry,
        isHighlighted: Bool,
        isGroupStart: Bool,
        layout: SettingsJumpMenu.Layout
    ) -> some View {
        let bandColor: Color = isHighlighted
            ? Color.accentColor
            : (entry.groupOrdinal % 2 == 1 ? Color.accentColor.opacity(0.08) : Color.clear)
        // 初期設定から変わっている項目の印(設定の見出しの ● と同じ判定・同じ色。番号と見出しの間。3739、ユーザ指定)
        let isModified: Bool = {
            guard let number = entry.number,
                let keys = SettingsCardKeys.keysForModifiedMark(
                    cardID: number,
                    action: SettingsCardKeys.currentPostModifierEmptyTapAction
                ) else {
                return false
            }
            return ContentView.isModifiedFromBasePreset(keys: keys)
        }()
        return HStack(spacing: 6) {
            if let number = entry.number {
                // 番号は右寄せで ● のすぐ左に付け、欄の幅は X.19 が収まる分だけ(番号と ● と見出しの間を詰めて、見出しの
                // 末尾が … になるのを減らす。3740、ユーザ指定)。印の無い行も ● の幅を取り、見出しの頭をそろえる
                HStack(spacing: 1) {
                    Text(number)
                        .font(.system(size: layout.fontSize).monospacedDigit())
                        .frame(width: layout.fontSize * 2.3, alignment: .trailing)
                    Text("●")
                        .font(.system(size: max(6, layout.fontSize - 5)))
                        .foregroundStyle(isHighlighted ? Color.white : ContentView.currentBasePreset.markColor.opacity(0.75))
                        .opacity(isModified ? 1 : 0)
                        .frame(width: layout.fontSize * 0.5)
                        .accessibilityHidden(!isModified)
                        .accessibilityLabel("初期設定から変更あり")
                }
                .padding(.trailing, -3)
            }
            Text(entry.title)
                .font(.system(size: layout.fontSize, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if isGroupStart, let groupName = SettingsJumpMenu.groupNames[entry.group] {
                // 区分の名前と番号の頭の文字(キー配列 (L)。ユーザ指定 3701)
                Text("\(groupName) (\(String(entry.group)))")
                    .font(.system(size: max(8, layout.fontSize - 2), weight: .semibold))
                    .foregroundStyle(isHighlighted ? Color.white : Color.accentColor)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .foregroundStyle(isHighlighted ? Color.white : (entry.isDestructive ? Color.red : Color.primary))
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: layout.rowHeight, maxHeight: layout.rowHeight, alignment: .leading)
        .background(bandColor)
        .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: LogoMenuFramePreferenceKey.self,
                        value: [entry.frameKey: proxy.frame(in: .global)]
                    )
                }
            )
    }
}
