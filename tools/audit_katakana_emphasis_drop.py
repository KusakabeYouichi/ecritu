#!/usr/bin/env python3
"""カタカナ強調フィルタ誤爆スキャンの第1段(タイ/ルイの一般化。2634)。

辞書 rank≤2 のカタカナ表層のうち LM に実在する語(国名・人名・外来語)を抽出する。
強調フィルタは「表層をかな化すると読みに一致するカタカナ」を抑制するため、
辞書上位のカタカナ実語が候補から消えることがある(タイ=国名 rank1、ルイ=人名 rank2)。
第2段はテスト側(SWEEP_KATAKANA=1)で実変換に通し、候補リストから完全に消えている
読みだけを NG として残す(seed 掲載などで免除済みのものを除くため)。

出力: tmp/katakana_emphasis_drop.tsv (reading \t katakana \t rank \t uni)
使い方: python3 tools/audit_katakana_emphasis_drop.py [--max-uni 6000]
"""
import argparse
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB = ROOT / "tmp" / "kana_kanji_dictionary.sqlite"
OUT = ROOT / "tmp" / "katakana_emphasis_drop.tsv"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--max-uni", type=int, default=6000,
                        help="カタカナ表層の unigram 上限(実語らしさの下限)")
    args = parser.parse_args()

    con = sqlite3.connect(DB)
    rows = con.execute(
        """
        SELECT d.reading, d.candidate, d.rank, u.cost
        FROM dictionary_entries d
        JOIN word_lm_unigram u ON u.surface = d.candidate
        WHERE d.rank <= 2
          AND length(d.reading) >= 2
          AND d.candidate GLOB '*[ア-ヺー]*'
          AND d.candidate NOT GLOB '*[^ア-ヺー]*'
          AND u.cost <= ?
        ORDER BY u.cost
        """,
        (args.max_uni,),
    ).fetchall()

    # 同一読みに複数のカタカナ候補があれば unigram 最良のみ残す
    best: dict[str, tuple[str, int, int]] = {}
    for reading, candidate, rank, cost in rows:
        if reading not in best or cost < best[reading][2]:
            best[reading] = (candidate, rank, cost)

    with OUT.open("w", encoding="utf-8") as f:
        for reading in sorted(best, key=lambda r: best[r][2]):
            candidate, rank, cost = best[reading]
            f.write(f"{reading}\t{candidate}\t{rank}\t{cost}\n")
    print(f"{len(best)} readings -> {OUT}")


if __name__ == "__main__":
    main()
