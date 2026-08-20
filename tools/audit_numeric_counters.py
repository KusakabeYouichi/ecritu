#!/usr/bin/env python3
"""SudachiDict の品詞「助数詞可能」から、écritu の助数詞表に無い漢字表層を洗い出す。

従来の監査(Tests の testDiagnosticNumericCounterAudit)は**手書きの列挙**だった。
列挙にない助数詞は永久に検出されない。実際 もん(問) は載っておらず、
「2を確定してから もん」で 問 が7位という報告(2596)まで気づけなかった。

そこで権威ある出所として SudachiDict の生CSV(品詞細分類=助数詞可能)を使う。

**この検査の限界(重要)**:
  Sudachi も 問 を助数詞可能と付けていない(もん の助数詞は 文=足袋のサイズ だけ)。
  つまりこの検査でも もん は拾えない。網羅の保証にはならず、あくまで補助。
  逆に、出てくる語の多くは古い単位(咫/浬/斛/仞)や か条 の異表記で実用性が無い。
  → 出力は「候補一覧」であって、そのまま登録してはいけない。人が選ぶ前提。

使い方: python3 tools/audit_numeric_counters.py [--all]
  既定は実用的そうなものだけ(表層1〜2文字・カタカナ交じりを除く)に絞る。
"""
import argparse
import csv
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "tmp" / "sudachi_raw"
TABLE_SOURCE = ROOT / "KeyboardExtension" / "KanaKanjiConverter+CompoundDerivation.swift"
POS_COUNTER = "助数詞可能"


def katakana_to_hiragana(text):
    return "".join(
        chr(ord(c) - 0x60) if 0x30A1 <= ord(c) <= 0x30F6 else c for c in text
    )


def has_kanji(text):
    return any(0x4E00 <= ord(c) <= 0x9FFF for c in text)


def has_katakana(text):
    return any(0x30A1 <= ord(c) <= 0x30FA for c in text)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--all", action="store_true", help="絞り込みをせず全件出す")
    args = parser.parse_args()

    if not TABLE_SOURCE.exists():
        print(f"表のソースが見つかりません: {TABLE_SOURCE}", file=sys.stderr)
        return 1

    pairs = set()
    found_csv = False
    for edition in ("core", "small"):
        path = RAW / f"sudachidict_{edition}" / f"{edition}_lex.csv"
        if not path.exists():
            continue
        found_csv = True
        with open(path, encoding="utf-8") as handle:
            for row in csv.reader(handle):
                if len(row) <= 12 or row[7] != POS_COUNTER:
                    continue
                surface, reading = row[0], katakana_to_hiragana(row[11])
                if not has_kanji(surface):
                    continue
                if not re.fullmatch(r"[ぁ-ゖー]{1,5}", reading):
                    continue
                if not args.all:
                    # 実用性の低いものを落とす: 長い表層、カタカナ交じり(ヶ寺/カ年 等)
                    if len(surface) > 2 or has_katakana(surface):
                        continue
                pairs.add((reading, surface))

    if not found_csv:
        print(f"SudachiDict の生CSVが見つかりません: {RAW}", file=sys.stderr)
        return 1

    source = TABLE_SOURCE.read_text(encoding="utf-8")
    registered = set(re.findall(r'"([ぁ-ゖー]+)":\s*\[', source))

    missing = {}
    for reading, surface in pairs:
        if reading in registered:
            continue
        missing.setdefault(reading, []).append(surface)

    print(f"助数詞可能(漢字表層) {len(pairs)}件 / 表に無い読み {len(missing)}件")
    print("読み\t表層")
    for reading in sorted(missing):
        print(f"{reading}\t{'/'.join(sorted(missing[reading]))}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
