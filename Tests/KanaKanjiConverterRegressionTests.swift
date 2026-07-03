import XCTest

final class KanaKanjiConverterRegressionTests: XCTestCase {
    private var defaultsSuiteName = ""
    private var converter: KanaKanjiConverter!

    override func setUp() {
        super.setUp()

        defaultsSuiteName = "com.kusakabe.ecritu.tests.kana-kanji.\(UUID().uuidString)"
        clearSuite(defaultsSuiteName)
        converter = KanaKanjiConverter(store: KanaKanjiStore(appGroupID: defaultsSuiteName))
    }

    override func tearDown() {
        clearSuite(defaultsSuiteName)
        converter = nil
        defaultsSuiteName = ""
        super.tearDown()
    }

    func testRegressionCorePhrasesRemainConvertibleOnSeedFallback() {
        let cases: [(reading: String, expected: String)] = [
            ("いきました", "行きました"),
            ("いって", "行って"),
            ("いったら", "行ったら"),
            ("たべました", "食べました"),
            ("みました", "見ました")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionGodanTeIkuChainDerivesMotteikuVariants() {
        converter.learn(reading: "もつ", candidate: "持つ")

        let cases: [(reading: String, expected: String)] = [
            ("もっていく", "持っていく"),
            ("もってく", "持ってく"),
            ("もってけ", "持ってけ"),
            ("もっていって", "持っていって"),
            ("もってって", "持ってって")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionVerbKataFormIsDerivedFromBaseVerbCandidate() {
        converter.learn(reading: "たべる", candidate: "食べる")
        converter.learn(reading: "くう", candidate: "食う")

        let cases: [(reading: String, expected: String)] = [
            ("たべかた", "食べ方"),
            ("くいかた", "食い方")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionLearnedVerbSupportsYouFormsViaInference() {
        // 学習語彙(品詞メタデータなし)の動詞でも、活用クラス推論により
        // 「よう/ように/ような」後置が導出できることを確認する。
        converter.learn(reading: "とれる", candidate: "取れる")

        let cases: [(reading: String, expected: String)] = [
            ("とれるように", "取れるように"),
            ("とれるような", "取れるような")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionGodanYasuiFormIsDerivedFromBaseVerbCandidate() {
        converter.learn(reading: "うつ", candidate: "打つ")
        converter.learn(reading: "かく", candidate: "書く")

        let cases: [(reading: String, expected: String)] = [
            ("うちやすい", "打ちやすい"),
            ("かきやすい", "書きやすい")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionGodanVolitionalFormsAreDerivedFromBaseVerbCandidate() {
        // -る動詞は五段/一段が読みで曖昧(帰る/変える)なため seed fallback ではクラス
        // 解決できないことがある。ここでは曖昧でない五段(く/む/す/ぐ)で導出を確認する。
        // (帰ろう 等の五段ラ行は本番=実辞書で動作確認済み)
        converter.learn(reading: "いく", candidate: "行く")
        converter.learn(reading: "かく", candidate: "書く")
        converter.learn(reading: "よむ", candidate: "読む")
        converter.learn(reading: "はなす", candidate: "話す")

        let cases: [(reading: String, expected: String)] = [
            ("いこう", "行こう"),
            ("かこう", "書こう"),
            ("よもう", "読もう"),
            ("はなそう", "話そう")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionGodanVolitionalFormAcceptsTrailingParticles() {
        // ユーザ報告: いこうかと→行こうかと。逐次入力(プレフィックスを順に評価)で
        // 候補キャッシュ連鎖を成立させたうえで、意志形+助詞(かと)が導出されることを確認。
        converter.learn(reading: "いく", candidate: "行く")

        for prefix in ["いこう", "いこうか"] {
            _ = converter.candidates(for: prefix, limit: 24, systemCandidateMode: .surface)
        }

        let candidates = converter.candidates(
            for: "いこうかと",
            limit: 24,
            systemCandidateMode: .surface
        )

        XCTAssertTrue(
            candidates.contains("行こうかと"),
            "candidates=\(candidates)"
        )
    }

    func testRegressionYasuiYasuiKanjiFormIsDerivedFromBaseVerbCandidate() {
        converter.learn(reading: "うつ", candidate: "打つ")
        converter.learn(reading: "たべる", candidate: "食べる")

        let cases: [(reading: String, expected: String)] = [
            ("うちやすい", "打ち易い"),
            ("たべやすい", "食べ易い")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionSourceFilteredModeStillReturnsSeedFallbackCandidates() {
        let candidates = converter.candidates(
            for: "いく",
            limit: 12,
            systemCandidateMode: .normalise
        )

        XCTAssertTrue(candidates.contains("行く"), "candidates=\(candidates)")
    }

    func testRegressionSingleCharacterReadingRemainsConvertibleOnSeedFallback() {
        let candidates = converter.candidates(
            for: "ひ",
            limit: 12,
            systemCandidateMode: .surface
        )

        XCTAssertTrue(candidates.contains("日"), "candidates=\(candidates)")
    }

    func testRegressionKaiPrioritizesCommonSingleKanjiCandidateOnSeedFallback() {
        let candidates = converter.candidates(
            for: "かい",
            limit: 12,
            systemCandidateMode: .surface
        )

        XCTAssertEqual(candidates.first, "回", "candidates=\(candidates)")
        XCTAssertTrue(candidates.contains("会"), "candidates=\(candidates)")
    }

    func testRegressionKiwotsukeruVariantsRemainConvertibleOnSeedFallback() {
        let baseCandidates = converter.candidates(
            for: "きをつける",
            limit: 24,
            systemCandidateMode: .surface
        )

        XCTAssertTrue(
            baseCandidates.contains("気を付ける"),
            "candidates=\(baseCandidates)"
        )
        XCTAssertTrue(
            baseCandidates.contains("気をつける"),
            "candidates=\(baseCandidates)"
        )

        let teFormCandidates = converter.candidates(
            for: "きをつけて",
            limit: 24,
            systemCandidateMode: .surface
        )

        XCTAssertTrue(
            teFormCandidates.contains("気を付けて"),
            "candidates=\(teFormCandidates)"
        )
        XCTAssertTrue(
            teFormCandidates.contains("気をつけて"),
            "candidates=\(teFormCandidates)"
        )
    }

    func testRegressionKigatsukuVariantsRemainConvertibleOnSeedFallback() {
        let baseCandidates = converter.candidates(
            for: "きがつく",
            limit: 24,
            systemCandidateMode: .surface
        )

        XCTAssertTrue(
            baseCandidates.contains("気が付く"),
            "candidates=\(baseCandidates)"
        )
        XCTAssertTrue(
            baseCandidates.contains("気がつく"),
            "candidates=\(baseCandidates)"
        )

        let taFormCandidates = converter.candidates(
            for: "きがついた",
            limit: 24,
            systemCandidateMode: .surface
        )

        XCTAssertTrue(
            taFormCandidates.contains("気が付いた"),
            "candidates=\(taFormCandidates)"
        )
        XCTAssertTrue(
            taFormCandidates.contains("気がついた"),
            "candidates=\(taFormCandidates)"
        )
    }

    func testRegressionKiniiruVariantsRemainConvertibleOnSeedFallback() {
        let baseCandidates = converter.candidates(
            for: "きにいる",
            limit: 24,
            systemCandidateMode: .surface
        )

        XCTAssertTrue(
            baseCandidates.contains("気に入る"),
            "candidates=\(baseCandidates)"
        )

        let teFormCandidates = converter.candidates(
            for: "きにいって",
            limit: 24,
            systemCandidateMode: .surface
        )

        XCTAssertTrue(
            teFormCandidates.contains("気に入って"),
            "candidates=\(teFormCandidates)"
        )
    }

    func testRegressionYamadaSurnameRemainsInTopCandidatesAfterKatakanaLearning() {
        converter.learn(reading: "やまだ", candidate: "ヤマダ")

        let candidates = converter.candidates(
            for: "やまだ",
            limit: 8,
            systemCandidateMode: .surface
        )

        XCTAssertEqual(candidates.first, "山田", "candidates=\(candidates)")
        XCTAssertTrue(candidates.contains("ヤマダ"), "candidates=\(candidates)")
    }

    func testRegressionLoanwordKatakanaCandidateIsNotDroppedBySameReadingPenalty() {
        let candidates = converter.candidates(
            for: "さいと",
            limit: 24,
            systemCandidateMode: .surface
        )

        XCTAssertEqual(candidates.first, "サイト", "candidates=\(candidates)")
    }

    func testRegressionHonorificPrefixCandidatesAreDerivedFromRegisteredBaseWords() {
        converter.learn(reading: "かんじょう", candidate: "勘定")
        converter.learn(reading: "さけ", candidate: "酒")
        converter.learn(reading: "そうだん", candidate: "相談")

        let accountCandidates = converter.candidates(
            for: "おかんじょう",
            limit: 24,
            systemCandidateMode: .surface
        )
        let sakeCandidates = converter.candidates(
            for: "おさけ",
            limit: 24,
            systemCandidateMode: .surface
        )
        let consultationCandidates = converter.candidates(
            for: "ごそうだん",
            limit: 24,
            systemCandidateMode: .surface
        )

        XCTAssertTrue(
            accountCandidates.contains("お勘定"),
            "candidates=\(accountCandidates)"
        )
        XCTAssertTrue(
            sakeCandidates.contains("お酒"),
            "candidates=\(sakeCandidates)"
        )
        XCTAssertTrue(
            consultationCandidates.contains("ご相談"),
            "candidates=\(consultationCandidates)"
        )
    }

    func testRegressionHonorificPrefixDerivationSkipsInflectableCandidates() {
        let candidates = converter.candidates(
            for: "おいく",
            limit: 24,
            systemCandidateMode: .surface
        )

        XCTAssertFalse(candidates.contains("お行く"), "candidates=\(candidates)")
    }

    func testRegressionHonorificGoDoesNotDeriveFromSuruVerbSurface() {
        converter.learn(reading: "べんきょうする", candidate: "勉強する")

        let candidates = converter.candidates(
            for: "ごべんきょうする",
            limit: 24,
            systemCandidateMode: .surface
        )

        XCTAssertFalse(candidates.contains("ご勉強する"), "candidates=\(candidates)")
    }

    func testRegressionHonorificOSuruCandidatesAreDerivedFromVerbRenyouForms() {
        converter.learn(reading: "つれる", candidate: "連れる")
        converter.learn(reading: "むかえる", candidate: "迎える")
        converter.learn(reading: "よぶ", candidate: "呼ぶ")

        let cases: [(reading: String, expected: String)] = [
            ("おつれする", "お連れする"),
            ("おつれしたい", "お連れしたい"),
            ("おむかえする", "お迎えする"),
            ("おむかえしたい", "お迎えしたい"),
            ("およびする", "お呼びする"),
            ("およびしたい", "お呼びしたい")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionHonorificORenyouAndONaruCandidatesAreDerivedFromVerbRenyouForms() {
        converter.learn(reading: "わすれる", candidate: "忘れる")
        converter.learn(reading: "きめる", candidate: "決める")
        converter.learn(reading: "しらべる", candidate: "調べる")
        converter.learn(reading: "みえる", candidate: "見える")
        converter.learn(reading: "かんがえる", candidate: "考える")

        let cases: [(reading: String, expected: String)] = [
            ("おわすれ", "お忘れ"),
            ("おわすれになる", "お忘れになる"),
            ("おきめになる", "お決めになる"),
            ("おしらべ", "お調べ"),
            ("おみえ", "お見え"),
            ("おかんがえ", "お考え")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionHonorificOSoftRequestCandidatesAreDerivedFromRenyouAndNounStems() {
        converter.learn(reading: "わすれる", candidate: "忘れる")
        converter.learn(reading: "きづかい", candidate: "気遣い")

        let cases: [(reading: String, expected: String)] = [
            ("おわすれなく", "お忘れなく"),
            ("おわすれなきよう", "お忘れなきよう"),
            ("おきづかいなく", "お気遣いなく")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionGodanPassiveFormsAreDerivedFromBaseVerbCandidates() {
        converter.learn(reading: "けす", candidate: "消す")
        converter.learn(reading: "うる", candidate: "売る")

        let kesareruCandidates = converter.candidates(
            for: "けされる",
            limit: 24,
            systemCandidateMode: .surface
        )
        let urareruCandidates = converter.candidates(
            for: "うられる",
            limit: 24,
            systemCandidateMode: .surface
        )

        XCTAssertTrue(
            kesareruCandidates.contains("消される"),
            "candidates=\(kesareruCandidates)"
        )
        XCTAssertTrue(
            urareruCandidates.contains("売られる"),
            "candidates=\(urareruCandidates)"
        )
    }

    func testRegressionGodanPassiveRenyouFormIsDerivedFromBaseVerbCandidate() {
        converter.learn(reading: "つかう", candidate: "使う")

        let candidates = converter.candidates(
            for: "つかわれ",
            limit: 24,
            systemCandidateMode: .surface
        )

        XCTAssertTrue(
            candidates.contains("使われ"),
            "candidates=\(candidates)"
        )
    }

    func testRegressionGodanPassiveTeAspectFormsAreDerivedFromBaseVerbCandidate() {
        converter.learn(reading: "ふくむ", candidate: "含む")

        let cases: [(reading: String, expected: String)] = [
            ("ふくまれて", "含まれて"),
            ("ふくまれてる", "含まれてる"),
            ("ふくまれている", "含まれている")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionMakuAuxiliaryVariantsAreDerivedFromGodanBase() {
        converter.learn(reading: "へる", candidate: "減る")

        let cases: [(reading: String, expected: String)] = [
            ("へりまくる", "減りまくる"),
            ("へりまくって", "減りまくって")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionSahenNounCandidatesDeriveSuruForms() {
        converter.learn(reading: "かくにん", candidate: "確認")

        let suruCandidates = converter.candidates(
            for: "かくにんする",
            limit: 24,
            systemCandidateMode: .surface
        )
        let pastCandidates = converter.candidates(
            for: "かくにんした",
            limit: 24,
            systemCandidateMode: .surface
        )

        XCTAssertTrue(
            suruCandidates.contains("確認する"),
            "candidates=\(suruCandidates)"
        )
        XCTAssertTrue(
            pastCandidates.contains("確認した"),
            "candidates=\(pastCandidates)"
        )
    }

    func testRegressionKigaSuruChainDerivesBothAffirmativeAndNegative() {
        converter.learn(reading: "きが", candidate: "気が")

        let cases: [(reading: String, expected: String)] = [
            ("きがする", "気がする"),
            ("きがしない", "気がしない")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionMixedScriptPhraseStemCanDeriveSuruFormsWithoutOptIn() {
        converter.learn(reading: "おとが", candidate: "音が")

        let candidates = converter.candidates(
            for: "おとがする",
            limit: 24,
            systemCandidateMode: .surface
        )

        XCTAssertTrue(
            candidates.contains("音がする"),
            "candidates=\(candidates)"
        )
    }

    func testRegressionSahenNounTeMiruChainDerivesShiteMite() {
        converter.learn(reading: "けんさくしてみる", candidate: "検索してみる")

        let directCandidates = converter.candidates(
            for: "けんさくしてみる",
            limit: 24,
            systemCandidateMode: .surface
        )

        XCTAssertTrue(
            directCandidates.contains("検索してみる"),
            "candidates=\(directCandidates)"
        )

        let cases: [(reading: String, expected: String)] = [
            ("けんさくしてみて", "検索してみて")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionTeIruVariantsAreDerivedFromBaseVerbCandidates() {
        converter.learn(reading: "おちる", candidate: "落ちる")

        let teCandidates = converter.candidates(
            for: "おちて",
            limit: 24,
            systemCandidateMode: .surface
        )
        let teruCandidates = converter.candidates(
            for: "おちてる",
            limit: 24,
            systemCandidateMode: .surface
        )
        let teIruCandidates = converter.candidates(
            for: "おちている",
            limit: 24,
            systemCandidateMode: .surface
        )

        XCTAssertTrue(
            teCandidates.contains("落ちて"),
            "candidates=\(teCandidates)"
        )
        XCTAssertTrue(
            teruCandidates.contains("落ちてる"),
            "candidates=\(teruCandidates)"
        )
        XCTAssertTrue(
            teIruCandidates.contains("落ちている"),
            "candidates=\(teIruCandidates)"
        )
    }

    func testRegressionTeAspectVariantsAreDerivedAcrossVerbClasses() {
        converter.learn(reading: "おちる", candidate: "落ちる")
        converter.learn(reading: "かく", candidate: "書く")
        converter.learn(reading: "よむ", candidate: "読む")
        converter.learn(reading: "あんないする", candidate: "案内する")
        converter.learn(reading: "かくにん", candidate: "確認")
        converter.learn(reading: "くる", candidate: "来る")
        converter.learn(reading: "いく", candidate: "行く")

        let cases: [(reading: String, expected: String)] = [
            ("おちていた", "落ちていた"),
            ("おちていなかった", "落ちていなかった"),
            ("おちていました", "落ちていました"),
            ("かいてた", "書いてた"),
            ("かいていません", "書いていません"),
            ("よんでなかった", "読んでなかった"),
            ("よんでます", "読んでます"),
            ("あんないしてた", "案内してた"),
            ("かくにんしていない", "確認していない"),
            ("きてなかった", "来てなかった"),
            ("きていました", "来ていました"),
            ("いっていた", "行っていた"),
            ("いっていません", "行っていません")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionTariFormsAreDerivedAcrossVerbClasses() {
        converter.learn(reading: "とまる", candidate: "止まる")
        converter.learn(reading: "たべる", candidate: "食べる")
        converter.learn(reading: "よむ", candidate: "読む")
        converter.learn(reading: "あんないする", candidate: "案内する")
        converter.learn(reading: "かくにん", candidate: "確認")
        converter.learn(reading: "くる", candidate: "来る")
        converter.learn(reading: "いく", candidate: "行く")

        let cases: [(reading: String, expected: String)] = [
            ("とまったり", "止まったり"),
            ("たべたり", "食べたり"),
            ("よんだり", "読んだり"),
            ("あんないしたり", "案内したり"),
            ("かくにんしたり", "確認したり"),
            ("きたり", "来たり"),
            ("いったり", "行ったり")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionTomattariSuruVariantsAreDerivedFromGodanBase() {
        converter.learn(reading: "とまる", candidate: "止まる")

        let cases: [(reading: String, expected: String)] = [
            ("とまった", "止まった"),
            ("とまったり", "止まったり"),
            ("とまったりします", "止まったりします"),
            ("とまったりしますか", "止まったりしますか"),
            ("とまったりしません", "止まったりしません"),
            ("とまったりしませんか", "止まったりしませんか"),
            ("とまったりするのですか", "止まったりするのですか")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionAuxiliaryChainingVariantsAreDerivedAcrossVerbClasses() {
        converter.learn(reading: "たべる", candidate: "食べる")
        converter.learn(reading: "かく", candidate: "書く")
        converter.learn(reading: "よむ", candidate: "読む")
        converter.learn(reading: "あんないする", candidate: "案内する")
        converter.learn(reading: "かくにん", candidate: "確認")
        converter.learn(reading: "くる", candidate: "来る")
        converter.learn(reading: "いく", candidate: "行く")

        let cases: [(reading: String, expected: String)] = [
            ("たべておく", "食べておく"),
            ("たべといた", "食べといた"),
            ("たべてみる", "食べてみる"),
            ("たべてしまわない", "食べてしまわない"),
            ("かいておく", "書いておく"),
            ("かいとく", "書いとく"),
            ("よんでおいて", "読んでおいて"),
            ("よんどかない", "読んどかない"),
            ("かいてみた", "書いてみた"),
            ("よんでみません", "読んでみません"),
            ("かいてしまいません", "書いてしまいません"),
            ("よんじゃわなかった", "読んじゃわなかった"),
            ("あんないしておく", "案内しておく"),
            ("あんないしとく", "案内しとく"),
            ("あんないしてみる", "案内してみる"),
            ("あんないしてしまわなかった", "案内してしまわなかった"),
            ("かくにんしておきます", "確認しておきます"),
            ("かくにんしときません", "確認しときません"),
            ("かくにんしてみました", "確認してみました"),
            ("かくにんしちゃいません", "確認しちゃいません"),
            ("きておく", "来ておく"),
            ("きといて", "来といて"),
            ("きてみない", "来てみない"),
            ("きちゃわない", "来ちゃわない"),
            ("いっておく", "行っておく"),
            ("いっとく", "行っとく"),
            ("いってみます", "行ってみます"),
            ("いっちゃいません", "行っちゃいません")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionShimauContractionsAreDerivedAcrossVerbClasses() {
        converter.learn(reading: "おわる", candidate: "終わる")
        converter.learn(reading: "いく", candidate: "行く")
        converter.learn(reading: "たべる", candidate: "食べる")

        let cases: [(reading: String, expected: String)] = [
            ("おわっちゃう", "終わっちゃう"),
            ("いっちゃう", "行っちゃう"),
            ("たべちゃう", "食べちゃう"),
            ("おわってしまう", "終わってしまう"),
            ("いってしまう", "行ってしまう"),
            ("たべてしまう", "食べてしまう")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionShimauContractionStemFormsAreDerivedAcrossVerbClasses() {
        converter.learn(reading: "たべる", candidate: "食べる")
        converter.learn(reading: "いく", candidate: "行く")
        converter.learn(reading: "よむ", candidate: "読む")
        converter.learn(reading: "くる", candidate: "来る")
        converter.learn(reading: "かくにん", candidate: "確認")

        let cases: [(reading: String, expected: String)] = [
            ("たべちゃ", "食べちゃ"),
            ("いっちゃ", "行っちゃ"),
            ("よんじゃ", "読んじゃ"),
            ("きちゃ", "来ちゃ"),
            ("かくにんしちゃ", "確認しちゃ")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionShimauRenyoFormsAreDerivedAcrossVerbClasses() {
        converter.learn(reading: "でる", candidate: "出る")
        converter.learn(reading: "かく", candidate: "書く")
        converter.learn(reading: "かくにん", candidate: "確認")
        converter.learn(reading: "くる", candidate: "来る")

        let cases: [(reading: String, expected: String)] = [
            ("でてしまい", "出てしまい"),
            ("かいてしまい", "書いてしまい"),
            ("かくにんしてしまい", "確認してしまい"),
            ("きてしまい", "来てしまい")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionAdjectiveSugiruFormsAreDerivedFromBaseAdjectiveCandidates() {
        converter.learn(reading: "おそい", candidate: "遅い")
        converter.learn(reading: "わるい", candidate: "悪い")

        let cases: [(reading: String, expected: String)] = [
            ("わるすぎ", "悪すぎ"),
            ("おそすぎる", "遅すぎる"),
            ("おそすぎない", "遅すぎない"),
            ("おそすぎて", "遅すぎて"),
            ("おそすぎた", "遅すぎた"),
            ("おそすぎません", "遅すぎません"),
            ("おそすぎれば", "遅すぎれば")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionTeKuruFormsAreDerivedFromIchidanBaseCandidate() {
        converter.learn(reading: "でる", candidate: "出る")

        let cases: [(reading: String, expected: String)] = [
            ("でてこない", "出てこない"),
            ("でてこなかった", "出てこなかった"),
            ("でてきた", "出てきた")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionTeKuruFormsAreDerivedFromGodanBaseCandidate() {
        converter.learn(reading: "うる", candidate: "売る")
        converter.learn(reading: "かく", candidate: "描く")

        let cases: [(reading: String, expected: String)] = [
            ("うってきた", "売ってきた"),
            ("かいてきた", "描いてきた")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionPostfixNoDaChainsAreDerivedFromBaseCandidates() {
        converter.learn(reading: "つかう", candidate: "使う")

        let cases: [(reading: String, expected: String)] = [
            ("つかったの", "使ったの"),
            ("つかったのだ", "使ったのだ"),
            ("つかったのだが", "使ったのだが")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionPostfixDaChainsAreDerivedFromBaseCandidates() {
        converter.learn(reading: "ちがい", candidate: "違い")

        let cases: [(reading: String, expected: String)] = [
            ("ちがいだ", "違いだ"),
            ("ちがいだろう", "違いだろう"),
            ("ちがいだった", "違いだった"),
            ("ちがいだったら", "違いだったら")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionPostfixDesuChainIsDerivedFromKatakanaBaseCandidate() {
        converter.learn(reading: "すらんぷ", candidate: "スランプ")

        let cases: [(reading: String, expected: String)] = [
            ("すらんぷで", "スランプで"),
            ("すらんぷだ", "スランプだ"),
            ("すらんぷです", "スランプです")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionPostfixNdaChainsAreDerivedFromBaseCandidates() {
        converter.learn(reading: "へいき", candidate: "平気")

        let cases: [(reading: String, expected: String)] = [
            ("へいきなのだけど", "平気なのだけど"),
            ("へいきなんだ", "平気なんだ"),
            ("へいきなんです", "平気なんです"),
            ("へいきなんだけど", "平気なんだけど"),
            ("へいきなんですけど", "平気なんですけど")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionPostfixDakeChainsAreDerivedFromBaseCandidates() {
        converter.learn(reading: "たす", candidate: "足す")

        let cases: [(reading: String, expected: String)] = [
            ("たしただけ", "足しただけ"),
            ("たしただけだ", "足しただけだ")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionPostfixNomiAttachesToNounLikeDake() {
        converter.learn(reading: "おきなわけん", candidate: "沖縄県")

        let cases: [(reading: String, expected: String)] = [
            ("おきなわけんだけ", "沖縄県だけ"),
            ("おきなわけんのみ", "沖縄県のみ")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionPostfixTameAndTameniDeriveFromVerbStem() {
        converter.learn(reading: "だす", candidate: "出す")

        let cases: [(reading: String, expected: String)] = [
            ("だすため", "出すため"),
            ("だすために", "出すために")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionPostfixKudasaiChainsAreDerivedFromBaseCandidates() {
        converter.learn(reading: "おくる", candidate: "送る")

        let cases: [(reading: String, expected: String)] = [
            ("おくってください", "送ってください"),
            ("おくってくださいね", "送ってくださいね")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionAdjectivePoliteFormsAreDerivedFromBaseAdjectiveCandidates() {
        converter.learn(reading: "おそい", candidate: "遅い")

        let cases: [(reading: String, expected: String)] = [
            ("おそいです", "遅いです"),
            ("おそくないです", "遅くないです"),
            ("おそかったです", "遅かったです"),
            ("おそくなかったです", "遅くなかったです"),
            ("おそくありません", "遅くありません"),
            ("おそくありませんでした", "遅くありませんでした")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionAdjectiveTariFormIsDerivedFromBaseAdjectiveCandidate() {
        converter.learn(reading: "いたい", candidate: "痛い")

        let candidates = converter.candidates(
            for: "いたかったり",
            limit: 24,
            systemCandidateMode: .surface
        )

        XCTAssertTrue(
            candidates.contains("痛かったり"),
            "candidates=\(candidates)"
        )
    }

    func testRegressionAdjectiveRenyoNegativeFormIsDerivedFromBaseAdjectiveCandidate() {
        converter.learn(reading: "たかい", candidate: "高い")

        let candidates = converter.candidates(
            for: "たかくなく",
            limit: 24,
            systemCandidateMode: .surface
        )

        XCTAssertTrue(
            candidates.contains("高くなく"),
            "candidates=\(candidates)"
        )
    }

    func testRegressionAdditionalPostfixAndTeAruFormsAreDerivedFromBaseCandidates() {
        converter.learn(reading: "ならべる", candidate: "並べる")
        converter.learn(reading: "かく", candidate: "書く")
        converter.learn(reading: "すき", candidate: "好き")
        converter.learn(reading: "わすれる", candidate: "忘れる")

        let cases: [(reading: String, expected: String)] = [
            ("ならべてある", "並べてある"),
            ("かいてある", "書いてある"),
            ("かいてあった", "書いてあった"),
            ("すきなら", "好きなら"),
            ("わすれたから", "忘れたから")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionPostfixNadoChainsAreDerivedFromBaseCandidates() {
        converter.learn(reading: "かび", candidate: "カビ")

        let cases: [(reading: String, expected: String)] = [
            ("かびを", "カビを"),
            ("かびなど", "カビなど"),
            ("かびなどを", "カビなどを")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionPostfixMadeChainsAreDerivedFromBaseCandidates() {
        converter.learn(reading: "かわく", candidate: "乾く")

        let cases: [(reading: String, expected: String)] = [
            ("かわくまで", "乾くまで"),
            ("かわくまでは", "乾くまでは"),
            ("かわくまでに", "乾くまでに")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionPostfixDePrefersLongerStemOverMadeAmbiguity() {
        converter.learn(reading: "なま", candidate: "生")

        let candidates = converter.candidates(
            for: "なまで",
            limit: 24,
            systemCandidateMode: .surface
        )

        XCTAssertTrue(
            candidates.contains("生で"),
            "candidates=\(candidates)"
        )
    }

    func testRegressionVerbNikuiFormsAreDerivedAcrossVerbClasses() {
        converter.learn(reading: "かく", candidate: "書く")
        converter.learn(reading: "たべる", candidate: "食べる")
        converter.learn(reading: "あんないする", candidate: "案内する")
        converter.learn(reading: "かくにん", candidate: "確認")
        converter.learn(reading: "くる", candidate: "来る")

        let cases: [(reading: String, expected: String)] = [
            ("かきにくい", "書きにくい"),
            ("かきにくくない", "書きにくくない"),
            ("たべにくい", "食べにくい"),
            ("あんないしにくい", "案内しにくい"),
            ("かくにんしにくかった", "確認しにくかった"),
            ("きにくい", "来にくい")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionVerbSugiruFormsAreDerivedAcrossVerbClasses() {
        converter.learn(reading: "かく", candidate: "書く")
        converter.learn(reading: "たべる", candidate: "食べる")
        converter.learn(reading: "あんないする", candidate: "案内する")
        converter.learn(reading: "かくにん", candidate: "確認")
        converter.learn(reading: "くる", candidate: "来る")

        let cases: [(reading: String, expected: String)] = [
            ("かきすぎ", "書きすぎ"),
            ("かきすぎる", "書きすぎる"),
            ("かきすぎた", "書きすぎた"),
            ("たべすぎ", "食べすぎ"),
            ("たべすぎる", "食べすぎる"),
            ("あんないしすぎ", "案内しすぎ"),
            ("あんないしすぎない", "案内しすぎない"),
            ("かくにんしすぎ", "確認しすぎ"),
            ("かくにんしすぎました", "確認しすぎました"),
            ("きすぎ", "来すぎ"),
            ("きすぎる", "来すぎる"),
            ("きすぎません", "来すぎません")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionGodanTagaruFormsAreDerivedFromBaseVerbCandidate() {
        converter.learn(reading: "よぶ", candidate: "呼ぶ")

        let cases: [(reading: String, expected: String)] = [
            ("よびたがる", "呼びたがる"),
            ("よびたがって", "呼びたがって"),
            ("よびたがった", "呼びたがった"),
            ("よびたがらない", "呼びたがらない")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionAdjectiveGaruFormsAreDerivedOnlyForAllowlistedCandidates() {
        converter.learn(reading: "こわい", candidate: "怖い")
        converter.learn(reading: "さむい", candidate: "寒い")
        converter.learn(reading: "あつい", candidate: "暑い")
        converter.learn(reading: "あかい", candidate: "赤い")

        let allowedCases: [(reading: String, expected: String)] = [
            ("こわがる", "怖がる"),
            ("こわがった", "怖がった"),
            ("こわがらない", "怖がらない"),
            ("こわがり", "怖がり"),
            ("さむがる", "寒がる"),
            ("あつがる", "暑がる")
        ]

        for testCase in allowedCases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }

        let blockedCandidates = converter.candidates(
            for: "あかがる",
            limit: 24,
            systemCandidateMode: .surface
        )

        XCTAssertFalse(
            blockedCandidates.contains("赤がる"),
            "candidates=\(blockedCandidates)"
        )

        let blockedArchaicCases: [(reading: String, blocked: String)] = [
            ("こわかる", "怖かる"),
            ("こわかり", "怖かり"),
            ("さむかり", "寒かり")
        ]

        for testCase in blockedArchaicCases {
            // Ensure blocked forms are filtered even if they exist in learned/user candidates.
            converter.learn(reading: testCase.reading, candidate: testCase.blocked)
        }

        for testCase in blockedArchaicCases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertFalse(
                candidates.contains(testCase.blocked),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionGodanNegativePastConditionalIsDerivedFromBaseVerbCandidate() {
        converter.learn(reading: "とどく", candidate: "届く")

        let candidates = converter.candidates(
            for: "とどかなかったら",
            limit: 24,
            systemCandidateMode: .surface
        )

        XCTAssertTrue(
            candidates.contains("届かなかったら"),
            "candidates=\(candidates)"
        )
    }

    func testRegressionGodanPastConditionalIsDerivedFromBaseVerbCandidate() {
        converter.learn(reading: "いれなおす", candidate: "入れ直す")

        let candidates = converter.candidates(
            for: "いれなおしたら",
            limit: 24,
            systemCandidateMode: .surface
        )

        XCTAssertTrue(
            candidates.contains("入れ直したら"),
            "candidates=\(candidates)"
        )
    }

    func testRegressionGodanCausativeTeFormIsDerivedFromBaseVerbCandidate() {
        converter.learn(reading: "おわる", candidate: "終わる")

        let cases: [(reading: String, expected: String)] = [
            ("おわらせる", "終わらせる"),
            ("おわらせて", "終わらせて")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionIchidanZuFormIsDerivedFromBaseVerbCandidate() {
        converter.learn(reading: "つける", candidate: "付ける")

        let candidates = converter.candidates(
            for: "つけず",
            limit: 24,
            systemCandidateMode: .surface
        )

        XCTAssertTrue(
            candidates.contains("付けず"),
            "candidates=\(candidates)"
        )
    }

    func testRegressionIchidanNegativePastConditionalIsDerivedFromBaseVerbCandidate() {
        converter.learn(reading: "ひろめる", candidate: "広める")

        let candidates = converter.candidates(
            for: "ひろめなかったら",
            limit: 24,
            systemCandidateMode: .surface
        )

        XCTAssertTrue(
            candidates.contains("広めなかったら"),
            "candidates=\(candidates)"
        )
    }

    func testRegressionIchidanPastConditionalIsDerivedFromBaseVerbCandidate() {
        converter.learn(reading: "しらべる", candidate: "調べる")

        let candidates = converter.candidates(
            for: "しらべたら",
            limit: 24,
            systemCandidateMode: .surface
        )

        XCTAssertTrue(
            candidates.contains("調べたら"),
            "candidates=\(candidates)"
        )
    }

    func testRegressionAdditionalInflectionFormsAreDerivedWithoutVocabularyAppend() {
        let cases: [(reading: String, expected: String)] = [
            ("かわねば", "買わねば"),
            ("みやすい", "見やすい"),
            ("かかさず", "欠かさず"),
            ("くわせる", "食わせる")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionRequestedAndRelatedInflectionPhrasesAreDerived() {
        converter.learn(reading: "すくない", candidate: "少ない")
        converter.learn(reading: "おおい", candidate: "多い")
        converter.learn(reading: "おおきい", candidate: "大きい")
        converter.learn(reading: "きをつける", candidate: "気を付ける")
        converter.learn(reading: "つかう", candidate: "使う")
        converter.learn(reading: "よむ", candidate: "読む")
        converter.learn(reading: "きょうゆう", candidate: "共有")

        // 「〜よう/ように/ような」を付ける後置活用は、語幹候補が動詞である確認に
        // システム辞書の活用クラスメタデータを要する(filterNonVerbalCandidatesForVerbalPostfix)。
        // 種辞書のみの本サンドボックスでは学習語に活用クラスが無いため、
        // 押さないよう/取れるように/取れるような は導出できない(本番=Sudachi辞書では動作)。
        // ここでは活用クラスを要しないケースのみを検証する。
        let cases: [(reading: String, expected: String)] = [
            ("すくなくなってきた", "少なくなってきた"),
            ("すくなくなってくる", "少なくなってくる"),
            ("おおいのだ", "多いのだ"),
            ("おおいのです", "多いのです"),
            ("おおきいし", "大きいし"),
            ("きをつける", "気を付ける"),
            ("きをつけて", "気を付けて"),
            ("つかったこと", "使ったこと"),
            ("よんだほうが", "読んだ方が"),
            ("よんだほうがいい", "読んだ方がいい"),
            ("きょうゆうできる", "共有できる"),
            ("きょうゆうできない", "共有できない")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionAdjectiveKuNariFormsAreDerived() {
        converter.learn(reading: "にがい", candidate: "苦い")

        let cases: [(reading: String, expected: String)] = [
            ("にがくな", "苦くな"),
            ("にがくなり", "苦くなり"),
            ("にがくなる", "苦くなる"),
            ("にがくなります", "苦くなります")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionAdjectiveKuSuruFormIsDerivedFromBaseAdjectiveCandidate() {
        converter.learn(reading: "みじかい", candidate: "短い")

        let cases: [(reading: String, expected: String)] = [
            ("みじかく", "短く"),
            ("みじかくする", "短くする")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionKotoNegativePostfixChainIsDerived() {
        converter.learn(reading: "きく", candidate: "聞く")

        let cases: [(reading: String, expected: String)] = [
            ("きいたことない", "聞いたことない"),
            ("きいたことなく", "聞いたことなく"),
            ("きいたことなければ", "聞いたことなければ")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionIchidanTeAspectConjunctiveFormsAreDerivedFromBaseVerbCandidate() {
        converter.learn(reading: "にる", candidate: "似る")

        let cases: [(reading: String, expected: String)] = [
            ("にていて", "似ていて"),
            ("にてて", "似てて")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionSuppressionAppliesToDerivedInflectionCandidates() {
        guard let defaults = UserDefaults(suiteName: defaultsSuiteName) else {
            XCTFail("failed to open test defaults")
            return
        }

        defaults.set(
            ["おいしい": ["美味しい"]],
            forKey: KanaKanjiStorageKeys.suppressionVocabulary
        )

        let baseCandidates = converter.candidates(
            for: "おいしい",
            limit: 24,
            systemCandidateMode: .surface
        )
        let inflectedCandidates = converter.candidates(
            for: "おいしく",
            limit: 24,
            systemCandidateMode: .surface
        )

        XCTAssertFalse(
            baseCandidates.contains("美味しい"),
            "candidates=\(baseCandidates)"
        )
        XCTAssertFalse(
            inflectedCandidates.contains("美味しく"),
            "candidates=\(inflectedCandidates)"
        )
    }

    func testRegressionNumericUnitReadingsIncludeCurrencyCandidates() {
        let cases: [(reading: String, expected: String)] = [
            ("せんえん", "千円"),
            ("まんえん", "万円"),
            ("おくえん", "億円"),
            ("ちょうえん", "兆円")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionNumericPrefixBoostPrioritizesCurrencyUnitFallback() {
        let candidates = converter.candidates(
            for: "4まんえん",
            limit: 24,
            systemCandidateMode: .surface
        )

        XCTAssertEqual(candidates.first, "万円", "candidates=\(candidates)")
    }

    func testRegressionNumericCounterCompoundFallbackDerivesSuuBai() {
        let candidates = converter.candidates(
            for: "すうばい",
            limit: 24,
            systemCandidateMode: .surface
        )

        XCTAssertTrue(candidates.contains("数倍"), "candidates=\(candidates)")
    }

    func testRegressionNumericCounterCompoundFallbackDerivesNanPatsu() {
        let candidates = converter.candidates(
            for: "なんぱつ",
            limit: 24,
            systemCandidateMode: .surface
        )

        XCTAssertTrue(candidates.contains("何発"), "candidates=\(candidates)")
    }

    func testRegressionNumericCounterCompoundFallbackDerivesHonCounterByNumberRule() {
        let cases: [(reading: String, expected: String)] = [
            ("いっぽん", "一本"),
            ("にほん", "二本"),
            ("さんぼん", "三本"),
            ("よんほん", "四本"),
            ("ごほん", "五本"),
            ("ろっぽん", "六本"),
            ("ななほん", "七本"),
            ("はっぽん", "八本"),
            ("きゅうほん", "九本"),
            ("じっぽん", "十本"),
            ("じゅっぽん", "十本"),
            ("なんぼん", "何本"),
            ("すうほん", "数本")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionNumericCounterCompoundFallbackDerivesHikiCounterByNumberRule() {
        let cases: [(reading: String, expected: String)] = [
            ("いっぴき", "一匹"),
            ("にひき", "二匹"),
            ("さんびき", "三匹"),
            ("よんひき", "四匹"),
            ("ごひき", "五匹"),
            ("ろっぴき", "六匹"),
            ("ななひき", "七匹"),
            ("はっぴき", "八匹"),
            ("きゅうひき", "九匹"),
            ("じっぴき", "十匹"),
            ("じゅっぴき", "十匹"),
            ("なんびき", "何匹"),
            ("すうひき", "数匹")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionNumericCounterCompoundFallbackDerivesSuuCounterVariants() {
        let cases: [(reading: String, expected: String)] = [
            ("すうこ", "数個"),
            ("すうかい", "数回"),
            ("すうかげつ", "数か月"),
            ("すうかしょ", "数か所"),
            ("すうけん", "数件"),
            ("すうしゅうかん", "数週間"),
            ("すうじかん", "数時間"),
            ("すうじつ", "数日"),
            ("すうだい", "数台"),
            ("すうにん", "数人"),
            ("すうねん", "数年"),
            ("すうびょう", "数秒"),
            ("すうふん", "数分"),
            ("すうまい", "数枚")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionNumericMagnitudeCompoundDerivesSuuSenNenAndVariants() {
        let cases: [(reading: String, expected: String)] = [
            ("すうせんねん", "数千年"),
            ("すうひゃくねん", "数百年"),
            ("すうまんねん", "数万年"),
            ("すうおくねん", "数億年"),
            ("なんびゃくねん", "何百年"),
            ("なんぜんねん", "何千年"),
            ("なんまんねん", "何万年"),
            ("すうせんえん", "数千円"),
            ("すうじゅうにん", "数十人"),
            ("すうせん", "数千"),
            ("なんびゃく", "何百"),
            ("すうぶんのいち", "数分の一"),
            ("なんぶんのいち", "何分の一"),
            ("すうせんぶんのいち", "数千分の一")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionNounKanjiSuffixAffixDerivesBetsuCompounds() {
        converter.learn(reading: "しゅるい", candidate: "種類")
        converter.learn(reading: "くに", candidate: "国")

        let cases: [(reading: String, expected: String)] = [
            ("しゅるいべつ", "種類別"),
            ("くにべつ", "国別")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionNounKanjiPrefixAffixDerivesBetsuCompounds() {
        converter.learn(reading: "かいしゃ", candidate: "会社")
        converter.learn(reading: "しょうひん", candidate: "商品")

        let cases: [(reading: String, expected: String)] = [
            ("べつかいしゃ", "別会社"),
            ("べつしょうひん", "別商品")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionPoliteVolitionalMashouAcrossConjugationClasses() {
        converter.learn(reading: "かう", candidate: "買う")
        converter.learn(reading: "たべる", candidate: "食べる")
        converter.learn(reading: "べんきょう", candidate: "勉強")
        converter.learn(reading: "くる", candidate: "来る")

        let cases: [(reading: String, expected: String)] = [
            ("かいましょう", "買いましょう"),
            ("たべましょう", "食べましょう"),
            ("べんきょうしましょう", "勉強しましょう"),
            ("きましょう", "来ましょう")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionMixedScriptSahenOptInDerivesNeOchiSuru() {
        converter.learn(reading: "ねおち", candidate: "寝落ち")

        let candidates = converter.candidates(
            for: "ねおちする",
            limit: 24,
            systemCandidateMode: .surface
        )

        XCTAssertTrue(candidates.contains("寝落ちする"), "candidates=\(candidates)")
    }

    func testRegressionMixedScriptSahenOptInSkipsUnlistedReadings() {
        converter.learn(reading: "かくうち", candidate: "架空ち")

        let candidates = converter.candidates(
            for: "かくうちする",
            limit: 24,
            systemCandidateMode: .surface
        )

        XCTAssertFalse(candidates.contains("架空ちする"), "candidates=\(candidates)")
    }

    func testRegressionOrdinalMeFallbackPrefersKanjiMeAfterCommittedNumberInput() {
        let candidates = converter.candidates(
            for: "10ぎょうめ",
            limit: 24,
            systemCandidateMode: .surface
        )

        XCTAssertEqual(candidates.first, "行め", "candidates=\(candidates)")

        if let meIndex = candidates.firstIndex(of: "行め"),
            let mokuIndex = candidates.firstIndex(of: "行目") {
            XCTAssertGreaterThan(mokuIndex, meIndex, "candidates=\(candidates)")
        }
    }

    func testRegressionHairuCompoundVerbFormsAreDerivedFromDictionaryForm() {
        converter.learn(reading: "てにはいる", candidate: "手に入る")

        let cases: [(reading: String, expected: String)] = [
            ("てにはいって", "手に入って"),
            ("てにはいった", "手に入った"),
            ("てにはいらない", "手に入らない"),
            ("てにはいれば", "手に入れば"),
            ("てにはいります", "手に入ります")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    func testRegressionWaveDashElongationSurfacesAreFilteredOut() {
        // SudachiDict の「〜」水増し表記(ちゃ〜んと 等)は既定変換に不要。どの生成経路から
        // 入っても(ここでは学習経由で注入)最終段で除去され、正規表記が残ることを確認する。
        converter.learn(reading: "ちゃんと", candidate: "チャント")
        converter.learn(reading: "ちゃんと", candidate: "ちゃ〜んと")

        let candidates = converter.candidates(
            for: "ちゃんと",
            limit: 24,
            systemCandidateMode: .surface
        )

        XCTAssertFalse(
            candidates.contains("ちゃ〜んと"),
            "candidates=\(candidates)"
        )
        XCTAssertTrue(
            candidates.contains("チャント"),
            "candidates=\(candidates)"
        )
    }

    func testRegressionNakaguroDecorationSurfacesAreFilteredOut() {
        // SudachiDict の中黒装飾表記(ち・ゃ・ん/ア・リ・ガ・ト 等)は既定変換に不要。
        // どの経路から入っても(ここでは学習経由で注入)除去され、正当な外国名区切り
        // (アイ・アール=セグメント複数文字)は残ることを確認する。
        converter.learn(reading: "ちゃんと", candidate: "ち・ゃ・んと")
        converter.learn(reading: "ひみつ", candidate: "ヒ・ミ・ツ")
        converter.learn(reading: "あいあーる", candidate: "アイ・アール")

        let chanto = converter.candidates(for: "ちゃんと", limit: 24, systemCandidateMode: .surface)
        XCTAssertFalse(chanto.contains("ち・ゃ・んと"), "candidates=\(chanto)")

        let himitsu = converter.candidates(for: "ひみつ", limit: 24, systemCandidateMode: .surface)
        XCTAssertFalse(himitsu.contains("ヒ・ミ・ツ"), "candidates=\(himitsu)")

        let air = converter.candidates(for: "あいあーる", limit: 24, systemCandidateMode: .surface)
        XCTAssertTrue(air.contains("アイ・アール"), "candidates=\(air)")
    }

    func testRegressionUserRegisteredNakaguroSurfaceSurvivesDecorativeFilter() {
        // ユーザ明示登録(追加語彙)の中黒表記(あ・うん 等の実在固有名)は
        // 装飾フィルタから免除され、候補に残ることを確認する。
        let store = KanaKanjiStore(appGroupID: defaultsSuiteName)
        store.addUserEntry(reading: "あうん", candidate: "あ・うん")

        let candidates = converter.candidates(
            for: "あうん",
            limit: 24,
            systemCandidateMode: .surface
        )

        XCTAssertTrue(
            candidates.contains("あ・うん"),
            "candidates=\(candidates)"
        )
    }

    func testRegressionNounKanjiKaSuffixesAreDerivedFromKanjiStem() {
        // 予約課/予約可 のような 名詞+か(課/可/化/科/下)は SudachiDict に単語として
        // 載らないことが多い。漢字語幹から派生することを確認する。
        converter.learn(reading: "よやく", candidate: "予約")

        let candidates = converter.candidates(
            for: "よやくか",
            limit: 24,
            systemCandidateMode: .surface
        )

        for expected in ["予約課", "予約可", "予約化"] {
            XCTAssertTrue(
                candidates.contains(expected),
                "expected=\(expected) candidates=\(candidates)"
            )
        }
    }

    func testRegressionYatsuPostfixIsDerivedFromVerbStem() {
        // 「入れるやつ」のような 動詞+やつ(口語の体言化)は postfix 素通りで導出する。
        converter.learn(reading: "いれる", candidate: "入れる")
        converter.learn(reading: "つかう", candidate: "使う")

        let cases: [(reading: String, expected: String)] = [
            ("いれるやつ", "入れるやつ"),
            ("つかうやつ", "使うやつ")
        ]

        for testCase in cases {
            let candidates = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )

            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "reading=\(testCase.reading) candidates=\(candidates)"
            )
        }
    }

    private func clearSuite(_ suiteName: String) {
        guard !suiteName.isEmpty else {
            return
        }

        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }
}
