#!/usr/bin/env python3
"""references/kanagaki.plist(かなで書く言葉)から KeyboardExtension/KanaGakiTable.swift を作る(3404)。

節の見出しは「<!-- ■ 英名 日本語名 -->」。英名が KanaGakiCategory の case 名になる。
アプリ(設定画面の例)とキーボード(変換)の両方がこの表を使う。plist を直したらこれを流してコミットする。

使い方: python3 tools/build_kanagaki_table.py
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "references" / "kanagaki.plist"
DST = ROOT / "KeyboardExtension" / "KanaGakiTable.swift"

HEADER = re.compile(r"<!--\s*■\s*(\w+)\s+(.+?)\s*-->")
ENTRY = re.compile(r"<key>phrase</key><string>([^<]+)</string><key>shortcut</key><string>([^<]+)</string>")


def swift_string(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main() -> int:
    groups = []  # [(id, title, [(surface, reading)])]
    for line in SRC.read_text(encoding="utf-8").splitlines():
        header = HEADER.search(line)
        if header:
            groups.append((header.group(1), header.group(2), []))
            continue
        entry = ENTRY.search(line)
        if entry and groups:
            groups[-1][2].append((entry.group(1), entry.group(2)))

    out = [
        "import Foundation",
        "",
        "// 生成ファイル。tools/build_kanagaki_table.py が references/kanagaki.plist から作る。手で直さない(3404)",
        "// かなで書く言葉: 漢字で書けるが、今の文章ではかなで書くことが多い語。コンテナー設定 X.8 で仲間ごとに",
        "// 抑制(漢字を出さない)/抑制しない(かなを先頭にして漢字はその後ろ)を選ぶ",
        "enum KanaGakiCategory: String, CaseIterable {",
    ]
    out += [f"    case {gid}" for gid, _, _ in groups]
    out += [
        "",
        "    var title: String {",
        "        switch self {",
    ]
    out += [f"        case .{gid}: return {swift_string(title)}" for gid, title, _ in groups]
    out += [
        "        }",
        "    }",
        "",
        "    var settingsKey: String {",
        '        "kanaGakiSuppress" + rawValue.prefix(1).uppercased() + rawValue.dropFirst()',
        "    }",
        "}",
        "",
        "enum KanaGakiTable {",
        "    // 仲間 → [(漢字表記, 読み)](plist の順。設定画面の例はこの順に先頭から並べる)",
        "    static let entries: [KanaGakiCategory: [(surface: String, reading: String)]] = [",
    ]
    for gid, _, items in groups:
        pairs = ", ".join(f"({swift_string(s)}, {swift_string(r)})" for s, r in items)
        out.append(f"        .{gid}: [{pairs}],")
    out += [
        "    ]",
        "",
        "    // 読み → 漢字表記 → 仲間(変換で引く用)",
        "    static let categoryByReadingAndSurface: [String: [String: KanaGakiCategory]] = {",
        "        var table: [String: [String: KanaGakiCategory]] = [:]",
        "        for (category, items) in entries {",
        "            for item in items {",
        "                table[item.reading, default: [:]][item.surface] = category",
        "            }",
        "        }",
        "        return table",
        "    }()",
        "}",
        "",
    ]
    DST.write_text("\n".join(out), encoding="utf-8")
    print(f"wrote {DST.relative_to(ROOT)}: {sum(len(g[2]) for g in groups)} 語 / {len(groups)} 仲間")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
