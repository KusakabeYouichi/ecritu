import SwiftUI

enum FlickGuideDisplayMode: String {
    case off
    case fourDirections
    case down
}

enum LongPressCandidatePanelPlacement {
    case above
    case below
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
        static let secondaryFlickThreshold: CGFloat = 12
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
    var onCommitWithDirection: ((String, FlickDirection) -> Void)? = nil
    var mainLabelFontSize: CGFloat = 28
    var flickGuideDisplayModeOverride: FlickGuideDisplayMode? = nil
    var showsDirectionalHints: Bool = true
    var showsGuideText: Bool = true
    var idleReplacement: AnyView? = nil
    var longPressCandidates: [String] = []
    var longPressCandidatePanelPlacement: LongPressCandidatePanelPlacement = .above
    var onLongPress: (() -> Void)? = nil
    var allowsDirectionalFlick: Bool = true
    var directionalFlickThreshold: CGFloat = 18
    var directionalCommitThreshold: CGFloat? = nil
    var activePreviewFontSize: CGFloat = 24
    var activeMainLabelFontSizeProvider: ((FlickDirection, String) -> CGFloat)? = nil
    var activePreviewFontSizeProvider: ((FlickDirection, String) -> CGFloat)? = nil
    var activePreviewHorizontalPadding: CGFloat = 12
    var directionalHintHorizontalOffset: CGFloat = Metrics.directionHintHorizontalOffset
    var directionalHintFontScale: CGFloat = 1
    var downDirectionalHintFontScale: CGFloat = 1
    var downDirectionalHintVerticalOffsetAdjustment: CGFloat = 0
    var onTouchStateChanged: (Bool) -> Void = { _ in }

    @State private var activeDirection: FlickDirection = .milieu
    @State private var isTouching = false
    @State private var longPressIsActive = false
    @State private var highlightedLongPressIndex = 0
    @State private var longPressWorkItem: DispatchWorkItem?
    @State private var stuckTouchWatchdogWorkItem: DispatchWorkItem?
    @State private var didTriggerLongPressAction = false
    @State private var latestTouchLocationX: CGFloat = 0
    @State private var longPressAnchorLocationX: CGFloat = 0
    @State private var keyFrameInGlobal: CGRect = .zero
    @State private var secondaryFlickPrimaryDirection: FlickDirection?
    @State private var secondaryFlickVerticalDirection: FlickDirection?
    @State private var secondaryFlickAnchorTranslation: CGSize = .zero
    @GestureState private var isGestureInProgress = false
    @Environment(\.keyboardAccentColor) private var accentColor
    @Environment(\.flickGuideDisplayMode) private var flickGuideDisplayMode
    @Environment(\.flickDirectionProfile) private var flickDirectionProfile

    private let keyLabelColor = KeyboardThemePalette.keyLabel

    private var effectiveFlickGuideDisplayMode: FlickGuideDisplayMode {
        flickGuideDisplayModeOverride ?? flickGuideDisplayMode
    }

    private var centerLabelOffsetY: CGFloat {
        effectiveFlickGuideDisplayMode == .down ? -6 : 0
    }

    private var idleMainLabelFontSize: CGFloat {
        effectiveFlickGuideDisplayMode == .down ? min(mainLabelFontSize, 24) : mainLabelFontSize
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Metrics.keyCornerRadius, style: .continuous)
                .fill(isTouching ? accentColor.opacity(0.85) : KeyboardThemePalette.keyBackground)

            RoundedRectangle(cornerRadius: Metrics.keyCornerRadius, style: .continuous)
                .stroke(KeyboardThemePalette.keyBorder, lineWidth: 1)

            if isTouching {
                Text(displayText)
                    .font(
                        .system(
                            size: resolvedActiveMainLabelFontSize(for: activeDirection),
                            weight: .bold,
                            design: .rounded
                        )
                    )
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

            if isTouching,
                !longPressIsActive,
                (activeDirection != .milieu || secondaryFlickPrimaryDirection != nil) {
                Text(displayText)
                    .font(
                        .system(
                            size: resolvedActivePreviewFontSize(for: activeDirection),
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .allowsTightening(true)
                    .foregroundStyle(.white)
                    .padding(.horizontal, activePreviewHorizontalPadding)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(accentColor.opacity(0.95)))
                    .offset(resolvedPreviewOffset)
            }

            if longPressIsActive,
                !longPressCandidates.isEmpty {
                longPressCandidatePanel
                    .offset(x: candidatePanelOffsetX, y: candidatePanelOffsetY)
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
        .onChange(of: isGestureInProgress) { inProgress in
            if !inProgress {
                finalizeTouchInteractionState()
            }
        }
        .onDisappear {
            finalizeTouchInteractionState()
        }
        .zIndex(isTouching ? KeyboardLayerZIndex.touchingKey : 0)
    }

    private var displayText: String {
        if longPressIsActive,
            !longPressCandidates.isEmpty,
            longPressCandidates.indices.contains(highlightedLongPressIndex) {
            return longPressCandidates[highlightedLongPressIndex]
        }

        if let secondaryOutput = resolvedSecondaryFlickOutput {
            return secondaryOutput
        }

        if let primaryDirection = secondaryFlickPrimaryDirection {
            return kana.output(for: primaryDirection)
        }

        return kana.output(for: activeDirection)
    }

    private var resolvedSecondaryFlickOutput: String? {
        guard let primaryDirection = secondaryFlickPrimaryDirection,
            let verticalDirection = secondaryFlickVerticalDirection else {
            return nil
        }

        return FlickKanaLayout.secondaryBracketFlickOutput(
            forPrimaryOutput: kana.output(for: primaryDirection),
            verticalDirection: verticalDirection
        )
    }

    private var resolvedPreviewOffset: CGSize {
        if let primaryDirection = secondaryFlickPrimaryDirection {
            let xOffset = primaryDirection == .gauche ? -Metrics.previewDistance : Metrics.previewDistance

            if let verticalDirection = secondaryFlickVerticalDirection,
                resolvedSecondaryFlickOutput != nil {
                let yOffset = verticalDirection == .haut ? -Metrics.previewDistance : Metrics.previewDistance
                return CGSize(width: xOffset, height: yOffset)
            }

            return CGSize(width: xOffset, height: 0)
        }

        return previewOffset(for: activeDirection)
    }

    private func resolvedActiveMainLabelFontSize(for direction: FlickDirection) -> CGFloat {
        let currentText = kana.output(for: direction)

        if let activeMainLabelFontSizeProvider {
            return activeMainLabelFontSizeProvider(direction, currentText)
        }

        return mainLabelFontSize
    }

    private func resolvedActivePreviewFontSize(for direction: FlickDirection) -> CGFloat {
        let previewText = kana.output(for: direction)

        if let activePreviewFontSizeProvider {
            return activePreviewFontSizeProvider(direction, previewText)
        }

        return activePreviewFontSize
    }

    private func previewOffset(for direction: FlickDirection) -> CGSize {
        switch direction {
        case .milieu:
            return CGSize(width: 0, height: -Metrics.previewDistance)
        case .haut:
            return CGSize(width: 0, height: -Metrics.previewDistance)
        case .droite:
            return CGSize(width: Metrics.previewDistance, height: 0)
        case .bas:
            return CGSize(width: 0, height: Metrics.previewDistance)
        case .gauche:
            return CGSize(width: -Metrics.previewDistance, height: 0)
        }
    }

    private var directionalHints: some View {
        ZStack {
            directionalHintText(kana.up, direction: .haut)
                .offset(y: -Metrics.directionHintVerticalOffset)

            directionalHintText(kana.down, direction: .bas)
                .offset(y: Metrics.directionHintVerticalOffset)

            directionalHintText(kana.left, direction: .gauche)
                .offset(x: -directionalHintHorizontalOffset)

            directionalHintText(kana.right, direction: .droite)
                .offset(x: directionalHintHorizontalOffset)
        }
        .allowsHitTesting(false)
        .opacity(
            isTouching
                || !showsGuideText
                || !showsDirectionalHints
                || effectiveFlickGuideDisplayMode != .fourDirections
                ? 0.0
                : 1.0
        )
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
        .offset(y: Metrics.directionHintVerticalOffset + downDirectionalHintVerticalOffsetAdjustment)
        .allowsHitTesting(false)
        .opacity(isTouching || !showsGuideText || effectiveFlickGuideDisplayMode != .down ? 0.0 : 1.0)
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
            return .system(size: scaledDirectionalHintSize(25), weight: .bold, design: .rounded)
        }

        if text == "小" {
            return .system(size: scaledDirectionalHintSize(6), weight: .semibold, design: .rounded)
        }

        switch text.count {
        case 7...:
            return .system(size: scaledDirectionalHintSize(6), weight: .medium, design: .rounded)
        case 5...6:
            return .system(size: scaledDirectionalHintSize(7), weight: .medium, design: .rounded)
        case 3...4:
            return .system(size: scaledDirectionalHintSize(8), weight: .semibold, design: .rounded)
        case 2:
            return .system(size: scaledDirectionalHintSize(9), weight: .semibold, design: .rounded)
        default:
            return .system(size: scaledDirectionalHintSize(10), weight: .semibold, design: .rounded)
        }
    }

    private var downDirectionalHintTexts: [String] {
        kana.orderedDirectionalGuideTexts(for: flickDirectionProfile)
    }

    private func downDirectionalHintFont(for text: String) -> Font {
        if isDakutenGuideText(text) {
            return .system(size: scaledDownDirectionalHintSize(12), weight: .bold, design: .rounded)
        }

        if text == "小" {
            return .system(size: scaledDownDirectionalHintSize(6), weight: .semibold, design: .rounded)
        }

        switch text.count {
        case 7...:
            return .system(size: scaledDownDirectionalHintSize(5), weight: .medium, design: .rounded)
        case 5...6:
            return .system(size: scaledDownDirectionalHintSize(6), weight: .medium, design: .rounded)
        case 3...4:
            return .system(size: scaledDownDirectionalHintSize(7), weight: .semibold, design: .rounded)
        case 2:
            return .system(size: scaledDownDirectionalHintSize(8), weight: .semibold, design: .rounded)
        default:
            return .system(size: scaledDownDirectionalHintSize(9), weight: .semibold, design: .rounded)
        }
    }

    private func scaledDirectionalHintSize(_ baseSize: CGFloat) -> CGFloat {
        baseSize * directionalHintFontScale
    }

    private func scaledDownDirectionalHintSize(_ baseSize: CGFloat) -> CGFloat {
        scaledDirectionalHintSize(baseSize) * downDirectionalHintFontScale
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
        case .haut:
            baseOffset = CGSize(width: 4, height: 8)
        case .gauche:
            baseOffset = CGSize(width: 8, height: 4)
        case .droite:
            baseOffset = CGSize(width: 4, height: 4)
        case .bas:
            baseOffset = CGSize(width: 4, height: 4)
        case .milieu:
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
                    .foregroundStyle(KeyboardThemePalette.longPressPanelText)
                    .frame(width: cellWidth, height: Metrics.candidateCellHeight)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                index == highlightedLongPressIndex
                                    ? KeyboardThemePalette.longPressPanelCellHighlight
                                    : KeyboardThemePalette.longPressPanelCellBackground
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(KeyboardThemePalette.keyBorder, lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, Metrics.candidatePanelPadding)
        .padding(.vertical, Metrics.candidatePanelVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: Metrics.keyCornerRadius, style: .continuous)
                .fill(KeyboardThemePalette.longPressPanelBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.keyCornerRadius, style: .continuous)
                .stroke(KeyboardThemePalette.longPressPanelBorder, lineWidth: 1)
        )
        .shadow(color: KeyboardThemePalette.longPressPanelShadow, radius: 4, y: 1)
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

    private var candidatePanelOffsetY: CGFloat {
        switch longPressCandidatePanelPlacement {
        case .above:
            return -Metrics.previewDistance
        case .below:
            return Metrics.previewDistance
        }
    }

    private var flickGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isGestureInProgress) { _, state, _ in
                state = true
            }
            .onChanged { value in
                if !isTouching {
                    onTouchStateChanged(true)
                    didTriggerLongPressAction = false
                    scheduleLongPressIfNeeded()
                    resetSecondaryFlickState()
                    scheduleStuckTouchWatchdog()
                }
                isTouching = true
                latestTouchLocationX = value.location.x

                if didTriggerLongPressAction {
                    return
                }

                if longPressIsActive {
                    highlightedLongPressIndex = longPressIndex(for: value.location.x)
                    return
                }

                guard allowsDirectionalFlick else {
                    activeDirection = .milieu
                    resetSecondaryFlickState()
                    return
                }

                let resolvedDirection = FlickGestureResolver.resolve(
                    translation: value.translation,
                    threshold: directionalFlickThreshold
                )
                let effectiveResolvedDirection = effectiveDirection(for: resolvedDirection)
                activeDirection = effectiveResolvedDirection

                if onLongPress != nil,
                    longPressCandidates.isEmpty,
                    effectiveResolvedDirection != .milieu {
                    // Do not let long-press override a deliberate directional flick.
                    cancelLongPressTimer()
                }

                updateSecondaryFlickState(
                    translation: value.translation,
                    resolvedDirection: effectiveResolvedDirection
                )
            }
            .onEnded { value in
                cancelLongPressTimer()

                if didTriggerLongPressAction {
                    finalizeTouchInteractionState()
                    return
                }

                let committedDirection: FlickDirection = {
                    guard !longPressIsActive,
                        allowsDirectionalFlick,
                        let directionalCommitThreshold else {
                        return activeDirection
                    }

                    let resolvedDirection = FlickGestureResolver.resolve(
                        translation: value.translation,
                        threshold: directionalCommitThreshold
                    )
                    return effectiveDirection(for: resolvedDirection)
                }()

                let committedText: String
                let committedDirectionForCallback: FlickDirection

                if longPressIsActive,
                    !longPressCandidates.isEmpty,
                    longPressCandidates.indices.contains(highlightedLongPressIndex) {
                    committedText = longPressCandidates[highlightedLongPressIndex]
                    committedDirectionForCallback = committedDirection
                } else if let secondaryOutput = resolvedSecondaryFlickOutput,
                    let primaryDirection = secondaryFlickPrimaryDirection {
                    committedText = secondaryOutput
                    committedDirectionForCallback = primaryDirection
                } else if let primaryDirection = secondaryFlickPrimaryDirection {
                    committedText = kana.output(for: primaryDirection)
                    committedDirectionForCallback = primaryDirection
                } else {
                    committedText = kana.output(for: committedDirection)
                    committedDirectionForCallback = committedDirection
                }

                finalizeTouchInteractionState()

                if let onCommitWithDirection {
                    onCommitWithDirection(committedText, committedDirectionForCallback)
                } else {
                    onCommit(committedText)
                }
            }
    }

    private func effectiveDirection(for direction: FlickDirection) -> FlickDirection {
        guard direction != .milieu else {
            return .milieu
        }

        return kana.output(for: direction).isEmpty ? .milieu : direction
    }

    private func updateSecondaryFlickState(
        translation: CGSize,
        resolvedDirection: FlickDirection
    ) {
        if secondaryFlickPrimaryDirection == nil {
            guard resolvedDirection == .gauche || resolvedDirection == .droite else {
                return
            }

            let primaryOutput = kana.output(for: resolvedDirection)

            guard primaryOutput == "『" || primaryOutput == "』" else {
                return
            }

            secondaryFlickPrimaryDirection = resolvedDirection
            secondaryFlickVerticalDirection = nil
            secondaryFlickAnchorTranslation = translation
            return
        }

        guard let primaryDirection = secondaryFlickPrimaryDirection else {
            return
        }

        if (primaryDirection == .gauche && resolvedDirection == .droite)
            || (primaryDirection == .droite && resolvedDirection == .gauche) {
            resetSecondaryFlickState()
            return
        }

        let relativeTranslation = CGSize(
            width: translation.width - secondaryFlickAnchorTranslation.width,
            height: translation.height - secondaryFlickAnchorTranslation.height
        )
        let resolvedVerticalDirection = FlickGestureResolver.resolve(
            translation: relativeTranslation,
            threshold: Metrics.secondaryFlickThreshold
        )

        if resolvedVerticalDirection == .haut || resolvedVerticalDirection == .bas {
            secondaryFlickVerticalDirection = resolvedVerticalDirection
            return
        }

        secondaryFlickVerticalDirection = nil
    }

    private func resetSecondaryFlickState() {
        secondaryFlickPrimaryDirection = nil
        secondaryFlickVerticalDirection = nil
        secondaryFlickAnchorTranslation = .zero
    }

    private func scheduleLongPressIfNeeded() {
        guard !longPressCandidates.isEmpty || onLongPress != nil else {
            return
        }

        cancelLongPressTimer()

        let workItem = DispatchWorkItem {
            if let onLongPress {
                didTriggerLongPressAction = true
                onLongPress()
                return
            }

            longPressIsActive = true
            activeDirection = .milieu
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

    private func scheduleStuckTouchWatchdog() {
        // SwiftUI の @GestureState reset / .onEnded がメインスレッド過負荷等で
        // 取りこぼされ isTouching が残ってしまうケースのフェイルセーフ。
        // 既存タイマーをキャンセルして 1.2 秒後に「指は離れているのに isTouching=true」
        // の状態を検知したら強制的に押下表示を解除する。
        stuckTouchWatchdogWorkItem?.cancel()

        let workItem = DispatchWorkItem {
            if isTouching && !isGestureInProgress {
                finalizeTouchInteractionState()
            }
        }
        stuckTouchWatchdogWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
    }

    private func cancelStuckTouchWatchdog() {
        stuckTouchWatchdogWorkItem?.cancel()
        stuckTouchWatchdogWorkItem = nil
    }

    private func finalizeTouchInteractionState() {
        cancelLongPressTimer()
        cancelStuckTouchWatchdog()
        activeDirection = .milieu
        resetSecondaryFlickState()
        longPressIsActive = false
        latestTouchLocationX = 0
        longPressAnchorLocationX = 0
        didTriggerLongPressAction = false

        if isTouching {
            isTouching = false
            onTouchStateChanged(false)
        }
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
