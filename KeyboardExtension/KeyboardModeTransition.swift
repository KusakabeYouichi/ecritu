import Foundation

enum LatinShiftState: Equatable {
    case off
    case on
    case locked
}

enum KanaCharacterMode: Equatable {
    case hiragana
    case katakana

    var toggleGuide: String {
        switch self {
        case .hiragana:
            return "カ"
        case .katakana:
            return "ひ"
        }
    }
}

struct KeyboardModeTransitionState: Equatable {
    var inputMode: KeyboardInputMode
    var diacriticMode: DiacriticMode
    var kanaCharacterMode: KanaCharacterMode
    var latinShiftState: LatinShiftState
    var lastLatinShiftTapAt: Date?
    var isKaomojiMode: Bool
    var spaceToastText: String?
    var spaceToastOpacity: Double
}

enum KeyboardModeTransition {
    static func switchInputMode(
        _ state: KeyboardModeTransitionState,
        to mode: KeyboardInputMode
    ) -> KeyboardModeTransitionState {
        var next = state
        next.inputMode = mode
        next.diacriticMode = .none
        next.latinShiftState = .off
        next.lastLatinShiftTapAt = nil

        if mode != .emoji {
            next.isKaomojiMode = false
        }

        if mode != .kana {
            next.spaceToastText = nil
            next.spaceToastOpacity = 0
        }

        return next
    }

    static func enterEmojiMode(from state: KeyboardModeTransitionState) -> KeyboardModeTransitionState {
        var next = switchInputMode(state, to: .emoji)
        next.isKaomojiMode = false
        return next
    }

    static func enterKaomojiMode(from state: KeyboardModeTransitionState) -> KeyboardModeTransitionState {
        var next = switchInputMode(state, to: .emoji)
        next.isKaomojiMode = true
        return next
    }

    static func selectModifier(
        _ output: String,
        state: KeyboardModeTransitionState
    ) -> KeyboardModeTransitionState {
        var next = state

        switch output {
        case "123":
            return switchInputMode(next, to: .number)
        case "カ", "ひ":
            guard next.inputMode == .kana else { return next }
            next.kanaCharacterMode = next.kanaCharacterMode == .hiragana ? .katakana : .hiragana
        case "ABC", "abc":
            return switchInputMode(next, to: .latin)
        case "あい", "あいう", "かな":
            return switchInputMode(next, to: .kana)
        case "゛":
            guard next.inputMode == .kana else { return next }
            next.diacriticMode = next.diacriticMode == .dakuten ? .none : .dakuten
        case "゜":
            guard next.inputMode == .kana else { return next }
            next.diacriticMode = next.diacriticMode == .handakuten ? .none : .handakuten
        case "小":
            guard next.inputMode == .kana else { return next }
            next.diacriticMode = next.diacriticMode == .smallKana ? .none : .smallKana
        default:
            break
        }

        return next
    }

    static func finishCommit(
        _ committedText: String,
        state: KeyboardModeTransitionState
    ) -> KeyboardModeTransitionState {
        var next = state

        if shouldApplyLatinShift(to: committedText, state: next),
           next.latinShiftState == .on {
            next.latinShiftState = .off
        }

        if next.inputMode == .kana,
           next.diacriticMode != .none {
            next.diacriticMode = .none
        }

        return next
    }

    static func handleLatinShiftTap(
        _ state: KeyboardModeTransitionState,
        now: Date,
        doubleTapThreshold: TimeInterval
    ) -> KeyboardModeTransitionState {
        guard state.inputMode == .latin else {
            return state
        }

        var next = state

        if let lastTapAt = next.lastLatinShiftTapAt,
           now.timeIntervalSince(lastTapAt) <= doubleTapThreshold,
           next.latinShiftState == .on {
            next.latinShiftState = .locked
            next.lastLatinShiftTapAt = nil
            return next
        }

        switch next.latinShiftState {
        case .off:
            next.latinShiftState = .on
            next.lastLatinShiftTapAt = now
        case .on:
            next.latinShiftState = .off
            next.lastLatinShiftTapAt = now
        case .locked:
            next.latinShiftState = .off
            next.lastLatinShiftTapAt = nil
        }

        return next
    }

    static func handleLatinShiftLongPress(
        _ state: KeyboardModeTransitionState
    ) -> KeyboardModeTransitionState {
        guard state.inputMode == .latin else {
            return state
        }

        var next = state
        next.latinShiftState = .locked
        next.lastLatinShiftTapAt = nil
        return next
    }

    private static func shouldApplyLatinShift(
        to text: String,
        state: KeyboardModeTransitionState
    ) -> Bool {
        guard state.inputMode == .latin,
              state.latinShiftState != .off,
              isLatinAlphabetKey(text) else {
            return false
        }

        return true
    }

    private static func isLatinAlphabetKey(_ value: String) -> Bool {
        guard value.count == 1,
              let scalar = value.unicodeScalars.first else {
            return false
        }

        return CharacterSet.letters.contains(scalar)
    }
}
