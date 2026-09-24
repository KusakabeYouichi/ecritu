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

## 撮影状態(take 5 = 現行、2026-09-24。01〜05 を無操作手順で撮り直し)

6枚すべて撮影済み・1320×2868。ホーム画面に追加した `capture-page.html` から起動して撮ったため、
Safari のドメイン表示ピルもツールバーも写っていない。音声入力はオフでマイクも無し。

| # | ファイル | 内容 |
|---|---|---|
| 01 | 01-kana.png | 「トカイの土着品種 Hárslevelű と くゔぇーるすーるー」+ 候補 Kövérszőlő |
| 02 | 02-comma-flick.png | や キーの2段階フリックで `(` を入力中(**3x3+わ/ピンク背景/style iPhone のフリック/前置修飾/アヒルのキー**) |
| 03 | 03-flags.png | 本文に🇭🇺を入れた状態で🇸🇰を長押し(Slovaquie バブル) |
| 04 | 04-kaomoji-search.png | 顔文字検索 よみ「わーい」の候補 |
| 05 | 05-number-unit.png | 書式化数値の単位 `36 200 000 hℓ`(sep mil + espace + 接頭辞 h + ℓ) |
| 06 | 06-settings.png | 設定アプリのアクセントカラー/テーマカラー(take 4、2026-09-19: ステータスバーの「◀ Safari」を消すため撮り直し。今日の寸法変更の影響を受けないので据え置き) |

01〜05 は 2026-09-24(edition 3200)に撮り直した。縦画面の寸法変更(候補欄の上余白 13→10pt、
ヘッダー 35→31pt、最下段とホームインジケーターの間 20→7pt、キー高さ +1pt)と「あいう」→「あい」を反映。
構図・本文・設定は take 3 と同じに揃えてある。撮り方は末尾の「無操作での撮影手順」。

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

## 無操作での撮影手順(2026-09-24 確立、take 5)

Xcode 27 には Simulator.app が無く、`simctl` にも触点注入が無い(CoreSimulator から
`SimDeviceLegacyHIDClient` も消えており idb 方式も不可)。**代わりに、指を使わずに撮る道を作った。**
01〜05 と マニュアルの hero-kana はこの手順で撮り直した。

### 1. シミュレーターの仕込み(**必ず停止中に書く**。起動中は cfprefsd が上書きする)

`~/Library/Developer/CoreSimulator/Devices/<UD>/data` を `D` として:

| 仕込み | 場所 |
|---|---|
| キーボードの有効化 | `D/Library/Preferences/.GlobalPreferences.plist` の `AppleKeyboards` に `jp.or.pleiades.merope.ecritu.keyboard` |
| 起動時に écritu が出る | `D/Library/Preferences/com.apple.keyboard.preferences.plist` の `KeyboardLastUsed` / `KeyboardLastUsedForLanguage:ja_JP` / `:NonASCII` / `KeyboardsCurrentAndNext:0,1` |
| 音声入力オフ(マイクを消す) | `D/Library/Preferences/com.apple.assistant.support.plist` の `Dictation Enabled = false` |
| フルアクセス帯を消す | 拡張の `UserDefaults.standard`(`D/Containers/Data/PluginKitPlugin/<拡張のUUID>/Library/Preferences/jp.or.pleiades.merope.ecritu.keyboard.plist`)に `didDismissFullAccessNotice = true` |
| 撮影用の設定 | App Group の plist(`simctl get_app_container <UD> jp.or.pleiades.merope.ecritu group.jp.or.pleiades.merope.ecritu`)に直接書く |

**フルアクセスが無くても設定の読み取りは効く**(書き込みだけ不可)ので、TCC を触る必要は無い。
拡張の UUID は各コンテナの `.com.apple.mobile_container_manager.metadata.plist` の
`MCMMetadataIdentifier` で引く。

### 2. ホーム画面の web クリップを単独起動する

`xcrun simctl launch <UD> com.apple.webapp` でホーム画面に追加済みの「メモ」が開く。
**ドメイン表示ピルも Safari のバーも出ない。** `simctl openurl` で Safari に開くとピルが写る。
ページの autofocus で入力欄に入り、上の仕込みにより écritu が出た状態になる。

### 3. 打鍵と画面状態は一時フックで作る(コミットしない)

拡張に使い捨てのコードを入れ、App Group のキーを読んで状態を作る。撮影後 `git checkout -- KeyboardExtension/` で外す。

| キー | 効果 | 仕込んだ場所 |
|---|---|---|
| `screenshotScript` | 本文の挿入と読みの打鍵(`handleTextInput` を 0.12 秒ごと) | `KeyboardViewController+Diagnostics.swift` / 呼び出しは `viewDidAppear` |
| `screenshot_inputMode` / `_emojiSubmode` / `_emojiCategory` | 面の初期状態 | `KeyboardRootView` の `@State` 初期値と `.onAppear` |
| `screenshot_kaomojiCategory` / `_kaomojiPrefix` / `_kaomojiReading` | 顔文字検索の状態(読み行のスクロールも `ScrollViewReader` で) | 同上 / `KeyboardRootView+EmojiKaomojiLayouts.swift` |
| `screenshot_numberBuffer` | 書式化数値の入力値。カテゴリー・単位・接頭辞は `FormattedNumberPreferences` が App Group に永続化しているのでそのまま書ける | `KeyboardRootView` |
| `screenshot_emojiBubble` | 国旗の国名吹き出しを出したままにする(`didHighlightItemAt` を直接呼ぶ) | `KeyboardKeyComponents.swift` |
| `screenshot_flickKey` | 2段階フリックの吹き出し(`isTouching` + `secondaryFlickPrimaryDirection=.gauche` + `secondaryFlickVerticalDirection=.haut`) | `FlickKeyView.swift` |

**でばぐ可視化を切ること**: `KeyboardRootView.memoryPressureVisualizationEnabled` を一時的に false に
する(シミュレーターは fp が 45 を超えるので削除キーに数値バッジが写る)。

### 4. つまずいた点

- 拡張の attach 失敗(`表示未到達`)が出ると純正キーボードが写る。web クリップを 2〜3 回起動し直せば通る
- 撮影のたびに `xcrun simctl status_bar <UD> override --time 9:41 …` を打ち直す(再起動で消える)
- マニュアルの hero-kana は **iPhone 17 Pro**(1206×2622)から撮って `(0,1630)-(1206,2446)` を切り抜く。
  App Store の 6.9 インチは iPhone 17 Pro Max(1320×2868)なので別のシミュレーターで撮る

