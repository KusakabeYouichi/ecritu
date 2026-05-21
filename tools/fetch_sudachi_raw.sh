#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEST_DIR="$ROOT_DIR/tmp/sudachi_raw"
SUDACHI_REF="develop"
RAW_DICT_BASE_URL="https://d2ej7fkh96fzlu.cloudfront.net/sudachidict-raw"
FORCE_OVERWRITE=false
INCLUDE_FULL=false

fatal_error() {
  echo "[dict][error] $1" >&2
  exit 1
}

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

extract_dict_version_from_gradle_properties() {
  local gradle_properties_path="$1"

  if [[ ! -f "$gradle_properties_path" ]]; then
    return 1
  fi

  awk -F= '
    /^dict\.version[[:space:]]*=/ {
      gsub(/[[:space:]]/, "", $2)
      if ($2 != "") {
        print $2
        exit 0
      }
    }
  ' "$gradle_properties_path"
}

raw_sources_for_module() {
  local module="$1"

  case "$module" in
    sudachidict_small)
      echo "small"
      ;;
    sudachidict_core)
      echo "small core"
      ;;
    sudachidict_full)
      echo "small core notcore"
      ;;
    *)
      return 1
      ;;
  esac
}

copy_raw_lex_sources_for_module() {
  local module="$1"
  local dict_version="$2"
  local module_dest_dir="$DEST_DIR/$module"
  local source_names
  local source_name

  source_names="$(raw_sources_for_module "$module" || true)"
  if [[ -z "$source_names" ]]; then
    echo "[dict] 警告: 未知モジュールのため raw 辞書取得をスキップします: $module" >&2
    return
  fi

  mkdir -p "$module_dest_dir"

  for source_name in $source_names; do
    local zip_url="$RAW_DICT_BASE_URL/${dict_version}/${source_name}_lex.zip"
    local zip_path="$tmp_dir/${module}_${source_name}_lex.zip"
    local extract_dir="$tmp_dir/${module}_${source_name}_extract"
    local found_csv_count=0

    echo "[dict] raw 辞書 ZIP を取得しています: $zip_url"
    if ! curl -fL "$zip_url" -o "$zip_path"; then
      echo "[dict] 警告: raw 辞書 ZIP の取得に失敗しました: $zip_url" >&2
      continue
    fi

    mkdir -p "$extract_dir"
    if ! tar -xf "$zip_path" -C "$extract_dir"; then
      echo "[dict] 警告: raw 辞書 ZIP の展開に失敗しました: $zip_path" >&2
      continue
    fi

    while IFS= read -r csv_file; do
      file_name="$(basename "$csv_file")"
      cp -f "$csv_file" "$module_dest_dir/$file_name"
      copied_count=$((copied_count + 1))
      found_csv_count=$((found_csv_count + 1))
    done < <(find "$extract_dir" -type f -name '*_lex.csv' | sort)

    if ((found_csv_count == 0)); then
      echo "[dict] 警告: raw 辞書 ZIP に *_lex.csv が見つかりません: $zip_url" >&2
    fi
  done
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
  fatal_error "curl コマンドが見つかりません。インストールして PATH を確認してください。"
fi

if ! command -v tar >/dev/null 2>&1; then
  fatal_error "tar コマンドが見つかりません。インストールして PATH を確認してください。"
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

echo "[dict] SudachiDict (${SUDACHI_REF}) をダウンロードしています..."
if ! curl -fL "$archive_url" -o "$archive_path"; then
  fatal_error "SudachiDict の取得に失敗しました。ref=${SUDACHI_REF}、ネットワーク接続、アクセス制限を確認してください。URL: $archive_url"
fi

echo "[dict] アーカイブを展開しています..."
if ! tar -xzf "$archive_path" -C "$tmp_dir"; then
  fatal_error "SudachiDict アーカイブの展開に失敗しました。ダウンロードファイル破損の可能性があります。"
fi

source_root="$(find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d -name 'SudachiDict-*' | head -n 1)"
if [[ -z "$source_root" ]]; then
  fatal_error "展開後に SudachiDict ディレクトリを検出できませんでした。"
fi

if [[ "$FORCE_OVERWRITE" == "true" ]]; then
  find "$DEST_DIR" -type f -name '*_lex.csv' -delete
fi

modules=("sudachidict_core" "sudachidict_small")
if [[ "$INCLUDE_FULL" == "true" ]]; then
  modules+=("sudachidict_full")
fi

copied_count=0
missing_required_dirs=()
missing_module_dirs=()

for module in "${modules[@]}"; do
  module_text_dir="$source_root/$module/src/main/text"

  if [[ ! -d "$module_text_dir" ]]; then
    missing_module_dirs+=("$module")
    if [[ "$module" == "sudachidict_core" || "$module" == "sudachidict_small" ]]; then
      missing_required_dirs+=("$module_text_dir")
    fi
    echo "[dict] 警告: 想定モジュールディレクトリが見つかりません: $module_text_dir" >&2
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

if ((${#missing_module_dirs[@]} > 0)); then
  dict_version="$(extract_dict_version_from_gradle_properties "$source_root/gradle.properties" || true)"

  if [[ -z "$dict_version" ]]; then
    echo "[dict] 警告: gradle.properties から dict.version を取得できないため raw 辞書フォールバックをスキップします。" >&2
  else
    echo "[dict] 想定モジュールが見つからないため raw 辞書 ZIP 取得へフォールバックします。dict.version=${dict_version}"
    for module in "${missing_module_dirs[@]}"; do
      copy_raw_lex_sources_for_module "$module" "$dict_version"
    done
  fi
fi

if ((copied_count == 0)); then
  if ((${#missing_required_dirs[@]} > 0)); then
    fatal_error "SudachiDict の取得に失敗しました。必要な CSV ディレクトリが見つからず raw 辞書フォールバックでも取得できませんでした。ref=${SUDACHI_REF}"
  fi
  fatal_error "SudachiDict の取得に失敗しました。*_lex.csv を取得できませんでした。ref=${SUDACHI_REF}、dict.version、raw 辞書 URL を確認してください。"
fi

final_count="$(find "$DEST_DIR" -type f -name '*_lex.csv' | wc -l | tr -d ' ')"

echo "[dict] Copied $copied_count files into: $DEST_DIR"
echo "[dict] Destination now has $final_count *_lex.csv files."
echo "[dict] Next step: build in Xcode or run bash tools/refresh_simulator_dictionary_on_build.sh"
