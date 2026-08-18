#!/usr/bin/env python3
"""vin.plist の「未分類」カテゴリーから既存カテゴリーへエントリを移す。

使い方: python3 tools/apply_vin_recat.py <再分類表.tsv> ...
再分類表は「表記<TAB>移動先カテゴリー名」の行を並べたもの。移動先は
vin.plist に実在するカテゴリー見出しと完全一致していること。
移動は各カテゴリーの末尾に追加する(カテゴリー内の並びは元々厳密でない)。
"""
import collections
import pathlib
import re
import sys

ENTRY = re.compile(r'<key>phrase</key><string>(.*?)</string><key>shortcut</key><string>(.*?)</string>')
COMMENT = re.compile(r'<!--\s*(.+?)\s*-->')
SOURCE_CATEGORY = "未分類"


def main(tsv_paths):
    path = pathlib.Path("references/vin.plist")
    lines = path.read_text().split("\n")

    moves = {}
    for tsv in tsv_paths:
        for line in pathlib.Path(tsv).read_text().split("\n"):
            if line.startswith("#") or "\t" not in line:
                continue
            phrase, category = line.split("\t", 1)
            moves[phrase] = category

    categories = set()
    for line in lines:
        if not ENTRY.search(line):
            comment = COMMENT.search(line)
            if comment:
                categories.add(comment.group(1))
    missing = sorted(set(moves.values()) - categories)
    if missing:
        sys.exit(f"存在しない移動先カテゴリー: {missing}")

    current = None
    taken = collections.defaultdict(list)
    kept = []
    found = set()
    for line in lines:
        entry = ENTRY.search(line)
        if not entry:
            comment = COMMENT.search(line)
            if comment:
                current = comment.group(1)
            kept.append(line)
            continue
        if current == SOURCE_CATEGORY and entry.group(1) in moves:
            taken[moves[entry.group(1)]].append(line)
            found.add(entry.group(1))
            continue
        kept.append(line)

    unresolved = sorted(set(moves) - found)
    if unresolved:
        print(f"未分類に見つからなかった語 {len(unresolved)}件: {unresolved[:20]}")

    current = None
    last_index_of = {}
    for index, line in enumerate(kept):
        if not ENTRY.search(line):
            comment = COMMENT.search(line)
            if comment:
                current = comment.group(1)
        else:
            last_index_of[current] = index

    out = []
    for index, line in enumerate(kept):
        out.append(line)
        for category, rows in taken.items():
            if last_index_of.get(category) == index:
                out.extend(rows)
    path.write_text("\n".join(out))

    counts = collections.Counter()
    current = None
    for line in out:
        entry = ENTRY.search(line)
        if not entry:
            comment = COMMENT.search(line)
            if comment:
                current = comment.group(1)
        else:
            counts[current] += 1
    print(f"移動 {len(found)}件 / 総エントリ {sum(counts.values())} / {SOURCE_CATEGORY} {counts[SOURCE_CATEGORY]}")


if __name__ == "__main__":
    main(sys.argv[1:])
