import UIKit

// markedText 確定まわり: 下線(marked)残留の掃除・確定のプリフライト/フォールバック・
// markedText ウォッチドッグ・ホスト同期。ホストアプリ差異のワークアラウンドが集まる場所。
extension KeyboardViewController {
    enum CommitSafetyLimits {
        static let composingContextPrefixTailLength = 16
        static let delayedUnderlineClearMs: Int = 30
        static let delayedUnderlineClearLongMs: Int = 480
        static let delayedUnderlineClearLongerMs: Int = 900
        static let verifiedEphemeralClearDelayMs: Int = 120
        static let verifiedEphemeralMarker = "\u{2060}"
        static let hostCallbackUnderlineClearWindow: CFTimeInterval = 2.4
        static let minimumNoReplaceClearNudgeWidth = 8
    }

    func inputHandlingTextLengthSummary(_ text: String) -> String {
        "len=\(text.count)"
    }

    func appendCommitUnderlineDiagnostics(
        _ stage: String,
        committedTextLength: Int? = nil,
        markedTextLength: Int? = nil,
        note: String = ""
    ) {
        guard Self.isCommitUnderlineDiagnosticsLoggingEnabled else {
            return
        }

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

    func checkMarkedTextHealth() {
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
}
