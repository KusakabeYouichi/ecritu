#!/usr/bin/env python3
"""Build a SQLite kana-kanji index from one or more JSON dictionaries.

This tool merges multiple reading->candidates JSON files and writes a compact
SQLite database for on-demand lookup on device.

Expected JSON inputs:
- vocab JSON: {"reading": ["candidate1", "candidate2", ...]}
- sources JSON: {"reading": {"candidate": ["normalized", "surface"]}}
- inflections JSON (either format):
  - {"reading": {"candidate": "inflection-class"}}
  - {"reading": [{"candidate": "...", "inflectionClass": "..."}, ...]}
"""

from __future__ import annotations

import argparse
import json
import sqlite3
from pathlib import Path
from typing import Dict, Iterable, List, Set, Tuple


ALLOWED_SOURCES = {"normalized", "surface"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build kana-kanji SQLite index")
    parser.add_argument(
        "--vocab-json",
        action="append",
        required=True,
        help="Path to reading->candidates JSON (repeatable)",
    )
    parser.add_argument(
        "--sources-json",
        action="append",
        default=[],
        help="Optional reading->candidate->sourceTags JSON (repeatable)",
    )
    parser.add_argument(
        "--inflections-json",
        action="append",
        default=[],
        help="Optional reading->candidate inflection JSON (repeatable)",
    )
    parser.add_argument(
        "--output",
        required=True,
        help="Output SQLite file path",
    )
    return parser.parse_args()


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def merge_vocab(paths: Iterable[Path]) -> Dict[str, List[str]]:
    merged: Dict[str, List[str]] = {}

    for path in paths:
        obj = load_json(path)
        if not isinstance(obj, dict):
            raise ValueError(f"{path} must be an object")

        for reading, raw_candidates in obj.items():
            if not isinstance(reading, str):
                continue
            if not isinstance(raw_candidates, list):
                continue

            existing = merged.get(reading, [])
            seen = set(existing)

            for raw_candidate in raw_candidates:
                if not isinstance(raw_candidate, str):
                    continue
                candidate = raw_candidate.strip()
                if not candidate or candidate in seen:
                    continue
                existing.append(candidate)
                seen.add(candidate)

            if existing:
                merged[reading] = existing

    return merged


def merge_sources(paths: Iterable[Path]) -> Dict[str, Dict[str, Set[str]]]:
    merged: Dict[str, Dict[str, Set[str]]] = {}

    for path in paths:
        obj = load_json(path)
        if not isinstance(obj, dict):
            raise ValueError(f"{path} must be an object")

        for reading, raw_candidate_map in obj.items():
            if not isinstance(reading, str):
                continue
            if not isinstance(raw_candidate_map, dict):
                continue

            candidate_map = merged.setdefault(reading, {})

            for candidate, raw_sources in raw_candidate_map.items():
                if not isinstance(candidate, str):
                    continue
                if not isinstance(raw_sources, list):
                    continue

                sources = candidate_map.setdefault(candidate.strip(), set())

                for raw_source in raw_sources:
                    if isinstance(raw_source, str) and raw_source in ALLOWED_SOURCES:
                        sources.add(raw_source)

                if not sources:
                    candidate_map.pop(candidate.strip(), None)

            if not candidate_map:
                merged.pop(reading, None)

    return merged


def parse_inflection_entries(raw_value) -> Iterable[Tuple[str, str]]:
    if isinstance(raw_value, dict):
        for candidate, inflection_class in raw_value.items():
            if not isinstance(candidate, str):
                continue
            if not isinstance(inflection_class, str):
                continue
            yield candidate.strip(), inflection_class.strip()
        return

    if isinstance(raw_value, list):
        for entry in raw_value:
            if not isinstance(entry, dict):
                continue

            raw_candidate = entry.get("candidate")
            raw_class = entry.get("inflectionClass")
            if raw_class is None:
                raw_class = entry.get("inflection_class")

            if not isinstance(raw_candidate, str):
                continue
            if not isinstance(raw_class, str):
                continue

            yield raw_candidate.strip(), raw_class.strip()


def merge_inflections(paths: Iterable[Path]) -> Dict[str, Dict[str, str]]:
    merged: Dict[str, Dict[str, str]] = {}

    for path in paths:
        obj = load_json(path)
        if not isinstance(obj, dict):
            raise ValueError(f"{path} must be an object")

        for reading, raw_entries in obj.items():
            if not isinstance(reading, str):
                continue

            candidate_map = merged.setdefault(reading, {})

            for candidate, inflection_class in parse_inflection_entries(raw_entries):
                if not candidate or not inflection_class:
                    continue
                candidate_map[candidate] = inflection_class

            if not candidate_map:
                merged.pop(reading, None)

    return merged


def build_sqlite(
    output_path: Path,
    vocab: Dict[str, List[str]],
    sources: Dict[str, Dict[str, Set[str]]],
    inflections: Dict[str, Dict[str, str]],
) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    if output_path.exists():
        output_path.unlink()

    conn = sqlite3.connect(str(output_path))
    try:
        conn.execute("PRAGMA journal_mode=OFF")
        conn.execute("PRAGMA synchronous=OFF")
        conn.execute("PRAGMA temp_store=MEMORY")

        conn.executescript(
            """
            CREATE TABLE dictionary_entries (
                reading TEXT NOT NULL,
                candidate TEXT NOT NULL,
                rank INTEGER NOT NULL,
                PRIMARY KEY (reading, candidate)
            );

            CREATE INDEX idx_dictionary_entries_reading_rank
                ON dictionary_entries (reading, rank);

            CREATE TABLE candidate_sources (
                reading TEXT NOT NULL,
                candidate TEXT NOT NULL,
                source TEXT NOT NULL,
                PRIMARY KEY (reading, candidate, source)
            );

            CREATE INDEX idx_candidate_sources_lookup
                ON candidate_sources (reading, candidate);

            CREATE TABLE inflection_classes (
                reading TEXT NOT NULL,
                candidate TEXT NOT NULL,
                inflection_class TEXT NOT NULL,
                PRIMARY KEY (reading, candidate)
            );

            CREATE INDEX idx_inflection_classes_lookup
                ON inflection_classes (reading, candidate);
            """
        )

        dictionary_rows: List[Tuple[str, str, int]] = []
        dictionary_candidate_set: Dict[str, Set[str]] = {}

        for reading in sorted(vocab.keys()):
            candidates = vocab[reading]
            dictionary_candidate_set[reading] = set(candidates)
            for rank, candidate in enumerate(candidates):
                dictionary_rows.append((reading, candidate, rank))

        conn.executemany(
            "INSERT INTO dictionary_entries(reading, candidate, rank) VALUES (?, ?, ?)",
            dictionary_rows,
        )

        source_rows: List[Tuple[str, str, str]] = []
        for reading, candidate_map in sources.items():
            allowed_candidates = dictionary_candidate_set.get(reading)
            if not allowed_candidates:
                continue

            for candidate, source_set in candidate_map.items():
                if candidate not in allowed_candidates:
                    continue
                for source in sorted(source_set):
                    source_rows.append((reading, candidate, source))

        if source_rows:
            conn.executemany(
                "INSERT INTO candidate_sources(reading, candidate, source) VALUES (?, ?, ?)",
                source_rows,
            )

        inflection_rows: List[Tuple[str, str, str]] = []
        for reading, candidate_map in inflections.items():
            allowed_candidates = dictionary_candidate_set.get(reading)
            if not allowed_candidates:
                continue

            for candidate, inflection_class in candidate_map.items():
                if candidate not in allowed_candidates:
                    continue
                inflection_rows.append((reading, candidate, inflection_class))

        if inflection_rows:
            conn.executemany(
                "INSERT INTO inflection_classes(reading, candidate, inflection_class) VALUES (?, ?, ?)",
                inflection_rows,
            )

        conn.commit()

        print(f"wrote sqlite: {output_path}")
        print(f"readings={len(vocab)}")
        print(f"dictionary_rows={len(dictionary_rows)}")
        print(f"source_rows={len(source_rows)}")
        print(f"inflection_rows={len(inflection_rows)}")
    finally:
        conn.close()


def main() -> int:
    args = parse_args()

    vocab_paths = [Path(path) for path in args.vocab_json]
    source_paths = [Path(path) for path in args.sources_json]
    inflection_paths = [Path(path) for path in args.inflections_json]

    for path in vocab_paths + source_paths + inflection_paths:
        if not path.exists():
            raise FileNotFoundError(path)

    vocab = merge_vocab(vocab_paths)
    sources = merge_sources(source_paths)
    inflections = merge_inflections(inflection_paths)

    build_sqlite(
        output_path=Path(args.output),
        vocab=vocab,
        sources=sources,
        inflections=inflections,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
