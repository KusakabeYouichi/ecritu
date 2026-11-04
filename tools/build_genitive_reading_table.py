#!/usr/bin/env python3
"""辞書の「の込み」読みの表(GenitiveReadingTable.swift)を作る(3678)。

Sudachi には 古代の氏姓・人名・国名を「の」込みの読みで持つ語がある(みなもとの=源、たちばなの=橘/橘ノ、あきの=秋、
いちの=市、いずの=伊豆 …)。橘諸兄(たちばなのもろえ)を 1 語で打つための読みだが、連文節では 秋+の/池+の のような
ふつうの合成を邪魔する(源/平/藤原/阿刀/岡 は suppr+exactReadingOnlySeed の二段構えで個別に止めていた)。
ここで機械的に拾い、変換では同じ二段構えにする: 連文節・合成の部品には使わず、ちょうどその読みを打ったときだけ末尾に出す。

拾う条件(辞書 tmp/kana_kanji_dictionary.sqlite の dictionary_entries):
  ・読みが 3 字以上で「の」で終わる
  ・表記が漢字だけ(の/之/乃/野/廼/能/埜 を含まない)で、の を除いた読みに同じ表記がある → 抑制+末尾に再供給
  ・表記が 漢字だけ+ノ で、ノ を除いた表記が の を除いた読みにある(橘ノ)→ 抑制だけ(末尾に出すのは ノ の無い方)
使い方: python3 tools/build_genitive_reading_table.py   (辞書を作り直したら流してコミットする)
"""
import re
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB = ROOT / "tmp" / "kana_kanji_dictionary.sqlite"
DST = ROOT / "KeyboardExtension" / "GenitiveReadingTable.swift"
KANJI = re.compile(r"^[一-鿿々]+$")
GENITIVE_KANJI = set("之乃野廼能埜")


def swift_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    con = sqlite3.connect(DB)
    rows = con.execute(
        "select reading, candidate from dictionary_entries where reading like '%の' and length(reading) >= 3"
    ).fetchall()
    by_reading = {}
    for reading, candidate in con.execute("select reading, candidate from dictionary_entries"):
        by_reading.setdefault(reading, set()).add(candidate)
    suppressed = {}
    resupplied = {}
    for reading, candidate in rows:
        stem_reading = reading[:-1]
        stem_surfaces = by_reading.get(stem_reading, set())
        if KANJI.match(candidate) and not (set(candidate) & GENITIVE_KANJI) and candidate in stem_surfaces:
            suppressed.setdefault(reading, set()).add(candidate)
            resupplied.setdefault(reading, set()).add(candidate)
        elif candidate.endswith("ノ") and KANJI.match(candidate[:-1]) and candidate[:-1] in stem_surfaces:
            suppressed.setdefault(reading, set()).add(candidate)
    lines = [
        "// このファイルは tools/build_genitive_reading_table.py が生成する。手で直さず、スクリプトを流し直すこと(3678)。",
        "// 辞書の「の込み」読み(みなもとの=源、たちばなの=橘/橘ノ、あきの=秋 …)。変換では抑制し、",
        "// ちょうどその読みを打ったときだけ resupplied の表記を末尾に出す(suppr+exactReadingOnlySeed と同じ二段構え)",
        "",
        "enum GenitiveReadingTable {",
        "    static let suppressed: [String: [String]] = [",
    ]
    for reading in sorted(suppressed):
        values = ", ".join(swift_string(s) for s in sorted(suppressed[reading]))
        lines.append(f"        {swift_string(reading)}: [{values}],")
    lines += ["    ]", "", "    static let resupplied: [String: [String]] = ["]
    for reading in sorted(resupplied):
        values = ", ".join(swift_string(s) for s in sorted(resupplied[reading]))
        lines.append(f"        {swift_string(reading)}: [{values}],")
    lines += ["    ]", "}", ""]
    DST.write_text("\n".join(lines), encoding="utf-8")
    print(f"wrote {DST.relative_to(ROOT)}: 抑制 {sum(len(v) for v in suppressed.values())} 語 / {len(suppressed)} 読み、"
          f"末尾に再供給 {sum(len(v) for v in resupplied.values())} 語")


if __name__ == "__main__":
    main()
