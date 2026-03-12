# fix-chrome-diskwrite

Chrome の過剰なディスク書き込みにより macOS の書き込み制限を超過してクラッシュする問題を修正する。

## 原因

Chrome は以下のデータを自動ダウンロード・書き込みし、macOS の disk writes 制限（約 2GB/24h）を超過すると OS に強制終了される。

- **Gemini Nano AI モデル**（`OptGuideOnDeviceModel/` 約 4GB）
- **optimization_guide_model_store**（最適化用モデル、再起動のたびに再生成）
- **screen_ai**（OCR/アクセシビリティ AI、約 123MB）
- **WasmTtsEngine**（テキスト読み上げ、約 22MB）
- **component_crx_cache**（コンポーネントキャッシュ、約 157MB）
- その他コンポーネントの自動更新

## やること

1. Enterprise Policy `GenAILocalFoundationalModelSettings=1` を設定（Gemini Nano の自動ダウンロードを禁止）
2. 既存のモデルデータ（`OptGuideOnDeviceModel/`）を削除

### `--full` オプション（推奨）

上記に加えて以下も適用:

3. コンポーネント自動更新を停止（`ComponentUpdatesEnabled=false`）
4. ScreenAI・TTS・バックグラウンドモードを無効化
5. Chrome 内蔵パスワードマネージャー・自動入力を無効化（macOS の `SafariPlatformSupport.Helper` クラッシュ防止）
6. 追加コンポーネントデータの削除（screen_ai, WasmTtsEngine, component_crx_cache 等）

> **注意**: Chrome 内蔵パスワードマネージャーの無効化は 1Password 等の拡張機能に影響しません。

## 使い方

Chrome を終了してから実行。

### npx（推奨）

```bash
# 基本（Gemini Nano のみ）
npx fix-chrome-diskwrite

# フル対策（推奨）
npx fix-chrome-diskwrite --full

# フル対策 + optimization_guide_model_store 自動削除
npx fix-chrome-diskwrite --full --opt-guide --schedule
```

### curl

```bash
# 基本
curl -fsSL https://raw.githubusercontent.com/kanketsu-jp/fix-chrome-diskwrite/main/bin/fix.sh | bash

# フル対策
curl -fsSL https://raw.githubusercontent.com/kanketsu-jp/fix-chrome-diskwrite/main/bin/fix.sh | bash -s -- --full

# フル対策 + optimization_guide_model_store 自動削除
curl -fsSL https://raw.githubusercontent.com/kanketsu-jp/fix-chrome-diskwrite/main/bin/fix.sh | bash -s -- --full --opt-guide --schedule
```

### オプション一覧

| オプション | 説明 |
|---|---|
| (なし) | Gemini Nano の DL 禁止 + 既存モデル削除 |
| `--full` | コンポーネント更新停止・ScreenAI/TTS 無効化・内蔵パスワードマネージャー無効化・追加データ削除 |
| `--opt-guide` | `optimization_guide_model_store` も削除 |
| `--schedule` | LaunchAgent で 1 時間ごとに `optimization_guide_model_store` を自動削除（`--opt-guide` と併用） |
| `--undo` | すべての設定を元に戻す（`--full`, `--opt-guide --schedule` と併用可） |

### 元に戻す

```bash
# 基本設定のみ元に戻す
npx fix-chrome-diskwrite --undo

# すべて元に戻す
npx fix-chrome-diskwrite --undo --full --opt-guide --schedule
```

## 確認方法

Chrome を再起動して `chrome://policy` を開く。設定したポリシーが反映されていれば OK。

## 参考

- [Chrome が突然落ちる原因は Gemini Nano だった — 調査と対処法](https://zenn.dev/kazuma_horiike/articles/0f7ba42b65951e)
- [GenAILocalFoundationalModelSettings - Chrome Enterprise Policy](https://chromeenterprise.google/policies/#GenAILocalFoundationalModelSettings)
- [How to disable the browser from downloading model files - Chromium Dev Group](https://groups.google.com/a/chromium.org/g/chrome-ai-dev-preview-discuss/c/t6fqOnTzA_g)

## おまけ: macOS の .DS_Store をリモート/USB ドライブに作らせない

Google Workspace（Google Drive）や NAS などのネットワークマウント、USB ドライブに `.DS_Store` が生成されるのを防ぐワンライナー。

```bash
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true && defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true
```

設定後、ログアウト→ログイン（または再起動）で反映される。

確認:

```bash
defaults read com.apple.desktopservices
```

元に戻す:

```bash
defaults delete com.apple.desktopservices DSDontWriteNetworkStores && defaults delete com.apple.desktopservices DSDontWriteUSBStores
```

> **注意**: ローカルディスクの `.DS_Store` は Finder の表示設定に使われるため、無効化する公式手段はない。

## License

MIT
