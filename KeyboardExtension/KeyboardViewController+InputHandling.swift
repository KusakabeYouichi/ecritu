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
        guard !text.isEmpty else {
            return false
        }

        return text.unicodeScalars.allSatisfy { scalar in
            CharacterSet.punctuationCharacters.contains(scalar)
                || CharacterSet.symbols.contains(scalar)
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
        commitComposingText(
            sourceText: sourceText,
            sourceReading: sourceReading,
            committedText: committedText,
            learn: true
        )
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
        let hasActiveConversion = activeConversion != nil
        let hasComposingText = !composingRawText.isEmpty

        if hasActiveConversion {
            commitActiveConversion(learn: true)
            refreshKeyboardStateAsync()
            return
        }

        if hasComposingText {
            commitComposingText(
                sourceText: composingRawText,
                sourceReading: composingReading,
                committedText: composingRawText,
                learn: true
            )
            refreshKeyboardStateAsync()
            return
        }

        clearComposingState()
        textDocumentProxy.insertText("\n")
        refreshKeyboardStateAsync()
    }

    func handleConversionCandidateSelection(_ index: Int) {
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

        let candidates = kanaKanjiConverter.candidates(
            for: composingReading,
            limit: 8,
            systemCandidateMode: currentKanaKanjiCandidateSourceModeFromSharedDefaults()
        )

        guard candidates.indices.contains(index) else {
            return
        }

        commitComposingText(
            sourceText: composingRawText,
            sourceReading: composingReading,
            committedText: candidates[index],
            learn: true
        )
        refreshKeyboardStateAsync()
    }

    func handleCommitComposingText() {
        guard currentInputMode == .kana else {
            return
        }

        if let activeConversion {
            commitActiveConversion(
                activeConversion,
                committedText: activeConversion.sourceText,
                learn: true
            )
            clearMarkedComposingText()
            clearComposingState()
            refreshKeyboardStateAsync()
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

    func commitComposingText(
        sourceText: String,
        sourceReading: String,
        committedText: String,
        learn: Bool
    ) {
        clearMarkedComposingText()

        // If source text still exists as plain text after clearing marked text, replace it.
        let contextBeforeInput = textDocumentProxy.documentContextBeforeInput ?? ""
        if !sourceText.isEmpty,
            contextBeforeInput.hasSuffix(sourceText) {
            deleteBackwardCharacterCount(sourceText.count)
        }

        textDocumentProxy.insertText(committedText)
        textDocumentProxy.unmarkText()
        DispatchQueue.main.async { [weak self] in
            self?.textDocumentProxy.unmarkText()
        }

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
        learn: Bool
    ) {
        clearMarkedComposingText()

        // If source text still exists as plain text after clearing marked text, replace it.
        let contextBeforeInput = textDocumentProxy.documentContextBeforeInput ?? ""
        if !conversion.committedText.isEmpty,
            contextBeforeInput.hasSuffix(conversion.committedText) {
            deleteBackwardCharacterCount(conversion.committedText.count)
        } else if !conversion.sourceText.isEmpty,
                    contextBeforeInput.hasSuffix(conversion.sourceText) {
            deleteBackwardCharacterCount(conversion.sourceText.count)
        }

        textDocumentProxy.insertText(committedText)
        textDocumentProxy.unmarkText()
        DispatchQueue.main.async { [weak self] in
            self?.textDocumentProxy.unmarkText()
        }

        if learn {
            kanaKanjiConverter.learn(
                reading: conversion.reading,
                candidate: committedText
            )
        }

        self.activeConversion = nil
        clearComposingState()
    }

    func synchronizeConversionContextIfNeeded() {
        let contextBeforeInput = textDocumentProxy.documentContextBeforeInput ?? ""

        if let activeConversion {
            guard contextBeforeInput.hasSuffix(activeConversion.committedText) else {
                self.activeConversion = nil
                clearComposingState()
                return
            }

            return
        }

        guard !composingRawText.isEmpty else {
            return
        }

        guard contextBeforeInput.hasSuffix(composingRawText) else {
            // Host app side actions (for example send button) can consume marked text.
            // Drop stale internal state so next key starts from a clean composition.
            textDocumentProxy.unmarkText()
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
