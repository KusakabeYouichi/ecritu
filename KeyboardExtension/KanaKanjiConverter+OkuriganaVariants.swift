import Foundation

// 送り仮名の許容形(終る/取扱う/届 …)の表示制御(2820)。
// 候補列の文字列に対する後段パスで、「漢字列が同じで、かなが片方の部分列」の組(終わる⇄終る)を見つけ、省かれた
// かなの位置から『送り仮名の付け方』(1973 年内閣告示)のどの許容か(語幹の中/複合語の前部要素/名詞化)を判定し、
// グループごとの設定(本則だけ/本則を先に/許容を先に)に従って並べ替え・除去する。
// 区切りを変えないので単文節・連文節・表示層のどの経路の文字列にも一様に効く。DP のコストは触らない。
// 学習済み・追加語彙(手動)の表層はユーザの選択なので対象外(位置を保つ)。行なう だけ使いたいなら 追加語彙 に登録する。
extension KanaKanjiConverter {
    // 通則1 の許容: 活用語尾の前の音節から送れる 6 語(表わす/著わす/現われる/行なう/断わる/賜わる)。
    // この 6 語だけは「長い方」が許容形(本則は 表す/行う …)。漢字+送り始めのかな で照合する
    static let okuriganaTsusoku1LongVariantPairs: Set<String> = ["表わ", "著わ", "現わ", "行な", "断わ", "賜わ"]
    // 通則2 の許容: 送り仮名を省ける 12 語(浮かぶ/生まれる/押さえる/捕らえる/晴れやか/積もる/聞こえる/起こる/落とす/
    // 暮らす/当たる/終わる/変わる)。漢字+省かれるかな で照合し、活用形や派生名詞(当たり/変わり/終わって)にも効く。
    // 語幹の中の送り仮名のゆれはこの 2 つのリストにある語だけを対象にする。辞書には 困まる/謝まる/為め のような
    // 本則より長い誤表記・旧表記もあり、「長い方が本則」を一般則にすると誤表記を守ってしまうため
    static let okuriganaTsusoku2ShortVariantPairs: Set<String> = [
        "浮か", "生ま", "押さ", "捕ら", "積も", "聞こ", "起こ", "落と", "暮ら", "当た", "終わ", "変わ",
        // 通則4 の許容のうち、語の中のかなを省く 代わり(代り)/向かい(向い) も同じ形なのでここに含める
        "代わ", "向か"
    ]
    // 通則4 の許容: 活用のある語から転じた名詞で末尾の送り仮名を省ける語(届け/願い/狩り/答え/問い/祭り/群れ。
    // 曇り/晴れ も告示にあるが天気の 曇/晴 が固定表記なので慣用語として触らない)。長い方(送った方)が本則。
    // 「末尾のかなが省かれた組」を機械的に拾うと 甘い/甘(部首名の供給)、勇む/勇・茂る/茂・渡り/渡(人名)、
    // 香り/香(別の名詞)を巻き込むので、名詞化はこのリストの語に限る
    static let okuriganaTsusoku4NominalizedPairs: Set<String> = ["届け", "願い", "狩り", "答え", "問い", "祭り", "群れ"]

    // 慣用で送り仮名を付けない語(通則7)と、活用のある語から転じた名詞で送らない語(通則4 の例外)。
    // 短い形がそのまま本則なので、対になる長い形(受け付け/話し)は別の語(動詞の連用形など)とみなし、この組は触らない。
    // 2 字以上の語は送り仮名を持たない候補に含まれていれば適用(申込書/代金引換/受付係。取扱う/取扱い のように送り仮名が
    // 残る形は動詞の許容形なので対象)。1 字の語は省かれたかなの直前の漢字がその字のとき(話し/次ぎ/何割り/春慶塗りの)に適用。
    // 末尾の「慣用の拡張」は告示にないが一般に固定した表記(入口/締切/振込、天気の 晴/曇)で、初期設定(許容を出さない)
    // で消えると困る語。ここは運用で増減してよい
    static let okuriganaFixedShortForms: Set<String> = [
        // 通則4 例外(送り仮名を付けない名詞)
        "謡", "虞", "趣", "氷", "印", "頂", "帯", "畳", "卸", "煙", "恋", "志", "次", "隣", "富", "恥", "話", "光", "舞",
        "折", "係", "掛", "組", "肥", "並", "巻", "割",
        // 通則7 (1) 特定の領域で慣用が固定した語(工芸品の 織/染/塗/彫/焼 を含む)
        "関取", "頭取", "取締役", "事務取扱", "織", "染", "塗", "彫", "焼",
        "書留", "気付", "切手", "消印", "小包", "振替", "切符", "踏切", "請負",
        "売値", "買値", "仲買", "歩合", "両替", "割引", "組合", "手当", "倉敷料", "作付", "売上", "貸付", "借入", "繰越",
        "小売", "積立", "取扱", "取次", "取引", "乗換", "乗組", "引受", "引換", "振出", "待合", "見積", "申込",
        // 通則7 (2) 一般に慣用が固定した語
        "奥書", "木立", "子守", "献立", "座敷", "試合", "字引", "場合", "羽織", "葉巻", "番組", "番付", "日付", "水引",
        "物置", "物語", "役割", "屋敷", "夕立", "割合", "合図", "合間", "植木", "置物", "織物", "貸家", "敷石", "敷地",
        "敷物", "立場", "建物", "並木", "巻紙", "受付", "受取", "浮世絵", "絵巻物", "仕立屋",
        // 慣用の拡張(告示外)
        "入口", "出口", "締切", "振込", "手続", "晴", "曇"
    ]
    private static let okuriganaFixedShortFormsMultiChar: [String] = okuriganaFixedShortForms.filter { $0.count >= 2 }
    private static let okuriganaFixedShortFormSingleChars: Set<Character> = Set(
        okuriganaFixedShortForms.filter { $0.count == 1 }.compactMap(\.first)
    )

    // 複合語の前部要素として省かれる送り仮名は 取(り)扱う/打(ち)合わせ/引(っ)越し のような活用語尾の断片で、
    // 助詞ではない。山に登る⇄山登る のような組を送り仮名のゆれと誤認しないための除外
    private static let okuriganaNeverOmittedKana: Set<Character> = Set("にをがはのとでへもやかてね")

    private static func isHiragana(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        return (0x3041...0x309F).contains(scalar.value)
    }

    private static func isKanji(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        return (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
            || scalar.value == 0x3005  // 々
    }

    struct OkuriganaVariantRelation {
        let standard: String
        let variant: String
        let group: OkuriganaVariantGroup
    }

    // 2 候補が送り仮名のゆれの組なら(本則, 許容形, グループ)を返す。漢字列(ひらがな以外の文字列)が同じで
    // 短い方が長い方の部分列、省かれた文字がすべてひらがな、各省略字の直前が漢字か省略字であること。
    // 本則の向き: 通則1 の 6 語は短い方、通則2/4 のリスト語と複合語の前部要素は長い方(送った方)が本則
    static func okuriganaVariantRelation(_ a: String, _ b: String) -> OkuriganaVariantRelation? {
        guard a != b else { return nil }
        let (long, short) = a.count >= b.count ? (Array(a), Array(b)) : (Array(b), Array(a))
        guard long.count > short.count, long.contains(where: isKanji) else { return nil }
        // 部分列照合(左から貪欲)。省略位置を集める
        var removed: [Int] = []
        var shortIndex = 0
        for (index, character) in long.enumerated() {
            if shortIndex < short.count, short[shortIndex] == character {
                shortIndex += 1
            } else {
                guard isHiragana(character) else { return nil }
                removed.append(index)
            }
        }
        guard shortIndex == short.count, !removed.isEmpty, removed.count <= 3 else { return nil }
        // 省略字は漢字の直後(または省略字の連続)に限る。助詞は送り仮名として省かれない。
        // 直前の漢字が 1 字の慣用語(話/次/割/塗 …)なら対象外
        var previousRemoved = -2
        for index in removed {
            let precededByKanji = index > 0 && isKanji(long[index - 1])
            guard precededByKanji || previousRemoved == index - 1 else { return nil }
            if precededByKanji {
                if okuriganaNeverOmittedKana.contains(long[index]) || okuriganaFixedShortFormSingleChars.contains(long[index - 1]) {
                    return nil
                }
            }
            previousRemoved = index
        }
        let shortString = String(short)
        let longString = String(long)
        if !short.contains(where: isHiragana), okuriganaFixedShortFormsMultiChar.contains(where: { shortString.contains($0) }) {
            return nil
        }
        // 通則1 の 6 語(表わす 等)は長い方が許容形
        if removed.count == 1, removed[0] > 0,
            okuriganaTsusoku1LongVariantPairs.contains(String(long[(removed[0] - 1)...removed[0]])) {
            return OkuriganaVariantRelation(standard: shortString, variant: longString, group: .stemInternal)
        }
        // 通則2 の 12 語(終わる 等)は短い方が許容形
        if removed.count == 1, removed[0] > 0,
            okuriganaTsusoku2ShortVariantPairs.contains(String(long[(removed[0] - 1)...removed[0]])) {
            return OkuriganaVariantRelation(standard: longString, variant: shortString, group: .stemInternal)
        }
        // 複合語の前部要素: 省略字の直後に漢字が続く(取り|扱う、打ち|合わせ)。長い方が本則
        if removed.contains(where: { index in index + 1 < long.count && isKanji(long[index + 1]) }) {
            return OkuriganaVariantRelation(standard: longString, variant: shortString, group: .compoundFront)
        }
        // 名詞化の省略: 通則4 のリスト語の末尾のかなが省かれる(届け/届、お届け/お届)
        if removed.count == 1, removed[0] == long.count - 1, removed[0] > 0,
            okuriganaTsusoku4NominalizedPairs.contains(String(long[(removed[0] - 1)...removed[0]])) {
            return OkuriganaVariantRelation(standard: longString, variant: shortString, group: .nominalized)
        }
        // それ以外(困った/困まった、甘い/甘、茂る/茂、香り/香 …)はリスト外なので触らない
        return nil
    }

    func applyOkuriganaVariantPreference(reading: String, to candidates: [String]) -> [String] {
        guard candidates.count >= 2 else {
            return candidates
        }
        let preference = okuriganaVariantPreference
        // 漢字列(ひらがなを除いた文字列)で組分け。2 つ以上の候補が集まった組だけ調べる
        var buckets: [String: [Int]] = [:]
        for (index, candidate) in candidates.enumerated() {
            let skeleton = String(candidate.filter { !Self.isHiragana($0) })
            guard !skeleton.isEmpty else { continue }
            buckets[skeleton, default: []].append(index)
        }
        let candidateBuckets = buckets.values.filter { $0.count >= 2 }
        guard !candidateBuckets.isEmpty else {
            return candidates
        }
        let normalizedReading = KanaTextNormalizer.normalizedReading(reading)
        // 学習済みと追加語彙(手動)の表記はユーザの選択なので設定に関わらず守る。追加語彙の動詞は活用形も
        // 派生される(行なう→行なって)ので、読みと表記の語幹(末尾 1 字を落としたもの)が一致する候補も守る
        var protected = Set(store.learnedDictionary()[normalizedReading] ?? [])
        for (ajoutReading, surfaces) in store.ajoutVocabulary() {
            if ajoutReading == normalizedReading {
                protected.formUnion(surfaces)
                continue
            }
            guard ajoutReading.count >= 3, normalizedReading.hasPrefix(ajoutReading.dropLast()) else { continue }
            for surface in surfaces where surface.count >= 2 && surface.contains(where: Self.isKanji) {
                protected.insert("\u{0}" + String(surface.dropLast()))  // 語幹の印(接頭の NUL で区別)
            }
        }
        let protectedStems = protected.filter { $0.hasPrefix("\u{0}") }.map { String($0.dropFirst()) }
        func isProtected(_ candidate: String) -> Bool {
            protected.contains(candidate) || protectedStems.contains(where: { candidate.hasPrefix($0) })
        }

        // 許容形 → (本則, グループ)。本則は連鎖(取り扱い→取扱い→取扱)の根へ辿る
        var relationByVariant: [String: OkuriganaVariantRelation] = [:]
        for bucket in candidateBuckets {
            for i in bucket.indices {
                for j in bucket.indices where j > i {
                    let a = candidates[bucket[i]], b = candidates[bucket[j]]
                    guard !isProtected(a), !isProtected(b),
                        let relation = Self.okuriganaVariantRelation(a, b) else { continue }
                    if let existing = relationByVariant[relation.variant], existing.standard.count >= relation.standard.count {
                        continue
                    }
                    relationByVariant[relation.variant] = relation
                }
            }
        }
        guard !relationByVariant.isEmpty else {
            return candidates
        }
        func root(of surface: String) -> String {
            var current = surface
            var hops = 0
            while let relation = relationByVariant[current], hops < 4 {
                current = relation.standard
                hops += 1
            }
            return current
        }

        var result: [String] = []
        var inserted = Set<String>()
        // 本則の前に置く許容形(許容を先に)
        var variantsBefore: [String: [String]] = [:]
        // 本則の直後に置く許容形(本則を先に)
        var variantsAfter: [String: [String]] = [:]
        for candidate in candidates {
            guard let relation = relationByVariant[candidate] else { continue }
            let standard = root(of: candidate)
            switch preference.mode(for: relation.group) {
            case .standardOnly:
                continue
            case .standardFirst:
                variantsAfter[standard, default: []].append(candidate)
            case .permittedFirst:
                variantsBefore[standard, default: []].append(candidate)
            }
        }
        // 組(本則+許容形)は、その組の最初のメンバーが現れた位置にまとめて出す。以前は許容形を飛ばして
        // 本則の位置で出していたため、最良候補が許容形(醗酵を行なう)だと組ごと本則(3 位)の位置まで
        // 落ち、無関係な 2 位(発行を行なう)が先頭に繰り上がっていた(2880)
        func emitGroup(standard: String) {
            for variant in variantsBefore[standard] ?? [] where inserted.insert(variant).inserted {
                result.append(variant)
            }
            if inserted.insert(standard).inserted {
                result.append(standard)
            }
            for variant in variantsAfter[standard] ?? [] where inserted.insert(variant).inserted {
                result.append(variant)
            }
        }
        for candidate in candidates {
            if inserted.contains(candidate) {
                continue
            }
            if relationByVariant[candidate] != nil {
                // 本則のみの設定でも、許容形が現れた位置に本則を出す(順位を保つ)。許容形だけを捨てると
                // 最良候補(醗酵を行なう)が消えて本則が 3 位の位置に落ち、無関係な 2 位が先頭になる
                emitGroup(standard: root(of: candidate))
                continue
            }
            emitGroup(standard: candidate)
        }
        return result
    }
}
