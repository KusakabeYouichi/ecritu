import CryptoKit
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

        let appleYaKey = ecrituYaKey.remapped(for: .littlebear)
        XCTAssertEqual(appleYaKey.center, "や")
        XCTAssertEqual(appleYaKey.left, "『")
        XCTAssertEqual(appleYaKey.up, "ゆ")
        XCTAssertEqual(appleYaKey.right, "』")
        XCTAssertEqual(appleYaKey.down, "よ")
    }

    func testNumberOneDirectionalArrowsAreSameAcrossProfiles() {
        let appleOne = FlickKanaLayout.numberRows(for: .littlebear, layoutMode: .telephone)[0][0]
        let ecrituOne = FlickKanaLayout.numberRows(for: .ecritu, layoutMode: .telephone)[0][0]

        XCTAssertEqual(appleOne.up, ecrituOne.up)
        XCTAssertEqual(appleOne.right, ecrituOne.right)
        XCTAssertEqual(appleOne.left, ecrituOne.left)
        XCTAssertEqual(appleOne.down, ecrituOne.down)
    }

    func testDownGuideOrderUsesProfileSpecificDirectionOrderForStandardKeys() {
        let ecrituYa = FlickKanaLayout.kanaYaSet
        let appleYa = ecrituYa.remapped(for: .littlebear)

        XCTAssertEqual(
            ecrituYa.orderedDirectionalGuideTexts(for: .ecritu),
            ["『", "ゆ", "』", "よ"]
        )
        XCTAssertEqual(
            appleYa.orderedDirectionalGuideTexts(for: .littlebear),
            ["『", "ゆ", "』", "よ"]
        )
    }

    func testDownGuideOrderKeepsFixedOrderForExceptionKeys() {
        let appleOne = FlickKanaLayout.numberRows(for: .littlebear, layoutMode: .telephone)[0][0]
        let ecrituOne = FlickKanaLayout.numberRows(for: .ecritu, layoutMode: .telephone)[0][0]

        XCTAssertEqual(
            appleOne.orderedDirectionalGuideTexts(for: .littlebear),
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
            dakutenKey.orderedDirectionalGuideTexts(for: .littlebear),
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

    func testContactCacheCipherRoundTrip() {
        let key = SymmetricKey(size: .bits256)
        let dictionary: [String: [String]] = [
            "やまだ": ["山田", "山田太郎"],
            "すずき": ["鈴木"]
        ]
        guard let sealed = ContactCacheCipher.seal(dictionary, key: key) else {
            XCTFail("seal failed")
            return
        }
        // 封緘データに平文が含まれない
        XCTAssertNil(String(data: sealed, encoding: .utf8))
        XCTAssertEqual(ContactCacheCipher.open(sealed, key: key), dictionary)
        // 別鍵では開かない
        XCTAssertNil(ContactCacheCipher.open(sealed, key: SymmetricKey(size: .bits256)))
        // 改竄検知(1バイト破壊)
        var tampered = sealed
        tampered[tampered.count - 1] ^= 0xFF
        XCTAssertNil(ContactCacheCipher.open(tampered, key: key))
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
        let apple = FlickKanaLayout.waSet(for: .none, profile: .littlebear)
        XCTAssertEqual(apple.up, "ん")
        XCTAssertEqual(apple.down, "〜")
        XCTAssertEqual(apple.left, "を")
        XCTAssertEqual(apple.right, "ー")
        // remapped がわキーを二重変換しないこと(profile非依存フラグ)
        XCTAssertEqual(ecritu.remapped(for: .littlebear), ecritu)
        // 5×2 の rows にも同じセットが載ること。3×3+わ は わキーを rows に含まず
        // waSet() 経由で別置きする構成なので、rows 側に わ が無いことだけ確認する
        // hanabi方向: 1998年の Newton OS 版 Hanabi(中央=わ/右=を/上=ん/左=ー)。下は空いていたので 〜 を置く
        let hanabi = FlickKanaLayout.waSet(for: .none, profile: .hanabi)
        XCTAssertEqual(hanabi.up, "ん")
        XCTAssertEqual(hanabi.right, "を")
        XCTAssertEqual(hanabi.down, "〜")
        XCTAssertEqual(hanabi.left, "ー")
        // 2段フリックは左右からしか起動しない。を→下=ゐ、ー→下=ゑ が出せること
        XCTAssertEqual(
            FlickKanaLayout.secondaryBracketFlickOutput(forPrimaryOutput: hanabi.right, verticalDirection: .bas), "ゐ")
        XCTAssertEqual(
            FlickKanaLayout.secondaryBracketFlickOutput(forPrimaryOutput: hanabi.left, verticalDirection: .bas), "ゑ")
        for profile in [FlickDirectionProfile.ecritu, .littlebear, .hanabi] {
            let rows = FlickKanaLayout.rows(for: .none, layoutMode: .fiveByTwo, profile: profile)
            let wa = rows.flatMap { $0 }.first { $0.label == "わ" }
            XCTAssertEqual(wa, FlickKanaLayout.waSet(for: .none, profile: profile), "profile=\(profile)")

            let threeByThree = FlickKanaLayout.rows(for: .none, layoutMode: .threeByThreePlusWa, profile: profile)
            XCTAssertNil(threeByThree.flatMap { $0 }.first { $0.label == "わ" })
        }
    }

    // 永続値は画面上の名前(hanabi / littlebear / écritu)。旧値 apple / ecritu も読める(3036)
    func testFlickDirectionProfileReadsLegacyStoredValues() {
        XCTAssertEqual(FlickDirectionProfile.littlebear.rawValue, "littlebear")
        XCTAssertEqual(FlickDirectionProfile.hanabi.rawValue, "hanabi")
        XCTAssertEqual(FlickDirectionProfile.ecritu.rawValue, "écritu")
        XCTAssertEqual(FlickDirectionProfile(rawValue: "apple"), .littlebear)
        XCTAssertEqual(FlickDirectionProfile(rawValue: "ecritu"), .ecritu)
        XCTAssertEqual(FlickDirectionProfile(rawValue: "écritu"), .ecritu)
        XCTAssertEqual(FlickDirectionProfile(rawValue: "littlebear"), .littlebear)
        XCTAssertNil(FlickDirectionProfile(rawValue: "style-i"))
    }

    // 3方式の母音配置(3010)。écritu式=上い/右う/左え/下お、littlebear式=左い/上う/右え/下お、
    // hanabi式=右い/下う/左え/上お。ガイド文字の並びも五十音順に見えること
    func testFlickDirectionProfilesPlaceVowelsAsDocumented() {
        let base = FlickKanaLayout.fiveByTwoRows[0][0]
        XCTAssertEqual(base.center, "あ")

        let ecritu = base.remapped(for: .ecritu)
        XCTAssertEqual([ecritu.up, ecritu.right, ecritu.left, ecritu.down], ["い", "う", "え", "お"])

        let apple = base.remapped(for: .littlebear)
        XCTAssertEqual([apple.left, apple.up, apple.right, apple.down], ["い", "う", "え", "お"])

        let hanabi = base.remapped(for: .hanabi)
        XCTAssertEqual([hanabi.right, hanabi.down, hanabi.left, hanabi.up], ["い", "う", "え", "お"])

        for profile in [FlickDirectionProfile.ecritu, .littlebear, .hanabi] {
            XCTAssertEqual(
                base.remapped(for: profile).orderedDirectionalGuideTexts(for: profile),
                ["い", "う", "え", "お"],
                "profile=\(profile)"
            )
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

    // 顔文字パネルの分類カテゴリーの表示順(2026-09-02)。設定アプリの選択肢
    // (App/SettingsModels.swift KaomojiCategoryChoice、別ターゲットなので直接参照不可)は
    // この並びを写している。導入時から設定側だけ辞書の反復順になっており食い違っていたので、
    // ここで並びを固定し、変えるときは設定側も同時に直す合図にする。
    func testKaomojiDisplayCategoryOrderIsStable() {
        XCTAssertEqual(
            KaomojiCatalog.displayCategoryOrder,
            ["rire", "kawaii", "timide", "panique", "decu", "triste", "colere", "surprise", "dodo",
             "coucou", "amour", "excite", "action", "bizarre", "heros", "special", "lignes"]
        )
        // 表示順に載っている分類は全て実データに存在すること(誤字で並びから落ちるのを防ぐ)
        let imported = Set(KaomojiCatalog.importedCategoryOrder)
        for name in KaomojiCatalog.displayCategoryOrder {
            XCTAssertTrue(imported.contains(name), "\(name) が importedEntriesByCategory に無い")
        }
        // 逆に、実データにあって表示順に載っていない分類が無いこと(新分類の追加漏れを検知)
        XCTAssertEqual(
            Set(KaomojiCatalog.displayCategoryOrder), imported,
            "表示順に載っていない分類: \(imported.subtracting(KaomojiCatalog.displayCategoryOrder))"
        )
    }

    // リットルは単位ドラムに収録され、接頭辞と組んで hL・cL・mL が作れること。
    func testLitreUnitIsAvailableWithPrefixes() {
        let litre = SIUnitCatalog.siNamed.first { $0.symbol == "L" }
        XCTAssertNotNil(litre, "単位ドラムにリットルが無い")
        XCTAssertEqual(litre?.reading, "リットル")

        // ワインで使う hL・cL・mL の接頭辞が揃っていること。
        for prefix in ["h", "c", "m"] {
            XCTAssertTrue(
                SIUnitCatalog.prefixes.contains { $0.symbol == prefix },
                "接頭辞 \(prefix) が無く \(prefix)L が作れない"
            )
        }
    }

    // 表示用グリフ(l / ℓ)への置換は大文字 L の単純置換で行うため、
    // 記号に大文字 L を含む単位はリットルただ1つでなければならない。
    // ここが破れると、新しく足した単位の L まで一緒に置換されて壊れる。
    func testCapitalLIsUsedOnlyByLitre() {
        let allUnits = SIUnitCatalog.siBase + SIUnitCatalog.siDerived + SIUnitCatalog.siNamed
        let withCapitalL = allUnits.filter { $0.symbol.contains("L") }
        XCTAssertEqual(
            withCapitalL.map(\.symbol), ["L"],
            "大文字 L を含む単位がリットル以外にある。単純置換が壊れる: \(withCapitalL.map(\.symbol))"
        )

        // 接頭辞側にも大文字 L があってはならない(prefix + symbol を一括置換するため)。
        XCTAssertTrue(
            SIUnitCatalog.prefixes.allSatisfy { !$0.symbol.contains("L") },
            "接頭辞に大文字 L がある"
        )
    }
}

// 個体の解放検査(3107): 実機で KeyboardViewController が閉じたあとも 22 体、最長 14 時間 retain=5 で残っていた
// (2026-09-19 のログ)。表示→非表示→参照を捨てる の後に deinit するかを Mac で直接見る。
// 解放されなければプロセス内(écritu 側)に掴んでいるものがある
final class KeyboardViewControllerLifecycleTests: XCTestCase {
    // 診断ログの追記はメインと候補生成キューの両方から来る(初回変換の区間計測 e93b85ae)。
    // バッファーの切り詰め(320 行超)を同時に走らせると removeSubrange が範囲外で SIGTRAP
    // (実機 3106/3110 で 2 件、数時間放置→数文字打つと落ちる)。ロック下でなければここで落ちる。
    @MainActor
    func testDiagnosticsLogAppendIsSafeAcrossThreads() throws {
        let controller = KeyboardViewController()
        guard controller.sharedDefaults != nil else {
            throw XCTSkip("App Group の UserDefaults が無い環境")
        }
        let group = DispatchGroup()
        let queues = (0..<4).map { DispatchQueue(label: "diag-race-\($0)") }
        for (index, queue) in queues.enumerated() {
            group.enter()
            queue.async {
                for i in 0..<1_500 {
                    controller.appendKeyboardDiagnosticsLog("競合試験 q\(index) #\(i) " + String(repeating: "x", count: 40))
                }
                group.leave()
            }
        }
        for i in 0..<1_500 {
            controller.appendKeyboardDiagnosticsLog("競合試験 main #\(i)")
        }
        XCTAssertEqual(group.wait(timeout: .now() + 60), .success)
        controller.persistBufferedKeyboardDiagnostics()
        XCTAssertLessThanOrEqual(controller.diagnosticsState.diagnosticsLogTextLineCount, 320)
    }

    @MainActor
    func testControllerDeallocatesAfterDismissal() {
        weak var weakController: KeyboardViewController?
        weak var weakView: UIView?
        autoreleasepool {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
            let controller = KeyboardViewController()
            weakController = controller
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.loadViewIfNeeded()
            weakView = controller.view
            controller.beginAppearanceTransition(true, animated: false)
            controller.endAppearanceTransition()
            RunLoop.main.run(until: Date().addingTimeInterval(0.8))
            controller.beginAppearanceTransition(false, animated: false)
            controller.endAppearanceTransition()
            window.rootViewController = nil
            window.isHidden = true
        }
        // 遅延実行(下線消し 900ms、bootstrap 2s、取り付け監視 5s)が [weak self] なら待たずに解放されるはずだが、
        // 強参照で握っている場合に区別できるよう 6 秒まで待つ
        let deadline = Date().addingTimeInterval(6)
        while weakController != nil && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertNil(weakController, "KeyboardViewController が閉じたあとも解放されない(retain=\(weakController.map { CFGetRetainCount($0) } ?? 0))")
        if let v = weakView {
            print("LIFECYCLE view alive retain=\(CFGetRetainCount(v)) window=\(v.window != nil) superview=\(v.superview != nil) subviews=\(v.subviews.count) constraints=\(v.constraints.count) sublayers=\(v.layer.sublayers?.count ?? 0) nextResponder=\(String(describing: v.next))")
            for c in v.constraints { print("LIFECYCLE constraint \(c)") }
            for sv in v.subviews { print("LIFECYCLE subview \(type(of: sv)) retain=\(CFGetRetainCount(sv))") }
        }
        // root の UIInputView はテストホスト(アプリ)の入力系に掴まれて残る(_UIInputViewContent ×2、retain=4)。
        // 実機の個体ごとの残留と同じ現象かは実機のメモリーグラフで確かめる。ここでは観察だけにして落とさない
        if weakView != nil {
            print("LIFECYCLE note: root UIInputView はコントローラー解放後も残る(テストホスト側の保持の可能性)")
        }
    }
}
