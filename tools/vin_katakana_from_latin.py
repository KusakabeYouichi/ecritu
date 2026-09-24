#!/usr/bin/env python3
"""vin.plist のラテン文字エントリに対応するカタカナエントリを作る(3206)。

読み(shortcut)をカタカナに直すだけでは中黒が入らないので、区切り(空白・ハイフン)の位置は
既存の「ラテン+カタカナが同じ読みで並んでいる組」1,247 組から語→カタカナの対応を学習し、
語ごとに読みを切って中黒でつなぐ。学習で埋まらないものは中黒なしで出し、要確認の印を付ける。

  一覧を出す: python3 tools/vin_katakana_from_latin.py --out tmp/vin_katakana_candidates.tsv
  登録する  : python3 tools/vin_katakana_from_latin.py --apply tmp/vin_katakana_candidates.tsv
"""
from __future__ import annotations

import argparse
import plistlib
import re
import sys
import unicodedata
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VIN = ROOT / "references" / "vin.plist"

KATAKANA = re.compile(r"[ァ-ヺー・ㇰ-ㇿ]")
HIRAGANA = re.compile(r"[ぁ-ゖ]")
KANJI = re.compile(r"[一-鿿々]")
SEPARATORS = re.compile(r"[  \-‐–—]+")


def is_latin_letter(ch: str) -> bool:
    return ch.isalpha() and unicodedata.name(ch, "").startswith("LATIN")


def kind_of(phrase: str) -> str:
    has_latin = any(is_latin_letter(c) for c in phrase)
    has_kata = bool(KATAKANA.search(phrase))
    has_hira = bool(HIRAGANA.search(phrase))
    has_kanji = bool(KANJI.search(phrase))
    if has_latin and not (has_kata or has_hira or has_kanji):
        return "latin"
    if has_kata and not (has_latin or has_hira or has_kanji):
        return "katakana"
    return "other"


def to_katakana(hira: str) -> str:
    return "".join(chr(ord(c) + 0x60) if "ぁ" <= c <= "ゖ" else c for c in hira)


def normalize_token(token: str) -> str:
    folded = unicodedata.normalize("NFKD", token.lower())
    return "".join(c for c in folded if not unicodedata.combining(c) and (c.isalnum()))


def tokens_of(phrase: str) -> list[str]:
    return [t for t in SEPARATORS.split(phrase) if t]


def load_entries() -> list[dict]:
    return plistlib.load(VIN.open("rb"))


def build_lexicon(entries: list[dict]) -> dict[str, set[str]]:
    """語(正規化) → カタカナ表記の候補集合。既存の対訳組と 1 語エントリから学習する。"""
    latin_by_reading: dict[str, list[str]] = defaultdict(list)
    kata_by_reading: dict[str, list[str]] = defaultdict(list)
    for entry in entries:
        kind = kind_of(entry["phrase"])
        if kind == "latin":
            latin_by_reading[entry["shortcut"]].append(entry["phrase"])
        elif kind == "katakana":
            kata_by_reading[entry["shortcut"]].append(entry["phrase"])

    lexicon: dict[str, set[str]] = defaultdict(set)
    for reading in set(latin_by_reading) & set(kata_by_reading):
        latin = latin_by_reading[reading][0]
        katakana = kata_by_reading[reading][0]
        words = tokens_of(latin)
        chunks = [c for c in katakana.split("・") if c]
        if len(words) == len(chunks):
            for word, chunk in zip(words, chunks):
                key = normalize_token(word)
                if key:
                    lexicon[key].add(chunk)
        elif len(words) == 1 and chunks:
            lexicon[normalize_token(latin)].add(katakana)
    # 1 語だけのラテンエントリは読みがそのまま語の読み
    for reading, phrases in latin_by_reading.items():
        for phrase in phrases:
            if len(tokens_of(phrase)) == 1:
                key = normalize_token(phrase)
                if key:
                    lexicon[key].add(to_katakana(reading))
    return lexicon


# ラテン文字の頭文字ごとに、カタカナ側の先頭に来うる字(未知語の切り出しを絞る錨)。
# フランス語の h は無音なので母音を、c/g は前舌母音で音が変わるので両方を許す。
INITIAL_KANA_BY_LETTER: dict[str, str] = {
    "a": "アイウエオァィゥェォヤユヨワ", "b": "バビブベボヴ", "c": "カキクケコサシスセソシャシュショチ",
    "d": "ダヂヅデドディドゥ", "e": "アイウエオァィゥェォヤユヨワ", "f": "ファフィフフェフォ",
    "g": "ガギグゲゴジャジジュジェジョ", "h": "ハヒフヘホアイウエオ",
    "i": "アイウエオァィゥェォヤユヨワ", "j": "ジャジジュジェジョヤユヨハヒフヘホ", "k": "カキクケコ",
    "l": "ラリルレロ", "m": "マミムメモ", "n": "ナニヌネノ", "o": "アイウエオァィゥェォヤユヨワ",
    "p": "パピプペポ", "q": "カキクケコ", "r": "ラリルレロ",
    "s": "サシスセソシャシュショ", "t": "タチツテトティトゥ", "u": "アイウエオァィゥェォヤユヨワ",
    "v": "ヴバビブベボ", "w": "ワウヴ", "x": "クグキサシ", "y": "イヤユヨ",
    "z": "ザジズゼゾツ",
}


def initial_matches(word: str, chunk: str) -> bool:
    """未知語の切り出しが、その語の頭文字と噛み合っているか。"""
    key = normalize_token(word)
    if not key or not chunk:
        return True
    letter = key[0]
    if letter.isdigit():
        return True
    allowed = INITIAL_KANA_BY_LETTER.get(letter)
    if not allowed:
        return True
    return chunk[0] in allowed or chunk[:2] in {allowed[i:i + 2] for i in range(0, len(allowed), 2)}


def split_reading(katakana_reading: str, words: list[str], lexicon: dict[str, set[str]]) -> tuple[list[str] | None, bool]:
    """語の並びに沿って読みのカタカナを切る。

    既知語はその表記で、未知語は「1 文字以上の任意の並び」として照合する(既知語が錨になる)。
    解が 1 つに定まったときだけ返す。戻り値は (区切り, 未知語を含むか)。
    """
    max_unknown = 14
    solutions: list[list[str]] = []

    def walk(index: int, position: int, acc: list[str]) -> None:
        if len(solutions) > 1:
            return
        if index == len(words):
            if position == len(katakana_reading):
                solutions.append(list(acc))
            return
        remaining = len(katakana_reading) - position
        if remaining <= 0:
            return
        candidates = lexicon.get(normalize_token(words[index])) or set()
        if candidates:
            for candidate in sorted(candidates, key=len, reverse=True):
                if katakana_reading.startswith(candidate, position):
                    acc.append(candidate)
                    walk(index + 1, position + len(candidate), acc)
                    acc.pop()
            return
        for length in range(1, min(max_unknown, remaining) + 1):
            chunk = katakana_reading[position: position + length]
            if not initial_matches(words[index], chunk):
                break
            acc.append(chunk)
            walk(index + 1, position + length, acc)
            acc.pop()

    walk(0, 0, [])
    if len(solutions) != 1:
        # 既知語の表記が合わない(同じ綴りで別の転写)ときは、頭文字だけを頼りに切り直す
        solutions.clear()
        lexicon_backup = lexicon
        lexicon = {}
        walk(0, 0, [])
        lexicon = lexicon_backup
        if len(solutions) != 1:
            return None, False
        return solutions[0], True
    chunks = solutions[0]
    has_unknown = any(not (lexicon.get(normalize_token(w)) or set()) for w in words)
    return chunks, has_unknown


def build_candidates(entries: list[dict]) -> list[dict]:
    lexicon = build_lexicon(entries)
    # 既存の対訳組から直接学べた語(この語だけで解けた区切りは確度が高い)
    attested = {key for key, values in lexicon.items() if values}
    # 解けた区切りから語彙を増やして解き直す(Anjou Gamay が解ければ Anjou が錨になる)。
    # 増えなくなるまで、多くても 4 周
    for _ in range(4):
        learned = 0
        for entry in entries:
            if kind_of(entry["phrase"]) != "latin":
                continue
            words = tokens_of(entry["phrase"])
            if len(words) <= 1:
                continue
            chunks, _unknown = split_reading(to_katakana(entry["shortcut"]), words, lexicon)
            if not chunks:
                continue
            for word, chunk in zip(words, chunks):
                key = normalize_token(word)
                if key and chunk not in lexicon[key]:
                    lexicon[key].add(chunk)
                    learned += 1
        if learned == 0:
            break
    kata_readings = {e["shortcut"] for e in entries if kind_of(e["phrase"]) == "katakana"}
    existing = {(e["phrase"], e["shortcut"]) for e in entries}
    rows: list[dict] = []
    seen: set[tuple[str, str]] = set()
    for entry in entries:
        if kind_of(entry["phrase"]) != "latin":
            continue
        reading = entry["shortcut"]
        if reading in kata_readings:
            continue
        katakana_reading = to_katakana(reading)
        words = tokens_of(entry["phrase"])
        if len(words) <= 1:
            proposal, confidence = katakana_reading, "単語1つ"
        else:
            chunks, _unknown = split_reading(katakana_reading, words, lexicon)
            if chunks:
                proposal = "・".join(chunks)
                inferred = any(normalize_token(w) not in attested for w in words)
                confidence = "区切り推定(推定語あり)" if inferred else "区切り推定"
            else:
                proposal, confidence = katakana_reading, "要確認(中黒なし)"
        key = (proposal, reading)
        if key in existing or key in seen:
            continue
        seen.add(key)
        rows.append({
            "reading": reading,
            "latin": entry["phrase"],
            "katakana": proposal,
            "confidence": confidence,
        })
    return rows


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, help="候補一覧(TSV)の出力先")
    parser.add_argument("--apply", type=Path, help="確認済み TSV を vin.plist へ登録する")
    parser.add_argument(
        "--missing-latin", type=Path,
        help="逆向きの一覧: カタカナだけでラテン表記が無い読みを TSV で出す(ラテン側は機械生成できない)"
    )
    args = parser.parse_args()

    entries = load_entries()
    if args.missing_latin:
        write_missing_latin(entries, args.missing_latin)
        return 0
    if args.apply:
        add_from_tsv(entries, args.apply)
        return 0

    rows = build_candidates(entries)
    order = {"要確認(中黒なし)": 0, "区切り推定(推定語あり)": 1, "区切り推定": 2, "単語1つ": 3}
    rows.sort(key=lambda r: (order.get(r["confidence"], 9), r["reading"]))
    lines = ["読み\tラテン表記\t追加するカタカナ\t区切りの根拠"]
    lines += [f"{r['reading']}\t{r['latin']}\t{r['katakana']}\t{r['confidence']}" for r in rows]
    text = "\n".join(lines) + "\n"
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text, encoding="utf-8")
        print(f"wrote: {args.out} ({len(rows)} 件)")
    else:
        sys.stdout.write(text)
    counts: dict[str, int] = defaultdict(int)
    for row in rows:
        counts[row["confidence"]] += 1
    for key, value in sorted(counts.items(), key=lambda x: -x[1]):
        print(f"  {key}: {value}")
    return 0


def write_missing_latin(entries: list[dict], out: Path) -> None:
    """カタカナ表記だけで、同じ読みのラテン表記が無いものを一覧にする(3207)。

    ラテン表記は綴りが機械的に決まらない(カタカナからは復元できない)ので、読みとカタカナだけを出す。
    """
    latin_readings = {e["shortcut"] for e in entries if kind_of(e["phrase"]) == "latin"}
    rows = [
        (e["shortcut"], e["phrase"])
        for e in entries
        if kind_of(e["phrase"]) == "katakana" and e["shortcut"] not in latin_readings
    ]
    rows.sort()
    lines = ["読み\tカタカナ表記"] + [f"{r}\t{p}" for r, p in rows]
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote: {out} ({len(rows)} 件 / {len({r for r, _ in rows})} 読み)")


def add_from_tsv(entries: list[dict], tsv: Path) -> None:
    """TSV の 3 列目(カタカナ)を vin.plist の末尾の専用節へ追加する。"""
    rows = []
    for line in tsv.read_text(encoding="utf-8").splitlines()[1:]:
        if not line.strip():
            continue
        parts = line.split("\t")
        if len(parts) < 3 or not parts[2]:
            continue
        rows.append((parts[2], parts[0]))
    existing = {(e["phrase"], e["shortcut"]) for e in entries}
    additions = [(p, r) for p, r in rows if (p, r) not in existing]
    text = VIN.read_text(encoding="utf-8")
    marker = "</array>"
    block = ["\t<!-- □ ラテン表記だけだった語のカタカナ表記(3206。読みから機械生成し目視確認済み) -->"]
    block += [
        f"\t<dict><key>phrase</key><string>{p}</string><key>shortcut</key><string>{r}</string></dict>"
        for p, r in additions
    ]
    text = text.replace(marker, "\n".join(block) + "\n" + marker)
    VIN.write_text(text, encoding="utf-8")
    print(f"added: {len(additions)} 件")


if __name__ == "__main__":
    raise SystemExit(main())
