# -*- coding: utf-8 -*-
"""漢字1文字ピッカー用の索引を Unihan から生成する。

出力: KeyboardExtension/KanjiRadicalIndex.txt
  1行 = 1字: radical(3桁) TAB 部首内画数(2桁) TAB 字 TAB 区点 TAB 読み
  並び順 = 部首番号 → 部首内画数 → コードポイント(= 康熙字典順)
  行頭が "NNN\t" で始まるバイト順ソートなので、実行時は mmap したまま
  バイト単位のバイナリサーチで部首ブロックを切り出せる(常駐フットプリント ≒ 0)。

対象は CJK 統合漢字 U+4E00–9FFF(20,992字)。表示は全字行い、ヒラギノ明朝に
グリフが無い字は実行時にフォント判定して色を変える(データに印は持たせない)。
"""
import pathlib
import sys

RAW = pathlib.Path("tmp/unihan_raw")
OUT = pathlib.Path("KeyboardExtension/KanjiRadicalIndex.txt")
URO = range(0x4E00, 0xA000)
MAX_ON = 3
MAX_KUN = 3


def read_field(filename, field):
    values = {}
    path = RAW / filename
    if not path.exists():
        sys.exit(f"missing {path} — bash tools/fetch_unihan_raw.sh を先に実行してください")
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            if line.startswith("#") or "\t" not in line:
                continue
            code, name, value = line.rstrip("\n").split("\t", 2)
            if name != field:
                continue
            cp = int(code[2:], 16)
            if cp in URO:
                values[cp] = value
    return values


def is_katakana(text):
    return all("ァ" <= ch <= "ヶ" or ch == "ー" for ch in text)


def main():
    rs = read_field("Unihan_IRGSources.txt", "kRSUnicode")
    jis = read_field("Unihan_OtherMappings.txt", "kJis0")
    readings = read_field("Unihan_Readings.txt", "kJapanese")

    rows = []
    skipped = 0
    for cp, raw in rs.items():
        # 複数指定は先頭を採用。85'.11 の ' は簡体側部首の印なので落とす。
        primary = raw.split()[0].replace("'", "").replace('"', "")
        radical_text, _, stroke_text = primary.partition(".")
        try:
            radical = int(radical_text)
            strokes = int(stroke_text)
        except ValueError:
            skipped += 1
            continue
        if not 1 <= radical <= 214:
            skipped += 1
            continue
        strokes = max(0, min(strokes, 99))

        kuten = jis.get(cp, "")
        if kuten:
            kuten = f"{int(kuten[:2])}-{int(kuten[2:])}"
        else:
            kuten = "—"

        forms = readings.get(cp, "").split()
        on = [f for f in forms if is_katakana(f)][:MAX_ON]
        kun = [f for f in forms if not is_katakana(f)][:MAX_KUN]
        reading_text = " ".join(on + kun) or "—"

        rows.append((radical, strokes, cp, kuten, reading_text))

    rows.sort()
    lines = [
        f"{radical:03d}\t{strokes:02d}\t{chr(cp)}\t{kuten}\t{reading}"
        for radical, strokes, cp, kuten, reading in rows
    ]
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")

    total = len(rows)
    with_kuten = sum(1 for r in rows if r[3] != "—")
    with_reading = sum(1 for r in rows if r[4] != "—")
    print(f"wrote: {OUT}")
    print(f"  字数: {total} (URO {len(URO)} 中) / kRSUnicode 無しで除外: {len(URO) - total}")
    print(f"  区点あり: {with_kuten} / 読みあり: {with_reading}")
    print(f"  サイズ: {OUT.stat().st_size / 1024:.0f}KB")
    if skipped:
        print(f"  部首番号が解釈できず除外: {skipped}")


if __name__ == "__main__":
    main()
