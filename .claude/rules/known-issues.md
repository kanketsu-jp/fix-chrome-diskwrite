# 既知の問題と対策状況

## 対策済み

### 拡張機能の過多によるクラッシュ
- 多数の拡張機能（Adobe Acrobat の content script 注入、不明な拡張機能等）が新規タブ作成時にクラッシュを引き起こしていた
- 不要な拡張機能を削除して解決済み
- **1Password（Stable/Nightly 両方）は無罪**。GWS 組織が Nightly をインストールしており、これは想定内

### キャッシュ破損による連鎖クラッシュ・もっさり
- クラッシュ後にキャッシュが壊れた状態で再起動すると、大量の `Cannot stat` エラーでもっさり→再クラッシュする
- cleanup.sh（2 分間隔 LaunchAgent）が Chrome 未起動時に自動修復
- **重要**: Chrome 起動中にキャッシュを削除すると逆効果（メモリ上のインデックスと不整合になり `Cannot stat` が増える）。起動中は `exit_type` リセットのみ

### Chrome 自体の disk writes 超過
- Gemini Nano、コンポーネント、キャッシュ等の大量書き込み
- Enterprise Policy 15 件 + 定期クリーンアップで対策済み

### Google Drive の大量書き込み
- ストリーミングモードでもメタデータ同期で 8.6GB+ 書き込む
- `.DS_Store` 抑制で軽減。根本解決は Google Drive 側の問題

## 未解決（Chrome 側の修正待ち）

### macOS ARM GPU パイプラインクラッシュ
- **Chrome 146** の macOS ARM (M4 Pro 等) で発生
- タブキャプチャ系操作時に GPU プロセスがクラッシュ
- エラー: `GPU state invalid after WaitForGetOffsetInRange`、`render pipeline cache limit overflow`
- **発生条件**: Meet のタブ共有、Claude Computer Use（WebRTC タブキャプチャ）
- **回避策**: Meet は「画面全体」を共有（タブキャプチャを避ける）
- Chromium バグ #355266358 関連。fix-chrome-diskwrite では対処不可

## 重要な知見

- **macOS の disk writes `.diag` レポートはクラッシュ原因ではない**: `.diag` は診断レポートに過ぎず、macOS は Chrome を kill していない（全て「Action taken: none」）。disk writes を減らしてもクラッシュ防止には直接関係ないが、SSD 寿命には有効
- **調査ログ**: `.temp/investigation-log-2026-03-16.md` に 2026-03-13〜18 の詳細な調査経緯を記録
