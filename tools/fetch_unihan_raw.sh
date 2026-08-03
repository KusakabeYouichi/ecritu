#!/usr/bin/env bash
# Unihan データベース(Unicode Character Database)を tmp/unihan_raw へ取得する。
# 漢字1文字ピッカーの部首・画数(kRSUnicode)、JIS区点(kJis0)の元データ。
# sudachi 生データと同じく非コミット(tmp/ 配下)。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEST_DIR="$ROOT_DIR/tmp/unihan_raw"
URL="https://www.unicode.org/Public/UCD/latest/ucd/Unihan.zip"

mkdir -p "$DEST_DIR"

if [[ -f "$DEST_DIR/Unihan_IRGSources.txt" && "${1:-}" != "--force" ]]; then
  echo "[unihan] 既に取得済み: $DEST_DIR (再取得は --force)"
  exit 0
fi

echo "[unihan] downloading $URL"
curl -fsSL --max-time 300 -o "$DEST_DIR/Unihan.zip" "$URL"
unzip -oq "$DEST_DIR/Unihan.zip" -d "$DEST_DIR"
rm -f "$DEST_DIR/Unihan.zip"
echo "[unihan] done:"
ls -1 "$DEST_DIR"
