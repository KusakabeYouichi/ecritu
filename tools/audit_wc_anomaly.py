#!/usr/bin/env python3
"""word_costs 異常高・欠落の常用語スキャン第1段(優先/縞模様の一般化。2634)。

LM unigram が常用圏(≤6000)なのに word_costs が異常高(≥8000)または欠落している
辞書語を抽出する。データ品質系の埋没(変換で常用語が沈む)の候補。
第2段(SWEEP_WC=1)で実変換に通し、上位2位に出ない読みだけを NG として残す。

出力: tmp/wc_anomaly.tsv (reading \t word \t uni \t wc[または-])
"""
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB = ROOT / "tmp" / "kana_kanji_dictionary.sqlite"
OUT = ROOT / "tmp" / "wc_anomaly.tsv"


def main() -> None:
    con = sqlite3.connect(DB)
    # 主読みガード: レア読み(はじめ→元 等の人名ハーベスト)は辞書が正しく下げて
    # いるので対象外。wc高型は「その読みが候補の最安読み」に限り、欠落型は
    # 「候補が word_costs に一切無い」に限る
    rows = con.execute(
        """
        SELECT d.reading, d.candidate, u.cost, w.cost
        FROM dictionary_entries d
        JOIN word_lm_unigram u ON u.surface = d.candidate
        LEFT JOIN word_costs w ON w.reading = d.reading AND w.candidate = d.candidate
        LEFT JOIN candidate_min_word_costs m ON m.candidate = d.candidate
        WHERE u.cost <= 6000 AND length(d.reading) >= 2 AND d.rank <= 3
          AND (
            (w.cost IS NOT NULL AND w.cost >= 8000 AND w.cost - m.min_cost <= 500)
            OR (w.cost IS NULL AND m.candidate IS NULL)
          )
        ORDER BY u.cost
        """
    ).fetchall()
    best: dict[str, tuple[str, int, object]] = {}
    for reading, candidate, uni, wc in rows:
        if reading not in best or uni < best[reading][1]:
            best[reading] = (candidate, uni, wc)
    with OUT.open("w", encoding="utf-8") as f:
        for reading in sorted(best, key=lambda r: best[r][1]):
            candidate, uni, wc = best[reading]
            f.write(f"{reading}\t{candidate}\t{uni}\t{wc if wc is not None else '-'}\n")
    print(f"{len(best)} readings -> {OUT}")


if __name__ == "__main__":
    main()
