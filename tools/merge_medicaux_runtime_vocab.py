#!/usr/bin/env python3
"""拡張が実行時に引く補助語彙(ÉcrituSecondVocab.eccs の元)に、病名(médicaux)を足した JSON を作る。

足すのは、補助語彙にも Premier(Sudachi 由来の本体)にも無い読みの病名だけ。
補助語彙の語は「同じ読みに LM 実在の語が無ければ単文節で昇格」「連文節で区間が LM 未収録なら +2000」の
扱いを受ける。読みがぶつかる病名まで入れると 光合成→咬合性・早老症→早漏症 のように一般語を押しのけるので外し、
ぶつからない病名だけ連文節で 1 語として勝てるようにする(骨盤内 が 骨盤ない に割れていた)。

使い方: python3 tools/merge_medicaux_runtime_vocab.py --second S.json --premier P.json --medicaux M.json --output O.json
"""
import argparse
import json


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--second", required=True)
    parser.add_argument("--premier", required=True)
    parser.add_argument("--medicaux", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    with open(args.second, encoding="utf-8") as f:
        second = json.load(f)
    with open(args.premier, encoding="utf-8") as f:
        taken = set(json.load(f))
    taken.update(second)
    with open(args.medicaux, encoding="utf-8") as f:
        medicaux = json.load(f)

    merged = dict(second)
    added = 0
    excluded = 0
    for reading, candidates in medicaux.items():
        if reading in taken:
            excluded += 1
            continue
        merged[reading] = candidates
        added += len(candidates)

    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(merged, f, ensure_ascii=False, separators=(",", ":"))
    print(f"[dict] 補助語彙に病名 {added} 語を足しました(読みがぶつかる {excluded} 読みは除外)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
