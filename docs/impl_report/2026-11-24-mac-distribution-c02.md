---
title: Mac 版をテスターへ配る(Developer ID 署名 + 公証の .pkg を作るスクリプト)
date: 2026-11-24
branch: pour-mac
cycle: c02
scale: 小
stages:
  env: done
  0_spec: done(事前調査 2 本: TestFlight / Mac App Store で配れるか、Mac App Store の実例)
  1_design: done
  2_test_design: done
  3_adversarial: done
  4_implement: done
  5_code_review: done(高 0、中 1、低 7。中と低 5 件を直した)
  6_tests: done(スクリプトの経路を実行して確認。自動テストは無い)
  7_e2e: skipped(署名・公証・実際のインストールは Developer ID の証明書が要る。証明書がまだ無い)
  8_reality_check: skipped(小。差分はレビュー役が設計と突き合わせ済み)
  9_report: done
adversarial:
  findings: 12
  rejected: 0
---

# Mac 版をテスターへ配る

## 経緯

ユーザの希望は「テスターには TestFlight で配る」だったが、調査と実測で Mac の入力メソッドは TestFlight / Mac App Store では配れない見込みと分かった。

- Apple の技術サポート担当者のフォーラム回答「Mac App Store で入力メソッドを配る公式な方法はない」(2020 年。2026 年 4 月の再質問でも変わらず)
- 実測: /Applications に置いた入力メソッドは、登録の呼び出しが成功を返しても入力ソースの台帳に載らない(~/Library/Input Methods では載る)
- 実測: サンドボックスだけでは IMKServer の接続名を登録できない。一時例外の権限(mach-register.global-name)を付けると登録できる
- Mac App Store で配られている本物の入力メソッドの実例は見つからなかった。ATOK・かわせみ・Google 日本語入力・macSKK・azooKey はどれもストア外

そこで、テスター配布は Developer ID 署名 + 公証の .pkg にする(ユーザ了承)。販売の経路は未決。

## 作ったもの

| ファイル | 内容 |
|---|---|
| tools/package_mac_input_method.sh | Release でビルド → 検査 → 署名 → pkg 作成 → 公証 → 確認。`--unsigned`(署名なしの試し)、`--notarize <キーチェーンプロファイル名>`、`--check-only <.app>` |
| MacInputMethod/Packaging/postinstall | /Library/Input Methods 側の古いプロセスだけを終了する。ホームの中には触れず、開発版が残っていれば警告だけ |
| MacInputMethod/Packaging/component.plist | 入れ先を固定(BundleIsRelocatable = false) |
| docs/mac-beta-install.md | テスター向けの入れ方・更新・消し方・操作の一覧(初回のインストールで確かめるまで下書き) |
| tools/install_mac_input_method.sh | 終了させる対象の正規表現を、ホームの絶対パスで先頭を固定する形に |

スクリプトの検査(1 つでも外れたら pkg を作らない):
- 未コミットの変更が無い(`--unsigned` は警告だけ)
- 同梱の辞書 sqlite と ÉcrituSecondVocab.eccs に、病名語彙の目印の語(iOS の tools/verify_archive_artifacts.sh と同じ 4 語)が無い
- tmp/.medicaux.state が 0、辞書が 50MB 以上、複製された 10 ファイルが tmp/ と同一、bundle ID が一致
- Release の実行ファイルを直接起動した自己検査 3 つが成功

配布ビルドは `ECRITU_INCLUDE_MEDICAUX=0 ARCHS=arm64` で行なう(テスターに Intel の Mac は無い。ユーザ回答)。

## 検証結果

| 観点 | 結果 |
|---|---|
| `--unsigned` | 終了コード 0。tmp/mac-dist/ecritu-0.1-3896-unsigned.pkg(約 32MB)。ビルドに約 9 分 |
| 展開した pkg | install-location = /Library/Input Methods、relocatable = false、postinstall が実行可能、arm64 だけ、辞書 86MB・724,159 行、病名語彙の目印の語 0 件 |
| 病名語彙の検査の対照 | 病名ありの辞書(main の作業ツリーの tmp)では同じ問い合わせが 4 件を返す |
| `--check-only` に目印の語入りの辞書 / 小さい辞書 | どちらも失敗で終わり、理由が出る |
| `--unsigned --notarize x` | 使い方を出して失敗 |
| 証明書を探す処理 | 見本の出力で確認(両方ある → 2 つの名前 / 片方だけ・チーム違い → 失敗)。この Mac の今の状態(Developer ID なし)でも「無い」と判定 |

## 未検証

- (2026-11-25 に確認済み)署名・公証・ステープル・Gatekeeper の評価: `--notarize` で通して終了コード 0。公証は Accepted、`spctl -a -t install` は「accepted / source=Notarized Developer ID」。tmp/mac-dist/ecritu-0.1-3896.pkg(31,803,765 バイト、コミット 580848f0)
- pkg の実際のインストールと、/Library/Input Methods に入れた版が入力ソースとして働くこと
- 開発版が動いているときの自己検査: IMKServer の作成のログは「成功」と出たが、同じ接続名が 2 つあるときに登録できているかは見ていない(自己検査のこの 1 行は弱い)
- eccs の検査の対照(病名ありの eccs で当たること)
- docs/mac-beta-install.md の手順

## 残課題 / 申し送り

1. (済み)Developer ID の証明書(Application と Installer)は、developer.apple.com の証明書のページで要求ファイルから作った。Xcode では「Account Holder だけができる操作」と断られた(Xcode の表示では権限が Admin。登録の種類は個人)。Xcode の表示が食い違う原因は未確認
2. (済み)公証用の資格情報はキーチェーンに `ecritu-notary` の名前で登録済み(ユーザが登録)
3. pkg の実際のインストールを確かめる。この Mac で試すときは、先に ~/Library/Input Methods の開発版を外す
4. 販売の経路(Mac 版を無料で配る / Mac 版だけ自前で売る / Apple の回答を待つ)は未決。Apple への質問文の下書きは作成済み(送るかどうかはユーザの判断)
5. この作業ツリーの tmp/ は病名なしの辞書になった。references/médicaux.plist がこの作業ツリーに無いので、ここでの開発ビルドにも病名語彙は入らない(最初のビルドからそうだった)
6. 証明書を名前で指定しているので、同じ名前の証明書が 2 つあると署名が「ambiguous」で失敗する(更新の時期に起きうる。失敗は見える)

## 2026-11-25 の追記(実際に入れて分かったことと直したこと)

配布物: tmp/mac-dist/ecritu-0.1-3896.pkg(公証済み、コミット 086bd6ca、SHA-256 e502a5b6…d4f1)。

| 分かったこと | 対応 |
|---|---|
| /Library/Input Methods に入れた版は、登録を呼んでも OS の読み直しで捨てられる。ログインし直すと入力ソースに出て、OS が起動する | 入れ先を [すべてのユーザ用] と [自分専用] から選べるようにした(ユーザ提案)。最後の画面でログインし直しを案内する |
| ~/Library/Input Methods は、登録(TISRegisterInputSource)を呼べば入れてすぐ一覧に出る | 本体に `--register-input-source` を足し、postinstall から呼ぶ |
| 入れた直後のログインの間は、OS が入力メソッドを起動できない(imklaunchagent の LaunchInputMethod() が status=-50)。ログインし直すと起動できる | postinstall で起動しておく(動いていれば接続名でつながる) |
| postinstall の $3 は [自分専用] でも / | 入れ先は $2 で見分ける。誤っていた間は古いプロセスが残り、入れ替え前の辞書を開いたままで変換できなかった |
| 第三者製の入力メソッドは、画像 1 枚がメニュー・一覧・切り替えの吹き出しの全部に使われる | 文字だけの画像にした(ユーザ決定、当面)。経緯は tools/generate_mac_icon.swift の冒頭 |

確かめたこと([自分専用]、公証済みの pkg、この Mac):
- 入れ先を選ぶ画面と最後の案内の画面が出る。管理者のパスワードは聞かれない
- インストールの完了と同じ時刻に ecritu が起動し直される(12:00:27)。入った版は Gatekeeper の評価が accepted(Notarized Developer ID)
- ログインし直したあとは、プロセスを終了させても OS が起動し直す

外した仮説(原因ではなかったもの): 同じ ID の写しが OS のアプリ台帳に載っていること / 公証の有無 / imklaunchagent が古い情報を持っていること。

未検証:
- [すべてのユーザ用] を新しい形の pkg で入れること(再起動後に動いたのは、最初の形の pkg で入れた版)
- 一度も入れたことのない Mac での動作(テスターが最初の確認になる)
- status=-50 の原因そのもの(避け方だけ分かっている)
