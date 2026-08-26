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
    // メモリ切迫の可視化(でばぐ表示)等、キー背景を状態色で塗り替えたいときに使う。
    var backgroundColorOverride: Color? = nil
    // キー左下隅の小さな注記(メモリ警告回数 等)。
    var cornerBadgeText: String? = nil
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
                    .fill(backgroundColorOverride
                        ?? (isEnabled ? KeyboardThemePalette.keyBackground : KeyboardThemePalette.keyBackgroundDisabled))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(KeyboardThemePalette.keyBorder, lineWidth: 1)
            )
            .overlay(alignment: .bottomLeading) {
                if let cornerBadgeText {
                    Text(cornerBadgeText)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(keyLabelColor)
                        .padding(.leading, 4)
                        .padding(.bottom, 2)
                }
            }
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
                KeyboardStuckTouchDiagnostics.onForceClear?("SpaceFlickActionKeyButton key=空白")
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
    let longPressLabelKind: SymbolInspectBubbleKind
    let action: () -> Void

    init(
        emoji: String,
        longPressLabel: String? = nil,
        longPressLabelKind: SymbolInspectBubbleKind = .standard,
        action: @escaping () -> Void
    ) {
        self.emoji = emoji
        self.longPressLabel = longPressLabel
        self.longPressLabelKind = longPressLabelKind
        self.action = action
    }

    var body: some View {
        Group {
            if let longPressLabel {
                Button(action: action) { emojiLabel }
                    .buttonStyle(SymbolInspectButtonStyle(label: longPressLabel, kind: longPressLabelKind))
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
    let longPressLabelKind: SymbolInspectBubbleKind
    let action: () -> Void

    init(
        symbol: String,
        font: Font = .system(size: 24, weight: .semibold, design: .rounded),
        longPressLabel: String? = nil,
        longPressLabelKind: SymbolInspectBubbleKind = .standard,
        action: @escaping () -> Void
    ) {
        self.symbol = symbol
        self.font = font
        self.longPressLabel = longPressLabel
        self.longPressLabelKind = longPressLabelKind
        self.action = action
    }

    var body: some View {
        Group {
            if let longPressLabel {
                Button(action: action) { symbolLabel }
                    .buttonStyle(SymbolInspectButtonStyle(label: longPressLabel, kind: longPressLabelKind))
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
// 吹き出しの色種別。通貨記号/ティッカー(黒)、非ISO国旗(青)、補助単位 cent/Pfennig(緑)。
enum SymbolInspectBubbleKind {
    case standard
    case alternate
    case subunit

    var bubbleColor: Color {
        switch self {
        case .standard: return Color.black.opacity(0.82)
        case .alternate: return Color(red: 0.12, green: 0.30, blue: 0.62).opacity(0.94)
        case .subunit: return Color(red: 0.10, green: 0.45, blue: 0.38).opacity(0.94)
        }
    }
}

private struct SymbolInspectButtonStyle: ButtonStyle {
    let label: String
    var kind: SymbolInspectBubbleKind = .standard

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
                    SymbolInspectBubbleOverlay(text: label, backgroundColor: kind.bubbleColor)
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
    var backgroundColor: Color = Color.black.opacity(0.82)

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

            SymbolLongPressBubble(text: text, textWidth: textWidth, backgroundColor: backgroundColor)
                .frame(width: proxy.size.width, alignment: .center)
                .offset(x: dx, y: verticalOffset)
        }
    }
}

private struct SymbolLongPressBubble: View {
    let text: String
    let textWidth: CGFloat
    var backgroundColor: Color = Color.black.opacity(0.82)

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
                    .fill(backgroundColor)
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

// ============================================================================
// 絵文字の描画を SwiftUI Text から UIKit(UILabel)へ(2668)
// ----------------------------------------------------------------------------
// メモリグラフ(simulator、8/26)で判明: SwiftUI の Text でカラー絵文字を描くと、描画済みの
// 絵文字1個ごとに 48KB の CGImage がシステム側の NSCache(_os_alloc_once_table 配下)に溜まり、
// パネルで眺めた絵文字の数だけ増えて退出でも消えない(601枚=27.3MB を実測。実機の per-process
// 上限 77MB に対し最大の押し上げ源)。UILabel は CoreText で直接レイヤーへ描くのでこの
// キャッシュを通らず、UICollectionView のセル再利用で同時生存を画面分(約40個)に固定する。
// ============================================================================

// 絵文字描画の画素予算(2669→2672)。CoreText はカラー絵文字を描くたびに展開画像をシステムの
// NSCache に保持し、プロセスが死ぬまで捨てない(UILabel/CTLineDraw/SwiftUI のどの経路でも同じ。
// sbix の emjc は Apple 独自の予測圧縮で自前復号は断念)。1個あたりの実測コストは絵文字フォントの
// ビットマップ段階で決まり、24pt では倍率3=54KB / 倍率2=20KB / 倍率1=10KB(段階の境界は約48px:
// 17pt 以下でないと 20KB にならず、フォントを少し縮めても効かない)。
// 「フリック中は描かない」(2670)は探すときのスクロールで空白になり本末転倒、「常に倍率2」(2633)は
// ぼやける、と使い勝手で不可(ユーザ評価)。そこで平時は元どおり(常時描画・倍率3)とし、
// footprint が高いときだけ「これから新しく描く絵文字」の倍率を落とす(既に描いた分はキャッシュ済み
// なので鮮明のまま)。段階は削除キーの色で可視化: 50MB〜=薄ピンク、65MB〜=ピンク。
enum EmojiRenderBudget {
    static let sharpScale: CGFloat = 3
    static let reducedScale: CGFloat = 2
    static let fallbackScale: CGFloat = 1
    static let reducedFootprintMB: Double = 50
    static let fallbackFootprintMB: Double = 65
    /// 節約段階(0=平時 / 1=倍率2 / 2=倍率1)。変化したときに呼ばれる(削除キーの色へ。main 専用)
    nonisolated(unsafe) static var onSavingLevelChange: ((Int) -> Void)?
    nonisolated(unsafe) private static var currentLevel = 0
    nonisolated(unsafe) private static var lastFootprintCheckAt: CFAbsoluteTime = 0
    nonisolated(unsafe) private static var cachedScale: CGFloat = sharpScale
    /// 直近に絵文字を描いた時刻(絵文字キャッシュ由来のメモリ警告の判定に使う。2673)
    nonisolated(unsafe) static var lastRenderAt: CFAbsoluteTime = 0

    /// 描く直前に呼ぶ。footprint に応じた描画倍率を返す(main 専用。footprint は 0.25 秒キャッシュ)
    static func scaleForRendering() -> CGFloat {
        let now = CFAbsoluteTimeGetCurrent()
        lastRenderAt = now
        if now - lastFootprintCheckAt < 0.25 {
            return cachedScale
        }
        lastFootprintCheckAt = now
        let footprintMB = MemoryForensics.currentPhysFootprintMB() ?? 0
        let level = footprintMB >= fallbackFootprintMB ? 2 : (footprintMB >= reducedFootprintMB ? 1 : 0)
        cachedScale = level == 2 ? fallbackScale : (level == 1 ? reducedScale : sharpScale)
        if level != currentLevel {
            currentLevel = level
            onSavingLevelChange?(level)
        }
        return cachedScale
    }
}

/// 絵文字パネルのグリッド。セクションの間に区切り線(ヘッダー)を挟む。
struct EmojiGridCollectionView: UIViewRepresentable {
    struct Section: Equatable {
        let emojis: [String]
        let showsDividerBefore: Bool
    }

    let sections: [Section]
    let columnCount: Int
    let itemSpacing: CGFloat
    let itemHeight: CGFloat
    let dividerBlockHeight: CGFloat
    /// 国旗カテゴリー: 押下中に国名の吹き出しを出す。
    let longPressLabels: [String: (text: String, kind: SymbolInspectBubbleKind)]
    /// カテゴリー切替の検知(変わったら先頭へスクロール)。
    let categoryKey: Int
    let onTextInput: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = itemSpacing
        layout.minimumLineSpacing = itemSpacing
        layout.sectionInset = .zero
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.showsVerticalScrollIndicator = false
        view.showsHorizontalScrollIndicator = false
        view.alwaysBounceVertical = true
        view.delaysContentTouches = false
        // 国旗の吹き出しが最上段で見切れないようクリップしない(旧 SymbolScrollClipDisabledModifier 相当)
        view.clipsToBounds = false
        view.register(EmojiGridCell.self, forCellWithReuseIdentifier: EmojiGridCell.reuseIdentifier)
        view.register(
            EmojiGridDividerView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: EmojiGridDividerView.reuseIdentifier
        )
        view.dataSource = context.coordinator
        view.delegate = context.coordinator
        context.coordinator.parent = self
        return view
    }

    func updateUIView(_ uiView: UICollectionView, context: Context) {
        let coordinator = context.coordinator
        let categoryChanged = coordinator.parent.categoryKey != categoryKey
        let sectionsChanged = coordinator.parent.sections != sections
        coordinator.parent = self
        if let layout = uiView.collectionViewLayout as? UICollectionViewFlowLayout {
            layout.minimumInteritemSpacing = itemSpacing
            layout.minimumLineSpacing = itemSpacing
        }
        if categoryChanged || sectionsChanged {
            coordinator.hideBubble()
            uiView.reloadData()
            if categoryChanged {
                uiView.setContentOffset(.zero, animated: false)
            }
        }
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
        var parent: EmojiGridCollectionView
        private weak var bubble: UIView?

        init(parent: EmojiGridCollectionView) {
            self.parent = parent
        }

        func numberOfSections(in collectionView: UICollectionView) -> Int {
            parent.sections.count
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            parent.sections[section].emojis.count
        }

        func collectionView(
            _ collectionView: UICollectionView,
            cellForItemAt indexPath: IndexPath
        ) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: EmojiGridCell.reuseIdentifier,
                for: indexPath
            )
            let emoji = parent.sections[indexPath.section].emojis[indexPath.item]
            (cell as? EmojiGridCell)?.configure(
                emoji: emoji,
                accessibilityText: parent.longPressLabels[emoji].map { "\(emoji) \($0.text)" } ?? emoji
            )
            return cell
        }

        func collectionView(
            _ collectionView: UICollectionView,
            viewForSupplementaryElementOfKind kind: String,
            at indexPath: IndexPath
        ) -> UICollectionReusableView {
            collectionView.dequeueReusableSupplementaryView(
                ofKind: kind,
                withReuseIdentifier: EmojiGridDividerView.reuseIdentifier,
                for: indexPath
            )
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            sizeForItemAt indexPath: IndexPath
        ) -> CGSize {
            let columns = max(1, parent.columnCount)
            let available = collectionView.bounds.width - parent.itemSpacing * CGFloat(columns - 1)
            let width = floor(max(1, available / CGFloat(columns)))
            return CGSize(width: width, height: parent.itemHeight)
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            referenceSizeForHeaderInSection section: Int
        ) -> CGSize {
            guard parent.sections[section].showsDividerBefore else {
                return .zero
            }
            return CGSize(width: collectionView.bounds.width, height: parent.dividerBlockHeight)
        }

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            let emoji = parent.sections[indexPath.section].emojis[indexPath.item]
            parent.onTextInput(emoji)
        }

        func collectionView(_ collectionView: UICollectionView, didHighlightItemAt indexPath: IndexPath) {
            let emoji = parent.sections[indexPath.section].emojis[indexPath.item]
            guard let label = parent.longPressLabels[emoji],
                let cell = collectionView.cellForItem(at: indexPath) else {
                return
            }
            showBubble(text: label.text, kind: label.kind, above: cell, in: collectionView)
        }

        func collectionView(_ collectionView: UICollectionView, didUnhighlightItemAt indexPath: IndexPath) {
            hideBubble()
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            hideBubble()
        }

        // 国旗の国名吹き出し(旧 SymbolInspectBubbleOverlay と同じ寸法: 13pt bold rounded、
        // 左右 padding 10、キーの上 36pt、画面端で 6pt 内側にクランプ)
        private func showBubble(text: String, kind: SymbolInspectBubbleKind, above cell: UIView, in host: UIView) {
            hideBubble()
            var font = UIFont.systemFont(ofSize: 13, weight: .bold)
            if let descriptor = font.fontDescriptor.withDesign(.rounded) {
                font = UIFont(descriptor: descriptor, size: 13)
            }
            let label = UILabel()
            label.text = text
            label.font = font
            label.textColor = .white
            label.textAlignment = .center
            label.numberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
            let textWidth = min(ceil((text as NSString).size(withAttributes: [.font: font]).width), 300)
            let bubbleWidth = textWidth + 20
            let bubbleHeight: CGFloat = 26
            let container = UIView()
            container.backgroundColor = UIColor(kind.bubbleColor)
            container.layer.cornerRadius = 8
            container.layer.cornerCurve = .continuous
            container.isUserInteractionEnabled = false
            label.frame = CGRect(x: 10, y: 0, width: textWidth, height: bubbleHeight)
            container.addSubview(label)
            let cellFrame = cell.convert(cell.bounds, to: host)
            let screenWidth = UIScreen.main.bounds.width
            let hostOriginX = host.convert(CGPoint.zero, to: nil).x
            let half = bubbleWidth / 2
            let centerXInScreen = hostOriginX + cellFrame.midX
            let clampedCenterX = min(max(centerXInScreen, 6 + half), max(6 + half, screenWidth - 6 - half))
            let centerX = clampedCenterX - hostOriginX
            container.frame = CGRect(
                x: centerX - half,
                y: cellFrame.midY - 36 - bubbleHeight / 2,
                width: bubbleWidth,
                height: bubbleHeight
            )
            host.addSubview(container)
            bubble = container
        }

        func hideBubble() {
            bubble?.removeFromSuperview()
            bubble = nil
        }
    }
}

final class EmojiGridCell: UICollectionViewCell {
    static let reuseIdentifier = "EmojiGridCell"
    private let label = UILabel()
    private let feedbackCircle = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        feedbackCircle.backgroundColor = UIColor(KeyboardThemePalette.pressFeedbackCircle)
        feedbackCircle.layer.cornerRadius = 12
        feedbackCircle.isHidden = true
        feedbackCircle.isUserInteractionEnabled = false
        label.font = .systemFont(ofSize: 24)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = false
        label.isAccessibilityElement = false
        contentView.addSubview(feedbackCircle)
        contentView.addSubview(label)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = contentView.bounds
        feedbackCircle.frame = CGRect(
            x: contentView.bounds.midX - 12,
            y: contentView.bounds.midY - 12,
            width: 24,
            height: 24
        )
    }

    func configure(emoji: String, accessibilityText: String) {
        // 画素予算(EmojiRenderBudget): footprint が高いときだけ倍率を落とす
        let scale = EmojiRenderBudget.scaleForRendering()
        if label.contentScaleFactor != scale {
            label.contentScaleFactor = scale
            label.layer.contentsScale = scale
        }
        label.text = emoji
        accessibilityLabel = accessibilityText
    }

    // 旧 EmojiTapFeedbackButtonStyle と同じ押下表現(0.84 倍+中央の薄い円)
    override var isHighlighted: Bool {
        didSet {
            let pressed = isHighlighted
            UIView.animate(withDuration: 0.08, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
                self.label.transform = pressed ? CGAffineTransform(scaleX: 0.84, y: 0.84) : .identity
                self.feedbackCircle.isHidden = !pressed
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        label.transform = .identity
        feedbackCircle.isHidden = true
    }
}

final class EmojiGridDividerView: UICollectionReusableView {
    static let reuseIdentifier = "EmojiGridDividerView"
    private let line = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        line.backgroundColor = UIColor(KeyboardThemePalette.thinDivider)
        addSubview(line)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // 旧 emojiSectionDivider: 高さ1の線+上下 padding 2
        line.frame = CGRect(x: 0, y: (bounds.height - 1) / 2, width: bounds.width, height: 1)
    }
}

/// UILabel で1行のテキストを描く(候補チップの絵文字用)。intrinsic サイズで SwiftUI に載る。
struct EmojiUILabelText: UIViewRepresentable {
    let text: String
    let font: UIFont
    let color: UIColor

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }

    func updateUIView(_ uiView: UILabel, context: Context) {
        let scale = EmojiRenderBudget.scaleForRendering()
        if uiView.contentScaleFactor != scale {
            uiView.contentScaleFactor = scale
            uiView.layer.contentsScale = scale
        }
        uiView.text = text
        uiView.font = font
        uiView.textColor = color
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        let size = uiView.intrinsicContentSize
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }
}

/// 候補チップの文字: 絵文字を含むときだけ UILabel 経由(SwiftUI Text の絵文字 CGImage キャッシュ回避)。
struct CandidateGlyphText: View {
    let text: String
    let fontSize: CGFloat
    let weight: Font.Weight
    let color: Color

    init(_ text: String, fontSize: CGFloat, weight: Font.Weight = .semibold, color: Color) {
        self.text = text
        self.fontSize = fontSize
        self.weight = weight
        self.color = color
    }

    var body: some View {
        if Self.containsEmoji(text) {
            EmojiUILabelText(
                text: text,
                font: .systemFont(ofSize: fontSize, weight: Self.uiWeight(weight)),
                color: UIColor(color)
            )
            .fixedSize()
        } else {
            Text(text)
                .font(.system(size: fontSize, weight: weight))
                .foregroundStyle(color)
        }
    }

    static func containsEmoji(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if scalar.properties.isEmojiPresentation
                || value == 0xFE0F
                || (0x1F1E6...0x1F1FF).contains(value)
                || (0x1F300...0x1FAFF).contains(value) {
                return true
            }
        }
        return false
    }

    private static func uiWeight(_ weight: Font.Weight) -> UIFont.Weight {
        switch weight {
        case .bold: return .bold
        case .semibold: return .semibold
        case .medium: return .medium
        case .light: return .light
        case .heavy: return .heavy
        default: return .regular
        }
    }
}
