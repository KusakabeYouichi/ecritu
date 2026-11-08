#!/usr/bin/env python3
"""Import a hand-ordered kaomoji list (one face per line) into tmp/kaomoji_merged.json.

Usage:
    python3 -I tools/import_kaomoji_lists.py tmp/kaomoji_merged.json \
        --list tmp/kaomoji_kirakira.txt:etincelles:きらきら \
        --list tmp/kaomoji_heart.txt:amour:はーと \
        [--skip tmp/kaomoji_import_skip.txt] [--move-out special:etincelles]

For each --list FILE:CATEGORY:READING
- every face in FILE (blank lines and lines starting with '#' are ignored) gets READING and CATEGORY;
  faces that are not in the JSON yet are added as new records. Existing categories are kept.
- faces in the JSON that have READING but are not in FILE lose READING (the file is the source of truth
  for that reading). The face itself and its other readings stay.
--skip FILE: faces to leave out (one per line, '#' comments allowed).
--move-out OLD:NEW: faces that end up in NEW lose OLD (e.g. sparkle faces leave special for etincelles).

The order of the list files is applied later by build_kaomoji_catalog.py --order.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def read_faces(path: Path) -> list[str]:
    faces: list[str] = []
    for line in path.read_text(encoding="utf-8").split("\n"):
        if not line.strip() or line.startswith("#"):
            continue
        if line not in faces:
            faces.append(line)
    return faces


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("merged")
    parser.add_argument("--list", action="append", required=True, help="FILE:CATEGORY:READING")
    parser.add_argument("--skip")
    parser.add_argument("--move-out", action="append", default=[], help="OLD:NEW")
    args = parser.parse_args()

    merged_path = Path(args.merged)
    records = json.loads(merged_path.read_text(encoding="utf-8"))
    by_face = {record["kaomoji"]: record for record in records}
    skip = set(read_faces(Path(args.skip))) if args.skip else set()

    for spec in args.list:
        file_name, category, reading = spec.rsplit(":", 2)
        faces = [face for face in read_faces(Path(file_name)) if face not in skip]
        face_set = set(faces)
        added = updated = dropped = 0
        for face in faces:
            record = by_face.get(face)
            if record is None:
                record = {"kaomoji": face, "yomi_list": [], "categories": []}
                records.append(record)
                by_face[face] = record
                added += 1
            else:
                updated += 1
            if reading not in record["yomi_list"]:
                record["yomi_list"].append(reading)
            if category not in record["categories"]:
                record["categories"].append(category)
        for record in records:
            if reading in record["yomi_list"] and record["kaomoji"] not in face_set:
                record["yomi_list"].remove(reading)
                dropped += 1
        print(f"[{reading}/{category}] {len(faces)} faces: new {added}, existing {updated}, reading removed from {dropped}")

    for spec in args.move_out:
        old, new = spec.split(":")
        moved = [r["kaomoji"] for r in records if old in r["categories"] and new in r["categories"]]
        for record in records:
            if record["kaomoji"] in moved:
                record["categories"].remove(old)
        print(f"[move-out] {old} -> {new}: {moved}")

    empty = [r["kaomoji"] for r in records if not r["categories"]]
    if empty:
        sys.exit(f"records without category: {empty}")
    merged_path.write_text(json.dumps(records, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"[kaomoji] {len(records)} records")


if __name__ == "__main__":
    main()
