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
    static let isSupplementaryExternalCandidatesEnabled = true
    static let organizationPrefixReadingsToTrim: [String] = [
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
    static let emojiReadingCandidatesByReading: [String: [String]] = {
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
    static let kaomojiReadingCandidatesByReading: [String: [String]] = {
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
    var hostingController: UIHostingController<KeyboardRootView>?
    var lastRenderConfiguration: RenderConfiguration?
    var keyboardHeightConstraint: NSLayoutConstraint?
    var keyboardMaxHeightConstraint: NSLayoutConstraint?
    weak var keyboardSizingView: UIView?
    var cachedPortraitSafeAreaBottomInset: CGFloat?
    var isObservingSettingsDidChange = false
    var keyboardHeightLockValue: CGFloat?
    var keyboardHeightLockReleaseTime: CFAbsoluteTime = 0
    var keyboardHeightLockReleaseWorkItem: DispatchWorkItem?
    var dictionaryPreloadWorkItem: DispatchWorkItem?
    var keyboardBootstrapWorkItem: DispatchWorkItem?
    var sharedDataPrewarmWorkItem: DispatchWorkItem?
    var supplementaryLexiconCandidatesByReading: [String: [String]] = [:]
    var supplementaryMergedCandidatesCacheByKey: [String: [String]] = [:]
    var contactCandidatesByReading: [String: [String]] = [:]
    var isRefreshingSupplementaryLexicon = false
    var supplementaryLexiconLastRefreshAt: Date?
    var isRefreshingContactCandidates = false
    var contactCandidatesLastRefreshAt: Date?
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
    var lastSynchronizedContextBeforeInputTail = ""
    var lastSynchronizedContextBeforeInputLength = 0
    var composingContextPrefixTail = ""
    var pendingHostCallbackUnderlineClearNudgeWidth: Int?
    var pendingHostCallbackUnderlineClearDeadline: CFAbsoluteTime = 0
    var cachedContextBeforeInput: String?
    var cachedContextAfterInput: String?
    var kanaKanjiStore: KanaKanjiStore { Self.sharedKanaKanjiStore }
    var kanaKanjiConverter: KanaKanjiConverter { Self.sharedKanaKanjiConverter }
    lazy var sharedDefaults = UserDefaults(suiteName: SharedDefaultsKeys.appGroupID)
    var diagnosticsSessionID = UUID().uuidString
    var diagnosticsSessionStartedAt = Date()
    let diagnosticsControllerID = UUID().uuidString
    var pendingRefreshKeyboardStateRequests = 0
    var isRefreshKeyboardStateAsyncScheduled = false
    var candidateGenerationCounter: UInt64 = 0
    var settledCandidatePresentation: CandidatePresentation?
    var settledCandidatePresentationKey: CandidatePresentationCacheKey?
    let candidateGenerationQueue = DispatchQueue(
        label: "com.kusakabe.ecritu.candidate-generation",
        qos: .userInitiated
    )
    var markedTextWatchdogTimer: DispatchSourceTimer?
    var lastMarkedTextUpdateAt: CFAbsoluteTime = 0
    static let markedTextWatchdogInterval: TimeInterval = 1.5
    static let markedTextWatchdogQuietPeriod: TimeInterval = 1.0
    static let markedTextWatchdogQueue = DispatchQueue(
        label: "com.kusakabe.ecritu.marked-text-watchdog",
        qos: .utility
    )

    struct CandidatePresentationCacheKey: Equatable {
        let reading: String
        let composingRawText: String
        let modeRawValue: String
    }
    var diagnosticsFlightRecorderLastObservedAt: [String: TimeInterval] = [:]
    var memoryFailSafeProfile: MemoryFailSafeProfile = .normal
    var hasDeferredSharedSettingsCatchUp = false
    var lastInactiveSessionSuppressionLogAt: CFAbsoluteTime = 0
    var didApplyInactiveSessionMitigation = false

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

    enum TextContextLimits {
        static let synchronizedContextTailLength = 192
        static let latinSuggestionScanTailLength = 192
        // documentContextBeforeInput/AfterInput を XPC から取得した直後にこの長さで
        // 切り詰めてキャッシュに保持。Facebook 等の長文投稿で host 側コンテキストが
        // 数十KBになっても downstream の String 操作と保持メモリを定数化する。
        static let cachedContextBeforeInputMaxLength = 512
        static let cachedContextAfterInputMaxLength = 512
    }

    enum SharedDefaultsKeys {
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
        static let kanaPostModifierEmptyTapAction = "kanaPostModifierEmptyTapAction"
        static let kanaPostModifierEmptyTapKaomojiCategory = "kanaPostModifierEmptyTapKaomojiCategory"
        static let kanaPostModifierEmptyTapEmojiCategory = "kanaPostModifierEmptyTapEmojiCategory"
        static let kanaPostModifierEmptyTapSymbolCategory = "kanaPostModifierEmptyTapSymbolCategory"
        static let kanaPostModifierFlickDakutenEnabled = "kanaPostModifierFlickDakutenEnabled"
        static let delimiterAutoCommitCandidate = "delimiterAutoCommitCandidate"
        static let landscapeCandidateSide = "landscapeCandidateSide"
        static let landscapeNumberPaneSide = "landscapeNumberPaneSide"
        static let landscapeLatinSuggestionMode = "landscapeLatinSuggestionMode"
        static let kanaKanjiCandidateSourceMode = "kanaKanjiCandidateSourceMode"
        static let historicalKanaCandidatesEnabled = "historicalKanaCandidatesEnabled"
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

    static let settingsDidChangeDarwinCallback: CFNotificationCallback = {
        _, observer, _, _, _ in
        guard let observer else {
            return
        }

        let controller = Unmanaged<KeyboardViewController>
            .fromOpaque(observer)
            .takeUnretainedValue()
        controller.handleSharedSettingsDidChange()
    }

    static let diagnosticsTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let hostTopOverlap: CGFloat = 0
    static let baselinePortraitScreenWidth: CGFloat = 390
    static let baselineLandscapeScreenHeight: CGFloat = 393
    static let candidateHeaderExpandedHeight: CGFloat = 35
    static let candidateHeaderCollapsedHeight: CGFloat = 3
    static let keyboardVerticalPadding: CGFloat = 23
    static let keyboardRowSpacing: CGFloat = 6
    static let mainKeyRowHeight: CGFloat = 46
    static let actionRowHeight: CGFloat = 42
    static let minimumKanaThreeByThreeHeight: CGFloat = 220
    static let maximumKanaThreeByThreeHeight: CGFloat = 280
    static let minimumCompactGridHeight: CGFloat = 194
    static let maximumCompactGridHeight: CGFloat = 252
    static let minimumCompactActionRowHeight: CGFloat = 200
    static let maximumCompactActionRowHeight: CGFloat = 260
    static let minimumKanaFiveByTwoHeight: CGFloat = 216
    static let maximumKanaFiveByTwoHeight: CGFloat = 280
    static let minimumEmojiHeight: CGFloat = 228
    static let maximumEmojiHeight: CGFloat = 290
    static let portraitSystemAccessoryOffset: CGFloat = 6
    static let keyboardSwitchHeightLockDuration: TimeInterval = 0.45
    private static let deviceSystemDictionaryPreloadDelay: TimeInterval = 1.2
    private static let minimumPhysicalMemoryForSystemDictionaryPreload: UInt64 = 5 * 1024 * 1024 * 1024
    private static let maximumResidentMemoryMBForSystemDictionaryPreload: Double = 95
    private static let refreshQueueBacklogLogThreshold = 6
    private static let refreshQueueWaitSlowThresholdMs = 60
    private static let renderConfigurationSlowThresholdMs = 16
    private static let refreshKeyboardStateSlowThresholdMs = 28
    static let maximumContactCandidateReadings = 4096
    static let maximumContactCandidateTotalEntries = 16384
    static let maximumContactCandidatesPerReading = 48
    static let maximumSupplementaryMergedCandidateCacheEntries = 512
    static let memoryFailSafeElevatedStartMB: Double = 120
    static let memoryFailSafeCriticalStartMB: Double = 150
    static let memoryFailSafeRecoverDeltaMB: Double = 14
    private static let refreshQueueDropThresholdInCriticalMode = 2
    static let diagnosticsFlightRecorderWindowSec: TimeInterval = 6
    static let diagnosticsFlightRecorderMaxEventCount = 120
    static let diagnosticsFlightRecorderMinRecordIntervalSec: TimeInterval = 0.12
    private static let baseKeyboardBackgroundColor = UIColor { trait in
        if trait.userInterfaceStyle == .dark {
            return UIColor(red: 0.12, green: 0.14, blue: 0.18, alpha: 1.0)
        }

        return UIColor(red: 0.89, green: 0.90, blue: 0.92, alpha: 1.0)
    }

    enum PortraitHeightProfile {
        case kanaThreeByThree
        case compactGrid
        case compactActionRow
        case kanaFiveByTwo
        case emoji
    }

    struct RenderConfiguration: Equatable {
        let directionProfile: FlickDirectionProfile
        let kanaLayoutMode: KanaLayoutMode
        let kanaModifierPlacementMode: KanaModifierPlacementMode
        let kanaPostModifierButtonState: KanaPostModifierButtonState
        let numberLayoutMode: NumberLayoutMode
        let latinLayoutMode: LatinLayoutMode
        let accentPaletteRawValue: String
        let isSystemDictionaryFallback: Bool
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
        let kanaPostModifierEmptyTapActionRawValue: String
        let kanaPostModifierEmptyTapKaomojiCategoryID: String
        let kanaPostModifierEmptyTapEmojiCategoryID: String
        let kanaPostModifierEmptyTapSymbolCategoryID: String
        let kanaPostModifierFlickDakutenEnabled: Bool
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

    struct DiagnosticsFlightRecorderEvent: Codable {
        let timestamp: TimeInterval
        let event: String
        let source: String
    }

    enum MemoryFailSafeProfile: String {
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
        applyConverterFeatureFlagsFromSharedDefaults()
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

        // textDidChange は host 側のテキストが変化した(送信/autocorrect/paste/選択など
        // 何らかの理由で)シグナルなので、自前/外部を問わずキャッシュを必ず無効化する。
        // 「自前操作なら skip」の最適化は send 時に stale context で nudge 計算が
        // 狂って iMessage 等で下線残留を招くため採用しない。
        invalidateTextContextCache()

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

        invalidateTextContextCache()

        synchronizeConversionContextIfNeeded(
            triggeredByExternalChange: shouldTreatAsExternalTextChange()
        )
        consumePendingHostCallbackUnderlineClearPassIfNeeded(trigger: "selectionDidChange")
        refreshKeyboardState(trigger: "selectionDidChange")
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

        stopMarkedTextWatchdog()

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
        invalidateTextContextCache()
    }

    // setMarkedText のように beforeInput/afterInput を変えない自前編集に使う。
    // タイムスタンプだけ更新してキャッシュ無効化を回避する(XPC 再取得を削減)。
    func noteOwnTextProxyEditTimestamp() {
        lastTextProxyEditAt = CFAbsoluteTimeGetCurrent()
    }

    // 自前で insertText を発行した直後にキャッシュ末尾を更新して XPC 再取得を回避する。
    func applyCachedContextInsertion(_ text: String) {
        guard !text.isEmpty,
            var cached = cachedContextBeforeInput else {
            return
        }

        cached.append(text)

        if cached.count > TextContextLimits.cachedContextBeforeInputMaxLength {
            cached = String(cached.suffix(TextContextLimits.cachedContextBeforeInputMaxLength))
        }

        cachedContextBeforeInput = cached
    }

    // 自前で deleteBackward を発行した直後にキャッシュ末尾を縮めて XPC 再取得を回避する。
    func applyCachedContextDeletion(count: Int = 1) {
        guard count > 0,
            var cached = cachedContextBeforeInput,
            !cached.isEmpty else {
            return
        }

        let removeCount = min(count, cached.count)
        cached = String(cached.dropLast(removeCount))
        cachedContextBeforeInput = cached
    }

    func invalidateTextContextCache() {
        cachedContextBeforeInput = nil
        cachedContextAfterInput = nil
    }

    func currentTextContextSnapshot() -> (beforeInput: String, afterInput: String) {
        if let cachedContextBeforeInput,
            let cachedContextAfterInput {
            return (cachedContextBeforeInput, cachedContextAfterInput)
        }

        let rawBefore = textDocumentProxy.documentContextBeforeInput ?? ""
        let rawAfter = textDocumentProxy.documentContextAfterInput ?? ""

        let beforeInput: String
        if rawBefore.count > TextContextLimits.cachedContextBeforeInputMaxLength {
            beforeInput = String(rawBefore.suffix(TextContextLimits.cachedContextBeforeInputMaxLength))
        } else {
            beforeInput = rawBefore
        }

        let afterInput: String
        if rawAfter.count > TextContextLimits.cachedContextAfterInputMaxLength {
            afterInput = String(rawAfter.prefix(TextContextLimits.cachedContextAfterInputMaxLength))
        } else {
            afterInput = rawAfter
        }

        cachedContextBeforeInput = beforeInput
        cachedContextAfterInput = afterInput
        return (beforeInput, afterInput)
    }

    func currentTextContextBeforeInput() -> String {
        currentTextContextSnapshot().beforeInput
    }

    func currentTextContextAfterInput() -> String {
        currentTextContextSnapshot().afterInput
    }

    func currentTextContextBeforeInputTail(maxLength: Int) -> String {
        guard maxLength > 0 else {
            return ""
        }

        let beforeInput = currentTextContextBeforeInput()

        if beforeInput.count <= maxLength {
            return beforeInput
        }

        return String(beforeInput.suffix(maxLength))
    }

    func context(_ context: String, hasSuffix expectedSuffix: String) -> Bool {
        guard !expectedSuffix.isEmpty else {
            return true
        }

        guard context.count >= expectedSuffix.count else {
            return false
        }

        return String(context.suffix(expectedSuffix.count)) == expectedSuffix
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

    func refreshKeyboardState(trigger: String = "direct") {
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

    private func makeRenderConfiguration() -> RenderConfiguration {
        updateMemoryFailSafeProfile(trigger: "makeRenderConfiguration")

        let sharedDefaults = UserDefaults(suiteName: SharedDefaultsKeys.appGroupID)
        let candidateSourceMode = currentKanaKanjiCandidateSourceMode(from: sharedDefaults)
        let candidatePresentation = currentCandidatePresentationForRender(
            systemCandidateMode: candidateSourceMode
        )
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
        } else if !lastSynchronizedContextBeforeInputTail.isEmpty {
            postModifierContext = lastSynchronizedContextBeforeInputTail
        } else {
            postModifierContext = currentTextContextBeforeInput()
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
        let kanaPostModifierEmptyTapActionRawValue = sharedStringValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.kanaPostModifierEmptyTapAction,
            fallback: "kaomoji"
        )
        let kanaPostModifierEmptyTapKaomojiCategoryID = sharedStringValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.kanaPostModifierEmptyTapKaomojiCategory,
            fallback: "existing"
        )
        let kanaPostModifierEmptyTapEmojiCategoryID = sharedStringValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.kanaPostModifierEmptyTapEmojiCategory,
            fallback: "0"
        )
        let kanaPostModifierEmptyTapSymbolCategoryID = sharedStringValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.kanaPostModifierEmptyTapSymbolCategory,
            fallback: "0"
        )
        let kanaPostModifierFlickDakutenEnabled = sharedBoolValue(
            from: sharedDefaults,
            key: SharedDefaultsKeys.kanaPostModifierFlickDakutenEnabled,
            fallback: true
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
            isSystemDictionaryFallback: kanaKanjiStore.isSystemDictionaryFallback(),
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
            kanaPostModifierEmptyTapActionRawValue: kanaPostModifierEmptyTapActionRawValue,
            kanaPostModifierEmptyTapKaomojiCategoryID: kanaPostModifierEmptyTapKaomojiCategoryID,
            kanaPostModifierEmptyTapEmojiCategoryID: kanaPostModifierEmptyTapEmojiCategoryID,
            kanaPostModifierEmptyTapSymbolCategoryID: kanaPostModifierEmptyTapSymbolCategoryID,
            kanaPostModifierFlickDakutenEnabled: kanaPostModifierFlickDakutenEnabled,
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
                ) ?? .ignored
            },
            onToggleParenthesesWrapper: { [weak self] in
                self?.toggleParenthesesWrapper()
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
            isSystemDictionaryFallback: configuration.isSystemDictionaryFallback,
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
            kanaPostModifierEmptyTapActionRawValue: configuration.kanaPostModifierEmptyTapActionRawValue,
            kanaPostModifierEmptyTapKaomojiCategoryID: configuration.kanaPostModifierEmptyTapKaomojiCategoryID,
            kanaPostModifierEmptyTapEmojiCategoryID: configuration.kanaPostModifierEmptyTapEmojiCategoryID,
            kanaPostModifierEmptyTapSymbolCategoryID: configuration.kanaPostModifierEmptyTapSymbolCategoryID,
            kanaPostModifierFlickDakutenEnabled: configuration.kanaPostModifierFlickDakutenEnabled,
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

    func latinSuggestions(prefix: String, limit: Int) -> [String] {
        kanaKanjiStore.latinSuggestions(prefix: prefix, limit: limit)
    }
}
