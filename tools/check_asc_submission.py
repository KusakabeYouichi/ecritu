#!/usr/bin/env python3
"""App Store 提出直前の取り違え防止チェック(3356)。

1) 審査に出す版(既定 1.0)に付いているビルドを App Store Connect から読み、git のタグと突き合わせる。
   合格は submitted-<版>-<ビルド> のタグがあるときだけ(tools/verify_archive_artifacts.sh を審査用モード=指定なしで
   通して --tag を付けたときにしか打たれない)。testflight-debug-…(Debug 構成=診断入り)、testflight-…(出荷前診断入り)、
   タグ無し(検査を通っていない古いビルド)はすべて ❌。
2) --expire: 役目を終えた Debug 構成の TestFlight 版(testflight-debug-… のタグのビルド)を期限切れにして、
   付け間違える候補から消す。最新の 1 つ(テスターが使っている版)は残す。期限切れは取り消せないので、
   既定は一覧を出すだけで、--yes を付けたときだけ実行する。

認証: 環境変数 ASC_KEY_ID / ASC_ISSUER_ID(リポジトリには入れない)。鍵は ~/.private_keys/AuthKey_<ASC_KEY_ID>.p8
(altool と同じ置き場所)。ASC_KEY_PATH で上書きできる。JWT は openssl だけで作る(追加の Python パッケージ不要)。

使い方:
  ASC_KEY_ID=… ASC_ISSUER_ID=… python3 tools/check_asc_submission.py            # 提出前チェック
  ASC_KEY_ID=… ASC_ISSUER_ID=… python3 tools/check_asc_submission.py --expire   # 期限切れにする候補の一覧
  ASC_KEY_ID=… ASC_ISSUER_ID=… python3 tools/check_asc_submission.py --expire --yes
終了コード: チェックが ❌ なら 1。
"""
import argparse
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

APP_ID_DEFAULT = "6811522525"  # écritu(App Store Connect のアプリ ID。秘密ではない)
API = "https://api.appstoreconnect.apple.com"


def die(msg):
    print(msg, file=sys.stderr)
    sys.exit(2)


def jwt():
    key_id = os.environ.get("ASC_KEY_ID")
    issuer = os.environ.get("ASC_ISSUER_ID")
    if not key_id or not issuer:
        die("環境変数 ASC_KEY_ID と ASC_ISSUER_ID を設定してください(値はリポジトリに入れない)")
    key_path = os.environ.get("ASC_KEY_PATH") or os.path.expanduser(f"~/.private_keys/AuthKey_{key_id}.p8")
    if not os.path.exists(key_path):
        die(f"API キーが見つかりません: {key_path}")

    def b64(data):
        return base64.urlsafe_b64encode(data).rstrip(b"=").decode()

    header = b64(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    now = int(time.time())
    payload = b64(json.dumps({"iss": issuer, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}).encode())
    signing_input = f"{header}.{payload}".encode()
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", key_path],
                         input=signing_input, capture_output=True, check=True).stdout

    # DER の SEQUENCE{INTEGER r, INTEGER s} を r||s(各 32 バイト)へ
    def read_int(buf, i):
        assert buf[i] == 0x02
        length = buf[i + 1]
        value = buf[i + 2:i + 2 + length]
        return value.lstrip(b"\x00").rjust(32, b"\x00"), i + 2 + length

    i = 2 if der[1] < 0x80 else 3
    r, i = read_int(der, i)
    s, _ = read_int(der, i)
    return f"{header}.{payload}.{b64(r + s)}"


_TOKEN = None


def call(method, path, body=None):
    global _TOKEN
    if _TOKEN is None:
        _TOKEN = jwt()
    req = urllib.request.Request(API + path, method=method,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Authorization": "Bearer " + _TOKEN, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            data = r.read()
            return json.loads(data) if data else {}
    except urllib.error.HTTPError as e:
        die(f"{method} {path} -> {e.code}: {e.read().decode()[:400]}")


def git_tags():
    out = subprocess.run(["git", "tag", "--list"], capture_output=True, text=True, check=True).stdout
    return set(out.split())


def check_submission(app_id, version_string, tags):
    versions = call("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[versionString]={version_string}"
                           f"&fields[appStoreVersions]=versionString,appStoreState&limit=5")["data"]
    if not versions:
        print(f"  ❌ 版 {version_string} が App Store Connect にありません")
        return False
    v = versions[0]
    state = v["attributes"]["appStoreState"]
    build = (call("GET", f"/v1/appStoreVersions/{v['id']}/build?fields[builds]=version,processingState,expired")
             .get("data") or None)
    print(f"版 {version_string}(状態 {state})")
    if build is None:
        print("  ❌ ビルドが付いていません")
        return False
    number = build["attributes"]["version"]
    print(f"  付いているビルド: {number}(処理 {build['attributes']['processingState']})")
    submitted = f"submitted-{version_string}-{number}"
    debug = f"testflight-debug-{version_string}-{number}"
    testflight = f"testflight-{version_string}-{number}"
    if debug in tags:
        print(f"  ❌ Debug 構成の TestFlight 版です({debug})。診断入りなので審査に出さないこと")
        return False
    if submitted in tags:
        print(f"  ✅ 審査用モードの検査を通ったビルドです({submitted})")
        return True
    if testflight in tags:
        print(f"  ❌ TestFlight 用のビルドです({testflight})。出荷前診断が入っている。診断 0 の Release で作り直す")
        return False
    print(f"  ❌ 検査済みの印({submitted})がありません。verify_archive_artifacts.sh を指定なしで通して --tag を付けたビルドを付ける")
    return False


def expire_debug_builds(app_id, version_string, tags, really):
    builds = call("GET", f"/v1/builds?filter[app]={app_id}&filter[expired]=false"
                         f"&fields[builds]=version,expired,uploadedDate&limit=200")["data"]
    debug = [b for b in builds if f"testflight-debug-{version_string}-{b['attributes']['version']}" in tags]
    debug.sort(key=lambda b: int(b["attributes"]["version"]))
    if not debug:
        print("期限切れにする Debug 構成の版はありません")
        return
    keep, targets = debug[-1], debug[:-1]
    print(f"残す(最新の Debug 構成の版): {keep['attributes']['version']}")
    if not targets:
        print("期限切れにする候補はありません")
        return
    for b in targets:
        print(f"  期限切れの候補: {b['attributes']['version']}(上げた日 {b['attributes']['uploadedDate'][:10]})")
    if not really:
        print("※ 一覧だけ。実行するには --yes を付ける(期限切れは取り消せない)")
        return
    for b in targets:
        call("PATCH", f"/v1/builds/{b['id']}", {"data": {"type": "builds", "id": b["id"], "attributes": {"expired": True}}})
        print(f"  期限切れにした: {b['attributes']['version']}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--version", default="1.0", help="審査に出す版(既定 1.0)")
    ap.add_argument("--app-id", default=APP_ID_DEFAULT)
    ap.add_argument("--expire", action="store_true", help="役目を終えた Debug 構成の TestFlight 版を期限切れにする(既定は一覧だけ)")
    ap.add_argument("--yes", action="store_true", help="--expire を実際に実行する")
    args = ap.parse_args()
    tags = git_tags()
    if args.expire:
        expire_debug_builds(args.app_id, args.version, tags, args.yes)
        return
    ok = check_submission(args.app_id, args.version, tags)
    print("== 提出してよい ==" if ok else "== 提出しない(上の ❌ を解消する) ==")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
