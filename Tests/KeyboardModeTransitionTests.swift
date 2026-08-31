import XCTest

final class KeyboardModeTransitionTests: XCTestCase {
    func testSwitchInputModeResetsTransientState() {
        let state = makeState(
            inputMode: .kana,
            diacriticMode: .dakuten,
            latinShiftState: .on,
            lastLatinShiftTapAt: Date(timeIntervalSinceReferenceDate: 10),
            emojiInputSubmode: .kaomoji,
            spaceToastText: "écritu",
            spaceToastOpacity: 1
        )

        let next = KeyboardModeTransition.switchInputMode(state, to: .number)

        XCTAssertEqual(next.inputMode, .number)
        XCTAssertEqual(next.diacriticMode, .none)
        XCTAssertEqual(next.latinShiftState, .off)
        XCTAssertNil(next.lastLatinShiftTapAt)
        XCTAssertEqual(next.emojiInputSubmode, .emoji)
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
        XCTAssertEqual(kaomoji.emojiInputSubmode, .kaomoji)

        let symbols = KeyboardModeTransition.enterSymbolsMode(from: kaomoji)
        XCTAssertEqual(symbols.inputMode, .emoji)
        XCTAssertEqual(symbols.emojiInputSubmode, .symbols)

        let emoji = KeyboardModeTransition.enterEmojiMode(from: symbols)
        XCTAssertEqual(emoji.inputMode, .emoji)
        XCTAssertEqual(emoji.emojiInputSubmode, .emoji)
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

    func testYaKeyRemapMatchesExpectedSymbolsPerDirectionProfile() {
        let ecrituYaKey = FlickKanaLayout.fiveByTwoRows[1][2]
        XCTAssertEqual(ecrituYaKey.center, "や")
        XCTAssertEqual(ecrituYaKey.up, "『")
        XCTAssertEqual(ecrituYaKey.right, "ゆ")
        XCTAssertEqual(ecrituYaKey.left, "』")
        XCTAssertEqual(ecrituYaKey.down, "よ")

        let appleYaKey = ecrituYaKey.remapped(for: .apple)
        XCTAssertEqual(appleYaKey.center, "や")
        XCTAssertEqual(appleYaKey.left, "『")
        XCTAssertEqual(appleYaKey.up, "ゆ")
        XCTAssertEqual(appleYaKey.right, "』")
        XCTAssertEqual(appleYaKey.down, "よ")
    }

    func testNumberOneDirectionalArrowsAreSameAcrossProfiles() {
        let appleOne = FlickKanaLayout.numberRows(for: .apple, layoutMode: .telephone)[0][0]
        let ecrituOne = FlickKanaLayout.numberRows(for: .ecritu, layoutMode: .telephone)[0][0]

        XCTAssertEqual(appleOne.up, ecrituOne.up)
        XCTAssertEqual(appleOne.right, ecrituOne.right)
        XCTAssertEqual(appleOne.left, ecrituOne.left)
        XCTAssertEqual(appleOne.down, ecrituOne.down)
    }

    func testDownGuideOrderUsesProfileSpecificDirectionOrderForStandardKeys() {
        let ecrituYa = FlickKanaLayout.kanaYaSet
        let appleYa = ecrituYa.remapped(for: .apple)

        XCTAssertEqual(
            ecrituYa.orderedDirectionalGuideTexts(for: .ecritu),
            ["『", "ゆ", "』", "よ"]
        )
        XCTAssertEqual(
            appleYa.orderedDirectionalGuideTexts(for: .apple),
            ["『", "ゆ", "』", "よ"]
        )
    }

    func testDownGuideOrderKeepsFixedOrderForExceptionKeys() {
        let appleOne = FlickKanaLayout.numberRows(for: .apple, layoutMode: .telephone)[0][0]
        let ecrituOne = FlickKanaLayout.numberRows(for: .ecritu, layoutMode: .telephone)[0][0]

        XCTAssertEqual(
            appleOne.orderedDirectionalGuideTexts(for: .apple),
            ["←", "↑", "→", "↓"]
        )
        XCTAssertEqual(
            ecrituOne.orderedDirectionalGuideTexts(for: .ecritu),
            ["←", "↑", "→", "↓"]
        )

        let dakutenKey = FlickKanaSet(
            label: "小",
            center: "小",
            up: "゛",
            right: "…",
            down: "゜",
            left: "カ",
            usesProfileDependentGuideOrder: false
        )

        XCTAssertEqual(
            dakutenKey.orderedDirectionalGuideTexts(for: .apple),
            ["カ", "゛", "…", "゜"]
        )
        XCTAssertEqual(
            dakutenKey.orderedDirectionalGuideTexts(for: .ecritu),
            ["カ", "゛", "…", "゜"]
        )
    }

    func testYaSecondaryBracketFlickOutputMap() {
        XCTAssertEqual(
            FlickKanaLayout.secondaryBracketFlickOutput(
                forPrimaryOutput: "『",
                verticalDirection: .haut
            ),
            "("
        )
        XCTAssertEqual(
            FlickKanaLayout.secondaryBracketFlickOutput(
                forPrimaryOutput: "『",
                verticalDirection: .bas
            ),
            "「"
        )
        XCTAssertEqual(
            FlickKanaLayout.secondaryBracketFlickOutput(
                forPrimaryOutput: "』",
                verticalDirection: .haut
            ),
            ")"
        )
        XCTAssertEqual(
            FlickKanaLayout.secondaryBracketFlickOutput(
                forPrimaryOutput: "』",
                verticalDirection: .bas
            ),
            "」"
        )
        XCTAssertNil(
            FlickKanaLayout.secondaryBracketFlickOutput(
                forPrimaryOutput: "ゆ",
                verticalDirection: .haut
            )
        )
    }

    func testWaSecondaryFlickOutputsForHistoricalKana() {
        // 案C(2026-08-31): を→下=ゐ、ー→下=ゑ、ん→下=〜
        XCTAssertEqual(
            FlickKanaLayout.secondaryBracketFlickOutput(forPrimaryOutput: "を", verticalDirection: .bas),
            "ゐ"
        )
        XCTAssertEqual(
            FlickKanaLayout.secondaryBracketFlickOutput(forPrimaryOutput: "ー", verticalDirection: .bas),
            "ゑ"
        )
        XCTAssertEqual(
            FlickKanaLayout.secondaryBracketFlickOutput(forPrimaryOutput: "ん", verticalDirection: .bas),
            "〜"
        )
        // 上方向には割り当てなし
        XCTAssertNil(FlickKanaLayout.secondaryBracketFlickOutput(forPrimaryOutput: "を", verticalDirection: .haut))
        XCTAssertNil(FlickKanaLayout.secondaryBracketFlickOutput(forPrimaryOutput: "ー", verticalDirection: .haut))
    }

    func testWaKeyAssignmentPerDirectionProfile() {
        // écritu方向: 母音方向(上=い段ゐ、下=お段を)、ー/んは1段のまま
        let ecritu = FlickKanaLayout.waSet(for: .none, profile: .ecritu)
        XCTAssertEqual(ecritu.up, "ゐ")
        XCTAssertEqual(ecritu.down, "を")
        XCTAssertEqual(ecritu.left, "ー")
        XCTAssertEqual(ecritu.right, "ん")
        // Apple方向: 従来の1段割り当てを無傷で維持
        let apple = FlickKanaLayout.waSet(for: .none, profile: .apple)
        XCTAssertEqual(apple.up, "ん")
        XCTAssertEqual(apple.down, "〜")
        XCTAssertEqual(apple.left, "を")
        XCTAssertEqual(apple.right, "ー")
        // remapped がわキーを二重変換しないこと(profile非依存フラグ)
        XCTAssertEqual(ecritu.remapped(for: .apple), ecritu)
        // rows(5×2/3×3+わ)にも同じセットが載ること
        for layout in [KanaLayoutMode.fiveByTwo, .threeByThreePlusWa] {
            for profile in [FlickDirectionProfile.ecritu, .apple] {
                let rows = FlickKanaLayout.rows(for: .none, layoutMode: layout, profile: profile)
                let wa = rows.flatMap { $0 }.first { $0.label == "わ" }
                XCTAssertEqual(wa, FlickKanaLayout.waSet(for: .none, profile: profile), "layout=\(layout) profile=\(profile)")
            }
        }
    }

    func testYaKeyAssignmentMatchesBetweenFiveByTwoAndThreeByThreePlusWa() {
        let fiveByTwoYa = FlickKanaLayout.fiveByTwoRows[1][2]
        let threeByThreeYa = FlickKanaLayout.threeByThreePlusWaRows[2][1]

        XCTAssertEqual(fiveByTwoYa.center, "や")
        XCTAssertEqual(threeByThreeYa.center, "や")
        XCTAssertEqual(fiveByTwoYa, threeByThreeYa)
        XCTAssertEqual(fiveByTwoYa.up, "『")
        XCTAssertEqual(fiveByTwoYa.right, "ゆ")
        XCTAssertEqual(fiveByTwoYa.left, "』")
        XCTAssertEqual(fiveByTwoYa.down, "よ")
    }

    private func makeState(
        inputMode: KeyboardInputMode = .kana,
        diacriticMode: DiacriticMode = .none,
        kanaCharacterMode: KanaCharacterMode = .hiragana,
        latinShiftState: LatinShiftState = .off,
        lastLatinShiftTapAt: Date? = nil,
        emojiInputSubmode: EmojiInputSubmode = .emoji,
        spaceToastText: String? = nil,
        spaceToastOpacity: Double = 0
    ) -> KeyboardModeTransitionState {
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
    // 基本記号の並びは 共通記号(りんごマーク・矢印・和文括弧) → 図形 → ASCII/JIS の順。
    // 使用頻度の高いものを手前に置くというユーザー指定(2600)。以前は ASCII が先頭で、
    // 共通記号は各並び(ASCII/EBCDIC/ANSI)の配列末尾に埋め込まれていた。
    func testBasicSymbolSectionsAreOrderedCommonShapesThenPunctuation() {
        let common = KeyboardRootView.SymbolCategory.basicSymbolsCommon
        let shapes = KeyboardRootView.SymbolCategory.basicSymbolsExtras

        let orders: [KeyboardRootView.BasicSymbolOrder] = [.ascii, .ebcdic, .ansi]
        for order in orders {
            let symbols = KeyboardRootView.SymbolCategory.basic.symbols(
                basicOrder: order,
                temperatureUnit: .celsius
            )
            XCTAssertEqual(
                Array(symbols.prefix(common.count)),
                common,
                "共通記号が先頭でない order=\(order)"
            )
            XCTAssertEqual(
                Array(symbols.dropFirst(common.count).prefix(shapes.count)),
                shapes,
                "図形が2番目でない order=\(order)"
            )
            let punctuation = Array(symbols.dropFirst(common.count + shapes.count))
            XCTAssertFalse(punctuation.isEmpty, "ASCII/JIS が空 order=\(order)")
            // 約物セクションに共通記号や図形が混ざっていないこと
            XCTAssertTrue(
                punctuation.allSatisfy { !common.contains($0) && !shapes.contains($0) },
                "約物セクションに他の群が混ざっている order=\(order) punctuation=\(punctuation)"
            )
        }
    }
}
