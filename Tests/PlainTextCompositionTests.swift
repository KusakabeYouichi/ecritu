import XCTest

// 未確定の方式 mountain view(3210)の純関数: 表示差分の手順と、カーソル位置の追跡。
// ホストへ出す deleteBackward/insertText の回数と位置がここで決まるので、ずれると本文を壊す
final class PlainTextCompositionTests: XCTestCase {
    func testPlanAppendsAtEnd() {
        let plan = PlainTextComposition.plan(old: "かん", new: "かんじ", cursorOffset: nil)
        XCTAssertEqual(plan, .init(moveCursorToEndFirst: 0, deleteCount: 0, insertText: "じ", cursorOffsetAfter: nil))
    }

    func testPlanDeletesLastAtEnd() {
        let plan = PlainTextComposition.plan(old: "かんじ", new: "かん", cursorOffset: nil)
        XCTAssertEqual(plan, .init(moveCursorToEndFirst: 0, deleteCount: 1, insertText: "", cursorOffsetAfter: nil))
    }

    // 候補循環: かんじ → 漢字。共通の先頭が無いので全部消して差し込む
    func testPlanReplacesWholeForCandidateCycle() {
        let plan = PlainTextComposition.plan(old: "かんじ", new: "漢字", cursorOffset: nil)
        XCTAssertEqual(plan, .init(moveCursorToEndFirst: 0, deleteCount: 3, insertText: "漢字", cursorOffsetAfter: nil))
        let next = PlainTextComposition.plan(old: "漢字", new: "感じ", cursorOffset: nil)
        XCTAssertEqual(next, .init(moveCursorToEndFirst: 0, deleteCount: 2, insertText: "感じ", cursorOffsetAfter: nil))
    }

    // カーソルが途中(かんじ|へんかん)で 1 字打つ: その位置に 1 字挿入、カーソルは 1 つ右へ
    func testPlanInsertsAtCursorInsideComposition() {
        let plan = PlainTextComposition.plan(old: "かんじへんかん", new: "かんじをへんかん", cursorOffset: 3)
        XCTAssertEqual(plan, .init(moveCursorToEndFirst: 0, deleteCount: 0, insertText: "を", cursorOffsetAfter: 4))
    }

    // カーソルが途中で削除: 直前 1 字を消す、カーソルは 1 つ左へ
    func testPlanDeletesBeforeCursorInsideComposition() {
        let plan = PlainTextComposition.plan(old: "かんじへんかん", new: "かんへんかん", cursorOffset: 3)
        XCTAssertEqual(plan, .init(moveCursorToEndFirst: 0, deleteCount: 1, insertText: "", cursorOffsetAfter: 2))
    }

    // カーソルが途中で全置換が要る変更: 末尾へ送ってから全部入れ替え、カーソルは末尾
    func testPlanFallsBackToWholeReplaceWhenChangeIsNotAtCursor() {
        let plan = PlainTextComposition.plan(old: "かんじへんかん", new: "漢字変換", cursorOffset: 3)
        XCTAssertEqual(plan.moveCursorToEndFirst, "へんかん".utf16.count)
        XCTAssertEqual(plan.deleteCount, 7)
        XCTAssertEqual(plan.insertText, "漢字変換")
        XCTAssertNil(plan.cursorOffsetAfter)
    }

    // 追跡: 末尾を優先する。前の文脈 + 未確定 全部が before の末尾にあれば末尾
    func testLocateCursorAtEnd() {
        XCTAssertEqual(
            PlainTextComposition.locateCursor(before: "今日はかんじへんかん", after: "", prefixTail: "今日は", presented: "かんじへんかん"),
            7
        )
    }

    // 追跡: かんじ|へんかん にカーソルがあると 3
    func testLocateCursorInside() {
        XCTAssertEqual(
            PlainTextComposition.locateCursor(before: "今日はかんじ", after: "へんかんです", prefixTail: "今日は", presented: "かんじへんかん"),
            3
        )
    }

    // 追跡: 未確定が本文から消えていたら nil(手放す)
    func testLocateCursorReturnsNilWhenCompositionIsGone() {
        XCTAssertNil(
            PlainTextComposition.locateCursor(before: "今日は", after: "", prefixTail: "今日は", presented: "かんじへんかん")
        )
    }

    func testMountainViewRawValues() {
        XCTAssertTrue(PlainTextComposition.isMountainView(rawValue: "mountain view"))
        XCTAssertTrue(PlainTextComposition.isMountainView(rawValue: "mountainview"))
        XCTAssertFalse(PlainTextComposition.isMountainView(rawValue: "écritu"))
        XCTAssertFalse(PlainTextComposition.isMountainView(rawValue: "tokushima"))
    }
}
