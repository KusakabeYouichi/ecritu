import AppKit
import EcrituInput

/// キーの打鍵をどう扱うか
enum KeyAction: Equatable {
    /// InputSession へ渡す
    case session(KeyInput)
    /// 未確定を確定(commitAll)してから、キーをホストへ通す
    case commitAndPass
    /// 何もせずホストへ通す
    case pass
}

/// キーコード・文字・修飾の組から動きを決める。判定は純粋な関数で、AppKit に触るのは NSEvent から引数を取り出すところだけ
enum KeyEventTranslator {
    struct Modifiers: OptionSet, Equatable {
        let rawValue: Int
        static let shift = Modifiers(rawValue: 1 << 0)
        static let control = Modifiers(rawValue: 1 << 1)
        static let option = Modifiers(rawValue: 1 << 2)
        static let command = Modifiers(rawValue: 1 << 3)
    }

    /// 物理キーのキーコード(Carbon の kVK_*)
    enum KeyCode {
        static let returnKey: UInt16 = 36
        static let tab: UInt16 = 48
        static let space: UInt16 = 49
        static let delete: UInt16 = 51
        static let escape: UInt16 = 53
        static let keypadEnter: UInt16 = 76
        static let f6: UInt16 = 97
        static let f7: UInt16 = 98
        /// 英数キー
        static let alphanumeric: UInt16 = 102
        static let kana: UInt16 = 104
        static let left: UInt16 = 123
        static let right: UInt16 = 124
        static let down: UInt16 = 125
        static let up: UInt16 = 126
    }

    /// NSEvent から引数を取り出して translate へ渡す
    static func action(for event: NSEvent) -> KeyAction {
        let flags = event.modifierFlags
        var modifiers: Modifiers = []
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return translate(
            keyCode: event.keyCode,
            characters: event.characters ?? "",
            charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
            modifiers: modifiers
        )
    }

    /// characters は Shift・CapsLock を反映した文字。charactersIgnoringModifiers は ⌃ の組み合わせを見分けるのに使う
    static func translate(
        keyCode: UInt16,
        characters: String,
        charactersIgnoringModifiers: String,
        modifiers: Modifiers
    ) -> KeyAction {
        // 英数 / かな は見ない。モードは setValue が運ぶ
        if keyCode == KeyCode.alphanumeric || keyCode == KeyCode.kana {
            return .pass
        }
        if modifiers.contains(.command) || modifiers.contains(.option) {
            return .commitAndPass
        }
        if modifiers.contains(.control) {
            switch charactersIgnoringModifiers.lowercased() {
            case "j":
                return .session(.toHiragana)
            case "k":
                return .session(.toKatakana)
            default:
                return .commitAndPass
            }
        }

        let shift = modifiers.contains(.shift)
        switch keyCode {
        case KeyCode.f6:
            return .session(.toHiragana)
        case KeyCode.f7:
            return .session(.toKatakana)
        case KeyCode.left:
            return .session(.left(shift: shift))
        case KeyCode.right:
            return .session(.right(shift: shift))
        case KeyCode.up:
            return .session(.up)
        case KeyCode.down:
            return .session(.down)
        case KeyCode.returnKey, KeyCode.keypadEnter:
            return .session(.enter)
        case KeyCode.delete:
            return .session(.backspace)
        case KeyCode.escape:
            return .session(.escape)
        case KeyCode.tab:
            return .session(.tab)
        case KeyCode.space:
            return .session(.space)
        default:
            break
        }

        // 印字できる ASCII(U+0021...U+007E)だけをセッションへ。それ以外の文字は確定してから通す
        if characters.unicodeScalars.count == 1,
            let scalar = characters.unicodeScalars.first,
            (0x21...0x7E).contains(scalar.value) {
            return .session(.character(Character(scalar)))
        }
        return .commitAndPass
    }
}
