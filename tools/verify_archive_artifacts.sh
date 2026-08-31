#!/bin/bash
# 提出ビルド(Archive)の成果物検証。App Store 提出前に1回実行する。
#   使い方: bash tools/verify_archive_artifacts.sh [path/to/écritu.xcarchive | path/to/écritu.app] [--tag]
#   引数なし: ~/Library/Developer/Xcode/Archives から最新の écritu.xcarchive を探す
#   --tag   : 検証OKのとき submitted-<version>-<build> の git タグを打つ(追跡性の記録)
# 検査項目: バンドルID / debug.dylib等の混入 / ITSAppUsesNonExemptEncryption /
#           アイコンのアルファ / appexサイズ / 辞書sqliteがtmpと同一(=テスト済みの辞書) /
#           プロビジョニングの失効日 / gitツリーの汚れ
set -u
FAIL=0
ok()   { echo "  ✅ $1"; }
bad()  { echo "  ❌ $1"; FAIL=1; }
warn() { echo "  ⚠️  $1"; }

TARGET="${1:-}"
DO_TAG=0
for a in "$@"; do [[ "$a" == "--tag" ]] && DO_TAG=1; done
[[ "$TARGET" == "--tag" ]] && TARGET=""

if [[ -z "$TARGET" ]]; then
  TARGET=$(ls -dt "$HOME"/Library/Developer/Xcode/Archives/*/*.xcarchive 2>/dev/null | grep -i "critu" | head -1 || true)
  [[ -z "$TARGET" ]] && { echo "xcarchiveが見つかりません。パスを引数で指定してください。"; exit 1; }
fi

if [[ "$TARGET" == *.xcarchive ]]; then
  APP=$(ls -d "$TARGET"/Products/Applications/*.app 2>/dev/null | head -1)
else
  APP="$TARGET"
fi
[[ -d "$APP" ]] || { echo ".appが見つかりません: $TARGET"; exit 1; }
APPEX=$(ls -d "$APP"/PlugIns/*.appex 2>/dev/null | head -1)
echo "対象: $APP"

# 1) バンドルID
APP_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist" 2>/dev/null)
KB_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APPEX/Info.plist" 2>/dev/null)
[[ "$APP_ID" == "com.kusakabe.ecritu" ]] && ok "アプリID: $APP_ID" || bad "アプリIDが本番でない: $APP_ID"
[[ "$KB_ID" == "com.kusakabe.ecritu.keyboard" ]] && ok "拡張ID: $KB_ID" || bad "拡張IDが本番でない: $KB_ID"

# 2) デバッグ用バイナリの混入
STRAY=$(find "$APP" -name "*.debug.dylib" -o -name "__preview.dylib" 2>/dev/null)
[[ -z "$STRAY" ]] && ok "debug.dylib/__preview.dylib の混入なし" || bad "デバッグ用バイナリが混入: $STRAY"

# 3) 暗号化申告
ITS=$(/usr/libexec/PlistBuddy -c "Print ITSAppUsesNonExemptEncryption" "$APP/Info.plist" 2>/dev/null)
[[ "$ITS" == "false" ]] && ok "ITSAppUsesNonExemptEncryption = NO" || bad "ITSAppUsesNonExemptEncryption が無い/真: '$ITS'"

# 4) アイコンのアルファ(ソース資産側で検査)
ALPHA_BAD=0
for f in App/Assets.xcassets/AppIcon.appiconset/icon-*.png; do
  has=$(sips -g hasAlpha "$f" 2>/dev/null | awk '/hasAlpha/{print $2}')
  [[ "$has" == "yes" ]] && { ALPHA_BAD=1; bad "アイコンにアルファ: $f"; }
done
[[ $ALPHA_BAD -eq 0 ]] && ok "アイコン9枚ともアルファなし"

# 5) appexサイズ
if [[ -d "$APPEX" ]]; then
  SZ=$(du -sm "$APPEX" | cut -f1)
  if (( SZ < 470 )); then ok "appexサイズ ${SZ}MB (<470MB)"; else warn "appexサイズ ${SZ}MB — 想定(約434MB)より大きい"; fi
fi

# 6) 辞書がテスト済みのtmpと同一か
if [[ -f "$APPEX/kana_kanji_dictionary.sqlite" && -f tmp/kana_kanji_dictionary.sqlite ]]; then
  H1=$(shasum -a 256 "$APPEX/kana_kanji_dictionary.sqlite" | cut -d' ' -f1)
  H2=$(shasum -a 256 tmp/kana_kanji_dictionary.sqlite | cut -d' ' -f1)
  [[ "$H1" == "$H2" ]] && ok "辞書sqliteがtmpと同一(テスト済み辞書がそのまま入っている)" || bad "辞書sqliteがtmpと不一致 — テスト後に辞書が変わっている"
  ROWS=$(sqlite3 "file:$APPEX/kana_kanji_dictionary.sqlite?mode=ro&immutable=1" "SELECT count(*) FROM dictionary_entries" 2>/dev/null || echo 0)
  (( ROWS > 100000 )) && ok "辞書行数 $ROWS" || bad "辞書行数が異常: $ROWS"
fi

# 7) プロビジョニングの失効(実機/配布ビルドのみ存在)
PROF="$APP/embedded.mobileprovision"
if [[ -f "$PROF" ]]; then
  EXP=$(security cms -D -i "$PROF" 2>/dev/null | plutil -extract ExpirationDate raw -o - - 2>/dev/null)
  ok "プロビジョニング失効日: ${EXP:-不明}"
else
  warn "embedded.mobileprovision なし(simulatorビルド?)"
fi

# 8) gitツリー
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
  warn "gitツリーに未コミット変更あり(提出物とコミットの対応が曖昧になります)"
else
  ok "gitツリーはクリーン"
fi

VER=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Info.plist" 2>/dev/null)
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Info.plist" 2>/dev/null)
echo "バージョン: $VER ($BUILD)  コミット: $(git rev-parse --short HEAD 2>/dev/null)"

if [[ $FAIL -eq 0 && $DO_TAG -eq 1 ]]; then
  TAG="submitted-$VER-$BUILD"
  git tag -f "$TAG" && echo "  🏷  git tag $TAG を作成(追跡性の記録)"
fi

if [[ $FAIL -eq 0 ]]; then echo "== 検証OK =="; else echo "== 検証NG(上の❌を解消してください) =="; exit 1; fi
