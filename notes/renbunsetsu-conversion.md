# 連文節変換 導入検討メモ

Apple 純正 IME 相当の連文節変換(複数文節を一括変換)を écritu に導入するかどうか、
方針 A/B/C を比較し、最小構成である C のプロトタイプ設計をまとめる。

---

## 1. 現状(確認済みの事実)

écritu の変換は **単文節 + ヒューリスティック連結** であり、連文節の基盤は持たない。

- 変換器 `KanaKanjiConverter` に **ラティス / ビタビ / 連接(connection)コスト処理は皆無**。
- 辞書 `kana_kanji_dictionary.sqlite` は `dictionary_entries(reading, candidate, rank)` のみ。
  **語コスト・連接 ID を持たない**(`candidate_sources` / `inflection_classes` は補助メタのみ)。
- `candidates(for reading:limit:systemCandidateMode:) -> [String]`
  (`KeyboardExtension/KanaKanjiConverter.swift:457`)は、**読み全体を 1 単位**として
  `scores: [String: Int]` を積み上げ、スコア降順で整列して上位 N 件を返す。
- 呼び出し側(`KeyboardViewController+InputHandling.swift:194` ほか)は
  **未確定読み全体をそのまま** `candidates(for:)` に渡す = 全体を 1 文節扱い。
- 複合はルールベースの糊付けのみ:
  前置パススルー(`お/ご`)、後置パススルー(深さ 3, `maxPostfixPassthroughDepth`)、
  数詞+桁+助数詞、名詞+漢字接辞 など(`candidates()` 内で `addCandidates(baseScore:)` で加点)。
- Sudachi 生データ(`tmp/sudachi_raw/**/*_lex.csv`)は left/right ID・語コスト・連接行列を
  含むが、`build_sudachi_index.py` は **left/right ID を読みつつ捨てている**(`SUDACHI_*_ID_INDEX`)。

つまり「全体を 1 読みとして辞書引き+接辞連結」しており、
`きょうはいいてんきです` のような複数文節入力は現状うまく変換できない。

---

## 2. 連文節変換に必要な要素

| 要素 | 内容 | 現状 |
|---|---|---|
| 分割ラティス | 読みを語/文節に分ける全経路をグラフ化 | なし |
| 言語モデル(LM: Language Model、連接コスト) | 語の生起コスト + 品詞間の接続コスト(**本丸**) | なし |
| 経路探索 | ビタビ/最短経路で文全体の最尤系列を選ぶ | なし |
| コスト付き辞書 | 語コスト + 連接 ID を持つ辞書 | 素データにはあるが未活用 |

加えてキーボード拡張特有の制約:
- **メモリ(jetsam)**: 連接行列 + 充実辞書は重い。本プロジェクトは既に
  `phys_footprint` ベースのメモリ失セーフと戦っている。
- **レイテンシ**: 打鍵ごとにラティス探索を端末上で回す必要。

---

## 3. 方針 A / B / C の比較

| 観点 | A: Sudachi コストで自前ビタビ | B: azooKey エンジン統合 | C: 軽量 bigram 再ランク(最小) |
|---|---|---|---|
| 変換品質 | ◎(正統・連文節) | ◎(学習済み LM、実績あり) | △〜○(分割改善+流暢さ選択) |
| 実装量 | 大(コア新規) | 中(統合+移行) | 小〜中(既存 `candidates()` 再利用) |
| 依存追加 | なし(Sudachi 素データ流用) | 大(SPM + 辞書/LM 資産) | なし |
| メモリ footprint | 中〜大(連接行列 + 辞書) | 大(要実測) | 小(圧縮 bigram のみ) |
| レイテンシ | 中(ラティス探索) | 中 | 小(数分割 × 既存変換 + 加点) |
| 既存資産活用 | 高(Sudachi 取込済み) | 低(辞書を作り直し/差替) | 最高(現行エンジンそのまま) |
| 段階導入 | しにくい(一括) | しにくい | しやすい(フラグで on/off) |
| 主リスク | メモリ/レイテンシ、LM 調整 | 依存の巨大さ、footprint、既存挙動との差異 | 品質が中庸で頭打ちの可能性 |
| 目安工数 | 数週間 | 1〜2 週間+検証 | 数日〜1 週間 |

### A. Sudachi コストで自前ビタビ
`build_sudachi_index.py` が既に読んでいる left/right ID・語コストと、Sudachi の
連接行列(`matrix.def`)を辞書に取り込み、MeCab/Sudachi 流の最小コスト法を実装する。
- 長所: 正統・依存なし・素データを持っている。
- 短所: コア新規実装。連接行列(数十 MB クラス)の圧縮・mmap 前提。品質チューニング要。

### B. azooKey エンジン統合
iOS キーボード向け Swift 製・連文節対応・学習済み LM 入りの OSS
(`AzooKeyKanaKanjiConverter`)を統合する。
- 長所: 品質への最短路。学習・変換の作り込みを再利用。
- 短所: 大きな依存。辞書/LM 資産の footprint 実測が必須。écritu 独自の
  追加語彙・記号/国旗/通貨の資産(references plist 群)を新エンジンへ再マッピングする移行コスト。

### C. 軽量 bigram 再ランク(最小構成)
現行 `candidates()` をそのまま「文節変換器」として再利用し、
**分割の列挙 + 軽量言語モデルでの経路スコアリング**だけを上に足す。
- 長所: 既存エンジン不変・依存なし・フラグで段階導入・低メモリ。
- 短所: 真のラティス最適化ではないため品質は中庸。ただし体感の "連文節っぽさ" は得やすい。

---

## 4. C プロトタイプ設計

### 4.1 目的 / 非目的
- **目的**: 未確定読み全体を、少数の妥当な文節分割に切り、各文節を既存 `candidates()` で
  変換し、軽量 bigram で最尤の連結を選んで **連文節候補を 1〜数件** 提示する。
- **非目的**: 全語彙にわたる厳密なラティス最適化(それは A/B)。C は 80/20 の近似。

### 4.2 全体構成

```
未確定読み R
   │
   ▼
[Segmenter] 少数の分割候補を列挙(前向き最長一致 + 小ビーム)
   │   例: きょうはいいてんきです
   │     → [今日/は/いい/天気/です] ほか数通り
   ▼
[Per-segment 変換] 各文節を既存 candidates(for:limit:) で top-k 取得(再利用)
   │
   ▼
[Path scorer] 経路スコア = Σ 文節スコア + λ·Σ bigram(seg_{i-1}, seg_i) − μ·(文節数ペナルティ)
   │   ビーム幅 B で保持
   ▼
[Merge] 上位連文節候補を、現行の単文節候補リストへ合流(重複排除)
```

### 4.3 データ構造(Swift 概略)

```swift
struct Segment {
    let reading: String        // 文節の読み
    let surface: String        // 変換後表層
    let score: Int             // candidates() 由来のスコア(高いほど良い)
}

struct SegPath {
    let segments: [Segment]
    let joined: String         // segments.map(\.surface).joined()
    let totalScore: Double
}
```

### 4.4 アルゴリズム
1. **分割列挙(Segmenter)**
   - 前向きに、位置 `i` から取り得る文節読み長を `1...maxSegLen`(例: 12)で試す。
   - 各始点で「その読み接頭が `candidates()` で意味のある変換を返すか」で枝刈り
     (返り top-1 のスコアが閾値未満・またはカタカナ素通りのみ、なら弱い枝)。
   - ビーム幅 `B`(例: 6)で部分経路を保持しながら末尾まで。**完全ラティスは張らない**。
2. **文節変換(再利用)**
   - 各文節読みに `candidates(for: seg, limit: k)` を適用(`k` は 2〜3)。既存キャッシュが効く。
3. **経路スコア**
   - `totalScore = Σ norm(seg.score) + λ·Σ logP_bigram(seg_i | seg_{i-1}) − μ·segmentCount`
   - `λ, μ` はチューニング係数。`μ` で過分割を抑制。
4. **合流**
   - 連文節 top-1〜3 を、単文節候補の上位に挿入(または僅かに優先)。重複排除。
   - **必ず現行の単文節候補も残す**(退行防止)。

### 4.5 言語モデル(LM: Language Model、bigram)

> 本メモの「LM」はすべて Language Model(言語モデル)の略。語・文節の並びやすさを
> 確率で表し、分割系列の自然さをスコア化するために使う。

- **単位**: 文節表層の bigram `P(seg_i | seg_{i-1})`。データが疎な場合は
  **品詞クラス bigram**(サ変/名詞/助詞/助動詞…)へバックオフ。最終バックオフは
  文字 trigram(超小型)。
- **作り方(自前コーパスが無い前提)**:
  - **品詞クラス bigram は Sudachi の連接行列 `matrix.def` から直接導出できる**
    (left/right ID 間の接続コスト = 事実上の品詞接続 LM)。écritu は既に `sudachi_raw` を
    取得済みなので **追加コーパス不要**。まずはこれだけで開始する。
  - **文字 trigram** は公開コーパスから集計:第一候補は日本語 Wikipedia ダンプ
    (現代文で量が十分)。バンドルするのは**集計後の n-gram 統計のみ**(原文は同梱しない)。
    青空文庫は文語調で IME 向きでないため補助程度。
  - **表層 bigram(将来アップグレード)**: Wikipedia を Sudachi で解析 → 語 bigram を集計
    → 高頻度のみ残す枝刈り + 量子化。
- ライセンス注意: Wikipedia は CC BY-SA。派生 n-gram(統計値)を同梱する形にし、
  由来表記を README/謝辞に残す。原文テキストは同梱しない。
- **サイズ目標**: 数百 KB〜数 MB(mmap 可能なフラット表)。**A の連接行列よりずっと小さい**。
- **段階**: まず「品詞クラス bigram + 文字 trigram」だけで開始(超小型)、
  効果が見えたら表層 bigram を追加。

### 4.6 統合ポイント(実ファイル)
- 新規: `KanaKanjiConverter.multiClauseCandidates(for:limit:mode:) -> [String]`
  を追加し、内部で既存 `candidates(for:)`(`KanaKanjiConverter.swift:457`)を文節ごとに再利用。
- 呼び出し側 `KeyboardViewController+InputHandling.swift:194` で、
  `converter.candidates(...)` の結果に `multiClauseCandidates(...)` を合流。
- LM ロードは `KanaKanjiStore` に配置(sqlite / mmap リソースと同じ経路)。
- **フラグ**: `isMultiClauseConversionEnabled`(`KeyboardViewController.swift` の
  既存フラグ群と同様)で on/off。既定 off で導入し、実機で比較。

### 4.7 メモリ / レイテンシ設計
- LM は mmap で読み込み、常駐 RSS を最小化(既存の footprint 失セーフ方針に整合)。
- ビーム幅 `B`・文節上限・`maxSegLen` で最悪計算量を上限化。
- 変換は既存の非同期キュー(`candidateGenerationQueue`)上で実行し UI をブロックしない。
- 計測: `phys_footprint` と変換 elapsed(既存の遅延ログ機構)で before/after を比較。

### 4.8 ガードレール(退行防止)
- 連文節候補が単文節候補より明確に良い時だけ上位に出す(スコア差の閾値)。
- 分割に失敗/低信頼なら **現行挙動へフォールバック**。
- フラグ既定 off + edition ごとに実機比較。

### 4.9 実装ステップ
1. `multiClauseCandidates` の骨組み(Segmenter + per-segment 再利用 + 単純結合、LM なし=等重み)。
2. 品詞クラス bigram + 文字 trigram の最小 LM を追加、`λ/μ` 調整。
3. フラグ導入・実機で before/after(品質体感 + footprint + elapsed)。
4. 効果次第で表層 bigram 追加、または A/B へ移行判断。

### 4.10 評価指標
- 代表入力セット(短文 20〜50)での**文全体一致率**(手動評価)。
- 変換レイテンシ(p50/p95)。
- キーボード拡張の `phys_footprint` 増分。
- 退行チェック(単文節の既存変換が悪化しないこと)。

---

## 5. 推奨ロードマップ

1. **C を試作**して費用対効果を測る(数日〜1 週間、依存なし・低リスク・可逆)。
2. 手応えがあれば:
   - 品質を突き詰めるなら **A(Sudachi コストで自前ビタビ)** — 依存なしで正統。
   - 早く高品質を得たいなら **B(azooKey 統合)** — footprint と移行コストを実測してから。
3. いずれも **フラグ既定 off + 実機比較 + edition bump** で段階導入する。

> メモ: 最大リスクは一貫して **拡張のメモリ footprint とレイテンシ**。
> C はここが最小で、A/B 判断の前の "地ならし" として最適。
