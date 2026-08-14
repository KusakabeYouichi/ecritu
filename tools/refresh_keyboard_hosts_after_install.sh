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

DEVICE="${1:-}"
if [[ -z "${DEVICE}" ]]; then
  DEVICE=$(xcrun devicectl list devices 2>/dev/null \
    | awk '/connected/ {
        for (i = 1; i <= NF; i++)
          if ($i ~ /^[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}$/) { print $i; exit }
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
    if xcrun devicectl device process terminate --device "${DEVICE}" --pid "${pid}" >/dev/null 2>&1; then
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
