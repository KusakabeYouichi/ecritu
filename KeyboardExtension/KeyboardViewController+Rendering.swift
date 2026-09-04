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
        let numberLayoutMode: NumberLayoutMode
        let latinLayoutMode: LatinLayoutMode
        let accentPaletteRawValue: String
        let isSystemDictionaryFallback: Bool
        let hasFullAccess: Bool
        let keyboardBackgroundThemeRawValue: String
        let basicSymbolOrderRawValue: String
        let temperatureUnitRawValue: String
        let radicalStrokeCountStyleRawValue: String
        let spaceToastTrigger: Int
        let returnKeySystemImageName: String?
        // UIReturnKeyType の文字ラベル(送信/開く/完了/次へ/移動 等。nil=⏎)。2785
        let returnKeyTitleOverride: String?
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
        // キーボードビューのウィンドウ座標の枠(0.5pt 丸め)。iPad 互換モードでは UIScreen.main(iPad 全幅)
        // と食い違い、幅の見積もりを UIScreen から取ると盤面が中央の箱からはみ出す(2786)。zero=未レイアウト
        let containerFrame: CGRect
        let shortcutVocabulary: [String]
        let composingText: String
        let conversionCandidates: [String]
        let selectedConversionCandidateIndex: Int?
        let latinSuggestionQuery: String
        let latinSuggestions: [String]
        let showsParenthesesWrapper: Bool
        // フィールドの keyboardType から決まる初期入力モード。フィールド移動で trait が
        // 変わったときに rootView 差し替えガード(== / equalIgnoringCandidateBar)を通すため
        // configuration に含める(4.4.1: 数字・小数フィールドへの追従)
        let initialInputMode: KeyboardInputMode

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
                numberLayoutMode: numberLayoutMode,
                latinLayoutMode: latinLayoutMode,
                accentPaletteRawValue: accentPaletteRawValue,
                isSystemDictionaryFallback: isSystemDictionaryFallback,
                hasFullAccess: hasFullAccess,
                keyboardBackgroundThemeRawValue: keyboardBackgroundThemeRawValue,
                basicSymbolOrderRawValue: basicSymbolOrderRawValue,
                temperatureUnitRawValue: temperatureUnitRawValue,
                radicalStrokeCountStyleRawValue: radicalStrokeCountStyleRawValue,
                spaceToastTrigger: spaceToastTrigger,
                returnKeySystemImageName: returnKeySystemImageName,
                returnKeyTitleOverride: returnKeyTitleOverride,
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
                containerFrame: containerFrame,
                shortcutVocabulary: shortcutVocabulary,
                composingText: fields.composingText,
                conversionCandidates: fields.conversionCandidates,
                selectedConversionCandidateIndex: fields.selectedConversionCandidateIndex,
                latinSuggestionQuery: fields.latinSuggestionQuery,
                latinSuggestions: fields.latinSuggestions,
                showsParenthesesWrapper: showsParenthesesWrapper,
                initialInputMode: initialInputMode
            )
        }
    }

    // 候補バー系の状態を publish する(値が同じなら publish しない — SwiftUI の無駄な
    // 再評価を避ける)。
    func updateCandidateBarModel(from configuration: RenderConfiguration) {
        let model = candidateBarModel
        // 後置修飾ボタンの状態も publish 経由(2686)。直前文脈から毎回算出する
        let postModifierState = FlickKanaLayout.postModifierButtonState(
            contextBeforeInput: postModifierContextForRender()
        )
        if model.kanaPostModifierButtonState != postModifierState {
            model.kanaPostModifierButtonState = postModifierState
        }
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
    // 後置修飾ボタンの表示状態(アヒルの大小・濁点/半濁点の印)を決める文脈。
    //
    // 後置修飾は未確定文字にしか作用しない(applyKanaPostModifier は確定済み文字列の末尾に
    // 濁点/半濁点/小書きを適用しない)。したがって表示も未確定文字だけから決める。
    // 以前は未確定が無いとき activeConversion.committedText → lastSynchronizedContextBeforeInputTail
    // → currentTextContextBeforeInput() と確定済み文脈へ落ちていたため、キーが作用しない
    // 状況で「小書きにできる」印(小さいアヒル)が出ていた。さらに lastSynchronized… は
    // 診断リセット時にしか空に戻らないキャッシュで、ホスト側で文字を消しても古い末尾を
    // 根拠に小さいアヒルが残り続けた(ユーザ報告 2755)。
    private func postModifierContextForRender() -> String? {
        composingRawText.isEmpty ? nil : composingRawText
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
        // MEMFORENSICS(時限計測 2624): 配列設定の化け(勝手な書き換わり/キー欠落)の監視。
        // 剥がすときはこのブロックと KeyboardMemoryForensics.swift を削除
        MemoryForensics.noteLayoutSettingsSnapshot(
            "kana=\(sharedDefaults?.string(forKey: SharedDefaultsKeys.kanaLayoutMode) ?? "欠落")"
                + " latin=\(sharedDefaults?.string(forKey: SharedDefaultsKeys.latinLayoutMode) ?? "欠落")"
                + " number=\(sharedDefaults?.string(forKey: SharedDefaultsKeys.numberLayoutMode) ?? "欠落")"
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
        let radicalStrokeCountStyleRawValue = sharedStringValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.radicalStrokeCountStyle,
            fallback: ""
        )
        let returnKeyType = textDocumentProxy.returnKeyType
        let hasAnyText = textDocumentProxy.hasText
        let hasPendingComposingText = !candidatePresentation.composingText.isEmpty
        let returnKeySystemImageName: String? = returnKeyType == .search ? "magnifyingglass" : nil
        // .search 以外の種別も表示に反映する(以前は全部 ⏎ で、送信欄で「改行」と読まれていた。2785)
        let returnKeyTitleOverride: String? = returnKeyType.flatMap(Self.returnKeyTitle(for:))
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
            numberLayoutMode: numberLayoutMode,
            latinLayoutMode: latinLayoutMode,
            accentPaletteRawValue: accentPaletteRawValue,
            isSystemDictionaryFallback: kanaKanjiStore.isSystemDictionaryFallback(),
            hasFullAccess: hasFullAccess,
            keyboardBackgroundThemeRawValue: keyboardBackgroundThemeRawValue,
            basicSymbolOrderRawValue: basicSymbolOrderRawValue,
            temperatureUnitRawValue: temperatureUnitRawValue,
            radicalStrokeCountStyleRawValue: radicalStrokeCountStyleRawValue,
            spaceToastTrigger: spaceToastTrigger,
            returnKeySystemImageName: returnKeySystemImageName,
            returnKeyTitleOverride: returnKeyTitleOverride,
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
            // iPad(互換モード含む)は複数キーボード時にシステムが下端バーに 🌐 を出すので、
            // needsInputModeSwitchKey=true でも自前の 🌐 は描かない(二重表示の回避。2786)
            showsNextKeyboardKey: needsInputModeSwitchKey && !Self.isRunningOnIPadHardware,
            containerFrame: Self.roundedToHalfPoint(view.convert(view.bounds, to: nil)),
            shortcutVocabulary: effectiveShortcutVocabularyForRender(),
            composingText: candidatePresentation.composingText,
            conversionCandidates: candidatePresentation.candidates,
            selectedConversionCandidateIndex: candidatePresentation.selectedIndex,
            latinSuggestionQuery: latinSuggestionQuery,
            latinSuggestions: latinSuggestions,
            showsParenthesesWrapper: hasParenthesesWrapper,
            initialInputMode: preferredInitialInputMode()
        )
    }

    // フィールドの keyboardType に入力モードを追従させる(App Store ガイドライン
    // 4.4.1: 数字・小数用のキーボードタイプへの対応)。数値系フィールドでは数字モードで
    // 開く。それ以外は かな。同一フィールド内のユーザ手動切替は上書きしない(trait が
    // 変わったフィールド移動時のみ、rootView の .onChange(of: initialInputMode) で追従)。
    func preferredInitialInputMode() -> KeyboardInputMode {
        switch textDocumentProxy.keyboardType {
        case .numberPad, .decimalPad, .asciiCapableNumberPad, .phonePad, .numbersAndPunctuation:
            return .number
        case .emailAddress, .URL, .asciiCapable:
            // ASCII系フィールドはラテン面で開く(IsASCIICapable 申告とセット。メール/URL欄で
            // かな面で開くと申告実態と食い違う)。数字・記号は面切替で到達できる
            return .latin
        default:
            return .kana
        }
    }

    func makeRootView(from configuration: RenderConfiguration) -> KeyboardRootView {
        var rootView = KeyboardRootView(
            onTextInput: { [weak self] text in
                self?.handleTextInput(text)
            },
            onDeleteBackward: { [weak self] in
                self?.handleDeleteBackward()
            },
            onLookupRadicalEntries: { [weak self] radical in
                self?.kanaKanjiConverter.store.kanjiRadicalIndex().entries(radical: radical) ?? []
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

                // 絵文字モードはピッカー構築で footprint が跳ねる。長寿命プロセスが高水位の
                // まま切り替えると per-process limit の jetsam で即死する(2026-08-14 17:01
                // 実測: footprint 63MB 圏で latin→emoji 切替直後に jetsam(1)
                // per-process-limit(7)。この kill は iOS がレポートを non-actionable として
                // 破棄するため .ips も残らない)。高水位なら先に再構築可能な dirty キャッシュ
                // (LM/word_costs/JSON辞書系。欧文辞書本体は mmap でfootprint非寄与)を落として
                // 余白を作る。sqlite は保持されるので変換は劣化せず、キャッシュは次の利用時に
                // 遅延再構築される。
                // MEMFORENSICS(時限計測 2611): 絵文字ピッカー構築の高水位帰属
                if mode == .emoji {
                    MemoryForensics.noteOperation("絵文字切替")
                    // ピッカー構築そのものの寄与を前後差分で名指しする(2631)。
                    // 1.2s=初期構築、5s=初期スクロール・グリフキャッシュ含む
                    MemoryForensics.noteSpikeWindow("絵文字切替")
                    MemoryForensics.noteSpikeWindow("絵文字切替+5s", delaySeconds: 5.0)
                }
                if previousMode == .emoji {
                    // 退出後に used が戻るか(=グリフキャッシュが解放されるか)の判定材料。
                    // 戻るなら退出時 pressure_relief でページ返却が根治になる(2632)
                    MemoryForensics.noteSpikeWindow("絵文字退出", minDeltaMB: -1_000)
                    MemoryForensics.noteSpikeWindow("絵文字退出+5s", delaySeconds: 5.0, minDeltaMB: -1_000)
                }
                if mode == .emoji,
                    let footprintMB = self.currentFootprintMB(),
                    footprintMB >= 50 {
                    self.kanaKanjiConverter.store.clearSystemDictionaryJSONCaches()
                    // free 済み dirty ページも OS へ返す(census 実測でアリーナ保持が
                    // footprint の主成分だったため。メモリ警告時と同じ処方)
                    malloc_zone_pressure_relief(nil, 0)
                    self.updateKeyboardDiagnosticsHeartbeat(
                        event: "絵文字モード切替前にキャッシュ解放 footprintMB=\(String(format: "%.1f", footprintMB))"
                            + "→\(self.diagnosticsFootprintMBText())",
                        appendLog: true
                    )
                }

                if mode != .kana {
                    self.clearComposingState()
                }

                self.refreshKeyboardStateAsync()
            },
            onFormattedNumberCategoryChanged: { [weak self] in
                // カレンダー↔単位でキーボード高さが変わるため、カテゴリー変更で高さを再計算する。
                self?.updateKeyboardHeightIfNeeded()
            },
            showsNextKeyboardKey: configuration.showsNextKeyboardKey,
            containerFrame: configuration.containerFrame,
            directionProfile: configuration.directionProfile,
            kanaLayoutMode: configuration.kanaLayoutMode,
            kanaModifierPlacementMode: configuration.kanaModifierPlacementMode,
            numberLayoutMode: configuration.numberLayoutMode,
            latinLayoutMode: configuration.latinLayoutMode,
            accentPaletteRawValue: configuration.accentPaletteRawValue,
            isSystemDictionaryFallback: configuration.isSystemDictionaryFallback,
            hasFullAccess: configuration.hasFullAccess,
            keyboardBackgroundThemeRawValue: configuration.keyboardBackgroundThemeRawValue,
            basicSymbolOrderRawValue: configuration.basicSymbolOrderRawValue,
            temperatureUnitRawValue: configuration.temperatureUnitRawValue,
            radicalStrokeCountStyleRawValue: configuration.radicalStrokeCountStyleRawValue,
            spaceToastTrigger: configuration.spaceToastTrigger,
            returnKeySystemImageName: configuration.returnKeySystemImageName,
            returnKeyTitleOverride: configuration.returnKeyTitleOverride,
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
            initialSpaceToastText: "écritu",
            initialInputMode: configuration.initialInputMode
        )
        // 寸法・位置の端末別分岐(KeyboardLayoutMetrics)。引数順に依存しないよう生成後に渡す。
        rootView.layoutMetrics = layoutMetrics
        return rootView
    }

    // UIReturnKeyType → キーの文字ラベル。純正キーボードの日本語表記に合わせる。
    // .default/.search(アイコン)/.join/.route/.emergencyCall/.continue は nil(⏎)
    static func returnKeyTitle(for type: UIReturnKeyType) -> String? {
        switch type {
        case .go: return "開く"
        case .send: return "送信"
        case .done: return "完了"
        case .next: return "次へ"
        case .google, .yahoo: return "検索"
        default: return nil
        }
    }

    static func roundedToHalfPoint(_ rect: CGRect) -> CGRect {
        func r(_ v: CGFloat) -> CGFloat { (v * 2).rounded() / 2 }
        return CGRect(x: r(rect.minX), y: r(rect.minY), width: r(rect.width), height: r(rect.height))
    }

    // 実ハードウェアが iPad か(iPhone 専用アプリの互換モードでは userInterfaceIdiom が .phone を返すため
    // sysctl hw.machine で判定。"iPad8,3" 等)。必須理由 API ではない
    static let isRunningOnIPadHardware: Bool = {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        guard size > 0 else { return false }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &buffer, &size, nil, 0)
        return String(cString: buffer).hasPrefix("iPad")
    }()
}
