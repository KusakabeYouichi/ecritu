#!/bin/bash
# 開発用シミュレーターの UDID を名前から引く(3684)。
# UDID はシミュレーターを作り直すたび(Xcode の更新・ランタイムの入れ替え)に変わるので、設定ファイルに固定しない。
# 名前は ECRITU_SIM_NAME(既定 iPhone 17 Pro Max。2026-10-16 以降はこれだけを使う)。同名が複数あれば最初の 1 台。
# 使い方: SIM_UDID="$(bash tools/simulator_udid.sh)" || exit 1
set -u
NAME="${ECRITU_SIM_NAME:-iPhone 17 Pro Max}"
UDID=$(xcrun simctl list devices available | sed -nE "s/^[[:space:]]*${NAME} \(([A-F0-9-]+)\) \((Booted|Shutdown)\).*/\1/p" | head -n 1)
if [[ -z "$UDID" ]]; then
  echo "シミュレーター「${NAME}」が見つかりません(xcrun simctl list devices available で名前を確認)" >&2
  exit 1
fi
echo "$UDID"
