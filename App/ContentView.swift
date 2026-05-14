import SwiftUI

struct ContentView: View {
    private static let sharedDefaults = UserDefaults(suiteName: SettingsKeys.appGroupID)
    private static let editionUpdatedAtRaw: String = "20260514104928"

    private static func editionDateText(from rawValue: String?) -> String? {
        guard let rawValue,
            rawValue.count >= 8 else {
            return nil
        }

        let yearPart = rawValue.prefix(4)
        let monthPart = rawValue.dropFirst(4).prefix(2)
        let dayPart = rawValue.dropFirst(6).prefix(2)

        guard let month = Int(monthPart),
            let day = Int(dayPart) else {
            return nil
        }

        return "\(yearPart)-\(month)-\(day)"
    }

    private static let editionNumberText: String = {
        let info = Bundle.main.infoDictionary ?? [:]
        let editionNumber = (info["CFBundleVersion"] as? String) ?? "?"

        if let dateText = editionDateText(from: editionUpdatedAtRaw) {
            return "édition n°\(editionNumber) (\(dateText))"
        }

        return "édition n°\(editionNumber)"
    }()

    @AppStorage(
        SettingsKeys.directionProfile,
        store: Self.sharedDefaults
    )
    private var directionProfileRawValue: String = DirectionOption.ecritu.rawValue

    @AppStorage(
        SettingsKeys.kanaLayoutMode,
        store: Self.sharedDefaults
    )
    private var kanaLayoutModeRawValue: String = KanaLayoutOption.fiveByTwo.rawValue

    @AppStorage(
        SettingsKeys.kanaModifierPlacement,
        store: Self.sharedDefaults
    )
    private var kanaModifierPlacementRawValue: String = KanaModifierPlacementOption.prefix.rawValue

    @AppStorage(
        SettingsKeys.latinLayoutMode,
        store: Self.sharedDefaults
    )
    private var latinLayoutModeRawValue: String = LatinLayoutOption.azerty.rawValue

    @AppStorage(
        SettingsKeys.numberLayoutMode,
        store: Self.sharedDefaults
    )
    private var numberLayoutModeRawValue: String = NumberLayoutOption.calculette.rawValue

    @AppStorage(
        SettingsKeys.basicSymbolOrder,
        store: Self.sharedDefaults
    )
    private var basicSymbolOrderRawValue: String = BasicSymbolOrderOption.ascii.rawValue

    @AppStorage(
        SettingsKeys.accentPalette,
        store: Self.sharedDefaults
    )
    private var accentPaletteRawValue: String = AccentColorOption.emeraude.rawValue

    @AppStorage(
        SettingsKeys.keyboardBackgroundTheme,
        store: Self.sharedDefaults
    )
    private var keyboardBackgroundThemeRawValue: String = KeyboardBackgroundThemeOption.bleu.rawValue

    @AppStorage(
        SettingsKeys.kanaFlickGuideDisplayMode,
        store: Self.sharedDefaults
    )
    private var kanaFlickGuideDisplayModeRawValue: String = FlickGuideDisplayOption.fourDirections.rawValue

    @AppStorage(
        SettingsKeys.latinFlickGuideDisplayMode,
        store: Self.sharedDefaults
    )
    private var latinFlickGuideDisplayModeRawValue: String = FlickGuideDisplayOption.fourDirections.rawValue

    @AppStorage(
        SettingsKeys.numberFlickGuideDisplayMode,
        store: Self.sharedDefaults
    )
    private var numberFlickGuideDisplayModeRawValue: String = FlickGuideDisplayOption.fourDirections.rawValue

    @AppStorage(
        SettingsKeys.keyRepeatInitialDelay,
        store: Self.sharedDefaults
    )
    private var keyRepeatInitialDelay: Double = RepeatSettings.initialDelayDefault

    @AppStorage(
        SettingsKeys.keyRepeatInterval,
        store: Self.sharedDefaults
    )
    private var keyRepeatInterval: Double = RepeatSettings.intervalDefault

    @AppStorage(
        SettingsKeys.kanaModeSwitcherTapAction,
        store: Self.sharedDefaults
    )
    private var kanaModeSwitcherTapActionRawValue: String = KanaModeSwitcherActionOption.emoji.rawValue

    @AppStorage(
        SettingsKeys.kanaModeSwitcherRightFlickAction,
        store: Self.sharedDefaults
    )
    private var kanaModeSwitcherRightFlickActionRawValue: String = KanaModeSwitcherActionOption.kaomoji.rawValue

    @AppStorage(
        SettingsKeys.kanaModeSwitcherUpFlickAction,
        store: Self.sharedDefaults
    )
    private var kanaModeSwitcherUpFlickActionRawValue: String = KanaModeSwitcherActionOption.symbols.rawValue

    @AppStorage(
        SettingsKeys.kanaKanjiCandidateSourceMode,
        store: Self.sharedDefaults
    )
    private var kanaKanjiCandidateSourceModeRawValue: String = KanaKanjiCandidateSourceModeOption.surface.rawValue

    @State private var userDictionaryEntries: [VocabularyEntry] = []
    @State private var userDictionaryReadingInput = ""
    @State private var userDictionaryCandidateInput = ""
    @State private var isUserDictionaryRegistrationVisible = false
    @State private var userDictionaryScrollIndexTitle = ""
    @State private var isUserDictionaryScrollIndexVisible = false
    @State private var suppressionDictionaryEntries: [VocabularyEntry] = []
    @State private var suppressionDictionaryReadingInput = ""
    @State private var suppressionDictionaryCandidateInput = ""
    @State private var isSuppressionDictionaryRegistrationVisible = false
    @State private var suppressionDictionaryScrollIndexTitle = ""
    @State private var isSuppressionDictionaryScrollIndexVisible = false
    @State private var shortcutDictionaryEntries: [VocabularyEntry] = []
    @State private var shortcutDictionaryCandidateInput = ""
    @State private var isShortcutDictionaryRegistrationVisible = false
    @State private var firstVocabularyEntries: [VocabularyEntry] = []
    @State private var firstVocabularyScrollIndexTitle = ""
    @State private var isFirstVocabularyScrollIndexVisible = false
    @State private var secondVocabularyEntries: [VocabularyEntry] = []
    @State private var secondVocabularyScrollIndexTitle = ""
    @State private var isSecondVocabularyScrollIndexVisible = false
    @GestureState private var isEditionNumberPressed = false

    private let setupSteps: [String] = [
        "設定 > 一般 > キーボード > キーボード > 新しいキーボードを追加",
        "作成したキーボードを有効化",
        "入力画面で地球儀キーから切り替え"
    ]

    private func rawValueSelection<Option: RawRepresentable>(
        from rawValue: String,
        default fallback: Option,
        onUpdate: @escaping (String) -> Void
    ) -> Binding<Option> where Option.RawValue == String {
        Binding(
            get: { Option(rawValue: rawValue) ?? fallback },
            set: { onUpdate($0.rawValue) }
        )
    }

    private var directionSelection: Binding<DirectionOption> {
        rawValueSelection(from: directionProfileRawValue, default: .ecritu) {
            directionProfileRawValue = $0
        }
    }

    private var kanaLayoutSelection: Binding<KanaLayoutOption> {
        rawValueSelection(from: kanaLayoutModeRawValue, default: .fiveByTwo) {
            kanaLayoutModeRawValue = $0
        }
    }

    private var kanaModifierPlacementSelection: Binding<KanaModifierPlacementOption> {
        rawValueSelection(from: kanaModifierPlacementRawValue, default: .prefix) {
            kanaModifierPlacementRawValue = $0
        }
    }

    private var latinLayoutSelection: Binding<LatinLayoutOption> {
        rawValueSelection(from: latinLayoutModeRawValue, default: .azerty) {
            latinLayoutModeRawValue = $0
        }
    }

    private var numberLayoutSelection: Binding<NumberLayoutOption> {
        rawValueSelection(from: numberLayoutModeRawValue, default: .calculette) {
            numberLayoutModeRawValue = $0
        }
    }

    private var basicSymbolOrderSelection: Binding<BasicSymbolOrderOption> {
        rawValueSelection(from: basicSymbolOrderRawValue, default: .ascii) {
            basicSymbolOrderRawValue = $0
        }
    }

    private var kanaFlickGuideDisplayModeSelection: Binding<FlickGuideDisplayOption> {
        rawValueSelection(from: kanaFlickGuideDisplayModeRawValue, default: .fourDirections) {
            kanaFlickGuideDisplayModeRawValue = $0
        }
    }

    private var latinFlickGuideDisplayModeSelection: Binding<FlickGuideDisplayOption> {
        rawValueSelection(from: latinFlickGuideDisplayModeRawValue, default: .fourDirections) {
            latinFlickGuideDisplayModeRawValue = $0
        }
    }

    private var numberFlickGuideDisplayModeSelection: Binding<FlickGuideDisplayOption> {
        rawValueSelection(from: numberFlickGuideDisplayModeRawValue, default: .fourDirections) {
            numberFlickGuideDisplayModeRawValue = $0
        }
    }

    private var isLatinFlickLayoutSelected: Bool {
        (LatinLayoutOption(rawValue: latinLayoutModeRawValue) ?? .azerty) == .flick
    }

    private var kanaKanjiCandidateSourceModeSelection: Binding<KanaKanjiCandidateSourceModeOption> {
        rawValueSelection(from: kanaKanjiCandidateSourceModeRawValue, default: .surface) {
            kanaKanjiCandidateSourceModeRawValue = $0
        }
    }

    private var accentPaletteSelection: Binding<AccentColorOption> {
        rawValueSelection(from: accentPaletteRawValue, default: .emeraude) {
            accentPaletteRawValue = $0
        }
    }

    private var keyboardBackgroundThemeSelection: Binding<KeyboardBackgroundThemeOption> {
        rawValueSelection(from: keyboardBackgroundThemeRawValue, default: .bleu) {
            keyboardBackgroundThemeRawValue = $0
        }
    }

    private func snappedRepeatValue(_ value: Double, to defaultValue: Double) -> Double {
        abs(value - defaultValue) <= RepeatSettings.snapThreshold ? defaultValue : value
    }

    private func migrateLegacyFlickGuideSettingIfNeeded() {
        guard let defaults = Self.sharedDefaults else {
            return
        }

        let guideModeKeys = [
            SettingsKeys.kanaFlickGuideDisplayMode,
            SettingsKeys.latinFlickGuideDisplayMode,
            SettingsKeys.numberFlickGuideDisplayMode
        ]

        let hasStoredNewGuideMode = guideModeKeys.contains { key in
            defaults.object(forKey: key) != nil
        }

        guard !hasStoredNewGuideMode,
                let legacyShowsGuide = defaults.object(forKey: SettingsKeys.showsFlickGuideCharacters) as? Bool else {
            return
        }

        let migratedMode = legacyShowsGuide
            ? FlickGuideDisplayOption.fourDirections.rawValue
            : FlickGuideDisplayOption.off.rawValue

        guideModeKeys.forEach { key in
            defaults.set(migratedMode, forKey: key)
        }
    }

    private var keyRepeatInitialDelayBinding: Binding<Double> {
        Binding(
            get: { keyRepeatInitialDelay },
            set: { keyRepeatInitialDelay = snappedRepeatValue($0, to: RepeatSettings.initialDelayDefault) }
        )
    }

    private var keyRepeatIntervalBinding: Binding<Double> {
        Binding(
            get: { keyRepeatInterval },
            set: { keyRepeatInterval = snappedRepeatValue($0, to: RepeatSettings.intervalDefault) }
        )
    }

    private var kanaModeSwitcherTapActionSelection: Binding<KanaModeSwitcherActionOption> {
        rawValueSelection(from: kanaModeSwitcherTapActionRawValue, default: .emoji) {
            kanaModeSwitcherTapActionRawValue = $0
        }
    }

    private var kanaModeSwitcherRightFlickActionSelection: Binding<KanaModeSwitcherActionOption> {
        rawValueSelection(from: kanaModeSwitcherRightFlickActionRawValue, default: .kaomoji) {
            kanaModeSwitcherRightFlickActionRawValue = $0
        }
    }

    private var kanaModeSwitcherUpFlickActionSelection: Binding<KanaModeSwitcherActionOption> {
        rawValueSelection(from: kanaModeSwitcherUpFlickActionRawValue, default: .symbols) {
            kanaModeSwitcherUpFlickActionRawValue = $0
        }
    }

    private var canAddUserDictionaryEntry: Bool {
        !normalizedKanaReading(from: userDictionaryReadingInput).isEmpty
            && !userDictionaryCandidateInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canAddSuppressionDictionaryEntry: Bool {
        !normalizedKanaReading(from: suppressionDictionaryReadingInput).isEmpty
            && !suppressionDictionaryCandidateInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canAddShortcutDictionaryEntry: Bool {
        !shortcutDictionaryCandidateInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var userVocabularyListMaxHeight: CGFloat {
        // Give section-index titles more vertical breathing room.
        336
    }

    private var userVocabularyListMinHeight: CGFloat {
        // Keep this above the custom-index top/bottom insets to avoid layout conflicts.
        40
    }

    private var userVocabularyListRowHeight: CGFloat {
        30
    }

    private func userVocabularyListHeight(for entryCount: Int) -> CGFloat {
        let contentHeight = CGFloat(max(entryCount, 1)) * userVocabularyListRowHeight
        return min(userVocabularyListMaxHeight, max(userVocabularyListMinHeight, contentHeight))
    }

    private func normalizedKanaReading(from text: String) -> String {
        var result = ""

        for character in text {
            let source = String(character)
            let normalized = source.applyingTransform(.hiraganaToKatakana, reverse: true) ?? source

            guard normalized.count == 1,
                    let first = normalized.first,
                    let scalar = String(first).unicodeScalars.first else {
                continue
            }

            if (0x3040...0x309F).contains(scalar.value) || scalar.value == 0x30FC {
                result.append(first)
            }
        }

        return result
    }

    private func loadDictionaryEntries(forKey key: String) -> [String: [String]] {
        guard let defaults = Self.sharedDefaults else {
            return [:]
        }

        if let dictionaryData = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode([String: [String]].self, from: dictionaryData) {
            return decoded
        }

        guard let rawDictionary = defaults.dictionary(forKey: key) else {
            return [:]
        }

        var decoded: [String: [String]] = [:]

        for (reading, rawCandidates) in rawDictionary {
            if let candidates = rawCandidates as? [String] {
                decoded[reading] = candidates
            } else if let candidates = rawCandidates as? [Any] {
                decoded[reading] = candidates.compactMap { $0 as? String }
            }
        }

        return decoded
    }

    private func uniqueCandidatesPreservingOrder(_ candidates: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmed.isEmpty,
                    seen.insert(trimmed).inserted else {
                continue
            }

            result.append(trimmed)
        }

        return result
    }

    private func uniqueShortcutCandidatesPreservingOrder(_ candidates: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for candidate in candidates {
            guard !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                seen.insert(candidate).inserted else {
                continue
            }

            result.append(candidate)
        }

        return result
    }

    private func normalizedDictionaryEntries(_ dictionary: [String: [String]]) -> [String: [String]] {
        var normalized: [String: [String]] = [:]

        for (reading, candidates) in dictionary {
            let normalizedReading = normalizedKanaReading(from: reading)

            guard !normalizedReading.isEmpty else {
                continue
            }

            let mergedCandidates = uniqueCandidatesPreservingOrder(
                (normalized[normalizedReading] ?? []) + candidates
            )

            if !mergedCandidates.isEmpty {
                normalized[normalizedReading] = mergedCandidates
            }
        }

        return normalized
    }

    private func mergedDictionary(
        preferred: [String: [String]],
        fallback: [String: [String]]
    ) -> [String: [String]] {
        var merged = fallback

        for (reading, preferredCandidates) in preferred {
            let combined = uniqueCandidatesPreservingOrder(
                preferredCandidates + (fallback[reading] ?? [])
            )

            if combined.isEmpty {
                merged.removeValue(forKey: reading)
            } else {
                merged[reading] = combined
            }
        }

        return merged
    }

    private func loadBundledInitialDictionaryEntries(filename: String) -> [String: [String]] {
        let fileExtension = "json"

        if let resourceURL = Bundle.main.url(forResource: filename, withExtension: fileExtension),
            let data = try? Data(contentsOf: resourceURL),
            let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            return normalizedDictionaryEntries(decoded)
        }

        if let pluginsURL = Bundle.main.builtInPlugInsURL,
            let pluginURLs = try? FileManager.default.contentsOfDirectory(
                at: pluginsURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
            for pluginURL in pluginURLs where pluginURL.pathExtension == "appex" {
                let resourceURL = pluginURL.appendingPathComponent("\(filename).\(fileExtension)")

                guard FileManager.default.fileExists(atPath: resourceURL.path),
                        let data = try? Data(contentsOf: resourceURL),
                        let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
                    continue
                }

                return normalizedDictionaryEntries(decoded)
            }
        }

        return [:]
    }

    private func loadBundledInitialUserDictionaryEntries() -> [String: [String]] {
        loadBundledInitialDictionaryEntries(filename: "InitialAjoutVocabMigration")
    }

    private func loadBundledInitialSuppressionDictionaryEntries() -> [String: [String]] {
        loadBundledInitialDictionaryEntries(filename: "InitialSupprVocabMigration")
    }

    private func loadBundledInitialShortcutVocabularyEntries() -> [String] {
        let fileExtension = "json"
        let filename = "InitialShortcutVocabMigration"

        if let resourceURL = Bundle.main.url(forResource: filename, withExtension: fileExtension),
            let data = try? Data(contentsOf: resourceURL),
            let decoded = try? JSONDecoder().decode([String].self, from: data) {
            return uniqueShortcutCandidatesPreservingOrder(decoded)
        }

        if let pluginsURL = Bundle.main.builtInPlugInsURL,
            let pluginURLs = try? FileManager.default.contentsOfDirectory(
                at: pluginsURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
            for pluginURL in pluginURLs where pluginURL.pathExtension == "appex" {
                let resourceURL = pluginURL.appendingPathComponent("\(filename).\(fileExtension)")

                guard FileManager.default.fileExists(atPath: resourceURL.path),
                    let data = try? Data(contentsOf: resourceURL),
                    let decoded = try? JSONDecoder().decode([String].self, from: data) else {
                    continue
                }

                return uniqueShortcutCandidatesPreservingOrder(decoded)
            }
        }

        return []
    }

    private func loadShortcutVocabularyCandidates() -> [String] {
        guard let defaults = Self.sharedDefaults else {
            return []
        }

        if let shortcutData = defaults.data(forKey: SettingsKeys.kanaKanjiShortcutVocabulary),
            let decoded = try? JSONDecoder().decode([String].self, from: shortcutData) {
            return uniqueShortcutCandidatesPreservingOrder(decoded)
        }

        if let rawArray = defaults.array(forKey: SettingsKeys.kanaKanjiShortcutVocabulary) {
            return uniqueShortcutCandidatesPreservingOrder(rawArray.compactMap { $0 as? String })
        }

        let legacyDictionary = loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiShortcutVocabulary)

        if !legacyDictionary.isEmpty {
            let candidates = legacyDictionary["☻"] ?? legacyDictionary
                .keys
                .sorted()
                .flatMap { legacyDictionary[$0] ?? [] }
            return uniqueShortcutCandidatesPreservingOrder(candidates)
        }

        return []
    }

    private func saveShortcutVocabularyCandidates(_ candidates: [String]) {
        guard let defaults = Self.sharedDefaults,
            let encoded = try? JSONEncoder().encode(candidates) else {
            return
        }

        defaults.set(encoded, forKey: SettingsKeys.kanaKanjiShortcutVocabulary)
    }

    private func loadAppGroupDictionaryEntries(filename: String) -> [String: [String]] {
        guard
            let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: SettingsKeys.appGroupID
            )
        else {
            return [:]
        }

        let fileURL = containerURL.appendingPathComponent(filename)

        guard
            let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode([String: [String]].self, from: data)
        else {
            return [:]
        }

        return normalizedDictionaryEntries(decoded)
    }

    private func sortedVocabularyEntries(from dictionary: [String: [String]]) -> [VocabularyEntry] {
        dictionary
            .keys
            .sorted()
            .flatMap { reading in
                (dictionary[reading] ?? []).map { candidate in
                    VocabularyEntry(reading: reading, candidate: candidate)
                }
            }
    }

    private func loadSystemVocabularyEntries() {
        let firstFromAppGroup = loadAppGroupDictionaryEntries(filename: "ÉcrituPremierVocab.json")
        let firstDictionary = firstFromAppGroup.isEmpty
            ? loadBundledInitialDictionaryEntries(filename: "ÉcrituPremierVocab")
            : firstFromAppGroup

        let secondFromAppGroup = loadAppGroupDictionaryEntries(filename: "ÉcrituSecondVocab.json")
        let secondDictionary = secondFromAppGroup.isEmpty
            ? loadBundledInitialDictionaryEntries(filename: "ÉcrituSecondVocab")
            : secondFromAppGroup

        firstVocabularyEntries = sortedVocabularyEntries(from: firstDictionary)
        secondVocabularyEntries = sortedVocabularyEntries(from: secondDictionary)
    }

    private func migrateInitialDictionaryIfNeeded(
        migrationFlagKey: String,
        dictionaryKey: String,
        initialDictionaryLoader: () -> [String: [String]]
    ) {
        guard let defaults = Self.sharedDefaults,
                !defaults.bool(forKey: migrationFlagKey) else {
            return
        }

        let initialDictionary = initialDictionaryLoader()

        guard !initialDictionary.isEmpty else {
            return
        }

        let currentDictionary = normalizedDictionaryEntries(
            loadDictionaryEntries(forKey: dictionaryKey)
        )
        let merged = mergedDictionary(preferred: currentDictionary, fallback: initialDictionary)
        saveDictionaryEntries(merged, forKey: dictionaryKey)
        defaults.set(true, forKey: migrationFlagKey)
    }

    private func migrateInitialUserDictionaryIfNeeded() {
        migrateInitialDictionaryIfNeeded(
            migrationFlagKey: SettingsKeys.kanaKanjiInitialUserDictionaryMigrated,
            dictionaryKey: SettingsKeys.kanaKanjiAjoutVocabulary,
            initialDictionaryLoader: loadBundledInitialUserDictionaryEntries
        )
    }

    private func migrateInitialSuppressionDictionaryIfNeeded() {
        migrateInitialDictionaryIfNeeded(
            migrationFlagKey: SettingsKeys.kanaKanjiInitialSuppressionDictionaryMigrated,
            dictionaryKey: SettingsKeys.kanaKanjiSuppressionVocabulary,
            initialDictionaryLoader: loadBundledInitialSuppressionDictionaryEntries
        )
    }

    private func migrateInitialShortcutVocabularyIfNeeded() {
        guard let defaults = Self.sharedDefaults else {
            return
        }

        let initialCandidates = loadBundledInitialShortcutVocabularyEntries()

        guard !initialCandidates.isEmpty else {
            return
        }

        let currentCandidates = loadShortcutVocabularyCandidates()
        // Keep initial shortcut order authoritative while preserving existing entries.
        let mergedCandidates = uniqueShortcutCandidatesPreservingOrder(initialCandidates + currentCandidates)

        if mergedCandidates != currentCandidates {
            saveShortcutVocabularyCandidates(mergedCandidates)
        }

        defaults.set(true, forKey: SettingsKeys.kanaKanjiInitialShortcutVocabularyMigrated)
    }

    private func saveDictionaryEntries(_ entriesByReading: [String: [String]], forKey key: String) {
        guard let defaults = Self.sharedDefaults,
                let encoded = try? JSONEncoder().encode(entriesByReading) else {
            return
        }

        defaults.set(encoded, forKey: key)
    }

    private func loadUserDictionaryEntries() {
        let dictionary = normalizedDictionaryEntries(
            loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiAjoutVocabulary)
        )

        userDictionaryEntries = dictionary
            .keys
            .sorted()
            .flatMap { reading in
                (dictionary[reading] ?? []).map { candidate in
                    VocabularyEntry(reading: reading, candidate: candidate)
                }
            }
    }

    private func saveUserDictionary(_ entriesByReading: [String: [String]]) {
        saveDictionaryEntries(entriesByReading, forKey: SettingsKeys.kanaKanjiAjoutVocabulary)
    }

    private func addUserDictionaryEntry() {
        let reading = normalizedKanaReading(from: userDictionaryReadingInput)
        let candidate = userDictionaryCandidateInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !reading.isEmpty,
                !candidate.isEmpty else {
            return
        }

        var dictionary = loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiAjoutVocabulary)

        var candidates = dictionary[reading] ?? []

        if let existingIndex = candidates.firstIndex(of: candidate) {
            candidates.remove(at: existingIndex)
        }

        candidates.insert(candidate, at: 0)
        dictionary[reading] = Array(candidates.prefix(32))
        saveUserDictionary(dictionary)

        userDictionaryReadingInput = ""
        userDictionaryCandidateInput = ""
        loadUserDictionaryEntries()
    }

    private func updateUserDictionaryEntry(_ originalEntry: VocabularyEntry) {
        let reading = normalizedKanaReading(from: userDictionaryReadingInput)
        let candidate = userDictionaryCandidateInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !reading.isEmpty,
            !candidate.isEmpty else {
            return
        }

        var dictionary = loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiAjoutVocabulary)

        var originalCandidates = dictionary[originalEntry.reading] ?? []
        originalCandidates.removeAll { $0 == originalEntry.candidate }

        if originalCandidates.isEmpty {
            dictionary.removeValue(forKey: originalEntry.reading)
        } else {
            dictionary[originalEntry.reading] = originalCandidates
        }

        var targetCandidates = dictionary[reading] ?? []

        if let existingIndex = targetCandidates.firstIndex(of: candidate) {
            targetCandidates.remove(at: existingIndex)
        }

        targetCandidates.insert(candidate, at: 0)
        dictionary[reading] = Array(targetCandidates.prefix(32))

        saveUserDictionary(dictionary)
        userDictionaryReadingInput = ""
        userDictionaryCandidateInput = ""
        loadUserDictionaryEntries()
    }

    private func removeUserDictionaryEntry(_ entry: VocabularyEntry) {
        var dictionary = loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiAjoutVocabulary)

        var candidates = dictionary[entry.reading] ?? []
        candidates.removeAll { $0 == entry.candidate }

        if candidates.isEmpty {
            dictionary.removeValue(forKey: entry.reading)
        } else {
            dictionary[entry.reading] = candidates
        }

        saveUserDictionary(dictionary)
        loadUserDictionaryEntries()
    }

    private func removeAllUserDictionaryEntries() {
        saveUserDictionary([:])
        loadUserDictionaryEntries()
    }

    private func reimportInitialUserDictionaryEntries() {
        guard let defaults = Self.sharedDefaults else {
            return
        }

        defaults.removeObject(forKey: SettingsKeys.kanaKanjiInitialUserDictionaryMigrated)
        migrateInitialUserDictionaryIfNeeded()
        loadUserDictionaryEntries()
    }

    private func resetKanaKanjiLearning() {
        Self.sharedDefaults?.removeObject(forKey: SettingsKeys.kanaKanjiLearningScores)
    }

    private func loadSuppressionDictionaryEntries() {
        let dictionary = loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiSuppressionVocabulary)

        suppressionDictionaryEntries = dictionary
            .keys
            .sorted()
            .flatMap { reading in
                (dictionary[reading] ?? []).map { candidate in
                    VocabularyEntry(reading: reading, candidate: candidate)
                }
            }
    }

    private func saveSuppressionDictionary(_ entriesByReading: [String: [String]]) {
        saveDictionaryEntries(entriesByReading, forKey: SettingsKeys.kanaKanjiSuppressionVocabulary)
    }

    private func addSuppressionDictionaryEntry() {
        let reading = normalizedKanaReading(from: suppressionDictionaryReadingInput)
        let candidate = suppressionDictionaryCandidateInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !reading.isEmpty,
                !candidate.isEmpty else {
            return
        }

        var dictionary = loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiSuppressionVocabulary)
        var candidates = dictionary[reading] ?? []

        if let existingIndex = candidates.firstIndex(of: candidate) {
            candidates.remove(at: existingIndex)
        }

        candidates.insert(candidate, at: 0)
        dictionary[reading] = Array(candidates.prefix(128))
        saveSuppressionDictionary(dictionary)

        suppressionDictionaryReadingInput = ""
        suppressionDictionaryCandidateInput = ""
        loadSuppressionDictionaryEntries()
    }

    private func updateSuppressionDictionaryEntry(_ originalEntry: VocabularyEntry) {
        let reading = normalizedKanaReading(from: suppressionDictionaryReadingInput)
        let candidate = suppressionDictionaryCandidateInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !reading.isEmpty,
            !candidate.isEmpty else {
            return
        }

        var dictionary = loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiSuppressionVocabulary)

        var originalCandidates = dictionary[originalEntry.reading] ?? []
        originalCandidates.removeAll { $0 == originalEntry.candidate }

        if originalCandidates.isEmpty {
            dictionary.removeValue(forKey: originalEntry.reading)
        } else {
            dictionary[originalEntry.reading] = originalCandidates
        }

        var targetCandidates = dictionary[reading] ?? []

        if let existingIndex = targetCandidates.firstIndex(of: candidate) {
            targetCandidates.remove(at: existingIndex)
        }

        targetCandidates.insert(candidate, at: 0)
        dictionary[reading] = Array(targetCandidates.prefix(128))

        saveSuppressionDictionary(dictionary)
        suppressionDictionaryReadingInput = ""
        suppressionDictionaryCandidateInput = ""
        loadSuppressionDictionaryEntries()
    }

    private func removeSuppressionDictionaryEntry(_ entry: VocabularyEntry) {
        var dictionary = loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiSuppressionVocabulary)
        var candidates = dictionary[entry.reading] ?? []
        candidates.removeAll { $0 == entry.candidate }

        if candidates.isEmpty {
            dictionary.removeValue(forKey: entry.reading)
        } else {
            dictionary[entry.reading] = candidates
        }

        saveSuppressionDictionary(dictionary)
        loadSuppressionDictionaryEntries()
    }

    private func loadShortcutDictionaryEntries() {
        shortcutDictionaryEntries = loadShortcutVocabularyCandidates().map { candidate in
            VocabularyEntry(reading: "☻", candidate: candidate)
        }
    }

    private func addShortcutDictionaryEntry() {
        let candidate = shortcutDictionaryCandidateInput

        guard !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        var candidates = loadShortcutVocabularyCandidates()

        if let existingIndex = candidates.firstIndex(of: candidate) {
            candidates.remove(at: existingIndex)
        }

        candidates.insert(candidate, at: 0)
        saveShortcutVocabularyCandidates(Array(candidates.prefix(128)))

        shortcutDictionaryCandidateInput = ""
        loadShortcutDictionaryEntries()
    }

    private func updateShortcutDictionaryEntry(_ originalEntry: VocabularyEntry) {
        let candidate = shortcutDictionaryCandidateInput

        guard !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        var candidates = loadShortcutVocabularyCandidates()
        candidates.removeAll { $0 == originalEntry.candidate }

        if let existingIndex = candidates.firstIndex(of: candidate) {
            candidates.remove(at: existingIndex)
        }

        candidates.insert(candidate, at: 0)
        saveShortcutVocabularyCandidates(Array(candidates.prefix(128)))

        shortcutDictionaryCandidateInput = ""
        loadShortcutDictionaryEntries()
    }

    private func removeShortcutDictionaryEntry(_ entry: VocabularyEntry) {
        var candidates = loadShortcutVocabularyCandidates()
        candidates.removeAll { $0 == entry.candidate }
        saveShortcutVocabularyCandidates(candidates)
        loadShortcutDictionaryEntries()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.screenBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Spacer(minLength: 0)

                            VStack(spacing: 4) {
                                Image("AppLogoDisplay")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 92, height: 92)
                                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                    .shadow(color: Color.black.opacity(0.12), radius: 5, y: 2)

                                Text(Self.editionNumberText)
                                    .font(.system(size: 4, weight: .regular, design: .monospaced))
                                    .foregroundStyle(.secondary.opacity(0.9))
                                    .lineLimit(1)
                                    .scaleEffect(isEditionNumberPressed ? 6.0 : 1.0, anchor: .top)
                                    .animation(.easeOut(duration: 0.08), value: isEditionNumberPressed)
                                    .contentShape(Rectangle())
                                    .simultaneousGesture(
                                        DragGesture(minimumDistance: 0)
                                            .updating($isEditionNumberPressed) { _, state, _ in
                                                state = true
                                            }
                                    )
                                    .zIndex(1)
                                    .accessibilityHidden(true)
                            }

                            Spacer(minLength: 0)
                        }

                        Text("このアプリはカスタムキーボード拡張の設定・管理を行うコンテナー・アプリ (Containing App) です。キーボード本体は拡張ターゲット側で実装されています。")
                            .font(.body)
                            .foregroundStyle(.secondary)

                        DirectionSettingsSection(selection: directionSelection)

                        KanaModifierSettingsSection(selection: kanaModifierPlacementSelection)

                        KanaLayoutSettingsSection(selection: kanaLayoutSelection)

                        LatinLayoutSettingsSection(selection: latinLayoutSelection)

                        NumberLayoutSettingsSection(selection: numberLayoutSelection)

                        BasicSymbolOrderSettingsSection(selection: basicSymbolOrderSelection)

                        AccentColorSettingsSection(selection: accentPaletteSelection)

                        ThemeColorSettingsSection(selection: keyboardBackgroundThemeSelection)

                        FlickGuideDisplaySettingsSection(
                            kanaSelection: kanaFlickGuideDisplayModeSelection,
                            latinSelection: latinFlickGuideDisplayModeSelection,
                            numberSelection: numberFlickGuideDisplayModeSelection,
                            isLatinGuideAvailable: isLatinFlickLayoutSelected
                        )

                        KeyRepeatSettingsSection(
                            keyRepeatInitialDelay: keyRepeatInitialDelayBinding,
                            keyRepeatInterval: keyRepeatIntervalBinding
                        )

                        KanaModeSwitcherAssignmentSection(
                            tapSelection: kanaModeSwitcherTapActionSelection,
                            rightFlickSelection: kanaModeSwitcherRightFlickActionSelection,
                            upFlickSelection: kanaModeSwitcherUpFlickActionSelection
                        )

                        VStack(alignment: .leading, spacing: 10) {
                            Text("かな漢字候補モード")
                                .font(.headline)

                            Picker("かな漢字候補モード", selection: kanaKanjiCandidateSourceModeSelection) {
                                ForEach(KanaKanjiCandidateSourceModeOption.allCases) { option in
                                    Text(option.title).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)

                            Text("システム辞書候補の採用基準を切り替えます。surface(既定) / normalisé / les deux を選べます。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .settingsCardStyle()

                        UserDictionarySettingsSection(
                            entries: $userDictionaryEntries,
                            readingInput: $userDictionaryReadingInput,
                            candidateInput: $userDictionaryCandidateInput,
                            isRegistrationVisible: $isUserDictionaryRegistrationVisible,
                            scrollIndexTitle: $userDictionaryScrollIndexTitle,
                            isScrollIndexVisible: $isUserDictionaryScrollIndexVisible,
                            canAddEntry: canAddUserDictionaryEntry,
                            listHeight: userVocabularyListHeight(for: userDictionaryEntries.count),
                            onAddEntry: addUserDictionaryEntry,
                            onUpdateEntry: updateUserDictionaryEntry,
                            onDeleteEntry: removeUserDictionaryEntry,
                            onDeleteAll: removeAllUserDictionaryEntries,
                            onResetLearning: resetKanaKanjiLearning,
                            onReimportInitialEntries: reimportInitialUserDictionaryEntries
                        )

                        SuppressionDictionarySettingsSection(
                            entries: $suppressionDictionaryEntries,
                            readingInput: $suppressionDictionaryReadingInput,
                            candidateInput: $suppressionDictionaryCandidateInput,
                            isRegistrationVisible: $isSuppressionDictionaryRegistrationVisible,
                            scrollIndexTitle: $suppressionDictionaryScrollIndexTitle,
                            isScrollIndexVisible: $isSuppressionDictionaryScrollIndexVisible,
                            canAddEntry: canAddSuppressionDictionaryEntry,
                            listHeight: userVocabularyListHeight(for: suppressionDictionaryEntries.count),
                            onAddEntry: addSuppressionDictionaryEntry,
                            onUpdateEntry: updateSuppressionDictionaryEntry,
                            onDeleteEntry: removeSuppressionDictionaryEntry
                        )

                        ShortcutDictionarySettingsSection(
                            entries: $shortcutDictionaryEntries,
                            candidateInput: $shortcutDictionaryCandidateInput,
                            isRegistrationVisible: $isShortcutDictionaryRegistrationVisible,
                            canAddEntry: canAddShortcutDictionaryEntry,
                            listHeight: userVocabularyListHeight(for: shortcutDictionaryEntries.count),
                            onAddEntry: addShortcutDictionaryEntry,
                            onUpdateEntry: updateShortcutDictionaryEntry,
                            onDeleteEntry: removeShortcutDictionaryEntry
                        )

                        ReadOnlyDictionarySettingsSection(
                            title: "第1語彙",
                            entries: firstVocabularyEntries,
                            scrollIndexTitle: $firstVocabularyScrollIndexTitle,
                            isScrollIndexVisible: $isFirstVocabularyScrollIndexVisible,
                            listHeight: userVocabularyListHeight(for: firstVocabularyEntries.count),
                            emptyMessage: "第1語彙は読み込まれていません。",
                            description: "Dictionnaire système premier (読み取り専用) 追加や削除はできません。"
                        )

                        ReadOnlyDictionarySettingsSection(
                            title: "第2語彙",
                            entries: secondVocabularyEntries,
                            scrollIndexTitle: $secondVocabularyScrollIndexTitle,
                            isScrollIndexVisible: $isSecondVocabularyScrollIndexVisible,
                            listHeight: userVocabularyListHeight(for: secondVocabularyEntries.count),
                            emptyMessage: "第2語彙は読み込まれていません。",
                            description: "Dictionnaire système secondaire (読み取り専用) 追加や削除はできません。"
                        )

                        SetupStepsSection(steps: setupSteps)

                        ThirdPartyLicensesSection()

                        Text("フリック入力に加えて、かな漢字変換・追加単語・抑制単語に対応しています。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(20)
                }
            }
            .onAppear {
                migrateLegacyFlickGuideSettingIfNeeded()
                migrateInitialUserDictionaryIfNeeded()
                migrateInitialShortcutVocabularyIfNeeded()
                migrateInitialSuppressionDictionaryIfNeeded()
                loadUserDictionaryEntries()
                loadSuppressionDictionaryEntries()
                loadShortcutDictionaryEntries()
                loadSystemVocabularyEntries()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UserDefaults.didChangeNotification,
                    object: Self.sharedDefaults
                )
            ) { _ in
                SettingsSyncNotification.postSettingsDidChange()
            }
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("écritu")
                        .font(.custom("SnellRoundhand-Bold", size: 34))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
            }
#endif
        }
    }
}

#Preview {
    ContentView()
}
