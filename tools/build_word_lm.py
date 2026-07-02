#!/usr/bin/env python3
"""連文節変換(案1: 自前単語LM)用の単語 n-gram(bigram)を構築する。

- 入力: 日本語コーパス(プレーンテキスト)
- 分割: SudachiPy(SplitMode.C = 単語単位)
- 出力(JSON): {"unigram": {surface: cost}, "bigram": {"prev\\tcur": cost},
               "params": {scale, oovCost, backoffPenalty}}
  cost は整数(-log 確率 × SCALE)。DP では
    経路コスト = Σ emission(Sudachi語コスト) + Σ transition(bigram)
  transition(prev,cur) = bigram があればその cost、無ければ backoffPenalty + unigram(cur)、
  unigram にも無ければ 0(emission 側で OOV を減点)。
"""
import argparse
import json
import math
import re
from collections import Counter

from sudachipy import Dictionary, SplitMode


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--input", action="append", required=True, help="corpus text file (repeatable)")
    p.add_argument("--output", required=True)
    p.add_argument("--scale", type=float, default=500.0, help="-logP を整数コストへ変換する係数")
    p.add_argument("--min-unigram", type=int, default=2)
    p.add_argument("--min-bigram", type=int, default=2)
    return p.parse_args()


def main():
    args = parse_args()
    tok = Dictionary(dict="core").create()

    uni = Counter()
    bi = Counter()
    sent_split = re.compile(r"[。!?\n]")

    for path in args.input:
        with open(path, encoding="utf-8") as f:
            text = f.read()
        for sent in sent_split.split(text):
            sent = sent.strip()
            if not sent:
                continue
            try:
                words = [m.surface() for m in tok.tokenize(sent, SplitMode.C)]
            except Exception:
                continue
            seq = ["<BOS>"] + [w for w in words if w.strip()] + ["<EOS>"]
            for w in seq:
                uni[w] += 1
            for a, b in zip(seq, seq[1:]):
                bi[(a, b)] += 1

    total_uni = sum(uni.values())
    scale = args.scale

    # 枝刈り + コスト化
    unigram_cost = {}
    for w, c in uni.items():
        if c < args.min_unigram and w not in ("<BOS>", "<EOS>"):
            continue
        unigram_cost[w] = int(round(-math.log(c / total_uni) * scale))

    bigram_cost = {}
    for (a, b), c in bi.items():
        if c < args.min_bigram:
            continue
        if a not in uni:
            continue
        # P(b|a) = c(a,b)/c(a)
        cost = int(round(-math.log(c / uni[a]) * scale))
        bigram_cost[f"{a}\t{b}"] = cost

    # OOV / backoff の既定コスト(最も稀な語より更に高い)
    max_uni_cost = max(unigram_cost.values()) if unigram_cost else int(10 * scale)
    oov_cost = max_uni_cost + int(2 * scale)
    backoff_penalty = int(2 * scale)  # bigram 未観測時の加算

    out = {
        "unigram": unigram_cost,
        "bigram": bigram_cost,
        "params": {
            "scale": scale,
            "oovCost": oov_cost,
            "backoffPenalty": backoff_penalty,
            "totalUnigram": total_uni,
        },
    }
    json.dump(out, open(args.output, "w", encoding="utf-8"), ensure_ascii=False)
    print(
        f"tokens={total_uni} uni={len(unigram_cost)} bi={len(bigram_cost)} "
        f"oovCost={oov_cost} backoff={backoff_penalty} -> {args.output}"
    )


if __name__ == "__main__":
    main()
