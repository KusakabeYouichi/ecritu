import Foundation

// かな識別(読みそのままのひらがな候補)を変換候補の先頭に残すかの判定(keepKana)。
// 単文節・連文節・表示層(candidatesForPresentation)が同じ述語を使う。
// KanaKanjiConverter.swift 本体(1949 行)から純移動(2805 リファクタ)。
// ファイル越境のため private だった補助関数は internal(モジュール境界でカプセル化)。
extension KanaKanjiConverter {
    // かな識別を変換候補の先頭に残すべき読みか。かなが正書とみなせる根拠(辞書に実在する
    // かな語=ちゃんと/そして、追加語彙のかな語=だが/なのに、学習済み)がある場合のみ true。
    // 活用+postfix の合成で組み上がったかな全文一致(かってみようかな 等)は変換意図の
    // 入力なので対象外(末尾のかなチップに一本化する)。
    // て/で 形+授受補助動詞(くれ/あげ)+任意のひらがな連鎖で終わる読みか。
    // してくれて/してくれないかな/してくれてるのね 等を列挙なしで一般判定する。
    static func hasTeBenefactiveKanaTail(_ reading: String) -> Bool {
        // てください/でください(依頼の補助動詞、かなが正書)も同型: してください が全かなエコー抑制で
        // 連文節から消え、単文節の 仕手ください が先頭に出ていた(2720)
        for marker in ["てくれ", "でくれ", "てあげ", "であげ", "てくださ", "でくださ"] {
            guard let range = reading.range(of: marker, options: .backwards),
                range.lowerBound != reading.startIndex else {
                continue
            }
            let tail = reading[range.upperBound...]
            if tail.unicodeScalars.allSatisfy({ (0x3041...0x3096).contains($0.value) }) {
                return true
            }
        }
        return false
    }

    // curated かな正書として登録してあるが、動詞未然形にも接続する否定辞。これで終わる読みは
    // 「〜がなかった」(かな正書)と「知らなかった」(活用形)の両方があり得るため、後者を
    // 取り違えないよう脱活用で判別する。
    static let kanaNegativeAuxiliaryCuratedSuffixes: Set<String> = ["なかった", "なくて", "ない"]

    // 読みが辞書の用言(漢字表記を持つ基底)へ脱活用できるか。活用形の判別に使う。
    func deinflectsToDictionaryPredicate(_ reading: String) -> Bool {
        guard let lastCharacter = reading.last,
            let ruleIndices = Self.deinflectionRulesByReadingLastCharacter[lastCharacter] else {
            return false
        }
        for index in ruleIndices {
            let rule = Self.allInflectionRules[index]
            guard !rule.readingSuffix.isEmpty, reading.hasSuffix(rule.readingSuffix) else { continue }
            let stem = reading.dropLast(rule.readingSuffix.count)
            guard stem.count >= 1 else { continue }
            let baseReading = String(stem) + rule.baseReadingSuffix
            if systemCandidates(for: baseReading, mode: .lesDeux)
                .contains(where: { Self.containsKanjiCandidate($0) }) {
                return true
            }
        }
        return false
    }

    func shouldKeepKanaIdentityLeading(for reading: String) -> Bool {
        let normalized = KanaTextNormalizer.normalizedReading(reading)
        guard !normalized.isEmpty else {
            return false
        }
        if let cached = stateQueue.sync(execute: { kanaIdentityLeadingCache[normalized] }) {
            return cached
        }
        let result = computeShouldKeepKanaIdentityLeading(normalized: normalized)
        stateQueue.sync {
            if kanaIdentityLeadingCache.count >= kanaIdentityLeadingCacheLimit {
                kanaIdentityLeadingCache.removeAll(keepingCapacity: true)
            }
            kanaIdentityLeadingCache[normalized] = result
        }
        return result
    }

    // 語幹のかなが正書か: 辞書にかなエントリが在り、かつ 語LM でかなが同読みの漢字代替の最安に
    // 迫っている(マージン800: 表記揺れの僅差は許容)。ある(2698≪有る6303)/ひらがな(6258 vs
    // 平仮名6089=僅差)は true、きた(7792 vs 北≈4300=大差)は false(2512)。
    func isKanaOrthographyStem(_ stem: String) -> Bool {
        let candidates = systemCandidates(for: stem, mode: .lesDeux)
        guard candidates.contains(stem) else {
            return false
        }
        let kanjiAlternatives = candidates.filter { Self.containsKanjiCandidate($0) }
        guard !kanjiAlternatives.isEmpty else {
            return true
        }
        let uni = store.wordLMUnigramCosts(for: [stem] + kanjiAlternatives)
        guard let kanaUni = uni[stem] else {
            return kanjiAlternatives.compactMap { uni[$0] }.isEmpty
        }
        guard let altBest = kanjiAlternatives.compactMap({ uni[$0] }).min() else {
            return true
        }
        return kanaUni < altBest + 800
    }

    func computeShouldKeepKanaIdentityLeading(normalized: String) -> Bool {
        if hasLearnedKanaIdentity(for: normalized) || hasCuratedKanaIdentity(for: normalized) {
            return true
        }
        // 口語の否定コピュラ・断定(じゃない/じゃん/だろう/でしょ 等)で終わる読みは、かなが
        // 正書の話し言葉(そうじゃないか/きれいじゃない 等)。連文節は全語彙経路として これらを
        // 最良に選べる(allNodesAreDictWords 非抑制)ので、提示層でも先頭かなを保持する根拠とする。
        // 名詞+助詞(ずかんで 等)はこの語尾を持たないので影響しない。
        // ではない 系は じゃない の対(ためではない→為ではない の繰り上がり対策。2540)。
        // keepKana は維持のみで昇格しないため、漢字正書の語幹(図鑑ではない 等)に発火しても実害なし。
        for suffix in ["じゃない", "じゃないか", "じゃん", "だろう", "でしょう", "でしょ", "じゃないの",
                       "ではない", "ではないか", "ではないの"]
        where normalized.count > suffix.count && normalized.hasSuffix(suffix) {
            return true
        }
        // 形式名詞「とき」(〜するとき/〜というとき/〜のとき)はかなが正書(2690)。
        // 時刻そのものを指す「時」(3時/その時刻)とは用法が違い、連体修飾を受けた形式名詞は
        // かなで書くのが標準。連文節は 困ったとき/行くとき/食べるときに を既にかな最良に
        // しているが、全かな読み(いざというとき)は素通りエコー抑制で multi が空になり、
        // 単文節の いざという時 が先頭に出ていた。連体修飾(直前が用言の連体形/という/の)の
        // ときだけ根拠にする — 名詞直後(たとえばの時)や単独の とき は対象外
        for tail in ["とき", "ときに", "ときは", "ときの", "ときも", "ときには"]
        where normalized.count > tail.count + 1 && normalized.hasSuffix(tail) {
            let stem = String(normalized.dropLast(tail.count))
            guard let last = stem.last else { continue }
            // 連体修飾の目印: 用言の連体形語尾(る/た/だ/い/な)か「という/の」
            if stem.hasSuffix("という") || stem.hasSuffix("の")
                || "るたないだいくうつむぶぬすぐぐ".contains(last) {
                return true
            }
        }
        // かな正書の語+助詞1字+かな正書の語(2683): いまだとまだ が keepKana=false で提示層に
        // 降格され、実機だけ 今だとまだ が先頭になっていた(いまだ/まだ 単独はどちらも true)。
        // 連結部は格助詞・接続助詞の1字に限り、両側とも根拠のある語のときだけ成立させる
        // (再帰は片側1段まで。長い文全体が無条件に keepKana になるのを防ぐ)
        if normalized.count >= 5 {
            for (index, character) in normalized.enumerated()
            where index >= 2 && index <= normalized.count - 3 {
                let particle = String(character)
                guard Self.multiClauseCaseParticleSurfaces.contains(particle) || particle == "は"
                    || particle == "も" || particle == "の" else {
                    continue
                }
                let head = String(normalized.prefix(index))
                let tail = String(normalized.dropFirst(index + 1))
                guard head.count >= 2, tail.count >= 2,
                    Self.multiClauseKanaAdverbReadings.contains(head)
                        || Self.multiClauseKanaAdverbReadings.contains(tail) else {
                    continue
                }
                if computeShouldKeepKanaIdentityLeading(normalized: head),
                    computeShouldKeepKanaIdentityLeading(normalized: tail) {
                    return true
                }
            }
        }
        // 係助詞 は/も + ない(そんなものはない/なにもない/じかんはない)は補助形容詞・
        // 存在否定のかな正書。連文節は かな最良を返すが根拠が無いと提示層が退避して
        // そんなものは無い が繰り上がっていた(ユーザ報告 2659)。維持のみで昇格しない。
        for suffix in ["はない", "もない", "はなかった", "もなかった", "はなく", "もなく", "はないよ", "もないよ",
                       "はないね", "もないね", "はないな", "もないな", "はないし", "もないし"]
        where normalized.count > suffix.count + 1 && normalized.hasSuffix(suffix) {
            return true
        }
        // 逆接の接続助詞・接続詞(だけど/けど/けれど/けれども)で終わる読みは、かなが正書
        // (だけど 単独/行くけど 等)。ダけど/打けど 等の漢字混じり誤変換が繰り上がるのを防ぐ。
        // 単独(==suffix)も対象にするため hasSuffix のみで判定する。
        // けど+終助詞(けどね/けどさ 等)も同格 — けど 単体しか無かったため、
        // やってないけどね だけ提示層が退避して 演ってないけどね が繰り上がっていた(2543)。
        for suffix in ["だけど", "だけれど", "けれども", "けれど", "けど",
                       "けどね", "けどねー", "けどな", "けどなー", "けどなあ", "けどさ", "けどよ"]
        where normalized.hasSuffix(suffix) {
            return true
        }
        // ていかれる 縮約の受身かなクラスタ(おいてかれてる/もってかれた 等)。
        // 連文節はかな最良を返すが根拠が無いと提示層が退避して 甥てかれてる 等が
        // 繰り上がっていた(2543)。維持のみで昇格しないため 置いて枯れてる 等の
        // 漢字最良ケースには影響しない。
        for suffix in ["てかれてる", "てかれた", "てかれる", "てかれて", "てかれない",
                       "でかれてる", "でかれた", "でかれる", "でかれて", "でかれない"]
        where normalized.count > suffix.count && normalized.hasSuffix(suffix) {
            return true
        }
        // 説明・疑問の終止クラスタ(こうなるのか/どうなるのかな/いいのかも 等)で終わる読みは、
        // かなが正書の話し言葉。連文節は こうなるのか をかな最良に選ぶが根拠が無いと提示層が
        // 末尾へ退避し、実機で 公なるのか が先頭になっていた(実機トレースで converter=かな先頭・
        // 表示=公なるのか先頭 の食い違いを確認、2669)。維持のみで昇格しない。
        for suffix in ["のか", "のかな", "のかなー", "のかも", "のかしら", "のかね", "のかよ", "のかい"]
        where normalized.count > suffix.count + 1 && normalized.hasSuffix(suffix) {
            return true
        }
        // 複合助詞(では/には/とは/でも 等)そのものはかなが正書。デは/出は/手は 等の漢字混じり
        // 誤変換が提示層で繰り上がるのを防ぐ(単独入力=複合助詞の話題断片)。
        if Self.multiClauseCompoundParticles.contains(normalized) {
            return true
        }
        // 長音化した終助詞クラスタそのもの(かなー/よねー/なー 等、会話の詠嘆・疑問)はかなが正書。
        // か(過/花/夏…)+なー 等の1字漢字合成が提示層で繰り上がるのを防ぐ。
        if normalized.hasSuffix("ー"), Self.multiClauseFinalParticleReadings.contains(normalized) {
            return true
        }
        // 補助動詞 〜て/でもらう(してもらった/よんでもらう 等)はかなが正書。converter は
        // seed(もらう=かな先頭)により かな最良を返すが、この根拠が無いと提示層が退避して
        // して貰った が繰り上がっていた(実機トレースで converter=かな先頭・表示=貰った先頭の
        // 食い違いを確認、2534)。て/で+もらう の形は補助動詞構文に限られるため誤発火しない。
        for suffix in ["てもらう", "てもらった", "てもらって", "てもらい", "てもらいます", "てもらいました",
                       "てもらえる", "てもらえば", "てもらえ", "てもらおう",
                       "でもらう", "でもらった", "でもらって", "でもらい", "でもらいます", "でもらいました",
                       "でもらえる", "でもらえば", "でもらえ", "でもらおう"]
        where normalized.count > suffix.count && normalized.hasSuffix(suffix) {
            return true
        }
        // 丁寧の ます(常にかな。マス/升/増す 等の漢字・カタカナ化は不自然)+終助詞/助動詞
        // (ね/よ/か/ました…)で終わる読み。ますね→マスね 等の繰り上がりを防ぐ。
        for suffix in ["ますね", "ますよ", "ますか", "ますが", "ますし", "ますよね", "ますねー", "ますよー",
                       "ました", "まして", "ませんか", "ません", "ましょう", "ましょ", "ます"]
        where normalized.hasSuffix(suffix) {
            return true
        }
        // 終助詞(よ/ね/な/わ/ぞ/さ)を1つ剥がした語幹が「辞書のかな語そのもの」(いい/だめ/やだ/むり 等)
        // なら根拠あり(いいよ→いい: 良いよ/イイよ/唯々よ の繰り上がりを防ぐ)。※systemCandidates 直接判定に
        // 限定し、活用連鎖(かってみよう 等=辞書かな語でない)では誤発火しない。
        // そう は文末の推量・指示(ほとんどそう/たぶんそう)。の は連体の言いさし
        // (それぞれの/ひとりひとりの)。いずれもかな語幹+終端はかなが正書
        // なあ/ねえ 系(詠嘆の長形。すごいなあ 等)も同型 — な の1字剥がしでは語幹が
        // すごいな になり不成立のため、長形を明示する(2403)。
        // よね/よねえ(同意を求める複合終助詞)も同型。おいしいよね は おいしい が misc の
        // かな正書登録なので語幹の根拠が立つ。2文字以上の複合形はリストに無く漏れていた(2564)
        for particle in ["よ", "ね", "な", "わ", "ぞ", "ぜ", "さ", "そう", "の", "なあ", "なぁ", "ねえ", "ねぇ",
                         "よね", "よねえ", "よねー", "わね", "わよ", "もんね"]
        where normalized.count > particle.count && normalized.hasSuffix(particle) {
            let stem = String(normalized.dropLast(particle.count))
            if stem.count >= 2, systemCandidates(for: stem, mode: .lesDeux).contains(stem) {
                return true
            }
            // 語幹自身に根拠があれば終助詞付きも同格(もったいないよ/よね: もったいない は
            // dictionary_entries に行が無く上の辞書判定に掛からないが、単独では根拠が立って
            // かな先頭で出る。終助詞を付けた途端 勿体無いよ が繰り上がっていた。2659)
            if stem.count >= 3, computeShouldKeepKanaIdentityLeading(normalized: stem) {
                return true
            }
            // curated かな識別(misc の だっけ 等=かな正書の明示登録)も語幹の根拠と認める。
            // ダッケ suppr 後の だっけ は辞書エントリが空で systemCandidates では拾えず、
            // keepKana=false → 提示層がかな最良(だっけな)を退避して候補なしになる。
            if stem.count >= 2,
                (store.initialAjoutVocabulary()[stem] ?? []).contains(stem)
                    || (store.ajoutVocabulary()[stem] ?? []).contains(stem) {
                return true
            }
            // かな機能語クラスタ(のに/のは 等の準体助詞+助詞)も語幹の根拠(のになあ→のに。
            // 辞書にエントリが無く systemCandidates では拾えない。2535)
            if Self.multiClauseNominalizerSurfaces.contains(stem) {
                return true
            }
            // 助詞1字+かな正書語の語幹(はうまい/がすごい 等)も根拠あり(2647):
            // 実機トレースでエンジンは はうまいなあ かな先頭なのに、根拠が立たず提示層が
            // 退避して は上手いなあ が繰り上がっていた
            if stem.count >= 3,
                let head = stem.first,
                Self.multiClauseCaseParticleSurfaces.contains(String(head)) || head == "の" {
                let rest = String(stem.dropFirst())
                if systemCandidates(for: rest, mode: .lesDeux).contains(rest) {
                    return true
                }
            }
            // い形容詞のかな過去(よかった/すごかった 等)は活用形なので辞書エントリでは拾えない。
            // Xかった→基底 X+い に脱活用して基底が辞書のかな語なら根拠あり(よかったな→よかった→
            // よい)。keepKana は「既にかな先頭の候補を維持するだけ」で昇格はしないため、漢字正書の
            // 形容詞(高かったな 等=エンジンが漢字先頭)に発火しても実害はない。
            if stem.count >= 4, stem.hasSuffix("かった") {
                let adjectiveBase = String(stem.dropLast(3)) + "い"
                if systemCandidates(for: adjectiveBase, mode: .lesDeux).contains(adjectiveBase) {
                    return true
                }
            }
        }
        // 説明・推量の のだろ/んだろ(のだろう の言いさし)で終わる読みは、剥がした語幹が
        // かな正書の識別なら根拠あり(いつだったのだろ→いつだった→いつ=seedかな先頭)。
        // 長形の のだろう は下の のは 群が拾うが、短形は末尾が の で終わらないため別途扱う(2455)
        for tail in ["のだろ", "んだろ"]
        where normalized.count > tail.count && normalized.hasSuffix(tail) {
            var stem = String(normalized.dropLast(tail.count))
            // コピュラ(だった/でした/だ/です)も続けて剥がす(いつだったのだろ→いつ)
            for copula in ["だった", "でした", "です", "だ"]
            where stem.count > copula.count && stem.hasSuffix(copula) {
                stem = String(stem.dropLast(copula.count))
                break
            }
            if stem.count >= 2, computeShouldKeepKanaIdentityLeading(normalized: stem) {
                return true
            }
        }
        // 準体助詞クラスタ(のに/のは/のが/のを/のも)で終わる読みは、剥がした語幹がかな正書の
        // 根拠を持つなら根拠あり。既存の判定は「終助詞を剥がした語幹がちょうど のに」という形
        // (のになあ)しか見ておらず、語幹側に のに が付く形(そんなことないのに)は漏れていた。
        // そんなことない/ないのに は個別には true なのに、繋げた形だけ false で提示層がかなを
        // 捨て、其麼ことないのに が先頭に残っていた(2584)。
        // 剥がした語幹の再帰判定なので、漢字が正書の語(食べるのに 等)には根拠が立っても
        // keepKana は昇格しないため表示は変わらない。
        for cluster in Self.multiClauseNominalizerSurfaces
        where normalized.count > cluster.count + 1 && normalized.hasSuffix(cluster) {
            let stem = String(normalized.dropLast(cluster.count))
            if stem.count >= 2, computeShouldKeepKanaIdentityLeading(normalized: stem) {
                return true
            }
        }
        // 連体の「の」で始まる断片(のときは/のときのは 等、文中から打ち始めた形)は、
        // 先頭の の を剥がした残りがかな正書の識別なら根拠あり(2455)。
        if normalized.count > 3, normalized.hasPrefix("の") {
            let remainder = String(normalized.dropFirst())
            if computeShouldKeepKanaIdentityLeading(normalized: remainder) {
                return true
            }
        }
        // 補助形容詞 やすい/にくい/づらい(+任意の ので)を剥がし、連用形の基底動詞が
        // seed かな先頭なら根拠あり(できやすいので→できやすい→でき→できる=seedかな先頭)。
        // ので の一般再帰は たべるので を巻き込むため、この経路に限定する(2453)。
        do {
            var probe = normalized
            if probe.count > 2, probe.hasSuffix("ので") {
                probe = String(probe.dropLast(2))
            }
            for auxiliary in ["やすい", "にくい", "づらい"]
            where probe.count > auxiliary.count && probe.hasSuffix(auxiliary) {
                let renyou = String(probe.dropLast(auxiliary.count))
                guard renyou.count >= 2 else { continue }
                for base in [renyou + "る", renyou + "う", renyou + "く"]
                where KanaKanjiSeedDictionary.seed[base]?.first == base {
                    return true
                }
            }
        }
        // 活用形の基底読みが seed でかな先頭に固定された用言(できる/なる 等)なら、その活用形も
        // かなが正書。できれば は提示層が 出来れば をかな版の下へ回す(demotingDekiKanjiBelowKana)
        // 一方で、かな識別に根拠が無いと除去してしまい 出来れば が先頭に残っていた(2467)。
        if let lastCharacter = normalized.last,
            let ruleIndices = Self.deinflectionRulesByReadingLastCharacter[lastCharacter] {
            for index in ruleIndices {
                let rule = Self.allInflectionRules[index]
                guard !rule.readingSuffix.isEmpty, normalized.hasSuffix(rule.readingSuffix) else { continue }
                let stem = normalized.dropLast(rule.readingSuffix.count)
                guard !stem.isEmpty else { continue }
                let baseReading = String(stem) + rule.baseReadingSuffix
                if KanaKanjiSeedDictionary.seed[baseReading]?.first == baseReading {
                    return true
                }
            }
        }
        // 引用の という/といって 等はかなが正書(などという/とかというのは)。前に立つのがかな正書の
        // 副助詞・並立助詞のときだけ維持する — 語幹を再帰判定にすると 図鑑(ずかん、辞書にかな
        // エントリがある)まで巻き込むため、語幹は明示集合に限定する(2487)。
        for quotation in Self.kanaOrthographyQuotationTails
        where normalized.count > quotation.count && normalized.hasSuffix(quotation) {
            let stem = String(normalized.dropLast(quotation.count))
            if Self.kanaOrthographyQuotationStems.contains(stem)
                || Self.kanaOrthographyQuotationStems.contains(where: { stem.hasSuffix($0) }) {
                return true
            }
        }
        // 接尾の補助動詞 まくり/まくる(〜しまくり/読みまくる)はかなが正書。辞書の まくり は
        // 海人草(まくり=生薬)/捲り が主で、かな まくり は wc11137 と重いため提示層で
        // し捲り に繰り上げられていた(2505)。
        for auxiliary in ["まくり", "まくる", "まくった", "まくって", "まくれ"]
        where normalized.count > auxiliary.count && normalized.hasSuffix(auxiliary) {
            return true
        }
        // やる の活用形で始まる全かなの読み(やってみようかな/やっておく/やりきる 等)は
        // かなが正書。やる は seed でかな先頭に固定してあり、当て表記(演る/犯る/飲る/行る/
        // 遣る/殺る)は提示層の demotingDekiKanjiBelowKana がかな版の下へ回す。ところが
        // その降格は「同じ候補列にかな版が居ること」が条件で、keepKana が false だと提示層が
        // 先にかな版を捨ててしまい、遣ってみようかな が先頭に残っていた(2583)。
        // やってみよう/やってみようかなー は別経路で true になっていて、間に挟まる
        // やってみようかな だけ false という不整合だったので、やる系をまとめて根拠にする。
        // keepKana は昇格せず「既にかな先頭の候補を維持する」だけなので、やり方 のように
        // 漢字が正書の語(エンジンが漢字先頭)に当たっても表示は変わらない。
        if normalized.count >= 3, normalized.hasPrefix("や"),
            normalized.unicodeScalars.allSatisfy({ (0x3041...0x3096).contains($0.value) }) {
            let second = normalized[normalized.index(normalized.startIndex, offsetBy: 1)]
            if SupplementaryCandidateMerger.yaruInflectionHeads.contains(second) {
                return true
            }
        }
        // 末尾を長音で引き伸ばした形(なるほどー/なるほどーー)は辞書に無く、合成の
        // {成保どー, 鳴穂どー} だけが並ぶ。長音を剥がした本体がかな正書の根拠を持つなら
        // 伸ばした形もかなが正書(2564)。本体判定の再帰なので、成る程 が正書の語には
        // 発火しない。長音だけの読み(ーー)は本体が空になるので対象外。
        if normalized.count > 1, normalized.hasSuffix("ー") {
            var stem = normalized
            while stem.count > 1, stem.hasSuffix("ー") {
                stem = String(stem.dropLast())
            }
            if stem.count >= 2, computeShouldKeepKanaIdentityLeading(normalized: stem) {
                return true
            }
        }
        // 語中に長音を挟んだ強調形(すごーい/たかーい/ながーい)も同じ扱い。末尾長音の
        // 判定だけでは すごーい(末尾は い)に発火しない。長音を全部取り除いた本体が
        // かな正書なら伸ばした形もかなが正書(すごい は seed でかな先頭。2564)。
        // 対象は本体が全てかなのときだけ — ラーメン/コーヒー のようなカタカナ語の
        // ひらがな入力(らーめん)を巻き込まないため。
        if normalized.count > 2, normalized.contains("ー"),
            !normalized.hasSuffix("ー") {
            let stem = normalized.replacingOccurrences(of: "ー", with: "")
            if stem.count >= 2, stem != normalized,
                stem.unicodeScalars.allSatisfy({ (0x3041...0x3096).contains($0.value) }),
                computeShouldKeepKanaIdentityLeading(normalized: stem) {
                return true
            }
        }
        // 指示代名詞(それ/これ 等)始まりの句は、続く副助詞(ぐらい/だけ 等、任意)を剥がした
        // 残りがかな維持の根拠を持つなら維持(それぐらいやるよ→やるよ→やる=辞書かな語。
        // 反れ/剃れ の活用が提示層で繰り上がるのを防ぐ。2535)。
        for pronoun in KanaKanjiConverter.kanaOrthographyDemonstrativePronounStems
        where normalized.count > pronoun.count && normalized.hasPrefix(pronoun) {
            var remainder = String(normalized.dropFirst(pronoun.count))
            for particle in ["ぐらい", "くらい", "だけ", "まで", "でも", "なら", "こそ", "ばかり", "ほど"]
            where remainder.count > particle.count && remainder.hasPrefix(particle) {
                remainder = String(remainder.dropFirst(particle.count))
                break
            }
            if remainder.count >= 2, computeShouldKeepKanaIdentityLeading(normalized: remainder) {
                return true
            }
        }
        // 丁寧のです系末尾(ですもんね/ですかね 等)を剥がした残りがかな正書の根拠を
        // 持つなら維持(できないですもんね→できない=活用剥がしで できる seed かな先頭。
        // 表示層で 出来ないですもんね が先頭に残っていた。2560)。
        for tail in ["ですもんね", "ですかね", "ですよね", "ですね", "ですもん", "ですよ", "です"]
        where normalized.count > tail.count + 1 && normalized.hasSuffix(tail) {
            let remainder = String(normalized.dropLast(tail.count))
            if computeShouldKeepKanaIdentityLeading(normalized: remainder) {
                return true
            }
            break
        }
        // seed かな先頭の語+末尾助詞(おもろまちなら/おもろまちならば 等)はかなが正書。
        // 連文節エンジンはかな先頭を返すのに、表示層のかな識別根拠が無く除去されて
        // お諸町なら が繰り上がっていた(実機トレースで確定。2557)。剥がす助詞は明示集合、
        // 残り語幹は seed のかな先頭指定(人手選別)に限るので、名詞+助詞一般は巻き込まない。
        if normalized.count >= 3 {
            for particle in Self.kanaIdentityTrailingParticles
            where normalized.count > particle.count && normalized.hasSuffix(particle) {
                let stem = String(normalized.dropLast(particle.count))
                if KanaKanjiSeedDictionary.seed[stem]?.first == stem {
                    return true
                }
            }
        }
        // かな正書の副詞(せめて 等=multiClauseKanaAdverbReadings)で始まる全かな句は、残りが
        // かな維持の根拠を持つか指示代名詞始まりなら維持(せめてこれぐらい。2513)。
        for adverb in KanaKanjiConverter.multiClauseKanaAdverbReadings
        where normalized.count > adverb.count && normalized.hasPrefix(adverb) {
            let remainder = String(normalized.dropFirst(adverb.count))
            if remainder.count >= 2,
                computeShouldKeepKanaIdentityLeading(normalized: remainder)
                    || KanaKanjiConverter.kanaOrthographyDemonstrativePronounStems
                        .contains(where: { remainder.hasPrefix($0) }) {
                return true
            }
        }
        // 形式名詞(こと/とき/もの/ため)+格助詞1字はかなが正書(ことで/ときに/ものを。
        // ユーザー方針: 接尾辞的な こと/とき はかな)。語幹を明示集合に限るので
        // 名詞+で(ずかんで/しごとで)は巻き込まない(2516)。
        if normalized.count >= 3,
            let last = normalized.last,
            "でにをがはもとへ".contains(last),
            ["こと", "とき", "もの", "ため"].contains(String(normalized.dropLast())) {
            return true
        }
        // かな正書の副詞(たまに 等=multiClauseKanaAdverbReadings)+助詞1字も同型
        // (たまには→玉には の繰り上がり対策。2540)。語幹は明示集合限定なので巻き込みなし。
        if normalized.count >= 3,
            let last = normalized.last,
            "でにをがはもとへ".contains(last),
            KanaKanjiConverter.multiClauseKanaAdverbReadings.contains(String(normalized.dropLast())) {
            return true
        }
        // 否定の連用 なく を剥がして再帰(ことでもなく→ことでも)。なく は seed かな先頭の
        // 頻出かな(2442)。漢字正書の語幹に発火しても keepKana は維持のみで実害なし。
        if normalized.count > 2, normalized.hasSuffix("なく") {
            let stem = String(normalized.dropLast(2))
            if stem.count >= 2, computeShouldKeepKanaIdentityLeading(normalized: stem) {
                return true
            }
        }
        // 複合助詞(でも/では/には 等)を1つ剥がして再帰(ことでも→こと)。
        // 単字助詞の剥がしと同様、維持のみで昇格しないため巻き込みは無害。
        for particle in KanaKanjiConverter.multiClauseCompoundParticles
        where normalized.count > particle.count && normalized.hasSuffix(particle) {
            let stem = String(normalized.dropLast(particle.count))
            if stem.count >= 2, computeShouldKeepKanaIdentityLeading(normalized: stem) {
                return true
            }
        }
        // 存在・進行の かな動詞(ある/いる)を剥がして再帰(やつにはある→やつには→(は/に 剥がし)→やつ)。
        // かな正書の語(やつ/ひび 等)+ 助詞 + ある/いる の全かな句が提示層で漢字化(奴にはある)に
        // 繰り上がるのを防ぐ。剥がした語幹が最終的にかな正書の識別に落ちる時だけ true。
        for verb in ["ある", "いる", "あった", "いた"]
        where normalized.count > verb.count && normalized.hasSuffix(verb) {
            let stem = String(normalized.dropLast(verb.count))
            // 接続助詞のて形+係助詞(ても/でも/ては/では)は用言に続く純かな語幹なので明示許可
            // (てもある→ても有る の退避対策。2517)
            if ["ても", "でも", "ては", "では", "とも"].contains(stem) {
                return true
            }
            if stem.count >= 2, computeShouldKeepKanaIdentityLeading(normalized: stem) {
                return true
            }
        }
        // 形式名詞(こと/とき/もの/ため/だけ)で終わる名詞化節は かな が正書(することがある→
        // ある/が を剥がした することが→すること、見るとき 等)。前に述語相当(2文字以上)がある
        // 全かな句は提示層で先頭かなを維持する(することがある→する事がある への繰り上がりを防ぐ)。
        // 疑問・引用の終端(かと/かな/か 等)は剥がしてから照合する(ってことかと→ってこと。
        // エンジンはかな最良なのに keepKana 不成立で って事かと が繰り上がるのを防ぐ)。
        var formalNounProbe = normalized
        for interrogativeTail in ["かと", "かな", "か"]
        where formalNounProbe.count > interrogativeTail.count
            && formalNounProbe.hasSuffix(interrogativeTail) {
            formalNounProbe = String(formalNounProbe.dropLast(interrogativeTail.count))
            break
        }
        // 連体修飾の の も剥がしてから形式名詞を照合する(そのための→そのため。そのため は
        // keep 成立なのに ための だと形式名詞の末尾照合に当たらず、実機で その為の が
        // 繰り上がっていた。名詞+の(図鑑の)は下の形式名詞照合に落ちないので無害。2489)
        if formalNounProbe.count > 3, formalNounProbe.hasSuffix("の") {
            formalNounProbe = String(formalNounProbe.dropLast())
        }
        // 格助詞 で は1字だけ剥がしてから照合(ってやつで→ってやつ)。で の一般再帰剥がしは
        // 名詞+で(ずかんで)や ので の厳格ゲート(たべるので)を迂回してしまうため行わない(2404)。
        if formalNounProbe.count > 1, formalNounProbe.hasSuffix("で") {
            formalNounProbe = String(formalNounProbe.dropLast())
        }
        for noun in KanaKanjiConverter.multiClauseFormalNounKanaReadings
        where formalNounProbe.count > noun.count && formalNounProbe.hasSuffix(noun) {
            let stem = String(formalNounProbe.dropLast(noun.count))
            if stem.count >= 2 {
                return true
            }
        }
        // て形+授受補助動詞で終わる読み(してくれて/教えてあげて/してくれてるのね 等)は
        // かなが正書 — エンジンの授受クランプ(isTeBenefactiveAuxiliaryReading)と同じ発想の
        // 一般判定。マーカ(て/で+くれ/あげ)以降が全ひらがなで文末まで続けば、活用形や
        // 終助詞クラスタが何であっても根拠あり(列挙リストは くれてる 等の漏れが続いたため廃止)。
        // かな最良が提示層で退避され して暮れてるのね 等が繰り上がるのを防ぐ(維持のみで昇格しない)。
        if Self.hasTeBenefactiveKanaTail(normalized) {
            return true
        }
        // 疑問・説明の のか に長音 ー が付く読み(なのかー/そうなのかー 等)は口語終端で
        // かなが正書。名詞漢字+のかー(名/菜+のかー 等)の無意味分割より かな全文を先頭へ。
        // 長音なしの なのか(=七日)は辞書語を守るため対象外(ー 付きに限定)。
        if normalized.count > 3, normalized.hasSuffix("のかー") {
            return true
        }
        if (store.initialAjoutVocabulary()[normalized] ?? []).contains(normalized) {
            return true
        }
        // curated かな識別(やって/やってみる 等の misc 登録)で終わり、前半が辞書のかな語
        // (とにかく 等)なら根拠あり(とにかくやってみる)。前半+curated末尾 の全かな句は
        // かなが正書とみなす。
        if normalized.count >= 5 {
            let initialDictionary = store.initialAjoutVocabulary()
            let manualDictionary = store.ajoutVocabulary()
            let maxSuffix = min(8, normalized.count - 2)
            for suffixLength in 3...maxSuffix {
                let suffix = String(normalized.suffix(suffixLength))
                guard (initialDictionary[suffix] ?? []).contains(suffix)
                    || (manualDictionary[suffix] ?? []).contains(suffix) else { continue }
                // 否定辞(なかった 等)は curated のかな正書(じかんがなかった)であると同時に
                // 動詞未然形にも付く(しら+なかった=知らなかった)。読み全体が辞書の用言へ
                // 脱活用できるなら活用形なので、この根拠は立てない — しら がたまたま辞書に
                // かなエントリを持つ(rank2 のかな収穫)ために しらなかった のかなが先頭に
                // 居座っていた(ユーザ報告 2753)。
                if Self.kanaNegativeAuxiliaryCuratedSuffixes.contains(suffix),
                    deinflectsToDictionaryPredicate(normalized) {
                    continue
                }
                let prefix = String(normalized.dropLast(suffixLength))
                if prefix.count >= 2,
                    systemCandidates(for: prefix, mode: .lesDeux).contains(prefix)
                        || store.wordCosts(for: prefix)[prefix] != nil {
                    return true
                }
            }
        }
        // seed でかな先頭に固定された語(たくさん/やっぱり/いつ/とき 等)で終わり、前半が
        // 2文字以上ある全かな句は、末尾語がかな正書なので先頭かなを維持する
        // (うまいものがたくさん→末尾 たくさん。curated 版の下の規則を seed へ広げたもの。2463)
        // 語長3文字以上に限る — 2文字の助詞相当(ので/とき 等)まで拾うと たべるので/みるので の
        // ような「述語+助詞」で漢字先頭を維持したいケースを壊す(2507の検証で3件退行)
        if normalized.count >= 5 {
            let maxSuffix = min(8, normalized.count - 2)
            for suffixLength in 3...max(3, maxSuffix) where suffixLength <= normalized.count - 2 {
                let suffix = String(normalized.suffix(suffixLength))
                guard KanaKanjiSeedDictionary.seed[suffix]?.first == suffix else {
                    continue
                }
                return true
            }
        }
        if (store.ajoutVocabulary()[normalized] ?? []).contains(normalized) {
            return true
        }
        if systemCandidates(for: normalized, mode: .lesDeux).contains(normalized) {
            return true
        }
        // 形容詞化の ない 系を剥がした語幹が「辞書のかな語」かつ「LM でかな優位」なら
        // かなが正書(もったいない: もったい 7272<勿体 7715。読み全体は辞書/LM に無い)。
        // 知らない 等は語幹の漢字(白/知ら…)が LM 優位なので発火しない(2406)。
        for tail in ["なかった", "なくて", "ない"]
        where normalized.count > tail.count + 1 && normalized.hasSuffix(tail) {
            let stem = String(normalized.dropLast(tail.count))
            let stemCandidates = systemCandidates(for: stem, mode: .lesDeux)
            guard stemCandidates.contains(stem) else { continue }
            let kanjiOthers = stemCandidates.filter { $0 != stem && Self.containsKanjiCandidate($0) }
            if !kanjiOthers.isEmpty, isLMKanaPreferred(reading: stem, among: kanjiOthers) {
                return true
            }
        }
        // 辞書に読みエントリが無い派生専用のかな語(もったいない 等=勿体+ない の合成のみ)は、
        // LM unigram にかな表層が実在すれば かなが正書の証拠とする。Wikipedia は漢字寄りの
        // コーパスなので、かな表層が収録されている時点で強いシグナル。辞書エントリがある読み
        // (ばあい=場合 等)は対象外(2406)。
        if normalized.count >= 4,
            store.wordCosts(for: normalized).isEmpty,
            store.wordLMUnigramCosts(for: [normalized])[normalized] != nil {
            return true
        }
        // 理由の ので 付きの読みは、剥がした語幹が seed でかな先頭に固定された正書のかな語
        // (ある/いる 等)のときだけ根拠ありとする(いるので/あるので: かなを #2 位置維持で残す)。
        // たべる/みる 等は dict rank2 に かな harvest があり systemCandidates.contains では拾えて
        // しまうため、より厳しい「seed かな先頭 or 学習済みかな識別」で判定する(食べるので/見るので
        // にかなが混ざるのを防ぐ)。
        if normalized.count > 2, normalized.hasSuffix("ので") {
            let stem = String(normalized.dropLast(2))
            if stem.count >= 2,
                (KanaKanjiSeedDictionary.seed[stem]?.first == stem || hasLearnedKanaIdentity(for: stem)) {
                return true
            }
        }
        // 理由のコピュラ だから を剥がした語幹が辞書のかな語(ばかり=副助詞 等)なら根拠あり
        // (ばかりだから→ばかり)。ばかり は candidate_sources のモードタグで systemCandidates に
        // かな識別が出ないため、word_costs のかな識別(ばかり=5598 実在)でも根拠と認める。
        // 名詞+だから(学生だから=漢字正書)に発火しても keepKana は維持のみで実害なし。
        if normalized.count > 3, normalized.hasSuffix("だから") {
            let stem = String(normalized.dropLast(3))
            if stem.count >= 2,
                systemCandidates(for: stem, mode: .lesDeux).contains(stem)
                    || store.wordCosts(for: stem)[stem] != nil {
                return true
            }
        }
        // 言いさし終止の から を剥がして再帰(じゃないから→じゃない: コピュラ否定末尾で true)。
        // ので は既存の厳格ゲート(seedかな先頭/学習のみ。たべるので を素通りさせない)を迂回
        // しないよう汎用剥がしにせず、じゃない系の複合末尾だけ下で明示する。
        if normalized.count > 3, normalized.hasSuffix("から") {
            let stem = String(normalized.dropLast(2))
            if stem.count >= 2, computeShouldKeepKanaIdentityLeading(normalized: stem) {
                return true
            }
        }
        // 疑問・推量の終端(かなあ/かも/かな/かと/か)を剥がした語幹が「辞書のかな語そのもの」
        // (いくつか→いくつ)か「かな語+ある/いる」(いくつあるかも→いくつある→いくつ)か
        // 「て/で形+授受補助動詞」(してくれないかな→してくれない)なら根拠あり。エンジンが
        // かな最良の疑問句が提示層で退避され 幾つあるかも/して暮れないかな 等が繰り上がるのを
        // 防ぐ。全面再帰にはしない — かってみようかな(活用連鎖の防護ケース)へ かってみよう の
        // 別根拠が伝播して退行した(2375)ため、限定列挙の狭い根拠にとどめる。
        for tail in ["かなあ", "かも", "かな", "かと", "か"]
        where normalized.count > tail.count && normalized.hasSuffix(tail) {
            let stem = String(normalized.dropLast(tail.count))
            guard stem.count >= 2 else { continue }
            if systemCandidates(for: stem, mode: .lesDeux).contains(stem) {
                return true
            }
            for verb in ["ある", "いる"]
            where stem.count > verb.count && stem.hasSuffix(verb) {
                let subStem = String(stem.dropLast(verb.count))
                if subStem.count >= 2, systemCandidates(for: subStem, mode: .lesDeux).contains(subStem) {
                    return true
                }
            }
            // コピュラ推量末尾(どこだろうか→どこだろう、そうでしょうかも 等)も根拠あり
            // (先頭のコピュラ末尾規則と同じ語彙。か 等が付くと届かないのをここで補う)
            for cop in ["だろう", "でしょう", "でしょ", "じゃない", "じゃん"]
            where stem.count > cop.count && stem.hasSuffix(cop) {
                return true
            }
        }
        // コピュラ否定(じゃない/じゃなくて/じゃなかった)で終わる全かな句はかなが正書
        // (じゃ+無かった 等の分割漢字化より かな全文)。keepKana は維持のみで昇格しないため、
        // 名詞部が漢字正書の句(嘘じゃない=エンジンが漢字先頭)に発火しても実害はない。
        for tail in ["じゃなかった", "じゃなかったか", "じゃなかったの", "じゃなくて", "じゃない", "じゃないので", "じゃないんで"] where normalized.hasSuffix(tail) {
            return true
        }
        // コピュラ だ+終助詞(だよ/だね…)と でしょ(でしょう縮約)もかなが正書。終助詞剥がし規則は
        // 語幹2文字以上を要求するため単独 だ では発火しない — 明示末尾で補う。
        for tail in ["だよ", "だね", "だな", "だわ", "だぞ", "だぜ", "だっけ", "でしょ"] where normalized.hasSuffix(tail) {
            return true
        }
        // なる系縮約(〜なってる/〜なっちゃう)で終わる読みはかなが正書(成ってる/為ってる/
        // 綯ってる の漢字化は不自然)。misc curated なってる/なっちゃう と対の提示層維持。
        for tail in ["なってる", "なっちゃう"] where normalized.count > tail.count && normalized.hasSuffix(tail) {
            return true
        }
        // 〜でいい(これでいい/それでいい/ままでいい)の いい はかなが正書(良い は suppr 済みの方針)。
        if normalized.count > 3, normalized.hasSuffix("でいい") {
            return true
        }
        // コピュラ だ(+活用尾 だった/だったら/だし/だって)を剥がした語幹のかな識別が辞書先頭
        // (どう/そう 等のかな正書語)なら根拠あり(どうだ→どう=rank0かな、そうだった→そう)。
        // 純カタカナ識別(ソウ 等)は漢字正書の根拠ではないので除いて先頭判定する。
        // 学生だ/学生だった 等は語幹の辞書先頭が漢字なので発火しない。
        for tail in KanaKanjiConverter.copulaDaTails
        where normalized.count > tail.count && normalized.hasSuffix(tail) {
            let stem = String(normalized.dropLast(tail.count))
            if stem.count >= 2,
                systemCandidates(for: stem, mode: .lesDeux)
                    .first(where: { !KanaKanjiConverter.isPureKatakanaCandidate($0) }) == stem {
                return true
            }
        }
        // 説明の んで(=ので 縮約)付きで、語幹が存在動詞のかな過去(あった/いた)の読みはかなが正書
        // (あったんで/いたんで)。エンジン側(2328)は文節先頭の あった をかな最良にするが、提示層の
        // かな降格が false のままだと先頭かなが末尾チップへ退避され実機だけ 会ったんで 先頭になる。
        if normalized.hasSuffix("んで"),
            KanaKanjiConverter.multiClauseClauseInitialKanaExistentialPasts.contains(String(normalized.dropLast(2))) {
            return true
        }
        // 名詞化節(のは/のが 等)・説明の のね/のよ 付きの読みは、剥がした語幹が辞書の
        // かな語(ひらがな/ある 等)なら根拠ありとする(ひらがなのは/あるのね: 合成でかな
        // 全文一致になるが、かなが正書の語幹+かなが唯一の正書の節、なので変換としてのかなを
        // 候補に残す。提示層は 2122 の位置維持で上位2件ならその位置を保つ)。
        // のだ/んだ/のです/んです(説明のコピュラ)も同型: うまいのだ→うまい(辞書のかな語)。
        // 語幹の条件は「かなが正書(LM でかな優位、または漢字代替なし)」。単に辞書にかなエントリが
        // 在るだけだと きたんだ(語幹 きた=正書は 来た)まで通り、かな きたんだが が候補上位に残る。
        // 辞書先頭で判定する案は ある/ひらがな(辞書先頭は漢字)を巻き添えにした(2512)
        for suffix in ["のは", "のが", "のも", "のを", "のに", "のね", "のよ", "のです", "んです", "のだ", "んだ"] where normalized.hasSuffix(suffix) {
            var stem = String(normalized.dropLast(suffix.count))
            // コピュラ「な」を挟む形(ひらがなな+のは=ひらがな+な+のは)は な も剥がす。
            if stem.count >= 3, stem.hasSuffix("な") {
                let withoutCopula = String(stem.dropLast())
                if isKanaOrthographyStem(withoutCopula) {
                    return true
                }
            }
            if stem.count >= 2, isKanaOrthographyStem(stem) {
                return true
            }
            // 五段る動詞の過去(なった 等)は活用形なので辞書エントリでは拾えない。った→基底 る に
            // 脱活用して基底が辞書のかな語なら根拠あり(なったのは→なった→なる=rank0かな)。
            // 買った(かう基底)等で かる に誤マッチしても keepKana は維持のみで実害なし。
            if stem.count >= 3, stem.hasSuffix("った") {
                let ruBase = String(stem.dropLast(2)) + "る"
                if systemCandidates(for: ruBase, mode: .lesDeux).first == ruBase {
                    return true
                }
            }
        }
        // 格助詞・係助詞を1つ剥がした語幹がかな正書の識別なら根拠ありとする
        // (あったが→あった→ある: ある過去のかな あった を候補に残す)。買ったが→かった→
        // 買う(漢字先頭)は false のまま。剥がしは1回のみ(語幹に助詞は残らない)。
        for particle in ["が", "は", "も", "を", "に", "へ", "と"]
        where normalized.count > particle.count && normalized.hasSuffix(particle) {
            let stem = String(normalized.dropLast(particle.count))
            if stem.count >= 2, computeShouldKeepKanaIdentityLeading(normalized: stem) {
                return true
            }
        }
        // 指示代名詞+助詞(これで/ここまで/そこから 等)はかなが正書。助詞の一般剥がしは
        // 名詞+助詞(ずかんで)を巻き込むため、かな正書の指示代名詞語幹に限定する(2406、
        // 2476 で助詞を まで/から/より/だけ 等に拡張 — ここまで が 小駒で/個々まで に
        // 繰り上げられていた)。
        for particle in KanaKanjiConverter.kanaOrthographyDemonstrativeFollowingParticles
        where normalized.count > particle.count && normalized.hasSuffix(particle) {
            if KanaKanjiConverter.kanaOrthographyDemonstrativePronounStems
                .contains(String(normalized.dropLast(particle.count))) {
                return true
            }
        }
        // かな/カタカナ正書を持つ形容動詞語幹(いや 等)+ 活用語尾。で の一般剥がしは上と同じ
        // 理由で危険なので語幹を明示集合に限定する。エンジンは いやで を2位(イヤで の直後)に
        // 返しているが keepKana 不成立だと提示層が候補から落としてしまう(2464)。
        for stem in KanaKanjiConverter.kanaOrthographyNaAdjectiveStems
        where normalized.count > stem.count && normalized.hasPrefix(stem) {
            let tail = String(normalized.dropFirst(stem.count))
            if KanaKanjiConverter.naAdjectiveInflectionTails.contains(tail),
                computeShouldKeepKanaIdentityLeading(normalized: stem) {
                return true
            }
        }
        // 指示代名詞+助詞 を「先頭から」剥がした残り(それは+いくつ 等)がかな正書の識別なら
        // 根拠あり(既存規則は末尾剥がしのみで、かな正書語が読みの後半にある形を拾えず、
        // エンジンかな最良の それはいくつ が提示層退避で それは幾つ に繰り上がっていた。2420)。
        // 剥がしは先頭1回のみ・語幹はかな正書の指示代名詞に限定する(名詞+助詞の巻き込み防止)。
        for stem in KanaKanjiConverter.kanaOrthographyDemonstrativePronounStems
        where normalized.count > stem.count + 2 && normalized.hasPrefix(stem) {
            let afterStem = normalized.dropFirst(stem.count)
            for particle in ["は", "が", "も", "で", "に", "を", "と", "へ"]
            where afterStem.hasPrefix(particle) {
                let remainder = String(afterStem.dropFirst(particle.count))
                if remainder.count >= 2, computeShouldKeepKanaIdentityLeading(normalized: remainder) {
                    return true
                }
            }
            break
        }
        // 指示連体詞(この/その/あの/どの)で終わる読みは、剥がした語幹がかな正書の識別なら
        // 根拠あり(みんなこの→みんな: エンジンはかな最良なのに keepKana 不成立で 皆この が
        // 繰り上がるのを防ぐ。2404)。
        for demonstrative in ["この", "その", "あの", "どの"]
        where normalized.count > demonstrative.count && normalized.hasSuffix(demonstrative) {
            let stem = String(normalized.dropLast(demonstrative.count))
            if stem.count >= 2, computeShouldKeepKanaIdentityLeading(normalized: stem) {
                return true
            }
        }
        // 文末のかな終助詞クラスタのうち長音化(ー付き=話し言葉)のもの(かなー/よねー/なー 等)を
        // 剥がした語幹がかな正書の識別なら根拠ありとする(ぐらいかなー→ぐらい: 副助詞 ぐらい は
        // かなが正書。連濁でしか ぐらい と読まない 暗い が繰り上がるのを防ぐ)。ー無しの素の かな
        // (かってみようかな 等の活用連鎖)は対象外=従来どおり末尾チップへ退避する。
        for suffix in Self.multiClauseFinalParticleReadings
        where suffix.hasSuffix("ー") && normalized.count > suffix.count && normalized.hasSuffix(suffix) {
            let stem = String(normalized.dropLast(suffix.count))
            if stem.count >= 2, computeShouldKeepKanaIdentityLeading(normalized: stem) {
                return true
            }
        }
        // かな正書の副詞(いまだ/まだ)で終わる読みは、末尾クラスタがかな正書(これはいまだ/
        // これはまだ: 未だ は漢字だが会話ではかな)。ただし しまだ→島田 の誤爆を避けるため、
        // 読み全体が副詞そのものか、直前が助詞(は/も/が/で/に)の時だけ根拠とする。
        for tail in Self.kanaOrthographyAdverbTails
        where normalized.hasSuffix(tail) {
            if normalized == tail {
                return true
            }
            let before = normalized.dropLast(tail.count).last
            if let before, Self.kanaOrthographyAdverbBoundaryParticles.contains(before) {
                return true
            }
        }
        // 活用形の読み(やってそうな 等)は、脱活用した基本形の辞書先頭(抑制適用後)が
        // かな identity(やる 等「かなが正書」の動詞)なら根拠ありとする。
        // かう→買う のように漢字が先頭の基本形は対象外(かってみようかな は末尾のまま)。
        let suppressedByReading = store.suppressedCandidatesByReading()
        let candidateRuleIndices = normalized.last
            .flatMap { Self.deinflectionRulesByReadingLastCharacter[$0] } ?? []
        for index in candidateRuleIndices {
            let rule = Self.allInflectionRules[index]
            guard normalized.hasSuffix(rule.readingSuffix), !rule.readingSuffix.isEmpty else { continue }
            let stem = String(normalized.dropLast(rule.readingSuffix.count))
            guard !stem.isEmpty else { continue }
            let baseReading = stem + rule.baseReadingSuffix
            guard baseReading != normalized else { continue }
            let suppressed = suppressedByReading[baseReading] ?? []
            let first = systemCandidates(for: baseReading, mode: .lesDeux)
                .first { !suppressed.contains($0) }
            if first == baseReading {
                return true
            }
        }
        return false
    }

    // かな候補チップの明示タップでかな識別を学習済みか(candidatesForPresentation が
    // 変換候補側にもかな識別を表示するかの判定に使う)。
    func hasLearnedKanaIdentity(for reading: String) -> Bool {
        let normalizedReading = KanaTextNormalizer.normalizedReading(reading)
        guard !normalizedReading.isEmpty else {
            return false
        }
        return (store.learnedDictionary()[normalizedReading] ?? []).contains(normalizedReading)
    }

    // 追加語彙(手動 or misc.plist の curated)に読みと同一のかな表層が登録されているか。
    // 「かながこの読みの正書」という人手の明示なので、提示層のかな維持根拠として学習と同格に
    // 扱う。keepKana の活用形経路は末尾から活用規則で基底を辿るため、補助動詞付きの句
    // (やってください=やる+て+ください)では基底 やる に到達できず判定できない(2564)。
    func hasCuratedKanaIdentity(for reading: String) -> Bool {
        let normalizedReading = KanaTextNormalizer.normalizedReading(reading)
        guard !normalizedReading.isEmpty else {
            return false
        }
        return (store.ajoutVocabulary()[normalizedReading] ?? []).contains(normalizedReading)
            || (store.initialAjoutVocabulary()[normalizedReading] ?? []).contains(normalizedReading)
    }
}
