import SwiftUI

struct ContentView: View {
    private static let sharedDefaults = UserDefaults(suiteName: SettingsKeys.appGroupID)

    private static let buildNumberText: String = {
        let buildNumber = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "?"
        return "build \(buildNumber)"
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
    @GestureState private var isBuildNumberPressed = false

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

    private var canAddUserDictionaryEntry: Bool {
        !normalizedKanaReading(from: userDictionaryReadingInput).isEmpty
            && !userDictionaryCandidateInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canAddSuppressionDictionaryEntry: Bool {
        !normalizedKanaReading(from: suppressionDictionaryReadingInput).isEmpty
            && !suppressionDictionaryCandidateInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    var body: some View {
        NavigationStack {
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

                            Text(Self.buildNumberText)
                                .font(.system(size: 4, weight: .regular, design: .monospaced))
                                .foregroundStyle(.secondary.opacity(0.9))
                                .lineLimit(1)
                                .scaleEffect(isBuildNumberPressed ? 6.0 : 1.0, anchor: .top)
                                .animation(.easeOut(duration: 0.08), value: isBuildNumberPressed)
                                .contentShape(Rectangle())
                                .simultaneousGesture(
                                    DragGesture(minimumDistance: 0)
                                        .updating($isBuildNumberPressed) { _, state, _ in
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

                    AccentColorSettingsSection(selection: accentPaletteSelection)

                    ThemeColorSettingsSection(selection: keyboardBackgroundThemeSelection)

                    FlickGuideDisplaySettingsSection(
                        kanaSelection: kanaFlickGuideDisplayModeSelection,
                        latinSelection: latinFlickGuideDisplayModeSelection,
                        numberSelection: numberFlickGuideDisplayModeSelection
                    )

                    KeyRepeatSettingsSection(
                        keyRepeatInitialDelay: keyRepeatInitialDelayBinding,
                        keyRepeatInterval: keyRepeatIntervalBinding
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
                        onDeleteEntry: removeUserDictionaryEntry,
                        onResetLearning: resetKanaKanjiLearning
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
                        onDeleteEntry: removeSuppressionDictionaryEntry
                    )

                    SetupStepsSection(steps: setupSteps)

                    Text("フリック入力に加えて、かな漢字変換・追加単語・抑制単語に対応しています。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .onAppear {
                migrateLegacyFlickGuideSettingIfNeeded()
                migrateInitialUserDictionaryIfNeeded()
                migrateInitialSuppressionDictionaryIfNeeded()
                loadUserDictionaryEntries()
                loadSuppressionDictionaryEntries()
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

private extension View {
    func settingsCardStyle() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(white: 0.94))
            )
    }
}
