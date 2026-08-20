#!/usr/bin/env python3
"""お/ご+名詞の素通り合成で先頭候補が不自然になる読みを洗い出す。

お菓子(おかし)/お盆(おぼん)と同じ亜型を機械的に見つける。両者の共通点:

  1. フル読み(おかし/おぼん)に「お/ご/御 で始まらない漢字語」が無い
     → politePrefixPassthroughCandidates の素通り合成が発火する条件
     (KanaKanjiConverter+PostfixDerivation.swift の fullReadingHasStandaloneWord)
  2. 現代正書の複合形(お菓子/お盆)が辞書にも LM にも無い
  3. 語幹の読み(かし/ぼん)で、読み別 word_cost の最安漢字が
     LM unigram の最頻出漢字と食い違う。しかも差が僅か
     (盆7453 と 梵7407 の差は46、器具/危惧 の亜型と同じ構図)

→ 合成は word_cost 順を継ぐので、レアな漢字(お梵)が先頭に立つ。

使い方: python3 tools/audit_polite_prefix_order.py [--limit N]
"""
import argparse
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB = ROOT / "tmp" / "kana_kanji_dictionary.sqlite"
PREFIXES = ("お", "ご")
# 語幹が短すぎると同音異義が多すぎて雑音になる。長すぎる読みは合成が起きにくい。
MIN_STEM = 2
MAX_STEM = 4
# word_cost の差がこれ以下なら「僅差=コストが判断材料にならない」とみなす
NEAR_TIE = 900


def has_kanji(text):
    return any(
        0x4E00 <= ord(c) <= 0x9FFF or 0x3400 <= ord(c) <= 0x4DBF or c == "々"
        for c in text
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--limit", type=int, default=0, help="出力件数の上限(0=無制限)")
    args = parser.parse_args()

    if not DB.exists():
        print(f"辞書が見つかりません: {DB}", file=sys.stderr)
        return 1

    db = sqlite3.connect(DB)

    # 語幹読み -> [(candidate, wc)] / 表層 -> unigram
    unigram = dict(db.execute("SELECT surface, cost FROM word_lm_unigram"))

    findings = []
    # お/ご で始まる読みを走査する。dictionary_entries の読みを母集団にする
    # (実際に入力されうる読みだけを見る)。
    for prefix in PREFIXES:
        readings = [
            r
            for (r,) in db.execute(
                "SELECT DISTINCT reading FROM dictionary_entries WHERE reading LIKE ?",
                (prefix + "%",),
            )
        ]
        for full in readings:
            stem = full[len(prefix):]
            if not (MIN_STEM <= len(stem) <= MAX_STEM):
                continue

            # 条件1: フル読みに お/ご/御 始まりでない漢字語があると素通り合成は起きない
            full_candidates = [
                c
                for (c,) in db.execute(
                    "SELECT candidate FROM dictionary_entries WHERE reading=?", (full,)
                )
            ]
            if any(
                has_kanji(c) and not c.startswith(("お", "ご", "御")) and has_kanji(c[0])
                for c in full_candidates
            ):
                continue

            # 条件2: 現代正書の複合形(お+漢字)が辞書に無い
            if any(c.startswith(prefix) and has_kanji(c) for c in full_candidates):
                continue

            # 条件3: 語幹の word_cost 最安漢字と LM 最頻出漢字が食い違い、かつ僅差
            costs = [
                (c, wc)
                for (c, wc) in db.execute(
                    "SELECT candidate, cost FROM word_costs WHERE reading=? ORDER BY cost",
                    (stem,),
                )
                if has_kanji(c)
            ]
            if len(costs) < 2:
                continue

            cheapest, cheapest_wc = costs[0]
            # LM で最も頻出(cost 最小)の漢字表層
            scored = [(c, unigram[c]) for c, _ in costs if c in unigram]
            if not scored:
                continue
            lm_best, lm_best_cost = min(scored, key=lambda x: x[1])
            if lm_best == cheapest:
                continue

            lm_best_wc = dict(costs).get(lm_best)
            if lm_best_wc is None:
                continue
            gap = lm_best_wc - cheapest_wc
            if gap > NEAR_TIE:
                continue

            # 収穫ジャンク(レア人名・地名)の排除。wc が底値帯の語は「お」を付けて
            # 入力されることがまずないので、見ても判断材料にならない。
            if cheapest_wc >= 9000:
                continue
            # 語幹が常用語であること。LM 最頻出漢字の unigram が重い語は日常入力に出ない。
            if lm_best_cost > 7000:
                continue

            findings.append(
                {
                    "full": full,
                    "current": prefix + cheapest,
                    "expected": prefix + lm_best,
                    "wc_gap": gap,
                    "cheapest_wc": cheapest_wc,
                    "lm_best_wc": lm_best_wc,
                    "lm_best_uni": lm_best_cost,
                    "cheapest_uni": unigram.get(cheapest, "なし"),
                }
            )

    # 差が小さいほど「偶然の逆転」で危ないので昇順に
    findings.sort(key=lambda f: f["wc_gap"])
    if args.limit:
        findings = findings[: args.limit]

    print(f"{len(findings)} 件")
    print("読み\t現在の先頭(推定)\t望ましい先頭(推定)\twc差\twc(現/望)\tuni(現/望)")
    for f in findings:
        print(
            f"{f['full']}\t{f['current']}\t{f['expected']}\t{f['wc_gap']}"
            f"\t{f['cheapest_wc']}/{f['lm_best_wc']}"
            f"\t{f['cheapest_uni']}/{f['lm_best_uni']}"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
