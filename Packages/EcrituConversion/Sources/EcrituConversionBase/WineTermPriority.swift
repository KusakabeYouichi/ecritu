import Foundation

// ワイン用語優先(デバッグ版専用。3805、ユーザ指定)。
// ワイン語彙(references/vin.plist)にある語のうち、同じ読みの一般語に先頭を取られているもの(どうろ=Douro/ドウロ←道路、
// たな=Tannat←棚、こな=Kona←粉)を、スイッチがオンのとき一般語より先にする。一般語のほうが崩れてもよい(検査・確認用)。
// - 対象の語は下の表が全部。表は tools/build_wine_term_priority_table.py が、vin の全読みを実際に変換した結果から作る
//   (先頭の候補がその読みのワイン用語でない読みを全部拾う)。コンテナーアプリの設定の説明もこの表から出すので、ずれない
// - 読み全体がその語のとき(どうろ)と、助詞が 1 つ付いた形(どうろは)は、ワイン用語を先頭に置く
// - 文の中では、読みが 3 かな以上で、語 LM に無いか稀な語だけ値段に上限を掛けて一般語より安くする(ドウロを擁します/
//   貴腐菌が付く)。2 かな以下(Gin=じん、Dão=だん)と、日常語でもある語(帰還/高価/発声)は文の中では下げない
//   (普通の文が軒並み崩れる)
// - 変換の本体(KanaKanjiConverter.wineTermPriorityEnabled)の初期値はオフ。デバッグ版のキーボードが設定(初期値オン)を読んで
//   オンにする。テストは明示的にオンにしたものだけがこの並びになる
#if DEBUG
public enum WineTermPriority {
    public static let sharedDefaultsKey = "debugWineTermPriorityEnabled"
    // 文の中で値段に上限を掛ける語の読みの長さの下限と、その上限(常用の漢字語の LM の値段 4000〜6000 より安く、登録語の 1500 より高い)
    public static let inSentenceMinReadingCount = 3
    public static let inSentenceWordCostCap = 3000

    public struct Entry {
        let reading: String
        let wineSurfaces: [String]
        // 表を作ったときに先頭だった一般語(説明に出すだけ。変換では使わない)
        public let displacedGeneral: String
        // 文の中でも一般語より先にする語(語 LM に無いか稀な語だけ。帰還/高価/発声 のような日常語は入らない)
        let inSentenceSurfaces: [String]
    }

    // 読み+助詞 の形では先頭に置かない読み(だんの は 段の。Dãoの が先頭だった。だん だけなら Dão が先頭のまま。ユーザ指定 3840)
    static let particleFormExcludedReadings: Set<String> = ["だん"]
    // 読み全体+この助詞 の形も先頭に置く(長い順に試す)
    static let trailingParticles: [String] = ["には", "では", "から", "まで", "より", "とは", "は", "が", "を", "に", "の", "も", "で", "と", "へ", "や"]

    public static let entries: [Entry] = table.split(separator: "\n").compactMap { line in
        let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard columns.count >= 3 else { return nil }
        return Entry(
            reading: String(columns[0]),
            wineSurfaces: columns[1].split(separator: "|").map(String.init),
            displacedGeneral: String(columns[2]),
            inSentenceSurfaces: columns.count >= 4 ? columns[3].split(separator: "|").map(String.init) : []
        )
    }

    static let surfacesByReading: [String: [String]] = Dictionary(
        entries.map { ($0.reading, $0.wineSurfaces) }, uniquingKeysWith: { first, _ in first }
    )
    // 文の中で値段に上限を掛ける語(読みが inSentenceMinReadingCount 以上のものだけ)
    public static let inSentenceSurfacesByReading: [String: [String]] = Dictionary(
        entries.filter { $0.reading.count >= inSentenceMinReadingCount && !$0.inSentenceSurfaces.isEmpty }
            .map { ($0.reading, $0.inSentenceSurfaces) },
        uniquingKeysWith: { first, _ in first }
    )

    public static let entriesByReading: [String: Entry] = Dictionary(entries.map { ($0.reading, $0) }, uniquingKeysWith: { first, _ in first })
    // 表の語がサ変名詞のとき、この活用が付いた形も先頭に置く
    static let suruTails: [String] = [
        "させられる", "させます", "させない", "させる", "させて", "させた", "されます", "されない", "される", "されて", "された",
        "します", "しない", "する", "して", "した",
    ]

    // 候補の並びの先頭に、表の語(読み全体)か 表の語+助詞・サ変の活用 を置く。表に無い読みは触らない
    // isSuruNoun(読み, 語): その語がサ変名詞か。地名など サ変でない語に する を付けた形は作らない(かいしする が 甲斐市する、
    // さくしした が 佐久市した になった。ユーザ指摘 3808)。サ変名詞の一般語(開始/作詞)がそのまま先頭に残る
    public static func ordered(reading: String, candidates: [String], isSuruNoun: (String, String) -> Bool) -> [String] {
        if let surfaces = surfacesByReading[reading] {
            return surfaces + candidates.filter { !surfaces.contains($0) }
        }
        // 読みの終わりの きょうかい は ひらがな を先頭に(清酒酵母の きょうかい6号/7号。後ろに数字を打つ時点では前が確定済みで、
        // 変換のときは数字が来ることが分からない。ユーザ決定 3810)。読み全体か、助詞の直後(正解はきょうかい)だけ。
        // 生産者協会/日本醸造協会 のように名詞に続く形はそのまま
        if reading.hasSuffix(trailingKanaReading), let top = candidates.first,
            let general = trailingKanaGeneralSurfaces.first(where: { top.hasSuffix($0) }) {
            let head = top.dropLast(general.count)
            if head.isEmpty || trailingKanaLeadingParticles.contains(head.last!) {
                let lead = head + trailingKanaReading
                return [String(lead)] + candidates.filter { $0 != lead }
            }
        }
        for particle in trailingParticles where reading.count > particle.count && reading.hasSuffix(particle) {
            let stem = String(reading.dropLast(particle.count))
            guard !particleFormExcludedReadings.contains(stem), let surfaces = surfacesByReading[stem] else { continue }
            let lead = surfaces.map { $0 + particle }
            return lead + candidates.filter { !lead.contains($0) }
        }
        // サ変の形(らっかさせる→落果させる。落下させる が先だった。ユーザ指定 3806): 読みが 表の読み+する の活用で、候補に
        // 一般語+その活用 があれば、一般語の所をワイン用語に替えた形を先頭に置く
        for tail in suruTails where reading.count > tail.count && reading.hasSuffix(tail) {
            guard let entry = entriesByReading[String(reading.dropLast(tail.count))],
                let general = candidates.first(where: { $0 == entry.displacedGeneral + tail }) else { continue }
            let suruSurfaces = entry.wineSurfaces.filter { isSuruNoun(entry.reading, $0) }
            guard !suruSurfaces.isEmpty else { continue }
            let lead = suruSurfaces.map { $0 + general.dropFirst(entry.displacedGeneral.count) }
            return lead + candidates.filter { !lead.contains($0) }
        }
        return candidates
    }

    // コンテナーアプリの設定の説明に出す全対象(読み: ワイン用語(押しのける一般語))
    public static var descriptionLines: [String] {
        entries.map { entry in
            let inSentence = entry.reading.count >= inSentenceMinReadingCount && !entry.inSentenceSurfaces.isEmpty
            return "\(entry.reading): \(entry.wineSurfaces.joined(separator: "、"))(一般語: \(entry.displacedGeneral))\(inSentence ? " ※文の中でも" : "")"
        } + ["\(trailingKanaReading): \(trailingKanaReading)(一般語: 協会) ※読みの終わりだけ(きょうかい6号)"]
    }

    // 読みの終わりで ひらがな を先頭にする語(ordered 参照)
    static let trailingKanaReading = "きょうかい"
    static let trailingKanaGeneralSurfaces = ["協会", "教会", "境界"]
    static let trailingKanaLeadingParticles: Set<Character> = ["は", "の", "が", "を", "に", "で", "と", "も", "や"]

    // 読み<TAB>ワイン用語(| 区切り。先頭に置く順)<TAB>表を作ったときの先頭の一般語<TAB>文の中でも上げる語(| 区切り)。
    // 手で書き換えない(tools/build_wine_term_priority_table.py で作り直す)
    // BEGIN GENERATED TABLE
    static let table = """
    あい	Aÿ|アイ	愛	Aÿ
    あし	葦	足	
    いき	壱岐	行き	
    いしょう	意匠	衣裳	
    いたく	委託	いたく	
    いちょう	萎凋	銀杏	萎凋
    いろづき	色づき	色付き	色づき
    いんど	インド	印度	
    うば	ウバ	乳母	ウバ
    えいが	栄華	映画	栄華
    えんざん	塩山	演算	塩山
    おうとう	黄桃	応答	黄桃
    おきゃくさま	お客様	お客さま	
    おまち	雄町	お待ち	
    かい	櫂	回	櫂
    かいし	甲斐市	開始	甲斐市
    かいしょく	改植	会食	改植
    かいそう	海藻	階層	海藻
    かいむ	海霧	皆無	海霧
    かいゆ	Caillou|カイユ	快癒	Caillou|カイユ
    かぐら	神蔵	神楽	神蔵
    かこう	果梗|花香|河口	加工	果梗|花香
    かす	粕	課す	粕
    かとう	果糖	加藤	果糖
    かめ	甕	噛め	甕
    からめる	カラメル	絡める	カラメル
    かりかた	カリカタ	借り方	カリカタ
    かりゅう	果粒	下流	果粒
    かんき	寒気	換気	寒気
    かんりゅう	寒流	韓流	
    き	樹	き	
    きかん	帰還	期間	
    きが	木香	気が	木香
    きしょう	希少	気象	
    きせい	寄生	規制	
    きたん	忌憚	綺譚	忌憚
    きふ	貴腐	寄付	貴腐
    きふきん	貴腐菌	寄付金	貴腐菌
    きゅうかく	嗅覚	球殻	嗅覚
    きょくりょくしんどう	極力振動	きょくりょく振動	極力振動
    きん	菌	金	
    きんし	菌糸	禁止	菌糸
    ぎんこう	吟香	銀行	吟香
    くま	球磨	熊	球磨
    くまがわ	球磨川	熊川	球磨川
    くりま	クリマ	来間	クリマ
    けいき	契機	景気	
    けいど	珪土|経度	軽度	珪土
    げんかん	厳寒	玄関	厳寒
    げんきん	厳禁	現金	厳禁
    げんこう	元寇	現行	
    げんしゅ	原酒	元首	原酒
    げんすい	原水	減衰	原水
    こい	鯉	来い	
    こいか	鯉科	恋歌	鯉科
    こう	梗	こう	梗
    こうか	高価	効果	
    こうかい	紅海	公開	
    こうぎ	広義	講義	
    こうしつ	硬質	皇室	
    こうすい	硬水	香水	
    こうせい	公正	構成	
    こうち	高地	耕地	
    こうちゅう	口中	校注	口中
    こうてき	好適	公的	好適
    こく	コク	濃く	コク
    こし	漉|枯死	こし	漉
    こっかい	黒海	国会	
    ことなり	コトナリ	異なり	コトナリ
    こな	Kona|コナ	粉	Kona|コナ
    こびん	小ビン	小瓶	小ビン
    こんじょう	混醸	根性	混醸
    こんにゅう	混乳	混入	混乳
    ごうしゅう	豪州	江州	
    さいせん	再栓	再選	再栓
    さいりょう	最良	裁量	
    さくし	佐久市	作詞	
    さけ	saké|サケ	さけ	saké
    さらさら	サラサラ	さらさら	サラサラ
    さん	酸	さん	
    さんが	3芽	参賀	3芽
    さんしょう	山椒	参照	山椒
    さんせい	酸性	賛成	
    ざくろ	ザクロ	柘榴	ザクロ
    ざんとう	残糖	残党	残糖
    しがい	死骸	市街	
    しこう	嗜好	思考	
    ししつ	脂質	資質	
    しも	霜	下	
    しゃこう	遮光	社交	
    しゅうかん	習慣	週間	
    しゅうきょう	州境	宗教	州境
    しゅうりょう	収量	終了	
    しゅし	種子	趣旨	種子
    しゅせき	酒石	主席	酒石
    しゅるい	酒類	種類	
    しょうこう	紹興	商工	紹興
    しょうしゃ	照射	商社	
    しょっかん	触感	食感	触感
    しょとう	初冬	諸島	初冬
    しんし	浸漬	しんし	浸漬
    しんしゅ	新種	新酒	
    しんしゅつ	浸出	進出	浸出
    しんしょう	新梢	心証	新梢
    しんしょく	新植	侵蝕	新植
    しんせき	浸漬	親戚	浸漬
    しんちょう	伸長	慎重	
    じき	磁器	時期	
    じてん	次点	自転	次点
    じゅこう	樹高	受講	樹高
    じょうかん	上燗	上巻	上燗
    じょこう	除梗	徐行	除梗
    じん	Gin|ジン	人	Gin
    すいけい	水系	推計	
    すいしん	水深	推進	
    すずき	スズキ	鈴木	
    すたー	スター	すたー	
    すだち	巣立	酢橘	巣立
    せいけい	成形	整形	
    せいち	静置	聖地	静置
    せいちょう	清澄	成長	
    せいとう	製糖	政党	製糖
    せいりゅう	整粒	清流	整粒
    せっかん	節間	石棺	節間
    せんぱく	船舶	1000泊	
    ぜんぼう	全房	全貌	全房
    そうかい	爽快	総会	爽快
    そば	蕎麦	そば	
    そんだ	Zonda|ソンダ	損だ	Zonda|ソンダ
    たいじょう	帯状	退場	帯状
    たいせい	耐性	体制	
    たな	Tannat|タナ	棚	Tannat|タナ
    たまねぎ	タマネギ	玉ねぎ	
    たら	鱈	たら	鱈
    たんかん	短稈	タンカン	短稈
    たんしょう	短梢	単勝	短梢
    だん	Dão|ダン	段	Dão
    だんじょう	段上	壇上	段上
    ちゃ	チャ	茶	チャ
    ちり	Chile|チリ	地理	Chile
    ちろ	Cirò|チロ	ちろ	Cirò|チロ
    つうかん	通関	痛感	通関
    つぶより	粒選	粒より	粒選
    つる	蔓	鶴	蔓
    ていげん	逓減	提言	逓減
    てんよう	展葉	てんよう	展葉
    でんぱ	伝播	電波	
    とう	糖	とう	
    とうか	糖化	透過	糖化
    とうかせい	糖化性	透過性	糖化性
    とうき	冬季	陶器	
    とかい	Tokaj|トカイ	都会	Tokaj|トカイ
    とちょう	徒長	都庁	徒長
    とみ	登美	富	登美
    どうろ	Douro|ドウロ	道路	Douro|ドウロ
    ないぞう	内臓	内蔵	
    なうさ	Naoussa|ナウサ	ナウさ	Naoussa|ナウサ
    なかて	中生	なかて	中生
    なす	ナス	なす	
    なんか	南下|軟化	なんか	
    なんよう	南陽	南洋	南陽
    にゅうしゅ	乳種	入手	乳種
    ねんど	粘土	年度	
    はこだて	函館	はこだて	
    はっせい	発声	発生	
    はんぎ	Hangi|ハンギ	半疑	Hangi|ハンギ
    ひょう	雹	表	雹
    びんがた	ビン型	紅型	ビン型
    ふる	フル	振る	
    ふれ	Frais|フレ	触れ	Frais|フレ
    ぶどうか	ブドウ科	武道家	ブドウ科
    ほうが	萌芽	ほうが	
    ほうこう	芳香	方向	
    ほうし	胞子	奉仕	
    ほしゅ	補酒	保守	補酒
    まる	Malle|マル	丸	Malle
    みえ	三重	みえ	
    めいじ	明示	明治	
    もくせい	木製	木星	
    もる	Moll|モル	漏る	Moll
    やぎ	山羊|ヤギ	屋宜	
    ゆうりょう	優良	有料	
    ようこう	陽光	要綱	陽光
    ようしょう	要衝	幼少	
    よれる	撚れる	縒れる	撚れる
    らいん	Rhein	LINE	Rhein
    らっか	落果|落花	落下	落果|落花
    らん	Rhin|ラン	蘭	Rhin
    りゅうぜつらん	リュウゼツラン	竜舌蘭	リュウゼツラン
    りょうしゅ	良酒	領主	良酒
    """
    // END GENERATED TABLE
}

#endif
