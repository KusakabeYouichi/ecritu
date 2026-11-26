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
        XCTAssertEqual(gesture.move(to: CGSize(width: 35, height: 0)), 2)
    }

    func testAccumulatorCarriesRemainderAcrossUpdates() {
        var accumulator = SpaceTrackpadAccumulator(anchorX: 15)
        XCTAssertEqual(accumulator.update(translationX: 35), 2)  // +20、端数 2
        XCTAssertEqual(accumulator.update(translationX: 42), 1)  // +7 で端数 9
        XCTAssertEqual(accumulator.update(translationX: 33), -1)  // -9
        XCTAssertEqual(accumulator.update(translationX: 41), 0)  // +8 では足りない
    }

    func testVerticalMovementDoesNotMoveCursor() {
        var gesture = SpaceTrackpadGesture()
        gesture.begin(at: 0)
        _ = gesture.activateIfDue(at: 0.4, isAvailable: true)
        XCTAssertEqual(gesture.move(to: CGSize(width: 0, height: 40)), 0)
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

    // MARK: - 盤の位置(格子と同じ寸法値から)

    func testHeroDuckSpansFirstTwoKanaColumnsAndTopTwoRows() {
        // 幅 360・高さ 218(段 50×4+間隔 6×3)、左右の列 60、間隔 6 → かなキーの幅 72
        let layout = HakoiriDuckBoardLayout(
            size: CGSize(width: 360, height: 218),
            leftColumnWidth: 60,
            rightColumnWidth: 60,
            spacing: 6
        )
        XCTAssertEqual(layout.rect(columns: 1...2, rows: 0...1), CGRect(x: 66, y: 0, width: 150, height: 106))
    }

    func testRightColumnReturnKeySpansBottomTwoRows() {
        let layout = HakoiriDuckBoardLayout(
            size: CGSize(width: 360, height: 218),
            leftColumnWidth: 60,
            rightColumnWidth: 60,
            spacing: 6
        )
        XCTAssertEqual(layout.rect(columns: 4...4, rows: 2...3), CGRect(x: 300, y: 112, width: 60, height: 106))
    }

    func testRightColumnWithoutGlobeHasChickAndMirroredParentDuck() {
        let pieces = HakoiriDuckBoardLayout.pieces(showsNextKeyboardKey: false)
        let rightColumn = pieces.filter { $0.columns == 4...4 }
        XCTAssertEqual(rightColumn.map(\.rows), [0...0, 2...3])
        XCTAssertEqual(rightColumn.map(\.motif), [.chick, .parentDuck(mirrored: true)])
    }

    func testNextKeyboardKeyModelTurnsReturnPieceIntoChickAndLeavesGlobeEmpty() {
        let pieces = HakoiriDuckBoardLayout.pieces(showsNextKeyboardKey: true)
        let rightColumn = pieces.filter { $0.columns == 4...4 }
        XCTAssertEqual(rightColumn.map(\.rows), [0...0, 2...2])
        XCTAssertEqual(rightColumn.map(\.motif), [.chick, .chick])
    }
}
