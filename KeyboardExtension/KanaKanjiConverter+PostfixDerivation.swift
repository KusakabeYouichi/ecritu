import Foundation

// 後置(postfix)派生: 語幹+助詞/助動詞の素通り合成(quick=キャッシュ利用/BFS=完全)と、
// お/ご 丁寧接頭辞ファミリの派生。
extension KanaKanjiConverter {
    static let politePrefixPassthroughPrefixes: [String] = ["お", "ご"]

    static func honorificOSuruInflectionSuffixes() -> [String] {
        var suffixes = ["する"]
        suffixes.append(contentsOf: KanaKanjiConverter.suruInflectionRules.map(\.readingSuffix))

        var seen = Set<String>()
        var unique: [String] = []

        for suffix in suffixes where !suffix.isEmpty {
            guard seen.insert(suffix).inserted else {
                continue
            }

            unique.append(suffix)
        }

        return unique.sorted {
            if $0.count != $1.count {
                return $0.count > $1.count
            }

            return $0 > $1
        }
    }

    static let honorificONaruInflectionSuffixes: [String] = [
        "になりません",
        "になりました",
        "になります",
        "にならない",
        "になった",
        "になって",
        "になり",
        "になる"
    ]

    static let honorificOSoftRequestSuffixes: [String] = [
        "なきように",
        "なきよう",
        "なく"
    ]

    static let maxPostfixPassthroughDepth = 3

    static func postfixOutputSuffixVariants(for suffix: String) -> [String] {
        var variants = [suffix]

        for replacement in Self.postfixPassthroughPrefixReplacements where suffix.hasPrefix(replacement.from) {
            let tail = String(suffix.dropFirst(replacement.from.count))
            let converted = replacement.to + tail

            if !variants.contains(converted) {
                variants.append(converted)
            }
        }

        return variants
    }

    func quickPostfixCandidatesUsingCachedStem(
        for reading: String,
        limit: Int,
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        guard reading.count >= 2,
                limit > 0 else {
            return []
        }

        // priority: 説明の んだ 系(のだ縮約)を述語らしい語幹に付けた合成は最優先。長語幹優先だけで
        // 並べると きたん(奇譚/忌憚)+だ が きた(来た)+んだ より前に出て、逐次入力でキャッシュに
        // 載った並びがそのまま伝播する(きたんだ→きたんだが)。BFS 側と同じ優先付けにする(2509)
        var weightedDerivedCandidates: [(priority: Int, stemLength: Int, derived: [String])] = []

        for passthrough in Self.postfixPassthroughSuffixes where reading.hasSuffix(passthrough) {
            let stem = String(reading.dropLast(passthrough.count))

            guard !stem.isEmpty else {
                continue
            }

            if Self.explanatorySuffixRequiresPredicateStem(passthrough),
                !Self.isPredicateLikeStemReading(stem) {
                continue
            }

            // 語幹の再利用なので数字接頭は無し(語幹は常にかな)。
            let stemKey = CandidateCacheKey(
                reading: stem,
                limit: limit,
                modeRawValue: systemCandidateMode.rawValue,
                hasDigitPrefix: false
            )

            guard let cachedStemCandidates = stateQueue.sync(execute: { candidateCache[stemKey] }),
                    !cachedStemCandidates.isEmpty else {
                continue
            }

            // 完全一致専用候補(踊り字 等)は語幹合成に載せない。candidates() の結果に
            // 含まれてキャッシュされるため、除外しないと くりかえし+は → 々は 等が漏れる。
            let exactOnly = Set(KanaKanjiSeedDictionary.exactReadingOnlySeed[stem] ?? [])
            let stemCandidates = exactOnly.isEmpty
                ? cachedStemCandidates
                : cachedStemCandidates.filter { !exactOnly.contains($0) }

            guard !stemCandidates.isEmpty else {
                continue
            }

            let nEndingFiltered = filterVerbStemFragmentCandidatesIfNeeded(
                stemCandidates,
                stemReading: stem,
                nextSuffix: passthrough
            )
            let filteredStemCandidates = filterNonVerbalCandidatesForVerbalPostfix(
                nEndingFiltered,
                stemReading: stem,
                nextSuffix: passthrough
            )

            guard !filteredStemCandidates.isEmpty else {
                continue
            }

            let suffixVariants = Self.postfixOutputSuffixVariants(for: passthrough)
            let derived = filteredStemCandidates.flatMap { candidate in
                suffixVariants.map { candidate + $0 }
            }

            guard !derived.isEmpty else {
                continue
            }

            let isPredicateExplanatory = Self.explanatorySuffixRequiresPredicateStem(passthrough)
                && Self.isPredicateLikeStemReading(stem)
            weightedDerivedCandidates.append((
                priority: isPredicateExplanatory ? 1 : 0,
                stemLength: stem.count,
                derived: derived
            ))
        }

        guard !weightedDerivedCandidates.isEmpty else {
            return []
        }

        let prioritized = weightedDerivedCandidates.sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }
            if lhs.stemLength != rhs.stemLength {
                return lhs.stemLength > rhs.stemLength
            }

            return lhs.derived.count > rhs.derived.count
        }

        let merged = prioritized.flatMap(\.derived)

        return Array(uniqueCandidates(from: merged).prefix(limit))

    }

    func postfixPassthroughCandidates(
        for reading: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode,
        limit: Int
    ) -> [String] {
        guard reading.count >= 2,
                limit > 0 else {
            return []
        }

        var derived: [String] = []
        // 説明の んだ 系(のだ縮約)を用言に付けた合成は最優先で前へ。BFS は長い語幹から処理する
        // ため、放置すると きたん(奇譚/忌憚)+だが が きた(来た)+んだが より前に出る。
        // 話し言葉では のだ縮約の方が圧倒的に頻出なので、述語語幹+説明の んだ を先頭群にする(2506)
        var predicateExplanatoryDerived: [String] = []
        // 収穫底値(wc>=10000)のレア語(木反田/三反田 等の名前収穫)を語幹にした合成は後方へ。
        // BFS は長い語幹から処理するため、放置すると 木反田+が が 来た+んだが より前に出る。
        // 候補としては残す(名前+ちゃん 等の正当な合成を失わない。2504)
        var harvestTierDerived: [String] = []
        var queue: [(stem: String, suffix: String, depth: Int)] = [(reading, "", 0)]
        var visited = Set<String>()
        // 語幹に抑制対象(例: これ→凝れ/梱れ の動詞活用、之レ 等)が混じると 凝れは のように
        // 合成されてしまう。合成前に語幹側の抑制を効かせる(candidates() のステージ4は
        // 合成後の これは 表層しか見ないため、ここで別途フィルタする)。
        let suppressedByReading = store.suppressedCandidatesByReading()

        while !queue.isEmpty {
            let current = queue.removeFirst()

            guard current.depth < Self.maxPostfixPassthroughDepth else {
                continue
            }

            for passthrough in Self.postfixPassthroughSuffixes where current.stem.hasSuffix(passthrough) {
                let nextStem = String(current.stem.dropLast(passthrough.count))

                guard !nextStem.isEmpty else {
                    continue
                }

                let nextSuffix = passthrough + current.suffix
                // か+ない の連鎖は漢字語幹には組まない(定義コメント参照。2723)。かな識別
                // (いかなくて 等の全かなエコー)は従来どおり残す
                let kaNaiChainKanaOnly = Self.isImpossibleKaNaiPostfixChain(nextSuffix)
                let visitKey = nextStem + "\u{1}" + nextSuffix

                guard visited.insert(visitKey).inserted else {
                    continue
                }

                let allowAttachment = !Self.explanatorySuffixRequiresPredicateStem(nextSuffix)
                    || Self.isPredicateLikeStemReading(nextStem)

                if allowAttachment {
                    let suppressedStemSurfaces = suppressedByReading[nextStem] ?? []
                    let inflectedStemCandidates = inflectionCandidates(
                        for: nextStem,
                        userDictionary: userDictionary,
                        initialUserDictionary: initialUserDictionary,
                        systemCandidateMode: systemCandidateMode,
                        limit: limit
                    )
                    var stemCandidates = orderedDerivationBaseCandidates(
                        uniqueCandidates(
                            from: candidatesForReading(
                                nextStem,
                                userDictionary: userDictionary,
                                initialUserDictionary: initialUserDictionary,
                                systemCandidateMode: systemCandidateMode
                            ) + inflectedStemCandidates
                        ).filter {
                            !suppressedStemSurfaces.contains($0)
                                && !isKatakanaEmphasisBaseCandidate($0, reading: nextStem)
                        },
                        reading: nextStem
                    )
                    // 説明の んだ/んです は用言の連体形に付く(名詞なら なんだ が必要)。読みが述語形
                    // (きた)でも辞書側は名詞(北/喜多)が先に並ぶため、活用派生の表層(来た/着た)を
                    // 前に出す。名詞側は候補として残す(北んだ 等は後方。2504)
                    if Self.explanatorySuffixRequiresPredicateStem(nextSuffix),
                        !inflectedStemCandidates.isEmpty {
                        // かな識別(語幹==読み)は昇格させない — b2 供給と同じ原則。昇格すると
                        // きたんだが のかな全文一致が 来たんだが を抑えてしまう
                        let promoted = Set(inflectedStemCandidates.filter { $0 != nextStem })
                        stemCandidates = stemCandidates.filter { promoted.contains($0) }
                            + stemCandidates.filter { !promoted.contains($0) }
                        // カ変(きた→来た/きて→来て)は同形の一段(着た/着て)より頻度が高い。
                        // 活用ルールの定義順ではカ変が最後なので、この表層だけ先頭へ寄せる
                        // (族ごと昇格させる案は 服を着ていました を壊した。2504)
                        if let kuruSurface = KanaKanjiConverter.multiClauseKuruFormSurfaces[nextStem],
                            let index = stemCandidates.firstIndex(of: kuruSurface),
                            index > 0 {
                            stemCandidates.remove(at: index)
                            stemCandidates.insert(kuruSurface, at: 0)
                        }
                    }

                    if kaNaiChainKanaOnly {
                        stemCandidates = stemCandidates.filter { $0 == nextStem }
                    }
                    let nEndingFiltered = filterVerbStemFragmentCandidatesIfNeeded(
                        stemCandidates,
                        stemReading: nextStem,
                        nextSuffix: nextSuffix
                    )
                    let filteredStemCandidates = filterNonVerbalCandidatesForVerbalPostfix(
                        nEndingFiltered,
                        stemReading: nextStem,
                        nextSuffix: nextSuffix
                    )

                    let stemWordCosts = store.wordCosts(for: nextStem)
                    let isExplanatorySuffix = Self.explanatorySuffixRequiresPredicateStem(nextSuffix)
                    let inflectedSurfaces = Set(inflectedStemCandidates.filter { $0 != nextStem })
                    for candidate in filteredStemCandidates {
                        let isHarvestTierStem = (stemWordCosts[candidate] ?? 0)
                            >= KanaKanjiConverter.CandidateScore.harvestTierWordCostFloor
                        let isPredicateExplanatory = isExplanatorySuffix
                            && inflectedSurfaces.contains(candidate)
                        for outputSuffix in Self.postfixOutputSuffixVariants(for: nextSuffix) {
                            if isPredicateExplanatory {
                                predicateExplanatoryDerived.append(candidate + outputSuffix)
                            } else if isHarvestTierStem {
                                harvestTierDerived.append(candidate + outputSuffix)
                            } else {
                                derived.append(candidate + outputSuffix)
                            }
                        }
                    }
                }

                queue.append((nextStem, nextSuffix, current.depth + 1))
            }
        }

        return Array(
            uniqueCandidates(from: predicateExplanatoryDerived + derived + harvestTierDerived)
                .prefix(limit)
        )
    }

    func politePrefixPassthroughCandidates(
        for reading: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode,
        limit: Int
    ) -> [String] {
        guard reading.count >= 2,
            limit > 0 else {
            return []
        }

        var derived: [String] = []

        // フル読み自体が「お/ご/御 始まりでない漢字語」(おそい→遅い、おもい→重い 等)を辞書に
        // 持つなら、それは丁寧接頭辞ではなく1語。お+[語幹候補]の総なめ合成(お添い/お沿い/お初位…
        // =おそい の誤分割)を止める。お名前/お仕事(フル語なし)や お金/お店(丸ごと辞書語)は
        // この判定に該当しないため温存される。
        let fullReadingHasStandaloneWord = candidatesForReading(
            reading,
            userDictionary: userDictionary,
            initialUserDictionary: initialUserDictionary,
            systemCandidateMode: systemCandidateMode
        ).contains { candidate in
            guard let firstScalar = candidate.unicodeScalars.first else {
                return false
            }
            if candidate.hasPrefix("お") || candidate.hasPrefix("ご") || candidate.hasPrefix("御") {
                return false
            }
            return (0x4E00...0x9FFF).contains(firstScalar.value)
                || (0x3400...0x4DBF).contains(firstScalar.value)
                || firstScalar.value == 0x3005
        }

        for prefix in Self.politePrefixPassthroughPrefixes where reading.hasPrefix(prefix) {
            let stem = String(reading.dropFirst(prefix.count))

            guard !stem.isEmpty else {
                continue
            }

            derived.append(
                contentsOf: politePrefixSuruCandidates(
                    prefix: prefix,
                    stemReading: stem,
                    userDictionary: userDictionary,
                    initialUserDictionary: initialUserDictionary,
                    systemCandidateMode: systemCandidateMode
                )
            )

            derived.append(
                contentsOf: politePrefixRenyouCandidates(
                    prefix: prefix,
                    stemReading: stem,
                    userDictionary: userDictionary,
                    initialUserDictionary: initialUserDictionary,
                    systemCandidateMode: systemCandidateMode,
                    allowBareRenyou: !fullReadingHasStandaloneWord
                )
            )

            derived.append(
                contentsOf: politePrefixSoftRequestCandidates(
                    prefix: prefix,
                    stemReading: stem,
                    userDictionary: userDictionary,
                    initialUserDictionary: initialUserDictionary,
                    systemCandidateMode: systemCandidateMode
                )
            )

            // お+名詞の素通り合成はフル読みが1語でない時だけ(お名前/お仕事)。おそい→遅い の
            // ように1語なら お+[そい候補]の誤合成を作らない。※お〜する/お〜になる/お〜ください
            // (上の3ブランチ)は接尾辞でゲート済みなので影響しない。
            guard !fullReadingHasStandaloneWord else {
                continue
            }

            let stemCandidates = orderedDerivationBaseCandidates(
                candidatesForReading(
                    stem,
                    userDictionary: userDictionary,
                    initialUserDictionary: initialUserDictionary,
                    systemCandidateMode: systemCandidateMode
                ),
                reading: stem
            )

            guard !stemCandidates.isEmpty else {
                continue
            }

            let metadata = inflectionMetadata(for: stem)
            let userCandidateSet = Set(
                combinedUserCandidates(
                    for: stem,
                    userDictionary: userDictionary
                ) + (initialUserDictionary[stem] ?? [])
            )
            // 収穫底値(wc>=10000)の語=レア人名収穫(皿野/紗良乃 等)に敬語接頭は
            // 付かない。お皿野 が8700定額で立ち、正解の お+皿+の 経路(連文節)を
            // 跨いでいた(おさらのちょっけい→お皿野直径。ユーザ報告 2647)
            let stemWordCosts = store.wordCosts(for: stem)

            for candidate in stemCandidates {
                if let wc = stemWordCosts[candidate],
                    wc >= KanaKanjiConverter.CandidateScore.harvestTierWordCostFloor,
                    !userCandidateSet.contains(candidate),
                    !(KanaKanjiSeedDictionary.seed[stem]?.contains(candidate) ?? false) {
                    continue
                }
                let resolvedClass = resolvedInflectionClass(
                    for: candidate,
                    baseReading: stem,
                    systemClassMap: metadata.classMap,
                    hasSystemMetadata: metadata.hasMetadata,
                    userCandidateSet: userCandidateSet
                )

                guard !shouldSkipPolitePrefixCandidate(
                    prefix,
                    candidate: candidate,
                    resolvedClass: resolvedClass
                ) else {
                    continue
                }

                guard shouldApplyPolitePrefix(prefix, to: candidate) else {
                    continue
                }

                derived.append(prefix + candidate)
            }
        }

        return Array(uniqueCandidates(from: derived).prefix(limit))
    }

    func politePrefixSoftRequestCandidates(
        prefix: String,
        stemReading: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        guard prefix == "お" else {
            return []
        }

        var derived: [String] = []

        for requestSuffix in Self.honorificOSoftRequestSuffixes where stemReading.hasSuffix(requestSuffix) {
            guard let baseStemReading = removingSuffix(stemReading, suffix: requestSuffix),
                !baseStemReading.isEmpty else {
                continue
            }

            derived.append(
                contentsOf: politePrefixDirectStemCandidates(
                    prefix: prefix,
                    stemReading: baseStemReading,
                    trailingSuffix: requestSuffix,
                    userDictionary: userDictionary,
                    initialUserDictionary: initialUserDictionary,
                    systemCandidateMode: systemCandidateMode
                )
            )

            derived.append(
                contentsOf: politePrefixRenyouCandidates(
                    prefix: prefix,
                    trailingSuffix: requestSuffix,
                    renyouReading: baseStemReading,
                    userDictionary: userDictionary,
                    initialUserDictionary: initialUserDictionary,
                    systemCandidateMode: systemCandidateMode
                )
            )
        }

        return uniqueCandidates(from: derived)
    }

    func politePrefixDirectStemCandidates(
        prefix: String,
        stemReading: String,
        trailingSuffix: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        guard !stemReading.isEmpty else {
            return []
        }

        let stemCandidates = orderedDerivationBaseCandidates(
            candidatesForReading(
                stemReading,
                userDictionary: userDictionary,
                initialUserDictionary: initialUserDictionary,
                systemCandidateMode: systemCandidateMode
            ),
            reading: stemReading
        )

        guard !stemCandidates.isEmpty else {
            return []
        }

        let metadata = inflectionMetadata(for: stemReading)
        var derived: [String] = []

        for candidate in stemCandidates {
            let resolvedClass = metadata.classMap[candidate]

            guard !shouldSkipPolitePrefixCandidate(
                prefix,
                candidate: candidate,
                resolvedClass: resolvedClass
            ) else {
                continue
            }

            guard shouldApplyPolitePrefix(prefix, to: candidate) else {
                continue
            }

            derived.append(prefix + candidate + trailingSuffix)
        }

        return uniqueCandidates(from: derived)
    }

    func politePrefixRenyouCandidates(
        prefix: String,
        stemReading: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode,
        allowBareRenyou: Bool = true
    ) -> [String] {
        guard prefix == "お" else {
            return []
        }

        var derived: [String] = []

        // バラの お+連用形(接尾辞なし)は お願い/お知らせ 等の名詞化連用のみ有効で、フル読みが
        // 1語(おそい→遅い)の場合は お添い/お沿い の誤合成になる。allowBareRenyou で抑止する。
        // お〜になる(下の naruSuffix ループ)は接尾辞でゲート済みなので常に許可。
        if allowBareRenyou {
            derived.append(
                contentsOf: politePrefixRenyouCandidates(
                    prefix: prefix,
                    trailingSuffix: "",
                    renyouReading: stemReading,
                    userDictionary: userDictionary,
                    initialUserDictionary: initialUserDictionary,
                    systemCandidateMode: systemCandidateMode
                )
            )
        }

        for naruSuffix in Self.honorificONaruInflectionSuffixes where stemReading.hasSuffix(naruSuffix) {
            guard let renyouReading = removingSuffix(stemReading, suffix: naruSuffix),
                !renyouReading.isEmpty else {
                continue
            }

            derived.append(
                contentsOf: politePrefixRenyouCandidates(
                    prefix: prefix,
                    trailingSuffix: naruSuffix,
                    renyouReading: renyouReading,
                    userDictionary: userDictionary,
                    initialUserDictionary: initialUserDictionary,
                    systemCandidateMode: systemCandidateMode
                )
            )
        }

        return uniqueCandidates(from: derived)
    }

    // 動詞の連用形(漢字)+ 指定接尾を生成する。丁寧接頭辞を伴わない素の連用形派生で、
    // 「連用形+に(目的: 食べに来る/飲みに行く)」や「連用形+ながら」等の供給に使う。
    // politePrefixRenyouCandidates の接頭辞なし版(空 prefix は shouldApplyPolitePrefix を
    // 通らないため別関数にする)。renyouReading=たべ → 食べ+suffix、のみ → 飲み+suffix。
    func verbRenyouPlusSuffixCandidates(
        renyouReading: String,
        trailingSuffix: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        guard !renyouReading.isEmpty else {
            return []
        }
        var derived: [String] = []
        // 一段: 基本形 = 連用形読み + る(食べ→食べる)
        derived.append(contentsOf: verbRenyouStemsWithSuffix(
            baseReading: renyouReading + "る",
            expectedInflectionClass: InflectionClass.ichidan,
            dictionaryEnding: "る",
            renyouEnding: "",
            trailingSuffix: trailingSuffix,
            userDictionary: userDictionary,
            initialUserDictionary: initialUserDictionary,
            systemCandidateMode: systemCandidateMode
        ))
        // 五段: 連用形(i段)→ 基本形(u段)。飲み→飲む、書き→書く
        for pattern in Self.godanPatterns where renyouReading.hasSuffix(pattern.iForm) {
            guard let readingStem = removingSuffix(renyouReading, suffix: pattern.iForm) else {
                continue
            }
            derived.append(contentsOf: verbRenyouStemsWithSuffix(
                baseReading: readingStem + pattern.dictionaryEnding,
                expectedInflectionClass: pattern.inflectionClass,
                dictionaryEnding: pattern.dictionaryEnding,
                renyouEnding: pattern.iForm,
                trailingSuffix: trailingSuffix,
                userDictionary: userDictionary,
                initialUserDictionary: initialUserDictionary,
                systemCandidateMode: systemCandidateMode
            ))
        }
        return uniqueCandidates(from: derived)
    }

    func verbRenyouStemsWithSuffix(
        baseReading: String,
        expectedInflectionClass: String,
        dictionaryEnding: String,
        renyouEnding: String,
        trailingSuffix: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        guard !baseReading.isEmpty, !dictionaryEnding.isEmpty else {
            return []
        }
        let baseCandidates = orderedDerivationBaseCandidates(
            candidatesForReading(
                baseReading,
                userDictionary: userDictionary,
                initialUserDictionary: initialUserDictionary,
                systemCandidateMode: systemCandidateMode
            ),
            reading: baseReading
        )
        guard !baseCandidates.isEmpty else {
            return []
        }
        let metadata = inflectionMetadata(for: baseReading)
        let userCandidateSet = Set(
            combinedUserCandidates(for: baseReading, userDictionary: userDictionary)
                + (initialUserDictionary[baseReading] ?? [])
        )
        var derived: [String] = []
        for candidate in baseCandidates {
            let resolvedClass = resolvedInflectionClass(
                for: candidate,
                baseReading: baseReading,
                systemClassMap: metadata.classMap,
                hasSystemMetadata: metadata.hasMetadata,
                userCandidateSet: userCandidateSet
            )
            guard resolvedClass == expectedInflectionClass,
                candidate.hasSuffix(dictionaryEnding) else {
                continue
            }
            // かな基本形(食べる が かな のまま=辞書に漢字が無い)は連用形もかなになり
            // 素通りと変わらないので除外(漢字連用形のみ供給)。
            let stem = String(candidate.dropLast(dictionaryEnding.count))
            let renyouSurface = stem + renyouEnding
            guard renyouSurface != String(baseReading.dropLast(dictionaryEnding.count)) + renyouEnding else {
                continue
            }
            derived.append(renyouSurface + trailingSuffix)
        }
        return uniqueCandidates(from: derived)
    }

    func politePrefixRenyouCandidates(
        prefix: String,
        trailingSuffix: String,
        renyouReading: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        guard !renyouReading.isEmpty else {
            return []
        }

        var derived: [String] = []

        derived.append(
            contentsOf: politePrefixRenyouCandidates(
                prefix: prefix,
                trailingSuffix: trailingSuffix,
                baseReading: renyouReading + "る",
                expectedInflectionClass: InflectionClass.ichidan,
                dictionaryEnding: "る",
                renyouEnding: "",
                userDictionary: userDictionary,
                initialUserDictionary: initialUserDictionary,
                systemCandidateMode: systemCandidateMode
            )
        )

        for pattern in Self.godanPatterns where renyouReading.hasSuffix(pattern.iForm) {
            guard let readingStem = removingSuffix(renyouReading, suffix: pattern.iForm) else {
                continue
            }

            let baseReading = readingStem + pattern.dictionaryEnding

            derived.append(
                contentsOf: politePrefixRenyouCandidates(
                    prefix: prefix,
                    trailingSuffix: trailingSuffix,
                    baseReading: baseReading,
                    expectedInflectionClass: pattern.inflectionClass,
                    dictionaryEnding: pattern.dictionaryEnding,
                    renyouEnding: pattern.iForm,
                    userDictionary: userDictionary,
                    initialUserDictionary: initialUserDictionary,
                    systemCandidateMode: systemCandidateMode
                )
            )
        }

        return uniqueCandidates(from: derived)
    }

    func politePrefixRenyouCandidates(
        prefix: String,
        trailingSuffix: String,
        baseReading: String,
        expectedInflectionClass: String,
        dictionaryEnding: String,
        renyouEnding: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        guard !baseReading.isEmpty,
            !dictionaryEnding.isEmpty else {
            return []
        }

        let baseCandidates = orderedDerivationBaseCandidates(
            candidatesForReading(
                baseReading,
                userDictionary: userDictionary,
                initialUserDictionary: initialUserDictionary,
                systemCandidateMode: systemCandidateMode
            ),
            reading: baseReading
        )

        guard !baseCandidates.isEmpty else {
            return []
        }

        let metadata = inflectionMetadata(for: baseReading)
        let userCandidateSet = Set(
            combinedUserCandidates(
                for: baseReading,
                userDictionary: userDictionary
            ) + (initialUserDictionary[baseReading] ?? [])
        )
        var derived: [String] = []

        for candidate in baseCandidates {
            let resolvedClass = resolvedInflectionClass(
                for: candidate,
                baseReading: baseReading,
                systemClassMap: metadata.classMap,
                hasSystemMetadata: metadata.hasMetadata,
                userCandidateSet: userCandidateSet
            )

            guard resolvedClass == expectedInflectionClass,
                candidate.hasSuffix(dictionaryEnding) else {
                continue
            }

            let stem = String(candidate.dropLast(dictionaryEnding.count))
            let renyouCandidate = stem + renyouEnding

            guard shouldApplyPolitePrefix(prefix, to: renyouCandidate) else {
                continue
            }

            derived.append(prefix + renyouCandidate + trailingSuffix)
        }

        return uniqueCandidates(from: derived)
    }

    func politePrefixSuruCandidates(
        prefix: String,
        stemReading: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        guard prefix == "お" else {
            return []
        }

        var derived: [String] = []

        for suruSuffix in Self.honorificOSuruInflectionSuffixes() where stemReading.hasSuffix(suruSuffix) {
            // 連用形1文字(い/み 等)の敬語o-suru合成は日本語に無い(お貸しする/お見せする は
            // 連用2文字以上)。一段 居る/射る/鋳る の連用「い」が おいしそー→お射しそー 等の
            // 暴発を作るため、2文字以上に限定する。
            guard let renyouReading = removingSuffix(stemReading, suffix: suruSuffix),
                renyouReading.count >= 2 else {
                continue
            }

            derived.append(
                contentsOf: politePrefixSuruCandidates(
                    prefix: prefix,
                    suruSuffix: suruSuffix,
                    baseReading: renyouReading + "る",
                    expectedInflectionClass: InflectionClass.ichidan,
                    dictionaryEnding: "る",
                    renyouEnding: "",
                    userDictionary: userDictionary,
                    initialUserDictionary: initialUserDictionary,
                    systemCandidateMode: systemCandidateMode
                )
            )

            for pattern in Self.godanPatterns where renyouReading.hasSuffix(pattern.iForm) {
                guard let readingStem = removingSuffix(renyouReading, suffix: pattern.iForm) else {
                    continue
                }

                let baseReading = readingStem + pattern.dictionaryEnding

                derived.append(
                    contentsOf: politePrefixSuruCandidates(
                        prefix: prefix,
                        suruSuffix: suruSuffix,
                        baseReading: baseReading,
                        expectedInflectionClass: pattern.inflectionClass,
                        dictionaryEnding: pattern.dictionaryEnding,
                        renyouEnding: pattern.iForm,
                        userDictionary: userDictionary,
                        initialUserDictionary: initialUserDictionary,
                        systemCandidateMode: systemCandidateMode
                    )
                )
            }
        }

        return uniqueCandidates(from: derived)
    }

    func politePrefixSuruCandidates(
        prefix: String,
        suruSuffix: String,
        baseReading: String,
        expectedInflectionClass: String,
        dictionaryEnding: String,
        renyouEnding: String,
        userDictionary: [String: [String]],
        initialUserDictionary: [String: [String]],
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        guard !baseReading.isEmpty,
            !dictionaryEnding.isEmpty else {
            return []
        }

        let baseCandidates = orderedDerivationBaseCandidates(
            candidatesForReading(
                baseReading,
                userDictionary: userDictionary,
                initialUserDictionary: initialUserDictionary,
                systemCandidateMode: systemCandidateMode
            ),
            reading: baseReading
        )

        guard !baseCandidates.isEmpty else {
            return []
        }

        let metadata = inflectionMetadata(for: baseReading)
        let userCandidateSet = Set(
            combinedUserCandidates(
                for: baseReading,
                userDictionary: userDictionary
            ) + (initialUserDictionary[baseReading] ?? [])
        )
        var derived: [String] = []

        for candidate in baseCandidates {
            let resolvedClass = resolvedInflectionClass(
                for: candidate,
                baseReading: baseReading,
                systemClassMap: metadata.classMap,
                hasSystemMetadata: metadata.hasMetadata,
                userCandidateSet: userCandidateSet
            )

            guard resolvedClass == expectedInflectionClass,
                candidate.hasSuffix(dictionaryEnding) else {
                continue
            }

            let stem = String(candidate.dropLast(dictionaryEnding.count))
            let renyouCandidate = stem + renyouEnding

            guard shouldApplyPolitePrefix(prefix, to: renyouCandidate) else {
                continue
            }

            derived.append(prefix + renyouCandidate + suruSuffix)
        }

        return uniqueCandidates(from: derived)
    }

    func shouldSkipPolitePrefixCandidate(
        _ prefix: String,
        candidate: String,
        resolvedClass: String?
    ) -> Bool {
        guard let resolvedClass else {
            return false
        }

        // Allow honorific-go for sahen nouns like "相談" that may be tagged as suru-capable.
        if prefix == "ご",
            resolvedClass == InflectionClass.suru,
            !candidate.hasSuffix("する") {
            return false
        }

        return true
    }

    func shouldApplyPolitePrefix(_ prefix: String, to candidate: String) -> Bool {
        guard !candidate.hasPrefix(prefix),
            !candidate.hasPrefix("御"),
            let firstScalar = candidate.unicodeScalars.first else {
            return false
        }

        if (0x4E00...0x9FFF).contains(firstScalar.value)
            || (0x3400...0x4DBF).contains(firstScalar.value)
            || firstScalar.value == 0x3005 {
            return true
        }

        return false
    }
}
