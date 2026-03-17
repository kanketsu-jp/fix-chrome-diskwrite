# fix-chrome-diskwrite

Chrome の過剰なディスク書き込みにより macOS の書き込み制限を超過してクラッシュする問題を修正するツール。

## ルールファイル

- `.claude/rules/chrome-disk-writes.md` — Chrome disk writes の技術的知見（書き込み先、制限の仕組み、安全な削除対象）
- `.claude/rules/development.md` — 開発ルール（プロジェクト構成、更新時の注意、バージョニング）
- `.claude/rules/known-issues.md` — 既知の問題と対策状況

## ユーザーの PC にインストール済みのもの

変更・削除する場合は影響を確認すること。

### LaunchAgent（`--schedule` で登録）
- **plist**: `~/Library/LaunchAgents/com.fix-chrome-diskwrite.cleanup.plist` — 2 分ごとに cleanup.sh を実行
- **スクリプト**: `~/.local/bin/fix-chrome-diskwrite-cleanup.sh` — cleanup.sh のインストール先
- **ログ**: `~/Library/Logs/fix-chrome-diskwrite-cleanup.log`
- Chrome 未起動時: 100MB 超のキャッシュを削除 + クラッシュ後の壊れたキャッシュを自動修復
- Chrome 起動中: `exit_type=Crashed` 検出時は exit_type リセットのみ（キャッシュは触らない — 起動中に削除すると Cannot stat エラーで逆効果）

### Chrome Enterprise Policy（15 件）

`defaults read com.google.Chrome` で確認。`--undo --full` で全削除。

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
| HighEfficiencyModeEnabled | true | メモリセーバー有効 |
| IntensiveWakeUpThrottlingEnabled | true | バックグラウンドタブ制限 |
