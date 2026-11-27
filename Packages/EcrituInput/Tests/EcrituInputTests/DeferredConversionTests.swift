import XCTest
@testable import EcrituInput

/// 求め終わった変換だけを待たずに返す偽の変換。candidates は「待って求める」呼び出しとして記録する
private final class DeferredFakeConversion: ConversionProviding {
    private struct Key: Hashable {
        var reading: String
        var precedingText: String
    }

    let inner = FakeConversion()
    private var cache: [Key: [String]] = [:]

    func candidates(reading: String, precedingText: String) -> [String] {
        let key = Key(reading: reading, precedingText: precedingText)
        if let cached = cache[key] {
            return cached
        }
        let result = inner.candidates(reading: reading, precedingText: precedingText)
        cache[key] = result
        return result
    }

    func cachedCandidates(reading: String, precedingText: String) -> [String]? {
        cache[Key(reading: reading, precedingText: precedingText)]
    }

    func learn(reading: String, candidate: String) {
        inner.learn(reading: reading, candidate: candidate)
    }

    /// 待って求めた回数
    var blockingCallCount: Int { inner.calls.count }
}

/// 打鍵を待たせないライヴ変換(D1〜D8)。
/// 変換がまだ求まっていない間はかなを表示し、求まった後の refresh で差し替える
final class DeferredConversionTests: XCTestCase {
    private var fake: DeferredFakeConversion!
    private var session: InputSession!

    override func setUp() {
        super.setUp()
        fake = DeferredFakeConversion()
        session = InputSession(conversion: fake)
    }

    private func useRepeatedRule(kana: Character, kanji: String) {
        fake.inner.additionalRule = { reading in
            guard !reading.isEmpty, reading.allSatisfy({ $0 == kana }) else { return nil }
            return [String(repeating: kanji, count: reading.count)]
        }
    }

    /// 裏の仕事の代わり: 要る変換を求めてから refresh する。反映するものが無ければ nil
    private func deliver(_ request: LiveConversionRequest?, file: StaticString = #filePath, line: UInt = #line) -> InputResult? {
        guard let request else {
            XCTFail("要る変換が残っていない", file: file, line: line)
            return nil
        }
        InputSession.prewarm(request, conversion: fake)
        return session.refresh(delivered: request)
    }

    // D1: 打鍵の結果はかなのまま返り、要る変換が残る。求まった後の refresh で変換後の表示になる
    func testD1KeystrokeShowsKanaThenRefreshShowsConversion() {
        let typed = session.type("kanji")
        XCTAssertEqual(typed.marked?.segments, [segment("かんじ", .raw)])
        XCTAssertEqual(
            typed.pendingConversion,
            LiveConversionRequest(reading: "かんじ", precedingText: "", wantsAutoCommit: false)
        )
        XCTAssertEqual(typed.committed, "")

        let refreshed = deliver(typed.pendingConversion)
        XCTAssertEqual(refreshed?.marked?.segments, [segment("漢字", .converted)])
        XCTAssertNil(refreshed?.pendingConversion)
        XCTAssertEqual(refreshed?.committed, "")
    }

    // D2: 打鍵では、待って求める変換を 1 度も呼ばない
    func testD2KeystrokesNeverWaitForConversion() {
        session.type("kanji")
        XCTAssertEqual(fake.blockingCallCount, 0)
    }

    // D3: 変換が求まる前に Enter を押しても、かなでなく変換後の 1 位が確定する
    func testD3EnterBeforeConversionArrivesCommitsConvertedText() {
        session.type("kanji")
        let result = session.handle(.enter)
        XCTAssertEqual(result.committed, "漢字")
        XCTAssertNil(result.marked)
        XCTAssertNil(result.pendingConversion)
    }

    // D4: 変換が求まる前に Space を押しても、候補の選択へ入れる
    func testD4SpaceBeforeConversionArrivesStartsSelection() {
        session.type("kanji")
        let result = session.handle(.space)
        XCTAssertEqual(result.candidates, CandidateList(items: ["漢字", "感じ", "幹事"], selectedIndex: 1))
        XCTAssertNil(result.pendingConversion)
    }

    // D5: 古い読みの変換が届いても、今の読みの表示には使わない(反映するものが無い)
    func testD5StaleConversionForShorterReadingChangesNothing() {
        let old = session.type("kan").pendingConversion
        XCTAssertEqual(old?.reading, "か")
        let current = session.type("ji")
        XCTAssertNil(deliver(old))
        // 今の読みの変換は、打鍵の結果が別に求めている
        XCTAssertEqual(current.pendingConversion?.reading, "かんじ")
    }

    // D6: 求め終わっている読みは、打鍵の結果でそのまま変換後の表示になる(Backspace で戻ったときなど)
    func testD6CachedReadingIsShownConvertedImmediately() {
        _ = deliver(session.type("kanji").pendingConversion)
        session.type("a")
        let back = session.handle(.backspace)
        XCTAssertEqual(back.marked?.segments, [segment("漢字", .converted)])
        XCTAssertNil(back.pendingConversion)
    }

    // D7: 自動確定は打鍵では行なわず、変換が求まった後の refresh で行なう
    func testD7AutoCommitIsDeferredUntilRefresh() {
        useRepeatedRule(kana: "あ", kanji: "亜")
        let typed = session.type(String(repeating: "a", count: 21))
        XCTAssertEqual(typed.committed, "")
        XCTAssertEqual(typed.pendingConversion?.reading, String(repeating: "あ", count: 21))
        XCTAssertEqual(typed.pendingConversion?.wantsAutoCommit, true)
        XCTAssertEqual(fake.blockingCallCount, 0)

        let refreshed = deliver(typed.pendingConversion)
        XCTAssertEqual(refreshed?.committed, String(repeating: "亜", count: 13))
        XCTAssertEqual(refreshed?.markedString, String(repeating: "亜", count: 8))
        XCTAssertNil(refreshed?.pendingConversion)
    }

    // D8: 変換を求めている間に読みが伸びていても(速く打ったとき)、求めた読みの先頭は確定する。
    // 残りは今の読みの残りで、その変換を改めて求める
    func testD8AutoCommitStillAppliesWhenReadingGrewMeanwhile() {
        useRepeatedRule(kana: "あ", kanji: "亜")
        let old = session.type(String(repeating: "a", count: 21)).pendingConversion
        session.type("a")
        let refreshed = deliver(old)
        XCTAssertEqual(refreshed?.committed, String(repeating: "亜", count: 13))
        // 残りの変換(8 文字ぶん)は求まっているので残し、伸びた 1 文字だけをかなで続ける
        XCTAssertEqual(refreshed?.marked?.segments, [
            segment(String(repeating: "亜", count: 8), .converted), segment("あ", .raw),
        ])
        XCTAssertEqual(refreshed?.pendingConversion?.reading, String(repeating: "あ", count: 9))
        XCTAssertEqual(refreshed?.pendingConversion?.precedingText, String(repeating: "亜", count: 8))

        let second = deliver(refreshed?.pendingConversion)
        XCTAssertEqual(second?.committed, "")
        XCTAssertEqual(second?.markedString, String(repeating: "亜", count: 9))
    }

    // D9: 待たずに答える変換(初期の実装)では、今までどおり打鍵の結果で変換後の表示になる
    func testD9SynchronousProviderStillConvertsOnKeystroke() {
        let synchronous = InputSession(conversion: FakeConversion())
        let typed = synchronous.type("kanji")
        XCTAssertEqual(typed.marked?.segments, [segment("漢字", .converted)])
        XCTAssertNil(typed.pendingConversion)
    }

    // D10: 全体の 1 位が 先頭 + 残り と一致しないときは、refresh でも 24 文字までは確定しない。超えたら確定する
    func testD10RefreshFollowsTheSameAutoCommitRuleAsKeystroke() {
        // 残りがちょうど 8 文字のときだけ 羽 を返す(全体と一致しない)
        fake.inner.additionalRule = { reading in
            guard !reading.isEmpty, reading.allSatisfy({ $0 == "う" }) else { return nil }
            return [String(repeating: reading.count == 8 ? "羽" : "宇", count: reading.count)]
        }
        var last = session.type(String(repeating: "u", count: 20))
        for count in 21...24 {
            last = session.type("u")
            let refreshed = deliver(last.pendingConversion)
            XCTAssertEqual(refreshed?.committed, "", "\(count)")
            XCTAssertEqual(refreshed?.markedString, String(repeating: "宇", count: count), "\(count)")
        }
        last = session.type("u")
        let refreshed = deliver(last.pendingConversion)
        XCTAssertEqual(refreshed?.committed, String(repeating: "宇", count: 17))
        XCTAssertEqual(refreshed?.markedString, String(repeating: "羽", count: 8))
    }

    // D11: 変換が届く前に確定していたら、届いた変換では何も起きない(確定の重複が無い)
    func testD11DeliveryAfterCommitChangesNothing() {
        useRepeatedRule(kana: "あ", kanji: "亜")
        let pending = session.type(String(repeating: "a", count: 21)).pendingConversion
        XCTAssertEqual(session.handle(.enter).committed, String(repeating: "亜", count: 21))
        XCTAssertNil(deliver(pending))
    }

    // D12: 変換が届く前に候補の選択へ入っていたら、届いた変換では何も起きない
    func testD12DeliveryDuringSelectionChangesNothing() {
        let pending = session.type("kanji").pendingConversion
        session.press(.space)
        XCTAssertNil(deliver(pending))
    }

    // D13: カタカナの表示へ切り替えていたら、届いた変換で自動確定しない(表示もカタカナのまま)
    func testD13DeliveryDuringKatakanaOverrideDoesNotAutoCommit() {
        useRepeatedRule(kana: "あ", kanji: "亜")
        let pending = session.type(String(repeating: "a", count: 21)).pendingConversion
        session.press(.toKatakana)
        let refreshed = deliver(pending)
        XCTAssertEqual(refreshed?.committed, "")
        XCTAssertEqual(refreshed?.markedString, String(repeating: "ア", count: 21))
    }

    // D14: 21 文字を超えていても、読みを変えないキー(←)の後に届いた変換で自動確定する
    func testD14AutoCommitSurvivesKeysThatDoNotChangeReading() {
        useRepeatedRule(kana: "あ", kanji: "亜")
        let pending = session.type(String(repeating: "a", count: 21)).pendingConversion
        session.press(.left(shift: false))
        XCTAssertEqual(deliver(pending)?.committed, String(repeating: "亜", count: 13))
    }

    // D15: 直前の文字列が変わっていたら(カーソルが動いた可能性)、届いた変換は使わない
    func testD15DeliveryAfterContextLostIsIgnored() {
        session.type("a")
        session.press(.enter)
        let pending = session.type("kanji").pendingConversion
        XCTAssertEqual(pending?.precedingText, "亜")
        session.contextLost()
        XCTAssertNil(deliver(pending))
    }

    // D16: 変換がまだ求まっていない打鍵では、直前に見せていた変換を残し、打ち足した分だけをかなで続ける
    // (全体をかなへ戻さない。打つたびに未確定の全体がちらつくのを防ぐ)
    func testD16PreviousConversionStaysWhileNewOneIsPending() {
        _ = deliver(session.type("kanji").pendingConversion)
        let typed = session.type("ka")
        XCTAssertEqual(typed.marked?.segments, [segment("漢字", .converted), segment("か", .raw)])
        XCTAssertEqual(typed.pendingConversion?.reading, "かんじか")
        // 子音だけ打った段階でも同じ(読みは変わらないので、見せていた変換のまま)
        let consonant = session.type("n")
        XCTAssertEqual(consonant.marked?.segments, [
            segment("漢字", .converted), segment("か", .raw), segment("n", .raw),
        ])
    }

    // D17: 見せていた変換を残した表示のまま Enter を押しても、確定するのは今の読みの変換
    func testD17EnterCommitsConversionOfCurrentReadingNotTheStaleDisplay() {
        fake.inner.additionalRule = { $0 == "かんじか" ? ["幹事か"] : nil }
        _ = deliver(session.type("kanji").pendingConversion)
        session.type("ka")
        XCTAssertEqual(session.handle(.enter).committed, "幹事か")
    }

    // D18: 確定した後の新しい入力には、前の入力で見せていた変換を持ち越さない
    func testD18PreviousConversionIsNotCarriedIntoNextComposition() {
        _ = deliver(session.type("kanji").pendingConversion)
        session.press(.enter)
        let typed = session.type("kanjika")
        XCTAssertEqual(typed.marked?.segments, [segment("かんじか", .raw)])
    }
}
