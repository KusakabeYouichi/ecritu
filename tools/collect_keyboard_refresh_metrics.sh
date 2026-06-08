#!/usr/bin/env bash
set -euo pipefail

SIM_UDID="${ECRITU_SIM_UDID:-3F938359-9491-4D88-8ED8-178CF3D74F61}"
APP_BUNDLE_ID="${ECRITU_APP_BUNDLE_ID:-com.kusakabe.ecritu.dev}"
APP_GROUP_ID="${ECRITU_APP_GROUP_ID:-group.${APP_BUNDLE_ID}}"
TAIL_COUNT="${ECRITU_METRICS_TAIL:-20}"
CLEAR_MODE=0

while (($# > 0)); do
  case "$1" in
    --clear)
      CLEAR_MODE=1
      shift
      ;;
    --tail)
      TAIL_COUNT="$2"
      shift 2
      ;;
    --sim-udid)
      SIM_UDID="$2"
      shift 2
      ;;
    --bundle-id)
      APP_BUNDLE_ID="$2"
      shift 2
      ;;
    --group-id)
      APP_GROUP_ID="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

GROUP_PATH="$(xcrun simctl get_app_container "$SIM_UDID" "$APP_BUNDLE_ID" "$APP_GROUP_ID" 2>/dev/null || true)"

if [[ -z "$GROUP_PATH" ]]; then
  echo "Failed to resolve app group container."
  echo "sim_udid=$SIM_UDID"
  echo "bundle_id=$APP_BUNDLE_ID"
  echo "group_id=$APP_GROUP_ID"
  exit 1
fi

PLIST_PATH="$GROUP_PATH/Library/Preferences/${APP_GROUP_ID}.plist"

echo "sim_udid=$SIM_UDID"
echo "bundle_id=$APP_BUNDLE_ID"
echo "group_id=$APP_GROUP_ID"
echo "group_path=$GROUP_PATH"
echo "plist_path=$PLIST_PATH"

if [[ ! -f "$PLIST_PATH" ]]; then
  echo "plist_missing=1"
  exit 0
fi

if ((CLEAR_MODE == 1)); then
  /usr/bin/plutil -remove keyboardDiagnosticsLogLines "$PLIST_PATH" 2>/dev/null || true
  /usr/bin/plutil -remove keyboardDiagnosticsLastEvent "$PLIST_PATH" 2>/dev/null || true
  /usr/bin/plutil -remove keyboardDiagnosticsLastHeartbeat "$PLIST_PATH" 2>/dev/null || true
  /usr/bin/plutil -remove keyboardDiagnosticsLastSessionID "$PLIST_PATH" 2>/dev/null || true
  echo "cleared=1"
  exit 0
fi

TMP_XML="$(mktemp)"
TMP_LINES="$(mktemp)"
cleanup() {
  rm -f "$TMP_XML" "$TMP_LINES"
}
trap cleanup EXIT

if ! /usr/bin/plutil -extract keyboardDiagnosticsLogLines xml1 "$PLIST_PATH" -o "$TMP_XML" 2>/dev/null; then
  echo "log_key_missing=1"
  exit 0
fi

BASE64_PAYLOAD="$(awk '
  BEGIN { in_data = 0 }
  /<data>/ { in_data = 1; next }
  /<\/data>/ { in_data = 0 }
  {
    if (in_data) {
      gsub(/[[:space:]]/, "", $0)
      printf "%s", $0
    }
  }
' "$TMP_XML")"

if [[ -z "$BASE64_PAYLOAD" ]]; then
  echo "decoded_lines=0"
  exit 0
fi

printf '%s' "$BASE64_PAYLOAD" \
  | base64 -D \
  | sed 's/^\["//; s/"\]$//; s/","/\
/g; s/\\\\"/"/g' > "$TMP_LINES"

line_count="$(wc -l < "$TMP_LINES" | tr -d ' ')"
immediate_kana="$(rg -o 'trigger=immediate-kanaInput' "$TMP_LINES" | wc -l | tr -d ' ' || true)"
immediate_commit="$(rg -o 'trigger=immediate-commit' "$TMP_LINES" | wc -l | tr -d ' ' || true)"
immediate_post_modifier="$(rg -o 'trigger=immediate-postModifier' "$TMP_LINES" | wc -l | tr -d ' ' || true)"
async_trigger="$(rg -o 'trigger=async' "$TMP_LINES" | wc -l | tr -d ' ' || true)"
async_enqueued="$(rg -o 'refreshKeyboardStateAsync' "$TMP_LINES" | wc -l | tr -d ' ' || true)"
slow_refresh="$(rg -o 'refreshKeyboardState.*elapsedMs=' "$TMP_LINES" | wc -l | tr -d ' ' || true)"
commit_events="$(rg -o 'stage=commitReplace:start|stage=finalize:start|確定置換' "$TMP_LINES" | wc -l | tr -d ' ' || true)"
commit_replace_start="$(rg -o 'stage=commitReplace:start' "$TMP_LINES" | wc -l | tr -d ' ' || true)"
commit_finalize_start="$(rg -o 'stage=finalize:start' "$TMP_LINES" | wc -l | tr -d ' ' || true)"

printf 'decoded_lines=%s\n' "$line_count"
printf 'immediate_kana_input=%s\n' "$immediate_kana"
printf 'immediate_commit=%s\n' "$immediate_commit"
printf 'immediate_post_modifier=%s\n' "$immediate_post_modifier"
printf 'async_trigger=%s\n' "$async_trigger"
printf 'async_related_logs=%s\n' "$async_enqueued"
printf 'slow_refresh_logs=%s\n' "$slow_refresh"
printf 'commit_events=%s\n' "$commit_events"
printf 'commit_replace_start=%s\n' "$commit_replace_start"
printf 'commit_finalize_start=%s\n' "$commit_finalize_start"

echo "recent_refresh_logs="
rg -n 'trigger=immediate-|trigger=async|refreshKeyboardStateAsync|refreshKeyboardState.*elapsedMs=' "$TMP_LINES" \
  | tail -n "$TAIL_COUNT" || true

echo "recent_commit_logs="
rg -n 'stage=commitReplace:start|stage=finalize:start|確定置換' "$TMP_LINES" \
  | tail -n "$TAIL_COUNT" || true
