import Foundation

// 連文節変換(案A1: 語コスト版ビタビ)。単語 n-gram LM(unigram/bigram+backoff)で
// ラティスを組み、Viterbi 最尤経路を候補にする。コスト定数・ノード・補助判定も本ファイルに集約。
extension KanaKanjiConverter {
    // MARK: - 連文節変換(案A1: 語コスト版ビタビ)
    //
    // 読み全体を文節ラティスに分割し、Sudachi 語コスト最小の経路を DP(ビタビ)で選ぶ。
    // 連接コスト(matrix.def)は未導入(=案A2)。連接が無いため各文節は「最安の変換」を
    // 独立に選べば最適で、経路コスト = Σ(語コスト) + 文節数ペナルティ。
    //   - 語コストは store.wordCosts(word_costs テーブル, Sudachi連接エントリ由来)。
    //   - コスト不明な文節(活用形・追加語彙・かな素通り)は candidates() の top1 を
    //     既定コストで補完。かな素通りは強く減点。
    // 呼び出し側でフラグ(isMultiClauseConversionEnabled)により on/off する。
    static let multiClauseMinReadingCount = 4
    static let multiClauseMaxReadingCount = 40      // これを超える長文は連文節DPを回さない(計算量抑制)
    static let multiClauseMaxSegmentReadingCount = 12
    static let multiClauseSupplementMaxLen = 8
    // 1文節あたり列挙する変換候補数。Sudachi の語コストは動詞が単漢字名詞より高く付く
    // 傾向があり、8 では かく の 書く(13位)のような頻出動詞がラティスから漏れて
    // 各のが 等の名詞ジャンクしか組めなくなるため 14 に拡大(順位付けは LM bigram が行う
    // ので、列挙が広がっても最良経路の質は落ちない)。
    static let multiClauseTopK = 14
    static let multiClauseInflectionTopK = 3        // 活用派生ノードの1文節あたり上限
    // 活用派生ノードが LM 未収録(普通)のときの専用コスト。LM コーパスは Sudachi A単位で
    // 活用形を「買っ+た」に分割するため、正しい活用表層(買った)は unigram に無い。
    // 一律 dictUnknown(8700)だと LM 収録済みのかな断片チェーン(かっ7079+た2102)や
    // word_costs ジャンク(カッタ7715/多部田7884)に負けるので、unigram 最大(8139)より
    // 下に置き「文法的に検証済みの派生は既知のレア語より僅かに信頼する」とする。
    static let multiClauseInflectionDerivedOOVCost = 7200
    // 格助詞の直後に来る活用派生ノード(に置かない/を書かない 等)の incoming OOV 割引。
    // 格助詞の後は述語が続くのが文法的に自然だが、活用形は LM 未収録が多く bigram も無いため
    // 7200 固定だと 高頻度語の断片チェーン(に+おか+ない+と 計~7538)に負ける。
    // 格助詞直後に限り 5000 へ下げ、断片チェーンに勝てるようにする(名詞は影響なし)。
    static let multiClauseInflectionAfterParticleCost = 5000
    static let multiClauseCaseParticleSurfaces: Set<String> = [
        "に", "を", "が", "へ", "と", "で", "は", "も", "から", "まで", "より"
    ]
    // 単独のバラ母音(あいうえお)。学習した接頭語(酒造所=しゅぞうじょ)より1モーラ長い入力
    // (しゅぞうじょう)で、末尾に余る母音がこれ。漢字語直後の単独バラ母音ノードは余りモーラの
    // 誤分割なので落とす。助詞(が/を/か/わ/の…)や助動詞(た/て/だ)は母音でないため保護される。
    static let multiClauseDanglingVowelKana: Set<String> = ["あ", "い", "う", "え", "お"]
    // 複合助詞(格助詞+係助詞は/も)。Sudachi は「に+は」に分割するため word_costs に無く、
    // 連文節では単位ノードを組めない。結果「べんりにはなったね」が「便利に放ったね」に化ける
    // (はなった が動詞1ノードに吸われ、に→は の1遷移分だけ得をする)。素通り(7000/字)で
    // 既にノード自体は列挙されるので、ここでは (1) 安価にクランプして単位ノードを競争させ、
    // (2) 直後の述語に格助詞と同じ活用割引を効かせる。文頭(BOS 直後)はクランプせず、
    // 「でも→デモ」「では→出は」等の文頭巻き添えを防ぐ。
    static let multiClauseCompoundParticles: Set<String> = [
        "には", "にも", "では", "でも", "とは", "とも",
        "へは", "へも", "からは", "からも", "までは", "までも", "よりは"
    ]
    // 複合助詞ノードのクランプ後コスト。名詞→格助詞の実 bigram(便利→に=1427 等)より
    // 安くして単位経路を勝たせる一方、極端に安くして別解を歪めない中庸値。
    static let multiClauseCompoundParticleCost = 1200
    // 名詞化節(準体助詞の+係/格助詞)。述語形(動詞終止形/形容詞/タ形)直後の
    // のが/のは/のを/のも/のに は「炊くのが好き」型の名詞化でかな単位が正書。Sudachi は
    // の+が に分割するため word_costs に無く、動詞→の の bigram も未観測が多い
    // (Wikipedia は名詞文体)ため、名詞側だけ bigram(宅→の 1484)で安くなり
    // 宅のが好き/核のが好き 等へ逆転する。述語形の直後に限り単位ノードを安価に
    // クランプする(名詞直後はクランプせず通常経路のまま)。
    static let multiClauseNominalizerSurfaces: Set<String> = ["のが", "のは", "のを", "のも", "のに"]
    static let multiClauseNominalizerAfterPredicateCost = 1200
    // 説明・詠嘆の終助詞連結「のね/のよ」。用言の辞書形述語(重い 等、inflection_classes
    // 登録)直後に限り単位ノードとして安価にする(おもいのね→重いのね)。名詞(思い)は
    // 表層末尾が い でも辞書形述語ではないため対象外 — の+ね 分割の従来経路のまま
    // (思いの外/思いのまま 等の名詞+の を歪めない)。
    static let multiClauseExplanatoryFinalSurfaces: Set<String> = ["のね", "のよ"]
    // かな表記が主の述語動詞の識別。inflection_classes に (かな, かな) 登録が無く辞書形述語
    // 判定が false になるが、のね/のよ クランプ・床免除の対象として辞書形述語扱いにする
    // (あるのね→有るのね 逆転の防止)。漢字が主の動詞(買う/見る 等)は含めない。
    static let multiClauseKanaPredicateIdentities: Set<String> = ["ある"]

    // 同音異義 あう の出し分け(best-effort): 前の名詞が人物なら 会う、それ以外は 合う を優先。
    // 辞書に動物性タグが無く助詞跨ぎ bigram も無いため、名詞の人物性を語彙+敬称接尾で近似する。
    // あう の活用読み(会う/合う が競合する形)。この読みのノードのみ調整対象。
    static let multiClauseAuVerbReadings: Set<String> = [
        "あう", "あった", "あって", "あい", "あいたい", "あいました", "あいます",
        "あわない", "あえる", "あえば", "あおう", "あわ", "あえ", "あいそう", "あってる"
    ]
    // 人物・役柄の名詞(会う を取りやすい)。網羅は不可能なので高頻度語を近似列挙。
    static let multiClausePersonNounSurfaces: Set<String> = [
        "人", "友達", "友人", "彼", "彼女", "彼氏", "皆", "みんな", "皆さん", "家族",
        "先生", "父", "母", "親", "兄", "姉", "弟", "妹", "息子", "娘", "子", "子供",
        "客", "お客", "自分", "僕", "私", "俺", "君", "あなた", "誰", "仲間", "恋人",
        "上司", "部下", "同僚", "先輩", "後輩", "夫", "妻", "社長", "部長", "課長",
        "祖父", "祖母", "叔父", "叔母", "医者", "店員", "神", "人々", "みな"
    ]
    // 人物を示す敬称・呼称の接尾(名前+これ で人物と判断)。
    static let multiClausePersonHonorificSuffixes: [String] = [
        "さん", "くん", "君", "ちゃん", "様", "さま", "氏", "先生", "せんせい", "殿"
    ]
    // 会う/合う のどちらの活用形かの判定(表層の先頭漢字で見る)。
    static func auVerbLeadingKanji(of surface: String) -> Character? {
        guard let first = surface.first, first == "会" || first == "合" else {
            return nil
        }
        return first
    }
    // 時間経過の名詞(直後の たつ 活用は 経つ が正書。立つ/建つ は不自然)。
    static let multiClauseTemporalElapseNounSurfaces: Set<String> = [
        "時間", "時", "月日", "年月", "歳月", "日にち", "日数", "とき", "日"
    ]
    // たつ 活用の表層先頭漢字(経 以外の たつ 族への減点判定に使う)。
    static func tatsuVerbLeadingKanji(of surface: String) -> Character? {
        guard let first = surface.first,
            "立建経断絶発起勃佇".contains(first) else {
            return nil
        }
        return first
    }
    // 名詞表層が人物らしいか(語彙一致 or 敬称接尾 or 敬称単独ノード)。
    // 田中さん が 田中+さん に分割されると直前ノードが「さん」単独になるため、敬称そのものも
    // 人物シグナルとして扱う(名前は無限で網羅できないが 敬称付きは高確度で人物)。
    static func isPersonLikeNounSurface(_ surface: String) -> Bool {
        if multiClausePersonNounSurfaces.contains(surface) {
            return true
        }
        if multiClausePersonHonorificSuffixes.contains(surface) {
            return true
        }
        for suffix in multiClausePersonHonorificSuffixes where surface.count > suffix.count && surface.hasSuffix(suffix) {
            return true
        }
        return false
    }
    // あう の出し分けペナルティ。LM 差(に→会っ/合っ が約90)を確実に超え、かつ他の
    // 構造(床/クランプ)を乱さない中庸値。非優先側の 会/合 表層にだけ課す。
    static let multiClauseAuPersonMismatchPenalty = 900
    // b2 活用供給のスパン先頭(seed/辞書順で最優先)の活用形に与える連文節ボーナス。
    // 同音活用(使えた/仕えた/支えた)が僅差 LM で沈むのを人手の並びで是正。汎用適用は
    // 見た/呼んだ 等の別動詞を潰すため、下記 allowlist の基底読みに限定する。
    // 分割経路([支え][た] の 支え→た bigram)まで覆すため大きめの値が要る。
    static let multiClausePreferredInflectionBonus = 800
    // 連文節でも seed 順を勝たせたい活用の基底読み(オプトイン)。span を脱活用して
    // ここに含まれる基底になる場合のみ、スパン先頭活用形にボーナスを与える。
    static let multiClauseSeedOrderInflectionBaseReadings: Set<String> = ["つかえる", "おく"]
    // (b2b) 未代表族の追加供給に先行ボーナス(800)を与える基底読みのopt-in。
    // 上の seed順allowlist と分離する — 共用すると主ループのspan判定(脱活用先が一致)が
    // 既存族の先頭(這ったら)にも同じボーナスを与えて同点に戻る(2424の検証で確認)。
    // 無差別に与えると 有った/要った/足って 等22件が退行するため、必ずopt-inで運用する。
    // まつ: まって/まっている/まった が 舞う(まう)族に先を越されていた。ルール定義順が
    // う→…→つ のため 舞って が先に立つが、LM は 待つ(6049)/待ち(5928)が 舞う(6578)/
    // 舞い(7446)より優勢で、日常頻度も 待つ が上(2495)
    static let multiClauseInflectionFamilyPreferenceBaseReadings: Set<String> = ["はる", "おく", "まつ"]
    // 連文節でも seed 先頭の「名詞」を勝たせたい読み(オプトイン)と読み別ボーナス値。
    // 数量詞複合(2本/二本)や分割に押されて seed 既定(日本)が沈むのを是正する。
    // a2 seed の先頭候補ノードにボーナス。既定は 800(multiClausePreferredInflectionBonus と同値)。
    // そうりょう は Wikipedia の観測 bigram(総量→は700/の875/が・を1424)が日常頻度(送料)と
    // 系統的に食い違う語で、最大不利 ≈3950(uni差966+の差2985)を超える 4200 で全助詞文脈を反転
    // (ユーザ要望: 学習なしで 送料の が一発)。
    static let multiClauseSeedOrderNounBonusesByReading: [String: Int] = [
        "にほん": 800, "ほうだい": 800, "おん": 800, "うち": 800, "そうりょう": 4200,
        // みな はかなが主流(LM みな5809≈皆5748)だが wc 皆4233≪みな7460 で連文節は漢字が勝つ。
        // 短span床(かな識別=wc7460 床上げ)ぶんを跨いで反転する値
        "みな": 3300,
        // にた は 似た が辞書に無く seed 供給(dictUnknown 8700)。かな にた(wc8000 床)との差を反転
        "にた": 2000,
        // たぶん はかな先頭(ユーザー指定)。LM 多分6808<たぶん7079 の僅差を反転
        "たぶん": 800,
        // ばい は助数詞 倍 の読み別 wc(8195)が 杯6866/枚7290 より重く、短span床で
        // 倍ぐらいに 等が 杯 に負ける。床差(~800)+マージンで反転
        "ばい": 1500,
        // ねあがり は地名 根上 の unigram(7406)が 値上がり(7537)より安い Wikipedia
        // バイアス。僅差(131)+マージンで反転
        "ねあがり": 800,
        // いくつ はかな主流(uni 4779≪幾つ5884)だが、かな識別の床上げで 幾つ が勝つ
        // (みな と同型)。床差を跨いで反転する値
        "いくつ": 3300,
        // はりわすれ は curated 2語(貼り忘れ/張り忘れ)が LM 無情報で分割経路の同点勝負に
        // なり、はりわすれた 等で 張り が先行する。seed 先頭(貼り忘れ)を優先
        "はりわすれ": 800,
        // きかんし は 機関誌/機関紙/気管支 が収穫底値(>=10000)で、帰還+し 等の合成に負ける。
        // seed 登録で単文節は是正済み。連文節側も seed 先頭(機関誌)へボーナスで揃える
        "きかんし": 1500,
        // とき はかな正書の形式名詞(ユーザー方針で 時 より前)。連文節では unigram
        // (時3807 < とき4282)で漢字が勝つため、seed 先頭(とき)へ差+マージンのボーナス。
        // 述語直後は既存の形式名詞ペナルティが担当し、ここは助詞直後(のときは 等)に効く
        "とき": 800
    ]
    // 形容動詞語幹の判定閾値: prev→な の bigram コストがこの値以下なら形容動詞とみなす
    // (便利491/静か425/元気1129 は形容動詞、馬2944 は偶発的な名詞→な なので除外)。
    static let multiClauseNaAdjectiveBigramThreshold = 2000
    // カ変「来る」の活用形(読み→漢字表層)。活用供給順で一段動詞の後に沈むため連文節に
    // 明示供給する。北/着た 等の同音とは競合し LM が文脈で選ぶ(単独 きた→北 は不変)。
    // 単文節の kuruInflectionForms(きてしまいました→来てしまいました 等の複合尾を含む)から
    // 自動生成する — 手書き7形だけだと きてしまいました 丸ごとspanにカ変が立たず、
    // 一段派生(着て/衣て/著て+しまいました)しか経路に無くなる(もうしょくばに… 対策)。
    static let multiClauseKuruFormSurfaces: [String: String] = {
        var map = Dictionary(
            KanaKanjiConverter.kuruInflectionForms.map { ($0.readingSuffix, $0.kanjiOutputSuffix) },
            uniquingKeysWith: { (first: String, _: String) in first }
        )
        // 終止/可能系はリスト外(単文節では辞書語・活用エンジンが賄う)なので旧map分を補完
        for (reading, surface) in ["くる": "来る", "くれ": "来れ", "これる": "来れる", "これた": "来れた"]
        where map[reading] == nil {
            map[reading] = surface
        }
        return map
    }()
    // 連用形+に(目的)直後の移動動詞ボーナス。北(名詞)5190+に→北4818 級を、来た(活用OOV
    // 7200)が上回れる水準に。移動動詞は 来/行/帰/戻 始まりの漢字表層で判定する。
    static let multiClauseRenyouNiMotionVerbBonus = 3500
    // 格助詞 に 直後のカ変(来る)到着点ボーナス。一段 着る 派生(着て+しまいました)との
    // 同コスト帯を確実に逆転できる控えめな値(に を伴わない文脈の 着て は不変)。
    static let multiClauseNiKuruArrivalBonus = 1500
    static func isMotionVerbSurface(_ surface: String) -> Bool {
        guard let first = surface.first else { return false }
        return first == "来" || first == "行" || first == "帰" || first == "戻"
    }
    // Nベスト風バリアント: 最良経路の1文節を同区間の次点表層に差し替えて提示する件数と、
    // 採用するコスト差の上限(bigram拮抗の第2候補: しかく→視覚/資格 等を拾う)。
    static let multiClauseVariantLimit = 3
    static let multiClauseVariantMaxDelta = 4000
    // 文末の終助詞クラスタ読み。文末セグメントがこれらの読みなのに表層が漢字・カタカナ
    // (かな→仮名/哉、かも→鴨、かー→カー 等)になるのは不自然なので、EOS 遷移で強めに
    // 減点してかな表記を優先する。伸ばし形(かー等)は長音がローンワード指標でもあるため
    // カタカナ素通り減点を受けず、この減点が唯一の防御になる。
    // し は接続助詞の文末用法(〜だろうし/〜だし)。市→EOS(1619)が し→EOS(4254)より
    // 安く出口で逆転するため(わかるだろう市)、ここで漢字表層に減点する。
    // な は終助詞の文末用法(〜だな/〜といいな)。奴/名/菜 等の文末漢字化に減点する。
    // けど/けどー は接続助詞の文末用法(〜ですけど)。けどー は uni/bigram とも未収録で、
    // 全かな best(ですけどー)がエコー抑制に捨てられ デスけどー 等の変種が繰り上がるため、
    // 終助詞クラスタと同じ「文末かなは正規の変換」扱いにする。
    // なあ/ねえ/よお/わあ は長音符でなく母音字で伸ばした終助詞(してるなあ)。ー形と同じ扱い
    // にしないと全かな best が捨てられ、名前収穫の変種(菜亜 wc10000)が繰り上がる。
    // だけ は副助詞(かなが正書)。非かな変種(抱け/竹/丈/岳)は文中でも不要で、
    // これだけ 等の全かな best のエコー例外にも効かせる。
    static let multiClauseFinalParticleReadings: Set<String> = ["かな", "かも", "よね", "かしら", "よな", "かー", "ねー", "なー", "よー", "わー", "のー", "かなー", "よねー", "よねえ", "のよね", "のよねー", "し", "な", "ね", "よ", "けど", "けどー", "なあ", "ねえ", "よお", "わあ", "だけ",
        // 接続助詞の言いさし終止(〜だから。/〜なので。=チャットで頻出)。EOS未観測の から が
        // 空(から=Wikipediaで文末頻出)に負ける じゃない空 対策
        "から", "ので"]

    // 文末の そう(推量・指示: ほとんどそう/たぶんそう)はかなが正書。層/僧/草(全漢字)が
    // EOS で勝つのを防ぐ。multiClauseFinalParticleReadings に入れると最長一致ボーナスや
    // 変種の漢字ブロックまで付いてきて に沿う(動詞)が変種からも消えるため、EOS の
    // 全漢字表層減点だけを per-reading で適用する(沿う/添う は う 含みで対象外)。
    static let multiClauseSentenceFinalAllKanjiPenaltyReadings: Set<String> = ["そう"]

    // 敬称の読み。数字の直後以外(=名詞/人名の後)では さん→山/三/桟 等の漢字化は
    // 接尾語にならない(名前+さん=かな敬称 が正書)ので、漢字表層に減点する。
    // 数字の後(十三/二十三 等)は正当な 三 なので免除する。
    static let multiClauseHonorificSuffixReadings: Set<String> = ["さん", "さま"]
    static let multiClauseHonorificKanjiPenalty = 3000
    // 地域接尾+産(産地表記)を かな敬称さん より優先するボーナス(2410)
    static let multiClauseRegionalProduceBonus = 3000
    // 述語直後の かち→価値 ボーナス(定義箇所のコメント参照)。床差396+マージン
    static let multiClausePredicateKachiValueBonus = 1500
    // 係助詞「は」直後の「ある」はかなが正書(ではある/にはある/とはある 等の概言・提題)。
    // 有る/在る/或る への漢字化は不自然なので減点し、N-best 変種(maxDelta4000)から落とす
    // (うまそうでは有る 対策)。ある はかな正書動詞(seed ある=[ある,有る,在る] のかな先頭)。
    static let multiClauseAruKanjiAfterWaPenalty = 4200
    // 接頭辞「お」(かな)直後の そい(添い/沿い 等)は おそい(遅い)の誤分割(お+そい)であることが
    // ほとんど。N-best 変種(お添いよね/お沿いよね)から落とすため減点する。寄り添い等の複合
    // (prev≠お)や お茶/お金(reading≠そい)は無傷。
    static let multiClauseHonorificOsoiSplitPenalty = 8000
    // かな正書として優先したい読み(副詞 いまだに、口語終止 したんだが 等)。連文節でも漢字
    // (未だに/紫檀…)や分割・レア動詞(湑む)に負けないよう、かな識別ノードを安価(< 辞書未知コスト)
    // にクランプして最上位に来られるようにする。
    // 口語のかな正書語(副詞 いまだに、口語終止 したんだが、俗語 やばい、口語断定 じゃん)。
    // カタカナ形が Wikipedia LM で安い(ヤバイ7649/ジャン5025)ため放置すると ヤバイジャン に
    // なる。かな識別を安価にして やばいじゃん を最上位にする(かなが現代口語の正書)。
    static let multiClauseKanaAdverbReadings: Set<String> = ["いまだに", "したんだが", "やばい", "じゃん"]
    // 文節先頭(直前=BOS)でのみ かな を優先する存在動詞の過去(あった=ある過去、いた=いる過去)。
    // あったんで→かな先頭にしつつ、気が/目が/サイズが+あった(prev≠BOS)は漢字 合った を守る。
    static let multiClauseClauseInitialKanaExistentialPasts: Set<String> = ["あった", "いた"]
    // 直後に特定動詞が続く連語でだけ特定表層を優先する(同音語の文脈限定是正)。
    // ひび: 直後(助詞任意)が はいる 活用のとき ひび(罅)を 日々 より優先(ひびが入る)。
    // さいど: 直後が あげる/さげる 系のとき 彩度 を サイド/再度 より優先(彩度上げる。写真編集)。
    static let multiClauseNounBeforeVerbCollocations: [String: (surface: String, verbPrefixes: [String])] = [
        "ひび": (surface: "ひび", verbPrefixes: ["はいっ", "はいら", "はいり", "はいる", "はいれ"]),
        "さいど": (surface: "彩度", verbPrefixes: ["あげ", "あが", "さげ", "さが"])
    ]
    static let multiClauseKanaAdverbCost = 4000
    // 口語の説明終止クラスタ(のだ縮約 ん + だ/です + 逆接/終助詞)。述語に付く正書かなで、
    // レア語・分割に負けやすい。全体1スパンのかな識別を安価にして 〜んだが/んだけど/んです…を
    // 通す(行ったんだが/食べたんです 等の一般ケース。名詞衝突する読みは個別 seed/clamp で補完)。
    // て形直後の くれる補助動詞(〜てくれる/てくれない)はかなが正書(使ってくれない)。
    // くれない 読みは 紅(名詞 LM5908)が最安の1ノードで居座り 使って紅 を作るため、て形直後の
    // かな識別を安価にして 使ってくれない を最上位にする。名詞直後(BOS/体言)は対象外。
    // て形直後の授受補助動詞(〜てくれる/〜てあげる)。かなが正書。あげ族は Wikipedia LM の
    // 基底頻度(挙げる5399<上げる5806<あげる6120=例を挙げる 等の百科事典バイアス)で
    // 挙げて が供給先頭になる(教えてあげて→教えて挙げて)のを是正する。
    // 活用列挙リストは くれてる(ている縮約)等の漏れが続いたため廃止し、
    // 「くれ/あげ 始まりの全ひらがな連鎖(≤8字)」の述語で一般判定する
    // (くれてた/くれてます/あげちゃう 等も自動で入る)。て/で 直後限定は各適用箇所が課す。
    static func isTeBenefactiveAuxiliaryReading(_ reading: String) -> Bool {
        guard reading.count >= 2, reading.count <= 8,
            reading.hasPrefix("くれ") || reading.hasPrefix("あげ") else {
            return false
        }
        return reading.unicodeScalars.allSatisfy { (0x3041...0x3096).contains($0.value) }
    }
    static let multiClauseColloquialExplanatoryTailReadings: Set<String> = [
        "んだが", "んだけど", "んだけれど", "んだけれども",
        "んですが", "んですけど", "んですけれど", "んですけれども",
        "んだよ", "んだね", "んだよね", "んだな",
        "んですよ", "んですね", "んですよね",
        "んだもん", "んだもの", "んだっけ",
        // んだろう/んだろ(のだろう の縮約)。だったん(達陀/脱炭/韃靼)の丸ごと語に
        // 区切りを奪われるのを防ぐ(いつだったんだろう→いつ脱炭だろう 対策。2460)
        "んだろう", "んだろ",
        // でしょ(でしょう縮約)。で+初/諸 等の単漢字分割に勝たせる(単文節は dict rank0 かな が
        // 受け皿にあるため、エコー抑制で multi=[] になっても候補は全滅しない)
        "でしょ",
        // かなー(詠嘆の終助詞クラスタ+長音)。素通り21000では 色香+なー 等の辞書語吸収に勝てない。
        // 単文節に かなー 受け皿あり
        "かなー"
        // ※コピュラ否定(じゃない/じゃなくて/じゃなかった)の追加は不可 — かな識別が単一ノード最良に
        // なると入力エコー抑制で multi=[] になり、single が空の じゃなくて は候補全滅する。
        // エンジンは元々かな最良を返しており、必要なのは提示層 keepKana のみ(2333)。
    ]
    // 直前ノードが数量(十/二十/漢数字/アラビア数字)で終わるか。三 の免除判定に使う。
    static let multiClauseNumericSurfaceTailCharacters: Set<Character> = [
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
        "〇", "一", "二", "三", "四", "五", "六", "七", "八", "九",
        "十", "百", "千", "万", "億", "兆", "零"
    ]
    // 数字がかな表記のまま(にじゅう/ひゃく…)の場合の免除。桁読みは名前末尾になりにくい。
    static let multiClauseNumericReadingTails: [String] = [
        "じゅう", "ひゃく", "びゃく", "ぴゃく", "せん", "ぜん", "まん", "おく", "ちょう"
    ]

    static func isNumericContextForHonorific(prevSurface: String, prevReading: String) -> Bool {
        if let last = prevSurface.last, multiClauseNumericSurfaceTailCharacters.contains(last) {
            return true
        }
        return multiClauseNumericReadingTails.contains { prevReading.hasSuffix($0) }
    }
    // 活用派生ノードの末尾助動詞トークン(長い順)。コーパスは A単位で 買わ+ない に分割する
    // ため、合成ノード「買わない」は出口 bigram(ない→よ/ない→EOS)を引けず、断片チェーン
    // (川+ない)に出口コストで逆転される。末尾トークンで bigram を代用して整合させる。
    static let multiClauseInflectionAuxTails: [String] = [
        "ました", "ません", "なかった", "ないで", "ない", "ます", "です", "った", "んだ", "いた",
        "えた", "した", "てる", "よう", "たい", "て", "た", "だ", "う"
    ]
    static let multiClauseFinalParticleKanjiPenalty = 3000
    // 文末の終助詞「な」は述語(用言・タ形)に付くもの。非述語(地名/名詞、例: 三田)の
    // 直後に文末「な」が来る区切りは不自然なので減点し、見た+な のような述語+終助詞の
    // 区切りを優先する(むかしみたな→昔見たな 対策)。連体詞「な」(きれいな花 等、な の
    // 後ろに語が続く)は node.end==n の文末限定で除外する。
    static let multiClauseSentenceFinalNaAfterNounPenalty = 3000
    // 述語(動詞連体形・活用派生)の直後に漢音の 人(にん/じん)は接続しない(描く人 は
    // かくひと のみ。にん/じん は 管理人/外国人 等の名詞接尾)。学習で かく→描く 等が
    // curated 化すると 触って+描く+人(にん) が 触って確認 を逆転するため、文法として遮断する
    // (さわってかくにん対策)。読み ひと は正当な接続なので対象外。
    static let multiClausePersonSuffixSinoReadings: Set<String> = ["にん", "じん"]
    // 読み跨ぎ bigram 借用の遮断対象。surface の LM 統計が別の主読みに支配される単漢字は、
    // bigram 借用(し→人 5902=ひと文脈、は→頭 4675=あたま文脈)が床上げを素通りして
    // 断片連結を過剰に安くするため、bigram を使わず unigram+短span床で評価する。
    // 人(にん/じん)=さわってかくにん/しにんからも対策、頭(ず)=にくいはず→にくいは頭対策。
    static let multiClauseBigramBorrowDeniedReadingsBySurface: [String: Set<String>] = [
        "人": ["にん", "じん"],
        "頭": ["ず"],
        // 日(び)=曜日の連濁読み収穫(wc6052、主読み ひ=5549)。あの→日 1272(あの日=
        // あのひ の実績)を借用して あのびじんの→あの日神野 の分断を作る
        "日": ["び"],
        // 化(か)は接辞用法のA単位分割(変化/文化 等)の bigram(色→化 3023 等)を借用して
        // 色化なー のような裸の接辞断片を作る。単独の 化(か)は文中に立たない
        "化": ["か"],
        // 四(よ)は数詞複合(十四/四人 等)のA単位 bigram(の→四 等)を借用して
        // のよねー→の四ねー のような終助詞クラスタの乗っ取りを作る。単独の 四(よ)は
        // 文中に立たない(四人/四時 等の複合は辞書丸ごと語が受け持つ)
        "四": ["よ"],
        // 麦酒(びーる)は歴史企業名(大日本麦酒 等)の bigram 日本→麦酒(3904)を借用して
        // 日本ビール(bigram未観測、ビール uni5354<麦酒6571)を逆転させる。unigram 評価なら ビール が勝つ
        "麦酒": ["びーる"],
        // 道(どう)は主読み みち の bigram(この→道/道→が 等)を借用して このどうがだと→
        // この道がだと の分断を作る。同(どう)も接頭用法のA単位分割(同社/同年)由来の
        // bigram を借用する同型。単独名詞として立つ 銅(どう)は正当なので触れない
        "道": ["どう"],
        "同": ["どう"]
    ]
    // 出側(prev)の読み跨ぎ bigram 借用の遮断。御(お)は文語・敬語コーパスの
    // 御(おん/ご/み)接頭 bigram(御→宿り2793/御→三2052 等)を借用して
    // 御宿り(おやどり)のような分断を実辞書語(親鳥)より安くしてしまう。
    // 該当ノードからの出遷移は bigram を引かず unigram+バックオフで評価する(2421)。
    static let multiClauseOutgoingBigramBorrowDeniedReadingsBySurface: [String: Set<String>] = [
        "御": ["お"]
    ]
    // 仮定の接続助詞「なら」は述語(動詞/形容詞の終止・連体形)直後ではかなが正書
    // (買うなら/するなら/食べるなら)。奈良/楢/ナラ への漢字・カタカナ化を EOS で減点する。
    // ただし体言+と直後(大阪と奈良)は正当な地名なので、直前が述語のときだけ発火させる。
    static let multiClauseConditionalParticleReadings: Set<String> = ["なら"]
    // 辞書形述語(終止形動詞/形容詞)の末尾かな。短spanレア読み床の免除判定で、
    // inflection_classes への問い合わせ対象を「漢字+この尾」の表層に絞る形状ゲート。
    static let multiClauseDictionaryFormTailCharacters: Set<Character> = [
        "う", "く", "ぐ", "す", "つ", "ぬ", "ぶ", "む", "る", "い"
    ]
    // 述語(動詞辞書形/形容詞/タ形)の末尾文字。なら の直前がこれで終わるか活用派生なら述語とみなす。
    static let multiClausePredicateTailCharacters: Set<Character> = [
        "う", "く", "ぐ", "す", "つ", "ぬ", "ぶ", "む", "る", "い", "た", "だ"
    ]
    // かな正書の代名詞(こいつ/そいつ/あいつ)。此奴/其奴/彼奴(旧表記)や コイツ 等の
    // カタカナは単文節の候補列には残す(単独入力では選択可)が、連文節の変種としては
    // 出さない(文中に旧表記が混じるのを防ぐ)。どいつ は ドイツ と正当に競合するため対象外。
    static let multiClauseKanaOrthodoxPronounReadings: Set<String> = ["こいつ", "そいつ", "あいつ"]
    // かな正書の指示代名詞語幹(これで/ここで 等の keepKana 判定に使う)。
    // かな/カタカナ表記が正書として使われる形容動詞語幹(ひらがなだと紛れるが漢字が馴染まない語)。
    // seed 側の並び指定と対で運用する(seed["いや"]=[イヤ,いや,嫌,否,厭])。
    // 動詞連用形+動詞 の複合動詞(取り忘れる/撮り忘れる/貼り忘れる)は生産的な語形成だが、
    // 同音の単漢字名詞(鳥)が1ノードで安いため 鳥忘れている のような非文法の無助詞連結が
    // 勝つことがある(単漢字名詞→動詞の減点600では届かない)。seed で連用形を供給した読みに
    // 限り、直後が動詞のときだけ連用形ノードを優遇する(2477)。
    // 対象ノードは「読みが下の集合 かつ 表層が送り仮名 り で終わる漢字表記」=連用形。
    // 同一スパンの連用形どうしには等しく効くので相対順(取り→撮り→捕り→採り)は変わらない。
    static let multiClauseCompoundVerbRenyouStemReadings: Set<String> = ["とり", "はり"]

    static let multiClauseCompoundVerbRenyouBonus = 3000

    static let kanaOrthographyNaAdjectiveStems: Set<String> = ["いや", "むら"]

    // 上の語幹に付く活用語尾・断定/丁寧の連なり。助詞の は/が 等は既存の剥がし規則が担当する。
    static let naAdjectiveInflectionTails: Set<String> = [
        "で", "だ", "な", "に", "なら", "だし", "だと", "だから",
        "だった", "だったら", "です", "でした", "じゃない", "ではない"
    ]

    // 上の指示代名詞に付く助詞。ここまで/そこから 等はかなが正書だが、助詞の一般剥がしは
    // 名詞+助詞(ずかんで)を巻き込むため語幹を指示代名詞に限定して照合する(2476)。
    static let kanaOrthographyDemonstrativeFollowingParticles: [String] = [
        "で", "まで", "から", "へ", "に", "は", "も", "と", "を", "より",
        "だけ", "でも", "では", "にも", "までは", "からは", "までに"
    ]

    // 引用の という 連鎖(かなが正書)。末尾の 名詞化節(のは/のが)込みの形も並べる。
    static let kanaOrthographyQuotationTails: [String] = [
        "という", "といって", "といえば", "といった", "といっても", "というか",
        "というのは", "というのが", "というのを", "というのも", "ということ", "ということは"
    ]

    // 上の引用連鎖の前に立つ、かな正書の副助詞・並立助詞。名詞+という(図鑑という)は対象外。
    static let kanaOrthographyQuotationStems: Set<String> = [
        "など", "なんて", "とか", "だけ", "ばかり", "くらい", "ぐらい",
        "こそ", "しか", "まで", "でも", "かも", "のみ"
    ]

    static let kanaOrthographyDemonstrativePronounStems: Set<String> = [
        "これ", "それ", "あれ", "どれ", "ここ", "そこ", "あそこ", "どこ",
        "こっち", "そっち", "あっち", "どっち", "こちら", "そちら", "あちら", "どちら"
    ]
    // 連体詞(こんな/そんな/あんな/どんな)直後の かんじ は 感じ が自然(こんな感じ)。
    // bigram 未観測で unigram の Wikipediaバイアス(漢字4805<感じ5118)により 漢字 が
    // 313差で先頭化するため、漢字 表層にのみ小さく減点して 感じ を最良にする
    // (こんな漢字 は変種#2 に残り、幹事/寛治 等も温存される)。
    static let multiClauseDemonstrativeSurfaces: Set<String> = ["こんな", "そんな", "あんな", "どんな"]
    static let multiClauseDemonstrativeKanjiPenalty = 500
    // 形式名詞・副助詞: 連体形(活用派生ノード)や辞書形述語の直後ではかな表記が正書
    // (行ったとき/するとき/貸し出すだけ)。実質名詞(時は金なり/時を刻む)は前が BOS や
    // 名詞のため発火せず区別できる。LM は た→とき(2819<た→時2920)で僅かにかなを好むが、
    // 下流 時→の(903<とき→の1107)で僅差逆転するため、述語直後のみ漢字表記へペナルティを
    // 課してかなを優先する。だけ は 抱け(命令形は述語に接続しない)/竹(連濁だけ は複合語
    // 内でのみ生じ、連体修飾の後では連濁しない)の排除(かしだすだけ対策。EOS 未観測語の
    // フォールバックが観測済み だけ→EOS より安い逆転で僅差負けしていた)。
    // はず(筈 は現代ではほぼかな正書。弓の筈 は文語的レア用法)も形式名詞扱い —
    // もっとあるはず が提示層のかな退避で もっとある筈 に繰り上がるのを防ぐ
    // くせ(癖 は逆接の形式名詞用法(やらないくせに)ではかなが正書)も対象 — keepKana の
    // 助詞剥がし(に)+形式名詞照合で やらないくせに の提示層かな退避を防ぐ(2424)
    static let multiClauseFormalNounKanaReadings: Set<String> = ["とき", "こと", "もの", "ため", "だけ", "はず", "やつ", "くせ"]
    static let multiClauseFormalNounKanjiPenalty = 1000
    // 形式名詞と同形の実質名詞(時は金なり/事の起こり/事あるごとに)。文頭に立つ とき/こと は
    // 「時間という概念」「事柄」そのものを指す実質名詞なので漢字が正書(ユーザー方針)。
    // 述語直後(〜したとき/〜すること)は上の逆向きペナルティでかなを優先しており、
    // 文頭限定なので衝突しない。値は seed 順ボーナス(とき800)を上回る必要がある(2459)
    static let multiClauseSubstantiveNounReadings: Set<String> = ["とき", "こと"]
    static let multiClauseSubstantiveNounKanaPenalty = 1500
    // 〜ったん を丸ごと1語とする名詞(脱炭/韃靼/達陀 等)は、直後が だろう/だろ/でしょう の
    // ときはコピュラ過去+準体助詞の分割(だった+ん)に道を譲る。「いつだったんだろう」が
    // いつ脱炭だろう に化けるのを防ぐ。文脈条件があるので 一旦(いったん)等の正当な語は無傷。
    // 脱炭 の読み だったん 自体 Sudachi の疑わしい収穫(通常は だつたん)(2461)
    static let multiClauseTanContractionSplitPenalty = 8000
    // 名詞直後の ほしい への減点(定義位置の транз コメント参照)
    static let multiClauseNounHoshiiPenalty = 2000
    static let multiClauseInflectionMaxSegmentReadingCount = 12  // 活用派生を試みる span 長上限
    // 活用ルールの readingSuffix 末尾文字。span がこのどれかで終わる時だけ活用派生を試みる
    // (ルール全走査の回数を抑える事前フィルタ)。
    static let inflectionRuleSuffixLastCharacters: Set<Character> = Set(
        KanaKanjiConverter.allInflectionRules.compactMap { $0.readingSuffix.last }
    )
    static let multiClauseBOSMarker = "<BOS>"
    static let multiClauseEOSMarker = "<EOS>"
    // LM コスト定数(cost = -logP × scale, scale=500 で学習)。sim_lm.py で検証した値と一致させる。
    static let multiClauseBackoffCost = 500         // bigram 未観測・unigram 既知
    // 会話的時相名詞の unigram キャップ(表層→キャップ値)。Wikipedia コーパスは
    // 昨日(uni 6869)を 機能(4237)より、最近(5294)を 細菌(5259)より過小評価し、
    // 昨日→は1126/最近→は1138 の実 bigram 優位すら uni 差が飲み込む(きのうは→機能は、
    // さいきんは→細菌は)。値は同音競合との均衡で表層ごとに調整する:
    // - 昨日 4300: 機能+backoff(4737)より安く、機能→が1112(昨日→が未観測)よりは弱い
    //   → きのうが→機能が は保たれる
    // - 最近 5000: 細菌→は1097 には勝ち(cap+1138 < 5759+1097 ⇔ cap<5718)、
    //   細菌→が1334 には負ける(cap+2533 > 7093 ⇔ cap>4560)→ さいきんが→細菌が 維持
    // 検索機能 等の複合は bigram 分岐が勝つ。unigram 分岐限定のキャップ。
    static let multiClauseConversationalTemporalNounUnigramCaps: [String: Int] = [
        "昨日": 4300,
        // 今日(会話最頻)が 経(お経4660)/教派(6278)等に unigram(5041)で競り負ける
        // (きょうはなして→経話して/教派なして)。昨日と同水準へ
        "今日": 4300,
        "最近": 5000,
        // 来週(会話最頻)が Wikipedia バイアスの 来襲(6869)に unigram(7792)で負ける
        // (らいしゅうあたり→来襲当)。来襲 を下回る水準へキャップ
        "来週": 6000,
        // 上げる(会話最頻)が 挙げる(5399=例を挙げる のWikipediaバイアス)に unigram(5806)で
        // 負ける(彩度挙げる 等)。bigram実績のある 例を挙げる 等は bigram 優先で無傷
        "上げる": 5300
    ]
    // 単漢字名詞→動詞の無助詞接続の減点。日本語で名詞が動詞に直接続くには助詞が要る
    // (どうみせる→同見せる/道見せる の 同/道 は音読み接辞で、主語・目的語として裸で
    // 動詞の前に立たない)。A単位分割由来で接辞断片の unigram は安く(同4323 ≪ どう4771)、
    // 床上げ(wc)後も どう(かな識別の床 5271)を279差で下回るため、文法側から減点する。
    // 減点は「単漢字+動詞」の候補同士では等しく掛かり相対順を変えない(花咲く/腹減った 等の
    // 助詞落ち口語は競合もかな識別=床上げ済みのため逆転しない)。かな識別を wc で安くする
    // 案(どう=4200)は そうしん→そう+しん 等の語中分断を生むため不採用(2118検証)。
    static let multiClauseSingleKanjiNounBeforeVerbPenalty = 600
    // 辞書形動詞(終止形。描く/走る/見る 等)の直後に して/する/した は非文法(正しくは て形 描いて)。
    // 描くして/走るして のような誤合成を強く減点し、隠して(かくす て形)等の正しい経路に譲る。
    static let multiClauseDictionaryFormPlusSuruPenalty = 5000
    // コピュラ終止「だ」(単独ノード)の直後に動詞(活用派生/辞書形述語)が続くのは文中では
    // 非文法(災厄だ+蹴落として 等。正しくは だけ+落として)。引用(だと言った)は と を挟むので無傷。
    static let multiClauseCopulaDaBeforeVerbPenalty = 4000
    // 並列助詞「や」(単独かなノード)の直後に敬称「さん」(読み)が続くのは 〜屋さん の誤分割
    // (くすりやさん→薬や+さん)。正当な並列(田中や佐藤さん)は間に名詞が挟まり直接遷移しない。
    static let multiClauseParallelYaBeforeSanPenalty = 4000
    // 辞書/変換にはあるがコーパス(LM)未収録の語。unigram 最大(8139)+バックオフ(500)より
    // 上に置き「どの既知語よりレア」として扱う。以前の 6000 は LM 中央値(7649)より安く、
    // 八津(OOV)が 奴(unigram 5963)に勝つ・ちゃ〜んと が ちゃんと に勝つ等の OOV 逆転を
    // 起こしていた。候補バー(単一経路)には引き続き全辞書候補が並ぶため、レア語は手動選択
    // +学習(curated 1500)で救済される。
    static let multiClauseDictUnknownCost = 8700
    // 丁寧接頭辞合成(b3: お+宿り→御宿り 等)のノードは、同スパンに実辞書語(収穫底値未満)が
    // ある場合に小さく後置する。LM未収録同士だと双方 dictUnknown(8700)の同点になり、合成の
    // 御宿り が実辞書語 親鳥(おやどり)と先頭を争ってしまう(2421)。お店/お見せ のような
    // 「辞書語も合成も正当」なスパンでは、この差は bigram 実勢があれば覆る水準に留める。
    static let multiClausePoliteSupplementDemotion = 200
    // 収穫底値(wc>=10000)の丸ごとエントリの連文節コスト。単文節の harvestTier 降格
    // (CandidateScore.harvestTierDictionary)の連文節版。レア名前収穫(廉梛/月叶 等)は
    // 正規の未知語(8700)や活用派生(7200)より信頼が低く、放置すると されんな→
    // 実用化さ+廉梛 のような名前断片が正規の派生+助詞を逆転する。
    static let multiClauseHarvestTierUnknownCost = 9500
    // 読み跨ぎ unigram 借用の一般遮断(2386): LM unigram は表層キーで読みを持たず、
    // レア読みが主読みの実績にタダ乗りする(後(うしろ)8932 が 後(あと系 min3995)の
    // uni3529 を借用、充て(みて)←あて 等)。「この読みの word_cost − 表層の全読み最安
    // word_cost ≥ 本閾値」なら unigram を信用せず word_cost を下限にする。読み≤2字は
    // 短span床(multiClauseRareReadingFloorMaxReadingCount)が既に適用済みのため、
    // 本規則は従来「解像度 保護」で床を免除していた読み3字以上の穴を埋める
    // (解像度 は単一読みで乖離0=無傷)。seed 掲載語は人手選別のため免除。
    static let multiClauseCrossReadingUnigramGapThreshold = 2500
    // curated ノードの EOS 遷移上限。かな正書の口語語彙(でかい 等)は X→EOS bigram が
    // Wikipedia文語コーパスに無く、出口で dictUnknown(8700)を払わされて断片連結
    // (出+会: 会→EOS 1571)に逆転される。人手で正書登録した curated は文末利用も
    // 信頼できるため、EOS 遷移を接続コスト級に抑える。
    static let multiClauseCuratedEOSCost = 3000
    // 短spanレア読み床上げ: LM unigram は表層のみで読みを見ないため、頻出表層×レア読み
    // (見(み)8055/店(たな)11947/三田(みた)8247 等)が不当に安くなり断片連鎖を作る
    // (むかしみたな→昔見店 等)。bigram 未観測時、短spanの漢字表層は
    // max(unigram+バックオフ, word_costs) で評価する — Sudachi(読み別)と LM(表層のみ)の
    // 高い方を採る。両者が食い違う(=表層が別読みや語幹断片として頻出なだけ)の時だけ
    // 自動で効き、真に頻出の読み(目(め)wc4477<uni+bo 等)は max が no-op で無影響。
    // 閾値方式(8000)は み一族(身6730/実7722/見8055…)の繰り上がりに勝てず廃止した。
    // 条件の意図:
    // - 読み1〜2文字限定: 長い読みで wc だけ特異的に高い正読み(解像度(かいぞうど)14076)を
    //   巻き添えにしない。断片連鎖の部品は実質短spanのみ。
    // - 漢字表層に加え、かな識別(surface==reading)にも適用する: コーパスのA単位分割は
    //   補助動詞のかな(してみた→し/て/み/た)も断片化するため、み(み)wc9225 のような
    //   かな識別が uni+bigram(み→た 1010)で激安チェーンを作る(むかしみたな→昔みたな)。
    //   ただし助詞・助動詞類(下の除外リスト)は正当な高頻度かなであり、薄マージン経路
    //   (じょやのかね 71点差等)を動かさないため除外する。
    // - カタカナ断片は既存のカタカナ化ペナルティが受け持つ。
    // - bigram 観測時は文脈の実証があるので免除。レア語自体は単文節+学習で選択可能。
    static let multiClauseRareReadingFloorMaxReadingCount = 2
    static let multiClauseKanaIdentityFloorExemptReadings: Set<String> = [
        // 格助詞・係助詞(caseParticleSurfaces と同梱+複合の部品)
        "に", "を", "が", "へ", "と", "で", "は", "も", "の",
        "から", "まで", "より",
        // 終助詞・間投助詞(や は除外しない: multiClauseFinalParticleReadings にも無く、
        // 文頭の や(uni 2998)が 後世 等と組む接着剤ジャンクになる(やこうせいのどうぶつ→
        // や後世の動物)。並立助詞 AやB は bigram 観測で床上げ免除されるため実害なし)
        "ね", "よ", "な", "か", "わ", "さ", "ぞ", "ぜ", "し",
        // 助動詞・接続の頻出かな(A単位分割で正当に頻出するもの)
        "た", "て", "だ", "ん", "う", "ない", "ます", "です", "たい", "てる",
        // 形式名詞・副助詞(かなが正書。wc はず=6777/だけ=5947 の床上げで断片に負けていた)
        "はず", "だけ",
        // 存在動詞 ある はかなが正書(uni ある2698≪有る6303)だが wc6465 の床上げで
        // 有る(bigram 有る→の1692)に負けていた(あるのね→有るのね)。頻出の自立語で
        // 断片ではないので床免除(なる/いる は LM 優劣が異なるため個別のまま)
        "ある",
        // 終助詞の長音形(のー は wc10379 の床上げで、外来語 ノー(wc2627)+EOS減点3000
        // を116差で下回れなかった。uni 6925 は実勢なので床免除で ノー に勝つ)
        "のー",
        // 複数接尾辞(彼ら/子供ら 等。A単位分割で 彼+ら と割れる正当な頻出かな)
        "ら"
    ]
    static let multiClausePassthroughPerCharCost = 7000 // 未変換かな 1文字あたり(点1: 余りを強く減点)
    static let multiClauseKatakanaNativeCost = 3000 // native 読みなのにカタカナ実体(何でもカタカナ化の抑止)
    // 追加語彙/学習語彙(sacoche/misc.plist 等のキュレーション or 学習)由来の語は強く優遇する。実コストは
    // min(通常コスト, この値)。強い bigram 並みに安くして分割・素通りに確実に勝たせる(=常に列挙も行う)。
    static let multiClauseCuratedWordCost = 1500
    // 語頭(文節頭)に来られない文字で始まる分割は日本語としてほぼあり得ないため強く減点。撥音ん・
    // 長音ー・促音っ・小書きかな等。「を」も現代仮名遣いでは目的格助詞専用なので語中に含めない。
    // 接続助詞・補助動詞の て(かな表層)は用言の連用形にしか付かない。名詞の直後に裸の て が
    // 立つと 上+て+あって のような断片チェーンが全span活用形(植えてあって)を逆転する
    // (植えて は LM 未収録=OOV 7200級、上 は unigram 3799 で激安)。
    // 連用形かどうかは「直前ノードの表層+て が、その1文字長いスパンの活用派生に在るか」で判定する
    // (話し→話して 在り=連用形、上→上て 無し=名詞)。述語末尾文字だけの判定では サ変の し・
    // 連用形の 話し・受身の され が漏れて5件退行した(検証済み)。
    // 判定は「直前ノードの表層+て」が派生集合に在るかで行い、漢字を含む表層に限って減点する。
    // 全かな表層(し=サ変連用形、され=受身、この=連体詞 等)は fail-open —
    // かなの連用形は派生集合に現れない(語幹なしの して/されて は導出できず集合が空になる)ため
    // 「集合が空なら連用形でない」とは判定できず、無理に減点すると して/公開されて を壊す
    // (検証で5件退行→ かな側の判定は諦めた)。派生集合が未計算のスパンも減点しない。
    // 対象ノードは surface==reading のかな表層に限る — 手/邸 のような名詞(reading て)は無関係。
    // で は格助詞(上で/東京で)として名詞に付くので対象外(2480)。
    static let multiClauseKanaTeAfterNonPredicatePenalty = 6000

    static let multiClauseForbiddenPenaltyCost = 100000
    static let multiClauseForbiddenInitials: Set<Character> = [
        "ん", "ー", "っ", "ぁ", "ぃ", "ぅ", "ぇ", "ぉ",
        "ゃ", "ゅ", "ょ", "ゎ", "ゕ", "ゖ", "ゝ", "ゞ", "・"
    ]
    // 語頭禁止の正当な例外。って/っていう は引用・話題の助詞(アプリって 等、wc実在の正当語)。
    // って を禁止したままだと 名詞+って が組めず、り を吸収して促音始まりを回避した活用合成ノード
    // (りって)が滑り込む(ふくすうあぷりって→複数アプ+りって)。
    // ※単独「ん」(準体助詞)は無条件ではなく「述語末尾直後のみ」条件付き免除に変更(transitionCost参照)。
    static let multiClauseForbiddenInitialExemptReadings: Set<String> = ["って", "っていう"]
    // ローンワード的な読みの指標(長音・小書き母音)。これらを含む読みはカタカナ表記が
    // 妥当なので、カタカナ素通りを減点しない(例: らんてぃーゆ→ランティーユ は許容)。
    static let multiClauseLoanwordMarkers: Set<Character> = [
        "ー", "ぁ", "ぃ", "ぅ", "ぇ", "ぉ", "ゎ"
    ]

    // ラティスのノード(1 つの文節候補)。同じ span でも表層ごとに別ノードを立て、bigram の
    // 文脈(直前の表層)を DP でつなぐ。
    // 借用可能な末尾トークンを返す。活用派生ノードに加え、かな識別ノード(curated の
    // やって/にした や word_costs のかな語)も対象 — かな表層はコーパスのトークン列と
    // 表記が一致するため、末尾トークンの bigram 代用が意味的に成立する。
    static func auxTailForBigramBorrow(of node: MultiClauseNode) -> String? {
        guard node.isInflectionDerived || node.surface == node.reading else {
            return nil
        }
        return inflectionAuxTail(of: node.surface)
    }

    static func inflectionAuxTail(of surface: String) -> String? {
        for tail in multiClauseInflectionAuxTails where surface.hasSuffix(tail) {
            return tail
        }
        return nil
    }

    struct MultiClauseNode {
        let start: Int
        let end: Int
        let surface: String
        let reading: String
        let isDictWord: Bool   // 辞書/変換で得た語(true) or かな素通り(false)
        let isCurated: Bool    // 追加語彙/学習語彙(sacoche/misc.plist 等の手動キュレーション or 学習)由来
        let isInflectionDerived: Bool  // (b2) 活用エンジン供給ノード(買った/断線しやすい 等)
        let wordCost: Int?     // word_costs(読み+表層)のコスト。(b) 由来のみ。レア読み床上げに使う
        // inflection_classes に登録された辞書形述語(炊く/書く 等)。Sudachi の word_cost は
        // 動詞が単漢字名詞より系統的に高く、短spanレア読み床が動詞を過剰に床上げする
        // (炊く: uni7666→wc9118)ため、床上げを免除する。読み跨ぎの頻出表層
        // (良く(いく)等)はクラス未登録なので免除されず、床の保護は維持される。
        var isDictionaryFormPredicate: Bool = false
    }

    func multiClauseCandidates(
        for reading: String,
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        guard store.hasWordLMMetadata else {
            return []
        }
        let normalized = KanaTextNormalizer.normalizedReading(reading)
        let chars = Array(normalized)
        let n = chars.count
        guard n >= Self.multiClauseMinReadingCount,
            n <= Self.multiClauseMaxReadingCount else {
            return []
        }

        let suppressedByReading = store.suppressedCandidatesByReading()
        // 補助語彙(ryukyu/vin/it 等の手選別リスト=SecondVocab)。LM未収録カタカナへの
        // 「何でもカタカナ化抑止」ペナルティから免除するために引く(ジャングリア 対策)。
        let supplementalSystemDictionary = store.loadSupplementalSystemDictionary()
        // 追加語彙(sacoche/misc.plist 等の手動キュレーション)と学習語彙。どちらもユーザ意図なので優遇する。
        let initialUserDictionary = store.initialUserDictionary()
        let learnedDictionary = store.learnedDictionary()
        let manualUserDictionary = store.userDictionary()

        // --- 1. ラティスのノード列挙 ---
        var nodes: [MultiClauseNode] = []
        // b2 活用供給の各スパン先頭(orderedDerivationBaseCandidates=seed/辞書順で最優先)の
        // 活用形ノードのキー("start-end-surface")。連文節でも seed の並び意図を効かせるため、
        // DP でこのノードに軽いボーナスを与える(単文節の seed leading boost の連文節版)。
        // 同音の活用(使えた/仕えた/支えた)が僅差 LM で沈むのを、人手の並びで是正する。
        var preferredInflectedNodeKeys = Set<String>()
        // 名詞 seed 順 opt-in の読み別ボーナス(multiClauseSeedOrderNounBonusesByReading)
        var seedOrderNounNodeBonuses: [String: Int] = [:]
        // (b5) 連用形+に(目的)ノードのキー。直後の移動動詞(来る/行く)を優先するのに使う。
        var renyouNiNodeKeys = Set<String>()
        // スパン別の活用派生表層(キー "start-end")。かな て の連用形接続判定に使う。
        var inflectedSurfacesBySpan: [String: Set<String>] = [:]
        // 短い追加語彙断片(ろー→ロー/raw 等)のうち、同じ開始位置により長い辞書語(ろーぬ→ローヌ)が
        // 実在するものは「長語を分断する断片」とみなし、conn/床(1500)を与えないノードのキー。
        var shortCuratedFragmentNodeKeys = Set<String>()
        // 連語文脈でかなを優先するノードのキー(ひび+入る=ひびが入る 等)。日々 でなく ひび を勝たせる。
        var collocationPreferredKanaNodeKeys = Set<String>()
        // カタカナ強調/交ぜ書きの対象ノード(供給後の一括分類パスで印付け)。
        // suppressed=+100000(事実上不採用)、demoted=+6000(後方)。
        var scriptVariantSuppressedNodeKeys = Set<String>()
        var scriptVariantDemotedNodeKeys = Set<String>()
        // 丁寧接頭辞合成ノードの後置対象(同スパンに実辞書語があるもの。定数コメント参照)
        var politeSupplementDemotedNodeKeys = Set<String>()
        // 補助語彙由来のカタカナ語ノード(ジャングリア 等)。手選別語なので
        // カタカナ化ペナルティ(multiClauseKatakanaNativeCost)を免除する
        var supplementalKatakanaExemptNodeKeys = Set<String>()
        var nodesEndingAt: [[Int]] = Array(repeating: [], count: n + 1)
        var nodesStartingAt: [[Int]] = Array(repeating: [], count: n)

        for start in 0..<n {
            let maxLen = min(Self.multiClauseMaxSegmentReadingCount, n - start)
            for len in 1...maxLen {
                let end = start + len
                let segmentReading = String(chars[start..<end])
                let suppressed = suppressedByReading[segmentReading]

                var surfaces: [(surface: String, isDictWord: Bool, isCurated: Bool, isInflectionDerived: Bool, wordCost: Int?, isDictionaryFormPredicate: Bool)] = []
                var seenSurfaces = Set<String>()
                func add(
                    _ surface: String,
                    isDictWord: Bool,
                    isCurated: Bool,
                    exemptDecorative: Bool = false,
                    isInflectionDerived: Bool = false,
                    wordCost: Int? = nil,
                    isDictionaryFormPredicate: Bool = false
                ) {
                    if let suppressed, suppressed.contains(surface) {
                        return
                    }
                    // 抑制の同一かな末尾合成(まったく→全く なら 全くありません も)を
                    // ラティスにも載せない(単文節ステージ4と同じ規則)。
                    if isComposedSuppressed(
                        candidate: surface,
                        reading: segmentReading,
                        suppressedByReading: suppressedByReading
                    ) {
                        return
                    }
                    if !exemptDecorative, Self.isDecorativeVariantSurface(surface, reading: segmentReading) {
                        return
                    }
                    // 連濁収穫(墓(ばか)等)もラティスに載せない(ばかすぎる→墓すぎる 対策)
                    if !exemptDecorative, isRendakuHarvestSurface(surface, reading: segmentReading) {
                        return
                    }
                    // かな正書の述語(ある 等)はどの供給経路(curated/seed/word_costs)でも
                    // 辞書形述語として扱う。curated(追加語彙 ある→ある)が先着すると dfp=false で
                    // 入り、後続 a2 seed の dfp=true が dedup で失われ、のね/のよ クランプが
                    // 効かず 有るのね に負ける(あるのね 事件)。供給元に依らず確定させる。
                    var resolvedDFP = isDictionaryFormPredicate
                    if surface == segmentReading,
                        Self.multiClauseKanaPredicateIdentities.contains(segmentReading) {
                        resolvedDFP = true
                    }
                    if seenSurfaces.insert(surface).inserted {
                        surfaces.append((surface, isDictWord, isCurated, isInflectionDerived, wordCost, resolvedDFP))
                    } else if resolvedDFP,
                        let index = surfaces.firstIndex(where: { $0.surface == surface }),
                        !surfaces[index].isDictionaryFormPredicate {
                        // 既に dfp=false で入っている かな述語を後続供給で dfp=true に格上げ。
                        surfaces[index].isDictionaryFormPredicate = true
                    } else if isInflectionDerived,
                        surface == segmentReading,
                        let index = surfaces.firstIndex(where: { $0.surface == surface }),
                        !surfaces[index].isInflectionDerived,
                        let existingWordCost = surfaces[index].wordCost,
                        existingWordCost >= KanaKanjiConverter.CandidateScore.harvestTierWordCostFloor {
                        // かな識別の活用形(います 等)は (b) word_costs の収穫底値
                        // (います wc13367→一律9500)が先着し、(b2) の安い活用派生コピー
                        // (7200)が dedupe で死ぬと、かな正書の活用形が漢字派生(居ます)に
                        // 系統的に負ける。派生フラグだけ合流させる(a2 seed の先着 dedupe
                        // 対策と同族)。unigram/wc が実勢の表層(たく 等)は正直な値付けを
                        // 尊重するため対象外(底値帯のみ)。漢字表層も対象外。
                        surfaces[index].isInflectionDerived = true
                    }
                }

                // (a) 追加語彙/学習語彙(curated)を常に列挙する。分割・素通りに確実に勝たせるため。
                //     追加語彙はかな識別(ございます/だが 等、かなが正書の登録)も含めて列挙する
                //     — 手動キュレーションの単語であり、かな文丸ごとの学習汚染(ですね事件)とは
                //     異なる。学習語彙側のかな識別スキップは維持。
                //     追加語彙はユーザ明示登録なので装飾フィルタも免除(あ・うん 等の実在固有名)。
                for surface in initialUserDictionary[segmentReading] ?? [] {
                    add(surface, isDictWord: true, isCurated: true, exemptDecorative: true)
                }
                // 手動追加語彙(アプリの語彙管理から登録)も同格の curated として列挙する
                // (従来は連文節に載らない既存ギャップだった)。
                for surface in manualUserDictionary[segmentReading] ?? [] {
                    add(surface, isDictWord: true, isCurated: true, exemptDecorative: true)
                }
                for surface in learnedDictionary[segmentReading] ?? [] where surface != segmentReading {
                    add(surface, isDictWord: true, isCurated: true)
                }

                // 短い追加語彙断片が同じ開始位置のより長い辞書語を分断するのを防ぐ。読み≤2モーラで
                // curated を含み、[start, start+longer] (longer>len) に辞書語が実在する時だけ、その
                // curated ノードを「断片」と印付けし、後段の transitionCost で床(1500)を外す。
                // ろー(ロー/raw)は ろーぬ→ローヌ が実在=断片印。やつ/気を は長い辞書語が無く床維持。
                if segmentReading.count <= 3,
                    surfaces.contains(where: { $0.isCurated && Self.isWordLikeSurface($0.surface) }) {
                    // 「より長い語」は常用語(word_cost が harvest 底値=レア人名 未満)に限る。
                    // ろーぬ→ローヌ(4577)は常用で断片印を付けるが、かおな→華音樹(10000=底値)の
                    // ようなレア人名では 顔(かお)を誤って断片扱いしない。
                    var hasLongerCommonWord = false
                    var probeLen = len + 1
                    while probeLen <= maxLen {
                        let longerReading = String(chars[start..<start + probeLen])
                        let longerCosts = store.wordCosts(for: longerReading)
                        if longerCosts.values.contains(where: {
                            $0 < KanaKanjiConverter.CandidateScore.harvestTierWordCostFloor
                        }) {
                            hasLongerCommonWord = true
                            break
                        }
                        probeLen += 1
                    }
                    // 跨ぎ常用語: 断片の接頭部が指示副詞(こう/そう/どう/ああ)か準体助詞の の で、
                    // その直後から断片の末尾を跨ぐ常用語がある(香茹(こうこ)の中の こう+こたえる、
                    // のか(curated)の中の の+かいじょう=会場 等)ときも分断とみなす。
                    // 接頭を限定するのは、してる(ルナ跨ぎ)/明日(あした)等の正当な curated
                    // かな識別・名詞を巻き込まないため。文末の のか(行くのか)は跨ぐ先が無く床維持。
                    if !hasLongerCommonWord, len >= 2 {
                        outer: for adverb in ["こう", "そう", "どう", "ああ", "の"] {
                            guard segmentReading.hasPrefix(adverb), adverb.count < len else { continue }
                            let crossStart = start + adverb.count
                            var crossLen = (end - crossStart) + 1
                            while crossStart + crossLen <= min(n, crossStart + 6) {
                                let crossReading = String(chars[crossStart..<crossStart + crossLen])
                                let crossCosts = store.wordCosts(for: crossReading)
                                if crossCosts.values.contains(where: {
                                    $0 < KanaKanjiConverter.CandidateScore.harvestTierWordCostFloor
                                }) {
                                    hasLongerCommonWord = true
                                    break outer
                                }
                                crossLen += 1
                            }
                        }
                    }
                    if hasLongerCommonWord {
                        for entry in surfaces where entry.isCurated && Self.isWordLikeSurface(entry.surface) {
                            shortCuratedFragmentNodeKeys.insert("\(start)-\(end)-\(entry.surface)")
                        }
                    }
                }

                // 連語で特定表層を優先(ひび+入る=ひびが入る、さいど+あげる=彩度上げる 等)。
                // 文脈限定=この区間の直後(助詞 は/が/を 任意)が指定動詞の活用のときだけ。
                // 日々を大切に/再度確認 等の非連語文脈は無影響。
                if let collocation = Self.multiClauseNounBeforeVerbCollocations[segmentReading] {
                    var afterIdx = end
                    if afterIdx < n, chars[afterIdx] == "は" || chars[afterIdx] == "が" || chars[afterIdx] == "を" {
                        afterIdx += 1
                    }
                    if afterIdx < n {
                        let rest = String(chars[afterIdx..<n])
                        if collocation.verbPrefixes.contains(where: { rest.hasPrefix($0) }) {
                            collocationPreferredKanaNodeKeys.insert("\(start)-\(end)-\(collocation.surface)")
                        }
                    }
                }

                let segmentEndsWithSokuon = segmentReading.hasSuffix("っ")
                let costMap = store.wordCosts(for: segmentReading)

                // (b2) の供給ゲートと同条件。a2 の派生形判定でも使うため先に評価する。
                let inflectionSupplyGateSatisfied = len >= 2
                    && len <= Self.multiClauseInflectionMaxSegmentReadingCount
                    && segmentReading.last.map { Self.inflectionRuleSuffixLastCharacters.contains($0) } == true
                // 活用エンジン供給の候補(b2 と a2 で共有。キャッシュは systemCandidateMode 込み)
                func cachedInflectedCandidates() -> [String] {
                    let inflectionCacheKey = "\(systemCandidateMode)|\(segmentReading)"
                    if let cached = stateQueue.sync(execute: { multiClauseInflectionCache[inflectionCacheKey] }) {
                        return cached
                    }
                    // かな識別の除外(b2 の where 相当)後に topK 件を確保できるよう、
                    // 取得は topK の2倍にする(limit ちょうどだと かな が枠を潰し、
                    // かって の 勝って(4番目)が入れない)。
                    let inflected = inflectionCandidates(
                        for: segmentReading,
                        userDictionary: manualUserDictionary,
                        initialUserDictionary: initialUserDictionary,
                        systemCandidateMode: systemCandidateMode,
                        limit: Self.multiClauseInflectionTopK * 2
                    )
                    stateQueue.sync {
                        if multiClauseInflectionCache.count >= multiClauseInflectionCacheLimit {
                            multiClauseInflectionCache.removeAll(keepingCapacity: true)
                        }
                        multiClauseInflectionCache[inflectionCacheKey] = inflected
                    }
                    return inflected
                }

                // (a2) seed(人手の並び矯正/供給)もラティスに載せる。辞書に無い正書
                //      (中の/柚花 等)を連文節でも組めるようにし、コスト同値帯
                //      (名前群は一律 dictUnknown/wc10000 等)のタイブレークを seed 順で
                //      押さえる(ノード列挙順が同 delta 変種の表示順になるため)。
                for surface in KanaKanjiSeedDictionary.seed[segmentReading] ?? [] {
                    if segmentEndsWithSokuon, containsKanji(surface) {
                        continue
                    }
                    // (b) と同じ辞書形述語判定を付ける。無いと seed 掲載の動詞(書く 等)が
                    // 床免除を失って床上げされ、同読みの別動詞(描く)に逆転される。
                    var seedIsDictionaryFormPredicate = false
                    if let lastChar = surface.last,
                        Self.multiClauseDictionaryFormTailCharacters.contains(lastChar),
                        containsKanji(surface) {
                        seedIsDictionaryFormPredicate = store.isShortReadingDictionaryFormPredicate(
                            reading: segmentReading,
                            candidate: surface
                        )
                    }
                    // かな正書の述語(ある/いる 等、かな表記が主の動詞)は inflection_classes に
                    // (かな, かな)で登録が無く上の判定が false になるが、辞書形述語として扱う
                    // (のね/のよ クランプや床免除の対象=あるのね→有るのね 逆転の防止)。
                    if surface == segmentReading,
                        Self.multiClauseKanaPredicateIdentities.contains(segmentReading) {
                        seedIsDictionaryFormPredicate = true
                    }
                    // 辞書に無い活用派生形の seed(読んだ/呼んだ 等の並び矯正)は b2 と同じ
                    // 活用派生フラグを付ける。付けないと dictUnknown(8700)の seed ノードが
                    // 先着 dedupe で b2 の安い活用OOVコピーを潰し、seed 外の同活用
                    // (喚んだ)だけが安く残って逆転する(ほんをよんだ→本を喚んだ)。
                    var seedIsInflectionDerived = false
                    if costMap[surface] == nil,
                        inflectionSupplyGateSatisfied,
                        cachedInflectedCandidates().contains(surface) {
                        seedIsInflectionDerived = true
                    }
                    add(
                        surface,
                        isDictWord: true,
                        isCurated: false,
                        isInflectionDerived: seedIsInflectionDerived,
                        wordCost: costMap[surface],
                        isDictionaryFormPredicate: seedIsDictionaryFormPredicate
                    )
                    // 名詞 seed 順の opt-in(にほん→日本 等)は先頭候補ノードにボーナスを与え、
                    // 数量詞複合(2本/二本)や分割に連文節でも勝たせる(値は読み別)。
                    if let bonus = Self.multiClauseSeedOrderNounBonusesByReading[segmentReading],
                        surface == KanaKanjiSeedDictionary.seed[segmentReading]?.first {
                        seedOrderNounNodeBonuses["\(start)-\(end)-\(surface)"] = bonus
                    }
                }

                // (b) word_costs(Sudachi 由来)から top-K を列挙。抑制語彙は除外。
                //     促音「っ」で終わる読みは日本語の語として自立しない断片(かっ/きっ 等)で、
                //     Sudachi の複合語内読み(核=カッ 等)由来の漢字ノードがジャンク合成
                //     (いきだけかったぜ→行きだけ核たぜ)を作るため、漢字含み表層は弾く。
                if !costMap.isEmpty {
                    let ordered = costMap.sorted { lhs, rhs in
                        lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key < rhs.key
                    }
                    var dictCount = 0
                    for (surface, cost) in ordered {
                        if segmentEndsWithSokuon, containsKanji(surface) {
                            continue
                        }
                        // 辞書形述語判定(ノード定義コメント参照)。床免除(読み≤2)に加えて
                        // のね/のよ の述語直後クランプでも使うため、長さゲートは置かず
                        // 「漢字+かな活用尾(炊く/書く/重い)」の形状だけで問い合わせを絞る
                        // (読み別キャッシュ済み)。
                        var isDictionaryFormPredicate = false
                        if let lastChar = surface.last,
                            Self.multiClauseDictionaryFormTailCharacters.contains(lastChar),
                            containsKanji(surface) {
                            isDictionaryFormPredicate = store.isShortReadingDictionaryFormPredicate(
                                reading: segmentReading,
                                candidate: surface
                            )
                        }
                        add(
                            surface,
                            isDictWord: true,
                            isCurated: false,
                            wordCost: cost,
                            isDictionaryFormPredicate: isDictionaryFormPredicate
                        )
                        if Self.isKatakanaString(surface),
                            supplementalSystemDictionary[segmentReading]?.contains(surface) == true {
                            supplementalKatakanaExemptNodeKeys.insert("\(start)-\(end)-\(surface)")
                        }
                        dictCount += 1
                        if dictCount >= Self.multiClauseTopK {
                            break
                        }
                    }
                }

                // (b2) 活用派生ノード: 活用形(買った/行ける 等)は辞書に収穫しない設計のため、
                //      活用エンジンから供給する。表層は LM 未収録が普通で dictUnknown(8700)が
                //      付くが、断片合成(核+た)や素通りよりは安く、「いきだけかったぜ→
                //      行きだけ買ったぜ」型の分割を可能にする。コスト抑制のため span 長 2〜8、
                //      活用ルール末尾文字に一致する読みのみ、上位3件に限定。
                if inflectionSupplyGateSatisfied {
                    let inflected = cachedInflectedCandidates()
                    // 「直前ノード+て」が連用形接続かの判定に使う(定数コメント参照)
                    inflectedSurfacesBySpan["\(start)-\(end)"] = Set(inflected)
                    // このスパンを脱活用した基底読みが seed順ボーナス allowlist に含まれるか。
                    // (つかえた/つかえ→つかえる 等。含まれる時だけ先頭活用形にボーナス)
                    let spanBaseInSeedOrderAllowlist: Bool = {
                        guard let lastChar = segmentReading.last,
                            let rules = Self.deinflectionRulesByReadingLastCharacter[lastChar] else {
                            return false
                        }
                        for rule in rules where !rule.readingSuffix.isEmpty && segmentReading.hasSuffix(rule.readingSuffix) {
                            let stem = segmentReading.dropLast(rule.readingSuffix.count)
                            guard !stem.isEmpty else { continue }
                            if Self.multiClauseSeedOrderInflectionBaseReadings.contains(stem + rule.baseReadingSuffix) {
                                return true
                            }
                        }
                        return false
                    }()
                    // かな識別(surface==読み)は原則除外(かなエコー防止)。ただし活用エンジンが
                    // かなを第1候補に据えた場合=基底並べ替えが isLMKanaPreferred でかな基底を
                    // 先頭化した場合(なる 3405≪成る/ある/いる/できる 等、かなが LM 優位な動詞)は、
                    // かなが正書なので活用形もかなを供給する。除外したままだと なった が捨てられ
                    // 成った/為った だけが残る(べんりにはなったな→便利には成ったな)。LM 劣位の
                    // 動詞(食べる/見る=たべる/みる が非優位)は依然として漢字が第1候補=かな除外。
                    // かな識別の除外(下記 where 条件)を prefix の後にやると、除外された
                    // かなが枠を潰して次点(かって の 勝って 等)が入れない。先に除外してから
                    // topK 件を採る。
                    var suppliedInflectionCount = 0
                    var suppliedInflectionSurfaces = Set<String>()
                    for (offset, surface) in inflected.enumerated() {
                        if surface == segmentReading, offset != 0 {
                            continue
                        }
                        add(surface, isDictWord: true, isCurated: false, isInflectionDerived: true)
                        suppliedInflectionSurfaces.insert(surface)
                        // スパン先頭(seed/辞書順で最優先)の漢字活用形を連文節ボーナス対象に
                        // 記録。ただし基底読みが allowlist の時のみ(見た/呼んだ 等への波及回避)。
                        if suppliedInflectionCount == 0, surface != segmentReading,
                            spanBaseInSeedOrderAllowlist {
                            preferredInflectedNodeKeys.insert("\(start)-\(end)-\(surface)")
                        }
                        suppliedInflectionCount += 1
                        if suppliedInflectionCount >= Self.multiClauseInflectionTopK {
                            break
                        }
                    }
                    // (b2b) 未代表族の追加供給: 同じ活用形が複数の基底読みから導出できるとき
                    // (はったら=はう系/はる系 等)、先行族が topK を占有すると後続族
                    // (貼ったら/張ったら)はノード自体が立たず LM 競争にすら参加できない
                    // (基底読み間順序の5例目)。topK に代表がいない族のうち、寄与基底の
                    // unigram 最小値が既代表族より明確に優勢(小さい)なものだけ先頭2件を
                    // 追加供給する — 供給の追加のみで既存の並び・ボーナスには触れない。
                    // 優劣ゲートが無いと、借用統計に乗るジャンク族(充て(みて)←あて 等、
                    // 基底が LM 未収録の文語)まで入って既存の最良を壊す。
                    if suppliedInflectionCount >= Self.multiClauseInflectionTopK {
                        let families = inflectionCandidateFamilies(
                            for: segmentReading,
                            userDictionary: manualUserDictionary,
                            initialUserDictionary: initialUserDictionary,
                            systemCandidateMode: systemCandidateMode,
                            perFamilyLimit: 2
                        )
                        let representedBestKey = families
                            .filter { $0.items.contains(where: { suppliedInflectionSurfaces.contains($0) }) }
                            .map(\.familyKey)
                            .min() ?? Int.max
                        for family in families
                        where !family.items.contains(where: { suppliedInflectionSurfaces.contains($0) })
                            && family.familyKey < representedBestKey {
                            for (offset, surface) in family.items.enumerated() where surface != segmentReading {
                                add(surface, isDictWord: true, isCurated: false, isInflectionDerived: true)
                                // 追加は後着列挙のため、OOV同点(全候補LM未収録=7200)の
                                // タイブレーク(列挙順)で既存族に必ず負ける。先行ボーナス(800)は
                                // 無差別に与えると22件退行(2424検証)するため、既存の
                                // seed順allowlist(opt-in)に掲載された基底読みの族に限定する
                                // (はる → ろぐはったら=ログ貼ったら)。
                                if offset == 0,
                                    Self.multiClauseInflectionFamilyPreferenceBaseReadings
                                        .contains(family.baseReading) {
                                    preferredInflectedNodeKeys.insert("\(start)-\(end)-\(surface)")
                                }
                            }
                        }
                    }
                }

                // (b3) 丁寧接頭辞派生ノード: お/ご+連用形(お渡し/お預かり/お届け 等)は
                //      Sudachi に1語で収穫されないことが多く(お願い/お知らせ は例外的に有る)、
                //      おわた+し のような断片合成に負ける。politePrefix 経路から上位を供給する。
                //      コストは dictUnknown(8700)扱い(isInflectionDerived を付けない)。派生の
                //      7200 だと Sudachi 実在の お店(unigram 7099+500)を お見せ が逆転してしまう。
                //      断片合成(苧綿+視 ≈16000)には 8700 でも十分勝てる。
                if len >= 3,
                    let firstChar = segmentReading.first,
                    firstChar == "お" || firstChar == "ご" {
                    let polite = politePrefixPassthroughCandidates(
                        for: segmentReading,
                        userDictionary: manualUserDictionary,
                        initialUserDictionary: initialUserDictionary,
                        systemCandidateMode: systemCandidateMode,
                        limit: Self.multiClauseInflectionTopK
                    )
                    // 同スパンに実辞書語(収穫底値未満)があれば合成ノードを後置(定数コメント参照)
                    let spanHasRealDictWord = costMap.values.contains {
                        $0 < KanaKanjiConverter.CandidateScore.harvestTierWordCostFloor
                    }
                    for surface in polite.prefix(Self.multiClauseInflectionTopK)
                    where surface != segmentReading {
                        add(surface, isDictWord: true, isCurated: false)
                        if spanHasRealDictWord {
                            politeSupplementDemotedNodeKeys.insert("\(start)-\(end)-\(surface)")
                        }
                    }
                }

                // (b4) 数量詞複合ノード: 何件/何軒/何本/何枚/数台 等はロジック生成で
                //      word_costs に無いため、連文節では 何県 分割や 軟堅 に負ける。
                //      単文節と同じ numericCounterCompoundCandidates を供給する。
                //      コストは活用派生と同じ(7200)= 分割ゴミには勝つが なんかい→難解
                //      のような実在の非数量語には基本負ける穏当な強さ。
                if len >= 2 {
                    // 算用数字+助数詞(2本/第1回)を漢数字より先に供給(ユーザ方針: 算用優先)。
                    for surface in arabicNumericCompoundCandidates(for: segmentReading)
                    where surface != segmentReading {
                        add(surface, isDictWord: true, isCurated: false, isInflectionDerived: true)
                    }
                    let numeric = numericCounterCompoundCandidates(
                        for: segmentReading,
                        userDictionary: manualUserDictionary,
                        initialUserDictionary: initialUserDictionary,
                        systemCandidateMode: systemCandidateMode,
                        limit: Self.multiClauseInflectionTopK
                    )
                    for surface in numeric.prefix(Self.multiClauseInflectionTopK)
                    where surface != segmentReading {
                        add(surface, isDictWord: true, isCurated: false, isInflectionDerived: true)
                    }
                }

                // (b4) 名詞化節(のが/のは 等)と説明の のね/のよ のかな単位ノードを常設する。
                //      辞書にレア名前(野賀 wc10000 等)だけがあると (c) の素通り補完が走らず、
                //      述語直後クランプの対象ノード自体が立たない(たくのがすき→宅のが好き)。
                if Self.multiClauseNominalizerSurfaces.contains(segmentReading)
                    || Self.multiClauseExplanatoryFinalSurfaces.contains(segmentReading)
                    // 口語終止クラスタ(かなー 等)も常設 — 辞書/wc に無い読みはノード自体が立たず、
                    // クランプ(4000)が適用できない(こんないろかなー→色香なー 対策)
                    || Self.multiClauseColloquialExplanatoryTailReadings.contains(segmentReading)
                    // 授受補助動詞(あげて/くれてる 等)も常設 — 基底LM順(挙げる5399<上げる<
                    // あげる)で b2 のかな供給が落ち、て形直後クランプの対象ノード自体が立たない
                    // (教えてあげて→教えて挙げて 対策。て/で 直後以外では素通りコストのまま)
                    || Self.isTeBenefactiveAuxiliaryReading(segmentReading) {
                    add(segmentReading, isDictWord: false, isCurated: false)
                }

                // (b4c) カ変「来る」の活用形。活用供給順で 着る/衣る/著る(一段)の後に回り
                //      来た/来て 等が topK から漏れて連文節に載らず、食べに来た鳥→食べに北鳥 等の
                //      名詞化(北)に負ける。来〜 を明示ノードで供給(北 とは競合させ LM に委ねる)。
                if let kuruSurface = Self.multiClauseKuruFormSurfaces[segmentReading] {
                    add(kuruSurface, isDictWord: true, isCurated: false, isInflectionDerived: true)
                }

                // (b5) 連用形+に(目的: 食べに来る/飲みに行く)ノード。動詞の連用形は活用
                //      エンジンの終点でないため 食べ 単独ノードが立たず、たべにきたとり→た部に…
                //      のような断片合成に落ちる。連用形+に を1単位で供給する(食べに/飲みに)。
                //      名詞+に(机に 等)は連用形が導出できず空になるので誤爆しない。
                if len >= 3, segmentReading.hasSuffix("に") {
                    let renyouReading = String(segmentReading.dropLast())
                    let renyouNi = verbRenyouPlusSuffixCandidates(
                        renyouReading: renyouReading,
                        trailingSuffix: "に",
                        userDictionary: manualUserDictionary,
                        initialUserDictionary: initialUserDictionary,
                        systemCandidateMode: systemCandidateMode
                    )
                    for surface in renyouNi.prefix(Self.multiClauseInflectionTopK)
                    where surface != segmentReading {
                        add(surface, isDictWord: true, isCurated: false, isInflectionDerived: true)
                        renyouNiNodeKeys.insert("\(start)-\(end)-\(surface)")
                    }
                }

                // (c) word_costs にも無ければかな素通り(最後の手段)。ローンワード的読みはカタカナ表記。
                //     ※以前は candidates() で補完していたが、多字 span に dictUnknown 一律コストの
                //       blob(例: てんきです→天気です)を作り、正しい細分割(天気+です)を大域的に
                //       上回って DP を歪めていた(はいい→配意 等)。活用形は (b2) の活用エンジン
                //       供給(限定的・8700)で拾う。
                if surfaces.isEmpty {
                    let passthrough: String
                    if readingLooksLikeLoanword(segmentReading),
                        len <= Self.multiClauseSupplementMaxLen {
                        passthrough = Self.hiraganaToKatakana(segmentReading)
                    } else {
                        passthrough = segmentReading
                    }
                    add(passthrough, isDictWord: false, isCurated: false)
                }

                for (surface, isDictWord, isCurated, isInflectionDerived, wordCost, isDictionaryFormPredicate) in surfaces {
                    let index = nodes.count
                    nodes.append(MultiClauseNode(
                        start: start,
                        end: end,
                        surface: surface,
                        reading: segmentReading,
                        isDictWord: isDictWord,
                        isCurated: isCurated,
                        isInflectionDerived: isInflectionDerived,
                        wordCost: wordCost,
                        isDictionaryFormPredicate: isDictionaryFormPredicate
                    ))
                    nodesEndingAt[end].append(index)
                    nodesStartingAt[start].append(index)
                }
            }
        }

        // --- 2. LM コスト(unigram/bigram)を一括ロード(sqlite アクセスを最小化) ---
        var unigramSurfaces = Set<String>()
        unigramSurfaces.insert(Self.multiClauseEOSMarker)
        for node in nodes {
            unigramSurfaces.insert(node.surface)
        }
        let unigramCosts = store.wordLMUnigramCosts(for: Array(unigramSurfaces))
        // 読み跨ぎ unigram 借用の遮断用(定数コメント参照)。旧形式 DB では空=機能オフ。
        let candidateMinWordCosts = store.candidateMinWordCosts(for: Array(unigramSurfaces))

        // カタカナ強調表記/交ぜ書きのモード適用(供給後の一括分類。単文節側と同じ述語)。
        // curated(ユーザ明示)は対象外。外来語(パン 等)は「カタカナ側が unigram 優位」で保護。
        // suppress は +100000(事実上不採用)、demote は +6000(後方)を transitionCost で加える。
        if katakanaEmphasisCandidateMode != .normal || mazegakiCandidateMode != .normal {
            // LM未収録カタカナの「代替が存在する限り強調」判定(単文節側と同義)用: 同スパンに
            // 漢字ノード(辞書/活用派生。成った 等)が居るか。代替ゼロの外来語(サジェスチョン=
            // 辞書唯一・LM未収録)まで抑制すると、LM実在の断片(さ+ジェス+チョン)がジャンク
            // 最良になるため、そこだけ保護する。
            var spanHasKanjiSurface = Set<String>()
            for node in nodes where containsKanji(node.surface) {
                spanHasKanjiSurface.insert("\(node.start)-\(node.end)")
            }
            for node in nodes where !node.isCurated {
                let key = "\(node.start)-\(node.end)-\(node.surface)"
                if katakanaEmphasisCandidateMode != .normal,
                    node.surface != node.reading,
                    let hira = KanaKanjiConverter.hiraganizedKanaOnlySurface(node.surface),
                    hira == node.reading,
                    !(KanaKanjiSeedDictionary.seed[node.reading]?.contains(node.surface) ?? false),
                    !(KanaKanjiSeedDictionary.exactReadingOnlySeed[node.reading]?.contains(node.surface) ?? false),
                    !KanaKanjiConverter.katakanaRunsAreSeedProtected(node.surface) {
                    let kataUni = unigramCosts[node.surface]
                    let altUni = unigramCosts[node.reading]
                    let isEmphasis: Bool
                    if let kataUni {
                        isEmphasis = (altUni != nil && altUni! < kataUni)
                    } else {
                        isEmphasis = altUni != nil
                            || spanHasKanjiSurface.contains("\(node.start)-\(node.end)")
                    }
                    if isEmphasis {
                        if katakanaEmphasisCandidateMode == .suppress {
                            scriptVariantSuppressedNodeKeys.insert(key)
                        } else {
                            scriptVariantDemotedNodeKeys.insert(key)
                        }
                        continue
                    }
                }
                if mazegakiCandidateMode != .normal,
                    !node.isInflectionDerived,
                    let kanjiPart = KanaKanjiConverter.mazegakiKanjiPart(node.surface, reading: node.reading) {
                    let sameReadingCosts = store.wordCosts(for: node.reading)
                    let fullKanjiExists = sameReadingCosts.keys.contains { full in
                        full != node.surface
                            && KanaKanjiConverter.isAllKanjiSurface(full)
                            && unigramCosts[full] != nil
                            && kanjiPart.count < full.count
                            && KanaKanjiConverter.isSubsequence(kanjiPart, of: full)
                    }
                    if fullKanjiExists {
                        if mazegakiCandidateMode == .suppress {
                            scriptVariantSuppressedNodeKeys.insert(key)
                        } else {
                            scriptVariantDemotedNodeKeys.insert(key)
                        }
                    }
                }
            }
        }

        var bigramPairs: [(String, String)] = []
        var seenPairs = Set<String>()
        func addPair(_ prev: String, _ cur: String) {
            if seenPairs.insert("\(prev)\t\(cur)").inserted {
                bigramPairs.append((prev, cur))
            }
        }
        for idx in nodesStartingAt[0] {
            addPair(Self.multiClauseBOSMarker, nodes[idx].surface)
        }
        if n >= 1 {
            for boundary in 1..<n {
                for prevIdx in nodesEndingAt[boundary] {
                    let prevNode = nodes[prevIdx]
                    let auxTail = Self.auxTailForBigramBorrow(of: prevNode)
                    for curIdx in nodesStartingAt[boundary] {
                        addPair(prevNode.surface, nodes[curIdx].surface)
                        if let auxTail {
                            addPair(auxTail, nodes[curIdx].surface)
                        }
                    }
                }
            }
        }
        for idx in nodesEndingAt[n] {
            addPair(nodes[idx].surface, Self.multiClauseEOSMarker)
            if let auxTail = Self.auxTailForBigramBorrow(of: nodes[idx]) {
                addPair(auxTail, Self.multiClauseEOSMarker)
            }
        }
        let bigramCosts = store.wordLMBigramCosts(for: bigramPairs)

        // 複合動詞の前部要素になる連用形ノード(定数コメント参照)。列挙後に一度だけ走査する。
        var compoundVerbRenyouNodeKeys = Set<String>()
        for node in nodes
        where Self.multiClauseCompoundVerbRenyouStemReadings.contains(node.reading)
            && node.surface != node.reading
            && node.surface.hasSuffix("り") {
            compoundVerbRenyouNodeKeys.insert("\(node.start)-\(node.end)-\(node.surface)")
        }

        // --- 3. コスト関数(sim_lm.py と一致): bigram / unigram+backoff / 辞書OOV / 素通りper-char ---
        func transitionCost(
            prev: String,
            prevAuxTail: String?,
            surface: String,
            reading: String,
            isDictWord: Bool,
            isCurated: Bool,
            isInflectionDerived: Bool,
            wordCost: Int? = nil,
            isDictionaryFormPredicate: Bool = false,
            prevIsDictionaryFormPredicate: Bool = false,
            prevIsInflectionDerived: Bool = false,
            isShortCuratedFragment: Bool = false,
            isCollocationPreferredKana: Bool = false,
            scriptVariantPenalty: Int = 0,
            prevDeniesOutgoingBigram: Bool = false,
            isSupplementalKatakanaExempt: Bool = false
        ) -> Int {
            var base: Int
            var penaltyForNounHoshii = 0
            // 読み跨ぎ bigram 借用の遮断(定数コメント参照。人(にん/じん)/頭(ず) 等)。
            // 一般則(2423): bigram は表層単位の統計なので、この読みの word_cost が
            // 収穫底値(>=10000)または表層の最安読みから大きく乖離(>=2500)している場合は
            // 主読みの実績とみなして信用しない(ない→曲 4185(きょく用途)を 曲(くせ wc10067)が
            // 借用して やらない曲に を作る穴 — unigram側の底値降格/乖離床(2078/2126/2386)を
            // bigram分岐だけが素通りしていた)。seed 掲載語は人手選別のため免除。
            let crossReadingBigramDenied: Bool = {
                // かな識別(表層==読み)は表層統計がそのまま自分の統計なので借用があり得ない
                // (かな識別の wc は収穫底値(>=10000)が多く、除外しないと できた/してる 等の
                // かな bigram を没収して漢字側に負ける)。seed 掲載語も人手選別のため免除。
                guard let wordCost,
                    surface != reading,
                    !(KanaKanjiSeedDictionary.seed[reading]?.contains(surface) ?? false) else {
                    return false
                }
                if wordCost >= KanaKanjiConverter.CandidateScore.harvestTierWordCostFloor {
                    return true
                }
                if let minWordCost = candidateMinWordCosts[surface],
                    wordCost - minWordCost >= Self.multiClauseCrossReadingUnigramGapThreshold {
                    return true
                }
                return false
            }()
            let deniesBigramBorrow = (Self.multiClauseBigramBorrowDeniedReadingsBySurface[surface]?
                .contains(reading) ?? false) || prevDeniesOutgoingBigram || crossReadingBigramDenied
            // BOS bigram は使わない: LMコーパス(Wikipedia)の「文頭に来やすい語」統計は
            // キーボードの断片入力(文中から打ち始めることが多い)と系統的に食い違い、
            // かくのが→各のが(BOS→各 3715 ≪ BOS→書く 6265)のような歪みを生むため、
            // 文頭は unigram+バックオフで評価する。文中の bigram は従来どおり。
            // EOS bigram は半分に圧縮して使う: 「文末に来やすい語」統計は断片入力と
            // 系統的に食い違う(記事は 〜の勝ち。で終わるが 〜の価値 は文中に続く:
            // 勝ち→EOS 1253 vs 価値→EOS 2399 の差1146が、の→価値 4234 ≪ の→勝ち 5150
            // の正しい優位916を逆転)。ただし全面無効はやり過ぎで、観測 EOS の正しい信号
            // (層2489<そう2945 が 学生層 を守る、さん2020<三3455 が 柚香さん を守る)まで
            // 消える(2094/2101/今回の全面無効で三度検証済み)。フォールバック(2119)との
            // 中間へ圧縮することで、過大な文末選好だけを弱める。
            if prev != Self.multiClauseBOSMarker,
                !deniesBigramBorrow,
                let bigram = bigramCosts["\(prev)\t\(surface)"] {
                if surface == Self.multiClauseEOSMarker {
                    let fallback = (unigramCosts[Self.multiClauseEOSMarker] ?? 1619)
                        + Self.multiClauseBackoffCost
                    base = fallback + (bigram - fallback) / 2
                    // 言いさし・話題断片のかな助詞終わり(〜出すと、/〜だから 等)は Wikipedia の
                    // 「この語は文末に来ない」統計(と→EOS 3879 等)が断片入力と系統的に食い違い、
                    // 半減圧縮でも 出すと が ダスト(EOS1648)に負ける。かな助詞 prev の観測 EOS は
                    // fallback より重くしない(よ→EOS 等、安い側の観測信号は保つ)。
                    if Self.multiClauseCaseParticleSurfaces.contains(prev)
                        || Self.multiClauseFinalParticleReadings.contains(prev) {
                        base = min(base, fallback)
                    }
                } else {
                    base = bigram
                }
            } else if !deniesBigramBorrow,
                let prevAuxTail,
                let auxBigram = bigramCosts["\(prevAuxTail)\t\(surface)"] {
                // 活用派生ノードの末尾助動詞トークンで bigram を代用(買わない→よ を ない→よ で評価)
                if surface == Self.multiClauseEOSMarker {
                    let fallback = (unigramCosts[Self.multiClauseEOSMarker] ?? 1619)
                        + Self.multiClauseBackoffCost
                    base = fallback + (auxBigram - fallback) / 2
                } else {
                    base = auxBigram
                }
            } else if let unigram = unigramCosts[surface] {
                base = unigram + Self.multiClauseBackoffCost
                // 短spanレア読み床上げ(定数コメント参照): 表層 unigram はコーパスA単位分割の
                // 影響で語幹断片(見=4181)や別読みの頻出表層(店=みせ用途)、補助動詞由来の
                // かな断片(み)を過小評価する。短spanの漢字表層とかな識別(助詞類は除外)は
                // Sudachi の読み別コストとの max で評価して断片連鎖を防ぐ。
                // 辞書形述語(inflection_classes 登録)は床上げを免除(ノード定義コメント参照)。
                if let wordCost,
                    !isDictionaryFormPredicate,
                    reading.count <= Self.multiClauseRareReadingFloorMaxReadingCount,
                    containsKanji(surface)
                        || (surface == reading
                            && !isCurated
                            && !Self.multiClauseKanaIdentityFloorExemptReadings.contains(reading)) {
                    base = max(base, wordCost)
                }
                // 会話的時相名詞の unigram キャップ(定数コメント参照)。観測 bigram
                // (機能→が/細菌→が 等)には及ばない水準なので が 文脈は同音側が保たれる。
                if let temporalCap = Self.multiClauseConversationalTemporalNounUnigramCaps[surface] {
                    base = min(base, temporalCap)
                }
                // 収穫底値(wc>=10000)の表層は unigram があっても信頼しない — その unigram
                // は別の主読みの統計で、レア読みがタダ乗りする(田中(でんちゅう12670)が
                // たなか 用途の4821、方面(かたも11000)が ほうめん 用途の4792 に乗って
                // 正解の区切りを奪う)。dictUnknown 分岐の底値降格と同じ水準へ床上げする。
                // seed 掲載語は人手選別のため免除(他の降格と同条件)。
                if let wordCost,
                    wordCost >= KanaKanjiConverter.CandidateScore.harvestTierWordCostFloor,
                    !(KanaKanjiSeedDictionary.seed[reading]?.contains(surface) ?? false) {
                    base = max(base, Self.multiClauseHarvestTierUnknownCost)
                }
                // 読み跨ぎ unigram 借用の一般遮断(定数コメント参照): この読みの word_cost が
                // 表層の全読み最安より大きく乖離していたら unigram は主読みの実績とみなし、
                // word_cost を下限にする(後(うしろ)→後ろ 等。読み3字以上のみ=≤2は短span床
                // 適用済み。単一読みの正直な高コスト語(解像度)は乖離0で無傷)。
                if let wordCost,
                    reading.count >= 3,
                    let minWordCost = candidateMinWordCosts[surface],
                    wordCost - minWordCost >= Self.multiClauseCrossReadingUnigramGapThreshold,
                    !(KanaKanjiSeedDictionary.seed[reading]?.contains(surface) ?? false) {
                    base = max(base, wordCost)
                }
            } else if isInflectionDerived {
                // 格助詞・複合助詞(には/では 等)の直後は述語が続くのが自然なので割引する。
                let prevAllowsInflectionDiscount =
                    Self.multiClauseCaseParticleSurfaces.contains(prev)
                    || Self.multiClauseCompoundParticles.contains(prev)
                base = prevAllowsInflectionDiscount
                    ? Self.multiClauseInflectionAfterParticleCost
                    : Self.multiClauseInflectionDerivedOOVCost
            } else if isDictWord {
                base = Self.multiClauseDictUnknownCost
                // 収穫底値ノードはさらに重く(定数コメント参照)。seed 掲載語(柚香 等、
                // wc が底値でも人手で代表に選んだ語)は単文節の降格と同様に免除する。
                if let wordCost,
                    wordCost >= KanaKanjiConverter.CandidateScore.harvestTierWordCostFloor,
                    !(KanaKanjiSeedDictionary.seed[reading]?.contains(surface) ?? false) {
                    base = Self.multiClauseHarvestTierUnknownCost
                }
            } else {
                base = Self.multiClausePassthroughPerCharCost * reading.count
            }
            // 活用派生ノードは OOV 信頼水準を上限にする。LM unigram に「実在するが高い」表層
            // (付けよう=7743)が、未収録の同族(着けよう=OOV 7200)より高く付いて基底順が
            // 逆転するのを防ぐ(きをつけよう→気を着けよう対策)。bigram が安ければそちらを尊重。
            if isInflectionDerived {
                let prevAllowsInflectionDiscount =
                    Self.multiClauseCaseParticleSurfaces.contains(prev)
                    || Self.multiClauseCompoundParticles.contains(prev)
                base = min(
                    base,
                    prevAllowsInflectionDiscount
                        ? Self.multiClauseInflectionAfterParticleCost
                        : Self.multiClauseInflectionDerivedOOVCost
                )
            }
            // 追加語彙/学習語彙は強い下限で優遇(自然な LM コストがより安ければそちらを尊重)。
            // ただし絵文字/記号のみの表層(sacoche の €/🇮🇳/₿ 等)は本文へ割り込ませないため優遇せず、
            // 列挙のみ(単文節候補としては到達可)。語形(かな/漢字/ラテン字を含む)だけ強化する。
            // 追加語彙は床(1500)で優遇するが、「短い断片が同じ開始位置のより長い辞書語を分断する」
            // ノード(ろー→ロー/raw。ろーぬ→ローヌ を分断)は床を与えず自然コスト(辞書/LM実勢、
            // 未収録=高コスト)にする。個別語ではなく断片の性質(供給側で判定)で ろーぬげんさん→
            // ロー脱げんさん 等の誤分割を抑止する。長い辞書語が無い正当な短語(やつ/気を)は床維持。
            // 単文節(ろー だけ入力→ロー/raw)は別経路なので従来どおり先頭に出る。
            if isCurated, Self.isWordLikeSurface(surface), !isShortCuratedFragment {
                base = min(base, Self.multiClauseCuratedWordCost)
            }
            // 複合助詞(かな表層)を単位ノードとして安価にクランプ。ただし基底の格助詞
            // (には→に/では→で)が直前語からの bigram で期待される時だけに限定する。
            // 便利→に は強 bigram(1427)なので には をクランプして 便利にはなった を通す一方、
            // たにた→で は bigram 未観測(unigram 2597)なので では はクランプせず、
            // で+はかったら(計ったら)の は始まり動詞分割を潰さない(たにたではかったら対策)。
            // 文頭(BOS 直後)も除外し でも→デモ/では→出は 等の巻き添えを防ぐ。
            if prev != Self.multiClauseBOSMarker,
                surface == reading,
                Self.multiClauseCompoundParticles.contains(surface),
                bigramCosts["\(prev)\t\(String(surface.dropLast()))"] != nil {
                base = min(base, Self.multiClauseCompoundParticleCost)
            }
            // 名詞化節 のが/のは/のを/のも/のに は述語形直後のみ安価にクランプ(定数コメント参照)。
            if prev != Self.multiClauseBOSMarker,
                surface == reading,
                Self.multiClauseNominalizerSurfaces.contains(surface),
                prev.last.map({ Self.multiClausePredicateTailCharacters.contains($0) }) ?? false {
                base = min(base, Self.multiClauseNominalizerAfterPredicateCost)
            }
            // 願望の ほしい/欲しい は て形等の述語直後が正書(買ってほしい)。名詞直後
            // (勝手ほしい)は「が」の脱落形でしか成立せず不自然なので減点する
            // (かってほしい の変種枠を 勝手ほしい が潰し、勝ってほしい が入れない対策)。
            if reading == "ほしい",
                prev != Self.multiClauseBOSMarker,
                !prevIsInflectionDerived,
                !prevIsDictionaryFormPredicate,
                !(prev.last.map { Self.multiClausePredicateTailCharacters.contains($0) } ?? false) {
                penaltyForNounHoshii = Self.multiClauseNounHoshiiPenalty
            }
            // て形直後の授受補助動詞(使ってくれない/してくれてる 等)はかなが正書。紅(名詞
            // くれない)や 暮れてる が繰り上がるのを、かな識別を安価にして防ぐ。prev が て/で
            // 終わり(て形)限定。
            if surface == reading,
                Self.isTeBenefactiveAuxiliaryReading(reading),
                prev != Self.multiClauseBOSMarker,
                (prev.hasSuffix("て") || prev.hasSuffix("で")) {
                base = min(base, Self.multiClauseKanaAdverbCost)
            }
            // 様態の そう(かな)は形容動詞語幹の直後が正書(便利そう/元気そう/静かそう)。
            // 形容動詞かどうかは LM の分布で判定する: prev→な の bigram コストが十分低い
            // (便利→な491/静か→な425/元気→な1129 等、強い連体接続)ことが「形容動詞語幹」の
            // 証拠。単なる名詞の偶発的 →な(馬→な2944 等)は閾値で除外する — でないと
            // 馬+そう が誤クランプされ 旨そう(い形容詞派生)を潰す(うまそうではある→馬そう…)。
            // な はラティスの隣接ペア先読みに載らないため store の点クエリ(キャッシュ済み)で引く。
            if surface == reading,
                reading == "そう",
                prev != Self.multiClauseBOSMarker,
                let naCost = store.wordLMBigramCosts(for: [(prev, "な")])["\(prev)\tな"],
                naCost <= Self.multiClauseNaAdjectiveBigramThreshold {
                base = min(base, Self.multiClauseNominalizerAfterPredicateCost)
            }
            // 説明・詠嘆の のね/のよ は辞書形述語(ノードフラグ)直後のみ安価にクランプ
            // (定数コメント参照)。表層末尾文字では名詞 思い と形容詞 重い を区別できない
            // ため、こちらは inflection_classes 由来のフラグでゲートする。
            if surface == reading,
                Self.multiClauseExplanatoryFinalSurfaces.contains(surface),
                prevIsDictionaryFormPredicate || prevIsInflectionDerived {
                // 活用派生(た形/て形: 置いたのよ/食べたのね)直後も説明・詠嘆の正書。
                // 名詞(思い 等)は活用派生ノードにならないため誤爆しない(2434)
                base = min(base, Self.multiClauseNominalizerAfterPredicateCost)
            }
            var penalty = 0
            penalty += penaltyForNounHoshii
            // 係助詞「は」(では/には/とは 等の複合助詞末尾含む)直後の ある は漢字化しない=
            // かな正書(定数コメント参照)。変種生成(pairCost)も本関数を通るため 有る/在る/或る を
            // 変種枠から落とす(うまそうでは有る 対策)。格助詞 が/を の後(在庫がある 等)は対象外。
            if reading == "ある",
                surface != "ある",
                containsKanji(surface),
                prev != Self.multiClauseBOSMarker,
                prev.hasSuffix("は") {
                penalty += Self.multiClauseAruKanjiAfterWaPenalty
            }
            // 接頭辞「お」(かな)+ そい は おそい(遅い)の誤分割。お添い/お沿い を変種から落とす。
            if reading == "そい", prev == "お" {
                penalty += Self.multiClauseHonorificOsoiSplitPenalty
            }
            // おそい の お接頭漢字表層(お添い/お沿い=お+添う/沿う連用の誤合成)も同様に減点する。
            // 遅い/おそい 以外で お始まりの漢字表層はこの読みでは不要。
            if reading == "おそい", surface != "おそい", surface.hasPrefix("お"), containsKanji(surface) {
                penalty += Self.multiClauseHonorificOsoiSplitPenalty
            }
            // かな正書の副詞(いまだに 等)・口語終止クラスタ(んだが/んです…)はかな識別を安価にして
            // 漢字/レア語/分割より上位にする。
            if surface == reading,
                Self.multiClauseKanaAdverbReadings.contains(reading)
                    || Self.multiClauseColloquialExplanatoryTailReadings.contains(reading) {
                base = min(base, Self.multiClauseKanaAdverbCost)
            }
            // オノマトペ「〜っと」(4文字以上の全かな。ぱしゃっと/ばたっと/ふわっと 等)はかなが正書。
            // ぱ+シャット のような かな断片+カタカナ語 の合成に勝たせる。きっと/ずっと/もっと(3文字)
            // は文字数条件で対象外(既存の価格付けを尊重)。
            if surface == reading,
                reading.count >= 4,
                reading.hasSuffix("っと") {
                base = min(base, Self.multiClauseKanaAdverbCost)
            }
            // 文節先頭(直前=BOS)の存在動詞かな過去(あった/いた)はかな正書を優先(あったんで→
            // かな先頭)。文節先頭に限定するので 気があった/目があった/サイズが合った 等(あった の
            // 直前が が/に で prev≠BOS)は無影響=「連文節でないときだけ」というユーザ指定を満たす。
            // かな副詞(もう/まだ)直後も文節先頭同等に扱う(もうあった/まだいた のかな正書。
            // 気があった 等の が/に 直後は従来どおり対象外)
            if surface == reading,
                prev == Self.multiClauseBOSMarker || prev == "もう" || prev == "まだ",
                Self.multiClauseClauseInitialKanaExistentialPasts.contains(reading) {
                base = min(base, Self.multiClauseKanaAdverbCost)
            }
            // 連語文脈でかな名詞を優先(ひび+入る=罅が入る)。かな ひび を 日々(LM5616)より安くする。
            if isCollocationPreferredKana {
                base = min(base, Self.multiClauseKanaAdverbCost)
            }
            // 単漢字名詞→動詞の無助詞接続の減点(定数コメント参照)。prev が単漢字の
            // 漢字表層で、現ノードが動詞(活用派生 or 辞書形述語)のとき。
            if prev.count == 1,
                containsKanji(prev),
                !prevIsInflectionDerived,
                isInflectionDerived || isDictionaryFormPredicate {
                penalty += Self.multiClauseSingleKanjiNounBeforeVerbPenalty
            }
            // 辞書形動詞(終止形。描く/走る 等)+ して/する/した は非文法(正しくは て形)。誤合成を減点。
            if prevIsDictionaryFormPredicate,
                reading == "して" || reading == "する" || reading == "した" || reading == "します" {
                penalty += Self.multiClauseDictionaryFormPlusSuruPenalty
            }
            // コピュラ終止「だ」直後の動詞(定数コメント参照)。さいやくだけおとして→災厄だ蹴落として
            // のような だ|け 誤分割を、だけ(副助詞)+動詞 の正しい区切りに負けさせる。
            if prev == "だ",
                isInflectionDerived || isDictionaryFormPredicate {
                penalty += Self.multiClauseCopulaDaBeforeVerbPenalty
            }
            // 並列助詞「や」直後の敬称さん(定数コメント参照)。薬屋さん/花屋さん の 屋 分断を排除。
            if prev == "や", reading == "さん" {
                penalty += Self.multiClauseParallelYaBeforeSanPenalty
            }
            // カタカナ化ペナルティ(何でもカタカナ化の抑止)。ただし LM unigram を持つ表層は
            // コーパス実在の外来語(サイズ/ゲスト 等、長音なしで readingLooksLikeLoanword に
            // 引っかからない語)なので対象外 — LM が既に価格付けしており二重減点は不当。
            if Self.isKatakanaString(surface),
                !readingLooksLikeLoanword(reading),
                unigramCosts[surface] == nil,
                !isSupplementalKatakanaExempt {
                penalty += Self.multiClauseKatakanaNativeCost
            }
            // を 跨ぎ文節の防止。ただし curated(気をつけて/気が合う 等、を/が 含みで明示登録
            // された慣用句)は正当な1文節なので免除する — でないと misc の 気を〜 慣用句群が
            // 連文節に一切乗れず、きをつけて→機をつけて 等の分割に負ける。
            if reading.count > 1, reading.contains("を"), !isCurated {
                penalty += Self.multiClauseForbiddenPenaltyCost
            }
            // 撥音「ん」等の語頭禁止。単独「ん」は準体助詞(切る+ん+だ/行った+ん=のだ縮約)だが、
            // これは述語の連体形直後にのみ立てる。直前文節の末尾が述語末尾文字
            // (multiClausePredicateTailCharacters=う/く/…/る/い/た/だ)のときだけ免除し、
            // 脱げ+ん のような非述語直後の偽準体助詞は禁止する — ろーぬげんさん→ロー脱げんさん の
            // ような「ん始まり文節」の誤分割を個別語ではなく汎用ルールで排除する。
            // って/っていう(引用・話題)は従来どおり無条件免除。
            if let first = reading.first,
                Self.multiClauseForbiddenInitials.contains(first) {
                let isForbiddenInitialExempt: Bool
                if reading == "ん" {
                    isForbiddenInitialExempt = prev != Self.multiClauseBOSMarker
                        && (prev.last.map(Self.multiClausePredicateTailCharacters.contains) ?? false)
                } else {
                    isForbiddenInitialExempt = Self.multiClauseForbiddenInitialExemptReadings.contains(reading)
                }
                if !isForbiddenInitialExempt {
                    penalty += Self.multiClauseForbiddenPenaltyCost
                }
            }
            // 促音「っ」で終わる読みの文節(かっ/カッ 等)は日本語の自立語として成立しない断片。
            // LM コーパスが活用形を A単位(買っ+た)で分割する影響で断片チェーンが不当に安く
            // なり、正しい活用ノード(買った 7200)を阻むため強く減点する。
            // (あっ/えっ 等の感動詞の単独入力は単文節経路が扱うので影響しない)
            if reading.count >= 2, reading.hasSuffix("っ"), !isCurated {
                penalty += Self.multiClauseForbiddenPenaltyCost
            }
            // 助動詞「た」の単独ノードは格助詞直後・文頭に立てない(非文法)。A単位分割由来の
            // 安い unigram/bigram(に→た 等)が断片チェーン(に+た+やつ=にたやつ、
            // た+分+最初=たぶん最初 等)を不当に安くし、正しいノード(似た/たぶん)を
            // 阻むため遮断する(2404/2407)。
            if reading == "た", surface == "た",
                prev == Self.multiClauseBOSMarker || Self.multiClauseCaseParticleSurfaces.contains(prev) {
                penalty += Self.multiClauseForbiddenPenaltyCost
            }
            // カタカナ強調/交ぜ書きモードのノード別ペナルティ(suppress=100000/demote=6000)
            penalty += scriptVariantPenalty
            return base + penalty
        }

        // --- 4. Viterbi DP(ノード = (span, 表層)) ---
        let infinity = Int.max / 4
        var best = Array(repeating: infinity, count: nodes.count)
        var backPointer = Array(repeating: -1, count: nodes.count)

        for boundary in 1...n {
            for idx in nodesEndingAt[boundary] {
                let node = nodes[idx]
                // スパン先頭(seed/辞書順で最優先)の活用形へのボーナス(定数コメント参照)。
                let preferredInflectionBonus = (preferredInflectedNodeKeys.contains("\(node.start)-\(node.end)-\(node.surface)")
                    ? Self.multiClausePreferredInflectionBonus
                    : 0)
                    + (seedOrderNounNodeBonuses["\(node.start)-\(node.end)-\(node.surface)"] ?? 0)
                let nodeIsShortCuratedFragment = shortCuratedFragmentNodeKeys.contains("\(node.start)-\(node.end)-\(node.surface)")
                let nodeIsCollocationPreferredKana = collocationPreferredKanaNodeKeys.contains("\(node.start)-\(node.end)-\(node.surface)")
                let nodeKeySV = "\(node.start)-\(node.end)-\(node.surface)"
                let nodeScriptVariantPenalty = (scriptVariantSuppressedNodeKeys.contains(nodeKeySV) ? 100000
                    : (scriptVariantDemotedNodeKeys.contains(nodeKeySV) ? 6000 : 0))
                    + (politeSupplementDemotedNodeKeys.contains(nodeKeySV)
                        ? Self.multiClausePoliteSupplementDemotion
                        : 0)
                let nodeIsSupplementalKatakanaExempt = supplementalKatakanaExemptNodeKeys.contains(nodeKeySV)
                // 〜ったん の丸ごと語 vs コピュラ過去+準体助詞(定数コメント参照)
                let nodeTanContractionPenalty: Int = {
                    guard node.reading.hasSuffix("ったん"),
                        node.surface != node.reading,
                        !node.isInflectionDerived,
                        node.end < n else {
                        return 0
                    }
                    let rest = String(chars[node.end...])
                    for follower in ["だろう", "だろ", "でしょう", "でしょ"] where rest.hasPrefix(follower) {
                        return Self.multiClauseTanContractionSplitPenalty
                    }
                    return 0
                }()
                if node.start == 0 {
                    // 文頭の形式名詞読みは実質名詞(定数コメント参照)。かな側に減点して漢字を優先
                    // こと は直後に格助詞・係助詞が続く形(ことがある/ことでもなく/ことになる)が
                    // 形式名詞用法でかなが正書。実質名詞は「事の起こり」(の+名詞)や
                    // 「事あるごとに」(助詞なしで述語が続く)なので、直後が の または
                    // 助詞以外なら実質名詞として扱う。とき は文頭で接尾辞用法になることが
                    // 稀なので無条件に漢字を優先する(2459)
                    let isFormalKotoUsage: Bool = {
                        guard node.reading == "こと", node.end < n else {
                            return false
                        }
                        let next = chars[node.end]
                        if next == "の" {
                            return false
                        }
                        return Self.multiClauseCaseParticleSurfaces.contains(String(next))
                    }()
                    let substantivePenalty = (
                        Self.multiClauseSubstantiveNounReadings.contains(node.reading)
                            && node.surface == node.reading
                            && !isFormalKotoUsage
                    ) ? Self.multiClauseSubstantiveNounKanaPenalty : 0
                    let cost = transitionCost(
                        prev: Self.multiClauseBOSMarker,
                        prevAuxTail: nil,
                        surface: node.surface,
                        reading: node.reading,
                        isDictWord: node.isDictWord,
                        isCurated: node.isCurated,
                        isInflectionDerived: node.isInflectionDerived,
                        wordCost: node.wordCost,
                        isDictionaryFormPredicate: node.isDictionaryFormPredicate,
                        isShortCuratedFragment: nodeIsShortCuratedFragment,
                        isCollocationPreferredKana: nodeIsCollocationPreferredKana,
                        scriptVariantPenalty: nodeScriptVariantPenalty,
                        isSupplementalKatakanaExempt: nodeIsSupplementalKatakanaExempt
                    ) - preferredInflectionBonus + substantivePenalty + nodeTanContractionPenalty
                    if cost < best[idx] {
                        best[idx] = cost
                        backPointer[idx] = -1
                    }
                }
                for prevIdx in nodesEndingAt[node.start] {
                    let prevCost = best[prevIdx]
                    if prevCost >= infinity {
                        continue
                    }
                    let prevNode = nodes[prevIdx]
                    let prevDeniesOutgoingBigram = Self.multiClauseOutgoingBigramBorrowDeniedReadingsBySurface[prevNode.surface]?
                        .contains(prevNode.reading) ?? false
                    var cost = prevCost + transitionCost(
                        prev: prevNode.surface,
                        prevAuxTail: Self.auxTailForBigramBorrow(of: prevNode),
                        surface: node.surface,
                        reading: node.reading,
                        isDictWord: node.isDictWord,
                        isCurated: node.isCurated,
                        isInflectionDerived: node.isInflectionDerived,
                        wordCost: node.wordCost,
                        isDictionaryFormPredicate: node.isDictionaryFormPredicate,
                        prevIsDictionaryFormPredicate: prevNode.isDictionaryFormPredicate,
                        prevIsInflectionDerived: prevNode.isInflectionDerived,
                        isShortCuratedFragment: nodeIsShortCuratedFragment,
                        isCollocationPreferredKana: nodeIsCollocationPreferredKana,
                        scriptVariantPenalty: nodeScriptVariantPenalty,
                        prevDeniesOutgoingBigram: prevDeniesOutgoingBigram,
                        isSupplementalKatakanaExempt: nodeIsSupplementalKatakanaExempt
                    ) - preferredInflectionBonus + nodeTanContractionPenalty
                    // 述語(活用派生・辞書形)直後の形式名詞・副助詞はかな表記が正書
                    // (行ったとき/貸し出すだけ 等)。漢字表記に減点。
                    if prevNode.isInflectionDerived || prevNode.isDictionaryFormPredicate,
                        Self.multiClauseFormalNounKanaReadings.contains(node.reading),
                        node.surface != node.reading {
                        cost += Self.multiClauseFormalNounKanjiPenalty
                    }
                    // 連用形+に(目的)の直後は移動動詞(来る/行く 系)が来る(食べに来た/飲みに行く)。
                    // 前ノードが b5 の 連用形+に なら、移動動詞にボーナスを与え 北 等の名詞化を退ける。
                    if renyouNiNodeKeys.contains("\(prevNode.start)-\(prevNode.end)-\(prevNode.surface)"),
                        Self.isMotionVerbSurface(node.surface) {
                        cost -= Self.multiClauseRenyouNiMotionVerbBonus
                    }
                    // かな て(接続助詞・補助動詞)は連用形接続(定数コメント参照)。
                    if node.reading.first == "て", node.surface == node.reading,
                        !node.isInflectionDerived,
                        !prevNode.isInflectionDerived,
                        !prevNode.isDictionaryFormPredicate,
                        let derivedForExtendedSpan =
                            inflectedSurfacesBySpan["\(prevNode.start)-\(prevNode.end + 1)"],
                        containsKanji(prevNode.surface),
                        !derivedForExtendedSpan.contains(prevNode.surface + "て") {
                        cost += Self.multiClauseKanaTeAfterNonPredicatePenalty
                    }
                    // 複合動詞の前部要素(連用形)+動詞(定数コメント参照)。取り/撮り忘れている を
                    // 鳥忘れている に勝たせる。
                    if compoundVerbRenyouNodeKeys.contains("\(prevNode.start)-\(prevNode.end)-\(prevNode.surface)"),
                        node.isInflectionDerived || node.isDictionaryFormPredicate {
                        cost -= Self.multiClauseCompoundVerbRenyouBonus
                    }
                    // 格助詞 に 直後のカ変(来る)活用は移動の到着点用法で最頻(職場に来て/こっちに来た)。
                    // 同読みの一段 着る はを格が普通(服を着て)なので、に 直後に限り来る側を押し上げる。
                    // カ変明示供給ノード(kuru map 一致)に限定し、来手 等の辞書同音や 行/言(いって)には
                    // 触れない。上に着て(重ね着)は稀用法として許容する。連用形+に(飲みに)の直後にも
                    // 等しく与え、のみ+に+来た が 飲みに+来た を新ボーナス差で逆転しないようにする。
                    if (prevNode.surface == "に" && prevNode.reading == "に")
                        || renyouNiNodeKeys.contains("\(prevNode.start)-\(prevNode.end)-\(prevNode.surface)"),
                        node.isInflectionDerived,
                        Self.multiClauseKuruFormSurfaces[node.reading] == node.surface {
                        cost -= Self.multiClauseNiKuruArrivalBonus
                    }
                    // 同音異義 あう の出し分け(best-effort): 現ノードが あう活用(会う/合う)で
                    // 直前が「に」なら、その前の名詞の人物性で優先を決める。人物→会う、
                    // それ以外→合う。非優先側の表層に減点(前の名詞は backPointer で辿る)。
                    if let auKanji = Self.auVerbLeadingKanji(of: node.surface),
                        Self.multiClauseAuVerbReadings.contains(node.reading),
                        prevNode.reading == "に" || prevNode.reading == "が" {
                        let nounIsPerson: Bool
                        if backPointer[prevIdx] >= 0 {
                            nounIsPerson = Self.isPersonLikeNounSurface(nodes[backPointer[prevIdx]].surface)
                        } else {
                            nounIsPerson = false
                        }
                        // 人物なら 合(=非会)に減点、非人物なら 会 に減点。
                        if nounIsPerson, auKanji == "合" {
                            cost += Self.multiClauseAuPersonMismatchPenalty
                        } else if !nounIsPerson, auKanji == "会" {
                            cost += Self.multiClauseAuPersonMismatchPenalty
                        }
                    }
                    // 敬称 さん/さま は数字の後以外では 山/三/桟 等の漢字接尾にならない。
                    // 名前+さん(かな敬称)を優先するため漢字表層に減点(数字直後は免除)。
                    // 例外: 地域接尾(県/道/府/都 等)直後の 産 は産地表記(愛知県産)なので
                    // 減点せず、逆に かな敬称(愛知県さん)より優先するボーナスを与える(2410)。
                    if Self.multiClauseHonorificSuffixReadings.contains(node.reading),
                        containsKanji(node.surface),
                        !Self.isNumericContextForHonorific(prevSurface: prevNode.surface, prevReading: prevNode.reading) {
                        if node.surface == "産",
                            let prevLast = prevNode.surface.last,
                            KanaKanjiConverter.regionalSuffixCharactersBeforeSan.contains(prevLast) {
                            cost -= Self.multiClauseRegionalProduceBonus
                        } else {
                            cost += Self.multiClauseHonorificKanjiPenalty
                        }
                    }
                    // 地域接尾(県/道/府/都/市 等)直後の 人(じん) は住人表記(京都人/大阪人)。
                    // 人(にん/じん) は読み跨ぎ借用の遮断で unigram+床評価になり、同音の
                    // 陣/尽/腎 等に負けるため、産 と同じボーナスで是正する(2434)
                    if node.reading == "じん", node.surface == "人",
                        let prevLastForJin = prevNode.surface.last,
                        KanaKanjiConverter.regionalSuffixCharactersBeforeSan.contains(prevLastForJin) {
                        cost -= Self.multiClauseRegionalProduceBonus
                    }
                    // 述語(活用派生/辞書形)直後の かち は「〜する価値ない」等の形式名詞的
                    // 用法が主。短span床の僅差(価値7191 vs 勝6795)で 勝/勝ち に負けるため
                    // 価値 にボーナス(行く価値ないね 対策。2434)
                    if node.reading == "かち", node.surface == "価値",
                        prevNode.isInflectionDerived || prevNode.isDictionaryFormPredicate {
                        cost -= Self.multiClausePredicateKachiValueBonus
                    }
                    // 文末の終助詞「な」直前が非述語(地名/名詞)なら減点(三田な を避け 見た+な を優先)。
                    // 助詞(から/まで 等)直後の な は正当(遅いからな)なので免除する。
                    if node.end == n,
                        node.reading == "な",
                        node.surface == "な",
                        !Self.isPredicateLikePrevForConditional(prevNode),
                        !Self.multiClauseCaseParticleSurfaces.contains(prevNode.surface) {
                        cost += Self.multiClauseSentenceFinalNaAfterNounPenalty
                    }
                    // 述語直後の 人(にん/じん) は文法として接続しない(定数コメント参照)。
                    if node.surface == "人",
                        Self.multiClausePersonSuffixSinoReadings.contains(node.reading),
                        Self.isPredicateLikePrevForConditional(prevNode) {
                        cost += Self.multiClauseForbiddenPenaltyCost
                    }
                    // 連体詞直後の かんじ→漢字 に小減点(定数コメント参照。こんな感じ を最良に)。
                    if node.reading == "かんじ",
                        node.surface == "漢字",
                        Self.multiClauseDemonstrativeSurfaces.contains(prevNode.surface) {
                        cost += Self.multiClauseDemonstrativeKanjiPenalty
                    }
                    // 時間経過の名詞(時間/月日 等。助詞 が/も/は 任意)直後の たつ 活用は
                    // 経つ が正書。経 以外の たつ 族表層(立/建 等)に減点(あう の人物性
                    // 判定と同型。時間が経ってたら を最良に)(2408)。
                    if let tatsuKanji = Self.tatsuVerbLeadingKanji(of: node.surface),
                        tatsuKanji != "経",
                        node.reading.hasPrefix("たっ") || node.reading.hasPrefix("たつ") || node.reading.hasPrefix("たち") {
                        let nounSurface: String?
                        if prevNode.surface == "が" || prevNode.surface == "も" || prevNode.surface == "は" {
                            nounSurface = backPointer[prevIdx] >= 0 ? nodes[backPointer[prevIdx]].surface : nil
                        } else {
                            nounSurface = prevNode.surface
                        }
                        if let nounSurface, Self.multiClauseTemporalElapseNounSurfaces.contains(nounSurface) {
                            cost += Self.multiClauseAuPersonMismatchPenalty
                        }
                    }
                    if cost < best[idx] {
                        best[idx] = cost
                        backPointer[idx] = prevIdx
                    } else if cost == best[idx],
                        backPointer[idx] >= 0,
                        Self.isNonNativeScriptSurface(nodes[backPointer[idx]].surface),
                        !Self.isNonNativeScriptSurface(prevNode.surface) {
                        // 完全同コストのタイブレークは非ネイティブ表層(カタカナのみ/ラテン字のみ)
                        // でない経路を優先する。かな入力に対して同じ証拠の強さならカタカナ・
                        // ラテン字化しない方が自然(法律かえるのは: 変える経路 6024+1810 と
                        // カエル経路 6927+907 が 7834 で完全タイ → 変える を採る。かれらは:
                        // curated 彼ら/カレラ/Carrera が 1500 で完全タイ → 彼ら を採る。
                        // 従来はノード列挙順で先に処理された方が勝っていた)。
                        backPointer[idx] = prevIdx
                    }
                }
            }
        }

        // --- 5. EOS 込みで最良の終端ノードを選ぶ ---
        var bestTotal = infinity
        var bestEndIndex = -1
        // 同点タイブレーク: 文末が助詞(かな)の経路を優先する。EOS は unigram を持つため
        // 文末実績のない名詞も uni+バックオフで文を終えられ、助詞終わりと完全同点になる
        // ことがある(あめのひも: 紐+EOS と 日+も+EOS が同点で、列挙順により名詞側が
        // 勝っていた)。同点時のみの介入なので他の均衡には影響しない。
        var bestIsParticleFinal = false
        for idx in nodesEndingAt[n] {
            if best[idx] >= infinity {
                continue
            }
            var eosCost = transitionCost(
                prev: nodes[idx].surface,
                prevAuxTail: Self.auxTailForBigramBorrow(of: nodes[idx]),
                surface: Self.multiClauseEOSMarker,
                reading: "",
                isDictWord: true,
                isCurated: false,
                isInflectionDerived: false
            )
            // curated ノードは EOS 遷移を上限クランプ(定数コメント参照)。
            if nodes[idx].isCurated {
                eosCost = min(eosCost, Self.multiClauseCuratedEOSCost)
            }
            var total = best[idx] + eosCost
            // 文末終助詞クラスタの最長一致ボーナス: かなー(3字) を なー(2字) より優先する
            // (こんないろかなー→色香+なー でなく 色+かなー。文末クラスタは最長で切るのが自然)。
            // 長さ×400 の差分なので、辞書語が明確に安い場合(ばか+なー 等)は逆転しない。
            if nodes[idx].surface == nodes[idx].reading,
                Self.multiClauseFinalParticleReadings.contains(nodes[idx].reading) {
                total -= nodes[idx].reading.count * 400
            }
            // 文末が終助詞クラスタ読み(かな/かも 等)なのに漢字表層(仮名/哉/鴨)なのは不自然。
            if Self.multiClauseFinalParticleReadings.contains(nodes[idx].reading),
                nodes[idx].surface != nodes[idx].reading,
                !nodes[idx].isCurated {
                total += Self.multiClauseFinalParticleKanjiPenalty
            }
            // 文末 そう の全漢字表層(層/僧/草)への減点(定数コメント参照)。直前ノードの
            // 表層がひらがな終わり(ほとんど/たぶん/これも 等)に限定 — 漢字名詞直後は
            // 学生層/富裕層 等の生産的な複合なので減点しない(がくせいそう の防護)。
            if Self.multiClauseSentenceFinalAllKanjiPenaltyReadings.contains(nodes[idx].reading),
                KanaKanjiConverter.isAllKanjiSurface(nodes[idx].surface),
                !nodes[idx].isCurated,
                backPointer[idx] >= 0,
                let prevLast = nodes[backPointer[idx]].surface.unicodeScalars.last,
                (0x3041...0x3096).contains(prevLast.value) {
                total += Self.multiClauseFinalParticleKanjiPenalty
            }
            let isParticleFinal = nodes[idx].surface == nodes[idx].reading
                && (Self.multiClauseCaseParticleSurfaces.contains(nodes[idx].surface)
                    || Self.multiClauseFinalParticleReadings.contains(nodes[idx].reading))
            if total < bestTotal || (total == bestTotal && isParticleFinal && !bestIsParticleFinal) {
                bestTotal = total
                bestEndIndex = idx
                bestIsParticleFinal = isParticleFinal
            }
        }
        guard bestEndIndex >= 0 else {
            return []
        }

        // --- 6. バックトラック(ノード列を保持) ---
        var pathIndices: [Int] = []
        var idx = bestEndIndex
        while idx >= 0 {
            pathIndices.append(idx)
            idx = backPointer[idx]
        }
        pathIndices.reverse()
        guard pathIndices.count >= 2 else {
            return []   // 単文節は既存の単文節経路に任せる
        }

        var segments = pathIndices.map { nodes[$0].surface }
        if true {
            print("TEMPDEBUGPATH \(normalized) -> " + pathIndices.map {
                "[\(nodes[$0].surface)/\(nodes[$0].reading)/d=\(nodes[$0].isInflectionDerived)/p=\(nodes[$0].isDictionaryFormPredicate)/c=\(nodes[$0].isCurated)]"
            }.joined())
        }

        // 仮定の接続助詞「なら」が述語直後で 奈良/楢/ナラ に漢字・カタカナ化した場合は
        // かな なら に是正する(買う奈良→買うなら)。連文節の best 分節は動詞を正しく取れて
        // いる(買う+奈良)ので、助詞区間の表層だけ差し替える。元の漢字版は変種に温存する。
        var conditionalNaraKanjiVariant: String? = nil
        if pathIndices.count >= 2 {
            let lastNode = nodes[pathIndices[pathIndices.count - 1]]
            let prevNode = nodes[pathIndices[pathIndices.count - 2]]
            if Self.multiClauseConditionalParticleReadings.contains(lastNode.reading),
                lastNode.surface != lastNode.reading,
                !lastNode.isCurated,
                Self.isPredicateLikePrevForConditional(prevNode) {
                conditionalNaraKanjiVariant = segments.joined()
                segments[segments.count - 1] = lastNode.reading
            }
        }

        let joined = segments.joined()
        // 全かな結果は原則返さない(素通りの丸ごとエコー防止)。ただし経路に curated ノード
        // (やって/にした 等、かなが正書として明示登録された語)を含む場合は、かな結果が
        // 正規の変換なので返す(やってそうな が候補なしになるのを防ぐ)。
        // 最良が全かなでも変種(そっちはつながる→そっちは繋がる 等の漢字混じり)は正当な
        // 変換なので捨てない — ここで即 return [] すると候補なしになる。
        // 文末が終助詞クラスタのかな表層(いるなー/だなー 等)なら、全かなでも正当な変換
        // (終助詞はかなが正書)なのでエコー抑制の対象外。抑制すると「なー→ナー にしただけ」の
        // 変種(いるナー)が最小 delta で最良に繰り上がってしまう。
        let lastNode = nodes[pathIndices[pathIndices.count - 1]]
        let lastPrevNode = pathIndices.count >= 2 ? nodes[pathIndices[pathIndices.count - 2]] : nil
        // 述語直後のかな「なら」(仮定: 買うなら/するなら)も全かなエコー抑制の対象外。
        let lastIsKanaConditionalNara = Self.multiClauseConditionalParticleReadings.contains(lastNode.reading)
            && lastNode.surface == lastNode.reading
            && (lastPrevNode.map { Self.isPredicateLikePrevForConditional($0) } ?? false)
        // 文末がかなの格助詞/複合助詞(ここでは/そこには 等の話題断片)や名詞化節
        // (ひらがなのは 等)も対象外 — これらはかなが唯一の正書で、抑制すると変種の
        // 漢字化(個々では)が最良に繰り上がってしまう。
        let lastIsKanaCaseParticle = lastNode.surface == lastNode.reading
            && (Self.multiClauseCaseParticleSurfaces.contains(lastNode.surface)
                || Self.multiClauseCompoundParticles.contains(lastNode.surface)
                || Self.multiClauseNominalizerSurfaces.contains(lastNode.surface)
                || Self.multiClauseExplanatoryFinalSurfaces.contains(lastNode.surface))
        let lastIsKanaFinalParticle = (Self.multiClauseFinalParticleReadings.contains(lastNode.reading)
            && lastNode.surface == lastNode.reading)
            || lastIsKanaConditionalNara
            || lastIsKanaCaseParticle
        // 末尾が「漢字語 + 単独の素通りかな1字(非助詞・非辞書・非活用)」は誤分割の余りモーラ
        // (学習した 酒造所(しゅぞうじょ)+ う → 酒造所う が しゅぞうじょう で最良化する等)。
        // このゴミ経路を返さず単文節(seed の 酒造場 等 丸ごと候補)に委ねる。
        // 末尾が「漢字語 + 単独バラ母音1字(あいうえお)」は余りモーラの誤分割(学習した
        // 酒造所(しゅぞうじょ)+ う → 酒造所う が しゅぞうじょう で最良化する等。う は辞書語でも
        // あるため isDictWord では弾けない)。単文節(seed の 酒造場 等 丸ごと候補)に委ねる。
        // 助詞(か/わ/の…)・助動詞(た/て/だ)は母音でないため対象外。
        if lastNode.surface == lastNode.reading,
            !lastNode.isCurated,
            Self.multiClauseDanglingVowelKana.contains(lastNode.reading),
            let prevNode = lastPrevNode,
            containsKanji(prevNode.surface) {
            return []
        }
        // 経路の全ノードが辞書語(素通り無し)の全かな=LM が変換候補の中から かな表記を
        // 選んだ結果(の+こと+です 等、かなが正書の機能語句)。素通りエコーではないので
        // 抑制しない(のことです が の事です に負けて最良を失うのを防ぐ)。
        let allNodesAreDictWords = !pathIndices.contains(where: { !nodes[$0].isDictWord })
        let suppressAllKanaBest = joined == normalized
            && !pathIndices.contains(where: { nodes[$0].isCurated })
            && !lastIsKanaFinalParticle
            && !allNodesAreDictWords
            // て/で+授受補助動詞のかな連鎖で終わる全かな(してくれないかな 等)はかなが正書。
            // b4 常設ノードが くれないかな を1スパン化すると末尾ノードの終助詞免除が
            // 外れるため、joined 全体の一般判定で免除する(keepKana 側と同じ述語)
            && !KanaKanjiConverter.hasTeBenefactiveKanaTail(normalized)

        // --- 7. Nベスト風バリアント: 最良経路の1文節だけを同区間の別表層に差し替えた変種を
        //        コスト差の小さい順に付ける。bigram が拮抗する読み(しかくとらないと→
        //        視覚/資格/四角…)で第2候補以降を提示するため。1文字区間(助詞等)は対象外。
        var variants: [(delta: Int, order: Int, joined: String)] = []
        var variantOrder = 0
        for (pos, nodeIdx) in pathIndices.enumerated() {
            let chosen = nodes[nodeIdx]
            guard chosen.reading.count >= 2 else {
                continue
            }
            let prevSurface = pos > 0 ? nodes[pathIndices[pos - 1]].surface : Self.multiClauseBOSMarker
            let nextNode: MultiClauseNode? = pos + 1 < pathIndices.count ? nodes[pathIndices[pos + 1]] : nil

            func pairCost(_ node: MultiClauseNode, asCurated: Bool = true) -> Int {
                let prevAuxTail: String? = pos > 0
                    ? Self.auxTailForBigramBorrow(of: nodes[pathIndices[pos - 1]])
                    : nil
                let prevIsDictionaryFormPredicate = pos > 0
                    ? nodes[pathIndices[pos - 1]].isDictionaryFormPredicate
                    : false
                let incoming = transitionCost(
                    prev: prevSurface,
                    prevAuxTail: prevAuxTail,
                    surface: node.surface,
                    reading: node.reading,
                    isDictWord: node.isDictWord,
                    isCurated: node.isCurated && asCurated,
                    isInflectionDerived: node.isInflectionDerived,
                    wordCost: node.wordCost,
                    isDictionaryFormPredicate: node.isDictionaryFormPredicate,
                    prevIsDictionaryFormPredicate: prevIsDictionaryFormPredicate,
                    prevIsInflectionDerived: pos > 0
                        ? nodes[pathIndices[pos - 1]].isInflectionDerived
                        : false,
                    isShortCuratedFragment: shortCuratedFragmentNodeKeys.contains("\(node.start)-\(node.end)-\(node.surface)"),
                    isCollocationPreferredKana: collocationPreferredKanaNodeKeys.contains("\(node.start)-\(node.end)-\(node.surface)"),
                    scriptVariantPenalty: scriptVariantSuppressedNodeKeys.contains("\(node.start)-\(node.end)-\(node.surface)") ? 100000
                        : (scriptVariantDemotedNodeKeys.contains("\(node.start)-\(node.end)-\(node.surface)") ? 6000 : 0)
                )
                let outgoing: Int
                if let nextNode {
                    outgoing = transitionCost(
                        prev: node.surface,
                        prevAuxTail: Self.auxTailForBigramBorrow(of: node),
                        surface: nextNode.surface,
                        reading: nextNode.reading,
                        isDictWord: nextNode.isDictWord,
                        isCurated: nextNode.isCurated,
                        isInflectionDerived: nextNode.isInflectionDerived,
                        wordCost: nextNode.wordCost,
                        isDictionaryFormPredicate: nextNode.isDictionaryFormPredicate,
                        prevIsDictionaryFormPredicate: node.isDictionaryFormPredicate,
                        prevIsInflectionDerived: node.isInflectionDerived,
                        isShortCuratedFragment: shortCuratedFragmentNodeKeys.contains("\(nextNode.start)-\(nextNode.end)-\(nextNode.surface)"),
                        isCollocationPreferredKana: collocationPreferredKanaNodeKeys.contains("\(nextNode.start)-\(nextNode.end)-\(nextNode.surface)"),
                        scriptVariantPenalty: scriptVariantSuppressedNodeKeys.contains("\(nextNode.start)-\(nextNode.end)-\(nextNode.surface)") ? 100000
                            : (scriptVariantDemotedNodeKeys.contains("\(nextNode.start)-\(nextNode.end)-\(nextNode.surface)") ? 6000 : 0)
                    )
                } else {
                    var eosCost = transitionCost(
                        prev: node.surface,
                        prevAuxTail: Self.auxTailForBigramBorrow(of: node),
                        surface: Self.multiClauseEOSMarker,
                        reading: "",
                        isDictWord: true,
                        isCurated: false,
                        isInflectionDerived: false
                    )
                    // curated ノードは EOS 遷移を上限クランプ(定数コメント参照)。
                    if node.isCurated {
                        eosCost = min(eosCost, Self.multiClauseCuratedEOSCost)
                    }
                    outgoing = eosCost
                }
                return incoming + outgoing
            }

            // 基準コストは curated 床(1500)を外した自然コストで取る。curated の激安を
            // 基準にすると同区間の代替(殺って 等)のコスト差が常に巨大になり、変種として
            // 表示されなくなるため(経路選択には影響しない=表示順位のみの調整)。
            let baseCost = pairCost(chosen, asCurated: false)
            // ただし curated かな識別(やってる 等、かなが正書の明示登録)の区間では、活用派生の
            // 漢字化(遣ってる/演ってる/犯ってる 等の俗字)だけ curated 床込みの実コスト差で
            // 評価する。natural 基準だと delta≈0 で他区間の正当な変種(皆やってる 等)より
            // 常に上位を占拠してしまう(2404)。単文節経路では従来どおり列挙される。
            let baseCostCurated = (chosen.isCurated && chosen.surface == chosen.reading)
                ? pairCost(chosen, asCurated: true)
                : baseCost
            for altIdx in nodesStartingAt[chosen.start] {
                let alt = nodes[altIdx]
                guard alt.end == chosen.end,
                    alt.surface != chosen.surface else {
                    continue
                }
                // 終助詞クラスタ区間の非かな表層(なー→ナー/名/菜 等)は変種として出さない
                // (終助詞はかなが正書。カタカナ・漢字化は不自然)。
                if Self.multiClauseFinalParticleReadings.contains(alt.reading),
                    alt.surface != alt.reading {
                    continue
                }
                // 敬称区間(さん/さま)の漢字表層(三/讃/様 等)も変種として出さない。
                // 数字直後(だい3 等)と地域接尾直後の 産(愛知県産)は従来どおり許す(2410)。
                if Self.multiClauseHonorificSuffixReadings.contains(alt.reading),
                    containsKanji(alt.surface),
                    !(alt.surface == "産"
                        && prevSurface.last.map(KanaKanjiConverter.regionalSuffixCharactersBeforeSan.contains) == true),
                    !Self.isNumericContextForHonorific(
                        prevSurface: prevSurface,
                        prevReading: pos > 0 ? nodes[pathIndices[pos - 1]].reading : ""
                    ) {
                    continue
                }
                // かな正書の代名詞区間で best がかなを選んでいる場合、旧表記・カタカナへの
                // 差し替え変種は出さない(定数コメント参照)。
                if Self.multiClauseKanaOrthodoxPronounReadings.contains(alt.reading),
                    chosen.surface == chosen.reading,
                    alt.surface != alt.reading {
                    continue
                }
                // 機能語(かな識別免除リスト=助詞/助動詞類)の区間で best がかなを選んで
                // いる場合、カタカナ/ラテン表層への差し替え変種は出さない。Sudachi の
                // カタカナ人名収穫(テル wc3788 等)が安く、してるなあ→しテルなあ のような
                // 人名が文中に割り込む変種を作るため。漢字表層(照る 等)は対象外のまま。
                if Self.multiClauseKanaIdentityFloorExemptReadings.contains(alt.reading),
                    chosen.surface == chosen.reading,
                    Self.isNonNativeScriptSurface(alt.surface) {
                    continue
                }
                let effectiveBase = (alt.isInflectionDerived && containsKanji(alt.surface))
                    ? baseCostCurated
                    : baseCost
                let delta = pairCost(alt) - effectiveBase
                guard delta <= Self.multiClauseVariantMaxDelta else {
                    continue
                }
                var altSegments = segments
                altSegments[pos] = alt.surface
                let variantJoined = altSegments.joined()
                if variantJoined == joined {
                    continue
                }
                // 入力そのままの全かな変種は原則捨てる(エコー防止)が、経路に curated ノード
                // を含む(やめるべし: べし が curated)か、末尾がかなの助詞/名詞化節
                // (ひらがなのは: 語幹かな差し替え+のは)なら、かな結果が正書の変換なので
                // 許す(best 経路の抑制ルールと同じ例外)。
                if variantJoined == normalized {
                    let variantHasCurated = alt.isCurated
                        || pathIndices.enumerated().contains(where: {
                            $0.offset != pos && nodes[$0.element].isCurated
                        })
                    let lastVariantNode = pos == pathIndices.count - 1
                        ? alt
                        : nodes[pathIndices[pathIndices.count - 1]]
                    let variantEndsWithKanaParticle = lastVariantNode.surface == lastVariantNode.reading
                        && (Self.multiClauseFinalParticleReadings.contains(lastVariantNode.reading)
                            || Self.multiClauseCaseParticleSurfaces.contains(lastVariantNode.surface)
                            || Self.multiClauseCompoundParticles.contains(lastVariantNode.surface)
                            || Self.multiClauseNominalizerSurfaces.contains(lastVariantNode.surface)
                            || Self.multiClauseExplanatoryFinalSurfaces.contains(lastVariantNode.surface))
                    if !variantHasCurated && !variantEndsWithKanaParticle {
                        continue
                    }
                }
                variants.append((delta, variantOrder, variantJoined))
                variantOrder += 1
            }
        }

        // 同 delta のタイブレークはノード列挙順(=seed/base優先順)。文字コード順だと
        // 採<撮 で 採れてる が 撮れてる を不当に上回る(でとれてる→で採れてる が先)。
        variants.sort { lhs, rhs in
            lhs.delta != rhs.delta ? lhs.delta < rhs.delta : lhs.order < rhs.order
        }
        var results = suppressAllKanaBest ? [] : [joined]
        for variant in variants where !results.contains(variant.joined) {
            results.append(variant.joined)
            if results.count >= 1 + Self.multiClauseVariantLimit {
                break
            }
        }
        // かなに是正した「なら」の元の漢字版(買う奈良 等)は候補として温存する(#2以降)。
        if let kanjiVariant = conditionalNaraKanjiVariant, !results.contains(kanjiVariant) {
            results.append(kanjiVariant)
        }
        // 旧仮名遣い(ゐゑヰヱ 等)の抑制は単文節と同じく連文節にも適用する(ぐらゐかなー 等)。
        return filterHistoricalKanaSurfaceCandidates(for: normalized, candidates: results)
    }

    // 仮定「なら」の直前が述語(動詞辞書形/形容詞/タ形、または活用派生)か。
    // 述語+なら=かな正書(買うなら)、体言+と+奈良=地名 の区別に使う。
    static func isPredicateLikePrevForConditional(_ prev: MultiClauseNode) -> Bool {
        if prev.isInflectionDerived {
            return true
        }
        return prev.surface.last.map { multiClausePredicateTailCharacters.contains($0) } ?? false
    }

    // 語形(かな・漢字・ラテン字を含む)か。絵文字/記号のみなら false。curated 優遇の対象判定に使う。
    static func isWordLikeSurface(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if (0x3041...0x3096).contains(value)      // ひらがな
                || (0x30A1...0x30FA).contains(value)  // カタカナ
                || value == 0x30FC                    // 長音符
                || (0x4E00...0x9FFF).contains(value)  // CJK 統合漢字
                || (0x3400...0x4DBF).contains(value)  // CJK 拡張A
                || (0x0041...0x005A).contains(value)  // A-Z
                || (0x0061...0x007A).contains(value) { // a-z
                return true
            }
        }
        return false
    }

    // タイブレーク用: カタカナのみ、またはラテン字のみの表層(かな入力に対する
    // 非ネイティブ表記)。同コストならこれらでない表層(漢字/かな)を優先する。
    static func isNonNativeScriptSurface(_ text: String) -> Bool {
        if isKatakanaString(text) {
            return true
        }
        guard !text.isEmpty else {
            return false
        }
        return text.unicodeScalars.allSatisfy { scalar in
            (0x0041...0x005A).contains(scalar.value)
                || (0x0061...0x007A).contains(scalar.value)
        }
    }

    static func isKatakanaString(_ text: String) -> Bool {
        guard !text.isEmpty else {
            return false
        }
        for scalar in text.unicodeScalars {
            // カタカナ(ァ U+30A1 〜 ヺ U+30FA)と長音符(ー U+30FC)。
            if (0x30A1...0x30FA).contains(scalar.value) || scalar.value == 0x30FC {
                continue
            }
            return false
        }
        return true
    }

    func readingLooksLikeLoanword(_ reading: String) -> Bool {
        for character in reading where Self.multiClauseLoanwordMarkers.contains(character) {
            return true
        }
        return false
    }
}
