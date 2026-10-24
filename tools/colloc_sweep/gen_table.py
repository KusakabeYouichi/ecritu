#!/usr/bin/env python3
"""確認表の判定(decisions.json)から 目的語+助詞+同音動詞 の連語表(Swift)を生成する。

使い方: .venv/bin/python -I tools/colloc_sweep/gen_table.py references/colloc_sweep/<id> KeyboardExtension/KanaKanjiConverter+ObjectVerbCollocations.swift

- mark が fix の組だけを採る(ok/未入力は載せない)
- 備考で順位を指定された組は OVERRIDES で扱う(備考は期待表記より優先)
  skip: 今の並びのまま(表に載せない) / heads: 優先する表記の頭を差し替える / kana: かなを優先(漢字は 2 番め以降)
- 動詞の読みの接頭は活用型から作る(五段=語幹+各段と音便、一段=語幹、サ変=語幹+し/す/さ/せ)
"""
import json
import os
import sys
import collections

from sudachipy import Dictionary, SplitMode

# 備考による上書き(key = 名詞+助詞+動詞)。3774 の備考 60 件の写し
OVERRIDES_3774 = {}
for key in ["立場を取る", "行動を取る", "形を取る", "構造を取る", "責任を取る", "態度を取る", "値を取る", "姿勢を取る",
            "形態を取る", "状態を取る", "進路を取る", "体制を取る", "名前を取る", "異名を取る", "距離を取る", "同期を取る",
            "遅れを取る", "対策が取る", "対応を取る", "酸化数を取る", "相手に取る", "接続を取る", "配置を取る", "統計を取る",
            "体制が取る", "手段を取る", "確認を取る", "軌道を取る", "睡眠を取る", "休息を取る"]:
    OVERRIDES_3774[key] = {"skip": "1位は[とる]、2位は[取る](今の並び)"}
for key in ["年に渡る", "長年に渡る", "長期に渡る", "年間に渡る", "手に渡る", "以上に渡る", "度に渡る", "長期間に渡る",
            "時間に渡る", "生涯に渡る", "日間に渡る", "多岐に渡る", "世紀に渡る", "広範囲に渡る", "全編に渡る", "複数回に渡る",
            "か月に渡る", "範囲に渡る", "終日に渡る", "全域に亘る", "将来に渡る"]:
    OVERRIDES_3774[key] = {"skip": "1位[わたる]、2位[渡る]、3位[亘る](今の並び)"}
OVERRIDES_3774["金を賭ける"] = {"skip": "1位は[かける/かけた]、2位を[賭ける/賭けた]"}
OVERRIDES_3774["名を挙げる"] = {"heads": ["上げ"]}  # 名[を]だったら[上][挙]の順(挙げ は対抗として 2 番め以降)
OVERRIDES_3774["名前を挙げる"] = {"heads": ["上げ"]}  # 名前が/名前を も 名が/名を と同じ指定(3776)
# 1 位はかな、2 位は漢字(3776)。かなの頭を優先し、漢字は対抗として 2 番め以降に残す
for key in ["電話を掛ける", "声を掛ける", "時間を掛ける", "時間が掛かる", "気が付く", "気に掛ける"]:
    OVERRIDES_3774[key] = {"kana": True}

GODAN_ROWS = {
    "う": "わいうえお", "く": "かきくけこ", "ぐ": "がぎぐげご", "す": "さしすせそ", "つ": "たちつてと",
    "ぬ": "なにぬねの", "ぶ": "ばびぶべぼ", "む": "まみむめも", "る": "らりるれろ",
}
GODAN_ONBIN = {"う": "っ", "つ": "っ", "る": "っ", "く": "い", "ぐ": "い", "ぬ": "ん", "ぶ": "ん", "む": "ん", "す": "し"}
# 接頭の直後に続いてよい文字。複合動詞(創り+上げる/取り+入れる)や別の動詞(終える の おえ)に当たらないよう、
# 未然・連用・音便・一段の語幹は直後の助動詞の頭まで含めて照合する。終止形(う段)は直後を問わない。e 段(仮定・命令・可能)は採らない
# 連用の や はやすい(遭いやすい)、一段の ら は られる(変えられます)。3777
MIZEN_FOLLOWERS = "なせれずぬ"
RENYOU_FOLLOWERS = "まただなそにつや"
ONBIN_FOLLOWERS = "たてだでちじ"
ICHIDAN_FOLLOWERS = "るれろよたてなまずさそちやら"
# 名詞の表記の直後の動詞の頭への加点。判定由来の組は 0(加点は接頭の絞り込みを素通りし、下に書くした/役目を負えた が出た。3777)。
# manual.json は group ごとに bonus で指定(古い multiClauseAcrossNoCollocationBonuses の値を引き継ぐ。標準 3000)
DECISION_NOUN_BONUS = 0
DEFAULT_NOUN_BONUS = 3000
# サ変は し/す/さ/せ の後ろの 1 字まで含める(かんし だけだと 関した(かんした)が対抗の区間から外れる)
SURU_FORMS = ["した", "して", "しな", "しま", "しよ", "しろ", "しそ", "しち", "する", "すれ", "すべ", "させ", "され", "さな", "せず", "せよ"]

tok = Dictionary().create()


def conj_type(dform):
    ms = tok.tokenize(dform, SplitMode.C)
    return ms[0].part_of_speech()[4] if len(ms) == 1 else ""


def verb_prefixes(vr, ctype):
    if ctype.startswith("五段") or ctype.startswith("文語四段"):
        stem, last = vr[:-1], vr[-1]
        if last not in GODAN_ROWS:
            return None
        a, i, u, e, o = GODAN_ROWS[last]
        out = [stem + a + f for f in MIZEN_FOLLOWERS]
        out += [stem + i + f for f in RENYOU_FOLLOWERS]
        out.append(stem + u)
        out.append(stem + o + "う")
        onbin = "っ" if vr.endswith("いく") or vr.endswith("ゆく") else GODAN_ONBIN[last]
        if onbin != i:
            out += [stem + onbin + f for f in ONBIN_FOLLOWERS]
        else:
            out += [stem + i + f for f in ONBIN_FOLLOWERS if f not in RENYOU_FOLLOWERS]
        return out
    if ctype.startswith("上一段") or ctype.startswith("下一段"):
        stem = vr[:-1]
        return [stem + f for f in ICHIDAN_FOLLOWERS]
    if ctype.startswith("サ行変格") and vr.endswith("する"):
        stem = vr[:-2]
        return [stem + k for k in SURU_FORMS]
    return None


def noun_reading(noun):
    """名詞の読み(ひらがな)。複数の読みがある語は manual.json の readings で指定する"""
    reading = "".join(m.reading_form() for m in tok.tokenize(noun, SplitMode.C))
    return "".join(chr(ord(c) - 0x60) if "ァ" <= c <= "ヶ" else c for c in reading)


def head_of(verb, ctype):
    """活用で変わらない表記の頭(手がける→手がけ、取る→取、冠する→冠)"""
    if ctype.startswith("サ行変格") and verb.endswith("する"):
        return verb[:-2]
    return verb[:-1]


def swift_str_list(xs):
    return "[" + ", ".join('"' + x + '"' for x in xs) + "]"


def main():
    src, out_path = sys.argv[1], sys.argv[2]
    items = json.load(open(os.path.join(src, "items.json"), encoding="utf-8"))
    dec = {d["key"]: d for d in json.load(open(os.path.join(src, "decisions.json"), encoding="utf-8"))}
    table = collections.OrderedDict()   # noun_r -> [[particle, prefixes, heads, nouns, bonus, comment]]
    skipped = []
    decided = {}   # (名詞の読み, 助詞, 動詞の読み) -> 表の行
    adjacent = collections.OrderedDict()   # (名詞の表記, 動詞の頭) -> (加点, 注記)。助詞なしの組
    for it in sorted(items, key=lambda x: (x["noun_r"], x["p"], x["vr"])):
        key = it["noun"] + it["p"] + it["verb"]
        d = dec.get(key, {})
        if d.get("mark") != "fix":
            skipped.append((key, "mark=" + (d.get("mark") or "未入力")))
            continue
        ov = OVERRIDES_3774.get(key, {})
        if "skip" in ov:
            skipped.append((key, ov["skip"]))
            continue
        ctype = conj_type(it["verb"])
        prefixes = verb_prefixes(it["vr"], ctype)
        if not prefixes:
            skipped.append((key, "活用型を扱えない: " + ctype))
            continue
        heads = ov.get("heads") or [head_of(it["vr"] if ov.get("kana") else it["verb"], ctype)]
        if not heads[0]:
            skipped.append((key, "表記の頭が空"))
            continue
        # スキャンは名詞の別の読み(帝=てい/みかど、名=な/めい)の組も変換している。辞書形の読みから名詞の読みを取り出して全部載せる
        noun_readings = [it["noun_r"]]
        for f in it["forms"]:
            tail = it["p"] + it["vr"]
            if f["form"] == "辞書形" and f["reading"].endswith(tail):
                nr = f["reading"][:-len(tail)]
                if nr and nr not in noun_readings:
                    noun_readings.append(nr)
        for nr in noun_readings:
            row = [it["p"], prefixes, heads, [it["noun"]], DECISION_NOUN_BONUS, key]
            table.setdefault(nr, []).append(row)
            decided[(nr, it["p"], it["vr"])] = row
    # 手で足す組(references/colloc_sweep/manual.json)。判定で載せた組(同じ名詞の読み・助詞・動詞の読み)と備考で外した組が優先
    manual_path = os.path.join(os.path.dirname(os.path.normpath(src)), "manual.json")
    manual = json.load(open(manual_path, encoding="utf-8")) if os.path.exists(manual_path) else {"readings": {}, "groups": []}
    manual_count = 0
    for g in manual["groups"]:
        for noun in g["nouns"]:
            for p in g["particles"]:
                for verb, vr in g["verbs"]:
                    key = noun + p + verb
                    if "skip" in OVERRIDES_3774.get(key, {}):
                        continue
                    ctype = conj_type(verb)
                    prefixes = verb_prefixes(vr, ctype)
                    if not prefixes:
                        skipped.append((key + "(手)", "活用型を扱えない: " + ctype))
                        continue
                    heads = [head_of(verb, ctype)]
                    bonus = g.get("bonus", DEFAULT_NOUN_BONUS)
                    # 助詞なし(particles に "")は 名詞の表記の直後の動詞の頭への加点だけ(靴下履いて/時間計って。3779)
                    if p == "":
                        if (noun, heads[0]) not in adjacent:
                            adjacent[(noun, heads[0])] = (bonus, key + "(手)")
                        continue
                    for nr in manual["readings"].get(noun) or [noun_reading(noun)]:
                        row = decided.get((nr, p, vr))
                        if row:
                            # 同じ読みの組が既にあれば、表記の頭は先の行のまま、名詞の表記と加点だけ合わせる(くぎ/釘、めがね/眼鏡)
                            if noun not in row[3]:
                                row[3].append(noun)
                            row[4] = max(row[4], bonus)
                            continue
                        row = [p, prefixes, heads, [noun], bonus, key + "(手)"]
                        decided[(nr, p, vr)] = row
                        table.setdefault(nr, []).append(row)
                        manual_count += 1
    lines = [
        "// このファイルは tools/colloc_sweep/gen_table.py が生成する。手で直さず、判定(references/colloc_sweep/<id>/decisions.json)",
        "// か生成スクリプトの上書き表、手で足す組(references/colloc_sweep/manual.json、行末の注記が (手))を直して再生成すること。",
        "",
        "extension KanaKanjiConverter {",
        "    // 目的語で決まる動詞の表 - (名詞+助詞の後ろの同音動詞の字を決める。味を変える/靴を履く。判定と manual.json から生成)",
        "    // 目的語+助詞+同音動詞の連語(3774、コーパス由来の 1058 組をユーザ判定)。名詞の読みの区間の直後が",
        "    // 助詞 particle、その直後が動詞の読みの接頭 prefixes のとき、その位置から始まる動詞ノードのうち表記が",
        "    // heads で始まり残りがかなだけのものを連語選好にする(席を立つ/消息を絶つ と同じ仕組み)。",
        "    // 名詞の表記 nouns の直後(助詞を挟む)の heads には nounBonus を加点し、名詞の取り違え(端を渡る/日が通る)も防ぐ",
        "    // (multiClauseAcrossNoCollocationBonusesByPrevPrev に合流する。3777)",
        "    static let multiClauseObjectVerbCollocations:",
        "        [String: [(particle: Character, prefixes: [String], heads: [String], nouns: [String], nounBonus: Int)]] = [",
    ]
    for nr, entries in sorted(table.items()):
        lines.append(f'        "{nr}": [')
        for p, prefixes, heads, nouns, bonus, key in entries:
            lines.append(f'            ("{p}", {swift_str_list(prefixes)}, {swift_str_list(heads)}, {swift_str_list(nouns)}, {bonus}),  // {key}')
        lines.append("        ],")
    lines.append("    ]")
    lines += [
        "",
        "    // 目的語で決まる動詞の表の 助詞なしの組 - (名詞の表記の直後の動詞の頭へ加点。時間計って/靴下履いて/この道通ってて。",
        "    // multiClauseBigramPrefixPairBonusesByPrev に合流する。3779)",
        "    static let multiClauseObjectVerbAdjacentBonuses: [(noun: String, head: String, bonus: Int)] = [",
    ]
    for (noun, head), (bonus, key) in adjacent.items():
        lines.append(f'        ("{noun}", "{head}", {bonus}),  // {key}')
    lines.append("    ]")
    lines.append("}")
    lines.append("")
    open(out_path, "w", encoding="utf-8").write("\n".join(lines))
    n = sum(len(v) for v in table.values())
    print(f"entries {n} (manual {manual_count}) nouns {len(table)} skipped {len(skipped)}", file=sys.stderr)
    for k, why in skipped:
        print("  skip", k, why, file=sys.stderr)


if __name__ == "__main__":
    main()
