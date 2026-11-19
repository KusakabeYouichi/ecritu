import Foundation

// ワインの語は、ラテン文字の表記よりカタカナの表記を先にする(ユーザ指定 3846)。単独(めるろー)、助詞つき(めるろーで)、
// 文の中(めるろーです、ぐれーこやありあにこがある)で揃える。以前は 11-16 の『両方の表記がある読みはラテン文字が先』で、
// 単独と助詞 1 つの形は Merlot が先、です や後ろに語が続く形はカタカナが先で、助詞によって入れ替わっていた
// 先頭の候補の中のラテン文字の語のうち、ワインの語(WineScriptTable)をカタカナの表記に替えた形を先頭にし、元の先頭を 2 番めに置く。
// IT の語(TestFlight/Apple)は表に無いので対象外
public enum WineScriptOrdering {
    // ラテン文字の表記 → カタカナの表記(表の順)
    static let katakanaByLatin: [String: [String]] = {
        var result: [String: [String]] = [:]
        // 読みの順にたどる(辞書の順は実行ごとに変わるので、選ばれるカタカナが揺れないように)
        for reading in WineScriptTable.surfacesByReading.keys.sorted() {
            guard let entry = WineScriptTable.surfacesByReading[reading] else { continue }
            for latin in entry.latin {
                result[latin, default: []].append(contentsOf: entry.katakana.filter { !(result[latin]?.contains($0) ?? false) })
            }
        }
        return result
    }()

    static func isLatinRunCharacter(_ character: Character) -> Bool {
        if character == " " || character == "-" || character == "'" || character == "’" || character == "." { return true }
        guard let scalar = character.unicodeScalars.first else { return false }
        return scalar.properties.isAlphabetic && scalar.value < 0x0250
    }

    public static func katakanaFirst(reading: String, candidates: [String]) -> [String] {
        guard let top = candidates.first,
            top.unicodeScalars.contains(where: { $0.properties.isAlphabetic && $0.value < 0x0250 }) else {
            return candidates
        }
        var replaced = ""
        var changed = false
        var run = ""
        func flushRun() {
            guard !run.isEmpty else { return }
            // 前後の空白は語に含めない
            let trimmed = run.trimmingCharacters(in: .whitespaces)
            // 言語を名指しした直後(フランス語ではPleurs/英語でLeaf growth)は、その言語の綴りを示しているのでラテン文字のまま
            let namesLanguage = ["語で", "語では", "語の", "語だと", "語は"].contains(where: { replaced.hasSuffix($0) })
            // カタカナの表記が複数あるとき(グリューナー・ヴェルトリーナー/フェルトリーナー)は、候補の中に出ているものを選ぶ
            if !namesLanguage, let options = katakanaByLatin[trimmed], let first = options.first {
                // 候補に出ているものが複数なら長いほう(メルロ と メルロー なら メルロー。メルロ は メルロー の一部にも当たるため)
                let katakana = options.filter { option in candidates.contains { $0.contains(option) } }
                    .max(by: { $0.count < $1.count }) ?? first
                replaced += run.replacingOccurrences(of: trimmed, with: katakana)
                changed = true
            } else {
                replaced += run
            }
            run = ""
        }
        for character in top {
            if isLatinRunCharacter(character) {
                run.append(character)
            } else {
                flushRun()
                replaced.append(character)
            }
        }
        flushRun()
        guard changed, replaced != top else { return candidates }
        // 替えた後もラテン文字の語が残り(表に無い語。Sonoma は vin.plist にカタカナの ソノマ だけ)、ラテン文字とカタカナの
        // 違いだけの全部カタカナの候補があれば、そちらを先頭にする(ナパでもSonomaでも → ナパでもソノマでも。3846)
        if replaced.unicodeScalars.contains(where: { $0.properties.isAlphabetic && $0.value < 0x0250 }) {
            func skeleton(_ text: String) -> String {
                String(text.filter { !isLatinRunCharacter($0) && !("ァ"..."ヺ").contains($0) && $0 != "ー" && $0 != "・" })
            }
            let target = skeleton(top)
            if let allKatakana = candidates.first(where: { candidate in
                !candidate.unicodeScalars.contains(where: { $0.properties.isAlphabetic && $0.value < 0x0250 })
                    && skeleton(candidate) == target
            }) {
                return [allKatakana, top] + candidates.filter { $0 != allKatakana && $0 != top }
            }
        }
        return [replaced, top] + candidates.filter { $0 != replaced && $0 != top }
    }
}
