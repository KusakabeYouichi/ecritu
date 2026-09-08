import Foundation

// テスト専用の書き込み補助。本番のキーボード拡張は追加語彙を読むだけ(書くのはコンテナーアプリ)なので、
// KanaKanjiStore+Learning.swift から移した(2822)。テストターゲットは拡張のソースを直接コンパイルするため
// internal メンバー(ajoutVocabulary/withCacheLock/learningPersistQueue)に届く
extension KanaKanjiStore {
    func addUserEntry(reading: String, candidate: String) {
        let normalizedReading = KanaTextNormalizer.normalizedReading(reading)
        let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedReading.isEmpty,
                !trimmedCandidate.isEmpty else {
            return
        }

        var dictionary = ajoutVocabulary()
        var candidates = dictionary[normalizedReading] ?? []

        if let existingIndex = candidates.firstIndex(of: trimmedCandidate) {
            candidates.remove(at: existingIndex)
        }

        candidates.insert(trimmedCandidate, at: 0)
        dictionary[normalizedReading] = Array(candidates.prefix(32))
        withCacheLock { cachedAjoutVocabulary = dictionary }
        saveAjoutVocabulary(dictionary)
    }

    func saveAjoutVocabulary(_ dictionary: [String: [String]]) {
        guard let defaults,
                let encoded = try? JSONEncoder().encode(dictionary) else {
            return
        }

        defaults.set(encoded, forKey: KanaKanjiStorageKeys.ajoutVocabulary)
    }

    // 学習永続化の完了を待つ(フレッシュな store で defaults を読む前に呼ぶ)。デバウンス待ちの分も即時に書き出す
    func waitForPendingLearningPersists() {
        persistDirtyLearningNow()
        learningPersistQueue.sync {}
    }
}

extension KanjiRadicalFileIndex {
    var isEmpty: Bool { data.isEmpty }
}
