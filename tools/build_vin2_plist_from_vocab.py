#!/usr/bin/env python3
"""Build references/vin2.plist from multiple vocabulary sources.

Sources (in priority order):
1) references/vin.plist
2) tmp/ÉcrituSecondVocab.json
3) tmp/ÉcrituPremierVocab.json

Matching strategy:
- exact match (including normalized alias)
- token composition for space/hyphen/slash-separated phrases
- Japanese longest-match composition for compact compounds
"""

from __future__ import annotations

import argparse
import json
import plistlib
import re
import unicodedata
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple
from xml.sax.saxutils import escape


READING_RE = re.compile(r"^[ぁ-ゖー]+$")
SEPARATOR_RE = re.compile(r"[\s\-‐‑‒–—/／,，・·]+")
JAPANESE_RE = re.compile(r"[ぁ-ゖゝゞァ-ヺー一-龯々〆〤]")
LATIN_RE = re.compile(r"[A-Za-zÀ-ÿ]")

CONNECTOR_READING = {
    "d": "ど",
    "de": "で",
    "del": "でる",
    "des": "で",
    "di": "でぃ",
    "du": "でゅ",
    "da": "だ",
    "do": "ど",
    "dos": "どす",
    "la": "ら",
    "le": "る",
    "les": "れ",
    "en": "あん",
    "et": "え",
    "of": "おぶ",
    "and": "あんど",
}

SINGLE_CHAR_OK = {
    "赤",
    "白",
    "黒",
    "山",
    "川",
    "村",
    "町",
    "県",
    "郡",
    "区",
    "東",
    "西",
    "南",
    "北",
    "上",
    "下",
    "中",
    "大",
    "小",
    "新",
    "旧",
}

GROUP1_OVERRIDES = {
    "Asti": "あすてぃ",
    "Austral": "おーすとらるー",
    "B.O.B.": "びおびー",
    "B.O.P.": "びおぴー",
    "BC V.Q.A.": "ぶりてぃっしゅころんびあゔぃーきゅーえー",
    "Baco Blanc": "ばこぶらん",
    "Bas-Armagnac": "ばーあるまにゃっく",
    "Basilicata": "ばしりかたー",
    "Bereich": "べれいぐ",
    "Bereich Saar": "べれいぐざーるー",
    "Bereich Werder": "べれいぐゔぇるでぅ",
    "Black Queen": "ぶらっくくぃーん",
    "Bourgogne": "ぶるごーにゅ",
    "Bourgogne Mousseux": "ぶるごーにゅむーすー",
    "Bourgogne Passe-Tout-Grains": "ぶるごーにゅぱすとぅぐれん",
    "Bourgogne Tonnerre": "ぶるごーにゅとんぬぇーる",
    "Cahors": "かおーる",
    "Canada": "かなだ",
    "Carnuntum": "かるぬんとぅむ",
    "Carnuntum D.A.C.": "かるぬんとぅむでぃーえーしー",
    "Crémant": "くれまん",
    "Crémant de Bourgogne": "くれまんでぶるごーにゅ",
    "Crémant de Die": "くれまんででぃ",
    "Crémant de Limoux": "くれまんでりもぅ",
    "Crémant de Loire": "くれまんでろわーるー",
    "G.I.": "じーあい",
    "G.I. Canterbury": "じーあいかんたべりー",
    "G.I. Martinborough": "じーあいまーてぃんぼろ",
    "G.I. Nagano": "じーあいながの",
    "G.I. North Canterbury": "じーあいのーすかんたべりー",
    "G.I. Osaka": "じーあいおおさか",
    "G.I. Yamagata": "じーあいやまがたー",
    "G.I. Yamanashi": "じーあいやまなし",
    "G.I. Zone": "じーあいぞーん",
    "G.I.C.": "じーあいしー",
    "G.I.イーデン・ヴァレー": "じーあいいーでんゔぁれー",
    "G.I.バロッサ": "じーあいばろっさ",
    "G.I.バロッサ・ヴァレー": "じーあいばろっさゔぁれー",
    "G.I.ブリティッシュ・コロンビア": "じーあいぶりてぃっしゅころんびあ",
    "G.I.制度": "じーあいせいど",
    "G.I.勝沼": "じーあいかつぬま",
    "G.I.指定": "じーあいしてい",
    "G.I.未指定": "じーあいみししてい",
    "G.I.登録": "じーあいとうろく",
    "G.I.登録数": "じーあいとうろくすう",
    "G.I.認定": "じーあいにんてい",
    "G.I.長野": "じーあいながの",
    "G.I.長野エクセレンス": "じーあいながのえくせれんす",
    "G.I.長野グランド": "じーあいながのぐらんど",
    "G.I.長野プラス": "じーあいながのぷらす",
    "G.I.長野プレミアム": "じーあいながのぷれみあむ",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build vin2.plist from multiple vocab sources")
    parser.add_argument("--vin2-tsv", default="references/vin2.tsv", help="Input vin2 TSV")
    parser.add_argument("--vin-plist", default="references/vin.plist", help="Input vin plist")
    parser.add_argument(
        "--second-vocab",
        default="tmp/ÉcrituSecondVocab.json",
        help="Supplemental vocab JSON",
    )
    parser.add_argument(
        "--premier-vocab",
        default="tmp/ÉcrituPremierVocab.json",
        help="Primary vocab JSON",
    )
    parser.add_argument("--output", default="references/vin2.plist", help="Output plist path")
    parser.add_argument(
        "--max-jp-segment-len",
        type=int,
        default=12,
        help="Maximum segment length for Japanese longest-match composition",
    )
    return parser.parse_args()


def normalize_reading(raw: str) -> Optional[str]:
    value = unicodedata.normalize("NFKC", raw).strip()
    if not value:
        return None
    value = value.replace("・", "").replace("･", "").replace(" ", "")
    if not value or not READING_RE.fullmatch(value):
        return None
    return value


def normalize_phrase(raw: str) -> str:
    value = unicodedata.normalize("NFKC", raw).strip()
    value = value.replace("’", "'").replace("`", "'").replace("ʼ", "'")
    value = value.replace("‐", "-").replace("‑", "-").replace("‒", "-").replace("–", "-").replace("—", "-")
    value = re.sub(r"\s+", " ", value)
    return value


def key_casefold(raw: str) -> str:
    normalized = normalize_phrase(raw)
    decomposed = unicodedata.normalize("NFD", normalized)
    without_marks = "".join(ch for ch in decomposed if unicodedata.category(ch) != "Mn")
    return without_marks.casefold()


def score_reading(reading: str, phrase: str) -> int:
    score = 100
    score += min(len(reading), 24)
    if len(reading) <= 1:
        score -= 40
    if len(set(reading)) == 1 and len(reading) >= 3:
        score -= 10
    if LATIN_RE.search(phrase):
        if len(reading) < 2:
            score -= 20
        if "ー" in reading:
            score += 2
    return score


class SourceMap:
    def __init__(self, name: str) -> None:
        self.name = name
        self.exact: Dict[str, str] = {}
        self.ambiguity: Dict[str, int] = {}
        self.norm_alias: Dict[str, str] = {}
        self.casefold_alias: Dict[str, str] = {}

    def add(self, phrase: str, reading: str) -> None:
        if phrase not in self.exact:
            self.exact[phrase] = reading
            self.ambiguity[phrase] = 1
            return

        current = self.exact[phrase]
        if current == reading:
            return

        self.ambiguity[phrase] += 1
        if score_reading(reading, phrase) > score_reading(current, phrase):
            self.exact[phrase] = reading

    def finalize_aliases(self) -> None:
        norm_best: Dict[str, Tuple[int, str]] = {}
        fold_best: Dict[str, Tuple[int, str]] = {}

        for phrase, reading in self.exact.items():
            base_score = score_reading(reading, phrase) - (self.ambiguity.get(phrase, 1) - 1) * 2

            norm_key = normalize_phrase(phrase)
            prev = norm_best.get(norm_key)
            if prev is None or base_score > prev[0]:
                norm_best[norm_key] = (base_score, reading)

            fold_key = key_casefold(phrase)
            prev_fold = fold_best.get(fold_key)
            if prev_fold is None or base_score > prev_fold[0]:
                fold_best[fold_key] = (base_score, reading)

        self.norm_alias = {key: value for key, (_, value) in norm_best.items()}
        self.casefold_alias = {key: value for key, (_, value) in fold_best.items()}

    def lookup(self, phrase: str, allow_ambiguous: bool) -> Optional[str]:
        exact = self.exact.get(phrase)
        if exact is not None:
            if allow_ambiguous or self.ambiguity.get(phrase, 1) <= 3:
                return exact

        normalized = normalize_phrase(phrase)
        alias = self.norm_alias.get(normalized)
        if alias is not None:
            return alias

        fold = self.casefold_alias.get(key_casefold(phrase))
        if fold is not None:
            return fold

        return None


def load_vin_plist(path: Path) -> SourceMap:
    source = SourceMap("vin")
    with path.open("rb") as f:
        obj = plistlib.load(f)

    if not isinstance(obj, list):
        return source

    for entry in obj:
        if not isinstance(entry, dict):
            continue
        raw_phrase = entry.get("phrase")
        raw_reading = entry.get("shortcut")
        if not isinstance(raw_phrase, str) or not isinstance(raw_reading, str):
            continue
        phrase = raw_phrase.strip()
        reading = normalize_reading(raw_reading)
        if not phrase or reading is None:
            continue
        source.add(phrase, reading)

    source.finalize_aliases()
    return source


def load_vocab_json(path: Path, name: str) -> SourceMap:
    source = SourceMap(name)
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        return source

    for raw_reading, raw_candidates in payload.items():
        if not isinstance(raw_reading, str) or not isinstance(raw_candidates, list):
            continue
        reading = normalize_reading(raw_reading)
        if reading is None:
            continue

        for candidate in raw_candidates:
            if not isinstance(candidate, str):
                continue
            phrase = candidate.strip()
            if not phrase:
                continue
            source.add(phrase, reading)

    source.finalize_aliases()
    return source


def load_vin2_groups(path: Path) -> Tuple[List[str], List[str]]:
    group1: List[str] = []
    group2: List[str] = []
    current = group1

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith("#"):
            if line.startswith("# ---"):
                current = group2
            continue
        current.append(line)

    return group1, group2


def dedupe_keep_order(items: Sequence[str]) -> List[str]:
    seen = set()
    result: List[str] = []
    for item in items:
        if item in seen:
            continue
        seen.add(item)
        result.append(item)
    return result


def lookup_priority(
    phrase: str,
    vin: SourceMap,
    second: SourceMap,
    premier: SourceMap,
) -> Tuple[Optional[str], Optional[str]]:
    reading = vin.lookup(phrase, allow_ambiguous=True)
    if reading is not None:
        return reading, "vin"

    reading = second.lookup(phrase, allow_ambiguous=True)
    if reading is not None:
        return reading, "second"

    allow_premier_ambiguous = len(phrase) >= 5
    reading = premier.lookup(phrase, allow_ambiguous=allow_premier_ambiguous)
    if reading is not None:
        return reading, "premier"

    return None, None


def number_to_hiragana(value: int) -> Optional[str]:
    if value < 0 or value > 9999:
        return None
    if value == 0:
        return "ぜろ"

    ones = ["", "いち", "に", "さん", "よん", "ご", "ろく", "なな", "はち", "きゅう"]
    result = ""

    if value >= 1000:
        q, value = divmod(value, 1000)
        if q == 1:
            result += "せん"
        else:
            result += ones[q] + "せん"

    if value >= 100:
        q, value = divmod(value, 100)
        if q == 1:
            result += "ひゃく"
        else:
            result += ones[q] + "ひゃく"

    if value >= 10:
        q, value = divmod(value, 10)
        if q == 1:
            result += "じゅう"
        else:
            result += ones[q] + "じゅう"

    if value > 0:
        result += ones[value]

    return result or None


def split_latin_apostrophe(text: str) -> str:
    return re.sub(r"(?i)\b([djl])'", r"\1 ", text)


def compose_from_tokens(
    phrase: str,
    vin: SourceMap,
    second: SourceMap,
    premier: SourceMap,
) -> Optional[str]:
    preprocessed = split_latin_apostrophe(phrase)
    parts = [part for part in SEPARATOR_RE.split(preprocessed) if part]
    if len(parts) <= 1:
        return None

    composed: List[str] = []
    for part in parts:
        lower = part.casefold()
        connector = CONNECTOR_READING.get(lower)
        if connector is not None:
            composed.append(connector)
            continue

        if part.isdigit():
            number_reading = number_to_hiragana(int(part))
            if number_reading is not None:
                composed.append(number_reading)
                continue

        num_unit = re.fullmatch(r"(\d+)(.+)", part)
        if num_unit is not None:
            number_text, unit_text = num_unit.groups()
            number_reading = number_to_hiragana(int(number_text))
            unit_reading, _ = lookup_priority(unit_text, vin, second, premier)
            if number_reading is not None and unit_reading is not None:
                composed.append(number_reading + unit_reading)
                continue

        reading, _ = lookup_priority(part, vin, second, premier)
        if reading is None:
            return None
        composed.append(reading)

    merged = "".join(composed)
    if normalize_reading(merged) is None:
        return None
    return merged


def compose_japanese_longest(
    phrase: str,
    vin: SourceMap,
    second: SourceMap,
    premier: SourceMap,
    max_segment_len: int,
) -> Optional[str]:
    if not JAPANESE_RE.search(phrase):
        return None
    if SEPARATOR_RE.search(phrase):
        return None

    length = len(phrase)
    best: List[Optional[Tuple[int, int, str]]] = [None] * (length + 1)
    best[0] = (0, 0, "")

    for i in range(length):
        state = best[i]
        if state is None:
            continue
        score_i, seg_i, reading_i = state

        upper = min(length, i + max_segment_len)
        for j in range(upper, i, -1):
            part = phrase[i:j]
            if len(part) == 1 and part not in SINGLE_CHAR_OK:
                continue

            part_reading, _ = lookup_priority(part, vin, second, premier)
            if part_reading is None:
                continue

            merged = reading_i + part_reading
            if normalize_reading(merged) is None:
                continue

            seg_count = seg_i + 1
            part_score = score_i + (j - i) * 10 - 4
            candidate = (part_score, seg_count, merged)

            current = best[j]
            if current is None or candidate[0] > current[0] or (
                candidate[0] == current[0] and candidate[1] < current[1]
            ):
                best[j] = candidate

    final_state = best[length]
    if final_state is None:
        return None

    _, seg_count, reading = final_state
    if seg_count <= 1:
        return None
    return reading


def group1_longest_substring(phrase: str, vin: SourceMap) -> Optional[str]:
    phrase_key = key_casefold(phrase)
    best_len = 0
    best_reading: Optional[str] = None

    for known_phrase, known_reading in vin.exact.items():
        if len(known_phrase) < 3:
            continue
        if key_casefold(known_phrase) in phrase_key and len(known_phrase) > best_len:
            best_len = len(known_phrase)
            best_reading = known_reading

    if best_len >= 3:
        return best_reading
    return None


def resolve_reading(
    phrase: str,
    vin: SourceMap,
    second: SourceMap,
    premier: SourceMap,
    max_segment_len: int,
    is_group1: bool,
) -> Tuple[Optional[str], Optional[str]]:
    if is_group1:
        override = GROUP1_OVERRIDES.get(phrase)
        if override is not None and normalize_reading(override) is not None:
            return override, "group1-override"

    reading, source = lookup_priority(phrase, vin, second, premier)
    if reading is not None:
        return reading, source

    token_reading = compose_from_tokens(phrase, vin, second, premier)
    if token_reading is not None:
        return token_reading, "token-composed"

    jp_reading = compose_japanese_longest(phrase, vin, second, premier, max_segment_len)
    if jp_reading is not None:
        return jp_reading, "jp-longest"

    if is_group1:
        substring_reading = group1_longest_substring(phrase, vin)
        if substring_reading is not None:
            return substring_reading, "group1-substr"

    return None, None


def emit_plist_lines(group1_rows: Sequence[Tuple[str, str]], group2_rows: Sequence[Tuple[str, str]]) -> List[str]:
    lines = [
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
        "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">",
        "<plist version=\"1.0\">",
        "<array>",
    ]

    if group1_rows:
        lines.append("\t<!-- ワイン関連用語 (地名・種名など) -->")
        for phrase, reading in group1_rows:
            lines.append(
                "\t<dict><key>phrase</key><string>"
                f"{escape(phrase)}</string><key>shortcut</key><string>{escape(reading)}</string></dict>"
            )

    if group2_rows:
        lines.append("\t<!-- ワイン関連技術用語・その他 -->")
        for phrase, reading in group2_rows:
            lines.append(
                "\t<dict><key>phrase</key><string>"
                f"{escape(phrase)}</string><key>shortcut</key><string>{escape(reading)}</string></dict>"
            )

    lines.append("</array>")
    lines.append("</plist>")
    return lines


def count_nonempty(values: Iterable[Optional[str]]) -> int:
    return sum(1 for value in values if value)


def main() -> int:
    args = parse_args()

    vin2_path = Path(args.vin2_tsv)
    vin_path = Path(args.vin_plist)
    second_path = Path(args.second_vocab)
    premier_path = Path(args.premier_vocab)
    output_path = Path(args.output)

    group1_raw, group2_raw = load_vin2_groups(vin2_path)
    group1_items = dedupe_keep_order(group1_raw)
    group2_items = dedupe_keep_order(group2_raw)

    vin = load_vin_plist(vin_path)
    second = load_vocab_json(second_path, "second")
    premier = load_vocab_json(premier_path, "premier")

    strategy_counts: Dict[str, int] = {}
    group1_rows: List[Tuple[str, str]] = []
    group2_rows: List[Tuple[str, str]] = []

    for phrase in group1_items:
        reading, strategy = resolve_reading(phrase, vin, second, premier, args.max_jp_segment_len, True)
        if reading is None or strategy is None:
            continue
        group1_rows.append((phrase, reading))
        strategy_counts[strategy] = strategy_counts.get(strategy, 0) + 1

    for phrase in group2_items:
        reading, strategy = resolve_reading(phrase, vin, second, premier, args.max_jp_segment_len, False)
        if reading is None or strategy is None:
            continue
        group2_rows.append((phrase, reading))
        strategy_counts[strategy] = strategy_counts.get(strategy, 0) + 1

    plist_text = "\n".join(emit_plist_lines(group1_rows, group2_rows)) + "\n"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(plist_text, encoding="utf-8")

    total = len(group1_items) + len(group2_items)
    found = len(group1_rows) + len(group2_rows)
    missing = total - found

    print(f"wrote: {output_path}")
    print(f"group1={len(group1_rows)}/{len(group1_items)}")
    print(f"group2={len(group2_rows)}/{len(group2_items)}")
    print(f"total={found}/{total} missing={missing}")
    print("strategy:")
    for key in sorted(strategy_counts.keys()):
        print(f"  {key}: {strategy_counts[key]}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
