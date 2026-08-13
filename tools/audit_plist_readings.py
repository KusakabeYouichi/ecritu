#!/usr/bin/env python3
"""Audit reading (shortcut) consistency in references/*.plist.

LLM レビューは巡回ごとに見落としが変わる(8巡目の24件中19件は前巡でも同一読みで
存在したのに未指摘だった)。ここでは決定的に検出できるものだけを機械で洗い出す。

検査:
  1. xml   : plist としてパースできるか / 完全重複 / 読みが かな以外を含む
  2. word  : 単語境界の部分語で読みが不整合(Suduiraut / Château Suduiraut 型)
  3. kanji : 漢字部分語で読みが不整合(樽熟成 / オーク樽熟成 型)
             ※既定では走らない。2026-08-12 の実測で47件すべてが誤検知だった
               (複合語の区切り違い・連濁の正当形)。--checks kanji で明示指定したときだけ実行する
  4. kana  : 促音欠落(にぽん 型)などの壊れ読みパターン

拗音の大書き取りこぼし(じえ→じぇ)は機械判定を諦めた。上田市=うえだし・指定=してい・
シエラ=しえら のような正当な語を大量に誤検知する(実測415件中ほぼ全てが誤検知)ため、
この観点は LLM レビュー側に任せる。

2026-08-13 に試して却下した検査(同じ轍を踏まないための記録):
  5. 多数決トークン: 単独エントリが無いトークンでも、それを含む複合語の読みから
     n-gram多数決で「トークンの読み」を推定し外れを検出する案。Centre Loire=さんとる
     「るわーる」(他8件はろわーる)を実際に拾えたが、12件中真陽性1件(精度8%)。
     n-gram多数決は隣接語まで巻き込み、読みのどの部分がどのトークンに対応するかを
     分離できないのが原理的な限界。kanji検査(0/47)と同じ失敗の仕方。
  6. カタカナ対照: カタカナ表記エントリの読みはカタカナ→ひらがなで決定的に定まるので、
     それを正解とみなし近い読みのラテン表記エントリを突合する案。Hessische Bergstraße=
     へっしっしゅ(カタカナ側は へっしっしぇ)を拾えたが62件中真陽性2〜3件。
     ラテン表記とカタカナ表記は**意図的に別の音訳**であることが多く
     (Château Mouton Rothschild=ろーとしると と ローシルト=ろしると は両方正しい併記)、
     正解として使えない。村/種/系/地区/産 等の接尾差も大量に混じる。

ポリシー許容差(ゔ↔ば行、長音の有無)は正規化して無視する。読みの ゔ は
FlickKanaLayout の「う」+濁点で入力できるため誤りではない。

usage: python3 tools/audit_plist_readings.py [--checks xml,word,kanji,kana]
                                             [--plist references/vin.plist ...]
"""

from __future__ import annotations

import argparse
import plistlib
import re
import sys
from pathlib import Path

KANA_RE = re.compile(r"^[ぁ-ゖーゔ]+$")
KATAKANA_ONLY_RE = re.compile(r"^[ァ-ヶー・]+$")
WORD_SEPARATOR_RE = re.compile(r"[ \-・]")
# 日本語として成立しない壊れ読み。部分一致で誤検知しないものだけを載せる
# (「きごう」は 記号/魚崎郷 を、「うわっ」は該当なしでも将来の正当語を誤検知しうるため外した)。
BROKEN_READING_PATTERNS = {
    "にぽん": "にほん/にっぽん",
}
# 日本語に存在しない拗音の組み合わせ。この読みは打鍵できず候補に出ない
# (2026-08-12 に Embouteillage=あんぶていゃーじゅ 等7件を実測。過去8巡の
# LLMレビューは「ファイル内で一貫しているから意図的」と判断して見送っていた)。
INVALID_YOON_SEQUENCES = ["いゃ", "いゅ", "いょ", "てぅ", "ぶゅ", "ぷゅ", "むゅ", "るゃ", "るゅ"]


def normalize_for_comparison(reading: str) -> str:
    """ポリシー上等価な表記差(ゔ↔ば行・長音)を潰す。"""
    for source, replacement in (("ゔぁ", "ば"), ("ゔぃ", "び"), ("ゔぇ", "べ"),
                                ("ゔぉ", "ぼ"), ("ゔゅ", "びゅ"), ("ゔょ", "びょ"),
                                ("ゔゃ", "びゃ"), ("ゔ", "ぶ")):
        reading = reading.replace(source, replacement)
    return reading.replace("ー", "")


def load_allowlist(path: Path) -> set[tuple[str, str]]:
    """許容リスト(誤検知確定の (phrase, reading))を読む。

    教本表記や意図的な両読み併記など「言語学的な正しさより優先する」読み。
    メモリではなくリポジトリ内に置くことで、環境が変わっても、LLM レビューを
    誰が回しても同じ除外が効く。
    """
    if not path.exists():
        return set()

    allowed: set[tuple[str, str]] = set()
    for line in path.read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        columns = line.split("\t")
        if len(columns) >= 3:
            allowed.add((columns[1], columns[2]))
    return allowed


def load_entries(
    paths: list[Path],
    allowed: set[tuple[str, str]] | None = None,
) -> tuple[list[tuple[str, str, str]], list[str]]:
    """allowed の (phrase, reading) は xml 検査(かな種・カタカナ一致)の指摘からも除外する。

    従来は entries の絞り込みにしか使っておらず、許容登録済みの スヰートポーヅ が
    カタカナ表記と読みの不一致として毎回フラグされていた(2026-08-14)。
    構造破損(パース不能・空 phrase・完全重複)は許容対象でも指摘する。
    """
    entries: list[tuple[str, str, str]] = []
    problems: list[str] = []
    allowed = allowed or set()

    for path in paths:
        try:
            items = plistlib.load(path.open("rb"))
        except Exception as error:  # noqa: BLE001 - 壊れた plist の理由をそのまま見せる
            problems.append(f"{path.name}: XML としてパースできない: {error}")
            continue

        seen: set[tuple[str, str]] = set()
        for item in items:
            phrase = item.get("phrase", "")
            reading = item.get("shortcut", "")
            if not phrase or not reading:
                problems.append(f"{path.name}: phrase/shortcut が空: {item!r}")
                continue
            if (phrase, reading) in seen:
                problems.append(f"{path.name}: 完全重複: {phrase} / {reading}")
            seen.add((phrase, reading))
            if (phrase, reading) in allowed:
                continue
            if not KANA_RE.match(reading):
                problems.append(f"{path.name}: 読みにかな以外: {phrase} / {reading!r}")
            if KATAKANA_ONLY_RE.match(phrase):
                hiragana = "".join(
                    chr(ord(char) - 0x60) if "ァ" <= char <= "ヶ" else char for char in phrase
                ).replace("・", "")
                if hiragana != reading:
                    problems.append(
                        f"{path.name}: カタカナ表記と読みが不一致: {phrase} / {reading}"
                    )
            # 末尾★は仮登録マーカー。読み検査の対象外。
            if not phrase.rstrip().endswith("★"):
                entries.append((path.name, phrase, reading))

    return entries, problems


def check_word_boundary(entries: list[tuple[str, str, str]]) -> list[str]:
    """空白/ハイフン区切りの部分語の読みが、複合語の読みに現れるか。

    許容リストの行は指摘対象からも「比較の基準」からも外す。許容の理由が
    「Muscat=仏みゅすか/英ますかっと のような言語差」なので、基準にすると
    Muscat of X 系9件・Madrid 2件・Orange 2件を無意味に誤検知する(2026-08-13実測)。
    """
    readings_by_phrase: dict[str, set[str]] = {}
    for _, phrase, reading in entries:
        readings_by_phrase.setdefault(phrase, set()).add(reading)

    findings: list[str] = []
    for _, phrase, reading in entries:
        tokens = [token for token in WORD_SEPARATOR_RE.split(phrase) if len(token) >= 5]
        if len(tokens) < 2:
            continue
        for token in tokens:
            token_readings = readings_by_phrase.get(token)
            if not token_readings:
                continue
            if not any(
                normalize_for_comparison(candidate) in normalize_for_comparison(reading)
                for candidate in token_readings
            ):
                findings.append(
                    f"{token}={'/'.join(sorted(token_readings))}  ⇔  {phrase}={reading}"
                )
                break
    return findings


def check_kanji_substring(entries: list[tuple[str, str, str]]) -> list[str]:
    """2〜4文字の漢字語の読みが、それを含む語の読みに現れるか。"""
    term_readings: dict[str, set[str]] = {}
    for _, phrase, reading in entries:
        if re.fullmatch(r"[一-鿿ぁ-ゖ]+", phrase) and 2 <= len(phrase) <= 4:
            term_readings.setdefault(phrase, set()).add(reading)

    findings: list[str] = []
    for _, phrase, reading in entries:
        for term, readings in term_readings.items():
            if term == phrase or term not in phrase:
                continue
            if not any(candidate in reading for candidate in readings):
                findings.append(f"{term}={'/'.join(sorted(readings))}  ⇔  {phrase}={reading}")
                break
    return findings


def check_kana_shape(entries: list[tuple[str, str, str]]) -> list[str]:
    """日本語として成立しない壊れ読み・打鍵できない拗音。"""
    findings: list[str] = []
    for _, phrase, reading in entries:
        for pattern, expected in BROKEN_READING_PATTERNS.items():
            if pattern in reading:
                findings.append(f"{phrase}={reading}  ({pattern} → {expected})")
                break
        for sequence in INVALID_YOON_SEQUENCES:
            if sequence in reading:
                findings.append(
                    f"{phrase}={reading}  (「{sequence}」は打鍵できない拗音結合)"
                )
                break
    return findings


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--plist",
        action="append",
        default=None,
        help="検査する plist。既定は references/vin.plist",
    )
    parser.add_argument(
        "--checks",
        default="xml,word,kana",
        help="実行する検査をカンマ区切りで指定(kanji は誤検知だらけなので既定では走らせない)",
    )
    arguments = parser.parse_args()

    root = Path(__file__).resolve().parent.parent
    paths = [Path(item) for item in arguments.plist] if arguments.plist else [
        root / "references" / "vin.plist",
    ]
    checks = {name.strip() for name in arguments.checks.split(",") if name.strip()}

    allowed = load_allowlist(root / "references" / "reading_audit_allowlist.tsv")
    entries, problems = load_entries(paths, allowed=allowed)
    entries = [entry for entry in entries if (entry[1], entry[2]) not in allowed]
    print(
        f"対象 {len(entries)} エントリ ({', '.join(path.name for path in paths)})"
        f" / 許容リストで除外 {len(allowed)} 件"
    )

    exit_code = 0
    if "xml" in checks:
        print(f"\n[xml] 構造・重複・かな種: {len(problems)}件")
        for problem in problems:
            print(f"  {problem}")
        if problems:
            exit_code = 1

    if "word" in checks:
        findings = check_word_boundary(entries)
        print(f"\n[word] 単語境界の読み不整合: {len(findings)}件")
        for finding in findings:
            print(f"  {finding}")

    if "kanji" in checks:
        findings = check_kanji_substring(entries)
        print(f"\n[kanji] 漢字部分語の読み不整合: {len(findings)}件")
        for finding in findings:
            print(f"  {finding}")

    if "kana" in checks:
        findings = check_kana_shape(entries)
        print(f"\n[kana] 拗音・促音の疑い: {len(findings)}件")
        for finding in findings:
            print(f"  {finding}")

    print(
        "\n注: word/kanji は「ファイル内で揺れている」ことだけを示す。"
        "どちらが正しいかは要判断で、意図的な併記もある。"
    )
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
