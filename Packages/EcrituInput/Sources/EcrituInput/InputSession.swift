import Foundation

/// 1 つの入力欄に対する入力の状態機械。キーを受け取り、確定する文字列・未確定の表示・候補一覧を返す
public final class InputSession {
    public enum Mode: Equatable { case japanese, latin }

    public static let candidatePageSize = 9

    /// 変えるのは handle(.switchTo…) だけ
    public private(set) var mode: Mode = .japanese

    /// 入力中の表記の上書き(無し / ひらがな / カタカナ)
    private enum DisplayOverride { case none, hiragana, katakana }

    private struct Selection {
        /// 対象 = text の先頭 targetLength 文字
        var targetLength: Int
        var candidates: [String]
        var index: Int
    }

    private enum State {
        case empty
        case composing
        case selecting(Selection)
        /// ラテン文字の直接入力の連なり。打った字数を数える
        case latinRun(count: Int)
    }

    /// 自動確定: text がこの文字数を超えたら判定する。要る変換が求まっていなければ打鍵では待たず、
    /// 裏で求め終わった後の refresh で判定する
    private static let readingLengthLimit = 20
    /// 自動確定で未確定に残す文字数
    private static let autoCommitKeepLength = 8
    /// この文字数を超えたら、全体の 1 位と食い違っても先頭を確定する
    private static let readingHardLimit = 24
    /// 直前の文字列として持つ文字数
    private static let precedingTextLength = 8

    /// 記号の対応
    private static let symbolMapping: [Character: String] = [
        ",": "、", ".": "。", "[": "『", "]": "』", "{": "「", "}": "」", "/": "・", "~": "\u{301C}",
    ]
    /// 直前が ASCII の数字のときは対応させない記号
    private static let symbolsKeptAfterDigit: Set<Character> = [",", ".", "/"]

    private let conversion: ConversionProviding
    private var state: State = .empty
    private var composer = RomajiComposer()
    private var displayOverride: DisplayOverride = .none
    private var precedingText = ""
    /// 1 回の handle / commitAll で確定した文字列
    private var committedInCall = ""
    /// 1 回の handle で自動確定の判定が求めた、読みとその 1 位。表示で同じ変換を取り直さないために使う
    private var knownBestInCall: (reading: String, candidate: String)?
    /// 1 回の handle / refresh で、表示か自動確定の判定に要るのにまだ求まっていなかった変換
    private var pendingLiveInCall: LiveConversionRequest?
    /// 入力中に最後に見せたライヴ変換(読み・そのときの直前の文字列・変換後)。入力を終えたら捨てる
    private var lastShownLive: (reading: String, precedingText: String, candidate: String)?

    public init(conversion: ConversionProviding) {
        self.conversion = conversion
    }

    public func handle(_ key: KeyInput) -> InputResult {
        committedInCall = ""
        knownBestInCall = nil
        pendingLiveInCall = nil
        let handled: Bool
        switch mode {
        case .latin:
            handled = handleLatinMode(key)
        case .japanese:
            handled = handleJapanese(key)
        }
        return makeResult(handled: handled)
    }

    /// 表示中の文字列を確定。学習しない。直接入力の連なりも終える
    public func commitAll() -> InputResult {
        committedInCall = ""
        knownBestInCall = nil
        pendingLiveInCall = nil
        commitAllInternal()
        return makeResult(handled: true)
    }

    /// 裏で求めていた変換(delivered)が求まった後に呼ぶ。反映するものが無ければ nil。
    /// - 読みが delivered のままなら、表示を作り直す(先送りにしていた自動確定の判定もここで行なう)
    /// - 読みが delivered に続けて伸びていたら(速く打ったとき)、自動確定の判定だけを delivered の読みで行なう。
    ///   先頭は今の読みの先頭でもあるので、確定してよい。確定しなかったら nil(今の読みの変換は別に求めている)
    /// - 入力中でない、直前の文字列が違う、読みが別物になった、のどれかなら nil
    public func refresh(delivered: LiveConversionRequest) -> InputResult? {
        guard case .composing = state, delivered.precedingText == precedingText,
              composer.text.hasPrefix(delivered.reading) else {
            return nil
        }
        committedInCall = ""
        knownBestInCall = nil
        pendingLiveInCall = nil
        if delivered.wantsAutoCommit, displayOverride == .none {
            autoCommitIfLong(judging: delivered.reading)
        }
        if composer.text != delivered.reading, committedInCall.isEmpty {
            return nil
        }
        return makeResult(handled: true)
    }

    /// request の変換を求めておく(求め終わるまで待つ)。裏のスレッドから呼ぶ。
    /// 自動確定の判定を先送りにした要求なら、判定に要る変換(先頭と残り)も一緒に求める
    public static func prewarm(_ request: LiveConversionRequest, conversion: ConversionProviding) {
        let text = request.reading
        _ = filtered(conversion.candidates(reading: text, precedingText: request.precedingText), reading: text)
        guard request.wantsAutoCommit, text.count > readingLengthLimit else { return }
        let headLength = text.count - autoCommitKeepLength
        let headReading = String(text.prefix(headLength))
        let head = filtered(
            conversion.candidates(reading: headReading, precedingText: request.precedingText), reading: headReading
        )[0]
        let rest = String(text.dropFirst(headLength))
        _ = conversion.candidates(reading: rest, precedingText: String(head.suffix(precedingTextLength)))
    }

    /// カーソルが動いた可能性があるとき。直前の文字列と連なりを捨てる。未確定には触れない
    public func contextLost() {
        precedingText = ""
        if case .latinRun = state {
            state = .empty
        }
    }

    // MARK: - モードと状態ごとのキー

    private func handleLatinMode(_ key: KeyInput) -> Bool {
        guard key == .switchToJapanese else { return false }
        mode = .japanese
        precedingText = ""
        return true
    }

    private func handleJapanese(_ key: KeyInput) -> Bool {
        switch state {
        case .empty:
            return handleEmpty(key)
        case .composing:
            return handleComposing(key)
        case .selecting(let selection):
            return handleSelecting(key, selection)
        case .latinRun(let count):
            return handleLatinRun(key, count: count)
        }
    }

    /// symbolsPassAfterDigit: 数字の直後の `,` `.` `/` を通す例外を当てるか(空の状態で受けたキーだけ当てる)
    private func handleEmpty(_ key: KeyInput, symbolsPassAfterDigit: Bool = true) -> Bool {
        switch key {
        case .character(let character):
            if character.isLowercaseLatinLetter {
                composer.input(character)
                state = .composing
                commitEmittedSymbolIfAny()
                return true
            }
            if character.isUppercaseLatinLetter {
                state = .latinRun(count: 1)
                appendPreceding(String(character))
                return false
            }
            if let mapped = mappedSymbol(for: character, passAfterDigit: symbolsPassAfterDigit) {
                commit(mapped)
                return true
            }
            appendPreceding(String(character))
            return false
        case .space:
            appendPreceding(" ")
            return false
        case .enter, .backspace, .tab, .left, .right, .up, .down, .escape:
            precedingText = ""
            return false
        case .toHiragana, .toKatakana:
            return false
        case .switchToLatin:
            mode = .latin
            precedingText = ""
            return true
        case .switchToJapanese:
            precedingText = ""
            return true
        }
    }

    private func handleComposing(_ key: KeyInput) -> Bool {
        switch key {
        case .character(let character):
            if character.isLowercaseLatinLetter || character == "-" || (character == "'" && composer.pending == "n")
                || composer.continuesSymbolSpelling(with: character) {
                displayOverride = .none
                composer.input(character)
                if !commitEmittedSymbolIfAny() {
                    autoCommitIfLong()
                }
                return true
            }
            // 数字・記号・大文字: 表示中の文字列を確定してから、空の状態としてキーを扱う(対応のある記号は常に対応先)
            composer.flush()
            commitDisplayed()
            return handleEmpty(key, symbolsPassAfterDigit: false)
        case .backspace:
            if displayOverride != .none {
                displayOverride = .none
            } else {
                composer.deleteBackward()
                if composer.isEmpty {
                    state = .empty
                }
            }
            return true
        case .enter:
            composer.flush()
            commitDisplayed()
            return true
        case .tab:
            composer.flush()
            commitDisplayed()
            precedingText = ""
            return false
        case .space:
            startSelection(shrinkByOne: false)
            return true
        case .left(shift: true):
            startSelection(shrinkByOne: true)
            return true
        case .left, .right, .up, .down, .switchToJapanese:
            return true
        case .escape:
            if displayOverride == .none {
                displayOverride = .hiragana
            }
            return true
        case .toHiragana, .toKatakana:
            // 末尾の n を確定した後の text が空(pending だけ)なら上書きへ入らない
            composer.flush()
            if !composer.text.isEmpty {
                displayOverride = key == .toHiragana ? .hiragana : .katakana
            }
            return true
        case .switchToLatin:
            commitAllInternal()
            mode = .latin
            return true
        }
    }

    private func handleSelecting(_ key: KeyInput, _ selection: Selection) -> Bool {
        var selection = selection
        switch key {
        case .space, .down:
            selection.index = (selection.index + 1) % selection.candidates.count
            state = .selecting(selection)
            return true
        case .up:
            selection.index = (selection.index + selection.candidates.count - 1) % selection.candidates.count
            state = .selecting(selection)
            return true
        case .left(shift: true):
            resizeTarget(selection, by: -1)
            return true
        case .right(shift: true):
            resizeTarget(selection, by: 1)
            return true
        case .left, .right:
            return true
        case .enter:
            commitSelection(selection)
            return true
        case .backspace, .escape:
            state = .composing
            displayOverride = .none
            return true
        case .toHiragana, .toKatakana:
            state = .composing
            return handleComposing(key)
        case .character(let character):
            if let digit = character.wholeNumberValue, character.isASCII {
                // 1〜9: 選択位置のページでその番号の候補。0 と、候補の無い番号は何もしない
                let page = selection.index / Self.candidatePageSize
                let index = page * Self.candidatePageSize + digit - 1
                if digit >= 1, index < selection.candidates.count {
                    selection.index = index
                    commitSelection(selection)
                }
                return true
            }
            // 確定の後は入力中か空。どちらでも対応のある記号は常に対応先
            commitSelection(selection)
            if case .composing = state {
                return handleComposing(key)
            }
            return handleEmpty(key, symbolsPassAfterDigit: false)
        case .tab:
            let displayed = displayedText()
            learn(selection)
            commit(displayed)
            resetComposition()
            precedingText = ""
            return false
        case .switchToLatin:
            commitAllInternal()
            mode = .latin
            return true
        case .switchToJapanese:
            // 何もしない(handled=true)
            return true
        }
    }

    private func handleLatinRun(_ key: KeyInput, count: Int) -> Bool {
        switch key {
        case .character(let character):
            appendPreceding(String(character))
            state = .latinRun(count: count + 1)
            return false
        case .space:
            appendPreceding(" ")
            state = .empty
            return false
        case .backspace:
            precedingText = ""
            state = count > 1 ? .latinRun(count: count - 1) : .empty
            return false
        case .enter, .tab, .left, .right, .up, .down, .escape:
            precedingText = ""
            state = .empty
            return false
        case .toHiragana, .toKatakana:
            state = .empty
            return false
        case .switchToJapanese:
            precedingText = ""
            state = .empty
            return true
        case .switchToLatin:
            precedingText = ""
            state = .empty
            mode = .latin
            return true
        }
    }

    // MARK: - 選択

    /// 入力中から選択中へ。shrinkByOne なら対象を text 全体 − 1 文字(1 文字なら全体)にする
    private func startSelection(shrinkByOne: Bool) {
        composer.flush()
        guard composer.isConvertible else { return }
        displayOverride = .none
        let length = composer.text.count
        let targetLength = shrinkByOne ? max(length - 1, 1) : length
        let candidates = fetchCandidates(reading: String(composer.text.prefix(targetLength)), precedingText: precedingText)
        let index = !shrinkByOne && candidates.count >= 2 ? 1 : 0
        state = .selecting(Selection(targetLength: targetLength, candidates: candidates, index: index))
    }

    private func resizeTarget(_ selection: Selection, by delta: Int) {
        let targetLength = min(max(selection.targetLength + delta, 1), composer.text.count)
        let candidates = fetchCandidates(reading: String(composer.text.prefix(targetLength)), precedingText: precedingText)
        state = .selecting(Selection(targetLength: targetLength, candidates: candidates, index: 0))
    }

    /// 対象の選択候補を確定して学習する。残りの text か pending があれば入力中として続ける
    private func commitSelection(_ selection: Selection) {
        learn(selection)
        commit(selection.candidates[selection.index])
        composer.removePrefix(selection.targetLength)
        displayOverride = .none
        state = composer.isEmpty ? .empty : .composing
    }

    private func learn(_ selection: Selection) {
        conversion.learn(reading: String(composer.text.prefix(selection.targetLength)),
                         candidate: selection.candidates[selection.index])
    }

    // MARK: - 確定

    private func commitAllInternal() {
        switch state {
        case .composing, .selecting:
            composer.flush()
            commit(displayedText())
            resetComposition()
        case .latinRun:
            state = .empty
        case .empty:
            break
        }
        precedingText = ""
    }

    /// 入力中の表示中の文字列を確定して空に戻す(学習しない)
    private func commitDisplayed() {
        commit(displayedText())
        resetComposition()
    }

    /// 記号の綴り(zh など)が完成していたら、表示中の文字列に続けてその記号を確定する(対応のある記号と同じ扱い。学習しない)
    @discardableResult
    private func commitEmittedSymbolIfAny() -> Bool {
        guard let symbol = composer.takeEmittedSymbol() else { return false }
        commit(displayedText() + symbol)
        resetComposition()
        return true
    }

    private func resetComposition() {
        composer = RomajiComposer()
        displayOverride = .none
        state = .empty
        lastShownLive = nil
    }

    /// 入力中に見せたライヴ変換を覚える(次の打鍵で変換がまだ求まっていないときの表示に使う)
    private func rememberShownLive(_ candidate: String) {
        lastShownLive = (composer.text, precedingText, candidate)
    }

    private func commit(_ text: String) {
        committedInCall += text
        appendPreceding(text)
    }

    private func appendPreceding(_ text: String) {
        precedingText = String((precedingText + text).suffix(Self.precedingTextLength))
    }

    /// 読みの長さの上限による自動確定(学習しない)
    ///
    /// judging は判定に使う読み。nil なら今の読み。裏の変換が届いたとき(refresh)は、求めた時点の読みを渡す。
    /// それは今の読みの先頭なので、その先頭を確定してよい
    private func autoCommitIfLong(judging judged: String? = nil) {
        guard composer.isConvertible else { return }
        let text = judged ?? composer.text
        let length = text.count
        guard length > Self.readingLengthLimit else { return }
        let headLength = length - Self.autoCommitKeepLength
        let rest = String(text.dropFirst(headLength))
        // 判定に要る 3 つの変換のどれかがまだ求まっていなければ、打鍵を待たせずに先送りにする(refresh で判定し直す)
        guard let whole = cachedBest(reading: text, precedingText: precedingText),
              let head = cachedBest(reading: String(text.prefix(headLength)), precedingText: precedingText),
              let tail = cachedBest(reading: rest, precedingText: String(head.suffix(Self.precedingTextLength)))
        else {
            if text == composer.text {
                pendingLiveInCall = LiveConversionRequest(
                    reading: text, precedingText: precedingText, wantsAutoCommit: true
                )
            }
            return
        }
        // 先頭の 1 位 P と残りの 1 位 Q をつないだものが全体の 1 位 T と一致したら P を確定する。
        // 一致しなくても、今の読みが上限を超えていれば P を確定する。確定の後の表示は、残りが Q の読みのままなら Q を使う
        if whole == head + tail || composer.text.count > Self.readingHardLimit {
            commit(head)
            composer.removePrefix(headLength)
            if composer.text == rest {
                knownBestInCall = (rest, tail)
            }
            // 確定で読みと直前の文字列が変わった。残りの変換 Q を「見せていた変換」にしておく
            // (読みがその後に伸びていたら、Q に続けて伸びた分をかなで見せる)
            lastShownLive = (rest, precedingText, tail)
        } else if text == composer.text {
            knownBestInCall = (text, whole)
        }
    }

    // MARK: - 表示

    /// deferrable = true は打鍵の結果として返す表示: ライヴ変換がまだ求まっていなければ、待たずにかなを出して
    /// pendingLiveInCall に要る変換を残す。false は確定に使う表示: 求め終わるまで待つ
    private func currentMarked(deferrable: Bool = false) -> MarkedText? {
        var segments: [MarkedText.Segment] = []
        func add(_ text: String, _ style: MarkedText.Style) {
            if !text.isEmpty {
                segments.append(MarkedText.Segment(text: text, style: style))
            }
        }
        switch state {
        case .empty, .latinRun:
            return nil
        case .composing:
            switch displayOverride {
            case .none:
                if let known = knownBestInCall, known.reading == composer.text {
                    add(known.candidate, .converted)
                    rememberShownLive(known.candidate)
                } else if composer.isConvertible {
                    if !deferrable {
                        add(bestCandidate(reading: composer.text, precedingText: precedingText), .converted)
                    } else if let best = cachedBest(reading: composer.text, precedingText: precedingText) {
                        add(best, .converted)
                        rememberShownLive(best)
                    } else {
                        // まだ求まっていない。直前に見せていた変換が今の読みの先頭に当たるなら、それを残して
                        // 打ち足した分だけをかなで続ける(全体をかなへ戻すと、打つたびに全体がちらつく)
                        if let shown = lastShownLive, shown.precedingText == precedingText,
                           composer.text.hasPrefix(shown.reading) {
                            add(shown.candidate, .converted)
                            add(String(composer.text.dropFirst(shown.reading.count)), .raw)
                        } else {
                            add(composer.text, .raw)
                        }
                        // 自動確定の判定を先送りにした要求が同じ読みで残っていれば、それを保つ(判定の印を落とさない)
                        if pendingLiveInCall?.reading != composer.text {
                            pendingLiveInCall = LiveConversionRequest(
                                reading: composer.text, precedingText: precedingText, wantsAutoCommit: false
                            )
                        }
                    }
                } else {
                    add(composer.text, .raw)
                }
            case .hiragana:
                add(composer.text, .raw)
            case .katakana:
                add(katakana(from: composer.text), .raw)
            }
        case .selecting(let selection):
            let target = selection.candidates[selection.index]
            add(target, .target)
            let rest = String(composer.text.dropFirst(selection.targetLength))
            // 選択中へ入れるのは text が変換できるときだけなので、残りも変換できる
            if !rest.isEmpty {
                let precedingForRest = String(target.suffix(Self.precedingTextLength))
                add(bestCandidate(reading: rest, precedingText: precedingForRest), .converted)
            }
        }
        add(composer.pending, .raw)
        return segments.isEmpty ? nil : MarkedText(segments: segments)
    }

    private func displayedText() -> String {
        currentMarked()?.segments.map(\.text).joined() ?? ""
    }

    private func currentCandidates() -> CandidateList? {
        guard case .selecting(let selection) = state else { return nil }
        return CandidateList(items: selection.candidates, selectedIndex: selection.index)
    }

    private func makeResult(handled: Bool) -> InputResult {
        #if DEBUG
        if Self.containsForbiddenCharacter(committedInCall) {
            assertionFailure("確定した文字列に U+FF00...U+FFFD の文字が残っている")
        }
        #endif
        let marked = currentMarked(deferrable: true)
        // 要る変換が残るのは入力中だけ(確定や選択へ移った後は要らない)
        var pending: LiveConversionRequest?
        if case .composing = state {
            pending = pendingLiveInCall
        }
        return InputResult(
            handled: handled, committed: committedInCall, marked: marked, candidates: currentCandidates(),
            pendingConversion: pending
        )
    }

    // MARK: - 変換

    /// 空の文字列と、U+FF00...U+FFFD の文字を含む候補を落とす。空になったら読みそのものを唯一の候補にする
    private static func filtered(_ candidates: [String], reading: String) -> [String] {
        let kept = candidates.filter { !$0.isEmpty && !containsForbiddenCharacter($0) }
        return kept.isEmpty ? [reading] : kept
    }

    private func fetchCandidates(reading: String, precedingText: String) -> [String] {
        Self.filtered(conversion.candidates(reading: reading, precedingText: precedingText), reading: reading)
    }

    private func bestCandidate(reading: String, precedingText: String) -> String {
        fetchCandidates(reading: reading, precedingText: precedingText)[0]
    }

    /// 待たずに答えられるときだけ 1 位を返す
    private func cachedBest(reading: String, precedingText: String) -> String? {
        conversion.cachedCandidates(reading: reading, precedingText: precedingText)
            .map { Self.filtered($0, reading: reading)[0] }
    }

    private func mappedSymbol(for character: Character, passAfterDigit: Bool) -> String? {
        if passAfterDigit, Self.symbolsKeptAfterDigit.contains(character),
           let last = precedingText.last, last.isASCII, last.isNumber {
            return nil
        }
        return Self.symbolMapping[character]
    }

    private static func containsForbiddenCharacter(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0xFF00...0xFFFD).contains($0.value) }
    }
}

private extension Character {
    var isLowercaseLatinLetter: Bool { asciiValue.map { (UInt8(ascii: "a")...UInt8(ascii: "z")).contains($0) } ?? false }
    var isUppercaseLatinLetter: Bool { asciiValue.map { (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains($0) } ?? false }
}
