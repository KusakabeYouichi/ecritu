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
| 06 | 06-settings.png | 設定アプリのアクセントカラー/テーマカラー(take 4、2026-09-19: ステータスバーの「◀ Safari」を消すため撮り直し) |

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

## 06 の撮り直し手順(2026-09-19、take 4)

Xcode 27 には Simulator.app の UI が同梱されておらず、CGEvent/AppleScript での操作ができない。代わりに
ContentView に一時的な scroll フック(環境変数 `ECRITU_SCREENSHOT_SCROLL_TO` があれば `.id("screenshot-anchor")`
を付けた 数字ペイン配列 (horizontal) のカードへ 1.5/2.5/3.5/4.5 秒後に scrollTo。LazyVStack は 1 回だと行き過ぎる)を
入れて撮り、撮影後に `git checkout -- App/ContentView.swift` で外した(コミットしない)。

1. `xcrun simctl boot B907C0B8-…`(iPhone 17 Pro Max)→ `xcodebuild build -scheme écritu -destination "platform=iOS Simulator,id=…"`
2. `xcrun simctl install … Debug-iphonesimulator/écritu.app`
3. `xcrun simctl spawn … defaults write group.jp.or.pleiades.merope.ecritu accentPalette -string emeraude`(theme は bleu)
4. `xcrun simctl status_bar … override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4`
5. `SIMCTL_CHILD_ECRITU_SCREENSHOT_SCROLL_TO=1 xcrun simctl launch … jp.or.pleiades.merope.ecritu` → 6 秒待って `simctl io … screenshot`
アプリはホーム画面(simctl launch)から起動するので「◀ Safari」は出ない。

## 01〜05 の撮り直しで分かったこと(2026-09-24)

今日の縦画面の寸法変更(候補欄の上余白 13→10pt、ヘッダー 35→31pt、最下段とホームインジケーターの
間 20→7pt、キー高さ +1pt)で、01〜05 の鍵盤の見た目がわずかに古くなった(最下段が実機では 13pt 下がる)。
文字や名前(単漢字入力など)は写っていないので、内容としての誤りは無い。

**撮り直しの障害**: 打鍵・フリック・長押しを起こす手段が無い。
- Xcode 27 には Simulator.app が無い(`Contents/Developer/Applications` 自体が無い)。DeviceHub.app は
  デバイス一覧で、シミュレーターの画面は出ない。CGEvent/AppleScript の対象が存在しない。
- `simctl` に触点注入は無い(`io` は録画・スクショ・画面列挙だけ、`ui` は外観設定だけ)。
- CoreSimulator から `SimDeviceLegacyHIDClient` が消えており、idb 方式(Indigo HID)も使えない。
- 残る道は XCUITest 用ターゲットの新設(pbxproj 手術)か、拡張に一時的な自動打鍵フックを入れる
  (06 の scroll フックと同じ流儀)。02(2段階フリックの泡)と 03(長押しの泡)は FlickKeyView の
  内部 @State を外から起こす必要があり、特に重い。

**前進した点**: 触らずにキーボードを出すところまでは自動化できた。
1. `~/Library/Developer/CoreSimulator/Devices/<UD>/data/Library/Preferences/.GlobalPreferences.plist` の
   `AppleKeyboards` に `jp.or.pleiades.merope.ecritu.keyboard` を入れる(旧 ID `com.kusakabe.ecritu.keyboard`
   が残っていたので置換した)。
2. 同 `com.apple.keyboard.preferences.plist` の `KeyboardLastUsed` /
   `KeyboardLastUsedForLanguage:ja_JP` / `:NonASCII` / `KeyboardsCurrentAndNext:0,1` を同じ ID にする。
   **どちらもシミュレーター停止中に書く**(起動中は cfprefsd が上書きする)。
3. 起動 → `simctl openurl` で `capture-page.html` を開くと autofocus で鍵盤が出て、écritu が選ばれている。

**フルアクセスだけ未解決**: 「フルアクセスがオフです」の帯が出る。旧 ID の許可は
`data/Library/TCC/TCC.db` の `kTCCServiceKeyboardNetwork | com.kusakabe.ecritu | 2` に入っていた。
`simctl privacy` にこのサービスは無いので、TCC.db へ新 ID の行を入れるしかない(要ユーザー許可)。
一時ビルドで帯と設定読みを差し替える手もある。
