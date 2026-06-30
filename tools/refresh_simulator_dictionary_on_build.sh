#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
AUTO_FETCH_SUDACHI_ON_BUILD="${ECRITU_AUTO_FETCH_SUDACHI_ON_BUILD:-1}"
AUTO_FETCH_SUDACHI_INCLUDE_FULL="${ECRITU_AUTO_FETCH_SUDACHI_INCLUDE_FULL:-0}"
PROMPT_ON_SUDACHI_FALLBACK="${ECRITU_PROMPT_ON_SUDACHI_FALLBACK:-1}"
SUDACHI_FALLBACK_NONINTERACTIVE_DEFAULT="${ECRITU_SUDACHI_FALLBACK_NONINTERACTIVE_DEFAULT:-continue}"

is_simulator_build=false
if [[ "${PLATFORM_NAME:-}" == *simulator* ]]; then
  is_simulator_build=true
fi

cd "$ROOT_DIR"

TMP_PREMIER="$ROOT_DIR/tmp/ÉcrituPremierVocab.json"
TMP_SECOND="$ROOT_DIR/tmp/ÉcrituSecondVocab.json"
TMP_INITIAL_AJOUT="$ROOT_DIR/tmp/InitialAjoutVocabMigration.json"
TMP_SECOND_INFLECTIONS="$ROOT_DIR/tmp/references_second_inflections.json"
TMP_INITIAL_AJOUT_INFLECTIONS="$ROOT_DIR/tmp/references_void_inflections.json"
TMP_SOURCES="$ROOT_DIR/tmp/kana_kanji_candidate_sources.json"
TMP_INFLECTIONS="$ROOT_DIR/tmp/kana_kanji_inflection_dictionary.json"
TMP_SQLITE="$ROOT_DIR/tmp/kana_kanji_dictionary.sqlite"

REF_RYUKYU_PLIST="$ROOT_DIR/references/ryukyu.plist"
REF_VIN_PLIST="$ROOT_DIR/references/vin.plist"
REF_IT_PLIST="$ROOT_DIR/references/it.plist"
REF_VOID_PLIST="$ROOT_DIR/references/void.plist"
REF_PERSONNALITES_PLIST="$ROOT_DIR/references/personnalités.plist"
REF_DRAPEAUX_PLIST="$ROOT_DIR/references/drapeaux.plist"
REF_MONNAIES_PLIST="$ROOT_DIR/references/monnaies.plist"
REF_ADJECTIVE_GARU_ALLOWLIST="$ROOT_DIR/references/adjective_garu_allowlist.json"

SUDACHI_CSV_FILES=()

discover_sudachi_csv_files() {
  SUDACHI_CSV_FILES=()
  while IFS= read -r csv_file; do
    SUDACHI_CSV_FILES+=("$csv_file")
  done < <(find "$ROOT_DIR/tmp/sudachi_raw" -type f -name '*_lex.csv' 2>/dev/null | sort)
}

is_truthy() {
  case "$1" in
    1|true|TRUE|yes|YES|on|ON)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

seed_entry_count() {
  ROOT_DIR="$ROOT_DIR" python3 - <<'PY'
from pathlib import Path
import os
import re

seed_path = Path(os.environ["ROOT_DIR"]) / "KeyboardExtension" / "KanaKanjiSeedDictionary.swift"

try:
    text = seed_path.read_text(encoding="utf-8")
except OSError:
    print("108")
    raise SystemExit(0)

entries = len(re.findall(r'"[^"]+"\s*:\s*\[', text))
print(entries if entries > 0 else 108)
PY
}

confirm_seed_fallback_continue() {
  local entry_count="$1"
  local prompt_message="Sudachiデータの取得に失敗したので、フォールバック用の${entry_count}エントリーだけの辞書でビルドを継続しますか?"
  local osascript_result=""

  if ! is_truthy "$PROMPT_ON_SUDACHI_FALLBACK"; then
    return 0
  fi

  if [[ -t 0 && -t 1 ]]; then
    local answer=""
    read -r -p "[dict] ${prompt_message} [y/N] " answer
    case "$answer" in
      y|Y|yes|YES)
        return 0
        ;;
      *)
        return 1
        ;;
    esac
  fi

  if command -v osascript >/dev/null 2>&1 && [[ -z "${CI:-}" ]]; then
    osascript_result="$(osascript \
      -e 'set promptText to item 1 of argv' \
      -e 'set dialogResult to display dialog promptText buttons {"中止", "継続"} default button "中止" with title "écritu Dictionary Build" with icon caution' \
      -e 'button returned of dialogResult' \
      "$prompt_message" 2>/dev/null || true)"

    if [[ "$osascript_result" == "継続" ]]; then
      return 0
    fi

    if [[ "$osascript_result" == "中止" ]]; then
      return 1
    fi

    echo "[dict] Warning: フォールバック確認ダイアログを表示できませんでした。非対話既定値(${SUDACHI_FALLBACK_NONINTERACTIVE_DEFAULT})を使用します。"
  fi

  case "$SUDACHI_FALLBACK_NONINTERACTIVE_DEFAULT" in
    abort|ABORT|stop|STOP)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

discover_sudachi_csv_files

if ((${#SUDACHI_CSV_FILES[@]} == 0)) && is_truthy "$AUTO_FETCH_SUDACHI_ON_BUILD"; then
  echo "[dict] Sudachi CSV が見つからないため自動取得を試行します..."
  if is_truthy "$AUTO_FETCH_SUDACHI_INCLUDE_FULL"; then
    FETCH_SUDACHI_CMD=(bash tools/fetch_sudachi_raw.sh --include-full)
  else
    FETCH_SUDACHI_CMD=(bash tools/fetch_sudachi_raw.sh)
  fi

  if "${FETCH_SUDACHI_CMD[@]}"; then
    discover_sudachi_csv_files
    echo "[dict] Sudachi CSV 自動取得に成功しました。"
  else
    echo "[dict] Warning: Sudachi CSV 自動取得に失敗しました。従来どおり同梱プレースホルダー辞書で継続します。"
  fi
fi

# Build supplemental and initial-migration vocab first so SQLite regeneration
# can include the latest plist-derived entries (e.g. it.plist additions).
python3 tools/build_second_vocab_from_references.py \
  --input-plist "$REF_RYUKYU_PLIST" \
  --input-plist "$REF_VIN_PLIST" \
  --input-plist "$REF_IT_PLIST" \
  --input-plist "$REF_PERSONNALITES_PLIST" \
  --input-plist "$REF_DRAPEAUX_PLIST" \
  --input-plist "$REF_MONNAIES_PLIST" \
  --output "$TMP_SECOND" \
  --output-inflections "$TMP_SECOND_INFLECTIONS"

python3 tools/build_second_vocab_from_references.py \
  --input-plist "$REF_VOID_PLIST" \
  --output "$TMP_INITIAL_AJOUT" \
  --output-inflections "$TMP_INITIAL_AJOUT_INFLECTIONS"

needs_sudachi_regeneration() {
  ROOT_DIR="$ROOT_DIR" python3 - <<'PY'
from pathlib import Path
import os

root = Path(os.environ["ROOT_DIR"])

inputs = [
    *sorted(root.glob("tmp/sudachi_raw/**/*_lex.csv")),
  root / "tools" / "refresh_simulator_dictionary_on_build.sh",
  root / "tools" / "build_sudachi_index.py",
  root / "references" / "adjective_garu_allowlist.json",
]

outputs = [
    root / "tmp" / "ÉcrituPremierVocab.json",
    root / "tmp" / "kana_kanji_candidate_sources.json",
    root / "tmp" / "kana_kanji_inflection_dictionary.json",
]

if not inputs or any(not out.exists() for out in outputs):
    print("1")
    raise SystemExit(0)

newest_input = max(path.stat().st_mtime for path in inputs if path.exists())
oldest_output = min(path.stat().st_mtime for path in outputs)
print("1" if newest_input > oldest_output else "0")
PY
}

needs_sqlite_regeneration() {
  if [[ ! -f "$TMP_SQLITE" ]]; then
    return 0
  fi

  if [[ "$TMP_PREMIER" -nt "$TMP_SQLITE" ]] \
    || [[ "$TMP_SECOND" -nt "$TMP_SQLITE" ]] \
    || [[ "$ROOT_DIR/tools/build_kana_kanji_sqlite.py" -nt "$TMP_SQLITE" ]] \
    || [[ "$ROOT_DIR/tools/refresh_simulator_dictionary_on_build.sh" -nt "$TMP_SQLITE" ]]; then
    return 0
  fi

  if [[ -f "$TMP_SOURCES" && "$TMP_SOURCES" -nt "$TMP_SQLITE" ]]; then
    return 0
  fi

  if [[ -f "$TMP_INFLECTIONS" && "$TMP_INFLECTIONS" -nt "$TMP_SQLITE" ]]; then
    return 0
  fi

  return 1
}

regenerate_sqlite_if_possible() {
  if [[ ! -f "$TMP_PREMIER" || ! -f "$TMP_SECOND" ]]; then
    if [[ -f "$TMP_SQLITE" ]]; then
      echo "[dict] Warning: sqlite再生成に必要な語彙JSONが不足しているため、古いSQLiteを削除してJSONフォールバックを優先します。"
      rm -f "$TMP_SQLITE"
    else
      echo "[dict] Skip sqlite regeneration (missing vocab json: $TMP_PREMIER or $TMP_SECOND)."
    fi
    return
  fi

  if ! needs_sqlite_regeneration; then
    echo "[dict] Skip sqlite regeneration (kana_kanji_dictionary.sqlite is up-to-date)."
    return
  fi

  local sqlite_args=(
    python3 tools/build_kana_kanji_sqlite.py
    --vocab-json "$TMP_SECOND"
    --vocab-json "$TMP_PREMIER"
    --output "$TMP_SQLITE"
  )

  if [[ -f "$TMP_SOURCES" ]]; then
    sqlite_args+=(--sources-json "$TMP_SOURCES")
  fi

  if [[ -f "$TMP_INFLECTIONS" ]]; then
    sqlite_args+=(--inflections-json "$TMP_INFLECTIONS")
  fi

  if [[ -f "$TMP_SECOND_INFLECTIONS" ]]; then
    sqlite_args+=(--inflections-json "$TMP_SECOND_INFLECTIONS")
  fi

  if [[ -f "$TMP_INITIAL_AJOUT_INFLECTIONS" ]]; then
    sqlite_args+=(--inflections-json "$TMP_INITIAL_AJOUT_INFLECTIONS")
  fi

  if "${sqlite_args[@]}"; then
    echo "[dict] SQLite regeneration complete."
  else
    echo "[dict] Warning: sqlite regeneration failed. Keeping previous artifacts if present."
  fi
}

if ((${#SUDACHI_CSV_FILES[@]} > 0)); then
  if [[ "$(needs_sudachi_regeneration)" == "1" ]]; then
    echo "[dict] Regenerating Sudachi-derived dictionary artifacts..."

    sudachi_args=(
      python3 tools/build_sudachi_index.py
      --input-glob "tmp/sudachi_raw/**/*_lex.csv"
      --output "$TMP_PREMIER"
      --output-sources "$TMP_SOURCES"
      --output-inflections "$TMP_INFLECTIONS"
      --max-candidates 24
      --min-reading-len 1
      --max-reading-len 10
      --max-candidate-len 20
      --single-reading-max-candidates 21
      --single-reading-max-candidate-len 1
    )

    if [[ -f "$REF_ADJECTIVE_GARU_ALLOWLIST" ]]; then
      sudachi_args+=(--adjective-garu-allowlist "$REF_ADJECTIVE_GARU_ALLOWLIST")
    fi

    if "${sudachi_args[@]}"; then
      echo "[dict] Sudachi regeneration complete."
    else
      echo "[dict] Warning: Sudachi regeneration failed. Keeping previous artifacts if present."
    fi
  else
    echo "[dict] Skip Sudachi regeneration (tmp artifacts are up-to-date)."
  fi
else
  SEED_ENTRY_COUNT="$(seed_entry_count)"
  if ! confirm_seed_fallback_continue "$SEED_ENTRY_COUNT"; then
    echo "[dict] Sudachi CSV が未取得のためビルドを中止しました。"
    echo "[dict] Hint: run 'bash tools/fetch_sudachi_raw.sh' and retry build."
    exit 1
  fi

  echo "[dict] フォールバック seed 辞書(${SEED_ENTRY_COUNT}エントリー)でビルドを継続します。"
  echo "[dict] Skip regeneration (tmp/sudachi_raw/**/*_lex.csv not found)."
  if is_truthy "$AUTO_FETCH_SUDACHI_ON_BUILD"; then
    echo "[dict] Hint: network or access restriction may block auto-fetch; run 'bash tools/fetch_sudachi_raw.sh' manually."
  else
    echo "[dict] Hint: auto-fetch is disabled (ECRITU_AUTO_FETCH_SUDACHI_ON_BUILD=$AUTO_FETCH_SUDACHI_ON_BUILD)."
    echo "[dict] Hint: run 'bash tools/fetch_sudachi_raw.sh' manually or enable auto-fetch."
  fi
fi

regenerate_sqlite_if_possible

if [[ -n "${TARGET_BUILD_DIR:-}" && -n "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]]; then
  BUNDLE_RESOURCES_DIR="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
  mkdir -p "$BUNDLE_RESOURCES_DIR"

  copy_into_bundle_if_exists() {
    local src_path="$1"
    local dst_name="$2"

    if [[ ! -f "$src_path" ]]; then
      echo "[dict] Skip bundle overwrite (missing): $src_path"
      return
    fi

    cp -f "$src_path" "$BUNDLE_RESOURCES_DIR/$dst_name"
    echo "[dict] Overwrote bundle resource: $dst_name"
  }

  copy_into_bundle_if_exists "$TMP_PREMIER" "ÉcrituPremierVocab.json"
  copy_into_bundle_if_exists "$TMP_SECOND" "ÉcrituSecondVocab.json"
  copy_into_bundle_if_exists "$TMP_INITIAL_AJOUT" "InitialAjoutVocabMigration.json"
  copy_into_bundle_if_exists "$TMP_SOURCES" "kana_kanji_candidate_sources.json"
  copy_into_bundle_if_exists "$TMP_INFLECTIONS" "kana_kanji_inflection_dictionary.json"
  copy_into_bundle_if_exists "$TMP_SQLITE" "kana_kanji_dictionary.sqlite"
else
  echo "[dict] Skip bundle overwrite (TARGET_BUILD_DIR/UNLOCALIZED_RESOURCES_FOLDER_PATH not set)."
fi

if [[ "$is_simulator_build" == "true" ]]; then
  if [[ -f "$TMP_PREMIER" && -f "$TMP_SQLITE" ]]; then
    if bash tools/install_simulator_kana_dictionary.sh; then
      echo "[dict] App Group dictionary sync complete."
    else
      echo "[dict] Warning: App Group dictionary sync failed; build continues with bundled resources."
    fi
  else
    echo "[dict] Skip App Group sync (tmp dictionary artifacts are missing)."
  fi
else
  echo "[dict] Skip App Group sync (PLATFORM_NAME=${PLATFORM_NAME:-unknown})."
fi
