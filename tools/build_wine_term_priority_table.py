#!/usr/bin/env python3
"""ワイン用語優先(デバッグ版専用。3805)の表を作り直す。

ワイン語彙(references/vin.plist)の読みを 1 つずつ実際に変換し、先頭の候補がその読みのワイン用語でない読みを全部拾って、
Packages/EcrituConversion/Sources/EcrituConversionBase/WineTermPriority.swift の BEGIN/END GENERATED TABLE の間に書き込む。

手順:
  1. 入力を作る:   python3 -I tools/build_wine_term_priority_table.py input <vin_in.tsv>
       (読み<TAB>その読みのワイン用語を | でつないだもの)
  2. 変換する:     TEST_RUNNER_AUDIT_IN=<vin_in.tsv> TEST_RUNNER_AUDIT_OUT=<vin_out.tsv> と実機の設定
       (tools/conversion_audit/ReadMe の AUDIT_KAKIKAE ほか)で testDiagnosticConversionAudit を回す。
       ワイン用語優先はオフのまま(TEST_RUNNER_AUDIT_WINE を付けない)
  3. 表を書く:     python3 -I tools/build_wine_term_priority_table.py table <vin_out.tsv>

拾わないもの: 先頭がその読みのワイン用語のどれか/『・』の有無だけの違い/カタカナと原語の書き分け・作る/造る などのほぼ一致
(tools/conversion_audit/near_match.py)/送り仮名の有無だけの違い/一括検査で『気にしなくていい』と決めた違いだけ(ignored_pairs.tsv)。
"""
import collections
import os
import re
import sqlite3
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools", "conversion_audit"))
import diff_pairs  # noqa: E402
import near_match  # noqa: E402

VIN_PLIST = os.path.join(ROOT, "references", "vin.plist")
SWIFT = os.path.join(ROOT, "Packages", "EcrituConversion", "Sources", "EcrituConversionBase", "WineTermPriority.swift")
ENTRY = re.compile(r"<key>phrase</key><string>(.*?)</string><key>shortcut</key><string>(.*?)</string>")
LATIN = re.compile(r"[A-Za-zÀ-ÖØ-öø-ÿŒœ]")
HIRAGANA = re.compile(r"[ぁ-ゖ]")
# 文の中でも一般語より先にする語: 語 LM に無いか、値段がこの値以上(=日常の文にまず出ない語)。帰還/高価/習慣/発声 のように
# 日常語でもある語は、文の中まで上げると普通の文が崩れすぎるので、読み全体・読み+助詞 のときだけ先頭にする
IN_SENTENCE_MIN_UNIGRAM = 7000
LM_SQLITE = os.path.join(ROOT, "tmp", "kana_kanji_dictionary.sqlite")
# 表に入れない読み(ユーザ指定 3810): こじょう=弧状(古城は が 弧状は。弧状 は は に続きにくい)、げんさん=減酸(原産 が先。地名+原産)、
# いか=イカ(以下の が イカの。一般語でも 以下 が先)
# げんきん=厳禁(ユーザ指定 3941): 現金 が先。げんきん が 厳禁、げんきんのみかな が 厳禁のミカな になっていた
EXCLUDED_READINGS = {"こじょう", "げんさん", "いか", "げんきん"}
# 文の中では上げない読み(ユーザ報告 3836): おまち=雄町。語 LM には稀でも、同じ読みの お待ち(お待ちください/お待ちになって)が
# 日常の文に頻出で、おまちください が 雄町ください になっていた。読みだけ・読み+助詞 のときは 雄町 を先頭のままにする
NOT_IN_SENTENCE_READINGS = {"おまち"}
# 拾った語を差し替える読み(ユーザ指定 3810): しゅし は 手指 でなく 種子 を先に(アニスの種子 が アニスの手指)。
# 読み → (先頭に置く語, 説明に出す一般語)
OVERRIDES = {"しゅし": (["種子"], "趣旨")}
# 読みだけなら先頭がワイン用語なので拾われないが、文の中では一般語が勝つ読み(ユーザ指定 3817): じょこう=除梗(除梗してから が
# 徐行してから)。読み → (先頭に置く語, 説明に出す一般語)。変換の結果に関係なく表に入れる
ADDITIONS = {"じょこう": (["除梗"], "徐行")}


def vin_surfaces_by_reading():
    by_reading = collections.OrderedDict()
    for line in open(VIN_PLIST, encoding="utf-8"):
        if line.strip().startswith("<!--"):
            continue
        for phrase, reading in ENTRY.findall(line):
            phrase = phrase.replace("&amp;", "&").replace("&apos;", "'").replace("&lt;", "<").replace("&gt;", ">")
            surfaces = by_reading.setdefault(reading, [])
            if phrase not in surfaces:
                surfaces.append(phrase)
    return by_reading


def write_input(dst):
    by_reading = vin_surfaces_by_reading()
    with open(dst, "w", encoding="utf-8") as f:
        for reading, surfaces in by_reading.items():
            f.write(reading + "\t" + "|".join(surfaces) + "\n")
    print(len(by_reading), "読み")


def write_table(src):
    readings, kakikae = near_match.load_tables()
    ignored = diff_pairs.load_ignored()

    def near(a, b):
        return near_match.is_near_match(a, b, readings, kakikae)

    lm = sqlite3.connect(LM_SQLITE)

    def in_sentence(surface):
        row = lm.execute("select cost from word_lm_unigram where surface = ?", (surface,)).fetchone()
        return row is None or row[0] >= IN_SENTENCE_MIN_UNIGRAM

    rows = []
    for line in open(src, encoding="utf-8"):
        cols = line.rstrip("\n").split("\t")
        i = next((j for j in range(2, len(cols)) if cols[j] in ("ok", "ng")), None)
        if i is None:
            continue
        reading, surfaces, top = cols[0], cols[1].split("|"), cols[i - 1]
        if not top or "\t" in top:
            continue

        def same(surface):
            if surface == top or surface.replace("・", "") == top.replace("・", ""):
                return True
            return near(surface.replace("・", ""), top.replace("・", "")) or not diff_pairs.remaining_spans(surface, top, ignored, near)

        if any(same(s) for s in surfaces):
            continue
        # 送り仮名の有無だけの違い(海沿/海沿い、値下/値下げ)は一般語との取り合いではないので拾わない
        if any(HIRAGANA.sub("", s_) == HIRAGANA.sub("", top) and HIRAGANA.sub("", top) for s_ in surfaces):
            continue
        # ラテン文字の表記を先、カタカナ・漢字を後(feedback: ラテン先・カタカナ2位)
        ordered = [s for s in surfaces if LATIN.search(s)] + [s for s in surfaces if not LATIN.search(s)]
        if reading in EXCLUDED_READINGS:
            continue
        if reading in OVERRIDES:
            ordered, top = OVERRIDES[reading]
        rows.append((reading, ordered, top))
    for reading, (ordered, top) in ADDITIONS.items():
        if all(r[0] != reading for r in rows):
            rows.append((reading, ordered, top))
    rows.sort(key=lambda r: r[0])
    body = "".join("    " + reading + "\t" + "|".join(surfaces) + "\t" + top + "\t"
                   + "|".join(s for s in surfaces if reading not in NOT_IN_SENTENCE_READINGS and in_sentence(s)) + "\n"
                   for reading, surfaces, top in rows)
    text = open(SWIFT, encoding="utf-8").read()
    begin = text.index("// BEGIN GENERATED TABLE")
    end = text.index("    // END GENERATED TABLE")
    new = text[:begin] + '// BEGIN GENERATED TABLE\n    static let table = """\n' + body + '    """\n' + text[end:]
    assert '"""' not in body and "\\" not in body
    open(SWIFT, "w", encoding="utf-8").write(new)
    print("文の中でも上げる語", sum(1 for r in rows for s in r[1] if in_sentence(s)))
    print(len(rows), "読み", sum(len(r[1]) for r in rows), "語",
          "2 かな以下", sum(1 for r in rows if len(r[0]) <= 2), "3 かな以上", sum(1 for r in rows if len(r[0]) >= 3))


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "input":
        write_input(sys.argv[2])
    elif len(sys.argv) == 3 and sys.argv[1] == "table":
        write_table(sys.argv[2])
    else:
        print(__doc__)
        sys.exit(1)
