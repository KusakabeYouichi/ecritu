#!/usr/bin/env python3
"""Build supplemental vocab JSON from Apple user dictionary plist files.

Each plist entry is expected to be a dict with:
- shortcut: reading
- phrase: candidate
"""

from __future__ import annotations

import argparse
import json
import plistlib
from pathlib import Path
from typing import Dict, List


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build ÉcrituSecondVocab.json from plist references")
    parser.add_argument(
        "--input-plist",
        action="append",
        required=True,
        help="Input plist path (repeatable)",
    )
    parser.add_argument("--output", required=True, help="Output JSON path")
    return parser.parse_args()


def merge_pair(merged: Dict[str, List[str]], reading: str, candidate: str) -> None:
    values = merged.setdefault(reading, [])
    if candidate not in values:
        values.append(candidate)


def load_plist(path: Path, merged: Dict[str, List[str]]) -> None:
    with path.open("rb") as f:
        obj = plistlib.load(f)

    if not isinstance(obj, list):
        return

    for entry in obj:
        if not isinstance(entry, dict):
            continue

        raw_reading = entry.get("shortcut")
        raw_phrase = entry.get("phrase")

        if not isinstance(raw_reading, str) or not isinstance(raw_phrase, str):
            continue

        reading = raw_reading.strip()
        phrase = raw_phrase.strip()

        if not reading or not phrase:
            continue

        merge_pair(merged, reading, phrase)


def main() -> int:
    args = parse_args()

    merged: Dict[str, List[str]] = {}

    for plist_path in args.input_plist:
        path = Path(plist_path)
        if path.exists():
            load_plist(path, merged)

    # Remove empty readings and stabilize output order.
    cleaned = {k: v for k, v in merged.items() if k and v}
    output_text = json.dumps(cleaned, ensure_ascii=False, indent=2, sort_keys=True) + "\n"

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    if output_path.exists():
        previous = output_path.read_text(encoding="utf-8")
        if previous == output_text:
            print(f"up-to-date: {output_path}")
            return 0

    output_path.write_text(output_text, encoding="utf-8")
    print(f"wrote: {output_path}")
    print(f"readings={len(cleaned)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
