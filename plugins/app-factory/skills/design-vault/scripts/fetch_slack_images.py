#!/usr/bin/env python3
"""Slack のデザイン収集チャンネルから未取り込みの画像を design-vault/inbox/ に落とす。

前回取り込んだ位置を state ファイル（vault/.slack_state.json）に記録するので、
何度実行しても同じ画像を二重に取り込まない。分析はしない（Claude 本体の仕事）。

必要な Slack スコープ: channels:history, groups:history, files:read
（既存の SLACK_BOT_TOKEN が全て保有済み。bot をチャンネルに招待するだけでよい）

使い方:
    python3 fetch_slack_images.py --vault ~/dev/prd-vault/design-vault
    python3 fetch_slack_images.py --vault ... --channel C0123ABCD --dry-run
"""

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

SLACK_API = "https://slack.com/api"
MAX_EDGE = 1200  # 保存する画像の長辺（px）。これ以上は sips で縮める


def api_get(method, token, params):
    """Slack Web API を叩いて JSON を返す。ok:false は例外にする。"""
    url = f"{SLACK_API}/{method}?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=30) as res:
        body = json.load(res)
    if not body.get("ok"):
        err = body.get("error", "unknown_error")
        if err == "not_in_channel":
            raise SystemExit(
                "エラー: bot がチャンネルにいません。Slack で対象チャンネルを開き\n"
                "  /invite @<bot名>\n"
                "を実行してから再試行してください。"
            )
        raise SystemExit(f"Slack API エラー ({method}): {err}")
    return body


def iter_messages(token, channel, oldest):
    """チャンネルのメッセージを古い順に返す（スレッド返信も含める）。"""
    cursor = None
    pages = []
    while True:
        params = {"channel": channel, "limit": 200, "oldest": oldest}
        if cursor:
            params["cursor"] = cursor
        body = api_get("conversations.history", token, params)
        pages.extend(body.get("messages", []))
        cursor = body.get("response_metadata", {}).get("next_cursor")
        if not cursor:
            break

    for msg in sorted(pages, key=lambda m: float(m.get("ts", 0))):
        yield msg
        # スレッドにまとめて画像を貼るケースを拾う
        if msg.get("thread_ts") == msg.get("ts") and msg.get("reply_count"):
            replies = api_get(
                "conversations.replies",
                token,
                {"channel": channel, "ts": msg["ts"], "limit": 200, "oldest": oldest},
            )
            for reply in replies.get("messages", []):
                if reply.get("ts") != msg.get("ts"):
                    yield reply


def download(token, url, dest):
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=60) as res:
        data = res.read()
    with open(dest, "wb") as fh:
        fh.write(data)
    return len(data)


def shrink(path):
    """長辺 MAX_EDGE の JPEG に変換する（macOS 標準の sips を使う）。失敗しても致命傷にしない。"""
    jpg = os.path.splitext(path)[0] + ".jpg"
    try:
        subprocess.run(
            ["sips", "-Z", str(MAX_EDGE), "-s", "format", "jpeg", path, "--out", jpg],
            check=True,
            capture_output=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return path  # sips が無い/失敗したら原本をそのまま使う
    if jpg != path and os.path.exists(jpg):
        os.remove(path)
    return jpg


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vault", required=True, help="design-vault ディレクトリ")
    ap.add_argument("--channel", default=os.environ.get("SLACK_DESIGN_CHANNEL_ID"))
    ap.add_argument("--token", default=os.environ.get("SLACK_BOT_TOKEN"))
    ap.add_argument("--since", help="この epoch 秒以降だけ取り込む（state を無視）")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    if not args.token:
        raise SystemExit("SLACK_BOT_TOKEN が未設定です（$APP_FACTORY_HOME/.env を読み込んでください）")
    if not args.channel:
        raise SystemExit("SLACK_DESIGN_CHANNEL_ID が未設定です（--channel でも指定できます）")

    vault = os.path.expanduser(args.vault)
    inbox = os.path.join(vault, "inbox")
    state_path = os.path.join(vault, ".slack_state.json")
    os.makedirs(inbox, exist_ok=True)

    state = {}
    if os.path.exists(state_path):
        with open(state_path) as fh:
            state = json.load(fh)
    oldest = args.since or state.get("last_ts", "0")

    fetched = []
    latest_ts = float(oldest or 0)

    for msg in iter_messages(args.token, args.channel, oldest):
        ts = float(msg.get("ts", 0))
        latest_ts = max(latest_ts, ts)
        for f in msg.get("files") or []:
            if not (f.get("mimetype") or "").startswith("image/"):
                continue
            url = f.get("url_private_download") or f.get("url_private")
            if not url:
                continue
            ext = os.path.splitext(f.get("name") or "")[1] or ".png"
            stem = f"{time.strftime('%Y%m%d', time.localtime(ts))}-{f['id']}"
            dest = os.path.join(inbox, stem + ext)
            if os.path.exists(dest) or os.path.exists(os.path.splitext(dest)[0] + ".jpg"):
                continue

            if args.dry_run:
                fetched.append({"image": dest, "dry_run": True})
                continue

            download(args.token, url, dest)
            dest = shrink(dest)
            meta = {
                "slack_file_id": f["id"],
                "slack_ts": msg.get("ts"),
                "posted_at": time.strftime("%Y-%m-%d %H:%M", time.localtime(ts)),
                "original_name": f.get("name"),
                "permalink": f.get("permalink"),
                # メッセージ本文はアプリ名や着目点のヒントになるので必ず残す
                "message_text": (msg.get("text") or "").strip(),
                "image": os.path.basename(dest),
                "analyzed": False,
            }
            with open(os.path.join(inbox, stem + ".json"), "w") as fh:
                json.dump(meta, fh, ensure_ascii=False, indent=2)
            fetched.append(meta)

    if not args.dry_run and fetched:
        with open(state_path, "w") as fh:
            json.dump({"last_ts": f"{latest_ts:.6f}", "channel": args.channel}, fh, indent=2)

    print(json.dumps({"fetched": len(fetched), "inbox": inbox, "items": fetched},
                     ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
