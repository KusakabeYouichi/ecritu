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

    /// 裏で変換を求める列。打鍵は待たせず、求め終わったら表示を差し替える
    private static let liveConversionQueue = DispatchQueue(
        label: "jp.or.pleiades.merope.inputmethod.ecritu.live-conversion", qos: .userInitiated
    )
    /// 反映のたびに進む番号。裏の仕事は、自分の番号が古くなっていたら何もしない(速く打ったときに古い変換をためない)
    private let liveGeneration = GenerationCounter()

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

    // MARK: - 入力メニュー

    /// 入力メニューに足す項目。IMK は項目の action をこのコントローラーへ送る(sender は項目を入れた辞書)ので target は置かない
    override func menu() -> NSMenu! {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "設定…", action: #selector(showPreferences(_:)), keyEquivalent: ""))
        return menu
    }

    /// 入力メニューの [設定…] と、IMK の環境設定の呼び出しの両方がここに来る
    override func showPreferences(_ sender: Any!) {
        SettingsWindowController.shared.show()
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
        scheduleLiveConversion(result.pendingConversion)
    }

    /// 表示に要る変換がまだ求まっていなければ、裏で求めてから表示を作り直す。
    /// 反映のたびに番号を進める。列で順番を待っている間に別の反映(次の打鍵など)があった仕事は、始めずに捨てる
    /// (速く打ったときに古い変換をためない)。始めた仕事の結果は捨てない: 読みがその後に伸びていても、
    /// 自動確定の判定には使える(使えるかどうかは InputSession.refresh が決める)
    private func scheduleLiveConversion(_ request: LiveConversionRequest?) {
        let generation = liveGeneration.advance()
        guard let request else {
            return
        }
        // 裏のスレッドではコントローラーを強くつかまない(裏で最後の参照になると、ウインドウがメイン以外で解放される)
        Self.liveConversionQueue.async { [liveGeneration, weak self] in
            guard liveGeneration.isCurrent(generation) else {
                return
            }
            InputSession.prewarm(request, conversion: conversionService)
            DispatchQueue.main.async {
                guard let self, let client = self.client(),
                      let result = self.session.refresh(delivered: request) else {
                    return
                }
                self.apply(result, to: client)
            }
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

/// スレッドをまたいで読める番号。メインスレッドが進め、裏の列が「まだ最新か」を見る
private final class GenerationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func advance() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }

    func isCurrent(_ generation: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value == generation
    }
}
