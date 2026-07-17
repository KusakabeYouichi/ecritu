import UIKit

// 変換ジョブの世代管理。kickoff の重複抑止(同一キーの in-flight 再投入禁止)と、直列
// キュー上の旧世代ジョブの早期スキップ判定を、main/変換キューの両方から行うためロックで
// 守る。1打鍵で refreshKeyboardState が複数トリガ(入力処理/ホスト通知/レイアウト)から
// 重複発火するため、抑止が無いと同じ読みのフル変換が2〜4回直列に完走していた。
final class CandidateGenerationSequencer {
    private let lock = NSLock()
    private var latestGeneration: UInt64 = 0
    private var pendingKey: KeyboardViewController.CandidatePresentationCacheKey?

    // 同一キーが in-flight なら nil(再投入不要)。それ以外は新世代を発行する。
    func requestGeneration(
        for key: KeyboardViewController.CandidatePresentationCacheKey
    ) -> UInt64? {
        lock.lock()
        defer { lock.unlock() }
        if pendingKey == key {
            return nil
        }
        latestGeneration &+= 1
        pendingKey = key
        return latestGeneration
    }

    func isCurrent(_ generation: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == latestGeneration
    }

    // ジョブ終了(適用・破棄とも)。自分が最新のときだけ in-flight 印を解除する。
    func finish(_ generation: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        if generation == latestGeneration {
            pendingKey = nil
        }
    }
}

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

        // stale-while-revalidate: 非同期変換が完了するまで前回の候補を表示したままにする。
        // 空を返すと1打鍵ごとに [消去→変換→表示] のチラつきになる(連文節導入以降の体感悪化の原因)。
        // 古い候補のタップ事故は handleConversionCandidateSelection 側の鮮度ガードで防ぐ。
        if let cached = settledCandidatePresentation, !cached.candidates.isEmpty {
            return CandidatePresentation(
                composingText: composingRawText,
                candidates: cached.candidates,
                selectedIndex: nil
            )
        }

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

        // 同一キーの変換が既に走行中なら再投入しない(重複kickoff抑止)。
        guard let generation = candidateGenerationSequencer.requestGeneration(for: pendingKey) else {
            return
        }
        let sequencer = candidateGenerationSequencer

        candidateGenerationQueue.async { [weak self] in
            // 旧世代ジョブの早期スキップ: 直列キューで自分の番が来た時点で新しい打鍵が
            // 来ていたら、フル変換を完走せず即座に譲る(連打バーストでN件の変換が
            // 直列に積み上がるのを防ぐ)。
            guard sequencer.isCurrent(generation) else {
                return
            }
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
                    var merged: [String] = multiClause
                    // 単文節#1 は連文節最良の「直後(2位)」に挿入する(消えない保険は維持しつつ、
                    // 先頭は常に連文節の大域最適)。以前は先頭に前置していたが、基底列挙順の悪い
                    // 単文節#1(はってある→這ってある 等)が連文節の正解(貼ってある)を潰していた。
                    // かな正書ケース(ところもあるが)もこの一般形に包含される。
                    if let first = converterCandidates.first,
                        !multiSet.contains(first) {
                        merged.insert(first, at: min(1, merged.count))
                    }
                    for candidate in converterCandidates where !multiSet.contains(candidate) {
                        if !merged.contains(candidate) {
                            merged.append(candidate)
                        }
                    }
                    converterCandidates = merged
                }
            }

            DispatchQueue.main.async {
                defer {
                    sequencer.finish(generation)
                }
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
        guard candidateGenerationSequencer.isCurrent(generation) else {
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

    func kanaKanjiCandidates(
        for reading: String,
        limit: Int,
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        guard limit > 0 else {
            return []
        }

        let converterLimit = max(limit * ExternalCandidateLimits.lookupMultiplier, limit + 12)
        let converter = kanaKanjiConverter
        // 変換の実行系を candidateGenerationQueue に一本化する(呼び出し元は main のみ)。
        // main 直呼びだと非同期経路と並行してエンジンが2系統で走っていた。直前まで表示
        // していた読みなら converter 側キャッシュにヒットするため、sync でも実質即時。
        let converterCandidates = candidateGenerationQueue.sync {
            converter.candidates(
                for: reading,
                limit: converterLimit,
                systemCandidateMode: systemCandidateMode
            )
        }
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
        // どの経路から来ても表示リストに同一文字列が二度出ないようにする(先勝ち)。
        var seen = Set<String>()
        var candidates = candidates.filter { seen.insert($0).inserted }

        // ユーザ方針: 「出来る」は候補に出してよいが、必ず「できる」より後ろ。
        // 「出来」の直後がひらがな(できる活用の頭 る/た/て/ま/な/ち/れ)で、同一リストに
        // 「でき」に置換した版が存在する場合のみ、漢字版をかな版の直後へ回す。
        // 出来事/出来高/出来上がる 等(直後が漢字 or あ 等)は対象外。
        candidates = SupplementaryCandidateMerger.demotingDekiKanjiBelowKana(candidates)

        guard !composingText.isEmpty else {
            return candidates
        }

        // かな識別(候補==入力かな)の扱い:
        // かなが正書とみなせる根拠(辞書に実在するかな語=ちゃんと、追加語彙=だが/なのに、
        // 学習済み)がある読みだけ変換候補側にも残す。活用+postfix の合成で組み上がった
        // かな全文一致(かってみようかな 等)は変換意図の入力なので末尾チップに一本化する。
        // 合流済みリストの先頭がかな識別=エンジン(連文節curated経路等)が変換の最良として
        // かなを選んだ場合。合流は連文節先頭(1884)なので、単文節の素通りかなが先頭に来る
        // 誤発火(かってみようかな 型)は起きない。やってそうな 等はこれで先頭に残る。
        if let first = candidates.first,
            first == composingText,
            isKanaOnlyText(first) {
            return candidates
        }
        if kanaKanjiConverter.shouldKeepKanaIdentityLeading(for: composingReading) {
            // かな正書の根拠がある読みでも、先頭でない(=エンジン最良でない)かな識別は
            // 末尾へ回す。うってしまって 等で 売ってしまって(1位)の直後にかなが挟まる
            // のを防ぎ、かな確定チップに近い位置に揃える(候補としては残す)。
            var reordered = candidates.filter { candidate in
                !(candidate == composingText && isKanaOnlyText(candidate))
            }
            if reordered.count != candidates.count, isKanaOnlyText(composingText) {
                reordered.append(composingText)
            }
            return reordered
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
