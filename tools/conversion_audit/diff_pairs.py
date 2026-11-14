#!/usr/bin/env python3
"""期待と先頭候補の違いを箇所ごとに切り出す(3801、ユーザ指定)。

1 行に違いが複数あれば別々の組にする(コク/こく、白/城、乳種/入手)。ユーザが『気にしなくていい』と決めた組は
ignored_pairs.tsv に置き、classify.py はその組(と near_match のほぼ一致)だけで違う行を c_ignored に分ける。

使い方:
  python3 -I tools/conversion_audit/diff_pairs.py <audit_out.tsv> <pairs.json> [--fix <読み+期待の tsv>]
    不一致の行の違いを組ごとに数えて json に書く(確認ページの元)。--fix の行は「直すと回答した行」として別に数える。

切り出し方: 文字単位の差分を取り、漢字・カタカナ・ラテン文字の連なりは前後の同じ字まで広げる(果/下 → 落果/落下)。
ひらがなと記号には広げない(粕/かす、・/(なし))。片方が空なら前の 1 字を添える(富み/富)。
"""
import collections
import difflib
import hashlib
import json
import os
import sys
import unicodedata

IGNORED_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ignored_pairs.tsv")


def char_class(c):
    o = ord(c)
    if c == "・":
        return "o"
    if 0x3041 <= o <= 0x309F:
        return "h"
    if 0x30A0 <= o <= 0x30FF:
        return "k"
    if 0x4E00 <= o <= 0x9FFF or c in "々〆ヶ":
        return "j"
    if (c.isascii() and c.isalpha()) or (unicodedata.category(c).startswith("L") and o < 0x250):
        return "l"
    if c.isdigit():
        return "d"
    return "o"


def spans(expected, first):
    """(期待の部分, 先頭の部分) の列。"""
    e, t = expected, first
    out = []
    for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, e, t, autojunk=False).get_opcodes():
        if tag == "equal":
            continue

        def edge(side):
            cs = set()
            if i2 > i1:
                cs.add(char_class(e[i1] if side < 0 else e[i2 - 1]))
            if j2 > j1:
                cs.add(char_class(t[j1] if side < 0 else t[j2 - 1]))
            return cs - {"h", "o"}

        a1, a2, b1, b2 = i1, i2, j1, j2
        while a1 > 0 and b1 > 0 and e[a1 - 1] == t[b1 - 1] and char_class(e[a1 - 1]) in edge(-1):
            a1 -= 1
            b1 -= 1
        while a2 < len(e) and b2 < len(t) and e[a2] == t[b2] and char_class(e[a2]) in edge(1):
            a2 += 1
            b2 += 1
        if ((a1 == a2 or b1 == b2) and a1 > 0 and b1 > 0
                and any(char_class(c) != "o" for c in e[a1:a2] + t[b1:b2])
                and not (out and (a1 - 1 < out[-1][1] or b1 - 1 < out[-1][3]))):
            a1 -= 1
            b1 -= 1
        out.append([a1, a2, b1, b2])
    merged = []
    for s in out:
        if merged and (s[0] < merged[-1][1] or s[2] < merged[-1][3]):
            merged[-1][1] = max(merged[-1][1], s[1])
            merged[-1][3] = max(merged[-1][3], s[3])
        else:
            merged.append(s)
    return [(e[a:b], t[c:d]) for a, b, c, d in merged]


def kind_of(a, b):
    if a and b and a != b and (a.startswith(b) or b.startswith(a) or a.endswith(b) or b.endswith(a)) \
            and not all(char_class(c) == "l" or c == " " for c in a + b):
        return "字の過不足(送り仮名など)"
    ca = set(char_class(c) for c in a) - {"o"}
    cb = set(char_class(c) for c in b) - {"o"}
    if not ca or not cb:
        return "記号の有無" if all(char_class(c) == "o" for c in a + b) else "字の過不足(送り仮名など)"
    if "l" in ca | cb:
        return "ラテン文字どうし" if ("l" in ca and "l" in cb) else "ラテン文字とかな・漢字"
    if "j" in ca and "j" in cb:
        return "漢字どうし"
    if "j" in ca | cb:
        other = cb if "j" in ca else ca
        return "漢字とカタカナ" if "k" in (ca | cb) and "h" not in other else "漢字とひらがな"
    if "k" in ca | cb and "h" in ca | cb and not ("k" in ca and "k" in cb and "h" in ca and "h" in cb):
        return "カタカナとひらがな"
    return "その他"


def pair_id(a, b):
    return "p-" + hashlib.sha1((a + "\t" + b).encode()).hexdigest()[:16]


def load_ignored(path=IGNORED_PATH):
    pairs = set()
    if not os.path.exists(path):
        return pairs
    for line in open(path, encoding="utf-8"):
        if line.startswith("#") or not line.strip():
            continue
        cols = line.rstrip("\n").split("\t")
        pairs.add((cols[0], cols[1] if len(cols) > 1 else ""))
    return pairs


def remaining_spans(expected, first, ignored, near=None):
    """『気にしなくていい』組と、near(部分ごとのほぼ一致の判定)に当たらない違いだけを返す。"""
    return [(a, b) for a, b in spans(expected, first)
            if (a, b) not in ignored and not (near and a and b and near(a, b))]


def main():
    args = sys.argv[1:]
    fix_path = None
    if "--fix" in args:
        i = args.index("--fix")
        fix_path = args[i + 1]
        del args[i:i + 2]
    src, dst = args
    fix = set(l.rstrip("\n") for l in open(fix_path, encoding="utf-8")) if fix_path else set()
    agg = collections.OrderedDict()
    rows = 0
    for line in open(src, encoding="utf-8"):
        cols = line.rstrip("\n").split("\t")
        i = next((j for j in range(2, len(cols)) if cols[j] in ("ok", "ng")), None)
        if i is None or cols[i] != "ng" or not cols[i - 1]:
            continue
        reading, expected, first = cols[0], cols[1], cols[i - 1]
        rows += 1
        kind = "fix" if reading + "\t" + expected in fix else "ok"
        for a, b in spans(expected, first):
            d = agg.setdefault((a, b), {"id": pair_id(a, b), "exp": a, "got": b, "type": kind_of(a, b),
                                        "fix": 0, "ok": 0, "ex": []})
            d[kind] += 1
            if len(d["ex"]) < 3:
                d["ex"].append({"k": kind, "e": expected, "t": first})
    json.dump(list(agg.values()), open(dst, "w", encoding="utf-8"), ensure_ascii=False, indent=0)
    print(rows, "行", len(agg), "組", sum(d["fix"] + d["ok"] for d in agg.values()), "か所")


if __name__ == "__main__":
    main()
