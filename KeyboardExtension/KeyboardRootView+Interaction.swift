import SwiftUI
import UIKit
import CoreFoundation
import Darwin

extension KeyboardRootView {
    func commitText(_ text: String) {
        inputState.commitText(text, shiftDoubleTapThreshold: shiftDoubleTapThreshold, onTextInput: onTextInput)
    }

    func consumeReturnToKanaAfterNextCommitIfNeeded() {
        inputState.consumeReturnToKanaAfterNextCommitIfNeeded()
    }

    func selectModifierMode(_ output: String) {
        selectModifierMode(output, direction: .milieu)
    }

    func selectModifierMode(_ output: String, direction: FlickDirection) {
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

        let prefersLatestContextResolution = direction == .milieu
        let outcome = onApplyKanaPostModifier(
            buttonState,
            prefersLatestContextResolution
        )

        switch outcome {
        case .applied:
            var next = transitionState
            next.diacriticMode = .none
            transitionState = next
        case .idleEmptyContext:
            if direction == .milieu {
                performPostModifierEmptyTapAction()
            }
        case .ignored:
            break
        }
    }

    func performPostModifierEmptyTapAction() {
        inputState.applyPostModifierEmptyTap(
            actionRawValue: kanaPostModifierEmptyTapActionRawValue,
            emojiCategoryID: kanaPostModifierEmptyTapEmojiCategoryID,
            symbolCategoryID: kanaPostModifierEmptyTapSymbolCategoryID,
            kaomojiCategoryID: kanaPostModifierEmptyTapKaomojiCategoryID,
            kaomojiPanel: kaomojiPanelState
        )
    }

    func commitEmojiKaomojiSymbolText(_ text: String) {
        // 履歴に足すかどうかの規則はモデル側(3243)。顔文字の分類がショートカットかどうかだけ渡す
        inputState.commitEmojiKaomojiSymbolText(
            text,
            isKaomojiShortcutCategory: kaomojiPanelState.isShortcutCategorySelected,
            onShortcutCandidateCommitted: onShortcutCandidateCommitted,
            onTextInput: onTextInput
        )
    }

    // 書式化数値入力モード: 左端モード列 最下段キーの長押しで起動。1件確定でかなへ戻す。
    func enterFormattedNumberMode() {
        formattedNumberState.resetBuffer()
        inputState.enterFormattedNumberMode()
    }

    func deleteFormattedNumberBackward() {
        formattedNumberState.deleteBackward()
    }

    // 確定: 現在のバッファを整形(3桁区切り/小数点)してホストへ挿入し、かな入力へ戻す。
    func commitFormattedNumber() {
        // カレンダーは日付ホイールから常に確定できる。単位系は数値未入力なら何もせず戻す。
        guard let text = formattedNumberState.takeCommitText(settings: formattedNumberFormatSettings) else {
            switchInputMode(.kana)
            return
        }
        onTextInput(text)
        consumeReturnToKanaAfterNextCommitIfNeeded()
    }

    func postModifierButtonState(forModifierOutput output: String) -> KanaPostModifierButtonState? {
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

    func switchInputMode(_ mode: KeyboardInputMode) {
        inputState.switchInputMode(mode)
    }

    func switchToLatinMode(with shiftState: LatinShiftState) {
        inputState.switchToLatinMode(with: shiftState)
    }

    func handleLatinModeSwitchTap() {
        guard inputMode != .latin else {
            return
        }

        switchToLatinMode(with: .off)
        startLatinModeSwitchSecondTapWindow()
    }

    func handleLatinModeSwitchDoubleTap() {
        guard inputMode == .latin,
                isAwaitingLatinModeSwitchSecondTap else {
            return
        }

        cancelLatinModeSwitchSecondTapWindow()
        switchToLatinMode(with: .locked)
    }

    func handleLatinModeSwitchLongPress() {
        cancelLatinModeSwitchSecondTapWindow()
        switchToLatinMode(with: .locked)
    }

    func startLatinModeSwitchSecondTapWindow() {
        inputState.startLatinModeSwitchSecondTapWindow(threshold: latinModeSwitchDoubleTapThreshold)
    }

    func cancelLatinModeSwitchSecondTapWindow() {
        inputState.cancelLatinModeSwitchSecondTapWindow()
    }

    func handleComposingTextCommitTap() {
        guard canTapComposingTextToCommit else {
            return
        }

        if didTriggerComposingCommitLongPress {
            didTriggerComposingCommitLongPress = false
            return
        }

        onCommitComposingText()
    }

    func handleComposingTextCommitLongPress() {
        guard canTapComposingTextToCommit else {
            return
        }

        didTriggerComposingCommitLongPress = true
        triggerKatakanaComposingCommitFeedbackAndCommit()
    }

    func handleReturnKeyKatakanaDoubleTap() {
        if !composingText.isEmpty {
            triggerKatakanaComposingCommitFeedbackAndCommit()
            return
        }

        _ = onUpgradeRecentKanaCommitToKatakana()
    }

    func handleReturnKeyKatakanaLongPress() {
        if !composingText.isEmpty {
            triggerKatakanaComposingCommitFeedbackAndCommit()
        }
    }

    func triggerKatakanaComposingCommitFeedbackAndCommit() {
        guard !composingText.isEmpty else {
            return
        }

        cancelPendingKatakanaCommit()

        let previewText = composingText
        katakanaCommitFeedbackText = previewText

        let workItem = DispatchWorkItem {
            self.pendingKatakanaCommitWorkItem = nil
            self.katakanaCommitFeedbackText = nil
            onCommitComposingTextAsKatakana()
        }

        pendingKatakanaCommitWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + katakanaCommitFeedbackDelay, execute: workItem)
    }

    func isShowingKatakanaCommitFeedback(for text: String) -> Bool {
        katakanaCommitFeedbackText == text
    }

    func cancelPendingKatakanaCommit() {
        pendingKatakanaCommitWorkItem?.cancel()
        pendingKatakanaCommitWorkItem = nil
        katakanaCommitFeedbackText = nil
    }

    // 面選択のパレット(左下キーの長押しで縦に出す。3124)。よく使う面はタップとフリックに残し、
    // たまにしか使わない面はラベルを読んで選べるようにする。長押しの書式化入力もここへ移した
    // 「部首」→「単漢字」(ユーザー指定 3194)。部首を入力する面ではなく、部首や画数から
    // 1 文字を探して入れる面なので、機能を言い当てる名前にする
    static let modePaletteLabels: [String] = ["記号", "絵文字", "顔文字", "単漢字", "書式化"]

    func selectModePalette(_ label: String) -> Bool {
        guard let target = KeyboardPanelRouting.panelTarget(forPaletteLabel: label) else {
            return false
        }
        // 書式化数値はバッファーも空にするのでビューから入る
        if target == .formattedNumber {
            enterFormattedNumberMode()
        } else {
            inputState.enterPanel(target)
        }
        #if DEBUG
        inputModeChangeTrigger = "面選択パレット(\(label))"  // 調査用ログ(記号面切替 2838)
        #endif
        return true
    }

    // キー部品の onCommit の型に合わせて出力文字列を受ける。切替キーは通常ラベル文字を出力しないが、
    // パレットから決めたときだけ選んだ面のラベルが渡る。方向は受けない(左下のキーのフリックは
    // パレットに先取りされて届かないので、届いてもタップ扱い。3174 以降)
    func selectKanaModeSwitcher(_ text: String) {
        if selectModePalette(text) {
            return
        }
        selectKanaModeSwitcher(direction: .milieu)
    }

    func selectCompactKeyboardSwitchKey(_: String) {
        selectCompactKeyboardSwitchKey(direction: .milieu)
    }

    func selectCompactKeyboardSwitchKey(_: String, direction: FlickDirection) {
        selectCompactKeyboardSwitchKey(direction: direction)
    }

    func selectCompactKeyboardSwitchKey(direction: FlickDirection) {
        switch KeyboardPanelRouting.compactSwitchKeyRoute(direction: direction) {
        case .advanceKeyboard:
            onAdvanceKeyboard()
        case .switchPanel:
            selectKanaModeSwitcher(direction: direction)
        case .ignore:
            return
        }
    }

    func handleCompactKeyboardSwitchLongPress() {
        selectKanaModeSwitcher(direction: .milieu, triggerLabel: "左下キー長押し(コンパクト)")
    }

    /// 面の切り替えを「短すぎる接触」として無視するか(定数コメント参照。2938)。
    /// 測れなかったとき(nil)と負値は通す。文字入力のキーはこの判定を通らない
    static func shouldIgnoreModeSwitchForShortTouch(commitDurationMs: Int?) -> Bool {
        guard let commitDurationMs, commitDurationMs >= 0 else {
            return false
        }
        return commitDurationMs < kanaModeSwitcherMinimumTouchDurationMs
    }

    func selectKanaModeSwitcher(direction: FlickDirection, triggerLabel: String? = nil) {
        // 短すぎる接触では面を切り替えない(2938、ユーザ報告: 机に置いた衝撃で部首入力面になった)。
        // 実測の誤発火は接触 58ms・開始位置がキーの外(-6,44)・移動量 41pt の下フリック。人のタップは
        // 概ね 80〜150ms なので、面の切り替えという戻しにくい操作にだけ下限を設ける。
        // 文字入力のキーは対象外(この分岐を通らない)。測れなかったとき(nil)は通す。
        // 却下は診断へ残すので、実使用で弾かれるようなら閾値を下げるか撤去する
        if Self.shouldIgnoreModeSwitchForShortTouch(
            commitDurationMs: KeyboardStuckTouchDiagnostics.lastCommitDurationMs
        ) {
            let durationMs = KeyboardStuckTouchDiagnostics.lastCommitDurationMs ?? -1
            KeyboardStuckTouchDiagnostics.onTouchForensics?(
                "面切替を却下(接触が短すぎ) dir=\(direction) durMs=\(durationMs)"
                    + " 下限=\(Self.kanaModeSwitcherMinimumTouchDurationMs)ms"
            )
            return
        }
        // 割り当て(下=単漢字固定、タップ/右/上=設定)と引き金の記録は inputState が行なう
        inputState.selectModeSwitcherPanel(
            direction: direction,
            triggerLabel: triggerLabel,
            tapAction: kanaModeSwitcherTapAction,
            rightAction: kanaModeSwitcherRightFlickAction,
            upAction: kanaModeSwitcherUpFlickAction
        )
    }

    // 単漢字・顔文字の面へはパレットと左下キーから inputState 経由で入る。ビュー側の取り次ぎは
    // 面内のキーから呼ぶ絵文字と記号の 2 つだけ残す
    func enterEmojiMode() {
        inputState.enterEmojiMode()
    }

    func enterSymbolsMode() {
        inputState.enterSymbolsMode()
    }

    func spaceActionKeyButton(
        title: String,
        titleOpacity: Double = 1,
        fixedWidth: CGFloat? = nil
    ) -> some View {
        SpaceFlickActionKeyButton(
            title: title,
            titleOpacity: titleOpacity,
            fixedWidth: fixedWidth,
            accessibilityLabelText: spaceKeyAccessibilityLabel,
            onSpace: onSpace,
            onTab: { onTextInput("\t") },
            // 変換キーとして働く間だけ長押しで候補送り(Apple 純正と同じ)。空白入力では連打しない
            repeatsWhileHolding: isSpaceActsAsConversionKey
        )
    }

    func showInitialSpaceToastIfNeeded() {
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

    func spaceKeyButton(
        fixedWidth: CGFloat?,
        keyHeight: CGFloat? = nil
    ) -> some View {
        let resolvedKeyHeight = keyHeight ?? compactActionKeyHeight

        return spaceActionKeyButton(
            title: spaceKeyDisplayTitle,
            titleOpacity: spaceKeyDisplayOpacity,
            fixedWidth: fixedWidth
        )
        .frame(maxWidth: fixedWidth == nil ? .infinity : nil)
        .frame(height: resolvedKeyHeight)
    }

    func longPressCandidates(for kana: FlickKanaSet) -> [String] {
        guard inputMode == .latin else {
            return []
        }

        let candidates = FlickKanaLayout.latinLongPressCandidates(for: kana.center, layoutMode: latinLayoutMode)

        guard latinShiftState != .off else {
            return candidates
        }

        return candidates.map(uppercasedLongPressCandidate)
    }

    func longPressCandidatePanelPlacement(forRowIndex rowIndex: Int) -> LongPressCandidatePanelPlacement {
        if isLandscapeLayout,
            inputMode == .latin,
            rowIndex == 0 {
            return .below
        }

        return .above
    }

    func uppercasedLongPressCandidate(_ candidate: String) -> String {
        if candidate == "ß" {
            return "ẞ"
        }

        return candidate.uppercased()
    }

    func allowsDirectionalFlick(for kana: FlickKanaSet) -> Bool {
        guard inputMode == .latin,
                latinLayoutMode != .flick,
                isLatinAlphabetKey(kana.center) else {
            return true
        }

        return false
    }

    func displayedKanaForKanaCharacterModeIfNeeded(_ kana: FlickKanaSet) -> FlickKanaSet {
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

    func kanaTextForDisplay(_ text: String) -> String {
        text.applyingTransform(.hiraganaToKatakana, reverse: false) ?? text
    }

    func displayedKana(for kana: FlickKanaSet) -> FlickKanaSet {
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

    func latinFlickIdleReplacement(for kana: FlickKanaSet) -> AnyView? {
        guard inputMode == .latin,
                latinLayoutMode == .flick,
                            isCurrentFlickGuideDisplayOff else {
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

    func latinFlickCompactText(for kana: FlickKanaSet) -> String {
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

    func numberPunctuationIdleReplacement(for kana: FlickKanaSet) -> AnyView? {
        guard inputMode == .number,
                isCurrentFlickGuideDisplayOff,
                            effectiveNumberLayoutMode != .clavier,
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

    func rowKeyIdleReplacement(for kana: FlickKanaSet) -> AnyView? {
        if let latinReplacement = latinFlickIdleReplacement(for: kana) {
            return latinReplacement
        }

        if let numberReplacement = numberPunctuationIdleReplacement(for: kana) {
            return numberReplacement
        }

        return nil
    }

    var punctuationIdleReplacement: AnyView? {
        guard inputMode == .kana,
                            isCurrentFlickGuideDisplayOff else {
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

    func isLatinShiftKey(_ kana: FlickKanaSet) -> Bool {
        kana.center == FlickKanaLayout.latinShiftKeyToken
    }

    func handleLatinShiftTap() {
        inputState.handleLatinShiftTap(now: Date(), doubleTapThreshold: shiftDoubleTapThreshold)
    }

    func handleLatinShiftLongPress() {
        transitionState = KeyboardModeTransition.handleLatinShiftLongPress(
            transitionState
        )
    }

    func isLatinAlphabetKey(_ value: String) -> Bool {
        guard value.count == 1,
                let scalar = value.unicodeScalars.first else {
            return false
        }

        return CharacterSet.letters.contains(scalar)
    }

    func updateActiveLayer(_ isTouching: Bool, layerIndex: Int, isLeftModeSwitchColumn: Bool = false) {
        if isLeftModeSwitchColumn {
            isTouchingLeftModeSwitchColumn = isTouching
        }

        if isTouching {
            activeLayerIndex = layerIndex
            return
        }

        if activeLayerIndex == layerIndex {
            activeLayerIndex = nil
        }
    }

    // 左の面切替の列の重なり順(3167)。列のキーを触っているあいだ、または何も触っていないときは
    // 段より前(列の吹き出しが段に隠れないように)。段のキーを触っているあいだは段より後ろへ下げ、
    // あ・た・濁点の左フリックの吹き出しが列に隠れないようにする。休んでいる段(0)よりは前に置く
    // 列と段の束は HStack の兄弟なので、勝ち負けはこの 2 つの値だけで決まる(段の内部の
    // zIndex は束の中の順序にしか効かない。3167 はここを取り違えて効かなかった)
    var leftModeSwitchColumnZIndex: Double {
        isTouchingLeftModeSwitchColumn || activeLayerIndex == nil ? 2 : 0
    }

    var kanaMainClusterZIndex: Double { 1 }

    func zIndex(for layerIndex: Int) -> Double {
        activeLayerIndex == layerIndex ? KeyboardLayerZIndex.activeRow : 0
    }

    var modifierIdleReplacement: AnyView? {
        guard inputMode == .kana, isModifierFlickGuideDisplayOff else {
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
