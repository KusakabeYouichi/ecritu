#!/usr/bin/env python3
"""Convert references/apple.list to Apple user dictionary plist format.

Input format:
- Non-empty line: "reading<TAB>phrase"
- Empty line: category separator

Output format:
- plist array of dict entries with keys: phrase, shortcut
- block comments: カネゴリー1, カネゴリー2, ...
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import List
from xml.sax.saxutils import escape


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Convert apple.list to it.plist")
    parser.add_argument("--input", required=True, help="Input list path")
    parser.add_argument("--output", required=True, help="Output plist path")
    return parser.parse_args()


def build_plist_lines(source_lines: List[str]) -> List[str]:
    lines: List[str] = [
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
        "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">",
        "<plist version=\"1.0\">",
        "<array>",
    ]

    category_number = 1
    comment_emitted_for_block = False
    wrote_entry = False

    for raw in source_lines:
        row = raw.rstrip("\n")

        if not row.strip():
            if comment_emitted_for_block:
                category_number += 1
                comment_emitted_for_block = False
            continue

        columns = row.split("\t")
        if len(columns) < 2:
            continue

        reading = columns[0].strip()
        phrase = columns[1].strip()
        if not reading or not phrase:
            continue

        if not comment_emitted_for_block:
            if wrote_entry:
                lines.append("")
            lines.append(f"\t<!-- カネゴリー{category_number} -->")
            comment_emitted_for_block = True

        lines.append(
            "\t<dict><key>phrase</key><string>"
            f"{escape(phrase)}</string><key>shortcut</key><string>{escape(reading)}</string></dict>"
        )
        wrote_entry = True

    lines.extend([
        "</array>",
        "</plist>",
    ])
    return lines


def main() -> int:
    args = parse_args()

    input_path = Path(args.input)
    output_path = Path(args.output)

    source_lines = input_path.read_text(encoding="utf-8").splitlines()
    plist_text = "\n".join(build_plist_lines(source_lines)) + "\n"

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(plist_text, encoding="utf-8")

    print(f"wrote: {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
