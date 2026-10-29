# iPad 版に向けた表示層の切り分け 計画

作業ブランチ: `refactor/shared-input-model`(main から 2026-10-28 に分岐。版 1.1 / 3577 審査中)

## 目的

iPad 版は、キー配列、高さ、フリックや長押しの操作、候補欄の見た目を iPhone 版とまったく別にする予定である(ユーザ 2026-10-28)。
そのとき配列を 2 系統並べても、入力の規則を 2 か所に書かずに済むようにする。
今回の範囲は**切り分けだけ**で、見た目や挙動は変えない。iPad の配列そのもの、`TARGETED_DEVICE_FAMILY` の変更、根元での配列の系統の切り替えは範囲外とする。

## 現状(2026-10-28 検査、edition 3577)

- **分離済み**
  - 変換の中核、候補の並び(`KeyboardCandidateBarModel`)、確定、学習、設定の保存は、すでに表示から分かれている。
  - ビューは 16 個のクロージャーを通してしか controller に触れない。
  - フリックの文字の表と高さの純関数(`KeyboardLayoutMetrics`)は、そのまま再利用できる。
- **ビューに入り込んでいる規則**(このままだと iPad 側に書き写すことになる)
  1. **入力の変換**
     - 英字シフト、カタカナ化、シフト記号(`latinShiftKeyToken`)、確定後にかなへ戻る処理(`KeyboardRootView+Interaction.swift:7-38`)。
     - 前置の濁点(同 :44-85)。
  2. **確定の規則**
     - 絵文字と顔文字はショートカットの履歴に足す。ただし顔文字のショートカット分類から選んだときは足さない(Interaction:113)。
     - 部首は履歴に足さず、確定してかなへ戻る(`+KanjiRadicalLayout.swift:22-26`)。
  3. **状態**
     - `KeyboardRootView` に `@State` が 40 個ある(`KeyboardRootView.swift:90-155`)。
     - 状態遷移は純関数の `KeyboardModeTransition` だが、適用はビューの計算プロパティ `transitionState` の setter で行なっている(:731-760)。
       この setter には、本番でも動く副作用(`MemoryForensics`)が付いている。
  4. **書式化数値**: 入力中の値、出力の組み立て、日付、共有 UserDefaults の読み書きがビューの拡張にある(`+FormattedNumberLayout.swift`)。
  5. **顔文字パネル**: 分類ごとの一覧の組み立てと、分類・行・読みの選択の状態遷移(`+EmojiKaomojiLayouts.swift:19-99`)。
  6. **部首パネル**
     - 漢字と部首の画数の区切りの組み立て(`+KanjiRadicalLayout.swift:826-858`)と、位置→字形の 2 段選択。
     - `KanjiRadicalCatalog.swift` は `RadicalPositionIcon`(Shape)のためだけに SwiftUI を import している。
  7. **モード切替の割り当て**: どのキーのどの向きで何の面を開くかと、70ms の誤タッチ防止(Interaction:87-111, 394-441)。
  8. **高さ**: `PortraitHeightProfile` が iPhone の配列名を列挙している。Duo の余白は controller にある(`+Layout.swift`)。

## 状態の持ち主と作り方(決定事項)

- **持ち主はビュー木の根**
  - モデルは `@State var inputState = KeyboardInputState()` の形で、ビュー木の根が持つ。`makeRootView` から渡したり、外から差し込んだりはしない。
  - 寿命は今の `@State` と同じになる。`rootView` の差し替え(KeyboardViewController.swift:1995)では保たれ、ホストの作り直し(:1721)では初期化される。
  - controller に持たせるのは挙動の変更になるので、今回はやらない。
- **モデルが持たないもの**
  - モデルは、クロージャーと描画設定(`RenderConfiguration` 由来の値)を持たない。差し替えのたびに設定が渡し直されるので、持つと古い値が残る。
  - 設定やクロージャーが要る処理は、メソッドの引数で受け取る(例: `kanaModeSwitcherTapAction`、`onTextInput`)。
  - クロージャーは今どおり、ビューの `let` に置く。
- **作り方**
  - `@Observable` と `@MainActor` で作る(対応は iOS 17 以上、project.pbxproj:1116)。
  - これを選ぶ理由は寿命を今と揃えるためで、描画を減らすためではない。根の `body` はほぼ全部の状態を読んでいるので、描画の回数は今と同じになる見込み。
  - 初期化は今の `@State` の初期値と同じ軽さに保つ。`makeRootView` のたびに評価されるため。
- **`onChange` の扱い**
  - `onInputModeChanged` を呼ぶ合成の `.onChange(of: InputModeObservation)`(KeyboardRootView.swift:1497-1507)は 1 本のまま残す。`.onChange` を増やすと Release WMO が落ちるからである。
  - 値は、モデルの項目から組み立てる。モデルの中から同期で呼ぶ形には変えない。呼ばれる時機が「次の描画」から「即時」に変わるため。
- **`DispatchWorkItem` の捕捉**: 2 度押し待ちとカタカナ確定の表示に使う `DispatchWorkItem` は、モデル(クラス)を弱く捕捉する。
- **`currentInputMode`**: controller 側の写しは今回は残す。

## 状態 40 個の行き先

| 行き先 | 状態 |
|---|---|
| `KeyboardInputState` | `inputMode`, `diacriticMode`, `kanaCharacterMode`, `latinShiftState`, `lastLatinShiftTapAt`, `emojiInputSubmode`, `spaceToastText`, `spaceToastOpacity`(この 8 個は遷移関数が扱う)、`returnToKanaAfterNextCommit`, `isAwaitingLatinModeSwitchSecondTap`, `pendingLatinModeSwitchSecondTapResetWorkItem`, `selectedEmojiCategory`, `selectedSymbolCategory`, `inputModeChangeTrigger`(調査用ログ。モード切替と一緒に動くため) |
| `FormattedNumberState` | `formattedNumberBuffer`, `selectedFormattedNumberCategory`, `formattedNumberGroupingEnabled`, `formattedNumberUnitSelection`, `formattedNumberPrefixSelection`, `formattedNumberCurrencySymbolBefore`, `formattedNumberUnitSpacing`, `formattedNumberDate`, `formattedNumberDateFormatTemplate` |
| `KaomojiPanelState` | `selectedKaomojiCategoryID`, `selectedKaomojiReadingPrefix`, `selectedKaomojiReading` |
| `RadicalPickerState` | `selectedRadicalCategory`, `selectedRadicalForm` |
| ビューに残す(押している間の見た目・触れ方) | `activeLayerIndex`, `isTouchingLeftModeSwitchColumn`, `lastShownSpaceToastTrigger`, `didTriggerComposingCommitLongPress`, `katakanaCommitFeedbackText`, `pendingKatakanaCommitWorkItem`, `formattedNumberDrumFullNameVisible`, `formattedNumberDrumLiveTag`, `lastInputModeObservation`(`onChange` 用), `didDismissFullAccessNotice`(拡張ローカルの保存) |

段 1 で実物を数え直し、この表と食い違えば表を直してから進める。
`selectedEmojiCategory`、`selectedSymbolCategory`、`inputModeChangeTrigger` は、段 1 では移さない。これらを書き換えるのはモード切替の割り当てなので、段 6 で一緒に移す(2026-10-28 段 1 実施時)。

## 段取り(各段 1 コミット以上、見た目と挙動は不変)

各段は次の順で進める。
1. ビューの中にある規則を、まず状態を持たない関数(`static func`)として外へ出し、ビューからそれを呼ぶ形にする。
2. その関数にテストを書く。
3. 状態をモデルへ移す。

ビューの `@State` は、ビュー木の外ではテストから書き換えられない。そのため、移す前の挙動を固定する手段はテストではなく、段ごとの「期待表」(入力と期待する結果の一覧)とする。この期待表は、移す前のコードを読んで作る。

| 段 | 内容 | 新しい型(英語名) |
|---|---|---|
| 1 | 遷移関数が扱う 8 個と、かなへ戻る印、2 度押し待ちをモデルへ移す。`transitionState` の setter に付いた副作用と、`switchInputMode` のつなぎもモデルへ移す | `KeyboardInputState` |
| 2 | 確定の規則を移す。`commitText` の変換(シフト・カタカナ化・シフト記号)を純関数にし、絵文字・顔文字・部首の確定と履歴をモデルのメソッドにする。クロージャーは引数で受け取る | `KeyboardInputState`(メソッド) |
| 3 | 書式化数値の入力中の値、設定、保存、出力をモデルへ移す。ドラムを押している間の見た目はビューに残す | `FormattedNumberState` |
| 4 | 顔文字パネルの選択の遷移と、分類ごとの一覧の組み立てを移す。`KaomojiCategory` をビューの入れ子から外す | `KaomojiPanelState` |
| 5 | 部首パネルの 2 段選択と、画数の区切りの組み立てを純関数とモデルへ移す。`RadicalPositionIcon` を別ファイルへ出し、`KanjiRadicalCatalog` を純粋なデータにする | `RadicalPickerState` |
| 6 | モード切替の割り当て(どの向きで何を開くか)をモデルのメソッドへ移す。ビューの設定(`kanaModeSwitcherTapAction` など)は引数で受け取る。70ms の門番はタッチの事実なので、ビューに残す | `KeyboardInputState` |

- **別に行なう下調べ**(番号の付いた段ではない)
  - 国旗の分類と長押しの名前(`KeyboardRootViewSupportTypes.swift:738-868`)を読み、規則が含まれているかを判定する。
  - 結果は、移す・移さないの判断メモにまとめ、移すなら段を足す。
- **クロージャーをまとめる型**(`KeyboardActions`): 規則を移すのに必須ではないので、今回はやらない。iPad の根の型を作るときに、要るかどうかを決める。
- **高さ**(現状の 8): iPad の配列が決まってから扱う。何を変数にするかは配列次第で、今切ると使わない抽象になる。

## 各段の検証

1. **期待表とテスト**
   - 段の前に、移す規則の期待表を作る(例: 「シフトオンで a → A」「カタカナモードで か → カ」「顔文字のショートカット分類からの確定は履歴に足さない」「画数 3 と 4 の字の間に区切りが 1 つ入る」)。
   - 出した純関数と、新しいモデルの操作に、期待表どおりのテストを書く。
   - 追加したテストは、実装を戻すと赤になることを確かめる。
2. **全テスト**: 分離フロー(`build-for-testing` → `test-without-building`)で回す。速度の門番 `testPerfBudgetKeystrokeSimulation`(100ms)も含めるが、この門番は変換しか測らない。
3. **描画の回数**
   - 決めた打鍵の列を実機で打ち、診断ログの `refreshKeyboardState遅延`(KeyboardViewController.swift:1999-2008)を各段の前後で比べる。
   - DEBUG で `Self._printChanges()` の回数も見て、増えていないことを確かめる。
4. **Release ビルド**: 段ごとに通す(WMO の body 限界)。
5. **実機での確認**: 段 1・2・3・5・6 の後に、ユーザが ⌘R で入れて一通り打つ。
   - 各面を通す: かな、英字(シフト・2 度押し)、数字、絵文字、顔文字(検索を含む)、部首、書式化数値。
   - 段 1 と段 6 では、次の 2 つも確かめる。
     - 入力欄の種類が違う欄へ移ったときに、面が追従すること。
     - 診断のチップでホストを作り直したときに、状態が初期化されること。
6. **新しいファイル**: pbxproj の拡張とテストの **両方のターゲット** に手で登録し、テストターゲットのビルドで確かめる。xcscheme はコミットしない。

## 取り込み

- 1.1 が承認され、1.1.1 の範囲が決まってから main に取り込む。
- それまでテスター向けには配らない。
- 1.1 の急ぎの修正は、main またはタグ `submitted-1.1-3577` から行なう。このブランチには、必要に応じて main を取り込む。

## 結果(2026-10-29、edition 3583)

- **段 1〜6 はすべて実施**
  - コミットは 152727ab・1c7bfbdd・2d077fa2・65ed49a9・f798f171・12a21113。
  - 段ごとに、期待表のテスト、壊すと赤になることの確認、全テスト、Release ビルド、差分のレビュー、実機での確認を通した。見た目と挙動の差は見つかっていない。
- **ビュー木の根の状態**
  - 4 つのモデル(`KeyboardInputState`・`FormattedNumberState`・`KaomojiPanelState`・`RadicalPickerState`)と、押している間の見た目のための `@State` 10 個になった。
  - 10 個の中身は「状態 40 個の行き先」の表の「ビューに残す」と同じ。
- **テスト**: 全部で 1,547 件。この枝で足したのは 108 件(段 1 から順に 12・21・34・18・9・14)。
- **移さなかったもの**
  - `selectModifierMode`(修飾キーの後置の振り分け)。controller のクロージャーと設定を合わせて 11 個の引数が要り、モデルに移すと不自然になるため、ビューに残した。中から呼ぶ空タップの処理はモデルへ移した。
  - 70ms の門番。タッチの事実なので、計画どおりビューに残した。
- **残っている宿題**
  - モデルが、ビューの入れ子の型(`KeyboardRootView.EmojiCategory`・`SymbolCategory`・`KanaModeSwitcherAction`)を参照している。iPad の配列を作るときに、トップレベルへ出す。
  - 描画の回数の比較(各段の検証の 3)は、まだやっていない。段 1 の前の版(3577)と 3583 で、同じ打鍵の列を実機で打って比べる。
- **ついでに見つかった、この枝とは関係のない不具合**: 左下のキーの右・上・下のフリックは、3174 以降は効かない(触れた瞬間に面選択のパレットが出るため)。それなのに設定 E.5 に右・上の割り当てが残っている。1.1.1 で扱う。

### 国旗の下調べ(2026-10-29)

`KeyboardRootViewSupportTypes.swift` の絵文字の区画ビューに、規則が 2 つある。

1. **国旗の並べ分け**(`emojiGridSections`)
   - 国旗を「普通の国 → 海外領土・属領 → その他の旗」の 3 つの区切りに分ける。
   - 判定には `AppleEmojiCatalog.flagOverseasTerritories` と `flagNonCountryNames` を使う。
2. **長押しで出す名前と色の種類**(`emojiLongPressLabels`)
   - 国は `flagOfficialNames` から名前を取り、ふつうの色で出す。
   - 国ではない旗は `flagNonCountryNames` から名前を取り、青系で出す。

- **判断**: 移す。
  - どちらも、データ(`AppleEmojiCatalog`)をどう分類するかの規則で、見た目ではない。iPad の絵文字の一覧でも同じものが要る。
  - 行き先は、表示の型(`EmojiGridCollectionView.Section`、`SymbolInspectBubbleKind`)に依存しない純関数とする。返すのは「区切りごとの絵文字の配列」と「名前と、国か国以外か」。表示の型への詰め替えはビューで行なう。
- **規模**: 小さい(20 行ほどの移動とテスト)。iPad の配列に着手するとき、最初に行なう。今の枝では行なわない。
- **見つけた点(直さない)**: `emojiLongPressLabels` は、描画のたびに国旗の全件を回して辞書を作っている。移すときに、一度だけ作る形にできるかを見る。

## やらないこと

- iPad の配列、`TARGETED_DEVICE_FAMILY`、根元での配列の系統の切り替え。
- 状態の持ち主を controller へ移すこと、`currentInputMode` の写しを外すこと、`KeyboardActions` を作ること。
- 見た目、文言、操作の変更。
- 変換の中核への変更。
