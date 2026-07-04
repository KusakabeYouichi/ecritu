import Foundation
import UIKit

extension KeyboardViewController {
    enum KanaPostModifierSafetyLimits {
        static let rapidDakutenSecondTapSuppressionSec: CFTimeInterval = 0.14
    }

    static let rapidDakutenSecondTapTargets: Set<Character> = ["っ", "ぅ"]

    func handleTextInput(_ text: String) {
        guard !text.isEmpty else {
            return
        }

        clearRecentKanaPlainCommitUpgradeContext()

        if currentInputMode == .kana,
            let activeConversion,
            shouldAutoCommitConversion(beforeInserting: text) {
            commitActiveConversionBeforeDelimiterInput(activeConversion, delimiter: text)
            refreshKeyboardStateForUserInitiatedAction(.kanaInput)
            return
        }

        commitActiveConversion(learn: true)

        if currentInputMode == .kana,
            let normalizedKana = KanaTextNormalizer.normalizedKanaCharacter(from: text) {
            if composingRawText.isEmpty {
                rememberComposingContextPrefixTail()
            }

            composingRawText.append(text)
            composingReading.append(normalizedKana)

            setMarkedComposingText(composingRawText)
        } else {
            if currentInputMode == .kana,
                !composingReading.isEmpty,
                shouldAutoCommitConversion(beforeInserting: text) {
                commitComposingTextBeforeDelimiterInput(delimiter: text)
                refreshKeyboardStateForUserInitiatedAction(.kanaInput)
                return
            }

            if !composingRawText.isEmpty {
                markTextProxyEdit()
                textDocumentProxy.unmarkText()
                clearComposingState()
            }

            markTextProxyEdit()
            textDocumentProxy.insertText(text)
            clearComposingState()
        }

        if currentInputMode == .kana {
            refreshKeyboardStateForUserInitiatedAction(.kanaInput)
        } else {
            refreshKeyboardStateAsync()
        }
    }

    func shouldAutoCommitConversion(beforeInserting text: String) -> Bool {
        guard !text.isEmpty else {
            return false
        }

        return text.unicodeScalars.allSatisfy { scalar in
            CharacterSet.punctuationCharacters.contains(scalar)
                || CharacterSet.symbols.contains(scalar)
        }
    }

    func commitComposingTextBeforeDelimiterInput(delimiter: String) {
        clearRecentKanaPlainCommitUpgradeContext()

        guard !composingRawText.isEmpty,
                !composingReading.isEmpty else {
            markTextProxyEdit()
            textDocumentProxy.unmarkText()
            clearComposingState()
            return
        }

        let sourceText = composingRawText
        let sourceReading = composingReading

        // 表示中の候補(非同期で連文節変換をマージ済み)をそのまま使う。以前は同期の単文節候補
        // (kanaKanjiCandidates)だけを見ており、連文節しか変換が無い長文では index1 が存在せず
        // 設定に関わらず常に未変換かなへ fallback していた。表示中候補なら「先頭の変換候補」設定が
        // 連文節にも効き、かつ主スレッドでの連文節DP再計算も避けられる。
        let presentationCandidates = currentCandidatePresentationForRender(
            systemCandidateMode: currentKanaKanjiCandidateSourceModeFromSharedDefaults()
        ).candidates

        // 自動確定候補: index0=未変換かな, index1=表示中の先頭変換候補, ... 。設定
        // delimiterAutoCommitCandidate(既定=先頭の変換候補=index1)でどれを確定するか選ぶ。
        // 確定キーは別実装で常に未変換かな。
        // かなが正書の読み(ちゃんと 等)や学習済みかな識別では表示先頭がかな自身になる。
        // その場合は index1 にもかなを置く(重複除外で次の漢字候補が繰り上がると、
        // ちゃんと。→喜屋武と のような不本意な自動確定になるため)。
        var autoCommitCandidates: [String] = [sourceText]
        if let first = presentationCandidates.first, first == sourceText {
            autoCommitCandidates.append(first)
        }
        for candidate in presentationCandidates where !autoCommitCandidates.contains(candidate) {
            autoCommitCandidates.append(candidate)
        }

        let preferredIndex = currentDelimiterAutoCommitCandidateIndexFromSharedDefaults()
        let preferredCandidate: String?

        if autoCommitCandidates.indices.contains(preferredIndex) {
            preferredCandidate = autoCommitCandidates[preferredIndex]
        } else {
            preferredCandidate = autoCommitCandidates.first
        }

        let committedText = preferredCandidate ?? sourceText
        commitComposingText(
            sourceText: sourceText,
            sourceReading: sourceReading,
            committedText: committedText,
            learn: true,
            trailingText: delimiter
        )
    }

    func commitActiveConversionBeforeDelimiterInput(
        _ conversion: ActiveConversion,
        delimiter: String
    ) {
        var autoCommitCandidates: [String] = [conversion.sourceText]

        for candidate in conversion.candidates where !autoCommitCandidates.contains(candidate) {
            autoCommitCandidates.append(candidate)
        }

        let preferredIndex = currentDelimiterAutoCommitCandidateIndexFromSharedDefaults()
        let preferredCandidate: String

        if autoCommitCandidates.indices.contains(preferredIndex) {
            preferredCandidate = autoCommitCandidates[preferredIndex]
        } else if let fallbackCandidate = autoCommitCandidates.first {
            preferredCandidate = fallbackCandidate
        } else {
            preferredCandidate = conversion.committedText
        }

        commitActiveConversion(
            conversion,
            committedText: preferredCandidate,
            learn: true,
            trailingText: delimiter
        )
    }

    func handleDeleteBackward() {
        if revertIdleCommitToComposingIfNeeded() {
            return
        }

        clearRecentKanaPlainCommitUpgradeContext()

        if activeConversion != nil {
            commitActiveConversion(learn: false)
            clearComposingState()
            markTextProxyEdit()
            textDocumentProxy.deleteBackward()
            refreshKeyboardStateAsync()
            return
        }

        if !composingRawText.isEmpty {
            composingRawText.removeLast()

            if !composingReading.isEmpty {
                composingReading.removeLast()
            }

            if composingRawText.isEmpty {
                clearMarkedComposingText()
                clearComposingState()
            } else {
                setMarkedComposingText(composingRawText)
            }

            refreshKeyboardStateAsync()
            return
        }

        if hasParenthesesWrapper {
            hasParenthesesWrapper = false
            refreshKeyboardStateAsync()
            return
        }

        markTextProxyEdit()
        textDocumentProxy.deleteBackward()
        refreshKeyboardStateAsync()
    }

    func handleSpaceInput() {
        clearRecentKanaPlainCommitUpgradeContext()

        guard currentInputMode == .kana else {
            commitActiveConversion(learn: true)

            if !composingRawText.isEmpty {
                markTextProxyEdit()
                textDocumentProxy.unmarkText()
            }

            clearComposingState()
            markTextProxyEdit()
            textDocumentProxy.insertText(" ")
            refreshKeyboardStateAsync()
            return
        }

        if activeConversion != nil {
            cycleActiveConversionCandidate()
            refreshKeyboardStateAsync()
            return
        }

        guard !composingReading.isEmpty else {
            if hasParenthesesWrapper {
                hasParenthesesWrapper = false
            }

            markTextProxyEdit()
            textDocumentProxy.insertText(" ")
            refreshKeyboardStateAsync()
            return
        }

        guard beginConversionFromComposingText() else {
            markTextProxyEdit()
            textDocumentProxy.unmarkText()
            markTextProxyEdit()
            textDocumentProxy.insertText(" ")
            clearComposingState()
            refreshKeyboardStateAsync()
            return
        }

        refreshKeyboardStateAsync()
    }

    func handleReturnInput() {
        let hasActiveConversion = activeConversion != nil
        let hasComposingText = !composingRawText.isEmpty

        if hasActiveConversion {
            if let activeConversion {
                rememberRecentKanaPlainCommit(
                    sourceText: activeConversion.sourceText,
                    sourceReading: activeConversion.reading,
                    committedText: activeConversion.sourceText
                )
            }

            commitActiveConversion(learn: true)
            refreshKeyboardStateForUserInitiatedAction(.commit)
            return
        }

        if hasComposingText {
            rememberRecentKanaPlainCommit(
                sourceText: composingRawText,
                sourceReading: composingReading,
                committedText: composingRawText
            )

            commitComposingText(
                sourceText: composingRawText,
                sourceReading: composingReading,
                committedText: composingRawText,
                learn: true
            )
            refreshKeyboardStateForUserInitiatedAction(.commit)
            return
        }

        if hasParenthesesWrapper {
            clearRecentKanaPlainCommitUpgradeContext()
            markTextProxyEdit()
            textDocumentProxy.insertText("()")
            clearComposingState()
            refreshKeyboardStateAsync()
            return
        }

        clearRecentKanaPlainCommitUpgradeContext()
        clearComposingState()
        markTextProxyEdit()
        textDocumentProxy.insertText("\n")
        refreshKeyboardStateAsync()
    }

    func handleConversionCandidateSelection(_ index: Int) {
        clearRecentKanaPlainCommitUpgradeContext()

        if currentInputMode == .latin {
            let token = currentLatinSuggestionQueryFromTextContext()

            guard !token.isEmpty else {
                return
            }

            let suggestions = currentLatinSuggestions(limit: CandidateLimits.latinSuggestionDefault)

            guard suggestions.indices.contains(index) else {
                return
            }

            commitLatinSuggestion(suggestions[index], replacing: token)
            refreshKeyboardStateAsync()
            return
        }

        guard currentInputMode == .kana else {
            return
        }

        if let conversion = activeConversion {
            guard conversion.candidates.indices.contains(index) else {
                return
            }

            let selectedCandidate = conversion.candidates[index]
            commitActiveConversion(
                conversion,
                committedText: selectedCandidate,
                learn: true
            )
            refreshKeyboardStateAsync()
            return
        }

        guard !composingReading.isEmpty else {
            return
        }

        // 表示に使っているのと同一の候補リストを index 参照する(再計算しない)。
        // 連文節候補は非同期経路(settled presentation)にのみ挿入されるため、ここで
        // kanaKanjiCandidates を再計算すると表示とズレて末尾候補が範囲外になり、タップ
        // しても確定しない不具合になっていた。表示と同じ presentation を使うことで一致させる。
        let presentation = currentCandidatePresentationForRender(
            systemCandidateMode: currentKanaKanjiCandidateSourceModeFromSharedDefaults()
        )

        guard presentation.candidates.indices.contains(index) else {
            return
        }

        commitComposingText(
            sourceText: composingRawText,
            sourceReading: composingReading,
            committedText: presentation.candidates[index],
            learn: true
        )
        refreshKeyboardStateAsync()
    }

    func commitLatinSuggestion(_ suggestion: String, replacing token: String) {
        guard !suggestion.isEmpty,
            !token.isEmpty else {
            return
        }

        commitActiveConversion(learn: true)

        if !composingRawText.isEmpty {
            markTextProxyEdit()
            textDocumentProxy.unmarkText()
            clearComposingState()
        }

        let contextBeforeInput = currentTextContextBeforeInput()

        if contextBeforeInput.hasSuffix(token) {
            deleteBackwardCharacterCount(token.count)
        }

        markTextProxyEdit()
        textDocumentProxy.insertText(suggestion)
        clearComposingState()
    }

    func handleCommitComposingText() {
        clearRecentKanaPlainCommitUpgradeContext()

        guard currentInputMode == .kana else {
            return
        }

        if let activeConversion {
            commitActiveConversion(
                activeConversion,
                committedText: activeConversion.sourceText,
                learn: true
            )
            clearComposingState()
            refreshKeyboardStateForUserInitiatedAction(.commit)
            return
        }

        guard !composingRawText.isEmpty else {
            return
        }

        commitComposingText(
            sourceText: composingRawText,
            sourceReading: composingReading,
            committedText: composingRawText,
            learn: true,
            learnKanaIdentity: true  // かな候補チップの明示タップ=かなが正書という意思表示
        )
        refreshKeyboardStateForUserInitiatedAction(.commit)
    }

    func handleCommitComposingTextAsKatakana() {
        clearRecentKanaPlainCommitUpgradeContext()

        guard currentInputMode == .kana else {
            return
        }

        if let activeConversion {
            let committedText = katakanaCommittedText(from: activeConversion.sourceText)

            commitActiveConversion(
                activeConversion,
                committedText: committedText,
                learn: true
            )
            clearComposingState()
            refreshKeyboardStateForUserInitiatedAction(.commit)
            return
        }

        guard !composingRawText.isEmpty else {
            return
        }

        let committedText = katakanaCommittedText(from: composingRawText)

        commitComposingText(
            sourceText: composingRawText,
            sourceReading: composingReading,
            committedText: committedText,
            learn: true
        )
        refreshKeyboardStateForUserInitiatedAction(.commit)
    }

    func katakanaCommittedText(from text: String) -> String {
        guard !text.isEmpty else {
            return text
        }

        return text.applyingTransform(.hiraganaToKatakana, reverse: false) ?? text
    }

    func clearRecentKanaPlainCommitUpgradeContext() {
        recentKanaPlainCommit = nil
    }

    func rememberRecentKanaPlainCommit(
        sourceText: String,
        sourceReading: String,
        committedText: String,
        fromIdleCommit: Bool = false
    ) {
        guard !sourceText.isEmpty,
                !committedText.isEmpty else {
            recentKanaPlainCommit = nil
            return
        }

        recentKanaPlainCommit = RecentKanaPlainCommit(
            sourceText: sourceText,
            sourceReading: sourceReading,
            committedText: committedText,
            committedAt: Date(),
            fromIdleCommit: fromIdleCommit
        )
    }

    func upgradeRecentKanaCommitToKatakana() -> Bool {
        guard let recentKanaPlainCommit else {
            return false
        }

        if Date().timeIntervalSince(recentKanaPlainCommit.committedAt) > recentKanaPlainCommitUpgradeWindow {
            self.recentKanaPlainCommit = nil
            return false
        }

        let katakanaText = katakanaCommittedText(from: recentKanaPlainCommit.committedText)
        guard katakanaText != recentKanaPlainCommit.committedText else {
            self.recentKanaPlainCommit = nil
            return false
        }

        let contextBeforeInput = currentTextContextBeforeInput()
        guard contextBeforeInput.hasSuffix(recentKanaPlainCommit.committedText) else {
            self.recentKanaPlainCommit = nil
            return false
        }

        deleteBackwardCharacterCount(recentKanaPlainCommit.committedText.count)
        markTextProxyEdit()
        textDocumentProxy.insertText(katakanaText)
        markTextProxyEdit()
        textDocumentProxy.unmarkText()

        if !recentKanaPlainCommit.sourceReading.isEmpty {
            kanaKanjiConverter.learn(
                reading: recentKanaPlainCommit.sourceReading,
                candidate: katakanaText
            )
        }

        self.recentKanaPlainCommit = nil
        clearComposingState()
        return true
    }

    func commitPendingComposingTextBeforeInputModeSwitch() {
        clearRecentKanaPlainCommitUpgradeContext()

        guard currentInputMode == .kana else {
            return
        }

        if activeConversion != nil {
            commitActiveConversion(learn: true)
            return
        }

        guard !composingRawText.isEmpty else {
            return
        }

        commitComposingText(
            sourceText: composingRawText,
            sourceReading: composingReading,
            committedText: composingRawText,
            learn: true
        )
    }

    func cycleActiveConversionCandidate() {
        guard var conversion = activeConversion,
                !conversion.candidates.isEmpty else {
            return
        }

        let nextIndex = (conversion.selectedIndex + 1) % conversion.candidates.count
        replaceActiveConversionText(with: conversion.candidates[nextIndex], conversion: &conversion)
        activeConversion = conversion
    }

    func beginConversionFromComposingText() -> Bool {
        guard !composingRawText.isEmpty,
                !composingReading.isEmpty else {
            return false
        }

        let candidates = kanaKanjiCandidates(
            for: composingReading,
            limit: effectiveKanaConversionCandidateLimit(),
            systemCandidateMode: currentKanaKanjiCandidateSourceModeFromSharedDefaults()
        )

        guard let firstCandidate = candidates.first else {
            return false
        }

        let sourceText = composingRawText
        let reading = composingReading
        replaceComposingText(with: firstCandidate)

        activeConversion = ActiveConversion(
            reading: reading,
            sourceText: sourceText,
            candidates: candidates,
            selectedIndex: 0,
            committedText: firstCandidate
        )

        clearComposingState()
        return true
    }

    func replaceComposingText(with replacement: String) {
        setMarkedComposingText(replacement)
    }

    func replaceActiveConversionText(
        with replacement: String,
        conversion: inout ActiveConversion
    ) {
        setMarkedComposingText(replacement)

        if let replacementIndex = conversion.candidates.firstIndex(of: replacement) {
            conversion.selectedIndex = replacementIndex
        }

        conversion.committedText = replacement
    }

    // 入力が一定時間止まったら未確定(marked)を実テキストに確定する。
    // ホストは送信時に拡張のmarkedを破棄するため、送信前に確定しておくことで送信に乗せる。
    func scheduleIdleCommitIfNeeded() {
        cancelIdleCommit()

        guard currentInputMode == .kana,
            activeConversion == nil,
            !composingRawText.isEmpty,
            currentIdleCommitEnabled(from: sharedDefaults) else {
            return
        }

        let interval = currentIdleCommitInterval(from: sharedDefaults)
        let work = DispatchWorkItem { [weak self] in
            self?.performIdleCommit()
        }
        idleCommitWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: work)
    }

    func cancelIdleCommit() {
        idleCommitWorkItem?.cancel()
        idleCommitWorkItem = nil
    }

    func performIdleCommit() {
        idleCommitWorkItem = nil

        guard currentInputMode == .kana,
            activeConversion == nil,
            !composingRawText.isEmpty,
            currentIdleCommitEnabled(from: sharedDefaults) else {
            return
        }

        // 行頭・確定文字なし(context空)では未確定のまま送信に乗る(host が marked を送る)。
        // この場合はアイドル確定する必要がなく、確定すると再変換できなくなるので避ける。
        guard !currentTextContextBeforeInput().isEmpty else {
            appendKeyboardDiagnosticsLogFromInputHandling(
                "アイドル確定スキップ 行頭(確定文字なし) composingLen=\(composingRawText.count)"
            )
            return
        }

        let committedRawText = composingRawText
        let committedReading = composingReading

        appendKeyboardDiagnosticsLogFromInputHandling(
            "アイドル確定 composingLen=\(committedRawText.count)"
        )

        commitComposingText(
            sourceText: committedRawText,
            sourceReading: committedReading,
            committedText: committedRawText,
            learn: false
        )
        refreshKeyboardStateForUserInitiatedAction(.commit)

        // 直後の削除キーで未確定へ戻せるよう記録する(fromIdleCommit)。
        rememberRecentKanaPlainCommit(
            sourceText: committedRawText,
            sourceReading: committedReading,
            committedText: committedRawText,
            fromIdleCommit: true
        )
    }

    // アイドル確定の直後に削除キーが押されたら、1文字削除ではなく
    // 確定した文字列を未確定(marked)状態に戻す。
    func revertIdleCommitToComposingIfNeeded() -> Bool {
        guard let recent = recentKanaPlainCommit,
            recent.fromIdleCommit,
            currentInputMode == .kana,
            activeConversion == nil,
            composingRawText.isEmpty else {
            return false
        }

        if Date().timeIntervalSince(recent.committedAt) > idleCommitUndoWindow {
            recentKanaPlainCommit = nil
            return false
        }

        let contextBeforeInput = currentTextContextBeforeInput()
        guard contextBeforeInput.hasSuffix(recent.committedText) else {
            recentKanaPlainCommit = nil
            return false
        }

        recentKanaPlainCommit = nil

        deleteBackwardCharacterCount(recent.committedText.count)
        composingRawText = recent.sourceText
        composingReading = recent.sourceReading
        rememberComposingContextPrefixTail()
        setMarkedComposingText(recent.sourceText)

        appendKeyboardDiagnosticsLogFromInputHandling(
            "アイドル確定を削除キーで未確定へ復帰 len=\(recent.sourceText.count)"
        )
        refreshKeyboardStateAsync()
        return true
    }

    func deleteBackwardCharacterCount(_ count: Int) {
        guard count > 0 else {
            return
        }

        markTextProxyEdit()
        for _ in 0..<count {
            textDocumentProxy.deleteBackward()
        }
    }

    func clearComposingState() {
        composingRawText = ""
        composingReading = ""
        hasParenthesesWrapper = false
        composingContextPrefixTail = ""
        invalidateSettledCandidatePresentation()
        cancelIdleCommit()

        if activeConversion == nil {
            stopMarkedTextWatchdog()
        }
    }

    func toggleParenthesesWrapper() {
        guard currentInputMode == .kana else {
            return
        }

        hasParenthesesWrapper.toggle()
        refreshKeyboardStateForUserInitiatedAction(.postModifier)
    }

    func wrappedCommittedTextIfNeeded(_ text: String) -> String {
        guard hasParenthesesWrapper else {
            return text
        }

        if text.hasPrefix("(") && text.hasSuffix(")") {
            return text
        }

        return "(\(text))"
    }

    func commitComposingText(
        sourceText: String,
        sourceReading: String,
        committedText: String,
        learn: Bool,
        learnKanaIdentity: Bool = false,
        trailingText: String = ""
    ) {
        let committedTextForInsertion = wrappedCommittedTextIfNeeded(committedText) + trailingText
        commitMarkedTextByReplacingCurrentMarkedText(
            currentMarkedText: sourceText,
            committedText: committedTextForInsertion,
            sourceTextForFallbackReplacement: sourceText
        )

        if learn {
            kanaKanjiConverter.learn(
                reading: sourceReading,
                candidate: committedText,
                allowKanaIdentity: learnKanaIdentity
            )
        }

        clearComposingState()
    }

    func commitActiveConversion(learn: Bool) {
        guard let activeConversion else {
            return
        }

        commitActiveConversion(
            activeConversion,
            committedText: activeConversion.committedText,
            learn: learn
        )
    }

    func commitActiveConversion(
        _ conversion: ActiveConversion,
        committedText: String,
        learn: Bool,
        trailingText: String = ""
    ) {
        let committedTextForInsertion = wrappedCommittedTextIfNeeded(committedText) + trailingText

        commitMarkedTextByReplacingCurrentMarkedText(
            currentMarkedText: conversion.committedText,
            committedText: committedTextForInsertion,
            sourceTextForFallbackReplacement: conversion.sourceText
        )

        if learn {
            kanaKanjiConverter.learn(
                reading: conversion.reading,
                candidate: committedText
            )
        }

        self.activeConversion = nil
        clearComposingState()
    }

    func applyKanaPostModifier(
        _ buttonState: KanaPostModifierButtonState,
        preferLatestContext: Bool = false
    ) -> KanaPostModifierApplyOutcome {
        let hadPendingComposingText = !composingRawText.isEmpty
            || !composingReading.isEmpty
            || activeConversion != nil

        commitActiveConversion(learn: true)

        let resolvedButtonState: KanaPostModifierButtonState = {
            guard preferLatestContext else {
                return buttonState
            }

            let contextForResolution: String?

            if !composingRawText.isEmpty {
                contextForResolution = composingRawText
            } else {
                contextForResolution = currentTextContextBeforeInputTail(
                    maxLength: TextContextLimits.synchronizedContextTailLength
                )
            }

            let latestState = FlickKanaLayout.postModifierButtonState(
                contextBeforeInput: contextForResolution
            )

            return latestState == .kaomoji ? buttonState : latestState
        }()

        func normalizedHiraganaKanaForPostModifier(_ character: Character) -> Character? {
            let source = String(character)
            let transformed = source.applyingTransform(.hiraganaToKatakana, reverse: true) ?? source

            guard transformed.count == 1,
                let normalized = transformed.first else {
                return nil
            }

            return normalized
        }

        func shouldSuppressRapidDakutenSecondTap(for character: Character) -> Bool {
            guard resolvedButtonState == .dakuten,
                let normalized = normalizedHiraganaKanaForPostModifier(character),
                Self.rapidDakutenSecondTapTargets.contains(normalized) else {
                return false
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - lastKanaPostModifierAppliedAt

            guard elapsed >= 0,
                elapsed < KanaPostModifierSafetyLimits.rapidDakutenSecondTapSuppressionSec,
                let previousCharacter = lastKanaPostModifierResultCharacter,
                let normalizedPrevious = normalizedHiraganaKanaForPostModifier(previousCharacter),
                normalizedPrevious == normalized else {
                return false
            }

            appendKeyboardDiagnosticsLogFromInputHandling(
                "後置修飾2段階抑止 normalized=\(normalized) elapsedMs=\(Int((elapsed * 1000).rounded()))"
            )
            return true
        }

        func resolvedPostModifierCharacter(from character: Character) -> Character? {
            guard !shouldSuppressRapidDakutenSecondTap(for: character) else {
                return nil
            }

            return FlickKanaLayout.postfixModifiedCharacter(
                from: character,
                for: resolvedButtonState
            )
        }

        if currentInputMode == .kana,
            !composingRawText.isEmpty,
            let lastCharacter = composingRawText.last,
            let replacedCharacter = resolvedPostModifierCharacter(from: lastCharacter) {
            composingRawText.removeLast()
            composingRawText.append(String(replacedCharacter))

            if !composingReading.isEmpty {
                composingReading.removeLast()
            }

            if let normalizedKana = KanaTextNormalizer.normalizedKanaCharacter(from: String(replacedCharacter)) {
                composingReading.append(normalizedKana)
            }

            setMarkedComposingText(composingRawText)
            lastKanaPostModifierAppliedAt = CFAbsoluteTimeGetCurrent()
            lastKanaPostModifierResultCharacter = replacedCharacter
            refreshKeyboardStateForUserInitiatedAction(.postModifier)
            return .applied
        }

        // 確定済み文字列の末尾には濁点/半濁点/小書きを適用しない。
        // 直前に commitActiveConversion が走っていた場合(hadPendingComposingText=true)は
        // ユーザの直近操作が「変換確定」だったので mode 切替は不適切→.ignored、
        // 完全に編集状態が無い(idle)場合は .idleEmptyContext を返して後置修飾空タップ
        // アクション(顔文字/絵文字/記号モードへの一時切替)を発火させる。
        return hadPendingComposingText ? .ignored : .idleEmptyContext
    }
}
