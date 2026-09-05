#!/usr/bin/env python3
"""新規 Swift ファイルを écritu.xcodeproj/project.pbxproj に登録する(手動編集の代行)。

pbxproj は手で管理している(xcodegen は運用しない。project.yml 冒頭の注意を参照)。新ファイルは
PBXFileReference + グループ掲載 + ターゲットごとの PBXBuildFile/Sources 掲載が要る。既存の同グループ・
同ターゲットのファイルを「手本」に、同じ場所へ 1 行ずつ差し込む。

使い方:
  python3 tools/register_pbxproj_source.py <新ファイル(リポジトリ相対)> --like <手本ファイル(リポジトリ相対)>

例: KeyboardExtension/SortedTSVBlob.swift を KanaKanjiStore+LatinSuggestions.swift と同じターゲット群(拡張+テスト)へ:
  python3 tools/register_pbxproj_source.py KeyboardExtension/SortedTSVBlob.swift \
      --like KeyboardExtension/KanaKanjiStore+LatinSuggestions.swift

手本がテストターゲットにも入っている場合は project.yml のテスト sources 一覧にも追記する(写しの同期)。
"""
import argparse
import hashlib
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PBXPROJ = os.path.join(ROOT, "écritu.xcodeproj", "project.pbxproj")
PROJECT_YML = os.path.join(ROOT, "project.yml")


def make_id(seed: str) -> str:
    return hashlib.sha1(seed.encode("utf-8")).hexdigest()[:24].upper()


def quoted(path_component: str) -> str:
    # pbxproj は英数字と . _ / 以外を含む値を引用符で囲む
    return path_component if re.fullmatch(r"[A-Za-z0-9_./]+", path_component) else f'"{path_component}"'


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("new_path")
    parser.add_argument("--like", required=True, dest="like_path")
    args = parser.parse_args()

    new_name = os.path.basename(args.new_path)
    like_name = os.path.basename(args.like_path)
    if os.path.dirname(args.new_path) != os.path.dirname(args.like_path):
        print("手本と同じディレクトリのファイルだけ扱う(グループが同じである前提)", file=sys.stderr)
        return 2
    if not os.path.exists(os.path.join(ROOT, args.new_path)):
        print(f"ファイルが無い: {args.new_path}", file=sys.stderr)
        return 2

    with open(PBXPROJ, encoding="utf-8") as f:
        text = f.read()
    if f"/* {new_name} */" in text:
        print(f"既に登録済み: {new_name}")
        return 0

    like_quoted = re.escape(like_name)
    ref_match = re.search(
        rf"^\t\t([0-9A-F]{{24}}) /\* {like_quoted} \*/ = \{{isa = PBXFileReference;.*\n", text, re.M
    )
    if not ref_match:
        print(f"手本の PBXFileReference が見つからない: {like_name}", file=sys.stderr)
        return 2
    like_ref_id = ref_match.group(1)
    new_ref_id = make_id(f"ref:{args.new_path}")

    build_matches = list(
        re.finditer(
            rf"^\t\t([0-9A-F]{{24}}) /\* {like_quoted} in Sources \*/ = \{{isa = PBXBuildFile; fileRef = {like_ref_id} /\* {like_quoted} \*/; \}};\n",
            text,
            re.M,
        )
    )
    if not build_matches:
        print(f"手本の PBXBuildFile が見つからない: {like_name}", file=sys.stderr)
        return 2

    # 1) PBXBuildFile(ターゲットごと)
    insertions = []
    new_build_ids = []
    for index, m in enumerate(build_matches):
        new_build_id = make_id(f"build:{args.new_path}:{index}")
        new_build_ids.append((m.group(1), new_build_id))
        line = (
            f"\t\t{new_build_id} /* {new_name} in Sources */ = {{isa = PBXBuildFile; "
            f"fileRef = {new_ref_id} /* {new_name} */; }};\n"
        )
        insertions.append((m.end(), line))

    # 2) PBXFileReference
    ref_line = (
        f"\t\t{new_ref_id} /* {new_name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
        f"path = {quoted(new_name)}; sourceTree = \"<group>\"; }};\n"
    )
    insertions.append((ref_match.end(), ref_line))

    # 3) グループ掲載(手本の参照行の直後)
    group_match = re.search(rf"^\t\t\t\t{like_ref_id} /\* {like_quoted} \*/,\n", text, re.M)
    if not group_match:
        print("手本のグループ掲載行が見つからない", file=sys.stderr)
        return 2
    insertions.append((group_match.end(), f"\t\t\t\t{new_ref_id} /* {new_name} */,\n"))

    # 4) Sources ビルドフェーズ掲載(ターゲットごと、手本の直後)
    for like_build_id, new_build_id in new_build_ids:
        src_match = re.search(rf"^\t\t\t\t{like_build_id} /\* {like_quoted} in Sources \*/,\n", text, re.M)
        if not src_match:
            print(f"手本の Sources 掲載行が見つからない: {like_build_id}", file=sys.stderr)
            return 2
        insertions.append((src_match.end(), f"\t\t\t\t{new_build_id} /* {new_name} in Sources */,\n"))

    for offset, line in sorted(insertions, key=lambda item: item[0], reverse=True):
        text = text[:offset] + line + text[offset:]
    with open(PBXPROJ, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"pbxproj: {new_name} を {len(new_build_ids)} ターゲットへ登録")

    # project.yml(写し): 手本がテスト sources に個別掲載されていれば同じ並びに追記
    with open(PROJECT_YML, encoding="utf-8") as f:
        yml = f.read()
    like_yml_line = f"      - path: {args.like_path}\n"
    if like_yml_line in yml and f"      - path: {args.new_path}\n" not in yml:
        yml = yml.replace(like_yml_line, like_yml_line + f"      - path: {args.new_path}\n", 1)
        with open(PROJECT_YML, "w", encoding="utf-8") as f:
            f.write(yml)
        print("project.yml: テスト sources に追記")
    return 0


if __name__ == "__main__":
    sys.exit(main())
