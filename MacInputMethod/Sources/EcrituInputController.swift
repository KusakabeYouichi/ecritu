import AppKit
import EcrituInput
import InputMethodKit

/// 入力欄(クライアント)ごとのコントローラー。キーを InputSession へ渡し、結果をクライアントと候補ウインドウへ反映する
final class EcrituInputController: IMKInputController {
    /// 入力モードの値(Info.plist の tsInputModeListKey のキー)
    private enum InputModeID {
        static let japanese = "com.apple.inputmethod.Japanese"
        static let roman = "com.apple.inputmethod.Roman"
    }

    private lazy var session = InputSession(conversion: conversionService)
    private let candidateWindow = CandidateWindow()
    /// 直前の反映で未確定があったか(nil になったときに空の未確定で消すため)
    private var hasMarkedText = false

    override func recognizedEvents(_ sender: Any!) -> Int {
        let mask: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown]
        return Int(mask.rawValue)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, let client = sender as? IMKTextInput else {
            return false
        }
        switch event.type {
        case .leftMouseDown, .rightMouseDown:
            apply(session.commitAll(), to: client)
            return false
        case .keyDown:
            break
        default:
            return false
        }

        switch KeyEventTranslator.action(for: event) {
        case .session(let key):
            let result = session.handle(key)
            apply(result, to: client)
            return result.handled
        case .commitAndPass:
            apply(session.commitAll(), to: client)
            return false
        case .pass:
            return false
        }
    }

    override func setValue(_ value: Any!, forTag tag: Int, client sender: Any!) {
        guard let modeID = value as? String, let client = sender as? IMKTextInput else {
            return
        }
        switch modeID {
        case InputModeID.roman:
            apply(session.handle(.switchToLatin), to: client)
        case InputModeID.japanese:
            apply(session.handle(.switchToJapanese), to: client)
        default:
            break
        }
    }

    override func activateServer(_ sender: Any!) {
        session.contextLost()
    }

    override func deactivateServer(_ sender: Any!) {
        commitAndClose(sender)
    }

    override func commitComposition(_ sender: Any!) {
        commitAndClose(sender)
    }

    private func commitAndClose(_ sender: Any!) {
        if let client = sender as? IMKTextInput {
            apply(session.commitAll(), to: client)
        }
        candidateWindow.close()
    }

    // MARK: - 反映

    private func apply(_ result: InputResult, to client: IMKTextInput) {
        let noReplacement = NSRange(location: NSNotFound, length: 0)
        if !result.committed.isEmpty {
            client.insertText(result.committed, replacementRange: noReplacement)
        }
        if let marked = result.marked {
            let text = Self.attributedMarkedText(marked)
            client.setMarkedText(text, selectionRange: NSRange(location: text.length, length: 0), replacementRange: noReplacement)
            hasMarkedText = true
        } else if hasMarkedText {
            client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: noReplacement)
            hasMarkedText = false
        }

        if let candidates = result.candidates {
            var lineRect = NSRect.zero
            _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &lineRect)
            candidateWindow.show(candidates, below: lineRect)
        } else {
            candidateWindow.close()
        }
    }

    /// 区切りごとの下線: 選択中の対象は太い下線、ほかは細い下線
    private static func attributedMarkedText(_ marked: MarkedText) -> NSAttributedString {
        let text = NSMutableAttributedString()
        for (index, segment) in marked.segments.enumerated() {
            let underline: NSUnderlineStyle = segment.style == .target ? .thick : .single
            text.append(NSAttributedString(string: segment.text, attributes: [
                .underlineStyle: underline.rawValue,
                .markedClauseSegment: index,
            ]))
        }
        return text
    }
}
