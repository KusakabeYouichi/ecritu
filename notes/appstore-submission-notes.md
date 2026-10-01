# App Store 提出メモ(下書き)

## 審査員向けノート(Review Notes 案・英語)

> écritu is a Japanese flick-input keyboard with on-device kana-kanji
> conversion. All processing is performed entirely on device:
> the keyboard extension makes no network connections of any kind.
> "Allow Full Access" is used only for App Group data sharing between
> the container app and the keyboard (user-added vocabulary,
> suppression list, learned candidates, and settings). The keyboard is
> fully functional for typing and conversion without Full Access.
> Contacts access (optional, in the container app) is used only to add
> contact names to conversion candidates on device; no data leaves the
> device. The contact cache stored in the App Group is protected by iOS
> Data Protection (completeUntilFirstUserAuthentication) and excluded from
> backup; the app itself performs no encryption (CryptoKit remains only to
> read data saved by older versions), which is why the app declares
> ITSAppUsesNonExemptEncryption = NO.
>
> (正本は appstore/metadata.md の「審査ノート」。ここは下書きの控え。3260 で暗号化をやめた記述に更新、3299)

## App Store Connect プライバシー質問票の回答方針

- データ収集: **なし**(トラッキングなし・収集なし)
- 連絡先: アプリ内で読み取るが**端末外へ送信しない・収集に該当しない**
  (「アプリからリンクされないデータ」ですらなく「収集しない」で申告)
- PrivacyInfo.xcprivacy は App/拡張の両方に同梱済み
  (UserDefaults: CA92.1 + 1C8F.1)

## 説明文の素材(日本語)

- フリック入力+かな漢字変換(連文節対応)を全て端末内で処理。
  ネットワーク通信は一切行いません
- 追加語彙・抑制語彙・学習語彙をアプリで管理
- 書式付き数値・日付・記号・絵文字・顔文字・部首名からの字形入力
- 欧文(英仏独伊)のサジェスト対応
- 辞書: SudachiDict ベース+Wikipedia由来の言語モデル統計(帰属表示は
  アプリ内ライセンス画面参照)

## 暗号(輸出コンプライアンス)の申告根拠

`ITSAppUsesNonExemptEncryption = NO` で申告する。3260(2026-09-27)以降、アプリ自身は暗号化を行なわない:

- 連絡先キャッシュ(読み→名前の対応表)は App Group のファイルに置き、保護は iOS のファイル保護
  (completeUntilFirstUserAuthentication)に委ねる。バックアップ対象外。
- CryptoKit(AES-GCM)は、旧版が保存した暗号化済みの対応表を読み出す移行のためだけに残る(復号のみ)。

通信も認証も行わない(そもそもネットワークコードが無い)。Apple の輸出規制の免除(OS 提供の
暗号の利用/付随的な用途)に該当するため NO とする。正本は appstore/metadata.md の「輸出コンプライアンス」。

## ShareAlike データの扱い(CC BY-SA)

同梱データのうち次は CC BY-SA 4.0 由来:

- 欧文サジェストの 4 リスト(LatinSuggestionLexicon_{en,fr,de,it}.txt) — wordfreq / Lexique
- Wikipedia 由来の語 n-gram 表(kana_kanji_dictionary.sqlite 内)

third_party/APP_STORE_OPEN_SOURCE_NOTICES.md に「これらのファイル自体は BY-SA で提供し、
暗号化も技術的保護もしていないので自由に取り出して再配布できる」と明記済み(アプリ内の
ライセンス画面から読める)。有償で販売する場合もこの扱いは変わらない — アプリ本体の
販売条件と、同梱データの再配布条件は別物として整理している。

## 出荷前診断のスイッチ(提出時に 1 か所だけ変える)

TestFlight 配布中だけ入れたい計測・可視化は、すべて Swift の
`#if ECRITU_PRERELEASE_DIAGNOSTICS` で括ってある。組み込みは
**Config/Edition.xcconfig の `ECRITU_PRERELEASE_DIAGNOSTICS`** 1 行で決まる。

- `1`(既定) — 開発・TestFlight。でばぐ可視化と診断カウンターが入る
- `0` — **App Store 提出はこちら**。`#if` の中身ごとバイナリから消える

`tools/verify_archive_artifacts.sh` が 1 のままのアーカイブを ❌ で弾くので、
戻し忘れは提出前に止まる。現在この `#if` で括ってあるもの:

- `KeyboardRootView.memoryPressureVisualizationEnabled`(削除キーの黄/橙と数値バッジ)
- 診断カウンター 3 か所(起動回数・セッション UUID・App Group 健全性プローブ)

そのほか一時的な仕掛けを残すときはコメントに `APP_STORE_BLOCKER:` と書く。
検証スクリプトが App/ と KeyboardExtension/ を走査して残っていれば落とす。

## 提出前チェックリスト
- [ ] **でばぐ可視化を戻す**: `KeyboardRootView.memoryPressureVisualizationEnabled` を `false` に(TestFlight 配布中だけ削除キーに黄/橙と数字を出している。2918)

- [ ] 本番バンドルID(.devなし)の App ID / App Group / プロビジョニング
- [ ] Archive は Release 構成(スキームの ArchiveAction は Release 済み)
- [ ] Release 実機での通しテスト(タイピング・変換・設定同期・診断UIが出ないこと)
- [ ] フルアクセスOFFの実機テスト(入力・変換が動く/学習等が効かない)
- [ ] スクリーンショット(6.9"/6.5" 必須サイズ)
- [ ] サポートURL: https://kusakabeyouichi.github.io/ecritu/manual/
- [ ] 年齢区分(4+)/ 価格 / 配信地域
