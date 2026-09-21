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
                    // 2 行になることがある(1 行目=メモリ警告のバースト数、2 行目=footprint 最大値。2921)。
                    // **修飾子を足さないこと**: ここの型はキー群の巨大なタプルに載るのでスタックを食う
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
    // 長押しで onSpace を連続発火(変換中の候補送り。Apple 純正の変換キー長押しと同じ)。
    // 呼び出し側は変換キーとして機能している間だけ true にする(空白入力では連打しない)。
    var repeatsWhileHolding = false
    var repeatInitialDelay: TimeInterval = 0.5
    var repeatInterval: TimeInterval = 0.2

    @Environment(\.keyboardAccentColor) private var accentColor
    @GestureState private var isGestureInProgress = false
    @State private var activeDirection: FlickDirection = .milieu
    @State private var isTouching = false
    @State private var stuckTouchWatchdogWorkItem: DispatchWorkItem?
    @State private var repeatStartWorkItem: DispatchWorkItem?
    @State private var repeatTimer: Timer?
    @State private var didRepeatDuringTouch = false

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
                        if repeatsWhileHolding {
                            scheduleRepeatStart()
                        }
                    }
                    isTouching = true
                    let direction = FlickGestureResolver.resolve(translation: value.translation)
                    activeDirection = direction == .haut ? .haut : .milieu
                    // 上フリック(タブ)に転じたら候補送りは止める
                    if activeDirection == .haut {
                        cancelRepeatStart()
                        stopRepeating()
                    }
                }
                .onEnded { _ in
                    let repeated = didRepeatDuringTouch
                    defer {
                        finalizeTouchInteractionState()
                    }

                    guard isEnabled else { return }

                    if activeDirection == .haut {
                        onTab()
                    } else if !repeated {
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

    // 長押し候補送り: 初期遅延後に1回送り、以後 repeatInterval ごとに送る。指を離すか
    // 上フリックに転じるまで続く。発火した場合、離した時の onSpace は抑止する(二重送り防止)。
    private func scheduleRepeatStart() {
        cancelRepeatStart()
        didRepeatDuringTouch = false
        let work = DispatchWorkItem {
            guard isTouching, activeDirection == .milieu else { return }
            didRepeatDuringTouch = true
            onSpace()
            let timer = Timer(timeInterval: repeatInterval, repeats: true) { _ in
                guard isTouching, activeDirection == .milieu else { return }
                onSpace()
            }
            repeatTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        repeatStartWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + repeatInitialDelay, execute: work)
    }

    private func cancelRepeatStart() {
        repeatStartWorkItem?.cancel()
        repeatStartWorkItem = nil
    }

    private func stopRepeating() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }

    private func cancelStuckTouchWatchdog() {
        stuckTouchWatchdogWorkItem?.cancel()
        stuckTouchWatchdogWorkItem = nil
    }

    private func finalizeTouchInteractionState() {
        cancelStuckTouchWatchdog()
        cancelRepeatStart()
        stopRepeating()
        didRepeatDuringTouch = false
        activeDirection = .milieu
        if isTouching {
            isTouching = false
        }
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
    @Environment(\.keyboardHorizontalBounds) private var keyboardHorizontalBounds
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
            // キーボード枠(iPad 互換モードでは画面より狭い箱)の内側にクランプ(2786)
            let bounds = keyboardHorizontalBounds
            let half = bubbleWidth / 2
            let keyCenterX = keyFrame.midX
            // 吹き出し中心を枠内[minX+margin+half, maxX-margin-half]にクランプし、はみ出しを内側へずらす。
            let clampedCenterX = min(
                max(keyCenterX, bounds.minX + screenMargin + half),
                max(bounds.minX + screenMargin + half, bounds.maxX - screenMargin - half)
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

// 絵文字の描画メモリについて(2669〜2685 の調査結果):
// CoreText はカラー絵文字を描くたびに展開画像をシステムの NSCache に保持する(1個あたり
// 24pt 倍率3 で約54KB。UILabel/CTLineDraw/SwiftUI のどの経路でも同じで、経路では避けられない。
// sbix の emjc は Apple 独自の予測圧縮で自前復号は断念)。ただし実機ではこのキャッシュは
// per-process のメモリ警告時に OS が捨てる(実測 8/26 19:27: fp59.1→27.5、used44→15)ので
// 青天井には積まれない。シミュレータには上限が無いため 121MB まで積み上がるが実機とは別物。
// よって描画倍率を落とす節約(2672〜2679)は撤去し、常に画面倍率で鮮明に描く(ユーザ指定 2685)。
// メモリ面で残す価値があるのは UICollectionView のセル再利用(SwiftUI の LazyVGrid は生成した
// セルを閉じるまで保持していた)。

/// 絵文字パネルのグリッド。セクションの間に区切り線(ヘッダー)を挟む。
// UIKit のスクロールビューにもスクロール縁の効果(Liquid Glass のぼかし)が付く(iOS 26 で追加、実測で
// 描かれ始めたのは 27)。SwiftUI 側の scrollEdgeEffectHidden は UIViewRepresentable の中の
// UIScrollView には伝播しないため、顔文字・絵文字の面(UICollectionView)だけ 3122 の対処が効かなかった
// (ユーザ報告)。UIKit 側は 4 辺それぞれの hidden を立てる
@MainActor
func hideScrollEdgeEffects(_ scrollView: UIScrollView) {
    if #available(iOS 26.0, *) {
        scrollView.topEdgeEffect.isHidden = true
        scrollView.bottomEdgeEffect.isHidden = true
        scrollView.leftEdgeEffect.isHidden = true
        scrollView.rightEdgeEffect.isHidden = true
    }
}

// 面選択のパレット(3124)。長押しでキーの真上に縦に積み、指を滑らせて離すと決まる。
// 欧文のアクセント選択(FlickKeyView の長押し候補)と同じ操作で、項目が語のラベルなので縦に置く。
// FlickKeyView と、面の下段の あい キー(ReturnToKanaPaletteKey)の両方から使う
struct LongPressVerticalCandidatePanel: View {
    let candidates: [String]
    let highlightedIndex: Int
    var cellWidth: CGFloat = 104

    // 名前だけだと分かりにくいので、面のアイコン(キーに出ているもの)を頭に付ける(ユーザ指定 3126)
    static let iconByLabel: [String: String] = [
        "記号": "⌘",
        "絵文字": "☺︎",
        "顔文字": "^_^",
        "部首": "部",
        "書式化": "12"
    ]

    static let cellHeight: CGFloat = 34
    static let horizontalPadding: CGFloat = 8
    // キーの左辺からの寄せ。左端のキーでも画面内に収まる(キー自身が枠の内側に置かれているため)
    static let keyLeadingInset: CGFloat = 2
    static let spacing: CGFloat = 3
    static let verticalPadding: CGFloat = 3
    // 盤の下端とキーの上辺の間隔(押している指で最下段が隠れない分)
    static let gap: CGFloat = 10

    static func panelHeight(count: Int) -> CGFloat {
        let n = CGFloat(max(0, count))
        return n * cellHeight + max(0, n - 1) * spacing + verticalPadding * 2
    }

    // 何段目かは「長押しが成立した位置からの上への移動量」で決める(3125)。キーの局所座標は
    // 盤が出た瞬間に ZStack の高さが伸びて原点がずれる(実測で半〜2 段のずれ)ので使えない。
    // index 0 は最下段(指を動かさない位置)。1 段ぶん(37pt)上げるごとに 1 つ進む
    static func index(forUpwardDistance distance: CGFloat, count: Int) -> Int {
        guard count > 0 else {
            return 0
        }
        let slot = cellHeight + spacing
        let raw = Int(round(distance / slot))
        return max(0, min(count - 1, raw))
    }

    var body: some View {
        VStack(spacing: Self.spacing) {
            ForEach(Array(candidates.enumerated()).reversed(), id: \.offset) { index, candidate in
                HStack(spacing: 6) {
                    Text(Self.iconByLabel[candidate] ?? "")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(width: 26, alignment: .center)
                    Text(candidate)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                    .foregroundStyle(KeyboardThemePalette.longPressPanelText)
                    .padding(.horizontal, 8)
                    .frame(width: cellWidth, height: Self.cellHeight)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                index == highlightedIndex
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
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, Self.verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(KeyboardThemePalette.longPressPanelBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(KeyboardThemePalette.longPressPanelBorder, lineWidth: 1)
        )
        .shadow(color: KeyboardThemePalette.longPressPanelShadow, radius: 4, y: 1)
        .allowsHitTesting(false)
    }
}

// 面の下段の あい(かなへ戻る)キー。タップで戻り、長押しで面選択のパレットを出す(3124)。
// ActionKeyButton に機能を足すと、あのキーは盤面のあちこちで使われていて型が膨らむ(本体の注記参照)ため、
// 見た目だけ合わせた専用のキーにしている
struct ReturnToKanaPaletteKey: View {
    let title: String
    var fontSize: CGFloat = 16
    var fixedWidth: CGFloat? = 56
    let candidates: [String]
    let onReturn: () -> Void
    let onSelectCandidate: (String) -> Void

    @State private var paletteIsActive = false
    @State private var highlightedIndex = 0
    @State private var longPressWorkItem: DispatchWorkItem?

    @State private var latestLocationY: CGFloat = 0
    @State private var anchorLocationY: CGFloat = 0

    // 面の切り替えは「選び直し」ではないので待たせない(ユーザ指定 3125)
    private static let longPressDelay: TimeInterval = 0.2

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(KeyboardThemePalette.keyLabel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(KeyboardThemePalette.keyBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(KeyboardThemePalette.keyBorder, lineWidth: 1)
                )

        }
        .overlay(alignment: .topLeading) {
            // キーの左上を基準に置く(測定に頼らない。3128)
            if paletteIsActive {
                LongPressVerticalCandidatePanel(
                    candidates: candidates,
                    highlightedIndex: highlightedIndex
                )
                    .offset(
                        x: LongPressVerticalCandidatePanel.keyLeadingInset,
                        y: -(LongPressVerticalCandidatePanel.panelHeight(count: candidates.count)
                            + LongPressVerticalCandidatePanel.gap)
                    )
                    .zIndex(KeyboardLayerZIndex.floatingOverlay)
            }
        }
        .frame(width: fixedWidth)
        .contentShape(Rectangle())
        .accessibilityLabel(title)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    latestLocationY = value.location.y
                    if paletteIsActive {
                        highlightedIndex = LongPressVerticalCandidatePanel.index(
                            forUpwardDistance: anchorLocationY - value.location.y,
                            count: candidates.count
                        )
                        return
                    }
                    guard longPressWorkItem == nil else {
                        return
                    }
                    let work = DispatchWorkItem {
                        paletteIsActive = true
                        highlightedIndex = 0
                        anchorLocationY = latestLocationY
                    }
                    longPressWorkItem = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.longPressDelay, execute: work)
                }
                .onEnded { _ in
                    longPressWorkItem?.cancel()
                    longPressWorkItem = nil
                    guard paletteIsActive else {
                        onReturn()
                        return
                    }
                    paletteIsActive = false
                    guard candidates.indices.contains(highlightedIndex) else {
                        return
                    }
                    onSelectCandidate(candidates[highlightedIndex])
                }
        )
        .onDisappear {
            longPressWorkItem?.cancel()
            longPressWorkItem = nil
            paletteIsActive = false
        }
    }
}

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
        hideScrollEdgeEffects(view)
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
            // 枠=ホスト(グリッド)のウィンドウ座標。iPad 互換モードの箱でも枠内に収まる(2786)
            let hostFrameInWindow = host.convert(host.bounds, to: nil)
            let hostOriginX = hostFrameInWindow.minX
            let half = bubbleWidth / 2
            let centerXInScreen = hostOriginX + cellFrame.midX
            let clampedCenterX = min(
                max(centerXInScreen, hostFrameInWindow.minX + 6 + half),
                max(hostFrameInWindow.minX + 6 + half, hostFrameInWindow.maxX - 6 - half)
            )
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

// 顔文字パネルの分類一覧を UICollectionView で描く(3084)。SwiftUI の VStack/HStack(kaomojiRowLayoutsView)だと
// 分類の全顔文字(百数十個)のボタンを一度に実体化し、パネル表示のたび footprint +5.6MB(実機、メッセージ/メモ)が
// 乗っていた。絵文字パネル(EmojiGridCollectionView、2633)と同型で、セル再利用により見えている行ぶんしか作らない。
// 行の切り方と幅・間隔は従来の kaomojiRows(幅計測+均等配分)をそのまま受け取り、1 行=1 セクションで並べる
struct KaomojiGridCollectionView: UIViewRepresentable {
    struct Item: Equatable {
        let text: String
        let width: CGFloat
    }
    struct Row: Equatable {
        let items: [Item]
        let spacing: CGFloat
    }

    let rows: [Row]
    let rowSpacing: CGFloat
    let itemHeight: CGFloat
    // 分類が変わったらスクロール位置を先頭へ
    let categoryKey: String
    let onTextInput: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.showsVerticalScrollIndicator = false
        view.showsHorizontalScrollIndicator = false
        view.alwaysBounceVertical = true
        view.delaysContentTouches = false
        hideScrollEdgeEffects(view)
        view.register(KaomojiGridCell.self, forCellWithReuseIdentifier: KaomojiGridCell.reuseIdentifier)
        view.dataSource = context.coordinator
        view.delegate = context.coordinator
        context.coordinator.parent = self
        return view
    }

    func updateUIView(_ uiView: UICollectionView, context: Context) {
        let coordinator = context.coordinator
        let categoryChanged = coordinator.parent.categoryKey != categoryKey
        let rowsChanged = coordinator.parent.rows != rows
        coordinator.parent = self
        if categoryChanged || rowsChanged {
            uiView.reloadData()
            if categoryChanged {
                uiView.setContentOffset(.zero, animated: false)
            }
        }
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
        var parent: KaomojiGridCollectionView

        init(parent: KaomojiGridCollectionView) {
            self.parent = parent
        }

        func numberOfSections(in collectionView: UICollectionView) -> Int {
            parent.rows.count
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            parent.rows[section].items.count
        }

        func collectionView(
            _ collectionView: UICollectionView,
            cellForItemAt indexPath: IndexPath
        ) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: KaomojiGridCell.reuseIdentifier,
                for: indexPath
            )
            (cell as? KaomojiGridCell)?.configure(text: parent.rows[indexPath.section].items[indexPath.item].text)
            return cell
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            sizeForItemAt indexPath: IndexPath
        ) -> CGSize {
            let item = parent.rows[indexPath.section].items[indexPath.item]
            // 行の幅計算は kaomojiRows 側で済んでいる。丸め誤差で 2 行に割れないよう幅を切り下げる
            return CGSize(width: floor(min(item.width, collectionView.bounds.width)), height: parent.itemHeight)
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            minimumInteritemSpacingForSectionAt section: Int
        ) -> CGFloat {
            // 均等配分の間隔。切り下げた幅ぶんの余りは末尾に残る(左寄せ)
            floor(parent.rows[section].spacing)
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            insetForSectionAt section: Int
        ) -> UIEdgeInsets {
            UIEdgeInsets(top: 0, left: 0, bottom: section == parent.rows.count - 1 ? 0 : parent.rowSpacing, right: 0)
        }

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            parent.onTextInput(parent.rows[indexPath.section].items[indexPath.item].text)
        }
    }
}

final class KaomojiGridCell: UICollectionViewCell {
    static let reuseIdentifier = "KaomojiGridCell"
    private let label = UILabel()
    private let feedback = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        // KaomojiTapFeedbackButtonStyle と同じ見た目(角丸 8 の塗り+縁、押下で 0.98 倍)
        feedback.backgroundColor = UIColor(KeyboardThemePalette.pressFeedbackRounded)
        feedback.layer.cornerRadius = 8
        feedback.layer.cornerCurve = .continuous
        feedback.layer.borderWidth = 1
        feedback.layer.borderColor = UIColor(KeyboardThemePalette.pressFeedbackRoundedBorder).cgColor
        feedback.isHidden = true
        feedback.isUserInteractionEnabled = false
        var font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        if let descriptor = font.fontDescriptor.withDesign(.rounded) {
            font = UIFont(descriptor: descriptor, size: 18)
        }
        label.font = font
        label.textColor = UIColor(KeyboardThemePalette.keyLabel)
        label.textAlignment = .center
        label.numberOfLines = 1
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.45
        label.isAccessibilityElement = false
        contentView.addSubview(feedback)
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
        feedback.frame = contentView.bounds
        label.frame = contentView.bounds.insetBy(dx: 4, dy: 0)
    }

    func configure(text: String) {
        label.text = text
        accessibilityLabel = text
    }

    override var isHighlighted: Bool {
        didSet {
            let pressed = isHighlighted
            UIView.animate(withDuration: 0.08, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
                self.label.transform = pressed ? CGAffineTransform(scaleX: 0.98, y: 0.98) : .identity
                self.feedback.isHidden = !pressed
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        label.transform = .identity
        feedback.isHidden = true
    }
}
