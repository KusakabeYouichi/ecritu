#!/usr/bin/env python3
"""Increment ECRITU_EDITION_NUMBER in Edition.xcconfig."""

from __future__ import annotations

import re
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: bump_edition_number.py <xcconfig-path>", file=sys.stderr)
        return 2

    path = Path(sys.argv[1])
    if not path.exists():
        print(f"error: file not found: {path}", file=sys.stderr)
        return 1

    text = path.read_text(encoding="utf-8")
    pattern = re.compile(r"^(ECRITU_EDITION_NUMBER\s*=\s*)(\d+)\s*$", re.MULTILINE)
    match = pattern.search(text)

    if match is None:
        print("error: ECRITU_EDITION_NUMBER not found", file=sys.stderr)
        return 1

    current_number = int(match.group(2))
    next_number = current_number + 1
    updated_text = text[: match.start(2)] + str(next_number) + text[match.end(2) :]
    path.write_text(updated_text, encoding="utf-8")

    print(f"Using edition number: {next_number}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
