#!/bin/bash
# App Store のカスタマーレビュー（最新50件）を取得してTSVで返す（iTunes RSS・APIキー不要）
# Usage: appstore_reviews.sh <app_id> [country]
#   出力: 評価 \t 日付 \t バージョン \t タイトル \t 本文（改行はスペースに置換）
# 注: RSSのpage=指定はApple側が応答しなくなったため使わない。最新50件で十分。
set -euo pipefail

APP_ID="${1:?App Store の数値IDを指定してください}"
COUNTRY="${2:-jp}"

curl -s --max-time 30 \
  "https://itunes.apple.com/${COUNTRY}/rss/customerreviews/id=${APP_ID}/sortby=mostrecent/json" \
| python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except json.JSONDecodeError:
    print('(レビューなし、またはApp ID不正)', file=sys.stderr)
    sys.exit(0)
entries = d.get('feed', {}).get('entry', [])
if isinstance(entries, dict):
    entries = [entries]
for e in entries:
    rating = e.get('im:rating', {}).get('label', '')
    updated = e.get('updated', {}).get('label', '')[:10]
    version = e.get('im:version', {}).get('label', '')
    title = e.get('title', {}).get('label', '').replace('\t', ' ')
    content = e.get('content', {}).get('label', '').replace('\n', ' ').replace('\t', ' ')
    print('\t'.join([rating, updated, version, title, content]))
"
