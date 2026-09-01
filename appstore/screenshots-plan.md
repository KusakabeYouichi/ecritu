# App Store スクリーンショット計画

## 必要サイズ(提出時にASCの表示で最終確認)

- iPhone 6.9インチ: 1320×2868(縦)— **iPhone 17 Pro Max シミュレータで撮影可能**
- (ASCが求める場合)6.5インチ: 1284×2778 — iPhone 11 Pro Max 等
- 実機 iPhone 15(6.1インチ)のスクショはサイズ不適合なので素材にしない

## 撮影手順(シミュレータ)

1. `xcodebuild -scheme écritu -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build` して Run(⌘R)
2. シミュレータの 設定 > 一般 > キーボード > キーボード で écritu を追加(+フルアクセス)
3. Safari で適当な入力ページを開き、地球儀で écritu に切替
4. ⌘S(またはFile > Save Screen)で撮影 → `appstore/screenshots/` へ保存
   命名: `01-kana.png` のように番号+内容

## ショットリスト(6枚構成・推奨テーマ: 初期設定のまま)

| # | 場面 | 見せるもの | 演出 |
|---|---|---|---|
| 01 | かな面+変換候補 | 5×2配列と候補バー | 「きょうのかいぎは」等を入力し連文節候補を表示 |
| 02 | 読点キーのフリックガイド | ?!・。がかなのまま | 、キーを長押し気味にしてガイド表示の瞬間 |
| 03 | 絵文字パネル(国旗長押し) | 国旗の国名バブル | 国旗カテゴリーで🇫🇷を押下中 |
| 04 | 顔文字検索 | 読み→顔文字 | 検索カテゴリーで「わーい」系を表示 |
| 05 | 書式化数値(カレンダー) | 日付・単位入力 | 数字モードのカレンダー/単位表示 |
| 06 | 設定アプリ | テーマ/配列のカード | アクセントカラー選択部など彩度のある画面 |

- キャプション焼き込み(上部に説明文)を入れる場合は撮影後にこちらで合成可能。
  まず素の6枚を撮って `appstore/screenshots/` に置いてください。

## 状態

- [x] 6.9インチ 6枚撮影済み(2026-09-01、iPhone 17 Pro Max シミュレータ、1320×2868 確認済み)
  - `01-kana.png` きょうのかいぎは+連文節候補 / `02-comma-flick.png` 、キーのフリック?プレビュー
  - `03-flags.png` 🇫🇷長押しFranceバブル / `04-kaomoji-search.png` よみ「わーい」の顔文字候補
  - `05-number-calendar.png` 書式化数値カレンダー(9月17日) / `06-settings.png` アクセント/テーマカラー
- テキスト素材は `appstore/metadata.md` に完成済み

## 撮り直し案(保留中 — 依頼があったら実施)

- 下端バーのマイクを消す: シミュレータの 設定 > 一般 > キーボード > 音声入力オフ(06は設定アプリ画面なので対象外)
- 例文をワインの説明文に変更し、écrituの個性(ワイン語彙+フランス語)を見せる:
  - 01: 「このシャトーのカベルネは」等のワイン文脈の連文節+変換候補
  - 追加候補: 欧文入力(azerty/qwerty)で Château の â・é を長押しアクセント入力しているところ、
    または欧文サジェスト(français 15,000語)が出ているところ。アクサン記号つき文字が
    そのまま打てることが伝わる構図にする

## 撮影メモ(再撮影用)

- シミュレータ操作は CGEvent 自動化(scratchpad/shoot/cgclick.py ほか)で実施
- ステータスバーは `xcrun simctl status_bar <UD> override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4`
- 入力ページは scratchpad/shoot/field.html(要 `<meta charset="utf-8">`)を `python3 -m http.server` で配信
