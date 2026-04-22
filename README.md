# écritu: フリックかな入力 MVP (SwiftUI + Keyboard Extension)

このフォルダーは、iPhone向けの「フリックでひらがなを直接入力する」最小実装です。

## 含まれるもの

- SwiftUIベースのフリックキー UI
- 2段のかなキー(あ/か/さ/た/な, は/ま/や/ら/わ)
- 削除・空白・改行・地球儀キー(次のキーボード)
- `UIInputViewController` と `textDocumentProxy` で直接入力

## フォルダー構成

- `App/` : ホストアプリ用の画面
- `KeyboardExtension/` : カスタムキーボード拡張本体

## Xcode での組み込み手順

1. iOS App プロジェクトを新規作成(SwiftUI, Swift)。
2. `File > New > Target... > Custom Keyboard Extension` を追加。
3. このフォルダーの `App/` の2ファイルをアプリターゲットへ追加。
4. このフォルダーの `KeyboardExtension/` の Swift ファイルを拡張ターゲットへ追加。
5. 拡張ターゲットの `Info.plist` を本フォルダーの `KeyboardExtension/Info.plist` 相当に設定。
6. 拡張ターゲットの Principal Class が `$(PRODUCT_MODULE_NAME).KeyboardViewController` であることを確認。
7. 実機でビルドし、iOS設定でキーボードを有効化。

## iPhone での有効化

1. `設定 > 一般 > キーボード > キーボード > 新しいキーボードを追加`
2. 作成したキーボードを選択
3. 入力画面で地球儀キーを押して切り替え

## MVP の制約
- かな漢字変換は簡易実装(候補選択・学習・ユーザー辞書対応)。高精度辞書は `tools/build_sudachi_index.py` で別途投入。
- Sudachi前処理では漢字以外の候補(カタカナ等)も保持できます。
- 追加辞書の初期データは `KeyboardExtension/InitialAjoutVocabMigration.json` に同梱され、ビルドごとに拡張バンドルから読み込まれます。
- 濁点/半濁点の後変換は未実装
- 一部フィールド(パスワードなど)ではサードパーティキーボードは利用不可

この状態で「フリック入力 + かな漢字変換」の動作確認ができます。
