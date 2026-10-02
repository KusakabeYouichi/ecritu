#!/usr/bin/env bash
# Unihan データベース(Unicode Character Database)を tmp/unihan_raw へ取得する。
# 漢字1文字ピッカーの部首・画数(kRSUnicode)、JIS区点(kJis0)の元データ。
# sudachi 生データと同じく非コミット(tmp/ 配下)。
#
# 版は固定し(3315)、展開した各ファイルを tools/dictionary_sources.sha256 と突き合わせてから tmp/ へ置く。
# 以前は Public/UCD/latest を取り、照合もしていなかった(セキュリティー検査 2026-10-02)。
# 版を上げるときは UNIHAN_VERSION を変え、--print-hashes の実測で manifest を同じコミットで更新する。
#   使い方: bash tools/fetch_unihan_raw.sh [--force] [--print-hashes] [--dest <path>]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEST_DIR="$ROOT_DIR/tmp/unihan_raw"
UNIHAN_VERSION="17.0.0"
URL="https://www.unicode.org/Public/${UNIHAN_VERSION}/ucd/Unihan.zip"
MANIFEST_PATH="$ROOT_DIR/tools/dictionary_sources.sha256"
FORCE=false
PRINT_HASHES=false

while (($# > 0)); do
  case "$1" in
    --force) FORCE=true; shift ;;
    --print-hashes) PRINT_HASHES=true; shift ;;
    --dest)
      (($# >= 2)) || { echo "[unihan] Missing value for --dest" >&2; exit 1; }
      DEST_DIR="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "[unihan] Unknown option: $1" >&2; exit 1 ;;
  esac
done

mkdir -p "$DEST_DIR"

if [[ -f "$DEST_DIR/Unihan_IRGSources.txt" && "$FORCE" != "true" ]]; then
  echo "[unihan] 既に取得済み: $DEST_DIR (再取得は --force)"
  exit 0
fi

[[ -f "$MANIFEST_PATH" ]] || { echo "[unihan][error] manifest が見つかりません: $MANIFEST_PATH" >&2; exit 1; }

tmp_dir="$(mktemp -d)"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT

echo "[unihan] downloading $URL"
curl -fsSL --max-time 300 -o "$tmp_dir/Unihan.zip" "$URL"
unzip -oq "$tmp_dir/Unihan.zip" -d "$tmp_dir/extract"

# 照合: 展開した全 .txt を manifest と突き合わせ、1 件でも合わなければ DEST_DIR には置かない
mismatches=()
actual_lines=()
while IFS= read -r txt; do
  rel_path="unihan_raw/$(basename "$txt")"
  actual_hash="$(shasum -a 256 "$txt" | cut -d' ' -f1)"
  actual_lines+=("$actual_hash  $rel_path")
  expected_hash="$(grep -E "^[0-9a-f]{64}  ${rel_path}$" "$MANIFEST_PATH" | cut -d' ' -f1 || true)"
  if [[ -z "$expected_hash" ]]; then
    mismatches+=("$rel_path: manifest に無い(実測 $actual_hash)")
  elif [[ "$expected_hash" != "$actual_hash" ]]; then
    mismatches+=("$rel_path: 期待 $expected_hash / 実測 $actual_hash")
  fi
done < <(find "$tmp_dir/extract" -type f -name 'Unihan_*.txt' | sort)

if [[ "$PRINT_HASHES" == "true" ]]; then
  echo "[unihan] 実測ハッシュ(manifest 形式):"
  printf '%s\n' "${actual_lines[@]}"
fi

if ((${#actual_lines[@]} == 0)); then
  echo "[unihan][error] 展開物に Unihan_*.txt がありません" >&2
  exit 1
fi
if ((${#mismatches[@]} > 0)); then
  echo "[unihan][error] 取得したファイルが tools/dictionary_sources.sha256 と一致しません。tmp/ には置きません。" >&2
  printf '  %s\n' "${mismatches[@]}" >&2
  echo "[unihan][error] 版を上げる意図なら UNIHAN_VERSION を変え、--print-hashes の実測で manifest を同じコミットで更新してください(version=${UNIHAN_VERSION})" >&2
  exit 1
fi
echo "[unihan] manifest と一致(${#actual_lines[@]} ファイル、version=${UNIHAN_VERSION})"

find "$tmp_dir/extract" -type f -name 'Unihan_*.txt' -exec mv -f {} "$DEST_DIR/" \;
echo "[unihan] done:"
ls -1 "$DEST_DIR"
