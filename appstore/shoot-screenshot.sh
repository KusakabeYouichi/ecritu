#!/bin/bash
# App Store スクリーンショット 1 枚の撮影(無操作手順。appstore/screenshots-plan.md)。
# 前提: appstore/apply-screenshot-hooks.py でフックを入れ、対象シミュレーター向けに Debug ビルド済み。
# 使い方: appstore/shoot-screenshot.sh <シミュレーターUDID> <出力の接頭辞> "<key=type:value> ..."
#   type は s=string / i=integer / b=bool / d=delete。App Group の plist に停止中に書く(起動中は cfprefsd が上書きする)。
#   拡張の装着失敗に備え web クリップを 2 回起動し、<接頭辞>_1.png と _2.png を撮る。ダイナミックアイランドが
#   写ることがあるので、写ったら少し待って `xcrun simctl io <UDID> screenshot` で撮り足す
set -u
UD=$1
OUT=$2
SEEDS=${3:-}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# é は合成形・分解形の揺れでグロブが外れるので使わない
APP=$(ls -d ~/Library/Developer/Xcode/DerivedData/*critu-*/Build/Products/Debug-iphonesimulator/*critu.app | head -1)

xcrun simctl boot "$UD" 2>/dev/null
xcrun simctl bootstatus "$UD" -b >/dev/null 2>&1
GROUP=$(xcrun simctl get_app_container "$UD" jp.or.pleiades.merope.ecritu group.jp.or.pleiades.merope.ecritu)
G="$GROUP/Library/Preferences/group.jp.or.pleiades.merope.ecritu.plist"

# 撮影用ページの配信(web クリップが http://127.0.0.1:8765/capture-page.html を開く)
if ! lsof -i :8765 >/dev/null 2>&1; then
  (cd "$ROOT/appstore" && nohup python3 -m http.server 8765 >/dev/null 2>&1 &)
fi

xcrun simctl shutdown "$UD" 2>/dev/null
sleep 4
for k in screenshotScript screenshot_inputMode screenshot_emojiSubmode screenshot_emojiCategory screenshot_emojiBubble \
         screenshot_kaomojiCategory screenshot_kaomojiPrefix screenshot_kaomojiReading screenshot_numberBuffer screenshot_flickKey \
         keyboardDiagnosticsSessionOwnerToken keyboardDiagnosticsSessionActive; do
  /usr/libexec/PlistBuddy -c "Delete :$k" "$G" 2>/dev/null
done
for seed in $SEEDS; do
  key=${seed%%=*}; rest=${seed#*=}; type=${rest%%:*}; value=${rest#*:}
  case $type in
    s) t=string ;; i) t=integer ;; b) t=bool ;;
    d) /usr/libexec/PlistBuddy -c "Delete :$key" "$G" 2>/dev/null; continue ;;
  esac
  /usr/libexec/PlistBuddy -c "Delete :$key" "$G" 2>/dev/null
  /usr/libexec/PlistBuddy -c "Add :$key $t $value" "$G"
done

xcrun simctl boot "$UD"
xcrun simctl bootstatus "$UD" -b >/dev/null 2>&1
xcrun simctl install "$UD" "$APP"
xcrun simctl status_bar "$UD" override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 >/dev/null
for i in 1 2; do
  xcrun simctl terminate "$UD" com.apple.webapp 2>/dev/null
  sleep 3
  xcrun simctl launch "$UD" com.apple.webapp >/dev/null 2>&1
  sleep 26
  xcrun simctl io "$UD" screenshot "${OUT}_$i.png" >/dev/null 2>&1
done
echo "shot $OUT done"
