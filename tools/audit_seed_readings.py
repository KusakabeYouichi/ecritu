#!/usr/bin/env python3
"""KanaKanjiSeedDictionary.swift の (読み, 表層) を Sudachi の読み(tmp/sudachi_readings_by_surface.json)と
sqlite 辞書(tmp/kana_kanji_dictionary.sqlite)に照合し、辞書に無い読みを seed が供給している組を洗い出す。

2026-09-03(2771): 最初期の手書き seed(2026-04-22、Sudachi 索引導入前の暫定表)に 事象@じしょ のような
誤読み供給が残っていたため作成。結果は2群:
  1. 表層は Sudachi にあるが読みが一致しない → 誤読みの筆頭候補(ただし 何時=なんじ、等=など、単位の
     三合/一石、人名 薫/柚花、々 のような正当な意図的供給も混じる。初回 28 件中 誤りは 3 件)
  2. 表層が Sudachi にも sqlite にも無い → 活用形・複合語・助詞付きの意図的供給が大半(目視確認用)
かな識別(表層==読み)、カタカナ、漢字を含まない表層は対象外。

usage: python3 tools/audit_seed_readings.py
"""
import re, json, sqlite3, unicodedata, collections
src = open("KeyboardExtension/KanaKanjiSeedDictionary.swift", encoding="utf-8").read()
# エントリ抽出: "読み": [ "a", "b", ... ]  (複数行可、コメント除去)
body = re.sub(r"//[^\n]*", "", src)
entries = []
for m in re.finditer(r'"((?:[^"\\]|\\.)*)"\s*:\s*\[((?:[^\]])*)\]', body, re.S):
    reading = m.group(1)
    if not re.fullmatch(r"[ぁ-ゖゝゞー]+", reading):
        continue
    surfaces = re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(2))
    entries.append((reading, surfaces))
print("seed readings:", len(entries), "pairs:", sum(len(s) for _, s in entries))
sud = json.load(open("tmp/sudachi_readings_by_surface.json"))
db = sqlite3.connect("tmp/kana_kanji_dictionary.sqlite")
def in_dict(reading, cand):
    return db.execute("select 1 from dictionary_entries where reading=? and candidate=? limit 1", (reading, cand)).fetchone() is not None
def kata_to_hira(s):
    return "".join(chr(ord(c)-0x60) if "ァ"<=c<="ヶ" else c for c in s)
def has_kanji(s):
    return any("一"<=c<="鿿" or c in "々〆" for c in s)
mismatch, unknown = [], []
for reading, surfaces in entries:
    for s in surfaces:
        if s == reading or kata_to_hira(s) == reading:
            continue
        if not has_kanji(s):
            continue
        if in_dict(reading, s):
            continue
        readings = sud.get(s)
        if readings is None:
            unknown.append((reading, s))
        elif reading not in readings:
            mismatch.append((reading, s, readings[:6]))
print("\n== 表層は Sudachi にあるが読みが合わない:", len(mismatch))
for r, s, rs in mismatch: print(f"  {r} → {s}   Sudachi読み: {'/'.join(rs)}")
print("\n== 表層が Sudachi にも sqlite(読み,表層)にも無い:", len(unknown))
for r, s in unknown: print(f"  {r} → {s}")
