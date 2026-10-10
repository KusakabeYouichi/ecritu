#!/usr/bin/env python3
"""頻度が極端に低い(語 LM に無い/底値帯の)候補が単文節の上位 3 位に入っている読みを抽出する(けいしょう型。3506)。

audit_lm_rank_mismatch.py は 1 位しか見ない(継承 が 1 位かつ LM 最良なので けいしょう は通過した)。
こちらは 2〜3 位も見て、「見たこともない語が上位 3 位に居て、その下にふつうの語がある」読みを拾う。
第 1 段(この sqlite 走査)の近似なので、第 2 段として testDumpSingleSegmentCandidates で実際の提示順に通し、
seed/抑制/curated/書きかえ/LM 1 位昇格で既に直っているものを落とすこと。

稀少の判定: 語 LM unigram が無い、または --rare 以上(底値帯)。主読みの門番(語コスト 全読み最安 +500)は
稀少側には使わない(物=もの/薬=やく のような常用語を稀少扱いにして雑音が増える)が、「下にあるふつうの語」側には
使う(じがた→地方、はらこ→原子 のように別読みの頻度を拾った語を「追い越されたふつうの語」に数えない)。人名(person_names の 姓/名)は ※ を付け、--ignore-names なら引き金にしない
(Wikipedia LM は固有名詞が過剰に強いので、LM 順を正解にしない)。
旧字体・異体字(scriptVariantToStandard)を含む候補と、かな識別・かな/カタカナだけの候補は提示近似から外す。
seed 掲載読みは人手で並べ済みなので対象外。

出力: tmp/rare_in_top3.tsv(--dump のときは tmp/rare_in_top3_presented.tsv)
  reading \t best_uni(その読みでいちばん普通の語の unigram) \t rare_in_top3 \t 上位 8(†=稀少、※=人名、[uni])
使い方: python3 tools/audit_rare_in_top3.py [--rare 8000] [--top 3] [--max-best-uni 8000]
第 2 段: 第 1 段の読み(tmp/rare_in_top3.tsv の 1 列目)を
  TEST_RUNNER_ECRITU_DUMP_TSV=readings.tsv TEST_RUNNER_ECRITU_DUMP_SURFACE=1 … testDumpSingleSegmentCandidates
に通し、その .out を --dump で渡すと、辞書順でなく実際の提示順(単文節上位 8)で同じ判定をし直す
"""
import argparse
import re
import sqlite3
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB = ROOT / "tmp" / "kana_kanji_dictionary.sqlite"
OUT = ROOT / "tmp" / "rare_in_top3.tsv"
SEED = ROOT / "KeyboardExtension" / "KanaKanjiSeedDictionary.swift"
FILTERS = ROOT / "KeyboardExtension" / "KanaKanjiConverter+SurfaceFilters.swift"

HIRAGANA = re.compile(r"^[ぁ-ゖー]+$")
KANJI = re.compile(r"[㐀-鿿豈-﫿]")


def seed_readings() -> set:
    text = SEED.read_text(encoding="utf-8")
    return set(re.findall(r'^\s*"([^"]+)":\s*\[', text, re.M))


def variant_characters() -> set:
    text = FILTERS.read_text(encoding="utf-8")
    start = text.index("static let scriptVariantToStandard")
    end = text.index("]", text.index("= [", start) + 3)
    block = text[start:end]
    # 1 文字キーだけ(複数文字の見出しは無い)
    return set(re.findall(r'"(.)":\s*\.init\(', block))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rare", type=int, default=8000, help="この unigram 以上(または未収録)を稀少とみなす")
    parser.add_argument("--top", type=int, default=3, help="稀少が入っていたら違和感とする順位")
    parser.add_argument("--max-best-uni", type=int, default=8000,
                        help="その読みでいちばん普通の語がこれより稀ならそもそも専門語の読みとして対象外")
    parser.add_argument("--show", type=int, default=8, help="出力に並べる上位の数")
    parser.add_argument("--min-reading", type=int, default=2, help="読みの最小かな数(2 かなは候補が多く別機構で並ぶので 3 以上を推奨)")
    parser.add_argument("--ignore-names", action="store_true", help="人名(姓/名)の稀少候補は引き金にしない")
    parser.add_argument("--dump", type=Path, help="testDumpSingleSegmentCandidates の .out(第 2 段: 実際の提示順で判定)")
    args = parser.parse_args()

    seeds = seed_readings()
    variants = variant_characters()
    con = sqlite3.connect(DB)
    unigram = dict(con.execute("SELECT surface, cost FROM word_lm_unigram"))
    min_cost = dict(con.execute("SELECT candidate, min_cost FROM candidate_min_word_costs"))
    entry_cost = {(r, c): cost for r, c, cost in con.execute("SELECT reading, candidate, cost FROM dictionary_entries")}
    names = defaultdict(set)
    for reading, candidate in con.execute("SELECT reading, candidate FROM person_names WHERE kind IN ('姓', '名')"):
        names[reading].add(candidate)

    by_reading = defaultdict(list)
    if args.dump:
        # DUMP \t reading \t keepKana \t 連文節 \t 単文節上位 8(1 列 1 候補)
        for line in args.dump.read_text(encoding="utf-8").splitlines():
            cols = line.split("\t")
            if len(cols) < 5 or cols[0] != "DUMP":
                continue
            for rank, candidate in enumerate(c for c in cols[4:] if c):
                by_reading[cols[1]].append((rank, candidate, None))
    else:
        rows = con.execute(
            "SELECT reading, rank, candidate, cost FROM dictionary_entries WHERE (sources & 1) != 0 ORDER BY reading, rank"
        )
        for reading, rank, candidate, cost in rows:
            by_reading[reading].append((rank, candidate, cost))

    def is_rare(candidate: str, reading: str) -> bool:
        uni = unigram.get(candidate)
        if uni is not None and uni < args.rare:
            return False
        if args.ignore_names and candidate in names.get(reading, ()):
            return False
        return True

    flagged = []
    for reading, entries in by_reading.items():
        if len(reading) < args.min_reading or not HIRAGANA.match(reading) or reading in seeds:
            continue
        shown = []
        for _, candidate, cost in entries:
            if candidate == reading or not KANJI.search(candidate):
                continue
            if any(ch in variants for ch in candidate):
                continue
            # --dump では活用派生・合成(勝つよう/来たい/方が)も並ぶ。辞書に無い表層は稀少の引き金にも
            # 追い越された語にもしない(unigram が無いのは合成だからで、見たこともない語ではない)
            if args.dump and (reading, candidate) not in entry_cost:
                continue
            shown.append((candidate, cost))
        if len(shown) < 2:
            continue
        rare_flags = [is_rare(c, reading) for c, _ in shown]
        top = rare_flags[: args.top]
        if not any(top):
            continue
        # 稀少の下に、ふつうの語があること(無ければ専門語ばかりの読みで、直しようがない)
        first_rare = top.index(True)
        def is_main_reading(candidate: str) -> bool:
            cost = entry_cost.get((reading, candidate))
            floor = min_cost.get(candidate)
            return cost is None or floor is None or cost - floor <= 500

        common_below = [
            (c, unigram.get(c, 99999)) for (c, _), rare in zip(shown[first_rare + 1:], rare_flags[first_rare + 1:])
            if not rare and is_main_reading(c)
        ]
        if not common_below:
            continue
        best_uni = min(u for _, u in common_below)
        if best_uni > args.max_best_uni:
            continue
        rare_in_top = [c for (c, _), rare in zip(shown[: args.top], top) if rare]
        marks = []
        for (c, _), rare in list(zip(shown, rare_flags))[: args.show]:
            uni = unigram.get(c)
            marks.append(("†" if rare else "") + ("※" if c in names.get(reading, ()) else "") + c + (f"[{uni}]" if uni is not None else "[-]"))
        flagged.append((best_uni, reading, rare_in_top, marks))

    flagged.sort(key=lambda x: (x[0], x[1]))
    out = OUT.with_name("rare_in_top3_presented.tsv") if args.dump else OUT
    with out.open("w", encoding="utf-8") as f:
        for best_uni, reading, rare_in_top, marks in flagged:
            f.write(f"{reading}\t{best_uni}\t{'/'.join(rare_in_top)}\t{' '.join(marks)}\n")

    bands = [(6000, 0), (6800, 0), (7500, 0), (99999, 0)]
    counts = defaultdict(int)
    for best_uni, *_ in flagged:
        for limit, _ in bands:
            if best_uni <= limit:
                counts[limit] += 1
                break
    print(f"{len(flagged)}件 → {out}")
    print("ふつうの語の unigram 帯ごと: " + ", ".join(f"≤{limit}: {counts[limit]}" for limit, _ in bands))


if __name__ == "__main__":
    main()
