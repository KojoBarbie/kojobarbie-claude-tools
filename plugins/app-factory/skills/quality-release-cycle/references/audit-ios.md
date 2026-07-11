# 監査観点: iOS ネイティブ（Swift / SwiftUI）パフォーマンス

`swiftui-pro` / `app-design-craft` スキルが利用可能なら、UI レビュー次元ではそれらの観点も併用する。

## 起動パス

1. `App` / `AppDelegate` の同期初期化（起動前にネットワークを待つ処理、重い DI コンテナ構築）
2. 初回フレームまでに main thread をブロックする処理（同期ディスク I/O、大きな UserDefaults/JSON 読み込み）

## SwiftUI

1. **過剰な再評価**: 巨大な body、`@ObservedObject`/`@EnvironmentObject` の粒度が粗く無関係な変更で再描画される構造。
   Observation（`@Observable`）移行の余地
2. `onAppear` でのデータ取得が画面再表示のたびに再実行される（キャッシュ・タスク管理の欠如）
3. `List`/`LazyVStack` の使い分け、ForEach の id 安定性
4. `task` modifier のキャンセル対応（画面離脱時に走り続ける async 処理）

## メモリ・リーク

1. クロージャの `[weak self]` 漏れ（特に購読・タイマー・通知センター）
2. Combine の `AnyCancellable` 保持と解放、NotificationCenter の removeObserver
3. 画像の原寸デコード（`UIImage(named:)` で表示サイズに対し過大な画像、`preparingThumbnail` 等の活用）

## 並行処理

1. `@MainActor` の適切な付与（UI 更新のスレッド違反）と、逆に main actor での重い処理
2. actor 分離への過剰な hop、Task の多重起動（連打対策）

## データアクセス

1. Core Data / SwiftData のフェッチが main thread で走っていないか、FetchRequest の述語・limit
2. N+1（リレーション先の逐次フェッチ）、ページネーション
3. URLSession のキャッシュポリシーとリトライ

## ライフサイクル

1. `scenePhase` でのバックグラウンド対応（音声・タイマー・位置情報の停止）
2. バックグラウンドタスクの期限管理

## 依存

1. SPM 依存の更新状況（メジャー遅れ・アーカイブ済みリポジトリ）
2. 最低サポート iOS バージョンと使用 API の整合
