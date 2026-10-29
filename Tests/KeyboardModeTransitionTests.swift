import CryptoKit
import XCTest
import UIKit

final class KeyboardModeTransitionTests: XCTestCase {
    // 3300: 共有設定に抑制語(poubelle)の値が無い(アプリ未起動・読み取り失敗)ときは同梱の初期値で抑制する。値があればそちらを優先
    func testSuppressionFallsBackToBundledPoubelleWhenSharedDefaultsMissing() throws {
        let suite = "test.poubelle.fallback.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let missing = KanaKanjiStore(appGroupID: suite).suppressedCandidatesByReading()
        XCTAssertTrue(missing["いたって"]?.contains("至って") == true, "同梱の poubelle で抑制される")
        // ユーザーが抑制を外した(空にした)状態は尊重する
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(try JSONEncoder().encode([String: [String]]()), forKey: KanaKanjiStorageKeys.suppressionVocabulary)
        let edited = KanaKanjiStore(appGroupID: suite).suppressedCandidatesByReading()
        XCTAssertFalse(edited["いたって"]?.contains("至って") == true, "共有設定の値(空)を優先する")
    }

    // 3296: かな 1 文字の正規化の速い道は、旧実装(ICU の文字変換)と全文字で結果が同じ
    private static func legacyNormalizedKanaCharacter(from text: String) -> Character? {
        guard text.count == 1 else { return nil }
        let source = text.precomposedStringWithCanonicalMapping
        let normalized = source.applyingTransform(.hiraganaToKatakana, reverse: true) ?? source
        guard normalized.count == 1, let character = normalized.first,
            let scalar = String(character).unicodeScalars.first,
            (0x3040...0x309F).contains(scalar.value) || scalar.value == 0x30FC else {
            return nil
        }
        return character
    }

    func testKanaNormalizerMatchesLegacyForAllCharacters() {
        var inputs: [String] = []
        for value in UInt32(0x20)...UInt32(0xFFFF) {
            if let scalar = Unicode.Scalar(value) { inputs.append(String(Character(scalar))) }
        }
        for value in UInt32(0x20000)...UInt32(0x20010) {
            if let scalar = Unicode.Scalar(value) { inputs.append(String(Character(scalar))) }
        }
        // 濁点・半濁点が別の文字になった形(か+゙ 等)と、絵文字の結合
        for base in UInt32(0x3041)...UInt32(0x30FA) {
            for mark in [UInt32(0x3099), UInt32(0x309A)] {
                inputs.append(String(String.UnicodeScalarView([Unicode.Scalar(base)!, Unicode.Scalar(mark)!])))
            }
        }
        inputs += ["👍🏽", "e\u{301}", "かか", ""]
        var mismatches: [String] = []
        for input in inputs {
            let expected = Self.legacyNormalizedKanaCharacter(from: input)
            let actual = KanaTextNormalizer.normalizedKanaCharacter(from: input)
            if expected != actual {
                let codes = input.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: "+")
                mismatches.append("\(codes): 旧=\(expected.map(String.init) ?? "nil") 新=\(actual.map(String.init) ?? "nil")")
            }
        }
        XCTAssertTrue(mismatches.isEmpty, "\(mismatches.count) 件不一致: \(mismatches.prefix(20))")
    }

    // 入力補助バーの設定(inputAssistantItem の初回アクセス)で増えるメモリ(3297、計測用。DIAG_ASSIST_MEM=1 のときだけ)
    @MainActor
    func testInputAssistantItemMemoryCost() throws {
        guard ProcessInfo.processInfo.environment["DIAG_ASSIST_MEM"] != nil else {
            throw XCTSkip("DIAG_ASSIST_MEM=1 のときだけ実行")
        }
        func usedMB() -> Double {
            var stats = malloc_statistics_t()
            malloc_zone_statistics(nil, &stats)
            return Double(stats.size_in_use) / 1_048_576
        }
        let controller = UIInputViewController()
        controller.loadViewIfNeeded()
        let before = usedMB()
        let assistant = controller.inputAssistantItem
        assistant.leadingBarButtonGroups = []
        assistant.trailingBarButtonGroups = []
        let after = usedMB()
        let second = UIInputViewController()
        second.loadViewIfNeeded()
        let before2 = usedMB()
        second.inputAssistantItem.leadingBarButtonGroups = []
        second.inputAssistantItem.trailingBarButtonGroups = []
        let after2 = usedMB()
        print(String(format: "DIAGASSIST 1体目 +%.2fMB 2体目 +%.2fMB", after - before, after2 - before2))
    }

    // 速さの比較(3296、計測用。DIAG_KANA_PERF=1 のときだけ)
    func testKanaNormalizerSpeedComparison() throws {
        guard ProcessInfo.processInfo.environment["DIAG_KANA_PERF"] != nil else {
            throw XCTSkip("DIAG_KANA_PERF=1 のときだけ実行")
        }
        let samples = ["か", "ア", "ー", "ん", "が", "漢", "字", "a"]
        let rounds = 20_000
        func measure(_ body: (String) -> Character?) -> Double {
            let start = CFAbsoluteTimeGetCurrent()
            var hits = 0
            for _ in 0..<rounds { for s in samples where body(s) != nil { hits += 1 } }
            XCTAssertGreaterThan(hits, 0)
            return (CFAbsoluteTimeGetCurrent() - start) * 1_000_000 / Double(rounds * samples.count)
        }
        let legacy = measure(Self.legacyNormalizedKanaCharacter)
        let current = measure(KanaTextNormalizer.normalizedKanaCharacter)
        print(String(format: "DIAGKANAPERF 旧=%.3fµs/字 新=%.3fµs/字 比=%.1f倍", legacy, current, legacy / current))
    }

    // 3291: 削除キー(押し続けるとリピートするキー)は 1 打鍵で 1 回だけ実行する
    func testRepeatKeyButtonActionRunsOncePerTouch() {
        let suppress = ActionKeyButton.shouldSuppressRepeatKeyButtonAction
        // 連打で 1 回目のボタン判定が 2 回目に触れた後に遅れて届く。どちらのボタン判定も弾く(ドラッグ判定が実行済み)
        let tap2Began = 100.15
        XCTAssertTrue(suppress(100.16, tap2Began, 100.08, false), "遅れて届いた 1 回目のボタン判定")
        XCTAssertTrue(suppress(100.23, tap2Began, 100.22, false), "2 回目のボタン判定")
        // 押し続けてリピート中に離す(触れてから 1 秒超)。リピート中なので弾く
        XCTAssertTrue(suppress(102.0, 100.0, 90.0, true), "リピート中に離した")
        // 離した直後(onEnded が先に届いた)も弾く
        XCTAssertTrue(suppress(102.1, 100.0, 102.0, false), "離した直後")
        // ドラッグ判定が来ない操作(VoiceOver のダブルタップ等)は実行する
        XCTAssertFalse(suppress(200.0, 0, 0, false), "ドラッグが来ない操作")
        XCTAssertFalse(suppress(200.0, 100.0, 100.1, false), "前のタッチから十分に時間が経った")
    }

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

    // 3585: 『や』キーの括弧を「」にすると、1段目が 「/」、2 段階フリックの下が 『/』。他のキーの 「/」 には 2 段階フリックが無い
    func testYaBracketCornerStyle() {
        let corner = FlickKanaLayout.rows(for: .none, layoutMode: .fiveByTwo, profile: .ecritu, yaBracket: .corner)
        let ya = corner.flatMap { $0 }.first { $0.label == "や" }
        XCTAssertEqual(ya?.up, "「")
        XCTAssertEqual(ya?.left, "」")
        XCTAssertEqual(ya?.right, "ゆ")
        XCTAssertEqual(ya?.down, "よ")

        let double = FlickKanaLayout.rows(for: .none, layoutMode: .fiveByTwo, profile: .ecritu, yaBracket: .doubleCorner)
        XCTAssertEqual(double.flatMap { $0 }.first { $0.label == "や" }?.up, "『")

        let threeByThree = FlickKanaLayout.rows(for: .none, layoutMode: .threeByThreePlusWa, profile: .littlebear, yaBracket: .corner)
        let yaLittleBear = threeByThree.flatMap { $0 }.first { $0.label == "や" }?.remapped(for: .littlebear)
        XCTAssertEqual(yaLittleBear?.left, "「")
        XCTAssertEqual(yaLittleBear?.right, "」")

        func out(_ primary: String, _ vertical: FlickDirection, ya: Bool) -> String? {
            FlickKanaLayout.secondaryBracketFlickOutput(forPrimaryOutput: primary, verticalDirection: vertical, isYaKey: ya)
        }
        XCTAssertEqual(out("「", .bas, ya: true), "『")
        XCTAssertEqual(out("」", .bas, ya: true), "』")
        XCTAssertEqual(out("「", .haut, ya: true), "(")
        XCTAssertEqual(out("」", .haut, ya: true), ")")
        XCTAssertNil(out("「", .bas, ya: false))
        XCTAssertNil(out("」", .bas, ya: false))
        // 『』 の設定(既定)は従来どおり
        XCTAssertEqual(out("『", .bas, ya: true), "「")
        XCTAssertEqual(out("』", .bas, ya: true), "」")
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
        // 2段階フリックは左右からしか起動しない。を→下=ゐ、ー→下=ゑ が出せること
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

    // 永続値は画面上の名前(hanabi / littlebear / écritu。3036)。旧値 apple / ecritu の読み替えは 3377 で撤去した
    func testFlickDirectionProfileStoredValues() {
        XCTAssertEqual(FlickDirectionProfile.littlebear.rawValue, "littlebear")
        XCTAssertEqual(FlickDirectionProfile.hanabi.rawValue, "hanabi")
        XCTAssertEqual(FlickDirectionProfile.ecritu.rawValue, "écritu")
        XCTAssertNil(FlickDirectionProfile(rawValue: "apple"))
        XCTAssertNil(FlickDirectionProfile(rawValue: "ecritu"))
        XCTAssertEqual(FlickDirectionProfile(rawValue: "écritu"), .ecritu)
        // 合成形・分解形のどちらで保存されていても読める(Swift の文字列比較は正準等価)
        XCTAssertEqual(FlickDirectionProfile(rawValue: "e\u{0301}critu"), .ecritu)
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
             "coucou", "amour", "excite", "action", "bizarre", "heros", "special"]
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
    // 3490: 別個体がセッションのオーナー(=この個体はゾンビ・予備)のとき、診断ログを 1 行書いても 320 行ぶんの
    // バッファー(160KB)を抱えない。オーナーの個体は従来どおりバッファーを持つ(5 秒バッチ)
    @MainActor
    func testNonOwnerControllerDoesNotRetainDiagnosticsLogBuffer() throws {
        let controller = KeyboardViewController()
        guard let defaults = controller.sharedDefaults else {
            throw XCTSkip("App Group の UserDefaults が無い")
        }
        let key = KeyboardViewController.SharedDefaultsKeys.keyboardDiagnosticsSessionOwnerToken
        let previousToken = defaults.string(forKey: key)
        defer {
            if let previousToken {
                defaults.set(previousToken, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.set("other-process:other-controller", forKey: key)
        controller.appendKeyboardDiagnosticsLog("非オーナーの追記 3490")
        let nonOwnerBuffer = controller.diagnosticsState.diagnosticsLogLock.withLock {
            controller.diagnosticsState.diagnosticsLogTextBuffer
        }
        XCTAssertNil(nonOwnerBuffer, "非オーナーの個体がバッファーを抱えている")

        defaults.set(controller.diagnosticsSessionOwnerToken(), forKey: key)
        controller.appendKeyboardDiagnosticsLog("オーナーの追記 3490")
        let ownerBuffer = controller.diagnosticsState.diagnosticsLogLock.withLock {
            controller.diagnosticsState.diagnosticsLogTextBuffer
        }
        XCTAssertNotNil(ownerBuffer, "オーナーの個体はバッファーを持つ")
        controller.persistBufferedKeyboardDiagnostics()
    }

    // 診断ログの追記はメインと候補生成キューの両方から来る(初回変換の区間計測 e93b85ae)。
    // バッファーの切り詰め(320 行超)を同時に走らせると removeSubrange が範囲外で SIGTRAP
    // (実機 3106/3110 で 2 件、数時間放置→数文字打つと落ちる)。ロック下でなければここで落ちる。
    @MainActor
    func testDiagnosticsLogAppendIsSafeAcrossThreads() throws {
        var controllerHolder: KeyboardViewController? = KeyboardViewController()
        guard let controller = controllerHolder, controller.sharedDefaults != nil else {
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
        controllerHolder = nil
        // 個体の deinit が張るスパイク窓(1.2 秒)を、次のテスト(MemoryForensicsTests の窓計数)へ漏らさない
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
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

// 入力の状態のモデル(iPad 版に向けた切り分け 段 1)。以前はビューの @State で、テストから触れなかった
@MainActor
final class KeyboardInputStateTests: XCTestCase {
    // 2 度押しの窓がテスト中に勝手に閉じないよう、十分長く取る
    private let longSecondTapThreshold: TimeInterval = 60

    func testSwitchingToKanaClearsReturnToKanaMark() {
        let state = KeyboardInputState()
        state.switchInputMode(.emoji)
        state.returnToKanaAfterNextCommit = true

        state.switchInputMode(.kana)

        XCTAssertEqual(state.inputMode, .kana)
        XCTAssertFalse(state.returnToKanaAfterNextCommit)
    }

    func testSwitchingToNumberClearsReturnToKanaMark() {
        let state = KeyboardInputState()
        state.returnToKanaAfterNextCommit = true

        state.switchInputMode(.number)

        XCTAssertEqual(state.inputMode, .number)
        XCTAssertFalse(state.returnToKanaAfterNextCommit)
    }

    func testSwitchingToEmojiKeepsReturnToKanaMark() {
        let state = KeyboardInputState()
        state.returnToKanaAfterNextCommit = true

        state.switchInputMode(.emoji)

        XCTAssertEqual(state.inputMode, .emoji)
        XCTAssertTrue(state.returnToKanaAfterNextCommit)
    }

    func testSwitchingToFormattedNumberKeepsReturnToKanaMark() {
        let state = KeyboardInputState()
        state.returnToKanaAfterNextCommit = true

        state.switchInputMode(.formattedNumber)

        XCTAssertEqual(state.inputMode, .formattedNumber)
        XCTAssertTrue(state.returnToKanaAfterNextCommit)
    }

    func testSwitchingAwayFromLatinClosesSecondTapWindow() throws {
        let state = KeyboardInputState()
        state.switchToLatinMode(with: .off)
        state.startLatinModeSwitchSecondTapWindow(threshold: longSecondTapThreshold)
        let pendingReset = try XCTUnwrap(state.pendingLatinModeSwitchSecondTapResetWorkItem)

        state.switchInputMode(.kana)

        XCTAssertFalse(state.isAwaitingLatinModeSwitchSecondTap)
        XCTAssertNil(state.pendingLatinModeSwitchSecondTapResetWorkItem)
        XCTAssertTrue(pendingReset.isCancelled)
    }

    func testSwitchingToLatinKeepsSecondTapWindowOpen() {
        let state = KeyboardInputState()
        state.switchToLatinMode(with: .off)
        state.startLatinModeSwitchSecondTapWindow(threshold: longSecondTapThreshold)

        state.switchInputMode(.latin)

        XCTAssertTrue(state.isAwaitingLatinModeSwitchSecondTap)
        state.cancelLatinModeSwitchSecondTapWindow()
    }

    func testSecondTapWindowClosesByItselfAfterThreshold() {
        let state = KeyboardInputState()
        state.startLatinModeSwitchSecondTapWindow(threshold: 0.05)
        XCTAssertTrue(state.isAwaitingLatinModeSwitchSecondTap)

        let closed = expectation(description: "2 度押しの窓が閉じる")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { closed.fulfill() }
        wait(for: [closed], timeout: 2)

        XCTAssertFalse(state.isAwaitingLatinModeSwitchSecondTap)
        XCTAssertNil(state.pendingLatinModeSwitchSecondTapResetWorkItem)
    }

    func testSwitchToLatinModeWithLockedSetsLockedShift() {
        let state = KeyboardInputState()
        state.lastLatinShiftTapAt = Date(timeIntervalSinceReferenceDate: 10)

        state.switchToLatinMode(with: .locked)

        XCTAssertEqual(state.inputMode, .latin)
        XCTAssertEqual(state.latinShiftState, .locked)
        XCTAssertNil(state.lastLatinShiftTapAt)
    }

    func testConsumeReturnToKanaSwitchesToKanaAndClearsMark() {
        let state = KeyboardInputState()
        state.switchInputMode(.emoji)
        state.emojiInputSubmode = .kaomoji
        state.returnToKanaAfterNextCommit = true

        state.consumeReturnToKanaAfterNextCommitIfNeeded()

        XCTAssertEqual(state.inputMode, .kana)
        XCTAssertEqual(state.emojiInputSubmode, .emoji)
        XCTAssertFalse(state.returnToKanaAfterNextCommit)
    }

    func testConsumeReturnToKanaStaysWhenMarkIsNotSet() {
        let state = KeyboardInputState()
        state.switchInputMode(.emoji)
        state.emojiInputSubmode = .kaomoji

        state.consumeReturnToKanaAfterNextCommitIfNeeded()

        XCTAssertEqual(state.inputMode, .emoji)
        XCTAssertEqual(state.emojiInputSubmode, .kaomoji)
    }

    func testTransitionStateAssignmentIsReadBackFieldByField() {
        let state = KeyboardInputState()
        let tappedAt = Date(timeIntervalSinceReferenceDate: 42)
        let assigned = KeyboardModeTransitionState(
            inputMode: .latin,
            diacriticMode: .dakuten,
            kanaCharacterMode: .katakana,
            latinShiftState: .on,
            lastLatinShiftTapAt: tappedAt,
            emojiInputSubmode: .symbols,
            spaceToastText: "空白",
            spaceToastOpacity: 0.5
        )

        state.transitionState = assigned

        XCTAssertEqual(state.inputMode, .latin)
        XCTAssertEqual(state.diacriticMode, .dakuten)
        XCTAssertEqual(state.kanaCharacterMode, .katakana)
        XCTAssertEqual(state.latinShiftState, .on)
        XCTAssertEqual(state.lastLatinShiftTapAt, tappedAt)
        XCTAssertEqual(state.emojiInputSubmode, .symbols)
        XCTAssertEqual(state.spaceToastText, "空白")
        XCTAssertEqual(state.spaceToastOpacity, 0.5)
        XCTAssertEqual(state.transitionState, assigned)
    }

    func testInitialStateMatchesFormerViewDefaults() {
        let state = KeyboardInputState()

        XCTAssertEqual(state.inputMode, .kana)
        XCTAssertEqual(state.diacriticMode, .none)
        XCTAssertEqual(state.kanaCharacterMode, .hiragana)
        XCTAssertEqual(state.latinShiftState, .off)
        XCTAssertNil(state.lastLatinShiftTapAt)
        XCTAssertEqual(state.emojiInputSubmode, .emoji)
        XCTAssertNil(state.spaceToastText)
        XCTAssertEqual(state.spaceToastOpacity, 0)
        XCTAssertFalse(state.returnToKanaAfterNextCommit)
        XCTAssertFalse(state.isAwaitingLatinModeSwitchSecondTap)
    }
}

// 確定の規則(iPad 版に向けた切り分け 段 2)。以前はビューの commitText / commitEmojiKaomojiSymbolText と
// 部首ピッカーの確定の中にあった。期待値は移す前のコードから作った期待表(経過ファイル)による
@MainActor
final class KeyboardCommitRulesTests: XCTestCase {
    private let shiftDoubleTapThreshold: TimeInterval = 0.32

    // ホストへ出た文字と履歴へ足した文字を、起きた順に残す
    private enum Event: Equatable {
        case text(String)
        case history(String)
    }

    private final class Recorder {
        var events: [Event] = []
    }

    private func commit(_ text: String, on state: KeyboardInputState, recorder: Recorder) {
        state.commitText(text, shiftDoubleTapThreshold: shiftDoubleTapThreshold) { recorder.events.append(.text($0)) }
    }

    private func commitFromPanel(
        _ text: String,
        on state: KeyboardInputState,
        isKaomojiShortcutCategory: Bool = false,
        recorder: Recorder
    ) {
        state.commitEmojiKaomojiSymbolText(
            text,
            isKaomojiShortcutCategory: isKaomojiShortcutCategory,
            onShortcutCandidateCommitted: { recorder.events.append(.history($0)) },
            onTextInput: { recorder.events.append(.text($0)) }
        )
    }

    private func latinState(shift: LatinShiftState) -> KeyboardInputState {
        let state = KeyboardInputState()
        state.switchToLatinMode(with: shift)
        return state
    }

    private func emojiState(submode: EmojiInputSubmode) -> KeyboardInputState {
        let state = KeyboardInputState()
        state.switchInputMode(.emoji)
        state.emojiInputSubmode = submode
        return state
    }

    // MARK: 純関数 committedOutput

    func testCommittedOutputUppercasesLetterWhileShiftIsOn() {
        let state = latinState(shift: .on)
        XCTAssertEqual(KeyboardModeTransition.committedOutput("a", state: state.transitionState), "A")
    }

    func testCommittedOutputKeepsLetterWhileShiftIsOff() {
        let state = latinState(shift: .off)
        XCTAssertEqual(KeyboardModeTransition.committedOutput("a", state: state.transitionState), "a")
    }

    func testCommittedOutputKeepsNonLetterAndMultiCharacterTextWhileShiftIsOn() {
        let state = latinState(shift: .on)
        XCTAssertEqual(KeyboardModeTransition.committedOutput("1", state: state.transitionState), "1")
        XCTAssertEqual(KeyboardModeTransition.committedOutput("ab", state: state.transitionState), "ab")
    }

    func testCommittedOutputUppercasesSharpSToDoubleS() {
        // 表示用のキーの字(ẞ)とは別に、確定は String.uppercased() のまま
        let state = latinState(shift: .on)
        XCTAssertEqual(KeyboardModeTransition.committedOutput("ß", state: state.transitionState), "SS")
    }

    func testCommittedOutputConvertsKanaToKatakanaInKatakanaMode() {
        let state = KeyboardInputState()
        state.kanaCharacterMode = .katakana
        XCTAssertEqual(KeyboardModeTransition.committedOutput("か", state: state.transitionState), "カ")
    }

    func testCommittedOutputKeepsHiraganaInHiraganaMode() {
        let state = KeyboardInputState()
        XCTAssertEqual(KeyboardModeTransition.committedOutput("か", state: state.transitionState), "か")
    }

    // MARK: commitText

    func testCommitWithShiftOnEmitsUppercaseAndTurnsShiftOff() {
        let state = latinState(shift: .on)
        let recorder = Recorder()

        commit("a", on: state, recorder: recorder)

        XCTAssertEqual(recorder.events, [.text("A")])
        XCTAssertEqual(state.latinShiftState, .off)
    }

    func testCommitWithShiftLockedKeepsShiftLocked() {
        let state = latinState(shift: .locked)
        let recorder = Recorder()

        commit("a", on: state, recorder: recorder)

        XCTAssertEqual(recorder.events, [.text("A")])
        XCTAssertEqual(state.latinShiftState, .locked)
    }

    func testCommitOfDigitWithShiftOnKeepsShiftOn() {
        let state = latinState(shift: .on)
        let recorder = Recorder()

        commit("1", on: state, recorder: recorder)

        XCTAssertEqual(recorder.events, [.text("1")])
        XCTAssertEqual(state.latinShiftState, .on)
    }

    func testCommitInKatakanaModeEmitsKatakanaAndClearsDiacritic() {
        let state = KeyboardInputState()
        state.kanaCharacterMode = .katakana
        state.diacriticMode = .dakuten
        let recorder = Recorder()

        commit("か", on: state, recorder: recorder)

        XCTAssertEqual(recorder.events, [.text("カ")])
        XCTAssertEqual(state.kanaCharacterMode, .katakana)
        XCTAssertEqual(state.diacriticMode, .none)
    }

    func testCommitOfEmptyTextEmitsNothing() {
        let state = latinState(shift: .on)
        let recorder = Recorder()

        commit("", on: state, recorder: recorder)

        XCTAssertEqual(recorder.events, [])
        XCTAssertEqual(state.latinShiftState, .on)
    }

    func testShiftKeyTokenTogglesShiftWithoutEmittingText() {
        let state = latinState(shift: .off)
        let recorder = Recorder()

        commit(FlickKanaLayout.latinShiftKeyToken, on: state, recorder: recorder)

        XCTAssertEqual(recorder.events, [])
        XCTAssertEqual(state.latinShiftState, .on)
        XCTAssertNotNil(state.lastLatinShiftTapAt)
    }

    func testShiftKeyTokenInNumberModeTogglesShift() {
        let state = KeyboardInputState()
        state.switchInputMode(.number)
        let recorder = Recorder()

        commit(FlickKanaLayout.latinShiftKeyToken, on: state, recorder: recorder)

        XCTAssertEqual(recorder.events, [])
        XCTAssertEqual(state.latinShiftState, .on)
    }

    func testCommitWithReturnToKanaMarkSwitchesToKana() {
        let state = emojiState(submode: .symbols)
        state.returnToKanaAfterNextCommit = true
        let recorder = Recorder()

        commit("★", on: state, recorder: recorder)

        XCTAssertEqual(recorder.events, [.text("★")])
        XCTAssertEqual(state.inputMode, .kana)
        XCTAssertFalse(state.returnToKanaAfterNextCommit)
    }

    // MARK: 絵文字・顔文字・記号の面からの確定

    func testEmojiCommitAddsToHistoryBeforeEmittingText() {
        let state = emojiState(submode: .emoji)
        let recorder = Recorder()

        commitFromPanel("😀", on: state, recorder: recorder)

        XCTAssertEqual(recorder.events, [.history("😀"), .text("😀")])
        XCTAssertEqual(state.inputMode, .emoji)
    }

    func testKaomojiCommitOutsideShortcutCategoryAddsToHistory() {
        let state = emojiState(submode: .kaomoji)
        let recorder = Recorder()

        commitFromPanel("(^_^)", on: state, isKaomojiShortcutCategory: false, recorder: recorder)

        XCTAssertEqual(recorder.events, [.history("(^_^)"), .text("(^_^)")])
    }

    func testKaomojiCommitFromShortcutCategoryDoesNotAddToHistory() {
        let state = emojiState(submode: .kaomoji)
        let recorder = Recorder()

        commitFromPanel("(^_^)", on: state, isKaomojiShortcutCategory: true, recorder: recorder)

        XCTAssertEqual(recorder.events, [.text("(^_^)")])
    }

    func testSymbolCommitDoesNotAddToHistory() {
        let state = emojiState(submode: .symbols)
        let recorder = Recorder()

        commitFromPanel("→", on: state, recorder: recorder)

        XCTAssertEqual(recorder.events, [.text("→")])
    }

    func testEmojiCommitWithReturnToKanaMarkSwitchesToKana() {
        let state = emojiState(submode: .emoji)
        state.returnToKanaAfterNextCommit = true
        let recorder = Recorder()

        commitFromPanel("😀", on: state, recorder: recorder)

        XCTAssertEqual(recorder.events, [.history("😀"), .text("😀")])
        XCTAssertEqual(state.inputMode, .kana)
        XCTAssertFalse(state.returnToKanaAfterNextCommit)
    }

    // MARK: 部首ピッカーの確定

    func testRadicalCommitEmitsCharacterAndReturnsToKana() {
        let state = emojiState(submode: .kanjiRadical)
        let recorder = Recorder()

        state.commitRadicalCharacter("漢") { recorder.events.append(.text($0)) }

        XCTAssertEqual(recorder.events, [.text("漢")])
        XCTAssertEqual(state.inputMode, .kana)
    }

    func testRadicalCommitClearsReturnToKanaMark() {
        let state = emojiState(submode: .kanjiRadical)
        state.returnToKanaAfterNextCommit = true

        state.commitRadicalCharacter("漢") { _ in }

        XCTAssertEqual(state.inputMode, .kana)
        XCTAssertFalse(state.returnToKanaAfterNextCommit)
    }
}

// 面の切り替えの割り当て(iPad 版に向けた切り分け 段 6)。以前はビューの selectModePalette /
// selectKanaModeSwitcher / selectCompactKeyboardSwitchKey / performPostModifierEmptyTapAction の中にあった。
// 期待値は設計の期待表(c01-phase6-design.md)による
@MainActor
final class KeyboardPanelRoutingTests: XCTestCase {
    // MARK: 面選択のパレット

    func testPaletteLabelsOpenTheirPanels() {
        XCTAssertEqual(KeyboardPanelRouting.panelTarget(forPaletteLabel: "記号"), .symbols)
        XCTAssertEqual(KeyboardPanelRouting.panelTarget(forPaletteLabel: "絵文字"), .emoji)
        XCTAssertEqual(KeyboardPanelRouting.panelTarget(forPaletteLabel: "顔文字"), .kaomoji)
        XCTAssertEqual(KeyboardPanelRouting.panelTarget(forPaletteLabel: "単漢字"), .kanjiRadical)
        XCTAssertEqual(KeyboardPanelRouting.panelTarget(forPaletteLabel: "書式化"), .formattedNumber)
    }

    func testUnknownPaletteLabelOpensNothing() {
        XCTAssertNil(KeyboardPanelRouting.panelTarget(forPaletteLabel: "x"))
        // 切替キーがパレットを使わずに確定したときに渡る空文字も面ではない
        XCTAssertNil(KeyboardPanelRouting.panelTarget(forPaletteLabel: ""))
    }

    // MARK: 左下キーの方向

    func testDownFlickAlwaysOpensKanjiRadical() {
        XCTAssertEqual(
            KeyboardPanelRouting.panelTarget(
                forModeSwitchDirection: .bas,
                tapAction: .emoji,
                rightAction: .kaomoji,
                upAction: .symbols
            ),
            .kanjiRadical
        )
    }

    func testTapRightAndUpFollowTheirAssignedActions() {
        func target(_ direction: FlickDirection) -> KeyboardPanelTarget? {
            KeyboardPanelRouting.panelTarget(
                forModeSwitchDirection: direction,
                tapAction: .kaomoji,
                rightAction: .symbols,
                upAction: .emoji
            )
        }

        XCTAssertEqual(target(.milieu), .kaomoji)
        XCTAssertEqual(target(.droite), .symbols)
        XCTAssertEqual(target(.haut), .emoji)
    }

    func testLeftFlickOpensNothing() {
        XCTAssertNil(
            KeyboardPanelRouting.panelTarget(
                forModeSwitchDirection: .gauche,
                tapAction: .emoji,
                rightAction: .emoji,
                upAction: .emoji
            )
        )
    }

    // MARK: コンパクト配列の左下キー

    func testCompactSwitchKeyTapAdvancesKeyboardAndFlicksSwitchPanel() {
        XCTAssertEqual(KeyboardPanelRouting.compactSwitchKeyRoute(direction: .milieu), .advanceKeyboard)
        XCTAssertEqual(KeyboardPanelRouting.compactSwitchKeyRoute(direction: .droite), .switchPanel)
        XCTAssertEqual(KeyboardPanelRouting.compactSwitchKeyRoute(direction: .haut), .switchPanel)
        XCTAssertEqual(KeyboardPanelRouting.compactSwitchKeyRoute(direction: .bas), .switchPanel)
        XCTAssertEqual(KeyboardPanelRouting.compactSwitchKeyRoute(direction: .gauche), .ignore)
    }

    // MARK: 面への入り方の適用

    func testEnterPanelKanjiRadicalOpensRadicalPicker() {
        let state = KeyboardInputState()

        state.enterPanel(.kanjiRadical)

        XCTAssertEqual(state.inputMode, .emoji)
        XCTAssertEqual(state.emojiInputSubmode, .kanjiRadical)
    }

    func testModeSwitcherDownFlickOpensRadicalPickerRegardlessOfAssignment() {
        let state = KeyboardInputState()

        state.selectModeSwitcherPanel(
            direction: .bas,
            triggerLabel: nil,
            tapAction: .symbols,
            rightAction: .symbols,
            upAction: .symbols
        )

        XCTAssertEqual(state.inputMode, .emoji)
        XCTAssertEqual(state.emojiInputSubmode, .kanjiRadical)
    }

    func testModeSwitcherLeftFlickLeavesKana() {
        let state = KeyboardInputState()

        state.selectModeSwitcherPanel(
            direction: .gauche,
            triggerLabel: nil,
            tapAction: .symbols,
            rightAction: .symbols,
            upAction: .symbols
        )

        XCTAssertEqual(state.inputMode, .kana)
    }

    // MARK: 修飾キーの空タップ

    func testEmptyTapEmojiSelectsConfiguredCategoryAndMarksReturnToKana() {
        let state = KeyboardInputState()

        state.applyPostModifierEmptyTap(
            actionRawValue: "emoji",
            emojiCategoryID: "7",
            symbolCategoryID: "0",
            kaomojiCategoryID: "existing",
            kaomojiPanel: KaomojiPanelState()
        )

        XCTAssertEqual(state.selectedEmojiCategory, .flags)
        XCTAssertEqual(state.inputMode, .emoji)
        XCTAssertEqual(state.emojiInputSubmode, .emoji)
        XCTAssertTrue(state.returnToKanaAfterNextCommit)
    }

    func testEmptyTapEmojiWithNonNumericCategoryKeepsCurrentCategory() {
        let state = KeyboardInputState()
        state.selectedEmojiCategory = .food

        state.applyPostModifierEmptyTap(
            actionRawValue: "emoji",
            emojiCategoryID: "flags",
            symbolCategoryID: "0",
            kaomojiCategoryID: "existing",
            kaomojiPanel: KaomojiPanelState()
        )

        XCTAssertEqual(state.selectedEmojiCategory, .food)
        XCTAssertEqual(state.inputMode, .emoji)
        XCTAssertEqual(state.emojiInputSubmode, .emoji)
    }

    func testEmptyTapSymbolsSelectsConfiguredCategoryAndMarksReturnToKana() {
        let state = KeyboardInputState()

        state.applyPostModifierEmptyTap(
            actionRawValue: "symbols",
            emojiCategoryID: "0",
            symbolCategoryID: "7",
            kaomojiCategoryID: "existing",
            kaomojiPanel: KaomojiPanelState()
        )

        XCTAssertEqual(state.selectedSymbolCategory, .music)
        XCTAssertEqual(state.inputMode, .emoji)
        XCTAssertEqual(state.emojiInputSubmode, .symbols)
        XCTAssertTrue(state.returnToKanaAfterNextCommit)
    }

    func testEmptyTapOtherSelectsKaomojiCategoryKeepingSearchReading() {
        let state = KeyboardInputState()
        let kaomojiPanel = KaomojiPanelState()
        kaomojiPanel.selectedReadingPrefix = "か"
        kaomojiPanel.selectedReading = "かお"

        state.applyPostModifierEmptyTap(
            actionRawValue: "kaomoji",
            emojiCategoryID: "0",
            symbolCategoryID: "0",
            kaomojiCategoryID: "shortcut",
            kaomojiPanel: kaomojiPanel
        )

        XCTAssertEqual(kaomojiPanel.selectedCategoryID, "shortcut")
        XCTAssertEqual(kaomojiPanel.selectedReadingPrefix, "か")
        XCTAssertEqual(kaomojiPanel.selectedReading, "かお")
        XCTAssertEqual(state.inputMode, .emoji)
        XCTAssertEqual(state.emojiInputSubmode, .kaomoji)
        XCTAssertTrue(state.returnToKanaAfterNextCommit)
    }

    func testInitialCategoriesMatchFormerViewDefaults() {
        let state = KeyboardInputState()

        XCTAssertEqual(state.selectedEmojiCategory, .people)
        XCTAssertEqual(state.selectedSymbolCategory, .basic)
    }
}
