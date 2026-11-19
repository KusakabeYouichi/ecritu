#!/usr/bin/env python3
"""references/it.plist(IT の語)から Packages/EcrituConversion/Sources/EcrituConversionBase/ITTermTable.swift を作る。

連文節で、文の頭の 登録語+助詞 をラテン文字の形にする規則(latinFirstForRegisteredWordPlusParticle、3846)を
IT の語だけに効かせるための表。ワインの語(vin.plist)などは、文の中ではカタカナを先にする(以前のユーザ指定)ので入れない。
it.plist を直したら、これを実行して表を作り直す。

使い方: python3 tools/build_it_term_table.py
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "references" / "it.plist"
DST = ROOT / "Packages" / "EcrituConversion" / "Sources" / "EcrituConversionBase" / "ITTermTable.swift"
ENTRY = re.compile(r"<key>phrase</key><string>(.*?)</string><key>shortcut</key><string>(.*?)</string>")
LATIN = re.compile(r"[A-Za-z]")


def main():
    text = re.sub(r"<!--.*?-->", "", SRC.read_text(encoding="utf-8"), flags=re.S)
    keys = sorted({f"{reading}\t{phrase}" for phrase, reading in ENTRY.findall(text) if LATIN.search(phrase)})
    for key in keys:
        assert '"' not in key and "\\" not in key, key
    lines = [
        "import Foundation",
        "",
        "// 生成ファイル。tools/build_it_term_table.py が references/it.plist から作る。手で直さない(3846)",
        "// IT の語のうち、表記にラテン文字を含むもの(読み+タブ+表記)。連文節で、文の頭の 登録語+助詞 をラテン文字の形に",
        "// する規則(てすとふらいとにあげる→TestFlightに上げる)を、この表の語だけに効かせる",
        "public enum ITTermTable {",
        "    public static let readingAndLatinSurfaces: Set<String> = [",
    ]
    lines += [f'        "{key.replace(chr(9), chr(92) + "t")}",' for key in keys]
    lines += ["    ]", "}", ""]
    DST.write_text("\n".join(lines), encoding="utf-8")
    print(f"wrote {DST.relative_to(ROOT)}: {len(keys)} 語")


main()
