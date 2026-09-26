import SwiftUI
import UIKit
import CoreFoundation
import Darwin

extension KeyboardViewController {
    func configureKeyboardContainerSizing() {
        // 3101(切り替え直後の 470pt)でも 3159(横画面で枠が広がらない)でも true は効かなかった。
        // 枠の高さはホストが決めていて、拡張側からは動かせない
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

    // 3103 で false(設定しない)を試したが 470pt の枠は変わらず、自前の preferredContentSize は無関係と判明。元に戻す
    static let synchronizesPreferredContentSize = true

    func synchronizePreferredContentSize(height: CGFloat, widthOverride: CGFloat? = nil) {
        guard Self.synchronizesPreferredContentSize else {
            return
        }
        let measuredWidth = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
        let targetWidth = widthOverride ?? measuredWidth
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

        // 実測が取れないときの既定。ホームボタン機(SE/8、下端 0)は縦横比で除く(3087)
        let fixedBounds = view.window?.windowScene?.screen.fixedCoordinateSpace.bounds ?? UIScreen.main.bounds
        if KeyboardLayoutMetrics.assumesHomeIndicator(
            shorterScreenEdge: shorterScreenEdge,
            longerScreenEdge: max(fixedBounds.width, fixedBounds.height),
            isPhone: traitCollection.userInterfaceIdiom == .phone
        ) {
            return 34
        }

        return 0
    }

    // 枠の外にある下端セーフエリア(ホームインジケーターの帯)。縦向きだけ、高さの表がこのぶんを
    // 引いて要求している(preferredHeight 参照)。面を組む側はこれを知らずに下の余白を足していたので、
    // 中身が枠より高くなり上へはみ出していた(3164)
    func bottomSafeAreaOutsideKeyboardFrame() -> CGFloat {
        let screenBounds = view.window?.windowScene?.screen.bounds
            ?? view.window?.bounds
            ?? UIScreen.main.bounds
        let fixedScreenBounds = view.window?.windowScene?.screen.fixedCoordinateSpace.bounds
        let shorterScreenEdge = fixedScreenBounds.map { min($0.width, $0.height) }
            ?? min(screenBounds.width, screenBounds.height)
        let isLandscape = view.window?.windowScene?.interfaceOrientation.isLandscape
            ?? (traitCollection.verticalSizeClass == .compact)
        guard !isLandscape else {
            return 0
        }
        return effectivePortraitBottomInset(for: shorterScreenEdge, isLandscapeOrientation: false)
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
        // ホスト枠の補正(3227)は縦画面だけ
        let compensated = height + (isLandscapeOrientation ? 0 : hostTopInsetCompensation)
        logPreferredKeyboardHeightIfChanged(
            height: compensated,
            profile: profile,
            isLandscapeOrientation: isLandscapeOrientation,
            screenBounds: screenBounds,
            shorterScreenEdge: shorterScreenEdge
        )
        return compensated
    }

    // ホストがサードパーティーの枠に足す 17pt(統合ログ 3218: _UIKBCompatInputView が y=17、非表示の入力アシスタント領域)を
    // こちらで補って、見た目を常に「17+中身」にする(3227。ユーザ指定: 高さが変わるのは避けたい)。
    // 経路と窓の初期高さの対応(実機ログ 3222〜3226):
    //  - アプリで最初に出る回: ホストが既定 216 で枠を組んでから申告値に更新 → 窓が 852 → 216 → 申告値。17 は付かない
    //  - その枠を引き継ぐ再表示: 前の枠の高さを一度当ててから更新 → 窓が 852 → 前の高さ → 申告値。17 は付かない
    //  - 切り替え/スナップショット経由の再表示: 窓が 852 → 申告値 と直に来る。ホストが 17 を足す(Gboard も同じ)
    // なので「最初の縦画面レイアウトで窓の高さが自分の申告値と違っていたら 17 を補う」で 3 経路とも揃う。
    // 補った回は透明な 17pt の帯を上に置き(ホストの地が透ける)、高さも +17 申告する
    static let hostPlaceholderTopInset: CGFloat = 17

    // 前の個体の消え方(3234)。開き直し(キーボードが引っ込む)は viewWillDisappear(animated: true)、切り替え(出たまま
    // 差し替え)は animated: false で来る(実機ログ 3233)。切り替えの後の再表示ではホストが 17 を足すので、窓が前の
    // 補正済みの高さを経由してきても補正しない。プロセス(=ホストアプリのセッション)単位で持つ
    enum PreviousDisappearanceKind: String {
        case unknown = "不明"
        case dismissed = "引っ込めた"
        case replaced = "差し替え"
    }
    nonisolated(unsafe) static var lastDisappearanceKind: PreviousDisappearanceKind = .unknown

    // ホスト枠 17pt を自前で補うかの判定(純関数。Tests/KeyboardControllerLifecycleTests で固定)。
    //   初期高さ < 申告: 既定(216)経由=アプリで最初の回。17 は付かない → 補う(3227)
    //   初期高さ = 申告: 前の枠を引き継いだ回。引っ込めた後の開き直しは 17 が付かない → 補う(3239)。
    //                    差し替え(切り替え)で消えた後はホストが 17 を足す → 補わない(3234)
    //   初期高さ > 申告: 前の個体が補正込み(261)で要求した枠をホストが覚えていて、そのまま来た回。
    //                    ホストの 17 が既に窓に入っているので、消え方によらず補わない。3238 の消え方だけの規則は
    //                    ここで二重補正(261+17=278、上の余白 34)になっていた(実機ログ 2026-09-27 02:57 JST)
    static func shouldCompensateHostTopInset(
        initialHeight: CGFloat,
        requestedHeight: CGFloat,
        previousDisappearance: PreviousDisappearanceKind
    ) -> Bool {
        if initialHeight < requestedHeight - 0.5 {
            return true
        }
        if initialHeight > requestedHeight + 0.5 {
            return false
        }
        return previousDisappearance == .dismissed
    }

    func recordDisappearanceKindIfNeeded(animated: Bool) {
        // 最初の viewWillDisappear(窓がまだある)だけを見る。引っ込めた後に窓が外れてから 2 回目が animated=false で来る
        guard !disappearanceKindRecorded, view.window != nil else {
            return
        }
        disappearanceKindRecorded = true
        Self.lastDisappearanceKind = animated ? .dismissed : .replaced
    }


    func resolveHostTopInsetCompensationFromLayoutIfNeeded() {
        guard !hostTopInsetCompensationResolved, let window = view.window else {
            return
        }
        let isLandscape = window.windowScene?.interfaceOrientation.isLandscape
            ?? (traitCollection.verticalSizeClass == .compact)
        guard !isLandscape else {
            hostTopInsetCompensationResolved = true
            return
        }
        let screenBounds = window.windowScene?.screen.bounds ?? UIScreen.main.bounds
        let screenHeight = max(screenBounds.width, screenBounds.height)
        let height = view.bounds.height
        // 表示前は窓が画面全体の寸法のまま(高さ実寸の 852)。実枠が来るまで待つ
        guard height > 0, height < screenHeight - 1 else {
            return
        }
        hostTopInsetCompensationResolved = true
        let requested = preferredKeyboardHeight()
        // 判定の規則は shouldCompensateHostTopInset のコメント参照(3227/3234/3239/3248)
        let compensates = Self.shouldCompensateHostTopInset(
            initialHeight: height,
            requestedHeight: requested,
            previousDisappearance: Self.lastDisappearanceKind
        )
        hostTopInsetCompensation = compensates ? Self.hostPlaceholderTopInset : 0
        if compensates {
            hostTopConstraint?.constant = Self.hostTopOverlapForCompensation + hostTopInsetCompensation
            updateBackgroundGradientAppearance()
        }
        appendKeyboardDiagnosticsLog(
            "ホスト枠の補正 \(compensates ? "+17pt" : "なし") 窓の初期高さ=\(Int(height)) 申告=\(Int(requested)) 前の消え方=\(Self.lastDisappearanceKind.rawValue)",
            critical: true
        )
        // 消え方は 1 回ぶんだけ有効。次の個体は自分の直前の個体の消え方で判断する
        Self.lastDisappearanceKind = .unknown
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

    // 候補欄の上の余白が時々消える件(3141)。要求値と実寸の食い違いが疑わしいので、
    // 食い違いが出た/消えた瞬間だけ 1 行残す。毎フレーム呼ばれる経路なので閾値と重複抑止を置く
    func logKeyboardHeightMismatchIfChanged() {
        // 表示前(viewWillAppear 未到達)は view が画面全体の寸法のままなので見ない。
        // 実測で毎回 610pt の食い違いとして出ていた(3143)
        guard !isAwaitingInitialHeightSettle, view.window != nil, view.superview != nil else {
            return
        }
        let expected = keyboardHeightConstraint?.constant ?? effectivePreferredKeyboardHeight()
        let actual = view.bounds.height
        guard expected > 0, actual > 0 else {
            return
        }
        let gap = ((actual - expected) * 2).rounded() / 2
        let previousGap = lastLoggedKeyboardHeightMismatch
        guard abs(gap - previousGap) > 0.5 else {
            return
        }
        lastLoggedKeyboardHeightMismatch = gap
        if abs(gap) <= 0.5 {
            keyboardHeightRetryCount = 0
        }
        // 一致し続けている間は無言。ずれた瞬間と、ずれが解消した瞬間だけ残す
        guard abs(gap) > 0.5 || abs(previousGap) > 0.5 else {
            return
        }
        let hostHeight = hostingController?.view.bounds.height ?? -1
        // 制約に入れた値も添える(3156)。横画面で面を切り替えたとき、要求 188 に対して実寸が
        // 176 のままだった。こちらが制約を更新できていないのか、ホストが拒んでいるのかを分ける
        let equalConstant = keyboardHeightConstraint.map { Int($0.constant) } ?? -1
        let maxConstant = keyboardMaxHeightConstraint.map { Int($0.constant) } ?? -1
        appendKeyboardDiagnosticsLog(
            "高さ実寸 差=\(gap)pt 要求=\(Int(expected)) view=\(Int(actual)) 面=\(Int(hostHeight))"
                + " 制約=\(equalConstant)/上限\(maxConstant)"
                + " 下端インセット view=\(Int(view.safeAreaInsets.bottom))"
                + "/窓=\(Int(view.window?.safeAreaInsets.bottom ?? 0))"
                + "/inputView=\(Int(inputView?.safeAreaInsets.bottom ?? 0))"
                + " モード=\(currentInputMode)",
            critical: true
        )
        requestKeyboardHeightAgainIfShrunk(expected: expected, actual: actual)
    }

    // 横画面で面を切り替えると、制約に 188 を入れてもホストが枠を 176 のままにすることがある
    // (実機実測 3156: 回転直後の 1 回目で再現。2 回目以降は 29ms で追随する)。中身は
    // 188 前提で組まれるので上下が切れる。ホストにもう一度要求を届けるため、制約の値を
    // 一瞬だけ 0.5pt ずらして戻し、レイアウトをやり直させる。効かないときのために回数を区切る(3158)
    func requestKeyboardHeightAgainIfShrunk(expected: CGFloat, actual: CGFloat) {
        guard actual + 0.5 < expected,
            keyboardHeightRetryCount < Self.keyboardHeightRetryLimit,
            let constraint = keyboardHeightConstraint else {
            return
        }
        keyboardHeightRetryCount += 1
        let attempt = keyboardHeightRetryCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self, let sizingView = self.inputView ?? self.view else {
                return
            }
            let target = constraint.constant
            guard self.view.bounds.height + 0.5 < target else {
                return
            }
            self.appendKeyboardDiagnosticsLog(
                "高さの再要求 \(attempt)回目 要求=\(Int(target)) view=\(Int(self.view.bounds.height))",
                critical: true
            )
            UIView.performWithoutAnimation {
                constraint.constant = target + 0.5
                self.keyboardMaxHeightConstraint?.constant = target + 0.5
                sizingView.layoutIfNeeded()
                constraint.constant = target
                self.keyboardMaxHeightConstraint?.constant = target
                self.synchronizePreferredContentSize(height: target)
                sizingView.layoutIfNeeded()
                self.view.superview?.layoutIfNeeded()
            }
        }
    }

    // 横画面のホストは「その表示で一度も使っていない高さ」へは枠を広げない(3156-3159 の実測。
    // かな 176 で開くと、記号 188 を要求しても 176 のままで上下が切れる。縮める方向は常に通る)。
    // 最初の 1 回だけ、その向きで使いうる最大の高さを通しておけば、あとは縮小だけで済む(3160)
    func maximumKeyboardHeightForCurrentOrientation() -> CGFloat {
        let base = effectivePreferredKeyboardHeight()
        let screenBounds = view.window?.windowScene?.screen.bounds
            ?? view.window?.bounds
            ?? UIScreen.main.bounds
        let fixedScreenBounds = view.window?.windowScene?.screen.fixedCoordinateSpace.bounds
        let shorterScreenEdge = fixedScreenBounds.map { min($0.width, $0.height) }
            ?? min(screenBounds.width, screenBounds.height)
        // 回転の最中は interfaceOrientation がまだ古い。遷移先のサイズがあればそちらを信じる(3162)
        let isLandscape: Bool = {
            if let target = pendingSizeTransitionTargetSize {
                return KeyboardLayoutMetrics.isLandscapeTransitionTarget(
                    targetWidth: target.width,
                    shorterScreenEdge: shorterScreenEdge
                )
            }
            return view.window?.windowScene?.interfaceOrientation.isLandscape
                ?? (traitCollection.verticalSizeClass == .compact)
        }()
        let bottomInset = effectivePortraitBottomInset(
            for: shorterScreenEdge,
            isLandscapeOrientation: isLandscape
        )
        var maxHeight = base
        // 書式化は高さ計算では emoji プロファイルに写す(portraitHeightProfile 参照)ので、
        // ここでも実際に使う集合だけを見る。入れると縦画面で 333pt という使わない値になり、
        // ホストに丸ごと無視されていた(3160 の実測)
        for profile in PortraitHeightProfile.allCases where profile != .formattedNumber {
            let height = layoutMetrics.preferredHeight(
                KeyboardLayoutMetrics.HeightInputs(
                    profile: profile,
                    isLandscapeOrientation: isLandscape,
                    shorterScreenEdge: shorterScreenEdge,
                    hasExpandedHeader: true,
                    portraitBottomInset: bottomInset,
                    usesKanaLandscapeHeightForCompactGrid: false
                )
            )
            maxHeight = max(maxHeight, height)
        }
        return maxHeight
    }

    // この向きで使いうる最大の高さを、向きごとに一度だけ通す(定義コメント参照。3160)。
    // 直後の更新が本来の高さへ縮める。表示は高さが落ち着くまで隠しているので(3100)一瞬の高さは見えない
    func primeMaximumKeyboardHeightIfNeeded(on sizingView: UIView, currentHeight: CGFloat) {
        guard !didPrimeMaximumKeyboardHeight else {
            return
        }
        didPrimeMaximumKeyboardHeight = true
        let primeHeight = maximumKeyboardHeightForCurrentOrientation()
        guard primeHeight > currentHeight + 0.5 else {
            return
        }
        appendKeyboardDiagnosticsLog(
            "高さの先出し \(Int(primeHeight))pt(この向きの最大。本来は \(Int(currentHeight))pt)",
            critical: true
        )
        UIView.performWithoutAnimation {
            if let keyboardMaxHeightConstraint {
                keyboardMaxHeightConstraint.constant = primeHeight
            } else {
                let maxConstraint = sizingView.heightAnchor.constraint(lessThanOrEqualToConstant: primeHeight)
                maxConstraint.priority = .required
                maxConstraint.isActive = true
                keyboardMaxHeightConstraint = maxConstraint
            }
            if let keyboardHeightConstraint {
                keyboardHeightConstraint.constant = primeHeight
            } else {
                let constraint = sizingView.heightAnchor.constraint(equalToConstant: primeHeight)
                constraint.priority = .required
                constraint.isActive = true
                keyboardHeightConstraint = constraint
            }
            synchronizePreferredContentSize(height: primeHeight)
            sizingView.layoutIfNeeded()
            view.superview?.layoutIfNeeded()
        }
    }

    func installKeyboardHeightConstraintIfNeeded() {
        let initialHeight = effectivePreferredKeyboardHeight()
        synchronizePreferredContentSize(height: initialHeight)
        guard let sizingView = inputView ?? view else {
            return
        }

        migrateKeyboardConstraintsIfNeeded(to: sizingView)

        primeMaximumKeyboardHeightIfNeeded(on: sizingView, currentHeight: initialHeight)

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
        primeMaximumKeyboardHeightIfNeeded(on: sizingView, currentHeight: nextHeight)
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
