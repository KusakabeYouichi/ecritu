import Foundation
import SwiftUI

struct LatinShiftKeyButton: View {
    let isOn: Bool
    let isLocked: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void

    @Environment(\.keyboardAccentColor) private var accentColor
    @State private var didTriggerLongPress = false
    private let keyLabelColor = KeyboardThemePalette.keyLabel

    private var shiftSymbol: String {
        "⇧"
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
                Text(shiftSymbol)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(shiftForegroundColor)

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
    @State private var activeDirection: FlickDirection = .milieu
    @State private var isTouching = false

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
                .onChanged { value in
                    guard isEnabled else { return }

                    isTouching = true
                    let direction = FlickGestureResolver.resolve(translation: value.translation)
                    activeDirection = direction == .haut ? .haut : .milieu
                }
                .onEnded { _ in
                    defer {
                        isTouching = false
                        activeDirection = .milieu
                    }

                    guard isEnabled else { return }

                    if activeDirection == .haut {
                        onTab()
                    } else {
                        onSpace()
                    }
                }
        )
        .zIndex(isTouching ? KeyboardLayerZIndex.touchingKey : 0)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint("上フリックでタブ")
        .frame(width: fixedWidth)
    }
}

struct EmojiKeyButton: View {
    let emoji: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(emoji)
                .font(.system(size: 24))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(EmojiTapFeedbackButtonStyle())
        .accessibilityLabel(emoji)
    }
}

struct SymbolKeyButton: View {
    let symbol: String
    let font: Font
    let action: () -> Void

    init(
        symbol: String,
        font: Font = .system(size: 24, weight: .semibold, design: .rounded),
        action: @escaping () -> Void
    ) {
        self.symbol = symbol
        self.font = font
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(symbol)
                .font(font)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(EmojiTapFeedbackButtonStyle())
        .accessibilityLabel(symbol)
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
