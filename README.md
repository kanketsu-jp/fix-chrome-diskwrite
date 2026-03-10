# fix-chrome-diskwrite

Chrome が Gemini Nano の AI モデル（4GB）を無断でダウンロードし、macOS のディスク書き込み制限を超過してクラッシュする問題を修正する。

## やること

1. Chrome の Enterprise Policy `GenAILocalFoundationalModelSettings=1` を設定（モデルの自動ダウンロードを禁止）
2. 既存のモデルデータ（`OptGuideOnDeviceModel/`）を削除（約 4GB 解放）

## 使い方

Chrome を終了してから実行。

### npx（推奨）

```bash
npx fix-chrome-diskwrite
```

### curl

```bash
curl -fsSL https://raw.githubusercontent.com/kanketsu-jp/fix-chrome-diskwrite/main/bin/fix.sh | bash
```

### オプション: optimization_guide_model_store の無効化

Gemini Nano 以外にも Chrome は `optimization_guide_model_store/` に最適化用モデルを自動ダウンロードする。これもディスク書き込み量を押し上げるため、`--opt-guide` オプションで既存データを削除できる。

```bash
npx fix-chrome-diskwrite --opt-guide
```

`--schedule` を付けると macOS LaunchAgent を登録し、1時間ごとに自動削除する。

```bash
npx fix-chrome-diskwrite --opt-guide --schedule
```

> **注意**: `optimization_guide_model_store` を無効化する公式 Enterprise Policy は存在しないため、Chrome 再起動後に再生成される。`--schedule` での自動削除を推奨。

### 元に戻す

```bash
npx fix-chrome-diskwrite --undo
# LaunchAgent も削除する場合
npx fix-chrome-diskwrite --undo --opt-guide --schedule
```

## 確認方法

Chrome を再起動して `chrome://policy` を開く。`GenAILocalFoundationalModelSettings` が `1` になっていれば OK。

## 参考

- [Chrome が突然落ちる原因は Gemini Nano だった — 調査と対処法](https://zenn.dev/kazuma_horiike/articles/0f7ba42b65951e)
- [GenAILocalFoundationalModelSettings - Chrome Enterprise Policy](https://chromeenterprise.google/policies/#GenAILocalFoundationalModelSettings)
- [How to disable the browser from downloading model files - Chromium Dev Group](https://groups.google.com/a/chromium.org/g/chrome-ai-dev-preview-discuss/c/t6fqOnTzA_g)

## License

MIT
