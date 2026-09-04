#!/usr/bin/env python3
"""Regenerate the two data tables in KeyboardExtension/KaomojiCatalog.swift
(importedEntriesByCategory / importedEntriesByReading) from a JSON list of
{"kaomoji", "yomi_list", "categories"} records (categories = French keys:
rire/kawaii/timide/panique/decu/triste/colere/surprise/dodo/coucou/amour/excite/
action/bizarre/heros/special/lignes).

Usage: python3 tools/build_kaomoji_catalog.py tmp/kaomoji_merged.json
Only the two tables are replaced; everything else in the Swift file is kept.
Category order inside the table follows KaomojiCatalog.importedCategoryOrder;
readings are sorted (localized order is applied at runtime).
"""

from __future__ import annotations

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


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("usage: build_kaomoji_catalog.py <merged.json>")
    records = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
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
