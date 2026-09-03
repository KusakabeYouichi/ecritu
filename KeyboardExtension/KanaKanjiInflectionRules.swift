import Foundation

// 活用ルールデータ: InflectionRule/GodanPattern の型定義と、形容詞/一段/五段/サ変/カ変の
// 活用テーブル、te系アスペクト等の派生サフィックス生成、ランキング用サフィックス、
// postfix 素通りサフィックス。ロジックは KanaKanjiConverter+Inflection.swift 側にあり、
// 本ファイルは宣言的データの置き場に徹する。
extension KanaKanjiConverter {
    enum InflectionClass {
        static let adjectiveI = "adjective-i"
        static let ichidan = "ichidan"
        static let godanU = "godan-u"
        static let godanKu = "godan-ku"
        static let godanGu = "godan-gu"
        static let godanSu = "godan-su"
        static let godanTsu = "godan-tsu"
        static let godanNu = "godan-nu"
        static let godanBu = "godan-bu"
        static let godanMu = "godan-mu"
        static let godanRu = "godan-ru"
        static let suru = "suru"
        static let kuru = "kuru"
    }

    // 活用クラス集合のビットマスク版。以前は InflectionRule.allowedClasses が Set<String> で、
    // ルール展開(約7,000本)ごとに SetStorage+String 要素をヒープに持ち、初回変換の常駐を
    // 約1MB以上押し上げていた(高水位台帳 2615 の解剖で特定)。クラス語彙は13種で固定なので
    // ビット集合にする。sqlite の inflection_classes が返すクラス名(String)との照合は
    // init(className:) で橋渡しする。
    struct InflectionClassSet: OptionSet, Hashable {
        let rawValue: UInt16

        static let adjectiveI = InflectionClassSet(rawValue: 1 << 0)
        static let ichidan = InflectionClassSet(rawValue: 1 << 1)
        static let godanU = InflectionClassSet(rawValue: 1 << 2)
        static let godanKu = InflectionClassSet(rawValue: 1 << 3)
        static let godanGu = InflectionClassSet(rawValue: 1 << 4)
        static let godanSu = InflectionClassSet(rawValue: 1 << 5)
        static let godanTsu = InflectionClassSet(rawValue: 1 << 6)
        static let godanNu = InflectionClassSet(rawValue: 1 << 7)
        static let godanBu = InflectionClassSet(rawValue: 1 << 8)
        static let godanMu = InflectionClassSet(rawValue: 1 << 9)
        static let godanRu = InflectionClassSet(rawValue: 1 << 10)
        static let suru = InflectionClassSet(rawValue: 1 << 11)
        static let kuru = InflectionClassSet(rawValue: 1 << 12)

        init(rawValue: UInt16) {
            self.rawValue = rawValue
        }

        // sqlite/JSON 由来のクラス名(InflectionClass の文字列)からの橋渡し。未知名は nil
        init?(className: String) {
            switch className {
            case InflectionClass.adjectiveI: self = .adjectiveI
            case InflectionClass.ichidan: self = .ichidan
            case InflectionClass.godanU: self = .godanU
            case InflectionClass.godanKu: self = .godanKu
            case InflectionClass.godanGu: self = .godanGu
            case InflectionClass.godanSu: self = .godanSu
            case InflectionClass.godanTsu: self = .godanTsu
            case InflectionClass.godanNu: self = .godanNu
            case InflectionClass.godanBu: self = .godanBu
            case InflectionClass.godanMu: self = .godanMu
            case InflectionClass.godanRu: self = .godanRu
            case InflectionClass.suru: self = .suru
            case InflectionClass.kuru: self = .kuru
            default: return nil
            }
        }

        func contains(className: String) -> Bool {
            guard let bit = InflectionClassSet(className: className) else {
                return false
            }
            return contains(bit)
        }

        func intersects(classNames: Set<String>) -> Bool {
            classNames.contains { contains(className: $0) }
        }
    }

    // sqlite の inflection_classes は (読み, 表層) につき1クラスしか持てず、同表記に
    // 一段と五段が同居する語で片方が失われる(いる: かな表記が 要る/入る 系の五段に
    // 巻き添えで godan-ru のみ登録され、居る系一段の います/いた/いて が導出できない)。
    // 辞書再ビルドで複数クラス化するまでのコード側補完(既存クラスに追加。置換しない)。
    // かかれる: 書かれる/描かれる は seed 供給のみで inflection_classes に無く、かかれる 基底からの
    // 一段派生(かかれている/かかれた 等)が 係れている 族だけになっていた(2784)
    static let supplementaryInflectionClassesByReading: [String: [String: Set<String>]] = [
        "いる": ["いる": [InflectionClass.ichidan]],
        "かかれる": ["書かれる": [InflectionClass.ichidan], "描かれる": [InflectionClass.ichidan]]
    ]

    struct InflectionRule {
        let readingSuffix: String
        let baseReadingSuffix: String
        // 明示指定が無いルール(全体の9割超)は baseReadingSuffix を使う。以前はここで
        // [baseReadingSuffix] の1要素配列を作っており、ルール展開約7,000本ぶんの
        // ArrayStorage が常駐していた(高水位台帳 2615 の解剖で特定)。nil のまま持ち、
        // 消費側は forEachBaseCandidateSuffix/firstBaseCandidateSuffix 経由で読む。
        private let explicitBaseCandidateSuffixes: [String]?
        let outputCandidateSuffix: String
        let allowedClasses: InflectionClassSet

        init(
            readingSuffix: String,
            baseReadingSuffix: String,
            baseCandidateSuffixes: [String]? = nil,
            outputCandidateSuffix: String? = nil,
            allowedClasses: InflectionClassSet
        ) {
            self.readingSuffix = readingSuffix
            self.baseReadingSuffix = baseReadingSuffix
            self.explicitBaseCandidateSuffixes = baseCandidateSuffixes
            self.outputCandidateSuffix = outputCandidateSuffix ?? readingSuffix
            self.allowedClasses = allowedClasses
        }

        func firstBaseCandidateSuffix(where predicate: (String) -> Bool) -> String? {
            if let explicitBaseCandidateSuffixes {
                return explicitBaseCandidateSuffixes.first(where: predicate)
            }
            return predicate(baseReadingSuffix) ? baseReadingSuffix : nil
        }

        func forEachBaseCandidateSuffix(_ body: (String) -> Void) {
            if let explicitBaseCandidateSuffixes {
                for suffix in explicitBaseCandidateSuffixes {
                    body(suffix)
                }
            } else {
                body(baseReadingSuffix)
            }
        }
    }

    struct GodanPattern {
        let dictionaryEnding: String
        let inflectionClass: String
        // 動的生成ルール用のビット版(InflectionClassSet(className:) は13種を必ず解決する)
        var classBit: InflectionClassSet { InflectionClassSet(className: inflectionClass) ?? [] }
        let aForm: String
        let iForm: String
        let eForm: String
        let oForm: String
        let teForm: String
        let taForm: String
    }

    private static func makeAdjectiveInflectionRules() -> [InflectionRule] { [
        InflectionRule(readingSuffix: "いです", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "のだ", baseReadingSuffix: "", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "のです", baseReadingSuffix: "", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "くない", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "くなく", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "くないです", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "くなかった", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "くなかったです", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "かった", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "かったり", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "かったです", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "くありません", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "くありませんでした", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "くて", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "ければ", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "そう", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "そうだ", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "そうな", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "そうに", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "そうで", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "そうもない", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "そうにない", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        // 様態そう の長音カジュアル表記「そー」(おいしそー 等)。そう と同じ位置付けで
        // 受け、出力も そー のまま(Apple純正と同じ解釈)。
        InflectionRule(readingSuffix: "そー", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "そーだ", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "そーな", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "そーに", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "そーで", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        // 伝聞「〜そうだ」: 終止形にそのまま付く(様態=語幹+そう とは別物)。おおいそうな→多いそうな 等。
        // baseReadingSuffix "" は「のだ/のです」と同型で、読みからそう系接尾を外した全体を基本形として引く。
        InflectionRule(readingSuffix: "そう", baseReadingSuffix: "", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "そうだ", baseReadingSuffix: "", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "そうな", baseReadingSuffix: "", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "そうです", baseReadingSuffix: "", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "そー", baseReadingSuffix: "", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "そーだ", baseReadingSuffix: "", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "そーな", baseReadingSuffix: "", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "そーです", baseReadingSuffix: "", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "く", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "くする", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "くなり", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "くなる", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "くなります", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "くなりました", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "くなりません", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "くなった", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "くなって", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "くなってる", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "くなっている", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "くなってた", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "くなっていた", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "くなってくる", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "くなってきた", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "くなってきて", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "くなってきます", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "すぎ", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "すぎる", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "すぎない", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "すぎなかった", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "すぎて", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "すぎた", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "すぎます", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "すぎました", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "すぎません", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "すぎれば", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "さ", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        // 程度の「〜め」(新しめ/大きめ/早め/安め)。めの/めに 等は postfix の/に が繋ぐ
        InflectionRule(readingSuffix: "め", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "めの", baseReadingSuffix: "い", allowedClasses: .adjectiveI),
        InflectionRule(readingSuffix: "めに", baseReadingSuffix: "い", allowedClasses: .adjectiveI)
    ] }

    // 一段の連用形(語幹そのもの)を供給する基底読みの opt-in(2026-08-27)。
    // 五段は iForm(食い/つき)があるのに一段には規則が無く、さんかくたべ→三角夛部 の人名合成
    // しか出なかった。ただし全一段に開くと 溜め/占め 等が既存の並びを崩す(ため→為 が
    // 溜め に、買い占めよね が 買いしめよね に退行)ため、報告のあった語だけ有効にする。
    // 空の readingSuffix = 読み全体が語幹(derivedCandidates 側で分岐)
    // のせる: のせわすれた が の+世話+擦れた になっていた。連用形 乗せ/載せ を供給し、複合動詞の
    // 前部要素ボーナス(multiClauseCompoundVerbRenyouStemReadings)と対で 載せ忘れた を組む(2784)
    static let ichidanRenyouNounBaseReadings: Set<String> = ["たべる", "のせる"]

    // 一段命令形(ろ/よ)を供給しない基底読み。居ろ が 色 を、射ろ が 意呂 を跨ぐ等、
    // 命令形として使う頻度より同音語の実害が大きいもの(2026-08-27)
    static let ichidanImperativeDeniedBaseReadings: Set<String> = ["いる", "える", "うる", "おる"]

    private static func makeIchidanRenyouNounRules() -> [InflectionRule] { [
        InflectionRule(readingSuffix: "", baseReadingSuffix: "る", allowedClasses: .ichidan)
    ] }

    private static func makeIchidanInflectionRules() -> [InflectionRule] { [
        InflectionRule(readingSuffix: "ない", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "なく", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ず", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "なかった", baseReadingSuffix: "る", allowedClasses: .ichidan),
        // 否定の並列(食べなかったり/食べなかったりする)。連文節の1ノード上限(12字)を超える
        // 食べたり食べなかったりする は 食べたり+食べなかったりする の2ノードで組む必要があり、
        // 後半が派生に無いと しなかった+利する に負ける(2757)
        InflectionRule(readingSuffix: "なかったり", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "なかったりする", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "なかったりした", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "なかったりして", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "なかったりします", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "なかったら", baseReadingSuffix: "る", allowedClasses: .ichidan),
        // 否定テ形(食べなくて/食べなくても)。願望否定テ(たくなくて)だけあって素の形が
        // 無かった(いかなくて→いか+なくて/凧なくて 等の断片合成に全長を取られる)
        InflectionRule(readingSuffix: "なくて", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "なくても", baseReadingSuffix: "る", allowedClasses: .ichidan),
        // 否定仮定形(食べなければ/食べなければならない)。口語縮約(なきゃ/なくちゃ)だけあって
        // 標準形が欠けており、ねなければ→ね無ければ、たべなければ→候補なし になっていた
        // (ユーザ報告 2026-08-27)
        InflectionRule(readingSuffix: "なければ", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "なければならない", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "なければいけない", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "なけれ", baseReadingSuffix: "る", allowedClasses: .ichidan),
        // 命令形+引用「って」(食べろって 等の口語)
        // 一段の命令形(食べろ/見ろ/起きろ)。命令+引用の ろって はあるのに素の ろ が無く、
        // たべろ は候補ゼロ、みろ→ミロ、おきろ→お帰路 になっていた(2026-08-27)。
        // ただし いる は除外(こんないろかなー→こんな居ろかなー と 色 を跨ぐ。
        // ichidanImperativeDeniedBaseReadings)
        InflectionRule(readingSuffix: "ろ", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "よ", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ろって", baseReadingSuffix: "る", allowedClasses: .ichidan),
        // 「〜なくなる」(状態変化の否定): 食べなくなった/食べなくなったら 等
        InflectionRule(readingSuffix: "なくなる", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "なくなった", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "なくなったら", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "なくなって", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "なくなります", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "なくなりました", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "なくなりません", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "なくなりませんでした", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "なくなれば", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "なくなり", baseReadingSuffix: "る", allowedClasses: .ichidan),
        // 関西弁・口語の否定縮約形(食べない→食べん, 食べなかった→食べんかった 等)
        InflectionRule(readingSuffix: "ん", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "んかった", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "んかったら", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "んで", baseReadingSuffix: "る", allowedClasses: .ichidan),
        // 「〜なくては/〜なければ」の口語縮約(食べなくちゃ, 食べなきゃ 等)
        InflectionRule(readingSuffix: "なくちゃ", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "なきゃ", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "なくちゃいけない", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "なきゃいけない", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "なくちゃならない", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "なきゃならない", baseReadingSuffix: "る", allowedClasses: .ichidan),
        // 関西方言の「〜ている→〜とる」縮約(食べとる, 食べとった 等)
        InflectionRule(readingSuffix: "とる", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "とった", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "とって", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "とったら", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "とらない", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "とらん", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "とらなかった", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "とらんかった", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "とります", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "とりました", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "とりません", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "とれば", baseReadingSuffix: "る", allowedClasses: .ichidan),
        // 関西方言の「〜てしまった→〜てもうた」縮約(食べてもうた 等)
        InflectionRule(readingSuffix: "てもう", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てもうた", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てもうて", baseReadingSuffix: "る", allowedClasses: .ichidan),
        // 同時進行の ながら(見ながら/食べながら)。連用形+ながら(2518)
        InflectionRule(readingSuffix: "ながら", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ます", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ました", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ません", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ましょう", baseReadingSuffix: "る", allowedClasses: .ichidan),
        // ぞんざいな ましょ(ましょう の口語): つなぎましょ が 繋+ましょ(名詞+素通り)に割れていた(2735)
        InflectionRule(readingSuffix: "ましょ", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "なさい", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "なさいませ", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "たい", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "たく", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "たくて", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "たくない", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "たくなくて", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "たくなかった", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "たくありません", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "たかった", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "たければ", baseReadingSuffix: "る", allowedClasses: .ichidan),
        // 願望+変化(食べたくなって 等。2647)
        InflectionRule(readingSuffix: "たくなる", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "たくなった", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "たくなって", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "そう", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "そうだ", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "そうな", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "そうに", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "そうで", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "そうもない", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "そうにない", baseReadingSuffix: "る", allowedClasses: .ichidan),
        // 様態そう の長音カジュアル表記(たべそー 等)。
        InflectionRule(readingSuffix: "そー", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "そーだ", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "そーな", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "そーに", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "そーで", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "にくい", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "にくく", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "にくくない", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "にくかった", baseReadingSuffix: "る", allowedClasses: .ichidan),
        // 補助形容詞の さ名詞化(食べやすさ/見えにくさ)。やすい は在るのに やすさ が無く
        // うちやすさ→内安さ になっていた(ユーザー報告 2614)
        InflectionRule(readingSuffix: "にくさ", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "すぎ", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "すぎる", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "すぎない", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "すぎなかった", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "すぎて", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "すぎた", baseReadingSuffix: "る", allowedClasses: .ichidan),
        // 連用形+始める(補助動詞)。きはじめる で 着始める(着る)が出ず、カ変ペアの 来始める
        // だけになっていた(ユーザ指定 2658)。他の一段(食べ始める 等)も1ノードで供給される
        InflectionRule(readingSuffix: "はじめる", baseReadingSuffix: "る", outputCandidateSuffix: "始める", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "はじめた", baseReadingSuffix: "る", outputCandidateSuffix: "始めた", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "はじめて", baseReadingSuffix: "る", outputCandidateSuffix: "始めて", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "はじめない", baseReadingSuffix: "る", outputCandidateSuffix: "始めない", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "はじめなかった", baseReadingSuffix: "る", outputCandidateSuffix: "始めなかった", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "はじめます", baseReadingSuffix: "る", outputCandidateSuffix: "始めます", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "はじめました", baseReadingSuffix: "る", outputCandidateSuffix: "始めました", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "はじめません", baseReadingSuffix: "る", outputCandidateSuffix: "始めません", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "はじめたら", baseReadingSuffix: "る", outputCandidateSuffix: "始めたら", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "はじめれば", baseReadingSuffix: "る", outputCandidateSuffix: "始めれば", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "はじめると", baseReadingSuffix: "る", outputCandidateSuffix: "始めると", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "はじめてる", baseReadingSuffix: "る", outputCandidateSuffix: "始めてる", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "はじめている", baseReadingSuffix: "る", outputCandidateSuffix: "始めている", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "はじめてから", baseReadingSuffix: "る", outputCandidateSuffix: "始めてから", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "すぎます", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "すぎました", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "すぎません", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "すぎれば", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "て", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てある", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てくる", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てきた", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てきて", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てこない", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てこなかった", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てきます", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てきました", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てきません", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てきちゃう", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てきちゃった", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てきちゃって", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てる", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ている", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てて", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ていて", baseReadingSuffix: "る", allowedClasses: .ichidan),
        // 仮定の縮約 〜てれば(着てれば=着ていれば)。五段は teForm+れば で既存、
        // 一段とカ変が欠けていた(きてれば→木てれば。ユーザ報告 2649)
        InflectionRule(readingSuffix: "てれば", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ていれば", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てた", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ていた", baseReadingSuffix: "る", allowedClasses: .ichidan),
        // 〜てた/〜ていた の派生「〜てたり/〜ていたり」(食べてたり, 食べていたりする 等)
        InflectionRule(readingSuffix: "てたり", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てたりする", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てたりしない", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てたりしなかった", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てたりします", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てたりしました", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てたりしません", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ていたり", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ていたりする", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ていたりしない", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ていたりしなかった", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ていたりします", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ていたりしました", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ていたりしません", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てない", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ていない", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てなかった", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ていなかった", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てます", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ています", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てました", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ていました", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てません", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ていません", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ておく", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ておいた", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ておいて", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ておかない", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ておかなかった", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ておきます", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ておきました", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ておきません", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "とく", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "といた", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "といて", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "とけば", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "とかない", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "とかなかった", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ときます", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ときました", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ときません", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てみる", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てみた", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てみて", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てみない", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てみなかった", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てみます", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てみました", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てみません", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てみたい", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てみたく", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てみたくて", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てみたくない", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てみたくなくて", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てみたくなかった", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てみたくありません", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てみたかった", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てみたければ", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てしまう", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てしまわない", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てしまわなかった", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てしまいます", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てしまいました", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てしまい", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てしまいません", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てしまった", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "てしまって", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ちゃう", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ちゃわない", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ちゃわなかった", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ちゃいます", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ちゃいました", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ちゃいません", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ちゃった", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ちゃって", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ちゃおう", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ちゃ", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "かた", baseReadingSuffix: "る", outputCandidateSuffix: "方", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "た", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "たら", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "たり", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "たりする", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "たりしない", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "たりしなかった", baseReadingSuffix: "る", allowedClasses: .ichidan),
        // 〜たりしなかったりする(食べたり食べなかったりする)。たり+し+なかった+り+する の
        // 断片連鎖は しなかったり が派生に無く、しなかった+利する に負けていた(2757)
        InflectionRule(readingSuffix: "たりしなかったりする", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "たりしなかったりした", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "たりしなかったりして", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "たりしなかったりします", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "たりします", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "たりしますか", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "たりしました", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "たりしません", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "たりしませんか", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "たりするのですか", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "よう", baseReadingSuffix: "る", allowedClasses: .ichidan),
        // 意志形+口語の引用促音(買ってみよっと/たべようっと)。よっと/ようっと で終わる読みは
        // 語彙が無く候補ゼロになっていた(かってみよっと、2534)。よう と同じ基底(る)から生成する
        InflectionRule(readingSuffix: "よっと", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "ようっと", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "れば", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "られ", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "られる", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "られない", baseReadingSuffix: "る", allowedClasses: .ichidan),
        // 受身+ん(口語の否定縮約: 食べられん/見られん)
        InflectionRule(readingSuffix: "られん", baseReadingSuffix: "る", allowedClasses: .ichidan),
        // 受身+てくる アスペクト連鎖(見られてくる/食べられてきます 等)。
        InflectionRule(readingSuffix: "られてくる", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "られてきた", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "られてきて", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "られてきます", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "られてきました", baseReadingSuffix: "る", allowedClasses: .ichidan),
        // 受身+たい 願望連鎖(見られたくない/食べられたかった 等)。プレーン語幹の たい 系
        // (readingSuffix: たくない)はあるが受身を挟む形が未定義で、おくられたくないね→
        // 置く+られたくない(かな断片合成)等に全長を取られる。
        InflectionRule(readingSuffix: "られたい", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "られたく", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "られたくない", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "られたくなくて", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "られたくなかった", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "られたかった", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "られたければ", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "させる", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "させない", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "させなかった", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "させた", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "させて", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "させたら", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "させたり", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "させれば", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "させよう", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "させます", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "させました", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "させません", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "させませんでした", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "させなさい", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "させたい", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "させたく", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "させたくない", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "させたかった", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "させられる", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "させられない", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "させられなかった", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "させられた", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "させられて", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "させられたら", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "させられれば", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "させられます", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "させられました", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "させられません", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "やすい", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "やすく", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "やすくない", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "やすかった", baseReadingSuffix: "る", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "やすさ", baseReadingSuffix: "る", allowedClasses: .ichidan),
        // 「〜やすい」の漢字「易い」候補(食べ易い 等)
        InflectionRule(readingSuffix: "やすい", baseReadingSuffix: "る", outputCandidateSuffix: "易い", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "やすく", baseReadingSuffix: "る", outputCandidateSuffix: "易く", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "やすくない", baseReadingSuffix: "る", outputCandidateSuffix: "易くない", allowedClasses: .ichidan),
        InflectionRule(readingSuffix: "やすかった", baseReadingSuffix: "る", outputCandidateSuffix: "易かった", allowedClasses: .ichidan)
    ] }

    static let godanPatterns: [GodanPattern] = [
        GodanPattern(dictionaryEnding: "う", inflectionClass: InflectionClass.godanU, aForm: "わ", iForm: "い", eForm: "え", oForm: "お", teForm: "って", taForm: "った"),
        GodanPattern(dictionaryEnding: "く", inflectionClass: InflectionClass.godanKu, aForm: "か", iForm: "き", eForm: "け", oForm: "こ", teForm: "いて", taForm: "いた"),
        GodanPattern(dictionaryEnding: "ぐ", inflectionClass: InflectionClass.godanGu, aForm: "が", iForm: "ぎ", eForm: "げ", oForm: "ご", teForm: "いで", taForm: "いだ"),
        GodanPattern(dictionaryEnding: "す", inflectionClass: InflectionClass.godanSu, aForm: "さ", iForm: "し", eForm: "せ", oForm: "そ", teForm: "して", taForm: "した"),
        GodanPattern(dictionaryEnding: "つ", inflectionClass: InflectionClass.godanTsu, aForm: "た", iForm: "ち", eForm: "て", oForm: "と", teForm: "って", taForm: "った"),
        GodanPattern(dictionaryEnding: "ぬ", inflectionClass: InflectionClass.godanNu, aForm: "な", iForm: "に", eForm: "ね", oForm: "の", teForm: "んで", taForm: "んだ"),
        GodanPattern(dictionaryEnding: "ぶ", inflectionClass: InflectionClass.godanBu, aForm: "ば", iForm: "び", eForm: "べ", oForm: "ぼ", teForm: "んで", taForm: "んだ"),
        GodanPattern(dictionaryEnding: "む", inflectionClass: InflectionClass.godanMu, aForm: "ま", iForm: "み", eForm: "め", oForm: "も", teForm: "んで", taForm: "んだ"),
        GodanPattern(dictionaryEnding: "る", inflectionClass: InflectionClass.godanRu, aForm: "ら", iForm: "り", eForm: "れ", oForm: "ろ", teForm: "って", taForm: "った")
    ]

    static func teShimauInflectionSuffixes(for teForm: String) -> [String] {
        guard !teForm.isEmpty else {
            return []
        }

        var suffixes = [
            teForm + "しまう",
            teForm + "しまわない",
            teForm + "しまわなかった",
            teForm + "しまいます",
            teForm + "しまいました",
            teForm + "しまい",
            teForm + "しまいません",
            teForm + "しまった",
            teForm + "しまって",
            // 意向形(使ってしまおう)。縮約側の ちゃおう/じゃおう と対
            teForm + "しまおう"
        ]
        suffixes.append(contentsOf: taiAdjectiveFamilyInflectionSuffixes(for: teForm + "しまい"))
        suffixes.append(contentsOf: taRiSuruInflectionSuffixes(for: teForm + "しまった"))

        if teForm.hasSuffix("て") {
            let contractionStem = String(teForm.dropLast())
            suffixes.append(contractionStem + "ちゃ")
            suffixes.append(contractionStem + "ちゃう")
            suffixes.append(contractionStem + "ちゃわない")
            suffixes.append(contractionStem + "ちゃわなかった")
            suffixes.append(contractionStem + "ちゃいます")
            suffixes.append(contractionStem + "ちゃいました")
            suffixes.append(contractionStem + "ちゃいません")
            suffixes.append(contractionStem + "ちゃった")
            suffixes.append(contractionStem + "ちゃって")
            // 縮約意向形(使っちゃおう=使ってしまおう)
            suffixes.append(contractionStem + "ちゃおう")
            suffixes.append(contentsOf: taiAdjectiveFamilyInflectionSuffixes(for: contractionStem + "ちゃい"))
            suffixes.append(contentsOf: taRiSuruInflectionSuffixes(for: contractionStem + "ちゃった"))
        } else if teForm.hasSuffix("で") {
            let contractionStem = String(teForm.dropLast())
            suffixes.append(contractionStem + "じゃ")
            suffixes.append(contractionStem + "じゃう")
            suffixes.append(contractionStem + "じゃわない")
            suffixes.append(contractionStem + "じゃわなかった")
            suffixes.append(contractionStem + "じゃいます")
            suffixes.append(contractionStem + "じゃいました")
            suffixes.append(contractionStem + "じゃいません")
            suffixes.append(contractionStem + "じゃった")
            suffixes.append(contractionStem + "じゃって")
            // 縮約意向形(読んじゃおう=読んでしまおう)
            suffixes.append(contractionStem + "じゃおう")
            suffixes.append(contentsOf: taiAdjectiveFamilyInflectionSuffixes(for: contractionStem + "じゃい"))
            suffixes.append(contentsOf: taRiSuruInflectionSuffixes(for: contractionStem + "じゃった"))
        }

        // 関西方言の「〜てしまった→〜てもうた」縮約
        // 「しまう→もう/まう」(食べてしまう→食べてもう/食べてまう, 食べてしまった→食べてもうた/食べてまった)
        suffixes.append(teForm + "もう")
        suffixes.append(teForm + "もうた")
        suffixes.append(teForm + "もうて")
        suffixes.append(teForm + "もうたら")
        suffixes.append(teForm + "もわない")
        suffixes.append(teForm + "まう")
        suffixes.append(teForm + "まった")
        suffixes.append(teForm + "まって")
        suffixes.append(teForm + "まったら")
        suffixes.append(teForm + "まわない")
        suffixes.append(contentsOf: taRiSuruInflectionSuffixes(for: teForm + "もうた"))
        suffixes.append(contentsOf: taRiSuruInflectionSuffixes(for: teForm + "まった"))

        return suffixes
    }

    static func teIruContractionInflectionSuffixes(for teForm: String) -> [String] {
        // 関西方言の「〜ている→〜とる」(〜でいる→〜どる)縮約
        // 「いる→おる」+ 音便で「と/ど」に変化
        guard !teForm.isEmpty else {
            return []
        }
        let lastChar = teForm.last!
        let stem = String(teForm.dropLast())
        let baseSyllable: String
        if lastChar == "て" {
            baseSyllable = "と"
        } else if lastChar == "で" {
            baseSyllable = "ど"
        } else {
            return []
        }

        let endings = [
            "る", "った", "って", "ったら",
            "らない", "らん", "らなかった", "らんかった",
            "ります", "りました", "りません",
            "れば", "ろう", "れ"
        ]
        var suffixes = endings.map { stem + baseSyllable + $0 }
        suffixes.append(contentsOf: taRiSuruInflectionSuffixes(for: stem + baseSyllable + "った"))
        return suffixes
    }

    static func godanCausativeInflectionSuffixes(for aForm: String) -> [String] {
        // 五段の使役・使役受身。「〜せる」「〜させられる」は一段動詞として活用する。
        // 例: 書く → 書かせる/書かせた/書かせて/書かせられた 等
        guard !aForm.isEmpty else {
            return []
        }

        let causativeStem = aForm + "せ"
        let causativePassiveStem = aForm + "せられ"

        let oneDanEndings = [
            "る", "ない", "なかった",
            "た", "たら", "たり", "て",
            "れば", "よう",
            // 命令形(飲ませろ/飲ませよ)。一段化した使役の命令。
            "ろ", "よ", "ろって", "よって",
            "ます", "ました", "ません", "ませんでした",
            "なさい",
            "たい", "たく", "たくない", "たくなくて", "たくなかった", "たかった", "たければ"
        ]

        var suffixes = oneDanEndings.flatMap { ending in
            [causativeStem + ending, causativePassiveStem + ending]
        }
        suffixes.append(contentsOf: taRiSuruInflectionSuffixes(for: causativeStem + "た"))
        suffixes.append(contentsOf: taRiSuruInflectionSuffixes(for: causativePassiveStem + "た"))
        return suffixes
    }

    static func teOkuInflectionSuffixes(for teForm: String) -> [String] {
        guard !teForm.isEmpty else {
            return []
        }

        var suffixes = [
            teForm + "おく",
            teForm + "おいた",
            teForm + "おいて",
            teForm + "おかない",
            teForm + "おかなかった",
            teForm + "おきます",
            teForm + "おきました",
            teForm + "おきません",
            // 仮定形(言っておけば/読んでおけば)。縮約側の とけば/どけば と対
            teForm + "おけば"
        ]
        suffixes.append(contentsOf: taiAdjectiveFamilyInflectionSuffixes(for: teForm + "おき"))

        if teForm.hasSuffix("て") {
            let contractionStem = String(teForm.dropLast())
            suffixes.append(contractionStem + "とく")
            suffixes.append(contractionStem + "といた")
            suffixes.append(contractionStem + "といて")
            suffixes.append(contractionStem + "とかない")
            suffixes.append(contractionStem + "とかなかった")
            suffixes.append(contractionStem + "ときます")
            suffixes.append(contractionStem + "ときました")
            suffixes.append(contractionStem + "ときません")
            // 縮約仮定形(言っとけば=言っておけば)。命令形 とけ は 解け と衝突するため追加しない
            suffixes.append(contractionStem + "とけば")
            suffixes.append(contentsOf: taiAdjectiveFamilyInflectionSuffixes(for: contractionStem + "とき"))
        } else if teForm.hasSuffix("で") {
            let contractionStem = String(teForm.dropLast())
            suffixes.append(contractionStem + "どく")
            suffixes.append(contractionStem + "どいた")
            suffixes.append(contractionStem + "どいて")
            suffixes.append(contractionStem + "どかない")
            suffixes.append(contractionStem + "どかなかった")
            suffixes.append(contractionStem + "どきます")
            suffixes.append(contractionStem + "どきました")
            suffixes.append(contractionStem + "どきません")
            // 縮約仮定形(読んどけば=読んでおけば)
            suffixes.append(contractionStem + "どけば")
            suffixes.append(contentsOf: taiAdjectiveFamilyInflectionSuffixes(for: contractionStem + "どき"))
        }

        return suffixes
    }

    static func taiAdjectiveFamilyInflectionSuffixes(for iStem: String) -> [String] {
        guard !iStem.isEmpty else {
            return []
        }

        return [
            iStem + "たい",
            iStem + "たく",
            iStem + "たくて",
            iStem + "たくない",
            iStem + "たくなくて",
            iStem + "たくなかった",
            iStem + "たくありません",
            iStem + "たかった",
            iStem + "たければ",
            // 願望+変化(食いたくなって/読みたくなる 等)。単一スパンの供給が無いと
            // 連文節で 悔いたく(7200)+なって(7200)=2スパンが 句+痛くなって(BOS bigram
            // 持ち)に僅差で跨がれ、食いたくなって が候補から消えていた(2647)
            iStem + "たくなる",
            iStem + "たくなった",
            iStem + "たくなって"
        ]
    }

    static func teMiruInflectionSuffixes(for teForm: String) -> [String] {
        guard !teForm.isEmpty else {
            return []
        }

        return [
            teForm + "みる",
            teForm + "みよう",
            // 意志形+口語の引用促音(買ってみよっと/やってみようっと。2534)
            teForm + "みよっと",
            teForm + "みようっと",
            teForm + "みましょう",
            teForm + "みるか",
            teForm + "みた",
            teForm + "みたら",
            teForm + "みれば",
            teForm + "みて",
            teForm + "みない",
            teForm + "みなかった",
            teForm + "みます",
            teForm + "みました",
            teForm + "みません"
        ] + taiAdjectiveFamilyInflectionSuffixes(for: teForm + "み")
    }

    static func teAruInflectionSuffixes(for teForm: String) -> [String] {
        guard !teForm.isEmpty else {
            return []
        }

        return [
            teForm + "ある",
            teForm + "あった"
        ]
    }

    static func teKuruInflectionSuffixes(for teForm: String) -> [String] {
        guard !teForm.isEmpty else {
            return []
        }

        return [
            teForm + "くる",
            teForm + "きた",
            teForm + "きて",
            teForm + "こない",
            teForm + "こなかった",
            teForm + "きます",
            teForm + "きました",
            teForm + "きません"
        ] + taiAdjectiveFamilyInflectionSuffixes(for: teForm + "き")
    }

    static func teIkuInflectionSuffixes(for teForm: String) -> [String] {
        guard !teForm.isEmpty else {
            return []
        }

        return [
            teForm + "いく",
            teForm + "く",
            teForm + "け",
            teForm + "いった",
            teForm + "いって",
            teForm + "いかない",
            teForm + "いかなかった",
            teForm + "いきます",
            teForm + "いきました",
            teForm + "いきません",
            teForm + "って"
        ] + taiAdjectiveFamilyInflectionSuffixes(for: teForm + "いき")
    }

    static func taiGaruInflectionSuffixes(for iForm: String) -> [String] {
        guard !iForm.isEmpty else {
            return []
        }

        return [
            iForm + "たがる",
            iForm + "たがった",
            iForm + "たがって",
            iForm + "たがらない",
            iForm + "たがらなかった",
            iForm + "たがります",
            iForm + "たがりました",
            iForm + "たがりません"
        ]
    }

    static func makuInflectionSuffixes(for renyouForm: String) -> [String] {
        guard !renyouForm.isEmpty else {
            return []
        }

        return [
            renyouForm + "まくる",
            renyouForm + "まくらない",
            renyouForm + "まくらなかった",
            renyouForm + "まくり",
            renyouForm + "まくります",
            renyouForm + "まくりました",
            renyouForm + "まくりません",
            renyouForm + "まくれ",
            renyouForm + "まくれば",
            renyouForm + "まくろう",
            renyouForm + "まくった",
            renyouForm + "まくって"
        ]
    }

    static let adjectiveGaruInflectionForms: [(readingSuffix: String, outputSuffix: String)] = [
        ("がらなかった", "がらなかった"),
        ("がりました", "がりました"),
        ("がりません", "がりません"),
        ("がらない", "がらない"),
        ("がり", "がり"),
        ("がった", "がった"),
        ("がって", "がって"),
        ("がる", "がる")
    ]

    static func taRiSuruInflectionSuffixes(for taForm: String) -> [String] {
        guard !taForm.isEmpty else {
            return []
        }

        let tari = taForm + "り"

        return [
            tari,
            tari + "する",
            tari + "しない",
            tari + "しなかった",
            tari + "します",
            tari + "しますか",
            tari + "しました",
            tari + "しません",
            tari + "しませんか",
            tari + "するのですか"
        ]
    }

    static func teAspectInflectionSuffixes(for teForm: String) -> [String] {
        guard !teForm.isEmpty else {
            return []
        }

        var suffixes: [String] = [
            teForm,
            teForm + "る",
            teForm + "いる",
            teForm + "て",
            teForm + "いて",
            teForm + "た",
            teForm + "いた",
            teForm + "ない",
            teForm + "いない",
            teForm + "なかった",
            teForm + "いなかった",
            teForm + "ます",
            teForm + "います",
            teForm + "ました",
            teForm + "いました",
            teForm + "ません",
            teForm + "いません",
            // 仮定の縮約(使ってれば=使っていれば)。無いと れば 単独区間が word_costs の
            // レバ(肝)しか持たず、使って+レバ の誤合成が先頭化する(2406)
            teForm + "れば",
            teForm + "いれば",
            // 過去仮定の縮約(経ってたら=経っていたら)。無いと ら 単独区間が 等(ら)に化けて
            // 経ってた+等 の誤合成が先頭化する(2407)
            teForm + "たら",
            teForm + "いたら"
        ]
        suffixes.append(contentsOf: taiAdjectiveFamilyInflectionSuffixes(for: teForm + "い"))
        suffixes.append(contentsOf: taiAdjectiveFamilyInflectionSuffixes(for: teForm))
        // 〜てた(=ていた)/〜ていた の派生「〜てたり/〜ていたり/〜てたりする/〜ていたりする」等
        suffixes.append(contentsOf: taRiSuruInflectionSuffixes(for: teForm + "た"))
        suffixes.append(contentsOf: taRiSuruInflectionSuffixes(for: teForm + "いた"))
        return suffixes
    }

    private static func makeGodanInflectionRules() -> [InflectionRule] {
        var rules: [InflectionRule] = []

        for pattern in godanPatterns {
            let passiveTeForm = pattern.aForm + "れて"

            var suffixes = [
                pattern.aForm + "ない",
                // 否定の連用形(わからなく/行かなく。〜なくなる 系はあるが素の なく が欠けていた)
                pattern.aForm + "なく",
                pattern.aForm + "なかった",
                pattern.aForm + "なかったら",
                // 否定の並列(行かなかったり/行かなかったりする。一段側のコメント参照)
                pattern.aForm + "なかったり",
                pattern.aForm + "なかったりする",
                pattern.aForm + "なかったりした",
                pattern.aForm + "なかったりして",
                pattern.aForm + "なかったりします",
                // 否定テ形(行かなくて/行かなくても)
                pattern.aForm + "なくて",
                pattern.aForm + "なくても",
                // 否定仮定形(行かなければ 等。標準形が欠けていた。2026-08-27)
                pattern.aForm + "なければ",
                pattern.aForm + "なければならない",
                pattern.aForm + "なければいけない",
                pattern.aForm + "なけれ",
                // 命令形+引用「って」(払えって/待てって 等の口語)
                pattern.eForm + "って",
                // 「〜なくなる」(状態変化の否定): 使わなくなった/使わなくなったら 等
                pattern.aForm + "なくなる",
                pattern.aForm + "なくなった",
                pattern.aForm + "なくなったら",
                pattern.aForm + "なくなって",
                pattern.aForm + "なくなります",
                pattern.aForm + "なくなりました",
                pattern.aForm + "なくなりません",
                pattern.aForm + "なくなりませんでした",
                pattern.aForm + "なくなれば",
                pattern.aForm + "なくなり",
                // 「〜なくては/〜なければ」の口語縮約(知らなくちゃ, 知らなきゃ 等)
                pattern.aForm + "なくちゃ",
                pattern.aForm + "なきゃ",
                pattern.aForm + "なくちゃいけない",
                pattern.aForm + "なきゃいけない",
                pattern.aForm + "なくちゃならない",
                pattern.aForm + "なきゃならない",
                pattern.aForm + "ねば",
                pattern.aForm + "ず",
                pattern.aForm + "れる",
                pattern.aForm + "れない",
                pattern.aForm + "れた",
                pattern.aForm + "れ",
                // 受身「〜れる」は一段活用なので、条件形・否定過去・丁寧・意志形も派生させる。
                // (書かれた はあるのに 書かれたら が無い、等の穴を塞ぐ)
                pattern.aForm + "れたら",
                pattern.aForm + "れれば",
                pattern.aForm + "れなかった",
                pattern.aForm + "れなかったら",
                pattern.aForm + "れます",
                pattern.aForm + "れました",
                pattern.aForm + "れません",
                pattern.aForm + "れよう",
                pattern.aForm + "れたり",
                // 受身+てくる アスペクト連鎖(送られてくる/送られてきます 等)。未定義だと
                // 奥+られてきます(られる基底のかな合成)等の断片に全長を取られる。
                pattern.aForm + "れてくる",
                pattern.aForm + "れてきた",
                pattern.aForm + "れてきて",
                pattern.aForm + "れてきます",
                pattern.aForm + "れてきました",
                // 受身+たい 願望連鎖(送られたくない/言われたかった 等)。
                pattern.aForm + "れたい",
                pattern.aForm + "れたく",
                pattern.aForm + "れたくない",
                pattern.aForm + "れたくなくて",
                pattern.aForm + "れたくなかった",
                pattern.aForm + "れたかった",
                pattern.aForm + "れたければ",
                // 受身+ん(口語の否定縮約: 送られん/言われん)
                pattern.aForm + "れん",
                // 同時進行の ながら(書きながら/聞きながら。2518)
                pattern.iForm + "ながら",
                pattern.iForm + "ます",
                pattern.iForm + "ました",
                pattern.iForm + "ません",
                pattern.iForm + "ましょう",
                pattern.iForm + "ましょ",
                pattern.iForm + "なさい",
                pattern.iForm + "なさいませ",
                pattern.iForm + "たい",
                pattern.iForm + "たく",
                pattern.iForm + "たくて",
                pattern.iForm + "たくない",
                pattern.iForm + "たくなくて",
                pattern.iForm + "たくなかった",
                pattern.iForm + "たくありません",
                pattern.iForm + "たかった",
                pattern.iForm + "たければ",
                // 願望+変化(食いたくなって 等。単一スパン供給が無いと連文節で
                // 句+痛くなって に跨がれる。2647)
                pattern.iForm + "たくなる",
                pattern.iForm + "たくなった",
                pattern.iForm + "たくなって",
                pattern.iForm + "そう",
                pattern.iForm + "そうだ",
                pattern.iForm + "そうな",
                pattern.iForm + "そうに",
                pattern.iForm + "そうで",
                pattern.iForm + "そうもない",
                pattern.iForm + "そうにない",
                pattern.iForm + "そー",
                pattern.iForm + "そーだ",
                pattern.iForm + "そーな",
                pattern.iForm + "そーに",
                pattern.iForm + "そーで",
                pattern.iForm + "にくい",
                pattern.iForm + "にくく",
                pattern.iForm + "にくくない",
                pattern.iForm + "にくかった",
                pattern.iForm + "にくさ",
                pattern.iForm + "やすい",
                pattern.iForm + "やすく",
                pattern.iForm + "やすくない",
                pattern.iForm + "やすかった",
                pattern.iForm + "やすさ",
                pattern.iForm + "すぎ",
                pattern.iForm + "すぎる",
                pattern.iForm + "すぎない",
                pattern.iForm + "すぎなかった",
                pattern.iForm + "すぎて",
                pattern.iForm + "すぎた",
                pattern.iForm + "すぎます",
                pattern.iForm + "すぎました",
                pattern.iForm + "すぎません",
                pattern.iForm + "すぎれば",
                pattern.eForm,
                pattern.eForm + "ば",
                pattern.oForm + "う",
                pattern.taForm,
                pattern.taForm + "ら"
            ]

            // 関西弁・口語の否定縮約形(知らない→知らん, 知らなかった→知らんかった 等)。
            // 五段す(aForm=さ)だけは除外 — 託さん/托さん/話さん が敬称「さん」と衝突し、
            // たくさん→託さん のように日常入力を邪魔する(方言形の損失より害が大きい。2462)
            // 「〜んで」(否定の連用: 選らんで=選らないで)は関西でも「ん」以外の形では稀で、
            // 稀な動詞(選る/彫る=える)と組んで 選らんで/彫らんで を えらんで の候補に混ぜていた
            // (ユーザ報告 2721)ため供給しない。ん/んかった/んかったら は残す
            if pattern.inflectionClass != InflectionClass.godanSu {
                suffixes.append(contentsOf: [
                    pattern.aForm + "ん",
                    pattern.aForm + "んかった",
                    pattern.aForm + "んかったら"
                ])
            }

            suffixes.append(contentsOf: KanaKanjiConverter.taRiSuruInflectionSuffixes(for: pattern.taForm))
            suffixes.append(contentsOf: KanaKanjiConverter.taiGaruInflectionSuffixes(for: pattern.iForm))
            suffixes.append(contentsOf: KanaKanjiConverter.makuInflectionSuffixes(for: pattern.iForm))
            suffixes.append(contentsOf: KanaKanjiConverter.teAspectInflectionSuffixes(for: pattern.teForm))
            suffixes.append(contentsOf: KanaKanjiConverter.teAspectInflectionSuffixes(for: passiveTeForm))
            suffixes.append(contentsOf: KanaKanjiConverter.godanCausativeInflectionSuffixes(for: pattern.aForm))
            // 使役/使役受身の te-aspect 派生(書かせている, 書かせていた, 書かせられている 等)
            suffixes.append(contentsOf: KanaKanjiConverter.teAspectInflectionSuffixes(for: pattern.aForm + "せて"))
            suffixes.append(contentsOf: KanaKanjiConverter.teAspectInflectionSuffixes(for: pattern.aForm + "せられて"))
            suffixes.append(contentsOf: KanaKanjiConverter.teAruInflectionSuffixes(for: pattern.teForm))
            suffixes.append(contentsOf: KanaKanjiConverter.teKuruInflectionSuffixes(for: pattern.teForm))
            suffixes.append(contentsOf: KanaKanjiConverter.teIkuInflectionSuffixes(for: pattern.teForm))
            suffixes.append(contentsOf: KanaKanjiConverter.teOkuInflectionSuffixes(for: pattern.teForm))
            suffixes.append(contentsOf: KanaKanjiConverter.teMiruInflectionSuffixes(for: pattern.teForm))
            suffixes.append(contentsOf: KanaKanjiConverter.teShimauInflectionSuffixes(for: pattern.teForm))
            suffixes.append(contentsOf: KanaKanjiConverter.teIruContractionInflectionSuffixes(for: pattern.teForm))

            for suffix in suffixes {
                rules.append(
                    InflectionRule(
                        readingSuffix: suffix,
                        baseReadingSuffix: pattern.dictionaryEnding,
                        allowedClasses: pattern.classBit
                    )
                )
            }

            rules.append(
                InflectionRule(
                    readingSuffix: pattern.iForm + "かた",
                    baseReadingSuffix: pattern.dictionaryEnding,
                    outputCandidateSuffix: pattern.iForm + "方",
                    allowedClasses: pattern.classBit
                )
            )

            // 「〜やすい」を漢字「易い」でも出せるようにする(打ち易い 等)。
            // かな候補は上の suffixes(やすい/やすく/…)で別途生成される。
            let yasuiKanjiForms: [(reading: String, candidate: String)] = [
                ("やすい", "易い"),
                ("やすく", "易く"),
                ("やすくない", "易くない"),
                ("やすかった", "易かった")
            ]
            for form in yasuiKanjiForms {
                rules.append(
                    InflectionRule(
                        readingSuffix: pattern.iForm + form.reading,
                        baseReadingSuffix: pattern.dictionaryEnding,
                        outputCandidateSuffix: pattern.iForm + form.candidate,
                        allowedClasses: pattern.classBit
                    )
                )
            }

            // 連用形+始める(補助動詞。のみはじめる→飲み始める。2658)。一段側は
            // InflectionRule の outputCandidateSuffix で同じく 始め を漢字出力する
            let hajimeruKanjiForms: [(reading: String, candidate: String)] = [
                ("はじめる", "始める"),
                ("はじめた", "始めた"),
                ("はじめて", "始めて"),
                ("はじめない", "始めない"),
                ("はじめなかった", "始めなかった"),
                ("はじめます", "始めます"),
                ("はじめました", "始めました"),
                ("はじめません", "始めません"),
                ("はじめたら", "始めたら"),
                ("はじめれば", "始めれば"),
                ("はじめると", "始めると"),
                ("はじめてる", "始めてる"),
                ("はじめている", "始めている"),
                ("はじめてから", "始めてから")
            ]
            for form in hajimeruKanjiForms {
                rules.append(
                    InflectionRule(
                        readingSuffix: pattern.iForm + form.reading,
                        baseReadingSuffix: pattern.dictionaryEnding,
                        outputCandidateSuffix: pattern.iForm + form.candidate,
                        allowedClasses: pattern.classBit
                    )
                )
            }
        }

        return rules
    }

    private static func makeSuruInflectionRules() -> [InflectionRule] { [
        InflectionRule(readingSuffix: "しない", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しなかった", baseReadingSuffix: "する", allowedClasses: .suru),
        // 否定の並列(再現しなかったり/しなかったりする。一段側のコメント参照)
        InflectionRule(readingSuffix: "しなかったり", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しなかったりする", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しなかったりした", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しなかったりして", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しなかったりします", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しなければ", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しなければならない", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しなければいけない", baseReadingSuffix: "する", allowedClasses: .suru),
        // 否定テ形(しなくて/しなくても)
        InflectionRule(readingSuffix: "しなくて", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しなくても", baseReadingSuffix: "する", allowedClasses: .suru),
        // 命令形(理解しろ/勉強しろ、文語 せよ)。無いと りかいしろ が単文節候補なし・連文節 理解白/理解城 になっていた(2722)
        InflectionRule(readingSuffix: "しろ", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "せよ", baseReadingSuffix: "する", allowedClasses: .suru),
        // 命令形+引用「って」(集中しろって 等の口語)
        InflectionRule(readingSuffix: "しろって", baseReadingSuffix: "する", allowedClasses: .suru),
        // 「〜なくなる」(状態変化の否定): 利用しなくなった 等
        InflectionRule(readingSuffix: "しなくなる", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しなくなった", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しなくなったら", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しなくなります", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しなくなりました", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しなくなりません", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しなくなって", baseReadingSuffix: "する", allowedClasses: .suru),
        // 関西弁・口語の否定縮約形(しない→せん, しなかった→せんかった 等)
        InflectionRule(readingSuffix: "せん", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "せんかった", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "せんかったら", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "せんで", baseReadingSuffix: "する", allowedClasses: .suru),
        // 「〜なくては/〜なければ」の口語縮約(しなくちゃ, しなきゃ 等)
        InflectionRule(readingSuffix: "しなくちゃ", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しなきゃ", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しなくちゃいけない", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しなきゃいけない", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しなくちゃならない", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しなきゃならない", baseReadingSuffix: "する", allowedClasses: .suru),
        // 関西方言の「〜している→〜しとる」縮約
        InflectionRule(readingSuffix: "しとる", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しとった", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しとって", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しとったら", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しとらない", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しとらん", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しとらなかった", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しとらんかった", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しとります", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しとりました", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しとりません", baseReadingSuffix: "する", allowedClasses: .suru),
        // 関西方言の「〜してしまった→〜してもうた」縮約
        InflectionRule(readingSuffix: "してもう", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してもうた", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してもうて", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しながら", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "します", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しました", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しません", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しましょう", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しましょ", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しなさい", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しなさいませ", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "したい", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "したく", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "したくて", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "したくない", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "したくなくて", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "したくなかった", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "したくありません", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "したかった", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "したければ", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しそう", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しそうだ", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しそうな", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しそうに", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しそうで", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しそうもない", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しそうにない", baseReadingSuffix: "する", allowedClasses: .suru),
        // 様態そう の長音カジュアル表記(しそー 等)。
        InflectionRule(readingSuffix: "しそー", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しそーだ", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しそーな", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しそーに", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しそーで", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しにくい", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しにくく", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しにくくない", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しにくかった", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しやすい", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しやすく", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しやすくない", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しやすかった", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しすぎ", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しすぎる", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しすぎない", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しすぎなかった", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しすぎて", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しすぎた", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しすぎます", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しすぎました", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しすぎません", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しすぎれば", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "して", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してる", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "している", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してて", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "していて", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してた", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "していた", baseReadingSuffix: "する", allowedClasses: .suru),
        // 〜してた/〜していた の派生「〜してたり/〜していたり」
        InflectionRule(readingSuffix: "してたり", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してたりする", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してたりしない", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してたりしなかった", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してたりします", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してたりしました", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してたりしません", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "していたり", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "していたりする", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "していたりしない", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "していたりしなかった", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "していたりします", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "していたりしました", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "していたりしません", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してない", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "していない", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してなかった", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "していなかった", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してます", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しています", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してました", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "していました", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してません", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "していません", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しておく", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しておいた", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しておいて", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しておかない", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しておかなかった", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しておきます", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しておきました", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しておきません", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しとく", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しといた", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しといて", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しとけば", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しとかない", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しとかなかった", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しときます", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しときました", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しときません", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してみる", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してみた", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してみて", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してみない", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してみなかった", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してみます", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してみました", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してみません", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してみたい", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してみたく", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してみたくて", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してみたくない", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してみたくなくて", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してみたくなかった", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してみたくありません", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してみたかった", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してみたければ", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してしまう", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してしまわない", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してしまわなかった", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してしまいます", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してしまいました", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してしまい", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してしまいません", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してしまった", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "してしまって", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しちゃう", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しちゃおう", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しちゃわない", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しちゃわなかった", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しちゃいます", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しちゃいました", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しちゃいません", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しちゃった", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しちゃって", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しちゃ", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "した", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "したら", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "したり", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "したりする", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "したりしない", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "したりしなかった", baseReadingSuffix: "する", allowedClasses: .suru),
        // 〜したりしなかったりする(再現したりしなかったりする。ichidan 側のコメント参照)
        InflectionRule(readingSuffix: "したりしなかったりする", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "したりしなかったりした", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "したりしなかったりして", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "したりしなかったりします", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "したりします", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "したりしますか", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "したりしました", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "したりしません", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "したりしませんか", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "したりするのですか", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しよう", baseReadingSuffix: "する", allowedClasses: .suru),
        // 意志形+口語の引用促音(掃除しよっと 等。ichidan 側の よっと/ようっと と対)
        InflectionRule(readingSuffix: "しよっと", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "しようっと", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "すれば", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "され", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "される", baseReadingSuffix: "する", allowedClasses: .suru),
        // 受身+ちゃう縮約(規定されちゃった 等。てしまう系の受身版)
        InflectionRule(readingSuffix: "されちゃう", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "されちゃった", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "されちゃって", baseReadingSuffix: "する", allowedClasses: .suru),
        // 受身+てくる アスペクト連鎖(送信されてくる/されてきます 等)。
        InflectionRule(readingSuffix: "されてくる", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "されてきた", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "されてきて", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "されてきます", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "されてきました", baseReadingSuffix: "する", allowedClasses: .suru),
        // 受身+たい 願望連鎖(送信されたくない/注目されたかった 等)。
        InflectionRule(readingSuffix: "されたい", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "されたく", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "されたくない", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "されたくなくて", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "されたくなかった", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "されたかった", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "されたければ", baseReadingSuffix: "する", allowedClasses: .suru),
        // 受身+ん(口語の否定縮約: 実用化されん)
        InflectionRule(readingSuffix: "されん", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "された", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "されて", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "されてる", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "されている", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "されてた", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "されていた", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "されています", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "されていました", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "されてました", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "されていません", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "されていない", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "されます", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "されました", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "されない", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "されません", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "されなかった", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "されませんでした", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "させる", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "させた", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "させて", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "させている", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "させてる", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "させます", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "させました", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "させない", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "させません", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "させなかった", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "させられる", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "させられた", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "させられて", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "させられている", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "させられます", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "させられました", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "させられない", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "させられません", baseReadingSuffix: "する", allowedClasses: .suru),
        InflectionRule(readingSuffix: "させられなかった", baseReadingSuffix: "する", allowedClasses: .suru)
    ] }

    private static func makeSahenNounSuruInflectionRules() -> [InflectionRule] { [
        InflectionRule(readingSuffix: "する", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "できる", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "できない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "できなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "できます", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "できました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "できません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "できて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "できてる", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "できている", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "できてて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "できていて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "できた", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "できていた", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "できてない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "できていない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "できてなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "できていなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "できてます", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "できています", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "できてました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "できていました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "できてません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "できていません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "できれば", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        // 「〜ちゃう」(てしまう縮約)の可能形。入力できちゃう 等。かな でき が既定出力なので
        // 入力できちゃう(かな)が生成され、出来ちゃう より前に出せる。
        InflectionRule(readingSuffix: "できちゃう", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "できちゃった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "できちゃって", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "できちゃいます", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "できちゃいました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        // 当然・義務の べき(文語 す+べき)。軽視すべき/検討すべきだ 等。規則が無く けいしすべき が
        // ケイしすべき/刑しすべき の断片合成になっていた(2509)
        InflectionRule(readingSuffix: "すべき", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "すべきだ", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "すべきです", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "すべきだった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "すべきでない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "すべきではない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しなかったり", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しなかったりする", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しなかったりした", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しなかったりして", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しなかったりします", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しなければ", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しなければならない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しなくて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しなくても", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "されん", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しながら", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "します", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しましょう", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しましょ", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "したい", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "したく", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "したくて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "したくない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "したくなくて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "したくなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "したくありません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "したかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "したければ", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しそう", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しそうだ", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しそうな", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しそうに", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しそうで", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しそうもない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しそうにない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しにくい", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しにくく", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しにくくない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しにくかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しやすい", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しやすく", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しやすくない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しやすかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しすぎ", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しすぎる", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しすぎない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しすぎなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しすぎて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しすぎた", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しすぎます", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しすぎました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しすぎません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しすぎれば", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "して", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してる", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "している", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "していて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してた", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "していた", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        // 〜してた/〜していた の派生「〜してたり/〜していたり」(サ変名詞用)
        InflectionRule(readingSuffix: "してたり", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してたりする", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してたりしない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してたりしなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してたりします", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してたりしました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してたりしません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "していたり", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "していたりする", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "していたりしない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "していたりしなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "していたりします", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "していたりしました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "していたりしません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "していない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "していなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してます", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しています", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "していました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "していません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しておく", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しておいた", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しておいて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しておかない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しておかなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しておきます", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しておきました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しておきません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しとく", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しといた", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しといて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しとけば", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しとかない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しとかなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しときます", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しときました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しときません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してみる", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してみた", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してみて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してみない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してみなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してみます", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してみました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してみません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してみたい", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してみたく", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してみたくて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してみたくない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してみたくなくて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してみたくなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してみたくありません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してみたかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してみたければ", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してしまう", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してしまわない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してしまわなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してしまいます", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してしまいました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してしまい", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してしまいません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してしまった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "してしまって", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しちゃう", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しちゃおう", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しちゃわない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しちゃわなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しちゃいます", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しちゃいました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しちゃいません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しちゃった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しちゃって", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しちゃ", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "した", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        // 命令形(理解しろ/勉強しろ、文語 注意せよ)。無いと りかいしろ が単文節候補なし・連文節 理解白/理解城 だった(2722)
        InflectionRule(readingSuffix: "しろ", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "せよ", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しろって", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "したら", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "したり", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "したりする", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "したりしない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "したりしなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "したりしなかったりする", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "したりしなかったりした", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "したりしなかったりして", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "したりしなかったりします", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "したりします", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "したりしますか", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "したりしました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "したりしません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "したりしませんか", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "したりするのですか", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "しよう", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "すれば", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "され", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "される", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "されちゃう", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "されちゃった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "されちゃって", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "された", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "されて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "されてる", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "されている", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "されています", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "されていました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "されてました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "されていません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "されていない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "されてた", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "されていた", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "されます", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "されました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "されない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "されません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "されなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "されませんでした", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "させる", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "させた", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "させて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "させている", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "させてる", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "させます", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "させました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "させない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "させません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "させなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "させられる", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "させられた", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "させられて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "させられている", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "させられます", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "させられました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "させられない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "させられません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru),
        InflectionRule(readingSuffix: "させられなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: .suru)
    ] }

    static let kuruInflectionForms: [(readingSuffix: String, kanjiOutputSuffix: String)] = [
        ("こない", "来ない"),
        ("こなかった", "来なかった"),
        ("こさせる", "来させる"),
        ("こさせた", "来させた"),
        ("こさせて", "来させて"),
        ("こられる", "来られる"),
        ("こなければ", "来なければ"),
        ("こなければならない", "来なければならない"),
        ("こなければいけない", "来なければいけない"),
        // 否定テ形(来なくて/来なくても)
        ("こなくて", "来なくて"),
        ("こなくても", "来なくても"),
        // 「〜なくなる」(状態変化の否定): 来なくなった 等
        ("こなくなる", "来なくなる"),
        ("こなくなった", "来なくなった"),
        ("こなくなったら", "来なくなったら"),
        ("こなくなって", "来なくなって"),
        ("こなくなります", "来なくなります"),
        ("こなくなりました", "来なくなりました"),
        ("こなくなりません", "来なくなりません"),
        // 関西弁・口語の否定縮約形(来ない→来ん 等)
        ("こん", "来ん"),
        ("こんかった", "来んかった"),
        ("こんかったら", "来んかったら"),
        ("こんで", "来んで"),
        // 「〜なくては/〜なければ」の口語縮約(来なくちゃ, 来なきゃ 等)
        ("こなくちゃ", "来なくちゃ"),
        ("こなきゃ", "来なきゃ"),
        ("こなくちゃいけない", "来なくちゃいけない"),
        ("こなきゃいけない", "来なきゃいけない"),
        ("こなくちゃならない", "来なくちゃならない"),
        ("こなきゃならない", "来なきゃならない"),
        // 関西方言の「〜ている→〜とる」縮約(来とる, 来とった 等)
        ("きとる", "来とる"),
        ("きとった", "来とった"),
        ("きとって", "来とって"),
        ("きとったら", "来とったら"),
        ("きとらない", "来とらない"),
        ("きとらん", "来とらん"),
        ("きとらなかった", "来とらなかった"),
        ("きとらんかった", "来とらんかった"),
        ("きとります", "来とります"),
        ("きとりました", "来とりました"),
        ("きとりません", "来とりません"),
        // 関西方言の「〜てしまった→〜てもうた」縮約(来てもうた 等)
        ("きてもう", "来てもう"),
        ("きてもうた", "来てもうた"),
        ("きてもうて", "来てもうて"),
        ("こい", "来い"),
        ("こいって", "来いって"),
        ("きながら", "来ながら"),
        ("きます", "来ます"),
        ("きました", "来ました"),
        ("きません", "来ません"),
        ("きましょう", "来ましょう"),
        ("きなさい", "来なさい"),
        ("きなさいませ", "来なさいませ"),
        ("きたい", "来たい"),
        ("きたく", "来たく"),
        ("きたくて", "来たくて"),
        ("きたくない", "来たくない"),
        ("きたくなくて", "来たくなくて"),
        ("きたくなかった", "来たくなかった"),
        ("きたくありません", "来たくありません"),
        ("きたかった", "来たかった"),
        ("きたければ", "来たければ"),
        ("きそう", "来そう"),
        ("きそうだ", "来そうだ"),
        ("きそうな", "来そうな"),
        ("きそうに", "来そうに"),
        ("きそうで", "来そうで"),
        ("きそうもない", "来そうもない"),
        ("きそうにない", "来そうにない"),
        ("きそー", "来そー"),
        ("きそーだ", "来そーだ"),
        ("きそーな", "来そーな"),
        ("きそーに", "来そーに"),
        ("きそーで", "来そーで"),
        ("きにくい", "来にくい"),
        ("きにくく", "来にくく"),
        ("きにくくない", "来にくくない"),
        ("きにくかった", "来にくかった"),
        ("きすぎ", "来すぎ"),
        ("きすぎる", "来すぎる"),
        ("きすぎない", "来すぎない"),
        ("きすぎなかった", "来すぎなかった"),
        ("きすぎて", "来すぎて"),
        ("きすぎた", "来すぎた"),
        ("きすぎます", "来すぎます"),
        ("きすぎました", "来すぎました"),
        ("きすぎません", "来すぎません"),
        ("きすぎれば", "来すぎれば"),
        // 連用形+始める(きはじめる→木始める。ユーザ報告 2658)。他の動詞は 連用形ノード
        // (食べ 等)+始める の2ノードで成立するが、来 は辞書に き→来 が無く供給欠落だった
        ("きはじめる", "来始める"),
        ("きはじめた", "来始めた"),
        ("きはじめて", "来始めて"),
        ("きはじめない", "来始めない"),
        ("きはじめなかった", "来始めなかった"),
        ("きはじめます", "来始めます"),
        ("きはじめました", "来始めました"),
        ("きはじめません", "来始めません"),
        ("きはじめたら", "来始めたら"),
        ("きはじめれば", "来始めれば"),
        ("きはじめると", "来始めると"),
        ("きはじめてる", "来始めてる"),
        ("きはじめている", "来始めている"),
        ("きはじめてから", "来始めてから"),
        ("きて", "来て"),
        ("きてる", "来てる"),
        ("きている", "来ている"),
        ("きてて", "来てて"),
        ("きていて", "来ていて"),
        ("きてれば", "来てれば"),
        ("きていれば", "来ていれば"),
        ("きてた", "来てた"),
        ("きていた", "来ていた"),
        // 〜てた/〜ていた の派生「〜てたり/〜ていたり」(来てたり, 来ていたりする 等)
        ("きてたり", "来てたり"),
        ("きてたりする", "来てたりする"),
        ("きてたりしない", "来てたりしない"),
        ("きてたりしなかった", "来てたりしなかった"),
        ("きてたりします", "来てたりします"),
        ("きてたりしました", "来てたりしました"),
        ("きてたりしません", "来てたりしません"),
        ("きていたり", "来ていたり"),
        ("きていたりする", "来ていたりする"),
        ("きていたりしない", "来ていたりしない"),
        ("きていたりしなかった", "来ていたりしなかった"),
        ("きていたりします", "来ていたりします"),
        ("きていたりしました", "来ていたりしました"),
        ("きていたりしません", "来ていたりしません"),
        ("きてない", "来てない"),
        ("きていない", "来ていない"),
        ("きてなかった", "来てなかった"),
        ("きていなかった", "来ていなかった"),
        ("きてます", "来てます"),
        ("きています", "来ています"),
        ("きてました", "来てました"),
        ("きていました", "来ていました"),
        ("きてません", "来てません"),
        ("きていません", "来ていません"),
        ("きておく", "来ておく"),
        ("きておいた", "来ておいた"),
        ("きておいて", "来ておいて"),
        ("きておかない", "来ておかない"),
        ("きておかなかった", "来ておかなかった"),
        ("きておきます", "来ておきます"),
        ("きておきました", "来ておきました"),
        ("きておきません", "来ておきません"),
        ("きとく", "来とく"),
        ("きといた", "来といた"),
        ("きといて", "来といて"),
        ("きとけば", "来とけば"),
        ("きとかない", "来とかない"),
        ("きとかなかった", "来とかなかった"),
        ("きときます", "来ときます"),
        ("きときました", "来ときました"),
        ("きときません", "来ときません"),
        ("きてみる", "来てみる"),
        ("きてみた", "来てみた"),
        ("きてみて", "来てみて"),
        ("きてみない", "来てみない"),
        ("きてみなかった", "来てみなかった"),
        ("きてみます", "来てみます"),
        ("きてみました", "来てみました"),
        ("きてみません", "来てみません"),
        ("きてみたい", "来てみたい"),
        ("きてみたく", "来てみたく"),
        ("きてみたくて", "来てみたくて"),
        ("きてみたくない", "来てみたくない"),
        ("きてみたくなくて", "来てみたくなくて"),
        ("きてみたくなかった", "来てみたくなかった"),
        ("きてみたくありません", "来てみたくありません"),
        ("きてみたかった", "来てみたかった"),
        ("きてみたければ", "来てみたければ"),
        ("きてしまう", "来てしまう"),
        ("きてしまわない", "来てしまわない"),
        ("きてしまわなかった", "来てしまわなかった"),
        ("きてしまいます", "来てしまいます"),
        ("きてしまいました", "来てしまいました"),
        ("きてしまい", "来てしまい"),
        ("きてしまいません", "来てしまいません"),
        ("きてしまった", "来てしまった"),
        ("きてしまって", "来てしまって"),
        ("きちゃう", "来ちゃう"),
        ("きちゃわない", "来ちゃわない"),
        ("きちゃわなかった", "来ちゃわなかった"),
        ("きちゃいます", "来ちゃいます"),
        ("きちゃいました", "来ちゃいました"),
        ("きちゃいません", "来ちゃいません"),
        ("きちゃった", "来ちゃった"),
        ("きちゃって", "来ちゃって"),
        ("きちゃ", "来ちゃ"),
        ("きた", "来た"),
        ("きたら", "来たら"),
        ("きたり", "来たり"),
        ("きたりする", "来たりする"),
        ("きたりしない", "来たりしない"),
        ("きたりしなかった", "来たりしなかった"),
        ("きたりします", "来たりします"),
        ("きたりしますか", "来たりしますか"),
        ("きたりしました", "来たりしました"),
        ("きたりしません", "来たりしません"),
        ("きたりしませんか", "来たりしませんか"),
        ("きたりするのですか", "来たりするのですか"),
        ("こよう", "来よう"),
        ("くれば", "来れば"),
        ("こられ", "来られ"),
        ("こられる", "来られる"),
        ("こられない", "来られない")
    ]

    private static func makeKuruInflectionRules() -> [InflectionRule] {
        var rules: [InflectionRule] = []

        for form in kuruInflectionForms {
            rules.append(
                InflectionRule(
                    readingSuffix: form.readingSuffix,
                    baseReadingSuffix: "くる",
                    baseCandidateSuffixes: ["くる"],
                    outputCandidateSuffix: form.readingSuffix,
                    allowedClasses: .kuru
                )
            )
            rules.append(
                InflectionRule(
                    readingSuffix: form.readingSuffix,
                    baseReadingSuffix: "くる",
                    baseCandidateSuffixes: ["来る"],
                    outputCandidateSuffix: form.kanjiOutputSuffix,
                    allowedClasses: .kuru
                )
            )
        }

        return rules
    }

    // 活用ルールの実体はこの1本だけ(2719)。以前は品詞別 static let(計7,676本)+ 連結コピーの
    // allInflectionRules + 末尾文字バケツ(ルールのコピー)で、同じ64B構造体を3重に常駐させていた
    // (≈1.5MB、memgraph 2645 の godanInflectionRules 1.06MB / allInflectionRules 0.90MB)。
    // 品詞別は生成関数にして一時化し、バケツは添字(Int)で参照する。
    private static let inflectionRuleTable: (rules: [InflectionRule], suruRange: Range<Int>) = {
        var rules: [InflectionRule] = []
        rules.append(contentsOf: makeAdjectiveInflectionRules())
        rules.append(contentsOf: makeIchidanInflectionRules())
        rules.append(contentsOf: makeIchidanRenyouNounRules())
        rules.append(contentsOf: makeGodanInflectionRules())
        rules.append(contentsOf: makeSahenNounSuruInflectionRules())
        let suruStart = rules.count
        rules.append(contentsOf: makeSuruInflectionRules())
        let suruRange = suruStart..<rules.count
        rules.append(contentsOf: makeKuruInflectionRules())
        return (rules, suruRange)
    }()
    static let allInflectionRules: [InflectionRule] = inflectionRuleTable.rules
    // サ変(する)ルールだけは丁寧接頭辞の接尾辞列挙が参照する。実体は allInflectionRules の範囲
    static var suruInflectionRules: ArraySlice<InflectionRule> {
        allInflectionRules[inflectionRuleTable.suruRange]
    }

    static let emptyStemAllowedBaseReadingSuffixes: Set<String> = [
        "する",
        "くる"
    ]

    static let inflectionRankingSuffixes: [String] = [
        "させられない", "させられる", "せられない", "せられる", "こられない", "こられる", "られない", "られる",
        "こられ", "され", "られ",
        "くありませんでした", "くなかったです", "くないです", "かったです", "くありません",
        "くなりません", "くなりました", "くなります",
        "すぎなかった", "すぎました", "すぎません", "にくくない", "すぎない", "すぎます", "にくかった",
        "させない", "させる", "せない", "せる", "やすくない", "たがらなかった", "たがりました", "たがりません", "がらなかった", "がりました", "がりません", "たくない", "なかったら", "たら", "なかった", "やすかった", "たかった", "くなかった",
        "すぎて", "すぎれば", "すぎた", "すぎる", "にくい", "にくく", "いです", "すぎ",
        "していなかった", "きていなかった", "でいなかった", "ていなかった", "してなかった", "きてなかった", "でなかった", "てなかった",
        "していません", "きていません", "でいません", "ていません", "していました", "きていました", "でいました", "ていました",
        "しています", "きています", "でいます", "ています", "してません", "きてません", "でません", "てません",
        "してました", "きてました", "でました", "てました", "してます", "きてます", "でます", "てます",
        "していない", "きていない", "でいない", "ていない", "してない", "きてない", "でない", "てない",
        "していた", "きていた", "でいた", "ていた", "してた", "きてた", "でた", "てた",
        "たりしなかったりします", "たりしなかったりする", "たりしなかったりした", "たりしなかったりして",
        "なかったりします", "なかったりする", "なかったりした", "なかったりして", "なかったり",
        "たりするのですか", "たりしませんか", "たりしますか", "たりしなかった", "たりしません", "たりしました", "たりします", "たりしない", "たりする",
        "したり", "きたり", "んだり", "いだり", "いたり", "ったり", "たり", "だり",
        // 仮定形(書けば/言えば/読めば 等)。無いと 書けば(980)が 駆け場(辞書1200)に沈む
        "ければ", "えば", "けば", "せば", "てば", "ねば", "めば", "べば", "げば", "れば",
        "てしまわなかった", "でしまわなかった", "てしまいません", "でしまいません", "てしまいました", "でしまいました", "てしまいます", "でしまいます", "てしまわない", "でしまわない",
        "てしまい", "でしまい",
        "ちゃわなかった", "じゃわなかった", "ちゃいません", "じゃいません", "ちゃいました", "じゃいました", "ちゃいます", "じゃいます", "ちゃわない", "じゃわない",
        "ておかなかった", "でおかなかった", "とかなかった", "どかなかった", "ておきません", "でおきません", "ときません", "どきません", "ておきました", "でおきました", "ときました", "どきました",
        "ておきます", "でおきます", "ときます", "どきます", "ておかない", "でおかない", "とかない", "どかない", "ておいた", "でおいた", "といた", "どいた", "ておいて", "でおいて", "といて", "どいて",
        "てみなかった", "でみなかった", "てみません", "でみません", "てみました", "でみました", "てみます", "でみます", "てみない", "でみない", "ておく", "でおく", "とく", "どく", "てみた", "でみた", "てみて", "でみて", "てみる", "でみる",
        "てしまって", "でしまって", "ちゃって", "じゃって",
        "てしまった", "でしまった", "ちゃった", "じゃった",
        "てしまう", "でしまう", "ちゃう", "じゃう",
        "ちゃ", "じゃ",
        "している", "きている", "でいる", "ている", "してる", "きてる", "でる", "てる",
        "きました", "しました", "きません", "しません", "ました", "ます",
        "だったら", "だった", "だ", "なら", "から",
        "んですけれど", "んですけど", "んだけれど", "んだけど", "けれど", "けど",
        "んです", "んだ",
        "くない", "かったり", "かった", "ければ", "くれば", "くなり", "くする", "やすい", "やすく", "よう", "こよう", "こい", "たがらない", "たがります", "がらない", "たい", "れば", "ねば", "ず",
        "がり",
        "たがった", "たがって", "たがる", "がった", "がって", "がる",
        "って", "った", "いて", "いた", "いで", "いだ", "んで", "んだ", "して", "した",
        "ない", "きて", "きた", "くて", "て", "た"
    ]

    static let ikuIrregularInflectionSuffixes: [String] = {
        var suffixes = ["った", "ったら"]
        suffixes.append(contentsOf: KanaKanjiConverter.taRiSuruInflectionSuffixes(for: "った"))
        suffixes.append(contentsOf: KanaKanjiConverter.teAspectInflectionSuffixes(for: "って"))
        suffixes.append(contentsOf: KanaKanjiConverter.teAruInflectionSuffixes(for: "って"))
        suffixes.append(contentsOf: KanaKanjiConverter.teKuruInflectionSuffixes(for: "って"))
        suffixes.append(contentsOf: KanaKanjiConverter.teIkuInflectionSuffixes(for: "って"))
        suffixes.append(contentsOf: KanaKanjiConverter.teOkuInflectionSuffixes(for: "って"))
        suffixes.append(contentsOf: KanaKanjiConverter.teMiruInflectionSuffixes(for: "って"))
        suffixes.append(contentsOf: KanaKanjiConverter.teShimauInflectionSuffixes(for: "って"))
        suffixes.append(contentsOf: KanaKanjiConverter.teIruContractionInflectionSuffixes(for: "って"))
        return suffixes
    }()

    static let postfixPassthroughSuffixes: [String] = [
        // 敬称: 人名/名詞に付く高頻度接尾辞。単文節が辞書の全人名(博子/弘子…)に敬称を
        // 付けられるようにし、連文節の「最良+変種3件」だけに依存して候補が激減する
        // (ひろこさん→5件、博子さん欠落 等)のを防ぐ。出力はかな(さん/くん/ちゃん/さま)。
        // 計算/生産 等の -さん 複合語は直接辞書(1200)が postfix(1120)より上位で正解維持。
        "ちゃん", "くん", "さま", "さん",
        // 補助動詞しまう: て形語幹+しまって(売ってしまって 等)。全長活用派生は基底列挙順が
        // 悪く(うる系が後方)、語幹curated(売って)の順を活かす合成経路をここで作る
        "しまいました", "しまった", "しまって", "しまう",
        "ほうがいい", "ほうがよい", "ほうが", "かもしれなかった", "かもしれません", "かもしれない", "かもしれず", "ようになる", "ようにする", "ようにして", "ように", "よう", "ような", "ようだ", "ようです", "みたいでした", "みたいだった", "みたいです", "みたいだ", "みたいな", "みたいに", "みたい", "っぽくなかった", "っぽくないです", "っぽくなった", "っぽくなって", "っぽくなる", "っぽければ", "っぽかった", "っぽいですか", "っぽいです", "っぽくない", "っぽくて", "っぽく", "っぽい", "はずがない", "はずだった", "はずでした", "はずです", "はずだ", "はず", "です", "んですけれど", "んですけど", "んだけれど", "んだけど", "のだ", "んです", "んだ", "だろう", "だったら", "だった", "なければ", "なくても", "なくなりました", "なくなりません", "なくなります", "なくなりたい", "なくならなかった", "なくならない", "なくなったら", "なくなった", "なくなって", "なくなれば", "なくなろう", "なくなり", "なくなる", "なくちゃいけない", "なきゃいけない", "なくちゃならない", "なきゃならない", "なくちゃ", "なきゃ", "なくて", "なかった", "なく", "ない", "だ", "けれど", "けど", "ください", "だけだ", "こと", "やつ", "ため", "など", "だけ", "のみ", "ほど", "にしたいです", "にしましょう", "にしました", "にしません", "にしたら", "にしたい", "にします", "にしよう", "にしとく", "にしても", "にすれば", "にできる", "にしないで", "にしない", "にして", "にした", "にする", "にせず", "によって", "によれば", "によると", "により", "による", "では", "には", "とは", "よりも", "より", "まで", "なら", "から", "へ", "は", "を", "に", "で", "と", "が", "も", "の", "し", "なあ", "なぁ", "ねえ", "ねぇ", "かー", "ねー", "なー", "よー", "わー", "ね", "よ", "な", "か",
        // 限定の しか(+ない系): 従来は し+か+ない の3段連鎖で組んでいたが、か+ない の連鎖を
        // 非文として弾いた(2723)ので、しか を1接尾辞として持つ(食う+しかない/石+しかない)。
        // 出力順は接尾辞の列挙順なので か の直後に置く(歴史+か が 礫+しか より前に出る従来順を維持)
        "しかなかった", "しかなくて", "しかなく", "しかない", "しか",
        // 色+がかる(紫がかった 等)。単文節でも 紫+がかった で組めるように(2731)
        "がかっている", "がかってる", "がかった", "がかって", "がかる",
        "や", "ぞ", "ぜ", "さ"
    ]
    static let postfixPassthroughPrefixReplacements: [(from: String, to: String)] = [
        ("ほう", "方")
    ]
}
