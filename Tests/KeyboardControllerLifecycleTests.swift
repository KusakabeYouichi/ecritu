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

    // ホスト枠 17pt の補正判定(3248)。実機ログの 4 つの形をそのまま固定する
    func testHostTopInsetCompensationRule() {
        typealias Kind = KeyboardViewController.PreviousDisappearanceKind
        func decide(_ initial: CGFloat, _ kind: Kind) -> Bool {
            KeyboardViewController.shouldCompensateHostTopInset(
                initialHeight: initial, requestedHeight: 244, previousDisappearance: kind
            )
        }
        // 既定 216 経由(アプリで最初の回)は消え方によらず補う(3227)
        XCTAssertTrue(decide(216, .unknown))
        XCTAssertTrue(decide(216, .replaced))
        // 前の枠 244 を引き継いだ回: 消え方によらず補わない(3239 の「引っ込めた後は補う」は 03:26 JST の実機で
        // ホストも帯を付けて 278 になったため撤回。3250)
        XCTAssertFalse(decide(244, .dismissed))
        XCTAssertFalse(decide(244, .replaced))
        XCTAssertFalse(decide(244, .unknown))
        // 前の個体の補正込み 261 をホストが覚えていた回: 消え方によらず補わない(二重補正 278 の防止。3248)
        XCTAssertFalse(decide(261, .dismissed))
        XCTAssertFalse(decide(261, .replaced))
        XCTAssertFalse(decide(261, .unknown))
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
