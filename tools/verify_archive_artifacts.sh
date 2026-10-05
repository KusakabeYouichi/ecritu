#!/bin/bash
# 提出ビルド(Archive)の成果物検証。App Store 提出前に1回実行する。
#   使い方: bash tools/verify_archive_artifacts.sh [path/to/écritu.xcarchive | path/to/écritu.app | path/to/écritu.ipa] [--tag]
#   引数なし: ~/Library/Developer/Xcode/Archives から最新の écritu.xcarchive を探す
#   --tag   : 検証OKのとき submitted-<version>-<build> の git タグを打つ(追跡性の記録)
#   モードは 3 つ(3347)。指定なし = App Store 審査用で、すべて厳しく見る。
#   --testflight : TestFlight 配布用(Release 構成)。出荷前診断(ECRITU_PRERELEASE_DIAGNOSTICS=1)を ❌ でなく ⚠️ にし、
#              タグは testflight-<version>-<build> にする(App Store 提出ではこの指定を付けない)
#   --testflight-debug : TestFlight 配布用(Debug 構成。テスターから診断ログを取る版、3312〜)。上に加えて、
#              Debug 構成なら必ず入る DEBUG 専用の文字列と、DEBUG 専用コード由来の「必要な理由 API」を ⚠️ にする。
#              逆に DEBUG 専用の文字列が無ければ ❌(Release で作ったのに指定を取り違えた)。タグは testflight-debug-<version>-<build>
# 検査項目: バンドルID / debug.dylib等の混入 / ITSAppUsesNonExemptEncryption /
#           アイコンのアルファ / appexサイズ / 辞書sqliteがtmpと同一(=テスト済みの辞書) /
#           プロビジョニング(失効日・配布用か) / get-task-allow / 出荷前診断フラグ(バイナリで判定) /
#           DEBUG 専用・撮影用の文字列の残留 / APP_STORE_BLOCKER の印 / 必要な理由 API の申告 / dSYM / gitツリーの汚れ
# xcarchive と エクスポート後(.app/.ipa)の違い: xcarchive の中身は開発用プロファイル+get-task-allow=true で
# 署名されており、エクスポート時に配布用で署名し直される。署名系の検査(get-task-allow・配布プロファイル)は
# エクスポート後の成果物を渡したときだけ ❌ にし、xcarchive では参考表示にとどめる(3307)
set -u
FAIL=0
ok()   { echo "  ✅ $1"; }
bad()  { echo "  ❌ $1"; FAIL=1; }
warn() { echo "  ⚠️  $1"; }

TARGET="${1:-}"
DO_TAG=0
TESTFLIGHT=0
DEBUG_BUILD=0
for a in "$@"; do
  [[ "$a" == "--tag" ]] && DO_TAG=1
  [[ "$a" == "--testflight" ]] && TESTFLIGHT=1
  [[ "$a" == "--testflight-debug" ]] && { TESTFLIGHT=1; DEBUG_BUILD=1; }
done
[[ "$TARGET" == --* ]] && TARGET=""
if [[ $DEBUG_BUILD -eq 1 ]]; then MODE_LABEL="TestFlight(Debug 構成)"
elif [[ $TESTFLIGHT -eq 1 ]]; then MODE_LABEL="TestFlight(Release 構成)"
else MODE_LABEL="App Store 審査用"; fi
echo "モード: $MODE_LABEL"

if [[ -z "$TARGET" ]]; then
  TARGET=$(ls -dt "$HOME"/Library/Developer/Xcode/Archives/*/*.xcarchive 2>/dev/null | grep -i "critu" | head -1 || true)
  [[ -z "$TARGET" ]] && { echo "xcarchiveが見つかりません。パスを引数で指定してください。"; exit 1; }
fi

TARGET="${TARGET%/}"   # 末尾の / を落とす(ls -F やタブ補完由来。*.xcarchive の判定を外さないため)
IS_ARCHIVE=0
UNZIP_DIR=""
if [[ "$TARGET" == *.xcarchive ]]; then
  IS_ARCHIVE=1
  APP=$(ls -d "$TARGET"/Products/Applications/*.app 2>/dev/null | head -1)
elif [[ "$TARGET" == *.ipa ]]; then
  UNZIP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/ecritu-verify.XXXXXX")
  trap 'rm -rf "$UNZIP_DIR"' EXIT
  unzip -q "$TARGET" -d "$UNZIP_DIR" || { echo ".ipa を展開できません: $TARGET"; exit 1; }
  APP=$(ls -d "$UNZIP_DIR"/Payload/*.app 2>/dev/null | head -1)
else
  APP="$TARGET"
fi
[[ -d "$APP" ]] || { echo ".appが見つかりません: $TARGET"; exit 1; }
APPEX=$(ls -d "$APP"/PlugIns/*.appex 2>/dev/null | head -1)
echo "対象: $APP"
APP_BIN="$APP/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist" 2>/dev/null)"
APPEX_BIN=""
[[ -d "$APPEX" ]] && APPEX_BIN="$APPEX/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APPEX/Info.plist" 2>/dev/null)"

# 1) バンドルID。期待値はリテラルでなく xcconfig から解決する(Config/Signing.local.xcconfig の
#    上書きを尊重。2026-09-11 に既定の com.kusakabe.ecritu が取得不能になり jp.or.pleiades.merope.ecritu
#    へ切り替えたため。notes/identifiers.md §8)
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
resolve_xcconfig_value() {
  local key="$1" value=""
  for f in "$ROOT_DIR/Config/Edition.xcconfig" "$ROOT_DIR/Config/Signing.local.xcconfig"; do
    [[ -f "$f" ]] || continue
    local v
    v=$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$f" | tail -1 | sed -E 's/^[^=]*=[[:space:]]*//; s/[[:space:]]*$//')
    [[ -n "$v" ]] && value="$v"
  done
  echo "$value"
}
EXPECTED_APP_ID=$(resolve_xcconfig_value ECRITU_APP_BUNDLE_IDENTIFIER)
[[ -z "$EXPECTED_APP_ID" ]] && EXPECTED_APP_ID="jp.or.pleiades.merope.ecritu"
EXPECTED_KB_ID="${EXPECTED_APP_ID}.keyboard"
APP_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist" 2>/dev/null)
KB_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APPEX/Info.plist" 2>/dev/null)
[[ "$APP_ID" == "$EXPECTED_APP_ID" ]] && ok "アプリID: $APP_ID" || bad "アプリIDが設定と不一致: $APP_ID(期待 $EXPECTED_APP_ID)"
[[ "$KB_ID" == "$EXPECTED_KB_ID" ]] && ok "拡張ID: $KB_ID" || bad "拡張IDが設定と不一致: $KB_ID(期待 $EXPECTED_KB_ID)"

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
  # 3302〜3303 で辞書を 441→81MB(出どころ・語コストを列に、全表 WITHOUT ROWID)、appex 約 463→103MB。
  # 元の大きさに戻っていたら気づけるように
  if (( SZ < 130 )); then ok "appexサイズ ${SZ}MB (<130MB)"; else warn "appexサイズ ${SZ}MB — 想定(約103MB)より大きい"; fi
fi

# 6) 辞書がテスト済みのtmpと同一か
if [[ -f "$APPEX/kana_kanji_dictionary.sqlite" && -f tmp/kana_kanji_dictionary.sqlite ]]; then
  H1=$(shasum -a 256 "$APPEX/kana_kanji_dictionary.sqlite" | cut -d' ' -f1)
  H2=$(shasum -a 256 tmp/kana_kanji_dictionary.sqlite | cut -d' ' -f1)
  [[ "$H1" == "$H2" ]] && ok "辞書sqliteがtmpと同一(テスト済み辞書がそのまま入っている)" || bad "辞書sqliteがtmpと不一致 — テスト後に辞書が変わっている"
  ROWS=$(sqlite3 "file:$APPEX/kana_kanji_dictionary.sqlite?mode=ro&immutable=1" "SELECT count(*) FROM dictionary_entries" 2>/dev/null || echo 0)
  (( ROWS > 100000 )) && ok "辞書行数 $ROWS" || bad "辞書行数が異常: $ROWS"
  # 病名(references/médicaux.plist)は MEDIS の使用許諾が下りるまで配らない。病名にしか無い語を目印に見る
  MED=$(sqlite3 "file:$APPEX/kana_kanji_dictionary.sqlite?mode=ro&immutable=1" \
    "SELECT count(*) FROM dictionary_entries WHERE candidate IN ('女性骨盤炎','外陰腟炎','クラミジア性','人工授精後')" 2>/dev/null || echo 0)
  (( MED == 0 )) && ok "病名(médicaux)は入っていない" || bad "病名(médicaux)が辞書に入っている — 使用許諾前は ECRITU_INCLUDE_MEDICAUX を外してビルドし直す"
fi

# 7) プロビジョニング(実機/配布ビルドのみ存在)。失効日に加えて、配布用かどうか(3307):
#    App Store/TestFlight 用のプロファイルには ProvisionedDevices が無く、get-task-allow も false。
#    xcarchive の中身は開発用のまま(エクスポートで差し替わる)なので参考表示にとどめる
PROF="$APP/embedded.mobileprovision"
if [[ -f "$PROF" ]]; then
  PROF_PLIST=$(security cms -D -i "$PROF" 2>/dev/null)
  EXP=$(echo "$PROF_PLIST" | plutil -extract ExpirationDate raw -o - - 2>/dev/null)
  PROF_NAME=$(echo "$PROF_PLIST" | plutil -extract Name raw -o - - 2>/dev/null)
  ok "プロビジョニング失効日: ${EXP:-不明}(${PROF_NAME:-名前不明})"
  if echo "$PROF_PLIST" | plutil -extract ProvisionedDevices json -o - - >/dev/null 2>&1; then
    if [[ $IS_ARCHIVE -eq 1 ]]; then
      echo "  ℹ️  プロファイルは開発用(端末限定)。xcarchive なので想定どおり — エクスポート後の .ipa を渡すと配布用か検査する"
    else
      bad "プロファイルが開発用(ProvisionedDevices あり)。App Store Connect 用のエクスポート(destination=upload/export, method app-store)でない"
    fi
  else
    ok "プロファイルは配布用(端末限定なし)"
  fi
else
  warn "embedded.mobileprovision なし(simulatorビルド?)"
fi

# 7b) get-task-allow(デバッガー接続許可)。配布物では両バイナリとも false でなければならない(3307)
check_get_task_allow() {
  local bundle="$1" label="$2"
  [[ -d "$bundle" ]] || return
  local value
  value=$(codesign -d --entitlements :- "$bundle" 2>/dev/null | plutil -extract get-task-allow raw -o - - 2>/dev/null || echo "なし")
  if [[ "$value" == "true" ]]; then
    if [[ $IS_ARCHIVE -eq 1 ]]; then
      echo "  ℹ️  $label: get-task-allow=true(xcarchive の中身は開発用署名のまま。エクスポートで false になる)"
    else
      bad "$label: get-task-allow=true のまま配布物に残っている(デバッガー接続可)。配布用に署名し直す"
    fi
  else
    ok "$label: get-task-allow=${value}"
  fi
}
check_get_task_allow "$APP" "App"
check_get_task_allow "$APPEX" "KeyboardExtension"

# 9) 出荷前診断の組み込み(ECRITU_PRERELEASE_DIAGNOSTICS)。提出ビルドは 0 でなければならない。
#    1 のままだと診断カウンターがバイナリに入る(削除キーの黄/橙と数値バッジは 3321 から DEBUG 専用)。
#    判定は**バイナリの文字列**で行なう(3307。以前は Config/Edition.xcconfig の文字列を見ていたため、
#    古いアーカイブ・Signing.local の上書き・アーカイブ後の編集をすり抜けた)。
#    keyboardDiagnosticsWriteProbe は #if ECRITU_PRERELEASE_DIAGNOSTICS の中にしか無いリテラル
#    (KeyboardViewController+Diagnostics.swift recordKeyboardDiagnosticsAppGroupHealth)
DIAG_HINT=$(resolve_xcconfig_value ECRITU_PRERELEASE_DIAGNOSTICS)
if [[ -n "$APPEX_BIN" && -f "$APPEX_BIN" ]]; then
  if strings "$APPEX_BIN" 2>/dev/null | grep -q "^keyboardDiagnosticsWriteProbe$"; then
    if [[ $TESTFLIGHT -eq 1 ]]; then
      warn "出荷前診断がバイナリに組み込まれている(xcconfig の現在値=${DIAG_HINT:-?})。TestFlight 配布ではこのまま。App Store 提出では 0 にして再アーカイブ"
    else
      bad "出荷前診断がバイナリに組み込まれている(xcconfig の現在値=${DIAG_HINT:-?})。Config/Edition.xcconfig を 0 にして再アーカイブしてください"
    fi
  else
    ok "出荷前診断はバイナリに組み込まれていない"
    [[ "$DIAG_HINT" != "0" ]] && warn "ただし xcconfig の現在値は ${DIAG_HINT:-?}(このアーカイブは別の値で作られている)"
  fi
else
  warn "拡張のバイナリが見つからず、出荷前診断の有無を判定できない"
fi

# 9b) DEBUG 専用・撮影用の文字列が配布バイナリに残っていないか(3307)。どれも #if DEBUG の中か、
#     撮影時だけ入れる一時フック(appstore/apply-screenshot-hooks.py)にしか存在しないリテラル
check_debug_only_strings() {
  local bin="$1" label="$2"
  [[ -n "$bin" && -f "$bin" ]] || return
  local syms hits
  syms=$(strings "$bin" 2>/dev/null)
  # 文字列リテラルそのものに合わせる(行頭固定)。App 側には同名のプロパティのシンボル
  # (_keyboardConversionLastTrace)が #if DEBUG の外にもあり、部分一致だと誤検知する
  hits=$(echo "$syms" | grep -E "^(MULTITRACE|SINGLETRACE|screenshotScript$|keyboardConversionLastTrace$|.*撮影用の一時フック)" | sort -u | head -5 | tr '\n' ' ')
  # 撮影用の一時フックはどのモードでも配布してはいけない
  local hookHits
  hookHits=$(echo "$syms" | grep -E "^(screenshotScript$|.*撮影用の一時フック)" | sort -u | head -3 | tr '\n' ' ')
  if [[ $DEBUG_BUILD -eq 1 ]]; then
    if [[ -n "$hookHits" ]]; then
      bad "$label: 撮影用の文字列がバイナリに残っている: $hookHits"
    elif [[ -n "$hits" ]]; then
      warn "$label: DEBUG 専用の文字列あり(Debug 構成なので想定どおり): $hits"
    else
      bad "$label: Debug 構成のはずが DEBUG 専用の文字列が無い(Release で作った版に --testflight-debug を付けていないか)"
    fi
  elif [[ -n "$hits" ]]; then
    bad "$label: DEBUG 専用/撮影用の文字列がバイナリに残っている: $hits"
  else
    ok "$label: DEBUG 専用/撮影用の文字列なし"
  fi
}
check_debug_only_strings "$APP_BIN" "App"
check_debug_only_strings "$APPEX_BIN" "KeyboardExtension"

# 9c) 撮影用の一時フックがソースツリーに残っていないか(3307)。git が clean でもコミットされていれば残るので ❌
HOOKS=$(grep -rln "撮影用の一時フック" App KeyboardExtension 2>/dev/null || true)
if [[ -n "$HOOKS" ]]; then
  bad "撮影用の一時フックがソースに残っている: $(echo "$HOOKS" | tr '\n' ' ')(git checkout -- KeyboardExtension/ で外す)"
else
  ok "撮影用の一時フックはソースに無い"
fi

# 9d) dSYM(クラッシュレポートの記号化に要る。xcarchive のみ)
if [[ $IS_ARCHIVE -eq 1 ]]; then
  DSYM_COUNT=$(ls -d "$TARGET"/dSYMs/*.dSYM 2>/dev/null | wc -l | tr -d ' ')
  (( DSYM_COUNT >= 2 )) && ok "dSYM ${DSYM_COUNT} 個(App と拡張)" || warn "dSYM が ${DSYM_COUNT} 個しかない(DEBUG_INFORMATION_FORMAT を確認)"
fi

# 10) 提出前に解消すべき印(APP_STORE_BLOCKER)。個別の一時的な仕掛け用
BLOCKERS=$(grep -rn "APP_STORE_BLOCKER:" App KeyboardExtension 2>/dev/null || true)
if [[ -n "$BLOCKERS" ]]; then
  bad "提出前に解消する印(APP_STORE_BLOCKER)が残っています:"
  echo "$BLOCKERS" | sed 's/^/      /'
else
  ok "APP_STORE_BLOCKER の印なし"
fi

# 11) 「必要な理由」の申告が要る API のシンボルが、PrivacyInfo.xcprivacy に申告の無い区分で残っていないか
#     (ITMS-91053。2026-10-02 に DEBUG 専用の計測が ProcessInfo.systemUptime を Release に残していたのを検出)
check_required_reason_apis() {
  local bin="$1" manifest="$2" label="$3"
  [[ -f "$bin" ]] || { warn "$label: バイナリが見つからない"; return; }
  local syms; syms=$(strings "$bin" 2>/dev/null)
  # 区分:シンボルの正規表現(macOS の bash 3.2 には連想配列が無い)
  local entry cat pattern hits
  for entry in \
    "SystemBootTime:systemUptime|mach_absolute_time|mach_continuous_time" \
    "DiskSpace:statfs|statvfs|volumeAvailableCapacity|volumeTotalCapacity" \
    "FileTimestamp:creationDate|modificationDate|contentModificationDateKey|creationDateKey|fileModificationDate" \
    "ActiveKeyboards:activeInputModes"; do
    cat=${entry%%:*}; pattern=${entry#*:}
    hits=$(echo "$syms" | grep -E "^(${pattern})$" | sort -u | tr '\n' ' ')
    [[ -n "$hits" ]] || continue
    if [[ -f "$manifest" ]] && grep -q "NSPrivacyAccessedAPICategory$cat" "$manifest"; then
      ok "$label: $cat の API($hits)を使い、申告あり"
    elif [[ $DEBUG_BUILD -eq 1 ]]; then
      # DEBUG 専用の計測(触れてからの遅れ等)が使う。TestFlight は受け付けられる(3312/3319 で実績)。
      # Release 構成で同じ ❌ が出たら審査で止まるので、そちらでは ❌ のまま
      warn "$label: $cat の API($hits)の申告が無い(Debug 構成の DEBUG 専用コード由来。App Store 審査用の Release 構成では ❌)"
    else
      bad "$label: $cat の API($hits)を使うのに PrivacyInfo.xcprivacy に申告が無い"
    fi
  done
}
check_required_reason_apis "$APP/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist" 2>/dev/null)" "$APP/PrivacyInfo.xcprivacy" "App"
if [[ -d "$APPEX" ]]; then
  check_required_reason_apis "$APPEX/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APPEX/Info.plist" 2>/dev/null)" "$APPEX/PrivacyInfo.xcprivacy" "KeyboardExtension"
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
  [[ $TESTFLIGHT -eq 1 ]] && TAG="testflight-$VER-$BUILD"
  [[ $DEBUG_BUILD -eq 1 ]] && TAG="testflight-debug-$VER-$BUILD"
  git tag -f "$TAG" && echo "  🏷  git tag $TAG を作成(追跡性の記録)"
fi

if [[ $FAIL -eq 0 ]]; then echo "== 検証OK =="; else echo "== 検証NG(上の❌を解消してください) =="; exit 1; fi
