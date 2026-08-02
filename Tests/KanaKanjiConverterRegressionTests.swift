import SwiftUI
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

    // 旧仕様(行め 固定先頭)は première…設定(2428)に置き換え。既定=漢字『目』先、
    // オフ=ひらがな『め』先。
    func testRegressionOrdinalMeFallbackFollowsOrdinalSetting() {
        let kanjiFirst = converter.candidates(
            for: "10ぎょうめ",
            limit: 24,
            systemCandidateMode: .surface
        )
        XCTAssertEqual(kanjiFirst.first, "行目", "candidates=\(kanjiFirst)")

        converter.setOrdinalMeKanjiPreferred(false)
        let meFirst = converter.candidates(
            for: "10ぎょうめ",
            limit: 24,
            systemCandidateMode: .surface
        )
        XCTAssertEqual(meFirst.first, "行め", "candidates=\(meFirst)")
        converter.setOrdinalMeKanjiPreferred(true)
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

        // 単文節: コイツ は既定(抑制)で消える(2350〜)。リスト後方モードでは復帰する
        let single = converter.candidates(for: "こいつ", limit: 6, systemCandidateMode: .surface)
        XCTAssertTrue(single.contains("此奴"), "single=\(single)")
        XCTAssertFalse(single.contains("コイツ"), "single=\(single)")
        converter.setKatakanaEmphasisCandidateMode(.demote)
        let demoted = converter.candidates(for: "こいつ", limit: 12, systemCandidateMode: .surface)
        XCTAssertTrue(demoted.contains("コイツ"), "demoted=\(demoted)")
        converter.setKatakanaEmphasisCandidateMode(.suppress)
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

    // 実LM回帰: じつようかされんな→実用化されんな。受身+ん(口語否定縮約)ルールが未定義で
    // されん ノード自体が無く、さ+廉梛(名前収穫 wc10000)の断片に全長を取られていた
    // (実用化されん が動いて見えたのは さ+れん 断片の見かけ上の正解)。ルール追加+
    // 収穫底値(wc>=10000)ノードの連文節降格(8700→9500、seed 掲載語は免除)で是正。
    func testRegressionRealLMSarennaPrefersSaren() throws {
        try prepareRealLMDictionary()

        let multi = converter.multiClauseCandidates(for: "じつようかされんな", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "実用化されんな", "multi=\(multi)")

        let shiranna = converter.multiClauseCandidates(for: "しらんな", systemCandidateMode: .surface)
        XCTAssertEqual(shiranna.first, "知らんな", "multi=\(shiranna)")
    }

    // 実LM回帰: かってほしい に 勝ってほしい が出る。かって の派生で 酤う/支う/交う
    // (古語・レア)が 勝って(かつ由来、う規則の後に列挙される)を語幹上限の外へ押し出して
    // いた。3語を suppr して 勝って を上限内(4位)へ。
    func testRegressionRealLMKattehoshiiIncludesKatte() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["かう": ["酤う", "支う", "交う"]])

        let multi = converter.multiClauseCandidates(for: "かってほしい", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "買ってほしい", "multi=\(multi)")
        XCTAssertTrue(multi.contains("勝ってほしい"), "multi=\(multi)")
    }

    // 実LM回帰: ぎんこう から ギンコウ(銀行のカタカナ表記ゆれ収穫、wc同値3295)を抑制。
    func testRegressionRealLMGinkouSuppressesKatakana() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["ぎんこう": ["ギンコウ"]])

        let single = converter.candidates(for: "ぎんこう", limit: 10, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "銀行", "single=\(single)")
        XCTAssertFalse(single.contains("ギンコウ"), "single=\(single)")
    }

    // 実LM回帰: せなかがわ→背中側。sacoche の なか川(店名、curated 1500)が せ+なか川 の
    // 分断を作り、背中+側(bigram 1828 実在)が106差で負けていた(実機相当の全語彙注入で
    // のみ再現)。分断される側の 背中側 も curated 化(ろーま事件の処方箋)。
    func testRegressionRealLMSenakagawaPrefersSenakaGawa() throws {
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
        let single = freshConverter.candidates(for: "せなかがわ", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "背中側", "single=\(single)")
        let multi = freshConverter.multiClauseCandidates(for: "せなかがわ", systemCandidateMode: .surface)
        XCTAssertFalse(multi.contains(where: { $0.contains("セ") }), "multi=\(multi)")
    }

    // よん系の活用派生は基底の辞書順が 呼ぶ族→読む族 で固定され、代表の 読んだ/読んでない
    // が6番手に沈んでいた(+連文節は a2 seed ノードの先着 dedupe が b2 の安い活用OOV
    // コピーを潰し 本を喚んだ が先頭化)。seed の先頭2固定と a2 の派生フラグで是正。
    func testRegressionRealLMYondaFamilyPrefersYomuThenYobu() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["よん": ["霊"]])
        for input in ["よんだ", "よんでる", "よんでない"] {
            let tail = input.dropFirst()
            let single = converter.candidates(for: input, limit: 8, systemCandidateMode: .surface)
            XCTAssertEqual(Array(single.prefix(2)), ["読" + tail, "呼" + tail], "single=\(single)")
        }
        let multi = converter.multiClauseCandidates(for: "ほんをよんだ", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "本を読んだ", "multi=\(multi)")
    }

    // なんの の dict は固有名収穫のみ(ナンノ=南野陽子等の愛称/南埜=レア姓)で、頻出の
    // 何の が沈んでいた。さらに読み なん の dict rank5 に三点リーダ装飾の な…ん が居て
    // な…んの 等のジャンク合成を作っていた(装飾フィルタに…ルールを追加して一般に遮断)。
    func testRegressionRealLMNannoPrefersNanNo() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["なんの": ["ナンノ"]])
        let single = converter.candidates(for: "なんの", limit: 10, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(3)), ["何の", "南の", "難の"], "single=\(single)")
        XCTAssertFalse(single.contains(where: { $0.contains("…") }), "single=\(single)")
        let multi = converter.multiClauseCandidates(for: "なんのはなし", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "何の話", "multi=\(multi)")
    }

    // こと(形式名詞)はかなが正書で LM も かな を選ぶ(uni こと2879 vs 事4381)が、
    // 全かなエコー抑制が最良経路(の+こと+です)を捨てて の事です が繰り上がっていた。
    // 経路の全ノードが辞書語(素通り無し)の全かなは LM の選択なので抑制しない。
    func testRegressionRealLMNokotodesuPrefersKanaKoto() throws {
        try prepareRealLMDictionary()
        let multi = converter.multiClauseCandidates(for: "のことです", systemCandidateMode: .surface)
        XCTAssertEqual(Array(multi.prefix(2)), ["のことです", "の事です"], "multi=\(multi)")
        let kare = converter.multiClauseCandidates(for: "かれのことです", systemCandidateMode: .surface)
        XCTAssertEqual(kare.first, "彼のことです", "multi=\(kare)")
    }

    // います はかなが正書(そこにいます 等)だが、①かな いる が inflection_classes で
    // godan-ru のみ登録(要る/入る の巻き添え)で います が導出されず、②連文節では
    // (b) word_costs の高コスト収穫かな(います wc13367→底値9500)が先着 dedupe で
    // (b2) の安い活用コピー(7200)を潰し、居ます が系統的に勝っていた。
    // 補助クラス表(いる=一段追加)+かな識別の派生フラグ合流で是正。
    // 坐す/在す(古語の敬語動詞)は suppr+exactReadingOnlySeed の末尾供給へ移動。
    func testRegressionRealLMImasuPrefersKana() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["います": ["坐す", "在す"]])
        let single = converter.candidates(for: "います", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(2)), ["います", "居ます"], "single=\(single)")
        for input in ["いますよね", "そこにいます"] {
            let multi = converter.multiClauseCandidates(for: input, systemCandidateMode: .surface)
            XCTAssertEqual(multi.first, input, "multi=\(multi)")
            XCTAssertEqual(multi.dropFirst().first?.contains("居ます"), true, "multi=\(multi)")
        }
    }

    // 連濁収穫フィルタ: 墓(ばか)/蓋・二(ぶた)/口(ぐち)等、Sudachi が複合語内の連濁読みで
    // 収穫した単漢字は単独・合成に出さない(連濁は複合語境界の現象)。判定は「清音化した
    // 読みに同じ表層がより安く実在」— 濁側が主の音読ペア(分=ぶん、台=だい)は誤爆しない。
    func testRegressionRealLMRendakuHarvestFiltered() throws {
        try prepareRealLMDictionary()
        let multi = converter.multiClauseCandidates(for: "ばかすぎる", systemCandidateMode: .surface)
        XCTAssertFalse(multi.contains(where: { $0.contains("墓") }), "multi=\(multi)")
        XCTAssertEqual(multi.first, "バカすぎる", "multi=\(multi)")
        let buta = converter.candidates(for: "ぶた", limit: 8, systemCandidateMode: .surface)
        XCTAssertFalse(buta.contains("蓋"), "buta=\(buta)")
        XCTAssertFalse(buta.contains("二"), "buta=\(buta)")
        XCTAssertTrue(buta.contains("豚"), "buta=\(buta)")
        // 濁音始まりでも正当な読み(音読で濁側が主/清音側に同表層なし)は温存
        let zou = converter.candidates(for: "ぞう", limit: 12, systemCandidateMode: .surface)
        XCTAssertTrue(zou.contains("象"), "zou=\(zou)")
        XCTAssertTrue(zou.contains("蔵"), "zou=\(zou)")
        let bun = converter.candidates(for: "ぶん", limit: 8, systemCandidateMode: .surface)
        XCTAssertTrue(bun.contains("分"), "bun=\(bun)")
    }

    // ここでは: 連文節の最良経路(ここ+では)が全かな=入力一致でエコー抑制され、変種の
    // 個々では が繰り上がっていた。格助詞/複合助詞はかなが唯一の正書なので、文末がかな
    // 助詞の全かなは抑制しない(免除枠組みへ追加)。踊り字 こゝ とレア人名収穫(小恋 等
    // rank13-23)は suppr+exactReadingOnlySeed(ここ 完全一致時のみ末尾)へ。
    func testRegressionRealLMKokodewaPrefersKana() throws {
        try prepareRealLMDictionary()
        try injectSuppression([
            "ここ": ["こゝ", "小恋", "小瑚", "小虹", "小香", "幸呼", "幸恋", "心湖", "湖々", "湖紅", "琥々", "瑚々"]
        ])
        let multi = converter.multiClauseCandidates(for: "ここでは", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "ここでは", "multi=\(multi)")
        let single = converter.candidates(for: "ここでは", limit: 12, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "ここでは", "single=\(single)")
        XCTAssertFalse(single.contains(where: { $0.contains("こゝ") || $0.contains("小恋") }), "single=\(single)")
        // レア人名は ここ 完全一致時のみ末尾に残る(exactReadingOnlySeed)
        let koko = converter.candidates(for: "ここ", limit: 40, systemCandidateMode: .surface)
        XCTAssertTrue(koko.contains("小恋"), "koko=\(koko)")
        XCTAssertEqual(koko.first, "ここ", "koko=\(koko)")
    }

    // ただの(連体の 唯の)はかなが正書だが、dict はレア姓収穫のみ(只野/タダノ/但野/
    // 哆唾乃 等)でかな ただの が無く、姓群が先頭を占めていた。かな正書維持型 seed で是正。
    func testRegressionRealLMTadanoPrefersKana() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "ただの", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(2)), ["ただの", "只野"], "single=\(single)")
        let multi = converter.multiClauseCandidates(for: "ただのかぜ", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first?.hasPrefix("ただの"), true, "multi=\(multi)")
    }

    // ひらがな: dict は 平仮名0/平がな1/ひらがな2 で交ぜ書きが かな に先行し、合成の
    // 二重加点(平がな=辞書+postfix)が 平仮名 をも脅かす。seed=[平仮名, ひらがな]+
    // seed内相対順の正規化(スコア再割当)で 平仮名→ひらがな の順に固定。合成にも効く。
    // 者(は)は複合語内読みの収穫で、連文節の の+者 が のは を食うため suppr。
    func testRegressionRealLMHiraganaKanaSecond() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["は": ["者"]])
        let single = converter.candidates(for: "ひらがな", limit: 8, systemCandidateMode: .surface)
        // 平がな は交ぜ書きクラス抑制(既定)で候補から消える(2350〜)
        XCTAssertEqual(Array(single.prefix(2)), ["平仮名", "ひらがな"], "single=\(single)")
        let composed = converter.candidates(for: "ひらがなのは", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(composed.prefix(2)), ["平仮名のは", "ひらがなのは"], "composed=\(composed)")
        let multi = converter.multiClauseCandidates(for: "ひらがなのは", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "平仮名のは", "multi=\(multi)")
        XCTAssertFalse(multi.contains(where: { $0.contains("者") }), "multi=\(multi)")
    }

    // Wikipedia LM は 昨日(uni 6869)を 機能(4237)より大幅に過小評価し、昨日→は/の の
    // 実 bigram 優位すら飲み込む(きのうは→機能は)。会話的時相名詞の unigram キャップ
    // (4300)で底上げ。観測 bigram(機能→が1112)より弱いので きのうが→機能が は保たれる。
    func testRegressionRealLMKinouPrefersYesterdayInContext() throws {
        try prepareRealLMDictionary()
        for (input, expectedFirst) in [
            ("きのうねあがりしたが", "昨日値上がりしたが"),
            ("きのうは", "昨日は"),
            ("きのうの", "昨日の"),
            ("きのうから", "昨日から"),
            ("きのうが", "機能が")
        ] {
            let multi = converter.multiClauseCandidates(for: input, systemCandidateMode: .surface)
            XCTAssertEqual(multi.first, expectedFirst, "input=\(input) multi=\(multi)")
        }
    }

    // 日(び)ノード(曜日の連濁読み収穫)が surface 単位 LM の あの→日 1272(あの日=
    // あのひ の実績)を読み跨ぎ借用し、あの+日+神野(じんの=EOSフォールバック逸得)が
    // あの+美人+の を逆転していた。日(び) を bigram 借用遮断リストへ(し人/頭(ず) と同族)。
    func testRegressionRealLMAnobijinPrefersBijin() throws {
        try prepareRealLMDictionary()
        let multi = converter.multiClauseCandidates(for: "あのびじんの", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "あの美人の", "multi=\(multi)")
        XCTAssertFalse(multi.contains(where: { $0.contains("あの日") }), "multi=\(multi)")
        // 曜日系(日=び を正当に含む語)は丸ごと辞書語のため無影響
        let friday = converter.multiClauseCandidates(for: "きんようびに", systemCandidateMode: .surface)
        XCTAssertEqual(friday.first, "金曜日に", "multi=\(friday)")
    }

    // 終助詞の長音形 のー/かなー/よねー が終助詞クラスタから漏れ、外来語 ノー(wc2627)等の
    // カタカナ化が文末を取っていた(いったのー→行ったノー)。クラスタ追加+のー の床免除
    // (wc10379 の床上げが ノー+EOS減点3000 を116差で下回る)で、かな長音形を文末正書に。
    func testRegressionRealLMIttanoElongatedFinalParticle() throws {
        try prepareRealLMDictionary()
        for (input, expectedFirst) in [
            ("いったのー", "行ったのー"),
            ("たべたのー", "食べたのー"),
            ("いったかなー", "行ったかなー"),
            ("いったよねー", "行ったよねー")
        ] {
            let multi = converter.multiClauseCandidates(for: input, systemCandidateMode: .surface)
            XCTAssertEqual(multi.first, expectedFirst, "input=\(input) multi=\(multi)")
            XCTAssertFalse(multi.contains(where: { $0.contains("ノー") || $0.contains("カナー") }), "multi=\(multi)")
        }
    }

    // 単漢字名詞→動詞の無助詞接続の減点: 同/道(どう)等の音読み接辞単漢字は裸で動詞の
    // 前に立たないが、A単位分割で unigram が安く(同4323 ≪ どう4771)、床上げ後も かな
    // 副詞 どう を279差で下回っていた(どうみせる→同見せる)。文法減点(600)で是正。
    // かな識別を wc で安くする案は そうしん→そう+しん の語中分断を生むため不採用。
    func testRegressionRealLMDoumiseruPrefersAdverb() throws {
        try prepareRealLMDictionary()
        for (input, expectedFirst) in [
            ("どうみせる", "どう見せる"),
            ("こうみせる", "こう見せる"),
            ("そうみせる", "そう見せる")
        ] {
            let multi = converter.multiClauseCandidates(for: input, systemCandidateMode: .surface)
            XCTAssertEqual(multi.first, expectedFirst, "input=\(input) multi=\(multi)")
        }
    }

    // かぶとむし: dict rank0 の 甲虫(主読み こうちゅう)が先頭を取り、学名カタカナが沈む。
    // seed=[カブトムシ, カブト虫, かぶと虫, 兜虫(辞書に無く供給)]+甲虫 は suppr+
    // exactReadingOnlySeed で完全一致時のみ末尾(かぶとむしも 等の合成には出さない)。
    func testRegressionRealLMKabutomushiPrefersKatakana() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["かぶとむし": ["甲虫"]])
        let single = converter.candidates(for: "かぶとむし", limit: 10, systemCandidateMode: .surface)
        // かぶと虫 は交ぜ書きクラス抑制(既定)で消える(2350〜)
        XCTAssertEqual(single, ["カブトムシ", "カブト虫", "兜虫", "甲虫"], "single=\(single)")
        let multi = converter.multiClauseCandidates(for: "かぶとむしも", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "カブトムシも", "multi=\(multi)")
        XCTAssertFalse(multi.contains("甲虫も"), "multi=\(multi)")
    }

    // 様態の そう は形容動詞語幹の直後がかな正書(便利そう)だが、層/僧/草 等の単漢字が
    // 先行していた(げんきそう→弦競う、たいへんそう→対変装 まで)。形容動詞判定は LM 分布
    // (prev→な の bigram 実績)で行い、な が続かない名詞の後(学生層=実在語)は触らない。
    func testRegressionRealLMNaAdjectiveSouPrefersKana() throws {
        try prepareRealLMDictionary()
        for (input, expectedFirst) in [
            ("べんりそう", "便利そう"),
            ("げんきそう", "元気そう"),
            ("しずかそう", "静かそう"),
            ("たいへんそう", "大変そう")
        ] {
            let multi = converter.multiClauseCandidates(for: input, systemCandidateMode: .surface)
            XCTAssertEqual(multi.first, expectedFirst, "input=\(input) multi=\(multi)")
        }
        // な が続かない名詞+そう は対象外(学生層 は実在語)
        let gakusei = converter.multiClauseCandidates(for: "がくせいそう", systemCandidateMode: .surface)
        XCTAssertEqual(gakusei.first, "学生層", "multi=\(gakusei)")
    }

    // Wikipedia LM は 細菌(uni 5259/は1097)を 最近(5294/は1138)より僅かに安く見て
    // さいきんは→細菌は になる(きのう/機能 と同族)。時相名詞キャップを表層別の値に
    // 拡張し 最近=5000 を追加(細菌→が1334 には勝たない水準で が 文脈は細菌を維持)。
    // 細きん(交ぜ書き収穫)は suppr。細瑾(古語: わずかな傷)は正当な収録として末尾残存。
    func testRegressionRealLMSaikinPrefersRecentInContext() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["さいきん": ["細きん"]])
        for (input, expectedFirst) in [
            ("さいきんは", "最近は"),
            ("さいきんの", "最近の"),
            ("さいきんも", "最近も"),
            ("さいきんが", "細菌が")
        ] {
            let multi = converter.multiClauseCandidates(for: input, systemCandidateMode: .surface)
            XCTAssertEqual(multi.first, expectedFirst, "input=\(input) multi=\(multi)")
        }
        let single = converter.candidates(for: "さいきん", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "最近", "single=\(single)")
        XCTAssertFalse(single.contains("細きん"), "single=\(single)")
    }

    // ひらがなのは のかな全文一致を候補2位に: ①変種エコー免除に「末尾がかなの助詞/
    // 名詞化節」を追加(bestの免除と同期)→連文節が ひらがなのは を変種2位に出せる。
    // ②かな正書根拠に「名詞化節(のは等)を剥がした語幹が辞書かな語」を追加。
    // ③提示層は根拠あり+2位以内のかな識別を位置維持(かってみようかな 型の防護は継続)。
    func testRegressionRealLMHiraganaNohaKanaSecond() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["は": ["者"]])
        let multi = converter.multiClauseCandidates(for: "ひらがなのは", systemCandidateMode: .surface)
        XCTAssertEqual(Array(multi.prefix(2)), ["平仮名のは", "ひらがなのは"], "multi=\(multi)")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "ひらがなのは"))
        XCTAssertFalse(converter.shouldKeepKanaIdentityLeading(for: "かってみようかな"))
        // 既存の名詞化節挙動は不変
        let kaku = converter.multiClauseCandidates(for: "かくのがすき", systemCandidateMode: .surface)
        XCTAssertEqual(kaku.first, "描くのが好き", "multi=\(kaku)")
    }

    // てかず: かな識別が既定で先頭化し 手数 が2番手だった。どちらも実用のため seed で
    // 手数→てかず の順に固定(かなは2位維持=提示層の位置維持(2122)で候補に残る)。
    func testRegressionRealLMTekazuPrefersKanji() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "てかず", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(2)), ["手数", "てかず"], "single=\(single)")
    }

    // 方面(かたも)=鳥取県湯梨浜町の地名のレア読み収穫(wc11000)が、表層 unigram
    // (ほうめん用途 4792)にタダ乗りして連文節の区切りを奪っていた(そんなつくりかたも→
    // そんな作り方面。読み3文字は短span床の対象外)。suppr+exactReadingOnlySeed の
    // 二段構えで、かたも 完全一致時のみ末尾供給に移す。
    func testRegressionRealLMKatamoPlaceNameExactOnly() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["かたも": ["方面"]])
        converter.store.addUserEntry(reading: "つくりかた", candidate: "作り方")
        let multi = converter.multiClauseCandidates(for: "そんなつくりかたも", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "そんな作り方も", "multi=\(multi)")
        XCTAssertFalse(multi.contains(where: { $0.contains("方面") }), "multi=\(multi)")
        // 完全一致では末尾に残る
        let exact = converter.candidates(for: "かたも", limit: 20, systemCandidateMode: .surface)
        XCTAssertTrue(exact.contains("方面"), "exact=\(exact)")
    }

    // ねん: dict は ねん0/念1/ネン2/年3 で頻出の 年 が4番手に沈んでいた。
    // seed=[年, 念, ねん] の宣言順固定(2114の正規化がかな識別も含めて保証)。
    func testRegressionRealLMNenPrefersYear() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "ねん", limit: 10, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(3)), ["年", "念", "ねん"], "single=\(single)")
    }

    // 田中(でんちゅう、wc12670=収穫底値)が表層 unigram(たなか 用途の4821)にタダ乗り
    // して 電柱(6667)から区切りを奪っていた(方面(かたも)と同族の読み跨ぎ)。一般修正:
    // wc>=10000 の表層は unigram があっても信頼せず harvest tier(9500)へ床上げ。
    func testRegressionRealLMDenchuuPrefersDenchu() throws {
        try prepareRealLMDictionary()
        for input in ["でんちゅうから", "でんちゅうが", "でんちゅうまで"] {
            let multi = converter.multiClauseCandidates(for: input, systemCandidateMode: .surface)
            XCTAssertEqual(multi.first?.hasPrefix("電柱"), true, "input=\(input) multi=\(multi)")
        }
    }

    // EOS bigram の過大な文末選好: 勝ち→EOS 1253 vs 価値→EOS 2399 の差1146が、
    // の→価値 4234 ≪ の→勝ち 5150 の正しい優位916を逆転(にほんえんのかち→〜の勝ち)。
    // EOS bigram をフォールバック(2119)との中間へ半圧縮して是正(全面無効は 学生層/
    // 柚香さん の正しい EOS 信号まで消し不成立=検証済み)。
    func testRegressionRealLMNihonenNoKachiPrefersValue() throws {
        try prepareRealLMDictionary()
        let multi = converter.multiClauseCandidates(for: "にほんえんのかち", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "日本円の価値", "multi=\(multi)")
        XCTAssertEqual(multi.dropFirst().first, "日本円の勝ち", "multi=\(multi)")
    }

    // いるが: dict は イルガ(SudachiDict の外国人名収穫、wc3897)/入賀(レア姓)のみで、
    // カタカナ名が先頭を取っていた。いる+が のかなが正書なので seed で先頭化。
    func testRegressionRealLMIrugaPrefersKana() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "いるが", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "いるが", "single=\(single)")
    }

    // なんごう: 数量詞複合の許可リストに ごう(号)/ごうしゃ(号車) が漏れており 何号 が
    // 出なかった。南鄕(旧字体異体字=見た目重複)と 永穂(読谷村の地名、正読は なんご で
    // なんごう は SudachiDict の異読疑い)は suppr。seed で 南郷→南濠→何号→かな の順。
    func testRegressionRealLMNangouSuppliesNangou() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["なんごう": ["南鄕", "永穂"]])
        let single = converter.candidates(for: "なんごう", limit: 10, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(3)), ["何号", "南郷", "南濠"], "single=\(single)")
        XCTAssertFalse(single.contains("南鄕"), "single=\(single)")
        XCTAssertFalse(single.contains("永穂"), "single=\(single)")
        let multi = converter.multiClauseCandidates(for: "なんごうしゃとなんばんせん", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "何号車と何番線", "multi=\(multi)")
    }

    // にほん→二本/2本 の学習があると にほんえん が [二本][円] に割れ、第1文節の変種
    // (2本円/二本円/にほん円)が 勝ち の変種枠を潰す(実機報告)。日本円 を curated 供給
    // して1ノードで区切りを勝たせ、日本円 先頭固定+勝ち の温存を両立する。
    func testRegressionRealLMNihonenNoKachiKeepsBoth() throws {
        try prepareRealLMDictionary()
        converter.store.incrementLearning(reading: "にほん", candidate: "二本")
        converter.store.incrementLearning(reading: "にほん", candidate: "2本")
        converter.store.addUserEntry(reading: "にほんえん", candidate: "日本円")
        let multi = converter.multiClauseCandidates(for: "にほんえんのかち", systemCandidateMode: .surface)
        XCTAssertEqual(Array(multi.prefix(2)), ["日本円の価値", "日本円の勝ち"], "multi=\(multi)")
        XCTAssertFalse(multi.contains(where: { $0.contains("二本円") || $0.contains("2本円") }), "multi=\(multi)")
    }

    // かみ: 日常頻度順(紙/髪/神/上)。カ申(神 の分解ノイズ)は suppr。
    func testRegressionRealLMKamiDailyOrder() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["かみ": ["カ申"]])
        let single = converter.candidates(for: "かみ", limit: 12, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(4)), ["紙", "髪", "神", "上"], "single=\(single)")
        XCTAssertFalse(single.contains("カ申"), "single=\(single)")
    }

    // なはし→那覇市(dict rank0 だが 那覇+し 等の合成分割に沈む)。seed で先頭固定。
    func testRegressionRealLMNahashiPrefersNahaCity() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "なはし", limit: 12, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "那覇市", "single=\(single)")
    }

    // あるのね: 存在動詞 ある はかなが正書だが、床上げ(wc6465)+のね クランプが辞書形述語
    // 直後限定で かな ある が述語フラグを持たず 有るのね に負けていた。床免除+かな述語識別
    // +のね/のよ の全かなエコー免除で あるのね を先頭に。
    func testRegressionRealLMArunoneKanaFirst() throws {
        try prepareRealLMDictionary()
        let multi = converter.multiClauseCandidates(for: "あるのね", systemCandidateMode: .surface)
        XCTAssertEqual(Array(multi.prefix(2)), ["あるのね", "有るのね"], "multi=\(multi)")
    }

    // あるのね: エンジン multi は あるのね を先頭にできる(2132)が、提示層の
    // shouldKeepKanaIdentityLeading が のね/のよ(説明終助詞)未対応で、かな候補が
    // 除去され末尾の かな確定チップに一本化されていた。のね/のよ を根拠判定に追加。
    func testRegressionRealLMArunoneKeepsKanaCandidate() throws {
        try prepareRealLMDictionary()
        // 実機同等の全語彙注入(curated ある→ある が dfp=false で先着し のね クランプを
        // 失わせる回帰の再現。エンジン直呼びだけでは検出できない=ろーま事件の教訓)
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
        let converter = KanaKanjiConverter(store: KanaKanjiStore(appGroupID: defaultsSuiteName))
        let multi = converter.multiClauseCandidates(for: "あるのね", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "あるのね", "multi=\(multi)")
        // 提示層がかな候補を除去せず残す根拠(のね を剥がした ある が辞書かな語)
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "あるのね"))
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "ひらがなのは"))
        // 語幹が2字未満(のね だけ)は対象外(空語幹で誤発火しない)
        XCTAssertFalse(converter.shouldKeepKanaIdentityLeading(for: "のね"))
    }

    // ひらがななのは: コピュラ な を挟む名詞化(ひらがな+な+のは)。stem 剥がしが のは のみで
    // な を残すと keepLeading が false になり かな候補が提示層で除去されていた。な も剥がす。
    func testRegressionRealLMHiraganaNanoheKeepsKana() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["は": ["者"]])
        let multi = converter.multiClauseCandidates(for: "ひらがななのは", systemCandidateMode: .surface)
        XCTAssertEqual(Array(multi.prefix(2)), ["平仮名なのは", "ひらがななのは"], "multi=\(multi)")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "ひらがななのは"))
    }

    // なは→那覇(沖縄県都)。unigram 6411 が高めで な+波 断片・全かなに負けていた。
    // curated で区切りを勝たせる。大きな箱/きれいな花 等 なは 部分列への巻き込みは無い。
    func testRegressionRealLMNahaPrefersNaha() throws {
        try prepareRealLMDictionary()
        converter.store.addUserEntry(reading: "なは", candidate: "那覇")
        XCTAssertEqual(converter.multiClauseCandidates(for: "なはでは", systemCandidateMode: .surface).first, "那覇では")
        XCTAssertEqual(converter.multiClauseCandidates(for: "なはではこれです", systemCandidateMode: .surface).first, "那覇ではこれです")
        XCTAssertEqual(converter.multiClauseCandidates(for: "おおきなはこ", systemCandidateMode: .surface).first, "大きな箱")
    }

    // あう は同音異義(会う/合う/逢う/遭う)。dict の 合う rank7 が rare な 晤う/遇う より
    // 下で連文節 topK3 から漏れ 合った が候補に出なかった。seed で 会う 先頭維持+合う 2番手、
    // rare 形は列挙外。合った/会った の #1/#2 は文脈依存(人に会った/条件に合った)で学習補正。
    func testRegressionRealLMAuSuppliesGou() throws {
        try prepareRealLMDictionary()
        let multi = converter.multiClauseCandidates(for: "とちにあった", systemCandidateMode: .surface)
        XCTAssertTrue(multi.contains("土地に合った"), "multi=\(multi)")
        XCTAssertFalse(multi.contains(where: { $0.contains("晤") || $0.contains("遇") }), "multi=\(multi)")
        // 人に会った は維持(合う先頭にすると壊れるケース)
        let hito = converter.multiClauseCandidates(for: "ひとにあった", systemCandidateMode: .surface)
        XCTAssertEqual(hito.first, "人に会った", "multi=\(hito)")
    }

    // みたにある: みたに→三谷(姓グロブ 3char単ノード)が [三田][に][ある] locative を
    // preempt して 〜にある が一切出なかった。姓グロブを suppr+exactReadingOnlySeed へ移し、
    // みたにある→三田にある を通す。映画を見た/昨日見た(見た は 三田 に化けない)は維持。
    func testRegressionRealLMMitaniAruLocative() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["みたに": ["三谷", "三渓", "水谷", "三谿", "参谷", "味谷", "己谷", "巳谷", "未谷", "美歎", "美谷", "見谷"]])
        XCTAssertEqual(converter.multiClauseCandidates(for: "みたにある", systemCandidateMode: .surface).first, "三田にある")
        XCTAssertEqual(converter.multiClauseCandidates(for: "えいがをみた", systemCandidateMode: .surface).first, "映画を見た")
        XCTAssertEqual(converter.multiClauseCandidates(for: "きのうみた", systemCandidateMode: .surface).first, "昨日見た")
        // 三谷 は みたに 完全一致でのみ供給(合成には出さない)
        let mitani = converter.candidates(for: "みたに", limit: 30, systemCandidateMode: .surface)
        XCTAssertTrue(mitani.contains("三谷"), "mitani=\(mitani)")
    }

    // 同音異義 あう の best-effort 出し分け: 前の名詞(に/が の前)が人物なら 会う、
    // それ以外は 合う を優先。辞書に動物性タグが無いため人物語彙+敬称接尾で近似する
    // (人名は網羅不可だが 〜さん 等の敬称付きは高確度で人物)。
    func testRegressionRealLMAuPersonHeuristic() throws {
        try prepareRealLMDictionary()
        let meets: [(String, String)] = [
            ("ひとにあった", "人に会った"), ("ともだちにあった", "友達に会った"),
            ("たなかさんにあった", "田中さんに会った"), ("せんせいにあった", "先生に会った"),
            ("かれにあった", "彼に会った")
        ]
        for (r, e) in meets {
            XCTAssertEqual(converter.multiClauseCandidates(for: r, systemCandidateMode: .surface).first, e, "input=\(r)")
        }
        let matches: [(String, String)] = [
            ("とちにあった", "土地に合った"), ("じょうけんにあった", "条件に合った"),
            ("サイズがあった", "サイズが合った"), ("きがあった", "気が合った"), ("めがあった", "目が合った")
        ]
        for (r, e) in matches {
            XCTAssertEqual(converter.multiClauseCandidates(for: r, systemCandidateMode: .surface).first, e, "input=\(r)")
        }
    }

    // 使える(可能=使う、日常最頻)が dict つかえる0/仕える1/支える2/使える3 で3番手に沈み、
    // 活用 使えた 等も下位化。seed で 使える を先頭に(単文節)。連文節は 支え uni が僅かに
    // 安く 支えた が先頭になりうるが、その場合は単文節#1挿入+学習で補正される。
    func testRegressionRealLMTsukaeruPrefersCanUse() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "つかえた", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "使えた", "single=\(single)")
        let single2 = converter.candidates(for: "つかえたのだが", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(single2.first, "使えたのだが", "single2=\(single2)")
        // 連文節でも seed 順(使える/仕える/支える)。基底 つかえる の allowlist 限定ボーナスで
        // 分割経路 [支え][た] を上回らせる。
        let multi = converter.multiClauseCandidates(for: "つかえたのだが", systemCandidateMode: .surface)
        XCTAssertEqual(Array(multi.prefix(3)), ["使えたのだが", "仕えたのだが", "支えたのだが"], "multi=\(multi)")
    }


    // 様態そう: 旨そう/上手そう(い形容詞語幹+そう)が 馬(名詞)+そう の分割に負けていた。
    // 真因は 馬→な bigram(2944)の存在で 2120 の形容動詞クランプが誤発火し 馬+そう を激安化。
    // →な コスト閾値(2000)で形容動詞(便利491/元気1129)と偶発名詞(馬2944)を分離。
    func testRegressionRealLMUmasouPrefersAdjective() throws {
        try prepareRealLMDictionary()
        let multi = converter.multiClauseCandidates(for: "うまそうではある", systemCandidateMode: .surface)
        // 2402: seed 先頭かな(うまそう)が派生にも効くようになり かな が先頭(旨そう は2番手)
        XCTAssertEqual(Array(multi.prefix(2)), ["うまそうではある", "旨そうではある"], "multi=\(multi)")
        XCTAssertFalse(multi.contains(where: { $0.hasPrefix("馬そう") }), "multi=\(multi)")
        // 形容動詞+そう(便利そう)は閾値内なのでクランプ維持
        let benri = converter.multiClauseCandidates(for: "べんりそうだ", systemCandidateMode: .surface)
        XCTAssertEqual(benri.first, "便利そうだ", "benri=\(benri)")
    }

    // カ変 来る の き活用(来ません/来ます)は活用供給順で 着る/衣る/著る(一段)より後になり、
    // 連文節の上位3供給から漏れて 鳥がきません→鳥が着ません になっていた(単文節は 来ません
    // 先頭で正)。seed きません/きます=[来〜, 着〜] で 来〜 を先頭供給。回帰ではなく既存の
    // 活用順の穴(EOS圧縮 前でも同挙動を確認済み)。
    func testRegressionRealLMKimasenPrefersKuru() throws {
        try prepareRealLMDictionary()
        XCTAssertEqual(converter.multiClauseCandidates(for: "とりがきません", systemCandidateMode: .surface).first, "鳥が来ません")
        XCTAssertEqual(converter.multiClauseCandidates(for: "とりがきます", systemCandidateMode: .surface).first, "鳥が来ます")
    }

    // ずかん: dict rank4 の かな エントリ由来で かな ずかん/ずかんで がエンジンで先頭化して
    // いた(ずかん unigram 8139 > 図鑑 5790 で本来 図鑑 が上)。seed で 図鑑 先頭化。
    // ずかんで はかな正書の根拠が無い(keepLeading=false)ので提示層で末尾寄せ/除去される
    // (提示層の早期returnを keepLeading でゲート)。
    func testRegressionRealLMZukanPrefersKanji() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "ずかん", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "図鑑", "single=\(single)")
        // ずかんで はかな正書の根拠なし=提示層でかな先頭を保持しない
        XCTAssertFalse(converter.shouldKeepKanaIdentityLeading(for: "ずかんで"))
        // 図鑑で は候補に存在する(単文節合成)
        let de = converter.candidates(for: "ずかんで", limit: 8, systemCandidateMode: .surface)
        XCTAssertTrue(de.contains("図鑑で"), "de=\(de)")
    }

    // あったが: あう(会/合/逢/遭)と ある(存在、かな正書 あった)が同居。会/合 は妥当だが
    // かな あったが(=有った の口語)も3位以内に。seed あった=[会った,合った,あった] で
    // エンジン3位、keepLeading(格助詞1つ剥がし あったが→あった→ある)で提示層が3位維持。
    func testRegressionRealLMAttagaKanaInTop3() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "あったが", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(3)), ["会ったが", "合ったが", "あったが"], "single=\(single)")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "あったが"))
        // 連文節は文節先頭(直前=BOS)の あった をかな優先するため かな あったが が先頭
        // (あった、が…=ある過去。誰かにあったが 等は に が前にあり無影響)。かな が top3 の意図は維持。
        let multi = converter.multiClauseCandidates(for: "あったが", systemCandidateMode: .surface)
        XCTAssertEqual(Array(multi.prefix(3)), ["あったが", "会ったが", "合ったが"], "multi=\(multi)")
    }

    // おととし: dict は 一昨年0/おととし1 のみ。一昨年 wc9096 が高く、単文節は かな識別先頭化、
    // 連文節は 弟(おとと)+誌(し) 等の断片合成に負けていた(弟誌の)。seed で単文節先頭化+
    // curated で連文節の区切りを勝たせる。弟誌/弟し/音とし は実語でなく合成。
    func testRegressionRealLMOtotoshiPrefersYear() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "おととし", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "一昨年", "single=\(single)")
        converter.store.addUserEntry(reading: "おととし", candidate: "一昨年")
        let multi = converter.multiClauseCandidates(for: "おととしの", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "一昨年の", "multi=\(multi)")
        XCTAssertFalse(multi.contains(where: { $0.contains("弟誌") }), "multi=\(multi)")
    }

    // たべにきたとり→た紅来た鳥 等(食べに来た鳥 が出ない)。動詞連用形は活用エンジンの終点で
    // 供給されず 食べ 単独ノードが立たない構造欠落。(b5)連用形+に を1単位供給+(b4c)カ変来る
    // 供給+連用形+に直後の移動動詞ボーナスで 食べに来た鳥 を成立させる。机に置く/北風 は無影響。
    func testRegressionRealLMRenyouNiMotion() throws {
        try prepareRealLMDictionary()
        XCTAssertEqual(converter.multiClauseCandidates(for: "たべにきたとり", systemCandidateMode: .surface).first, "食べに来た鳥")
        XCTAssertEqual(converter.multiClauseCandidates(for: "のみにきた", systemCandidateMode: .surface).first, "飲みに来た")
        // 名詞+に(机に置く)や 北風 は連用形が導出できず/移動動詞でないので無影響
        XCTAssertEqual(converter.multiClauseCandidates(for: "つくえにおく", systemCandidateMode: .surface).first, "机に置く")
        XCTAssertEqual(converter.multiClauseCandidates(for: "きたかぜがつよい", systemCandidateMode: .surface).first, "北風が強い")
    }

    // そうじゃないか: 連文節は かな そうじゃないか を正しく最良にする(全語彙経路)が、2145 で
    // 提示層の早期returnを keepLeading でゲートした際、口語否定(じゃない)語尾が keepLeading
    // 非対応で かな が除去される回帰が出た。口語否定・断定語尾(じゃない/じゃん/だろう/でしょ)を
    // keepLeading の根拠に追加。名詞+助詞(ずかんで)は非該当で false 維持。
    func testRegressionRealLMSoujanaiKanaKept() throws {
        try prepareRealLMDictionary()
        XCTAssertEqual(converter.multiClauseCandidates(for: "そうじゃないか", systemCandidateMode: .surface).first, "そうじゃないか")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "そうじゃないか"))
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "きれいじゃないか"))
        XCTAssertFalse(converter.shouldKeepKanaIdentityLeading(for: "ずかんで"))
    }

    // うまそう: ユーザ好みで かな うまそう→旨そう→上手そう の順(様態そう。casual は かな)。
    // 2143 で 旨そう 先頭にしたが、かな優先の希望に更新。seed で単文節の並びを固定。
    func testRegressionRealLMUmasouKanaOrder() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "うまそう", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(3)), ["うまそう", "旨そう", "上手そう"], "single=\(single)")
        // 馬そう(名詞+そう)は出さない(2143の閾値クランプ維持)
        let multi = converter.multiClauseCandidates(for: "うまそうではある", systemCandidateMode: .surface)
        XCTAssertFalse(multi.contains(where: { $0.hasPrefix("馬そう") }), "multi=\(multi)")
    }

    // うまそうだ→{馬そうだ, 馬操舵, 馬左右田, …}(全語彙)の是正。真因は misc の
    // そうだ→そうだ curated(1500)で 馬+そうだ が激安化(ある→ある と同型)。misc から外し
    // seed へ(順序のみ)。そうだ/そうだね の かな先頭(f5afe34 の目的)は seed で維持。
    func testRegressionRealLMUmasoudaNoUma() throws {
        try prepareRealLMDictionary()
        let supprData = try Data(contentsOf: URL(fileURLWithPath: "/Users/kusakabe/Git/ecritu/KeyboardExtension/InitialSupprHiddenVocabMigration.json"))
        UserDefaults(suiteName: defaultsSuiteName)?.set(supprData, forKey: "ÉcrituSuppr_Vocab")
        for name in ["InitialAjoutVocabMigration", "InitialMiscVocabMigration"] {
            let data = try Data(contentsOf: URL(fileURLWithPath: "/Users/kusakabe/Git/ecritu/KeyboardExtension/\(name).json"))
            let dict = try JSONDecoder().decode([String: [String]].self, from: data)
            for (r, cs) in dict { for c in cs.reversed() { converter.store.addUserEntry(reading: r, candidate: c) } }
        }
        let fresh = KanaKanjiConverter(store: KanaKanjiStore(appGroupID: defaultsSuiteName))
        let single = fresh.candidates(for: "うまそうだ", limit: 8, systemCandidateMode: .surface)
        // 2402: seed 先頭かな(うまそう)が派生にも効くようになり かな が先頭(旨そう は2番手)
        XCTAssertEqual(Array(single.prefix(2)), ["うまそうだ", "旨そうだ"], "single=\(single)")
        XCTAssertFalse(single.contains(where: { $0.hasPrefix("馬") }), "single=\(single)")
        // そうだ/そうだね は かな先頭を維持
        XCTAssertEqual(fresh.candidates(for: "そうだ", limit: 4, systemCandidateMode: .surface).first, "そうだ")
        XCTAssertEqual(fresh.multiClauseCandidates(for: "そうだね", systemCandidateMode: .surface).first, "そうだね")
    }

    // かいそう→{解そう, 会そう, 介そう, …}(サ変名詞 解/会/介 の五段化 解す/会す/介す の意向形)が
    // godanVolitional ブースト(+320)で辞書名詞・様態を押しのけていた。サ変名詞語幹(〜する成立)
    // +漢字の五段化意向はブースト対象外に。真正五段(話す→話そう/書く→書こう)は維持。
    func testRegressionRealLMKaisouNoSahenVolitional() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "かいそう", limit: 8, systemCandidateMode: .surface)
        XCTAssertFalse(single.contains(where: { ["解そう", "会そう", "介そう"].contains($0) }), "single=\(single)")
        XCTAssertEqual(single.first, "海藻", "single=\(single)")
        // 真正五段の意向形は維持
        XCTAssertEqual(converter.candidates(for: "はなそう", limit: 4, systemCandidateMode: .surface).first, "話そう")
        XCTAssertTrue(converter.candidates(for: "かこう", limit: 6, systemCandidateMode: .surface).contains("書こう"))
    }

    // 様態そう(買いそう/飼いそう=五段連用+そう)が活用スコア(980)のまま辞書名詞群に沈み
    // 候補に出なかった。読み末尾が様態そう系のとき、そうで終わる漢字活用派生に控えめブースト
    // (220)を与え top 圏へ(名詞は残す)。おいしそう/なりそう(既存の様態)は不変。
    func testRegressionRealLMKaisouBuyAppears() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "かいそう", limit: 8, systemCandidateMode: .surface)
        XCTAssertTrue(single.contains("買いそう"), "single=\(single)")
        XCTAssertTrue(single.prefix(8).contains("飼いそう"), "single=\(single)")
        // 解そう系は出ない(2153)/海藻は上位維持
        XCTAssertFalse(single.contains(where: { ["解そう", "会そう", "介そう"].contains($0) }), "single=\(single)")
        XCTAssertEqual(converter.candidates(for: "おいしそう", limit: 3, systemCandidateMode: .surface).first, "美味しそう")
        XCTAssertEqual(converter.candidates(for: "なりそう", limit: 3, systemCandidateMode: .surface).first, "成りそう")
    }

    // ねろめさんが→根路銘サンガ: さんが rank0 の サンガ(京都サンガ/僧伽)が 敬称「さん」+「が」の
    // 分割を preempt。敬称 X さんが が圧倒的頻出なので サンガ を suppr+exactReadingOnlySeed
    // (さんが 完全一致時のみ末尾)へ。根路銘/田中/京都 さんが すべて敬称が先頭に。
    func testRegressionRealLMSangaHonorific() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["さんが": ["サンガ"]])
        XCTAssertEqual(converter.multiClauseCandidates(for: "ねろめさんが", systemCandidateMode: .surface).first, "根路銘さんが")
        XCTAssertEqual(converter.multiClauseCandidates(for: "たなかさんが", systemCandidateMode: .surface).first, "田中さんが")
        // サンガ は さんが 完全一致(単文節)でのみ末尾に残る(合成・連文節からは排除)
        let exact = converter.candidates(for: "さんが", limit: 200, systemCandidateMode: .surface)
        XCTAssertTrue(exact.contains("サンガ"), "exact tail should keep サンガ")
    }

    // しまもよう→縞模様: dict rank0 に在るが word_cost=15347(収穫底値10000超)で
    // harvestTier 降格され、しま+もよう合成(島もよう 等)の下に沈んでいた。seed 登録で
    // seedExempt(降格免除)となり systemDictionary 級で先頭化する。
    func testRegressionRealLMShimamoyou() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "しまもよう", limit: 10, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "縞模様", "single=\(single)")
    }

    // きると→キルト後退: dict は キルト(rank0, wc541 と異常低=最強)のみで、動詞+と 条件形
    // 切ると/着ると(活用派生980)を押さえ先頭化。seed 順正規化で 切ると→着ると→キルト に。
    func testRegressionRealLMKirutoVerbFirst() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "きると", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(3)), ["切ると", "着ると", "キルト"], "single=\(single)")
    }


    // いきたい: たい形は活用派生(980同点)で基底列挙 いきる(一段)先行のため 生き/活き が先。
    // 会話頻度は 行く>生きる。seed 順正規化で 行きたい→生きたい→活きたい に是正。
    func testRegressionRealLMIkitaiFrequencyOrder() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "いきたい", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(3)), ["行きたい", "生きたい", "活きたい"], "single=\(single)")
    }

    // なのかー/そうなのかー: 末尾ー付き(辞書語なし)は 名/菜+のかー 等の無意味分割に。
    // 疑問・説明の のか+長音ー は口語終端でかなが正書。keepLeading=true + multiClause が
    // かな全文を先頭に返し、提示層 case(A) で かな #1 を維持する。長音なし なのか(=七日)は
    // 対象外(ー 付きに限定)。
    func testRegressionRealLMNanokaLongVowelKanaLeads() throws {
        try prepareRealLMDictionary()
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "なのかー"))
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "そうなのかー"))
        XCTAssertEqual(converter.multiClauseCandidates(for: "なのかー", systemCandidateMode: .surface), ["なのかー"])
        XCTAssertEqual(converter.multiClauseCandidates(for: "そうなのかー", systemCandidateMode: .surface).first, "そうなのかー")
    }

    // いる/いるので: ゐる(旧かな)は完全抑制、イル(カタカナ源)/入ル(京都地名)は
    // suppr+exactReadingOnlySeed で いる 完全一致時のみ末尾供給し合成・連文節から排除。
    // base いる は かな/居る を先頭に(入る は主読み はいる の副次で wordCost10054 の収穫底値
    // ゆえ seed には入れず=連文節で 入るので が先頭化するのを防ぐ)。
    func testRegressionRealLMIruNoiseAndOrder() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["いる": ["ゐる", "イル", "入ル"]])
        let base = converter.candidates(for: "いる", limit: 14, systemCandidateMode: .surface)
        XCTAssertEqual(Array(base.prefix(2)), ["いる", "居る"], "base=\(base)")
        XCTAssertFalse(base.contains("ゐる"), "ゐる should be fully suppressed")
        // イル/入ル は完全一致 いる の末尾でのみ再供給される
        XCTAssertTrue(base.contains("イル") && base.contains("入ル"), "base=\(base)")
        let multi = converter.multiClauseCandidates(for: "いるので", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "居るので", "multi=\(multi.prefix(6))")
        XCTAssertFalse(multi.contains("ゐるので"), "multi=\(multi.prefix(6))")
        XCTAssertNotEqual(multi.first, "入るので")
    }

    // 理由の ので: 基底が seed かな先頭の正書かな語(いる/ある)なら かな識別を先頭側に残す
    // (いるので→居るので #1 の直後にかな #2 を位置維持)。たべる/みる 等は dict rank2 の
    // かな harvest があるが seed 非掲載なので false=かなは末尾チップのみ(食べるので/見るので)。
    func testRegressionRealLMNodeKanaLeadingSeedGate() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["いる": ["ゐる", "イル", "入ル"]])
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "いるので"))
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "あるので"))
        XCTAssertFalse(converter.shouldKeepKanaIdentityLeading(for: "たべるので"))
        XCTAssertFalse(converter.shouldKeepKanaIdentityLeading(for: "みるので"))
    }

    // ねろめさんしか→根路銘さんしか: 蚕糸(さんし, unigram7216)+か が 敬称「さん」+副助詞「しか」の
    // 分割を preempt(レア名は →さん bigram が無く負ける)。蚕糸 を suppr+exactReadingOnlySeed で
    // さんし 完全一致時のみ末尾供給し合成・連文節から排除。田中さんしか(bigram成立)は不変。
    func testRegressionRealLMSanshikaHonorific() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["さんし": ["蚕糸"]])
        XCTAssertEqual(converter.multiClauseCandidates(for: "ねろめさんしか", systemCandidateMode: .surface).first, "根路銘さんしか")
        XCTAssertEqual(converter.multiClauseCandidates(for: "たなかさんしか", systemCandidateMode: .surface).first, "田中さんしか")
        // 蚕糸 は さんし 完全一致でのみ末尾に残る
        let exact = converter.candidates(for: "さんし", limit: 250, systemCandidateMode: .surface)
        XCTAssertTrue(exact.contains("蚕糸"), "exact tail should keep 蚕糸")
    }

    // ではある: 係助詞「は」直後の ある は漢字化しない=かな正書(では有る/では在る/では或る は
    // N-best 変種から除外)。うまそうでは有る 対策。格助詞 が の後(在庫が有る)は 有る を保持。
    // ※うまそうではある(かな全文)を #1 にするのは passthrough コストの構造的限界で不可(旨そう… が #1)。
    func testRegressionRealLMDewaAruKanaOnly() throws {
        try prepareRealLMDictionary()
        let dewa = converter.multiClauseCandidates(for: "ではある", systemCandidateMode: .surface)
        XCTAssertEqual(dewa.first, "ではある")
        XCTAssertFalse(dewa.contains("では有る"), "dewa=\(dewa)")
        let umasou = converter.multiClauseCandidates(for: "うまそうではある", systemCandidateMode: .surface)
        XCTAssertFalse(umasou.contains(where: { $0.hasSuffix("では有る") }), "umasou=\(umasou.prefix(8))")
        // 格助詞 が の後は 有る を保持(存在の 在庫が有る は正当)
        let zaiko = converter.multiClauseCandidates(for: "ざいこがある", systemCandidateMode: .surface)
        XCTAssertTrue(zaiko.contains("在庫が有る"), "zaiko=\(zaiko.prefix(4))")
    }

    // 実LM回帰: したんだが は連文節では単一ノード扱いで multi=[](単文節に委譲)。単文節トップが
    // 四反田が(レア地名読み)/湑んだが になるため、seed で口語終止のかな正書を先頭供給する。
    func testRegressionRealLMShitandagaPrefersKana() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "したんだが", limit: 12, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "したんだが", "single=\(single)")
    }

    // 実LM回帰: おそいよねえ の お添い/お沿い(お接頭+添う/沿う連用の誤合成)を落とし 遅いよねえ を
    // 最良にする。お始まりの漢字表層(reading=おそい)を減点する。
    func testRegressionRealLMOsoiYoneeDropsHonorificMisparse() throws {
        try prepareRealLMDictionary()
        let multi = converter.multiClauseCandidates(for: "おそいよねえ", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "遅いよねえ", "multi=\(multi)")
        XCTAssertFalse(
            multi.contains { $0.hasPrefix("お添い") || $0.hasPrefix("お沿い") },
            "お添い/お沿い の誤合成が残っている multi=\(multi)"
        )
    }

    // 実LM回帰: 酒造所/酒造場 は複合語が辞書・Sudachi基底・LM いずれにも未登録(構成要素は在るが
    // 単漢字接尾の連文節を抑止しているため合成もされない)。seed 供給で候補化されることを検証する。
    func testRegressionRealLMShuzouCompoundsSupplied() throws {
        try prepareRealLMDictionary()
        XCTAssertTrue(
            converter.candidates(for: "しゅぞうしょ", limit: 12, systemCandidateMode: .surface).contains("酒造所"),
            "しゅぞうしょ→酒造所 が供給されていない"
        )
        XCTAssertTrue(
            converter.candidates(for: "しゅぞうじょ", limit: 12, systemCandidateMode: .surface).contains("酒造所"),
            "しゅぞうじょ→酒造所 が供給されていない"
        )
        XCTAssertTrue(
            converter.candidates(for: "しゅぞうじょう", limit: 12, systemCandidateMode: .surface).contains("酒造場"),
            "しゅぞうじょう→酒造場 が供給されていない"
        )
    }

    // 実LM回帰: しゅぞうじょ→酒造所 を学習した後、しゅぞうじょう が 酒造所(しゅぞうじょ)+う の
    // 余りモーラ分割 酒造所う を multi 最良にしていた(候補バーが multi 優先で先頭表示)。末尾が
    // 漢字語+単独素通りかな1字なら multi を返さず単文節(seed の 酒造場)に委ねる。
    func testRegressionRealLMShuzouLearnedNoDanglingKana() throws {
        try prepareRealLMDictionary()
        converter.store.addLearnedEntry(reading: "しゅぞうじょ", candidate: "酒造所")
        converter.store.addLearnedEntry(reading: "しゅぞうしょ", candidate: "酒造所")
        converter.store.waitForPendingLearningPersists()
        converter.clearAllCaches()
        let multi = converter.multiClauseCandidates(for: "しゅぞうじょう", systemCandidateMode: .surface)
        XCTAssertFalse(multi.contains("酒造所う"), "余りモーラ分割が残っている multi=\(multi)")
        let single = converter.candidates(for: "しゅぞうじょう", limit: 12, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "酒造場", "single=\(single)")
    }

    // 実LM回帰: おそい は 遅い という1語なので、丁寧接頭辞の お+[そい候補](お添い/お沿い/お副い/
    // お初位…)を単文節合成で作らない(根本修正=そもそも候補に出さない→学習もされない)。
    // フル読みが1語でない お名前 は温存する。
    func testRegressionRealLMOsoiNoHonorificMisparseCandidates() throws {
        try prepareRealLMDictionary()
        let osoi = converter.candidates(for: "おそい", limit: 24, systemCandidateMode: .surface)
        XCTAssertFalse(osoi.contains { $0.hasPrefix("お") && $0 != "おそい" }, "お+誤合成が残っている osoi=\(osoi)")
        XCTAssertEqual(osoi.first, "遅い", "osoi=\(osoi)")
        // フル読みが1語でない honorific 名詞は温存(お名前)。
        let oname = converter.candidates(for: "おなまえ", limit: 8, systemCandidateMode: .surface)
        XCTAssertTrue(oname.contains("お名前"), "お名前 が失われた oname=\(oname)")
    }

    // 実LM回帰: いまだに は かな(いまだに)が先頭、合成語 未だに(辞書に無く 未だ+に)を seed 2番手で
    // 供給して候補に残す。順序は いまだに → 未だに。
    func testRegressionRealLMImadaniKeepsMidaAfterKana() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "いまだに", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "いまだに", "single=\(single)")
        guard let kanaIdx = single.firstIndex(of: "いまだに"),
            let kanjiIdx = single.firstIndex(of: "未だに") else {
            return XCTFail("未だに が候補に無い single=\(single)")
        }
        XCTAssertLessThan(kanaIdx, kanjiIdx, "未だに が いまだに より前 single=\(single)")
    }

    // 実LM回帰: 旧仮名遣い(ゐゑヰヱ)は既定(historicalKanaSurfaceAllowed=false)で単文節・連文節とも
    // 抑制。設定ONで含める。ぐらいかなー→ぐらゐかなー 等。
    func testRegressionRealLMHistoricalKanaSuppressedByDefault() throws {
        try prepareRealLMDictionary()
        converter.setHistoricalKanaSurfaceAllowed(false)
        let multi = converter.multiClauseCandidates(for: "ぐらいかなー", systemCandidateMode: .surface)
        XCTAssertFalse(multi.contains { $0.contains("ゐ") || $0.contains("ゑ") }, "旧仮名が連文節に残存 multi=\(multi)")
        let single = converter.candidates(for: "ぐらい", limit: 24, systemCandidateMode: .surface)
        XCTAssertFalse(single.contains { $0.contains("ゐ") || $0.contains("ゑ") }, "旧仮名が単文節に残存 single=\(single)")
        // 設定ONなら含める。
        converter.setHistoricalKanaSurfaceAllowed(true)
        converter.clearAllCaches()
        let allowedSingle = converter.candidates(for: "ぐらい", limit: 24, systemCandidateMode: .surface)
        XCTAssertTrue(allowedSingle.contains { $0.contains("ゐ") }, "設定ONで旧仮名が含まれない single=\(allowedSingle)")
    }

    // 実LM回帰: 提示層のかな識別先頭維持(shouldKeepKanaIdentityLeading)。エンジンがかなを最良に
    // 選んでも根拠が無いと提示層が末尾へ退避し漢字(暗いかなー/これは未だ)が繰り上がっていた
    // (Mac正解・実機ジャンクの真因)。かな終助詞クラスタ剥がし+かな副詞末尾で根拠を認める。
    func testRegressionRealLMKanaIdentityLeadingEvidence() throws {
        try prepareRealLMDictionary()
        // ぐらいかなー: 終助詞 かなー を剥がすと ぐらい(副助詞・かな正書)。
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "ぐらいかなー"), "ぐらいかなー")
        // これはいまだ / これはまだ: 末尾がかな副詞(直前が助詞 は)。
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "これはいまだ"), "これはいまだ")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "これはまだ"), "これはまだ")
    }

    // 実LM回帰: て形+くれる補助動詞(使ってくれない)。くれない読みは 紅(名詞LM5908)が最安1ノードで
    // 使って紅 を作っていた。て形直後のかな識別を安価化し 使ってくれない を最上位にする。
    func testRegressionRealLMTeKureAuxiliary() throws {
        try prepareRealLMDictionary()
        XCTAssertEqual(converter.multiClauseCandidates(for: "つかってくれない", systemCandidateMode: .surface).first, "使ってくれない")
        XCTAssertEqual(converter.multiClauseCandidates(for: "みてくれない", systemCandidateMode: .surface).first, "見てくれない")
        XCTAssertEqual(converter.multiClauseCandidates(for: "たべてくれた", systemCandidateMode: .surface).first, "食べてくれた")
    }

    // 実LM回帰: 副助詞ぐらい(連濁)はかなが正書。暗い/昏い等はくらい読みの誤エントリなので
    // 読みぐらいで抑制(suppr)。ぐらいかなー→暗いかなー が2位に出るのを消す。
    func testRegressionRealLMGuraiSuppressesKuraiAdjectives() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["ぐらい": ["暗い", "昏い", "冥い", "瞑い", "黯い", "闇い", "蒙い", "溟い"]])
        converter.clearAllCaches()
        let multi = converter.multiClauseCandidates(for: "ぐらいかなー", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "ぐらいかなー", "multi=\(multi)")
        XCTAssertFalse(multi.contains { $0.hasPrefix("暗い") || $0.hasPrefix("昏い") }, "くらい形容詞が残存 multi=\(multi)")
    }

    // 実LM回帰: 俗語 やばい/口語断定 じゃん はカタカナ形が Wikipedia LM で安く(ヤバイ/ジャン)、
    // ヤバイジャン が連文節最良になっていた。かな識別を安価化し やばいじゃん を最上位に。
    func testRegressionRealLMYabaiJan() throws {
        try prepareRealLMDictionary()
        let multi = converter.multiClauseCandidates(for: "やばいじゃん", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "やばいじゃん", "multi=\(multi)")
    }

    // 実LM回帰: 逆接の接続詞 だけど はかなが正書。提示層のかな識別維持根拠が無く ダけど/打けど が
    // 繰り上がっていた(単文節#1は だけど)。だけど/けど/けれど… を根拠に追加。
    func testRegressionRealLMDakedoKanaLeading() throws {
        try prepareRealLMDictionary()
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "だけど"), "だけど")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "いくけど"), "いくけど")
        XCTAssertEqual(converter.candidates(for: "だけど", limit: 6, systemCandidateMode: .surface).first, "だけど")
    }

    // 実LM回帰: 複合語 殻付き(からつき)が辞書に無く単文節で出なかった。seed で供給する。
    // ※連文節 からつきのほうが は から(助詞・激安)+付き 分割が強く 殻付き は未達(別途 curated 化が必要)。
    func testRegressionRealLMKaratsukiSupplied() throws {
        try prepareRealLMDictionary()
        XCTAssertEqual(converter.candidates(for: "からつき", limit: 6, systemCandidateMode: .surface).first, "殻付き")
    }

    // 実LM回帰: 殻付き を curated(misc, コスト1500)化すると連文節でも から(助詞)+付き 分割に勝つ。
    // テストバンドルは misc JSON を読まないため addUserEntry で curated を再現する。
    func testRegressionRealLMKaratsukiCuratedWinsMultiClause() throws {
        try prepareRealLMDictionary()
        converter.store.addUserEntry(reading: "からつき", candidate: "殻付き")
        converter.store.waitForPendingLearningPersists()
        converter.clearAllCaches()
        let multi = converter.multiClauseCandidates(for: "からつきのほうが", systemCandidateMode: .surface)
        XCTAssertTrue(multi.first?.hasPrefix("殻付き") ?? false, "multi=\(multi)")
    }

    // 実LM回帰: 現る(うつる)は非標準の誤読み割り当て。基底+て形を suppr 登録し 現って/現ってます を
    // 単文節・連文節とも除去(テストバンドルは hidden JSON 非搭載のため injectSuppression で再現)。
    func testRegressionRealLMUtsuruGensuruSuppressed() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["うつる": ["現る"], "うつって": ["現って"]])
        converter.clearAllCaches()
        let single = converter.candidates(for: "うつって", limit: 10, systemCandidateMode: .surface)
        XCTAssertFalse(single.contains { $0.hasPrefix("現") }, "単文節に現って残存 single=\(single)")
        // ※連文節 ここにもうつってます の 現ってます は別の脱活用経路で残る(既知の未解決課題)。
    }

    // 実LM回帰: うつる の常用表記(写る/移る/映る/感染る)を seed で上位順に固定。活用派生(うつって)
    // にも波及し、連文節の活用供給 top3 にも 写る系が入る。※現る(非標準・基底索引由来)は seed 非経由の
    // ため demote しきれず上位に残る(構造課題)。ここでは 写/移/映 が 感染/憑 より前であることを確認。
    func testRegressionRealLMUtsuruCommonWritingsOrder() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "うつって", limit: 10, systemCandidateMode: .surface)
        for w in ["写って", "移って", "映って"] {
            XCTAssertTrue(single.contains(w), "\(w) が候補に無い single=\(single)")
        }
        guard let iUtsu = single.firstIndex(of: "写って"),
            let iKan = single.firstIndex(of: "感染って") else {
            return XCTFail("single=\(single)")
        }
        XCTAssertLessThan(iUtsu, iKan, "写って が 感染って より前 single=\(single)")
    }

    // 実LM回帰: だけど の誤生成(だ の漢字/カタカナ表層+けど=ダけど/打けど…)を誤エントリ抑制。
    // だ はコピュラで常にかな。テストバンドルは hidden JSON 非搭載のため injectSuppression で再現。
    func testRegressionRealLMDakedoVariantsSuppressed() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["だけど": ["ダけど", "堕けど", "大けど", "娜けど", "惰けど", "打けど", "田けど", "舵けど", "駄けど", "拿けど"]])
        converter.clearAllCaches()
        let single = converter.candidates(for: "だけど", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "だけど", "single=\(single)")
        XCTAssertFalse(single.contains { $0 != "だけど" && $0.hasSuffix("けど") }, "だ変種+けど が残存 single=\(single)")
    }

    // 実LM回帰: 算用数字+助数詞をロジック生成(arabicNumericCompoundCandidates)。追加語彙に個別登録
    // せず任意の数×助数詞+第N回を出す。算用は漢数字複合より前(2本>二本)、辞書の非数値語(日本)は上のまま。
    func testRegressionRealLMArabicNumericCompound() throws {
        try prepareRealLMDictionary()
        // パーサ単体。
        XCTAssertEqual(KanaKanjiConverter.japaneseNumberReadingValue("ごひゃく"), 500)
        XCTAssertEqual(KanaKanjiConverter.japaneseNumberReadingValue("にじゅう"), 20)
        XCTAssertEqual(KanaKanjiConverter.japaneseNumberReadingValue("さん"), 3)
        // 生成。
        XCTAssertEqual(converter.arabicNumericCompoundCandidates(for: "にしゅうかん"), ["2週間"])
        XCTAssertEqual(converter.arabicNumericCompoundCandidates(for: "だいいっかい"), ["第1回"])
        // にほん: 日本(非数値辞書語)が先頭、2本 は候補にあり漢数字 二本 より前。
        let nihon = converter.candidates(for: "にほん", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(nihon.first, "日本", "nihon=\(nihon)")
        guard let iAra = nihon.firstIndex(of: "2本"), let iKan = nihon.firstIndex(of: "二本") else {
            return XCTFail("2本/二本 が無い nihon=\(nihon)")
        }
        XCTAssertLessThan(iAra, iKan, "2本 が 二本 より前 nihon=\(nihon)")
    }

    // 実LM回帰: 連文節 ここにもうつってます の 現ってます を除去。基底抑制が活用に波及しないため、
    // 現る/現って に加え活用形(現ってます/現ってる/現ってた/現った)を誤エントリ登録して各スパンで消す。
    func testRegressionRealLMGensuruMultiSuppressed() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["うつる": ["現る"], "うつって": ["現って"], "うつってます": ["現ってます"], "うつってる": ["現ってる"], "うつってた": ["現ってた"], "うつった": ["現った"]])
        converter.clearAllCaches()
        let multi = converter.multiClauseCandidates(for: "ここにもうつってます", systemCandidateMode: .surface)
        XCTAssertFalse(multi.contains { $0.contains("現って") }, "現ってます 残存 multi=\(multi)")
    }

    // 実LM回帰: しちにん→7人/七人(arabic+kanji)、はいすいこう→排水溝(seed供給・排水坑より前)、
    // しゅちょう→主張(LM最頻・seed先頭化)、では→かな先頭(複合助詞・提示層維持)。
    func testRegressionRealLMBatch3() throws {
        try prepareRealLMDictionary()
        let shichinin = converter.candidates(for: "しちにん", limit: 8, systemCandidateMode: .surface)
        XCTAssertTrue(shichinin.contains("7人"), "しちにん=\(shichinin)")
        XCTAssertTrue(shichinin.contains("七人"), "しちにん=\(shichinin)")
        let haisui = converter.candidates(for: "はいすいこう", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(haisui.first, "排水溝", "はいすいこう=\(haisui)")
        let shuchou = converter.candidates(for: "しゅちょう", limit: 5, systemCandidateMode: .surface)
        XCTAssertEqual(shuchou.first, "主張", "しゅちょう=\(shuchou)")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "では"), "では keepKana")
    }

    // 実LM回帰: 長音終助詞(かなー)・丁寧ます+終助詞(ますね/ますよ/ました)はエンジンがかなを1位に
    // 返すが提示層 keepKana=false で末尾退避し カなー/マスね が繰り上がっていた。keepKana=true に。
    // すます(澄ます が正)はエンジンが漢字1位なので keepKana=true でも澄ますは不変(誤爆なし)。
    func testRegressionRealLMKanaaMasuneKanaLeading() throws {
        try prepareRealLMDictionary()
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "かなー"), "かなー")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "ますね"), "ますね")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "ました"), "ました")
        XCTAssertEqual(converter.candidates(for: "ますね", limit: 3, systemCandidateMode: .surface).first, "ますね")
        // 誤爆防止: すます は 澄ます が先頭のまま(kana識別は先頭でないので keepKana は影響しない)。
        XCTAssertNotEqual(converter.candidates(for: "すます", limit: 3, systemCandidateMode: .surface).first, "すます")
    }

    // 実LM回帰: びょう は 秒(LM最頻・助数詞)が辞書word_cost順で 鋲/眇 に沈んでいた。seedで 秒 先頭・
    // 鋲/病 続き、眇 は後方へ。
    func testRegressionRealLMByouOrder() throws {
        try prepareRealLMDictionary()
        let byou = converter.candidates(for: "びょう", limit: 12, systemCandidateMode: .surface)
        XCTAssertEqual(byou.first, "秒", "びょう=\(byou)")
        guard let iByou = byou.firstIndex(of: "秒"), let iByou2 = byou.firstIndex(of: "眇") else {
            return XCTFail("秒/眇 が無い byou=\(byou)")
        }
        XCTAssertLessThan(iByou, iByou2, "秒 が 眇 より前 byou=\(byou)")
    }

    // 回帰: かこく(助数詞 か国/ヶ国)は数字直後で か国→箇国→カ国… の順(マップ順)に前置。カコク抑制。
    func testRegressionRealLMKakokuCounter() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["かこく": ["カコク"]])
        converter.clearAllCaches()
        let cands = converter.candidates(for: "かこく", limit: 16, systemCandidateMode: .surface)
        let boosted = KanaKanjiConverter.digitContextCounterBoostedCandidates(cands, reading: "かこく", precedingCharacter: "3")
        XCTAssertEqual(Array(boosted.prefix(2)), ["か国", "箇国"], "boosted=\(boosted.prefix(6))")
        // 過酷/苛酷 は counter の後ろ。
        guard let iKa = boosted.firstIndex(of: "か国"), let iKakoku = boosted.firstIndex(of: "過酷") else {
            return XCTFail("boosted=\(boosted)")
        }
        XCTAssertLessThan(iKa, iKakoku, "か国 が 過酷 より前")
        XCTAssertFalse(cands.contains("カコク"), "カコク残存 cands=\(cands)")
    }

    // 回帰: 直前確定が数字(半角/全角)なら助数詞を先頭へ前置する純粋関数(90確定→びょう→秒)。
    func testRegressionDigitContextCounterBoost() throws {
        let cands = ["鋲", "秒", "病", "眇"]
        // 直前が数字(半角) → 秒 が先頭。
        XCTAssertEqual(
            KanaKanjiConverter.digitContextCounterBoostedCandidates(cands, reading: "びょう", precedingCharacter: "9").first,
            "秒"
        )
        // 全角数字も対象。
        XCTAssertEqual(
            KanaKanjiConverter.digitContextCounterBoostedCandidates(cands, reading: "びょう", precedingCharacter: "０").first,
            "秒"
        )
        // 直前が数字でなければ不変。
        XCTAssertEqual(
            KanaKanjiConverter.digitContextCounterBoostedCandidates(cands, reading: "びょう", precedingCharacter: "あ"),
            cands
        )
        // 助数詞でない読みは不変。
        XCTAssertEqual(
            KanaKanjiConverter.digitContextCounterBoostedCandidates(["日本", "二本"], reading: "にほん", precedingCharacter: "9"),
            ["日本", "二本"]
        )
        // ほん→本 も数字直後で先頭に。
        XCTAssertEqual(
            KanaKanjiConverter.digitContextCounterBoostedCandidates(["盆", "本", "翻"], reading: "ほん", precedingCharacter: "3").first,
            "本"
        )
    }

    // 実LM回帰: びょう の 眇(見間違えやすい)を seed 末尾で降格(秒先頭・眇は廟/渺の後)。
    func testRegressionRealLMByouGensuruDemoted() throws {
        try prepareRealLMDictionary()
        let byou = converter.candidates(for: "びょう", limit: 12, systemCandidateMode: .surface)
        XCTAssertEqual(byou.first, "秒", "byou=\(byou)")
        guard let iByou = byou.firstIndex(of: "廟"), let iGen = byou.firstIndex(of: "眇") else {
            return XCTFail("廟/眇 が無い byou=\(byou)")
        }
        XCTAssertLessThan(iByou, iGen, "眇 が 廟 より後 byou=\(byou)")
    }

    // 実LM回帰: 長押し/隠して/こぞって を curated(misc)化で連文節・単文節に供給(seedは連文節に入らない)。
    // 辞書形動詞+して 誤合成(描くして)は一般ペナルティで抑止。テストは addUserEntry で curated 再現。
    func testRegressionRealLMBatch4Curated() throws {
        try prepareRealLMDictionary()
        converter.store.addUserEntry(reading: "ながおし", candidate: "長押し")
        converter.store.addUserEntry(reading: "こぞって", candidate: "こぞって")
        converter.store.addUserEntry(reading: "かくして", candidate: "隠して")
        converter.store.waitForPendingLearningPersists()
        converter.clearAllCaches()
        XCTAssertTrue(converter.multiClauseCandidates(for: "ながおしで", systemCandidateMode: .surface).first?.hasPrefix("長押し") ?? false)
        XCTAssertEqual(converter.candidates(for: "こぞって", limit: 4, systemCandidateMode: .surface).first, "こぞって")
        let umaku = converter.multiClauseCandidates(for: "うまくかくして", systemCandidateMode: .surface)
        XCTAssertTrue(umaku.first?.hasSuffix("隠して") ?? false, "umaku=\(umaku)")
    }

    // 実LM回帰: いいよ はエンジンがかな1位に返すが keepKana=false で 良いよ/イイよ/唯々よ が繰り上がって
    // いた。終助詞よ剥がし+語幹いいが辞書かな語で keepKana=true に。かってみようかな(活用連鎖)は不変。
    // 踊り字(ゝゞ)は独立トグル iterationMarkSurfaceAllowed で制御(既定OFFで抑制、ONで含める)。
    func testRegressionRealLMIiyoAndOdoriji() throws {
        try prepareRealLMDictionary()
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "いいよ"), "いいよ")
        XCTAssertFalse(converter.shouldKeepKanaIdentityLeading(for: "かってみようかな"), "かってみようかな は不変")
        // 踊り字(ゝ)は踊り字トグル既定OFFで抑制(旧仮名トグルとは独立)。
        converter.setHistoricalKanaSurfaceAllowed(false)
        converter.setIterationMarkSurfaceAllowed(false)
        converter.clearAllCaches()
        let iiyo = converter.candidates(for: "いいよ", limit: 12, systemCandidateMode: .surface)
        XCTAssertFalse(iiyo.contains { $0.contains("ゝ") || $0.contains("ゞ") }, "踊り字が残存 iiyo=\(iiyo)")
        // 踊り字トグルONで含める(旧仮名はOFFのまま=独立確認)。
        converter.setIterationMarkSurfaceAllowed(true)
        converter.clearAllCaches()
        XCTAssertTrue(converter.candidates(for: "いいよ", limit: 12, systemCandidateMode: .surface).contains { $0.contains("ゝ") }, "踊り字トグルONで踊り字が出ない")
    }

    // 実LM回帰: ひび は 皹(稀字)が先頭・かな ひび が圏外だった。日々(daily・最頻)先頭を保ちつつ
    // かな ひび を2番手に、皹/皸/罅(稀字)を降格(罅割れの意味で ひび を選べるように)。
    func testRegressionRealLMHibiKanaSecond() throws {
        try prepareRealLMDictionary()
        let hibi = converter.candidates(for: "ひび", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(hibi.first, "日々", "hibi=\(hibi)")
        XCTAssertEqual(hibi.dropFirst().first, "ひび", "hibi=\(hibi)")
    }

    // 実LM回帰: やつ(かな優先=既存misc curated)+ヤツ抑制、のにー(にー→ニー のカタカナ化を抑制)。
    // テストバンドルは misc/hidden JSON 非搭載のため addUserEntry / injectSuppression で再現。
    func testRegressionRealLMYatsuAndNonii() throws {
        try prepareRealLMDictionary()
        converter.store.addUserEntry(reading: "やつ", candidate: "やつ")
        converter.store.waitForPendingLearningPersists()
        try injectSuppression(["やつ": ["ヤツ"], "にー": ["ニー"], "のにー": ["のニー"]])
        converter.clearAllCaches()
        XCTAssertEqual(converter.multiClauseCandidates(for: "やつにはある", systemCandidateMode: .surface).first, "やつにはある")
        XCTAssertFalse(converter.candidates(for: "やつ", limit: 6, systemCandidateMode: .surface).contains("ヤツ"), "ヤツ残存")
        XCTAssertEqual(converter.multiClauseCandidates(for: "いったのにー", systemCandidateMode: .surface).first, "行ったのにー")
    }

    // 実LM回帰: ろーぬげんさん→ローヌ原産(ローヌ/原産 とも辞書語。連文節が正しく分割することの確認)。
    func testRegressionRealLMRhoneGensan() throws {
        try prepareRealLMDictionary()
        XCTAssertEqual(converter.multiClauseCandidates(for: "ろーぬげんさん", systemCandidateMode: .surface).first, "ローヌ原産")
    }

    // 実LM回帰: かな正書語+助詞+ある/いる の全かな句(やつにはある)を提示層で先頭維持。ある/いる を
    // 剥がして再帰し語幹(やつ)がかな正書なら keepKana=true(奴にはある への繰り上がりを防ぐ)。
    // ろーぬげんさん→ローヌ原産 も現行コードで先頭(退行防止)。
    func testRegressionRealLMYatsuNihaAruAndRhone() throws {
        try prepareRealLMDictionary()
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "やつにはある"), "やつにはある keepKana")
        XCTAssertEqual(converter.multiClauseCandidates(for: "ろーぬげんさん", systemCandidateMode: .surface).first, "ローヌ原産")
    }

    // 追加語彙 ろー→raw(1〜2モーラのラテン断片)が連文節で ローヌ を分断しないこと。
    // 実機のみ再現していた ろーぬげんさん→raw脱げんさん の一般対処(短ラテン断片の床除外)。
    func testRegressionRealLMRhoneShortLatinFragmentDoesNotFragment() throws {
        try prepareRealLMDictionary()
        converter.store.addUserEntry(reading: "ろー", candidate: "raw")
        converter.invalidateCandidateCache()
        let multi = converter.multiClauseCandidates(for: "ろーぬげんさん", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "ローヌ原産", "ろー→raw 断片下でも ローヌ原産 が先頭であるべき: \(multi.prefix(4))")
        // 単文節では ろー→raw が従来どおり供給されること(床除外は連文節限定)。
        let single = converter.candidates(for: "ろー", limit: 6, systemCandidateMode: .surface)
        XCTAssertTrue(single.contains("raw"), "単文節 ろー では raw が候補に残るべき: \(single.prefix(6))")
    }

    // 実機同様に追加語彙(sacoche=InitialAjout + 変換対策 misc=InitialMisc)と抑制
    // (InitialSupprHidden)をテストの store へ投入する。ストアの initialUserDictionary() は
    // Bundle(for: KanaKanjiStore.self) のバンドル同梱JSONを読むが、テストバンドルには
    // これらが同梱されない(=追加語彙が空になり、実機のみ再現するバグがMacで再現しない根本原因)。
    // ここではリポジトリの生成済みJSONを直接読み、manual追加語彙(ÉcrituAjoutVocab)へ一括投入して
    // 実機の initialUserDictionary 相当を再現する(multi では同格の curated 供給として扱われる)。
    // 追加語彙由来の「実機のみ」誤変換(ろーぬげんさん→raw脱げんさん 等)の回帰検知に使う。
    private func loadDeviceAddedVocabulary(
        includeMisc: Bool = true,
        includeSuppression: Bool = true
    ) throws {
        let root = "/Users/kusakabe/Git/ecritu/KeyboardExtension"

        func loadJSON(_ name: String) -> [String: [String]] {
            let url = URL(fileURLWithPath: "\(root)/\(name).json")
            guard let data = try? Data(contentsOf: url),
                let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
                return [:]
            }
            return decoded
        }

        var combined = loadJSON("InitialAjoutVocabMigration")
        if includeMisc {
            for (reading, candidates) in loadJSON("InitialMiscVocabMigration") {
                combined[reading, default: []].append(contentsOf: candidates)
            }
        }

        guard let defaults = UserDefaults(suiteName: defaultsSuiteName) else {
            throw XCTSkip("no defaults suite in this environment")
        }
        // 実機の userDictionary() が読む形式(JSON Data の [String:[String]])で一括書き込みする
        // (addUserEntry の1件ずつ保存だと数百件で低速なため)。
        let combinedData = try JSONEncoder().encode(combined)
        defaults.set(combinedData, forKey: "ÉcrituAjoutVocab")

        if includeSuppression {
            let suppression = loadJSON("InitialSupprHiddenVocabMigration")
            if !suppression.isEmpty {
                let suppressionData = try JSONEncoder().encode(suppression)
                defaults.set(suppressionData, forKey: "ÉcrituSuppr_Vocab")
            }
        }

        converter.invalidateCandidateCache()
    }

    // 実機同様に追加語彙をロードした状態で、追加語彙断片(ろー→raw)が長語を分断しないこと。
    // 実データ(sacoche.plist→InitialAjout)由来で ろーぬげんさん→ローヌ原産 を固定し、
    // 「テストが追加語彙を読まないため実機のみ再現していた」ギャップを回帰で塞ぐ。
    func testRegressionRealLMDeviceVocabularyRhoneNotFragmented() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary()

        // sacoche に ろー→raw が実在することを前提にした回帰(存在しなければ前提が崩れるので確認)。
        XCTAssertTrue(
            converter.store.userDictionary()["ろー"]?.contains("raw") ?? false,
            "前提: sacoche 由来の ろー→raw が追加語彙にロードされていること"
        )

        let multi = converter.multiClauseCandidates(for: "ろーぬげんさん", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "ローヌ原産", "実機同様の追加語彙下でも ローヌ原産 が先頭: \(multi.prefix(4))")
    }

    // することがある: 形式名詞 こと で終わる名詞化節はかなが正書。提示層で先頭かな
    // することがある が する事がある に繰り上がらないよう keepKana を true にする。
    func testRegressionRealLMSuruKotoGaAruKeepsKana() throws {
        try prepareRealLMDictionary()
        let multi = converter.multiClauseCandidates(for: "することがある", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "することがある", "エンジン最良がかな: \(multi.prefix(3))")
        XCTAssertTrue(
            converter.shouldKeepKanaIdentityLeading(for: "することがある"),
            "形式名詞 こと 終わりの名詞化節は提示層でかな先頭維持すべき"
        )
    }

    // あったんで(文節先頭のあった=ある過去+んで)はかな先頭。ただし 気が/目が/サイズが/条件に+
    // あった(あったが文節先頭でない=連文節)は 合う の漢字 合った を維持する(文脈限定の切り分け)。
    func testRegressionRealLMAttandeKanaLeadingClauseInitialOnly() throws {
        try prepareRealLMDictionary()
        let attande = converter.multiClauseCandidates(for: "あったんで", systemCandidateMode: .surface)
        XCTAssertEqual(attande.first, "あったんで", "文節先頭 あったんで はかな先頭: \(attande.prefix(3))")
        // 提示層のかな降格を受けないこと(false だと実機バーだけ 会ったんで が先頭に繰り上がる)
        XCTAssertTrue(
            converter.shouldKeepKanaIdentityLeading(for: "あったんで"),
            "あったんで(=あった+んで)は提示層でかな先頭維持すべき"
        )
        for (reading, expected) in [
            ("きがあった", "気が合った"),
            ("めがあった", "目が合った"),
            ("さいずがあった", "サイズが合った"),
            ("じょうけんにあった", "条件に合った")
        ] {
            let m = converter.multiClauseCandidates(for: reading, systemCandidateMode: .surface)
            XCTAssertEqual(m.first, expected, "\(reading) は 合う 慣用句(あったが文節先頭でない): \(m.prefix(3))")
        }
    }

    // ひび+入る の連語(ひびが入る/ひびは入ってない)ではかな ひび(罅)を優先。ただし 入る 以外
    // (ひびを大切に/ひびの暮らし=日々)は 日々 を維持する(文脈限定=直後が はいる 活用のときだけ)。
    func testRegressionRealLMHibiPrefersKanaBeforeHairu() throws {
        try prepareRealLMDictionary()
        XCTAssertEqual(
            converter.multiClauseCandidates(for: "ひびははいってなかった", systemCandidateMode: .surface).first,
            "ひびは入ってなかった"
        )
        XCTAssertEqual(
            converter.multiClauseCandidates(for: "ひびがはいった", systemCandidateMode: .surface).first,
            "ひびが入った"
        )
        // 入る 以外は 日々 のまま
        XCTAssertEqual(
            converter.multiClauseCandidates(for: "ひびをたいせつに", systemCandidateMode: .surface).first,
            "日々を大切に"
        )
        XCTAssertEqual(
            converter.multiClauseCandidates(for: "ひびのくらし", systemCandidateMode: .surface).first,
            "日々の暮らし"
        )
    }

    // ほうだい: 連文節が 法第(法+第 の誤合成)を単独で返しマージ先頭を奪っていた。seed+seedOrder
    // ボーナスで 放題 を最良化(→multi は単語なので委譲=[])し、表示は単文節順 放題/邦題/砲台/法大 に。
    func testRegressionRealLMHoudaiPrefersHoudai() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "ほうだい", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(4)), ["放題", "邦題", "砲台", "法大"], "single=\(single.prefix(6))")
        // 連文節が 法第 を先頭に出さない(委譲=[] か、放題 が先頭)。
        let multi = converter.multiClauseCandidates(for: "ほうだい", systemCandidateMode: .surface)
        XCTAssertFalse(multi.first == "法第", "連文節が 法第 を先頭に出すべきでない: \(multi.prefix(3))")
    }

    // ておく/てしまう 縮約の欠落活用形(とけば=仮定形、ちゃおう/じゃおう=意向形)の供給。
    // いっとけば→一途毛羽、つかっちゃおう→使っちゃ王 等の誤合成しか出なかった。
    func testRegressionRealLMTokebaChaouSupplied() throws {
        try prepareRealLMDictionary()
        let ittokeba = converter.candidates(for: "いっとけば", limit: 6, systemCandidateMode: .surface)
        XCTAssertTrue(ittokeba.contains("言っとけば"), "言っとけば が候補にあるべき: \(ittokeba.prefix(6))")
        XCTAssertTrue(ittokeba.contains("行っとけば"), "行っとけば が候補にあるべき: \(ittokeba.prefix(6))")
        let chaou = converter.candidates(for: "つかっちゃおう", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(chaou.first, "使っちゃおう", "single=\(chaou.prefix(4))")
        let jaou = converter.candidates(for: "よんじゃおう", limit: 4, systemCandidateMode: .surface)
        XCTAssertTrue(jaou.contains("呼んじゃおう"), "single=\(jaou.prefix(4))")
        let tabetokeba = converter.candidates(for: "たべとけば", limit: 3, systemCandidateMode: .surface)
        XCTAssertEqual(tabetokeba.first, "食べとけば", "single=\(tabetokeba.prefix(3))")
    }

    // よかったな: エンジン(連文節)はかな最良だが、keepKana=false だと提示層が先頭かなを末尾へ
    // 退避し実機だけ 良かったな 先頭になる。い形容詞かな過去(Xかった→基底X+い が辞書かな語)の
    // 終助詞剥がし規則で提示層でもかな先頭を維持。
    func testRegressionRealLMYokattanaKeepsKana() throws {
        try prepareRealLMDictionary()
        let multi = converter.multiClauseCandidates(for: "よかったな", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "よかったな", "multi=\(multi.prefix(3))")
        XCTAssertTrue(
            converter.shouldKeepKanaIdentityLeading(for: "よかったな"),
            "よかったな は提示層でかな先頭維持すべき"
        )
    }

    // わからなく: 否定連用形 なく の活用規則欠落で 分からなく 系が出ず、単漢字わ+から+なく の
    // 合成(わから無く/ワからなく)だけが並んでいた。なく 規則補充+seed でかな→分から→解ら の順。
    func testRegressionRealLMWakaranakuSupplied() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "わからなく", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(3)), ["わからなく", "分からなく", "解らなく"], "single=\(single)")
        // godan なく の一般供給確認(名詞合成の干渉が無い動詞で導出を確認)
        let naku = converter.candidates(for: "うごかなく", limit: 6, systemCandidateMode: .surface)
        XCTAssertTrue(naku.contains("動かなく"), "godan なく 一般: \(naku)")
    }

    // らいしゅうあたり: Wikipedia バイアスで 来襲(unigram6869)が 来週(7792)に勝ち 来襲当 が先頭
    // だった。来週 を時相名詞キャップ(6000)+単独の 当(あたり)を suppr で 来週あたり を先頭に。
    // 敵が来襲(文脈で来襲が正)と くじが当たり(当たり)は無傷。
    func testRegressionRealLMRaishuuAtari() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["あたり": ["当", "當", "中"]])
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let raishuu = converter.multiClauseCandidates(for: "らいしゅうあたり", systemCandidateMode: .surface)
        XCTAssertEqual(raishuu.first, "来週あたり", "multi=\(raishuu.prefix(4))")
        let teki = converter.multiClauseCandidates(for: "てきがらいしゅう", systemCandidateMode: .surface)
        XCTAssertEqual(teki.first, "敵が来襲", "multi=\(teki.prefix(3))")
    }

    // くるひ: 辞書は文語レア読みの 来日(wc11000)のみで {来日, くるひ} になっていた。
    // 来日(くるひ)を suppr、来る日 を seed 供給して 来る日 を先頭に。来日(らいにち)は無傷。
    func testRegressionRealLMKuruhiPrefersKuruHi() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["くるひ": ["来日"]])
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let single = converter.candidates(for: "くるひ", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "来る日", "single=\(single)")
        XCTAssertFalse(single.contains("来日"), "来日(くるひ)は抑制済みのはず: \(single)")
        let rainichi = converter.candidates(for: "らいにち", limit: 3, systemCandidateMode: .surface)
        XCTAssertTrue(rainichi.contains("来日"), "来日(らいにち)は無傷のはず: \(rainichi)")
    }

    // じゃなかった(コピュラ否定=かな正書): エンジンはかな最良だが keepKana=false で実機バーだけ
    // じゃ無かった が先頭に繰り上がっていた(提示層かな降格)。コピュラ否定末尾規則で維持。
    func testRegressionRealLMJanakattaKeepsKana() throws {
        try prepareRealLMDictionary()
        let multi = converter.multiClauseCandidates(for: "じゃなかった", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "じゃなかった", "multi=\(multi.prefix(3))")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "じゃなかった"))
        // じゃなくて は multi の単一かな結果が唯一の候補供給。退行しないこと
        let janakute = converter.multiClauseCandidates(for: "じゃなくて", systemCandidateMode: .surface)
        XCTAssertEqual(janakute.first, "じゃなくて", "multi=\(janakute.prefix(3))")
    }

    // かわいいね: カタカナ強調 カワイイ/交ぜ書き カワイい(Sudachi収穫)は suppr 済みだが、実機では
    // curated いいね(床1500)が 川+いいね 分割を作り かな かわいいね に勝っていた(ろーま事件と同型。
    // 追加語彙を読まない素のテストでは再現しない)。処方箋どおり かわいいね も curated 化して
    // 文節数の少ない方を勝たせる。実機忠実に追加語彙+抑制(可愛い=手動分を追加)をロードして検証。
    func testRegressionRealLMKawaiineKanaLeads() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary(includeSuppression: false)
        var suppression = try JSONDecoder().decode(
            [String: [String]].self,
            from: Data(contentsOf: URL(fileURLWithPath: "/Users/kusakabe/Git/ecritu/KeyboardExtension/InitialSupprHiddenVocabMigration.json"))
        )
        suppression["かわいい", default: []].append("可愛い")
        try injectSuppression(suppression)
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        // curated かわいいね が1ノード最良になると multi は単文節委譲([]。したんだが型)。
        // 表示は single 先頭=かわいいね になり、川いいね は multi から消える。
        let multi = converter.multiClauseCandidates(for: "かわいいね", systemCandidateMode: .surface)
        XCTAssertTrue(multi.isEmpty || multi.first == "かわいいね", "multi=\(multi.prefix(4))")
        XCTAssertFalse(multi.prefix(2).contains("川いいね"), "multi=\(multi.prefix(3))")
        let single = converter.candidates(for: "かわいいね", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "かわいいね", "single=\(single)")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "かわいいね"))
    }

    // さいしこみ(再仕込み。醤油の製法): 複合語が Sudachi 未収録で 祭祀+コミ の分割が勝っていた。
    // seed 供給で 再仕込み醤油/再仕込醤油 を組めるように(酒造所と同じ未収録パターン)。
    func testRegressionRealLMSaishikomiShouyu() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "さいしこみ", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "再仕込み", "single=\(single)")
        let multi = converter.multiClauseCandidates(for: "さいしこみしょうゆ", systemCandidateMode: .surface)
        XCTAssertTrue(
            multi.first == "再仕込み醤油" || multi.first == "再仕込醤油",
            "multi=\(multi.prefix(4))"
        )
        XCTAssertFalse(multi.prefix(3).contains(where: { $0.contains("コミ") || $0.contains("祭祀") }), "multi=\(multi.prefix(3))")
    }

    // とれたて: dict は 取れ立て(rank0。丸ごとエントリで合成ではない)が先頭で、常用の 採れたて が
    // 2番手だった。seed で 採れたて→獲れたて(未登録を供給)の順に。取れ立て は後方に残る。
    func testRegressionRealLMToretatePrefersToretate() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "とれたて", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(2)), ["採れたて", "獲れたて"], "single=\(single)")
        let multi = converter.multiClauseCandidates(for: "とれたてを", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "採れたてを", "multi=\(multi.prefix(4))")
    }

    // うまいね: 熟寝ね/熟睡ね=文語レア読み 熟寝/熟睡(うまい)+ね、ウマイネ=ウマ+イネ、馬イネ=
    // 馬+イネ の合成だった。カタカナ強調 ウマイ/ウマい と文語 熟寝/熟睡(うまい)を suppr、seed で
    // うまい→旨い→巧い、うまいね を curated 化(いいね/かわいいね と同処方)で分割に勝たせる。
    func testRegressionRealLMUmaineKanaLeads() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary(includeSuppression: true)
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let single = converter.candidates(for: "うまいね", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(3)), ["うまいね", "旨いね", "巧いね"], "single=\(single)")
        let multi = converter.multiClauseCandidates(for: "うまいね", systemCandidateMode: .surface)
        XCTAssertFalse(multi.prefix(2).contains(where: { $0.contains("イネ") || $0.contains("稲") }), "multi=\(multi.prefix(3))")
        // 熟睡(じゅくすい)は無傷
        XCTAssertEqual(converter.candidates(for: "じゅくすい", limit: 2, systemCandidateMode: .surface).first, "熟睡")
    }

    // にほんびーる: 歴史企業名の bigram 日本→麦酒(3904)が 日本ビール(未観測、ビール uni5354<
    // 麦酒6571)を逆転していた。麦酒(びーる)を bigram 借用遮断に追加し unigram 評価で ビール を勝たせる。
    func testRegressionRealLMNihonBeerPrefersBeer() throws {
        try prepareRealLMDictionary()
        let multi = converter.multiClauseCandidates(for: "にほんびーる", systemCandidateMode: .surface)
        XCTAssertEqual(Array(multi.prefix(2)), ["日本ビール", "日本麦酒"], "multi=\(multi.prefix(4))")
    }

    // なんしんとう: 親等 が辞書未収録(しんとう は浸透/新党/神道 のみ)で 何親等 が組めなかった。
    // 助数詞マップに しんとう→親等 を追加(なん/数字文脈: 2親等 も)。
    func testRegressionRealLMNanShintouSupplied() throws {
        try prepareRealLMDictionary()
        let nan = converter.candidates(for: "なんしんとう", limit: 3, systemCandidateMode: .surface)
        XCTAssertEqual(nan.first, "何親等", "single=\(nan)")
        let ni = converter.candidates(for: "にしんとう", limit: 4, systemCandidateMode: .surface)
        XCTAssertTrue(ni.contains("2親等") && ni.contains("二親等"), "single=\(ni)")
    }

    // ばかりだから: エンジンはかな最良だが keepKana=false で実機バーだけ交ぜ書き収穫 ばかリだから が
    // 先頭だった(提示層かな降格)。だから 剥がし規則+交ぜ書き ばかリ/カタカナ バカリ の suppr。
    func testRegressionRealLMBakariDakaraKeepsKana() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["ばかり": ["ばかリ", "バカリ"]])
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let multi = converter.multiClauseCandidates(for: "ばかりだから", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "ばかりだから", "multi=\(multi.prefix(3))")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "ばかりだから"))
    }

    // うらないしかしらないが: 頭(かしら=組の頭のレア用法、wc3305)+ないが の誤区切りが
    // 占い師頭ないが を作っていた。頭/カシラ(かしら)を suppr、慣用連語 しか知らない を curated 化して
    // 占いしか知らないが を勝たせる(実機忠実に追加語彙+抑制をロード)。
    func testRegressionRealLMUranaiShikaShiranai() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary(includeSuppression: true)
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let multi = converter.multiClauseCandidates(for: "うらないしかしらないが", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "占いしか知らないが", "multi=\(multi.prefix(4))")
        let shika = converter.multiClauseCandidates(for: "しかしらないが", systemCandidateMode: .surface)
        XCTAssertEqual(shika.first, "しか知らないが", "multi=\(shika.prefix(3))")
    }

    // いいだした: 言い出す が Sudachi 未収録(思い出す/飛び出す等は在る)で 飯田した 等の
    // 地名+した合成になっていた。misc pos五段(耐え抜く と同処方)で活用一括供給。動き出す も同穴。
    func testRegressionRealLMIidashitaSupplied() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary(includeSuppression: true)
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let iida = converter.candidates(for: "いいだした", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(iida.first, "言い出した", "single=\(iida)")
        let ugoki = converter.candidates(for: "うごきだした", limit: 3, systemCandidateMode: .surface)
        XCTAssertEqual(ugoki.first, "動き出した", "single=\(ugoki)")
    }

    // なったのは: なった の辞書エントリはカタカナ収穫 ナッタ のみで ナッタのは が先頭だった。
    // ナッタ を suppr、keepKana の のは剥がしに った→る 脱活用(なった→なる=rank0かな)を追加。
    func testRegressionRealLMNattanohaKanaLeads() throws {
        try prepareRealLMDictionary()
        // 実機忠実(追加語彙+抑制。素の環境では 綯ったのは=レア漢字が浮上して実機と一致しない)
        try loadDeviceAddedVocabulary(includeSuppression: true)
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let multi = converter.multiClauseCandidates(for: "なったのは", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "なったのは", "multi=\(multi.prefix(3))")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "なったのは"))
    }

    // さいやくだけおとして: だ|けおとして の誤分割(災厄だ+蹴落として)が だけ+落として に勝っていた。
    // コピュラ終止 だ 直後の動詞は文中非文法なのでペナルティ(汎用)。だけ(副助詞)側が勝つ。
    func testRegressionRealLMSaiyakuDakeOtoshite() throws {
        try prepareRealLMDictionary()
        let multi = converter.multiClauseCandidates(for: "さいやくだけおとして", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "災厄だけ落として", "multi=\(multi.prefix(4))")
        XCTAssertFalse(multi.prefix(3).contains(where: { $0.contains("蹴") }), "multi=\(multi.prefix(3))")
    }

    // じゅうりょうせい: dict 順で 重量制(rank0、LM無し)が 従量制(LM7369=課金方式で頻出)より先だった。
    func testRegressionRealLMJuuryouseiPrefersJuuryousei() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "じゅうりょうせい", limit: 3, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(2)), ["従量制", "重量制"], "single=\(single)")
    }

    // だよ/でしょ: コピュラ だ のカタカナ収穫 ダ(rank0/wc4406=かな だ5733より安)が ダよ/ダけど
    // 一族の根本 → suppr。でしょ(でしょう縮約)は で+初/ショ/諸 の単漢字分割に負けていた →
    // 口語終止クラスタへ。両方 keepKana のコピュラ終助詞末尾規則で提示層でもかな維持。
    func testRegressionRealLMDayoDeshoKanaLeads() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary(includeSuppression: true)
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let dayo = converter.candidates(for: "だよ", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(dayo.first, "だよ", "single=\(dayo)")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "だよ"))
        let imin = converter.multiClauseCandidates(for: "いみんでしょ", systemCandidateMode: .surface)
        XCTAssertEqual(imin.first, "移民でしょ", "multi=\(imin.prefix(4))")
        let sou = converter.multiClauseCandidates(for: "そうでしょ", systemCandidateMode: .surface)
        XCTAssertEqual(sou.first, "そうでしょ", "multi=\(sou.prefix(3))")
    }

    // どうだ(副詞どう+コピュラだ、かな正書): 合成は 道だ/同だ が先行しかな識別が末尾に沈んでいた。
    // seed 供給+keepKana(だ剥がしで語幹のかな識別が辞書先頭=どう)で先頭維持。
    func testRegressionRealLMDoudaKanaLeads() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "どうだ", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "どうだ", "single=\(single)")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "どうだ"))
    }

    // そうだった(副詞そう+コピュラだ過去、かな正書): エンジンはかな最良を選ぶが提示層の
    // かな降格で 層だった/僧だった 等が先行していた。コピュラ活用尾剥がし(だった/だし…)で
    // 語幹の辞書先頭(純カタカナ除く)がかな(そう)なら keepKana で先頭維持。
    func testRegressionRealLMSoudattaKanaLeads() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "そうだった", limit: 5, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "そうだった", "single=\(single)")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "そうだった"))
    }

    // よね(終助詞クラスタ、かな正書): かな は辞書/LM未収録で末尾に沈み 与根/人名合成が
    // 先行していた。seed(かな掲載)で先頭供給、keepKana は systemCandidates の seed 合流で成立。
    func testRegressionRealLMYoneKanaLeads() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "よね", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "よね", "single=\(single)")
        XCTAssertEqual(single.dropFirst().first, "米", "single=\(single)")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "よね"))
    }

    // ぱしゃっと: 連文節の ぱ+シャット(カタカナ語)合成が先頭を奪っていた。オノマトペ
    // 〜っと(4文字以上の全かな)のかな正書クランプで排除(きっと/ずっと=3文字は対象外)。
    func testRegressionRealLMPashattoKanaLeads() throws {
        try prepareRealLMDictionary()
        let multi = converter.multiClauseCandidates(for: "ぱしゃっと", systemCandidateMode: .surface)
        XCTAssertTrue(multi.isEmpty || multi.first == "ぱしゃっと", "multi=\(multi.prefix(3))")
        XCTAssertFalse(multi.contains("ぱシャット"), "multi=\(multi.prefix(3))")
        let single = converter.candidates(for: "ぱしゃっと", limit: 3, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "ぱしゃっと", "single=\(single)")
    }

    // くすりやさん: 連文節の 薬+や(並列助詞)+さん 分割が 薬屋さん(単文節は正)を奪っていた。
    // や→さん の直接遷移は 〜屋さん の誤分割でしか起きない(田中や佐藤さん は間に名詞)ため
    // 汎用ペナルティで排除。花屋さん も同時に改善。
    func testRegressionRealLMKusuriyasanPrefersYasan() throws {
        try prepareRealLMDictionary()
        let kusuri = converter.multiClauseCandidates(for: "くすりやさん", systemCandidateMode: .surface)
        XCTAssertEqual(kusuri.first, "薬屋さん", "multi=\(kusuri.prefix(4))")
        let hana = converter.multiClauseCandidates(for: "はなやさん", systemCandidateMode: .surface)
        XCTAssertEqual(hana.first, "花屋さん", "multi=\(hana.prefix(4))")
    }

    // これでいい: コレ(これ rank1)/イイ(いい rank2)のカタカナ収穫と 謂(いい=単独では使わない読み、
    // rank17)を suppr、keepKana に 〜でいい 末尾規則。これでいい がかな先頭に。
    func testRegressionRealLMKoredeiiKanaLeads() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary(includeSuppression: true)
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        // single は供給なし(表示は multi のみ)。multi のかな先頭と keepKana を確認する。
        let multi = converter.multiClauseCandidates(for: "これでいい", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "これでいい", "multi=\(multi.prefix(4))")
        XCTAssertFalse(multi.prefix(3).contains(where: { $0.contains("コレ") || $0.contains("イイ") || $0.contains("謂") }), "multi=\(multi.prefix(3))")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "これでいい"))
    }

    // きょうはなして: 経(お経4660)/教派(6278)が 今日(5041)に unigram で競り勝っていた。
    // 今日 を時相名詞キャップ(4300=昨日と同値)へ。
    func testRegressionRealLMKyouHanashite() throws {
        try prepareRealLMDictionary()
        let multi = converter.multiClauseCandidates(for: "きょうはなして", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "今日話して", "multi=\(multi.prefix(4))")
    }

    // くいかた: 未収録の合成で基底 くい の辞書順(杭/悔い/…/食い)がそのまま出ていた。
    // 食い方 を seed 供給(杭 の基底並び替えは 杭を打つ に波及するため per-form)。
    func testRegressionRealLMKuikataPrefersKuikata() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "くいかた", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "食い方", "single=\(single)")
    }

    // せんを: dict が セン/せん/先/千… の順で頻出の 線 が top8 圏外だった。seed 線→千→先+
    // セン suppr。かな せんを は 線を が最良になれば提示層が自然に末尾チップ化する。
    func testRegressionRealLMSenwoPrefersSen() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "せんを", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "線を", "single=\(single)")
        let hiku = converter.multiClauseCandidates(for: "せんをひく", systemCandidateMode: .surface)
        XCTAssertEqual(hiku.first, "線を引く", "multi=\(hiku.prefix(3))")
    }

    // きょうはなして(実機忠実): misc curated きょうは→今日は(床1500)が きょうは|なして の分割を
    // 固定し 今日話して を消していた(ろーま事件型。素の環境では再現しない)。今日 の時相キャップ
    // (2345)で curated の元目的(教派 対策)が不要になったため撤去。今日は/今日は寒い は維持。
    func testRegressionRealLMKyouHanashiteDeviceFidelity() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary(includeSuppression: true)
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let multi = converter.multiClauseCandidates(for: "きょうはなして", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "今日話して", "multi=\(multi.prefix(4))")
        let kyouha = converter.multiClauseCandidates(for: "きょうは", systemCandidateMode: .surface)
        XCTAssertEqual(kyouha.first, "今日は", "multi=\(kyouha.prefix(3))")
        let samui = converter.multiClauseCandidates(for: "きょうはさむい", systemCandidateMode: .surface)
        XCTAssertEqual(samui.first, "今日は寒い", "multi=\(samui.prefix(3))")
    }

    // まんえん: 直前が数字確定のとき 万円 を先頭へ(まんえん を助数詞マップに追加)。
    // 何万円/数万円 は大数位複合で既対応。文脈なしの まんえん は 蔓延 先頭のまま(妥当)。
    func testRegressionRealLMManenDigitContext() throws {
        try prepareRealLMDictionary()
        XCTAssertEqual(converter.candidates(for: "なんまんえん", limit: 2, systemCandidateMode: .surface).first, "何万円")
        XCTAssertEqual(converter.candidates(for: "すうまんえん", limit: 2, systemCandidateMode: .surface).first, "数万円")
        let boosted = KanaKanjiConverter.digitContextCounterBoostedCandidates(
            ["蔓延", "万延", "万円", "まんえん"],
            reading: "まんえん",
            precedingCharacter: "5"
        )
        XCTAssertEqual(boosted.first, "万円", "digit文脈で万円が先頭: \(boosted)")
        // 数字文脈なしは並び不変
        let plain = KanaKanjiConverter.digitContextCounterBoostedCandidates(
            ["蔓延", "万延", "万円"],
            reading: "まんえん",
            precedingCharacter: "。"
        )
        XCTAssertEqual(plain.first, "蔓延", "非数字文脈は不変: \(plain)")
        // 文脈なしでも 万円 は 蔓延 に次ぐ2番手(seed)
        let single = converter.candidates(for: "まんえん", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(2)), ["蔓延", "万円"], "single=\(single)")
    }

    // カタカナ強調表記/交ぜ書きの3値モード([抑制/リスト後方/同列]、既定=抑制)。
    // 抑制: ウマイ/まん延 が候補から消える。後方: 末尾に残る。同列: 従来順位。
    // 外来語(パン)と seed 掲載カタカナ(イカ)は常に対象外。
    func testRegressionRealLMScriptVariantModes() throws {
        try prepareRealLMDictionary()
        // 既定(抑制)
        let umaiSuppressed = converter.candidates(for: "うまい", limit: 8, systemCandidateMode: .surface)
        XCTAssertFalse(umaiSuppressed.contains("ウマイ") || umaiSuppressed.contains("ウマい"), "\(umaiSuppressed)")
        let manenSuppressed = converter.candidates(for: "まんえん", limit: 10, systemCandidateMode: .surface)
        XCTAssertFalse(manenSuppressed.contains("まん延"), "\(manenSuppressed)")
        // 外来語/seed掲載は残る
        let pan = converter.candidates(for: "ぱん", limit: 5, systemCandidateMode: .surface)
        XCTAssertTrue(pan.contains("パン"), "\(pan)")
        let ika = converter.candidates(for: "いか", limit: 6, systemCandidateMode: .surface)
        XCTAssertTrue(ika.contains("イカ"), "\(ika)")
        // 後方
        converter.setKatakanaEmphasisCandidateMode(.demote)
        converter.setMazegakiCandidateMode(.demote)
        let umaiDemoted = converter.candidates(for: "うまい", limit: 20, systemCandidateMode: .surface)
        XCTAssertTrue(umaiDemoted.contains("ウマイ"), "\(umaiDemoted)")
        XCTAssertTrue(umaiDemoted.firstIndex(of: "ウマイ")! > umaiDemoted.firstIndex(of: "旨い")!, "\(umaiDemoted)")
        let manenDemoted = converter.candidates(for: "まんえん", limit: 12, systemCandidateMode: .surface)
        XCTAssertTrue(manenDemoted.contains("まん延"), "\(manenDemoted)")
        XCTAssertTrue(manenDemoted.firstIndex(of: "まん延")! > manenDemoted.firstIndex(of: "蔓延")!, "\(manenDemoted)")
        // 同列
        converter.setKatakanaEmphasisCandidateMode(.normal)
        converter.setMazegakiCandidateMode(.normal)
        let umaiNormal = converter.candidates(for: "うまい", limit: 8, systemCandidateMode: .surface)
        XCTAssertTrue(umaiNormal.contains("ウマイ"), "\(umaiNormal)")
        // 連文節: 抑制時に交ぜ書き/強調ノードが最良経路に出ない
        converter.setKatakanaEmphasisCandidateMode(.suppress)
        converter.setMazegakiCandidateMode(.suppress)
        let panyasan = converter.multiClauseCandidates(for: "ぱんやさん", systemCandidateMode: .surface)
        XCTAssertEqual(panyasan.first, "パン屋さん", "外来語パンは連文節でも無傷: \(panyasan.prefix(3))")
    }

    // しきいき: 色域(カラーマネジメント)が Sudachi/LM とも未収録で 識閾 しか出なかった。seed 供給。
    func testRegressionRealLMShikiikiSupplied() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "しきいき", limit: 3, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(2)), ["色域", "識閾"], "single=\(single)")
    }

    // さいどあげる: 彩度(uni7143)が サイド/再度(5500級=正当な頻出語)に負け 彩度上げる が候補に
    // 出なかった。連語機構(ひび+入る と同じ)を特定表層優先に一般化し、あげ/さげ 直前の さいど を
    // 彩度 に。再度確認/サイドを固める 等の非連語文脈は無影響。
    func testRegressionRealLMSaidoAgeru() throws {
        try prepareRealLMDictionary()
        let ageru = converter.multiClauseCandidates(for: "さいどあげる", systemCandidateMode: .surface)
        XCTAssertEqual(ageru.first, "彩度上げる", "multi=\(ageru.prefix(4))")
        let wo = converter.multiClauseCandidates(for: "さいどをさげて", systemCandidateMode: .surface)
        XCTAssertEqual(wo.first, "彩度を下げて", "multi=\(wo.prefix(4))")
        // 非連語文脈は不変(元々の サイド/再度 が上位、彩度 は先頭化しない)
        let kakunin = converter.multiClauseCandidates(for: "さいどかくにん", systemCandidateMode: .surface)
        XCTAssertNotEqual(kakunin.first, "彩度確認", "multi=\(kakunin.prefix(3))")
        XCTAssertTrue(kakunin.prefix(2).contains("再度確認") || kakunin.prefix(2).contains("サイド確認"), "multi=\(kakunin.prefix(3))")
    }

    // こんないろかなー: 色化(色+化=A単位bigram借用3023)と 色香+なー が こんな色かなー を消していた。
    // 化(か)の借用遮断+かなー を口語終止クラスタ常設ノード化+文末終助詞の最長一致ボーナスで是正。
    func testRegressionRealLMKonnaIroKanaa() throws {
        try prepareRealLMDictionary()
        let multi = converter.multiClauseCandidates(for: "こんないろかなー", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "こんな色かなー", "multi=\(multi.prefix(4))")
        XCTAssertFalse(multi.prefix(3).contains(where: { $0.contains("色化") || $0.contains("色香") }), "multi=\(multi.prefix(3))")
    }

    // とにかくやってみる: エンジンはかな最良だが keepKana=false で実機バーだけ先頭かなが末尾へ
    // 退避(手動抑制で 遣って が消えた実機では 演って/犯って が繰り上がる)。curated かな識別
    // (やってみる 等)末尾+辞書かな語前半 の一般規則で提示層かな維持。
    func testRegressionRealLMTonikakuYattemiru() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary(includeSuppression: true)
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let multi = converter.multiClauseCandidates(for: "とにかくやってみる", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "とにかくやってみる", "multi=\(multi.prefix(4))")
        XCTAssertTrue(
            converter.shouldKeepKanaIdentityLeading(for: "とにかくやってみる"),
            "curated末尾+かな語前半で提示層かな維持すべき"
        )
    }

    // しって: 報る(しる)は Sudachi の疑義読み収穫(報せる=しらせる/報いる=むくいる のみが正)。
    // 基底を suppr し活用 報って にも伝播させる。じゃないから: 文末の接続助詞 から が終助詞集合に
    // 無く EOS で 空(から) に負けていた(じゃない空)。から/ので を言いさし終止として集合へ。
    func testRegressionRealLMShitteJanaikara() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["しる": ["報る"]])
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let shitte = converter.candidates(for: "しって", limit: 8, systemCandidateMode: .surface)
        XCTAssertFalse(shitte.contains("報って"), "single=\(shitte)")
        // 先頭のかな識別 しって は提示層で末尾チップ化されるため、変換としては 知って が先頭
        XCTAssertEqual(Array(shitte.prefix(2)), ["しって", "知って"], "single=\(shitte)")
        let janai = converter.multiClauseCandidates(for: "じゃないから", systemCandidateMode: .surface)
        XCTAssertEqual(janai.first, "じゃないから", "multi=\(janai.prefix(4))")
        XCTAssertFalse(janai.prefix(3).contains("じゃない空"), "multi=\(janai.prefix(3))")
        // 提示層でもかな先頭維持(から剥がし→じゃない 再帰)
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "じゃないから"))
    }

    // きていされちゃった: 受身+ちゃう縮約(されちゃう/されちゃった/されちゃって)のサ変規則が欠落し、
    // 規定(suru登録済み)なのに 規定去れちゃった 等の合成しか出なかった(とけば/ちゃおう と同族)。
    func testRegressionRealLMSarechattaSupplied() throws {
        try prepareRealLMDictionary()
        // 規則追加で全読みが1ノード導出可能になり multi は単文節委譲([])。表示は single 先頭
        let multi = converter.multiClauseCandidates(for: "きていされちゃった", systemCandidateMode: .surface)
        XCTAssertTrue(multi.isEmpty || multi.first == "規定されちゃった", "multi=\(multi.prefix(4))")
        let single = converter.candidates(for: "きていされちゃった", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "規定されちゃった", "single=\(single)")
        XCTAssertFalse(single.contains(where: { $0.contains("去れ") }), "single=\(single)")
    }

    // ていしょく: ユーザ指定順(定食→定職→停職→抵触→牴触→牴觸→觝触)。底触/低触 は誤エントリsuppr。
    func testRegressionRealLMTeishokuOrdering() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["ていしょく": ["底触", "低触"]])
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let single = converter.candidates(for: "ていしょく", limit: 12, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(7)), ["定食", "定職", "停職", "抵触", "牴触", "牴觸", "觝触"], "single=\(single)")
        XCTAssertFalse(single.contains("底触") || single.contains("低触"), "single=\(single)")
    }

    // おおい: 辞書 rank 順で 覆い が先頭だったが、word_cost/LM とも 多い が最頻。
    // seed で 多い→覆い→大井→蓋。かな おおい は seed 非掲載の自動末尾降格、大炊 は後続。
    // ※おおいた の 多いた 先頭は seed 導入前からの既存問題(合成が辞書 大分 に勝つ)で本修正とは独立。
    func testRegressionRealLMOoiOrdering() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let single = converter.candidates(for: "おおい", limit: 12, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(3)), ["多い", "覆い", "大井"], "single=\(single)")
        XCTAssertFalse(single.prefix(6).contains("おおい"), "single=\(single)")
        XCTAssertFalse(single.prefix(4).contains("大炊"), "single=\(single)")
        let multi = converter.multiClauseCandidates(for: "ひとがおおい", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "人が多い", "multi=\(multi.prefix(4))")
        let oita = converter.candidates(for: "おおいた", limit: 4, systemCandidateMode: .surface)
        XCTAssertTrue(oita.prefix(4).contains("大分"), "oita=\(oita)")
    }

    // のだろうか: 単漢字合成(乃だろうか/幅だろうか 等)がかな識別より先行していた。
    // したんだが と同型の seed かな供給。keepKana は seed 掲載で自動成立。
    func testRegressionRealLMNodaroukaKanaFirst() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let single = converter.candidates(for: "のだろうか", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "のだろうか", "single=\(single)")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "のだろうか"))
    }

    // おおいた: 多く(い形容詞連用形の収穫、クラス無し)が語尾く推論で五段動詞と誤判定され、
    // 書く→書いた 式に 多いた(非文法)が導出されて辞書語 大分 に勝っていた。同語幹のい形
    // (多い=adjective-i)実在時は五段く推論を止める一般ゲートを追加(近く/早く 等も同時に防護)。
    func testRegressionRealLMOoitaNoUngrammaticalAita() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let oita = converter.candidates(for: "おおいた", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(oita.first, "大分", "oita=\(oita)")
        XCTAssertFalse(oita.contains("多いた"), "oita=\(oita)")
        let chikaita = converter.candidates(for: "ちかいた", limit: 8, systemCandidateMode: .surface)
        XCTAssertFalse(chikaita.contains("近いた"), "chikaita=\(chikaita)")
        // 正当な五段く動詞の活用と い形容詞の正書活用は不変
        let kaita = converter.candidates(for: "かいた", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(kaita.first, "書いた", "kaita=\(kaita)")
        let ookatta = converter.candidates(for: "おおかった", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(ookatta.first, "多かった", "ookatta=\(ookatta)")
        let ookunatta = converter.candidates(for: "おおくなった", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(ookunatta.first, "多くなった", "ookunatta=\(ookunatta)")
    }

    // いくつあるかも: エンジンはかな最良(LM: いくつ4779<幾つ5884+いくつ→ある観測済みで
    // 一般機構は全文脈機能。いくつある/いくつか/いくつも 全てかな先頭)だが、keepKana が
    // かも/か 末尾で不成立→提示層退避で 幾つあるかも が実機先頭。疑問終端(かも/かな/かと/か)
    // 剥がし→再帰の一般則を追加(から と同型)。
    func testRegressionRealLMIkutsuArukamoKanaFirst() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let multi = converter.multiClauseCandidates(for: "いくつあるかも", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "いくつあるかも", "multi=\(multi.prefix(4))")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "いくつあるかも"))
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "いくつか"))
        // 活用連鎖の防護ケースは不変(全面再帰にしない根拠)
        XCTAssertFalse(converter.shouldKeepKanaIdentityLeading(for: "かってみようかな"))
        // 単独・類似パターンもかな先頭(一般機構の確認)
        let single = converter.candidates(for: "いくつ", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "いくつ", "single=\(single)")
        let ikutsumo = converter.multiClauseCandidates(for: "いくつも", systemCandidateMode: .surface)
        XCTAssertEqual(ikutsumo.first, "いくつも", "ikutsumo=\(ikutsumo.prefix(3))")
    }

    // うち: かなが正書(ユーザ方針: うち>家 全般)。家(うち)は正当な読みだが LM
    // (家4250/家→で1685)がかな(4319/2148)を上回り 家で水を使う 等が全文脈で先頭化していた。
    // seed かな先頭+連文節 opt-in(にほん/おん と同機構)。
    func testRegressionRealLMUchiKanaFirst() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let single = converter.candidates(for: "うち", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(2)), ["うち", "家"], "single=\(single)")
        let multi = converter.multiClauseCandidates(for: "うちでみずをつかう", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "うちで水を使う", "multi=\(multi.prefix(4))")
        XCTAssertTrue(multi.contains("家で水を使う"), "multi=\(multi.prefix(4))")
        // 別読みは不変: 打ち合わせ(うちあわせ)/内側(うちがわ)/家(いえ)
        let uchiawase = converter.candidates(for: "うちあわせ", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(uchiawase.first, "打ち合わせ", "uchiawase=\(uchiawase)")
        let uchigawa = converter.candidates(for: "うちがわ", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(uchigawa.first, "内側", "uchigawa=\(uchigawa)")
        let ie = converter.candidates(for: "いえ", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(ie.first, "家", "ie=\(ie)")
    }

    // ってことかと: エンジンはかな最良(こと 優先の一般機構=LM+述語直後ペナルティは機能済み)
    // だが、keepKana の形式名詞照合が終助詞付き(〜かと/かな/か)で不成立→提示層がかな退避し
    // って事かと が実機バー先頭になっていた。疑問終端を剥がしてから形式名詞照合する。
    func testRegressionRealLMTteKotoKatoKanaFirst() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let multi = converter.multiClauseCandidates(for: "ってことかと", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "ってことかと", "multi=\(multi.prefix(4))")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "ってことかと"))
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "ってこと"))
        // こと 優先の既存一般機構の確認(名詞直後=仕事のこと でも かな が先頭)
        let multi2 = converter.multiClauseCandidates(for: "しごとのこと", systemCandidateMode: .surface)
        XCTAssertEqual(multi2.first, "仕事のこと", "multi2=\(multi2.prefix(4))")
    }

    // ほとんどそう: 文末の そう(推量・指示)はかなが正書だが、層/僧/草 の単漢字が EOS で
    // 勝っていた。終助詞クラスタに そう を追加(漢字減点は全漢字表層のみ=沿う/添う 免除)+
    // keepKana の終助詞剥がしに そう(語幹 ほとんど=辞書かな語)。
    func testRegressionRealLMHotondoSouKanaFirst() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let multi = converter.multiClauseCandidates(for: "ほとんどそう", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "ほとんどそう", "multi=\(multi.prefix(4))")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "ほとんどそう"))
        // に沿う(動詞、う含み=全漢字でない)は減点対象外。best は にそう(に→そう4769<
        // に→沿う4785 の既存LM選好、変種枠に 沿う が入らないのも既存挙動)
        let sou = converter.multiClauseCandidates(for: "きやくにそう", systemCandidateMode: .surface)
        XCTAssertEqual(sou.first, "規約にそう", "sou=\(sou.prefix(4))")
    }









    // ときどき: 副詞のかな正書(ユーザ方針)。時々 が基底 word_cost 順で先頭だった。
    func testRegressionRealLMTokidokiKanaFirst() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let single = converter.candidates(for: "ときどき", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(2)), ["ときどき", "時々"], "single=\(single)")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "ときどき"))
    }

    // それぞれの: 其々/其其/夫夫(基底 word_cost 6684 同値)がかな(7654/LM4329=最頻)より
    // 先頭だった。seed かな先頭、合成(それぞれの)にも語幹順で波及。
    func testRegressionRealLMSorezoreKanaFirst() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let single = converter.candidates(for: "それぞれ", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(2)), ["それぞれ", "其々"], "single=\(single)")
        let sorezoreNo = converter.candidates(for: "それぞれの", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(sorezoreNo.first, "それぞれの", "sorezoreNo=\(sorezoreNo)")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "それぞれの"))
        let multi = converter.multiClauseCandidates(for: "それぞれのいけん", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "それぞれの意見", "multi=\(multi.prefix(4))")
    }

    // おす/めす: 例外的に使うカタカナ(オス/メス)が、雄5712/雌6247 の LM 僅差で
    // 「代替あり=強調」とクラス抑制され候補から消えていた。seed 掲載で保護。
    func testRegressionRealLMOsuMesuKatakanaProtected() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let osu = converter.candidates(for: "おす", limit: 16, systemCandidateMode: .surface)
        XCTAssertEqual(Array(osu.prefix(3)), ["押す", "推す", "オス"], "osu=\(osu)")
        XCTAssertTrue(osu.prefix(6).contains("雄"), "osu=\(osu)")
        let mesu = converter.candidates(for: "めす", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(mesu.prefix(3)), ["メス", "雌", "召す"], "mesu=\(mesu)")
    }

    // ちがうくに: ジャンク辞書エントリ 違うい(ちがうい、adjective-i収穫ミス)の く形派生
    // 違うく(ちがうく)+に が 違う+国(11659<12505)を逆転し、別分節のため変種にも 国 が
    // 出なかった。違うい を誤エントリ suppr(危うい/ものうい は正当な Xうい 形容詞で無傷)。
    func testRegressionRealLMChigauKuniOrdering() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["ちがうい": ["違うい"]])
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let multi = converter.multiClauseCandidates(for: "ちがうくに", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "違う国", "multi=\(multi.prefix(4))")
        XCTAssertTrue(multi.contains("違う国"), "multi=\(multi.prefix(4))")
        // 正当な Xうい 形容詞は無傷
        let ayaui = converter.candidates(for: "あやうく", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(ayaui.first, "危うく", "ayaui=\(ayaui)")
    }

    // このどうがだと: 道(どう)が主読み みち の bigram(この→道/道→が)を借用して
    // この道がだと の分断を作っていた(どうがだと 単独は 動画だと で正常=文頭 bigram なし)。
    // bigram 借用遮断リストに 道(どう)/同(どう) を追加(銅(どう)=正当な単独名詞は不変)。
    func testRegressionRealLMKonoDougaBigramBorrow() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let multi = converter.multiClauseCandidates(for: "このどうがだと", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "この動画だと", "multi=\(multi.prefix(4))")
        // 主読み側(このみち)は不変
        let michi = converter.multiClauseCandidates(for: "このみちをいく", systemCandidateMode: .surface)
        XCTAssertEqual(michi.first, "この道を行く", "michi=\(michi.prefix(4))")
    }

    // もっとあるはず: エンジンはかな最良だが keepKana=false で もっとある筈 が実機先頭。
    // はず を形式名詞リストへ(筈 は現代ではほぼかな正書。述語直後の漢字ペナルティも効く)。
    func testRegressionRealLMAruhazuKanaFirst() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let multi = converter.multiClauseCandidates(for: "もっとあるはず", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "もっとあるはず", "multi=\(multi.prefix(3))")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "もっとあるはず"))
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "あるはず"))
    }

    // さかえまちのかいじょう: 栄町のか以上(のか+以上 分割)が の+会場 に勝っていた。
    // clean 状態は 2386(読み跨ぎ遮断)で解消済みだが、実機は misc curated のか(床1500)が
    // の+か を激安化して再現(ろー/こうこ と同じ短curated断片型)。跨ぎ常用語判定の接頭に
    // の を追加し、のか の中の の+かいじょう(会場)を検出して床外し。文末の のか(行くのか)は
    // 跨ぐ先が無く床維持。
    func testRegressionRealLMSakaemachiKaijou() throws {
        try prepareRealLMDictionary()
        converter.store.addUserEntry(reading: "のか", candidate: "のか") // misc curated 相当
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let multi = converter.multiClauseCandidates(for: "さかえまちのかいじょう", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "栄町の会場", "multi=\(multi.prefix(4))")
        XCTAssertFalse(multi.contains(where: { $0.contains("か以上") }), "multi=\(multi.prefix(4))")
        // 文末の のか(curated の正当用途)は不変
        let ikunoka = converter.multiClauseCandidates(for: "なんでいくのか", systemCandidateMode: .surface)
        XCTAssertTrue(ikunoka.first?.hasSuffix("のか") ?? false, "ikunoka=\(ikunoka.prefix(4))")
    }

    // せき: かな識別が先頭・席(LM5494=最頻)が7番手だった。seed 席→関→咳→堰→責→籍。
    // 助数詞マップに せき=[席,隻] 追加(6確定→せき で 席 先頭、ろくせき→6席 複合も有効化)。
    func testRegressionRealLMSekiOrderingAndCounter() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let single = converter.candidates(for: "せき", limit: 12, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(6)), ["席", "関", "咳", "堰", "責", "籍"], "single=\(single)")
        XCTAssertFalse(single.prefix(8).contains("せき"), "single=\(single)")
        // 直前確定が数字 → 席 が先頭(隻=船舶の助数詞は2番手)
        let boosted = KanaKanjiConverter.digitContextCounterBoostedCandidates(
            single, reading: "せき", precedingCharacter: "6")
        XCTAssertEqual(boosted.first, "席", "boosted=\(boosted.prefix(4))")
        // 数字+せき の複合(ろくせき→6席)
        let rokuseki = converter.candidates(for: "ろくせき", limit: 10, systemCandidateMode: .surface)
        XCTAssertTrue(rokuseki.contains("6席"), "rokuseki=\(rokuseki)")
    }

    // 読み跨ぎ unigram 借用の一般遮断: LM unigram は表層キーで読みを持たず、レア読みが
    // 主読みの実績にタダ乗りしていた。この読みの word_cost − 全読み最安 ≥2500 なら
    // unigram を信用せず word_cost を下限に(読み3字以上=既存短span床の免除穴)。
    // 後(うしろ、wc8932/min3995)が uni3529 を借用して 後ろ(uni5677)に勝つのが実例。
    func testRegressionRealLMCrossReadingUnigramBorrowBlocked() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let multi = converter.multiClauseCandidates(for: "うしろにならぶ", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "後ろに並ぶ", "multi=\(multi.prefix(4))")
        XCTAssertFalse(multi.prefix(3).contains(where: { $0.hasPrefix("後に") }), "multi=\(multi.prefix(4))")
        // 単一読みの正直な高コスト語(解像度=乖離0)は無傷
        let kaizoudo = converter.multiClauseCandidates(for: "かいぞうどがたかい", systemCandidateMode: .surface)
        XCTAssertEqual(kaizoudo.first, "解像度が高い", "kaizoudo=\(kaizoudo.prefix(4))")
        // あと 読み(主読み側)の 後 は無傷
        let ato = converter.multiClauseCandidates(for: "あとでいく", systemCandidateMode: .surface)
        XCTAssertTrue(ato.first?.hasPrefix("後で") ?? false, "ato=\(ato.prefix(4))")
    }

    // みて: かな識別先頭+文語命令形(充て/満て=満つ/充つ の五段つ命令形。充て は あて 用途の
    // LM6266 を読み跨ぎ借用)が 見て より前に浮上していた。seed で 見-族をユーザ指定順に固定。
    func testRegressionRealLMMiteOrdering() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let single = converter.candidates(for: "みて", limit: 12, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(5)), ["見て", "観て", "診て", "看て", "視て"], "single=\(single)")
        XCTAssertFalse(single.prefix(8).contains("充て"), "single=\(single)")
        XCTAssertFalse(single.prefix(8).contains("満て"), "single=\(single)")
        XCTAssertFalse(single.prefix(8).contains("みて"), "single=\(single)")
        // 合成(みてくれ 等)にも基底順で波及
        let multi = converter.multiClauseCandidates(for: "しゃしんをみて", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "写真を見て", "multi=\(multi.prefix(4))")
    }

    // これやすい: 活用合成(ら抜き基底 これる)の最安が旧字体 來れる(wc9641)で
    // 來れやすい が先頭だった。來れる は suppr(來 の人名は別読みで無傷)、seed
    // これる=[これる, 来れる] で これ 系を強く、ユーザ第一希望の これ安い(指示詞+形容詞)は
    // misc curated 供給。テストは注入で misc 相当を再現。
    func testRegressionRealLMKoreyasuiOrdering() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["これる": ["來れる"]])
        converter.store.addUserEntry(reading: "これやすい", candidate: "これ安い")
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let single = converter.candidates(for: "これやすい", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(2)), ["これ安い", "これやすい"], "single=\(single)")
        XCTAssertFalse(single.contains(where: { $0.contains("來") }), "single=\(single)")
        // 連文節の これ+形容詞 は不変
        let kai = converter.multiClauseCandidates(for: "これかいやすい", systemCandidateMode: .surface)
        XCTAssertEqual(kai.first, "これ買いやすい", "kai=\(kai.prefix(4))")
    }

    // そうりょう: ユーザ指定順(送料→総量→総領→惣領→爽涼→蒼龍→蒼竜)。
    // 送料(EC頻出)が word_cost 7404 で沈んでいた。
    func testRegressionRealLMSouryouOrdering() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let single = converter.candidates(for: "そうりょう", limit: 10, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(7)), ["送料", "総量", "総領", "惣領", "爽涼", "蒼龍", "蒼竜"], "single=\(single)")
        // 助詞付きの連文節も読み別ボーナス(そうりょう=4200。Wikipedia の観測 bigram
        // 総量→は700/の875 等の最大不利 ≈3950 を超える値)で 送料 を全文脈先頭に
        // (ユーザ要望: 学習なしで一発。総量/総領 等は後続候補に残る)
        for particle in ["が", "の", "は", "を"] {
            let multi = converter.multiClauseCandidates(for: "そうりょう" + particle, systemCandidateMode: .surface)
            XCTAssertEqual(multi.first, "送料" + particle, "particle=\(particle) multi=\(multi.prefix(4))")
        }
        let no = converter.candidates(for: "そうりょうの", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(no.first, "送料の", "no=\(no)")
    }

    // とんかつや: とんかつ屋 は Sudachi 未収録の複合。トン+勝谷(かつや の名前収穫 wc9770)の
    // 分割が とんかつ+屋 に勝っていた。seed(単文節)+misc curated(連文節)で供給。
    func testRegressionRealLMTonkatsuyaSupply() throws {
        try prepareRealLMDictionary()
        converter.store.addUserEntry(reading: "とんかつや", candidate: "とんかつ屋")
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let single = converter.candidates(for: "とんかつや", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "とんかつ屋", "single=\(single)")
        XCTAssertFalse(single.prefix(4).contains(where: { $0.contains("勝谷") || $0.contains("勝矢") }), "single=\(single)")
        let multi = converter.multiClauseCandidates(for: "とんかつやにいく", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "とんかつ屋に行く", "multi=\(multi.prefix(4))")
        // とんかつ 単独は不変
        let tonkatsu = converter.candidates(for: "とんかつ", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(tonkatsu.first, "とんかつ", "tonkatsu=\(tonkatsu)")
    }

    // してくれないかな(あ): エンジンはかな最良(授受クランプ機能済み)だが keepKana が
    // かな/かなあ 付きで不成立→提示層退避で して紅かな/して暮れないかなあ が実機先頭。
    // 疑問終端剥がし(かなあ 追加)後の語幹への授受照合を追加。
    func testRegressionRealLMShiteKurenaikanaKanaFirst() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let kana = converter.multiClauseCandidates(for: "してくれないかな", systemCandidateMode: .surface)
        XCTAssertEqual(kana.first, "してくれないかな", "kana=\(kana.prefix(4))")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "してくれないかな"))
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "してくれないかなあ"))
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "おしえてあげようかな"))
        // ている縮約(くれてる)等の未列挙活用も一般判定(prefix述語)で通る
        let kureteru = converter.multiClauseCandidates(for: "してくれてるのね", systemCandidateMode: .surface)
        XCTAssertEqual(kureteru.first, "してくれてるのね", "kureteru=\(kureteru.prefix(4))")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "してくれてるのね"))
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "まってくれてた"))
        // コピュラ推量+か(どこだろうか)も同じ穴 — 剥がし後のコピュラ末尾照合で成立
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "どこだろうか"))
        let doko = converter.multiClauseCandidates(for: "どこだろうか", systemCandidateMode: .surface)
        XCTAssertTrue(doko.isEmpty || doko.first == "どこだろうか", "doko=\(doko.prefix(4))")
        // 活用連鎖の防護は不変
        XCTAssertFalse(converter.shouldKeepKanaIdentityLeading(for: "かってみようかな"))
    }

    // いわれたがわ: 基底 いう のかな LM 優先(という 分割由来で いう3293≪言う4804)が
    // 受身形に波及し、連文節で かな いわれた が 言われた と OOV 7200 タイ+列挙順先勝ち
    // (→いわれた側)。受身形は 言われ* が正書のため per-form seed で矯正。
    func testRegressionRealLMIwaretagawaKanjiFirst() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let multi = converter.multiClauseCandidates(for: "いわれたがわ", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "言われた側", "multi=\(multi.prefix(4))")
        let single = converter.candidates(for: "いわれた", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(3)), ["言われた", "云われた", "謂われた"], "single=\(single)")
        let iwarete = converter.multiClauseCandidates(for: "いわれてみれば", systemCandidateMode: .surface)
        XCTAssertEqual(iwarete.first, "言われてみれば", "iwarete=\(iwarete.prefix(4))")
        // 能動形のかな優先は不変(という 等)
        let toiu = converter.multiClauseCandidates(for: "そういうこと", systemCandidateMode: .surface)
        XCTAssertEqual(toiu.first, "そういうこと", "toiu=\(toiu.prefix(4))")
    }

    // ひさべつ: 被差別 は Sudachi core/LM とも無し(被・差別 は単独実在)の完全供給欠落。
    // 単文節は seed、連文節は seed ノード(dictUnknown 8700)が 日(ひ)+差別 分割に負けるため
    // misc curated 化(殻付き/仕方ない と同型)。テストは addUserEntry で misc 相当を注入。
    func testRegressionRealLMHisabetsuSupply() throws {
        try prepareRealLMDictionary()
        converter.store.addUserEntry(reading: "ひさべつ", candidate: "被差別")
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let single = converter.candidates(for: "ひさべつ", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "被差別", "single=\(single)")
        let multi = converter.multiClauseCandidates(for: "ひさべつぶらく", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "被差別部落", "multi=\(multi.prefix(4))")
    }

    // かげつ: 数量詞合成(何か月/3か月/数か月)の助数詞表層は辞書順を使うため、
    // 箇月(rank0。か月 は rank7)が先頭化していた。seed で公用文主流の か月 を先頭に。
    func testRegressionRealLMKagetsuKagakiFirst() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let nan = converter.candidates(for: "なんかげつ", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(nan.first, "何か月", "nan=\(nan)")
        let san = converter.candidates(for: "さんかげつ", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(san.first, "3か月", "san=\(san)")
        let suu = converter.candidates(for: "すうかげつ", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(suu.first, "数か月", "suu=\(suu)")
    }

    // えんさつ: 辞書未収録。助数詞マップに えんさつ=[円札] を追加(なんえんさつ→何円札/
    // 数字文脈ブースト/算用合成)し、紙幣の通称(漢数字)は seed で先頭固定。
    // sacoche の個別4件(千円札/二千円札/五千円札/一万円札)は撤去。
    func testRegressionRealLMEnsatsuCounter() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        for (r, expected) in [("せんえんさつ", "千円札"), ("にせんえんさつ", "二千円札"),
                              ("ごせんえんさつ", "五千円札"), ("いちまんえんさつ", "一万円札")] {
            let single = converter.candidates(for: r, limit: 6, systemCandidateMode: .surface)
            XCTAssertEqual(single.first, expected, "r=\(r) single=\(single)")
        }
        let nan = converter.multiClauseCandidates(for: "なんえんさつ", systemCandidateMode: .surface)
        XCTAssertEqual(nan.first, "何円札", "nan=\(nan.prefix(3))")
        let boosted = KanaKanjiConverter.digitContextCounterBoostedCandidates(
            ["猿さつ", "円札"], reading: "えんさつ", precedingCharacter: "0")
        XCTAssertEqual(boosted.first, "円札")
    }

    // さいこうほう: 最高峰(唯一の辞書エントリ)が wc10759 の harvest 降格で合成
    // (最高法/最高方)に負けて先頭陥落していた(縞模様 2156 と同型)。seed で指定順に固定。
    func testRegressionRealLMSaikouhouOrdering() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let single = converter.candidates(for: "さいこうほう", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(4)), ["最高峰", "再興法", "最高法", "最高方"], "single=\(single)")
        let multi = converter.multiClauseCandidates(for: "せかいさいこうほう", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "世界最高峰", "multi=\(multi.prefix(4))")
    }

    // ちょうせい: 調整(LM5147=最頻)が word_cost 順で 調製 に、dict rank で 長生(地名収穫)
    // にも沈んでいた。ユーザ指定順の seed 固定。
    func testRegressionRealLMChouseiOrdering() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let single = converter.candidates(for: "ちょうせい", limit: 14, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(12)),
            ["調整", "調製", "町制", "調性", "長征", "町政", "町勢", "長逝", "朝政", "潮声", "長生", "聴政"],
            "single=\(single)")
        // サ変派生にも基底順で波及
        let suru = converter.candidates(for: "ちょうせいする", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(suru.first, "調整する", "suru=\(suru)")
    }

    // ていかいにゅう: 低介入 が未収録で 低下+移入 の誤分割が先頭だった。seed 供給。
    func testRegressionRealLMTeikainyuSupply() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let single = converter.candidates(for: "ていかいにゅう", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "低介入", "single=\(single)")
        let multi = converter.multiClauseCandidates(for: "ていかいにゅう", systemCandidateMode: .surface)
        XCTAssertTrue(multi.isEmpty || multi.first == "低介入", "multi=\(multi.prefix(4))")
    }

    // たいし: 対し(対する連用形、LM4011=最頻)が辞書エントリに無く 太史/対支 等が
    // 先頭だった。seed 対し→大使→太子。
    func testRegressionRealLMTaishiOrdering() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let single = converter.candidates(for: "たいし", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(3)), ["対し", "大使", "太子"], "single=\(single)")
        // に対し の連文節は不変
        let multi = converter.multiClauseCandidates(for: "これにたいし", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "これに対し", "multi=\(multi.prefix(4))")
    }

    // はやってる: 流行ってる を文節先頭の第一候補に(かな識別/実機の は+やる系 分割より前)。
    func testRegressionRealLMHayatteruOrdering() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let single = converter.candidates(for: "はやってる", limit: 5, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "流行ってる", "single=\(single)")
    }

    // しぼうさん: 脂肪酸 が wc13906 の harvest 降格で 名前+さん 合成に負けて8番手だった
    // (最高峰 と同型)。seed 掲載=降格免除で先頭復帰。
    func testRegressionRealLMShibousanOrdering() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let single = converter.candidates(for: "しぼうさん", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "脂肪酸", "single=\(single)")
    }

    // しないことになってる: 基底列挙で 綯う(レア)経由の 綯ってる が先行していた。
    // misc curated なってる+keepKana(なってる/なっちゃう 末尾)で かな先頭を固定。
    func testRegressionRealLMNatteruKanaFirst() throws {
        try prepareRealLMDictionary()
        converter.store.addUserEntry(reading: "なってる", candidate: "なってる") // misc 相当
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let multi = converter.multiClauseCandidates(for: "しないことになってる", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "しないことになってる", "multi=\(multi.prefix(3))")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "しないことになってる"))
    }

    // もうあった: かな副詞(もう/まだ)直後の存在動詞かな過去も文節先頭同等にクランプ+
    // keepKana の ある/いる 剥がしに あった/いた を追加。気があった 等の が 直後は不変。
    func testRegressionRealLMMouattaKanaFirst() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let multi = converter.multiClauseCandidates(for: "もうあった", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "もうあった", "multi=\(multi.prefix(3))")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "もうあった"))
        let kigaatta = converter.multiClauseCandidates(for: "きがあった", systemCandidateMode: .surface)
        XCTAssertFalse(kigaatta.first == "きがあった", "kigaatta=\(kigaatta.prefix(3))")
    }

    // しまった: 感動詞・補助動詞のかなが正書だが、基底 しまう の辞書順(仕舞う 先行)が
    // 派生に波及し 仕舞った が先頭だった。ユーザ指定順の seed(してしまった は不変)。
    func testRegressionRealLMShimattaOrdering() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let single = converter.candidates(for: "しまった", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(3)), ["しまった", "閉まった", "締った"], "single=\(single)")
        let multi = converter.multiClauseCandidates(for: "してしまった", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "してしまった", "multi=\(multi.prefix(3))")
    }





    // うまいのだ: 説明のコピュラ のだ 付きでかなが末尾落ちしていた(keepKana のだ系未対応+
    // 派生基底のLM降格が seed かな先頭を覆す+カタカナ強調語幹 ウマい の合成素通りの三重奏)。
    // 2402 で一般対応: keepKana に のだ/んだ/のです/んです、seed 先頭かな読みは LM 降格免除、
    // postfix/活用派生の基底に isKatakanaEmphasisBaseCandidate フィルタ。
    func testRegressionRealLMUmainodaKanaLeading() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let single = converter.candidates(for: "うまいのだ", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "うまいのだ", "single=\(single)")
        XCTAssertTrue(single.contains("旨いのだ"), "single=\(single)")
        XCTAssertFalse(single.contains("ウマいのだ"), "single=\(single)")
        XCTAssertFalse(single.contains("ウマイのだ"), "single=\(single)")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "うまいのだ"))
    }

    // すごいなあ: keepKana の終助詞剥がしに なあ 系長形が無く、かなが末尾退避していた(2403)
    func testRegressionRealLMSugoinaaKanaLeading() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "すごいなあ"))
        let single = converter.candidates(for: "すごいなあ", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "すごいなあ", "single=\(single)")
    }

    // すごい: かな正書が主流(LM かな6214<凄い6883)なのに dict は 凄い0 が先頭だった。seed 供給
    func testRegressionRealLMSugoiKanaFirst() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let single = converter.candidates(for: "すごい", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(2)), ["すごい", "凄い"], "single=\(single)")
    }

    // 2404 バッチ(9件報告)の単文節側: おおきく(供給+大い/大く suppr)、より(寄り>縒り)、
    // かかせれば(per-form seed)、おりたたんで(基底読み間順序を seed 供給)、なんて(何て供給)、
    // やつ(かな先頭)
    func testRegressionRealLMBatch2404Single() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["おおきい": ["大い"], "おおきく": ["大く"]])
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let ookiku = converter.candidates(for: "おおきく", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(ookiku.first, "大きく", "ookiku=\(ookiku)")
        XCTAssertFalse(ookiku.contains("大く"), "ookiku=\(ookiku)")
        let yori = converter.candidates(for: "より", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(Array(yori.prefix(3)), ["より", "寄り", "縒り"], "yori=\(yori)")
        let kakasereba = converter.candidates(for: "かかせれば", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(Array(kakasereba.prefix(3)), ["書かせれば", "描かせれば", "欠かせれば"], "kakasereba=\(kakasereba)")
        let oritatande = converter.candidates(for: "おりたたんで", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(Array(oritatande.prefix(3)), ["折り畳んで", "折畳んで", "折りたたんで"], "oritatande=\(oritatande)")
        let nante = converter.candidates(for: "なんて", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(Array(nante.prefix(2)), ["なんて", "何て"], "nante=\(nante)")
        let yatsu = converter.candidates(for: "やつ", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(Array(yatsu.prefix(2)), ["やつ", "奴"], "yatsu=\(yatsu)")
    }

    // 2404 バッチの連文節側(実機相当: misc/ajout/suppr 読み込み): ってやつで/みんなこの/
    // みなやってる のかな先頭、にたやつがある の 似た(た断片チェーン遮断+seed 供給)。
    // 変種の curated かな識別区間 delta 補正で 皆やってる が2番手に入る。
    func testRegressionRealLMBatch2404Multi() throws {
        try prepareRealLMDictionary()
        let supprData = try Data(contentsOf: URL(fileURLWithPath: "/Users/kusakabe/Git/ecritu/KeyboardExtension/InitialSupprHiddenVocabMigration.json"))
        UserDefaults(suiteName: defaultsSuiteName)?.set(supprData, forKey: "ÉcrituSuppr_Vocab")
        for name in ["InitialAjoutVocabMigration", "InitialMiscVocabMigration"] {
            let data = try Data(contentsOf: URL(fileURLWithPath: "/Users/kusakabe/Git/ecritu/KeyboardExtension/\(name).json"))
            let dict = try JSONDecoder().decode([String: [String]].self, from: data)
            for (r, cs) in dict { for c in cs.reversed() { converter.store.addUserEntry(reading: r, candidate: c) } }
        }
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let tteyatsude = converter.multiClauseCandidates(for: "ってやつで", systemCandidateMode: .surface)
        XCTAssertEqual(tteyatsude.first, "ってやつで", "tteyatsude=\(tteyatsude)")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "ってやつで"))
        let minnakono = converter.multiClauseCandidates(for: "みんなこの", systemCandidateMode: .surface)
        XCTAssertEqual(minnakono.first, "みんなこの", "minnakono=\(minnakono)")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "みんなこの"))
        let minayatteru = converter.multiClauseCandidates(for: "みなやってる", systemCandidateMode: .surface)
        XCTAssertEqual(Array(minayatteru.prefix(2)), ["みなやってる", "皆やってる"], "minayatteru=\(minayatteru)")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "みなやってる"))
        let nitayatsu = converter.multiClauseCandidates(for: "にたやつがある", systemCandidateMode: .surface)
        XCTAssertEqual(nitayatsu.first, "似たやつがある", "nitayatsu=\(nitayatsu)")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "にたやつがある"))
    }

    // これで/それで 等の指示代名詞+で はかなが正書(keepKana)。学習済みのかな識別が
    // 学習リセットで消えると素の穴が露出していた(2406)。で の一般剥がしは名詞+で
    // (ずかんで)を巻き込むため、かな正書の指示代名詞語幹に限定。
    func testRegressionRealLMKoredeKanaLeading() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "これで"))
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "それで"))
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "ここで"))
        XCTAssertFalse(converter.shouldKeepKanaIdentityLeading(for: "ずかんで"))
        let single = converter.candidates(for: "これで", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "これで", "single=\(single)")
    }

    // もったいない: 辞書に読みエントリが無い合成専用のかな形容詞。ない 系剥がし語幹の
    // 辞書かな×LM優位(もったい7272<勿体7715)を keepKana の根拠に追加(2406)
    func testRegressionRealLMMottainaiKanaLeading() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "もったいない"))
        let single = converter.candidates(for: "もったいない", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "もったいない", "single=\(single)")
    }

    // ちかい: 誓(レア名詞収穫)が dict rank0 で 近い より先頭だった。seed 供給(2406)
    func testRegressionRealLMChikaiOrder() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let single = converter.candidates(for: "ちかい", limit: 5, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(2)), ["近い", "誓い"], "single=\(single)")
    }

    // つかってれば: て形+れば(ている已然縮約)が活用供給に無く、れば 単独区間が
    // word_costs の レバ(肝)しか持たないため 使って+レバ が先頭化していた(2406)
    func testRegressionRealLMTsukattereba() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let single = converter.candidates(for: "つかってれば", limit: 5, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "使ってれば", "single=\(single)")
        XCTAssertFalse(single.contains("使ってレバ"), "single=\(single)")
    }

    // たってたら/じかんがたってたら: て形+たら(ていた已然縮約)が活用供給に無く、
    // ら 単独区間が 等(ら)に化けて 経ってた+等 が先頭化していた(2407)
    func testRegressionRealLMTattetara() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let single = converter.candidates(for: "たってたら", limit: 5, systemCandidateMode: .surface)
        XCTAssertTrue(single.contains("経ってたら"), "single=\(single)")
        XCTAssertFalse(single.contains(where: { $0.hasSuffix("等") }), "single=\(single)")
        let multi = converter.multiClauseCandidates(for: "じかんがたってたら", systemCandidateMode: .surface)
        // 2408: 時間経過の名詞直後は 経つ を最良に(立つ/建つ に減点)
        XCTAssertEqual(multi.first, "時間が経ってたら", "multi=\(multi)")
        XCTAssertFalse(multi.contains(where: { $0.contains("等") }), "multi=\(multi)")
        let noParticle = converter.multiClauseCandidates(for: "じかんたってたら", systemCandidateMode: .surface)
        XCTAssertEqual(noParticle.first, "時間経ってたら", "noParticle=\(noParticle)")
    }

    // たぶんさいしょは: BOS 直後の単独助動詞た 断片(た+分+最初は)が A単位 unigram の
    // 安さで たぶん(1語)を阻んでいた。格助詞直後と同様に文頭の た も遮断(2407)
    func testRegressionRealLMTabunSaishoha() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let multi = converter.multiClauseCandidates(for: "たぶんさいしょは", systemCandidateMode: .surface)
        // 2408: たぶん はかな先頭(ユーザー指定。seed+連文節ボーナス)
        XCTAssertEqual(Array(multi.prefix(2)), ["たぶん最初は", "多分最初は"], "multi=\(multi)")
        XCTAssertFalse(multi.contains(where: { $0.hasPrefix("た分") || $0.hasPrefix("た文") }), "multi=\(multi)")
    }

    // やらないくせに: 曲(くせ wc10067=収穫底値、最安読み きょく4472)が きょく用途の
    // bigram(ない→曲 4185)を借用して やらない曲に が先頭化。bigram分岐だけが
    // 収穫底値降格/最安読み乖離ガードを素通りしていた穴を一般則で遮断(2423)
    func testRegressionKuseniNotHijackedByKyokuBigram() throws {
        try prepareRealLMDictionary()
        let multi = converter.multiClauseCandidates(for: "やらないくせに", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "やらないくせに", "multi=\(multi.prefix(5))")
        XCTAssertFalse(multi.prefix(4).contains("やらない曲に"), "multi=\(multi.prefix(5))")
        XCTAssertTrue(multi.contains("やらない癖に"), "癖 は温存: \(multi.prefix(5))")
        // 提示層のかな識別退避を防ぐ(false だと実機バーで 演らないくせに が繰り上がり
        // かなが末尾に落ちる。2424)
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "やらないくせに"))
    }

    // うちに: 海事レア語 打ち荷/打荷(wc7864=底値未満で降格対象外・LM未収録)が
    // 家に/内に の合成より先頭に来ていた。suppr(非表示)で恒久除去(2423)
    func testRegressionUchiniRareCargoSuppressed() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["うちに": ["打ち荷", "打荷"]])
        let single = converter.candidates(for: "うちに", limit: 10, systemCandidateMode: .surface)
        XCTAssertFalse(single.contains("打ち荷"), "single=\(single)")
        XCTAssertFalse(single.contains("打荷"), "single=\(single)")
        XCTAssertTrue(single.contains("家に") && single.contains("内に"), "single=\(single)")
    }

    // ろぐはったら: 辞書に はった の動詞形が無く全て活用派生供給で、ルール定義順の連結だと
    // はう系(這った/匍った/匐った)がTopK3を占有し はる系(貼った/張った)が圏外だった。
    // 基底読み族をunigram最小値で整列する構造対応(基底読み間順序の5例目。2423)
    func testRegressionHattaraSuppliesHaruFamily() throws {
        try prepareRealLMDictionary()
        let multi = converter.multiClauseCandidates(for: "ろぐはったら", systemCandidateMode: .surface)
        // OOV同点のタイブレークは優勢族代表の先行ボーナスが破る(seed はる で 貼>張)
        XCTAssertEqual(multi.first, "ログ貼ったら", "multi=\(multi.prefix(6))")
        XCTAssertTrue(multi.contains(where: { $0.contains("這ったら") }), "這う系も温存: \(multi.prefix(6))")
    }

    // あとの: レア姓 阿刀(あとの、wc9770=底値降格の閾値未満)が rank0 で先頭に居座り、
    // 合成順も 跡>後 だった。suppr+完全一致時のみ末尾再供給(二段構え)+seed あと で
    // ユーザー指定順 {後の, 跡の, あとの, 痕の, 趾の} に(2437)
    func testRegressionAtonoOrdering() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["あとの": ["阿刀"]])
        let single = converter.candidates(for: "あとの", limit: 24, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(5)), ["後の", "跡の", "あとの", "痕の", "趾の"], "single=\(single)")
        // 二段構え: 完全一致の単文節では 阿刀 が末尾側に残る
        XCTAssertTrue(single.contains("阿刀"), "阿刀 は完全一致時のみ末尾: \(single)")
    }

    // きあげ: 生揚げ は辞書に なまあげ 読みのみ(醤油の 生揚げ=きあげ が未登録)。
    // misc curated で 生揚げ/生揚げ醤油 を供給(2436)
    func testRegressionKiageSuppliedFromMisc() throws {
        try prepareRealLMDictionary()
        converter.store.addUserEntry(reading: "きあげ", candidate: "生揚げ")
        converter.store.addUserEntry(reading: "きあげしょうゆ", candidate: "生揚げ醤油")
        XCTAssertEqual(
            converter.candidates(for: "きあげ", limit: 8, systemCandidateMode: .surface).first,
            "生揚げ"
        )
        XCTAssertEqual(
            converter.candidates(for: "きあげしょうゆ", limit: 8, systemCandidateMode: .surface).first,
            "生揚げ醤油"
        )
    }

    // とうきょうじゅう: 中(じゅう wc9550、最安読み6173から3377乖離)が読み跨ぎ借用ガード
    // (2386/2423)の巻き添えで bigram(東京→中4120)/unigram を没収され、重/銃/十 に
    // 負けていた。正当な生産的接尾なので seed 掲載で免除+名詞接辞 じゅう→中 を供給(2435)
    func testRegressionTokyoJuuRangeSuffix() throws {
        try prepareRealLMDictionary()
        let multi = converter.multiClauseCandidates(for: "とうきょうじゅう", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "東京中", "multi=\(multi.prefix(4))")
        // 単独 じゅう は 十 が先頭のまま
        let solo = converter.candidates(for: "じゅう", limit: 5, systemCandidateMode: .surface)
        XCTAssertEqual(solo.first, "十", "solo=\(solo)")
    }

    // いくない 等: い形容詞「いい」は語幹活用しない(連用・過去は よ- 系)のに、
    // いい 基底から 良く/善く(いく)/良くない(いくない) 等の非標準形が派生されていた。
    // いい 基底の adjectiveI 派生を一般ブロック(2434)
    func testRegressionIiBaseAdjectiveNotInflected() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "いくない", limit: 8, systemCandidateMode: .surface)
        XCTAssertFalse(single.contains("良くない") || single.contains("善くない"), "single=\(single)")
        // よくない(正書経路)は無傷
        let yoku = converter.candidates(for: "よくない", limit: 8, systemCandidateMode: .surface)
        XCTAssertTrue(yoku.contains("良くない"), "yoku=\(yoku)")
    }

    // いくかちないね: 述語直後の かち は形式名詞的な 価値(〜する価値ない)が主だが、
    // 短span床の僅差で 勝(6795)<価値(7191) となり 行く勝ないね が先頭だった。
    // 述語直後の 価値 にボーナス(1500。800では不足を実測)(2434)
    func testRegressionPredicateKachiPrefersValue() throws {
        try prepareRealLMDictionary()
        let multi = converter.multiClauseCandidates(for: "いくかちないね", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "行く価値ないね", "multi=\(multi.prefix(4))")
    }

    // きょうとじん: 人(にん/じん)は読み跨ぎ借用の遮断で unigram+床評価になり、同音の
    // 陣/尽/腎 に負けて 京都人 が出なかった。名詞接辞 じん→人 の供給+地域接尾直後の
    // 人(じん) ボーナス(産 と同機構)(2434)
    func testRegressionKyotoJinSuffix() throws {
        try prepareRealLMDictionary()
        let multi = converter.multiClauseCandidates(for: "きょうとじん", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "京都人", "multi=\(multi.prefix(4))")
    }

    // 3さつめ: 冊 が助数詞マップに無く、序数フォールバックも直接ヒット(佐津目 wc9219)で
    // 走らないため 冊目 が出なかった。さつ→冊 をマップへ追加し、め選好パスで助数詞語幹の
    // 目/め を補生成(こめ=米/だいめ=代目 は誤爆ガードで無傷)(2434)
    func testRegressionSatsumeCounterOrdinal() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "さつめ", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(2)), ["冊目", "冊め"], "single=\(single)")
        XCTAssertTrue(single.contains("佐津目"), "佐津目 は温存: \(single)")
        let kome = converter.candidates(for: "こめ", limit: 5, systemCandidateMode: .surface)
        XCTAssertFalse(kome.contains("個目"), "kome=\(kome)")
        let daime = converter.candidates(for: "だいめ", limit: 5, systemCandidateMode: .surface)
        XCTAssertEqual(daime.first, "代目", "daime=\(daime)")
    }

    // のよねー: 四(よ)が数詞複合のA単位bigram(の→四)を借用し の四ねー が先頭だった。
    // 入側デニー(人/頭/日/化 と同機構)に 四(よ) を追加、終助詞クラスタへ のよね/のよねー
    // も追加(2434)
    func testRegressionNoyoneFinalParticleCluster() throws {
        try prepareRealLMDictionary()
        let multi = converter.multiClauseCandidates(for: "のよねー", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "のよねー", "multi=\(multi.prefix(4))")
    }

    // おいた/おいたのよ/おいてある: (1) のね/のよ クランプが辞書形述語限定で、た形
    // (置いた=活用派生)後に効かず お+板野+よ が先頭化。活用派生直後も対象に。
    // (2) 活用派生順が 老いる系>置く系 で 置いた が沈む — 族昇格opt-in(おく)+seed。
    // ユーザー指定順: おいた={置いた, 老いた, おいた}(2434)
    func testRegressionOitaFamilyAndExplanatoryClamp() throws {
        try prepareRealLMDictionary()
        let solo = converter.candidates(for: "おいた", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(solo.prefix(3)), ["置いた", "老いた", "おいた"], "solo=\(solo)")
        let noyo = converter.multiClauseCandidates(for: "おいたのよ", systemCandidateMode: .surface)
        XCTAssertEqual(Array(noyo.prefix(2)), ["置いたのよ", "老いたのよ"], "noyo=\(noyo.prefix(4))")
        let tearu = converter.candidates(for: "おいてある", limit: 8, systemCandidateMode: .surface)
        if let oku = tearu.firstIndex(of: "置いてある"), let oi = tearu.firstIndex(of: "老いてある") {
            XCTAssertTrue(oku < oi, "tearu=\(tearu)")
        } else {
            XCTFail("置いてある/老いてある が両方あるべき: \(tearu)")
        }
    }

    // じゃんぐりあ: 補助語彙(ryukyu)供給の ジャングリア(wc7500)が、LM未収録カタカナへの
    // カタカナ化ペナルティ(3000)に巻き込まれ、じゃん+グリア(神経膠細胞、LM収録)の分割に
    // 負けていた。手選別の補助語彙由来カタカナはペナルティ免除(2433)
    func testRegressionJungriaSupplementalKatakanaExempt() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "じゃんぐりあ", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "ジャングリア", "single=\(single)")
        let multi = converter.multiClauseCandidates(for: "じゃんぐりあ", systemCandidateMode: .surface)
        XCTAssertNotEqual(multi.first, "じゃんグリア", "multi=\(multi.prefix(4))")
    }

    // にちめ: Sudachi core の 日圧(にち、企業略称の固有名詞収穫 wc10000)が序数
    // フォールバックの語幹に混ざり 日圧め/日圧目 を合成していた。suppr(にち→日圧)+
    // フォールバックの語幹抑制フィルタ(日圧目 は読み末尾め≠表層末尾目で合成後フィルタが
    // 効かないため語幹側で遮断)(2430)
    func testRegressionNichimeSuppressedStemNotComposed() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["にち": ["日圧"]])
        let single = converter.candidates(for: "にちめ", limit: 15, systemCandidateMode: .surface)
        XCTAssertFalse(single.contains("日圧め") || single.contains("日圧目"), "single=\(single)")
        XCTAssertTrue(single.contains("日目"), "日目 は健在: \(single)")
    }

    // め/目 選好(コンテナー設定 première…/un peu …)。既定: 序数=漢字『目』先
    // (告示 通則4)、形容詞語幹=『目』を出さない(かな『め』のみ。付表の語1)(2428)
    func testRegressionMeSuffixPreferences() throws {
        try prepareRealLMDictionary()
        // 形容詞・既定(OFF): 目形(薄目/多目)を出さない。名詞の 大目 は無傷
        let usumeOff = converter.candidates(for: "うすめ", limit: 10, systemCandidateMode: .surface)
        XCTAssertFalse(usumeOff.contains("薄目"), "usumeOff=\(usumeOff)")
        XCTAssertTrue(usumeOff.contains("薄め"), "usumeOff=\(usumeOff)")
        let oomeOff = converter.candidates(for: "おおめ", limit: 10, systemCandidateMode: .surface)
        XCTAssertFalse(oomeOff.contains("多目"), "oomeOff=\(oomeOff)")
        XCTAssertTrue(oomeOff.contains("大目"), "大目(名詞)は無傷: \(oomeOff)")
        // 形容詞・ON: かな め が先(薄目 rank0 でも)、辞書に目形が無い組(狭め)は補生成
        converter.setAdjectiveMeKanjiCandidatesEnabled(true)
        let usume = converter.candidates(for: "うすめ", limit: 10, systemCandidateMode: .surface)
        if let me = usume.firstIndex(of: "薄め"), let kanji = usume.firstIndex(of: "薄目") {
            XCTAssertTrue(me < kanji, "usume=\(usume)")
        } else {
            XCTFail("薄め/薄目 が両方あるべき: \(usume)")
        }
        let semame = converter.candidates(for: "せまめ", limit: 10, systemCandidateMode: .surface)
        if let me = semame.firstIndex(of: "狭め"), let kanji = semame.firstIndex(of: "狭目") {
            XCTAssertTrue(me < kanji, "semame=\(semame)")
        } else {
            XCTFail("狭め/狭目(補生成)が両方あるべき: \(semame)")
        }
        converter.setAdjectiveMeKanjiCandidatesEnabled(false)
        // 序数・既定(目先): 辞書丸ごと語(三番目)が先頭のまま、め形も補生成されて後続
        // (両形とも常に出す — スイッチは順序のみ。2430)
        let sanbanKanji = converter.candidates(for: "さんばんめ", limit: 10, systemCandidateMode: .surface)
        XCTAssertEqual(sanbanKanji.first, "三番目", "sanbanKanji=\(sanbanKanji)")
        if let kanji = sanbanKanji.firstIndex(of: "三番目"), let me = sanbanKanji.firstIndex(of: "三番め") {
            XCTAssertTrue(kanji < me, "sanbanKanji=\(sanbanKanji)")
        } else {
            XCTFail("目先モードでも 三番め が出るべき: \(sanbanKanji)")
        }
        let banmeKanji = converter.candidates(for: "ばんめ", limit: 10, systemCandidateMode: .surface)
        XCTAssertTrue(banmeKanji.contains("番め"), "目先モードでも 番め が出るべき: \(banmeKanji)")
        // 序数・め先モード: 辞書に無い 三番め/番め を補生成して 目形より先に
        converter.setOrdinalMeKanjiPreferred(false)
        let sanban = converter.candidates(for: "さんばんめ", limit: 10, systemCandidateMode: .surface)
        if let me = sanban.firstIndex(of: "三番め"), let kanji = sanban.firstIndex(of: "三番目") {
            XCTAssertTrue(me < kanji, "sanban=\(sanban)")
        } else {
            XCTFail("三番め(補生成)/三番目 が両方あるべき: \(sanban)")
        }
        let banme = converter.candidates(for: "ばんめ", limit: 10, systemCandidateMode: .surface)
        if let me = banme.firstIndex(of: "番め"), let kanji = banme.firstIndex(of: "番目") {
            XCTAssertTrue(me < kanji, "banme=\(banme)")
        } else {
            XCTFail("番め(補生成)/番目 が両方あるべき: \(banme)")
        }
        converter.setOrdinalMeKanjiPreferred(true)
    }

    // 3かいほど: ほど が素通り接尾辞に無く かい+ほど の単文節合成が存在しないため、
    // 数字直後ブースト(回ほど を前置)の対象候補が供給されていなかった。ほど を
    // postfixPassthroughSuffixes へ追加(2425)
    func testRegressionKaihodoComposesCounter() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "かいほど", limit: 20, systemCandidateMode: .surface)
        XCTAssertTrue(single.contains("回ほど"), "single=\(single.prefix(8))")
        let boosted = KanaKanjiConverter.digitContextCounterBoostedCandidates(
            single,
            reading: "かいほど",
            precedingCharacter: "3"
        )
        XCTAssertEqual(boosted.first, "回ほど", "boosted=\(boosted.prefix(4))")
    }

    // はりわすれ: SudachiDict に 貼り(はり)エントリ自体が無く(張り/針/梁 のみ)、
    // 貼り忘れ が候補化できなかった(供給欠落型)。misc curated で複合語を供給(2425)
    func testRegressionHariwasureSuppliedFromMisc() throws {
        try prepareRealLMDictionary()
        converter.store.addUserEntry(reading: "はりわすれ", candidate: "貼り忘れ")
        converter.store.addUserEntry(reading: "はりわすれ", candidate: "張り忘れ")
        converter.store.addUserEntry(reading: "はりわすれる", candidate: "貼り忘れる")
        converter.store.addUserEntry(reading: "はりわすれる", candidate: "張り忘れる")
        let single = converter.candidates(for: "はりわすれ", limit: 10, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(2)), ["貼り忘れ", "張り忘れ"], "single=\(single.prefix(5))")
        // 張り忘れ 等の既存合成はクリーンテスト環境では再現しない(実機のみの合成経路)。
        // 本修正は curated の追加供給のみで既存経路に触れないため、先頭の検証に留める。
        // 一段 curated からの活用派生(貼り忘れた)も供給される
        let ta = converter.multiClauseCandidates(for: "はりわすれた", systemCandidateMode: .surface)
        XCTAssertEqual(ta.first, "貼り忘れた", "ta=\(ta.prefix(4))")
    }

    // おやどりの: 丁寧接頭辞合成(お+宿り→御宿り)が実辞書語 親鳥/親鶏 と同点(共に
    // LM未収録=dictUnknown 8700)になり連文節先頭を奪っていた。同スパンに実辞書語が
    // あるスパンでは合成ノードを+200後置(2421)
    func testRegressionOyadoriPrefersDictWordOverPoliteComposition() throws {
        try prepareRealLMDictionary()
        let multi = converter.multiClauseCandidates(for: "おやどりの", systemCandidateMode: .surface)
        XCTAssertEqual(Array(multi.prefix(2)), ["親鳥の", "親鶏の"], "multi=\(multi.prefix(5))")
        // 合成の 御宿りの は変種として残ってよい(先頭でなければ可)
        let solo = converter.candidates(for: "おやどり", limit: 5, systemCandidateMode: .surface)
        XCTAssertEqual(Array(solo.prefix(2)), ["親鳥", "親鶏"], "solo=\(solo)")
    }

    // おおいのはどれ: 辞書の連濁収穫動詞読み(どる→取る/捕る/獲る…)から活用エンジンが
    // どれ→取れ を派生し、多いのは取れ/獲れ/捕れ が どれ より先頭に出ていた。連濁は
    // 複合語内でのみ生じ文節頭に立たないため、連濁収穫基底からの活用派生を除去(2419)
    func testRegressionRendakuVerbBaseNotInflected() throws {
        try prepareRealLMDictionary()
        let multi = converter.multiClauseCandidates(for: "おおいのはどれ", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "多いのはどれ", "multi=\(multi.prefix(5))")
        let solo = converter.candidates(for: "どれ", limit: 10, systemCandidateMode: .surface)
        XCTAssertFalse(solo.contains("取れ"), "solo=\(solo)")
        // 正当な濁音動詞(出る: 清音読みエントリ自体が無い)の活用は温存
        let deta = converter.candidates(for: "でた", limit: 5, systemCandidateMode: .surface)
        XCTAssertTrue(deta.contains("出た"), "deta=\(deta)")
    }

    // それはいくつ: かな主流の いくつ(uni 4779≪幾つ5884)が、かな識別の床上げで
    // それは幾つ に負けていた。seed+連文節ボーナス(みな と同型)でかな先頭に(2419)
    func testRegressionIkutsuPrefersKana() throws {
        try prepareRealLMDictionary()
        let multi = converter.multiClauseCandidates(for: "それはいくつ", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "それはいくつ", "multi=\(multi.prefix(5))")
        XCTAssertTrue(multi.contains("それは幾つ"), "multi=\(multi.prefix(5))")
        let solo = converter.candidates(for: "いくつ", limit: 5, systemCandidateMode: .surface)
        XCTAssertEqual(solo.first, "いくつ", "solo=\(solo)")
        // 提示層のかな識別退避を防ぐ(false だと実機バーで それは幾つ が繰り上がる。2420)
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "それはいくつ"))
    }

    // えんやすによるねあがり: 地名 根上(旧根上町)の LM unigram が 値上がり より安く、
    // 円安による根上 が先頭になっていた。seed+連文節ボーナスで 値上がり を先頭に(2418)
    func testRegressionRealLMNeagariPrefersPriceRise() throws {
        try prepareRealLMDictionary()
        let multi = converter.multiClauseCandidates(for: "えんやすによるねあがり", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "円安による値上がり", "multi=\(multi.prefix(5))")
        let tanni = converter.multiClauseCandidates(for: "たんにえんやすによるねあがり", systemCandidateMode: .surface)
        XCTAssertEqual(tanni.first, "単に円安による値上がり", "multi=\(tanni.prefix(5))")
    }

    // こうきじてん: 康熙字典 が SudachiDict/LM に無く候補に出なかった。misc curated で供給(2418)
    func testRegressionKoukiJitenSuppliedFromMisc() throws {
        try prepareRealLMDictionary()
        converter.store.addUserEntry(reading: "こうきじてん", candidate: "康熙字典")
        let single = converter.candidates(for: "こうきじてん", limit: 10, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "康熙字典", "single=\(single)")
    }

    // まったくありません: 全くありません が文語形容詞 全い(まったい)の活用として生成され、
    // poubelle の まったく→全く 抑制(基底読みが異なる)をすり抜けて先頭に出ていた。
    // 抑制の同一かな末尾合成(r+t→s+t)フィルタで除去(2418)
    func testRegressionComposedSuppressionMattaku() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["まったく": ["全く"]])
        let single = converter.candidates(for: "まったくありません", limit: 10, systemCandidateMode: .surface)
        XCTAssertFalse(single.contains("全くありません"), "single=\(single)")
        let multi = converter.multiClauseCandidates(for: "まったくありませんが", systemCandidateMode: .surface)
        XCTAssertFalse(multi.contains("全くありませんが"), "multi=\(multi.prefix(5))")
        let solo = converter.candidates(for: "まったく", limit: 10, systemCandidateMode: .surface)
        XCTAssertEqual(solo.first, "まったく", "solo=\(solo)")
    }

    // かいしか: かいし+か のレア語合成(芥子か/怪死か/甲斐市か…)が20件以上並び、
    // 助数詞合成の 回しか が25位に埋もれていた。助数詞+付属語末尾の合成を先頭候補の
    // 直後へ一般繰り上げ(先頭の最良解は保持。2417)
    func testRegressionCounterParticleTailPromotion() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "かいしか", limit: 30, systemCandidateMode: .surface)
        XCTAssertEqual(single.dropFirst().first, "回しか", "single=\(single.prefix(5))")
    }

    // 1確定→かいしか: 数字文脈ブーストが「読み=助数詞そのもの」限定で、助数詞+かな末尾
    // (かい+しか)の合成(回しか)が雑多な合成(開始か/芥子か 等)に埋もれていた。
    // 助数詞読み+かな末尾への一般拡張で 回しか を先頭に(2416)
    func testRegressionDigitContextCounterWithKanaTail() throws {
        let boosted = KanaKanjiConverter.digitContextCounterBoostedCandidates(
            ["開始か", "会しか", "芥子か", "回しか", "階しか"],
            reading: "かいしか",
            precedingCharacter: "1"
        )
        XCTAssertEqual(boosted.first, "回しか", "boosted=\(boosted)")
        // 数字直後でなければ従来どおり不変
        let plain = KanaKanjiConverter.digitContextCounterBoostedCandidates(
            ["開始か", "回しか"],
            reading: "かいしか",
            precedingCharacter: nil
        )
        XCTAssertEqual(plain.first, "開始か", "plain=\(plain)")
        // 従来の 読み=助数詞そのもの も不変(90確定→びょう→秒)
        let exact = KanaKanjiConverter.digitContextCounterBoostedCandidates(
            ["病", "秒"],
            reading: "びょう",
            precedingCharacter: "0"
        )
        XCTAssertEqual(exact.first, "秒", "exact=\(exact)")
        // 数字直後の かい は 回, 階 の順(3かい→3回/3階。2426)
        let kai = KanaKanjiConverter.digitContextCounterBoostedCandidates(
            ["会", "回", "海", "階"],
            reading: "かい",
            precedingCharacter: "3"
        )
        XCTAssertEqual(Array(kai.prefix(2)), ["回", "階"], "kai=\(kai)")
        // 末尾が変換済みの合成(まい+ちゅう→枚中)も助数詞表層の前方一致で先頭へ(2421)
        let converted = KanaKanjiConverter.digitContextCounterBoostedCandidates(
            ["米中", "マイ中", "枚中", "毎中"],
            reading: "まいちゅう",
            precedingCharacter: "7"
        )
        XCTAssertEqual(converted.first, "枚中", "converted=\(converted)")
    }

    // ばいぐらいに: 倍(助数詞)が dict rank6 で 杯ぐらいに が先頭だった。seed {倍、杯}(2414)
    func testRegressionRealLMBaiGurainiOrder() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let multi = converter.multiClauseCandidates(for: "ばいぐらいに", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "倍ぐらいに", "multi=\(multi)")
        let bai = converter.candidates(for: "ばい", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(Array(bai.prefix(2)), ["倍", "杯"], "bai=\(bai)")
    }

    // あいちけんさん: 様(さん)は読みとして誤り(旧 fallback seed 由来。様=さま/よう)で
    // 撤去。産 を名詞漢字接辞に追加し 愛知県産/フランス産 を供給(カタカナ語幹も許可)(2409)
    func testRegressionRealLMKensanProduce() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let aichi = converter.candidates(for: "あいちけんさん", limit: 6, systemCandidateMode: .surface)
        // 2410: 地域接尾+産 は敬称さん合成より優先(単文節ブースト+連文節ボーナス)
        XCTAssertEqual(aichi.first, "愛知県産", "aichi=\(aichi)")
        XCTAssertFalse(aichi.contains("愛知県様"), "aichi=\(aichi)")
        let aichiMulti = converter.multiClauseCandidates(for: "あいちけんさん", systemCandidateMode: .surface)
        XCTAssertEqual(aichiMulti.first, "愛知県産", "aichiMulti=\(aichiMulti)")
        XCTAssertFalse(aichiMulti.contains("愛知県三"), "aichiMulti=\(aichiMulti)")
        XCTAssertFalse(aichiMulti.contains("愛知県讃"), "aichiMulti=\(aichiMulti)")
        // 人名+さん(かな敬称)は従来どおり
        let tanaka = converter.multiClauseCandidates(for: "たなかさん", systemCandidateMode: .surface)
        XCTAssertEqual(tanaka.first, "田中さん", "tanaka=\(tanaka)")
        let france = converter.candidates(for: "ふらんすさん", limit: 8, systemCandidateMode: .surface)
        XCTAssertTrue(france.contains("フランス産"), "france=\(france)")
    }

    // 品詞横断調査(2398): かな正書の閉クラス語(助詞・助動詞)でかなが先頭に出ない/
    // 候補に無いものを是正。ごとく/ごとき/いえども はかなが候補に無かった。
    // ばかり は 計り が先頭だった(漢字は方針どおり2番手残置)。
    func testRegressionRealLMClosedClassKanaFirst() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        for (r, expectedPrefix) in [
            ("ごとく", ["ごとく", "五徳"]),
            ("ごとき", ["ごとき"]),
            ("いえども", ["いえども", "雖も"]),
            ("ばかり", ["ばかり", "計り"]),
        ] {
            let single = converter.candidates(for: r, limit: 6, systemCandidateMode: .surface)
            XCTAssertEqual(Array(single.prefix(expectedPrefix.count)), expectedPrefix, "r=\(r) single=\(single)")
        }
        // 比況の連文節(やまのごとく)も かな が出る
        let multi = converter.multiClauseCandidates(for: "やまのごとく", systemCandidateMode: .surface)
        XCTAssertTrue(multi.first?.hasSuffix("ごとく") ?? false, "multi=\(multi.prefix(4))")
    }

    // そのた: その他 は Sudachi に単独語が無く(その他の所得 等の複合のみ)、LM unigram も
    // 無い完全な供給欠落=候補なしになっていた。そのた/そのほか とも seed で供給。
    func testRegressionRealLMSonotaSupply() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let sonota = converter.candidates(for: "そのた", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(sonota.first, "その他", "sonota=\(sonota)")
        let sonohoka = converter.candidates(for: "そのほか", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(sonohoka.first, "その他", "sonohoka=\(sonohoka)")
    }

    // かこに: 賀古(人名収穫、dict rank0)が語幹先頭で 賀古に が先行。過去(wc5860/LM4741=最頻)を
    // seed 先頭に。舟子/水主/水手/水夫(かこ=船漕ぎの古語)は実在読みのため後続維持。
    func testRegressionRealLMKakoniOrdering() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let kako = converter.candidates(for: "かこ", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(kako.first, "過去", "kako=\(kako)")
        let single = converter.candidates(for: "かこに", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "過去に", "single=\(single)")
        let multi = converter.multiClauseCandidates(for: "かこにもどる", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "過去に戻る", "multi=\(multi.prefix(4))")
    }

    // してくれて: エンジンはかな最良(既存の て形+くれ クランプ)だが keepKana=false で
    // 提示層がかな退避し して暮れて が繰り上がっていた。授受補助動詞末尾+て/で形の
    // keepKana 根拠を追加。単独 くれて は クレテ(収穫)先頭化を seed かな掲載で是正。
    func testRegressionRealLMShiteKureteKanaFirst() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let multi = converter.multiClauseCandidates(for: "してくれて", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "してくれて", "multi=\(multi.prefix(4))")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "してくれて"))
        let kurete = converter.candidates(for: "くれて", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(kurete.first, "くれて", "kurete=\(kurete)")
    }

    // おしえてあげて: Wikipedia LM の基底頻度(挙げる5399<上げる5806<あげる6120=例を挙げる
    // 等の百科事典バイアス)で 教えて挙げて が先頭化。授受クランプを あげ族 に拡張。
    func testRegressionRealLMOshieteAgeteKanaAuxiliary() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let multi = converter.multiClauseCandidates(for: "おしえてあげて", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "教えてあげて", "multi=\(multi.prefix(4))")
        let agata = converter.multiClauseCandidates(for: "てをあげて", systemCandidateMode: .surface)
        // を 直後(て形でない)の あげて はクランプ対象外 — 手を挙げて/上げて の漢字は維持
        XCTAssertTrue(agata.contains(where: { $0.contains("挙げて") || $0.contains("上げて") }), "agata=\(agata.prefix(4))")
    }

    // えあこんをおん: を→御(5399)が を→オン(5530)より僅差で安く エアコンを御 が先頭化
    // (Wikipediaバイアス)。seed おん=オン先頭+連文節 opt-in ボーナスで是正。ON/On/on は
    // LM 実在なのに辞書未登録だった供給欠落を seed で補う。御(接頭辞)/音(単独名詞でない読み)は
    // suppr+完全一致時のみ末尾再供給の二段構え(変種枠3から ON/On/on を押し出さないため)。
    func testRegressionRealLMAirconOn() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["おん": ["御", "音"]])
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let multi = converter.multiClauseCandidates(for: "えあこんをおん", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "エアコンをオン", "multi=\(multi.prefix(5))")
        XCTAssertFalse(multi.contains(where: { $0.contains("を御") || $0.contains("を音") }), "multi=\(multi.prefix(5))")
        XCTAssertTrue(multi.contains(where: { $0.hasSuffix("ON") || $0.hasSuffix("On") || $0.hasSuffix("on") }), "multi=\(multi.prefix(5))")
        let single = converter.candidates(for: "おん", limit: 12, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "オン", "single=\(single)")
        XCTAssertTrue(["ON", "On", "on"].allSatisfy(single.contains), "single=\(single)")
        // 完全一致時のみ 音/御 を末尾再供給。複合読み(御社)は無傷
        XCTAssertTrue(single.contains("音") && single.contains("御"), "single=\(single)")
        // (おんしゃ の既存並び 音写/恩赦/御社 はこの suppr の影響を受けない)
        let onsha = converter.candidates(for: "おんしゃ", limit: 4, systemCandidateMode: .surface)
        XCTAssertTrue(onsha.contains("御社"), "onsha=\(onsha)")
        // おん を含む複合語の区切りは不変
        let onsen = converter.candidates(for: "おんせん", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(onsen.first, "温泉", "onsen=\(onsen)")
        let ongaku = converter.multiClauseCandidates(for: "おんがくをきく", systemCandidateMode: .surface)
        XCTAssertEqual(ongaku.first, "音楽を聴く", "ongaku=\(ongaku.prefix(4))")
    }

    // さじぇすちょん: LM未収録・代替ゼロの外来語(サジェスチョン、辞書唯一 wc2148)が
    // 連文節側のカタカナ強調クラス抑制(+100000)で不採用になり、LM実在の断片
    // さ+ジェス+チョン(人名収穫)がジャンク最良→表示先頭になっていた。単文節側と同義の
    // 「代替(同スパン漢字ノード/かな側LM)が存在する限り強調」判定を multi 側にも導入。
    func testRegressionRealLMSuggestionLoanwordNotFragmented() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let multi = converter.multiClauseCandidates(for: "さじぇすちょん", systemCandidateMode: .surface)
        XCTAssertTrue(multi.isEmpty || multi.first == "サジェスチョン", "multi=\(multi.prefix(4))")
        XCTAssertFalse(multi.contains("さジェスチョン"), "multi=\(multi.prefix(4))")
        let single = converter.candidates(for: "さじぇすちょん", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "サジェスチョン", "single=\(single)")
        // 同スパンに漢字ノード(成った 等)があるカタカナ収穫(ナッタ)の連文節抑制は維持
        let natta = converter.multiClauseCandidates(for: "なったのは", systemCandidateMode: .surface)
        XCTAssertFalse(natta.contains(where: { $0.contains("ナッタ") }), "natta=\(natta.prefix(4))")
    }

    // できた: かなが正書(基底 できる 3767 ≪ 出来る 5254)。単独入力は かな→出来た→人名収穫
    // (出來田/出木田/出来田)の順に。keepKana も併記(提示層のかな退避防止、2329-2330 の教訓)。
    func testRegressionRealLMDekitaKanaFirst() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let single = converter.candidates(for: "できた", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(2)), ["できた", "出来た"], "single=\(single)")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "できた"))
        // 合成は連文節側の選択を維持(かな/漢字とも上位)
        let multi = converter.multiClauseCandidates(for: "しゅくだいができた", systemCandidateMode: .surface)
        XCTAssertEqual(Array(multi.prefix(2)), ["宿題ができた", "宿題が出来た"], "multi=\(multi.prefix(4))")
    }

    // まけたからしかたない: から+仕方ない の区切りが 枯らし+方+ない 分割に負けていた
    // (→負けた枯らし方ない)。仕方ない(辞書wc7696)を curated(misc, 連文節1500)化して
    // 区切りを勝たせる(殻付き と同型)。テストバンドルは misc JSON を読まないため addUserEntry で再現。
    func testRegressionRealLMMaketakaraShikatanai() throws {
        try prepareRealLMDictionary()
        converter.store.addUserEntry(reading: "しかたない", candidate: "仕方ない")
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let multi = converter.multiClauseCandidates(for: "まけたからしかたない", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "負けたから仕方ない", "multi=\(multi.prefix(4))")
        XCTAssertFalse(multi.contains(where: { $0.contains("枯らし方") }), "multi=\(multi.prefix(6))")
        let sub = converter.multiClauseCandidates(for: "からしかたない", systemCandidateMode: .surface)
        XCTAssertEqual(sub.first, "から仕方ない", "sub=\(sub.prefix(4))")
        let single = converter.candidates(for: "しかたない", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "仕方ない", "single=\(single)")
    }

    // ぜんかい: ユーザ指定順(前回→全開→全快→全壊→全潰→全会)。あわせて 1000回 の誤生成
    // (連濁 ぜん が単独で桁成立していた)を是正。さんぜんかい→3000回/せんかい→1000回 は正当。
    func testRegressionRealLMZenkaiOrderingAndRendakuDigit() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let single = converter.candidates(for: "ぜんかい", limit: 20, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(6)), ["前回", "全開", "全快", "全壊", "全潰", "全会"], "single=\(single.prefix(8))")
        XCTAssertFalse(single.contains("1000回"), "single=\(single)")
        // 正当な連濁・非連濁の数値生成は無傷
        let sanzen = converter.candidates(for: "さんぜんかい", limit: 20, systemCandidateMode: .surface)
        XCTAssertTrue(sanzen.contains("3000回"), "sanzen=\(sanzen.prefix(8))")
        let sen = converter.candidates(for: "せんかい", limit: 20, systemCandidateMode: .surface)
        XCTAssertTrue(sen.contains("1000回"), "sen=\(sen.prefix(8))")
        let nizen = converter.candidates(for: "にぜんかい", limit: 20, systemCandidateMode: .surface)
        XCTAssertFalse(nizen.contains("2000回"), "nizen=\(nizen.prefix(8))")
    }

    // とかじゃなかったか: 冠者(かじゃ、wc5886)が と+冠者 分割で とか+じゃ を乗っ取っていた。
    // 冠者/カジャ を suppr し、かじゃ 完全一致時のみ 冠者 を末尾再供給(二段構え)。
    func testRegressionRealLMTokajaKanjaTakeover() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["かじゃ": ["冠者", "カジャ"]])
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let multi = converter.multiClauseCandidates(for: "とかじゃなかったか", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "とかじゃなかったか", "multi=\(multi.prefix(4))")
        XCTAssertFalse(multi.contains(where: { $0.contains("冠者") }), "multi=\(multi.prefix(6))")
        // keepKana が false だと提示層が先頭かなを末尾チップへ退避し、変種(とかじゃ無かったか)が
        // 実機バー先頭に繰り上がる(2329-2330 と同型)。じゃなかったか 末尾で根拠成立を固定。
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "とかじゃなかったか"))
        // 単文節経路は内容語ゼロのこの読みを組み立てない(実機バーは連文節経路)。出る場合も 冠者 は不可
        let single = converter.candidates(for: "とかじゃなかったか", limit: 30, systemCandidateMode: .surface)
        XCTAssertTrue(single.isEmpty || single.first == "とかじゃなかったか", "single=\(single.prefix(8))")
        XCTAssertFalse(single.contains(where: { $0.contains("冠者") }), "single=\(single.prefix(8))")
        // 完全一致時は 冠者 を末尾供給(かんじゃ 読みは辞書に残るため無傷)
        let exact = converter.candidates(for: "かじゃ", limit: 30, systemCandidateMode: .surface)
        XCTAssertTrue(exact.contains("冠者"), "exact=\(exact)")
        let kanja = converter.candidates(for: "かんじゃ", limit: 30, systemCandidateMode: .surface)
        XCTAssertTrue(kanja.contains("冠者"), "kanja=\(kanja.prefix(15))")
    }

    // だっけな: ダッケ(だっけ の辞書エントリはこれのみのカタカナ収穫)が先頭化していた。
    // だっけ はLM未収録+漢字代替ゼロでクラス抑制が素通りするため個別suppr。かな だっけ を勝たせる。
    // suppr 後は keepKana が成立しないと提示層がかな最良(だっけな)を退避して候補なしになる
    // (実機で発生)— curated だっけ(misc 既存)を語幹根拠に keepKana を固定する。
    func testRegressionRealLMDakkeKanaFirst() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["だっけ": ["ダッケ"]])
        converter.store.addUserEntry(reading: "だっけ", candidate: "だっけ") // misc curated 相当
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let multi = converter.multiClauseCandidates(for: "だっけな", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "だっけな", "multi=\(multi.prefix(4))")
        XCTAssertFalse(multi.contains(where: { $0.contains("ダッケ") }), "multi=\(multi.prefix(6))")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "だっけな"))
        let single = converter.candidates(for: "だっけな", limit: 6, systemCandidateMode: .surface)
        XCTAssertTrue(single.isEmpty || single.first == "だっけな", "single=\(single)")
        XCTAssertFalse(single.contains(where: { $0.contains("ダッケ") }), "single=\(single)")
        // suppr 後は だっけ の辞書エントリが空になり、単独入力はかなチップが供給する(なった と同型)
        let exact = converter.candidates(for: "だっけ", limit: 6, systemCandidateMode: .surface)
        XCTAssertTrue(exact.isEmpty || exact.first == "だっけ", "exact=\(exact)")
        XCTAssertFalse(exact.contains("ダッケ"), "exact=\(exact)")
    }

    // じょせい: ユーザ指定順(女性→助勢→女声→助成)。基底 word_cost 順では 助成 が先頭だった。
    func testRegressionRealLMJoseiOrdering() throws {
        try prepareRealLMDictionary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let single = converter.candidates(for: "じょせい", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(4)), ["女性", "助勢", "女声", "助成"], "single=\(single)")
    }

    // ぐーぐるはこうこたえる: 追加語彙 香茹(こうこ、curated床1500)が こう+答える の区切りを
    // 分断していた(ろーま型)。2326のde-floorゲートを「断片内部から始まり末尾を跨ぐ常用語
    // (こうこ の中の こたえる)」条件で拡張(読み≤3字に拡大)。香茹を食べた 等の助詞ありは無傷。
    func testRegressionRealLMKouKotaeru() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary(includeSuppression: true)
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let multi = converter.multiClauseCandidates(for: "ぐーぐるはこうこたえるんだけど", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "Googleはこう答えるんだけど", "multi=\(multi.prefix(4))")
        // curated 香茹 の正当用法(助詞あり)は維持
        let kouko = converter.multiClauseCandidates(for: "こうこをたべた", systemCandidateMode: .surface)
        XCTAssertEqual(kouko.first, "香茹を食べた", "multi=\(kouko.prefix(3))")
    }

    // あきの: seed 秋の→空きの→秋野。秋(あきの=正規化ミス)/厭きの suppr、飽きの は後方に残す。
    // なのにー: ニー(knee等のLM実在でクラス保護される)を個別 suppr 復元。
    func testRegressionRealLMAkinoNanonii() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["あきの": ["秋", "厭きの"], "にー": ["ニー"], "のにー": ["のニー"]])
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let akino = converter.candidates(for: "あきの", limit: 16, systemCandidateMode: .surface)
        XCTAssertEqual(Array(akino.prefix(3)), ["秋の", "空きの", "秋野"], "single=\(akino)")
        XCTAssertFalse(akino.contains("秋") || akino.contains("厭きの"), "single=\(akino)")
        XCTAssertTrue(akino.contains("飽きの"), "飽きの(飽きのこない)は残す: \(akino)")
        if let kanaIdx = akino.firstIndex(of: "あきの"), let top = akino.firstIndex(of: "秋の") {
            XCTAssertGreaterThan(kanaIdx, top + 5, "かな識別は後方: \(akino)")
        }
        let nanonii = converter.multiClauseCandidates(for: "なのにー", systemCandidateMode: .surface)
        XCTAssertTrue(nanonii.isEmpty || nanonii.first == "なのにー", "multi=\(nanonii.prefix(3))")
        XCTAssertFalse(nanonii.contains("なのニー"), "multi=\(nanonii.prefix(3))")
    }

    // もじでだすと: 文字でダスト が先頭だった。と→EOS 3879(Wikipediaで と は文末に来ない)の
    // 半減圧縮でも 出すと+EOS が ダスト(EOS1648)に負ける系統的食い違い。かな助詞 prev の
    // 観測EOSを fallback で上限して 文字で出すと を最良に。
    func testRegressionRealLMMojideDasuto() throws {
        try prepareRealLMDictionary()
        let multi = converter.multiClauseCandidates(for: "もじでだすと", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "文字で出すと", "multi=\(multi.prefix(4))")
        XCTAssertFalse(multi.contains("文字でダスト"), "multi=\(multi.prefix(4))")
    }

    // もうしょくばにきてしまいました: 来て が経路に無く、着て/衣て/著て(一段きる派生)のみだった。
    // (1) カ変連文節供給を kuruInflectionForms 全形から自動生成(きてしまいました 丸ごとspan対応)
    // (2) 著る/衣る(着る の古語表記)を基底suppr (3) 格助詞に直後のカ変到着点ボーナスで 来て を先頭に。
    func testRegressionRealLMShokubaNiKite() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["きる": ["著る", "衣る"]])
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let multi = converter.multiClauseCandidates(for: "もうしょくばにきてしまいました", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "もう職場に来てしまいました", "multi=\(multi.prefix(4))")
        XCTAssertTrue(multi.contains("もう職場に着てしまいました"), "着て は次点に残す: \(multi.prefix(4))")
        XCTAssertFalse(multi.contains(where: { $0.contains("衣て") || $0.contains("著て") }), "multi=\(multi.prefix(4))")
        // を格の 着て は不変(に 直後限定ボーナスの誤爆防止)
        let fuku = converter.multiClauseCandidates(for: "ふくをきていました", systemCandidateMode: .surface)
        XCTAssertEqual(fuku.first, "服を着ていました", "multi=\(fuku.prefix(3))")
        // 単文節の きてしまいました は 来て が先頭(既存挙動の固定)
        let single = converter.candidates(for: "きてしまいました", limit: 3, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "来てしまいました", "single=\(single)")
    }

    // 欧文サジェスチョンの別レイヤー(同梱頻度リスト): 追加語彙が先頭、汎用語が頻度順で後続。
    // 言語トグルOFFで当該言語が消えること、追加語彙と同キーは追加語彙が勝つことを確認。
    func testGenericLatinLexiconSuggestions() throws {
        let store = KanaKanjiStore(appGroupID: defaultsSuiteName)
        store.genericLatinLexiconDirectoryURLOverride = URL(
            fileURLWithPath: "/Users/kusakabe/Git/ecritu/KeyboardExtension", isDirectory: true
        )
        // 既定は全言語OFF(サジェストに汎用語が混ざらない)
        XCTAssertFalse(store.latinSuggestions(prefix: "informa", limit: 8).contains("information"))
        store.setGenericLatinLexiconEnabledLanguages(["en", "fr", "de", "it"])
        // 索引ロード(全言語=10万語超。mmap+改行カウントのみでパース無し)の所要時間を確認
        let builtAt = CFAbsoluteTimeGetCurrent()
        let loadedCounts = ["en", "fr", "de", "it"].map {
            store.genericLatinLexiconIndex(language: $0)?.entryCount ?? 0
        }
        let buildMs = (CFAbsoluteTimeGetCurrent() - builtAt) * 1000
        print("PROBE lexicon mmap: \(Int(buildMs))ms, entries=\(loadedCounts)")
        XCTAssertEqual(loadedCounts, [15000, 15000, 60000, 15000])
        let english = store.latinSuggestions(prefix: "informa", limit: 8)
        XCTAssertTrue(english.contains("information"), "suggestions=\(english)")
        let french = store.latinSuggestions(prefix: "voil", limit: 8)
        XCTAssertTrue(french.contains("voilà"), "suggestions=\(french)")
        let german = store.latinSuggestions(prefix: "polizei", limit: 8)
        XCTAssertTrue(german.contains("Polizei"), "大文字名詞の保持: \(german)")
        let compound = store.latinSuggestions(prefix: "Schlussfolg", limit: 8)
        XCTAssertTrue(compound.contains("Schlussfolgerung"), "複合語の深いランク: \(compound)")
        let gegen = store.latinSuggestions(prefix: "Gegenübers", limit: 8)
        XCTAssertTrue(gegen.contains("Gegenüberstellung"), "複合語の深いランク: \(gegen)")
        let italian = store.latinSuggestions(prefix: "perch", limit: 8)
        XCTAssertTrue(italian.contains("perché"), "アクセント保持: \(italian)")
        // 空白後のフォールバック: 語句全体(hello wor)で一致ゼロ→空白直後(wor)から再検索
        let afterSpace = store.latinSuggestions(prefix: "hello wor", limit: 8)
        XCTAssertTrue(afterSpace.contains(where: { $0.hasPrefix("wor") }), "suggestions=\(afterSpace)")
        let multiSpace = store.latinSuggestions(prefix: "je pense que natur", limit: 8)
        XCTAssertTrue(multiSpace.contains("natürlich"), "3語以上でも段階的に縮む: \(multiSpace)")
        // 追加語彙(SecondVocab相当)が先頭に来る: 手動でエントリを注入して確認
        store.setGenericLatinLexiconEnabledLanguages(["en"])
        let englishOnly = store.latinSuggestions(prefix: "voil", limit: 8)
        XCTAssertFalse(englishOnly.contains("voilà"), "fr OFF: \(englishOnly)")
    }

    // マニュアル目次のかな入力モード画面例(assets/hero-kana.png)を再生成する。
    // 設定: フリック方向Apple/3×3+わ/後置修飾/émeraude/rose sakura poudré/かなガイド4方向/
    // 修飾キーガイドoff/左下タップ=記号(⌘)。出力は tmp/ — 変更時に docs/manual/assets/ へコピーする。
    @MainActor
    func testRenderManualHeroScreenshotKanaMode() throws {
        let view = KeyboardRootView(
            onTextInput: { _ in },
            onDeleteBackward: {},
            onSpace: {},
            onReturn: {},
            onAdvanceKeyboard: {},
            onApplyKanaPostModifier: { _, _ in .ignored },
            onToggleParenthesesWrapper: {},
            onSelectConversionCandidate: { _ in },
            onCommitComposingText: {},
            onCommitComposingTextAsKatakana: {},
            onUpgradeRecentKanaCommitToKatakana: { false },
            onInputModeChanged: { _ in },
            showsNextKeyboardKey: false,
            directionProfile: .apple,
            kanaLayoutMode: .threeByThreePlusWa,
            kanaModifierPlacementMode: .postfix,
            kanaPostModifierButtonState: .kaomoji,
            numberLayoutMode: .calculette,
            latinLayoutMode: .flick,
            accentPaletteRawValue: "emeraude",
            isSystemDictionaryFallback: false,
            keyboardBackgroundThemeRawValue: "sakura",
            basicSymbolOrderRawValue: "ascii",
            temperatureUnitRawValue: TemperatureUnitPreference.celsius.rawValue,
            spaceToastTrigger: 0,
            returnKeySystemImageName: nil,
            isReturnKeyEnabled: true,
            kanaFlickGuideDisplayMode: .fourDirections,
            latinFlickGuideDisplayMode: .fourDirections,
            numberFlickGuideDisplayMode: .fourDirections,
            modifierFlickGuideDisplayMode: .off,
            keyRepeatInitialDelay: 0.5,
            keyRepeatInterval: 0.1,
            kanaModeSwitcherTapActionRawValue: "symbols",
            kanaModeSwitcherRightFlickActionRawValue: "kaomoji",
            kanaModeSwitcherUpFlickActionRawValue: "emoji",
            kanaPostModifierEmptyTapActionRawValue: "kaomoji",
            kanaPostModifierEmptyTapKaomojiCategoryID: "existing",
            kanaPostModifierEmptyTapEmojiCategoryID: "0",
            kanaPostModifierEmptyTapSymbolCategoryID: "0",
            kanaPostModifierFlickDakutenEnabled: true,
            landscapeCandidateSideRawValue: "left",
            landscapeNumberPaneSideRawValue: "left",
            landscapeLatinSuggestionModeRawValue: "sidebar",
            shortcutVocabulary: [],
            candidateBarModel: KeyboardCandidateBarModel(),
            showsParenthesesWrapper: false,
            initialSpaceToastText: nil
        )
        .frame(width: 402, height: 272)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        guard let image = renderer.uiImage, let data = image.pngData() else {
            XCTFail("render failed")
            return
        }
        try data.write(to: URL(fileURLWithPath: "/Users/kusakabe/Git/ecritu/tmp/manual_hero_kana.png"))
        print("PROBE screenshot: \(image.size)")
    }

    // 欧文サジェスチョンの大小適応: 打った先頭が大文字なら候補の先頭も大文字化(付与のみ)。
    // 独名詞など元から大文字のentryは不変、小文字入力での小文字化もしない。
    func testLatinSuggestionCaseAdaptation() throws {
        typealias VC = KeyboardViewController
        XCTAssertEqual(VC.adaptedLatinSuggestionCase("natural", toQuery: "Natur"), "Natural")
        XCTAssertEqual(VC.adaptedLatinSuggestionCase("natürlich", toQuery: "Natür"), "Natürlich")
        XCTAssertEqual(VC.adaptedLatinSuggestionCase("natural", toQuery: "NATUR"), "NATURAL")
        XCTAssertEqual(VC.adaptedLatinSuggestionCase("natural", toQuery: "natur"), "natural")
        XCTAssertEqual(VC.adaptedLatinSuggestionCase("Natur", toQuery: "natur"), "Natur")
        XCTAssertEqual(VC.adaptedLatinSuggestionCase("NÜCHI by WPÜ", toQuery: "Nüchi"), "NÜCHI by WPÜ")
        XCTAssertEqual(VC.adaptedLatinSuggestionCase("it’s", toQuery: "It"), "It’s")
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
        // 補助語彙(SecondVocab)も実機同等に配備する(テストバンドルには載らないため、
        // 生成物 tmp/ÉcrituSecondVocab.json を共有コンテナへ。ジャングリア の
        // 補助語彙カタカナ免除などの検証に必要)
        let secondVocabSource = URL(fileURLWithPath: "/Users/kusakabe/Git/ecritu/tmp/ÉcrituSecondVocab.json")
        if fileManager.fileExists(atPath: secondVocabSource.path) {
            let secondVocabDestination = container.appendingPathComponent("ÉcrituSecondVocab.json")
            if !fileManager.fileExists(atPath: secondVocabDestination.path) {
                try fileManager.copyItem(at: secondVocabSource, to: secondVocabDestination)
            }
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
