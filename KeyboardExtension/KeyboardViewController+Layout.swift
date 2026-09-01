import SwiftUI
import UIKit
import CoreFoundation
import Darwin

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
            // 記号/絵文字/顔文字と下段バー位置・高さを完全一致させるため emoji プロファイルにする
            // (これらは全て emoji プロファイルでバーが揃う。kana だと約8pt高くバーがずれる)。
            return .emoji
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

    func shouldUseKanaLandscapeHeightForCompactGrid() -> Bool {
        if currentInputMode == .number {
            return true
        }

        if currentInputMode == .latin {
            return effectiveLatinLayoutModeForHeight() == .flick
        }

        return false
    }

    func effectivePortraitBottomInset(for shorterScreenEdge: CGFloat, isLandscapeOrientation: Bool) -> CGFloat {
        // 実測値を「縦のセーフエリア」として採用してよいのは、縦向きで、かつサイズ遷移が
        // 終わっているときだけ。横向きのホームインジケーター(21pt)や回転途中の中間値を
        // 掴むと、縦の高さが誤った値で算出される。実機ログでは回転の最中に 21 を拾って
        // 255pt(正しくは242pt)を publish していた(2026-09-02)。
        let canSampleLiveInset = !isLandscapeOrientation && pendingSizeTransitionTargetSize == nil
        let measuredInset = canSampleLiveInset
            ? max(
                view.safeAreaInsets.bottom,
                view.window?.safeAreaInsets.bottom ?? 0,
                inputView?.safeAreaInsets.bottom ?? 0
            )
            : 0

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
            // サイズ遷移中は、UIKit が viewWillTransition で渡した遷移先サイズだけが
            // 一貫した根拠になる。interfaceOrientation は他のジオメトリより先に切り替わる
            // ことがあり、「縦の幅に横の高さ」という不整合を生む(2026-09-02 実機ログ)。
            if let target = pendingSizeTransitionTargetSize {
                return KeyboardLayoutMetrics.isLandscapeTransitionTarget(
                    targetWidth: target.width,
                    shorterScreenEdge: shorterScreenEdge
                )
            }

            if let orientation = view.window?.windowScene?.interfaceOrientation {
                return orientation.isLandscape
            }

            if traitCollection.verticalSizeClass == .compact {
                return true
            }

            return false
        }()

        // 実際の算出は KeyboardLayoutMetrics.preferredHeight(純粋関数)に委譲する。
        // ここは環境値を集めるだけ。横組みにするかの判定もビュー側と同じ metrics が持つ。
        let profile = portraitHeightProfile()
        let height = layoutMetrics.preferredHeight(
            KeyboardLayoutMetrics.HeightInputs(
                profile: profile,
                isLandscapeOrientation: isLandscapeOrientation,
                shorterScreenEdge: shorterScreenEdge,
                hasExpandedHeader: hasExpandedHeaderForHeight(using: configuration),
                portraitBottomInset: effectivePortraitBottomInset(
                    for: shorterScreenEdge,
                    isLandscapeOrientation: isLandscapeOrientation
                ),
                usesKanaLandscapeHeightForCompactGrid: shouldUseKanaLandscapeHeightForCompactGrid()
            )
        )
        logPreferredKeyboardHeightIfChanged(
            height: height,
            profile: profile,
            isLandscapeOrientation: isLandscapeOrientation,
            screenBounds: screenBounds
        )
        return height
    }

    // 高さ要求が変わったときだけ critical で残す。メッセージ.app で回転を挟むと
    // ホスト側の placeholder / compat view / tracking の3値が食い違ったまま固定され、
    // 会話の最終行が入力欄の下に潜り込む症状が出る(2026-09-01 実機再現)。統合ログには
    // écritu が何ptを要求したかが残らず突き合わせができなかったため、ここで記録する。
    // 毎フレーム呼ばれる経路なので、変化時のみ・1行だけに絞る。
    private func logPreferredKeyboardHeightIfChanged(
        height: CGFloat,
        profile: PortraitHeightProfile,
        isLandscapeOrientation: Bool,
        screenBounds: CGRect
    ) {
        let rounded = (height * 2).rounded() / 2
        guard abs(rounded - lastLoggedPreferredKeyboardHeight) > 0.5
            || lastLoggedPreferredKeyboardHeightIsLandscape != isLandscapeOrientation else {
            return
        }
        lastLoggedPreferredKeyboardHeight = rounded
        lastLoggedPreferredKeyboardHeightIsLandscape = isLandscapeOrientation
        let orientation = isLandscapeOrientation ? "横" : "縦"
        appendKeyboardDiagnosticsLog(
            "高さ要求 \(rounded)pt profile=\(profile) \(orientation)"
                + " 画面=\(Int(screenBounds.width))x\(Int(screenBounds.height))"
                + " 下端インセット=\(Int(view.window?.safeAreaInsets.bottom ?? 0))",
            critical: true
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
