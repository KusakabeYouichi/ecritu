#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEST_DIR="$ROOT_DIR/tmp/sudachi_raw"
SUDACHI_REF="develop"
FORCE_OVERWRITE=false
INCLUDE_FULL=false

usage() {
  cat <<'USAGE'
Usage: bash tools/fetch_sudachi_raw.sh [options]

Downloads SudachiDict source CSV files and places *_lex.csv under tmp/sudachi_raw.

Options:
  --dest <path>         Output directory (default: tmp/sudachi_raw)
  --ref <git-ref>       SudachiDict ref to download (default: develop)
  --force               Replace existing *_lex.csv files in destination
  --include-full        Also import sudachidict_full data when available
  -h, --help            Show this help
USAGE
}

while (($# > 0)); do
  case "$1" in
    --dest)
      if (($# < 2)); then
        echo "[dict] Missing value for --dest" >&2
        exit 1
      fi
      DEST_DIR="$2"
      shift 2
      ;;
    --ref)
      if (($# < 2)); then
        echo "[dict] Missing value for --ref" >&2
        exit 1
      fi
      SUDACHI_REF="$2"
      shift 2
      ;;
    --force)
      FORCE_OVERWRITE=true
      shift
      ;;
    --include-full)
      INCLUDE_FULL=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[dict] Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! command -v curl >/dev/null 2>&1; then
  echo "[dict] curl is required but was not found in PATH" >&2
  exit 1
fi

if ! command -v tar >/dev/null 2>&1; then
  echo "[dict] tar is required but was not found in PATH" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"

existing_count="$(find "$DEST_DIR" -type f -name '*_lex.csv' | wc -l | tr -d ' ')"
if [[ "$existing_count" != "0" && "$FORCE_OVERWRITE" != "true" ]]; then
  echo "[dict] Destination already has $existing_count *_lex.csv files: $DEST_DIR"
  echo "[dict] Re-run with --force if you want to replace them."
  exit 0
fi

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

archive_path="$tmp_dir/sudachidict.tar.gz"
archive_url="https://github.com/WorksApplications/SudachiDict/archive/refs/heads/${SUDACHI_REF}.tar.gz"

echo "[dict] Downloading SudachiDict (${SUDACHI_REF})..."
curl -fL "$archive_url" -o "$archive_path"

echo "[dict] Extracting archive..."
tar -xzf "$archive_path" -C "$tmp_dir"

source_root="$(find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d -name 'SudachiDict-*' | head -n 1)"
if [[ -z "$source_root" ]]; then
  echo "[dict] Failed to locate extracted SudachiDict directory" >&2
  exit 1
fi

if [[ "$FORCE_OVERWRITE" == "true" ]]; then
  find "$DEST_DIR" -type f -name '*_lex.csv' -delete
fi

modules=("sudachidict_core" "sudachidict_small")
if [[ "$INCLUDE_FULL" == "true" ]]; then
  modules+=("sudachidict_full")
fi

copied_count=0

for module in "${modules[@]}"; do
  module_text_dir="$source_root/$module/src/main/text"

  if [[ ! -d "$module_text_dir" ]]; then
    echo "[dict] Skip missing module directory: $module_text_dir"
    continue
  fi

  while IFS= read -r csv_file; do
    file_name="$(basename "$csv_file")"
    module_dest_dir="$DEST_DIR/$module"
    mkdir -p "$module_dest_dir"
    cp -f "$csv_file" "$module_dest_dir/$file_name"
    copied_count=$((copied_count + 1))
  done < <(find "$module_text_dir" -type f -name '*_lex.csv' | sort)
done

if ((copied_count == 0)); then
  echo "[dict] No *_lex.csv files were copied. Check SudachiDict ref/modules." >&2
  exit 1
fi

final_count="$(find "$DEST_DIR" -type f -name '*_lex.csv' | wc -l | tr -d ' ')"

echo "[dict] Copied $copied_count files into: $DEST_DIR"
echo "[dict] Destination now has $final_count *_lex.csv files."
echo "[dict] Next step: build in Xcode or run bash tools/refresh_simulator_dictionary_on_build.sh"
