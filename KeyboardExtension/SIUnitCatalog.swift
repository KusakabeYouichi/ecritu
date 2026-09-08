import Foundation

// 書式化数値入力モードで使う単位カタログ。記号(symbol)は指数を上付き文字
// (² U+00B2 / ³ U+00B3 / ⁻¹ U+207B+U+00B9)、積を中点(· U+00B7)で内部保持する(表示/確定時は設定で ·/⋅/空白 に切替)。
// reading=名称(ドラムに添える)。用途・サブグループの列は描画に使っていなかったので撤去(2822)。ドラムは配列順の平坦リスト
struct SIUnit: Identifiable, Hashable {
    let symbol: String
    let reading: String
    // 金額カテゴリー用: 記号を数値の前に付けるのが既定か(ユーロ等は後ろが既定なので false)。
    // 単位系では未使用。
    var symbolBeforeAmount: Bool = true

    var id: String { symbol }
}

// SI接頭辞(基本単位ドラムと組み合わせる)。symbol は単位記号に前置する文字(なしは "")。
struct SIPrefix: Identifiable, Hashable {
    let symbol: String

    var id: String { symbol.isEmpty ? "_none" : symbol }
}

enum SIUnitCatalog {
    // 接頭辞ドラムの選択肢(大→小、中央に「なし」)。マイクロは SI/ISO 80000-1 準拠の
    // μ = GREEK SMALL LETTER MU(U+03BC)。互換用の MICRO SIGN(U+00B5)は使わない。
    static let prefixes: [SIPrefix] = [
        SIPrefix(symbol: "T"),
        SIPrefix(symbol: "G"),
        SIPrefix(symbol: "M"),
        SIPrefix(symbol: "k"),
        SIPrefix(symbol: "h"),
        SIPrefix(symbol: ""),
        SIPrefix(symbol: "c"),
        SIPrefix(symbol: "m"),
        SIPrefix(symbol: "μ"),
        SIPrefix(symbol: "n"),
        SIPrefix(symbol: "p")
    ]

    // SI基本単位。質量は接頭辞が付く g(グラム)を基本にする(k で kg)。t は接頭辞で作れず別途。
    static let siBase: [SIUnit] = [
        SIUnit(symbol: "m", reading: "メートル"),
        SIUnit(symbol: "g", reading: "グラム"),
        SIUnit(symbol: "s", reading: "秒"),
        SIUnit(symbol: "A", reading: "アンペア"),
        SIUnit(symbol: "K", reading: "ケルビン"),
        SIUnit(symbol: "mol", reading: "モル"),
        SIUnit(symbol: "cd", reading: "カンデラ")
    ]

    // SI組立単位(固有の名称を持たないもの)。ユーザ提供の一覧を機械/熱/電磁/化学の順で収録。
    static let siDerived: [SIUnit] = [
        // 機械・運動・力学
        SIUnit(symbol: "m²", reading: "平方メートル"),
        SIUnit(symbol: "m³", reading: "立方メートル"),
        SIUnit(symbol: "m/s", reading: "メートル毎秒"),
        SIUnit(symbol: "m/s²", reading: "メートル毎秒毎秒"),
        SIUnit(symbol: "s⁻¹", reading: "毎秒"),
        SIUnit(symbol: "rad/s", reading: "ラジアン毎秒"),
        SIUnit(symbol: "rad/s²", reading: "ラジアン毎秒毎秒"),
        SIUnit(symbol: "kg/m³", reading: "キログラム毎立方メートル"),
        SIUnit(symbol: "m³/kg", reading: "立方メートル毎キログラム"),
        SIUnit(symbol: "kg·m/s", reading: "キログラムメートル毎秒"),
        SIUnit(symbol: "N·s", reading: "ニュートン秒"),
        SIUnit(symbol: "N·m", reading: "ニュートンメートル"),
        SIUnit(symbol: "Pa·s", reading: "パスカル秒"),
        SIUnit(symbol: "m²/s", reading: "平方メートル毎秒"),
        SIUnit(symbol: "N/m", reading: "ニュートン毎メートル"),
        // 熱力学
        SIUnit(symbol: "J/K", reading: "ジュール毎ケルビン"),
        SIUnit(symbol: "J/(kg·K)", reading: "ジュール毎キログラムケルビン"),
        SIUnit(symbol: "J/kg", reading: "ジュール毎キログラム"),
        SIUnit(symbol: "W/(m·K)", reading: "ワット毎メートルケルビン"),
        SIUnit(symbol: "W/(m²·K)", reading: "ワット毎平方メートルケルビン"),
        SIUnit(symbol: "J/m³", reading: "ジュール毎立方メートル"),
        SIUnit(symbol: "K⁻¹", reading: "毎ケルビン"),
        // 電磁気学
        SIUnit(symbol: "A/m", reading: "アンペア毎メートル"),
        SIUnit(symbol: "C/m³", reading: "クーロン毎立方メートル"),
        SIUnit(symbol: "C/m²", reading: "クーロン毎平方メートル"),
        SIUnit(symbol: "F/m", reading: "ファラド毎メートル"),
        SIUnit(symbol: "H/m", reading: "ヘンリー毎メートル"),
        SIUnit(symbol: "V/m", reading: "ボルト毎メートル"),
        SIUnit(symbol: "A/m²", reading: "アンペア毎平方メートル"),
        SIUnit(symbol: "S/m", reading: "ジーメンス毎メートル"),
        SIUnit(symbol: "Ω·m", reading: "オームメートル"),
        SIUnit(symbol: "C/kg", reading: "クーロン毎キログラム"),
        // 化学・分子物理学・光
        SIUnit(symbol: "mol/m³", reading: "モル毎立方メートル"),
        SIUnit(symbol: "m³/mol", reading: "立方メートル毎モル"),
        SIUnit(symbol: "J/mol", reading: "ジュール毎モル"),
        SIUnit(symbol: "J/(mol·K)", reading: "ジュール毎モルケルビン"),
        SIUnit(symbol: "kg/mol", reading: "キログラム毎モル"),
        SIUnit(symbol: "cd/m²", reading: "カンデラ毎平方メートル"),
        SIUnit(symbol: "W/sr", reading: "ワット毎ステラジアン"),
        SIUnit(symbol: "W/m²", reading: "ワット毎平方メートル")
    ]

    // 固有の名称を持つSI組立単位(全22個)。基本単位表現は quantity ではなく別途参照とし、
    // ここでは記号・名称・主な物理量を収録する。
    static let siNamed: [SIUnit] = [
        // 力・運動・エネルギー
        SIUnit(symbol: "N", reading: "ニュートン"),
        SIUnit(symbol: "Pa", reading: "パスカル"),
        SIUnit(symbol: "J", reading: "ジュール"),
        SIUnit(symbol: "W", reading: "ワット"),
        // 電磁気
        SIUnit(symbol: "C", reading: "クーロン"),
        SIUnit(symbol: "V", reading: "ボルト"),
        SIUnit(symbol: "F", reading: "ファラド"),
        SIUnit(symbol: "Ω", reading: "オーム"),
        SIUnit(symbol: "S", reading: "ジーメンス"),
        SIUnit(symbol: "Wb", reading: "ウェーバ"),
        SIUnit(symbol: "T", reading: "テスラ"),
        SIUnit(symbol: "H", reading: "ヘンリー"),
        // 光・放射線
        SIUnit(symbol: "lm", reading: "ルーメン"),
        SIUnit(symbol: "lx", reading: "ルクス"),
        SIUnit(symbol: "Bq", reading: "ベクレル"),
        SIUnit(symbol: "Gy", reading: "グレイ"),
        SIUnit(symbol: "Sv", reading: "シーベルト"),
        // 角度・時間・その他
        SIUnit(symbol: "rad", reading: "ラジアン"),
        SIUnit(symbol: "sr", reading: "ステラジアン"),
        SIUnit(symbol: "Hz", reading: "ヘルツ"),
        // 度記号は内部では SI 形 °C(U+00B0 + C)で保持し、表示・確定時に設定 degreeSymbol(°C / ℃)へ変換する
        SIUnit(symbol: "\u{00B0}C", reading: "セルシウス度"),
        SIUnit(symbol: "kat", reading: "カタール"),
        // t(トン)は SI併用の非SI単位。接頭辞2連ドラムに馴染まないため固有側に暫定収録。
        // 将来「非SI併用単位」カテゴリーを設けたら移す。
        SIUnit(symbol: "t", reading: "トン"),
        // L(リットル)も SI併用の非SI単位。接頭辞ドラムと組んで hL・cL・mL を作るため固有側に収録する。
        // 記号は内部では常に大文字 L で保持する(小文字 l は mol・lm・lx・J/mol 等と衝突し、
        // 表示用グリフへの置換が安全に行えないため)。表示・確定時に設定 numberLitreSymbol の
        // グリフ(l / L / ℓ)へ変換する。
        SIUnit(symbol: "L", reading: "リットル")
    ]

    // 金額カテゴリーの通貨記号。記号モード(KeyboardRootViewSupportTypes.currencySymbols)の全24種に
    // 対応。symbolBeforeAmount=false は記号が後ろに来るのが慣習の通貨(ユーロ等)。読みは日本語名称。
    static let currencies: [SIUnit] = [
        SIUnit(symbol: "¥", reading: "円"),
        SIUnit(symbol: "$", reading: "ドル"),
        SIUnit(symbol: "€", reading: "ユーロ", symbolBeforeAmount: false),
        SIUnit(symbol: "£", reading: "ポンド"),
        SIUnit(symbol: "¢", reading: "セント", symbolBeforeAmount: false),
        SIUnit(symbol: "₩", reading: "ウォン"),
        SIUnit(symbol: "₹", reading: "ルピー"),
        SIUnit(symbol: "₽", reading: "ルーブル", symbolBeforeAmount: false),
        SIUnit(symbol: "₺", reading: "トルコリラ"),
        SIUnit(symbol: "฿", reading: "バーツ"),
        SIUnit(symbol: "₫", reading: "ドン", symbolBeforeAmount: false),
        SIUnit(symbol: "₴", reading: "フリヴニャ", symbolBeforeAmount: false),
        SIUnit(symbol: "₦", reading: "ナイラ"),
        SIUnit(symbol: "₱", reading: "ペソ"),
        SIUnit(symbol: "₡", reading: "コロン"),
        SIUnit(symbol: "₲", reading: "グアラニー", symbolBeforeAmount: false),
        SIUnit(symbol: "₵", reading: "セディ"),
        SIUnit(symbol: "₭", reading: "キープ", symbolBeforeAmount: false),
        SIUnit(symbol: "₸", reading: "テンゲ", symbolBeforeAmount: false),
        SIUnit(symbol: "₮", reading: "トゥグルグ", symbolBeforeAmount: false),
        SIUnit(symbol: "₰", reading: "ペニヒ", symbolBeforeAmount: false),
        SIUnit(symbol: "₪", reading: "シェケル"),
        SIUnit(symbol: "₾", reading: "ラリ", symbolBeforeAmount: false),
        SIUnit(symbol: "﷼", reading: "リヤル"),
        // 漢字・ハングルの通貨単位語(いずれも後置)。
        SIUnit(symbol: "元", reading: "ゲン", symbolBeforeAmount: false),
        SIUnit(symbol: "圆", reading: "ユアン", symbolBeforeAmount: false),
        SIUnit(symbol: "円", reading: "エン", symbolBeforeAmount: false),
        SIUnit(symbol: "圓", reading: "エン", symbolBeforeAmount: false),
        SIUnit(symbol: "원", reading: "ウォン", symbolBeforeAmount: false),
        SIUnit(symbol: "銅", reading: "ドン", symbolBeforeAmount: false)
    ]

    // 通貨記号の既定位置(前=true)。未知の記号は前置扱い。
    static func currencySymbolBeforeAmount(_ symbol: String) -> Bool {
        currencies.first(where: { $0.symbol == symbol })?.symbolBeforeAmount ?? true
    }

    // カテゴリー別の単位一覧。SI基本はユーザ確認後に拡充する(現状は空=占位表示)。
    static func units(for category: FormattedNumberCategory) -> [SIUnit] {
        switch category {
        case .siDerived:
            return siDerived
        case .siNamed:
            return siNamed
        case .siBase:
            return siBase
        case .currency:
            return currencies
        case .calendar:
            return []
        }
    }
}

// 温度の度記号の字形(設定 degreeSymbol。2773)。内部の正規形は SI 形 °C/°F(度記号 U+00B0 + 大文字)で、
// 表示・確定の最終段でこの設定へ変換する。℃/℉(U+2103/U+2109)は SI の規定にない互換文字だが
// 日本語環境で慣用(保守的初期設定はこちら)。単位ドラム・変換候補(せっし/かし/数字+ど)に一様に効く
enum DegreeSymbolStyle: String {
    case composed
    case compat

    static let sharedDefaultsKey = "degreeSymbol"

    init(sharedRawValue: String?) {
        self = sharedRawValue == DegreeSymbolStyle.compat.rawValue ? .compat : .composed
    }

    func styled(_ text: String) -> String {
        switch self {
        case .composed:
            guard text.contains("\u{2103}") || text.contains("\u{2109}") else { return text }
            return text
                .replacingOccurrences(of: "\u{2103}", with: "\u{00B0}C")
                .replacingOccurrences(of: "\u{2109}", with: "\u{00B0}F")
        case .compat:
            guard text.contains("\u{00B0}") else { return text }
            return text
                .replacingOccurrences(of: "\u{00B0}C", with: "\u{2103}")
                .replacingOccurrences(of: "\u{00B0}F", with: "\u{2109}")
        }
    }

    // 候補列に適用し、変換で同じ文字列になったもの(°C と ℃ の併記など)は先勝ちで畳む
    func styled(_ candidates: [String]) -> [String] {
        var seen = Set<String>()
        return candidates.map(styled).filter { seen.insert($0).inserted }
    }
}
