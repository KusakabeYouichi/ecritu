#!/usr/bin/env python3
"""補助語彙(ryukyu.plist)の語のうち、Sudachi が地名とするものを 地名の補い の JSON にする(3789、ユーザ指定)。

地名の表(place_names)は LM に収録された語だけに絞って作るので、琉球の地名の多く(安謝/泡瀬/伊祖 など)が落ちていた。
補助語彙に登録済みで Sudachi の品詞が 地名 の語は、LM に無くても地名として入れる。
出力は reading -> candidate -> "登録"(references/place_names_add.json と同じ形)。
"""
import json
import re
import sys
from pathlib import Path

ENTRY_PATTERN = re.compile(
    r"<dict><key>phrase</key><string>([^<]+)</string><key>shortcut</key><string>([^<]+)</string></dict>"
)


def main() -> int:
    if len(sys.argv) < 4:
        print("usage: build_supplement_place_names.py <sudachi place names json> <output json> <plist>...", file=sys.stderr)
        return 2
    places = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    result = {}
    for plist_path in sys.argv[3:]:
        text = Path(plist_path).read_text(encoding="utf-8")
        # コメントアウトした行は対象外
        text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
        for phrase, reading in ENTRY_PATTERN.findall(text):
            if phrase in places.get(reading, {}):
                result.setdefault(reading, {})[phrase] = "登録"
    Path(sys.argv[2]).write_text(
        json.dumps(result, ensure_ascii=False, indent=0, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(f"supplement place names: {sum(len(v) for v in result.values())}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
