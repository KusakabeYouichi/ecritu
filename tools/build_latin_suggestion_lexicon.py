#!/usr/bin/env python3
"""Build LatinSuggestionLexicon_{lang}.txt (英/仏/独/伊の汎用サジェスト語彙) from
wordfreq top lists (en/de/it) and Lexique 3.83 (fr).

2026-08-31: Leipzig Corpora は公式 Terms of Usage が CC BY-NC(商用不可)のため撤去し、
en/de/it の頻度源を wordfreq(データ CC BY-SA 4.0)へ移行。wordfreq は全語を小文字化し
ドイツ語の ß も ss に正規化するため、de の表示形は Tatoeba 独文(CC-BY 2.0 FR)の
ケース付き出現数(旧 Leipzig 実装と同じ「優勢表記+大文字は3倍超のみ」規則)と
deWiktionary 見出し(CC BY-SA)のフォールバックで復元する。

Sources (downloaded separately, not committed; tmp/latin_sources/ 推奨):
- wordfreq: python3 -m venv venv && venv/bin/pip install wordfreq &&
  venv/bin/python3 -c "from wordfreq import top_n_list; import sys;
  open('wf_en.txt','w').write('\n'.join(top_n_list('en',40000)))" (de=120000/it=40000)
- Tatoeba: https://downloads.tatoeba.org/exports/per_language/deu/deu_sentences.tsv.bz2
- deWiktionary: https://dumps.wikimedia.org/dewiktionary/latest/dewiktionary-latest-all-titles-in-ns0.gz (展開して渡す)
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
- wordfreq (data: CC BY-SA 4.0) — R. Speer ほか(SUBTLEX 等の元コーパス作者のクレジット必須)
- Tatoeba (CC-BY 2.0 FR) — 独語表示形の復元に使用
- Wiktionary (CC BY-SA) — 独語表示形のフォールバックに使用
- Lexique 3.83 (CC BY-SA 4.0) — B. New, C. Pallier
"""

from __future__ import annotations

import argparse
import re
import subprocess
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


def load_wordfreq_list(path: Path, lang: str) -> list[str]:
    """wordfreq top_n_list のダンプ(1行1語、頻度順)を読む。全語小文字。"""
    words = [w.strip() for w in path.read_text(encoding="utf-8").splitlines() if w.strip()]
    return [w for w in words if is_clean_word(w, lang)] if lang != "de" else words


def _fold_de(word: str) -> str:
    # wordfreq が ß を ss に正規化するため、照合キーは小文字+ß→ss で揃える
    return word.lower().replace("ß", "ss")


_DE_TOKEN = re.compile(r"[A-Za-zÄÖÜäöüß][A-Za-zÄÖÜäöüß'’\-]*")


def load_tatoeba_cased_counts(path: Path) -> dict[str, dict[str, int]]:
    """Tatoeba 独文からケース付き出現数を数える。文頭トークンは大文字バイアスが
    あるので除外する。キーは _fold_de。"""
    counts: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    for line in path.read_text(encoding="utf-8").splitlines():
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        words = _DE_TOKEN.findall(parts[2])
        for w in words[1:]:
            counts[_fold_de(w)][w] += 1
    return counts


def load_wiktionary_titles(path: Path) -> dict[str, set[str]]:
    pat = re.compile(r"^[A-Za-zÄÖÜäöüß\-]+$")
    by_fold: dict[str, set[str]] = defaultdict(set)
    for t in path.read_text(encoding="utf-8").splitlines():
        t = t.strip()
        if t and " " not in t and pat.match(t):
            by_fold[_fold_de(t)].add(t)
    return by_fold


def _dominant_cased(variants: dict[str, int]) -> str | None:
    """旧 Leipzig 実装と同じ規則: 小文字と大文字始まりの両表記があるときは、
    大文字側が3倍超の頻度のときだけ大文字(ほぼ常に大文字=名詞)を採用。"""
    lower = [w for w in variants if not w[0].isupper()]
    upper = [w for w in variants if w[0].isupper() and not w.isupper()]
    if not lower and not upper:
        return None
    if not lower:
        return max(upper, key=lambda w: variants[w])
    if not upper:
        return max(lower, key=lambda w: variants[w])
    best_upper = max(upper, key=lambda w: variants[w])
    best_lower = max(lower, key=lambda w: variants[w])
    if variants[best_upper] > variants[best_lower] * 3:
        return best_upper
    return best_lower


def _wiktionary_display(fold_key: str, by_fold: dict[str, set[str]]) -> str | None:
    forms = by_fold.get(fold_key)
    if not forms:
        return None
    lowers = [f for f in forms if not f[0].isupper()]
    caps = [f for f in forms if f[0].isupper() and not f.isupper()]
    if lowers:
        # 小文字見出しが存在する語は小文字(動詞・機能語)。ß付きを優先して ss化を戻す
        return sorted(lowers, key=lambda f: ("ß" not in f, len(f)))[0]
    if caps:
        return sorted(caps, key=lambda f: ("ß" not in f, len(f)))[0]
    return None


# ß/ss 同キーの目視分類(2026-08-31、全50ペアを検査)で確定した除去リスト。
# 旧正書法(1996年改革前: 短母音+ß — daß/bißchen/mußte 等)と、標準独語では ß が
# 正書のもののスイス綴り(Einbussen/Stössen 等)、および紛れ込んだ固有名。
# 別語ペア(Busse/Buße, Masse/Maße, massig/mäßig, müsse/Muße, schoss/Schoß,
# säße, büßen/Bussen)は両方とも残る。
DE_DISPLAY_BLOCKLIST = {
    # 旧正書法(→ss が現行)
    "Abschluß", "aufgepaßt", "bewußt", "bewußtlos", "bißchen", "daß", "eßt",
    "Fitneßstudio", "gefaßt", "gehaßt", "gestreßt", "gewußt", "goß", "haßte",
    "Kompromiß", "laßt", "Mißerfolg", "mißtrauisch", "mißverstanden", "mußt",
    "müßt", "müßte", "müßten", "müßtest", "mußtest", "Obergeschoß", "Paßwort",
    "Rußland", "Schuß", "Streß", "Tschüß", "vergeßt", "Verlaß", "verläßlich",
    "vermißt", "wißt", "wußte", "wußten", "wußtest", "wüßten", "wußtet",
    # スイス綴り(標準独語は ß: Einbußen/Stößen/Verstöße(n))
    "Einbussen", "Stössen", "Verstösse", "Verstössen",
    # 固有名の紛れ込み
    "Sasse",
}


def load_wordfreq_de(
    path: Path,
    tatoeba_counts: dict[str, dict[str, int]],
    wikt_by_fold: dict[str, set[str]],
    min_tatoeba: int = 3,
) -> list[str]:
    """de は表示形の復元つき: Tatoeba の優勢表記 → Wiktionary 見出しの順で決め、
    どちらにも無い語(小文字化された固有名・外来語が主)は表示形が保証できないので
    落とす。"""
    out: list[str] = []
    seen: set[str] = set()

    def displays_for(key: str) -> list[str]:
        # ß→ss 畳み込みは Buße/Busse・Maße/Masse のような別語も同じキーに束ねる
        # (1996年正書法: 長母音+ß / 短母音+ss)。ß系と ss系の両ファミリーが実在する
        # 場合は、それぞれの優勢表記を両方出す。
        variants = tatoeba_counts.get(key)
        if variants and sum(variants.values()) >= min_tatoeba:
            fam_ss = {w: n for w, n in variants.items() if "ß" not in w}
            fam_sz = {w: n for w, n in variants.items() if "ß" in w}
            results = []
            primary_fam, other_fam = (
                (fam_ss, fam_sz)
                if sum(fam_ss.values()) >= sum(fam_sz.values())
                else (fam_sz, fam_ss)
            )
            d = _dominant_cased(primary_fam) if primary_fam else None
            if d:
                results.append(d)
            # 副ファミリーは「絶対数>=10 かつ 主ファミリーの15%以上」のときだけ出す。
            # 本物の別語ペア(Buße/Busse, Maße/Masse)は両者とも常用なので通り、
            # 旧正書法(Abschluß)やスイス綴り(abfliessen)の微量出現は落ちる
            if other_fam and sum(other_fam.values()) >= max(
                10, sum(primary_fam.values()) * 15 // 100
            ):
                d2 = _dominant_cased(other_fam)
                if d2:
                    results.append(d2)
            if results:
                return results
        forms = wikt_by_fold.get(key, set())
        fam_ss = {f for f in forms if "ß" not in f}
        fam_sz = {f for f in forms if "ß" in f}
        if fam_ss and fam_sz:
            # 頻度情報が無い場合の ß/ss 判定: 1996年正書法では ß は長母音・二重母音の
            # 直後のみ。綴りから確実に分かるのは二重母音(ei/au/äu/eu)と ie で、
            # その場合だけ ß形(weiß/fließen)。単母音直後は長さが判定できないため
            # ss形を選ぶ(短母音なら正書、長母音でもスイス綴りとして読める)。
            sample = next(iter(fam_sz))
            idx = sample.find("ß")
            before = sample[max(0, idx - 2):idx].lower()
            diphthongs = ("ei", "au", "äu", "eu", "ie")
            fam = fam_sz if before.endswith(diphthongs) else fam_ss
        else:
            fam = fam_sz or fam_ss
        if not fam:
            return []
        d = _wiktionary_display(key, {key: fam})
        return [d] if d else []

    for w in path.read_text(encoding="utf-8").splitlines():
        w = w.strip()
        if not w:
            continue
        for display in displays_for(_fold_de(w)):
            if display in DE_DISPLAY_BLOCKLIST:
                continue
            if not is_clean_word(display, "de"):
                continue
            if display in seen:
                continue
            seen.add(display)
            out.append(display)
    return out


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
    parser.add_argument("--wordfreq-en", required=True, type=Path)
    parser.add_argument("--wordfreq-de", required=True, type=Path)
    parser.add_argument("--wordfreq-it", required=True, type=Path)
    parser.add_argument("--tatoeba-de", required=True, type=Path)
    parser.add_argument("--dewikt-titles", required=True, type=Path)
    parser.add_argument("--lexique", type=Path, help="Lexique383.tsv(省略時は fr を生成しない)")
    parser.add_argument("--top", type=int, default=5000)
    parser.add_argument("--top-en", type=int, help="英語の語数(未指定は--top)")
    parser.add_argument("--top-fr", type=int, help="フランス語の語数(未指定は--top)")
    parser.add_argument("--top-de", type=int, help="ドイツ語の語数(未指定は--top)")
    parser.add_argument("--top-it", type=int, help="イタリア語の語数(未指定は--top)")
    parser.add_argument("--min-count", type=int, default=3, help="Tatoeba照合の最低出現数")
    parser.add_argument(
        "--output-dir", required=True, type=Path,
        help="LatinSuggestionLexicon_{lang}.txt の出力先ディレクトリ")
    parser.add_argument("--review-dir", type=Path, help="言語別レビュー用リストの出力先")
    return parser.parse_args()


def fold_search_keys(words: list[str]) -> list[str]:
    """実行時(Swift)と同一の折り畳みで検索キーを計算する。Python側で近似実装せず、
    tools/fold_latin_keys.swift に委譲して完全一致を保証する。"""
    script = Path(__file__).parent / "fold_latin_keys.swift"
    result = subprocess.run(
        ["swift", str(script)],
        input="\n".join(words) + "\n",
        capture_output=True, text=True, check=True,
    )
    keys = result.stdout.splitlines()
    if len(keys) != len(words):
        raise RuntimeError(f"fold key count mismatch: {len(keys)} != {len(words)}")
    return keys


def main() -> None:
    args = parse_args()
    tatoeba_counts = load_tatoeba_cased_counts(args.tatoeba_de)
    wikt_by_fold = load_wiktionary_titles(args.dewikt_titles)
    lists = {
        "en": load_wordfreq_list(args.wordfreq_en, "en")[: args.top_en or args.top],
        "de": load_wordfreq_de(
            args.wordfreq_de, tatoeba_counts, wikt_by_fold, args.min_count
        )[: args.top_de or args.top],
        "it": load_wordfreq_list(args.wordfreq_it, "it")[: args.top_it or args.top],
    }
    if args.lexique:
        lists["fr"] = load_lexique(args.lexique)[: args.top_fr or args.top]
    args.output_dir.mkdir(parents=True, exist_ok=True)
    for lang, words in lists.items():
        keys = fold_search_keys(words)
        # 実行時は読むだけで検索できるよう、キー順にソートして key\tword\trank で出力
        rows = sorted(
            ((keys[i], words[i], i) for i in range(len(words))),
            key=lambda row: (row[0], row[2]),
        )
        out = args.output_dir / f"LatinSuggestionLexicon_{lang}.txt"
        out.write_text(
            "\n".join(f"{k}\t{w}\t{r}" for k, w, r in rows) + "\n",
            encoding="utf-8",
        )
        print(f"{lang}: {len(words)} words -> {out}")
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
