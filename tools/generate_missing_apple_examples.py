#!/usr/bin/env python3
"""Generate example words convertible in Apple/macOS dictionary but missing in ecritu vocab.

Input expectations:
- source JSON: {reading: [candidate, ...]}
- ecritu JSONs: {reading: [candidate, ...]}
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source",
        type=Path,
        default=Path("tmp/macos_user_dictionary.json"),
        help="source dictionary JSON (Apple/macOS side)",
    )
    parser.add_argument(
        "--ecritu",
        type=Path,
        nargs="+",
        default=[
            Path("tmp/ÉcrituPremierVocab.json"),
            Path("tmp/ÉcrituSecondVocab.json"),
        ],
        help="ecritu dictionary JSON files",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("references/apple_missing_examples.md"),
        help="output markdown path",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=300,
        help="maximum number of examples",
    )
    parser.add_argument(
        "--exclude-plist",
        type=Path,
        default=None,
        help="Appleユーザー辞書のエクスポートplist（shortcut/phraseペアを除外）",
    )
    return parser.parse_args()


def is_katakana(text: str) -> bool:
    # 全てカタカナ（長音含む）
    return all(("ァ" <= ch <= "ヶ" or ch == "ー") for ch in text)

def is_english(text: str) -> bool:
    # 全て英字または数字または記号（A-Za-z0-9-_.など）
    return all(("A" <= ch <= "Z") or ("a" <= ch <= "z") or ("0" <= ch <= "9") or ch in "-_ .+/#&'()[]" for ch in text)

def is_katakana_to_english_pair(reading: str, candidate: str) -> bool:
    # 読みがカタカナ、候補が英語（ラテン文字）
    return is_katakana(reading) and is_english(candidate)
    parser.add_argument(
        "--katakana-to-english",
        action="store_true",
        help="カタカナ→英語ペアのみ抽出する",
    )


def load_dictionary(path: Path) -> dict[str, list[str]]:
    obj = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(obj, dict):
        raise ValueError(f"dictionary must be object: {path}")

    result: dict[str, list[str]] = {}
    for reading, candidates in obj.items():
        if not isinstance(reading, str) or not isinstance(candidates, list):
            continue
        cleaned: list[str] = []
        seen: set[str] = set()
        for candidate in candidates:
            if not isinstance(candidate, str):
                continue
            value = candidate.strip()
            if not value or value in seen:
                continue
            cleaned.append(value)
            seen.add(value)
        if cleaned:
            result[reading] = cleaned
    return result


def merge_ecritu_candidates(paths: list[Path]) -> dict[str, set[str]]:
    merged: dict[str, set[str]] = {}
    for path in paths:
        entries = load_dictionary(path)
        for reading, candidates in entries.items():
            bucket = merged.setdefault(reading, set())
            bucket.update(candidates)
    return merged


def is_hiragana(text: str) -> bool:
    return all("ぁ" <= ch <= "ゖ" or ch == "ー" for ch in text)


def has_kanji(text: str) -> bool:
    return any("一" <= ch <= "龯" for ch in text)


def is_katakana_or_latin(text: str) -> bool:
    for ch in text:
        if "ァ" <= ch <= "ヶ" or ch == "ー":
            continue
        if "A" <= ch <= "Z" or "a" <= ch <= "z" or "0" <= ch <= "9":
            continue
        return False
    return True


def looks_like_word(reading: str, candidate: str) -> bool:
    if len(reading) > 10 or len(candidate) > 14:
        return False
    if " " in candidate or "\t" in candidate:
        return False
    if candidate == reading:
        return False
    # Prefer lexical items rather than sentences.
    if not (has_kanji(candidate) or is_katakana_or_latin(candidate)):
        return False
    # Source is generally hiragana reading; keep this focused.
    if not is_hiragana(reading):
        return False
    return True


# --- ユーザー辞書plistから除外ペアを抽出 ---
def load_exclude_plist(path: Path) -> set[tuple[str, str]]:
    import plistlib
    exclude = set()
    if not path or not path.exists():
        return exclude
    with path.open("rb") as f:
        obj = plistlib.load(f)
    if not isinstance(obj, list):
        return exclude
    for entry in obj:
        if not isinstance(entry, dict):
            continue
        reading = entry.get("shortcut")
        phrase = entry.get("phrase")
        if isinstance(reading, str) and isinstance(phrase, str):
            exclude.add((reading.strip(), phrase.strip()))
    return exclude


def collect_missing_examples(
    source: dict[str, list[str]],
    ecritu: dict[str, set[str]],
    limit: int,
    exclude_pairs: set[tuple[str, str]] = None,
) -> list[tuple[str, str]]:
    missing: list[tuple[str, str]] = []
    exclude_pairs = exclude_pairs or set()

    for reading in sorted(source.keys()):
        ecritu_candidates = ecritu.get(reading, set())
        for candidate in source[reading]:
            if candidate in ecritu_candidates:
                continue
            if (reading, candidate) in exclude_pairs:
                continue
            # 新オプション: カタカナ→英語ペアのみ
            from argparse import Namespace
            import sys
            args = getattr(sys.modules[__name__], 'args', None)
            if args and getattr(args, 'katakana_to_english', False):
                if not is_katakana_to_english_pair(reading, candidate):
                    continue
            else:
                if not looks_like_word(reading, candidate):
                    continue
            missing.append((reading, candidate))
            if len(missing) >= limit:
                return missing

    return missing


def write_markdown(
    output: Path,
    source_path: Path,
    ecritu_paths: list[Path],
    examples: list[tuple[str, str]],
) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)

    lines: list[str] = []
    lines.append("# Apple側では変換候補になり、écritu辞書には未収録の例")
    lines.append("")
    lines.append(f"- source: {source_path}")
    lines.append("- ecritu:")
    for path in ecritu_paths:
        lines.append(f"  - {path}")
    lines.append(f"- examples: {len(examples)}")
    lines.append("")
    lines.append("| よみ | 候補 |")
    lines.append("| --- | --- |")
    for reading, candidate in examples:
        safe_reading = reading.replace("|", "\\|")
        safe_candidate = candidate.replace("|", "\\|")
        lines.append(f"| {safe_reading} | {safe_candidate} |")

    output.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    global args
    args = parse_args()

    if not args.source.exists():
        raise FileNotFoundError(args.source)

    for path in args.ecritu:
        if not path.exists():
            raise FileNotFoundError(path)

    source_dict = load_dictionary(args.source)
    ecritu_dict = merge_ecritu_candidates(args.ecritu)
    exclude_pairs = set()
    if args.exclude_plist:
        exclude_pairs = load_exclude_plist(args.exclude_plist)
    examples = collect_missing_examples(source_dict, ecritu_dict, args.limit, exclude_pairs)
    write_markdown(args.output, args.source, args.ecritu, examples)

    print(f"generated: {args.output}")
    print(f"example_count={len(examples)}")
    if args.exclude_plist:
        print(f"excluded_pairs={len(exclude_pairs)} from {args.exclude_plist}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
