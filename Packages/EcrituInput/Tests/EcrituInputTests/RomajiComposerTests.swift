import XCTest
@testable import EcrituInput

/// 設計 5 章「ローマ字」R1〜R25。期待値は (text, pending)
final class RomajiComposerTests: XCTestCase {
    private func compose(_ romaji: String) -> RomajiComposer {
        var composer = RomajiComposer()
        for character in romaji {
            composer.input(character)
        }
        return composer
    }

    private func assertComposes(_ romaji: String, text: String, pending: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        let composer = compose(romaji)
        XCTAssertEqual(composer.text, text, "text of \(romaji)", file: file, line: line)
        XCTAssertEqual(composer.pending, pending, "pending of \(romaji)", file: file, line: line)
    }

    func testR01KaBecomesKana() {
        assertComposes("ka", text: "か", pending: "")
    }

    func testR02LoneConsonantStaysPending() {
        assertComposes("k", text: "", pending: "k")
    }

    func testR03ContractedSound() {
        assertComposes("kya", text: "きゃ", pending: "")
    }

    func testR04HepburnAndKunreiBothWork() {
        let cases = [("shi", "し"), ("si", "し"), ("chi", "ち"), ("ti", "ち"), ("tsu", "つ"),
                     ("tu", "つ"), ("fu", "ふ"), ("hu", "ふ"), ("ji", "じ"), ("zi", "じ")]
        for (romaji, kana) in cases {
            assertComposes(romaji, text: kana, pending: "")
        }
    }

    func testR05DoubledConsonantBecomesSmallTsu() {
        assertComposes("kitte", text: "きって", pending: "")
    }

    func testR06TchBecomesSmallTsuAndCha() {
        assertComposes("matcha", text: "まっちゃ", pending: "")
    }

    func testR07NBeforeConsonantBecomesN() {
        assertComposes("kanji", text: "かんじ", pending: "")
    }

    func testR08TrailingNStaysPending() {
        assertComposes("kan", text: "か", pending: "n")
    }

    func testR09DoubleNBecomesN() {
        assertComposes("kann", text: "かん", pending: "")
    }

    func testR10ApostropheAfterNBecomesN() {
        assertComposes("kan'i", text: "かんい", pending: "")
    }

    func testR11NyaIsContractedSound() {
        assertComposes("kanya", text: "かにゃ", pending: "")
    }

    func testR12TripleNThenVowel() {
        assertComposes("konnnichiha", text: "こんにちは", pending: "")
    }

    func testR13DoubleNThenVowelConsumesBothN() {
        assertComposes("konnichiha", text: "こんいちは", pending: "")
    }

    func testR14SmallKanaWithXAndL() {
        let cases = [("xa", "ぁ"), ("la", "ぁ"), ("ltu", "っ"), ("xtu", "っ"), ("xya", "ゃ")]
        for (romaji, kana) in cases {
            assertComposes(romaji, text: kana, pending: "")
        }
    }

    func testR15LoanwordSounds() {
        let cases = [("va", "ゔぁ"), ("vu", "ゔ"), ("fa", "ふぁ"), ("thi", "てぃ"), ("dhi", "でぃ"),
                     ("wi", "うぃ"), ("we", "うぇ")]
        for (romaji, kana) in cases {
            assertComposes(romaji, text: kana, pending: "")
        }
    }

    func testR16ContractedSoundsInBothSystems() {
        let cases = [("sha", "しゃ"), ("sya", "しゃ"), ("cha", "ちゃ"), ("tya", "ちゃ"), ("ja", "じゃ"),
                     ("jya", "じゃ"), ("zya", "じゃ")]
        for (romaji, kana) in cases {
            assertComposes(romaji, text: kana, pending: "")
        }
    }

    func testR17VowelsWoAndNn() {
        let cases = [("a", "あ"), ("i", "い"), ("u", "う"), ("e", "え"), ("o", "お"), ("wo", "を"), ("nn", "ん")]
        for (romaji, kana) in cases {
            assertComposes(romaji, text: kana, pending: "")
        }
    }

    func testR18DeleteRemovesLastKanaCharacter() {
        var composer = compose("kya")
        composer.deleteBackward()
        XCTAssertEqual(composer.text, "き")
        XCTAssertEqual(composer.pending, "")
    }

    func testR19DeleteRemovesLastPendingLetter() {
        var composer = compose("ky")
        composer.deleteBackward()
        XCTAssertEqual(composer.text, "")
        XCTAssertEqual(composer.pending, "k")
    }

    func testR20UnmatchedLetterStaysLatin() {
        assertComposes("qaka", text: "qあか", pending: "")
    }

    func testR21UnmatchedPairMovesFirstLetterAsLatin() {
        assertComposes("kq", text: "kq", pending: "")
    }

    func testR22HyphenBecomesLongVowelMark() {
        assertComposes("ko-hi-", text: "こーひー", pending: "")
    }

    // R26: z に続けて h j k l で矢印(左・下・上・右)。読みにも打ちかけにも残らない
    func testR26ZThenHJKLEmitsArrowsOutsideTheReading() {
        // z に続けて . , / - は … ‥ ・ 〜
        let cases: [(String, String)] = [
            ("zh", "\u{2190}"), ("zj", "\u{2193}"), ("zk", "\u{2191}"), ("zl", "\u{2192}"),
            ("z.", "\u{2026}"), ("z,", "\u{2025}"), ("z/", "\u{30FB}"), ("z-", "\u{301C}"),
        ]
        for (keys, arrow) in cases {
            var composer = RomajiComposer()
            for character in keys {
                composer.input(character)
            }
            XCTAssertEqual(composer.takeEmittedSymbol(), arrow, keys)
            XCTAssertEqual(composer.text, "", keys)
            XCTAssertEqual(composer.pending, "", keys)
            XCTAssertNil(composer.takeEmittedSymbol(), "2 回めは返さない: \(keys)")
        }
    }

    // R27: z で始まるかなの綴りは今までどおり
    func testR27ZaRowStillComposesKana() {
        assertComposes("zazizuzezo", text: "ざじずぜぞ", pending: "")
        assertComposes("zya", text: "じゃ", pending: "")
    }

    func testR23HyphenAfterConsonantLeavesConsonantLatin() {
        assertComposes("kok-", text: "こkー", pending: "")
    }

    func testR24FlushTurnsOnlyLoneNIntoN() {
        var kan = compose("kan")
        kan.flush()
        XCTAssertEqual(kan.text, "かん")
        XCTAssertEqual(kan.pending, "")

        var kank = compose("kank")
        kank.flush()
        XCTAssertEqual(kank.text, "かん")
        XCTAssertEqual(kank.pending, "k")
    }

    func testR25TableOutputsOnlyHiraganaAndLongVowelMark() {
        for (key, kana) in RomajiComposer.table {
            for scalar in kana.unicodeScalars {
                let isHiragana = (0x3041...0x3096).contains(scalar.value)
                XCTAssertTrue(isHiragana || scalar.value == 0x30FC, "\(key) -> \(kana)")
            }
        }
    }
}
