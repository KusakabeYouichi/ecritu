import UIKit

// 候補提示: 変換候補プレゼンテーションの生成(同期/非同期)・連文節候補の合流・
// 表示用フィルタ(かな識別の扱い)・Latin サジェストのクエリ/トークン判定。
extension KeyboardViewController {
    enum CandidateLimits {
        static let presentationDefault = 24
        static let conversionDefault = 24
        static let latinSuggestionDefault = 40
    }

    enum DiagnosticsThresholds {
        static let latinSuggestionSlowMs = 18
        static let candidatePresentationSlowMs = 18
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

    func kickOffAsyncCandidateGeneration(
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
            var converterCandidates = converter.candidates(
                for: reading,
                limit: converterLimit,
                systemCandidateMode: systemCandidateMode
            )

            // 連文節変換(案1: 自前単語LM): フラグ on の時のみ、連文節候補を上位(先頭候補の次)へ
            // 合流。既存の単文節候補は必ず残し、重複は除外する(退行防止)。
            if Self.isMultiClauseConversionEnabled {
                let multiClause = converter.multiClauseCandidates(
                    for: reading,
                    systemCandidateMode: systemCandidateMode
                )
                if !multiClause.isEmpty {
                    // 連文節の並び(最良+変種)を先頭にそのまま置き、単文節候補を後ろに
                    // 続ける(重複は単文節側から除去)。連文節が返せる読み(4文字以上)では
                    // 大域最適の方が単文節合成より信頼できるため。
                    let multiSet = Set(multiClause)
                    var merged: [String] = []
                    if let first = converterCandidates.first, !multiSet.contains(first) {
                        merged.append(first)
                    }
                    merged.append(contentsOf: multiClause)
                    for candidate in converterCandidates where !multiSet.contains(candidate) && candidate != merged.first {
                        if !merged.contains(candidate) {
                            merged.append(candidate)
                        }
                    }
                    converterCandidates = merged
                }
            }

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

    func applyAsyncCandidateGenerationResult(
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

    func candidatesForPresentation(
        from candidates: [String],
        composingText: String
    ) -> [String] {
        guard !composingText.isEmpty else {
            return candidates
        }

        // かな識別(候補==入力かな)の扱い:
        // かなが正書とみなせる根拠(辞書に実在するかな語=ちゃんと、追加語彙=だが/なのに、
        // 学習済み)がある読みだけ変換候補側にも残す。活用+postfix の合成で組み上がった
        // かな全文一致(かってみようかな 等)は変換意図の入力なので末尾チップに一本化する。
        if kanaKanjiConverter.shouldKeepKanaIdentityLeading(for: composingReading) {
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

    var latinSuggestionTokenBoundaryCharacterSet: CharacterSet {
        CharacterSet(charactersIn: " -.&'’/,+:;()!?")
            .union(.whitespacesAndNewlines)
    }

    func isLatinSuggestionConnectorScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar {
        case " ", "-", ".", "&", "'", "’", "/", ",", "+", ":", ";", "(", ")", "!", "?":
            return true
        default:
            return false
        }
    }

    func isLatinSuggestionCoreScalar(_ scalar: UnicodeScalar) -> Bool {
        if CharacterSet.decimalDigits.contains(scalar) {
            return true
        }

        let scalarText = String(scalar)

        if scalarText.range(of: #"\p{Latin}"#, options: .regularExpression) != nil {
            return true
        }

        return false
    }

    func isLatinSuggestionMarkScalar(_ scalar: UnicodeScalar) -> Bool {
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
}
