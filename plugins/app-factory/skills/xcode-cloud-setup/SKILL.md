---
name: xcode-cloud-setup
description: "App Store Connect APIでXcode CloudのTestFlightワークフロー2本（PRトリガー・タグトリガー）を作成し、Bundle ID登録も行う。Use when: (1)「○○のXcode Cloudワークフロー作って」「Xcode Cloud設定して」と言われたとき、(2) app-kickoffからBundle ID登録を頼まれたとき、(3) TestFlight配信の自動化・CI/CD設定を頼まれたとき。前提: 対象アプリがXcode Cloudにオンボーディング済み（初回のみXcodeでの手動操作が必要）。"
---

# Xcode Cloud Setup

## 前提

**最初に `~/.config/app-factory/config.env` を読み込む**（無ければ各変数はデフォルト値: `APP_FACTORY_HOME=~/dev/business/claude-cron`、`GITHUB_OWNER=KojoBarbie`、`BUNDLE_ID_PREFIX=com.kojobarbie`）。

App Store Connect API（`$APP_FACTORY_HOME/.env` の `APP_STORE_*` キー）でXcode Cloud関連を自動化する。

## Appleの制約（前提知識）

- **アプリレコード作成**（ASC上の「アプリ」）と**Xcode Cloud初回オンボーディング**（ciProduct作成＋GitHub接続）はAPIに作成エンドポイントがなく、ユーザーのUI操作が必須。この2つが済んでいないのにワークフロー作成を頼まれたら、状態を確認して手順を案内する
- それ以外（Bundle ID登録、ワークフロー作成・変更、ビルド起動）はすべてAPIで可能

## スクリプト

すべて `python3 {skill_dir}/scripts/asc_cloud.py <subcommand>` で実行する。実行前に `.env` を読み込むこと:

```bash
[ -f ~/.config/app-factory/config.env ] && . ~/.config/app-factory/config.env
set -a && source "${APP_FACTORY_HOME:-$HOME/dev/business/claude-cron}/.env" && set +a
```

| サブコマンド | 用途 |
|---|---|
| `register-bundle-id <identifier> <name>` | Bundle ID登録（例: `register-bundle-id "${BUNDLE_ID_PREFIX}.hirune" Hirune`）。登録済みなら成功扱い |
| `status [AppName]` | ciProducts・接続済みリポジトリ・既存ワークフローの一覧（オンボーディング状態の確認に使う） |
| `create-workflows <AppName> [--keep-others]` | TestFlightワークフロー2本を作成し、それ以外を削除（下記） |
| `setup-beta-group <bundle_id> [--group-name developer] [--testers a@b,c@d]` | 内部TestFlightグループを用意（無ければ作成・`hasAccessToAllBuilds=true`＝全ビルド自動配信ON）し、既存ASCユーザーをテスター追加。冪等 |

## create-workflows が作る2本

1. **PR to TestFlight** — mainターゲットのPRが更新されるたびにアーカイブ→TestFlight内部配布
2. **Tag to TestFlight** — `v*` タグのpushでアーカイブ→TestFlight内部配布

スクリプトは ciProduct / scmRepository / 最新のXcode・macOSバージョンID（"Latest Release"優先＝自動追従）を自動解決する。オプション: `--scheme`（省略時はAppName）、`--project`（省略時は `{AppName}.xcodeproj`）、`--branch`（PRの宛先＝リポジトリのデフォルトブランチ。既定 `main`。**実行前に `gh repo view "$GITHUB_OWNER"/{AppName} --json defaultBranchRef` で必ず確認して合わせる**）。

## この2本以外は削除する

作成後、**この2本以外のワークフローは削除する**（`--keep-others` で抑止できる）。Xcodeのオンボーディングは必ず `Default` を1本作るが、これは残しておく理由がない:

- `Default` は main への push ごとに走るため、PR用ワークフローと二重にビルドが動いてXcode Cloudの計算時間を食う
- Xcodeがスキームを取り違えることがある（ウィジェット拡張のスキームが選ばれ、走るたびに必ず失敗する例が実際にあった）
- オンボーディングをやり直すと `Defaultd` `Defaultaaa` のような名前違いが積み上がる

**注意**: DayMarks・Pitakiri・antiscroll・MileDay のように独自名のワークフローを持つ既存アプリに対して実行すると、それらも消える。既存アプリに足すだけのときは `--keep-others` を付ける。

## 自動検知の仕組み（前提）

通常はこのスキルを手で呼ぶ必要はない。`app-kickoff` がアプリ名を `$APP_FACTORY_HOME/.data/pending_xcode_cloud.txt` に登録し、承認チェックジョブ（`run_prd_approval_check.sh`、毎日9時/21時）が `check-onboarded` でポーリング → 検知したら `create-workflows` 実行 → Slack通知、まで全自動で行う。3日以上未完了のアプリには3日おきに手動タスクのチェックリストをSlackに再送する。このスキルを手動で使うのは、自動作成が失敗したときのリカバリーや、既存アプリへの追加設定のとき。

## 手順

1. `status <AppName>` でオンボーディング状態を確認
2. ciProductが見つからない場合: ユーザーに手動手順を案内して終了 — 「App Store Connectでアプリ作成（Bundle IDは登録済み）→ Xcodeで Product > Xcode Cloud > Create Workflow（GitHub接続もこの流れで）。終わったらもう一度声をかけてください」
3. ciProductがある場合: `create-workflows <AppName>` を実行し、作成された2本のワークフロー名とIDを報告。既存ワークフローと重複する名前があればスキップして報告。削除したワークフローがあれば何を消したかも報告する
4. 結果をSlack（`$SLACK_WEBHOOK_URL_PRD`）に短く通知する（キックオフの流れで呼ばれた場合のみ）

## トラブルシューティング

- 403 Forbidden: APIキーの権限不足（App Manager以上が必要）。キーのロールをASCで確認するようユーザーに伝える
- ciProductはあるがrepositoryが見つからない: GitHub接続が未完了。Xcode Cloudオンボーディングのやり直しを案内
- **`status` / `check-onboarded` が「未オンボーディング」と言うのに、ユーザーはXcodeで作成できたと言う**: `/v1/ciProducts` の一覧はオンボーディング直後の製品を数時間返さないことがある（2026-08-11 に実測）。`scmRepositories` には先に現れるので、**リポジトリだけ登録済みでciProductが無い状態を「未オンボーディング」と断定しない**。時間を置いて再実行する。急ぐならXcodeのキャッシュ（`~/Library/Caches/com.apple.dt.Xcode/fsCachedData/` 配下のJSON）にASCが返した製品一覧が残っているので、そこからciProductのidを拾える
- **ユーザーが「そのワークフローはすでに存在します」というエラーに当たった**: ワークフロー名がユニークである必要があるのは**ciProduct単位**。同じアプリに既に `Default` がある＝オンボーディングは前回すでに成功している。他リポジトリの同名ワークフローとは衝突しないので、そちらを疑わない
