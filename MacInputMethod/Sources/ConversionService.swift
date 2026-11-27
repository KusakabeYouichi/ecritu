import EcrituConversion
import EcrituInput
import Foundation

/// 変換エンジンを包み、入力の状態機械(InputSession)へ候補を渡す。
/// 単文節と連文節の合流・提示の整え・後処理は iOS のキーボードと同じ順・同じ引数で行なう
final class ConversionService: ConversionProviding {
    /// 提示する候補の件数(iOS の effectiveKanaPresentationCandidateLimit の通常時)
    private static let presentationLimit = 24
    /// 単文節の候補を取る件数(iOS と同じ: max(提示の件数 × 2, 提示の件数 + 12))
    private static let singleCandidateLimit = max(
        presentationLimit * ExternalCandidateLimits.lookupMultiplier,
        presentationLimit + 12
    )

    /// 結果の覚え書きの件数の上限(超えたら全部捨てる)
    private static let memoLimit = 64

    private struct MemoKey: Hashable {
        let reading: String
        let precedingCharacter: Character?
    }

    private let converter: KanaKanjiConverter
    /// 結果の覚え書き。Backspace・選択中の伸縮・自動確定の判定で同じ読みを引き直すときの重複を省く。learn と設定の変更で全部捨てる
    private var memo: [MemoKey: [String]] = [:]
    /// memo を守る。短い間だけ取る
    private let memoLock = NSLock()
    /// converter(エンジン)を守る。変換 1 回の間ずっと取る
    private let converterLock = NSLock()
    /// 変換の設定の置き場(学習と同じ suite)。suite 名が使えないときは nil で、設定は保存しない
    private let defaults: UserDefaults?
    /// 今の変換の設定。書くときは converterLock と memoLock の両方を取る。読むときはどちらか一方を取っていればよい
    /// (変換の最中は converterLock、設定画面などは memoLock)
    private var currentSettings: ConversionSettings

    /// appGroupID は UserDefaults の suite 名(学習と変換の設定の置き場)。containerDirectory はエンジンが同名の辞書を探す場所
    init(appGroupID: String, containerDirectory: URL) {
        KanaKanjiStore.sharedContainerURLOverride = containerDirectory
        converter = KanaKanjiConverter(store: KanaKanjiStore(appGroupID: appGroupID))
        defaults = UserDefaults(suiteName: appGroupID)
        // 値の無い Mac は現代的初期設定(新規インストールの iOS と同じ値)
        currentSettings = defaults.map(ConversionSettings.init(defaults:)) ?? .contemporary
        currentSettings.apply(to: converter)
    }

    /// 今の変換の設定(どのスレッドからでも読める)
    var settings: ConversionSettings {
        memoLock.lock()
        defer { memoLock.unlock() }
        return currentSettings
    }

    /// 設定を変えてエンジンへ入れ、保存する。覚え書きは前の設定の結果なので捨てる。
    /// 裏で変換している最中なら、それが終わるのを待ってから入れる
    func updateSettings(_ newSettings: ConversionSettings) {
        converterLock.lock()
        defer { converterLock.unlock() }
        newSettings.apply(to: converter)
        memoLock.lock()
        currentSettings = newSettings
        memo.removeAll()
        memoLock.unlock()
        if let defaults {
            newSettings.save(to: defaults)
        }
    }

    func preload() {
        converterLock.lock()
        defer { converterLock.unlock() }
        converter.preloadSystemDictionaryIfNeeded()
        converter.preloadSharedDataCachesIfNeeded()
    }

    /// 起動時の自己検査用: 同梱の sqlite 辞書を開けているか
    var isSystemDictionaryOpen: Bool {
        !converter.store.isSystemDictionaryFallback()
    }

    /// 求め終わるまで待つ。メインスレッド(確定・候補の選択)と裏のスレッド(打鍵のたびのライヴ変換)の両方から呼ばれる
    func candidates(reading: String, precedingText: String) -> [String] {
        let key = MemoKey(reading: reading, precedingCharacter: precedingText.last)
        if let memorized = memorized(key) {
            return memorized
        }
        // エンジンは 1 度に 1 つの変換だけ。裏で同じ読みを求めている最中なら、それを待って覚え書きから返す
        converterLock.lock()
        defer { converterLock.unlock() }
        if let memorized = memorized(key) {
            return memorized
        }
        let result = convert(reading: reading, precedingCharacter: key.precedingCharacter)
        memoLock.lock()
        if memo.count >= Self.memoLimit {
            memo.removeAll()
        }
        memo[key] = result
        memoLock.unlock()
        return result
    }

    /// 覚え書きにあるときだけ返す。エンジンを待たない(打鍵を待たせないため、converterLock は取らない)
    func cachedCandidates(reading: String, precedingText: String) -> [String]? {
        memorized(MemoKey(reading: reading, precedingCharacter: precedingText.last))
    }

    func learn(reading: String, candidate: String) {
        converterLock.lock()
        defer { converterLock.unlock() }
        _ = converter.learn(reading: reading, candidate: candidate)
        memoLock.lock()
        memo.removeAll()
        memoLock.unlock()
    }

    private func memorized(_ key: MemoKey) -> [String]? {
        memoLock.lock()
        defer { memoLock.unlock() }
        return memo[key]
    }

    private func convert(reading: String, precedingCharacter: Character?) -> [String] {
        let merged = mergedCandidates(reading: reading, precedingCharacter: precedingCharacter)
        // iOS と同じ位置(合流の後、提示の整えの前)で提示の件数に切る
        let presented = candidatesForPresentation(
            from: Array(merged.candidates.prefix(Self.presentationLimit)),
            reading: reading,
            multiClauseLeadingKana: merged.multiClauseLeadingKana
        )
        let processed = postProcessed(presented, reading: reading, precedingCharacter: precedingCharacter)

        var seen = Set<String>()
        var result = processed.filter { candidate in
            !Self.containsForbiddenCharacter(candidate) && seen.insert(candidate).inserted
        }
        if !result.contains(reading) {
            result.append(reading)
        }
        return result
    }

    // MARK: - 合流(iOS: KeyboardViewController+CandidatePresentation.swift の kickOffAsyncCandidateGeneration)

    private func mergedCandidates(
        reading: String,
        precedingCharacter: Character?
    ) -> (candidates: [String], multiClauseLeadingKana: Bool) {
        // X.1 かな漢字候補モード。converterLock の中なので、memoLock を取らずに読める
        let sourceMode = currentSettings.candidateSourceMode
        let single = converter.candidates(
            for: reading,
            limit: Self.singleCandidateLimit,
            systemCandidateMode: sourceMode
        )
        var multiClause = converter.multiClauseCandidates(
            for: reading,
            systemCandidateMode: sourceMode,
            precedingCharacter: precedingCharacter
        )
        // 単文節も連文節も空の短い読み(助詞始まりの断片)は、連文節を短い読みで取り直す
        if multiClause.isEmpty, single.isEmpty, reading.count >= 2 {
            multiClause = converter.multiClauseCandidates(
                for: reading,
                systemCandidateMode: sourceMode,
                minReadingCountOverride: 2
            )
        }
        // 連文節エンジンが全かなを最良に選んだか(提示の整えで、かなを先頭に残す根拠になる)
        let multiClauseLeadingKana = multiClause.first == reading
        guard !multiClause.isEmpty else {
            return (single, multiClauseLeadingKana)
        }

        // 連文節の並びを先頭に置き、単文節の 1 位をその直後(例外あり)へ差し込み、残りの単文節を後ろに続ける
        let multiSet = Set(multiClause)
        var merged = multiClause
        let singleBestIsBareKanaEcho = single.first == reading
            && !converter.shouldKeepKanaIdentityLeading(for: reading)
        if let first = single.first, !multiSet.contains(first), !singleBestIsBareKanaEcho {
            let insertionIndex: Int
            if converter.shouldPromoteSingleBestAboveMultiClause(reading: reading, singleBest: first) {
                insertionIndex = 0
            } else if merged.count >= 2, KanaKanjiConverter.keepsSecondAgainstSingleBest(merged[0], merged[1]) {
                insertionIndex = 2
            } else {
                insertionIndex = min(1, merged.count)
            }
            merged.insert(first, at: insertionIndex)
        }
        for candidate in single where !multiSet.contains(candidate) && !merged.contains(candidate) {
            merged.append(candidate)
        }
        return (merged, multiClauseLeadingKana)
    }

    // MARK: - 提示の整え
    // 写しの元: KeyboardExtension/KeyboardViewController+CandidatePresentation.swift:651-743
    // (candidatesForPresentation、kanaKeptAtSeedPositionReadings、kanaKeptAtEnginePositionReadings、isKanaOnlyText)。
    // 次の区切りでパッケージへ移して共有する。Mac では未確定の文字列と読みが同じなので、どちらも reading を使う

    // たこ: 胼胝/胝/胼/腓胝 の次に かな(3749、ユーザ指定)。きが: 起臥/木香 の次に かな(3752、ユーザ指定)
    // うそつく/うそついて/うそついた: 嘘つく の次に かな(3840、ユーザ指定)
    private static let kanaKeptAtSeedPositionReadings: Set<String> = ["かぶ", "ひろし", "しょう", "たこ", "きが", "うそつく", "うそついて", "うそついた"]
    // かなを変換候補の列のエンジンの位置に残す読み(seed の無い連文節の読み。3824、ユーザ指定)
    private static let kanaKeptAtEnginePositionReadings: Set<String> = ["なんでしたっけ", "なんでしたっけね", "なんでしたか"]

    private func candidatesForPresentation(
        from candidates: [String],
        reading: String,
        multiClauseLeadingKana: Bool
    ) -> [String] {
        // どの経路から来ても同じ文字列を二度出さない(先勝ち)
        var seen = Set<String>()
        var candidates = candidates.filter { seen.insert($0).inserted }

        // 「出来る」は「できる」より後ろ
        candidates = SupplementaryCandidateMerger.demotingDekiKanjiBelowKana(candidates)
        // 読みが完全一致するときだけ、指定表層を最後尾へ(ほんと→本当)
        candidates = SupplementaryCandidateMerger.demotingPresentationTailSeed(candidates, reading: reading)
        // 読みが完全一致するときだけ、指定表層をこの順で先頭に並べる(そう→添う,沿う)
        candidates = SupplementaryCandidateMerger.promotingPresentationOrderSeed(candidates, reading: reading)

        guard !reading.isEmpty else {
            return candidates
        }

        // かな識別(候補 == 読み)の扱い: かな正書の根拠がある読みだけ変換候補側に残す
        if let first = candidates.first,
            first == reading,
            Self.isKanaOnlyText(first),
            multiClauseLeadingKana || converter.shouldKeepKanaIdentityLeading(for: reading) {
            return candidates
        }
        // かなを seed の位置に残す読み
        if Self.kanaKeptAtSeedPositionReadings.contains(reading), Self.isKanaOnlyText(reading),
            KanaKanjiSeedDictionary.seed[reading]?.dropFirst().contains(reading) == true {
            return candidates
        }
        // かなをエンジンの位置(2 番め)に残す読み
        if Self.kanaKeptAtEnginePositionReadings.contains(reading), Self.isKanaOnlyText(reading),
            let kanaIndex = candidates.firstIndex(of: reading), kanaIndex <= 2 {
            return candidates
        }
        if converter.shouldKeepKanaIdentityLeading(for: reading) {
            // かな正書の根拠があり、上位 3 位以内に居るかな識別は位置を保つ
            if let kanaIndex = candidates.firstIndex(where: { $0 == reading && Self.isKanaOnlyText($0) }), kanaIndex <= 2 {
                return candidates
            }
            // それより下のかな識別は末尾へ回す(候補としては残す)
            var reordered = candidates.filter { !($0 == reading && Self.isKanaOnlyText($0)) }
            if reordered.count != candidates.count, Self.isKanaOnlyText(reading) {
                reordered.append(reading)
            }
            return reordered
        }

        return candidates.filter { !($0 == reading && Self.isKanaOnlyText($0)) }
    }

    private static func isKanaOnlyText(_ text: String) -> Bool {
        guard !text.isEmpty else {
            return false
        }
        return text.allSatisfy { character in
            KanaTextNormalizer.normalizedKanaCharacter(from: String(character)) != nil
        }
    }

    // MARK: - 後処理(iOS: applyAsyncCandidateGenerationResult と同じ順・同じ引数)

    private func postProcessed(_ candidates: [String], reading: String, precedingCharacter: Character?) -> [String] {
        let converter = converter
        // め終わり読みの『め/目』選好
        let mePreferred = converter.applyMeSuffixPreferences(reading: reading, to: candidates)
        // 助数詞+付属語を先頭候補の直後へ
        let promoted = KanaKanjiConverter.counterKanaTailPromotedCandidates(mePreferred, reading: reading)
        // 直前の確定済みの文字がラテン文字・数字のときの並び
        let boosted = KanaKanjiConverter.digitContextCounterBoostedCandidates(
            KanaKanjiConverter.latinContextPreferredCandidates(
                promoted,
                reading: reading,
                precedingCharacter: precedingCharacter
            ),
            reading: reading,
            precedingCharacter: precedingCharacter,
            suppressedCandidates: converter.store.suppressedCandidatesByReading()[reading] ?? [],
            ordinalMeKanaFirst: !converter.withStateLock { converter.ordinalMeKanjiPreferred },
            tailConversion: { tail in converter.counterTailConversion(tail) },
            isCommonWord: { surface in converter.isCommonWordForCounterBlock(surface) }
        )
        // 助数詞「か」の表記と、活用のかなの表記を設定順に
        let kaOrdered = converter.applyInflectionalKanaVariantPreference(
            reading: reading,
            to: converter.applyKaCounterVariantPreference(
                reading: reading,
                to: boosted,
                precedingCharacter: precedingCharacter
            )
        )
        // 文頭の感動詞はかなを先頭へ
        return KanaKanjiConverter.sentenceInitialInterjectionPromotedCandidates(
            kaOrdered,
            reading: reading,
            precedingCharacter: precedingCharacter
        )
    }

    /// U+FF00...U+FFFD の文字を含むか(入力できない文字。候補ウインドウに出す列から落とす)
    static func containsForbiddenCharacter(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0xFF00...0xFFFD).contains($0.value) }
    }
}
