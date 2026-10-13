import XCTest

// 忘れられた離脱個体の掃除(3199)の資格判定。UIKit を使わない純関数なので Mac 上で固定できる。
// 誤爆すると「表示中のキーボードのビュー階層を消す」(2604 の事故)ので、否定側を厚めに置く。
final class KeyboardControllerLifecycleTests: XCTestCase {
    private func isEligible(
        hasBeenDemoted: Bool = false,
        ageSeconds: Double = 600,
        isInWindow: Bool = false,
        hasSuperview: Bool = false,
        hasParent: Bool = false,
        isHostingViewInWindow: Bool = false,
        hasDisplayedSibling: Bool = true
    ) -> Bool {
        ForgottenDetachedControllerGate.isEligible(
            hasBeenDemoted: hasBeenDemoted,
            ageSeconds: ageSeconds,
            isInWindow: isInWindow,
            hasSuperview: hasSuperview,
            hasParent: hasParent,
            isHostingViewInWindow: isHostingViewInWindow,
            hasDisplayedSibling: hasDisplayedSibling
        )
    }

    // ホスト枠 17pt の補正判定(3264): Gboard と同じく縦画面は常に補う(常に 261 を申告)
    func testHostTopInsetCompensationRule() {
        typealias Kind = KeyboardViewController.PreviousDisappearanceKind
        for initial in [CGFloat(216), 244, 261] {
            for kind in [Kind.unknown, .dismissed, .replaced] {
                XCTAssertTrue(KeyboardViewController.shouldCompensateHostTopInset(
                    initialHeight: initial, requestedHeight: 244, previousDisappearance: kind
                ), "\(initial) \(kind)")
            }
        }
    }

    // 実機ログ(2026-09-24 08:17 JST)の id=68540833 と同じ形: 完全離脱・降格経路なし・17分生存
    func testForgottenDetachedControllerIsEligible() {
        XCTAssertTrue(isEligible(ageSeconds: 1032.6))
    }

    func testDisplayedControllerIsNeverEligible() {
        XCTAssertFalse(isEligible(isInWindow: true))
        XCTAssertFalse(isEligible(hasSuperview: true))
        XCTAssertFalse(isEligible(hasParent: true))
        XCTAssertFalse(isEligible(isHostingViewInWindow: true))
    }

    // 表示中の個体が他に無いときは、これが唯一のキーボードかもしれないので触らない
    func testWithoutDisplayedSiblingIsNotEligible() {
        XCTAssertFalse(isEligible(hasDisplayedSibling: false))
    }

    // 降格済みはゾンビ・カナリア側の担当(温存/keep-1 の判断がそちらにある)
    func testDemotedControllerIsLeftToZombieCanary() {
        XCTAssertFalse(isEligible(hasBeenDemoted: true))
    }

    // iOS が取り付ける前の投機生成個体を巻き込まない
    func testYoungControllerIsNotEligible() {
        XCTAssertFalse(isEligible(ageSeconds: 59))
        XCTAssertTrue(isEligible(ageSeconds: ForgottenDetachedControllerGate.minimumAgeSeconds))
    }
}

#if DEBUG
final class LaunchStallMonitorTests: XCTestCase {
    // 3574: メインスレッドを 600ms 止めると、停止時間と停止中の呼び出し元が記録される
    func testRecordsMainThreadStallWithStack() {
        let monitor = LaunchStallMonitor()
        monitor.start()
        // 先に 1 往復させて基準を作ってから止める
        let warm = expectation(description: "warm")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { warm.fulfill() }
        wait(for: [warm], timeout: 2)
        Thread.sleep(forTimeInterval: 0.6)
        let spin = expectation(description: "spin")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { spin.fulfill() }
        wait(for: [spin], timeout: 2)
        let text = monitor.finish()
        XCTAssertNotNil(text)
        XCTAssertTrue(text?.contains("mainStallMaxMs=") ?? false, "text=\(text ?? "nil")")
        XCTAssertTrue(text?.contains("stack@") ?? false, "text=\(text ?? "nil")")
        print("STALLTEXT \(text ?? "nil")")
    }

    func testNoStallReportsNothing() {
        let monitor = LaunchStallMonitor()
        monitor.start()
        let wait1 = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { wait1.fulfill() }
        wait(for: [wait1], timeout: 2)
        XCTAssertNil(monitor.finish())
    }
}

#endif
