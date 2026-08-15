#!/usr/bin/env python3
"""LM実勢と辞書順の乖離が大きい読みを抽出する(機械的チェックの第1段)。

げんかい/いがい/じょうず型(rank0 の unigram が同読みの最良 unigram より大きく劣る、
または rank0 が LM 未収録)を sqlite から一括抽出し、TSV に書き出す。
第2段はテスト側で実変換に通し、LM 最良候補が上位に出ない読みだけを NG として残す
(短spanフロア/昇格/seed 等の実行時機構で救済済みのものを除くため)。

出力: tmp/lm_rank_mismatch.tsv (reading \t best_surface \t best_uni \t top \t top_uni \t gap)
使い方: python3 tools/audit_lm_rank_mismatch.py [--min-gap 1200] [--max-best-uni 6800]
"""
import argparse
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB = ROOT / "tmp" / "kana_kanji_dictionary.sqlite"
OUT = ROOT / "tmp" / "lm_rank_mismatch.tsv"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--min-gap", type=int, default=1200,
                        help="rank0 と最良の unigram 差の下限(rank0 が LM 未収録なら無条件)")
    parser.add_argument("--max-best-uni", type=int, default=6800,
                        help="最良候補の unigram 上限(常用語に限る)")
    args = parser.parse_args()

    con = sqlite3.connect(DB)
    rows = con.execute(
        """
        WITH uni AS (
          SELECT d.reading, d.rank, d.candidate, u.cost
          FROM dictionary_entries d
          JOIN word_lm_unigram u ON u.surface = d.candidate
          -- 読み跨ぎの誤期待(宇宙=たかおき 等の人名読みハーベスト)を除くため、
          -- この読みが表層の主読み(word_cost が全読み最安に近い)である候補に限る
          JOIN word_costs w ON w.reading = d.reading AND w.candidate = d.candidate
          JOIN candidate_min_word_costs m ON m.candidate = d.candidate
          WHERE length(d.reading) >= 2
            AND w.cost - m.min_cost <= 500
        ),
        r0 AS (
          SELECT d.reading, d.candidate AS top, u.cost AS top_uni
          FROM dictionary_entries d
          LEFT JOIN word_lm_unigram u ON u.surface = d.candidate
          WHERE d.rank = 0
        ),
        best AS (
          SELECT reading,
                 (SELECT candidate FROM uni u2
                   WHERE u2.reading = uni.reading ORDER BY cost, rank LIMIT 1) AS best_surface,
                 MIN(cost) AS best_uni
          FROM uni
          GROUP BY reading
        )
        SELECT r0.reading, best.best_surface, best.best_uni,
               r0.top, r0.top_uni,
               COALESCE(r0.top_uni, 99999) - best.best_uni AS gap
        FROM r0
        JOIN best ON best.reading = r0.reading
        WHERE best.best_uni <= ?
          AND (r0.top_uni IS NULL OR r0.top_uni - best.best_uni >= ?)
          AND r0.top != best.best_surface
        ORDER BY gap DESC
        """,
        (args.max_best_uni, args.min_gap),
    ).fetchall()

    with OUT.open("w", encoding="utf-8") as f:
        for reading, best_surface, best_uni, top, top_uni, gap in rows:
            f.write(f"{reading}\t{best_surface}\t{best_uni}\t{top}\t{top_uni or ''}\t{gap}\n")

    print(f"{len(rows)}件 → {OUT}")


if __name__ == "__main__":
    main()
