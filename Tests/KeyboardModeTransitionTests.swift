import XCTest

final class KeyboardModeTransitionTests: XCTestCase {
    func testSwitchInputModeResetsTransientState() {
        let state = makeState(
            inputMode: .kana,
            diacriticMode: .dakuten,
            latinShiftState: .on,
            lastLatinShiftTapAt: Date(timeIntervalSinceReferenceDate: 10),
            isKaomojiMode: true,
            spaceToastText: "écritu",
            spaceToastOpacity: 1
        )

        let next = KeyboardModeTransition.switchInputMode(state, to: .number)

        XCTAssertEqual(next.inputMode, .number)
        XCTAssertEqual(next.diacriticMode, .none)
        XCTAssertEqual(next.latinShiftState, .off)
        XCTAssertNil(next.lastLatinShiftTapAt)
        XCTAssertFalse(next.isKaomojiMode)
        XCTAssertNil(next.spaceToastText)
        XCTAssertEqual(next.spaceToastOpacity, 0)
    }

    func testSelectModifierTogglesKanaSpecificModes() {
        let initial = makeState(inputMode: .kana)

        let dakutenOn = KeyboardModeTransition.selectModifier("゛", state: initial)
        XCTAssertEqual(dakutenOn.diacriticMode, .dakuten)

        let dakutenOff = KeyboardModeTransition.selectModifier("゛", state: dakutenOn)
        XCTAssertEqual(dakutenOff.diacriticMode, .none)

        let katakana = KeyboardModeTransition.selectModifier("カ", state: initial)
        XCTAssertEqual(katakana.kanaCharacterMode, .katakana)

        let hiragana = KeyboardModeTransition.selectModifier("ひ", state: katakana)
        XCTAssertEqual(hiragana.kanaCharacterMode, .hiragana)
    }

    func testSelectModifierModeSwitches() {
        let kana = makeState(inputMode: .kana)
        XCTAssertEqual(
            KeyboardModeTransition.selectModifier("123", state: kana).inputMode,
            .number
        )

        let number = makeState(inputMode: .number)
        XCTAssertEqual(
            KeyboardModeTransition.selectModifier("abc", state: number).inputMode,
            .latin
        )

        let latin = makeState(inputMode: .latin)
        XCTAssertEqual(
            KeyboardModeTransition.selectModifier("かな", state: latin).inputMode,
            .kana
        )
    }

    func testSelectModifierIgnoresKanaSpecificSelectionOutsideKanaMode() {
        let latin = makeState(inputMode: .latin, diacriticMode: .none, kanaCharacterMode: .hiragana)

        let afterDakuten = KeyboardModeTransition.selectModifier("゛", state: latin)
        XCTAssertEqual(afterDakuten.diacriticMode, .none)

        let afterKanaToggle = KeyboardModeTransition.selectModifier("カ", state: latin)
        XCTAssertEqual(afterKanaToggle.kanaCharacterMode, .hiragana)
    }

    func testEnterEmojiAndKaomojiModes() {
        let state = makeState(inputMode: .kana)

        let kaomoji = KeyboardModeTransition.enterKaomojiMode(from: state)
        XCTAssertEqual(kaomoji.inputMode, .emoji)
        XCTAssertTrue(kaomoji.isKaomojiMode)

        let emoji = KeyboardModeTransition.enterEmojiMode(from: kaomoji)
        XCTAssertEqual(emoji.inputMode, .emoji)
        XCTAssertFalse(emoji.isKaomojiMode)
    }

    func testFinishCommitConsumesOneShotStates() {
        let kanaState = makeState(inputMode: .kana, diacriticMode: .smallKana)
        let kanaNext = KeyboardModeTransition.finishCommit("ぁ", state: kanaState)
        XCTAssertEqual(kanaNext.diacriticMode, .none)

        let latinShiftOn = makeState(inputMode: .latin, latinShiftState: .on)
        let latinAfterLetter = KeyboardModeTransition.finishCommit("a", state: latinShiftOn)
        XCTAssertEqual(latinAfterLetter.latinShiftState, .off)

        let latinAfterDigit = KeyboardModeTransition.finishCommit("1", state: latinShiftOn)
        XCTAssertEqual(latinAfterDigit.latinShiftState, .on)

        let latinLocked = makeState(inputMode: .latin, latinShiftState: .locked)
        let latinLockedAfterLetter = KeyboardModeTransition.finishCommit("a", state: latinLocked)
        XCTAssertEqual(latinLockedAfterLetter.latinShiftState, .locked)
    }

    func testLatinShiftTapTransitionAndDoubleTapLock() {
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
        let latin = makeState(inputMode: .latin, latinShiftState: .off)

        let singleTap = KeyboardModeTransition.handleLatinShiftTap(
            latin,
            now: t0,
            doubleTapThreshold: 0.32
        )
        XCTAssertEqual(singleTap.latinShiftState, .on)
        XCTAssertEqual(singleTap.lastLatinShiftTapAt, t0)

        let doubleTap = KeyboardModeTransition.handleLatinShiftTap(
            singleTap,
            now: t0.addingTimeInterval(0.2),
            doubleTapThreshold: 0.32
        )
        XCTAssertEqual(doubleTap.latinShiftState, .locked)
        XCTAssertNil(doubleTap.lastLatinShiftTapAt)

        let tapWhenLocked = KeyboardModeTransition.handleLatinShiftTap(
            doubleTap,
            now: t0.addingTimeInterval(1.0),
            doubleTapThreshold: 0.32
        )
        XCTAssertEqual(tapWhenLocked.latinShiftState, .off)
        XCTAssertNil(tapWhenLocked.lastLatinShiftTapAt)
    }

    func testLatinShiftLongPressRequiresLatinMode() {
        let kanaState = makeState(inputMode: .kana, latinShiftState: .off)
        XCTAssertEqual(
            KeyboardModeTransition.handleLatinShiftLongPress(kanaState).latinShiftState,
            .off
        )

        let latinState = makeState(inputMode: .latin, latinShiftState: .off)
        let locked = KeyboardModeTransition.handleLatinShiftLongPress(latinState)
        XCTAssertEqual(locked.latinShiftState, .locked)
        XCTAssertNil(locked.lastLatinShiftTapAt)
    }

    func testPostfixModifierConvertsHiraganaCharacter() {
        let dakuten = FlickKanaLayout.postfixModifiedCharacter(from: "か", mode: .dakuten)
        XCTAssertEqual(dakuten, "が")

        let handakuten = FlickKanaLayout.postfixModifiedCharacter(from: "は", mode: .handakuten)
        XCTAssertEqual(handakuten, "ぱ")

        let smallKana = FlickKanaLayout.postfixModifiedCharacter(from: "つ", mode: .smallKana)
        XCTAssertEqual(smallKana, "っ")
    }

    func testPostfixModifierConvertsKatakanaCharacter() {
        let dakuten = FlickKanaLayout.postfixModifiedCharacter(from: "カ", mode: .dakuten)
        XCTAssertEqual(dakuten, "ガ")

        let handakuten = FlickKanaLayout.postfixModifiedCharacter(from: "ハ", mode: .handakuten)
        XCTAssertEqual(handakuten, "パ")

        let smallKana = FlickKanaLayout.postfixModifiedCharacter(from: "ツ", mode: .smallKana)
        XCTAssertEqual(smallKana, "ッ")
    }

    func testPostfixModifierReturnsNilWhenUnsupported() {
        XCTAssertNil(FlickKanaLayout.postfixModifiedCharacter(from: "ん", mode: .dakuten))
        XCTAssertNil(FlickKanaLayout.postfixModifiedCharacter(from: "A", mode: .smallKana))
        XCTAssertNil(FlickKanaLayout.postfixModifiedCharacter(from: "か", mode: .none))
    }

    func testPostModifierButtonStateClassificationByPreviousCharacter() {
        XCTAssertEqual(FlickKanaLayout.postModifierButtonState(contextBeforeInput: nil), .kaomoji)
        XCTAssertEqual(FlickKanaLayout.postModifierButtonState(contextBeforeInput: "あ"), .smallKana)
        XCTAssertEqual(FlickKanaLayout.postModifierButtonState(contextBeforeInput: "う"), .smallKana)
        XCTAssertEqual(FlickKanaLayout.postModifierButtonState(contextBeforeInput: "つ"), .smallKana)
        XCTAssertEqual(FlickKanaLayout.postModifierButtonState(contextBeforeInput: "ゃ"), .kaomoji)
        XCTAssertEqual(FlickKanaLayout.postModifierButtonState(contextBeforeInput: "ぁ"), .kaomoji)
        XCTAssertEqual(FlickKanaLayout.postModifierButtonState(contextBeforeInput: "ぅ"), .dakuten)
        XCTAssertEqual(FlickKanaLayout.postModifierButtonState(contextBeforeInput: "っ"), .dakuten)
        XCTAssertEqual(FlickKanaLayout.postModifierButtonState(contextBeforeInput: "か"), .dakuten)
        XCTAssertEqual(FlickKanaLayout.postModifierButtonState(contextBeforeInput: "さ"), .dakuten)
        XCTAssertEqual(FlickKanaLayout.postModifierButtonState(contextBeforeInput: "は"), .dakuten)
        XCTAssertEqual(FlickKanaLayout.postModifierButtonState(contextBeforeInput: "ば"), .handakuten)
        XCTAssertEqual(FlickKanaLayout.postModifierButtonState(contextBeforeInput: "な"), .kaomoji)
        XCTAssertEqual(FlickKanaLayout.postModifierButtonState(contextBeforeInput: "ん"), .kaomoji)
    }

    func testPostModifierButtonStateClassificationSupportsKatakana() {
        XCTAssertEqual(FlickKanaLayout.postModifierButtonState(contextBeforeInput: "ッ"), .dakuten)
        XCTAssertEqual(FlickKanaLayout.postModifierButtonState(contextBeforeInput: "ャ"), .kaomoji)
        XCTAssertEqual(FlickKanaLayout.postModifierButtonState(contextBeforeInput: "バ"), .handakuten)
        XCTAssertEqual(FlickKanaLayout.postModifierButtonState(contextBeforeInput: "ン"), .kaomoji)
    }

    func testPostfixModifierByButtonStateSupportsSecondTapProgression() {
        XCTAssertEqual(
            FlickKanaLayout.postfixModifiedCharacter(from: "う", for: .smallKana),
            "ぅ"
        )
        XCTAssertEqual(
            FlickKanaLayout.postfixModifiedCharacter(from: "ぅ", for: .dakuten),
            "ゔ"
        )
        XCTAssertEqual(
            FlickKanaLayout.postfixModifiedCharacter(from: "つ", for: .smallKana),
            "っ"
        )
        XCTAssertEqual(
            FlickKanaLayout.postfixModifiedCharacter(from: "っ", for: .dakuten),
            "づ"
        )
        XCTAssertEqual(
            FlickKanaLayout.postfixModifiedCharacter(from: "は", for: .dakuten),
            "ば"
        )
        XCTAssertEqual(
            FlickKanaLayout.postfixModifiedCharacter(from: "ば", for: .handakuten),
            "ぱ"
        )
    }

    func testPostfixModifierByButtonStateConvertsKatakana() {
        XCTAssertEqual(
            FlickKanaLayout.postfixModifiedCharacter(from: "ウ", for: .smallKana),
            "ゥ"
        )
        XCTAssertEqual(
            FlickKanaLayout.postfixModifiedCharacter(from: "ッ", for: .dakuten),
            "ヅ"
        )
        XCTAssertEqual(
            FlickKanaLayout.postfixModifiedCharacter(from: "バ", for: .handakuten),
            "パ"
        )
    }

    func testPostfixModifierByButtonStateReturnsNilForKaomoji() {
        XCTAssertNil(FlickKanaLayout.postfixModifiedCharacter(from: "な", for: .kaomoji))
    }

    func testYaKeyRemapFollowsProfileDirectionRule() {
        let yaKey = FlickKanaLayout.fiveByTwoRows[1][2]
        XCTAssertEqual(yaKey.center, "や")

        let appleYaKey = yaKey.remapped(for: .apple)

        XCTAssertEqual(appleYaKey.left, yaKey.up)
        XCTAssertEqual(appleYaKey.up, yaKey.right)
        XCTAssertEqual(appleYaKey.right, yaKey.left)
        XCTAssertEqual(appleYaKey.down, yaKey.down)
    }

    func testNumberOneDirectionalArrowsAreSameAcrossProfiles() {
        let appleOne = FlickKanaLayout.numberRows(for: .apple, layoutMode: .telephone)[0][0]
        let ecrituOne = FlickKanaLayout.numberRows(for: .ecritu, layoutMode: .telephone)[0][0]

        XCTAssertEqual(appleOne.up, ecrituOne.up)
        XCTAssertEqual(appleOne.right, ecrituOne.right)
        XCTAssertEqual(appleOne.left, ecrituOne.left)
        XCTAssertEqual(appleOne.down, ecrituOne.down)
    }

    func testYaKeyAssignmentMatchesBetweenFiveByTwoAndThreeByThreePlusWa() {
        let fiveByTwoYa = FlickKanaLayout.fiveByTwoRows[1][2]
        let threeByThreeYa = FlickKanaLayout.threeByThreePlusWaRows[2][1]

        XCTAssertEqual(fiveByTwoYa.center, "や")
        XCTAssertEqual(threeByThreeYa.center, "や")
        XCTAssertEqual(fiveByTwoYa, threeByThreeYa)
    }

    private func makeState(
        inputMode: KeyboardInputMode = .kana,
        diacriticMode: DiacriticMode = .none,
        kanaCharacterMode: KanaCharacterMode = .hiragana,
        latinShiftState: LatinShiftState = .off,
        lastLatinShiftTapAt: Date? = nil,
        isKaomojiMode: Bool = false,
        spaceToastText: String? = nil,
        spaceToastOpacity: Double = 0
    ) -> KeyboardModeTransitionState {
        KeyboardModeTransitionState(
            inputMode: inputMode,
            diacriticMode: diacriticMode,
            kanaCharacterMode: kanaCharacterMode,
            latinShiftState: latinShiftState,
            lastLatinShiftTapAt: lastLatinShiftTapAt,
            isKaomojiMode: isKaomojiMode,
            spaceToastText: spaceToastText,
            spaceToastOpacity: spaceToastOpacity
        )
    }
}
