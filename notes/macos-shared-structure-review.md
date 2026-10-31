# macOS 版を同じリポジトリーで作るための構成点検(2026-11-01、edition 3630)

前提: macOS 版は IMKit の入力メソッド(IMKInputController)として作り、iPhone 版と同じリポジトリーで開発する。
変換・語彙・辞書生成は 1 セットのまま両方に効かせる。3 リポジトリー化はしない(第三の利用者が出るまで)。

この文書は「今どうなっているか(実測)」「macOS 版で何が共有でき、何が無いか」「分け方の案と移行の順番」をまとめたもの。
層の考え方そのものは notes/architecture-layers.md、iPad 向けの分離は docs/ipad-layout-separation-plan.md を参照。

## 1. 今の構成(実測)

ターゲットは 3 つ(écritu=コンテナーアプリ、KeyboardExtension、écrituTests)。Swift Package は無く、各ターゲットがソースを直接コンパイルする。

| 層 | 主なファイル | 行数 | import |
|---|---|---|---|
| 変換中核 | KanaKanji*.swift(19 本)、KakikaeTable、KanaGakiTable、SupplementalVocabCompactStore 等 | 約 32,000 | Foundation、SQLite3 だけ(ビルドフェーズ tools/verify_conversion_core_portability.sh で強制) |
| 入力の状態(UI 無し) | KeyboardInputState、KeyboardModeTransition、FormattedNumberState、KaomojiPanelState、RadicalPickerState、FlickKanaMap/FlickKanaLayout、各 Catalog | 約 7,500 | Foundation、Observation(FlickKanaMap は CoreGraphics) |
| iOS の入力コントローラー | KeyboardViewController(+8 分割) | 約 9,600 | UIKit、SwiftUI |
| iOS の画面 | KeyboardRootView(+9 分割)、FlickKeyView、KeyboardKeyComponents 等 | 約 12,500 | SwiftUI、UIKit |
| コンテナーアプリ | App/*.swift | 約 12,800 | SwiftUI、UIKit、Contacts |
| テスト | Tests/*.swift(回帰 26,000 行を含む) | 約 30,000 | XCTest(回帰テストは SwiftUI、ModeTransition は UIKit も) |

OS に触る場所(変換中核の中):
- KanaKanjiStore: `UserDefaults(suiteName:)`、`FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`、`Bundle(for: KanaKanjiStore.self)`(資源の読み込み 7 か所)、学習語彙ファイルの読み書き
- KanaKanjiConverter+MultiClause: `ProcessInfo`(トレース用の環境変数。移植の障害ではない)

資源(KeyboardExtension のバンドルに Copy Bundle Resources で入るもの): 辞書 kana_kanji_dictionary.sqlite(81MB)、語彙 JSON 7 本、欧文サジェストの語彙 5 本、bushu/grammaire の plist、KanjiRadicalIndex。
これらは tools/refresh_simulator_dictionary_on_build.sh(ビルドフェーズ)が references/*.plist と third_party/sudachidict から tmp/ に生成し、バンドルへ複製する。

## 2. macOS 版で共有できるもの・書き直すもの・まだ無いもの

共有できる(そのまま): 変換中核、入力の状態、語彙データと辞書生成、設定の保存形式(App Group の UserDefaults と Darwin 通知。macOS でも同じ仕組みが使える)。

書き直す(プラットフォーム固有): 画面(SwiftUI/UIKit の面・候補欄)、UIInputViewController と textDocumentProxy の扱い、高さの計算(KeyboardLayoutMetrics は UIKit 前提で iOS 専用のまま)。

まだ無い(作る必要がある): **入力セッション**。「かなを溜める→変換を頼む→候補を並べる→確定する→学習する→未確定を本文へ映す」の流れが、今は KeyboardViewController の拡張(InputHandling 1,188 行、MarkedTextCommit 856 行、PlainTextComposition 330 行、CandidatePresentation 748 行)に textDocumentProxy と一緒に書かれている。macOS の IMKit は `insertText`/`setMarkedText`/候補ウインドウの API が別物なので、この流れを OS に依存しない形に切り出さないと、同じ処理を 2 つ持つことになる。
iPad 監査(docs/ipad-layout-separation-plan.md)で挙げた「ビュー側の commitText(ラテン文字のシフト・カタカナ化・前置濁点・かなへ戻る)」も同じ場所に入るべきもので、未着手。

## 3. 問題点(影響の大きい順)

1. **設定の型と鍵が二重定義**。App/SettingsModels.swift の enum(KanaLayoutOption 等 20 個)と拡張側の enum(KanaLayoutMode 等 20 個)が同じ rawValue を別々に持ち、鍵の文字列も App(SettingsKeys)と拡張(SharedDefaultsKeys、99 本)で別々に書いてある。一致はコメントと目視だけ。3618 の E.5 で初期値のずれ(🌐 上フリック)が実機で露見したのはこの構造のため。macOS 版が加わると三重になる。
2. **入力セッションが iOS のコントローラーに埋まっている**(上記)。textDocumentProxy への参照 66 か所。
3. **変換中核に module の境界が無い**。ポータビリティーは検査スクリプト頼み。Mac ターゲットを足すと、約 60 本のファイルの pbxproj 手動登録が 3 ターゲット分になる(xcodeproj gem は é の scheme を壊す。project_pbxproj_xcodeproj_gem)。
4. **資源の複製がビルドフェーズ script に依存**。Mac ターゲットにも同じ資源(81MB の辞書を含む)が要る。共有のリソースバンドルが無い。
5. **テストが UI フレームワークに依存**。回帰テスト(26,000 行)は KeyboardRootView を 2 か所で生成するため SwiftUI を import し、iOS シミュレーターでしか回らない。変換のテストは本来 macOS 上で直接回せる(シミュレーター不要で速く、⌘R と DerivedData のロックも争わない)。
6. KanaKanjiStore の資源読み込みが `Bundle(for:)` 7 か所に分散(Package 化すると `Bundle.module` へ一括で変わる)。
7. 小さいもの: KanjiRadicalCatalog が SwiftUI を import(iPad 監査で既知)、FlickKanaMap が CoreGraphics(macOS でも可、問題なし)。

## 4. 提案する構成(同じリポジトリー、ローカル Swift Package)

```
Packages/
  EcrituSettings/     設定の鍵と enum の単一定義(App・拡張・Mac が共有。rawValue の一致を型で保証)
  EcrituConversion/   変換中核 + KanaKanjiStore。OS 依存 4 点は protocol(ConversionEnvironment)で注入
                      資源(辞書 sqlite・JSON・lexicon)は Package の resources として同梱(Bundle.module)
  EcrituInput/        入力の状態(InputState/ModeTransition/FormattedNumberState/各 Catalog/FlickKana*)+ 新設の入力セッション
                      (TextTarget protocol: insert/replaceMarked/deleteBackward/contextBefore を iOS と macOS が実装)
App/                  iOS コンテナーアプリ(今のまま)
KeyboardExtension/    iOS のキーボード(画面・UIInputViewController・TextTarget の iOS 実装)
MacInputMethod/       macOS の入力メソッド(IMKInputController・候補ウインドウ・TextTarget の macOS 実装)+ 設定画面
Tests/                UI を伴うテストだけ残し、変換・入力のテストは各 Package の test target へ
```

Package にする利点: ターゲット追加のたびの pbxproj 手動登録が無くなる(Package は Package.swift で完結)。ポータビリティーは「EcrituConversion が UIKit/AppKit に依存できない」ことで自然に守られる(検査スクリプトは残してもよい)。
辞書生成(tools/、tmp/)はそのままで、出力先を Package の Resources に向ける。

## 5. 移行の順番(安全な順。各段で全網テストと実機確認)

1. **EcrituSettings**(1〜2 日): 鍵と enum を 1 か所にし、App と拡張の二重定義を消す。macOS の前でも効く(3618 型のずれを構造で防ぐ)。
2. **EcrituConversion**(2〜3 日): KanaKanji*.swift と資源を Package へ移す。KanaKanjiStore の 4 点を protocol に。pbxproj は 2 ターゲットから約 25 本を外す。Release(WMO)の確認必須。
3. **テストの分離**(1 日): 回帰テストから KeyboardRootView 生成の 2 か所を外し、変換テストを Package 側へ。macOS で `swift test` が回るようにする(速度と ⌘R 競合の解消)。
4. **EcrituInput と入力セッション**(1〜2 週): iPad 監査の残りと同じ作業。textDocumentProxy を TextTarget に隠す。ここが macOS 版の本体を支える。
5. **MacInputMethod**(規模は別途): IMKit の骨組み、候補ウインドウ、設定画面(App Group は同じ team で使える。Darwin 通知も同じ)。CI に macOS の Release ジョブを足す。

リスクと注意:
- é を含むプロジェクト名と scheme(アクセントの NFC/NFD。feedback_accent_normalization_compromises)。Package 名は ASCII にする。
- Release の WMO で body が巨大になる既知の問題(project_release_wmo_body_limit)。Package 化は WMO の単位を小さくするので有利。
- ⌘R の速さ(連語表 Swift の 257 秒)は Package 化で変わらないが、変換中核が別 module になるので UI だけの変更で再コンパイルされなくなる。
- 辞書 sqlite(81MB)を Package resources にすると App にも入る形になりやすい。App は辞書を使わない(語彙の一覧表示のみ)ので、資源は EcrituConversion の「別 Package(EcrituDictionaryData)」に分け、拡張と Mac だけが依存する。

## 6. やらないこと

- 3 リポジトリー化(変換と語彙が毎日動くので版合わせが重い)。
- 使う予定の無い protocol 抽象(差し替え点は 4 つと分かっている。Package 化のときに切る)。
- 辞書生成の二重化(tools/ は 1 セット。出力先だけ増やす)。
