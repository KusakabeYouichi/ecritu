#!/usr/bin/env bash
# Mac の入力メソッド(ecritu.app)をテスターへ配る .pkg にする(Developer ID 署名 + 公証)。
# 使い方:
#   bash tools/package_mac_input_method.sh [--unsigned] [--notarize <notarytool のキーチェーンプロファイル名>]
#   bash tools/package_mac_input_method.sh --check-only <ecritu.app の場所>
#
#   (指定なし)   Release でビルド → 検査 → Developer ID で署名 → pkg を作る(公証には出さない)
#   --unsigned   署名なしで pkg を作る(手元の試し用。配ってはいけない)
#   --notarize   署名した pkg を Apple の公証へ提出し、通ったらステープルする
#   --check-only 病名語彙などの混入検査だけを、指定の .app に対して行なう
#
# 資格情報(パスワード・API キー)は受け取らない・表示しない。--notarize はキーチェーンプロファイルの名前だけ受け取る。
# Apple のサーバーへ出る操作: 署名のタイムスタンプ取得(--unsigned 以外)と、公証の提出(--notarize のときだけ)
set -euo pipefail

BUNDLE_ID="jp.or.pleiades.merope.inputmethod.ecritu"
PKG_ID="${BUNDLE_ID}.pkg"
APP_NAME="ecritu.app"
# 辞書 sqlite の大きさの下限(仮置きの辞書のまま配らないための検査)
MIN_SQLITE_BYTES=$((50 * 1024 * 1024))
# 病名語彙にしか無い語の目印(tools/verify_archive_artifacts.sh と同じ語。これ以外の病名語彙は書かない)
MEDICAUX_MARKERS=('女性骨盤炎' '外陰腟炎' 'クラミジア性' '人工授精後')
# tools/refresh_simulator_dictionary_on_build.sh がバンドルへ複製する 10 ファイル(tmp/ の同名ファイルと同一であるべきもの)
COPIED_FILES=(
  "ÉcrituSecondVocab.json"
  "ÉcrituSecondVocab.eccs"
  "InitialAjoutVocabMigration.json"
  "InitialMiscVocabMigration.json"
  "InitialSupprVocabMigration.json"
  "InitialSupprHiddenVocabMigration.json"
  "InitialSupprHiddenNounVocabMigration.json"
  "kana_kanji_dictionary.sqlite"
  "EmojiReadingVocab.json"
  "LatinSuggestionSupplemental.txt"
)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  echo "使い方:"
  echo "  bash tools/package_mac_input_method.sh [--unsigned] [--notarize <notarytool のキーチェーンプロファイル名>]"
  echo "  bash tools/package_mac_input_method.sh --check-only <$APP_NAME の場所>"
  echo "  --unsigned と --notarize は同時に指定できません"
}

# ---- 検査 ----------------------------------------------------------------

# 検査の失敗を貯めて、最後にまとめて出す
CHECK_FAILURES=()
fail_check() { CHECK_FAILURES+=("$1"); echo "  NG: $1"; }
pass_check() { echo "  OK: $1"; }

# .app の中身を検査する。外れた内容は全部出し、1 つでも外れたら 1 を返す
# $1: .app のパス   $2: tmp/ と同一かの検査をするなら 1
check_app_contents() {
  local app="$1" compare_tmp="${2:-1}"
  local res="$app/Contents/Resources"
  CHECK_FAILURES=()
  echo "検査: $app"

  # Info.plist の CFBundleIdentifier
  local id
  id="$(plutil -extract CFBundleIdentifier raw -o - "$app/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$id" == "$BUNDLE_ID" ]]; then pass_check "CFBundleIdentifier = $id"; else fail_check "CFBundleIdentifier が想定と違う: '${id}'(想定 $BUNDLE_ID)"; fi

  # 辞書 sqlite: 大きさと病名語彙の目印(運び手を直接見る)
  local sqlite="$res/kana_kanji_dictionary.sqlite"
  if [[ ! -f "$sqlite" ]]; then
    fail_check "辞書 sqlite が入っていない: $sqlite"
  else
    local size
    size="$(stat -f%z "$sqlite")"
    if (( size >= MIN_SQLITE_BYTES )); then pass_check "辞書 sqlite の大きさ ${size} バイト(50MB 以上)"; else fail_check "辞書 sqlite が小さすぎる: ${size} バイト(50MB 未満)"; fi
    local in_list="" w
    for w in "${MEDICAUX_MARKERS[@]}"; do in_list+="${in_list:+,}'$w'"; done
    local hits
    if hits="$(sqlite3 "file:$sqlite?mode=ro&immutable=1" "SELECT count(*) FROM dictionary_entries WHERE candidate IN ($in_list)" 2>/dev/null)"; then
      if [[ "$hits" == "0" ]]; then pass_check "辞書 sqlite に病名語彙の目印の語が無い"; else fail_check "辞書 sqlite に病名語彙の目印の語が ${hits} 件ある"; fi
    else
      fail_check "辞書 sqlite を問い合わせできない(壊れているか、dictionary_entries が無い)"
    fi
  fi

  # 補助語彙(圧縮形式)に目印の語のバイト列が無い
  local eccs="$res/ÉcrituSecondVocab.eccs"
  if [[ ! -f "$eccs" ]]; then
    fail_check "ÉcrituSecondVocab.eccs が入っていない"
  else
    local bad=0
    for w in "${MEDICAUX_MARKERS[@]}"; do
      if LC_ALL=C grep -q -F -- "$w" "$eccs"; then bad=1; fi
    done
    if (( bad == 0 )); then pass_check "ÉcrituSecondVocab.eccs に病名語彙の目印の語が無い"; else fail_check "ÉcrituSecondVocab.eccs に病名語彙の目印の語のバイト列がある"; fi
  fi

  # 複製された 10 ファイルが tmp/ の同名ファイルと同一(ビルドの途中で tmp/ が変わっていない)
  if [[ "$compare_tmp" == "1" ]]; then
    local f h1 h2 mismatch=0
    for f in "${COPIED_FILES[@]}"; do
      if [[ ! -f "$res/$f" ]]; then fail_check "バンドルに無い: $f"; mismatch=1; continue; fi
      if [[ ! -f "$ROOT_DIR/tmp/$f" ]]; then fail_check "tmp/ に無い: $f"; mismatch=1; continue; fi
      h1="$(shasum -a 256 "$res/$f" | cut -d' ' -f1)"
      h2="$(shasum -a 256 "$ROOT_DIR/tmp/$f" | cut -d' ' -f1)"
      if [[ "$h1" != "$h2" ]]; then fail_check "tmp/ の同名ファイルと内容が違う: $f"; mismatch=1; fi
    done
    if (( mismatch == 0 )); then pass_check "複製された 10 ファイルが tmp/ と同一"; fi
  fi

  if (( ${#CHECK_FAILURES[@]} > 0 )); then
    echo "検査に失敗: ${#CHECK_FAILURES[@]} 件"
    return 1
  fi
  echo "検査に通りました"
}

# ---- 証明書 ----------------------------------------------------------------

# `security find-identity -v` の出力(文字列)を受け、Developer ID の 2 つの名前を探す。
# 標準出力: 1 行目 = Application の名前、2 行目 = Installer の名前。無いほうは空行。両方あれば 0、どちらか無ければ 1
find_developer_id_identities() {
  local listing="$1" team="$2"
  local app inst
  app="$(printf '%s\n' "$listing" | sed -n 's/.*"\(Developer ID Application: .*('"$team"')\)".*/\1/p' | head -n 1)"
  inst="$(printf '%s\n' "$listing" | sed -n 's/.*"\(Developer ID Installer: .*('"$team"')\)".*/\1/p' | head -n 1)"
  printf '%s\n%s\n' "$app" "$inst"
  [[ -n "$app" && -n "$inst" ]]
}

print_certificate_howto() {
  echo "  作り方: [Xcode] > [Settings] > [Accounts] でチームを選び、[Manage Certificates…] の [+] から"
  echo "          『Developer ID Application』と『Developer ID Installer』の 2 つを作ってください(アカウントの持ち主の権限が要ります)。"
}

# ---- 自己検査(Release の実行ファイルを直接起動して、起動時のログ 3 行を見る) -----------------

run_self_check() {
  local exe="$1" log="$2"
  : > "$log"
  "$exe" > "$log" 2>&1 &
  local pid=$!
  local i ok=0
  for ((i = 0; i < 40; i++)); do   # 最長 20 秒
    if [[ "$(grep -c '自己検査' "$log" || true)" -ge 3 ]]; then ok=1; break; fi
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.5
  done
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  echo "  起動時のログ:"
  grep '自己検査' "$log" | sed 's/^/    /' || true
  if (( ok == 0 )); then echo "  NG: 自己検査のログ 3 行が出なかった(ログ全体: $log)"; return 1; fi
  if grep -q '自己検査.*失敗' "$log"; then echo "  NG: 自己検査に失敗があった(ログ全体: $log)"; return 1; fi
  echo "  OK: 自己検査 3 行とも成功"
}

# ---- 本体 ------------------------------------------------------------------

main() {
  local unsigned=0 notarize_profile="" check_only_app="" have_check_only=0
  while (( $# > 0 )); do
    case "$1" in
      --unsigned) unsigned=1; shift ;;
      --notarize)
        if (( $# < 2 )) || [[ "$2" == --* ]]; then usage; exit 1; fi
        notarize_profile="$2"; shift 2 ;;
      --check-only)
        if (( $# < 2 )); then usage; exit 1; fi
        have_check_only=1; check_only_app="${2%/}"; shift 2 ;;
      *) usage; exit 1 ;;
    esac
  done

  if (( have_check_only )); then
    if [[ ! -f "$check_only_app/Contents/Info.plist" ]]; then echo "$APP_NAME ではありません: $check_only_app"; usage; exit 1; fi
    # 仮の .app の検査にも使うので、tmp/ との同一検査も行なう(違えば理由つきで失敗)
    check_app_contents "$check_only_app" 1
    return
  fi

  if (( unsigned )) && [[ -n "$notarize_profile" ]]; then
    echo "--unsigned と --notarize は同時に指定できません"
    usage
    exit 1
  fi

  cd "$ROOT_DIR"

  # 1. 作業ツリーの状態。配った pkg がどのコミットか分かるようにする
  local dirty commit
  dirty="$(git status --porcelain)"
  commit="$(git rev-parse --short HEAD)"
  if [[ -n "$dirty" ]]; then
    if (( unsigned )); then
      echo "警告: 未コミットの変更があります(--unsigned は続行)。コミット $commit の pkg とは限りません"
    else
      echo "未コミットの変更があります。コミットしてからやり直してください(試しなら --unsigned)"
      printf '%s\n' "$dirty" | head -n 10
      exit 1
    fi
  fi

  # 2. 版の番号とチーム ID
  local edition team
  edition="$(sed -n 's/^ECRITU_EDITION_NUMBER *= *\([0-9][0-9]*\).*/\1/p' Config/Edition.xcconfig | head -n 1)"
  team="$(sed -n 's/^ECRITU_DEVELOPMENT_TEAM *= *\([A-Z0-9]*\).*/\1/p' Config/Edition.xcconfig | head -n 1)"
  if [[ -z "$edition" || -z "$team" ]]; then echo "Config/Edition.xcconfig から版の番号かチーム ID を読めません"; exit 1; fi

  # 3. 署名に使う証明書(ビルドに数分かかるので先に探す)
  local app_identity="" inst_identity=""
  if (( ! unsigned )); then
    local ids
    if ids="$(find_developer_id_identities "$(security find-identity -v 2>/dev/null || true)" "$team")"; then
      app_identity="$(printf '%s\n' "$ids" | sed -n 1p)"
      inst_identity="$(printf '%s\n' "$ids" | sed -n 2p)"
      echo "署名の証明書: $app_identity / $inst_identity"
    else
      echo "Developer ID の証明書が見つかりません(チーム $team)。"
      [[ -z "$(printf '%s\n' "$ids" | sed -n 1p)" ]] && echo "  無い: Developer ID Application"
      [[ -z "$(printf '%s\n' "$ids" | sed -n 2p)" ]] && echo "  無い: Developer ID Installer"
      print_certificate_howto
      echo "試しに署名なしで作るなら --unsigned を付けてください。pkg は作っていません。"
      exit 1
    fi
  fi

  # 4. この作業ツリーの tmp/ を病名なしで作り直すことの告知
  echo "お知らせ: 配布用のビルドは ECRITU_INCLUDE_MEDICAUX=0 で、この作業ツリーの tmp/ の辞書を病名語彙なしに作り直します。"
  if compgen -G "$ROOT_DIR/references/m*dicaux.plist" > /dev/null; then
    echo "  references/ に病名語彙の元ファイルがあります。次の開発ビルドは Signing.local.xcconfig の設定で病名語彙を戻します。"
  else
    echo "  references/ に病名語彙の元ファイル(git 管理外)がこの作業ツリーにありません。次の開発ビルドでも病名語彙は戻りません。"
  fi
  if [[ -d "$HOME/Library/Input Methods/$APP_NAME" ]]; then
    echo "警告: $HOME/Library/Input Methods/$APP_NAME(開発版)があります。触れませんが、pkg を入れる前に入力ソースから外して消してください。"
    echo "  このあとの自己検査で、ビルドした ecritu を数秒だけ起動します(開発版が動いていると、同じ接続名のものが一時的に 2 つになります)。"
  fi

  # 5. ビルド(古い製品を先に消す)
  local dist="$ROOT_DIR/tmp/mac-dist"
  local derived="$dist/DerivedData"
  rm -rf "$derived/Build/Products" "$dist/root" "$dist/scripts"
  # 同じ版の番号の古い pkg(署名なし・公証前・公証済み)も消す。今回作ったものと取り違えないように
  rm -f "$dist"/ecritu-0.1-"$edition"*.pkg
  mkdir -p "$dist"
  echo "Release でビルドします(初回は数分〜10 分かかります)"
  xcodebuild -project MacInputMethod/EcrituPourMac.xcodeproj -scheme EcrituPourMac -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$derived" \
    ECRITU_INCLUDE_MEDICAUX=0 ARCHS=arm64 ONLY_ACTIVE_ARCH=NO build > "$dist/build.log" 2>&1 || {
      echo "ビルドに失敗しました。ログの末尾($dist/build.log):"
      tail -n 30 "$dist/build.log"
      exit 1
    }
  tail -n 3 "$dist/build.log"
  local built="$derived/Build/Products/Release/$APP_NAME"
  [[ -d "$built" ]] || { echo "ビルド結果が見つかりません: $built"; exit 1; }

  # 6. 検査
  local state
  state="$(cat "$ROOT_DIR/tmp/.medicaux.state" 2>/dev/null || echo '?')"
  if [[ "$state" != "0" ]]; then echo "tmp/.medicaux.state が 0 でありません: '$state'"; exit 1; fi
  echo "tmp/.medicaux.state = 0"
  check_app_contents "$built" 1 || exit 1

  # 7. 実行ファイルの自己検査(署名の付け直しの前の、ビルドそのまま)
  echo "実行ファイルの自己検査(直接起動して数秒で終了させます)"
  run_self_check "$built/Contents/MacOS/ecritu" "$dist/self-check.log" || exit 1

  # 8. 署名
  if (( ! unsigned )); then
    echo "署名します(タイムスタンプの取得で Apple のサーバーへ通信します)"
    codesign --force --options runtime --timestamp --sign "$app_identity" "$built"
    codesign --verify --strict --verbose=2 "$built"
    # 出力をいったん変数に受ける(pipefail の下で grep -q が先に読み終えると、パイプ全体が失敗扱いになるため)
    local sign_info
    sign_info="$(codesign -dv "$built" 2>&1 || true)"
    if grep -q 'flags=.*runtime' <<< "$sign_info"; then echo "  OK: hardened runtime あり"; else echo "  NG: hardened runtime が無い"; exit 1; fi
  fi

  # 9. pkg
  mkdir -p "$dist/root" "$dist/scripts"
  ditto "$built" "$dist/root/$APP_NAME"
  cp "$ROOT_DIR/MacInputMethod/Packaging/postinstall" "$dist/scripts/postinstall"
  chmod 755 "$dist/scripts/postinstall"
  local base="$dist/ecritu-0.1-$edition" pkg
  local final_pkg=""
  if (( unsigned )); then pkg="$base-unsigned.pkg"; else pkg="$base-not-notarized.pkg"; final_pkg="$base.pkg"; fi
  rm -f "$pkg" "$final_pkg"
  local sign_args=()
  if (( ! unsigned )); then sign_args=(--sign "$inst_identity" --timestamp); fi
  # 部品の pkg を作り、入れ先を [すべてのユーザ用] と [自分専用] から選べる配布用の pkg で包む(distribution.xml の domains)。
  # [自分専用] では、install-location はホームからの相対の場所として働く(~/Library/Input Methods)
  local component_dir="$dist/component"
  rm -rf "$component_dir"; mkdir -p "$component_dir"
  pkgbuild --root "$dist/root" --component-plist "$ROOT_DIR/MacInputMethod/Packaging/component.plist" \
    --install-location "/Library/Input Methods" --identifier "$PKG_ID" --version "0.1.$edition" \
    --scripts "$dist/scripts" "$component_dir/ecritu-component.pkg"
  sed -e "s/@PKG_ID@/$PKG_ID/g" -e "s/@VERSION@/0.1.$edition/g" -e "s/@COMPONENT@/ecritu-component.pkg/g" \
    "$ROOT_DIR/MacInputMethod/Packaging/distribution.xml" > "$dist/distribution.xml"
  productbuild --distribution "$dist/distribution.xml" --package-path "$component_dir" \
    --resources "$ROOT_DIR/MacInputMethod/Packaging/Resources" \
    ${sign_args[@]+"${sign_args[@]}"} "$pkg"
  if (( ! unsigned )); then
    pkgutil --check-signature "$pkg"
  fi

  # 10. 公証
  if (( ! unsigned )); then
    if [[ -n "$notarize_profile" ]]; then
      echo "公証に提出します(Apple へ送信します)"
      local out id
      if out="$(xcrun notarytool submit "$pkg" --keychain-profile "$notarize_profile" --wait 2>&1)"; then
        echo "$out" | tail -n 8
        if grep -q 'status: Accepted' <<< "$out"; then
          # ステープルと確認が済むまでは -not-notarized の名前のままにする(途中で失敗したものを成果物の名前で残さない)
          xcrun stapler staple "$pkg"
          xcrun stapler validate "$pkg"
          if ! spctl -a -t install -vv "$pkg"; then
            echo "NG: Gatekeeper の評価に通りません。pkg(配らないでください): $pkg"
            exit 1
          fi
          mv "$pkg" "$final_pkg"; pkg="$final_pkg"
        else
          id="$(echo "$out" | sed -n 's/^ *id: *//p' | head -n 1)"
          echo "公証が通りませんでした。ログ:"
          [[ -n "$id" ]] && xcrun notarytool log "$id" --keychain-profile "$notarize_profile" || true
          echo "pkg(公証なし): $pkg"
          exit 1
        fi
      else
        echo "$out" | tail -n 8
        echo "公証への提出に失敗しました(プロファイル名 '$notarize_profile' を確かめてください)。pkg(公証なし): $pkg"
        exit 1
      fi
    else
      echo "公証はしていません。公証するには、先に一度だけ次でプロファイルを作ってから --notarize を付けて再実行してください:"
      echo "  xcrun notarytool store-credentials <プロファイル名>(Apple ID・App 用パスワード・チーム ID を対話で入力し、キーチェーンに保存されます)"
      echo "  bash tools/package_mac_input_method.sh --notarize <プロファイル名>"
    fi
  fi

  # 11. 結果
  echo ""
  echo "pkg: $pkg"
  echo "大きさ: $(stat -f%z "$pkg") バイト"
  echo "SHA-256: $(shasum -a 256 "$pkg" | cut -d' ' -f1)"
  echo "コミット: $commit$([[ -n "$dirty" ]] && echo '(未コミットの変更あり)')"
}

# source されたとき(試験用に関数だけ呼ぶとき)は main を回さない
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
