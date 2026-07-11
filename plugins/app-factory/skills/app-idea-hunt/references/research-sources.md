# リサーチ情報源と手順

候補集めは「切り口の多様性」が命。同じソースばかり見ると毎週同じ顔ぶれになる。以下から**最低3つの異なる切り口**を使い、10〜20候補を集める。

## 1. App Store 各国トップチャート（iTunes RSS API — 確実・無料）

```bash
# 例: 米国 無料トップ50
curl -s "https://rss.marketingtools.apple.com/api/v2/us/apps/top-free/50/apps.json" | python3 -m json.tool | head -80
# 有料トップ（支払い意欲の実証データとして特に重要）
curl -s "https://rss.marketingtools.apple.com/api/v2/us/apps/top-paid/50/apps.json"
```

- 国コード: `us`, `gb`, `de`, `kr`, `au` など。日本にまだ来ていないものを探すので日本以外を見る
- **有料チャートは宝の山**: そこにあるアプリは「人が金を払う課題」の一覧
- 旧APIならジャンル絞り込みが可能（動かなければスキップ）:
  `https://itunes.apple.com/us/rss/toppaidapplications/limit=50/genre=6013/json`
  注目カテゴリに対応するジャンルコード: 6017=Education, 6013=Health & Fitness, 6007=Productivity, 6015=Finance, 6012=Lifestyle（カップル系はここに多い）。その他 6002=Utilities

## 2. アプリ詳細の深掘り（iTunes Search/Lookup API)

候補が見つかったら詳細を取る:

```bash
# 海外での実績確認（評価件数=規模の代理指標、価格、更新頻度）
bash {skill_dir}/scripts/jp_appstore_search.sh "sleep tracker" 10 us
# 特定アプリのlookup
curl -s "https://itunes.apple.com/lookup?id={appId}&country=us"
```

## 3. Product Hunt（新しい動きの検知）

```
WebFetch: https://www.producthunt.com/leaderboard/daily （または /weekly）
```

iOSアプリ・モバイル系で票を集めているものを拾う。まだApp Storeチャートに載る前の萌芽が見つかる。

## 4. Web検索（トレンド文脈の把握）

WebSearchで以下のようなクエリを季節・時期を変えて数本:

- `best new iOS apps 2026 indie`
- `viral health app TikTok` / `wellness app trending`
- `App Store 有料ランキング 海外 話題`
- `indie iOS app revenue success` （個人開発で売れた実例＝規模感の合う参考例）

## 5. コミュニティの生の声（需要の一次情報）

- Reddit: `r/iosapps`, `r/QuantifiedSelf`, `r/getdisciplined`, `r/sleep` などを WebSearch (`site:reddit.com ○○ app`) で。「こういうアプリないの?」という投稿は未充足需要そのもの
- 日本側: `○○ アプリ おすすめ` で上位に出る記事の内容が古い/貧弱なら、そのジャンルは日本語圏の情報空白=チャンス

## 6. Apptopia トレンド（ジョブ実行環境内で実行時のみ）

ジョブ実行環境（`$APP_FACTORY_HOME`）で実行されている場合、playwright-cli で:

```
https://apptopia.com/top-charts/trending-apps
https://apptopia.com/top-charts/trending-apps/itunes-connect/health-fitness/united-states
```

（詳細手順は `$APP_FACTORY_HOME` の `overseas-app-trends` スキル参照。作者環境の前提なので、無い環境ならスキップしてよい）

## 収集時の心得

- **数字を必ず添える**: 評価件数・順位・価格。後のスコアリングが主観にならないように
- **「なぜ今伸びているか」を1行で言えないアプリは候補にしない**（一過性バイラルとの区別）
- `config.yml` の注目カテゴリ（教育・健康管理・仕事効率化・金融・恋愛カップル）の候補は多めに拾ってよい。ただし各カテゴリの規制枠に注意: 健康系はApple審査で医療機器扱いにならない範囲（記録・可視化・習慣化支援まで）、金融系は投資助言・与信に踏み込まない範囲（家計簿・貯金・サブスク管理など）、恋愛系はマッチングではなくカップル向けクローズドアプリに限る
