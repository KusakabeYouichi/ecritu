import Foundation

// 補助語彙(ÉcrituSecondVocab.json)をビルド時に畳んで、コンパクト表の直列化形式(ECCS1)で書き出す(3030)。
//
// 拡張は起動後の初回変換で補助語彙を読むが、JSON を [String: [String]](16,226 読み)へ復元してから
// 畳んでいたため、その一瞬の辞書が malloc アリーナを +8MB 広げて返さなかった(実機の区間計測で確定:
// 「直接候補: 補助語彙の読み込み alloc 28→36」)。連絡先キャッシュ(3020)と同じ処方で、畳む作業を
// ビルド時へ移し、拡張は配列 4 本を作るだけにする。
//
// 正規化・重複排除は拡張側の loadSupplementalSystemDictionary と同じにするため、
// KanaTextNormalizer / SupplementalVocabCompactStore / KanaKanjiTypes(uniquedTrimmedCandidates)を
// 同じソースからいっしょにコンパイルする(tools/refresh_simulator_dictionary_on_build.sh 参照):
//   swiftc tools/build_second_vocab_compact.swift KeyboardExtension/KanaTextNormalizer.swift \
//          KeyboardExtension/SupplementalVocabCompactStore.swift KeyboardExtension/KanaKanjiTypes.swift
// 使い方: <tool> <入力 JSON> <出力 .eccs>
// 複数ファイルを swiftc で結合するので、最上位文は使わず @main に置く

@main
enum BuildSecondVocabCompact {
    static func main() {
        let arguments = CommandLine.arguments
        guard arguments.count == 3 else {
            FileHandle.standardError.write(Data("usage: build_second_vocab_compact <input.json> <output.eccs>\n".utf8))
            exit(2)
        }
        let inputURL = URL(fileURLWithPath: arguments[1])
        let outputURL = URL(fileURLWithPath: arguments[2])

        guard let data = try? Data(contentsOf: inputURL),
            let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            FileHandle.standardError.write(Data("補助語彙 JSON を読めません: \(inputURL.path)\n".utf8))
            exit(1)
        }

        // KanaKanjiStore.normalizeDictionary と同じ手順
        var normalized: [String: [String]] = [:]
        for (reading, candidates) in decoded {
            let normalizedReading = KanaTextNormalizer.normalizedReading(reading)
            guard !normalizedReading.isEmpty else {
                continue
            }
            let merged = (normalized[normalizedReading] ?? []) + candidates
            normalized[normalizedReading] = merged.uniquedTrimmedCandidates()
        }

        let store = SupplementalVocabCompactStore(dictionary: normalized)
        let serialized = store.serializedData()

        // 往復して同一であることを確かめてから書く(形式のずれをビルド時に止める)
        guard let restored = SupplementalVocabCompactStore(serialized: serialized), restored == store else {
            FileHandle.standardError.write(Data("直列化の往復が一致しません\n".utf8))
            exit(1)
        }

        do {
            try serialized.write(to: outputURL, options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("書き出しに失敗: \(error)\n".utf8))
            exit(1)
        }
        print("[dict] 補助語彙を畳みました: \(store.readingCount) 読み, \(serialized.count) バイト → \(outputURL.lastPathComponent)")
    }
}
