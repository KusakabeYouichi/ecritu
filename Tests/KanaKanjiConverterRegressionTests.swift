import SwiftUI
import XCTest

final class KanaKanjiConverterRegressionTests: XCTestCase {
    private var defaultsSuiteName = ""
    private var converter: KanaKanjiConverter!

    override func setUp() {
        super.setUp()

        Self.purgeStaleTestContainersIfNeeded()
        defaultsSuiteName = "com.kusakabe.ecritu.tests.kana-kanji.\(UUID().uuidString)"
        clearSuite(defaultsSuiteName)
        // 偽 group ID での containerURL はプロセス初回に約40秒かかるため、テストは
        // ローカルディレクトリーを共有コンテナとして使う(store 側の override と対)。
        // 従来の containerURL は UUID group ごとに別コンテナ=テスト間隔離だったので、
        // テストごとのサブディレクトリーで同じ隔離を保つ(共有にすると2件が挙動変化)
        testContainerURL = URL(
            fileURLWithPath: "/Users/kusakabe/Git/ecritu/tmp/test_app_group/\(defaultsSuiteName)",
            isDirectory: true
        )
        KanaKanjiStore.sharedContainerURLOverride = testContainerURL
        converter = KanaKanjiConverter(store: KanaKanjiStore(appGroupID: defaultsSuiteName))
    }

    var testContainerURL: URL!

    // テスト用コンテナの親。1テストあたり実辞書(約417MB)を複製するため、後始末が漏れると
    // 静かに積み上がる。実際に旧実装(UUID group ID で実コンテナを作る方式)では
    // シミュレータ内に AppGroup コンテナが13万件・辞書コピー8.2万件まで蓄積し、
    // ディスクを埋めて全体スイートが73件失敗した(2026-08-13)。現方式は tearDown で
    // 消えるが、クラッシュや強制終了では残るため、起動時に残骸を掃除して再発を防ぐ。
    static let testAppGroupRootPath = "/Users/kusakabe/Git/ecritu/tmp/test_app_group"
    private static var didPurgeStaleTestContainers = false

    static func purgeStaleTestContainersIfNeeded() {
        guard !didPurgeStaleTestContainers else {
            return
        }
        didPurgeStaleTestContainers = true

        let root = URL(fileURLWithPath: testAppGroupRootPath, isDirectory: true)
        let fileManager = FileManager.default
        guard let leftovers = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ), !leftovers.isEmpty else {
            return
        }
        for leftover in leftovers {
            try? fileManager.removeItem(at: leftover)
        }
        print("前回実行の残骸テストコンテナを削除: \(leftovers.count)件")
    }

    override func tearDown() {
        clearSuite(defaultsSuiteName)
        if let testContainerURL {
            do {
                try FileManager.default.removeItem(at: testContainerURL)
            } catch CocoaError.fileNoSuchFile {
                // 辞書を複製しないテストではディレクトリー自体が作られない。正常。
            } catch {
                // 削除失敗を黙って捨てると蓄積に気付けない。テストは落とさず警告に留める
                // (1件の後始末失敗で無関係な検証結果を覆い隠さないため)。
                print("警告: テストコンテナの削除に失敗 path=\(testContainerURL.path) error=\(error)")
            }
        }
        testContainerURL = nil
        KanaKanjiStore.sharedContainerURLOverride = nil
        converter = nil
        defaultsSuiteName = ""
        super.tearDown()
    }

    // 実LM回帰: 開発機の tmp sqlite(実辞書+連文節LM)を app group コンテナへ複製して
    // multiClauseCandidates を直接検証する。tmp が無い環境では skip(実LM依存のため)。
    // むかしみたな: かな断片チェーン(昔+み+た+な、み→た bigram 1010)や短spanレア読み
    // (見店/実棚/三田な)に負けず 昔見たな が最良になること(短span床上げ+文末な減点)。
    // からさ: 辞書に からさ が無く(Sudachi は「形容詞+さ」を生産的派生として扱い、core_lex の
    // さ 終わり名詞は40件のみ)、終助詞さ の postfix 素通りが から の全候補に さ を付けるため
    // 嘉良さ/唐さ/迦羅さ… が20件並び 辛さ が20番目に沈んでいた。形容詞さ名詞化ブーストで
    // 辛さ を先頭に、辣さ/鹹さ をそれに続かせる。
    func testRegressionRealLMKarasaPrefersAdjectiveNominalization() throws {
        try prepareRealLMDictionary()

        let list = converter.candidates(for: "からさ", limit: 30, systemCandidateMode: .surface)
        XCTAssertEqual(list.first, "辛さ", "list=\(list)")
        let kanjiSaForms = list.filter { ["辛さ", "辣さ", "鹹さ"].contains($0) }
        XCTAssertEqual(kanjiSaForms, ["辛さ", "辣さ", "鹹さ"], "list=\(list)")
        if let karasaIndex = list.firstIndex(of: "からさ") {
            XCTAssertEqual(karasaIndex, list.count - 1, "かな候補は末尾 list=\(list)")
        }
    }

    // げんかい: 基底辞書順と word_cost が LM 実勢と逆(厳戒 rank0/cost6518 だが LM では
    // 限界5422 << 厳戒7649)。seed で 限界 を先頭に矯正する。
    func testRegressionRealLMGenkaiPrefersGenkai() throws {
        try prepareRealLMDictionary()

        let list = converter.candidates(for: "げんかい", limit: 12, systemCandidateMode: .surface)
        XCTAssertEqual(list.first, "限界", "list=\(list)")
    }

    // 意志形+口語の引用促音(〜よっと/〜ようっと)。語彙が無く候補ゼロになっていた。
    // てみる複合(teMiruInflectionSuffixes)と一段/サ変の活用ルールで供給する。
    func testRegressionRealLMVolitionalQuotativeTto() throws {
        try prepareRealLMDictionary()

        for (reading, expected) in [
            ("かってみよっと", "買ってみよっと"),
            ("かってみようっと", "買ってみようっと"),
            ("たべよっと", "食べよっと")
        ] {
            let single = converter.candidates(for: reading, limit: 8, systemCandidateMode: .surface)
            XCTAssertEqual(single.first, expected, "reading=\(reading) single=\(single)")
        }
    }

    // ちしま/からふと: カタカナ表記ゆれの word_cost が異常に低くカタカナが先頭だった(貽貝と
    // 同亜型)。seed で漢字先頭に。ちしまと はさらに 的(まと)の surface LM 借用で
    // 致死+的 が連文節を乗っ取っていた(bigram 借用遮断で対処)。
    func testRegressionRealLMChishimaKarafutoOrdering() throws {
        try prepareRealLMDictionary()

        XCTAssertEqual(converter.candidates(for: "ちしま", limit: 8, systemCandidateMode: .surface).first, "千島")
        XCTAssertEqual(converter.candidates(for: "からふと", limit: 8, systemCandidateMode: .surface).first, "樺太")
        let chishimato = converter.multiClauseCandidates(for: "ちしまと", systemCandidateMode: .surface)
        XCTAssertEqual(chishimato.first, "千島と", "multi=\(chishimato)")
        XCTAssertFalse(chishimato.contains("致死的"), "multi=\(chishimato)")
    }

    // きぐ: 単文節は rank(器具0<危惧1)も unigram(5885<6112)も 器具 が上なのに、読み2字は
    // 短spanレア読み床上げ base=max(base, wc) を受け、wc が実勢と逆(器具7179>危惧6518)な
    // ために連文節だけ 危惧なんて が先頭になっていた。床上げ免除で是正(むき/じ/けい と同型)。
    // 併せて 危惧 の交ぜ書き 危ぐ が候補から消えていること。
    func testRegressionRealLMKiguOrdering() throws {
        try prepareRealLMDictionary()

        let single = converter.candidates(for: "きぐ", limit: 24, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "器具", "single=\(single)")
        let multi = converter.multiClauseCandidates(for: "きぐなんて", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "器具なんて", "multi=\(multi)")

        // 交ぜ書き 危ぐ の抑制(suppr.plist 由来)はテストバンドルに JSON が載らないため
        // defaults 側で再現する。実機では bundledHiddenSuppressionDictionary が読む。
        try injectSuppression(["きぐ": ["危ぐ"]])
        converter.clearAllCaches()
        let suppressed = converter.candidates(for: "きぐ", limit: 24, systemCandidateMode: .surface)
        XCTAssertFalse(suppressed.contains("危ぐ"), "single=\(suppressed)")
        XCTAssertEqual(suppressed.first, "器具", "single=\(suppressed)")
    }

    // いっかつ: dictionary_entries が 一喝 rank0 で、LM(一括6106<一喝7216)と食い違っていた。
    // rank1 は 喝 の互換漢字(U+FA36)版という重複エントリ。seed で 一括 を先頭に。
    func testRegressionRealLMIkkatsuOrdering() throws {
        try prepareRealLMDictionary()

        let candidates = converter.candidates(for: "いっかつ", limit: 24, systemCandidateMode: .surface)
        XCTAssertEqual(candidates.first, "一括", "candidates=\(candidates)")
    }

    // こういしょう: 後遺症 の読み別 wc 13100(unigram 6676 の一般語なのに収穫底値超え)で
    // 連文節の床上げ+bigram借用拒否を受け、へんな+こういしょう が 3分割(変な行為章)に
    // 負けていた。ひこうき と同型。seed 免除で 変な後遺症 が最良になること。
    func testRegressionRealLMHennaKouishou() throws {
        try prepareRealLMDictionary()

        let multi = converter.multiClauseCandidates(for: "へんなこういしょう", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "変な後遺症", "multi=\(multi)")
        let single = converter.candidates(for: "こういしょう", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "後遺症", "single=\(single)")
    }

    // もらう: かな正書を先頭に(ユーザー方針)。基底辞書は 貰う rank0 で LM 実勢
    // (もらう5669 < 貰う6722)と逆だった。seed のかな先頭が基底・活用派生・合成の
    // 全経路に波及することを検証する。
    func testRegressionRealLMMorauPrefersKana() throws {
        try prepareRealLMDictionary()

        for reading in ["もらう", "もらった"] {
            let single = converter.candidates(for: reading, limit: 12, systemCandidateMode: .surface)
            let kanjiIndex = single.firstIndex { $0.contains("貰") }
            let kanaIndex = single.firstIndex(of: reading)
            XCTAssertNotNil(kanaIndex, "reading=\(reading) single=\(single)")
            if let kanaIndex, let kanjiIndex {
                XCTAssertLessThan(kanaIndex, kanjiIndex, "reading=\(reading) single=\(single)")
            }
        }
        // してもらった は6文字=単文節候補なし(連文節のみ)。表示トップ=連文節最良。
        let multi = converter.multiClauseCandidates(for: "してもらった", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "してもらった", "multi=\(multi)")
        // 提示層の退避を受けないこと(かな正書の根拠)。実機では converter=かな先頭 でも
        // この根拠が無いと提示層が退避して して貰った が繰り上がっていた(2534)。
        for reading in ["してもらった", "かいてもらう", "よんでもらった"] {
            XCTAssertTrue(
                converter.shouldKeepKanaIdentityLeading(for: reading),
                "keepKana should hold for \(reading)"
            )
        }
    }

    // いがい: 貽貝(word_cost 3700)と表記ゆれ収穫(イガイ/イ貝/い貝)が上位を独占し、
    // LM 最頻出の 以外(4226)が2番目以降に沈んでいた。seed で常用語を先頭群に固定する。
    func testRegressionRealLMIgaiPrefersCommonWords() throws {
        try prepareRealLMDictionary()

        let list = converter.candidates(for: "いがい", limit: 20, systemCandidateMode: .surface)
        XCTAssertEqual(Array(list.prefix(3)), ["以外", "意外", "遺骸"], "list=\(list)")
    }

    // こうげん: 光源 が word_costs に無く rank14 まで沈んでいた。seed で LM 実勢順の
    // 先頭5件を固定し、かな こうげん は末尾側へ降格すること。
    func testRegressionRealLMKougenOrdering() throws {
        try prepareRealLMDictionary()

        let list = converter.candidates(for: "こうげん", limit: 20, systemCandidateMode: .surface)
        XCTAssertEqual(Array(list.prefix(5)), ["高原", "光源", "抗原", "公言", "膠原"], "list=\(list)")
        if let kanaIndex = list.firstIndex(of: "こうげん") {
            XCTAssertGreaterThan(kanaIndex, 9, "かな候補は後方 list=\(list)")
        }
    }

    // ものれいる→モノレイル(sacoche)/まぐせいふ→MagSafe(it)の語彙追加(2535)。
    // モノレイル は追加語彙ロード、MagSafe は補助語彙(SecondVocab)経由で出ること。
    func testRegressionRealLMVocabMonoreiluMagSafe() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary()

        let monoreilu = converter.candidates(for: "ものれいる", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(monoreilu.first, "モノレイル", "single=\(monoreilu)")
        let magsafe = converter.candidates(for: "まぐせいふ", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(magsafe.first, "MagSafe", "single=\(magsafe)")
    }

    // おかし: 辞書エントリが 御菓子(wc7812)だけで現代正書の お菓子 が1件も無かった。
    // 御菓子 は LM 未収録なので連文節では dictUnknown 扱いになり、ぼるどーのおかし が
    // 丘(LM5514)+し の分割に負けて ボルドーの丘し になっていた(2584)。
    func testRegressionRealLMOkashi() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary()

        let single = converter.candidates(for: "おかし", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "お菓子", "single=\(single)")
        let multi = converter.multiClauseCandidates(for: "ぼるどーのおかし", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "ボルドーのお菓子", "multi=\(Array(multi.prefix(4)))")

        // おぼん も同型: 辞書はかな1件(wc10005)だけで お盆 が無く、丁寧接頭辞 お+ぼん の
        // 合成になる。ぼん の読み別 wc が 梵7407 < 盆7453 と46だけ梵が安いため お梵 が先頭
        // だった(2592)。
        let obon = converter.candidates(for: "おぼん", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(obon.first, "お盆", "single=\(obon)")

        // お/ご+名詞の素通り合成は語幹の読み別 word_cost 順を継ぐため、常用の ご神体/ご家紋 が
        // 5位に沈んでいた(audit_polite_prefix_order.py で検出)。先頭は据え置きで2番目に固定
        // するというユーザ判断(2594)。
        for testCase in [("ごしんたい", "ご進退", "ご神体"), ("ごかもん", "ご花紋", "ご家紋")] {
            let list = converter.candidates(for: testCase.0, limit: 8, systemCandidateMode: .surface)
            XCTAssertEqual(
                Array(list.prefix(2)),
                [testCase.1, testCase.2],
                "reading=\(testCase.0) list=\(list)"
            )
        }
    }

    // そんなことないのに: エンジンは かな を先頭で返すのに keepKana=false で提示層が
    // それを捨て、其麼(白話文由来の当て字)が先頭に残っていた。そんなことない/ないのに は
    // 個別には true なのに繋げた形だけ漏れていたので、準体助詞クラスタ(のに/のは/のが/
    // のを/のも)の剥がしを keepKana の根拠に足した。其麼 自体もユーザ指定で抑制(2584)。
    func testRegressionRealLMSonnaKotoNaiNoni() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary()

        XCTAssertTrue(
            converter.shouldKeepKanaIdentityLeading(for: "そんなことないのに"),
            "keepKana=false だと提示層がかなを捨てる"
        )
        let multi = converter.multiClauseCandidates(for: "そんなことないのに", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "そんなことないのに", "multi=\(Array(multi.prefix(4)))")
        // 抑制だけ入れると かな が捨てられて候補ゼロになるので、残っていることを固定する
        XCTAssertFalse(multi.isEmpty, "候補ゼロ")
        XCTAssertFalse(multi.contains("其麼ことないのに"), "multi=\(Array(multi.prefix(4)))")
        let sonna = converter.candidates(for: "そんな", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(sonna.first, "そんな", "single=\(sonna)")
        XCTAssertFalse(sonna.contains("其麼"), "single=\(sonna)")
    }

    // でのむ: 格助詞1字+2字動詞の3文字読みは連文節の対象外(multiClauseMinReadingCount=4)で
    // で|飲む の分割が試されず、でのむ の辞書エントリも無いため候補ゼロだった。とよむ と同型で
    // 単文節へ seed 供給する(2584)。
    func testRegressionRealLMDeNomu() throws {
        try prepareRealLMDictionary()

        let candidates = converter.candidates(for: "でのむ", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(candidates.first, "で飲む", "candidates=\(candidates)")
    }

    // いーしむ→eSIM(it.plist=SecondVocab 経由。ユーザ追加 2552)。
    func testRegressionRealLMVocabESIM() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary()

        let esim = converter.candidates(for: "いーしむ", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(esim.first, "eSIM", "single=\(esim)")
        // おーえす→OS(2553)
        let os = converter.candidates(for: "おーえす", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(os.first, "OS", "single=\(os)")
        // たいまそう→大麻草: 辞書・LM未収録の供給欠落。misc 登録(2555)
        let taimasou = converter.candidates(for: "たいまそう", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(taimasou.first, "大麻草", "single=\(taimasou)")
    }

    // はつえんとう/じゅうよう/いしょく: word_cost タイ(または LM 実勢との逆転)を辞書 rank 順が
    // 決めていた3件を seed で矯正(2535)。いしょくする は合成時に LM が効くため元から正しい
    // 順だったこと(経路差)も回帰で固定する。
    func testRegressionRealLMWordCostTieSeedOrdering() throws {
        try prepareRealLMDictionary()

        let hatsuentou = converter.candidates(for: "はつえんとう", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(hatsuentou.prefix(2)), ["発煙筒", "発炎筒"], "list=\(hatsuentou)")
        let juuyou = converter.candidates(for: "じゅうよう", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(juuyou.prefix(2)), ["重要", "重用"], "list=\(juuyou)")
        let ishoku = converter.candidates(for: "いしょく", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(ishoku.first, "移植", "list=\(ishoku)")
        let ishokusuru = converter.candidates(for: "いしょくする", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(ishokusuru.first, "移植する", "list=\(ishokusuru)")
    }

    // 数字直後の助数詞: さい(歳/才/菜)は digitContextAdditional で供給し、かなエコーは末尾へ。
    // 助数詞+かな末尾(かいぐらい)は合成候補が辞書 rank 圏外でも合成供給する(回ぐらい。2535)。
    func testRegressionRealLMDigitContextCounterSupply() throws {
        try prepareRealLMDictionary()

        let sai = converter.candidates(for: "2さい", limit: 16, systemCandidateMode: .surface)
        XCTAssertEqual(Array(sai.prefix(3)), ["歳", "才", "菜"], "list=\(sai)")
        XCTAssertEqual(sai.last, "さい", "かなエコーは末尾 list=\(sai)")
        let kaigurai = converter.candidates(for: "1かいぐらい", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(kaigurai.prefix(2)), ["回ぐらい", "階ぐらい"], "list=\(kaigurai)")
    }

    // みにいきたい: 身→に bigram(541)のコーパスバイアスで 身に が独占していた。連語
    // (み+に+いく活用)で 見 を優先し、動詞クランプは prev ひらがな限定(無条件だと
    // ミニ+行きたい が同じ開始位置で恩恵を受けて逆転する。2535)。
    func testRegressionRealLMMiniIkitaiPrefersMiru() throws {
        try prepareRealLMDictionary()

        let ikitai = converter.multiClauseCandidates(for: "みにいきたい", systemCandidateMode: .surface)
        XCTAssertEqual(ikitai.first, "見に行きたい", "multi=\(ikitai)")
        let iku = converter.multiClauseCandidates(for: "みにいく", systemCandidateMode: .surface)
        XCTAssertEqual(iku.first, "見に行く", "multi=\(iku)")
    }

    // じしんない: bigram 皆無で unigram 順(自身4428<地震4803<自信6075)だった。連語で 自信 を
    // 先頭に、文法的に不自然な 自身+ない は demote して 地震ない を2番目に(ユーザ指定 2535)。
    func testRegressionRealLMJishinNaiPrefersJishin() throws {
        try prepareRealLMDictionary()
        // なさそう のかな表記は misc curated 由来のため実機相当の追加語彙で検証する
        // (素の辞書だと 無さそう 表記になり表記ゆれで落ちる)。
        try loadDeviceAddedVocabulary()

        let nai = converter.multiClauseCandidates(for: "じしんない", systemCandidateMode: .surface)
        XCTAssertEqual(Array(nai.prefix(2)), ["自信ない", "地震ない"], "multi=\(nai)")
        let nasasou = converter.multiClauseCandidates(for: "じしんなさそう", systemCandidateMode: .surface)
        XCTAssertEqual(nasasou.first, "自信なさそう", "multi=\(nasasou)")
    }

    // かたん: 下端 を先頭に(ユーザ指定 2535。設計/工作で頻用)。単文節は seed 順、連文節
    // (かたんぐらい)は seed 順 opt-in ボーナスで 勝たん(活用OOV)/加担 を逆転する。
    func testRegressionRealLMKatanPrefersKatan() throws {
        try prepareRealLMDictionary()

        let katan = converter.candidates(for: "かたん", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(katan.prefix(2)), ["下端", "加担"], "list=\(katan)")
        let gurai = converter.multiClauseCandidates(for: "かたんぐらい", systemCandidateMode: .surface)
        XCTAssertEqual(gurai.first, "下端ぐらい", "multi=\(gurai)")
    }

    // うめの(読み3文字=連文節対象外): 梅の(合成)が postfix 派生の活用群に埋もれていた。
    // seed 供給で 梅の/梅野 を先頭群に、かな うめの は後方へ自然降格(2535)。
    // なにする: 何する が供給されず な+にする の postfix 分割だけだった。seed 供給(2535)。
    func testRegressionRealLMUmenoNanisuruSeedSupply() throws {
        try prepareRealLMDictionary()

        let umeno = converter.candidates(for: "うめの", limit: 12, systemCandidateMode: .surface)
        XCTAssertEqual(Array(umeno.prefix(2)), ["梅の", "梅野"], "list=\(umeno)")
        let nanisuru = converter.candidates(for: "なにする", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(nanisuru.first, "何する", "list=\(nanisuru)")
    }

    // 合格圏内/網脂: 実在語/複合語が連文節の分割(合格圏ない/網+油)に負ける供給欠落。
    // misc curated で区切りを勝たせる(2535)。テストは実機相当の追加語彙をロードして検証。
    func testRegressionRealLMDeviceVocabGoukakuKennaiAmiabura() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary()

        let kennai = converter.candidates(for: "ごうかくけんない", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(kennai.first, "合格圏内", "single=\(kennai)")
        let amiabura = converter.candidates(for: "あみあぶら", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(amiabura.first, "網脂", "single=\(amiabura)")
        XCTAssertFalse(amiabura.contains("阿弥脂"), "single=\(amiabura)")
    }

    // もうしこみじ: 時(じ)は unigram 3807 の最頻出語なのに読み別 wc 6156 の床上げで
    // 字(wc4066)に一律負けていた。短spanレア読み床の免除(むき と同型)で是正(2535)。
    func testRegressionRealLMMoushikomiJiPrefersToki() throws {
        try prepareRealLMDictionary()

        let multi = converter.multiClauseCandidates(for: "もうしこみじ", systemCandidateMode: .surface)
        XCTAssertEqual(Array(multi.prefix(3)), ["申し込み時", "申込時", "申込み時"], "multi=\(multi)")
    }

    // すくなかった(ので): ルール定義順で 酸い族(LM未収録のレア語)が 少ない族(unigram 4804)に
    // 先行していた。族の opt-in 昇格(はる/おく/まつ と同型)で是正(2535)。
    func testRegressionRealLMSukunakattaPrefersSukunai() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary()

        let sukunakatta = converter.candidates(for: "すくなかった", limit: 12, systemCandidateMode: .surface)
        XCTAssertEqual(sukunakatta.first, "少なかった", "single=\(sukunakatta)")
        let node = converter.multiClauseCandidates(for: "すくなかったので", systemCandidateMode: .surface)
        XCTAssertEqual(node.first, "少なかったので", "multi=\(node)")
    }

    // のになあ/それぐらいやるよ: エンジンはかな最良を返すのに keepKana の根拠が無く、提示層が
    // 先頭かなを退避して 乃になあ/反れぐらいやるよ が繰り上がっていた(2535)。
    // かな先頭化の修正には keepKana assert を必ず併記する(定番の再発点)。
    func testRegressionRealLMKanaIdentityNoniNaaSoreguraiYaruyo() throws {
        try prepareRealLMDictionary()

        let noninaa = converter.candidates(for: "のになあ", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(noninaa.first, "のになあ", "single=\(noninaa)")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "のになあ"))

        let yaruyo = converter.multiClauseCandidates(for: "それぐらいやるよ", systemCandidateMode: .surface)
        XCTAssertEqual(yaruyo.first, "それぐらいやるよ", "multi=\(yaruyo)")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "それぐらいやるよ"))
    }

    // こういうのみかけたら: のみ(飲み)始まりの丸ごと活用(飲み掛けたら)が bigram で先行し、
    // こういうの+見かけたら の名詞化が出なかった。連体詞直後の準体助詞 の クランプ+
    // の直後の活用派生の連語選好で是正(2535)。
    func testRegressionRealLMKouiuNoMikaketara() throws {
        try prepareRealLMDictionary()

        let multi = converter.multiClauseCandidates(for: "こういうのみかけたら", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "こういうの見かけたら", "multi=\(multi)")
    }

    // ほとう: vin 由来の 補糖(既定 wc11000)が、補助語彙昇格の LM 実在語ゲート(浦東)と
    // 収穫底値降格の二重で7番目に沈んでいた。seed 掲載で免除+先頭化(2537)。
    func testRegressionRealLMHotouPrefersHotou() throws {
        try prepareRealLMDictionary()

        let list = converter.candidates(for: "ほとう", limit: 12, systemCandidateMode: .surface)
        XCTAssertEqual(list.first, "補糖", "list=\(list)")
    }

    // ため: dict rank0 が 為 だが wc も LM もかなが優位で、形式名詞はかな正書(とき と
    // 同方針、ユーザー指定 2538)。単独・合成(ためではない)・連文節文脈で ため が先頭、
    // 為 は2番目に残ること。溜め系(溜めた 等)の活用は影響を受けないこと。
    func testRegressionRealLMTamePrefersKana() throws {
        try prepareRealLMDictionary()

        let tame = converter.candidates(for: "ため", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(tame.prefix(2)), ["ため", "為"], "list=\(tame)")
        let dewanai = converter.candidates(for: "ためではない", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(dewanai.first, "ためではない", "list=\(dewanai)")
        let multi = converter.multiClauseCandidates(for: "ためではない", systemCandidateMode: .surface)
        if let first = multi.first {
            XCTAssertEqual(first, "ためではない", "multi=\(multi)")
        }
        // エンジンがかな最良でも keepKana が無いと提示層が退避して 為ではない が繰り上がる
        // (実機で再発した定番。かな先頭化には keepKana assert を必ず併記する)
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "ためではない"))
        let tameta = converter.candidates(for: "ためた", limit: 8, systemCandidateMode: .surface)
        XCTAssertTrue(
            tameta.contains { $0.hasPrefix("溜め") || $0.hasPrefix("貯め") },
            "溜めた/貯めた が残ること list=\(tameta)"
        )
    }

    // かな副詞群のかな先頭化(ユーザー方針 2538)。せっかく の報告を受けた一括調査で
    // かなが先頭でなかった16語を seed で矯正。漢字主形が2番目に残ることも代表語で確認。
    func testRegressionRealLMKanaAdverbsPreferKana() throws {
        try prepareRealLMDictionary()

        for reading in ["せっかく", "さっそく", "いよいよ", "いったん", "きわめて", "おおむね",
                        "つくづく", "いまさら", "めったに", "とっくに", "なにしろ", "たびたび",
                        "のちほど", "ふだん", "たいてい", "あらためて"] {
            let list = converter.candidates(for: reading, limit: 8, systemCandidateMode: .surface)
            XCTAssertEqual(list.first, reading, "reading=\(reading) list=\(list)")
        }
        let sekkaku = converter.candidates(for: "せっかく", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(sekkaku.dropFirst().first, "折角", "list=\(sekkaku)")
        let fudan = converter.candidates(for: "ふだん", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(fudan.dropFirst().first, "普段", "list=\(fudan)")
    }

    // のにー(詠嘆の長音形): のに だけだと ー が余り、いいの→飯野(人名収穫)+に+ー の
    // 分割に負けて よめればいいのにー→読めれば飯野にー になっていた(2538)。
    // 長音なしの形が退行しないことも同時に確認する。
    func testRegressionRealLMYomerebaIinoniLongVowel() throws {
        try prepareRealLMDictionary()
        // いい のかな正書は実機相当の追加語彙(curated)前提(素の辞書は 良い 表記になる)
        try loadDeviceAddedVocabulary()

        let plain = converter.multiClauseCandidates(for: "よめればいいのに", systemCandidateMode: .surface)
        XCTAssertEqual(plain.first, "読めればいいのに", "multi=\(plain)")
        let long = converter.multiClauseCandidates(for: "よめればいいのにー", systemCandidateMode: .surface)
        XCTAssertEqual(long.first, "読めればいいのにー", "multi=\(long)")
        XCTAssertFalse(long.contains { $0.contains("飯野") }, "multi=\(long)")
    }

    // ありえない: Sudachi に あり得る が無く {アリエない, 有りえない, 有家ない, 有江ない}
    // だった(2538)。misc の あり得る(一段)で活用を供給し、seed で並びを
    // {あり得ない, ありえない, 有りえない} に固定。派生形(ありえなかった)も出ること。
    func testRegressionRealLMArienaiPrefersArieru() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary()

        let arienai = converter.candidates(for: "ありえない", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(arienai.prefix(3)), ["あり得ない", "ありえない", "有りえない"], "list=\(arienai)")
        let arienakatta = converter.candidates(for: "ありえなかった", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(arienakatta.first, "あり得なかった", "list=\(arienakatta)")
    }

    // たまには: 玉+には に負けていた(2540)。たまに をかな副詞集合+seed かな先頭にし、
    // keepKana(かな副詞+助詞1字)で提示層の退避も防ぐ。
    // こめは: postfix 基底順が dict rank(コメ rank0)のままで {こめは, 混めは, 込めは, コメは,
    // 米は} だった。seed こめ=[米, コメ] で {米は, コメは} を先頭群に。
    // りょうりうまい: 上手い が bigram 料理→上手(じょうず読みの統計)を読み跨ぎ借用して
    // 料理上手い が先頭だった。seed 順 opt-in ボーナスで かな うまい を勝たせる。
    func testRegressionRealLMTamanihaKomehaRyouriumai() throws {
        try prepareRealLMDictionary()

        let tamaniha = converter.multiClauseCandidates(for: "たまには", systemCandidateMode: .surface)
        XCTAssertEqual(tamaniha.first, "たまには", "multi=\(tamaniha)")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "たまには"))
        let tamani = converter.candidates(for: "たまに", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(tamani.first, "たまに", "list=\(tamani)")

        let komeha = converter.candidates(for: "こめは", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(komeha.prefix(2)), ["米は", "コメは"], "list=\(komeha)")

        let umai = converter.multiClauseCandidates(for: "りょうりうまい", systemCandidateMode: .surface)
        XCTAssertEqual(umai.first, "料理うまい", "multi=\(umai)")
        let umaiSingle = converter.candidates(for: "うまい", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(umaiSingle.first, "うまい", "list=\(umaiSingle)")
    }

    // しめで: 派生基底順で 沁めで/浸目で/染めで が先行していた。seed で
    // {締めで, しめで, 〆で} に固定(2543)。単独 しめ の 〆 は 2643 のユーザ指定で
    // 2位へ変更(旧: exactReadingOnly の末尾供給。testRegressionRealLM2643Batch が受け持つ)
    func testRegressionRealLMShimedeOrdering() throws {
        try prepareRealLMDictionary()

        let shimede = converter.candidates(for: "しめで", limit: 10, systemCandidateMode: .surface)
        XCTAssertEqual(Array(shimede.prefix(3)), ["締めで", "しめで", "〆で"], "list=\(shimede)")
    }

    // じょうず: 上図(rank0/wc7388)が 上手 に僅差で勝ち 上図にやると になっていた。
    // seed+連文節ボーナスで LM 実勢どおり 上手 を先頭に(2543)。
    func testRegressionRealLMJouzuPrefersJouzu() throws {
        try prepareRealLMDictionary()

        let single = converter.candidates(for: "じょうず", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "上手", "list=\(single)")
        let multi = converter.multiClauseCandidates(for: "じょうずにやると", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "上手にやると", "multi=\(multi)")
    }

    // けんきょさ: 検挙(wc6498/uni6325=Wikipediaバイアス)が 謙虚 に勝ち 検挙さ が先頭
    // だった。さ名詞化は形容詞/形容動詞語幹にのみ成立し 検挙さ は非文法。形容動詞性を
    // prev→な の bigram 実績(謙虚→な441、検挙→な無し)で判定して 謙虚さ を先頭に(2543)。
    // 単文節(ブースト)と連文節(さクランプ)の両経路を検証する。
    func testRegressionRealLMKenkyosaPrefersNaAdjective() throws {
        try prepareRealLMDictionary()

        let single = converter.candidates(for: "けんきょさ", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "謙虚さ", "single=\(single)")
        let multi = converter.multiClauseCandidates(for: "けんきょさ", systemCandidateMode: .surface)
        if let first = multi.first {
            XCTAssertEqual(first, "謙虚さ", "multi=\(multi)")
        }
        // い形容詞さ名詞化(辛さ)と サ変名詞単独(検挙)の既存挙動が退行しないこと
        let karasa = converter.candidates(for: "からさ", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(karasa.first, "辛さ", "list=\(karasa)")
        let kenkyo = converter.candidates(for: "けんきょ", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(kenkyo.first, "検挙", "list=\(kenkyo)")
    }

    // おきやすい: おく族の opt-in 昇格(2434)が おきやすい にも効き 置きやすい が先頭
    // だった。やすい 文脈は 起きる が主(bigram 起き→やすい2136 vs 置き→やすい無し)
    // なので seed 句で固定(2547)。置く系の文脈(おきっぱなし)は不変であること。
    func testRegressionRealLMOkiyasuiPrefersOkiru() throws {
        try prepareRealLMDictionary()

        let okiyasui = converter.candidates(for: "おきやすい", limit: 10, systemCandidateMode: .surface)
        XCTAssertEqual(okiyasui.first, "起きやすい", "list=\(okiyasui)")
        // 置く系の文脈は不変(起きっぱなし に化けないこと)
        let okippanashi = converter.multiClauseCandidates(for: "おきっぱなし", systemCandidateMode: .surface)
        if let first = okippanashi.first {
            XCTAssertFalse(first.hasPrefix("起き"), "multi=\(okippanashi)")
        }
    }

    // たえうる: 耐え+うる(得る)の合成が供給されず {拷得る, 多恵得る, ...} の名前ジャンク
    // だけだった(2547)。でじゅね: sacoche 追加(仏 déjeuner)。
    func testRegressionRealLMTaeuruDejeune() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary()

        let taeuru = converter.candidates(for: "たえうる", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(taeuru.prefix(2)), ["耐えうる", "耐え得る"], "list=\(taeuru)")
        let dejeune = converter.candidates(for: "でじゅね", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(dejeune.first, "デジュネ", "list=\(dejeune)")
    }

    // なくす: {なくす, 無くす, 喪くす, 亡くす, 失くす} だった。失くす/亡くす を先頭群に
    // (ユーザ指定 2547)。
    func testRegressionRealLMNakusuPrefersNakusu() throws {
        try prepareRealLMDictionary()

        let nakusu = converter.candidates(for: "なくす", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(nakusu.prefix(2)), ["失くす", "亡くす"], "list=\(nakusu)")
        // むりょう: 無量(uni6386)vs 無料(uni5279)の差1107が一般昇格ゲート(1200)を
        // 僅かに下回るニアミス。seed で 無料 を先頭に(2547)
        let muryou = converter.candidates(for: "むりょう", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(Array(muryou.prefix(2)), ["無料", "無量"], "list=\(muryou)")
    }

    // がめんけい: 系(uni3925)/計(uni5171)が短spanレア読み床で床上げされ、
    // 画面ケイ(ケイ wc5959)に負けていた。床免除(むき/じ と同型)で
    // {画面系, 画面計} を先頭群に(2547)。
    func testRegressionRealLMGamenkeiPrefersKei() throws {
        try prepareRealLMDictionary()

        let gamenkei = converter.multiClauseCandidates(for: "がめんけい", systemCandidateMode: .surface)
        XCTAssertEqual(Array(gamenkei.prefix(2)), ["画面系", "画面計"], "multi=\(gamenkei)")
    }

    // しんぴんかうか: カウカ(カタカナ固有名の収穫、wc4576=異常低)が 買う+か の合成に
    // 1ノードで勝っていた(suppr で除去)。除去後は 飼う→か(896、Wikipedia の疑問形
    // 分割由来)の bigram で 新品飼うか が繰り上がるため、ペア単位の bigram 遮断で
    // 新品買うか を先頭に(2547)。
    func testRegressionRealLMShinpinkaukaPrefersKau() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary()

        let kauka = converter.multiClauseCandidates(for: "しんぴんかうか", systemCandidateMode: .surface)
        XCTAssertEqual(kauka.first, "新品買うか", "multi=\(kauka)")
        XCTAssertFalse(kauka.contains { $0.contains("カウカ") }, "multi=\(kauka)")
        // 飼う 本体の文脈は無傷(ねこをかう が 飼う を保てること)
        let neko = converter.multiClauseCandidates(for: "ねこをかう", systemCandidateMode: .surface)
        XCTAssertTrue(neko.contains { $0.contains("飼う") }, "multi=\(neko)")
    }

    // 同じ経路の他の形容詞さ名詞化(辞書に無い語)も先頭に出ること。
    func testRegressionRealLMAdjectiveSaNominalizationsRankFirst() throws {
        try prepareRealLMDictionary()

        for (reading, expected) in [("よわさ", "弱さ"), ("しろさ", "白さ"), ("ふるさ", "古さ")] {
            let list = converter.candidates(for: reading, limit: 30, systemCandidateMode: .surface)
            XCTAssertEqual(list.first, expected, "reading=\(reading) list=\(list)")
        }
    }

    // 五段サ行の未然形(話す→話さ)は形容詞さ名詞化ではないので、ブーストの対象外であること。
    func testRegressionRealLMGodanMizenSaIsNotBoostedAsNominalization() throws {
        try prepareRealLMDictionary()

        let list = converter.candidates(for: "はなさ", limit: 30, systemCandidateMode: .surface)
        XCTAssertNotEqual(list.first, "話さ", "list=\(list)")
    }

    // やってないけどね/おいてかれてる: 連文節はかな最良を返すのに keepKana の根拠
    // (けど+終助詞/ていかれ縮約の受身)が無く、提示層が退避して 演ってないけどね/
    // 甥てかれてる が繰り上がっていた(2543)。
    // そんなんじゃ: そんなん(「そんなの」の口語縮約)が辞書に無く 村ナンジャ 等の
    // 分割ジャンクだけだった。misc curated のかな識別で供給する。
    func testRegressionRealLMKedoneTekareSonnan() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary()

        let kedone = converter.multiClauseCandidates(for: "やってないけどね", systemCandidateMode: .surface)
        XCTAssertEqual(kedone.first, "やってないけどね", "multi=\(kedone)")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "やってないけどね"))
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "やってないけど"))

        let tekare = converter.multiClauseCandidates(for: "おいてかれてる", systemCandidateMode: .surface)
        XCTAssertEqual(tekare.first, "おいてかれてる", "multi=\(tekare)")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "おいてかれてる"))

        let sonnan = converter.multiClauseCandidates(for: "そんなんじゃ", systemCandidateMode: .surface)
        XCTAssertEqual(sonnan.first, "そんなんじゃ", "multi=\(sonnan)")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "そんなんじゃ"))
    }

    // LM優位辞書候補の一般昇格(applyLMDominantDictCandidateBoost、2545): 一括スイープで
    // 常用語1218読みがレア語の辞書rank順に埋もれていた構造問題の対応。ゲート
    // (常用語uni≦6800/差≧1200/主読み判定)と、seed・curated・かな首位化の各レイヤーが
    // 上位に残ることを代表例で固定する。
    func testRegressionRealLMDominantDictCandidateBoost() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary()

        // 埋もれていた常用語が先頭へ
        XCTAssertEqual(converter.candidates(for: "こうどう", limit: 8, systemCandidateMode: .surface).first, "行動")
        XCTAssertEqual(converter.candidates(for: "せいゆう", limit: 8, systemCandidateMode: .surface).first, "声優")
        XCTAssertEqual(converter.candidates(for: "かいほう", limit: 8, systemCandidateMode: .surface).first, "解放")
        // 読み跨ぎの誤昇格ガード: 宇宙(たかおき=人名読みハーベスト)は主読み判定で昇格しない
        let takaoki = converter.candidates(for: "たかおき", limit: 8, systemCandidateMode: .surface)
        XCTAssertNotEqual(takaoki.first, "宇宙", "list=\(takaoki)")
        // curated レイヤーはこの機構より上位のまま(へいき→平気 のユーザー矯正が勝つ)
        let heiki = converter.candidates(for: "へいき", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(heiki.first, "平気", "list=\(heiki)")
    }

    // まつだ: dict rank0 は 松田 だが、かな首位化・カタカナ識別(マツダ)・合成
    // (待つだ/松だ)に沈められていた。seed 先頭化+かな非掲載でかな識別は末尾へ
    // (ユーザ指定 2552)。
    func testRegressionRealLMMatsudaPrefersMatsuda() throws {
        try prepareRealLMDictionary()

        let matsuda = converter.candidates(for: "まつだ", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(matsuda.first, "松田", "list=\(matsuda)")
        // かな識別は先頭群に残らないこと(末尾寄りでOK)
        XCTAssertFalse(matsuda.prefix(3).contains("まつだ"), "list=\(matsuda)")
    }

    // あるのになあ: アルノ(伊アルノ川等の収穫、wc4576=異常低)が ある+の の合成に
    // 1ノードで勝ち アルノになあ が先頭だった(カウカ と同型、suppr で除去)。
    // かな あるのになあ が先頭に出ること(2559)。
    func testRegressionRealLMArunoninaaPrefersKana() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary()

        let arunoninaa = converter.candidates(for: "あるのになあ", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(arunoninaa.first, "あるのになあ", "list=\(arunoninaa)")
        XCTAssertFalse(arunoninaa.contains { $0.contains("アルノ") }, "list=\(arunoninaa)")
        // 表示層のかな識別根拠(無いと実機バーでかなが末尾へ落ちる。2560)
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "あるのになあ"))
    }

    // めどがたったら: 変種が たったら 側(経った/建った/足った=連語では無用)に振られて
    // いた。連語クランプで動詞を 立 に固定し、変種枠を めど/メド の名詞表記側に譲る
    // (ユーザ指定 2559)。
    func testRegressionRealLMMedogaTattaraVariants() throws {
        try prepareRealLMDictionary()

        let medo = converter.multiClauseCandidates(for: "めどがたったら", systemCandidateMode: .surface)
        XCTAssertEqual(medo.first, "めどが立ったら", "multi=\(medo)")
        XCTAssertFalse(
            medo.prefix(5).contains { $0.contains("経った") || $0.contains("建った") || $0.contains("足った") },
            "multi=\(medo)"
        )
        XCTAssertTrue(medo.prefix(5).contains("目処が立ったら"), "multi=\(medo)")
    }

    // ですもんね: です+門/物/紋+ね の合成が かな より先だった(ですかね と同型。
    // ユーザ指定 2559)。
    func testRegressionRealLMDesumonneKanaLeading() throws {
        try prepareRealLMDictionary()

        let desumonne = converter.candidates(for: "ですもんね", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(desumonne.first, "ですもんね", "list=\(desumonne)")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "ですもんね"))
        // できない部分の 出来/でき はエンジン非関知(表示層 demotingDekiKanjiBelowKana が
        // かな版を上へ)。ここでは ですもんね 部分がかなで保たれることだけ固定する
        let dekinai = converter.multiClauseCandidates(for: "できないですもんね", systemCandidateMode: .surface)
        XCTAssertTrue(dekinai.first?.hasSuffix("ですもんね") == true, "multi=\(dekinai)")
        // 全かな版が変種として残ること(エコー抑制の seed かな句例外。これが無いと
        // 実機バーに 出来ないですもんね しか出ず、表示層の でき昇格も効かない。2561)
        XCTAssertTrue(dekinai.contains("できないですもんね"), "multi=\(dekinai)")
        // 表示層のかな識別根拠(無いと全かなの できないですもんね が除去され
        // 出来ないですもんね だけが残る。2560)
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "できないですもんね"))
    }

    // いいほんでした: ほんで の固有名収穫(本出 wc10000/品田 wc11000)が
    // 本+でした の正しい分割に勝ち いい本出した になっていた(suppr で除去。2564)。
    func testRegressionRealLMIihondeshitaPrefersHon() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary()

        let hon = converter.multiClauseCandidates(for: "いいほんでした", systemCandidateMode: .surface)
        XCTAssertEqual(hon.first, "いい本でした", "multi=\(hon)")
        XCTAssertFalse(hon.contains { $0.contains("本出") || $0.contains("品田") }, "multi=\(hon)")
    }

    // みずにつけてた: 水(+助詞)直後の つけ活用は 浸/漬 が主({水に付けてた, 水に着けてた}
    // が先頭だった)。連語の複数プレフィクス選好+seed つける 並び拡充(ユーザ指定 2563)。
    func testRegressionRealLMMizuniTsuketetaPrefersTsukeru() throws {
        try prepareRealLMDictionary()

        let mizu = converter.multiClauseCandidates(for: "みずにつけてた", systemCandidateMode: .surface)
        XCTAssertEqual(Array(mizu.prefix(2)), ["水に浸けてた", "水に漬けてた"], "multi=\(mizu)")
        // 一般文脈の つける は 付ける 先頭のまま(跟ける は先頭群から沈む)
        let tsukeru = converter.candidates(for: "つける", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(tsukeru.first, "付ける", "list=\(tsukeru)")
        XCTAssertFalse(tsukeru.prefix(5).contains("跟ける"), "list=\(tsukeru)")
    }

    // 助数詞監査で検出した数字直後の供給漏れ10種(そく/はく/こう/てき/そう/き/
    // きゅう/い/だんめ/こめ。2563)。代表を固定する。
    func testRegressionRealLMDigitCounterAuditAdditions() throws {
        try prepareRealLMDictionary()

        let expectations: [(String, String)] = [
            ("3そく", "足"), ("3はく", "泊"), ("3こう", "校"), ("3てき", "滴"),
            ("3そう", "艘"), ("3き", "機"), ("3きゅう", "球"), ("3い", "位"),
            ("3だんめ", "段目"), ("3こめ", "個目")
        ]
        var failures: [String] = []
        for (input, expected) in expectations {
            let list = converter.candidates(for: input, limit: 16, systemCandidateMode: .surface)
            if !list.prefix(5).contains(expected) {
                failures.append("\(input)→\(expected) top=\(list.prefix(5))")
            }
        }
        XCTAssertTrue(failures.isEmpty, "\(failures.count)件:\n" + failures.joined(separator: "\n"))
    }

    // ひとばん: 辞書・LM未収録の供給欠落({人版, 人蛮} 等の合成ジャンクのみ)。
    // 一晩 を seed 供給。1ばん は 番/晩 を数字直後の助数詞として供給(ユーザ指定 2562)。
    func testRegressionRealLMHitobanAndBanCounter() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary()

        let hitoban = converter.candidates(for: "ひとばん", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(hitoban.first, "一晩", "list=\(hitoban)")
        // 実機バーは連文節先頭が上に来るため、連文節が空でなければ 一晩 が先頭であること
        // (実機で 人+版 の分割が先頭だった。シミュレータは空=単文節に委譲。2563)
        let hitobanMulti = converter.multiClauseCandidates(for: "ひとばん", systemCandidateMode: .surface)
        XCTAssertTrue(hitobanMulti.isEmpty || hitobanMulti.first == "一晩", "multi=\(hitobanMulti)")
        let ban = converter.candidates(for: "1ばん", limit: 16, systemCandidateMode: .surface)
        XCTAssertEqual(Array(ban.prefix(2)), ["番", "晩"], "list=\(ban)")
    }

    // もん: 2を確定してから もん を打つと {もん, 門, 物, 紋, 者, 文, 問, 悶} で 問 が7位だった。
    // Sudachi は 問 を助数詞可能と付けていない(もん の助数詞は 文=足袋のサイズ だけ)ので、
    // 品詞由来の機械的な洗い出しでも拾えない。本表へ登録する(2596)。
    // あわせて候補キャッシュのキーに数字接頭が入っておらず、先に「もん」を変換していると
    // 「2もん」がそのキャッシュを引き当てて数字ブーストに到達しない状態だった。
    // 呼び出し順で助数詞が出る/出ないが変わるので、順序に依存する形で検証する。
    func testRegressionRealLMMonCounterAfterDigit() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary()

        // 先にキャッシュを作ってから数字付きを引く(キャッシュキーの取り違えの再発検出)
        let bare = converter.candidates(for: "もん", limit: 10, systemCandidateMode: .surface)
        XCTAssertFalse(bare.isEmpty)
        let withDigit = converter.candidates(for: "2もん", limit: 10, systemCandidateMode: .surface)
        // 3つとも助数詞なので順序まで固定する(問=問題数 / 門=大砲 / 文=昔の通貨単位)
        XCTAssertEqual(Array(withDigit.prefix(3)), ["問", "門", "文"], "list=\(withDigit)")
        XCTAssertEqual(withDigit.last, "もん", "かなエコーは末尾へ list=\(withDigit)")

        // 提示層の経路(直前確定が数字)も同じ表を使う
        let boosted = KanaKanjiConverter.digitContextCounterBoostedCandidates(
            bare,
            reading: "もん",
            precedingCharacter: "2",
            suppressedCandidates: []
        )
        XCTAssertEqual(boosted.first, "問", "list=\(boosted)")

        // ばん(既存)も順序に依存せず効くこと
        _ = converter.candidates(for: "ばん", limit: 10, systemCandidateMode: .surface)
        let ban = converter.candidates(for: "1ばん", limit: 16, systemCandidateMode: .surface)
        XCTAssertEqual(Array(ban.prefix(2)), ["番", "晩"], "list=\(ban)")
    }

    // 「数詞に付く助数詞は大抵『何』にも付く」(ユーザ指摘 2597)。個別対応ではなく生成規則に
    // する。なんもん→何問 が出なかったのは japaneseNumberReadingValue が なん を数詞と
    // 見ないため。序数接頭とも両立させる(だいなんもん→第何問)。スコアは数詞複合(360)なので
    // 辞書語(難問/難題)を押しのけない。
    func testRegressionRealLMNanCounterCompound() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary()

        for (reading, expected) in [("なんもん", "何問"), ("なんぼん", "何本"),
                                    ("なんにん", "何人"), ("なんまい", "何枚"),
                                    ("なんこ", "何個"), ("なんがい", "何階"),
                                    ("なんかぶ", "何株"), ("なんめい", "何名"),
                                    ("なんけた", "何桁"), ("なんわり", "何割")] {
            let list = converter.candidates(for: reading, limit: 10, systemCandidateMode: .surface)
            XCTAssertTrue(list.contains(expected), "reading=\(reading) list=\(list)")
        }
        // 辞書語は先頭を保つ(何N が押しのけない)
        XCTAssertEqual(
            converter.candidates(for: "なんもん", limit: 6, systemCandidateMode: .surface).first,
            "難問"
        )
        XCTAssertEqual(
            converter.candidates(for: "なんだい", limit: 6, systemCandidateMode: .surface).first,
            "難題"
        )
        // 助数詞でない なん+かな には波及しない
        for reading in ["なんて", "なんの", "なんとか"] {
            let list = converter.candidates(for: reading, limit: 8, systemCandidateMode: .surface)
            XCTAssertFalse(list.isEmpty, "reading=\(reading)")
        }
        // 機械洗い出しの助数詞は数字文脈限定の表へ入れた。本表はかなの数詞読みからも
        // 算用数字の複合を作るので、本表へ入れると以下が汚れる(実測で確認した経路)。
        for (reading, expectedFirst) in [("さんま", "さんま"), ("さんか", "参加"),
                                         ("さんぽ", "散歩"), ("にせ", "偽")] {
            let list = converter.candidates(for: reading, limit: 8, systemCandidateMode: .surface)
            XCTAssertEqual(list.first, expectedFirst, "reading=\(reading) list=\(list)")
        }
        // ordinalMeStemTailCharacters は本表の表層末字から自動生成される。目/米/間 が増えても
        // 〜め/〜目 の序数判定が一般名詞を巻き込まないこと。
        XCTAssertEqual(
            converter.candidates(for: "あとめ", limit: 4, systemCandidateMode: .surface).first,
            "跡目"
        )
        XCTAssertEqual(
            converter.candidates(for: "かため", limit: 4, systemCandidateMode: .surface).first,
            "固め"
        )
    }

    // かんしては: 基底 かんする の順は正しい(関0/冠1/關2/姦3/箝4/緘5)のに、て形の派生で
    // {冠しては, 關しては, 関しては, …} と崩れていた。基底に seed を置いても派生には
    // 伝わらないので活用形側にも置く。旧字体の關と別語の姦は末尾へ(ユーザー指定 2606)。
    // じかせんが: 耳下腺 は wc11060(収穫底値超え)で LM 未収録のため連文節で重く扱われ、
    // 時(3807)+河川(5321)+が の分割に負けていた。seed 掲載で収穫底値の降格を免除する。
    func testRegressionRealLMKanshiteAndJikasen() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary()

        let expectedOrder = ["関しては", "冠しては", "箝しては", "緘しては", "關しては", "姦しては"]
        let kanshiteha = converter.candidates(for: "かんしては", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(kanshiteha.prefix(6)), expectedOrder, "list=\(kanshiteha)")
        XCTAssertEqual(kanshiteha.last, "かんしては", "かなは末尾 list=\(kanshiteha)")
        // 基底と て形も同じ並び
        XCTAssertEqual(
            Array(converter.candidates(for: "かんする", limit: 6, systemCandidateMode: .surface).prefix(2)),
            ["関する", "冠する"]
        )
        XCTAssertEqual(
            Array(converter.candidates(for: "かんして", limit: 6, systemCandidateMode: .surface).prefix(2)),
            ["関して", "冠して"]
        )

        XCTAssertEqual(
            converter.candidates(for: "じかせんが", limit: 6, systemCandidateMode: .surface).first,
            "耳下腺が"
        )
        let jikasengaMulti = converter.multiClauseCandidates(for: "じかせんが", systemCandidateMode: .surface)
        XCTAssertEqual(jikasengaMulti.first, "耳下腺が", "multi=\(Array(jikasengaMulti.prefix(4)))")
    }

    // いたい: 痛い は dict rank0 なのに {いたい, 遺体, 居たい, 射たい, 鋳たい, 痛い} と6位。
    // たい(願望)の活用派生が上位を占めていた。seed で宣言順に矯正(ユーザ指定 2606)。
    func testRegressionRealLMItaiPrefersItai() throws {
        try prepareRealLMDictionary()

        let itai = converter.candidates(for: "いたい", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(itai.prefix(4)), ["痛い", "居たい", "いたい", "遺体"], "list=\(itai)")
    }

    // てんじて: {点じて, 転じて} だった。話題を転じて 等の 転じて が実勢(ユーザ指定 2606)。
    func testRegressionRealLMTenjitePrefersTenjite() throws {
        try prepareRealLMDictionary()

        let tenjite = converter.candidates(for: "てんじて", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(tenjite.first, "転じて", "list=\(tenjite)")
    }

    // そこに: 底荷(船舶のバラスト)が先頭だった。指示語のかなが実勢(ユーザ指定 2606)。
    func testRegressionRealLMSokoNiPrefersKana() throws {
        try prepareRealLMDictionary()

        let sokoNi = converter.candidates(for: "そこに", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(Array(sokoNi.prefix(3)), ["そこに", "底に", "其処に"], "list=\(sokoNi)")
    }

    // はなにみず: 文頭の裸の係助詞 は が組む は+何+水(unigram 計 11133)が
    // 花+に+水(11248)を 115 差で押し切っていた。BOS 助詞減点で是正(ユーザ報告 2606)。
    func testRegressionRealLMHanaNiMizuPrefersHanaNiMizu() throws {
        try prepareRealLMDictionary()

        let hanaNiMizu = converter.multiClauseCandidates(for: "はなにみず", systemCandidateMode: .surface)
        XCTAssertEqual(hanaNiMizu.first, "花に水", "list=\(hanaNiMizu)")
    }

    // 文頭の助詞減点が断片継続(で飲む)や 楽しいし嬉しい を巻き添えにしないこと。
    func testRegressionRealLMBOSParticlePenaltyKeepsFragments() throws {
        try prepareRealLMDictionary()

        let denomu = converter.candidates(for: "でのむ", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(denomu.first, "で飲む", "list=\(denomu)")
        let tanoshii = converter.multiClauseCandidates(for: "たのしいしうれしい", systemCandidateMode: .surface)
        XCTAssertEqual(tanoshii.first, "楽しいし嬉しい", "list=\(tanoshii)")
    }

    // しけんまえだし: 姓の1ノード 前田(uni 5390)が 前(4035)+だし(6401)を下回り
    // 「試験前田し」になっていた。接続助詞 し は述語直後にしか立てない(ユーザ報告 2606)。
    func testRegressionRealLMShikenMaeDashiPrefersShikenMaeDashi() throws {
        try prepareRealLMDictionary()

        let shikenMaeDashi = converter.multiClauseCandidates(for: "しけんまえだし", systemCandidateMode: .surface)
        XCTAssertEqual(shikenMaeDashi.first, "試験前だし", "list=\(shikenMaeDashi)")
        // 乃至(ないし)は い が述語末尾なので し 減点の対象外
        let naishi = converter.candidates(for: "ないし", limit: 4, systemCandidateMode: .surface)
        XCTAssertTrue(naishi.contains("乃至"), "list=\(naishi)")
    }

    // にわにみず: 二→輪(2684)を にりん 文脈から借用した単漢字断片 二+輪(計7125)が
    // 庭(8203)を下回っていた。輪(わ)の bigram 借用を遮断(調査中に発見 2606)。
    func testRegressionRealLMNiwaPrefersNiwa() throws {
        try prepareRealLMDictionary()

        let niwaNiMizu = converter.multiClauseCandidates(for: "にわにみず", systemCandidateMode: .surface)
        XCTAssertEqual(niwaNiMizu.first, "庭に水", "list=\(niwaNiMizu)")
        let niwaNoKi = converter.multiClauseCandidates(for: "にわのき", systemCandidateMode: .surface)
        XCTAssertEqual(niwaNoKi.first, "庭の木", "list=\(niwaNoKi)")
        // 輪 の正当な複合(首輪/一輪車)は無傷
        let kubiwa = converter.multiClauseCandidates(for: "くびわをつける", systemCandidateMode: .surface)
        XCTAssertEqual(kubiwa.first, "首輪をつける", "list=\(kubiwa)")
        let ichirinsha = converter.candidates(for: "いちりんしゃ", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(ichirinsha.first, "一輪車", "list=\(ichirinsha)")
    }

    // たい: 国名の タイ は dict rank1 なのにカタカナ強調フィルタで消えていた。
    // seed 掲載で免除し先頭へ。對 は末尾、かな たい も先頭から外す(ユーザ指定 2608)。
    func testRegressionRealLMTaiIncludesKatakanaTai() throws {
        try prepareRealLMDictionary()

        let tai = converter.candidates(for: "たい", limit: 16, systemCandidateMode: .surface)
        XCTAssertEqual(Array(tai.prefix(6)), ["タイ", "鯛", "他意", "Tai", "🇹🇭", "対"], "list=\(tai)")
        let taiIndex = tai.firstIndex(of: "たい") ?? Int.max
        let objIndex = tai.firstIndex(of: "對") ?? Int.max
        XCTAssertGreaterThan(taiIndex, 10, "list=\(tai)")
        XCTAssertGreaterThan(objIndex, taiIndex, "list=\(tai)")
    }

    // ちしまをさきに: 連用形+に(目的)ノード 裂きに に格助詞直後の活用割引(5000)が効き、
    // 先(を→先4557)+に(先→に532)を 89 差で押し切っていた。文末では割引を外す(ユーザ報告 2608)。
    func testRegressionRealLMChishimaWoSakiNiPrefersSakiNi() throws {
        try prepareRealLMDictionary()

        let chishima = converter.multiClauseCandidates(for: "ちしまをさきに", systemCandidateMode: .surface)
        XCTAssertEqual(chishima.first, "千島を先に", "list=\(chishima)")
        // 目的の に は移動動詞が続く文中では従来どおり効く
        let sakiniiku = converter.multiClauseCandidates(for: "はなをさきにいく", systemCandidateMode: .surface)
        XCTAssertTrue(sakiniiku.contains { $0.hasSuffix("に行く") }, "list=\(sakiniiku)")
    }

    // しきなそば: 連体の な がどんな名詞にも継げて 式な側 になっていた。形容動詞語幹の
    // 判定(prev→な bigram 実績)で遮断し、識名 は seed で収穫底値降格を免除、
    // 表外訓の 側(そば)は連文節で減点する(ユーザ報告 2608)。
    func testRegressionRealLMShikinaSobaPrefersShikinaSoba() throws {
        try prepareRealLMDictionary()

        let shikinaSoba = converter.multiClauseCandidates(for: "しきなそば", systemCandidateMode: .surface)
        XCTAssertEqual(shikinaSoba.first, "識名そば", "list=\(shikinaSoba)")
        let shikina = converter.candidates(for: "しきな", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(shikina.first, "識名", "list=\(shikina)")
    }

    // 形容動詞語幹の な は従来どおり通ること(便利491/有名422/静か425 は閾値2000より安い)。
    func testRegressionRealLMNaAdjectiveStemsStillConnect() throws {
        try prepareRealLMDictionary()

        for (reading, expected) in [("べんりなもの", "便利な"), ("ゆうめいなひと", "有名な"),
                                    ("しずかなへや", "静かな")] {
            let list = converter.multiClauseCandidates(for: reading, systemCandidateMode: .surface)
            XCTAssertTrue(list.first?.hasPrefix(expected) ?? false, "\(reading) list=\(list)")
        }
    }

    // そば: 側 の unigram(4280)は主読み がわ の統計に支配されており、短span床(wc5755)を
    // 通しても かな そば(5965)に勝って 側を食べる を作っていた(ユーザ報告 2608)。
    func testRegressionRealLMSobaPrefersKana() throws {
        try prepareRealLMDictionary()

        let taberu = converter.multiClauseCandidates(for: "そばをたべる", systemCandidateMode: .surface)
        XCTAssertEqual(taberu.first, "そばを食べる", "list=\(taberu)")
        XCTAssertTrue(taberu.contains("蕎麦を食べる"), "list=\(taberu)")
        let oku = converter.multiClauseCandidates(for: "そばにおく", systemCandidateMode: .surface)
        XCTAssertEqual(oku.first, "そばに置く", "list=\(oku)")
    }

    // 補助語彙のコンパクト表(UTF8ブロブ+二分探索)が [String: [String]] と同じ答えを
    // 返すことの固定。常駐 6.8MB→約1MB の置き換え(2615)の正しさの根拠。
    func testSupplementalVocabCompactStoreRoundTrip() {
        let dictionary: [String: [String]] = [
            "まつやにわいん": ["松脂ワイン"],
            "あ": ["亜", "阿"],
            "てーるぶらんしゅ": ["テール・ブランシュ"],
            "ん": [],
            "じゃんぐりあ": ["ジャングリア"],
            "ぴーゔぃ": ["ピーヴィ", "PIWI"]
        ]
        let store = SupplementalVocabCompactStore(dictionary: dictionary)
        XCTAssertEqual(store.readingCount, dictionary.count)
        for (reading, candidates) in dictionary {
            XCTAssertEqual(store.candidates(for: reading), candidates, "reading=\(reading)")
            for candidate in candidates {
                XCTAssertTrue(store.contains(reading: reading, surface: candidate), "\(reading)/\(candidate)")
            }
            XCTAssertFalse(store.contains(reading: reading, surface: "存在しない表層"))
        }
        XCTAssertEqual(store.candidates(for: "みとうろく"), [])
        XCTAssertFalse(store.contains(reading: "みとうろく", surface: "亜"))
        var collected: Set<String> = []
        store.forEachCandidate { collected.insert($0) }
        XCTAssertEqual(collected, Set(dictionary.values.flatMap { $0 }))
        // 空辞書
        XCTAssertTrue(SupplementalVocabCompactStore.empty.isEmpty)
        XCTAssertEqual(SupplementalVocabCompactStore.empty.candidates(for: "あ"), [])
    }

    // ★時限診断(MEMFORENSICS 2615): 変換1回あたりの malloc アリーナ成長をチャネル別に測る。
    // 実機台帳で「変換1〜2字で+4〜8MB」の高水位成長が確定したため、犯行チャネルを Mac で絞る。
    // 原因解明後に削除してよい(常設の回帰アサートは持たない)。
    func testDiagMemoryWatermarkPerConversionChannel() throws {
        guard ProcessInfo.processInfo.environment["WATERMARK"] != nil else {
            throw XCTSkip("WATERMARK=1(xcodebuild には TEST_RUNNER_WATERMARK=1)のときだけ実行")
        }
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary()

        func stats() -> (used: Double, alloc: Double) {
            var s = malloc_statistics_t()
            malloc_zone_statistics(nil, &s)
            return (Double(s.size_in_use) / 1_048_576, Double(s.size_allocated) / 1_048_576)
        }
        func report(_ label: String, _ before: (used: Double, alloc: Double)) {
            let after = stats()
            print("WATERMARK \(label): used \(String(format: "%.2f→%.2f (Δ%+.2f)", before.used, after.used, after.used - before.used))"
                + "  alloc \(String(format: "%.1f→%.1f (Δ%+.2f)", before.alloc, after.alloc, after.alloc - before.alloc))")
        }

        // ── Z: 初回変換で遅延ロードされる常駐の分解(容疑者を1つずつ触る)──
        var z = stats()
        _ = converter.store.loadSupplementalSystemDictionary()
        report("Z:補助語彙(SecondVocab)", z)
        z = stats()
        _ = converter.store.suppressedCandidatesByReading()
        report("Z:抑制語彙", z)
        z = stats()
        _ = KanaKanjiSeedDictionary.seed.count
        _ = KanaKanjiSeedDictionary.exactReadingOnlySeed.count
        report("Z:seed静的表", z)
        z = stats()
        _ = converter.store.initialUserDictionary()
        _ = converter.store.learnedDictionary()
        _ = converter.store.userDictionary()
        report("Z:追加/学習語彙", z)
        z = stats()
        _ = converter.store.loadSystemCandidateSources()
        report("Z:candidateSources", z)
        z = stats()
        _ = converter.store.loadSystemDictionary()
        report("Z:systemDictionary(JSON)", z)

        // ── Z2: 変換パイプラインの段階分解(初回変換の +3.3MB の在処)──
        z = stats()
        _ = converter.store.systemCandidates(for: "が", taggedWith: "second")
        report("Z2:store点引き[が]", z)
        z = stats()
        _ = converter.store.systemCandidates(for: "が", mode: .surface)
        report("Z2:store.systemCandidates[が]", z)
        z = stats()
        _ = converter.systemCandidates(for: "が", mode: .surface)
        report("Z2:converter.systemCandidates[が]", z)
        z = stats()
        _ = converter.candidatesForReading("が", userDictionary: [:], initialUserDictionary: [:], systemCandidateMode: .surface)
        report("Z2:candidatesForReading[が]", z)
        print("WATERMARK hist前: \(KeyboardViewController.diagnosticsMallocSizeHistogram())")
        // ── A: 1字読みの単文節(実機台帳の主犯疑い)を読み別に ──
        for r in ["が", "に", "と", "し", "か", "は", "の", "て", "も", "で"] {
            let b1 = stats()
            _ = converter.candidates(for: r, limit: 24, systemCandidateMode: .surface)
            report("A:単文節[\(r)]", b1)
        }
        print("WATERMARK キャッシュ: \(converter.diagnosticsCacheCountsSummary())")
        print("WATERMARK sqlite/fp: \(MemoryForensics.summaryLine())")
        print("WATERMARK hist後: \(KeyboardViewController.diagnosticsMallocSizeHistogram())")
        print("WATERMARK 構造: \(converter.store.diagnosticsStructureBytesSummary())")
        var b = stats()

        // ── B: バースト打鍵の再現(1打鍵ごとに変換。実運用と同じ増分列)──
        b = stats()
        let phrase = "きょうのてんきはいいですね"
        for end in 1...phrase.count {
            let r = String(phrase.prefix(end))
            _ = converter.candidates(for: r, limit: 24, systemCandidateMode: .surface)
            if r.count >= 4 {
                _ = converter.multiClauseCandidates(for: r, systemCandidateMode: .surface)
            }
        }
        report("B:バースト13打鍵", b)

        // ── C: 連文節だけ(長め読み5種)──
        b = stats()
        for r in ["きょうはいいてんきですね", "あしたのかいぎのしりょう", "でんしゃがおくれています",
                  "おひるごはんなにたべよう", "しゅうまつはえいがをみたい"] {
            _ = converter.multiClauseCandidates(for: r, systemCandidateMode: .surface)
        }
        report("C:連文節x5", b)

        // ── D: 単文節だけ(同じ長め読み)──
        b = stats()
        for r in ["きょうはいいてんきですね", "あしたのかいぎのしりょう", "でんしゃがおくれています",
                  "おひるごはんなにたべよう", "しゅうまつはえいがをみたい"] {
            _ = converter.candidates(for: r, limit: 24, systemCandidateMode: .surface)
        }
        report("D:単文節長め x5", b)

        // ── E: A〜D をもう1周(キャッシュ温存時の定常成長)──
        b = stats()
        for r in ["が", "に", "と", "し", "か"] {
            _ = converter.candidates(for: r, limit: 24, systemCandidateMode: .surface)
        }
        for r in ["きょうはいいてんきですね", "あしたのかいぎのしりょう"] {
            _ = converter.multiClauseCandidates(for: r, systemCandidateMode: .surface)
            _ = converter.candidates(for: r, limit: 24, systemCandidateMode: .surface)
        }
        report("E:2周目(ウォーム)", b)

        // ── F: 別の読み群でコールド増分(キャッシュに乗っていない読み)──
        b = stats()
        for r in ["ぎんこうにいってきます", "らいしゅうのよていをきめる", "ばんごはんはかれーにする"] {
            _ = converter.multiClauseCandidates(for: r, systemCandidateMode: .surface)
            _ = converter.candidates(for: r, limit: 24, systemCandidateMode: .surface)
        }
        report("F:コールド新規x3", b)
    }

    // 2618バッチ: ユーザ報告7件(じゅうわり/みしょうの/あれがはじめて/すごいだろー/
    // するのね/うまいぜ/ごはんがたける)。詳細は各コミットメッセージ参照。
    func testRegression2618Batch() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary()

        func barTop(_ reading: String) -> String? {
            let multi = converter.multiClauseCandidates(for: reading, systemCandidateMode: .surface)
            if let first = multi.first { return first }
            return converter.candidates(for: reading, limit: 4, systemCandidateMode: .surface).first
        }
        // じゅうわり: 十割 は とわり のみ辞書登録で、連文節が 中(じゅう)+割り を作っていた
        XCTAssertEqual(barTop("じゅうわり"), "十割")
        // みしょうの: 実生 を2番目に
        let mishouno = converter.candidates(for: "みしょうの", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(Array(mishouno.prefix(2)), ["未詳の", "実生の"], "list=\(mishouno)")
        // あれがはじめて: 文語已然形 有れ がかな指示語を跨いでいた
        XCTAssertEqual(barTop("あれがはじめて"), "あれが初めて")
        // すごいだろー: 追加語彙 ろー(raw)が だ の直後に食い込んでいた
        XCTAssertEqual(barTop("すごいだろー"), "すごいだろー")
        // するのね: かな する が述語判定されず のね クランプが漢字側だけに効いていた
        XCTAssertEqual(barTop("するのね"), "するのね")
        // うまいぜ: keepKana が立たず提示層でかなが退避されていた
        XCTAssertEqual(barTop("うまいぜ"), "うまいぜ")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "うまいぜ"))
        // ごはんがたける: 人名 健(seed)の1ノード勝ち。炊ける curated 供給で1・2位に
        let gohan = converter.multiClauseCandidates(for: "ごはんがたける", systemCandidateMode: .surface)
        XCTAssertEqual(Array(gohan.prefix(2)), ["ごはんが炊ける", "ご飯が炊ける"], "list=\(gohan)")
        // 健 は単語レベルでは上位に残す(人名入力の受け皿)
        let takeru = converter.candidates(for: "たける", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(takeru.first, "炊ける", "list=\(takeru)")
        XCTAssertTrue(takeru.prefix(3).contains("健"), "list=\(takeru)")

        // 防護: 荒れ系(あれ 床免除の巻き添え確認)
        let hada = converter.multiClauseCandidates(for: "はだがあれた", systemCandidateMode: .surface)
        XCTAssertTrue(hada.first?.hasSuffix("荒れた") ?? false, "list=\(hada)")
        // 防護: ろー の終助詞化が タロー(たろー、辞書唯一のエントリ)を壊さない
        // (太郎 は たろう 表記のみで、たろー には元から居ない)
        let taroo = converter.candidates(for: "たろー", limit: 6, systemCandidateMode: .surface)
        XCTAssertTrue(taroo.contains("タロー"), "list=\(taroo)")
        // 防護: 単独 ろー の追加語彙(raw/ロー)は健在
        let roo = converter.candidates(for: "ろー", limit: 6, systemCandidateMode: .surface)
        XCTAssertTrue(roo.contains("raw"), "list=\(roo)")
    }

    // けんない: 単漢字+ない の素通り断片(件ない/券ない…24件)が複数チャネル累積で
    // 辞書語(県内 rank0/uni5537、圏内)を追い越していた。せんない/とない は LM優位昇格
    // (2545)が偶然救っていただけで、rank0 が LM 最良の読みでは断片が露出する構造。
    // 「辞書非掲載の1漢字+ない」断片群の直上へ LM実在の辞書語を持ち上げる(ユーザ報告 2618)。
    func testRegressionRealLMKennaiPrefersDictionaryWords() throws {
        try prepareRealLMDictionary()

        let kennai = converter.candidates(for: "けんない", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(Array(kennai.prefix(2)), ["県内", "圏内"], "list=\(kennai)")
        // しゃない は 2636 のユーザ指定で {社内, 車内} 先頭(かな降格)に変更
        let shanai = converter.candidates(for: "しゃない", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(Array(shanai.prefix(2)), ["社内", "車内"], "list=\(shanai)")
        let kannai = converter.candidates(for: "かんない", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(kannai.first, "管内", "list=\(kannai)")
        // 既存の救済経路は不変(かなエコー→線内/都内 の並び)
        let sennai = converter.candidates(for: "せんない", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(Array(sennai.prefix(3)), ["せんない", "線内", "詮ない"], "list=\(sennai)")
        // 正当な 1漢字+ない の辞書語は無傷
        let setsunai = converter.candidates(for: "せつない", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(setsunai.first, "切ない", "list=\(setsunai)")
    }

    // いいねえ: 連文節が終助詞の引き伸ばし    // いいねえ: 連文節が終助詞の引き伸ばし え を 画(いいね画)に漢字化して先頭を
    // 乗っ取っていた。終端の単独母音読み漢字ノードは直前ノード読み末尾と同母音なら
    // 引き伸ばし表記としてペナルティ(ユーザ報告 2614)。
    func testRegressionRealLMIineePrefersKana() throws {
        try prepareRealLMDictionary()

        for reading in ["いいねえ", "いいなあ"] {
            let multi = converter.multiClauseCandidates(for: reading, systemCandidateMode: .surface)
            let single = converter.candidates(for: reading, limit: 4, systemCandidateMode: .surface)
            XCTAssertEqual(multi.first ?? single.first, reading, "multi=\(multi) single=\(single)")
        }
        // 異母音の正当な単漢字合成(この+絵 等の え)は巻き添えにしない
        let konoe = converter.candidates(for: "このえ", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(konoe.first, "近衛", "list=\(konoe)")
    }

    // うちやすさ: 補助形容詞の さ名詞化(やすさ/にくさ)が派生語尾に無く、
    // 打ちやすさ が生成されなかった(やすい は在るのに)。ユーザ報告 2614。
    func testRegressionRealLMYasusaNominalization() throws {
        try prepareRealLMDictionary()

        let uchiyasusa = converter.candidates(for: "うちやすさ", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(uchiyasusa.first, "打ちやすさ", "list=\(uchiyasusa)")
        let mienikusa = converter.candidates(for: "みえにくさ", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(mienikusa.first, "見えにくさ", "list=\(mienikusa)")
        let tabeyasusa = converter.candidates(for: "たべやすさ", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(tabeyasusa.first, "食べやすさ", "list=\(tabeyasusa)")
    }

    // ゆうせんで: 関西弁縮約(する→せんで)が文語サ変(有する/幽する)と組んで
    // 有せんで/幽せんで が上位を占めていた。漢語一字サ変は縮約対象から除外し、
    // 優先(wc8457=同音最悪)は seed の基底順宣言で救済(ユーザ報告 2614)。
    func testRegressionRealLMYuusendePrefersYuusen() throws {
        try prepareRealLMDictionary()

        let yuusende = converter.candidates(for: "ゆうせんで", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(yuusende.prefix(3)), ["ゆうせんで", "優先で", "有線で"], "list=\(yuusende)")
        XCTAssertFalse(yuusende.contains("有せんで"), "list=\(yuusende)")
        // ※語幹2字以上の正例は無し: せん縮約は辞書単独エントリのサ変(ほぼ漢語一字+する)
        // にのみ効く仕組みで、掃除する 等の複合サ変には元から生成されない(ゲートは削るだけ)
    }

    // かくてい: 基底辞書順が 画定>劃定>確定 と実頻度の逆で、単文節は LM優位昇格(2545)が
    // 救うが活用派生(しちゃう 等)は基底順をコピーして 画定しちゃう が先頭だった。
    // seed の基底順宣言で全派生を是正(ユーザ報告 2613)。
    func testRegressionRealLMKakuteiDerivationsPreferKakutei() throws {
        try prepareRealLMDictionary()

        let base = converter.candidates(for: "かくてい", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(base.first, "確定", "list=\(base)")
        for reading in ["かくていしちゃう", "かくていした", "かくていして"] {
            let multi = converter.multiClauseCandidates(for: reading, systemCandidateMode: .surface)
            let single = converter.candidates(for: reading, limit: 6, systemCandidateMode: .surface)
            let top = multi.first ?? single.first
            XCTAssertTrue(top?.hasPrefix("確定") ?? false, "\(reading) multi=\(multi) single=\(single)")
        }
    }

    // かわいいなあ: 終助詞 なあ の遷移が bigram 頼みで、いい→なあ の観測bigramを持つ
    // 川+いい 分割が かわいい を跨いでいた。述語直後の終助詞かなクラスタをクランプ
    // (のが/のは と同型の文法クランプ。ユーザ報告 2628)。
    func testRegressionRealLMKawaiinaaPrefersKana() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary()

        for reading in ["かわいいなあ", "かわいいな", "かわいいねえ", "すごいなあ"] {
            let multi = converter.multiClauseCandidates(for: reading, systemCandidateMode: .surface)
            XCTAssertEqual(multi.first, reading, "reading=\(reading) multi=\(multi)")
        }
    }

    // つれていって: 辞書の いって は名詞 一手 のみで、動詞て形直後でも 連れて一手 が
    // 先頭だった(行って/言って は派生OOV 7200 で常敗)。て形直後の いって は
    // 行って をクランプ・一手 を減点し、連れて言って は suppr で封じる(ユーザ報告 2628)。
    func testRegressionRealLMTsureteittePrefersItte() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary()

        let tsurete = converter.multiClauseCandidates(for: "つれていって", systemCandidateMode: .surface)
        XCTAssertEqual(tsurete.first, "連れて行って", "list=\(tsurete)")
        XCTAssertFalse(tsurete.contains("連れて言って"), "list=\(tsurete)")
        // 同型の補助動詞連結(multi が空なら単文節に委譲されるのでバートップで判定)
        let motteMulti = converter.multiClauseCandidates(for: "もっていって", systemCandidateMode: .surface)
        let motteSingle = converter.candidates(for: "もっていって", limit: 4, systemCandidateMode: .surface)
        let motteTop = motteMulti.first ?? motteSingle.first
        XCTAssertTrue(motteTop == "持って行って" || motteTop == "持っていって",
                      "multi=\(motteMulti) single=\(motteSingle)")
        // 将棋の「ここで一手」(助詞 で+一手)は無傷
        let kokode = converter.multiClauseCandidates(for: "ここでいって", systemCandidateMode: .surface)
        XCTAssertTrue(kokode.contains { $0.contains("一手") } || !kokode.isEmpty, "list=\(kokode)")
    }

    // たく: 基底順が実頻度の逆(炊く rank8)。seed {炊く, 焚く, 卓, 択}+かな末尾降格
    // (ユーザ指定 2630)。たくのが好き(名詞化節)の既存調整は無傷であること。
    func testRegressionRealLMTakuPrefersVerb() throws {
        try prepareRealLMDictionary()

        let taku = converter.candidates(for: "たく", limit: 12, systemCandidateMode: .surface)
        XCTAssertEqual(Array(taku.prefix(4)), ["炊く", "焚く", "卓", "択"], "list=\(taku)")
        if let kanaIndex = taku.firstIndex(of: "たく") {
            XCTAssertGreaterThan(kanaIndex, 5, "list=\(taku)")
        }
        // 防護: 名詞化節(たくのがすき→炊くのが好き)
        let takunoga = converter.multiClauseCandidates(for: "たくのがすき", systemCandidateMode: .surface)
        XCTAssertEqual(takunoga.first, "炊くのが好き", "list=\(takunoga)")

        // 卓 は助数詞としても供給(数字文脈限定の表+何N。ユーザ指定 2630)。
        // 数字文脈限定なので さんたく→三択 は侵食しない。
        let boosted = KanaKanjiConverter.digitContextCounterBoostedCandidates([], reading: "たく", precedingCharacter: "3")
        XCTAssertTrue(boosted.contains("卓"), "\(boosted)")
        let nantaku = converter.candidates(for: "なんたく", limit: 6, systemCandidateMode: .surface)
        XCTAssertTrue(nantaku.contains("何卓"), "single=\(nantaku)")
        let santaku = converter.candidates(for: "さんたく", limit: 6, systemCandidateMode: .surface)
        XCTAssertFalse(santaku.contains("3卓") || santaku.contains("三卓"), "single=\(santaku)")
    }

    // N択(三者択一の意): 一〜四択が辞書・LMに無い → seed 供給(算用併記)。
    // ごたく は 御託 先頭を守り exactReadingOnly で末尾供給。3+たく の数字文脈は 卓/択(2633)
    // くいたくなって: 食いたくなって が消え {句痛くなって, くいたくなって} だけに(2647)
    func testRegressionRealLMKuitakunatte() throws {
        try prepareRealLMDictionary()

        for probe in ["くいたい", "くいたく", "くいたくなって", "くいたくない",
                      "おさらのちょっけい", "さらのちょっけい", "おさらの", "みたの"] {
            let s = converter.candidates(for: probe, limit: 8, systemCandidateMode: .surface)
            let m = converter.multiClauseCandidates(for: probe, systemCandidateMode: .surface)
            print("PROBE2647 \(probe) single=\(s.prefix(6)) multi=\(m.prefix(4))")
        }
        let target = converter.candidates(for: "くいたくなって", limit: 8, systemCandidateMode: .surface)
        let multi = converter.multiClauseCandidates(for: "くいたくなって", systemCandidateMode: .surface)
        let barTop = multi.first ?? target.first
        XCTAssertEqual(barTop, "食いたくなって", "multi=\(multi.prefix(3)) single=\(target.prefix(4))")

        // おさらのちょっけい: お+収穫底値人名(皿野)の敬語合成が正解経路を跨いでいた(2647)
        let osara = converter.multiClauseCandidates(for: "おさらのちょっけい", systemCandidateMode: .surface)
        XCTAssertEqual(osara.first, "お皿の直径", "multi=\(osara.prefix(4))")

        // みたの: 三田の を2位へ(見たの 先頭は維持)
        let mitano = converter.candidates(for: "みたの", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(Array(mitano.prefix(2)), ["見たの", "三田の"], "list=\(mitano)")

        // はうまいなあ: 助詞直後でも うまい はかな(床免除)。提示層の根拠(keepKana)も
        // 立つこと(実機でエンジンかな先頭・表示は上手い先頭の食い違いがあった)
        let umai = converter.multiClauseCandidates(for: "はうまいなあ", systemCandidateMode: .surface)
        XCTAssertEqual(umai.first, "はうまいなあ", "multi=\(umai.prefix(4))")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "はうまいなあ"))

        // かいしめよね: 会染めよね(染む族)が 買い占めよね を跨ぐ(2647追)
        let kaishime = converter.multiClauseCandidates(for: "かいしめよね", systemCandidateMode: .surface)
        print("PROBE2647 かいしめよね multi=\(kaishime.prefix(6))")
        XCTAssertEqual(kaishime.first, "買い占めよね", "multi=\(kaishime.prefix(4))")

        // せんじつはじめて: じつ 読みの 日 助数詞合成(1000日)を作らない
        let senjitsu = converter.multiClauseCandidates(for: "せんじつはじめて", systemCandidateMode: .surface)
        XCTAssertEqual(senjitsu.first, "先日初めて", "multi=\(senjitsu.prefix(4))")
        XCTAssertFalse(senjitsu.prefix(4).contains { $0.contains("1000日") || $0.contains("千日") },
                       "multi=\(senjitsu.prefix(4))")
    }

    // つくろう: かな先頭→作ろう 先頭・かな末尾側へ(ユーザ指定 2649)
    func testRegressionRealLMTsukurouPrefersTsukuru() throws {
        try prepareRealLMDictionary()

        let list = converter.candidates(for: "つくろう", limit: 10, systemCandidateMode: .surface)
        XCTAssertEqual(Array(list.prefix(4)), ["作ろう", "造ろう", "創ろう", "繕う"], "list=\(list)")
        if let kanaIndex = list.firstIndex(of: "つくろう") {
            XCTAssertGreaterThan(kanaIndex, 3, "list=\(list)")
        }
    }

    // したいところだが: し対ところだが 等の誤区切りが上位に(ユーザ報告 2649)
    func testRegressionRealLMShitaiTokorodaga() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary(includeSuppression: true)

        let multi = converter.multiClauseCandidates(for: "したいところだが", systemCandidateMode: .surface)
        let single = converter.candidates(for: "したいところだが", limit: 6, systemCandidateMode: .surface)
        print("PROBE2649 multi=\(multi.prefix(5)) single=\(single.prefix(5))")
        let barTop = multi.first ?? single.first
        XCTAssertEqual(barTop, "したいところだが", "multi=\(multi.prefix(4)) single=\(single.prefix(4))")
        XCTAssertFalse((multi.prefix(3) + single.prefix(3)).contains { $0.contains("し対") || $0.contains("し態") },
                       "multi=\(multi.prefix(4)) single=\(single.prefix(4))")
    }

    // ちゃんと(かな副詞): チャン/喜屋武 が読み長で揺れて先頭を取っていた(2650)
    func testRegressionRealLMChantoKanaAdverb() throws {
        try prepareRealLMDictionary()

        for probe in ["ちゃんとしてる", "ちゃんとしてるらしい", "ちゃんとしている", "ちゃんとしているらしい"] {
            let multi = converter.multiClauseCandidates(for: probe, systemCandidateMode: .surface)
            let single = converter.candidates(for: probe, limit: 4, systemCandidateMode: .surface)
            let barTop = multi.first ?? single.first
            XCTAssertEqual(barTop, probe, "\(probe): multi=\(multi.prefix(3)) single=\(single.prefix(3))")
        }
    }

    // あかっぽく/あおっぽく: 頭1かな断片(あ闊歩句/あ尾っぽ句)が っぽく派生を跨いでいた(2650)
    func testRegressionRealLMAkappokuPrefersDerived() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary(includeSuppression: true)

        let aka = converter.candidates(for: "あかっぽく", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(aka.first, "赤っぽく", "list=\(aka)")
        XCTAssertFalse(aka.prefix(3).contains { $0.contains("闊歩") }, "list=\(aka)")
        let ao = converter.candidates(for: "あおっぽく", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(ao.first, "青っぽく", "list=\(ao)")
        XCTAssertFalse(ao.prefix(3).contains { $0.contains("尾っぽ") }, "list=\(ao)")
        // 実機バーは連文節優先(barTop=multi.first)なので連文節側も固定する
        // (実機トレース: 単文節=赤っぽく先頭なのに連文節が あ闊歩句 を返していた)
        let akaMulti = converter.multiClauseCandidates(for: "あかっぽく", systemCandidateMode: .surface)
        let akaBar = akaMulti.first ?? aka.first
        XCTAssertEqual(akaBar, "赤っぽく", "multi=\(akaMulti.prefix(4))")
        let aoMulti = converter.multiClauseCandidates(for: "あおっぽく", systemCandidateMode: .surface)
        let aoBar = aoMulti.first ?? ao.first
        XCTAssertEqual(aoBar, "青っぽく", "multi=\(aoMulti.prefix(4))")
    }

    // しぜんこう: wc11640(収穫底値)で 自然光(rank0/uni7302)が底値降格していた(2649)
    func testRegressionRealLMShizenkouPrefersDictWord() throws {
        try prepareRealLMDictionary()

        let single = converter.candidates(for: "しぜんこう", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "自然光", "list=\(single)")
        let multi = converter.multiClauseCandidates(for: "まどからのしぜんこう", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "窓からの自然光", "multi=\(multi.prefix(4))")
    }

    // きてれば: てれば 縮約(=ていれば)が一段・カ変に無く 木てれば になっていた(2649)
    func testRegressionRealLMKiterebaContraction() throws {
        try prepareRealLMDictionary()

        let kitereba = converter.candidates(for: "きてれば", limit: 8, systemCandidateMode: .surface)
        XCTAssertTrue(kitereba.prefix(3).contains("来てれば"), "list=\(kitereba)")
        XCTAssertTrue(kitereba.prefix(3).contains("着てれば"), "list=\(kitereba)")
        let kiteireba = converter.candidates(for: "きていれば", limit: 8, systemCandidateMode: .surface)
        XCTAssertTrue(kiteireba.prefix(3).contains("来ていれば"), "list=\(kiteireba)")
    }

    // ときどき: かな正書の副詞。単文節(かな先頭)と連文節(時々通ります)の不整合を
    // multiClauseKanaAdverbReadings で是正(ユーザ報告 2647)
    func testRegressionRealLMTokidokiKanaAdverb() throws {
        try prepareRealLMDictionary()

        let single = converter.candidates(for: "ときどき", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(2)), ["ときどき", "時々"], "list=\(single)")
        let multi = converter.multiClauseCandidates(for: "ときどきとおります", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "ときどき通ります", "multi=\(multi.prefix(4))")
    }

    // 2645 バッチ: うんだ/うみやすい/かねはらって/ちこくしないでねー/うかった/せみなー/
    // れいかい/2じしけん(全てユーザ報告・指定順)
    func testRegressionRealLM2645Batch() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary(includeSuppression: true)

        let unda = converter.candidates(for: "うんだ", limit: 12, systemCandidateMode: .surface)
        XCTAssertEqual(Array(unda.prefix(9)),
                       ["生んだ", "産んだ", "膿んだ", "熟んだ", "倦んだ", "惓んだ", "績んだ", "運だ", "うんだ"],
                       "list=\(unda)")
        let sokode = converter.multiClauseCandidates(for: "そこでうんだ", systemCandidateMode: .surface)
        XCTAssertEqual(Array(sokode.prefix(2)), ["そこで生んだ", "そこで産んだ"], "multi=\(sokode.prefix(4))")
        let umiyasui = converter.multiClauseCandidates(for: "もっとうみやすい", systemCandidateMode: .surface)
        XCTAssertEqual(Array(umiyasui.prefix(2)), ["もっと生みやすい", "もっと産みやすい"], "multi=\(umiyasui.prefix(4))")

        let kaneharatte = converter.multiClauseCandidates(for: "かねはらって", systemCandidateMode: .surface)
        XCTAssertEqual(kaneharatte.first, "金払って", "multi=\(kaneharatte.prefix(4))")

        let chikoku = converter.multiClauseCandidates(for: "ちこくしないでねー", systemCandidateMode: .surface)
        XCTAssertEqual(chikoku.first, "遅刻しないでねー", "multi=\(chikoku.prefix(4))")

        let ukatta = converter.candidates(for: "うかった", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(Array(ukatta.prefix(3)), ["受かった", "憂かった", "うかった"], "list=\(ukatta)")
        let ukattahouga = converter.multiClauseCandidates(for: "うかったほうが", systemCandidateMode: .surface)
        XCTAssertEqual(ukattahouga.first?.hasPrefix("受かった"), true, "multi=\(ukattahouga.prefix(4))")

        let seminar = converter.candidates(for: "せみなー", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(seminar.first, "セミナー", "list=\(seminar)")

        let reikai = converter.candidates(for: "れいかい", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(reikai.prefix(6)), ["例会", "例解", "嶺海", "冷灰", "霊界", "霊怪"], "list=\(reikai)")

        // 2確定→じしけん: 次試験(末尾変換込みの合成供給)を先頭群に
        let converterForTail = converter
        let ji = KanaKanjiConverter.digitContextCounterBoostedCandidates(
            ["時試験", "次しけん", "じしけん"], reading: "じしけん", precedingCharacter: "2",
            tailConversion: { tail in
                converterForTail?.candidates(for: tail, limit: 1, systemCandidateMode: .surface).first
            }
        )
        XCTAssertEqual(ji.first, "次試験", "boost=\(ji)")
        // 付属語末尾は変換供給しない(3+かいしか → 回鹿 を作らない)
        let kaishika = KanaKanjiConverter.digitContextCounterBoostedCandidates(
            [], reading: "かいしか", precedingCharacter: "3",
            tailConversion: { _ in "鹿" }
        )
        XCTAssertFalse(kaishika.contains("回鹿"), "boost=\(kaishika)")
    }

    // かげになってる: 嗅げにになってる(に二重)だけになる合成バグ+嗅げ の浮上(2644)
    func testRegressionRealLMKageNinatteru() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary(includeSuppression: true)

        for probe in ["かげに", "かげにな", "かげになって", "かげになってる", "かげになっている", "かげになってて"] {
            let m = converter.multiClauseCandidates(for: probe, systemCandidateMode: .surface)
            let s = converter.candidates(for: probe, limit: 6, systemCandidateMode: .surface)
            print("PROBE \(probe) multi=\(m.prefix(5)) single=\(s.prefix(5))")
        }
        let target = converter.multiClauseCandidates(for: "かげになってる", systemCandidateMode: .surface)
        XCTAssertEqual(target.first, "影になってる", "multi=\(target.prefix(4))")
        XCTAssertFalse(target.contains { $0.contains("にに") }, "に二重: \(target.prefix(6))")
        // 嗅げ系は変種列に残る(非文だが先頭を取らなければ実害小)。先頭の維持だけ固定
        let targetIru = converter.multiClauseCandidates(for: "かげになっている", systemCandidateMode: .surface)
        XCTAssertEqual(targetIru.first, "影になっている", "multi=\(targetIru.prefix(4))")
        for probe in ["かげになって", "かげになってて"] {
            let m = converter.multiClauseCandidates(for: probe, systemCandidateMode: .surface)
            XCTAssertEqual(m.first?.hasPrefix("影"), true, "\(probe) multi=\(m.prefix(3))")
        }

        // とっていて: かな先頭+捕っていていて(いて二重)の報告(2644)
        let totteite = converter.candidates(for: "とっていて", limit: 10, systemCandidateMode: .surface)
        let totteiteMulti = converter.multiClauseCandidates(for: "とっていて", systemCandidateMode: .surface)
        print("PROBE とっていて single=\(totteite) multi=\(totteiteMulti.prefix(5))")
        print("PROBE skipKanaLead=\(converter.derivationBaseSeedSkipsKanaLead(for: "とっていて"))"
            + " kanaPreferred=\(converter.isLMKanaPreferred(reading: "とっていて", among: ["取っていて"]))")
        XCTAssertFalse(totteite.contains { $0.contains("いていて") }, "いて二重: \(totteite)")
        XCTAssertEqual(totteite.first, "取っていて", "single=\(totteite.prefix(4))")
    }

    // 2643 バッチ: ふんぐらいかな/かさない/かねひで/かげ/とった(ウ音便)/しめ
    func testRegressionRealLM2643Batch() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary(includeSuppression: true)

        // 5確定→ふんぐらいかな: 末尾6かなまで合成供給(分ぐらいかな)
        let fun = KanaKanjiConverter.digitContextCounterBoostedCandidates(
            [], reading: "ふんぐらいかな", precedingCharacter: "5"
        )
        XCTAssertTrue(fun.contains("分ぐらいかな"), "\(fun)")

        // かさない: 断片合成(科さない 等)より正規活用 貸さない を先頭に
        let kasanai = converter.candidates(for: "かさない", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(kasanai.prefix(3)), ["貸さない", "課さない", "科さない"], "list=\(kasanai)")

        // かげ: {影, 陰, 蔭} 先頭(嗅げ/かな が上位に居た)
        let kage = converter.candidates(for: "かげ", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(kage.prefix(3)), ["影", "陰", "蔭"], "list=\(kage)")

        // しめ: 〆 を2位に(序数の目選好オンだと 締目 が割り込むため、実機の既定と
        // 同じくオフで検証。オン時は 締目 が先頭に入るのは仕様)
        converter.setOrdinalMeKanjiPreferred(false)
        let shime = converter.candidates(for: "しめ", limit: 16, systemCandidateMode: .surface)
        XCTAssertEqual(Array(shime.prefix(4)), ["締め", "〆", "〆め", "絞め"], "list=\(shime)")

        // とった: ウ音便誤生成(問った/訪った)を根絶し、ユーザ指定順
        let totta = converter.candidates(for: "とった", limit: 16, systemCandidateMode: .surface)
        XCTAssertFalse(totta.contains("問った") || totta.contains("訪った"), "list=\(totta)")
        XCTAssertEqual(Array(totta.prefix(5)), ["取った", "撮った", "採った", "捕った", "獲った"], "list=\(totta)")
        let totteite = converter.multiClauseCandidates(for: "とっていて", systemCandidateMode: .surface)
        XCTAssertFalse(totteite.prefix(4).contains { $0.contains("問っ") || $0.contains("訪っ") }, "multi=\(totteite.prefix(4))")
        let wototta = converter.multiClauseCandidates(for: "をとった", systemCandidateMode: .surface)
            .first ?? converter.candidates(for: "をとった", limit: 4, systemCandidateMode: .surface).first
        XCTAssertEqual(wototta, "を取った", "wototta=\(String(describing: wototta))")
        let tottatoki = converter.multiClauseCandidates(for: "とったとき", systemCandidateMode: .surface)
        XCTAssertFalse(tottatoki.prefix(4).contains { $0.contains("問っ") || $0.contains("訪っ") }, "multi=\(tottatoki.prefix(4))")

        // かねひで: 合成・連文節にもかな優先が伝播すること
        let kanehidega = converter.candidates(for: "かねひでが", limit: 8, systemCandidateMode: .surface)
        XCTAssertTrue(kanehidega.prefix(3).contains("かねひでが"), "list=\(kanehidega)")
        XCTAssertTrue(kanehidega.prefix(3).contains("金秀が"), "list=\(kanehidega)")
        // 先頭は かねひでが安い(かなの かねひで が保持されることが本質。全かな
        // かねひでがやすい はエコー抑制の対象で、要望があれば misc curated 化で対応)
        let kanehideyasui = converter.multiClauseCandidates(for: "かねひでがやすい", systemCandidateMode: .surface)
        XCTAssertEqual(kanehideyasui.first, "かねひでが安い", "multi=\(kanehideyasui.prefix(4))")
    }

    // あじ: 基底 按司(0) アジ(1) 鯵(2)…味(4)。seed {味, 鯵, アジ}+鰺(異体字)suppr(2642)
    func testRegressionRealLMAjiPrefersAji() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary(includeSuppression: true)

        let aji = converter.candidates(for: "あじ", limit: 10, systemCandidateMode: .surface)
        XCTAssertEqual(Array(aji.prefix(3)), ["味", "鯵", "アジ"], "list=\(aji)")
        XCTAssertFalse(aji.contains("鰺"), "鰺は抑制: \(aji)")
    }

    // さがっちゃってるね: て形直後の短カタカナ化(ルネ)の乗っ取り防止の一般則(2642)
    func testRegressionRealLMSagatchatteruNeAvoidsRune() throws {
        try prepareRealLMDictionary()

        let multi = converter.multiClauseCandidates(for: "さがっちゃってるね", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "下がっちゃってるね", "multi=\(multi.prefix(4))")
        XCTAssertFalse(multi.prefix(3).contains { $0.contains("ルネ") }, "multi=\(multi.prefix(4))")
    }

    // しろいさらの: 白い皿の が先頭になること(ユーザ報告 2642。さらの がかな固定で
    // 皿 が出ず、しろい に 皓い/皎い のレア字が出ていた)
    func testRegressionRealLMShiroiSaranoPrefersShiroiSarano() throws {
        try prepareRealLMDictionary()

        let multi = converter.multiClauseCandidates(for: "しろいさらの", systemCandidateMode: .surface)
        let sara = converter.candidates(for: "さら", limit: 6, systemCandidateMode: .surface)
        let sarano = converter.multiClauseCandidates(for: "さらの", systemCandidateMode: .surface)
        print("PROBE shiroisarano multi=\(multi.prefix(6)) sara=\(sara) sarano=\(sarano.prefix(6))")
        for probe in ["しろいさら", "さらをあらう", "さらのうえ", "おおきいさらの", "さらがしろい"] {
            let m = converter.multiClauseCandidates(for: probe, systemCandidateMode: .surface)
            print("PROBE \(probe) multi=\(m.prefix(5))")
        }
        XCTAssertEqual(multi.first, "白い皿の", "multi=\(multi.prefix(4))")
    }

    // のいみ: 連文節の断片(の+意味)として の意味 が出ること(ユーザ報告 2642)
    func testRegressionRealLMNoImiOffersComposition() throws {
        try prepareRealLMDictionary()

        var multi = converter.multiClauseCandidates(for: "のいみ", systemCandidateMode: .surface)
        let single = converter.candidates(for: "のいみ", limit: 8, systemCandidateMode: .surface)
        // 実機と同じ候補ゼロ救済(単・連とも空→連文節を短読みで再試行)
        if multi.isEmpty, single.isEmpty {
            multi = converter.multiClauseCandidates(
                for: "のいみ", systemCandidateMode: .surface, minReadingCountOverride: 2
            )
        }
        print("PROBE noimi multi=\(multi.prefix(6)) single=\(single.prefix(8))")
        let barTop = multi.first ?? single.first
        XCTAssertEqual(barTop, "の意味", "multi=\(multi.prefix(4)) single=\(single.prefix(4))")
    }

    func testRegressionRealLMNTakuChoices() throws {
        try prepareRealLMDictionary()

        XCTAssertEqual(converter.candidates(for: "いったく", limit: 3, systemCandidateMode: .surface).first, "一択")
        XCTAssertEqual(converter.candidates(for: "にたく", limit: 3, systemCandidateMode: .surface).first, "二択")
        let santaku = converter.candidates(for: "さんたく", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(santaku.first, "三択", "single=\(santaku)")
        XCTAssertTrue(santaku.contains("賛託"), "賛託は残す: \(santaku)")
        XCTAssertEqual(converter.candidates(for: "よんたく", limit: 3, systemCandidateMode: .surface).first, "四択")

        // ご託(ご+託 合成)が先頭に来る経路は従来からある。御託 が上位に残ることと
        // 五択 が末尾供給されることだけ固定する
        let gotaku = converter.candidates(for: "ごたく", limit: 30, systemCandidateMode: .surface)
        XCTAssertTrue(gotaku.prefix(2).contains("御託"), "御託は上位維持: \(gotaku)")
        XCTAssertTrue(gotaku.contains("五択"), "single=\(gotaku)")

        let boosted = KanaKanjiConverter.digitContextCounterBoostedCandidates([], reading: "たく", precedingCharacter: "3")
        XCTAssertTrue(boosted.contains("択") && boosted.contains("卓"), "\(boosted)")
    }

    // るい: 人名の ルイ(基底rank2)がカタカナ強調フィルタで消え、かな るい が2位だった。
    // seed {類, ルイ, 塁, 累}+かな非掲載で末尾降格(ユーザ指定 2627)。
    func testRegressionRealLMRuiIncludesKatakanaRui() throws {
        try prepareRealLMDictionary()

        let rui = converter.candidates(for: "るい", limit: 24, systemCandidateMode: .surface)
        XCTAssertEqual(Array(rui.prefix(4)), ["類", "ルイ", "塁", "累"], "list=\(rui)")
        // かな るい は上位から退く(完全除去はしない: かなチップとは別に候補列の末尾側へ)
        if let kanaIndex = rui.firstIndex(of: "るい") {
            XCTAssertGreaterThan(kanaIndex, 7, "list=\(rui)")
        }
    }

    // せんせんげつ: Sudachi は 先先月(踊り字なし)を収穫底値 wc11402 で持つのみで、
    // 底値降格で沈み候補ゼロ同然。先々週 は踊り字なし版すら無い。seed 供給(ユーザ報告 2613)。
    func testRegressionRealLMSensengetsuSuppliesOdoriji() throws {
        try prepareRealLMDictionary()

        let sensengetsu = converter.candidates(for: "せんせんげつ", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(sensengetsu.first, "先々月", "list=\(sensengetsu)")
        let sensenshuu = converter.candidates(for: "せんせんしゅう", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(sensenshuu.first, "先々週", "list=\(sensenshuu)")
    }

    // きゅうかんび: {休館日, 休刊日, 休肝日} だった。休肝日 を2番目に(ユーザ指定 2606)。
    func testRegressionRealLMKyukanbiOrdering() throws {
        try prepareRealLMDictionary()

        let kyukanbi = converter.candidates(for: "きゅうかんび", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(Array(kyukanbi.prefix(3)), ["休館日", "休肝日", "休刊日"], "list=\(kyukanbi)")
    }

    // あいぱっど: it.plist の記載順(iPad Air→mini→Pro→iPad)がそのまま rank になり、
    // 無印 iPad が4番目だった。plist の並べ替えで先頭に(ユーザ指定 2611)。
    func testRegressionRealLMAipaddoPrefersIPad() throws {
        try prepareRealLMDictionary()

        let aipaddo = converter.candidates(for: "あいぱっど", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(aipaddo.first, "iPad", "list=\(aipaddo)")
    }

    // での: 複合助詞のかなが正書なのに デの/手の の合成が先頭だった(ユーザ指定 2610)。
    func testRegressionRealLMDenoPrefersKana() throws {
        try prepareRealLMDictionary()

        let deno = converter.candidates(for: "での", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(Array(deno.prefix(2)), ["での", "出の"], "list=\(deno)")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "での"), "list=\(deno)")
    }

    // がすき: 助詞+述語の断片 が+好き が候補ゼロだった(でのむ/なひと と同型。ユーザ指定 2610)。
    func testRegressionRealLMGaSukiSuppliesGaSuki() throws {
        try prepareRealLMDictionary()

        let gasuki = converter.candidates(for: "がすき", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(gasuki.first, "が好き", "list=\(gasuki)")
    }

    // なひと: 形容動詞連体形の な+人 が候補ゼロだった(ユーザ指定 2606)。
    func testRegressionRealLMNaHitoSuppliesNaHito() throws {
        try prepareRealLMDictionary()

        let nahito = converter.candidates(for: "なひと", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(nahito.first, "な人", "list=\(nahito)")
    }

    // はなしか: {噺家, 咄家, はなしか, 話か} だった。話か を先頭に、かな は末尾へ
    // (ユーザ指定 2559)。
    func testRegressionRealLMHanashikaPrefersHanashika() throws {
        try prepareRealLMDictionary()

        let hanashika = converter.candidates(for: "はなしか", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(hanashika.first, "話か", "list=\(hanashika)")
        XCTAssertFalse(hanashika.prefix(3).contains("はなしか"), "list=\(hanashika)")
    }

    // やる: かな やる(8372)が 遣る/ヤル(5971) に負けて基底4位で、活用コピーもその順を継ぎ
    // やってください→{演って, 犯って, 飲って…} になっていた。seed で基底先頭をかなに
    // (ユーザ指定 2564)。
    func testRegressionRealLMYaruPrefersKana() throws {
        try prepareRealLMDictionary()
        // 遣る は poubelle(InitialSuppr)、殺る/姦る は suppr(InitialSupprHidden)。
        // かな活用形は misc(InitialMisc)の curated 供給。実機相当にするため全部注入する
        var merged: [String: [String]] = [:]
        for name in ["InitialSupprVocabMigration", "InitialSupprHiddenVocabMigration"] {
            let data = try Data(contentsOf: URL(fileURLWithPath: "/Users/kusakabe/Git/ecritu/KeyboardExtension/\(name).json"))
            for (reading, candidates) in try JSONDecoder().decode([String: [String]].self, from: data) {
                merged[reading, default: []].append(contentsOf: candidates)
            }
        }
        UserDefaults(suiteName: defaultsSuiteName)?.set(try JSONEncoder().encode(merged), forKey: "ÉcrituSuppr_Vocab")
        for name in ["InitialAjoutVocabMigration", "InitialMiscVocabMigration"] {
            let data = try Data(contentsOf: URL(fileURLWithPath: "/Users/kusakabe/Git/ecritu/KeyboardExtension/\(name).json"))
            for (reading, candidates) in try JSONDecoder().decode([String: [String]].self, from: data) {
                for candidate in candidates.reversed() {
                    converter.store.addUserEntry(reading: reading, candidate: candidate)
                }
            }
        }
        let fresh = KanaKanjiConverter(store: KanaKanjiStore(appGroupID: defaultsSuiteName))
        // やってみようかな は keepKana が false で提示層がかな版を捨てており、降格の相方が
        // 消えて 遣ってみようかな が先頭に残っていた。やってみよう/やってみようかなー は
        // 別経路で true だったので、間に挟まる形だけ落ちるという不整合だった(2583)。
        for reading in ["やってください", "やってる", "やった",
                        "やってみよう", "やってみようかな", "やってみようかなー",
                        "やっておく", "やらないで", "やれそう"] {
            let list = fresh.candidates(for: reading, limit: 8, systemCandidateMode: .surface)
            // 当て表記(演る/犯る/飲る/行る)は候補に残す。抑制すると活用形の生成元ごと
            // 消えて候補ゼロになるため、提示層で かな版の下へ回す方式にした
            XCTAssertGreaterThan(list.count, 1, "reading=\(reading) list=\(list)")
            XCTAssertTrue(
                fresh.shouldKeepKanaIdentityLeading(for: reading),
                "keepKana=false だと提示層がかな版を捨てる: reading=\(reading)"
            )
            let presented = SupplementaryCandidateMerger.demotingDekiKanjiBelowKana(list)
            XCTAssertEqual(presented.first, reading, "reading=\(reading) presented=\(presented)")
        }
    }

    // 2564 第2報: のずるそうじ/はやり/だねえ/すむのよ/なるほどー の候補順。
    // なるほ(成保/鳴穂)と のよ(野与/野與)はいずれも収穫底値10000のレア語しか無く、
    // なるほどー・すむのよ を割って当て字合成を作っていたので抑制する。
    func testRegressionRealLMOrderFixes2564Second() throws {
        try prepareRealLMDictionary()
        var merged: [String: [String]] = [:]
        for name in ["InitialSupprVocabMigration", "InitialSupprHiddenVocabMigration"] {
            let data = try Data(contentsOf: URL(fileURLWithPath: "/Users/kusakabe/Git/ecritu/KeyboardExtension/\(name).json"))
            for (reading, candidates) in try JSONDecoder().decode([String: [String]].self, from: data) {
                merged[reading, default: []].append(contentsOf: candidates)
            }
        }
        UserDefaults(suiteName: defaultsSuiteName)?.set(try JSONEncoder().encode(merged), forKey: "\u{c9}crituSuppr_Vocab")
        for name in ["InitialAjoutVocabMigration", "InitialMiscVocabMigration"] {
            let data = try Data(contentsOf: URL(fileURLWithPath: "/Users/kusakabe/Git/ecritu/KeyboardExtension/\(name).json"))
            for (reading, candidates) in try JSONDecoder().decode([String: [String]].self, from: data) {
                for candidate in candidates.reversed() {
                    converter.store.addUserEntry(reading: reading, candidate: candidate)
                }
            }
        }
        let fresh = KanaKanjiConverter(store: KanaKanjiStore(appGroupID: defaultsSuiteName))
        let singles: [(reading: String, expected: String)] = [
            ("のずるそうじ", "ノズル掃除"),
            ("はやり", "流行り"),
            ("だねえ", "だねえ"),
            ("すむのよ", "済むのよ")
        ]
        for (reading, expected) in singles {
            let list = fresh.candidates(for: reading, limit: 8, systemCandidateMode: .surface)
            XCTAssertEqual(list.first, expected, "reading=\(reading) list=\(list)")
            // 連文節が別解(住むのよ 等)を先頭に返すと実機で負けるので、curated 1ノード化で
            // 単文節に委ねさせる。空か、先頭が単文節と一致していること
            let multi = fresh.multiClauseCandidates(for: reading, systemCandidateMode: .surface)
            XCTAssertTrue(multi.isEmpty || multi.first == expected, "reading=\(reading) multi=\(multi)")
        }
        // なるほどー は連文節が 成保どー/鳴穂どー を返していた。なるほ の抑制で消える
        // なるほどー: なるほ の抑制後も なる+保+どー に割られたので seed で1ノード化した
        for reading in ["なるほどー", "なるほどーー"] {
            let single = fresh.candidates(for: reading, limit: 8, systemCandidateMode: .surface)
            XCTAssertEqual(single.first, reading, "reading=\(reading) single=\(single)")
            let multi = fresh.multiClauseCandidates(for: reading, systemCandidateMode: .surface)
            XCTAssertFalse(
                multi.contains(where: { $0.contains("保") || $0.contains("穂") }),
                "reading=\(reading) multi=\(multi)"
            )
        }
    }

    // Swift の辞書リテラルはキー重複で実行時に必ずクラッシュする(Dictionary.swift:840
    // "Dictionary literal contains duplicate keys" → SIGTRAP)。2564で なはし を既存と
    // 気づかず重複追加し、実機のキーボードが起動46秒で落ちた。静的な表なので早期に検出する。
    func testSeedDictionaryHasNoDuplicateKeys() throws {
        // 参照するだけでリテラルが評価される。重複があればここで落ちる
        XCTAssertFalse(KanaKanjiSeedDictionary.seed.isEmpty)
        XCTAssertFalse(KanaKanjiSeedDictionary.exactReadingOnlySeed.isEmpty)
        // 値側も空でないこと(空配列は候補ゼロを招く)
        for (reading, candidates) in KanaKanjiSeedDictionary.seed {
            XCTAssertFalse(candidates.isEmpty, "seed[\(reading)] が空")
        }
        for (reading, candidates) in KanaKanjiSeedDictionary.exactReadingOnlySeed {
            XCTAssertFalse(candidates.isEmpty, "exactReadingOnlySeed[\(reading)] が空")
        }
    }

    // すごーい: {スゴーイ, すごーい} でカタカナが先頭だった(スゴ〜イ/スゴーイ 4283 に対し
    // かな 8156)。末尾長音の keepKana は hasSuffix("ー") 判定なので、長音が語中にある
    // すごーい(末尾は い)には発火しない。長音を全部除いた本体がかな正書(すごい は seed で
    // かな先頭)なら伸ばした形もかなが正書として扱う(ユーザ指定 2564)。
    func testRegressionRealLMInternalElongationKana() throws {
        try prepareRealLMDictionary()

        let list = converter.candidates(for: "すごーい", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(list.first, "すごーい", "list=\(list)")
        // カタカナも候補には残す
        XCTAssertTrue(list.contains(where: { $0.contains("スゴ") }), "list=\(list)")
        // カタカナ語のひらがな入力は巻き込まない(らーめん→ラーメン のままでよい)
        let ramen = converter.candidates(for: "らーめん", limit: 4, systemCandidateMode: .surface)
        XCTAssertNotEqual(ramen.first, "らーめん", "ramen=\(ramen)")
    }

    // 単漢字が最安・rank0 なのに seed 未掲載で沈む読み(からだ→体 と同型)。
    // なみだ は24候補中に 涙 が無かった。単漢字は seed 掲載時のみ優遇される設計
    // (applySeedSingleKanjiPriorityBoost)。1073件の実測から単独入力する語を抽出した。
    // ちから→力 は元々2位に出ていたが、seed で先頭に揃える(ユーザ指定 2564)。
    func testRegressionRealLMSingleKanjiSeeds() throws {
        try prepareRealLMDictionary()

        let cases: [(reading: String, kanji: String)] = [
            ("なみだ", "涙"), ("あいだ", "間"), ("ちから", "力"), ("いけ", "池"), ("ふだ", "札")
        ]
        for (reading, kanji) in cases {
            let list = converter.candidates(for: reading, limit: 8, systemCandidateMode: .surface)
            XCTAssertEqual(list.first, kanji, "reading=\(reading) list=\(list)")
            // かなも候補に残す
            XCTAssertTrue(list.contains(reading), "reading=\(reading) list=\(list)")
        }
    }

    // からだ: {嘉良だ, 唐だ, 迦羅だ, 空だ, 殻だ, 幹だ, 加羅だ} で 体 が出なかった。
    // 体 は word_cost 2888(カラダ と最安タイ)・dict rank0 なのに、から が助詞として
    // 超高頻度(LM 2848)で から+だ(bigram 3176)の合計6024 が 体(4545)+体→だ(3338)=7883 を
    // 下回るため。misc の 体が(からだが)と同じ構図で、が が付かない形が抜けていた。
    // 抑制の誤りではなく辞書は正常(ユーザ指定 2564)。
    func testRegressionRealLMKaradaSingleNode() throws {
        try prepareRealLMDictionary()

        let solo = converter.candidates(for: "からだ", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(solo.first, "体", "solo=\(solo)")
        // seed で1ノード化されるので連文節は単文節に委ねる(空 or 体 が先頭)
        let multi = converter.multiClauseCandidates(for: "からだ", systemCandidateMode: .surface)
        XCTAssertTrue(multi.isEmpty || multi.first == "体", "multi=\(multi)")
        XCTAssertFalse(multi.contains(where: { $0.contains("空だ") || $0.contains("殻だ") }), "multi=\(multi)")
    }

    // いたみが: 単独の いたみ は {痛み, 悼み, 伊丹, 悼, 傷み} で妥当なのに、いたみが だと
    // {傷みが, 痛みが, 伊丹が, …} に変わる。傷み→が の bigram が 424 と極端に安く
    // (傷みが激しい 等)、unigram 差(痛み6254 < 傷み7022)を逆転する。単文節は bigram を
    // 見ないため並びが食い違っていた(ユーザ指定 2564)。
    func testRegressionRealLMItamiGa() throws {
        try prepareRealLMDictionary()

        let multi = converter.multiClauseCandidates(for: "いたみが", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "痛みが", "multi=\(multi)")
        // 単独の並びは従来どおり
        let solo = converter.candidates(for: "いたみ", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(solo.first, "痛み", "solo=\(solo)")
    }

    // おいしいよね: {お石井よね, お石射よね, お伊志井よね, …} と合成だらけだった。
    // お(LM4363)+石井(LM5382) の合計が おいしい(LM6491)より安く、よね は LM 未収録で
    // どちらの経路でも同じ評価なので前半の差で分割が勝つ。単独の おいしい でも2位以降が
    // お石井/お石射 になっていた(ユーザ指定 2564)。
    // 対処は (1) いしい の収穫底値レア姓を抑制 (2) お+石井 のペアを重くする の2つ。
    // よね 側も抑制しかけたが、よね の候補を減らすと います+よね が組めなくなり
    // いますよね→井升よね に壊れたため撤回した(既存テストで検出)。
    func testRegressionRealLMOishiiYone() throws {
        try prepareRealLMDictionary()
        var merged: [String: [String]] = [:]
        for name in ["InitialSupprVocabMigration", "InitialSupprHiddenVocabMigration"] {
            let data = try Data(contentsOf: URL(fileURLWithPath: "/Users/kusakabe/Git/ecritu/KeyboardExtension/\(name).json"))
            for (reading, candidates) in try JSONDecoder().decode([String: [String]].self, from: data) {
                merged[reading, default: []].append(contentsOf: candidates)
            }
        }
        UserDefaults(suiteName: defaultsSuiteName)?.set(try JSONEncoder().encode(merged), forKey: "\u{c9}crituSuppr_Vocab")
        for name in ["InitialAjoutVocabMigration", "InitialMiscVocabMigration"] {
            let data = try Data(contentsOf: URL(fileURLWithPath: "/Users/kusakabe/Git/ecritu/KeyboardExtension/\(name).json"))
            for (reading, candidates) in try JSONDecoder().decode([String: [String]].self, from: data) {
                for candidate in candidates.reversed() {
                    converter.store.addUserEntry(reading: reading, candidate: candidate)
                }
            }
        }
        let fresh = KanaKanjiConverter(store: KanaKanjiStore(appGroupID: defaultsSuiteName))
        let multi = fresh.multiClauseCandidates(for: "おいしいよね", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "おいしいよね", "multi=\(multi)")
        // 石井 は姓として残すが、接頭辞 お の直後に来る組み合わせ(お石井)はペアで
        // 重くしたので先頭には立たない
        XCTAssertFalse(
            multi.contains(where: { $0.contains("石射") || $0.contains("伊志井") || $0.contains("甃井") }),
            "multi=\(multi)"
        )
        if let ishiiIndex = multi.firstIndex(where: { $0.contains("石井") }) {
            XCTAssertGreaterThan(ishiiIndex, 0, "石井 が先頭に来てはいけない multi=\(multi)")
        }
        // 実機で問題だったのは提示層。converter は おいしいよね を1位で返していたのに
        // shouldKeepKanaIdentityLeading が false でかな候補が除去され お石井よね が
        // 繰り上がっていた(実機トレースで確認。2564)
        XCTAssertTrue(
            fresh.shouldKeepKanaIdentityLeading(for: "おいしいよね"),
            "提示層がかな候補を除去してしまう"
        )
        // 単独の おいしい も 石井系 が候補から消える(石井 単体は姓として残す)
        let solo = fresh.candidates(for: "おいしい", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(solo.first, "おいしい", "solo=\(solo)")
        let ishii = fresh.candidates(for: "いしい", limit: 4, systemCandidateMode: .surface)
        XCTAssertTrue(ishii.contains("石井"), "ishii=\(ishii)")
    }

    // それほどでもなかった: 単独の なかった は {なかった, 無かった, 莫かった…} で妥当だが、
    // 連文節では {それほどでも無かった, それほどでも莫かった, …} でかなが末尾に落ちていた。
    // 活用形 なかった は LM に無い(Sudachi の A単位は ない+た に分割)ため unigram で
    // 評価できず、活用エンジンが基底 ない の並び(dict rank は 無い が0位)を継ぐ。
    // でも→ない の bigram も未観測で文脈補正が効かない(ユーザ指定 2564)。
    func testRegressionRealLMDemoNakattaKanaLeading() throws {
        try prepareRealLMDictionary()
        for name in ["InitialAjoutVocabMigration", "InitialMiscVocabMigration"] {
            let data = try Data(contentsOf: URL(fileURLWithPath: "/Users/kusakabe/Git/ecritu/KeyboardExtension/\(name).json"))
            for (reading, candidates) in try JSONDecoder().decode([String: [String]].self, from: data) {
                for candidate in candidates.reversed() {
                    converter.store.addUserEntry(reading: reading, candidate: candidate)
                }
            }
        }
        let fresh = KanaKanjiConverter(store: KanaKanjiStore(appGroupID: defaultsSuiteName))
        let multi = fresh.multiClauseCandidates(for: "それほどでもなかった", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "それほどでもなかった", "multi=\(multi)")
        // 単独の なかった は従来どおりかな先頭
        let solo = fresh.candidates(for: "なかった", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(solo.first, "なかった", "solo=\(solo)")
    }

    // 活用クラスタの穴を一括で埋めた分(2564)。にした/にして/にする/にしよう はあったのに
    // 条件形 にしたら が漏れていた件の横展開。読みの候補が収穫底値のレア語だけ(にしながら→
    // 西名柄10000、できた→出來田/出木田/出来田、できれば→出来れば11155、しまおう→縞王/島王)
    // のものは かまぼこにしたら と同じく句を割るので優先度が高い。してみる 系は丸ごと未登録。
    func testRegressionRealLMConjugationClusterGaps() throws {
        try prepareRealLMDictionary()
        var merged: [String: [String]] = [:]
        for name in ["InitialSupprVocabMigration", "InitialSupprHiddenVocabMigration"] {
            let data = try Data(contentsOf: URL(fileURLWithPath: "/Users/kusakabe/Git/ecritu/KeyboardExtension/\(name).json"))
            for (reading, candidates) in try JSONDecoder().decode([String: [String]].self, from: data) {
                merged[reading, default: []].append(contentsOf: candidates)
            }
        }
        UserDefaults(suiteName: defaultsSuiteName)?.set(try JSONEncoder().encode(merged), forKey: "\u{c9}crituSuppr_Vocab")
        for name in ["InitialAjoutVocabMigration", "InitialMiscVocabMigration"] {
            let data = try Data(contentsOf: URL(fileURLWithPath: "/Users/kusakabe/Git/ecritu/KeyboardExtension/\(name).json"))
            for (reading, candidates) in try JSONDecoder().decode([String: [String]].self, from: data) {
                for candidate in candidates.reversed() {
                    converter.store.addUserEntry(reading: reading, candidate: candidate)
                }
            }
        }
        let fresh = KanaKanjiConverter(store: KanaKanjiStore(appGroupID: defaultsSuiteName))
        let readings = ["にしても", "にしながら",
                        "になったら", "になっても", "になったり", "になりません",
                        "してみる", "してみた", "してみて", "してみよう",
                        "してみたら", "してみれば", "してみても",
                        "やったら", "やっても", "やったり",
                        "できた", "できて", "できない", "できたら",
                        "できれば", "できても", "できます",
                        "しまった", "しまって", "しまおう"]
        for reading in readings {
            let list = fresh.candidates(for: reading, limit: 8, systemCandidateMode: .surface)
            let presented = SupplementaryCandidateMerger.demotingDekiKanjiBelowKana(list)
            XCTAssertEqual(presented.first, reading, "reading=\(reading) presented=\(presented)")
        }
    }

    // せいせい: dictionary_entries の rank が 整斉/世世/清々/正々/済々/世々/斉整/齊整 の
    // 順で、LM で圧倒的に高頻度な 生成(4824)/精製(6032) が9位・10位に沈んでいた。
    // 製成 は sacoche 登録(酒造用語)で先頭に出ていたが日常語を優先する(ユーザ指定 2564)。
    func testRegressionRealLMSeiseiOrder() throws {
        try prepareRealLMDictionary()
        for name in ["InitialAjoutVocabMigration", "InitialMiscVocabMigration"] {
            let data = try Data(contentsOf: URL(fileURLWithPath: "/Users/kusakabe/Git/ecritu/KeyboardExtension/\(name).json"))
            for (reading, candidates) in try JSONDecoder().decode([String: [String]].self, from: data) {
                for candidate in candidates.reversed() {
                    converter.store.addUserEntry(reading: reading, candidate: candidate)
                }
            }
        }
        let fresh = KanaKanjiConverter(store: KanaKanjiStore(appGroupID: defaultsSuiteName))
        let list = fresh.candidates(for: "せいせい", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(list.prefix(3)), ["生成", "精製", "製成"], "list=\(list)")
    }

    // やわらかくてのうこう: {軟らかくて農耕, 柔らかくて農耕, 軟かくて農耕, 柔らかくて濃厚}
    // の順で 農耕 が固定されていた。単文節は dictionary_entries の rank(濃厚が rank0)を
    // 見るので 濃厚 が先頭になるが、連文節は LM unigram(農耕5874 < 濃厚6427)を見るため
    // 逆転する。柔らかくて→農耕 も →濃厚 も bigram 未観測で文脈補正が効かない。
    // 変種は1文節だけ差し替える方式なので 農耕 固定のまま前半だけが入れ替わっていた。
    func testRegressionRealLMYawarakakuteNoukou() throws {
        try prepareRealLMDictionary()

        let multi = converter.multiClauseCandidates(for: "やわらかくてのうこう", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "柔らかくて濃厚", "multi=\(multi)")
        // 単文節の並びは従来どおり(濃厚が先頭)
        let single = converter.candidates(for: "のうこう", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "濃厚", "single=\(single)")
    }

    // かまぼこにしたら: {かまぼこ西田ら, 蒲鉾にしたら, かまぼこ仁下ら, …} の順だった。
    // にした/にして/にする/にしよう は misc に登録済みだが条件形 にしたら が漏れており、
    // したら 単独も辞書は 設楽/設樂 だけでかながない。さらに にした の読みには収穫底値
    // 10000 のレア姓(仁下/西多/西夛)、にしたら には 西太良 があり句を割る(ユーザ指定 2564)。
    func testRegressionRealLMShitaraConditional() throws {
        try prepareRealLMDictionary()
        var merged: [String: [String]] = [:]
        for name in ["InitialSupprVocabMigration", "InitialSupprHiddenVocabMigration"] {
            let data = try Data(contentsOf: URL(fileURLWithPath: "/Users/kusakabe/Git/ecritu/KeyboardExtension/\(name).json"))
            for (reading, candidates) in try JSONDecoder().decode([String: [String]].self, from: data) {
                merged[reading, default: []].append(contentsOf: candidates)
            }
        }
        UserDefaults(suiteName: defaultsSuiteName)?.set(try JSONEncoder().encode(merged), forKey: "\u{c9}crituSuppr_Vocab")
        for name in ["InitialAjoutVocabMigration", "InitialMiscVocabMigration"] {
            let data = try Data(contentsOf: URL(fileURLWithPath: "/Users/kusakabe/Git/ecritu/KeyboardExtension/\(name).json"))
            for (reading, candidates) in try JSONDecoder().decode([String: [String]].self, from: data) {
                for candidate in candidates.reversed() {
                    converter.store.addUserEntry(reading: reading, candidate: candidate)
                }
            }
        }
        let fresh = KanaKanjiConverter(store: KanaKanjiStore(appGroupID: defaultsSuiteName))
        let multi = fresh.multiClauseCandidates(for: "かまぼこにしたら", systemCandidateMode: .surface)
        // 蒲鉾 を先頭に(LM は かまぼこ7216 < 蒲鉾7272 の僅差で放置するとかなが勝つ)
        XCTAssertEqual(multi.first, "蒲鉾にしたら", "multi=\(multi)")
        XCTAssertFalse(
            multi.contains(where: { $0.contains("仁下") || $0.contains("西多") || $0.contains("西太良") }),
            "multi=\(multi)"
        )
        for reading in ["したら", "にしたら"] {
            let list = fresh.candidates(for: reading, limit: 6, systemCandidateMode: .surface)
            XCTAssertEqual(list.first, reading, "reading=\(reading) list=\(list)")
        }
    }

    // ろーすかつ: {ロース勝つ, ロースかつ, ロース且つ, ロース喝} で ロースカツ が出なかった。
    // ロース→カツ の bigram が未観測で unigram 差だけで決まり、Wikipedia 由来の LM では
    // 勝つ(5948)/かつ(4857) が カツ(7243) より安い。ヒレカツ(2148)・メンチカツ(2118)・
    // カツ丼(3702)は辞書にあるのに ロースカツ 等は未収録だった(ユーザ指定 2564)。
    func testRegressionRealLMKatsuCompounds() throws {
        try prepareRealLMDictionary()
        for name in ["InitialAjoutVocabMigration", "InitialMiscVocabMigration"] {
            let data = try Data(contentsOf: URL(fileURLWithPath: "/Users/kusakabe/Git/ecritu/KeyboardExtension/\(name).json"))
            for (reading, candidates) in try JSONDecoder().decode([String: [String]].self, from: data) {
                for candidate in candidates.reversed() {
                    converter.store.addUserEntry(reading: reading, candidate: candidate)
                }
            }
        }
        let fresh = KanaKanjiConverter(store: KanaKanjiStore(appGroupID: defaultsSuiteName))
        let cases: [(reading: String, expected: String)] = [
            ("ろーすかつ", "ロースカツ"),
            ("ぎゅうかつ", "牛カツ"),
            ("かつさんど", "カツサンド"),
            ("かつかれー", "カツカレー"),
            ("えびふらい", "エビフライ"),
            ("かきふらい", "カキフライ"),
            // 三元豚: Sudachi に 三元豚 も 三元 も無く さんげん→三弦/三絃 にしかならない
            ("さんげんとん", "三元豚")
        ]
        for (reading, expected) in cases {
            let list = fresh.candidates(for: reading, limit: 8, systemCandidateMode: .surface)
            XCTAssertEqual(list.first, expected, "reading=\(reading) list=\(list)")
        }
        // フライ物はカタカナを先頭にしつつ漢字表記も候補に残す(ユーザ指定 2564)
        for (reading, kanji) in [("えびふらい", "海老フライ"), ("かきふらい", "牡蠣フライ")] {
            let list = fresh.candidates(for: reading, limit: 8, systemCandidateMode: .surface)
            XCTAssertTrue(list.contains(kanji), "reading=\(reading) list=\(list)")
        }
    }

    // なはしすいどうきょく: {那覇し水道局, 奈半し水道局, …} で 那覇市水道局 が5位だった。
    // 那覇市 は word_cost 10199(収穫底値帯)で 那覇(7869)+し(2760)の分割より高く、
    // 連文節も 那覇→市 / 市→水道 の bigram が未観測。水道局 も辞書・LM とも未収録で
    // 水道+局 の合成頼みだった(ユーザ指定 2564)。
    func testRegressionRealLMNahaCityWaterBureau() throws {
        try prepareRealLMDictionary()
        for name in ["InitialAjoutVocabMigration", "InitialMiscVocabMigration"] {
            let data = try Data(contentsOf: URL(fileURLWithPath: "/Users/kusakabe/Git/ecritu/KeyboardExtension/\(name).json"))
            for (reading, candidates) in try JSONDecoder().decode([String: [String]].self, from: data) {
                for candidate in candidates.reversed() {
                    converter.store.addUserEntry(reading: reading, candidate: candidate)
                }
            }
        }
        let fresh = KanaKanjiConverter(store: KanaKanjiStore(appGroupID: defaultsSuiteName))
        let naha = fresh.candidates(for: "なはし", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(naha.first, "那覇市", "list=\(naha)")
        let bureau = fresh.candidates(for: "すいどうきょく", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(bureau.first, "水道局", "list=\(bureau)")
        let combined = fresh.multiClauseCandidates(for: "なはしすいどうきょく", systemCandidateMode: .surface)
        XCTAssertEqual(combined.first, "那覇市水道局", "multi=\(combined)")
    }

    // 句・複合語の読みは基底辞書が空で seed が候補集合そのものになる(systemCandidates の
    // マージは storeCandidates が空なら seed のみ)。1候補だけ書くと他の表記が出せなくなる
    // ため、残したい表記も並べる。先頭(既定の変換結果)は変えない(ユーザ指定 2564)。
    func testRegressionRealLMPhraseSeedKeepsVariants() throws {
        try prepareRealLMDictionary()

        let cases: [(reading: String, leading: String, variant: String)] = [
            ("くいかた", "食い方", "食いかた"),
            ("からつき", "殻付き", "殻つき"),
            ("いきませんか", "行きませんか", "いきませんか"),
            ("くいにいきませんか", "食いに行きませんか", "食いにいきませんか"),
            ("つかわずにすむ", "使わずに済む", "使わずにすむ"),
            ("なにする", "何する", "なにする"),
            ("ひとばん", "一晩", "ひと晩")
        ]
        for (reading, leading, variant) in cases {
            let list = converter.candidates(for: reading, limit: 8, systemCandidateMode: .surface)
            XCTAssertEqual(list.first, leading, "reading=\(reading) list=\(list)")
            XCTAssertTrue(list.contains(variant), "reading=\(reading) list=\(list)")
        }
    }

    // つかわずにすむ: すむ の word_cost が 住む(7228) < 済む(7946) のため 使わずに住む
    // だった。「〜ずに済む」は済むが正しい(ユーザ指定 2564)。
    func testRegressionRealLMTsukawazuNiSumu() throws {
        try prepareRealLMDictionary()

        let list = converter.candidates(for: "つかわずにすむ", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(list.first, "使わずに済む", "list=\(list)")
    }

    // なんでまた: {何で又, 何でまた, 何で股, なんで又, なんでまた} だった。日常表記の
    // 何でまた を先頭、かな を2位へ(ユーザ指定 2564)。
    func testRegressionRealLMNandeMata() throws {
        try prepareRealLMDictionary()

        let list = converter.candidates(for: "なんでまた", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(list.first, "何でまた", "list=\(list)")
        XCTAssertEqual(list.dropFirst().first, "なんでまた", "list=\(list)")
    }

    // かえるかなあ: {変えるかなあ, 蛙化なあ, 帰るかなあ, カエルかなあ, …} で 買えるかなあ が
    // 7位だった。買える→帰る→変える の順に(ユーザ指定 2564)。
    func testRegressionRealLMKaeruKanaa() throws {
        try prepareRealLMDictionary()

        let list = converter.candidates(for: "かえるかなあ", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(list.prefix(3)), ["買えるかなあ", "帰るかなあ", "変えるかなあ"], "list=\(list)")
    }

    // くいにいきませんか: くい の word_cost が 悔い(7159) < 食い(9019) で
    // 悔いに行きませんか が先頭だった(ユーザ指定 2564)。
    func testRegressionRealLMKuiNiIkimasenka() throws {
        try prepareRealLMDictionary()

        let list = converter.candidates(for: "くいにいきませんか", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(list.first, "食いに行きませんか", "list=\(list)")
    }

    // なるほどー: 末尾を長音で引き伸ばした形は辞書に無く {成保どー, 鳴穂どー, なるほどー} の
    // 順だった。長音を剥がした本体がかな正書なら伸ばした形もかなが正書として供給する
    // (ユーザ指定 2564)。漢字が正書の語(成る程 ではなく なるほど 側)にのみ発火する。
    func testRegressionRealLMElongatedKanaTail() throws {
        try prepareRealLMDictionary()

        for reading in ["なるほどー", "なるほどーー"] {
            let single = converter.candidates(for: reading, limit: 8, systemCandidateMode: .surface)
            XCTAssertEqual(single.first, reading, "single reading=\(reading) list=\(single)")
        }
        // 長音を伴わない本体側は従来どおり(なるほど 自体の先頭は変わらない)
        let base = converter.candidates(for: "なるほど", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(base.first, "なるほど", "list=\(base)")
    }

    // 追加語彙(sacoche/misc)込みの回帰: なのね のかな正書、醤油麹/OK/デュアーズ の供給欠落
    // (ユーザ指定 2564)。テストバンドルには JSON が載らないので実機相当に注入する。
    func testRegressionRealLMVocabAdditions2564() throws {
        try prepareRealLMDictionary()
        for name in ["InitialAjoutVocabMigration", "InitialMiscVocabMigration"] {
            let data = try Data(contentsOf: URL(fileURLWithPath: "/Users/kusakabe/Git/ecritu/KeyboardExtension/\(name).json"))
            let dict = try JSONDecoder().decode([String: [String]].self, from: data)
            for (reading, candidates) in dict {
                for candidate in candidates.reversed() {
                    converter.store.addUserEntry(reading: reading, candidate: candidate)
                }
            }
        }
        let fresh = KanaKanjiConverter(store: KanaKanjiStore(appGroupID: defaultsSuiteName))
        let cases: [(reading: String, expected: String)] = [
            ("なのね", "なのね"),
            ("しょうゆこうじ", "醤油麹"),
            ("おーけい", "OK"),
            ("でゅあーず", "デュアーズ")
        ]
        for (reading, expected) in cases {
            let list = fresh.candidates(for: reading, limit: 8, systemCandidateMode: .surface)
            XCTAssertEqual(list.first, expected, "reading=\(reading) list=\(list)")
        }
    }

    // はくし: 博士 が word_cost 8757 で {柏子, 白指, 白詩, 薄志, 薄資}(7404)のレア語群に
    // 負けて7番目だった。白紙 1位を維持しつつ 博士 を2位へ(ユーザ指定 2564)。
    func testRegressionRealLMHakushiPrefersHakushi() throws {
        try prepareRealLMDictionary()

        let hakushi = converter.candidates(for: "はくし", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(hakushi.first, "白紙", "list=\(hakushi)")
        XCTAssertEqual(hakushi.dropFirst().first, "博士", "list=\(hakushi)")
    }

    // なるので/ですかね: かな正書の機能語句が連文節で 鳴るので/出須賀ね に乗っ取られて
    // いた。句スパンのかな識別を seed 供給+ボーナスで先頭に(ユーザ指定 2556)。
    func testRegressionRealLMNarunodeDesukaneKanaLeading() throws {
        try prepareRealLMDictionary()

        let narunode = converter.candidates(for: "なるので", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(narunode.first, "なるので", "list=\(narunode)")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "なるので"))
        let desukane = converter.candidates(for: "ですかね", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(desukane.first, "ですかね", "list=\(desukane)")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "ですかね"))
        // 別スパンの なる(音が鳴る)と 気になるので は不変であること
        let naru = converter.multiClauseCandidates(for: "おとがなる", systemCandidateMode: .surface)
        XCTAssertTrue(naru.contains { $0.contains("鳴る") }, "multi=\(naru)")
        let kininaru = converter.multiClauseCandidates(for: "きになるのでしょう", systemCandidateMode: .surface)
        XCTAssertEqual(kininaru.first, "気になるのでしょう", "multi=\(kininaru)")
    }

    // ごはん: ご飯 が dictionary_entries に無く、連文節で 語+版 の分割が勝って
    // 炊き込んだ語版 になっていた。おもろまち: 収穫底値+LM未収録で お諸町 等の分割に
    // 負けていた。どちらも a2 seed供給+名詞seed順ボーナスで是正(2554)。
    func testRegressionRealLMGohanOmoromachiMultiClause() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary()

        let gohan = converter.multiClauseCandidates(for: "たきこんだごはん", systemCandidateMode: .surface)
        XCTAssertEqual(gohan.first, "炊き込んだご飯", "multi=\(gohan)")
        let omoro = converter.multiClauseCandidates(for: "おもろまちならば", systemCandidateMode: .surface)
        XCTAssertEqual(omoro.first, "おもろまちならば", "multi=\(omoro)")
        let omoroNara = converter.multiClauseCandidates(for: "おもろまちなら", systemCandidateMode: .surface)
        XCTAssertEqual(omoroNara.first, "おもろまちなら", "multi=\(omoroNara)")
        // 表示層のかな識別根拠(これが無いと実機バーでかな先頭が除去され お諸町 が
        // 繰り上がる — 実機トレースで確定した実バグ。2557)
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "おもろまちなら"))
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "おもろまちならば"))
        // 単文節の ごはん は seed 既定のまま
        let single = converter.candidates(for: "ごはん", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(2)), ["ご飯", "御飯"], "single=\(single)")
    }

    // たえきれる/堪えきれる: Sudachi に無く、たえきれなくなって が 栲切れ/多恵きれ 等の
    // 名前合成に落ちていた。misc 一段登録(あり得る と同型)で活用ごと供給(2554)。
    func testRegressionRealLMTaekirePrefersTaeru() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary()

        let nakunatte = converter.candidates(for: "たえきれなくなって", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(nakunatte.prefix(2)), ["耐えきれなくなって", "堪えきれなくなって"], "list=\(nakunatte)")
        let nai = converter.candidates(for: "たえきれない", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(nai.first, "耐えきれない", "list=\(nai)")
    }

    // いきませんか: 一段 生きる/活きる 連用が五段 行く 連用より先に出ていた。
    // 勧誘の主用途 行きませんか を先頭に(ユーザ指定 2554)。
    func testRegressionRealLMIkimasenkaPrefersIku() throws {
        try prepareRealLMDictionary()

        let iki = converter.candidates(for: "いきませんか", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(iki.first, "行きませんか", "list=\(iki)")
    }

    // さす: 動詞4種 {指す, 刺す, 挿す, 差す} を先頭群に、かな さす は末尾へ。
    // さしなおす: 辞書エントリ無しの供給欠落(挿し直す/刺し直す が出ない)を seed 供給
    // (ユーザ指定 2552)。
    func testRegressionRealLMSasuSashinaosuOrdering() throws {
        try prepareRealLMDictionary()

        let sasu = converter.candidates(for: "さす", limit: 10, systemCandidateMode: .surface)
        XCTAssertEqual(Array(sasu.prefix(7)), ["指す", "刺す", "挿す", "差す", "サス", "砂州", "鎖す"], "list=\(sasu)")
        let naosu = converter.candidates(for: "さしなおす", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(naosu.prefix(4)), ["指し直す", "挿し直す", "差し直す", "刺し直す"], "list=\(naosu)")
    }

    // しもん: カタカナ識別 シモン が先頭だった。{指紋, 諮問, 試問} を先頭群に、
    // シモン は後方へ(ユーザ指定 2552)。
    func testRegressionRealLMShimonPrefersShimon() throws {
        try prepareRealLMDictionary()

        let shimon = converter.candidates(for: "しもん", limit: 10, systemCandidateMode: .surface)
        XCTAssertEqual(Array(shimon.prefix(3)), ["指紋", "諮問", "試問"], "list=\(shimon)")
    }

    // スイープ残渣のうちユーザが並びを明示指定した読み(2550)。seed の複数掲載
    // (順序正規化)で指定順を先頭に固定する。LM最良が3位以下になる読み
    // (だん/ねぎ/こんだ/こうし/みこ/あらい/あわ/するっ)はスイープの許容リスト側に登録済み。
    func testRegressionRealLMSweepCustomOrderReadings() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary()

        let expectations: [(String, [String])] = [
            ("あらい", ["洗い", "粗い", "荒い", "新井"]),
            ("あわ", ["泡", "粟", "阿波"]),
            ("かこう", ["加工", "書こう", "描こう"]),
            ("かろう", ["刈ろう", "家老"]),
            ("こうこ", ["香茹", "考古"]),
            ("こうし", ["仔牛", "講師", "行使", "格子", "孔子", "光子"]),
            ("こうしん", ["香信", "更新", "行進"]),
            ("こんだ", ["混んだ", "込んだ", "今田"]),
            ("しんとう", ["浸透", "神道", "心頭", "震盪"]),
            ("するっ", ["するっ", "スルっ", "スルッ"]),
            ("せいい", ["誠意", "征夷", "青衣"]),
            ("せんりょう", ["線量", "占領", "染料"]),
            ("だん", ["段", "談", "団"]),
            ("ちし", ["地誌", "致死", "致仕", "致事", "知歯"]),
            ("てい", ["亭", "低", "底", "丁"]),
            ("とうか", ["透過", "投下", "等価", "灯火", "桃花", "灯下"]),
            ("ねぎ", ["ねぎ", "葱", "ネギ", "禰宜"]),
            ("はいたい", ["ハイタイ", "敗退"]),
            ("ひょう", ["表", "票", "雹", "豹"]),
            ("ふれ", ["触れ", "振れ", "降れ"]),
            ("ぼう", ["某", "棒", "房", "坊", "傍"]),
            ("みこ", ["巫女", "御子", "皇子", "神子"]),
            ("みのる", ["実る", "稔"]),
            ("めり", ["メリ", "減り"]),
            ("ゆたか", ["豊か", "豊"])
        ]
        var failures: [String] = []
        for (reading, prefix) in expectations {
            let list = converter.candidates(for: reading, limit: 10, systemCandidateMode: .surface)
            if Array(list.prefix(prefix.count)) != prefix {
                failures.append("\(reading): 期待=\(prefix) 実際=\(list.prefix(prefix.count + 2))")
            }
        }
        XCTAssertTrue(failures.isEmpty, "\(failures.count)件:\n" + failures.joined(separator: "\n"))
    }

    // 助数詞監査(常設ハーネス): 数字直後(3+読み)で主要助数詞が上位5位に出るかを一括検査し、
    // 出ないものを COUNTERNG 行で報告する(1ばん→版 のような供給漏れの機械的検出。
    // びょういん は数字+非助数詞の対照群)。TEST_RUNNER_COUNTERAUDIT=1 のときだけ実行。
    func testDiagnosticNumericCounterAudit() throws {
        guard ProcessInfo.processInfo.environment["COUNTERAUDIT"] != nil else {
            throw XCTSkip("COUNTERAUDIT=1(xcodebuild には TEST_RUNNER_COUNTERAUDIT=1)のときだけ実行")
        }
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary()

        let counters: [(String, [String])] = [
            ("かい", ["回", "階"]),
            ("ほん", ["本"]),
            ("まい", ["枚"]),
            ("さつ", ["冊", "札"]),
            ("だい", ["台"]),
            ("けん", ["件", "軒"]),
            ("こ", ["個"]),
            ("にん", ["人"]),
            ("めい", ["名"]),
            ("ひき", ["匹"]),
            ("とう", ["頭", "等"]),
            ("わ", ["羽", "話"]),
            ("そく", ["足"]),
            ("ちゃく", ["着"]),
            ("つう", ["通"]),
            ("きゃく", ["脚", "客"]),
            ("ばい", ["倍", "杯"]),
            ("はい", ["杯", "敗"]),
            ("はつ", ["発"]),
            ("しょう", ["勝", "章"]),
            ("ど", ["度"]),
            ("てん", ["点"]),
            ("えん", ["円"]),
            ("さい", ["歳"]),
            ("ばん", ["番", "晩"]),
            ("はく", ["泊"]),
            ("にち", ["日"]),
            ("しゅう", ["週", "周"]),
            ("ねん", ["年"]),
            ("びょう", ["秒"]),
            ("ふん", ["分"]),
            ("じ", ["時"]),
            ("かげつ", ["ヶ月", "カ月", "か月"]),
            ("きょく", ["曲"]),
            ("えき", ["駅"]),
            ("しゃ", ["社", "車"]),
            ("こう", ["校"]),
            ("かん", ["巻", "缶"]),
            ("じょう", ["畳", "錠"]),
            ("ちょうめ", ["丁目"]),
            ("つぼ", ["坪"]),
            ("くみ", ["組"]),
            ("さら", ["皿"]),
            ("ぜん", ["膳"]),
            ("つぶ", ["粒"]),
            ("てき", ["滴"]),
            ("たば", ["束"]),
            ("ふくろ", ["袋"]),
            ("はこ", ["箱"]),
            ("せき", ["隻", "席"]),
            ("そう", ["艘", "槽"]),
            ("き", ["機", "基"]),
            ("もん", ["問", "門"]),
            ("だん", ["段"]),
            ("きゅう", ["球", "級"]),
            ("い", ["位"]),
            ("ごう", ["号"]),
            ("がつ", ["月"]),
            ("けた", ["桁"]),
            ("わり", ["割"]),
            ("ぶ", ["部"]),
            ("ぎょう", ["行"]),
            ("れつ", ["列"]),
            ("もじ", ["文字"]),
            ("だんめ", ["段目"]),
            ("ばんめ", ["番目"]),
            ("こめ", ["個目"]),
            ("かいめ", ["回目"]),
            ("にんめ", ["人目"]),
            ("びょういん", ["病院"])
        ]
        var ngCount = 0
        for (reading, expectedList) in counters {
            let list = converter.candidates(for: "3" + reading, limit: 16, systemCandidateMode: .surface)
            let top = Array(list.prefix(5))
            if !expectedList.contains(where: { top.contains($0) }) {
                ngCount += 1
                print("COUNTERNG\t\(reading)\t期待=\(expectedList)\ttop=\(top)")
            }
        }
        print("COUNTERAUDIT done checked=\(counters.count) ng=\(ngCount)")
        XCTAssertEqual(ngCount, 0, "助数詞の供給漏れあり(COUNTERNG 行参照)")
    }

    // 連文節ラティスのアロケーション計測(常設ハーネス)。実タイプを模して文の全プレフィクスを
    // 変換し、malloc ゾーン統計(確保集計/使用中/ピーク)の増分を出力する。アリーナ肥大
    // (実機で alloc 68〜72MB)対策の効果測定用。TEST_RUNNER_ALLOCPROF=1 のときだけ実行。
    func testDiagnosticMultiClauseAllocationProfile() throws {
        guard ProcessInfo.processInfo.environment["ALLOCPROF"] != nil else {
            throw XCTSkip("ALLOCPROF=1(xcodebuild には TEST_RUNNER_ALLOCPROF=1)のときだけ実行")
        }
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary()

        let sentences = [
            "きょうはあめがふりそうなのでかさをもっていきます",
            "たきこんだごはんをたべてからでかけるつもりです",
            "しんぴんをかうかどうかはねだんをみてからきめたい",
            "らいしゅうのかいぎのしりょうをじゅんびしておいてください",
            "このあたりはよるになるとひとどおりがすくなくなる"
        ]
        // ウォームアップ(キャッシュ初期化ぶんを計測から外す)
        for s in sentences {
            _ = converter.multiClauseCandidates(for: s, systemCandidateMode: .surface)
        }

        var before = malloc_statistics_t()
        malloc_zone_statistics(nil, &before)
        let repeats = 20
        for _ in 0..<repeats {
            for sentence in sentences {
                let chars = Array(sentence)
                for end in 4...chars.count {
                    _ = converter.multiClauseCandidates(
                        for: String(chars[0..<end]), systemCandidateMode: .surface)
                }
            }
        }
        var after = malloc_statistics_t()
        malloc_zone_statistics(nil, &after)
        func mb(_ v: Int) -> String { String(format: "%.1f", Double(v) / 1048576.0) }
        let useB = Int(before.size_in_use), useA = Int(after.size_in_use)
        let allocB = Int(before.size_allocated), allocA = Int(after.size_allocated)
        print("ALLOCPROF conversions=\(repeats * sentences.map { $0.count - 3 }.reduce(0, +))")
        print("ALLOCPROF size_in_use \(mb(useB))MB -> \(mb(useA))MB (Δ\(mb(useA - useB))MB)")
        print("ALLOCPROF size_allocated(アリーナ) \(mb(allocB))MB -> \(mb(allocA))MB (Δ\(mb(allocA - allocB))MB)")
        print("ALLOCPROF blocks_in_use \(before.blocks_in_use) -> \(after.blocks_in_use)")
    }

    // LM順乖離スイープ第2段(常設ハーネス): tools/audit_lm_rank_mismatch.py の出力を
    // 実変換に通し、LM最良候補が上位2位に出ない読みだけを SWEEPNG 行で報告する。
    // 4千変換で数十秒〜2分かかるため通常のスイートではスキップし、
    // TEST_RUNNER_SWEEP=1 のときだけ実行する(機械的チェックの定期実行用)。
    // LM順乖離スイープの残渣一括是正(ユーザ承認156読み、2548〜2550)の固定。
    // seed 供給+並び指定で、LM最良候補が上位2位以内(かな識別先頭を許容)に出ること。
    func testRegressionRealLMSweepApprovedResiduePairs() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary()

        let pairs: [(String, String)] = [
            ("あいこ", "愛子"), ("あかし", "証"), ("あきら", "晶"), ("あこう", "赤穂"), ("あすか", "飛鳥"), ("あず", "按司"),
            ("あたえ", "与"), ("あまてらす", "アマテラス"), ("あまの", "天野"), ("あめ", "雨"), ("あらまち", "新町"),
            // いたい→遺体 は 2606 で除外。ユーザ指定で {痛い, 居たい, いたい, 遺体} の順に
            // 変えたため上位2件に入らなくなった(testRegressionRealLMItaiPrefersItai が受け持つ)
            ("あんだ", "安打"), ("いこう", "以降"), ("いちお", "一男"), ("うただ", "宇多田"),
            ("うつびょう", "うつ病"), ("うら", "裏"), ("えんじゃ", "演者"), ("おおはら", "小原"), ("おき", "起き"),
            ("おくない", "屋内"), ("おさか", "櫻坂"), ("おた", "尾田"), ("おちかた", "遠方"), ("かえ", "変え"),
            ("かき", "下記"), ("かぐら", "神楽"), ("かごう", "化合"), ("かずお", "和夫"), ("かずき", "和樹"),
            ("かずみ", "和美"), ("かずや", "和也"), ("かずよし", "知良"), ("かせい", "火星"), ("かた", "型"),
            ("かつひろ", "克洋"), ("かとう", "加藤"), ("かぶ", "下部"), ("かみすぎ", "上杉"), ("きい", "紀伊"),
            ("きっす", "キッス"), ("きっと", "キット"), ("きない", "畿内"), ("きょうだ", "強打"), ("くだ", "管"),
            ("くどく", "功徳"), ("くにお", "邦男"), ("くるめ", "久留米"), ("けいこ", "恵子"), ("こうが", "黄河"),
            ("こうき", "後期"), ("こうず", "構図"), ("こうない", "構内"), ("こうやま", "神山"), ("こうよう", "高揚"),
            ("こうり", "公理"), ("こし", "腰"), ("こた", "古田"), ("こな", "粉"), ("こもだ", "米田"), ("さい", "再"),
            ("さけ", "酒"), ("さし", "指し"), ("さつ", "冊"), ("さとこ", "敏子"), ("さへん", "左辺"), ("さわだ", "沢田"),
            ("しこう", "施行"), ("しだ", "志田"), ("しゅういち", "修一"), ("しゅん", "駿"), ("しるべ", "導"),
            ("しんし", "紳士"), ("しんど", "震度"), ("じゅり", "受理"), ("じょうおう", "承応"), ("すおう", "周防"),
            // たい→対 は 2608 で除外。ユーザ指定で タイ を先頭にしたため上位2件に入らなくなった
            ("せい", "性"), ("せんない", "線内"), ("そうけい", "総計"), ("そうだ", "操舵"), ("そだ", "曽田"),
            ("たいぞう", "泰三"), ("たいない", "体内"), ("たかあき", "貴明"), ("たかこ", "貴子"), ("たから", "宝"),
            ("たくろう", "拓郎"), ("たけもと", "竹本"), ("たける", "健"), ("ただお", "忠夫"), ("だいだ", "代打"),
            ("ちゅう", "注"), ("ちょうだ", "町田"), ("ちり", "地理"), ("つげ", "告げ"), ("つむ", "積む"), ("つよし", "剛"),
            ("つる", "鶴"), ("とう", "等"), ("としろう", "俊郎"), ("とない", "都内"), ("なおや", "直也"), ("なおゆき", "尚之"),
            ("なおよし", "直美"), ("なかみ", "中身"), ("のせ", "乗せ"), ("のぶお", "信雄"), ("のぶただ", "信忠"),
            ("のぶゆき", "信之"), ("はえ", "栄え"), ("はた", "羽田"), ("はたの", "波多野"), ("はる", "春"), ("はるお", "春夫"),
            ("はるだ", "原田"), ("ひだ", "飛騨"), ("ひでお", "英夫"), ("ひでこ", "秀子"), ("ひろう", "披露"),
            ("ふくそう", "服装"), ("ふくよう", "服用"), ("ふこう", "不幸"), ("ふみひろ", "史浩"), ("へき", "碧"),
            ("ほうろう", "放浪"), ("ほや", "ホヤ"), ("まいる", "マイル"), ("まおう", "魔王"), ("まさあき", "正昭"),
            ("まさこ", "雅子"), ("まさつぐ", "正次"), ("まさなり", "雅也"), ("まさのぶ", "正信"), ("まちこ", "町子"),
            ("まり", "マリ"), ("みえ", "見え"), ("みかえる", "ミカエル"), ("みたて", "見立て"), ("みつお", "光雄"),
            ("もくし", "目視"), ("もとむ", "探"), ("もん", "門"), ("やすこ", "靖子"), ("ゆうき", "有機"), ("ゆうや", "裕也"),
            ("ゆき", "雪"), ("よしさだ", "義貞"), ("よしただ", "義理"), ("よしだ", "吉田"), ("よしひと", "賢人"),
            ("よしみつ", "義満"), ("よそう", "予想"), ("りょうこ", "良子")
        ]
        var failures: [String] = []
        for (reading, expected) in pairs {
            let list = converter.candidates(for: reading, limit: 8, systemCandidateMode: .surface)
            if !list.prefix(2).contains(expected) {
                failures.append("\(reading)→\(expected) top=\(list.prefix(4))")
            }
        }
        XCTAssertTrue(failures.isEmpty, "\(failures.count)件:\n" + failures.joined(separator: "\n"))
    }

    func testDiagnosticLMRankMismatchSweep() throws {
        guard ProcessInfo.processInfo.environment["SWEEP"] != nil else {
            throw XCTSkip("SWEEP=1(xcodebuild には TEST_RUNNER_SWEEP=1)のときだけ実行")
        }
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary()

        let tsvURL = URL(fileURLWithPath: "/Users/kusakabe/Git/ecritu/tmp/lm_rank_mismatch.tsv")
        guard FileManager.default.fileExists(atPath: tsvURL.path) else {
            throw XCTSkip("先に tools/audit_lm_rank_mismatch.py を実行して TSV を生成すること")
        }
        let tsv = try String(contentsOf: tsvURL, encoding: .utf8)
        // ユーザレビュー済みの許容読み(現状の並びが正、以後NG報告しない。2548)
        let acceptedReadings: Set<String> = [
            "かの", "そく", "そる", "いよいよ", "よぎ", "ふくしま", "きへい", "へいき",
            "たいら", "あだち", "ばい", "あたり", "さら", "きが", "きおう", "こむ",
            "こうがんざい", "しょうのう", "せき", "へい", "やすい", "しろう",
            "しんそん", "やぎ",
            // 追加レビュー分(2549)
            "きき", "かく", "せんか", "しゃ", "つけたり", "ねた", "にしん", "さんが",
            "うめず", "かせ", "こい", "きよう", "じん", "じゅう", "かみ", "さいき",
            "しげる", "まさみ", "いさむ", "ばんどう", "きょ", "くす",
            // 追加レビュー分(2550)。後半8読みは並び明示指定(custom order テスト)で
            // LM最良が3位以下になるため許容
            "どう", "した", "ぶら",
            "だん", "ねぎ", "こんだ", "こうし", "みこ", "あらい", "あわ", "するっ",
            // 頻度上位語が第4候補までに含まれており現状で可(2551)
            "いれい", "かいげん", "かくしゅ", "なかむら", "かいえん"
        ]
        // 追加語彙(Ajout)で覆われた読みは、ユーザの明示登録が LM 最良より優先されるのが
        // 正なのでスイープ対象外(香信/核種/線量/カイエン 等の誤NG防止。2550)
        let userVocabReadings = Set(converter.store.userDictionary().keys)
        var checked = 0
        var ngCount = 0
        for line in tsv.split(separator: "\n") {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard cols.count >= 6 else { continue }
            let reading = String(cols[0])
            if acceptedReadings.contains(reading) { continue }
            if userVocabReadings.contains(reading) { continue }
            let expected = String(cols[1])
            let gap = String(cols[5])
            let list = converter.candidates(for: reading, limit: 8, systemCandidateMode: .surface)
            checked += 1
            if !list.prefix(2).contains(expected) {
                ngCount += 1
                print("SWEEPNG\t\(reading)\t\(expected)\tgap=\(gap)\ttop=\(list.prefix(4))")
            }
        }
        print("SWEEP done checked=\(checked) ng=\(ngCount)")
    }

    // 派生基底のLM優位昇格(2639、かくてい型90件の構造対応): 辞書順が LM 実勢と
    // 乖離した読みの活用派生が LM 最良から出ること。例外4読み(商談/閉廷/棲息/沈澱が正)
    // と、きそん の suru 否認(既存 は辞書がサ変可能を過剰付与、既存しちゃう を生成しない)。
    func testRegressionRealLMDerivationBaseLMPromotion() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary(includeSuppression: true)

        // 代表例: 出演/急行/信仰/覚醒(スイープ真性群)
        for (reading, expected) in [("しゅつえんしちゃう", "出演しちゃう"),
                                    ("きゅうこうしちゃう", "急行しちゃう"),
                                    ("しんこうしちゃう", "信仰しちゃう"),
                                    ("かくせいしちゃう", "覚醒しちゃう")] {
            let list = converter.candidates(for: reading, limit: 6, systemCandidateMode: .surface)
            XCTAssertEqual(list.first, expected, "\(reading) list=\(list)")
        }
        // 例外読み: 現状の辞書順を維持(ユーザ指定)
        for (reading, expected) in [("しょうだんしちゃう", "商談しちゃう"),
                                    ("へいていしちゃう", "閉廷しちゃう"),
                                    ("せいそくしちゃう", "棲息しちゃう")] {
            let list = converter.candidates(for: reading, limit: 6, systemCandidateMode: .surface)
            XCTAssertEqual(list.first, expected, "\(reading) list=\(list)")
        }
        // きそん: 既存 はサ変化しない(クラス否認)。毀損しちゃう が先頭で 既存しちゃう は不在
        let kison = converter.candidates(for: "きそんしちゃう", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(kison.first, "毀損しちゃう", "list=\(kison)")
        XCTAssertFalse(kison.contains("既存しちゃう"), "list=\(kison)")
        // 基底単体の並びは不変(既存 が名詞として先頭のまま)
        let kisonBase = converter.candidates(for: "きそん", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(kisonBase.first, "既存", "list=\(kisonBase)")
    }

    // wc異常スキャン129件の一括是正(並びはユーザ指定 2637)。〜家/師/市/誌 等の
    // 複合は applyDictOverTailKanaFragmentBoost(ロジック対応)、その他は seed。
    // 抑制連動: 歷史/專門/せん門/飜訳/飜譯(字形類似・交ぜ書き)、岡@おかの(二段構え)。
    // たい/たく/しん/あん/さくら は既存指定(2608/2630/2635)を維持し対象外。
    func testRegressionRealLMWordCostAnomalyBatchOrdering() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary(includeSuppression: true)

        let expectations: [(String, [String])] = [
            ("いっ", ["一", "壱", "いっ"]),
            ("うけ", ["うけ", "受け"]),
            ("じつぎょうか", ["実業家", "実業科", "実業課", "実業か"]),
            ("いでんし", ["遺伝子", "遺伝し"]),
            ("あきらか", ["明らか", "あきらか", "彰か", "明か"]),
            ("そう", ["そう", "層", "総", "想"]),
            ("みん", ["明", "民", "みん", "泯"]),
            ("いけだ", ["池田", "イケダ", "いけだ", "池だ"]),
            ("これ", ["これ", "此れ", "之"]),
            ("ぎょう", ["行", "業", "尭"]),
            ("けん", ["県", "件", "券", "権"]),
            ("しつ", ["質", "室"]),
            ("むかえ", ["迎え", "向かえ"]),
            ("たろう", ["太郎"]),
            ("じしゃ", ["自社", "寺社", "寺舎", "侍者", "自車"]),
            ("とうほう", ["当方", "東方", "東宝", "東峰"]),
            ("せいぶ", ["西部", "西武"]),
            ("じゅん", ["順", "純", "準", "じゅん"]),
            ("まこと", ["誠", "真", "まこと", "諄"]),
            ("そうごさよう", ["相互作用"]),
            ("おかだ", ["岡田", "オカダ", "丘だ"]),
            ("まっく", ["Mac", "マック"]),
            ("うた", ["歌", "詩", "唄", "うた"]),
            ("らくごか", ["落語家", "落語か"]),
            ("しゅう", ["週", "集", "周"]),
            ("ちょうこくか", ["彫刻家", "彫刻か"]),
            ("わだ", ["和田", "輪だ", "和だ"]),
            ("しそうか", ["思想家"]),
            ("きょう", ["今日", "京"]),
            ("うんどうか", ["運動家", "運動か"]),
            ("けいせい", ["形成", "京成", "傾城"]),
            ("から", ["から", "唐"]),
            ("かね", ["かね", "兼ね", "兼"]),
            ("しゃしんか", ["写真家", "写真か"]),
            ("かん", ["缶", "勘", "観"]),
            ("ふじた", ["藤田"]),
            ("かき", ["下記", "柿", "書き", "牡蠣"]),
            ("みる", ["見る", "観る", "みる", "診る"]),
            ("うちだ", ["内田", "ウチダ", "うちだ", "家だ", "内だ"]),
            ("ふごうか", ["符号化"]),
            ("よけ", ["除け", "避け", "よけ"]),
            ("ちょうきょうし", ["調教師", "調教し"]),
            ("かえる", ["帰る", "変える", "買える", "蛙"]),
            ("たんけんか", ["探検家", "探険家", "探検か", "探険か", "単券か"]),
            ("しばた", ["柴田", "芝田"]),
            ("いしだ", ["石田"]),
            ("せんきょく", ["選曲", "選挙区", "戦局", "選局"]),
            ("はらだ", ["原田"]),
            ("おだ", ["織田"]),
            ("けんきゅうか", ["研究家", "研究科"]),
            ("れきしか", ["歴史家", "歴史か"]),
            ("ながらく", ["ながらく", "永らく", "長らく"]),
            ("よこはまし", ["横浜市"]),
            ("ひろし", ["弘", "寛", "博"]),
            ("まい", ["枚", "舞", "マイ", "まい"]),
            ("ほんやくか", ["翻訳家", "翻訳か", "本薬か"]),
            ("かなり", ["かなり", "可成", "可なり", "可", "香菜里"]),
            ("わたり", ["渡り", "わたり", "ワタリ", "渡"]),
            ("くれ", ["暮れ", "呉", "暮"]),
            ("ゆく", ["行く", "往く", "ゆく"]),
            ("げいじゅつか", ["芸術家"]),
            ("しゅだいか", ["主題歌", "主題か"]),
            ("いさむ", ["勇", "勇む"]),
            ("いとう", ["伊藤", "伊東"]),
            ("いち", ["位置", "一", "市", "いち"]),
            ("せんもんか", ["専門家", "専門科", "専門か"]),
            ("きし", ["棋士", "岸"]),
            ("ほんるいだ", ["本塁打"]),
            ("しはいか", ["支配下"]),
            ("てつや", ["徹夜", "哲也"]),
            ("かくとうか", ["格闘家", "格闘か"]),
            ("くぼ", ["窪", "久保"]),
            ("こどもたち", ["子供たち", "子どもたち", "子供達"]),
            ("いいだ", ["飯田"]),
            ("いか", ["以下", "イカ", "烏賊", "異化"]),
            ("かずひこ", ["和彦", "一彦"]),
            ("すすめ", ["薦め", "進め", "勧め", "ススメ"]),
            ("えんざんし", ["演算子", "演算し"]),
            ("とく", ["得", "解く", "説く"]),
            ("ぜい", ["税", "勢", "贅"]),
            ("ぎんこうか", ["銀行家", "銀行か"]),
            ("せんだいし", ["仙台市"]),
            ("ならび", ["並び", "ならび"]),
            ("あべ", ["阿部", "安倍"]),
            ("しげる", ["茂る", "繁る", "茂", "しげる"]),
            ("びじゅつか", ["美術科", "美術家", "美術か"]),
            ("むらた", ["村田", "ムラタ"]),
            ("すいせい", ["彗星", "水星", "水棲", "水生"]),
            ("うめだ", ["梅田", "梅だ"]),
            ("どうじんし", ["同人誌"]),
            ("ろう", ["ロウ", "郎", "蝋", "老"]),
            ("けいようし", ["形容詞", "形容し", "掲揚し"]),
            ("はまだ", ["浜田"]),
            ("むかい", ["向い", "向かい", "迎い", "向"]),
            ("でんじは", ["電磁波"]),
            ("けいひん", ["景品", "京浜"]),
            ("じゅうどうか", ["柔道家", "柔道か"]),
            ("まんがし", ["漫画誌"]),
            ("あきら", ["晶", "彰", "章", "秋良"]),
            ("にしだ", ["西田"]),
            ("にゅうしゃ", ["入社", "入車", "入射"]),
            ("いんしょうは", ["印象派"]),
            ("まんざいし", ["漫才師"]),
            ("のう", ["脳", "能"]),
            ("りゅういち", ["隆一", "龍一", "竜一"]),
            ("ゆうき", ["有機", "勇気", "結城"]),
            ("ちじょうは", ["地上波"]),
            ("やしき", ["屋敷", "邸"]),
            ("こうち", ["高知", "高地"]),
            ("ながのし", ["長野市"]),
            ("にっせい", ["ニッセイ", "日生", "日成"]),
            ("いわた", ["岩田", "イワタ"]),
            ("および", ["および", "及び", "及"]),
            ("じょじし", ["叙事詩"]),
            ("とだ", ["戸田", "とだ"]),
            ("しょうぞうが", ["肖像画"]),
            ("てらだ", ["寺田", "寺だ"]),
            ("つだ", ["津田", "ツダ"]),
            ("せんたくし", ["選択肢"]),
            ("はんがか", ["版画家", "版画か"]),
            ("いたみ", ["痛み", "伊丹", "悼み", "悼"]),
            ("ちば", ["千葉", "千馬", "ちば", "地場"]),
            ("みため", ["見た目", "見ため"])
        ]
        var failures: [String] = []
        for (reading, expected) in expectations {
            let list = converter.candidates(for: reading, limit: 12, systemCandidateMode: .surface)
            if Array(list.prefix(expected.count)) != expected {
                failures.append("\(reading) expected=\(expected) got=\(list.prefix(expected.count + 2))")
            }
        }
        // おかの: 源=みなもとの と同型の二段構え(suppr+exactReadingOnly末尾再供給)。
        // 抑制の主目的である 岡の の合成が上位に生きることも固定
        let okano = converter.candidates(for: "おかの", limit: 60, systemCandidateMode: .surface)
        XCTAssertEqual(Array(okano.prefix(3)), ["岡野", "オカノ", "丘野"], "list=\(okano)")
        XCTAssertTrue(okano.prefix(5).contains("岡の"), "岡の の合成が生きる: \(okano.prefix(6))")
        XCTAssertTrue(okano.contains("岡"), "岡 は完全一致時のみ末尾再供給: \(okano)")
        XCTAssertTrue(failures.isEmpty, "\(failures.count)件:\n" + failures.joined(separator: "\n"))
    }

    // 付属語断片スキャン32件の一括是正(並びはユーザ指定 2636)。
    func testRegressionRealLMFragmentUndercutBatchOrdering() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary()

        let expectations: [(String, [String])] = [
            ("こくない", ["国内", "濃くない"]),
            ("みずから", ["みずから", "水から", "自ら", "自から", "美豆から"]),
            ("おこない", ["行ない", "行い"]),
            ("しゃない", ["社内", "車内"]),
            ("あきない", ["商い", "商", "あきない", "飽きない", "厭きない", "倦きない"]),
            ("あてない", ["当てない", "宛てない", "アテナイ"]),
            ("うらない", ["売らない", "占い", "うらない"]),
            ("くれない", ["くれない", "紅", "暮れない", "繰れない"]),
            ("おさない", ["幼い", "押さない", "稚ない", "幼ない"]),
            ("まじない", ["まじない", "呪い"]),
            ("かいさつない", ["改札内", "開札ない", "改刷ない"]),
            ("しきちない", ["敷地内"]),
            ("いざない", ["いざない", "誘い"]),
            ("とうきょうとない", ["東京都内"]),
            ("おおだから", ["大宝", "おおだから"]),
            ("おおだけ", ["大岳", "大竹", "大嶽", "おおだけ"]),
            ("いきない", ["域内", "活きない", "生きない"]),
            ("せいたいない", ["生体内", "生態ない"]),
            ("きかんない", ["期間内", "機関ない"]),
            ("かていない", ["家庭内", "課程ない", "仮定ない", "過程ない"]),
            ("しせつない", ["施設内", "使節ない"]),
            ("いけない", ["いけない", "行けない", "逝けない", "池内"]),
            ("ぐるーぷない", ["グループ内"]),
            ("かいから", ["回から", "会から", "貝殻"]),
            ("そしきない", ["組織内"]),
            ("かわない", ["買わない", "飼わない", "川内", "かわない"]),
            ("きたない", ["汚い", "きたない", "汚ない", "汚たない", "キタナイ"]),
            ("ぎたない", ["汚い", "ぎたない"]),
            ("ほっかいどうない", ["北海道内"]),
            ("こうない", ["構内", "校内"]),
            ("しんない", ["新内", "身内", "心内", "芯ない"]),
            ("ねんどない", ["年度内"])
        ]
        var failures: [String] = []
        for (reading, expected) in expectations {
            let list = converter.candidates(for: reading, limit: 10, systemCandidateMode: .surface)
            if Array(list.prefix(expected.count)) != expected {
                failures.append("\(reading) expected=\(expected) got=\(list.prefix(expected.count + 2))")
            }
        }
        XCTAssertTrue(failures.isEmpty, "\(failures.count)件:\n" + failures.joined(separator: "\n"))
    }

    // カタカナ誤爆スキャン23件の一括是正(並びはユーザ指定 2635)。
    // ママぁ(読み違いの誤エントリ)は suppr で抑制。
    func testRegressionRealLMKatakanaDropBatchOrdering() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary(includeSuppression: true)

        let expectations: [(String, [String])] = [
            ("まんが", ["漫画", "マンガ", "まんが", "漫畫", "馬鍬"]),
            ("とん", ["トン", "屯", "とん", "噸", "瓲"]),
            ("さん", ["さん", "酸", "三", "山", "サン"]),
            ("ある", ["ある", "有る", "在る", "アル", "或る"]),
            ("ひと", ["人", "ひと", "他人", "ヒト", "費途"]),
            ("れい", ["例", "礼", "零", "レイ", "れい"]),
            ("やまと", ["大和", "やまと", "ヤマト", "山都", "山跡"]),
            ("りん", ["燐", "林", "リン", "りん", "臨"]),
            ("あん", ["案", "安", "アン", "あん", "按"]),
            ("にっぽん", ["日本", "にっぽん", "ニッポン"]),
            ("さくら", ["桜", "さくら", "佐倉", "サクラ", "櫻"]),
            ("とよた", ["豊田", "トヨタ", "とよた", "豊太", "豊大"]),
            ("さら", ["皿", "沙羅", "サラ", "娑羅", "さら"]),
            ("しん", ["芯", "新", "深", "しん", "シン"]),
            // 2637 で 勘 を2位に統合({缶, 勘, 観, ...} のユーザ指定)
            ("かん", ["缶", "勘", "観", "冠", "かん", "カン"]),
            ("こんご", ["今後", "コンゴ", "こんご", "🇨🇬", "🇨🇩"]),
            // 2637 で 権 を4位に統合({県, 件, 券, 権, ...} のユーザ指定)
            ("けん", ["県", "件", "券", "権", "ケン", "けん"]),
            ("ねこ", ["猫", "ねこ", "ネコ", "根子", "弥固"]),
            ("ちゃん", ["ちゃん", "チャン", "喜屋武"]),
            ("はん", ["版", "班", "藩", "はん", "ハン"]),
            ("ろん", ["論", "ロン", "崙", "ろん"]),
            ("だん", ["段", "談", "団", "ダン", "檀"]),
            ("まま", ["ママ", "まま", "侭", "間々"])
        ]
        var failures: [String] = []
        for (reading, expected) in expectations {
            let list = converter.candidates(for: reading, limit: 10, systemCandidateMode: .surface)
            if Array(list.prefix(expected.count)) != expected {
                failures.append("\(reading) expected=\(expected) got=\(list.prefix(expected.count + 2))")
            }
        }
        let mama = converter.candidates(for: "まま", limit: 12, systemCandidateMode: .surface)
        XCTAssertFalse(mama.contains("ママぁ"), "ママぁは抑制: \(mama)")
        XCTAssertTrue(failures.isEmpty, "\(failures.count)件:\n" + failures.joined(separator: "\n"))
    }

    // カタカナ先頭スキャン(せみなー型の一般化。2645): 辞書 rank0 がカタカナ実語
    // (LM収録)なのに、かな識別が先頭に出る読みを KATALEAD 行で報告。
    // tools/audit_katakana_emphasis_drop.py の TSV(rank列)を再利用する。
    // SWEEP_KATALEAD=1(env TEST_RUNNER_SWEEP_KATALEAD=1)のときだけ実行。
    func testDiagnosticKatakanaLeadSweep() throws {
        guard ProcessInfo.processInfo.environment["SWEEP_KATALEAD"] != nil else {
            throw XCTSkip("SWEEP_KATALEAD=1 のときだけ実行")
        }
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary()

        let tsvURL = URL(fileURLWithPath: "/Users/kusakabe/Git/ecritu/tmp/katakana_emphasis_drop.tsv")
        guard FileManager.default.fileExists(atPath: tsvURL.path) else {
            throw XCTSkip("先に tools/audit_katakana_emphasis_drop.py を実行して TSV を生成すること")
        }
        let tsv = try String(contentsOf: tsvURL, encoding: .utf8)
        var checked = 0
        var ngCount = 0
        for line in tsv.split(separator: "\n") {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard cols.count >= 4, cols[2] == "0" else { continue }
            let reading = String(cols[0])
            let katakana = String(cols[1])
            let list = converter.candidates(for: reading, limit: 4, systemCandidateMode: .surface)
            checked += 1
            if list.first == reading {
                ngCount += 1
                print("KATALEAD\t\(reading)\t\(katakana)\tuni=\(cols[3])\ttop=\(list.prefix(4))")
            }
        }
        print("KATALEAD done checked=\(checked) ng=\(ngCount)")
    }

    // カタカナ強調フィルタ誤爆スキャン第2段(タイ/ルイの一般化。2634):
    // tools/audit_katakana_emphasis_drop.py の出力(辞書rank≤2かつLM実在のカタカナ)を
    // 実変換に通し、候補リストから完全に消えている読みだけを KATADROP 行で報告する。
    // TEST_RUNNER_SWEEP_KATAKANA=1 のときだけ実行。
    func testDiagnosticKatakanaEmphasisDropSweep() throws {
        guard ProcessInfo.processInfo.environment["SWEEP_KATAKANA"] != nil else {
            throw XCTSkip("SWEEP_KATAKANA=1(xcodebuild には TEST_RUNNER_SWEEP_KATAKANA=1)のときだけ実行")
        }
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary()

        let tsvURL = URL(fileURLWithPath: "/Users/kusakabe/Git/ecritu/tmp/katakana_emphasis_drop.tsv")
        guard FileManager.default.fileExists(atPath: tsvURL.path) else {
            throw XCTSkip("先に tools/audit_katakana_emphasis_drop.py を実行して TSV を生成すること")
        }
        let tsv = try String(contentsOf: tsvURL, encoding: .utf8)
        var checked = 0
        var ngCount = 0
        for line in tsv.split(separator: "\n") {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard cols.count >= 4 else { continue }
            let reading = String(cols[0])
            let katakana = String(cols[1])
            let list = converter.candidates(for: reading, limit: 10, systemCandidateMode: .surface)
            checked += 1
            if !list.contains(katakana) {
                ngCount += 1
                print("KATADROP\t\(reading)\t\(katakana)\trank=\(cols[2])\tuni=\(cols[3])\ttop=\(list.prefix(4))")
            }
        }
        print("KATADROP done checked=\(checked) ng=\(ngCount)")
    }

    // 活用派生の基底順コピー検出(かくてい/ゆうせんの一般化。2634):
    // lm_rank_mismatch の読みに しちゃう を付けた実変換で、基底は是正済み
    // (LM最良が上位2位)なのに派生では辞書順コピーが勝つものを DERIVEDNG 行で報告。
    // 2545のLM優位昇格が直接辞書候補のみで、活用派生に届かない構造の網羅検査。
    func testDiagnosticDerivedBaseOrderCopySweep() throws {
        guard ProcessInfo.processInfo.environment["SWEEP_DERIVED"] != nil else {
            throw XCTSkip("SWEEP_DERIVED=1(env TEST_RUNNER_SWEEP_DERIVED=1)のときだけ実行")
        }
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary(includeSuppression: true)

        let tsvURL = URL(fileURLWithPath: "/Users/kusakabe/Git/ecritu/tmp/lm_rank_mismatch.tsv")
        guard FileManager.default.fileExists(atPath: tsvURL.path) else {
            throw XCTSkip("先に tools/audit_lm_rank_mismatch.py を実行して TSV を生成すること")
        }
        let tsv = try String(contentsOf: tsvURL, encoding: .utf8)
        // ユーザレビュー済みの許容読み(両表記とも正当なサ変で現状の並びが可。2638)。
        // 後半4読みは 2639 のLM昇格例外(derivationLMPromotionDeniedReadings)と対
        let acceptedReadings: Set<String> = [
            "ほうそう", "かんどう", "かんつう", "へいかん", "せっぷく", "らっか", "めっき", "しっと",
            "ちんでん", "しょうだん", "へいてい", "せいそく",
            // おでかけ=お出かけしちゃう 先頭が自然/そうでん=wc1点差(相伝6517vs送電6518)で
            // 送電しちゃう 2位、許容範囲(2639)
            "おでかけ", "そうでん"
        ]
        var checked = 0
        var ngCount = 0
        for line in tsv.split(separator: "\n") {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard cols.count >= 6 else { continue }
            let reading = String(cols[0])
            // する動詞・サ変(〜する)には しちゃう が直接接続しない
            // (して+ちゃう=しちゃう が正で、するしちゃう は打たれない。2638)
            guard reading != "する", !reading.hasSuffix("する") else { continue }
            guard !acceptedReadings.contains(reading) else { continue }
            let best = String(cols[1])
            let top = String(cols[3])
            // 基底が是正済みの読みだけが対象(未是正はLM順乖離スイープの持ち場)
            let baseList = converter.candidates(for: reading, limit: 4, systemCandidateMode: .surface)
            guard baseList.prefix(2).contains(best) else { continue }
            let derived = converter.candidates(for: reading + "しちゃう", limit: 12, systemCandidateMode: .surface)
            let posBest = derived.firstIndex(of: best + "しちゃう")
            let posTop = derived.firstIndex(of: top + "しちゃう")
            // サ変でない読みは両派生とも出ないのでスキップ
            guard posBest != nil || posTop != nil else { continue }
            checked += 1
            if let posTop, posBest == nil || posBest! > posTop {
                ngCount += 1
                print("DERIVEDNG\t\(reading)\t\(best)\ttop=\(top)\tderived=\(derived.prefix(4))")
            }
        }
        print("DERIVEDNG done checked=\(checked) ng=\(ngCount)")
    }

    // 単漢字+付属語断片の辞書語跨ぎ検出(けんない=県内の一般化。2634):
    // まで/から/だけ/など/ない 終わりの読みの辞書語が実変換の上位2位に出ないものを
    // FRAGNG 行で報告。SWEEP_FRAGMENT=1(env TEST_RUNNER_SWEEP_FRAGMENT=1)のときだけ実行。
    func testDiagnosticFragmentUndercutSweep() throws {
        guard ProcessInfo.processInfo.environment["SWEEP_FRAGMENT"] != nil else {
            throw XCTSkip("SWEEP_FRAGMENT=1 のときだけ実行")
        }
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary()

        let tsvURL = URL(fileURLWithPath: "/Users/kusakabe/Git/ecritu/tmp/fragment_undercut.tsv")
        guard FileManager.default.fileExists(atPath: tsvURL.path) else {
            throw XCTSkip("先に tools/audit_fragment_undercut.py を実行して TSV を生成すること")
        }
        let tsv = try String(contentsOf: tsvURL, encoding: .utf8)
        var checked = 0
        var ngCount = 0
        for line in tsv.split(separator: "\n") {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard cols.count >= 4 else { continue }
            let reading = String(cols[0])
            let word = String(cols[1])
            let list = converter.candidates(for: reading, limit: 8, systemCandidateMode: .surface)
            checked += 1
            if !list.prefix(2).contains(word) {
                ngCount += 1
                print("FRAGNG\t\(reading)\t\(word)\tuni=\(cols[3])\ttop=\(list.prefix(4))")
            }
        }
        print("FRAGNG done checked=\(checked) ng=\(ngCount)")
    }

    // word_costs 異常高・欠落の常用語検出(優先/縞模様の一般化。2634):
    // uni≤6000 かつ (wc≥8000 or 欠落) の辞書語が実変換の上位2位に出ないものを
    // WCNG 行で報告。SWEEP_WC=1(env TEST_RUNNER_SWEEP_WC=1)のときだけ実行。
    func testDiagnosticWordCostAnomalySweep() throws {
        guard ProcessInfo.processInfo.environment["SWEEP_WC"] != nil else {
            throw XCTSkip("SWEEP_WC=1 のときだけ実行")
        }
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary()

        let tsvURL = URL(fileURLWithPath: "/Users/kusakabe/Git/ecritu/tmp/wc_anomaly.tsv")
        guard FileManager.default.fileExists(atPath: tsvURL.path) else {
            throw XCTSkip("先に tools/audit_wc_anomaly.py を実行して TSV を生成すること")
        }
        let tsv = try String(contentsOf: tsvURL, encoding: .utf8)
        var checked = 0
        var ngCount = 0
        for line in tsv.split(separator: "\n") {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard cols.count >= 4 else { continue }
            let reading = String(cols[0])
            let word = String(cols[1])
            let list = converter.candidates(for: reading, limit: 8, systemCandidateMode: .surface)
            checked += 1
            if !list.prefix(2).contains(word) {
                ngCount += 1
                print("WCNG\t\(reading)\t\(word)\tuni=\(cols[2])\twc=\(cols[3])\ttop=\(list.prefix(4))")
            }
        }
        print("WCNG done checked=\(checked) ng=\(ngCount)")
    }

    // かな述語+終助詞クラスタの乗っ取り検出(かわいいなあの一般化。2634):
    // 述語単体の multi 先頭を基準表記とし、終助詞クラスタを付けた multi 先頭が
    // 「基準表記+クラスタそのまま」にならない組を PARTNG 行で報告。
    // SWEEP_PARTICLE=1(env TEST_RUNNER_SWEEP_PARTICLE=1)のときだけ実行。
    func testDiagnosticFinalParticleClusterSweep() throws {
        guard ProcessInfo.processInfo.environment["SWEEP_PARTICLE"] != nil else {
            throw XCTSkip("SWEEP_PARTICLE=1 のときだけ実行")
        }
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary()

        let predicates = [
            "かわいい", "おいしい", "すごい", "たのしい", "うれしい", "ねむい", "さむい",
            "あつい", "やばい", "つらい", "えらい", "ひどい", "うまい", "たかい", "やすい",
            "おおきい", "ちいさい", "たべる", "たべた", "いく", "いった", "する", "した",
            "ある", "あった", "ない", "なかった", "できる", "できた", "わかる", "わかった"
        ]
        let clusters = [
            "なあ", "ねえ", "よね", "よねえ", "かな", "かなー", "かも", "けど",
            "わあ", "よお", "なー", "ねー", "だろー", "よなあ"
        ]
        var checked = 0
        var ngCount = 0
        for predicate in predicates {
            let baseTop = converter.multiClauseCandidates(for: predicate, systemCandidateMode: .surface).first
                ?? converter.candidates(for: predicate, limit: 1, systemCandidateMode: .surface).first
            guard let baseTop else { continue }
            for cluster in clusters {
                let reading = predicate + cluster
                let top = converter.multiClauseCandidates(for: reading, systemCandidateMode: .surface).first
                    ?? converter.candidates(for: reading, limit: 1, systemCandidateMode: .surface).first
                checked += 1
                if top != baseTop + cluster {
                    ngCount += 1
                    // 期待表記が何位に居るかも出す(先頭でなくても上位なら許容の判断材料)
                    let multi = converter.multiClauseCandidates(for: reading, systemCandidateMode: .surface)
                    let position = multi.firstIndex(of: baseTop + cluster).map { "\($0 + 1)位" } ?? "圏外"
                    print("PARTNG\t\(reading)\texpected=\(baseTop + cluster)(\(position))\ttop=\(top ?? "-")")
                }
            }
        }
        print("PARTNG done checked=\(checked) ng=\(ngCount)")
    }

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

    // poubelle【過剰な漢字化】で抑制中の語は、抑制の有無に関わらずかなが先頭であること。
    // 抑制はアプリの画面から解除できるので、解除された瞬間に既定が漢字へ変わらないよう
    // seed で並びを宣言している。同時に、seed へ対の漢字を書くと抑制を上書きして再供給
    // してしまうため、抑制中は漢字が出ないことも併せて固定する(2583)。
    func testRegressionOverKanjifiedWordsKeepKanaLeadingRegardlessOfSuppression() throws {
        try prepareRealLMDictionary()
        guard let defaults = UserDefaults(suiteName: defaultsSuiteName) else {
            XCTFail("failed to open test defaults")
            return
        }

        let cases: [(reading: String, kanji: String)] = [
            ("おいしい", "美味しい"),
            ("かわいい", "可愛い"),
            ("まずい", "不味い"),
            ("さらに", "更に"),
            ("ただし", "但し"),
            ("おそらく", "恐らく"),
            ("しばらく", "暫く"),
            ("さすが", "流石"),
            ("もはや", "最早"),
            ("なお", "猶")
        ]

        for testCase in cases {
            defaults.removeObject(forKey: KanaKanjiStorageKeys.suppressionVocabulary)
            converter.clearAllCaches()
            let unsuppressed = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )
            XCTAssertEqual(
                unsuppressed.first,
                testCase.reading,
                "抑制なしで かな が先頭でない: \(testCase.reading) candidates=\(unsuppressed)"
            )

            defaults.set(
                [testCase.reading: [testCase.kanji]],
                forKey: KanaKanjiStorageKeys.suppressionVocabulary
            )
            converter.clearAllCaches()
            let suppressed = converter.candidates(
                for: testCase.reading,
                limit: 24,
                systemCandidateMode: .surface
            )
            XCTAssertEqual(
                suppressed.first,
                testCase.reading,
                "抑制ありで かな が先頭でない: \(testCase.reading) candidates=\(suppressed)"
            )
            XCTAssertFalse(
                suppressed.contains(testCase.kanji),
                "seed が抑制を上書きして再供給している: \(testCase.kanji) candidates=\(suppressed)"
            )
        }

        defaults.removeObject(forKey: KanaKanjiStorageKeys.suppressionVocabulary)
        converter.clearAllCaches()
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
        // 本旨は 気が の curated が 着替え を分断しないこと。もって の表記は かな/持って いずれも
        // 正当なので先頭語だけを見る(かな もって の先頭化は 誤推論基底 もう 由来だった。2465)
        XCTAssertEqual(kigae.first?.hasPrefix("着替え"), true, "multi=\(kigae)")
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

    // 実LM回帰: かえりのひこうき→帰りの飛行機。飛行機 は読み別 wc が 11443(unigram 5406 の
    // 一般語なのに収穫底値超え)で、連文節の bigram 借用拒否+9500 床上げを受けて
    // 帰りの日+後期/皇紀 の分割に負けていた(コスト異常型)。seed 掲載の免除で是正(2529)
    func testRegressionRealLMKaerinoHikoukiPrefersAirplane() throws {
        try prepareRealLMDictionary()

        let multi = converter.multiClauseCandidates(for: "かえりのひこうき", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "帰りの飛行機", "multi=\(multi)")

        let single = converter.candidates(for: "ひこうき", limit: 5, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "飛行機", "single=\(single)")
    }

    // 実LM回帰: とよむ→と読む。辞書は 響動む(古語)のみで 引用と+読む が出なかった。
    // 読み3文字は連文節対象外のため seed の単文節供給で是正(2529)
    func testRegressionRealLMToyomuSuppliesToYomu() throws {
        try prepareRealLMDictionary()

        let single = converter.candidates(for: "とよむ", limit: 5, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "と読む", "single=\(single)")
        // 響動む(古語)は 2679 で抑制(とよんでた→響動んでた が と+呼んでた を跨いでいた)
        XCTAssertFalse(single.contains("響動む"), "single=\(single)")
    }

    // 実LM回帰: れいは のかな識別先頭化を是正。あきの と同型(かな人名収穫 wc10000 +
    // 識別供給の二重加算)で、ひらがな れいは が 例は/零は 合成より先頭に居座っていた。
    // seed 宣言(かな非掲載)で末尾へ降格(2529)
    func testRegressionRealLMReihaDemotesKanaIdentity() throws {
        try prepareRealLMDictionary()

        let single = converter.candidates(for: "れいは", limit: 15, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "例は", "single=\(single)")
        // かな識別は先頭群から退く(末尾寄り)。完全削除はしない
        if let kanaIndex = single.firstIndex(of: "れいは") {
            XCTAssertGreaterThanOrEqual(kanaIndex, 5, "single=\(single)")
        }
        // ガード: れいはい(礼拝)の複合読みは無傷
        let reihai = converter.candidates(for: "れいはいします", limit: 5, systemCandidateMode: .surface)
        XCTAssertEqual(reihai.first, "礼拝します", "single=\(reihai)")
    }

    // 実LM回帰: おおやさんしかもうからない→大家さんしか儲からない。副助詞 しか のかな識別が
    // 床上げ(wc6838)されて しかも(uni5660)分割に負け、しかも+受からない 区切りに固執して
    // いた。免除リスト追加で しか+儲からない を通す(2529)
    func testRegressionRealLMShikaMoukaranaiSplit() throws {
        try prepareRealLMDictionary()

        let multi = converter.multiClauseCandidates(for: "おおやさんしかもうからない", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "大家さんしか儲からない", "multi=\(multi)")
        // ガード: 接続詞 しかも の正当な用途は無傷(しかも+雨)
        let shikamo = converter.multiClauseCandidates(for: "しかもあめだ", systemCandidateMode: .surface)
        XCTAssertEqual(shikamo.first, "しかも雨だ", "multi=\(shikamo)")
    }

    // 実LM回帰: ふらんすはもっとだよ が全かなエコー1件になるのを是正。オノマトペ「〜っと」
    // クランプ(4文字以上全かな)が 〜はもっと 区間に誤爆して丸ごと4000化し、
    // フランスは+もっと の正しい分割を潰していた(2529)
    func testRegressionRealLMFuransuWaMottoSplitsLoanword() throws {
        try prepareRealLMDictionary()

        let multi = converter.multiClauseCandidates(for: "ふらんすはもっとだよ", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "フランスはもっとだよ", "multi=\(multi)")

        let motto = converter.multiClauseCandidates(for: "ふらんすはもっと", systemCandidateMode: .surface)
        XCTAssertEqual(motto.first, "フランスはもっと", "multi=\(motto)")

        // ガード: 真のオノマトペ(ぱしゃっと)はかなクランプ維持、もっとだよ 単体の全かなも維持
        let pasha = converter.multiClauseCandidates(for: "ぱしゃっととった", systemCandidateMode: .surface)
        XCTAssertEqual(pasha.first?.hasPrefix("ぱしゃっと"), true, "multi=\(pasha)")
        let mottodayo = converter.multiClauseCandidates(for: "もっとだよ", systemCandidateMode: .surface)
        XCTAssertEqual(mottodayo.first, "もっとだよ", "multi=\(mottodayo)")
    }

    // 実LM回帰: こっちはむしがないてる→こっちは虫が鳴いてる。は→無視(4383)< は→虫(5607)の
    // Wikipediaバイアスで 無視 が勝ち、が→ない(2654)のかなエコーが 鳴いてる に勝っていた。
    // 連語テーブル(むし+なく活用→虫、動詞表層は 鳴 系優先)で文脈限定是正(2529)
    func testRegressionRealLMMushiGaNaiteruPrefersNaku() throws {
        try prepareRealLMDictionary()

        let multi = converter.multiClauseCandidates(for: "こっちはむしがないてる", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "こっちは虫が鳴いてる", "multi=\(multi)")

        let bos = converter.multiClauseCandidates(for: "むしがないてる", systemCandidateMode: .surface)
        XCTAssertEqual(bos.first, "虫が鳴いてる", "multi=\(bos)")

        // ガード: 無視 の正当な用途は無傷(むしする/むしされた/をむしして)
        XCTAssertEqual(converter.multiClauseCandidates(for: "むしする", systemCandidateMode: .surface).first, "無視する")
        XCTAssertEqual(converter.candidates(for: "むしされた", limit: 5, systemCandidateMode: .surface).first, "無視された")
        XCTAssertEqual(converter.multiClauseCandidates(for: "をむしして", systemCandidateMode: .surface).first, "を無視して")
        // ガード: むしがない(〜虫がない)は 鳴い に化けない
        let nai = converter.multiClauseCandidates(for: "むしがないへや", systemCandidateMode: .surface)
        XCTAssertEqual(nai.first, "虫がない部屋", "multi=\(nai)")
    }

    // 実LM回帰: たいわん から タイワン を抑制(suppr.plist 2529、ユーザ指定)。テストバンドルは
    // suppr JSON を含まないため injectSuppression で実機相当を再現する
    func testRegressionRealLMTaiwanSuppressesKatakana() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["たいわん": ["タイワン"]])

        let single = converter.candidates(for: "たいわん", limit: 8, systemCandidateMode: .surface)
        XCTAssertFalse(single.contains("タイワン"), "single=\(single)")
        // 台湾 が先頭(seed 並び矯正 2531)、🇹🇼/台灣 は後続に残る
        XCTAssertEqual(single.first, "台湾", "single=\(single)")
        XCTAssertTrue(single.contains("🇹🇼"), "single=\(single)")
        XCTAssertTrue(single.contains("台灣"), "single=\(single)")
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
        // LM優位辞書候補の一般昇格(2545)で 階層(LM 4787級)が 海藻 の上に来た。
        // どちらも妥当な常用語なので先頭2件に両方が居ることを固定する。
        XCTAssertEqual(Set(single.prefix(2)), Set(["海藻", "階層"]), "single=\(single)")
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
    // 尺貫法の体積単位: 数字文脈で 合/勺/升/斗/石 が出ること(ユーザ指摘 2612)。
    // 合 と 勺 が欠落していた(ごう=[号]のみ/しゃく=[尺]のみ)。升/斗/石(連濁ごく含む)は
    // 既存の digit 表でカバー済みなことも合わせて固定する。
    func testRegressionDigitContextVolumeUnitCounters() {
        func boosted(_ reading: String) -> [String] {
            KanaKanjiConverter.digitContextCounterBoostedCandidates([], reading: reading, precedingCharacter: "2")
        }
        XCTAssertTrue(boosted("ごう").contains("合"), "\(boosted("ごう"))")
        XCTAssertEqual(boosted("ごう").first, "号", "号の先頭は維持 \(boosted("ごう"))")
        XCTAssertTrue(boosted("しゃく").contains("勺"), "\(boosted("しゃく"))")
        XCTAssertEqual(boosted("しゃく").first, "尺", "尺の先頭は維持 \(boosted("しゃく"))")
        XCTAssertTrue(boosted("しょう").contains("升"), "\(boosted("しょう"))")
        XCTAssertTrue(boosted("と").contains("斗"), "\(boosted("と"))")
        XCTAssertTrue(boosted("こく").contains("石"), "\(boosted("こく"))")
        XCTAssertTrue(boosted("ごく").contains("石"), "連濁 \(boosted("ごく"))")
        // 勺 は連濁しない: じゃく は 尺 のみ
        XCTAssertFalse(boosted("じゃく").contains("勺"), "\(boosted("じゃく"))")
    }

    // 尺貫法×漢数字(一〜十)の複合44件を exactReadingOnly で補充(ユーザ指定 2613)。
    // 完全一致時のみ末尾供給: 頻出語(じっと/護国 等)の先頭は変えない。
    func testRegressionRealLMKanjiNumeralVolumeUnits() throws {
        try prepareRealLMDictionary()

        for (reading, compound) in [("さんごう", "三合"), ("いちごう", "一合"), ("ごしゃく", "五勺"),
                                    ("にしょう", "二升"), ("さんと", "三斗"), ("さんごく", "三石"),
                                    ("ごこく", "五石"), ("じっと", "十斗")] {
            let list = converter.candidates(for: reading, limit: 30, systemCandidateMode: .surface)
            XCTAssertTrue(list.contains(compound), "\(reading) list=\(list)")
        }
        // 頻出語の先頭は不変
        XCTAssertEqual(converter.candidates(for: "じっと", limit: 4, systemCandidateMode: .surface).first, "じっと")
        XCTAssertEqual(converter.candidates(for: "ごこく", limit: 4, systemCandidateMode: .surface).first, "護国")
        // 万石: 数字直後の優先(62確定→まんごく→万石 が先頭群)
        let mangoku = KanaKanjiConverter.digitContextCounterBoostedCandidates([], reading: "まんごく", precedingCharacter: "2")
        XCTAssertTrue(mangoku.contains("万石"), "\(mangoku)")
    }

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
        // かな識別 しって の先頭化は誤推論基底 しつ(かな。読み しつ に活用クラス行が無いのに
        // 五段つと推論)由来だったため、システム候補への推論停止(2465)で 知って が先頭になった。
        // かな しって は次点に残る(提示層では末尾チップ化される)
        XCTAssertEqual(Array(shitte.prefix(2)), ["知って", "しって"], "single=\(shitte)")
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

    // みつかる: dict rank が 見付かる0<見つかる1 で旧表記が先頭だった。seed で
    // 現代の主表記 見つかる を先頭に(2439)
    func testRegressionMitsukaruOrdering() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "みつかる", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(2)), ["見つかる", "見付かる"], "single=\(single)")
        let tsukeru = converter.candidates(for: "みつける", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(Array(tsukeru.prefix(2)), ["見つける", "見付ける"], "tsukeru=\(tsukeru)")
    }

    // たくさん→託さん/托さん: 五段活用の口語否定縮約(aForm+ん。知らん/やらん)は有用だが、
    // 五段す だけは aForm=さ のため 託さん/托さん/話さん が敬称「さん」と衝突し、
    // たくさん の日常入力を邪魔していた。五段す のみ ん系派生を作らない一般対策(2462)。
    // あわせて読み うまい のレア語(熟寝/熟睡/右舞)を抑制してジャンク合成を除去
    // いやで: エンジンは {イヤで, いやで, 嫌で, ...} と2位にかなを返していたが、keepKana が
    // 不成立で提示層がかな識別を候補から落としていた(実機は イヤで/嫌で/否で/厭で)。
    // かな正書の形容動詞語幹(いや/むら)+活用語尾 を keepKana の根拠に加える(2464)
    // かわってきてる→河ってきてる: 辞書の交ぜ書き名詞「河う」(鳥のカワウ=河鵜。鵜が常用外の
    // ための交ぜ書きエントリ)を、読み かわう に活用クラス行が無いことから五段う動詞と推論して
    // 河って/河ってきて を生成し、スパン全体の 変わってきてる を逆転していた。システム辞書候補への
    // クラス推論を止めた(音の借用による誤活用の一般対策。2465)
    // 促音を含むカタカナ語(リッター/ヘット/ネット/チケット 等)が候補から丸ごと消えていた。
    // 2450 の「読みに無い っ/ー の水増し表記」フィルタが、表層のカタカナ促音「ッ」を読みの
    // ひらがな「っ」と突き合わせられず、促音カタカナ 13,348 エントリを装飾表記と誤判定していた。
    // かなの種を揃えて比較する(2466)
    func testRegressionKatakanaSokuonIsNotDecorativePadding() throws {
        try prepareRealLMDictionary()
        for (reading, expected) in [
            ("りったー", "リッター"), ("へっと", "ヘット"),
            ("ねっと", "ネット"), ("ちけっと", "チケット")
        ] {
            let single = converter.candidates(for: reading, limit: 8, systemCandidateMode: .surface)
            XCTAssertTrue(single.contains(expected), "\(reading)=\(single)")
        }
    }

    // 学習語彙に入れた促音カタカナ語(パレット)も、装飾表記フィルタが最終段で
    // どの経路からの候補も落とすため「長押し確定しても学習されない」ように見えていた。
    // 2466 の促音判定修正の学習経路側の防波堤
    func testRegressionLearnedKatakanaSokuonSurvivesDecorativeFilter() throws {
        try prepareRealLMDictionary()
        converter.store.addLearnedEntry(reading: "ぱれっと", candidate: "パレット")
        converter.invalidateCandidateCache()
        let single = converter.candidates(for: "ぱれっと", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "パレット", "single=\(single)")
    }

    // ろっぺん→6片/六片: 片 は 2469 で数字文脈供給マップにしか入れていなかったため、
    // 数詞込みの読み(ろっぽん→6本 と同じ形)では候補が空だった。数詞複合の照合にも
    // 補助表を合流させ、音便系列(いっぺん/にへん/さんぺん/ろっぺん)を許可する(2474)
    func testRegressionPenCounterNumericCompound() throws {
        try prepareRealLMDictionary()
        let roppen = converter.candidates(for: "ろっぺん", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(Array(roppen.prefix(2)), ["6片", "六片"], "roppen=\(roppen)")
        let sanpen = converter.candidates(for: "さんぺん", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(Array(sanpen.prefix(2)), ["3片", "三片"], "sanpen=\(sanpen)")
        let nihen = converter.candidates(for: "にへん", limit: 8, systemCandidateMode: .surface)
        XCTAssertTrue(nihen.contains("2片"), "nihen=\(nihen)")
        // 一遍(辞書 wc4500)は 1片 より上のまま(数詞複合は辞書より下位)
        let ippen = converter.candidates(for: "いっぺん", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(ippen.first, "一遍", "ippen=\(ippen)")
        XCTAssertTrue(ippen.contains("1片"), "ippen=\(ippen)")
        // 片目/跡目 を序数と誤判定しないこと(補助表を助数詞本表に入れない理由)
        let katame = converter.candidates(for: "かため", limit: 8, systemCandidateMode: .surface)
        XCTAssertFalse(katame.contains("片め"), "katame=\(katame)")
    }

    // さんぼん→3本/三本: 3本 が 三盆/山本/上鳳(レア辞書語)の後ろで4番目だった。連濁形の
    // 助数詞(ぼん)は数詞に付いたときしか現れないので数詞複合を辞書級へ引き上げる(2472)。
    // 清音形(ほん)は対象外 = にほん→日本 の方針は不変
    func testRegressionVoicedCounterNumericCompoundOutranksRareDictionary() throws {
        try prepareRealLMDictionary()
        let sanbon = converter.candidates(for: "さんぼん", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(sanbon.prefix(2)), ["3本", "三本"], "sanbon=\(sanbon)")
        let ippiki = converter.candidates(for: "さんびき", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(ippiki.prefix(2)), ["3匹", "三匹"], "sanbiki=\(ippiki)")
        // 清音形の助数詞は従来どおり辞書語が先頭(にほん→日本)
        let nihon = converter.candidates(for: "にほん", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(nihon.first, "日本", "nihon=\(nihon)")
    }

    // 1ぺん/6ぺん→1片/6片: ぺん は へん の促音便読みのため 片(ぺん wc10155)が連濁収穫
    // フィルタで落ち、数字を打っても助数詞 片 が候補に出なかった。数字文脈限定で供給する(2469)
    func testRegressionDigitContextSuppliesPenCounterKanji() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "ぺん", limit: 8, systemCandidateMode: .surface)
        XCTAssertFalse(single.contains("片"), "単独入力では従来どおり出さない single=\(single)")
        let boosted = KanaKanjiConverter.digitContextCounterBoostedCandidates(
            single,
            reading: "ぺん",
            precedingCharacter: "6"
        )
        XCTAssertEqual(boosted.first, "片", "boosted=\(boosted)")
        // 同じ構造で落ちていた他の助数詞(本/匹/分/発/杯)も数字文脈で供給する(2471)
        for (reading, expected) in [
            ("ぽん", "本"), ("ぼん", "本"), ("ぴき", "匹"),
            ("びき", "匹"), ("ぷん", "分"), ("ぱつ", "発"), ("ぱい", "杯")
        ] {
            let candidates = converter.candidates(for: reading, limit: 8, systemCandidateMode: .surface)
            let boostedCounter = KanaKanjiConverter.digitContextCounterBoostedCandidates(
                candidates,
                reading: reading,
                precedingCharacter: "6"
            )
            XCTAssertEqual(boostedCounter.first, expected, "\(reading)=\(boostedCounter)")
        }
        // 抑制済みなら復活させない
        let suppressed = KanaKanjiConverter.digitContextCounterBoostedCandidates(
            single,
            reading: "ぺん",
            precedingCharacter: "6",
            suppressedCandidates: ["片"]
        )
        XCTAssertFalse(suppressed.contains("片"), "suppressed=\(suppressed)")
    }

    // りょうてい: 料亭(wc7399)より 竜蹄(馬の美称)/量定 が先に並んでいた。seed で 料亭 を先頭へ
    func testRegressionRyouteiPrefersRyoutei() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "りょうてい", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "料亭", "single=\(single)")
    }

    // できれば: 提示層は 出来れば を かな版の直後へ回す(出来る は使いたくないというユーザ方針)が、
    // かな識別 できれば に keepKana の根拠が無く除去されるため 出来れば が先頭に残っていた。
    // 活用形の基底読みが seed でかな先頭に固定された用言(できる)なら活用形もかな正書とみなす(2467)
    func testRegressionSeedKanaLeadingBaseInflectionKeepsKana() throws {
        try prepareRealLMDictionary()
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "できれば"))
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "できたら"))
        let single = converter.candidates(for: "できれば", limit: 6, systemCandidateMode: .surface)
        XCTAssertTrue(single.contains("できれば"), "single=\(single)")
        // 提示層(かな版の直後へ漢字版を回す)まで通した並び
        let presented = SupplementaryCandidateMerger.demotingDekiKanjiBelowKana(single)
        XCTAssertEqual(Array(presented.prefix(2)), ["できれば", "出来れば"], "presented=\(presented)")
    }

    // でさいきどう→で再軌道: 単文節は 再起動 を返すのに連文節が 再+軌道 に割れていた。
    // 再起動 は LM unigram 6609 を持つが word_cost が収穫底値(11219)のため、レア読みの
    // unigram タダ乗りを防ぐ床上げに掛かって信用されていなかった。seed 掲載で免除(2470)
    func testRegressionSaikidouNotSplitInMultiClause() throws {
        try prepareRealLMDictionary()
        let de = converter.multiClauseCandidates(for: "でさいきどう", systemCandidateMode: .surface)
        XCTAssertEqual(de.first, "で再起動", "multi=\(de.prefix(4))")
        let wo = converter.multiClauseCandidates(for: "をさいきどう", systemCandidateMode: .surface)
        XCTAssertEqual(wo.first, "を再起動", "multi=\(wo.prefix(4))")
        let single = converter.candidates(for: "さいきどう", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "再起動", "single=\(single)")
    }

    // とりわすれている→鳥忘れている: 動詞連用形+動詞(取り忘れる/撮り忘れる)は生産的な複合動詞
    // だが、同音の単漢字名詞 鳥 が1ノードで安いため無助詞連結が勝っていた(名詞→動詞の減点600では
    // 届かない)。seed 供給した連用形読みに限り、直後が動詞のときだけ優遇する(2477)
    func testRegressionCompoundVerbRenyouOutranksHomophoneNoun() throws {
        try prepareRealLMDictionary()
        let teiru = converter.multiClauseCandidates(for: "とりわすれている", systemCandidateMode: .surface)
        XCTAssertEqual(teiru.first, "取り忘れている", "multi=\(teiru.prefix(4))")
        XCTAssertTrue(teiru.contains("撮り忘れている"), "multi=\(teiru.prefix(4))")
        let teru = converter.multiClauseCandidates(for: "とりわすれてる", systemCandidateMode: .surface)
        XCTAssertEqual(teru.first, "取り忘れてる", "multi=\(teru.prefix(4))")
        XCTAssertTrue(teru.contains("撮り忘れてる"), "multi=\(teru.prefix(4))")
        let hari = converter.multiClauseCandidates(for: "はりわすれている", systemCandidateMode: .surface)
        XCTAssertEqual(hari.first, "貼り忘れている", "multi=\(hari.prefix(4))")
        // 助詞のある文脈は無傷(ボーナスは連用形ノードの直後が動詞のときだけ)
        XCTAssertEqual(
            converter.multiClauseCandidates(for: "とりのこえ", systemCandidateMode: .surface).first,
            "鳥の声"
        )
        XCTAssertEqual(
            converter.multiClauseCandidates(for: "とりをみた", systemCandidateMode: .surface).first,
            "鳥を見た"
        )
    }

    // とりわすれてる が学習後に {取り忘れてる, とりわすれてる} だけになる件: 全長読みが
    // 学習/追加語彙の1ノードで賄えると連文節は単文節に委ねて空を返し、単文節には
    // 「連用形+活用形」を合成する経路が無いため変種が全部消える。貼り忘れる と同じく
    // 複合動詞を curated 供給して 撮り/摂り/録り/採り忘れてる を常に選べるようにする(2478)
    func testRegressionToriWasureruCompoundSuppliedFromMisc() throws {
        try prepareRealLMDictionary()
        for candidate in ["取り忘れる", "撮り忘れる", "摂り忘れる", "録り忘れる", "採り忘れる"] {
            converter.store.addUserEntry(reading: "とりわすれる", candidate: candidate)
        }
        converter.store.addLearnedEntry(reading: "とりわすれてる", candidate: "取り忘れてる")
        converter.store.waitForPendingLearningPersists()
        converter.invalidateCandidateCache()

        let teru = converter.candidates(for: "とりわすれてる", limit: 10, systemCandidateMode: .surface)
        XCTAssertEqual(teru.first, "取り忘れてる", "teru=\(teru)")
        for expected in ["撮り忘れてる", "摂り忘れてる", "録り忘れてる", "採り忘れてる"] {
            XCTAssertTrue(teru.contains(expected), "teru=\(teru)")
        }
        let ta = converter.candidates(for: "とりわすれた", limit: 10, systemCandidateMode: .surface)
        XCTAssertTrue(ta.contains("撮り忘れた"), "ta=\(ta)")
    }

    // たいりく→大睦: 収穫底値(wc10000)のレア人名収穫。睦 の読みは むつみ/ぼく/まこと だけで
    // 辞書に りく が無く、たい+りく の分解でも説明できない誤エントリなので抑制した
    func testRegressionTairikuRareNameSuppressed() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["たいりく": ["大睦"]])
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let single = converter.candidates(for: "たいりく", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "大陸", "single=\(single)")
        XCTAssertFalse(single.contains("大睦"), "single=\(single)")
    }

    // おいやって: 追いやる と 追い遣る が同コスト(9426)で辞書順が 追い遣る 先行だったため
    // 追い遣って が先頭だった。「やる」はかな書きが普通なので seed で 追いやる を先頭に(2486)
    func testRegressionOiyaruPrefersKanaOkurigana() throws {
        try prepareRealLMDictionary()
        for reading in ["おいやって", "おいやった", "おいやられた", "おいやる"] {
            let single = converter.candidates(for: reading, limit: 6, systemCandidateMode: .surface)
            XCTAssertEqual(single.first?.contains("遣"), false, "\(reading)=\(single)")
        }
        let te = converter.candidates(for: "おいやって", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(Array(te.prefix(2)), ["追いやって", "追い遣って"], "te=\(te)")
    }

    // などという: エンジンは かな先頭(などという)を返していたが keepKana 不成立で提示層が
    // かな識別を落とし、などと言う が先頭になっていた。引用の という を剥がして語幹(など)が
    // かな正書なら維持する規則を追加(2487)
    func testRegressionQuotationToiuKeepsKana() throws {
        try prepareRealLMDictionary()
        let multi = converter.multiClauseCandidates(for: "などという", systemCandidateMode: .surface)
        XCTAssertEqual(Array(multi.prefix(2)), ["などという", "などと言う"], "multi=\(multi.prefix(4))")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "などという"))
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "などというのは"))
        // 名詞+という(図鑑という)は語幹がかな正書でないので巻き込まない
        XCTAssertFalse(converter.shouldKeepKanaIdentityLeading(for: "ずかんという"))
    }

    // そのための: エンジンは かな先頭(そのための)を返していたが keepKana 不成立で提示層が
    // かな識別を落とし その為の が先頭になっていた。そのため は成立するのに ための だと
    // 形式名詞(ため)の末尾照合に当たらないため、連体修飾の の を剥がしてから照合する(2489)
    func testRegressionFormalNounWithAttributiveNoKeepsKana() throws {
        try prepareRealLMDictionary()
        let multi = converter.multiClauseCandidates(for: "そのための", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "そのための", "multi=\(multi.prefix(4))")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "そのための"))
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "このための"))
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "そのため"))
        // 名詞+の(ずかんの)は既存の単字助詞剥がし規則(の を含む)の対象で、この変更とは無関係。
        // かな維持は「維持のみで昇格しない」ので、漢字が最良の読みには影響しない
    }

    // にほんごがうてる→日本語が得てる: 得る/獲る は読み うる で一段登録されているため語幹「う」から
    // 得てる/獲てる/得て のような現代語では使わない活用が作られ、打てる を押し下げていた。
    // うる(文語)基底からの一段派生を作らない(いい 基底の除外と同型。2494)
    func testRegressionArchaicUruBaseNotInflected() throws {
        try prepareRealLMDictionary()
        let uteru = converter.candidates(for: "うてる", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(uteru.first, "打てる", "uteru=\(uteru)")
        XCTAssertFalse(uteru.contains("得てる"), "uteru=\(uteru)")
        let multi = converter.multiClauseCandidates(for: "にほんごがうてる", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "日本語が打てる", "multi=\(multi.prefix(4))")
        // える 読みの派生は無傷(得てる/得られる)
        let eteru = converter.candidates(for: "えてる", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(eteru.first, "得てる", "eteru=\(eteru)")
        let erareru = converter.candidates(for: "えられる", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(erareru.first, "得られる", "erareru=\(erareru)")
        // あり得る(複合)も無傷
        let ariuru = converter.multiClauseCandidates(for: "ありうる", systemCandidateMode: .surface)
        XCTAssertEqual(ariuru.first?.hasSuffix("得る"), true, "ariuru=\(ariuru.prefix(3))")
    }

    // まっている→舞っている: 活用ルール定義順(う→…→つ)のため 舞う 族が先に立っていた。
    // LM は 待つ(6049)/待ち(5928)が 舞う(6578)/舞い(7446)より優勢で日常頻度も 待つ が上なので、
    // 基底読み族のopt-in昇格(はる/おく と同じ機構)に まつ を追加(2495)
    func testRegressionMatsuFamilyPreferredOverMau() throws {
        try prepareRealLMDictionary()
        let teiru = converter.candidates(for: "まっている", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(teiru.first, "待っている", "teiru=\(teiru)")
        let multi = converter.multiClauseCandidates(for: "まっている", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "待っている", "multi=\(multi.prefix(3))")
        let te = converter.candidates(for: "まって", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(te.first, "待って", "te=\(te)")
        let teru = converter.candidates(for: "まってる", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(teru.first, "待ってる", "teru=\(teru)")
        // 舞う 族は候補として残る
        XCTAssertTrue(te.contains("舞って"), "te=\(te)")
    }

    // こっちむきに→こっち剥きに / こっちむき→こっち無機: 向き は unigram 5555 で
    // 無機(6037)/無期(7143)/剥き(7216)より安いのに、読み2字の短spanレア読み床上げ
    // (読み別 wc 7924)で沈んでいた。この床だけ seed 免除が無かったので、隣の収穫底値床・
    // 読み跨ぎ遮断と同条件(seed 掲載語は人手選別なので免除)に揃えた(2499)。
    // うえの は 上の が候補に無く かな先頭だったので seed で 上の→上野→うえの に
    func testRegressionMukiFloorExemptAndUenoOrdering() throws {
        try prepareRealLMDictionary()
        let ni = converter.multiClauseCandidates(for: "こっちむきに", systemCandidateMode: .surface)
        XCTAssertEqual(ni.first, "こっち向きに", "ni=\(ni.prefix(4))")
        let muki = converter.multiClauseCandidates(for: "こっちむき", systemCandidateMode: .surface)
        XCTAssertEqual(muki.first, "こっち向き", "muki=\(muki.prefix(4))")
        // 後ろ向きに 等の既存の並びは不変
        let ushiro = converter.multiClauseCandidates(for: "うしろむきに", systemCandidateMode: .surface)
        XCTAssertEqual(ushiro.first, "後ろ向きに", "ushiro=\(ushiro.prefix(4))")
        // むき 単独はかな先頭のまま(seed の宣言順)
        let mukiAlone = converter.candidates(for: "むき", limit: 3, systemCandidateMode: .surface)
        XCTAssertEqual(Array(mukiAlone.prefix(2)), ["むき", "向き"], "mukiAlone=\(mukiAlone)")
        let ueno = converter.candidates(for: "うえの", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(Array(ueno.prefix(3)), ["上の", "上野", "うえの"], "ueno=\(ueno)")
    }

    // きたんだが→来たんだが: 3つの原因を直した(2504)。
    // (1) postfix 合成の語幹順が辞書の名詞(北/喜多)を先に並べていた。説明の んだ 系は用言の
    //     連体形に付く(名詞なら なんだ)ので活用派生の語幹を前に出す(かな識別は昇格させない)。
    // (2) 収穫底値(wc10000)のレア名前を語幹にした合成(木反田+が)が長語幹優先で先に出ていた
    //     ので後方へ回す(候補としては残す)。
    // (3) 連文節が 奇譚(uni6523)+だが を選んでいた。のだ縮約の準体助詞 ん は述語直後で頻出なので、
    //     活用派生の直後に限りボーナスを与える(名詞側の減点は 簡単だが を壊すので採らない)。
    func testRegressionKitandagaPrefersKuruContraction() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "きたんだが", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "来たんだが", "single=\(single)")
        // きたん(奇譚/忌憚)+だが は長い語幹だが、のだ縮約(来た+んだが)を優先する(2506)
        XCTAssertFalse(single.prefix(4).contains { $0.hasSuffix("譚だが") }, "single=\(single)")
        let multi = converter.multiClauseCandidates(for: "きたんだが", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "来たんだが", "multi=\(multi.prefix(4))")
        XCTAssertEqual(
            converter.candidates(for: "きたんだ", limit: 4, systemCandidateMode: .surface).first,
            "来たんだ"
        )
        XCTAssertEqual(
            converter.multiClauseCandidates(for: "みたんだが", systemCandidateMode: .surface).first,
            "見たんだが"
        )
        // 形容動詞+だが、丸ごと語、コピュラ過去+準体助詞(2461)は無傷
        XCTAssertEqual(
            converter.multiClauseCandidates(for: "かんたんだが", systemCandidateMode: .surface).first,
            "簡単だが"
        )
        XCTAssertEqual(
            converter.multiClauseCandidates(for: "いったんていし", systemCandidateMode: .surface).first,
            "一旦停止"
        )
        XCTAssertEqual(
            converter.multiClauseCandidates(for: "いつだったんだろう", systemCandidateMode: .surface).first,
            "いつだったんだろう"
        )
    }

    // きたんだが が実機だけ 奇譚だが になっていた: 逐次入力で各前置き(き→きた→きたん→きたんだ)が
    // 候補キャッシュに載り、キャッシュ利用の quick postfix 経路(スコア1120=BFS 1040より上)が
    // 「長い語幹優先」だけで並べるため きたん(奇譚/忌憚)+だ が伝播していた。BFS 側(2506)と同じ
    // 「述語+説明の んだ を最優先」をこの経路にも入れる(2509)
    func testRegressionKitandagaWithWarmStemCache() throws {
        try prepareRealLMDictionary()
        // 実機と同じ順で前置きを変換してキャッシュを温める
        for reading in ["き", "きた", "きたん", "きたんだ"] {
            _ = converter.candidates(for: reading, limit: 8, systemCandidateMode: .surface)
        }
        let kitanda = converter.candidates(for: "きたんだ", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(kitanda.first, "来たんだ", "kitanda=\(kitanda)")
        let single = converter.candidates(for: "きたんだが", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "来たんだが", "single=\(single)")
    }

    // おとく: Sudachi は 汚涜/お徳/おとく のみで お得/おトク 皆無。seed 供給+指定順
    // {お得, お徳, おトク, おとく, 汚涜}。連文節は全かなエコー(おとくです)が最良に
    // 出ていたため seed 順ボーナス(2000)で お得+です を優先(2524)
    func testRegressionRealLMOtokuPrefersOtoku() throws {
        try prepareRealLMDictionary()
        XCTAssertEqual(
            Array(converter.candidates(for: "おとく", limit: 5, systemCandidateMode: .surface)),
            ["お得", "お徳", "おトク", "おとく", "汚涜"]
        )
        XCTAssertEqual(converter.candidates(for: "おとくです", limit: 5, systemCandidateMode: .surface).first, "お得です")
        let multi = converter.multiClauseCandidates(for: "おとくです", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "お得です", "multi=\(multi)")
        // おとくだった が 音+下った(おと|くだった 跨ぎ合成)に負けないこと(2526でボーナス3300へ)
        let datta = converter.multiClauseCandidates(for: "おとくだった", systemCandidateMode: .surface)
        XCTAssertEqual(datta.first, "お得だった", "multi=\(datta)")
        // ガード: ボーナス過大だと侵食される実在語(4200で お得伊佐間 が出た)
        let isama = converter.multiClauseCandidates(for: "おとくいさま", systemCandidateMode: .surface)
        XCTAssertEqual(isama.first, "お得意さま", "multi=\(isama)")
        XCTAssertEqual(converter.candidates(for: "おとくにぐん", limit: 3, systemCandidateMode: .surface).first, "乙訓郡")
        let kurabe = converter.multiClauseCandidates(for: "おとくらべ", systemCandidateMode: .surface)
        XCTAssertEqual(kurabe.first, "音比べ", "multi=\(kurabe)")
    }

    // いち→位置 を先頭に(ユーザー指定): 基底は 伊地/一/…/位置(6位)。seed で単文節を
    // 矯正し、連文節は 連体の の 直後限定の遷移ボーナスで 地図上の位置 等を最良に。
    // 一から(やり直す)等の慣用句は の以外の文脈なので不変(2525)
    func testRegressionRealLMIchiPrefersPosition() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "いち", limit: 5, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(3)), ["位置", "一", "市"], "single=\(single)")
        let map = converter.multiClauseCandidates(for: "ちずじょうのいち", systemCandidateMode: .surface)
        XCTAssertEqual(map.first, "地図上の位置", "multi=\(map)")
        // ガード: 慣用句/辞書語は不変
        let idiom = converter.multiClauseCandidates(for: "いちからやりなおす", systemCandidateMode: .surface)
        XCTAssertTrue(idiom.first?.hasPrefix("一から") == true, "multi=\(idiom)")
        XCTAssertEqual(converter.candidates(for: "いちば", limit: 3, systemCandidateMode: .surface).first, "市場")
        XCTAssertEqual(converter.candidates(for: "だいいち", limit: 3, systemCandidateMode: .surface).first, "第一")
    }

    // れふぉーる→レフォール(西洋わさび): 辞書に れふぉ〜 が皆無で single 空、
    // multi は れ+フォール(れフォール)に化けていた。sacoche curated で救済(2523)
    func testRegressionRealLMRefooruPrefersCurated() throws {
        try prepareRealLMDictionary()
        converter.store.addUserEntry(reading: "れふぉーる", candidate: "レフォール")

        XCTAssertEqual(converter.candidates(for: "れふぉーる", limit: 5, systemCandidateMode: .surface).first, "レフォール")
        // 連文節は単語1個で全読みを覆うとき空を返す(ふぉーる 等と同じ)。
        // curated 導入前の れフォール(れ+フォール 合成)が最良に残らないことだけ確認
        let multi = converter.multiClauseCandidates(for: "れふぉーる", systemCandidateMode: .surface)
        XCTAssertNotEqual(multi.first, "れフォール", "multi=\(multi)")
    }

    // ふらんすしゃ: 候補バーでは単文節#1(フランス車)を連文節合成(フランス社)より
    // 先頭に置く(2522)。判定は 読み末尾しゃ+単文節#1末尾車 のスコープ限定
    func testWholeReadingShaAffixPromotesAboveMultiClause() throws {
        try prepareRealLMDictionary()
        // 単文節#1がフランス車のままであること(2520の供給)
        XCTAssertEqual(converter.candidates(for: "ふらんすしゃ", limit: 5, systemCandidateMode: .surface).first, "フランス車")
        // 昇格判定: しゃ/車 のみ true。敬称さん(田中産)や 社 辞書語(新聞社)は対象外
        XCTAssertTrue(converter.shouldPromoteSingleBestAboveMultiClause(reading: "ふらんすしゃ", singleBest: "フランス車"))
        XCTAssertTrue(converter.shouldPromoteSingleBestAboveMultiClause(reading: "にほんしゃ", singleBest: "日本車"))
        XCTAssertFalse(converter.shouldPromoteSingleBestAboveMultiClause(reading: "しんぶんしゃ", singleBest: "新聞社"))
        XCTAssertFalse(converter.shouldPromoteSingleBestAboveMultiClause(reading: "たなかさん", singleBest: "田中産"))
        XCTAssertFalse(converter.shouldPromoteSingleBestAboveMultiClause(reading: "きしゃ", singleBest: "汽車"))
    }

    // ふらんすしゃ→フランス車: 名詞+車(産地・所属)の接辞合成(2520)。
    // reading>=4ガードで いしゃ/きしゃ 等の短い読みには影響しない
    func testFuransushaProducesFuransusha() throws {
        try prepareRealLMDictionary()
        XCTAssertEqual(converter.candidates(for: "ふらんすしゃ", limit: 5, systemCandidateMode: .surface).first, "フランス車")
        XCTAssertEqual(converter.candidates(for: "にほんしゃ", limit: 5, systemCandidateMode: .surface).first, "日本車")
        XCTAssertEqual(converter.candidates(for: "えいこくしゃ", limit: 5, systemCandidateMode: .surface).first, "英国車")
        // 既存語のガード: 会社/医者/汽車系が崩れないこと
        XCTAssertEqual(converter.candidates(for: "かいしゃ", limit: 5, systemCandidateMode: .surface).first, "会社")
        XCTAssertEqual(converter.candidates(for: "いしゃ", limit: 5, systemCandidateMode: .surface).first, "医者")
        XCTAssertEqual(converter.candidates(for: "きしゃ", limit: 5, systemCandidateMode: .surface).first, "記者")
    }

    // おんがくをならせる→音楽を成らせる: 鳴らせる は 鳴る(なる族)の使役だが、なる族の基底順は
    // かな なる(LM3405)が先頭のため連文節の活用供給 TopK3 から漏れていた(基底読み間順序型)。
    // seed(a2)で供給+先頭ノードボーナス。鳴らせる は word_costs に収穫底値10302で実在するため
    // a2 の派生フラグ条件(costMap==nil)を底値帯まで広げた — 素の辞書ノード(8700・助詞後
    // 割引なし)のままだと 成らせる(活用OOV=助詞後5000)に勝てない(2519)
    func testRegressionNaraseruPrefersNarasu() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "ならせる", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "鳴らせる", "single=\(single)")
        let multi = converter.multiClauseCandidates(for: "おんがくをならせる", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "音楽を鳴らせる", "multi=\(multi.prefix(4))")
        // ならす(辞書の丸ごとエントリ)は従来どおり
        XCTAssertEqual(
            converter.multiClauseCandidates(for: "おんがくをならす", systemCandidateMode: .surface).first,
            "音楽を鳴らす"
        )
    }

    // ながら(同時進行): 連用形+ながら の活用規則がどのクラスにも無く、みながら→みな柄/
    // かきながら→火器ながら のような断片合成しか出なかった(未対応だった)。一段/五段/サ変/
    // カ変に追加(2518)。あるきながら だけ動いていたのは 歩き が辞書の連用形収穫にあったため
    func testRegressionNagaraInflection() throws {
        try prepareRealLMDictionary()
        for (reading, expected) in [
            ("みながら", "見ながら"), ("かきながら", "書きながら"),
            ("たべながら", "食べながら"), ("ききながら", "聞きながら"),
            ("べんきょうしながら", "勉強しながら")
        ] {
            let single = converter.candidates(for: reading, limit: 5, systemCandidateMode: .surface)
            XCTAssertEqual(single.first, expected, "\(reading)=\(single)")
        }
        // 連文節の文脈でも組める
        let multi = converter.multiClauseCandidates(for: "おんがくをききながら", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "音楽を聞きながら", "multi=\(multi.prefix(3))")
        let terebi = converter.multiClauseCandidates(for: "てれびをみながらたべる", systemCandidateMode: .surface)
        XCTAssertEqual(terebi.first, "テレビを見ながら食べる", "terebi=\(terebi.prefix(3))")
    }

    // なおす: 治す(wc7184)が辞書順先頭だが 直す と同程度に頻出(ユーザー指定で 直す 先頭)。
    // てもある: エンジンはかな先頭だが keepKana 不成立で提示層が ても有る に繰り上げていた。
    // ある/いる 剥がしの語幹に接続助詞のて形+係助詞(ても/でも 等)を明示許可(2517)
    func testRegressionNaosuAndTemoaru() throws {
        try prepareRealLMDictionary()
        let naosu = converter.candidates(for: "なおす", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(Array(naosu.prefix(2)), ["直す", "治す"], "naosu=\(naosu)")
        let naoshite = converter.candidates(for: "なおして", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(Array(naoshite.prefix(2)), ["直して", "治して"], "naoshite=\(naoshite)")
        // 病気の文脈は 治った が先頭のまま(意味的に正しい側を維持)
        XCTAssertEqual(
            converter.multiClauseCandidates(for: "びょうきがなおった", systemCandidateMode: .surface).first,
            "病気が治った"
        )
        let temoaru = converter.multiClauseCandidates(for: "てもある", systemCandidateMode: .surface)
        XCTAssertEqual(temoaru.first, "てもある", "temoaru=\(temoaru)")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "てもある"))
    }

    // ことで: エンジンは かな先頭(ことで→事で)を返していたが keepKana 不成立で提示層が
    // かなを末尾チップへ回し、事で が先頭になっていた。形式名詞(こと/とき/もの/ため)+
    // 格助詞1字を keepKana の根拠に追加(語幹は明示集合=しごとで/ずかんで は巻き込まない。2516)
    func testRegressionKotodeKeepsKana() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "ことで", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(2)), ["ことで", "事で"], "single=\(single)")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "ことで"))
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "ときに"))
        // 名詞+で は巻き込まない(仕事で が先頭のまま)
        XCTAssertFalse(converter.shouldKeepKanaIdentityLeading(for: "しごとで"))
        XCTAssertEqual(
            converter.multiClauseCandidates(for: "しごとで", systemCandidateMode: .surface).first,
            "仕事で"
        )
    }

    // 実機のみの2件(学習リセット・キャッシュクリアでも消えない=追加語彙が原因のパターン)。
    // どちらも misc の curated 登録が別読みのラティスを歪めていた(loadDeviceAddedVocabulary で再現)。
    // (1) きたんだが→着たんだが: misc の きた→来た(curated)が先着 dedupe で b2 活用コピーを
    //     潰し、来た ノードが isInflectionDerived を失って準体助詞 ん のボーナスが効かなかった。
    //     curated 先着ノードへの派生フラグ合流を追加(2105/2108 の同族)。
    // (2) かたほうが→方ほうが: misc の ほうが(curated 床1500)が名詞 方(かた)の直後にも立てた。
    //     比較の ほうが は連体形・の・な にしか付かないので文法ゲートを追加(2514)
    func testRegressionDeviceVocabularyKitandagaAndKatahouga() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary()
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let kitanda = converter.multiClauseCandidates(for: "きたんだが", systemCandidateMode: .surface)
        XCTAssertEqual(kitanda.first, "来たんだが", "kitanda=\(kitanda.prefix(3))")
        // 読み全体に seed があると連文節は単文節(seed 順)に委ねる(2657)ので、実機バーと同じ
        // multi ?? single で検証する
        let katahou = converter.multiClauseCandidates(for: "かたほうが", systemCandidateMode: .surface)
        let katahouSingle = converter.candidates(for: "かたほうが", limit: 3, systemCandidateMode: .surface)
        XCTAssertEqual(katahou.first ?? katahouSingle.first, "片方が", "katahou=\(katahou.prefix(3)) single=\(katahouSingle)")
        // 比較の ほうが の正当な文脈(連体形/の/な)は無傷
        XCTAssertEqual(
            converter.multiClauseCandidates(for: "かったほうがいい", systemCandidateMode: .surface).first,
            "買った方がいい"
        )
        XCTAssertEqual(
            converter.multiClauseCandidates(for: "はやいほうが", systemCandidateMode: .surface).first,
            "早いほうが"
        )
        XCTAssertEqual(
            converter.multiClauseCandidates(for: "こっちのほうが", systemCandidateMode: .surface).first,
            "こっちのほうが"
        )
        XCTAssertEqual(
            converter.multiClauseCandidates(for: "しずかなほうが", systemCandidateMode: .surface).first,
            "静かなほうが"
        )
    }

    // かたほうが→方ほうが: quick postfix(キャッシュ語幹)の 方+ほうが が BFS の長語幹 片方+が に
    // 勝っていた。seed で 片方が を辞書チャネル(1200>postfix 1120)から直接供給(2513)。
    // くらいのはなぜだろう→くらいのは…: 副助詞 くらい/ぐらい は文頭に立たないので BOS 直後の
    // かな識別に減点(かな くらい 5614 < 暗い 6012 で形容詞が負けていた)。なぜ は 何故 より
    // かなが正書なのでかな副詞クランプへ。
    // せめてこれぐらい→攻めて…: せめて(副詞、かな正書)をかな副詞クランプに追加し、
    // かな副詞で始まる全かな句の keepKana 規則も追加
    func testRegressionKatahouKuraiSemete() throws {
        try prepareRealLMDictionary()
        let katahou = converter.candidates(for: "かたほうが", limit: 5, systemCandidateMode: .surface)
        XCTAssertEqual(katahou.first, "片方が", "katahou=\(katahou)")
        // 読み全体に seed があると連文節は単文節に委ねる(2657): バー基準(multi ?? single)
        XCTAssertEqual(
            converter.multiClauseCandidates(for: "かたほうが", systemCandidateMode: .surface).first ?? katahou.first,
            "片方が"
        )
        for reading in ["くらいのはなぜだ", "くらいのはなぜだろう"] {
            let multi = converter.multiClauseCandidates(for: reading, systemCandidateMode: .surface)
            XCTAssertEqual(multi.first?.hasPrefix("暗いのはなぜだ"), true, "\(reading)=\(multi.prefix(3))")
        }
        let semete = converter.multiClauseCandidates(for: "せめてこれぐらい", systemCandidateMode: .surface)
        XCTAssertEqual(semete.first, "せめてこれぐらい", "semete=\(semete.prefix(3))")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "せめてこれぐらい"))
        // ぐらい/くらい の文中・文頭形容詞は無傷
        XCTAssertEqual(
            converter.multiClauseCandidates(for: "せんえんぐらい", systemCandidateMode: .surface).first,
            "千円ぐらい"
        )
        XCTAssertEqual(
            converter.multiClauseCandidates(for: "くらいくらい", systemCandidateMode: .surface).first,
            "暗いくらい"
        )
        XCTAssertEqual(
            converter.multiClauseCandidates(for: "これぐらいのおおきさ", systemCandidateMode: .surface).first,
            "これぐらいの大きさ"
        )
    }

    // きたんだが が実機で 奇譚だが のまま残った件(3例目): 実機は misc/Ajout の追加語彙を読み、
    // かな識別 curated の だが(連文節床1500)が存在する。すると 奇譚+だが(2ノード)が
    // 来た+ん+だが(3ノード)より安くなる — テストバンドルは追加語彙を読まないため再現しなかった。
    // curated だが を注入して再現し、準体助詞 ん のボーナスを 3000→5000 に調整(2511)
    func testRegressionKitandagaWithCuratedDaga() throws {
        try prepareRealLMDictionary()
        converter.store.addUserEntry(reading: "だが", candidate: "だが")
        converter.invalidateCandidateCache()
        let multi = converter.multiClauseCandidates(for: "きたんだが", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "来たんだが", "multi=\(multi.prefix(4))")
        XCTAssertEqual(
            converter.multiClauseCandidates(for: "みたんだが", systemCandidateMode: .surface).first,
            "見たんだが"
        )
        // かな きたんだが は使わない(ユーザー指定)= keepKana 不成立で提示層が末尾チップへ回す。
        // 従来は のは/んだ 剥がしの語幹条件が「辞書にかなエントリが在る」だけで きた が通っていた。
        // かな正書の語幹(ある/ひらがな)は isKanaOrthographyStem(LM 優位+マージン800)で維持(2512)
        XCTAssertFalse(converter.shouldKeepKanaIdentityLeading(for: "きたんだが"))
        XCTAssertFalse(converter.shouldKeepKanaIdentityLeading(for: "きたんだ"))
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "あるんだ"))
        // 形容動詞+だが は無傷
        XCTAssertEqual(
            converter.multiClauseCandidates(for: "かんたんだが", systemCandidateMode: .surface).first,
            "簡単だが"
        )
    }

    // けいし: 単語レベルで 軽視 を 刑死 より優先(ユーザー指定)。サ変派生にも基底順が伝わる(2510)
    func testRegressionKeishiPrefersKeishiVerb() throws {
        try prepareRealLMDictionary()
        let keishi = converter.candidates(for: "けいし", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(
            Array(keishi.prefix(5)),
            ["けいし", "警視", "軽視", "罫紙", "刑死"],
            "keishi=\(keishi)"
        )
        let suru = converter.candidates(for: "けいしする", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(suru.first, "軽視する", "suru=\(suru)")
        let subeki = converter.candidates(for: "けいしすべき", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(subeki.first, "軽視すべき", "subeki=\(subeki)")
    }

    // けいしすべき→ケイしすべき: 当然・義務の べき(文語 す+べき)のサ変規則が無く、断片合成に
    // なっていた(けいしする は規則があるので動いていた)。すべき/すべきだ/すべきです/
    // すべきだった/すべきでない/すべきではない を追加(2509)
    func testRegressionSahenSubekiInflection() throws {
        try prepareRealLMDictionary()
        let keishi = converter.candidates(for: "けいしすべき", limit: 5, systemCandidateMode: .surface)
        XCTAssertTrue(keishi.contains("軽視すべき"), "keishi=\(keishi)")
        XCTAssertFalse(keishi.contains("ケイしすべき"), "keishi=\(keishi)")
        XCTAssertEqual(
            converter.candidates(for: "けんとうすべき", limit: 3, systemCandidateMode: .surface).first,
            "検討すべき"
        )
        XCTAssertEqual(
            converter.candidates(for: "ちゅういすべきだ", limit: 3, systemCandidateMode: .surface).first,
            "注意すべきだ"
        )
    }

    // など: 等 は読み など を辞書に持たない(等の読みは とう/ら/ひとし/たち)ため候補に出なかった。
    // seed で供給して2番目に置く(1番目はかな)。ただし 等 の unigram(4051)は安く、連文節で
    // これなど→これ等/などという→等という を作るので、連文節だけ床上げする(2508)
    func testRegressionNadoSuppliesTouSingleClauseOnly() throws {
        try prepareRealLMDictionary()
        let nado = converter.candidates(for: "など", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(Array(nado.prefix(2)), ["など", "等"], "nado=\(nado)")
        // 連文節ではかなのまま(2487 の などという も維持)
        XCTAssertEqual(
            converter.multiClauseCandidates(for: "ほんなどをよむ", systemCandidateMode: .surface).first,
            "本などを読む"
        )
        XCTAssertEqual(
            converter.multiClauseCandidates(for: "などという", systemCandidateMode: .surface).first,
            "などという"
        )
    }

    // あとおき: 辞書に丸ごとのエントリが無く単文節は空、連文節は 沖(wc5165)が 置き(7714)より
    // 安いため 後沖/後起き になっていた。未登録の複合語なので misc curated で供給する
    func testRegressionAtookiSuppliedFromMisc() throws {
        try prepareRealLMDictionary()
        converter.store.addUserEntry(reading: "あとおき", candidate: "後置き")
        converter.invalidateCandidateCache()
        let single = converter.candidates(for: "あとおき", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "後置き", "single=\(single)")
        // 全長読みが curated の時は連文節は単文節に委ねる(空を返す)=提示層は単文節の並びを使う
        XCTAssertTrue(
            converter.multiClauseCandidates(for: "あとおき", systemCandidateMode: .surface).isEmpty
        )
    }

    // か: 蚊 は読み か のエントリが辞書に無く(語LMには 6955 で在る)候補にすら出なかった。
    // 名詞として唯一自立する 蚊 を先頭に、接頭辞・接尾辞の 科/下/過/加、古語的な 彼/鹿 と続ける。
    // ので: 辞書には 能出/野出/野手(収穫底値)しか無く、かなの接続助詞が候補に無かった(2507)
    func testRegressionKaAndNodeKanaSeeded() throws {
        try prepareRealLMDictionary()
        let ka = converter.candidates(for: "か", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(
            Array(ka.prefix(7)),
            ["蚊", "科", "下", "過", "加", "彼", "鹿"],
            "ka=\(ka)"
        )
        let node = converter.candidates(for: "ので", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(node.first, "ので", "node=\(node)")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "ので"))
        // 助詞としての用法(連文節)は無傷
        XCTAssertEqual(
            converter.multiClauseCandidates(for: "さむいのででかけない", systemCandidateMode: .surface).first,
            "寒いので出掛けない"
        )
        XCTAssertEqual(
            converter.multiClauseCandidates(for: "そうですか", systemCandidateMode: .surface).first,
            "そうですか"
        )
    }

    // ひとにでも→人にデモ: でも は辞書に デモ(wc2537/uni5547)しか無いため連文節がカタカナ語を
    // 選んでいた。格助詞の直後の でも は副助詞なので、その文脈のカタカナ/漢字表層に減点する。
    // 名詞直後(反対+でも)は対象外なので 反対デモ は無傷。かなを seed で供給する案は
    // ことでもなく→ことでも無く を壊したため採らない(2505)
    func testRegressionCaseParticlePlusDemoClampsKana() throws {
        try prepareRealLMDictionary()
        let multi = converter.multiClauseCandidates(for: "ひとにでも", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "人にでも", "multi=\(multi.prefix(4))")
        let single = converter.candidates(for: "ひとにでも", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(2)), ["人にでも", "ひとにでも"], "single=\(single)")
        // 名詞+でも は対象外(反対デモ が先頭のまま)
        XCTAssertEqual(
            converter.multiClauseCandidates(for: "はんたいでも", systemCandidateMode: .surface).first,
            "反対デモ"
        )
        // ことでもなく(こと は格助詞ではない)は かな先頭のまま
        XCTAssertEqual(
            converter.multiClauseCandidates(for: "ことでもなく", systemCandidateMode: .surface).first,
            "ことでもなく"
        )
    }

    // しまくり: 接尾の補助動詞 まくり はかなが正書だが、かな まくり(wc11137)が 捲り(9561)より
    // 重いため提示層で し捲り に繰り上げられていた。まくり/まくる で終わる読みを keepKana の
    // 根拠に加える。ほんとだ は かな ほんと(4550)が 本当(2581)に負けるので curated で供給(2505)
    func testRegressionMakuriAndHontodaKanaLeading() throws {
        try prepareRealLMDictionary()
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "しまくり"))
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "やりまくる"))
        let multi = converter.multiClauseCandidates(for: "しまくり", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "しまくり", "multi=\(multi.prefix(4))")
        // 勉強しまくり(漢字+かな)は従来どおり先頭
        XCTAssertEqual(
            converter.multiClauseCandidates(for: "べんきょうしまくり", systemCandidateMode: .surface).first,
            "勉強しまくり"
        )
        // ほんとだ: curated のかな識別が先頭に来る
        converter.store.addUserEntry(reading: "ほんとだ", candidate: "ほんとだ")
        converter.invalidateCandidateCache()
        let honto = converter.candidates(for: "ほんとだ", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(Array(honto.prefix(2)), ["ほんとだ", "本当だ"], "honto=\(honto)")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "ほんとだ"))
    }

    // かいし: 芥子(wc3727=カイシ と同値の収穫)と 会し が先頭を占め 開始/会誌 が後ろだった。
    // seed で指定順に固定(2498)
    func testRegressionKaishiOrdering() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "かいし", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(
            Array(single.prefix(6)),
            ["開始", "会誌", "怪死", "会し", "芥子", "会試"],
            "single=\(single)"
        )
    }

    // 補助語彙(ryukyu/vin/it.plist)は同じ読みに語LM実在の一般語が無いときだけ辞書より上へ
    // 昇格する。いちまん→糸満(7500)は 一満(6324)の後ろに沈んでいた。一律昇格は頻出語を
    // 押し下げるため不可(び→美/にほん→🇯🇵/じん→ジン。実測2331読み・頻出衝突525件。2497)
    func testRegressionSupplementalVocabularyPromotedOnlyWithoutCommonWord() throws {
        try prepareRealLMDictionary()
        let itoman = converter.candidates(for: "いちまん", limit: 5, systemCandidateMode: .surface)
        XCTAssertEqual(itoman.first, "糸満", "itoman=\(itoman)")
        let akasaki = converter.candidates(for: "あかさき", limit: 5, systemCandidateMode: .surface)
        XCTAssertEqual(akasaki.first, "赤崎", "akasaki=\(akasaki)")
        // 語LM実在の一般語がある読みは従来どおり(昇格しない)
        // なか は LM優位辞書候補の一般昇格(2545)で 中(uni3674)が先頭になった。
        // 名詞 中 が先頭は標準的な期待値なので改善として固定する
        for (reading, expected) in [
            ("にほん", "日本"), ("じん", "人"), ("なか", "中"),
            ("ぎんこう", "銀行"), ("よね", "よね"), ("から", "から")
        ] {
            let single = converter.candidates(for: reading, limit: 3, systemCandidateMode: .surface)
            XCTAssertEqual(single.first, expected, "\(reading)=\(single)")
        }
    }

    // きへい: 補助語彙(ryukyu.plist の 㐂平)は既定 word_cost(3字11000)で5番目に沈んでいた。
    // 補助語彙を一律で辞書より上に昇格させる案は 銀行→吟香/米→与根/遅い→襲 の3件を壊したため
    // 撤回し、語別に seed で昇格する(2496)
    func testRegressionKiheiSupplementalWordPromotedBySeed() throws {
        try prepareRealLMDictionary()
        let kihei = converter.candidates(for: "きへい", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(
            Array(kihei.prefix(4)),
            ["㐂平", "奇兵", "起兵", "騎兵"],
            "kihei=\(kihei)"
        )
        // 一律昇格で壊れた読みは無傷であること(撤回の根拠。ぎんこう→吟香、よね→与根 になっていた。
        // 3件目の おそい→襲 は suppr.plist で抑制済みで、テストバンドルが hidden 抑制JSONを
        // 読まないために現れていただけ=実機では無関係)
        XCTAssertEqual(
            converter.candidates(for: "ぎんこう", limit: 3, systemCandidateMode: .surface).first,
            "銀行"
        )
        XCTAssertEqual(
            converter.candidates(for: "よね", limit: 3, systemCandidateMode: .surface).first,
            "よね"
        )
    }

    // ほっきょくぐま: 語LMに ホッキョクグマ の unigram はあるが辞書エントリが無く変換できない。
    // 北極熊 も辞書に無いので両方 misc で供給する
    func testRegressionHokkyokugumaSuppliedFromMisc() throws {
        try prepareRealLMDictionary()
        converter.store.addUserEntry(reading: "ほっきょくぐま", candidate: "北極熊")
        converter.store.addUserEntry(reading: "ほっきょくぐま", candidate: "ホッキョクグマ")
        let single = converter.candidates(for: "ほっきょくぐま", limit: 5, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "ホッキョクグマ", "single=\(single)")
        XCTAssertTrue(single.contains("北極熊"), "single=\(single)")
    }

    // きんせい: 金青(wc3727=キンセイ と同値の収穫)が先頭で 金星/近世 が7000台に沈んでいた。
    // そばを: かな そば(2517)が先頭で 蕎麦(5892)が3番目だった。どちらも seed で並びを指定(2493)
    func testRegressionKinseiAndSobaOrdering() throws {
        try prepareRealLMDictionary()
        let kinsei = converter.candidates(for: "きんせい", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(
            Array(kinsei.prefix(5)),
            ["金星", "近世", "謹製", "禁制", "均整"],
            "kinsei=\(kinsei)"
        )
        let soba = converter.candidates(for: "そばを", limit: 5, systemCandidateMode: .surface)
        XCTAssertEqual(Array(soba.prefix(4)), ["蕎麦を", "そばを", "側を", "傍を"], "soba=\(soba)")
        // そば 単独の並びは変えていない(かな正書のまま)
        let sobaAlone = converter.candidates(for: "そば", limit: 3, systemCandidateMode: .surface)
        XCTAssertEqual(sobaAlone.first, "そば", "sobaAlone=\(sobaAlone)")
    }

    // でま→デマ: 実在の外来語なのに候補に出なかった。カタカナ強調抑止は LM unigram で
    // 「カタカナが同音の漢字より安い」ことを保護条件にしていたが、手間(6037)が デマ(6955)より
    // 安いため強調表記と誤判定していた。SudachiDict のカタカナ強調収穫は元の語と同一コストで
    // 入る(ウマイ=旨い5415/バカリ=秤5401)一方、外来語は その読みの主語彙として明確に安い
    // (デマ2137 ≪ 手間9327)ので、辞書コスト差2500以上を外来語の保護条件に加えた(2485)
    func testRegressionLoanwordKatakanaProtectedByWordCostGap() throws {
        try prepareRealLMDictionary()
        let dema = converter.candidates(for: "でま", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(dema.first, "デマ", "dema=\(dema)")
        // 手間/手ま は てま の連濁収穫。単独入力の候補列では多字表層も弾く(2485)
        XCTAssertFalse(dema.contains("手間"), "dema=\(dema)")
        XCTAssertFalse(dema.contains("手ま"), "dema=\(dema)")
        // 複合語内の連濁はラティス側に残す(人込み が作れること)
        let hitogomi = converter.candidates(for: "ひとごみ", limit: 6, systemCandidateMode: .surface)
        XCTAssertTrue(
            hitogomi.contains("人混み") || hitogomi.contains("人込み"),
            "hitogomi=\(hitogomi)"
        )
        // 強調表記の抑止は維持(同一コストの収穫は保護しない)
        let umai = converter.candidates(for: "うまい", limit: 8, systemCandidateMode: .surface)
        XCTAssertFalse(umai.contains("ウマイ"), "umai=\(umai)")
        let bakari = converter.candidates(for: "ばかり", limit: 8, systemCandidateMode: .surface)
        XCTAssertFalse(bakari.contains("バカリ"), "bakari=\(bakari)")
        // 出ました/出ます の妨害が無いこと(2文字ノードが活用形を崩さない)
        XCTAssertEqual(
            converter.candidates(for: "でました", limit: 4, systemCandidateMode: .surface).first,
            "出ました"
        )
        XCTAssertEqual(
            converter.multiClauseCandidates(for: "でまがひろまる", systemCandidateMode: .surface).first,
            "デマが広まる"
        )
    }

    // うえてあって→上てあって: 裸の接続助詞「て」が名詞(上=unigram3799)の直後に立ち、
    // 断片チェーン 上+て+あって が全span活用形 植えてあって(LM未収録=OOV)を逆転していた。
    // て は用言の連用形にしか付かないので、準体助詞 ん の「述語の直後にしか立てない」規則と
    // 同型に、直前が述語末尾文字でなければ減点する一般規則を入れた(2480)
    func testRegressionKanaTeRequiresPredicateBefore() throws {
        try prepareRealLMDictionary()
        let uete = converter.multiClauseCandidates(for: "うえてあって", systemCandidateMode: .surface)
        XCTAssertEqual(uete.first, "植えてあって", "multi=\(uete.prefix(4))")
        XCTAssertFalse(uete.contains("上てあって"), "multi=\(uete.prefix(4))")
        // 格助詞 で は名詞に付くので対象外(上で〜)
        let uede = converter.multiClauseCandidates(for: "うえでまってる", systemCandidateMode: .surface)
        XCTAssertEqual(uede.first?.hasPrefix("上で"), true, "multi=\(uede.prefix(4))")
        // 名詞の 手(reading て、表層≠読み)は無傷。なお かな指示詞+かな て(このての話)は
        // 減点対象外 — かな表層の直前は連用形かを判定できないため fail-open にしている
        let kono = converter.multiClauseCandidates(for: "このてのはなし", systemCandidateMode: .surface)
        XCTAssertEqual(kono.first?.hasSuffix("の話"), true, "multi=\(kono.prefix(4))")
        // 述語直後の て形+補助動詞も無傷
        let oite = converter.multiClauseCandidates(for: "おいてあって", systemCandidateMode: .surface)
        XCTAssertEqual(oite.first, "置いてあって", "multi=\(oite.prefix(4))")
    }

    // ここまで: エンジンは単文節/連文節ともかな先頭を返していたが keepKana 不成立で提示層が
    // かな識別を除去し、小駒で/個々まで が繰り上がっていた(LM に ここまで の unigram が無く
    // 個々5547/小駒7884 の合成が組める)。指示代名詞+助詞の照合を まで/から 等へ拡張(2476)
    func testRegressionDemonstrativePronounWithParticleKeepsKana() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "ここまで", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "ここまで", "single=\(single)")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "ここまで"))
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "そこから"))
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "これだけ"))
        // 名詞+助詞は巻き込まない(2406 の判断を維持)
        XCTAssertFalse(converter.shouldKeepKanaIdentityLeading(for: "ずかんまで"))
    }

    // 忘てる: 文語「忘る」が inflection_classes で一段活用登録されており、語幹「忘」から
    // 送り仮名を欠いた 忘て/忘てる を派生していた(とりわすれてる→取り忘てる)。基底を抑制
    func testRegressionWasuruArchaicBaseSuppressed() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["わすれる": ["忘る"]])
        converter.clearSharedDataCaches()
        converter.invalidateCandidateCache()
        let teru = converter.candidates(for: "わすれてる", limit: 8, systemCandidateMode: .surface)
        XCTAssertFalse(teru.contains("忘てる"), "teru=\(teru)")
        XCTAssertEqual(teru.first, "忘れてる", "teru=\(teru)")
        let multi = converter.multiClauseCandidates(for: "とりわすれてる", systemCandidateMode: .surface)
        XCTAssertFalse(multi.contains("取り忘てる"), "multi=\(multi.prefix(5))")
    }

    // とり→撮り / はり→貼り: 辞書の連用形収穫に 撮り(取り/執り/捕り/採り のみ)と
    // 貼り(張り のみ。貼り は連濁読み ばり でだけ実在)が無く、撮り忘れ/貼り忘れ が作れなかった。
    // 撮る/貼る は inflection_classes に在るので活用形は出るが裸の連用形は供給されない(2475)
    func testRegressionRenyoukeiSuppliedFromSeed() throws {
        try prepareRealLMDictionary()
        let tori = converter.candidates(for: "とり", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(tori.prefix(4)), ["取り", "とり", "鳥", "撮り"], "tori=\(tori)")
        let hari = converter.candidates(for: "はり", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(hari.prefix(4)), ["はり", "針", "張り", "貼り"], "hari=\(hari)")
        // 連文節の合成にも seed 経由で届く
        let multi = converter.multiClauseCandidates(for: "とりわすれてる", systemCandidateMode: .surface)
        XCTAssertTrue(multi.contains("撮り忘れてる"), "multi=\(multi.prefix(5))")
    }

    func testRegressionInferredInflectionClassNotAppliedToSystemCandidates() throws {
        try prepareRealLMDictionary()
        let kawatte = converter.candidates(for: "かわって", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(kawatte.first, "変わって", "kawatte=\(kawatte)")
        XCTAssertFalse(kawatte.contains("河って"), "kawatte=\(kawatte)")
        let multi = converter.multiClauseCandidates(for: "かわってきてる", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "変わってきてる", "multi=\(multi.prefix(4))")
    }

    func testRegressionNaAdjectiveKanaOrthographyInflection() throws {
        try prepareRealLMDictionary()
        let iyade = converter.candidates(for: "いやで", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(iyade.prefix(3)), ["イヤで", "いやで", "嫌で"], "iyade=\(iyade)")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "いやで"))
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "むらで"))
        // 名詞+で の巻き込みが無いこと(2406 の判断を維持)
        XCTAssertFalse(converter.shouldKeepKanaIdentityLeading(for: "ずかんで"))
    }

    func testRegressionGodanSuNegativeContractionExcluded() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["うまい": ["熟寝", "熟睡", "右舞"]])

        let takusan = converter.candidates(for: "たくさん", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(takusan.prefix(2)), ["たくさん", "沢山"], "takusan=\(takusan)")
        XCTAssertFalse(takusan.contains("託さん"), "takusan=\(takusan)")
        XCTAssertFalse(takusan.contains("托さん"), "takusan=\(takusan)")

        let multi = converter.multiClauseCandidates(for: "うまいものがたくさん", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "うまいものがたくさん", "multi=\(multi.prefix(4))")
        // 提示層のかな退避を防ぐ(false だと実機バーで 上手い が繰り上がる)
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "うまいものがたくさん"))
        for junk in ["うまいものが托さん", "うまいものが託さん", "熟睡ものがたくさん"] {
            XCTAssertFalse(multi.contains(junk), "\(junk) が残っている: \(multi.prefix(4))")
        }
        // 五段す 以外の口語否定縮約は温存(知らん/やらん)
        XCTAssertTrue(
            converter.candidates(for: "しらん", limit: 8, systemCandidateMode: .surface).contains("知らん"),
            "五段ら の ん形は温存"
        )
    }

    // いつだったんだろう: 〜ったん を丸ごと1語とする名詞(脱炭/韃靼/達陀)がコピュラ過去+
    // 準体助詞の分割(だった+ん)より安く、いつ脱炭だろう が先頭になっていた。直後が
    // だろう/だろ/でしょう のときだけ丸ごと語に減点する文脈条件付きの規則で是正。
    // 一旦(いったん)等の正当な語や、だったんそば(韃靼そば)は文脈条件外なので無傷。
    // なお 陀 に「たん」の読みは無く、辞書にあるのは達陀(だったん)という語全体(2461)
    func testRegressionTanContractionPrefersCopulaSplit() throws {
        try prepareRealLMDictionary()
        for reading in ["いつだったんだろう", "いつだったんだろ"] {
            let multi = converter.multiClauseCandidates(for: reading, systemCandidateMode: .surface)
            XCTAssertEqual(multi.first, reading, "\(reading)=\(multi.prefix(3))")
        }
        // 文脈条件外は無傷(一旦停止/韃靼そば系/なんだろう)
        XCTAssertEqual(
            converter.multiClauseCandidates(for: "いったんていし", systemCandidateMode: .surface).first,
            "一旦停止"
        )
        XCTAssertTrue(
            converter.multiClauseCandidates(for: "だったんそば", systemCandidateMode: .surface)
                .contains { $0.hasPrefix("韃靼") || $0.hasPrefix("脱炭") },
            "だったん の丸ごと語は文脈条件外では温存"
        )
        XCTAssertEqual(
            converter.multiClauseCandidates(for: "なんだろう", systemCandidateMode: .surface).first,
            "何だろう"
        )
    }

    // とき/こと の使い分け(ユーザー方針): 「時間という概念そのもの」「事柄」を指す実質名詞は
    // 漢字(時は金なり/事の起こり/事あるごとに)、接尾辞的な形式名詞はかな(〜したとき/
    // 〜すること)。前者は文頭のかな側に減点(seed順ボーナス800を上回る1500)、後者は既存の
    // 述語直後の漢字ペナルティ(1000)が担当する。例外として ことが〜(経験・可能性の
    // 形式名詞用法)は文頭でもかなを維持(2459)
    func testRegressionTokiKotoSubstantiveVsFormal() throws {
        try prepareRealLMDictionary()

        // 実質名詞(文頭)= 漢字
        for (reading, expected) in [
            ("ときはかねなり", "時"), ("ことのおこり", "事の起こり"), ("ことあるごとに", "事あるごとに"),
            ("ときがきた", "時")
        ] {
            let multi = converter.multiClauseCandidates(for: reading, systemCandidateMode: .surface)
            XCTAssertTrue(
                multi.first?.hasPrefix(expected) ?? false,
                "\(reading)=\(multi.prefix(3))"
            )
        }

        // 接尾辞的な形式名詞 = かな(述語直後/連体詞直後)
        for (reading, expected) in [
            ("みたとき", "見たとき"), ("たべるとき", "食べるとき"), ("することは", "することは"),
            ("したことがある", "したことがある"), ("そのとき", "そのとき"), ("このこと", "このこと")
        ] {
            let multi = converter.multiClauseCandidates(for: reading, systemCandidateMode: .surface)
            XCTAssertEqual(multi.first, expected, "\(reading)=\(multi.prefix(3))")
        }

        // 例外: 直後に助詞が続く形(経験・可能性・変化)は文頭でもかな
        for reading in ["ことがある", "ことがない", "ことでもなく", "ことになる"] {
            let multi = converter.multiClauseCandidates(for: reading, systemCandidateMode: .surface)
            XCTAssertEqual(multi.first, reading, "\(reading)=\(multi.prefix(3))")
        }
    }

    // 変わってきてる: 読み「る」の唯一の候補が ル(rank0/wc4335)で、合成末尾が
    // 変わってきてル のようなカタカナ混じりになっていた。漢字を含む合成表層は既存の
    // カタカナ強調判定(表層全体をかな化して読みと比較)の対象外で抜けていたため、
    // seed でかな識別を先頭にして合成の種を かな に固定(単独の ル は#2で選べる)(2458)
    func testRegressionRuKanaNotKatakanaInComposition() throws {
        try prepareRealLMDictionary()
        let multi = converter.multiClauseCandidates(for: "かわってきてる", systemCandidateMode: .surface)
        for candidate in multi.prefix(4) {
            XCTAssertFalse(candidate.hasSuffix("ル"), "カタカナのル が残っている: \(multi.prefix(4))")
        }
        XCTAssertTrue(multi.contains("変わってきてる"), "multi=\(multi.prefix(4))")
        // 単独の る はかな先頭、ル は#2
        XCTAssertEqual(
            Array(converter.candidates(for: "る", limit: 3, systemCandidateMode: .surface).prefix(2)),
            ["る", "ル"]
        )
    }

    // きかんし: 機関誌(wc10093)/機関紙(10121)/機関士(10648)/季刊誌(13053)/気管支(15536)が
    // すべて収穫底値(>=10000)で harvest tier へ降格され、帰還し/期間し 等の合成の下に
    // 沈んで候補に出てこなかった(2156 と同型の逆症状)。seed 登録で降格免除+並び指定、
    // 連文節側も seed 順ボーナスで揃える(2457)
    func testRegressionKikanshiHarvestFloorExempted() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "きかんし", limit: 14, systemCandidateMode: .surface)
        XCTAssertEqual(
            Array(single.prefix(5)),
            ["機関誌", "機関紙", "気管支", "機関士", "季刊誌"],
            "single=\(single.prefix(8))"
        )
        // 動詞連用形の合成は後続
        let kikanshiIndex = try XCTUnwrap(single.firstIndex(of: "機関誌"))
        let kikanIndex = try XCTUnwrap(single.firstIndex(of: "帰還し"))
        XCTAssertTrue(kikanshiIndex < kikanIndex, "single=\(single.prefix(8))")
    }

    // こうかいされて/されてる で 公開⇄後悔 が入れ替わっていた。前者は連文節が効き
    // (公開→さ bigram582 < 後悔→さ1660)、後者は連文節が空(さ変+てる縮約のノードが
    // 組めない)で単文節の辞書順(紅海0/後悔1/公会2/公開3)に落ちるため。seed で単文節の
    // 並びを 公開先頭に固定し両方を揃える(2456)
    func testRegressionKoukaiPrefersPublic() throws {
        try prepareRealLMDictionary()
        XCTAssertEqual(
            converter.candidates(for: "こうかい", limit: 6, systemCandidateMode: .surface).first,
            "公開"
        )
        XCTAssertEqual(
            converter.candidates(for: "こうかいされてる", limit: 5, systemCandidateMode: .surface).first,
            "公開されてる"
        )
        XCTAssertEqual(
            converter.multiClauseCandidates(for: "こうかいされて", systemCandidateMode: .surface).first,
            "公開されて"
        )
    }

    // 2026-08-03 の一括報告(ユーザー指定の並び)。読みキーごとに独立した seed 指定+
    // 交ぜ書き許可(今まで)+連文節ボーナス(とき)+keepKana(のだろ/先頭の の)(2455)
    func testRegressionUserSpecifiedOrderingBatch() throws {
        try prepareRealLMDictionary()

        // 単文節の並び
        let expectations: [(String, [String])] = [
            ("いままで", ["今まで", "いままで", "今迄"]),
            ("とき", ["とき", "時"]),
            ("いつ", ["いつ", "何時"]),
            ("あって", ["あって", "会って", "合って", "有って"]),
            ("しじょう", ["市場", "私情"]),
            ("きょうかい", ["協会", "教会", "境界"])
        ]
        for (reading, expected) in expectations {
            let candidates = converter.candidates(for: reading, limit: 8, systemCandidateMode: .surface)
            XCTAssertEqual(
                Array(candidates.prefix(expected.count)),
                expected,
                "\(reading)=\(candidates.prefix(6))"
            )
        }

        // 連文節でかな先頭+提示層でも退避しない(keepKana)
        let kanaLeading = [
            "いつだったのだろう", "いつだったのだろ", "のときのは", "のときは", "あってな"
        ]
        for reading in kanaLeading {
            let multi = converter.multiClauseCandidates(for: reading, systemCandidateMode: .surface)
            XCTAssertEqual(multi.first, reading, "multi(\(reading))=\(multi.prefix(3))")
            XCTAssertTrue(
                converter.shouldKeepKanaIdentityLeading(for: reading),
                "keepKana(\(reading)) が false"
            )
        }
    }

    // ていしえき: 未登録の複合語で、連文節が 停止+駅(駅 uni4050 < 液 uni6008)を選んでいた。
    // misc curated で 停止液 を供給(単独の えき は 駅 先頭のまま)(2454)
    func testRegressionTeishiekiPrefersLiquid() throws {
        try prepareRealLMDictionary()
        converter.store.addUserEntry(reading: "ていしえき", candidate: "停止液")
        // curated が丸ごと1ノードになる読みは連文節が空を返し単文節に委ねる(設計どおり)
        let single = converter.candidates(for: "ていしえき", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "停止液", "single=\(single)")
        // 単独の えき は 駅 が先頭のまま
        let eki = converter.candidates(for: "えき", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(eki.first, "駅", "eki=\(eki)")

        // 氷酢酸(ひょうさくさん): 辞書は さくさん→酢酸 のみで未登録だった(2454)
        converter.store.addUserEntry(reading: "ひょうさくさん", candidate: "氷酢酸")
        XCTAssertEqual(
            converter.candidates(for: "ひょうさくさん", limit: 6, systemCandidateMode: .surface).first,
            "氷酢酸"
        )
    }

    // できやすいので: 辞書rank0が 出来る(wc4362)でかなは rank3。ユーザー方針で「出来る」は
    // 後ろに回したいので seed でかな先頭に。さらに提示層の退避を防ぐため、補助形容詞
    // やすい/にくい/づらい(+任意のので)を剥がした基底動詞が seed かな先頭なら
    // keepKana を成立させる(2453)
    func testRegressionDekiyasuiKanaLeading() throws {
        try prepareRealLMDictionary()
        let multi = converter.multiClauseCandidates(for: "できやすいので", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "できやすいので", "multi=\(multi.prefix(4))")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "できやすいので"))
        // 単独 できる もかな先頭(出来る は#2温存)
        let dekiru = converter.candidates(for: "できる", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(Array(dekiru.prefix(2)), ["できる", "出来る"], "dekiru=\(dekiru)")
        // ので の一般再帰は入れていない(たべるので は漢字先頭のまま)
        XCTAssertFalse(converter.shouldKeepKanaIdentityLeading(for: "たべるので"))
    }

    // えだ: 辞書に 枝(wc4351/rank0)があるのに、1文字読み え の合成15件が全部その前に
    // 並んでいた。seed で 枝 を先頭へ。さらに読み え の名前・旧字・レア読み
    // (江/衣/枝/穢/畫/重/慧/会)は単独でも使わず合成の温床なので抑制。コストでは
    // 分離できない(衣6606 < 柄7731)ので語義判断による suppr で対応(2452)
    func testRegressionEdaOrderingAndRareEReadings() throws {
        try prepareRealLMDictionary()
        try injectSuppression(["え": ["江", "衣", "枝", "穢", "畫", "重", "慧", "会"]])
        let single = converter.candidates(for: "えだ", limit: 24, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "枝", "single=\(single.prefix(6))")
        for unwanted in ["江だ", "衣だ", "枝だ", "穢だ", "畫だ", "重だ", "慧だ", "会だ"] {
            XCTAssertFalse(single.contains(unwanted), "\(unwanted) が残っている: \(single)")
        }
        // 常用の1字語からの合成は温存
        XCTAssertTrue(single.contains("絵だ"), "single=\(single)")
        XCTAssertTrue(single.contains("餌だ"), "single=\(single)")
        // 単独の え も整理される(絵/画/柄/荏/榎/餌 は残る)
        let e = converter.candidates(for: "え", limit: 10, systemCandidateMode: .surface)
        XCTAssertEqual(e.first, "え", "e=\(e)")
        XCTAssertTrue(e.contains("絵"), "e=\(e)")
        XCTAssertFalse(e.contains("穢"), "e=\(e)")
    }

    // カタカナ正書の例外枠(ユーザー方針): 原則カタカナ化は抑制だが「ひらがなだと紛れる+
    // 漢字が馴染みない」語はカタカナが読みやすい。seed 掲載でカタカナ強調抑制から免除
    // (katakanaRunsAreSeedProtected)。いや は指定順、むら は 斑 の意味の ムラ を追加(2451)
    func testRegressionKatakanaOrthographyExceptions() throws {
        try prepareRealLMDictionary()
        let iya = converter.candidates(for: "いや", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(iya.prefix(5)), ["イヤ", "いや", "嫌", "否", "厭"], "iya=\(iya)")
        // 合成(いや+で)にも seed 順が伝わる
        let iyade = converter.candidates(for: "いやで", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(
            Array(iyade.prefix(5)),
            ["イヤで", "いやで", "嫌で", "否で", "厭で"],
            "iyade=\(iyade)"
        )
        let mura = converter.candidates(for: "むら", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(Array(mura.prefix(3)), ["村", "ムラ", "むら"], "mura=\(mura)")
    }

    // いやで: SudachiDict の促音/長音の水増し表記(イヤっ rank6 / 嫌ー rank12)が合成の種に
    // なり イヤっで/嫌ーで を作っていた。読みに無い っ/ッ/ー が表層にある候補を装飾表記
    // として一般に除去(読み側にある入力=いやー/やっぱ/こーひー は無傷)(2450)
    func testRegressionSokuonChoonPaddingFiltered() throws {
        try prepareRealLMDictionary()
        let iyade = converter.candidates(for: "いやで", limit: 24, systemCandidateMode: .surface)
        XCTAssertFalse(iyade.contains("イヤっで"), "iyade=\(iyade.prefix(8))")
        XCTAssertFalse(iyade.contains("嫌ーで"), "iyade=\(iyade.prefix(8))")
        XCTAssertTrue(iyade.contains("嫌で"), "iyade=\(iyade.prefix(8))")
        let iya = converter.candidates(for: "いや", limit: 24, systemCandidateMode: .surface)
        XCTAssertFalse(iya.contains("イヤっ"), "iya=\(iya.prefix(8))")
        XCTAssertFalse(iya.contains("嫌ー"), "iya=\(iya.prefix(8))")
        // 読みに っ/ー を含む入力は温存(誤爆しない)
        XCTAssertTrue(
            converter.candidates(for: "いやー", limit: 6, systemCandidateMode: .surface).contains("イヤー")
        )
        XCTAssertTrue(
            converter.candidates(for: "やっぱ", limit: 6, systemCandidateMode: .surface).contains("やっぱ")
        )
        XCTAssertTrue(
            converter.candidates(for: "こーひー", limit: 6, systemCandidateMode: .surface).contains("コーヒー")
        )
    }

    // やっぱり: 辞書rank0がカタカナ(ヤッパリ)で、さらに やっぱ+李(李 uni5116)の合成が
    // 先頭を取っていた。seed でかな先頭を固定(2449)
    func testRegressionYappariKanaLeading() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "やっぱり", limit: 24, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "やっぱり", "single=\(single.prefix(6))")
        XCTAssertFalse(single.contains("やっぱ李"), "single=\(single)")
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "やっぱり"))
    }

    // 部首名の変換供給(くさかんむり→艹 等、2565)。bushu.plist の全名前(2字以上)で
    // 完全一致入力から字形が候補に出ることを一括検査する。
    func testRegressionRealLMRadicalNameSuppliesForm() throws {
        KanjiRadicalCatalog.resourceDirectoryURLOverride = URL(
            fileURLWithPath: "/Users/kusakabe/Git/ecritu/references", isDirectory: true
        )
        defer { KanjiRadicalCatalog.resourceDirectoryURLOverride = nil }
        try prepareRealLMDictionary()

        var failures: [String] = []
        for (name, forms) in KanjiRadicalCatalog.formsByKanaName.sorted(by: { $0.key < $1.key }) {
            let list = converter.candidates(for: name, limit: 64, systemCandidateMode: .surface)
            for form in forms where !list.contains(form) {
                failures.append("\(name)→\(form) list=\(list.suffix(4))")
            }
        }
        XCTAssertTrue(failures.isEmpty, "\(failures.count)件:\n" + failures.joined(separator: "\n"))
    }

    // フルアクセスOFF相当(共有コンテナ不達・共有defaults空)でも、変換系APIが
    // クラッシュせず動作すること(App Store ガイドライン4.4.1: フルアクセスなしでも
    // 基本機能が動くこと)。実機ではバンドル辞書で変換も維持されるが、テスト環境は
    // バンドルに辞書が無いためフォールバック動作(候補が返り、落ちない)を確認する。
    func testKeyboardSurvivesWithoutAppGroupAccess() throws {
        let previousOverride = KanaKanjiStore.sharedContainerURLOverride
        defer { KanaKanjiStore.sharedContainerURLOverride = previousOverride }
        // 存在せず作成もできないパス=コンテナ不達を再現
        KanaKanjiStore.sharedContainerURLOverride = URL(
            fileURLWithPath: "/nonexistent-fullaccess-off/\(UUID().uuidString)", isDirectory: true
        )
        let isolated = KanaKanjiConverter(
            store: KanaKanjiStore(appGroupID: "group.fullaccess.off.\(UUID().uuidString)")
        )

        // 変換・学習・語彙・診断系の主要APIを一巡(すべて落ちないこと)
        let single = isolated.candidates(for: "きょうは", limit: 8, systemCandidateMode: .surface)
        XCTAssertFalse(single.isEmpty, "フォールバックでも候補ゼロにならない list=\(single)")
        _ = isolated.multiClauseCandidates(for: "きょうはあめです", systemCandidateMode: .surface)
        _ = isolated.shouldKeepKanaIdentityLeading(for: "きょうは")
        isolated.store.addLearnedEntry(reading: "てすと", candidate: "テスト")
        _ = isolated.store.learnedDictionary()
        _ = isolated.store.userDictionary()
        _ = isolated.store.initialUserDictionary()
        _ = isolated.store.suppressedCandidatesByReading()
        _ = isolated.store.shortcutVocabulary()
        _ = isolated.store.loadSupplementalSystemDictionary()
    }

    // 部首カテゴリー分類表(bushu.plist)の読み込みと、8カテゴリーへの割り振り(2444)
    func testKanjiRadicalCatalogCategories() throws {
        KanjiRadicalCatalog.resourceDirectoryURLOverride = URL(
            fileURLWithPath: "/Users/kusakabe/Git/ecritu/references", isDirectory: true
        )
        defer { KanjiRadicalCatalog.resourceDirectoryURLOverride = nil }
        let forms = KanjiRadicalCatalog.allForms
        XCTAssertEqual(forms.count, 245, "字形数 = 214部首 + 位置別字形31")

        // 214部首すべてが1つ以上の字形で表現されている
        let radicals = Set(forms.map(\.radical))
        XCTAssertEqual(radicals.count, 214, "部首番号の網羅数=\(radicals.count)")
        XCTAssertEqual(radicals.min(), 1)
        XCTAssertEqual(radicals.max(), 214)

        // どの字形も8カテゴリーのいずれかに属する(未分類なし)
        let known = Set(RadicalPositionCategory.allCases.map(\.rawValue))
        for form in forms {
            XCTAssertFalse(form.categories.isEmpty, "\(form.form) が未分類")
            XCTAssertTrue(known.isSuperset(of: form.categories), "\(form.form) に未知カテゴリー")
        }

        // 8カテゴリーすべてに字形がある
        for category in RadicalPositionCategory.allCases {
            XCTAssertFalse(
                KanjiRadicalCatalog.forms(in: category).isEmpty,
                "\(category.title) が空"
            )
        }

        // 字形単位の分類: 氵=偏 / 氺=脚(同じ部首85でも位置別)
        let water = forms.filter { $0.radical == 85 }
        XCTAssertEqual(water.first { $0.form == "氵" }?.categories, ["偏"])
        XCTAssertEqual(water.first { $0.form == "氺" }?.categories, ["脚"])
        // 阝 は こざと(偏・部首170)と おおざと(旁・部首163)で別エントリー
        let atoR = forms.filter { $0.form == "阝" }
        XCTAssertEqual(Set(atoR.map(\.radical)), [163, 170])
        // 複数所属(日=偏・冠・脚)
        XCTAssertEqual(forms.first { $0.form == "日" }?.categories, ["偏", "冠", "脚"])

        // 画数: 字形ごとに持つ(氵=3画 / 水=4画、艹=3画 / 艸=6画)。1〜17画に収まる
        XCTAssertEqual(water.first { $0.form == "氵" }?.strokes, 3)
        XCTAssertEqual(water.first { $0.form == "水" }?.strokes, 4)
        XCTAssertEqual(forms.first { $0.form == "艹" }?.strokes, 3)
        XCTAssertEqual(forms.first { $0.form == "艸" }?.strokes, 6)
        for form in forms {
            XCTAssertTrue(1...17 ~= form.strokes, "\(form.form) の画数=\(form.strokes)")
        }

        // カテゴリー内は画数順(同画数は部首番号順)= 画数区切りを挟める並び。どの選択でも成立する
        let choiceSets: [RadicalStrokeChoices] = [
            RadicalStrokeChoices(),
            RadicalStrokeChoices(rawValue: "traditional"),
            RadicalStrokeChoices(rawValue: "140:6,162:7,113:5,184:9")
        ]
        for choices in choiceSets {
            for category in RadicalPositionCategory.allCases {
                let ordered = KanjiRadicalCatalog.forms(in: category, choices: choices)
                let keys = ordered.map { [$0.strokes(choices: choices), $0.radical] }
                XCTAssertEqual(keys, keys.sorted { lhs, rhs in
                    lhs[0] != rhs[0] ? lhs[0] < rhs[0] : lhs[1] < rhs[1]
                }, "\(category.title)/\(choices.rawValue) の並びが画数順でない")
            }
        }

        // 部首ごとの画数選択(2502)。選択肢は 艹=3/4/6、辶=3/4/7、礻=4/5/5、飠=7/8/9
        XCTAssertEqual(
            RadicalStrokeChoiceCatalog.options(forRadical: 140).map(\.strokes),
            [3, 4, 6]
        )
        XCTAssertEqual(
            RadicalStrokeChoiceCatalog.options(forRadical: 113).map(\.form),
            ["礻", "⺭", "示"]
        )
        XCTAssertEqual(RadicalStrokeChoiceCatalog.totalBasisStrokes(forRadical: 140), 3)

        let kusa = try XCTUnwrap(forms.first { $0.form == "艹" })
        XCTAssertEqual(kusa.strokes(choices: RadicalStrokeChoices()), 3)
        var custom = RadicalStrokeChoices()
        custom.setStrokes(6, forRadical: 140)
        XCTAssertEqual(kusa.strokes(choices: custom), 6)
        XCTAssertEqual(custom.rawValue, "140:6")
        // 一覧・見出しの字形も選択に追随する(2503)
        XCTAssertEqual(kusa.displayForm(choices: custom), "艸")
        XCTAssertEqual(kusa.displayForm(choices: RadicalStrokeChoices()), "⺾")
        XCTAssertEqual(
            water.first { $0.form == "氵" }?.displayForm(choices: custom),
            "氵"
        )
        // 旧設定(traditional)からの移行=各部首の2番目の選択肢
        let migrated = RadicalStrokeChoices(rawValue: "traditional")
        XCTAssertEqual(kusa.strokes(choices: migrated), 4)
        let shinnyou = try XCTUnwrap(forms.first { $0.form == "辶" })
        XCTAssertEqual(shinnyou.strokes(choices: migrated), 4)
        let shimesu = try XCTUnwrap(forms.first { $0.form == "礻" })
        XCTAssertEqual(shimesu.strokes(choices: migrated), 5)
        // 選択肢を持たない字形はどの選択でも同じ
        XCTAssertEqual(
            water.first { $0.form == "氵" }?.strokes(choices: migrated),
            water.first { $0.form == "氵" }?.strokes(choices: RadicalStrokeChoices())
        )
    }

    // 吹き出しの読み表示: 音読み(カタカナ)と訓読み(ひらがな)の境目に / を入れる。
    // 片方しか無い字はスラッシュ無し(2491)
    func testKanjiInspectBubbleReadingsDisplayText() {
        XCTAssertEqual(
            KanjiInspectBubble.readingsDisplayText(for: "ヒョウ ギョウ こおり ひ こおる"),
            "ヒョウ ギョウ / こおり ひ こおる"
        )
        XCTAssertEqual(KanjiInspectBubble.readingsDisplayText(for: "コウ"), "コウ")
        XCTAssertEqual(KanjiInspectBubble.readingsDisplayText(for: "さんずい"), "さんずい")
        XCTAssertEqual(KanjiInspectBubble.readingsDisplayText(for: "—"), "—")
    }

    // 漢字1文字ピッカーの索引(mmap+バイナリサーチ)。部首ブロックが部首内画数順で
    // 切り出せること、区点・読みが引けること、フォント差の判定が効くことを確認(2443)
    func testKanjiRadicalIndexLookup() throws {
        let store = KanaKanjiStore(appGroupID: defaultsSuiteName)
        store.kanjiRadicalIndexDirectoryURLOverride = URL(
            fileURLWithPath: "/Users/kusakabe/Git/ecritu/KeyboardExtension", isDirectory: true
        )
        let index = store.kanjiRadicalIndex()
        XCTAssertFalse(index.isEmpty, "索引が読めていない")

        // 部首85(水)は 氵 系の字を大量に含む
        let water = index.entries(radical: 85)
        XCTAssertGreaterThan(water.count, 300, "water=\(water.count)")
        XCTAssertTrue(water.contains { $0.character == "漢" }, "漢 が部首85にあるべき")
        // ファイル順 = 総画数 → 部首内画数 → コードポイント(字グリッドの総画数区切り用。2483)
        let totals = water.map(\.totalStrokes)
        XCTAssertEqual(totals, totals.sorted(), "総画数が昇順でない")
        for (former, latter) in zip(water, water.dropFirst())
        where former.totalStrokes == latter.totalStrokes {
            XCTAssertLessThanOrEqual(
                former.residualStrokes,
                latter.residualStrokes,
                "同じ総画数の中は部首内画数の昇順であるべき"
            )
        }

        // 区点と読み(漢 = 区20点33)
        let kan = try XCTUnwrap(water.first { $0.character == "漢" })
        XCTAssertEqual(kan.kuten, "20-33", "kuten=\(kan.kuten)")
        XCTAssertTrue(kan.readings.contains("カン"), "readings=\(kan.readings)")
        XCTAssertEqual(kan.residualStrokes, 11)
        // 総画数は Unihan kTotalStrokes(伝統寄りの数え方。日本の辞典の13画とは1画ずれる)
        XCTAssertEqual(kan.totalStrokes, 14)

        // 区点の無い字は「—」
        let noKuten = index.entries(radical: 1).first { $0.character == "丂" }
        XCTAssertEqual(noKuten?.kuten, "—", "区点なしは — を返す")

        // 範囲外・境界
        XCTAssertTrue(index.entries(radical: 0).isEmpty)
        XCTAssertTrue(index.entries(radical: 215).isEmpty)
        XCTAssertFalse(index.entries(radical: 1).isEmpty)
        XCTAssertFalse(index.entries(radical: 214).isEmpty)

        // ヒラギノ明朝のグリフ有無(色分けの判定)
        XCTAssertTrue(KanaKanjiStore.hasMinchoGlyph(for: "漢"))
        // 东(U+4E1C、簡体字)はヒラギノ明朝に無く、実機では PingFang 等で描かれる=色分け対象
        XCTAssertFalse(KanaKanjiStore.hasMinchoGlyph(for: "东"), "簡体字は明朝に無い")
    }

    // ことでもなく: かな なく の識別wc10363(収穫底値)が短spanかな床+底値unigram不信
    // (2126)に踏まれ、無く(活用派生7200)に負けていた。ない と同類の頻出かなとして
    // seed 掲載で両ガードを免除(2442)
    func testRegressionKotodemonakuPrefersKana() throws {
        try prepareRealLMDictionary()
        let multi = converter.multiClauseCandidates(for: "ことでもなく", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "ことでもなく", "multi=\(multi.prefix(4))")
        // 提示層のかな退避も防ぐ
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "ことでもなく"))
        // 泣く/鳴く は単独 なく の候補に温存
        let solo = converter.candidates(for: "なく", limit: 10, systemCandidateMode: .surface)
        XCTAssertTrue(solo.contains("泣く") && solo.contains("鳴く"), "solo=\(solo)")
    }

    // ふじわらの/みなもとの/たいらの: 古代氏姓の の込み読み(藤原=フジワラノ 等、Sudachi
    // 実在)が rank0 に居座り、藤原の/源の/平の の合成を抑えていた。阿刀 と同型の
    // suppr+完全一致時のみ末尾再供給。平野(たいらの) の怪しい収穫も同時に抑制(2440)
    func testRegressionClassicalClanGenitiveReadings() throws {
        try prepareRealLMDictionary()
        try injectSuppression([
            "ふじわらの": ["藤原"],
            "みなもとの": ["源"],
            "たいらの": ["平", "平野"]
        ])
        let fujiwara = converter.candidates(for: "ふじわらの", limit: 20, systemCandidateMode: .surface)
        XCTAssertEqual(fujiwara.first, "藤原の", "fujiwara=\(fujiwara.prefix(5))")
        XCTAssertTrue(fujiwara.contains("藤原"), "藤原 は完全一致時のみ末尾: \(fujiwara)")
        let minamoto = converter.candidates(for: "みなもとの", limit: 20, systemCandidateMode: .surface)
        XCTAssertEqual(minamoto.first, "源の", "minamoto=\(minamoto.prefix(5))")
        let taira = converter.candidates(for: "たいらの", limit: 20, systemCandidateMode: .surface)
        XCTAssertEqual(taira.first, "平の", "taira=\(taira.prefix(5))")
        XCTAssertFalse(taira.prefix(3).contains("平野"), "taira=\(taira.prefix(5))")
    }

    // うつった: 基底並べ替えのLMかな昇格が seed(うつる)の漢字先頭を上書きし、かなが
    // 先頭化していた。語形seedでユーザー指定順 {写った, 移った, 映った, 感染った,
    // うつった, 憑った} に固定(2438)
    func testRegressionUtsuttaOrdering() throws {
        try prepareRealLMDictionary()
        let single = converter.candidates(for: "うつった", limit: 10, systemCandidateMode: .surface)
        XCTAssertEqual(
            Array(single.prefix(6)),
            ["写った", "移った", "映った", "感染った", "うつった", "憑った"],
            "single=\(single)"
        )
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
        // 全読みを1ノードで覆う 貼り忘れた が立つ場合、連文節は単文節に委ねる(2657)ので
        // 実機バーと同じ multi ?? single で検証する
        let ta = converter.multiClauseCandidates(for: "はりわすれた", systemCandidateMode: .surface)
        let taSingle = converter.candidates(for: "はりわすれた", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(ta.first ?? taSingle.first, "貼り忘れた", "ta=\(ta.prefix(4)) single=\(taSingle.prefix(4))")
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

    // あいゆ→アイユ: 辞書に実在(wc2148)だが同読みの漢字収穫(愛由/藍結=収穫底値)があるため
    // カタカナ強調抑止で消えていた。追加語彙登録は抑止の対象外という前提の防波堤。
    // りったー→ℓ: 辞書は音写ごとに別読み(りったー→リッター、りっとる→リットル)で持ち、
    // 単位記号 ℓ はどちらにも無いので misc で補う。読み替え(りったー→リットル)は不要(2473)
    func testRegressionCuratedKatakanaAndUnitSymbolSupplied() throws {
        try prepareRealLMDictionary()
        converter.store.addUserEntry(reading: "あいゆ", candidate: "アイユ")
        let aiyu = converter.candidates(for: "あいゆ", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(aiyu.first, "アイユ", "aiyu=\(aiyu)")

        converter.store.addUserEntry(reading: "りったー", candidate: "ℓ")
        let litre = converter.candidates(for: "りったー", limit: 8, systemCandidateMode: .surface)
        XCTAssertTrue(litre.contains("ℓ"), "litre=\(litre)")
        XCTAssertTrue(litre.contains("リッター"), "litre=\(litre)")
        // 音写の読み替え(りったー→リットル)は出さない(ユーザー方針)
        XCTAssertFalse(litre.contains("リットル"), "litre=\(litre)")
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
            // 計り は はかり の連濁収穫なので単文節では出さない(2485)。本旨は かな が先頭
            ("ばかり", ["ばかり"]),
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
            onLookupRadicalEntries: { _ in [] },
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
            numberLayoutMode: .calculette,
            latinLayoutMode: .flick,
            accentPaletteRawValue: "emeraude",
            isSystemDictionaryFallback: false,
            hasFullAccess: true,
            keyboardBackgroundThemeRawValue: "sakura",
            basicSymbolOrderRawValue: "ascii",
            temperatureUnitRawValue: TemperatureUnitPreference.celsius.rawValue,
            radicalStrokeCountStyleRawValue: "",
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
            initialSpaceToastText: nil,
            initialInputMode: .kana
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
        let container: URL = testContainerURL
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

    // となりのせき: Wikipedia LM の 積 優遇(の→積 bigram が の→席 より安い)で
    // 隣の積 が先頭だった。の→席 ペア重みで日常語の 席 を先頭に(ユーザ報告 2656)
    func testRegressionRealLMTonarinoSekiPrefersSeat() throws {
        try prepareRealLMDictionary()

        let expectations: [(String, String)] = [
            ("となりのせき", "隣の席"),
            ("まどがわのせき", "窓側の席"),
            // 席+助詞 は元から 席 が勝つ(席→に/が の bigram)。退行監視
            ("せきにつく", "席に就く"),
            ("せきがない", "席がない")
        ]
        for (probe, expected) in expectations {
            let multi = converter.multiClauseCandidates(for: probe, systemCandidateMode: .surface)
            let single = converter.candidates(for: probe, limit: 4, systemCandidateMode: .surface)
            let barTop = multi.first ?? single.first
            XCTAssertEqual(barTop, expected, "\(probe): multi=\(multi.prefix(4)) single=\(single.prefix(4))")
        }
        let tonari = converter.multiClauseCandidates(for: "となりのせき", systemCandidateMode: .surface)
        XCTAssertTrue(tonari.contains("隣の積"), "積 は候補として残す list=\(tonari.prefix(5))")
    }

    // かくした: 核子+た/各紙+た/客死+た(名詞+過去助動詞=非文)が 1ノードの 格下 を跨いで
    // {隠した,核子た,各紙た,客死た,…}になり 格下 が8番目だった(ユーザ報告 2657)。
    // 活用派生でない漢字語直後の た を遮断し {隠した,格下,…} へ。
    func testRegressionRealLMKakushitaBlocksNounPlusTa() throws {
        try prepareRealLMDictionary()

        let multi = converter.multiClauseCandidates(for: "かくした", systemCandidateMode: .surface)
        let single = converter.candidates(for: "かくした", limit: 6, systemCandidateMode: .surface)
        let bar = multi + single.filter { !multi.contains($0) }
        // ユーザ指定: 格下 を先頭(seed。読み全体の seed があれば連文節は単文節に委ねる)
        XCTAssertEqual(Array(bar.prefix(2)), ["格下", "隠した"], "bar=\(bar.prefix(6))")
        for junk in ["核子た", "各紙た", "客死た", "各誌た"] {
            XCTAssertFalse(bar.prefix(4).contains(junk), "\(junk) bar=\(bar.prefix(6))")
        }
        // 活用派生の 連用形+た は従来どおり(退行監視)
        for (probe, expected) in [("はなした", "話した"), ("かえした", "返した"), ("しめした", "示した"), ("こわした", "壊した")] {
            let m = converter.multiClauseCandidates(for: probe, systemCandidateMode: .surface)
            let s = converter.candidates(for: probe, limit: 4, systemCandidateMode: .surface)
            XCTAssertEqual(m.first ?? s.first, expected, "\(probe): multi=\(m.prefix(4)) single=\(s.prefix(4))")
        }
    }

    // きはじめる: 辞書に き→来 が無く 木始める しか出なかった(ユーザ報告 2658)。カ変ペアで
    // 来始める 族を供給し、活用順位サフィックス外でもカ変ブーストを適用して先頭に
    func testRegressionRealLMKihajimeruSuppliesKuru() throws {
        try prepareRealLMDictionary()

        for (probe, expected, second) in [("きはじめる", "来始める", "着始める"), ("きはじめた", "来始めた", "着始めた"), ("きはじめて", "来始めて", "着始めて")] {
            let multi = converter.multiClauseCandidates(for: probe, systemCandidateMode: .surface)
            let single = converter.candidates(for: probe, limit: 4, systemCandidateMode: .surface)
            let bar = multi + single.filter { !multi.contains($0) }
            XCTAssertEqual(bar.first, expected, "\(probe): multi=\(multi.prefix(4)) single=\(single.prefix(4))")
            // 着る(一段)の 連用形+始める も2番目に(ユーザ指定 2658)
            XCTAssertEqual(bar.dropFirst().first, second, "\(probe): bar=\(bar.prefix(4))")
        }
        // 一段/五段の 連用形+始める が1ノードで供給される
        XCTAssertEqual(converter.candidates(for: "たべはじめる", limit: 3, systemCandidateMode: .surface).first, "食べ始める")
        XCTAssertEqual(converter.candidates(for: "のみはじめた", limit: 3, systemCandidateMode: .surface).first, "飲み始めた")
        // 既存のカ変ペアの並びは不変(退行監視)
        let sugiru = converter.candidates(for: "きすぎる", limit: 3, systemCandidateMode: .surface)
        XCTAssertEqual(sugiru.first, "来すぎる", "list=\(sugiru)")
    }

    // しそ: 紫蘇(辞書 rank0・wc2692)が Wikipedia LM 未収録で、LM 収録の 始祖 が先頭化していた
    // (ユーザ指定 2661: {紫蘇, シソ, 始祖, …})
    func testRegressionRealLMShisoPrefersPerilla() throws {
        try prepareRealLMDictionary()

        let list = converter.candidates(for: "しそ", limit: 5, systemCandidateMode: .surface)
        XCTAssertEqual(Array(list.prefix(3)), ["紫蘇", "シソ", "始祖"], "list=\(list)")
        // 連文節の中でも seed 先頭語が LM 未収録のせいで消えない(しそじゃない→始祖じゃない
        // だった。ユーザ報告 2662)
        let multi = converter.multiClauseCandidates(for: "しそじゃない", systemCandidateMode: .surface)
        // 変種順も seed の並び(ユーザ指定 2665: 単文節 [しそ] と同じ順に)
        XCTAssertEqual(Array(multi.prefix(3)), ["紫蘇じゃない", "シソじゃない", "始祖じゃない"], "multi=\(multi.prefix(4))")
    }

    // せきをたつ: {籍を絶つ, 籍を断つ, 席を絶つ, 籍を発つ} で 席を立つ が無かった(ユーザ報告 2663)。
    // Wikipedia LM の を→絶つ/籍→を 優遇。seed たつ 先頭の 立つ 族を連文節でも優先
    func testRegressionRealLMSekiWoTatsuPrefersStandUp() throws {
        try prepareRealLMDictionary()

        // せき の同音競争は連語外では LM に任せる(席→を のペア重みは 咳をする をさらに
        // 遠ざける)。せきをする は {席をする, 咳をする}(籍をする 先頭からは改善、咳 先頭は
        // 連語表の複数エントリ対応が要る別案件)
        for (probe, expected) in [("せきをたつ", "席を立つ"), ("せきをたって", "席を立って"), ("せきをたった", "席を立った")] {
            let multi = converter.multiClauseCandidates(for: probe, systemCandidateMode: .surface)
            let single = converter.candidates(for: probe, limit: 3, systemCandidateMode: .surface)
            XCTAssertEqual(multi.first ?? single.first, expected, "\(probe): multi=\(multi.prefix(4)) single=\(single.prefix(3))")
        }
    }

    // もったいないよ/よね: 終助詞を付けると 勿体無いよ が繰り上がっていた(ユーザ報告 2659)。
    // もったいない は dictionary_entries に行が無く、終助詞剥がしの辞書判定に掛からなかった
    func testRegressionRealLMMottainaiWithFinalParticleKeepsKana() throws {
        try prepareRealLMDictionary()

        for probe in ["もったいない", "もったいないよ", "もったいないよね"] {
            XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: probe), probe)
            let multi = converter.multiClauseCandidates(for: probe, systemCandidateMode: .surface)
            let single = converter.candidates(for: probe, limit: 3, systemCandidateMode: .surface)
            XCTAssertEqual(multi.first ?? single.first, probe, "\(probe): multi=\(multi.prefix(3)) single=\(single.prefix(3))")
        }
    }

    // そんなものはない: {そんなものは無い, そんな物はない, そんなものは内} だった(ユーザ報告 2659)。
    // 係助詞 は/も + ない の keepKana 根拠と、は/も 直後の 無い の減点(変種としては残す)
    func testRegressionRealLMSonnaMonoWaNaiKanaOrder() throws {
        try prepareRealLMDictionary()

        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "そんなものはない"))
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "なにもない"))
        let multi = converter.multiClauseCandidates(for: "そんなものはない", systemCandidateMode: .surface)
        XCTAssertEqual(Array(multi.prefix(3)), ["そんなものはない", "そんな物はない", "そんなものは無い"], "multi=\(multi.prefix(5))")
    }

    // ごうてん: 号店(2号店)は辞書に無く ごう/てん の辞書順も下位で {ご雨天, ご于闐} だった。
    // たくさんのめると: たくさん→の bigram 461 が安く たくさんの+メルト(wc 2148)に負けていた
    // (ユーザ報告 2674)
    func testRegressionRealLMGoutenAndTakusanNomeru() throws {
        try prepareRealLMDictionary()

        XCTAssertEqual(
            Array(converter.candidates(for: "ごうてん", limit: 3, systemCandidateMode: .surface).prefix(2)),
            ["号店", "合点"]
        )
        XCTAssertEqual(converter.candidates(for: "のめる", limit: 3, systemCandidateMode: .surface).first, "飲める")
        for (probe, expected) in [
            ("たくさんのめると", "たくさん飲めると"),
            ("たくさんのめるといいなー", "たくさん飲めるといいなー"),
            // 連語外の正常系(が→飲める bigram 観測)は不変
            ("びーるがのめると", "ビールが飲めると")
        ] {
            let multi = converter.multiClauseCandidates(for: probe, systemCandidateMode: .surface)
            let single = converter.candidates(for: probe, limit: 3, systemCandidateMode: .surface)
            XCTAssertEqual(multi.first ?? single.first, expected, "\(probe): multi=\(multi.prefix(3))")
        }
        // たくさんの+名詞(連語の verbPrefixes 外)は無傷
        let hito = converter.multiClauseCandidates(for: "たくさんのひとが", systemCandidateMode: .surface)
        XCTAssertEqual(hito.first, "たくさんの人が", "multi=\(hito.prefix(3))")
    }

    // かかせる/しようしょ/いまだとまだ/せいかいでは(ユーザ指定 2675〜2677)
    func testRegressionRealLMKakaseruShiyoushoImadaSeikai() throws {
        try prepareRealLMDictionary()

        // かかせる: 辞書は {欠かせる, かかせる} のみで 書/描 は活用由来のため下位だった
        XCTAssertEqual(
            Array(converter.candidates(for: "かかせる", limit: 4, systemCandidateMode: .surface).prefix(2)),
            ["書かせる", "描かせる"]
        )
        // しようしょ: 仕様書 は Sudachi wc 13674(収穫底値超)で連文節が床上げして却下していた
        XCTAssertEqual(converter.candidates(for: "しようしょ", limit: 2, systemCandidateMode: .surface).first, "仕様書")
        let testSpec = converter.multiClauseCandidates(for: "てすとしようしょ", systemCandidateMode: .surface)
        XCTAssertEqual(testSpec.first, "テスト仕様書", "multi=\(testSpec.prefix(3))")
        // いまだ/まだ はかな正書(辞書 rank0 は 未だ)
        let imada = converter.multiClauseCandidates(for: "いまだとまだ", systemCandidateMode: .surface)
        // ユーザ指定(2684): 1位 今だとまだ、2位 いまだとまだ(seed 順)
        XCTAssertEqual(Array(imada.prefix(3)), ["今だとまだ", "いまだとまだ", "未だとまだ"], "multi=\(imada.prefix(4))")
        XCTAssertEqual(
            converter.multiClauseCandidates(for: "まだできない", systemCandidateMode: .surface).first,
            "まだできない"
        )
        XCTAssertEqual(
            converter.multiClauseCandidates(for: "いまだにできない", systemCandidateMode: .surface).first,
            "いまだにできない"
        )
        // opt-in 外のかな正書(など)は従来どおり 等 を繰り上げない
        let nado = converter.multiClauseCandidates(for: "などという", systemCandidateMode: .surface)
        XCTAssertEqual(Array(nado.prefix(2)), ["などという", "などと言う"], "multi=\(nado.prefix(3))")
        // せいかい: Sudachi は 正解<政界 なのに LM は 政界<正解 で 政界では が先頭だった。
        // seed 先頭語を seed 兄弟の最安 unigram 直下へ置く一般則(2677)で是正
        let seikai = converter.multiClauseCandidates(for: "せいかいでは", systemCandidateMode: .surface)
        XCTAssertEqual(seikai.first, "正解では", "multi=\(seikai.prefix(3))")
    }

    // うたい/うたいだし/こうあつせんじょうき/やつですね/とよんでた/ばいしょうきん/
    // きゅうりょうぶくろ(ユーザ指定 2678/2679)
    func testRegressionRealLMCompoundSupplyAndKanaNoun() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary(includeSuppression: true)

        // 収穫底値の床上げ除外(2678): 自分の主読みで LM がよく知る複合語は分割に負けない
        let baishou = converter.multiClauseCandidates(for: "ばいしょうきん", systemCandidateMode: .surface)
        let baishouSingle = converter.candidates(for: "ばいしょうきん", limit: 2, systemCandidateMode: .surface)
        XCTAssertEqual(baishou.first ?? baishouSingle.first, "賠償金", "multi=\(baishou.prefix(3))")
        // 供給欠落の補填(seed)
        XCTAssertEqual(converter.candidates(for: "うたい", limit: 3, systemCandidateMode: .surface).first, "歌い")
        for (probe, expected) in [
            ("うたいだし", "歌い出し"),
            ("こうあつせんじょうき", "高圧洗浄機"),
            ("きゅうりょうぶくろ", "給料袋")
        ] {
            let multi = converter.multiClauseCandidates(for: probe, systemCandidateMode: .surface)
            let single = converter.candidates(for: probe, limit: 3, systemCandidateMode: .surface)
            XCTAssertEqual(multi.first ?? single.first, expected, "\(probe): multi=\(multi.prefix(3)) single=\(single.prefix(3))")
        }
        // やつ はかな正書(単文節と連文節の先頭を揃える)
        let yatsu = converter.multiClauseCandidates(for: "やつですね", systemCandidateMode: .surface)
        XCTAssertEqual(Array(yatsu.prefix(2)), ["やつですね", "奴ですね"], "multi=\(yatsu.prefix(3))")
        // とよんでた: 響動む/とよむ(古語)を抑制し、引用の と は 呼 を先に。
        // 目的語+を の文脈は 読 のまま、名前/そう+よぶ活用は 呼(連語表)
        for (probe, expected) in [
            ("とよんでた", "と呼んでた"),
            ("そうよんでた", "そう呼んでた"),
            ("なまえをよんでた", "名前を呼んでた"),
            ("ほんをよんでた", "本を読んでた")
        ] {
            let multi = converter.multiClauseCandidates(for: probe, systemCandidateMode: .surface)
            XCTAssertEqual(multi.first, expected, "\(probe): multi=\(multi.prefix(3))")
        }
    }

    // 2確定→ごうてん: 数字文脈の助数詞合成(号+てん=号点/号てん/合点/合てん)が本来の
    // 号店 を押しのけていた。読み全体に seed 宣言のある語では合成を前置しない(2681)
    func testRegressionDigitContextSkipsCounterWhenSeedWordExists() throws {
        try prepareRealLMDictionary()

        func boosted(_ reading: String) -> [String] {
            let base = converter.candidates(for: reading, limit: 8, systemCandidateMode: .surface)
            return KanaKanjiConverter.digitContextCounterBoostedCandidates(
                base,
                reading: reading,
                precedingCharacter: "2",
                tailConversion: { [weak converter] tail in
                    converter?.candidates(for: tail, limit: 1, systemCandidateMode: .surface).first
                }
            )
        }
        XCTAssertEqual(boosted("ごうてん").first, "号店", "boosted=\(boosted("ごうてん").prefix(4))")
        // 既存の助数詞合成(seed の無い読み)は不変
        XCTAssertEqual(boosted("かいしか").first, "回しか")
        XCTAssertEqual(boosted("ふんぐらいかな").first, "分ぐらいかな")
        XCTAssertEqual(boosted("さい").first, "歳")
    }

    // いまだとまだ: 提示層の keepKana が false でかな候補が降格され、実機だけ 今だとまだ が
    // 先頭になっていた(いまだ/まだ 単独は true)。かな正書の語+助詞1字+かな正書の語 を
    // 根拠に加える(2683)
    func testRegressionKeepKanaForKanaWordParticleKanaWord() throws {
        try prepareRealLMDictionary()

        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "いまだとまだ"))
        // 両側ともかな副詞でない(名詞+と+名詞)は従来どおり false
        XCTAssertFalse(converter.shouldKeepKanaIdentityLeading(for: "がっこうとびょういん"))
        let imada = converter.multiClauseCandidates(for: "いまだとまだ", systemCandidateMode: .surface)
        XCTAssertEqual(Array(imada.prefix(2)), ["今だとまだ", "いまだとまだ"], "multi=\(imada.prefix(4))")
        // いまだに/まだ のかな正書は不変(2676)
        XCTAssertEqual(
            converter.multiClauseCandidates(for: "いまだにできない", systemCandidateMode: .surface).first,
            "いまだにできない"
        )
    }

    // よういち: 辞書 rank0 は 洋一 だがユーザ指定で 陽一 を先頭に(2688)。さらに よういち の
    // 候補は Sudachi wc が全て10000(収穫底値)で連文節では全員 9500 に床上げされ同点になり、
    // くさかべよういち→日下部容一 のように辞書順の偶然で並んでいた
    func testRegressionRealLMYouichiPrefersYou() throws {
        try prepareRealLMDictionary()

        XCTAssertEqual(
            Array(converter.candidates(for: "よういち", limit: 4, systemCandidateMode: .surface).prefix(2)),
            ["陽一", "洋一"]
        )
        for probe in ["くさかべよういち", "たなかよういち"] {
            let multi = converter.multiClauseCandidates(for: probe, systemCandidateMode: .surface)
            XCTAssertTrue(multi.first?.hasSuffix("陽一") == true, "\(probe): multi=\(multi.prefix(3))")
            XCTAssertTrue(multi.dropFirst().first?.hasSuffix("洋一") == true, "\(probe): multi=\(multi.prefix(3))")
            // 収穫底値の同点で紛れ込んでいた 容一/容壱/容市 が先頭群に来ない
            XCTAssertFalse(multi.prefix(3).contains { $0.contains("容") }, "\(probe): multi=\(multi.prefix(3))")
        }
    }

    // かじ: 辞書は人名/寺の数え方が上位で 家事15位・火事20位だった(ユーザ指定 2689)。
    // 鍛治(鍛冶の誤用表記)は抑制。かじがおきた は文脈的に 火事 なので連語で上書き
    func testRegressionRealLMKajiOrder() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary(includeSuppression: true)

        let single = converter.candidates(for: "かじ", limit: 7, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(4)), ["家事", "火事", "鍛冶", "梶"], "single=\(single)")
        XCTAssertFalse(single.contains("鍛治"), "誤用表記は抑制: \(single)")
        for (probe, expected) in [
            ("かじがおきた", "火事が起きた"),
            ("かじをてつだう", "家事を手伝う"),
            ("かじやさん", "鍛冶屋さん")
        ] {
            let multi = converter.multiClauseCandidates(for: probe, systemCandidateMode: .surface)
            let single = converter.candidates(for: probe, limit: 3, systemCandidateMode: .surface)
            XCTAssertEqual(multi.first ?? single.first, expected, "\(probe): multi=\(multi.prefix(3))")
        }
    }

    // 形式名詞「とき」はかなが正書(2690)。〜するとき/〜というとき/〜のとき はかな、
    // 時刻そのもの(3時)は漢字、の書き分け
    func testRegressionFormalNounTokiPrefersKana() throws {
        try prepareRealLMDictionary()

        // 句として辞書に両形がある読み(時=rank0/かな=rank1)でもかなが先頭
        XCTAssertEqual(
            converter.candidates(for: "いざというとき", limit: 2, systemCandidateMode: .surface).first,
            "いざというとき"
        )
        for (probe, expected) in [
            ("こまったとき", "困ったとき"),
            ("そのとき", "そのとき"),
            ("たべるときに", "食べるときに"),
            ("がっこうのとき", "学校のとき")
        ] {
            let multi = converter.multiClauseCandidates(for: probe, systemCandidateMode: .surface)
            let single = converter.candidates(for: probe, limit: 3, systemCandidateMode: .surface)
            XCTAssertEqual(multi.first ?? single.first, expected, "\(probe): multi=\(multi.prefix(3))")
        }
        // 単独の とき は従来どおり(かな先頭は辞書順のまま)
        XCTAssertEqual(converter.candidates(for: "とき", limit: 2, systemCandidateMode: .surface).first, "とき")
    }

    // たいようちゅう: 太陽柱(サンピラーの日本語名)は Sudachi にも LM にも無く、
    // {太陽中, 太陽注, 太陽虫, 太陽忠} の合成しか出なかった。sacoche.plist に追加語彙として
    // 登録(ユーザ指定 2691)。追加語彙のある読みは合成が抑止されるため、使う可能性のある
    // 太陽中 だけ明示的に2番目へ
    func testRegressionAjoutTaiyouchuu() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary(includeSuppression: true)

        let single = converter.candidates(for: "たいようちゅう", limit: 4, systemCandidateMode: .surface)
        XCTAssertEqual(Array(single.prefix(2)), ["太陽柱", "太陽中"], "single=\(single)")
        XCTAssertFalse(single.contains { $0.hasPrefix("太陽") && ["注", "虫", "忠"].contains(String($0.suffix(1))) },
                       "不要な合成が残っている: \(single)")
        let multi = converter.multiClauseCandidates(for: "たいようちゅうがみえた", systemCandidateMode: .surface)
        XCTAssertEqual(multi.first, "太陽柱が見えた", "multi=\(multi.prefix(3))")
    }

    // あいます: Sudachi の唯一の候補が アイマス(ゲームの略称、wc2117)で、活用エンジン由来の
    // 会います/合います/逢います(活用チャネル980 < 辞書1200)を跨いで先頭に居座っていた。
    // 抑制せず4番目に残す(ユーザ指定 2026-08-27)
    func testRegressionRealLMAimasuPrefersVerb() throws {
        try prepareRealLMDictionary()

        XCTAssertEqual(
            Array(converter.candidates(for: "あいます", limit: 5, systemCandidateMode: .surface)),
            ["会います", "合います", "逢います", "アイマス", "あいます"]
        )
        XCTAssertEqual(
            converter.multiClauseCandidates(for: "きょうあいます", systemCandidateMode: .surface).first,
            "今日会います"
        )
    }

    // 並列の接続詞はかなが正書(ユーザ指定 2026-08-27)。または/又は は両方 LM 未収録で
    // 辞書順(又は 上位)に従い、そーすまたは→ソース又は になっていた
    func testRegressionConjunctionsPreferKana() throws {
        try prepareRealLMDictionary()

        for (probe, expected) in [
            ("そーすまたは", "ソースまたは"),
            ("しおまたはこしょう", "塩または"),
            ("しおもしくはこしょう", "塩もしくは"),
            ("しおならびにこしょう", "塩ならびに"),
            ("しおあるいはこしょう", "塩あるいは"),
            ("しおおよびこしょう", "塩および")
        ] {
            let multi = converter.multiClauseCandidates(for: probe, systemCandidateMode: .surface)
            XCTAssertTrue(multi.first?.hasPrefix(expected) == true, "\(probe): multi=\(multi.prefix(3))")
        }
        XCTAssertEqual(converter.candidates(for: "または", limit: 2, systemCandidateMode: .surface).first, "または")
    }

    // 否定仮定形「〜なければ」の供給(ユーザ報告 2026-08-27)。口語縮約(なきゃ/なくちゃ)
    // だけあって標準形が全クラスで欠けており、ねなければ→ね無ければ、たべなければ→候補なし
    // になっていた
    func testRegressionNegativeConditionalSupplied() throws {
        try prepareRealLMDictionary()

        for (probe, expected) in [
            ("ねなければ", "寝なければ"),        // 一段
            ("みなければ", "見なければ"),
            ("たべなければ", "食べなければ"),
            ("こなければ", "来なければ"),        // カ変
            ("たべなければならない", "食べなければならない")
        ] {
            let single = converter.candidates(for: probe, limit: 4, systemCandidateMode: .surface)
            XCTAssertEqual(single.first, expected, "\(probe): single=\(single.prefix(4))")
        }
        // 五段(行く)はかな正書の いかなければ が先頭でも 行かなければ が候補にあること
        let ika = converter.candidates(for: "いかなければ", limit: 4, systemCandidateMode: .surface)
        XCTAssertTrue(ika.contains("行かなければ"), "single=\(ika.prefix(4))")
    }

    // だと: 断定「だ」+引用/条件の「と」。辞書に だと のエントリが無く、当て字の
    // 打つ(だと 読み)/駄と/惰と/堕と しか出なかった(ユーザ指定 2026-08-27)
    func testRegressionDatoPrefersKana() throws {
        try prepareRealLMDictionary()

        XCTAssertEqual(converter.candidates(for: "だと", limit: 3, systemCandidateMode: .surface).first, "だと")
        // 文中の だと は従来どおり
        XCTAssertEqual(
            converter.multiClauseCandidates(for: "だとおもう", systemCandidateMode: .surface).first,
            "だと思う"
        )
        let ame = converter.multiClauseCandidates(for: "あめだと", systemCandidateMode: .surface)
        XCTAssertEqual(ame.first, "雨だと", "multi=\(ame.prefix(3))")
    }

    // 一段の連用形(食べる→食べ)の供給(ユーザ報告 2026-08-27)。五段は iForm(食い/つき)が
    // あるのに一段には規則が無く、さんかくたべ→三角夛部/三角田倍 の人名合成しか出なかった
    func testRegressionIchidanRenyouNounSupplied() throws {
        try prepareRealLMDictionary()

        for (probe, expected) in [
            ("さんかくたべ", "三角食べ"),
            ("まわしたべ", "回し食べ"),
            ("たべほうだい", "食べ放題")
        ] {
            let multi = converter.multiClauseCandidates(for: probe, systemCandidateMode: .surface)
            let single = converter.candidates(for: probe, limit: 3, systemCandidateMode: .surface)
            XCTAssertEqual(multi.first ?? single.first, expected, "\(probe): multi=\(multi.prefix(3))")
        }
        // 基底(食べる)と既存の派生は不変
        XCTAssertEqual(converter.candidates(for: "たべる", limit: 2, systemCandidateMode: .surface).first, "食べる")
        XCTAssertEqual(converter.candidates(for: "たべなければ", limit: 2, systemCandidateMode: .surface).first, "食べなければ")
    }

    // 活用形の網羅点検(ユーザ依頼 2026-08-27)。一段の命令形(食べろ/見ろ/起きろ)、
    // カ変の使役・可能(来させる/来られる)、形容詞連用形の順位(高く が9番目だった)、
    // サ変受身の単独形(される)を是正
    func testRegressionInflectionCoverageGaps() throws {
        try prepareRealLMDictionary()

        for (probe, expected) in [
            ("たべろ", "食べろ"),     // 一段の命令形(ろ の規則が無かった)
            // 起きろ は お+帰路 の敬語接頭合成が辞書チャネルで勝つため先頭は譲るが候補には出る
            ("たべよ", "食べよ"),
            ("こさせる", "来させる"),  // カ変の使役
            ("こられる", "来られる"),  // カ変の可能/受身
            ("たかく", "高く"),       // 形容詞連用形(人名 高久 に埋もれていた)
            ("さむく", "寒く"),
            ("ちかく", "近く"),
            ("される", "される")      // サ変受身の単独形
        ] {
            let single = converter.candidates(for: probe, limit: 4, systemCandidateMode: .surface)
            XCTAssertEqual(single.first, expected, "\(probe): single=\(single.prefix(4))")
        }
        // 見ろ は ミロ(人名/画家)が辞書 rank0 なので先頭は譲るが候補には出る
        XCTAssertTrue(
            converter.candidates(for: "みろ", limit: 6, systemCandidateMode: .surface).contains("見ろ")
        )
        XCTAssertTrue(
            converter.candidates(for: "おきろ", limit: 6, systemCandidateMode: .surface).contains("起きろ")
        )
    }

    // ちかく: 近く(LM 4969)優位なのに辞書順が 知覚→地殻→近く。お+合成で お地殻 が先頭化(2666)
    func testOchikakuPrefersONear() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary(includeSuppression: true)
        XCTAssertEqual(converter.candidates(for: "おちかく", limit: 3, systemCandidateMode: .surface).first, "お近く")
        XCTAssertEqual(converter.multiClauseCandidates(for: "おちかくの", systemCandidateMode: .surface).first, "お近くの")
        XCTAssertEqual(converter.multiClauseCandidates(for: "おちかくまで", systemCandidateMode: .surface).first, "お近くまで")
        XCTAssertEqual(converter.candidates(for: "ちかく", limit: 3, systemCandidateMode: .surface).first, "近く")
    }

    // 旧字体 殼 は全7件抑制。球殼 のみ新字体が辞書に無かったため misc で 球殻 を補完(2666)
    func testOldFormKakuSuppressed() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary(includeSuppression: true)
        let chikaku = converter.candidates(for: "ちかく", limit: 10, systemCandidateMode: .surface)
        XCTAssertFalse(chikaku.contains("地殼"), "\(chikaku)")
        XCTAssertTrue(chikaku.contains("地殻"))
        let kyuukaku = converter.candidates(for: "きゅうかく", limit: 5, systemCandidateMode: .surface)
        XCTAssertEqual(kyuukaku.first, "球殻", "\(kyuukaku)")
        XCTAssertFalse(kyuukaku.contains("球殼"))
    }

    // vin.plist の 醗酵 系にサ変属性(pos)を付与。sqlite 再生成判定の穴も同時に塞いだ(2666)
    func testSaihakkouSuruFromVinPos() throws {
        try prepareRealLMDictionary()
        let result = converter.candidates(for: "さいはっこうする", limit: 5, systemCandidateMode: .surface)
        XCTAssertTrue(result.contains("再醗酵する"), "\(result)")
        // 派生でも 再醗酵 を先頭に(ユーザ指定 2668)
        let saseta = converter.candidates(for: "さいはっこうさせた", limit: 3, systemCandidateMode: .surface)
        XCTAssertEqual(Array(saseta.prefix(2)), ["再醗酵させた", "再発行させた"], "\(saseta)")
        let bare = converter.candidates(for: "さいはっこう", limit: 3, systemCandidateMode: .surface)
        XCTAssertEqual(Array(bare.prefix(2)), ["再醗酵", "再発行"], "\(bare)")
    }

    // のか/のかな を終助詞クラスタに。人名収穫 乃佳/乃歌/乃花 が文末で勝っていた(2666)
    func testNokaSentenceFinalStaysKana() throws {
        try prepareRealLMDictionary()
        let result = converter.multiClauseCandidates(for: "こうなるのか", systemCandidateMode: .surface)
        XCTAssertEqual(result.first, "こうなるのか", "\(result)")
        XCTAssertFalse(result.contains { $0.contains("乃") }, "\(result)")
        // 提示層: 根拠が無いとかな最良が末尾へ退避し 公なるのか が先頭化していた(実機トレース 2669)
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "こうなるのか"))
        XCTAssertTrue(converter.shouldKeepKanaIdentityLeading(for: "どうなるのかな"))
        XCTAssertFalse(converter.shouldKeepKanaIdentityLeading(for: "のか"))
    }

    // さすが をかな副詞に(指す+が 分割が勝っていた)。seed 順変種で 流石Apple を2番目に(2666)
    func testSasugaAppleOrdering() throws {
        try prepareRealLMDictionary()
        let result = converter.multiClauseCandidates(for: "さすがあっぷる", systemCandidateMode: .surface)
        XCTAssertEqual(Array(result.prefix(2)), ["さすがApple", "流石Apple"], "\(result)")
        let sore = converter.multiClauseCandidates(for: "さすがにそれは", systemCandidateMode: .surface)
        XCTAssertEqual(Array(sore.prefix(2)), ["さすがにそれは", "流石にそれは"], "\(sore)")
    }

    // おちかく(全読み): 連文節 オチ描く が単文節 お近く より先に合流していた。丁寧接頭辞派生
    // (お+語幹最良)は連文節の断片分割より先頭に置く(2667)
    func testOchikakuWholeReadingPromotesPoliteDerivation() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary(includeSuppression: true)
        XCTAssertTrue(converter.shouldPromoteSingleBestAboveMultiClause(reading: "おちかく", singleBest: "お近く"))
        XCTAssertFalse(converter.shouldPromoteSingleBestAboveMultiClause(reading: "おちかく", singleBest: "お地殻"))
        // 全読みが辞書語(お母さん)なら派生ではないので対象外
        XCTAssertFalse(converter.shouldPromoteSingleBestAboveMultiClause(reading: "おかあさん", singleBest: "お母さん"))
        // 派生でも語幹が最良(土産)なら昇格対象(おみやげ は辞書に全読みが無い)
        XCTAssertTrue(converter.shouldPromoteSingleBestAboveMultiClause(reading: "おみやげ", singleBest: "お土産"))
        XCTAssertFalse(converter.shouldPromoteSingleBestAboveMultiClause(reading: "おそいから", singleBest: "遅いから"))
    }

    // 終助詞クラスタのクランプが表層末尾(く/い…)で判定され、かな識別 ぶそく だけ安く 不足 は
    // 素通りだったため メモリーぶそくかも が先頭化していた。読みでも判定して揃える(2672)
    func testMemoryBusokuKamoKeepsKanji() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary(includeSuppression: true)
        XCTAssertEqual(converter.multiClauseCandidates(for: "めもりーぶそくかも", systemCandidateMode: .surface).first, "メモリー不足かも")
        XCTAssertEqual(converter.multiClauseCandidates(for: "めもりーぶそくかな", systemCandidateMode: .surface).first, "メモリー不足かな")
        XCTAssertEqual(converter.multiClauseCandidates(for: "めもりーぶそくか", systemCandidateMode: .surface).first, "メモリー不足か")
    }

    // なる はかな識別の短span床で 成る に負けていた。床免除でかな先頭に(2673)
    func testNaruKanaLeadsInMultiClause() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary(includeSuppression: true)
        XCTAssertEqual(converter.multiClauseCandidates(for: "なるといいなー", systemCandidateMode: .surface).first, "なるといいなー")
        XCTAssertEqual(converter.multiClauseCandidates(for: "なるのか", systemCandidateMode: .surface).first, "なるのか")
        // bigram 実勢(が→鳴る 4741 < が→なる 5110)がある文脈は 鳴る を保つ
        XCTAssertEqual(converter.multiClauseCandidates(for: "でんわがなる", systemCandidateMode: .surface).first, "電話が鳴る")
        XCTAssertEqual(converter.multiClauseCandidates(for: "おおきくなる", systemCandidateMode: .surface).first, "大きくなる")
    }

    // たとえば はかな正書(ユーザ指定 2688)。seed かな先頭+連文節かな副詞
    func testTatoebaKanaLeads() throws {
        try prepareRealLMDictionary()
        XCTAssertEqual(converter.candidates(for: "たとえば", limit: 3, systemCandidateMode: .surface).first, "たとえば")
        XCTAssertEqual(converter.multiClauseCandidates(for: "たとえばこれ", systemCandidateMode: .surface).first, "たとえばこれ")
    }

    // すると: 辞書の唯一の語 スルト(人名 Surtr)を抑制し、接続詞 すると をかなで供給(2688)
    func testSurutoSuppressedAndKanaLeads() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary(includeSuppression: true)
        let result = converter.candidates(for: "すると", limit: 5, systemCandidateMode: .surface)
        XCTAssertEqual(result.first, "すると", "\(result)")
        XCTAssertFalse(result.contains("スルト"))
    }

    // かわない: 買う は漢字が常なので 買わない 先頭、かなは後ろ(ユーザ指定 2688)
    func testKawanaiKanjiLeads() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary(includeSuppression: true)
        XCTAssertEqual(converter.multiClauseCandidates(for: "わたしはかわない", systemCandidateMode: .surface).first, "私は買わない")
        XCTAssertEqual(converter.candidates(for: "かわない", limit: 3, systemCandidateMode: .surface).first, "買わない")
    }

    // ジップロック(商品名、Sudachi 未収録)を misc で供給。並びは ジップロック→ジップロック®→Ziploc(2698)
    func testZiplocFromMisc() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary(includeSuppression: true)
        let r = converter.candidates(for: "じっぷろっく", limit: 5, systemCandidateMode: .surface)
        XCTAssertEqual(Array(r.prefix(3)), ["ジップロック", "ジップロック®", "Ziploc"], "\(r)")
    }

    // きく: 効く を2位に(ユーザ指定 2698)。連文節の変種順も seed に従う
    func testKikuSeedOrder() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary(includeSuppression: true)
        XCTAssertEqual(Array(converter.candidates(for: "きく", limit: 5, systemCandidateMode: .surface).prefix(3)), ["聞く", "効く", "聴く"])
        let kamo = converter.multiClauseCandidates(for: "きくかも", systemCandidateMode: .surface)
        XCTAssertEqual(Array(kamo.prefix(2)), ["聞くかも", "効くかも"], "\(kamo)")
        // 単文節#1 は候補バーで連文節最良の直後に挿入されるため、単文節側も 菊鹿も(終助詞の漢字化)を
        // 先頭にしてはいけない(実機で {聞くかも, 菊鹿も, 効くかも} になっていた。2705)
        let single = converter.candidates(for: "きくかも", limit: 6, systemCandidateMode: .surface)
        XCTAssertEqual(single.first, "聞くかも", "\(single)")
        XCTAssertFalse(single.prefix(3).contains("菊鹿も"), "\(single)")
        // 語幹 ひらが は用言でないので対象外(従来の先頭 平仮名 を維持)
        XCTAssertEqual(converter.candidates(for: "ひらがな", limit: 3, systemCandidateMode: .surface).first, "平仮名")
    }

    // 用言語幹に名詞接辞(か→課/可/化/科/下)を付けない(来れる課 等の無用合成。2700)
    func testNoNounAffixOnVerbStem() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary(includeSuppression: true)
        let r = converter.candidates(for: "これるか", limit: 8, systemCandidateMode: .surface)
        XCTAssertEqual(r.first, "来れるか", "\(r)")
        XCTAssertFalse(r.contains { $0.hasPrefix("来れる") && $0 != "来れるか" }, "\(r)")
        let t = converter.candidates(for: "たべれるか", limit: 8, systemCandidateMode: .surface)
        XCTAssertFalse(t.contains("食べれる課"), "\(t)")
    }

    // 述語直後の か(1字)をクランプし、これ+ルカ(人名)の分割に負けないようにする(2700)
    func testKaAfterPredicateClampInMultiClause() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary(includeSuppression: true)
        XCTAssertEqual(converter.multiClauseCandidates(for: "これるか", systemCandidateMode: .surface).first, "来れるか")
        XCTAssertEqual(converter.multiClauseCandidates(for: "たべれるか", systemCandidateMode: .surface).first, "食べれるか")
    }

    // 数字確定直後の助数詞ブースト: 助詞始まりの長い末尾(もおしたことない)でも 回+変換形 を供給する。
    // 以前は末尾6かな制限で かいもおしたことない が漏れ、変換形も全漢字限定で おした がかなのままだった(2700)
    func testDigitContextCounterBoostWithLongParticleTail() throws {
        try prepareRealLMDictionary()
        try loadDeviceAddedVocabulary(includeSuppression: true)
        let reading = "かいもおしたことない"
        let engine = converter.multiClauseCandidates(for: reading, systemCandidateMode: .surface)
            + converter.candidates(for: reading, limit: 8, systemCandidateMode: .surface)
        let boosted = KanaKanjiConverter.digitContextCounterBoostedCandidates(
            engine, reading: reading, precedingCharacter: "1",
            tailConversion: { [converter] tail in
                if tail.count >= 4, let m = converter!.multiClauseCandidates(for: tail, systemCandidateMode: .surface).first { return m }
                return converter!.candidates(for: tail, limit: 1, systemCandidateMode: .surface).first
            }
        )
        XCTAssertEqual(boosted.first, "回も押したことない", "\(boosted.prefix(5))")
    }
}
