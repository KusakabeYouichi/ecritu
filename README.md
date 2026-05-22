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

## Git フック (推奨)

- 共有スキームファイルの表記ゆれを防ぐため、pre-commit フックを同梱しています。
- 初回のみ、リポジトリルートで `git config core.hooksPath .githooks` を実行してください。
- コミット時に `tools/normalize_unicode_project_names.sh` を実行し、`.xcscheme` が書き換わった場合はコミットを停止して再ステージを促します。

## GitHub 共同開発セットアップ (無料アカウント前提)

- 無料の Apple ID でも、シミュレータ開発とローカル実機検証は可能です。
- 参加者ごとの署名衝突を避けるため、各自で `Config/Signing.local.xcconfig` を作成してください。
	1. `cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig`
	2. `ECRITU_DEVELOPMENT_TEAM` を自分の Team ID に変更
	3. `ECRITU_APP_BUNDLE_IDENTIFIER` を一意な値に変更 (例: `com.<yourname>.ecritu.dev`)
- GitHub 上のブランチ運用と PR 手順は `CONTRIBUTING.md` を参照してください。
- PR 作成時は GitHub Actions の `iOS CI` が自動で走り、署名不要のシミュレータテストを行います。

## MVP の制約
- かな漢字変換は簡易実装(候補選択・学習・ユーザー辞書対応)。高精度辞書は `tools/build_sudachi_index.py` で別途投入。
- 大規模辞書を実機で扱う場合は、`tools/build_kana_kanji_sqlite.py` でSQLite化して `tmp/kana_kanji_dictionary.sqlite` を生成してください。
- `tools/build_kana_kanji_sqlite.py` は `--vocab-json` を複数指定できるため、語彙ファイルを増やす場合もマージして1つのSQLiteにできます。
- エディション番号(`CFBundleVersion`)は `Config/Edition.xcconfig` の `ECRITU_EDITION_NUMBER` を単一ソースとして参照します。
- VSCode のビルドタスクは `tools/xcodebuild_with_edition_bump.sh` を経由し、ビルド系コマンド実行のたびに番号更新を自動で行います。
- 同時に `Config/Edition.xcconfig` の `ECRITU_EDITION_UPDATED_AT` も現在日時へ自動更新します。
- 同時に `App/ContentView.swift` 内の `editionUpdatedAtRaw` も同期更新され、コンテナーアプリ表示へ反映されます。
- エディション番号は実質ビルド番号として扱い、テスト用ビルドや失敗ビルドで増えても巻き戻しません。
- Xcode側ビルドは `Config/Edition.xcconfig` の現在値をそのまま使います(自動更新しません)。
- システム語彙は `tmp/ÉcrituPremierVocab.json` (Sudachi由来) に加え、補助語彙 `tmp/ÉcrituSecondVocab.json` も読み込みます。
- SudachiDict CSV の初回準備は `bash tools/fetch_sudachi_raw.sh` を実行してください(`tmp/sudachi_raw/` を作成します)。
- 既存CSVを取り直す場合は `bash tools/fetch_sudachi_raw.sh --force` を使います。
- 補助語彙 `tmp/ÉcrituSecondVocab.json` は `references/ryukyu.plist` / `references/vin.plist` / `references/apple.plist` からビルド時に生成します。
- 追加語彙の初期投入データ `InitialAjoutVocabMigration.json` は `references/void.plist` からビルド時に生成し、更新時はシグネチャ比較で再マージされます。
- clone直後のビルド失敗を避けるため、拡張バンドルには `KeyboardExtension/DefaultDictionaryResources/` の軽量プレースホルダー辞書を同梱しています。
- 実運用の高精度辞書を使う場合は、`tools/build_sudachi_index.py` / `tools/build_kana_kanji_sqlite.py` で `tmp/` 配下に生成し、`tools/install_simulator_kana_dictionary.sh` でシミュレータのApp Groupへ反映してください。
- 第1語彙が0件になる環境の切り分けには、`bash tools/diagnose_kana_dictionary.sh` を実行してください。`tmp/`・ビルド済み `.app`・シミュレータ App Group の辞書有無/件数を一括で確認できます。
- 他環境の調査では、上記スクリプトの出力全文を共有すると原因を特定しやすくなります。
- Xcodeで `KeyboardExtension` をビルドすると、`tools/refresh_simulator_dictionary_on_build.sh` が毎回実行され、`tmp/sudachi_raw` にCSVが無い場合は `tools/fetch_sudachi_raw.sh` の自動実行を試みます。
- 自動取得に成功すると、そのまま `tmp/` の辞書再生成まで実行します。自動取得に失敗した場合はビルドを止めず、同梱プレースホルダー辞書で継続します。
- Sudachi CSV が最終的に見つからない場合は、既定で「フォールバック用 seed 辞書(約108エントリー)のみでビルド継続するか」を確認します（拒否時はビルド中止）。
- 自動取得を無効化する場合は環境変数 `ECRITU_AUTO_FETCH_SUDACHI_ON_BUILD=0` を設定してください（必要なら `ECRITU_AUTO_FETCH_SUDACHI_INCLUDE_FULL=1` で full 辞書も自動取得対象にできます）。
- フォールバック確認を無効化する場合は `ECRITU_PROMPT_ON_SUDACHI_FALLBACK=0`、非対話環境の既定動作を中止側に寄せる場合は `ECRITU_SUDACHI_FALLBACK_NONINTERACTIVE_DEFAULT=abort` を設定してください（確認ダイアログを表示できない環境でもこの既定値を使用します）。
- 同スクリプトは、生成済み `tmp/` 辞書があれば拡張バンドル内リソースを上書きするため、実機ビルドでもシード辞書ではなく生成辞書を同梱できます。
- App Group への辞書反映(`tools/install_simulator_kana_dictionary.sh`)はシミュレータビルド時のみ自動実行します。
- Sudachi CSV が無い環境では自動生成をスキップし、同梱プレースホルダー辞書でビルドを継続します。
- SudachiDict 関連の法的文書は `third_party/sudachidict/LICENSE-2.0.txt` と `third_party/sudachidict/LEGAL` をソース同梱しています。
- コンテナーアプリには「オープンソースライセンス」セクションを実装し、上記文書をアプリ内で閲覧できます（App Store 配布時の確認導線）。
- `tools/verify_third_party_license_assets.sh` で、配布前にライセンス文書の同梱漏れ（ソース/アプリバンドル）を検証できます。
- 他の開発環境で実機ビルドする場合は、`Config/Signing.local.xcconfig.example` を `Config/Signing.local.xcconfig` としてコピーし、`ECRITU_DEVELOPMENT_TEAM` と `ECRITU_APP_BUNDLE_IDENTIFIER` を各自の値に変更してください。
- App Group は既定で `group.$(ECRITU_APP_BUNDLE_IDENTIFIER)` を使います。実機署名時はアプリ/拡張の両ターゲットで同じ Team / Bundle ID 系列 / App Group になるよう揃えてください。
- Sudachi前処理では1文字読みも収録対象としつつ、1文字読み専用の候補数・候補長上限でノイズ増加を抑制します。
- Sudachi前処理では漢字以外の候補(カタカナ等)も保持できます。
- 追加辞書の初期データは `KeyboardExtension/InitialAjoutVocabMigration.json` に同梱され、ビルドごとに拡張バンドルから読み込まれます。
- 濁点/半濁点の後変換は未実装
- 一部フィールド(パスワードなど)ではサードパーティキーボードは利用不可

この状態で「フリック入力 + かな漢字変換」の動作確認ができます。
