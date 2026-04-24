#!/usr/bin/env python3
"""Increment edition number and refresh update date metadata."""

from __future__ import annotations

from datetime import datetime
import re
import sys
from pathlib import Path


def update_content_view_timestamp(xcconfig_path: Path, timestamp_value: str) -> None:
    content_view_path = xcconfig_path.parent.parent / "App" / "ContentView.swift"

    if not content_view_path.exists():
        raise FileNotFoundError(f"content view file not found: {content_view_path}")

    content = content_view_path.read_text(encoding="utf-8")
    pattern = re.compile(
        r'^(\s*private static let editionUpdatedAtRaw: String = ")(\d+)(")\s*$',
        re.MULTILINE,
    )
    match = pattern.search(content)

    if match is None:
        raise RuntimeError("editionUpdatedAtRaw constant not found in ContentView.swift")

    updated_content = (
        content[: match.start(2)]
        + timestamp_value
        + content[match.end(2) :]
    )
    content_view_path.write_text(updated_content, encoding="utf-8")


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

    timestamp_key = "ECRITU_EDITION_UPDATED_AT"
    timestamp_value = datetime.now().strftime("%Y%m%d%H%M%S")
    timestamp_pattern = re.compile(
        rf"^({timestamp_key}\s*=\s*)(\d+)\s*$",
        re.MULTILINE
    )
    timestamp_match = timestamp_pattern.search(updated_text)

    if timestamp_match is None:
        if not updated_text.endswith("\n"):
            updated_text += "\n"
        updated_text += f"{timestamp_key} = {timestamp_value}\n"
    else:
        updated_text = (
            updated_text[: timestamp_match.start(2)]
            + timestamp_value
            + updated_text[timestamp_match.end(2) :]
        )

    path.write_text(updated_text, encoding="utf-8")
    update_content_view_timestamp(path, timestamp_value)

    print(f"Using edition number: {next_number}")
    print(f"Updated edition timestamp: {timestamp_value}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
