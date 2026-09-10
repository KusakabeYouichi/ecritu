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

    func beginKeyboardHeightLock() {
        let lockHeight = preferredKeyboardHeight()
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

    func effectivePreferredKeyboardHeight() -> CGFloat {
        if let keyboardHeightLockValue,
            CFAbsoluteTimeGetCurrent() < keyboardHeightLockReleaseTime {
            return keyboardHeightLockValue
        }

        if keyboardHeightLockValue != nil {
            self.keyboardHeightLockValue = nil
            keyboardHeightLockReleaseTime = 0
        }

        return preferredKeyboardHeight()
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

    // 回転が終わってからホストに最終値でもう一度計算させる(2859、実機ログで確認した順序への手当て)。
    // ホストは拡張より約 40ms 先に動く。メッセージ.app は縦へ戻る途中で「横のときの高さ 176」を
    // 縦の幅に当てて 234 と算出し、そのまま本文の下端余白を決めていた(2026-09-10 16:46:33 の実機ログ)。
    // écritu が 242 を通知するのはその 10ms 後で、最終的なジオメトリ(placeholder 300 / guide 334)は
    // 正しく揃うのに、会話の最終行は入力欄の下に潜ったままになる。ホスト内部の余白は読めないので、
    // 遷移が落ち着いた後に 1pt ずらして戻し、確実に1回計算し直させる。1フレームの 1pt なので目には見えない。
    // 幅が変わる遷移のときだけ、1回だけ走る。効いたかどうかは診断ログの「回転後の再通知」で追える。
    func scheduleKeyboardHeightRepublishAfterSizeTransition() {
        keyboardHeightRepublishWorkItem?.cancel()
        probeKeyboardGeometryUntilSettled(attempt: 0, previousSample: nil)
    }

    // 「回転が終わった」の判定は遷移コーディネーターの完了だけに頼らない(ユーザ指摘 2859)。
    // 完了コールバックの後もセーフエリアと窓の幅は数フレーム動く。固定の待ち時間で決め打ちすると
    // 端末やホストが変わったときに外れるので、幅と算出高さが 2 回続けて同じ値になった時点を
    // 「落ち着いた」とみなす。上限に達したらそのときの値で打ち切る(無限に待たない)。
    private func probeKeyboardGeometryUntilSettled(attempt: Int, previousSample: CGSize?) {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            let sample = CGSize(width: view.bounds.width, height: effectivePreferredKeyboardHeight())
            let isSettled = previousSample.map {
                abs($0.width - sample.width) <= 0.5 && abs($0.height - sample.height) <= 0.5
            } ?? false

            guard isSettled || attempt >= Self.keyboardHeightRepublishMaxProbes else {
                probeKeyboardGeometryUntilSettled(attempt: attempt + 1, previousSample: sample)
                return
            }

            republishKeyboardHeightToHost(
                height: sample.height,
                settled: isSettled,
                elapsedProbes: attempt
            )
        }
        keyboardHeightRepublishWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.keyboardHeightRepublishProbeInterval, execute: workItem)
    }

    // ホストに最終値でもう一度計算させる。同じ値の再代入は UIKit が握り潰すので、
    // 1pt ずらしてから戻す。1 フレームの 1pt なので見た目には出ない。
    // 戻しは次の実行ループでなく 1 フレーム跨いでから行う(2861): 連続ターンで出すと
    // ホスト側で同一フレームに畳まれ、正味「変化なし」になって計算し直しが起きない
    // (2860 の実機ログでは再通知が発火しているのに重なりが残った)
    private func republishKeyboardHeightToHost(height: CGFloat, settled: Bool, elapsedProbes: Int) {
        // 予約から発火までの間に次の回転が始まっていたら何もしない(2862)。
        // 遷移中(pendingSizeTransitionTargetSize が非nil)か、採ったときの値と今の値が
        // 食い違っていたら、この通知は古い ─ 新しい遷移が自分の分を予約する
        guard pendingSizeTransitionTargetSize == nil,
            abs(effectivePreferredKeyboardHeight() - height) <= 0.5 else {
            return
        }
        synchronizePreferredContentSize(height: height - 1)
        updateKeyboardHeightIfNeeded()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            synchronizePreferredContentSize(height: height)
            updateKeyboardHeightIfNeeded()
            appendKeyboardDiagnosticsLog(
                "回転後の再通知 \(height)pt 収束=\(settled ? "済" : "打ち切り") 待ち=\(elapsedProbes)回",
                critical: true
            )
        }
        keyboardHeightRepublishWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.keyboardHeightRepublishNudgeHold,
            execute: workItem
        )
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

    func hasExpandedHeaderForHeight() -> Bool {
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

        // 横向きの値(21)を縦の値として掴まないための門番(定数コメント参照。2855)。
        // 向き判定より先にセーフエリアだけが切り替わる瞬間があり、その値をキャッシュすると次の回転に響く
        if measuredInset > 0.5,
            KeyboardLayoutMetrics.isPlausiblePortraitBottomInset(
                measuredInset,
                shorterScreenEdge: shorterScreenEdge,
                isPhone: traitCollection.userInterfaceIdiom == .phone
            ) {
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

    func preferredKeyboardHeight() -> CGFloat {
        let screenBounds = view.window?.windowScene?.screen.bounds
            ?? view.window?.bounds
            ?? UIScreen.main.bounds
        // 画面の短辺は向きに依存しない値なので、回らない座標系から採る(2859)。
        // UIScreen.bounds は表示の向きに追随して回るため、回転の最中は「縦と判定して
        // いるのに 852x393」という不整合が出る(2026-09-10 実機ログ)。min を取る限り
        // 同じ値になるので今回の高さ自体は正しかったが、window.bounds への
        // フォールバックは iPad の分割表示で画面でなく窓の短辺を返す。固定座標系を優先する。
        let fixedScreenBounds = view.window?.windowScene?.screen.fixedCoordinateSpace.bounds
        let shorterScreenEdge = fixedScreenBounds.map { min($0.width, $0.height) }
            ?? min(screenBounds.width, screenBounds.height)
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
                hasExpandedHeader: hasExpandedHeaderForHeight(),
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
            screenBounds: screenBounds,
            shorterScreenEdge: shorterScreenEdge
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
        screenBounds: CGRect,
        shorterScreenEdge: CGFloat
    ) {
        let rounded = (height * 2).rounded() / 2
        guard abs(rounded - lastLoggedPreferredKeyboardHeight) > 0.5
            || lastLoggedPreferredKeyboardHeightIsLandscape != isLandscapeOrientation else {
            return
        }
        lastLoggedPreferredKeyboardHeight = rounded
        lastLoggedPreferredKeyboardHeightIsLandscape = isLandscapeOrientation
        let orientation = isLandscapeOrientation ? "横" : "縦"
        // 実測の画面寸法は回転の途中で向きと食い違う。短辺は固定座標系から採るので影響を
        // 受けないが、食い違い自体が遷移中かどうかの手掛かりになるので両方残す(2859)
        let liveIsLandscape = screenBounds.width > screenBounds.height
        let inconsistency = liveIsLandscape == isLandscapeOrientation ? "" : "(向きと不一致)"
        appendKeyboardDiagnosticsLog(
            "高さ要求 \(rounded)pt profile=\(profile) \(orientation)"
                + " 短辺=\(Int(shorterScreenEdge))"
                + " 画面=\(Int(screenBounds.width))x\(Int(screenBounds.height))\(inconsistency)"
                + " 下端インセット=\(Int(view.window?.safeAreaInsets.bottom ?? 0))",
            critical: true
        )
    }

    func installKeyboardHeightConstraintIfNeeded() {
        let initialHeight = effectivePreferredKeyboardHeight()
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

    func updateKeyboardHeightIfNeeded() {
        guard let sizingView = inputView ?? view else {
            return
        }

        migrateKeyboardConstraintsIfNeeded(to: sizingView)

        guard let keyboardHeightConstraint else {
            installKeyboardHeightConstraintIfNeeded()
            return
        }

        let nextHeight = effectivePreferredKeyboardHeight()
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
