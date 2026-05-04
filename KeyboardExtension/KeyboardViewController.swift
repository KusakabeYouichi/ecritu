import SwiftUI
import UIKit
import CoreFoundation

final class KeyboardViewController: UIInputViewController {
    private var hostingController: UIHostingController<KeyboardRootView>?
    private var lastRenderConfiguration: RenderConfiguration?
    private var keyboardHeightConstraint: NSLayoutConstraint?
    private var cachedPortraitSafeAreaBottomInset: CGFloat?
    private var isObservingSettingsDidChange = false
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
    private static let landscapeKeyboardHeight: CGFloat = 244
    private static let baseKeyboardBackgroundColor = UIColor(
        red: 0.89,
        green: 0.90,
        blue: 0.92,
        alpha: 1.0
    )

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
        let showsNextKeyboardKey: Bool
        let composingText: String
        let conversionCandidates: [String]
        let selectedConversionCandidateIndex: Int?
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureInputAssistantBar()
        startObservingSettingsDidChange()
        setupKeyboardView()
        kanaKanjiConverter.preloadSystemDictionaryIfNeeded { [weak self] in
            self?.refreshKeyboardStateAsync()
        }
    }

    deinit {
        stopObservingSettingsDidChange()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        configureInputAssistantBar()
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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let configuration = makeRenderConfiguration()
        installKeyboardHeightConstraintIfNeeded(using: configuration)
        updateKeyboardHeightIfNeeded(using: configuration)

        guard lastRenderConfiguration != nil else {
            return
        }

        applyKeyboardBaseBackground()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        guard
            previousTraitCollection?.horizontalSizeClass != traitCollection.horizontalSizeClass
                || previousTraitCollection?.verticalSizeClass != traitCollection.verticalSizeClass
        else {
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
        applyKeyboardBaseBackground()
    }

    private func configureInputAssistantBar() {
        let assistant = inputAssistantItem
        assistant.leadingBarButtonGroups = []
        assistant.trailingBarButtonGroups = []
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
            fallback: .flick
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

    private func portraitHeightFineTuning(for profile: PortraitHeightProfile) -> CGFloat {
        switch profile {
        case .kanaThreeByThree:
            // 3x3+わは独立補正で高さを合わせる。
            return 40
        case .compactGrid:
            // 数字/ラテンフリック系も3x3+わと同一高さに揃える。
            return 40
        case .compactActionRow:
            // compactActionRowはベースが4pt低い分だけ加算して揃える。
            return 44
        case .kanaFiveByTwo:
            // 5x2は現状高めに見えるため、やや下げる。
            return -6
        case .emoji:
            // 絵文字/記号入力もテキスト系モードと同等の見た目高さに揃える。
            return 40
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
            return min(Self.landscapeKeyboardHeight, shorterScreenEdge * 0.9)
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
        guard keyboardHeightConstraint == nil else {
            return
        }

        let constraint = view.heightAnchor.constraint(
            equalToConstant: preferredKeyboardHeight(using: configuration)
        )
        constraint.priority = UILayoutPriority(999)
        constraint.isActive = true
        keyboardHeightConstraint = constraint
    }

    private func updateKeyboardHeightIfNeeded(using configuration: RenderConfiguration? = nil) {
        guard let keyboardHeightConstraint else {
            return
        }

        let nextHeight = preferredKeyboardHeight(using: configuration)

        guard abs(keyboardHeightConstraint.constant - nextHeight) > 0.5 else {
            return
        }

        keyboardHeightConstraint.constant = nextHeight

        view.setNeedsLayout()
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
            fallback: LatinLayoutMode.flick
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
            showsNextKeyboardKey: needsInputModeSwitchKey,
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
            onApplyKanaPostModifier: { [weak self] buttonState in
                self?.applyKanaPostModifier(buttonState) ?? false
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

                guard self.currentInputMode != mode else {
                    return
                }

                self.currentInputMode = mode

                if mode != .kana {
                    self.commitActiveConversion(learn: true)
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
