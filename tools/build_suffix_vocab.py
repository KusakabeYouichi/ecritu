#!/usr/bin/env python3
"""references/suffixes.plist(接尾辞の補い)から、sqlite に足す語彙 JSON と語コスト JSON を作る(3397)。

Sudachi core に読みの項目が無い接尾辞(港(こう) 等)を補う。語彙は Premier の後ろに足す(同じ読みでは既存の語より後ろの rank)。
語コストは plist の cost(必須)をそのまま使う。弱い既定コストだと、連文節の「別の読みの統計を借りない」安全策
(同じ表記の別の読みより 2500 以上高いと LM を信用しない)に掛かり、港→LM が効かない(港(みなと) 3596)。

使い方: python3 tools/build_suffix_vocab.py references/suffixes.plist --vocab-out V.json --costs-out C.json
"""
import argparse
import json
import plistlib


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("plist")
    parser.add_argument("--vocab-out", required=True)
    parser.add_argument("--costs-out", required=True)
    args = parser.parse_args()

    with open(args.plist, "rb") as f:
        entries = plistlib.load(f)

    vocab: dict = {}
    costs: dict = {}
    for entry in entries:
        phrase, reading, cost = entry["phrase"], entry["shortcut"], entry["cost"]
        vocab.setdefault(reading, [])
        if phrase not in vocab[reading]:
            vocab[reading].append(phrase)
        costs.setdefault(reading, {})[phrase] = int(cost)

    with open(args.vocab_out, "w", encoding="utf-8") as f:
        json.dump(vocab, f, ensure_ascii=False)
    with open(args.costs_out, "w", encoding="utf-8") as f:
        json.dump(costs, f, ensure_ascii=False)
    print(f"[dict] 接尾辞の補い {sum(len(v) for v in vocab.values())} 語")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
