#!/usr/bin/env python3
"""references/vin.plist から Packages/EcrituConversion/Sources/EcrituConversionBase/WineScriptTable.swift を作る。

同じ読みにラテン文字の表記とカタカナの表記の両方があるワインの語(Merlot/メルロー)の一覧。変換の結果で、
ワインの語はカタカナの形をラテン文字の形より先にする(ユーザ指定 3846: 単独・助詞つき・文の中で揃える)ために使う。
vin.plist を直したら、これを実行して表を作り直す。

使い方: python3 tools/build_wine_script_table.py
"""
import collections
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "references" / "vin.plist"
DST = ROOT / "Packages" / "EcrituConversion" / "Sources" / "EcrituConversionBase" / "WineScriptTable.swift"
ENTRY = re.compile(r"<key>phrase</key><string>(.*?)</string><key>shortcut</key><string>(.*?)</string>")
LATIN = re.compile(r"[A-Za-zÀ-ÖØ-öø-ÿĀ-ž]")
KATAKANA = re.compile(r"^[ァ-ヺー・]+$")


def main():
    text = re.sub(r"<!--.*?-->", "", SRC.read_text(encoding="utf-8"), flags=re.S)
    by_reading = collections.OrderedDict()
    for phrase, reading in ENTRY.findall(text):
        latin, katakana = by_reading.setdefault(reading, ([], []))
        if LATIN.search(phrase):
            if phrase not in latin:
                latin.append(phrase)
        elif KATAKANA.match(phrase):
            if phrase not in katakana:
                katakana.append(phrase)
    rows = [(r, l, k) for r, (l, k) in by_reading.items() if l and k]
    rows.sort(key=lambda row: row[0])
    body = "".join(f"    {r}\t{'|'.join(l)}\t{'|'.join(k)}\n" for r, l, k in rows)
    assert '"""' not in body and "\\" not in body
    lines = [
        "import Foundation",
        "",
        "// 生成ファイル。tools/build_wine_script_table.py が references/vin.plist から作る。手で直さない(3846)",
        "// 同じ読みにラテン文字とカタカナの両方の表記があるワインの語。ワインの語はカタカナの形を先にする(ユーザ指定 3846)",
        "public enum WineScriptTable {",
        "    // 読み → (ラテン文字の表記, カタカナの表記)。初めて使うときに下の文字列から作る",
        "    public static let surfacesByReading: [String: (latin: [String], katakana: [String])] = {",
        "        var result: [String: (latin: [String], katakana: [String])] = [:]",
        '        for line in table.split(separator: "\\n") {',
        '            let columns = line.split(separator: "\\t", omittingEmptySubsequences: false)',
        "            guard columns.count == 3 else { continue }",
        '            result[String(columns[0])] = (columns[1].split(separator: "|").map(String.init), columns[2].split(separator: "|").map(String.init))',
        "        }",
        "        return result",
        "    }()",
        "    // 読みの長さの最大(前方一致を試す上限)",
        "    public static let maxReadingCount: Int = surfacesByReading.keys.map(\\.count).max() ?? 0",
        "",
        '    static let table = """',
    ]
    DST.write_text("\n".join(lines) + "\n" + body + '    """\n}\n', encoding="utf-8")
    print(f"wrote {DST.relative_to(ROOT)}: {len(rows)} 読み")


main()
