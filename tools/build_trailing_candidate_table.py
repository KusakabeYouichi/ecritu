#!/usr/bin/env python3
"""references/fiefs.plist(候補の後ろのほうに足す語)から
Packages/EcrituConversion/Sources/EcrituConversionBase/TrailingCandidateTable.swift を作る(3860)。

plist を直したらこれを流してコミットする。コメントアウトした行(行頭の <!--<dict>…</dict>-->)は載せない。

使い方: python3 tools/build_trailing_candidate_table.py
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "references" / "fiefs.plist"
DST = ROOT / "Packages" / "EcrituConversion" / "Sources" / "EcrituConversionBase" / "TrailingCandidateTable.swift"

ENTRY = re.compile(r"<key>phrase</key><string>([^<]+)</string><key>shortcut</key><string>([^<]+)</string>")


def swift_string(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main() -> int:
    by_reading = {}  # 読み → [表記](plist の順)
    for line in SRC.read_text(encoding="utf-8").splitlines():
        entry = ENTRY.search(re.sub(r"<!--.*?-->", "", line))
        if not entry:
            continue
        surface, reading = entry.group(1), entry.group(2)
        if surface not in by_reading.setdefault(reading, []):
            by_reading[reading].append(surface)
    out = [
        "import Foundation",
        "",
        "// 生成ファイル。tools/build_trailing_candidate_table.py が references/fiefs.plist から作る。手で直さない(3860)",
        "// 候補の後ろのほうに足す語(藩の名前)。読み全体がこの読みのときだけ、単文節の候補に足す(先頭は奪わない)",
        "public enum TrailingCandidateTable {",
        "    public static let surfacesByReading: [String: [String]] = [",
    ]
    for reading in sorted(by_reading):
        surfaces = ", ".join(swift_string(s) for s in by_reading[reading])
        out.append(f"        {swift_string(reading)}: [{surfaces}],")
    out += [
        "    ]",
        "",
        "    // 足す位置(0 始まり)。候補がこれより少なければ末尾",
        "    public static let insertionIndex = 2",
        "",
        "    public static func inserted(reading: String, candidates: [String]) -> [String] {",
        "        guard let surfaces = surfacesByReading[reading] else {",
        "            return candidates",
        "        }",
        "        let missing = surfaces.filter { !candidates.contains($0) }",
        "        guard !missing.isEmpty else {",
        "            return candidates",
        "        }",
        "        var result = candidates",
        "        result.insert(contentsOf: missing, at: min(insertionIndex, result.count))",
        "        return result",
        "    }",
        "}",
        "",
    ]
    DST.write_text("\n".join(out), encoding="utf-8")
    print(f"wrote {DST.relative_to(ROOT)}: {len(by_reading)} 読み")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
