#!/usr/bin/env python3
"""references/kakikae.plist(同音の漢字による書きかえ)から KeyboardExtension/KakikaeTable.swift を作る(3422)。

節の見出しは「<!-- ■ 英名 説明 -->」。normal はコンテナー X.9 で選ぶ組、lateStandardized(報告の後に常用漢字に加わった字の組)は
X.10 で選ぶ組(3570)。
アプリ(設定画面の例)とキーボード(変換)の両方がこの表を使う。plist を直したらこれを流してコミットする。

使い方: python3 tools/build_kakikae_table.py
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "references" / "kakikae.plist"
DST = ROOT / "KeyboardExtension" / "KakikaeTable.swift"

HEADER = re.compile(r"<!--\s*■\s*(\w+)")
ENTRY = re.compile(r"<key>before</key><string>([^<]+)</string><key>after</key><string>([^<]+)</string>")


def swift_string(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main() -> int:
    section = None
    pairs = []  # [(before, after, isLateStandardized)]
    for line in SRC.read_text(encoding="utf-8").splitlines():
        header = HEADER.search(line)
        if header:
            section = header.group(1)
            continue
        entry = ENTRY.search(line)
        if entry and section:
            before, after = entry.group(1), entry.group(2)
            if len(before) != len(after):
                raise SystemExit(f"字数が違う組: {before} → {after}")
            pairs.append((before, after, section == "lateStandardized"))

    out = [
        "import Foundation",
        "",
        "// 生成ファイル。tools/build_kakikae_table.py が references/kakikae.plist から作る。手で直さない(3422)",
        "// 同音の漢字による書きかえ(1956 年 国語審議会報告)の語の組。コンテナー設定 X.9 で 書きかえ前だけ/後だけ/両方 を選ぶ。",
        "// 報告の後に書きかえ前の字が常用漢字に加わった組は X.10 で別に選ぶ(3570)",
        "enum KakikaeTable {",
        "    // (書きかえ前, 書きかえ後, 報告の後に常用漢字に加わった字の組か)。plist の順",
        "    static let pairs: [(before: String, after: String, isLateStandardized: Bool)] = [",
    ]
    for before, after, late in pairs:
        out.append(f"        ({swift_string(before)}, {swift_string(after)}, {'true' if late else 'false'}),")
    out += [
        "    ]",
        "",
        "    // X.9 で選ぶ組(isLateStandardized を除く)",
        "    static let switchablePairs: [(before: String, after: String)] = pairs.filter { !$0.isLateStandardized }.map { ($0.before, $0.after) }",
        "",
        "    // X.10 で選ぶ組(報告の後に常用漢字に加わった字の組。3570)",
        "    static let lateStandardizedPairs: [(before: String, after: String)] = pairs.filter { $0.isLateStandardized }.map { ($0.before, $0.after) }",
        "",
        "    // 書きかえ前 → 書きかえ後 / 書きかえ後 → 書きかえ前(X.9 の組だけ)",
        "    static let afterByBefore: [String: String] = Dictionary(switchablePairs.map { ($0.before, $0.after) }, uniquingKeysWith: { first, _ in first })",
        "    static let beforeByAfter: [String: String] = Dictionary(switchablePairs.map { ($0.after, $0.before) }, uniquingKeysWith: { first, _ in first })",
        "",
        "    // 候補の中の出現を探すための索引(語の先頭の字 → 組)。打鍵ごとに全組を contains で舐めないため",
        "    static let switchablePairsByBeforeHead: [Character: [(before: String, after: String)]] =",
        "        Dictionary(grouping: switchablePairs, by: { $0.before.first! })",
        "    static let switchablePairsByAfterHead: [Character: [(before: String, after: String)]] =",
        "        Dictionary(grouping: switchablePairs, by: { $0.after.first! })",
        "    static let lateStandardizedPairsByBeforeHead: [Character: [(before: String, after: String)]] =",
        "        Dictionary(grouping: lateStandardizedPairs, by: { $0.before.first! })",
        "    static let lateStandardizedPairsByAfterHead: [Character: [(before: String, after: String)]] =",
        "        Dictionary(grouping: lateStandardizedPairs, by: { $0.after.first! })",
        "}",
        "",
    ]
    DST.write_text("\n".join(out), encoding="utf-8")
    print(f"wrote {DST.relative_to(ROOT)}: {len(pairs)} 組(X.10 の組 {sum(1 for p in pairs if p[2])})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
