import Foundation

final class KanaKanjiConverter {
    private struct CandidateCacheKey: Hashable {
        let reading: String
        let limit: Int
        let modeRawValue: String
    }

    private enum InflectionClass {
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

    private struct InflectionRule {
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

    private struct GodanPattern {
        let dictionaryEnding: String
        let inflectionClass: String
        let aForm: String
        let iForm: String
        let eForm: String
        let oForm: String
        let teForm: String
        let taForm: String
    }

    private static let adjectiveInflectionRules: [InflectionRule] = [
        InflectionRule(readingSuffix: "いです", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "のだ", baseReadingSuffix: "", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "のです", baseReadingSuffix: "", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くない", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くないです", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなかった", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなかったです", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "かった", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "かったです", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くありません", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くありませんでした", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くて", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "ければ", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "く", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
        InflectionRule(readingSuffix: "くなる", baseReadingSuffix: "い", allowedClasses: [InflectionClass.adjectiveI]),
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

    private static let ichidanInflectionRules: [InflectionRule] = [
        InflectionRule(readingSuffix: "ない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "なかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ます", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ました", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ません", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たい", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たくない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "たかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "にくい", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "にくく", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "にくくない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "にくかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
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
        InflectionRule(readingSuffix: "てる", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ている", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てた", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "ていた", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
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
        InflectionRule(readingSuffix: "てしまう", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てしまわない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てしまわなかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てしまいます", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "てしまいました", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
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
        InflectionRule(readingSuffix: "た", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
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
        InflectionRule(readingSuffix: "させられる", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "させられない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "やすい", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "やすく", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "やすくない", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan]),
        InflectionRule(readingSuffix: "やすかった", baseReadingSuffix: "る", allowedClasses: [InflectionClass.ichidan])
    ]

    private static let godanPatterns: [GodanPattern] = [
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

    private static func teShimauInflectionSuffixes(for teForm: String) -> [String] {
        guard !teForm.isEmpty else {
            return []
        }

        var suffixes = [
            teForm + "しまう",
            teForm + "しまわない",
            teForm + "しまわなかった",
            teForm + "しまいます",
            teForm + "しまいました",
            teForm + "しまいません",
            teForm + "しまった",
            teForm + "しまって"
        ]

        if teForm.hasSuffix("て") {
            let contractionStem = String(teForm.dropLast())
            suffixes.append(contractionStem + "ちゃう")
            suffixes.append(contractionStem + "ちゃわない")
            suffixes.append(contractionStem + "ちゃわなかった")
            suffixes.append(contractionStem + "ちゃいます")
            suffixes.append(contractionStem + "ちゃいました")
            suffixes.append(contractionStem + "ちゃいません")
            suffixes.append(contractionStem + "ちゃった")
            suffixes.append(contractionStem + "ちゃって")
        } else if teForm.hasSuffix("で") {
            let contractionStem = String(teForm.dropLast())
            suffixes.append(contractionStem + "じゃう")
            suffixes.append(contractionStem + "じゃわない")
            suffixes.append(contractionStem + "じゃわなかった")
            suffixes.append(contractionStem + "じゃいます")
            suffixes.append(contractionStem + "じゃいました")
            suffixes.append(contractionStem + "じゃいません")
            suffixes.append(contractionStem + "じゃった")
            suffixes.append(contractionStem + "じゃって")
        }

        return suffixes
    }

    private static func teOkuInflectionSuffixes(for teForm: String) -> [String] {
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
        }

        return suffixes
    }

    private static func teMiruInflectionSuffixes(for teForm: String) -> [String] {
        guard !teForm.isEmpty else {
            return []
        }

        return [
            teForm + "みる",
            teForm + "みた",
            teForm + "みて",
            teForm + "みない",
            teForm + "みなかった",
            teForm + "みます",
            teForm + "みました",
            teForm + "みません"
        ]
    }

    private static func taRiSuruInflectionSuffixes(for taForm: String) -> [String] {
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

    private static func teAspectInflectionSuffixes(for teForm: String) -> [String] {
        guard !teForm.isEmpty else {
            return []
        }

        return [
            teForm,
            teForm + "る",
            teForm + "いる",
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
    }

    private static let godanInflectionRules: [InflectionRule] = {
        var rules: [InflectionRule] = []

        for pattern in godanPatterns {
            var suffixes = [
                pattern.aForm + "ない",
                pattern.aForm + "なかった",
                pattern.aForm + "ねば",
                pattern.aForm + "ず",
                pattern.aForm + "れる",
                pattern.aForm + "れない",
                pattern.aForm + "せる",
                pattern.aForm + "せない",
                pattern.aForm + "せられる",
                pattern.aForm + "せられない",
                pattern.aForm + "れて",
                pattern.aForm + "れた",
                pattern.aForm + "れ",
                pattern.iForm + "ます",
                pattern.iForm + "ました",
                pattern.iForm + "ません",
                pattern.iForm + "たい",
                pattern.iForm + "たくない",
                pattern.iForm + "たかった",
                pattern.iForm + "にくい",
                pattern.iForm + "にくく",
                pattern.iForm + "にくくない",
                pattern.iForm + "にくかった",
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
                pattern.taForm
            ]

            suffixes.append(contentsOf: KanaKanjiConverter.taRiSuruInflectionSuffixes(for: pattern.taForm))
            suffixes.append(contentsOf: KanaKanjiConverter.teAspectInflectionSuffixes(for: pattern.teForm))
            suffixes.append(contentsOf: KanaKanjiConverter.teOkuInflectionSuffixes(for: pattern.teForm))
            suffixes.append(contentsOf: KanaKanjiConverter.teMiruInflectionSuffixes(for: pattern.teForm))
            suffixes.append(contentsOf: KanaKanjiConverter.teShimauInflectionSuffixes(for: pattern.teForm))

            for suffix in suffixes {
                rules.append(
                    InflectionRule(
                        readingSuffix: suffix,
                        baseReadingSuffix: pattern.dictionaryEnding,
                        allowedClasses: [pattern.inflectionClass]
                    )
                )
            }
        }

        return rules
    }()

    private static let suruInflectionRules: [InflectionRule] = [
        InflectionRule(readingSuffix: "しない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しなかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "します", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しました", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しません", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したい", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したくない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しにくい", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しにくく", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しにくくない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しにくかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
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
        InflectionRule(readingSuffix: "してた", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していた", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
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
        InflectionRule(readingSuffix: "してしまう", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまわない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまわなかった", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまいます", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまいました", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
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
        InflectionRule(readingSuffix: "した", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
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
        InflectionRule(readingSuffix: "されない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させる", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられる", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられない", baseReadingSuffix: "する", allowedClasses: [InflectionClass.suru])
    ]

    private static let sahenNounSuruInflectionRules: [InflectionRule] = [
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
        InflectionRule(readingSuffix: "したい", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したくない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "したかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しにくい", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しにくく", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しにくくない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "しにくかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
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
        InflectionRule(readingSuffix: "してた", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "していた", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
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
        InflectionRule(readingSuffix: "してしまう", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまわない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまわなかった", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまいます", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "してしまいました", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
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
        InflectionRule(readingSuffix: "した", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
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
        InflectionRule(readingSuffix: "されない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させる", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられる", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru]),
        InflectionRule(readingSuffix: "させられない", baseReadingSuffix: "", baseCandidateSuffixes: [""], allowedClasses: [InflectionClass.suru])
    ]

    private static let kuruInflectionForms: [(readingSuffix: String, kanjiOutputSuffix: String)] = [
        ("こない", "来ない"),
        ("こなかった", "来なかった"),
        ("こい", "来い"),
        ("きます", "来ます"),
        ("きました", "来ました"),
        ("きません", "来ません"),
        ("きたい", "来たい"),
        ("きたくない", "来たくない"),
        ("きたかった", "来たかった"),
        ("きにくい", "来にくい"),
        ("きにくく", "来にくく"),
        ("きにくくない", "来にくくない"),
        ("きにくかった", "来にくかった"),
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
        ("きてた", "来てた"),
        ("きていた", "来ていた"),
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
        ("きてしまう", "来てしまう"),
        ("きてしまわない", "来てしまわない"),
        ("きてしまわなかった", "来てしまわなかった"),
        ("きてしまいます", "来てしまいます"),
        ("きてしまいました", "来てしまいました"),
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
        ("きた", "来た"),
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

    private static let kuruInflectionRules: [InflectionRule] = {
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

    private static let allInflectionRules: [InflectionRule] =
        adjectiveInflectionRules
        + ichidanInflectionRules
        + godanInflectionRules
        + sahenNounSuruInflectionRules
        + suruInflectionRules
        + kuruInflectionRules

    private static let emptyStemAllowedBaseReadingSuffixes: Set<String> = [
        "する",
        "くる"
    ]

    private static let inflectionRankingSuffixes: [String] = [
        "させられない", "させられる", "せられない", "せられる", "こられない", "こられる", "られない", "られる",
        "こられ", "され", "られ",
        "くありませんでした", "くなかったです", "くないです", "かったです", "くありません",
        "すぎなかった", "すぎました", "すぎません", "にくくない", "すぎない", "すぎます", "にくかった",
        "させない", "させる", "せない", "せる", "やすくない", "たくない", "なかった", "やすかった", "たかった", "くなかった",
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
        "ちゃわなかった", "じゃわなかった", "ちゃいません", "じゃいません", "ちゃいました", "じゃいました", "ちゃいます", "じゃいます", "ちゃわない", "じゃわない",
        "ておかなかった", "でおかなかった", "とかなかった", "どかなかった", "ておきません", "でおきません", "ときません", "どきません", "ておきました", "でおきました", "ときました", "どきました",
        "ておきます", "でおきます", "ときます", "どきます", "ておかない", "でおかない", "とかない", "どかない", "ておいた", "でおいた", "といた", "どいた", "ておいて", "でおいて", "といて", "どいて",
        "てみなかった", "でみなかった", "てみません", "でみません", "てみました", "でみました", "てみます", "でみます", "てみない", "でみない", "ておく", "でおく", "とく", "どく", "てみた", "でみた", "てみて", "でみて", "てみる", "でみる",
        "てしまって", "でしまって", "ちゃって", "じゃって",
        "てしまった", "でしまった", "ちゃった", "じゃった",
        "てしまう", "でしまう", "ちゃう", "じゃう",
        "している", "きている", "でいる", "ている", "してる", "きてる", "でる", "てる",
        "きました", "しました", "きません", "しません", "ました", "ます",
        "くない", "かった", "ければ", "くれば", "やすい", "やすく", "よう", "こよう", "こい", "たい", "れば", "ねば", "ず",
        "って", "った", "いて", "いた", "いで", "いだ", "んで", "んだ", "して", "した",
        "ない", "きて", "きた", "くて", "て", "た"
    ]

    private static let ikuIrregularInflectionSuffixes: [String] = {
        var suffixes = ["った"]
        suffixes.append(contentsOf: KanaKanjiConverter.taRiSuruInflectionSuffixes(for: "った"))
        suffixes.append(contentsOf: KanaKanjiConverter.teAspectInflectionSuffixes(for: "って"))
        suffixes.append(contentsOf: KanaKanjiConverter.teOkuInflectionSuffixes(for: "って"))
        suffixes.append(contentsOf: KanaKanjiConverter.teMiruInflectionSuffixes(for: "って"))
        suffixes.append(contentsOf: KanaKanjiConverter.teShimauInflectionSuffixes(for: "って"))
        return suffixes
    }()

    private static let postfixPassthroughSuffixes: [String] = [
        "ほうがいい", "ほうがよい", "ほうが", "ようになる", "ようにする", "ようにして", "ように", "ような", "ようだ", "ようです", "こと", "では", "には", "とは", "へ", "は", "を", "に", "で", "と", "が", "も", "の", "ね", "よ", "な", "か", "や", "ぞ", "ぜ", "さ"
    ]
    private static let postfixPassthroughPrefixReplacements: [(from: String, to: String)] = [
        ("ほう", "方")
    ]
    private static let politePrefixPassthroughPrefixes: [String] = ["お"]

    private static let maxPostfixPassthroughDepth = 3

    private static let kuruKanjiCandidateBoost = 1450
    private static let godanImperativeCandidateBoost = 320
    private static let numericUnitFallbackCandidateBoost = 320

    private static let numericUnitFallbackCandidatesByReading: [String: [String]] = [
        "せんえん": ["千円"],
        "まんえん": ["万円"],
        "おくえん": ["億円"],
        "ちょうえん": ["兆円"]
    ]

    private static func postfixOutputSuffixVariants(for suffix: String) -> [String] {
        var variants = [suffix]

        for replacement in Self.postfixPassthroughPrefixReplacements where suffix.hasPrefix(replacement.from) {
            let tail = String(suffix.dropFirst(replacement.from.count))
            let converted = replacement.to + tail

            if !variants.contains(converted) {
                variants.append(converted)
            }
        }

        return variants
    }

    private static let iVowelKanaBeforeRu: Set<Character> = [
        "い", "き", "ぎ", "し", "じ", "ち", "ぢ", "に", "ひ", "び", "ぴ", "み", "り", "ゐ"
    ]

    private static let eVowelKanaBeforeRu: Set<Character> = [
        "え", "け", "げ", "せ", "ぜ", "て", "で", "ね", "へ", "べ", "ぺ", "め", "れ", "ゑ"
    ]

    private let store: KanaKanjiStore
    private let stateQueue = DispatchQueue(label: "com.kusakabe.ecritu.kana-kanji.converter-state")
    private var candidateCache: [CandidateCacheKey: [String]] = [:]
    private var candidateCacheOrder: [CandidateCacheKey] = []

    private let candidateCacheLimit = 96

    init(store: KanaKanjiStore) {
        self.store = store
    }

    func preloadSystemDictionaryIfNeeded(onLoaded: (() -> Void)? = nil) {
        store.prepareSystemDictionaryIfNeeded { [weak self] in
            guard let self else {
                onLoaded?()
                return
            }

            self.stateQueue.sync {
                self.invalidateCandidateCache()
            }

            onLoaded?()
        }
    }

    func clearSharedDataCaches() {
        store.clearSharedDataCaches()

        stateQueue.sync {
            invalidateCandidateCache()
        }
    }

    func clearAllCaches() {
        store.clearSystemDictionaryCaches()
        store.clearSharedDataCaches()

        stateQueue.sync {
            invalidateCandidateCache()
        }
    }

    func candidates(
        for reading: String,
        limit: Int,
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        let normalizedReading = KanaTextNormalizer.normalizedReading(reading)

        guard !normalizedReading.isEmpty,
                limit > 0 else {
            return []
        }

        let cacheKey = CandidateCacheKey(
            reading: normalizedReading,
            limit: limit,
            modeRawValue: systemCandidateMode.rawValue
        )

        if let cachedCandidates = stateQueue.sync(execute: { candidateCache[cacheKey] }) {
            return cachedCandidates
        }

        let manualUserDictionary = store.userDictionary()
        let learnedDictionary = store.learnedDictionary()
        let userDictionary = mergedDictionary(
            preferred: manualUserDictionary,
            fallback: learnedDictionary
        )
        let initialUserDictionary = store.initialUserDictionary()
        let learningScoresForReading = store.learningScores(for: normalizedReading)
        let suppressedCandidatesByReading = store.suppressedCandidatesByReading()
        var scores: [String: Int] = [:]
        let systemCandidates = systemCandidates(
            for: normalizedReading,
            mode: systemCandidateMode
        )
        let userCandidates = uniqueCandidates(
            from: (manualUserDictionary[normalizedReading] ?? [])
                + (initialUserDictionary[normalizedReading] ?? [])
        )
        let userCandidateSet = Set(userCandidates)
        let learnedCandidates = uniqueCandidates(
            from: (learnedDictionary[normalizedReading] ?? []).filter {
                !userCandidateSet.contains($0)
            }
        )
        let hasDirectCandidates = !systemCandidates.isEmpty
            || !userCandidates.isEmpty
            || !learnedCandidates.isEmpty

        addCandidates(
            systemCandidates,
            baseScore: 1200,
            to: &scores
        )
        addCandidates(
            userCandidates,
            baseScore: 2400,
            to: &scores
        )
        addCandidates(
            learnedCandidates,
            baseScore: 2280,
            to: &scores
        )

        addCandidates(
            inflectionCandidates(
                for: normalizedReading,
                userDictionary: userDictionary,
                initialUserDictionary: initialUserDictionary,
                systemCandidateMode: systemCandidateMode,
                limit: limit * 3
            ),
            baseScore: 980,
            to: &scores
        )

        addCandidates(
            politePrefixPassthroughCandidates(
                for: normalizedReading,
                userDictionary: userDictionary,
                initialUserDictionary: initialUserDictionary,
                systemCandidateMode: systemCandidateMode,
                limit: limit * 2
            ),
            baseScore: 1100,
            to: &scores
        )

        addCandidates(
            ordinalMeFallbackCandidates(
                for: normalizedReading,
                hasDirectCandidates: hasDirectCandidates,
                userDictionary: userDictionary,
                initialUserDictionary: initialUserDictionary,
                systemCandidateMode: systemCandidateMode,
                limit: limit * 2
            ),
            baseScore: 1080,
            to: &scores
        )

        let numericUnitFallback = numericUnitFallbackCandidates(
            for: normalizedReading,
            limit: limit * 2
        )

        addCandidates(
            numericUnitFallback,
            baseScore: 1070,
            to: &scores
        )

        applyNumericUnitFallbackPriorityBoost(
            for: normalizedReading,
            fallbackCandidates: numericUnitFallback,
            to: &scores
        )

        let quickPostfixCandidates = quickPostfixCandidatesUsingCachedStem(
            for: normalizedReading,
            limit: limit,
            systemCandidateMode: systemCandidateMode
        )

        if !quickPostfixCandidates.isEmpty {
            addCandidates(
                quickPostfixCandidates,
                baseScore: 1120,
                to: &scores
            )
        } else {
            addCandidates(
                postfixPassthroughCandidates(
                    for: normalizedReading,
                    userDictionary: userDictionary,
                    initialUserDictionary: initialUserDictionary,
                    systemCandidateMode: systemCandidateMode,
                    limit: limit * 3
                ),
                baseScore: 1040,
                to: &scores
            )
        }

        applyInflectionRankingHeuristics(
            for: normalizedReading,
            userDictionary: userDictionary,
            initialUserDictionary: initialUserDictionary,
            systemCandidateMode: systemCandidateMode,
            to: &scores
        )

        applyLearning(
            learningScoresForReading,
            to: &scores
        )

        if let suppressedCandidates = suppressedCandidatesByReading[normalizedReading],
            !suppressedCandidates.isEmpty {
            for candidate in suppressedCandidates {
                scores.removeValue(forKey: candidate)
            }
        }

        let sortedCandidates = scores.keys.sorted { lhs, rhs in
            let lhsScore = scores[lhs, default: 0]
            let rhsScore = scores[rhs, default: 0]

            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }

            if lhs.count != rhs.count {
                return lhs.count < rhs.count
            }

            return lhs < rhs
        }

        let finalCandidates = Array(sortedCandidates.prefix(limit))

        if !finalCandidates.isEmpty {
            stateQueue.sync {
                if candidateCache[cacheKey] == nil {
                    candidateCacheOrder.append(cacheKey)
                }

                candidateCache[cacheKey] = finalCandidates

                while candidateCacheOrder.count > candidateCacheLimit {
                    let removedKey = candidateCacheOrder.removeFirst()
                    candidateCache.removeValue(forKey: removedKey)
                }
            }
        }

        return finalCandidates
    }

    func learn(reading: String, candidate: String) {
        let normalizedReading = KanaTextNormalizer.normalizedReading(reading)
        let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedReading.isEmpty,
                !trimmedCandidate.isEmpty else {
            return
        }

        store.addLearnedEntry(reading: normalizedReading, candidate: trimmedCandidate)
        store.incrementLearning(reading: normalizedReading, candidate: trimmedCandidate)

        stateQueue.sync {
            invalidateCandidateCache()
        }
    }

    private func addCandidates(
        _ candidates: [String],
        baseScore: Int,
        to scores: inout [String: Int]
    ) {
        for (index, candidate) in uniqueCandidates(from: candidates).enumerated() {
            scores[candidate, default: 0] += max(1, baseScore - index)
        }
    }

    private func mergedDictionary(
        preferred: [String: [String]],
        fallback: [String: [String]]
    ) -> [String: [String]] {
        var merged = preferred

        for (reading, fallbackCandidates) in fallback {
            let combined = uniqueCandidates(
                from: (merged[reading] ?? []) + fallbackCandidates
            )

            if !combined.isEmpty {
                merged[reading] = combined
            }
        }

        return merged
    }

    private func applyLearning(
        _ learningScoresForReading: [String: Int],
        to scores: inout [String: Int]
    ) {
        for (candidate, count) in learningScoresForReading {
            scores[candidate, default: 0] += count * 64
        }
    }

    private func invalidateCandidateCache() {
        candidateCache.removeAll(keepingCapacity: true)
        candidateCacheOrder.removeAll(keepingCapacity: true)
    }

    private func quickPostfixCandidatesUsingCachedStem(
        for reading: String,
        limit: Int,
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        guard reading.count >= 2,
                limit > 0 else {
            return []
        }

        for passthrough in Self.postfixPassthroughSuffixes where reading.hasSuffix(passthrough) {
            let stem = String(reading.dropLast(passthrough.count))

            guard !stem.isEmpty else {
                continue
            }

            let stemKey = CandidateCacheKey(
                reading: stem,
                limit: limit,
                modeRawValue: systemCandidateMode.rawValue
            )

            guard let stemCandidates = stateQueue.sync(execute: { candidateCache[stemKey] }),
                    !stemCandidates.isEmpty else {
                continue
            }

            let suffixVariants = Self.postfixOutputSuffixVariants(for: passthrough)
            let derived = stemCandidates.flatMap { candidate in
                suffixVariants.map { candidate + $0 }
            }
            return Array(uniqueCandidates(from: derived).prefix(limit))
        }

        return []
    }

    private func applyInflectionRankingHeuristics(
        for reading: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode,
        to scores: inout [String: Int]
    ) {
        guard let matchedSuffix = matchingInflectionRankingSuffix(for: reading) else {
            applyGodanImperativeBoost(
                for: reading,
                userDictionary: userDictionary,
                initialUserDictionary: initialUserDictionary,
                systemCandidateMode: systemCandidateMode,
                to: &scores
            )
            return
        }

        for candidate in Array(scores.keys) {
            var delta = 0

            if candidate.hasSuffix(matchedSuffix) {
                delta += 220
            } else if !containsHiragana(candidate) {
                // Readings that look inflected should not prioritize pure-kanji name-like entries.
                delta -= 260
            }

            if delta != 0 {
                scores[candidate, default: 0] += delta
            }
        }

        applyKuruCandidateBoost(for: reading, to: &scores)
        applyGodanImperativeBoost(
            for: reading,
            userDictionary: userDictionary,
            initialUserDictionary: initialUserDictionary,
            systemCandidateMode: systemCandidateMode,
            to: &scores
        )
    }

    private func applyNumericUnitFallbackPriorityBoost(
        for reading: String,
        fallbackCandidates: [String],
        to scores: inout [String: Int]
    ) {
        guard hasLeadingNumberPrefix(in: reading),
            !fallbackCandidates.isEmpty else {
            return
        }

        for candidate in fallbackCandidates {
            scores[candidate, default: 0] += Self.numericUnitFallbackCandidateBoost
        }
    }

    private func hasLeadingNumberPrefix(in text: String) -> Bool {
        let trimmed = trimmingLeadingNumberPrefix(from: text)
        return !trimmed.isEmpty && trimmed != text
    }

    private func applyGodanImperativeBoost(
        for reading: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode,
        to scores: inout [String: Int]
    ) {
        for pattern in Self.godanPatterns where reading.hasSuffix(pattern.eForm) {
            guard let stem = removingSuffix(reading, suffix: pattern.eForm) else {
                continue
            }

            let baseReading = stem + pattern.dictionaryEnding
            let baseCandidates = Set(
                candidatesForReading(
                    baseReading,
                    userDictionary: userDictionary,
                    initialUserDictionary: initialUserDictionary,
                    systemCandidateMode: systemCandidateMode
                )
            )

            guard !baseCandidates.isEmpty else {
                continue
            }

            for candidate in Array(scores.keys) where candidate.hasSuffix(pattern.eForm) {
                let candidateStem = String(candidate.dropLast(pattern.eForm.count))
                let baseCandidate = candidateStem + pattern.dictionaryEnding

                guard baseCandidates.contains(baseCandidate) else {
                    continue
                }

                scores[candidate, default: 0] += Self.godanImperativeCandidateBoost
            }
        }
    }

    private func applyKuruCandidateBoost(
        for reading: String,
        to scores: inout [String: Int]
    ) {
        for form in Self.kuruInflectionForms where reading.hasSuffix(form.readingSuffix) {
            for candidate in Array(scores.keys) where candidate.hasSuffix(form.kanjiOutputSuffix) {
                scores[candidate, default: 0] += Self.kuruKanjiCandidateBoost
            }
        }
    }

    private func matchingInflectionRankingSuffix(for reading: String) -> String? {
        for suffix in Self.inflectionRankingSuffixes where reading.hasSuffix(suffix) {
            return suffix
        }

        return nil
    }

    private func containsHiragana(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            if (0x3040...0x309F).contains(scalar.value) || scalar.value == 0x30FC {
                return true
            }
        }

        return false
    }

    private func inflectionCandidates(
        for reading: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode,
        limit: Int
    ) -> [String] {
        guard reading.count >= 2,
                limit > 0 else {
            return []
        }

        var derived: [String] = []

        // "行く" is irregular in te/ta forms (行って/行った), so place it first.
        derived.append(
            contentsOf: deriveIkuIrregularCandidates(
                for: reading,
                userDictionary: userDictionary,
                initialUserDictionary: initialUserDictionary,
                systemCandidateMode: systemCandidateMode
            )
        )

        for rule in Self.allInflectionRules {
            derived.append(
                contentsOf: derivedCandidates(
                    for: reading,
                    rule: rule,
                    userDictionary: userDictionary,
                    initialUserDictionary: initialUserDictionary,
                    systemCandidateMode: systemCandidateMode
                )
            )
        }

        return Array(uniqueCandidates(from: derived).prefix(limit))
    }

    private func postfixPassthroughCandidates(
        for reading: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode,
        limit: Int
    ) -> [String] {
        guard reading.count >= 2,
                limit > 0 else {
            return []
        }

        var derived: [String] = []
        var queue: [(stem: String, suffix: String, depth: Int)] = [(reading, "", 0)]
        var visited = Set<String>()

        while !queue.isEmpty {
            let current = queue.removeFirst()

            guard current.depth < Self.maxPostfixPassthroughDepth else {
                continue
            }

            for passthrough in Self.postfixPassthroughSuffixes where current.stem.hasSuffix(passthrough) {
                let nextStem = String(current.stem.dropLast(passthrough.count))

                guard !nextStem.isEmpty else {
                    continue
                }

                let nextSuffix = passthrough + current.suffix
                let visitKey = nextStem + "\u{1}" + nextSuffix

                guard visited.insert(visitKey).inserted else {
                    continue
                }

                let stemCandidates = uniqueCandidates(
                    from: candidatesForReading(
                        nextStem,
                        userDictionary: userDictionary,
                        initialUserDictionary: initialUserDictionary,
                        systemCandidateMode: systemCandidateMode
                    ) + inflectionCandidates(
                        for: nextStem,
                        userDictionary: userDictionary,
                        initialUserDictionary: initialUserDictionary,
                        systemCandidateMode: systemCandidateMode,
                        limit: limit
                    )
                )

                for candidate in stemCandidates {
                    for outputSuffix in Self.postfixOutputSuffixVariants(for: nextSuffix) {
                        derived.append(candidate + outputSuffix)
                    }
                }

                queue.append((nextStem, nextSuffix, current.depth + 1))
            }
        }

        return Array(uniqueCandidates(from: derived).prefix(limit))
    }

    private func politePrefixPassthroughCandidates(
        for reading: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode,
        limit: Int
    ) -> [String] {
        guard reading.count >= 2,
            limit > 0 else {
            return []
        }

        var derived: [String] = []

        for prefix in Self.politePrefixPassthroughPrefixes where reading.hasPrefix(prefix) {
            let stem = String(reading.dropFirst(prefix.count))

            guard !stem.isEmpty else {
                continue
            }

            let stemCandidates = candidatesForReading(
                stem,
                userDictionary: userDictionary,
                initialUserDictionary: initialUserDictionary,
                systemCandidateMode: systemCandidateMode
            )

            guard !stemCandidates.isEmpty else {
                continue
            }

            let metadata = inflectionMetadata(for: stem)
            let userCandidateSet = Set(
                (userDictionary[stem] ?? []) + (initialUserDictionary[stem] ?? [])
            )

            for candidate in stemCandidates {
                guard resolvedInflectionClass(
                    for: candidate,
                    baseReading: stem,
                    systemClassMap: metadata.classMap,
                    hasSystemMetadata: metadata.hasMetadata,
                    userCandidateSet: userCandidateSet
                ) == nil else {
                    continue
                }

                guard shouldApplyPolitePrefix(prefix, to: candidate) else {
                    continue
                }

                derived.append(prefix + candidate)
            }
        }

        return Array(uniqueCandidates(from: derived).prefix(limit))
    }

    private func ordinalMeFallbackCandidates(
        for reading: String,
        hasDirectCandidates: Bool,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode,
        limit: Int
    ) -> [String] {
        guard !hasDirectCandidates,
            reading.count >= 2,
            reading.hasSuffix("め"),
            limit > 0 else {
            return []
        }

        let stem = String(reading.dropLast(1))

        guard !stem.isEmpty else {
            return []
        }

        var stemCandidates = uniqueCandidates(
            from: candidatesForReading(
                stem,
                userDictionary: userDictionary,
                initialUserDictionary: initialUserDictionary,
                systemCandidateMode: systemCandidateMode
            ) + inflectionCandidates(
                for: stem,
                userDictionary: userDictionary,
                initialUserDictionary: initialUserDictionary,
                systemCandidateMode: systemCandidateMode,
                limit: limit
            )
        )

        if stemCandidates.isEmpty {
            let trimmedStem = trimmingLeadingNumberPrefix(from: stem)

            if !trimmedStem.isEmpty,
                trimmedStem != stem {
                stemCandidates = uniqueCandidates(
                    from: candidatesForReading(
                        trimmedStem,
                        userDictionary: userDictionary,
                        initialUserDictionary: initialUserDictionary,
                        systemCandidateMode: systemCandidateMode
                    ) + inflectionCandidates(
                        for: trimmedStem,
                        userDictionary: userDictionary,
                        initialUserDictionary: initialUserDictionary,
                        systemCandidateMode: systemCandidateMode,
                        limit: limit
                    )
                )
            }
        }

        guard !stemCandidates.isEmpty else {
            return []
        }

        let kanjiStemCandidates = stemCandidates.filter(containsKanji)
        let nonKanjiStemCandidates = stemCandidates.filter { !containsKanji($0) }

        guard !kanjiStemCandidates.isEmpty else {
            return []
        }

        var derived: [String] = []

        for candidate in kanjiStemCandidates {
            derived.append(candidate + "め")
        }

        for candidate in nonKanjiStemCandidates {
            derived.append(candidate + "め")
        }

        // Keep kanji+"目" candidates available, but behind kanji+"め".
        for candidate in kanjiStemCandidates {
            derived.append(candidate + "目")
        }

        return Array(uniqueCandidates(from: derived).prefix(limit))
    }

    private func numericUnitFallbackCandidates(
        for reading: String,
        limit: Int
    ) -> [String] {
        guard limit > 0 else {
            return []
        }

        var lookupKeys = [reading]
        let trimmedReading = trimmingLeadingNumberPrefix(from: reading)

        if !trimmedReading.isEmpty,
            trimmedReading != reading {
            lookupKeys.append(trimmedReading)
        }

        var derived: [String] = []

        for key in lookupKeys {
            if let fallbackCandidates = Self.numericUnitFallbackCandidatesByReading[key] {
                derived.append(contentsOf: fallbackCandidates)
            }
        }

        return Array(uniqueCandidates(from: derived).prefix(limit))
    }

    private func shouldApplyPolitePrefix(_ prefix: String, to candidate: String) -> Bool {
        guard !candidate.hasPrefix(prefix),
            !candidate.hasPrefix("御"),
            let firstScalar = candidate.unicodeScalars.first else {
            return false
        }

        if (0x4E00...0x9FFF).contains(firstScalar.value)
            || (0x3400...0x4DBF).contains(firstScalar.value)
            || firstScalar.value == 0x3005 {
            return true
        }

        return false
    }

    private func deriveIkuIrregularCandidates(
        for reading: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        var results: [String] = []

        for irregularSuffix in Self.ikuIrregularInflectionSuffixes {
            guard let stem = removingSuffix(reading, suffix: irregularSuffix) else {
                continue
            }

            let baseReading = stem + "く"
            for candidate in candidatesForReading(
                baseReading,
                userDictionary: userDictionary,
                initialUserDictionary: initialUserDictionary,
                systemCandidateMode: systemCandidateMode
            ) where candidate.hasSuffix("行く") {
                let prefix = String(candidate.dropLast("行く".count))
                results.append(prefix + "行" + irregularSuffix)
            }
        }

        return results
    }

    private func derivedCandidates(
        for reading: String,
        rule: InflectionRule,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        guard let readingStem = removingSuffix(reading, suffix: rule.readingSuffix) else {
            return []
        }

        if readingStem.isEmpty,
            !Self.emptyStemAllowedBaseReadingSuffixes.contains(rule.baseReadingSuffix) {
            return []
        }

        let baseReading = readingStem + rule.baseReadingSuffix

        let baseCandidates = candidatesForReading(
            baseReading,
            userDictionary: userDictionary,
            initialUserDictionary: initialUserDictionary,
            systemCandidateMode: systemCandidateMode
        )

        guard !baseCandidates.isEmpty else {
            return []
        }

        let metadata = inflectionMetadata(for: baseReading)
        let userCandidateSet = Set(
            (userDictionary[baseReading] ?? []) + (initialUserDictionary[baseReading] ?? [])
        )
        var results: [String] = []

        for candidate in baseCandidates {
            guard let matchedSuffix = rule.baseCandidateSuffixes.first(where: { candidate.hasSuffix($0) }) else {
                continue
            }

            let resolvedClass = resolvedInflectionClass(
                for: candidate,
                baseReading: baseReading,
                systemClassMap: metadata.classMap,
                hasSystemMetadata: metadata.hasMetadata,
                userCandidateSet: userCandidateSet
            )

            let inflectionClass = resolvedClass
                ?? inferredSahenInflectionClass(
                    for: candidate,
                    rule: rule
                )

            guard let inflectionClass,
                rule.allowedClasses.contains(inflectionClass) else {
                continue
            }

            let stem = String(candidate.dropLast(matchedSuffix.count))
            results.append(stem + rule.outputCandidateSuffix)
        }

        return results
    }

    private func inflectionMetadata(for reading: String) -> (classMap: [String: String], hasMetadata: Bool) {
        store.systemInflectionMetadata(for: reading)
    }

    private func resolvedInflectionClass(
        for candidate: String,
        baseReading: String,
        systemClassMap: [String: String],
        hasSystemMetadata: Bool,
        userCandidateSet: Set<String>
    ) -> String? {
        if let inflectionClass = systemClassMap[candidate] {
            return inflectionClass
        }

        // Keep inference only as fallback for user dictionary entries.
        guard !hasSystemMetadata || userCandidateSet.contains(candidate) else {
            return nil
        }

        return inferredInflectionClass(for: candidate, baseReading: baseReading)
    }

    private func inferredSahenInflectionClass(
        for candidate: String,
        rule: InflectionRule
    ) -> String? {
        guard rule.baseReadingSuffix.isEmpty,
            rule.allowedClasses == [InflectionClass.suru],
            !candidate.hasSuffix("する"),
            !candidate.hasSuffix("くる"),
            !candidate.hasSuffix("来る"),
            !containsHiragana(candidate),
            containsKanjiOrKatakana(candidate) else {
            return nil
        }

        return InflectionClass.suru
    }

    private func inferredInflectionClass(for candidate: String, baseReading: String) -> String? {
        if candidate.hasSuffix("する") {
            return InflectionClass.suru
        }

        if candidate.hasSuffix("来る") || candidate.hasSuffix("くる") {
            return InflectionClass.kuru
        }

        if baseReading.hasSuffix("る") && candidate.hasSuffix("る") {
            if isLikelyIchidanBaseReading(baseReading) {
                return InflectionClass.ichidan
            }

            return InflectionClass.godanRu
        }

        for pattern in Self.godanPatterns where baseReading.hasSuffix(pattern.dictionaryEnding) {
            if candidate.hasSuffix(pattern.dictionaryEnding) {
                return pattern.inflectionClass
            }
        }

        if baseReading.hasSuffix("い") && candidate.hasSuffix("い") {
            return InflectionClass.adjectiveI
        }

        return nil
    }

    private func isLikelyIchidanBaseReading(_ reading: String) -> Bool {
        guard reading.hasSuffix("る"),
                reading.count >= 2 else {
            return false
        }

        let chars = Array(reading)
        let preRu = chars[chars.count - 2]

        return Self.iVowelKanaBeforeRu.contains(preRu)
            || Self.eVowelKanaBeforeRu.contains(preRu)
    }

    private func containsKanjiOrKatakana(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            if (0x30A0...0x30FF).contains(scalar.value)
                || (0x3400...0x9FFF).contains(scalar.value) {
                return true
            }
        }

        return false
    }

    private func containsKanji(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            if (0x3400...0x9FFF).contains(scalar.value) {
                return true
            }
        }

        return false
    }

    private func systemCandidates(
        for reading: String,
        mode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        let storeCandidates = store.systemCandidates(for: reading, mode: mode)

        if storeCandidates.isEmpty {
            return KanaKanjiSeedDictionary.seed[reading] ?? []
        }

        return uniqueCandidates(
            from: storeCandidates + (KanaKanjiSeedDictionary.seed[reading] ?? [])
        )
    }

    private func candidatesForReading(
        _ reading: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        uniqueCandidates(
            from: (userDictionary[reading] ?? [])
                + (initialUserDictionary[reading] ?? [])
                + systemCandidates(for: reading, mode: systemCandidateMode)
        )
    }

    private func removingSuffix(_ text: String, suffix: String) -> String? {
        guard !suffix.isEmpty,
                text.hasSuffix(suffix) else {
            return nil
        }

        return String(text.dropLast(suffix.count))
    }

    private func trimmingLeadingNumberPrefix(from text: String) -> String {
        String(text.drop(while: { $0.isNumber }))
    }

    private func uniqueCandidates(from candidates: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmed.isEmpty,
                    !seen.contains(trimmed) else {
                continue
            }

            seen.insert(trimmed)
            result.append(trimmed)
        }

        return result
    }
}
