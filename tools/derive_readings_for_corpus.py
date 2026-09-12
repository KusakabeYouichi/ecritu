#!/usr/bin/env python3
"""文章から「読み → 期待する表記」の対を作る(変換の抜き取り検査用。2859)。

変換器は「読み」を受け取って「表記」を返す。手元の文章は表記しかないので、
Sudachi の 表層→読み 表(tmp/sudachi_readings_by_surface.json)で読みを逆算する。
**読みが 1 つに定まる語だけを使う**。複数の読みを持つ語(行く=いく/ゆく)が混じった文は、
逆算した読みが正しい保証が無く、変換が再現できなくても不具合とは言えないので捨てる。

使い方:
    python3 tools/derive_readings_for_corpus.py < 文章.txt > 対.tsv
出力は「読み<TAB>期待する表記」。
"""
import json
import os
import re
import sys

READINGS_PATH = os.path.join(os.path.dirname(__file__), "..", "tmp", "sudachi_readings_by_surface.json")
# 読みが複数ある語でも、word_costs で最安の読みが 2 位を大きく引き離すもの(行く=いく 等)は
# その読みを採る。環境変数 ECRITU_CORPUS_DOMINANT=1 のときだけ(検査の網を広げる。2883)
DOMINANT_PATH = os.path.join(os.path.dirname(__file__), "..", "tmp", "dominant_readings_by_surface.json")
KATAKANA_TO_HIRAGANA = str.maketrans({chr(c): chr(c - 0x60) for c in range(0x30A1, 0x30F7)})
KANA_RE = re.compile(r"[ぁ-ゖー]")
KANA_ONLY_RE = re.compile(r"[ぁ-ゖー]+\Z")
# 文の切れ目。記号・数字・ラテン文字を含む断片は読みが定まらないので後で捨てる
SENTENCE_SPLIT_RE = re.compile(r"[。．\.!?！？\n、,，「」『』()()\[\]【】…・:：;；/／\s]+")
UNSUPPORTED_RE = re.compile(r"[^ぁ-ゖァ-ヺー一-龥々〆ヶ]")

MAX_WORD_LENGTH = 12


def load_readings():
    with open(READINGS_PATH, encoding="utf-8") as handle:
        return json.load(handle)


def load_dominant():
    if os.environ.get("ECRITU_CORPUS_DOMINANT") != "1" or not os.path.exists(DOMINANT_PATH):
        return {}
    with open(DOMINANT_PATH, encoding="utf-8") as handle:
        return json.load(handle)


def segment(text, readings, dominant=None):
    """最長一致で区切る。読みが 1 つに定まらない語や未知語があれば None"""
    dominant = dominant or {}
    segments = []
    index = 0

    while index < len(text):
        if KANA_RE.match(text[index]):
            end = index
            while end < len(text) and KANA_RE.match(text[end]):
                end += 1
            segments.append((text[index:end], text[index:end]))
            index = end
            continue

        matched = None
        for length in range(min(MAX_WORD_LENGTH, len(text) - index), 0, -1):
            word = text[index:index + length]
            candidates = readings.get(word)
            if not candidates:
                continue

            hiragana = sorted({c.translate(KATAKANA_TO_HIRAGANA) for c in candidates})
            if len(hiragana) == 1 and KANA_ONLY_RE.match(hiragana[0]):
                matched = (word, hiragana[0])
            elif word in dominant and KANA_ONLY_RE.match(dominant[word]):
                matched = (word, dominant[word])
            break

        if matched is None:
            return None

        segments.append(matched)
        index += len(matched[0])

    return segments


def main():
    readings = load_readings()
    dominant = load_dominant()
    seen = set()

    for chunk in SENTENCE_SPLIT_RE.split(sys.stdin.read()):
        chunk = chunk.strip()
        if not (2 <= len(chunk) <= 24) or UNSUPPORTED_RE.search(chunk):
            continue

        segments = segment(chunk, readings, dominant)
        if segments is None:
            continue

        reading = "".join(r for _, r in segments)
        # 全部かなの断片は検査の意味が無い
        if reading == chunk or chunk in seen:
            continue

        seen.add(chunk)
        print(f"{reading}\t{chunk}")


if __name__ == "__main__":
    main()
