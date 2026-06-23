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
    @State private var selectedKaomojiReadingPrefix: String? = nil
    @State private var selectedKaomojiReading: String? = nil
    @State private var emojiInputSubmode: EmojiInputSubmode = .emoji
    @State var returnToKanaAfterNextCommit: Bool = false
    @State var didTriggerComposingCommitLongPress = false
    @State var katakanaCommitFeedbackText: String? = nil
    @State var pendingKatakanaCommitWorkItem: DispatchWorkItem?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let shiftDoubleTapThreshold: TimeInterval = 0.32
    let latinModeSwitchDoubleTapThreshold: TimeInterval = 0.28
    private let katakanaCommitDoubleTapThreshold: TimeInterval = 0.2
    let katakanaCommitFeedbackDelay: TimeInterval = 0.14
    let keyLabelColor = KeyboardThemePalette.keyLabel
    private let candidateHeaderExpandedHeight: CGFloat = 35
    private let candidateHeaderContentDownshift: CGFloat = 4
    private var keyboardRowSpacing: CGFloat { isLandscapeLayout ? 4 : 6 }
    private var keyboardTopPadding: CGFloat {
        if isLandscapeLayout
            && (inputMode == .kana || inputMode == .number || isLandscapeLatinThreeByThreeMode) {
            return 0
        }

        return isLandscapeLayout ? 1 : 3
    }
    private var keyboardHorizontalPadding: CGFloat { isLandscapeLayout ? 6 : 8 }
    private var keyboardBottomPadding: CGFloat { isLandscapeLayout ? 4 : 20 }
    private let candidateStateFontSize: CGFloat = 15
    private let candidateTextFontSize: CGFloat = 16
    var compactActionKeyHeight: CGFloat { isLandscapeLayout ? 34 : 42 }
    private let compactModeSwitchKeyWidth: CGFloat = 32
    private let wideModeSwitchKeyWidth: CGFloat = 58
    private let compactEmojiKeyHeight: CGFloat = 28
    private let compactKaomojiKeyHeight: CGFloat = 30
    private let emojiGridSpacing: CGFloat = 2
    private let kaomojiMaxColumns = 5
    private let kaomojiMinKeyWidth: CGFloat = 52
    private let kaomojiHorizontalPadding: CGFloat = 8
    private let kaomojiFontSize: CGFloat = 18
    private let kaomojiMinInterItemSpacingMultiplier: CGFloat = 1.2
    private let kaomojiCategoryButtonWidth: CGFloat = 40
    private let kaomojiSearchReadingDisplayLimit = 120

    private var showsKanaConversionCandidates: Bool {
        inputMode == .kana && (!composingText.isEmpty || showsParenthesesWrapper)
    }

    var isLandscapeLayout: Bool {
        verticalSizeClass == .compact
    }

    private var usesLandscapeKanaCandidateSidebar: Bool {
        isLandscapeLayout && inputMode == .kana
    }

    private var usesLandscapeLatinSuggestionSidebar: Bool {
        isLandscapeLayout
            && inputMode == .latin
            && landscapeLatinSuggestionMode == .sidebar
    }

    private var showsLatinSuggestionCandidates: Bool {
        inputMode == .latin && !latinSuggestionQuery.isEmpty
    }

    private var usesLandscapeLatinTypewriterLayout: Bool {
        isLandscapeLayout
            && inputMode == .latin
            && (latinLayoutMode == .qwerty || latinLayoutMode == .azerty)
    }

    private var landscapeLatinInlineReturnRowIndex: Int {
        // Keep return key directly under delete: right of L (QWERTY) / m (AZERTY).
        1
    }

    private var landscapeLatinInlinePunctuationKeys: [FlickKanaSet] {
        let marks: [String] = latinLayoutMode == .qwerty
            ? [",", "/"]
            : [",", "/", "'"]

        return marks.map { mark in
            FlickKanaSet(
                label: mark,
                center: mark,
                up: "",
                right: "",
                down: "",
                left: ""
            )
        }
    }

    private var needsQwertyMiddleRowApostrophe: Bool {
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

    private var landscapeNumberSymbolPanelRows: [[String]] {
        // Custom landscape number-side companion symbols (4 rows x 6 columns).
        [
            ["+", "€", "℃", "mm", "mg", "ml"],
            ["-", "$", "℉", "cm", "cg", "cl"],
            ["±", "¥", "°", "m", "g", "l"],
            ["(", ")", "/", "km", "kg", "kl"]
        ]
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
    private func latinSpaceLeftActionButtons(
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
    private func latinSpaceRightActionButtons(
        fixedWidth: CGFloat? = nil,
        keyHeight: CGFloat? = nil
    ) -> some View {
        latinActionButtons(
            symbols: latinSpaceRightActionSymbols,
            fixedWidth: fixedWidth,
            keyHeight: keyHeight
        )
    }

    private func isLandscapeLatinRightShiftKey(_ kana: FlickKanaSet) -> Bool {
        kana.label == "__latin_shift_right__"
    }

    private var landscapeLatinRightShiftKey: FlickKanaSet {
        FlickKanaSet(
            label: "__latin_shift_right__",
            center: FlickKanaLayout.latinShiftKeyToken,
            up: "",
            right: "",
            down: "",
            left: ""
        )
    }

    private func landscapeBottomRowWithInlinePunctuation(_ row: [FlickKanaSet]) -> [FlickKanaSet] {
        var augmentedRow = row

        // QWERTY rows don't include a right-shift token in source rows; add it back in landscape.
        if latinLayoutMode == .qwerty,
            !augmentedRow.contains(where: isLandscapeLatinRightShiftKey) {
            augmentedRow.append(landscapeLatinRightShiftKey)
        }

        guard let rightShiftIndex = augmentedRow.firstIndex(where: isLandscapeLatinRightShiftKey) else {
            return augmentedRow
        }

        augmentedRow.insert(contentsOf: landscapeLatinInlinePunctuationKeys, at: rightShiftIndex)
        return augmentedRow
    }

    private var landscapeKanaCandidateSide: LandscapeCandidateSide {
        LandscapeCandidateSide(rawValue: landscapeCandidateSideRawValue) ?? .left
    }

    private var landscapeNumberPaneSide: LandscapeCandidateSide {
        LandscapeCandidateSide(rawValue: landscapeNumberPaneSideRawValue) ?? .left
    }

    private var landscapeLatinSuggestionMode: LandscapeLatinSuggestionMode {
        LandscapeLatinSuggestionMode(rawValue: landscapeLatinSuggestionModeRawValue) ?? .sidebar
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

    private var conversionStateLabel: String {
        isActiveConversion ? "変換中" : "未確定"
    }

    private var conversionStateColor: Color {
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

    private var isReturnActsAsCommitKey: Bool {
        inputMode == .kana && !composingText.isEmpty
    }

    private var returnActionKeyTitle: String {
        if isReturnActsAsCommitKey {
            return "確定"
        }

        return returnKeySystemImageName == nil ? "⏎" : ""
    }

    private var returnActionKeySystemImageName: String? {
        isReturnActsAsCommitKey ? nil : returnKeySystemImageName
    }

    private var returnActionKeyAccessibilityLabel: String {
        if isReturnActsAsCommitKey {
            return "確定"
        }

        return returnKeySystemImageName == nil ? "改行" : "検索"
    }

    private var returnActionKeyFontSize: CGFloat {
        isReturnActsAsCommitKey ? 16 : 22
    }

    private var returnKeyKatakanaDoubleTapAction: (() -> Void)? {
        isReturnActsAsCommitKey ? handleReturnKeyKatakanaDoubleTap : nil
    }

    private var returnKeyKatakanaLongPressAction: (() -> Void)? {
        isReturnActsAsCommitKey ? handleReturnKeyKatakanaLongPress : nil
    }

    var canTapComposingTextToCommit: Bool {
        !composingText.isEmpty
    }

    private var accentPalette: AccentPalette {
        AccentPalette(rawValue: accentPaletteRawValue) ?? .emeraude
    }

    private var accentColor: Color {
        if isSystemDictionaryFallback {
            return Color(uiColor: .systemGray)
        }

        return accentPalette.color
    }

    private var basicSymbolOrder: BasicSymbolOrder {
        BasicSymbolOrder(rawValue: basicSymbolOrderRawValue) ?? .ascii
    }

    private var temperatureUnit: TemperatureUnitPreference {
        TemperatureUnitPreference(rawValue: temperatureUnitRawValue) ?? .celsius
    }

    private var currentFlickGuideDisplayMode: FlickGuideDisplayMode {
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

    private var showsFlickGuideCharacters: Bool {
        currentFlickGuideDisplayMode == .fourDirections
    }

    private var showsModifierFlickGuideCharacters: Bool {
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

    private var isPrefixModifierActive: Bool {
        inputMode == .kana && kanaModifierPlacementMode == .prefix && diacriticMode != .none
    }

    private var rows: [[FlickKanaSet]] {
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

    private var isKanaThreeByThreeMode: Bool {
        inputMode == .kana && kanaLayoutMode == .threeByThreePlusWa
    }

    private var isKanaFiveByTwoMode: Bool {
        inputMode == .kana && kanaLayoutMode == .fiveByTwo
    }

    private var kanaCandidateHeaderTopPadding: CGFloat {
        (isKanaThreeByThreeMode ? 6 : 4) + candidateHeaderContentDownshift
    }

    private var usesThreeByThreeGridForNumberOrLatin: Bool {
        (inputMode == .number || inputMode == .latin)
            && rows.count == 4
            && rows.allSatisfy { $0.count == 3 }
    }

    private var usesLandscapeCompactNumberLayout: Bool {
        isLandscapeLayout
            && inputMode == .number
            && usesThreeByThreeGridForNumberOrLatin
    }

    private var isLandscapeLatinThreeByThreeMode: Bool {
        isLandscapeLayout
            && inputMode == .latin
            && usesThreeByThreeGridForNumberOrLatin
    }

    private var kanaFiveByTwoSideInset: CGFloat {
        isKanaFiveByTwoMode ? 6 : 0
    }

    private func horizontalInsetsForMainRow(_ rowIndex: Int) -> EdgeInsets {
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

    private var modifierSelectorKey: FlickKanaSet {
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

    private var emojiGridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: emojiGridSpacing), count: 9)
    }

    private var symbolGridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: emojiGridSpacing), count: 8)
    }

    private var kaomojiSearchReadingColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: keyboardRowSpacing), count: 3)
    }

    private var kaomojiCategories: [KaomojiCategory] {
        let preferredImportedCategoryOrder: [String] = [
            "笑",
            "かわいい",
            "照れ",
            "焦り",
            "しょぼん",
            "悲",
            "怒",
            "驚き",
            "くそねみ",
            "挨拶",
            "ラブ",
            "激しい",
            "うごき",
            "キモい",
            "キャラ",
            "特殊",
            "ライン"
        ]

        let importedCategorySet = Set(KaomojiCatalog.importedCategoryOrder)
        let orderedImportedCategories = preferredImportedCategoryOrder
            .filter { importedCategorySet.contains($0) }
        let remainingImportedCategories = KaomojiCatalog.importedCategoryOrder
            .filter { !orderedImportedCategories.contains($0) }

        var categories: [KaomojiCategory] = [
            KaomojiCategory(kind: .shortcut),
            KaomojiCategory(kind: .existing),
            KaomojiCategory(kind: .search)
        ]

        categories.append(contentsOf: orderedImportedCategories.map { name in
            KaomojiCategory(kind: .imported(name))
        })
        categories.append(contentsOf: remainingImportedCategories.map { name in
            KaomojiCategory(kind: .imported(name))
        })
        return categories
    }

    private var selectedKaomojiCategory: KaomojiCategory {
        kaomojiCategories.first(where: { $0.id == selectedKaomojiCategoryID })
            ?? KaomojiCategory(kind: .existing)
    }

    private var isKaomojiSearchCategorySelected: Bool {
        if case .search = selectedKaomojiCategory.kind {
            return true
        }

        return false
    }

    private var selectedKaomojiCategoryEntries: [String] {
        switch selectedKaomojiCategory.kind {
        case .shortcut:
            return shortcutVocabularyEntries
        case .existing:
            return KaomojiCatalog.existingEntries
        case .imported(let name):
            return KaomojiCatalog.entries(forImportedCategory: name)
        case .search:
            return []
        }
    }

    private var kaomojiSearchReadings: [String] {
        return Array(
            KaomojiCatalog.readings(prefix: selectedKaomojiReadingPrefix)
                .prefix(kaomojiSearchReadingDisplayLimit)
        )
    }

    private var selectedKaomojiSearchResults: [String] {
        guard let selectedKaomojiReading,
            !selectedKaomojiReading.isEmpty else {
            return []
        }

        return KaomojiCatalog.entries(forReading: selectedKaomojiReading)
    }

    private func selectKaomojiCategory(_ category: KaomojiCategory) {
        selectedKaomojiCategoryID = category.id

        if case .search = category.kind {
            return
        }

        selectedKaomojiReadingPrefix = nil
        selectedKaomojiReading = nil
    }

    private func selectKaomojiReadingPrefix(_ prefix: String?) {
        selectedKaomojiReadingPrefix = prefix
        selectedKaomojiReading = nil
    }

    private func measuredKaomojiWidth(_ kaomoji: String) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: kaomojiFontSize, weight: .semibold)
        ]
        let textWidth = ceil((kaomoji as NSString).size(withAttributes: attributes).width)
        return max(kaomojiMinKeyWidth, textWidth + kaomojiHorizontalPadding * 2)
    }

    private var shortcutVocabularyEntries: [String] {
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

    private func kaomojiRows(
        for availableWidth: CGFloat,
        entries: [String]
    ) -> [KaomojiRowLayout] {
        let minSpacing = keyboardRowSpacing * kaomojiMinInterItemSpacingMultiplier

        guard !entries.isEmpty else {
            return []
        }

        guard availableWidth > 0 else {
            return [KaomojiRowLayout(items: entries, spacing: minSpacing)]
        }

        var rows: [KaomojiRowLayout] = []
        var currentRow: [String] = []
        var currentRowItemsWidth: CGFloat = 0

        func appendCurrentRow() {
            guard !currentRow.isEmpty else {
                return
            }

            let resolvedSpacing: CGFloat
            if currentRow.count > 1 {
                let distributed = (availableWidth - currentRowItemsWidth)
                    / CGFloat(currentRow.count - 1)
                resolvedSpacing = max(minSpacing, distributed)
            } else {
                resolvedSpacing = minSpacing
            }

            rows.append(KaomojiRowLayout(items: currentRow, spacing: resolvedSpacing))
            currentRow.removeAll(keepingCapacity: true)
            currentRowItemsWidth = 0
        }

        for kaomoji in entries {
            let keyWidth = min(measuredKaomojiWidth(kaomoji), availableWidth)

            if currentRow.isEmpty {
                currentRow = [kaomoji]
                currentRowItemsWidth = keyWidth
                continue
            }

            let nextItemCount = currentRow.count + 1
            let nextItemsWidth = currentRowItemsWidth + keyWidth
            let nextRequiredWidth = nextItemsWidth + minSpacing * CGFloat(nextItemCount - 1)
            let canAppendByWidth = nextRequiredWidth <= availableWidth
            let canAppendByCount = nextItemCount <= kaomojiMaxColumns

            if canAppendByWidth && canAppendByCount {
                currentRow.append(kaomoji)
                currentRowItemsWidth = nextItemsWidth
            } else {
                appendCurrentRow()
                currentRow = [kaomoji]
                currentRowItemsWidth = keyWidth
            }
        }

        appendCurrentRow()

        return rows
    }

    @ViewBuilder
    private func kaomojiRowLayoutsView(
        _ rows: [KaomojiRowLayout],
        availableWidth: CGFloat,
        sectionID: String
    ) -> some View {
        let indexedRows = Array(rows.enumerated()).map { index, row in
            (id: "\(sectionID)-row-\(index)", row: row)
        }

        ForEach(indexedRows, id: \.id) { rowEntry in
            let row = rowEntry.row
            HStack(spacing: row.spacing) {
                ForEach(Array(row.items.enumerated()), id: \.offset) { _, kaomoji in
                    KaomojiKeyButton(kaomoji: kaomoji) {
                        commitEmojiKaomojiSymbolText(kaomoji)
                    }
                    .frame(
                        width: min(measuredKaomojiWidth(kaomoji), availableWidth),
                        height: compactKaomojiKeyHeight
                    )
                }

                if row.items.count == 1 {
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var mainFlickKeyHeight: CGFloat {
        isLandscapeLayout ? 40 : 46
    }

    private var fourRowAlignedClusterHeight: CGFloat {
        mainFlickKeyHeight * 4 + keyboardRowSpacing * 3
    }

    private var fourRowAlignedTopContentHeight: CGFloat {
        fourRowAlignedClusterHeight - mainFlickKeyHeight - keyboardRowSpacing
    }

    private func kanaThreeByThreeMainLabelFontSize(for displayMode: FlickGuideDisplayMode) -> CGFloat {
        switch displayMode {
        case .off:
            return 26
        case .fourDirections:
            return 24
        case .down:
            return 23
        }
    }

    private var kanaThreeByThreeMainLabelFontSize: CGFloat {
        kanaThreeByThreeMainLabelFontSize(for: currentFlickGuideDisplayMode)
    }

    private var numberThreeByThreeMainLabelFontSize: CGFloat {
        isLandscapeLayout ? 24 : 28
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

    private var numberDownDirectionalHintScale: CGFloat {
        1.12
    }

    private var numberDownDirectionalHintVerticalOffsetAdjustment: CGFloat {
        -2
    }

    private var modifierMainLabelFontSize: CGFloat {
        let baseSize: CGFloat = isKanaThreeByThreeMode
            ? kanaThreeByThreeMainLabelFontSize(for: modifierFlickGuideDisplayMode)
            : 28

        let centerLabel = modifierSelectorKey.center

        if inputMode == .kana && centerLabel == "小" {
            return baseSize * 0.6
        }

        let isPostfixKana = inputMode == .kana
            && kanaModifierPlacementMode == .postfix

        if isPostfixKana && centerLabel == "^_^" {
            return baseSize * 0.7
        }

        return baseSize
    }

    private var modifierDirectionalFlickThreshold: CGFloat {
        if inputMode == .kana && kanaModifierPlacementMode == .postfix {
            // Postfix modifier misfires are expensive (e.g. つ -> づ), so require larger movement.
            return 26
        }

        return 18
    }

    private var modifierDirectionalCommitThreshold: CGFloat? {
        if inputMode == .kana && kanaModifierPlacementMode == .postfix {
            // Prefer center on postfix modifier unless movement is clearly directional.
            return 32
        }

        return nil
    }

    private var selectorKeySize: CGFloat {
        mainFlickKeyHeight
    }

    private var kanaFiveByTwoTrailingKeyWidth: CGFloat {
        if isKanaFiveByTwoMode {
            return selectorKeySize + 8
        }

        return selectorKeySize
    }

    private var actionRowTopSpacing: CGFloat {
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
    private var rowKeyMainLabelFontWeight: Font.Weight {
        if inputMode == .latin && (latinLayoutMode == .qwerty || latinLayoutMode == .azerty) {
            return .semibold
        }
        if inputMode == .number && effectiveNumberLayoutMode == .clavier {
            return .semibold
        }
        return .bold
    }

    // clavier 配列はメイン letter キーも system 行の inline 記号キーも 26pt に統一する。
    private var clavierKeyFontSize: CGFloat { 26 }

    // 漢数字(一二三四五六七八九〇)はASCII数字より字幅が広いので少し小さめに描画する。
    private func clavierMainKeyFontSize(for text: String) -> CGFloat {
        guard text.count == 1, let scalar = text.unicodeScalars.first else {
            return clavierKeyFontSize
        }
        // CJK統合漢字 (一〜九) と 〇 (U+3007)
        if (0x4E00...0x9FFF).contains(scalar.value) || scalar.value == 0x3007 {
            return clavierKeyFontSize - 4
        }
        return clavierKeyFontSize
    }

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

    private var usesWideLeftModeSwitchButtons: Bool {
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

    private var leftModeSwitchButtonWidth: CGFloat {
        usesWideLeftModeSwitchButtons ? wideModeSwitchKeyWidth : compactModeSwitchKeyWidth
    }

    private var rightEdgeUtilityColumnWidth: CGFloat {
        let mirroredUtilityColumnWidth = wideModeSwitchKeyWidth * 2 - leftModeSwitchButtonWidth
        return max(wideModeSwitchKeyWidth, mirroredUtilityColumnWidth)
    }

    private var kanaModeSwitchButtonTitle: String {
        usesWideLeftModeSwitchButtons ? "あいう" : "あい"
    }

    private var landscapeLeftModeSwitchFontSize: CGFloat {
        16
    }

    private var landscapeLeftModeSwitchKaomojiIconFontSize: CGFloat {
        24
    }

    private var portraitLeftModeSwitchFontSize: CGFloat {
        13
    }

    private var unifiedLeftModeSwitchFontSize: CGFloat {
        isLandscapeLayout ? landscapeLeftModeSwitchFontSize : portraitLeftModeSwitchFontSize
    }

    private var compactKanaModeSwitchButtonFontSize: CGFloat {
        unifiedLeftModeSwitchFontSize
    }

    private var standardKanaModeSwitchButtonFontSize: CGFloat {
        unifiedLeftModeSwitchFontSize
    }

    private var leftModeSwitchNumberFontSize: CGFloat {
        if usesWideLeftModeSwitchButtons && !isLandscapeLayout {
            return 18
        }

        return unifiedLeftModeSwitchFontSize
    }

    private var leftModeSwitchLatinFontSize: CGFloat {
        if usesWideLeftModeSwitchButtons && !isLandscapeLayout {
            return 18
        }

        return unifiedLeftModeSwitchFontSize
    }

    private var portraitCompactLeftModeSwitchKaomojiIconFontSize: CGFloat {
        28
    }

    private var portraitWideLeftModeSwitchKaomojiIconFontSize: CGFloat {
        20
    }

    private var portraitWideLeftModeSwitchEmojiIconFontSize: CGFloat {
        26
    }

    private var kaomojiTransitionIconFontSize: CGFloat {
        if isLandscapeLayout {
            return landscapeLeftModeSwitchKaomojiIconFontSize
        }

        if usesWideLeftModeSwitchButtons {
            return portraitWideLeftModeSwitchKaomojiIconFontSize
        }

        return portraitCompactLeftModeSwitchKaomojiIconFontSize
    }

    private var symbolTransitionIconFontSize: CGFloat {
        if isLandscapeLayout {
            return unifiedLeftModeSwitchFontSize
        }

        if usesWideLeftModeSwitchButtons {
            return 20
        }

        return 16
    }

    private var portraitCompactKanaModeSwitcherIconFontSize: CGFloat {
        portraitCompactLeftModeSwitchKaomojiIconFontSize
    }

    private var kanaModeSwitcherEmojiIconFontSize: CGFloat {
        if isLandscapeLayout {
            return landscapeLeftModeSwitchKaomojiIconFontSize
        }

        if !usesWideLeftModeSwitchButtons {
            return portraitCompactKanaModeSwitcherIconFontSize
        }

        return portraitWideLeftModeSwitchKaomojiIconFontSize
    }

    private var kanaModeSwitcherFaceEmojiIconFontSize: CGFloat {
        if isLandscapeLayout {
            return landscapeLeftModeSwitchKaomojiIconFontSize
        }

        if !usesWideLeftModeSwitchButtons {
            return portraitCompactKanaModeSwitcherIconFontSize
        }

        return portraitWideLeftModeSwitchEmojiIconFontSize
    }

    private var kanaModeSwitcherFaceEmojiMainLabelFontSize: CGFloat {
        if isLandscapeLayout || !usesWideLeftModeSwitchButtons {
            return kanaModeSwitcherFaceEmojiIconFontSize
        }

        return portraitWideLeftModeSwitchEmojiIconFontSize + 1
    }

    private var kanaModeSwitcherKaomojiMainLabelFontSize: CGFloat {
        if isLandscapeLayout {
            return landscapeLeftModeSwitchKaomojiIconFontSize
        }

        return max(1, portraitWideLeftModeSwitchKaomojiIconFontSize - 1)
    }

    private func compactKanaModeSwitcherMainLabelFontSize(for action: KanaModeSwitcherAction) -> CGFloat {
        switch action {
        case .symbols:
            return symbolTransitionIconFontSize
        case .emoji:
            return compactKanaModeSwitcherEmojiMainLabelFontSize
        case .kaomoji:
            return unifiedLeftModeSwitchFontSize
        }
    }

    private func wideKanaModeSwitcherMainLabelFontSize(for action: KanaModeSwitcherAction) -> CGFloat {
        switch action {
        case .symbols:
            return symbolTransitionIconFontSize
        case .emoji:
            return kanaModeSwitcherFaceEmojiMainLabelFontSize
        case .kaomoji:
            return kanaModeSwitcherKaomojiMainLabelFontSize
        }
    }

    private func compactKanaModeSwitcherActiveLabelFontSize(for action: KanaModeSwitcherAction) -> CGFloat {
        switch action {
        case .symbols:
            return symbolTransitionIconFontSize
        case .emoji:
            return compactKanaModeSwitcherEmojiActiveIconFontSize
        case .kaomoji:
            return compactKanaModeSwitcherPreviewIconFontSize
        }
    }

    private func wideKanaModeSwitcherActiveMainLabelFontSize(for action: KanaModeSwitcherAction) -> CGFloat {
        switch action {
        case .symbols:
            return symbolTransitionIconFontSize
        case .emoji:
            return kanaModeSwitcherFaceEmojiIconFontSize
        case .kaomoji:
            return kanaModeSwitcherKaomojiMainLabelFontSize
        }
    }

    private func wideKanaModeSwitcherActivePreviewFontSize(for action: KanaModeSwitcherAction) -> CGFloat {
        switch action {
        case .symbols:
            return symbolTransitionIconFontSize
        case .emoji:
            return kanaModeSwitcherFaceEmojiIconFontSize
        case .kaomoji:
            return kanaModeSwitcherEmojiIconFontSize
        }
    }

    private var kanaModeSwitcherMainLabelFontSize: CGFloat {
        if !usesWideLeftModeSwitchButtons {
            return compactKanaModeSwitcherMainLabelFontSize(for: kanaModeSwitcherTapAction)
        }

        return wideKanaModeSwitcherMainLabelFontSize(for: kanaModeSwitcherTapAction)
    }

    private func kanaModeSwitcherMainLabelFontSizeForDirection(
        _ direction: FlickDirection,
        mainText: String
    ) -> CGFloat {
        if mainText == "🌐" {
            return kaomojiTransitionIconFontSize
        }

        if !usesWideLeftModeSwitchButtons {
            if direction == .milieu {
                return kanaModeSwitcherMainLabelFontSize
            }

            if let action = kanaModeSwitcherAction(for: direction) {
                return compactKanaModeSwitcherActiveLabelFontSize(for: action)
            }

            if mainText == "⌘" {
                return symbolTransitionIconFontSize
            }

            if mainText == "☺︎" {
                return compactKanaModeSwitcherEmojiActiveIconFontSize
            }

            if mainText == "^_^" {
                return compactKanaModeSwitcherPreviewIconFontSize
            }

            return kanaModeSwitcherMainLabelFontSize
        }

        if direction == .milieu {
            return kanaModeSwitcherMainLabelFontSize
        }

        if let action = kanaModeSwitcherAction(for: direction) {
            return wideKanaModeSwitcherActiveMainLabelFontSize(for: action)
        }

        if mainText == "⌘" {
            return symbolTransitionIconFontSize
        }

        if mainText == "☺︎" {
            return kanaModeSwitcherFaceEmojiIconFontSize
        }

        if mainText == "^_^" {
            return kanaModeSwitcherKaomojiMainLabelFontSize
        }

        return kanaModeSwitcherMainLabelFontSize
    }

    private var kanaModeSwitcherPreviewFontSize: CGFloat {
        return 14
    }

    private var compactKanaModeSwitcherPreviewIconFontSize: CGFloat {
        18
    }

    private var compactKanaModeSwitcherEmojiMainLabelFontSize: CGFloat {
        unifiedLeftModeSwitchFontSize + 2
    }

    private var compactKanaModeSwitcherEmojiActiveIconFontSize: CGFloat {
        compactKanaModeSwitcherPreviewIconFontSize + 2
    }

    private func kanaModeSwitcherAction(for direction: FlickDirection) -> KanaModeSwitcherAction? {
        switch direction {
        case .droite:
            return kanaModeSwitcherRightFlickAction
        case .haut:
            return kanaModeSwitcherUpFlickAction
        default:
            return nil
        }
    }

    private func kanaModeSwitcherPreviewFontSizeForDirection(
        _ direction: FlickDirection,
        previewText: String
    ) -> CGFloat {
        guard !isLandscapeLayout else {
            return kanaModeSwitcherPreviewFontSize
        }

        if !usesWideLeftModeSwitchButtons {
            if let action = kanaModeSwitcherAction(for: direction) {
                return compactKanaModeSwitcherActiveLabelFontSize(for: action)
            }

            if previewText == "⌘" {
                return symbolTransitionIconFontSize
            }

            if previewText == "☺︎" {
                return compactKanaModeSwitcherEmojiActiveIconFontSize
            }

            if previewText == "^_^" {
                return compactKanaModeSwitcherPreviewIconFontSize
            }

            return kanaModeSwitcherPreviewFontSize
        }

        if let action = kanaModeSwitcherAction(for: direction) {
            return wideKanaModeSwitcherActivePreviewFontSize(for: action)
        }

        if previewText == "⌘" {
            return symbolTransitionIconFontSize
        }

        if previewText == "☺︎" {
            return kanaModeSwitcherFaceEmojiIconFontSize
        }

        if previewText == "^_^" {
            return kanaModeSwitcherEmojiIconFontSize
        }

        return kanaModeSwitcherPreviewFontSize
    }

    private var kanaModeSwitcherPreviewHorizontalPadding: CGFloat {
        if !usesWideLeftModeSwitchButtons {
            return 3
        }

        return 8
    }

    private let kaomojiModeReturnIconFontSize: CGFloat = 32

    private var kanaFiveByTwoTopNumberKeys: [String] {
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    }

    private func leftModeSwitchNumberButton(height: CGFloat) -> some View {
        ActionKeyButton(
            title: "123",
            fontSize: leftModeSwitchNumberFontSize,
            isEnabled: inputMode != .number,
            action: { switchInputMode(.number) }
        )
            .frame(width: leftModeSwitchButtonWidth, height: height)
    }

    private func leftModeSwitchLatinButton(height: CGFloat) -> some View {
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

    private func leftModeSwitchKanaButton(height: CGFloat, fontSize: CGFloat) -> some View {
        ActionKeyButton(
            title: kanaModeSwitchButtonTitle,
            fontSize: fontSize,
            isEnabled: inputMode != .kana,
            action: { switchInputMode(.kana) }
        )
            .frame(width: leftModeSwitchButtonWidth, height: height)
    }

    private func leftModeSwitchEmojiButton(height: CGFloat) -> some View {
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
    private func compactLeftModeSwitchButton(slot slotIndex: Int, height: CGFloat) -> some View {
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

    private var threeByThreeKanaRows: [[FlickKanaSet]] {
        FlickKanaLayout.rows(for: activeKanaModifierMode, layoutMode: .threeByThreePlusWa).map { row in
            row.map {
                displayedKanaForKanaCharacterModeIfNeeded($0.remapped(for: directionProfile))
            }
        }
    }

    private var threeByThreeKanaLeftColumn: some View {
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

    private func threeByThreeKanaMainCluster(
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
    private func threeByThreeMainKey(_ kana: FlickKanaSet, rowIndex: Int) -> some View {
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
    private func threeByThreeLeftColumnButton(rowIndex: Int, rowHeight: CGFloat) -> some View {
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
    private func threeByThreeRightColumnButton(rowIndex: Int, rowHeight: CGFloat, rowSpacing: CGFloat) -> some View {
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

    private var landscapeNumberNarrowGrid: some View {
        let rowHeight = mainFlickKeyHeight
        let rowSpacing: CGFloat = keyboardRowSpacing
        // Keep number-mode keys the same width as mode-switch keys.
        let keyWidth = leftModeSwitchButtonWidth
        let numberClusterOnLeft = landscapeNumberPaneSide == .left

        return HStack(spacing: 0) {
            landscapeNumberCompactColumns(
                rowHeight: rowHeight,
                rowSpacing: rowSpacing,
                keyWidth: keyWidth,
                numberClusterOnLeft: numberClusterOnLeft
            )
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func landscapeNumberCompactColumns(
        rowHeight: CGFloat,
        rowSpacing: CGFloat,
        keyWidth: CGFloat,
        numberClusterOnLeft: Bool
    ) -> some View {
        HStack(spacing: rowSpacing) {
            if numberClusterOnLeft {
                landscapeNumberModeSwitchColumn(rowHeight: rowHeight, rowSpacing: rowSpacing)
                landscapeNumberMainKeyCluster(
                    rowHeight: rowHeight,
                    rowSpacing: rowSpacing,
                    keyWidth: keyWidth
                )
                landscapeNumberUtilityColumn(
                    rowHeight: rowHeight,
                    rowSpacing: rowSpacing,
                    keyWidth: keyWidth
                )
                landscapeNumberSymbolPanel(
                    rowHeight: rowHeight,
                    rowSpacing: rowSpacing,
                    keyWidth: keyWidth
                )
            } else {
                landscapeNumberModeSwitchColumn(rowHeight: rowHeight, rowSpacing: rowSpacing)
                landscapeNumberSymbolPanel(
                    rowHeight: rowHeight,
                    rowSpacing: rowSpacing,
                    keyWidth: keyWidth
                )
                landscapeNumberMainKeyCluster(
                    rowHeight: rowHeight,
                    rowSpacing: rowSpacing,
                    keyWidth: keyWidth
                )
                landscapeNumberUtilityColumn(
                    rowHeight: rowHeight,
                    rowSpacing: rowSpacing,
                    keyWidth: keyWidth
                )
            }
        }
    }

    private func landscapeNumberModeSwitchColumn(
        rowHeight: CGFloat,
        rowSpacing: CGFloat
    ) -> some View {
        VStack(spacing: rowSpacing) {
            ForEach(0..<4, id: \.self) { rowIndex in
                threeByThreeLeftColumnButton(rowIndex: rowIndex, rowHeight: rowHeight)
            }
        }
    }

    private func landscapeNumberMainKeyCluster(
        rowHeight: CGFloat,
        rowSpacing: CGFloat,
        keyWidth: CGFloat
    ) -> some View {
        VStack(spacing: rowSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: rowSpacing) {
                    ForEach(row) { kana in
                        threeByThreeMainKey(kana, rowIndex: rowIndex)
                            .frame(width: keyWidth, height: rowHeight)
                    }
                }
                .zIndex(zIndex(for: rowIndex))
            }
        }
    }

    private func landscapeNumberUtilityColumn(
        rowHeight: CGFloat,
        rowSpacing: CGFloat,
        keyWidth: CGFloat
    ) -> some View {
        VStack(spacing: rowSpacing) {
            ActionKeyButton(
                title: "⌫",
                accessibilityLabel: "削除",
                fontSize: 26,
                repeatsWhileHolding: true,
                repeatInitialDelay: keyRepeatInitialDelay,
                repeatInterval: keyRepeatInterval,
                action: onDeleteBackward
            )
                .frame(width: keyWidth, height: rowHeight)

            spaceActionKeyButton(title: "")
                .frame(width: keyWidth, height: rowHeight)

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
            .frame(width: keyWidth, height: rowHeight, alignment: .top)
            .zIndex(KeyboardLayerZIndex.rightEdgeUtilityColumn)

            Color.clear
                .allowsHitTesting(false)
                .frame(width: keyWidth, height: rowHeight)
        }
    }

    private func landscapeNumberSymbolPanel(
        rowHeight: CGFloat,
        rowSpacing: CGFloat,
        keyWidth: CGFloat
    ) -> some View {
        VStack(spacing: rowSpacing) {
            ForEach(Array(landscapeNumberSymbolPanelRows.enumerated()), id: \.offset) { _, symbols in
                HStack(spacing: rowSpacing) {
                    ForEach(symbols, id: \.self) { symbol in
                        ActionKeyButton(
                            title: symbol,
                            fontSize: 20,
                            action: { commitText(symbol) }
                        )
                            .frame(width: keyWidth, height: rowHeight)
                    }
                }
            }
        }
    }

    private var emojiKeyboardView: some View {
        KeyboardRootEmojiKeyboardSectionView(
            selectedEmojiCategory: $selectedEmojiCategory,
            keyboardRowSpacing: keyboardRowSpacing,
            emojiGridColumns: emojiGridColumns,
            emojiGridSpacing: emojiGridSpacing,
            compactEmojiKeyHeight: compactEmojiKeyHeight,
            mainFlickKeyHeight: mainFlickKeyHeight,
            fourRowAlignedTopContentHeight: fourRowAlignedTopContentHeight,
            fourRowAlignedClusterHeight: fourRowAlignedClusterHeight,
            keyRepeatInitialDelay: keyRepeatInitialDelay,
            keyRepeatInterval: keyRepeatInterval,
            onTextInput: commitEmojiKaomojiSymbolText,
            onSwitchToKana: { switchInputMode(.kana) },
            onDeleteBackward: onDeleteBackward
        )
    }

    private var symbolKeyboardView: some View {
        KeyboardRootSymbolKeyboardSectionView(
            selectedSymbolCategory: $selectedSymbolCategory,
            basicSymbolOrder: basicSymbolOrder,
            temperatureUnit: temperatureUnit,
            keyboardRowSpacing: keyboardRowSpacing,
            symbolGridColumns: symbolGridColumns,
            emojiGridSpacing: emojiGridSpacing,
            compactEmojiKeyHeight: compactEmojiKeyHeight,
            mainFlickKeyHeight: mainFlickKeyHeight,
            fourRowAlignedTopContentHeight: fourRowAlignedTopContentHeight,
            fourRowAlignedClusterHeight: fourRowAlignedClusterHeight,
            keyRepeatInitialDelay: keyRepeatInitialDelay,
            keyRepeatInterval: keyRepeatInterval,
            onTextInput: commitEmojiKaomojiSymbolText,
            onSwitchToKana: { switchInputMode(.kana) },
            onDeleteBackward: onDeleteBackward
        )
    }

    private func kaomojiSearchPrefixButton(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(
                    isSelected
                        ? KeyboardThemePalette.keyLabel
                        : KeyboardThemePalette.keyLabelSecondary
                )
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            isSelected
                                ? KeyboardThemePalette.categoryButtonBackgroundSelected
                                : KeyboardThemePalette.categoryButtonBackground
                        )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(
                            isSelected
                                ? KeyboardThemePalette.keyBorderEmphasis
                                : KeyboardThemePalette.keyBorder,
                            lineWidth: isSelected ? 1.2 : 1
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func kaomojiSearchReadingButton(
        reading: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(reading)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .foregroundStyle(
                    isSelected
                        ? KeyboardThemePalette.keyLabel
                        : KeyboardThemePalette.keyLabelSecondary
                )
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            isSelected
                                ? KeyboardThemePalette.categoryButtonBackgroundSelected
                                : KeyboardThemePalette.categoryButtonBackground
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(
                            isSelected
                                ? KeyboardThemePalette.keyBorderEmphasis
                                : KeyboardThemePalette.keyBorder,
                            lineWidth: isSelected ? 1.2 : 1
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private var kaomojiKeyboardView: some View {
        GeometryReader { geometry in
            let categoryRows = kaomojiRows(
                for: geometry.size.width,
                entries: selectedKaomojiCategoryEntries
            )
            let searchResultRows = kaomojiRows(
                for: geometry.size.width,
                entries: selectedKaomojiSearchResults
            )

            VStack(spacing: keyboardRowSpacing) {
                ScrollView(.vertical, showsIndicators: false) {
                    if isKaomojiSearchCategorySelected {
                        VStack(alignment: .leading, spacing: keyboardRowSpacing) {
                            Text("1) 上の文字を選ぶ  2) 読みを選ぶ  3) 下の顔文字をタップ")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(KeyboardThemePalette.keyLabelSecondary)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    kaomojiSearchPrefixButton(
                                        title: "全",
                                        isSelected: selectedKaomojiReadingPrefix == nil,
                                        action: { selectKaomojiReadingPrefix(nil) }
                                    )

                                    ForEach(KaomojiCatalog.readingIndexHeadings, id: \.self) { heading in
                                        kaomojiSearchPrefixButton(
                                            title: heading,
                                            isSelected: selectedKaomojiReadingPrefix == heading,
                                            action: { selectKaomojiReadingPrefix(heading) }
                                        )
                                    }
                                }
                            }

                            if let selectedKaomojiReading,
                                !selectedKaomojiReading.isEmpty {
                                HStack(spacing: 8) {
                                    Text("よみ: \(selectedKaomojiReading)")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(KeyboardThemePalette.keyLabelSecondary)

                                    Spacer(minLength: 0)

                                    Button(action: { self.selectedKaomojiReading = nil }) {
                                        Text("読みを選び直す")
                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                            .lineLimit(1)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .foregroundStyle(KeyboardThemePalette.keyLabelSecondary)
                                            .background(
                                                Capsule(style: .continuous)
                                                    .fill(KeyboardThemePalette.categoryButtonBackground)
                                            )
                                            .overlay(
                                                Capsule(style: .continuous)
                                                    .stroke(KeyboardThemePalette.keyBorder, lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }

                                Rectangle()
                                    .fill(KeyboardThemePalette.thinDivider)
                                    .frame(height: 1)
                                    .padding(.vertical, 4)

                                if searchResultRows.isEmpty {
                                    Text("該当する顔文字がありません")
                                        .font(.system(size: 12, weight: .regular, design: .rounded))
                                        .foregroundStyle(KeyboardThemePalette.keyLabelSecondary)
                                } else {
                                    Text("候補をタップして入力")
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundStyle(KeyboardThemePalette.keyLabelSecondary)

                                    kaomojiRowLayoutsView(
                                        searchResultRows,
                                        availableWidth: geometry.size.width,
                                        sectionID: "kaomoji-search-results"
                                    )
                                }
                            } else {
                                LazyVGrid(columns: kaomojiSearchReadingColumns, spacing: keyboardRowSpacing) {
                                    ForEach(kaomojiSearchReadings, id: \.self) { reading in
                                        kaomojiSearchReadingButton(
                                            reading: reading,
                                            isSelected: selectedKaomojiReading == reading,
                                            action: { selectedKaomojiReading = reading }
                                        )
                                    }
                                }

                                if kaomojiSearchReadings.isEmpty {
                                    Text("該当する読みがありません")
                                        .font(.system(size: 12, weight: .regular, design: .rounded))
                                        .foregroundStyle(KeyboardThemePalette.keyLabelSecondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                    } else {
                        LazyVStack(alignment: .leading, spacing: keyboardRowSpacing) {
                            kaomojiRowLayoutsView(
                                categoryRows,
                                availableWidth: geometry.size.width,
                                sectionID: "kaomoji-category-\(selectedKaomojiCategoryID)"
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                    }
                }
                .frame(height: fourRowAlignedTopContentHeight)

                HStack(spacing: keyboardRowSpacing) {
                    ActionKeyButton(
                        title: "あい",
                        fixedWidth: 56,
                        action: { switchInputMode(.kana) }
                    )
                        .frame(height: mainFlickKeyHeight)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: keyboardRowSpacing) {
                            ForEach(kaomojiCategories) { category in
                                KaomojiCategoryKeyButton(
                                    icon: category.icon,
                                    accessibilityLabel: category.title,
                                    isSelected: selectedKaomojiCategoryID == category.id,
                                    action: { selectKaomojiCategory(category) }
                                )
                                .frame(width: kaomojiCategoryButtonWidth)
                                .frame(height: mainFlickKeyHeight)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    ActionKeyButton(
                        title: "⌫",
                        accessibilityLabel: "削除",
                        fontSize: 26,
                        fixedWidth: 56,
                        repeatsWhileHolding: true,
                        repeatInitialDelay: keyRepeatInitialDelay,
                        repeatInterval: keyRepeatInterval,
                        action: onDeleteBackward
                    )
                        .frame(height: mainFlickKeyHeight)
                }
                .frame(height: mainFlickKeyHeight)
            }
            .frame(height: fourRowAlignedClusterHeight, alignment: .top)
        }
        .frame(height: fourRowAlignedClusterHeight, alignment: .top)
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

    private var emojiHeaderTitle: String {
        switch emojiInputSubmode {
        case .emoji:
            return selectedEmojiCategory.frenchName
        case .kaomoji:
            return selectedKaomojiCategory.title
        case .symbols:
            return selectedSymbolCategory.frenchName
        }
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

    private func landscapeCandidateSidebarWidth() -> CGFloat {
        let screenWidth = max(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
        let ratio: CGFloat = isKanaFiveByTwoMode ? 0.34 : 0.4
        let desired = screenWidth * ratio
        return min(max(desired, 180), 320)
    }

    private var landscapeEmptyCandidatePlaceholderCount: Int { 6 }

    private var landscapeKanaCandidateSidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            let showsWrapperOnly = showsParenthesesWrapper && composingText.isEmpty

            if !composingText.isEmpty || showsWrapperOnly {
                Text(showsWrapperOnly ? "()" : conversionStateLabel)
                    .font(.system(size: candidateStateFontSize, weight: .bold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(conversionStateColor.opacity(0.95))
                    )

                if !showsWrapperOnly, canTapComposingTextToCommit {
                    let showsKatakanaCommitFeedback = isShowingKatakanaCommitFeedback(for: composingText)

                    Button {
                        handleComposingTextCommitTap()
                    } label: {
                        if showsParenthesesWrapper {
                            HStack(spacing: 0) {
                                Text("(")
                                    .foregroundStyle(
                                        showsKatakanaCommitFeedback
                                            ? Color.white
                                            : accentColor
                                    )
                                Text(composingText)
                                    .foregroundStyle(
                                        showsKatakanaCommitFeedback
                                            ? Color.white
                                            : keyLabelColor.opacity(0.9)
                                    )
                                Text(")")
                                    .foregroundStyle(
                                        showsKatakanaCommitFeedback
                                            ? Color.white
                                            : accentColor
                                    )
                            }
                            .font(.system(size: candidateTextFontSize, weight: .semibold))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(
                                        showsKatakanaCommitFeedback
                                            ? accentColor.opacity(0.95)
                                            : KeyboardThemePalette.candidateHeaderChipBackground
                                    )
                            )
                        } else {
                            Text(composingText)
                                .font(.system(size: candidateTextFontSize, weight: .semibold))
                                .foregroundStyle(
                                    showsKatakanaCommitFeedback
                                        ? Color.white
                                        : keyLabelColor.opacity(0.9)
                                )
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(
                                            showsKatakanaCommitFeedback
                                                ? accentColor.opacity(0.95)
                                                : KeyboardThemePalette.candidateHeaderChipBackground
                                        )
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("通常タップで変換せずに確定。ロングタップでカタカナ確定")
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.4)
                            .onEnded { _ in
                                handleComposingTextCommitLongPress()
                            }
                    )
                } else if !showsWrapperOnly {
                    if showsParenthesesWrapper {
                        HStack(spacing: 0) {
                            Text("(")
                                .foregroundStyle(accentColor)
                            Text(composingText)
                                .foregroundStyle(keyLabelColor.opacity(0.9))
                            Text(")")
                                .foregroundStyle(accentColor)
                        }
                        .font(.system(size: candidateTextFontSize, weight: .semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(KeyboardThemePalette.candidateHeaderChipBackground)
                        )
                    } else {
                        Text(composingText)
                            .font(.system(size: candidateTextFontSize, weight: .semibold))
                            .foregroundStyle(keyLabelColor.opacity(0.9))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(KeyboardThemePalette.candidateHeaderChipBackground)
                            )
                    }
                }
            }

            if conversionCandidates.isEmpty {
                if !(showsParenthesesWrapper && composingText.isEmpty) {
                    ForEach(0..<landscapeEmptyCandidatePlaceholderCount, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(KeyboardThemePalette.candidateHeaderPlaceholderBackground)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 24)
                    }
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(conversionCandidates.enumerated()), id: \.offset) { index, candidate in
                            let isSelected = selectedConversionCandidateIndex == index

                            Button {
                                onSelectConversionCandidate(index)
                            } label: {
                                if showsParenthesesWrapper {
                                    HStack(spacing: 0) {
                                        Text("(")
                                            .foregroundStyle(isSelected ? Color.white : accentColor)
                                        Text(candidate)
                                            .foregroundStyle(isSelected ? Color.white : keyLabelColor)
                                        Text(")")
                                            .foregroundStyle(isSelected ? Color.white : accentColor)
                                    }
                                    .font(.system(size: candidateTextFontSize, weight: .semibold))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .fill(
                                                isSelected
                                                    ? accentColor.opacity(0.9)
                                                    : KeyboardThemePalette.candidateHeaderChipBackground
                                            )
                                    )
                                } else {
                                    Text(candidate)
                                        .font(.system(size: candidateTextFontSize, weight: .semibold))
                                        .foregroundStyle(isSelected ? Color.white : keyLabelColor)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                        .background(
                                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                .fill(
                                                    isSelected
                                                        ? accentColor.opacity(0.9)
                                                        : KeyboardThemePalette.candidateHeaderChipBackground
                                                )
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(KeyboardThemePalette.candidateHeaderSubtleBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(KeyboardThemePalette.candidateHeaderBorder, lineWidth: 1)
        )
    }

    private var landscapeLatinSuggestionSidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            if latinSuggestionQuery.isEmpty {
                ForEach(0..<landscapeEmptyCandidatePlaceholderCount, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(KeyboardThemePalette.candidateHeaderPlaceholderBackground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 24)
                }
            } else if latinSuggestions.isEmpty {
                Text("候補なし")
                    .font(.system(size: candidateTextFontSize, weight: .regular))
                    .foregroundStyle(keyLabelColor.opacity(0.6))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(KeyboardThemePalette.candidateHeaderPlaceholderBackground)
                    )
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(latinSuggestions.enumerated()), id: \.offset) { index, candidate in
                            Button {
                                onSelectConversionCandidate(index)
                            } label: {
                                Text(candidate)
                                    .font(.system(size: candidateTextFontSize, weight: .semibold))
                                    .foregroundStyle(keyLabelColor)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .fill(KeyboardThemePalette.candidateHeaderChipBackground)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(KeyboardThemePalette.candidateHeaderSubtleBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(KeyboardThemePalette.candidateHeaderBorder, lineWidth: 1)
        )
    }

    private var landscapeLatinReferenceClusterHeight: CGFloat {
        // ラテン横画面の主要クラスターは4段固定。
        mainFlickKeyHeight * 4 + keyboardRowSpacing * 3
    }

    @ViewBuilder
    private var landscapeLatinSwappableMainCluster: some View {
        if usesLandscapeLatinTypewriterLayout {
            landscapeLatinTypewriterMainCluster
        } else if usesThreeByThreeGridForNumberOrLatin {
            landscapeLatinThreeByThreeMainCluster
        } else {
            keyboardMainContent
        }
    }

    private var landscapeLatinThreeByThreeMainCluster: some View {
        let rowHeight = mainFlickKeyHeight
        let rowSpacing: CGFloat = keyboardRowSpacing

        return VStack(spacing: rowSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: rowSpacing) {
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

    private var landscapeKanaFiveByTwoLeftColumn: some View {
        let modeSwitchHeight: CGFloat = mainFlickKeyHeight

        return VStack(spacing: keyboardRowSpacing) {
            compactLeftModeSwitchButton(slot: 0, height: modeSwitchHeight)

            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, _ in
                compactLeftModeSwitchButton(slot: rowIndex + 1, height: modeSwitchHeight)
            }

            if rows.count < 3 {
                compactLeftModeSwitchButton(slot: rows.count + 1, height: modeSwitchHeight)
            }
        }
    }

    private var landscapeKanaFiveByTwoMainCluster: some View {
        VStack(spacing: keyboardRowSpacing) {
            HStack(spacing: keyboardRowSpacing) {
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

            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: keyboardRowSpacing) {
                    ForEach(row) { kana in
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

                            FlickKeyView(
                                kana: renderedKana,
                                onCommit: commitText,
                                showsDirectionalHints: showsFlickGuideCharacters,
                                idleReplacement: rowKeyIdleReplacement(for: renderedKana),
                                longPressCandidates: longPressCandidates(for: kana),
                                longPressCandidatePanelPlacement: longPressCandidatePanelPlacement(forRowIndex: rowIndex),
                                allowsDirectionalFlick: allowsDirectionalFlick(for: kana),
                                downDirectionalHintFontScale: inputMode == .number
                                    ? numberDownDirectionalHintScale
                                    : 1,
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
                }
                .padding(horizontalInsetsForMainRow(rowIndex))
                .zIndex(zIndex(for: rowIndex))
            }

            HStack(spacing: keyboardRowSpacing) {
                if showsNextKeyboardKey {
                    ActionKeyButton(title: "🌐", fixedWidth: 54, action: onAdvanceKeyboard)
                        .frame(height: mainFlickKeyHeight)
                }

                ActionKeyButton(
                    title: "⌫",
                    accessibilityLabel: "削除",
                    fontSize: 26,
                    fixedWidth: 64,
                    repeatsWhileHolding: true,
                    repeatInitialDelay: keyRepeatInitialDelay,
                    repeatInterval: keyRepeatInterval,
                    action: onDeleteBackward
                )
                    .frame(height: mainFlickKeyHeight)

                spaceKeyButton(fixedWidth: nil, keyHeight: mainFlickKeyHeight)

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
                    .frame(width: kanaFiveByTwoTrailingKeyWidth, height: selectorKeySize)
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
                    .frame(width: kanaFiveByTwoTrailingKeyWidth, height: selectorKeySize)

                ActionKeyButton(
                    title: returnActionKeyTitle,
                    systemImageName: returnActionKeySystemImageName,
                    accessibilityLabel: returnActionKeyAccessibilityLabel,
                    fontSize: returnActionKeyFontSize,
                    fixedWidth: 72,
                    isEnabled: isReturnKeyEnabled,
                    onLongPress: returnKeyKatakanaLongPressAction,
                    onDoubleTap: returnKeyKatakanaDoubleTapAction,
                    doubleTapThreshold: katakanaCommitDoubleTapThreshold,
                    prefersImmediateSingleTapWhenDoubleTapEnabled: true,
                    action: onReturn
                )
                    .frame(height: mainFlickKeyHeight)
            }
            .zIndex(zIndex(for: rows.count))
        }
    }

    private var landscapeLatinModeSwitchColumn: some View {
        VStack(spacing: keyboardRowSpacing) {
            leftModeSwitchNumberButton(height: mainFlickKeyHeight)
            leftModeSwitchLatinButton(height: mainFlickKeyHeight)
            leftModeSwitchKanaButton(
                height: mainFlickKeyHeight,
                fontSize: compactKanaModeSwitchButtonFontSize
            )
            leftModeSwitchEmojiButton(height: mainFlickKeyHeight)
        }
    }

    private let landscapeLatinTypewriterMiddleRowOffsetFactor: CGFloat = 0.25
    private let landscapeLatinTypewriterBottomRowOffsetFromMiddleFactor: CGFloat = 0.5

    private func landscapeLatinTypewriterLetterAnchorOffsetFactor(_ rowIndex: Int) -> CGFloat {
        switch rowIndex {
        case 1:
            return landscapeLatinTypewriterMiddleRowOffsetFactor
        case 2:
            return landscapeLatinTypewriterMiddleRowOffsetFactor
                + landscapeLatinTypewriterBottomRowOffsetFromMiddleFactor
        default:
            return 0
        }
    }

    private func landscapeLatinTypewriterLeadingControlPitchCount(_ row: [FlickKanaSet]) -> CGFloat {
        CGFloat(row.prefix { isLatinShiftKey($0) }.count)
    }

    private func landscapeLatinTypewriterRowInsets(
        leadingOffsetFactor: CGFloat,
        keyPitch: CGFloat
    ) -> EdgeInsets {
        EdgeInsets(
            top: 0,
            leading: leadingOffsetFactor * keyPitch,
            bottom: 0,
            trailing: 0
        )
    }

    private func landscapeLatinTypewriterRowInsets(_ rowIndex: Int, keyPitch: CGFloat) -> EdgeInsets {
        landscapeLatinTypewriterRowInsets(
            leadingOffsetFactor: landscapeLatinTypewriterLetterAnchorOffsetFactor(rowIndex),
            keyPitch: keyPitch
        )
    }

    private func landscapeLatinTypewriterRowInsets(_ rowIndex: Int) -> EdgeInsets {
        guard usesLandscapeLatinTypewriterLayout else {
            return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        }

        let fallbackKeyPitch = mainFlickKeyHeight + keyboardRowSpacing
        return landscapeLatinTypewriterRowInsets(rowIndex, keyPitch: fallbackKeyPitch)
    }

    @ViewBuilder
    private func landscapeLatinTypewriterKey(
        _ kana: FlickKanaSet,
        rowIndex: Int,
        fixedWidth: CGFloat? = nil,
        shiftFixedWidth: CGFloat? = nil
    ) -> some View {
        if isLatinShiftKey(kana) {
            let shiftKey = LatinShiftKeyButton(
                isOn: latinShiftState != .off,
                isLocked: latinShiftState == .locked,
                onTap: handleLatinShiftTap,
                onLongPress: handleLatinShiftLongPress
            )
            let resolvedShiftWidth = shiftFixedWidth ?? fixedWidth

            if let resolvedShiftWidth {
                shiftKey
                    .frame(width: resolvedShiftWidth, height: mainFlickKeyHeight)
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
                mainLabelFontSize: 25,
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

            if let fixedWidth {
                letterKey
                    .frame(width: fixedWidth, height: mainFlickKeyHeight)
            } else {
                letterKey
                    .frame(maxWidth: .infinity)
                    .frame(height: mainFlickKeyHeight)
            }
        }
    }

    private func landscapeLatinInlineDeleteKey(fixedWidth: CGFloat) -> some View {
        ActionKeyButton(
            title: "⌫",
            accessibilityLabel: "削除",
            fontSize: 26,
            repeatsWhileHolding: true,
            repeatInitialDelay: keyRepeatInitialDelay,
            repeatInterval: keyRepeatInterval,
            action: onDeleteBackward
        )
            .frame(width: fixedWidth, height: mainFlickKeyHeight)
    }

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

    private func landscapeLatinInlineReturnKey(fixedWidth: CGFloat) -> some View {
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
            .frame(width: fixedWidth, height: mainFlickKeyHeight)
    }

    private func landscapeLatinInlineApostropheKey(fixedWidth: CGFloat) -> some View {
        ActionKeyButton(
            title: "'",
            fontSize: 20,
            action: { commitText("'") }
        )
            .frame(width: fixedWidth, height: mainFlickKeyHeight)
    }

    private var landscapeLatinInlineActionTypewriterMainCluster: some View {
        GeometryReader { geometry in
            let topRow = rows.indices.contains(0) ? rows[0] : []
            let middleRow = rows.indices.contains(1) ? rows[1] : []
            let bottomRow = rows.indices.contains(2)
                ? landscapeBottomRowWithInlinePunctuation(rows[2])
                : []
            let inlineReturnRowIndex = landscapeLatinInlineReturnRowIndex

            let topRawLeadingOffsetFactor = landscapeLatinTypewriterLetterAnchorOffsetFactor(0)
                - landscapeLatinTypewriterLeadingControlPitchCount(topRow)
            let middleRawLeadingOffsetFactor = landscapeLatinTypewriterLetterAnchorOffsetFactor(1)
                - landscapeLatinTypewriterLeadingControlPitchCount(middleRow)
            let bottomRawLeadingOffsetFactor = landscapeLatinTypewriterLetterAnchorOffsetFactor(2)
                - landscapeLatinTypewriterLeadingControlPitchCount(bottomRow)

            let minimumRawLeadingOffsetFactor = min(
                topRawLeadingOffsetFactor,
                middleRawLeadingOffsetFactor,
                bottomRawLeadingOffsetFactor
            )

            let topLeadingOffsetFactor = topRawLeadingOffsetFactor - minimumRawLeadingOffsetFactor
            let middleLeadingOffsetFactor = middleRawLeadingOffsetFactor - minimumRawLeadingOffsetFactor
            let bottomLeadingOffsetFactor = bottomRawLeadingOffsetFactor - minimumRawLeadingOffsetFactor

            let rowSpecs: [(keyPitchCount: CGFloat, offsetFactor: CGFloat)] = [
                (CGFloat(topRow.count + 1), topLeadingOffsetFactor),
                (
                    CGFloat(
                        middleRow.count
                            + (inlineReturnRowIndex == 1 ? 1 : 0)
                            + (needsQwertyMiddleRowApostrophe ? 1 : 0)
                    ),
                    middleLeadingOffsetFactor
                ),
                (
                    CGFloat(bottomRow.count + (inlineReturnRowIndex == 2 ? 1 : 0)) + 1,
                    bottomLeadingOffsetFactor
                )
            ].filter { $0.keyPitchCount > 0 }

            let resolvedKeyWidth = max(
                1,
                rowSpecs
                    .map { spec in
                        let denominator = spec.keyPitchCount + spec.offsetFactor

                        guard denominator > 0 else {
                            return 1
                        }

                        let numerator = geometry.size.width
                            - keyboardRowSpacing
                            * (max(spec.keyPitchCount - 1, 0) + spec.offsetFactor)

                        return numerator / denominator
                    }
                    .min() ?? 1
            )
            let keyPitch = resolvedKeyWidth + keyboardRowSpacing
            let topInsets = landscapeLatinTypewriterRowInsets(
                leadingOffsetFactor: topLeadingOffsetFactor,
                keyPitch: keyPitch
            )
            let middleInsets = landscapeLatinTypewriterRowInsets(
                leadingOffsetFactor: middleLeadingOffsetFactor,
                keyPitch: keyPitch
            )
            let bottomInsets = landscapeLatinTypewriterRowInsets(
                leadingOffsetFactor: bottomLeadingOffsetFactor,
                keyPitch: keyPitch
            )
            let shiftKeyExtraWidth = max(0, (resolvedKeyWidth + keyboardRowSpacing) / 2)
            let widenedShiftKeyWidth = resolvedKeyWidth + shiftKeyExtraWidth
            let rightShiftIndexInBottomRow = bottomRow.firstIndex(where: isLandscapeLatinRightShiftKey)
                ?? max(bottomRow.count - 1, 0)
            let referenceRightEdgeX = bottomInsets.leading
                + CGFloat(rightShiftIndexInBottomRow + 1) * resolvedKeyWidth
                + CGFloat(rightShiftIndexInBottomRow) * keyboardRowSpacing
                + shiftKeyExtraWidth * 2
            let topRowLeadingKeyCount = topRow.count
            let topDeleteKeyWidth = max(
                resolvedKeyWidth,
                referenceRightEdgeX
                    - topInsets.leading
                    - CGFloat(topRowLeadingKeyCount) * resolvedKeyWidth
                    - CGFloat(topRowLeadingKeyCount) * keyboardRowSpacing
            )
            let middleRowLeadingKeyCount = middleRow.count
                + (needsQwertyMiddleRowApostrophe ? 1 : 0)
            let middleReturnKeyWidth = max(
                resolvedKeyWidth,
                referenceRightEdgeX
                    - middleInsets.leading
                    - CGFloat(middleRowLeadingKeyCount) * resolvedKeyWidth
                    - CGFloat(middleRowLeadingKeyCount) * keyboardRowSpacing
            )
            VStack(alignment: .leading, spacing: keyboardRowSpacing) {
                HStack(spacing: keyboardRowSpacing) {
                    ForEach(Array(topRow.enumerated()), id: \.offset) { _, kana in
                        landscapeLatinTypewriterKey(kana, rowIndex: 0, fixedWidth: resolvedKeyWidth)
                    }

                    landscapeLatinInlineDeleteKey(fixedWidth: topDeleteKeyWidth)
                }
                .padding(topInsets)
                .zIndex(zIndex(for: 0))

                HStack(spacing: keyboardRowSpacing) {
                    ForEach(Array(middleRow.enumerated()), id: \.offset) { _, kana in
                        landscapeLatinTypewriterKey(kana, rowIndex: 1, fixedWidth: resolvedKeyWidth)
                    }

                    if needsQwertyMiddleRowApostrophe {
                        landscapeLatinInlineApostropheKey(fixedWidth: resolvedKeyWidth)
                    }

                    if inlineReturnRowIndex == 1 {
                        landscapeLatinInlineReturnKey(fixedWidth: middleReturnKeyWidth)
                    }
                }
                .padding(middleInsets)
                .zIndex(zIndex(for: 1))

                HStack(spacing: keyboardRowSpacing) {
                    ForEach(Array(bottomRow.enumerated()), id: \.offset) { _, kana in
                        landscapeLatinTypewriterKey(
                            kana,
                            rowIndex: 2,
                            fixedWidth: resolvedKeyWidth,
                            shiftFixedWidth: widenedShiftKeyWidth
                        )
                    }

                    if inlineReturnRowIndex == 2 {
                        landscapeLatinInlineReturnKey(fixedWidth: resolvedKeyWidth)
                    }
                }
                .padding(bottomInsets)
                .zIndex(zIndex(for: 2))

                HStack(spacing: keyboardRowSpacing) {
                    if showsNextKeyboardKey {
                        ActionKeyButton(title: "🌐", fixedWidth: 54, action: onAdvanceKeyboard)
                            .frame(height: mainFlickKeyHeight)
                    }

                    latinSpaceLeftActionButtons(fixedWidth: 44, keyHeight: mainFlickKeyHeight)

                    spaceKeyButton(fixedWidth: nil, keyHeight: mainFlickKeyHeight)

                    latinSpaceRightActionButtons(fixedWidth: 44, keyHeight: mainFlickKeyHeight)
                }
                .zIndex(zIndex(for: rows.count))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var landscapeLatinTypewriterMainCluster: some View {
        Group {
            if usesLandscapeLatinTypewriterLayout {
                landscapeLatinInlineActionTypewriterMainCluster
            } else {
                VStack(spacing: keyboardRowSpacing) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                        HStack(spacing: keyboardRowSpacing) {
                            ForEach(row) { kana in
                                landscapeLatinTypewriterKey(kana, rowIndex: rowIndex)
                            }
                        }
                        .padding(landscapeLatinTypewriterRowInsets(rowIndex))
                        .zIndex(zIndex(for: rowIndex))
                    }

                    HStack(spacing: keyboardRowSpacing) {
                        if showsNextKeyboardKey {
                            ActionKeyButton(title: "🌐", fixedWidth: 54, action: onAdvanceKeyboard)
                                .frame(height: compactActionKeyHeight)
                        }

                        ActionKeyButton(
                            title: "⌫",
                            accessibilityLabel: "削除",
                            fontSize: 26,
                            repeatsWhileHolding: true,
                            repeatInitialDelay: keyRepeatInitialDelay,
                            repeatInterval: keyRepeatInterval,
                            action: onDeleteBackward
                        )
                            .frame(maxWidth: .infinity)
                            .frame(height: compactActionKeyHeight)

                        spaceKeyButton(fixedWidth: nil)

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
                            .frame(height: compactActionKeyHeight)
                    }
                    .padding(.top, actionRowTopSpacing)
                    .zIndex(zIndex(for: rows.count))
                }
            }
        }
    }

    @ViewBuilder
    private var landscapeKanaFixedModeSwitchColumn: some View {
        if isKanaThreeByThreeMode {
            threeByThreeKanaLeftColumn
        } else if isKanaFiveByTwoMode {
            landscapeKanaFiveByTwoLeftColumn
        } else {
            Color.clear
                .allowsHitTesting(false)
                .frame(width: leftModeSwitchButtonWidth)
        }
    }

    @ViewBuilder
    private var landscapeKanaSwappableMainCluster: some View {
        if isKanaThreeByThreeMode {
            threeByThreeKanaMainCluster(
                kanaRows: threeByThreeKanaRows,
                rowHeight: mainFlickKeyHeight,
                rowSpacing: keyboardRowSpacing
            )
        } else if isKanaFiveByTwoMode {
            landscapeKanaFiveByTwoMainCluster
        } else {
            keyboardMainContent
        }
    }

    private var landscapeKanaReferenceClusterHeight: CGFloat {
        if isKanaThreeByThreeMode {
            // 3x3+わのかな塊は4段固定。
            return mainFlickKeyHeight * 4 + keyboardRowSpacing * 3
        }

        if isKanaFiveByTwoMode {
            // 5x2は上段数字 + かな段 + 下段アクションを含める。
            let topAndKanaRowCount = CGFloat(rows.count + 1)
            let verticalGapCount = CGFloat(rows.count + 1)
            return topAndKanaRowCount * mainFlickKeyHeight
                + mainFlickKeyHeight
                + verticalGapCount * keyboardRowSpacing
        }

        return 0
    }

    @ViewBuilder
    private var keyboardMainContent: some View {
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
