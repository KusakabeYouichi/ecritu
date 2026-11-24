import EcrituInput
import XCTest

/// キーコード・文字・修飾の組 → 動き(設計 B 7 章 T1〜T10、8 章 N7)
final class KeyEventTranslatorTests: XCTestCase {
    private func action(
        _ keyCode: UInt16,
        _ characters: String,
        ignoringModifiers: String? = nil,
        _ modifiers: KeyEventTranslator.Modifiers = []
    ) -> KeyAction {
        KeyEventTranslator.translate(
            keyCode: keyCode,
            characters: characters,
            charactersIgnoringModifiers: ignoringModifiers ?? characters,
            modifiers: modifiers
        )
    }

    // T1
    func testLowercaseLetterGoesToSessionAsCharacter() {
        XCTAssertEqual(action(0, "a"), .session(.character("a")))
    }

    // T2
    func testShiftedLetterGoesToSessionAsUppercaseCharacter() {
        XCTAssertEqual(action(0, "A", ignoringModifiers: "a", .shift), .session(.character("A")))
    }

    // T3
    func testCommandOrOptionCommitsThenPasses() {
        XCTAssertEqual(action(0, "a", .command), .commitAndPass)
        XCTAssertEqual(action(0, "\u{E5}", ignoringModifiers: "a", .option), .commitAndPass)
    }

    // T4
    func testControlJAndControlKSwitchDisplayToHiraganaAndKatakana() {
        XCTAssertEqual(action(38, "\n", ignoringModifiers: "j", .control), .session(.toHiragana))
        XCTAssertEqual(action(40, "\u{0B}", ignoringModifiers: "k", .control), .session(.toKatakana))
    }

    // T5
    func testOtherControlCombinationCommitsThenPasses() {
        XCTAssertEqual(action(0, "\u{01}", ignoringModifiers: "a", .control), .commitAndPass)
    }

    // T6
    func testF6AndF7SwitchDisplayToHiraganaAndKatakana() {
        XCTAssertEqual(action(97, "\u{F709}"), .session(.toHiragana))
        XCTAssertEqual(action(98, "\u{F70A}"), .session(.toKatakana))
    }

    // T7
    func testArrowsGoToSessionWithShiftState() {
        XCTAssertEqual(action(123, "\u{F702}"), .session(.left(shift: false)))
        XCTAssertEqual(action(123, "\u{F702}", .shift), .session(.left(shift: true)))
        XCTAssertEqual(action(124, "\u{F703}"), .session(.right(shift: false)))
        XCTAssertEqual(action(124, "\u{F703}", .shift), .session(.right(shift: true)))
        XCTAssertEqual(action(126, "\u{F700}"), .session(.up))
        XCTAssertEqual(action(125, "\u{F701}"), .session(.down))
    }

    // T8
    func testEditingKeysGoToSession() {
        XCTAssertEqual(action(36, "\r"), .session(.enter))
        XCTAssertEqual(action(76, "\u{03}"), .session(.enter))
        XCTAssertEqual(action(51, "\u{7F}"), .session(.backspace))
        XCTAssertEqual(action(53, "\u{1B}"), .session(.escape))
        XCTAssertEqual(action(48, "\t"), .session(.tab))
        XCTAssertEqual(action(49, " "), .session(.space))
        XCTAssertEqual(action(49, " ", .shift), .session(.space))
    }

    // T9
    func testNonASCIICharactersCommitThenPass() {
        XCTAssertEqual(action(93, "\u{A5}"), .commitAndPass)
        XCTAssertEqual(action(0, "\u{3042}"), .commitAndPass)
    }

    // T10
    func testAlphanumericAndKanaKeysPassWithoutTouchingSession() {
        XCTAssertEqual(action(102, ""), .pass)
        XCTAssertEqual(action(104, ""), .pass)
    }
}
