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

    // 実LM回帰: 開発機の tmp sqlite(実辞書+連文節LM)を app group コンテナへ複製して
    // multiClauseCandidates を直接検証する。tmp が無い環境では skip(実LM依存のため)。
    // むかしみたな: かな断片チェーン(昔+み+た+な、み→た bigram 1010)や短spanレア読み
    // (見店/実棚/三田な)に負けず 昔見たな が最良になること(短span床上げ+文末な減点)。
    func testRegressionRealLMMukashiMitanaPrefersPredicateParse() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["みたな": ["美多奈"]])

        let multi = converter.multiClauseCandidates(for: "むかしみたな", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "昔見たな", "multi=\(multi)")
    }

    // 実LM回帰: 述語直後の 人(にん/じん) は接続しない文法遮断の検証。
    // かく→描く の学習(curated 1500)が かく span を安くすると、遮断なしでは
    // 触って+描く+人(にん) が 触って確認 を逆転していた(さわってかくにん事件)。
    // 人(ひと) の正当な接続(絵を描く人)は影響を受けないことも同時に確認する。
    func testRegressionRealLMPredicatePlusNinIsBlocked() throws {
        try prepareRealLMDictionary()
        converter.store.addLearnedEntry(reading: "かく", candidate: "描く")

        let kakunin = converter.multiClauseCandidates(for: "さわってかくにん", systemCandidateMode: .surface)
        XCTAssertEqual(kakunin.first, "触って確認", "multi=\(kakunin)")

        let kakuhito = converter.multiClauseCandidates(for: "えをかくひと", systemCandidateMode: .surface)
        XCTAssertTrue(
            kakuhito.contains { $0.hasSuffix("描く人") || $0.hasSuffix("書く人") },
            "人(ひと)の正当な接続が失われている multi=\(kakuhito)"
        )
    }

    // 実LM回帰: からだが — curated かな識別 だが(1500)が 空(から)+だが 分割を安くし、
    // 体(からだ)+が(が→EOS 3831 が重い)を218差で逆転していた(空だが/殻だが が先頭、
    // 体が が末尾)。misc の固定句 体が(からだが) と カラ/カラダ 抑制で 体が を最良にする。
    // テストバンドルには misc/suppr が載らないため addUserEntry/defaults 注入で再現する。
    func testRegressionRealLMKaradagaPrefersTaiga() throws {
        try prepareRealLMDictionary()
        converter.store.addUserEntry(reading: "だが", candidate: "だが")
        converter.store.addUserEntry(reading: "からだが", candidate: "体が")
        try injectSuppression(["から": ["カラ"], "からだ": ["カラダ"]])
        converter.clearAllCaches()

        // 固定句 体が(からだが) が最良になると連文節は単一ノード経路として [] を返し
        // 単文節経路(curated 2400)に委ねる仕様。表示は単文節リストがそのまま出る。
        let multi = converter.multiClauseCandidates(for: "からだが", systemCandidateMode: .surface)
        XCTAssertTrue(multi.isEmpty, "multi=\(multi)")

        let single = converter.candidates(for: "からだが", limit: 24, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "体が", "single=\(single)")
        XCTAssertFalse(single.contains("カラダが"), "カラダ抑制が効いていない single=\(single)")
    }

    // 実LM回帰: ほうりつかえるのは — 者(は)=wc11000 のジャンク読みが の→者(3994、の者=もの
    // 由来の読み跨ぎbigram)で安売りされ 法律カエルの者 を作っていた(suppr 者(は) で遮断)。
    // さらに 変える経路(6024+1810)と カエル経路(6927+907)が 7834 で完全タイとなり、
    // ノード列挙順で カエル が先勝ちしていた(同コストは非カタカナ優先のタイブレークで是正)。
    func testRegressionRealLMHouritsuKaeruNohaPrefersKaeru() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["は": ["者"]])

        let multi = converter.multiClauseCandidates(for: "ほうりつかえるのは", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "法律変えるのは", "multi=\(multi)")
    }

    // 実LM回帰: けいぶるのだんせん — 断線(実在語 wc6518)は LM unigram 7369 が弱く、
    // Wikipediaバイアスの断片連鎖 段+戦(段→戦=1716 将棋記事/の→段=4936 文楽記事)に
    // 1181差で負けていた。misc curated 断線(だんせん) で先頭化(LMバイアス型の定番処方)。
    // ケイブル は学習語彙を注入して実機状態(けいぶる→ケイブル)を再現する。
    func testRegressionRealLMKeiburuNoDansenPrefersDansen() throws {
        try prepareRealLMDictionary()
        converter.store.addLearnedEntry(reading: "けいぶる", candidate: "ケイブル")
        converter.store.addUserEntry(reading: "だんせん", candidate: "断線")

        let multi = converter.multiClauseCandidates(for: "けいぶるのだんせん", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "ケイブルの断線", "multi=\(multi)")
    }

    // 様態そう の長音カジュアル表記「そー」が そう と同格で活用導出されること
    // (おいしそー→美味しそー 等。形容詞は inflection メタデータが要るため実LMで検証)。
    func testRegressionRealLMSooLongVowelVariantDerivesLikeSou() throws {
        try prepareRealLMDictionary()

        // 実機の抑制状態を再現(オイシイ/オイシい=カタカナ書き抑制)
        try injectSuppression(["おいしい": ["オイシイ", "オイシい"]])

        let adjective = converter.candidates(for: "おいしそー", limit: 24, systemCandidateMode: .surface)
        XCTAssertTrue(adjective.contains("美味しそー"), "adjective=\(adjective)")
        XCTAssertTrue(adjective.contains("おいしそー"), "adjective=\(adjective)")
        // 敬語o-suru合成の連用1文字暴発(お居しそー/お射しそー/お鋳しそー)が居ないこと
        XCTAssertFalse(
            adjective.contains { $0.hasPrefix("お居し") || $0.hasPrefix("お射し") || $0.hasPrefix("お鋳し") },
            "adjective=\(adjective)"
        )
        // オイシい 抑制で オイシそー が導出されないこと
        XCTAssertFalse(adjective.contains("オイシそー"), "adjective=\(adjective)")

        let ichidan = converter.candidates(for: "たべそー", limit: 24, systemCandidateMode: .surface)
        XCTAssertTrue(ichidan.contains("食べそー"), "ichidan=\(ichidan)")

        let godan = converter.candidates(for: "いきそー", limit: 24, systemCandidateMode: .surface)
        XCTAssertTrue(godan.contains("行きそー"), "godan=\(godan)")
    }

    // 実LM回帰: かれらは — Sudachi は 彼ら を A単位で 彼+ら に分割するため word_costs に
    // 彼ら が無く、sacoche の カレラ/Carrera(curated 1500)が合成経路(彼+ら+は 9576)に
    // 圧勝して かれらは→カレラは 一色になっていた。misc curated 彼ら で同点(7270)を作り、
    // 非ネイティブ表層(カタカナ/ラテン字のみ)タイブレークで 彼らは を最良にする。
    // カレラは/Carreraは は同点変種として温存される(ポルシェ用途は無傷)。
    func testRegressionRealLMKarerahaPrefersKarera() throws {
        try prepareRealLMDictionary()
        // 実機状態を再現: sacoche(カレラ/Carrera)+misc(彼ら)相当を curated 注入
        converter.store.addUserEntry(reading: "かれら", candidate: "カレラ")
        converter.store.addUserEntry(reading: "かれら", candidate: "Carrera")
        converter.store.addUserEntry(reading: "かれら", candidate: "彼ら")

        let multi = converter.multiClauseCandidates(for: "かれらは", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "彼らは", "multi=\(multi)")
        XCTAssertTrue(multi.contains("カレラは"), "カレラは が変種に残ること multi=\(multi)")
    }

    // 実LM回帰: にうっかり — Sudachi の促音大書き表記ゆれエントリ うツかり(wc7730)が、
    // 全かなエコー抑制で捨てられた最良(に+うっかり)の同コスト変種(dictUnknown 8700 で
    // delta 0)として繰り上がっていた。suppr うツかり+misc かな識別 うっかり(エコー抑制
    // 免除)で にうっかり を最良に。
    func testRegressionRealLMNiUkkariPrefersKana() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["うっかり": ["うツかり"]])
        converter.store.addUserEntry(reading: "うっかり", candidate: "うっかり")

        let multi = converter.multiClauseCandidates(for: "にうっかり", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "にうっかり", "multi=\(multi)")
        XCTAssertFalse(multi.contains("にうツかり"), "multi=\(multi)")
    }

    // 実LM回帰: やこうせいのどうぶつ — 夜行性は Sudachi 実在(wc10555 ジャンク級、
    // uni7792)だが、文頭 や(2998)+後世(や→後世 4885)+の(後世→の 413) の接着剤ジャンクに
    // 1979差で負けていた。misc curated 夜行性+かな識別床上げ除外から や を削除で是正。
    func testRegressionRealLMYakouseiPrefersNocturnal() throws {
        try prepareRealLMDictionary()
        converter.store.addUserEntry(reading: "やこうせい", candidate: "夜行性")

        let multi = converter.multiClauseCandidates(for: "やこうせいのどうぶつ", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "夜行性の動物", "multi=\(multi)")
    }

    // 実LM回帰: それぞれを — かな正書語(uni4329≪其々7995)なのにかな識別curatedが無く、
    // 最良の それぞれ+を が全かなエコー抑制で捨てられ 其々を が繰り上がっていた
    // (にうっかり と同型)。misc かな識別 それぞれ で最良を通す。
    func testRegressionRealLMSorezoreWoPrefersKana() throws {
        try prepareRealLMDictionary()
        converter.store.addUserEntry(reading: "それぞれ", candidate: "それぞれ")

        let multi = converter.multiClauseCandidates(for: "それぞれを", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "それぞれを", "multi=\(multi)")
        XCTAssertTrue(multi.contains("其々を"), "漢字変種の温存 multi=\(multi)")
    }

    // 実LM回帰: しゅうせい — 熟語合成ブーストで 終生/醜声 が exact 辞書順(修正 wc6505 先頭)
    // より前に繰り上がっていた。seed 最強ブースト(こうこう→高校 と同処方)で 修正/習性 を
    // #1/#2 に固定する。
    func testRegressionRealLMShuuseiPrefersShuseiAndShusei() throws {
        try prepareRealLMDictionary()

        let single = converter.candidates(for: "しゅうせい", limit: 12, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(2)), ["修正", "習性"], "single=\(single)")
    }

    // 実LM回帰: ふくすうあぷりって — 語頭禁止(促音始まり100000)が引用助詞 って(wc5101)を
    // 巻き添えにし、複数+アプリ+って が組めず、り を吸収した活用合成 りって(7200)による
    // 複数アプ+りって が最良化していた。って/っていう を語頭禁止の例外(ん と同格)にして
    // 是正。ッて/ツて 等の表記ゆれ変種は suppr で抑制(注入で再現)。
    func testRegressionRealLMApuritteQuotative() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["って": ["ッて", "ツて", "ッテ", "っテ"]])

        let multi = converter.multiClauseCandidates(for: "ふくすうあぷりって", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "複数アプリって", "multi=\(multi)")
        XCTAssertFalse(
            multi.contains { $0.contains("アプり") || $0.contains("ッて") || $0.contains("ツて") },
            "multi=\(multi)"
        )
    }

    // 実LM回帰: おくられてきます — 受身+てくる アスペクト連鎖(られてきます/れてきます)の
    // 活用ルールが未定義で 送られてきます が供給されず、奥+られてきます(られる基底のかな
    // 活用合成)/奥ラれてきます(基底 ラれる=Sudachi混在表記)/老くられてきます(形容詞く
    // ルールが 老い を誤って活用)等の断片が最良化していた(供給欠落型)。
    func testRegressionRealLMOkurareteKimasuDerives() throws {
        try prepareRealLMDictionary()

        let single = converter.candidates(for: "おくられてきます", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "送られてきます", "single=\(single)")

        // 一段・サ変の同型連鎖も導出されること
        let ichidan = converter.candidates(for: "たべられてきた", limit: 8, systemCandidateMode: .surface)
        XCTAssertTrue(ichidan.contains("食べられてきた"), "ichidan=\(ichidan)")
    }

    // 実LM回帰: くわえよう — wc では 加える(9397)が基底先頭なのに並べ替え層で 銜えよう が
    // 繰り上がっていた(しゅうせい と同型)。seed くわえる=[加える, 咥える, くわえる] で
    // 加えよう を先頭固定、seed 非掲載の 銜える は後方へ沈む。
    func testRegressionRealLMKuwaeyouPrefersKuwaeru() throws {
        try prepareRealLMDictionary()

        let single = converter.candidates(for: "くわえよう", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "加えよう", "single=\(single)")
        if let ginIndex = single.firstIndex(of: "銜えよう") {
            XCTAssertGreaterThanOrEqual(ginIndex, 3, "銜えよう は末尾寄りに sink=\(single)")
        }
    }

    // 実LM回帰: みずは — レア人名11件(水羽/水華/... 全て wc10000)が読み完全一致として
    // 水+は 合成より前に並んでいた(たつと人名と同型)。suppr 11件+misc 固定句 水は で
    // 先頭化。見ずは 等の動詞系は温存される。
    func testRegressionRealLMMizuhaPrefersMizuWa() throws {
        try prepareRealLMDictionary()
        try injectSuppression([
            "みずは": ["水羽", "水華", "水葉", "水葩", "泉羽", "泉葉", "瑞羽", "瑞芭", "瑞葉", "美須羽", "美須葉"]
        ])
        converter.store.addUserEntry(reading: "みずは", candidate: "水は")

        let single = converter.candidates(for: "みずは", limit: 12, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "水は", "single=\(single)")
        XCTAssertFalse(single.contains("水羽"), "single=\(single)")
        XCTAssertTrue(single.contains("見ずは"), "動詞系の温存 single=\(single)")
    }

    // 実LM回帰: こんなかんじ — bigram 無しで unigram 漢字(4805)<感じ(5118) の Wikipedia
    // バイアスにより こんな漢字 が先頭だった。連体詞(こんな/そんな 等)直後の 漢字 に
    // 小減点(500)して こんな感じ を最良に。漢字/幹事/寛治 は変種として温存される。
    func testRegressionRealLMKonnaKanjiPrefersFeeling() throws {
        try prepareRealLMDictionary()

        let multi = converter.multiClauseCandidates(for: "こんなかんじ", systemCandidateMode: .surface)
        XCTAssertEqual(Array(multi.prefix(2)), ["こんな感じ", "こんな漢字"], "multi=\(multi)")
    }

    // 実LM回帰: としとってから — wc は 年取る/年老る(共に10085)のみで 歳 系欠落、
    // 賭し(uni7489)+とって 断片が最良化していた。misc curated(五段+て/た形直接)で
    // 年取ってから #1、歳とってから #2 を固定。
    func testRegressionRealLMToshitotteKara() throws {
        try prepareRealLMDictionary()
        // addUserEntry は先頭挿入(新しい順)のため、実機の misc JSON 順
        // (年取って が先頭)に合わせて逆順で注入する
        converter.store.addUserEntry(reading: "としとって", candidate: "歳とって")
        converter.store.addUserEntry(reading: "としとって", candidate: "年取って")

        let multi = converter.multiClauseCandidates(for: "としとってから", systemCandidateMode: .surface)
        XCTAssertEqual(Array(multi.prefix(2)), ["年取ってから", "歳とってから"], "multi=\(multi)")
    }

    // 実LM回帰: おそいからな — 唐菜(からな 9770)等のジャンクと、文末な減点の助詞誤爆
    // (から は述語末尾でないため 遅い+から+な に+3000が乗っていた)の二重原因。
    // suppr(唐菜/晏い/遅そい/襲)+助詞直後の な 免除で 遅いからな を最良に。
    func testRegressionRealLMOsoiKaranaPrefersKana() throws {
        try prepareRealLMDictionary()
        try injectSuppression([
            "からな": ["唐菜"],
            "おそい": ["晏い", "遅そい", "襲"]
        ])

        let multi = converter.multiClauseCandidates(for: "おそいからな", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "遅いからな", "multi=\(multi)")
    }

    // 実LM回帰: どちらもおいしく — 最良の どちらも+おいしく(uni7143)が全かなエコー抑制で
    // 捨てられ、同スパンの敬語合成 お石工/お石ユ(石ユ=石工のカタカナ混じり表記ゆれ、
    // suppr済)が変種繰り上がりしていた(うっかり同型)。misc かな識別 おいしく で是正。
    func testRegressionRealLMDochiramoOishiku() throws {
        try prepareRealLMDictionary()
        try injectSuppression([
            "いしく": ["石ユ"],
            "おいしい": ["美味しい", "オイシイ", "オイシい"]
        ])
        converter.store.addUserEntry(reading: "おいしく", candidate: "おいしく")

        let multi = converter.multiClauseCandidates(for: "どちらもおいしく", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "どちらもおいしく", "multi=\(multi)")
        // お石工(実在語の敬語合成)は変種#2に残る。表記ゆれの 石ユ だけ不在を確認
        XCTAssertFalse(multi.contains { $0.contains("石ユ") }, "multi=\(multi)")
    }

    // 実LM回帰: いただきました — LMはかな優位(いただく6955<戴7334<頂7446)だが、単文節の
    // かな識別LM判定が活用形読み(LM未収録)で行われ証明できず 頂きました が先頭だった。
    // misc 頻出形直接登録(ございます同処方)+いたゞく(繰り返し記号の表記ゆれ)抑制。
    func testRegressionRealLMItadakimashitaPrefersKana() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["いただく": ["いたゞく"]])
        converter.store.addUserEntry(reading: "いただきました", candidate: "いただきました")

        let single = converter.candidates(for: "いただきました", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "いただきました", "single=\(single)")
        XCTAssertTrue(single.contains("頂きました"), "漢字版温存 single=\(single)")
        XCTAssertFalse(single.contains("いたゞきました"), "single=\(single)")
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

    func testRegressionNakunaruChainDerivesNegativeChangeForms() {
        converter.learn(reading: "つかう", candidate: "使う")
        converter.learn(reading: "たべる", candidate: "食べる")

        let cases: [(reading: String, expected: String)] = [
            ("つかわなくなる", "使わなくなる"),
            ("つかわなくなった", "使わなくなった"),
            ("つかわなくなったら", "使わなくなったら"),
            ("つかわなくなって", "使わなくなって"),
            ("たべなくなった", "食べなくなった"),
            ("たべなくなったら", "食べなくなったら")
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

    func testRegressionGodanCausativeImperativeIsDerived() {
        converter.learn(reading: "のむ", candidate: "飲む")
        converter.learn(reading: "かく", candidate: "書く")

        let cases: [(reading: String, expected: String)] = [
            ("のませろ", "飲ませろ"),
            ("のませよ", "飲ませよ"),
            ("かかせろ", "書かせろ")
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

    func testRegressionShimauPostfixComposesFromTeFormStem() {
        converter.learn(reading: "うって", candidate: "売って")

        let candidates = converter.candidates(
            for: "うってしまって",
            limit: 24,
            systemCandidateMode: .surface
        )

        XCTAssertTrue(
            candidates.contains("売ってしまって"),
            "candidates=\(candidates)"
        )

        if let kanaIndex = candidates.firstIndex(of: "うってしまって"),
            let composedIndex = candidates.firstIndex(of: "売ってしまって") {
            XCTAssertLessThan(
                composedIndex,
                kanaIndex,
                "売ってしまって はかな識別より上位であるべき: \(candidates)"
            )
        }
    }

    func testRegressionCompoundNukuVerbFormsAreDerived() {
        converter.learn(reading: "たえぬく", candidate: "耐え抜く")

        let cases: [(reading: String, expected: String)] = [
            ("たえぬいた", "耐え抜いた"),
            ("たえぬいて", "耐え抜いて"),
            ("たえぬきます", "耐え抜きます")
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

    func testRegressionAdjectiveMeDegreeFormsAreDerived() {
        converter.learn(reading: "あたらしい", candidate: "新しい")
        converter.learn(reading: "おおきい", candidate: "大きい")

        let cases: [(reading: String, expected: String)] = [
            ("あたらしめ", "新しめ"),
            ("あたらしめの", "新しめの"),
            ("おおきめ", "大きめ"),
            ("おおきめに", "大きめに")
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

    func testRegressionImperativeQuoteTteFormsAreDerived() {
        converter.learn(reading: "はらう", candidate: "払う")
        converter.learn(reading: "まつ", candidate: "待つ")
        converter.learn(reading: "たべる", candidate: "食べる")

        let cases: [(reading: String, expected: String)] = [
            ("はらえって", "払えって"),
            ("まてって", "待てって"),
            ("たべろって", "食べろって")
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

    func testRegressionNaaLongParticlePostfixIsDerived() {
        // 「いきたいなあ」のような 長形の終助詞(なあ/ねえ)も postfix 素通りで導出する。
        converter.learn(reading: "いく", candidate: "行く")

        let cases: [(reading: String, expected: String)] = [
            ("いきたいなあ", "行きたいなあ"),
            ("いきたいねえ", "行きたいねえ")
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

    func testRegressionKanaIdentityLearningRequiresExplicitChipCommitAndShortReading() {
        // かな識別(候補==読み)は通常の確定では学習しない(連文節の素通りブロック事故防止)。
        converter.learn(reading: "ちゃんと", candidate: "ちゃんと")
        XCTAssertFalse(converter.hasLearnedKanaIdentity(for: "ちゃんと"))

        // かな候補チップの明示タップ(allowKanaIdentity)なら単語相当の読みは学習する。
        converter.learn(reading: "ちゃんと", candidate: "ちゃんと", allowKanaIdentity: true)
        XCTAssertTrue(converter.hasLearnedKanaIdentity(for: "ちゃんと"))

        // 文丸ごとの読みは明示タップでも学習しない。
        converter.learn(
            reading: "きょうはいいてんきですね",
            candidate: "きょうはいいてんきですね",
            allowKanaIdentity: true
        )
        XCTAssertFalse(converter.hasLearnedKanaIdentity(for: "きょうはいいてんきですね"))

        // 保存→再読込(learnedDictionary の読み込みフィルタ)でも単語相当の識別は残る。
        // 学習の永続化は非同期のため、フレッシュな store で読む前にフラッシュする。
        converter.store.waitForPendingLearningPersists()
        let reloaded = KanaKanjiConverter(store: KanaKanjiStore(appGroupID: defaultsSuiteName))
        XCTAssertTrue(reloaded.hasLearnedKanaIdentity(for: "ちゃんと"))
    }

    func testRegressionInitialUserDictionarySahenNounDerivesConjugations() {
        // 追加語彙(void.plist=initialUserDictionary)のサ変名詞も活用推論の対象になる
        // (まかいぞうしてる→魔改造してる)。以前は手動追加分のみで、void 由来は
        // し→市 等の誤分割だけが残っていた。
        let derived = converter.inflectionCandidates(
            for: "まかいぞうしてる",
            userDictionary: [:],
            initialUserDictionary: ["まかいぞう": ["魔改造"]],
            systemCandidateMode: .surface,
            limit: 5
        )

        XCTAssertTrue(derived.contains("魔改造してる"), "derived=\(derived)")
    }

    func testRegressionTeMiruVolitionalIsDerived() {
        // 「買ってみようかな」= てみる系の意志形+終助詞。てみよう チェーンから導出する。
        converter.learn(reading: "かう", candidate: "買う")

        let candidates = converter.candidates(
            for: "かってみようかな",
            limit: 24,
            systemCandidateMode: .surface
        )

        XCTAssertTrue(candidates.contains("買ってみようかな"), "candidates=\(candidates)")

        let tara = converter.candidates(for: "かってみたら", limit: 24, systemCandidateMode: .surface)
        XCTAssertTrue(tara.contains("買ってみたら"), "candidates=\(tara)")
    }

    func testRegressionKanaIdentityLeadingRequiresLexicalEvidence() {
        // かな識別を先頭に残すのは「かなが正書」の根拠がある読みだけ。
        // 合成で組み上がるだけの読み(かってみようかな 等)は対象外。
        XCTAssertFalse(converter.shouldKeepKanaIdentityLeading(for: "かってみようかな"))

        // 学習済み(かなチップ明示タップ)は根拠になる。
        converter.learn(reading: "ちゃんと", candidate: "ちゃんと", allowKanaIdentity: true)
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "ちゃんと"))

        // 追加語彙(だが→だが 型)も根拠になる。converter の store は辞書をキャッシュする
        // ため、書き込み後に生成したフレッシュな converter で確認する。
        KanaKanjiStore(appGroupID: defaultsSuiteName).addUserEntry(reading: "だが", candidate: "だが")
        let freshConverter = KanaKanjiConverter(store: KanaKanjiStore(appGroupID: defaultsSuiteName))
        XCTAssertTrue(freshConverter.shouldKeepKanaIdentityLeading(for: "だが"))
    }

    func testRegressionNiSuruFamilyPostfixIsDerived() {
        // 「もやし炒めにした」= 名詞+にする 文法族。postfix 素通りで導出する
        // (連文節では にし→西 の単漢字が に+した を押しのけるため、単一経路で正解を供給)。
        converter.learn(reading: "もやしいため", candidate: "もやし炒め")

        let cases: [(reading: String, expected: String)] = [
            ("もやしいためにした", "もやし炒めにした"),
            ("もやしいためにしよう", "もやし炒めにしよう"),
            ("もやしいためにします", "もやし炒めにします")
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

    // 実LM回帰: かな素通し断片直後の 人(にん) 遮断と、ぜい金(かな漢字混じり収穫遺物)の抑制。
    // し→人(bigram5902、ひと文脈からの読み跨ぎ借用)+人→から(2336)が複合助詞 からも の
    // clamp(1200)を人側だけに発動させ、bigramを持たない 死人(7331)経路を逆転していた
    // (しにんからもぜいきん→し人からも税金/し人からもぜい金)。
    func testRegressionRealLMShininKaramoHasNoFragmentNin() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["ぜいきん": ["ぜい金"]])

        let multi = converter.multiClauseCandidates(for: "しにんからもぜいきん", systemCandidateMode: .surface)
        XCTAssertTrue(multi.contains("死人からも税金"), "multi=\(multi)")
        XCTAssertFalse(multi.contains(where: { $0.contains("し人") || $0.contains("氏人") }), "multi=\(multi)")
        XCTAssertFalse(multi.contains(where: { $0.contains("ぜい金") }), "multi=\(multi)")
    }

    // 実LM回帰: 文語助動詞 べし のかな正書curated供給。辞書の読み べし は 餅子(wc7404
    // レア語)のみで、かな同一ノードが供給されず やめるべし→止める餅子 等になっていた。
    func testRegressionRealLMYameruBeshiPrefersKanaBeshi() throws {
        try prepareRealLMDictionary()
        // 実機の追加語彙(misc.plist 由来はテストバンドルに載らない)を store 側で再現
        converter.store.addUserEntry(reading: "べし", candidate: "べし")

        let multi = converter.multiClauseCandidates(for: "やめるべし", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "止めるべし", "multi=\(multi)")
        XCTAssertTrue(multi.contains("やめるべし"), "multi=\(multi)")
        if let kanaIndex = multi.firstIndex(of: "やめるべし"),
            let mochikoIndex = multi.firstIndex(where: { $0.contains("餅子") }) {
            XCTAssertLessThan(kanaIndex, mochikoIndex, "multi=\(multi)")
        }
    }

    // 実LM回帰: かな正書の口語形容詞 でかい の curated 供給+curated EOS 上限。
    // でかい→EOS bigram が無く(Wikipedia文語バイアス、EOS遷移は dictUnknown 8700)、
    // 文末で 出(で)+会(かい) の断片連結(出口 会→EOS 1571)に負けていた
    // (そんなにでかい→そんなに出会/出下位/出買い/出貝)。
    func testRegressionRealLMSonnaniDekaiPrefersKana() throws {
        try prepareRealLMDictionary()
        // 実機の追加語彙(misc.plist 由来はテストバンドルに載らない)を store 側で再現
        converter.store.addUserEntry(reading: "でかい", candidate: "でかい")

        let multi = converter.multiClauseCandidates(for: "そんなにでかい", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "そんなにでかい", "multi=\(multi)")
        XCTAssertFalse(multi.contains(where: { $0.contains("出会") || $0.contains("出貝") }), "multi=\(multi)")
    }

    // 実LM回帰: きをつけよう→気を付けよう。単字 き は短spanレア読み床で 気(wc6164)が
    // 木(wc4548)に負けるため 気を を curated 供給。さらに活用派生の OOV 上限
    // (LM 実在で高い 付けよう 7743 が未収録の 着けよう OOV 7200 に逆転される)と
    // seed つける=[付ける,着ける] の基底順で 付けよう を最良にする。
    func testRegressionRealLMKiwoTsukeyouPrefersKiwo() throws {
        try prepareRealLMDictionary()
        converter.store.addUserEntry(reading: "きを", candidate: "気を")

        let multi = converter.multiClauseCandidates(for: "きをつけよう", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "気を付けよう", "multi=\(multi)")
        XCTAssertFalse(multi.contains(where: { $0.contains("木") }), "multi=\(multi)")
    }

    // 実LM回帰: ですけどー のかな先頭化。けどー は uni/bigram 未収録で全かな best が
    // エコー抑制に捨てられ デスけどー/ですゥけどー(装飾収穫遺物)が繰り上がっていた。
    // けど/けどー を終助詞クラスタに追加+ですゥ族を suppr 抑制。
    func testRegressionRealLMDesukedoLongVowelPrefersKana() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["です": ["ですゥ", "です〜", "で〜す", "で〜〜す"]])

        let multiLong = converter.multiClauseCandidates(for: "ですけどー", systemCandidateMode: .surface)
        XCTAssertEqual(multiLong.first, "ですけどー", "multi=\(multiLong)")
        XCTAssertFalse(multiLong.contains(where: { $0.contains("ゥ") }), "multi=\(multiLong)")

        let multiShort = converter.multiClauseCandidates(for: "ですけど", systemCandidateMode: .surface)
        XCTAssertEqual(multiShort.first, "ですけど", "multi=\(multiShort)")

        let single = converter.candidates(for: "ですけど", limit: 8, systemCandidateMode: .surface)
        XCTAssertFalse(single.contains(where: { $0.contains("ゥ") }), "single=\(single)")
    }

    // 実LM回帰: 実機相当の追加語彙(sacoche+misc 全部)込みでの検証。テストバンドルには
    // 追加語彙 JSON が載らず initialUserDictionary が空のため、エンジン直呼びだけでは
    // 実機と乖離する(ろーまにいたる事件の教訓)。curated のか(疑問形)が 〜のかお を
    // のか+お に分断して 顔 のスパンが消えていた(あんたのかお南海揉みたい/乃佳お 等)。
    // 分断される側の 顔 も curated 化して救済(同床なら文節数の少ない区切りが勝つ)。
    func testRegressionRealLMKaoNankaimoWithFullVocab() throws {
        try prepareRealLMDictionary()
        // 実機相当の抑制を注入(1912確立の手順)
        let supprData = try Data(contentsOf: URL(fileURLWithPath: "/Users/kusakabe/Git/ecritu/KeyboardExtension/InitialSupprHiddenVocabMigration.json"))
        UserDefaults(suiteName: defaultsSuiteName)?.set(supprData, forKey: "ÉcrituSuppr_Vocab")
        // 実機相当の追加語彙(sacoche+misc)を注入 — テストバンドルには JSON が載らず
        // initialUserDictionary が空のため(ろーまにいたる事件の教訓)
        for name in ["InitialAjoutVocabMigration", "InitialMiscVocabMigration"] {
            let data = try Data(contentsOf: URL(fileURLWithPath: "/Users/kusakabe/Git/ecritu/KeyboardExtension/\(name).json"))
            let dict = try JSONDecoder().decode([String: [String]].self, from: data)
            for (reading, candidates) in dict {
                for candidate in candidates.reversed() {
                    converter.store.addUserEntry(reading: reading, candidate: candidate)
                }
            }
        }
        let freshConverter = KanaKanjiConverter(store: KanaKanjiStore(appGroupID: defaultsSuiteName))
        let multi = freshConverter.multiClauseCandidates(for: "あんたのかおなんかいもみたい", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "あんたの顔何回も見たい", "multi=\(multi)")
        XCTAssertFalse(multi.contains(where: { $0.contains("南海揉") || $0.contains("乃佳") }), "multi=\(multi)")
    }

    // 実LM回帰: 動詞終止形+のが(名詞化節)。Sudachi は の+が に分割し動詞→の の bigram も
    // 未観測が多いため、名詞側だけ bigram(宅→の 1484/核→の)で安くなり 宅のが好き/
    // 核のが好き 等へ逆転していた。修正: (1) 述語形直後の のが/のは/のを/のも/のに を
    // 単位ノードとしてクランプ+かな単位ノードを常設(辞書にレア名前 野賀 しか無いと
    // 素通り補完が走らずノード自体が立たない)、(2) 辞書形述語(inflection_classes 登録)は
    // 短spanレア読み床を免除(Sudachi の動詞 word_cost は単漢字名詞より系統的に高い:
    // 炊く9118/書く 等。読み跨ぎの頻出表層 良く(いく) はクラス未登録なので床の保護は維持)。
    func testRegressionRealLMVerbNogaNominalizerPrefersVerb() throws {
        try prepareRealLMDictionary()

        let cases: [(reading: String, expected: String)] = [
            ("たくのがすき", "炊くのが好き"),
            ("いくのがすき", "行くのが好き"),
            ("よむのがすき", "読むのが好き")
        ]
        for testCase in cases {
            let multi = converter.multiClauseCandidates(for: testCase.reading, systemCandidateMode: .surface)
            XCTAssertEqual(multi.first, testCase.expected, "reading=\(testCase.reading) multi=\(multi)")
        }
        // かくのがすき は 書く/描く とも正当(絵を描くのが好き)。seed の連文節供給(2079)で
        // 描く ノードが常時ラティスに載り、LM(uni は 描く が頻出)どおり 描く が最良になる。
        // 両方が上位2位以内に入ることを固定する(核のが好き 等のジャンク排除が本旨)。
        let kaku = converter.multiClauseCandidates(for: "かくのがすき", systemCandidateMode: .surface)
        XCTAssertEqual(Set(kaku.prefix(2)), Set(["書くのが好き", "描くのが好き"]), "multi=\(kaku)")
        // 名詞ジャンク(宅/核)が経路から消えていること
        let taku = converter.multiClauseCandidates(for: "たくのがすき", systemCandidateMode: .surface)
        XCTAssertFalse(taku.contains(where: { $0.contains("宅") }), "multi=\(taku)")
    }

    // 実LM回帰: 追加語彙(すくえあ→Square)+格助詞+活用の合成で、に が ニ に化けない
    // こと(Squareニすれば 報告のロック)。現行エンジンはクリーン状態で正解するため、
    // 実機相当の追加語彙全注入で固定する。
    func testRegressionRealLMSquareNiSurebaKeepsKanaParticle() throws {
        try prepareRealLMDictionary()
        let supprData = try Data(contentsOf: URL(fileURLWithPath: "/Users/kusakabe/Git/ecritu/KeyboardExtension/InitialSupprHiddenVocabMigration.json"))
        UserDefaults(suiteName: defaultsSuiteName)?.set(supprData, forKey: "ÉcrituSuppr_Vocab")
        for name in ["InitialAjoutVocabMigration", "InitialMiscVocabMigration"] {
            let data = try Data(contentsOf: URL(fileURLWithPath: "/Users/kusakabe/Git/ecritu/KeyboardExtension/\(name).json"))
            let dict = try JSONDecoder().decode([String: [String]].self, from: data)
            for (reading, candidates) in dict {
                for candidate in candidates.reversed() {
                    converter.store.addUserEntry(reading: reading, candidate: candidate)
                }
            }
        }
        let freshConverter = KanaKanjiConverter(store: KanaKanjiStore(appGroupID: defaultsSuiteName))
        let multi = freshConverter.multiClauseCandidates(for: "すくえあにすれば", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "Squareにすれば", "multi=\(multi)")
        XCTAssertFalse(multi.contains(where: { $0.contains("ニ") }), "multi=\(multi)")
        let single = freshConverter.candidates(for: "すくえあにすれば", limit: 10, systemCandidateMode: .surface)
        XCTAssertFalse(single.contains(where: { $0.contains("ニす") }), "single=\(single)")
    }

    // 実LM回帰: 汎用の ではなく/でなく のかな正書curated供給。かな なく は wc10363 の
    // 短span床上げで沈み(無く/莫く/鳴く/泣く は ない基底の活用派生や辞書語で先行)、
    // 全かな best はエコー抑制に捨てられて とかでは無く が最良になっていた。
    // curated 句にすることで echo 例外(経路に curated)が効き、かなが先頭に出る。
    func testRegressionRealLMDehanakuPrefersKana() throws {
        try prepareRealLMDictionary()
        converter.store.addUserEntry(reading: "ではなく", candidate: "ではなく")
        converter.store.addUserEntry(reading: "でなく", candidate: "でなく")
        for input in ["とかではなく", "とかでなく", "それではなく"] {
            let multi = converter.multiClauseCandidates(for: input, systemCandidateMode: .surface)
            XCTAssertEqual(multi.first, input, "multi=\(multi)")
            XCTAssertFalse(multi.contains(where: { $0.contains("無く") || $0.contains("莫") }), "multi=\(multi)")
        }
    }

    // 実LM回帰: 母音字伸ばしの終助詞 なあ/ねえ。してるなあ(全かな best)がエコー抑制に
    // 捨てられ、名前収穫の変種(してる菜亜 wc10000/しテルなあ)が繰り上がっていた
    // (いるなー/ですけどー と同族)。なあ 等を終助詞クラスタに追加して文末かなを正規扱い。
    func testRegressionRealLMShiterunaaPrefersKana() throws {
        try prepareRealLMDictionary()

        let multi = converter.multiClauseCandidates(for: "してるなあ", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "してるなあ", "multi=\(multi)")
        XCTAssertFalse(multi.contains(where: { $0.contains("菜亜") }), "multi=\(multi)")
        // 機能語区間のカタカナ人名変種(しテルなあ)も出さない
        XCTAssertFalse(multi.contains(where: { $0.contains("テル") }), "multi=\(multi)")

        let neeMulti = converter.multiClauseCandidates(for: "つかれたねえ", systemCandidateMode: .surface)
        XCTAssertEqual(neeMulti.first, "疲れたねえ", "multi=\(neeMulti)")
    }

    // 実LM回帰: なかの の並び。辞書は人名のみ(中野/仲野/中埜/名香野…)で 中の が
    // 合成経由の末尾に落ちていた。seed で 中の を供給し、交ぜ書き 中ノ(wc6000)と
    // カタカナ人名 ナカノ(wc5652)は suppr 抑制。
    func testRegressionRealLMNakanoOffersNakaNoEarly() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["なかの": ["中ノ", "ナカノ"]])

        let candidates = converter.candidates(for: "なかの", limit: 12, systemCandidateMode: .surface)
        guard let nakaNoIndex = candidates.firstIndex(of: "中の") else {
            return XCTFail("中の not offered: \(candidates)")
        }
        XCTAssertLessThan(nakaNoIndex, 3, "candidates=\(candidates)")
        XCTAssertTrue(candidates.contains("中野"), "candidates=\(candidates)")
        XCTAssertFalse(candidates.contains("中ノ"), "candidates=\(candidates)")
        XCTAssertFalse(candidates.contains("ナカノ"), "candidates=\(candidates)")
    }

    // 約物の読み変換(exactReadingOnlySeed): よく使う記号は読みの完全一致でのみ候補末尾に
    // 供給する。合成(ばつが 等)や連文節には漏らさない(踊り字と同じ仕組み)。
    func testYakumonoExactReadingOnlySupply() {
        let exactCases: [(reading: String, symbol: String)] = [
            ("ばつ", "×"),
            ("まる", "○"),
            ("こめじるし", "※"),
            ("やじるし", "→"),
            ("ちぇっく", "✓"),
            ("なかぐろ", "・")
        ]
        for testCase in exactCases {
            let candidates = converter.candidates(for: testCase.reading, limit: 30, systemCandidateMode: .surface)
            XCTAssertTrue(candidates.contains(testCase.symbol), "reading=\(testCase.reading) candidates=\(candidates)")
        }
        // 完全一致でない読みには混ざらない
        let composed = converter.candidates(for: "ばつが", limit: 30, systemCandidateMode: .surface)
        XCTAssertFalse(composed.contains(where: { $0.contains("×") }), "candidates=\(composed)")
        let shita = converter.candidates(for: "したの", limit: 30, systemCandidateMode: .surface)
        XCTAssertFalse(shita.contains(where: { $0.contains("↓") }), "candidates=\(shita)")
        // 連文節のラティスにも載らない(まる/した 等のスパンは word_costs 由来のみ。
        // seed の連文節供給(a2)は通常 seed だけを参照し、exactReadingOnlySeed は対象外)
        for reading in ["まるをかいた", "やじるしをかく", "したのほうにある"] {
            let multi = converter.multiClauseCandidates(for: reading, systemCandidateMode: .surface)
            XCTAssertFalse(
                multi.contains(where: { candidate in
                    candidate.contains("○") || candidate.contains("→") || candidate.contains("↓")
                }),
                "reading=\(reading) multi=\(multi)"
            )
        }
        // 踊り字も同様(どう スパンに 々 が立たない)
        let odoriji = converter.multiClauseCandidates(for: "どうしてもいく", systemCandidateMode: .surface)
        XCTAssertFalse(odoriji.contains(where: { $0.contains("々") }), "multi=\(odoriji)")
    }

    // 実LM回帰: なぜ のかな正書curated供給。LM はかな優位(なぜ5289<何故6391)だが、
    // 最良の なぜ+それ+が(全かな)がエコー抑制に捨てられ 何故それが が先頭化していた
    // (それぞれ/うっかり と同型)。
    func testRegressionRealLMNazeSoregaPrefersKana() throws {
        try prepareRealLMDictionary()
        // 実機の追加語彙(misc.plist 由来はテストバンドルに載らない)を store 側で再現
        converter.store.addUserEntry(reading: "なぜ", candidate: "なぜ")

        let multi = converter.multiClauseCandidates(for: "なぜそれが", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "なぜそれが", "multi=\(multi)")
        // 何故それが は変種delta上限(なぜ→それ の bigram 優位)で落ちる。単独 なぜ では
        // 何故 が引き続き候補に出ることを確認する。
        let single = converter.candidates(for: "なぜ", limit: 10, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "なぜ", "single=\(single)")
        XCTAssertTrue(single.contains("何故"), "single=\(single)")
    }

    // 実LM回帰: きがした→気がした。気が+する はサ変名詞と見なされず供給経路が無い一方、
    // 帰臥/起臥(2字漢語)はサ変推論で 帰臥した 等を作り先頭化していた。気が 単独の curated は
    // 危害(きがい)/着替え(きがえ)/気軽(きがる)/飢餓 を分断するため、気がする+頻出形の
    // 句登録(いただきました方式)で供給する。
    func testRegressionRealLMKigashitaPrefersKiga() throws {
        try prepareRealLMDictionary()
        converter.store.addUserEntry(reading: "きがする", candidate: "気がする")
        converter.store.addUserEntry(reading: "きがした", candidate: "気がした")
        converter.store.addUserEntry(reading: "きがして", candidate: "気がして")

        let shita = converter.candidates(for: "きがした", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(shita.first, "気がした", "single=\(shita)")
        let suru = converter.candidates(for: "きがする", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(suru.first, "気がする", "single=\(suru)")
        let node = converter.multiClauseCandidates(for: "きがしたので", systemCandidateMode: .surface)
        XCTAssertEqual(node.first, "気がしたので", "multi=\(node)")
        // 気が を丸ごと curated にしていないことの防波堤: 着替え/気軽 の分断が起きない
        let kigae = converter.multiClauseCandidates(for: "きがえをもって", systemCandidateMode: .surface)
        XCTAssertEqual(kigae.first, "着替えをもって", "multi=\(kigae)")
        let kigaru = converter.multiClauseCandidates(for: "きがるにどうぞ", systemCandidateMode: .surface)
        XCTAssertEqual(kigaru.first, "気軽にどうぞ", "multi=\(kigaru)")
    }

    // 実LM回帰テストの共通セットアップ: 開発機の tmp sqlite(実辞書+連文節LM)を
    // app group コンテナへ複製する。tmp が無い環境では XCTSkip(実LM依存のため)。
    // 実LM回帰: 受身+たい 願望連鎖(られたくない/れたくない/されたくない)。プレーン語幹の
    // たい系はあったが受身を挟む形が未定義で、おくられたくないね→置くられたくないね/
    // 奥られたくないね(かな断片合成)等に全長を取られていた(供給欠落型)。
    func testRegressionRealLMPassiveTaiChainsDerive() throws {
        try prepareRealLMDictionary()

        let multi = converter.multiClauseCandidates(for: "おくられたくないね", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "送られたくないね", "multi=\(multi)")
        XCTAssertFalse(multi.contains(where: { $0.contains("置く") || $0.contains("奥") }), "multi=\(multi)")

        let cases: [(reading: String, expected: String)] = [
            ("おくられたくない", "送られたくない"),
            ("みられたくない", "見られたくない")
        ]
        for testCase in cases {
            let single = converter.candidates(for: testCase.reading, limit: 8, systemCandidateMode: .surface)
            XCTAssertEqual(single.first, testCase.expected, "reading=\(testCase.reading) single=\(single)")
        }

        // 長い読みは単文節経路が空になり連文節が担当する(され連鎖の検証)。
        let sareta = converter.multiClauseCandidates(for: "そうしんされたくない", systemCandidateMode: .surface)
        XCTAssertEqual(sareta.first, "送信されたくない", "multi=\(sareta)")
    }

    // 実LM回帰: なつは→夏は。読み なつは の辞書エントリは全てレア名前収穫
    // (夏羽/捺葉/奈津羽…wc10000)で、合成の 夏は が9番目に沈んでいた(水は と同型)。
    // per-word curated ではなく収穫底値帯(wc>=10000)の一般降格で直す(構造対応)。
    func testRegressionRealLMNatsuhaPrefersNatsuWa() throws {
        try prepareRealLMDictionary()

        let single = converter.candidates(for: "なつは", limit: 24, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "夏は", "single=\(single)")
        // 名前群は消さず後方(合成群の後ろ)に残る
        XCTAssertTrue(single.contains("夏羽"), "single=\(single)")
    }

    // 実LM回帰: ゆずか→柚花/柚香。柚花 は辞書に無く合成経由のみ、柚香(rank0)は wc11000 で
    // 名前収穫群に埋もれていた。seed 供給+seed の連文節ラティス搭載+seed の収穫底値降格
    // 免除の3点で、単独・敬称合成(さん)とも 柚花→柚香 を先頭に固定する。
    func testRegressionRealLMYuzukaPrefersYuzuka() throws {
        try prepareRealLMDictionary()

        let single = converter.candidates(for: "ゆずか", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(2)), ["柚花", "柚香"], "single=\(single)")

        let multi = converter.multiClauseCandidates(for: "ゆずかさん", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "柚花さん", "multi=\(multi)")
        XCTAssertEqual(multi.dropFirst().first, "柚香さん", "multi=\(multi)")
    }

    // 実LM回帰: なんじ→何時。何時 は Sudachi 正規化で いつ 読みのみ登録され、なんじ 読みは
    // 汝/南寺/名前収穫だけだった(供給欠落型)。seed で供給(連文節ラティスにも a2 で載る)。
    func testRegressionRealLMNanjiPrefersNanji() throws {
        try prepareRealLMDictionary()

        let single = converter.candidates(for: "なんじ", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "何時", "single=\(single)")

        // いま/今 はどちらも正当なので 何時 の部分だけ固定する
        let multi = converter.multiClauseCandidates(for: "いまなんじですか", systemCandidateMode: .surface)
        XCTAssertTrue(multi.first?.contains("何時ですか") == true, "multi=\(multi)")
    }

    // 実LM回帰: あしたは→明日は。朝(あした=古語読み)の表層が あさ 読みの uni(4453)を
    // 借用して 明日(5910)に連文節で勝っていた(読み跨ぎ)。朝 は候補として温存(ユーザ意向)
    // したいので抑制せず、明日 を curated で先頭固定。晨(古語)/アシタ(カタカナ収穫)は抑制。
    func testRegressionRealLMAshitahaPrefersAshita() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["あした": ["晨", "アシタ"]])
        converter.store.addUserEntry(reading: "あした", candidate: "明日")

        let multi = converter.multiClauseCandidates(for: "あしたは", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "明日は", "multi=\(multi)")
        // 朝は は変種として残ってよい(先頭でなければ問題ない)
        XCTAssertFalse(multi.contains(where: { $0.contains("晨") || $0.contains("アシタ") }), "multi=\(multi)")

        let single = converter.candidates(for: "あした", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "明日", "single=\(single)")
        XCTAssertTrue(single.contains("朝"), "朝は候補として温存 single=\(single)")

        // 巻き添え確認: あしたば(明日葉)が 明日+ば に分断されない
        let ashitaba = converter.candidates(for: "あしたば", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(ashitaba.first, "明日葉", "single=\(ashitaba)")
    }

    // 実LM回帰: いいね→いいね が先頭、言い値 が2番目。dict の読み いいね は 言い値 のみで、
    // かな いいね は uni 未収録の供給欠落。イイ/唯々/いゝ/易々+ね の合成が先行していた。
    // イイね/いゝね(今どき流行らない書き方)は読み直接ペアで抑制。
    func testRegressionRealLMIinePrefersKana() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["いいね": ["イイね", "いゝね"]])
        converter.store.addUserEntry(reading: "いいね", candidate: "いいね")

        let single = converter.candidates(for: "いいね", limit: 10, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(2)), ["いいね", "言い値"], "single=\(single)")
        XCTAssertFalse(single.contains("イイね"), "single=\(single)")
        XCTAssertFalse(single.contains("いゝね"), "single=\(single)")
    }

    // 実LM回帰: 否定テ形 なくて/なくても の供給。願望否定テ(たくなくて)だけあって素の形が
    // 全クラス未定義で、いかなくて→いか+なくて/凧なくて 等の断片合成に全長を取られ、
    // いかなくていいのかな はかなエコー1つだけになっていた(供給欠落型)。
    // しんぱい は inflection_classes のメタデータ穴(親拝/進拝 のみ suru 登録で 心配 が
    // 未登録)のため、心配する の句登録+親拝/進拝 の抑制も併せて検証する。
    func testRegressionRealLMNegativeTeFormsDerive() throws {
        try prepareRealLMDictionary()
        converter.store.addUserEntry(reading: "しんぱいする", candidate: "心配する")
        try injectSuppression(["しんぱい": ["親拝", "進拝"]])

        let ikanakute = converter.candidates(for: "いかなくて", limit: 8, systemCandidateMode: .surface)
        // 2089: 単独の いかなくて は本動詞用途が主のため 行かなくて を先頭(seed)、かな は2番目
        XCTAssertEqual(Array(ikanakute.prefix(2)), ["行かなくて", "いかなくて"], "single=\(ikanakute)")

        let multi = converter.multiClauseCandidates(for: "いかなくていいのかな", systemCandidateMode: .surface)
        XCTAssertTrue(multi.contains("行かなくていいのかな"), "multi=\(multi)")
        XCTAssertTrue(multi.count >= 2, "かなエコー1つだけに戻らないこと multi=\(multi)")

        let tabe = converter.candidates(for: "たべなくても", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(tabe.first, "食べなくても", "single=\(tabe)")

        let shinpai = converter.candidates(for: "しんぱいしなくても", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(shinpai.first, "心配しなくても", "single=\(shinpai)")
    }

    // 実LM回帰: あかくなりにくいはず→赤くなりにくいはず。はず(かな正書の形式名詞)が
    // 床上げ免除リスト外で wc6777 に床上げされ、bigram は→頭(4675、あたま文脈の読み跨ぎ
    // 借用が床を素通り)の は+頭(ず) に負けていた。はず を免除+頭(ず) を bigram 借用遮断へ。
    func testRegressionRealLMHazuPrefersKana() throws {
        try prepareRealLMDictionary()

        let multi = converter.multiClauseCandidates(for: "あかくなりにくいはず", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "赤くなりにくいはず", "multi=\(multi)")
        XCTAssertFalse(multi.contains(where: { $0.contains("頭") }), "multi=\(multi)")

        // はず 単独もかな先頭を確認
        let single = converter.candidates(for: "はず", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "はず", "single=\(single)")
    }

    // 実LM回帰: Sudachi 生エスケープのデコード(かぶしきがいしゃ→\u0028株\u0029 が
    // (株) と表示される)と、會社(旧字体)の抑制(かぶしきかいしゃ→株式會社 合成の是正)。
    func testRegressionRealLMSudachiEscapesDecoded() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["かいしゃ": ["會社"]])

        let kabu = converter.candidates(for: "かぶしきがいしゃ", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(kabu.prefix(2)), ["株式会社", "(株)"], "single=\(kabu)")
        XCTAssertFalse(kabu.contains(where: { $0.contains("\\u00") }), "single=\(kabu)")

        let kaisha = converter.candidates(for: "かぶしきかいしゃ", limit: 8, systemCandidateMode: .surface)
        XCTAssertFalse(kaisha.contains(where: { $0.contains("會") }), "single=\(kaisha)")
    }

    // 実LM回帰: つぎは→次は。丸ごと語の 継ぎ歯/継ぎ端(歯科用語、wc7864 の正規語で
    // 収穫底値降格の対象外)が合成の 次+は より先に並んでいた(なかの/夏は の正規語版)。
    func testRegressionRealLMTsugihaPrefersTsugiWa() throws {
        try prepareRealLMDictionary()

        let single = converter.candidates(for: "つぎは", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "次は", "single=\(single)")
        XCTAssertTrue(single.contains("継ぎ歯"), "継ぎ歯は温存 single=\(single)")
    }

    // 実LM回帰: さっきのは/さっきは/さっき のかな先頭化。さっき はかな正書の口語で、
    // かな識別curatedが無いと全かな best がエコー抑制に捨てられ 殺気のは/削器のは/箚記のは
    // (レア語)が繰り上がっていた(それぞれ/うっかり と同型)。
    func testRegressionRealLMSakkiPrefersKana() throws {
        try prepareRealLMDictionary()
        converter.store.addUserEntry(reading: "さっき", candidate: "さっき")
        // 実機の抑制状態を再現(者(は) は suppr.plist で抑制済み)
        try injectSuppression(["は": ["者"]])

        for input in ["さっきのは", "さっきは"] {
            let multi = converter.multiClauseCandidates(for: input, systemCandidateMode: .surface)
            XCTAssertEqual(multi.first, input, "multi=\(multi)")
        }

        let single = converter.candidates(for: "さっき", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "さっき", "single=\(single)")
    }

    // 実LM回帰: いかなくて の並び(行かなくて 先頭)。基底 いく のかなLM優遇(〜ていく 由来)で
    // かな が先頭化し、名詞+なくて 合成(イカなくて、bfs帯1040>派生980)が2位に居た。
    // seed いかなくて=[行かなくて]+読み2文字以下の名詞語幹への なくて 合成を動詞要求で遮断。
    // ない形容詞(勿体ない/申し訳ない=辞書に基底が無く名詞+なくて合成が唯一の供給)は
    // 語幹3文字以上なので影響しないことも固定する。
    func testRegressionRealLMIkanakuteOrdering() throws {
        try prepareRealLMDictionary()
        converter.store.addUserEntry(reading: "うまく", candidate: "うまく")

        // イく/イク(カタカナ交ぜ書き族、suppr済)の派生 イかなくて が出ないことも固定
        try injectSuppression(["いく": ["イく", "イク"]])
        let single = converter.candidates(for: "いかなくて", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "行かなくて", "single=\(single)")
        XCTAssertFalse(single.contains("イカなくて"), "single=\(single)")
        XCTAssertFalse(single.contains("イかなくて"), "single=\(single)")

        // 文脈があるときは かな いかなくて が勝つ(うまくいく はかなが正書)
        let umaku = converter.multiClauseCandidates(for: "うまくいかなくて", systemCandidateMode: .surface)
        XCTAssertEqual(umaku.first, "うまくいかなくて", "multi=\(umaku)")

        // ない形容詞の合成供給は温存
        let mottainai = converter.candidates(for: "もったいなくて", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(mottainai.first, "もったいなくて", "single=\(mottainai)")
        let moushiwake = converter.candidates(for: "もうしわけなくて", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(moushiwake.first, "申し訳なくて", "single=\(moushiwake)")
    }

    // 実LM回帰: おおいとはげるよ→多いと禿げるよ。禿げる(dict rank0)は uni 未収録で
    // 連文節ノードが 8700 になり、は+ゲル(uni6785)の断片連結に負けていた。curated で供給。
    func testRegressionRealLMHageruPrefersHageru() throws {
        try prepareRealLMDictionary()
        converter.store.addUserEntry(reading: "はげる", candidate: "禿げる")

        let multi = converter.multiClauseCandidates(for: "おおいとはげるよ", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "多いと禿げるよ", "multi=\(multi)")
        XCTAssertFalse(multi.contains(where: { $0.contains("ゲル") }), "multi=\(multi)")
    }

    // 実LM回帰: おもいのね→重いのね。説明の のね は用言直後が主用途だが、表層末尾の い では
    // 名詞 思い と形容詞 重い を区別できないため、辞書形述語フラグ(inflection_classes)で
    // ゲートした単位ノードクランプを使う。名詞+の(思いの外)は従来経路のまま。
    func testRegressionRealLMOmoinonePrefersOmoi() throws {
        try prepareRealLMDictionary()

        let multi = converter.multiClauseCandidates(for: "おもいのね", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "重いのね", "multi=\(multi)")

        let takai = converter.multiClauseCandidates(for: "たかいのよ", systemCandidateMode: .surface)
        XCTAssertEqual(takai.first, "高いのよ", "multi=\(takai)")

        // 名詞+の の慣用は歪めない(丸ごと辞書語のため連文節は単一経路へ委譲=[]が正常)
        let hokaMulti = converter.multiClauseCandidates(for: "おもいのほか", systemCandidateMode: .surface)
        XCTAssertFalse(hokaMulti.contains(where: { $0.contains("重い") }), "multi=\(hokaMulti)")
        let hoka = converter.candidates(for: "おもいのほか", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(hoka.first, "思いの外", "single=\(hoka)")
    }

    // 実LM回帰: りょうが→量が/凌駕。合成の 量+が が丸ごと語(凌駕/リョウガ/楞加)より後ろに
    // 沈んでいた。seed で 量が→凌駕 を固定。りょうがする はサ変推論が 凌駕 からのみ成立する
    // ため 凌駕する が先頭のまま。リョウガ/リョウ(カタカナ人名収穫)は suppr。
    func testRegressionRealLMRyougaOrdering() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["りょうが": ["リョウガ"], "りょう": ["リョウ"]])

        let single = converter.candidates(for: "りょうが", limit: 10, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(2)), ["量が", "凌駕"], "single=\(single)")
        XCTAssertFalse(single.contains("リョウガ"), "single=\(single)")

        let suru = converter.candidates(for: "りょうがする", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(suru.first, "凌駕する", "single=\(suru)")
    }

    // 実LM回帰: あめのひも→雨の日も。EOS unigram(1619)による フォールバック(2119)が
    // 観測済みの も→EOS(3052)より安い逆転構造で 雨の紐 が僅差勝ちしていた。EOS床の
    // 一般化は 感じ 等のカジュアル語彙(Wikipedia文末に出ない)を痛めるため不成立と検証
    // 済みで、句 seed で対応。文中(あめのひもある)は LM で正しく 雨の日も が勝つ。
    func testRegressionRealLMAmenohimoPrefersHimo() throws {
        try prepareRealLMDictionary()

        let single = converter.candidates(for: "あめのひも", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "雨の日も", "single=\(single)")
        XCTAssertTrue(single.contains("雨の紐"), "雨の紐は次点で温存 single=\(single)")

        let multi = converter.multiClauseCandidates(for: "あめのひもある", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "雨の日もある", "multi=\(multi)")
    }

    // 実LM回帰: かな正書の代名詞(こいつ/そいつ/あいつ)の連文節変種抑止。単文節の候補列
    // には 此奴/コイツ を残しつつ、連文節では旧表記・カタカナの差し替え変種を出さない。
    func testRegressionRealLMKoitsuVariantsStayKanaInMultiClause() throws {
        try prepareRealLMDictionary()

        for input in ["こいつはすごい", "あいつがきた"] {
            let multi = converter.multiClauseCandidates(for: input, systemCandidateMode: .surface)
            XCTAssertFalse(
                multi.contains(where: { $0.contains("奴") || $0.contains("コイツ") || $0.contains("アイツ") }),
                "multi=\(multi)"
            )
        }

        // 単文節の候補列は無傷(単独入力では選択可能)
        let single = converter.candidates(for: "こいつ", limit: 6, systemCandidateMode: .surface)
        XCTAssertTrue(single.contains("此奴"), "single=\(single)")
        XCTAssertTrue(single.contains("コイツ"), "single=\(single)")
    }

    // 実LM回帰: いかの の並び。dict いか は イカ0/凧1/いか2/… の順で、頻出の 以下 が沈み、
    // 方言読みの 凧(いかのぼり)とかな いか が上位に居た。seed いか の列挙(6件)で
    // 以下 を先頭、凧/かな を後方へ(凧 は正規の方言読みなので抑制しない)。
    func testRegressionRealLMIkanoOrdering() throws {
        try prepareRealLMDictionary()

        let single = converter.candidates(for: "いかの", limit: 12, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "以下の", "single=\(single)")
        if let takoIndex = single.firstIndex(of: "凧の") {
            XCTAssertGreaterThanOrEqual(takoIndex, 6, "single=\(single)")
        }
        if let kanaIndex = single.firstIndex(of: "いかの") {
            XCTAssertGreaterThanOrEqual(kanaIndex, 6, "single=\(single)")
        }

        // いかが(如何)は自前の辞書エントリが先行し無傷
        let ikaga = converter.candidates(for: "いかが", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(ikaga.first, "いかが", "single=\(ikaga)")
    }

    // 実LM回帰: かしだすだけ→貸し出すだけ。述語直後の だけ に 抱け(命令形は述語に接続
    // しない)/竹(連体修飾の後では連濁しない)が並んでいた。形式名詞かな優先ルールに だけ を
    // 追加し、ゲートを辞書形述語ノードにも拡張。
    func testRegressionRealLMKashidasuDakePrefersKana() throws {
        try prepareRealLMDictionary()

        let multi = converter.multiClauseCandidates(for: "かしだすだけ", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "貸し出すだけ", "multi=\(multi)")
        XCTAssertFalse(multi.contains(where: { $0.contains("抱け") || $0.contains("竹") }), "multi=\(multi)")
    }

    // 実LM回帰: りゅうきゅう→琉球。ryukyu.plist がビルド時に辞書へマージされ、plist の並び
    // (瑠求→留求→流求→琉球)がそのまま rank 0-3 になっていた。seed の列挙で 琉球 を先頭、
    // 歴史文書表記(瑠求/留求/流求)を末尾へ(抑制はしない)。
    func testRegressionRealLMRyukyuPrefersRyukyu() throws {
        try prepareRealLMDictionary()

        let single = converter.candidates(for: "りゅうきゅう", limit: 10, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "琉球", "single=\(single)")
        XCTAssertTrue(single.contains("瑠求"), "歴史表記は末尾に温存 single=\(single)")
        if let ruIndex = single.firstIndex(of: "瑠求"),
            let kanaIndex = single.firstIndex(of: "りゅうきゅう") {
            XCTAssertGreaterThan(ruIndex, kanaIndex, "歴史表記はかなより後ろ single=\(single)")
        }
        // 合成・連文節には混じらない(exactReadingOnly)
        let multi = converter.multiClauseCandidates(for: "りゅうきゅうの", systemCandidateMode: .surface)
        XCTAssertFalse(multi.contains(where: { $0.contains("瑠求") || $0.contains("留求") || $0.contains("流求") }), "multi=\(multi)")
    }

    // 実LM回帰: ひさしぶり→久しぶり。dict は 久し振り rank0 だが LM は 久しぶり のみ収録
    // (現代の主流表記)。seed で先頭固定(連文節 ひさしぶりに にも効く)。
    func testRegressionRealLMHisashiburiPrefersBuri() throws {
        try prepareRealLMDictionary()

        let single = converter.candidates(for: "ひさしぶり", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "久しぶり", "single=\(single)")

        let multi = converter.multiClauseCandidates(for: "ひさしぶりにあった", systemCandidateMode: .surface)
        XCTAssertTrue(multi.first?.hasPrefix("久しぶりに") == true, "multi=\(multi)")
    }

    // 実LM回帰: してるな→してるな。して が LM 未収録で弱く、してるな だけが して+ルナ
    // (uni6239+EOS未観測フォールバック逆転)に区切りを取られていた(やってるな/みてるな は
    // 従来から正常)。してる をかな正書 curated(misc.plist)で供給。
    func testRegressionRealLMShiterunaPrefersKana() throws {
        try prepareRealLMDictionary()
        converter.store.addUserEntry(reading: "してる", candidate: "してる")

        let multi = converter.multiClauseCandidates(for: "してるな", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "してるな", "multi=\(multi)")
        XCTAssertFalse(multi.contains(where: { $0.contains("ルナ") || $0.contains("月") || $0.contains("流南") }), "multi=\(multi)")

        // 同族の既存正常形が壊れないこと
        let yatteru = converter.multiClauseCandidates(for: "やってるな", systemCandidateMode: .surface)
        XCTAssertEqual(yatteru.first, "やってるな", "multi=\(yatteru)")
    }

    private func prepareRealLMDictionary() throws {
        let fileManager = FileManager.default
        let source = URL(fileURLWithPath: "/Users/kusakabe/Git/ecritu/tmp/kana_kanji_dictionary.sqlite")
        guard fileManager.fileExists(atPath: source.path) else {
            throw XCTSkip("real LM sqlite not available on this machine")
        }
        guard let container = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: defaultsSuiteName
        ) else {
            throw XCTSkip("no app group container in this environment")
        }
        try fileManager.createDirectory(at: container, withIntermediateDirectories: true)
        let destination = container.appendingPathComponent("kana_kanji_dictionary.sqlite")
        if !fileManager.fileExists(atPath: destination.path) {
            try fileManager.copyItem(at: source, to: destination)
        }
    }

    // 実機の抑制状態(suppr.plist 由来はテストバンドルに載らない)を defaults 側で再現する。
    private func injectSuppression(_ suppression: [String: [String]]) throws {
        let suppressionData = try JSONEncoder().encode(suppression)
        UserDefaults(suiteName: defaultsSuiteName)?.set(suppressionData, forKey: "ÉcrituSuppr_Vocab")
    }

    private func clearSuite(_ suiteName: String) {
        guard !suiteName.isEmpty else {
            return
        }

        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }
}
