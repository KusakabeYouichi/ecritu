#!/usr/bin/env python3
"""Remove blocklisted words from LatinSuggestionLexicon_{lang}.txt in place.

build_latin_suggestion_lexicon.py applies the same list at generation time; this script
lets us re-filter the committed lists without re-downloading the sources (2785).
Usage: python3 tools/apply_latin_suggestion_blocklist.py KeyboardExtension/LatinSuggestionLexicon_*.txt
"""

from __future__ import annotations

import sys
import unicodedata
from pathlib import Path

BLOCKLIST_PATH = Path(__file__).with_name("latin_suggestion_blocklist.txt")


def fold(word: str) -> str:
    decomposed = unicodedata.normalize("NFD", word)
    stripped = "".join(ch for ch in decomposed if unicodedata.category(ch) != "Mn")
    return unicodedata.normalize("NFC", stripped).lower()


def load_blocklist() -> tuple[set[str], set[tuple[str, str]]]:
    """Returns (blocked folded words, per-language exceptions as (word, lang))."""
    words = set()
    exceptions = set()
    for line in BLOCKLIST_PATH.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("!") and "@" in line:
            word, lang = line[1:].split("@", 1)
            exceptions.add((fold(word), lang))
            continue
        words.add(fold(line))
    return words, exceptions


def is_blocked(folded_key: str, lang: str, blocklist: set[str], exceptions: set[tuple[str, str]]) -> bool:
    return folded_key in blocklist and (folded_key, lang) not in exceptions


def language_of(path: Path) -> str:
    # LatinSuggestionLexicon_en.txt -> en
    return path.stem.rsplit("_", 1)[-1]


def main() -> None:
    blocklist, exceptions = load_blocklist()
    for arg in sys.argv[1:]:
        path = Path(arg)
        lang = language_of(path)
        kept = []
        removed = []
        for line in path.read_text(encoding="utf-8").splitlines():
            key = line.split("\t", 1)[0]
            if is_blocked(fold(key), lang, blocklist, exceptions):
                removed.append(line)
            else:
                kept.append(line)
        path.write_text("\n".join(kept) + "\n", encoding="utf-8")
        print(f"{path.name}: removed {len(removed)}: {', '.join(r.split(chr(9))[1] for r in removed)}")


if __name__ == "__main__":
    main()
