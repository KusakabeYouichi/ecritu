import SwiftUI
import UIKit
import CoreFoundation
import Darwin
import Contacts

extension KeyboardRootView {
    var usesLandscapeKanaCandidateSidebar: Bool {
        isLandscapeLayout && inputMode == .kana
    }

    var usesLandscapeLatinSuggestionSidebar: Bool {
        isLandscapeLayout
            && inputMode == .latin
            && landscapeLatinSuggestionMode == .sidebar
    }

    var usesLandscapeLatinTypewriterLayout: Bool {
        isLandscapeLayout
            && inputMode == .latin
            && (latinLayoutMode == .qwerty || latinLayoutMode == .azerty)
    }

    var landscapeLatinInlineReturnRowIndex: Int {
        // Keep return key directly under delete: right of L (QWERTY) / m (AZERTY).
        1
    }

    var landscapeLatinInlinePunctuationKeys: [FlickKanaSet] {
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

    var landscapeNumberSymbolPanelRows: [[String]] {
        // Custom landscape number-side companion symbols (4 rows x 6 columns).
        [
            ["+", "€", "℃", "mm", "mg", "ml"],
            ["-", "$", "℉", "cm", "cg", "cl"],
            ["±", "¥", "°", "m", "g", "l"],
            ["(", ")", "/", "km", "kg", "kl"]
        ]
    }

    func isLandscapeLatinRightShiftKey(_ kana: FlickKanaSet) -> Bool {
        kana.label == "__latin_shift_right__"
    }

    var landscapeLatinRightShiftKey: FlickKanaSet {
        FlickKanaSet(
            label: "__latin_shift_right__",
            center: FlickKanaLayout.latinShiftKeyToken,
            up: "",
            right: "",
            down: "",
            left: ""
        )
    }

    func landscapeBottomRowWithInlinePunctuation(_ row: [FlickKanaSet]) -> [FlickKanaSet] {
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

    var landscapeKanaCandidateSide: LandscapeCandidateSide {
        LandscapeCandidateSide(rawValue: landscapeCandidateSideRawValue) ?? .left
    }

    var landscapeNumberPaneSide: LandscapeCandidateSide {
        LandscapeCandidateSide(rawValue: landscapeNumberPaneSideRawValue) ?? .left
    }

    var landscapeLatinSuggestionMode: LandscapeLatinSuggestionMode {
        LandscapeLatinSuggestionMode(rawValue: landscapeLatinSuggestionModeRawValue) ?? .sidebar
    }

    var usesLandscapeCompactNumberLayout: Bool {
        isLandscapeLayout
            && inputMode == .number
            && usesThreeByThreeGridForNumberOrLatin
    }

    var isLandscapeLatinThreeByThreeMode: Bool {
        isLandscapeLayout
            && inputMode == .latin
            && usesThreeByThreeGridForNumberOrLatin
    }

    var landscapeNumberNarrowGrid: some View {
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
    func landscapeNumberCompactColumns(
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

    func landscapeNumberModeSwitchColumn(
        rowHeight: CGFloat,
        rowSpacing: CGFloat
    ) -> some View {
        VStack(spacing: rowSpacing) {
            ForEach(0..<4, id: \.self) { rowIndex in
                threeByThreeLeftColumnButton(rowIndex: rowIndex, rowHeight: rowHeight)
            }
        }
    }

    func landscapeNumberMainKeyCluster(
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

    func landscapeNumberUtilityColumn(
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

    func landscapeNumberSymbolPanel(
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

    func landscapeCandidateSidebarWidth() -> CGFloat {
        let screenWidth = max(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
        let ratio: CGFloat = isKanaFiveByTwoMode ? 0.34 : 0.4
        let desired = screenWidth * ratio
        return min(max(desired, 180), 320)
    }

    var landscapeKanaCandidateSidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            let showsWrapperOnly = showsParenthesesWrapper && composingText.isEmpty

            if !composingText.isEmpty || showsWrapperOnly {
                // 状態はアイコンのミニカプセルで示す(鉛筆=未確定/循環矢印=変換中)。
                Group {
                    if showsWrapperOnly {
                        Text("()")
                    } else {
                        Image(systemName: conversionStateIconName)
                    }
                }
                .font(.system(size: candidateStateFontSize, weight: .bold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(conversionStateColor.opacity(0.95))
                )
                .accessibilityLabel(conversionStateLabel)

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

    var landscapeLatinSuggestionSidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            if latinSuggestionQuery.isEmpty {
                ForEach(0..<landscapeEmptyCandidatePlaceholderCount, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(KeyboardThemePalette.candidateHeaderPlaceholderBackground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 24)
                }
            } else if latinSuggestions.isEmpty {
                // かな側と同じ空集合アイコン(候補なし)。
                Image(systemName: "circle.slash")
                    .font(.system(size: candidateTextFontSize, weight: .regular))
                    .foregroundStyle(keyLabelColor.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(KeyboardThemePalette.candidateHeaderPlaceholderBackground)
                    )
                    .accessibilityLabel("候補なし")
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

    var landscapeLatinReferenceClusterHeight: CGFloat {
        // ラテン横画面の主要クラスターは4段固定。
        mainFlickKeyHeight * 4 + keyboardRowSpacing * 3
    }

    @ViewBuilder
    var landscapeLatinSwappableMainCluster: some View {
        if usesLandscapeLatinTypewriterLayout {
            landscapeLatinTypewriterMainCluster
        } else if usesThreeByThreeGridForNumberOrLatin {
            landscapeLatinThreeByThreeMainCluster
        } else {
            keyboardMainContent
        }
    }

    var landscapeLatinThreeByThreeMainCluster: some View {
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

    var landscapeKanaFiveByTwoLeftColumn: some View {
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

    var landscapeKanaFiveByTwoMainCluster: some View {
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

    var landscapeLatinModeSwitchColumn: some View {
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

    func landscapeLatinTypewriterLetterAnchorOffsetFactor(_ rowIndex: Int) -> CGFloat {
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

    func landscapeLatinTypewriterLeadingControlPitchCount(_ row: [FlickKanaSet]) -> CGFloat {
        CGFloat(row.prefix { isLatinShiftKey($0) }.count)
    }

    func landscapeLatinTypewriterRowInsets(
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

    func landscapeLatinTypewriterRowInsets(_ rowIndex: Int, keyPitch: CGFloat) -> EdgeInsets {
        landscapeLatinTypewriterRowInsets(
            leadingOffsetFactor: landscapeLatinTypewriterLetterAnchorOffsetFactor(rowIndex),
            keyPitch: keyPitch
        )
    }

    func landscapeLatinTypewriterRowInsets(_ rowIndex: Int) -> EdgeInsets {
        guard usesLandscapeLatinTypewriterLayout else {
            return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        }

        let fallbackKeyPitch = mainFlickKeyHeight + keyboardRowSpacing
        return landscapeLatinTypewriterRowInsets(rowIndex, keyPitch: fallbackKeyPitch)
    }

    @ViewBuilder
    func landscapeLatinTypewriterKey(
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

    func landscapeLatinInlineDeleteKey(fixedWidth: CGFloat) -> some View {
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

    func landscapeLatinInlineReturnKey(fixedWidth: CGFloat) -> some View {
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

    func landscapeLatinInlineApostropheKey(fixedWidth: CGFloat) -> some View {
        ActionKeyButton(
            title: "'",
            fontSize: 20,
            action: { commitText("'") }
        )
            .frame(width: fixedWidth, height: mainFlickKeyHeight)
    }

    var landscapeLatinInlineActionTypewriterMainCluster: some View {
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

    var landscapeLatinTypewriterMainCluster: some View {
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
    var landscapeKanaFixedModeSwitchColumn: some View {
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
    var landscapeKanaSwappableMainCluster: some View {
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

    var landscapeKanaReferenceClusterHeight: CGFloat {
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
}
