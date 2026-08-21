import XCTest
import UIKit

// 寸法・位置の端末別分岐(KeyboardLayoutMetrics)の回帰テスト(2609)。
//
// このテストの主目的は **iPhone の値を1ptも動かさないこと** の保証。
// iPad 側を調整するときは .pad だけを触り、ここが緑のままであることを確認する。
final class KeyboardLayoutMetricsTests: XCTestCase {
    private let allProfiles: [KeyboardViewController.PortraitHeightProfile] = [
        .kanaThreeByThree, .compactGrid, .compactActionRow, .kanaFiveByTwo, .emoji, .formattedNumber
    ]

    private func inputs(
        _ profile: KeyboardViewController.PortraitHeightProfile,
        landscape: Bool,
        shorterScreenEdge: CGFloat,
        bottomInset: CGFloat,
        hasExpandedHeader: Bool = false,
        usesKanaLandscapeHeightForCompactGrid: Bool = false
    ) -> KeyboardLayoutMetrics.HeightInputs {
        KeyboardLayoutMetrics.HeightInputs(
            profile: profile,
            isLandscapeOrientation: landscape,
            shorterScreenEdge: shorterScreenEdge,
            hasExpandedHeader: hasExpandedHeader,
            portraitBottomInset: bottomInset,
            usesKanaLandscapeHeightForCompactGrid: usesKanaLandscapeHeightForCompactGrid
        )
    }

    // MARK: - iPhone(リファクタ前の実装が返していた値をそのまま固定する)

    func testPhonePortraitHeightsAreUnchanged() {
        let metrics = KeyboardLayoutMetrics.phone
        let expected: [KeyboardViewController.PortraitHeightProfile: CGFloat] = [
            .kanaThreeByThree: 242,
            .compactGrid: 242,
            .compactActionRow: 242,
            .kanaFiveByTwo: 242,
            .emoji: 242,
            .formattedNumber: 332
        ]

        for profile in allProfiles {
            let height = metrics.preferredHeight(
                inputs(profile, landscape: false, shorterScreenEdge: 393, bottomInset: 34)
            )
            XCTAssertEqual(height, expected[profile], "profile=\(profile)")
        }
    }

    func testPhoneLandscapeHeightsAreUnchanged() {
        let metrics = KeyboardLayoutMetrics.phone
        let expected: [KeyboardViewController.PortraitHeightProfile: CGFloat] = [
            .kanaThreeByThree: 176,
            .compactGrid: 186,
            .compactActionRow: 176,
            .kanaFiveByTwo: 176,
            .emoji: 188,
            .formattedNumber: 230
        ]

        for profile in allProfiles {
            let height = metrics.preferredHeight(
                inputs(profile, landscape: true, shorterScreenEdge: 393, bottomInset: 34)
            )
            XCTAssertEqual(height, expected[profile], "profile=\(profile)")
        }
    }

    // 数字/ラテンフリックの compactGrid はかなと同じ横組み高さに揃える(既存挙動)。
    func testPhoneLandscapeCompactGridFollowsKanaWhenRequested() {
        let metrics = KeyboardLayoutMetrics.phone
        let height = metrics.preferredHeight(
            inputs(
                .compactGrid,
                landscape: true,
                shorterScreenEdge: 393,
                bottomInset: 34,
                usesKanaLandscapeHeightForCompactGrid: true
            )
        )
        XCTAssertEqual(height, 176)
    }

    func testPhoneStillUsesCompactLandscapeLayout() {
        XCTAssertTrue(KeyboardLayoutMetrics.phone.allowsCompactLandscapeLayout)
        XCTAssertTrue(
            KeyboardLayoutMetrics.phone.usesCompactLandscapeLayout(isLandscapeOrientation: true)
        )
        XCTAssertFalse(
            KeyboardLayoutMetrics.phone.usesCompactLandscapeLayout(isLandscapeOrientation: false)
        )
    }

    // 横組みの詰めた余白は iPhone だけのもの。
    func testPhoneLandscapeFrameIsCompact() {
        let metrics = KeyboardLayoutMetrics.phone
        let landscape = metrics.frame(usesCompactLandscapeLayout: true)
        XCTAssertEqual(landscape.rowSpacing, 4)
        XCTAssertEqual(landscape.bottomPadding, 4)
        XCTAssertEqual(landscape.actionKeyHeight, 34)
        let portrait = metrics.frame(usesCompactLandscapeLayout: false)
        XCTAssertEqual(portrait.rowSpacing, 6)
        XCTAssertEqual(portrait.bottomPadding, 20)
        XCTAssertEqual(portrait.actionKeyHeight, 42)
    }

    // MARK: - iPad(下段見切れの再発防止)

    // iPad は横画面でも段を詰めない。ビュー側の isLandscapeLayout も常に false になる。
    func testPadNeverUsesCompactLandscapeLayout() {
        XCTAssertFalse(KeyboardLayoutMetrics.pad.allowsCompactLandscapeLayout)
        XCTAssertFalse(
            KeyboardLayoutMetrics.pad.usesCompactLandscapeLayout(isLandscapeOrientation: true)
        )
    }

    // 本題: iPad の横画面は縦画面とまったく同じ高さになる。
    // 以前は横画面だけ横組みの枠(約190pt)に切り替わり、縦組みで描かれた下段が見切れていた。
    func testPadLandscapeHeightMatchesPortrait() {
        let metrics = KeyboardLayoutMetrics.pad
        // iPad mini 6 は 744x1133pt。短辺は向きに依らず 744。
        for profile in allProfiles {
            let portrait = metrics.preferredHeight(
                inputs(profile, landscape: false, shorterScreenEdge: 744, bottomInset: 20)
            )
            let landscape = metrics.preferredHeight(
                inputs(profile, landscape: true, shorterScreenEdge: 744, bottomInset: 20)
            )
            XCTAssertEqual(portrait, landscape, "profile=\(profile)")
        }
    }

    // 割り当てる枠が、実際に描かれる縦組みの中身より低くならないこと(=見切れない)。
    func testPadHeightCoversPortraitContent() {
        let metrics = KeyboardLayoutMetrics.pad
        for profile in allProfiles {
            let allocated = metrics.preferredHeight(
                inputs(profile, landscape: true, shorterScreenEdge: 744, bottomInset: 20)
            )
            let content = metrics.basePortraitHeight(profile: profile, hasExpandedHeader: false)
            XCTAssertGreaterThanOrEqual(allocated, content, "profile=\(profile) allocated=\(allocated) content=\(content)")
        }
    }

    // リファクタ前の iPad 縦画面(=正常だった側)の値を維持していること。
    func testPadPortraitHeightsAreUnchanged() {
        let metrics = KeyboardLayoutMetrics.pad
        let expected: [KeyboardViewController.PortraitHeightProfile: CGFloat] = [
            .kanaThreeByThree: 273,
            .compactGrid: 252,
            .compactActionRow: 260,
            .kanaFiveByTwo: 272,
            .emoji: 273,
            .formattedNumber: 340
        ]

        for profile in allProfiles {
            let height = metrics.preferredHeight(
                inputs(profile, landscape: false, shorterScreenEdge: 744, bottomInset: 20)
            )
            XCTAssertEqual(height, expected[profile], "profile=\(profile)")
        }
    }
}
