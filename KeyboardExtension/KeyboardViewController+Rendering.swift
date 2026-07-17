import UIKit

// キーボードの描画設定(RenderConfiguration)の構築と、それを SwiftUI ルートビューへ
// 橋渡しする処理。設定の読み出しヘルパは +Settings、候補提示は +CandidatePresentation に
// あり、本ファイルはそれらを集約して 1 つの RenderConfiguration / KeyboardRootView を組む。
extension KeyboardViewController {
    // 描画に必要な設定を一括で保持する値型(差分検出で再描画要否を判定)。
    struct RenderConfiguration: Equatable {
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
        let showsNextKeyboardKey: Bool
        let shortcutVocabulary: [String]
        let composingText: String
        let conversionCandidates: [String]
        let selectedConversionCandidateIndex: Int?
        let latinSuggestionQuery: String
        let latinSuggestions: [String]
        let showsParenthesesWrapper: Bool

        // 候補バー系(composing/変換候補/選択位置/英字サジェスト)を除いた等価判定。
        // これが等しい打鍵ではキー盤面に影響がなく、rootView 差し替えを省略できる。
        func equalIgnoringCandidateBar(_ other: RenderConfiguration) -> Bool {
            var normalizedSelf = self
            var normalizedOther = other
            normalizedSelf = normalizedSelf.replacingCandidateBarFields(with: RenderConfiguration.candidateBarFieldPlaceholder)
            normalizedOther = normalizedOther.replacingCandidateBarFields(with: RenderConfiguration.candidateBarFieldPlaceholder)
            return normalizedSelf == normalizedOther
        }

        private static let candidateBarFieldPlaceholder = (
            composingText: "",
            conversionCandidates: [String](),
            selectedConversionCandidateIndex: Int?.none,
            latinSuggestionQuery: "",
            latinSuggestions: [String]()
        )

        private func replacingCandidateBarFields(
            with fields: (
                composingText: String,
                conversionCandidates: [String],
                selectedConversionCandidateIndex: Int?,
                latinSuggestionQuery: String,
                latinSuggestions: [String]
            )
        ) -> RenderConfiguration {
            RenderConfiguration(
                directionProfile: directionProfile,
                kanaLayoutMode: kanaLayoutMode,
                kanaModifierPlacementMode: kanaModifierPlacementMode,
                kanaPostModifierButtonState: kanaPostModifierButtonState,
                numberLayoutMode: numberLayoutMode,
                latinLayoutMode: latinLayoutMode,
                accentPaletteRawValue: accentPaletteRawValue,
                isSystemDictionaryFallback: isSystemDictionaryFallback,
                keyboardBackgroundThemeRawValue: keyboardBackgroundThemeRawValue,
                basicSymbolOrderRawValue: basicSymbolOrderRawValue,
                temperatureUnitRawValue: temperatureUnitRawValue,
                spaceToastTrigger: spaceToastTrigger,
                returnKeySystemImageName: returnKeySystemImageName,
                isReturnKeyEnabled: isReturnKeyEnabled,
                kanaFlickGuideDisplayMode: kanaFlickGuideDisplayMode,
                latinFlickGuideDisplayMode: latinFlickGuideDisplayMode,
                numberFlickGuideDisplayMode: numberFlickGuideDisplayMode,
                modifierFlickGuideDisplayMode: modifierFlickGuideDisplayMode,
                keyRepeatInitialDelay: keyRepeatInitialDelay,
                keyRepeatInterval: keyRepeatInterval,
                kanaModeSwitcherTapActionRawValue: kanaModeSwitcherTapActionRawValue,
                kanaModeSwitcherRightFlickActionRawValue: kanaModeSwitcherRightFlickActionRawValue,
                kanaModeSwitcherUpFlickActionRawValue: kanaModeSwitcherUpFlickActionRawValue,
                kanaPostModifierEmptyTapActionRawValue: kanaPostModifierEmptyTapActionRawValue,
                kanaPostModifierEmptyTapKaomojiCategoryID: kanaPostModifierEmptyTapKaomojiCategoryID,
                kanaPostModifierEmptyTapEmojiCategoryID: kanaPostModifierEmptyTapEmojiCategoryID,
                kanaPostModifierEmptyTapSymbolCategoryID: kanaPostModifierEmptyTapSymbolCategoryID,
                kanaPostModifierFlickDakutenEnabled: kanaPostModifierFlickDakutenEnabled,
                landscapeCandidateSideRawValue: landscapeCandidateSideRawValue,
                landscapeNumberPaneSideRawValue: landscapeNumberPaneSideRawValue,
                landscapeLatinSuggestionModeRawValue: landscapeLatinSuggestionModeRawValue,
                showsNextKeyboardKey: showsNextKeyboardKey,
                shortcutVocabulary: shortcutVocabulary,
                composingText: fields.composingText,
                conversionCandidates: fields.conversionCandidates,
                selectedConversionCandidateIndex: fields.selectedConversionCandidateIndex,
                latinSuggestionQuery: fields.latinSuggestionQuery,
                latinSuggestions: fields.latinSuggestions,
                showsParenthesesWrapper: showsParenthesesWrapper
            )
        }
    }

    // 候補バー系の状態を publish する(値が同じなら publish しない — SwiftUI の無駄な
    // 再評価を避ける)。
    func updateCandidateBarModel(from configuration: RenderConfiguration) {
        let model = candidateBarModel
        if model.composingText != configuration.composingText {
            model.composingText = configuration.composingText
        }
        if model.conversionCandidates != configuration.conversionCandidates {
            model.conversionCandidates = configuration.conversionCandidates
        }
        if model.selectedConversionCandidateIndex != configuration.selectedConversionCandidateIndex {
            model.selectedConversionCandidateIndex = configuration.selectedConversionCandidateIndex
        }
        if model.latinSuggestionQuery != configuration.latinSuggestionQuery {
            model.latinSuggestionQuery = configuration.latinSuggestionQuery
        }
        if model.latinSuggestions != configuration.latinSuggestions {
            model.latinSuggestions = configuration.latinSuggestions
        }
    }

    // 後置修飾(濁点/小書き等)の判定に使う「直前文脈」。未確定入力→変換確定文脈→
    // 同期済み末尾→本文、の順で最初に非空のものを採る。
    private func postModifierContextForRender() -> String? {
        if !composingRawText.isEmpty {
            return composingRawText
        }
        if let activeConversion {
            return activeConversion.committedText
        }
        if !lastSynchronizedContextBeforeInputTail.isEmpty {
            return lastSynchronizedContextBeforeInputTail
        }
        return currentTextContextBeforeInput()
    }

    // 修飾キーのフリックガイド表示: 個別設定があればそれ、無ければ かな 設定を継承。
    private func resolvedModifierFlickGuideDisplayMode(
        from sharedDefaults: UserDefaults?,
        kanaFallback: FlickGuideDisplayMode
    ) -> FlickGuideDisplayMode {
        guard sharedDefaults?.object(forKey: SharedDefaultsKeys.modifierFlickGuideDisplayMode) != nil else {
            return kanaFallback
        }
        return sharedFlickGuideDisplayModeValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.modifierFlickGuideDisplayMode
        )
    }

    func makeRenderConfiguration() -> RenderConfiguration {
        updateMemoryFailSafeProfile(trigger: "makeRenderConfiguration")

        let sharedDefaults = self.sharedDefaults
        let candidateSourceMode = currentKanaKanjiCandidateSourceMode(from: sharedDefaults)
        let candidatePresentation = currentCandidatePresentationForRender(
            systemCandidateMode: candidateSourceMode
        )
        let directionProfile = sharedEnumValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.directionProfile,
            fallback: FlickDirectionProfile.ecritu
        )
        let kanaLayoutMode = sharedEnumValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.kanaLayoutMode,
            fallback: KanaLayoutMode.fiveByTwo
        )
        let kanaModifierPlacementMode = sharedEnumValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.kanaModifierPlacement,
            fallback: KanaModifierPlacementMode.prefix
        )
        let kanaPostModifierButtonState = FlickKanaLayout.postModifierButtonState(
            contextBeforeInput: postModifierContextForRender()
        )
        let numberLayoutMode = sharedEnumValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.numberLayoutMode,
            fallback: NumberLayoutMode.calculette
        )
        let latinLayoutMode = sharedEnumValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.latinLayoutMode,
            fallback: LatinLayoutMode.azerty
        )
        let accentPaletteRawValue = sharedStringValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.accentPalette,
            fallback: "emeraude"
        )
        let keyboardBackgroundThemeRawValue = sharedStringValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.keyboardBackgroundTheme,
            fallback: "bleu"
        )
        let basicSymbolOrderRawValue = sharedStringValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.basicSymbolOrder,
            fallback: "ascii"
        )
        let temperatureUnitRawValue = currentTemperatureUnit().rawValue
        let returnKeyType = textDocumentProxy.returnKeyType
        let hasAnyText = textDocumentProxy.hasText
        let hasPendingComposingText = !candidatePresentation.composingText.isEmpty
        let returnKeySystemImageName: String? = returnKeyType == .search ? "magnifyingglass" : nil
        let isReturnKeyEnabled = hasPendingComposingText || (returnKeyType == .search ? hasAnyText : true)
        let kanaFlickGuideDisplayMode = sharedFlickGuideDisplayModeValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.kanaFlickGuideDisplayMode
        )
        let latinFlickGuideDisplayMode = sharedFlickGuideDisplayModeValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.latinFlickGuideDisplayMode
        )
        let numberFlickGuideDisplayMode = sharedFlickGuideDisplayModeValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.numberFlickGuideDisplayMode
        )
        let modifierFlickGuideDisplayMode = resolvedModifierFlickGuideDisplayMode(
            from: sharedDefaults,
            kanaFallback: kanaFlickGuideDisplayMode
        )
        let keyRepeatInitialDelay = sharedDoubleValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.keyRepeatInitialDelay,
            fallback: 0.5,
            range: 0.1...0.8
        )
        let keyRepeatInterval = sharedDoubleValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.keyRepeatInterval,
            fallback: 0.1,
            range: 0.05...0.2
        )
        let kanaModeSwitcherTapActionRawValue = sharedStringValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.kanaModeSwitcherTapAction,
            fallback: "emoji"
        )
        let kanaModeSwitcherRightFlickActionRawValue = sharedStringValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.kanaModeSwitcherRightFlickAction,
            fallback: "kaomoji"
        )
        let kanaModeSwitcherUpFlickActionRawValue = sharedStringValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.kanaModeSwitcherUpFlickAction,
            fallback: "symbols"
        )
        let kanaPostModifierEmptyTapActionRawValue = sharedStringValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.kanaPostModifierEmptyTapAction,
            fallback: "kaomoji"
        )
        let kanaPostModifierEmptyTapKaomojiCategoryID = sharedStringValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.kanaPostModifierEmptyTapKaomojiCategory,
            fallback: "existing"
        )
        let kanaPostModifierEmptyTapEmojiCategoryID = sharedStringValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.kanaPostModifierEmptyTapEmojiCategory,
            fallback: "0"
        )
        let kanaPostModifierEmptyTapSymbolCategoryID = sharedStringValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.kanaPostModifierEmptyTapSymbolCategory,
            fallback: "0"
        )
        let kanaPostModifierFlickDakutenEnabled = sharedBoolValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.kanaPostModifierFlickDakutenEnabled,
            fallback: true
        )
        let landscapeCandidateSideRawValue = sharedStringValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.landscapeCandidateSide,
            fallback: "left"
        )
        let landscapeNumberPaneSideRawValue = sharedStringValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.landscapeNumberPaneSide,
            fallback: "left"
        )
        let landscapeLatinSuggestionModeRawValue = sharedStringValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.landscapeLatinSuggestionMode,
            fallback: "sidebar"
        )
        let latinSuggestionQuery = currentLatinSuggestionQueryFromTextContext()
        let latinSuggestions = currentLatinSuggestions()

        return RenderConfiguration(
            directionProfile: directionProfile,
            kanaLayoutMode: kanaLayoutMode,
            kanaModifierPlacementMode: kanaModifierPlacementMode,
            kanaPostModifierButtonState: kanaPostModifierButtonState,
            numberLayoutMode: numberLayoutMode,
            latinLayoutMode: latinLayoutMode,
            accentPaletteRawValue: accentPaletteRawValue,
            isSystemDictionaryFallback: kanaKanjiStore.isSystemDictionaryFallback(),
            keyboardBackgroundThemeRawValue: keyboardBackgroundThemeRawValue,
            basicSymbolOrderRawValue: basicSymbolOrderRawValue,
            temperatureUnitRawValue: temperatureUnitRawValue,
            spaceToastTrigger: spaceToastTrigger,
            returnKeySystemImageName: returnKeySystemImageName,
            isReturnKeyEnabled: isReturnKeyEnabled,
            kanaFlickGuideDisplayMode: kanaFlickGuideDisplayMode,
            latinFlickGuideDisplayMode: latinFlickGuideDisplayMode,
            numberFlickGuideDisplayMode: numberFlickGuideDisplayMode,
            modifierFlickGuideDisplayMode: modifierFlickGuideDisplayMode,
            keyRepeatInitialDelay: keyRepeatInitialDelay,
            keyRepeatInterval: keyRepeatInterval,
            kanaModeSwitcherTapActionRawValue: kanaModeSwitcherTapActionRawValue,
            kanaModeSwitcherRightFlickActionRawValue: kanaModeSwitcherRightFlickActionRawValue,
            kanaModeSwitcherUpFlickActionRawValue: kanaModeSwitcherUpFlickActionRawValue,
            kanaPostModifierEmptyTapActionRawValue: kanaPostModifierEmptyTapActionRawValue,
            kanaPostModifierEmptyTapKaomojiCategoryID: kanaPostModifierEmptyTapKaomojiCategoryID,
            kanaPostModifierEmptyTapEmojiCategoryID: kanaPostModifierEmptyTapEmojiCategoryID,
            kanaPostModifierEmptyTapSymbolCategoryID: kanaPostModifierEmptyTapSymbolCategoryID,
            kanaPostModifierFlickDakutenEnabled: kanaPostModifierFlickDakutenEnabled,
            landscapeCandidateSideRawValue: landscapeCandidateSideRawValue,
            landscapeNumberPaneSideRawValue: landscapeNumberPaneSideRawValue,
            landscapeLatinSuggestionModeRawValue: landscapeLatinSuggestionModeRawValue,
            showsNextKeyboardKey: needsInputModeSwitchKey,
            shortcutVocabulary: effectiveShortcutVocabularyForRender(),
            composingText: candidatePresentation.composingText,
            conversionCandidates: candidatePresentation.candidates,
            selectedConversionCandidateIndex: candidatePresentation.selectedIndex,
            latinSuggestionQuery: latinSuggestionQuery,
            latinSuggestions: latinSuggestions,
            showsParenthesesWrapper: hasParenthesesWrapper
        )
    }

    func makeRootView(from configuration: RenderConfiguration) -> KeyboardRootView {
        return KeyboardRootView(
            onTextInput: { [weak self] text in
                self?.handleTextInput(text)
            },
            onDeleteBackward: { [weak self] in
                self?.handleDeleteBackward()
            },
            onSpace: { [weak self] in
                self?.handleSpaceInput()
            },
            onReturn: { [weak self] in
                self?.handleReturnInput()
            },
            onAdvanceKeyboard: { [weak self] in
                self?.advanceToNextInputMode()
            },
            onApplyKanaPostModifier: { [weak self] buttonState, preferLatestContext in
                self?.applyKanaPostModifier(
                    buttonState,
                    preferLatestContext: preferLatestContext
                ) ?? .ignored
            },
            onToggleParenthesesWrapper: { [weak self] in
                self?.toggleParenthesesWrapper()
            },
            onSelectConversionCandidate: { [weak self] index in
                self?.handleConversionCandidateSelection(index)
            },
            onCommitComposingText: { [weak self] in
                self?.handleCommitComposingText()
            },
            onCommitComposingTextAsKatakana: { [weak self] in
                self?.handleCommitComposingTextAsKatakana()
            },
            onUpgradeRecentKanaCommitToKatakana: { [weak self] in
                guard let self else {
                    return false
                }

                let upgraded = self.upgradeRecentKanaCommitToKatakana()

                if upgraded {
                    self.refreshKeyboardStateAsync()
                }

                return upgraded
            },
            onInputModeChanged: { [weak self] mode in
                guard let self else {
                    return
                }

                let previousMode = self.currentInputMode

                guard previousMode != mode else {
                    return
                }

                if previousMode == .kana,
                    mode != .kana {
                    self.commitPendingComposingTextBeforeInputModeSwitch()
                }

                self.currentInputMode = mode
                self.updateKeyboardDiagnosticsHeartbeat(
                    event: "入力モード変更 \(self.keyboardInputModeName(previousMode)) -> \(self.keyboardInputModeName(mode))",
                    appendLog: true
                )

                if mode != .kana {
                    self.clearComposingState()
                }

                self.refreshKeyboardStateAsync()
            },
            showsNextKeyboardKey: configuration.showsNextKeyboardKey,
            directionProfile: configuration.directionProfile,
            kanaLayoutMode: configuration.kanaLayoutMode,
            kanaModifierPlacementMode: configuration.kanaModifierPlacementMode,
            kanaPostModifierButtonState: configuration.kanaPostModifierButtonState,
            numberLayoutMode: configuration.numberLayoutMode,
            latinLayoutMode: configuration.latinLayoutMode,
            accentPaletteRawValue: configuration.accentPaletteRawValue,
            isSystemDictionaryFallback: configuration.isSystemDictionaryFallback,
            keyboardBackgroundThemeRawValue: configuration.keyboardBackgroundThemeRawValue,
            basicSymbolOrderRawValue: configuration.basicSymbolOrderRawValue,
            temperatureUnitRawValue: configuration.temperatureUnitRawValue,
            spaceToastTrigger: configuration.spaceToastTrigger,
            returnKeySystemImageName: configuration.returnKeySystemImageName,
            isReturnKeyEnabled: configuration.isReturnKeyEnabled,
            kanaFlickGuideDisplayMode: configuration.kanaFlickGuideDisplayMode,
            latinFlickGuideDisplayMode: configuration.latinFlickGuideDisplayMode,
            numberFlickGuideDisplayMode: configuration.numberFlickGuideDisplayMode,
            modifierFlickGuideDisplayMode: configuration.modifierFlickGuideDisplayMode,
            keyRepeatInitialDelay: configuration.keyRepeatInitialDelay,
            keyRepeatInterval: configuration.keyRepeatInterval,
            kanaModeSwitcherTapActionRawValue: configuration.kanaModeSwitcherTapActionRawValue,
            kanaModeSwitcherRightFlickActionRawValue: configuration.kanaModeSwitcherRightFlickActionRawValue,
            kanaModeSwitcherUpFlickActionRawValue: configuration.kanaModeSwitcherUpFlickActionRawValue,
            kanaPostModifierEmptyTapActionRawValue: configuration.kanaPostModifierEmptyTapActionRawValue,
            kanaPostModifierEmptyTapKaomojiCategoryID: configuration.kanaPostModifierEmptyTapKaomojiCategoryID,
            kanaPostModifierEmptyTapEmojiCategoryID: configuration.kanaPostModifierEmptyTapEmojiCategoryID,
            kanaPostModifierEmptyTapSymbolCategoryID: configuration.kanaPostModifierEmptyTapSymbolCategoryID,
            kanaPostModifierFlickDakutenEnabled: configuration.kanaPostModifierFlickDakutenEnabled,
            landscapeCandidateSideRawValue: configuration.landscapeCandidateSideRawValue,
            landscapeNumberPaneSideRawValue: configuration.landscapeNumberPaneSideRawValue,
            landscapeLatinSuggestionModeRawValue: configuration.landscapeLatinSuggestionModeRawValue,
            shortcutVocabulary: configuration.shortcutVocabulary,
            candidateBarModel: candidateBarModel,
            showsParenthesesWrapper: configuration.showsParenthesesWrapper,
            initialSpaceToastText: "écritu"
        )
    }
}
