#!/usr/bin/env python3
"""vin.plist の「未分類」節を解体して、各エントリを行き先へ移す。

入力: 計画 TSV(phrase / shortcut / action)
  action = delete            → etc.plist の【教本テキストからの切り出し】節へ
           etc:sudachi-no    → etc.plist の【SudachiDict に収録が無い語】節へ
           etc:sudachi-yes   → etc.plist の【SudachiDict に収録がある語】節へ
           vin:<節見出し>     → vin.plist の該当節へ

etc.plist はビルドに取り込まれない保管ファイルなので、ここへ移した語は変換に影響しない
(refresh_simulator_dictionary_on_build.sh の --input-plist に etc.plist は無い)。
語として成立しない切り出しも、消さずに記録として残す。

各節の中は読み(shortcut)の五十音順を保つ。
"""
import argparse
import csv
import re
import sys
from pathlib import Path

REF = Path(__file__).resolve().parent.parent / "references"
SECTION_RE = re.compile(r"^\t<!-- (■ )?(.*?) -->$")
ENTRY_RE = re.compile(
    r"^\t<dict><key>phrase</key><string>(.*?)</string>"
    r"<key>shortcut</key><string>(.*?)</string></dict>"
)

NOT_A_WORD_HEADING = (
    "■ 教本テキストからの切り出し(語として成立しない断片。"
    "記録として残すだけで、どこにも登録しない)"
)


def entry_line(phrase, shortcut, comment=None):
    line = (
        f"\t<dict><key>phrase</key><string>{phrase}</string>"
        f"<key>shortcut</key><string>{shortcut}</string></dict>"
    )
    if comment:
        line += f"\t<!-- {comment} -->"
    return line


def find_section(lines, heading):
    """見出し行の索引と、その節の終端(次の見出し or </array>)を返す。"""
    for i, line in enumerate(lines):
        m = SECTION_RE.match(line)
        if m and m.group(2) == heading:
            start = i
            break
    else:
        return None, None
    for j in range(start + 1, len(lines)):
        if SECTION_RE.match(lines[j]) or lines[j].strip() == "</array>":
            return start, j
    return start, len(lines)


def insert_sorted(lines, start, end, new_entries):
    """節の中へ読み順で差し込む。既存が非整列でも壊さないよう、各語ごとに
    「自分より後ろの読みが最初に現れる位置」を探して入れる。"""
    for phrase, shortcut, comment in new_entries:
        pos = end
        for k in range(start + 1, end):
            m = ENTRY_RE.match(lines[k])
            if m and m.group(2) > shortcut:
                pos = k
                break
        lines.insert(pos, entry_line(phrase, shortcut, comment))
        end += 1
    return end


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", required=True, help="計画 TSV")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    plan = list(csv.DictReader(open(args.plan, encoding="utf-8"), delimiter="\t"))
    by_action = {}
    for row in plan:
        by_action.setdefault(row["action"], []).append((row["phrase"], row["shortcut"]))

    vin_path = REF / "vin.plist"
    etc_path = REF / "etc.plist"
    vin_lines = vin_path.read_text(encoding="utf-8").splitlines()
    etc_lines = etc_path.read_text(encoding="utf-8").splitlines()

    # --- 1. vin.plist の未分類節からエントリを取り除く ---------------------
    start, end = find_section(vin_lines, "未分類")
    if start is None:
        print("未分類 節が見つかりません", file=sys.stderr)
        return 1
    planned = {(r["phrase"], r["shortcut"]) for r in plan}
    kept, removed = [], 0
    for line in vin_lines[start + 1:end]:
        m = ENTRY_RE.match(line)
        if m and (m.group(1), m.group(2)) in planned:
            removed += 1
            continue
        kept.append(line)
    # 節ごと畳む(残りが空行だけなら見出しも消す)
    if any(ENTRY_RE.match(x) for x in kept):
        vin_lines[start + 1:end] = kept
    else:
        while start > 0 and vin_lines[start - 1].strip() == "":
            start -= 1
        vin_lines[start:end] = []
    print(f"vin.plist 未分類から {removed} 件を除去")

    # --- 2. vin.plist の各節へ移す ----------------------------------------
    for action, items in sorted(by_action.items()):
        if not action.startswith("vin:"):
            continue
        heading = action.split(":", 1)[1]
        s, e = find_section(vin_lines, heading)
        if s is None:
            print(f"  !! 節が見つかりません: {heading}", file=sys.stderr)
            return 1
        insert_sorted(vin_lines, s, e, [(p, sc, None) for p, sc in items])
        print(f"  vin.plist [{heading}] へ {len(items)} 件")

    # --- 3. etc.plist へ移す ----------------------------------------------
    mapping = {
        "etc:sudachi-yes": "SudachiDict に収録がある語(読み+表記の組が一致。生CSV core/small で判定)",
        "etc:sudachi-no": "SudachiDict に収録が無い語(この組では引けない。追加語彙の候補)",
    }
    for action, heading in mapping.items():
        items = by_action.get(action)
        if not items:
            continue
        s, e = find_section(etc_lines, heading)
        if s is None:
            print(f"  !! 節が見つかりません: {heading}", file=sys.stderr)
            return 1
        insert_sorted(
            etc_lines, s, e, [(p, sc, "元: vin.plist 未分類") for p, sc in items]
        )
        print(f"  etc.plist [{heading[:20]}…] へ {len(items)} 件")

    # --- 4. 語として成立しない断片は新しい節へ ------------------------------
    fragments = by_action.get("delete", [])
    if fragments:
        close = next(i for i, x in enumerate(etc_lines) if x.strip() == "</array>")
        block = ["", f"\t<!-- {NOT_A_WORD_HEADING} -->"]
        for phrase, shortcut in sorted(fragments, key=lambda x: x[1]):
            block.append(entry_line(phrase, shortcut))
        etc_lines[close:close] = block
        print(f"  etc.plist [教本テキストからの切り出し] へ {len(fragments)} 件(新設)")

    if args.dry_run:
        print("(dry-run のため書き込みません)")
        return 0

    vin_path.write_text("\n".join(vin_lines) + "\n", encoding="utf-8")
    etc_path.write_text("\n".join(etc_lines) + "\n", encoding="utf-8")
    print("書き込み完了")
    return 0


if __name__ == "__main__":
    sys.exit(main())
