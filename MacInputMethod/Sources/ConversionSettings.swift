import EcrituConversion
import Foundation

/// 変換の設定(iPhone のアプリの X.1〜X.13)。エンジンへの入れ方は iOS のキーボードと同じ
/// (KeyboardExtension/KeyboardViewController+Settings.swift の applyConverterFeatureFlagsFromSharedDefaults)。
/// 保存のキーと値の形も iOS と同じにして、あとで読み書きを共有できるようにする
struct ConversionSettings: Equatable {
    /// X.1 かな漢字候補モード(エンジンの設定ではなく、変換のたびに systemCandidateMode として渡す)
    var candidateSourceMode: KanaKanjiCandidateSourceMode
    /// X.2 旧仮名遣い候補
    var historicalKanaAllowed: Bool
    /// X.3 仮名の踊り字候補
    var iterationMarkAllowed: Bool
    /// X.4 カタカナ強調表記の候補
    var katakanaEmphasisMode: ScriptVariantCandidateMode
    /// X.5 交ぜ書きの候補
    var mixedScriptMode: ScriptVariantCandidateMode
    /// X.6 旧字体・異体字の候補(入っている小分類を抑制する)
    var suppressedScriptVariants: Set<ScriptVariantSuppressionCategory>
    /// X.7 かなで書く言葉の候補(入っている仲間を抑制する)
    var suppressedKanaSpellings: Set<KanaSpellingCategory>
    /// X.8 常用漢字による書きかえ
    var kanjiRewrite: KanjiRewritePreference
    /// X.8 の例外(日常語は常用漢字を先に)
    var kanjiRewriteEverydayException: Bool
    /// X.9 常用漢字による書きかえ(後に追加)
    var lateStandardizedRewrite: KanjiRewritePreference
    /// X.10 助数詞の『か』の表記
    var kaCounterVariants: KaCounterVariantPreference
    /// X.11 送り仮名の許容形
    var inflectionalKanaVariants: InflectionalKanaVariantPreference
    /// X.12 序数化: 目(漢字)が先か
    var ordinalMeKanjiPreferred: Bool
    /// X.12 形式名詞化: 形式名詞の『目』にひらがな『め』の候補も出すか
    var formalNounMeKanaEnabled: Bool
    /// X.12 形状名詞化・傾向派生: 程度の『め』に漢字『目』の候補も出すか
    var adjectiveMeKanjiEnabled: Bool
    /// X.13 数詞の表記
    var numeralStyle: NumeralStylePreference

    /// 現代的初期設定の値(iOS: App/ContentView+LogoMenu.swift の contemporaryPresetValues のうち X.1〜X.13)。
    /// 値の無い Mac はこれで動く(この設定画面を作る前の ConversionService が入れていた値と同じ)
    static let contemporary = ConversionSettings(
        candidateSourceMode: .surface,
        historicalKanaAllowed: false,
        iterationMarkAllowed: false,
        katakanaEmphasisMode: .suppress,
        mixedScriptMode: .suppress,
        suppressedScriptVariants: [.kyujitai, .itaiji, .ryakuji, .confusable, .lookalike],
        suppressedKanaSpellings: [.adverb, .conjunction, .auxiliary, .formalNoun, .demonstrative],
        kanjiRewrite: .bothBeforeFirst,
        kanjiRewriteEverydayException: true,
        lateStandardizedRewrite: .bothBeforeFirst,
        kaCounterVariants: .conservative,
        inflectionalKanaVariants: .contemporary,
        ordinalMeKanjiPreferred: false,
        formalNounMeKanaEnabled: true,
        adjectiveMeKanjiEnabled: true,
        numeralStyle: .contemporaryDefault
    )

    /// 保存のキー。iOS の App/SettingsModels.swift の SettingsKeys(拡張側は SharedDefaultsKeys)と同じ文字列。
    /// X.6・X.7 の小分類のキーはパッケージの settingsKey を使う
    enum Key {
        static let candidateSourceMode = "kanaKanjiCandidateSourceMode"
        static let historicalKana = "historicalKanaCandidatesEnabled"
        static let iterationMark = "iterationMarkCandidatesEnabled"
        static let katakanaEmphasis = "katakanaEmphasisCandidateMode"
        static let mixedScript = "mazegakiCandidateMode"
        static let kanjiRewrite = "kakikaePreference"
        static let kanjiRewriteEverydayException = "kakikaeEverydayException"
        static let lateStandardizedRewrite = "lateStandardizedRewritePreference"
        static let kaCounterVariants = "kaCounterVariantPreference"
        static let inflectionalKanaVariants = "okuriganaVariantPreference"
        static let ordinalMeKanjiPreferred = "ordinalMeKanjiPreferred"
        static let formalNounMeKana = "formalNounMeKanaCandidatesEnabled"
        static let adjectiveMeKanji = "adjectiveMeKanjiCandidatesEnabled"
        static let numeralStyle = "numeralStylePreference"
    }

    init(
        candidateSourceMode: KanaKanjiCandidateSourceMode,
        historicalKanaAllowed: Bool,
        iterationMarkAllowed: Bool,
        katakanaEmphasisMode: ScriptVariantCandidateMode,
        mixedScriptMode: ScriptVariantCandidateMode,
        suppressedScriptVariants: Set<ScriptVariantSuppressionCategory>,
        suppressedKanaSpellings: Set<KanaSpellingCategory>,
        kanjiRewrite: KanjiRewritePreference,
        kanjiRewriteEverydayException: Bool,
        lateStandardizedRewrite: KanjiRewritePreference,
        kaCounterVariants: KaCounterVariantPreference,
        inflectionalKanaVariants: InflectionalKanaVariantPreference,
        ordinalMeKanjiPreferred: Bool,
        formalNounMeKanaEnabled: Bool,
        adjectiveMeKanjiEnabled: Bool,
        numeralStyle: NumeralStylePreference
    ) {
        self.candidateSourceMode = candidateSourceMode
        self.historicalKanaAllowed = historicalKanaAllowed
        self.iterationMarkAllowed = iterationMarkAllowed
        self.katakanaEmphasisMode = katakanaEmphasisMode
        self.mixedScriptMode = mixedScriptMode
        self.suppressedScriptVariants = suppressedScriptVariants
        self.suppressedKanaSpellings = suppressedKanaSpellings
        self.kanjiRewrite = kanjiRewrite
        self.kanjiRewriteEverydayException = kanjiRewriteEverydayException
        self.lateStandardizedRewrite = lateStandardizedRewrite
        self.kaCounterVariants = kaCounterVariants
        self.inflectionalKanaVariants = inflectionalKanaVariants
        self.ordinalMeKanjiPreferred = ordinalMeKanjiPreferred
        self.formalNounMeKanaEnabled = formalNounMeKanaEnabled
        self.adjectiveMeKanjiEnabled = adjectiveMeKanjiEnabled
        self.numeralStyle = numeralStyle
    }

    /// 保存した値を読む。値の読み方(真偽は Bool として、選択肢は rawValue、X.10・X.11 はパッケージの decode)は iOS と同じ。
    /// 値が無い・読めないときは、そのキーだけ現代的初期設定の値にする(iOS のキーボードの代わりの値は戦略的初期設定寄りの
    /// ものがあるが、Mac は現代的初期設定で始める)
    init(defaults: UserDefaults) {
        let base = Self.contemporary
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            defaults.object(forKey: key) as? Bool ?? fallback
        }
        func string(_ key: String) -> String? {
            defaults.object(forKey: key) as? String
        }

        candidateSourceMode = string(Key.candidateSourceMode).flatMap(KanaKanjiCandidateSourceMode.init(rawValue:))
            ?? base.candidateSourceMode
        historicalKanaAllowed = bool(Key.historicalKana, base.historicalKanaAllowed)
        iterationMarkAllowed = bool(Key.iterationMark, base.iterationMarkAllowed)
        katakanaEmphasisMode = string(Key.katakanaEmphasis).flatMap(ScriptVariantCandidateMode.init(rawValue:))
            ?? base.katakanaEmphasisMode
        mixedScriptMode = string(Key.mixedScript).flatMap(ScriptVariantCandidateMode.init(rawValue:))
            ?? base.mixedScriptMode
        suppressedScriptVariants = Set(ScriptVariantSuppressionCategory.allCases.filter { category in
            bool(category.settingsKey, base.suppressedScriptVariants.contains(category))
        })
        suppressedKanaSpellings = Set(KanaSpellingCategory.allCases.filter { category in
            bool(category.settingsKey, base.suppressedKanaSpellings.contains(category))
        })
        kanjiRewrite = string(Key.kanjiRewrite).flatMap(KanjiRewritePreference.init(rawValue:)) ?? base.kanjiRewrite
        kanjiRewriteEverydayException = bool(Key.kanjiRewriteEverydayException, base.kanjiRewriteEverydayException)
        lateStandardizedRewrite = string(Key.lateStandardizedRewrite).flatMap(KanjiRewritePreference.init(rawValue:))
            ?? base.lateStandardizedRewrite
        kaCounterVariants = string(Key.kaCounterVariants).flatMap(Self.decodedKaCounterVariants) ?? base.kaCounterVariants
        inflectionalKanaVariants = string(Key.inflectionalKanaVariants).flatMap(Self.decodedInflectionalKanaVariants)
            ?? base.inflectionalKanaVariants
        ordinalMeKanjiPreferred = bool(Key.ordinalMeKanjiPreferred, base.ordinalMeKanjiPreferred)
        formalNounMeKanaEnabled = bool(Key.formalNounMeKana, base.formalNounMeKanaEnabled)
        adjectiveMeKanjiEnabled = bool(Key.adjectiveMeKanji, base.adjectiveMeKanjiEnabled)
        numeralStyle = string(Key.numeralStyle).flatMap(NumeralStylePreference.init(rawValue:)) ?? base.numeralStyle
    }

    /// iOS のアプリが書くのと同じキー・同じ形で書く(真偽は Bool、選択肢は rawValue、X.10・X.11 は encoded)
    func save(to defaults: UserDefaults) {
        defaults.set(candidateSourceMode.rawValue, forKey: Key.candidateSourceMode)
        defaults.set(historicalKanaAllowed, forKey: Key.historicalKana)
        defaults.set(iterationMarkAllowed, forKey: Key.iterationMark)
        defaults.set(katakanaEmphasisMode.rawValue, forKey: Key.katakanaEmphasis)
        defaults.set(mixedScriptMode.rawValue, forKey: Key.mixedScript)
        for category in ScriptVariantSuppressionCategory.allCases {
            defaults.set(suppressedScriptVariants.contains(category), forKey: category.settingsKey)
        }
        for category in KanaSpellingCategory.allCases {
            defaults.set(suppressedKanaSpellings.contains(category), forKey: category.settingsKey)
        }
        defaults.set(kanjiRewrite.rawValue, forKey: Key.kanjiRewrite)
        defaults.set(kanjiRewriteEverydayException, forKey: Key.kanjiRewriteEverydayException)
        defaults.set(lateStandardizedRewrite.rawValue, forKey: Key.lateStandardizedRewrite)
        defaults.set(kaCounterVariants.encoded, forKey: Key.kaCounterVariants)
        defaults.set(inflectionalKanaVariants.encoded, forKey: Key.inflectionalKanaVariants)
        defaults.set(ordinalMeKanjiPreferred, forKey: Key.ordinalMeKanjiPreferred)
        defaults.set(formalNounMeKanaEnabled, forKey: Key.formalNounMeKana)
        defaults.set(adjectiveMeKanjiEnabled, forKey: Key.adjectiveMeKanji)
        defaults.set(numeralStyle.rawValue, forKey: Key.numeralStyle)
    }

    /// エンジンへ入れる(X.1 を除く。X.1 は変換のたびに渡す)
    func apply(to converter: KanaKanjiConverter) {
        converter.setHistoricalKanaSurfaceAllowed(historicalKanaAllowed)
        converter.setIterationMarkSurfaceAllowed(iterationMarkAllowed)
        converter.setKatakanaEmphasisCandidateMode(katakanaEmphasisMode)
        converter.setMixedScriptCandidateMode(mixedScriptMode)
        converter.setScriptVariantSuppressionCategories(suppressedScriptVariants)
        converter.setKanaSpellingSuppressedCategories(suppressedKanaSpellings)
        converter.setKanjiRewritePreference(kanjiRewrite)
        converter.setKanjiRewriteEverydayException(kanjiRewriteEverydayException)
        converter.setLateStandardizedRewritePreference(lateStandardizedRewrite)
        converter.setOrdinalMeKanjiPreferred(ordinalMeKanjiPreferred)
        converter.setKaCounterVariantPreference(kaCounterVariants)
        converter.setNumeralStylePreference(numeralStyle)
        converter.setInflectionalKanaVariantPreference(inflectionalKanaVariants)
        converter.setAdjectiveMeKanjiCandidatesEnabled(adjectiveMeKanjiEnabled)
        converter.setFormalNounMeKanaCandidatesEnabled(formalNounMeKanaEnabled)
    }

    /// X.10 の保存値を読む。読み方はパッケージの decode(iOS と同じ)。表記を1つも読めない値は読めないものとして nil
    /// (decode はそのとき全部オフの並びを返すので、そのまま使うと候補から『か』の表記が全部消える)
    private static func decodedKaCounterVariants(_ encoded: String) -> KaCounterVariantPreference? {
        let recognizesAnyVariant = encoded.split(separator: ",").contains { token in
            let raw = token.hasPrefix("-") ? String(token.dropFirst()) : String(token)
            // 旧形式(表記そのもの。"か" など)も decode は受け付ける
            return KaCounterVariant(rawValue: raw) != nil
                || KaCounterVariant.allCases.contains { String($0.character) == raw }
        }
        return recognizesAnyVariant ? KaCounterVariantPreference.decode(encoded) : nil
    }

    /// X.11 の保存値を読む。読み方はパッケージの decode(iOS と同じ)。グループを1つも読めない値は読めないものとして nil
    /// (decode はそのとき戦略的初期設定の値を返す)
    private static func decodedInflectionalKanaVariants(_ encoded: String) -> InflectionalKanaVariantPreference? {
        let recognizesAnyGroup = encoded.split(separator: ",").contains { token in
            let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
            return parts.count == 2
                && InflectionalKanaVariantGroup(rawValue: parts[0]) != nil
                && InflectionalKanaVariantMode(rawValue: parts[1]) != nil
        }
        return recognizesAnyGroup ? InflectionalKanaVariantPreference.decode(encoded) : nil
    }
}
