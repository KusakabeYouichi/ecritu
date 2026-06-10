import SwiftUI
import UIKit
import CoreFoundation
import Darwin
import Contacts

final class KeyboardViewController: UIInputViewController {
    enum UserInitiatedRefreshReason: String {
        case kanaInput = "kanaInput"
        case commit = "commit"
        case postModifier = "postModifier"
    }

    private static let sharedKanaKanjiStore = KanaKanjiStore(appGroupID: SharedDefaultsKeys.appGroupID)
    private static let sharedKanaKanjiConverter = KanaKanjiConverter(store: sharedKanaKanjiStore)
    private static let isSupplementaryExternalCandidatesEnabled = true
    private static let organizationPrefixReadingsToTrim: [String] = [
        "かぶしきがいしゃ",
        "ゆうげんがいしゃ",
        "ごうどうがいしゃ",
        "ごうめいがいしゃ",
        "ごうしがいしゃ",
        "いっぱんしゃだんほうじん",
        "いっぱんざいだんほうじん",
        "こうえきしゃだんほうじん",
        "こうえきざいだんほうじん",
        "とくていひえいりかつどうほうじん",
        "しゃかいふくしほうじん",
        "いりょうほうじん",
        "がっこうほうじん",
        "しゅうきょうほうじん"
    ]
    private static let emojiReadingCandidatesByReading: [String: [String]] = {
        let allCandidates = Set(
            AppleEmojiCatalog.people
                + AppleEmojiCatalog.nature
                + AppleEmojiCatalog.foodAndDrink
                + AppleEmojiCatalog.activity
                + AppleEmojiCatalog.travelAndPlaces
                + AppleEmojiCatalog.objects
                + AppleEmojiCatalog.symbols
                + AppleEmojiCatalog.flags
        )
        let entries: [(String, [String])] = [
            ("えがお", ["😀", "😄", "😊", "🙂"]),
            ("にこにこ", ["😊", "😄", "😁"]),
            ("にっこり", ["🙂", "😊", "☺️"]),
            ("うれしい", ["😊", "🥰", "😍"]),
            ("しあわせ", ["😊", "🥰", "😇"]),
            ("てれる", ["😊", "☺️", "🥰"]),
            ("わらい", ["😂", "🤣", "😆"]),
            ("えへへ", ["😅", "😊", "😄"]),
            ("にやり", ["😏", "😼", "😎"]),
            ("なみだ", ["😭", "😢", "🥲"]),
            ("かなしい", ["😢", "🥲", "😞"]),
            ("しょんぼり", ["😔", "😞", "🙁"]),
            ("おこり", ["😡", "😠", "🤬"]),
            ("いかり", ["😠", "😡", "🤬"]),
            ("げきおこ", ["🤬", "😡", "😤"]),
            ("おどろき", ["😳", "😲", "😮"]),
            ("びっくり", ["😳", "😲", "😱"]),
            ("しんぱい", ["😟", "😰", "😨"]),
            ("ねむい", ["😴", "😪", "🥱"]),
            ("つかれた", ["😮‍💨", "😩", "😪"]),
            ("あせ", ["😅", "😓", "😥"]),
            ("あせる", ["😅", "😓", "😰"]),
            ("ぴえん", ["🥺"]),
            ("うるうる", ["🥹", "🥺", "🥲"]),
            ("はーと", ["❤️", "💔", "💕"]),
            ("らぶ", ["❤️", "💕", "🥰"]),
            ("だいすき", ["🥰", "😍", "❤️"]),
            ("はーとぶれいく", ["💔"]),
            ("きらきら", ["✨"]),
            ("まる", ["⭕️"]),
            ("ばつ", ["❌"]),
            ("ひゃく", ["💯"]),
            ("おんぷ", ["🎵", "🎶"]),
            ("ぱーてぃー", ["🥳", "🎉"]),
            ("おいわい", ["🎉", "🥳", "✨"]),
            ("ぷれぜんと", ["🎁", "🎉"]),
            ("けーき", ["🎂"]),
            ("こーひー", ["☕️"]),
            ("びーる", ["🍺"]),
            ("かんぱい", ["🍺", "🍻", "🥂"]),
            ("はんばーがー", ["🍔"]),
            ("ごはん", ["🍚", "🍙", "🍛"]),
            ("すし", ["🍣"]),
            ("らーめん", ["🍜"]),
            ("ぴざ", ["🍕"]),
            ("ぽてと", ["🍟"]),
            ("いちご", ["🍓"]),
            ("いぬ", ["🐶"]),
            ("ねこ", ["🐱"]),
            ("さる", ["🐵"]),
            ("うさぎ", ["🐰"]),
            ("ぱんだ", ["🐼"]),
            ("ぺんぎん", ["🐧"]),
            ("ひよこ", ["🐤"]),
            ("くるま", ["🚗"]),
            ("たくしー", ["🚕"]),
            ("ばす", ["🚌"]),
            ("でんしゃ", ["🚃", "🚅"]),
            ("しんかんせん", ["🚅"]),
            ("ひこうき", ["✈️"]),
            ("ろけっと", ["🚀"]),
            ("たいよう", ["☀️"]),
            ("つき", ["🌙"]),
            ("あめ", ["☔️"]),
            ("ゆき", ["❄️"]),
            ("ほのお", ["🔥"]),
            ("ぐっど", ["👍"]),
            ("いいね", ["👍", "👌"]),
            ("だめ", ["👎", "❌"]),
            ("ぴーす", ["✌️", "👍"]),
            ("おねがい", ["🙏"]),
            ("ありがとう", ["🙏", "😊"]),
            ("はくしゅ", ["👏"]),
            ("ばんざい", ["🙌"]),
            ("がっつぽーず", ["💪", "✊"]),
            ("てをふる", ["👋"]),
            ("おーけー", ["👌"]),
            ("どくろ", ["💀", "☠️"]),
            ("おばけ", ["👻"]),
            ("うんち", ["💩"]),
            ("ろぼっと", ["🤖"])
        ]
        return buildSupplementarySymbolCandidatesByReading(entries: entries, allowedCandidates: allCandidates)
    }()
    private static let kaomojiReadingCandidatesByReading: [String: [String]] = {
        let allCandidates = Set(KaomojiCatalog.entries)
        let entries: [(String, [String])] = [
            ("えがお", ["^_^", "(^^)", "(*^^*)", "(o^^o)"]),
            ("にこにこ", ["^_^", "(^^)", "(*^^*)"]),
            ("にっこり", ["(o^^o)", "(*^_^*)", "(^_^)v"]),
            ("わらい", ["(≧∀≦)", "(⌒▽⌒)", "(*´∀`*)"]),
            ("うれしい", ["٩( 'ω' )و", "٩(^‿^)۶", "(*^▽^*)"]),
            ("たのしい", ["(⌒▽⌒)", "o(^▽^)o", "♪( ´▽`)"]),
            ("てれ", ["(//∇//)", "(〃ω〃)"]),
            ("おねがい", ["m(_ _)m", "m(__)m", "(^人^)"]),
            ("かなしい", ["( T_T)/(^-^ )"]),
            ("ないた", ["(T_T)", "(;_;)", "(´;ω;`)"]),
            ("しょんぼり", ["(-_-)", "( ¬_¬)", "( ..ω.. )"]),
            ("ねむい", ["(-_-)zzz", "(( _ _ ))..zzzZZ"]),
            ("つかれた", ["(-_-)", "(_ _)..o○", "(´-`)..oO"]),
            ("いかり", ["( *`ω´)", "o(`ω´ )o"]),
            ("びっくり", ["(・Д・)", "(　oдo)", "Σ('◉⌓◉’)" ]),
            ("はてな", ["(・・?)", "(@_@)", "(o_o)"]),
            ("しょっく", ["Σ(oдolll)", "Σ(-。-/)/", "((((;oДo)))))))"]),
            ("あせる", [":(;'o'ωo'):", "(ㆀ˘.з.˘)", "(⁎⁍̴̆Ɛ⁍̴̆⁎)"]),
            ("ごめん", ["m(_ _)m", "m(._.)m", "(>人<;)"]),
            ("どうも", ["m(__)m", "(^人^)"]),
            ("やった", ["٩( 'ω' )و", "(^^)v", "(^-^)v"]),
            ("ぴーす", ["✌︎('ω')✌︎", "( ✌︎'ω')✌︎", "✌︎('ω'✌︎ )"]),
            ("きりっ", ["(`・ω・´)", "(`・∀・´)", "(=^▽^)σ"]),
            ("どや", ["(`・ω・´)", "( ͡° ͜ʖ ͡°)"]),
            ("どんまい", ["( T_T)/(^-^ )", "ʅ(◞‿◟)ʃ"]),
            ("よろしく", ["(^人^)", "m(_ _)m"]),
            ("おつかれ", ["(^_^)a", "(-^-)ゞ", "(`_´)ゞ"]),
            ("くま", ["ʕ•ᴥ•ʔ", "(ᵔᴥᵔ)"]),
            ("ねこ", ["(=^x^=)", "(=^ェ^=)"]),
            ("いぬ", ["U・x・U", "U^ェ^U"]),
            ("ぺんぎん", ["∧( 'Θ' )∧", "ϵ( 'Θ' )϶"]),
            ("かお", ["('ω')", "(・ω・)", "(°_°)"]),
            ("へんがお", ["(๑•ૅㅁ•๑)", "(΄◉◞౪◟◉`)", "Σ੧(❛□❛✿)"]),
            ("しろめ", ["(o_o)", "(O_O)", "(@_@)"]),
            ("おこ", ["( *`ω´)", "o(`ω´ )o"]),
            ("いや", [">_<", "(>_<)", "(ノ_<)"])
        ]
        return buildSupplementarySymbolCandidatesByReading(entries: entries, allowedCandidates: allCandidates)
    }()
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
    private var dictionaryPreloadWorkItem: DispatchWorkItem?
    private var keyboardBootstrapWorkItem: DispatchWorkItem?
    private var sharedDataPrewarmWorkItem: DispatchWorkItem?
    private var supplementaryLexiconCandidatesByReading: [String: [String]] = [:]
    private var supplementaryMergedCandidatesCacheByKey: [String: [String]] = [:]
    private var contactCandidatesByReading: [String: [String]] = [:]
    private var isRefreshingSupplementaryLexicon = false
    private var supplementaryLexiconLastRefreshAt: Date?
    private var isRefreshingContactCandidates = false
    private var contactCandidatesLastRefreshAt: Date?
    var currentInputMode: KeyboardInputMode = .kana
    private var spaceToastTrigger = 0
    var composingRawText = ""
    var composingReading = ""
    var hasParenthesesWrapper = false
    var activeConversion: ActiveConversion?
    var recentKanaPlainCommit: RecentKanaPlainCommit?
    let recentKanaPlainCommitUpgradeWindow: TimeInterval = 0.45
    var lastKanaPostModifierAppliedAt: CFAbsoluteTime = 0
    var lastKanaPostModifierResultCharacter: Character?
    var lastTextProxyEditAt: CFAbsoluteTime = 0
    let externalTextChangeDetectionWindow: CFTimeInterval = 0.35
    var lastSynchronizedContextBeforeInput = ""
    var composingContextPrefixTail = ""
    var pendingHostCallbackUnderlineClearNudgeWidth: Int?
    var pendingHostCallbackUnderlineClearDeadline: CFAbsoluteTime = 0
    private var kanaKanjiStore: KanaKanjiStore { Self.sharedKanaKanjiStore }
    var kanaKanjiConverter: KanaKanjiConverter { Self.sharedKanaKanjiConverter }
    private lazy var sharedDefaults = UserDefaults(suiteName: SharedDefaultsKeys.appGroupID)
    private var diagnosticsSessionID = UUID().uuidString
    private var diagnosticsSessionStartedAt = Date()
    private let diagnosticsControllerID = UUID().uuidString
    private var pendingRefreshKeyboardStateRequests = 0
    private var isRefreshKeyboardStateAsyncScheduled = false
    private var diagnosticsFlightRecorderLastObservedAt: [String: TimeInterval] = [:]
    private var memoryFailSafeProfile: MemoryFailSafeProfile = .normal
    private var hasDeferredSharedSettingsCatchUp = false
    private var lastInactiveSessionSuppressionLogAt: CFAbsoluteTime = 0
    private var didApplyInactiveSessionMitigation = false

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

    struct RecentKanaPlainCommit: Equatable {
        let sourceText: String
        let sourceReading: String
        let committedText: String
        let committedAt: Date
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
        static let modifierFlickGuideDisplayMode = "flickGuideDisplayModeModifier"
        static let showsFlickGuideCharacters = "showsFlickGuideCharacters"
        static let keyRepeatInitialDelay = "keyRepeatInitialDelay"
        static let keyRepeatInterval = "keyRepeatInterval"
        static let kanaModeSwitcherTapAction = "kanaModeSwitcherTapAction"
        static let kanaModeSwitcherRightFlickAction = "kanaModeSwitcherRightFlickAction"
        static let kanaModeSwitcherUpFlickAction = "kanaModeSwitcherUpFlickAction"
        static let delimiterAutoCommitCandidate = "delimiterAutoCommitCandidate"
        static let landscapeCandidateSide = "landscapeCandidateSide"
        static let landscapeNumberPaneSide = "landscapeNumberPaneSide"
        static let landscapeLatinSuggestionMode = "landscapeLatinSuggestionMode"
        static let kanaKanjiCandidateSourceMode = "kanaKanjiCandidateSourceMode"
        static let userDictionaryCandidateDisplayMode = "userDictionaryCandidateDisplayMode"
        static let contactCandidateDisplayMode = "contactCandidateDisplayMode"
        static let emojiCandidateDisplayEnabled = "emojiCandidateDisplayEnabled"
        static let kaomojiCandidateDisplayEnabled = "kaomojiCandidateDisplayEnabled"
        static let contactCandidatesByReadingCache = "contactCandidatesByReadingCache"
        static let supplementaryLexiconIndexCacheByReading = "supplementaryLexiconIndexCacheByReading"
        static let supplementaryLexiconIndexSignature = "supplementaryLexiconIndexSignature"
        static let keyboardDiagnosticsLogLines = "keyboardDiagnosticsLogLines"
        static let keyboardDiagnosticsInstallMarker = "keyboardDiagnosticsInstallMarker"
        static let keyboardDiagnosticsSessionActive = "keyboardDiagnosticsSessionActive"
        static let keyboardDiagnosticsSessionOwnerToken = "keyboardDiagnosticsSessionOwnerToken"
        static let keyboardDiagnosticsLastHeartbeat = "keyboardDiagnosticsLastHeartbeat"
        static let keyboardDiagnosticsLastEvent = "keyboardDiagnosticsLastEvent"
        static let keyboardDiagnosticsLastSessionID = "keyboardDiagnosticsLastSessionID"
        static let keyboardDiagnosticsFailSafeProfile = "keyboardDiagnosticsFailSafeProfile"
        static let keyboardDiagnosticsFlightRecorderEvents = "keyboardDiagnosticsFlightRecorderEvents"
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
        controller.handleSharedSettingsDidChange()
    }

    private static let diagnosticsTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

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
    private static let deviceSystemDictionaryPreloadDelay: TimeInterval = 1.2
    private static let minimumPhysicalMemoryForSystemDictionaryPreload: UInt64 = 5 * 1024 * 1024 * 1024
    private static let maximumResidentMemoryMBForSystemDictionaryPreload: Double = 95
    private static let refreshQueueBacklogLogThreshold = 6
    private static let refreshQueueWaitSlowThresholdMs = 60
    private static let renderConfigurationSlowThresholdMs = 16
    private static let refreshKeyboardStateSlowThresholdMs = 28
    private static let maximumContactCandidateReadings = 4096
    private static let maximumContactCandidateTotalEntries = 16384
    private static let maximumContactCandidatesPerReading = 48
    private static let maximumSupplementaryMergedCandidateCacheEntries = 512
    private static let memoryFailSafeElevatedStartMB: Double = 120
    private static let memoryFailSafeCriticalStartMB: Double = 150
    private static let memoryFailSafeRecoverDeltaMB: Double = 14
    private static let refreshQueueDropThresholdInCriticalMode = 2
    private static let diagnosticsFlightRecorderWindowSec: TimeInterval = 6
    private static let diagnosticsFlightRecorderMaxEventCount = 120
    private static let diagnosticsFlightRecorderMinRecordIntervalSec: TimeInterval = 0.12
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
        let modifierFlickGuideDisplayMode: FlickGuideDisplayMode
        let keyRepeatInitialDelay: TimeInterval
        let keyRepeatInterval: TimeInterval
        let kanaModeSwitcherTapActionRawValue: String
        let kanaModeSwitcherRightFlickActionRawValue: String
        let kanaModeSwitcherUpFlickActionRawValue: String
        let landscapeCandidateSideRawValue: String
        let landscapeNumberPaneSideRawValue: String
        let landscapeLatinSuggestionModeRawValue: String
        let showsNextKeyboardKey: Bool
        let shortcutVocabulary: [String]
        let composingText: String
        let conversionCandidates: [String]
        let selectedConversionCandidateIndex: Int?
        let latinSuggestionQuery: String
        let latinSuggestions: [String]
        let showsParenthesesWrapper: Bool
    }

    private struct DiagnosticsFlightRecorderEvent: Codable {
        let timestamp: TimeInterval
        let event: String
        let source: String
    }

    private enum MemoryFailSafeProfile: String {
        case normal
        case elevated
        case critical
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        startKeyboardDiagnosticsSession()
        updateKeyboardDiagnosticsHeartbeat(event: "viewDidLoad", appendLog: true)
        configureKeyboardContainerSizing()
        beginKeyboardHeightLock()
        prepareKeyboardVisualForTransition()
        configureInputAssistantBar()
        startObservingSettingsDidChange()
        setupKeyboardView()
    }

    deinit {
        finishKeyboardDiagnosticsSession(reason: "deinit")
        keyboardBootstrapWorkItem?.cancel()
        dictionaryPreloadWorkItem?.cancel()
        keyboardHeightLockReleaseWorkItem?.cancel()
        stopObservingSettingsDidChange()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateKeyboardDiagnosticsHeartbeat(event: "viewWillAppear", appendLog: true)

        guard !shouldSuppressHeavyOperations(reason: "viewWillAppear") else {
            return
        }

        configureKeyboardContainerSizing()
        ensureKeyboardViewIfNeeded()
        beginKeyboardHeightLock(using: makeRenderConfiguration())
        configureInputAssistantBar()
        prepareKeyboardVisualForTransition()
        spaceToastTrigger += 1
        refreshKeyboardState(trigger: "viewWillAppear")
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        updateKeyboardDiagnosticsHeartbeat(event: "textDidChange")

        guard !shouldSuppressHeavyOperations(reason: "textDidChange") else {
            return
        }

        synchronizeConversionContextIfNeeded(
            triggeredByExternalChange: shouldTreatAsExternalTextChange()
        )
        consumePendingHostCallbackUnderlineClearPassIfNeeded(trigger: "textDidChange")
        refreshKeyboardState(trigger: "textDidChange")
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        updateKeyboardDiagnosticsHeartbeat(event: "selectionDidChange")

        guard !shouldSuppressHeavyOperations(reason: "selectionDidChange") else {
            return
        }

        synchronizeConversionContextIfNeeded(
            triggeredByExternalChange: shouldTreatAsExternalTextChange()
        )
        consumePendingHostCallbackUnderlineClearPassIfNeeded(trigger: "selectionDidChange")
        refreshKeyboardState(trigger: "selectionDidChange")
    }

    private func refreshSupplementaryLexiconIfNeeded(force: Bool) {
        guard Self.isSupplementaryExternalCandidatesEnabled else {
            supplementaryLexiconCandidatesByReading = [:]
            supplementaryMergedCandidatesCacheByKey = [:]
            return
        }

        hydrateSupplementaryLexiconCandidatesFromPersistentCacheIfNeeded()

        if !force,
            isRefreshingSupplementaryLexicon {
            return
        }

        if !force,
            let lastRefreshAt = supplementaryLexiconLastRefreshAt,
            Date().timeIntervalSince(lastRefreshAt) < 30 {
            return
        }

        isRefreshingSupplementaryLexicon = true

        requestSupplementaryLexicon { [weak self] lexicon in
            guard let self else {
                return
            }

            let lexiconEntries: [(userInput: String, candidate: String)] = lexicon.entries.map { entry in
                (entry.userInput, entry.documentText)
            }

            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self else {
                    return
                }

                let signature = self.supplementaryLexiconEntriesSignature(fromEntries: lexiconEntries)
                let mergedCandidates: [String: [String]]
                let usedPersistentIndex: Bool

                if let cachedCandidates = self.cachedSupplementaryLexiconIndex(signature: signature) {
                    mergedCandidates = cachedCandidates
                    usedPersistentIndex = true
                } else {
                    mergedCandidates = self.buildSupplementaryLexiconCandidates(
                        fromEntries: lexiconEntries
                    )
                    usedPersistentIndex = false
                    self.storeSupplementaryLexiconIndex(
                        signature: signature,
                        dictionary: mergedCandidates
                    )
                }

                let entryCount = mergedCandidates.values.reduce(0) { partialResult, candidates in
                    partialResult + candidates.count
                }

                DispatchQueue.main.async {
                    if self.view.window == nil {
                        self.clearSupplementaryLexiconCandidatesForMemoryTrim()
                        return
                    }

                    self.isRefreshingSupplementaryLexicon = false
                    self.supplementaryLexiconLastRefreshAt = Date()

                    let previousCandidates = self.supplementaryLexiconCandidatesByReading
                    self.supplementaryLexiconCandidatesByReading = mergedCandidates
                    self.supplementaryMergedCandidatesCacheByKey = [:]

                    self.updateKeyboardDiagnosticsHeartbeat(
                        event: "補助語彙を更新 entries=\(entryCount) indexCache=\(usedPersistentIndex ? "hit" : "miss")",
                        appendLog: true
                    )

                    if previousCandidates != mergedCandidates {
                        self.refreshKeyboardStateAsync()
                    }
                }
            }
        }
    }

    private func clearSupplementaryLexiconCandidatesForMemoryTrim() {
        isRefreshingSupplementaryLexicon = false
        supplementaryLexiconLastRefreshAt = Date()
        supplementaryLexiconCandidatesByReading = [:]
        supplementaryMergedCandidatesCacheByKey = [:]
    }

    private func hydrateSupplementaryLexiconCandidatesFromPersistentCacheIfNeeded() {
        guard supplementaryLexiconCandidatesByReading.isEmpty else {
            return
        }

        guard let defaults = UserDefaults(suiteName: SharedDefaultsKeys.appGroupID),
            let cachedDictionary = defaults.dictionary(forKey: SharedDefaultsKeys.supplementaryLexiconIndexCacheByReading)
                as? [String: [String]],
            !cachedDictionary.isEmpty else {
            return
        }

        supplementaryLexiconCandidatesByReading = cachedDictionary
    }

    private func buildSupplementaryLexiconCandidates(
        fromEntries entries: [(userInput: String, candidate: String)]
    ) -> [String: [String]] {
        var dictionary: [String: [String]] = [:]
        var seenCandidatesByReading: [String: Set<String>] = [:]
        let maxCandidatesPerReading = 128

        for entry in entries {
            let candidate = entry.candidate.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !candidate.isEmpty,
                candidate.count <= 64 else {
                continue
            }

            let userInput = entry.userInput.trimmingCharacters(in: .whitespacesAndNewlines)
            var readingKeys = supplementaryReadingKeys(userInput: userInput, candidate: candidate)

            guard !readingKeys.isEmpty else {
                continue
            }

            var seenReadings = Set<String>()
            readingKeys = readingKeys.filter { seenReadings.insert($0).inserted }

            for reading in readingKeys {
                let existingCount = dictionary[reading]?.count ?? 0

                guard existingCount < maxCandidatesPerReading else {
                    continue
                }

                var seenCandidates = seenCandidatesByReading[reading] ?? Set(dictionary[reading] ?? [])

                guard seenCandidates.insert(candidate).inserted else {
                    seenCandidatesByReading[reading] = seenCandidates
                    continue
                }

                seenCandidatesByReading[reading] = seenCandidates
                var candidates = dictionary[reading] ?? []
                candidates.append(candidate)
                dictionary[reading] = candidates
            }
        }

        return dictionary
    }

    private func supplementaryLexiconEntriesSignature(
        fromEntries entries: [(userInput: String, candidate: String)]
    ) -> String {
        var aggregateHash: UInt64 = 1469598103934665603
        var entryCount = 0

        for entry in entries {
            let userInput = entry.userInput.trimmingCharacters(in: .whitespacesAndNewlines)
            let candidate = entry.candidate.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !candidate.isEmpty,
                candidate.count <= 64 else {
                continue
            }

            let pairHash = stableSupplementaryHash(userInput) ^ (stableSupplementaryHash(candidate) &* 1099511628211)
            aggregateHash ^= pairHash
            aggregateHash = aggregateHash &* 1099511628211
            entryCount += 1
        }

        return "\(entryCount):\(String(aggregateHash, radix: 16))"
    }

    private func stableSupplementaryHash(_ value: String) -> UInt64 {
        var hash: UInt64 = 1469598103934665603

        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }

        return hash
    }

    private func cachedSupplementaryLexiconIndex(signature: String) -> [String: [String]]? {
        guard let defaults = UserDefaults(suiteName: SharedDefaultsKeys.appGroupID),
            defaults.string(forKey: SharedDefaultsKeys.supplementaryLexiconIndexSignature) == signature,
            let dictionary = defaults.dictionary(forKey: SharedDefaultsKeys.supplementaryLexiconIndexCacheByReading)
                as? [String: [String]],
            !dictionary.isEmpty else {
            return nil
        }

        return dictionary
    }

    private func storeSupplementaryLexiconIndex(
        signature: String,
        dictionary: [String: [String]]
    ) {
        guard let defaults = UserDefaults(suiteName: SharedDefaultsKeys.appGroupID) else {
            return
        }

        defaults.set(signature, forKey: SharedDefaultsKeys.supplementaryLexiconIndexSignature)
        defaults.set(dictionary, forKey: SharedDefaultsKeys.supplementaryLexiconIndexCacheByReading)
    }

    private func refreshContactCandidatesIfNeeded(force: Bool) {
        guard Self.isSupplementaryExternalCandidatesEnabled else {
            contactCandidatesByReading = [:]
            supplementaryMergedCandidatesCacheByKey = [:]
            return
        }

        let displayMode = currentContactCandidateDisplayModeFromSharedDefaults()

        guard displayMode.usesContacts else {
            clearContactCandidatesIfNeeded(refreshKeyboardState: true)
            return
        }

        if !force,
            isRefreshingContactCandidates {
            return
        }

        if !force,
            let lastRefreshAt = contactCandidatesLastRefreshAt,
            Date().timeIntervalSince(lastRefreshAt) < 30 {
            return
        }

        isRefreshingContactCandidates = true
        loadCachedContactCandidatesInBackground { [weak self] cachedCandidates in
            guard let self else {
                return
            }

            let currentDisplayMode = self.currentContactCandidateDisplayModeFromSharedDefaults()

            guard currentDisplayMode.usesContacts else {
                self.clearContactCandidatesIfNeeded(refreshKeyboardState: true)
                return
            }

            if !cachedCandidates.isEmpty {
                self.isRefreshingContactCandidates = false
                self.contactCandidatesLastRefreshAt = Date()

                let previous = self.contactCandidatesByReading
                self.contactCandidatesByReading = cachedCandidates
                self.supplementaryMergedCandidatesCacheByKey = [:]

                if previous != cachedCandidates {
                    self.refreshKeyboardStateAsync()
                }
                return
            }

            let authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)

            switch authorizationStatus {
            case .authorized, .limited:
                self.loadContactCandidates(displayMode: currentDisplayMode)
            case .notDetermined:
                // Avoid permission prompts from extension process; app-side permission flow should handle this.
                self.clearContactCandidatesIfNeeded(refreshKeyboardState: true)
            case .denied, .restricted:
                self.clearContactCandidatesIfNeeded(refreshKeyboardState: true)
            @unknown default:
                self.clearContactCandidatesIfNeeded(refreshKeyboardState: true)
            }
        }
    }

    private func loadCachedContactCandidatesInBackground(
        completion: @escaping ([String: [String]]) -> Void
    ) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else {
                return
            }

            let cachedCandidates = self.limitContactCandidateDictionary(
                self.cachedContactCandidatesFromSharedDefaults()
            )

            DispatchQueue.main.async {
                completion(cachedCandidates)
            }
        }
    }

    private func cachedContactCandidatesFromSharedDefaults() -> [String: [String]] {
        guard let sharedDefaults = UserDefaults(suiteName: SharedDefaultsKeys.appGroupID),
            let dictionary = sharedDefaults.dictionary(forKey: SharedDefaultsKeys.contactCandidatesByReadingCache)
                as? [String: [String]] else {
            return [:]
        }

        return dictionary
    }

    private func clearContactCandidatesIfNeeded(refreshKeyboardState: Bool) {
        let hadContactCandidates = !contactCandidatesByReading.isEmpty
        isRefreshingContactCandidates = false
        contactCandidatesLastRefreshAt = Date()
        contactCandidatesByReading = [:]
        supplementaryMergedCandidatesCacheByKey = [:]

        if refreshKeyboardState,
            hadContactCandidates {
            refreshKeyboardStateAsync()
        }
    }

    private func loadContactCandidates(displayMode: ContactCandidateDisplayMode) {
        isRefreshingContactCandidates = true

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else {
                return
            }

            let store = CNContactStore()
            let request = CNContactFetchRequest(keysToFetch: [
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactMiddleNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactNicknameKey as CNKeyDescriptor,
                CNContactOrganizationNameKey as CNKeyDescriptor,
                CNContactPhoneticOrganizationNameKey as CNKeyDescriptor,
                CNContactPhoneticGivenNameKey as CNKeyDescriptor,
                CNContactPhoneticMiddleNameKey as CNKeyDescriptor,
                CNContactPhoneticFamilyNameKey as CNKeyDescriptor
            ])

            var dictionary: [String: [String]] = [:]
            var totalCandidateCount = 0
            var didReachLimit = false

            do {
                try store.enumerateContacts(with: request) { contact, stop in
                    self.appendContactCandidates(
                        from: contact,
                        displayMode: displayMode,
                        to: &dictionary,
                        totalCandidateCount: &totalCandidateCount
                    )

                    if self.hasReachedContactCandidateBuildLimit(
                        readingCount: dictionary.count,
                        totalCandidateCount: totalCandidateCount
                    ) {
                        didReachLimit = true
                        stop.pointee = true
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.clearContactCandidatesIfNeeded(refreshKeyboardState: true)
                }
                return
            }

            DispatchQueue.main.async {
                if self.view.window == nil {
                    self.clearContactCandidatesIfNeeded(refreshKeyboardState: false)
                    return
                }

                guard self.currentContactCandidateDisplayModeFromSharedDefaults() == displayMode else {
                    self.isRefreshingContactCandidates = false
                    self.refreshContactCandidatesIfNeeded(force: true)
                    return
                }

                self.isRefreshingContactCandidates = false
                self.contactCandidatesLastRefreshAt = Date()

                let previous = self.contactCandidatesByReading
                self.contactCandidatesByReading = dictionary
                self.supplementaryMergedCandidatesCacheByKey = [:]

                if didReachLimit {
                    self.updateKeyboardDiagnosticsHeartbeat(
                        event: "連絡先候補を上限で打ち切り readings=\(dictionary.count) entries=\(totalCandidateCount)",
                        appendLog: true
                    )
                }

                if previous != dictionary {
                    self.refreshKeyboardStateAsync()
                }
            }
        }
    }

    private func appendContactCandidates(
        from contact: CNContact,
        displayMode: ContactCandidateDisplayMode,
        to dictionary: inout [String: [String]],
        totalCandidateCount: inout Int
    ) {
        let familyName = contact.familyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let givenName = contact.givenName.trimmingCharacters(in: .whitespacesAndNewlines)
        let middleName = contact.middleName.trimmingCharacters(in: .whitespacesAndNewlines)
        let nickname = contact.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let organizationName = contact.organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phoneticOrganizationName = contact.phoneticOrganizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullName = [familyName, givenName, middleName].filter { !$0.isEmpty }.joined()

        let phoneticFamily = contact.phoneticFamilyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phoneticGiven = contact.phoneticGivenName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phoneticMiddle = contact.phoneticMiddleName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullNamePhonetic = [phoneticFamily, phoneticGiven, phoneticMiddle].joined()
        let includeFullNameForNameMatches = displayMode.includesFullNameForNameMatches

        let readingCandidates: [(String, [String])] = [
            (
                phoneticFamily,
                contactNameCandidates(
                    primaryName: familyName,
                    fullName: fullName,
                    includeFullName: includeFullNameForNameMatches
                )
            ),
            (
                phoneticGiven,
                contactNameCandidates(
                    primaryName: givenName,
                    fullName: fullName,
                    includeFullName: includeFullNameForNameMatches
                )
            ),
            (
                phoneticMiddle,
                contactNameCandidates(
                    primaryName: middleName,
                    fullName: fullName,
                    includeFullName: includeFullNameForNameMatches
                )
            ),
            (fullNamePhonetic, [fullName]),
            (
                familyName,
                contactNameCandidates(
                    primaryName: familyName,
                    fullName: fullName,
                    includeFullName: includeFullNameForNameMatches
                )
            ),
            (
                givenName,
                contactNameCandidates(
                    primaryName: givenName,
                    fullName: fullName,
                    includeFullName: includeFullNameForNameMatches
                )
            ),
            (
                middleName,
                contactNameCandidates(
                    primaryName: middleName,
                    fullName: fullName,
                    includeFullName: includeFullNameForNameMatches
                )
            ),
            (fullName, [fullName]),
            (nickname, [nickname])
        ]

        for (readingText, candidates) in readingCandidates {
            appendCandidates(
                candidates,
                forReadingText: readingText,
                to: &dictionary,
                totalCandidateCount: &totalCandidateCount
            )
        }

        if !organizationName.isEmpty {
            let organizationReadingKeys = companyReadingKeys(
                organizationName: organizationName,
                phoneticOrganizationName: phoneticOrganizationName
            )

            for readingKey in organizationReadingKeys {
                appendCandidates(
                    [organizationName],
                    forReadingText: readingKey,
                    to: &dictionary,
                    totalCandidateCount: &totalCandidateCount
                )
            }
        }
    }

    private func companyReadingKeys(
        organizationName: String,
        phoneticOrganizationName: String
    ) -> [String] {
        var keys: [String] = []
        var seen = Set<String>()

        func appendKey(_ reading: String) {
            let normalized = KanaTextNormalizer.normalizedReading(reading)

            guard !normalized.isEmpty,
                seen.insert(normalized).inserted else {
                return
            }

            keys.append(normalized)

            let trimmed = trimmingOrganizationPrefix(from: normalized)

            guard !trimmed.isEmpty,
                trimmed != normalized,
                seen.insert(trimmed).inserted else {
                return
            }

            keys.append(trimmed)
        }

        if shouldUseOrganizationNameReadingFallback(organizationName) {
            appendKey(organizationName)
        }
        appendKey(phoneticOrganizationName)

        return keys
    }

    private func shouldUseOrganizationNameReadingFallback(_ organizationName: String) -> Bool {
        let source = organizationName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !source.isEmpty else {
            return false
        }

        var hasKana = false

        for scalar in source.precomposedStringWithCanonicalMapping.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                continue
            }

            if scalar.value == 0x30FB || scalar.value == 0xFF65 {
                continue
            }

            let normalized = KanaTextNormalizer.normalizedReading(String(scalar))

            if !normalized.isEmpty {
                hasKana = true
                continue
            }

            return false
        }

        return hasKana
    }

    private func trimmingOrganizationPrefix(from normalizedReading: String) -> String {
        var reading = normalizedReading

        while true {
            var matched = false

            for prefix in Self.organizationPrefixReadingsToTrim where reading.hasPrefix(prefix) {
                reading = String(reading.dropFirst(prefix.count))
                matched = true
                break
            }

            guard matched else {
                return reading
            }
        }
    }

    private func contactNameCandidates(
        primaryName: String,
        fullName: String,
        includeFullName: Bool
    ) -> [String] {
        guard !primaryName.isEmpty else {
            return []
        }

        guard includeFullName,
            !fullName.isEmpty,
            fullName != primaryName else {
            return [primaryName]
        }

        return [primaryName, fullName]
    }

    private func appendCandidates(
        _ candidates: [String],
        forReadingText readingText: String,
        to dictionary: inout [String: [String]],
        totalCandidateCount: inout Int
    ) {
        let normalizedReading = KanaTextNormalizer.normalizedReading(readingText)

        guard !normalizedReading.isEmpty else {
            return
        }

        if dictionary[normalizedReading] == nil,
            dictionary.count >= Self.maximumContactCandidateReadings {
            return
        }

        guard totalCandidateCount < Self.maximumContactCandidateTotalEntries else {
            return
        }

        var existingCandidates = dictionary[normalizedReading] ?? []
        var existingCandidateSet = Set(existingCandidates)

        for candidate in candidates {
            if existingCandidates.count >= Self.maximumContactCandidatesPerReading
                || totalCandidateCount >= Self.maximumContactCandidateTotalEntries {
                break
            }

            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmed.isEmpty,
                existingCandidateSet.insert(trimmed).inserted else {
                continue
            }

            existingCandidates.append(trimmed)
            totalCandidateCount += 1
        }

        if !existingCandidates.isEmpty {
            dictionary[normalizedReading] = existingCandidates
        }
    }

    private func hasReachedContactCandidateBuildLimit(
        readingCount: Int,
        totalCandidateCount: Int
    ) -> Bool {
        readingCount >= Self.maximumContactCandidateReadings
            || totalCandidateCount >= Self.maximumContactCandidateTotalEntries
    }

    private func limitContactCandidateDictionary(
        _ source: [String: [String]]
    ) -> [String: [String]] {
        guard !source.isEmpty else {
            return [:]
        }

        var limited: [String: [String]] = [:]
        var totalCandidateCount = 0

        for (reading, candidates) in source {
            if hasReachedContactCandidateBuildLimit(
                readingCount: limited.count,
                totalCandidateCount: totalCandidateCount
            ) {
                break
            }

            appendCandidates(
                candidates,
                forReadingText: reading,
                to: &limited,
                totalCandidateCount: &totalCandidateCount
            )
        }

        return limited
    }

    private func supplementaryReadingKeys(userInput: String, candidate: String) -> [String] {
        var readingKeys: [String] = []

        let normalizedUserInput = KanaTextNormalizer.normalizedReading(userInput)
        if !normalizedUserInput.isEmpty {
            readingKeys.append(normalizedUserInput)
        }

        let tokenSource = userInput.replacingOccurrences(of: "・", with: " ")
        let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        let userInputTokens = tokenSource
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }

        for token in userInputTokens {
            let normalizedToken = KanaTextNormalizer.normalizedReading(token)

            if !normalizedToken.isEmpty {
                readingKeys.append(normalizedToken)
            }
        }

        let normalizedCandidate = KanaTextNormalizer.normalizedReading(candidate)
        if !normalizedCandidate.isEmpty {
            readingKeys.append(normalizedCandidate)
        }

        return readingKeys
    }

    private static func buildSupplementarySymbolCandidatesByReading(
        entries: [(String, [String])],
        allowedCandidates: Set<String>
    ) -> [String: [String]] {
        var dictionary: [String: [String]] = [:]

        for (reading, candidates) in entries {
            let normalizedReading = KanaTextNormalizer.normalizedReading(reading)

            guard !normalizedReading.isEmpty else {
                continue
            }

            var mergedCandidates = dictionary[normalizedReading] ?? []
            var seenCandidates = Set(mergedCandidates)

            for candidate in candidates {
                guard allowedCandidates.contains(candidate),
                    seenCandidates.insert(candidate).inserted else {
                    continue
                }

                mergedCandidates.append(candidate)
            }

            if !mergedCandidates.isEmpty {
                dictionary[normalizedReading] = mergedCandidates
            }
        }

        return dictionary
    }

    func supplementaryLexiconCandidates(for reading: String) -> [String] {
        guard Self.isSupplementaryExternalCandidatesEnabled else {
            return []
        }

        let normalizedReading = KanaTextNormalizer.normalizedReading(reading)

        guard !normalizedReading.isEmpty else {
            return []
        }

        let defaults = sharedDefaults
        let usesContacts = currentContactCandidateDisplayMode(from: defaults).usesContacts
        let usesUserDictionaryCandidates = currentUserDictionaryCandidateDisplayMode(from: defaults)
            .usesUserDictionaryCandidates
        let showsEmojiCandidates = currentEmojiCandidateDisplayEnabled(from: defaults)
        let showsKaomojiCandidates = currentKaomojiCandidateDisplayEnabled(from: defaults)

        let cacheKey = "\(normalizedReading)|c:\(usesContacts ? 1 : 0)|u:\(usesUserDictionaryCandidates ? 1 : 0)|e:\(showsEmojiCandidates ? 1 : 0)|k:\(showsKaomojiCandidates ? 1 : 0)"

        if let cachedCandidates = supplementaryMergedCandidatesCacheByKey[cacheKey] {
            return cachedCandidates
        }

        let contactCandidates: [String]

        if usesContacts {
            contactCandidates = contactCandidatesByReading[normalizedReading] ?? []
        } else {
            contactCandidates = []
        }

        let lexiconCandidates: [String]

        if usesUserDictionaryCandidates {
            lexiconCandidates = supplementaryLexiconCandidatesByReading[normalizedReading] ?? []
        } else {
            lexiconCandidates = []
        }

        let emojiCandidates: [String]

        if showsEmojiCandidates {
            emojiCandidates = Self.emojiReadingCandidatesByReading[normalizedReading] ?? []
        } else {
            emojiCandidates = []
        }

        let kaomojiCandidates: [String]

        if showsKaomojiCandidates {
            kaomojiCandidates = Self.kaomojiReadingCandidatesByReading[normalizedReading] ?? []
        } else {
            kaomojiCandidates = []
        }

        if contactCandidates.isEmpty,
            lexiconCandidates.isEmpty,
            emojiCandidates.isEmpty {
            supplementaryMergedCandidatesCacheByKey[cacheKey] = kaomojiCandidates

            if supplementaryMergedCandidatesCacheByKey.count > Self.maximumSupplementaryMergedCandidateCacheEntries {
                supplementaryMergedCandidatesCacheByKey.removeAll(keepingCapacity: true)
            }

            return kaomojiCandidates
        }

        var mergedCandidates: [String] = []
        var seenCandidates = Set<String>()

        for candidate in contactCandidates + lexiconCandidates + emojiCandidates + kaomojiCandidates {
            if seenCandidates.insert(candidate).inserted {
                mergedCandidates.append(candidate)
            }
        }

        supplementaryMergedCandidatesCacheByKey[cacheKey] = mergedCandidates

        if supplementaryMergedCandidatesCacheByKey.count > Self.maximumSupplementaryMergedCandidateCacheEntries {
            supplementaryMergedCandidatesCacheByKey.removeAll(keepingCapacity: true)
        }

        return mergedCandidates
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateKeyboardDiagnosticsHeartbeat(event: "viewDidAppear", appendLog: true)

        scheduleKeyboardBootstrapIfNeeded()

        guard lastRenderConfiguration != nil else {
            return
        }

        applyKeyboardBaseBackground()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        updateKeyboardDiagnosticsHeartbeat(event: "viewWillDisappear", appendLog: true)

        if let workItem = dictionaryPreloadWorkItem {
            workItem.cancel()
            dictionaryPreloadWorkItem = nil
            updateKeyboardDiagnosticsHeartbeat(
                event: "キーボード非表示のため辞書プリロード予約をキャンセル",
                appendLog: true
            )
        }

        performHiddenKeyboardMemoryTrim(
            reason: "viewWillDisappear",
            releaseHostingView: false,
            includeSystemCaches: memoryFailSafeProfile != .normal
        )
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        updateKeyboardDiagnosticsHeartbeat(event: "viewDidDisappear", appendLog: true)

        performHiddenKeyboardMemoryTrim(
            reason: "viewDidDisappear",
            releaseHostingView: true,
            includeSystemCaches: true
        )
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        updateKeyboardDiagnosticsHeartbeat(event: "メモリ警告受信 キャッシュ解放開始", appendLog: true)

        if memoryFailSafeProfile != .critical {
            memoryFailSafeProfile = .critical
            persistKeyboardDiagnosticsFailSafeProfile()
            appendKeyboardDiagnosticsLog(
                "メモリ警告を受けてフェイルセーフをcriticalへ昇格 rssMB=\(diagnosticsResidentMemoryMBText())",
                file: #fileID,
                line: #line,
                function: #function
            )
        }

        kanaKanjiConverter.clearAllCaches()

        if view.window == nil {
            performHiddenKeyboardMemoryTrim(
                reason: "memoryWarningHidden",
                releaseHostingView: true,
                includeSystemCaches: true
            )
        }

        updateKeyboardDiagnosticsHeartbeat(event: "メモリ警告受信 キャッシュ解放完了", appendLog: true)
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
        let sizeClassDidChange = previousTraitCollection?.verticalSizeClass != traitCollection.verticalSizeClass

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

    private func scheduleKeyboardBootstrapIfNeeded() {
        guard keyboardBootstrapWorkItem == nil else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            self.keyboardBootstrapWorkItem = nil

            guard !self.shouldSuppressHeavyOperations(reason: "keyboardBootstrap") else {
                return
            }

            if Self.isSupplementaryExternalCandidatesEnabled {
                self.refreshSupplementaryLexiconIfNeeded(force: true)
                self.refreshContactCandidatesIfNeeded(force: true)
            }
            self.requestSharedDataPrewarmIfNeeded()
            self.requestSystemDictionaryPreloadIfNeeded()
        }

        keyboardBootstrapWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    private func requestSharedDataPrewarmIfNeeded() {
        guard !shouldSuppressHeavyOperations(reason: "requestSharedDataPrewarmIfNeeded") else {
            return
        }

        sharedDataPrewarmWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            self.sharedDataPrewarmWorkItem = nil

            guard !self.shouldSuppressHeavyOperations(reason: "sharedDataPrewarm") else {
                return
            }

            let startedAt = CFAbsoluteTimeGetCurrent()
            self.kanaKanjiConverter.preloadSharedDataCachesIfNeeded()
            let elapsedMs = self.performanceElapsedMilliseconds(since: startedAt)

            if elapsedMs >= Self.renderConfigurationSlowThresholdMs {
                self.appendKeyboardDiagnosticsLog(
                    "共有データプリウォーム遅延 elapsedMs=\(elapsedMs)",
                    file: #fileID,
                    line: #line,
                    function: #function
                )
            }
        }

        sharedDataPrewarmWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func ensureKeyboardViewIfNeeded() {
        guard hostingController == nil else {
            return
        }

        setupKeyboardView()
        updateKeyboardDiagnosticsHeartbeat(event: "キーボードビューを再構築", appendLog: true)
    }

    func markTextProxyEdit() {
        lastTextProxyEditAt = CFAbsoluteTimeGetCurrent()
    }

    func shouldTreatAsExternalTextChange() -> Bool {
        let elapsed = CFAbsoluteTimeGetCurrent() - lastTextProxyEditAt
        return elapsed > externalTextChangeDetectionWindow
    }

    private func configureInputAssistantBar() {
        let assistant = inputAssistantItem
        assistant.leadingBarButtonGroups = []
        assistant.trailingBarButtonGroups = []
    }

    private func configureKeyboardContainerSizing() {
        inputView?.allowsSelfSizing = false

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

    private func keyboardInputModeName(_ mode: KeyboardInputMode) -> String {
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

    private func shouldPreloadSystemDictionaryAtLaunch() -> Bool {
#if targetEnvironment(simulator)
        true
#else
        ProcessInfo.processInfo.physicalMemory >= Self.minimumPhysicalMemoryForSystemDictionaryPreload
#endif
    }

    private func requestSystemDictionaryPreloadIfNeeded() {
        guard !shouldSuppressHeavyOperations(reason: "requestSystemDictionaryPreloadIfNeeded") else {
            return
        }

        updateMemoryFailSafeProfile(trigger: "requestSystemDictionaryPreloadIfNeeded")

        if let residentMemoryMB = currentResidentMemoryMB(),
            residentMemoryMB >= Self.maximumResidentMemoryMBForSystemDictionaryPreload {
            updateKeyboardDiagnosticsHeartbeat(
                event: "システム辞書プリロードを省略 rssMB=\(String(format: "%.1f", residentMemoryMB)) thresholdMB=\(String(format: "%.1f", Self.maximumResidentMemoryMBForSystemDictionaryPreload)) physicalMemoryGB=\(physicalMemoryGBText())",
                appendLog: true
            )
            return
        }

        guard shouldPreloadSystemDictionaryAtLaunch() else {
            updateKeyboardDiagnosticsHeartbeat(
                event: "システム辞書プリロードを省略 physicalMemoryGB=\(physicalMemoryGBText())",
                appendLog: true
            )
            return
        }

#if targetEnvironment(simulator)
        startSystemDictionaryPreload(trigger: "immediate")
#else
        let delay = Self.deviceSystemDictionaryPreloadDelay
        updateKeyboardDiagnosticsHeartbeat(
            event: "システム辞書プリロードを遅延予定 delaySec=\(String(format: "%.1f", delay)) physicalMemoryGB=\(physicalMemoryGBText())",
            appendLog: true
        )

        dictionaryPreloadWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.startSystemDictionaryPreload(trigger: "delayed")
        }
        dictionaryPreloadWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
#endif
    }

    private func startSystemDictionaryPreload(trigger: String) {
        let preloadStartedAt = CFAbsoluteTimeGetCurrent()
        updateKeyboardDiagnosticsHeartbeat(
            event: "システム辞書プリロード開始 trigger=\(trigger) physicalMemoryGB=\(physicalMemoryGBText())",
            appendLog: true
        )

        kanaKanjiConverter.preloadSystemDictionaryIfNeeded { [weak self] in
            guard let self else {
                return
            }

            guard !self.shouldSuppressHeavyOperations(reason: "systemDictionaryPreloadCompletion") else {
                return
            }

            self.updateMemoryFailSafeProfile(trigger: "systemDictionaryPreloadCompletion")

            let elapsedMs = max(0, Int((CFAbsoluteTimeGetCurrent() - preloadStartedAt) * 1000))
            self.refreshKeyboardStateAsync()
            self.updateKeyboardDiagnosticsHeartbeat(
                event: "システム辞書プリロード完了 trigger=\(trigger) elapsedMs=\(elapsedMs)",
                appendLog: true
            )
        }
    }

    private func physicalMemoryGBText() -> String {
        let physicalMemoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        return String(format: "%.1f", physicalMemoryGB)
    }

    private func diagnosticsProcessLabel() -> String {
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown.keyboard.bundle"
        let processName = ProcessInfo.processInfo.processName
        return "\(bundleID)(\(processName))"
    }

    private func diagnosticsProcessID() -> Int32 {
        getpid()
    }

    private func diagnosticsSessionOwnerToken() -> String {
        "\(diagnosticsProcessID()):\(diagnosticsControllerID)"
    }

    private func currentResidentMemoryBytes() -> UInt64? {
        var info = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<integer_t>.size
        )

        let result: kern_return_t = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), intPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }

        return UInt64(info.resident_size)
    }

    private func diagnosticsResidentMemoryMBText() -> String {
        guard let bytes = currentResidentMemoryBytes() else {
            return "unknown"
        }

        let mb = Double(bytes) / 1_048_576
        return String(format: "%.1f", mb)
    }

    private func currentResidentMemoryMB() -> Double? {
        guard let bytes = currentResidentMemoryBytes() else {
            return nil
        }

        return Double(bytes) / 1_048_576
    }

    private func shouldSuppressHeavyOperations(reason: String) -> Bool {
        guard let sharedDefaults,
            let activeOwnerToken = sharedDefaults.string(
                forKey: SharedDefaultsKeys.keyboardDiagnosticsSessionOwnerToken
            ),
            !activeOwnerToken.isEmpty else {
            didApplyInactiveSessionMitigation = false
            return false
        }

        let currentOwnerToken = diagnosticsSessionOwnerToken()

        guard activeOwnerToken != currentOwnerToken else {
            didApplyInactiveSessionMitigation = false
            return false
        }

        let now = CFAbsoluteTimeGetCurrent()

        if now - lastInactiveSessionSuppressionLogAt >= 1.0 {
            appendKeyboardDiagnosticsLog(
                "多重生存中の非アクティブインスタンスで重い更新を抑止 reason=\(reason) activeOwner=\(activeOwnerToken) currentOwner=\(currentOwnerToken)",
                file: #fileID,
                line: #line,
                function: #function
            )
            lastInactiveSessionSuppressionLogAt = now
        }

        if !didApplyInactiveSessionMitigation {
            performHiddenKeyboardMemoryTrim(
                reason: "inactiveSession-\(reason)",
                releaseHostingView: view.window == nil,
                includeSystemCaches: true
            )
            didApplyInactiveSessionMitigation = true
        }

        return true
    }

    private func performHiddenKeyboardMemoryTrim(
        reason: String,
        releaseHostingView: Bool,
        includeSystemCaches: Bool
    ) {
        pendingRefreshKeyboardStateRequests = 0
        isRefreshKeyboardStateAsyncScheduled = false
        activeConversion = nil
        clearComposingState()
        clearRecentKanaPlainCommitUpgradeContext()
        lastSynchronizedContextBeforeInput = ""

        keyboardHeightLockReleaseWorkItem?.cancel()
        keyboardHeightLockReleaseWorkItem = nil
        keyboardHeightLockValue = nil
        keyboardHeightLockReleaseTime = 0

        dictionaryPreloadWorkItem?.cancel()
        dictionaryPreloadWorkItem = nil

        keyboardBootstrapWorkItem?.cancel()
        keyboardBootstrapWorkItem = nil

        sharedDataPrewarmWorkItem?.cancel()
        sharedDataPrewarmWorkItem = nil

        clearSupplementaryLexiconCandidatesForMemoryTrim()
        clearContactCandidatesIfNeeded(refreshKeyboardState: false)

        if includeSystemCaches {
            kanaKanjiConverter.clearAllCaches()
        } else {
            kanaKanjiConverter.clearSharedDataCaches()
        }

        if releaseHostingView,
            let host = hostingController {
            host.willMove(toParent: nil)
            host.view.removeFromSuperview()
            host.removeFromParent()
            hostingController = nil
        }

        lastRenderConfiguration = nil

        updateKeyboardDiagnosticsHeartbeat(
            event: "キーボード非表示でメモリ解放 reason=\(reason) releaseView=\(releaseHostingView) clearSystem=\(includeSystemCaches) profile=\(memoryFailSafeProfile.rawValue)",
            appendLog: true
        )
    }

    private func updateMemoryFailSafeProfile(trigger: String) {
        guard let residentMemoryMB = currentResidentMemoryMB() else {
            return
        }

        let nextProfile = nextMemoryFailSafeProfile(for: residentMemoryMB)

        guard nextProfile != memoryFailSafeProfile else {
            return
        }

        let previousProfile = memoryFailSafeProfile
        memoryFailSafeProfile = nextProfile
        persistKeyboardDiagnosticsFailSafeProfile()

        appendKeyboardDiagnosticsLog(
            "メモリフェイルセーフ遷移 \(previousProfile.rawValue) -> \(nextProfile.rawValue) trigger=\(trigger) rssMB=\(String(format: "%.1f", residentMemoryMB))",
            file: #fileID,
            line: #line,
            function: #function
        )

        switch nextProfile {
        case .normal:
            break
        case .elevated:
            kanaKanjiConverter.clearSharedDataCaches()
        case .critical:
            kanaKanjiConverter.clearAllCaches()
        }

        if previousProfile == .critical,
            nextProfile != .critical {
            applyDeferredSharedSettingsCatchUpIfNeeded(trigger: trigger)
        }
    }

    private func applyDeferredSharedSettingsCatchUpIfNeeded(trigger: String) {
        guard hasDeferredSharedSettingsCatchUp,
            memoryFailSafeProfile != .critical else {
            return
        }

        guard view.window != nil || hostingController != nil else {
            return
        }

        hasDeferredSharedSettingsCatchUp = false

        appendKeyboardDiagnosticsLog(
            "critical中に保留した共有設定反映を再開 trigger=\(trigger) profile=\(memoryFailSafeProfile.rawValue)",
            file: #fileID,
            line: #line,
            function: #function
        )

        kanaKanjiConverter.clearSharedDataCaches()
        refreshContactCandidatesIfNeeded(force: true)
        refreshKeyboardStateAsync()
    }

    private func nextMemoryFailSafeProfile(for residentMemoryMB: Double) -> MemoryFailSafeProfile {
        let elevatedStart = Self.memoryFailSafeElevatedStartMB
        let criticalStart = Self.memoryFailSafeCriticalStartMB
        let recoverDelta = Self.memoryFailSafeRecoverDeltaMB

        switch memoryFailSafeProfile {
        case .normal:
            if residentMemoryMB >= criticalStart {
                return .critical
            }

            if residentMemoryMB >= elevatedStart {
                return .elevated
            }

            return .normal
        case .elevated:
            if residentMemoryMB >= criticalStart {
                return .critical
            }

            if residentMemoryMB < elevatedStart - recoverDelta {
                return .normal
            }

            return .elevated
        case .critical:
            if residentMemoryMB >= criticalStart - recoverDelta {
                return .critical
            }

            if residentMemoryMB >= elevatedStart - recoverDelta {
                return .elevated
            }

            return .normal
        }
    }

    func effectiveKanaPresentationCandidateLimit() -> Int {
        switch memoryFailSafeProfile {
        case .normal:
            return 24
        case .elevated:
            return 14
        case .critical:
            return 8
        }
    }

    func effectiveKanaConversionCandidateLimit() -> Int {
        switch memoryFailSafeProfile {
        case .normal:
            return 24
        case .elevated:
            return 14
        case .critical:
            return 8
        }
    }

    func effectiveLatinSuggestionLimit(defaultLimit: Int) -> Int {
        let normalizedLimit = max(0, defaultLimit)

        switch memoryFailSafeProfile {
        case .normal:
            return normalizedLimit
        case .elevated:
            return min(normalizedLimit, 18)
        case .critical:
            return 0
        }
    }

    private func effectiveShortcutVocabularyForRender() -> [String] {
        switch memoryFailSafeProfile {
        case .normal:
            return kanaKanjiStore.shortcutVocabulary()
        case .elevated:
            return Array(kanaKanjiStore.shortcutVocabulary().prefix(20))
        case .critical:
            return []
        }
    }

    private func diagnosticsRuntimeContext() -> String {
        "process=\(diagnosticsProcessLabel()) pid=\(diagnosticsProcessID()) controllerID=\(diagnosticsControllerID) rssMB=\(diagnosticsResidentMemoryMBText()) failSafe=\(memoryFailSafeProfile.rawValue)"
    }

    private func persistKeyboardDiagnosticsFailSafeProfile(in defaults: UserDefaults? = nil) {
        let targetDefaults = defaults ?? sharedDefaults
        targetDefaults?.set(
            memoryFailSafeProfile.rawValue,
            forKey: SharedDefaultsKeys.keyboardDiagnosticsFailSafeProfile
        )
    }

    private func diagnosticsLogLines(from defaults: UserDefaults) -> [String] {
        if let data = defaults.data(forKey: SharedDefaultsKeys.keyboardDiagnosticsLogLines),
            let decoded = try? JSONDecoder().decode([String].self, from: data) {
            return decoded
        }

        if let raw = defaults.array(forKey: SharedDefaultsKeys.keyboardDiagnosticsLogLines) {
            return raw.compactMap { $0 as? String }
        }

        return []
    }

    private func saveDiagnosticsLogLines(_ lines: [String], to defaults: UserDefaults) {
        if let encoded = try? JSONEncoder().encode(lines) {
            defaults.set(encoded, forKey: SharedDefaultsKeys.keyboardDiagnosticsLogLines)
            return
        }

        defaults.set(lines, forKey: SharedDefaultsKeys.keyboardDiagnosticsLogLines)
    }

    private func flightRecorderEvents(from defaults: UserDefaults) -> [DiagnosticsFlightRecorderEvent] {
        guard
            let data = defaults.data(forKey: SharedDefaultsKeys.keyboardDiagnosticsFlightRecorderEvents),
            let decoded = try? JSONDecoder().decode([DiagnosticsFlightRecorderEvent].self, from: data)
        else {
            return []
        }

        return decoded
    }

    private func saveFlightRecorderEvents(_ events: [DiagnosticsFlightRecorderEvent], to defaults: UserDefaults) {
        if let encoded = try? JSONEncoder().encode(events) {
            defaults.set(encoded, forKey: SharedDefaultsKeys.keyboardDiagnosticsFlightRecorderEvents)
            return
        }

        defaults.removeObject(forKey: SharedDefaultsKeys.keyboardDiagnosticsFlightRecorderEvents)
    }

    private func trimmedFlightRecorderEvents(
        _ events: [DiagnosticsFlightRecorderEvent],
        anchorTimestamp: TimeInterval
    ) -> [DiagnosticsFlightRecorderEvent] {
        let minimumTimestamp = anchorTimestamp - Self.diagnosticsFlightRecorderWindowSec
        var filtered = events.filter { $0.timestamp >= minimumTimestamp }

        if filtered.count > Self.diagnosticsFlightRecorderMaxEventCount {
            filtered.removeFirst(filtered.count - Self.diagnosticsFlightRecorderMaxEventCount)
        }

        return filtered
    }

    private func clearFlightRecorderEvents(in defaults: UserDefaults) {
        defaults.removeObject(forKey: SharedDefaultsKeys.keyboardDiagnosticsFlightRecorderEvents)
        diagnosticsFlightRecorderLastObservedAt.removeAll(keepingCapacity: true)
    }

    private func observeKeyboardDiagnosticsEvent(
        _ event: String,
        file: String = #fileID,
        line: Int = #line,
        function: String = #function,
        forceRecord: Bool = false
    ) {
        guard let sharedDefaults else {
            return
        }

        let now = Date().timeIntervalSince1970
        let sourceFile = (file as NSString).lastPathComponent
        let source = "\(sourceFile):\(line) \(function)"
        let dedupeKey = "\(event)|\(source)"

        if !forceRecord,
            let previous = diagnosticsFlightRecorderLastObservedAt[dedupeKey],
            now - previous < Self.diagnosticsFlightRecorderMinRecordIntervalSec {
            return
        }

        var events = flightRecorderEvents(from: sharedDefaults)
        events.append(
            DiagnosticsFlightRecorderEvent(
                timestamp: now,
                event: event,
                source: source
            )
        )

        let anchorTimestamp = events.last?.timestamp ?? now
        events = trimmedFlightRecorderEvents(events, anchorTimestamp: anchorTimestamp)
        saveFlightRecorderEvents(events, to: sharedDefaults)
        diagnosticsFlightRecorderLastObservedAt[dedupeKey] = now
    }

    private func flushFlightRecorderEventsIfPresent(reason: String) {
        guard let sharedDefaults else {
            return
        }

        let events = flightRecorderEvents(from: sharedDefaults)
        guard !events.isEmpty else {
            return
        }

        let anchorTimestamp = events.last?.timestamp ?? Date().timeIntervalSince1970
        let trimmed = trimmedFlightRecorderEvents(events, anchorTimestamp: anchorTimestamp)

        appendKeyboardDiagnosticsLog(
            "終了直前の高頻度イベントを退避 count=\(trimmed.count) windowSec=\(Int(Self.diagnosticsFlightRecorderWindowSec)) reason=\(reason)",
            file: #fileID,
            line: #line,
            function: #function
        )

        for item in trimmed {
            let timestampText = Self.diagnosticsTimestampFormatter.string(
                from: Date(timeIntervalSince1970: item.timestamp)
            )
            appendKeyboardDiagnosticsLog(
                "直前イベント \(timestampText) \(item.event) @ \(item.source)",
                file: #fileID,
                line: #line,
                function: #function
            )
        }

        clearFlightRecorderEvents(in: sharedDefaults)
    }

    private func keyboardDiagnosticsCurrentInstallMarker() -> String {
        let bundle = Bundle.main
        let bundleID = bundle.bundleIdentifier ?? "unknown.keyboard.bundle"
        let buildNumber = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "?"
        return "\(bundleID)|\(buildNumber)|build"
    }

    private func clearKeyboardDiagnosticsStorage(
        in defaults: UserDefaults,
        preservingInstallMarker installMarker: String
    ) {
        defaults.removeObject(forKey: SharedDefaultsKeys.keyboardDiagnosticsLogLines)
        defaults.removeObject(forKey: SharedDefaultsKeys.keyboardDiagnosticsFlightRecorderEvents)
        defaults.removeObject(forKey: SharedDefaultsKeys.keyboardDiagnosticsSessionActive)
        defaults.removeObject(forKey: SharedDefaultsKeys.keyboardDiagnosticsSessionOwnerToken)
        defaults.removeObject(forKey: SharedDefaultsKeys.keyboardDiagnosticsLastHeartbeat)
        defaults.removeObject(forKey: SharedDefaultsKeys.keyboardDiagnosticsLastEvent)
        defaults.removeObject(forKey: SharedDefaultsKeys.keyboardDiagnosticsLastSessionID)
        defaults.removeObject(forKey: SharedDefaultsKeys.keyboardDiagnosticsFailSafeProfile)
        defaults.set(installMarker, forKey: SharedDefaultsKeys.keyboardDiagnosticsInstallMarker)
    }

    private func resetKeyboardDiagnosticsIfInstallChanged() {
        guard let sharedDefaults else {
            return
        }

        let currentMarker = keyboardDiagnosticsCurrentInstallMarker()
        let previousMarker = sharedDefaults.string(forKey: SharedDefaultsKeys.keyboardDiagnosticsInstallMarker)

        guard previousMarker != currentMarker else {
            return
        }

        clearKeyboardDiagnosticsStorage(
            in: sharedDefaults,
            preservingInstallMarker: currentMarker
        )

        let previousMarkerDescription = previousMarker ?? "none"
        appendKeyboardDiagnosticsLog(
            "診断ログをインストール単位で初期化 previous=\(previousMarkerDescription) current=\(currentMarker)",
            file: #fileID,
            line: #line,
            function: #function
        )
    }

    private func appendKeyboardDiagnosticsLog(
        _ event: String,
        file: String = #fileID,
        line: Int = #line,
        function: String = #function
    ) {
        guard let sharedDefaults else {
            return
        }

        let sourceFile = (file as NSString).lastPathComponent
        let timestamp = Self.diagnosticsTimestampFormatter.string(from: Date())
        let entry =
            "\(timestamp) [\(diagnosticsSessionID)] \(event) {\(diagnosticsRuntimeContext())} (\(sourceFile):\(line) \(function))"

        var lines = diagnosticsLogLines(from: sharedDefaults)
        lines.append(entry)

        let maxLineCount = 320
        if lines.count > maxLineCount {
            lines.removeFirst(lines.count - maxLineCount)
        }

        saveDiagnosticsLogLines(lines, to: sharedDefaults)
        sharedDefaults.set(entry, forKey: SharedDefaultsKeys.keyboardDiagnosticsLastEvent)
        sharedDefaults.set(Date().timeIntervalSince1970, forKey: SharedDefaultsKeys.keyboardDiagnosticsLastHeartbeat)
        sharedDefaults.set(diagnosticsSessionID, forKey: SharedDefaultsKeys.keyboardDiagnosticsLastSessionID)
    }

    private func updateKeyboardDiagnosticsHeartbeat(
        event: String,
        file: String = #fileID,
        line: Int = #line,
        function: String = #function,
        appendLog: Bool = false
    ) {
        guard let sharedDefaults else {
            return
        }

        observeKeyboardDiagnosticsEvent(event, file: file, line: line, function: function)
        persistKeyboardDiagnosticsFailSafeProfile(in: sharedDefaults)

        let sourceFile = (file as NSString).lastPathComponent
        let summary = "\(event) [\(diagnosticsRuntimeContext())] @ \(sourceFile):\(line) \(function)"

        sharedDefaults.set(Date().timeIntervalSince1970, forKey: SharedDefaultsKeys.keyboardDiagnosticsLastHeartbeat)
        sharedDefaults.set(summary, forKey: SharedDefaultsKeys.keyboardDiagnosticsLastEvent)
        sharedDefaults.set(diagnosticsSessionID, forKey: SharedDefaultsKeys.keyboardDiagnosticsLastSessionID)

        if appendLog {
            appendKeyboardDiagnosticsLog(event, file: file, line: line, function: function)
        }
    }

    private func startKeyboardDiagnosticsSession() {
        resetKeyboardDiagnosticsIfInstallChanged()

        guard let sharedDefaults else {
            return
        }

        diagnosticsFlightRecorderLastObservedAt.removeAll(keepingCapacity: true)

        let previousSessionWasActive = sharedDefaults.bool(
            forKey: SharedDefaultsKeys.keyboardDiagnosticsSessionActive
        )
        let previousOwnerToken = sharedDefaults.string(
            forKey: SharedDefaultsKeys.keyboardDiagnosticsSessionOwnerToken
        ) ?? "unknown"

        if previousSessionWasActive {
            let previousSessionID = sharedDefaults.string(
                forKey: SharedDefaultsKeys.keyboardDiagnosticsLastSessionID
            ) ?? "unknown"
            let previousEvent = sharedDefaults.string(
                forKey: SharedDefaultsKeys.keyboardDiagnosticsLastEvent
            ) ?? "unknown"
            let previousHeartbeat = sharedDefaults.double(
                forKey: SharedDefaultsKeys.keyboardDiagnosticsLastHeartbeat
            )
            let elapsed: String = {
                guard previousHeartbeat > 0 else {
                    return "unknown"
                }

                let delta = max(0, Date().timeIntervalSince(Date(timeIntervalSince1970: previousHeartbeat)))
                return String(format: "%.1f", delta)
            }()

            let activeOwnerPrefix = "\(diagnosticsProcessID()):"
            let looksLikeControllerOverlap = previousOwnerToken.hasPrefix(activeOwnerPrefix)
                && previousOwnerToken != diagnosticsSessionOwnerToken()
            let reason = looksLikeControllerOverlap
                ? "前回セッション継続中の可能性(多重生存)"
                : "前回セッションが非正常終了の可能性"

            appendKeyboardDiagnosticsLog(
                "\(reason) session=\(previousSessionID) owner=\(previousOwnerToken) lastEvent=\(previousEvent) elapsedSec=\(elapsed)",
                file: #fileID,
                line: #line,
                function: #function
            )
            flushFlightRecorderEventsIfPresent(reason: reason)
        } else {
            clearFlightRecorderEvents(in: sharedDefaults)
        }

        diagnosticsSessionID = UUID().uuidString
        diagnosticsSessionStartedAt = Date()
        sharedDefaults.set(true, forKey: SharedDefaultsKeys.keyboardDiagnosticsSessionActive)
        sharedDefaults.set(
            diagnosticsSessionOwnerToken(),
            forKey: SharedDefaultsKeys.keyboardDiagnosticsSessionOwnerToken
        )
        sharedDefaults.set(diagnosticsSessionID, forKey: SharedDefaultsKeys.keyboardDiagnosticsLastSessionID)
        persistKeyboardDiagnosticsFailSafeProfile(in: sharedDefaults)
        appendKeyboardDiagnosticsLog(
            "キーボード拡張セッション開始",
            file: #fileID,
            line: #line,
            function: #function
        )
    }

    private func finishKeyboardDiagnosticsSession(
        reason: String,
        file: String = #fileID,
        line: Int = #line,
        function: String = #function
    ) {
        guard let sharedDefaults else {
            return
        }

        let elapsedSec = max(0, Date().timeIntervalSince(diagnosticsSessionStartedAt))

        appendKeyboardDiagnosticsLog(
            "キーボード拡張セッション終了 reason=\(reason) elapsedSec=\(String(format: "%.1f", elapsedSec))",
            file: file,
            line: line,
            function: function
        )

        let currentOwnerToken = diagnosticsSessionOwnerToken()
        let storedOwnerToken = sharedDefaults.string(
            forKey: SharedDefaultsKeys.keyboardDiagnosticsSessionOwnerToken
        )

        if storedOwnerToken == nil || storedOwnerToken == currentOwnerToken {
            sharedDefaults.set(false, forKey: SharedDefaultsKeys.keyboardDiagnosticsSessionActive)
            sharedDefaults.removeObject(forKey: SharedDefaultsKeys.keyboardDiagnosticsSessionOwnerToken)
            sharedDefaults.set(
                Date().timeIntervalSince1970,
                forKey: SharedDefaultsKeys.keyboardDiagnosticsLastHeartbeat
            )
            clearFlightRecorderEvents(in: sharedDefaults)
        } else {
            appendKeyboardDiagnosticsLog(
                "終了時owner不一致のためactive更新を見送り currentOwner=\(currentOwnerToken) storedOwner=\(storedOwnerToken ?? "none")",
                file: file,
                line: line,
                function: function
            )
        }
    }

    func appendKeyboardDiagnosticsLogFromInputHandling(_ event: String) {
        appendKeyboardDiagnosticsLog(event)
    }

    func performanceElapsedMilliseconds(since startedAt: CFAbsoluteTime) -> Int {
        max(0, Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000))
    }

    private func refreshKeyboardState(trigger: String = "direct") {
        guard !shouldSuppressHeavyOperations(reason: "refreshKeyboardState-\(trigger)") else {
            return
        }

        updateMemoryFailSafeProfile(trigger: "refreshKeyboardState-\(trigger)")

        let shouldRenderKeyboardView = view.window != nil || trigger == "viewWillAppear"

        if shouldRenderKeyboardView {
            ensureKeyboardViewIfNeeded()
        } else if hostingController == nil {
            return
        }

        let refreshStartedAt = CFAbsoluteTimeGetCurrent()
        let configurationStartedAt = CFAbsoluteTimeGetCurrent()
        let configuration = makeRenderConfiguration()
        let configurationElapsedMs = performanceElapsedMilliseconds(since: configurationStartedAt)

        applyKeyboardBaseBackground()
        installKeyboardHeightConstraintIfNeeded()
        updateKeyboardHeightIfNeeded(using: configuration)

        guard configuration != lastRenderConfiguration else {
            let refreshElapsedMs = performanceElapsedMilliseconds(since: refreshStartedAt)

            if configurationElapsedMs >= Self.renderConfigurationSlowThresholdMs
                || refreshElapsedMs >= Self.refreshKeyboardStateSlowThresholdMs {
                appendKeyboardDiagnosticsLog(
                    "refreshKeyboardState遅延 trigger=\(trigger) elapsedMs=\(refreshElapsedMs) configMs=\(configurationElapsedMs) changed=false pending=\(pendingRefreshKeyboardStateRequests)",
                    file: #fileID,
                    line: #line,
                    function: #function
                )
            }

            return
        }

        lastRenderConfiguration = configuration
        UIView.performWithoutAnimation {
            hostingController?.rootView = makeRootView(from: configuration)
            hostingController?.view.layoutIfNeeded()
        }

        let refreshElapsedMs = performanceElapsedMilliseconds(since: refreshStartedAt)

        if configurationElapsedMs >= Self.renderConfigurationSlowThresholdMs
            || refreshElapsedMs >= Self.refreshKeyboardStateSlowThresholdMs {
            appendKeyboardDiagnosticsLog(
                "refreshKeyboardState遅延 trigger=\(trigger) elapsedMs=\(refreshElapsedMs) configMs=\(configurationElapsedMs) changed=true pending=\(pendingRefreshKeyboardStateRequests)",
                file: #fileID,
                line: #line,
                function: #function
            )
        }
    }

    func refreshKeyboardStateAsync() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.refreshKeyboardStateAsync()
            }
            return
        }

        guard !shouldSuppressHeavyOperations(reason: "refreshKeyboardStateAsync-enqueue") else {
            return
        }

        updateMemoryFailSafeProfile(trigger: "refreshKeyboardStateAsync-enqueue")

        if view.window == nil,
            hostingController == nil {
            return
        }

        pendingRefreshKeyboardStateRequests += 1
        let queuedDepth = pendingRefreshKeyboardStateRequests
        let enqueuedAt = CFAbsoluteTimeGetCurrent()

        if memoryFailSafeProfile == .critical,
            queuedDepth >= Self.refreshQueueDropThresholdInCriticalMode {
            pendingRefreshKeyboardStateRequests = max(0, pendingRefreshKeyboardStateRequests - 1)

            appendKeyboardDiagnosticsLog(
                "criticalフェイルセーフでrefreshKeyboardStateAsyncを間引き queueDepth=\(queuedDepth)",
                file: #fileID,
                line: #line,
                function: #function
            )
            return
        }

        if queuedDepth >= Self.refreshQueueBacklogLogThreshold {
            appendKeyboardDiagnosticsLog(
                "refreshKeyboardStateAsync滞留 queueDepth=\(queuedDepth)",
                file: #fileID,
                line: #line,
                function: #function
            )
        }

        if isRefreshKeyboardStateAsyncScheduled {
            return
        }

        scheduleRefreshKeyboardStateAsyncExecution(
            enqueuedAt: enqueuedAt,
            queuedDepthAtEnqueue: queuedDepth
        )
    }

    func refreshKeyboardStateForUserInitiatedAction(_ reason: UserInitiatedRefreshReason) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.refreshKeyboardStateForUserInitiatedAction(reason)
            }
            return
        }

        let trigger = "refreshKeyboardStateImmediate-\(reason.rawValue)"

        guard !shouldSuppressHeavyOperations(reason: trigger) else {
            return
        }

        updateMemoryFailSafeProfile(trigger: trigger)
        refreshKeyboardState(trigger: "immediate-\(reason.rawValue)")
    }

    private func scheduleRefreshKeyboardStateAsyncExecution(
        enqueuedAt: CFAbsoluteTime,
        queuedDepthAtEnqueue: Int
    ) {
        guard !isRefreshKeyboardStateAsyncScheduled else {
            return
        }

        isRefreshKeyboardStateAsyncScheduled = true

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.pendingRefreshKeyboardStateRequests = max(0, self.pendingRefreshKeyboardStateRequests - 1)

            guard !self.shouldSuppressHeavyOperations(reason: "refreshKeyboardStateAsync-execute") else {
                self.pendingRefreshKeyboardStateRequests = 0
                self.isRefreshKeyboardStateAsyncScheduled = false
                return
            }

            self.updateMemoryFailSafeProfile(trigger: "refreshKeyboardStateAsync-execute")

            let queueWaitMs = self.performanceElapsedMilliseconds(since: enqueuedAt)

            if queueWaitMs >= Self.refreshQueueWaitSlowThresholdMs
                || queuedDepthAtEnqueue >= Self.refreshQueueBacklogLogThreshold {
                self.appendKeyboardDiagnosticsLog(
                    "refreshKeyboardStateAsync実行 waitMs=\(queueWaitMs) queueDepthAtEnqueue=\(queuedDepthAtEnqueue) pendingNow=\(self.pendingRefreshKeyboardStateRequests)",
                    file: #fileID,
                    line: #line,
                    function: #function
                )
            }

            self.refreshKeyboardState(trigger: "async")
            self.isRefreshKeyboardStateAsyncScheduled = false

            if self.pendingRefreshKeyboardStateRequests > 0 {
                self.scheduleRefreshKeyboardStateAsyncExecution(
                    enqueuedAt: CFAbsoluteTimeGetCurrent(),
                    queuedDepthAtEnqueue: self.pendingRefreshKeyboardStateRequests
                )
            }
        }
    }

    private func handleSharedSettingsDidChange() {
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
            self.kanaKanjiConverter.clearSharedDataCaches()

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
            // 5x2(上段数字+かな2段+下段アクション)は実質4段なのでcompactActionRowと同等に合わせる。
            return 50
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
            // Header + top number row + 2 kana rows + action row + internal row spacing + padding.
            return headerHeight
                + rowSpacing
                + Self.mainKeyRowHeight * 3
                + Self.actionRowHeight
                + rowSpacing * 3
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

    private func currentContactCandidateDisplayMode(from defaults: UserDefaults?) -> ContactCandidateDisplayMode {
        let rawValue = sharedStringValue(
            from: defaults,
            key: SharedDefaultsKeys.contactCandidateDisplayMode,
            fallback: ContactCandidateDisplayMode.namesOnly.rawValue
        )

        return ContactCandidateDisplayMode(rawValue: rawValue) ?? .namesOnly
    }

    private func currentUserDictionaryCandidateDisplayMode(
        from defaults: UserDefaults?
    ) -> UserDictionaryCandidateDisplayMode {
        let rawValue = sharedStringValue(
            from: defaults,
            key: SharedDefaultsKeys.userDictionaryCandidateDisplayMode,
            fallback: UserDictionaryCandidateDisplayMode.on.rawValue
        )

        return UserDictionaryCandidateDisplayMode(rawValue: rawValue) ?? .on
    }

    private func currentEmojiCandidateDisplayEnabled(from defaults: UserDefaults?) -> Bool {
        sharedBoolValue(
            from: defaults,
            key: SharedDefaultsKeys.emojiCandidateDisplayEnabled,
            fallback: true
        )
    }

    private func currentKaomojiCandidateDisplayEnabled(from defaults: UserDefaults?) -> Bool {
        sharedBoolValue(
            from: defaults,
            key: SharedDefaultsKeys.kaomojiCandidateDisplayEnabled,
            fallback: true
        )
    }

    private func currentDelimiterAutoCommitCandidateIndex(from defaults: UserDefaults?) -> Int {
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

    private func currentTemperatureUnit() -> TemperatureUnitPreference {
        if let rawValue = UserDefaults.standard.string(forKey: "AppleTemperatureUnit"),
            let unit = TemperatureUnitPreference.fromAppleTemperatureUnit(rawValue) {
            return unit
        }

        return Locale.autoupdatingCurrent.measurementSystem == .us ? .fahrenheit : .celsius
    }

    private func makeRenderConfiguration() -> RenderConfiguration {
        updateMemoryFailSafeProfile(trigger: "makeRenderConfiguration")

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
        let modifierFlickGuideDisplayMode: FlickGuideDisplayMode

        if sharedDefaults?.object(forKey: SharedDefaultsKeys.modifierFlickGuideDisplayMode) != nil {
            modifierFlickGuideDisplayMode = sharedFlickGuideDisplayModeValue(
                from: sharedDefaults,
                key: SharedDefaultsKeys.modifierFlickGuideDisplayMode
            )
        } else {
            modifierFlickGuideDisplayMode = kanaFlickGuideDisplayMode
        }
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
        let landscapeLatinSuggestionModeRawValue = sharedStringValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.landscapeLatinSuggestionMode,
            fallback: "sidebar"
        )
        let latinSuggestionQuery = currentLatinSuggestionQueryFromTextContext()
        let latinSuggestions = currentLatinSuggestions()

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
            modifierFlickGuideDisplayMode: modifierFlickGuideDisplayMode,
            keyRepeatInitialDelay: keyRepeatInitialDelay,
            keyRepeatInterval: keyRepeatInterval,
            kanaModeSwitcherTapActionRawValue: kanaModeSwitcherTapActionRawValue,
            kanaModeSwitcherRightFlickActionRawValue: kanaModeSwitcherRightFlickActionRawValue,
            kanaModeSwitcherUpFlickActionRawValue: kanaModeSwitcherUpFlickActionRawValue,
            landscapeCandidateSideRawValue: landscapeCandidateSideRawValue,
            landscapeNumberPaneSideRawValue: landscapeNumberPaneSideRawValue,
            landscapeLatinSuggestionModeRawValue: landscapeLatinSuggestionModeRawValue,
            showsNextKeyboardKey: needsInputModeSwitchKey,
            shortcutVocabulary: effectiveShortcutVocabularyForRender(),
            composingText: candidatePresentation.composingText,
            conversionCandidates: candidatePresentation.candidates,
            selectedConversionCandidateIndex: candidatePresentation.selectedIndex,
            latinSuggestionQuery: latinSuggestionQuery,
            latinSuggestions: latinSuggestions,
            showsParenthesesWrapper: hasParenthesesWrapper
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
            onCommitComposingTextAsKatakana: { [weak self] in
                self?.handleCommitComposingTextAsKatakana()
            },
            onUpgradeRecentKanaCommitToKatakana: { [weak self] in
                guard let self else {
                    return false
                }

                let upgraded = self.upgradeRecentKanaCommitToKatakana()

                if upgraded {
                    self.refreshKeyboardStateAsync()
                }

                return upgraded
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
                self.updateKeyboardDiagnosticsHeartbeat(
                    event: "入力モード変更 \(self.keyboardInputModeName(previousMode)) -> \(self.keyboardInputModeName(mode))",
                    appendLog: true
                )

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
            modifierFlickGuideDisplayMode: configuration.modifierFlickGuideDisplayMode,
            keyRepeatInitialDelay: configuration.keyRepeatInitialDelay,
            keyRepeatInterval: configuration.keyRepeatInterval,
            kanaModeSwitcherTapActionRawValue: configuration.kanaModeSwitcherTapActionRawValue,
            kanaModeSwitcherRightFlickActionRawValue: configuration.kanaModeSwitcherRightFlickActionRawValue,
            kanaModeSwitcherUpFlickActionRawValue: configuration.kanaModeSwitcherUpFlickActionRawValue,
            landscapeCandidateSideRawValue: configuration.landscapeCandidateSideRawValue,
            landscapeNumberPaneSideRawValue: configuration.landscapeNumberPaneSideRawValue,
            landscapeLatinSuggestionModeRawValue: configuration.landscapeLatinSuggestionModeRawValue,
            shortcutVocabulary: configuration.shortcutVocabulary,
            composingText: configuration.composingText,
            conversionCandidates: configuration.conversionCandidates,
            selectedConversionCandidateIndex: configuration.selectedConversionCandidateIndex,
            latinSuggestionQuery: configuration.latinSuggestionQuery,
            latinSuggestions: configuration.latinSuggestions,
            showsParenthesesWrapper: configuration.showsParenthesesWrapper,
            initialSpaceToastText: "écritu"
        )
    }

    func currentKanaKanjiCandidateSourceModeFromSharedDefaults() -> KanaKanjiCandidateSourceMode {
        currentKanaKanjiCandidateSourceMode(
            from: sharedDefaults
        )
    }

    private func currentUserDictionaryCandidateDisplayModeFromSharedDefaults() -> UserDictionaryCandidateDisplayMode {
        currentUserDictionaryCandidateDisplayMode(
            from: sharedDefaults
        )
    }

    private func currentContactCandidateDisplayModeFromSharedDefaults() -> ContactCandidateDisplayMode {
        currentContactCandidateDisplayMode(
            from: sharedDefaults
        )
    }

    private func currentEmojiCandidateDisplayEnabledFromSharedDefaults() -> Bool {
        currentEmojiCandidateDisplayEnabled(
            from: sharedDefaults
        )
    }

    private func currentKaomojiCandidateDisplayEnabledFromSharedDefaults() -> Bool {
        currentKaomojiCandidateDisplayEnabled(
            from: sharedDefaults
        )
    }

    func currentDelimiterAutoCommitCandidateIndexFromSharedDefaults() -> Int {
        currentDelimiterAutoCommitCandidateIndex(
            from: sharedDefaults
        )
    }

    func latinSuggestions(prefix: String, limit: Int) -> [String] {
        kanaKanjiStore.latinSuggestions(prefix: prefix, limit: limit)
    }
}
