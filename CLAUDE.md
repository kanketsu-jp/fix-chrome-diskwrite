# fix-chrome-diskwrite

Chrome の過剰なディスク書き込みにより macOS の書き込み制限を超過してクラッシュする問題を修正するツール。

## 前回の調査ログ

直近の調査内容は `.temp/investigation-log-2026-03-16.md` に記録されている。新しい会話を始める前にこのログを確認すること。

## ルール

- `.claude/rules/chrome-disk-writes.md` — Chrome disk writes クラッシュに関する技術的知見（書き込み先、制限の仕組み、安全な削除対象など）
- `.claude/rules/development.md` — 開発ルール（プロジェクト構成、記事執筆ルール、更新時の注意事項）

## ユーザーの PC に常駐しているもの

以下はこのツールでインストールされたもの。変更・削除する場合は影響を確認すること。

### `--schedule` で登録
- **LaunchAgent**: `com.fix-chrome-diskwrite.cleanup` — 1 時間ごとに cleanup.sh を実行
- **スクリプト**: `~/.local/bin/fix-chrome-diskwrite-cleanup.sh` — cleanup.sh のインストール先
- **ログ**: `~/Library/Logs/fix-chrome-diskwrite-cleanup.log`
- Chrome 未起動時: 通常のキャッシュクリーンアップ（100MB超のキャッシュを削除）
- Chrome 起動中: クラッシュ検知時のみキャッシュ修復（`exit_type=Crashed` を検出し壊れたキャッシュを削除）

## 適用済みの Chrome Enterprise Policy（15 件）

`defaults read com.google.Chrome` で確認可能。`--undo --full` で全て削除される。

| ポリシー | 値 | 目的 |
|---|---|---|
| GenAILocalFoundationalModelSettings | 1 | Gemini Nano DL 禁止 |
| ComponentUpdatesEnabled | false | コンポーネント自動更新停止 |
| ScreenAIEnabled | false | ScreenAI 無効化 |
| TextToSpeechEnabled | false | TTS 無効化 |
| BackgroundModeEnabled | false | バックグラウンド書き込み防止 |
| PasswordManagerEnabled | false | 内蔵パスワードマネージャー無効化 |
| AutofillAddressEnabled | false | 住所自動入力無効化 |
| AutofillCreditCardEnabled | false | クレジットカード自動入力無効化 |
| DiskCacheSize | 50MB | HTTP キャッシュ上限 |
| MediaCacheSize | 32MB | メディアキャッシュ上限 |
| ForceGpuMemAvailableMb | 4096 | GPU メモリ上限拡大 |
| RendererProcessLimit | 20 | Renderer プロセス数制限 |
| TotalMemoryLimitMb | 16384 | Chrome 全体メモリ 16GB 上限 |
| HighEfficiencyModeEnabled | true | メモリセーバー（タブ自動破棄）有効 |
| IntensiveWakeUpThrottlingEnabled | true | バックグラウンドタブの JS 実行制限 |

## 既知の問題

- **拡張機能の過多がクラッシュを引き起こす**: 多数の拡張機能（特に Adobe Acrobat の content script 注入、不明な拡張機能）が新規タブ作成時にクラッシュを引き起こす。不要な拡張機能を削除することで解決。1Password（Stable/Nightly 両方）は無罪。詳細は `.temp/investigation-log-2026-03-16.md` を参照。
- **macOS の disk writes .diag レポートはクラッシュ原因ではない**: `.diag` は診断レポートに過ぎず、macOS は Chrome を kill していない（全て「Action taken: none」）。disk writes を減らしてもクラッシュ防止には直接関係ない。SSD 寿命には有効。
- **macOS ARM で GPU パイプラインクラッシュ**: Chrome 146 の macOS ARM (M4 Pro 等) で、タブキャプチャ系操作時に GPU プロセスがクラッシュする（`GPU state invalid after WaitForGetOffsetInRange`、`render pipeline cache limit overflow`）。Meet のタブ共有、Claude Computer Use（WebRTC タブキャプチャ）で発生。Chromium バグ #355266358 関連。回避策: Meet は「画面全体」を共有。fix-chrome-diskwrite では対処不可。Chrome 側の修正待ち。
- **キャッシュ破損による連鎖クラッシュ**: クラッシュ後にキャッシュが壊れた状態で再起動すると、大量の `Cannot stat` エラーが発生し再クラッシュする。cleanup.sh のクラッシュ検知機能（`exit_type=Crashed` 検出）で自動修復される。
