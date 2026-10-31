import SwiftUI
import UIKit
import CoreFoundation
import Darwin

extension KeyboardRootView {
    var threeByThreeWaKana: FlickKanaSet {
        displayedKanaForKanaCharacterModeIfNeeded(
            FlickKanaLayout.waSet(for: activeKanaModifierMode, profile: directionProfile)
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

    // 左端上段[123]・中段[abc]・下段[あい]。タップで面を切り替え、右フリックで設定 E.5 の面を開く(3618)
    func leftModeSwitchNumberButton(height: CGFloat) -> some View {
        ModeSwitchColumnKey(
            title: "123",
            fontSize: leftModeSwitchNumberFontSize,
            isTapEnabled: inputMode != .number,
            rightFlickLabel: leftModeSwitchNumberKeyRightFlickAction.keyLabel,
            showsRightFlickHint: showsFlickGuideCharacters,
            onTap: { switchInputMode(.number) },
            onRightFlick: {
                selectLeftModeSwitchKeyRightFlick(leftModeSwitchNumberKeyRightFlickAction, keyTitle: "123")
            }
        )
            .frame(width: leftModeSwitchButtonWidth, height: height)
    }

    func leftModeSwitchLatinButton(height: CGFloat) -> some View {
        ZStack {
            ModeSwitchColumnKey(
                title: "abc",
                fontSize: leftModeSwitchLatinFontSize,
                isTapEnabled: inputMode != .latin,
                rightFlickLabel: leftModeSwitchLatinKeyRightFlickAction.keyLabel,
                showsRightFlickHint: showsFlickGuideCharacters,
                onLongPress: handleLatinModeSwitchLongPress,
                onTap: handleLatinModeSwitchTap,
                onRightFlick: {
                    selectLeftModeSwitchKeyRightFlick(leftModeSwitchLatinKeyRightFlickAction, keyTitle: "abc")
                }
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
        ModeSwitchColumnKey(
            title: kanaModeSwitchButtonTitle,
            fontSize: fontSize,
            isTapEnabled: inputMode != .kana,
            rightFlickLabel: leftModeSwitchKanaKeyRightFlickAction.keyLabel,
            showsRightFlickHint: showsFlickGuideCharacters,
            onTap: { switchInputMode(.kana) },
            onRightFlick: {
                selectLeftModeSwitchKeyRightFlick(leftModeSwitchKanaKeyRightFlickAction, keyTitle: "あい")
            }
        )
            .frame(width: leftModeSwitchButtonWidth, height: height)
    }

    // 左端最下段のキー(面を切り替えるキー)。かな・英字・数字のどのモードでも同じ(3625。以前は英字=☺︎ 絵文字
    // (長押しで書式化)、数字 clavier=⌘ 記号、calculette/téléphone=空きと、モードごとに別のキーだった)。
    // タップ(.milieu)と右フリック(.droite)は設定 E.5 の面。面選択のパレットは押したままで出る
    func modeSwitcherPaletteKey(
        height: CGFloat,
        touchForensicsLabel: String,
        onTouchStateChanged: @escaping (Bool) -> Void = { _ in }
    ) -> some View {
        FlickKeyView(
            kana: kanaModeSwitcherKana,
            onCommit: selectKanaModeSwitcher,
            onCommitWithDirection: selectKanaModeSwitcher(_:direction:),
            mainLabelFontSize: kanaModeSwitcherMainLabelFontSize,
            showsDirectionalHints: showsFlickGuideCharacters,
            showsGuideText: false,
            longPressCandidates: Self.modePaletteLabels,
            longPressCandidateAxis: .vertical,
            longPressCandidateCellWidth: 116,
            longPressCandidateColumnCount: modePaletteColumnCount,
            longPressDelayOverride: Self.modePaletteLongPressDelay,
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
            onTouchStateChanged: onTouchStateChanged,
            touchForensicsLabel: touchForensicsLabel  // 調査用ログ(記号面切替 2838)
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
            modeSwitcherPaletteKey(
                height: height,
                touchForensicsLabel: isKanaFiveByTwoMode ? "左下キー(5x2)" : "左下キー(コンパクト)"
            )
        default:
            Color.clear
                .allowsHitTesting(false)
                .frame(width: leftModeSwitchButtonWidth, height: height)
        }
    }

    var threeByThreeKanaRows: [[FlickKanaSet]] {
        FlickKanaLayout.rows(for: activeKanaModifierMode, layoutMode: .threeByThreePlusWa, profile: directionProfile, yaBracket: kanaYaBracketMode).map { row in
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

            modeSwitcherPaletteKey(
                height: rowHeight,
                touchForensicsLabel: "左下キー(3x3)",
                onTouchStateChanged: { isTouching in
                    updateActiveLayer(isTouching, layerIndex: 3, isLeftModeSwitchColumn: true)
                }
            )
        }
        // 列の吹き出しは段より前、ただし段のキーを触っているあいだは後ろへ(定義箇所のコメント参照。3167)
        .zIndex(leftModeSwitchColumnZIndex)
    }

    func threeByThreeKanaMainCluster(
        kanaRows: [[FlickKanaSet]],
        rowHeight: CGFloat,
        rowSpacing: CGFloat
    ) -> some View {
        VStack(spacing: rowSpacing) {
            HStack(spacing: rowSpacing) {
                // 3 つのかなキーは ForEach でまとめる(2921): 1 つずつ並べると巨大なタプル型になり、
                // body 構築時のスタックを食い潰して App Extension が落ちる(Xcode 27 で縦画面でも越えた)
                ForEach(0..<3, id: \.self) { column in
                    FlickKeyView(
                        kana: kanaRows[0][column],
                        onCommit: commitText,
                        mainLabelFontSize: kanaThreeByThreeMainLabelFontSize,
                        showsDirectionalHints: showsFlickGuideCharacters,
                        onTouchStateChanged: { isTouching in
                            updateActiveLayer(isTouching, layerIndex: 0)
                        }
                    )
                        .frame(maxWidth: .infinity)
                        .frame(height: rowHeight)
                }

                deleteActionKey(showsMemoryPressure: true)
                    .frame(width: rightEdgeUtilityColumnWidth, height: rowHeight)
            }
            .zIndex(zIndex(for: 0))

            HStack(spacing: rowSpacing) {
                // 3 つのかなキーは ForEach でまとめる(2921): 1 つずつ並べると巨大なタプル型になり、
                // body 構築時のスタックを食い潰して App Extension が落ちる(Xcode 27 で縦画面でも越えた)
                ForEach(0..<3, id: \.self) { column in
                    FlickKeyView(
                        kana: kanaRows[1][column],
                        onCommit: commitText,
                        mainLabelFontSize: kanaThreeByThreeMainLabelFontSize,
                        showsDirectionalHints: showsFlickGuideCharacters,
                        onTouchStateChanged: { isTouching in
                            updateActiveLayer(isTouching, layerIndex: 1)
                        }
                    )
                        .frame(maxWidth: .infinity)
                        .frame(height: rowHeight)
                }

                spaceActionKeyButton(
                    title: spaceKeyDisplayTitle,
                    titleOpacity: spaceKeyDisplayOpacity
                )
                    .frame(width: rightEdgeUtilityColumnWidth, height: rowHeight)
            }
            .zIndex(zIndex(for: 1))

            HStack(spacing: rowSpacing) {
                // 3 つのかなキーは ForEach でまとめる(2921): 1 つずつ並べると巨大なタプル型になり、
                // body 構築時のスタックを食い潰して App Extension が落ちる(Xcode 27 で縦画面でも越えた)
                ForEach(0..<3, id: \.self) { column in
                    FlickKeyView(
                        kana: kanaRows[2][column],
                        onCommit: commitText,
                        mainLabelFontSize: kanaThreeByThreeMainLabelFontSize,
                        showsDirectionalHints: showsFlickGuideCharacters,
                        onTouchStateChanged: { isTouching in
                            updateActiveLayer(isTouching, layerIndex: 2)
                        }
                    )
                        .frame(maxWidth: .infinity)
                        .frame(height: rowHeight)
                }

                ZStack(alignment: .top) {
                    Color.clear

                    returnActionKey()
                        .frame(maxWidth: .infinity)
                        .frame(height: threeByThreeReturnKeyHeight(rowHeight: rowHeight, rowSpacing: rowSpacing))
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

                threeByThreeFourthRowUtilitySlot(width: rightEdgeUtilityColumnWidth, rowHeight: rowHeight)
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
            // 段の束の重なり順(定義箇所のコメント参照。3168)
            .zIndex(kanaMainClusterZIndex)
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
            modeSwitcherPaletteKey(height: rowHeight, touchForensicsLabel: "左下キー(3x3 列)")
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
            deleteActionKey(showsMemoryPressure: true)
                .frame(width: rightEdgeUtilityColumnWidth, height: rowHeight)
        case 1:
            spaceActionKeyButton(title: "")
                .frame(width: rightEdgeUtilityColumnWidth, height: rowHeight)
        case 2:
            ZStack(alignment: .top) {
                Color.clear

                returnActionKey()
                    .frame(maxWidth: .infinity)
                    .frame(height: threeByThreeReturnKeyHeight(rowHeight: rowHeight, rowSpacing: rowSpacing))
            }
            .frame(width: rightEdgeUtilityColumnWidth, height: rowHeight, alignment: .top)
            .zIndex(KeyboardLayerZIndex.rightEdgeUtilityColumn)
        case 3:
            threeByThreeFourthRowUtilitySlot(width: rightEdgeUtilityColumnWidth, rowHeight: rowHeight)
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

    // 3×3 系(3x3+わ / 数字・ラテン 3×3 / 横画面コンパクト数字)の右列 4 段目。
    // 地球儀キーが要る機種(ホームボタン機: needsInputModeSwitchKey=true、iOS の地球儀バーが無い)では
    // 2 段ぶち抜きだった ⏎ を 1 段に戻し、空いた 4 段目に 🌐 を置く(ガイドライン 4.4.1: 次の
    // キーボードへ切り替える手段。以前は 3×3 系だけ 🌐 が無く、SE 系で純正へ戻れなかった。2785)。
    // 地球儀バーのある機種(iPhone 15/16 等)は従来どおり ⏎ 2 段+空きで表示は変わらない。
    func threeByThreeReturnKeyHeight(rowHeight: CGFloat, rowSpacing: CGFloat) -> CGFloat {
        showsNextKeyboardKey ? rowHeight : rowHeight * 2 + rowSpacing
    }

    @ViewBuilder
    func threeByThreeFourthRowUtilitySlot(width: CGFloat, rowHeight: CGFloat) -> some View {
        if showsNextKeyboardKey {
            ActionKeyButton(
                title: "🌐",
                accessibilityLabel: "次のキーボード",
                fontSize: 22,
                action: onAdvanceKeyboard
            )
                .frame(width: width, height: rowHeight)
        } else {
            Color.clear
                .allowsHitTesting(false)
                .frame(width: width, height: rowHeight)
        }
    }
}
