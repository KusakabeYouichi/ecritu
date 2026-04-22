import Foundation
import UIKit

extension KeyboardViewController {
    func makeCandidatePresentation(
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> CandidatePresentation {
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

        return CandidatePresentation(
            composingText: composingRawText,
            candidates: kanaKanjiConverter.candidates(
                for: composingReading,
                limit: 8,
                systemCandidateMode: systemCandidateMode
            ),
            selectedIndex: nil
        )
    }

    func handleTextInput(_ text: String) {
        guard !text.isEmpty else {
            return
        }

        commitActiveConversion(learn: true)

        if currentInputMode == .kana,
           let normalizedKana = KanaTextNormalizer.normalizedKanaCharacter(from: text) {
            composingRawText.append(text)
            composingReading.append(normalizedKana)
            setMarkedComposingText(composingRawText)
        } else {
            if currentInputMode == .kana,
               !composingReading.isEmpty,
               shouldAutoCommitConversion(beforeInserting: text) {
                commitComposingTextBeforeDelimiterInput()
                textDocumentProxy.insertText(text)
                refreshKeyboardStateAsync()
                return
            }

            if !composingRawText.isEmpty {
                textDocumentProxy.unmarkText()
                clearComposingState()
            }

            textDocumentProxy.insertText(text)
            clearComposingState()
        }

        refreshKeyboardStateAsync()
    }

    func shouldAutoCommitConversion(beforeInserting text: String) -> Bool {
        switch text {
        case "。", "、", "！", "？", ".", ",", "!", "?", "」", "』", "）", ")", "】", "]", "〉", "》":
            return true
        default:
            return false
        }
    }

    func commitComposingTextBeforeDelimiterInput() {
        guard !composingRawText.isEmpty,
              !composingReading.isEmpty else {
            textDocumentProxy.unmarkText()
            clearComposingState()
            return
        }

        let sourceText = composingRawText
        let sourceReading = composingReading

        let preferredCandidate = kanaKanjiConverter.candidates(
            for: sourceReading,
            limit: 12,
            systemCandidateMode: currentKanaKanjiCandidateSourceModeFromSharedDefaults()
        ).first

        let committedText = preferredCandidate ?? sourceText

        // Commit marked text first, then replace deterministically when needed.
        textDocumentProxy.unmarkText()

        if committedText != sourceText {
            deleteBackwardCharacterCount(sourceText.count)
            textDocumentProxy.insertText(committedText)
        }

        kanaKanjiConverter.learn(reading: sourceReading, candidate: committedText)
        clearComposingState()
    }

    func handleDeleteBackward() {
        if activeConversion != nil {
            commitActiveConversion(learn: false)
            clearComposingState()
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
            } else {
                setMarkedComposingText(composingRawText)
            }

            refreshKeyboardStateAsync()
            return
        }

        textDocumentProxy.deleteBackward()
        refreshKeyboardStateAsync()
    }

    func handleSpaceInput() {
        guard currentInputMode == .kana else {
            commitActiveConversion(learn: true)

            if !composingRawText.isEmpty {
                textDocumentProxy.unmarkText()
            }

            clearComposingState()
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
            textDocumentProxy.insertText(" ")
            refreshKeyboardStateAsync()
            return
        }

        guard beginConversionFromComposingText() else {
            textDocumentProxy.unmarkText()
            textDocumentProxy.insertText(" ")
            clearComposingState()
            refreshKeyboardStateAsync()
            return
        }

        refreshKeyboardStateAsync()
    }

    func handleReturnInput() {
        commitActiveConversion(learn: true)

        if !composingRawText.isEmpty {
            textDocumentProxy.unmarkText()
        }

        clearComposingState()
        textDocumentProxy.insertText("\n")
        refreshKeyboardStateAsync()
    }

    func handleConversionCandidateSelection(_ index: Int) {
        guard currentInputMode == .kana else {
            return
        }

        if var conversion = activeConversion {
            guard conversion.candidates.indices.contains(index) else {
                return
            }

            if index != conversion.selectedIndex {
                replaceActiveConversionText(with: conversion.candidates[index], conversion: &conversion)
                activeConversion = conversion
            }

            commitActiveConversion(learn: true)
            refreshKeyboardStateAsync()
            return
        }

        guard !composingReading.isEmpty else {
            return
        }

        let candidates = kanaKanjiConverter.candidates(
            for: composingReading,
            limit: 8,
            systemCandidateMode: currentKanaKanjiCandidateSourceModeFromSharedDefaults()
        )

        guard candidates.indices.contains(index) else {
            return
        }

        replaceComposingText(with: candidates[index])
        kanaKanjiConverter.learn(reading: composingReading, candidate: candidates[index])
        textDocumentProxy.unmarkText()
        clearComposingState()
        refreshKeyboardStateAsync()
    }

    func handleCommitComposingText() {
        guard currentInputMode == .kana else {
            return
        }

        if activeConversion != nil {
            commitActiveConversion(learn: true)
            clearComposingState()
            refreshKeyboardStateAsync()
            return
        }

        guard !composingRawText.isEmpty else {
            return
        }

        if !composingReading.isEmpty {
            kanaKanjiConverter.learn(reading: composingReading, candidate: composingRawText)
        }

        textDocumentProxy.unmarkText()
        clearComposingState()
        refreshKeyboardStateAsync()
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

        let candidates = kanaKanjiConverter.candidates(
            for: composingReading,
            limit: 12,
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
        textDocumentProxy.setMarkedText(
            text,
            selectedRange: NSRange(location: text.count, length: 0)
        )
    }

    func clearMarkedComposingText() {
        textDocumentProxy.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
        textDocumentProxy.unmarkText()
    }

    func deleteBackwardCharacterCount(_ count: Int) {
        guard count > 0 else {
            return
        }

        for _ in 0..<count {
            textDocumentProxy.deleteBackward()
        }
    }

    func clearComposingState() {
        composingRawText = ""
        composingReading = ""
    }

    func commitActiveConversion(learn: Bool) {
        guard let activeConversion else {
            return
        }

        if learn {
            kanaKanjiConverter.learn(
                reading: activeConversion.reading,
                candidate: activeConversion.committedText
            )
        }

        textDocumentProxy.unmarkText()
        self.activeConversion = nil
    }

    func synchronizeConversionContextIfNeeded() {
        guard let activeConversion else {
            return
        }

        let contextBeforeInput = textDocumentProxy.documentContextBeforeInput ?? ""

        guard contextBeforeInput.hasSuffix(activeConversion.committedText) else {
            self.activeConversion = nil
            clearComposingState()
            return
        }
    }

    func applyKanaPostModifier(_ buttonState: KanaPostModifierButtonState) -> Bool {
        commitActiveConversion(learn: true)

        if currentInputMode == .kana,
           !composingRawText.isEmpty,
           let lastCharacter = composingRawText.last,
           let replacedCharacter = FlickKanaLayout.postfixModifiedCharacter(
                from: lastCharacter,
                for: buttonState
           ) {
            composingRawText.removeLast()
            composingRawText.append(String(replacedCharacter))

            if !composingReading.isEmpty {
                composingReading.removeLast()
            }

            if let normalizedKana = KanaTextNormalizer.normalizedKanaCharacter(from: String(replacedCharacter)) {
                composingReading.append(normalizedKana)
            }

            setMarkedComposingText(composingRawText)
            refreshKeyboardStateAsync()
            return true
        }

        guard let contextBeforeInput = textDocumentProxy.documentContextBeforeInput,
              let lastCharacter = contextBeforeInput.last,
              let replacedCharacter = FlickKanaLayout.postfixModifiedCharacter(
                  from: lastCharacter,
                  for: buttonState
              ) else {
            return false
        }

        textDocumentProxy.deleteBackward()
        textDocumentProxy.insertText(String(replacedCharacter))

        if currentInputMode == .kana,
           !composingRawText.isEmpty {
            composingRawText.removeLast()
            composingRawText.append(String(replacedCharacter))

            if !composingReading.isEmpty {
                composingReading.removeLast()
            }

            if let normalizedKana = KanaTextNormalizer.normalizedKanaCharacter(from: String(replacedCharacter)) {
                composingReading.append(normalizedKana)
            }
        }

        refreshKeyboardStateAsync()
        return true
    }
}
