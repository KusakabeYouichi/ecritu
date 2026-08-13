#!/usr/bin/env python3
"""vin-add.plist の全エントリを、分類結果に従って vin.plist / etc.plist の該当節末尾へ移す。

plistlib で書き直すとコメント(節見出し・行内注記)が全て失われるため、**行単位**で移動する。

入力: tmp/vinadd_results/b*.tsv  (phrase<TAB>category)
出力: references/vin.plist, references/vin-add.plist, references/etc.plist を書き換え

使い方:
  python3 tools/vinadd_apply_migration.py --dry-run   # 検証のみ
  python3 tools/vinadd_apply_migration.py             # 適用
"""
from __future__ import annotations
import argparse, pathlib, re, sys, collections, unicodedata

REF = pathlib.Path("references")
ENTRY_RE = re.compile(r"<key>phrase</key><string>(.*?)</string><key>shortcut</key><string>(.*?)</string>")
COMMENT_RE = re.compile(r"^\s*<!--\s*(.*?)\s*-->\s*$")
ETC_LABEL = "ETC"
NEW_SECTIONS = ["微生物", "輸入・流通", "サーヴィス"]
ETC_NEW_SECTION = "一般用語(vin-addより移動)"


def nfc(text: str) -> str:
    """é の NFC/NFD 差で突合が外れるのを防ぐ(bière/saké/dégustation で実際に発生)。"""
    return unicodedata.normalize("NFC", text)


def load_labels() -> dict[str, str]:
    labels = {}
    dup = []
    final = pathlib.Path("tmp/vinadd_final_labels.tsv")
    if final.exists():
        for line in final.read_text().splitlines():
            if line.strip() and "\t" in line:
                phrase, cat = line.split("\t")[:2]
                labels[nfc(phrase)] = cat.strip()
        return labels, dup
    for path in sorted(pathlib.Path("tmp/vinadd_results").glob("b*.tsv")):
        for line in path.read_text().splitlines():
            if not line.strip():
                continue
            parts = line.split("\t")
            if len(parts) < 2:
                continue
            phrase, cat = parts[0], parts[1].strip()
            if nfc(phrase) in labels and labels[nfc(phrase)] != cat:
                dup.append((phrase, labels[nfc(phrase)], cat))
            labels[nfc(phrase)] = cat
    return labels, dup


def sections_of(lines: list[str]) -> list[tuple[str, int, int]]:
    """[(節名, 見出し行index, 最終エントリ行index)] を返す。エントリ0件なら最終=見出し。"""
    out = []
    cur = None
    for i, ln in enumerate(lines):
        m = COMMENT_RE.match(ln)
        if m:
            if cur: out.append(cur)
            cur = [m.group(1), i, i]
            continue
        if ENTRY_RE.search(ln) and cur:
            cur[2] = i
    if cur: out.append(cur)
    return [tuple(c) for c in out]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    labels, dup = load_labels()
    if dup:
        print(f"警告: 同一phraseに異なる分類 {len(dup)}件")
        for p, a, b in dup[:10]: print(f"  {p}: {a} / {b}")

    vin_lines = (REF/"vin.plist").read_text().splitlines()
    add_lines = (REF/"vin-add.plist").read_text().splitlines()
    etc_lines = (REF/"etc.plist").read_text().splitlines()

    # vin-add の移動対象行を集める
    moving = []      # (category, rawline)
    unlabeled = []
    keep_add = []    # 移動しない行(ヘッダ・フッタ・節コメント)
    for ln in add_lines:
        m = ENTRY_RE.search(ln)
        if not m:
            keep_add.append(ln); continue
        phrase = m.group(1)
        cat = labels.get(nfc(phrase))
        if cat is None:
            unlabeled.append(phrase); keep_add.append(ln); continue
        moving.append((cat, ln))
    print(f"移動対象 {len(moving)}件 / 未分類で残す {len(unlabeled)}件")
    if unlabeled:
        for p in unlabeled[:20]: print(f"  未分類: {p}")

    by_cat = collections.defaultdict(list)
    for cat, ln in moving: by_cat[cat].append(ln)

    vin_sec = {name for name, _, _ in sections_of(vin_lines)}
    unknown = [c for c in by_cat if c not in vin_sec and c != ETC_LABEL and c not in NEW_SECTIONS]
    if unknown:
        print(f"エラー: vin.plist に存在しない節名 {len(unknown)}種")
        for c in unknown: print(f"  '{c}' ({len(by_cat[c])}件)")
        return 1

    print("\n分類ごとの件数:")
    for c, v in sorted(by_cat.items(), key=lambda kv: -len(kv[1])):
        print(f"  {len(v):5d}  {c}")

    if args.dry_run:
        print("\n--dry-run のため書き込みなし")
        return 0

    # --- fromage 節を フロマージュ 節へ統合 --------------------------------
    secs = sections_of(vin_lines)
    src = next((t for t in secs if t[0] == "fromage"), None)
    dst = next((t for t in secs if t[0] == "フロマージュ"), None)
    if src and dst:
        s_head, s_last = src[1], src[2]
        moved = vin_lines[s_head + 1:s_last + 1]
        del vin_lines[s_head:s_last + 1]           # 見出し+エントリを撤去
        secs2 = sections_of(vin_lines)
        d = next(t for t in secs2 if t[0] == "フロマージュ")
        vin_lines[d[2] + 1:d[2] + 1] = moved
        print(f"fromage 節 {len(moved)}件を フロマージュ 節へ統合")

    # --- vin.plist へ挿入 ---------------------------------------------------
    # 末尾の節から順に挿入する。前方の行indexがずれないようにするため。
    etc_moving = by_cat.pop(ETC_LABEL, [])
    vin_secs = sections_of(vin_lines)
    existing = {name for name, _, _ in vin_secs}

    # 新節は </array> の直前にまとめて作る
    tail_new = []
    for name in NEW_SECTIONS:
        if name in existing or not by_cat.get(name):
            continue
        tail_new.append("\t<!-- %s -->" % name)
        tail_new.extend(by_cat.pop(name))

    # 既存節への挿入(後方から)
    inserts = []   # (挿入位置, 行リスト)
    for name, head, last in vin_secs:
        rows = by_cat.pop(name, None)      # pop しないと検証で残留扱いになる
        if rows:
            inserts.append((last + 1, rows))
    for pos, rows in sorted(inserts, key=lambda t: -t[0]):
        vin_lines[pos:pos] = rows

    if tail_new:
        close = max(i for i, l in enumerate(vin_lines) if l.strip() == "</array>")
        vin_lines[close:close] = tail_new

    残り = {k: v for k, v in by_cat.items() if v and k not in NEW_SECTIONS}
    if 残り:
        print("エラー: 挿入先が見つからない分類が残った")
        for k, v in 残り.items(): print(f"  {k} ({len(v)}件)")
        return 1

    # --- etc.plist へ一般用語を追加 ----------------------------------------
    if etc_moving:
        close = max(i for i, l in enumerate(etc_lines) if l.strip() == "</array>")
        block = ["\t<!-- %s -->" % ETC_NEW_SECTION] + etc_moving
        etc_lines[close:close] = block

    # --- vin-add.plist はエントリを全て失う -------------------------------
    (REF/"vin.plist").write_text("\n".join(vin_lines) + "\n")
    (REF/"etc.plist").write_text("\n".join(etc_lines) + "\n")
    (REF/"vin-add.plist").write_text("\n".join(keep_add) + "\n")
    print(f"\n適用完了: vin.plist へ {len(moving)-len(etc_moving)}件、etc.plist へ {len(etc_moving)}件")
    return 0


if __name__ == "__main__":
    sys.exit(main())
