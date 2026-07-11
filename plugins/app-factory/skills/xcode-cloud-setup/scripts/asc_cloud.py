#!/usr/bin/env python3
"""App Store Connect API — Bundle ID登録とXcode Cloudワークフロー作成.

環境変数（~/dev/others/claude-cron/.env を source してから実行）:
  APP_STORE_KEY_ID      — API Key ID
  APP_STORE_ISSUER_ID   — Issuer ID
  APP_STORE_P8_KEY      — .p8 秘密鍵の内容（改行含む文字列）

サブコマンド:
  register-bundle-id <identifier> <name>   Bundle IDを登録（登録済みなら成功扱い）
  status [AppName]                         ciProducts・リポジトリ・ワークフローの一覧
  check-onboarded <AppName>                Xcode Cloudオンボーディング済みなら exit 0、未了なら exit 1
                                           （承認チェックジョブのポーリング用）
  create-workflows <AppName> [--scheme S] [--project P.xcodeproj]
                                           PR/タグトリガーのTestFlightワークフロー2本を作成

依存: pyjwt, cryptography, requests（claude-cron の .venv に導入済み。
  ~/dev/others/claude-cron/.venv/bin/python3 での実行を推奨）
"""

import argparse
import json
import os
import sys
import time

import jwt
import requests

BASE_URL = "https://api.appstoreconnect.apple.com"


def token() -> str:
    key_id = os.environ["APP_STORE_KEY_ID"]
    issuer_id = os.environ["APP_STORE_ISSUER_ID"]
    # .env には literal \n で格納されているため実改行に戻す
    private_key = os.environ["APP_STORE_P8_KEY"].replace("\\n", "\n")
    now = int(time.time())
    payload = {"iss": issuer_id, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}
    return jwt.encode(payload, private_key, algorithm="ES256", headers={"kid": key_id})


def api(method: str, path: str, body: dict | None = None) -> dict:
    r = requests.request(
        method,
        f"{BASE_URL}{path}",
        headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"},
        json=body,
        timeout=60,
    )
    if r.status_code >= 400:
        try:
            detail = json.dumps(r.json().get("errors", []), ensure_ascii=False, indent=2)
        except Exception:
            detail = r.text[:500]
        raise SystemExit(f"ERROR {r.status_code} {method} {path}\n{detail}")
    return r.json() if r.text else {}


def get_all(path: str, params: str = "") -> list:
    """ページネーションを畳んで全件返す."""
    items, url = [], f"{path}?limit=200{('&' + params) if params else ''}"
    while url:
        data = api("GET", url)
        items.extend(data.get("data", []))
        next_url = (data.get("links") or {}).get("next")
        url = next_url.replace(BASE_URL, "") if next_url else None
    return items


# ---------- register-bundle-id ----------

def register_bundle_id(identifier: str, name: str) -> None:
    existing = get_all("/v1/bundleIds", f"filter[identifier]={identifier}")
    # filterは前方一致的に振る舞うことがあるため完全一致を確認
    for b in existing:
        if b["attributes"]["identifier"] == identifier:
            print(f"OK: {identifier} は登録済み（id={b['id']}）")
            return
    body = {
        "data": {
            "type": "bundleIds",
            "attributes": {"identifier": identifier, "name": name, "platform": "IOS"},
        }
    }
    created = api("POST", "/v1/bundleIds", body)
    print(f"OK: {identifier} を登録しました（id={created['data']['id']}）")


# ---------- status ----------

def find_product(app_name: str | None):
    products = get_all("/v1/ciProducts", "include=primaryRepositories")
    if app_name:
        products = [p for p in products if p["attributes"]["name"].lower() == app_name.lower()]
    return products


def status(app_name: str | None) -> None:
    products = find_product(app_name)
    if not products:
        print("ciProductが見つかりません。Xcode Cloudのオンボーディング（Xcodeで Product > Xcode Cloud > Create Workflow）が未完了です。")
        return
    for p in products:
        print(f"product: {p['attributes']['name']}  id={p['id']}  type={p['attributes']['productType']}")
        repos = get_all(f"/v1/ciProducts/{p['id']}/primaryRepositories")
        for r in repos:
            print(f"  repository: {r['attributes'].get('repositoryName')}  id={r['id']}")
        workflows = get_all(f"/v1/ciProducts/{p['id']}/workflows")
        for w in workflows:
            print(f"  workflow: {w['attributes']['name']}  id={w['id']}  enabled={w['attributes']['isEnabled']}")
        if not workflows:
            print("  workflow: (なし)")


def check_onboarded(app_name: str) -> None:
    """ciProduct と接続済みリポジトリの両方が存在すれば onboarded とみなす."""
    products = find_product(app_name)
    if products:
        repos = get_all(f"/v1/ciProducts/{products[0]['id']}/primaryRepositories")
        if repos:
            print(f"onboarded: product={products[0]['id']}")
            return
        print("not onboarded (ciProductはあるがリポジトリ接続なし)")
        raise SystemExit(1)
    print("not onboarded")
    raise SystemExit(1)


# ---------- create-workflows ----------

def latest_version_ids() -> tuple[str, str]:
    """最新のXcodeバージョンと、それに対応するmacOSバージョンのIDを返す.

    "Latest Release" という名前のエントリがあればそれを選ぶ（Apple側の
    リリースに自動追従するエイリアス）。なければ一覧の末尾（最新）。
    """
    xcodes = get_all("/v1/ciXcodeVersions")
    if not xcodes:
        raise SystemExit("ERROR: ciXcodeVersions が取得できません")

    def version_key(entry):
        # name は "Xcode 26.2" 形式。一覧は未ソートなので数値で最大を選ぶ
        import re
        m = re.search(r"(\d+)(?:\.(\d+))?", entry["attributes"].get("name") or "")
        return (int(m.group(1)), int(m.group(2) or 0)) if m else (0, 0)

    xcode = next(
        (x for x in xcodes if (x["attributes"].get("name") or "").lower() == "latest release"),
        max(xcodes, key=version_key),
    )
    macs = get_all(f"/v1/ciXcodeVersions/{xcode['id']}/macOsVersions")
    if not macs:
        raise SystemExit("ERROR: 対応するmacOSバージョンが取得できません")
    mac = next(
        (m for m in macs if (m["attributes"].get("name") or "").lower() == "latest release"),
        max(macs, key=version_key),
    )
    print(f"使用バージョン: {xcode['attributes'].get('name')} / {mac['attributes'].get('name')}")
    return xcode["id"], mac["id"]


def build_workflow_body(
    name: str,
    description: str,
    start_condition_key: str,
    start_condition: dict,
    clean: bool,
    scheme: str,
    container_path: str,
    product_id: str,
    repo_id: str,
    xcode_id: str,
    macos_id: str,
) -> dict:
    return {
        "data": {
            "type": "ciWorkflows",
            "attributes": {
                "name": name,
                "description": description,
                "isEnabled": True,
                "isLockedForEditing": False,
                "clean": clean,
                "containerFilePath": container_path,
                start_condition_key: start_condition,
                "actions": [
                    {
                        "name": "Archive - iOS",
                        "actionType": "ARCHIVE",
                        "scheme": scheme,
                        "platform": "IOS",
                        "isRequiredToPass": True,
                        "buildDistributionAudience": "INTERNAL_ONLY",
                    }
                ],
            },
            "relationships": {
                "product": {"data": {"type": "ciProducts", "id": product_id}},
                "repository": {"data": {"type": "scmRepositories", "id": repo_id}},
                "xcodeVersion": {"data": {"type": "ciXcodeVersions", "id": xcode_id}},
                "macOsVersion": {"data": {"type": "ciMacOsVersions", "id": macos_id}},
            },
        }
    }


def create_workflows(app_name: str, scheme: str | None, project: str | None, branch: str) -> None:
    products = find_product(app_name)
    if not products:
        raise SystemExit(
            f"ERROR: ciProduct '{app_name}' が見つかりません。先にXcodeでXcode Cloudのオンボーディング"
            "（Product > Xcode Cloud > Create Workflow）を1回行ってください。"
        )
    product = products[0]
    product_id = product["id"]
    repos = get_all(f"/v1/ciProducts/{product_id}/primaryRepositories")
    if not repos:
        raise SystemExit("ERROR: 接続済みリポジトリが見つかりません。GitHub接続が未完了です。")
    repo_id = repos[0]["id"]
    xcode_id, macos_id = latest_version_ids()

    scheme = scheme or app_name
    container_path = project or f"{app_name}.xcodeproj"
    existing = {w["attributes"]["name"] for w in get_all(f"/v1/ciProducts/{product_id}/workflows")}

    # 注意: isAllMatch: true のときは patterns キーを含めてはいけない（API仕様）
    plans = [
        (
            "PR to TestFlight",
            f"{branch} 宛PRの作成・更新ごとにアーカイブしてTestFlight内部配布（app-kickoff自動生成）",
            "pullRequestStartCondition",
            {
                "source": {"isAllMatch": True},
                "destination": {
                    "isAllMatch": False,
                    "patterns": [{"pattern": branch, "isPrefix": False}],
                },
                "autoCancel": True,
            },
            False,  # clean
        ),
        (
            "Tag to TestFlight",
            "v* タグのpushでアーカイブしてTestFlight内部配布（app-kickoff自動生成）",
            "tagStartCondition",
            {
                "source": {"isAllMatch": False, "patterns": [{"pattern": "v", "isPrefix": True}]},
                "autoCancel": True,
            },
            True,  # clean（リリースビルドはクリーンビルド）
        ),
    ]

    for name, desc, key, cond, clean in plans:
        if name in existing:
            print(f"SKIP: '{name}' は既に存在します")
            continue
        body = build_workflow_body(
            name, desc, key, cond, clean, scheme, container_path,
            product_id, repo_id, xcode_id, macos_id,
        )
        created = api("POST", "/v1/ciWorkflows", body)
        print(f"OK: '{name}' を作成しました（id={created['data']['id']}）")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)

    p1 = sub.add_parser("register-bundle-id")
    p1.add_argument("identifier")
    p1.add_argument("name")

    p2 = sub.add_parser("status")
    p2.add_argument("app_name", nargs="?")

    p4 = sub.add_parser("check-onboarded")
    p4.add_argument("app_name")

    p3 = sub.add_parser("create-workflows")
    p3.add_argument("app_name")
    p3.add_argument("--scheme")
    p3.add_argument("--project")
    p3.add_argument("--branch", default="main", help="PRの宛先ブランチ（リポジトリのデフォルトブランチ。既定: main）")

    args = parser.parse_args()
    if args.cmd == "register-bundle-id":
        register_bundle_id(args.identifier, args.name)
    elif args.cmd == "status":
        status(args.app_name)
    elif args.cmd == "check-onboarded":
        check_onboarded(args.app_name)
    elif args.cmd == "create-workflows":
        create_workflows(args.app_name, args.scheme, args.project, args.branch)


if __name__ == "__main__":
    main()
