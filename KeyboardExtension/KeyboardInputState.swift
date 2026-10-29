import Foundation
import Observation

// キーボードの入力の状態(面・濁点・かな/カナ・英字シフト・空白の案内・かなへ戻る印・2 度押し待ち)。
// 以前は KeyboardRootView の @State だったものを、配列(iPhone/iPad)をまたいで使えるように外へ出した。
// 持ち主はビュー木の根(@State で持つ)。寿命は以前の @State と同じで、makeRootView から渡したりはしない。
// クロージャーと描画設定(RenderConfiguration 由来の値)は持たない。要る処理は引数で受け取る。
// 遷移の規則そのものは KeyboardModeTransition(純関数)にあり、ここは適用と付随する印の出し入れだけを行なう。
@Observable
@MainActor
final class KeyboardInputState {
    var inputMode: KeyboardInputMode = .kana
    var diacriticMode: DiacriticMode = .none
    var kanaCharacterMode: KanaCharacterMode = .hiragana
    var latinShiftState: LatinShiftState = .off
    var lastLatinShiftTapAt: Date? = nil
    var emojiInputSubmode: EmojiInputSubmode = .emoji
    var spaceToastText: String? = nil
    var spaceToastOpacity: Double = 0
    // 絵文字・書式化数値などから 1 件確定したら、かなへ戻す印
    var returnToKanaAfterNextCommit: Bool = false
    // 『abc』キーの 2 度押し(英字の固定シフト)を待っているか
    var isAwaitingLatinModeSwitchSecondTap = false
    var pendingLatinModeSwitchSecondTapResetWorkItem: DispatchWorkItem?
    // 絵文字・記号の面で選んでいる分類
    var selectedEmojiCategory: KeyboardRootView.EmojiCategory = .people
    var selectedSymbolCategory: KeyboardRootView.SymbolCategory = .basic
    // 調査用ログ(記号面切替 2838): 直近のモード切替の引き金(左下キー タップ/フリック、修飾キー空タップ 等)。
    // 「触っていないのに記号面になった」の再現待ち。原因判明後に外す
    var inputModeChangeTrigger: String = "面内キー"

    init() {}

    var transitionState: KeyboardModeTransitionState {
        get {
            KeyboardModeTransitionState(
                inputMode: inputMode,
                diacriticMode: diacriticMode,
                kanaCharacterMode: kanaCharacterMode,
                latinShiftState: latinShiftState,
                lastLatinShiftTapAt: lastLatinShiftTapAt,
                emojiInputSubmode: emojiInputSubmode,
                spaceToastText: spaceToastText,
                spaceToastOpacity: spaceToastOpacity
            )
        }
        set {
            // MEMFORENSICS(時限計測 2782): 漢字ピッカー(部首→漢字一覧、SwiftUI LazyVGrid+明朝グリフ)の
            // 表示/退出の footprint 推移。絵文字パネルの 絵文字切替/絵文字退出 と同じ窓(1.2s と 5s)
            let enteringKanjiRadical = newValue.inputMode == .emoji && newValue.emojiInputSubmode == .kanjiRadical
            let wasKanjiRadical = inputMode == .emoji && emojiInputSubmode == .kanjiRadical
            if enteringKanjiRadical, !wasKanjiRadical {
                MemoryForensics.noteOperation("漢字ピッカー切替")
                MemoryForensics.noteSpikeWindow("漢字ピッカー切替")
                MemoryForensics.noteSpikeWindow("漢字ピッカー切替+5s", delaySeconds: 5.0)
            } else if wasKanjiRadical, !enteringKanjiRadical {
                MemoryForensics.noteSpikeWindow("漢字ピッカー退出", minDeltaMB: -1_000)
                MemoryForensics.noteSpikeWindow("漢字ピッカー退出+5s", delaySeconds: 5.0, minDeltaMB: -1_000)
            }
            inputMode = newValue.inputMode
            diacriticMode = newValue.diacriticMode
            kanaCharacterMode = newValue.kanaCharacterMode
            latinShiftState = newValue.latinShiftState
            lastLatinShiftTapAt = newValue.lastLatinShiftTapAt
            emojiInputSubmode = newValue.emojiInputSubmode
            spaceToastText = newValue.spaceToastText
            spaceToastOpacity = newValue.spaceToastOpacity
        }
    }

    func switchInputMode(_ mode: KeyboardInputMode) {
        if mode != .latin {
            cancelLatinModeSwitchSecondTapWindow()
        }

        if mode != .emoji, mode != .formattedNumber {
            returnToKanaAfterNextCommit = false
        }

        transitionState = KeyboardModeTransition.switchInputMode(
            transitionState,
            to: mode
        )
    }

    func switchToLatinMode(with shiftState: LatinShiftState) {
        var next = KeyboardModeTransition.switchInputMode(
            transitionState,
            to: .latin
        )

        next.latinShiftState = shiftState
        next.lastLatinShiftTapAt = nil
        transitionState = next
    }

    // 書式化数値へ入る。1 件確定したらかなへ戻す印を付ける
    func enterFormattedNumberMode() {
        transitionState = KeyboardModeTransition.enterFormattedNumberMode(from: transitionState)
        returnToKanaAfterNextCommit = true
    }

    func enterKanjiRadicalMode() {
        transitionState = KeyboardModeTransition.enterKanjiRadicalMode(
            from: transitionState
        )
    }

    func enterEmojiMode() {
        transitionState = KeyboardModeTransition.enterEmojiMode(
            from: transitionState
        )
    }

    func enterKaomojiMode() {
        transitionState = KeyboardModeTransition.enterKaomojiMode(
            from: transitionState
        )
    }

    func enterSymbolsMode() {
        transitionState = KeyboardModeTransition.enterSymbolsMode(
            from: transitionState
        )
    }

    // 書式化数値はバッファーも空にする必要があるので、ビューの enterFormattedNumberMode() から入る。ここでは何もしない
    func enterPanel(_ target: KeyboardPanelTarget) {
        switch target {
        case .symbols:
            enterSymbolsMode()
        case .emoji:
            enterEmojiMode()
        case .kaomoji:
            enterKaomojiMode()
        case .kanjiRadical:
            enterKanjiRadicalMode()
        case .formattedNumber:
            break
        }
    }

    // 左下キー(面の切り替え)のタップ/フリック。70ms の門番はタッチの事実なのでビューに残し、通ったあとをここで行なう。
    // タップ/右/上の割り当ては設定なので引数で受ける。書式化数値はこの経路からは選ばれない
    func selectModeSwitcherPanel(
        direction: FlickDirection,
        triggerLabel: String?,
        tapAction: KeyboardRootView.KanaModeSwitcherAction,
        rightAction: KeyboardRootView.KanaModeSwitcherAction,
        upAction: KeyboardRootView.KanaModeSwitcherAction
    ) {
        // 調査用ログ(記号面切替 2838): どの操作で面が変わったかを記録。原因判明後に外す
        #if DEBUG
        inputModeChangeTrigger = triggerLabel ?? "左下キー \(direction)"
        #endif
        guard let target = KeyboardPanelRouting.panelTarget(
            forModeSwitchDirection: direction,
            tapAction: tapAction,
            rightAction: rightAction,
            upAction: upAction
        ) else {
            return
        }
        enterPanel(target)
    }

    // 後置の修飾キーを未確定なしでタップしたとき、設定の面と分類を開く。1 件確定したらかなへ戻す。
    // 設定値は引数で受ける。顔文字の分類の選択は KaomojiPanelState(ビューが持つ)を受け取って書く
    func applyPostModifierEmptyTap(
        actionRawValue: String,
        emojiCategoryID: String,
        symbolCategoryID: String,
        kaomojiCategoryID: String,
        kaomojiPanel: KaomojiPanelState
    ) {
        // 調査用ログ(記号面切替 2838): 未確定なしで修飾キーをタップした経路。原因判明後に外す
        #if DEBUG
        inputModeChangeTrigger = "修飾キー空タップ(\(actionRawValue))"
        #endif
        switch actionRawValue {
        case "emoji":
            if let rawValue = Int(emojiCategoryID),
                let category = KeyboardRootView.EmojiCategory(rawValue: rawValue) {
                selectedEmojiCategory = category
            }
            enterEmojiMode()
        case "symbols":
            if let rawValue = Int(symbolCategoryID),
                let category = KeyboardRootView.SymbolCategory(rawValue: rawValue) {
                selectedSymbolCategory = category
            }
            enterSymbolsMode()
        default:
            kaomojiPanel.selectCategory(id: kaomojiCategoryID)
            enterKaomojiMode()
        }

        returnToKanaAfterNextCommit = true
    }

    func consumeReturnToKanaAfterNextCommitIfNeeded() {
        guard returnToKanaAfterNextCommit else {
            return
        }

        returnToKanaAfterNextCommit = false
        switchInputMode(.kana)
    }

    // 文字キーの確定。文字を出してから状態を進める(順序は以前のビューの commitText と同じ)。
    // シフト記号はシフトの切り替えだけで、文字は出さない
    func commitText(
        _ text: String,
        shiftDoubleTapThreshold: TimeInterval,
        onTextInput: (String) -> Void
    ) {
        guard !text.isEmpty else {
            return
        }

        if text == FlickKanaLayout.latinShiftKeyToken {
            handleLatinShiftTap(now: Date(), doubleTapThreshold: shiftDoubleTapThreshold)
            return
        }

        onTextInput(KeyboardModeTransition.committedOutput(text, state: transitionState))

        transitionState = KeyboardModeTransition.finishCommit(
            text,
            state: transitionState
        )

        consumeReturnToKanaAfterNextCommitIfNeeded()
    }

    func handleLatinShiftTap(now: Date, doubleTapThreshold: TimeInterval) {
        transitionState = KeyboardModeTransition.handleLatinShiftTap(
            transitionState,
            now: now,
            doubleTapThreshold: doubleTapThreshold
        )
    }

    // 絵文字・顔文字・記号の面からの確定。絵文字と顔文字はショートカットの履歴の先頭へ足す(3243)。
    // 顔文字のショートカット分類から選んだとき、記号面、それ以外の面からは足さない。
    // 顔文字の分類の選択はまだビューの状態なので、ショートカット分類かどうかを引数で受け取る
    func commitEmojiKaomojiSymbolText(
        _ text: String,
        isKaomojiShortcutCategory: Bool,
        onShortcutCandidateCommitted: (String) -> Void,
        onTextInput: (String) -> Void
    ) {
        if inputMode == .emoji {
            switch emojiInputSubmode {
            case .emoji:
                onShortcutCandidateCommitted(text)
            case .kaomoji:
                if !isKaomojiShortcutCategory {
                    onShortcutCandidateCommitted(text)
                }
            default:
                break
            }
        }
        onTextInput(text)
        consumeReturnToKanaAfterNextCommitIfNeeded()
    }

    // 部首ピッカーで字をタップしたときの確定。履歴には足さず、かなへ戻る
    func commitRadicalCharacter(_ character: String, onTextInput: (String) -> Void) {
        onTextInput(character)
        switchInputMode(.kana)
    }

    // 2 度押しの待ち時間(秒)は設定(latinModeSwitchDoubleTapThreshold)なので引数で受け取る
    func startLatinModeSwitchSecondTapWindow(threshold: TimeInterval) {
        cancelLatinModeSwitchSecondTapWindow()
        isAwaitingLatinModeSwitchSecondTap = true

        let safeThreshold = max(0.05, threshold)
        let workItem = DispatchWorkItem { [weak self] in
            self?.pendingLatinModeSwitchSecondTapResetWorkItem = nil
            self?.isAwaitingLatinModeSwitchSecondTap = false
        }

        pendingLatinModeSwitchSecondTapResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + safeThreshold, execute: workItem)
    }

    func cancelLatinModeSwitchSecondTapWindow() {
        pendingLatinModeSwitchSecondTapResetWorkItem?.cancel()
        pendingLatinModeSwitchSecondTapResetWorkItem = nil
        isAwaitingLatinModeSwitchSecondTap = false
    }
}

// 面の切り替えで開く面
enum KeyboardPanelTarget: Equatable {
    case symbols
    case emoji
    case kaomoji
    case kanjiRadical
    case formattedNumber
}

// コンパクト配列の左下キー(地球儀の位置)の行き先
enum KeyboardCompactSwitchKeyRoute: Equatable {
    case advanceKeyboard
    case switchPanel
    case ignore
}

// どのキー・どの方向でどの面を開くかの割り当て(純関数)。以前はビューの切り替え処理の中にあった
enum KeyboardPanelRouting {
    // 面選択のパレット(左下キーの長押し)のラベル。ラベルの一覧は KeyboardRootView.modePaletteLabels
    static func panelTarget(forPaletteLabel label: String) -> KeyboardPanelTarget? {
        switch label {
        case "記号":
            return .symbols
        case "絵文字":
            return .emoji
        case "顔文字":
            return .kaomoji
        case "単漢字":
            return .kanjiRadical
        case "書式化":
            return .formattedNumber
        default:
            return nil
        }
    }

    static func panelTarget(
        forModeSwitchDirection direction: FlickDirection,
        tapAction: KeyboardRootView.KanaModeSwitcherAction,
        rightAction: KeyboardRootView.KanaModeSwitcherAction,
        upAction: KeyboardRootView.KanaModeSwitcherAction
    ) -> KeyboardPanelTarget? {
        // 下フリックは部首ピッカー固定(タップ/右/上の3スロットは設定で割り当て可)
        if direction == .bas {
            return .kanjiRadical
        }

        let action: KeyboardRootView.KanaModeSwitcherAction

        switch direction {
        case .milieu:
            action = tapAction
        case .droite:
            action = rightAction
        case .haut:
            action = upAction
        default:
            return nil
        }

        switch action {
        case .emoji:
            return .emoji
        case .kaomoji:
            return .kaomoji
        case .symbols:
            return .symbols
        }
    }

    static func compactSwitchKeyRoute(direction: FlickDirection) -> KeyboardCompactSwitchKeyRoute {
        switch direction {
        case .milieu:
            return .advanceKeyboard
        // 下は通常の左下キーと同じく単漢字の面(案内「熙」)。以前は下を受けず、案内だけ出て何も起きなかった
        // (提出前監査 第3回)
        case .droite, .haut, .bas:
            return .switchPanel
        default:
            return .ignore
        }
    }
}
