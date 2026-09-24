import UIKit

// 未確定の方式「mountain view」(3210): 未確定をホストに下線付きの marked text として預けるのではなく、
// 普通の確定文字として置き(insertText)、どこまでが変換対象かを拡張側で追跡する。Google 日本語入力の方式。
//
// これで変わること(実機動画 2026-09-24 23:45 で確認した Google の動き):
//   - 入力欄をタップしても未確定は消えない(ただの文字なので)。カーソルが未確定の中に入ると、
//     カーソルより左だけが変換対象になり、候補もその区間のものになる
//   - 候補を選ぶと左区間だけが置き換わり、カーソルは残りの右区間の末尾へ飛ぶ。残りが次の変換対象
//   - 送信・完了で未確定が捨てられない(確定文字だから)
//   - 下線は出ない
//
// ホストへの窓口は 3 つに絞る: presentPlainComposition(表示の差分適用)/ commitPlainComposition(区間の置換)/
// trackPlainCompositionCursorIfNeeded(カーソル位置の追跡)。marked 方式の下線掃除・watchdog・アイドル確定・
// ホスト確定の照合はすべてこの方式では無効(呼び元の先頭で usesPlainTextComposition を見て抜ける)。
extension KeyboardViewController {
    // 設定の読み。打鍵ごとに数回呼ばれるので 1 秒だけ覚える(UserDefaults の読みを毎回しない)
    var usesPlainTextComposition: Bool {
        let now = CFAbsoluteTimeGetCurrent()
        if now - plainTextCompositionModeCheckedAt > 1.0 {
            let raw = sharedStringValue(
                from: sharedDefaults,
                key: SharedDefaultsKeys.composingTextStyle,
                fallback: "écritu"
            )
            plainTextCompositionModeCached = PlainTextComposition.isMountainView(rawValue: raw)
            plainTextCompositionModeCheckedAt = now
        }
        return plainTextCompositionModeCached
    }

    // 変換の対象になる区間(カーソルが未確定の中にあれば、その左側だけ)
    var effectiveComposingRawText: String {
        guard usesPlainTextComposition, let offset = plainCompositionCursorOffset else {
            return composingRawText
        }
        return String(composingRawText.prefix(offset))
    }

    var effectiveComposingReading: String {
        guard usesPlainTextComposition, let offset = plainCompositionCursorOffset else {
            return composingReading
        }
        return String(composingReading.prefix(offset))
    }

    // 未確定の表示を text に合わせる。ホストに置いてある文字列(plainCompositionPresentedText)との差分だけを
    // insertText / deleteBackward で当てる。カーソルが未確定の中にあるときは、その位置での挿入・削除だけを
    // 差分として受け付け、それ以外(候補循環など)はカーソルを末尾へ戻してから全置換する
    func presentPlainComposition(_ text: String) {
        let old = plainCompositionPresentedText
        guard text != old else {
            return
        }
        let plan = PlainTextComposition.plan(
            old: old,
            new: text,
            cursorOffset: plainCompositionCursorOffset
        )
        if plan.moveCursorToEndFirst > 0 {
            markTextProxyEdit()
            textDocumentProxy.adjustTextPosition(byCharacterOffset: plan.moveCursorToEndFirst)
        }
        if plan.deleteCount > 0 {
            markTextProxyEdit()
            for _ in 0..<plan.deleteCount {
                textDocumentProxy.deleteBackward()
            }
        }
        if !plan.insertText.isEmpty {
            markTextProxyEdit()
            textDocumentProxy.insertText(plan.insertText)
        }
        plainCompositionPresentedText = text
        plainCompositionCursorOffset = plan.cursorOffsetAfter
        lastMarkedTextUpdateAt = CFAbsoluteTimeGetCurrent()
        if text.isEmpty {
            plainCompositionCursorOffset = nil
        }
    }

    // 変換対象の区間(カーソルまで)を committedText に置き換える。右側に残りがあればカーソルをその末尾へ
    // 送り、残りを返す(呼び元が次の未確定として引き継ぐ)。残りが無ければ空を返す
    @discardableResult
    func commitPlainComposition(_ committedText: String) -> String {
        let old = plainCompositionPresentedText
        let boundary = min(plainCompositionCursorOffset ?? old.count, old.count)
        let left = String(old.prefix(boundary))
        let remainder = String(old.dropFirst(boundary))
        if left != committedText {
            markTextProxyEdit()
            for _ in 0..<left.count {
                textDocumentProxy.deleteBackward()
            }
            if !committedText.isEmpty {
                textDocumentProxy.insertText(committedText)
            }
        }
        if !remainder.isEmpty {
            markTextProxyEdit()
            textDocumentProxy.adjustTextPosition(byCharacterOffset: remainder.utf16.count)
        }
        appendKeyboardDiagnosticsLogFromInputHandling(
            "mountain view 確定 left=\(left.count)字→\(committedText.count)字 remainder=\(remainder.count)字"
        )
        plainCompositionPresentedText = remainder
        plainCompositionCursorOffset = nil
        return remainder
    }

    // 確定のあとに右側の残りを次の未確定として引き継ぐ(候補の並びとカーソル位置の記憶を作り直す)
    func adoptPlainCompositionRemainder(rawRemainder: String, readingRemainder: String) {
        composingRawText = rawRemainder
        composingReading = readingRemainder
        hasParenthesesWrapper = false
        plainCompositionCursorOffset = nil
        invalidateSettledCandidatePresentation()
        // 残りの直前の文脈(確定した文字を含む)を覚え直す。カーソル追跡の錨になる
        let contextBeforeInput = currentTextContextBeforeInput()
        let prefixWithRemainder = contextBeforeInput.dropLast(min(rawRemainder.count, contextBeforeInput.count))
        composingContextPrefixTail = String(prefixWithRemainder.suffix(CommitSafetyLimits.composingContextPrefixTailLength))
    }

    // カーソル位置の追跡。未確定(確定文字として置いてある)の中のどこにカーソルがあるかを、
    // 直前の文脈+未確定の先頭部分 / 未確定の残り部分 の一致で求める。一致しなければ未確定を手放す
    // (文字は本文に残る。Google も同じ)
    func trackPlainCompositionCursorIfNeeded(trigger: String) {
        guard usesPlainTextComposition,
            activeConversion == nil,
            !plainCompositionPresentedText.isEmpty else {
            return
        }
        let before = currentTextContextBeforeInput()
        let after = currentTextContextAfterInput()
        let located = PlainTextComposition.locateCursor(
            before: before,
            after: after,
            prefixTail: composingContextPrefixTail,
            presented: plainCompositionPresentedText
        )
        guard let located else {
            appendKeyboardDiagnosticsLogFromInputHandling(
                "mountain view 未確定を手放す(文脈に見つからない) trigger=\(trigger) presented=\(plainCompositionPresentedText.count)字",
                critical: true
            )
            dropPlainCompositionTracking()
            return
        }
        let newOffset: Int? = located == plainCompositionPresentedText.count ? nil : located
        if newOffset != plainCompositionCursorOffset {
            appendKeyboardDiagnosticsLogFromInputHandling(
                "mountain view カーソル位置 \(plainCompositionCursorOffset.map(String.init) ?? "末尾")→\(newOffset.map(String.init) ?? "末尾") trigger=\(trigger)"
            )
            plainCompositionCursorOffset = newOffset
            invalidateSettledCandidatePresentation()
        }
    }

    // 未確定の追跡をやめる(本文の文字はそのまま)
    func dropPlainCompositionTracking() {
        plainCompositionPresentedText = ""
        plainCompositionCursorOffset = nil
        activeConversion = nil
        clearComposingState()
    }

    // カーソルが未確定の中にあるときの打鍵: ホストはカーソル位置に挿入するので、こちらの読みも同じ位置へ差し込む
    func insertPlainCompositionCharacterAtCursor(raw: String, normalized: String) -> Bool {
        guard usesPlainTextComposition, let offset = plainCompositionCursorOffset else {
            return false
        }
        var rawChars = Array(composingRawText)
        var readingChars = Array(composingReading)
        let index = min(offset, rawChars.count)
        rawChars.insert(contentsOf: Array(raw), at: index)
        readingChars.insert(contentsOf: Array(normalized), at: min(index, readingChars.count))
        composingRawText = String(rawChars)
        composingReading = String(readingChars)
        presentPlainComposition(composingRawText)
        return true
    }

    // カーソルが未確定の中にあるときの削除: カーソルの左 1 字を読みからも消す。
    // カーソルが未確定の先頭(左に消すものが無い)なら未確定を手放してホストに任せる
    func deletePlainCompositionCharacterBeforeCursor() -> Bool {
        guard usesPlainTextComposition, let offset = plainCompositionCursorOffset else {
            return false
        }
        guard offset > 0 else {
            dropPlainCompositionTracking()
            markTextProxyEdit()
            textDocumentProxy.deleteBackward()
            return true
        }
        var rawChars = Array(composingRawText)
        var readingChars = Array(composingReading)
        rawChars.remove(at: offset - 1)
        if offset - 1 < readingChars.count {
            readingChars.remove(at: offset - 1)
        }
        composingRawText = String(rawChars)
        composingReading = String(readingChars)
        if composingRawText.isEmpty {
            presentPlainComposition("")
            clearComposingState()
        } else {
            presentPlainComposition(composingRawText)
        }
        return true
    }
}

// 純関数の部分。UIKit に触らないのでテストで固定する
enum PlainTextComposition {
    static func isMountainView(rawValue: String) -> Bool {
        switch rawValue {
        case "mountain view", "mountainview", "mountainView":
            return true
        default:
            return false
        }
    }

    struct Plan: Equatable {
        var moveCursorToEndFirst: Int = 0   // 先にカーソルを末尾へ送る文字数(utf16)
        var deleteCount: Int = 0            // deleteBackward の回数(Character 単位)
        var insertText: String = ""
        var cursorOffsetAfter: Int? = nil   // 適用後の未確定内カーソル位置(nil=末尾)
    }

    // old(ホストに置いてある)を new にするための最小の手順。
    // カーソルが末尾: 共通の先頭を残して、後ろを消して差し込む(候補循環はこの形)。
    // カーソルが途中(offset): その位置での純粋な挿入か、その直前の純粋な削除だけを差分として受ける。
    // それ以外はカーソルを末尾へ送ってから全置換する(カーソルは末尾になる)
    static func plan(old: String, new: String, cursorOffset: Int?) -> Plan {
        let oldChars = Array(old)
        let newChars = Array(new)
        if let offset = cursorOffset, offset < oldChars.count {
            let leftOld = Array(oldChars[..<offset])
            let rightOld = Array(oldChars[offset...])
            // 純粋な挿入: new = leftOld + ins + rightOld
            if newChars.count > oldChars.count,
                Array(newChars[..<offset]) == leftOld,
                Array(newChars[(newChars.count - rightOld.count)...]) == rightOld {
                let ins = String(newChars[offset..<(newChars.count - rightOld.count)])
                return Plan(deleteCount: 0, insertText: ins, cursorOffsetAfter: offset + ins.count)
            }
            // 純粋な削除(カーソルの直前 n 字): new = leftOld.dropLast(n) + rightOld
            if newChars.count < oldChars.count,
                newChars.count >= rightOld.count,
                Array(newChars[(newChars.count - rightOld.count)...]) == rightOld {
                let n = oldChars.count - newChars.count
                if n <= leftOld.count, Array(newChars[..<(newChars.count - rightOld.count)]) == Array(leftOld.dropLast(n)) {
                    return Plan(deleteCount: n, insertText: "", cursorOffsetAfter: offset - n)
                }
            }
            // それ以外: 末尾へ送ってから全置換
            let moveBy = String(rightOld).utf16.count
            return Plan(moveCursorToEndFirst: moveBy, deleteCount: oldChars.count, insertText: new, cursorOffsetAfter: nil)
        }
        // カーソルは末尾
        var common = 0
        while common < oldChars.count, common < newChars.count, oldChars[common] == newChars[common] {
            common += 1
        }
        return Plan(
            deleteCount: oldChars.count - common,
            insertText: String(newChars[common...]),
            cursorOffsetAfter: nil
        )
    }

    // カーソルが未確定のどこにあるか。末尾を優先して試し、見つからなければ nil(未確定が本文から消えた)
    static func locateCursor(before: String, after: String, prefixTail: String, presented: String) -> Int? {
        let chars = Array(presented)
        for k in stride(from: chars.count, through: 0, by: -1) {
            let left = String(chars[..<k])
            let right = String(chars[k...])
            if before.hasSuffix(prefixTail + left), after.hasPrefix(right) {
                return k
            }
        }
        return nil
    }
}
