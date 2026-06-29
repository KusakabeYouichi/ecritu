import Foundation
import SwiftUI
import UIKit

struct LatinShiftKeyButton: View {
    let isOn: Bool
    let isLocked: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void

    @Environment(\.keyboardAccentColor) private var accentColor
    @State private var didTriggerLongPress = false
    private let keyLabelColor = KeyboardThemePalette.keyLabel
    private let shiftSymbolHorizontalOffset: CGFloat = 1
    private let shiftSymbolVerticalOffset: CGFloat = 3

    private var shiftSymbolName: String {
        "shift.fill"
    }

    private var shiftBackgroundColor: Color {
        if isLocked {
            return accentColor
        }

        if isOn {
            return Color(red: 0.38, green: 0.52, blue: 0.88)
        }

        return KeyboardThemePalette.keyBackground
    }

    private var shiftForegroundColor: Color {
        (isOn || isLocked) ? Color.white : keyLabelColor
    }

    private var shiftBorderColor: Color {
        if isLocked {
            return KeyboardThemePalette.keyStrokeOnAccent.opacity(0.95)
        }

        if isOn {
            return KeyboardThemePalette.keyStrokeOnAccent
        }

        return KeyboardThemePalette.keyBorder
    }

    var body: some View {
        Button(action: {
            if didTriggerLongPress {
                didTriggerLongPress = false
                return
            }

            onTap()
        }) {
            VStack(spacing: 2) {
                Image(systemName: shiftSymbolName)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(shiftForegroundColor)
                    .offset(x: shiftSymbolHorizontalOffset, y: shiftSymbolVerticalOffset)

                Capsule()
                    .fill(shiftForegroundColor.opacity(isLocked ? 0.95 : 0))
                    .frame(width: 16, height: 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(shiftBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        shiftBorderColor,
                        lineWidth: isLocked ? 1.4 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4)
                .onEnded { _ in
                    didTriggerLongPress = true
                    onLongPress()
                }
        )
        .accessibilityLabel(isLocked ? "シフト ロック中" : "シフト")
    }
}

struct ActionKeyButton: View {
    let title: String
    var systemImageName: String? = nil
    var accessibilityLabel: String? = nil
    var fontSize: CGFloat = 16
    var titleOpacity: Double = 1
    var fixedWidth: CGFloat? = nil
    var isEnabled: Bool = true
    var onLongPress: (() -> Void)? = nil
    var onDoubleTap: (() -> Void)? = nil
    var doubleTapThreshold: TimeInterval = 0.28
    var prefersImmediateSingleTapWhenDoubleTapEnabled = false
    var repeatsWhileHolding = false
    var repeatInitialDelay: TimeInterval = 0.5
    var repeatInterval: TimeInterval = 0.1
    let action: () -> Void
    @State private var didTriggerLongPress = false
    @State private var pendingSingleTapWorkItem: DispatchWorkItem?
    @State private var lastImmediateSingleTapAt: Date?
    @State private var repeatStartWorkItem: DispatchWorkItem?
    @State private var repeatTimer: Timer?
    private let keyLabelColor = KeyboardThemePalette.keyLabel

    var body: some View {
        Button(action: {
            if didTriggerLongPress {
                didTriggerLongPress = false
                return
            }

            handleTapAction()
        }) {
            Group {
                if let systemImageName {
                    Image(systemName: systemImageName)
                        .font(.system(size: fontSize, weight: .semibold))
                } else {
                    Text(title)
                        .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                        .opacity(titleOpacity)
                }
            }
            .foregroundStyle(isEnabled ? keyLabelColor : KeyboardThemePalette.keyLabelSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isEnabled ? KeyboardThemePalette.keyBackground : KeyboardThemePalette.keyBackgroundDisabled)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(KeyboardThemePalette.keyBorder, lineWidth: 1)
            )
        }
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel ?? title)
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4)
                .onEnded { _ in
                    guard isEnabled,
                            !repeatsWhileHolding,
                            let onLongPress else {
                        return
                    }

                    cancelPendingSingleTapAction()
                    lastImmediateSingleTapAt = nil
                    didTriggerLongPress = true
                    onLongPress()
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard isEnabled,
                            repeatsWhileHolding else {
                        return
                    }

                    beginRepeatingActionIfNeeded()
                }
                .onEnded { _ in
                    cancelRepeatingActionStart()
                    stopRepeatingAction()
                }
        )
        .onDisappear {
            cancelPendingSingleTapAction()
            lastImmediateSingleTapAt = nil
            cancelRepeatingActionStart()
            stopRepeatingAction()
        }
        .frame(width: fixedWidth)
    }

    private func handleTapAction() {
        guard isEnabled else {
            return
        }

        guard !repeatsWhileHolding,
                let onDoubleTap else {
            action()
            return
        }

        if prefersImmediateSingleTapWhenDoubleTapEnabled {
            let now = Date()
            let safeThreshold = max(0.05, doubleTapThreshold)

            if let lastImmediateSingleTapAt,
                now.timeIntervalSince(lastImmediateSingleTapAt) <= safeThreshold {
                self.lastImmediateSingleTapAt = nil
                onDoubleTap()
                return
            }

            self.lastImmediateSingleTapAt = now
            action()
            return
        }

        if let pendingSingleTapWorkItem {
            pendingSingleTapWorkItem.cancel()
            self.pendingSingleTapWorkItem = nil
            onDoubleTap()
            return
        }

        let safeThreshold = max(0.05, doubleTapThreshold)

        let workItem = DispatchWorkItem {
            pendingSingleTapWorkItem = nil
            action()
        }

        pendingSingleTapWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + safeThreshold, execute: workItem)
    }

    private func cancelPendingSingleTapAction() {
        pendingSingleTapWorkItem?.cancel()
        pendingSingleTapWorkItem = nil
    }

    private func beginRepeatingActionIfNeeded() {
        guard repeatTimer == nil,
                repeatStartWorkItem == nil else {
            return
        }

        cancelPendingSingleTapAction()
        lastImmediateSingleTapAt = nil
        didTriggerLongPress = true
        action()
        scheduleRepeatingActionStartIfNeeded()
    }

    private func scheduleRepeatingActionStartIfNeeded() {
        guard repeatTimer == nil,
                repeatStartWorkItem == nil else {
            return
        }

        let safeInitialDelay = max(0, repeatInitialDelay)

        let workItem = DispatchWorkItem {
            startRepeatingAction()
            repeatStartWorkItem = nil
        }

        repeatStartWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + safeInitialDelay, execute: workItem)
    }

    private func cancelRepeatingActionStart() {
        repeatStartWorkItem?.cancel()
        repeatStartWorkItem = nil
    }

    private func startRepeatingAction() {
        stopRepeatingAction()

        let safeRepeatInterval = max(0.01, repeatInterval)

        let timer = Timer(timeInterval: safeRepeatInterval, repeats: true) { _ in
            action()
        }

        RunLoop.main.add(timer, forMode: .common)
        repeatTimer = timer
    }

    private func stopRepeatingAction() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }
}

struct SpaceFlickActionKeyButton: View {
    let title: String
    var titleOpacity: Double = 1
    var fixedWidth: CGFloat? = nil
    var isEnabled: Bool = true
    var accessibilityLabelText: String = "空白"
    let onSpace: () -> Void
    let onTab: () -> Void

    @Environment(\.keyboardAccentColor) private var accentColor
    @GestureState private var isGestureInProgress = false
    @State private var activeDirection: FlickDirection = .milieu
    @State private var isTouching = false
    @State private var stuckTouchWatchdogWorkItem: DispatchWorkItem?

    private let keyLabelColor = KeyboardThemePalette.keyLabel
    private let tabPreviewText = "⇥"

    private var displayText: String {
        activeDirection == .haut ? tabPreviewText : title
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    isEnabled
                        ? (isTouching ? accentColor.opacity(0.85) : KeyboardThemePalette.keyBackground)
                        : KeyboardThemePalette.keyBackgroundDisabled
                )

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(KeyboardThemePalette.keyBorder, lineWidth: 1)

            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(isEnabled ? keyLabelColor : KeyboardThemePalette.keyLabelSecondary)
                .opacity(activeDirection == .haut ? 0 : titleOpacity)

            if isTouching {
                Text(displayText)
                    .font(
                        .system(
                            size: activeDirection == .haut ? 22 : 16,
                            weight: activeDirection == .haut ? .bold : .semibold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.white)
                    .opacity(titleOpacity)
            }

            if isTouching && activeDirection == .haut {
                Text(tabPreviewText)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(accentColor.opacity(0.95)))
                    .overlay(
                        Capsule()
                            .stroke(KeyboardThemePalette.keyStrokeOnAccent, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.16), radius: 1.5, y: 1)
                    .offset(y: -44)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isGestureInProgress) { _, state, _ in
                    state = true
                }
                .onChanged { value in
                    guard isEnabled else { return }

                    if !isTouching {
                        scheduleStuckTouchWatchdog()
                    }
                    isTouching = true
                    let direction = FlickGestureResolver.resolve(translation: value.translation)
                    activeDirection = direction == .haut ? .haut : .milieu
                }
                .onEnded { _ in
                    defer {
                        finalizeTouchInteractionState()
                    }

                    guard isEnabled else { return }

                    if activeDirection == .haut {
                        onTab()
                    } else {
                        onSpace()
                    }
                }
        )
        .onChange(of: isGestureInProgress) { inProgress in
            if !inProgress {
                finalizeTouchInteractionState()
            }
        }
        .onDisappear {
            finalizeTouchInteractionState()
        }
        .zIndex(isTouching ? KeyboardLayerZIndex.touchingKey : 0)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint("上フリックでタブ")
        .frame(width: fixedWidth)
    }

    private func scheduleStuckTouchWatchdog() {
        // FlickKeyView と同じく、.onEnded / @GestureState reset がメインスレッド
        // 過負荷で取りこぼされ isTouching が残るケースのフェイルセーフ。
        // 1.2 秒後に「指は離れているのに isTouching=true」なら強制解除する。
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
        cancelStuckTouchWatchdog()
        activeDirection = .milieu
        if isTouching {
            isTouching = false
        }
    }
}

struct EmojiKeyButton: View {
    let emoji: String
    let longPressLabel: String?
    let action: () -> Void

    init(emoji: String, longPressLabel: String? = nil, action: @escaping () -> Void) {
        self.emoji = emoji
        self.longPressLabel = longPressLabel
        self.action = action
    }

    var body: some View {
        Group {
            if let longPressLabel {
                Button(action: action) { emojiLabel }
                    .buttonStyle(SymbolInspectButtonStyle(label: longPressLabel))
            } else {
                Button(action: action) { emojiLabel }
                    .buttonStyle(EmojiTapFeedbackButtonStyle())
            }
        }
        .accessibilityLabel(accessibilityText)
    }

    private var emojiLabel: some View {
        Text(emoji)
            .font(.system(size: 24))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
    }

    private var accessibilityText: String {
        guard let longPressLabel else {
            return emoji
        }
        return "\(emoji) \(longPressLabel)"
    }
}

struct SymbolKeyButton: View {
    let symbol: String
    let font: Font
    let longPressLabel: String?
    let action: () -> Void

    init(
        symbol: String,
        font: Font = .system(size: 24, weight: .semibold, design: .rounded),
        longPressLabel: String? = nil,
        action: @escaping () -> Void
    ) {
        self.symbol = symbol
        self.font = font
        self.longPressLabel = longPressLabel
        self.action = action
    }

    var body: some View {
        Group {
            if let longPressLabel {
                Button(action: action) { symbolLabel }
                    .buttonStyle(SymbolInspectButtonStyle(label: longPressLabel))
            } else {
                Button(action: action) { symbolLabel }
                    .buttonStyle(EmojiTapFeedbackButtonStyle())
            }
        }
        .accessibilityLabel(accessibilityText)
    }

    private var symbolLabel: some View {
        Text(symbol)
            .font(font)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
    }

    private var accessibilityText: String {
        guard let longPressLabel else {
            return symbol
        }
        return "\(symbol) \(longPressLabel)"
    }
}

// 通貨記号/国旗用: 押している間だけ通貨コード・ティッカー・国名を吹き出し表示する。
// ScrollView 内でも確実に発火するよう、ジェスチャーではなく isPressed で駆動する。
private struct SymbolInspectButtonStyle: ButtonStyle {
    let label: String

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.84 : 1)
            .background(
                Circle()
                    .fill(configuration.isPressed ? KeyboardThemePalette.pressFeedbackCircle : Color.clear)
                    .frame(width: 24, height: 24)
            )
            .overlay {
                if configuration.isPressed {
                    SymbolInspectBubbleOverlay(text: label)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .zIndex(configuration.isPressed ? 1 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

// キー上に吹き出しを配置する。なるべく1行で表示し、画面端に当たる場合は内側へずらす。
// 1行で最大幅を超える長い名前(バチカン等)のみ2行に折り返す。
private struct SymbolInspectBubbleOverlay: View {
    let text: String

    private let maxBubbleWidth: CGFloat = 320
    private let screenMargin: CGFloat = 6
    private let horizontalPadding: CGFloat = 10
    private let verticalOffset: CGFloat = -36

    // 1行表示に必要なテキスト幅を UIFont で実測する。
    private var idealTextWidth: CGFloat {
        var font = UIFont.systemFont(ofSize: 13, weight: .bold)
        if let descriptor = font.fontDescriptor.withDesign(.rounded) {
            font = UIFont(descriptor: descriptor, size: 13)
        }
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    var body: some View {
        let maxTextWidth = maxBubbleWidth - horizontalPadding * 2
        let textWidth = min(idealTextWidth, maxTextWidth)
        let bubbleWidth = textWidth + horizontalPadding * 2

        GeometryReader { proxy in
            let keyFrame = proxy.frame(in: .global)
            let screenWidth = UIScreen.main.bounds.width
            let half = bubbleWidth / 2
            let keyCenterX = keyFrame.midX
            // 吹き出し中心を画面内[margin+half, width-margin-half]にクランプし、はみ出しを内側へずらす。
            let clampedCenterX = min(
                max(keyCenterX, screenMargin + half),
                max(screenMargin + half, screenWidth - screenMargin - half)
            )
            let dx = clampedCenterX - keyCenterX

            SymbolLongPressBubble(text: text, textWidth: textWidth)
                .frame(width: proxy.size.width, alignment: .center)
                .offset(x: dx, y: verticalOffset)
        }
    }
}

private struct SymbolLongPressBubble: View {
    let text: String
    let textWidth: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: textWidth)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.black.opacity(0.82))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(KeyboardThemePalette.keyStrokeOnAccent, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 2, y: 1)
    }
}

struct EmojiTapFeedbackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.84 : 1)
            .background(
                Circle()
                    .fill(configuration.isPressed ? KeyboardThemePalette.pressFeedbackCircle : Color.clear)
                    .frame(width: 24, height: 24)
            )
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

struct KaomojiKeyButton: View {
    let kaomoji: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(kaomoji)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(KaomojiTapFeedbackButtonStyle())
        .accessibilityLabel(kaomoji)
    }
}

struct KaomojiTapFeedbackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(configuration.isPressed ? KeyboardThemePalette.pressFeedbackRounded : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        configuration.isPressed ? KeyboardThemePalette.pressFeedbackRoundedBorder : Color.clear,
                        lineWidth: 1
                    )
            )
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

struct EmojiCategoryKeyButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    private let keyLabelColor = KeyboardThemePalette.keyLabel

    var body: some View {
        Button(action: action) {
            Text(icon)
                .font(.system(size: 18))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            isSelected
                                ? KeyboardThemePalette.categoryButtonBackgroundSelected
                                : KeyboardThemePalette.categoryButtonBackground
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            isSelected
                                ? KeyboardThemePalette.keyBorderEmphasis
                                : KeyboardThemePalette.keyBorder,
                            lineWidth: isSelected ? 1.4 : 1
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(icon)
    }
}

struct SymbolCategoryKeyButton: View {
    let icon: String
    let tintColor: Color
    let isSelected: Bool
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(icon)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? tintColor : tintColor.opacity(0.8))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            isSelected
                                ? tintColor.opacity(0.22)
                                : KeyboardThemePalette.categoryButtonBackground
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            isSelected
                                ? tintColor.opacity(0.75)
                                : KeyboardThemePalette.keyBorder,
                            lineWidth: isSelected ? 1.4 : 1
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct KaomojiCategoryKeyButton: View {
    let icon: String
    let accessibilityLabel: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(icon)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(
                isSelected
                    ? KeyboardThemePalette.keyLabel
                    : KeyboardThemePalette.keyLabelSecondary
            )
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isSelected
                            ? KeyboardThemePalette.categoryButtonBackgroundSelected
                            : KeyboardThemePalette.categoryButtonBackground
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected
                            ? KeyboardThemePalette.keyBorderEmphasis
                            : KeyboardThemePalette.keyBorder,
                        lineWidth: isSelected ? 1.4 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
