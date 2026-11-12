#!/usr/bin/env python3
"""一括検査の『ほぼ一致』(3775、ユーザ指定 2026-11-12)。期待と先頭の違いを区間ごとに分けて種類を付ける。
使い方: python3 -I tools/conversion_audit/near_match.py <audit_out.tsv> [--examples 件数] [--list 種類]
  種類ごとに「その種類まで許すと、不一致が何行減るか」を出す。--list で、その種類だけで違っている行を全部出す。

違いの種類(1 つの行に複数の区間があれば、全部が許す種類のときだけ『ほぼ一致』):
  latin_kana  カタカナで書くか原語(ラテン文字)で書くか。語彙に同じ読みで両方が載っている語だけ(メルロー⇔Merlot)。
              読みが同じ別の語(コナ⇔粉)は入らない
  tsukuru     作る/造る/創る の字の違い(つくる の語幹 1 字)
  kakikae     同音の漢字による書きかえの組(references/kakikae.plist。蒸溜⇔蒸留、醗酵⇔発酵、沙漠⇔砂漠)
  okurigana   送り仮名だけの違い(終わった⇔終った、度合い⇔度合)。違う区間がひらがなの足し引きだけ
  number      漢数字か算用数字か(一日⇔1日、五百万石⇔500万石)
  hira_kata   ひらがなかカタカナか(りんご⇔リンゴ、びん⇔ビン)
  kana_kanji  片方がひらがな、片方が漢字を含む(よい⇔良い、こと⇔事。酸⇔さん のような取り違えも混ざるので、許すかは別に判断する)
  other       上のどれでもない(別の語・区切りの違い)
classify.py は latin_kana・tsukuru・kakikae・number だけで違う行(NEAR_KINDS)を c_near.tsv に分け、確認表には出さない。"""
import difflib
import os
import re
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
REFERENCES = os.path.join(HERE, "..", "..", "references")
PLIST_ENTRY = re.compile(r"<key>phrase</key><string>([^<]+)</string><key>shortcut</key><string>([^<]+)</string>")
KAKIKAE_ENTRY = re.compile(r"<key>before</key><string>([^<]+)</string><key>after</key><string>([^<]+)</string>")
# 原語とカタカナの両方が載る語彙(ワイン・酒・一般の固有名)
VOCAB_FILES = ["vin.plist", "vin-latin-candidates.plist", "vin-acronyme.plist", "sake.plist", "misc.plist", "it.plist",
               "compenser.plist", "acronymes.plist"]
ORDER = ["latin_kana", "tsukuru", "kakikae", "number", "okurigana", "hira_kata", "kana_kanji"]
KANJI_DIGITS = set("〇一二三四五六七八九十百千万億")
MAKE = set("作造創")


def is_hiragana(s):
    return bool(s) and all("ぁ" <= c <= "ゖ" or c == "ー" for c in s)


def is_katakana(s):
    return bool(s) and all("ァ" <= c <= "ヺ" or c in "ー・" for c in s)


def is_latin(s):
    return bool(s) and any(c.isalpha() for c in s) and all(
        c.isascii() and (c.isalnum() or c in " '.-&") or "À" <= c <= "ž" for c in s)


def has_kanji(s):
    return any("一" <= c <= "鿿" or c in "々〆" for c in s)


def to_hiragana(s):
    return "".join(chr(ord(c) - 0x60) if "ァ" <= c <= "ヶ" else c for c in s.replace("・", ""))


def load_tables():
    readings = {}
    for name in VOCAB_FILES:
        path = os.path.join(REFERENCES, name)
        if not os.path.exists(path):
            continue
        for line in open(path, encoding="utf-8"):
            if line.strip().startswith("<!--"):
                continue
            for surface, reading in PLIST_ENTRY.findall(line):
                readings.setdefault(surface, set()).add(reading)
    kakikae = set()
    path = os.path.join(REFERENCES, "kakikae.plist")
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            for before, after in KAKIKAE_ENTRY.findall(line):
                # 違う字の組だけを覚える(蒸溜/蒸留 → 溜/留)
                pairs = [(a, b) for a, b in zip(before, after) if a != b]
                if len(before) == len(after) and pairs:
                    kakikae.update(frozenset(p) for p in pairs)
                kakikae.add(frozenset((before, after)))
    return readings, kakikae


def segments(expected, first):
    """違う区間を (期待側, 先頭側) の列にする。となり合う区間はつなぐ"""
    matcher = difflib.SequenceMatcher(None, expected, first, autojunk=False)
    out = []
    last_end = None
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag == "equal":
            continue
        if out and last_end == (i1, j1):
            a, b = out[-1]
            out[-1] = (a + expected[i1:i2], b + first[j1:j2])
        else:
            out.append((expected[i1:i2], first[j1:j2]))
        last_end = (i2, j2)
    return out


def same_word_in_two_scripts(kana, latin, readings):
    """カタカナの語とラテン文字の語が、語彙の同じ読みに載っているか"""
    kana_reading = to_hiragana(kana)
    latin_readings = readings.get(latin) or readings.get(latin.strip()) or set()
    if kana_reading in latin_readings:
        return True
    # カタカナの形そのものが別の読みで載っている語(ヴ と ぶ のゆれ)も、読みが 1 つでも重なれば同じ語
    return bool(latin_readings & (readings.get(kana) or set()))


def kind_of(a, b, readings, kakikae, expected="", first=""):
    if a and b:
        if is_katakana(a) and is_latin(b) and same_word_in_two_scripts(a, b, readings):
            return "latin_kana"
        if is_latin(a) and is_katakana(b) and same_word_in_two_scripts(b, a, readings):
            return "latin_kana"
        if len(a) == 1 and len(b) == 1 and a in MAKE and b in MAKE:
            return "tsukuru"
        if frozenset((a, b)) in kakikae:
            return "kakikae"
        digits_a, digits_b = any(c.isdigit() for c in a), any(c.isdigit() for c in b)
        if digits_a != digits_b and (set(a) & KANJI_DIGITS or set(b) & KANJI_DIGITS):
            return "number"
        if to_hiragana(a) == to_hiragana(b):
            return "hira_kata"
        if (is_hiragana(a) and has_kanji(b)) or (has_kanji(a) and is_hiragana(b)):
            return "kana_kanji"
    if (not a or is_hiragana(a)) and (not b or is_hiragana(b)) and (a or b):
        # ひらがなの足し引きだけ(送り仮名)。両方にひらがながあって違うとき(い⇔え)は別の語
        if not a or not b:
            return "okurigana"
    return "other"


def kinds_of_line(expected, first, readings, kakikae):
    # 中黒の有無だけの違いは一致(classify.py と同じ)
    if expected.replace("・", "") == first.replace("・", ""):
        return []
    # ラテン文字とカタカナは語の途中で区間が割れやすいので、語彙の語で先に置き換えてから比べる
    return [kind_of(a, b, readings, kakikae) for a, b in word_level_segments(expected, first, readings)]


def word_level_segments(expected, first, readings):
    """ラテン文字の連なり・カタカナの連なりを 1 文字として扱って差分を取る(Merlot と メルロー が 1 区間になる)"""
    token = re.compile(r"[A-Za-zÀ-ž][A-Za-zÀ-ž0-9'.&-]*(?: [A-Za-zÀ-ž][A-Za-zÀ-ž0-9'.&-]*)*|[ァ-ヺー・]+|.", re.S)
    tokens_a, tokens_b = token.findall(expected), token.findall(first)
    matcher = difflib.SequenceMatcher(None, tokens_a, tokens_b, autojunk=False)
    out = []
    last_end = None
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag == "equal":
            continue
        a, b = "".join(tokens_a[i1:i2]), "".join(tokens_b[j1:j2])
        if out and last_end == (i1, j1):
            out[-1] = (out[-1][0] + a, out[-1][1] + b)
        else:
            out.append((a, b))
        last_end = (i2, j2)
    # 1 区間の両側に ラテン文字/カタカナ の語と別の違いが混ざったら、語の組を先に外す
    refined = []
    for a, b in out:
        refined.extend(split_script_pair(a, b, readings))
    return refined


def split_script_pair(a, b, readings):
    """区間の頭か末尾が カタカナ⇔ラテン文字 の同じ語なら、その組と残りに分ける"""
    token = re.compile(r"[A-Za-zÀ-ž][A-Za-zÀ-ž0-9'.&-]*(?: [A-Za-zÀ-ž][A-Za-zÀ-ž0-9'.&-]*)*|[ァ-ヺー・]+|[^A-Za-zÀ-žァ-ヺー・]+", re.S)
    tokens_a, tokens_b = token.findall(a), token.findall(b)
    if len(tokens_a) <= 1 and len(tokens_b) <= 1:
        return [(a, b)]
    result = []
    while tokens_a and tokens_b and pair_ok(tokens_a[0], tokens_b[0], readings):
        result.append((tokens_a.pop(0), tokens_b.pop(0)))
    tail = []
    while tokens_a and tokens_b and pair_ok(tokens_a[-1], tokens_b[-1], readings):
        tail.insert(0, (tokens_a.pop(), tokens_b.pop()))
    rest_a, rest_b = "".join(tokens_a), "".join(tokens_b)
    if rest_a or rest_b:
        # 残りは文字単位でもう一度(送り仮名や 1 字の違いを拾う)
        result.extend(segments(rest_a, rest_b) if rest_a and rest_b else [(rest_a, rest_b)])
    return result + tail


def pair_ok(x, y, readings):
    return (is_katakana(x) and is_latin(y) and same_word_in_two_scripts(x, y, readings)) or (
        is_latin(x) and is_katakana(y) and same_word_in_two_scripts(y, x, readings))


# 『ほぼ一致』として許す種類(ユーザ指定 2026-11-12)。取り違えが混ざらない 4 つ。送り仮名・ひらがな/カタカナ・かな/漢字 は
# 変換できていない行(マデラ→までら、酸→さん)が混ざるので入れない
NEAR_KINDS = ("latin_kana", "tsukuru", "kakikae", "number")


def is_near_match(expected, first, readings, kakikae, allowed=NEAR_KINDS):
    kinds = kinds_of_line(expected, first, readings, kakikae)
    return bool(kinds) and all(kind in allowed for kind in kinds)


def main():
    args = sys.argv[1:]
    examples = 12
    list_kind = None
    rest = []
    i = 0
    while i < len(args):
        if args[i] == "--examples":
            examples = int(args[i + 1]); i += 2
        elif args[i] == "--list":
            list_kind = args[i + 1]; i += 2
        else:
            rest.append(args[i]); i += 1
    readings, kakikae = load_tables()
    rows = []
    total = 0
    for line in open(rest[0], encoding="utf-8"):
        cols = line.rstrip("\n").split("\t")
        index = next((j for j in range(2, len(cols)) if cols[j] in ("ok", "ng")), None)
        if index is None:
            continue
        total += 1
        expected, first = cols[1], cols[index - 1]
        if cols[index] == "ok" or expected.replace("・", "") == first.replace("・", ""):
            continue
        rows.append((expected, first, kinds_of_line(expected, first, readings, kakikae)))
    if list_kind:
        for expected, first, kinds in rows:
            if kinds and all(kind == list_kind for kind in kinds):
                print(f"{expected}\t{first}")
        return
    print(f"全 {total} 行、先頭が期待と違う行 {len(rows)}")
    allowed = []
    remaining = len(rows)
    for kind in ORDER:
        allowed.append(kind)
        near = sum(1 for _, _, kinds in rows if kinds and all(k in allowed for k in kinds))
        only = [(e, f) for e, f, kinds in rows if kinds and all(k == kind for k in kinds)]
        print(f"\n[{kind}] この種類だけで違う行 {len(only)}。ここまで許すと不一致は {len(rows) - near} 行(-{remaining - (len(rows) - near)})")
        remaining = len(rows) - near
        pairs = Counter()
        for expected, first, kinds in rows:
            for (a, b), k in zip(word_level_segments(expected, first, readings), kinds):
                if k == kind:
                    pairs[(a or "(なし)", b or "(なし)")] += 1
        print("  多い違い(期待→先頭、回数): " + "、".join(f"{a}→{b} {n}" for (a, b), n in pairs.most_common(examples)))
    other = sum(1 for _, _, kinds in rows if "other" in kinds)
    print(f"\n[other] 別の語・区切りの違いを含む行 {other}")


if __name__ == "__main__":
    main()
