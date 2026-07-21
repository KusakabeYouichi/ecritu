import Foundation

// 書式化数値入力モードで使う単位カタログ。記号(symbol)は指数を上付き文字
// (² U+00B2 / ³ U+00B3 / ⁻¹ U+207B+U+00B9)、積を中黒(・ U+30FB)で表記する。
// reading=名称、quantity=用途。group=サブグループ(ドラムは group 順の平坦リスト)。
struct SIUnit: Identifiable, Hashable {
    let symbol: String
    let reading: String
    let quantity: String
    let group: String

    var id: String { symbol }
}

// SI接頭辞(基本単位ドラムと組み合わせる)。symbol は単位記号に前置する文字(なしは "")。
struct SIPrefix: Identifiable, Hashable {
    let symbol: String
    let reading: String

    var id: String { symbol.isEmpty ? "_none" : symbol }
}

enum SIUnitCatalog {
    // 接頭辞ドラムの選択肢(大→小、中央に「なし」)。µ は micro sign(U+00B5)。
    static let prefixes: [SIPrefix] = [
        SIPrefix(symbol: "T", reading: "テラ"),
        SIPrefix(symbol: "G", reading: "ギガ"),
        SIPrefix(symbol: "M", reading: "メガ"),
        SIPrefix(symbol: "k", reading: "キロ"),
        SIPrefix(symbol: "", reading: "(なし)"),
        SIPrefix(symbol: "c", reading: "センチ"),
        SIPrefix(symbol: "m", reading: "ミリ"),
        SIPrefix(symbol: "µ", reading: "マイクロ"),
        SIPrefix(symbol: "n", reading: "ナノ"),
        SIPrefix(symbol: "p", reading: "ピコ")
    ]

    // SI基本単位。質量は接頭辞が付く g(グラム)を基本にする(k で kg)。t は接頭辞で作れず別途。
    static let siBase: [SIUnit] = [
        SIUnit(symbol: "m", reading: "メートル", quantity: "長さ", group: "SI基本単位"),
        SIUnit(symbol: "g", reading: "グラム", quantity: "質量", group: "SI基本単位"),
        SIUnit(symbol: "s", reading: "秒", quantity: "時間", group: "SI基本単位"),
        SIUnit(symbol: "A", reading: "アンペア", quantity: "電流", group: "SI基本単位"),
        SIUnit(symbol: "K", reading: "ケルビン", quantity: "熱力学温度", group: "SI基本単位"),
        SIUnit(symbol: "mol", reading: "モル", quantity: "物質量", group: "SI基本単位"),
        SIUnit(symbol: "cd", reading: "カンデラ", quantity: "光度", group: "SI基本単位")
    ]

    // SI組立単位(固有の名称を持たないもの)。ユーザ提供の一覧を機械/熱/電磁/化学の順で収録。
    static let siDerived: [SIUnit] = [
        // 機械・運動・力学
        SIUnit(symbol: "m²", reading: "平方メートル", quantity: "面積", group: "機械・運動・力学"),
        SIUnit(symbol: "m³", reading: "立方メートル", quantity: "体積、容積", group: "機械・運動・力学"),
        SIUnit(symbol: "m/s", reading: "メートル毎秒", quantity: "速さ、速度", group: "機械・運動・力学"),
        SIUnit(symbol: "m/s²", reading: "メートル毎秒毎秒", quantity: "加速度", group: "機械・運動・力学"),
        SIUnit(symbol: "s⁻¹", reading: "毎秒", quantity: "角速度、回転速度、角周波数", group: "機械・運動・力学"),
        SIUnit(symbol: "rad/s", reading: "ラジアン毎秒", quantity: "角速度", group: "機械・運動・力学"),
        SIUnit(symbol: "rad/s²", reading: "ラジアン毎秒毎秒", quantity: "角加速度", group: "機械・運動・力学"),
        SIUnit(symbol: "kg/m³", reading: "キログラム毎立方メートル", quantity: "密度、質量密度", group: "機械・運動・力学"),
        SIUnit(symbol: "m³/kg", reading: "立方メートル毎キログラム", quantity: "比体積", group: "機械・運動・力学"),
        SIUnit(symbol: "kg・m/s", reading: "キログラムメートル毎秒", quantity: "運動量", group: "機械・運動・力学"),
        SIUnit(symbol: "N・s", reading: "ニュートン秒", quantity: "力積", group: "機械・運動・力学"),
        SIUnit(symbol: "N・m", reading: "ニュートンメートル", quantity: "力のモーメント、トルク", group: "機械・運動・力学"),
        SIUnit(symbol: "Pa・s", reading: "パスカル秒", quantity: "粘度、粘性係数", group: "機械・運動・力学"),
        SIUnit(symbol: "m²/s", reading: "平方メートル毎秒", quantity: "動粘度、動粘性係数", group: "機械・運動・力学"),
        SIUnit(symbol: "N/m", reading: "ニュートン毎メートル", quantity: "表面張力、ばね定数", group: "機械・運動・力学"),
        // 熱力学
        SIUnit(symbol: "J/K", reading: "ジュール毎ケルビン", quantity: "熱容量、エントロピー", group: "熱力学"),
        SIUnit(symbol: "J/(kg・K)", reading: "ジュール毎キログラムケルビン", quantity: "比熱容量、比エントロピー", group: "熱力学"),
        SIUnit(symbol: "J/kg", reading: "ジュール毎キログラム", quantity: "比エネルギー、比エンタルピー、潜熱", group: "熱力学"),
        SIUnit(symbol: "W/(m・K)", reading: "ワット毎メートルケルビン", quantity: "熱伝導率", group: "熱力学"),
        SIUnit(symbol: "W/(m²・K)", reading: "ワット毎平方メートルケルビン", quantity: "熱伝達率、熱貫流率(U値)", group: "熱力学"),
        SIUnit(symbol: "J/m³", reading: "ジュール毎立方メートル", quantity: "エネルギー密度、発熱量", group: "熱力学"),
        SIUnit(symbol: "K⁻¹", reading: "毎ケルビン", quantity: "線膨張率、体膨張率", group: "熱力学"),
        // 電磁気学
        SIUnit(symbol: "A/m", reading: "アンペア毎メートル", quantity: "磁界の強さ(磁界強度)", group: "電磁気学"),
        SIUnit(symbol: "C/m³", reading: "クーロン毎立方メートル", quantity: "電荷密度、体積電荷密度", group: "電磁気学"),
        SIUnit(symbol: "C/m²", reading: "クーロン毎平方メートル", quantity: "電束密度、面電荷密度", group: "電磁気学"),
        SIUnit(symbol: "F/m", reading: "ファラド毎メートル", quantity: "誘電率", group: "電磁気学"),
        SIUnit(symbol: "H/m", reading: "ヘンリー毎メートル", quantity: "透磁率", group: "電磁気学"),
        SIUnit(symbol: "V/m", reading: "ボルト毎メートル", quantity: "電界の強さ(電界強度)", group: "電磁気学"),
        SIUnit(symbol: "A/m²", reading: "アンペア毎平方メートル", quantity: "電流密度", group: "電磁気学"),
        SIUnit(symbol: "S/m", reading: "ジーメンス毎メートル", quantity: "導電率", group: "電磁気学"),
        SIUnit(symbol: "Ω・m", reading: "オームメートル", quantity: "電気抵抗率(比抵抗)", group: "電磁気学"),
        SIUnit(symbol: "C/kg", reading: "クーロン毎キログラム", quantity: "照射線量", group: "電磁気学"),
        // 化学・分子物理学・光
        SIUnit(symbol: "mol/m³", reading: "モル毎立方メートル", quantity: "物質量濃度(モル濃度)", group: "化学・分子物理学・光"),
        SIUnit(symbol: "m³/mol", reading: "立方メートル毎モル", quantity: "モル体積", group: "化学・分子物理学・光"),
        SIUnit(symbol: "J/mol", reading: "ジュール毎モル", quantity: "モルエネルギー", group: "化学・分子物理学・光"),
        SIUnit(symbol: "J/(mol・K)", reading: "ジュール毎モルケルビン", quantity: "モル熱容量、モルエントロピー", group: "化学・分子物理学・光"),
        SIUnit(symbol: "kg/mol", reading: "キログラム毎モル", quantity: "モル質量", group: "化学・分子物理学・光"),
        SIUnit(symbol: "cd/m²", reading: "カンデラ毎平方メートル", quantity: "輝度", group: "化学・分子物理学・光"),
        SIUnit(symbol: "W/sr", reading: "ワット毎ステラジアン", quantity: "放射強度", group: "化学・分子物理学・光"),
        SIUnit(symbol: "W/m²", reading: "ワット毎平方メートル", quantity: "放射照度、エネルギーフラックス密度、音の強さ", group: "化学・分子物理学・光")
    ]

    // 固有の名称を持つSI組立単位(全22個)。基本単位表現は quantity ではなく別途参照とし、
    // ここでは記号・名称・主な物理量を収録する。
    static let siNamed: [SIUnit] = [
        // 力・運動・エネルギー
        SIUnit(symbol: "N", reading: "ニュートン", quantity: "力", group: "力・運動・エネルギー"),
        SIUnit(symbol: "Pa", reading: "パスカル", quantity: "圧力、応力", group: "力・運動・エネルギー"),
        SIUnit(symbol: "J", reading: "ジュール", quantity: "エネルギー、仕事、熱量", group: "力・運動・エネルギー"),
        SIUnit(symbol: "W", reading: "ワット", quantity: "工率、仕事率、電力", group: "力・運動・エネルギー"),
        // 電磁気
        SIUnit(symbol: "C", reading: "クーロン", quantity: "電荷、電気量", group: "電磁気"),
        SIUnit(symbol: "V", reading: "ボルト", quantity: "電位、電位差、電圧", group: "電磁気"),
        SIUnit(symbol: "F", reading: "ファラド", quantity: "静電容量", group: "電磁気"),
        SIUnit(symbol: "Ω", reading: "オーム", quantity: "電気抵抗", group: "電磁気"),
        SIUnit(symbol: "S", reading: "ジーメンス", quantity: "コンダクタンス", group: "電磁気"),
        SIUnit(symbol: "Wb", reading: "ウェーバ", quantity: "磁束", group: "電磁気"),
        SIUnit(symbol: "T", reading: "テスラ", quantity: "磁束密度", group: "電磁気"),
        SIUnit(symbol: "H", reading: "ヘンリー", quantity: "インダクタンス", group: "電磁気"),
        // 光・放射線
        SIUnit(symbol: "lm", reading: "ルーメン", quantity: "光束", group: "光・放射線"),
        SIUnit(symbol: "lx", reading: "ルクス", quantity: "照度", group: "光・放射線"),
        SIUnit(symbol: "Bq", reading: "ベクレル", quantity: "放射能", group: "光・放射線"),
        SIUnit(symbol: "Gy", reading: "グレイ", quantity: "吸収線量、比エネルギー", group: "光・放射線"),
        SIUnit(symbol: "Sv", reading: "シーベルト", quantity: "線量当量", group: "光・放射線"),
        // 角度・時間・その他
        SIUnit(symbol: "rad", reading: "ラジアン", quantity: "平面角", group: "角度・時間・その他"),
        SIUnit(symbol: "sr", reading: "ステラジアン", quantity: "立体角", group: "角度・時間・その他"),
        SIUnit(symbol: "Hz", reading: "ヘルツ", quantity: "周波数", group: "角度・時間・その他"),
        SIUnit(symbol: "℃", reading: "セルシウス度", quantity: "セルシウス温度", group: "角度・時間・その他"),
        SIUnit(symbol: "kat", reading: "カタール", quantity: "酵素活性", group: "角度・時間・その他")
    ]

    // カテゴリー別の単位一覧。SI基本はユーザ確認後に拡充する(現状は空=占位表示)。
    static func units(for category: FormattedNumberCategory) -> [SIUnit] {
        switch category {
        case .siDerived:
            return siDerived
        case .siNamed:
            return siNamed
        case .siBase:
            return siBase
        case .calendar:
            return []
        }
    }
}
