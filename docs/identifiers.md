# 識別子の全体像(bundle ID / App Group / Team ID)

écritu はアプリ本体とキーボード拡張の 2 つのプロセスで動き、両者は **App Group** を通じて設定・学習・辞書を共有する。
共有が成立するかどうかは複数の識別子が正しく揃っているかに掛かっており、1 か所でもずれると
「変換は動くのに設定だけ届かない」という分かりにくい壊れ方をする。

この文書は、識別子が **何か / 何をするか / どこに書き込まれるか / どう伝わるか** を一通り説明する。

---

## 1. 登場する識別子

| 識別子 | 例 | 役割 | 決める人 |
|---|---|---|---|
| Team ID | `487V53DJMW` | Apple 開発者チームの識別子。署名と App ID の名前空間 | Apple が発行 |
| App ID prefix | `487V53DJMW` | entitlements 内で `$(AppIdentifierPrefix)` として展開される。通常は Team ID と同じ | Apple |
| アプリの bundle ID | `com.kusakabe.ecritu` | アプリ本体の一意名。App ID の実体 | 開発者(Apple に登録) |
| 拡張の bundle ID | `com.kusakabe.ecritu.keyboard` | キーボード拡張の一意名。アプリの bundle ID を接頭辞に持つ必要がある | 同上 |
| テストの bundle ID | `com.kusakabe.ecritu.tests` | テストバンドル用 | 同上 |
| App Group ID | `group.com.kusakabe.ecritu` | アプリと拡張が共有するコンテナーの名前。`group.` で始まる必要がある | 開発者(Apple に登録) |
| keychain access group | `487V53DJMW.com.kusakabe.ecritu` | Keychain 項目の共有範囲 | 派生 |
| 拡張ポイント識別子 | `com.apple.keyboard-service` | 「これはキーボード拡張である」という宣言。iOS が拡張の種類を判別する | Apple 定義(固定) |
| 主クラス名 | `<モジュール名>.KeyboardViewController` | 拡張の起動時に iOS が生成するクラス | 開発者 |
| Darwin 通知名 | `com.kusakabe.ecritu.settings-changed.group.com.kusakabe.ecritu` | 設定変更をプロセス間に知らせる合図の名前 | 派生(コード内で組み立て) |

Apple 側にも登録が要るのは **App ID**(アプリと拡張の 2 つ)と **App Group** の 3 つ。Xcode の自動署名が裏で登録する。

---

## 2. 単一の源泉と派生

このリポジトリは、同一性に関わる値を **1 つの変数から派生**させている。源泉は `Config/Edition.xcconfig`。

```
ECRITU_DEVELOPMENT_TEAM      = 487V53DJMW
ECRITU_APP_BUNDLE_IDENTIFIER = com.kusakabe.ecritu          ← ここだけが本当の入力
ECRITU_KEYBOARD_BUNDLE_IDENTIFIER = $(ECRITU_APP_BUNDLE_IDENTIFIER).keyboard
ECRITU_TESTS_BUNDLE_IDENTIFIER    = $(ECRITU_APP_BUNDLE_IDENTIFIER).tests
ECRITU_APP_GROUP_IDENTIFIER       = group.$(ECRITU_APP_BUNDLE_IDENTIFIER)
```

各自の値で上書きするための仕組みが `Config/Signing.local.xcconfig`(git 管理外)。
`Edition.xcconfig` の末尾で `#include?` されており、あれば後から読まれて既定値を上書きする。
書き換えるのは実質 2 行(`ECRITU_DEVELOPMENT_TEAM` と `ECRITU_APP_BUNDLE_IDENTIFIER`)で、残りは自動で追従する。

派生の流れ:

```
ECRITU_APP_BUNDLE_IDENTIFIER
├─ PRODUCT_BUNDLE_IDENTIFIER (écritu ターゲット)
├─ ECRITU_KEYBOARD_BUNDLE_IDENTIFIER → PRODUCT_BUNDLE_IDENTIFIER (KeyboardExtension)
├─ ECRITU_TESTS_BUNDLE_IDENTIFIER    → PRODUCT_BUNDLE_IDENTIFIER (écrituTests)
├─ ECRITU_APP_GROUP_IDENTIFIER
│  ├─ entitlements の com.apple.security.application-groups(両ターゲット)
│  ├─ アプリの Info.plist の EcrituAppGroupIdentifier(INFOPLIST_KEY_… 経由)
│  └─ 拡張の Info.plist の EcrituAppGroupIdentifier(KeyboardExtension/Info.plist に直接記述)
└─ keychain-access-groups の後半($(AppIdentifierPrefix) と連結)
```

**この一本化が壊れる典型が、Xcode の画面から bundle ID や App Groups を直接書き換えること。**
画面で触った 1 か所だけがリテラルになり、変数から派生する残りは古い値のまま取り残される。

---

## 3. どこに書き込まれるか(ビルド成果物)

ビルドすると、値は 4 か所に焼き込まれる。

| 書き込み先 | 内容 | 生成元 |
|---|---|---|
| `Info.plist`(アプリ) | `CFBundleIdentifier`、`EcrituAppGroupIdentifier` | ビルド設定から生成(`GENERATE_INFOPLIST_FILE = YES`) |
| `Info.plist`(拡張) | 同上 + `NSExtensionPointIdentifier`、`RequestsOpenAccess` | `KeyboardExtension/Info.plist` の `$(…)` を展開 |
| entitlements(署名に埋め込まれる) | `com.apple.security.application-groups`、`keychain-access-groups` | `App/Ecritu.entitlements` / `KeyboardExtension/KeyboardExtension.entitlements` |
| `embedded.mobileprovision` | 上記 entitlements を Apple が承認した証明書 | Xcode の自動署名 |

確認コマンド(実機向けビルド後):

```
P=$(find ~/Library/Developer/Xcode/DerivedData -path '*Debug-iphoneos/*.app/PlugIns/KeyboardExtension.appex/embedded.mobileprovision' -print -quit)
plutil -p "$(dirname "$P")/Info.plist" | grep -i AppGroup
codesign -d --entitlements :- "$(dirname "$P")" 2>/dev/null | grep -A 4 application-groups
security cms -D -i "$P" | plutil -extract Entitlements xml1 -o - -
```

DerivedData が複数ある環境では `find … -print -quit` が意図しない方を拾うので、`echo "$P"` でパスを確認する。

---

## 4. 実行時にどう使われるか(伝達経路)

### 4.1 App Group 名の決まり方

アプリも拡張も、**自分の Info.plist に焼かれた `EcrituAppGroupIdentifier` を読んで**使う群を決める。

- アプリ: `SettingsKeys.appGroupID`(`App/SettingsModels.swift`)
- 拡張: `KeyboardViewController.SharedDefaultsKeys.appGroupID`

どちらも値が無い/空のときだけ、bundle ID から `group.<bundle ID>` を組み立てるフォールバックが働く
(拡張は末尾の `.keyboard` を落としてから組み立てる)。**通常はフォールバックに落ちない**ので、
Info.plist に焼かれた値がそのまま「要求する群」になる。

### 4.2 iOS 側の検査

拡張が `UserDefaults(suiteName:)` や `containerURL(forSecurityApplicationGroupIdentifier:)` を呼ぶと、
iOS は **要求された群が署名の entitlements に含まれているか**を見る。含まれていなければ拒否する。
このとき統合ログに出るのが次の行。

```
container_create_or_lookup_app_group_path_by_app_group_identifier: client is not entitled
containermanagerd … error=(55|3|0)
```

つまり検査されるのは **「Info.plist が要求する群」と「entitlements が許す群」の一致**であって、
片方だけ正しくても通らない。

### 4.3 設定が拡張へ届くまで

```
コンテナーアプリで設定を変更
  → UserDefaults(suiteName: <App Group>) に書く          … 共有コンテナー内の plist
  → Darwin 通知 "com.kusakabe.ecritu.settings-changed.<App Group>" を投げる
      ↑ 通知名に App Group 名を含むので、群が違えば通知も届かない
  → キーボード拡張が同じ名前を購読していて受信
  → 拡張が UserDefaults を読み直して画面と変換に反映
```

フルアクセスがオフのときは、この経路の最初(共有コンテナーへの書き込み)が成立しない。
そのため拡張側は「変換はバンドル辞書で動くが、設定と学習だけ届かない」状態になる。
キーボードは候補欄にその旨のバナーを出す。

### 4.4 その他の共有

| 用途 | 経路 |
|---|---|
| 辞書ファイル | `containerURL(…)` で共有コンテナーを引き、バンドルに実体が無いときのフォールバックとして使う |
| 診断ログ | 拡張が共有 `UserDefaults` に書き、コンテナーアプリが読んで表示する |
| 設定の退避 | Keychain(`kSecClassGenericPassword`)。アクセス範囲は `keychain-access-groups` の先頭。アプリを削除しても同じ Team ID なら読める |

---

## 5. 壊れ方の実例(2026-09-07〜09 のベータテスター)

| 場所 | 値 | 由来 |
|---|---|---|
| 拡張の Info.plist の群名 | `group.com.kusakabe.ecritu` | 変数(= リポジトリの既定値のまま) |
| 拡張の署名の群 | `group.com.twaitsjp.ecritu` | Xcode の App Groups 画面で追加 |
| 拡張の bundle ID | `com.twaitsjp.ecritu.keyboard` | Xcode の画面で上書き |
| keychain 群 | `7XRR4A633F.com.kusakabe.ecritu` | 変数(既定値のまま) |

`Config/Signing.local.xcconfig` を作らずに Xcode の画面だけで識別子を変えたため、値が分裂した。
拡張は Info.plist の `group.com.kusakabe.ecritu` を要求し、署名はそれを許していないので拒否された。
変換はバンドル辞書で動くので、症状は「設定と学習だけ届かない」になり、原因特定に 3 日かかった。

なお、片方だけでは起きない。

- ローカル設定を作らなかっただけ(画面を触らない): すべて既定値で揃うので食い違わない。代わりに他チームでは署名の登録で弾かれ、見える形で失敗する
- 画面で書き換えただけ(ローカル設定もある): 値が一致するので動く。汚いだけ

---

## 6. 事故を防ぐ仕組み

### ビルド時の検査(`tools/verify_signing_identity.sh`)

アプリと拡張の両ターゲットのビルドフェーズに入っており、次の 4 点が破れたら `error:` を出してビルドを止める。

1. App Group == `group.` + アプリの bundle ID
2. 拡張の bundle ID == アプリの bundle ID + `.keyboard`
3. 実際にビルドされる `PRODUCT_BUNDLE_IDENTIFIER` が派生値と一致(= 画面での上書きが無い)
4. entitlements の群が `$(ECRITU_APP_GROUP_IDENTIFIER)` のまま(= 画面から追加していない)
5. 実機ビルドで、設定されている Team ID の署名証明書が手元にあるか(= `Config/Signing.local.xcconfig` の作り忘れ検出)。
   証明書の OU を読んで判定するので、ファイルの有無ではなく実効値で見る。シミュレーターと CI(`CODE_SIGNING_ALLOWED=NO`)は対象外

### 実行時のログ

アプリと拡張の両方が、起動時に自分の状態を 1 行で出す。

```
AppGroup健全性 group=… container=… profileGroups=[…] bundle=… fullAccess=0/1 containerURL=ok defaults=ok
```

拡張側は同じ行を iOS の統合ログにも出す。フルアクセスがオフで共有コンテナーに書けない状況でも読めるようにするため。

```
sudo log collect --device-name "<iPhone 名>" --last 10m
/usr/bin/log show --archive <出力>.logarchive --style compact \
  --predicate 'process == "KeyboardExtension" AND category == "diagnostics"'
```

---

## 7. 新しい環境でビルドするとき

```
cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig
```

```
ECRITU_DEVELOPMENT_TEAM      = <自分の Team ID>
ECRITU_APP_BUNDLE_IDENTIFIER = com.<自分>.ecritu
```

残りの 3 行は変数から派生するので触らない。**Xcode の画面では bundle ID も App Groups も変更しない。**
すでに触ってしまった場合は、Build Settings の Product Bundle Identifier が太字なら選んで delete し、
entitlements は `git checkout --` で戻す。

その後 Clean Build Folder → 実機を選んで ⌘R。実機からアプリを削除して入れ直し、
キーボードを追加し直してフルアクセスをオンにする(再インストールでキーボードの登録が外れることがある)。
