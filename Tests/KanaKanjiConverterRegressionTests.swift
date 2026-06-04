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
            ("おむかえする", "お迎えする"),
            ("およびする", "お呼びする")
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
        converter.learn(reading: "つかう", candidate: "使う")
        converter.learn(reading: "よむ", candidate: "読む")
        converter.learn(reading: "とれる", candidate: "取れる")
        converter.learn(reading: "きょうゆう", candidate: "共有")

        let cases: [(reading: String, expected: String)] = [
            ("すくなくなってきた", "少なくなってきた"),
            ("すくなくなってくる", "少なくなってくる"),
            ("おおいのだ", "多いのだ"),
            ("おおいのです", "多いのです"),
            ("おおきいし", "大きいし"),
            ("つかったこと", "使ったこと"),
            ("よんだほうが", "読んだ方が"),
            ("よんだほうがいい", "読んだ方がいい"),
            ("とれるように", "取れるように"),
            ("とれるような", "取れるような"),
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

    private func clearSuite(_ suiteName: String) {
        guard !suiteName.isEmpty else {
            return
        }

        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }
}
