# Contributing to écritu

このリポジトリは、Apple Developer Program 未加入 (無料 Apple ID) の開発者でも共同開発できる構成を前提にしています。

## 1. 初回セットアップ

1. フックを有効化します。

```bash
git config core.hooksPath .githooks
```

2. 署名のローカル上書きファイルを作成します。

```bash
cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig
```

3. `Config/Signing.local.xcconfig` を編集します。
- `ECRITU_DEVELOPMENT_TEAM` を自分の Team ID に変更
- `ECRITU_APP_BUNDLE_IDENTIFIER` を一意な値に変更 (例: `com.yourname.ecritu.dev`)
- `ECRITU_APP_GROUP_IDENTIFIER` は通常そのままで可

4. VS Code のタスク `Run ecritu on iPhone 17 Pro` を実行し、
シミュレータでビルド・インストール・起動できることを確認します。

## 2. ブランチと PR

1. `main` から作業ブランチを切ります。
- 推奨プレフィックス: `feature/` `fix/` `chore/`
2. 小さな単位でコミットします。
3. Pull Request を作成します。
4. GitHub Actions の `iOS CI` が成功することを確認します。

## 3. ローカル確認の最低ライン

Pull Request 前に、少なくとも次を実行してください。

1. `Build ecritu (iOS Simulator)`
2. `Run ecritu on iPhone 17 Pro`
3. 必要に応じてテスト実行

```bash
xcodebuild -project "écritu.xcodeproj" -scheme "écritu" -destination "platform=iOS Simulator,name=iPhone 17 Pro" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO test
```

## 4. 無料アカウントでの制約

- App Store 配布と TestFlight 配布はできません。
- 署名関連で `No Account for Team` が出る場合は Team ID を見直してください。
- Bundle Identifier 重複エラー時は `ECRITU_APP_BUNDLE_IDENTIFIER` を変更してください。

## 5. CI の考え方

- CI は署名不要のシミュレータテストのみを実行します。
- 実機動作の最終確認は各開発者のローカル環境で行います。
