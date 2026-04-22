import Foundation
import SwiftUI

struct LatinShiftKeyButton: View {
    let isOn: Bool
    let isLocked: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void

    @Environment(\.keyboardAccentColor) private var accentColor
    @State private var didTriggerLongPress = false
    private let keyLabelColor = Color(red: 0.11, green: 0.13, blue: 0.16)

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

        return Color.white.opacity(0.92)
    }

    private var shiftForegroundColor: Color {
        (isOn || isLocked) ? Color.white : keyLabelColor
    }

    private var shiftBorderColor: Color {
        if isLocked {
            return Color.white.opacity(0.62)
        }

        if isOn {
            return Color.white.opacity(0.35)
        }

        return Color.black.opacity(0.14)
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
    var repeatsWhileHolding = false
    var repeatInitialDelay: TimeInterval = 0.5
    var repeatInterval: TimeInterval = 0.1
    let action: () -> Void
    @State private var didTriggerLongPress = false
    @State private var repeatStartWorkItem: DispatchWorkItem?
    @State private var repeatTimer: Timer?
    private let keyLabelColor = Color(red: 0.11, green: 0.13, blue: 0.16)

    var body: some View {
        Button(action: {
            if didTriggerLongPress {
                didTriggerLongPress = false
                return
            }

            action()
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
            .foregroundStyle(isEnabled ? keyLabelColor : keyLabelColor.opacity(0.35))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isEnabled ? Color.white.opacity(0.92) : Color(white: 0.9).opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.black.opacity(0.14), lineWidth: 1)
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
            cancelRepeatingActionStart()
            stopRepeatingAction()
        }
        .frame(width: fixedWidth)
    }

    private func beginRepeatingActionIfNeeded() {
        guard repeatTimer == nil,
              repeatStartWorkItem == nil else {
            return
        }

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
    @State private var activeDirection: FlickDirection = .center
    @State private var isTouching = false

    private let keyLabelColor = Color(red: 0.11, green: 0.13, blue: 0.16)
    private let tabPreviewText = "⇥"

    private var displayText: String {
        activeDirection == .up ? tabPreviewText : title
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    isEnabled
                        ? (isTouching ? accentColor.opacity(0.85) : Color.white.opacity(0.92))
                        : Color(white: 0.9).opacity(0.92)
                )

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.black.opacity(0.14), lineWidth: 1)

            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(isEnabled ? keyLabelColor : keyLabelColor.opacity(0.35))
                .opacity(activeDirection == .up ? 0 : titleOpacity)

            if isTouching {
                Text(displayText)
                    .font(
                        .system(
                            size: activeDirection == .up ? 22 : 16,
                            weight: activeDirection == .up ? .bold : .semibold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.white)
                    .opacity(titleOpacity)
            }

            if isTouching && activeDirection == .up {
                Text(tabPreviewText)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(accentColor.opacity(0.95)))
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.32), lineWidth: 1)
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
                    activeDirection = direction == .up ? .up : .center
                }
                .onEnded { _ in
                    defer {
                        isTouching = false
                        activeDirection = .center
                    }

                    guard isEnabled else { return }

                    if activeDirection == .up {
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

struct EmojiTapFeedbackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.84 : 1)
            .background(
                Circle()
                    .fill(configuration.isPressed ? Color.black.opacity(0.15) : Color.clear)
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
                    .fill(configuration.isPressed ? Color.black.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        configuration.isPressed ? Color.black.opacity(0.16) : Color.clear,
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
    private let keyLabelColor = Color(red: 0.11, green: 0.13, blue: 0.16)

    var body: some View {
        Button(action: action) {
            Text(icon)
                .font(.system(size: 18))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            isSelected
                                ? Color.white.opacity(0.98)
                                : Color.white.opacity(0.78)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            isSelected
                                ? keyLabelColor.opacity(0.55)
                                : Color.black.opacity(0.11),
                            lineWidth: isSelected ? 1.4 : 1
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(icon)
    }
}
