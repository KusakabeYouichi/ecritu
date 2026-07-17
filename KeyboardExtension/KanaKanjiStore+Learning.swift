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

        var dictionary = learnedDictionary()
        var candidates = dictionary[normalizedReading] ?? []

        if let existingIndex = candidates.firstIndex(of: trimmedCandidate) {
            candidates.remove(at: existingIndex)
        }

        candidates.insert(trimmedCandidate, at: 0)
        dictionary[normalizedReading] = Array(candidates.prefix(32))
        withCacheLock { cachedLearnedDictionary = dictionary }
        saveLearnedDictionary(dictionary)
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

        if let encoded = try? JSONEncoder().encode(scores) {
            defaults.set(encoded, forKey: KanaKanjiStorageKeys.learningScores)
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

        var scores = learningScores()
        let key = learningKey(reading: normalizedReading, candidate: trimmedCandidate)
        scores[key, default: 0] += 1
        withCacheLock {
            cachedLearningScores = scores

            if var indexedScores = cachedLearningScoresByReading {
                var candidateScores = indexedScores[normalizedReading] ?? [:]
                candidateScores[trimmedCandidate] = scores[key, default: 0]
                indexedScores[normalizedReading] = candidateScores
                cachedLearningScoresByReading = indexedScores
            }
        }

        guard let defaults,
                let encoded = try? JSONEncoder().encode(scores) else {
            return
        }

        defaults.set(encoded, forKey: KanaKanjiStorageKeys.learningScores)
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
