import Foundation
import SwiftUI
import UIKit

struct KeyboardRootView: View {
    let onTextInput: (String) -> Void
    let onDeleteBackward: () -> Void
    let onSpace: () -> Void
    let onReturn: () -> Void
    let onAdvanceKeyboard: () -> Void
    let onApplyKanaPostModifier: (KanaPostModifierButtonState) -> Bool
    let onInputModeChanged: (KeyboardInputMode) -> Void
    let showsNextKeyboardKey: Bool
    let directionProfile: FlickDirectionProfile
    let kanaLayoutMode: KanaLayoutMode
    let kanaModifierPlacementMode: KanaModifierPlacementMode
    let kanaPostModifierButtonState: KanaPostModifierButtonState
    let numberLayoutMode: NumberLayoutMode
    let latinLayoutMode: LatinLayoutMode
    let accentPaletteRawValue: String
    let keyboardBackgroundThemeRawValue: String
    let spaceToastTrigger: Int
    let returnKeySystemImageName: String?
    let isReturnKeyEnabled: Bool
    let showsFlickGuideCharacters: Bool
    let keyRepeatInitialDelay: TimeInterval
    let keyRepeatInterval: TimeInterval
    let initialSpaceToastText: String?

    private enum EmojiCategory: Int, CaseIterable, Identifiable {
        case people
        case animals
        case food
        case activities
        case travel
        case objects
        case symbols
        case flags

        var id: Int { rawValue }

        var icon: String {
            switch self {
            case .people: return "😀"
            case .animals: return "🐻"
            case .food: return "🍔"
            case .activities: return "🏀"
            case .travel: return "🚗"
            case .objects: return "💡"
            case .symbols: return "❤️"
            case .flags: return "🇫🇷"
            }
        }

        var frenchName: String {
            switch self {
            case .people: return "Personnes"
            case .animals: return "Animaux et nature"
            case .food: return "Nourriture et boissons"
            case .activities: return "Activités"
            case .travel: return "Voyages et lieux"
            case .objects: return "Objets"
            case .symbols: return "Symboles"
            case .flags: return "Drapeaux"
            }
        }

        var emojis: [String] {
            switch self {
            case .people:
                return AppleEmojiCatalog.people
            case .animals:
                return AppleEmojiCatalog.nature
            case .food:
                return AppleEmojiCatalog.foodAndDrink
            case .activities:
                return AppleEmojiCatalog.activity
            case .travel:
                return AppleEmojiCatalog.travelAndPlaces
            case .objects:
                return AppleEmojiCatalog.objects
            case .symbols:
                return AppleEmojiCatalog.symbols
            case .flags:
                return AppleEmojiCatalog.flags
            }
        }
    }

    private enum AccentPalette: String {
        case tuile
        case emeraude

        var color: Color {
            switch self {
            case .tuile:
                return Color(red: 136.0 / 255.0, green: 63.0 / 255.0, blue: 53.0 / 255.0)
            case .emeraude:
                return Color(red: 0.06, green: 0.73, blue: 0.56)
            }
        }
    }

    private enum KeyboardBackgroundTheme: String {
        case bleu
        case sakura

        var gradientStops: [Gradient.Stop] {
            switch self {
            case .bleu:
                return [
                    .init(color: Color(red: 0.89, green: 0.90, blue: 0.92), location: 0.0),
                    .init(color: Color(red: 0.8, green: 0.86, blue: 0.95), location: 0.34),
                    .init(color: Color(red: 0.9, green: 0.95, blue: 1.0), location: 1.0)
                ]
            case .sakura:
                return [
                    .init(color: Color(red: 0.89, green: 0.90, blue: 0.92), location: 0.0),
                    .init(color: Color(red: 0.95, green: 0.84, blue: 0.88), location: 0.34),
                    .init(color: Color(red: 1.0, green: 0.94, blue: 0.96), location: 1.0)
                ]
            }
        }
    }

    @State private var inputMode: KeyboardInputMode = .kana
    @State private var diacriticMode: DiacriticMode = .none
    @State private var kanaCharacterMode: KanaCharacterMode = .hiragana
    @State private var activeLayerIndex: Int? = nil
    @State private var spaceToastText: String? = nil
    @State private var spaceToastOpacity: Double = 0
    @State private var lastShownSpaceToastTrigger = -1
    @State private var latinShiftState: LatinShiftState = .off
    @State private var lastLatinShiftTapAt: Date? = nil
    @State private var selectedEmojiCategory: EmojiCategory = .people
    @State private var isKaomojiMode = false

    private let shiftDoubleTapThreshold: TimeInterval = 0.32
    private let keyLabelColor = Color(red: 0.11, green: 0.13, blue: 0.16)
    private let candidatePlaceholderHeight: CGFloat = 29
    private let keyboardRowSpacing: CGFloat = 6
    private let keyboardTopPadding: CGFloat = 3
    private let keyboardHorizontalPadding: CGFloat = 8
    private let keyboardBottomPadding: CGFloat = 20
    private let compactActionKeyHeight: CGFloat = 42
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

    private struct KaomojiRowLayout {
        let items: [String]
        let spacing: CGFloat
    }

    private var accentPalette: AccentPalette {
        AccentPalette(rawValue: accentPaletteRawValue) ?? .emeraude
    }

    private var accentColor: Color {
        accentPalette.color
    }

    private var keyboardBackgroundTheme: KeyboardBackgroundTheme {
        KeyboardBackgroundTheme(rawValue: keyboardBackgroundThemeRawValue) ?? .bleu
    }

    private var keyboardBackgroundGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(stops: keyboardBackgroundTheme.gradientStops),
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var transitionState: KeyboardModeTransitionState {
        get {
            KeyboardModeTransitionState(
                inputMode: inputMode,
                diacriticMode: diacriticMode,
                kanaCharacterMode: kanaCharacterMode,
                latinShiftState: latinShiftState,
                lastLatinShiftTapAt: lastLatinShiftTapAt,
                isKaomojiMode: isKaomojiMode,
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
            isKaomojiMode = newValue.isKaomojiMode
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
            return FlickKanaLayout.numberRows(for: directionProfile, layoutMode: numberLayoutMode)
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

    private var usesThreeByThreeGridForNumberOrLatin: Bool {
        (inputMode == .number || inputMode == .latin)
            && rows.count == 4
            && rows.allSatisfy { $0.count == 3 }
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

    private let punctuationKana = FlickKanaSet(
        label: "、",
        center: "、",
        up: "?",
        right: "!",
        down: "・",
        left: "。"
    )

    private var modifierSelectorKey: FlickKanaSet {
        let usesPostfixModifierSwap = inputMode == .kana && kanaModifierPlacementMode == .postfix
        let modeSwitchText = inputMode == .kana ? kanaCharacterMode.toggleGuide : "123"

        if usesPostfixModifierSwap {
            switch kanaPostModifierButtonState {
            case .kaomoji:
                return FlickKanaSet(
                    label: "^_^",
                    center: "^_^",
                    up: "",
                    right: modeSwitchText,
                    down: "…",
                    left: ""
                )
            case .smallKana:
                return FlickKanaSet(
                    label: "小",
                    center: "小",
                    up: "゜",
                    right: modeSwitchText,
                    down: "…",
                    left: "゛"
                )
            case .dakuten:
                return FlickKanaSet(
                    label: "゛",
                    center: "゛",
                    up: "゜",
                    right: modeSwitchText,
                    down: "…",
                    left: "゛"
                )
            case .handakuten:
                return FlickKanaSet(
                    label: "゜",
                    center: "゜",
                    up: "゜",
                    right: modeSwitchText,
                    down: "…",
                    left: "゛"
                )
            }
        }

        return FlickKanaSet(
            label: "小",
            center: "小",
            up: "゜",
            right: modeSwitchText,
            down: "…",
            left: "゛"
        )
    }

    private var emojiGridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: emojiGridSpacing), count: 9)
    }

    private func measuredKaomojiWidth(_ kaomoji: String) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: kaomojiFontSize, weight: .semibold)
        ]
        let textWidth = ceil((kaomoji as NSString).size(withAttributes: attributes).width)
        return max(kaomojiMinKeyWidth, textWidth + kaomojiHorizontalPadding * 2)
    }

    private func kaomojiRows(for availableWidth: CGFloat) -> [KaomojiRowLayout] {
        let minSpacing = keyboardRowSpacing * kaomojiMinInterItemSpacingMultiplier

        guard availableWidth > 0 else {
            return [KaomojiRowLayout(items: KaomojiCatalog.entries, spacing: minSpacing)]
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

        for kaomoji in KaomojiCatalog.entries {
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

    private let mainFlickKeyHeight: CGFloat = 46

    private var kanaThreeByThreeMainLabelFontSize: CGFloat {
        showsFlickGuideCharacters ? 24 : 26
    }

    private var modifierMainLabelFontSize: CGFloat {
        let baseSize: CGFloat = isKanaThreeByThreeMode
            ? kanaThreeByThreeMainLabelFontSize
            : 28

        let isPostfixKana = inputMode == .kana
            && kanaModifierPlacementMode == .postfix
        let centerLabel = modifierSelectorKey.center

        if isPostfixKana && centerLabel == "小" {
            return baseSize * 0.6
        }

        if isPostfixKana && centerLabel == "^_^" {
            return baseSize * 0.7
        }

        return baseSize
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

    private var showsCompactLeftModeSwitchButtons: Bool {
        if inputMode == .kana {
            return isKanaFiveByTwoMode
        }

        if inputMode == .latin {
            return latinLayoutMode == .qwerty || latinLayoutMode == .azerty
        }

        return false
    }

    private var usesWideLeftModeSwitchButtons: Bool {
        kanaLayoutMode == .threeByThreePlusWa && latinLayoutMode == .flick
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

    private var compactKanaModeSwitchButtonFontSize: CGFloat {
        usesWideLeftModeSwitchButtons ? 12 : 13
    }

    private var standardKanaModeSwitchButtonFontSize: CGFloat {
        usesWideLeftModeSwitchButtons ? 16 : 13
    }

    private var leftModeSwitchNumberFontSize: CGFloat {
        usesWideLeftModeSwitchButtons ? 20 : 12
    }

    private var leftModeSwitchLatinFontSize: CGFloat {
        usesWideLeftModeSwitchButtons ? 22 : 13
    }

    private var kaomojiTransitionIconFontSize: CGFloat {
        usesWideLeftModeSwitchButtons ? 32 : 28
    }

    private let kaomojiModeReturnIconFontSize: CGFloat = 32

    private var kanaFiveByTwoTopNumberKeys: [String] {
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    }

    @ViewBuilder
    private func compactLeftModeSwitchButton(slot slotIndex: Int, height: CGFloat) -> some View {
        switch slotIndex {
        case 0:
            ActionKeyButton(
                title: "123",
                fontSize: 12,
                isEnabled: inputMode != .number,
                action: { switchInputMode(.number) }
            )
                .frame(width: leftModeSwitchButtonWidth, height: height)
        case 1:
            ActionKeyButton(
                title: "abc",
                fontSize: 13,
                isEnabled: inputMode != .latin,
                action: { switchInputMode(.latin) }
            )
                .frame(width: leftModeSwitchButtonWidth, height: height)
        case 2:
            ActionKeyButton(
                title: kanaModeSwitchButtonTitle,
                fontSize: compactKanaModeSwitchButtonFontSize,
                isEnabled: inputMode != .kana,
                action: { switchInputMode(.kana) }
            )
                .frame(width: leftModeSwitchButtonWidth, height: height)
        case 3:
            if isKanaFiveByTwoMode {
                ActionKeyButton(
                    title: "☺︎",
                    accessibilityLabel: "絵文字/顔文字",
                    fontSize: kaomojiTransitionIconFontSize,
                    onLongPress: enterKaomojiMode,
                    action: enterEmojiMode
                )
                    .frame(width: leftModeSwitchButtonWidth, height: height)
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

    private var threeByThreeKanaGrid: some View {
        let rowHeight = mainFlickKeyHeight
        let rowSpacing: CGFloat = keyboardRowSpacing
        let kanaRows = threeByThreeKanaRows

        return VStack(spacing: rowSpacing) {
            HStack(spacing: rowSpacing) {
                ActionKeyButton(
                    title: "123",
                    fontSize: leftModeSwitchNumberFontSize,
                    isEnabled: inputMode != .number,
                    action: { switchInputMode(.number) }
                )
                    .frame(width: leftModeSwitchButtonWidth, height: rowHeight)

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
                ActionKeyButton(
                    title: "abc",
                    fontSize: leftModeSwitchLatinFontSize,
                    isEnabled: inputMode != .latin,
                    action: { switchInputMode(.latin) }
                )
                    .frame(width: leftModeSwitchButtonWidth, height: rowHeight)

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
                    title: inputMode == .kana ? (spaceToastText ?? "") : "",
                    titleOpacity: inputMode == .kana ? spaceToastOpacity : 0
                )
                    .frame(width: rightEdgeUtilityColumnWidth, height: rowHeight)
            }
            .zIndex(zIndex(for: 1))

            HStack(spacing: rowSpacing) {
                ActionKeyButton(
                    title: kanaModeSwitchButtonTitle,
                    fontSize: standardKanaModeSwitchButtonFontSize,
                    isEnabled: inputMode != .kana,
                    action: { switchInputMode(.kana) }
                )
                    .frame(width: leftModeSwitchButtonWidth, height: rowHeight)

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
                        title: returnKeySystemImageName == nil ? "⏎" : "",
                        systemImageName: returnKeySystemImageName,
                        accessibilityLabel: returnKeySystemImageName == nil ? "改行" : "検索",
                        fontSize: 22,
                        isEnabled: isReturnKeyEnabled,
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
                ActionKeyButton(
                    title: "☺︎",
                    accessibilityLabel: "絵文字",
                    fontSize: kaomojiTransitionIconFontSize,
                    onLongPress: enterKaomojiMode,
                    action: enterEmojiMode
                )
                    .frame(width: leftModeSwitchButtonWidth, height: rowHeight)

                FlickKeyView(
                    kana: modifierSelectorKey,
                    onCommit: selectModifierMode,
                    mainLabelFontSize: modifierMainLabelFontSize,
                    showsDirectionalHints: showsFlickGuideCharacters,
                    idleReplacement: modifierIdleReplacement,
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

            FlickKeyView(
                kana: renderedKana,
                onCommit: commitText,
                showsDirectionalHints: showsFlickGuideCharacters,
                idleReplacement: rowKeyIdleReplacement(for: renderedKana),
                longPressCandidates: longPressCandidates(for: kana),
                allowsDirectionalFlick: allowsDirectionalFlick(for: kana),
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
            ActionKeyButton(
                title: "123",
                fontSize: leftModeSwitchNumberFontSize,
                isEnabled: inputMode != .number,
                action: { switchInputMode(.number) }
            )
                .frame(width: leftModeSwitchButtonWidth, height: rowHeight)
        case 1:
            ActionKeyButton(
                title: "abc",
                fontSize: leftModeSwitchLatinFontSize,
                isEnabled: inputMode != .latin,
                action: { switchInputMode(.latin) }
            )
                .frame(width: leftModeSwitchButtonWidth, height: rowHeight)
        case 2:
            ActionKeyButton(
                title: kanaModeSwitchButtonTitle,
                fontSize: standardKanaModeSwitchButtonFontSize,
                isEnabled: inputMode != .kana,
                action: { switchInputMode(.kana) }
            )
                .frame(width: leftModeSwitchButtonWidth, height: rowHeight)
        case 3:
            ActionKeyButton(
                title: "☺︎",
                accessibilityLabel: "絵文字",
                fontSize: kaomojiTransitionIconFontSize,
                onLongPress: enterKaomojiMode,
                action: enterEmojiMode
            )
                .frame(width: leftModeSwitchButtonWidth, height: rowHeight)
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
                    title: returnKeySystemImageName == nil ? "⏎" : "",
                    systemImageName: returnKeySystemImageName,
                    accessibilityLabel: returnKeySystemImageName == nil ? "改行" : "検索",
                    fontSize: 22,
                    isEnabled: isReturnKeyEnabled,
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

    private var emojiKeyboardView: some View {
        VStack(spacing: keyboardRowSpacing) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: emojiGridColumns, spacing: emojiGridSpacing) {
                    ForEach(Array(selectedEmojiCategory.emojis.enumerated()), id: \.offset) { _, emoji in
                        EmojiKeyButton(emoji: emoji) {
                            onTextInput(emoji)
                        }
                        .frame(height: compactEmojiKeyHeight)
                    }
                }
                .padding(.vertical, 2)
            }

            HStack(spacing: keyboardRowSpacing) {
                ActionKeyButton(
                    title: "あい",
                    fixedWidth: 56,
                    action: { switchInputMode(.kana) }
                )
                    .frame(height: compactActionKeyHeight)

                ForEach(EmojiCategory.allCases, id: \.self) { category in
                    EmojiCategoryKeyButton(
                        icon: category.icon,
                        isSelected: selectedEmojiCategory == category,
                        action: { selectedEmojiCategory = category }
                    )
                        .frame(maxWidth: .infinity)
                        .frame(height: compactActionKeyHeight)
                }

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
                    .frame(height: compactActionKeyHeight)
            }
        }
    }

    private var kaomojiKeyboardView: some View {
        GeometryReader { geometry in
            let rows = kaomojiRows(for: geometry.size.width)

            VStack(spacing: keyboardRowSpacing) {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: keyboardRowSpacing) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            HStack(spacing: row.spacing) {
                                ForEach(Array(row.items.enumerated()), id: \.offset) { _, kaomoji in
                                    KaomojiKeyButton(kaomoji: kaomoji) {
                                        onTextInput(kaomoji)
                                    }
                                    .frame(
                                        width: min(measuredKaomojiWidth(kaomoji), geometry.size.width),
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                }

                HStack(spacing: keyboardRowSpacing) {
                    ActionKeyButton(
                        title: "あい",
                        fixedWidth: 56,
                        action: { switchInputMode(.kana) }
                    )
                        .frame(height: compactActionKeyHeight)

                    ActionKeyButton(
                        title: "☺︎",
                        accessibilityLabel: "絵文字",
                        fontSize: kaomojiModeReturnIconFontSize,
                        action: { isKaomojiMode = false }
                    )
                        .frame(maxWidth: .infinity)
                        .frame(height: compactActionKeyHeight)

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
                        .frame(height: compactActionKeyHeight)
                }
            }
        }
    }

    private var emojiCategoryHeaderView: some View {
        Group {
            if inputMode == .emoji {
                Text(isKaomojiMode ? "顔文字" : selectedEmojiCategory.frenchName)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(keyLabelColor.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.leading, 2)
                    .padding(.top, 2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            } else {
                Color.clear
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: candidatePlaceholderHeight)
    }

    var body: some View {
        ZStack {
            keyboardBackgroundGradient
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea()

            VStack(spacing: keyboardRowSpacing) {
            emojiCategoryHeaderView

            if inputMode == .emoji {
                if isKaomojiMode {
                    kaomojiKeyboardView
                } else {
                    emojiKeyboardView
                }
            } else if isKanaThreeByThreeMode {
                threeByThreeKanaGrid
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
                        let compactLeftModeSwitchSlot = isKanaFiveByTwoMode ? rowIndex + 1 : rowIndex

                        if showsCompactLeftModeSwitchButtons && compactLeftModeSwitchSlot < 4 {
                            compactLeftModeSwitchButton(slot: compactLeftModeSwitchSlot, height: mainFlickKeyHeight)
                        }

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
                                    allowsDirectionalFlick: allowsDirectionalFlick(for: kana),
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
                    if showsCompactLeftModeSwitchButtons && rows.count < 3 {
                        let compactLeftModeSwitchSlot = isKanaFiveByTwoMode ? rows.count + 1 : rows.count
                        compactLeftModeSwitchButton(slot: compactLeftModeSwitchSlot, height: compactActionKeyHeight)
                    }

                    if showsNextKeyboardKey {
                        ActionKeyButton(title: "🌐", fixedWidth: 54, action: onAdvanceKeyboard)
                            .frame(height: compactActionKeyHeight)
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
                        .frame(height: compactActionKeyHeight)

                    spaceKeyButton(fixedWidth: nil)

                    if inputMode == .kana {
                        FlickKeyView(
                            kana: modifierSelectorKey,
                            onCommit: selectModifierMode,
                            mainLabelFontSize: modifierMainLabelFontSize,
                            showsDirectionalHints: showsFlickGuideCharacters,
                            idleReplacement: modifierIdleReplacement,
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
                    } else if inputMode == .number {
                        ActionKeyButton(
                            title: "あい",
                            fixedWidth: 58,
                            action: { switchInputMode(.kana) }
                        )
                            .frame(height: compactActionKeyHeight)

                        ActionKeyButton(
                            title: "abc",
                            fontSize: leftModeSwitchLatinFontSize,
                            fixedWidth: 58,
                            action: { switchInputMode(.latin) }
                        )
                            .frame(height: compactActionKeyHeight)
                    } else {
                        if !showsCompactLeftModeSwitchButtons {
                            ActionKeyButton(
                                title: "あい",
                                fixedWidth: 58,
                                action: { switchInputMode(.kana) }
                            )
                                .frame(height: compactActionKeyHeight)

                            ActionKeyButton(
                                title: "123",
                                fontSize: 20,
                                fixedWidth: 58,
                                action: { switchInputMode(.number) }
                            )
                                .frame(height: compactActionKeyHeight)
                        }
                    }

                    ActionKeyButton(
                        title: returnKeySystemImageName == nil ? "⏎" : "",
                        systemImageName: returnKeySystemImageName,
                        accessibilityLabel: returnKeySystemImageName == nil ? "改行" : "検索",
                        fontSize: 22,
                        fixedWidth: 72,
                        isEnabled: isReturnKeyEnabled,
                        action: onReturn
                    )
                        .frame(height: compactActionKeyHeight)
                }
                .padding(.top, actionRowTopSpacing)
                .zIndex(zIndex(for: rows.count))
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
        .environment(\.keyboardAccentColor, accentColor)
    }

    private func commitText(_ text: String) {
        guard !text.isEmpty else {
            return
        }

        if text == FlickKanaLayout.latinShiftKeyToken {
            handleLatinShiftTap()
            return
        }

        let usesShift = shouldApplyLatinShift(to: text)
        let shiftedOutput = usesShift ? text.uppercased() : text
        let output = convertedKanaOutputIfNeeded(shiftedOutput)

        onTextInput(output)

        transitionState = KeyboardModeTransition.finishCommit(
            text,
            state: transitionState
        )
    }

    private func selectModifierMode(_ output: String) {
        if output == "…" {
            commitText(output)
            return
        }

        guard inputMode == .kana,
              kanaModifierPlacementMode == .postfix else {
            transitionState = KeyboardModeTransition.selectModifier(
                output,
                state: transitionState
            )
            return
        }

        guard let buttonState = postModifierButtonState(forModifierOutput: output) else {
            transitionState = KeyboardModeTransition.selectModifier(
                output,
                state: transitionState
            )
            return
        }

        if buttonState == .kaomoji {
            enterKaomojiMode()
            return
        }

        let applied = onApplyKanaPostModifier(buttonState)

        if applied {
            var next = transitionState
            next.diacriticMode = .none
            transitionState = next
        }
    }

    private func postModifierButtonState(forModifierOutput output: String) -> KanaPostModifierButtonState? {
        switch output {
        case "^_^":
            return .kaomoji
        case "゛":
            return .dakuten
        case "゜":
            return .handakuten
        case "小":
            return .smallKana
        default:
            return nil
        }
    }

    private func switchInputMode(_ mode: KeyboardInputMode) {
        transitionState = KeyboardModeTransition.switchInputMode(
            transitionState,
            to: mode
        )
    }

    private func enterEmojiMode() {
        transitionState = KeyboardModeTransition.enterEmojiMode(
            from: transitionState
        )
    }

    private func enterKaomojiMode() {
        transitionState = KeyboardModeTransition.enterKaomojiMode(
            from: transitionState
        )
    }

    private func spaceActionKeyButton(
        title: String,
        titleOpacity: Double = 1,
        fixedWidth: CGFloat? = nil
    ) -> some View {
        SpaceFlickActionKeyButton(
            title: title,
            titleOpacity: titleOpacity,
            fixedWidth: fixedWidth,
            onSpace: onSpace,
            onTab: { onTextInput("\t") }
        )
    }

    private func showInitialSpaceToastIfNeeded() {
        guard inputMode == .kana,
              let initialSpaceToastText,
              !initialSpaceToastText.isEmpty else {
            return
        }

        guard lastShownSpaceToastTrigger != spaceToastTrigger else {
            return
        }

        lastShownSpaceToastTrigger = spaceToastTrigger

        spaceToastText = initialSpaceToastText
        spaceToastOpacity = 1

        let fadeDelay: TimeInterval = 0.85
        let fadeDuration: TimeInterval = 0.32

        DispatchQueue.main.asyncAfter(deadline: .now() + fadeDelay) {
            withAnimation(.easeOut(duration: fadeDuration)) {
                spaceToastOpacity = 0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + fadeDuration + 0.02) {
                spaceToastText = nil
            }
        }
    }

    private func spaceKeyButton(fixedWidth: CGFloat?) -> some View {
        spaceActionKeyButton(
            title: inputMode == .kana ? (spaceToastText ?? "") : "",
            titleOpacity: inputMode == .kana ? spaceToastOpacity : 0,
            fixedWidth: fixedWidth
        )
        .frame(maxWidth: fixedWidth == nil ? .infinity : nil)
        .frame(height: compactActionKeyHeight)
    }

    private func longPressCandidates(for kana: FlickKanaSet) -> [String] {
        guard inputMode == .latin else {
            return []
        }

        let candidates = FlickKanaLayout.latinLongPressCandidates(for: kana.center, layoutMode: latinLayoutMode)

        guard latinShiftState != .off else {
            return candidates
        }

        return candidates.map(uppercasedLongPressCandidate)
    }

    private func uppercasedLongPressCandidate(_ candidate: String) -> String {
        if candidate == "ß" {
            return "ẞ"
        }

        return candidate.uppercased()
    }

    private func allowsDirectionalFlick(for kana: FlickKanaSet) -> Bool {
        guard inputMode == .latin,
              latinLayoutMode != .flick,
              isLatinAlphabetKey(kana.center) else {
            return true
        }

        return false
    }

    private func shouldApplyLatinShift(to text: String) -> Bool {
        guard inputMode == .latin,
              latinShiftState != .off,
              isLatinAlphabetKey(text) else {
            return false
        }

        return true
    }

    private func convertedKanaOutputIfNeeded(_ text: String) -> String {
        guard inputMode == .kana,
              kanaCharacterMode == .katakana else {
            return text
        }

        return text.applyingTransform(.hiraganaToKatakana, reverse: false) ?? text
    }

    private func displayedKanaForKanaCharacterModeIfNeeded(_ kana: FlickKanaSet) -> FlickKanaSet {
        guard inputMode == .kana,
              kanaCharacterMode == .katakana else {
            return kana
        }

        return FlickKanaSet(
            label: kanaTextForDisplay(kana.label),
            center: kanaTextForDisplay(kana.center),
            up: kanaTextForDisplay(kana.up),
            right: kanaTextForDisplay(kana.right),
            down: kanaTextForDisplay(kana.down),
            left: kanaTextForDisplay(kana.left)
        )
    }

    private func kanaTextForDisplay(_ text: String) -> String {
        text.applyingTransform(.hiraganaToKatakana, reverse: false) ?? text
    }

    private func displayedKana(for kana: FlickKanaSet) -> FlickKanaSet {
        guard inputMode == .latin,
              latinShiftState != .off,
              isLatinAlphabetKey(kana.center) else {
            return kana
        }

        return FlickKanaSet(
            label: kana.label.uppercased(),
            center: kana.center.uppercased(),
            up: kana.up.uppercased(),
            right: kana.right.uppercased(),
            down: kana.down.uppercased(),
            left: kana.left.uppercased()
        )
    }

    private func latinFlickIdleReplacement(for kana: FlickKanaSet) -> AnyView? {
        guard inputMode == .latin,
              latinLayoutMode == .flick,
              !showsFlickGuideCharacters else {
            return nil
        }

        let compactText = latinFlickCompactText(for: kana)

        return AnyView(
            Text(compactText)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(keyLabelColor)
                .padding(.horizontal, 3)
        )
    }

    private func latinFlickCompactText(for kana: FlickKanaSet) -> String {
        let parts = [kana.center, kana.left, kana.up, kana.right, kana.down]
            .filter { !$0.isEmpty }

        guard kana.center == "'",
              parts.count >= 2,
              parts[0] == "'",
              parts[1] == "\"" else {
            return parts.joined()
        }

        // Add a thin gap only between adjacent single/double quotes.
        return parts[0] + "\u{2009}" + parts.dropFirst().joined()
    }

    private func numberPunctuationIdleReplacement(for kana: FlickKanaSet) -> AnyView? {
        guard inputMode == .number,
              !showsFlickGuideCharacters,
                            kana.center == "." || kana.center == "'" || kana.center == "(" else {
            return nil
        }

        let compactText = [kana.center, kana.left, kana.up, kana.right, kana.down]
            .filter { !$0.isEmpty }
            .joined()

        return AnyView(
            Text(compactText)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(keyLabelColor)
                .padding(.horizontal, 3)
        )
    }

    private func rowKeyIdleReplacement(for kana: FlickKanaSet) -> AnyView? {
        if let latinReplacement = latinFlickIdleReplacement(for: kana) {
            return latinReplacement
        }

        if let numberReplacement = numberPunctuationIdleReplacement(for: kana) {
            return numberReplacement
        }

        return nil
    }

    private var punctuationIdleReplacement: AnyView? {
        guard inputMode == .kana,
              !showsFlickGuideCharacters else {
            return nil
        }

        let topLineText = [
            punctuationKana.center,
            punctuationKana.left
        ]
        .filter { !$0.isEmpty }
        .joined()

        let bottomLineText = [
            punctuationKana.up,
            punctuationKana.right,
            punctuationKana.down
        ]
        .filter { !$0.isEmpty }
        .joined()

        return AnyView(
            VStack(spacing: -3) {
                Text(topLineText)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                Text(bottomLineText)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
                .foregroundStyle(keyLabelColor)
                .padding(.horizontal, 2)
                .padding(.vertical, 1)
        )
    }

    private func isLatinShiftKey(_ kana: FlickKanaSet) -> Bool {
        kana.center == FlickKanaLayout.latinShiftKeyToken
    }

    private func handleLatinShiftTap() {
        transitionState = KeyboardModeTransition.handleLatinShiftTap(
            transitionState,
            now: Date(),
            doubleTapThreshold: shiftDoubleTapThreshold
        )
    }

    private func handleLatinShiftLongPress() {
        transitionState = KeyboardModeTransition.handleLatinShiftLongPress(
            transitionState
        )
    }

    private func isLatinAlphabetKey(_ value: String) -> Bool {
        guard value.count == 1,
              let scalar = value.unicodeScalars.first else {
            return false
        }

        return CharacterSet.letters.contains(scalar)
    }

    private func updateActiveLayer(_ isTouching: Bool, layerIndex: Int) {
        if isTouching {
            activeLayerIndex = layerIndex
            return
        }

        if activeLayerIndex == layerIndex {
            activeLayerIndex = nil
        }
    }

    private func zIndex(for layerIndex: Int) -> Double {
        activeLayerIndex == layerIndex ? KeyboardLayerZIndex.activeRow : 0
    }

    private var modifierIdleReplacement: AnyView? {
        guard inputMode == .kana, !showsFlickGuideCharacters else {
            return nil
        }

        if kanaModifierPlacementMode == .postfix {
            return AnyView(
                Group {
                    switch kanaPostModifierButtonState {
                    case .kaomoji:
                        DakutenDuckCompositeIconView()
                    case .smallKana:
                        DakutenDuckCompositeIconView(isSmallKanaMode: true)
                            .scaleEffect(0.6)
                            .offset(x: -3, y: 3)
                    case .dakuten:
                        DakutenDuckCompositeIconView(showsDakutenMark: true)
                    case .handakuten:
                        DakutenDuckCompositeIconView(showsHandakutenMark: true)
                    }
                }
                    .padding(7)
            )
        }

        return AnyView(
            DakutenDuckCompositeIconView(
                showsDakutenMark: diacriticMode == .dakuten,
                showsHandakutenMark: diacriticMode == .handakuten,
                isSmallKanaMode: diacriticMode == .smallKana
            )
                .scaleEffect(diacriticMode == .smallKana ? 0.6 : 1)
                .offset(
                    x: diacriticMode == .smallKana ? -3 : 0,
                    y: diacriticMode == .smallKana ? 3 : 0
                )
                .padding(7)
        )
    }
}

#Preview {
    KeyboardRootView(
        onTextInput: { _ in },
        onDeleteBackward: {},
        onSpace: {},
        onReturn: {},
        onAdvanceKeyboard: {},
        onApplyKanaPostModifier: { _ in false },
        onInputModeChanged: { _ in },
        showsNextKeyboardKey: true,
        directionProfile: .ecritu,
        kanaLayoutMode: .fiveByTwo,
        kanaModifierPlacementMode: .prefix,
        kanaPostModifierButtonState: .kaomoji,
        numberLayoutMode: .calculette,
        latinLayoutMode: .flick,
        accentPaletteRawValue: "emeraude",
        keyboardBackgroundThemeRawValue: "bleu",
        spaceToastTrigger: 1,
        returnKeySystemImageName: nil,
        isReturnKeyEnabled: true,
        showsFlickGuideCharacters: true,
        keyRepeatInitialDelay: 0.5,
        keyRepeatInterval: 0.1,
        initialSpaceToastText: nil
    )
}
