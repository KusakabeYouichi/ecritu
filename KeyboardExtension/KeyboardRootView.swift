import Foundation
import SwiftUI
import UIKit

struct KeyboardRootView: View {
    let onTextInput: (String) -> Void
    let onDeleteBackward: () -> Void
    let onSpace: () -> Void
    let onReturn: () -> Void
    let onAdvanceKeyboard: () -> Void
    let onApplyKanaPostModifier: (KanaPostModifierButtonState, Bool) -> KanaPostModifierApplyOutcome
    let onToggleParenthesesWrapper: () -> Void
    let onSelectConversionCandidate: (Int) -> Void
    let onCommitComposingText: () -> Void
    let onCommitComposingTextAsKatakana: () -> Void
    let onUpgradeRecentKanaCommitToKatakana: () -> Bool
    let onInputModeChanged: (KeyboardInputMode) -> Void
    let showsNextKeyboardKey: Bool
    let directionProfile: FlickDirectionProfile
    let kanaLayoutMode: KanaLayoutMode
    let kanaModifierPlacementMode: KanaModifierPlacementMode
    let kanaPostModifierButtonState: KanaPostModifierButtonState
    let numberLayoutMode: NumberLayoutMode
    let latinLayoutMode: LatinLayoutMode
    let accentPaletteRawValue: String
    let isSystemDictionaryFallback: Bool
    let keyboardBackgroundThemeRawValue: String
    let basicSymbolOrderRawValue: String
    let temperatureUnitRawValue: String
    let spaceToastTrigger: Int
    let returnKeySystemImageName: String?
    let isReturnKeyEnabled: Bool
    let kanaFlickGuideDisplayMode: FlickGuideDisplayMode
    let latinFlickGuideDisplayMode: FlickGuideDisplayMode
    let numberFlickGuideDisplayMode: FlickGuideDisplayMode
    let modifierFlickGuideDisplayMode: FlickGuideDisplayMode
    let keyRepeatInitialDelay: TimeInterval
    let keyRepeatInterval: TimeInterval
    let kanaModeSwitcherTapActionRawValue: String
    let kanaModeSwitcherRightFlickActionRawValue: String
    let kanaModeSwitcherUpFlickActionRawValue: String
    let kanaPostModifierEmptyTapActionRawValue: String
    let kanaPostModifierEmptyTapKaomojiCategoryID: String
    let kanaPostModifierEmptyTapEmojiCategoryID: String
    let kanaPostModifierEmptyTapSymbolCategoryID: String
    let kanaPostModifierFlickDakutenEnabled: Bool
    let landscapeCandidateSideRawValue: String
    let landscapeNumberPaneSideRawValue: String
    let landscapeLatinSuggestionModeRawValue: String
    let shortcutVocabulary: [String]
    // 候補バー系の状態は ObservableObject 経由で受ける。候補だけが変わる打鍵では
    // rootView を差し替えず(=UIHostingController の同期 layoutIfNeeded も走らせず)、
    // モデルの publish だけで SwiftUI に再評価させるため。既存の消費箇所は
    // computed プロパティで無改修のまま互換にする。
    @ObservedObject var candidateBarModel: KeyboardCandidateBarModel
    var composingText: String { candidateBarModel.composingText }
    var conversionCandidates: [String] { candidateBarModel.conversionCandidates }
    var selectedConversionCandidateIndex: Int? { candidateBarModel.selectedConversionCandidateIndex }
    var latinSuggestionQuery: String { candidateBarModel.latinSuggestionQuery }
    var latinSuggestions: [String] { candidateBarModel.latinSuggestions }
    let showsParenthesesWrapper: Bool
    let initialSpaceToastText: String?

    @State var inputMode: KeyboardInputMode = .kana
    @State var diacriticMode: DiacriticMode = .none
    @State var kanaCharacterMode: KanaCharacterMode = .hiragana
    @State var activeLayerIndex: Int? = nil
    @State var spaceToastText: String? = nil
    @State var spaceToastOpacity: Double = 0
    @State var lastShownSpaceToastTrigger = -1
    @State var latinShiftState: LatinShiftState = .off
    @State private var lastLatinShiftTapAt: Date? = nil
    @State var isAwaitingLatinModeSwitchSecondTap = false
    @State var pendingLatinModeSwitchSecondTapResetWorkItem: DispatchWorkItem?
    @State var selectedEmojiCategory: EmojiCategory = .people
    @State var selectedSymbolCategory: SymbolCategory = .basic
    @State var selectedKaomojiCategoryID = "existing"
    @State var selectedKaomojiReadingPrefix: String? = nil
    @State var selectedKaomojiReading: String? = nil
    @State var emojiInputSubmode: EmojiInputSubmode = .emoji
    @State var returnToKanaAfterNextCommit: Bool = false
    @State var formattedNumberBuffer: String = ""
    @State var selectedFormattedNumberCategory: FormattedNumberCategory = .siBase
    @State var formattedNumberGroupingEnabled: Bool = true
    @State var didTriggerComposingCommitLongPress = false
    @State var katakanaCommitFeedbackText: String? = nil
    @State var pendingKatakanaCommitWorkItem: DispatchWorkItem?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let shiftDoubleTapThreshold: TimeInterval = 0.32
    let latinModeSwitchDoubleTapThreshold: TimeInterval = 0.28
    let katakanaCommitDoubleTapThreshold: TimeInterval = 0.2
    let katakanaCommitFeedbackDelay: TimeInterval = 0.14
    let keyLabelColor = KeyboardThemePalette.keyLabel
    private let candidateHeaderExpandedHeight: CGFloat = 35
    private let candidateHeaderContentDownshift: CGFloat = 4
    var keyboardRowSpacing: CGFloat { isLandscapeLayout ? 4 : 6 }
    private var keyboardTopPadding: CGFloat {
        if isLandscapeLayout
            && (inputMode == .kana || inputMode == .number || isLandscapeLatinThreeByThreeMode) {
            return 0
        }

        return isLandscapeLayout ? 1 : 3
    }
    private var keyboardHorizontalPadding: CGFloat { isLandscapeLayout ? 6 : 8 }
    private var keyboardBottomPadding: CGFloat { isLandscapeLayout ? 4 : 20 }
    let candidateStateFontSize: CGFloat = 15
    let candidateTextFontSize: CGFloat = 16
    var compactActionKeyHeight: CGFloat { isLandscapeLayout ? 34 : 42 }
    private let compactModeSwitchKeyWidth: CGFloat = 32
    private let wideModeSwitchKeyWidth: CGFloat = 58
    let compactEmojiKeyHeight: CGFloat = 28
    let compactKaomojiKeyHeight: CGFloat = 30
    let emojiGridSpacing: CGFloat = 2
    let kaomojiMaxColumns = 5
    let kaomojiMinKeyWidth: CGFloat = 52
    let kaomojiHorizontalPadding: CGFloat = 8
    let kaomojiFontSize: CGFloat = 18
    let kaomojiMinInterItemSpacingMultiplier: CGFloat = 1.2
    let kaomojiCategoryButtonWidth: CGFloat = 40
    let kaomojiSearchReadingDisplayLimit = 120

    var showsKanaConversionCandidates: Bool {
        inputMode == .kana && (!composingText.isEmpty || showsParenthesesWrapper)
    }

    var isLandscapeLayout: Bool {
        verticalSizeClass == .compact
    }

    var showsLatinSuggestionCandidates: Bool {
        inputMode == .latin && !latinSuggestionQuery.isEmpty
    }

    var needsQwertyMiddleRowApostrophe: Bool {
        latinLayoutMode == .qwerty
    }

    var usesPortraitLatinInlineDeleteLayout: Bool {
        !isLandscapeLayout
            && inputMode == .latin
            && (latinLayoutMode == .qwerty || latinLayoutMode == .azerty)
    }

    private var portraitLatinQwertyBottomRowSlackWidth: CGFloat {
        guard usesPortraitLatinInlineDeleteLayout,
            latinLayoutMode == .qwerty else {
            return 0
        }

        let estimatedKeyboardWidth = max(
            1,
            UIScreen.main.bounds.width - keyboardHorizontalPadding * 2
        )
        let leadingControlWidth: CGFloat = showsCompactLeftModeSwitchButtons
            ? (leftModeSwitchButtonWidth + keyboardRowSpacing)
            : 0
        let letterAreaWidth = max(1, estimatedKeyboardWidth - leadingControlWidth)
        let topRowLetterCount = CGFloat(max(rows.first?.count ?? 10, 1))
        let topRowLetterSpacingCount = CGFloat(max(Int(topRowLetterCount) - 1, 0))
        let topRowLetterWidth = max(
            1,
            (letterAreaWidth - keyboardRowSpacing * topRowLetterSpacingCount) / topRowLetterCount
        )

        // Width budget previously expressed as trailing inset; now redistributed to Shift/Delete.
        let trailingPitchFactor: CGFloat = 0.75
        return (topRowLetterWidth + keyboardRowSpacing) * trailingPitchFactor
    }

    func portraitQwertyBottomRowKeyMetrics(rowIndex: Int) -> (letter: CGFloat, edge: CGFloat)? {
        guard usesPortraitLatinInlineDeleteLayout,
            latinLayoutMode == .qwerty,
            rowIndex == 2 else {
            return nil
        }

        let estimatedKeyboardWidth = max(
            1,
            UIScreen.main.bounds.width - keyboardHorizontalPadding * 2
        )
        let leadingControlWidth: CGFloat = showsCompactLeftModeSwitchButtons
            ? (leftModeSwitchButtonWidth + keyboardRowSpacing)
            : 0
        let availableRowWidth = max(1, estimatedKeyboardWidth - leadingControlWidth)
        let spacingCount: CGFloat = 8
        let keyCount: CGFloat = 9
        let letterKeyWidth = max(
            1,
            (availableRowWidth
                - portraitLatinQwertyBottomRowSlackWidth
                - keyboardRowSpacing * spacingCount) / keyCount
        )
        let edgeKeyWidth = letterKeyWidth + portraitLatinQwertyBottomRowSlackWidth / 2

        return (letter: letterKeyWidth, edge: edgeKeyWidth)
    }

    func shouldReplacePortraitAzertyRightShiftWithDelete(
        rowIndex: Int,
        kana: FlickKanaSet
    ) -> Bool {
        usesPortraitLatinInlineDeleteLayout
            && latinLayoutMode == .azerty
            && rowIndex == 2
            && isLandscapeLatinRightShiftKey(kana)
    }

    // clavier 縦画面では行3 (rowIndex == 2) の右 shift トークンを delete に差し替える
    // (AZERTY portrait の挙動と同じ)。
    var usesPortraitClavierInlineDeleteLayout: Bool {
        !isLandscapeLayout
            && inputMode == .number
            && effectiveNumberLayoutMode == .clavier
    }

    func shouldReplacePortraitClavierRightShiftWithDelete(
        rowIndex: Int,
        kana: FlickKanaSet
    ) -> Bool {
        usesPortraitClavierInlineDeleteLayout
            && rowIndex == 2
            && isLandscapeLatinRightShiftKey(kana)
    }

    func shouldAppendPortraitQwertyDeleteKey(rowIndex: Int) -> Bool {
        usesPortraitLatinInlineDeleteLayout
            && latinLayoutMode == .qwerty
            && rowIndex == 2
    }

    var portraitLatinDeleteReplacementSymbol: String {
        "@"
    }

    private var latinSpaceRightActionSymbols: [String] {
        if isLandscapeLayout,
            latinLayoutMode == .qwerty || latinLayoutMode == .azerty {
            return [".", "-"]
        }

        if !isLandscapeLayout,
            latinLayoutMode == .qwerty || latinLayoutMode == .azerty {
            return [".", "-"]
        }

        return ["!", "?", "@", "&", "/"]
    }

    private var latinSpaceLeftActionSymbols: [String] {
        if isLandscapeLayout,
            latinLayoutMode == .qwerty || latinLayoutMode == .azerty {
            return ["@", "_"]
        }

        if !isLandscapeLayout,
            latinLayoutMode == .qwerty || latinLayoutMode == .azerty {
            return ["/"]
        }

        return [":", "_", "(", ")"]
    }

    @ViewBuilder
    private func latinActionButtons(
        symbols: [String],
        fixedWidth: CGFloat? = nil,
        keyHeight: CGFloat? = nil
    ) -> some View {
        let resolvedKeyHeight = keyHeight ?? compactActionKeyHeight

        ForEach(symbols, id: \.self) { symbol in
            ActionKeyButton(
                title: symbol,
                fontSize: 20,
                fixedWidth: fixedWidth,
                action: { commitText(symbol) }
            )
                .frame(height: resolvedKeyHeight)
        }
    }

    @ViewBuilder
    func latinSpaceLeftActionButtons(
        fixedWidth: CGFloat? = nil,
        keyHeight: CGFloat? = nil
    ) -> some View {
        latinActionButtons(
            symbols: latinSpaceLeftActionSymbols,
            fixedWidth: fixedWidth,
            keyHeight: keyHeight
        )
    }

    @ViewBuilder
    func latinSpaceRightActionButtons(
        fixedWidth: CGFloat? = nil,
        keyHeight: CGFloat? = nil
    ) -> some View {
        latinActionButtons(
            symbols: latinSpaceRightActionSymbols,
            fixedWidth: fixedWidth,
            keyHeight: keyHeight
        )
    }

    private var landscapeEmojiHeaderHeight: CGFloat { 26 }

    var emojiHeaderTopPadding: CGFloat { isLandscapeLayout ? 8 : 13 }

    var candidateHeaderHeight: CGFloat {
        if isLandscapeLayout {
            if inputMode == .emoji {
                return landscapeEmojiHeaderHeight
            }

            return 0
        }

        // 候補表示時の押し下げをなくすため、テキスト系モードでも常に同じヘッダー領域を予約する。
        return candidateHeaderExpandedHeight
    }

    private var isActiveConversion: Bool {
        selectedConversionCandidateIndex != nil
    }

    // VoiceOver 用の状態名(表示はアイコンのミニカプセルに置き換え済み)。
    var conversionStateLabel: String {
        isActiveConversion ? "変換中" : "未確定"
    }

    // 状態はテキストラベルでなく SF Symbols のミニカプセルで示す(候補エリアの節約)。
    // 鉛筆=未確定(編集中)、循環矢印=変換中(スペース送り)。
    var conversionStateIconName: String {
        isActiveConversion ? "arrow.triangle.2.circlepath" : "pencil"
    }

    var conversionStateColor: Color {
        isActiveConversion ? accentColor : Color.orange
    }

    private var isSpaceActsAsConversionKey: Bool {
        inputMode == .kana && !composingText.isEmpty
    }

    var spaceKeyDisplayTitle: String {
        if isSpaceActsAsConversionKey {
            return "変換"
        }

        if inputMode == .kana {
            return spaceToastText ?? ""
        }

        return ""
    }

    var spaceKeyDisplayOpacity: Double {
        if isSpaceActsAsConversionKey {
            return 1
        }

        return inputMode == .kana ? spaceToastOpacity : 0
    }

    var spaceKeyAccessibilityLabel: String {
        isSpaceActsAsConversionKey ? "変換" : "空白"
    }

    var isReturnActsAsCommitKey: Bool {
        inputMode == .kana && !composingText.isEmpty
    }

    var returnActionKeyTitle: String {
        if isReturnActsAsCommitKey {
            return "確定"
        }

        return returnKeySystemImageName == nil ? "⏎" : ""
    }

    var returnActionKeySystemImageName: String? {
        isReturnActsAsCommitKey ? nil : returnKeySystemImageName
    }

    var returnActionKeyAccessibilityLabel: String {
        if isReturnActsAsCommitKey {
            return "確定"
        }

        return returnKeySystemImageName == nil ? "改行" : "検索"
    }

    var returnKeyKatakanaDoubleTapAction: (() -> Void)? {
        isReturnActsAsCommitKey ? handleReturnKeyKatakanaDoubleTap : nil
    }

    var returnKeyKatakanaLongPressAction: (() -> Void)? {
        isReturnActsAsCommitKey ? handleReturnKeyKatakanaLongPress : nil
    }

    var canTapComposingTextToCommit: Bool {
        !composingText.isEmpty
    }

    private var accentPalette: AccentPalette {
        AccentPalette(rawValue: accentPaletteRawValue) ?? .emeraude
    }

    var accentColor: Color {
        if isSystemDictionaryFallback {
            return Color(uiColor: .systemGray)
        }

        return accentPalette.color
    }

    var basicSymbolOrder: BasicSymbolOrder {
        BasicSymbolOrder(rawValue: basicSymbolOrderRawValue) ?? .ascii
    }

    var temperatureUnit: TemperatureUnitPreference {
        TemperatureUnitPreference(rawValue: temperatureUnitRawValue) ?? .celsius
    }

    var currentFlickGuideDisplayMode: FlickGuideDisplayMode {
        switch inputMode {
        case .kana:
            return kanaFlickGuideDisplayMode
        case .latin:
            guard latinLayoutMode == .flick else {
                return .off
            }
            return latinFlickGuideDisplayMode
        case .number:
            // clavier はフリック方向を持たない単純キーなので、フリックガイドは常に off
            // (これにより中央ラベルの上方オフセットがかからず、文字が中央表示になる)
            if effectiveNumberLayoutMode == .clavier {
                return .off
            }
            return numberFlickGuideDisplayMode
        case .emoji:
            return .off
        case .formattedNumber:
            return .off
        }
    }

    var showsFlickGuideCharacters: Bool {
        currentFlickGuideDisplayMode == .fourDirections
    }

    var showsModifierFlickGuideCharacters: Bool {
        modifierFlickGuideDisplayMode == .fourDirections
    }

    var isCurrentFlickGuideDisplayOff: Bool {
        currentFlickGuideDisplayMode == .off
    }

    var isModifierFlickGuideDisplayOff: Bool {
        modifierFlickGuideDisplayMode == .off
    }

    private var keyboardBackgroundTheme: KeyboardBackgroundTheme {
        KeyboardBackgroundTheme(rawValue: keyboardBackgroundThemeRawValue) ?? .bleu
    }

    private var keyboardBackgroundGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(stops: keyboardBackgroundTheme.gradientStops(for: colorScheme)),
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var transitionState: KeyboardModeTransitionState {
        get {
            KeyboardModeTransitionState(
                inputMode: inputMode,
                diacriticMode: diacriticMode,
                kanaCharacterMode: kanaCharacterMode,
                latinShiftState: latinShiftState,
                lastLatinShiftTapAt: lastLatinShiftTapAt,
                emojiInputSubmode: emojiInputSubmode,
                spaceToastText: spaceToastText,
                spaceToastOpacity: spaceToastOpacity
            )
        }
        nonmutating set {
            inputMode = newValue.inputMode
            diacriticMode = newValue.diacriticMode
            kanaCharacterMode = newValue.kanaCharacterMode
            latinShiftState = newValue.latinShiftState
            lastLatinShiftTapAt = newValue.lastLatinShiftTapAt
            emojiInputSubmode = newValue.emojiInputSubmode
            spaceToastText = newValue.spaceToastText
            spaceToastOpacity = newValue.spaceToastOpacity
        }
    }

    var activeKanaModifierMode: DiacriticMode {
        kanaModifierPlacementMode == .prefix ? diacriticMode : .none
    }

    var isPrefixModifierActive: Bool {
        inputMode == .kana && kanaModifierPlacementMode == .prefix && diacriticMode != .none
    }

    var rows: [[FlickKanaSet]] {
        switch inputMode {
        case .kana:
            return FlickKanaLayout.rows(for: activeKanaModifierMode, layoutMode: kanaLayoutMode).map { row in
                row.map {
                    displayedKanaForKanaCharacterModeIfNeeded($0.remapped(for: directionProfile))
                }
            }
        case .number:
            return FlickKanaLayout.numberRows(
                for: directionProfile,
                layoutMode: effectiveNumberLayoutMode,
                temperatureUnit: temperatureUnit,
                isShifted: latinShiftState != .off
            )
        case .latin:
            return FlickKanaLayout.latinRows(for: directionProfile, layoutMode: latinLayoutMode)
        case .emoji:
            return []
        case .formattedNumber:
            // 独自テンキーを formattedNumberKeyboardView で構築するため FlickKanaSet 行は不要。
            return []
        }
    }

    var isKanaThreeByThreeMode: Bool {
        inputMode == .kana && kanaLayoutMode == .threeByThreePlusWa
    }

    var isKanaFiveByTwoMode: Bool {
        inputMode == .kana && kanaLayoutMode == .fiveByTwo
    }

    var kanaCandidateHeaderTopPadding: CGFloat {
        (isKanaThreeByThreeMode ? 6 : 4) + candidateHeaderContentDownshift
    }

    var usesThreeByThreeGridForNumberOrLatin: Bool {
        (inputMode == .number || inputMode == .latin)
            && rows.count == 4
            && rows.allSatisfy { $0.count == 3 }
    }

    private var kanaFiveByTwoSideInset: CGFloat {
        isKanaFiveByTwoMode ? 6 : 0
    }

    func horizontalInsetsForMainRow(_ rowIndex: Int) -> EdgeInsets {
        guard isKanaFiveByTwoMode else {
            return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        }

        // Keep total horizontal inset the same, but move the top two rows left.
        if rowIndex < 2 {
            return EdgeInsets(
                top: 0,
                leading: 0,
                bottom: 0,
                trailing: kanaFiveByTwoSideInset * 2
            )
        }

        return EdgeInsets(
            top: 0,
            leading: kanaFiveByTwoSideInset,
            bottom: 0,
            trailing: kanaFiveByTwoSideInset
        )
    }

    let punctuationKana = FlickKanaSet(
        label: "、",
        center: "、",
        up: "?",
        right: "!",
        down: "・",
        left: "。"
    )

    var kanaModeSwitcherTapAction: KanaModeSwitcherAction {
        KanaModeSwitcherAction(rawValue: kanaModeSwitcherTapActionRawValue) ?? .emoji
    }

    var kanaModeSwitcherRightFlickAction: KanaModeSwitcherAction {
        KanaModeSwitcherAction(rawValue: kanaModeSwitcherRightFlickActionRawValue) ?? .kaomoji
    }

    var kanaModeSwitcherUpFlickAction: KanaModeSwitcherAction {
        KanaModeSwitcherAction(rawValue: kanaModeSwitcherUpFlickActionRawValue) ?? .symbols
    }

    var kanaModeSwitcherKana: FlickKanaSet {
        FlickKanaSet(
            label: kanaModeSwitcherTapAction.keyLabel,
            center: kanaModeSwitcherTapAction.keyLabel,
            up: kanaModeSwitcherUpFlickAction.keyLabel,
            right: kanaModeSwitcherRightFlickAction.keyLabel,
            down: "",
            left: "",
            usesProfileDependentGuideOrder: false
        )
    }

    var compactKeyboardSwitchKana: FlickKanaSet {
        FlickKanaSet(
            label: "🌐",
            center: "🌐",
            up: kanaModeSwitcherUpFlickAction.keyLabel,
            right: kanaModeSwitcherRightFlickAction.keyLabel,
            down: "",
            left: "",
            usesProfileDependentGuideOrder: false
        )
    }

    var modifierSelectorKey: FlickKanaSet {
        let modeSwitchText = inputMode == .kana ? kanaCharacterMode.toggleGuide : "123"

        if inputMode == .kana && kanaModifierPlacementMode == .postfix {
            let postfixFlickUp = kanaPostModifierFlickDakutenEnabled ? "゛" : ""
            let postfixFlickRight = kanaPostModifierFlickDakutenEnabled ? "゜" : ""
            switch kanaPostModifierButtonState {
            case .kaomoji:
                return makeModifierSelectorKey(
                    label: "^_^",
                    up: "",
                    right: "",
                    modeSwitchText: modeSwitchText
                )
            case .smallKana:
                return makeModifierSelectorKey(
                    label: "小",
                    up: postfixFlickUp,
                    right: postfixFlickRight,
                    modeSwitchText: modeSwitchText
                )
            case .dakuten:
                return makeModifierSelectorKey(
                    label: "゛",
                    up: postfixFlickUp,
                    right: postfixFlickRight,
                    modeSwitchText: modeSwitchText
                )
            case .handakuten:
                return makeModifierSelectorKey(
                    label: "゜",
                    up: postfixFlickUp,
                    right: postfixFlickRight,
                    modeSwitchText: modeSwitchText
                )
            }
        }

        return makeModifierSelectorKey(
            label: "小",
            up: "゛",
            right: "゜",
            modeSwitchText: modeSwitchText
        )
    }

    var shortcutVocabularyEntries: [String] {
        var seen = Set<String>()
        var result: [String] = []

        for candidate in shortcutVocabulary {
            let normalized = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !normalized.isEmpty,
                seen.insert(normalized).inserted else {
                continue
            }

            result.append(candidate)
        }

        return result
    }

    var mainFlickKeyHeight: CGFloat {
        isLandscapeLayout ? 40 : 46
    }

    var fourRowAlignedClusterHeight: CGFloat {
        mainFlickKeyHeight * 4 + keyboardRowSpacing * 3
    }

    var fourRowAlignedTopContentHeight: CGFloat {
        fourRowAlignedClusterHeight - mainFlickKeyHeight - keyboardRowSpacing
    }

    var numberThreeByThreeDirectionalHintScale: CGFloat {
        isLandscapeLayout ? 0.82 : 1
    }

    private var shorterScreenEdge: CGFloat {
        min(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
    }

    var usesCompactKanaFiveByTwoBottomActionRow: Bool {
        !isLandscapeLayout
            && isKanaFiveByTwoMode
            && showsNextKeyboardKey
            && shorterScreenEdge <= 390
    }

    var bottomActionRowGlobeKeyWidth: CGFloat {
        usesCompactKanaFiveByTwoBottomActionRow ? 44 : 54
    }

    var bottomActionRowDeleteKeyWidth: CGFloat {
        usesCompactKanaFiveByTwoBottomActionRow ? 56 : 64
    }

    var bottomActionRowKanaTrailingKeyWidth: CGFloat {
        usesCompactKanaFiveByTwoBottomActionRow ? selectorKeySize : kanaFiveByTwoTrailingKeyWidth
    }

    var bottomActionRowReturnKeyWidth: CGFloat {
        usesCompactKanaFiveByTwoBottomActionRow ? 64 : 72
    }

    private var portraitLatinInlineActionBaseKeyWidth: CGFloat {
        guard usesPortraitLatinInlineDeleteLayout || usesPortraitClavierInlineDeleteLayout else {
            return 0
        }

        let estimatedKeyboardWidth = max(
            1,
            UIScreen.main.bounds.width - keyboardHorizontalPadding * 2
        )
        let leadingControlWidth: CGFloat = shouldShowCompactLeftModeSwitchInBottomActionRow
            ? leftModeSwitchButtonWidth
            : 0
        let globeKeyWidth: CGFloat = showsNextKeyboardKey
            ? bottomActionRowGlobeKeyWidth
            : 0
        let fixedWidthTotal = leadingControlWidth + globeKeyWidth + bottomActionRowReturnKeyWidth
        let spacingCount = CGFloat(5
            + (shouldShowCompactLeftModeSwitchInBottomActionRow ? 1 : 0)
            + (showsNextKeyboardKey ? 1 : 0))
        let flexibleKeyCount: CGFloat = 5

        return max(
            1,
            (estimatedKeyboardWidth - fixedWidthTotal - keyboardRowSpacing * spacingCount)
                / flexibleKeyCount
        )
    }

    var portraitLatinInlineActionSymbolKeyWidth: CGFloat {
        max(1, portraitLatinInlineActionBaseKeyWidth - 3)
    }

    var portraitLatinInlineReturnKeyWidth: CGFloat {
        66
    }

    var numberDownDirectionalHintScale: CGFloat {
        1.12
    }

    var numberDownDirectionalHintVerticalOffsetAdjustment: CGFloat {
        -2
    }

    var modifierDirectionalFlickThreshold: CGFloat {
        if inputMode == .kana && kanaModifierPlacementMode == .postfix {
            // Postfix modifier misfires are expensive (e.g. つ -> づ), so require larger movement.
            return 26
        }

        return 18
    }

    var modifierDirectionalCommitThreshold: CGFloat? {
        if inputMode == .kana && kanaModifierPlacementMode == .postfix {
            // Prefer center on postfix modifier unless movement is clearly directional.
            return 32
        }

        return nil
    }

    var selectorKeySize: CGFloat {
        mainFlickKeyHeight
    }

    var kanaFiveByTwoTrailingKeyWidth: CGFloat {
        if isKanaFiveByTwoMode {
            return selectorKeySize + 8
        }

        return selectorKeySize
    }

    var actionRowTopSpacing: CGFloat {
        inputMode == .kana ? 0 : 8
    }

    var shouldShowCompactLeftModeSwitchInBottomActionRow: Bool {
        showsCompactLeftModeSwitchButtons
            && rows.count <= 3
            && !usesCompactKanaFiveByTwoBottomActionRow
    }

    var showsCompactLeftModeSwitchButtons: Bool {
        if inputMode == .kana {
            return isKanaFiveByTwoMode
        }

        if inputMode == .latin {
            return latinLayoutMode == .qwerty || latinLayoutMode == .azerty
        }

        if inputMode == .number {
            return effectiveNumberLayoutMode == .clavier
        }

        return false
    }

    // clavier 配列は縦画面専用。横画面の場合は calculette にフォールバックする。
    var effectiveNumberLayoutMode: NumberLayoutMode {
        if numberLayoutMode == .clavier && isLandscapeLayout {
            return .calculette
        }
        return numberLayoutMode
    }

    // メインキー(letter / number / kana)の中央ラベルのフォントウエイト。
    // AZERTY/QWERTY の英字キー、および clavier 配列の数字・記号キーは semibold、
    // それ以外(かなフリック、calculette/telephone)は従来通り bold。
    var rowKeyMainLabelFontWeight: Font.Weight {
        if inputMode == .latin && (latinLayoutMode == .qwerty || latinLayoutMode == .azerty) {
            return .semibold
        }
        if inputMode == .number && effectiveNumberLayoutMode == .clavier {
            return .semibold
        }
        return .bold
    }

    // clavier 配列はメイン letter キーも system 行の inline 記号キーも 26pt に統一する。
    var clavierKeyFontSize: CGFloat { 26 }

    // clavier system 行に並べる 4 つの記号(shift 状態で切替)。
    // 配置順: index 0 = delete 跡(AZERTY の `@` 位置)、index 1 = space-left(`/`)、
    //         index 2/3 = space-right(`.`/`-`)。
    private var clavierSystemRowSymbols: [String] {
        if latinShiftState != .off {
            return ["・", "〜", "…", "±"]
        }
        return ["@", "/", ".", "-"]
    }

    func clavierInlineSymbol(at index: Int) -> String {
        let symbols = clavierSystemRowSymbols
        guard symbols.indices.contains(index) else {
            return ""
        }
        return symbols[index]
    }

    var usesWideLeftModeSwitchButtons: Bool {
        if isLandscapeLayout {
            return true
        }

        // 数字配列が clavier の場合は(他モードのときも含めて)左モード切替列を幅狭で
        // 統一する(AZERTY/QWERTY のとき幅狭にしているのと同じ理由 = clavier モード時に
        // 行幅を最大化したい)。
        if numberLayoutMode == .clavier {
            return false
        }

        return kanaLayoutMode == .threeByThreePlusWa && latinLayoutMode == .flick
    }

    var leftModeSwitchButtonWidth: CGFloat {
        usesWideLeftModeSwitchButtons ? wideModeSwitchKeyWidth : compactModeSwitchKeyWidth
    }

    var rightEdgeUtilityColumnWidth: CGFloat {
        let mirroredUtilityColumnWidth = wideModeSwitchKeyWidth * 2 - leftModeSwitchButtonWidth
        return max(wideModeSwitchKeyWidth, mirroredUtilityColumnWidth)
    }

    var kanaModeSwitchButtonTitle: String {
        usesWideLeftModeSwitchButtons ? "あいう" : "あい"
    }

    func kanaModeSwitcherAction(for direction: FlickDirection) -> KanaModeSwitcherAction? {
        switch direction {
        case .droite:
            return kanaModeSwitcherRightFlickAction
        case .haut:
            return kanaModeSwitcherUpFlickAction
        default:
            return nil
        }
    }

    var kanaModeSwitcherPreviewHorizontalPadding: CGFloat {
        if !usesWideLeftModeSwitchButtons {
            return 3
        }

        return 8
    }

    private let kaomojiModeReturnIconFontSize: CGFloat = 32

    var kanaFiveByTwoTopNumberKeys: [String] {
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    }

    var landscapeEmptyCandidatePlaceholderCount: Int { 6 }

    let landscapeLatinTypewriterMiddleRowOffsetFactor: CGFloat = 0.25
    let landscapeLatinTypewriterBottomRowOffsetFromMiddleFactor: CGFloat = 0.5

    @ViewBuilder
    func inlineLatinDeleteKey(fixedWidth: CGFloat? = nil) -> some View {
        let deleteKey = ActionKeyButton(
            title: "⌫",
            accessibilityLabel: "削除",
            fontSize: 26,
            repeatsWhileHolding: true,
            repeatInitialDelay: keyRepeatInitialDelay,
            repeatInterval: keyRepeatInterval,
            action: onDeleteBackward
        )

        if let fixedWidth {
            deleteKey
                .frame(width: fixedWidth, height: mainFlickKeyHeight)
        } else {
            deleteKey
                .frame(maxWidth: .infinity)
                .frame(height: mainFlickKeyHeight)
        }
    }

    var body: some View {
        ZStack {
            keyboardBackgroundGradient
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea()

            VStack(spacing: keyboardRowSpacing) {
                if usesLandscapeKanaCandidateSidebar {
                    HStack(spacing: keyboardRowSpacing) {
                        landscapeKanaFixedModeSwitchColumn
                            .frame(width: leftModeSwitchButtonWidth)
                            .frame(height: landscapeKanaReferenceClusterHeight, alignment: .top)

                        if landscapeKanaCandidateSide == .left {
                            landscapeKanaCandidateSidebar
                                .frame(width: landscapeCandidateSidebarWidth())
                                .frame(height: landscapeKanaReferenceClusterHeight, alignment: .top)

                            landscapeKanaSwappableMainCluster
                                .frame(maxWidth: .infinity)
                                .frame(height: landscapeKanaReferenceClusterHeight, alignment: .top)
                        } else {
                            landscapeKanaSwappableMainCluster
                                .frame(maxWidth: .infinity)
                                .frame(height: landscapeKanaReferenceClusterHeight, alignment: .top)

                            landscapeKanaCandidateSidebar
                                .frame(width: landscapeCandidateSidebarWidth())
                                .frame(height: landscapeKanaReferenceClusterHeight, alignment: .top)
                        }
                    }
                    .padding(.top, isKanaFiveByTwoMode ? keyboardRowSpacing + 1 : 0)
                } else if usesLandscapeLatinSuggestionSidebar {
                    HStack(spacing: keyboardRowSpacing) {
                        landscapeLatinModeSwitchColumn
                            .frame(width: leftModeSwitchButtonWidth)
                            .frame(height: landscapeLatinReferenceClusterHeight, alignment: .top)

                        if landscapeKanaCandidateSide == .left {
                            landscapeLatinSuggestionSidebar
                                .frame(width: landscapeCandidateSidebarWidth())
                                .frame(height: landscapeLatinReferenceClusterHeight, alignment: .top)

                            landscapeLatinSwappableMainCluster
                                .frame(maxWidth: .infinity)
                                .frame(height: landscapeLatinReferenceClusterHeight, alignment: .top)
                        } else {
                            landscapeLatinSwappableMainCluster
                                .frame(maxWidth: .infinity)
                                .frame(height: landscapeLatinReferenceClusterHeight, alignment: .top)

                            landscapeLatinSuggestionSidebar
                                .frame(width: landscapeCandidateSidebarWidth())
                                .frame(height: landscapeLatinReferenceClusterHeight, alignment: .top)
                        }
                    }
                } else {
                    topHeaderView
                    keyboardMainContent
                }
            }
            .padding(.top, keyboardTopPadding)
            .padding(.horizontal, keyboardHorizontalPadding)
            .padding(.bottom, keyboardBottomPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onAppear {
            onInputModeChanged(inputMode)
            showInitialSpaceToastIfNeeded()
        }
        .onChange(of: inputMode) { mode in
            onInputModeChanged(mode)
        }
        .onChange(of: spaceToastTrigger) { _ in
            showInitialSpaceToastIfNeeded()
        }
        .onDisappear {
            didTriggerComposingCommitLongPress = false
            cancelPendingKatakanaCommit()
            cancelLatinModeSwitchSecondTapWindow()
        }
        .environment(\.flickDirectionProfile, directionProfile)
        .environment(\.flickGuideDisplayMode, currentFlickGuideDisplayMode)
        .environment(\.keyboardAccentColor, accentColor)
    }

}

#Preview {
    KeyboardRootView(
        onTextInput: { _ in },
        onDeleteBackward: {},
        onSpace: {},
        onReturn: {},
        onAdvanceKeyboard: {},
        onApplyKanaPostModifier: { _, _ in .ignored },
        onToggleParenthesesWrapper: {},
        onSelectConversionCandidate: { _ in },
        onCommitComposingText: {},
        onCommitComposingTextAsKatakana: {},
        onUpgradeRecentKanaCommitToKatakana: { false },
        onInputModeChanged: { _ in },
        showsNextKeyboardKey: true,
        directionProfile: .ecritu,
        kanaLayoutMode: .fiveByTwo,
        kanaModifierPlacementMode: .prefix,
        kanaPostModifierButtonState: .kaomoji,
        numberLayoutMode: .calculette,
        latinLayoutMode: .flick,
        accentPaletteRawValue: "emeraude",
        isSystemDictionaryFallback: false,
        keyboardBackgroundThemeRawValue: "bleu",
        basicSymbolOrderRawValue: "ascii",
        temperatureUnitRawValue: TemperatureUnitPreference.celsius.rawValue,
        spaceToastTrigger: 1,
        returnKeySystemImageName: nil,
        isReturnKeyEnabled: true,
        kanaFlickGuideDisplayMode: .fourDirections,
        latinFlickGuideDisplayMode: .fourDirections,
        numberFlickGuideDisplayMode: .fourDirections,
        modifierFlickGuideDisplayMode: .fourDirections,
        keyRepeatInitialDelay: 0.5,
        keyRepeatInterval: 0.1,
                kanaModeSwitcherTapActionRawValue: "emoji",
                kanaModeSwitcherRightFlickActionRawValue: "kaomoji",
                kanaModeSwitcherUpFlickActionRawValue: "symbols",
                kanaPostModifierEmptyTapActionRawValue: "kaomoji",
                kanaPostModifierEmptyTapKaomojiCategoryID: "existing",
                kanaPostModifierEmptyTapEmojiCategoryID: "0",
                kanaPostModifierEmptyTapSymbolCategoryID: "0",
                kanaPostModifierFlickDakutenEnabled: true,
                landscapeCandidateSideRawValue: "left",
            landscapeNumberPaneSideRawValue: "left",
        landscapeLatinSuggestionModeRawValue: "sidebar",
        shortcutVocabulary: [],
        candidateBarModel: {
            let model = KeyboardCandidateBarModel()
            model.composingText = "かな"
            model.conversionCandidates = ["仮名", "かな"]
            model.selectedConversionCandidateIndex = 0
            model.latinSuggestionQuery = "caf"
            model.latinSuggestions = ["cafe", "café"]
            return model
        }(),
        showsParenthesesWrapper: false,
        initialSpaceToastText: nil
    )
}
