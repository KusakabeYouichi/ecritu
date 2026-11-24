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

    /// 自動確定: text がこの文字数を超えたら、打鍵ごとに 1 回だけ判定する(同期のライヴ変換を短く保つ)
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

    public init(conversion: ConversionProviding) {
        self.conversion = conversion
    }

    public func handle(_ key: KeyInput) -> InputResult {
        committedInCall = ""
        knownBestInCall = nil
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
        commitAllInternal()
        return makeResult(handled: true)
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
    }

    private func commit(_ text: String) {
        committedInCall += text
        appendPreceding(text)
    }

    private func appendPreceding(_ text: String) {
        precedingText = String((precedingText + text).suffix(Self.precedingTextLength))
    }

    /// 読みの長さの上限による自動確定(学習しない)
    private func autoCommitIfLong() {
        guard composer.isConvertible else { return }
        let text = composer.text
        let length = text.count
        guard length > Self.readingLengthLimit else { return }
        let whole = bestCandidate(reading: text, precedingText: precedingText)
        let headLength = length - Self.autoCommitKeepLength
        let head = bestCandidate(reading: String(text.prefix(headLength)), precedingText: precedingText)
        let rest = String(text.dropFirst(headLength))
        let tail = bestCandidate(reading: rest, precedingText: String(head.suffix(Self.precedingTextLength)))
        // 先頭の 1 位 P と残りの 1 位 Q をつないだものが全体の 1 位 T と一致したら P を確定する。
        // 一致しなくても上限を超えていれば P を確定する。確定の後の表示は求めた Q をそのまま使う
        if whole == head + tail || length > Self.readingHardLimit {
            commit(head)
            composer.removePrefix(headLength)
            knownBestInCall = (rest, tail)
        } else {
            knownBestInCall = (text, whole)
        }
    }

    // MARK: - 表示

    private func currentMarked() -> MarkedText? {
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
                } else if composer.isConvertible {
                    add(bestCandidate(reading: composer.text, precedingText: precedingText), .converted)
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
        return InputResult(handled: handled, committed: committedInCall, marked: currentMarked(), candidates: currentCandidates())
    }

    // MARK: - 変換

    /// 空の文字列と、U+FF00...U+FFFD の文字を含む候補を落とす。空になったら読みそのものを唯一の候補にする
    private func fetchCandidates(reading: String, precedingText: String) -> [String] {
        let candidates = conversion.candidates(reading: reading, precedingText: precedingText)
            .filter { !$0.isEmpty && !Self.containsForbiddenCharacter($0) }
        return candidates.isEmpty ? [reading] : candidates
    }

    private func bestCandidate(reading: String, precedingText: String) -> String {
        fetchCandidates(reading: reading, precedingText: precedingText)[0]
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
