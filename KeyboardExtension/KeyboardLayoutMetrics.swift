import CoreGraphics
import UIKit

// 寸法・位置の端末別分岐をここ1か所に集約する(2609)。
//
// 分岐の理由: iPad の横画面は verticalSizeClass が .regular なので、ビュー側の
// isLandscapeLayout(= .compact 判定)は false のまま「縦組みの背の高いレイアウト」を描く。
// ところが高さ計算側は interfaceOrientation.isLandscape で横組みと判定し、
// iPhone 用の低い枠(約190pt)しか確保しないため下段が見切れていた。
// 「レイアウトの向き判定」と「高さの向き判定」を metrics 側の1つの旗
// (allowsCompactLandscapeLayout)に統一して食い違いを構造的に断つ。
//
// 方針: .phone の値は既存コードからの逐語コピーで、iPhone の見た目は1ptも変えない
// (KeyboardLayoutMetricsTests が全プロファイル×向きで旧実装の値を固定している)。
// iPad の調整は .pad の側だけを触れば済み、iPhone には波及しない。
enum KeyboardDeviceKind {
    case phone
    case pad

    static func resolve(_ traitCollection: UITraitCollection) -> KeyboardDeviceKind {
        traitCollection.userInterfaceIdiom == .pad ? .pad : .phone
    }
}

struct KeyboardLayoutMetrics {
    // 段の高さ・余白。縦組み/横組みで別の値を持つ。
    struct FrameMetrics {
        var rowSpacing: CGFloat
        var horizontalPadding: CGFloat
        var bottomPadding: CGFloat
        var actionKeyHeight: CGFloat
        // かな/数字/ラテン3x3 は上余白を殺して段を稼ぐ(横組み専用の詰め)。
        var topPadding: CGFloat
        var topPaddingWhenRowsAreDense: CGFloat
    }

    // 横組み(段を詰めた背の低い構成)への切り替えを許すか。
    // iPad は画面高に余裕があり、Apple 純正も横画面で段を詰めないので false。
    // これが false のとき、ビューも高さ計算も向きに依らず縦組みとして扱う。
    var allowsCompactLandscapeLayout: Bool

    var portrait: FrameMetrics
    var landscape: FrameMetrics

    // 高さ計算(KeyboardViewController+Layout)側のノブ。
    var candidateHeaderExpandedHeight: CGFloat
    var candidateHeaderCollapsedHeight: CGFloat
    var keyboardVerticalPadding: CGFloat
    var keyboardRowSpacing: CGFloat
    var mainKeyRowHeight: CGFloat
    var actionRowHeight: CGFloat
    var portraitSystemAccessoryOffset: CGFloat
    var baselinePortraitScreenWidth: CGFloat
    var baselineLandscapeScreenHeight: CGFloat
    var portraitScaleRange: ClosedRange<CGFloat>
    var landscapeScaleRange: ClosedRange<CGFloat>

    // プロファイル別の高さ表。辞書ではなく関数にして case の網羅を型で担保する。
    var portraitHeightBounds: (KeyboardViewController.PortraitHeightProfile) -> ClosedRange<CGFloat>
    var landscapeHeightBounds: (KeyboardViewController.PortraitHeightProfile) -> ClosedRange<CGFloat>
    var baseLandscapeHeight: (KeyboardViewController.PortraitHeightProfile) -> CGFloat
    var portraitHeightFineTuning: (KeyboardViewController.PortraitHeightProfile) -> CGFloat

    static func metrics(for kind: KeyboardDeviceKind) -> KeyboardLayoutMetrics {
        switch kind {
        case .phone:
            return .phone
        case .pad:
            return .pad
        }
    }

    /// 横組みレイアウトを使うかの唯一の判定。ビューと高さ計算の両方がこれを呼ぶ。
    func usesCompactLandscapeLayout(isLandscapeOrientation: Bool) -> Bool {
        allowsCompactLandscapeLayout && isLandscapeOrientation
    }

    func frame(usesCompactLandscapeLayout: Bool) -> FrameMetrics {
        usesCompactLandscapeLayout ? landscape : portrait
    }
}

extension KeyboardLayoutMetrics {
    // MARK: - iPhone(既存値の逐語コピー。変更禁止 — 変えるときは回帰テストごと)

    static let phone = KeyboardLayoutMetrics(
        allowsCompactLandscapeLayout: true,
        portrait: FrameMetrics(
            rowSpacing: 6,
            horizontalPadding: 8,
            bottomPadding: 20,
            actionKeyHeight: 42,
            topPadding: 3,
            topPaddingWhenRowsAreDense: 3
        ),
        landscape: FrameMetrics(
            rowSpacing: 4,
            horizontalPadding: 6,
            bottomPadding: 4,
            actionKeyHeight: 34,
            topPadding: 1,
            topPaddingWhenRowsAreDense: 0
        ),
        candidateHeaderExpandedHeight: 35,
        candidateHeaderCollapsedHeight: 3,
        keyboardVerticalPadding: 23,
        keyboardRowSpacing: 6,
        mainKeyRowHeight: 46,
        actionRowHeight: 42,
        portraitSystemAccessoryOffset: 6,
        baselinePortraitScreenWidth: 390,
        baselineLandscapeScreenHeight: 393,
        portraitScaleRange: 0.92...1.08,
        landscapeScaleRange: 0.9...1.08,
        portraitHeightBounds: { profile in
            switch profile {
            case .kanaThreeByThree: return 220...280
            case .compactGrid: return 194...252
            case .compactActionRow: return 200...260
            case .kanaFiveByTwo: return 216...280
            case .emoji: return 228...290
            case .formattedNumber: return 300...340
            }
        },
        landscapeHeightBounds: { profile in
            switch profile {
            case .kanaThreeByThree: return 162...194
            case .compactGrid: return 172...204
            case .compactActionRow: return 162...194
            case .kanaFiveByTwo: return 162...194
            case .emoji: return 170...204
            case .formattedNumber: return 200...260
            }
        },
        baseLandscapeHeight: { profile in
            switch profile {
            case .kanaThreeByThree: return 176
            case .compactGrid: return 186
            case .compactActionRow: return 176
            case .kanaFiveByTwo: return 176
            case .emoji: return 188
            case .formattedNumber: return 230
            }
        },
        portraitHeightFineTuning: { profile in
            switch profile {
            case .kanaThreeByThree: return 46
            case .compactGrid: return 46
            case .compactActionRow: return 50
            case .kanaFiveByTwo: return 50
            case .emoji: return 46
            case .formattedNumber: return 46
            }
        }
    )

    // MARK: - iPad(ここだけを触れば iPhone に影響しない)

    static let pad: KeyboardLayoutMetrics = {
        var metrics = KeyboardLayoutMetrics.phone
        // iPad は横画面でも段を詰めない。ビュー(isLandscapeLayout)も高さ計算も
        // 常に縦組みとして扱われ、両者の食い違いが起きなくなる。
        metrics.allowsCompactLandscapeLayout = false
        // 横組みを使わないので landscape 側は参照されないが、取り違えたときに
        // iPhone の詰めた値が紛れ込まないよう縦組みと同じ値にしておく。
        metrics.landscape = metrics.portrait
        // 基準短辺(390)とスケール上限(1.08)は iPhone のまま据え置く。iPad の短辺は
        // 縦横どちらでも同じ(mini 6 なら 744)ので上限に張り付き、横画面は現に正常な
        // 縦画面と同一の高さになる。ここを iPad 基準に直すと縦画面が今より縮んで退行する。
        return metrics
    }()
}

extension KeyboardLayoutMetrics {
    // 高さ計算の入力。UIKit に触らない純粋な値だけを受け取るので単体テストできる
    // (KeyboardLayoutMetricsTests が iPhone の値を全プロファイル×向きで固定している)。
    struct HeightInputs {
        var profile: KeyboardViewController.PortraitHeightProfile
        var isLandscapeOrientation: Bool
        var shorterScreenEdge: CGFloat
        var hasExpandedHeader: Bool
        var portraitBottomInset: CGFloat
        // 数字/ラテンフリックの compactGrid はかなと同じ横組み高さに揃える。
        var usesKanaLandscapeHeightForCompactGrid: Bool
    }

    func headerHeight(hasExpandedHeader: Bool) -> CGFloat {
        hasExpandedHeader ? candidateHeaderExpandedHeight : candidateHeaderCollapsedHeight
    }

    /// 縦組みの基準高さ。ヘッダー + 段 + 段間 + 外周余白。
    func basePortraitHeight(
        profile: KeyboardViewController.PortraitHeightProfile,
        hasExpandedHeader: Bool
    ) -> CGFloat {
        let header = headerHeight(hasExpandedHeader: hasExpandedHeader)
        let spacing = keyboardRowSpacing
        let outer = header + spacing + spacing * 3 + keyboardVerticalPadding

        switch profile {
        case .kanaThreeByThree, .compactGrid, .emoji:
            // 主段4つ。
            return outer + mainKeyRowHeight * 4
        case .compactActionRow, .kanaFiveByTwo:
            // 主段3つ+アクション段。
            return outer + mainKeyRowHeight * 3 + actionRowHeight
        case .formattedNumber:
            // 単位ドラム/カレンダーに縦の余裕を持たせるため主段4つ+90。
            return outer + mainKeyRowHeight * 4 + 90
        }
    }

    func effectiveLandscapeProfile(
        _ profile: KeyboardViewController.PortraitHeightProfile,
        usesKanaLandscapeHeightForCompactGrid: Bool
    ) -> KeyboardViewController.PortraitHeightProfile {
        if profile == .compactGrid, usesKanaLandscapeHeightForCompactGrid {
            return .kanaThreeByThree
        }

        return profile
    }

    func preferredHeight(_ inputs: HeightInputs) -> CGFloat {
        if usesCompactLandscapeLayout(isLandscapeOrientation: inputs.isLandscapeOrientation) {
            let profile = effectiveLandscapeProfile(
                inputs.profile,
                usesKanaLandscapeHeightForCompactGrid: inputs.usesKanaLandscapeHeightForCompactGrid
            )
            let scale = clamp(
                inputs.shorterScreenEdge / baselineLandscapeScreenHeight,
                to: landscapeScaleRange
            )
            let bounds = landscapeHeightBounds(profile)
            return clamp(round(baseLandscapeHeight(profile) * scale), to: bounds)
        }

        let profile = inputs.profile
        let scale = clamp(
            inputs.shorterScreenEdge / baselinePortraitScreenWidth,
            to: portraitScaleRange
        )
        let scaled = round(
            basePortraitHeight(profile: profile, hasExpandedHeader: inputs.hasExpandedHeader) * scale
        )
        let headerCompensation = inputs.hasExpandedHeader
            ? candidateHeaderExpandedHeight - candidateHeaderCollapsedHeight
            : 0
        let adjusted = scaled
            - inputs.portraitBottomInset
            - portraitSystemAccessoryOffset
            + portraitHeightFineTuning(profile)
            - headerCompensation

        return clamp(adjusted, to: portraitHeightBounds(profile))
    }

    private func clamp(_ value: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
