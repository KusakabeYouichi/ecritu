#!/usr/bin/env python3
"""文章から断片(句点・読点・括弧・記号で区切った語句)を取り出し、Sudachi で読みを推定して TSV に書く(3640)。
使い方: .venv/bin/python -I tools/conversion_audit/extract.py <text.txt> <out.tsv> [--limit N] [--seed S] [--max-len 18] [--sample-sentences M]
--sample-sentences M: 大きな文章(jawiki_p1.txt 157MB)では先に文を M 本だけ無作為に選んでから断片を取る(記事の偏りを減らす)
出力の各行: 読み(ひらがな) \t 元の表記 \t 文番号 \t 印(固有名詞/用言)
対象: 漢字・ひらがな・カタカナ・ー・々・中黒・ラテン文字 の断片で 3〜max-len 字、漢字かカタカナかラテン文字を含むもの。
中黒(ピノ・ノワール)と、ラテン文字の語の間の空白・ハイフン・ドット・アポストロフィ(Pinot Noir/Saint-Émilion/St. Julien)では切らない(3676)。
--reading-overrides <plist>(複数可): écritu の語彙の 表記→読み で Sudachi の読みを上書きする。ラテン文字の部分はここに載っているものだけ読みが付く。
Sudachi の読みが取れない形態素(未知語)を含む断片は捨てる。同じ断片は 1 回だけ。
"""
import random
import re
import sys

from sudachipy import Dictionary, SplitMode

# 『・』では切らない(ピノ・ノワール/ブラン・ド・ブラン が切れて 〜はサン のような断片ができていた。ユーザ指摘 3657)
SPLIT_CHARS = set("。、「」『』（）()〈〉《》【】〔〕［］[]：:；;！!？?…―—\t\n /／　,.-〜~\"'“”‘’")
# ラテン文字の語の間なら切らない記号(空白・ハイフン・ドット・アポストロフィ)
LATIN_JOINERS = set(" -.'’")
LATIN = re.compile(r"[A-Za-zÀ-ÖØ-öø-ÿŒœ]")
JA = re.compile(r"^[ぁ-ゖァ-ヺー々一-鿿・A-Za-zÀ-ÖØ-öø-ÿŒœ '’.\-]+$")
HAS_TARGET = re.compile(r"[一-鿿ァ-ヺA-Za-zÀ-ÖØ-öø-ÿŒœ]")


def split_fragments(sent):
    """句読点・括弧・記号で切る。ラテン文字の語の間の 空白/ハイフン/ドット/アポストロフィ は切らない。
    ドットは語の後ろ(St. Julien の St.)でも、次がラテン文字なら切らない"""
    out = []
    current = []
    for i, c in enumerate(sent):
        if c in SPLIT_CHARS:
            k = i - 1
            while c == " " and k > 0 and sent[k] == ".":
                k -= 1
            prev_latin = k >= 0 and bool(LATIN.match(sent[k]))
            j = i + 1
            while c == "." and j < len(sent) and sent[j] == " ":
                j += 1
            next_latin = j < len(sent) and bool(LATIN.match(sent[j]))
            if c in LATIN_JOINERS and prev_latin and next_latin:
                current.append(c)
                continue
            out.append("".join(current))
            current = []
        else:
            current.append(c)
    out.append("".join(current))
    return out
HIRA = re.compile(r"^[ぁ-ゖー]+$")


def kata2hira(s):
    return "".join(chr(ord(c) - 0x60) if 0x30A1 <= ord(c) <= 0x30F6 else c for c in s)


PLIST_ENTRY = re.compile(r"<key>phrase</key><string>([^<]+)</string><key>shortcut</key><string>([^<]+)</string>")


def load_reading_overrides(paths):
    """écritu の語彙 plist(references/vin.plist 等)の 表記→読み。Sudachi の読み違い(根頭癌腫病=ねあたま…、新樽=しんたる)を
    écritu に登録した読みで上書きするために使う(3676)。2 字以上で漢字かカタカナを含む表記だけ。1 つの表記に読みが
    複数あるものは使わない(どれが文の読みか決められない)"""
    readings = {}
    for path in paths:
        for line in open(path, encoding="utf-8"):
            stripped = line.strip()
            if stripped.startswith("<!--"):
                continue
            for surface, reading in PLIST_ENTRY.findall(line):
                if len(surface) >= 2 and HAS_TARGET.search(surface) and HIRA.match(reading):
                    readings.setdefault(surface, set()).add(reading)
    return {s: next(iter(r)) for s, r in readings.items() if len(r) == 1}


def apply_reading_overrides(morphemes, overrides):
    """形態素の境界にそろう最長の語彙の表記があれば、その範囲の読みを語彙の読みにする。
    読みの無い形態素(ラテン文字)が語彙で覆われずに残ったら None(捨てる)"""
    out = []
    i = 0
    while i < len(morphemes):
        best = None
        surface = ""
        for j in range(i, len(morphemes)):
            surface += morphemes[j][0]
            if surface in overrides:
                best = (j, overrides[surface])
        if best is not None and best[0] > i or (best is not None and morphemes[i][1] != best[1]):
            out.append(best[1])
            i = best[0] + 1
        else:
            if morphemes[i][1] is None:
                return None
            out.append(morphemes[i][1])
            i += 1
    return "".join(out)


def main():
    args = sys.argv[1:]
    limit = None
    seed = 1
    max_len = 18
    sample_sentences = None
    override_files = []
    rest = []
    i = 0
    while i < len(args):
        if args[i] == "--limit":
            limit = int(args[i + 1]); i += 2
        elif args[i] == "--seed":
            seed = int(args[i + 1]); i += 2
        elif args[i] == "--max-len":
            max_len = int(args[i + 1]); i += 2
        elif args[i] == "--sample-sentences":
            sample_sentences = int(args[i + 1]); i += 2
        elif args[i] == "--reading-overrides":
            override_files.append(args[i + 1]); i += 2
        else:
            rest.append(args[i]); i += 1
    src, dst = rest
    overrides = load_reading_overrides(override_files)
    tok = Dictionary().create()
    text = open(src, encoding="utf-8").read()
    sentences = re.split(r"[。\n]", text)
    if sample_sentences is not None and len(sentences) > sample_sentences:
        rng = random.Random(seed)
        picked = sorted(rng.sample(range(len(sentences)), sample_sentences))
        sentences = [sentences[k] for k in picked]
    seen = set()
    rows = []
    skipped_oov = 0
    for sent_no, sent in enumerate(sentences):
        for frag in split_fragments(sent):
            frag = frag.strip()
            if not (3 <= len(frag) <= max_len) or not JA.match(frag) or not HAS_TARGET.search(frag):
                continue
            if frag in seen:
                continue
            seen.add(frag)
            ok = True
            flags = set()
            morphemes = []  # (表層, 読み)。中黒は読みを持たない
            for k, m in enumerate(tok.tokenize(frag, SplitMode.C)):
                pos = m.part_of_speech()
                if m.surface() == "・":
                    morphemes.append(("・", ""))
                    continue
                # ラテン文字の語と語の間の記号は読みを持たず、語は語彙の上書きでだけ読みが付く(None のまま残れば捨てる)
                if LATIN.search(m.surface()) or m.surface().strip(" -.'’") == "":
                    morphemes.append((m.surface(), None))
                    continue
                r = kata2hira(m.reading_form())
                if not r or not HIRA.match(r) or pos[0] in ("補助記号", "空白"):
                    ok = False
                    break
                # 括弧などで切れた断片の頭が助詞・助動詞なら文の途中からの切れ端(をサイボ/のせかいの)。捨てる
                if k == 0 and pos[0] in ("助詞", "助動詞"):
                    ok = False
                    break
                if pos[1] == "固有名詞":
                    flags.add("固有名詞")
                if pos[0] == "動詞" or pos[0] == "形容詞":
                    flags.add("用言")
                morphemes.append((m.surface(), r))
            reading = apply_reading_overrides(morphemes, overrides) if ok else ""
            if ok and (not reading or frag.startswith("・") or frag.endswith("・")):
                ok = False
            if not ok:
                skipped_oov += 1
                continue
            rows.append((reading, frag, sent_no, "/".join(sorted(flags))))
    if limit is not None and len(rows) > limit:
        random.Random(seed).shuffle(rows)
        rows = sorted(rows[:limit], key=lambda r: r[2])
    with open(dst, "w", encoding="utf-8") as f:
        for reading, frag, sent_no, flags in rows:
            f.write(f"{reading}\t{frag}\t{sent_no}\t{flags}\n")
    print(f"fragments={len(rows)} skipped_oov={skipped_oov}", file=sys.stderr)


if __name__ == "__main__":
    main()
