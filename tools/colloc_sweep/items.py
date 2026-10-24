#!/usr/bin/env python3
"""colloc_sweep_result.tsv(testDiagnosticCollocationSweep の出力)から確認表の質問 items.json を作る。
動詞部分が期待と違う組だけを残す(うる=得る は除外)。名詞部分の不一致だけの組は別問題なので落とす。
使い方: items.py tmp/colloc_sweep_result.tsv references/colloc_sweep/<id>/items.json
"""
import sys
import collections
import json

rows = [l.rstrip("\n").split("\t") for l in open(sys.argv[1], encoding="utf-8")]
items = collections.OrderedDict()
for r in rows:
    reading, expected, ns, nr, p, dform, vr, c, share, rivals, form, shown = r
    if form == "た形":
        # 辞書形読みと た形読みの共通接頭を除いた分だけ表記の末尾を差し替える(行う→行った、関する→関した)
        ta_r = reading[len(nr + p):]
        common = 0
        while common < min(len(vr), len(ta_r)) and vr[common] == ta_r[common]:
            common += 1
        removed = len(vr) - common
        expected = ns + p + dform[:len(dform) - removed] + ta_r[common:]
    key = (ns, p, dform)
    it = items.setdefault(key, {"noun": ns, "noun_r": nr, "p": p, "verb": dform, "vr": vr, "count": int(c),
                                "share": float(share), "rivals": rivals, "forms": []})
    sh = shown.split("|")
    it["forms"].append({"form": form, "reading": reading, "expected": expected, "top": sh[:4]})


def verb_part(top, ns, p):
    return top[len(ns + p):] if top.startswith(ns + p) else None


out = []
for key, it in items.items():
    if it["vr"] == "うる":
        continue
    mis = []
    for f in it["forms"]:
        top = f["top"][0] if f["top"] else ""
        if top == f["expected"]:
            f["status"] = "ok"
            continue
        vp = verb_part(top, it["noun"], it["p"])
        if vp is None:
            f["status"] = "noun"
            continue
        f["status"] = "verb"
        f["got_verb"] = vp
        mis.append(f)
    if not mis:
        continue
    it["kana"] = all(all(0x3041 <= ord(ch) <= 0x309F for ch in f.get("got_verb", "")) for f in mis)
    out.append(it)
print(len(out), "items; kana-only", sum(1 for i in out if i["kana"]), file=sys.stderr)
json.dump(out, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False, indent=0)
