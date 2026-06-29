#!/usr/bin/env python3
"""Build a compact kana->candidate JSON index from Sudachi dictionary CSV sources.

Supported inputs:
- Sudachi raw lexicon CSV (core_lex.csv / small_lex.csv / notcore_lex.csv)
- Other CSV-like lexicon rows (heuristic fallback)

For Sudachi raw lexicon CSV (19 columns), this script uses:
- cost column: index 3
- POS column: index 5
- inflection type column: index 9
- reading column: index 11
- normalized form column: index 12
- surface fallback: index 4 then index 0

Usage:
    python tools/build_sudachi_index.py \
        --input-glob "tmp/sudachi_raw/core_lex/**/*.csv" \
    --output tmp/ÉcrituPremierVocab.json
"""

from __future__ import annotations

import argparse
import csv
import glob
import json
import os
import re
import unicodedata
from collections import defaultdict
from typing import Dict, Iterable, List, Optional, Set, Tuple


SUDACHI_READING_INDEX = 11
SUDACHI_NORMALIZED_INDEX = 12
SUDACHI_SURFACE_FALLBACK_INDEX = 4
SUDACHI_LEFT_ID_INDEX = 1
SUDACHI_RIGHT_ID_INDEX = 2
SUDACHI_COST_INDEX = 3
SUDACHI_POS_INDEX = 5
SUDACHI_INFLECTION_TYPE_INDEX = 9

# 活用語の品詞(動詞・形容詞)。誤読みの活用パラダイムが波及するため、
# 非連接エントリ(left_id=right_id=-1)ではこれらを収穫対象から除外する。
INFLECTING_POS_PREFIXES = ("動詞", "形容詞")

UNKNOWN_COST_SENTINEL = 10**9

SOURCE_TAG_NORMALIZED = "normalized"
SOURCE_TAG_SURFACE = "surface"
SOURCE_TAG_ADJECTIVE_GARU = "adjective-garu"

CANDIDATE_POLICY_NORMALIZED = "normalized"
CANDIDATE_POLICY_SURFACE = "surface"
CANDIDATE_POLICY_BOTH = "both"

KIGOU_READING = "きごう"
UNICODE_ESCAPE_PATTERN = re.compile(r"\\u([0-9a-fA-F]{4})")
KAOMOJI_BRACKET_PATTERN = re.compile(r"(?:\\u0028|\\u0029|[()（）［］｛｝])")
ASCII_EMOTICON_PATTERN = re.compile(r"^[><^;:_\-~@oO0|/\\.]+$")


def extract_inflection_class(row: List[str], reading: str, candidate: str) -> Optional[str]:
    pos = row[SUDACHI_POS_INDEX].strip() if len(row) > SUDACHI_POS_INDEX else ""
    inflection_type = row[SUDACHI_INFLECTION_TYPE_INDEX].strip() if len(row) > SUDACHI_INFLECTION_TYPE_INDEX else ""
    pos_details = [
        value.strip()
        for value in row[SUDACHI_POS_INDEX:SUDACHI_INFLECTION_TYPE_INDEX]
        if value.strip() and value.strip() != "*"
    ]

    if any("サ変可能" in value for value in pos_details):
        return "suru"

    if "サ行変格" in inflection_type or "サ変" in inflection_type:
        return "suru"

    if "カ行変格" in inflection_type or "カ変" in inflection_type:
        return "kuru"

    if "一段" in inflection_type:
        return "ichidan"

    if "五段" in inflection_type:
        if "カ行" in inflection_type:
            return "godan-ku"
        if "ガ行" in inflection_type:
            return "godan-gu"
        if "サ行" in inflection_type:
            return "godan-su"
        if "タ行" in inflection_type:
            return "godan-tsu"
        if "ナ行" in inflection_type:
            return "godan-nu"
        if "バ行" in inflection_type:
            return "godan-bu"
        if "マ行" in inflection_type:
            return "godan-mu"
        if "ラ行" in inflection_type:
            return "godan-ru"
        if "ワ" in inflection_type or "ア行" in inflection_type:
            return "godan-u"

        if reading.endswith("う") and candidate.endswith("う"):
            return "godan-u"

    if "形容詞" in pos or "形容詞" in inflection_type:
        if reading.endswith("い") and candidate.endswith("い"):
            return "adjective-i"

    # Fallback for normalized forms where inflection type is omitted.
    if candidate.endswith("する"):
        return "suru"

    if candidate.endswith("来る") or candidate.endswith("くる"):
        return "kuru"

    return None


def katakana_to_hiragana(text: str) -> str:
    chars: List[str] = []
    for ch in text:
        code = ord(ch)
        if 0x30A1 <= code <= 0x30F6:
            chars.append(chr(code - 0x60))
        elif 0x3040 <= code <= 0x309F or code == 0x30FC:
            chars.append(ch)
    return "".join(chars)


def is_hiragana_like(text: str) -> bool:
    if not text:
        return False

    for ch in text:
        code = ord(ch)
        if (0x3040 <= code <= 0x309F) or code == 0x30FC:
            continue
        return False

    return True


def is_kana_like(text: str) -> bool:
    if not text:
        return False
    has_kana = False
    for ch in text:
        code = ord(ch)
        if (0x3040 <= code <= 0x309F) or (0x30A0 <= code <= 0x30FF) or code == 0x30FC:
            has_kana = True
            continue
        return False
    return has_kana


def normalize_candidate(text: str) -> str:
    return text.strip()


def decode_unicode_escape_sequences(text: str) -> str:
    def replace(match: re.Match[str]) -> str:
        return chr(int(match.group(1), 16))

    return UNICODE_ESCAPE_PATTERN.sub(replace, text)


def contains_japanese_script(text: str) -> bool:
    for ch in text:
        code = ord(ch)
        if (0x3040 <= code <= 0x30FF) or (0x3400 <= code <= 0x9FFF):
            return True
    return False


def contains_kanji(text: str) -> bool:
    for ch in text:
        code = ord(ch)
        if 0x3400 <= code <= 0x9FFF:
            return True
    return False


def is_kigou_kaomoji_candidate(candidate: str) -> bool:
    expanded = decode_unicode_escape_sequences(candidate)

    if len(expanded) < 2:
        return False

    if expanded.lower() in {"orz", "otz"}:
        return True

    has_bracket = bool(KAOMOJI_BRACKET_PATTERN.search(candidate) or KAOMOJI_BRACKET_PATTERN.search(expanded))

    if has_bracket and len(expanded) >= 3:
        return True

    if len(expanded) <= 8 and ASCII_EMOTICON_PATTERN.fullmatch(expanded):
        return True

    if len(expanded) <= 8 and not contains_kanji(expanded) and not is_kana_like(expanded):
        has_symbol = any(unicodedata.category(ch)[0] in {"P", "S"} for ch in expanded)
        if has_symbol:
            return True

    return False


def should_exclude_candidate_for_reading(reading: str, candidate: str) -> bool:
    if reading != KIGOU_READING:
        return False

    return is_kigou_kaomoji_candidate(candidate)


def is_disconnected_inflecting_row(row: List[str]) -> bool:
    """Sudachiが単独トークン化しない非連接エントリ(left_id=right_id=-1)のうち、
    活用語(動詞・形容詞)を判定する。

    非連接エントリは旧仮名遣い・文語形などを古文照合用に保持したもので、
    連接行列に載らず通常解析には出力されない。活用語をここから収穫すると、
    誤読み(例: 惚れる→トレル)の活用形が一括で語彙に紛れ込むため除外する。
    名詞(地名・固有名詞)は単独で無害かつ必要なので除外しない。"""
    if len(row) <= SUDACHI_RIGHT_ID_INDEX:
        return False

    if row[SUDACHI_LEFT_ID_INDEX].strip() != "-1" or row[SUDACHI_RIGHT_ID_INDEX].strip() != "-1":
        return False

    pos = row[SUDACHI_POS_INDEX].strip() if len(row) > SUDACHI_POS_INDEX else ""
    return pos.startswith(INFLECTING_POS_PREFIXES)


def is_valid_single_reading_candidate(
    reading: str,
    candidate: str,
    max_candidate_len: int,
) -> bool:
    if len(candidate) > max_candidate_len:
        return False

    if is_kana_like(candidate):
        # 1文字読みでは、かな候補を同音同形に限定してノイズを抑える。
        return katakana_to_hiragana(candidate) == reading

    return True


def extract_reading(row: List[str]) -> Optional[str]:
    if len(row) > SUDACHI_READING_INDEX:
        reading = row[SUDACHI_READING_INDEX].strip()
        if is_kana_like(reading):
            hira = katakana_to_hiragana(reading)
            if hira:
                return hira

    for cell in row:
        value = cell.strip()
        if is_kana_like(value):
            hira = katakana_to_hiragana(value)
            if hira:
                return hira

    return None


def extract_normalized_candidate(row: List[str]) -> Optional[str]:
    if len(row) > SUDACHI_NORMALIZED_INDEX:
        normalized = normalize_candidate(row[SUDACHI_NORMALIZED_INDEX])
        if normalized and normalized != "*":
            return normalized

    return None


def extract_surface_candidate(row: List[str]) -> Optional[str]:
    if not row:
        return None

    if len(row) > SUDACHI_SURFACE_FALLBACK_INDEX:
        fallback_surface = normalize_candidate(row[SUDACHI_SURFACE_FALLBACK_INDEX])
        if fallback_surface and fallback_surface != "*":
            return fallback_surface

    surface = normalize_candidate(row[0])
    fallback = surface if surface else None

    # Prefer non-empty normalized-like fields near tail.
    for value in reversed(row[1:]):
        value = normalize_candidate(value)
        if not value:
            continue
        if value == "*":
            continue
        if is_kana_like(value):
            continue
        return value

    return fallback


def extract_cost(row: List[str]) -> Optional[int]:
    if len(row) <= SUDACHI_COST_INDEX:
        return None

    raw_cost = row[SUDACHI_COST_INDEX].strip()

    if not raw_cost or raw_cost == "*":
        return None

    try:
        return int(raw_cost)
    except ValueError:
        return None


def iter_csv_rows(paths: Iterable[str]) -> Iterable[List[str]]:
    for path in paths:
        with open(path, "r", encoding="utf-8") as f:
            reader = csv.reader(f)
            for row in reader:
                if not row:
                    continue
                if row[0].startswith("#"):
                    continue
                yield row


def load_adjective_garu_allowlist(path: Optional[str]) -> Dict[str, Set[str]]:
    if not path:
        return {}

    with open(path, "r", encoding="utf-8") as f:
        raw = json.load(f)

    if not isinstance(raw, dict):
        raise ValueError("adjective-garu allowlist must be an object")

    allowlist: Dict[str, Set[str]] = {}

    for raw_reading, raw_candidates in raw.items():
        if not isinstance(raw_reading, str):
            continue

        reading = katakana_to_hiragana(raw_reading.strip())

        if not reading or not is_hiragana_like(reading):
            continue

        if not isinstance(raw_candidates, list):
            continue

        candidates: Set[str] = set()

        for raw_candidate in raw_candidates:
            if not isinstance(raw_candidate, str):
                continue

            candidate = normalize_candidate(raw_candidate)

            if candidate:
                candidates.add(candidate)

        if candidates:
            allowlist[reading] = candidates

    return allowlist


def build_index(
    paths: List[str],
    max_candidates: int,
    min_reading_len: int,
    max_reading_len: int,
    max_candidate_len: int,
    single_reading_max_candidates: int,
    single_reading_max_candidate_len: int,
    include_non_japanese_candidates: bool,
    require_kanji_candidate: bool,
    candidate_policy: str,
    adjective_garu_allowlist: Dict[str, Set[str]],
) -> Tuple[Dict[str, List[str]], Dict[str, Dict[str, str]], Dict[str, Dict[str, List[str]]]]:
    counters: Dict[str, Dict[str, int]] = defaultdict(lambda: defaultdict(int))
    cost_stats: Dict[str, Dict[str, Dict[str, int]]] = defaultdict(
        lambda: defaultdict(lambda: {"sum": 0, "count": 0, "min": UNKNOWN_COST_SENTINEL})
    )
    class_counters: Dict[str, Dict[str, Dict[str, int]]] = defaultdict(
        lambda: defaultdict(lambda: defaultdict(int))
    )
    source_counters: Dict[str, Dict[str, Dict[str, int]]] = defaultdict(
        lambda: defaultdict(lambda: defaultdict(int))
    )

    include_normalized = candidate_policy in (CANDIDATE_POLICY_NORMALIZED, CANDIDATE_POLICY_BOTH)
    include_surface = candidate_policy in (CANDIDATE_POLICY_SURFACE, CANDIDATE_POLICY_BOTH)

    for row in iter_csv_rows(paths):
        inflection_type = (
            row[SUDACHI_INFLECTION_TYPE_INDEX].strip()
            if len(row) > SUDACHI_INFLECTION_TYPE_INDEX
            else ""
        )
        # 文語(古語・古典)動詞は除外。現代語の活用派生規則と合わず、
        # 例: 伸ぶ(文語上二段-バ行)が「のんで→伸んで」と五段-バ行扱いで誤派生する。
        if "文語" in inflection_type:
            continue

        # 非連接(left_id=right_id=-1)の活用語は誤読みの活用形が紛れ込むため除外。
        if is_disconnected_inflecting_row(row):
            continue

        reading = extract_reading(row)
        normalized_candidate = extract_normalized_candidate(row)
        surface_candidate = extract_surface_candidate(row)
        candidate_cost = extract_cost(row)

        candidates_with_sources: Dict[str, Set[str]] = defaultdict(set)

        if include_normalized and normalized_candidate:
            candidates_with_sources[normalized_candidate].add(SOURCE_TAG_NORMALIZED)

        if include_surface and surface_candidate:
            candidates_with_sources[surface_candidate].add(SOURCE_TAG_SURFACE)

        if not reading or not candidates_with_sources:
            continue

        if not is_hiragana_like(reading):
            continue

        if len(reading) < min_reading_len:
            continue

        if len(reading) > max_reading_len:
            continue

        is_single_reading = len(reading) == 1

        for candidate, sources in candidates_with_sources.items():
            if len(candidate) > max_candidate_len:
                continue

            if should_exclude_candidate_for_reading(reading, candidate):
                continue

            if is_single_reading and not is_valid_single_reading_candidate(
                reading=reading,
                candidate=candidate,
                max_candidate_len=single_reading_max_candidate_len,
            ):
                continue

            if not include_non_japanese_candidates and not contains_japanese_script(candidate):
                continue

            if require_kanji_candidate and not contains_kanji(candidate):
                continue

            counters[reading][candidate] += 1

            if candidate_cost is not None:
                stats = cost_stats[reading][candidate]
                stats["sum"] += candidate_cost
                stats["count"] += 1
                stats["min"] = min(stats["min"], candidate_cost)

            for source in sources:
                source_counters[reading][candidate][source] += 1

            inflection_class = extract_inflection_class(row, reading, candidate)
            if inflection_class is not None:
                class_counters[reading][candidate][inflection_class] += 1

    index: Dict[str, List[str]] = {}
    for reading, cand_counter in counters.items():

        def candidate_sort_key(item: Tuple[str, int]) -> Tuple[int, int, float, int, int, str]:
            candidate, frequency = item
            stats = cost_stats[reading].get(candidate)

            if stats and stats["count"] > 0:
                has_no_cost = 0
                min_cost = stats["min"]
                avg_cost = stats["sum"] / stats["count"]
            else:
                has_no_cost = 1
                min_cost = UNKNOWN_COST_SENTINEL
                avg_cost = float(UNKNOWN_COST_SENTINEL)

            return (
                -frequency,
                has_no_cost,
                min_cost,
                avg_cost,
                len(candidate),
                candidate,
            )

        sorted_candidates = sorted(
            cand_counter.items(),
            key=candidate_sort_key,
        )
        per_reading_limit = max_candidates
        if len(reading) == 1:
            per_reading_limit = min(max_candidates, single_reading_max_candidates)

        index[reading] = [cand for cand, _ in sorted_candidates[:per_reading_limit]]

    inflection_index: Dict[str, Dict[str, str]] = {}
    for reading, candidates in index.items():
        reading_class_counter = class_counters.get(reading)
        if not reading_class_counter:
            continue

        candidate_map: Dict[str, str] = {}
        for candidate in candidates:
            class_counter = reading_class_counter.get(candidate)
            if not class_counter:
                continue

            inflection_class = sorted(
                class_counter.items(),
                key=lambda x: (-x[1], x[0]),
            )[0][0]
            candidate_map[candidate] = inflection_class

        if candidate_map:
            inflection_index[reading] = candidate_map

    candidate_source_index: Dict[str, Dict[str, List[str]]] = {}
    for reading, candidates in index.items():
        reading_source_counter = source_counters.get(reading)
        if not reading_source_counter:
            continue

        candidate_source_map: Dict[str, List[str]] = {}

        for candidate in candidates:
            source_counter = reading_source_counter.get(candidate)
            if not source_counter:
                continue

            sources: List[str] = []

            if source_counter.get(SOURCE_TAG_NORMALIZED, 0) > 0:
                sources.append(SOURCE_TAG_NORMALIZED)

            if source_counter.get(SOURCE_TAG_SURFACE, 0) > 0:
                sources.append(SOURCE_TAG_SURFACE)

            if sources:
                candidate_source_map[candidate] = sources

        if candidate_source_map:
            candidate_source_index[reading] = candidate_source_map

    for reading, allowed_candidates in adjective_garu_allowlist.items():
        inflection_map = inflection_index.get(reading)

        if not inflection_map:
            continue

        available_candidates = set(index.get(reading, []))
        metadata_map = candidate_source_index.setdefault(reading, {})

        for candidate in sorted(allowed_candidates):
            if candidate not in available_candidates:
                continue

            if inflection_map.get(candidate) != "adjective-i":
                continue

            sources = metadata_map.setdefault(candidate, [])

            if SOURCE_TAG_ADJECTIVE_GARU not in sources:
                sources.append(SOURCE_TAG_ADJECTIVE_GARU)

        if not metadata_map:
            candidate_source_index.pop(reading, None)

    return index, inflection_index, candidate_source_index


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build kana->candidate index from Sudachi CSV")
    parser.add_argument(
        "--input-glob",
        required=True,
        help="Glob pattern for Sudachi CSV files (example: sudachi/src/main/text/**/*.csv)",
    )
    parser.add_argument(
        "--output",
        required=True,
        help="Output JSON path",
    )
    parser.add_argument(
        "--output-inflections",
        help="Optional output path for reading->candidate->inflectionClass JSON",
    )
    parser.add_argument(
        "--output-sources",
        help="Output path for reading->candidate->[sourceTag] JSON",
    )
    parser.add_argument(
        "--adjective-garu-allowlist",
        help="Optional JSON path for adjective->garu allowlist (reading->candidates)",
    )
    parser.add_argument(
        "--candidate-policy",
        choices=[
            CANDIDATE_POLICY_NORMALIZED,
            CANDIDATE_POLICY_SURFACE,
            CANDIDATE_POLICY_BOTH,
        ],
        default=CANDIDATE_POLICY_BOTH,
        help="Candidate extraction policy (default: both)",
    )
    parser.add_argument(
        "--max-candidates",
        type=int,
        default=16,
        help="Max candidates to keep per reading",
    )
    parser.add_argument(
        "--min-reading-len",
        type=int,
        default=1,
        help="Minimum reading length to keep",
    )
    parser.add_argument(
        "--max-reading-len",
        type=int,
        default=12,
        help="Maximum reading length to keep",
    )
    parser.add_argument(
        "--max-candidate-len",
        type=int,
        default=24,
        help="Maximum candidate length to keep",
    )
    parser.add_argument(
        "--single-reading-max-candidates",
        type=int,
        default=21,
        help="Max candidates to keep for 1-character readings",
    )
    parser.add_argument(
        "--single-reading-max-candidate-len",
        type=int,
        default=1,
        help="Maximum candidate length to keep for 1-character readings",
    )
    parser.add_argument(
        "--include-non-japanese-candidates",
        action="store_true",
        help="Keep candidates that do not contain any Japanese script",
    )
    parser.add_argument(
        "--require-kanji-candidate",
        action="store_true",
        help="Keep only candidates containing at least one Kanji character",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    paths = sorted(glob.glob(args.input_glob, recursive=True))

    if not paths:
        print(f"No files matched: {args.input_glob}")
        return 1

    index, inflection_index, candidate_source_index = build_index(
        paths=paths,
        max_candidates=max(1, args.max_candidates),
        min_reading_len=max(1, args.min_reading_len),
        max_reading_len=max(1, args.max_reading_len),
        max_candidate_len=max(1, args.max_candidate_len),
        single_reading_max_candidates=max(1, args.single_reading_max_candidates),
        single_reading_max_candidate_len=max(1, args.single_reading_max_candidate_len),
        include_non_japanese_candidates=args.include_non_japanese_candidates,
        require_kanji_candidate=args.require_kanji_candidate,
        candidate_policy=args.candidate_policy,
        adjective_garu_allowlist=load_adjective_garu_allowlist(args.adjective_garu_allowlist),
    )

    os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(index, f, ensure_ascii=False, sort_keys=True)

    print(f"wrote {len(index)} readings -> {args.output}")
    single_reading_count = sum(1 for reading in index if len(reading) == 1)
    print(f"wrote {single_reading_count} single-character readings")

    output_sources = args.output_sources
    if output_sources is None:
        output_sources = os.path.join(
            os.path.dirname(args.output) or ".",
            "kana_kanji_candidate_sources.json",
        )

    os.makedirs(os.path.dirname(output_sources) or ".", exist_ok=True)
    with open(output_sources, "w", encoding="utf-8") as f:
        json.dump(candidate_source_index, f, ensure_ascii=False, sort_keys=True)
    print(f"wrote {len(candidate_source_index)} readings with source tags -> {output_sources}")

    if args.output_inflections:
        os.makedirs(os.path.dirname(args.output_inflections) or ".", exist_ok=True)
        with open(args.output_inflections, "w", encoding="utf-8") as f:
            json.dump(inflection_index, f, ensure_ascii=False, sort_keys=True)
        print(
            f"wrote {len(inflection_index)} readings with inflection classes -> {args.output_inflections}"
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
