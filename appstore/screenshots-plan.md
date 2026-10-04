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

## 撮影状態(take 8 = 現行、2026-10-04。全 6 枚とマニュアルの hero・目次画像を撮り直し)

**take 8(2026-10-04、edition 3322)**: 01〜05 と hero-kana は take 7 とピクセル単位で同じ(キーボードの見た目は 10-02 から
変わっていない)ことを確かめて差し替え。06 は設定カードの付番(V.2/V.3/V.4/F.1、2026-10-02)を反映して撮り直し。
06 の一時フックは ContentView の V.2 カードに `.id("screenshot-anchor")`、ScrollViewReader に環境変数
`ECRITU_SCREENSHOT_SCROLL_TO` で 1.5/2.5/3.5/4.5 秒後に scrollTo(撮影後 `git checkout -- App/ContentView.swift`)。
`accentPalette=emeraude` を停止中に書いて起動。hero-kana は iPhone 17 Pro(EAA1651A、web クリップ無し)で
Safari に capture-page を開いて撮り、`(0,1624)-(1206,2446)` を切り抜き。目次画像は同じ切り抜き範囲で再生成
(変わったのは toc-07-settings と toc-08-kana。toc-08-landscape は図からの切り抜きなので対象外)。
05 は 2 回とも 17pt の余白付きで、3 回目で余白無し。判定は前回との行ごとの差(差が出るのがキーボード上端 1854 より上だけなら余白付き)。

### take 7 の記録(2026-10-02。01〜05 を上余白の補正なしで撮り直し、高さを 02 にそろえた)

6枚すべて撮影済み・1320×2868。ホーム画面に追加した `capture-page.html` から起動して撮ったため、
Safari のドメイン表示ピルもツールバーも写っていない。音声入力はオフでマイクも無し。

| # | ファイル | 内容 |
|---|---|---|
| 01 | 01-kana.png | 「トカイの土着品種 Hárslevelű と くゔぇーるすーるー」+ 候補 Kövérszőlő |
| 02 | 02-comma-flick.png | 『や』キーの2段階フリックで `(` を入力中(**3x3+わ/ピンク背景/style iPhone のフリック/前置修飾/アヒルのキー**) |
| 03 | 03-flags.png | 本文に🇭🇺を入れた状態で🇸🇰を長押し(Slovaquie バブル) |
| 04 | 04-kaomoji-search.png | 顔文字検索 よみ「わーい」の候補 |
| 05 | 05-number-unit.png | 書式化数値の単位 `36 200 000 hℓ`(sep mil + espace + 接頭辞 h + ℓ) |
| 06 | 06-settings.png | 設定アプリの V.2 数字ペイン配列/V.3 アクセントカラー/V.4 テーマカラー/F.1(take 8、2026-10-04: カードの付番を反映) |

01〜05 は 2026-10-02(edition 3292 相当)に撮り直した。9/25 の 3216 で縦の高さを純正のかなキーボードに揃え、
候補欄の上に未確定の行を常設したため、9/24 の take 5 とは高さと候補欄が違っていた。
(以下は take 5 の記録)01〜05 は 2026-09-24(edition 3200)に撮り直した。縦画面の寸法変更(候補欄の上余白 13→10pt、
ヘッダー 35→31pt、最下段とホームインジケーターの間 20→7pt、キー高さ +1pt)と「あいう」→「あい」を反映。
構図・本文・設定は take 3 と同じに揃えてある。撮り方は末尾の「無操作での撮影手順」。

**02 の設定**(撮影時だけ変更し、撮影後に既定へ戻した):
`keyboardBackgroundTheme=sakura` / `flickDirectionProfile=apple` /
`kanaModifierPlacement=prefix` / `flickGuideDisplayModeModifier=off`(これでアヒルになる)/
`kanaLayoutMode=threeByThreePlusWa`。本文は01の文を Kövérszőlő まで確定させた状態。
2段階フリックは『や』キーを左へフリック(『)→指を離さず上へ、で `(` が出る。
**05 の設定**: `numberLitreSymbol=script`(ℓ)。製品の初期設定は `l`。

05 の数値(フランスのワイン生産量 36 200 000 hℓ)の出典は、フランス政府の農業・食料主権省(Ministère de l’Agriculture et de la Souveraineté alimentaire)の統計データ(ユーザ確認 2026-10-04)。

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

**道具(2026-10-02)**: フックは `python3 appstore/apply-screenshot-hooks.py` でまとめて入る(コミットしない。
撮影後 `git checkout -- KeyboardExtension/`)。1 枚の撮影は `appstore/shoot-screenshot.sh <UDID> <出力接頭辞> "<種>"`。
take 6 で使った種(iPhone 17 Pro Max、`B907C0B8-0540-436D-9D10-2E5747498716`):

| # | 種(`key=型:値`、型 s/i/b、d は削除) |
|---|---|
| 01 | `screenshotScript=s:01 kanaLayoutMode=d: keyboardBackgroundTheme=d: flickDirectionProfile=d: kanaModifierPlacement=d: flickGuideDisplayModeModifier=d:` |
| 02 | `screenshotScript=s:02 screenshot_flickKey=s:や kanaLayoutMode=s:threeByThreePlusWa keyboardBackgroundTheme=s:sakura flickDirectionProfile=s:apple kanaModifierPlacement=s:prefix flickGuideDisplayModeModifier=s:off` |
| 03 | `screenshotScript=s:03 screenshot_inputMode=s:emoji screenshot_emojiSubmode=s:emoji screenshot_emojiCategory=s:flags screenshot_emojiBubble=s:🇸🇰` |
| 04 | `screenshotScript=s:04 screenshot_inputMode=s:emoji screenshot_emojiSubmode=s:kaomoji screenshot_kaomojiCategory=s:search screenshot_kaomojiPrefix=s:わ screenshot_kaomojiReading=s:わーい` |
| 05 | `screenshotScript=s:05 screenshot_inputMode=s:formattedNumber screenshot_numberBuffer=s:36200000 numberLitreSymbol=s:script formattedNumber.lastCategory=i:2 formattedNumber.lastUnit.2=s:L formattedNumber.lastPrefix.2=s:h formattedNumber.unitSpacing=b:true` |

撮影後は 02/05 で変えた設定(配列・背景・フリック方向・修飾の位置・ガイド・ℓ)と `screenshot*` を削除して既定に戻す。
**ダイナミックアイランドが写ることがある**(take 6 の 04 で 2 回)。写ったら数秒待って `xcrun simctl io <UDID> screenshot` で撮り足す。

**上余白の補正を切ってから撮る**(take 7、2026-10-02)。3264 以降、縦画面は 17pt の透明な帯を足して高く申告する
(実機のホストが付ける灰色の余白を打ち消すため)。シミュレーターのホストは余白を付けないので、帯がそのまま
キーボードの上の空白として写る。apply-screenshot-hooks.py が `hostPlaceholderTopInset` を 0 にする。

**高さがそろっているか必ず測る**(take 7 の差し替え)。iOS はキーボードを出す経路によって、他社製キーボードの上に
17pt の灰色の余白を足す(製品は補正で打ち消すが、撮影では補正を切っている)。余白が付いた回はキーボードが 17pt 高く
写る。6.9 インチなら、中央の列でホストの入力補助バーの下端が y=1824・キーボードの上端が 1854 になっていれば正しい
(余白付きは 1773/1803)。余白が付きやすい条件と対策:
- アプリの入れ直し直後 → 入れ直しは先に済ませ、撮影は `SKIP_INSTALL=1` で起動し直すだけにする
- 表示直後の面の切り替え(かな→絵文字)→ apply-screenshot-hooks.py の 6 で最初から指定の面で開く
- それでも付く回はある → 起動し直しを数回繰り返して、付かない回を選ぶ

**純正キーボードが写り続けたら**、装着失敗で iOS が「最後に使ったキーボード」を純正に切り替えて覚えている。
停止中に `D/Library/Preferences/com.apple.keyboard.preferences.plist` の `KeyboardLastUsed`・
`KeyboardLastUsedForLanguage:ja_JP`・`:NonASCII`・`KeyboardsCurrentAndNext:0/1` を
`jp.or.pleiades.merope.ecritu.keyboard` に戻して起動し直す(take 7 の 02 で発生)。


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
- マニュアルの hero-kana は **iPhone 17 Pro**(1206×2622)から撮り、キーボードの上端の 17px 上から最下段のピンクが
  終わる 49px 下までを切り抜く(take 7、2026-10-02: 上端 1641・ピンクの終わり 2397 → `(0,1624)-(1206,2446)`、高さ 822)。
  撮影用の設定: `kanaLayoutMode=threeByThreePlusWa keyboardBackgroundTheme=sakura flickDirectionProfile=littlebear
  kanaModifierPlacement=postfix accentPalette=emeraude flickGuideDisplayModeKana=fourDirections
  flickGuideDisplayModeModifier=off kanaModeSwitcherTapAction=symbols`(本文は空。Safari で開いてよい=上は切り抜きで落ちる)。
  旧記録(take 5): `(0,1630)-(1206,2446)` を切り抜いた。
  App Store の 6.9 インチは iPhone 17 Pro Max(1320×2868)なので別のシミュレーターで撮る

