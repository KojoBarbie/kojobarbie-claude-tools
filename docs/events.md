# データ契約 — App Factory が外に出すもの

App Factory は**通知しない**。状態とイベントをファイルに落とすところまでが責務で、
「それを誰にどう知らせるか」は利用者が自分で決める。

この文書はその境界にあるデータの仕様。ここに書かれたものだけが公開インターフェースで、
これ以外（ログの書式、内部の一時ファイル）は予告なく変わる。

## なぜ配送を持たないか

以前は各スキル・各ジョブが直接 Slack に投稿していた。`SLACK_WEBHOOK_URL_FACTORY` /
`_PRD` / `_FEATURE` というチャンネル分類がスキル本文にハードコードされていて、
これは「利用者の Slack がどう仕切られているか」の知識であり、プラグインが持つべきものではない。

実際これは壊れた。スキルは `_FACTORY` に出すつもりで書かれていたが利用者の `.env` に
その変数が無く、`${A:-$B}` のフォールバックで黙って別チャンネルに合流し、
**エラーも出ないまま全通知が1チャンネルに積み上がった**（1週間で84通・105,000字）。

配送手段を持たなければこの壊れ方はしない。

## 3つの層

| 層 | 実体 | 誰が書くか |
|---|---|---|
| **状態** | GitHub（判断ブロック `judge:v1`・ラベル・issue/PR）と `portfolio.yml` | スキルが直接書く。**このリポジトリは何も足さない** |
| **イベント** | `$APP_FACTORY_HOME/data/events.jsonl` | 各ジョブ・スキルが追記する |
| **派生スナップショット** | `$APP_FACTORY_HOME/data/pending.json` | `run_factory_reminder.sh` が上書き生成する |
| 通知 | — | **利用者の担当**（リファレンス実装: `cron/scripts/notify_stdout.sh`） |

状態の大半は既に GitHub にある。判断待ちの PR も、承認待ちの機能提案も、
`needs-clarification` の issue も、GitHub に問い合わせれば取れる。
だから受け手を作るのに `events.jsonl` は必須ではない — GitHub だけでダッシュボードは作れる。

`events.jsonl` が担うのは GitHub に残らないもの、すなわち
**「その実行で何が起きたか」**（何を作り、何を見送り、なぜ止まったか）だけ。

## events.jsonl

1行1イベントの JSON（JSONL）。**追記専用**で、既存行は書き換えない。

```json
{"ts":"2026-08-21T13:04:02+09:00","job":"factory-build","kind":"pr_opened","severity":"action","app":"AntiScroll","title":"シールド画面の初期表示を短縮","url":"https://github.com/owner/antiscroll/pull/212","meta":{"issue":"190","judge_type":"run","cost":"5"}}
```

### フィールド

| キー | 必須 | 内容 |
|---|---|---|
| `ts` | ✓ | ISO 8601（タイムゾーン付き）。`emit_event` が自動で入れる |
| `job` | ✓ | 発生源のジョブ/スキル名（`factory-build` / `store-release` / `portfolio-review` ほか） |
| `kind` | ✓ | 何が起きたか。下表の閉じた語彙のみ |
| `severity` | ✓ | `info` / `action` / `error` の3値のみ |
| `app` | | 対象アプリ名。アプリに紐づかないイベントでは省略 |
| `title` | | 人間が読む1行。300字で切られる |
| `url` | | GitHub の PR / issue など、その場へ行ける URL |
| `meta` | | 任意の補助情報。**値は全て文字列**（受け手が型を推測しなくて済むように） |

### severity — 受け手が分岐に使う唯一のフィールド

| 値 | 意味 | 受け手の想定挙動 |
|---|---|---|
| `info` | 起きたことの記録。人間は何もしなくてよい | タイムラインに積む。通知しない |
| `action` | **人間が動かないと止まる** | 通知する |
| `error` | ジョブが失敗した。仕組み側の問題 | 通知する |

`action` を安売りしないこと。「見ておいたほうがいい」は `info` であって `action` ではない。
`action` の定義は「これを放置すると何かが進まない」。

### kind — 閉じた語彙

自由文字列にすると受け手が書けなくなるので、増やすときはこの表に足す。

| kind | severity の目安 | 意味 |
|---|---|---|
| `job_started` | `info` | ジョブが起動した。**必ず最初に出す**（ハートビート） |
| `job_finished` | `info` | ジョブが正常終了した。`meta.summary` に1行サマリ |
| `job_failed` | `error` | ジョブが異常終了した |
| `job_skipped` | `info` | 事前判定で用が無く、何もせず終えた。`meta.reason` |
| `pr_opened` | `action` / `info` | PR を作った。人間の判断が要るなら `action` |
| `pr_merged` | `info` | PR をマージした |
| `pr_closed` | `info` | PR を閉じた |
| `comment_answered` | `action` | 人間のコメントに修正・返信した（**下記の同一名義問題**） |
| `blocked` | `action` | 自動実装が詰まった（`factory-blocked`） |
| `needs_input` | `action` | 要件が確認できず人間に投げた（`needs-clarification`） |
| `human_task` | `action` | 人にしかできない外部作業を切り出した（`human-task`） |
| `budget_reached` | `action` | 判断キューが予算に達し、新規着手を止めた |
| `proposal_opened` | `action` | 機能提案・PRD を起票した。承認待ち |
| `release_prepared` | `action` | リリース列車を用意した。提出承認待ち |
| `release_submitted` | `info` | App Store に提出した |
| `review_passed` | `info` | 審査を通過した |
| `review_rejected` | `action` | 審査でリジェクトされた |
| `report` | `info` | 週報・監査レポートなど。`meta.body` に本文 |

### ハートビート

`job_failed` は「ジョブが走って失敗した」しか表現できない。
**ジョブが起動すらしなかった場合はイベントが1行も出ない**ので、失敗として検知できない。

そのため全ジョブは処理の前に必ず `job_started` を出す。
受け手は「今日 `factory-build` の `job_started` が3回無い」を異常として扱えばよい。

### 同一名義問題（`comment_answered` がある理由）

この運用では bot も人間も同じ GitHub アカウントを使うため、
**bot が PR に返信しても人間に GitHub 通知が飛ばない**。
「返してくれたのか分からない」でループが閉じなくなるので、
人間のコメントに対応したときは PR 1本ごとに `comment_answered` を出す。

### 既読は持たない

`events.jsonl` に既読フラグは無いし、追加もしない。
どこまで見たかは**受け手が自分の `last_seen_ts` を持つ**。
既読はインターフェースの都合であって、事実の記録ではない。

### 行の書き換えをしない理由

`factory-build` は1日3回、`factory-dispatch` と時間帯が重なりうる。
追記専用なら並行実行でも壊れない。1行は 4096 バイト未満に収まるよう
`title` と `meta` の各値を 300 字で切っているので、`O_APPEND` の追記が分断されない。

### ローテーション

このリポジトリは行わない。肥大が問題になったら受け手側で切る
（`events.jsonl` を月次でリネームする等）。プラグインは常に末尾に追記するだけ。

## pending.json

「いま人間の行動を待っているもの」の一覧。`run_factory_reminder.sh` が実行のたびに
**全部入りで上書き**する（差分ではない）。events.jsonl と違い、これは現在の状態のスナップショット。

```json
{
  "generated": "2026-08-21T12:00:00+09:00",
  "budget_minutes": 45,
  "judge": { "count": 17, "cost_total": 53, "over_budget": true, "blocked": 4 },
  "degraded": ["Tanamori"],
  "groups": [
    {
      "key": "judge_look",
      "label": "見るだけ",
      "hint": "各10秒・スクショを見て OK なら通す",
      "action": "内容を見て問題なければマージ、不要ならクローズ",
      "default_if_ignored": "期限を過ぎたら自動でマージ/クローズされます",
      "items": [
        { "app": "Tanamori", "type": "pr", "ref": 12, "title": "CI が落ちています。…",
          "url": "https://github.com/…/pull/12", "cost": 0.2, "due": "あと17日",
          "ci": "failing", "mergeable": "MERGEABLE", "blocked": true,
          "asked_at": "2026-08-18" }
      ]
    }
  ]
}
```

| キー | 内容 |
|---|---|
| `judge.cost_total` | 判断ブロックの `cost` 合計（分）。`budget_minutes` に達すると新規着手が止まる |
| `judge.over_budget` | 止まっているかどうか。受け手はこれを強調するとよい |
| `judge.blocked` | `blocked` な項目の数（下記） |
| `degraded` | GitHub API から取得できなかったリポジトリ名。**空でなければ件数は実際より少ない** |
| `groups[].key` | 機械が使う識別子（`judge_look` / `judge_run` / `judge_decide` / `judge_other` / `human_task` / `prd_pr` / `release_train` / `feature_proposal` / `factory_blocked` / `needs_clarification` / `app_review_rejected` / `onboarding`） |
| `groups[].default_if_ignored` | **放置したら何が起きるか**。これが無い催促は判断材料にならない |
| `groups[].items` | **省略も丸めもしない**。「上位5件だけ」は表示側の判断なので受け手がやる |

### items の項目

| キー | 内容 |
|---|---|
| `title` | 判断ブロックの `ask`。**書かれた時点の静的テキスト**なので、下記と必ず照合すること |
| `ci` | `ok` / `failing` / `pending` / `none`（PR のみ） |
| `mergeable` | `MERGEABLE` / `CONFLICTING` / `UNKNOWN`（PR のみ） |
| `blocked` | `ci == "failing"` または `mergeable == "CONFLICTING"`。**人間が `title` の依頼をこなしても、そのままではマージできない** |
| `asked_at` | `title` が書かれた日（`YYYY-MM-DD`）。古い判断ブロックには無い |

### なぜ ci / mergeable を必ず入れるのか

`title`（= `ask`）は PR 本文に埋め込まれた静的テキストなのに、内容は
CI やコンフリクトという**動的な事実**を指すことが多い。両者は放っておくと必ずズレる。

実測された壊れ方（2026-08-20）:

- **直ったのに「壊れています」と言い続ける** — 人間の「コンフリしてるので直して！」に
  bot が6時間後に解消して返信したが、ask は「コンフリクトしています」のまま。
  判断キューに2日間その文面が出続け、人間は「まだ壊れている」と読んで飛ばし続けた
- **壊れているのに「実機で確認してください」と言う** — ask が「実機で広告を1本見て…（5分）」の
  PR が実は `CONFLICTING`。人間が5分かけて確認してもマージできない

**受け手は `title` を単独で表示してはいけない。** `ci` と `mergeable` を必ず併記して、
人間が「まだ本当にそうなのか」を照合できるようにする。
`blocked` が立っているものは、依頼をこなしても進まないことを明示する。

書き手側（`factory-build` / `ship-issue`）が ask を書き直す責任も別途あるが、
それは人間の指示に依存するので、**受け手側の併記が機械的な保険**になる。

`degraded` を明示するのは、取得失敗を黙って0件にすると
**実際より状況が軽く見える**という一番まずい壊れ方をするため。

## 受け手の作り方

リファレンス実装が `cron/scripts/notify_stdout.sh` にある。
`pending.json` と当日の `events.jsonl` を人間可読に整形して標準出力に出すだけで、
配送は何もしない。`cron` に繋いでもいいし、手で叩いてもいい。

Slack・メール・自前ダッシュボードなどに繋ぐ例は
[README の「通知を繋ぐ」](../README.md#通知を繋ぐ) にある。
