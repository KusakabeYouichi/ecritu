import Foundation
import SwiftUI
import UIKit

#if DEBUG
// 調査用(3145): 候補欄の上の余白が時々ほとんど無くなる件。原因が分かったら外す。
// 実際に描かれた「スクロール枠の上端」と「チップの上端」の差を測り、指定した余白
// (kanaCandidateHeaderTopPadding)とずれた瞬間だけ 1 行残す。SwiftUI 側から呼ぶので
// ビュー(値型)に状態を持たせず、ここへ置く
enum KeyboardCandidateBarLayoutForensics {
    static var onReport: ((String) -> Void)?
    nonisolated(unsafe) static var scrollTopY: CGFloat = .nan
    nonisolated(unsafe) static var contentTopY: CGFloat = .nan
    nonisolated(unsafe) static var lastReportedGap: CGFloat = .nan

    static func note(scrollTopY newScrollTopY: CGFloat? = nil, contentTopY newContentTopY: CGFloat? = nil, expected: CGFloat) {
        if let newScrollTopY {
            scrollTopY = newScrollTopY
        }
        if let newContentTopY {
            contentTopY = newContentTopY
        }
        guard scrollTopY.isFinite, contentTopY.isFinite else {
            return
        }
        let gap = ((contentTopY - scrollTopY) * 2).rounded() / 2
        guard !lastReportedGap.isFinite || abs(gap - lastReportedGap) > 0.5 else {
            return
        }
        lastReportedGap = gap
        onReport?("候補欄の余白 実測=\(gap)pt 指定=\(expected)pt 枠上端=\(Int(scrollTopY)) チップ上端=\(Int(contentTopY))")
    }
}

#endif

// 候補バー系の状態(未確定文字列/変換候補/選択位置/英字サジェスト)。毎打鍵で変わるのは
// ここだけなので、rootView 差し替えではなく publish で更新して SwiftUI に差分再評価させる。
final class KeyboardCandidateBarModel: ObservableObject {
    @Published var composingText: String = ""
    // tokushima(3211): 候補欄に出す未確定(下線付き)。他の方式では空
    @Published var internalCompositionPreviewText: String = ""
    @Published var conversionCandidates: [String] = []
    @Published var selectedConversionCandidateIndex: Int? = nil
    @Published var latinSuggestionQuery: String = ""
    @Published var latinSuggestions: [String] = []
    // 後置修飾ボタン(濁点/小書き/顔文字)の状態。直前文脈で毎打鍵変わるため、rootView 差し替え
    // ではなく publish で渡す(2686)。以前は RenderConfiguration 経由だったので「か/は/つ」等を
    // 打つたびに候補バー除外判定をすり抜けて全キーを作り直していた
    @Published var kanaPostModifierButtonState: KanaPostModifierButtonState = .kaomoji
    // メモリ切迫の可視化(でばぐ用途。後で取り除く可能性あり)。かな削除キーの背景色に反映:
    // 1回目=黄 / 2回目以降=橙+回数(えんじ=sqlite アンロードは 2769 で撤去)。
    @Published var memoryWarningCountForDebugDisplay: Int = 0
    @Published var memoryWarningBurstCountForDebugDisplay: Int = 0
    // このセッションの footprint 最大値(MB、切り上げ)。赤くなる描画異常の調査用: 画面を撮るのは現象の後なので
    // 現在値では「そのとき切迫していたか」が分からない。警告(62MB 手前)より下の帯もこれなら見える(2918)
    @Published var memoryFootprintPeakMBForDebugDisplay: Int = 0
    // プロセス生涯の footprint 最大値。セッション側は表示のたびに 0 に戻るので、
    // 「いつか 45 を超えた」記録はこちらにしか残らない(ユーザ指定 2924)
    @Published var memoryFootprintProcessPeakMBForDebugDisplay: Int = 0
}

enum KeyboardThemePalette {
    static let keyLabel = Color(uiColor: .label)
    static let keyLabelSecondary = Color(uiColor: .secondaryLabel)

    static let keyBackground = Color(uiColor: .secondarySystemBackground).opacity(0.92)
    static let keyBackgroundDisabled = Color(uiColor: .tertiarySystemFill).opacity(0.92)
    static let keyBorder = Color(uiColor: .separator).opacity(0.42)
    static let keyBorderEmphasis = Color(uiColor: .separator).opacity(0.62)
    static let keyStrokeOnAccent = Color.white.opacity(0.32)

    static let categoryButtonBackground = Color(uiColor: .tertiarySystemBackground).opacity(0.9)
    static let categoryButtonBackgroundSelected = Color(uiColor: .secondarySystemBackground)

    static let candidateHeaderChipBackground = Color(uiColor: .secondarySystemBackground).opacity(0.82)
    static let candidateHeaderSubtleBackground = Color(uiColor: .secondarySystemBackground).opacity(0.68)
    static let candidateHeaderPlaceholderBackground = Color(uiColor: .tertiarySystemFill).opacity(0.9)
    static let candidateHeaderBorder = Color(uiColor: .separator).opacity(0.38)

    static let longPressPanelText = Color(uiColor: .label)
    static let longPressPanelCellBackground = Color(uiColor: .tertiarySystemBackground)
    static let longPressPanelCellHighlight = Color(
        uiColor: UIColor { trait in
            if trait.userInterfaceStyle == .dark {
                return UIColor(red: 0.24, green: 0.33, blue: 0.49, alpha: 1.0)
            }

            return UIColor(red: 0.84, green: 0.89, blue: 1.0, alpha: 1.0)
        }
    )
    static let longPressPanelBackground = Color(uiColor: .secondarySystemBackground)
    static let longPressPanelBorder = Color(uiColor: .separator).opacity(0.45)
    static let longPressPanelShadow = Color.black.opacity(0.18)

    static let pressFeedbackCircle = Color(
        uiColor: UIColor { trait in
            if trait.userInterfaceStyle == .dark {
                return UIColor.white.withAlphaComponent(0.18)
            }

            return UIColor.black.withAlphaComponent(0.15)
        }
    )
    static let pressFeedbackRounded = Color(
        uiColor: UIColor { trait in
            if trait.userInterfaceStyle == .dark {
                return UIColor.white.withAlphaComponent(0.14)
            }

            return UIColor.black.withAlphaComponent(0.12)
        }
    )
    static let pressFeedbackRoundedBorder = Color(
        uiColor: UIColor { trait in
            if trait.userInterfaceStyle == .dark {
                return UIColor.white.withAlphaComponent(0.2)
            }

            return UIColor.black.withAlphaComponent(0.16)
        }
    )
    static let thinDivider = Color(uiColor: .separator).opacity(0.5)
}

#if DEBUG
// 調査用(3163): 面の中身が枠からはみ出していないか。ZStack は中身を中央に置くので、
// 中身が枠より高いと上下に同じだけはみ出す(= 上の余白が消える / 上下が切れる)。
// 中身の上端・下端を枠の座標で残す。原因が分かったら外す
enum KeyboardRootOverflowForensics {
    static var onReport: ((String) -> Void)?
    nonisolated(unsafe) static var lastTop: CGFloat = .nan

    static func note(top: CGFloat, bottom: CGFloat) {
        guard !lastTop.isFinite || abs(top - lastTop) > 0.5 else {
            return
        }
        lastTop = top
        onReport?("面の中身 上端=\(Int(top)) 下端=\(Int(bottom))")
    }
}

struct KeyboardRootOverflowProbe: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { report(proxy.frame(in: .global)) }
                    .onChange(of: proxy.frame(in: .global).minY) { _ in
                        report(proxy.frame(in: .global))
                    }
            }
        )
    }

    private func report(_ frame: CGRect) {
        KeyboardRootOverflowForensics.note(top: frame.minY, bottom: frame.maxY)
    }
}

#endif

// 調査用(3145): 候補欄の上余白の実測。DEBUG 以外では何もしない
struct CandidateBarTopMarginProbe: ViewModifier {
    let expected: CGFloat
    let isContent: Bool

    func body(content: Content) -> some View {
        #if DEBUG
        content.background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { report(proxy.frame(in: .global).minY) }
                    .onChange(of: proxy.frame(in: .global).minY) { value in
                        report(value)
                    }
            }
        )
        #else
        content
        #endif
    }

    #if DEBUG
    private func report(_ minY: CGFloat) {
        if isContent {
            KeyboardCandidateBarLayoutForensics.note(contentTopY: minY, expected: expected)
        } else {
            KeyboardCandidateBarLayoutForensics.note(scrollTopY: minY, expected: expected)
        }
    }
    #endif
}

// 面の中身を、与えられた高さに収める(3170)。横画面では ホストが枠を広げてくれず
// (3156-3162 の実測)、記号・絵文字・顔文字・部首・書式化の中身が枠より高くて上下が
// 切れていた。中身は自然な高さで組んでから、入りきらないときだけ縮める。
// 縮尺はレイアウトの大きさを変えないので、測った自然な高さが揺れ戻ることはない
private struct KeyboardPanelNaturalHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct KeyboardPanelFitsProposedHeightModifier: ViewModifier {
    @State private var naturalHeight: CGFloat = 0

    func body(content: Content) -> some View {
        GeometryReader { proxy in
            let available = proxy.size.height
            let scale = (available > 0 && naturalHeight > available + 0.5)
                ? available / naturalHeight
                : 1
            content
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    GeometryReader { inner in
                        Color.clear.preference(
                            key: KeyboardPanelNaturalHeightKey.self,
                            value: inner.size.height
                        )
                    }
                )
                .scaleEffect(scale, anchor: .top)
                .frame(width: proxy.size.width, height: available, alignment: .top)
        }
        .onPreferenceChange(KeyboardPanelNaturalHeightKey.self) { value in
            if abs(value - naturalHeight) > 0.5 {
                naturalHeight = value
            }
        }
    }
}

// スクロールの縁に出る効果(Liquid Glass のぼかし。上の縁から下へ弱まる)を切る(3106)。
// API は iOS 26 からだが、描かれ始めるのは実測で 27(iPhone 15 は 26.6 では出ず 27 で出た。
// テスターの iPhone 15 Pro/27 は候補バーの中身が上 6 割ほどぼやけた ─ 画像 IMG_0235)。
// 当てる先は面ごと ─ 根にまとめて被せると候補欄の上の余白まで消える(3122 で入れて 3140 で撤回)。
struct KeyboardScrollEdgeEffectHiddenModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectHidden(true, for: .all)
        } else {
            content
        }
    }
}

// 記号の一覧は、長押しの吹き出しが最上段で見切れないようクリップを外している(iOS17+)。
// ただし外すと下側も描かれるため、枠が詰まる横画面では中身が下段バーに重なって見えていた
// (ユーザー報告の画像 3190)。上だけ広げた覆いにして、下は枠で切る
private struct SymbolScrollClipDisabledModifier: ViewModifier {
    // 吹き出しが上へ出る余地(吹き出しの高さぶん)
    static let bubbleAllowance: CGFloat = 56

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content
                .scrollClipDisabled()
                .mask(
                    Rectangle()
                        .padding(.top, -Self.bubbleAllowance)
                        .ignoresSafeArea()
                )
        } else {
            content
        }
    }
}

extension KeyboardRootView {
    // 宣言順=カテゴリボタンの表示順(顔→食べ物→動物→行動→オブジェクト→乗り物→国旗→シンボル)。
    // rawValue は設定(kanaPostModifierEmptyTapEmojiCategoryID)に永続化されているため、
    // 並べ替えても歴史的な値を明示指定して互換を維持する。
    enum EmojiCategory: Int, CaseIterable, Identifiable {
        case people = 0
        case food = 2
        case animals = 1
        case activities = 3
        case objects = 5
        case travel = 4
        case flags = 7
        case symbols = 6

        var id: Int { rawValue }

        var icon: String {
            switch self {
            case .people: return "😀"
            case .animals: return "🦆"
            case .food: return "🍷"
            case .activities: return "🏀"
            case .travel: return "🚗"
            case .objects: return "💡"
            case .symbols: return "❤️"
            case .flags: return "🇫🇷"
            }
        }

        var frenchName: String {
            switch self {
            case .people: return "Personnes"
            case .animals: return "Animaux et nature"
            case .food: return "Nourriture et boissons"
            case .activities: return "Activités"
            case .travel: return "Voyages et lieux"
            case .objects: return "Objets"
            case .symbols: return "Symboles"
            case .flags: return "Drapeaux"
            }
        }

        var emojis: [String] {
            switch self {
            case .people:
                return AppleEmojiCatalog.people
            case .animals:
                return AppleEmojiCatalog.nature
            case .food:
                return AppleEmojiCatalog.foodAndDrink
            case .activities:
                return AppleEmojiCatalog.activity
            case .travel:
                return AppleEmojiCatalog.travelAndPlaces
            case .objects:
                return AppleEmojiCatalog.objects
            case .symbols:
                return AppleEmojiCatalog.symbols
            case .flags:
                return AppleEmojiCatalog.flags
            }
        }

        // サブグループ(区切り線で仕切る)。単一セクションのカテゴリは区切り線なし。
        // 国旗は動的分割(国→領土→その他)のため emojiScrollContent 側で特別扱い。
        var sections: [[String]] {
            switch self {
            case .people:
                return AppleEmojiCatalog.peopleSections
            case .animals:
                return AppleEmojiCatalog.natureSections
            case .food:
                return AppleEmojiCatalog.foodAndDrinkSections
            case .activities:
                return AppleEmojiCatalog.activitySections
            case .travel:
                return AppleEmojiCatalog.travelAndPlacesSections
            case .objects, .symbols, .flags:
                return [emojis]
            }
        }
    }

    struct KaomojiCategory: Identifiable, Hashable {
        enum Kind: Hashable {
            case shortcut
            case existing
            case imported(String)
            case search
        }

        let kind: Kind

        var id: String {
            switch kind {
            case .shortcut:
                return "shortcut"
            case .existing:
                return "existing"
            case .imported(let name):
                return "imported:\(name)"
            case .search:
                return "search"
            }
        }

        var title: String {
            switch kind {
            case .shortcut:
                return "Raccourcis (ショートカット)"
            case .existing:
                return "Base (基本)"
            case .imported(let name):
                switch KaomojiCatalog.canonicalCategoryKey(name) {
                case "rire":
                    return "Sourire / Rire (笑顔)"
                case "kawaii":
                    return "Kawaii / Chou (かわいい)"
                case "timide":
                    return "Timide (照れ)"
                case "panique":
                    return "Stress / Panique (焦り)"
                case "decu":
                    return "Déçu / Déprimé (がっかり)"
                case "triste":
                    return "Triste (悲しい)"
                case "colere":
                    return "En colère (怒り)"
                case "surprise":
                    return "Surprise (驚き)"
                case "dodo":
                    return "Dodo (眠い)"
                case "coucou":
                    return "Coucou (挨拶)"
                case "amour":
                    return "Amour (愛)"
                case "excite":
                    return "Excité / Crazy (興奮)"
                case "action":
                    return "Action (動き)"
                case "bizarre":
                    return "Bizarre (奇妙)"
                case "heros":
                    return "Héros (キャラ)"
                case "special":
                    return "Spécial (特殊)"
                case "lignes":
                    return "Lignes (区切り線)"
                default:
                    return name
                }
            case .search:
                return "Recherche (検索)"
            }
        }

        var icon: String {
            switch kind {
            case .shortcut:
                return "⚡️"
            case .existing:
                return "🙂"
            case .imported(let name):
                switch KaomojiCatalog.canonicalCategoryKey(name) {
                case "rire":
                    return "😂"
                case "kawaii":
                    return "🥰"
                case "timide":
                    return "😊"
                case "panique":
                    return "💦"
                case "decu":
                    return "😔"
                case "triste":
                    return "😢"
                case "colere":
                    return "😠"
                case "surprise":
                    return "😲"
                case "dodo":
                    return "😴"
                case "coucou":
                    return "🙋"
                case "amour":
                    return "❤️"
                case "excite":
                    return "💥"
                case "action":
                    return "🏃"
                case "bizarre":
                    return "🤪"
                case "heros":
                    return "🧑"
                case "special":
                    return "✨"
                case "lignes":
                    return "💬"
                default:
                    return "🗂️"
                }
            case .search:
                return "🔎"
            }
        }
    }

    enum BasicSymbolOrder: String {
        case ascii
        case ebcdic
        case ansi
    }

    enum SymbolCategory: Int, CaseIterable, Identifiable {
        case basic
        case brackets
        case currency
        case units
        case math
        case arrows
        case enclosed

        var id: Int { rawValue }

        func icon(temperatureUnit: TemperatureUnitPreference) -> String {
            switch self {
            case .basic: return "!?"
            case .brackets: return "『』"
            case .currency: return "€"
            case .units: return temperatureUnit.primarySymbol
            case .math: return "∑"
            case .arrows: return "↗"
            case .enclosed: return "⓪"
            }
        }

        var frenchName: String {
            switch self {
            case .basic: return "Symboles de base"
            case .brackets: return "Parenthèses et guillemets"
            case .currency: return "Monnaies"
            case .units: return "Unités"
            case .math: return "Mathématiques"
            case .arrows: return "Flèches"
            case .enclosed: return "Caractères entourés"
            }
        }

        var tintColor: Color {
            switch self {
            case .basic:
                return Color(red: 0.16, green: 0.40, blue: 0.86)
            case .brackets:
                return Color(red: 0.08, green: 0.60, blue: 0.48)
            case .currency:
                return Color(red: 0.10, green: 0.66, blue: 0.32)
            case .units:
                return Color(red: 0.92, green: 0.50, blue: 0.14)
            case .math:
                return Color(red: 0.77, green: 0.30, blue: 0.23)
            case .arrows:
                return Color(red: 0.48, green: 0.36, blue: 0.87)
            case .enclosed:
                return Color(red: 0.88, green: 0.26, blue: 0.57)
            }
        }

        func symbols(
            basicOrder: BasicSymbolOrder,
            temperatureUnit: TemperatureUnitPreference
        ) -> [String] {
            switch self {
            case .basic:
                let baseSymbols: [String]
                switch basicOrder {
                case .ascii:
                    baseSymbols = Self.basicSymbolsASCII
                case .ebcdic:
                    baseSymbols = Self.basicSymbolsEBCDIC
                case .ansi:
                    baseSymbols = Self.basicSymbolsANSI
                }
                return Self.basicSymbolsCommon + Self.basicSymbolsExtras + baseSymbols
            case .brackets:
                return Self.bracketAndQuoteSymbols
            case .currency:
                return Self.currencySymbols + Self.bitcoinSymbols + Self.cryptoAlternativeSymbols
            case .units:
                return Self.unitSymbols(for: temperatureUnit)
            case .math:
                return Self.mathSymbols
            case .arrows:
                return Self.arrowSymbols
            case .enclosed:
                return Self.enclosedSymbols
            }
        }

        // ASCII punctuation in code point order.
        private static let basicSymbolsASCII: [String] = [
            "!", "\"", "#", "$", "%", "&", "'", "(", ")", "*", "+", ",", "-", ".", "/",
            ":", ";", "<", "=", ">", "?", "@", "[", "\\", "]", "^", "_", "`", "{", "|", "}", "~"
        ]

        private static let basicSymbolsEBCDIC: [String] = [
            ".", "<", "(", "+", "|", "&", "!", "$", "*", ")", ";", "-", "/", ",", "%", "_",
            ">", "?", "`", ":", "#", "@", "'", "=", "\"", "~", "^", "[", "]", "{", "}", "\\"
        ]

        private static let basicSymbolsANSI: [String] = [
            "!", "@", "#", "$", "%", "^", "&", "*",
            "(", ")", "-", "_", "=", "+", "[", "]",
            "{", "}", ";", ":", "'", "\"", ",", ".",
            "<", ">", "/", "?", "\\", "|", "`", "~"
        ]

        // どの並び(ASCII/EBCDIC/ANSI)でも共通で出す記号。りんごマーク・⌘・中黒・矢印・和文括弧。
        // basic カテゴリーの先頭セクションに置く(ユーザー指定 2600: 共通記号 → 図形 →
        // ASCII/JIS の順。使用頻度の高いものを手前に)。
        static let basicSymbolsCommon: [String] = [
            "", "⌘", "☻", "・", "←", "↑", "→", "↓", "「", "」", "『", "』"
        ]

        // basicカテゴリーの2番目のセクションに置く図形記号(16個)。
        static let basicSymbolsExtras: [String] = [
            "○", "●", "△", "▲", "▽", "▼", "□", "■",
            "◇", "◆", "☆", "★", "◎", "×", "※", "✓"
        ]

        private static let bracketAndQuoteSymbols: [String] = [
            "(", ")", "[", "]", "{", "}", "<", ">",
            "『", "』", "「", "」", "【", "】", "〔", "〕", "〈", "〉", "《", "》",
            "“", "”", "‘", "’", "«", "»", "‹", "›", "〝", "〟"
        ]

        private static let currencySymbols: [String] = [
            "€", "$", "¢", "£", "¥", "₩", "₹", "₽", "₺", "฿", "₫", "₴", "₦", "₱", "₡", "₲", "₵", "₭", "₸", "₮", "₰", "₪", "₾", "﷼"
        ]

        // 通貨カテゴリー末尾に区切り線を挟んで配置する暗号資産記号。
        static let bitcoinSymbols: [String] = ["₿"]

        // 専用記号を持たない暗号資産の代替表記。
        static let cryptoAlternativeSymbols: [String] = [
            "Ξ", "⟠", "Ł", "Ð", "₳", "₮", "✕"
        ]

        // 長押し中に吹き出し表示する通貨コード(ISO-4217)。¢・₰はISOコードを持たないため割り当てない。
        static let currencyISOCodes: [String: String] = [
            "€": "EUR", "$": "USD", "£": "GBP", "¥": "JPY", "₩": "KRW",
            "₹": "INR", "₽": "RUB", "₺": "TRY", "฿": "THB", "₫": "VND",
            "₴": "UAH", "₦": "NGN", "₱": "PHP", "₡": "CRC", "₲": "PYG",
            "₵": "GHS", "₭": "LAK", "₸": "KZT", "₮": "MNT", "₪": "ILS",
            "₾": "GEL", "﷼": "SAR"
        ]

        // 長押し中に吹き出し表示する暗号資産のティッカーシンボル。
        static let cryptoTickerSymbols: [String: String] = [
            "₿": "BTC", "Ξ": "ETH", "⟠": "ETH", "Ł": "LTC",
            "Ð": "DOGE", "₳": "ADA", "₮": "USDT", "✕": "XRP"
        ]

        // 補助単位(ISO通貨コードを持たない)。吹き出しは別色・コードでなく名称を表示する。
        static let currencySubunitLabels: [String: String] = [
            "¢": "cent", "₰": "Pfennig"
        ]

        private static let unitSymbolsTail: [String] = [
            "°", "′", "″", "%", "‰", "μ", "Ω", "ℓ", "㎜", "㎝", "㎞", "㎡", "㎢", "㎥", "㎎", "㎏", "㏄", "㎖", "㎗", "㎐", "㎑", "㎒", "㎓"
        ]

        private static func unitSymbols(for temperatureUnit: TemperatureUnitPreference) -> [String] {
            switch temperatureUnit {
            case .celsius:
                return ["℃", "℉"] + unitSymbolsTail
            case .fahrenheit:
                return ["℉", "℃"] + unitSymbolsTail
            }
        }

        private static let mathSymbols: [String] = [
            "+", "-", "±", "×", "÷", "=", "≠", "≈", "≡", "<", ">", "≤", "≥", "¬", "∧", "∨", "⊻",
            "∀", "∃", "∞", "√", "∛", "∜", "∑", "∏", "∫", "∬", "∮", "∂", "∇",
            "∈", "∉", "∋", "∌", "∩", "∪", "⊂", "⊃", "⊆", "⊇", "⊄", "⊅", "∝", "∴", "∵", "⊥", "∠"
        ]

        private static let arrowSymbols: [String] = [
            "←", "↑", "→", "↓", "↔", "↕", "↖", "↗", "↘", "↙",
            "⇐", "⇑", "⇒", "⇓", "⇔", "⇕", "↩", "↪",
            "➔", "➜", "➝", "➞", "➟", "➠"
        ]

        private static let enclosedSymbols: [String] = [
            "©", "®", "⓪", "①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩", "⑪", "⑫", "⑬", "⑭", "⑮", "⑯", "⑰", "⑱", "⑲", "⑳",
            "㉑", "㉒", "㉓", "㉔", "㉕", "㉖", "㉗", "㉘", "㉙", "㉚",
            "Ⓐ", "Ⓑ", "Ⓒ", "Ⓓ", "Ⓔ", "Ⓕ", "Ⓖ", "Ⓗ", "Ⓘ", "Ⓙ", "Ⓚ", "Ⓛ", "Ⓜ", "Ⓝ", "Ⓞ", "Ⓟ", "Ⓠ", "Ⓡ", "Ⓢ", "Ⓣ", "Ⓤ", "Ⓥ", "Ⓦ", "Ⓧ", "Ⓨ", "Ⓩ",
            "ⓐ", "ⓑ", "ⓒ", "ⓓ", "ⓔ", "ⓕ", "ⓖ", "ⓗ", "ⓘ", "ⓙ", "ⓚ", "ⓛ", "ⓜ", "ⓝ", "ⓞ", "ⓟ", "ⓠ", "ⓡ", "ⓢ", "ⓣ", "ⓤ", "ⓥ", "ⓦ", "ⓧ", "ⓨ", "ⓩ"
        ]
    }

    enum KanaModeSwitcherAction: String {
        case emoji
        case kaomoji
        case symbols

        var keyLabel: String {
            switch self {
            case .emoji:
                return "☺︎"
            case .kaomoji:
                return "^_^"
            case .symbols:
                return "⌘"
            }
        }
    }

    enum LandscapeCandidateSide: String {
        case left
        case right
    }

    enum LandscapeLatinSuggestionMode: String {
        case sidebar
        case off
    }

    enum AccentPalette: String {
        case tuile
        case emeraude

        var color: Color {
            switch self {
            case .tuile:
                return Color(red: 136.0 / 255.0, green: 63.0 / 255.0, blue: 53.0 / 255.0)
            case .emeraude:
                return Color(red: 0.06, green: 0.73, blue: 0.56)
            }
        }
    }

    enum KeyboardBackgroundTheme: String {
        case bleu
        case sakura

        func gradientStops(for colorScheme: ColorScheme) -> [Gradient.Stop] {
            switch self {
            case .bleu:
                if colorScheme == .dark {
                    return [
                        .init(color: Color(red: 0.12, green: 0.14, blue: 0.18), location: 0.0),
                        .init(color: Color(red: 0.12, green: 0.21, blue: 0.30), location: 0.34),
                        .init(color: Color(red: 0.10, green: 0.17, blue: 0.25), location: 1.0)
                    ]
                }

                return [
                    .init(color: Color(red: 0.89, green: 0.90, blue: 0.92), location: 0.0),
                    .init(color: Color(red: 0.8, green: 0.86, blue: 0.95), location: 0.34),
                    .init(color: Color(red: 0.9, green: 0.95, blue: 1.0), location: 1.0)
                ]
            case .sakura:
                if colorScheme == .dark {
                    return [
                        .init(color: Color(red: 0.13, green: 0.13, blue: 0.16), location: 0.0),
                        .init(color: Color(red: 0.24, green: 0.18, blue: 0.23), location: 0.34),
                        .init(color: Color(red: 0.18, green: 0.14, blue: 0.20), location: 1.0)
                    ]
                }

                return [
                    .init(color: Color(red: 0.89, green: 0.90, blue: 0.92), location: 0.0),
                    .init(color: Color(red: 0.95, green: 0.84, blue: 0.88), location: 0.34),
                    .init(color: Color(red: 1.0, green: 0.94, blue: 0.96), location: 1.0)
                ]
            }
        }
    }

    struct KaomojiRowLayout {
        let items: [String]
        let spacing: CGFloat
    }
}

    struct KeyboardRootEmojiKeyboardSectionView: View {
        @Binding var selectedEmojiCategory: KeyboardRootView.EmojiCategory
        let keyboardRowSpacing: CGFloat
        let emojiGridColumns: [GridItem]
        let emojiGridSpacing: CGFloat
        let compactEmojiKeyHeight: CGFloat
        let mainFlickKeyHeight: CGFloat
        let fourRowAlignedTopContentHeight: CGFloat
        let fourRowAlignedClusterHeight: CGFloat
        let keyRepeatInitialDelay: TimeInterval
        let keyRepeatInterval: TimeInterval
        let onTextInput: (String) -> Void
        let onSwitchToKana: () -> Void
        // あい の長押しで出す面選択のパレット(3124)
        let onSelectModePalette: (String) -> Void
        // 横画面は 2 列に折る(3171)
        var paletteColumnCount: Int = 1
        // 下段バーの端のキー幅(3189)
        var returnKeyWidth: CGFloat = 56
        var deleteKeyWidth: CGFloat = 56
        let onDeleteBackward: () -> Void
        // 地球儀キーが要る機種(ホームボタン機)だけ非 nil。あい の右に 🌐 を置く(4.4.1。2785)
        var onAdvanceKeyboard: (() -> Void)? = nil
        // 圧迫可視化(削除キーの色/回数)。かなレイアウトの⌫と同じ状態を絵文字パネルでも見せる(2673)
        var deleteKeyBackgroundColorOverride: Color? = nil
        var deleteKeyCornerBadgeText: String? = nil

        var body: some View {
            VStack(spacing: keyboardRowSpacing) {
                // UIKit のセル再利用グリッド(2668)。SwiftUI の LazyVGrid+Text は生成したセルを
                // 閉じるまで保持し、描画済み絵文字1個ごとに 48KB の CGImage がシステムの
                // NSCache に溜まって退出でも消えなかった(601枚=27.3MB 実測)。
                EmojiGridCollectionView(
                    sections: emojiGridSections,
                    columnCount: emojiGridColumns.count,
                    itemSpacing: emojiGridSpacing,
                    itemHeight: compactEmojiKeyHeight,
                    dividerBlockHeight: 5 + keyboardRowSpacing,
                    longPressLabels: emojiLongPressLabels,
                    categoryKey: selectedEmojiCategory.rawValue,
                    onTextInput: onTextInput
                )
                .frame(height: fourRowAlignedTopContentHeight)

                HStack(spacing: keyboardRowSpacing) {
                    ReturnToKanaPaletteKey(
                        title: "あい",
                        fixedWidth: returnKeyWidth,
                        candidates: KeyboardRootView.modePaletteLabels,
                        paletteColumnCount: paletteColumnCount,
                        onReturn: onSwitchToKana,
                        onSelectCandidate: onSelectModePalette
                    )
                    .frame(height: mainFlickKeyHeight)
                    PanelAdvanceKeyboardKey(action: onAdvanceKeyboard, height: mainFlickKeyHeight)

                    ForEach(KeyboardRootView.EmojiCategory.allCases, id: \.self) { category in
                        EmojiCategoryKeyButton(
                            icon: category.icon,
                            isSelected: selectedEmojiCategory == category,
                            action: { selectedEmojiCategory = category }
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: mainFlickKeyHeight)
                    }

                    ActionKeyButton(
                        title: "⌫",
                        accessibilityLabel: "削除",
                        fontSize: 26,
                        fixedWidth: deleteKeyWidth,
                        repeatsWhileHolding: true,
                        repeatInitialDelay: keyRepeatInitialDelay,
                        repeatInterval: keyRepeatInterval,
                        backgroundColorOverride: deleteKeyBackgroundColorOverride,
                        cornerBadgeText: deleteKeyCornerBadgeText,
                        action: onDeleteBackward
                    )
                    .frame(height: mainFlickKeyHeight)
                }
                .frame(height: mainFlickKeyHeight)
            }
            .frame(height: fourRowAlignedClusterHeight, alignment: .top)
        }

        // 複数セクションのカテゴリー(顔/食べ物/動物/行動/乗り物)は、サブグループの間に
        // 区切り線を挟む。国旗は動的分割(国→領土→その他)のため特別扱い。
        private var emojiGridSections: [EmojiGridCollectionView.Section] {
            let sections = selectedEmojiCategory.sections
            if selectedEmojiCategory != .flags, sections.count > 1 {
                return sections.enumerated().map { index, section in
                    EmojiGridCollectionView.Section(emojis: section, showsDividerBefore: index > 0)
                }
            } else if selectedEmojiCategory == .flags {
                let territorySet = AppleEmojiCatalog.flagOverseasTerritories
                let nonCountrySet = Set(AppleEmojiCatalog.flagNonCountryNames.keys)
                let all = selectedEmojiCategory.emojis
                // {普通の国 → 海外領土・属領 → その他の旗} の順に区切り線で分ける。
                let countryFlags = all.filter { !territorySet.contains($0) && !nonCountrySet.contains($0) }
                let territoryFlags = all.filter { territorySet.contains($0) }
                let otherFlags = all.filter { nonCountrySet.contains($0) }
                var result = [EmojiGridCollectionView.Section(emojis: countryFlags, showsDividerBefore: false)]
                if !territoryFlags.isEmpty {
                    result.append(EmojiGridCollectionView.Section(emojis: territoryFlags, showsDividerBefore: true))
                }
                if !otherFlags.isEmpty {
                    result.append(EmojiGridCollectionView.Section(emojis: otherFlags, showsDividerBefore: true))
                }
                return result
            } else {
                return [EmojiGridCollectionView.Section(emojis: selectedEmojiCategory.emojis, showsDividerBefore: false)]
            }
        }

        // 国旗の押下吹き出し(国名。領土・その他は青系)
        private var emojiLongPressLabels: [String: (text: String, kind: SymbolInspectBubbleKind)] {
            guard selectedEmojiCategory == .flags else {
                return [:]
            }
            var labels: [String: (text: String, kind: SymbolInspectBubbleKind)] = [:]
            for emoji in selectedEmojiCategory.emojis {
                if let name = AppleEmojiCatalog.flagOfficialNames[emoji] {
                    labels[emoji] = (name, .standard)
                } else if let name = AppleEmojiCatalog.flagNonCountryNames[emoji] {
                    labels[emoji] = (name, .alternate)
                }
            }
            return labels
        }
    }

    struct KeyboardRootSymbolKeyboardSectionView: View {
        @Binding var selectedSymbolCategory: KeyboardRootView.SymbolCategory
        let basicSymbolOrder: KeyboardRootView.BasicSymbolOrder
        let temperatureUnit: TemperatureUnitPreference
        let keyboardRowSpacing: CGFloat
        let symbolGridColumns: [GridItem]
        let emojiGridSpacing: CGFloat
        let compactEmojiKeyHeight: CGFloat
        let mainFlickKeyHeight: CGFloat
        let fourRowAlignedTopContentHeight: CGFloat
        let fourRowAlignedClusterHeight: CGFloat
        let keyRepeatInitialDelay: TimeInterval
        let keyRepeatInterval: TimeInterval
        let onTextInput: (String) -> Void
        let onSwitchToKana: () -> Void
        // あい の長押しで出す面選択のパレット(3124)
        let onSelectModePalette: (String) -> Void
        // 横画面は 2 列に折る(3171)
        var paletteColumnCount: Int = 1
        // 下段バーの端のキー幅(3189)
        var returnKeyWidth: CGFloat = 56
        var deleteKeyWidth: CGFloat = 56
        let onDeleteBackward: () -> Void
        var onAdvanceKeyboard: (() -> Void)? = nil

        var body: some View {
            VStack(spacing: keyboardRowSpacing) {
                ScrollView(.vertical, showsIndicators: false) {
                    symbolCategoryContentView
                        .padding(.vertical, 2)
                }
                .frame(height: fourRowAlignedTopContentHeight)
                // 通貨記号の長押し吹き出しが最上段で見切れないようクリップを解除(iOS17+)。
                .modifier(SymbolScrollClipDisabledModifier())

                HStack(spacing: keyboardRowSpacing) {
                    ReturnToKanaPaletteKey(
                        title: "あい",
                        fixedWidth: returnKeyWidth,
                        candidates: KeyboardRootView.modePaletteLabels,
                        paletteColumnCount: paletteColumnCount,
                        onReturn: onSwitchToKana,
                        onSelectCandidate: onSelectModePalette
                    )
                    .frame(height: mainFlickKeyHeight)
                    PanelAdvanceKeyboardKey(action: onAdvanceKeyboard, height: mainFlickKeyHeight)

                    ForEach(KeyboardRootView.SymbolCategory.allCases, id: \.self) { category in
                        SymbolCategoryKeyButton(
                            icon: category.icon(temperatureUnit: temperatureUnit),
                            tintColor: category.tintColor,
                            isSelected: selectedSymbolCategory == category,
                            accessibilityLabel: category.frenchName,
                            action: { selectedSymbolCategory = category }
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: mainFlickKeyHeight)
                    }

                    ActionKeyButton(
                        title: "⌫",
                        accessibilityLabel: "削除",
                        fontSize: 26,
                        fixedWidth: deleteKeyWidth,
                        repeatsWhileHolding: true,
                        repeatInitialDelay: keyRepeatInitialDelay,
                        repeatInterval: keyRepeatInterval,
                        action: onDeleteBackward
                    )
                    .frame(height: mainFlickKeyHeight)
                }
                .frame(height: mainFlickKeyHeight)
            }
            .frame(height: fourRowAlignedClusterHeight, alignment: .top)
        }

        @ViewBuilder
        private var symbolCategoryContentView: some View {
            let symbols = selectedSymbolCategory.symbols(
                basicOrder: basicSymbolOrder,
                temperatureUnit: temperatureUnit
            )

            switch selectedSymbolCategory {
            case .basic:
                // 並びは 共通記号 → 図形 → ASCII/JIS。件数から素直に切る(末尾からの
                // 逆算とマジックナンバーをやめた)。
                let commonCount = KeyboardRootView.SymbolCategory.basicSymbolsCommon.count
                let extrasCount = KeyboardRootView.SymbolCategory.basicSymbolsExtras.count
                let commonEnd = min(symbols.count, commonCount)
                let extrasEnd = min(symbols.count, commonCount + extrasCount)
                let commonSymbols = Array(symbols.prefix(commonEnd))
                let shapeSymbols = Array(symbols[commonEnd..<extrasEnd])
                let punctuationSymbols = Array(symbols.dropFirst(extrasEnd))
                symbolGridSections([commonSymbols, shapeSymbols, punctuationSymbols])

            case .currency:
                let cryptoCount = KeyboardRootView.SymbolCategory.cryptoAlternativeSymbols.count
                let bitcoinCount = KeyboardRootView.SymbolCategory.bitcoinSymbols.count
                let cryptoStart = max(0, symbols.count - cryptoCount)
                let bitcoinStart = max(0, cryptoStart - bitcoinCount)
                let fiatSymbols = Array(symbols.prefix(bitcoinStart))
                let bitcoinSymbols = Array(symbols[bitcoinStart..<cryptoStart])
                let cryptoSymbols = Array(symbols.suffix(cryptoCount))
                let isoCodes = KeyboardRootView.SymbolCategory.currencyISOCodes
                let subunits = KeyboardRootView.SymbolCategory.currencySubunitLabels
                let fiatLabels = isoCodes.merging(subunits) { current, _ in current }
                let tickers = KeyboardRootView.SymbolCategory.cryptoTickerSymbols
                symbolGridSectionsLabeled([
                    (fiatSymbols, fiatLabels),
                    (bitcoinSymbols, tickers),
                    (cryptoSymbols, tickers)
                ])

            case .enclosed:
                let numberStart = symbols.firstIndex(of: "⓪")
                let upperStart = symbols.firstIndex(of: "Ⓐ")
                let lowerStart = symbols.firstIndex(of: "ⓐ")

                if let numberStart,
                    let upperStart,
                    let lowerStart,
                    numberStart < upperStart,
                    upperStart < lowerStart {
                    let markSymbols = Array(symbols[..<numberStart])
                    let numberSymbols = Array(symbols[numberStart..<upperStart])
                    let upperSymbols = Array(symbols[upperStart..<lowerStart])
                    let lowerSymbols = Array(symbols[lowerStart...])
                    symbolGridSections([markSymbols, numberSymbols, upperSymbols, lowerSymbols])
                } else {
                    symbolGridSection(symbols)
                }

            default:
                symbolGridSection(symbols)
            }
        }

        @ViewBuilder
        private func symbolGridSections(_ sections: [[String]]) -> some View {
            LazyVStack(alignment: .leading, spacing: keyboardRowSpacing) {
                ForEach(Array(sections.enumerated()), id: \.offset) { index, sectionSymbols in
                    symbolGridSection(sectionSymbols)

                    if index + 1 < sections.count {
                        let nextSectionSymbols = sections[index + 1]
                        if !sectionSymbols.isEmpty && !nextSectionSymbols.isEmpty {
                            symbolSectionDivider
                        }
                    }
                }
            }
        }

        @ViewBuilder
        private func symbolGridSectionsLabeled(
            _ sections: [(symbols: [String], labels: [String: String])]
        ) -> some View {
            LazyVStack(alignment: .leading, spacing: keyboardRowSpacing) {
                ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                    symbolGridSection(section.symbols, labels: section.labels)

                    if index + 1 < sections.count {
                        let nextSectionSymbols = sections[index + 1].symbols
                        if !section.symbols.isEmpty && !nextSectionSymbols.isEmpty {
                            symbolSectionDivider
                        }
                    }
                }
            }
        }

        private func symbolGridSection(
            _ symbols: [String],
            labels: [String: String]? = nil
        ) -> some View {
            let symbolFont: Font = selectedSymbolCategory == .enclosed
                ? .custom("HiraginoSans-W6", size: 24)
                : .system(size: 24, weight: .semibold, design: .rounded)

            return LazyVGrid(columns: symbolGridColumns, spacing: emojiGridSpacing) {
                ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                    let kind: SymbolInspectBubbleKind = KeyboardRootView.SymbolCategory.currencySubunitLabels[symbol] != nil
                        ? .subunit
                        : .standard
                    SymbolKeyButton(
                        symbol: symbol,
                        font: symbolFont,
                        longPressLabel: labels?[symbol],
                        longPressLabelKind: kind
                    ) {
                        onTextInput(symbol)
                    }
                    .frame(height: compactEmojiKeyHeight)
                }
            }
        }

        private var symbolSectionDivider: some View {
            Rectangle()
                .fill(KeyboardThemePalette.thinDivider)
                .frame(height: 1)
                .padding(.vertical, 2)
        }
    }

    struct KeyboardRootKanaCandidateHeaderView: View {
        let showsParenthesesWrapper: Bool
        let composingText: String
        // tokushima(3211): 候補の上に小さく出す未確定(下線付き)。空なら従来どおり
        var internalCompositionPreviewText: String = ""
        let conversionStateLabel: String
        let conversionStateIconName: String
        let conversionStateColor: Color
        let candidateStateFontSize: CGFloat
        let candidateTextFontSize: CGFloat
        let canTapComposingTextToCommit: Bool
        let showsKatakanaCommitFeedback: Bool
        let accentColor: Color
        let keyLabelColor: Color
        let conversionCandidates: [String]
        let selectedConversionCandidateIndex: Int?
        let kanaCandidateHeaderTopPadding: CGFloat
        let onSelectConversionCandidate: (Int) -> Void
        let onComposingTextCommitTap: () -> Void
        let onComposingTextCommitLongPress: () -> Void

        @ViewBuilder private var conversionCandidateChips: some View {
            if conversionCandidates.isEmpty {
                if !(showsParenthesesWrapper && composingText.isEmpty) {
                    // 変換候補が入力かなのみ=「候補なし」。文字ラベルでなく空集合アイコンで示す。
                    Image(systemName: "circle.slash")
                        .font(.system(size: candidateTextFontSize, weight: .regular))
                        .foregroundStyle(keyLabelColor.opacity(0.6))
                        .padding(.horizontal, 8)
                        .padding(.vertical, showsInternalCompositionPreview ? 2 : 4)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(KeyboardThemePalette.candidateHeaderPlaceholderBackground)
                        )
                        .accessibilityLabel("候補なし")
                }
            }

            ForEach(Array(conversionCandidates.enumerated()), id: \.offset) { index, candidate in
                let isSelected = selectedConversionCandidateIndex == index

                Button {
                    onSelectConversionCandidate(index)
                } label: {
                    // 括弧付き/なしでラベル内容だけ分岐し、チップの装飾(余白・背景・枠)は共通(2805 で 2 重を解消)
                    Group {
                        if showsParenthesesWrapper {
                            HStack(spacing: 0) {
                                Text("(")
                                    .foregroundStyle(isSelected ? Color.white : accentColor)
                                CandidateGlyphText(candidate, fontSize: candidateTextFontSize, color: isSelected ? Color.white : keyLabelColor)
                                Text(")")
                                    .foregroundStyle(isSelected ? Color.white : accentColor)
                            }
                            .font(.system(size: candidateTextFontSize, weight: .semibold))
                        } else {
                            CandidateGlyphText(candidate, fontSize: candidateTextFontSize, color: isSelected ? Color.white : keyLabelColor)
                        }
                    }
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, showsInternalCompositionPreview ? 2 : 4)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(
                                isSelected
                                    ? accentColor.opacity(0.9)
                                    : KeyboardThemePalette.candidateHeaderChipBackground
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(
                                KeyboardThemePalette.candidateHeaderBorder,
                                lineWidth: isSelected ? 0 : 1
                            )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(candidate)
                // かな識別(候補==入力かな)は末尾のかな確定チップと同様に
                // ロングタップでカタカナ確定できるようにする(挙動の一貫性)。
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.4)
                        .onEnded { _ in
                            if candidate == composingText {
                                onComposingTextCommitLongPress()
                            }
                        }
                )
                // 選択追従のスクロール先。ForEach の id と揃える。
                .id(index)
            }
        }

        // 末尾に「かなのみの候補」として出す(変換候補と同じチップ体裁)。タップで確定、
        // ロングタップでカタカナ確定。カタカナ確定フィードバック時はハイライト。
        @ViewBuilder private func composingKanaChip(_ text: String) -> some View {
            Text(text)
                .font(.system(size: candidateTextFontSize, weight: .semibold))
                .foregroundStyle(showsKatakanaCommitFeedback ? Color.white : keyLabelColor)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, showsInternalCompositionPreview ? 2 : 4)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(
                            showsKatakanaCommitFeedback
                                ? accentColor.opacity(0.9)
                                : KeyboardThemePalette.candidateHeaderChipBackground
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(
                            KeyboardThemePalette.candidateHeaderBorder,
                            lineWidth: showsKatakanaCommitFeedback ? 0 : 1
                        )
                )
        }

        // tokushima(3211): 未確定の行を上に足すぶん、チップ側の余白を詰めて 35pt の枠に収める
        private var showsInternalCompositionPreview: Bool {
            !internalCompositionPreviewText.isEmpty
        }

        // tokushima(3212): 状態カプセル(鉛筆/循環矢印)は未確定の行の左に置く。チップ行にはカプセルと
        // 同じ幅の空きを置いて、未確定の書き始めと 1 つめの候補の左端を揃える(ユーザ指定)
        private static let conversionStateCapsuleFixedWidth: CGFloat = 30

        @ViewBuilder private var conversionStateCapsule: some View {
            Group {
                if showsParenthesesWrapper && composingText.isEmpty {
                    Text("()")
                } else {
                    Image(systemName: conversionStateIconName)
                }
            }
            .font(.system(size: candidateStateFontSize, weight: .bold))
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(conversionStateColor.opacity(0.95))
            )
            .accessibilityLabel(conversionStateLabel)
        }

        var body: some View {
            // 変換キー連打で選択を送ると、選択チップが画面外のままになっていた(2605)。
            // スワイプで手動スクロールしていると気づけない。選択が変わったら追従させる。
            ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
            if showsInternalCompositionPreview {
                HStack(spacing: 6) {
                    conversionStateCapsule
                        .frame(width: Self.conversionStateCapsuleFixedWidth)
                    Text(internalCompositionPreviewText)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .underline()
                        .lineLimit(1)
                        .truncationMode(.head)
                        .foregroundStyle(keyLabelColor.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .allowsHitTesting(false)
                        .accessibilityLabel("未確定 \(internalCompositionPreviewText)")
                }
                .padding(.horizontal, 2)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    let showsWrapperOnly = showsParenthesesWrapper && composingText.isEmpty

                    if showsInternalCompositionPreview {
                        // tokushima: カプセルは上の行。同じ幅の空きで 1 つめの候補の左端を未確定の書き始めに揃える
                        Color.clear
                            .frame(width: Self.conversionStateCapsuleFixedWidth, height: 1)
                    } else if showsWrapperOnly || (!composingText.isEmpty && !conversionCandidates.isEmpty) {
                        // 候補なし(⊘)のとき状態は必ず未確定なので、カプセルは冗長 — 出さずに左へ詰める。
                        // 状態はアイコンのミニカプセルで示す(鉛筆=未確定/循環矢印=変換中)。
                        conversionStateCapsule
                    }

                    conversionCandidateChips

                    // 変換チップ側に同一のかな候補が出ている場合は末尾チップを重複表示しない
                    if !composingText.isEmpty, !conversionCandidates.contains(composingText) {
                        let kanaChipText = showsParenthesesWrapper ? "(\(composingText))" : composingText
                        if canTapComposingTextToCommit {
                            Button {
                                onComposingTextCommitTap()
                            } label: {
                                composingKanaChip(kanaChipText)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(composingText)を確定")
                            .accessibilityHint("通常タップで変換せずに確定。ロングタップでカタカナ確定")
                            .simultaneousGesture(
                                LongPressGesture(minimumDuration: 0.4)
                                    .onEnded { _ in
                                        onComposingTextCommitLongPress()
                                    }
                            )
                        } else {
                            composingKanaChip(kanaChipText)
                        }
                    } else if showsWrapperOnly {
                        composingKanaChip("()")
                    }

                }
                .modifier(CandidateBarTopMarginProbe(expected: showsInternalCompositionPreview ? 0 : kanaCandidateHeaderTopPadding, isContent: true))
                .padding(.horizontal, 2)
                .padding(.top, showsInternalCompositionPreview ? 0 : kanaCandidateHeaderTopPadding)
                .padding(.bottom, 0)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .modifier(CandidateBarTopMarginProbe(expected: showsInternalCompositionPreview ? 0 : kanaCandidateHeaderTopPadding, isContent: false))
            }
            .onChange(of: selectedConversionCandidateIndex) { index in
                guard let index else {
                    return
                }
                // 端では SwiftUI が clamp するので、先頭でも不自然な余白にはならない。
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
            .modifier(KeyboardScrollEdgeEffectHiddenModifier())
            }
        }
    }

    struct KeyboardRootLatinSuggestionHeaderView: View {
        let latinSuggestions: [String]
        let candidateTextFontSize: CGFloat
        let keyLabelColor: Color
        let kanaCandidateHeaderTopPadding: CGFloat
        let onSelectConversionCandidate: (Int) -> Void

        var body: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if latinSuggestions.isEmpty {
                        // かな側と同じ空集合アイコン(候補なし)。
                        Image(systemName: "circle.slash")
                            .font(.system(size: candidateTextFontSize, weight: .regular))
                            .foregroundStyle(keyLabelColor.opacity(0.6))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(KeyboardThemePalette.candidateHeaderPlaceholderBackground)
                            )
                            .accessibilityLabel("候補なし")
                    }

                    ForEach(Array(latinSuggestions.enumerated()), id: \.offset) { index, candidate in
                        Button {
                            onSelectConversionCandidate(index)
                        } label: {
                            Text(candidate)
                                .font(.system(size: candidateTextFontSize, weight: .semibold))
                                .foregroundStyle(keyLabelColor)
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(KeyboardThemePalette.candidateHeaderChipBackground)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(KeyboardThemePalette.candidateHeaderBorder, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(candidate)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.top, kanaCandidateHeaderTopPadding)
                .padding(.bottom, 0)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            // かな側(3095)と同じく iOS 26 以降のスクロール縁のぼかしを切る。欧文面だけ残っていた(ユーザ報告 3119、iOS 27)
            .modifier(KeyboardScrollEdgeEffectHiddenModifier())
        }
    }

// パネル(絵文字/顔文字/記号/漢字ピッカー/書式化数値)下段の 🌐。地球儀キーが要る機種
// (needsInputModeSwitchKey=true のホームボタン機)だけ action が渡され、それ以外は何も描かない
// (iPhone 15/16 等の表示は不変)。かなが 3×3 のときパネルからしか純正へ戻れないケースの受け皿(2785)
struct PanelAdvanceKeyboardKey: View {
    let action: (() -> Void)?
    let height: CGFloat

    var body: some View {
        if let action {
            ActionKeyButton(
                title: "🌐",
                accessibilityLabel: "次のキーボード",
                fontSize: 22,
                fixedWidth: 44,
                action: action
            )
            .frame(height: height)
        }
    }
}
