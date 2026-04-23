import Foundation
import SwiftUI

struct DakutenDuckCompositeIconView: View {
    var showsDakutenMark = false
    var showsHandakutenMark = false
    var isSmallKanaMode = false

    var body: some View {
        GeometryReader { proxy in
            let layout = DakutenDuckVectorPaths.layout(in: proxy.size)
            let scale = layout.scale
            let transform = layout.transform
            let eyeRingCenter = CGPoint(x: 497.7, y: 322.1).applying(transform)
            let eyeRingRadius = 25.2 * scale
            let pupilRadius = 13.9 * scale
            let eyeHighlightCenter = CGPoint(x: 491.1, y: 315.0).applying(transform)
            let eyeHighlightRadius = 4.5 * scale
            let shiftKeyBlue = Color(red: 0.38, green: 0.52, blue: 0.88)
            let duckStrokeColor = isSmallKanaMode
                ? shiftKeyBlue
                : Color(red: 0.11, green: 0.13, blue: 0.16)
            let overlayColor = shiftKeyBlue
            let handakutenVisualOffset = CGAffineTransform(translationX: 3, y: -4)

            ZStack {
                DakutenDuckVectorPaths.duckOuter
                    .applying(transform)
                    .stroke(
                        duckStrokeColor,
                        style: StrokeStyle(
                            lineWidth: max(1.2, 20 * scale),
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )

                DakutenDuckVectorPaths.beak
                    .applying(transform)
                    .stroke(
                        duckStrokeColor,
                        style: StrokeStyle(
                            lineWidth: max(1.1, 16 * scale),
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )

                Path(
                    ellipseIn: CGRect(
                        x: eyeRingCenter.x - eyeRingRadius,
                        y: eyeRingCenter.y - eyeRingRadius,
                        width: eyeRingRadius * 2,
                        height: eyeRingRadius * 2
                    )
                )
                .stroke(
                    duckStrokeColor,
                    style: StrokeStyle(lineWidth: max(1.0, 12 * scale))
                )

                Path(
                    ellipseIn: CGRect(
                        x: eyeRingCenter.x - pupilRadius,
                        y: eyeRingCenter.y - pupilRadius,
                        width: pupilRadius * 2,
                        height: pupilRadius * 2
                    )
                )
                .fill(duckStrokeColor)

                Path(
                    ellipseIn: CGRect(
                        x: eyeHighlightCenter.x - eyeHighlightRadius,
                        y: eyeHighlightCenter.y - eyeHighlightRadius,
                        width: eyeHighlightRadius * 2,
                        height: eyeHighlightRadius * 2
                    )
                )
                .fill(Color.white)

                if showsHandakutenMark {
                    DakutenDuckVectorPaths.handakutenHaloBand
                        .applying(transform)
                        .applying(handakutenVisualOffset)
                        .fill(
                            overlayColor,
                            style: FillStyle(eoFill: true, antialiased: true)
                        )

                    DakutenDuckVectorPaths.handakutenHaloOuter
                        .applying(transform)
                        .applying(handakutenVisualOffset)
                        .stroke(
                            overlayColor,
                            style: StrokeStyle(
                                lineWidth: max(0.9, 8 * scale),
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )

                    DakutenDuckVectorPaths.handakutenHaloInner
                        .applying(transform)
                        .applying(handakutenVisualOffset)
                        .stroke(
                            overlayColor,
                            style: StrokeStyle(
                                lineWidth: max(0.8, 6 * scale),
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                }

                if showsDakutenMark {
                    DakutenDuckVectorPaths.sweatLarge
                        .applying(transform)
                        .stroke(
                            overlayColor,
                            style: StrokeStyle(
                                lineWidth: max(1.0, 14 * scale),
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )

                    DakutenDuckVectorPaths.sweatSmall
                        .applying(transform)
                        .stroke(
                            overlayColor,
                            style: StrokeStyle(
                                lineWidth: max(1.0, 14 * scale),
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )

                    DakutenDuckVectorPaths.sweatLargeHighlight
                        .applying(transform)
                        .stroke(
                            overlayColor,
                            style: StrokeStyle(
                                lineWidth: max(0.8, 7 * scale),
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )

                    DakutenDuckVectorPaths.sweatSmallHighlight
                        .applying(transform)
                        .stroke(
                            overlayColor,
                            style: StrokeStyle(
                                lineWidth: max(0.8, 7 * scale),
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .allowsHitTesting(false)
    }
}

enum DakutenDuckVectorPaths {
    static let viewBox = CGSize(width: 1391, height: 1391)

    static let duckOuter = SVGPathMiniParser.path(
        from: """
        M 658.0 35.0 L 704.0 36.0 L 755.0 46.0 L 799.0 62.0 L 837.0 83.0 L 914.0 143.0 L 949.0 182.0 L 971.0 215.0 L 992.0 258.0 L 1005.0 300.0 L 1013.0 343.0 L 1012.0 394.0 L 998.0 464.0 L 972.0 523.0 L 951.0 553.0 L 952.0 560.0 L 1063.0 608.0 L 1145.0 630.0 L 1180.0 631.0 L 1261.0 613.0 L 1302.0 617.0 L 1329.0 630.0 L 1347.0 649.0 L 1359.0 668.0 L 1357.0 672.0 L 1362.0 674.0 L 1378.0 734.0 L 1380.0 817.0 L 1372.0 873.0 L 1350.0 946.0 L 1331.0 996.0 L 1303.0 1047.0 L 1241.0 1135.0 L 1201.0 1182.0 L 1139.0 1244.0 L 1069.0 1293.0 L 983.0 1337.0 L 935.0 1353.0 L 856.0 1369.0 L 797.0 1374.0 L 712.0 1374.0 L 629.0 1367.0 L 560.0 1354.0 L 432.0 1317.0 L 354.0 1285.0 L 301.0 1256.0 L 198.0 1184.0 L 137.0 1128.0 L 89.0 1070.0 L 54.0 1009.0 L 32.0 953.0 L 12.0 848.0 L 12.0 787.0 L 16.0 765.0 L 30.0 715.0 L 47.0 674.0 L 80.0 612.0 L 122.0 562.0 L 198.0 504.0 L 302.0 451.0 L 285.0 423.0 L 248.0 383.0 L 216.0 338.0 L 172.0 256.0 L 169.0 236.0 L 163.0 226.0 L 160.0 179.0 L 165.0 226.0 L 178.0 268.0 L 185.0 276.0 L 173.0 244.0 L 164.0 199.0 L 164.0 171.0 L 177.0 134.0 L 200.0 103.0 L 240.0 79.0 L 293.0 76.0 L 329.0 85.0 L 299.0 74.0 L 249.0 73.0 L 215.0 87.0 L 202.0 97.0 L 224.0 81.0 L 247.0 73.0 L 298.0 73.0 L 403.0 105.0 L 433.0 106.0 L 488.0 90.0 L 512.0 72.0 L 556.0 54.0 L 626.0 38.0 L 657.0 36.0 L 658.0 35.0 Z
        """
    )

    static let beak = SVGPathMiniParser.path(
        from: """
        M 253.0 76.0 L 301.0 77.0 L 408.0 108.0 L 447.0 106.0 L 472.0 95.0 L 490.0 91.0 L 479.0 108.0 L 455.0 135.0 L 448.0 139.0 L 443.0 151.0 L 433.0 156.0 L 418.0 173.0 L 413.0 185.0 L 406.0 190.0 L 410.0 193.0 L 391.0 209.0 L 389.0 216.0 L 383.0 218.0 L 383.0 234.0 L 373.0 239.0 L 365.0 270.0 L 360.0 273.0 L 354.0 319.0 L 355.0 372.0 L 357.0 389.0 L 363.0 402.0 L 370.0 433.0 L 371.0 448.0 L 369.0 478.0 L 363.0 481.0 L 362.0 487.0 L 353.0 490.0 L 344.0 498.0 L 337.0 495.0 L 324.0 476.0 L 315.0 470.0 L 314.0 464.0 L 300.0 447.0 L 287.0 423.0 L 265.0 400.0 L 227.0 346.0 L 218.0 338.0 L 218.0 333.0 L 193.0 295.0 L 173.0 244.0 L 164.0 199.0 L 164.0 171.0 L 174.0 139.0 L 200.0 103.0 L 223.0 87.0 L 240.0 79.0 L 252.0 77.0 L 253.0 76.0 Z
        """
    )

    static let sweatLarge = rotated(
        SVGPathMiniParser.path(
            from: """
            M 852 96 C 904 94 946 154 942 228 C 938 292 900 347 852 357 C 817 363 793 335 794 293 C 796 230 821 160 852 96 Z
            """
        ),
        degrees: -24,
        around: CGPoint(x: 866, y: 228)
    )
    .applying(sweatOffset)

    static let sweatSmall = rotated(
        SVGPathMiniParser.path(
            from: """
            M 1006 72 C 1062 72 1109 134 1104 213 C 1099 280 1061 337 1009 349 C 970 357 942 330 943 289 C 944 222 971 146 1006 72 Z
            """
        ),
        degrees: -24,
        around: CGPoint(x: 1028, y: 206)
    )
    .applying(sweatOffset)

    static let sweatLargeHighlight = rotated(
        SVGPathMiniParser.path(
            from: """
            M 853 129 C 832 164 823 206 828 244
            """
        ),
        degrees: -24,
        around: CGPoint(x: 866, y: 228)
    )
    .applying(sweatOffset)

    static let sweatSmallHighlight = rotated(
        SVGPathMiniParser.path(
            from: """
            M 1008 109 C 987 143 977 186 983 225
            """
        ),
        degrees: -24,
        around: CGPoint(x: 1028, y: 206)
    )
    .applying(sweatOffset)

    static let handakutenHaloOuter = rotated(
        Path(
            ellipseIn: CGRect(
                x: 535,
                y: 70,
                width: 650,
                height: 260
            )
        ),
        degrees: 24,
        around: CGPoint(x: 860, y: 200)
    )

    static let handakutenHaloInner = rotated(
        Path(
            ellipseIn: CGRect(
                x: 642.5,
                y: 122.5,
                width: 435,
                height: 155
            )
        ),
        degrees: 24,
        around: CGPoint(x: 860, y: 200)
    )

    static let handakutenHaloBand: Path = {
        var path = Path()
        path.addPath(handakutenHaloOuter)
        path.addPath(handakutenHaloInner)
        return path
    }()

    private static let sweatOffset = CGAffineTransform(translationX: 244, y: -40)

    static func layout(in size: CGSize) -> (scale: CGFloat, transform: CGAffineTransform) {
        let scale = min(size.width / viewBox.width, size.height / viewBox.height)
        let offsetX = (size.width - viewBox.width * scale) * 0.5
        let offsetY = (size.height - viewBox.height * scale) * 0.5

        let transform = CGAffineTransform(translationX: offsetX, y: offsetY)
            .scaledBy(x: scale, y: scale)

        return (scale, transform)
    }

    private static func rotated(_ path: Path, degrees: CGFloat, around center: CGPoint) -> Path {
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: center.x, y: center.y)
        transform = transform.rotated(by: degrees * .pi / 180)
        transform = transform.translatedBy(x: -center.x, y: -center.y)
        return path.applying(transform)
    }
}

enum SVGPathMiniParser {
    private static let tokenRegex = try! NSRegularExpression(
        pattern: #"[A-Za-z]|[-+]?(?:\d*\.\d+|\d+)(?:[eE][-+]?\d+)?"#,
        options: []
    )

    static func path(from data: String) -> Path {
        let tokens = tokenize(data)
        var path = Path()
        var index = 0
        var command: Character = "M"
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero

        func toNumber(_ token: String) -> CGFloat? {
            guard let value = Double(token) else {
                return nil
            }
            return CGFloat(value)
        }

        while index < tokens.count {
            if isCommand(tokens[index]) {
                command = Character(tokens[index])
                index += 1
            }

            let isRelative = command.isLowercase
            let upperCommand = Character(String(command).uppercased())

            switch upperCommand {
            case "M":
                guard index + 1 < tokens.count,
                        let x = toNumber(tokens[index]),
                        let y = toNumber(tokens[index + 1]) else {
                    break
                }

                let start = point(x: x, y: y, relativeTo: current, isRelative: isRelative)
                path.move(to: start)
                current = start
                subpathStart = start
                index += 2

                // Implicit subsequent line commands after M/m.
                while index + 1 < tokens.count, !isCommand(tokens[index]) {
                    guard let lineX = toNumber(tokens[index]),
                            let lineY = toNumber(tokens[index + 1]) else {
                        break
                    }

                    let next = point(x: lineX, y: lineY, relativeTo: current, isRelative: isRelative)
                    path.addLine(to: next)
                    current = next
                    index += 2
                }

            case "L":
                while index + 1 < tokens.count, !isCommand(tokens[index]) {
                    guard let x = toNumber(tokens[index]),
                            let y = toNumber(tokens[index + 1]) else {
                        break
                    }

                    let next = point(x: x, y: y, relativeTo: current, isRelative: isRelative)
                    path.addLine(to: next)
                    current = next
                    index += 2
                }

            case "C":
                while index + 5 < tokens.count, !isCommand(tokens[index]) {
                    guard let x1 = toNumber(tokens[index]),
                            let y1 = toNumber(tokens[index + 1]),
                            let x2 = toNumber(tokens[index + 2]),
                            let y2 = toNumber(tokens[index + 3]),
                            let x = toNumber(tokens[index + 4]),
                            let y = toNumber(tokens[index + 5]) else {
                        break
                    }

                    let control1 = point(x: x1, y: y1, relativeTo: current, isRelative: isRelative)
                    let control2 = point(x: x2, y: y2, relativeTo: current, isRelative: isRelative)
                    let destination = point(x: x, y: y, relativeTo: current, isRelative: isRelative)
                    path.addCurve(to: destination, control1: control1, control2: control2)
                    current = destination
                    index += 6
                }

            case "Z":
                path.closeSubpath()
                current = subpathStart

            default:
                // Skip unsupported commands defensively.
                if index < tokens.count {
                    index += 1
                }
            }
        }

        return path
    }

    private static func tokenize(_ input: String) -> [String] {
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        let matches = tokenRegex.matches(in: input, options: [], range: range)

        return matches.compactMap { match in
            guard let tokenRange = Range(match.range, in: input) else {
                return nil
            }
            return String(input[tokenRange])
        }
    }

    private static func isCommand(_ token: String) -> Bool {
        guard token.count == 1, let char = token.first else {
            return false
        }
        return char.isLetter
    }

    private static func point(x: CGFloat, y: CGFloat, relativeTo current: CGPoint, isRelative: Bool) -> CGPoint {
        guard isRelative else {
            return CGPoint(x: x, y: y)
        }
        return CGPoint(x: current.x + x, y: current.y + y)
    }
}
