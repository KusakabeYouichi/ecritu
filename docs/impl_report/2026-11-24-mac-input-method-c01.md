---
title: macOS 用の日本語入力 第 1 区切り(ローマ字・ライヴ変換・候補選択)
date: 2026-11-24
branch: pour-mac
cycle: c01
scale: 大
stages:
  env: done
  0_spec: done(設計書なし。notes/macos-shared-structure-review.md を参照し、単体の計画で進めた)
  1_design: done
  2_test_design: done
  3_adversarial: done(初回 25 件 + 読み直し 9 件)
  4_implement: done
  5_code_review: done(2 回。高 0)
  6_tests: done(テストを読む 3 回。「赤を先に見る」は skipped: 全ファイルが新規で、実装を退避するとコンパイルできず全件が赤になるだけのため。代わりにテストを読む役が、改訂前の実装と区別できるかを 1 本ずつ見た)
  7_e2e: skipped(入力ソースの登録と実際の打鍵は [システム設定] の手作業が要り、自動で確かめられない。ユーザの確認待ち)
  8_reality_check: done
  9_report: done
adversarial:
  findings: 34
  rejected: 2
---

# macOS 用の日本語入力 第 1 区切り

## 何を作ったか

écritu の変換エンジン(Packages/EcrituConversion)をそのまま使う、macOS の入力メソッド(InputMethodKit)の最初の版。
ローマ字で打ち、打鍵ごとに変換結果を未確定に表示し(ライヴ変換)、Space で候補を選び、Enter で確定する。

| 場所 | 内容 |
|---|---|
| Packages/EcrituInput/ | UI を持たない入力ロジック。ローマ字→かな(RomajiComposer)、入力の状態機械(InputSession)。依存は Foundation だけ |
| MacInputMethod/ | Mac のターゲット。IMKInputController、キーの読み替え、自前の候補ウインドウ、エンジンの呼び出し(ConversionService)、Info.plist |
| MacInputMethod/EcrituPourMac.xcodeproj | tools/generate_mac_project.rb の生成物(正は生成スクリプト。手で直さない) |
| tools/install_mac_input_method.sh | ビルド済みの ecritu.app を ~/Library/Input Methods へ入れる(実行するのはユーザ) |
| Packages/EcrituConversion/…/KanaKanjiStore.swift | `sharedContainerURLOverride` を public に(1 語。挙動は変えない) |

iOS のプロジェクト・ソース・既存のスクリプトは変更していない。

## 仕様(ユーザが決めたこと・メインが置いたこと)

ユーザが決めたこと:
- Xcode プロジェクトは別(iOS の écritu.xcodeproj に触れない)
- ローマ字打ちだけ。U+FF00〜U+FFFD の文字は入力できない。数字・ラテン文字は未確定にしない
- 未確定中の『、』『。』はそこで自動確定。未確定が無いときの Space は U+0020
- 単文節と連文節の合流・後処理は今回 Mac 側に置き、次の区切りで iOS のものをパッケージへ移して共有する

メインが置いたこと:
- カタカナ入力モードは作らない。未確定中の F7 / ⌃K で一時的にカタカナ表示、F6 / ⌃J / Escape でひらがな表示。確定は Enter
- Shift+字(大文字)で始めたラテン文字は、Space・かなキー・Enter などまで直接入力(記号も通す)
- 未確定が無いときの数字・Space・対応の無い記号は、入力メソッドが横取りせずアプリへ通す
- 記号の対応: `,`→、 `.`→。 `[`→『 `]`→』(当初は「 」。ユーザ指定で二重括弧に改めた)`{`→「 `}`→」(ユーザ指定)`/`→・ `~`→〜。未確定が無く直前が数字のとき `,` `.` `/` はそのまま通す(3.5、1,000、11/24)
- ⇧← / ⇧→ で変換の対象を先頭から伸縮し、その範囲の候補を選んで確定、残りはライヴ変換を続ける
- 未確定が 20 文字を超えたら、変換が安定している先頭側(全体の 1 位 == 先頭側の 1 位 + 残り 8 文字の 1 位)を自動で確定する。24 文字を超えたら無条件に確定する
- 学習は候補を選んで確定したときだけ(ライヴ変換のままの確定、カタカナ表示の確定は学習しない)
- 署名は ad hoc。bundle ID は `jp.or.pleiades.merope.inputmethod.ecritu`(ユーザ未確認)
- エンジンの設定は現代的初期設定の値を固定で入れる(設定画面は無い)
- 常駐の形式は `LSUIElement`(純正の入力メソッドがどれもこの形式だったので合わせた。当初案の `LSBackgroundOnly` はやめた)
- ローマ字表には、設計で名指ししなかった慣用の綴りも入れた(`xwa` / `lwa`→ゎ、`xtsu` / `ltsu`→っ、`dya` 行→ぢゃ行)

## 主要な実装の詳細

- **InputSession**(Packages/EcrituInput): 状態は 空 / 入力中 / 選択中 / ラテン文字の連なり。`handle(_ key:) -> InputResult`(確定する文字列・未確定の区切り・候補一覧・キーを通すか)。
  変換は `ConversionProviding`(candidates / learn)を注入。候補の列から U+FF00...U+FFFD を含む候補と空の文字列を落とし、空になれば読みそのものを使う
- **RomajiComposer**: ヘボン式と訓令式、小書き(x / l)、促音、`nn` / `n'`、外来音。規則に当たらない字はラテン文字のまま text に残り、その間は変換しない
- **ConversionService**(Mac): iOS の KeyboardViewController+CandidatePresentation.swift と同じ順・同じ引数で、合流(256-376)→ 24 件に切る → 提示の整え(651-743 の写し、約 70 行)→ 後処理(501-545 の public 関数)→ 重複と U+FF00...U+FFFD の除外 → 末尾に読み。
  直前の確定済み 1 文字を渡すので、数字の直後の助数詞が上がる。結果の覚え書き(読み, 直前の 1 文字)を 64 件まで持ち、learn で捨てる
- **呼んでいない iOS の処理**(次の区切りで共有化する材料): ユーザ辞書・連絡先・絵文字の読みの合流、度記号の字形、相対日付
- **コントローラー**: モードは `setValue(_:forTag:client:)` だけを正にする。⌘ / ⌥ / ほかの ⌃ 付き・ASCII 以外の文字・マウスは、未確定を確定してから通す
- **保存先**: 学習は UserDefaults の suite `jp.or.pleiades.merope.inputmethod.ecritu.conversion`。App Group のコンテナーは引かない
- **資源**: iOS と同じ辞書スクリプト(tools/refresh_simulator_dictionary_on_build.sh)を Mac のビルドフェーズから呼ぶ。部首の索引と欧文サジェストの語彙は入れていない

## 検証結果

| 検証 | 結果 |
|---|---|
| `swift test`(Packages/EcrituInput) | 94 件成功、失敗 0 |
| `xcodebuild test`(EcrituPourMac、実辞書) | 32 件成功、失敗 0、expected failure 1(下の速度) |
| ビルド | BUILD SUCCEEDED |
| .app の Resources | 指定の 14 本すべてあり、辞書 86MB |
| 実行ファイルの直接起動 | コントローラーのクラスの解決・IMKServer の作成・辞書を開く、の 3 つとも成功のログ |
| iOS 側 | 変更は public の 1 語。同じソースが Mac のビルドで通ることで確認。iOS シミュレーターのテストは回していない |

実辞書で確かめた主なもの: `かんじ` に 漢字 / 感じ / 幹事、`きょうはいいてんきです` → 今日はいい天気です、直前が数字のとき `こ`→個 / `にん`→人 / `ばい`→倍 / `じ`→次、
学習の前後で 1 位が変わる、`ほんと` の 1 位が 本当 でない、`できる` が 出来る より前、`ずかんで` → 図鑑で。

U+FF00...U+FFFD の除外: 49 の読みを調べたが、エンジンがこの範囲の文字を含む候補を返す読みは見つからなかった。
そのため、ConversionService 側の除外は実辞書のテストでは効いていることを示せていない(セッション側の除外は偽の変換のテスト S47 / S48 で確かめている)。

速度(Mac、Debug 構成。変換のパッケージは Debug でも最適化あり):
- 測り方: 長さごとに別の読み 5 つを使い、1 回ごとに新しいサービスを作って preload してから 1 回測った中央値(結果の覚え書きに当たらないようにするため。同じサービスで同じ読みを繰り返す測り方では 10 文字 20〜27ms、20 文字 62ms だった)
- 変換 1 回の中央値: 10 文字 33.7ms / 20 文字 72.4ms / 24 文字 84.4ms(14:59 の実行。最後の実行では 30.1 / 64.6 / 87.8ms で、実行ごとに 1 割ほど揺れる)
- 自動確定の判定が入る打鍵(21〜23 文字め): 約 70ms。確定の後(24〜26 文字め): 15〜21ms(3 回の中央値。最後の実行では 21 文字めの 1 回めだけ 151ms だった。起動直後の最初の判定は遅い)
- 目安(20 文字で 50ms 未満)は未達。テストには `XCTExpectFailure(strict)` で既知の未達として残した

## 未検証(ユーザの手作業が要る)

- 入力ソースとして登録できるか(Info.plist の入力モードの定義、ad hoc 署名)
- 文字種(`tsInputMethodCharacterRepertoireKey`)は [Hira, Kana, Latn] の仮置き。`Hani` が要るかは、照合できる資料が手元に無く決められなかった(純正の日本語入力の Info.plist は IMK のキーを持たない)
- `setValue(_:forTag:client:)` に渡る値が Info.plist の入力モードのキー(`com.apple.inputmethod.Japanese` など)であること
- 英数キー / かなキーでの切り替え、新しいアプリに移ったときのモードの同期
- 候補ウインドウの表示と位置(画面の下端で切れないか、全画面のアプリの上に出るか)
- 実際の打鍵(確定を挿入してからキーを通す順がアプリで保たれるか、マウスで移動したときに直前の文字が残らないか)

## 敵対的検証で却下した指摘

- 初回 9(コンテナーアプリの移行が無いと語彙が効かない): 実測で、初期語彙はエンジンがバンドルから直接読むと分かったため
- 読み直しのテスト指摘 2(速度を Debug 構成で測っている): 変換のパッケージは Debug でも最適化しているため記録だけにした。予算の最終判断は非同期化のときに Release の値で行なう

## 残課題 / 申し送り

1. **変換の非同期化**(最優先): 同期のライヴ変換は 20 文字で約 70ms かかり、打鍵の表示がその分遅れる。打った字をすぐ表示し、変換結果は届き次第差し替える方式にする。済んだら C13 の expected failure が strict で落ちて知らせる
2. **合流・後処理の共有化**: ConversionService の合流・提示の整え(写し)・後処理の呼び出し順を、iOS の KeyboardViewController から Packages/EcrituConversion へ移し、iOS と Mac が同じものを呼ぶ
3. **設定ウインドウと語彙**: 追加語彙・抑制語彙の登録と削除、OS のユーザ辞書(テキスト置換)を読めるかの調査(ユーザ要望 2026-11-24)
4. ユーザの判断待ち: bundle ID / 記号の対応(`[ ] / ~`、数字の直後の `,` `.` を通す件。『合計は5。』が打てない)/ `2` の後の `じ` が 次 になる件(エンジンの表のとおり。iPhone での並びは未確認)
5. 中ほどの文節の伸縮(エンジンに文節境界を返す公開 API が要る)、F10(打ったままのラテン文字)、絵文字の読み・相対日付・連絡先
6. 配布: Developer ID 署名と公証、Mac App Store に出せるかの確認
7. 辞書スクリプトは sqlite を毎回作り直す(build_suffix_vocab.py が毎回書き直すため。既存の挙動で、iOS のビルドも同じ)
8. CI に Mac のビルドを足すかは未着手
9. KanaKanjiStore.swift の `sharedContainerURLOverride` のコメントは「テスト用」のまま(今回は 1 語だけの変更に限った)。Mac では本番の経路で使うので、共有化の区切りで保存先の渡し方ごと直す
