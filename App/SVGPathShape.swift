import SwiftUI

// SVG の path データ(d 属性)を描く Shape。24x24 の viewBox 前提のアイコン用(3647)。
// 対応: M m L l H h V v C c A a Z z(暗黙の繰り返し含む)。メニューのアイコン 3 つ(Tabler / Lucide の
// 線画アイコン)が使う範囲だけで、S/Q/T は無い。線の太さと端の形は描く側(strokeStyle)で決める
struct SVGPathShape: Shape {
    let pathData: [String]
    var viewBoxSize: CGFloat = 24

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / viewBoxSize
        let offsetX = rect.minX + (rect.width - viewBoxSize * scale) / 2
        let offsetY = rect.minY + (rect.height - viewBoxSize * scale) / 2
        var result = Path()
        for data in pathData {
            result.addPath(Self.parse(data))
        }
        return result.applying(
            CGAffineTransform(translationX: offsetX, y: offsetY).scaledBy(x: scale, y: scale)
        )
    }

    // 数値(".5.5" のような詰め書きと "-.553" のような符号つきも 1 個ずつ切る)とコマンド文字に分ける
    private enum Token {
        case command(Character)
        case number(CGFloat)
    }

    private static func tokenize(_ data: String) -> [Token] {
        var tokens: [Token] = []
        let characters = Array(data)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character.isLetter {
                tokens.append(.command(character))
                index += 1
            } else if character == "-" || character == "+" || character == "." || character.isNumber {
                var end = index + 1
                var seenDot = character == "."
                while end < characters.count {
                    let next = characters[end]
                    if next.isNumber {
                        end += 1
                    } else if next == ".", !seenDot {
                        seenDot = true
                        end += 1
                    } else {
                        break
                    }
                }
                if let value = Double(String(characters[index..<end])) {
                    tokens.append(.number(CGFloat(value)))
                }
                index = end
            } else {
                index += 1
            }
        }
        return tokens
    }

    static func parse(_ data: String) -> Path {
        var path = Path()
        let tokens = tokenize(data)
        var position = 0
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var command: Character = " "

        func numbers(_ count: Int) -> [CGFloat]? {
            guard position + count <= tokens.count else {
                return nil
            }
            var values: [CGFloat] = []
            for offset in 0..<count {
                guard case .number(let value) = tokens[position + offset] else {
                    return nil
                }
                values.append(value)
            }
            position += count
            return values
        }

        while position < tokens.count {
            if case .command(let next) = tokens[position] {
                command = next
                position += 1
                if next == "Z" || next == "z" {
                    path.closeSubpath()
                    current = subpathStart
                    continue
                }
            }
            let isRelative = command.isLowercase
            let origin = isRelative ? current : .zero
            switch command {
            case "M", "m":
                guard let v = numbers(2) else { return path }
                current = CGPoint(x: origin.x + v[0], y: origin.y + v[1])
                subpathStart = current
                path.move(to: current)
                // 続く座標の組は暗黙の L
                command = isRelative ? "l" : "L"
            case "L", "l":
                guard let v = numbers(2) else { return path }
                current = CGPoint(x: origin.x + v[0], y: origin.y + v[1])
                path.addLine(to: current)
            case "H", "h":
                guard let v = numbers(1) else { return path }
                current = CGPoint(x: origin.x + v[0], y: current.y)
                path.addLine(to: current)
            case "V", "v":
                guard let v = numbers(1) else { return path }
                current = CGPoint(x: current.x, y: origin.y + v[0])
                path.addLine(to: current)
            case "C", "c":
                guard let v = numbers(6) else { return path }
                let c1 = CGPoint(x: origin.x + v[0], y: origin.y + v[1])
                let c2 = CGPoint(x: origin.x + v[2], y: origin.y + v[3])
                let end = CGPoint(x: origin.x + v[4], y: origin.y + v[5])
                path.addCurve(to: end, control1: c1, control2: c2)
                current = end
            case "A", "a":
                guard let v = numbers(7) else { return path }
                let end = CGPoint(x: origin.x + v[5], y: origin.y + v[6])
                addArc(
                    to: &path, from: current, radiusX: v[0], radiusY: v[1],
                    rotationDegrees: v[2], largeArc: v[3] != 0, sweep: v[4] != 0, end: end
                )
                current = end
            default:
                return path
            }
        }
        return path
    }

    // SVG の端点指定の円弧(仕様 F.6.5)を、90 度以下ごとの 3 次ベジェに分けて足す
    private static func addArc(
        to path: inout Path, from start: CGPoint, radiusX: CGFloat, radiusY: CGFloat,
        rotationDegrees: CGFloat, largeArc: Bool, sweep: Bool, end: CGPoint
    ) {
        var rx = abs(radiusX)
        var ry = abs(radiusY)
        guard start != end else {
            return
        }
        guard rx > 0, ry > 0 else {
            path.addLine(to: end)
            return
        }
        let phi = rotationDegrees * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)
        let halfDX = (start.x - end.x) / 2
        let halfDY = (start.y - end.y) / 2
        let x1 = cosPhi * halfDX + sinPhi * halfDY
        let y1 = -sinPhi * halfDX + cosPhi * halfDY

        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 {
            let factor = lambda.squareRoot()
            rx *= factor
            ry *= factor
        }

        let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var coefficient = denominator == 0 ? 0 : (max(0, numerator / denominator)).squareRoot()
        if largeArc == sweep {
            coefficient = -coefficient
        }
        let centerXPrime = coefficient * rx * y1 / ry
        let centerYPrime = -coefficient * ry * x1 / rx
        let centerX = cosPhi * centerXPrime - sinPhi * centerYPrime + (start.x + end.x) / 2
        let centerY = sinPhi * centerXPrime + cosPhi * centerYPrime + (start.y + end.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let length = (ux * ux + uy * uy).squareRoot() * (vx * vx + vy * vy).squareRoot()
            var value = acos(max(-1, min(1, dot / length)))
            if ux * vy - uy * vx < 0 {
                value = -value
            }
            return value
        }

        let startAngle = angle(1, 0, (x1 - centerXPrime) / rx, (y1 - centerYPrime) / ry)
        var sweepAngle = angle(
            (x1 - centerXPrime) / rx, (y1 - centerYPrime) / ry,
            (-x1 - centerXPrime) / rx, (-y1 - centerYPrime) / ry
        )
        if !sweep, sweepAngle > 0 {
            sweepAngle -= 2 * .pi
        } else if sweep, sweepAngle < 0 {
            sweepAngle += 2 * .pi
        }

        let segmentCount = max(1, Int((abs(sweepAngle) / (.pi / 2)).rounded(.up)))
        let delta = sweepAngle / CGFloat(segmentCount)
        let alpha = 4.0 / 3.0 * tan(delta / 4)

        func point(_ t: CGFloat) -> CGPoint {
            let x = rx * cos(t)
            let y = ry * sin(t)
            return CGPoint(x: cosPhi * x - sinPhi * y + centerX, y: sinPhi * x + cosPhi * y + centerY)
        }

        func derivative(_ t: CGFloat) -> CGPoint {
            let x = -rx * sin(t)
            let y = ry * cos(t)
            return CGPoint(x: cosPhi * x - sinPhi * y, y: sinPhi * x + cosPhi * y)
        }

        var t1 = startAngle
        for _ in 0..<segmentCount {
            let t2 = t1 + delta
            let p1 = point(t1)
            let d1 = derivative(t1)
            let p2 = point(t2)
            let d2 = derivative(t2)
            path.addCurve(
                to: p2,
                control1: CGPoint(x: p1.x + alpha * d1.x, y: p1.y + alpha * d1.y),
                control2: CGPoint(x: p2.x - alpha * d2.x, y: p2.y - alpha * d2.y)
            )
            t1 = t2
        }
    }
}

// メニューの初期設定 3 項目のアイコン(3647)。出どころと許諾は Open Source Notices に記載
//   戦略的: Tabler Icons chess-knight(MIT)/ 現代的: Lucide sparkles(ISC)/ 保守的: Lucide shield(ISC)
enum LogoMenuPresetIcon {
    case chessKnight
    case sparkles
    case shield

    var pathData: [String] {
        switch self {
        case .chessKnight:
            return [
                "M8 16l-1.447 .724a1 1 0 0 0 -.553 .894v2.382h12v-2.382a1 1 0 0 0 -.553 -.894l-1.447 -.724h-8z",
                "M9 3l1 3l-3.491 2.148a1 1 0 0 0 .524 1.852h2.967l-2.073 6h7.961l.112 -5c0 -3 -1.09 -5.983 -4 -7c-1.94 -.678 -2.94 -1.011 -3 -1z"
            ]
        case .sparkles:
            return [
                "M9.937 15.5A2 2 0 0 0 8.5 14.063l-6.135-1.582a.5.5 0 0 1 0-.962L8.5 9.936A2 2 0 0 0 9.937 8.5l1.582-6.135a.5.5 0 0 1 .963 0L14.063 8.5A2 2 0 0 0 15.5 9.937l6.135 1.581a.5.5 0 0 1 0 .964L15.5 14.063a2 2 0 0 0-1.437 1.437l-1.582 6.135a.5.5 0 0 1-.963 0z",
                "M20 3v4",
                "M22 5h-4",
                "M4 17v2",
                "M5 18H3"
            ]
        case .shield:
            return [
                "M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z"
            ]
        }
    }
}

struct LogoMenuPresetIconView: View {
    let icon: LogoMenuPresetIcon
    var size: CGFloat = 20

    var body: some View {
        SVGPathShape(pathData: icon.pathData)
            .stroke(style: StrokeStyle(lineWidth: size / 12, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}
