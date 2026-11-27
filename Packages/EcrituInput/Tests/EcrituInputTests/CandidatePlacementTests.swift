import XCTest
@testable import EcrituInput

/// 候補ウインドウを出す場所(W1〜W5)。画面は幅 1000・高さ 800、下の 50 は Dock で使えない
final class CandidatePlacementTests: XCTestCase {
    private let visible = CGRect(x: 0, y: 50, width: 1000, height: 750)
    private let size = CGSize(width: 150, height: 240)

    private func origin(anchor: CGRect) -> CGPoint {
        CandidatePlacement.origin(size: size, anchor: anchor, visibleFrame: visible)
    }

    // W1: 下に入るときは、行のすぐ下・行の左端に出す
    func testW1FitsBelowTheLine() {
        XCTAssertEqual(origin(anchor: CGRect(x: 300, y: 500, width: 2, height: 20)), CGPoint(x: 300, y: 260))
    }

    // W2: 画面の下端に近くて下に入りきらないときは、行のすぐ上に出す(行を隠さない)
    func testW2NearBottomGoesAboveTheLine() {
        XCTAssertEqual(origin(anchor: CGRect(x: 300, y: 80, width: 2, height: 20)), CGPoint(x: 300, y: 100))
    }

    // W3: ちょうど下に入る境目(下端が使える範囲の下端と同じ)は下のまま
    func testW3ExactlyFitsBelow() {
        XCTAssertEqual(origin(anchor: CGRect(x: 300, y: 290, width: 2, height: 20)), CGPoint(x: 300, y: 50))
    }

    // W4: 右端に近いときは、右へはみ出さないように左へ寄せる
    func testW4NearRightEdgeIsShiftedLeft() {
        XCTAssertEqual(origin(anchor: CGRect(x: 950, y: 500, width: 2, height: 20)), CGPoint(x: 850, y: 260))
    }

    // W5: 行の矩形が取れなかったとき(全部 0)でも、使える範囲の中に出す
    func testW5ZeroAnchorStaysInsideVisibleFrame() {
        let point = origin(anchor: .zero)
        XCTAssertTrue(visible.contains(CGRect(origin: point, size: size)), "\(point)")
    }
}
