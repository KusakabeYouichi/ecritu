#!/usr/bin/env bash
# 変換中核に UI や Apple 専用フレームワークが混ざるのを防ぐ(2858)。
#
# 将来 macOS や Android へ移植する可能性がある。変換の改良はこの先ずっと続くので、
# そのときソースを分岐(フォーク)させず 1 セットで共存させたい。そのためには
# 「変換」「UI」「OS・構成」が独立している必要がある。
#
# 現状(2026-09-10 実測)は既にその形になっている:
#   - 変換中核 19 ファイル(KanaKanji*.swift)の import は Foundation と SQLite3 のみ。
#     SQLite3 は macOS でも Android でも使えるので移植の障害にならない
#   - OS 依存は KanaKanjiStore に集約(UserDefaults の App Group / containerURL / Bundle)。
#     ここが移植時の差し替え点になる
#   - 描画の関心事(字形の有無の判定)は 2858 で UI 層へ移した
#
# この検査は「知らないうちに UI 依存が中核へ漏れる」ことだけを止める。
# UserDefaults や Bundle(Foundation で移植可能)は対象にしない。
set -uo pipefail

ROOT_DIR="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT_DIR"

# 変換中核が import してはいけないもの(UI・Apple 専用の描画/端末フレームワーク)
FORBIDDEN='^import (UIKit|SwiftUI|AppKit|CoreText|CoreGraphics|CoreAnimation|Combine|Contacts|WebKit)$'

fail=0

while IFS= read -r file; do
  [[ -f "$file" ]] || continue

  hits="$(grep -nE "$FORBIDDEN" "$file" || true)"
  [[ -n "$hits" ]] || continue

  while IFS= read -r hit; do
    line_number="${hit%%:*}"
    statement="${hit#*:}"
    echo "$file:$line_number: error: [変換中核] $statement は変換の層に入れられません(UI・OS 層へ置いてください)"
    fail=1
  done <<< "$hits"
done < <(git ls-files -- 'KeyboardExtension/KanaKanji*.swift')

if ((fail)); then
  echo "note: 変換中核は Foundation と SQLite3 だけに保ちます(将来の macOS/Android 移植でソースを分岐させないため)。詳細は docs/architecture-layers.md" >&2
  exit 1
fi

exit 0
