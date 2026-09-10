#!/usr/bin/env bash
# 署名まわりの識別子が食い違ったままビルドが通るのを防ぐ(2847)。
#
# 背景: この repo は同一性に関わる値を Config/Edition.xcconfig の 1 変数から派生させている
# (bundle ID / App Group / keychain 群 / Info.plist の EcrituAppGroupIdentifier)。
# 各自の値は Config/Signing.local.xcconfig(git 管理外)で上書きする決まりだが、これを作らずに
# Xcode の画面で bundle ID を書き換えたり App Groups をキャパビリティ画面から追加すると、
# 画面で触った 1 か所だけがリテラルになり、変数由来の残りは既定値のまま残る。
# ベータテスター環境で実際に起きた(2026-09-07〜09 の 3 日調査):
#   署名の App Groups = group.com.twaitsjp.ecritu(画面で追加)
#   Info.plist の群名 = group.com.kusakabe.ecritu(変数=既定値)
#   → 拡張は実行時に Info.plist の値で App Group を要求 → 権限に無いので containermanagerd が拒否
#   → 設定も学習も共有されないが、変換自体はバンドル辞書で動くので「動くのに設定が届かない」に見える
#
# 破れてはいけない不変条件だけを見る(entitlements の解析は不要):
#   1. App Group == group.<アプリの bundle ID>
#   2. 拡張の bundle ID == <アプリの bundle ID>.keyboard
#   3. 実際にビルドされる PRODUCT_BUNDLE_IDENTIFIER が上の派生値と一致(=画面での上書きが無い)
#   4. entitlements ファイルの群が $(ECRITU_APP_GROUP_IDENTIFIER) のまま(=画面での追加が無い)
#   5. 実機ビルドで、設定されている Team ID の署名証明書が手元にあるか(=ローカル設定の作り忘れ検出。2853)
set -uo pipefail

fail=0

report() {
  # Xcode のイシューナビゲータに出す(error: 接頭辞)
  echo "error: [署名識別子] $1"
  fail=1
}

app_bundle_id="${ECRITU_APP_BUNDLE_IDENTIFIER:-}"
app_group_id="${ECRITU_APP_GROUP_IDENTIFIER:-}"
keyboard_bundle_id="${ECRITU_KEYBOARD_BUNDLE_IDENTIFIER:-}"
product_bundle_id="${PRODUCT_BUNDLE_IDENTIFIER:-}"

if [[ -z "$app_bundle_id" || -z "$app_group_id" ]]; then
  report "ECRITU_APP_BUNDLE_IDENTIFIER / ECRITU_APP_GROUP_IDENTIFIER が空です。Config/Edition.xcconfig が読まれていません"
  exit 1
fi

# 1. App Group は必ず group.<アプリの bundle ID>
if [[ "$app_group_id" != "group.$app_bundle_id" ]]; then
  report "App Group が bundle ID と食い違っています: $app_group_id ≠ group.$app_bundle_id"
fi

# 2. 拡張の bundle ID は アプリ + .keyboard
if [[ -n "$keyboard_bundle_id" && "$keyboard_bundle_id" != "$app_bundle_id.keyboard" ]]; then
  report "拡張の bundle ID が食い違っています: $keyboard_bundle_id ≠ $app_bundle_id.keyboard"
fi

# 3. このターゲットが実際に使う bundle ID が派生値と一致するか(画面での上書き検出)。
#    .appex かどうかで期待値を切り替える(ターゲット名は é を含むため比較に使わない)
if [[ -n "$product_bundle_id" ]]; then
  if [[ "${WRAPPER_EXTENSION:-}" == "appex" ]]; then
    expected_bundle_id="$app_bundle_id.keyboard"
  else
    expected_bundle_id="$app_bundle_id"
  fi

  if [[ "$product_bundle_id" != "$expected_bundle_id" ]]; then
    report "PRODUCT_BUNDLE_IDENTIFIER が Xcode の画面で上書きされています: $product_bundle_id ≠ $expected_bundle_id"
    echo "note: Build Settings の Product Bundle Identifier が太字なら選んで delete し、\$(ECRITU_APP_BUNDLE_IDENTIFIER) 由来に戻してください"
  fi
fi

# 4. entitlements の群がリテラルに置き換わっていないか(App Groups をキャパビリティ画面から
#    追加すると $(...) が実値に書き換わる)。ファイルはソース側を見る。
#    リテラルでも値が派生値と一致していれば実害は無いので警告に留め、食い違うときだけ止める(2854)
for entitlements in "${SRCROOT:-.}/App/Ecritu.entitlements" "${SRCROOT:-.}/KeyboardExtension/KeyboardExtension.entitlements"; do
  [[ -f "$entitlements" ]] || continue

  grep -q 'ECRITU_APP_GROUP_IDENTIFIER' "$entitlements" && continue

  # キー名にドットを含むため plutil -extract は使えない(パス区切りと解釈される)。PlistBuddy で読む
  literal_groups="$(/usr/libexec/PlistBuddy -c "Print :com.apple.security.application-groups" "$entitlements" 2>/dev/null \
    | sed -n '2,$p' | sed 's/^ *//' | grep -v '^}$' | paste -sd' ' -)"
  rel="${entitlements#"${SRCROOT:-.}/"}"

  if [[ "$literal_groups" == "$app_group_id" ]]; then
    echo "warning: [署名識別子] $(basename "$entitlements") の App Group がリテラル($literal_groups)です。値は合っているので通しますが、bundle ID を変えても追従しません"
    echo "note: git checkout -- $rel で \$(ECRITU_APP_GROUP_IDENTIFIER) に戻せます"
  else
    report "$(basename "$entitlements") の App Group がリテラルで、しかも派生値と違います: ${literal_groups:-(読めず)} ≠ $app_group_id"
    echo "note: git checkout -- $rel で戻し、Config/Signing.local.xcconfig で bundle ID を変えてください"
  fi
done

# 5. Config/Signing.local.xcconfig の作り忘れ検出(2853)。実機向けビルドのときだけ、
#    設定されている Team ID が手元の署名証明書(Apple Development の OU)に在るかを見る。
#    無ければ他人のチーム ID でビルドしようとしている = ローカル設定を作っていない。
#    ファイルの有無ではなく実効値で判定するので、作者(既定値が自分のチーム)は素通りする。
#    シミュレーターと CI(CODE_SIGNING_ALLOWED=NO)は対象外
if [[ "${PLATFORM_NAME:-}" == "iphoneos" && "${CODE_SIGNING_ALLOWED:-YES}" != "NO" ]]; then
  team="${ECRITU_DEVELOPMENT_TEAM:-}"
  local_teams="$(security find-certificate -a -c "Apple Development" -p 2>/dev/null \
    | awk '/BEGIN CERT/{c++} {print > ("/tmp/.ecritu_cert_" c ".pem")}' 2>/dev/null; \
    for f in /tmp/.ecritu_cert_*.pem; do
      [[ -f "$f" ]] || continue
      openssl x509 -in "$f" -noout -subject 2>/dev/null | sed -nE 's/.*OU *= *([A-Z0-9]+).*/\1/p'
    done | sort -u; rm -f /tmp/.ecritu_cert_*.pem)"

  if [[ -n "$team" && -n "$local_teams" ]] && ! printf '%s\n' "$local_teams" | grep -Fxq "$team"; then
    report "Team ID $team の署名証明書がこの Mac にありません(手元にあるのは: $(echo $local_teams))"
    echo "note: Config/Signing.local.xcconfig を作って自分の Team ID と bundle ID を設定してください" >&2
    echo "note: cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig" >&2
  fi
fi

if ((fail)); then
  echo "note: 各自の値は Config/Signing.local.xcconfig で設定します(cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig)。README の「GitHub 共同開発セットアップ」参照"
  exit 1
fi

exit 0
