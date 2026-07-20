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

        var weightedDerivedCandidates: [(stemLength: Int, derived: [String])] = []

        for passthrough in Self.postfixPassthroughSuffixes where reading.hasSuffix(passthrough) {
            let stem = String(reading.dropLast(passthrough.count))

            guard !stem.isEmpty else {
                continue
            }

            if Self.explanatorySuffixRequiresPredicateStem(passthrough),
                !Self.isPredicateLikeStemReading(stem) {
                continue
            }

            let stemKey = CandidateCacheKey(
                reading: stem,
                limit: limit,
                modeRawValue: systemCandidateMode.rawValue
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

            weightedDerivedCandidates.append((stemLength: stem.count, derived: derived))
        }

        guard !weightedDerivedCandidates.isEmpty else {
            return []
        }

        let prioritized = weightedDerivedCandidates.sorted { lhs, rhs in
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
                let visitKey = nextStem + "\u{1}" + nextSuffix

                guard visited.insert(visitKey).inserted else {
                    continue
                }

                let allowAttachment = !Self.explanatorySuffixRequiresPredicateStem(nextSuffix)
                    || Self.isPredicateLikeStemReading(nextStem)

                if allowAttachment {
                    let suppressedStemSurfaces = suppressedByReading[nextStem] ?? []
                    let stemCandidates = orderedDerivationBaseCandidates(
                        uniqueCandidates(
                            from: candidatesForReading(
                                nextStem,
                                userDictionary: userDictionary,
                                initialUserDictionary: initialUserDictionary,
                                systemCandidateMode: systemCandidateMode
                            ) + inflectionCandidates(
                                for: nextStem,
                                userDictionary: userDictionary,
                                initialUserDictionary: initialUserDictionary,
                                systemCandidateMode: systemCandidateMode,
                                limit: limit
                            )
                        ).filter { !suppressedStemSurfaces.contains($0) },
                        reading: nextStem
                    )

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

                    for candidate in filteredStemCandidates {
                        for outputSuffix in Self.postfixOutputSuffixVariants(for: nextSuffix) {
                            derived.append(candidate + outputSuffix)
                        }
                    }
                }

                queue.append((nextStem, nextSuffix, current.depth + 1))
            }
        }

        return Array(uniqueCandidates(from: derived).prefix(limit))
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
                    systemCandidateMode: systemCandidateMode
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

            for candidate in stemCandidates {
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
        systemCandidateMode: KanaKanjiCandidateSourceMode
    ) -> [String] {
        guard prefix == "お" else {
            return []
        }

        var derived: [String] = []

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
