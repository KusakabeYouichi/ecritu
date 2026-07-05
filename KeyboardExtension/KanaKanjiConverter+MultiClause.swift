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
    static let multiClauseTopK = 8                  // 1文節あたり列挙する変換候補数(sim: TOPK)
    static let multiClauseInflectionTopK = 3        // 活用派生ノードの1文節あたり上限
    // 活用派生ノードが LM 未収録(普通)のときの専用コスト。LM コーパスは Sudachi A単位で
    // 活用形を「買っ+た」に分割するため、正しい活用表層(買った)は unigram に無い。
    // 一律 dictUnknown(8700)だと LM 収録済みのかな断片チェーン(かっ7079+た2102)や
    // word_costs ジャンク(カッタ7715/多部田7884)に負けるので、unigram 最大(8139)より
    // 下に置き「文法的に検証済みの派生は既知のレア語より僅かに信頼する」とする。
    static let multiClauseInflectionDerivedOOVCost = 7600
    // Nベスト風バリアント: 最良経路の1文節を同区間の次点表層に差し替えて提示する件数と、
    // 採用するコスト差の上限(bigram拮抗の第2候補: しかく→視覚/資格 等を拾う)。
    static let multiClauseVariantLimit = 3
    static let multiClauseVariantMaxDelta = 4000
    // 文末の終助詞クラスタ読み。文末セグメントがこれらの読みなのに表層が漢字(かな→仮名/哉、
    // かも→鴨 等)になるのは不自然なので、EOS 遷移で強めに減点してかな表記を優先する。
    static let multiClauseFinalParticleReadings: Set<String> = ["かな", "かも", "よね", "かしら", "よな"]
    static let multiClauseFinalParticleKanjiPenalty = 3000
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
    // 辞書/変換にはあるがコーパス(LM)未収録の語。unigram 最大(8139)+バックオフ(500)より
    // 上に置き「どの既知語よりレア」として扱う。以前の 6000 は LM 中央値(7649)より安く、
    // 八津(OOV)が 奴(unigram 5963)に勝つ・ちゃ〜んと が ちゃんと に勝つ等の OOV 逆転を
    // 起こしていた。候補バー(単一経路)には引き続き全辞書候補が並ぶため、レア語は手動選択
    // +学習(curated 1500)で救済される。
    static let multiClauseDictUnknownCost = 8700
    static let multiClausePassthroughPerCharCost = 7000 // 未変換かな 1文字あたり(点1: 余りを強く減点)
    static let multiClauseKatakanaNativeCost = 3000 // native 読みなのにカタカナ実体(何でもカタカナ化の抑止)
    // 追加語彙/学習語彙(void.plist 等のキュレーション or 学習)由来の語は強く優遇する。実コストは
    // min(通常コスト, この値)。強い bigram 並みに安くして分割・素通りに確実に勝たせる(=常に列挙も行う)。
    static let multiClauseCuratedWordCost = 1500
    // 語頭(文節頭)に来られない文字で始まる分割は日本語としてほぼあり得ないため強く減点。撥音ん・
    // 長音ー・促音っ・小書きかな等。「を」も現代仮名遣いでは目的格助詞専用なので語中に含めない。
    static let multiClauseForbiddenPenaltyCost = 100000
    static let multiClauseForbiddenInitials: Set<Character> = [
        "ん", "ー", "っ", "ぁ", "ぃ", "ぅ", "ぇ", "ぉ",
        "ゃ", "ゅ", "ょ", "ゎ", "ゕ", "ゖ", "ゝ", "ゞ", "・"
    ]
    // ローンワード的な読みの指標(長音・小書き母音)。これらを含む読みはカタカナ表記が
    // 妥当なので、カタカナ素通りを減点しない(例: らんてぃーゆ→ランティーユ は許容)。
    static let multiClauseLoanwordMarkers: Set<Character> = [
        "ー", "ぁ", "ぃ", "ぅ", "ぇ", "ぉ", "ゎ"
    ]

    // ラティスのノード(1 つの文節候補)。同じ span でも表層ごとに別ノードを立て、bigram の
    // 文脈(直前の表層)を DP でつなぐ。
    struct MultiClauseNode {
        let start: Int
        let end: Int
        let surface: String
        let reading: String
        let isDictWord: Bool   // 辞書/変換で得た語(true) or かな素通り(false)
        let isCurated: Bool    // 追加語彙/学習語彙(void.plist 等の手動キュレーション or 学習)由来
        let isInflectionDerived: Bool  // (b2) 活用エンジン供給ノード(買った/断線しやすい 等)
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
        // 追加語彙(void.plist 等の手動キュレーション)と学習語彙。どちらもユーザ意図なので優遇する。
        let initialUserDictionary = store.initialUserDictionary()
        let learnedDictionary = store.learnedDictionary()
        let manualUserDictionary = store.userDictionary()

        // --- 1. ラティスのノード列挙 ---
        var nodes: [MultiClauseNode] = []
        var nodesEndingAt: [[Int]] = Array(repeating: [], count: n + 1)
        var nodesStartingAt: [[Int]] = Array(repeating: [], count: n)

        for start in 0..<n {
            let maxLen = min(Self.multiClauseMaxSegmentReadingCount, n - start)
            for len in 1...maxLen {
                let end = start + len
                let segmentReading = String(chars[start..<end])
                let suppressed = suppressedByReading[segmentReading]

                var surfaces: [(surface: String, isDictWord: Bool, isCurated: Bool, isInflectionDerived: Bool)] = []
                var seenSurfaces = Set<String>()
                func add(
                    _ surface: String,
                    isDictWord: Bool,
                    isCurated: Bool,
                    exemptDecorative: Bool = false,
                    isInflectionDerived: Bool = false
                ) {
                    if let suppressed, suppressed.contains(surface) {
                        return
                    }
                    if !exemptDecorative, Self.isDecorativeVariantSurface(surface, reading: segmentReading) {
                        return
                    }
                    if seenSurfaces.insert(surface).inserted {
                        surfaces.append((surface, isDictWord, isCurated, isInflectionDerived))
                    }
                }

                // (a) 追加語彙/学習語彙(curated)を常に列挙する。分割・素通りに確実に勝たせるため。
                //     ただし surface==読み(かな識別=変換でない)は優遇しない。過去にかな確定を
                //     学習してしまった履歴が最安の単スパンになり変換をブロックするのを防ぐ。
                //     追加語彙はユーザ明示登録なので装飾フィルタも免除(あ・うん 等の実在固有名)。
                for surface in initialUserDictionary[segmentReading] ?? [] where surface != segmentReading {
                    add(surface, isDictWord: true, isCurated: true, exemptDecorative: true)
                }
                for surface in learnedDictionary[segmentReading] ?? [] where surface != segmentReading {
                    add(surface, isDictWord: true, isCurated: true)
                }

                // (b) word_costs(Sudachi 由来)から top-K を列挙。抑制語彙は除外。
                //     促音「っ」で終わる読みは日本語の語として自立しない断片(かっ/きっ 等)で、
                //     Sudachi の複合語内読み(核=カッ 等)由来の漢字ノードがジャンク合成
                //     (いきだけかったぜ→行きだけ核たぜ)を作るため、漢字含み表層は弾く。
                let segmentEndsWithSokuon = segmentReading.hasSuffix("っ")
                let costMap = store.wordCosts(for: segmentReading)
                if !costMap.isEmpty {
                    let ordered = costMap.sorted { lhs, rhs in
                        lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key < rhs.key
                    }
                    var dictCount = 0
                    for (surface, _) in ordered {
                        if segmentEndsWithSokuon, containsKanji(surface) {
                            continue
                        }
                        add(surface, isDictWord: true, isCurated: false)
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
                if len >= 2,
                    len <= Self.multiClauseInflectionMaxSegmentReadingCount,
                    let lastChar = segmentReading.last,
                    Self.inflectionRuleSuffixLastCharacters.contains(lastChar) {
                    let inflected = inflectionCandidates(
                        for: segmentReading,
                        userDictionary: manualUserDictionary,
                        initialUserDictionary: initialUserDictionary,
                        systemCandidateMode: systemCandidateMode,
                        limit: Self.multiClauseInflectionTopK
                    )
                    for surface in inflected.prefix(Self.multiClauseInflectionTopK)
                    where surface != segmentReading {
                        add(surface, isDictWord: true, isCurated: false, isInflectionDerived: true)
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

                for (surface, isDictWord, isCurated, isInflectionDerived) in surfaces {
                    let index = nodes.count
                    nodes.append(MultiClauseNode(
                        start: start,
                        end: end,
                        surface: surface,
                        reading: segmentReading,
                        isDictWord: isDictWord,
                        isCurated: isCurated,
                        isInflectionDerived: isInflectionDerived
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
                    for curIdx in nodesStartingAt[boundary] {
                        addPair(nodes[prevIdx].surface, nodes[curIdx].surface)
                    }
                }
            }
        }
        for idx in nodesEndingAt[n] {
            addPair(nodes[idx].surface, Self.multiClauseEOSMarker)
        }
        let bigramCosts = store.wordLMBigramCosts(for: bigramPairs)

        // --- 3. コスト関数(sim_lm.py と一致): bigram / unigram+backoff / 辞書OOV / 素通りper-char ---
        func transitionCost(
            prev: String,
            surface: String,
            reading: String,
            isDictWord: Bool,
            isCurated: Bool,
            isInflectionDerived: Bool
        ) -> Int {
            var base: Int
            if let bigram = bigramCosts["\(prev)\t\(surface)"] {
                base = bigram
            } else if let unigram = unigramCosts[surface] {
                base = unigram + Self.multiClauseBackoffCost
            } else if isInflectionDerived {
                base = Self.multiClauseInflectionDerivedOOVCost
            } else if isDictWord {
                base = Self.multiClauseDictUnknownCost
            } else {
                base = Self.multiClausePassthroughPerCharCost * reading.count
            }
            // 追加語彙/学習語彙は強い下限で優遇(自然な LM コストがより安ければそちらを尊重)。
            // ただし絵文字/記号のみの表層(void の €/🇮🇳/₿ 等)は本文へ割り込ませないため優遇せず、
            // 列挙のみ(単文節候補としては到達可)。語形(かな/漢字/ラテン字を含む)だけ強化する。
            if isCurated, Self.isWordLikeSurface(surface) {
                base = min(base, Self.multiClauseCuratedWordCost)
            }
            var penalty = 0
            if Self.isKatakanaString(surface), !readingLooksLikeLoanword(reading) {
                penalty += Self.multiClauseKatakanaNativeCost
            }
            if reading.count > 1, reading.contains("を") {
                penalty += Self.multiClauseForbiddenPenaltyCost
            }
            if let first = reading.first, Self.multiClauseForbiddenInitials.contains(first) {
                penalty += Self.multiClauseForbiddenPenaltyCost
            }
            // 促音「っ」で終わる読みの文節(かっ/カッ 等)は日本語の自立語として成立しない断片。
            // LM コーパスが活用形を A単位(買っ+た)で分割する影響で断片チェーンが不当に安く
            // なり、正しい活用ノード(買った 7600)を阻むため強く減点する。
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
                if node.start == 0 {
                    let cost = transitionCost(
                        prev: Self.multiClauseBOSMarker,
                        surface: node.surface,
                        reading: node.reading,
                        isDictWord: node.isDictWord,
                        isCurated: node.isCurated,
                        isInflectionDerived: node.isInflectionDerived
                    )
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
                    let cost = prevCost + transitionCost(
                        prev: nodes[prevIdx].surface,
                        surface: node.surface,
                        reading: node.reading,
                        isDictWord: node.isDictWord,
                        isCurated: node.isCurated,
                        isInflectionDerived: node.isInflectionDerived
                    )
                    if cost < best[idx] {
                        best[idx] = cost
                        backPointer[idx] = prevIdx
                    }
                }
            }
        }

        // --- 5. EOS 込みで最良の終端ノードを選ぶ ---
        var bestTotal = infinity
        var bestEndIndex = -1
        for idx in nodesEndingAt[n] {
            if best[idx] >= infinity {
                continue
            }
            var total = best[idx] + transitionCost(
                prev: nodes[idx].surface,
                surface: Self.multiClauseEOSMarker,
                reading: "",
                isDictWord: true,
                isCurated: false,
                isInflectionDerived: false
            )
            // 文末が終助詞クラスタ読み(かな/かも 等)なのに漢字表層(仮名/哉/鴨)なのは不自然。
            if Self.multiClauseFinalParticleReadings.contains(nodes[idx].reading),
                nodes[idx].surface != nodes[idx].reading,
                !nodes[idx].isCurated {
                total += Self.multiClauseFinalParticleKanjiPenalty
            }
            if total < bestTotal {
                bestTotal = total
                bestEndIndex = idx
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

        let segments = pathIndices.map { nodes[$0].surface }
        let joined = segments.joined()
        if joined == normalized {
            return []
        }

        // --- 7. Nベスト風バリアント: 最良経路の1文節だけを同区間の別表層に差し替えた変種を
        //        コスト差の小さい順に付ける。bigram が拮抗する読み(しかくとらないと→
        //        視覚/資格/四角…)で第2候補以降を提示するため。1文字区間(助詞等)は対象外。
        var variants: [(delta: Int, joined: String)] = []
        for (pos, nodeIdx) in pathIndices.enumerated() {
            let chosen = nodes[nodeIdx]
            guard chosen.reading.count >= 2 else {
                continue
            }
            let prevSurface = pos > 0 ? nodes[pathIndices[pos - 1]].surface : Self.multiClauseBOSMarker
            let nextNode: MultiClauseNode? = pos + 1 < pathIndices.count ? nodes[pathIndices[pos + 1]] : nil

            func pairCost(_ node: MultiClauseNode) -> Int {
                let incoming = transitionCost(
                    prev: prevSurface,
                    surface: node.surface,
                    reading: node.reading,
                    isDictWord: node.isDictWord,
                    isCurated: node.isCurated,
                    isInflectionDerived: node.isInflectionDerived
                )
                let outgoing: Int
                if let nextNode {
                    outgoing = transitionCost(
                        prev: node.surface,
                        surface: nextNode.surface,
                        reading: nextNode.reading,
                        isDictWord: nextNode.isDictWord,
                        isCurated: nextNode.isCurated,
                        isInflectionDerived: nextNode.isInflectionDerived
                    )
                } else {
                    outgoing = transitionCost(
                        prev: node.surface,
                        surface: Self.multiClauseEOSMarker,
                        reading: "",
                        isDictWord: true,
                        isCurated: false,
                        isInflectionDerived: false
                    )
                }
                return incoming + outgoing
            }

            let baseCost = pairCost(chosen)
            for altIdx in nodesStartingAt[chosen.start] {
                let alt = nodes[altIdx]
                guard alt.end == chosen.end,
                    alt.surface != chosen.surface else {
                    continue
                }
                let delta = pairCost(alt) - baseCost
                guard delta <= Self.multiClauseVariantMaxDelta else {
                    continue
                }
                var altSegments = segments
                altSegments[pos] = alt.surface
                let variantJoined = altSegments.joined()
                if variantJoined == normalized || variantJoined == joined {
                    continue
                }
                variants.append((delta, variantJoined))
            }
        }

        variants.sort { lhs, rhs in
            lhs.delta != rhs.delta ? lhs.delta < rhs.delta : lhs.joined < rhs.joined
        }
        var results = [joined]
        for variant in variants where !results.contains(variant.joined) {
            results.append(variant.joined)
            if results.count >= 1 + Self.multiClauseVariantLimit {
                break
            }
        }
        return results
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
