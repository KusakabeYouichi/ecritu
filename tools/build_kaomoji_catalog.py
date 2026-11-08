#!/usr/bin/env python3
"""Regenerate the two data tables in KeyboardExtension/KaomojiCatalog.swift
(importedEntriesByCategory / importedEntriesByReading) from a JSON list of
{"kaomoji", "yomi_list", "categories"} records (categories = French keys:
etincelles/rire/kawaii/timide/panique/decu/triste/colere/surprise/dodo/coucou/amour/
excite/action/bizarre/heros/special).

Usage: python3 -I tools/build_kaomoji_catalog.py tmp/kaomoji_merged.json \
           [--order tmp/kaomoji_kirakira.txt:etincelles:きらきら --order tmp/kaomoji_heart.txt:amour:はーと]
Only the two tables are replaced; everything else in the Swift file is kept.
Category order inside the table follows KaomojiCatalog.importedCategoryOrder;
readings are sorted (localized order is applied at runtime).
Faces inside a category or a reading follow the record order of the JSON, except that
--order FILE:CATEGORY:READING puts the faces listed in FILE first, in the file's order
(hand-sorted from the most popular, 3724), and keeps the rest after them.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

SWIFT = Path(__file__).resolve().parents[1] / "KeyboardExtension" / "KaomojiCatalog.swift"


def swift_string(s: str) -> str:
    return json.dumps(s, ensure_ascii=False)


def render_table(name: str, mapping: dict[str, list[str]], keys: list[str]) -> str:
    lines = [f"    static let {name}: [String: [String]] = ["]
    for key in keys:
        values = mapping.get(key, [])
        if not values:
            continue
        lines.append(f"        {swift_string(key)}: [")
        for value in values:
            lines.append(f"            {swift_string(value)},")
        lines.append("        ],")
    lines.append("    ]")
    return "\n".join(lines)


def ordered_faces(path: Path) -> list[str]:
    faces: list[str] = []
    for line in path.read_text(encoding="utf-8").split("\n"):
        if line.strip() and not line.startswith("#") and line not in faces:
            faces.append(line)
    return faces


def put_first(bucket: list[str], order: list[str]) -> list[str]:
    present = set(bucket)
    head = [face for face in order if face in present]
    head_set = set(head)
    return head + [face for face in bucket if face not in head_set]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("merged")
    parser.add_argument("--order", action="append", default=[], help="FILE:CATEGORY:READING")
    args = parser.parse_args()
    records = json.loads(Path(args.merged).read_text(encoding="utf-8"))
    source = SWIFT.read_text(encoding="utf-8")

    order_match = re.search(r"static let importedCategoryOrder: \[String\] = \[(.*?)\]", source, re.S)
    if not order_match:
        sys.exit("importedCategoryOrder not found")
    category_order = re.findall(r'"([^"]+)"', order_match.group(1))

    by_category: dict[str, list[str]] = {}
    by_reading: dict[str, list[str]] = {}
    for record in records:
        face = record["kaomoji"]
        for category in record["categories"]:
            if category not in category_order:
                sys.exit(f"unknown category {category!r} for {face!r}")
            bucket = by_category.setdefault(category, [])
            if face not in bucket:
                bucket.append(face)
        for reading in record["yomi_list"]:
            bucket = by_reading.setdefault(reading, [])
            if face not in bucket:
                bucket.append(face)

    for spec in args.order:
        file_name, category, reading = spec.rsplit(":", 2)
        order = ordered_faces(Path(file_name))
        if category in by_category:
            by_category[category] = put_first(by_category[category], order)
        if reading in by_reading:
            by_reading[reading] = put_first(by_reading[reading], order)

    def replace_table(text: str, name: str, rendered: str) -> str:
        pattern = re.compile(
            rf"    static let {name}: \[String: \[String\]\] = \[\n.*?\n    \]",
            re.S,
        )
        if not pattern.search(text):
            sys.exit(f"table {name} not found")
        return pattern.sub(lambda _: rendered, text, count=1)

    source = replace_table(source, "importedEntriesByCategory", render_table("importedEntriesByCategory", by_category, category_order))
    source = replace_table(source, "importedEntriesByReading", render_table("importedEntriesByReading", by_reading, sorted(by_reading)))
    SWIFT.write_text(source, encoding="utf-8")
    print(f"[kaomoji] {len(records)} faces, {len(by_reading)} readings, categories={ {k: len(v) for k, v in by_category.items()} }")


if __name__ == "__main__":
    main()
