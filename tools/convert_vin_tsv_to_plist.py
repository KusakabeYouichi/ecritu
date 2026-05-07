#!/usr/bin/env python3
"""Convert references/vin.tsv to Apple user dictionary plist format.

Input TSV columns:
1) reading
2) phrase
3) category

Output plist format (array of dict):
- shortcut: reading
- phrase: phrase

Category values are emitted as XML comments between blocks.
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import List
from xml.sax.saxutils import escape


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Convert vin.tsv to vin.plist")
    parser.add_argument("--input", required=True, help="Input TSV path")
    parser.add_argument("--output", required=True, help="Output plist path")
    return parser.parse_args()


def build_plist_lines(tsv_lines: List[str]) -> List[str]:
    lines: List[str] = [
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
        "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">",
        "<plist version=\"1.0\">",
        "<array>",
    ]

    current_category = ""
    emitted_any = False

    for raw in tsv_lines:
        row = raw.rstrip("\n")
        if not row.strip() or row.lstrip().startswith("#"):
            continue

        columns = row.split("\t")
        if len(columns) < 2:
            continue

        reading = columns[0].strip()
        phrase = columns[1].strip()
        category = columns[2].strip() if len(columns) >= 3 else ""

        if not reading or not phrase:
            continue

        if category and category != current_category:
            if emitted_any:
                lines.append("")
            lines.append(f"\t<!-- {escape(category)} -->")
            current_category = category

        escaped_phrase = escape(phrase)
        escaped_reading = escape(reading)
        lines.append(
            "\t<dict><key>phrase</key><string>"
            f"{escaped_phrase}</string><key>shortcut</key><string>{escaped_reading}</string></dict>"
        )
        emitted_any = True

    lines.extend([
        "</array>",
        "</plist>",
    ])
    return lines


def main() -> int:
    args = parse_args()
    input_path = Path(args.input)
    output_path = Path(args.output)

    tsv_lines = input_path.read_text(encoding="utf-8").splitlines()
    plist_text = "\n".join(build_plist_lines(tsv_lines)) + "\n"

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(plist_text, encoding="utf-8")

    print(f"wrote: {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
