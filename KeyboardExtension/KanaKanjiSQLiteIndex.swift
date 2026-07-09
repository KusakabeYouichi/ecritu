import Foundation
import SQLite3

// かな漢字辞書の SQLite 低レベルアクセス層。DB接続・プリペアドステートメントの管理と、
// 候補/活用/語コスト/単語LM(unigram/bigram)の問い合わせを担う。上位の意味処理は
// KanaKanjiStore が担当する。
private let sqliteTransientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class KanaKanjiSQLiteIndex {
    private let queryQueue = DispatchQueue(label: "com.kusakabe.ecritu.kana-kanji.sqlite-index")
    private var database: OpaquePointer?
    private var selectCandidatesStatement: OpaquePointer?
    private var selectCandidatesBySourceStatement: OpaquePointer?
    private var selectCandidatesWithExactSourceStatement: OpaquePointer?
    private var selectInflectionStatement: OpaquePointer?
    private var selectWordCostStatement: OpaquePointer?
    private var selectWordLMUnigramStatement: OpaquePointer?
    private var selectWordLMBigramStatement: OpaquePointer?
    private(set) var hasSourceMetadata = false
    private(set) var hasInflectionMetadata = false
    private(set) var hasWordCostMetadata = false
    private(set) var hasWordLMMetadata = false
    private(set) var hasAnyEntries = false

    init?(databaseURL: URL) {
        var openedDatabase: OpaquePointer?
        let openResult = databaseURL.path.withCString { pathCString in
            sqlite3_open_v2(
                pathCString,
                &openedDatabase,
                SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
                nil
            )
        }

        guard openResult == SQLITE_OK,
            let openedDatabase else {
            if let openedDatabase {
                sqlite3_close(openedDatabase)
            }
            return nil
        }

        database = openedDatabase

        guard let candidateStatement = prepareStatement(
            sql: "SELECT candidate FROM dictionary_entries WHERE reading = ? ORDER BY rank ASC"
        ) else {
            return nil
        }
        selectCandidatesStatement = candidateStatement

        hasSourceMetadata = tableExists("candidate_sources")
        if hasSourceMetadata {
            selectCandidatesBySourceStatement = prepareStatement(
                sql: "SELECT e.candidate FROM dictionary_entries e WHERE e.reading = ? AND (NOT EXISTS (SELECT 1 FROM candidate_sources s_any WHERE s_any.reading = e.reading AND s_any.candidate = e.candidate) OR EXISTS (SELECT 1 FROM candidate_sources s WHERE s.reading = e.reading AND s.candidate = e.candidate AND s.source = ?)) ORDER BY e.rank ASC"
            )
            selectCandidatesWithExactSourceStatement = prepareStatement(
                sql: "SELECT e.candidate FROM dictionary_entries e INNER JOIN candidate_sources s ON s.reading = e.reading AND s.candidate = e.candidate WHERE e.reading = ? AND s.source = ? ORDER BY e.rank ASC"
            )
        }

        hasInflectionMetadata = tableExists("inflection_classes")
        if hasInflectionMetadata {
            selectInflectionStatement = prepareStatement(
                sql: "SELECT candidate, inflection_class FROM inflection_classes WHERE reading = ?"
            )
        }

        hasWordCostMetadata = tableExists("word_costs")
        if hasWordCostMetadata {
            selectWordCostStatement = prepareStatement(
                sql: "SELECT candidate, cost FROM word_costs WHERE reading = ?"
            )
        }

        // 連文節変換(案1: 自前単語 n-gram LM)。unigram/bigram の両テーブルが揃って初めて有効。
        hasWordLMMetadata = tableExists("word_lm_unigram") && tableExists("word_lm_bigram")
        if hasWordLMMetadata {
            selectWordLMUnigramStatement = prepareStatement(
                sql: "SELECT cost FROM word_lm_unigram WHERE surface = ?"
            )
            selectWordLMBigramStatement = prepareStatement(
                sql: "SELECT cost FROM word_lm_bigram WHERE prev = ? AND cur = ?"
            )
        }

        if let probeStatement = prepareStatement(
            sql: "SELECT 1 FROM dictionary_entries LIMIT 1"
        ) {
            hasAnyEntries = sqlite3_step(probeStatement) == SQLITE_ROW
            sqlite3_finalize(probeStatement)
        }
    }

    deinit {
        if let selectCandidatesStatement {
            sqlite3_finalize(selectCandidatesStatement)
        }

        if let selectCandidatesBySourceStatement {
            sqlite3_finalize(selectCandidatesBySourceStatement)
        }

        if let selectCandidatesWithExactSourceStatement {
            sqlite3_finalize(selectCandidatesWithExactSourceStatement)
        }

        if let selectInflectionStatement {
            sqlite3_finalize(selectInflectionStatement)
        }

        if let selectWordCostStatement {
            sqlite3_finalize(selectWordCostStatement)
        }

        if let selectWordLMUnigramStatement {
            sqlite3_finalize(selectWordLMUnigramStatement)
        }

        if let selectWordLMBigramStatement {
            sqlite3_finalize(selectWordLMBigramStatement)
        }

        if let database {
            sqlite3_close(database)
        }
    }

    func candidates(for reading: String, requiredSources: Set<String>?) -> [String] {
        queryQueue.sync {
            if let requiredSources,
                requiredSources.count == 1,
                hasSourceMetadata,
                let source = requiredSources.first,
                let statement = selectCandidatesBySourceStatement {
                return fetchCandidates(reading: reading, source: source, statement: statement)
            }

            guard let statement = selectCandidatesStatement else {
                return []
            }

            return fetchCandidates(reading: reading, source: nil, statement: statement)
        }
    }

    func candidates(withExactSource source: String, for reading: String) -> [String] {
        queryQueue.sync {
            guard hasSourceMetadata,
                let statement = selectCandidatesWithExactSourceStatement else {
                return []
            }

            return fetchCandidates(reading: reading, source: source, statement: statement)
        }
    }

    func inflectionClassMap(for reading: String) -> [String: String] {
        queryQueue.sync {
            guard hasInflectionMetadata,
                let statement = selectInflectionStatement else {
                return [:]
            }

            resetStatement(statement)

            let bindResult = reading.withCString { readingCString in
                sqlite3_bind_text(statement, 1, readingCString, -1, sqliteTransientDestructor)
            }

            guard bindResult == SQLITE_OK else {
                return [:]
            }

            var result: [String: String] = [:]

            while sqlite3_step(statement) == SQLITE_ROW {
                guard let candidateCString = sqlite3_column_text(statement, 0),
                    let inflectionClassCString = sqlite3_column_text(statement, 1) else {
                    continue
                }

                let candidate = String(cString: candidateCString)
                let inflectionClass = String(cString: inflectionClassCString)

                guard !candidate.isEmpty,
                    !inflectionClass.isEmpty else {
                    continue
                }

                result[candidate] = inflectionClass
            }

            return result
        }
    }

    func wordCostMap(for reading: String) -> [String: Int] {
        queryQueue.sync {
            guard hasWordCostMetadata,
                let statement = selectWordCostStatement else {
                return [:]
            }

            resetStatement(statement)

            let bindResult = reading.withCString { readingCString in
                sqlite3_bind_text(statement, 1, readingCString, -1, sqliteTransientDestructor)
            }

            guard bindResult == SQLITE_OK else {
                return [:]
            }

            var result: [String: Int] = [:]

            while sqlite3_step(statement) == SQLITE_ROW {
                guard let candidateCString = sqlite3_column_text(statement, 0) else {
                    continue
                }

                let candidate = String(cString: candidateCString)
                guard !candidate.isEmpty else {
                    continue
                }

                result[candidate] = Int(sqlite3_column_int(statement, 1))
            }

            return result
        }
    }

    // 連文節 DP 用: 与えた表層集合の unigram コストをまとめて引く(1 回の sync 内で完結)。
    func wordLMUnigramCosts(for surfaces: [String]) -> [String: Int] {
        queryQueue.sync {
            guard hasWordLMMetadata,
                let statement = selectWordLMUnigramStatement else {
                return [:]
            }

            var result: [String: Int] = [:]
            result.reserveCapacity(surfaces.count)

            for surface in surfaces where result[surface] == nil {
                resetStatement(statement)
                let bindResult = surface.withCString { surfaceCString in
                    sqlite3_bind_text(statement, 1, surfaceCString, -1, sqliteTransientDestructor)
                }
                guard bindResult == SQLITE_OK else {
                    continue
                }
                if sqlite3_step(statement) == SQLITE_ROW {
                    result[surface] = Int(sqlite3_column_int(statement, 0))
                }
            }

            return result
        }
    }

    // 連文節 DP 用: 与えた (prev, cur) 対の bigram コストをまとめて引く。キーは "prev\tcur"。
    func wordLMBigramCosts(for pairs: [(String, String)]) -> [String: Int] {
        queryQueue.sync {
            guard hasWordLMMetadata,
                let statement = selectWordLMBigramStatement else {
                return [:]
            }

            var result: [String: Int] = [:]
            result.reserveCapacity(pairs.count)

            for (prev, cur) in pairs {
                let key = "\(prev)\t\(cur)"
                if result[key] != nil {
                    continue
                }
                resetStatement(statement)
                let prevBind = prev.withCString { prevCString in
                    sqlite3_bind_text(statement, 1, prevCString, -1, sqliteTransientDestructor)
                }
                let curBind = cur.withCString { curCString in
                    sqlite3_bind_text(statement, 2, curCString, -1, sqliteTransientDestructor)
                }
                guard prevBind == SQLITE_OK, curBind == SQLITE_OK else {
                    continue
                }
                if sqlite3_step(statement) == SQLITE_ROW {
                    result[key] = Int(sqlite3_column_int(statement, 0))
                }
            }

            return result
        }
    }

    private func fetchCandidates(
        reading: String,
        source: String?,
        statement: OpaquePointer
    ) -> [String] {
        resetStatement(statement)

        let readingBindResult = reading.withCString { readingCString in
            sqlite3_bind_text(statement, 1, readingCString, -1, sqliteTransientDestructor)
        }

        guard readingBindResult == SQLITE_OK else {
            return []
        }

        if let source {
            let sourceBindResult = source.withCString { sourceCString in
                sqlite3_bind_text(statement, 2, sourceCString, -1, sqliteTransientDestructor)
            }

            guard sourceBindResult == SQLITE_OK else {
                return []
            }
        }

        var results: [String] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let candidateCString = sqlite3_column_text(statement, 0) else {
                continue
            }

            let candidate = String(cString: candidateCString)

            if !candidate.isEmpty {
                results.append(candidate)
            }
        }

        return results
    }

    private func resetStatement(_ statement: OpaquePointer) {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
    }

    private func prepareStatement(sql: String) -> OpaquePointer? {
        guard let database else {
            return nil
        }

        var statement: OpaquePointer?
        let prepareResult = sql.withCString { sqlCString in
            sqlite3_prepare_v2(database, sqlCString, -1, &statement, nil)
        }

        guard prepareResult == SQLITE_OK,
            let statement else {
            return nil
        }

        return statement
    }

    private func tableExists(_ tableName: String) -> Bool {
        guard database != nil,
            let statement = prepareStatement(
                sql: "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1"
            ) else {
            return false
        }

        defer {
            sqlite3_finalize(statement)
        }

        let bindResult = tableName.withCString { tableNameCString in
            sqlite3_bind_text(statement, 1, tableNameCString, -1, sqliteTransientDestructor)
        }

        guard bindResult == SQLITE_OK else {
            return false
        }

        return sqlite3_step(statement) == SQLITE_ROW
    }
}
