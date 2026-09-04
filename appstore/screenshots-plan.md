# App Store スクリーンショット計画

## 必要サイズ(提出時にASCの表示で最終確認)

- iPhone 6.9インチ: 1320×2868(縦)— **iPhone 17 Pro Max シミュレータで撮影可能**
- (ASCが求める場合)6.5インチ: 1284×2778 — iPhone 11 Pro Max 等
- 実機 iPhone 15(6.1インチ)のスクショはサイズ不適合なので素材にしない

## 撮影手順(シミュレータ)

1. アプリをシミュレータへインストール(`xcrun simctl install <UD> <path>/écritu.app`)
2. 設定 > 一般 > キーボード で écritu を追加(+フルアクセス)、**音声入力をオフ**(マイクを消す)
3. 下記「撮影用の入力ページ」をホーム画面に追加し、そのアイコンから起動
4. 地球儀で écritu に切替 → `xcrun simctl io <UD> screenshot appstore/screenshots/NN-name.png`

## 撮影状態(take 3 = 現行、2026-09-02)

6枚すべて撮影済み・1320×2868。ホーム画面に追加した `capture-page.html` から起動して撮ったため、
Safari のドメイン表示ピルもツールバーも写っていない。音声入力はオフでマイクも無し。

| # | ファイル | 内容 |
|---|---|---|
| 01 | 01-kana.png | 「トカイの土着品種 Hárslevelű と くゔぇーるすーるー」+ 候補 Kövérszőlő |
| 02 | 02-comma-flick.png | や キーの2段階フリックで `(` を入力中(**3x3+わ/ピンク背景/style iPhone のフリック/前置修飾/アヒルのキー**) |
| 03 | 03-flags.png | 本文に🇭🇺を入れた状態で🇸🇰を長押し(Slovaquie バブル) |
| 04 | 04-kaomoji-search.png | 顔文字検索 よみ「わーい」の候補 |
| 05 | 05-number-unit.png | 書式化数値の単位 `36 200 000 hℓ`(sep mil + espace + 接頭辞 h + ℓ) |
| 06 | 06-settings.png | 設定アプリのアクセントカラー/テーマカラー |

**02 の設定**(撮影時だけ変更し、撮影後に既定へ戻した):
`keyboardBackgroundTheme=sakura` / `flickDirectionProfile=apple` /
`kanaModifierPlacement=prefix` / `flickGuideDisplayModeModifier=off`(これでアヒルになる)/
`kanaLayoutMode=threeByThreePlusWa`。本文は01の文を Kövérszőlő まで確定させた状態。
2段階フリックは や キーを左へフリック(『)→指を離さず上へ、で `(` が出る。
**05 の設定**: `numberLitreSymbol=script`(ℓ)。製品の初期設定は `l`。

数値はユーザー提供。公開前に出典と数字を再確認すること。

## 撮影用の入力ページ

`appstore/capture-page.html` を使う(scratchpad に作り直さない)。配信は
`python3 -m http.server 8765` をこのディレクトリで起動し、シミュレータから
`http://127.0.0.1:8765/capture-page.html` を開く。

**必ずホーム画面に追加してから、そのアイコンで起動して撮る。** Safari で直接開くと、
キーボード表示中に画面中央へ `127.0.0.1` のドメイン表示ピルが出てしまい、下部にも
Safari のバーが残る。ホーム画面から起動すればスタンドアロン表示になり、どちらも消える。

手順: Safari で開く → 共有ボタン → 「ホーム画面に追加」 → 追加 → ホーム画面のアイコンで起動。
一度追加すればシミュレータに残るので、次回以降はアイコンから起動するだけ。

## 撮影メモ(再撮影用)

- シミュレータ操作は CGEvent 自動化(scratchpad/shoot/cgclick.py ほか)で実施
- ステータスバーは `xcrun simctl status_bar <UD> override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4`
- 入力ページは上記「撮影用の入力ページ」を参照(`appstore/capture-page.html`)
