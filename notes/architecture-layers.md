# 層の分け方(将来の移植を見据えて)

écritu は将来 macOS や Android へ移植する可能性がある。そのとき **ソースを分岐(フォーク)させたくない**。
かな漢字変換の改良はこの先ずっと続くので、分岐させると片方だけ良くなって合流できなくなる。
1 セットのソースに共存させるには、「変換」「UI」「OS・構成」が独立している必要がある。

この文書は、いまの分かれ方と、これから守る規則を書く。**大きな作り直しはしない。**
現状すでにほぼ分かれているので、その形を崩さないことが目的。

---

## 1. 3 つの層

| 層 | 中身 | 依存してよいもの |
|---|---|---|
| 変換 | `KeyboardExtension/KanaKanji*.swift`(19 ファイル) | Foundation、SQLite3 |
| UI | `KeyboardRootView*`、`KeyboardKeyComponents`、`FlickKeyView`、`App/` の画面 | SwiftUI、UIKit、CoreText ほか |
| OS・構成 | `KanaKanjiStore` の入出力、`KeyboardViewController`、ビルド設定 | 何でも(ここが移植時の差し替え点) |

### 変換層(移植で共有したい部分)

2026-09-10 時点で、19 ファイルの import は **Foundation と SQLite3 だけ**。UIKit も SwiftUI も 1 つも無い。
SQLite3 は macOS にも Android にもあるので障害にならない。

含まれるもの: ラティス探索と連文節のコスト計算、活用、送り仮名や助数詞の表記選好、かな正書の判定、
seed 辞書、抑制と追加語彙の適用、候補の並べ替え。**改良が集中するのはここ**。

### OS・構成層(移植で書き換える部分)

OS 依存は `KanaKanjiStore` に集約されている。移植時に差し替えるのはこの 4 種類だけ。

| 依存 | 用途 | 移植先での相当 |
|---|---|---|
| `UserDefaults(suiteName:)` | 設定・学習・追加語彙の共有 | macOS: 同じ。Android: SharedPreferences か DataStore |
| `containerURL(forSecurityApplicationGroupIdentifier:)` | 共有コンテナーの場所 | macOS: App Group か Application Support。Android: filesDir |
| `Bundle(for:)` | 同梱リソース(辞書 sqlite、JSON)の場所 | macOS: 同じ。Android: assets |
| 診断ログの書き出し | 開発ビルドの調査用 | 任意 |

`KanaKanjiConverter` はこれらを一切知らない。`KanaKanjiStore` を通してのみ触る。
移植では **ストアの実装を差し替えれば変換層はそのまま動く**、というのが狙いの形。

---

## 2. 守る規則

**変換層に UI と Apple 専用フレームワークを入れない。**

`tools/verify_conversion_core_portability.sh` がビルドのたびに検査し、破れたらビルドを止める。

```
KeyboardExtension/KanaKanjiTypes.swift:2: error: [変換中核] import UIKit は変換の層に入れられません
```

禁止するのは UIKit / SwiftUI / AppKit / CoreText / CoreGraphics / CoreAnimation / Combine / Contacts / WebKit。
`UserDefaults` と `Bundle` は Foundation なので対象にしない(移植先にも相当物がある)。

### 置き場所に迷ったら

- **文字列や候補の並びを決める** → 変換層
- **色・寸法・字形・入力イベント** → UI 層。実例: 字形の有無の判定(`KanjiGlyphAvailability`)は
  2858 で変換層から UI 層へ移した。「明朝にグリフがあるか」は描画の都合であって変換の都合ではない
- **保存場所・権限・プロセス間の連絡** → OS・構成層

---

## 3. いま無理にやらないこと

- 変換層を別モジュール(Swift Package)に切り出すこと。境界はすでに機械検査で守られており、
  モジュール分割はビルド構成と辞書生成スクリプトに波及する。移植を実際に始めるときでよい
- OS 依存を protocol で抽象化すること。差し替え点は `KanaKanjiStore` の 4 種類だけと分かっているので、
  移植先が決まってから、その OS に合う形で切ればよい。使う予定の無い抽象は保守の負担にしかならない
- Android を Swift で書く前提を置くこと。Kotlin で書き直す判断もありうる。その場合でも
  「変換層が Foundation だけで書かれている」ことは移植の見通しを良くする(辞書と表と規則がそのまま読める)
