#!/usr/bin/env python3
"""colloc_full.json から「同音動詞があり、ある名詞+助詞の後ろでは片方に偏る」組を選び、
変換器に掛ける読みの TSV を作る。
列: reading, expected, noun_s, noun_r, particle, verb_dform, verb_reading, count, share, rivals
"""
import json
import sys
import collections

from sudachipy import Dictionary, SplitMode

MIN_VERB_OVERALL = 15   # 同音の対抗馬として数える動詞の最低出現数
MIN_TRIGRAM = 4         # 名詞+助詞+動詞読み の最低合計
MIN_SHARE = 0.7         # 優勢動詞の割合

tok = Dictionary().create()


def conj_type(dform):
    ms = tok.tokenize(dform, SplitMode.C)
    return ms[0].part_of_speech()[4] if len(ms) == 1 else ""


def ta_form(reading, ctype):
    """辞書形の読みから た形の読み。作れなければ None"""
    last = reading[-1]
    if ctype.startswith("五段"):
        if reading.endswith("いく") or reading.endswith("ゆく"):
            return reading[:-1] + "った"
        table = {"う": "った", "つ": "った", "る": "った", "く": "いた", "ぐ": "いだ", "す": "した",
                 "ぬ": "んだ", "ぶ": "んだ", "む": "んだ"}
        return reading[:-1] + table[last] if last in table else None
    if ctype.startswith("上一段") or ctype.startswith("下一段"):
        return reading[:-1] + "た" if last == "る" else None
    if ctype.startswith("サ行変格"):
        return reading[:-2] + "した" if reading.endswith("する") else None
    if ctype.startswith("カ行変格"):
        return reading[:-2] + "きた" if reading.endswith("くる") else None
    return None


def main():
    d = json.load(open(sys.argv[1], encoding="utf-8"))
    verb = collections.defaultdict(dict)
    for vr, dform, c in d["verb"]:
        verb[vr][dform] = c
    homophones = {vr: {s for s, c in m.items() if c >= MIN_VERB_OVERALL} for vr, m in verb.items()}
    homophones = {vr: s for vr, s in homophones.items() if len(s) >= 2}
    tri = collections.defaultdict(lambda: collections.Counter())
    for ns, nr, p, vr, dform, c in d["tri"]:
        if vr in homophones and dform in homophones[vr]:
            tri[(ns, nr, p, vr)][dform] += c
    rows = []
    for (ns, nr, p, vr), m in tri.items():
        total = sum(m.values())
        if total < MIN_TRIGRAM:
            continue
        dform, c = m.most_common(1)[0]
        share = c / total
        if share < MIN_SHARE:
            continue
        skeleton = lambda w: "".join(ch for ch in w if not ("\u3041" <= ch <= "\u309f"))
        # 送り仮名違い(果す/行なう)は同音語の対抗馬に数えない
        rivals = sorted((s for s in homophones[vr] - {dform} if skeleton(s) != skeleton(dform)), key=lambda s: -verb[vr][s])
        if not rivals:
            continue
        ctype = conj_type(dform)
        rows.append((nr + p + vr, ns + p + dform, ns, nr, p, dform, vr, c, share, "/".join(rivals), ctype))
    rows.sort(key=lambda r: -r[7])
    out = open(sys.argv[2], "w", encoding="utf-8")
    n = 0
    for r in rows:
        reading, expected, ns, nr, p, dform, vr, c, share, rivals, ctype = r
        out.write("\t".join([reading, expected, ns, nr, p, dform, vr, str(c), f"{share:.2f}", rivals, "辞書形"]) + "\n")
        n += 1
        ta_r = ta_form(vr, ctype)
        ta_s = ta_form(dform, ctype) if ta_r else None
        if ta_r and ta_s:
            out.write("\t".join([nr + p + ta_r, ns + p + ta_s, ns, nr, p, dform, vr, str(c), f"{share:.2f}", rivals, "た形"]) + "\n")
            n += 1
    print("rows", n, "pairs", len(rows), file=sys.stderr)


if __name__ == "__main__":
    main()
