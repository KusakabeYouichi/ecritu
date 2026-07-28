#!/usr/bin/env python3
"""Build LatinSuggestionLexicon.json (英/仏/独/伊の汎用サジェスト語彙) from
Leipzig Corpora words lists (en/de/it) and Lexique 3.83 (fr).

Sources (downloaded separately, not committed):
- Leipzig: {lang}_news_2023_300K-words.txt  (id \t word \t count)
- Lexique: Lexique383.tsv (ortho/cgram/freqfilms2 columns)

Cleaning policy (v1):
- 単語形のみ: 先頭は文字、以降は文字・内部アポストロフィ・ハイフンのみ。数字・記号・
  ピリオド(略語)は除外。
- 3文字未満は除外(補完サジェストとして無意味な短語と、伊語エリジオンの切り株を
  まとめて落とす)。
- en/fr/it: 大文字始まりを除外(固有名詞対策。文頭大文字の一般語は小文字側が上位に
  居るので取りこぼしなし)。
- de: 名詞が大文字正書のため大文字始まりを許可。ALLCAPS(略語)のみ除外。
- it: 語末アポストロフィは po' 等の許可リスト以外除外(e'=è の代用打ちを排除)。
- fr: Lexique の freqfilms2(字幕頻度)を ortho ごとに合算してランク化。空白入り
  (複合表現)は除外。

Attribution (アプリの謝辞に記載):
- Leipzig Corpora Collection (CC BY) — D. Goldhahn, T. Eckart, U. Quasthoff 2012
- Lexique 3.83 (CC BY-SA) — B. New, C. Pallier
"""

from __future__ import annotations

import argparse
import json
import re
import unicodedata
from collections import defaultdict
from pathlib import Path

WORD_PATTERN = re.compile(r"^[^\W\d_][^\W\d_'’\-]*(?:['’\-][^\W\d_]+)*$")
TRAILING_APOSTROPHE_ALLOWLIST_IT = {"po'"}
# 伊語エリジオンの切り株(dell'→dell 等、トークナイザのアポストロフィ剥がれ)
ELISION_STEM_BLOCKLIST_IT = {
    "dell", "nell", "sull", "dall", "coll", "quell", "quest", "tutt",
    "anch", "sant", "senz", "mezz", "cinquant", "trent", "quarant",
}
MIN_LENGTH = 3


def is_clean_word(word: str, lang: str) -> bool:
    if len(word) < MIN_LENGTH:
        return False
    if word != unicodedata.normalize("NFC", word):
        return False
    if lang == "it" and (word.endswith("'") or word.endswith("’")):
        return word in TRAILING_APOSTROPHE_ALLOWLIST_IT
    if lang == "it" and word.lower() in ELISION_STEM_BLOCKLIST_IT:
        return False
    if not WORD_PATTERN.match(word):
        return False
    first = word[0]
    if lang == "de":
        # 名詞の大文字は正書。ALLCAPS(CDU 等の略語)だけ除外
        if word.isupper():
            return False
    else:
        if first.isupper():
            return False
    return True


def load_leipzig(path: Path, lang: str) -> list[str]:
    freq: dict[str, int] = defaultdict(int)
    for line in path.read_text(encoding="utf-8").splitlines():
        parts = line.split("\t")
        if len(parts) != 3:
            continue
        word, count = parts[1], parts[2]
        try:
            n = int(count)
        except ValueError:
            continue
        if is_clean_word(word, lang):
            freq[word] += n
    if lang == "de":
        # 文頭大文字の重複(Die vs die)を解消: 小文字キーごとに支配的な表記だけ残し
        # 頻度は合算する(冠詞類→小文字、名詞→大文字が自然に残る)。
        grouped: dict[str, dict[str, int]] = defaultdict(dict)
        for word, n in freq.items():
            grouped[word.lower()][word] = n
        # 文頭大文字の接続詞(Denn/Aber 等)が僅差で勝つのを防ぐため、大文字表記は
        # 小文字表記の3倍超の頻度がある(=ほぼ常に大文字=名詞)場合だけ採用する。
        def dominant(variants: dict[str, int]) -> str:
            lower = [w for w in variants if not w[0].isupper()]
            upper = [w for w in variants if w[0].isupper()]
            if not lower:
                return max(upper, key=lambda w: variants[w])
            if not upper:
                return max(lower, key=lambda w: variants[w])
            best_lower = max(lower, key=lambda w: variants[w])
            best_upper = max(upper, key=lambda w: variants[w])
            if variants[best_upper] > variants[best_lower] * 3:
                return best_upper
            return best_lower
        freq = {
            dominant(variants): sum(variants.values())
            for variants in grouped.values()
        }
    return [w for w, _ in sorted(freq.items(), key=lambda kv: (-kv[1], kv[0]))]


def load_lexique(path: Path) -> list[str]:
    freq: dict[str, float] = defaultdict(float)
    lines = path.read_text(encoding="utf-8").splitlines()
    header = lines[0].split("\t")
    ortho_idx = header.index("ortho")
    freq_idx = header.index("freqfilms2")
    for line in lines[1:]:
        parts = line.split("\t")
        if len(parts) <= max(ortho_idx, freq_idx):
            continue
        ortho = parts[ortho_idx]
        if " " in ortho or not is_clean_word(ortho, "fr"):
            continue
        try:
            freq[ortho] += float(parts[freq_idx])
        except ValueError:
            continue
    return [w for w, _ in sorted(freq.items(), key=lambda kv: (-kv[1], kv[0]))]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--leipzig-en", required=True, type=Path)
    parser.add_argument("--leipzig-de", required=True, type=Path)
    parser.add_argument("--leipzig-it", required=True, type=Path)
    parser.add_argument("--lexique", required=True, type=Path)
    parser.add_argument("--top", type=int, default=5000)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--review-dir", type=Path, help="言語別レビュー用リストの出力先")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    lists = {
        "en": load_leipzig(args.leipzig_en, "en")[: args.top],
        "de": load_leipzig(args.leipzig_de, "de")[: args.top],
        "it": load_leipzig(args.leipzig_it, "it")[: args.top],
        "fr": load_lexique(args.lexique)[: args.top],
    }
    for lang, words in lists.items():
        print(f"{lang}: {len(words)} words")
    args.output.write_text(
        json.dumps(lists, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    if args.review_dir:
        args.review_dir.mkdir(parents=True, exist_ok=True)
        for lang, words in lists.items():
            review_path = args.review_dir / f"latin_suggest_review_{lang}.txt"
            review_path.write_text(
                "\n".join(f"{i + 1}\t{w}" for i, w in enumerate(words)) + "\n",
                encoding="utf-8",
            )


if __name__ == "__main__":
    main()
