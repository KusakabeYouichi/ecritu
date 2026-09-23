import SwiftUI
import UIKit
import CoreFoundation
import Darwin

final class KeyboardViewController: UIInputViewController {
    enum UserInitiatedRefreshReason: String {
        case kanaInput = "kanaInput"
        case commit = "commit"
        case postModifier = "postModifier"
    }

    private static let sharedKanaKanjiStore = KanaKanjiStore(appGroupID: SharedDefaultsKeys.appGroupID)
    private static let sharedKanaKanjiConverter = KanaKanjiConverter(store: sharedKanaKanjiStore)
    static let isSupplementaryExternalCandidatesEnabled = true
    // 手書きの厳選読み(顔・仕草など)。emoji.plist(CLDR由来)より優先してマージする。
    private static let curatedEmojiReadingCandidatesByReading: [String: [String]] = {
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

    // 絵文字候補の読み→絵文字マップ。厳選読み(curated)を優先し、バンドルの
    // EmojiReadingVocab.json(references/emoji.plist=CLDR整備版 由来)をマージする。
    static let emojiReadingCandidatesByReading: [String: [String]] = {
        var merged = curatedEmojiReadingCandidatesByReading
        guard let url = Bundle(for: KeyboardViewController.self).url(
                forResource: "EmojiReadingVocab", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let loaded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            return merged
        }
        for (reading, emojis) in loaded {
            if var existing = merged[reading] {
                var seen = Set(existing)
                for emoji in emojis where seen.insert(emoji).inserted {
                    existing.append(emoji)
                }
                merged[reading] = existing
            } else {
                merged[reading] = emojis
            }
        }
        return merged
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
    // スクロール縁の効果(ぼかし)を切る修飾は**面ごと**に当てる。3122 で根にまとめて被せたところ、
    // 候補欄の上の余白まで消えた(ユーザ報告、切り分けビルドで確定)ので 3140 で撤回した。
    var hostingController: UIHostingController<KeyboardRootView>?
    var lastRenderConfiguration: RenderConfiguration?
    var keyboardHeightConstraint: NSLayoutConstraint?
    var keyboardMaxHeightConstraint: NSLayoutConstraint?
    weak var keyboardSizingView: UIView?
    var cachedPortraitSafeAreaBottomInset: CGFloat?
    // 回転アニメーション中の遷移先サイズ(viewWillTransition が渡す確定値)。
    // 非nilの間は「サイズ遷移が進行中」を意味し、高さ算出は生のウィンドウ・ビューの
    // ジオメトリでなくこの確定値を根拠にする(preferredKeyboardHeight 参照)。
    var pendingSizeTransitionTargetSize: CGSize?
    var isObservingSettingsDidChange = false
    var keyboardHeightLockValue: CGFloat?
    // 高さ要求の診断ログ用(変化時だけ1行残す。logPreferredKeyboardHeightIfChanged 参照)
    var lastLoggedPreferredKeyboardHeight: CGFloat = -1
    // 候補欄の上の余白が時々なくなる件(ユーザ報告 3141)。要求した高さと実際に与えられた高さが
    // 食い違うと面が縮み、真っ先に上の余白が食われる、という筋を確かめるための記録。
    // 食い違いの有無が変わったときだけ 1 行残す
    var lastLoggedKeyboardHeightMismatch: CGFloat = 0
    // 枠がこちらの要求より小さいままのときに、もう一度要求を届けた回数(3158)。一致したら 0 に戻す
    var keyboardHeightRetryCount = 0
    // この表示で「その向きの最大の高さ」を一度通したか(3160)
    var didPrimeMaximumKeyboardHeight = false
    static let keyboardHeightRetryLimit = 3
    var lastLoggedPreferredKeyboardHeightIsLandscape = false
    var keyboardHeightLockReleaseTime: CFAbsoluteTime = 0
    var keyboardHeightLockReleaseWorkItem: DispatchWorkItem?
    var dictionaryPreloadWorkItem: DispatchWorkItem?
    var keyboardBootstrapWorkItem: DispatchWorkItem?
    var sharedDataPrewarmWorkItem: DispatchWorkItem?
    var keyboardAttachWatchdogWorkItem: DispatchWorkItem?
    // watchdog が「表示未到達」と数えた時刻。この後 viewWillAppear が来たら遅延復帰として
    // 数え直す(ホスト接続の再確立が遅いだけで attach 自体は成立している。2564)
    var keyboardAttachWatchdogFiredAt: CFAbsoluteTime?
    var supplementaryLexiconCandidatesByReading: [String: [String]] = [:]
    var supplementaryMergedCandidatesCacheByKey: [String: [String]] = [:]
    // 連絡先候補はプロセス共有(2655)。内容はコンテナが書く共有キャッシュそのもので全個体
    // 同一(実機: 4126読み・4945件)なのに個体ごとに持っていたため、多重生存時に alive×約1MB
    // の常駐と、設定変更通知での全個体同時再読込(一時ピーク約2MB×個体数)を生んでいた。
    // 辞書ストア(sharedKanaKanjiStore)と同じくプロセスに1部だけ持ち、読込中フラグと
    // 最終更新時刻も共有して再読込を1回に集約する。アクセスは全て main。
    // 連絡先候補は補助語彙と同じコンパクト表で常駐させる(2718)。[String: [String]] だと
    // 1件の連絡先を最大10通りの読みに展開したエントリが Swift 辞書+配列+String の
    // オーバーヘッド(150〜250B/エントリ)で約0.85MB になっていた(memgraph 2645)。
    static var sharedContactCandidatesByReading: SupplementalVocabCompactStore = .empty
    static var sharedIsRefreshingContactCandidates = false
    static var sharedContactCandidatesLastRefreshAt: Date?
    // 復号済みの畳んだ封緘版の印(コンテナーが書く UUID)。個体が作られるたび(bootstrap の force 読込)に同じ blob を
    // 復号し直し、そのたび約 1MB の Data を確保して malloc の領域を 1 つ開けていた(実機 3080: 48→52)。印が同じなら共有表をそのまま使う
    static var sharedContactCandidatesStamp: String?
    var contactCandidatesByReading: SupplementalVocabCompactStore {
        get { Self.sharedContactCandidatesByReading }
        set { Self.sharedContactCandidatesByReading = newValue }
    }
    var isRefreshingContactCandidates: Bool {
        get { Self.sharedIsRefreshingContactCandidates }
        set { Self.sharedIsRefreshingContactCandidates = newValue }
    }
    var contactCandidatesLastRefreshAt: Date? {
        get { Self.sharedContactCandidatesLastRefreshAt }
        set { Self.sharedContactCandidatesLastRefreshAt = newValue }
    }
    var isRefreshingSupplementaryLexicon = false
    var supplementaryLexiconLastRefreshAt: Date?
    var currentInputMode: KeyboardInputMode = .kana
    var spaceToastTrigger = 0
    var composingRawText = ""
    var composingReading = ""
    var hasParenthesesWrapper = false
    var activeConversion: ActiveConversion?
    var recentKanaPlainCommit: RecentKanaPlainCommit?
    let recentKanaPlainCommitUpgradeWindow: TimeInterval = 0.45
    let idleCommitUndoWindow: TimeInterval = 4.0
    var lastKanaPostModifierAppliedAt: CFAbsoluteTime = 0
    var lastKanaPostModifierResultCharacter: Character?
    var lastTextProxyEditAt: CFAbsoluteTime = 0
    let externalTextChangeDetectionWindow: CFTimeInterval = 0.35
    // メモリ警告を1イベント(バースト)にまとめる窓(定義は Diagnostics の memoryWarningBurstCountThisSession 参照)
    static let memoryWarningBurstWindow: CFTimeInterval = 2.0
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
    #if DEBUG
    #endif
    let diagnosticsState = DiagnosticsState()
    var pendingRefreshKeyboardStateRequests = 0
    var isRefreshKeyboardStateAsyncScheduled = false
    let candidateGenerationSequencer = CandidateGenerationSequencer()
    let candidateBarModel = KeyboardCandidateBarModel()
    var settledCandidatePresentation: CandidatePresentation?
    var settledCandidatePresentationKey: CandidatePresentationCacheKey?
    let candidateGenerationQueue = DispatchQueue(
        label: "com.kusakabe.ecritu.candidate-generation",
        qos: .userInitiated
    )
    var markedTextWatchdogTimer: DispatchSourceTimer?
    var idleCommitWorkItem: DispatchWorkItem?
    var lastMarkedTextUpdateAt: CFAbsoluteTime = 0
    static let markedTextWatchdogInterval: TimeInterval = 1.5
    static let markedTextWatchdogQuietPeriod: TimeInterval = 1.0
    static let idleCommitIntervalDefault: TimeInterval = 1.2
    static let idleCommitIntervalRange: ClosedRange<Double> = 0.3...5.0
    static let markedTextWatchdogQueue = DispatchQueue(
        label: "com.kusakabe.ecritu.marked-text-watchdog",
        qos: .utility
    )

    struct CandidatePresentationCacheKey: Equatable {
        let reading: String
        let composingRawText: String
        let modeRawValue: String
    }
    var memoryFailSafeProfile: MemoryFailSafeProfile = .normal
    // サスペンド時スリム化(キーボード非表示時のキャッシュ破棄+ページ返却)。
    // コンテナーアプリでOn/Off可、既定オン(2640)
    var isSuspendMemorySlimmingEnabled = true
    // 地球儀キーの要否(needsInputModeSwitchKey)。ホスト接続後(viewDidAppear)に読んで保持し、描画では
    // この値を使う(描画ごとの直接参照は接続前呼び出しの UIKit エラーログを量産する。2824)
    var cachedNeedsInputModeSwitchKey = false
    // 表示直後の高さ落ち着き待ち(3100)。純正など高さの違うキーボードから切り替えた直後、ウィンドウは前のキーボードの
    // 高さ(実測 461/471pt)のままで、こちらの高さ制約(242pt)が効くまでの 1 フレームを écritu が描いてしまう
    // (面が約 220pt 上にずれて見える「跳ね」。ユーザ報告の録画 03:07)。view の高さが要求値に一致するまで面を隠す。
    // 取り付け失敗などで一致しない場合に見えないままにならないよう、期限を過ぎたら必ず見せる
    var isAwaitingInitialHeightSettle = false
    var initialHeightSettleDeadline: CFAbsoluteTime = 0
    static let initialHeightSettleTimeoutSec: CFAbsoluteTime = 0.25
    // 温度の度記号の字形(設定 degreeSymbol。提示層で °C/℃ を置換する)
    var degreeSymbolStyle: DegreeSymbolStyle = .composed
    // MEMFORENSICS(時限計測 2651): プロセス初回変換スパイクの解剖は1回だけ
    nonisolated(unsafe) static var didProbeFirstConversionSpike = false
    var hasDeferredSharedSettingsCatchUp = false
    var lastInactiveSessionSuppressionLogAt: CFAbsoluteTime = 0
    var didApplyInactiveSessionMitigation = false
    // 読み込みから表示までの間に、別個体が画面を持っていたか(3147)。予備個体の判定に使う
    var observedAnotherInstanceAsDisplayOwner = false
    // ──── 多重生存の原因特定用センサス(でばぐ計測。後で外す可能性あり)────
    // 全インスタンスの弱参照レジストリ。セッション開始・非アクティブ降格・メモリ警告時に
    // 生存一覧とアンカー(window/superview/parent/CF参照数)をログし、「誰が保持しているか」の
    // 手がかりを残す。弱参照なので保持自体には影響しない。
    static let liveControllerCensus = NSHashTable<KeyboardViewController>.weakObjects()
    // プロセス内で最後に viewWillAppear が到達した時刻。attach 監視 watchdog の偽陽性判定に使う
    // (自分の監視開始より後に別インスタンスが表示されていれば、ユーザーは écritu を見ている=
    // iOS の投機生成VCであって attach 失敗ではない。2532)。
    static var lastAttachedViewWillAppearAt: CFAbsoluteTime = 0
    let controllerCreatedAt: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    // 測定(2721): 個体1体を立ち上げる(init→初回 viewDidAppear)コスト。init 時点の snapshot
    let controllerCreationSnapshot = MemoryForensics.snapshot()
    var didLogControllerCreationDelta = false
    // 非アクティブ降格を検知した時刻(deinit までのゾンビ滞留時間の計測に使う)
    var lostActiveOwnershipAt: CFAbsoluteTime = 0
    // 最後に反映済みの設定変更世代。-1 は未初期化(初回表示で現在値に合わせるだけで破棄しない)。
    // **プロセス単位で持つこと**(2972)。キャッシュ(学習/追加語彙/候補)は静的な共有ストアに
    // あってプロセス生涯で生きるのに、以前はこの世代をビュー・コントローラーの
    // インスタンス変数にしていた。キーボードの表示ごとに新しい VC が作られるため毎回
    // 未初期化に戻り、「VC が居ない間に起きた設定変更」は次の VC の初回 viewWillAppear で
    // 現在値に合わせるだけになって破棄されない。学習リセットを押してからキーボードを開くと
    // まさにこの順序になり、リセットがまったく反映されていなかった(実機ログで確認)。
    static var lastSeenSettingsChangeGeneration = -1
    // 学習リセットの世代(2968)。-1 は未初期化。上と同じ理由でプロセス単位
    static var lastSeenLearningResetGeneration = -1

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
        var fromIdleCommit: Bool = false
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
        static let idleCommitEnabled = "idleCommitEnabled"
        static let idleCommitInterval = "idleCommitInterval"
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
        static let katakanaEmphasisCandidateMode = "katakanaEmphasisCandidateMode"
        static let mazegakiCandidateMode = "mazegakiCandidateMode"
        // 旧字体・異体字の抑制(小分類ごと。2991)。値は ScriptVariantSuppressionCategory.settingsKey
        static let scriptVariantSuppressKyujitai = "scriptVariantSuppressKyujitai"
        static let scriptVariantSuppressItaiji = "scriptVariantSuppressItaiji"
        static let scriptVariantSuppressRyakuji = "scriptVariantSuppressRyakuji"
        static let scriptVariantSuppressConfusable = "scriptVariantSuppressConfusable"
        static let scriptVariantSuppressPersonNameVariant = "scriptVariantSuppressPersonNameVariant"
        static let iterationMarkCandidatesEnabled = "iterationMarkCandidatesEnabled"
        static let latinLexiconEnglishEnabled = "latinLexiconEnglishEnabled"
        static let degreeSymbol = DegreeSymbolStyle.sharedDefaultsKey
        // 書式化数値モード(KeyboardRootView+FormattedNumberLayout)が読む書式設定。App 側 SettingsKeys と同じ文字列(2805 で直書きを集約)
        static let numberThousandsSeparator = "numberThousandsSeparator"
        static let numberDecimalSeparator = "numberDecimalSeparator"
        static let numberGroupFourDigits = "numberGroupFourDigits"
        static let numberUnitProductSeparator = "numberUnitProductSeparator"
        static let numberLitreSymbol = "numberLitreSymbol"
        static let formattedNumberKeypadLayout = "formattedNumberKeypadLayout"
        static let calendarWeekStart = "calendarWeekStart"
        static let calendarWeekdayLanguage = "calendarWeekdayLanguage"
        static let calendarSundayColor = "calendarSundayColor"
        static let calendarFridayColor = "calendarFridayColor"
        static let calendarSaturdayColor = "calendarSaturdayColor"
        static let dateFormatStyle = "dateFormatStyle"
        static let latinLexiconFrenchEnabled = "latinLexiconFrenchEnabled"
        static let latinLexiconGermanEnabled = "latinLexiconGermanEnabled"
        static let latinLexiconItalianEnabled = "latinLexiconItalianEnabled"
        static let userDictionaryCandidateDisplayMode = "userDictionaryCandidateDisplayMode"
        static let contactCandidateDisplayMode = "contactCandidateDisplayMode"
        static let emojiCandidateDisplayEnabled = "emojiCandidateDisplayEnabled"
        static let radicalStrokeCountStyle = "radicalStrokeCountStyle"
        static let ordinalMeKanjiPreferred = "ordinalMeKanjiPreferred"
        static let kaCounterVariantPreference = "kaCounterVariantPreference"
        static let okuriganaVariantPreference = "okuriganaVariantPreference"
        static let adjectiveMeKanjiCandidatesEnabled = "adjectiveMeKanjiCandidatesEnabled"
        static let suspendMemorySlimmingEnabled = "suspendMemorySlimmingEnabled"
        static let kaomojiCandidateDisplayEnabled = "kaomojiCandidateDisplayEnabled"
        static let contactCandidatesByReadingCache = "contactCandidatesByReadingCache"
        // AES-GCM封緘版(平文キーは移行後に削除される)
        static let contactCandidatesByReadingCacheSealed = "contactCandidatesByReadingCacheSealed"
        // 畳んだ表を封緘した版(3020)
        static let contactCandidatesByReadingCacheCompactSealed = "contactCandidatesByReadingCacheCompactSealed"
        static let contactCandidatesByReadingCacheCompactSealedStamp = "contactCandidatesByReadingCacheCompactSealedStamp"
        static let supplementaryLexiconIndexCacheByReading = "supplementaryLexiconIndexCacheByReading"
        static let supplementaryLexiconIndexSignature = "supplementaryLexiconIndexSignature"
        static let keyboardDiagnosticsLogLines = "keyboardDiagnosticsLogLines"
        // 重大イベント(メモリ警告/最終手段アンロード/フェイルセーフ遷移)の保護ログ。
        // 320行ローテーションとinstall変更リセットの対象外(事後検証の証拠を残す)。
        static let keyboardDiagnosticsCriticalLogLines = "keyboardDiagnosticsCriticalLogLines"
        static let keyboardDiagnosticsInstallMarker = "keyboardDiagnosticsInstallMarker"
        static let keyboardDiagnosticsSessionActive = "keyboardDiagnosticsSessionActive"
        static let keyboardDiagnosticsSessionOwnerToken = "keyboardDiagnosticsSessionOwnerToken"
        static let keyboardDiagnosticsLastHeartbeat = "keyboardDiagnosticsLastHeartbeat"
        static let keyboardDiagnosticsLastEvent = "keyboardDiagnosticsLastEvent"
        static let keyboardDiagnosticsLastSessionID = "keyboardDiagnosticsLastSessionID"
        static let keyboardDiagnosticsFailSafeProfile = "keyboardDiagnosticsFailSafeProfile"
        static let keyboardDiagnosticsFlightRecorderEvents = "keyboardDiagnosticsFlightRecorderEvents"
        // 起動回数と表示未到達(viewDidLoad後にviewWillAppearが来ない=attach失敗の疑い)回数。
        // critical logと同様にinstall変更リセットの対象外(「何回中何回」を累積で観測する)。
        static let keyboardDiagnosticsLaunchCount = "keyboardDiagnosticsLaunchCount"
        static let keyboardDiagnosticsAttachFailureCount = "keyboardDiagnosticsAttachFailureCount"
        // 未到達と数えた後に viewWillAppear が遅れて来た回数。ホスト接続の再確立が遅いだけで
        // attach は成立しており、真の失敗と区別しないと統計が実態からずれる(実測6.5秒。2564)
        static let keyboardDiagnosticsAttachLateRecoveryCount = "keyboardDiagnosticsAttachLateRecoveryCount"
        // 表示予定のない予備の個体だった回数(3147)。ホストはキーボードを閉じる際に、次に備えて
        // 入力ビューの個体をもう 1 つ作ることがある。実機の統合ログで確認: Facebook が
        // 「セッション無効化 → すぐ次の remote view controller を要求 → 12 秒後に破棄」を行い、
        // その間キーボードは画面に無い(placeholder 393x0)。未到達と数えると実態からずれる
        static let keyboardDiagnosticsSpareControllerCount = "keyboardDiagnosticsSpareControllerCount"
        // デバッグ用: 直近1回の変換トレース(上書き式)。実機のみ再現する誤変換の層特定に使う。
        // reading→連文節上位|単文節上位|LM/フェイルセーフ/モード を記録。ローテなし・単一値。
        static let keyboardConversionLastTrace = "keyboardConversionLastTrace"
        // 設定変更の世代カウンタ(コンテナ app が変更のたび +1)。サスペンド中のキーボードが
        // Darwin 通知を取りこぼしても、次のキーボード表示でこの値の変化を見て共有キャッシュを
        // 破棄し、学習リセット等を確実に反映する。App 側 SettingsKeys と同一キー文字列。
        static let settingsChangeGeneration = "settingsChangeGeneration"
        // 学習リセットの世代カウンタ(2968)。通常の設定変更と分けているのは、リセットでは
        // プロセス内の学習キャッシュを「書き出さずに」捨てる必要があるため。App 側と同一キー文字列。
        static let learningResetGeneration = "learningResetGeneration"
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

    // 背景グラデーションの層(2920)。SwiftUI ではなく UIKit 側に置く理由は applyKeyboardBaseBackground のコメント参照
    private var backgroundGradientLayer: CAGradientLayer?

    private static let hostTopOverlap: CGFloat = 0
    // 寸法・位置の定数は KeyboardLayoutMetrics に集約した(2609)。
    // 端末別の値はそちらの .phone / .pad を触る。
    var layoutMetrics: KeyboardLayoutMetrics {
        KeyboardLayoutMetrics.metrics(for: KeyboardDeviceKind.resolve(traitCollection))
    }

    static let keyboardSwitchHeightLockDuration: TimeInterval = 0.45
    private static let deviceSystemDictionaryPreloadDelay: TimeInterval = 1.2
    private static let minimumPhysicalMemoryForSystemDictionaryPreload: UInt64 = 5 * 1024 * 1024 * 1024
    private static let maximumFootprintMBForSystemDictionaryPreload: Double = 100
    private static let refreshQueueBacklogLogThreshold = 6
    private static let refreshQueueWaitSlowThresholdMs = 60
    private static let renderConfigurationSlowThresholdMs = 16
    private static let refreshKeyboardStateSlowThresholdMs = 28
    // 上限は ContactCacheCipher.Limits に移した(3020。コンテナー側も同じ規則で切るため)
    static let maximumSupplementaryMergedCandidateCacheEntries = 512
    static let isCommitUnderlineDiagnosticsLoggingEnabled = false
    // 連文節変換(案1: 自前単語 n-gram LM のラティス Viterbi)。連文節候補を先頭の次へ合流する
    // (既存の単文節候補は保持)ため退行リスクは低い。実機で検証する。
    static let isMultiClauseConversionEnabled = true
    // メモリフェイルセーフは jetsam 実値(phys_footprint)で判定する。RSS(resident_size)は
    // 共有/クリーンページや mmap を含み jetsam 圧を過大評価するため使わない。
    // 閾値の基準は拡張プロセスの per-process 上限 77MB(2026-08 に jetsam 死のカーネルログ4件で実測)。
    // 旧値 90/115/12 は上限を知る前(通常ピーク48の2.4倍)に決めたもので到達不能だった(2769 で見直し)。
    // elevated 62: 長寿命プロセスの実測ベースライン(最大58.5)を超えて育ったとき(候補14/欧文18/
    //   ショートカット20、共有キャッシュ破棄)。critical 70: 死の7MB手前の最終縮小(候補8/欧文0/全キャッシュ破棄)。
    // recover 6: elevated→normal は56未満、critical→elevated は64未満(58〜62 の往復でばたつかない幅)。
    // 別系統の予防ゲート(絵文字切替前解放 50)はそのまま(欧文構築見送り 52 は 2770 で構築自体を廃止)
    static let memoryFailSafeElevatedStartMB: Double = 62
    static let memoryFailSafeCriticalStartMB: Double = 70
    static let memoryFailSafeRecoverDeltaMB: Double = 6
    private static let refreshQueueDropThresholdInCriticalMode = 2
    #if DEBUG
    static let diagnosticsFlightRecorderWindowSec: TimeInterval = 6
    static let diagnosticsFlightRecorderMaxEventCount = 120
    static let diagnosticsFlightRecorderMinRecordIntervalSec: TimeInterval = 0.12
    #endif
    private static let baseKeyboardBackgroundColor = UIColor { trait in
        if trait.userInterfaceStyle == .dark {
            return UIColor(red: 0.12, green: 0.14, blue: 0.18, alpha: 1.0)
        }

        return UIColor(red: 0.89, green: 0.90, blue: 0.92, alpha: 1.0)
    }

    enum PortraitHeightProfile: CaseIterable {
        case kanaThreeByThree
        case compactGrid
        case compactActionRow
        case kanaFiveByTwo
        case emoji
        case formattedNumber
    }

    #if DEBUG
    struct DiagnosticsFlightRecorderEvent: Codable {
        let timestamp: TimeInterval
        let event: String
        let source: String
    }
    #endif

    enum MemoryFailSafeProfile: String {
        case normal
        case elevated
        case critical
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // 起動計測: 初回起動が iOS の拡張起動デッドラインを超えると純正キーボードに
        // 差し替えられるため、同期区間の実測を診断ログへ残す(遅い時のみ)。
        let launchStartedAt = CFAbsoluteTimeGetCurrent()
        keyboardLaunchViewDidLoadAt = launchStartedAt
        startKeyboardDiagnosticsSession()
        // MEMFORENSICS(時限計測 2611): 高水位台帳の出力先。剥がすときはこのブロックと
        // KeyboardMemoryForensics.swift を削除(grep MEMFORENSICS)
        // 出力先は「そのとき生きている個体」を書き込み時に選ぶ(2721)。以前は viewDidLoad の個体を
        // weak で捕まえていたため、その個体の deinit 直後に発火する測定(個体deinit の窓)が黙って落ちた
        MemoryForensics.logSink = { line in
            DispatchQueue.main.async {
                let live = KeyboardViewController.liveControllerCensus.allObjects
                let target = live.first(where: { $0.viewIfLoaded?.window != nil }) ?? live.first
                target?.appendKeyboardDiagnosticsLog(line, critical: true, file: #fileID, line: #line, function: "MemoryForensics")
            }
        }
        MemoryForensics.noteOperation("起動")
        updateKeyboardDiagnosticsHeartbeat(event: "viewDidLoad", appendLog: true)
        recordKeyboardDiagnosticsAppGroupHealth()
        startKeyboardAttachWatchdog()
        configureKeyboardContainerSizing()
        beginKeyboardHeightLock()
        prepareKeyboardVisualForTransition()
        configureInputAssistantBar()
        Self.liveControllerCensus.add(self)
        startObservingSettingsDidChange()
        applyConverterFeatureFlagsFromSharedDefaults()
        let setupStartedAt = CFAbsoluteTimeGetCurrent()
        setupKeyboardView()
        let totalMs = Int((CFAbsoluteTimeGetCurrent() - launchStartedAt) * 1000)
        let setupMs = Int((CFAbsoluteTimeGetCurrent() - setupStartedAt) * 1000)
        if totalMs >= 80 {
            appendKeyboardDiagnosticsLog(
                "起動同期区間が遅い viewDidLoad=\(totalMs)ms (setupKeyboardView=\(setupMs)ms)"
            )
        }
    }

    deinit {
        // 測定(2721): 個体1体の解体で used/alloc/fp がどれだけ戻るか。ゾンビ4体(retain=8、1.5〜2.8時間)
        // のビュー解放が fp を3MBしか戻さなかったので、VC本体の死の値を直接測る。static 呼び出しで
        // self は捕まえない(解体中の weak 参照は禁止)
        MemoryForensics.noteSpikeWindow(
            "個体deinit(\(diagnosticsState.diagnosticsControllerID.prefix(8))) alive=\(Self.liveControllerCensus.allObjects.count - 1)",
            minDeltaMB: 0
        )
        // 以降のログ書き込みは同期保存(解体中の self への weak 参照を作らない。Diagnostics 参照)
        diagnosticsState.diagnosticsLogLock.withLock {
            diagnosticsState.diagnosticsIsDeinitializing = true
            diagnosticsState.diagnosticsLogFlushWorkItem?.cancel()
            diagnosticsState.diagnosticsLogFlushWorkItem = nil
        }
        flushDiagnosticsLogLinesIfDirty()
        if lostActiveOwnershipAt > 0 {
            let zombieSec = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - lostActiveOwnershipAt)
            appendKeyboardDiagnosticsLog(
                "ゾンビ滞留 アクティブ喪失→deinit=\(zombieSec)s controllerID=\(diagnosticsState.diagnosticsControllerID)",
                critical: true,
                file: #fileID,
                line: #line,
                function: #function
            )
        }
        finishKeyboardDiagnosticsSession(reason: "deinit")
        keyboardAttachWatchdogWorkItem?.cancel()
        keyboardBootstrapWorkItem?.cancel()
        dictionaryPreloadWorkItem?.cancel()
        keyboardHeightLockReleaseWorkItem?.cancel()
        stopObservingSettingsDidChange()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        cancelKeyboardAttachWatchdog()
        // 未到達と数えた後に表示が来たなら遅延復帰として数え直す(cancel より後に呼ぶ)
        recordKeyboardAttachLateRecoveryIfNeeded()
        Self.lastAttachedViewWillAppearAt = CFAbsoluteTimeGetCurrent()
        // 表示された時点でオーナー権を主張する(未表示の投機生成VCに奪われた状態からの復帰も
        // ここで行う)。この後の shouldSuppressHeavyOperations が誤って抑止に落ちないよう、
        // ビュー構築より前に済ませる必要がある。
        claimKeyboardSessionOwnership()
        // 押下残留(赤キー)フックは単一グローバルで最後の代入が勝つ。viewDidLoad で張ると
        // 未表示の投機生成VCが計測を横取りし(カウンタがそのゾンビ側に溜まる)、そのVCが
        // 解放された後は weak self=nil で計測が黙って落ちる。表示インスタンスが持つ(2532)。
        KeyboardStuckTouchDiagnostics.onForceClear = { [weak self] detail in
            self?.recordStuckTouchForceClear(detail)
        }
        // 調査用ログ(記号面切替 2838): 左下キーの commit ごとの接触詳細。原因判明後に外す
        KeyboardStuckTouchDiagnostics.onTouchForensics = { [weak self] detail in
            self?.appendKeyboardDiagnosticsLog("接触詳細 \(detail)")
        }
        #if DEBUG
        // 調査用ログ(3163): 面の中身が枠に収まっているか。枠の高さも添える
        KeyboardRootOverflowForensics.onReport = { [weak self] detail in
            guard let self else {
                return
            }
            self.appendKeyboardDiagnosticsLog(
                detail + " 枠高さ=\(Int(self.view.bounds.height)) モード=\(self.currentInputMode)",
                critical: true
            )
        }
        // 調査用ログ(候補欄の上余白 3145): 実測の余白が変わった瞬間だけ。原因判明後に外す
        KeyboardCandidateBarLayoutForensics.onReport = { [weak self] detail in
            guard let self else {
                return
            }
            // 面の上端も添える。余白が「詰まった」のか「バーごと上にずれた」のかを区別するため
            let keyboardTopY = Int(self.view.convert(self.view.bounds, to: nil).minY)
            self.appendKeyboardDiagnosticsLog(
                detail + " 面上端=\(keyboardTopY) 面高さ=\(Int(self.view.bounds.height))",
                critical: true
            )
        }
        #endif
        updateKeyboardDiagnosticsHeartbeat(event: "viewWillAppear", appendLog: true)
        // 高さが落ち着くまで面を隠す(定義コメント参照。3100)
        isAwaitingInitialHeightSettle = true
        initialHeightSettleDeadline = CFAbsoluteTimeGetCurrent() + Self.initialHeightSettleTimeoutSec

        // メモリ警告カウントは「表示セッション」単位でリセットする。
        // 拡張プロセスはアプリ切替をまたいで長生きするため、プロセス生涯で累積させると
        // どこかで警告2回に達した時点で辞書が永久停止し、「みまん→候補なし」の辞書なし
        // キーボードに退化したまま戻らない(いじょう→異常 だけ残るのは学習語彙経路)。
        diagnosticsState.memoryWarningCountThisSession = 0
        diagnosticsState.memoryWarningBurstCountThisSession = 0
        diagnosticsState.lastMemoryWarningAt = 0
        candidateBarModel.memoryWarningCountForDebugDisplay = 0
        candidateBarModel.memoryWarningBurstCountForDebugDisplay = 0
        candidateBarModel.memoryFootprintPeakMBForDebugDisplay = 0
        diagnosticsState.memoryFootprintPeakMB = 0
        // 非アクティブ降格時に解除した Darwin observer を再登録する(多重ガードあり)。
        startObservingSettingsDidChange()
        lostActiveOwnershipAt = 0
        kanaKanjiConverter.store.exitConstrainedMemoryCacheMode()
        // サスペンド中に取りこぼした設定変更(学習リセット等)を、世代カウンタの変化で検知して
        // 反映する。Darwin 通知を受け損ねても表示のたびに保険が効く。
        applyMissedSharedSettingsChangeIfNeeded(trigger: "viewWillAppear")

        guard !shouldSuppressHeavyOperations(reason: "viewWillAppear") else {
            return
        }

        configureKeyboardContainerSizing()
        ensureKeyboardViewIfNeeded()
        // viewDidLoad 直後の初回表示では setupKeyboardView が構築した設定をそのまま使い、
        // 設定全読みの二重実行を避ける(設定変更は observer 経由で反映されるため安全)。
        beginKeyboardHeightLock()
        configureInputAssistantBar()
        prepareKeyboardVisualForTransition()
        spaceToastTrigger += 1
        refreshKeyboardState(trigger: "viewWillAppear")
    }

    // 外部変更の直前通知。完了ボタンでは textDidChange(文脈空)の 8ms 前に文脈そのままで届く(2684 実機)
    override func textWillChange(_ textInput: UITextInput?) {
        super.textWillChange(textInput)
        commitComposingTextOnExternalTextWillChangeIfNeeded(trigger: "textWillChange")
    }

    // 入力欄のタップ(カーソル移動)はテキストが変わらないので textWillChange が来ず、
    // selectionWillChange だけが「ホストが動く前」に届く。ここで確定しないと、ホストが
    // marked セッションを終了する(確定するか捨てるかはアプリ依存)ため未確定が消える
    // ことがある。文節区切りの指定は拡張には不可能(タッチ位置を取る API が無い)だが、
    // 消失は確定に置き換えられる(2979、ユーザ報告)
    override func selectionWillChange(_ textInput: UITextInput?) {
        super.selectionWillChange(textInput)
        commitComposingTextOnExternalTextWillChangeIfNeeded(trigger: "selectionWillChange")
    }

    // ホスト起因の変更が「起きる前」に届く唯一のフック。メモの完了ボタンでは textDidChange
    // (文脈空=編集終了後)の 8ms 前に来て、文脈はまだ元のまま(実機ログ 2684)。編集終了後の
    // 確定(viewWillDisappear / textDidChange 内)はホストに届かなかったので、ここで未確定を
    // 確定する(Apple 純正のキーボード終了時確定と同じ結果)。自前の編集(setMarkedText 等)に
    // 伴う通知は 0.35s 窓で除外。外部変更で未確定を保持し続ける理由は無く(従来は直後の
    // textDidChange で破棄していた)、確定の方が Apple の挙動に近い。
    // 打鍵直後の「外部変更」判定はホスト文脈の遅延・嘘(メッセージ実測 2026-08-31:
    // context=空なのにmarked=5文字が8回)で誤発火し、入力中の未確定を勝手に確定して
    // 入力が滅茶苦茶になる。メモの完了ボタン(本来の用途)はタップまでに間が空くので、
    // 直近打鍵から一定時間は見送る
    static let externalCommitKeystrokeQuiescenceSec: TimeInterval = 1.0

    func commitComposingTextOnExternalTextWillChangeIfNeeded(trigger: String) {
        guard shouldTreatAsExternalTextChange(),
            activeConversion != nil || !composingRawText.isEmpty else {
            return
        }
        let sinceOwnEdit = CFAbsoluteTimeGetCurrent() - lastTextProxyEditAt
        if sinceOwnEdit < Self.externalCommitKeystrokeQuiescenceSec {
            appendKeyboardDiagnosticsLogFromInputHandling(
                "外部変更確定を打鍵直後のため見送り trigger=\(trigger) sinceOwnEditMs=\(Int(sinceOwnEdit * 1000)) composingLen=\(composingRawText.count)",
                critical: true
            )
            return
        }
        appendKeyboardDiagnosticsLogFromInputHandling(
            "外部変更の直前に未確定を確定 trigger=\(trigger) composingLen=\(composingRawText.count) active=\(activeConversion != nil)",
            critical: true
        )
        // 素の unmarkText はメモ(Notes)では下線が残る(2685 実機。通常の確定キーも同じ理由で
        // カーソル微動 ±1 を挟む clearPass を使っている)。同期的に届く範囲で同じ手順を2回行う。
        performNonDestructiveUnderlineClearPass(stage: "willChange-1", nudgeWidth: 1)
        performNonDestructiveUnderlineClearPass(stage: "willChange-2", nudgeWidth: 1)
        activeConversion = nil
        clearComposingState()
        stopMarkedTextWatchdog()
    }

    // footprint 最大値をでばぐ表示へ反映する。**レイアウト経路から呼ばないこと**(2921)
    func publishMemoryFootprintPeakForDebugDisplay() {
        let peak = diagnosticsState.memoryFootprintPeakMB
        if candidateBarModel.memoryFootprintPeakMBForDebugDisplay != peak {
            candidateBarModel.memoryFootprintPeakMBForDebugDisplay = peak
        }
        let processPeak = diagnosticsState.memoryFootprintProcessPeakMB
        if candidateBarModel.memoryFootprintProcessPeakMBForDebugDisplay != processPeak {
            candidateBarModel.memoryFootprintProcessPeakMBForDebugDisplay = processPeak
        }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        updateKeyboardDiagnosticsHeartbeat(event: "textDidChange")
        publishMemoryFootprintPeakForDebugDisplay()

        // textDidChange は host 側のテキストが変化した(送信/autocorrect/paste/選択など
        // 何らかの理由で)シグナルなので、自前/外部を問わずキャッシュを必ず無効化する。
        // 「自前操作なら skip」の最適化は send 時に stale context で nudge 計算が
        // 狂って iMessage 等で下線残留を招くため採用しない。
        // 多重生存の非アクティブインスタンスでも、未確定の確定/クリアと下線残留クリアは
        // 正しさに不可欠なので必ず実行し、重い再描画(refreshKeyboardState)のみ抑止する。
        invalidateTextContextCache()

        synchronizeConversionContextIfNeeded(
            triggeredByExternalChange: shouldTreatAsExternalTextChange()
        )
        consumePendingHostCallbackUnderlineClearPassIfNeeded(trigger: "textDidChange")

        guard !shouldSuppressHeavyOperations(reason: "textDidChange") else {
            return
        }

        refreshKeyboardState(trigger: "textDidChange")
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        updateKeyboardDiagnosticsHeartbeat(event: "selectionDidChange")

        // 多重生存の非アクティブインスタンスでも、未確定の確定/クリアと下線残留クリアは
        // 正しさに不可欠なので必ず実行し、重い再描画(refreshKeyboardState)のみ抑止する。
        invalidateTextContextCache()

        synchronizeConversionContextIfNeeded(
            triggeredByExternalChange: shouldTreatAsExternalTextChange()
        )
        consumePendingHostCallbackUnderlineClearPassIfNeeded(trigger: "selectionDidChange")

        guard !shouldSuppressHeavyOperations(reason: "selectionDidChange") else {
            return
        }

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

    var keyboardLaunchViewDidLoadAt: CFAbsoluteTime = 0

    // 前回のセッションが未確定(marked)を残したままキーボードが閉じた場合(メモの完了ボタン等。
    // 閉じる時点の確定はホストに届かない回がある)、ホスト側には下線付きの marked 範囲が残る。
    // 次にキーボードが出た時点で écritu 側に未確定は無いので、ここで unmarkText して
    // 残留 marked を確定文字にする(Apple 純正がキーボード終了時に確定するのと同じ結果)。
    // marked が無ければ unmarkText は文書を変えない。放置すると最初の打鍵の setMarkedText が
    // 残留範囲を置き換えて前回の文字が消えていた(ユーザ報告 2680)。
    func commitStaleHostMarkedTextOnAppear() {
        guard composingRawText.isEmpty, activeConversion == nil else {
            return
        }
        noteOwnTextProxyEditTimestamp()
        textDocumentProxy.unmarkText()
    }

    // 左下キーだけ、触れてから SwiftUI の判定に届くまで 755ms かかる(実測 5 回とも 754〜756ms)。
    // 配信遅れもメインスレッドの詰まりも 30ms 未満だったので、touch を握っているのは UIKit の
    // ジェスチャー調停。画面端のシステム操作(ホームインジケータ/端スワイプ)の門番は
    // およそ 0.75 秒 touch を保留するので、下端と左端の保留を切って確かめる(3149)。
    // 効くなら「キーボード表示中は端のシステム操作を 1 回ぶん遅らせる」という代償と釣り合うかを判断する
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        [.bottom, .left]
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        // 門番は窓に付くので、窓に載ってから外す(定義コメント参照。3172)
        relaxSystemGestureGateDelayIfNeeded()
        updateKeyboardDiagnosticsHeartbeat(event: "viewDidAppear", appendLog: true)
        // ホスト接続が確立した後に地球儀キーの要否を 1 回だけ読む(定義コメント参照。2824)。変わっていれば再描画
        let needsSwitchKey = needsInputModeSwitchKey
        if needsSwitchKey != cachedNeedsInputModeSwitchKey {
            cachedNeedsInputModeSwitchKey = needsSwitchKey
            refreshKeyboardStateAsync()
        }
        if !didLogControllerCreationDelta {
            didLogControllerCreationDelta = true
            MemoryForensics.noteSyncDelta(
                "個体生成→表示(\(diagnosticsState.diagnosticsControllerID.prefix(8))) alive=\(Self.liveControllerCensus.allObjects.count)",
                since: controllerCreationSnapshot,
                minDeltaMB: -1
            )
        }
        // 測定(2726): 表示後4秒の used/fp 推移を 250ms 刻みで1行に。8/30 10:43 の警告は表示の 1.2 秒後に
        // used +4.4MB だったが、bootstrap の各段(補助語彙/連絡先/プリウォーム/初回変換)のどこかを
        // 既存の同期Δでは掴めなかった(連絡先は displayMode で未使用、変換Δは閾値未満)。時系列で場所を特定する
        MemoryForensics.sampleTimeline(
            "個体表示後(\(diagnosticsState.diagnosticsControllerID.prefix(8)))",
            intervalSeconds: 0.25,
            sampleCount: 16
        )
        commitStaleHostMarkedTextOnAppear()
        // 窓に載っている今なら「別に表示中の個体が実在する」が自明なので、忘れられた離脱個体を
        // 安全に掃除できる(3199)。センサスは降格が起きたときにしか走らないため、こちらも入り口にする
        sweepForgottenDetachedControllers(trigger: "viewDidAppear")

        if keyboardLaunchViewDidLoadAt > 0 {
            let toAppearMs = Int((CFAbsoluteTimeGetCurrent() - keyboardLaunchViewDidLoadAt) * 1000)
            keyboardLaunchViewDidLoadAt = 0
            if toAppearMs >= 250 {
                appendKeyboardDiagnosticsLog("初回表示まで遅い viewDidLoad→viewDidAppear=\(toAppearMs)ms")
            }
        }

        scheduleKeyboardBootstrapIfNeeded()

        guard lastRenderConfiguration != nil else {
            return
        }

        applyKeyboardBaseBackground()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        updateKeyboardDiagnosticsHeartbeat(event: "viewWillDisappear", appendLog: true)
        persistBufferedKeyboardDiagnostics()

        commitPendingComposingTextForKeyboardDismiss()
        stopMarkedTextWatchdog()
        cancelIdleCommit()

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
            includeSystemCaches: memoryFailSafeProfile != .normal,
            honorsSlimmingToggle: true
        )
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        updateKeyboardDiagnosticsHeartbeat(event: "viewDidDisappear", appendLog: true)

        performHiddenKeyboardMemoryTrim(
            reason: "viewDidDisappear",
            releaseHostingView: true,
            includeSystemCaches: true,
            honorsSlimmingToggle: true
        )
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // 自己コスト計測(2654): 8/25 の死2件(10:34/16:56)は、警告時 fp59.6 の直後に
        // 記録した「メモリ内訳census」が最終行で、census2 が2回とも記録されないまま
        // 0.7 秒後に 77MB(ActiveHard)で殺されていた。ハンドラ自身の重さを入口/診断後/
        // 出口の3点で残す。
        let handlerEntrySnapshot = MemoryForensics.snapshot()
        // 多重生存中の非アクティブ(ゾンビ)側は軽量対応のみ: キャッシュを解放して終わる。
        // フェイルセーフ昇格・LM縮小・警告回数のカウントはアクティブ側に任せる(ゾンビの
        // 重複反応で回数が水増しされ、削除キーの可視化も実態とずれるため。2411)。
        if shouldSuppressHeavyOperations(reason: "didReceiveMemoryWarning") {
            kanaKanjiConverter.clearAllCaches()
            // 圧迫時こそ非表示ゾンビのビュー階層を手放す(降格時の一度きり判定を補う。2574)。
            // ここは非オーナーが確定している経路なので window 条件は課さない(2583)。
            releaseHostingViewIfZombie(reason: "memoryWarning", ignoringWindowAttachment: true)
            return
        }
        // 絵文字キャッシュ由来の警告(2673): 実機では CoreText の絵文字キャッシュ(展開画像、
        // 1個54KB)が per-process 警告のタイミングで OS に purge される(実測 8/26 19:27:
        // fp59.1→27.5、used44→15)。絵文字パネル表示中/描画直後の警告は OS 側で正しく処理される
        // 無害なもので、LM縮小・critical昇格・削除キー橙は過剰反応になる。軽量対応だけして戻る
        if currentInputMode == .emoji {
            kanaKanjiConverter.clearAllCaches()
            malloc_zone_pressure_relief(nil, 0)
            appendKeyboardDiagnosticsLog(
                "メモリ警告(絵文字キャッシュ由来)を軽量処理 footprintMB=\(diagnosticsFootprintMBText())"
                    + " mode=\(currentInputMode)",
                critical: true,
                file: #fileID,
                line: #line,
                function: #function
            )
            return
        }
        diagnosticsState.memoryWarningCountThisSession += 1
        let warningNow = CFAbsoluteTimeGetCurrent()
        if warningNow - diagnosticsState.lastMemoryWarningAt > Self.memoryWarningBurstWindow {
            diagnosticsState.memoryWarningBurstCountThisSession += 1
        }
        diagnosticsState.lastMemoryWarningAt = warningNow
        // attach 待ちの5秒間は診断を丸ごと飛ばす(2603)。実測(00:41 の attach 失敗):
        // 起動直後のインスタンスが viewWillAppear を待っている最中にメモリ警告を2回受け、
        // センサス(alive=12 の走査)+ census2(malloc 全ブロック列挙、実測113ms)を
        // 2往復ぶん main スレッドで実行していた。refreshKeyboardStateAsync が waitMs=2478 まで
        // 押し出され、viewDidLoad から5秒以内に viewWillAppear が来ず純正へ落ちた。
        // 診断は原因を測るためのものなので、それ自体が原因になっては本末転倒。
        // 解放(キャッシュ/アリーナ返却)は下でそのまま行う。
        // 警告は数百msの間に連続で届くことがある(実測: 200ms 内に6回)。そのたびに
        // 全ブロック列挙をやり直すと main を塞ぐだけで新しい情報も出ないので間隔を置く。
        let now = CFAbsoluteTimeGetCurrent()
        let isCensusThrottled = now - Self.lastMemoryCensusAt < Self.memoryCensusMinimumInterval
        let isAwaitingAttach = keyboardAttachWatchdogWorkItem != nil || isCensusThrottled
        var heavyCensusAllowedThisWarning = false
        if !isAwaitingAttach {
            Self.lastMemoryCensusAt = now
        }
        if isAwaitingAttach {
            appendKeyboardDiagnosticsLog(
                "メモリ内訳の採取をスキップ"
                    + " reason=\(keyboardAttachWatchdogWorkItem != nil ? "awaitingAttach" : "throttled")"
                    + " footprintMB=\(diagnosticsFootprintMBText())",
                critical: true,
                file: #fileID,
                line: #line,
                function: #function
            )
        } else {
            logLiveControllerCensus(trigger: "memoryWarning")
        }
        // footprint 高止まり(安静時51MB級)の正体切り分け: malloc ヒープの実使用量と
        // 自前キャッシュの件数を記録する。mallocUsed が小さいのに footprint が大きければ
        // ヒープ外(描画層/IOSurface/圧縮メモリ 等)、大きければ自前かライブラリの蓄積。
        if !isAwaitingAttach {
            var stats = malloc_statistics_t()
            malloc_zone_statistics(nil, &stats)
            let usedMB = Double(stats.size_in_use) / 1_048_576
            let allocatedMB = Double(stats.size_allocated) / 1_048_576
            appendKeyboardDiagnosticsLog(
                "メモリ内訳census mallocUsedMB=\(String(format: "%.1f", usedMB))"
                    + " mallocAllocMB=\(String(format: "%.1f", allocatedMB))"
                    + " \(kanaKanjiConverter.diagnosticsCacheCountsSummary())"
                    + " \(MemoryForensics.loadSummary)",
                critical: true,
                file: #fileID,
                line: #line,
                function: #function
            )
            // 重い診断(census2〜4: malloc 全ブロック列挙・ObjC 全クラス名表の初回構築・
            // ヒープ解剖)は余裕があるときだけ(2654)。per-process 上限は ActiveHard 77MB
            // (カーネルログ原文)で、警告は fp≈60 で届く。8/25 の死2件はどちらも census2
            // の計算中に殺されており、上限まで 22MB を切った状態で数MBを確保しながら
            // main を数百ms塞ぐ診断は、原因を測るどころか原因そのものになっていた。
            let heavyCensusFootprintMB = currentFootprintMB() ?? 0
            heavyCensusAllowedThisWarning = Self.allowsHeavyCensus(footprintMB: heavyCensusFootprintMB)
            if !heavyCensusAllowedThisWarning {
                appendKeyboardDiagnosticsLog(
                    "重い診断(census2〜4)をスキップ footprintMB=\(String(format: "%.1f", heavyCensusFootprintMB))"
                        + " 閾値=\(Self.memoryHeavyCensusMaxFootprintMB)",
                    critical: true,
                    file: #fileID,
                    line: #line,
                    function: #function
                )
            }
        }
        if !isAwaitingAttach, heavyCensusAllowedThisWarning {
            // census v2(2570): (a) 全 malloc ゾーンの内訳 — malloc_zone_statistics(nil) は
            // デフォルトゾーンだけで、Nano ゾーン(≤256B の小粒確保)が見えていなかった。
            // (b) 常駐辞書構造の概算バイト — ベースライン固定費(約35MB)の正体特定用。
            // ★malloc 全ブロック列挙(diagnosticsMallocSizeHistogram / heapAnatomySummary)は
            // 実機では呼ばない(2667)。プロセス内の列挙はヒープ規模に比例した一時確保を行い、
            // 実測 fp 39.6→77MB(+37MB、1.5秒)で即死した(8/26 15:24、カーネルログ確定)。
            // 8/25 の警告時2件(fp59.6→0.7秒で77)も census2 実行中で、同じ原因。
            // 統計読み(malloc_zone_statistics/task_info)と自前構造の概算だけ残す。
            appendKeyboardDiagnosticsLog(
                "メモリ内訳census2 \(Self.diagnosticsAllMallocZonesSummary())"
                    + " | \(kanaKanjiConverter.store.diagnosticsStructureBytesSummary())",
                critical: true,
                file: #fileID,
                line: #line,
                function: #function
            )
            appendKeyboardDiagnosticsLog(
                "メモリ内訳census3 \(Self.diagnosticsStaticCatalogBytesSummary())",
                critical: true,
                file: #fileID,
                line: #line,
                function: #function
            )
            // MEMFORENSICS(時限計測 2611): sqlite/footprint 内訳(ヒープ解剖は 2667 で撤去、上記)
            appendKeyboardDiagnosticsLog(
                "メモリ内訳census4 \(MemoryForensics.summaryLine())",
                critical: true,
                file: #fileID,
                line: #line,
                function: #function
            )
        }
        // メモリ切迫の可視化(でばぐ表示): かな削除キーの背景色に反映する。
        candidateBarModel.memoryWarningCountForDebugDisplay = diagnosticsState.memoryWarningCountThisSession
        candidateBarModel.memoryWarningBurstCountForDebugDisplay = diagnosticsState.memoryWarningBurstCountThisSession
        publishMemoryFootprintPeakForDebugDisplay()
        persistBufferedKeyboardDiagnostics()
        updateKeyboardDiagnosticsHeartbeat(
            event: "メモリ警告受信(\(diagnosticsState.memoryWarningCountThisSession)回目) キャッシュ解放開始",
            appendLog: true,
            criticalLog: true
        )

        if memoryFailSafeProfile != .critical {
            memoryFailSafeProfile = .critical
            persistKeyboardDiagnosticsFailSafeProfile()
            appendKeyboardDiagnosticsLog(
                "メモリ警告を受けてフェイルセーフをcriticalへ昇格 rssMB=\(diagnosticsResidentMemoryMBText())",
                critical: true,
                file: #fileID,
                line: #line,
                function: #function
            )
        }

        let handlerAfterCensusSnapshot = MemoryForensics.snapshot()
        kanaKanjiConverter.clearAllCaches()

        // 解放済みヒープを OS へ返す。census 実測(2545)で、警告時の footprint 60MB のうち
        // malloc アリーナが 68MB(実使用 38.7MB)=約29MB が「free 済みだが dirty なまま
        // footprint に残るページ」だった。変換ラティス等の一時ピークで育ったアリーナは
        // 放っておくと返らないため、警告時に明示的に返却して jetsam 圧を下げる。
        do {
            var before = malloc_statistics_t()
            malloc_zone_statistics(nil, &before)
            malloc_zone_pressure_relief(nil, 0)
            var after = malloc_statistics_t()
            malloc_zone_statistics(nil, &after)
            appendKeyboardDiagnosticsLog(
                "mallocアリーナ返却 allocMB=\(String(format: "%.1f", Double(before.size_allocated) / 1_048_576))"
                    + "→\(String(format: "%.1f", Double(after.size_allocated) / 1_048_576))"
                    + " usedMB=\(String(format: "%.1f", Double(after.size_in_use) / 1_048_576))"
                    + " footprintMB=\(diagnosticsFootprintMBText())",
                critical: true,
                file: #fileID,
                line: #line,
                function: #function
            )
        }

        do {
            let exitSnapshot = MemoryForensics.snapshot()
            func fmt(_ value: Double) -> String { String(format: "%.1f", value) }
            appendKeyboardDiagnosticsLog(
                "警告ハンドラ自己コスト fp=\(fmt(handlerEntrySnapshot.fpMB))→\(fmt(handlerAfterCensusSnapshot.fpMB))(診断後)→\(fmt(exitSnapshot.fpMB))(解放後)"
                    + " alloc=\(fmt(handlerEntrySnapshot.allocMB))→\(fmt(handlerAfterCensusSnapshot.allocMB))→\(fmt(exitSnapshot.allocMB))"
                    + " used=\(fmt(handlerEntrySnapshot.usedMB))→\(fmt(handlerAfterCensusSnapshot.usedMB))→\(fmt(exitSnapshot.usedMB))",
                critical: true,
                file: #fileID,
                line: #line,
                function: #function
            )
        }

        // 警告が重なるときは非アクティブ個体を積極的に手放す(2658、ユーザ指定の段階制)。
        // 通常のゾンビ解放はオーナー確認や滞留時間の条件を課しているが、警告3回目以降は
        // 「まだ純正へ落ちてはいないが危ない」状態なので、表示中でない全個体のビュー階層と
        // キャッシュを即座に捨てる(1体あたりフレームワーク状態が3〜4MB)。
        // 表示中の個体は window を持つので対象にならない
        if diagnosticsState.memoryWarningCountThisSession >= Self.aggressiveInactiveReleaseWarningCount {
            var releasedCount = 0
            for controller in KeyboardViewController.liveControllerCensus.allObjects
            where controller !== self && controller.viewIfLoaded?.window == nil {
                controller.kanaKanjiConverter.clearAllCaches()
                let warningReason = "memoryWarning×\(diagnosticsState.memoryWarningCountThisSession)"
                if controller.lostActiveOwnershipAt > 0 {
                    controller.releaseHostingViewIfZombie(
                        reason: warningReason,
                        ignoringWindowAttachment: true
                    )
                } else {
                    // 降格経路を通っていない個体は releaseHostingViewIfZombie が先頭で弾く(3199)。
                    // 警告3回目まで来たら、忘れられた離脱個体こそ真っ先に手放したい
                    controller.releaseDetachedKeyboardResources(
                        reason: "forgottenDetached-\(warningReason)",
                        logLabel: "忘れられた離脱個体の保持物を解放"
                    )
                }
                releasedCount += 1
            }
            if releasedCount > 0 {
                malloc_zone_pressure_relief(nil, 0)
                appendKeyboardDiagnosticsLog(
                    "警告\(diagnosticsState.memoryWarningCountThisSession)回目のため非表示個体を強制解放"
                        + " count=\(releasedCount) footprintMB=\(diagnosticsFootprintMBText())",
                    critical: true,
                    file: #fileID,
                    line: #line,
                    function: #function
                )
            }
        }

        // 2回目以降の警告は圧迫が続いている証拠なので、LMキャッシュを縮小モードへ
        // (上限を下げて再成長を抑える。変換品質は維持)。初回警告は ef56d52 の方針
        // どおり通常キャッシュ破棄のみで変換品質を守る。
        if diagnosticsState.memoryWarningCountThisSession >= 2 {
            kanaKanjiConverter.store.enterConstrainedMemoryCacheMode()
            appendKeyboardDiagnosticsLog(
                "メモリ警告\(diagnosticsState.memoryWarningCountThisSession)回目のためLMキャッシュを縮小モードへ footprintMB=\(diagnosticsFootprintMBText())",
                critical: true,
                file: #fileID,
                line: #line,
                function: #function
            )
            // sqlite の最終手段アンロード(footprint 115 以上で閉じる)は 2769 で撤去。上限 77MB に
            // 到達不能な条件で、閉じても約 2MB しか返らず UX 全損だけが残る設計だった
        }

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

        // 高さの設置/更新は描画設定を引数に取らない(どちらも自身で読む)。以前は
        // 直近の描画設定を渡していた名残で束縛だけが残っていた(2848 で除去)。
        installKeyboardHeightConstraintIfNeeded()
        updateKeyboardHeightIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateBackgroundGradientAppearance()

        let configuration = lastRenderConfiguration ?? makeRenderConfiguration()
        installKeyboardHeightConstraintIfNeeded()
        updateKeyboardHeightIfNeeded()

        updateKeyboardVisualVisibility(using: configuration)
        logKeyboardHeightMismatchIfChanged()

        guard lastRenderConfiguration != nil else {
            return
        }

        applyKeyboardBaseBackground()

        // 実幅が描画時の見積もりと違えば作り直す(初回は幅 0 で描き、レイアウト後に確定。
        // iPad 互換モードの箱幅や回転で変わる。2786)
        let frame = Self.roundedToHalfPoint(view.convert(view.bounds, to: nil))
        guard frame.width > 0, frame != configuration.containerFrame else {
            return
        }
        // 初回(未計測=zero)は UIScreen 全幅を仮定して描いている。実枠がその仮定どおり
        // (左端 0・画面全幅=iPhone の通常表示)なら作り直す必要はない。作り直すのは
        // iPad 互換モードの箱など仮定と違うときだけ(2787: 全機種で毎回 2 回描いていた)
        if configuration.containerFrame == .zero,
            frame.minX == 0,
            abs(frame.width - UIScreen.main.bounds.width) < 0.5 {
            return
        }
        refreshKeyboardState(trigger: "containerFrame")
    }

    // 回転(サイズ遷移)の正規の入口。UIKit はここで遷移先サイズを確定値として渡す。
    //
    // これが無いと、回転は traitCollectionDidChange と毎フレームのレイアウトパスでしか
    // 拾えない。どちらもアニメーションの途中で走るため、window/view から読んだ中間状態の
    // ジオメトリ(向きだけ先に切り替わった状態、確定していないセーフエリア)で高さを算出し、
    // それをホストへ publish してしまう。実機ログでは 242→255→176→242 と揺れ、
    // ホスト側は placeholder 300(正しくは317)を掴んだまま固定され、メッセージ.app で
    // 会話の最終行が入力欄の下に潜り込んでいた(2026-09-02 再現、画面オフ→オンで解消)。
    override func viewWillTransition(
        to size: CGSize,
        with coordinator: any UIViewControllerTransitionCoordinator
    ) {
        pendingSizeTransitionTargetSize = size
        // 向きが変わると枠の高さはホストが取り直すので、その向きの最大の高さも通し直す(3160)
        didPrimeMaximumKeyboardHeight = false
        // 遷移先の高さを、他の処理より先に publish する(2865)。ホストは遷移を始めてから
        // 約 15ms で本文の余白(KeyboardLayoutGuide)を確定させる。実機ログでは écritu の
        // 正しい値が届くのが 53ms 後で、ホストは古い高さで guide を決めてから 400ms 後に
        // 訂正していた。純正キーボードは guide を一度しか設定せず、最初から正しい値。
        // super とレイアウト計算(SwiftUI の再配置)を挟むと 40ms 遅れるので、
        // プロパティの代入だけを先に済ませる。幅も遷移先の値を使う(view.bounds はまだ旧幅)
        synchronizePreferredContentSize(
            height: effectivePreferredKeyboardHeight(),
            widthOverride: size.width
        )
        super.viewWillTransition(to: size, with: coordinator)

        // 遷移先の確定値でレイアウトを合わせる。
        installKeyboardHeightConstraintIfNeeded()
        updateKeyboardHeightIfNeeded()

        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            guard let self else {
                return
            }
            // 遷移完了。ここで初めて window/view のジオメトリが確定するので、
            // 確定値で再算出してホストと同期し直す。
            pendingSizeTransitionTargetSize = nil
            installKeyboardHeightConstraintIfNeeded()
            updateKeyboardHeightIfNeeded()
            // 回転は面を丸ごと組み直す。前の向きのぶんは解放されても malloc が
            // ページを抱えたままで footprint が下がらない(横画面で警告が出やすかった。3186)
            performRotationMemoryTrim()
        }
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

        installKeyboardHeightConstraintIfNeeded()
        updateKeyboardHeightIfNeeded()
    }

    // 調査用(3136): UIKit が触れたと判断した時刻を記録するだけの認識器。状態を変えないので他の操作を邪魔しない。
    // 押下表示(緑)が出るまでの体感の遅さが、UIKit→SwiftUI の受け渡しにあるのかを測るために入れた。原因判明後に外す
    private final class RawTouchProbeGestureRecognizer: UIGestureRecognizer {
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            KeyboardStuckTouchDiagnostics.lastRawTouchBeganAt = CFAbsoluteTimeGetCurrent()
            if let view, let touch = touches.first {
                KeyboardStuckTouchDiagnostics.lastRawTouchLocation = touch.location(in: view)
            }
            // 遅れが「指→拡張プロセス」で生じているのか「拡張プロセスの中」なのかを分ける(3148)。
            // UITouch.timestamp は端末が指を検出した時刻(systemUptime と同じ基準)なので、
            // 受け取った瞬間との差が iOS 側の配信遅れになる。あわせてメインキューに空の仕事を
            // 積み、それが走るまでの時間でメインスレッドの詰まりを測る
            let deliveryDelayMs = touches.first.map {
                Int((ProcessInfo.processInfo.systemUptime - $0.timestamp) * 1000)
            } ?? -1
            let queuedAt = CFAbsoluteTimeGetCurrent()
            DispatchQueue.main.async {
                let mainDelayMs = Int((CFAbsoluteTimeGetCurrent() - queuedAt) * 1000)
                if deliveryDelayMs > 30 || mainDelayMs > 30 {
                    KeyboardStuckTouchDiagnostics.onTouchForensics?(
                        "生タッチの内訳 配信遅れ\(deliveryDelayMs)ms メインの詰まり\(mainDelayMs)ms"
                    )
                }
            }
            // この touch を追っている認識器の一覧(3161)。縦画面でだけ 750ms 遅れる原因が
            // システム側のジェスチャー調停なら、ここに名前が出る。delaysTouchesBegan も添える
            if let touch = touches.first {
                let names = (touch.gestureRecognizers ?? []).map { recognizer -> String in
                    let name = String(describing: type(of: recognizer))
                    return recognizer.delaysTouchesBegan ? name + "(遅延あり)" : name
                }
                KeyboardStuckTouchDiagnostics.onTouchForensics?(
                    "生タッチの認識器 \(names.joined(separator: ", "))"
                )
            }
            // ログの時刻そのもので突き合わせるため、生のタッチ側にも 1 行残す(差分計算の当てにならなさを排除)
            KeyboardStuckTouchDiagnostics.onTouchForensics?("生タッチ began n=\(touches.count)")
            super.touchesBegan(touches, with: event)
        }

        // 指を離した時刻も残す(3152)。SwiftUI の判定が離した後に来ているのかを見る
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            KeyboardStuckTouchDiagnostics.onTouchForensics?("生タッチ ended")
            super.touchesEnded(touches, with: event)
        }
    }

    // 画面下端のシステム操作の門番(_UISystemGestureGate…)は、触れてから約 0.75 秒 touch を
    // 保留してから配る。縦画面では最下段がその帯に入るため、キーが緑になるまで 750ms かかっていた
    // (実測: 縦 753〜756ms / 横 78〜85ms。事象の時刻から数えても 775ms。3161 で名指しした)。
    // 純正キーボードにこの遅れは無い。拡張からは preferredScreenEdgesDeferringSystemGestures が
    // 効かない(3150 で実証)ので、キーボードの窓に付いている門番の「配る前に待つ」指定だけを外す。
    // システム操作そのものは生きたままで、認識されれば従来どおりこちらの touch は取り消される(3172)
    func relaxSystemGestureGateDelayIfNeeded() {
        var views: [UIView] = []
        var node: UIView? = view
        while let current = node {
            views.append(current)
            node = current.superview
        }
        if let window = view.window {
            views.append(window)
        }

        var relaxed = 0
        for target in views {
            for recognizer in target.gestureRecognizers ?? [] {
                guard String(describing: type(of: recognizer)).contains("SystemGestureGate") else {
                    continue
                }
                // 3173 で門番自体を止めた(isEnabled = false)ところ、ホストアプリ(メモ)が
                // 2 回落ちた(ユーザー報告 3181。クラッシュレポートは未生成だが、入れた直後から
                // 起きている)。システムの認識器を止めるのは踏み込みすぎと判断して取り消す。
                // 待ちの指定を外すだけなら実害が無いことは確認済みなので、そちらは残す(効果も無い)
                recognizer.delaysTouchesBegan = false
                relaxed += 1
            }
        }

        guard relaxed > 0 else {
            return
        }
        appendKeyboardDiagnosticsLog(
            "システム操作の門番の待ちを外した \(relaxed)個",
            critical: true
        )
    }

    private func installRawTouchProbeIfNeeded() {
        #if DEBUG
        let probe = RawTouchProbeGestureRecognizer(target: nil, action: nil)
        probe.cancelsTouchesInView = false
        probe.delaysTouchesBegan = false
        probe.delaysTouchesEnded = false
        view.addGestureRecognizer(probe)
        #endif
    }

    private func setupKeyboardView() {
        installRawTouchProbeIfNeeded()
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
        // 双子起動(iOSが数百msの間に2インスタンスを連続生成)では、双方の起動処理が重なり
        // 単独なら~35MBの起動時footprintが2倍化して60MB枠に接触する(2026-08-01 15:35の
        // 警告3連打の実測)。多重生存中は bootstrap(補助語彙+共有プリウォーム+辞書
        // プリロード予約)を追加遅延し、敗者インスタンスのdeinit(実測~2秒)とピークをずらす。
        var delay = 0.2
        if KeyboardViewController.liveControllerCensus.allObjects.count >= 2 {
            delay = 2.0
            appendKeyboardDiagnosticsLog("多重生存のためbootstrapを遅延 delaySec=\(delay)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
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
            // 長寿命データの先行確保(2703)は A/B(2713 vs 2714)で malloc 半端分に差が無く撤去(2715)。
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
    // 自前で deleteBackward を発行した直後にキャッシュ末尾を縮めて XPC 再取得を回避する。
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

        if let footprintMB = currentFootprintMB(),
            footprintMB >= Self.maximumFootprintMBForSystemDictionaryPreload {
            updateKeyboardDiagnosticsHeartbeat(
                event: "システム辞書プリロードを省略 footprintMB=\(String(format: "%.1f", footprintMB)) thresholdMB=\(String(format: "%.1f", Self.maximumFootprintMBForSystemDictionaryPreload)) physicalMemoryGB=\(physicalMemoryGBText())",
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
        updateKeyboardHeightIfNeeded()

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

        // 候補バー系(未確定/変換候補/英字サジェスト)だけの変化なら、rootView を差し替えず
        // モデルの publish だけで更新する。差し替えは view ツリー全体の再構築+同期
        // layoutIfNeeded を伴い、毎打鍵では最も高くつく(キー盤面は不変のまま)。
        let previousConfiguration = lastRenderConfiguration
        lastRenderConfiguration = configuration
        updateCandidateBarModel(from: configuration)

        if let previousConfiguration,
            configuration.equalIgnoringCandidateBar(previousConfiguration),
            hostingController != nil {
            return
        }

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

    // キーボード上辺の角 R(2920)。メッセージ/メモ/メイル等 Apple 純正アプリは入力領域に角丸のグレイを描くので、
    // 四角のまま塗ると桜色が角からはみ出して見えた。角は透明にしてホスト側の描画に馴染ませる。
    // コンテナの clipsToBounds は false のまま(長押しパネルやフリック案内がキーボードの外に描くため)
    static let keyboardBackgroundCornerRadius: CGFloat = 12

    private func applyKeyboardBaseBackground() {
        // 下地は透明。塗りは backgroundGradientLayer が全域に行う(角 R の外はホストが見える)
        view.backgroundColor = .clear
        inputView?.backgroundColor = .clear
        hostingController?.view.backgroundColor = .clear
        installBackgroundGradientLayerIfNeeded()
        updateBackgroundGradientAppearance()
    }

    private func installBackgroundGradientLayerIfNeeded() {
        guard backgroundGradientLayer == nil else {
            return
        }

        let layer = CAGradientLayer()
        layer.startPoint = CGPoint(x: 0.5, y: 0)
        layer.endPoint = CGPoint(x: 0.5, y: 1)
        layer.cornerRadius = Self.keyboardBackgroundCornerRadius
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        layer.needsDisplayOnBoundsChange = true
        view.layer.insertSublayer(layer, at: 0)
        backgroundGradientLayer = layer
    }

    // 色(テーマ×明暗)と寸法を view.bounds に合わせる。安全領域を経由しないので横画面でも端まで塗れる
    func updateBackgroundGradientAppearance() {
        guard let backgroundGradientLayer else {
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backgroundGradientLayer.frame = view.bounds
        let rawValue = lastRenderConfiguration?.keyboardBackgroundThemeRawValue
            ?? sharedStringValue(
                from: sharedDefaults,
                key: SharedDefaultsKeys.keyboardBackgroundTheme,
                fallback: "bleu"
            )
        let theme = KeyboardRootView.KeyboardBackgroundTheme(rawValue: rawValue) ?? .bleu
        let scheme: ColorScheme = traitCollection.userInterfaceStyle == .dark ? .dark : .light
        let stops = theme.gradientStops(for: scheme)
        backgroundGradientLayer.colors = stops.map { UIColor($0.color).cgColor }
        backgroundGradientLayer.locations = stops.map { NSNumber(value: Double($0.location)) }
        CATransaction.commit()
    }

    private func prepareKeyboardVisualForTransition() {
        view.alpha = 1
        hostingController?.view.alpha = 1
    }

    private func updateKeyboardVisualVisibility(using _: RenderConfiguration) {
        // 表示直後の高さ落ち着き待ち(定義コメント参照。3100): view の高さが要求値から 1pt 超ずれている間は
        // 面を隠す。一致するか期限を過ぎたら見せる。回転などの通常時は awaiting=false なので素通り
        if isAwaitingInitialHeightSettle {
            let expectedHeight = keyboardHeightConstraint?.constant ?? effectivePreferredKeyboardHeight()
            let actualHeight = view.bounds.height
            let settled = abs(actualHeight - expectedHeight) <= 1
            let timedOut = CFAbsoluteTimeGetCurrent() >= initialHeightSettleDeadline
            if !settled && !timedOut {
                view.alpha = 0
                return
            }
            isAwaitingInitialHeightSettle = false
            // 通常経路(1 フレームで一致)はログしない。期限切れで見せたときだけ残す(3116 でログ整理)
            if view.alpha != 1, timedOut {
                appendKeyboardDiagnosticsLog(
                    "表示ゲート 期限切れで表示 view=\(Int(actualHeight)) 期待=\(Int(expectedHeight))",
                    file: #fileID, line: #line, function: #function
                )
            }
        }

        if view.alpha != 1 {
            view.alpha = 1
        }

        if hostingController?.view.alpha != 1 {
            hostingController?.view.alpha = 1
        }
    }

    func latinSuggestions(prefix: String, limit: Int) -> [String] {
        kanaKanjiStore.latinSuggestions(prefix: prefix, limit: limit)
    }
}
