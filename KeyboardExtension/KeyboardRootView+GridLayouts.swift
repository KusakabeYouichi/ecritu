import SwiftUI
import UIKit
import CoreFoundation
import Darwin
import Contacts

extension KeyboardRootView {
    var threeByThreeWaKana: FlickKanaSet {
        displayedKanaForKanaCharacterModeIfNeeded(
            FlickKanaLayout.waSet(for: activeKanaModifierMode).remapped(for: directionProfile)
        )
    }

    func makeModifierSelectorKey(
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

    func leftModeSwitchSymbolsButton(height: CGFloat) -> some View {
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

    var threeByThreeKanaGrid: some View {
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

    var threeByThreeNumberOrLatinGrid: some View {
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
}
