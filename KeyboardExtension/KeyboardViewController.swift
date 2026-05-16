import SwiftUI
import UIKit
import CoreFoundation

final class KeyboardViewController: UIInputViewController {
    private var hostingController: UIHostingController<KeyboardRootView>?
    private var lastRenderConfiguration: RenderConfiguration?
    private var keyboardHeightConstraint: NSLayoutConstraint?
    private var keyboardMaxHeightConstraint: NSLayoutConstraint?
    private weak var keyboardSizingView: UIView?
    private var cachedPortraitSafeAreaBottomInset: CGFloat?
    private var isObservingSettingsDidChange = false
    private var keyboardHeightLockValue: CGFloat?
    private var keyboardHeightLockReleaseTime: CFAbsoluteTime = 0
    private var keyboardHeightLockReleaseWorkItem: DispatchWorkItem?
    var currentInputMode: KeyboardInputMode = .kana
    private var spaceToastTrigger = 0
    var composingRawText = ""
    var composingReading = ""
    var activeConversion: ActiveConversion?
    private lazy var kanaKanjiStore = KanaKanjiStore(appGroupID: SharedDefaultsKeys.appGroupID)
    lazy var kanaKanjiConverter = KanaKanjiConverter(store: kanaKanjiStore)

    struct ActiveConversion: Equatable {
        let reading: String
        let sourceText: String
        let candidates: [String]
        var selectedIndex: Int
        var committedText: String
    }

    struct CandidatePresentation: Equatable {
        let composingText: String
        let candidates: [String]
        let selectedIndex: Int?
    }

    private enum SharedDefaultsKeys {
        private static func fallbackAppGroupID() -> String {
            guard let bundleID = Bundle.main.bundleIdentifier,
                !bundleID.isEmpty else {
                return "group.com.kusakabe.ecritu"
            }

            if bundleID.hasSuffix(".keyboard") {
                let containerBundleID = String(bundleID.dropLast(".keyboard".count))
                return "group.\(containerBundleID)"
            }

            return "group.\(bundleID)"
        }

        static let appGroupID: String = {
            guard
                let value = Bundle.main.object(forInfoDictionaryKey: "EcrituAppGroupIdentifier") as? String,
                !value.isEmpty
            else {
                return fallbackAppGroupID()
            }
            return value
        }()
        static let directionProfile = "flickDirectionProfile"
        static let kanaLayoutMode = "kanaLayoutMode"
        static let kanaModifierPlacement = "kanaModifierPlacement"
        static let numberLayoutMode = "numberLayoutMode"
        static let latinLayoutMode = "latinLayoutMode"
        static let basicSymbolOrder = "basicSymbolOrder"
        static let accentPalette = "accentPalette"
        static let keyboardBackgroundTheme = "keyboardBackgroundTheme"
        static let kanaFlickGuideDisplayMode = "flickGuideDisplayModeKana"
        static let latinFlickGuideDisplayMode = "flickGuideDisplayModeLatin"
        static let numberFlickGuideDisplayMode = "flickGuideDisplayModeNumber"
        static let showsFlickGuideCharacters = "showsFlickGuideCharacters"
        static let keyRepeatInitialDelay = "keyRepeatInitialDelay"
        static let keyRepeatInterval = "keyRepeatInterval"
        static let kanaModeSwitcherTapAction = "kanaModeSwitcherTapAction"
        static let kanaModeSwitcherRightFlickAction = "kanaModeSwitcherRightFlickAction"
        static let kanaModeSwitcherUpFlickAction = "kanaModeSwitcherUpFlickAction"
        static let landscapeCandidateSide = "landscapeCandidateSide"
        static let landscapeNumberPaneSide = "landscapeNumberPaneSide"
        static let keyboardInputProbeCount = "keyboardInputProbeCount"
        static let keyboardInputProbeHeartbeat = "keyboardInputProbeHeartbeat"
        static let keyboardInputProbeLastEvent = "keyboardInputProbeLastEvent"
        static let keyboardInputProbeLastText = "keyboardInputProbeLastText"
        static let kanaKanjiCandidateSourceMode = "kanaKanjiCandidateSourceMode"
        static var settingsDidChangeDarwinNotificationName: String {
            "com.kusakabe.ecritu.settings-changed.\(appGroupID)"
        }
    }

    private static let settingsDidChangeDarwinCallback: CFNotificationCallback = {
        _, observer, _, _, _ in
        guard let observer else {
            return
        }

        let controller = Unmanaged<KeyboardViewController>
            .fromOpaque(observer)
            .takeUnretainedValue()
        controller.refreshKeyboardStateAsync()
    }

    private static let hostTopOverlap: CGFloat = 0
    private static let baselinePortraitScreenWidth: CGFloat = 390
    private static let baselineLandscapeScreenHeight: CGFloat = 393
    private static let candidateHeaderExpandedHeight: CGFloat = 35
    private static let candidateHeaderCollapsedHeight: CGFloat = 3
    private static let keyboardVerticalPadding: CGFloat = 23
    private static let keyboardRowSpacing: CGFloat = 6
    private static let mainKeyRowHeight: CGFloat = 46
    private static let actionRowHeight: CGFloat = 42
    private static let minimumKanaThreeByThreeHeight: CGFloat = 220
    private static let maximumKanaThreeByThreeHeight: CGFloat = 280
    private static let minimumCompactGridHeight: CGFloat = 194
    private static let maximumCompactGridHeight: CGFloat = 252
    private static let minimumCompactActionRowHeight: CGFloat = 200
    private static let maximumCompactActionRowHeight: CGFloat = 260
    private static let minimumKanaFiveByTwoHeight: CGFloat = 216
    private static let maximumKanaFiveByTwoHeight: CGFloat = 280
    private static let minimumEmojiHeight: CGFloat = 228
    private static let maximumEmojiHeight: CGFloat = 290
    private static let portraitSystemAccessoryOffset: CGFloat = 6
    private static let keyboardSwitchHeightLockDuration: TimeInterval = 0.45
    private static let baseKeyboardBackgroundColor = UIColor { trait in
        if trait.userInterfaceStyle == .dark {
            return UIColor(red: 0.12, green: 0.14, blue: 0.18, alpha: 1.0)
        }

        return UIColor(red: 0.89, green: 0.90, blue: 0.92, alpha: 1.0)
    }

    private enum PortraitHeightProfile {
        case kanaThreeByThree
        case compactGrid
        case compactActionRow
        case kanaFiveByTwo
        case emoji
    }

    private struct RenderConfiguration: Equatable {
        let directionProfile: FlickDirectionProfile
        let kanaLayoutMode: KanaLayoutMode
        let kanaModifierPlacementMode: KanaModifierPlacementMode
        let kanaPostModifierButtonState: KanaPostModifierButtonState
        let numberLayoutMode: NumberLayoutMode
        let latinLayoutMode: LatinLayoutMode
        let accentPaletteRawValue: String
        let keyboardBackgroundThemeRawValue: String
        let basicSymbolOrderRawValue: String
        let temperatureUnitRawValue: String
        let spaceToastTrigger: Int
        let returnKeySystemImageName: String?
        let isReturnKeyEnabled: Bool
        let kanaFlickGuideDisplayMode: FlickGuideDisplayMode
        let latinFlickGuideDisplayMode: FlickGuideDisplayMode
        let numberFlickGuideDisplayMode: FlickGuideDisplayMode
        let keyRepeatInitialDelay: TimeInterval
        let keyRepeatInterval: TimeInterval
        let kanaModeSwitcherTapActionRawValue: String
        let kanaModeSwitcherRightFlickActionRawValue: String
        let kanaModeSwitcherUpFlickActionRawValue: String
        let landscapeCandidateSideRawValue: String
        let landscapeNumberPaneSideRawValue: String
        let showsNextKeyboardKey: Bool
        let shortcutVocabulary: [String]
        let composingText: String
        let conversionCandidates: [String]
        let selectedConversionCandidateIndex: Int?
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureKeyboardContainerSizing()
        beginKeyboardHeightLock()
        prepareKeyboardVisualForTransition()
        configureInputAssistantBar()
        startObservingSettingsDidChange()
        setupKeyboardView()
        kanaKanjiConverter.preloadSystemDictionaryIfNeeded { [weak self] in
            self?.refreshKeyboardStateAsync()
        }
    }

    deinit {
        keyboardHeightLockReleaseWorkItem?.cancel()
        stopObservingSettingsDidChange()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        configureKeyboardContainerSizing()
        beginKeyboardHeightLock(using: makeRenderConfiguration())
        configureInputAssistantBar()
        prepareKeyboardVisualForTransition()
        spaceToastTrigger += 1
        refreshKeyboardState()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        synchronizeConversionContextIfNeeded()
        refreshKeyboardState()
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        synchronizeConversionContextIfNeeded()
        refreshKeyboardState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard lastRenderConfiguration != nil else {
            return
        }

        applyKeyboardBaseBackground()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        let configuration = makeRenderConfiguration()
        installKeyboardHeightConstraintIfNeeded(using: configuration)
        updateKeyboardHeightIfNeeded(using: configuration)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let configuration = makeRenderConfiguration()
        installKeyboardHeightConstraintIfNeeded(using: configuration)
        updateKeyboardHeightIfNeeded(using: configuration)

        updateKeyboardVisualVisibility(using: configuration)

        guard lastRenderConfiguration != nil else {
            return
        }

        applyKeyboardBaseBackground()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        let styleDidChange = previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle
        let sizeClassDidChange =
            previousTraitCollection?.horizontalSizeClass != traitCollection.horizontalSizeClass
                || previousTraitCollection?.verticalSizeClass != traitCollection.verticalSizeClass

        guard styleDidChange || sizeClassDidChange else {
            return
        }

        if styleDidChange {
            applyKeyboardBaseBackground()
        }

        guard sizeClassDidChange else {
            return
        }

        let configuration = makeRenderConfiguration()
        installKeyboardHeightConstraintIfNeeded(using: configuration)
        updateKeyboardHeightIfNeeded(using: configuration)
    }

    private func setupKeyboardView() {
        let configuration = makeRenderConfiguration()
        let host = UIHostingController(rootView: makeRootView(from: configuration))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.clipsToBounds = false
        view.clipsToBounds = false

        view.addSubview(host.view)

        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor, constant: Self.hostTopOverlap),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Keep keyboard height scaled to the current iPhone screen size.
        installKeyboardHeightConstraintIfNeeded(using: configuration)
        updateKeyboardHeightIfNeeded(using: configuration)

        host.didMove(toParent: self)
        hostingController = host
        lastRenderConfiguration = configuration
        prepareKeyboardVisualForTransition()
        applyKeyboardBaseBackground()
    }

    private func configureInputAssistantBar() {
        let assistant = inputAssistantItem
        assistant.leadingBarButtonGroups = []
        assistant.trailingBarButtonGroups = []
    }

    private func configureKeyboardContainerSizing() {
        (inputView as? UIInputView)?.allowsSelfSizing = false

        if let inputView {
            migrateKeyboardConstraintsIfNeeded(to: inputView)
        }
    }

    private func migrateKeyboardConstraintsIfNeeded(to sizingView: UIView) {
        guard keyboardSizingView !== sizingView else {
            return
        }

        keyboardHeightConstraint?.isActive = false
        keyboardHeightConstraint = nil
        keyboardMaxHeightConstraint?.isActive = false
        keyboardMaxHeightConstraint = nil
        keyboardSizingView = sizingView
    }

    private func beginKeyboardHeightLock(using configuration: RenderConfiguration? = nil) {
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

    private func effectivePreferredKeyboardHeight(using configuration: RenderConfiguration? = nil) -> CGFloat {
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

    private func startObservingSettingsDidChange() {
        guard !isObservingSettingsDidChange else {
            return
        }

        let observer = Unmanaged.passUnretained(self).toOpaque()
        let name = SharedDefaultsKeys.settingsDidChangeDarwinNotificationName as CFString

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer,
            Self.settingsDidChangeDarwinCallback,
            name,
            nil,
            .deliverImmediately
        )

        isObservingSettingsDidChange = true
    }

    private func stopObservingSettingsDidChange() {
        guard isObservingSettingsDidChange else {
            return
        }

        let observer = Unmanaged.passUnretained(self).toOpaque()
        let name = CFNotificationName(
            SharedDefaultsKeys.settingsDidChangeDarwinNotificationName as CFString
        )

        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer,
            name,
            nil
        )

        isObservingSettingsDidChange = false
    }

    private func refreshKeyboardState() {
        let configuration = makeRenderConfiguration()
        applyKeyboardBaseBackground()
        installKeyboardHeightConstraintIfNeeded()
        updateKeyboardHeightIfNeeded(using: configuration)

        guard configuration != lastRenderConfiguration else {
            return
        }

        lastRenderConfiguration = configuration
        UIView.performWithoutAnimation {
            hostingController?.rootView = makeRootView(from: configuration)
            hostingController?.view.layoutIfNeeded()
        }
    }

    func refreshKeyboardStateAsync() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshKeyboardState()
        }
    }

    private func applyKeyboardBaseBackground() {
        view.backgroundColor = Self.baseKeyboardBackgroundColor
        inputView?.backgroundColor = Self.baseKeyboardBackgroundColor
        hostingController?.view.backgroundColor = Self.baseKeyboardBackgroundColor
    }

    private func prepareKeyboardVisualForTransition() {
        view.alpha = 1
        hostingController?.view.alpha = 1
    }

    private func updateKeyboardVisualVisibility(using _: RenderConfiguration) {
        if view.alpha != 1 {
            view.alpha = 1
        }

        if hostingController?.view.alpha != 1 {
            hostingController?.view.alpha = 1
        }
    }

    private func synchronizePreferredContentSize(height: CGFloat) {
        let targetWidth = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
        let targetSize = CGSize(width: targetWidth, height: height)

        guard abs(preferredContentSize.height - targetSize.height) > 0.5
            || abs(preferredContentSize.width - targetSize.width) > 0.5 else {
            return
        }

        preferredContentSize = targetSize
    }

    func recordKeyboardInputProbe(event: String, text: String? = nil) {
        guard let defaults = UserDefaults(suiteName: SharedDefaultsKeys.appGroupID) else {
            return
        }

        let nextCount = defaults.integer(forKey: SharedDefaultsKeys.keyboardInputProbeCount) + 1
        defaults.set(nextCount, forKey: SharedDefaultsKeys.keyboardInputProbeCount)
        defaults.set(Date().timeIntervalSince1970, forKey: SharedDefaultsKeys.keyboardInputProbeHeartbeat)
        defaults.set(event, forKey: SharedDefaultsKeys.keyboardInputProbeLastEvent)

        if let text, !text.isEmpty {
            defaults.set(String(text.prefix(12)), forKey: SharedDefaultsKeys.keyboardInputProbeLastText)
        }
    }

    private func effectiveKanaLayoutModeForHeight() -> KanaLayoutMode {
        if let mode = lastRenderConfiguration?.kanaLayoutMode {
            return mode
        }

        let sharedDefaults = UserDefaults(suiteName: SharedDefaultsKeys.appGroupID)
        return sharedEnumValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.kanaLayoutMode,
            fallback: .fiveByTwo
        )
    }

    private func effectiveLatinLayoutModeForHeight() -> LatinLayoutMode {
        if let mode = lastRenderConfiguration?.latinLayoutMode {
            return mode
        }

        let sharedDefaults = UserDefaults(suiteName: SharedDefaultsKeys.appGroupID)
        return sharedEnumValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.latinLayoutMode,
            fallback: .azerty
        )
    }

    private func hasExpandedHeaderForHeight(using configuration: RenderConfiguration? = nil) -> Bool {
        // 候補表示の有無でボタン群が上下しないよう、テキスト系モードでは常に候補ヘッダー領域を確保する。
        switch currentInputMode {
        case .emoji, .kana, .number, .latin:
            return true
        }
    }

    private func portraitHeightProfile() -> PortraitHeightProfile {
        switch currentInputMode {
        case .emoji:
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

    private func portraitHeightBounds(for profile: PortraitHeightProfile) -> ClosedRange<CGFloat> {
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
        }
    }

    private func landscapeHeightBounds(for profile: PortraitHeightProfile) -> ClosedRange<CGFloat> {
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
        }
    }

    private func baseLandscapeKeyboardHeight(for profile: PortraitHeightProfile) -> CGFloat {
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
        }
    }

    private func shouldUseKanaLandscapeHeightForCompactGrid() -> Bool {
        if currentInputMode == .number {
            return true
        }

        if currentInputMode == .latin {
            return effectiveLatinLayoutModeForHeight() == .flick
        }

        return false
    }

    private func portraitHeightFineTuning(for profile: PortraitHeightProfile) -> CGFloat {
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
            // 5x2も他モードと同程度の見た目高さに寄せる。
            return 0
        case .emoji:
            // 絵文字/記号入力もテキスト系モードと同等の見た目高さに揃える。
            return 46
        }
    }

    private func candidateHeaderHeightCompensation(
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
        }
    }

    private func basePortraitKeyboardHeight(
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
            // Header + top number row + 3 main rows + action row + internal row spacing + padding.
            return headerHeight
                + rowSpacing
                + Self.mainKeyRowHeight * 4
                + Self.actionRowHeight
                + rowSpacing * 4
                + Self.keyboardVerticalPadding
        case .emoji:
            // 絵文字/記号入力もテキスト系と同じ基準高さに揃える。
            return headerHeight
                + rowSpacing
                + Self.mainKeyRowHeight * 4
                + rowSpacing * 3
                + Self.keyboardVerticalPadding
        }
    }

    private func effectivePortraitBottomInset(for shorterScreenEdge: CGFloat) -> CGFloat {
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

    private func preferredKeyboardHeight(using configuration: RenderConfiguration? = nil) -> CGFloat {
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

    private func installKeyboardHeightConstraintIfNeeded(using configuration: RenderConfiguration? = nil) {
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

    private func updateKeyboardHeightIfNeeded(using configuration: RenderConfiguration? = nil) {
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

    private func sharedStringValue(
        from defaults: UserDefaults?,
        key: String,
        fallback: String
    ) -> String {
        defaults?.string(forKey: key) ?? fallback
    }

    private func sharedBoolValue(
        from defaults: UserDefaults?,
        key: String,
        fallback: Bool
    ) -> Bool {
        (defaults?.object(forKey: key) as? Bool) ?? fallback
    }

    private func sharedEnumValue<Value: RawRepresentable>(
        from defaults: UserDefaults?,
        key: String,
        fallback: Value
    ) -> Value where Value.RawValue == String {
        let rawValue = sharedStringValue(from: defaults, key: key, fallback: fallback.rawValue)
        return Value(rawValue: rawValue) ?? fallback
    }

    private func sharedDoubleValue(
        from defaults: UserDefaults?,
        key: String,
        fallback: Double,
        range: ClosedRange<Double>
    ) -> Double {
        guard let defaults,
                let number = defaults.object(forKey: key) as? NSNumber else {
            return fallback
        }

        return min(max(number.doubleValue, range.lowerBound), range.upperBound)
    }

    private func sharedFlickGuideDisplayModeValue(
        from defaults: UserDefaults?,
        key: String
    ) -> FlickGuideDisplayMode {
        if let rawValue = defaults?.string(forKey: key),
            let mode = FlickGuideDisplayMode(rawValue: rawValue) {
            return mode
        }

        let legacyShowsGuide = sharedBoolValue(
            from: defaults,
            key: SharedDefaultsKeys.showsFlickGuideCharacters,
            fallback: true
        )

        return legacyShowsGuide ? .fourDirections : .off
    }

    private func currentKanaKanjiCandidateSourceMode(from defaults: UserDefaults?) -> KanaKanjiCandidateSourceMode {
        let rawValue = sharedStringValue(
            from: defaults,
            key: SharedDefaultsKeys.kanaKanjiCandidateSourceMode,
            fallback: KanaKanjiCandidateSourceMode.surface.rawValue
        )

        return KanaKanjiCandidateSourceMode(rawValue: rawValue) ?? .surface
    }

    private func currentTemperatureUnit() -> TemperatureUnitPreference {
        if let rawValue = UserDefaults.standard.string(forKey: "AppleTemperatureUnit"),
            let unit = TemperatureUnitPreference.fromAppleTemperatureUnit(rawValue) {
            return unit
        }

        if #available(iOS 16.0, *) {
            return Locale.autoupdatingCurrent.measurementSystem == .us ? .fahrenheit : .celsius
        }

        return Locale.autoupdatingCurrent.usesMetricSystem ? .celsius : .fahrenheit
    }

    private func makeRenderConfiguration() -> RenderConfiguration {
        let sharedDefaults = UserDefaults(suiteName: SharedDefaultsKeys.appGroupID)
        let candidateSourceMode = currentKanaKanjiCandidateSourceMode(from: sharedDefaults)
        let candidatePresentation = makeCandidatePresentation(systemCandidateMode: candidateSourceMode)
        let directionProfile = sharedEnumValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.directionProfile,
            fallback: FlickDirectionProfile.ecritu
        )
        let kanaLayoutMode = sharedEnumValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.kanaLayoutMode,
            fallback: KanaLayoutMode.fiveByTwo
        )
        let kanaModifierPlacementMode = sharedEnumValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.kanaModifierPlacement,
            fallback: KanaModifierPlacementMode.prefix
        )
        let postModifierContext: String?

        if !composingRawText.isEmpty {
            postModifierContext = composingRawText
        } else if let activeConversion {
            postModifierContext = activeConversion.committedText
        } else {
            postModifierContext = textDocumentProxy.documentContextBeforeInput
        }

        let kanaPostModifierButtonState = FlickKanaLayout.postModifierButtonState(
            contextBeforeInput: postModifierContext
        )
        let numberLayoutMode = sharedEnumValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.numberLayoutMode,
            fallback: NumberLayoutMode.calculette
        )
        let latinLayoutMode = sharedEnumValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.latinLayoutMode,
            fallback: LatinLayoutMode.azerty
        )
        let accentPaletteRawValue = sharedStringValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.accentPalette,
            fallback: "emeraude"
        )
        let keyboardBackgroundThemeRawValue = sharedStringValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.keyboardBackgroundTheme,
            fallback: "bleu"
        )
        let basicSymbolOrderRawValue = sharedStringValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.basicSymbolOrder,
            fallback: "ascii"
        )
        let temperatureUnitRawValue = currentTemperatureUnit().rawValue
        let returnKeyType = textDocumentProxy.returnKeyType
        let hasAnyText = textDocumentProxy.hasText
        let hasPendingComposingText = !candidatePresentation.composingText.isEmpty
        let returnKeySystemImageName: String? = returnKeyType == .search ? "magnifyingglass" : nil
        let isReturnKeyEnabled = hasPendingComposingText || (returnKeyType == .search ? hasAnyText : true)
        let kanaFlickGuideDisplayMode = sharedFlickGuideDisplayModeValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.kanaFlickGuideDisplayMode
        )
        let latinFlickGuideDisplayMode = sharedFlickGuideDisplayModeValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.latinFlickGuideDisplayMode
        )
        let numberFlickGuideDisplayMode = sharedFlickGuideDisplayModeValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.numberFlickGuideDisplayMode
        )
        let keyRepeatInitialDelay = sharedDoubleValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.keyRepeatInitialDelay,
            fallback: 0.5,
            range: 0.1...0.8
        )
        let keyRepeatInterval = sharedDoubleValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.keyRepeatInterval,
            fallback: 0.1,
            range: 0.05...0.2
        )
        let kanaModeSwitcherTapActionRawValue = sharedStringValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.kanaModeSwitcherTapAction,
            fallback: "emoji"
        )
        let kanaModeSwitcherRightFlickActionRawValue = sharedStringValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.kanaModeSwitcherRightFlickAction,
            fallback: "kaomoji"
        )
        let kanaModeSwitcherUpFlickActionRawValue = sharedStringValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.kanaModeSwitcherUpFlickAction,
            fallback: "symbols"
        )
        let landscapeCandidateSideRawValue = sharedStringValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.landscapeCandidateSide,
            fallback: "left"
        )
        let landscapeNumberPaneSideRawValue = sharedStringValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.landscapeNumberPaneSide,
            fallback: "left"
        )

        return RenderConfiguration(
            directionProfile: directionProfile,
            kanaLayoutMode: kanaLayoutMode,
            kanaModifierPlacementMode: kanaModifierPlacementMode,
            kanaPostModifierButtonState: kanaPostModifierButtonState,
            numberLayoutMode: numberLayoutMode,
            latinLayoutMode: latinLayoutMode,
            accentPaletteRawValue: accentPaletteRawValue,
            keyboardBackgroundThemeRawValue: keyboardBackgroundThemeRawValue,
            basicSymbolOrderRawValue: basicSymbolOrderRawValue,
            temperatureUnitRawValue: temperatureUnitRawValue,
            spaceToastTrigger: spaceToastTrigger,
            returnKeySystemImageName: returnKeySystemImageName,
            isReturnKeyEnabled: isReturnKeyEnabled,
            kanaFlickGuideDisplayMode: kanaFlickGuideDisplayMode,
            latinFlickGuideDisplayMode: latinFlickGuideDisplayMode,
            numberFlickGuideDisplayMode: numberFlickGuideDisplayMode,
            keyRepeatInitialDelay: keyRepeatInitialDelay,
            keyRepeatInterval: keyRepeatInterval,
            kanaModeSwitcherTapActionRawValue: kanaModeSwitcherTapActionRawValue,
            kanaModeSwitcherRightFlickActionRawValue: kanaModeSwitcherRightFlickActionRawValue,
            kanaModeSwitcherUpFlickActionRawValue: kanaModeSwitcherUpFlickActionRawValue,
            landscapeCandidateSideRawValue: landscapeCandidateSideRawValue,
            landscapeNumberPaneSideRawValue: landscapeNumberPaneSideRawValue,
            showsNextKeyboardKey: needsInputModeSwitchKey,
            shortcutVocabulary: kanaKanjiStore.shortcutVocabulary(),
            composingText: candidatePresentation.composingText,
            conversionCandidates: candidatePresentation.candidates,
            selectedConversionCandidateIndex: candidatePresentation.selectedIndex
        )
    }

    private func makeRootView(from configuration: RenderConfiguration) -> KeyboardRootView {

        return KeyboardRootView(
            onTextInput: { [weak self] text in
                self?.handleTextInput(text)
            },
            onDeleteBackward: { [weak self] in
                self?.handleDeleteBackward()
            },
            onSpace: { [weak self] in
                self?.handleSpaceInput()
            },
            onReturn: { [weak self] in
                self?.handleReturnInput()
            },
            onAdvanceKeyboard: { [weak self] in
                self?.advanceToNextInputMode()
            },
            onApplyKanaPostModifier: { [weak self] buttonState, preferLatestContext in
                self?.applyKanaPostModifier(
                    buttonState,
                    preferLatestContext: preferLatestContext
                ) ?? false
            },
            onSelectConversionCandidate: { [weak self] index in
                self?.handleConversionCandidateSelection(index)
            },
            onCommitComposingText: { [weak self] in
                self?.handleCommitComposingText()
            },
            onInputModeChanged: { [weak self] mode in
                guard let self else {
                    return
                }

                let previousMode = self.currentInputMode

                guard previousMode != mode else {
                    return
                }

                if previousMode == .kana,
                    mode != .kana {
                    self.commitPendingComposingTextBeforeInputModeSwitch()
                }

                self.currentInputMode = mode

                if mode != .kana {
                    self.clearComposingState()
                }

                self.refreshKeyboardStateAsync()
            },
            showsNextKeyboardKey: configuration.showsNextKeyboardKey,
            directionProfile: configuration.directionProfile,
            kanaLayoutMode: configuration.kanaLayoutMode,
            kanaModifierPlacementMode: configuration.kanaModifierPlacementMode,
            kanaPostModifierButtonState: configuration.kanaPostModifierButtonState,
            numberLayoutMode: configuration.numberLayoutMode,
            latinLayoutMode: configuration.latinLayoutMode,
            accentPaletteRawValue: configuration.accentPaletteRawValue,
            keyboardBackgroundThemeRawValue: configuration.keyboardBackgroundThemeRawValue,
            basicSymbolOrderRawValue: configuration.basicSymbolOrderRawValue,
            temperatureUnitRawValue: configuration.temperatureUnitRawValue,
            spaceToastTrigger: configuration.spaceToastTrigger,
            returnKeySystemImageName: configuration.returnKeySystemImageName,
            isReturnKeyEnabled: configuration.isReturnKeyEnabled,
            kanaFlickGuideDisplayMode: configuration.kanaFlickGuideDisplayMode,
            latinFlickGuideDisplayMode: configuration.latinFlickGuideDisplayMode,
            numberFlickGuideDisplayMode: configuration.numberFlickGuideDisplayMode,
            keyRepeatInitialDelay: configuration.keyRepeatInitialDelay,
            keyRepeatInterval: configuration.keyRepeatInterval,
            kanaModeSwitcherTapActionRawValue: configuration.kanaModeSwitcherTapActionRawValue,
            kanaModeSwitcherRightFlickActionRawValue: configuration.kanaModeSwitcherRightFlickActionRawValue,
            kanaModeSwitcherUpFlickActionRawValue: configuration.kanaModeSwitcherUpFlickActionRawValue,
            landscapeCandidateSideRawValue: configuration.landscapeCandidateSideRawValue,
            landscapeNumberPaneSideRawValue: configuration.landscapeNumberPaneSideRawValue,
            shortcutVocabulary: configuration.shortcutVocabulary,
            composingText: configuration.composingText,
            conversionCandidates: configuration.conversionCandidates,
            selectedConversionCandidateIndex: configuration.selectedConversionCandidateIndex,
            initialSpaceToastText: "écritu"
        )
    }

    func currentKanaKanjiCandidateSourceModeFromSharedDefaults() -> KanaKanjiCandidateSourceMode {
        currentKanaKanjiCandidateSourceMode(
            from: UserDefaults(suiteName: SharedDefaultsKeys.appGroupID)
        )
    }
}
