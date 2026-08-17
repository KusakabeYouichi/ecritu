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
> device.

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

## 提出前チェックリスト

- [ ] 本番バンドルID(.devなし)の App ID / App Group / プロビジョニング
- [ ] Archive は Release 構成(スキームの ArchiveAction は Release 済み)
- [ ] Release 実機での通しテスト(タイピング・変換・設定同期・診断UIが出ないこと)
- [ ] フルアクセスOFFの実機テスト(入力・変換が動く/学習等が効かない)
- [ ] スクリーンショット(6.9"/6.5" 必須サイズ)
- [ ] サポートURL: https://kusakabeyouichi.github.io/ecritu/manual/
- [ ] 年齢区分(4+)/ 価格 / 配信地域
