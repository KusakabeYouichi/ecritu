#!/usr/bin/env python3
"""連語スキャンの確認表(artifact の db collection "colloc")の判定を保存・照会する。

  decisions.py export <db_dir> <items.json> <decisions.json>
      ArtifactData で out_dir に落とした colloc/*.json を items.json の並び(html.py と同じ順)で突き合わせ、
      1組1行の decisions.json(id/key/mark/note)にまとめる。
  decisions.py show <items.json> <decisions.json> [fix|ok|pending|note]
      前回の質問と回答を並べて表示する(動詞読みごと)。
  decisions.py undone <new_items.json> <decisions.json>...
      新しい items.json のうち、過去の decisions.json のどれにも key が無い組だけを表示する。
"""
import sys
import os
import json
import collections


def ordered_rows(items):
    """html.py と同じ順序(動詞読みの組数降順→出現数降順)。doc id c-NNNN はこの順番"""
    groups = collections.OrderedDict()
    for it in items:
        groups.setdefault(it["vr"], []).append(it)
    order = sorted(groups, key=lambda k: -len(groups[k]))
    rows = []
    for vr in order:
        rows.extend(sorted(groups[vr], key=lambda x: -x["count"]))
    return rows


def key_of(it):
    return it["noun"] + it["p"] + it["verb"]


def load_decisions(path):
    return {d["key"]: d for d in json.load(open(path, encoding="utf-8"))}


def export(db_dir, items_path, out_path):
    items = json.load(open(items_path, encoding="utf-8"))
    db = {}
    for fn in os.listdir(db_dir):
        if fn.endswith(".json"):
            db[fn[:-5]] = json.load(open(os.path.join(db_dir, fn), encoding="utf-8"))
    out = []
    stats = collections.Counter()
    for i, it in enumerate(ordered_rows(items)):
        did = "c-%04d" % i
        key = key_of(it)
        d = db.get(did, {})
        if d and d.get("key") != key:
            sys.exit(f"key mismatch {did}: {key} != {d.get('key')}")
        mark = d.get("mark", "") or ""
        note = d.get("note", "") or ""
        stats[mark or "pending"] += 1
        out.append({"id": did, "key": key, "mark": mark, "note": note})
    json.dump(out, open(out_path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(dict(stats), file=sys.stderr)


def describe(it):
    forms = []
    for f in it["forms"]:
        if f["status"] == "ok":
            continue
        forms.append(f"{f['expected']} → {f['top'][0] if f['top'] else '(なし)'}")
    return f"[{it['count']}回 {round(it['share'] * 100)}% 対抗 {it['rivals']}] " + " / ".join(forms)


def show(items_path, dec_path, flt=None):
    items = json.load(open(items_path, encoding="utf-8"))
    dec = load_decisions(dec_path)
    byvr = collections.OrderedDict()
    for it in ordered_rows(items):
        d = dec.get(key_of(it), {})
        mark = d.get("mark", "") or "pending"
        note = d.get("note", "")
        if flt == "note" and not note.strip():
            continue
        if flt in ("fix", "ok", "pending") and mark != flt:
            continue
        byvr.setdefault(it["vr"], []).append((d.get("id", "-"), it, mark, note))
    for vr, lst in byvr.items():
        print(f"\n## {vr} ({len(lst)})")
        for did, it, mark, note in lst:
            print(f"- {did} {key_of(it)} 【{mark}】 {describe(it)}" + (f"  備考: {note}" if note else ""))


def undone(new_items_path, dec_paths):
    items = json.load(open(new_items_path, encoding="utf-8"))
    seen = set()
    for p in dec_paths:
        seen |= set(load_decisions(p))
    byvr = collections.OrderedDict()
    for it in ordered_rows(items):
        if key_of(it) in seen:
            continue
        byvr.setdefault(it["vr"], []).append(it)
    n = sum(len(v) for v in byvr.values())
    print(f"未判定 {n} / {len(items)} 組")
    for vr, lst in byvr.items():
        print(f"\n## {vr} ({len(lst)})")
        for it in lst:
            print(f"- {key_of(it)} {describe(it)}")


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "export":
        export(sys.argv[2], sys.argv[3], sys.argv[4])
    elif cmd == "show":
        show(sys.argv[2], sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else None)
    elif cmd == "undone":
        undone(sys.argv[2], sys.argv[3:])
    else:
        sys.exit(__doc__)
