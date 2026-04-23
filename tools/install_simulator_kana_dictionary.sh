#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DICT_PATH="${1:-$ROOT_DIR/tmp/ÉcrituPremierVocab.json}"
SECOND_DICT_PATH="${ECRITU_SECOND_DICT_PATH:-$ROOT_DIR/tmp/ÉcrituSecondVocab.json}"
INFLECTION_DICT_PATH="${2:-$ROOT_DIR/tmp/kana_kanji_inflection_dictionary.json}"
SOURCE_TAG_DICT_PATH="${3:-$ROOT_DIR/tmp/kana_kanji_candidate_sources.json}"
SQLITE_DICT_PATH="${4:-$ROOT_DIR/tmp/kana_kanji_dictionary.sqlite}"

if [[ ! -f "$DICT_PATH" ]]; then
  echo "Dictionary file not found: $DICT_PATH" >&2
  exit 1
fi

SIM_UDID="$(xcrun simctl list devices available | sed -nE 's/^[[:space:]]*iPhone 17 Pro \(([A-F0-9-]+)\) \((Booted|Shutdown)\).*/\1/p' | head -n 1)"

if [[ -z "$SIM_UDID" ]]; then
  echo "iPhone 17 Pro simulator is not available" >&2
  exit 1
fi

xcrun simctl boot "$SIM_UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIM_UDID" -b >/dev/null

APP_GROUP_PATH="$(xcrun simctl get_app_container "$SIM_UDID" com.kusakabe.ecritu "group.com.kusakabe.ecritu")"

if [[ -z "$APP_GROUP_PATH" ]]; then
  echo "Failed to resolve app group container path" >&2
  exit 1
fi

cp -f "$DICT_PATH" "$APP_GROUP_PATH/ÉcrituPremierVocab.json"

if [[ -f "$SECOND_DICT_PATH" ]]; then
  cp -f "$SECOND_DICT_PATH" "$APP_GROUP_PATH/ÉcrituSecondVocab.json"
fi

find "$APP_GROUP_PATH" -maxdepth 1 -type f -name 'kana_kanji*_dictionary.json' ! -name 'kana_kanji_inflection_dictionary.json' -delete

if [[ -f "$INFLECTION_DICT_PATH" ]]; then
  cp -f "$INFLECTION_DICT_PATH" "$APP_GROUP_PATH/kana_kanji_inflection_dictionary.json"
fi

if [[ -f "$SOURCE_TAG_DICT_PATH" ]]; then
  cp -f "$SOURCE_TAG_DICT_PATH" "$APP_GROUP_PATH/kana_kanji_candidate_sources.json"
fi

if [[ -f "$SQLITE_DICT_PATH" ]]; then
  cp -f "$SQLITE_DICT_PATH" "$APP_GROUP_PATH/kana_kanji_dictionary.sqlite"
fi

echo "Installed dictionary to: $APP_GROUP_PATH/ÉcrituPremierVocab.json"
ls -lh "$APP_GROUP_PATH/ÉcrituPremierVocab.json"

if [[ -f "$SECOND_DICT_PATH" ]]; then
  echo "Installed supplemental dictionary to: $APP_GROUP_PATH/ÉcrituSecondVocab.json"
  ls -lh "$APP_GROUP_PATH/ÉcrituSecondVocab.json"
else
  echo "Supplemental dictionary not found (skipped): $SECOND_DICT_PATH"
fi

if [[ -f "$INFLECTION_DICT_PATH" ]]; then
  echo "Installed inflection dictionary to: $APP_GROUP_PATH/kana_kanji_inflection_dictionary.json"
  ls -lh "$APP_GROUP_PATH/kana_kanji_inflection_dictionary.json"
else
  echo "Inflection dictionary not found (skipped): $INFLECTION_DICT_PATH"
fi

if [[ -f "$SOURCE_TAG_DICT_PATH" ]]; then
  echo "Installed candidate-source dictionary to: $APP_GROUP_PATH/kana_kanji_candidate_sources.json"
  ls -lh "$APP_GROUP_PATH/kana_kanji_candidate_sources.json"
else
  echo "Candidate-source dictionary not found (skipped): $SOURCE_TAG_DICT_PATH"
fi

if [[ -f "$SQLITE_DICT_PATH" ]]; then
  echo "Installed SQLite dictionary to: $APP_GROUP_PATH/kana_kanji_dictionary.sqlite"
  ls -lh "$APP_GROUP_PATH/kana_kanji_dictionary.sqlite"
else
  echo "SQLite dictionary not found (skipped): $SQLITE_DICT_PATH"
fi
