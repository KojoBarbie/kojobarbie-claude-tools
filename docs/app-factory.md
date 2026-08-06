# App Factory — 週次でアプリが生まれ、育ち続ける自動ワークフロー

> 作成: 2026-07-09（v2: 設計レビュー反映）。目標: **1年後に全アプリ合計で月5〜10万円**の収益。
> セットアップ手順・必要なキー・残る人力作業の一覧は [setup-runbook.md](setup-runbook.md)。
> 仮説: 「大量に出す → 計測して見込みを判定する → 見込みのある芽にだけ投資を寄せる」を
> 人手最小で回し続ければ、当たるアプリができて日銭を稼げる。

## 0. 全体像

既存パイプライン（app-idea-hunt → prd-approval-check → app-kickoff → xcode-cloud-setup →
feature-hunt → ship-issue → quality-release-cycle）に、欠けていた輪をスキルとして追加し、
1本のサイクルに閉じる。

```
                 ①出す                          ②検証・改善                ③育てる
┌────────────────────────────────────┐ ┌─────────────────────┐ ┌──────────────────┐
│ app-idea-hunt（JTBD分析+KPI設計 ☆）│ │ portfolio-review ★  │ │ feature-hunt      │
│   ↓ [人:PRDマージ]                 │ │  (KPI計測→ゲート    │ │   ↓ [人:👍/go]    │
│ app-kickoff ─→ [人:ASC+Xcode 5分] │ │   判定→週報)        │ │ growth-advisor ★  │
│   ↓                                │ │ quality-release-    │ │   ↓               │
│ factory-build ★ (自律実装×3/日)    │ │ cycle audit         │ │ factory-build ★   │
│   ↓                                │ │   ↓                 │ │   ↓               │
│ store-release ★ ─→ App Store      │ │ factory-build ★     │ │ store-release ★   │
└────────────────────────────────────┘ └─────────────────────┘ └──────────────────┘
      ★ = 新スキル4本（app-factory プラグイン）  ☆ = 既存スキルの強化

   状態の一元管理: prd-vault/portfolio.yml（全アプリのステージ・KPI・メトリクス）
   実行の分散管理: $APP_FACTORY_HOME/data/factory_schedule.tsv（曜日×リポジトリの割当表）★
   人間の接点: 週報1通 + PRDマージ + 機能👍 + 新規アプリのASC/Xcode(5分)
   人間からの起点: prd-vault に idea ラベルのissue = 作りたいネタの指名（任意・下記1章）
```

設計原則:

1. **状態は portfolio.yml に一元化** — どのジョブも「いま何をすべきか」を自分で考えず、
   portfolio.yml のステージから機械的に導く。ステージを書き換えられるのは portfolio-review だけ。
2. **人間の判断は「価値があるか」だけに絞る** — PRDの筋（ジョブ分析の妥当性）と大きめ機能の承認は
   人間。実装・テスト・マージ・リリース段取り・計測・ステージ判定は全部AI。
3. **計測は後付けしない** — 何を計測すれば収益への道筋が分かるかを **PRD の時点で** KPI ツリーと
   マイルストーンに落とす。計測実装は MVP issue に必ず含める（リリース後に「数字がない」を防ぐ）。
4. **トークン消費は分散させる** — 全リポジトリ一括実行のジョブを作らない。
   リポジトリ横断ジョブは「1日1リポジトリ」の割当表方式で月〜金に分散する。
5. **人間の接点はすべて Slack に集約** — 意思決定が必要なものは金曜の週報1通に必ず再掲。
   見落としてもサイクルは止まらない（デフォルト動作が決まっている）。
6. **安全レールで暴走を防ぐ** — auto-merge には機械的な条件、ストア提出には人間の承認ゲート（approved）、
   失敗の繰り返しにはブロックラベル。

## 1. ①出す — アイデアの質を上げる（app-idea-hunt の強化）

現状の app-idea-hunt は「海外でそこそこ売れている」ことを起点にスコアリングして PRD 化するが、
**なぜ売れているのか（どんなジョブを雇われているのか）の分解が仕組みとして担保されていない**。
以下を SKILL.md とPRDテンプレートの必須セクションとして追加する:

### JTBD 分析（PRD 新セクション「ジョブ分析」）

1. **ジョブ分解**: 元ネタのサービスをジョブ理論で分解する。
   - 機能的ジョブ（何を片付けたいのか）/ 感情的ジョブ（どう感じたいのか）/ 社会的ジョブ（どう見られたいのか）
   - 「誰が・どんな状況で・何の代わりに」雇っているか（競合は同カテゴリアプリとは限らない —
     紙のメモ・我慢・配偶者への口頭依頼なども代替品）
2. **人気の因果仮説**: なぜ海外で人気/急上昇しているのか。
   - ジョブ自体が新しく生まれた（規制・流行・プラットフォーム変化）のか、
     既存ジョブの解決コストを下げたのか、単にマーケがうまいだけなのか
   - 急上昇の場合はきっかけ（バイラル・特集・季節性）を特定し、再現可能性を評価
3. **日本への移転可能性**: 日本に持ってきたとき、ジョブとサービスの対応が保存されるか。
   - 同じ状況・同じジョブが日本に存在するか（生活習慣・制度・文化の差分を明示）
   - 日本では別の解決手段が既に支配的でないか
   - ジョブは同じでもサービス側の調整が必要な点（決済感覚・トーン・ローカル制度対応）
4. **人間チェックの明示**: この分析が PRD レビュー（PRマージ判断）の主眼であることを
   PR 本文に明記する。人間は「コードの見積もり」ではなく「ジョブ分析が信じられるか」を見る。

### KPI ツリーとマイルストーン（PRD 新セクション「KPIと計測計画」）

収益性スコアで終わらせず、**収益に至る因果チェーンを先に引いておく**。後の portfolio-review が
このセクションをそのまま判定基準として使う。

1. **KPI ツリー**: 収益 ← 収益化ファネル（例: ペイウォール到達率 × トライアル開始率 × 転換率、
   広告なら DAU × セッション数 × 表示単価）← 継続（D1/D7/D30）← アクティベーション
   （初回セッションでコア行動を完了した率）← DL。アプリごとに「コア行動」を1つ定義する。
2. **計測イベント一覧**: Firebase Analytics に仕込むイベント名を PRD に列挙
   （`core_action_completed`、`paywall_viewed` 等）。**app-kickoff はこれを「計測実装」issue として
   必ず MVP issue に含める**。
3. **マイルストーン**（初期値。アプリ特性で PRD が上書き）:
   - M0: リリース
   - M1（リリース+4週）: DL 累計 ≥ 100 / アクティベーション率 ≥ 40% / D1 ≥ 15%
   - M2（+8週）: 収益初発生、または DAU ≥ 10 で増加傾向
   - M3（+16週）: 月次収益 ≥ 5,000円
4. **数値は必ず具体値**: M1〜M3 の基準はグローバル初期値の丸写しを禁止し、カテゴリ水準・
   元ネタアプリの実績・想定市場規模から根拠1行付きでアプリ固有の数値を置く。収益目標は
   「収益化手段 × 想定転換率 × 必要ユーザー数」の算数を1行書く
5. **見送り基準も先に書く**: 「M1 未達なら maintain 行き」を PRD 時点で合意しておく
   （リリース後に情が湧いてズルズル投資するのを構造的に防ぐ）。

### モックとトンマナ（PRD と同じ PR でレビュー）

「文章の PRD だけでは Go 判断がしづらい」を解消するため、app-idea-hunt は PRD と同時に
**モック**（コア画面の見た目）と**トンマナ**（配色・タイポ・ムード）を作り、
prd-vault 内の **showcase サイト**（`showcase/`、Next.js 静的エクスポート → Vercel）に集約する:

- アプリごとに2ページ: `/apps/<slug>/tone`（パレット・タイポグラフィ・Do/Don't。ダークモード
  禁止の規約を反映）と `/apps/<slug>/mock`（iPhone フレーム内のコア画面1〜2枚。トンマナ準拠）
- PRD の PR に同じブランチで含める → **人間は PR 1本で「ジョブ分析・KPI 数値・見た目」を
  まとめてレビュー**できる。Slack 通知に showcase の URL を添える
- 一覧ページ（`/`）が全アプリのモック/トンマナ/ステータスのカタログになる
- app-kickoff のデザインコンセプトシートは tone ページを正として引き継ぐ
- Vercel プロジェクト `pv-showcase-12ced869` が prd-vault に接続済み。**PR ごとにプレビューが自動デプロイされ PR にコメントが付く**ので、人間の接続作業はもう無い
- showcase だけ Vercel なのは、PR プレビューと Vercel Authentication による認証ゲートが効くため。**LP は「製品やサービスの販売の宣伝」に当たり Hobby の非商用条件を外れるので Firebase Hosting のまま**（この使い分けを崩さない）

### 指名モード（人間の側から「これを作りたい」と言う口）

週次の自動提案は「AIが探してきたものを人間が承認する」一方向で、**人間から起点を作る口が無かった**。
結果、`ideas/`（選定に漏れた次点候補）が溜まる一方で、Step 0 の重複回避ルール
（過去に提案・却下したネタを再提案しない）によって構造的に再浮上しない状態になっていた
— 「hirune が一段落したら再評価」とメモされた案があっても、再評価するジョブが存在しない。

prd-vault に **`idea` ラベルの issue** を立てる入口を追加してこれを埋める:

- **入口を GitHub issue にした理由**: App Factory の人間判断はすべて issue/PR に集約されている
  （feature-hunt の `go`／store-release の `approved`／PRD の マージ・クローズ）。ここだけ Slack にすると
  経路が2系統になる。Slack は全ジョブで**送信専用**に徹させ、双方向にしない
  （将来 Slack から投げたくなったら「Slack → issue を立てるブリッジ」を足せばよく、パイプライン本体は無改造で済む）
- **ポーリングは既存の prd-approval-check（毎日2回）に相乗り**する。新規 launchd ジョブは不要で、
  「対象があるときだけ claude を起動する」既存の節約パターンもそのまま効く
- 1つの入口で2種類を受ける: `ideas/` からの**昇格**（タイトルに slug を書くだけ）と、
  手元アイデアの**持ち込み**（本文に雑に書く。参考元・価格・実績はパイプラインが裏取りする）
- **指名は「発掘を省略する」機能であって「審査を省略する」機能ではない**。除外フィルタ・競合チェック・
  スコアリング・ジョブ分析はすべて通る。ただしスコアは相対選定（上位N本）が成立しないので
  `config.yml` の `nomination_min_score` を通過ラインとした絶対判定に切り替える
- **懸念が出ても bot は issue をクローズしない**。懸念と根拠を 🤖 コメントで提示して止まるだけで、
  ユーザーが返信すれば「承知の上での判断」として PRD 化する（懸念は PRD の「リスクと検証ポイント」に残す）。
  指名を出した本人の意志を AI が否決しない、という原則。ボツにするかは人間が issue を閉じて決める
- 状態は「コメント無し=新規 / 最終コメントが 🤖 =判断待ち / ユーザー返信あり=再開 / `processed`=処理済み」で
  表現する（オープンPRの改訂検知とまったく同じパターンを流用）

## 2. ステージモデル（アプリのライフサイクル）

| ステージ | 意味 | このステージで自動で起きること |
|---|---|---|
| `building` | kickoff済み・MVP issue 残あり | factory-build が最優先で MVP issue を消化 |
| `review` | MVP完了・リリース準備〜Apple審査中 | store-release がメタデータ生成→承認ゲート付き提出→審査追跡 |
| `validating` | リリース後の検証期（デフォルト8週） | KPI計測。audit 対象。改善は監査Issue経由の小粒だけ |
| `growing` | マイルストーン通過＝有望 | feature-hunt 毎週 + growth-advisor 月次 + audit 隔週 + 収益化強化 |
| `maintain` | 見込み薄いが維持 | クラッシュ・審査対応のみ。audit 四半期 |
| `sunset` | 投資停止 | 何もしない（ストア掲載は残す） |

### ステージゲート（portfolio-review が毎週判定）

**判定基準は各アプリの PRD「KPIと計測計画」のマイルストーンが第一**。PRD に無い場合の
グローバル初期値を `portfolio.yml` の `gates:` に置く:

- `validating → growing`: M1 かつ M2 を達成（= コア行動の継続利用が実証され、収益の芽がある）
- `validating → maintain`: 8週経過で M1 未達
- `growing → maintain`: 8週連続で収益・DAU とも横ばい以下
- `maintain → sunset`: 12週 DAU ほぼゼロ
- 逆方向（maintain → growing など）も指標が回復すれば可

判定に迷うケースは自動で降格せず、週報に「要判断」として人間に出す。

## 3. 状態管理

環境依存のパス・識別子（ジョブ実行環境 `$APP_FACTORY_HOME`、PRD リポジトリ `$PRD_VAULT_DIR`、
GitHub owner `$GITHUB_OWNER`、Bundle ID プレフィックス `$BUNDLE_ID_PREFIX`、アプリ生成先 `$APPS_DIR`、
claude CLI `$CLAUDE_BIN`）は `~/.config/app-factory/config.env` に一元化されている
（`cron/install.sh` がテンプレートから生成。詳細は [setup-runbook.md](setup-runbook.md) §0）。
全ジョブ・スキルはまずこれを読み、以下の本文もこの変数名で参照する。

### prd-vault/portfolio.yml（何をすべきかの「脳」）

prd-vault に置く理由: PRD・却下履歴・config.yml（スコアリング重み・月5万円の目標）が既にあり、
「プロダクトの意思決定の記録場所」として確立しているため。git 履歴がそのまま意思決定ログになる。

- `apps[]`: name / repo / path / prd / stage / stage_since / bundle_id / asc_app_id /
  analytics_env_prefix / revenuecat_project / core_action（PRD から転記）等
- `apps[].kpi`: PRD のマイルストーン（M1〜M3）の達成状況
- `apps[].metrics`: 週次スナップショット（downloads_7d / dau_avg / d1_retention /
  activation_rate / crash_free / revenue_7d_jpy / trend）。取れない指標は `unmeasured` と明示
- `gates`: グローバル初期値（PRD が上書き）
- 初回は portfolio-review が自動ブートストラップ（prd/・shipped/・`$APPS_DIR`・
  既存 feature_hunt_apps.txt から生成して main にコミット）

### $APP_FACTORY_HOME/data/factory_schedule.tsv（いつ誰がやるかの「時刻表」）★新設

**リポジトリ横断ジョブ（feature-hunt / audit / growth-advisor）を1日1リポジトリに分散する割当表。**

現状の問題: feature-hunt は火曜に1ジョブで全アプリを直列実行（アプリが増えるほど1回の
トークン消費が膨張）、audit はアプリごとに launchd plist を手作業で追加（スケールしない）。

新方式:

- portfolio-review が毎週金曜、ステージに応じた頻度ルールで**翌週分の割当表を生成**する:
  - growing: feature-hunt 週1 + audit 隔週 + growth-advisor 月1
  - validating: audit 隔週（後期は feature-hunt 隔週も）
  - maintain: audit 四半期 / building・review: なし（factory-build と store-release の領分）
- 割当は月〜金の1日1スロット。溢れた分は優先度順（growing 優先）で翌週に回す
  （dispatcher の実行履歴 `logs/factory_dispatch_history.tsv` から前回実行日を見て自然に優先される）
- **`run_factory_dispatch.sh`（平日 3:00 の launchd ジョブ1本）が当日のスロットを読み、
  該当リポジトリで該当スキルを1本だけ実行**。スロットが空の日は bash 判定だけで即終了
  （claude を起動しない = トークン消費ゼロ。prd-approval-check と同じ節約パターン）
- bash で読むため形式は TSV（`日付 \t アプリ名 \t 絶対パス \t ジョブ`）。
  あわせて bash 事前判定用のミラー `data/factory_apps.tsv`（`name \t path \t repo \t stage`）も
  portfolio-review が毎週再生成する

```
# factory_schedule.tsv の例（portfolio-review が毎週金曜に翌週分を生成。手編集可。パスは portfolio.yml の path）
2026-07-20	ExampleFlutterApp	~/dev/flutter/ExampleFlutterApp	audit
2026-07-21	ExampleApp	~/dev/swift/ExampleApp	feature-hunt
```

これにより既存の audit plist 3本と feature-hunt の全アプリ直列実行は廃止でき、
アプリが何本に増えても「平日5スロット」の中で自動的に頻度調整される。

## 4. 週間カレンダー

深夜帯を積極的に使う: 監査・提案などのリポジトリ横断ジョブは深夜〜早朝に回す。
factory-build だけは滞留解消のスループットを優先して 8時間ごと（5:00 / 13:00 / 21:00）に走らせ、
人が読む通知（提出承認の依頼・週報）は日中に届くようにする。
launchd はスリープ中に時刻を過ぎた場合、次の起床時にまとめて1回実行する。

| 曜日・時刻 | ジョブ | 状態 |
|---|---|---|
| 月 9:00 | app-idea-hunt（JTBD分析+KPI設計を強化 ☆） | 既存を強化 |
| 毎日 9:00 / 21:00 | prd-approval-check（マージ検知→kickoff、Xcode Cloud ポーリング、`idea` issue の指名検知 ☆） | 既存を強化 |
| **平日 3:00** | **factory-dispatch**（割当表に従い feature-hunt / audit / growth-advisor を1日1リポジトリ実行） | ★新規 |
| **8時間ごと 5:00 / 13:00 / 21:00** | **factory-build**（issue を選び自律実装。1回最大3件・同一アプリ1件 = 最大9件/日） | ★新規 |
| **毎日 6:00** | **store-release**（bash 事前判定で用がある日だけ起動。列車起票→承認ゲート→提出→審査追跡） | ★新規 |
| **金 17:00** | **portfolio-review**（計測→ゲート判定→portfolio.yml 更新→翌週の割当表生成→週報） | ★新規 |

廃止・置き換え: 火曜の feature-hunt 一括ジョブ、月/木/金の audit plist 3本 → factory-dispatch に統合
（`cron/install.sh --migrate` で無効化）。

## 5. 新規スキルの責務

### factory-build（実装の自動化 — 現状最大のボトルネック解消）

現状: feature-hunt や audit が Issue を作っても、人間が `ship-issue N` を起動して計画承認するまで
何も進まない。これを**8時間ごと（5:00 / 13:00 / 21:00）**の自動ジョブにする。

- portfolio.yml を読み、`building` → `growing` → `validating`(監査「高」のみ) の順でアプリを走査
- 着手可能な issue を優先度順に選ぶ: MVP issue（kickoff起票・依存順。計測実装 issue を優先）→
  承認済み機能 sub-issue（`feature-approved` の子）→ 監査 issue（高→中）
- 1回の実行で最大3件、**かつ同一アプリからは最大1件**（＝最大3アプリが1変更ずつ。在庫の多いアプリの
  独占を防ぎ、1アプリ＝1ビルド1変更に保って TestFlight の実機確認を切り分け可能にする。回収マージも同制約）。
  issue ごとに **ship-issue の「無人モード」**で自走: プランモードには
  入らないが**計画→実装の順序は守る**。計画（アプローチ・変更ファイル・テスト方針・受け入れ条件の
  解釈）を実装前に issue へ `🤖 実装計画:` コメントとして投稿し、PR 本文にも残す
  （承認ゲートだけを外し、人間が事後に計画へ遡れる形を保つ）
- **auto-merge は段階導入スイッチ（`data/factory_automerge_enabled` の存在）が ON のときだけ**。
  ON でも全条件を満たす必要がある: テスト green + CI green +
  セルフレビューの高 severity 指摘ゼロ + 差分 600 行未満 + マイグレーション・課金・権限まわりを触っていない
- 満たさない場合は PR を open のまま残し、Slack と週報で人間に回す
- **PR 滞留ガード: open PR が10本以上のリポジトリには新規 PR を出さない**（そのアプリの issue は
  1件も着手しない）。回収マージと人間コメントへの対応は滞留中も継続するので、レビューが進んで
  10本を切れば自動的に再開する。真のボトルネックは生産量ではなく**人間のレビュー帯域**であり、
  修正 PR が15〜16本溜まると人間が処理を諦めて PR の山ごと死ぬため、そこに合わせて流入を絞る
- **人間との修正のやり取りは GitHub 上で完結**: 実装前なら issue 本文の編集/コメント、実装後なら
  PR へのコメント（インライン単発コメント or PR 全体コメント。同一名義のため正式 Review = approve/
  request-changes は自分の PR に付けられないので普通のコメントで指示する。次回実行時に修正 or
  理由付き返信の1往復で自動対応。人間コメントが未解決の PR は auto-merge しない）、
  触らせたくないものは `factory-blocked` ラベル。
  **同一 GitHub 名義のため bot の返信は人間に通知されない** → 対応した PR は factory-build が
  Slack に「💬 返信したよ（PR URL）」を出す。今すぐ拾わせたいときは「ファクトリー回して」で手動起動可
- 同一 issue で2回失敗したら `factory-blocked` ラベルを付けて以後スキップ（週報で報告）
- 朝の回と夜の回で同じ issue を二重に取らないよう、着手時に `factory-wip` ラベルを付ける（冪等性）

### store-release（リリースの自動化 — もう1つの大穴）

現状: TestFlight 配信までは Xcode Cloud で自動だが、App Store 提出（メタデータ・スクショ・審査提出）
は完全に人手で、仕組み自体が存在しない。

- `building` で MVP issue が全部閉じたアプリを検出 → `review` 候補として処理開始
- PRD からストアメタデータ（名前・サブタイトル・説明・キーワード・プライバシー）を生成し、
  アプリリポジトリにコミット（レビュー可能な形で残す）
- スクリーンショット: シミュレータ撮影の自動化は初期スコープ外。`docs/store-assets/` に
  置かれたものを使い、無ければ Slack で1回だけ人間に依頼（これだけは人手）
- ASC API でバージョン作成→**カテゴリ（メイン/サブ）・著作権・メタデータ投入**→ビルド
  （タグ→TestFlight ワークフロー産）を紐付け。バージョンは semver ルール（機能追加ありでマイナー↑ /
  バグ修正のみでパッチ↑ / メジャーは人間指示か `major` ラベルのときだけ）で決める
- **提出は人間の承認ゲート付き（オプトイン）**。実現方法は GitHub issue（Slack の webhook は返信を
  読めないため）: リリースごとに `release-train` ラベルの issue を起票し、Slack には
  「内容を確認して承認（`approved` ラベル or 👍）したら提出します。止める/延期は `hold` or close」と通知。
  **承認が付くまで提出しない（默っていても提出されない）**。メタデータ生成・TestFlight 用ビルド確保など
  提出手前の準備は承認前でも進める。この issue がリリース列車の状態機械（チェックリスト・審査状況コメント）も兼ねる
- **初回提出は人間併走**: ASC API での提出が初めてのアプリは、承認済みでも提出直前でもう一度止めて
  Slack で案内（App Privacy・輸出コンプラ等の初回特有の穴を確認。2回目以降は承認だけで全自動）
- 審査中アプリのステータスを毎回追跡し、リジェクトされたら内容を要約して週報+即時通知
- 既リリースアプリは「前回リリース以降のマージ済み PR が5件以上 or 6週経過」で
  次バージョンのリリース列車を同じ流れで走らせる

### portfolio-review（計測と意思決定 — ②の欠落を埋める「脳」）

- 全アプリのメトリクスを取得: Firebase Analytics（ジョブ実行環境の firebase-bigquery スキル。作者環境の前提）、
  ASC API（DL数・クラッシュ）、RevenueCat API（収益）。取れない指標は「未計測」と明示し、
  **計測の穴は「計測実装 issue」として起票する**（黙って0にしない）
- **各アプリの PRD の KPI マイルストーン（M1〜M3）に対して達成状況を判定**し、
  ステージゲートを適用。portfolio.yml を更新して prd-vault にコミット
- 翌週の factory_schedule.yml（割当表）を生成
- **週報を Slack に1通**: 今週生まれた/進んだ/リリースされたもの、各アプリの KPI 達成状況と傾向、
  ステージ変更、収益の合計と目標（月5〜10万円）への進捗と外挿、
  **人間の要アクション一覧**（未マージ PRD PR / 未承認機能提案 / 提出承認待ちのリリース /
  factory-blocked / ASC・Xcode 未オンボーディング / スクショ依頼）

### growth-advisor（③の武器 — docs/growth-advisor-research.md の設計を実装）

- 対象: `growing` ステージのアプリ（factory-dispatch 経由・月次ローテで1本ずつ）
- 2段階入力: ❶コード探索（機能棚卸し）+ ❷製品コンテキスト（PRD のジョブ分析・KPI 実績）
- 多軸提案: 新機能 / 収益化・価格 / ASO・マーケ / リテンション施策 / PMF 仮説
- 各提案に「根拠（この製品のこのデータ・このコード）・前提・検証方法（KPI ツリーのどの指標が
  どう動けば成功か）」をセットで付ける（汎用SaaS機能の垂れ流しを禁止）
- 出力は feature-hunt と同じ Issue 形式（`feature-proposal` ラベル）に統一 →
  人間の👍/go → sub-issue 分割 → factory-build が拾う、という既存の川に流す

## 6. 人間がやること（週30分想定）

| タイミング | やること | やらないとどうなる |
|---|---|---|
| 月〜 | PRD PR をマージ/クローズ/コメント（主眼はジョブ分析の妥当性） | 新規アプリが生まれないだけ。既存は回り続ける |
| 随時 | 機能提案 Issue に 👍/go または close | 提案が溜まる（6件超で新規提案は自動休止） |
| キックオフ時 | ASC アプリレコード作成 + Xcode Cloud 初回オンボーディング（計5分） | そのアプリのリリースが進まない（3日ごとにリマインド） |
| 提出承認の通知が来たら | release-train issue の内容（メタデータ・スクショ・著作権・カテゴリ・バージョン）を確認し、よければ `approved` ラベル or 👍 | **提出されない**（承認しない限り待機） |
| 金 | 週報を読む。「要判断」があれば返信 | 保守的側（現状維持）に倒れる |
| 随時 | App Review リジェクト・スクショ依頼への対応 | そのアプリのリリースが止まる |

## 7. 収益目標の逆算

月5〜10万円を1年後に達成するためのポートフォリオ算数（仮置き。portfolio-review が実績で毎週更新）:

- 週1本 PRD 承認 → 年間 ~40本 kickoff → MVP完走率 7割 → **~25本リリース**
- M1/M2 通過率 2割 → **~5本が growing**
- growing のうち月1〜3万円到達が 2〜3本 + ロングテール（maintain の広告収益）で 5〜10万円

この算数自体が仮説なので、週報に「今の通過率で1年後いくらになるか」の外挿を毎週載せ、
ボトルネック（本数が足りない/通過率が低い/単価が低い）を特定して config.yml・gates の調整や
アイデア選定基準の変更を人間に提案する。

## 8. 段階的ロールアウト

1. **Phase 0**: app-idea-hunt の強化（JTBD 分析 + KPI 設計）と PRD テンプレート改修、
   app-kickoff に「計測実装 issue の必須化」を追加 — 上流から直す。プロンプト改修のみで安全
2. **Phase 1**: portfolio-review を導入。まず計測と週報だけ回す
   （portfolio.yml ブートストラップ → 数字が見える状態を作る。壊すものがない）
3. **Phase 2**: factory-dispatch を導入し、既存 audit 3本 + feature-hunt 一括実行を割当表方式に移行
4. **Phase 3**: factory-build を `building` アプリ限定・auto-merge なし（PR 作成まで）で開始 →
   1〜2週様子を見て auto-merge を解禁
5. **Phase 4**: store-release を導入（初回は Hirune / Nokorun 等の MVP 完了アプリで人間併走）
6. **Phase 5**: growth-advisor を導入（growing アプリが生まれてから）

## 9. スキルの集約と、リポジトリの外に残るもの

**アプリのライフサイクルに関わるスキルは全てこのリポジトリの `plugins/app-factory/` に集約した**
（app-idea-hunt / app-kickoff / xcode-cloud-setup / feature-hunt は `~/.claude/skills` から移動、
quality-release-cycle は dev-workflow-tools から移動）。強化はスキル本文に直接反映済みで、
以後の改修もここで直接行う:

- app-idea-hunt: JTBD 分析・KPI 数値必須化・モック/トンマナ（showcase）
- app-kickoff: 計測 issue 必須化 / **アーキテクチャ・テスト戦略文書の書き切り**
  （`docs/architecture.md` / `docs/test-strategy.md` — 無人実装はこれに従い、逸脱 issue は人間に回す）/
  **必須 issue セット**（オンボーディング=実装時に onboarding-advisor 起動・ペイウォール=RevenueCat・
  設定画面=問い合わせ/利用規約/プライバシーポリシーの3項目）/
  **外部サービス一気通貫**（Firebase・RevenueCat は自動作成、AdMob は API 非対応のため人力5分）/
  **LP 生成**（`lp/` に React プロジェクト + app-ads.txt + 規約ページ → アプリの Firebase プロジェクト内の
  `{slug}-lp` Hosting サイト（`https://{slug}-lp.web.app`）へ公開。設定画面とストア提出のプライバシー URL はここを指す）

⚠️ **このリポジトリはパブリック**。スキル・cron テンプレートにシークレット
（webhook 実 URL・API キー・トークン）を書かない。参照は環境変数名のみ、実値はジョブ実行環境の
`$APP_FACTORY_HOME/.env`。

リポジトリの外に残るもの:

- ジョブ実行環境 `$APP_FACTORY_HOME`（デフォルト: `~/dev/others/claude-cron`）:
  .env・logs・data・launchd 実体。`cron/install.sh` が配備し、移行手順は `cron/README.md`
  （ホームスキルの削除・run_prd_approval_check.sh の asc_cloud.py パス修正を含む）
- `prd-vault`（private）: PRD・portfolio.yml（portfolio-review が自動生成）・
  showcase サイト（app-idea-hunt が自動ブートストラップ。Vercel 接続済みで人間の作業は無し）

## 10. コストと安全性の考慮

- **トークン消費の平準化が設計の柱**: リポジトリ横断ジョブは廃止し、1日1リポジトリの割当表方式に。
  日次の claude 起動は最大5回（factory-build×3 + dispatch×1 + 既存 prd-approval-check）+
  空スロット日は bash 判定のみで claude 不起動
- factory-build が最も重い（1回で最大 issue 3件の実装 × 1日3回）。消費が問題になったら1回の上限か実行回数を下げる
- すべてのジョブはジョブ実行環境（`$APP_FACTORY_HOME`）の共通規約に従う: config.env・`.env` 読込 →
  `claude -p --permission-mode bypassPermissions` → ログ → 失敗時 Slack。
  **シークレットは .env のみ、リポジトリに置かない**
- auto-merge・ストア提出という「外に出る」操作には必ずガード（auto-merge は CI green 等の機械条件、
  ストア提出は人間の承認ゲート = `approved` オプトイン）
- 全ジョブ冪等: 二重実行しても Issue・PR・提出が重複しない（🤖 マーカー・`factory-wip` ラベル・
  ASC 状態照会で判定）
