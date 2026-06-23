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
    let composingText: String
    let conversionCandidates: [String]
    let selectedConversionCandidateIndex: Int?
    let latinSuggestionQuery: String
    let latinSuggestions: [String]
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

    private var showsKanaConversionCandidates: Bool {
        inputMode == .kana && (!composingText.isEmpty || showsParenthesesWrapper)
    }

    var isLandscapeLayout: Bool {
        verticalSizeClass == .compact
    }

    private var showsLatinSuggestionCandidates: Bool {
        inputMode == .latin && !latinSuggestionQuery.isEmpty
    }

    var needsQwertyMiddleRowApostrophe: Bool {
        latinLayoutMode == .qwerty
    }

    private var usesPortraitLatinInlineDeleteLayout: Bool {
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

    private func portraitQwertyBottomRowKeyMetrics(rowIndex: Int) -> (letter: CGFloat, edge: CGFloat)? {
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

    private func shouldReplacePortraitAzertyRightShiftWithDelete(
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
    private var usesPortraitClavierInlineDeleteLayout: Bool {
        !isLandscapeLayout
            && inputMode == .number
            && effectiveNumberLayoutMode == .clavier
    }

    private func shouldReplacePortraitClavierRightShiftWithDelete(
        rowIndex: Int,
        kana: FlickKanaSet
    ) -> Bool {
        usesPortraitClavierInlineDeleteLayout
            && rowIndex == 2
            && isLandscapeLatinRightShiftKey(kana)
    }

    private func shouldAppendPortraitQwertyDeleteKey(rowIndex: Int) -> Bool {
        usesPortraitLatinInlineDeleteLayout
            && latinLayoutMode == .qwerty
            && rowIndex == 2
    }

    private var portraitLatinDeleteReplacementSymbol: String {
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

    private var emojiHeaderTopPadding: CGFloat { isLandscapeLayout ? 8 : 13 }

    private var candidateHeaderHeight: CGFloat {
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

    var conversionStateLabel: String {
        isActiveConversion ? "変換中" : "未確定"
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

    private var activeKanaModifierMode: DiacriticMode {
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
        }
    }

    var isKanaThreeByThreeMode: Bool {
        inputMode == .kana && kanaLayoutMode == .threeByThreePlusWa
    }

    var isKanaFiveByTwoMode: Bool {
        inputMode == .kana && kanaLayoutMode == .fiveByTwo
    }

    private var kanaCandidateHeaderTopPadding: CGFloat {
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

    private var threeByThreeWaKana: FlickKanaSet {
        displayedKanaForKanaCharacterModeIfNeeded(
            FlickKanaLayout.waSet(for: activeKanaModifierMode).remapped(for: directionProfile)
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

    private var kanaModeSwitcherKana: FlickKanaSet {
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

    private var compactKeyboardSwitchKana: FlickKanaSet {
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

    private func makeModifierSelectorKey(
        label: String,
        up: String,
        right: String,
        modeSwitchText: String
    ) -> FlickKanaSet {
        FlickKanaSet(
            label: label,
            center: label,
            up: up,
            right: right,
            down: "…",
            left: modeSwitchText,
            usesProfileDependentGuideOrder: false
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

    private var numberThreeByThreeDirectionalHintScale: CGFloat {
        isLandscapeLayout ? 0.82 : 1
    }

    private var shorterScreenEdge: CGFloat {
        min(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
    }

    private var usesCompactKanaFiveByTwoBottomActionRow: Bool {
        !isLandscapeLayout
            && isKanaFiveByTwoMode
            && showsNextKeyboardKey
            && shorterScreenEdge <= 390
    }

    private var bottomActionRowGlobeKeyWidth: CGFloat {
        usesCompactKanaFiveByTwoBottomActionRow ? 44 : 54
    }

    private var bottomActionRowDeleteKeyWidth: CGFloat {
        usesCompactKanaFiveByTwoBottomActionRow ? 56 : 64
    }

    private var bottomActionRowKanaTrailingKeyWidth: CGFloat {
        usesCompactKanaFiveByTwoBottomActionRow ? selectorKeySize : kanaFiveByTwoTrailingKeyWidth
    }

    private var bottomActionRowReturnKeyWidth: CGFloat {
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

    private var portraitLatinInlineActionSymbolKeyWidth: CGFloat {
        max(1, portraitLatinInlineActionBaseKeyWidth - 3)
    }

    private var portraitLatinInlineReturnKeyWidth: CGFloat {
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

    private var shouldShowCompactLeftModeSwitchInBottomActionRow: Bool {
        showsCompactLeftModeSwitchButtons
            && rows.count <= 3
            && !usesCompactKanaFiveByTwoBottomActionRow
    }

    private var showsCompactLeftModeSwitchButtons: Bool {
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

    private func clavierInlineSymbol(at index: Int) -> String {
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

    private var rightEdgeUtilityColumnWidth: CGFloat {
        let mirroredUtilityColumnWidth = wideModeSwitchKeyWidth * 2 - leftModeSwitchButtonWidth
        return max(wideModeSwitchKeyWidth, mirroredUtilityColumnWidth)
    }

    private var kanaModeSwitchButtonTitle: String {
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

    private var kanaModeSwitcherPreviewHorizontalPadding: CGFloat {
        if !usesWideLeftModeSwitchButtons {
            return 3
        }

        return 8
    }

    private let kaomojiModeReturnIconFontSize: CGFloat = 32

    var kanaFiveByTwoTopNumberKeys: [String] {
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    }

    func leftModeSwitchNumberButton(height: CGFloat) -> some View {
        ActionKeyButton(
            title: "123",
            fontSize: leftModeSwitchNumberFontSize,
            isEnabled: inputMode != .number,
            action: { switchInputMode(.number) }
        )
            .frame(width: leftModeSwitchButtonWidth, height: height)
    }

    func leftModeSwitchLatinButton(height: CGFloat) -> some View {
        ZStack {
            ActionKeyButton(
                title: "abc",
                fontSize: leftModeSwitchLatinFontSize,
                isEnabled: inputMode != .latin,
                onLongPress: handleLatinModeSwitchLongPress,
                action: handleLatinModeSwitchTap
            )

            if inputMode == .latin,
                isAwaitingLatinModeSwitchSecondTap {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onTapGesture(perform: handleLatinModeSwitchDoubleTap)
            }
        }
        .frame(width: leftModeSwitchButtonWidth, height: height)
    }

    func leftModeSwitchKanaButton(height: CGFloat, fontSize: CGFloat) -> some View {
        ActionKeyButton(
            title: kanaModeSwitchButtonTitle,
            fontSize: fontSize,
            isEnabled: inputMode != .kana,
            action: { switchInputMode(.kana) }
        )
            .frame(width: leftModeSwitchButtonWidth, height: height)
    }

    func leftModeSwitchEmojiButton(height: CGFloat) -> some View {
        ActionKeyButton(
            title: "☺︎",
            accessibilityLabel: "絵文字",
            fontSize: kanaModeSwitcherFaceEmojiIconFontSize,
            onLongPress: enterKaomojiMode,
            action: enterEmojiMode
        )
            .frame(width: leftModeSwitchButtonWidth, height: height)
    }

    private func leftModeSwitchSymbolsButton(height: CGFloat) -> some View {
        ActionKeyButton(
            title: "⌘",
            accessibilityLabel: "記号入力",
            fontSize: symbolTransitionIconFontSize,
            action: enterSymbolsMode
        )
            .frame(width: leftModeSwitchButtonWidth, height: height)
    }

    @ViewBuilder
    func compactLeftModeSwitchButton(slot slotIndex: Int, height: CGFloat) -> some View {
        switch slotIndex {
        case 0:
            leftModeSwitchNumberButton(height: height)
        case 1:
            leftModeSwitchLatinButton(height: height)
        case 2:
            leftModeSwitchKanaButton(
                height: height,
                fontSize: compactKanaModeSwitchButtonFontSize
            )
        case 3:
            if isKanaFiveByTwoMode {
                FlickKeyView(
                    kana: kanaModeSwitcherKana,
                    onCommit: selectKanaModeSwitcher,
                    onCommitWithDirection: selectKanaModeSwitcher,
                    mainLabelFontSize: kanaModeSwitcherMainLabelFontSize,
                    showsDirectionalHints: showsFlickGuideCharacters,
                    showsGuideText: false,
                    activePreviewFontSize: kanaModeSwitcherPreviewFontSize,
                    activeMainLabelFontSizeProvider: { direction, mainText in
                        kanaModeSwitcherMainLabelFontSizeForDirection(
                            direction,
                            mainText: mainText
                        )
                    },
                    activePreviewFontSizeProvider: { direction, previewText in
                        kanaModeSwitcherPreviewFontSizeForDirection(
                            direction,
                            previewText: previewText
                        )
                    },
                    activePreviewHorizontalPadding: kanaModeSwitcherPreviewHorizontalPadding,
                    directionalHintHorizontalOffset: 16
                )
                    .frame(width: leftModeSwitchButtonWidth, height: height)
            } else if inputMode == .latin {
                leftModeSwitchEmojiButton(height: height)
            } else if inputMode == .number && effectiveNumberLayoutMode == .clavier {
                // clavier 縦画面では電卓/電話モードと同じく ⌘ (記号入力モードへの切替)を
                // 左コンパクト列の最下段(slot 3)に配置する。
                leftModeSwitchSymbolsButton(height: height)
            } else {
                Color.clear
                    .allowsHitTesting(false)
                    .frame(width: leftModeSwitchButtonWidth, height: height)
            }
        default:
            Color.clear
                .allowsHitTesting(false)
                .frame(width: leftModeSwitchButtonWidth, height: height)
        }
    }

    var threeByThreeKanaRows: [[FlickKanaSet]] {
        FlickKanaLayout.rows(for: activeKanaModifierMode, layoutMode: .threeByThreePlusWa).map { row in
            row.map {
                displayedKanaForKanaCharacterModeIfNeeded($0.remapped(for: directionProfile))
            }
        }
    }

    var threeByThreeKanaLeftColumn: some View {
        let rowHeight: CGFloat = mainFlickKeyHeight
        let rowSpacing: CGFloat = keyboardRowSpacing

        return VStack(spacing: rowSpacing) {
            leftModeSwitchNumberButton(height: rowHeight)
            leftModeSwitchLatinButton(height: rowHeight)
            leftModeSwitchKanaButton(
                height: rowHeight,
                fontSize: standardKanaModeSwitchButtonFontSize
            )

            FlickKeyView(
                kana: kanaModeSwitcherKana,
                onCommit: selectKanaModeSwitcher,
                onCommitWithDirection: selectKanaModeSwitcher,
                mainLabelFontSize: kanaModeSwitcherMainLabelFontSize,
                showsDirectionalHints: showsFlickGuideCharacters,
                showsGuideText: false,
                activePreviewFontSize: kanaModeSwitcherPreviewFontSize,
                activeMainLabelFontSizeProvider: { direction, mainText in
                    kanaModeSwitcherMainLabelFontSizeForDirection(
                        direction,
                        mainText: mainText
                    )
                },
                activePreviewFontSizeProvider: { direction, previewText in
                    kanaModeSwitcherPreviewFontSizeForDirection(
                        direction,
                        previewText: previewText
                    )
                },
                activePreviewHorizontalPadding: kanaModeSwitcherPreviewHorizontalPadding,
                directionalHintHorizontalOffset: 16,
                onTouchStateChanged: { isTouching in
                    updateActiveLayer(isTouching, layerIndex: 3)
                }
            )
                .frame(width: leftModeSwitchButtonWidth, height: rowHeight)
        }
        // Keep left-column flick previews above the main 4th-row modifier cluster.
        .zIndex(KeyboardLayerZIndex.activeRow + 1)
    }

    func threeByThreeKanaMainCluster(
        kanaRows: [[FlickKanaSet]],
        rowHeight: CGFloat,
        rowSpacing: CGFloat
    ) -> some View {
        VStack(spacing: rowSpacing) {
            HStack(spacing: rowSpacing) {
                FlickKeyView(
                    kana: kanaRows[0][0],
                    onCommit: commitText,
                    mainLabelFontSize: kanaThreeByThreeMainLabelFontSize,
                    showsDirectionalHints: showsFlickGuideCharacters,
                    onTouchStateChanged: { isTouching in
                        updateActiveLayer(isTouching, layerIndex: 0)
                    }
                )
                    .frame(maxWidth: .infinity)
                    .frame(height: rowHeight)

                FlickKeyView(
                    kana: kanaRows[0][1],
                    onCommit: commitText,
                    mainLabelFontSize: kanaThreeByThreeMainLabelFontSize,
                    showsDirectionalHints: showsFlickGuideCharacters,
                    onTouchStateChanged: { isTouching in
                        updateActiveLayer(isTouching, layerIndex: 0)
                    }
                )
                    .frame(maxWidth: .infinity)
                    .frame(height: rowHeight)

                FlickKeyView(
                    kana: kanaRows[0][2],
                    onCommit: commitText,
                    mainLabelFontSize: kanaThreeByThreeMainLabelFontSize,
                    showsDirectionalHints: showsFlickGuideCharacters,
                    onTouchStateChanged: { isTouching in
                        updateActiveLayer(isTouching, layerIndex: 0)
                    }
                )
                    .frame(maxWidth: .infinity)
                    .frame(height: rowHeight)

                ActionKeyButton(
                    title: "⌫",
                    accessibilityLabel: "削除",
                    fontSize: 26,
                    repeatsWhileHolding: true,
                    repeatInitialDelay: keyRepeatInitialDelay,
                    repeatInterval: keyRepeatInterval,
                    action: onDeleteBackward
                )
                    .frame(width: rightEdgeUtilityColumnWidth, height: rowHeight)
            }
            .zIndex(zIndex(for: 0))

            HStack(spacing: rowSpacing) {
                FlickKeyView(
                    kana: kanaRows[1][0],
                    onCommit: commitText,
                    mainLabelFontSize: kanaThreeByThreeMainLabelFontSize,
                    showsDirectionalHints: showsFlickGuideCharacters,
                    onTouchStateChanged: { isTouching in
                        updateActiveLayer(isTouching, layerIndex: 1)
                    }
                )
                    .frame(maxWidth: .infinity)
                    .frame(height: rowHeight)

                FlickKeyView(
                    kana: kanaRows[1][1],
                    onCommit: commitText,
                    mainLabelFontSize: kanaThreeByThreeMainLabelFontSize,
                    showsDirectionalHints: showsFlickGuideCharacters,
                    onTouchStateChanged: { isTouching in
                        updateActiveLayer(isTouching, layerIndex: 1)
                    }
                )
                    .frame(maxWidth: .infinity)
                    .frame(height: rowHeight)

                FlickKeyView(
                    kana: kanaRows[1][2],
                    onCommit: commitText,
                    mainLabelFontSize: kanaThreeByThreeMainLabelFontSize,
                    showsDirectionalHints: showsFlickGuideCharacters,
                    onTouchStateChanged: { isTouching in
                        updateActiveLayer(isTouching, layerIndex: 1)
                    }
                )
                    .frame(maxWidth: .infinity)
                    .frame(height: rowHeight)

                spaceActionKeyButton(
                    title: spaceKeyDisplayTitle,
                    titleOpacity: spaceKeyDisplayOpacity
                )
                    .frame(width: rightEdgeUtilityColumnWidth, height: rowHeight)
            }
            .zIndex(zIndex(for: 1))

            HStack(spacing: rowSpacing) {
                FlickKeyView(
                    kana: kanaRows[2][0],
                    onCommit: commitText,
                    mainLabelFontSize: kanaThreeByThreeMainLabelFontSize,
                    showsDirectionalHints: showsFlickGuideCharacters,
                    onTouchStateChanged: { isTouching in
                        updateActiveLayer(isTouching, layerIndex: 2)
                    }
                )
                    .frame(maxWidth: .infinity)
                    .frame(height: rowHeight)

                FlickKeyView(
                    kana: kanaRows[2][1],
                    onCommit: commitText,
                    mainLabelFontSize: kanaThreeByThreeMainLabelFontSize,
                    showsDirectionalHints: showsFlickGuideCharacters,
                    onTouchStateChanged: { isTouching in
                        updateActiveLayer(isTouching, layerIndex: 2)
                    }
                )
                    .frame(maxWidth: .infinity)
                    .frame(height: rowHeight)

                FlickKeyView(
                    kana: kanaRows[2][2],
                    onCommit: commitText,
                    mainLabelFontSize: kanaThreeByThreeMainLabelFontSize,
                    showsDirectionalHints: showsFlickGuideCharacters,
                    onTouchStateChanged: { isTouching in
                        updateActiveLayer(isTouching, layerIndex: 2)
                    }
                )
                    .frame(maxWidth: .infinity)
                    .frame(height: rowHeight)

                ZStack(alignment: .top) {
                    Color.clear

                    ActionKeyButton(
                        title: returnActionKeyTitle,
                        systemImageName: returnActionKeySystemImageName,
                        accessibilityLabel: returnActionKeyAccessibilityLabel,
                        fontSize: returnActionKeyFontSize,
                        isEnabled: isReturnKeyEnabled,
                        onLongPress: returnKeyKatakanaLongPressAction,
                        onDoubleTap: returnKeyKatakanaDoubleTapAction,
                        doubleTapThreshold: katakanaCommitDoubleTapThreshold,
                        prefersImmediateSingleTapWhenDoubleTapEnabled: true,
                        action: onReturn
                    )
                        .frame(maxWidth: .infinity)
                        .frame(height: rowHeight * 2 + rowSpacing)
                }
                    .frame(width: rightEdgeUtilityColumnWidth, height: rowHeight, alignment: .top)
                .zIndex(KeyboardLayerZIndex.rightEdgeUtilityColumn)
            }
            .zIndex(zIndex(for: 2))

            HStack(spacing: rowSpacing) {
                FlickKeyView(
                    kana: modifierSelectorKey,
                    onCommit: selectModifierMode,
                    onCommitWithDirection: selectModifierMode,
                    mainLabelFontSize: modifierMainLabelFontSize,
                    flickGuideDisplayModeOverride: modifierFlickGuideDisplayMode,
                    showsDirectionalHints: showsModifierFlickGuideCharacters,
                    idleReplacement: modifierIdleReplacement,
                    onLongPress: onToggleParenthesesWrapper,
                    directionalFlickThreshold: modifierDirectionalFlickThreshold,
                    directionalCommitThreshold: modifierDirectionalCommitThreshold,
                    onTouchStateChanged: { isTouching in
                        updateActiveLayer(isTouching, layerIndex: 3)
                    }
                )
                    .frame(maxWidth: .infinity)
                    .frame(height: rowHeight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                isPrefixModifierActive
                                    ? accentColor.opacity(0.95)
                                    : Color.clear,
                                lineWidth: 2
                            )
                    )

                FlickKeyView(
                    kana: threeByThreeWaKana,
                    onCommit: commitText,
                    mainLabelFontSize: kanaThreeByThreeMainLabelFontSize,
                    showsDirectionalHints: showsFlickGuideCharacters,
                    onTouchStateChanged: { isTouching in
                        updateActiveLayer(isTouching, layerIndex: 3)
                    }
                )
                    .frame(maxWidth: .infinity)
                    .frame(height: rowHeight)

                FlickKeyView(
                    kana: punctuationKana,
                    onCommit: commitText,
                    mainLabelFontSize: kanaThreeByThreeMainLabelFontSize,
                    showsDirectionalHints: showsFlickGuideCharacters,
                    idleReplacement: punctuationIdleReplacement,
                    onTouchStateChanged: { isTouching in
                        updateActiveLayer(isTouching, layerIndex: 3)
                    }
                )
                    .frame(maxWidth: .infinity)
                    .frame(height: rowHeight)

                Color.clear
                    .allowsHitTesting(false)
                    .frame(width: rightEdgeUtilityColumnWidth, height: rowHeight)
            }
            .zIndex(zIndex(for: 3))
        }
    }

    private var threeByThreeKanaGrid: some View {
        let rowHeight = mainFlickKeyHeight
        let rowSpacing: CGFloat = keyboardRowSpacing
        let kanaRows = threeByThreeKanaRows

        return HStack(spacing: rowSpacing) {
            threeByThreeKanaLeftColumn
            threeByThreeKanaMainCluster(
                kanaRows: kanaRows,
                rowHeight: rowHeight,
                rowSpacing: rowSpacing
            )
        }
    }

    @ViewBuilder
    func threeByThreeMainKey(_ kana: FlickKanaSet, rowIndex: Int) -> some View {
        if isLatinShiftKey(kana) {
            LatinShiftKeyButton(
                isOn: latinShiftState != .off,
                isLocked: latinShiftState == .locked,
                onTap: handleLatinShiftTap,
                onLongPress: handleLatinShiftLongPress
            )
                .frame(maxWidth: .infinity)
                .frame(height: mainFlickKeyHeight)
        } else {
            let renderedKana = displayedKana(for: kana)
            let baseMainLabelFontSize = inputMode == .number
                ? numberThreeByThreeMainLabelFontSize
                : CGFloat(28)
            let mainLabelFontSize = inputMode == .latin
                && latinLayoutMode == .flick
                && renderedKana.center == "@"
                ? baseMainLabelFontSize - 1
                : baseMainLabelFontSize
            let directionalHintScale = inputMode == .number
                ? numberThreeByThreeDirectionalHintScale
                : CGFloat(1)

            FlickKeyView(
                kana: renderedKana,
                onCommit: commitText,
                mainLabelFontSize: mainLabelFontSize,
                showsDirectionalHints: showsFlickGuideCharacters,
                idleReplacement: rowKeyIdleReplacement(for: renderedKana),
                longPressCandidates: longPressCandidates(for: kana),
                longPressCandidatePanelPlacement: longPressCandidatePanelPlacement(forRowIndex: rowIndex),
                allowsDirectionalFlick: allowsDirectionalFlick(for: kana),
                directionalHintFontScale: directionalHintScale,
                downDirectionalHintFontScale: inputMode == .number ? numberDownDirectionalHintScale : 1,
                downDirectionalHintVerticalOffsetAdjustment: inputMode == .number
                    ? numberDownDirectionalHintVerticalOffsetAdjustment
                    : 0,
                onTouchStateChanged: { isTouching in
                    updateActiveLayer(isTouching, layerIndex: rowIndex)
                }
            )
                .frame(maxWidth: .infinity)
                .frame(height: mainFlickKeyHeight)
        }
    }

    @ViewBuilder
    func threeByThreeLeftColumnButton(rowIndex: Int, rowHeight: CGFloat) -> some View {
        switch rowIndex {
        case 0:
            leftModeSwitchNumberButton(height: rowHeight)
        case 1:
            leftModeSwitchLatinButton(height: rowHeight)
        case 2:
            leftModeSwitchKanaButton(
                height: rowHeight,
                fontSize: standardKanaModeSwitchButtonFontSize
            )
        case 3:
            if inputMode == .number {
                leftModeSwitchSymbolsButton(height: rowHeight)
            } else {
                leftModeSwitchEmojiButton(height: rowHeight)
            }
        default:
            Color.clear
                .allowsHitTesting(false)
                .frame(width: leftModeSwitchButtonWidth, height: rowHeight)
        }
    }

    @ViewBuilder
    func threeByThreeRightColumnButton(rowIndex: Int, rowHeight: CGFloat, rowSpacing: CGFloat) -> some View {
        switch rowIndex {
        case 0:
            ActionKeyButton(
                title: "⌫",
                accessibilityLabel: "削除",
                fontSize: 26,
                repeatsWhileHolding: true,
                repeatInitialDelay: keyRepeatInitialDelay,
                repeatInterval: keyRepeatInterval,
                action: onDeleteBackward
            )
                .frame(width: rightEdgeUtilityColumnWidth, height: rowHeight)
        case 1:
            spaceActionKeyButton(title: "")
                .frame(width: rightEdgeUtilityColumnWidth, height: rowHeight)
        case 2:
            ZStack(alignment: .top) {
                Color.clear

                ActionKeyButton(
                    title: returnActionKeyTitle,
                    systemImageName: returnActionKeySystemImageName,
                    accessibilityLabel: returnActionKeyAccessibilityLabel,
                    fontSize: returnActionKeyFontSize,
                    isEnabled: isReturnKeyEnabled,
                    onLongPress: returnKeyKatakanaLongPressAction,
                    onDoubleTap: returnKeyKatakanaDoubleTapAction,
                    doubleTapThreshold: katakanaCommitDoubleTapThreshold,
                    prefersImmediateSingleTapWhenDoubleTapEnabled: true,
                    action: onReturn
                )
                    .frame(maxWidth: .infinity)
                    .frame(height: rowHeight * 2 + rowSpacing)
            }
            .frame(width: rightEdgeUtilityColumnWidth, height: rowHeight, alignment: .top)
            .zIndex(KeyboardLayerZIndex.rightEdgeUtilityColumn)
        case 3:
            Color.clear
                .allowsHitTesting(false)
                .frame(width: rightEdgeUtilityColumnWidth, height: rowHeight)
        default:
            Color.clear
                .allowsHitTesting(false)
                .frame(width: rightEdgeUtilityColumnWidth, height: rowHeight)
        }
    }

    private var threeByThreeNumberOrLatinGrid: some View {
        // Keep number-mode key height aligned with kana key height.
        let rowHeight = mainFlickKeyHeight
        let rowSpacing: CGFloat = keyboardRowSpacing

        return VStack(spacing: rowSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: rowSpacing) {
                    threeByThreeLeftColumnButton(rowIndex: rowIndex, rowHeight: rowHeight)

                    ForEach(row) { kana in
                        threeByThreeMainKey(kana, rowIndex: rowIndex)
                    }

                    threeByThreeRightColumnButton(
                        rowIndex: rowIndex,
                        rowHeight: rowHeight,
                        rowSpacing: rowSpacing
                    )
                }
                .zIndex(zIndex(for: rowIndex))
            }
        }
    }

    private var topHeaderView: some View {
        Group {
            if inputMode == .emoji {
                Text(emojiHeaderTitle)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(keyLabelColor.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 2)
                    .padding(.top, emojiHeaderTopPadding)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            } else if showsKanaConversionCandidates {
                kanaConversionCandidateHeaderView
            } else if showsLatinSuggestionCandidates {
                latinSuggestionHeaderView
            } else {
                Color.clear
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: candidateHeaderHeight)
    }

    private var kanaConversionCandidateHeaderView: some View {
        KeyboardRootKanaCandidateHeaderView(
            showsParenthesesWrapper: showsParenthesesWrapper,
            composingText: composingText,
            conversionStateLabel: conversionStateLabel,
            conversionStateColor: conversionStateColor,
            candidateStateFontSize: candidateStateFontSize,
            candidateTextFontSize: candidateTextFontSize,
            canTapComposingTextToCommit: canTapComposingTextToCommit,
            showsKatakanaCommitFeedback: isShowingKatakanaCommitFeedback(for: composingText),
            accentColor: accentColor,
            keyLabelColor: keyLabelColor,
            conversionCandidates: conversionCandidates,
            selectedConversionCandidateIndex: selectedConversionCandidateIndex,
            kanaCandidateHeaderTopPadding: kanaCandidateHeaderTopPadding,
            onSelectConversionCandidate: onSelectConversionCandidate,
            onComposingTextCommitTap: handleComposingTextCommitTap,
            onComposingTextCommitLongPress: handleComposingTextCommitLongPress
        )
    }

    private var latinSuggestionHeaderView: some View {
        KeyboardRootLatinSuggestionHeaderView(
            latinSuggestions: latinSuggestions,
            candidateTextFontSize: candidateTextFontSize,
            keyLabelColor: keyLabelColor,
            kanaCandidateHeaderTopPadding: kanaCandidateHeaderTopPadding,
            onSelectConversionCandidate: onSelectConversionCandidate
        )
    }

    var landscapeEmptyCandidatePlaceholderCount: Int { 6 }

    let landscapeLatinTypewriterMiddleRowOffsetFactor: CGFloat = 0.25
    let landscapeLatinTypewriterBottomRowOffsetFromMiddleFactor: CGFloat = 0.5

    @ViewBuilder
    private func inlineLatinDeleteKey(fixedWidth: CGFloat? = nil) -> some View {
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

    @ViewBuilder
    var keyboardMainContent: some View {
        if inputMode == .emoji {
            switch emojiInputSubmode {
            case .emoji:
                emojiKeyboardView
            case .kaomoji:
                kaomojiKeyboardView
            case .symbols:
                symbolKeyboardView
            }
        } else if usesLandscapeLatinTypewriterLayout {
            HStack(spacing: keyboardRowSpacing) {
                landscapeLatinModeSwitchColumn
                landscapeLatinTypewriterMainCluster
                    .frame(maxWidth: .infinity)
            }
        } else if isKanaThreeByThreeMode {
            threeByThreeKanaGrid
        } else if usesLandscapeCompactNumberLayout {
            landscapeNumberNarrowGrid
        } else if usesThreeByThreeGridForNumberOrLatin {
            threeByThreeNumberOrLatinGrid
        } else {
            if isKanaFiveByTwoMode {
                HStack(spacing: keyboardRowSpacing) {
                    compactLeftModeSwitchButton(slot: 0, height: mainFlickKeyHeight)

                    ForEach(kanaFiveByTwoTopNumberKeys, id: \.self) { key in
                        ActionKeyButton(
                            title: key,
                            fontSize: 18,
                            action: { commitText(key) }
                        )
                            .frame(maxWidth: .infinity)
                            .frame(height: mainFlickKeyHeight)
                    }
                }
            }

            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: keyboardRowSpacing) {
                    let qwertyBottomRowKeyMetrics = portraitQwertyBottomRowKeyMetrics(rowIndex: rowIndex)
                    let compactLeftModeSwitchSlot = isKanaFiveByTwoMode ? rowIndex + 1 : rowIndex

                    if showsCompactLeftModeSwitchButtons && compactLeftModeSwitchSlot < 4 {
                        compactLeftModeSwitchButton(slot: compactLeftModeSwitchSlot, height: mainFlickKeyHeight)
                    }

                    ForEach(row) { kana in
                        if shouldReplacePortraitAzertyRightShiftWithDelete(
                            rowIndex: rowIndex,
                            kana: kana
                        ) || shouldReplacePortraitClavierRightShiftWithDelete(
                            rowIndex: rowIndex,
                            kana: kana
                        ) {
                            inlineLatinDeleteKey()
                        } else if isLatinShiftKey(kana) {
                            let shiftKey = LatinShiftKeyButton(
                                isOn: latinShiftState != .off,
                                isLocked: latinShiftState == .locked,
                                onTap: handleLatinShiftTap,
                                onLongPress: handleLatinShiftLongPress
                            )

                            if let qwertyBottomRowKeyMetrics {
                                shiftKey
                                    .frame(width: qwertyBottomRowKeyMetrics.edge, height: mainFlickKeyHeight)
                            } else {
                                shiftKey
                                    .frame(maxWidth: .infinity)
                                    .frame(height: mainFlickKeyHeight)
                            }
                        } else {
                            let renderedKana = displayedKana(for: kana)

                            let letterKey = FlickKeyView(
                                kana: renderedKana,
                                onCommit: commitText,
                                mainLabelFontSize: (inputMode == .number && effectiveNumberLayoutMode == .clavier)
                                    ? clavierMainKeyFontSize(for: renderedKana.center)
                                    : 28,
                                mainLabelFontWeight: rowKeyMainLabelFontWeight,
                                showsDirectionalHints: showsFlickGuideCharacters,
                                idleReplacement: rowKeyIdleReplacement(for: renderedKana),
                                longPressCandidates: longPressCandidates(for: kana),
                                longPressCandidatePanelPlacement: longPressCandidatePanelPlacement(forRowIndex: rowIndex),
                                allowsDirectionalFlick: allowsDirectionalFlick(for: kana),
                                onTouchStateChanged: { isTouching in
                                    updateActiveLayer(isTouching, layerIndex: rowIndex)
                                }
                            )

                            if let qwertyBottomRowKeyMetrics {
                                letterKey
                                    .frame(width: qwertyBottomRowKeyMetrics.letter, height: mainFlickKeyHeight)
                            } else {
                                letterKey
                                    .frame(maxWidth: .infinity)
                                    .frame(height: mainFlickKeyHeight)
                            }
                        }
                    }

                    if shouldAppendPortraitQwertyDeleteKey(rowIndex: rowIndex) {
                        inlineLatinDeleteKey(fixedWidth: qwertyBottomRowKeyMetrics?.edge)
                    }
                }
                .padding(horizontalInsetsForMainRow(rowIndex))
                .zIndex(zIndex(for: rowIndex))
            }

            let unifiedActionRowHeight = isLandscapeLayout ? compactActionKeyHeight : mainFlickKeyHeight
            let unifiedActionRowTopSpacing = isLandscapeLayout ? actionRowTopSpacing : 0

            HStack(spacing: keyboardRowSpacing) {
                if shouldShowCompactLeftModeSwitchInBottomActionRow {
                    let compactLeftModeSwitchSlot = isKanaFiveByTwoMode ? rows.count + 1 : rows.count
                    compactLeftModeSwitchButton(slot: compactLeftModeSwitchSlot, height: unifiedActionRowHeight)
                }

                if showsNextKeyboardKey {
                    if usesCompactKanaFiveByTwoBottomActionRow {
                        FlickKeyView(
                            kana: compactKeyboardSwitchKana,
                            onCommit: selectCompactKeyboardSwitchKey,
                            onCommitWithDirection: selectCompactKeyboardSwitchKey,
                            mainLabelFontSize: kaomojiTransitionIconFontSize,
                            showsDirectionalHints: showsFlickGuideCharacters,
                            showsGuideText: false,
                            onLongPress: handleCompactKeyboardSwitchLongPress,
                            activePreviewFontSize: kanaModeSwitcherPreviewFontSize,
                            activeMainLabelFontSizeProvider: { direction, mainText in
                                kanaModeSwitcherMainLabelFontSizeForDirection(
                                    direction,
                                    mainText: mainText
                                )
                            },
                            activePreviewFontSizeProvider: { direction, previewText in
                                kanaModeSwitcherPreviewFontSizeForDirection(
                                    direction,
                                    previewText: previewText
                                )
                            },
                            activePreviewHorizontalPadding: kanaModeSwitcherPreviewHorizontalPadding,
                            directionalHintHorizontalOffset: 16
                        )
                            .frame(width: bottomActionRowGlobeKeyWidth, height: unifiedActionRowHeight)
                    } else {
                        ActionKeyButton(
                            title: "🌐",
                            fixedWidth: bottomActionRowGlobeKeyWidth,
                            action: onAdvanceKeyboard
                        )
                            .frame(height: unifiedActionRowHeight)
                    }
                }

                if usesPortraitLatinInlineDeleteLayout {
                    ActionKeyButton(
                        title: portraitLatinDeleteReplacementSymbol,
                        fontSize: 22,
                        fixedWidth: portraitLatinInlineActionSymbolKeyWidth,
                        action: { commitText(portraitLatinDeleteReplacementSymbol) }
                    )
                        .frame(height: unifiedActionRowHeight)
                } else if usesPortraitClavierInlineDeleteLayout {
                    // delete 自体は行3 右端に配置済み。AZERTY 行末の `@` と同じスロットには
                    // clavier の最初の記号(`#`/shift時 `!`)を置き、space 位置を AZERTY と
                    // 揃える。フォントサイズは clavier の他キーと統一(26pt)。
                    ActionKeyButton(
                        title: clavierInlineSymbol(at: 0),
                        fontSize: clavierKeyFontSize,
                        fixedWidth: portraitLatinInlineActionSymbolKeyWidth,
                        action: { commitText(clavierInlineSymbol(at: 0)) }
                    )
                        .frame(height: unifiedActionRowHeight)
                } else {
                    ActionKeyButton(
                        title: "⌫",
                        accessibilityLabel: "削除",
                        fontSize: 26,
                        fixedWidth: bottomActionRowDeleteKeyWidth,
                        repeatsWhileHolding: true,
                        repeatInitialDelay: keyRepeatInitialDelay,
                        repeatInterval: keyRepeatInterval,
                        action: onDeleteBackward
                    )
                        .frame(height: unifiedActionRowHeight)
                }

                if usesPortraitLatinInlineDeleteLayout {
                    latinSpaceLeftActionButtons(
                        fixedWidth: portraitLatinInlineActionSymbolKeyWidth,
                        keyHeight: unifiedActionRowHeight
                    )
                } else if usesPortraitClavierInlineDeleteLayout {
                    // AZERTY の space-left 位置(`/`)に clavier の2番目の記号を置く。
                    ActionKeyButton(
                        title: clavierInlineSymbol(at: 1),
                        fontSize: clavierKeyFontSize,
                        fixedWidth: portraitLatinInlineActionSymbolKeyWidth,
                        action: { commitText(clavierInlineSymbol(at: 1)) }
                    )
                        .frame(height: unifiedActionRowHeight)
                }

                spaceKeyButton(fixedWidth: nil, keyHeight: unifiedActionRowHeight)

                if inputMode == .latin {
                    latinSpaceRightActionButtons(
                        fixedWidth: usesPortraitLatinInlineDeleteLayout
                            ? portraitLatinInlineActionSymbolKeyWidth
                            : nil,
                        keyHeight: unifiedActionRowHeight
                    )
                } else if usesPortraitClavierInlineDeleteLayout {
                    // AZERTY の space-right 位置(`.`/`-`)に clavier の3,4番目の記号を置く。
                    ForEach([2, 3], id: \.self) { index in
                        ActionKeyButton(
                            title: clavierInlineSymbol(at: index),
                            fontSize: clavierKeyFontSize,
                            fixedWidth: portraitLatinInlineActionSymbolKeyWidth,
                            action: { commitText(clavierInlineSymbol(at: index)) }
                        )
                            .frame(height: unifiedActionRowHeight)
                    }
                }

                if inputMode == .kana {
                    FlickKeyView(
                        kana: modifierSelectorKey,
                        onCommit: selectModifierMode,
                        onCommitWithDirection: selectModifierMode,
                        mainLabelFontSize: modifierMainLabelFontSize,
                        flickGuideDisplayModeOverride: modifierFlickGuideDisplayMode,
                        showsDirectionalHints: showsModifierFlickGuideCharacters,
                        idleReplacement: modifierIdleReplacement,
                        onLongPress: onToggleParenthesesWrapper,
                        directionalFlickThreshold: modifierDirectionalFlickThreshold,
                        directionalCommitThreshold: modifierDirectionalCommitThreshold,
                        onTouchStateChanged: { isTouching in
                            updateActiveLayer(isTouching, layerIndex: rows.count)
                        }
                    )
                        .frame(width: bottomActionRowKanaTrailingKeyWidth, height: selectorKeySize)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(
                                    isPrefixModifierActive
                                        ? accentColor.opacity(0.95)
                                        : Color.clear,
                                    lineWidth: 2
                                )
                        )

                    FlickKeyView(
                        kana: punctuationKana,
                        onCommit: commitText,
                        showsDirectionalHints: showsFlickGuideCharacters,
                        idleReplacement: punctuationIdleReplacement,
                        onTouchStateChanged: { isTouching in
                            updateActiveLayer(isTouching, layerIndex: rows.count)
                        }
                    )
                        .frame(width: bottomActionRowKanaTrailingKeyWidth, height: selectorKeySize)
                } else if inputMode == .number {
                    if effectiveNumberLayoutMode == .clavier && !isLandscapeLayout {
                        // clavier portrait: shift は行3 左、delete は行3 右、#$%& は
                        // delete跡 / space-left / space-right に配置済み(AZERTY と
                        // 同じ位置)。 あい/abc/⌘ は左 compact mode switch 列に集約
                        // しているので system 行右端には何も追加しない。
                        EmptyView()
                    } else {
                        ActionKeyButton(
                            title: "あい",
                            fixedWidth: 58,
                            action: { switchInputMode(.kana) }
                        )
                            .frame(height: unifiedActionRowHeight)

                        ActionKeyButton(
                            title: "abc",
                            fontSize: leftModeSwitchLatinFontSize,
                            fixedWidth: 58,
                            action: { switchInputMode(.latin) }
                        )
                            .frame(height: unifiedActionRowHeight)

                        ActionKeyButton(
                            title: "⌘",
                            accessibilityLabel: "記号入力",
                            fontSize: symbolTransitionIconFontSize,
                            fixedWidth: 58,
                            action: enterSymbolsMode
                        )
                            .frame(height: unifiedActionRowHeight)
                    }
                } else {
                    if !showsCompactLeftModeSwitchButtons {
                        ActionKeyButton(
                            title: "あい",
                            fixedWidth: 58,
                            action: { switchInputMode(.kana) }
                        )
                            .frame(height: unifiedActionRowHeight)

                        ActionKeyButton(
                            title: "123",
                            fontSize: 20,
                            fixedWidth: 58,
                            action: { switchInputMode(.number) }
                        )
                            .frame(height: unifiedActionRowHeight)
                    }
                }

                ActionKeyButton(
                    title: returnActionKeyTitle,
                    systemImageName: returnActionKeySystemImageName,
                    accessibilityLabel: returnActionKeyAccessibilityLabel,
                    fontSize: returnActionKeyFontSize,
                    fixedWidth: (usesPortraitLatinInlineDeleteLayout || usesPortraitClavierInlineDeleteLayout)
                        ? portraitLatinInlineReturnKeyWidth
                        : bottomActionRowReturnKeyWidth,
                    isEnabled: isReturnKeyEnabled,
                    onLongPress: returnKeyKatakanaLongPressAction,
                    onDoubleTap: returnKeyKatakanaDoubleTapAction,
                    doubleTapThreshold: katakanaCommitDoubleTapThreshold,
                    prefersImmediateSingleTapWhenDoubleTapEnabled: true,
                    action: onReturn
                )
                    .frame(height: unifiedActionRowHeight)
            }
            .padding(.top, unifiedActionRowTopSpacing)
            .zIndex(zIndex(for: rows.count))
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
        composingText: "かな",
        conversionCandidates: ["仮名", "かな"],
        selectedConversionCandidateIndex: 0,
        latinSuggestionQuery: "caf",
        latinSuggestions: ["cafe", "café"],
        showsParenthesesWrapper: false,
        initialSpaceToastText: nil
    )
}
