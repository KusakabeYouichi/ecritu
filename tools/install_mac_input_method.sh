#!/usr/bin/env bash
# Mac の入力メソッド(ecritu.app)を ~/Library/Input Methods/ へ入れる。実行するのはユーザ。
# 使い方: bash tools/install_mac_input_method.sh [ビルド済みの ecritu.app の場所]
#   場所を省くと、DerivedData から EcrituPourMac のビルド(Debug)を探す
set -euo pipefail

APP_NAME="ecritu.app"
INSTALL_DIR="$HOME/Library/Input Methods"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME"

usage() {
  echo "使い方: bash tools/install_mac_input_method.sh [ビルド済みの $APP_NAME の場所]"
  echo "  先に xcodebuild -project MacInputMethod/EcrituPourMac.xcodeproj -scheme EcrituPourMac -destination 'platform=macOS' build でビルドしてください"
}

# 1. ビルド済みの ecritu.app の場所。末尾が ecritu.app で Contents/Info.plist を持つものだけ受け付ける
app_path="${1:-}"
if [[ -z "$app_path" ]]; then
  app_path="$(ls -dt "$HOME"/Library/Developer/Xcode/DerivedData/EcrituPourMac-*/Build/Products/Debug/"$APP_NAME" 2>/dev/null | head -n 1 || true)"
fi
app_path="${app_path%/}"
if [[ -z "$app_path" || "$(basename "$app_path")" != "$APP_NAME" || ! -f "$app_path/Contents/Info.plist" ]]; then
  usage
  exit 1
fi
echo "入れるもの: $app_path"

# 2. 別名で複製してから入れ替える(複製の途中で失敗しても、入っているものを壊さない)
mkdir -p "$INSTALL_DIR"
staging="$INSTALL_DIR/.$APP_NAME.installing"
rm -rf "$staging"
cp -R "$app_path" "$staging"
rm -rf "$INSTALLED_APP"
mv "$staging" "$INSTALLED_APP"
echo "入れました: $INSTALLED_APP"

# 3. 動いている ecritu を終了する。入れ替えの後に行なう(先に終了すると、macOS が古い版を起動し直すことがある)。
#    対象は名前でなく、インストール先の実行ファイルの場所で絞る。ホームの絶対パスを正規表現として先頭に固定する
#    (固定しないと、別の場所の同名パスを含むコマンドラインにも当たる)
kill_pattern="^$(printf '%s' "$INSTALLED_APP/Contents/MacOS/" | sed 's/[][\.*^$+?(){}|]/\\&/g')"
if pkill -f "$kill_pattern"; then
  echo "動いていた ecritu を終了しました(次に使うときに新しい版が起動します)"
fi

# 4. 初回の案内
echo ""
echo "初めて入れたときは [システム設定] > [キーボード] > [入力ソース] の [編集] で『écritu』を追加してください。"
echo "一覧に出てこないときは、いったんログアウトしてからもう一度ログインしてください。"
