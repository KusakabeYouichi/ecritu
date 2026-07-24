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
    static let multiClauseSeedOrderInflectionBaseReadings: Set<String> = ["つかえる"]
    // 形容動詞語幹の判定閾値: prev→な の bigram コストがこの値以下なら形容動詞とみなす
    // (便利491/静か425/元気1129 は形容動詞、馬2944 は偶発的な名詞→な なので除外)。
    static let multiClauseNaAdjectiveBigramThreshold = 2000
    // カ変「来る」の活用形(読み→漢字表層)。活用供給順で一段動詞の後に沈むため連文節に
    // 明示供給する。北/着た 等の同音とは競合し LM が文脈で選ぶ(単独 きた→北 は不変)。
    static let multiClauseKuruFormSurfaces: [String: String] = [
        "きた": "来た", "きて": "来て", "くる": "来る", "くれ": "来れ",
        "こない": "来ない", "これる": "来れる", "これた": "来れた"
    ]
    // 連用形+に(目的)直後の移動動詞ボーナス。北(名詞)5190+に→北4818 級を、来た(活用OOV
    // 7200)が上回れる水準に。移動動詞は 来/行/帰/戻 始まりの漢字表層で判定する。
    static let multiClauseRenyouNiMotionVerbBonus = 3500
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
    static let multiClauseFinalParticleReadings: Set<String> = ["かな", "かも", "よね", "かしら", "よな", "かー", "ねー", "なー", "よー", "わー", "のー", "かなー", "よねー", "よねえ", "し", "な", "ね", "よ", "けど", "けどー", "なあ", "ねえ", "よお", "わあ", "だけ"]

    // 敬称の読み。数字の直後以外(=名詞/人名の後)では さん→山/三/桟 等の漢字化は
    // 接尾語にならない(名前+さん=かな敬称 が正書)ので、漢字表層に減点する。
    // 数字の後(十三/二十三 等)は正当な 三 なので免除する。
    static let multiClauseHonorificSuffixReadings: Set<String> = ["さん", "さま"]
    static let multiClauseHonorificKanjiPenalty = 3000
    // 係助詞「は」直後の「ある」はかなが正書(ではある/にはある/とはある 等の概言・提題)。
    // 有る/在る/或る への漢字化は不自然なので減点し、N-best 変種(maxDelta4000)から落とす
    // (うまそうでは有る 対策)。ある はかな正書動詞(seed ある=[ある,有る,在る] のかな先頭)。
    static let multiClauseAruKanjiAfterWaPenalty = 4200
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
        "日": ["び"]
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
    static let multiClauseFormalNounKanaReadings: Set<String> = ["とき", "こと", "もの", "ため", "だけ"]
    static let multiClauseFormalNounKanjiPenalty = 1000
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
        "最近": 5000
    ]
    // 単漢字名詞→動詞の無助詞接続の減点。日本語で名詞が動詞に直接続くには助詞が要る
    // (どうみせる→同見せる/道見せる の 同/道 は音読み接辞で、主語・目的語として裸で
    // 動詞の前に立たない)。A単位分割由来で接辞断片の unigram は安く(同4323 ≪ どう4771)、
    // 床上げ(wc)後も どう(かな識別の床 5271)を279差で下回るため、文法側から減点する。
    // 減点は「単漢字+動詞」の候補同士では等しく掛かり相対順を変えない(花咲く/腹減った 等の
    // 助詞落ち口語は競合もかな識別=床上げ済みのため逆転しない)。かな識別を wc で安くする
    // 案(どう=4200)は そうしん→そう+しん 等の語中分断を生むため不採用(2118検証)。
    static let multiClauseSingleKanjiNounBeforeVerbPenalty = 600
    // 辞書/変換にはあるがコーパス(LM)未収録の語。unigram 最大(8139)+バックオフ(500)より
    // 上に置き「どの既知語よりレア」として扱う。以前の 6000 は LM 中央値(7649)より安く、
    // 八津(OOV)が 奴(unigram 5963)に勝つ・ちゃ〜んと が ちゃんと に勝つ等の OOV 逆転を
    // 起こしていた。候補バー(単一経路)には引き続き全辞書候補が並ぶため、レア語は手動選択
    // +学習(curated 1500)で救済される。
    static let multiClauseDictUnknownCost = 8700
    // 収穫底値(wc>=10000)の丸ごとエントリの連文節コスト。単文節の harvestTier 降格
    // (CandidateScore.harvestTierDictionary)の連文節版。レア名前収穫(廉梛/月叶 等)は
    // 正規の未知語(8700)や活用派生(7200)より信頼が低く、放置すると されんな→
    // 実用化さ+廉梛 のような名前断片が正規の派生+助詞を逆転する。
    static let multiClauseHarvestTierUnknownCost = 9500
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
    static let multiClauseForbiddenPenaltyCost = 100000
    static let multiClauseForbiddenInitials: Set<Character> = [
        "ん", "ー", "っ", "ぁ", "ぃ", "ぅ", "ぇ", "ぉ",
        "ゃ", "ゅ", "ょ", "ゎ", "ゕ", "ゖ", "ゝ", "ゞ", "・"
    ]
    // 語頭禁止の正当な例外。ん は準体助詞(できる+ん+だ)、って/っていう は引用・話題の
    // 助詞(アプリって 等、wc実在の正当語)。って を禁止したままだと 名詞+って が組めず、
    // り を吸収して促音始まりを回避した活用合成ノード(りって)が滑り込む
    // (ふくすうあぷりって→複数アプ+りって)。
    static let multiClauseForbiddenInitialExemptReadings: Set<String> = ["ん", "って", "っていう"]
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
        // (b5) 連用形+に(目的)ノードのキー。直後の移動動詞(来る/行く)を優先するのに使う。
        var renyouNiNodeKeys = Set<String>()
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
                    for (offset, surface) in inflected.enumerated() {
                        if surface == segmentReading, offset != 0 {
                            continue
                        }
                        add(surface, isDictWord: true, isCurated: false, isInflectionDerived: true)
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
                    for surface in polite.prefix(Self.multiClauseInflectionTopK)
                    where surface != segmentReading {
                        add(surface, isDictWord: true, isCurated: false)
                    }
                }

                // (b4) 数量詞複合ノード: 何件/何軒/何本/何枚/数台 等はロジック生成で
                //      word_costs に無いため、連文節では 何県 分割や 軟堅 に負ける。
                //      単文節と同じ numericCounterCompoundCandidates を供給する。
                //      コストは活用派生と同じ(7200)= 分割ゴミには勝つが なんかい→難解
                //      のような実在の非数量語には基本負ける穏当な強さ。
                if len >= 2 {
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
                    || Self.multiClauseExplanatoryFinalSurfaces.contains(segmentReading) {
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
            prevIsInflectionDerived: Bool = false
        ) -> Int {
            var base: Int
            var penaltyForNounHoshii = 0
            // 読み跨ぎ bigram 借用の遮断(定数コメント参照。人(にん/じん)/頭(ず) 等)。
            let deniesBigramBorrow = Self.multiClauseBigramBorrowDeniedReadingsBySurface[surface]?
                .contains(reading) ?? false
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
            if isCurated, Self.isWordLikeSurface(surface) {
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
                prevIsDictionaryFormPredicate {
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
            // 単漢字名詞→動詞の無助詞接続の減点(定数コメント参照)。prev が単漢字の
            // 漢字表層で、現ノードが動詞(活用派生 or 辞書形述語)のとき。
            if prev.count == 1,
                containsKanji(prev),
                !prevIsInflectionDerived,
                isInflectionDerived || isDictionaryFormPredicate {
                penalty += Self.multiClauseSingleKanjiNounBeforeVerbPenalty
            }
            // カタカナ化ペナルティ(何でもカタカナ化の抑止)。ただし LM unigram を持つ表層は
            // コーパス実在の外来語(サイズ/ゲスト 等、長音なしで readingLooksLikeLoanword に
            // 引っかからない語)なので対象外 — LM が既に価格付けしており二重減点は不当。
            if Self.isKatakanaString(surface),
                !readingLooksLikeLoanword(reading),
                unigramCosts[surface] == nil {
                penalty += Self.multiClauseKatakanaNativeCost
            }
            // を 跨ぎ文節の防止。ただし curated(気をつけて/気が合う 等、を/が 含みで明示登録
            // された慣用句)は正当な1文節なので免除する — でないと misc の 気を〜 慣用句群が
            // 連文節に一切乗れず、きをつけて→機をつけて 等の分割に負ける。
            if reading.count > 1, reading.contains("を"), !isCurated {
                penalty += Self.multiClauseForbiddenPenaltyCost
            }
            // 単独の「ん」は準体助詞(できる+ん+だ=のだ縮約)として正当な文節なので
            // 語頭禁止の対象外にする(word_costs に んだ が無く、これを禁じると
            // 〜るんだ/〜んです の文末クラスタが組めず ルン/キルン 等の分割に負ける)。
            if let first = reading.first,
                Self.multiClauseForbiddenInitials.contains(first),
                !Self.multiClauseForbiddenInitialExemptReadings.contains(reading) {
                penalty += Self.multiClauseForbiddenPenaltyCost
            }
            // 促音「っ」で終わる読みの文節(かっ/カッ 等)は日本語の自立語として成立しない断片。
            // LM コーパスが活用形を A単位(買っ+た)で分割する影響で断片チェーンが不当に安く
            // なり、正しい活用ノード(買った 7200)を阻むため強く減点する。
            // (あっ/えっ 等の感動詞の単独入力は単文節経路が扱うので影響しない)
            if reading.count >= 2, reading.hasSuffix("っ"), !isCurated {
                penalty += Self.multiClauseForbiddenPenaltyCost
            }
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
                let preferredInflectionBonus = preferredInflectedNodeKeys.contains("\(node.start)-\(node.end)-\(node.surface)")
                    ? Self.multiClausePreferredInflectionBonus
                    : 0
                if node.start == 0 {
                    let cost = transitionCost(
                        prev: Self.multiClauseBOSMarker,
                        prevAuxTail: nil,
                        surface: node.surface,
                        reading: node.reading,
                        isDictWord: node.isDictWord,
                        isCurated: node.isCurated,
                        isInflectionDerived: node.isInflectionDerived,
                        wordCost: node.wordCost,
                        isDictionaryFormPredicate: node.isDictionaryFormPredicate
                    ) - preferredInflectionBonus
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
                        prevIsInflectionDerived: prevNode.isInflectionDerived
                    ) - preferredInflectionBonus
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
                    if Self.multiClauseHonorificSuffixReadings.contains(node.reading),
                        containsKanji(node.surface),
                        !Self.isNumericContextForHonorific(prevSurface: prevNode.surface, prevReading: prevNode.reading) {
                        cost += Self.multiClauseHonorificKanjiPenalty
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
            // 文末が終助詞クラスタ読み(かな/かも 等)なのに漢字表層(仮名/哉/鴨)なのは不自然。
            if Self.multiClauseFinalParticleReadings.contains(nodes[idx].reading),
                nodes[idx].surface != nodes[idx].reading,
                !nodes[idx].isCurated {
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
        // 経路の全ノードが辞書語(素通り無し)の全かな=LM が変換候補の中から かな表記を
        // 選んだ結果(の+こと+です 等、かなが正書の機能語句)。素通りエコーではないので
        // 抑制しない(のことです が の事です に負けて最良を失うのを防ぐ)。
        let allNodesAreDictWords = !pathIndices.contains(where: { !nodes[$0].isDictWord })
        let suppressAllKanaBest = joined == normalized
            && !pathIndices.contains(where: { nodes[$0].isCurated })
            && !lastIsKanaFinalParticle
            && !allNodesAreDictWords

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
                        : false
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
                        prevIsInflectionDerived: node.isInflectionDerived
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
                let delta = pairCost(alt) - baseCost
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
        return results
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
