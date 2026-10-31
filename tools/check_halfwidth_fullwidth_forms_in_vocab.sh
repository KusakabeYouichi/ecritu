#!/usr/bin/env bash
# 同梱する語彙・絵文字・顔文字のデータに、Unicode の Halfwidth and Fullwidth Forms(U+FF01〜U+FFEE。いわゆる全角の
# 英数字・記号と、いわゆる半角のカタカナ)が入っていないかをビルドのたびに見る(3616、ユーザ指定)。見つけたら Xcode の
# 警告として出し、ビルドは止めない。対象は references/ の plist・json と、KeyboardExtension/ に写した語彙の json。
# Swift の文言は判定用の一覧(数字の検出 等)に同じ範囲の文字を正当に使うので対象外(手で git grep -P で点検する)。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

count=0
while IFS= read -r -d '' file; do
  while IFS=$'\t' read -r lineno text; do
    [[ -z "$lineno" ]] && continue
    echo "$file:$lineno: warning: U+FF01〜U+FFEE の文字(いわゆる全角の英数字・記号、いわゆる半角のカタカナ)が語彙のデータに入っている。普通の文字(『(』『2』『カ』)に直す: $text"
    count=$((count + 1))
  done < <(perl -CSD -ne 'if (/[\x{FF01}-\x{FFEE}]/) { s/^\s+//; print "$.\t$_" }' "$file" | cut -c1-200)
done < <(git ls-files -z -- 'references/*.plist' 'references/*.json' 'KeyboardExtension/*.json')

if (( count > 0 )); then
  echo "warning: U+FF01〜U+FFEE の文字が語彙のデータに $count 行ある(上の警告を参照)"
fi
exit 0
