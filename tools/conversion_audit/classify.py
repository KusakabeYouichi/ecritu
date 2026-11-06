#!/usr/bin/env python3
"""一括検査の結果(testDiagnosticConversionAudit の TSV)を 3 つに分ける(3640)。
使い方: python3 -I tools/conversion_audit/classify.py <audit_out.tsv> <出力ディレクトリ>
入力の列: 読み, 期待, 文番号, 印, 先頭の候補, ok/ng, 期待が候補列に有るか, 上位 6 件
出力:
  c_ok.tsv        正しく変換できた(先頭が期待と一致)
  c_policy.tsv    先頭は違うが écritu の表記方針(かなで書く言葉)の範囲(事→こと 等)。直さない
  c_style.tsv     期待(書き手)がかな書きで écritu は漢字(あと→後、みそ汁→味噌汁)。書き手の流儀なので直さない
  a_register.tsv  期待の表記が候補列に無い(語の登録が要る見込み。読みの推定違いも混ざる)
  b_logic.tsv     期待の表記は候補列に有るが先頭でない(並び・区切りのロジック。segments.py で 区切り を b_segment.tsv に分ける)
a/b には 段階(1=直すべし 2=できたら直すべし 3=直さなくていい)と理由を付ける。段階は機械的な目安:
  固有名詞を含む断片は 3。違う部分がカタカナなら 語 LM に有れば 2、無ければ 3(人名・作品名の見込み)。
  漢字を含む違いは 語 LM に有って期待が 10 字以下なら 1、長ければ 2、LM に無ければ 2(稀な語か読みの推定違い)。
  先頭が空(候補なし。カタカナ語は長押しでカタカナ確定できる)は理由に印を付ける。
  期待の表記がかな書きの方針と違うだけなら c_policy。
"""
import os
import sys

# écritu がかなで書く(漢字を先頭に出さない)語。期待側の漢字をかなに正規化して比べる
KANA_POLICY = [
    ("事", "こと"), ("出来", "でき"), ("等", "など"), ("迄", "まで"), ("様", "よう"), ("居", "い"), ("頂", "いただ"),
    ("下さい", "ください"), ("位", "くらい"), ("所", "ところ"), ("物", "もの"), ("全て", "すべて"), ("貰", "もら"),
    ("殆ど", "ほとんど"), ("既に", "すでに"), ("更に", "さらに"), ("又", "また"), ("其の", "その"), ("此の", "この"),
    ("何時", "いつ"), ("何処", "どこ"), ("為", "ため"), ("故", "ゆえ"), ("筈", "はず"), ("訳", "わけ"), ("達", "たち"),
    ("或いは", "あるいは"), ("併せて", "あわせて"), ("且つ", "かつ"), ("即ち", "すなわち"), ("但し", "ただし"),
    ("於いて", "おいて"), ("於ける", "おける"), ("於て", "おいて"), ("尚", "なお"), ("僅か", "わずか"), ("沢山", "たくさん"),
    ("是非", "ぜひ"), ("暫く", "しばらく"), ("予め", "あらかじめ"), ("概ね", "おおむね"), ("凡そ", "およそ"), ("遂に", "ついに"),
    ("益々", "ますます"), ("寧ろ", "むしろ"), ("若しくは", "もしくは"), ("乃至", "ないし"), ("及び", "および"), ("並びに", "ならびに"),
    ("成る", "なる"), ("成っ", "なっ"), ("成り", "なり"), ("有る", "ある"), ("有り", "あり"), ("無い", "ない"), ("無く", "なく"),
    ("致し", "いたし"), ("致す", "いたす"), ("行なう", "行う"), ("行なっ", "行っ"), ("行ない", "行い"), ("行なわ", "行わ"),
    ("この時", "このとき"), ("その時", "そのとき"), ("あの時", "あのとき"), ("例えば", "たとえば"), ("主に", "おもに"),
    ("易い", "やすい"), ("頃", "ころ"), ("良い", "よい"), ("付け", "つけ"), ("当た", "あた"), ("負わ", "おわ"), ("更なる", "さらなる"),
    ("様々", "さまざま"), ("他", "ほか"), ("共に", "ともに"), ("通り", "とおり"), ("毎", "ごと"), ("例え", "たとえ"),
]


def policy_normalize(text):
    for kanji, kana in KANA_POLICY:
        text = text.replace(kanji, kana)
    return text


def is_hiragana(s):
    return bool(s) and all("ぁ" <= c <= "ゖ" or c == "ー" for c in s)


def is_katakana(s):
    return bool(s) and all("ァ" <= c <= "ヺ" or c == "ー" for c in s)


def load_lm_surfaces():
    import sqlite3
    path = os.path.join(os.path.dirname(__file__), "..", "..", "tmp", "kana_kanji_dictionary.sqlite")
    if not os.path.exists(path):
        return set()
    con = sqlite3.connect(path)
    return {row[0] for row in con.execute("select surface from word_lm_unigram")}


def katakana_run(s):
    best = run = 0
    for c in s:
        run = run + 1 if ("ァ" <= c <= "ヺ" or c == "ー") else 0
        best = max(best, run)
    return best


def is_latin_run(s):
    return bool(s) and all(c.isascii() and (c.isalpha() or c in " '.-&") or "À" <= c <= "ÿ" or c in "Œœ" for c in s)


def latin_katakana_only_difference(a, b):
    """違う部分が カタカナ⇔ラテン文字 だけか(クリュ⇔Cru)"""
    core = diff_core(a, b)
    exp_part, got_part = core.split("→", 1)
    return (is_katakana(exp_part.replace("・", "")) and is_latin_run(got_part)) or (
        is_latin_run(exp_part) and is_katakana(got_part.replace("・", "")))


def diff_core(a, b):
    """共通の前後を落として違う部分だけを 期待→先頭 の形にする"""
    i = 0
    while i < min(len(a), len(b)) and a[i] == b[i]:
        i += 1
    j = 0
    while j < min(len(a), len(b)) - i and a[-1 - j] == b[-1 - j]:
        j += 1
    core_a = a[i:len(a) - j] or "(なし)"
    core_b = b[i:len(b) - j] or "(なし)"
    return f"{core_a}→{core_b}"


def main():
    src, outdir = sys.argv[1:3]
    os.makedirs(outdir, exist_ok=True)
    buckets = {"c_ok": [], "c_policy": [], "c_style": [], "a_register": [], "b_logic": []}
    lm = load_lm_surfaces()
    for line in open(src, encoding="utf-8"):
        cols = line.rstrip("\n").split("\t")
        if len(cols) < 8:
            continue
        reading, expected, sent_no, flags, first, ok, found, top = cols[:8]
        if ok == "ok" or expected.replace("・", "") == first.replace("・", ""):
            buckets["c_ok"].append([reading, expected, first, top])
            continue
        # ラテン文字とカタカナの違いだけなら 2 番目までに入っていれば一致(ユーザ指定 3657。ラテン文字が先、カタカナが 2 番目)
        if expected in top.split("|")[:2] and latin_katakana_only_difference(expected, first):
            buckets["c_ok"].append([reading, expected, first, top])
            continue
        if policy_normalize(expected) == policy_normalize(first) or policy_normalize(expected) == first:
            buckets["c_policy"].append([reading, expected, first, top])
            continue
        core = diff_core(expected, first)
        exp_part, got_part = core.split("→", 1)
        if is_hiragana(exp_part) and not is_hiragana(got_part) and got_part != "(なし)" and first:
            buckets["c_style"].append([reading, expected, first, core, top])
            continue
        proper = "固有名詞" in flags
        in_lm = exp_part in lm or expected in lm
        empty = "候補が空。" if not first else ""
        if proper:
            level, why = "3", empty + "固有名詞を含む"
        elif is_katakana(exp_part):
            if in_lm:
                level, why = "2", empty + "LM 収録のカタカナ語(辞書に無い)"
            else:
                level, why = "3", empty + "カタカナの未収録語(固有名の見込み)"
        elif not in_lm:
            level, why = "2", empty + "LM 未収録の語(稀な語か読みの推定違い)"
        elif len(expected) <= 10:
            level, why = "1", empty + "LM 収録の一般語句"
        else:
            level, why = "2", empty + "長い句(入力の単位として稀)"
        row = [level, why, reading, expected, first, core, flags, top]
        buckets["a_register" if found == "no" else "b_logic"].append(row)
    headers = {
        "c_ok": "読み\t期待\t先頭\t上位6",
        "c_policy": "読み\t期待\t先頭\t上位6",
        "c_style": "読み\t期待\t先頭\t違い(期待→先頭)\t上位6",
        "a_register": "段階\t理由\t読み\t期待\t先頭\t違い(期待→先頭)\t印\t上位6",
        "b_logic": "段階\t理由\t読み\t期待\t先頭\t違い(期待→先頭)\t印\t上位6",
    }
    for name, rows in buckets.items():
        if name.startswith(("a_", "b_")):
            rows.sort(key=lambda r: (r[0], r[3]))
        with open(os.path.join(outdir, name + ".tsv"), "w", encoding="utf-8") as f:
            f.write(headers[name] + "\n")
            for r in rows:
                f.write("\t".join(r) + "\n")
    total = sum(len(v) for v in buckets.values())
    print(f"total={total} " + " ".join(f"{k}={len(v)}" for k, v in buckets.items()))
    for name in ("a_register", "b_logic"):
        counts = {}
        for r in buckets[name]:
            counts[r[0]] = counts.get(r[0], 0) + 1
        print(f"  {name}: " + " ".join(f"段階{k}={v}" for k, v in sorted(counts.items())))


if __name__ == "__main__":
    main()
