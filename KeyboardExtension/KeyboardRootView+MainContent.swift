import SwiftUI

// キーボード本体(候補バーより下)の描画。入力モード(かな/英/数/記号/絵文字/顔文字)と
// レイアウトモードに応じて各レイアウトビューを組み立てる中核。個々のレイアウトは
// +GridLayouts / +LandscapeLayouts / +EmojiKaomojiLayouts に委譲する。
extension KeyboardRootView {
    @ViewBuilder
    var keyboardMainContent: some View {
        if inputMode == .formattedNumber {
            formattedNumberKeyboardView
        } else if inputMode == .emoji {
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
}
