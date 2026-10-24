#!/usr/bin/env python3
"""testDiagnosticConjugationOrderSurvey の出力(CONJFLIP 行)から確認表の質問 conj.json を作る。
使い方: items.py survey.txt conj.json
"""
import sys
import json

rows = []
for line in open(sys.argv[1], encoding="utf-8"):
    if not line.startswith("CONJFLIP"):
        continue
    p = line.rstrip("\n").split("\t")
    kind, reading = p[1], p[2]
    forms = []
    for f in p[3:]:
        label, r, h = f.split("=", 2)
        forms.append({"label": label, "reading": r, "heads": [x for x in h.split("/") if x]})
    base = forms[0]["heads"][:2]
    for f in forms[1:]:
        f["flip"] = len(f["heads"]) >= 2 and f["heads"][:2] != base
    rows.append({"kind": kind, "reading": reading, "forms": forms})
json.dump(rows, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False)
print(len(rows), "suru", sum(1 for r in rows if r["kind"] == "suru"), "godan", sum(1 for r in rows if r["kind"] == "godan"), file=sys.stderr)
