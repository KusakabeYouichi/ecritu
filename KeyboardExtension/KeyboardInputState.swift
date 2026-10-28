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

    func consumeReturnToKanaAfterNextCommitIfNeeded() {
        guard returnToKanaAfterNextCommit else {
            return
        }

        returnToKanaAfterNextCommit = false
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
