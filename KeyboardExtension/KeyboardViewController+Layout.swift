import SwiftUI
import UIKit
import CoreFoundation
import Darwin
import Contacts

extension KeyboardViewController {
    func configureKeyboardContainerSizing() {
        inputView?.allowsSelfSizing = false

        if let inputView {
            migrateKeyboardConstraintsIfNeeded(to: inputView)
        }
    }

    func migrateKeyboardConstraintsIfNeeded(to sizingView: UIView) {
        guard keyboardSizingView !== sizingView else {
            return
        }

        keyboardHeightConstraint?.isActive = false
        keyboardHeightConstraint = nil
        keyboardMaxHeightConstraint?.isActive = false
        keyboardMaxHeightConstraint = nil
        keyboardSizingView = sizingView
    }

    func beginKeyboardHeightLock(using configuration: RenderConfiguration? = nil) {
        let lockHeight = preferredKeyboardHeight(using: configuration)
        keyboardHeightLockValue = lockHeight
        keyboardHeightLockReleaseTime = CFAbsoluteTimeGetCurrent() + Self.keyboardSwitchHeightLockDuration
        synchronizePreferredContentSize(height: lockHeight)

        keyboardHeightLockReleaseWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            self.keyboardHeightLockValue = nil
            self.keyboardHeightLockReleaseTime = 0
            self.refreshKeyboardStateAsync()
        }
        keyboardHeightLockReleaseWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.keyboardSwitchHeightLockDuration,
            execute: workItem
        )
    }

    func effectivePreferredKeyboardHeight(using configuration: RenderConfiguration? = nil) -> CGFloat {
        if let keyboardHeightLockValue,
            CFAbsoluteTimeGetCurrent() < keyboardHeightLockReleaseTime {
            return keyboardHeightLockValue
        }

        if keyboardHeightLockValue != nil {
            self.keyboardHeightLockValue = nil
            keyboardHeightLockReleaseTime = 0
        }

        return preferredKeyboardHeight(using: configuration)
    }

    func synchronizePreferredContentSize(height: CGFloat) {
        let targetWidth = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
        let targetSize = CGSize(width: targetWidth, height: height)

        guard abs(preferredContentSize.height - targetSize.height) > 0.5
            || abs(preferredContentSize.width - targetSize.width) > 0.5 else {
            return
        }

        preferredContentSize = targetSize
    }

    func effectiveKanaLayoutModeForHeight() -> KanaLayoutMode {
        if let mode = lastRenderConfiguration?.kanaLayoutMode {
            return mode
        }

        let sharedDefaults = self.sharedDefaults
        return sharedEnumValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.kanaLayoutMode,
            fallback: .fiveByTwo
        )
    }

    func effectiveLatinLayoutModeForHeight() -> LatinLayoutMode {
        if let mode = lastRenderConfiguration?.latinLayoutMode {
            return mode
        }

        let sharedDefaults = self.sharedDefaults
        return sharedEnumValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.latinLayoutMode,
            fallback: .azerty
        )
    }

    func hasExpandedHeaderForHeight(using configuration: RenderConfiguration? = nil) -> Bool {
        // 候補表示の有無でボタン群が上下しないよう、テキスト系モードでは常に候補ヘッダー領域を確保する。
        switch currentInputMode {
        case .emoji, .kana, .number, .latin, .formattedNumber:
            return true
        }
    }

    func portraitHeightProfile() -> PortraitHeightProfile {
        switch currentInputMode {
        case .emoji:
            return .emoji
        case .formattedNumber:
            // カレンダーだけ graphical を収めるため高い。単位系は通常(絵文字相当)の高さ。
            return FormattedNumberPreferences.lastCategory() == .calendar ? .formattedNumber : .emoji
        case .kana:
            return effectiveKanaLayoutModeForHeight() == .fiveByTwo
                ? .kanaFiveByTwo
                : .kanaThreeByThree
        case .number:
            return .compactGrid
        case .latin:
            return effectiveLatinLayoutModeForHeight() == .flick ? .compactGrid : .compactActionRow
        }
    }

    func portraitHeightBounds(for profile: PortraitHeightProfile) -> ClosedRange<CGFloat> {
        switch profile {
        case .kanaThreeByThree:
            return Self.minimumKanaThreeByThreeHeight...Self.maximumKanaThreeByThreeHeight
        case .compactGrid:
            return Self.minimumCompactGridHeight...Self.maximumCompactGridHeight
        case .compactActionRow:
            return Self.minimumCompactActionRowHeight...Self.maximumCompactActionRowHeight
        case .kanaFiveByTwo:
            return Self.minimumKanaFiveByTwoHeight...Self.maximumKanaFiveByTwoHeight
        case .emoji:
            return Self.minimumEmojiHeight...Self.maximumEmojiHeight
        case .formattedNumber:
            return Self.minimumFormattedNumberHeight...Self.maximumFormattedNumberHeight
        }
    }

    func landscapeHeightBounds(for profile: PortraitHeightProfile) -> ClosedRange<CGFloat> {
        switch profile {
        case .kanaThreeByThree:
            return 162...194
        case .compactGrid:
            if shouldUseKanaLandscapeHeightForCompactGrid() {
                return 162...194
            }

            return 172...204
        case .compactActionRow:
            return 162...194
        case .kanaFiveByTwo:
            return 162...194
        case .emoji:
            return 170...204
        case .formattedNumber:
            return 200...260
        }
    }

    func baseLandscapeKeyboardHeight(for profile: PortraitHeightProfile) -> CGFloat {
        switch profile {
        case .kanaThreeByThree:
            return 176
        case .compactGrid:
            if shouldUseKanaLandscapeHeightForCompactGrid() {
                return 176
            }

            return 186
        case .compactActionRow:
            return 176
        case .kanaFiveByTwo:
            return 176
        case .emoji:
            return 188
        case .formattedNumber:
            return 230
        }
    }

    func shouldUseKanaLandscapeHeightForCompactGrid() -> Bool {
        if currentInputMode == .number {
            return true
        }

        if currentInputMode == .latin {
            return effectiveLatinLayoutModeForHeight() == .flick
        }

        return false
    }

    func portraitHeightFineTuning(for profile: PortraitHeightProfile) -> CGFloat {
        switch profile {
        case .kanaThreeByThree:
            // 3x3+わは独立補正で高さを合わせる。
            return 46
        case .compactGrid:
            // 数字/ラテンフリック系も3x3+わと同一高さに揃える。
            return 46
        case .compactActionRow:
            // compactActionRowはベースが4pt低い分だけ加算して揃える。
            return 50
        case .kanaFiveByTwo:
            // 5x2(上段数字+かな2段+下段アクション)は実質4段なのでcompactActionRowと同等に合わせる。
            return 50
        case .emoji:
            // 絵文字/記号入力もテキスト系モードと同等の見た目高さに揃える。
            return 46
        case .formattedNumber:
            return 46
        }
    }

    func candidateHeaderHeightCompensation(
        for profile: PortraitHeightProfile,
        using configuration: RenderConfiguration? = nil
    ) -> CGFloat {
        guard hasExpandedHeaderForHeight(using: configuration) else {
            return 0
        }

        let headerDelta = Self.candidateHeaderExpandedHeight - Self.candidateHeaderCollapsedHeight

        switch profile {
        case .kanaThreeByThree:
            return headerDelta
        case .compactGrid:
            return headerDelta
        case .compactActionRow:
            return headerDelta
        case .kanaFiveByTwo:
            return headerDelta
        case .emoji:
            return headerDelta
        case .formattedNumber:
            return headerDelta
        }
    }

    func basePortraitKeyboardHeight(
        for profile: PortraitHeightProfile,
        using configuration: RenderConfiguration? = nil
    ) -> CGFloat {
        let headerHeight = hasExpandedHeaderForHeight(using: configuration)
            ? Self.candidateHeaderExpandedHeight
            : Self.candidateHeaderCollapsedHeight
        let rowSpacing = Self.keyboardRowSpacing

        switch profile {
        case .kanaThreeByThree:
            // Header + 4 main rows + internal row spacing + outer vertical padding.
            return headerHeight
                + rowSpacing
                + Self.mainKeyRowHeight * 4
                + rowSpacing * 3
                + Self.keyboardVerticalPadding
        case .compactGrid:
            // Header + 4 main rows + internal row spacing + outer vertical padding.
            return headerHeight
                + rowSpacing
                + Self.mainKeyRowHeight * 4
                + rowSpacing * 3
                + Self.keyboardVerticalPadding
        case .compactActionRow:
            // Header + 3 main rows + action row + internal row spacing + outer vertical padding.
            return headerHeight
                + rowSpacing
                + Self.mainKeyRowHeight * 3
                + Self.actionRowHeight
                + rowSpacing * 3
                + Self.keyboardVerticalPadding
        case .kanaFiveByTwo:
            // Header + top number row + 2 kana rows + action row + internal row spacing + padding.
            return headerHeight
                + rowSpacing
                + Self.mainKeyRowHeight * 3
                + Self.actionRowHeight
                + rowSpacing * 3
                + Self.keyboardVerticalPadding
        case .emoji:
            // 絵文字/記号入力もテキスト系と同じ基準高さに揃える。
            return headerHeight
                + rowSpacing
                + Self.mainKeyRowHeight * 4
                + rowSpacing * 3
                + Self.keyboardVerticalPadding
        case .formattedNumber:
            // graphical カレンダーを収めるため、テキスト系より高い基準高さにする。
            return headerHeight
                + rowSpacing
                + Self.mainKeyRowHeight * 4
                + rowSpacing * 3
                + Self.keyboardVerticalPadding
                + 110
        }
    }

    func effectivePortraitBottomInset(for shorterScreenEdge: CGFloat) -> CGFloat {
        let measuredInset = max(
            view.safeAreaInsets.bottom,
            view.window?.safeAreaInsets.bottom ?? 0,
            inputView?.safeAreaInsets.bottom ?? 0
        )

        if measuredInset > 0.5 {
            cachedPortraitSafeAreaBottomInset = measuredInset
            return measuredInset
        }

        if let cachedPortraitSafeAreaBottomInset {
            return cachedPortraitSafeAreaBottomInset
        }

        if traitCollection.userInterfaceIdiom == .phone,
            shorterScreenEdge >= 375 {
            return 34
        }

        return 0
    }

    func preferredKeyboardHeight(using configuration: RenderConfiguration? = nil) -> CGFloat {
        let screenBounds = view.window?.windowScene?.screen.bounds
            ?? view.window?.bounds
            ?? UIScreen.main.bounds
        let shorterScreenEdge = min(screenBounds.width, screenBounds.height)
        let isLandscapeOrientation: Bool = {
            if let orientation = view.window?.windowScene?.interfaceOrientation {
                return orientation.isLandscape
            }

            if traitCollection.verticalSizeClass == .compact {
                return true
            }

            return false
        }()

        if isLandscapeOrientation {
            let profile = portraitHeightProfile()
            let baseLandscapeHeight = baseLandscapeKeyboardHeight(for: profile)
            let scale = max(0.9, min(shorterScreenEdge / Self.baselineLandscapeScreenHeight, 1.08))
            let scaledLandscapeHeight = round(baseLandscapeHeight * scale)
            let bounds = landscapeHeightBounds(for: profile)
            return min(max(scaledLandscapeHeight, bounds.lowerBound), bounds.upperBound)
        }

        let profile = portraitHeightProfile()
        let basePortraitHeight = basePortraitKeyboardHeight(for: profile, using: configuration)
        let widthScale = max(0.92, min(shorterScreenEdge / Self.baselinePortraitScreenWidth, 1.08))
        let scaledPortraitKeyboardHeight = round(basePortraitHeight * widthScale)
        let systemInset = effectivePortraitBottomInset(for: shorterScreenEdge)
        let headerCompensation = candidateHeaderHeightCompensation(
            for: profile,
            using: configuration
        )
        let adjustedPortraitKeyboardHeight = scaledPortraitKeyboardHeight
            - systemInset
            - Self.portraitSystemAccessoryOffset
            + portraitHeightFineTuning(for: profile)
            - headerCompensation
        let bounds = portraitHeightBounds(for: profile)

        return min(
            max(adjustedPortraitKeyboardHeight, bounds.lowerBound),
            bounds.upperBound
        )
    }

    func installKeyboardHeightConstraintIfNeeded(using configuration: RenderConfiguration? = nil) {
        let initialHeight = effectivePreferredKeyboardHeight(using: configuration)
        synchronizePreferredContentSize(height: initialHeight)
        guard let sizingView = inputView ?? view else {
            return
        }

        migrateKeyboardConstraintsIfNeeded(to: sizingView)

        if let keyboardMaxHeightConstraint {
            if abs(keyboardMaxHeightConstraint.constant - initialHeight) > 0.5 {
                keyboardMaxHeightConstraint.constant = initialHeight
            }
        } else {
            let maxConstraint = sizingView.heightAnchor.constraint(
                lessThanOrEqualToConstant: initialHeight
            )
            maxConstraint.priority = .required
            maxConstraint.isActive = true
            keyboardMaxHeightConstraint = maxConstraint
        }

        guard keyboardHeightConstraint == nil else {
            return
        }

        let constraint = sizingView.heightAnchor.constraint(
            equalToConstant: initialHeight
        )
        constraint.priority = .required
        constraint.isActive = true
        keyboardHeightConstraint = constraint
    }

    func updateKeyboardHeightIfNeeded(using configuration: RenderConfiguration? = nil) {
        guard let sizingView = inputView ?? view else {
            return
        }

        migrateKeyboardConstraintsIfNeeded(to: sizingView)

        guard let keyboardHeightConstraint else {
            installKeyboardHeightConstraintIfNeeded(using: configuration)
            return
        }

        let nextHeight = effectivePreferredKeyboardHeight(using: configuration)
        synchronizePreferredContentSize(height: nextHeight)

        let needsEqualHeightUpdate = abs(keyboardHeightConstraint.constant - nextHeight) > 0.5
        let needsMaxHeightUpdate = {
            guard let keyboardMaxHeightConstraint else {
                return false
            }

            return abs(keyboardMaxHeightConstraint.constant - nextHeight) > 0.5
        }()

        guard needsEqualHeightUpdate || needsMaxHeightUpdate else {
            return
        }

        UIView.performWithoutAnimation {
            if needsMaxHeightUpdate {
                keyboardMaxHeightConstraint?.constant = nextHeight
            }

            if needsEqualHeightUpdate {
                keyboardHeightConstraint.constant = nextHeight
            }

            view.layoutIfNeeded()
            inputView?.layoutIfNeeded()
            view.superview?.layoutIfNeeded()
        }
    }
}
