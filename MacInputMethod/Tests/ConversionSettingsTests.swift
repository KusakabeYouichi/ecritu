import EcrituConversion
import XCTest

/// 変換の設定(X.1〜X.13)の保存・読み込みと、ConversionService での効き方の検査。
/// 一時の suite と一時ディレクトリーを使い、利用者の設定・学習を汚さない
final class ConversionSettingsTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var containerDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "jp.or.pleiades.merope.inputmethod.ecritu.tests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        containerDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EcrituPourMacTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: containerDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaults = nil
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        if let containerDirectory {
            try? FileManager.default.removeItem(at: containerDirectory)
        }
        containerDirectory = nil
        KanaKanjiStore.sharedContainerURLOverride = nil
        try super.tearDownWithError()
    }

    private func makeService() -> ConversionService {
        let service = ConversionService(appGroupID: suiteName, containerDirectory: containerDirectory)
        service.preload()
        return service
    }

    /// 13項目のどれも現代的初期設定と違う値(1項目に複数の値があるものは全部変える)
    private static let changedEverywhere = ConversionSettings(
        candidateSourceMode: .lesDeux,
        historicalKanaAllowed: true,
        iterationMarkAllowed: true,
        katakanaEmphasisMode: .demote,
        mixedScriptMode: .normal,
        suppressedScriptVariants: [.ryakuji, .personNameVariant],
        suppressedKanaSpellings: [.formalNoun, .adverbKanaFirst],
        kanjiRewrite: .afterOnly,
        kanjiRewriteEverydayException: false,
        lateStandardizedRewrite: .beforeOnly,
        kaCounterVariants: KaCounterVariantPreference.decode("ke,-hiragana,kanji,-smallKe,ko,-katakana,-smallKa"),
        inflectionalKanaVariants: InflectionalKanaVariantPreference.decode("stem:permittedFirst,compound:standardOnly,noun:permittedFirst"),
        ordinalMeKanjiPreferred: true,
        formalNounMeKanaEnabled: false,
        adjectiveMeKanjiEnabled: false,
        numeralStyle: .kanjiOnly
    )

    // MARK: - 保存と読み込み

    func testEmptyDefaultsLoadContemporaryPresetValues() {
        let loaded = ConversionSettings(defaults: defaults)
        // 現代的初期設定(iOS の contemporaryPresetValues)を1つずつ具体値で書く
        XCTAssertEqual(loaded.candidateSourceMode, .surface)
        XCTAssertFalse(loaded.historicalKanaAllowed)
        XCTAssertFalse(loaded.iterationMarkAllowed)
        XCTAssertEqual(loaded.katakanaEmphasisMode, .suppress)
        XCTAssertEqual(loaded.mixedScriptMode, .suppress)
        XCTAssertEqual(loaded.suppressedScriptVariants, [.kyujitai, .itaiji, .ryakuji, .confusable, .lookalike])
        XCTAssertEqual(loaded.suppressedKanaSpellings, [.adverb, .conjunction, .auxiliary, .formalNoun, .demonstrative])
        XCTAssertEqual(loaded.kanjiRewrite, .bothBeforeFirst)
        XCTAssertTrue(loaded.kanjiRewriteEverydayException)
        XCTAssertEqual(loaded.lateStandardizedRewrite, .bothBeforeFirst)
        XCTAssertEqual(loaded.kaCounterVariants.order, [.hiragana, .kanji, .smallKe, .katakana, .smallKa, .ko, .ke])
        XCTAssertEqual(loaded.kaCounterVariants.enabled, [.hiragana, .kanji, .smallKe, .katakana])
        XCTAssertEqual(loaded.inflectionalKanaVariants.mode(for: .stemInternal), .standardOnly)
        XCTAssertEqual(loaded.inflectionalKanaVariants.mode(for: .compoundFront), .standardFirst)
        XCTAssertEqual(loaded.inflectionalKanaVariants.mode(for: .nominalized), .standardFirst)
        XCTAssertFalse(loaded.ordinalMeKanjiPreferred)
        XCTAssertTrue(loaded.formalNounMeKanaEnabled)
        XCTAssertTrue(loaded.adjectiveMeKanjiEnabled)
        XCTAssertEqual(loaded.numeralStyle, .arabicFirst)
        XCTAssertEqual(loaded, .contemporary)
    }

    func testSavedValuesOfAllThirteenItemsAreLoadedBack() {
        Self.changedEverywhere.save(to: defaults)
        let loaded = ConversionSettings(defaults: defaults)
        XCTAssertEqual(loaded, Self.changedEverywhere)
        XCTAssertEqual(loaded.kaCounterVariants.order, [.ke, .hiragana, .kanji, .smallKe, .ko, .katakana, .smallKa])
        XCTAssertEqual(loaded.kaCounterVariants.enabled, [.ke, .kanji, .ko])
    }

    func testSavedValuesUseTheSameKeysAndFormsAsIOS() {
        Self.changedEverywhere.save(to: defaults)
        XCTAssertEqual(defaults.object(forKey: "kanaKanjiCandidateSourceMode") as? String, "lesDeux")
        XCTAssertEqual(defaults.object(forKey: "historicalKanaCandidatesEnabled") as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: "iterationMarkCandidatesEnabled") as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: "katakanaEmphasisCandidateMode") as? String, "demote")
        XCTAssertEqual(defaults.object(forKey: "mazegakiCandidateMode") as? String, "normal")
        XCTAssertEqual(defaults.object(forKey: "scriptVariantSuppressKyujitai") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "scriptVariantSuppressPersonNameVariant") as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: "kanaGakiSuppressAdverb") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "kanaGakiSuppressAdverbKanaFirst") as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: "kakikaePreference") as? String, "afterOnly")
        XCTAssertEqual(defaults.object(forKey: "kakikaeEverydayException") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "lateStandardizedRewritePreference") as? String, "beforeOnly")
        XCTAssertEqual(defaults.object(forKey: "kaCounterVariantPreference") as? String, "ke,-hiragana,kanji,-smallKe,ko,-katakana,-smallKa")
        XCTAssertEqual(defaults.object(forKey: "okuriganaVariantPreference") as? String, "stem:permittedFirst,compound:standardOnly,noun:permittedFirst")
        XCTAssertEqual(defaults.object(forKey: "ordinalMeKanjiPreferred") as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: "formalNounMeKanaCandidatesEnabled") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "adjectiveMeKanjiCandidatesEnabled") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "numeralStylePreference") as? String, "kanjiOnly")
    }

    func testUnreadableValueFallsBackToContemporaryOnlyForThatKey() {
        Self.changedEverywhere.save(to: defaults)
        defaults.set("tout", forKey: "kanaKanjiCandidateSourceMode")
        defaults.set("oui", forKey: "historicalKanaCandidatesEnabled")
        defaults.set("rien", forKey: "kakikaePreference")
        defaults.set("x,y,z", forKey: "kaCounterVariantPreference")
        defaults.set("stem:jamais", forKey: "okuriganaVariantPreference")
        defaults.set(42, forKey: "numeralStylePreference")

        let loaded = ConversionSettings(defaults: defaults)

        var expected = Self.changedEverywhere
        expected.candidateSourceMode = .surface
        expected.historicalKanaAllowed = false
        expected.kanjiRewrite = .bothBeforeFirst
        expected.kaCounterVariants = .conservative
        expected.inflectionalKanaVariants = .contemporary
        expected.numeralStyle = .arabicFirst
        XCTAssertEqual(loaded, expected)
    }

    // MARK: - ConversionService での効き方

    // 搔(見分けにくい字形)は 5cadf1f3 でエンジンの表に入った
    func testTurningLookalikeSuppressionOffShowsOldFormAndTurningItOnHidesItAgain() {
        let service = makeService()
        XCTAssertFalse(service.candidates(reading: "かききる", precedingText: "").contains("搔き切る"))

        var settings = service.settings
        settings.suppressedScriptVariants.remove(.lookalike)
        service.updateSettings(settings)
        let offList = service.candidates(reading: "かききる", precedingText: "")
        XCTAssertTrue(offList.contains("搔き切る"), "\(offList)")

        settings.suppressedScriptVariants.insert(.lookalike)
        service.updateSettings(settings)
        let onList = service.candidates(reading: "かききる", precedingText: "")
        XCTAssertFalse(onList.contains("搔き切る"), "\(onList)")
    }

    // X.1: 巨きい は表層(surface)の辞書にだけある表記。normalisé にすると出なくなり、大きい は残る
    func testNormaliseSourceModeDropsSpellingFoundOnlyInSurfaceDictionary() {
        let service = makeService()
        XCTAssertTrue(service.candidates(reading: "おおきい", precedingText: "").contains("巨きい"))

        var settings = service.settings
        settings.candidateSourceMode = .normalise
        service.updateSettings(settings)
        let list = service.candidates(reading: "おおきい", precedingText: "")
        XCTAssertFalse(list.contains("巨きい"), "\(list)")
        XCTAssertEqual(list.first, "大きい", "\(list)")
    }

    /// 候補の列について確かめること
    private enum Expectation {
        case contains(String)
        case lacks(String)
        case first(String)
    }

    /// 1項目の効き方: 現代的初期設定での列(before)と、change を当てた後の列(after)
    private struct EngineCase {
        let item: String
        let reading: String
        let change: (inout ConversionSettings) -> Void
        let before: [Expectation]
        let after: [Expectation]
    }

    // X.1・X.6 以外の項目がエンジンまで届くこと(apply(to:) の各行)。
    // 読みと表記は、エンジンを実際に回して設定の前後で列が変わるものを選んだ
    private static let engineCases: [EngineCase] = [
        EngineCase(item: "X.2", reading: "なおさら", change: { $0.historicalKanaAllowed = true },
                   before: [.lacks("なほ更")], after: [.contains("なほ更")]),
        EngineCase(item: "X.3", reading: "ここ", change: { $0.iterationMarkAllowed = true },
                   before: [.lacks("こゝ")], after: [.contains("こゝ")]),
        EngineCase(item: "X.4", reading: "これ", change: { $0.katakanaEmphasisMode = .normal },
                   before: [.lacks("コレ")], after: [.contains("コレ")]),
        EngineCase(item: "X.5", reading: "さくひん", change: { $0.mixedScriptMode = .normal },
                   before: [.lacks("作ひん")], after: [.contains("作ひん")]),
        EngineCase(item: "X.7", reading: "いわゆる", change: { $0.suppressedKanaSpellings.remove(.adverb) },
                   before: [.lacks("所謂")], after: [.contains("所謂")]),
        EngineCase(item: "X.8", reading: "はっこう", change: { $0.kanjiRewrite = .afterOnly },
                   before: [.first("醗酵")], after: [.first("発酵"), .lacks("醗酵")]),
        EngineCase(item: "X.8 日常語の例外", reading: "りょうかい", change: { $0.kanjiRewriteEverydayException = false },
                   before: [.first("了解")], after: [.first("諒解")]),
        EngineCase(item: "X.9", reading: "おくそく", change: { $0.lateStandardizedRewrite = .afterOnly },
                   before: [.first("臆測")], after: [.first("憶測"), .lacks("臆測")]),
        EngineCase(
            item: "X.10", reading: "すうかげつ",
            change: { $0.kaCounterVariants = KaCounterVariantPreference.decode("katakana,-hiragana,-kanji,-smallKe,-smallKa,-ko,-ke") },
            before: [.first("数か月")], after: [.first("数カ月"), .lacks("数か月")]
        ),
        EngineCase(item: "X.11", reading: "おわる", change: { $0.inflectionalKanaVariants.modes[.stemInternal] = .permittedFirst },
                   before: [.first("終わる"), .lacks("終る")], after: [.first("終る")]),
        EngineCase(item: "X.12 序数化", reading: "さんばんめ", change: { $0.ordinalMeKanjiPreferred = true },
                   before: [.first("三番め")], after: [.first("三番目")]),
        EngineCase(item: "X.12 形式名詞化", reading: "ひどいめにあう", change: { $0.formalNounMeKanaEnabled = false },
                   before: [.contains("ひどいめに遭う")], after: [.lacks("ひどいめに遭う"), .contains("ひどい目に遭う")]),
        EngineCase(item: "X.12 形状名詞化", reading: "すくなめ", change: { $0.adjectiveMeKanjiEnabled = false },
                   before: [.contains("少な目")], after: [.lacks("少な目"), .first("少なめ")]),
        EngineCase(item: "X.13", reading: "にまい", change: { $0.numeralStyle = .kanjiOnly },
                   before: [.first("2枚")], after: [.first("二枚"), .lacks("2枚")]),
    ]

    private func check(_ expectations: [Expectation], in list: [String], _ label: String) {
        for expectation in expectations {
            switch expectation {
            case .contains(let surface):
                XCTAssertTrue(list.contains(surface), "\(label): \(surface) が無い \(list)")
            case .lacks(let surface):
                XCTAssertFalse(list.contains(surface), "\(label): \(surface) がある \(list)")
            case .first(let surface):
                XCTAssertEqual(list.first, surface, "\(label): \(list)")
            }
        }
    }

    func testEachConversionSettingReachesTheEngine() {
        let service = makeService()
        for engineCase in Self.engineCases {
            service.updateSettings(.contemporary)
            check(engineCase.before, in: service.candidates(reading: engineCase.reading, precedingText: ""),
                  "\(engineCase.item) 変更前")

            var settings = ConversionSettings.contemporary
            engineCase.change(&settings)
            service.updateSettings(settings)
            check(engineCase.after, in: service.candidates(reading: engineCase.reading, precedingText: ""),
                  "\(engineCase.item) 変更後")
        }
    }

    func testNewServiceOnSameSuiteStartsWithSavedSettings() {
        let service = makeService()
        service.updateSettings(Self.changedEverywhere)
        XCTAssertEqual(makeService().settings, Self.changedEverywhere)
    }

    // 保存してある値が、作った時点でエンジンに入っていること(読むだけでなく)
    func testSettingsStoredBeforeCreationAreAppliedToTheEngine() {
        var settings = ConversionSettings.contemporary
        settings.suppressedScriptVariants.remove(.lookalike)
        settings.save(to: defaults)

        let list = makeService().candidates(reading: "かききる", precedingText: "")
        XCTAssertTrue(list.contains("搔き切る"), "\(list)")
    }
}
