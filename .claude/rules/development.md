# 開発ルール

## プロジェクト構成

- `bin/fix.sh` — メインスクリプト（Enterprise Policy 設定、データ削除、クラッシュループ修復）
- `bin/cleanup.sh` — 定期クリーンアップスクリプト（LaunchAgent から呼び出される、クラッシュ後自動修復機能付き）
- `cli.js` — npx エントリポイント（fix.sh を呼び出すだけ）
- `.temp/blog.md` — Zenn 記事の原稿
- README.md — npm パッケージの README

## ユーザー PC 上のファイル（リポジトリ外）

- `~/.local/bin/fix-chrome-diskwrite-cleanup.sh` — cleanup.sh のインストール先
- `~/Library/LaunchAgents/com.fix-chrome-diskwrite.cleanup.plist` — LaunchAgent（2 分間隔）
- `~/Library/Logs/fix-chrome-diskwrite-cleanup.log` — クリーンアップログ

## 記事の執筆ルール

- Zenn 記事は `~/Library/CloudStorage/GoogleDrive-kazuma-horiike@kanketsu.jp/My Drive/Knowledge/MAIN_技術記事執筆ルール_堀池一真スタイル.md` に従う
- 見出しは `##` から開始（Zenn のルール）
- `:::message` / `:::message alert` は行頭から記述

## スクリプト更新時の注意

- fix.sh を変更したら、README.md と .temp/blog.md も同期すること
- cleanup.sh を変更したら、インストール済みの `~/.local/bin/fix-chrome-diskwrite-cleanup.sh` も更新すること
- LaunchAgent のラベル名を変更した場合、旧ラベルのマイグレーション処理を入れること
- 全プロファイルを対象とすること（Default だけでなく Profile 2, 3, ... も）
- `~/Library/Caches/Google/Chrome/` を忘れないこと（Application Support とは別の場所）

## バージョニング

- コミットメッセージに `vX.Y.Z:` プレフィックスを付ける
- 破壊的変更（オプション追加、LaunchAgent 変更等）はメジャーバージョンを上げる
