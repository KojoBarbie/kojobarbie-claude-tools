#!/bin/bash
# App Store をキーワード検索し、上位アプリの概要をTSVで返す（競合チェック用）
# Usage: jp_appstore_search.sh "検索語" [limit] [country]
#   出力: アプリ名 \t 評価件数 \t 平均評価 \t 価格 \t ジャンル \t 最終更新日 \t URL
set -euo pipefail

TERM="${1:?検索語を指定してください}"
LIMIT="${2:-10}"
COUNTRY="${3:-jp}"

ENCODED=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$TERM")

curl -s --max-time 30 "https://itunes.apple.com/search?term=${ENCODED}&country=${COUNTRY}&entity=software&limit=${LIMIT}" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except json.JSONDecodeError:
    print('ERROR: APIレスポンスが不正です', file=sys.stderr); sys.exit(1)
results = d.get('results', [])
if not results:
    print('(該当なし)')
for r in results:
    print('\t'.join([
        (r.get('trackName') or '')[:50],
        str(r.get('userRatingCount', 0)),
        '%.1f' % (r.get('averageUserRating') or 0),
        r.get('formattedPrice', ''),
        (r.get('genres') or [''])[0],
        str(r.get('currentVersionReleaseDate', ''))[:10],
        r.get('trackViewUrl', ''),
    ]))
"
