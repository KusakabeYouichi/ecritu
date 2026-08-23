#!/usr/bin/env python3
"""単漢字+付属語断片の辞書語跨ぎスキャン第1段(けんない=県内の一般化。2634)。

まで/から/だけ/など/ない で終わる読みの辞書語(LM実在)を抽出する。
断片合成(単漢字+付属語)のチャネル累積が辞書直候補を跨ぐと、県内 が 剣ない に
負ける型の不具合になる。第2段(SWEEP_FRAGMENT=1)で実変換に通し、
辞書語が上位2位に出ない読みだけを NG として残す。

出力: tmp/fragment_undercut.tsv (reading \t word \t rank \t uni)
"""
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB = ROOT / "tmp" / "kana_kanji_dictionary.sqlite"
OUT = ROOT / "tmp" / "fragment_undercut.tsv"

SUFFIXES = ("まで", "から", "だけ", "など", "ない")


def main() -> None:
    con = sqlite3.connect(DB)
    rows = con.execute(
        """
        SELECT d.reading, d.candidate, d.rank, u.cost FROM dictionary_entries d
        JOIN word_lm_unigram u ON u.surface = d.candidate
        WHERE d.rank <= 3 AND length(d.reading) >= 4 AND u.cost <= 6800
        ORDER BY u.cost
        """
    ).fetchall()
    best: dict[str, tuple[str, int, int]] = {}
    for reading, candidate, rank, cost in rows:
        if not reading.endswith(SUFFIXES):
            continue
        if reading not in best or cost < best[reading][2]:
            best[reading] = (candidate, rank, cost)
    with OUT.open("w", encoding="utf-8") as f:
        for reading in sorted(best, key=lambda r: best[r][2]):
            candidate, rank, cost = best[reading]
            f.write(f"{reading}\t{candidate}\t{rank}\t{cost}\n")
    print(f"{len(best)} readings -> {OUT}")


if __name__ == "__main__":
    main()
