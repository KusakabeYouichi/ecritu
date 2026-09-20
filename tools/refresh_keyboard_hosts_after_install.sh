#!/usr/bin/env bash
# 実機への再インストール(⌘R)に伴う「Apple純正キーボードが1回出る」事象の予防。
#
# 背景(2026-08-14 の iOS 統合ログで実測):
#   再インストールで旧ビルドのキーボード拡張プロセスが SIGKILL されると、直前まで
#   écritu をホストしていた常駐アプリ(メモ/メッセージ/Spotlight 等)は旧プラグイン
#   UUID のキャッシュを持ったまま生き残る。その状態での最初のキーボード要求は
#   launch failed → PKPlugIn must have pid! → no such plugin (uuid not found) で
#   失敗し、iOS はサードパーティ唯一の環境でも純正キーボードへ silent フォール
#   バックする(次の要求で pkd が新 UUID を解決して自己修復する=1回きり)。
#
#   ホストプロセス側のキャッシュが原因なのでアプリ側のコードでは防げない。
#   代わりにインストール前後でホストを畳んでおけば、次回起動時に新しい登録を
#   引き直すため事象は発生しない。Xcode スキームの Run pre-action から呼ぶ想定
#   (手動実行も可: tools/refresh_keyboard_hosts_after_install.sh [デバイスUUID])。
#
# 失敗しても ⌘R を妨げないよう、常に exit 0 で終える。
set -uo pipefail

# Xcode pre-action 経由(ビルド設定あり)でシミュレータ向けのときは何もしない。
if [[ -n "${PLATFORM_NAME:-}" && "${PLATFORM_NAME}" != iphoneos* ]]; then
  echo "[keyboard-hosts] skip (PLATFORM_NAME=${PLATFORM_NAME})"
  exit 0
fi

# écritu をホストしがちな常駐アプリ(実測でstale参照が確認できたもの)。
HOST_PATTERNS=(
  "MobileNotes.app/MobileNotes"
  "MobileSMS.app/MobileSMS"
  "Spotlight.app/Spotlight"
)

# 実行記録(スキームの pre-action は出力を捨てるので、効いたかどうかをここに残す。2026-09-20)
LOG_DIR="${HOME}/Library/Logs/ecritu"
mkdir -p "${LOG_DIR}" 2>/dev/null && exec > >(tee -a "${LOG_DIR}/keyboard-hosts.log") 2>&1
echo "[keyboard-hosts] $(date '+%Y-%m-%d %H:%M:%S') start"
DEVICE="${1:-}"
if [[ -z "${DEVICE}" ]]; then
  # 実機の行だけを見る。以前は UUID 形式(8-4-4-4-12)で拾っていたため、実機の UDID
  # (8-16 形式 00008120-…)に合わず、起動中のシミュレーター(connected 表示)を掴んで
  # 実機のホストが 1 つも終了されていなかった(2026-09-20 統合ログ: メモが旧 UUID で
  # 「no such plugin (uuid not found)」×3→純正フォールバック)。
  DEVICE=$(xcrun devicectl list devices 2>/dev/null \
    | awk '/connected/ && /physical/ {
        for (i = 1; i <= NF; i++)
          if ($(i + 1) == "(UDID)") { print $i; exit }
      }')
fi
if [[ -z "${DEVICE}" ]]; then
  echo "[keyboard-hosts] skip (no connected device found via devicectl)"
  exit 0
fi

if ! PROCESSES=$(xcrun devicectl device info processes --device "${DEVICE}" 2>&1); then
  echo "[keyboard-hosts] skip (process listing failed for ${DEVICE}: ${PROCESSES:0:120})"
  exit 0
fi

echo "[keyboard-hosts] device=${DEVICE}"
for pattern in "${HOST_PATTERNS[@]}"; do
  found=0
  while IFS= read -r pid; do
    [[ -n "${pid}" ]] || continue
    found=1
    if [[ -n "${KEYBOARD_HOSTS_DRY_RUN:-}" ]]; then
      echo "[keyboard-hosts] dry-run: would terminate ${pattern##*/} (pid ${pid})"
    elif xcrun devicectl device process terminate --device "${DEVICE}" --pid "${pid}" >/dev/null 2>&1; then
      echo "[keyboard-hosts] terminated ${pattern##*/} (pid ${pid})"
    else
      echo "[keyboard-hosts] terminate failed ${pattern##*/} (pid ${pid})"
    fi
  done < <(printf '%s\n' "${PROCESSES}" | awk -v p="${pattern}" '$2 ~ (p "$") { print $1 }')
  if [[ "${found}" == "0" ]]; then
    echo "[keyboard-hosts] ${pattern##*/} not running"
  fi
done

exit 0
