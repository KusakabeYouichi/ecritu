#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEST_DIR="$ROOT_DIR/tmp/sudachi_raw"
# 取得する版はタグに固定し、展開した CSV を tools/dictionary_sources.sha256 と突き合わせる(3315)。
# 以前は develop ブランチを追い、照合もしていなかったため、ミラーの改ざんやブランチの移動で
# 出荷する辞書の中身が黙って変わり得た(セキュリティー検査 2026-10-02)。版を上げる手順は manifest 冒頭
SUDACHI_REF="v20260428"
MANIFEST_PATH="$ROOT_DIR/tools/dictionary_sources.sha256"
PRINT_HASHES=false
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
  --ref <git-ref>       SudachiDict ref to download (default: v20260428, the pinned tag)
  --force               Replace existing *_lex.csv files in destination
  --include-full        Also import sudachidict_full data when available
  --print-hashes        Print "sha256  path" lines for the fetched CSVs (for updating tools/dictionary_sources.sha256)
  -h, --help            Show this help

Every fetched CSV is checked against tools/dictionary_sources.sha256 before it is placed in the
destination. A mismatch aborts; to move to a new version intentionally, change --ref/SUDACHI_REF,
run with --print-hashes, review, and update the manifest in the same commit as the rebuilt dictionary.
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
  local module_dest_dir="$staging_dir/$module"
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
    --print-hashes)
      PRINT_HASHES=true
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
# archive/<ref>.tar.gz はタグ・ブランチ・コミット SHA のどれでも解決する(refs/heads/ 固定だとタグが取れない)
archive_url="https://github.com/WorksApplications/SudachiDict/archive/${SUDACHI_REF}.tar.gz"
# 展開した CSV はいったん staging に置き、manifest と照合してから DEST_DIR へ移す
staging_dir="$tmp_dir/staged"
mkdir -p "$staging_dir"

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
    module_dest_dir="$staging_dir/$module"
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

# 照合(3315): staging の CSV を manifest(tools/dictionary_sources.sha256、相対パスは tmp/ 基準)と突き合わせる。
# 1 件でも合わない・載っていないなら DEST_DIR には何も置かずに失敗する。--print-hashes は実測値を manifest 形式で出す
[[ -f "$MANIFEST_PATH" ]] || fatal_error "manifest が見つかりません: $MANIFEST_PATH"
mismatches=()
actual_lines=()
while IFS= read -r staged_csv; do
  rel_path="sudachi_raw/${staged_csv#"$staging_dir/"}"
  actual_hash="$(shasum -a 256 "$staged_csv" | cut -d' ' -f1)"
  actual_lines+=("$actual_hash  $rel_path")
  expected_hash="$(grep -E "^[0-9a-f]{64}  ${rel_path}$" "$MANIFEST_PATH" | cut -d' ' -f1 || true)"
  if [[ -z "$expected_hash" ]]; then
    mismatches+=("$rel_path: manifest に無い(実測 $actual_hash)")
  elif [[ "$expected_hash" != "$actual_hash" ]]; then
    mismatches+=("$rel_path: 期待 $expected_hash / 実測 $actual_hash")
  fi
done < <(find "$staging_dir" -type f -name '*_lex.csv' | sort)

if [[ "$PRINT_HASHES" == "true" ]]; then
  echo "[dict] 実測ハッシュ(manifest 形式):"
  printf '%s\n' "${actual_lines[@]}"
fi

if ((${#mismatches[@]} > 0)); then
  echo "[dict][error] 取得した CSV が tools/dictionary_sources.sha256 と一致しません。tmp/ には置きません。" >&2
  printf '  %s\n' "${mismatches[@]}" >&2
  echo "[dict][error] 版を上げる意図なら、--ref を新しいタグにして --print-hashes で実測を確かめ、manifest を同じコミットで更新してください(ref=${SUDACHI_REF})" >&2
  exit 1
fi
echo "[dict] manifest と一致(${#actual_lines[@]} ファイル、ref=${SUDACHI_REF})"

# 照合を通ったものだけ DEST_DIR へ
while IFS= read -r staged_csv; do
  rel="${staged_csv#"$staging_dir/"}"
  mkdir -p "$DEST_DIR/$(dirname "$rel")"
  mv -f "$staged_csv" "$DEST_DIR/$rel"
done < <(find "$staging_dir" -type f -name '*_lex.csv' | sort)

final_count="$(find "$DEST_DIR" -type f -name '*_lex.csv' | wc -l | tr -d ' ')"

echo "[dict] Copied $copied_count files into: $DEST_DIR"
echo "[dict] Destination now has $final_count *_lex.csv files."
echo "[dict] Next step: build in Xcode or run bash tools/refresh_simulator_dictionary_on_build.sh"
