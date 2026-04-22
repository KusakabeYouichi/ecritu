import SwiftUI
import UIKit

struct ContentView: View {
    private enum SettingsKeys {
        static let appGroupID = "group.com.kusakabe.ecritu"
        static let directionProfile = "flickDirectionProfile"
        static let kanaLayoutMode = "kanaLayoutMode"
        static let kanaModifierPlacement = "kanaModifierPlacement"
        static let latinLayoutMode = "latinLayoutMode"
        static let numberLayoutMode = "numberLayoutMode"
        static let accentPalette = "accentPalette"
        static let keyboardBackgroundTheme = "keyboardBackgroundTheme"
        static let showsFlickGuideCharacters = "showsFlickGuideCharacters"
        static let keyRepeatInitialDelay = "keyRepeatInitialDelay"
        static let keyRepeatInterval = "keyRepeatInterval"
        static let kanaKanjiAjoutVocabulary = "ÉcrituAjoutVocab"
        static let kanaKanjiInitialUserDictionaryMigrated = "kanaKanjiInitialUserDictionaryMigrated"
        static let kanaKanjiInitialSuppressionDictionaryMigrated = "kanaKanjiInitialSuppressionDictionaryMigrated"
        static let kanaKanjiSuppressionVocabulary = "ÉcrituSuppr_Vocab"
        static let kanaKanjiCandidateSourceMode = "kanaKanjiCandidateSourceMode"
        static let kanaKanjiLearningScores = "kanaKanjiLearningScores"
    }

    private enum RepeatSettings {
        static let initialDelayDefault = 0.5
        static let initialDelayRange: ClosedRange<Double> = 0.1...0.8
        static let intervalDefault = 0.1
        static let intervalRange: ClosedRange<Double> = 0.05...0.2
        static let snapThreshold = 0.01
    }

    private enum KanaLayoutOption: String, CaseIterable, Identifiable {
        case fiveByTwo
        case threeByThreePlusWa

        var id: String { rawValue }

        var title: String {
            switch self {
            case .fiveByTwo: return "5x2"
            case .threeByThreePlusWa: return "3x3+わ"
            }
        }
    }

    private enum KanaModifierPlacementOption: String, CaseIterable, Identifiable {
        case prefix
        case postfix

        var id: String { rawValue }

        var title: String {
            switch self {
            case .prefix: return "前置修飾"
            case .postfix: return "後置修飾"
            }
        }
    }

    private enum DirectionOption: String, CaseIterable, Identifiable {
        case apple
        case ecritu

        var id: String { rawValue }

        var title: String {
            switch self {
            case .apple: return "Apple"
            case .ecritu: return "écritu"
            }
        }
    }

    private enum LatinLayoutOption: String, CaseIterable, Identifiable {
        case azerty
        case qwerty
        case flick

        var id: String { rawValue }

        var title: String {
            switch self {
            case .flick: return "3x3"
            case .qwerty: return "qwerty"
            case .azerty: return "azerty"
            }
        }
    }

    private enum NumberLayoutOption: String, CaseIterable, Identifiable {
        case calculette
        case telephone

        var id: String { rawValue }

        var title: String {
            switch self {
            case .calculette: return "calculette"
            case .telephone: return "téléphone"
            }
        }
    }

    private enum KanaKanjiCandidateSourceModeOption: String, CaseIterable, Identifiable {
        case normalise
        case surface
        case lesDeux

        var id: String { rawValue }

        var title: String {
            switch self {
            case .normalise: return "normalisé"
            case .surface: return "surface"
            case .lesDeux: return "les deux"
            }
        }
    }

    private enum AccentColorOption: String, CaseIterable, Identifiable {
        case tuile
        case emeraude

        var id: String { rawValue }

        var title: String {
            switch self {
            case .tuile: return "tuilé"
            case .emeraude: return "émeraude"
            }
        }

        var color: Color {
            switch self {
            case .tuile:
                return Color(red: 136.0 / 255.0, green: 63.0 / 255.0, blue: 53.0 / 255.0)
            case .emeraude:
                return Color(red: 0.06, green: 0.73, blue: 0.56)
            }
        }
    }

    private enum KeyboardBackgroundThemeOption: String, CaseIterable, Identifiable {
        case bleu
        case sakura

        var id: String { rawValue }

        var title: String {
            switch self {
            case .bleu: return "bleu ciel brumeux"
            case .sakura: return "rose sakura poudré"
            }
        }

        var subtitle: String {
            switch self {
            case .bleu: return "brume douce et lumière du ciel"
            case .sakura: return "rose poudré inspiré des fleurs"
            }
        }

        var gradientColors: [Color] {
            switch self {
            case .bleu:
                return [
                    Color(red: 0.86, green: 0.91, blue: 1.0),
                    Color(red: 0.95, green: 0.97, blue: 1.0)
                ]
            case .sakura:
                return [
                    Color(red: 1.0, green: 0.88, blue: 0.93),
                    Color(red: 1.0, green: 0.95, blue: 0.97)
                ]
            }
        }
    }

    private static let sharedDefaults = UserDefaults(suiteName: SettingsKeys.appGroupID)

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
        SettingsKeys.showsFlickGuideCharacters,
        store: Self.sharedDefaults
    )
    private var showsFlickGuideCharacters: Bool = true

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

    private let setupSteps: [String] = [
        "設定 > 一般 > キーボード > キーボード > 新しいキーボードを追加",
        "作成したキーボードを有効化",
        "入力画面で地球儀キーから切り替え"
    ]

    private struct VocabularyEntry: Identifiable {
        let reading: String
        let candidate: String

        var id: String { reading + "\t" + candidate }
    }

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

    private func isAtRepeatDefault(_ value: Double, default defaultValue: Double) -> Bool {
        abs(value - defaultValue) <= RepeatSettings.snapThreshold
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

    private func migrateInitialUserDictionaryIfNeeded() {
        guard let defaults = Self.sharedDefaults,
              !defaults.bool(forKey: SettingsKeys.kanaKanjiInitialUserDictionaryMigrated) else {
            return
        }

        let initialDictionary = loadBundledInitialUserDictionaryEntries()

        guard !initialDictionary.isEmpty else {
            return
        }

        let currentDictionary = normalizedDictionaryEntries(
            loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiAjoutVocabulary)
        )
        let merged = mergedDictionary(preferred: currentDictionary, fallback: initialDictionary)
        saveDictionaryEntries(merged, forKey: SettingsKeys.kanaKanjiAjoutVocabulary)
        defaults.set(true, forKey: SettingsKeys.kanaKanjiInitialUserDictionaryMigrated)
    }

    private func migrateInitialSuppressionDictionaryIfNeeded() {
        guard let defaults = Self.sharedDefaults,
              !defaults.bool(forKey: SettingsKeys.kanaKanjiInitialSuppressionDictionaryMigrated) else {
            return
        }

        let initialDictionary = loadBundledInitialSuppressionDictionaryEntries()

        guard !initialDictionary.isEmpty else {
            return
        }

        let currentDictionary = normalizedDictionaryEntries(
            loadDictionaryEntries(forKey: SettingsKeys.kanaKanjiSuppressionVocabulary)
        )
        let merged = mergedDictionary(preferred: currentDictionary, fallback: initialDictionary)
        saveDictionaryEntries(merged, forKey: SettingsKeys.kanaKanjiSuppressionVocabulary)
        defaults.set(true, forKey: SettingsKeys.kanaKanjiInitialSuppressionDictionaryMigrated)
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

    private struct IndexedVocabularyList: UIViewRepresentable {
        let entries: [VocabularyEntry]
        let onDelete: (VocabularyEntry) -> Void
        let onIndexIndicatorStateChange: (String, Bool) -> Void

        private static let kanaIndexTitles: [String] = ["あ", "か", "さ", "た", "な", "は", "ま", "や", "ら", "わ"]
        private static let allIndexTitles: [String] = kanaIndexTitles

        func makeCoordinator() -> Coordinator {
            Coordinator(
                entries: entries,
                onDelete: onDelete,
                onIndexIndicatorStateChange: onIndexIndicatorStateChange
            )
        }

        func makeUIView(context: Context) -> UITableView {
            let tableView = UITableView(frame: .zero, style: .plain)
            tableView.dataSource = context.coordinator
            tableView.delegate = context.coordinator
            tableView.register(UITableViewCell.self, forCellReuseIdentifier: Coordinator.cellReuseIdentifier)
            tableView.backgroundColor = .clear
            tableView.showsVerticalScrollIndicator = false
            tableView.sectionHeaderTopPadding = 0
            tableView.rowHeight = 30
            tableView.separatorStyle = .none
            context.coordinator.attachCustomIndex(to: tableView)
            return tableView
        }

        func updateUIView(_ uiView: UITableView, context: Context) {
            context.coordinator.update(
                entries: entries,
                onDelete: onDelete,
                onIndexIndicatorStateChange: onIndexIndicatorStateChange
            )
            context.coordinator.attachCustomIndex(to: uiView)
            uiView.reloadData()
            uiView.layoutIfNeeded()
            context.coordinator.refreshCustomIndexVisibility()
        }

        private static func indexTitle(for reading: String) -> String {
            let trimmed = reading.trimmingCharacters(in: .whitespacesAndNewlines)

            guard let first = trimmed.first else {
                return "あ"
            }

            let firstString = String(first)

            let hiragana = firstString.applyingTransform(.hiraganaToKatakana, reverse: true) ?? firstString

            guard let kana = hiragana.first else {
                return "あ"
            }

            switch kana {
            case "ぁ", "あ", "ぃ", "い", "ぅ", "う", "ぇ", "え", "ぉ", "お", "ゔ":
                return "あ"
            case "か", "が", "き", "ぎ", "く", "ぐ", "け", "げ", "こ", "ご":
                return "か"
            case "さ", "ざ", "し", "じ", "す", "ず", "せ", "ぜ", "そ", "ぞ":
                return "さ"
            case "た", "だ", "ち", "ぢ", "っ", "つ", "づ", "て", "で", "と", "ど":
                return "た"
            case "な", "に", "ぬ", "ね", "の":
                return "な"
            case "は", "ば", "ぱ", "ひ", "び", "ぴ", "ふ", "ぶ", "ぷ", "へ", "べ", "ぺ", "ほ", "ぼ", "ぽ":
                return "は"
            case "ま", "み", "む", "め", "も":
                return "ま"
            case "ゃ", "や", "ゅ", "ゆ", "ょ", "よ":
                return "や"
            case "ら", "り", "る", "れ", "ろ":
                return "ら"
            case "ゎ", "わ", "を", "ん":
                return "わ"
            default:
                return "あ"
            }
        }

        final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {
            static let cellReuseIdentifier = "IndexedVocabularyCell"
            static let candidateLabelTag = 1001
            static let readingLabelTag = 1002

            private var entries: [VocabularyEntry]
            private var onDelete: (VocabularyEntry) -> Void
            private var onIndexIndicatorStateChange: (String, Bool) -> Void
            private var groupedEntries: [String: [VocabularyEntry]] = [:]
            private var visibleSectionTitles: [String] = []
            private var overlayHideWorkItem: DispatchWorkItem?
            private var currentIndexIndicatorTitle = ""
            private weak var tableView: UITableView?
            private let customIndexContainerView = UIView()
            private let customIndexStackView = UIStackView()
            private var customIndexLabels: [UILabel] = []
            private lazy var customIndexTapGesture = UITapGestureRecognizer(
                target: self,
                action: #selector(handleCustomIndexTap(_:))
            )
            private lazy var customIndexPanGesture = UIPanGestureRecognizer(
                target: self,
                action: #selector(handleCustomIndexPan(_:))
            )

            init(
                entries: [VocabularyEntry],
                onDelete: @escaping (VocabularyEntry) -> Void,
                onIndexIndicatorStateChange: @escaping (String, Bool) -> Void
            ) {
                self.entries = entries
                self.onDelete = onDelete
                self.onIndexIndicatorStateChange = onIndexIndicatorStateChange
                super.init()
                rebuildSections()
            }

            func update(
                entries: [VocabularyEntry],
                onDelete: @escaping (VocabularyEntry) -> Void,
                onIndexIndicatorStateChange: @escaping (String, Bool) -> Void
            ) {
                self.entries = entries
                self.onDelete = onDelete
                self.onIndexIndicatorStateChange = onIndexIndicatorStateChange
                rebuildSections()
            }

            func attachCustomIndex(to tableView: UITableView) {
                self.tableView = tableView

                if customIndexContainerView.superview !== tableView {
                    customIndexContainerView.translatesAutoresizingMaskIntoConstraints = false
                    customIndexContainerView.backgroundColor = .clear
                    customIndexContainerView.isUserInteractionEnabled = true
                    customIndexContainerView.layer.zPosition = 10

                    customIndexStackView.translatesAutoresizingMaskIntoConstraints = false
                    customIndexStackView.axis = .vertical
                    customIndexStackView.alignment = .center
                    customIndexStackView.distribution = .fillEqually
                    customIndexStackView.spacing = 0

                    customIndexContainerView.addSubview(customIndexStackView)
                    customIndexContainerView.addGestureRecognizer(customIndexTapGesture)
                    customIndexContainerView.addGestureRecognizer(customIndexPanGesture)

                    tableView.addSubview(customIndexContainerView)

                    NSLayoutConstraint.activate([
                        customIndexContainerView.trailingAnchor.constraint(equalTo: tableView.frameLayoutGuide.trailingAnchor, constant: -4),
                        customIndexContainerView.topAnchor.constraint(equalTo: tableView.frameLayoutGuide.topAnchor, constant: 20),
                        customIndexContainerView.bottomAnchor.constraint(equalTo: tableView.frameLayoutGuide.bottomAnchor, constant: -20),
                        customIndexContainerView.widthAnchor.constraint(equalToConstant: 24),

                        customIndexStackView.leadingAnchor.constraint(equalTo: customIndexContainerView.leadingAnchor),
                        customIndexStackView.trailingAnchor.constraint(equalTo: customIndexContainerView.trailingAnchor),
                        customIndexStackView.topAnchor.constraint(equalTo: customIndexContainerView.topAnchor),
                        customIndexStackView.bottomAnchor.constraint(equalTo: customIndexContainerView.bottomAnchor)
                    ])

                    rebuildCustomIndexLabels()
                }

                if customIndexLabels.isEmpty {
                    rebuildCustomIndexLabels()
                }

                tableView.bringSubviewToFront(customIndexContainerView)

                refreshCustomIndexVisibility()

                DispatchQueue.main.async { [weak self] in
                    self?.refreshCustomIndexVisibility()
                }
            }

            private func rebuildCustomIndexLabels() {
                for label in customIndexLabels {
                    customIndexStackView.removeArrangedSubview(label)
                    label.removeFromSuperview()
                }

                customIndexLabels.removeAll()

                for title in IndexedVocabularyList.allIndexTitles {
                    let label = UILabel()
                    label.translatesAutoresizingMaskIntoConstraints = false
                    label.text = title
                    label.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
                    label.textColor = .systemBlue
                    label.textAlignment = .center

                    NSLayoutConstraint.activate([
                        label.widthAnchor.constraint(equalToConstant: 20)
                    ])

                    customIndexStackView.addArrangedSubview(label)
                    customIndexLabels.append(label)
                }
            }

            func refreshCustomIndexVisibility() {
                let isScrollable = isTableViewScrollable()
                let shouldShowIndex = !customIndexLabels.isEmpty && isScrollable

                customIndexContainerView.isHidden = !shouldShowIndex
                customIndexContainerView.isUserInteractionEnabled = shouldShowIndex

                if !shouldShowIndex {
                    hideScrollingIndexOverlayImmediately()
                }
            }

            private func isTableViewScrollable() -> Bool {
                guard let tableView else {
                    return false
                }

                tableView.layoutIfNeeded()
                let visibleHeight = tableView.bounds.height
                guard visibleHeight > 1 else {
                    return false
                }

                let contentHeight = tableView.contentSize.height

                return contentHeight > visibleHeight + 1
            }

            private func nearestIndexPosition(for point: CGPoint) -> Int? {
                guard !customIndexLabels.isEmpty else {
                    return nil
                }

                customIndexStackView.layoutIfNeeded()

                var nearestIndex = 0
                var nearestDistance = CGFloat.greatestFiniteMagnitude

                for (index, label) in customIndexLabels.enumerated() {
                    let distance = abs(point.y - label.frame.midY)

                    if distance < nearestDistance {
                        nearestDistance = distance
                        nearestIndex = index
                    }
                }

                return nearestIndex
            }

            private func resolveSection(for title: String, at index: Int) -> Int {
                guard !visibleSectionTitles.isEmpty else {
                    return 0
                }

                if let exactIndex = visibleSectionTitles.firstIndex(of: title) {
                    return exactIndex
                }

                for next in index..<IndexedVocabularyList.allIndexTitles.count {
                    let candidate = IndexedVocabularyList.allIndexTitles[next]
                    if let resolvedIndex = visibleSectionTitles.firstIndex(of: candidate) {
                        return resolvedIndex
                    }
                }

                for previous in stride(from: index, through: 0, by: -1) {
                    let candidate = IndexedVocabularyList.allIndexTitles[previous]
                    if let resolvedIndex = visibleSectionTitles.firstIndex(of: candidate) {
                        return resolvedIndex
                    }
                }

                return 0
            }

            private func navigateToSection(at index: Int) {
                guard let tableView,
                      !IndexedVocabularyList.allIndexTitles.isEmpty,
                      !visibleSectionTitles.isEmpty else {
                    return
                }

                let boundedIndex = min(max(index, 0), IndexedVocabularyList.allIndexTitles.count - 1)
                let title = IndexedVocabularyList.allIndexTitles[boundedIndex]
                showScrollingIndexOverlay(title: title)

                let section = resolveSection(for: title, at: boundedIndex)
                let rowCount = tableView.numberOfRows(inSection: section)

                guard rowCount > 0 else {
                    return
                }

                tableView.scrollToRow(at: IndexPath(row: 0, section: section), at: .top, animated: false)
            }

            @objc
            private func handleCustomIndexTap(_ gesture: UITapGestureRecognizer) {
                let point = gesture.location(in: customIndexStackView)

                guard let index = nearestIndexPosition(for: point) else {
                    return
                }

                navigateToSection(at: index)
                scheduleHideScrollingIndexOverlay()
            }

            @objc
            private func handleCustomIndexPan(_ gesture: UIPanGestureRecognizer) {
                let point = gesture.location(in: customIndexStackView)

                switch gesture.state {
                case .began, .changed:
                    if let index = nearestIndexPosition(for: point) {
                        navigateToSection(at: index)
                    }
                case .ended, .cancelled, .failed:
                    scheduleHideScrollingIndexOverlay()
                default:
                    break
                }
            }

            private func rebuildSections() {
                var grouped: [String: [VocabularyEntry]] = [:]

                for indexTitle in IndexedVocabularyList.allIndexTitles {
                    grouped[indexTitle] = []
                }

                for entry in entries {
                    let indexTitle = IndexedVocabularyList.indexTitle(for: entry.reading)
                    grouped[indexTitle, default: []].append(entry)
                }

                groupedEntries = grouped
                visibleSectionTitles = IndexedVocabularyList.allIndexTitles.filter {
                    !(groupedEntries[$0]?.isEmpty ?? true)
                }

                refreshCustomIndexVisibility()

                if visibleSectionTitles.isEmpty {
                    hideScrollingIndexOverlayImmediately()
                }
            }

            private func currentVisibleSectionTitle(in tableView: UITableView) -> String? {
                let topY = tableView.contentOffset.y + tableView.adjustedContentInset.top + 1
                let probePoint = CGPoint(x: 8, y: max(topY, 1))

                if let indexPath = tableView.indexPathForRow(at: probePoint),
                   indexPath.section < visibleSectionTitles.count {
                    return visibleSectionTitles[indexPath.section]
                }

                guard let firstVisible = tableView.indexPathsForVisibleRows?.sorted(by: {
                    if $0.section == $1.section {
                        return $0.row < $1.row
                    }
                    return $0.section < $1.section
                }).first,
                firstVisible.section < visibleSectionTitles.count else {
                    return nil
                }

                return visibleSectionTitles[firstVisible.section]
            }

            private func showScrollingIndexOverlay(title: String?) {
                guard isTableViewScrollable() else {
                    hideScrollingIndexOverlayImmediately()
                    return
                }

                guard let title, !title.isEmpty else {
                    return
                }

                overlayHideWorkItem?.cancel()
                currentIndexIndicatorTitle = title
                onIndexIndicatorStateChange(title, true)
            }

            private func scheduleHideScrollingIndexOverlay() {
                overlayHideWorkItem?.cancel()

                let workItem = DispatchWorkItem { [weak self] in
                    guard let self else {
                        return
                    }

                    self.onIndexIndicatorStateChange(self.currentIndexIndicatorTitle, false)
                }

                overlayHideWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
            }

            private func hideScrollingIndexOverlayImmediately() {
                overlayHideWorkItem?.cancel()
                onIndexIndicatorStateChange(currentIndexIndicatorTitle, false)
            }

            private func entry(at indexPath: IndexPath) -> VocabularyEntry {
                let sectionTitle = visibleSectionTitles[indexPath.section]
                return groupedEntries[sectionTitle]![indexPath.row]
            }

            func numberOfSections(in tableView: UITableView) -> Int {
                visibleSectionTitles.count
            }

            func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
                let sectionTitle = visibleSectionTitles[section]
                return groupedEntries[sectionTitle]?.count ?? 0
            }

            func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
                nil
            }

            func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
                CGFloat.leastNonzeroMagnitude
            }

            func sectionIndexTitles(for tableView: UITableView) -> [String]? {
                nil
            }

            func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int {
                resolveSection(for: title, at: index)
            }

            func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
                guard let tableView = scrollView as? UITableView else {
                    return
                }

                showScrollingIndexOverlay(title: currentVisibleSectionTitle(in: tableView))
            }

            func scrollViewDidScroll(_ scrollView: UIScrollView) {
                guard let tableView = scrollView as? UITableView else {
                    return
                }

                let isUserInteracting = scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating
                guard isUserInteracting else {
                    return
                }

                showScrollingIndexOverlay(title: currentVisibleSectionTitle(in: tableView))
            }

            func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
                if !decelerate {
                    scheduleHideScrollingIndexOverlay()
                }
            }

            func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
                scheduleHideScrollingIndexOverlay()
            }

            func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
                let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellReuseIdentifier, for: indexPath)
                let entry = entry(at: indexPath)

                let candidateLabel: UILabel
                let readingLabel: UILabel

                if let existingCandidateLabel = cell.contentView.viewWithTag(Self.candidateLabelTag) as? UILabel,
                   let existingReadingLabel = cell.contentView.viewWithTag(Self.readingLabelTag) as? UILabel {
                    candidateLabel = existingCandidateLabel
                    readingLabel = existingReadingLabel
                } else {
                    candidateLabel = UILabel()
                    candidateLabel.tag = Self.candidateLabelTag
                    candidateLabel.translatesAutoresizingMaskIntoConstraints = false
                    candidateLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
                    candidateLabel.textColor = .label
                    candidateLabel.textAlignment = .left
                    candidateLabel.lineBreakMode = .byTruncatingTail

                    readingLabel = UILabel()
                    readingLabel.tag = Self.readingLabelTag
                    readingLabel.translatesAutoresizingMaskIntoConstraints = false
                    readingLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                    readingLabel.textColor = .secondaryLabel
                    readingLabel.textAlignment = .left
                    readingLabel.lineBreakMode = .byTruncatingTail

                    cell.contentView.addSubview(candidateLabel)
                    cell.contentView.addSubview(readingLabel)

                    NSLayoutConstraint.activate([
                        candidateLabel.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 10),
                        candidateLabel.trailingAnchor.constraint(lessThanOrEqualTo: cell.contentView.centerXAnchor, constant: -10),
                        candidateLabel.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),

                        readingLabel.leadingAnchor.constraint(equalTo: cell.contentView.centerXAnchor, constant: -2),
                        readingLabel.trailingAnchor.constraint(lessThanOrEqualTo: cell.contentView.trailingAnchor, constant: -10),
                        readingLabel.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor)
                    ])
                }

                candidateLabel.text = entry.candidate
                readingLabel.text = entry.reading

                cell.textLabel?.text = nil
                cell.backgroundColor = UIColor.white.withAlphaComponent(0.72)
                cell.selectionStyle = .none

                return cell
            }

            func tableView(
                _ tableView: UITableView,
                trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
            ) -> UISwipeActionsConfiguration? {
                let target = entry(at: indexPath)

                let delete = UIContextualAction(style: .destructive, title: "削除") { [weak self] _, _, completion in
                    self?.onDelete(target)
                    completion(true)
                }

                return UISwipeActionsConfiguration(actions: [delete])
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Spacer(minLength: 0)

                        Image("AppLogoDisplay")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 92, height: 92)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .shadow(color: Color.black.opacity(0.12), radius: 5, y: 2)

                        Spacer(minLength: 0)
                    }

                    Text("このアプリはカスタムキーボード拡張の設定・管理を行うコンテナー・アプリ (Containing App) です。キーボード本体は拡張ターゲット側で実装されています。")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("フリック方向")
                            .font(.headline)

                        Picker("フリック方向", selection: directionSelection) {
                            ForEach(DirectionOption.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("Apple / écritu の切り替えは次回のキーボード表示時に反映されます。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .settingsCardStyle()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("かな修飾")
                            .font(.headline)

                        Picker("かな修飾", selection: kanaModifierPlacementSelection) {
                            ForEach(KanaModifierPlacementOption.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("濁点・半濁点・拗音/促音の入力方式を切り替えます。前置修飾は修飾を先に選択、後置修飾は文字入力後に修飾を選択します。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .settingsCardStyle()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("かな配列")
                            .font(.headline)

                        Picker("かな配列", selection: kanaLayoutSelection) {
                            ForEach(KanaLayoutOption.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("かなモードで使う配列を切り替えます。標準は 5x2、3x3+わ は Apple標準の日本語配列に合わせて各段5ボタン(3かな + 機能2)で表示します。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .settingsCardStyle()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("ラテン文字配列")
                            .font(.headline)

                        Picker("ラテン文字配列", selection: latinLayoutSelection) {
                            ForEach(LatinLayoutOption.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("abcモードで使う配列を切り替えます。qwerty/azertyでは文字キーを長押ししてアクセント付き文字を入力できます。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .settingsCardStyle()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("数字配列")
                            .font(.headline)

                        Picker("数字配列", selection: numberLayoutSelection) {
                            ForEach(NumberLayoutOption.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("123モードの数字キー配列を切り替えます。téléphone は上段が 1-2-3、calculette は上段が 7-8-9 です。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .settingsCardStyle()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("アクセントカラー")
                            .font(.headline)

                        HStack(spacing: 8) {
                            ForEach(AccentColorOption.allCases) { option in
                                let isSelected = accentPaletteSelection.wrappedValue == option

                                Button {
                                    accentPaletteSelection.wrappedValue = option
                                } label: {
                                    Text(option.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(option.color)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                .fill(
                                                    isSelected
                                                        ? Color.white.opacity(0.96)
                                                        : Color.white.opacity(0.7)
                                                )
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                .stroke(
                                                    isSelected
                                                        ? option.color.opacity(0.65)
                                                        : Color.black.opacity(0.1),
                                                    lineWidth: isSelected ? 1.3 : 1
                                                )
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(option.title)
                            }
                        }
                        .padding(4)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(white: 0.9))
                        )

                        Text("キー押下時のアクセント色を切り替えます。チュイレは瓦の色、エメロードは宝石の色です。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .settingsCardStyle()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("テーマカラー")
                            .font(.headline)

                        VStack(spacing: 8) {
                            ForEach(KeyboardBackgroundThemeOption.allCases) { option in
                                let isSelected = keyboardBackgroundThemeSelection.wrappedValue == option

                                Button {
                                    keyboardBackgroundThemeSelection.wrappedValue = option
                                } label: {
                                    HStack(alignment: .top, spacing: 9) {
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .fill(
                                                LinearGradient(
                                                    colors: option.gradientColors,
                                                    startPoint: .top,
                                                    endPoint: .bottom
                                                )
                                            )
                                            .frame(width: 52, height: 30)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
                                            )

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(option.title)
                                                .font(.footnote.weight(.semibold))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.9)

                                            Text(option.subtitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(3)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(
                                                isSelected
                                                    ? Color.accentColor
                                                    : Color.black.opacity(0.22)
                                            )
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 9)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(
                                                isSelected
                                                    ? Color.white.opacity(0.96)
                                                    : Color.white.opacity(0.72)
                                            )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(
                                                isSelected
                                                    ? Color.black.opacity(0.15)
                                                    : Color.black.opacity(0.08),
                                                lineWidth: isSelected ? 1.2 : 1
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(option.title)
                            }
                        }
                        .padding(4)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(white: 0.9))
                        )

                        Text("キーボード背景のグラデイションを切り替えます。左の色見本は実際の背景色です。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .settingsCardStyle()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("表示")
                            .font(.headline)

                        Toggle("フリックガイド文字", isOn: $showsFlickGuideCharacters)
                            .tint(Color.orange)

                        Text("各キーの4方向に表示するガイド文字のON/OFFを切り替えます。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .settingsCardStyle()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("削除キーリピート")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("リピート開始までの時間")
                                        .font(.subheadline.weight(.semibold))
                                    Spacer(minLength: 12)
                                    if isAtRepeatDefault(
                                        keyRepeatInitialDelay,
                                        default: RepeatSettings.initialDelayDefault
                                    ) {
                                        Text("デフォルト")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(Color.orange)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(
                                                Capsule(style: .continuous)
                                                    .fill(Color.orange.opacity(0.12))
                                            )
                                    }
                                    Text("\(keyRepeatInitialDelay.formatted(.number.precision(.fractionLength(2)))) 秒")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }

                                Slider(value: keyRepeatInitialDelayBinding, in: RepeatSettings.initialDelayRange, step: 0.01)
                                    .tint(Color.orange)

                                HStack {
                                    Text("デフォルト: \(RepeatSettings.initialDelayDefault.formatted(.number.precision(.fractionLength(2)))) 秒")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Spacer(minLength: 8)

                                    if !isAtRepeatDefault(
                                        keyRepeatInitialDelay,
                                        default: RepeatSettings.initialDelayDefault
                                    ) {
                                        Button("デフォルトに戻す") {
                                            keyRepeatInitialDelay = RepeatSettings.initialDelayDefault
                                        }
                                        .font(.caption.weight(.semibold))
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("リピート速度(間隔)")
                                        .font(.subheadline.weight(.semibold))
                                    Spacer(minLength: 12)
                                    if isAtRepeatDefault(
                                        keyRepeatInterval,
                                        default: RepeatSettings.intervalDefault
                                    ) {
                                        Text("デフォルト")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(Color.orange)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(
                                                Capsule(style: .continuous)
                                                    .fill(Color.orange.opacity(0.12))
                                            )
                                    }
                                    Text("\(keyRepeatInterval.formatted(.number.precision(.fractionLength(2)))) 秒")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }

                                Slider(value: keyRepeatIntervalBinding, in: RepeatSettings.intervalRange, step: 0.01)
                                    .tint(Color.orange)

                                HStack {
                                    Text("デフォルト: \(RepeatSettings.intervalDefault.formatted(.number.precision(.fractionLength(2)))) 秒")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Spacer(minLength: 8)

                                    if !isAtRepeatDefault(
                                        keyRepeatInterval,
                                        default: RepeatSettings.intervalDefault
                                    ) {
                                        Button("デフォルトに戻す") {
                                            keyRepeatInterval = RepeatSettings.intervalDefault
                                        }
                                        .font(.caption.weight(.semibold))
                                    }
                                }
                            }
                        }

                        Text("削除キーは1回目の押下で削除され、上の時間が過ぎると設定した間隔で連続削除されます。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .settingsCardStyle()

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

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text("追加語彙")
                                .font(.headline)

                            Spacer(minLength: 8)

                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isUserDictionaryRegistrationVisible.toggle()
                                }
                            } label: {
                                Image(systemName: isUserDictionaryRegistrationVisible ? "xmark" : "plus")
                                    .font(.headline.weight(.bold))
                                    .frame(width: 28, height: 28)
                                    .background(
                                        Circle()
                                            .fill(
                                                isUserDictionaryRegistrationVisible
                                                    ? Color.red.opacity(0.16)
                                                    : Color.accentColor.opacity(0.14)
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                isUserDictionaryRegistrationVisible
                                    ? "追加単語の登録欄を閉じる"
                                    : "追加単語の登録欄を表示"
                            )
                        }

                        if isUserDictionaryRegistrationVisible {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("追加単語の登録")
                                    .font(.subheadline.weight(.semibold))

                                HStack(spacing: 8) {
                                    TextField("候補", text: $userDictionaryCandidateInput)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(Color.white.opacity(0.9))
                                        )

                                    TextField("よみ", text: $userDictionaryReadingInput)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(Color.white.opacity(0.9))
                                        )

                                    Button("登録") {
                                        addUserDictionaryEntry()
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            isUserDictionaryRegistrationVisible = false
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(!canAddUserDictionaryEntry)
                                }
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Spacer(minLength: 8)

                            Text(userDictionaryScrollIndexTitle)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .frame(minWidth: 26, minHeight: 20)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.white.opacity(0.82))
                                )
                                .opacity(isUserDictionaryScrollIndexVisible ? 1 : 0)
                                .animation(.easeOut(duration: 0.28), value: isUserDictionaryScrollIndexVisible)
                        }

                        if userDictionaryEntries.isEmpty {
                            Text("登録済みの追加単語はありません。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            IndexedVocabularyList(
                                entries: userDictionaryEntries,
                                onDelete: removeUserDictionaryEntry,
                                onIndexIndicatorStateChange: { title, isVisible in
                                    DispatchQueue.main.async {
                                        if !title.isEmpty {
                                            userDictionaryScrollIndexTitle = title
                                        }

                                        withAnimation(.easeOut(duration: 0.28)) {
                                            isUserDictionaryScrollIndexVisible = isVisible
                                        }
                                    }
                                }
                            )
                            .frame(height: userVocabularyListHeight(for: userDictionaryEntries.count))
                        }

                        Button("学習履歴をリセット") {
                            resetKanaKanjiLearning()
                        }
                        .buttonStyle(.bordered)

                        Text("追加単語はキーボード拡張と共有され、候補の優先順位に反映されます。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .settingsCardStyle()

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text("抑制語彙")
                                .font(.headline)

                            Spacer(minLength: 8)

                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isSuppressionDictionaryRegistrationVisible.toggle()
                                }
                            } label: {
                                Image(systemName: isSuppressionDictionaryRegistrationVisible ? "xmark" : "plus")
                                    .font(.headline.weight(.bold))
                                    .frame(width: 28, height: 28)
                                    .background(
                                        Circle()
                                            .fill(
                                                isSuppressionDictionaryRegistrationVisible
                                                    ? Color.red.opacity(0.16)
                                                    : Color.accentColor.opacity(0.14)
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                isSuppressionDictionaryRegistrationVisible
                                    ? "抑制単語の登録欄を閉じる"
                                    : "抑制単語の登録欄を表示"
                            )
                        }

                        if isSuppressionDictionaryRegistrationVisible {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("抑制単語の登録")
                                    .font(.subheadline.weight(.semibold))

                                HStack(spacing: 8) {
                                    TextField("単語", text: $suppressionDictionaryCandidateInput)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(Color.white.opacity(0.9))
                                        )

                                    TextField("よみ", text: $suppressionDictionaryReadingInput)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(Color.white.opacity(0.9))
                                        )

                                    Button("登録") {
                                        addSuppressionDictionaryEntry()
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            isSuppressionDictionaryRegistrationVisible = false
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(!canAddSuppressionDictionaryEntry)
                                }
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Spacer(minLength: 8)

                            Text(suppressionDictionaryScrollIndexTitle)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .frame(minWidth: 26, minHeight: 20)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.white.opacity(0.82))
                                )
                                .opacity(isSuppressionDictionaryScrollIndexVisible ? 1 : 0)
                                .animation(.easeOut(duration: 0.28), value: isSuppressionDictionaryScrollIndexVisible)
                        }

                        if suppressionDictionaryEntries.isEmpty {
                            Text("登録済みの抑制単語はありません。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            IndexedVocabularyList(
                                entries: suppressionDictionaryEntries,
                                onDelete: removeSuppressionDictionaryEntry,
                                onIndexIndicatorStateChange: { title, isVisible in
                                    DispatchQueue.main.async {
                                        if !title.isEmpty {
                                            suppressionDictionaryScrollIndexTitle = title
                                        }

                                        withAnimation(.easeOut(duration: 0.28)) {
                                            isSuppressionDictionaryScrollIndexVisible = isVisible
                                        }
                                    }
                                }
                            )
                            .frame(height: userVocabularyListHeight(for: suppressionDictionaryEntries.count))
                        }

                        Text("抑制は『読み+単語』の組み合わせで適用され、同じ単語でも別の読み候補には影響しません。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .settingsCardStyle()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("有効化手順")
                            .font(.headline)
                        ForEach(Array(setupSteps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1).")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(step)
                                    .font(.subheadline)
                            }
                        }
                    }
                    .settingsCardStyle()

                    Text("フリック入力に加えて、かな漢字変換・追加単語・抑制単語に対応しています。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .onAppear {
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
