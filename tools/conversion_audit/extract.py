#!/usr/bin/env python3
"""文章から断片(句点・読点・括弧・記号で区切った語句)を取り出し、Sudachi で読みを推定して TSV に書く(3640)。
使い方: .venv/bin/python -I tools/conversion_audit/extract.py <text.txt> <out.tsv> [--limit N] [--seed S] [--max-len 18] [--sample-sentences M]
--sample-sentences M: 大きな文章(jawiki_p1.txt 157MB)では先に文を M 本だけ無作為に選んでから断片を取る(記事の偏りを減らす)
出力の各行: 読み(ひらがな) \t 元の表記 \t 文番号 \t 印(固有名詞/用言)
対象: 漢字・ひらがな・カタカナ・ー・々 だけの断片で 3〜max-len 字、漢字かカタカナを含むもの。
Sudachi の読みが取れない形態素(未知語)を含む断片は捨てる。同じ断片は 1 回だけ。
"""
import random
import re
import sys

from sudachipy import Dictionary, SplitMode

SPLIT = re.compile(r"[。、「」『』（）()〈〉《》【】〔〕［］\[\]・：:；;！!？?…―—?\s/／　,.\-〜~\"'“”‘’『』]")
JA = re.compile(r"^[ぁ-ゖァ-ヺー々一-鿿]+$")
HAS_TARGET = re.compile(r"[一-鿿ァ-ヺ]")
HIRA = re.compile(r"^[ぁ-ゖー]+$")


def kata2hira(s):
    return "".join(chr(ord(c) - 0x60) if 0x30A1 <= ord(c) <= 0x30F6 else c for c in s)


def main():
    args = sys.argv[1:]
    limit = None
    seed = 1
    max_len = 18
    sample_sentences = None
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
        else:
            rest.append(args[i]); i += 1
    src, dst = rest
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
        for frag in SPLIT.split(sent):
            frag = frag.strip()
            if not (3 <= len(frag) <= max_len) or not JA.match(frag) or not HAS_TARGET.search(frag):
                continue
            if frag in seen:
                continue
            seen.add(frag)
            reading = ""
            ok = True
            flags = set()
            for k, m in enumerate(tok.tokenize(frag, SplitMode.C)):
                pos = m.part_of_speech()
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
                reading += r
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
