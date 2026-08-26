import Foundation

// 複合語派生: 数詞+助数詞・大数位・分数・序数(〜つ目)・名詞+漢字接辞(課/可/別 等)。
extension KanaKanjiConverter {
    static let numericUnitFallbackCandidatesByReading: [String: [String]] = [
        "せんえん": ["千円"],
        "まんえん": ["万円"],
        "おくえん": ["億円"],
        "ちょうえん": ["兆円"]
    ]

    static let numericCounterPrefixCandidatesByReading: [String: [String]] = [
        "いっ": ["一"],
        "きゅう": ["九"],
        "ご": ["五"],
        "さん": ["三"],
        "しち": ["七"],
        "じっ": ["十"],
        "じゅっ": ["十"],
        "に": ["二"],
        "なな": ["七"],
        "なん": ["何"],
        "はっ": ["八"],
        "よん": ["四"],
        "ろっ": ["六"],
        "すう": ["数"]
    ]

    static let numericCounterSuffixCandidatesByReading: [String: [String]] = [
        // もん: 3つとも助数詞なので順序まで明示する(ユーザー指定 2600)。
        //   問 = 問題数 / 門 = 大砲を数える(2門) / 文 = 昔の通貨単位(一文銭)・足袋のサイズ
        // 2を確定してから もん を打つと {もん, 門, 物, 紋, 者, 文, 問, 悶} で問が7位、
        // 第2問/何問 も出なかった。Sudachi は 問 を助数詞可能と付けていない
        // (もん の助数詞は 文 だけ)ので、機械的な洗い出しでも拾えない(2596)
        "もん": ["問", "門", "文"],
        "こ": ["個"],
        "えん": ["円"],
        "えんだま": ["円玉"],
        "えんさつ": ["円札"],
        "かい": ["回"],
        "ごう": ["号"],
        "ごうしゃ": ["号車"],
        "せだい": ["世代"],
        "じ": ["次"],
        "かげつ": ["か月", "カ月", "ヶ月", "ヵ月", "箇月"],
        "かこく": ["か国", "箇国", "カ国", "ヶ国", "ヵ国", "ケ国"],
        "かしょ": ["か所", "箇所", "カ所", "ヶ所", "ヵ所"],
        "けん": ["軒", "件"],
        "しゅうかん": ["週間"],
        "じかん": ["時間"],
        // じつ→日 は本表から数字文脈限定表へ移動(2647): 助数詞単独の 日 は にち 読みが正で、
        // 本表に居ると かな数詞合成が せん+じつ→1000日 を作る。数日(すうじつ)は
        // 数字文脈限定表も引くため健在
        "にち": ["日"],
        "だい": ["台"],
        "にん": ["人"],
        "ねん": ["年"],
        "ほん": ["本"],
        "びょう": ["秒"],
        "ふん": ["分"],
        "ぷん": ["分"],
        "ひき": ["匹"],
        "ぼん": ["本"],
        "びき": ["匹"],
        "まい": ["枚"],
        "さつ": ["冊"],
        "ぽん": ["本"],
        "ぴき": ["匹"],
        "はい": ["倍", "杯"],
        "ばい": ["倍"],
        "はつ": ["発"],
        "ぱつ": ["発"],
        // 親等(親族の距離)。しんとう は辞書に 親等 が未収録(浸透/新党/神道 のみ)で、
        // 何親等/2親等 が組めなかった
        "しんとう": ["親等"],
        // 席(座席)/隻(船舶)。6確定→せき で 席 を先頭に(6せき→6席 の複合も有効化)
        "せき": ["席", "隻"],
        // 万円(金額)。直前が数字のとき 万円 を先頭へ(5確定→まんえん→万円)。
        // 何万円/数万円 は大数位(まん=万)+えん の複合で既に対応済み
        "まんえん": ["万円"],
        // 万石(石高)。62確定→まんごく→62万石(仙台六十二万石 等。ユーザー文脈 2613)
        "まんごく": ["万石"]
    ]

    static let numericCounterAllowedSuffixReadingsByPrefixReading: [String: Set<String>] = [
        // 片(1片=いっぺん/2片=にへん/3片=さんぺん/6片=ろっぺん)も 本/匹 と同じ音便系列
        "いっ": ["ぽん", "ぴき", "ぺん"],
        "きゅう": ["ほん", "ひき", "へん"],
        "ご": ["ほん", "ひき", "へん"],
        "さん": ["ぼん", "びき", "ぺん"],
        "しち": ["にん"],
        "じっ": ["ぽん", "ぴき", "ぺん"],
        "じゅっ": ["ぽん", "ぴき", "ぺん"],
        "に": ["ほん", "ひき", "へん"],
        "なな": ["ほん", "ひき", "へん"],
        // 数詞に付く助数詞は大抵「何」にも付く(ユーザ指摘 2597)。もん を足して 何問 を生成する
        // (辞書に 何N があるのは 何階/何月/何度 だけで、それ以外は生成しないと出ない)
        "なん": [
            "こ", "かい", "かげつ", "かしょ", "けん", "ごう", "ごうしゃ", "しゅうかん", "じかん", "にち", "だい", "にん", "ねん",
            "はい", "ばい", "はつ", "ぱつ", "びょう", "ぷん", "ぼん", "びき", "まい", "しんとう", "ぺん", "もん",
            // 機械洗い出しぶん(数字文脈限定の表に入れた助数詞。何N はここで有効化する)
            "あた", "いんかん", "か", "かいき", "かいり", "かうら", "かかん", "かく", "かごう", "かさね", "かじ", "かじょう", "かそう", "かそん", "かた", "かちょう", "かにち", "かねん", "かぶ", "かよ", "かり", "かん", "かんめ", "がい", "がうら", "がさね", "がた", "がっ", "がつ", "がん", "きゃく", "きょく", "きれ", "きろぐらむ", "きん", "ぎょう", "ぎれ", "くみ", "ぐ", "ぐみ", "けた", "げた", "げっ", "げつ", "げん", "こうじ", "こうにち", "こうねん", "こく", "こま", "ごく", "さお", "さら", "ざお", "ざら", "しな", "しめ", "しゃ", "しゃく", "しゅ", "しゅう", "しゅうき", "しゅうねん", "しょう", "しょく", "しりんぐ", "じつかん", "じめ", "じゃく", "じゅう", "じょう", "じん", "すじ", "すん", "ずん", "せ", "せつ", "せん", "そうばい", "ぞく", "たい", "たく", "たて", "たば", "たび", "たま", "たん", "だ", "だて", "だま", "だん", "ちゃく", "ちょう", "ちょうぶ", "ちょうめ", "つい", "つか", "つがい", "つき", "つぼ", "づき", "て", "てい", "てん", "で", "と", "とう", "とおり", "とん", "ど", "どおり", "なのびょう", "にちかん", "ねんかん", "ねんじ", "はり", "はん", "ばしん", "ばり", "ばりき", "ぱく", "ぱり", "ぱん", "ひょう", "ひろ", "びょうかん", "ぴょう", "ふくろ", "ふり", "ふんかん", "ぶ", "ぶくろ", "ぶり", "ぶん", "ぷり", "ぷんかん", "へいべい", "ぺーじ", "ほ", "ぽ", "ま", "まき", "まわり", "むね", "めい", "めん", "めーとる", "もう", "もく", "もんめ", "よう", "より", "り", "りょう", "りん", "れん", "ろり", "わけ", "わり"
        ],
        "はっ": ["ぽん", "ぴき", "ぺん"],
        "よん": ["ほん", "ひき", "へん"],
        "ろっ": ["ぽん", "ぴき", "ぺん"],
        "すう": [
            "こ", "かい", "かげつ", "かしょ", "けん", "しゅうかん", "じかん", "じつ", "だい", "にん", "ねん",
            "はい", "ばい", "はつ", "ぱつ", "びょう", "ふん", "ひき", "ほん", "まい"
        ]
    ]

    // 大数位(桁). 接頭(数/何/数字)と助数詞の間に挟まる「千・百・万…」を表す。
    // 連濁・促音の読み(ぜん/びゃく/ぴゃく等)も含め、読み一致で正しい組のみ生成する。
    static let numericMagnitudeCandidatesByReading: [(reading: String, candidate: String)] = [
        ("せん", "千"), ("ぜん", "千"),
        ("ひゃく", "百"), ("びゃく", "百"), ("ぴゃく", "百"),
        ("まん", "万"),
        ("おく", "億"),
        ("ちょう", "兆"),
        ("じゅう", "十")
    ]

    // 「分の一」等の分数末尾。助数詞の「分(ふん/ぷん)」とは読み(ぶん)で区別される。
    static let numericFractionSuffixCandidatesByReading: [String: [String]] = [
        "ぶんのいち": ["分の一"]
    ]

    // 名詞に付く生産的な漢字接尾辞(種類別・色別・国別…)。語幹(名詞)+接尾辞漢字。
    // か: 予約課/入場可/自動化/情報科/管理下 のような複合は SudachiDict に単語として
    //     載らないことが多いため、ここで派生させる(家/歌/価 は既存語が辞書にあり非生産的)。
    static let nounKanjiSuffixAffixCandidatesByReading: [(reading: String, candidate: String)] = [
        ("べつ", "別"),
        ("か", "課"),
        ("か", "可"),
        ("か", "化"),
        ("か", "科"),
        ("か", "下"),
        // 産地表記(愛知県産/フランス産 等)。地名に限らず名詞+産 は生産的(2409)
        ("さん", "産"),
        // 住人・出身(京都人/現代人/社会人 等)。名詞+人 は生産的(2434)
        ("じん", "人"),
        // 産地・所属の車(フランス車/日本車/英国車 等)。名詞+車 は生産的(2520)
        ("しゃ", "車")
    ]

    // 名詞に付く生産的な漢字接頭辞(別会社・別人物・別商品…)。接頭辞漢字+語幹(名詞)。
    static let nounKanjiPrefixAffixCandidatesByReading: [(reading: String, candidate: String)] = [
        ("べつ", "別")
    ]

    // 桁の前に来る数字(1..9)の読み。促音形(いっ/はっ/ろっ)含む。長い順に並べる(貪欲一致)。
    static let arabicPlaceDigitReadings: [(reading: String, value: Int)] = [
        ("きゅう", 9), ("はっ", 8), ("はち", 8), ("なな", 7), ("ろっ", 6), ("ろく", 6),
        ("ご", 5), ("よん", 4), ("さん", 3), ("に", 2), ("いっ", 1), ("いち", 1)
    ]
    // 一の位(1..9)の読み。し/しち/く や 助数詞前の促音形(いっ/ろっ/はっ=1本/6本/8本)も含む。
    static let arabicUnitDigitReadings: [(reading: String, value: Int)] = [
        ("きゅう", 9), ("く", 9), ("はち", 8), ("はっ", 8), ("なな", 7), ("しち", 7),
        ("ろく", 6), ("ろっ", 6), ("ご", 5), ("よん", 4), ("し", 4), ("さん", 3),
        ("に", 2), ("いち", 1), ("いっ", 1)
    ]
    // 桁(降順)。連濁マーカ(ぜん/びゃく/ぴゃく)含む。
    static let arabicPlaceMarkers: [(markers: [String], value: Int)] = [
        (["せん", "ぜん"], 1000),
        (["ひゃく", "びゃく", "ぴゃく"], 100),
        (["じゅう", "じゅっ", "じっ"], 10)
    ]
    // 連濁・半濁の桁読みは先行数字が固定(さんぜん/さんびゃく/ろっぴゃく/はっぴゃく)。
    // 単独や他の数字では成立しない(ぜんかい→1000回/びゃくにん→100人 等の誤生成を防ぐ)。
    static let rendakuPlaceMarkerAllowedDigits: [String: Set<Int>] = [
        "ぜん": [3], "びゃく": [3], "ぴゃく": [6, 8]
    ]
    // 和語数詞(〜つ)。ひとつ→1つ 等。
    static let arabicWagoTsuReadings: [String: Int] = [
        "ひとつ": 1, "ふたつ": 2, "みっつ": 3, "よっつ": 4, "いつつ": 5,
        "むっつ": 6, "ななつ": 7, "やっつ": 8, "ここのつ": 9
    ]

    // 漢数字の読み(いち/にじゅう/ごひゃく/さんぜん…)を算用数字値へ。1..9999。純粋な数の読みで
    // なければ nil(末尾に余りが残る=助数詞等が混じる読みは呼び出し側で分離済みが前提)。
    static func japaneseNumberReadingValue(_ reading: String) -> Int? {
        guard !reading.isEmpty else {
            return nil
        }
        var rest = Substring(reading)
        var total = 0
        var matchedAnything = false
        for place in arabicPlaceMarkers {
            var digit = 1
            var digitMatched = false
            for (dr, dv) in arabicPlaceDigitReadings where rest.hasPrefix(dr) {
                let after = rest.dropFirst(dr.count)
                if place.markers.contains(where: { after.hasPrefix($0) }) {
                    digit = dv
                    digitMatched = true
                    rest = after
                    break
                }
            }
            for marker in place.markers where rest.hasPrefix(marker) {
                if let allowed = rendakuPlaceMarkerAllowedDigits[marker],
                    !digitMatched || !allowed.contains(digit) {
                    continue
                }
                total += digit * place.value
                matchedAnything = true
                rest = rest.dropFirst(marker.count)
                break
            }
        }
        if !rest.isEmpty {
            for (dr, dv) in arabicUnitDigitReadings where rest == dr {
                total += dv
                matchedAnything = true
                rest = ""
                break
            }
        }
        guard matchedAnything, rest.isEmpty, total > 0 else {
            return nil
        }
        return total
    }

    // 算用数字+助数詞(2本/3週間/500円玉)と、序数(第1回/第2世代)をロジックで生成する。
    // 追加語彙に個別登録せずに任意の数×助数詞を出せる。算用は漢数字より前に置きたいので
    // 呼び出し側で漢数字複合より先に挿入する。
    func arabicNumericCompoundCandidates(for reading: String) -> [String] {
        guard reading.count >= 2 else {
            return []
        }
        var results: [String] = []
        var seen = Set<String>()
        func emit(_ s: String) {
            if seen.insert(s).inserted {
                results.append(s)
            }
        }
        // 序数接頭「第」(だい)。付き/無し両方を試す。
        let bodies: [(prefix: String, body: String)]
        if reading.hasPrefix("だい"), reading.count >= 4 {
            bodies = [("第", String(reading.dropFirst(2))), ("", reading)]
        } else {
            bodies = [("", reading)]
        }
        for (ordinalPrefix, body) in bodies {
            // 和語数詞+つ(ひとつ→1つ 等)。第 は付かない。
            if ordinalPrefix.isEmpty, let value = Self.arabicWagoTsuReadings[body] {
                emit("\(value)つ")
                continue
            }
            for counterReading in Self.numericCompoundCounterReadings
            where body.count > counterReading.count && body.hasSuffix(counterReading) {
                let counterSurfaces = Self.numericCompoundCounterSurfaces(for: counterReading) ?? []
                let numberReading = String(body.dropLast(counterReading.count))
                guard let value = Self.japaneseNumberReadingValue(numberReading) else {
                    continue
                }
                for surface in counterSurfaces {
                    emit("\(ordinalPrefix)\(value)\(surface)")
                }
            }
        }
        return results
    }

    // 直前確定が数字(半角0-9/全角０-９)のとき、現在の読みが助数詞そのものなら、その助数詞表層を
    // 候補の先頭へ前置する(90確定→びょう→秒 を先頭)。数量詞マップ(全助数詞)を対象にする。
    static func isCounterBoostDigit(_ character: Character) -> Bool {
        let scalars = Array(character.unicodeScalars)
        guard scalars.count == 1, let value = scalars.first?.value else {
            return false
        }
        return (0x30...0x39).contains(value) || (0xFF10...0xFF19).contains(value)
    }

    // 助数詞+付属語かな末尾(かい+しか 等)の合成は、数字文脈が無くても 芥子か/怪死か の
    // ようなレア語合成より前に置きたい。先頭候補(開始か 等の最良解)は保ち、その直後へ
    // 繰り上げる(2417)。末尾は付属語の許可リストに限定して誤発火を防ぐ。
    static let counterPromotableKanaTails: Set<String> = [
        "しか", "だけ", "ずつ", "ごと", "ごとに", "ぐらい", "くらい", "ほど", "など",
        "まで", "でも", "かも", "こそ", "さえ", "すら", "ばかり",
    ]

    static func counterKanaTailPromotedCandidates(
        _ candidates: [String],
        reading: String
    ) -> [String] {
        guard candidates.count > 2 else { return candidates }
        for (counterReading, surfaces) in numericCounterSuffixCandidatesByReading
            .sorted(by: { $0.key.count > $1.key.count })
        where reading.count > counterReading.count && reading.hasPrefix(counterReading) {
            let tail = String(reading.dropFirst(counterReading.count))
            guard counterPromotableKanaTails.contains(tail) else { continue }
            let present = Set(candidates)
            let promoted = surfaces.map { $0 + tail }.filter { present.contains($0) }
            guard !promoted.isEmpty else { continue }
            let promotedSet = Set(promoted)
            if let firstIndex = candidates.firstIndex(where: { promotedSet.contains($0) }),
                firstIndex <= promoted.count {
                return candidates
            }
            let rest = candidates.filter { !promotedSet.contains($0) }
            return [rest[0]] + promoted + Array(rest.dropFirst())
        }
        return candidates
    }

    // 数字直後ブースト専用の追加助数詞表層。numericCounterSuffixCandidatesByReading に
    // 足すと複合生成(第N/何N)にも波及して 第1階 等の誤生成が出るため分離する(2426)。
    static let digitContextAdditionalCounterSurfacesByReading: [String: [String]] = [
        "かい": ["階"],
        // 歳/才(年齢)と 菜(品数: 一汁三菜)。本表(numericCounter…)に足すと 第2歳 等の
        // 序数誤生成に波及するため数字直後ブースト専用にする(2さい→2歳。2535)
        "さい": ["歳", "才", "菜"],
        // 番(順番)と 晩(夜数)。1ばん→{版, バン, 蛮, 房} と助数詞が出なかった
        // (ユーザ指定 2562)
        "ばん": ["番", "晩"],
        // 助数詞監査(testDiagnosticNumericCounterAudit)で検出した供給漏れ10種(2563)
        "そく": ["足"],
        "はく": ["泊"],
        "こう": ["校"],
        "てき": ["滴"],
        "そう": ["艘", "槽"],
        "き": ["機", "基"],
        "きゅう": ["球", "級"],
        "い": ["位"],
        "だんめ": ["段目"],
        "こめ": ["個目"],
        // ここから: SudachiDict の品詞「助数詞可能」から機械的に洗い出した助数詞
        // (tools/audit_numeric_counters.py)。本表ではなくこちらへ入れる — 本表はかなの
        // 数詞読みからも算用数字の複合を作るため、短い助数詞を入れると さんま→3間 /
        // さんか→3課 / さんぽ→3歩 のような無用な候補が付く(実測で確認)。数字確定直後の
        // 昇格に限れば普通の語を汚さない。「何」複合は なん 許可リスト側で別途有効化する。
        // 表層の並びは LM unigram の頻度順。除外: じゅうの=重(〜重の の連体形が助数詞扱いで
        // 収穫されたノイズ)/ えこ=会古(正体不明)/ 手ぇ・手ェ(方言表記)。2597
        "あた": ["咫"],
        "いんかん": ["員環"],
        "か": ["課"],
        "かいき": ["回忌"],
        "かいり": ["海里", "浬"],
        "かうら": ["カ浦", "箇浦"],
        "かかん": ["日間"],
        "かく": ["画"],
        "かごう": ["か郷", "箇郷"],
        "かさね": ["重", "重ね", "襲", "襲ね"],
        "かじ": ["ヶ寺", "箇寺", "ヵ寺"],
        "かじょう": ["箇条", "か条", "ヶ条", "カ条", "ヵ条", "ケ条", "ヶ條", "個条"],
        "かそう": ["ヵ荘", "箇荘"],
        "かそん": ["ヶ村", "か村", "ヵ村", "カ村", "箇村"],
        "かた": ["方"],
        "かちょう": ["ヵ町", "箇町"],
        "かにち": ["か日", "箇日"],
        "かねん": ["カ年", "ヵ年", "か年", "ヶ年", "箇年", "ケ年", "個年"],
        "かぶ": ["株"],
        "かよ": ["箇夜"],
        "かり": ["ヶ里", "箇里"],
        "かん": ["巻", "缶", "貫", "卷", "罐", "鑵"],
        "かんめ": ["貫目"],
        "がい": ["階"],
        "がうら": ["ガ浦", "箇浦"],
        "がさね": ["重", "重ね", "襲", "襲ね"],
        "がた": ["方"],
        "がっ": ["月"],
        "がつ": ["月"],
        "がん": ["貫"],
        "きゃく": ["脚"],
        "きょく": ["局"],
        "きれ": ["切れ", "切", "帛"],
        "きろぐらむ": ["瓩"],
        "きん": ["斤", "听"],
        "ぎょう": ["行"],
        "ぎれ": ["切れ", "切", "帛"],
        "くみ": ["組", "組み"],
        "ぐ": ["具"],
        "ぐみ": ["組", "組み"],
        "けた": ["桁"],
        "げた": ["桁"],
        "げっ": ["月"],
        "げつ": ["月"],
        "げん": ["元", "間", "件"],
        // 尺貫法の体積単位 合。本表の ごう=[号] とマージされ、数字文脈で {2号, 2合} になる
        // (本表に足すと さんごう→3合 のかな複合まで生成して 山号/三郷 と衝突するため
        //  digit 限定に置く。何合 は なん 分岐が digit 表も引くので出る。ユーザー指摘 2612)
        "ごう": ["合"],
        "こうじ": ["講時"],
        "こうにち": ["光日"],
        "こうねん": ["光年"],
        "こく": ["石", "斛"],
        "こま": ["齣"],
        "ごく": ["石", "斛"],
        "さお": ["棹", "竿"],
        "さら": ["皿"],
        "ざお": ["棹", "竿"],
        "ざら": ["皿"],
        "しな": ["品"],
        "しめ": ["締め", "締"],
        "しゃ": ["社"],
        // 尺貫法の体積単位 勺(1合の1/10)。2確定→しゃく で 2勺 を出す(ユーザー指摘 2612)。
        // 連濁形 じゃく(三尺=さんじゃく)は 尺 のみ ─ 勺 は連濁しない
        "しゃく": ["尺", "勺"],
        "しゅ": ["種", "首", "朱"],
        "しゅう": ["周", "週"],
        "しゅうき": ["周忌"],
        "しゅうねん": ["周年"],
        "しょう": ["勝", "升"],
        "しょく": ["食"],
        "しりんぐ": ["志"],
        "じつ": ["日"],
        "じつかん": ["日間"],
        "じめ": ["締め", "締"],
        "じゃく": ["尺"],
        "じゅう": ["重"],
        "じょう": ["条", "乗", "畳", "帖", "丈", "疊"],
        "じん": ["仞", "仭"],
        "すじ": ["筋"],
        "すん": ["寸"],
        "ずん": ["寸"],
        "せ": ["畝"],
        "せつ": ["節"],
        "せん": ["銭"],
        "そうばい": ["層倍"],
        "ぞく": ["足"],
        "たい": ["体"],
        "たく": ["卓", "択"],
        "たて": ["立", "立て"],
        "たば": ["束"],
        "たび": ["度"],
        "たま": ["球", "玉", "珠"],
        "たん": ["段", "反", "端"],
        "だ": ["駄"],
        "だて": ["立", "立て"],
        "だま": ["球", "玉", "珠"],
        "だん": ["段"],
        "ちゃく": ["着"],
        "ちょう": ["町", "丁", "挺", "梃"],
        "ちょうぶ": ["町歩"],
        "ちょうめ": ["丁目"],
        "つい": ["対"],
        "つか": ["束"],
        "つがい": ["番", "番い"],
        "つき": ["月"],
        "つぼ": ["坪"],
        "づき": ["月"],
        "て": ["手"],
        "てい": ["艇"],
        "てん": ["点", "點"],
        "で": ["手"],
        "と": ["斗"],
        "とう": ["等", "棟"],
        "とおり": ["通り", "通"],
        "とん": ["瓲", "噸"],
        "ど": ["度"],
        "どおり": ["通り", "通"],
        "なのびょう": ["ナノ秒"],
        "にちかん": ["日間"],
        "ねんかん": ["年間"],
        "ねんじ": ["年次"],
        "はり": ["張", "針", "張り", "鉤", "鈎"],
        "はん": ["版"],
        "ばしん": ["馬身"],
        "ばり": ["張", "針", "張り", "鉤", "鈎"],
        "ばりき": ["馬力"],
        "ぱく": ["泊"],
        "ぱり": ["張", "張り"],
        "ぱん": ["版"],
        "ひょう": ["票", "俵"],
        "ひろ": ["尋"],
        "びょうかん": ["秒間"],
        "ぴょう": ["票", "俵"],
        "ふくろ": ["袋"],
        "ふり": ["振り"],
        "ふんかん": ["分間"],
        "ぶ": ["部", "分", "歩"],
        "ぶくろ": ["袋"],
        "ぶり": ["振り"],
        "ぶん": ["分"],
        "ぷり": ["振り"],
        "ぷんかん": ["分間"],
        "へいべい": ["平米"],
        "ぺーじ": ["頁"],
        "ほ": ["歩"],
        "ぽ": ["歩"],
        "ま": ["間"],
        "まき": ["巻", "卷"],
        "まわり": ["回り", "廻り"],
        "むね": ["棟"],
        "めい": ["名"],
        "めん": ["面"],
        "めーとる": ["米"],
        "もう": ["毛"],
        "もく": ["目"],
        "もんめ": ["匁"],
        "よう": ["葉"],
        "より": ["寄り"],
        "り": ["里"],
        "りょう": ["両", "輌", "輛"],
        "りん": ["厘"],
        "れん": ["連"],
        "ろり": ["露里"],
        "わけ": ["分", "分け"],
        "わり": ["割", "割り"]
    ]

    // 助数詞として使うが numericCounterSuffixCandidatesByReading には入れられない表層。
    // あの表は ordinalMeStemTailCharacters(『〜め/〜目』の序数判定ゲート)にも流れるため、
    // 片 を入れると 片目/跡目 等の一般名詞を序数と誤判定してしまう(定義コメント参照)。
    // 使いどころは2つ: (a) 数字確定後に助数詞だけを打つ形の供給(6+ぺん→片。連濁収穫
    // フィルタで落ちる分の復活。2469)、(b) 数詞複合の照合(ろっぺん→6片/六片。2474)。
    static let supplementalCounterSurfacesByReading: [String: [String]] = [
        "ぺん": ["片"],
        "へん": ["片"],
        // 同じ構造で落ちていた助数詞の促音便・連濁読み(6ぽん/3ぼん/6ぴき/3びき/6ぷん/
        // 6ぱつ/6ぱい)。数詞込みの読み(ろっぽん/いっぴき)は数詞合成の別経路で出るが、
        // 数字を確定してから助数詞だけ打つ形では供給が無かった(2471)
        "ぽん": ["本"],
        "ぼん": ["本"],
        "ぴき": ["匹"],
        "びき": ["匹"],
        "ぷん": ["分"],
        "ぱつ": ["発"],
        "ぱい": ["杯"]
    ]

    // 数詞複合の照合に使う助数詞表層(本表 + 上の補助表)。
    static func numericCompoundCounterSurfaces(for reading: String) -> [String]? {
        let base = numericCounterSuffixCandidatesByReading[reading]
        let supplemental = supplementalCounterSurfacesByReading[reading]
        switch (base, supplemental) {
        case (nil, nil):
            return nil
        case let (base?, nil):
            return base
        case let (nil, supplemental?):
            return supplemental
        case let (base?, supplemental?):
            return base + supplemental.filter { !base.contains($0) }
        }
    }

    static var numericCompoundCounterReadings: Set<String> {
        Set(numericCounterSuffixCandidatesByReading.keys)
            .union(supplementalCounterSurfacesByReading.keys)
    }

    static func digitBoostCounterSurfaces(for reading: String) -> [String]? {
        let base = numericCounterSuffixCandidatesByReading[reading]
        let extra = digitContextAdditionalCounterSurfacesByReading[reading]
        switch (base, extra) {
        case (nil, nil):
            return nil
        case let (base?, nil):
            return base
        case let (nil, extra?):
            return extra
        case let (base?, extra?):
            return base + extra
        }
    }

    // tailConversion: 助数詞+かな末尾の合成供給時に、末尾を変換して漢字形も併せて
    // 供給するためのフック(2確定→じしけん→次試験。static のため呼び出し側が
    // converter.candidates を閉じ込めて渡す。2645)
    static func digitContextCounterBoostedCandidates(
        _ candidates: [String],
        reading: String,
        precedingCharacter: Character?,
        suppressedCandidates: Set<String> = [],
        tailConversion: ((String) -> String?)? = nil
    ) -> [String] {
        guard let precedingCharacter,
            isCounterBoostDigit(precedingCharacter) else {
            return candidates
        }
        let present = Set(candidates)
        // 数字文脈限定の助数詞供給(定数コメント参照)。抑制済み表層は復活させない。
        var boosted: [String] = (Self.supplementalCounterSurfacesByReading[reading] ?? [])
            .filter { !present.contains($0) && !suppressedCandidates.contains($0) }
        if let counterSurfaces = Self.digitBoostCounterSurfaces(for: reading) {
            // 助数詞マップの順(か国,箇国,…)で前置する(候補列の順ではなく人手の優先順を採用)。
            // 候補列に無い助数詞も数字文脈なら供給する(抑制済みは復活させない)。
            boosted += counterSurfaces.filter {
                !boosted.contains($0) && (present.contains($0) || !suppressedCandidates.contains($0))
            }
        } else {
            // 読みが「助数詞読み+かな末尾」(かい+しか/まい+ちゅう 等)なら、助数詞表層で
            // 始まる合成候補(回しか/枚中。末尾はかな素通りでも変換済みでも可)を前置する
            // (1確定→かいしか→1回しか、17確定→まいちゅう→17枚中。2416/2421)。複数の
            // 助数詞読みが前方一致する場合は最長を優先し、末尾は短いかなに限定する。
            // 読み全体が seed 宣言のある語(号店/回転 等)なら、助数詞+かな末尾の合成は前置
            // しない(2681)。2確定→ごうてん で 号+てん の合成(号点/号てん/合点/合てん)が
            // 本来の 号店 を押しのけていた。合成は語が無いときの受け皿なので、人手宣言のある
            // 読みでは出番がない
            let readingHasSeedWord = KanaKanjiSeedDictionary.seed[reading] != nil
            for counterReading in Set(numericCounterSuffixCandidatesByReading.keys)
                .union(digitContextAdditionalCounterSurfacesByReading.keys)
                .sorted(by: { $0.count != $1.count ? $0.count > $1.count : $0 < $1 })
            where !readingHasSeedWord
                && reading.count > counterReading.count && reading.hasPrefix(counterReading) {
                let surfaces = Self.digitBoostCounterSurfaces(for: counterReading) ?? []
                let tail = String(reading.dropFirst(counterReading.count))
                // 末尾は6かなまで(ぐらいかな=5かな が4制限で漏れ、5確定→ふんぐらいかな で
                // 分ぐらいかな が出なかった。ユーザ報告 2643)
                guard tail.count <= 6,
                    tail.allSatisfy({ ("ぁ"..."ゖ").contains($0) || $0 == "ー" }) else {
                    continue
                }
                var matched: [String] = []
                for surface in surfaces {
                    // 末尾の変換形(しけん→試験)も供給する(2次試験。かな形より先)。
                    // 付属語末尾(しか/だけ 等)は変換しない(回鹿 の誤供給防止)。
                    // 変換形は全漢字のみ(分行き 等の交ぜ形は供給しない)
                    if !counterPromotableKanaTails.contains(tail),
                        let convertedTail = tailConversion?(tail),
                        convertedTail != tail,
                        KanaKanjiConverter.isAllKanjiSurface(convertedTail) {
                        let convertedForm = surface + convertedTail
                        if !suppressedCandidates.contains(convertedForm),
                            !matched.contains(convertedForm) {
                            matched.append(convertedForm)
                        }
                    }
                    let existing = candidates.filter {
                        $0.count > surface.count && $0.hasPrefix(surface) && !matched.contains($0)
                    }
                    if existing.isEmpty {
                        // 助数詞が辞書 rank 圏外だと合成候補自体が立たない(回ぐらい 等)。
                        // 数字文脈なら 助数詞+かな末尾 を合成供給する(抑制済みは復活させない)
                        let synthesized = surface + tail
                        if !candidates.contains(synthesized),
                            !suppressedCandidates.contains(synthesized),
                            !matched.contains(synthesized) {
                            matched.append(synthesized)
                        }
                    } else {
                        matched.append(contentsOf: existing)
                    }
                }
                if !matched.isEmpty {
                    boosted += matched
                    break
                }
            }
        }
        guard !boosted.isEmpty else {
            return candidates
        }
        let boostSet = Set(boosted)
        var rest = candidates.filter { !boostSet.contains($0) }
        // 数字直後で助数詞が立つ文脈では、読みそのもの(かなエコー)を助数詞より前に
        // 出したい状況が無い(2さい で さい が先頭に居座る対策)。末尾へ送る。
        if let echoIndex = rest.firstIndex(of: reading) {
            rest.remove(at: echoIndex)
            rest.append(reading)
        }
        return boosted + rest
    }

    // 順序の『目』が付く語幹の末尾文字(助数詞表層の末字+番/代/丁/つ/行 等)。
    // め/目 選好の序数判定に使う — 跡目/片目 等の一般名詞を巻き込まないためのゲート。
    static let ordinalMeStemTailCharacters: Set<Character> = {
        var characters = Set<Character>()
        for surfaces in numericCounterSuffixCandidatesByReading.values {
            for surface in surfaces {
                if let last = surface.last {
                    characters.insert(last)
                }
            }
        }
        for surfaces in digitContextAdditionalCounterSurfacesByReading.values {
            for surface in surfaces {
                if let last = surface.last {
                    characters.insert(last)
                }
            }
        }
        for extra in "番代丁つ行駅" {
            characters.insert(extra)
        }
        return characters
    }()

    // め終わり読みの『め/目』選好(コンテナー設定 première…/un peu …)。
    // - 形容詞語幹+め(多め/少なめ): 語幹+い が同読みのい形容詞に実在する組が対象。
    //   OFF: 漢字『目』形(多目/薄目 等の Sudachi 収穫)を候補から除く。
    //   ON: かな『め』形を先に(無ければ 目形の位置へ補生成)、め形しか無い先頭組(狭め)には
    //   目形を直後に補生成する(1973年内閣告示第2号 付表の語1 は『め』)。
    // - 序数(N回目/二日目 等): 語幹末尾が助数詞的な組が対象。スイッチで め/目 の先後を決め、
    //   欠けている側は補生成する(番目⇄番め。同 通則4 は『目』)。
    // 供給源(辞書/フォールバック/活用)を問わず最終列で整えるので、辞書側の並び
    // (薄目 rank0<薄め rank1 等)にも一様に効く。
    func applyMeSuffixPreferences(reading: String, to candidates: [String]) -> [String] {
        guard reading.count >= 2, reading.hasSuffix("め"), !candidates.isEmpty else {
            return candidates
        }
        let stemReading = String(reading.dropLast())
        let adjectiveSurfaces = Set(systemCandidates(for: stemReading + "い", mode: .lesDeux))
        var result = candidates
        // 語幹読みが助数詞そのもの(さつめ=さつ+め 等)なら、助数詞+目/め を先頭へ補生成
        // する。辞書に地名等の直接ヒット(佐津目)しか無く、序数フォールバックが走らない
        // 読みでも 冊目/冊め を供給する(3さつめ 対策。数字直後はさらに digit boost が前置)
        // 誤爆ガード: 1字の助数詞読み(こ=米/じ=字 等の実語と衝突)は対象外。既に序数らしい
        // 候補(語幹末尾が助数詞文字の 〜目/〜め: 代目/本目/回目 等)が居るなら供給済みとみなす
        if stemReading.count >= 2,
            let counterSurfaces = Self.numericCounterSuffixCandidatesByReading[stemReading],
            let counter = counterSurfaces.first,
            !result.contains(where: { candidate in
                guard candidate.count >= 2,
                    let last = candidate.last, last == "目" || last == "め",
                    let stemTail = candidate.dropLast().last else {
                    return false
                }
                return Self.ordinalMeStemTailCharacters.contains(stemTail)
            }) {
            let pair = ordinalMeKanjiPreferred
                ? [counter + "目", counter + "め"]
                : [counter + "め", counter + "目"]
            for (offset, form) in pair.enumerated() where !result.contains(form) {
                result.insert(form, at: min(offset, result.count))
            }
        }
        var stems: [String] = []
        var seenStems = Set<String>()
        for candidate in result where candidate.count >= 2 && candidate != reading {
            guard let last = candidate.last, last == "め" || last == "目" else {
                continue
            }
            let stem = String(candidate.dropLast())
            // かなだけの語幹(かな識別 等)は対象外
            guard stem.contains(where: { !("ぁ"..."ゖ").contains($0) && $0 != "ー" }) else {
                continue
            }
            if seenStems.insert(stem).inserted {
                stems.append(stem)
            }
        }
        var appendedAdjectiveKanji = false
        for stem in stems {
            let meForm = stem + "め"
            let kanjiForm = stem + "目"
            if adjectiveSurfaces.contains(stem + "い") {
                if !adjectiveMeKanjiCandidatesEnabled {
                    result.removeAll { $0 == kanjiForm }
                    continue
                }
                let meIndex = result.firstIndex(of: meForm)
                let kanjiIndex = result.firstIndex(of: kanjiForm)
                switch (meIndex, kanjiIndex) {
                case let (me?, kanji?) where kanji < me:
                    result.remove(at: me)
                    result.insert(meForm, at: kanji)
                case let (nil, kanji?):
                    result.insert(meForm, at: kanji)
                case let (me?, nil) where !appendedAdjectiveKanji:
                    result.insert(kanjiForm, at: min(me + 1, result.count))
                    appendedAdjectiveKanji = true
                default:
                    break
                }
                continue
            }
            guard let tail = stem.last,
                Self.ordinalMeStemTailCharacters.contains(tail)
                    || stem.contains(where: \.isNumber) else {
                continue
            }
            // 両形とも常に出す(スイッチは順序のみ)。辞書に片方しか無い語
            // (番目/丁目/本目/代目/分目 等)でも欠け側を補生成する。
            let meIndex = result.firstIndex(of: meForm)
            let kanjiIndex = result.firstIndex(of: kanjiForm)
            if ordinalMeKanjiPreferred {
                switch (meIndex, kanjiIndex) {
                case let (me?, kanji?) where me < kanji:
                    result.remove(at: kanji)
                    result.insert(kanjiForm, at: me)
                case let (me?, nil):
                    result.insert(kanjiForm, at: me)
                case let (nil, kanji?):
                    result.insert(meForm, at: min(kanji + 1, result.count))
                default:
                    break
                }
            } else {
                switch (meIndex, kanjiIndex) {
                case let (me?, kanji?) where kanji < me:
                    result.remove(at: me)
                    result.insert(meForm, at: kanji)
                case let (nil, kanji?):
                    result.insert(meForm, at: kanji)
                case let (me?, nil):
                    result.insert(kanjiForm, at: min(me + 1, result.count))
                default:
                    break
                }
            }
        }
        // 補生成した 〜目/〜め が抑制済み表層を復活させないように、読み単位の抑制を
        // 出口で適用する(締目@しめ が suppr を素通りしていた。2643)
        if let suppressed = store.suppressedCandidatesByReading()[reading], !suppressed.isEmpty {
            result.removeAll { suppressed.contains($0) }
        }
        return result
    }

    func ordinalMeFallbackCandidates(
        for reading: String,
        hasDirectCandidates: Bool,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode,
        limit: Int
    ) -> [String] {
        guard !hasDirectCandidates,
            reading.count >= 2,
            reading.hasSuffix("め"),
            limit > 0 else {
            return []
        }

        let stem = String(reading.dropLast(1))

        guard !stem.isEmpty else {
            return []
        }

        // 語幹側の抑制を合成前に効かせる(postfix 合成と同じ規則。にち→日圧 を抑制しても
        // 日圧目 は読み末尾(め)と表層末尾(目)が異なり合成後フィルタで拾えないため必須)
        let suppressedStemSurfaces = store.suppressedCandidatesByReading()

        var stemCandidates = uniqueCandidates(
            from: candidatesForReading(
                stem,
                userDictionary: userDictionary,
                initialUserDictionary: initialUserDictionary,
                systemCandidateMode: systemCandidateMode
            ) + inflectionCandidates(
                for: stem,
                userDictionary: userDictionary,
                initialUserDictionary: initialUserDictionary,
                systemCandidateMode: systemCandidateMode,
                limit: limit
            )
        ).filter { !(suppressedStemSurfaces[stem]?.contains($0) ?? false) }

        if stemCandidates.isEmpty {
            let trimmedStem = trimmingLeadingNumberPrefix(from: stem)

            if !trimmedStem.isEmpty,
                trimmedStem != stem {
                stemCandidates = uniqueCandidates(
                    from: candidatesForReading(
                        trimmedStem,
                        userDictionary: userDictionary,
                        initialUserDictionary: initialUserDictionary,
                        systemCandidateMode: systemCandidateMode
                    ) + inflectionCandidates(
                        for: trimmedStem,
                        userDictionary: userDictionary,
                        initialUserDictionary: initialUserDictionary,
                        systemCandidateMode: systemCandidateMode,
                        limit: limit
                    )
                ).filter { !(suppressedStemSurfaces[trimmedStem]?.contains($0) ?? false) }
            }
        }

        guard !stemCandidates.isEmpty else {
            return []
        }

        let kanjiStemCandidates = stemCandidates.filter(containsKanji)
        let nonKanjiStemCandidates = stemCandidates.filter { !containsKanji($0) }

        guard !kanjiStemCandidates.isEmpty else {
            return []
        }

        var derived: [String] = []

        for candidate in kanjiStemCandidates {
            derived.append(candidate + "め")
        }

        for candidate in nonKanjiStemCandidates {
            derived.append(candidate + "め")
        }

        // Keep kanji+"目" candidates available, but behind kanji+"め".
        for candidate in kanjiStemCandidates {
            derived.append(candidate + "目")
        }

        return Array(uniqueCandidates(from: derived).prefix(limit))
    }

    func numericUnitFallbackCandidates(
        for reading: String,
        limit: Int
    ) -> [String] {
        guard limit > 0 else {
            return []
        }

        var lookupKeys = [reading]
        let trimmedReading = trimmingLeadingNumberPrefix(from: reading)

        if !trimmedReading.isEmpty,
            trimmedReading != reading {
            lookupKeys.append(trimmedReading)
        }

        var derived: [String] = []

        for key in lookupKeys {
            if let fallbackCandidates = Self.numericUnitFallbackCandidatesByReading[key] {
                derived.append(contentsOf: fallbackCandidates)
            }
        }

        return Array(uniqueCandidates(from: derived).prefix(limit))
    }

    func numericCounterCompoundCandidates(
        for reading: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode,
        limit: Int
    ) -> [String] {
        guard limit > 0 else {
            return []
        }

        var derived: [String] = []

        for (prefixReading, allowedPrefixes) in Self.numericCounterPrefixCandidatesByReading {
            guard reading.hasPrefix(prefixReading) else {
                continue
            }

            let suffixReading = String(reading.dropFirst(prefixReading.count))

            guard !suffixReading.isEmpty else {
                continue
            }

            if let allowedSuffixReadings = Self.numericCounterAllowedSuffixReadingsByPrefixReading[prefixReading],
                !allowedSuffixReadings.contains(suffixReading) {
                continue
            }

            // 「何」だけは数字文脈限定の助数詞からも表層を引く。本表はかなの数詞読みからも
            // 算用数字の複合を作るため(実測: さんこ→3個、にほん→2本)、短い助数詞を本表へ
            // 入れると さんま→3間 / さんか→3課 のような無用な候補が付く。一方「何」は
            // なん+助数詞 の形しか作らず、許可リストでゲートもされるので普通の語を汚さない。
            let allowedSuffixes: [String]
            // すう も同様(じつ→日 を本表から数字文脈限定表へ移した後の 数日 供給。2647)
            if prefixReading == "なん" || prefixReading == "すう",
                let digitOnly = Self.digitContextAdditionalCounterSurfacesByReading[suffixReading] {
                let compound = Self.numericCompoundCounterSurfaces(for: suffixReading) ?? []
                allowedSuffixes = compound + digitOnly.filter { !compound.contains($0) }
            } else if let compound = Self.numericCompoundCounterSurfaces(for: suffixReading) {
                allowedSuffixes = compound
            } else {
                continue
            }

            let prefixCandidates = uniqueCandidates(
                from: candidatesForReading(
                    prefixReading,
                    userDictionary: userDictionary,
                    initialUserDictionary: initialUserDictionary,
                    systemCandidateMode: systemCandidateMode
                )
            ).filter { allowedPrefixes.contains($0) }

            let resolvedPrefixCandidates = prefixCandidates.isEmpty
                ? allowedPrefixes
                : prefixCandidates

            // 助数詞表層は辞書順のままだと 箇月(rank0)が か月(rank7)に先行する。
            // seed の並び矯正(かげつ=[か月,…] 等)を反映するため seed 順整列を通す。
            let suffixCandidates = orderedDerivationBaseCandidates(
                uniqueCandidates(
                    from: candidatesForReading(
                        suffixReading,
                        userDictionary: userDictionary,
                        initialUserDictionary: initialUserDictionary,
                        systemCandidateMode: systemCandidateMode
                    )
                ).filter { allowedSuffixes.contains($0) },
                reading: suffixReading
            )

            let resolvedSuffixCandidates = suffixCandidates.isEmpty
                ? allowedSuffixes
                : suffixCandidates

            for prefixCandidate in resolvedPrefixCandidates {
                for suffixCandidate in resolvedSuffixCandidates {
                    derived.append(prefixCandidate + suffixCandidate)
                }
            }
        }

        // 桁(千/百/万…)を挟む汎用パス: 接頭 + 桁+ + (助数詞 | 分の一 | ∅)。
        // 例: すうせんねん→数千年, なんびゃくねん→何百年, すうせんぶんのいち→数千分の一。
        // 接頭直結の助数詞(数年・三本等)は上の既存パスが拗音・連濁制約付きで担当し、
        // ここは必ず桁を1つ以上含む組(または接頭+分の一)のみを生成する。
        for (prefixReading, allowedPrefixes) in Self.numericCounterPrefixCandidatesByReading {
            guard reading.hasPrefix(prefixReading) else {
                continue
            }

            let afterPrefix = String(reading.dropFirst(prefixReading.count))

            guard !afterPrefix.isEmpty else {
                continue
            }

            let prefixCandidates = uniqueCandidates(
                from: candidatesForReading(
                    prefixReading,
                    userDictionary: userDictionary,
                    initialUserDictionary: initialUserDictionary,
                    systemCandidateMode: systemCandidateMode
                )
            ).filter { allowedPrefixes.contains($0) }

            let resolvedPrefixCandidates = prefixCandidates.isEmpty
                ? allowedPrefixes
                : prefixCandidates

            var tailCandidates: [String] = []

            // 桁始まり: 桁+ (助数詞 | 分の一 | ∅)
            for magnitude in Self.numericMagnitudeCandidatesByReading
                where afterPrefix.hasPrefix(magnitude.reading) {
                let afterMagnitude = String(afterPrefix.dropFirst(magnitude.reading.count))

                for tail in numericMagnitudeTailCandidates(for: afterMagnitude) {
                    tailCandidates.append(magnitude.candidate + tail)
                }
            }

            // 桁なしの分数: 接頭 + 分の一 (例: すうぶんのいち→数分の一)
            if let fractions = Self.numericFractionSuffixCandidatesByReading[afterPrefix] {
                tailCandidates.append(contentsOf: fractions)
            }

            for prefixCandidate in resolvedPrefixCandidates {
                for tail in tailCandidates {
                    derived.append(prefixCandidate + tail)
                }
            }
        }

        return Array(uniqueCandidates(from: derived).prefix(limit))
    }

    // 桁の連なりと末尾(助数詞 | 分の一 | ∅)を読みから分解し、漢字列候補を返す。
    // ∅(空文字)は桁を1つ以上消費済みの場合のみ許可し、「数千」等の助数詞なしを表す。
    func numericMagnitudeTailCandidates(
        for reading: String,
        magnitudeConsumed: Bool = true
    ) -> [String] {
        if reading.isEmpty {
            return magnitudeConsumed ? [""] : []
        }

        var results: [String] = []

        if let counters = Self.numericCounterSuffixCandidatesByReading[reading] {
            results.append(contentsOf: counters)
        }

        if let fractions = Self.numericFractionSuffixCandidatesByReading[reading] {
            results.append(contentsOf: fractions)
        }

        for magnitude in Self.numericMagnitudeCandidatesByReading
            where reading.hasPrefix(magnitude.reading) {
            let rest = String(reading.dropFirst(magnitude.reading.count))

            for tail in numericMagnitudeTailCandidates(for: rest, magnitudeConsumed: true) {
                results.append(magnitude.candidate + tail)
            }
        }

        return results
    }

    // 単文節#1を連文節より前に出す全読み接辞(2522): 読み末尾がreadingSuffixかつ
    // 単文節#1がsurfaceSuffixで終わるとき、連文節のLM合成(フランス+社 等)より
    // 接辞複合/辞書語(フランス車)を優先する。さん→産 は敬称さん(田中さん)と
    // 衝突するため入れない。
    static let multiClausePromotedWholeReadingAffixes: [(readingSuffix: String, surfaceSuffix: String)] = [
        ("しゃ", "車")
    ]

    func shouldPromoteSingleBestAboveMultiClause(reading: String, singleBest: String) -> Bool {
        guard reading.count >= 4 else {
            return false
        }
        return Self.multiClausePromotedWholeReadingAffixes.contains { affix in
            reading.hasSuffix(affix.readingSuffix) && singleBest.hasSuffix(affix.surfaceSuffix)
        }
    }

    // 名詞に付く生産的な漢字接辞を組み合わせる: 語幹(名詞)+別(種類別)、別+語幹(別会社)。
    // 語幹は漢字を含む候補に限り、1モーラ語幹(区別/差別等の誤分割)は除外する。
    // 辞書語(餞別等)は system 候補が上位に来るため、補完として低めのスコアで併置する。
    func nounKanjiAffixCandidates(
        for reading: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode,
        limit: Int
    ) -> [String] {
        guard reading.count >= 4,
            limit > 0 else {
            return []
        }

        func kanjiStemCandidates(for stemReading: String) -> [String] {
            uniqueCandidates(
                from: candidatesForReading(
                    stemReading,
                    userDictionary: userDictionary,
                    initialUserDictionary: initialUserDictionary,
                    systemCandidateMode: systemCandidateMode
                )
            ).filter { containsKanjiOrKatakana($0) }
        }

        var derived: [String] = []

        for affix in Self.nounKanjiSuffixAffixCandidatesByReading
            where reading.hasSuffix(affix.reading) {
            let stem = String(reading.dropLast(affix.reading.count))

            guard stem.count >= 2 else {
                continue
            }

            for candidate in kanjiStemCandidates(for: stem).prefix(6) {
                derived.append(candidate + affix.candidate)
            }
        }

        for affix in Self.nounKanjiPrefixAffixCandidatesByReading
            where reading.hasPrefix(affix.reading) {
            let stem = String(reading.dropFirst(affix.reading.count))

            guard stem.count >= 2 else {
                continue
            }

            for candidate in kanjiStemCandidates(for: stem).prefix(6) {
                derived.append(affix.candidate + candidate)
            }
        }

        return Array(uniqueCandidates(from: derived).prefix(limit))
    }

    func trimmingLeadingNumberPrefix(from text: String) -> String {
        String(text.drop(while: { $0.isNumber }))
    }
}
