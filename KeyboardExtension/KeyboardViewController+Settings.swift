import SwiftUI
import UIKit
import CoreFoundation
import Darwin
import Contacts

extension KeyboardViewController {
    func applyConverterFeatureFlagsFromSharedDefaults() {
        let historicalKanaAllowed = sharedBoolValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.historicalKanaCandidatesEnabled,
            fallback: false
        )
        kanaKanjiConverter.setHistoricalKanaSurfaceAllowed(historicalKanaAllowed)
    }

    func startObservingSettingsDidChange() {
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

    func stopObservingSettingsDidChange() {
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

    func keyboardInputModeName(_ mode: KeyboardInputMode) -> String {
        switch mode {
        case .kana:
            return "kana"
        case .number:
            return "number"
        case .latin:
            return "latin"
        case .emoji:
            return "emoji"
        }
    }

    func effectiveShortcutVocabularyForRender() -> [String] {
        switch memoryFailSafeProfile {
        case .normal:
            return kanaKanjiStore.shortcutVocabulary()
        case .elevated:
            return Array(kanaKanjiStore.shortcutVocabulary().prefix(20))
        case .critical:
            return []
        }
    }

    func handleSharedSettingsDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            guard !self.shouldSuppressHeavyOperations(reason: "handleSharedSettingsDidChange") else {
                return
            }

            self.updateMemoryFailSafeProfile(trigger: "handleSharedSettingsDidChange")

            self.updateKeyboardDiagnosticsHeartbeat(
                event: "共有設定変更通知を受信",
                appendLog: true
            )
            self.applyConverterFeatureFlagsFromSharedDefaults()
            self.kanaKanjiConverter.clearSharedDataCaches()
            self.invalidateSettledCandidatePresentation()

            if self.memoryFailSafeProfile == .critical {
                self.hasDeferredSharedSettingsCatchUp = true

                if !self.currentContactCandidateDisplayModeFromSharedDefaults().usesContacts {
                    self.clearContactCandidatesIfNeeded(refreshKeyboardState: false)
                }

                self.appendKeyboardDiagnosticsLog(
                    "criticalフェイルセーフで共有設定変更処理を軽量化 contactRefresh=skip refresh=async deferredCatchUp=true",
                    file: #fileID,
                    line: #line,
                    function: #function
                )
                self.refreshKeyboardStateAsync()
                return
            }

            self.hasDeferredSharedSettingsCatchUp = false
            self.refreshContactCandidatesIfNeeded(force: true)
            self.refreshKeyboardState(trigger: "settingsChanged")
        }
    }

    func sharedStringValue(
        from defaults: UserDefaults?,
        key: String,
        fallback: String
    ) -> String {
        defaults?.string(forKey: key) ?? fallback
    }

    func sharedBoolValue(
        from defaults: UserDefaults?,
        key: String,
        fallback: Bool
    ) -> Bool {
        (defaults?.object(forKey: key) as? Bool) ?? fallback
    }

    func sharedEnumValue<Value: RawRepresentable>(
        from defaults: UserDefaults?,
        key: String,
        fallback: Value
    ) -> Value where Value.RawValue == String {
        let rawValue = sharedStringValue(from: defaults, key: key, fallback: fallback.rawValue)
        return Value(rawValue: rawValue) ?? fallback
    }

    func sharedDoubleValue(
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

    func sharedFlickGuideDisplayModeValue(
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

    func currentKanaKanjiCandidateSourceMode(from defaults: UserDefaults?) -> KanaKanjiCandidateSourceMode {
        let rawValue = sharedStringValue(
            from: defaults,
            key: SharedDefaultsKeys.kanaKanjiCandidateSourceMode,
            fallback: KanaKanjiCandidateSourceMode.surface.rawValue
        )

        return KanaKanjiCandidateSourceMode(rawValue: rawValue) ?? .surface
    }

    func currentContactCandidateDisplayMode(from defaults: UserDefaults?) -> ContactCandidateDisplayMode {
        let rawValue = sharedStringValue(
            from: defaults,
            key: SharedDefaultsKeys.contactCandidateDisplayMode,
            fallback: ContactCandidateDisplayMode.namesOnly.rawValue
        )

        return ContactCandidateDisplayMode(rawValue: rawValue) ?? .namesOnly
    }

    func currentUserDictionaryCandidateDisplayMode(
        from defaults: UserDefaults?
    ) -> UserDictionaryCandidateDisplayMode {
        let rawValue = sharedStringValue(
            from: defaults,
            key: SharedDefaultsKeys.userDictionaryCandidateDisplayMode,
            fallback: UserDictionaryCandidateDisplayMode.on.rawValue
        )

        return UserDictionaryCandidateDisplayMode(rawValue: rawValue) ?? .on
    }

    func currentEmojiCandidateDisplayEnabled(from defaults: UserDefaults?) -> Bool {
        sharedBoolValue(
            from: defaults,
            key: SharedDefaultsKeys.emojiCandidateDisplayEnabled,
            fallback: true
        )
    }

    func currentKaomojiCandidateDisplayEnabled(from defaults: UserDefaults?) -> Bool {
        sharedBoolValue(
            from: defaults,
            key: SharedDefaultsKeys.kaomojiCandidateDisplayEnabled,
            fallback: true
        )
    }

    func currentDelimiterAutoCommitCandidateIndex(from defaults: UserDefaults?) -> Int {
        let rawValue = sharedStringValue(
            from: defaults,
            key: SharedDefaultsKeys.delimiterAutoCommitCandidate,
            fallback: "zero"
        )

        switch rawValue {
        case "one":
            return 1
        default:
            return 0
        }
    }

    func currentTemperatureUnit() -> TemperatureUnitPreference {
        if let rawValue = UserDefaults.standard.string(forKey: "AppleTemperatureUnit"),
            let unit = TemperatureUnitPreference.fromAppleTemperatureUnit(rawValue) {
            return unit
        }

        return Locale.autoupdatingCurrent.measurementSystem == .us ? .fahrenheit : .celsius
    }

    func currentKanaKanjiCandidateSourceModeFromSharedDefaults() -> KanaKanjiCandidateSourceMode {
        currentKanaKanjiCandidateSourceMode(
            from: sharedDefaults
        )
    }

    func currentUserDictionaryCandidateDisplayModeFromSharedDefaults() -> UserDictionaryCandidateDisplayMode {
        currentUserDictionaryCandidateDisplayMode(
            from: sharedDefaults
        )
    }

    func currentContactCandidateDisplayModeFromSharedDefaults() -> ContactCandidateDisplayMode {
        currentContactCandidateDisplayMode(
            from: sharedDefaults
        )
    }

    func currentEmojiCandidateDisplayEnabledFromSharedDefaults() -> Bool {
        currentEmojiCandidateDisplayEnabled(
            from: sharedDefaults
        )
    }

    func currentKaomojiCandidateDisplayEnabledFromSharedDefaults() -> Bool {
        currentKaomojiCandidateDisplayEnabled(
            from: sharedDefaults
        )
    }

    func currentDelimiterAutoCommitCandidateIndexFromSharedDefaults() -> Int {
        currentDelimiterAutoCommitCandidateIndex(
            from: sharedDefaults
        )
    }

    func currentIdleCommitEnabled(from defaults: UserDefaults?) -> Bool {
        sharedBoolValue(
            from: defaults,
            key: SharedDefaultsKeys.idleCommitEnabled,
            fallback: false
        )
    }

    func currentIdleCommitInterval(from defaults: UserDefaults?) -> TimeInterval {
        sharedDoubleValue(
            from: defaults,
            key: SharedDefaultsKeys.idleCommitInterval,
            fallback: Self.idleCommitIntervalDefault,
            range: Self.idleCommitIntervalRange
        )
    }
}
