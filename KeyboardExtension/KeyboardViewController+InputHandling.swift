import Foundation
import UIKit

extension KeyboardViewController {
    private enum CandidateLimits {
        static let presentationDefault = 24
        static let conversionDefault = 24
        static let latinSuggestionDefault = 40
    }

    private enum CommitSafetyLimits {
        static let composingContextPrefixTailLength = 16
        static let delayedUnderlineClearMs: Int = 30
        static let delayedUnderlineClearLongMs: Int = 480
        static let delayedUnderlineClearLongerMs: Int = 900
        static let verifiedEphemeralClearDelayMs: Int = 120
        static let verifiedEphemeralMarker = "\u{2060}"
        static let hostCallbackUnderlineClearWindow: CFTimeInterval = 2.4
        static let minimumNoReplaceClearNudgeWidth = 8
    }

    private enum DiagnosticsThresholds {
        static let latinSuggestionSlowMs = 18
        static let candidatePresentationSlowMs = 18
    }

    private enum KanaPostModifierSafetyLimits {
        static let rapidDakutenSecondTapSuppressionSec: CFTimeInterval = 0.14
    }

    private static let rapidDakutenSecondTapTargets: Set<Character> = ["っ", "ぅ"]

    private func inputHandlingTextLengthSummary(_ text: String) -> String {
        "len=\(text.count)"
    }

    func appendCommitUnderlineDiagnostics(
        _ stage: String,
        committedTextLength: Int? = nil,
        markedTextLength: Int? = nil,
        note: String = ""
    ) {
        let contextBeforeInput = currentTextContextBeforeInput()
        let contextAfterInput = currentTextContextAfterInput()

        var components: [String] = [
            "下線診断",
            "stage=\(stage)",
            "before=\(inputHandlingTextLengthSummary(contextBeforeInput))",
            "after=\(inputHandlingTextLengthSummary(contextAfterInput))",
            "composingLen=\(composingRawText.count)",
            "readingLen=\(composingReading.count)",
            "active=\(activeConversion == nil ? 0 : 1)"
        ]

        if let committedTextLength {
            components.append("committedLen=\(committedTextLength)")
        }

        if let markedTextLength {
            components.append("markedLen=\(markedTextLength)")
        }

        if !note.isEmpty {
            components.append("note=\(note)")
        }

        appendKeyboardDiagnosticsLogFromInputHandling(components.joined(separator: " "))
    }

    func currentLatinSuggestionQueryFromTextContext() -> String {
        guard currentInputMode == .latin else {
            return ""
        }

        let contextBeforeInput = currentTextContextBeforeInputTail(
            maxLength: TextContextLimits.latinSuggestionScanTailLength
        )

        guard !contextBeforeInput.isEmpty else {
            return ""
        }

        return trailingLatinSuggestionToken(from: contextBeforeInput)
    }

    func currentLatinSuggestions(limit: Int = CandidateLimits.latinSuggestionDefault) -> [String] {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let query = currentLatinSuggestionQueryFromTextContext()
        let effectiveLimit = effectiveLatinSuggestionLimit(defaultLimit: limit)

        guard !query.isEmpty,
            effectiveLimit > 0 else {
            return []
        }

        let lookupLimit = max(effectiveLimit + 12, effectiveLimit * 2)
        let suggestions = latinSuggestions(prefix: query, limit: lookupLimit)
        let filteredSuggestions = suggestions.filter { suggestion in
            !isCurrentLatinSuggestionQuery(suggestion, query: query)
        }
        let results = Array(filteredSuggestions.prefix(effectiveLimit))

        let elapsedMs = performanceElapsedMilliseconds(since: startedAt)
        if elapsedMs >= DiagnosticsThresholds.latinSuggestionSlowMs {
            appendKeyboardDiagnosticsLogFromInputHandling(
                "latin候補取得遅延 elapsedMs=\(elapsedMs) queryLen=\(query.count) lookupLimit=\(lookupLimit) result=\(results.count)"
            )
        }

        return results
    }

    func currentCandidatePresentationForRender(
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> CandidatePresentation {
        guard currentInputMode == .kana else {
            invalidateSettledCandidatePresentation()
            return CandidatePresentation(composingText: "", candidates: [], selectedIndex: nil)
        }

        if let activeConversion {
            invalidateSettledCandidatePresentation()
            return CandidatePresentation(
                composingText: activeConversion.sourceText,
                candidates: activeConversion.candidates,
                selectedIndex: activeConversion.selectedIndex
            )
        }

        guard !composingReading.isEmpty else {
            invalidateSettledCandidatePresentation()
            return CandidatePresentation(composingText: "", candidates: [], selectedIndex: nil)
        }

        let cacheKey = CandidatePresentationCacheKey(
            reading: composingReading,
            composingRawText: composingRawText,
            modeRawValue: systemCandidateMode.rawValue
        )

        if let cached = settledCandidatePresentation,
            settledCandidatePresentationKey == cacheKey {
            return cached
        }

        kickOffAsyncCandidateGeneration(
            reading: composingReading,
            composingRawText: composingRawText,
            systemCandidateMode: systemCandidateMode
        )

        return CandidatePresentation(
            composingText: composingRawText,
            candidates: [],
            selectedIndex: nil
        )
    }

    func invalidateSettledCandidatePresentation() {
        settledCandidatePresentation = nil
        settledCandidatePresentationKey = nil
    }

    private func kickOffAsyncCandidateGeneration(
        reading: String,
        composingRawText: String,
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) {
        candidateGenerationCounter &+= 1
        let generation = candidateGenerationCounter
        let presentationLimit = effectiveKanaPresentationCandidateLimit()

        guard presentationLimit > 0 else {
            return
        }

        let converter = kanaKanjiConverter
        let pendingKey = CandidatePresentationCacheKey(
            reading: reading,
            composingRawText: composingRawText,
            modeRawValue: systemCandidateMode.rawValue
        )

        candidateGenerationQueue.async { [weak self] in
            let converterLimit = max(
                presentationLimit * ExternalCandidateLimits.lookupMultiplier,
                presentationLimit + 12
            )
            let converterCandidates = converter.candidates(
                for: reading,
                limit: converterLimit,
                systemCandidateMode: systemCandidateMode
            )

            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                self.applyAsyncCandidateGenerationResult(
                    generation: generation,
                    cacheKey: pendingKey,
                    converterCandidates: converterCandidates,
                    presentationLimit: presentationLimit,
                    systemCandidateMode: systemCandidateMode
                )
            }
        }
    }

    private func applyAsyncCandidateGenerationResult(
        generation: UInt64,
        cacheKey: CandidatePresentationCacheKey,
        converterCandidates: [String],
        presentationLimit: Int,
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) {
        guard generation == candidateGenerationCounter else {
            return
        }

        guard cacheKey.reading == composingReading,
            cacheKey.composingRawText == composingRawText,
            currentInputMode == .kana,
            activeConversion == nil else {
            return
        }

        let supplementaryCandidates = supplementaryLexiconCandidates(for: cacheKey.reading)

        let merged: [String]
        if supplementaryCandidates.isEmpty {
            merged = Array(converterCandidates.prefix(presentationLimit))
        } else {
            merged = SupplementaryCandidateMerger.mergeSupplementaryAndConverterCandidates(
                reading: cacheKey.reading,
                supplementaryCandidates: supplementaryCandidates,
                converterCandidates: converterCandidates,
                limit: presentationLimit
            )
        }

        let filtered = candidatesForPresentation(
            from: merged,
            composingText: cacheKey.composingRawText
        )

        let presentation = CandidatePresentation(
            composingText: cacheKey.composingRawText,
            candidates: filtered,
            selectedIndex: nil
        )

        settledCandidatePresentation = presentation
        settledCandidatePresentationKey = cacheKey

        refreshKeyboardStateAsync()
    }

    func makeCandidatePresentation(
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> CandidatePresentation {
        let startedAt = CFAbsoluteTimeGetCurrent()

        guard currentInputMode == .kana else {
            return CandidatePresentation(composingText: "", candidates: [], selectedIndex: nil)
        }

        if let activeConversion {
            return CandidatePresentation(
                composingText: activeConversion.sourceText,
                candidates: activeConversion.candidates,
                selectedIndex: activeConversion.selectedIndex
            )
        }

        guard !composingReading.isEmpty else {
            return CandidatePresentation(composingText: "", candidates: [], selectedIndex: nil)
        }

        let presentationLimit = effectiveKanaPresentationCandidateLimit()

        guard presentationLimit > 0 else {
            return CandidatePresentation(
                composingText: composingRawText,
                candidates: [],
                selectedIndex: nil
            )
        }

        let rawCandidates = kanaKanjiCandidates(
            for: composingReading,
            limit: presentationLimit,
            systemCandidateMode: systemCandidateMode
        )
        let presentationCandidates = candidatesForPresentation(
            from: rawCandidates,
            composingText: composingRawText
        )

        let elapsedMs = performanceElapsedMilliseconds(since: startedAt)
        if elapsedMs >= DiagnosticsThresholds.candidatePresentationSlowMs {
            appendKeyboardDiagnosticsLogFromInputHandling(
                "候補提示生成遅延 elapsedMs=\(elapsedMs) readingLen=\(composingReading.count) raw=\(rawCandidates.count) presented=\(presentationCandidates.count)"
            )
        }

        return CandidatePresentation(
            composingText: composingRawText,
            candidates: presentationCandidates,
            selectedIndex: nil
        )
    }

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

        let systemCandidates = kanaKanjiCandidates(
            for: sourceReading,
            limit: effectiveKanaConversionCandidateLimit(),
            systemCandidateMode: currentKanaKanjiCandidateSourceModeFromSharedDefaults()
        )
        let presentationCandidates = candidatesForPresentation(
            from: systemCandidates,
            composingText: sourceText
        )

        // 自動確定では「未変換かな」を第0候補として扱い、設定で第0/第1候補を選べるようにする。
        var autoCommitCandidates: [String] = [sourceText]
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

        let candidates = kanaKanjiCandidates(
            for: composingReading,
            limit: effectiveKanaPresentationCandidateLimit(),
            systemCandidateMode: currentKanaKanjiCandidateSourceModeFromSharedDefaults()
        )
        let presentationCandidates = candidatesForPresentation(
            from: candidates,
            composingText: composingRawText
        )

        guard presentationCandidates.indices.contains(index) else {
            return
        }

        commitComposingText(
            sourceText: composingRawText,
            sourceReading: composingReading,
            committedText: presentationCandidates[index],
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
            learn: true
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
        committedText: String
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
            committedAt: Date()
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

    func setMarkedComposingText(_ text: String) {
        // setMarkedText は documentContextBeforeInput/AfterInput を変えないため
        // キャッシュ無効化は不要(タイムスタンプのみ更新)。
        noteOwnTextProxyEditTimestamp()
        textDocumentProxy.setMarkedText(
            text,
            selectedRange: NSRange(location: text.utf16.count, length: 0)
        )

        lastMarkedTextUpdateAt = CFAbsoluteTimeGetCurrent()

        if text.isEmpty {
            stopMarkedTextWatchdog()
            cancelIdleCommit()
        } else {
            startMarkedTextWatchdogIfNeeded()
            scheduleIdleCommitIfNeeded()
        }
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

    private func performIdleCommit() {
        idleCommitWorkItem = nil

        guard currentInputMode == .kana,
            activeConversion == nil,
            !composingRawText.isEmpty,
            currentIdleCommitEnabled(from: sharedDefaults) else {
            return
        }

        appendKeyboardDiagnosticsLogFromInputHandling(
            "アイドル確定 composingLen=\(composingRawText.count)"
        )

        commitComposingText(
            sourceText: composingRawText,
            sourceReading: composingReading,
            committedText: composingRawText,
            learn: false
        )
        refreshKeyboardStateForUserInitiatedAction(.commit)
    }

    func startMarkedTextWatchdogIfNeeded() {
        guard markedTextWatchdogTimer == nil else {
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: Self.markedTextWatchdogQueue)
        timer.schedule(
            deadline: .now() + Self.markedTextWatchdogInterval,
            repeating: Self.markedTextWatchdogInterval,
            leeway: .milliseconds(200)
        )
        timer.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                self?.checkMarkedTextHealth()
            }
        }
        timer.resume()
        markedTextWatchdogTimer = timer
    }

    func stopMarkedTextWatchdog() {
        markedTextWatchdogTimer?.cancel()
        markedTextWatchdogTimer = nil
    }

    private func checkMarkedTextHealth() {
        guard currentInputMode == .kana else {
            stopMarkedTextWatchdog()
            return
        }

        guard !composingRawText.isEmpty || activeConversion != nil else {
            stopMarkedTextWatchdog()
            return
        }

        // 直近の marked text 更新から間もないときはスキップ
        // (キーを連打している間は無駄な hasText IPC を発生させない)
        let elapsedSinceUpdate = CFAbsoluteTimeGetCurrent() - lastMarkedTextUpdateAt
        if elapsedSinceUpdate < Self.markedTextWatchdogQuietPeriod {
            return
        }

        // documentContextBeforeInput / After は marked text を含まない仕様のため、
        // 「ホスト側で marked が失われたか」の信頼できる proxy 信号は hasText のみ。
        // 入力欄全体が空になっていれば marked text も確実に失われている。
        guard !textDocumentProxy.hasText else {
            return
        }

        appendKeyboardDiagnosticsLogFromInputHandling(
            "watchdog: 入力欄が空のため編集中状態を破棄 composingLen=\(composingRawText.count) hasActiveConversion=\(activeConversion != nil)"
        )
        self.activeConversion = nil
        clearComposingState()
        stopMarkedTextWatchdog()
        refreshKeyboardStateAsync()
    }

    func kanaKanjiCandidates(
        for reading: String,
        limit: Int,
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        guard limit > 0 else {
            return []
        }

        let converterLimit = max(limit * ExternalCandidateLimits.lookupMultiplier, limit + 12)
        let converterCandidates = kanaKanjiConverter.candidates(
            for: reading,
            limit: converterLimit,
            systemCandidateMode: systemCandidateMode
        )
        let supplementaryCandidates = supplementaryLexiconCandidates(for: reading)

        if supplementaryCandidates.isEmpty {
            return Array(converterCandidates.prefix(limit))
        }

        return SupplementaryCandidateMerger.mergeSupplementaryAndConverterCandidates(
            reading: reading,
            supplementaryCandidates: supplementaryCandidates,
            converterCandidates: converterCandidates,
            limit: limit
        )
    }

    func clearMarkedComposingText() {
        // setMarkedText("", ...) と unmarkText は marked text が空の状態では
        // documentContextBeforeInput/AfterInput を変えないため、キャッシュ無効化は不要。
        noteOwnTextProxyEditTimestamp()
        textDocumentProxy.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
        noteOwnTextProxyEditTimestamp()
        textDocumentProxy.unmarkText()
    }

    func rememberComposingContextPrefixTail() {
        let contextBeforeInput = currentTextContextBeforeInput()
        composingContextPrefixTail = String(
            contextBeforeInput.suffix(CommitSafetyLimits.composingContextPrefixTailLength)
        )
    }

    func performNonDestructiveUnderlineClearPass(
        stage: String,
        nudgeWidth: Int
    ) {
        let resolvedNudgeWidth = max(0, nudgeWidth)

        appendCommitUnderlineDiagnostics(
            "clearPass:start:\(stage)",
            note: "nudge=\(resolvedNudgeWidth)"
        )

        // 直前のコミット/送信で host 側テキストが変化している可能性が高いため、
        // pass の入口で1回キャッシュを破棄して fresh な context で nudge 幅を算出する。
        // (cc7bad3 で全部 noteOwn... 化したら iMessage 送信時に stale context で
        // adjustTextPosition が実コンテンツより長く動こうとして下線残留する不具合あり)。
        invalidateTextContextCache()

        markTextProxyEdit()
        textDocumentProxy.unmarkText()

        let contextBeforeInput = currentTextContextBeforeInput()
        let contextAfterInput = currentTextContextAfterInput()

        if resolvedNudgeWidth > 0,
            !contextBeforeInput.isEmpty {
            let backwardOffset = min(resolvedNudgeWidth, contextBeforeInput.count)
            noteOwnTextProxyEditTimestamp()
            textDocumentProxy.adjustTextPosition(byCharacterOffset: -backwardOffset)
            noteOwnTextProxyEditTimestamp()
            textDocumentProxy.adjustTextPosition(byCharacterOffset: backwardOffset)
        } else if resolvedNudgeWidth > 0,
            !contextAfterInput.isEmpty {
            let forwardOffset = min(resolvedNudgeWidth, contextAfterInput.count)
            noteOwnTextProxyEditTimestamp()
            textDocumentProxy.adjustTextPosition(byCharacterOffset: forwardOffset)
            noteOwnTextProxyEditTimestamp()
            textDocumentProxy.adjustTextPosition(byCharacterOffset: -forwardOffset)
        }

        noteOwnTextProxyEditTimestamp()
        textDocumentProxy.unmarkText()

        appendCommitUnderlineDiagnostics(
            "clearPass:end:\(stage)",
            note: "nudge=\(resolvedNudgeWidth)"
        )
    }

    func clearMarkedTextArtifactsAfterCommit(
        committedTextLength: Int,
        nudgeWidth: Int = 1,
        allowVerifiedEphemeralFallback: Bool = false
    ) {
        let resolvedNudgeWidth = max(0, nudgeWidth)

        appendCommitUnderlineDiagnostics(
            "clearArtifacts:start",
            committedTextLength: committedTextLength,
            note: "nudge=\(resolvedNudgeWidth)"
        )

        // Apply repeated non-destructive unmarking so hosts such as Notes/Safari
        // can clear visual underline artifacts without mutating committed text.
        performNonDestructiveUnderlineClearPass(
            stage: "immediate-1",
            nudgeWidth: resolvedNudgeWidth
        )
        performNonDestructiveUnderlineClearPass(
            stage: "immediate-2",
            nudgeWidth: resolvedNudgeWidth
        )

        schedulePendingHostCallbackUnderlineClearPass(nudgeWidth: resolvedNudgeWidth)

        DispatchQueue.main.async { [weak self] in
            self?.performNonDestructiveUnderlineClearPass(
                stage: "async",
                nudgeWidth: resolvedNudgeWidth
            )
        }

        let delayedPasses: [(interval: DispatchTimeInterval, stage: String)] = [
            (.milliseconds(CommitSafetyLimits.delayedUnderlineClearMs), "delayed-30ms"),
            (.milliseconds(120), "delayed-120ms"),
            (.milliseconds(CommitSafetyLimits.delayedUnderlineClearLongMs), "delayed-480ms"),
            (.milliseconds(CommitSafetyLimits.delayedUnderlineClearLongerMs), "delayed-900ms")
        ]

        for delayedPass in delayedPasses {
            DispatchQueue.main.asyncAfter(deadline: .now() + delayedPass.interval) { [weak self] in
                guard let self else {
                    return
                }

                // Skip delayed clear once user starts a new composition.
                guard self.activeConversion == nil,
                    self.composingRawText.isEmpty,
                    self.composingReading.isEmpty else {
                    self.appendCommitUnderlineDiagnostics(
                        "clearArtifacts:skip:\(delayedPass.stage)"
                    )
                    return
                }

                self.performNonDestructiveUnderlineClearPass(
                    stage: delayedPass.stage,
                    nudgeWidth: resolvedNudgeWidth
                )
            }
        }

        if allowVerifiedEphemeralFallback {
            appendCommitUnderlineDiagnostics(
                "clearArtifacts:verifiedEphemeralScheduled",
                committedTextLength: committedTextLength,
                note: "delayMs=\(CommitSafetyLimits.verifiedEphemeralClearDelayMs)"
            )

            DispatchQueue.main.asyncAfter(
                deadline: .now() + .milliseconds(CommitSafetyLimits.verifiedEphemeralClearDelayMs)
            ) { [weak self] in
                guard let self else {
                    return
                }

                guard self.activeConversion == nil,
                    self.composingRawText.isEmpty,
                    self.composingReading.isEmpty else {
                    self.appendCommitUnderlineDiagnostics("clearArtifacts:skip:verifiedEphemeral")
                    return
                }

                self.performVerifiedEphemeralUnderlineClearPass(stage: "verifiedEphemeral")
            }
        }

        appendCommitUnderlineDiagnostics(
            "clearArtifacts:scheduled",
            committedTextLength: committedTextLength,
            note: "nudge=\(resolvedNudgeWidth)"
        )
    }

    func performVerifiedEphemeralUnderlineClearPass(stage: String) {
        let marker = CommitSafetyLimits.verifiedEphemeralMarker
        let contextBeforeInsert = currentTextContextBeforeInput()
        let contextAfterInput = currentTextContextAfterInput()

        guard !contextBeforeInsert.isEmpty || !contextAfterInput.isEmpty else {
            appendCommitUnderlineDiagnostics("clearPass:skip:\(stage)", note: "reason=noContext")
            return
        }

        appendCommitUnderlineDiagnostics(
            "clearPass:start:\(stage)",
            note: "before=\(inputHandlingTextLengthSummary(contextBeforeInsert))"
        )

        markTextProxyEdit()
        textDocumentProxy.insertText(marker)

        let contextAfterInsert = currentTextContextBeforeInput()
        let insertAppearsAtSuffix = contextAfterInsert.hasSuffix(marker)
        let insertLikelyApplied = insertAppearsAtSuffix
            && (contextAfterInsert.count > contextBeforeInsert.count
                || !contextBeforeInsert.hasSuffix(marker))

        if insertLikelyApplied {
            appendCommitUnderlineDiagnostics("clearPass:verifiedEphemeralDelete:\(stage)")
            markTextProxyEdit()
            textDocumentProxy.deleteBackward()
        } else {
            appendCommitUnderlineDiagnostics(
                "clearPass:verifiedEphemeralSkipDelete:\(stage)",
                note: "before=\(inputHandlingTextLengthSummary(contextBeforeInsert)) afterInsert=\(inputHandlingTextLengthSummary(contextAfterInsert))"
            )
        }

        markTextProxyEdit()
        textDocumentProxy.unmarkText()

        let contextAfterPass = currentTextContextBeforeInput()
        appendCommitUnderlineDiagnostics(
            "clearPass:end:\(stage)",
            note: "before=\(inputHandlingTextLengthSummary(contextBeforeInsert)) afterInsert=\(inputHandlingTextLengthSummary(contextAfterInsert)) afterPass=\(inputHandlingTextLengthSummary(contextAfterPass))"
        )
    }

    func schedulePendingHostCallbackUnderlineClearPass(nudgeWidth: Int) {
        let resolvedNudgeWidth = max(0, nudgeWidth)
        pendingHostCallbackUnderlineClearNudgeWidth = resolvedNudgeWidth
        pendingHostCallbackUnderlineClearDeadline =
            CFAbsoluteTimeGetCurrent() + CommitSafetyLimits.hostCallbackUnderlineClearWindow

        appendCommitUnderlineDiagnostics(
            "clearArtifacts:hostSyncScheduled",
            note: "nudge=\(resolvedNudgeWidth)"
        )
    }

    func consumePendingHostCallbackUnderlineClearPassIfNeeded(trigger: String) {
        guard let nudgeWidth = pendingHostCallbackUnderlineClearNudgeWidth else {
            return
        }

        let now = CFAbsoluteTimeGetCurrent()

        if now > pendingHostCallbackUnderlineClearDeadline {
            pendingHostCallbackUnderlineClearNudgeWidth = nil
            pendingHostCallbackUnderlineClearDeadline = 0
            appendCommitUnderlineDiagnostics("clearArtifacts:hostSyncExpired:\(trigger)")
            return
        }

        guard activeConversion == nil,
            composingRawText.isEmpty,
            composingReading.isEmpty else {
            pendingHostCallbackUnderlineClearNudgeWidth = nil
            pendingHostCallbackUnderlineClearDeadline = 0
            appendCommitUnderlineDiagnostics("clearArtifacts:hostSyncSkip:\(trigger)")
            return
        }

        pendingHostCallbackUnderlineClearNudgeWidth = nil
        pendingHostCallbackUnderlineClearDeadline = 0

        performNonDestructiveUnderlineClearPass(
            stage: "hostSync-\(trigger)",
            nudgeWidth: nudgeWidth
        )
    }

    func performNoReplaceCommitPreflightToggleIfNeeded(
        committedText: String,
        contextBeforeInput: String
    ) {
        guard !committedText.isEmpty else {
            return
        }

        guard !composingRawText.isEmpty || activeConversion != nil else {
            appendCommitUnderlineDiagnostics("finalize:noReplacePreflightSkip", note: "reason=noComposing")
            return
        }

        let hasContextAnchor = composingContextPrefixTail.isEmpty
            || contextBeforeInput.hasSuffix(composingContextPrefixTail)

        guard hasContextAnchor else {
            appendCommitUnderlineDiagnostics("finalize:noReplacePreflightSkip", note: "reason=anchorMismatch")
            return
        }

        appendCommitUnderlineDiagnostics(
            "finalize:noReplacePreflightToggle",
            committedTextLength: committedText.count
        )

        markTextProxyEdit()
        textDocumentProxy.setMarkedText(
            committedText,
            selectedRange: NSRange(location: 0, length: 0)
        )
        markTextProxyEdit()
        textDocumentProxy.setMarkedText(
            committedText,
            selectedRange: NSRange(location: committedText.utf16.count, length: 0)
        )
    }

    func finalizeCommitWithoutReplacingText(_ committedText: String) {
        appendCommitUnderlineDiagnostics(
            "finalize:start",
            committedTextLength: committedText.count
        )

        var shouldUseExtendedNudgeWidth = false

        if !committedText.isEmpty {
            let contextBeforeInput = currentTextContextBeforeInput()
            let expectedMarkedSuffix = composingContextPrefixTail + committedText
            let canReplaceByDeleteAndInsert = contextBeforeInput.hasSuffix(expectedMarkedSuffix)
                || contextBeforeInput.hasSuffix(committedText)

            appendCommitUnderlineDiagnostics(
                "finalize:decision",
                committedTextLength: committedText.count,
                note: "canReplace=\(canReplaceByDeleteAndInsert ? 1 : 0)"
            )

            if canReplaceByDeleteAndInsert {
                markTextProxyEdit()
                textDocumentProxy.unmarkText()

                let contextAfterUnmark = currentTextContextBeforeInput()
                if contextAfterUnmark.hasSuffix(committedText) {
                    appendCommitUnderlineDiagnostics(
                        "finalize:unmarkSucceededReplace",
                        committedTextLength: committedText.count
                    )
                } else {
                    appendCommitUnderlineDiagnostics(
                        "finalize:toggleMarkedAfterUnmark",
                        committedTextLength: committedText.count
                    )
                    markTextProxyEdit()
                    textDocumentProxy.setMarkedText(
                        committedText,
                        selectedRange: NSRange(location: 0, length: 0)
                    )
                    markTextProxyEdit()
                    textDocumentProxy.setMarkedText(
                        committedText,
                        selectedRange: NSRange(location: committedText.utf16.count, length: 0)
                    )
                }
            } else {
                shouldUseExtendedNudgeWidth = true

                // Hosts such as Notes/Safari may hide marked text from context.
                // Prime marked state first, then try unmark and fallback insert.
                performNoReplaceCommitPreflightToggleIfNeeded(
                    committedText: committedText,
                    contextBeforeInput: contextBeforeInput
                )

                // Try unmark first, then force commit with insert if needed.
                appendCommitUnderlineDiagnostics(
                    "finalize:noReplaceTryUnmark",
                    committedTextLength: committedText.count
                )
                markTextProxyEdit()
                textDocumentProxy.unmarkText()

                let contextAfterUnmark = currentTextContextBeforeInput()
                let likelyCommittedByUnmark = contextAfterUnmark.hasSuffix(committedText)
                    && contextAfterUnmark.count >= contextBeforeInput.count

                if !likelyCommittedByUnmark {
                    appendCommitUnderlineDiagnostics(
                        "finalize:insertFallbackNoReplace",
                        committedTextLength: committedText.count,
                        note: "afterUnmark=\(inputHandlingTextLengthSummary(contextAfterUnmark))"
                    )
                    markTextProxyEdit()
                    textDocumentProxy.insertText(committedText)
                } else {
                    appendCommitUnderlineDiagnostics(
                        "finalize:unmarkSucceededNoReplace",
                        committedTextLength: committedText.count,
                        note: "afterUnmark=\(inputHandlingTextLengthSummary(contextAfterUnmark))"
                    )
                }
            }
        }

        let clearNudgeWidth: Int

        if shouldAvoidCursorNudgeAfterCommit(committedText) {
            clearNudgeWidth = 0
        } else if shouldUseExtendedNudgeWidth {
            clearNudgeWidth = max(CommitSafetyLimits.minimumNoReplaceClearNudgeWidth, committedText.count)
        } else {
            clearNudgeWidth = 1
        }

        appendCommitUnderlineDiagnostics(
            "finalize:clearPlan",
            committedTextLength: committedText.count,
            note: "nudge=\(clearNudgeWidth)"
        )

        clearMarkedTextArtifactsAfterCommit(
            committedTextLength: committedText.count,
            nudgeWidth: clearNudgeWidth,
            allowVerifiedEphemeralFallback: shouldUseExtendedNudgeWidth
        )
    }

    func commitMarkedTextByReplacingCurrentMarkedText(
        currentMarkedText: String,
        committedText: String,
        sourceTextForFallbackReplacement: String? = nil
    ) {
        appendCommitUnderlineDiagnostics(
            "commitReplace:start",
            committedTextLength: committedText.count,
            markedTextLength: currentMarkedText.count
        )

        if let sourceTextForFallbackReplacement,
            !sourceTextForFallbackReplacement.isEmpty,
            sourceTextForFallbackReplacement != committedText,
            currentMarkedText == sourceTextForFallbackReplacement {
            let contextBeforeInput = currentTextContextBeforeInput()
            let expectedSourceSuffix = composingContextPrefixTail + sourceTextForFallbackReplacement
            let expectedCommittedSuffix = composingContextPrefixTail + committedText
            let hasSourceSuffix = contextBeforeInput.hasSuffix(expectedSourceSuffix)
            let alreadyCommittedAtSuffix = contextBeforeInput.hasSuffix(expectedCommittedSuffix)

            if hasSourceSuffix && !alreadyCommittedAtSuffix {
                appendKeyboardDiagnosticsLogFromInputHandling(
                    "確定置換をsource直接置換で実施 context=\(inputHandlingTextLengthSummary(contextBeforeInput)) sourceLen=\(sourceTextForFallbackReplacement.count) committedLen=\(committedText.count)"
                )

                markTextProxyEdit()
                textDocumentProxy.unmarkText()

                let contextAfterUnmark = currentTextContextBeforeInput()
                let stillHasSourceSuffix = contextAfterUnmark.hasSuffix(expectedSourceSuffix)

                if stillHasSourceSuffix {
                    deleteBackwardCharacterCount(sourceTextForFallbackReplacement.count)
                    markTextProxyEdit()
                    textDocumentProxy.insertText(committedText)

                    let clearNudgeWidth = shouldAvoidCursorNudgeAfterCommit(committedText) ? 0 : 1
                    clearMarkedTextArtifactsAfterCommit(
                        committedTextLength: committedText.count,
                        nudgeWidth: clearNudgeWidth
                    )
                    return
                }
            }
        }

        if currentMarkedText == committedText {
            appendCommitUnderlineDiagnostics(
                "commitReplace:sameText",
                committedTextLength: committedText.count,
                markedTextLength: currentMarkedText.count
            )
            finalizeCommitWithoutReplacingText(committedText)
            return
        }

        let contextBeforeInput = currentTextContextBeforeInput()
        let expectedMarkedSuffix = composingContextPrefixTail + currentMarkedText
        let canLikelyReplaceMarkedText = !currentMarkedText.isEmpty
            && contextBeforeInput.hasSuffix(expectedMarkedSuffix)

        if !canLikelyReplaceMarkedText {
            appendKeyboardDiagnosticsLogFromInputHandling(
                "確定置換をフォールバック context=\(inputHandlingTextLengthSummary(contextBeforeInput)) markedLen=\(currentMarkedText.count) committedLen=\(committedText.count)"
            )
        }

        // Prefer replacing the currently marked range directly and avoid
        // deleteBackward-based replacement that can remove surrounding text.
        appendCommitUnderlineDiagnostics(
            "commitReplace:setMarked",
            committedTextLength: committedText.count,
            markedTextLength: currentMarkedText.count
        )
        markTextProxyEdit()
        textDocumentProxy.setMarkedText(
            committedText,
            selectedRange: NSRange(location: committedText.utf16.count, length: 0)
        )

        let clearNudgeWidth = shouldAvoidCursorNudgeAfterCommit(committedText) ? 0 : 1
        clearMarkedTextArtifactsAfterCommit(
            committedTextLength: committedText.count,
            nudgeWidth: clearNudgeWidth
        )
    }

    func shouldAvoidCursorNudgeAfterCommit(_ committedText: String) -> Bool {
        guard !committedText.isEmpty else {
            return false
        }

        if committedText.unicodeScalars.contains(where: {
            $0.properties.isEmoji || $0.properties.isEmojiPresentation
        }) {
            return true
        }

        let hasLetterOrDigit = committedText.unicodeScalars.contains {
            CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
        }

        return !hasLetterOrDigit
    }

    func candidatesForPresentation(
        from candidates: [String],
        composingText: String
    ) -> [String] {
        guard !composingText.isEmpty else {
            return candidates
        }

        return candidates.filter { candidate in
            !(candidate == composingText && isKanaOnlyText(candidate))
        }
    }

    func isKanaOnlyText(_ text: String) -> Bool {
        guard !text.isEmpty else {
            return false
        }

        return text.allSatisfy { character in
            KanaTextNormalizer.normalizedKanaCharacter(from: String(character)) != nil
        }
    }

    func trailingLatinSuggestionToken(from context: String) -> String {
        guard !context.isEmpty else {
            return ""
        }

        var tokenScalars: [UnicodeScalar] = []
        let maxTokenScalars = 64
        var containsLatinCore = false

        for scalar in context.unicodeScalars.reversed() {
            if isLatinSuggestionCoreScalar(scalar) {
                tokenScalars.append(scalar)
                containsLatinCore = true
            } else if isLatinSuggestionMarkScalar(scalar) {
                guard !tokenScalars.isEmpty else {
                    break
                }

                tokenScalars.append(scalar)
            } else if isLatinSuggestionConnectorScalar(scalar) {
                guard containsLatinCore else {
                    break
                }

                tokenScalars.append(scalar)
            } else {
                break
            }

            if tokenScalars.count >= maxTokenScalars {
                break
            }
        }

        guard !tokenScalars.isEmpty,
            containsLatinCore else {
            return ""
        }

        let token = String(String.UnicodeScalarView(tokenScalars.reversed()))
            .trimmingCharacters(in: latinSuggestionTokenBoundaryCharacterSet)

        guard isLatinSuggestionToken(token) else {
            return ""
        }

        return token
    }

    private var latinSuggestionTokenBoundaryCharacterSet: CharacterSet {
        CharacterSet(charactersIn: " -.&'’/,+:;()!?")
            .union(.whitespacesAndNewlines)
    }

    private func isLatinSuggestionConnectorScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar {
        case " ", "-", ".", "&", "'", "’", "/", ",", "+", ":", ";", "(", ")", "!", "?":
            return true
        default:
            return false
        }
    }

    private func isLatinSuggestionCoreScalar(_ scalar: UnicodeScalar) -> Bool {
        if CharacterSet.decimalDigits.contains(scalar) {
            return true
        }

        let scalarText = String(scalar)

        if scalarText.range(of: #"\p{Latin}"#, options: .regularExpression) != nil {
            return true
        }

        return false
    }

    private func isLatinSuggestionMarkScalar(_ scalar: UnicodeScalar) -> Bool {
        let category = scalar.properties.generalCategory

        return category == .nonspacingMark || category == .spacingMark
    }

    func isLatinSuggestionToken(_ token: String) -> Bool {
        guard token.range(of: #"[\p{Latin}0-9]"#, options: .regularExpression) != nil else {
            return false
        }

        return token.range(
            of: #"^[\p{Latin}\p{M}0-9 \-\.&'’/,+:;()!?]+$"#,
            options: .regularExpression
        ) != nil
    }

    func isCurrentLatinSuggestionQuery(_ suggestion: String, query: String) -> Bool {
        suggestion.trimmingCharacters(in: .whitespacesAndNewlines) == query
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
        trailingText: String = ""
    ) {
        let committedTextForInsertion = wrappedCommittedTextIfNeeded(committedText) + trailingText
        commitMarkedTextByReplacingCurrentMarkedText(
            currentMarkedText: sourceText,
            committedText: committedTextForInsertion,
            sourceTextForFallbackReplacement: sourceText
        )

        if learn {
            kanaKanjiConverter.learn(reading: sourceReading, candidate: committedText)
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

    func synchronizeConversionContextIfNeeded(triggeredByExternalChange: Bool = false) {
        let contextBeforeInput = currentTextContextBeforeInput()
        let previousContextBeforeInputTail = lastSynchronizedContextBeforeInputTail
        let previousContextBeforeInputLength = lastSynchronizedContextBeforeInputLength

        defer {
            lastSynchronizedContextBeforeInputTail = String(
                contextBeforeInput.suffix(TextContextLimits.synchronizedContextTailLength)
            )
            lastSynchronizedContextBeforeInputLength = contextBeforeInput.count
        }

        if let activeConversion {
            guard context(contextBeforeInput, hasSuffix: activeConversion.committedText) else {
                appendKeyboardDiagnosticsLogFromInputHandling(
                    "変換状態不一致で破棄 external=\(triggeredByExternalChange) context=\(inputHandlingTextLengthSummary(contextBeforeInput)) committedLen=\(activeConversion.committedText.count)"
                )
                self.activeConversion = nil
                clearComposingState()
                return
            }

            return
        }

        guard !composingRawText.isEmpty else {
            return
        }

        if context(contextBeforeInput, hasSuffix: composingRawText) {
            let hostLikelyConsumedCommittedText =
                !previousContextBeforeInputTail.isEmpty
                && context(previousContextBeforeInputTail, hasSuffix: composingRawText)
                && previousContextBeforeInputLength > contextBeforeInput.count
                && contextBeforeInput == composingRawText

            if (triggeredByExternalChange && contextBeforeInput == composingRawText)
                || hostLikelyConsumedCommittedText {
                // Host app actions such as send can leave only marked text.
                // Treat it as stale composition and clear it so it doesn't remain.
                appendKeyboardDiagnosticsLogFromInputHandling(
                    "編集中テキストを破棄 external=\(triggeredByExternalChange) hostConsumed=\(hostLikelyConsumedCommittedText) context=\(inputHandlingTextLengthSummary(contextBeforeInput)) composingLen=\(composingRawText.count) prevContext=len=\(previousContextBeforeInputLength)"
                )
                markTextProxyEdit()
                textDocumentProxy.unmarkText()
                clearComposingState()
            }

            return
        }

        // Host app side actions (for example send button) can consume marked text.
        // Drop stale internal state so next key starts from a clean composition.
        appendKeyboardDiagnosticsLogFromInputHandling(
            "文脈不一致で編集中テキストを破棄 external=\(triggeredByExternalChange) context=\(inputHandlingTextLengthSummary(contextBeforeInput)) composingLen=\(composingRawText.count) prevContext=len=\(previousContextBeforeInputLength)"
        )

        if triggeredByExternalChange && contextBeforeInput.isEmpty {
            // 行頭・確定文字なしで送信した場合、host は marked を送信済みだが入力欄に
            // marked を残す。ここで unmarkText すると残った marked が実テキストとして確定し
            // 入力欄に残る(送信済みなのに残留)。確定文字が無い(context空)場面なので、
            // commit せず marked を空置換して取り除く。確定済みテキストが無いため
            // 巻き込み削除のリスクがない。
            markTextProxyEdit()
            textDocumentProxy.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
            markTextProxyEdit()
            textDocumentProxy.unmarkText()
        } else {
            markTextProxyEdit()
            textDocumentProxy.unmarkText()
        }

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
