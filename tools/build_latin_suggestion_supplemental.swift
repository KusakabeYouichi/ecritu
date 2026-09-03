// 補助語彙(ÉcrituSecondVocab.json)から欧文サジェストの索引ファイル LatinSuggestionSupplemental.txt を
// 前計算する(2770)。以前はキーボード起動後に実行時構築していた(補助語彙 15k 件の全走査で
// footprint +8MB の瞬間ピーク、alloc のラチェット成長、fp≥52 での見送りゲートと削除キーの薄ピンク表示)。
// 汎用レキシコン(LatinSuggestionLexicon_{lang}.txt)と同じ形式 key\tcandidate\trank\n で、
// キーの UTF-8 バイト順にソート済み。実行時は Data(mappedIfSafe) のまま GenericLatinLexiconFileIndex で
// 二分探索するので、ロードも検索もヒープを使わない。
//
// フィルタと折り畳みは KanaKanjiStore+LatinSuggestions.swift の実行時判定と同一:
//   mayContainLatinLetterOrDigit → trim → isLatinSuggestionCandidate(正規表現) → 重複除外 →
//   latinSuggestionSearchKey(diacritic/case/width insensitive, fr_FR, lowercased)
// rank は 0 固定(追加語彙側の並びはキー順+同キー内は候補の localizedCaseInsensitiveCompare 順)。
//
// 3 つめ以降の引数は欧文サジェスト専用 plist(references/vin-acronyme.plist)。shortcut を検索キー、
// phrase を候補としてそのまま合流する(キーは phrase から導出しない: 『D.A.C.』を dac で引くため)。
// キーには実行時と同じ折り畳みを掛けるので、plist 側は小文字・ピリオド除去済みでなくても揃う。
//
// 使い方: swift tools/build_latin_suggestion_supplemental.swift <SecondVocab.json> <出力.txt> [<欧文専用.plist>...]
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write("usage: build_latin_suggestion_supplemental.swift <SecondVocab.json> <output.txt> [<latin-only.plist>...]\n".data(using: .utf8)!)
    exit(2)
}

let inputURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])
let latinOnlyPlistURLs = arguments.dropFirst(3).map { URL(fileURLWithPath: $0) }

guard let data = try? Data(contentsOf: inputURL),
    let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: [String]] else {
    FileHandle.standardError.write("failed to read \(inputURL.path)\n".data(using: .utf8)!)
    exit(1)
}

func mayContainLatinLetterOrDigit(_ candidate: String) -> Bool {
    for scalar in candidate.unicodeScalars {
        let value = scalar.value
        if (0x30...0x39).contains(value) || (0x41...0x5A).contains(value)
            || (0x61...0x7A).contains(value) || (0x00C0...0x024F).contains(value) {
            return true
        }
    }
    return false
}

func isLatinSuggestionCandidate(_ candidate: String) -> Bool {
    guard candidate.range(of: #"[\p{Latin}0-9]"#, options: .regularExpression) != nil else {
        return false
    }
    return candidate.range(
        of: #"^[\p{Latin}\p{M}0-9 \-\.&'’/,+:;()!?]+$"#,
        options: .regularExpression
    ) != nil
}

func searchKey(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
        .folding(
            options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
            locale: Locale(identifier: "fr_FR")
        )
        .lowercased()
}

struct Entry {
    let keyBytes: [UInt8]
    let key: String
    let candidate: String
}

var seenCandidates = Set<String>()
var entries: [Entry] = []

// 読み順を固定してから走査し、同じ候補の初出を決定的にする(実行時は辞書順序依存だった)
for reading in dictionary.keys.sorted() {
    for candidate in dictionary[reading] ?? [] {
        guard mayContainLatinLetterOrDigit(candidate) else { continue }
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
            isLatinSuggestionCandidate(trimmed),
            !trimmed.contains("\t"), !trimmed.contains("\n"),
            seenCandidates.insert(trimmed).inserted else {
            continue
        }
        let key = searchKey(trimmed)
        guard !key.isEmpty else { continue }
        entries.append(Entry(keyBytes: Array(key.utf8), key: key, candidate: trimmed))
    }
}

// 欧文専用 plist: shortcut がキー。同じ候補が補助語彙側にあっても(キーが違うので)別行として残す
var seenPairs = Set<String>()
var latinOnlyCount = 0
for plistURL in latinOnlyPlistURLs {
    guard let plistData = try? Data(contentsOf: plistURL),
        let rows = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [[String: Any]] else {
        FileHandle.standardError.write("failed to read \(plistURL.path)\n".data(using: .utf8)!)
        exit(1)
    }
    for row in rows {
        guard let rawShortcut = row["shortcut"] as? String, let rawPhrase = row["phrase"] as? String else { continue }
        let candidate = rawPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = searchKey(rawShortcut)
        guard !candidate.isEmpty, !key.isEmpty else { continue }
        guard isLatinSuggestionCandidate(candidate), !candidate.contains("\t"), !candidate.contains("\n") else {
            FileHandle.standardError.write("[latin-suppl] skip non-latin phrase: \(candidate) (\(plistURL.lastPathComponent))\n".data(using: .utf8)!)
            continue
        }
        guard seenPairs.insert(key + "\t" + candidate).inserted else { continue }
        entries.append(Entry(keyBytes: Array(key.utf8), key: key, candidate: candidate))
        latinOnlyCount += 1
    }
}

entries.sort { lhs, rhs in
    if lhs.keyBytes == rhs.keyBytes {
        return lhs.candidate.localizedCaseInsensitiveCompare(rhs.candidate) == .orderedAscending
    }
    return lhs.keyBytes.lexicographicallyPrecedes(rhs.keyBytes)
}

var output = ""
output.reserveCapacity(entries.count * 32)
for entry in entries {
    output += entry.key
    output += "\t"
    output += entry.candidate
    output += "\t0\n"
}

do {
    try output.write(to: outputURL, atomically: true, encoding: .utf8)
} catch {
    FileHandle.standardError.write("failed to write \(outputURL.path): \(error)\n".data(using: .utf8)!)
    exit(1)
}

print("[latin-suppl] \(entries.count) entries (latin-only plist: \(latinOnlyCount)) -> \(outputURL.path)")
