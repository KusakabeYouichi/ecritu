import SwiftUI
import UIKit

// トラックパッド中に かな 3×3+わ(縦画面)へ重ねる『箱入りあひる』の盤(c10)。
// 横 5 列(c0=左のモード列、c1〜c3=かな、c4=右列)× 縦 4 段を、『箱入り娘』の初期配置を 90 度回して
// 出口(2 ます)を左に置いた盤に見立てる(ユーザ指定 3909)。出口は左の列の [abc][あいう](c0 の r1〜r2)。
// 駒はキーの枠でなく ます の格子で置く(⏎ の 2 段の枠や 🌐 の有無で配置は変わらない)。
// 主役のあひる(2×2)は濁点のあひると同じ線画。すべて線画で、色は薄く、画像ファイルは使わない
struct HakoiriDuckBoardLayout {
    enum Motif: Equatable {
        // 主役(娘の役)。濁点のあひるの線画
        case heroDuck
        // 親鳥(横長の駒)。主役と同じあひるの線画を縦横比を保って収める。mirrored は左右反転
        case parentDuck(mirrored: Bool)
        case feather
        case waterWithMaple
        case eggs
        case chick
    }

    struct Piece: Equatable {
        let columns: ClosedRange<Int>
        let rows: ClosedRange<Int>
        let motif: Motif
    }

    // 盤の外寸(格子と同じ大きさ)と、格子と同じ寸法値(左の列の幅・右の列の幅・キーの間隔)
    let size: CGSize
    let leftColumnWidth: CGFloat
    let rightColumnWidth: CGFloat
    let spacing: CGFloat

    // 縦画面・iPhone 17 の かなキーの幅(おおよそ)。線幅はこれを基準に比例させる
    static let referenceKanaKeyWidth: CGFloat = 80

    var kanaKeyWidth: CGFloat {
        max(0, (size.width - leftColumnWidth - rightColumnWidth - spacing * 4) / 3)
    }

    var rowHeight: CGFloat {
        max(0, (size.height - spacing * 3) / 4)
    }

    var lineScale: CGFloat {
        kanaKeyWidth / Self.referenceKanaKeyWidth
    }

    // 指定の列・段にまたがる長方形(キーの間隔を含む)
    func rect(columns: ClosedRange<Int>, rows: ClosedRange<Int>) -> CGRect {
        let minX = columnMinX(columns.lowerBound)
        let maxX = columnMinX(columns.upperBound) + columnWidth(columns.upperBound)
        let minY = CGFloat(rows.lowerBound) * (rowHeight + spacing)
        let maxY = CGFloat(rows.upperBound) * (rowHeight + spacing) + rowHeight
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func columnMinX(_ column: Int) -> CGFloat {
        switch column {
        case 0:
            return 0
        case 4:
            return size.width - rightColumnWidth
        default:
            return leftColumnWidth + spacing + CGFloat(column - 1) * (kanaKeyWidth + spacing)
        }
    }

    private func columnWidth(_ column: Int) -> CGFloat {
        switch column {
        case 0:
            return leftColumnWidth
        case 4:
            return rightColumnWidth
        default:
            return kanaKeyWidth
        }
    }

    // 出口の段(左の端の r1〜r2)。盤の外枠はここだけ開ける
    static let exitRows: ClosedRange<Int> = 1...2

    // 『箱入り娘』の初期配置を 90 度回したもの。空き 2 ます(c0 の r1・r2)は出口の前で、何も描かない
    //      c0     c1     c2     c3     c4
    // r0   ひよこ [ 水面+もみじ ] [ 親鳥       ]
    // r1   空き   ひよこ 羽根   [ 主役のあひる ]
    // r2   空き   ひよこ 羽根   [             ]
    // r3   ひよこ [ 卵 2 つ    ] [ 親鳥(反転) ]
    static let pieces: [Piece] = [
        Piece(columns: 3...4, rows: 1...2, motif: .heroDuck),
        Piece(columns: 1...2, rows: 0...0, motif: .waterWithMaple),
        Piece(columns: 3...4, rows: 0...0, motif: .parentDuck(mirrored: false)),
        Piece(columns: 2...2, rows: 1...2, motif: .feather),
        Piece(columns: 1...2, rows: 3...3, motif: .eggs),
        Piece(columns: 3...4, rows: 3...3, motif: .parentDuck(mirrored: true)),
        Piece(columns: 0...0, rows: 0...0, motif: .chick),
        Piece(columns: 1...1, rows: 1...1, motif: .chick),
        Piece(columns: 1...1, rows: 2...2, motif: .chick),
        Piece(columns: 0...0, rows: 3...3, motif: .chick),
    ]

    // 盤の外枠の縦の開き(出口)。上下の段との間隔の真ん中から真ん中まで
    var exitOpening: ClosedRange<CGFloat> {
        let top = CGFloat(Self.exitRows.lowerBound) * (rowHeight + spacing) - spacing / 2
        let bottom = CGFloat(Self.exitRows.upperBound) * (rowHeight + spacing) + rowHeight + spacing / 2
        return top...bottom
    }
}

// トラックパッド中だけ描く。盤は格子の .overlay に置き、ルートの body には触れない(改訂 2 の R6)
struct HakoiriDuckBoardOverlay: View {
    let leftColumnWidth: CGFloat
    let rightColumnWidth: CGFloat
    let spacing: CGFloat
    let ownerTag: String

    @ObservedObject private var trackpadDisplay = SpaceTrackpadDisplayState.shared

    var body: some View {
        if trackpadDisplay.isActive {
            Canvas { context, size in
                let line = KeyboardThemePalette.trackpadBoardLine.resolve(in: context.environment)
                trackpadDisplay.noteBoardDrawn(
                    size: size,
                    ownerTag: ownerTag,
                    appearance: "外観=\(context.environment.colorScheme == .dark ? "dark" : "light") 線="
                        + String(format: "%.2f,%.2f,%.2f,%.2f", line.red, line.green, line.blue, line.opacity)
                )
                let layout = HakoiriDuckBoardLayout(
                    size: size,
                    leftColumnWidth: leftColumnWidth,
                    rightColumnWidth: rightColumnWidth,
                    spacing: spacing
                )
                HakoiriDuckBoardDrawing.draw(
                    in: &context,
                    layout: layout,
                    pieces: HakoiriDuckBoardLayout.pieces,
                    color: KeyboardThemePalette.trackpadBoardLine
                )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

enum HakoiriDuckBoardDrawing {
    // 線幅(iPhone 17 の かなキー幅のとき)。あひる 3pt、ほかの駒 2pt
    static let heroLineWidth: CGFloat = 3
    static let pieceLineWidth: CGFloat = 2
    // 駒の輪郭をキーの枠の内側へ寄せる量と、輪郭から絵までの余白
    static let pieceInset: CGFloat = 3
    static let motifInset: CGFloat = 8
    static let pieceCornerRadius: CGFloat = 10
    // 盤の外枠(細め)
    static let boardLineWidth: CGFloat = 1.5

    static func draw(
        in context: inout GraphicsContext,
        layout: HakoiriDuckBoardLayout,
        pieces: [HakoiriDuckBoardLayout.Piece],
        color: Color
    ) {
        let scale = layout.lineScale
        guard scale > 0 else {
            return
        }
        drawBoardOutline(in: &context, layout: layout, color: color, scale: scale)
        for piece in pieces {
            let isHero = piece.motif == .heroDuck
            let lineWidth = (isHero ? heroLineWidth : pieceLineWidth) * scale
            let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            let pieceRect = layout.rect(columns: piece.columns, rows: piece.rows)
                .insetBy(dx: pieceInset * scale, dy: pieceInset * scale)
            context.stroke(
                Path(roundedRect: pieceRect, cornerRadius: pieceCornerRadius * scale, style: .continuous),
                with: .color(color),
                style: style
            )
            let motifRect = pieceRect.insetBy(dx: motifInset * scale, dy: motifInset * scale)
            guard motifRect.width > 0, motifRect.height > 0 else {
                continue
            }
            switch piece.motif {
            case .heroDuck:
                drawDuck(in: &context, rect: motifRect, mirrored: false, color: color, style: style)
            case .parentDuck(let mirrored):
                drawDuck(in: &context, rect: motifRect, mirrored: mirrored, color: color, style: style)
            case .feather:
                context.stroke(featherPath(in: motifRect), with: .color(color), style: style)
            case .waterWithMaple:
                context.stroke(wavesPath(in: motifRect), with: .color(color), style: style)
                context.stroke(maplePath(in: motifRect), with: .color(color), style: style)
            case .eggs:
                context.stroke(eggsPath(in: motifRect), with: .color(color), style: style)
            case .chick:
                context.stroke(chickPath(in: motifRect), with: .color(color), style: style)
            }
        }
    }

    // 盤の外枠(角の丸い長方形)。左の端の出口の段だけ開け、出口のますに小さな ← を置く
    private static func drawBoardOutline(
        in context: inout GraphicsContext,
        layout: HakoiriDuckBoardLayout,
        color: Color,
        scale: CGFloat
    ) {
        let lineWidth = boardLineWidth * scale
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        let board = CGRect(origin: .zero, size: layout.size).insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let radius = pieceCornerRadius * scale
        let opening = layout.exitOpening
        var outline = Path()
        outline.move(to: CGPoint(x: board.minX, y: opening.lowerBound))
        outline.addArc(tangent1End: CGPoint(x: board.minX, y: board.minY), tangent2End: CGPoint(x: board.maxX, y: board.minY), radius: radius)
        outline.addArc(tangent1End: CGPoint(x: board.maxX, y: board.minY), tangent2End: CGPoint(x: board.maxX, y: board.maxY), radius: radius)
        outline.addArc(tangent1End: CGPoint(x: board.maxX, y: board.maxY), tangent2End: CGPoint(x: board.minX, y: board.maxY), radius: radius)
        outline.addArc(tangent1End: CGPoint(x: board.minX, y: board.maxY), tangent2End: CGPoint(x: board.minX, y: board.minY), radius: radius)
        outline.addLine(to: CGPoint(x: board.minX, y: opening.upperBound))
        context.stroke(outline, with: .color(color), style: style)

        let exitRect = layout.rect(columns: 0...0, rows: HakoiriDuckBoardLayout.exitRows)
        let arrowLength = min(exitRect.width * 0.5, 18 * scale)
        let head = arrowLength * 0.35
        let tip = CGPoint(x: exitRect.midX - arrowLength / 2, y: exitRect.midY)
        var arrow = Path()
        arrow.move(to: CGPoint(x: tip.x + arrowLength, y: tip.y))
        arrow.addLine(to: tip)
        arrow.move(to: CGPoint(x: tip.x + head, y: tip.y - head))
        arrow.addLine(to: tip)
        arrow.addLine(to: CGPoint(x: tip.x + head, y: tip.y + head))
        context.stroke(arrow, with: .color(color), style: style)
    }

    // 濁点のあひる(duckOuter+くちばし+目)を rect に収める。目は輪と瞳
    private static func drawDuck(
        in context: inout GraphicsContext,
        rect: CGRect,
        mirrored: Bool,
        color: Color,
        style: StrokeStyle
    ) {
        let fitted = DakutenDuckVectorPaths.layout(in: rect.size)
        var transform = fitted.transform
        if mirrored {
            // x → 幅 - x(駒の中で左右反転)
            transform = transform.concatenating(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: rect.width, ty: 0))
        }
        transform = transform.concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY))
        context.stroke(DakutenDuckVectorPaths.duckOuter.applying(transform), with: .color(color), style: style)
        context.stroke(DakutenDuckVectorPaths.beak.applying(transform), with: .color(color), style: style)
        let eyeCenter = DakutenDuckVectorPaths.eyeCenter.applying(transform)
        let eyeRadius = DakutenDuckVectorPaths.eyeRingRadius * fitted.scale
        let pupilRadius = DakutenDuckVectorPaths.pupilRadius * fitted.scale
        context.stroke(
            Path(ellipseIn: CGRect(x: eyeCenter.x - eyeRadius, y: eyeCenter.y - eyeRadius, width: eyeRadius * 2, height: eyeRadius * 2)),
            with: .color(color),
            style: StrokeStyle(lineWidth: style.lineWidth * 0.6)
        )
        context.fill(
            Path(ellipseIn: CGRect(x: eyeCenter.x - pupilRadius, y: eyeCenter.y - pupilRadius, width: pupilRadius * 2, height: pupilRadius * 2)),
            with: .color(color)
        )
    }

    // rect の中に収めた正方形(中央寄せ)
    private static func square(in rect: CGRect) -> CGRect {
        let side = min(rect.width, rect.height)
        return CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
    }

    private static func point(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
    }

    // 羽根 1 枚(羽軸と、木の葉形の羽)。縦長の駒に合わせて縦に描く
    private static func featherPath(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height * 0.5)
        let box = CGRect(x: rect.midX - side / 2, y: rect.midY - side, width: side, height: side * 2)
        var path = Path()
        path.move(to: point(0.5, 0.04, in: box))
        path.addCurve(to: point(0.5, 0.82, in: box), control1: point(0.0, 0.25, in: box), control2: point(0.05, 0.7, in: box))
        path.addCurve(to: point(0.5, 0.04, in: box), control1: point(0.95, 0.7, in: box), control2: point(1.0, 0.25, in: box))
        path.move(to: point(0.5, 0.12, in: box))
        path.addLine(to: point(0.5, 0.98, in: box))
        // 羽の筋
        for y in [0.35, 0.5, 0.65] as [CGFloat] {
            path.move(to: point(0.5, y + 0.06, in: box))
            path.addLine(to: point(0.25, y - 0.04, in: box))
            path.move(to: point(0.5, y + 0.06, in: box))
            path.addLine(to: point(0.75, y - 0.04, in: box))
        }
        return path
    }

    // 水面の波線 3 本(駒の左 6 割)
    private static func wavesPath(in rect: CGRect) -> Path {
        let waveRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width * 0.6, height: rect.height)
        var path = Path()
        for y in [0.3, 0.55, 0.8] as [CGFloat] {
            let segments = 4
            let segmentWidth = waveRect.width / CGFloat(segments)
            let amplitude = min(rect.height * 0.08, segmentWidth * 0.25)
            var current = CGPoint(x: waveRect.minX, y: waveRect.minY + waveRect.height * y)
            path.move(to: current)
            for index in 0..<segments {
                let next = CGPoint(x: current.x + segmentWidth, y: current.y)
                let direction: CGFloat = index.isMultiple(of: 2) ? -1 : 1
                path.addQuadCurve(
                    to: next,
                    control: CGPoint(x: current.x + segmentWidth / 2, y: current.y + amplitude * 2 * direction)
                )
                current = next
            }
        }
        return path
    }

    // もみじ 1 枚(駒の右側に浮かべる)。5 つの裂片と葉柄
    private static func maplePath(in rect: CGRect) -> Path {
        let leafRect = square(in: CGRect(x: rect.minX + rect.width * 0.65, y: rect.minY, width: rect.width * 0.35, height: rect.height))
        let center = CGPoint(x: leafRect.midX, y: leafRect.midY - leafRect.height * 0.05)
        let outer = leafRect.width * 0.48
        let inner = leafRect.width * 0.2
        // 上から時計回りの裂片の向き(度。0 が真上)
        let lobes: [CGFloat] = [0, 58, 112, -112, -58].sorted()
        var path = Path()
        for (index, angle) in lobes.enumerated() {
            let tip = polar(center, radius: outer, degrees: angle)
            let nextAngle = index + 1 < lobes.count ? lobes[index + 1] : lobes[0] + 360
            let notch = polar(center, radius: inner, degrees: (angle + nextAngle) / 2)
            if index == 0 {
                path.move(to: tip)
            } else {
                path.addLine(to: tip)
            }
            path.addLine(to: notch)
        }
        path.closeSubpath()
        path.move(to: center)
        path.addLine(to: CGPoint(x: center.x, y: center.y + outer * 1.0))
        return path
    }

    private static func polar(_ center: CGPoint, radius: CGFloat, degrees: CGFloat) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: center.x + radius * sin(radians), y: center.y - radius * cos(radians))
    }

    // 卵 2 つ(縦長の楕円)
    private static func eggsPath(in rect: CGRect) -> Path {
        let eggHeight = rect.height
        let eggWidth = eggHeight * 0.78
        let gap = eggWidth * 0.5
        let totalWidth = eggWidth * 2 + gap
        let startX = rect.midX - totalWidth / 2
        var path = Path()
        path.addEllipse(in: CGRect(x: startX, y: rect.minY, width: eggWidth, height: eggHeight))
        path.addEllipse(in: CGRect(x: startX + eggWidth + gap, y: rect.minY, width: eggWidth, height: eggHeight))
        return path
    }

    // ひよこ(丸い頭+胴+小さいくちばし+目)。左向き
    private static func chickPath(in rect: CGRect) -> Path {
        let box = square(in: rect)
        var path = Path()
        // 胴
        path.addEllipse(in: CGRect(
            x: box.minX + box.width * 0.22,
            y: box.minY + box.height * 0.45,
            width: box.width * 0.7,
            height: box.height * 0.5
        ))
        // 頭
        let headCenter = point(0.38, 0.32, in: box)
        let headRadius = box.width * 0.2
        path.addEllipse(in: CGRect(
            x: headCenter.x - headRadius,
            y: headCenter.y - headRadius,
            width: headRadius * 2,
            height: headRadius * 2
        ))
        // くちばし
        path.move(to: CGPoint(x: headCenter.x - headRadius * 0.92, y: headCenter.y - headRadius * 0.2))
        path.addLine(to: CGPoint(x: headCenter.x - headRadius * 1.5, y: headCenter.y + headRadius * 0.05))
        path.addLine(to: CGPoint(x: headCenter.x - headRadius * 0.92, y: headCenter.y + headRadius * 0.3))
        // 目
        let eyeRadius = headRadius * 0.12
        path.addEllipse(in: CGRect(
            x: headCenter.x - headRadius * 0.35 - eyeRadius,
            y: headCenter.y - headRadius * 0.25 - eyeRadius,
            width: eyeRadius * 2,
            height: eyeRadius * 2
        ))
        return path
    }
}
