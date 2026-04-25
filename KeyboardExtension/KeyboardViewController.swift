import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    private var hostingController: UIHostingController<KeyboardRootView>?
    private var lastRenderConfiguration: RenderConfiguration?
    private var keyboardHeightConstraint: NSLayoutConstraint?
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
        static let appGroupID: String = {
            guard
                let value = Bundle.main.object(forInfoDictionaryKey: "EcrituAppGroupIdentifier") as? String,
                !value.isEmpty
            else {
                return "group.com.kusakabe.ecritu"
            }
            return value
        }()
        static let directionProfile = "flickDirectionProfile"
        static let kanaLayoutMode = "kanaLayoutMode"
        static let kanaModifierPlacement = "kanaModifierPlacement"
        static let numberLayoutMode = "numberLayoutMode"
        static let latinLayoutMode = "latinLayoutMode"
        static let accentPalette = "accentPalette"
        static let keyboardBackgroundTheme = "keyboardBackgroundTheme"
        static let kanaFlickGuideDisplayMode = "flickGuideDisplayModeKana"
        static let latinFlickGuideDisplayMode = "flickGuideDisplayModeLatin"
        static let numberFlickGuideDisplayMode = "flickGuideDisplayModeNumber"
        static let showsFlickGuideCharacters = "showsFlickGuideCharacters"
        static let keyRepeatInitialDelay = "keyRepeatInitialDelay"
        static let keyRepeatInterval = "keyRepeatInterval"
        static let kanaKanjiCandidateSourceMode = "kanaKanjiCandidateSourceMode"
    }

    private static let hostTopOverlap: CGFloat = 0
    private static let baselinePortraitScreenHeight: CGFloat = 844
    private static let baselinePortraitKeyboardHeight: CGFloat = 372
    private static let minimumPortraitKeyboardHeight: CGFloat = 336
    private static let maximumPortraitKeyboardHeight: CGFloat = 436
    private static let landscapeKeyboardHeight: CGFloat = 244
    private static let baseKeyboardBackgroundColor = UIColor(
        red: 0.89,
        green: 0.90,
        blue: 0.92,
        alpha: 1.0
    )

    private struct RenderConfiguration: Equatable {
        let directionProfile: FlickDirectionProfile
        let kanaLayoutMode: KanaLayoutMode
        let kanaModifierPlacementMode: KanaModifierPlacementMode
        let kanaPostModifierButtonState: KanaPostModifierButtonState
        let numberLayoutMode: NumberLayoutMode
        let latinLayoutMode: LatinLayoutMode
        let accentPaletteRawValue: String
        let keyboardBackgroundThemeRawValue: String
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
        setupKeyboardView()
        kanaKanjiConverter.preloadSystemDictionaryIfNeeded { [weak self] in
            self?.refreshKeyboardStateAsync()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        configureInputAssistantBar()
        installKeyboardHeightConstraintIfNeeded()
        updateKeyboardHeightIfNeeded()
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

        installKeyboardHeightConstraintIfNeeded()
        updateKeyboardHeightIfNeeded()

        guard lastRenderConfiguration != nil else {
            return
        }

        applyKeyboardBaseBackground()
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
        installKeyboardHeightConstraintIfNeeded()
        updateKeyboardHeightIfNeeded()

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

    private func refreshKeyboardState() {
        let configuration = makeRenderConfiguration()
        applyKeyboardBaseBackground()

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

    private func preferredKeyboardHeight() -> CGFloat {
        let screenBounds = view.window?.windowScene?.screen.bounds ?? UIScreen.main.bounds
        let longerScreenEdge = max(screenBounds.width, screenBounds.height)
        let shorterScreenEdge = min(screenBounds.width, screenBounds.height)
        let isLandscapeOrientation = view.bounds.width > view.bounds.height

        if isLandscapeOrientation {
            return min(Self.landscapeKeyboardHeight, shorterScreenEdge * 0.9)
        }

        let scaledPortraitKeyboardHeight = Self.baselinePortraitKeyboardHeight
            * (longerScreenEdge / Self.baselinePortraitScreenHeight)

        return min(
            max(round(scaledPortraitKeyboardHeight), Self.minimumPortraitKeyboardHeight),
            Self.maximumPortraitKeyboardHeight
        )
    }

    private func installKeyboardHeightConstraintIfNeeded() {
        guard keyboardHeightConstraint == nil else {
            return
        }

        let constraint = view.heightAnchor.constraint(equalToConstant: preferredKeyboardHeight())
        constraint.priority = UILayoutPriority(999)
        constraint.isActive = true
        keyboardHeightConstraint = constraint
    }

    private func updateKeyboardHeightIfNeeded() {
        guard let keyboardHeightConstraint else {
            return
        }

        let nextHeight = preferredKeyboardHeight()

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
