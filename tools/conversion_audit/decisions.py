#!/usr/bin/env python3
"""一括検査の確認表(artifact の db collection "audit")の判定を保存・照会する。

  decisions.py export <db_dir> <items.json> <decisions.json>
      ArtifactData list で db_dir に落とした audit/*.json を items.json(html.py の出力)の doc id で突き合わせ、
      1 行 1 件の decisions.json(id/key/cls/stage/reading/expected/top/mark/note)にまとめる。
  decisions.py show <decisions.json> [fix|ok|pending|note]
      判定を並べて表示する(分類→段階の順)。
"""
import collections
import json
import os
import sys


def export(db_dir, items_path, out_path):
    items = json.load(open(items_path, encoding="utf-8"))
    db = {}
    for fn in os.listdir(db_dir):
        if fn.endswith(".json"):
            db[fn[:-5]] = json.load(open(os.path.join(db_dir, fn), encoding="utf-8"))
    out = []
    stats = collections.Counter()
    for it in items:
        d = db.get(it["id"], {})
        if d and d.get("key") != it["key"]:
            sys.exit(f"key mismatch {it['id']}: {it['key']!r} != {d.get('key')!r}")
        mark = d.get("mark", "") or ""
        note = d.get("note", "") or ""
        stats[mark or "pending"] += 1
        out.append({"id": it["id"], "key": it["key"], "cls": it["cls"], "stage": it["stage"], "reading": it["reading"],
                    "expected": it["expected"], "top": it["top"], "mark": mark, "note": note})
    json.dump(out, open(out_path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(dict(stats), file=sys.stderr)


def show(dec_path, flt=None):
    dec = json.load(open(dec_path, encoding="utf-8"))
    group = None
    for d in dec:
        mark = d["mark"] or "pending"
        if flt == "note" and not d["note"].strip():
            continue
        if flt in ("fix", "ok", "pending") and mark != flt:
            continue
        g = f"{d['cls']} 段階 {d['stage']}"
        if g != group:
            group = g
            print(f"== {g}")
        print(f"{mark:8} {d['expected']} → {d['top'] or '(なし)'}  [{d['reading']}]" + (f"  備考: {d['note']}" if d["note"] else ""))


if __name__ == "__main__":
    if len(sys.argv) >= 5 and sys.argv[1] == "export":
        export(sys.argv[2], sys.argv[3], sys.argv[4])
    elif len(sys.argv) >= 3 and sys.argv[1] == "show":
        show(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
    else:
        sys.exit(__doc__)
