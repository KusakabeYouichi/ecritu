import SwiftUI
import UIKit
import CoreFoundation
import Darwin
import Contacts

extension KeyboardRootView {
    func commitText(_ text: String) {
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

        consumeReturnToKanaAfterNextCommitIfNeeded()
    }

    func consumeReturnToKanaAfterNextCommitIfNeeded() {
        guard returnToKanaAfterNextCommit else {
            return
        }

        returnToKanaAfterNextCommit = false
        switchInputMode(.kana)
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
        switch kanaPostModifierEmptyTapActionRawValue {
        case "emoji":
            if let rawValue = Int(kanaPostModifierEmptyTapEmojiCategoryID),
                let category = EmojiCategory(rawValue: rawValue) {
                selectedEmojiCategory = category
            }
            enterEmojiMode()
        case "symbols":
            if let rawValue = Int(kanaPostModifierEmptyTapSymbolCategoryID),
                let category = SymbolCategory(rawValue: rawValue) {
                selectedSymbolCategory = category
            }
            enterSymbolsMode()
        default:
            selectedKaomojiCategoryID = kanaPostModifierEmptyTapKaomojiCategoryID
            enterKaomojiMode()
        }

        returnToKanaAfterNextCommit = true
    }

    func commitEmojiKaomojiSymbolText(_ text: String) {
        onTextInput(text)
        consumeReturnToKanaAfterNextCommitIfNeeded()
    }

    // 書式化数値入力モード: 左端モード列 最下段キーの長押しで起動。1件確定でかなへ戻す。
    func enterFormattedNumberMode() {
        formattedNumberBuffer = ""
        transitionState = KeyboardModeTransition.enterFormattedNumberMode(from: transitionState)
        returnToKanaAfterNextCommit = true
    }

    // テンキーからの数字/記号入力はホストへ流さず、ローカルバッファに溜めてプレビューする。
    func appendFormattedNumber(_ token: String) {
        formattedNumberBuffer.append(token)
    }

    func deleteFormattedNumberBackward() {
        guard !formattedNumberBuffer.isEmpty else {
            return
        }
        formattedNumberBuffer.removeLast()
    }

    // 確定: 現在のバッファを整形(3桁区切り/小数点)してホストへ挿入し、かな入力へ戻す。
    // 単位記号の付与・間隔設定は後続フェーズ。
    func commitFormattedNumber() {
        guard !formattedNumberBuffer.isEmpty else {
            formattedNumberBuffer = ""
            switchInputMode(.kana)
            return
        }
        let text = formattedNumberDisplayString()
        formattedNumberBuffer = ""
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
        if mode != .latin {
            cancelLatinModeSwitchSecondTapWindow()
        }

        if mode != .emoji, mode != .formattedNumber {
            returnToKanaAfterNextCommit = false
        }

        transitionState = KeyboardModeTransition.switchInputMode(
            transitionState,
            to: mode
        )
    }

    func switchToLatinMode(with shiftState: LatinShiftState) {
        var next = KeyboardModeTransition.switchInputMode(
            transitionState,
            to: .latin
        )

        next.latinShiftState = shiftState
        next.lastLatinShiftTapAt = nil
        transitionState = next
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
        cancelLatinModeSwitchSecondTapWindow()
        isAwaitingLatinModeSwitchSecondTap = true

        let safeThreshold = max(0.05, latinModeSwitchDoubleTapThreshold)
        let workItem = DispatchWorkItem {
            self.pendingLatinModeSwitchSecondTapResetWorkItem = nil
            self.isAwaitingLatinModeSwitchSecondTap = false
        }

        pendingLatinModeSwitchSecondTapResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + safeThreshold, execute: workItem)
    }

    func cancelLatinModeSwitchSecondTapWindow() {
        pendingLatinModeSwitchSecondTapResetWorkItem?.cancel()
        pendingLatinModeSwitchSecondTapResetWorkItem = nil
        isAwaitingLatinModeSwitchSecondTap = false
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

    func selectKanaModeSwitcher(_ output: String) {
        selectKanaModeSwitcher(output, direction: .milieu)
    }

    func selectCompactKeyboardSwitchKey(_ output: String) {
        selectCompactKeyboardSwitchKey(output, direction: .milieu)
    }

    func selectCompactKeyboardSwitchKey(_ output: String, direction: FlickDirection) {
        switch direction {
        case .milieu:
            onAdvanceKeyboard()
        case .droite, .haut:
            selectKanaModeSwitcher(output, direction: direction)
        default:
            return
        }
    }

    func handleCompactKeyboardSwitchLongPress() {
        selectKanaModeSwitcher(kanaModeSwitcherTapAction.keyLabel, direction: .milieu)
    }

    func selectKanaModeSwitcher(_ output: String, direction: FlickDirection) {
        let action: KanaModeSwitcherAction

        switch direction {
        case .milieu:
            action = kanaModeSwitcherTapAction
        case .droite:
            action = kanaModeSwitcherRightFlickAction
        case .haut:
            action = kanaModeSwitcherUpFlickAction
        default:
            return
        }

        switch action {
        case .emoji:
            enterEmojiMode()
        case .kaomoji:
            enterKaomojiMode()
        case .symbols:
            enterSymbolsMode()
        }
    }

    func enterEmojiMode() {
        transitionState = KeyboardModeTransition.enterEmojiMode(
            from: transitionState
        )
    }

    func enterKaomojiMode() {
        transitionState = KeyboardModeTransition.enterKaomojiMode(
            from: transitionState
        )
    }

    func enterSymbolsMode() {
        transitionState = KeyboardModeTransition.enterSymbolsMode(
            from: transitionState
        )
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
            onTab: { onTextInput("\t") }
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

    func shouldApplyLatinShift(to text: String) -> Bool {
        guard inputMode == .latin,
                latinShiftState != .off,
                isLatinAlphabetKey(text) else {
            return false
        }

        return true
    }

    func convertedKanaOutputIfNeeded(_ text: String) -> String {
        guard inputMode == .kana,
                kanaCharacterMode == .katakana else {
            return text
        }

        return text.applyingTransform(.hiraganaToKatakana, reverse: false) ?? text
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
        transitionState = KeyboardModeTransition.handleLatinShiftTap(
            transitionState,
            now: Date(),
            doubleTapThreshold: shiftDoubleTapThreshold
        )
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

    func updateActiveLayer(_ isTouching: Bool, layerIndex: Int) {
        if isTouching {
            activeLayerIndex = layerIndex
            return
        }

        if activeLayerIndex == layerIndex {
            activeLayerIndex = nil
        }
    }

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
