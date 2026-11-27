import CoreGraphics
import XCTest

// 空白キーの長押しのトラックパッド(c10)。発動・積算・移動量の判断を確かめる
final class SpaceTrackpadTests: XCTestCase {
    // MARK: - 発動と終了

    func testReleaseBeforeActivationDelayInsertsSpace() {
        var gesture = SpaceTrackpadGesture()
        gesture.begin(at: 0)
        XCTAssertFalse(gesture.activateIfDue(at: 0.39, isAvailable: true))
        XCTAssertEqual(gesture.end(), .space)
    }

    func testUpwardFlickBeforeActivationInsertsTabAndNeverActivates() {
        var gesture = SpaceTrackpadGesture()
        gesture.begin(at: 0)
        _ = gesture.move(to: CGSize(width: 0, height: -20))
        XCTAssertFalse(gesture.activateIfDue(at: 0.4, isAvailable: true))
        XCTAssertEqual(gesture.end(), .tab)
    }

    func testHorizontalFlickBeforeActivationInsertsSpaceAndNeverActivates() {
        var gesture = SpaceTrackpadGesture()
        gesture.begin(at: 0)
        _ = gesture.move(to: CGSize(width: 20, height: 0))
        XCTAssertFalse(gesture.activateIfDue(at: 0.4, isAvailable: true))
        XCTAssertEqual(gesture.end(), .space)
    }

    // 取り消しの片づけが指を離した通知より先に来ても、トラックパッドだった接触は空白を入れない
    func testEndingTrackpadContactTwiceStillInsertsNothing() {
        var gesture = SpaceTrackpadGesture()
        gesture.begin(at: 0)
        _ = gesture.activateIfDue(at: 0.4, isAvailable: true)
        XCTAssertEqual(gesture.end(), .nothing)
        XCTAssertEqual(gesture.end(), .nothing)
    }

    func testEndingTabFlickTwiceStillInsertsTab() {
        var gesture = SpaceTrackpadGesture()
        gesture.begin(at: 0)
        _ = gesture.move(to: CGSize(width: 0, height: -20))
        XCTAssertEqual(gesture.end(), .tab)
        XCTAssertEqual(gesture.end(), .tab)
    }

    func testNewContactAfterTrackpadInsertsSpaceOnTap() {
        var gesture = SpaceTrackpadGesture()
        gesture.begin(at: 0)
        _ = gesture.activateIfDue(at: 0.4, isAvailable: true)
        _ = gesture.end()
        gesture.begin(at: 5)
        XCTAssertEqual(gesture.end(), .space)
    }

    func testHoldingWithSmallDriftActivatesAtActivationDelay() {
        var gesture = SpaceTrackpadGesture()
        gesture.begin(at: 0)
        _ = gesture.move(to: CGSize(width: 5, height: 0))
        XCTAssertTrue(gesture.activateIfDue(at: 0.4, isAvailable: true))
        XCTAssertEqual(gesture.phase, .active)
    }

    func testReleasingAfterActivationInsertsNothingEvenAfterMovingUp() {
        var gesture = SpaceTrackpadGesture()
        gesture.begin(at: 0)
        _ = gesture.activateIfDue(at: 0.4, isAvailable: true)
        _ = gesture.move(to: CGSize(width: 0, height: -30))
        XCTAssertEqual(gesture.end(), .nothing)
    }

    func testNoFlickFeedbackWhileActive() {
        var gesture = SpaceTrackpadGesture()
        gesture.begin(at: 0)
        _ = gesture.activateIfDue(at: 0.4, isAvailable: true)
        _ = gesture.move(to: CGSize(width: 0, height: -30))
        XCTAssertEqual(gesture.feedbackDirection, .milieu)
    }

    func testUpwardFlickShowsTabFeedbackBeforeActivation() {
        var gesture = SpaceTrackpadGesture()
        gesture.begin(at: 0)
        _ = gesture.move(to: CGSize(width: 0, height: -20))
        XCTAssertEqual(gesture.feedbackDirection, .haut)
    }

    func testHoldingWithComposingTextDoesNotActivate() {
        var gesture = SpaceTrackpadGesture()
        gesture.begin(at: 0)
        let available = SpaceTrackpad.isAvailable(composingEmpty: "か".isEmpty)
        XCTAssertFalse(gesture.activateIfDue(at: 1.0, isAvailable: available))
        XCTAssertEqual(gesture.phase, .pending)
    }

    func testAvailableOnlyWhenComposingIsEmpty() {
        XCTAssertTrue(SpaceTrackpad.isAvailable(composingEmpty: true))
        XCTAssertFalse(SpaceTrackpad.isAvailable(composingEmpty: false))
    }

    // MARK: - 積算

    func testDriftBeforeActivationIsDiscarded() {
        var gesture = SpaceTrackpadGesture()
        gesture.begin(at: 0)
        _ = gesture.move(to: CGSize(width: 15, height: 0))
        _ = gesture.activateIfDue(at: 0.4, isAvailable: true)
        // 起点は 15。+20 で 2 文字(端数 2 を持ち越す)
        XCTAssertEqual(gesture.move(to: CGSize(width: 35, height: 0)), SpaceTrackpadStep(characters: 2, lines: 0))
    }

    func testAccumulatorCarriesRemainderAcrossUpdates() {
        var accumulator = SpaceTrackpadAccumulator(anchorX: 15)
        XCTAssertEqual(accumulator.update(translationX: 35), 2)  // +20、端数 2
        XCTAssertEqual(accumulator.update(translationX: 42), 1)  // +7 で端数 9
        XCTAssertEqual(accumulator.update(translationX: 33), -1)  // -9
        XCTAssertEqual(accumulator.update(translationX: 41), 0)  // +8 では足りない
    }

    // 3916: 縦は 20pt で 1 行(上が負)。発動前の縦のずれは捨てる
    func testVerticalMovementMovesLines() {
        var gesture = SpaceTrackpadGesture()
        gesture.begin(at: 0)
        _ = gesture.move(to: CGSize(width: 0, height: 5))
        _ = gesture.activateIfDue(at: 0.4, isAvailable: true)
        XCTAssertEqual(gesture.move(to: CGSize(width: 0, height: 45)), SpaceTrackpadStep(characters: 0, lines: 2))
        XCTAssertEqual(gesture.move(to: CGSize(width: 0, height: 20)), SpaceTrackpadStep(characters: 0, lines: -1))
        XCTAssertEqual(gesture.move(to: CGSize(width: 0, height: 10)), .zero)
    }

    func testDiagonalMovementMovesBoth() {
        var gesture = SpaceTrackpadGesture()
        gesture.begin(at: 0)
        _ = gesture.activateIfDue(at: 0.4, isAvailable: true)
        XCTAssertEqual(gesture.move(to: CGSize(width: -18, height: -20)), SpaceTrackpadStep(characters: -2, lines: -1))
    }

    // MARK: - 行の移動(3916)

    func testMovingUpKeepsColumn() {
        var cursor = SpaceTrackpadCursor(before: "abcd\nef", after: "gh")
        // 2 行めの ef| → 1 行めの ab|: cd(2) + 改行 + ef(2) = 5 戻る
        XCTAssertEqual(cursor.moveLines(by: -1), -5)
        XCTAssertEqual(cursor.position, 2)
    }

    func testMovingDownClampsToShortLineAndRestoresColumn() {
        var cursor = SpaceTrackpadCursor(before: "abcd", after: "\nx\nwxyz")
        // 1 行めの 4 桁め → 短い 2 行め(x)の行末 → 3 行めの 4 桁め
        XCTAssertEqual(cursor.moveLines(by: 1), 2)
        XCTAssertEqual(cursor.position, 6)
        XCTAssertEqual(cursor.moveLines(by: 1), 5)
        XCTAssertEqual(cursor.position, 11)
    }

    func testMovingTwoLinesAtOnceAndThroughEmptyLine() {
        var cursor = SpaceTrackpadCursor(before: "ab\n\ncd", after: nil)
        XCTAssertEqual(cursor.moveLines(by: -1), -3)
        XCTAssertEqual(cursor.position, 3)
        var twoUp = SpaceTrackpadCursor(before: "ab\n\ncd", after: nil)
        XCTAssertEqual(twoUp.moveLines(by: -2), -4)
        XCTAssertEqual(twoUp.position, 2)
    }

    func testLineMoveStopsAtContextEdges() {
        var top = SpaceTrackpadCursor(before: "abc", after: "\nd")
        XCTAssertEqual(top.moveLines(by: -1), 0)
        var bottom = SpaceTrackpadCursor(before: "a\nbc", after: "de")
        XCTAssertEqual(bottom.moveLines(by: 1), 0)
    }

    func testLineMoveCountsUtf16OfEmojiAndCrlf() {
        // 👍 は utf16 で 2、\r\n は 1 文字で utf16 2
        var cursor = SpaceTrackpadCursor(before: "👍x\r\ny", after: nil)
        XCTAssertEqual(cursor.moveLines(by: -1), -4)
        XCTAssertEqual(cursor.position, 1)
    }

    func testHorizontalMoveForgetsPreferredColumn() {
        var cursor = SpaceTrackpadCursor(before: "abcd", after: "\nx\nwxyz")
        _ = cursor.moveLines(by: 1)  // x の行末(桁 1)、覚えている桁は 4
        _ = cursor.move(by: -1)  // 桁 0
        _ = cursor.moveLines(by: 1)
        XCTAssertEqual(cursor.position, 7)  // 3 行めの 桁 0
    }

    func testSessionRereadsContextAtLineEdge() {
        var session = SpaceTrackpadCursorSession(before: "b", after: nil, now: 0)
        let offset = session.utf16Offset(forLines: -1, now: 0.2) { ("a\nb", nil) }
        XCTAssertEqual(offset, -2)
    }

    // 3920: ホストが後ろの文脈を今の行の終わりまでしか渡さない(メモ)。読み直しても下の行が見えなければ、改行をまたいで 1 行進め、
    // 次の動きで読み直して同じ桁に合わせる
    func testDownCrossesUnseenNewlineThenRestoresColumn() {
        var session = SpaceTrackpadCursorSession(before: "ab", after: "cd", now: 0)
        // 桁 2。cd(2) + 改行 1
        XCTAssertEqual(session.utf16Offset(forLines: 1, now: 0.2) { ("ab", "cd") }, 3)
        // ホストに届くまでの指の動きは捨てる
        XCTAssertEqual(session.utf16Offset(forSteps: 1, now: 0.25) { XCTFail("読まない"); return (nil, nil) }, 0)
        // 次の行の頭にいる。桁 2 へ合わせてから 1 文字右
        XCTAssertEqual(session.utf16Offset(forSteps: 1, now: 0.4) { ("abcd\n", "wxyz") }, 3)
    }

    func testUpCrossesUnseenNewline() {
        var session = SpaceTrackpadCursorSession(before: "ab", after: nil, now: 0)
        XCTAssertEqual(session.utf16Offset(forLines: -1, now: 0.2) { ("ab", nil) }, -3)
        // 前の行 xyz の行末にいる。桁 2 へ(-1)合わせてから 1 文字左(-1)
        XCTAssertEqual(session.utf16Offset(forSteps: -1, now: 0.4) { ("xyz", "\nab") }, -2)
    }

    func testCrossingWaitsForRereadBeforeCrossingAgain() {
        var session = SpaceTrackpadCursorSession(before: "ab", after: nil, now: 0)
        // 下に見える行が無い(文章の終わりかもしれない)。改行 1 ぶんだけ送る(終わりならホストが止める)
        XCTAssertEqual(session.utf16Offset(forLines: 1, now: 0.2) { ("ab", nil) }, 1)
        // 終わりだった: 読み直すと同じ位置。桁 2 のまま動かない
        XCTAssertEqual(session.utf16Offset(forSteps: -1, now: 0.4) { ("ab", nil) }, -1)
    }

    func testVerticalMovementDoesNotMoveCursorBeforeActivation() {
        var gesture = SpaceTrackpadGesture()
        gesture.begin(at: 0)
        XCTAssertEqual(gesture.move(to: CGSize(width: 0, height: 4)), .zero)
    }

    // MARK: - 移動量(utf16)

    func testMovingLeftOneAsciiCharacter() {
        var cursor = SpaceTrackpadCursor(before: "abc", after: "de")
        XCTAssertEqual(cursor.move(by: -1), -1)
    }

    func testMovingLeftTwoCharactersSendsOnce() {
        var cursor = SpaceTrackpadCursor(before: "abc", after: "de")
        XCTAssertEqual(cursor.move(by: -2), -2)
    }

    func testMovingLeftOverSurrogatePairEmoji() {
        var cursor = SpaceTrackpadCursor(before: "a👍", after: nil)
        XCTAssertEqual(cursor.move(by: -1), -2)
    }

    func testMovingLeftTwoOverEmojiAndAscii() {
        var cursor = SpaceTrackpadCursor(before: "a👍", after: nil)
        XCTAssertEqual(cursor.move(by: -2), -3)
    }

    func testMovingLeftOverZwjFamilyEmoji() {
        var cursor = SpaceTrackpadCursor(before: "x👨‍👩‍👧", after: nil)
        XCTAssertEqual(cursor.move(by: -1), -8)
    }

    func testMovingRightOverPrecomposedKana() {
        var cursor = SpaceTrackpadCursor(before: "", after: "がx")
        XCTAssertEqual(cursor.move(by: 1), 1)
    }

    func testMovingRightOverCombiningDakuten() {
        var cursor = SpaceTrackpadCursor(before: "", after: "か\u{3099}x")
        XCTAssertEqual(cursor.move(by: 1), 2)
    }

    func testStopsAtBeforeEdge() {
        var cursor = SpaceTrackpadCursor(before: "a", after: nil)
        XCTAssertEqual(cursor.move(by: -3), -1)
        XCTAssertEqual(cursor.move(by: -1), 0)
    }

    func testDoesNotMoveRightWhenAfterIsNil() {
        var cursor = SpaceTrackpadCursor(before: "ab", after: nil)
        XCTAssertEqual(cursor.move(by: 1), 0)
    }

    func testStopsAtAfterEdge() {
        var cursor = SpaceTrackpadCursor(before: nil, after: "a")
        XCTAssertEqual(cursor.move(by: 3), 1)
        XCTAssertEqual(cursor.move(by: 1), 0)
    }

    func testDoesNotMoveLeftWhenBeforeIsNil() {
        var cursor = SpaceTrackpadCursor(before: nil, after: "ab")
        XCTAssertEqual(cursor.move(by: -1), 0)
    }

    func testConsecutiveMovesUseSnapshotPosition() {
        var cursor = SpaceTrackpadCursor(before: "👍a", after: nil)
        XCTAssertEqual(cursor.move(by: -1), -1)
        XCTAssertEqual(cursor.move(by: -1), -2)
    }

    // MARK: - 端での読み直し(改訂 2 の R1)

    func testSessionDoesNotRereadWhileSnapshotHasRoom() {
        var session = SpaceTrackpadCursorSession(before: "abc", after: nil, now: 0)
        let offset = session.utf16Offset(forSteps: -1, now: 1) { ("zzzzz👍", nil) }
        XCTAssertEqual(offset, -1)
    }

    func testSessionRereadsAtEdgeAfterInterval() {
        var session = SpaceTrackpadCursorSession(before: "", after: nil, now: 0)
        let offset = session.utf16Offset(forSteps: -1, now: 0.2) { ("a👍", nil) }
        XCTAssertEqual(offset, -2)
    }

    func testSessionRereadsAtExactlyTheIntervalAndKeepsMovingOnNewSnapshot() {
        var session = SpaceTrackpadCursorSession(before: "", after: nil, now: 0)
        XCTAssertEqual(session.utf16Offset(forSteps: -1, now: 0.1) { ("ab", nil) }, -1)
        XCTAssertEqual(session.utf16Offset(forSteps: -1, now: 0.15) { (nil, nil) }, -1)
    }

    func testSessionRereadsAtMostOncePerInterval() {
        var session = SpaceTrackpadCursorSession(before: "", after: nil, now: 0)
        XCTAssertEqual(session.utf16Offset(forSteps: -1, now: 0.2) { ("", nil) }, 0)
        // 読み直してから 0.05 秒。文脈が増えていても、まだ読まない
        XCTAssertEqual(session.utf16Offset(forSteps: -1, now: 0.25) { ("xy", nil) }, 0)
    }

    func testSessionDoesNotRereadRightAfterAdjust() {
        var session = SpaceTrackpadCursorSession(before: "a", after: nil, now: 0)
        XCTAssertEqual(session.utf16Offset(forSteps: -1, now: 0.5) { (nil, nil) }, -1)
        // 端に着いた直後(移動から 0.05 秒)は読み直さない
        XCTAssertEqual(session.utf16Offset(forSteps: -1, now: 0.55) { ("xyz", nil) }, 0)
    }

    func testSessionStopsWhenRereadStillHasNothing() {
        var session = SpaceTrackpadCursorSession(before: "", after: nil, now: 0)
        XCTAssertEqual(session.utf16Offset(forSteps: -1, now: 0.2) { ("", nil) }, 0)
    }

    // MARK: - 盤(箱入り娘の初期配置を 90 度回し、出口を左に)

    // 幅 360・高さ 218(段 50×4+間隔 6×3)、左の列 42(狭い)、右の列 60、間隔 6 → かなキーの幅 78
    private let boardLayout = HakoiriDuckBoardLayout(
        size: CGSize(width: 360, height: 218),
        leftColumnWidth: 42,
        rightColumnWidth: 60,
        spacing: 6
    )

    func testNarrowLeftColumnCellUsesItsOwnWidth() {
        XCTAssertEqual(boardLayout.rect(columns: 0...0, rows: 0...0), CGRect(x: 0, y: 0, width: 42, height: 50))
    }

    func testKanaColumnsStartAfterNarrowLeftColumn() {
        XCTAssertEqual(boardLayout.rect(columns: 1...2, rows: 0...0), CGRect(x: 48, y: 0, width: 162, height: 50))
    }

    func testHeroDuckPieceCoversRightTwoColumnsOfMiddleRows() {
        let hero = HakoiriDuckBoardLayout.pieces.first { $0.motif == .heroDuck }
        XCTAssertEqual(hero?.columns, 3...4)
        XCTAssertEqual(hero?.rows, 1...2)
        XCTAssertEqual(boardLayout.rect(columns: 3...4, rows: 1...2), CGRect(x: 216, y: 56, width: 144, height: 106))
    }

    func testVerticalFeatherPieceIsInMiddleKanaColumn() {
        let feather = HakoiriDuckBoardLayout.pieces.first { $0.motif == .feather }
        XCTAssertEqual(feather?.columns, 2...2)
        XCTAssertEqual(feather?.rows, 1...2)
        XCTAssertEqual(boardLayout.rect(columns: 2...2, rows: 1...2), CGRect(x: 132, y: 56, width: 78, height: 106))
    }

    func testExitIsOnLeftEdgeAcrossMiddleRows() {
        XCTAssertEqual(HakoiriDuckBoardLayout.exitRows, 1...2)
        XCTAssertEqual(boardLayout.exitOpening, 53...165)
    }

    func testPiecesCoverEveryCellOnceExceptTwoExitCells() {
        var covered: [String] = []
        for piece in HakoiriDuckBoardLayout.pieces {
            for column in piece.columns {
                for row in piece.rows {
                    covered.append("c\(column)r\(row)")
                }
            }
        }
        XCTAssertEqual(covered.count, 18)
        XCTAssertEqual(Set(covered).count, 18)
        let all = Set((0...4).flatMap { column in (0...3).map { "c\(column)r\($0)" } })
        XCTAssertEqual(all.subtracting(covered), ["c0r1", "c0r2"])
    }

    func testChicksAreAtStartPositions() {
        let chicks = HakoiriDuckBoardLayout.pieces.filter { $0.motif == .chick }
        XCTAssertEqual(Set(chicks.map { "c\($0.columns.lowerBound)r\($0.rows.lowerBound)" }), ["c0r0", "c1r1", "c1r2", "c0r3"])
    }

    // 盤を描いた個体を見分ける(3911)。始めるたびに数え直し、個体ごとに印の順で並べる
    func testBoardDrawOwnersAreCountedPerOwnerAndResetOnActivation() {
        let display = SpaceTrackpadDisplayState()
        display.setActive(true)
        XCTAssertEqual(display.boardDrawOwnersSummary, "なし")
        display.noteBoardDrawn(size: CGSize(width: 377, height: 203), ownerTag: "D06ED979")
        display.noteBoardDrawn(size: CGSize(width: 377, height: 203), ownerTag: "7E303189")
        display.noteBoardDrawn(size: CGSize(width: 377, height: 203), ownerTag: "D06ED979")
        XCTAssertEqual(display.boardDrawOwnersSummary, "7E303189×1 D06ED979×2")
        XCTAssertEqual(display.boardDrawCount, 3)
        display.setActive(false)
        display.setActive(true)
        XCTAssertEqual(display.boardDrawOwnersSummary, "なし")
    }
}
