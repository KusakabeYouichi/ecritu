# App Store 提出用メタデータ(écritu)

作成: 2026-09-01。文字数制限を検証済み。ASCの入力欄にそのまま貼り付け可。

## アプリ名(30字以内)

écritu 日本語フリックキーボード

## サブタイトル(30字以内)

モード切替を最小にした日本語入力

## プロモーションテキスト(170字以内・随時変更可)

「?」「。」「〜」「…」括弧まで、かなのまま打てる日本語フリックキーボード。通信は一切なし — 入力内容が端末の外に出ることはありません。連文節変換、絵文字・顔文字・記号パネル、単位や日付の入力補助まで、この1枚に。

## キーワード(100字以内・現在63字)

キーボード,日本語入力,フリック,かな,IME,変換,絵文字,顔文字,記号,オフライン,プライバシー,辞書,旧仮名,部首,単位

## 説明文(4000字以内)

écritu(エクリチュ)は、「モード切り替えを最小に」を合言葉に設計された iPhone 用の日本語フリック入力キーボードです。

■ 通信ゼロ。入力内容は端末の外に出ません
écritu にはネットワーク通信を行うコードそのものがありません。入力した文字、変換履歴、学習した語彙が開発者を含む誰かに送られることは、仕組みの上でありえません。解析SDK・広告SDKも不使用。フルアクセスの用途は、本体アプリとキーボードの間で設定と学習語彙を共有することだけです。

■ モードを切り替えずに、そのまま打てる
「?」「!」「。」「・」は読点キーのフリックに、「〜」「ー」はわキーに、『』などの括弧はやキーに。よく使う記号のためにいちいち記号モードへ入る必要はありません。やキー・わキーは「2段フリック」に対応し、()「」や旧仮名の「ゐ」「ゑ」まで指を離さずに入力できます。

■ 賢い変換と、育つ辞書
文節をまたいだ連文節変換に対応。確定した候補は端末内で学習され、使うほどあなたの言葉に馴染みます。単語の手動登録(追加語彙)、出したくない候補を隠す抑制語彙、定型文のショートカット語彙、iOS の連絡先やユーザ辞書との連携も。

■ 絵文字・顔文字・記号のパネル
カテゴリー分けされた絵文字(国旗は長押しで国名をフランス語表示)、読みから探せる顔文字検索、通貨・単位・数学記号・矢印・囲み文字。漢字1字を部首から探せるピッカーも備えています。

■ 数字・単位・日付の入力補助
数字モードでは 3,000 のような桁区切り、km や ℃ などの単位、金額、日付や曜日(カレンダー表示つき)まで、書式化された数値をそのまま入力できます。

■ 欧文もサジェスト
英語・フランス語・ドイツ語・イタリア語の入力補完を搭載(オフライン辞書)。アクセント付き文字も長押しで。メールアドレスやURLの欄では自動的に英字配列で開きます。

■ 細かな設定
かな配列(5×2 / 3×3+わ)、フリック方向(style écritu / style iPhone)、英字配列(QWERTY / AZERTY / 3×3)、テーマとアクセントカラー、フリックガイドの表示方法など、細部まで好みに合わせられます。

操作方法の詳しい説明は、操作マニュアル(全9章。アプリのアイコンを長押ししたメニューから Safari で開けます)をご覧ください。

## What's New(初回)

初回リリースです。

## URL類

- プライバシーポリシー: https://kusakabeyouichi.github.io/ecritu/manual/privacy.html
- サポートURL: https://kusakabeyouichi.github.io/ecritu/manual/
- マーケティングURL(任意): https://kusakabeyouichi.github.io/ecritu/manual/

## App Privacy 申告(ASCフォームの回答)

- データ収集: 「いいえ、このアプリからデータを収集しません」
  (連絡先は端末内でのみ読み取り・暗号化保存し、開発者には送信されない=Appleの定義で「収集」に該当しない)
- トラッキング: なし

## 審査ノート(Notes for Review 欄)

App Group を用いて本体アプリとキーボード拡張の間で設定・学習語彙を共有するためにフルアクセスを使用します。フルアクセスは任意で、オフでもすべての入力・変換機能が動作します(学習と設定の反映だけが行われません)。ネットワーク通信を行うコードは含まれておらず、入力内容が端末外へ送信されることはありません。連絡先名の変換候補機能は初期設定でオフで、ユーザーが設定でオンにしたときだけ許可を求め、本体アプリのみが連絡先を読み取り、AES-GCM で暗号化して端末内に保存します。パスワード・ワンタイムコード・カード番号等のフィールドでは学習を行いません。キーボード拡張は約 400MB の変換辞書を同梱し、完全オフラインで動作します(ダウンロードサイズが大きいのはこのためです)。

(英語で求められた場合)
Full Access is used solely to share settings and the learned vocabulary between the container app and the keyboard extension via an App Group. Full Access is optional: every input and conversion feature works without it (only learning persistence and settings sync are skipped). The app contains no networking code; nothing typed ever leaves the device. The optional contact-name feature is off by default, asks for permission only when the user turns it on in Settings, reads contacts only in the container app, and stores an encrypted (AES-GCM) mapping on device. No learning occurs in password, one-time-code or credit-card fields. The keyboard extension bundles a ~400 MB conversion dictionary and works fully offline, which is why the download is large.

## 輸出コンプライアンス(暗号化)

ITSAppUsesNonExemptEncryption = NO で申告済み。使用する暗号は Apple 提供の CryptoKit(AES-GCM)のみで、用途は端末内データ(連絡先対応表)の保護。輸出規制の免除対象(暗号を「端末内のデータ保護」に限って使用)に該当し、通信・DRM・独自暗号は無い。ASC で質問が出た場合は「免除に該当」を選ぶ。

## 年齢レーティング

すべて「なし」で 4+。根拠: IME の辞書にワイン等の語が含まれることは「アルコール使用の描写・言及」に当たらない(Apple 純正キーボード・辞書アプリも 4+)。欧文サジェストは差別語・強い卑語を除外リストで提案から外している(tools/latin_suggestion_blocklist.txt、2026-09-04)。
