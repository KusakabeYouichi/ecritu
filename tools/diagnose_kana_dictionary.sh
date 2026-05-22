#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="${ECRITU_PROJECT_PATH:-$ROOT_DIR/écritu.xcodeproj}"
SCHEME_NAME="${ECRITU_SCHEME_NAME:-écritu}"
SIM_NAME="${ECRITU_SIM_NAME:-iPhone 17 Pro}"

WARN_COUNT=0

log_header() {
  echo ""
  echo "== $1 =="
}

warn_line() {
  echo "[WARN] $1"
  WARN_COUNT=$((WARN_COUNT + 1))
}

ok_line() {
  echo "[OK]   $1"
}

info_line() {
  echo "[INFO] $1"
}

file_size_bytes() {
  if [[ -f "$1" ]]; then
    stat -f "%z" "$1"
  else
    echo "0"
  fi
}

file_mtime_utc() {
  if [[ -f "$1" ]]; then
    date -u -r "$1" "+%Y-%m-%dT%H:%M:%SZ"
  else
    echo "-"
  fi
}

json_stats() {
  local json_path="$1"
  python3 - "$json_path" <<'PY'
import json
import sys

path = sys.argv[1]

with open(path, "rb") as f:
    data = json.load(f)

if not isinstance(data, dict):
    print("type=invalid")
    raise SystemExit(3)

readings = len(data)
list_items = 0
dict_items = 0
scalar_values = 0
max_per_reading = 0

for values in data.values():
    if isinstance(values, list):
        count = len(values)
        list_items += count
        if count > max_per_reading:
            max_per_reading = count
    elif isinstance(values, dict):
        count = len(values)
        dict_items += count
        if count > max_per_reading:
            max_per_reading = count
    else:
        scalar_values += 1

print(
    "readings="
    f"{readings} "
    f"list_items={list_items} "
    f"dict_items={dict_items} "
    f"scalar_values={scalar_values} "
    f"max_per_reading={max_per_reading}"
)

if readings == 0:
    raise SystemExit(2)
PY
}

sqlite_stats() {
  local sqlite_path="$1"
  python3 - "$sqlite_path" <<'PY'
import sqlite3
import sys

path = sys.argv[1]
con = sqlite3.connect(path)

try:
    cur = con.cursor()
    cur.execute("SELECT COUNT(*), COUNT(DISTINCT reading) FROM dictionary_entries")
    rows, readings = cur.fetchone()
    print(f"rows={rows} readings={readings}")
    if rows == 0:
        raise SystemExit(2)
except sqlite3.Error as exc:
    print(f"sqlite_error={exc}")
    raise SystemExit(3)
finally:
    con.close()
PY
}

report_json_file() {
  local label="$1"
  local path="$2"

  if [[ ! -f "$path" ]]; then
    warn_line "$label missing: $path"
    return
  fi

  local size
  size="$(file_size_bytes "$path")"
  local mtime
  mtime="$(file_mtime_utc "$path")"

  if [[ "$size" == "0" ]]; then
    warn_line "$label exists but empty: $path"
    return
  fi

  local stats
  if stats="$(json_stats "$path" 2>/dev/null)"; then
    ok_line "$label $stats size=${size}B mtime=$mtime path=$path"
  else
    local code=$?
    if [[ $code -eq 2 ]]; then
      warn_line "$label has zero readings size=${size}B mtime=$mtime path=$path"
    else
      warn_line "$label could not be parsed as dictionary JSON size=${size}B mtime=$mtime path=$path"
    fi
  fi
}

report_sqlite_file() {
  local label="$1"
  local path="$2"

  if [[ ! -f "$path" ]]; then
    warn_line "$label missing: $path"
    return
  fi

  local size
  size="$(file_size_bytes "$path")"
  local mtime
  mtime="$(file_mtime_utc "$path")"

  if [[ "$size" == "0" ]]; then
    warn_line "$label exists but empty: $path"
    return
  fi

  local stats
  if stats="$(sqlite_stats "$path" 2>/dev/null)"; then
    ok_line "$label $stats size=${size}B mtime=$mtime path=$path"
  else
    local code=$?
    if [[ $code -eq 2 ]]; then
      warn_line "$label has zero rows size=${size}B mtime=$mtime path=$path"
    else
      warn_line "$label could not be queried size=${size}B mtime=$mtime path=$path"
    fi
  fi
}

find_built_app_path() {
  local app_path=""

  app_path="$(find "$ROOT_DIR/build/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name '*.app' 2>/dev/null | head -n 1 || true)"

  if [[ -z "$app_path" ]]; then
    app_path="$(find "$ROOT_DIR/build/Debug-iphonesimulator" -maxdepth 1 -name '*.app' 2>/dev/null | head -n 1 || true)"
  fi

  echo "$app_path"
}

detect_bundle_id_from_build_settings() {
  if [[ ! -d "$PROJECT_PATH" ]]; then
    return
  fi

  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME_NAME" \
    -showBuildSettings 2>/dev/null \
    | awk -F ' = ' '/^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER[[:space:]]*=/{print $2; exit}'
}

detect_group_id_from_build_settings() {
  if [[ ! -d "$PROJECT_PATH" ]]; then
    return
  fi

  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME_NAME" \
    -showBuildSettings 2>/dev/null \
    | awk -F ' = ' '/^[[:space:]]*ECRITU_APP_GROUP_IDENTIFIER[[:space:]]*=/{print $2; exit}'
}

find_sim_udid() {
  if [[ -n "${ECRITU_SIM_UDID:-}" ]]; then
    echo "$ECRITU_SIM_UDID"
    return
  fi

  xcrun simctl list devices available \
    | sed -nE "s/^[[:space:]]*${SIM_NAME// /\\ } \\(([A-F0-9-]+)\\) \\((Booted|Shutdown)\\).*/\\1/p" \
    | head -n 1
}

log_header "Environment"
info_line "root=$ROOT_DIR"
info_line "project=$PROJECT_PATH"
info_line "scheme=$SCHEME_NAME"
info_line "simulator_name=$SIM_NAME"

log_header "Local tmp artifacts"
report_json_file "tmp premier" "$ROOT_DIR/tmp/ÉcrituPremierVocab.json"
report_json_file "tmp second" "$ROOT_DIR/tmp/ÉcrituSecondVocab.json"
report_json_file "tmp candidate sources" "$ROOT_DIR/tmp/kana_kanji_candidate_sources.json"
report_json_file "tmp inflection" "$ROOT_DIR/tmp/kana_kanji_inflection_dictionary.json"
report_sqlite_file "tmp sqlite" "$ROOT_DIR/tmp/kana_kanji_dictionary.sqlite"

APP_PATH="${ECRITU_APP_PATH:-$(find_built_app_path)}"
APP_BUNDLE_ID="${ECRITU_APP_BUNDLE_IDENTIFIER:-}"
APP_GROUP_ID="${ECRITU_APP_GROUP_IDENTIFIER:-}"

if [[ -z "$APP_BUNDLE_ID" && -n "$APP_PATH" ]]; then
  APP_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist" 2>/dev/null || true)"
fi

if [[ -z "$APP_GROUP_ID" && -n "$APP_PATH" ]]; then
  APP_GROUP_ID="$(/usr/libexec/PlistBuddy -c 'Print :EcrituAppGroupIdentifier' "$APP_PATH/Info.plist" 2>/dev/null || true)"
fi

if [[ -z "$APP_BUNDLE_ID" ]]; then
  APP_BUNDLE_ID="$(detect_bundle_id_from_build_settings || true)"
fi

if [[ -z "$APP_GROUP_ID" ]]; then
  APP_GROUP_ID="$(detect_group_id_from_build_settings || true)"
fi

if [[ -z "$APP_GROUP_ID" && -n "$APP_BUNDLE_ID" ]]; then
  APP_GROUP_ID="group.$APP_BUNDLE_ID"
fi

log_header "Built app resources"

if [[ -z "$APP_PATH" ]]; then
  warn_line "built app not found under build/Debug-iphonesimulator"
else
  ok_line "app path=$APP_PATH"

  KBD_APPEX_PATH="$APP_PATH/PlugIns/KeyboardExtension.appex"

  if [[ ! -d "$KBD_APPEX_PATH" ]]; then
    warn_line "KeyboardExtension.appex not found in built app"
  else
    report_json_file "bundle premier" "$KBD_APPEX_PATH/ÉcrituPremierVocab.json"
    report_json_file "bundle second" "$KBD_APPEX_PATH/ÉcrituSecondVocab.json"
    report_json_file "bundle candidate sources" "$KBD_APPEX_PATH/kana_kanji_candidate_sources.json"
    report_json_file "bundle inflection" "$KBD_APPEX_PATH/kana_kanji_inflection_dictionary.json"
    report_sqlite_file "bundle sqlite" "$KBD_APPEX_PATH/kana_kanji_dictionary.sqlite"
  fi
fi

log_header "Simulator App Group resources"

if [[ -z "$APP_BUNDLE_ID" ]]; then
  warn_line "app bundle identifier could not be detected"
else
  info_line "app_bundle_id=$APP_BUNDLE_ID"
fi

if [[ -z "$APP_GROUP_ID" ]]; then
  warn_line "app group identifier could not be detected"
else
  info_line "app_group_id=$APP_GROUP_ID"
fi

SIM_UDID="$(find_sim_udid || true)"
if [[ -z "$SIM_UDID" ]]; then
  warn_line "simulator not found: $SIM_NAME"
else
  info_line "sim_udid=$SIM_UDID"

  xcrun simctl boot "$SIM_UDID" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$SIM_UDID" -b >/dev/null 2>&1 || true

  APP_GROUP_PATH=""
  if [[ -n "$APP_BUNDLE_ID" && -n "$APP_GROUP_ID" ]]; then
    APP_GROUP_PATH="$(xcrun simctl get_app_container "$SIM_UDID" "$APP_BUNDLE_ID" "$APP_GROUP_ID" 2>/dev/null || true)"
  fi

  if [[ -z "$APP_GROUP_PATH" ]]; then
    warn_line "app group container not resolved (app may not be installed, or bundle/group mismatch)"
  else
    ok_line "app_group_path=$APP_GROUP_PATH"
    report_json_file "app group premier" "$APP_GROUP_PATH/ÉcrituPremierVocab.json"
    report_json_file "app group second" "$APP_GROUP_PATH/ÉcrituSecondVocab.json"
    report_json_file "app group candidate sources" "$APP_GROUP_PATH/kana_kanji_candidate_sources.json"
    report_json_file "app group inflection" "$APP_GROUP_PATH/kana_kanji_inflection_dictionary.json"
    report_sqlite_file "app group sqlite" "$APP_GROUP_PATH/kana_kanji_dictionary.sqlite"
  fi
fi

log_header "Suggested next actions"
if [[ $WARN_COUNT -eq 0 ]]; then
  ok_line "No obvious dictionary deployment issue detected."
  info_line "If candidate count is still zero in app, capture extension logs around KanaKanjiStore load path."
else
  info_line "1) If tmp premier is missing or empty, run: bash tools/fetch_sudachi_raw.sh"
  info_line "2) Then rebuild KeyboardExtension so refresh_simulator_dictionary_on_build.sh regenerates artifacts."
  info_line "3) If app group files are missing, run: bash tools/install_simulator_kana_dictionary.sh"
  info_line "4) Re-run this script and share full output for remote troubleshooting."
fi

echo ""
info_line "diagnostic_warnings=$WARN_COUNT"
