#!/usr/bin/env python3
"""Build supplemental vocab JSON from Apple user dictionary plist files.

Each plist entry is expected to be a dict with:
- shortcut: reading
- phrase: candidate
- pos (optional): plist-side POS label (サ変名詞 / 一段 / 五段 / カ変 / 形容詞)
"""

from __future__ import annotations

import argparse
import json
import plistlib
from pathlib import Path
from typing import Dict, List, Optional


# plist pos label -> Swift InflectionClass internal label
POS_TO_SWIFT_CLASS = {
    "サ変名詞": "suru",
    "一段": "ichidan",
    "カ変": "kuru",
    "形容詞": "adjective-i",
    # "五段" is resolved per-row from candidate suffix at insertion time.
}

GODAN_SUFFIX_TO_CLASS = {
    "う": "godan-u",
    "く": "godan-ku",
    "ぐ": "godan-gu",
    "す": "godan-su",
    "つ": "godan-tsu",
    "ぬ": "godan-nu",
    "ぶ": "godan-bu",
    "む": "godan-mu",
    "る": "godan-ru",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build ÉcrituSecondVocab.json from plist references")
    parser.add_argument(
        "--input-plist",
        action="append",
        required=True,
        help="Input plist path (repeatable)",
    )
    parser.add_argument("--output", required=True, help="Output JSON path")
    parser.add_argument(
        "--output-inflections",
        default=None,
        help="Optional output JSON path for inflection class metadata from plist pos field",
    )
    return parser.parse_args()


def merge_pair(merged: Dict[str, List[str]], reading: str, candidate: str) -> None:
    values = merged.setdefault(reading, [])
    if candidate not in values:
        values.append(candidate)


def resolve_swift_class(pos: str, candidate: str) -> Optional[str]:
    if pos == "五段":
        if not candidate:
            return None
        last = candidate[-1]
        return GODAN_SUFFIX_TO_CLASS.get(last)
    return POS_TO_SWIFT_CLASS.get(pos)


def load_plist(
    path: Path,
    merged: Dict[str, List[str]],
    inflections: Optional[Dict[str, Dict[str, str]]],
) -> None:
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

        if inflections is None:
            continue

        raw_pos = entry.get("pos")
        if not isinstance(raw_pos, str):
            continue
        pos = raw_pos.strip()
        if not pos:
            continue

        swift_class = resolve_swift_class(pos, phrase)
        if swift_class is None:
            continue

        reading_map = inflections.setdefault(reading, {})
        # First-write wins; subsequent same-reading entries don't overwrite.
        reading_map.setdefault(phrase, swift_class)


def main() -> int:
    args = parse_args()

    merged: Dict[str, List[str]] = {}
    inflections: Optional[Dict[str, Dict[str, str]]] = (
        {} if args.output_inflections else None
    )

    for plist_path in args.input_plist:
        path = Path(plist_path)
        if path.exists():
            load_plist(path, merged, inflections)

    cleaned = {k: v for k, v in merged.items() if k and v}
    output_text = json.dumps(cleaned, ensure_ascii=False, indent=2, sort_keys=True) + "\n"

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    if output_path.exists() and output_path.read_text(encoding="utf-8") == output_text:
        print(f"up-to-date: {output_path}")
    else:
        output_path.write_text(output_text, encoding="utf-8")
        print(f"wrote: {output_path}")
        print(f"readings={len(cleaned)}")

    if inflections is not None and args.output_inflections:
        cleaned_inflections = {k: v for k, v in inflections.items() if k and v}
        inflections_text = json.dumps(
            cleaned_inflections, ensure_ascii=False, indent=2, sort_keys=True
        ) + "\n"
        inflections_path = Path(args.output_inflections)
        inflections_path.parent.mkdir(parents=True, exist_ok=True)
        if inflections_path.exists() and inflections_path.read_text(encoding="utf-8") == inflections_text:
            print(f"up-to-date: {inflections_path}")
        else:
            inflections_path.write_text(inflections_text, encoding="utf-8")
            print(f"wrote: {inflections_path}")
            tagged = sum(len(v) for v in cleaned_inflections.values())
            print(f"inflection-tagged candidates={tagged}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
