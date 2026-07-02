#!/usr/bin/env python3
"""Wikipedia の pages-articles(.bz2)から本文プレーンテキストを抽出する(LM学習用)。

wikitext のマークアップを大まかに除去する(n-gram 集計用途なので完全さは不要)。
出力サイズ上限に達したら打ち切る。ストリーム処理で巨大展開ファイルを作らない。
usage: extract_wiki_text.py <input.bz2> <output.txt> [max_mb]
"""
import bz2
import re
import sys

TEXT_OPEN = re.compile(r"<text\b[^>]*>")
TEXT_CLOSE = "</text>"

# 大まかな wikitext クリーナ
RE_COMMENT = re.compile(r"<!--.*?-->", re.S)
RE_REF = re.compile(r"<ref[^>]*?/>|<ref[^>]*?>.*?</ref>", re.S)
RE_TAG = re.compile(r"<[^>]+>")
RE_TABLE = re.compile(r"\{\|.*?\|\}", re.S)
RE_TEMPLATE = re.compile(r"\{\{[^{}]*?\}\}", re.S)
RE_FILE = re.compile(r"\[\[(?:ファイル|画像|File|Image|Category|カテゴリ):[^\[\]]*?\]\]", re.I)
RE_LINK = re.compile(r"\[\[(?:[^\[\]|]*\|)?([^\[\]|]+)\]\]")
RE_EXTLINK = re.compile(r"\[https?://[^\s\]]+\s*([^\]]*)\]")
RE_BOLDITALIC = re.compile(r"'{2,5}")
RE_HEADING = re.compile(r"^=+\s*(.*?)\s*=+\s*$", re.M)
RE_ENTITY = re.compile(r"&(?:amp|lt|gt|quot|nbsp);")
RE_WS = re.compile(r"[ \t]+")


def clean(text):
    text = RE_COMMENT.sub(" ", text)
    text = RE_REF.sub(" ", text)
    text = RE_TABLE.sub(" ", text)
    # テンプレートは入れ子があるので数回除去
    for _ in range(5):
        new = RE_TEMPLATE.sub(" ", text)
        if new == text:
            break
        text = new
    text = RE_FILE.sub(" ", text)
    text = RE_LINK.sub(r"\1", text)
    text = RE_EXTLINK.sub(r"\1", text)
    text = RE_TAG.sub(" ", text)
    text = RE_BOLDITALIC.sub("", text)
    text = RE_HEADING.sub(r"\1", text)
    text = RE_ENTITY.sub(" ", text)
    return text


def main():
    src, dst = sys.argv[1], sys.argv[2]
    max_bytes = int(float(sys.argv[3]) * 1024 * 1024) if len(sys.argv) > 3 else 200 * 1024 * 1024

    written = 0
    buf = []
    in_text = False
    with bz2.open(src, "rt", encoding="utf-8", errors="ignore") as f, \
            open(dst, "w", encoding="utf-8") as out:
        for line in f:
            if not in_text:
                m = TEXT_OPEN.search(line)
                if m:
                    line = line[m.end():]
                    in_text = True
                else:
                    continue
            # in_text
            if TEXT_CLOSE in line:
                line = line[:line.index(TEXT_CLOSE)]
                buf.append(line)
                body = clean("\n".join(buf))
                buf = []
                in_text = False
                for para in body.split("\n"):
                    para = RE_WS.sub(" ", para).strip()
                    if len(para) >= 10:  # 短い行/残骸は捨てる
                        out.write(para + "\n")
                        written += len(para.encode("utf-8")) + 1
                if written >= max_bytes:
                    break
            else:
                buf.append(line)
    print(f"extracted {written/1024/1024:.1f} MB -> {dst}")


if __name__ == "__main__":
    main()
