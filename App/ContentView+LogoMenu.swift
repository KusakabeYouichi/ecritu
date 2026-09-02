import SwiftUI
import Security
#if os(iOS)
import UIKit
#endif

// ロゴ長押しメニュー(2760)。長押し(0.5秒)でロゴ直下にメニューを出し、押している間だけ表示する。
// 指を項目まで滑らせて離すとその項目を実行、動かさずに離せば何もしない(離した時点でメニューは消える)。
// 従来の「ロゴ長押し=設定を YAML でコピー」はメニューの1項目に移した。

enum LogoMenuAction: String, CaseIterable, Identifiable {
    case strategicDefaults
    case conservativeDefaults
    case copyYAML
    case stashSettings
    case restoreStashedSettings
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .strategicDefaults: return "戦略的初期設定"
        case .conservativeDefaults: return "保守的初期設定"
        case .copyYAML: return "設定をクリップボードにコピー"
        case .stashSettings: return "現在の設定を退避"
        case .restoreStashedSettings: return "退避した設定を復元"
        case .about: return "écritu について"
        }
    }

    var subtitle: String {
        switch self {
        case .strategicDefaults: return "初期設定(標準)に戻す"
        case .conservativeDefaults: return "作者の使用設定にする"
        case .copyYAML: return "YAML 形式"
        case .stashSettings: return "再インストール後も残る場所に保存"
        case .restoreStashedSettings: return "退避していた設定に戻す"
        case .about: return "édition と著作権表示"
        }
    }

    var systemImage: String {
        switch self {
        case .strategicDefaults: return "arrow.counterclockwise"
        case .conservativeDefaults: return "person.crop.circle"
        case .copyYAML: return "doc.on.clipboard"
        case .stashSettings: return "tray.and.arrow.down"
        case .restoreStashedSettings: return "tray.and.arrow.up"
        case .about: return "info.circle"
        }
    }

    // 設定を書き換える項目は確認ダイアログを挟む(ユーザ指定)
    var needsConfirmation: Bool {
        switch self {
        case .strategicDefaults, .conservativeDefaults, .restoreStashedSettings: return true
        case .copyYAML, .stashSettings, .about: return false
        }
    }
}

// 長押し→ドラッグの進行状態。GestureState なので指を離すと自動で .inactive に戻り、メニューも消える
enum LogoMenuGestureState: Equatable {
    case inactive
    case pressing
    case dragging(CGPoint)

    var isActive: Bool { self != .inactive }

    var location: CGPoint? {
        if case .dragging(let point) = self { return point }
        return nil
    }
}

// 情報表示用のアラート(確認ではなく OK だけ)
struct LogoMenuInfo: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

// ロゴとメニュー項目の枠を同じ座標空間で集める(指の位置との当たり判定用)
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
    private static let service = "com.kusakabe.ecritu.settings-stash"
    private static let account = "settings"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static func save(_ data: Data) -> Bool {
        var query = baseQuery
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        query[kSecValueData as String] = data
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update: [String: Any] = [kSecValueData as String: data]
            return SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary) == errSecSuccess
        }
        return status == errSecSuccess
    }

    static func load() -> Data? {
        var query = baseQuery
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
}

extension ContentView {
    static let logoMenuCoordinateSpace = "logoMenuSpace"
    static let logoMenuLogoFrameKey = "logo"
    static let aboutCopyrightText = "Copyright © 2026 Youichi Kusakabe"

    // ユーザが変えられる設定のキー(設定画面の全項目)。settingsYAMLExportText と同じ集合を保つこと。
    // 語彙・学習・診断ログなどのデータ系キーは含めない(初期設定に戻しても消えない)
    static let userSettingsKeys: [String] = [
        SettingsKeys.kanaLayoutMode, SettingsKeys.latinLayoutMode, SettingsKeys.numberLayoutMode,
        SettingsKeys.formattedNumberKeypadLayout, SettingsKeys.basicSymbolOrder, SettingsKeys.kanaModifierPlacement,
        SettingsKeys.directionProfile, SettingsKeys.keyRepeatInitialDelay, SettingsKeys.keyRepeatInterval,
        SettingsKeys.idleCommitEnabled, SettingsKeys.idleCommitInterval,
        SettingsKeys.kanaModeSwitcherTapAction, SettingsKeys.kanaModeSwitcherRightFlickAction, SettingsKeys.kanaModeSwitcherUpFlickAction,
        SettingsKeys.kanaPostModifierEmptyTapAction, SettingsKeys.kanaPostModifierEmptyTapKaomojiCategory,
        SettingsKeys.kanaPostModifierEmptyTapEmojiCategory, SettingsKeys.kanaPostModifierEmptyTapSymbolCategory,
        SettingsKeys.kanaPostModifierFlickDakutenEnabled,
        SettingsKeys.numberThousandsSeparator, SettingsKeys.numberGroupFourDigits, SettingsKeys.numberDecimalSeparator,
        SettingsKeys.numberUnitProductSeparator, SettingsKeys.numberLitreSymbol,
        SettingsKeys.calendarWeekStart, SettingsKeys.calendarWeekdayLanguage, SettingsKeys.calendarSundayColor,
        SettingsKeys.calendarSaturdayColor, SettingsKeys.calendarFridayColor, SettingsKeys.dateFormatStyle,
        SettingsKeys.latinLexiconFrenchEnabled, SettingsKeys.latinLexiconItalianEnabled,
        SettingsKeys.latinLexiconGermanEnabled, SettingsKeys.latinLexiconEnglishEnabled,
        SettingsKeys.kanaFlickGuideDisplayMode, SettingsKeys.latinFlickGuideDisplayMode,
        SettingsKeys.numberFlickGuideDisplayMode, SettingsKeys.modifierFlickGuideDisplayMode,
        SettingsKeys.landscapeLatinSuggestionMode, SettingsKeys.landscapeCandidateSide, SettingsKeys.landscapeNumberPaneSide,
        SettingsKeys.accentPalette, SettingsKeys.keyboardBackgroundTheme,
        SettingsKeys.delimiterAutoCommitCandidate, SettingsKeys.kanaKanjiCandidateSourceMode,
        SettingsKeys.historicalKanaCandidatesEnabled, SettingsKeys.iterationMarkCandidatesEnabled,
        SettingsKeys.katakanaEmphasisCandidateMode, SettingsKeys.mazegakiCandidateMode,
        SettingsKeys.emojiCandidateDisplayEnabled, SettingsKeys.radicalStrokeCountStyle,
        SettingsKeys.ordinalMeKanjiPreferred, SettingsKeys.adjectiveMeKanjiCandidatesEnabled,
        SettingsKeys.suspendMemorySlimmingEnabled, SettingsKeys.kaomojiCandidateDisplayEnabled,
        SettingsKeys.contactCandidateDisplayMode, SettingsKeys.userDictionaryCandidateDisplayMode
    ]

    // 保守的初期設定 = 作者の使用設定(2026-09-02 の YAML エクスポートから転記。ユーザ指定 2760)。
    // 書いていないキーは標準の初期設定のまま(適用前に全キーを消してから上書きする)
    static let conservativePresetValues: [String: Any] = [
        SettingsKeys.kanaLayoutMode: KanaLayoutOption.threeByThreePlusWa.rawValue,
        SettingsKeys.latinLayoutMode: LatinLayoutOption.azerty.rawValue,
        SettingsKeys.numberLayoutMode: NumberLayoutOption.clavier.rawValue,
        SettingsKeys.formattedNumberKeypadLayout: FormattedNumberKeypadOption.calculette.rawValue,
        SettingsKeys.basicSymbolOrder: BasicSymbolOrderOption.ansi.rawValue,
        SettingsKeys.kanaModifierPlacement: KanaModifierPlacementOption.postfix.rawValue,
        SettingsKeys.directionProfile: DirectionOption.apple.rawValue,
        SettingsKeys.keyRepeatInitialDelay: 0.5,
        SettingsKeys.keyRepeatInterval: 0.1,
        SettingsKeys.idleCommitEnabled: false,
        SettingsKeys.idleCommitInterval: 1.2,
        SettingsKeys.kanaModeSwitcherTapAction: KanaModeSwitcherActionOption.symbols.rawValue,
        SettingsKeys.kanaModeSwitcherRightFlickAction: KanaModeSwitcherActionOption.kaomoji.rawValue,
        SettingsKeys.kanaModeSwitcherUpFlickAction: KanaModeSwitcherActionOption.emoji.rawValue,
        SettingsKeys.kanaPostModifierEmptyTapAction: KanaPostModifierEmptyTapActionOption.kaomoji.rawValue,
        SettingsKeys.kanaPostModifierEmptyTapKaomojiCategory: "shortcut",   // Raccourcis (ショートカット)
        SettingsKeys.kanaPostModifierEmptyTapEmojiCategory: "0",            // Personnes
        SettingsKeys.kanaPostModifierEmptyTapSymbolCategory: "0",           // Symboles de base
        SettingsKeys.kanaPostModifierFlickDakutenEnabled: false,
        SettingsKeys.numberThousandsSeparator: ThousandsSeparatorOption.comma.rawValue,
        SettingsKeys.numberGroupFourDigits: true,
        SettingsKeys.numberDecimalSeparator: DecimalSeparatorOption.dot.rawValue,
        SettingsKeys.numberUnitProductSeparator: UnitProductSeparatorOption.dotOperator.rawValue,
        SettingsKeys.numberLitreSymbol: LitreSymbolOption.small.rawValue,
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
        SettingsKeys.keyboardBackgroundTheme: KeyboardBackgroundThemeOption.sakura.rawValue,
        SettingsKeys.delimiterAutoCommitCandidate: DelimiterAutoCommitCandidateOption.one.rawValue,
        SettingsKeys.kanaKanjiCandidateSourceMode: KanaKanjiCandidateSourceModeOption.surface.rawValue,
        SettingsKeys.historicalKanaCandidatesEnabled: false,
        SettingsKeys.iterationMarkCandidatesEnabled: false,
        SettingsKeys.katakanaEmphasisCandidateMode: ScriptVariantModeOption.suppress.rawValue,
        SettingsKeys.mazegakiCandidateMode: ScriptVariantModeOption.suppress.rawValue,
        SettingsKeys.emojiCandidateDisplayEnabled: true,
        SettingsKeys.radicalStrokeCountStyle: "140:4,113:5,184:8",
        SettingsKeys.ordinalMeKanjiPreferred: false,
        SettingsKeys.adjectiveMeKanjiCandidatesEnabled: true,
        SettingsKeys.suspendMemorySlimmingEnabled: true,
        SettingsKeys.kaomojiCandidateDisplayEnabled: true,
        SettingsKeys.contactCandidateDisplayMode: ContactCandidateDisplayModeOption.namesOnly.rawValue,
        SettingsKeys.userDictionaryCandidateDisplayMode: UserDictionaryCandidateDisplayModeOption.on.rawValue
    ]

    // ──── ジェスチャー ────

    var logoPressAndDragGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.5)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.logoMenuCoordinateSpace)))
            .updating($logoMenuGesture) { value, state, _ in
                switch value {
                case .second(true, let drag):
                    // 長押し成立(0.5秒経過)。ドラッグ値が来るまでは位置なしで表示
                    state = drag.map { .dragging($0.location) } ?? .pressing
                default:
                    // .first(true) は押し始め(まだ長押し未成立)なので出さない
                    state = .inactive
                }
            }
            .onEnded { value in
                guard case .second(true, let drag?) = value,
                    let action = logoMenuAction(at: drag.location) else {
                    return
                }
                performLogoMenuAction(action)
            }
    }

    var logoMenuHighlightedAction: LogoMenuAction? {
        logoMenuGesture.location.flatMap(logoMenuAction(at:))
    }

    func logoMenuAction(at point: CGPoint) -> LogoMenuAction? {
        LogoMenuAction.allCases.first { logoMenuFrames[$0.rawValue]?.contains(point) == true }
    }

    // ──── メニュー表示 ────

    @ViewBuilder
    var logoMenuOverlay: some View {
        if logoMenuGesture.isActive {
            let logoFrame = logoMenuFrames[Self.logoMenuLogoFrameKey] ?? .zero
            ZStack(alignment: .top) {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                VStack(spacing: 0) {
                    ForEach(LogoMenuAction.allCases) { action in
                        logoMenuRow(action, isHighlighted: logoMenuHighlightedAction == action)
                    }
                }
                .frame(width: 300)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                // ロゴの直下(指がロゴにある状態から下へ滑らせる)。ロゴ枠が未取得なら上端に置く
                .padding(.top, max(logoFrame.maxY + 10, 0))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)   // 指はロゴ上のジェスチャーが追い続ける
            .transition(.opacity)
        }
    }

    private func logoMenuRow(_ action: LogoMenuAction, isHighlighted: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: action.systemImage)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(action.title)
                    .font(.body.weight(.semibold))
                Text(action.subtitle)
                    .font(.caption)
                    .foregroundStyle(isHighlighted ? Color.white.opacity(0.85) : Color.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(isHighlighted ? Color.white : Color.primary)
        .background(isHighlighted ? Color.accentColor : Color.clear)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: LogoMenuFramePreferenceKey.self,
                    value: [action.rawValue: proxy.frame(in: .named(Self.logoMenuCoordinateSpace))]
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
        case .about:
            logoMenuInfo = LogoMenuInfo(
                title: "écritu",
                message: "\(Self.editionNumberText)\n\(Self.aboutCopyrightText)"
            )
        case .strategicDefaults, .conservativeDefaults, .restoreStashedSettings:
            break
        }
    }

    // 確認ダイアログの本文。復元は退避した日時と édition を見せる
    func logoMenuConfirmationMessage(for action: LogoMenuAction) -> String {
        switch action {
        case .strategicDefaults:
            return "すべての設定を初期設定(標準)に戻します。語彙・学習内容はそのままです。"
        case .conservativeDefaults:
            return "すべての設定を作者の使用設定(3x3+わ・AZERTY・後置修飾・Apple 式フリック 等)にします。語彙・学習内容はそのままです。"
        case .restoreStashedSettings:
            if let stash = loadSettingsStash() {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "ja_JP")
                formatter.dateFormat = "yyyy-MM-dd HH:mm"
                return "\(formatter.string(from: stash.savedAt)) に退避した設定(édition n°\(stash.editionNumber))に戻します。現在の設定は失われます。"
            }
            return "退避した設定がありません。"
        case .copyYAML, .stashSettings, .about:
            return ""
        }
    }

    func confirmLogoMenuAction(_ action: LogoMenuAction) {
        switch action {
        case .strategicDefaults:
            applyStrategicDefaults()
            showSettingsToast("初期設定(標準)に戻しました")
        case .conservativeDefaults:
            applyConservativePreset()
            showSettingsToast("保守的初期設定にしました")
        case .restoreStashedSettings:
            if restoreStashedSettings() {
                showSettingsToast("退避した設定を復元しました")
            } else {
                logoMenuInfo = LogoMenuInfo(title: "復元できません", message: "退避した設定がありません。")
            }
        case .copyYAML, .stashSettings, .about:
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
        SettingsSyncNotification.postSettingsDidChange()
    }

    func applyConservativePreset() {
        guard let defaults = Self.sharedDefaults else { return }
        removeAllUserSettings()
        for (key, value) in Self.conservativePresetValues {
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
        let stash = SettingsStash(editionNumber: editionNumber, savedAt: Date(), values: values)
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
        SettingsSyncNotification.postSettingsDidChange()
        return true
    }

    // ──── トースト ────

    func showSettingsToast(_ message: String) {
        withAnimation(.easeOut(duration: 0.15)) {
            settingsToastMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeIn(duration: 0.3)) {
                if settingsToastMessage == message {
                    settingsToastMessage = nil
                }
            }
        }
    }
}
