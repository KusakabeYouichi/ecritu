import XCTest
@testable import EcrituInput

/// 設計 5 章「状態機械」S1〜S60
final class InputSessionTests: XCTestCase {
    private var fake: FakeConversion!
    private var session: InputSession!

    override func setUp() {
        super.setUp()
        fake = FakeConversion()
        session = InputSession(conversion: fake)
    }

    private func learned(_ reading: String, _ candidate: String) -> FakeConversion.Learned {
        FakeConversion.Learned(reading: reading, candidate: candidate)
    }

    /// S3 の状態: kanji Space
    @discardableResult
    private func selectKanji() -> InputResult {
        session.type("kanji")
        return session.handle(.space)
    }

    /// S7 の状態: kanji ⇧←
    @discardableResult
    private func shrinkKanji() -> InputResult {
        session.type("kanji")
        return session.handle(.left(shift: true))
    }

    func testS01MarkedTextFollowsEachKey() {
        let expected = ["k", "か", "かn", "缶j", "漢字"]
        for (character, display) in zip("kanji", expected) {
            let result = session.handle(.character(character))
            XCTAssertEqual(result.markedString, display)
            XCTAssertEqual(result.committed, "")
            XCTAssertTrue(result.handled)
            if display == "かn" {
                XCTAssertEqual(result.marked?.segments, [segment("か", .converted), segment("n", .raw)])
            }
        }
    }

    func testS02EnterCommitsBestWithoutLearning() {
        session.type("kanji")
        let result = session.handle(.enter)
        XCTAssertEqual(result.committed, "漢字")
        XCTAssertNil(result.marked)
        XCTAssertEqual(fake.learned, [])
    }

    func testS03SpaceSelectsSecondCandidate() {
        let result = selectKanji()
        XCTAssertEqual(result.marked?.segments, [segment("感じ", .target)])
        XCTAssertEqual(result.candidates, CandidateList(items: ["漢字", "感じ", "幹事"], selectedIndex: 1))
    }

    func testS04SpaceMovesToNextCandidateAndWraps() {
        selectKanji()
        XCTAssertEqual(session.handle(.space).candidates?.selectedIndex, 2)
        XCTAssertEqual(session.handle(.space).candidates?.selectedIndex, 0)
    }

    func testS05UpMovesToPreviousCandidateAndWraps() {
        selectKanji()
        XCTAssertEqual(session.handle(.up).candidates?.selectedIndex, 0)
        XCTAssertEqual(session.handle(.up).candidates?.selectedIndex, 2)
    }

    func testS06EnterInSelectionCommitsAndLearns() {
        selectKanji()
        let result = session.handle(.enter)
        XCTAssertEqual(result.committed, "感じ")
        XCTAssertEqual(fake.learned, [learned("かんじ", "感じ")])
        XCTAssertNil(result.marked)
    }

    func testS07ShiftLeftTargetsAllButLastCharacter() {
        let result = shrinkKanji()
        XCTAssertEqual(result.marked?.segments, [segment("缶", .target), segment("字", .converted)])
        XCTAssertEqual(result.candidates, CandidateList(items: ["缶", "感"], selectedIndex: 0))
        XCTAssertTrue(fake.calls.contains(FakeConversion.Call(reading: "じ", precedingText: "缶")))
    }

    func testS08EnterOnShrunkTargetLeavesRestComposing() {
        shrinkKanji()
        let first = session.handle(.enter)
        XCTAssertEqual(first.committed, "缶")
        XCTAssertEqual(fake.learned, [learned("かん", "缶")])
        XCTAssertEqual(first.markedString, "字")
        XCTAssertNil(first.candidates)

        let second = session.handle(.enter)
        XCTAssertEqual(second.committed, "字")
        XCTAssertEqual(fake.learned, [learned("かん", "缶")])
    }

    func testS09ShrinkStopsAtOneCharacter() {
        shrinkKanji()
        let once = session.handle(.left(shift: true))
        XCTAssertEqual(once.marked?.segments.first, segment("か", .target))
        XCTAssertEqual(once.candidates, CandidateList(items: ["か"], selectedIndex: 0))

        let twice = session.handle(.left(shift: true))
        XCTAssertEqual(twice.marked?.segments.first, segment("か", .target))
        XCTAssertEqual(twice.candidates, CandidateList(items: ["か"], selectedIndex: 0))
    }

    func testS10ExtendStopsAtWholeText() {
        shrinkKanji()
        let expected = CandidateList(items: ["漢字", "感じ", "幹事"], selectedIndex: 0)
        XCTAssertEqual(session.handle(.right(shift: true)).candidates, expected)
        let again = session.handle(.right(shift: true))
        XCTAssertEqual(again.candidates, expected)
        XCTAssertEqual(again.marked?.segments, [segment("漢字", .target)])
    }

    func testS11DigitCommitsAndPassesThrough() {
        session.type("kanji")
        let result = session.handle(.character("3"))
        XCTAssertEqual(result.committed, "漢字")
        XCTAssertFalse(result.handled)
        XCTAssertNil(result.marked)
    }

    func testS12DigitPassesAndBecomesPrecedingText() {
        let digit = session.handle(.character("3"))
        XCTAssertFalse(digit.handled)
        XCTAssertEqual(digit.committed, "")
        XCTAssertEqual(session.type("ko").markedString, "個")
    }

    func testS13CommaAndPeriodCommitWithJapanesePunctuation() {
        session.type("kanji")
        let comma = session.handle(.character(","))
        XCTAssertEqual(comma.committed, "漢字、")
        XCTAssertTrue(comma.handled)

        session.type("kanji")
        let period = session.handle(.character("."))
        XCTAssertEqual(period.committed, "漢字。")
        XCTAssertTrue(period.handled)
    }

    // S65: 空の状態で z に続けて h j k l → 矢印をそのまま確定。未確定は残らない
    func testS65ZThenHJKLCommitsArrowWhenEmpty() {
        let cases: [(Character, String)] = [("h", "\u{2190}"), ("j", "\u{2193}"), ("k", "\u{2191}"), ("l", "\u{2192}")]
        for (key, arrow) in cases {
            let first = session.handle(.character("z"))
            XCTAssertEqual(first.committed, "")
            XCTAssertEqual(first.marked?.segments.map(\.text).joined(), "z")
            let second = session.handle(.character(key))
            XCTAssertEqual(second.committed, arrow)
            XCTAssertTrue(second.handled)
            XCTAssertNil(second.marked)
        }
    }

    // S66: 入力中なら、表示中の文字列に続けて矢印を 1 つの結果で確定(対応のある記号と同じ。学習しない)
    func testS66ArrowAfterComposingCommitsDisplayedTextAndArrow() {
        session.type("kanjiz")
        let result = session.handle(.character("l"))
        XCTAssertEqual(result.committed, "漢字\u{2192}")
        XCTAssertTrue(result.handled)
        XCTAssertNil(result.marked)
        XCTAssertEqual(fake.learned, [])
    }

    // S68: z に続けて . , / - → … ‥ ・ 〜 をそのまま確定(句読点や ー にならない)
    func testS68ZThenPunctuationCommitsEllipsisAndOthers() {
        let cases: [(Character, String)] = [(".", "\u{2026}"), (",", "\u{2025}"), ("/", "\u{30FB}"), ("-", "\u{301C}")]
        for (key, symbol) in cases {
            session.handle(.character("z"))
            let result = session.handle(.character(key))
            XCTAssertEqual(result.committed, symbol, String(key))
            XCTAssertTrue(result.handled, String(key))
            XCTAssertNil(result.marked, String(key))
        }
    }

    // S69: 入力中の z. は、表示中の文字列に続けて … を確定する。z を挟まない . は今までどおり 。
    func testS69EllipsisAfterComposingAndPlainPeriodUnchanged() {
        session.type("kanjiz")
        let ellipsis = session.handle(.character("."))
        XCTAssertEqual(ellipsis.committed, "漢字\u{2026}")
        XCTAssertNil(ellipsis.marked)

        session.type("kanji")
        let period = session.handle(.character("."))
        XCTAssertEqual(period.committed, "漢字。")
    }

    // S67: 矢印の直後は空の状態に戻っていて、続きは新しい読みになる
    func testS67TypingContinuesAfterArrow() {
        session.type("zl")
        let result = session.type("ka")
        XCTAssertEqual(result.committed, "")
        XCTAssertEqual(result.marked?.segments.map(\.text).joined(), "か")
    }

    func testS14MappedSymbolsCommitWhenEmpty() {
        let cases: [(Character, String)] = [(",", "、"), (".", "。"), ("[", "『"), ("]", "』"), ("{", "「"), ("}", "」"), ("/", "・"), ("~", "\u{301C}")]
        for (key, expected) in cases {
            let result = session.handle(.character(key))
            XCTAssertEqual(result.committed, expected, String(key))
            XCTAssertTrue(result.handled, String(key))
        }
    }

    func testS15OtherKeysPassWhenEmpty() {
        let keys: [KeyInput] = [.character("-"), .character("!"), .character("?"), .character("("),
                                .character("'"), .character("3"), .space]
        for key in keys {
            let result = session.handle(key)
            XCTAssertFalse(result.handled, "\(key)")
            XCTAssertEqual(result.committed, "", "\(key)")
        }
    }

    func testS16SymbolsAfterDigitArePassedThrough() {
        for sequence in ["3.5", "3,", "3/"] {
            let fresh = InputSession(conversion: FakeConversion())
            for character in sequence {
                let result = fresh.handle(.character(character))
                XCTAssertFalse(result.handled, "\(sequence) \(character)")
                XCTAssertEqual(result.committed, "", "\(sequence) \(character)")
            }
        }
    }

    func testS17HyphenExtendsReading() {
        session.type("ko")
        let result = session.handle(.character("-"))
        XCTAssertEqual(result.markedString, "こー")
        XCTAssertEqual(result.committed, "")
    }

    func testS18KatakanaOverrideCommitsWithoutLearning() {
        session.type("kanji")
        XCTAssertEqual(session.handle(.toKatakana).marked?.segments, [segment("カンジ", .raw)])
        XCTAssertEqual(session.handle(.enter).committed, "カンジ")
        XCTAssertEqual(fake.learned, [])
    }

    func testS19HiraganaOverrideCommitsWithoutLearning() {
        session.type("kanji")
        session.press(.toHiragana)
        XCTAssertEqual(session.handle(.enter).committed, "かんじ")
        XCTAssertEqual(fake.learned, [])
    }

    func testS20EscapeShowsHiraganaAndRepeatsHarmlessly() {
        session.type("kanji")
        XCTAssertEqual(session.handle(.escape).markedString, "かんじ")
        let again = session.handle(.escape)
        XCTAssertEqual(again.markedString, "かんじ")
        XCTAssertEqual(again.committed, "")
        XCTAssertTrue(again.handled)
    }

    func testS21TypingClearsKatakanaOverride() {
        session.type("kanji")
        session.press(.toKatakana)
        XCTAssertEqual(session.handle(.character("a")).markedString, "かんじあ")
    }

    func testS22BackspaceOnlyClearsOverride() {
        session.type("kanji")
        session.press(.toKatakana)
        XCTAssertEqual(session.handle(.backspace).markedString, "漢字")
    }

    func testS23BackspaceDeletesOneCharacter() {
        session.type("kanji")
        XCTAssertEqual(session.handle(.backspace).markedString, "缶")
    }

    func testS24BackspaceToEmptyClearsMarked() {
        session.type("k")
        let result = session.handle(.backspace)
        XCTAssertNil(result.marked)
        XCTAssertTrue(result.handled)
        XCTAssertEqual(result.committed, "")
    }

    func testS25EditingKeysPassWhenEmpty() {
        let keys: [KeyInput] = [.backspace, .enter, .left(shift: false), .tab, .escape]
        for key in keys {
            let result = session.handle(key)
            XCTAssertFalse(result.handled, "\(key)")
            XCTAssertEqual(result.committed, "", "\(key)")
        }
    }

    func testS26SpaceEndsLatinRun() {
        let keys: [KeyInput] = [.character("A"), .character("p"), .character("p"), .space]
        for key in keys {
            let result = session.handle(key)
            XCTAssertFalse(result.handled, "\(key)")
            XCTAssertEqual(result.committed, "", "\(key)")
        }
        XCTAssertEqual(session.type("ka").markedString, "か")
    }

    func testS27UppercaseCommitsAndStartsLatinRun() {
        session.type("kanji")
        let upper = session.handle(.character("A"))
        XCTAssertEqual(upper.committed, "漢字")
        XCTAssertFalse(upper.handled)

        let lower = session.handle(.character("b"))
        XCTAssertFalse(lower.handled)
        XCTAssertEqual(lower.committed, "")
        XCTAssertNil(lower.marked)
    }

    func testS28LatinRunPassesSymbolsAndLetters() {
        session.press(.character("A"))
        for character in ".ka" {
            let result = session.handle(.character(character))
            XCTAssertFalse(result.handled, String(character))
            XCTAssertEqual(result.committed, "", String(character))
        }
    }

    func testS29BackspaceToZeroEndsLatinRun() {
        session.press(.character("A"))
        session.press(.backspace)
        XCTAssertEqual(session.type("ka").markedString, "か")
    }

    func testS30SwitchToJapaneseEndsLatinRun() {
        session.type("Ab")
        XCTAssertTrue(session.handle(.switchToJapanese).handled)
        XCTAssertEqual(session.type("ka").markedString, "か")
    }

    func testS31ContextLostEndsLatinRun() {
        session.press(.character("A"))
        session.contextLost()
        XCTAssertEqual(session.type("ka").markedString, "か")
    }

    func testS32EnterFlushesTrailingN() {
        session.type("kan")
        XCTAssertEqual(session.handle(.enter).committed, "缶")
    }

    func testS33EnterKeepsOtherPending() {
        session.type("kank")
        XCTAssertEqual(session.handle(.enter).committed, "缶k")
    }

    func testS34DigitPicksCandidateOnPage() {
        selectKanji()
        let result = session.handle(.character("3"))
        XCTAssertEqual(result.committed, "幹事")
        XCTAssertEqual(fake.learned, [learned("かんじ", "幹事")])
        XCTAssertNil(result.marked)
        XCTAssertTrue(result.handled)
    }

    func testS35DigitWithoutCandidateAndZeroDoNothing() {
        selectKanji()
        for digit: Character in ["4", "0"] {
            let result = session.handle(.character(digit))
            XCTAssertTrue(result.handled, String(digit))
            XCTAssertEqual(result.committed, "", String(digit))
            XCTAssertEqual(result.candidates?.selectedIndex, 1, String(digit))
        }
    }

    func testS36DigitPicksFromSecondPage() {
        session.type("sa")
        session.press(.space)
        var result = session.handle(.down)
        for _ in 1..<8 {
            result = session.handle(.down)
        }
        XCTAssertEqual(result.candidates?.selectedIndex, 9)
        XCTAssertEqual(session.handle(.character("2")).committed, "瑳")
    }

    func testS37LetterCommitsSelectionThenStartsReading() {
        selectKanji()
        let result = session.handle(.character("a"))
        XCTAssertEqual(result.committed, "感じ")
        XCTAssertEqual(fake.learned, [learned("かんじ", "感じ")])
        XCTAssertEqual(result.markedString, "亜")
    }

    func testS38SymbolCommitsSelectionAndRestInOneResult() {
        shrinkKanji()
        let result = session.handle(.character(","))
        XCTAssertEqual(result.committed, "缶字、")
        XCTAssertEqual(fake.learned, [learned("かん", "缶")])
    }

    func testS39HyphenAfterWholeSelectionPassesThrough() {
        selectKanji()
        let result = session.handle(.character("-"))
        XCTAssertEqual(result.committed, "感じ")
        XCTAssertEqual(fake.learned, [learned("かんじ", "感じ")])
        XCTAssertFalse(result.handled)
        XCTAssertNil(result.marked)
    }

    func testS40HyphenAfterShrunkSelectionExtendsRest() {
        shrinkKanji()
        let result = session.handle(.character("-"))
        XCTAssertEqual(result.committed, "缶")
        XCTAssertEqual(fake.learned, [learned("かん", "缶")])
        XCTAssertEqual(result.markedString, "じー")
        XCTAssertTrue(result.handled)
    }

    func testS41EscapeAndBackspaceReturnToComposing() {
        for key in [KeyInput.escape, .backspace] {
            let fresh = InputSession(conversion: FakeConversion())
            fresh.type("kanji")
            fresh.press(.space)
            let result = fresh.handle(key)
            XCTAssertEqual(result.marked?.segments, [segment("漢字", .converted)], "\(key)")
            XCTAssertNil(result.candidates, "\(key)")
            // 読みが削られていないこと: 確定すると読み全体の 1 位になる
            XCTAssertEqual(fresh.handle(.enter).committed, "漢字", "\(key)")
        }
    }

    func testS42TabInSelectionCommitsLearnsAndPasses() {
        selectKanji()
        let result = session.handle(.tab)
        XCTAssertEqual(result.committed, "感じ")
        XCTAssertEqual(fake.learned, [learned("かんじ", "感じ")])
        XCTAssertFalse(result.handled)
    }

    func testS43CommitAllWhileComposing() {
        session.type("kanji")
        let result = session.commitAll()
        XCTAssertEqual(result.committed, "漢字")
        XCTAssertEqual(fake.learned, [])
        XCTAssertNil(result.marked)
    }

    func testS44CommitAllWhileSelectingDoesNotLearn() {
        selectKanji()
        XCTAssertEqual(session.commitAll().committed, "感じ")
        XCTAssertEqual(fake.learned, [])
    }

    func testS45LatinModePassesEverything() {
        session.press(.switchToLatin)
        for key in [KeyInput.character("a"), .space, .enter] {
            XCTAssertFalse(session.handle(key).handled, "\(key)")
        }
        XCTAssertEqual(session.mode, .latin)
    }

    func testS46SwitchToLatinCommitsAndBackToJapanese() {
        session.type("kanji")
        XCTAssertEqual(session.handle(.switchToLatin).committed, "漢字")
        XCTAssertEqual(session.mode, .latin)
        session.press(.switchToJapanese)
        XCTAssertEqual(session.type("ka").markedString, "か")
    }

    func testS47ForbiddenCandidateIsDropped() {
        session.type("e")
        XCTAssertEqual(session.handle(.character("-")).markedString, "ええ")
    }

    func testS48AllCandidatesDroppedFallsBackToReading() {
        XCTAssertEqual(session.type("dame").markedString, "だめ")
        XCTAssertEqual(session.handle(.space).candidates, CandidateList(items: ["だめ"], selectedIndex: 0))
    }

    func testS49ArrowsWhileComposingDoNothing() {
        session.type("kanji")
        let keys: [KeyInput] = [.left(shift: false), .right(shift: false), .up, .down, .right(shift: true)]
        for key in keys {
            let result = session.handle(key)
            XCTAssertTrue(result.handled, "\(key)")
            XCTAssertEqual(result.markedString, "漢字", "\(key)")
        }
    }

    func testS50TextWithLatinIsShownRawAndCannotBeConverted() {
        let typed = session.type("qa")
        XCTAssertEqual(typed.marked?.segments, [segment("qあ", .raw)])
        XCTAssertEqual(fake.calls, [])
        for key in [KeyInput.space, .left(shift: true)] {
            let result = session.handle(key)
            XCTAssertTrue(result.handled, "\(key)")
            XCTAssertEqual(result.marked?.segments, [segment("qあ", .raw)], "\(key)")
            XCTAssertNil(result.candidates, "\(key)")
        }
        XCTAssertEqual(session.handle(.enter).committed, "qあ")
    }

    func testS51ApostropheAfterNIsPartOfReading() {
        let result = session.type("kan'i")
        XCTAssertEqual(result.markedString, "かんい")
        XCTAssertEqual(result.committed, "")
    }

    func testS52ApostropheWithoutNCommitsAndPasses() {
        session.type("ka")
        let result = session.handle(.character("'"))
        XCTAssertEqual(result.committed, "か")
        XCTAssertFalse(result.handled)
    }

    func testS53EnterClearsPrecedingText() {
        session.press(.character("3"))
        session.press(.enter)
        XCTAssertEqual(session.type("ko").markedString, "子")
    }

    func testS54ContextLostClearsPrecedingText() {
        session.press(.character("3"))
        session.contextLost()
        XCTAssertEqual(session.type("ko").markedString, "子")
    }

    func testS55LongReadingCommitsHeadMatchingWhole() {
        fake.additionalRule = { reading in
            guard !reading.isEmpty, reading.allSatisfy({ $0 == "あ" }) else { return nil }
            return [String(repeating: "亜", count: reading.count)]
        }
        let first20 = session.type(String(repeating: "a", count: 20))
        XCTAssertEqual(first20.committed, "")
        let result = session.press(.character("a"))
        XCTAssertEqual(result.committed, String(repeating: "亜", count: 13))
        XCTAssertEqual(result.markedString, String(repeating: "亜", count: 8))
        XCTAssertEqual(fake.learned, [])
    }

    func testS55bHeadIsCommittedOverTwentyFourEvenWhenRestDiffers() {
        // 残りがちょうど 8 文字のときだけ 羽 を返す。T != P + Q なので 24 文字までは確定しない
        fake.additionalRule = { reading in
            guard !reading.isEmpty, reading.allSatisfy({ $0 == "う" }) else { return nil }
            return [String(repeating: reading.count == 8 ? "羽" : "宇", count: reading.count)]
        }
        session.type(String(repeating: "u", count: 20))
        for count in 21...24 {
            XCTAssertEqual(session.press(.character("u")).committed, "", "\(count)")
        }
        let result = session.press(.character("u"))
        XCTAssertEqual(result.committed, String(repeating: "宇", count: 17))
        XCTAssertEqual(result.markedString, String(repeating: "羽", count: 8))
    }

    func testS56HeadIsCommittedOverTwentyFourWhenWholeDiffers() {
        // 21 文字以上の読みには 井、それ未満には 胃 を返す。全体の 1 位が P + Q と一致することが無い
        fake.additionalRule = { reading in
            guard !reading.isEmpty, reading.allSatisfy({ $0 == "い" }) else { return nil }
            return [String(repeating: reading.count >= 21 ? "井" : "胃", count: reading.count)]
        }
        session.type(String(repeating: "i", count: 20))
        for count in 21...24 {
            XCTAssertEqual(session.press(.character("i")).committed, "", "\(count)")
        }
        let result = session.press(.character("i"))
        XCTAssertEqual(result.committed, String(repeating: "胃", count: 17))
        XCTAssertEqual(result.markedString, String(repeating: "胃", count: 8))
    }

    func testS64AutoCommitKeystrokeConvertsOnlyThreeTimes() {
        // 所要時間の上限を守るための仕様なので、呼び出しの回数を観点にする(全体・先頭 13 文字・残り 8 文字)
        fake.additionalRule = { reading in
            guard !reading.isEmpty, reading.allSatisfy({ $0 == "あ" }) else { return nil }
            return [String(repeating: "亜", count: reading.count)]
        }
        session.type(String(repeating: "a", count: 20))
        let before = fake.calls.count
        session.press(.character("a"))
        let readings = fake.calls.dropFirst(before).map(\.reading)
        XCTAssertEqual(readings.sorted(), [String(repeating: "あ", count: 21),
                                           String(repeating: "あ", count: 13),
                                           String(repeating: "あ", count: 8)].sorted())
    }

    func testS57OverrideKeysPassWhenEmpty() {
        XCTAssertFalse(session.handle(.toKatakana).handled)
        XCTAssertFalse(session.handle(.toHiragana).handled)
    }

    func testS58PendingOnlyIgnoresSelectionAndOverride() {
        for key in [KeyInput.space, .left(shift: true), .toKatakana] {
            let fresh = InputSession(conversion: FakeConversion())
            fresh.type("k")
            let result = fresh.handle(key)
            XCTAssertTrue(result.handled, "\(key)")
            XCTAssertEqual(result.markedString, "k", "\(key)")
            XCTAssertNil(result.candidates, "\(key)")
        }
    }

    func testS59KatakanaOverrideFlushesTrailingN() {
        session.type("kan")
        XCTAssertEqual(session.handle(.toKatakana).markedString, "カン")
    }

    func testS60TabWhileComposingCommitsAndPasses() {
        session.type("kanji")
        let result = session.handle(.tab)
        XCTAssertEqual(result.committed, "漢字")
        XCTAssertFalse(result.handled)
    }

    func testS61CommaAfterDigitIsMappedWhileComposing() {
        // に の 1 位は ASCII の数字で終わる 2。確定した直後でも、入力中に受けた記号は対応先になる
        session.type("ni")
        let result = session.press(.character(","))
        XCTAssertEqual(result.committed, "2、")
        XCTAssertTrue(result.handled)
    }

    func testS62OverrideIsNotEnteredWithPendingOnly() {
        session.type("k")
        session.press(.toKatakana)
        let result = session.press(.backspace)
        XCTAssertNil(result.marked)
    }

    func testS63EmptyCandidateIsDropped() {
        XCTAssertEqual(session.type("sora").markedString, "空")
    }
}
