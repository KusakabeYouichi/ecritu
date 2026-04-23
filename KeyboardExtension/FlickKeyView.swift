import SwiftUI

enum FlickGuideDisplayMode: String {
    case off
    case fourDirections
    case down
}

private struct KeyboardAccentColorKey: EnvironmentKey {
    static let defaultValue = Color(red: 0.06, green: 0.73, blue: 0.56)
}

private struct FlickGuideDisplayModeKey: EnvironmentKey {
    static let defaultValue: FlickGuideDisplayMode = .fourDirections
}

private struct FlickDirectionProfileKey: EnvironmentKey {
    static let defaultValue: FlickDirectionProfile = .ecritu
}

extension EnvironmentValues {
    var keyboardAccentColor: Color {
        get { self[KeyboardAccentColorKey.self] }
        set { self[KeyboardAccentColorKey.self] = newValue }
    }

    var flickGuideDisplayMode: FlickGuideDisplayMode {
        get { self[FlickGuideDisplayModeKey.self] }
        set { self[FlickGuideDisplayModeKey.self] = newValue }
    }

    var flickDirectionProfile: FlickDirectionProfile {
        get { self[FlickDirectionProfileKey.self] }
        set { self[FlickDirectionProfileKey.self] = newValue }
    }
}

struct FlickKeyView: View {
    private enum Metrics {
        static let keyCornerRadius: CGFloat = 10
        static let previewDistance: CGFloat = 44
        static let directionHintVerticalOffset: CGFloat = 16
        static let directionHintHorizontalOffset: CGFloat = 20

        static let longPressDelay: TimeInterval = 0.35
        static let candidateCellWidth: CGFloat = 34
        static let candidateCellHeight: CGFloat = 34
        static let candidateSpacing: CGFloat = 3
        static let candidatePanelPadding: CGFloat = 8
        static let candidatePanelVerticalPadding: CGFloat = 3
        static let candidatePanelContentInset: CGFloat = 16
        static let candidatePanelMinCellWidth: CGFloat = 24

        static let panelHorizontalMargin: CGFloat = 24
        static let panelSafetyInset: CGFloat = 10
        static let panelEdgeBuffer: CGFloat = 12
    }

    let kana: FlickKanaSet
    let onCommit: (String) -> Void
    var mainLabelFontSize: CGFloat = 28
    var showsDirectionalHints: Bool = true
    var idleReplacement: AnyView? = nil
    var longPressCandidates: [String] = []
    var allowsDirectionalFlick: Bool = true
    var onTouchStateChanged: (Bool) -> Void = { _ in }

    @State private var activeDirection: FlickDirection = .center
    @State private var isTouching = false
    @State private var longPressIsActive = false
    @State private var highlightedLongPressIndex = 0
    @State private var longPressWorkItem: DispatchWorkItem?
    @State private var latestTouchLocationX: CGFloat = 0
    @State private var longPressAnchorLocationX: CGFloat = 0
    @State private var keyFrameInGlobal: CGRect = .zero
    @Environment(\.keyboardAccentColor) private var accentColor
    @Environment(\.flickGuideDisplayMode) private var flickGuideDisplayMode
    @Environment(\.flickDirectionProfile) private var flickDirectionProfile

    private let keyLabelColor = Color(red: 0.11, green: 0.13, blue: 0.16)

    private var centerLabelOffsetY: CGFloat {
        flickGuideDisplayMode == .down ? -6 : 0
    }

    private var idleMainLabelFontSize: CGFloat {
        flickGuideDisplayMode == .down ? min(mainLabelFontSize, 24) : mainLabelFontSize
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Metrics.keyCornerRadius, style: .continuous)
                .fill(isTouching ? accentColor.opacity(0.85) : Color.white.opacity(0.95))

            RoundedRectangle(cornerRadius: Metrics.keyCornerRadius, style: .continuous)
                .stroke(Color.black.opacity(0.12), lineWidth: 1)

            if isTouching {
                Text(displayText)
                    .font(.system(size: mainLabelFontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
            } else if let idleReplacement {
                idleReplacement
                    .offset(y: centerLabelOffsetY)
            } else {
                Text(kana.center)
                    .font(.system(size: idleMainLabelFontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(keyLabelColor)
                    .offset(y: centerLabelOffsetY)
            }

            directionalHints
            downDirectionalHints

            if isTouching && activeDirection != .center && !longPressIsActive {
                Text(kana.output(for: activeDirection))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(accentColor.opacity(0.95)))
                    .offset(previewOffset)
            }

            if longPressIsActive,
                !longPressCandidates.isEmpty {
                longPressCandidatePanel
                    .offset(x: candidatePanelOffsetX, y: -Metrics.previewDistance)
                    .zIndex(KeyboardLayerZIndex.floatingOverlay)
            }
        }
        .contentShape(Rectangle())
        .gesture(flickGesture)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: FlickKeyFramePreferenceKey.self, value: proxy.frame(in: .global))
            }
        )
        .onPreferenceChange(FlickKeyFramePreferenceKey.self) { newValue in
            keyFrameInGlobal = newValue
        }
        .zIndex(isTouching ? KeyboardLayerZIndex.touchingKey : 0)
    }

    private var displayText: String {
        if longPressIsActive,
            !longPressCandidates.isEmpty,
            longPressCandidates.indices.contains(highlightedLongPressIndex) {
            return longPressCandidates[highlightedLongPressIndex]
        }

        return kana.output(for: activeDirection)
    }

    private var previewOffset: CGSize {
        switch activeDirection {
        case .center:
            return CGSize(width: 0, height: -Metrics.previewDistance)
        case .up:
            return CGSize(width: 0, height: -Metrics.previewDistance)
        case .right:
            return CGSize(width: Metrics.previewDistance, height: 0)
        case .down:
            return CGSize(width: 0, height: Metrics.previewDistance)
        case .left:
            return CGSize(width: -Metrics.previewDistance, height: 0)
        }
    }

    private var directionalHints: some View {
        ZStack {
            directionalHintText(kana.up, direction: .up)
                .offset(y: -Metrics.directionHintVerticalOffset)

            directionalHintText(kana.down, direction: .down)
                .offset(y: Metrics.directionHintVerticalOffset)

            directionalHintText(kana.left, direction: .left)
                .offset(x: -Metrics.directionHintHorizontalOffset)

            directionalHintText(kana.right, direction: .right)
                .offset(x: Metrics.directionHintHorizontalOffset)
        }
        .allowsHitTesting(false)
        .opacity(isTouching || !showsDirectionalHints || flickGuideDisplayMode != .fourDirections ? 0.0 : 1.0)
    }

    private var downDirectionalHints: some View {
        HStack(spacing: 2) {
            ForEach(Array(downDirectionalHintTexts.enumerated()), id: \.offset) { _, text in
                Text(text)
                    .font(downDirectionalHintFont(for: text))
                    .minimumScaleFactor(0.1)
                    .lineLimit(1)
                    .allowsTightening(true)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(keyLabelColor.opacity(0.55))
            }
        }
        .padding(.horizontal, 4)
        .offset(y: Metrics.directionHintVerticalOffset)
        .allowsHitTesting(false)
        .opacity(isTouching || flickGuideDisplayMode != .down ? 0.0 : 1.0)
    }

    @ViewBuilder
    private func directionalHintText(_ text: String, direction: FlickDirection) -> some View {
        if isModeSwitchHintText(text) {
            Text(text)
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.01)
                .lineLimit(1)
                .allowsTightening(true)
                .fixedSize(horizontal: true, vertical: false)
                .tracking(-0.2)
                .scaleEffect(0.32)
                .foregroundStyle(keyLabelColor.opacity(0.55))
                .offset(specialDirectionalHintOffset(for: text, direction: direction))
        } else {
            Text(text)
                .font(directionalHintFont(for: text))
                .minimumScaleFactor(0.1)
                .lineLimit(1)
                .allowsTightening(true)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(keyLabelColor.opacity(0.55))
                .offset(specialDirectionalHintOffset(for: text, direction: direction))
        }
    }

    private func isModeSwitchHintText(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return text == "123" || normalized == "abc"
    }

    private func directionalHintFont(for text: String) -> Font {
        if isDakutenGuideText(text) {
            return .system(size: 25, weight: .bold, design: .rounded)
        }

        if text == "小" {
            return .system(size: 6, weight: .semibold, design: .rounded)
        }

        switch text.count {
        case 7...:
            return .system(size: 6, weight: .medium, design: .rounded)
        case 5...6:
            return .system(size: 7, weight: .medium, design: .rounded)
        case 3...4:
            return .system(size: 8, weight: .semibold, design: .rounded)
        case 2:
            return .system(size: 9, weight: .semibold, design: .rounded)
        default:
            return .system(size: 10, weight: .semibold, design: .rounded)
        }
    }

    private var downDirectionalHintTexts: [String] {
        kana.orderedDirectionalGuideTexts(for: flickDirectionProfile)
    }

    private func downDirectionalHintFont(for text: String) -> Font {
        if isDakutenGuideText(text) {
            return .system(size: 12, weight: .bold, design: .rounded)
        }

        if text == "小" {
            return .system(size: 6, weight: .semibold, design: .rounded)
        }

        switch text.count {
        case 7...:
            return .system(size: 5, weight: .medium, design: .rounded)
        case 5...6:
            return .system(size: 6, weight: .medium, design: .rounded)
        case 3...4:
            return .system(size: 7, weight: .semibold, design: .rounded)
        case 2:
            return .system(size: 8, weight: .semibold, design: .rounded)
        default:
            return .system(size: 9, weight: .semibold, design: .rounded)
        }
    }

    private func isDakutenGuideText(_ text: String) -> Bool {
        text == "゛" || text == "゜"
    }

    private func specialDirectionalHintOffset(for text: String, direction: FlickDirection) -> CGSize {
        guard isDakutenGuideText(text) else {
            return .zero
        }

        let baseOffset: CGSize

        switch direction {
        case .up:
            baseOffset = CGSize(width: 4, height: 8)
        case .left:
            baseOffset = CGSize(width: 8, height: 4)
        case .right:
            baseOffset = CGSize(width: 4, height: 4)
        case .down:
            baseOffset = CGSize(width: 4, height: 4)
        case .center:
            baseOffset = CGSize(width: 4, height: 4)
        }

        // Keep the two marks visually distinct: handakuten slightly right/down,
        // dakuten slightly down to stay inside the key while preserving alignment.
        if text == "゜" {
            return CGSize(width: baseOffset.width + 1, height: baseOffset.height + 1)
        }

        if text == "゛" {
            return CGSize(width: baseOffset.width, height: baseOffset.height + 2)
        }

        return baseOffset
    }

    private var longPressCandidatePanel: some View {
        let cellWidth = effectiveCandidateCellWidth
        let candidateFontSize: CGFloat = cellWidth < 30 ? 18 : 20

        return HStack(spacing: Metrics.candidateSpacing) {
            ForEach(Array(longPressCandidates.enumerated()), id: \.offset) { index, candidate in
                Text(candidate)
                    .font(.system(size: candidateFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.9))
                    .frame(width: cellWidth, height: Metrics.candidateCellHeight)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(index == highlightedLongPressIndex ? Color(red: 0.84, green: 0.89, blue: 1.0) : Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, Metrics.candidatePanelPadding)
        .padding(.vertical, Metrics.candidatePanelVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: Metrics.keyCornerRadius, style: .continuous)
                .fill(Color(red: 0.97, green: 0.97, blue: 0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.keyCornerRadius, style: .continuous)
                .stroke(Color.black.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 4, y: 1)
        .allowsHitTesting(false)
    }

    private var candidatePanelWidth: CGFloat {
        let count = CGFloat(longPressCandidates.count)
        let contentWidth = count * effectiveCandidateCellWidth + max(0, count - 1) * Metrics.candidateSpacing
        return contentWidth + Metrics.candidatePanelContentInset
    }

    private var effectiveCandidateCellWidth: CGFloat {
        guard !longPressCandidates.isEmpty else {
            return Metrics.candidateCellWidth
        }

        let count = CGFloat(longPressCandidates.count)
        let sideInset = Metrics.panelHorizontalMargin + Metrics.panelSafetyInset + Metrics.panelEdgeBuffer
        let maxPanelWidth = UIScreen.main.bounds.width - sideInset * 2
        let availableContentWidth = maxPanelWidth - Metrics.candidatePanelContentInset - max(0, count - 1) * Metrics.candidateSpacing
        let maxCellWidth = floor(availableContentWidth / count)

        return max(Metrics.candidatePanelMinCellWidth, min(Metrics.candidateCellWidth, maxCellWidth))
    }

    private var candidatePanelOffsetX: CGFloat {
        guard keyFrameInGlobal.width > 0,
                !longPressCandidates.isEmpty else {
            return 0
        }

        let panelWidth = candidatePanelWidth
        let screenWidth = UIScreen.main.bounds.width
        let panelMinX = keyFrameInGlobal.midX - panelWidth * 0.5
        let panelMaxX = keyFrameInGlobal.midX + panelWidth * 0.5
        let minX = Metrics.panelHorizontalMargin + Metrics.panelSafetyInset + Metrics.panelEdgeBuffer
        let maxX = screenWidth - minX
        var shift: CGFloat = 0

        if panelMinX < minX {
            shift += minX - panelMinX
        }

        if panelMaxX > maxX {
            shift -= panelMaxX - maxX
        }

        return shift
    }

    private var flickGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isTouching {
                    onTouchStateChanged(true)
                    scheduleLongPressIfNeeded()
                }
                isTouching = true
                latestTouchLocationX = value.location.x

                if longPressIsActive {
                    highlightedLongPressIndex = longPressIndex(for: value.location.x)
                    return
                }

                guard allowsDirectionalFlick else {
                    activeDirection = .center
                    return
                }

                let resolvedDirection = FlickGestureResolver.resolve(translation: value.translation)
                activeDirection = effectiveDirection(for: resolvedDirection)
            }
            .onEnded { _ in
                cancelLongPressTimer()

                if longPressIsActive,
                    !longPressCandidates.isEmpty,
                    longPressCandidates.indices.contains(highlightedLongPressIndex) {
                    onCommit(longPressCandidates[highlightedLongPressIndex])
                } else {
                    onCommit(kana.output(for: activeDirection))
                }

                activeDirection = .center
                longPressIsActive = false
                isTouching = false
                latestTouchLocationX = 0
                longPressAnchorLocationX = 0
                onTouchStateChanged(false)
            }
    }

    private func effectiveDirection(for direction: FlickDirection) -> FlickDirection {
        guard direction != .center else {
            return .center
        }

        return kana.output(for: direction).isEmpty ? .center : direction
    }

    private func scheduleLongPressIfNeeded() {
        guard !longPressCandidates.isEmpty else {
            return
        }

        cancelLongPressTimer()

        let workItem = DispatchWorkItem {
            longPressIsActive = true
            activeDirection = .center
            longPressAnchorLocationX = latestTouchLocationX
            highlightedLongPressIndex = 0
        }

        longPressWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.longPressDelay, execute: workItem)
    }

    private func cancelLongPressTimer() {
        longPressWorkItem?.cancel()
        longPressWorkItem = nil
    }

    private func longPressIndex(for locationX: CGFloat) -> Int {
        guard !longPressCandidates.isEmpty else {
            return 0
        }

        let slotWidth = effectiveCandidateCellWidth + Metrics.candidateSpacing
        let rawIndex = Int(round((locationX - longPressAnchorLocationX) / slotWidth))

        return max(0, min(longPressCandidates.count - 1, rawIndex))
    }
}

private struct FlickKeyFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

#Preview {
    FlickKeyView(kana: FlickKanaLayout.fiveByTwoRows[0][0]) { _ in }
        .frame(width: 64, height: 58)
        .padding()
}
