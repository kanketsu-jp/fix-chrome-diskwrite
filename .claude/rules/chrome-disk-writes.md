# Chrome disk writes クラッシュの知見

## macOS の disk writes 制限

- macOS は各プロセスに 24 時間スライディングウィンドウで disk writes 上限を課す（約 2GB / 24h）
- この制限はプロセス再起動ではリセットされない。macOS の再起動でリセットされる
- Chrome はマルチプロセスアーキテクチャのため、Main と Helper それぞれに制限がかかる
- クラッシュレポートは `/Library/Logs/DiagnosticReports/` に `.diag` ファイルとして出力される（遅延あり）

## Chrome の書き込み先（すべて把握すること）

### Application Support 内
- `~/Library/Application Support/Google/Chrome/`
  - `OptGuideOnDeviceModel/` — Gemini Nano 本体（~4GB）★最大の犯人
  - `optimization_guide_model_store/` — TFLite モデル群（再生成される）
  - `GraphiteDawnCache/`, `BrowserMetrics/`, `component_crx_cache/` — 共有キャッシュ
  - `screen_ai/`, `WasmTtsEngine/`, `OnDeviceHeadSuggestModel/` — AI コンポーネント
  - 各プロファイル内: `Service Worker/CacheStorage/`, `DawnWebGPUCache/`, `DIPS-wal`
  - 拡張機能の LevelDB ログ（`Local Extension Settings/*/000xxx.log`）

### Caches 内（見落としやすい）
- `~/Library/Caches/Google/Chrome/`
  - `Default/Cache/`, `Profile 2/Cache/` — HTTP キャッシュ（プロファイルごとに 1-2GB）
  - `Default/Code Cache/`, `Profile 2/Code Cache/` — JS コンパイルキャッシュ
  - ★ Application Support とは別の場所なので忘れがち

## 複数プロファイルの影響

- プロファイル数に比例して書き込み量が増える
- 3 プロファイルなら書き込み量は約 3 倍
- 全プロファイルを対象にクリーンアップする必要がある
- プロファイル検出: `Default`, `Profile 2`, `Profile 3`, ... を自動検出する

## クラッシュループ

- Chrome クラッシュ時に `Preferences` の `exit_type` が `Crashed` のまま残る
- 次回起動時にセッション復元 → 大量タブ読み込み → 再クラッシュのループ
- 修復: `exit_type` を `Normal` にリセット + セッションファイル削除
- 全プロファイルに対して行う必要がある

## 拡張機能の書き込み

- Adobe Acrobat (`efaidnbmnnnibpcajpcglclefindmkaj`) — 起動直後に 12MB 書き込む
- Wappalyzer (`gppongmhjkpfnbhagpmjfkannfbllamg`) — 全ページでデータ収集、4MB+
- 1Password (`aeblfdkhhhdcdjpifhhbdiojplfjncoa`) — IndexedDB に 2MB+ / プロファイル
- 対策: 「拡張機能をクリックしたとき」モードに変更（スクリプトでは制御不可、Chrome UI で設定）

## 削除しても安全なもの / 安全でないもの

### 安全（キャッシュ・再生成される）
- Service Worker CacheStorage, HTTP Cache, Code Cache
- GraphiteDawnCache, DawnWebGPUCache, BrowserMetrics
- DIPS-wal, 拡張機能の .log ファイル（LevelDB WAL）
- optimization_guide_model_store, screen_ai, WasmTtsEngine

### 削除してはいけない（ユーザーデータ）
- History, Bookmarks, Cookies, Passwords
- Extensions/ (拡張機能本体)
- Preferences, Local State
- Login Data
