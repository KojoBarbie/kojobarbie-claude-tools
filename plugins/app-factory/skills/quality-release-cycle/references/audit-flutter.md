# 監査観点: Flutter パフォーマンス

`.fvmrc` / `fvm_config.json` があるリポジトリではコマンドはすべて `fvm flutter` 経由で実行する。

## 起動パス

1. `main.dart` で初回フレーム前にブロッキング await している処理（Firebase init 以外の直列 await は要精査）
2. 重い初期化（広告 SDK・音声・通知・ウォームアップ）が `addPostFrameCallback` 等に退避されているか
3. スプラッシュ→初画面の遷移で全画面スピナーに落ちる時間

## 状態管理（Riverpod / Bloc / Provider — 使用ライブラリを検出して該当観点を使う）

1. **autoDispose 漏れ**: 画面を離れてもリスナー（特に Firestore/DB の snapshots）が解放されないプロバイダー。
   `StreamProvider.family` の非 autoDispose は頻出パターン
2. watch の粒度: 画面トップレベルでの watch により、部分更新（スライダー操作等）で画面全体が再ビルドしていないか。
   `select` / Consumer 分割の余地
3. ストリーミング表示（チャット等）でトークン毎に全体再ビルドしていないか

## データアクセス

1. N+1 クエリ、`limit` なしの全件取得、ページネーションのカーソル管理（毎回1ページ目を取り直す破綻パターン）
2. cache-first（ローカルキャッシュ先行表示 → バックグラウンド更新）の活用
3. 読み取りのたびに走る書き込み（マイグレーション判定等）
4. SSE / WebSocket の購読が保持・キャンセルされているか（リーク）

## 画像・アセット

1. アセットの実サイズを実測する（`du -h` と `sips -g pixelWidth -g pixelHeight`（macOS）等）。
   画面表示サイズに対して過大な解像度の PNG は指摘
2. `Image.asset` の `cacheWidth/cacheHeight`、precache とキャッシュキーの一致
3. **Flame 等ゲームエンジン併用時**: `loadSprite` / `images.load` は縮小なしの原寸デコードなので、
   Flutter 側だけ最適化されて Flame 側が漏れるパターンを必ず確認（GPU 常駐 = 幅×高さ×4 bytes で概算を示す）
4. BGM・動画などの大容量アセットのバンドルサイズ影響

## 描画

1. `ListView` vs `ListView.builder`、リストアイテムの key、const コンストラクタ
2. 毎フレームの `Paint` 生成、`MaskFilter.blur` / `ImageFilter` などの高コスト描画がアニメーションループ内にないか
3. ゲームループ内のオブジェクト生成（GC churn）

## ライフサイクル・音声

1. `didChangeAppLifecycleState` でバックグラウンド時に音声・タイマー・購読を停止しているか
2. AudioSession の共存設定（他アプリの音を止めていないか）

## 依存

1. `flutter pub outdated` 相当の確認（メジャー遅れ・保守停止パッケージ）
2. intl と flutter_localizations の整合
