#!/usr/bin/env python3
"""活用で入れ替わる並びの確認表(artifact の db collection "decisions")の判定を保存・照会する。

  decisions.py export <db_dir> <conj.json> <decisions.json>
      ArtifactData で out_dir に落とした decisions/*.json を conj.json の並びで突き合わせて 1 読み 1 行にまとめる
      (id は kind-NNN、mark は fix/ok/空、order は指示の本文。order があれば mark 空でも fix 扱い)
  decisions.py show <conj.json> <decisions.json> [fix|ok|pending]
      前回の質問(5 形の並び)と回答を並べて表示する
  decisions.py undone <new_conj.json> <decisions.json>...
      新しい conj.json のうち、過去の decisions.json のどれにも 読み が無いものだけを表示する
"""
import sys
import os
import json


def doc_id(i, r):
    return r["kind"] + "-" + str(i).zfill(3)


def effective_mark(d):
    return d.get("mark") or ("fix" if (d.get("order") or "").strip() else "")


def export(db_dir, conj_path, out_path):
    rows = json.load(open(conj_path, encoding="utf-8"))
    db = {}
    for fn in os.listdir(db_dir):
        if fn.endswith(".json"):
            v = json.load(open(os.path.join(db_dir, fn), encoding="utf-8"))
            db[fn[:-5]] = v.get("data", v)
    out = []
    n = {"fix": 0, "ok": 0, "": 0}
    for i, r in enumerate(rows):
        did = doc_id(i, r)
        d = db.get(did, {})
        if d and d.get("reading") != r["reading"]:
            sys.exit(f"reading mismatch {did}: {r['reading']} != {d.get('reading')}")
        mark = effective_mark(d)
        n[mark] += 1
        out.append({"id": did, "kind": r["kind"], "reading": r["reading"], "mark": mark, "order": (d.get("order") or "").strip()})
    json.dump(out, open(out_path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print({"fix": n["fix"], "ok": n["ok"], "pending": n[""]}, file=sys.stderr)


def forms_text(r):
    return " | ".join(f"{f['label']}:{'/'.join(f['heads'])}" for f in r["forms"])


def show(conj_path, dec_path, flt=None):
    rows = json.load(open(conj_path, encoding="utf-8"))
    dec = {d["reading"]: d for d in json.load(open(dec_path, encoding="utf-8"))}
    for i, r in enumerate(rows):
        d = dec.get(r["reading"], {})
        mark = d.get("mark") or "pending"
        if flt and mark != flt:
            continue
        line = f"- {doc_id(i, r)} {r['reading']} 【{mark}】 {forms_text(r)}"
        if d.get("order"):
            line += f"  指示: {d['order']}"
        print(line)


def undone(new_path, dec_paths):
    rows = json.load(open(new_path, encoding="utf-8"))
    seen = set()
    for p in dec_paths:
        seen |= {d["reading"] for d in json.load(open(p, encoding="utf-8"))}
    todo = [(i, r) for i, r in enumerate(rows) if r["reading"] not in seen]
    print(f"未判定 {len(todo)} / {len(rows)} 読み")
    for i, r in todo:
        print(f"- {r['kind']} {r['reading']} {forms_text(r)}")


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
