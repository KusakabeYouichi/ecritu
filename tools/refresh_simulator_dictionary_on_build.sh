#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

is_simulator_build=false
if [[ "${PLATFORM_NAME:-}" == *simulator* ]]; then
  is_simulator_build=true
fi

cd "$ROOT_DIR"

TMP_PREMIER="$ROOT_DIR/tmp/ÉcrituPremierVocab.json"
TMP_SECOND="$ROOT_DIR/tmp/ÉcrituSecondVocab.json"
TMP_SOURCES="$ROOT_DIR/tmp/kana_kanji_candidate_sources.json"
TMP_INFLECTIONS="$ROOT_DIR/tmp/kana_kanji_inflection_dictionary.json"
TMP_SQLITE="$ROOT_DIR/tmp/kana_kanji_dictionary.sqlite"

SUDACHI_CSV_FILES=()
while IFS= read -r csv_file; do
  SUDACHI_CSV_FILES+=("$csv_file")
done < <(find "$ROOT_DIR/tmp/sudachi_raw" -type f -name '*_lex.csv' 2>/dev/null | sort)

needs_regeneration() {
  ROOT_DIR="$ROOT_DIR" python3 - <<'PY'
from pathlib import Path
import os

root = Path(os.environ["ROOT_DIR"])

inputs = [
    *sorted(root.glob("tmp/sudachi_raw/**/*_lex.csv")),
    root / "tools" / "build_sudachi_index.py",
    root / "tools" / "build_kana_kanji_sqlite.py",
]

second_vocab = root / "tmp" / "ÉcrituSecondVocab.json"
if second_vocab.exists():
    inputs.append(second_vocab)

outputs = [
    root / "tmp" / "ÉcrituPremierVocab.json",
    root / "tmp" / "kana_kanji_candidate_sources.json",
    root / "tmp" / "kana_kanji_inflection_dictionary.json",
    root / "tmp" / "kana_kanji_dictionary.sqlite",
]

if not inputs or any(not out.exists() for out in outputs):
    print("1")
    raise SystemExit(0)

newest_input = max(path.stat().st_mtime for path in inputs if path.exists())
oldest_output = min(path.stat().st_mtime for path in outputs)
print("1" if newest_input > oldest_output else "0")
PY
}

if ((${#SUDACHI_CSV_FILES[@]} > 0)); then
  if [[ "$(needs_regeneration)" == "1" ]]; then
    echo "[dict] Regenerating tmp dictionary artifacts from Sudachi CSV..."

    if python3 tools/build_sudachi_index.py \
      --input-glob "tmp/sudachi_raw/**/*_lex.csv" \
      --output "$TMP_PREMIER" \
      --output-sources "$TMP_SOURCES" \
      --output-inflections "$TMP_INFLECTIONS" \
      --max-candidates 8 \
      --min-reading-len 1 \
      --max-reading-len 10 \
      --max-candidate-len 20 \
      --single-reading-max-candidates 8 \
      --single-reading-max-candidate-len 1 \
      && python3 tools/build_kana_kanji_sqlite.py \
        --vocab-json "$TMP_PREMIER" \
        --vocab-json "$TMP_SECOND" \
        --sources-json "$TMP_SOURCES" \
        --inflections-json "$TMP_INFLECTIONS" \
        --output "$TMP_SQLITE"; then
      echo "[dict] Regeneration complete."
    else
      echo "[dict] Warning: regeneration failed. Keeping previous artifacts if present."
    fi
  else
    echo "[dict] Skip regeneration (tmp artifacts are up-to-date)."
  fi
else
  echo "[dict] Skip regeneration (tmp/sudachi_raw/**/*_lex.csv not found)."
fi

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
  copy_into_bundle_if_exists "$TMP_SOURCES" "kana_kanji_candidate_sources.json"
  copy_into_bundle_if_exists "$TMP_INFLECTIONS" "kana_kanji_inflection_dictionary.json"
  copy_into_bundle_if_exists "$TMP_SQLITE" "kana_kanji_dictionary.sqlite"
else
  echo "[dict] Skip bundle overwrite (TARGET_BUILD_DIR/UNLOCALIZED_RESOURCES_FOLDER_PATH not set)."
fi

if [[ "$is_simulator_build" == "true" ]]; then
  if [[ -f "$TMP_PREMIER" && -f "$TMP_SOURCES" && -f "$TMP_INFLECTIONS" && -f "$TMP_SQLITE" ]]; then
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
