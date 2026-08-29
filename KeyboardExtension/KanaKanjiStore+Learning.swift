import Foundation

// 学習語彙(手動追加=追加語彙 / 自動学習=学習語彙)の読み書きと学習スコア。
// UserDefaults 上の ÉcrituAjoutVocab / 学習辞書 / 学習スコアを更新・集計する。
extension KanaKanjiStore {
    func addUserEntry(reading: String, candidate: String) {
        let normalizedReading = KanaTextNormalizer.normalizedReading(reading)
        let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedReading.isEmpty,
                !trimmedCandidate.isEmpty else {
            return
        }

        var dictionary = userDictionary()
        var candidates = dictionary[normalizedReading] ?? []

        if let existingIndex = candidates.firstIndex(of: trimmedCandidate) {
            candidates.remove(at: existingIndex)
        }

        candidates.insert(trimmedCandidate, at: 0)
        dictionary[normalizedReading] = Array(candidates.prefix(32))
        withCacheLock { cachedUserDictionary = dictionary }
        saveUserDictionary(dictionary)
    }

    func addLearnedEntry(reading: String, candidate: String, allowKanaIdentity: Bool = false) {
        let normalizedReading = KanaTextNormalizer.normalizedReading(reading)
        let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedReading.isEmpty,
                !trimmedCandidate.isEmpty else {
            return
        }

        // かな識別(候補==読み)は原則学習しない(全経路での最終防波堤)。学習すると連文節DP
        // で最安の素通り単スパンになり、その読みが変換不能になる。例外はかな候補チップの
        // 明示タップ(allowKanaIdentity)かつ単語相当の短い読みのみ。
        if trimmedCandidate == normalizedReading {
            guard allowKanaIdentity,
                normalizedReading.count <= Self.kanaIdentityLearnableMaxReadingCount else {
                return
            }
        }

        _ = learnedDictionary()   // キャッシュを確実にロード(ロックの外で)
        // キャッシュをその場で更新する(2715)。以前は learnedDictionary() の戻り値(コピー)を
        // 変更していたため、コピーオンライトで確定ごとに学習辞書全体が新しいブロックへ複製され、
        // 変換の一時確保と同じページに置き直されていた(半端ページの温床)。
        withCacheLock {
            var candidates = cachedLearnedDictionary?[normalizedReading] ?? []
            if let existingIndex = candidates.firstIndex(of: trimmedCandidate) {
                candidates.remove(at: existingIndex)
            }
            candidates.insert(trimmedCandidate, at: 0)
            cachedLearnedDictionary?[normalizedReading] = Array(candidates.prefix(32))
            learningPersistDirtyLearned = true
        }
        // 永続化は数秒のデバウンスでまとめて1回(確定ごとの全量 JSON 化をやめる)。変換は
        // メモリ内キャッシュを見るため即時に反映される。
        scheduleLearningPersist()
    }

    static let learningPersistDebounceInterval: TimeInterval = 2.0

    func scheduleLearningPersist() {
        let alreadyScheduled: Bool = withCacheLock { learningPersistWorkItem != nil }
        guard !alreadyScheduled else {
            return
        }
        let work = DispatchWorkItem { [weak self] in
            self?.persistDirtyLearningNow()
        }
        withCacheLock { learningPersistWorkItem = work }
        learningPersistQueue.asyncAfter(deadline: .now() + Self.learningPersistDebounceInterval, execute: work)
    }

    // dirty な学習データのスナップショットを1回だけ取り、JSON 化して defaults に書く。
    // 呼び出し元: デバウンスの発火、キャッシュ破棄前(clearSharedDataCaches)、テストの待機。
    func persistDirtyLearningNow() {
        let (learned, scores): ([String: [String]]?, [String: Int]?) = withCacheLock {
            learningPersistWorkItem?.cancel()
            learningPersistWorkItem = nil
            let l = learningPersistDirtyLearned ? cachedLearnedDictionary : nil
            let s = learningPersistDirtyScores ? cachedLearningScores : nil
            learningPersistDirtyLearned = false
            learningPersistDirtyScores = false
            return (l, s)
        }
        if let learned {
            saveLearnedDictionary(learned)
        }
        if let scores, let defaults,
            let encoded = try? JSONEncoder().encode(scores) {
            defaults.set(encoded, forKey: KanaKanjiStorageKeys.learningScores)
        }
    }

    func flushPendingLearningPersists() {
        persistDirtyLearningNow()
    }

    // テスト用: 学習永続化の完了を待つ(フレッシュな store で defaults を読む前に呼ぶ)。
    // デバウンス待ちの分も即時に書き出す。
    func waitForPendingLearningPersists() {
        persistDirtyLearningNow()
        learningPersistQueue.sync {}
    }

    func learningScores() -> [String: Int] {
        if let cached = withCacheLock({ cachedLearningScores }) {
            return cached
        }

        guard let defaults,
                let learningData = defaults.data(forKey: KanaKanjiStorageKeys.learningScores),
                let decoded = try? JSONDecoder().decode([String: Int].self, from: learningData) else {
            withCacheLock {
                cachedLearningScores = Self.initialLearningScores
                cachedLearningScoresByReading = nil
            }
            return Self.initialLearningScores
        }

        var scores = decoded

        // Ensure rare candidates stay at the very bottom even when old learning data exists.
        for (key, value) in Self.initialLearningScores {
            if let existing = scores[key] {
                scores[key] = min(existing, value)
            } else {
                scores[key] = value
            }
        }

        withCacheLock {
            cachedLearningScores = scores
            cachedLearningScoresByReading = nil
        }

        // 正規化後の書き戻しは初回変換経路でも走るため非同期にする。
        learningPersistQueue.async {
            if let encoded = try? JSONEncoder().encode(scores) {
                defaults.set(encoded, forKey: KanaKanjiStorageKeys.learningScores)
            }
        }

        return scores
    }

    func learningScores(for reading: String) -> [String: Int] {
        let normalizedReading = KanaTextNormalizer.normalizedReading(reading)

        guard !normalizedReading.isEmpty else {
            return [:]
        }

        return learningScoresByReading()[normalizedReading] ?? [:]
    }

    func incrementLearning(reading: String, candidate: String) {
        let normalizedReading = KanaTextNormalizer.normalizedReading(reading)
        let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedReading.isEmpty,
                !trimmedCandidate.isEmpty else {
            return
        }

        _ = learningScores()   // キャッシュを確実にロード(ロックの外で)
        let key = learningKey(reading: normalizedReading, candidate: trimmedCandidate)
        // スコア表と読み別インデックスもその場で更新(2715。全量コピーをやめる)
        withCacheLock {
            cachedLearningScores?[key, default: 0] += 1
            let newScore = cachedLearningScores?[key] ?? 1
            if cachedLearningScoresByReading != nil {
                cachedLearningScoresByReading?[normalizedReading, default: [:]][trimmedCandidate] = newScore
            }
            learningPersistDirtyScores = true
        }
        scheduleLearningPersist()
    }

    func saveUserDictionary(_ dictionary: [String: [String]]) {
        guard let defaults,
                let encoded = try? JSONEncoder().encode(dictionary) else {
            return
        }

        defaults.set(encoded, forKey: KanaKanjiStorageKeys.userDictionary)
    }

    func saveLearnedDictionary(_ dictionary: [String: [String]]) {
        guard let defaults,
                let encoded = try? JSONEncoder().encode(dictionary) else {
            return
        }

        defaults.set(encoded, forKey: KanaKanjiStorageKeys.learnedDictionary)
    }

    func learningKey(reading: String, candidate: String) -> String {
        reading + "\t" + candidate
    }

    func learningScoresByReading() -> [String: [String: Int]] {
        if let cached = withCacheLock({ cachedLearningScoresByReading }) {
            return cached
        }

        // learningScores() 自身が cacheLock を取る(非再帰ロック)ため、ロックの外で呼ぶ。
        let scores = learningScores()
        var indexedScores: [String: [String: Int]] = [:]

        for (key, score) in scores {
            guard let parsed = parseLearningKey(key) else {
                continue
            }

            var candidateScores = indexedScores[parsed.reading] ?? [:]
            candidateScores[parsed.candidate] = score
            indexedScores[parsed.reading] = candidateScores
        }

        withCacheLock { cachedLearningScoresByReading = indexedScores }
        return indexedScores
    }

    func parseLearningKey(_ key: String) -> (reading: String, candidate: String)? {
        guard let separatorIndex = key.firstIndex(of: "\t") else {
            return nil
        }

        let reading = String(key[..<separatorIndex])
        let candidateStartIndex = key.index(after: separatorIndex)
        let candidate = String(key[candidateStartIndex...])

        guard !reading.isEmpty,
                !candidate.isEmpty else {
            return nil
        }

        return (reading, candidate)
    }
}
