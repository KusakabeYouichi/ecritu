import Foundation

/// ローマ字をかなに組み立てる。text はかな(規則に当たらなかったラテン文字が混ざり得る)、pending は打ちかけのローマ字(常に末尾)
struct RomajiComposer {
    private(set) var text = ""
    private(set) var pending = ""

    var isEmpty: Bool { text.isEmpty && pending.isEmpty }

    /// 変換できる = text が空でなく、ASCII を 1 字も含まない
    var isConvertible: Bool {
        !text.isEmpty && !text.unicodeScalars.contains { $0.isASCII }
    }

    mutating func input(_ character: Character) {
        let joined = pending + String(character)
        if let kana = Self.table[joined] {
            text += kana
            pending = ""
            return
        }
        if Self.prefixes.contains(joined) {
            pending = joined
            return
        }
        if pending == "n" {
            text += "ん"
            pending = ""
            input(character)
            return
        }
        if pending.count == 1, pending == String(character), Self.isConsonant(character) {
            text += "っ"
            pending = String(character)
            return
        }
        guard let first = pending.first else {
            text.append(character)
            return
        }
        // pending の先頭 1 字をラテン文字のまま移し、残り + 入力を処理し直す
        let rest = pending.dropFirst() + String(character)
        text.append(first)
        pending = ""
        for next in rest {
            input(next)
        }
    }

    /// 1 字削除: pending があれば末尾 1 字、無ければ text の末尾 1 文字
    mutating func deleteBackward() {
        if !pending.isEmpty {
            pending.removeLast()
        } else if !text.isEmpty {
            text.removeLast()
        }
    }

    /// 末尾の n の確定: pending が n ちょうどなら ん にする。ほかの pending は残す
    mutating func flush() {
        if pending == "n" {
            text += "ん"
            pending = ""
        }
    }

    /// text の先頭 count 文字を取り除く(確定した分)
    mutating func removePrefix(_ count: Int) {
        text = String(text.dropFirst(count))
    }

    private static func isConsonant(_ character: Character) -> Bool {
        guard let ascii = character.asciiValue, character.isLetter else { return false }
        return !"aiueon".utf8.contains(ascii)
    }

    /// キー→かな。ヘボン式と訓令式の両方、小書き(x / l 接頭)、外来音
    static let table: [String: String] = {
        var table: [String: String] = [:]
        let vowels = ["a", "i", "u", "e", "o"]
        // 5 母音の行。空文字列の箇所はキーを作らない
        func addRow(_ consonant: String, _ kana: [String]) {
            for (vowel, value) in zip(vowels, kana) where !value.isEmpty {
                table[consonant + vowel] = value
            }
        }
        addRow("", ["あ", "い", "う", "え", "お"])
        addRow("k", ["か", "き", "く", "け", "こ"])
        addRow("g", ["が", "ぎ", "ぐ", "げ", "ご"])
        addRow("s", ["さ", "し", "す", "せ", "そ"])
        addRow("z", ["ざ", "じ", "ず", "ぜ", "ぞ"])
        addRow("t", ["た", "ち", "つ", "て", "と"])
        addRow("d", ["だ", "ぢ", "づ", "で", "ど"])
        addRow("n", ["な", "に", "ぬ", "ね", "の"])
        addRow("h", ["は", "ひ", "ふ", "へ", "ほ"])
        addRow("b", ["ば", "び", "ぶ", "べ", "ぼ"])
        addRow("p", ["ぱ", "ぴ", "ぷ", "ぺ", "ぽ"])
        addRow("m", ["ま", "み", "む", "め", "も"])
        addRow("r", ["ら", "り", "る", "れ", "ろ"])
        addRow("y", ["や", "", "ゆ", "", "よ"])
        addRow("w", ["わ", "うぃ", "", "うぇ", "を"])
        addRow("f", ["ふぁ", "ふぃ", "ふ", "ふぇ", "ふぉ"])
        addRow("v", ["ゔぁ", "ゔぃ", "ゔ", "ゔぇ", "ゔぉ"])
        addRow("j", ["じゃ", "じ", "じゅ", "じぇ", "じょ"])
        addRow("sh", ["しゃ", "し", "しゅ", "しぇ", "しょ"])
        addRow("ch", ["ちゃ", "ち", "ちゅ", "ちぇ", "ちょ"])
        addRow("ts", ["つぁ", "つぃ", "つ", "つぇ", "つぉ"])
        addRow("tch", ["っちゃ", "っち", "っちゅ", "っちぇ", "っちょ"])
        // 拗音: い段 + 小書きの ゃ ぃ ゅ ぇ ょ
        let contracted = ["ゃ", "ぃ", "ゅ", "ぇ", "ょ"]
        let iColumn: [(String, String)] = [
            ("ky", "き"), ("gy", "ぎ"), ("sy", "し"), ("zy", "じ"), ("jy", "じ"), ("ty", "ち"), ("dy", "ぢ"),
            ("ny", "に"), ("hy", "ひ"), ("by", "び"), ("py", "ぴ"), ("my", "み"), ("ry", "り"),
        ]
        for (consonant, base) in iColumn {
            addRow(consonant, contracted.map { base + $0 })
        }
        for prefix in ["x", "l"] {
            addRow(prefix, ["ぁ", "ぃ", "ぅ", "ぇ", "ぉ"])
            table[prefix + "tu"] = "っ"
            table[prefix + "tsu"] = "っ"
            table[prefix + "ya"] = "ゃ"
            table[prefix + "yu"] = "ゅ"
            table[prefix + "yo"] = "ょ"
            table[prefix + "wa"] = "ゎ"
        }
        table["thi"] = "てぃ"
        table["dhi"] = "でぃ"
        table["twu"] = "とぅ"
        table["dwu"] = "どぅ"
        table["kwa"] = "くぁ"
        table["gwa"] = "ぐぁ"
        table["nn"] = "ん"
        table["n'"] = "ん"
        table["-"] = "ー"
        return table
    }()

    /// 表のキーの真の接頭辞(打ちかけとして待つもの)
    private static let prefixes: Set<String> = {
        var prefixes = Set<String>()
        for key in table.keys where key.count > 1 {
            for length in 1..<key.count {
                prefixes.insert(String(key.prefix(length)))
            }
        }
        return prefixes
    }()
}
