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

    struct InflectionRule {
        let readingSuffix: String
        let baseReadingSuffix: String
        let baseCandidateSuffixes: [String]
        let outputCandidateSuffix: String
        let allowedClasses: Set<String>

        init(
            readingSuffix: String,
            baseReadingSuffix: String,
            baseCandidateSuffixes: [String]? = nil,
            outputCandidateSuffix: String? = nil,
            allowedClasses: Set<String>
        ) {
            self.readingSuffix = readingSuffix
            self.baseReadingSuffix = baseReadingSuffix
            self.baseCandidateSuffixes = baseCandidateSuffixes ?? [baseReadingSuffix]
            self.outputCandidateSuffix = outputCandidateSuffix ?? readingSuffix
            self.allowedClasses = allowedClasses
        }
    }

    struct GodanPattern {
        let dictionaryEnding: String
        let inflectionClass: String
        let aForm: String
        let iForm: String
        let eForm: String
        let oForm: String
        let teForm: String
        let taForm: String
    }

    static let adjectiveInflectionRules: [InflectionRule] = [
        InflectionRule(readingSuffix: "いです", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "のだ", baseReadingSuffix: "", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "のです", baseReadingSuffix: "", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くない", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなく", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くないです", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなかった", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなかったです", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "かった", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "かったり", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "かったです", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くありません", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くありませんでした", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くて", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "ければ", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "そう", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "そうだ", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "そうな", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "そうに", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "そうで", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "そうもない", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "そうにない", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        // 伝聞「〜そうだ」: 終止形にそのまま付く(様態=語幹+そう とは別物)。おおいそうな→多いそうな 等。
        // baseReadingSuffix "" は「のだ/のです」と同型で、読みからそう系接尾を外した全体を基本形として引く。
        InflectionRule(readingSuffix: "そう", baseReadingSuffix: "", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "そうだ", baseReadingSuffix: "", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "そうな", baseReadingSuffix: "", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "そうです", baseReadingSuffix: "", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "く", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くする", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなり", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなる", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなります", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなりました", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなりません", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなった", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなって", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなってる", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなっている", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなってた", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなっていた", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなってくる", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなってきた", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなってきて", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなってきます", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "すぎ", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "すぎる", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "すぎない", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "すぎなかった", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "すぎて", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "すぎた", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "すぎます", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "すぎました", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "すぎません", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "すぎれば", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "さ", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI])
    ]

    static let ichidanInflectionRules: [InflectionRule] = [
        InflectionRule(readingSuffix: "ない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ず", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "なかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "なかったら", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        // 関西弁・口語の否定縮約形(食べない→食べん, 食べなかった→食べんかった 等)
        InflectionRule(readingSuffix: "ん", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "んかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "んかったら", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "んで", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        // 「〜なくては/〜なければ」の口語縮約(食べなくちゃ, 食べなきゃ 等)
        InflectionRule(readingSuffix: "なくちゃ", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "なきゃ", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "なくちゃいけない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "なきゃいけない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "なくちゃならない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "なきゃならない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        // 関西方言の「〜ている→〜とる」縮約(食べとる, 食べとった 等)
        InflectionRule(readingSuffix: "とる", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "とった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "とって", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "とったら", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "とらない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "とらん", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "とらなかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "とらんかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "とります", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "とりました", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "とりません", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "とれば", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        // 関西方言の「〜てしまった→〜てもうた」縮約(食べてもうた 等)
        InflectionRule(readingSuffix: "てもう", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てもうた", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てもうて", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ます", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ました", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ません", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ましょう", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "なさい", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "なさいませ", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たい", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たく", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たくて", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たくない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たくなくて", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たくなかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たくありません", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たければ", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "そう", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "そうだ", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "そうな", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "そうに", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "そうで", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "そうもない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "そうにない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "にくい", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "にくく", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "にくくない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "にくかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "すぎ", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "すぎる", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "すぎない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "すぎなかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "すぎて", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "すぎた", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "すぎます", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "すぎました", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "すぎません", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "すぎれば", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "て", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てある", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てくる", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てきた", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てきて", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てこない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てこなかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てきます", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てきました", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てきません", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てる", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ている", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てて", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ていて", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てた", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ていた", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        // 〜てた/〜ていた の派生「〜てたり/〜ていたり」(食べてたり, 食べていたりする 等)
        InflectionRule(readingSuffix: "てたり", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てたりする", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てたりしない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てたりしなかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てたりします", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てたりしました", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てたりしません", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ていたり", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ていたりする", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ていたりしない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ていたりしなかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ていたりします", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ていたりしました", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ていたりしません", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ていない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てなかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ていなかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てます", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ています", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てました", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ていました", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てません", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ていません", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ておく", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ておいた", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ておいて", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ておかない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ておかなかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ておきます", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ておきました", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ておきません", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "とく", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "といた", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "といて", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "とかない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "とかなかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ときます", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ときました", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ときません", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てみる", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てみた", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てみて", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てみない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てみなかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てみます", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てみました", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てみません", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てみたい", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てみたく", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てみたくて", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てみたくない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てみたくなくて", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てみたくなかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てみたくありません", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てみたかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てみたければ", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てしまう", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てしまわない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てしまわなかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てしまいます", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てしまいました", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てしまい", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てしまいません", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てしまった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てしまって", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ちゃう", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ちゃわない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ちゃわなかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ちゃいます", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ちゃいました", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ちゃいません", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ちゃった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ちゃって", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ちゃ", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "かた", baseReadingSuffix: "る", outputCandidateSuffix: "方", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "た", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たら", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たり", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たりする", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たりしない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たりしなかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たりします", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たりしますか", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たりしました", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たりしません", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たりしませんか", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たりするのですか", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "よう", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "れば", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "られ", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "られる", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "られない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "させる", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "させない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "させなかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "させた", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "させて", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "させたら", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "させたり", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "させれば", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "させよう", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "させます", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "させました", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "させません", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "させませんでした", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "させなさい", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "させたい", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "させたく", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "させたくない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "させたかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "させられる", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "させられない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "させられなかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "させられた", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "させられて", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "させられたら", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "させられれば", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "させられます", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "させられました", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "させられません", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "やすい", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "やすく", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "やすくない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "やすかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        // 「〜やすい」の漢字「易い」候補(食べ易い 等)
        InflectionRule(readingSuffix: "やすい", baseReadingSuffix: "る", outputCandidateSuffix: "易い", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "やすく", baseReadingSuffix: "る", outputCandidateSuffix: "易く", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "やすくない", baseReadingSuffix: "る", outputCandidateSuffix: "易くない", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "やすかった", baseReadingSuffix: "る", outputCandidateSuffix: "易かった", allowedClasses: [InflectionClass.ichidan])
    ]

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
            teForm + "しまって"
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
            teForm + "おきません"
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
            iStem + "たければ"
        ]
    }

    static func teMiruInflectionSuffixes(for teForm: String) -> [String] {
        guard !teForm.isEmpty else {
            return []
        }

        return [
            teForm + "みる",
            teForm + "みよう",
            teForm + "みましょう",
            teForm + "みるか",
            teForm + "みた",
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
            teForm + "いません"
        ]
        suffixes.append(contentsOf: taiAdjectiveFamilyInflectionSuffixes(for: teForm + "い"))
        suffixes.append(contentsOf: taiAdjectiveFamilyInflectionSuffixes(for: teForm))
        // 〜てた(=ていた)/〜ていた の派生「〜てたり/〜ていたり/〜てたりする/〜ていたりする」等
        suffixes.append(contentsOf: taRiSuruInflectionSuffixes(for: teForm + "た"))
        suffixes.append(contentsOf: taRiSuruInflectionSuffixes(for: teForm + "いた"))
        return suffixes
    }

    static let godanInflectionRules: [InflectionRule] = {
        var rules: [InflectionRule] = []

        for pattern in godanPatterns {
            let passiveTeForm = pattern.aForm + "れて"

            var suffixes = [
                pattern.aForm + "ない",
                pattern.aForm + "なかった",
                pattern.aForm + "なかったら",
                // 関西弁・口語の否定縮約形(知らない→知らん, 知らなかった→知らんかった 等)
                pattern.aForm + "ん",
                pattern.aForm + "んかった",
                pattern.aForm + "んかったら",
                pattern.aForm + "んで",
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
                pattern.iForm + "ます",
                pattern.iForm + "ました",
                pattern.iForm + "ません",
                pattern.iForm + "ましょう",
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
                pattern.iForm + "そう",
                pattern.iForm + "そうだ",
                pattern.iForm + "そうな",
                pattern.iForm + "そうに",
                pattern.iForm + "そうで",
                pattern.iForm + "そうもない",
                pattern.iForm + "そうにない",
                pattern.iForm + "にくい",
                pattern.iForm + "にくく",
                pattern.iForm + "にくくない",
                pattern.iForm + "にくかった",
                pattern.iForm + "やすい",
                pattern.iForm + "やすく",
                pattern.iForm + "やすくない",
                pattern.iForm + "やすかった",
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
                        allowedClasses: [pattern.inflectionClass]
                    )
                )
            }

            rules.append(
                InflectionRule(
                    readingSuffix: pattern.iForm + "かた",
                    baseReadingSuffix: pattern.dictionaryEnding,
                    outputCandidateSuffix: pattern.iForm + "方",
                    allowedClasses: [pattern.inflectionClass]
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
                        allowedClasses: [pattern.inflectionClass]
                    )
                )
            }
        }

        return rules
    }()

    static let suruInflectionRules: [InflectionRule] = [
        InflectionRule(readingSuffix: "しない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しなかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        // 関西弁・口語の否定縮約形(しない→せん, しなかった→せんかった 等)
        InflectionRule(readingSuffix: "せん", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "せんかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "せんかったら", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "せんで", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        // 「〜なくては/〜なければ」の口語縮約(しなくちゃ, しなきゃ 等)
        InflectionRule(readingSuffix: "しなくちゃ", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しなきゃ", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しなくちゃいけない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しなきゃいけない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しなくちゃならない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しなきゃならない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        // 関西方言の「〜している→〜しとる」縮約
        InflectionRule(readingSuffix: "しとる", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しとった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しとって", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しとったら", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しとらない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しとらん", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しとらなかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しとらんかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しとります", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しとりました", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しとりません", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        // 関西方言の「〜してしまった→〜してもうた」縮約
        InflectionRule(readingSuffix: "してもう", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してもうた", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してもうて", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "します", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しました", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しません", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しましょう", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しなさい", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しなさいませ", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したい", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したく", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したくて", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したくない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したくなくて", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したくなかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したくありません", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したければ", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しそう", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しそうだ", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しそうな", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しそうに", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しそうで", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しそうもない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しそうにない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しにくい", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しにくく", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しにくくない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しにくかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しやすい", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しやすく", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しやすくない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しやすかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎ", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎる", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎなかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎて", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎた", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎます", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎました", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎません", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎれば", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "して", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してる", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "している", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してて", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していて", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してた", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していた", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        // 〜してた/〜していた の派生「〜してたり/〜していたり」
        InflectionRule(readingSuffix: "してたり", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してたりする", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してたりしない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してたりしなかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してたりします", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してたりしました", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してたりしません", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していたり", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していたりする", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していたりしない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していたりしなかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していたりします", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していたりしました", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していたりしません", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してなかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していなかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してます", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しています", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してました", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していました", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してません", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していません", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しておく", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しておいた", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しておいて", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しておかない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しておかなかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しておきます", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しておきました", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しておきません", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しとく", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しといた", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しといて", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しとかない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しとかなかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しときます", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しときました", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しときません", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみる", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみた", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみて", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみなかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみます", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみました", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみません", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみたい", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみたく", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみたくて", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみたくない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみたくなくて", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみたくなかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみたくありません", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみたかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみたければ", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまう", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまわない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまわなかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまいます", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまいました", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまい", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまいません", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまって", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しちゃう", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しちゃわない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しちゃわなかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しちゃいます", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しちゃいました", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しちゃいません", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しちゃった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しちゃって", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しちゃ", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "した", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したら", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したり", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したりする", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したりしない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したりしなかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したりします", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したりしますか", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したりしました", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したりしません", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したりしませんか", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したりするのですか", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しよう", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "すれば", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "され", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "される", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "された", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されて", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されてる", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されている", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されてた", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されていた", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されています", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されていました", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されてました", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されていません", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されていない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されます", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されました", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されません", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されなかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されませんでした", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させる", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させた", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させて", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させている", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させてる", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させます", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させました", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させません", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させなかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられる", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられた", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられて", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられている", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられます", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられました", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられません", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられなかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru])
    ]

    static let sahenNounSuruInflectionRules: [InflectionRule] = [
        InflectionRule(readingSuffix: "する", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できる", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できます", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できてる", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できている", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できてて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できていて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できた", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できていた", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できてない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できていない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できてなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できていなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できてます", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できています", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できてました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できていました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できてません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できていません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "できれば", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "します", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しましょう", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したい", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したく", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したくて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したくない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したくなくて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したくなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したくありません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したければ", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しそう", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しそうだ", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しそうな", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しそうに", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しそうで", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しそうもない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しそうにない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しにくい", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しにくく", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しにくくない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しにくかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しやすい", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しやすく", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しやすくない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しやすかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎ", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎる", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎた", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎます", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しすぎれば", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "して", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してる", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "している", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してた", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していた", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        // 〜してた/〜していた の派生「〜してたり/〜していたり」(サ変名詞用)
        InflectionRule(readingSuffix: "してたり", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してたりする", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してたりしない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してたりしなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してたりします", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してたりしました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してたりしません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していたり", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していたりする", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していたりしない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していたりしなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していたりします", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していたりしました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していたりしません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してます", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しています", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しておく", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しておいた", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しておいて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しておかない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しておかなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しておきます", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しておきました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しておきません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しとく", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しといた", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しといて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しとかない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しとかなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しときます", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しときました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しときません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみる", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみた", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみます", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみたい", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみたく", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみたくて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみたくない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみたくなくて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみたくなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみたくありません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみたかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してみたければ", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまう", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまわない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまわなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまいます", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまいました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまい", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまいません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまって", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しちゃう", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しちゃわない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しちゃわなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しちゃいます", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しちゃいました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しちゃいません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しちゃった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しちゃって", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しちゃ", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "した", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したら", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したり", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したりする", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したりしない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したりしなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したりします", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したりしますか", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したりしました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したりしません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したりしませんか", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したりするのですか", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しよう", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "すれば", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "され", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "される", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "された", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されてる", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されている", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されています", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されていました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されてました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されていません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されていない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されてた", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されていた", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されます", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "されませんでした", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させる", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させた", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させている", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させてる", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させます", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられる", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられた", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられて", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられている", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられます", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられません", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru])
    ]

    static let kuruInflectionForms: [(readingSuffix: String, kanjiOutputSuffix: String)] = [
        ("こない", "来ない"),
        ("こなかった", "来なかった"),
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
        ("きて", "来て"),
        ("きてる", "来てる"),
        ("きている", "来ている"),
        ("きてて", "来てて"),
        ("きていて", "来ていて"),
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

    static let kuruInflectionRules: [InflectionRule] = {
        var rules: [InflectionRule] = []

        for form in kuruInflectionForms {
            rules.append(
                InflectionRule(
                    readingSuffix: form.readingSuffix,
                    baseReadingSuffix: "くる",
                    baseCandidateSuffixes: ["くる"],
                    outputCandidateSuffix: form.readingSuffix,
                    allowedClasses: [InflectionClass.kuru]
                )
            )
            rules.append(
                InflectionRule(
                    readingSuffix: form.readingSuffix,
                    baseReadingSuffix: "くる",
                    baseCandidateSuffixes: ["来る"],
                    outputCandidateSuffix: form.kanjiOutputSuffix,
                    allowedClasses: [InflectionClass.kuru]
                )
            )
        }

        return rules
    }()

    static let allInflectionRules: [InflectionRule] =
        adjectiveInflectionRules
        + ichidanInflectionRules
        + godanInflectionRules
        + sahenNounSuruInflectionRules
        + suruInflectionRules
        + kuruInflectionRules

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
        "たりするのですか", "たりしませんか", "たりしますか", "たりしなかった", "たりしません", "たりしました", "たりします", "たりしない", "たりする",
        "したり", "きたり", "んだり", "いだり", "いたり", "ったり", "たり", "だり",
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
        "ほうがいい", "ほうがよい", "ほうが", "ようになる", "ようにする", "ようにして", "ように", "よう", "ような", "ようだ", "ようです", "みたいでした", "みたいだった", "みたいです", "みたいだ", "みたいな", "みたいに", "みたい", "っぽくなかった", "っぽくないです", "っぽくなった", "っぽくなって", "っぽくなる", "っぽければ", "っぽかった", "っぽいですか", "っぽいです", "っぽくない", "っぽくて", "っぽく", "っぽい", "はずがない", "はずだった", "はずでした", "はずです", "はずだ", "はず", "です", "んですけれど", "んですけど", "んだけれど", "んだけど", "のだ", "んです", "んだ", "だろう", "だったら", "だった", "なければ", "なくても", "なくなりました", "なくなりません", "なくなります", "なくなりたい", "なくならなかった", "なくならない", "なくなった", "なくなって", "なくなれば", "なくなろう", "なくなり", "なくなる", "なくちゃいけない", "なきゃいけない", "なくちゃならない", "なきゃならない", "なくちゃ", "なきゃ", "なくて", "なかった", "なく", "ない", "だ", "けれど", "けど", "ください", "だけだ", "こと", "やつ", "ため", "など", "だけ", "のみ", "では", "には", "とは", "よりも", "より", "まで", "なら", "から", "へ", "は", "を", "に", "で", "と", "が", "も", "の", "し", "なあ", "なぁ", "ねえ", "ねぇ", "ね", "よ", "な", "か", "や", "ぞ", "ぜ", "さ"
    ]
    static let postfixPassthroughPrefixReplacements: [(from: String, to: String)] = [
        ("ほう", "方")
    ]
}
