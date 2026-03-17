# Chrome クラッシュ調査ログ (2026-03-13 〜 2026-03-18)

## 発端

2026-03-13: Chrome が突然クラッシュし、再起動しても新しいタブを開こうとした瞬間にまたクラッシュする。
PC スペック: MacBook Pro M4 Pro / 48GB RAM / GPU 20コア / macOS 26.3.1

## 調査の流れ

### 1. 初期調査 (3/13)

- Activity Monitor のスクリーンショットを確認 → メモリは問題なし（48GB中 34.8GB 使用、Swap 0）
- `/Library/Logs/DiagnosticReports/` を確認 → Chrome の `.diag` ファイルが複数見つかる
- Preferences の `exit_type` が `Crashed` → **クラッシュループ**を発見
- fix-chrome-diskwrite のポリシーは正しく適用済みだった

### 2. クラッシュループの発見と修復 (3/13)

- `exit_type: Crashed` + `exited_cleanly: None` → セッション復元のループ
- Preferences を修正 + セッションファイルをバックアップ・削除
- **→ fix.sh に `--fix-crash-loop` オプションを追加**
- Default だけでなく Profile 2, Profile 3 も対象にする必要があった
- **→ 全プロファイル自動検出に対応**

### 3. ポリシー適用後もクラッシュが継続 (3/13)

クラッシュレポートを確認:
```
Event: disk writes
Writes: 2147.74 MB over 1596 seconds
```
- ポリシーで Gemini Nano は止まっているが、**他のコンポーネントの書き込みだけで 2.1GB を超過**
- 3 プロファイルの存在が書き込み量を 3 倍に
- 拡張機能の書き込みが大きい:
  - Adobe Acrobat: 起動直後に 12MB
  - Wappalyzer: 4MB+
  - 1Password: 2MB+/プロファイル

### 4. Service Worker キャッシュの大量書き込み (3/13)

- 3 プロファイル合計で Service Worker CacheStorage が **1.2GB**
- DawnWebGPUCache、BrowserMetrics も起動時に再生成
- **→ cleanup.sh を新規作成（LaunchAgent から 1 時間ごと実行）**
- **→ LaunchAgent を単発 rm から cleanup.sh スクリプトに置き換え**

### 5. macOS 再起動後もクラッシュ (3/15)

- disk writes カウンタはリセットされたはず
- 調査で `~/Library/Caches/Google/Chrome/` に **4.2GB** のキャッシュを発見
- Application Support とは**別の場所**にある HTTP キャッシュと Code Cache
- **→ cleanup.sh と fix.sh --full にこのパスを追加**

### 6. キャッシュ削除後もクラッシュ (3/15)

- クラッシュレポート: Helper Renderer が 11 時間で **8.6GB** 書き込み
- Footprint: 622MB → 837MB（max 1051MB）
- **→ DiskCacheSize=50MB, MediaCacheSize=32MB のポリシーを追加**

### 7. disk writes 以外のクラッシュを発見 (3/16)

- モニタリングツール（monitor.py, proc_monitor.py）を作成して調査
- クラッシュ時の制限消費率は **30.4%（653MB / 2147MB）** — disk writes ではない
- GPU プロセス (Main Helper) が **2 分で 993MB** まで膨張
- **→ ForceGpuMemAvailableMb=4096, RendererProcessLimit=20, TotalMemoryLimitMb=16384 を追加**

### 8. Claude Computer Use が原因と判明 (3/16)

- GPU 安定化設定後もクラッシュ → disk writes は 26.6% で制限未到達
- macOS のクラッシュレポートも出ていない（disk writes/メモリ/シグナル いずれでもない）
- クラッシュ時の状況: **Claude のブラウザ操作（Computer Use）中に新しいタブを開くとクラッシュ**
- WEB 検索で同様の報告を確認:
  - Chromium バグ #355266358（macOS ARM での sidePanel API クラッシュ）が根本原因
  - GitHub Issues: #27530, #16201 など多数
  - **これは fix-chrome-diskwrite の対象外**

### 9. クリーンアップ (3/16)

一時的な調査用ファイルを削除:
- `.temp/for-my-pc/` ディレクトリ一式（モニター、DB、ログ）
- `~/.local/bin/chrome-stable-launch.sh`
- 一時的な Chrome ポリシー 5 件（TabDiscardingExceptions, SitePerProcess 等）
- デバッグ用 Chrome flags 2 件（smooth-scrolling, enable-gpu-rasterization）
- Sessions_backup_* ディレクトリ 4 件

## 追加調査 (3/16 14:00)

### 原因 3: Google Drive の disk writes が Chrome を巻き添えにしている

Activity Monitor で Google Drive が **11.88GB** 書き込んでいることを発見。Chrome は 504.7MB のみ。
クラッシュレポートでも Google Drive が `disk writes` 制限超過（8.6GB / 19 時間）。

- Google Drive の設定は既に **ストリーミングモード**（ミラーリングではない）
- 2 アカウント登録、共有ドライブ 15 個以上
- ストリーミングでもメタデータ同期だけで大量書き込みが発生
- macOS の disk writes 制限はプロセスごとだが、同じユーザーの累積書き込みがシステム全体の書き込み性能に影響し、Chrome の書き込みが遅延→蓄積で制限超過する可能性がある

### 結論の更新

Chrome クラッシュの原因は **4 つ**:
1. **Chrome 自体の disk writes** — Gemini Nano、コンポーネント、キャッシュ（対策済み）
2. **Claude Computer Use** — Chromium sidePanel API バグ（対象外）
3. **Google Drive の大量書き込み** — ストリーミングモードでもメタデータ同期で 8.6GB+（新発見）
4. **拡張機能の競合または不具合** — 下記参照（対策済み）

### 10. 拡張機能が原因と特定 (3/17)

全ポリシー削除してもクラッシュ → ポリシーを全て戻してもクラッシュしない → **ポリシーは原因ではない**。
前回の調査中に削除した拡張機能がクラッシュ原因だった。

#### 切り分け結果
- **ポリシー15件**: 全て戻してもクラッシュしない → 無罪
- **Wappalyzer**: 再インストールしてもクラッシュしない → 無罪
- **削除してクラッシュが止まった拡張機能**:
  - Adobe Acrobat (`efaidnbmnnnibpcajpcglclefindmkaj`)
  - ChatGPT search (`ejcfepkfckglbgocfkanmcdngdijcgld`)
  - Claude in Chrome (`fcoeoabgfenejglbffodgkkbkcdhcgfn`)
  - GoFullPage (`fdpohaocaechififmbbbbbknoalclacl`)
  - React Developer Tools (`fmkadmapgofadopljbjfkapdkoienihi`)
  - 1Password Nightly (`gejiddohjgogedgjnonbofjigllpkmbf`) ← 通常版と競合・corrupted 状態だった
  - Google Docs Offline (`ghbmnnjooekpmoecnnnilnnbdlolhkhi`)
  - Application Launcher for Drive (`lmjegmlicamnimmfhcmpkclmigmmcbeh`)
  - Send to Kindle (`cgdjpilhipecahhcilnafpblkieebhea`)
  - Tag Assistant (`kejbdjndbnbjgmefkgdddjlbokphdefk`)
  - 不明な拡張機能 (`ioijepjbllchodiajdakejdbjmdgggoj`)

#### 最も疑わしい犯人
- **Adobe Acrobat** — 全ページで content script 注入、起動直後に 12MB 書き込み
- **不明な拡張機能** (`ioijepjbllchodiajdakejdbjmdgggoj`) — 正体不明、Chrome Web Store に存在しない、両プロファイルにインストールされていた

#### 無罪確定
- **1Password Nightly** (`gejiddohjgogedgjnonbofjigllpkmbf`) — GWS 組織がインストール。Nightly は 1Password の開発版。ログでも正常動作（NmLockState 送受信 2-3ms）
- **1Password Stable** (`aeblfdkhhhdcdjpifhhbdiojplfjncoa`) — 正常
- **Wappalyzer** — 再インストールしてもクラッシュしない

### 11. GPU パイプラインクラッシュの発見 (3/17-18)

investigate.sh（Chrome を直接起動してログ収集）で詳細調査。

#### Meet タブ共有でクラッシュ
- Meet で「タブ」を画面共有しようとした瞬間にクラッシュ
- stderr 最後のエラー: `GPU state invalid after WaitForGetOffsetInRange`
- 直前: `Overflowed the render pipeline cache limit of 64 elements` が繰り返し出力
- WebRTC の EncodeVideoFrame → GPU パイプラインキャッシュオーバーフロー → GPU プロセスクラッシュ → Chrome 全体死亡

#### Claude Computer Use でクラッシュ
- Claude Computer Use（WebRTC タブキャプチャ）がアクティブな状態で同じパターンでクラッシュ
- `web-contents-media-stream://` がログに記録された直後に無言で消滅
- Meet のタブ共有と**同じ根本原因**（GPU パイプラインバグ）

#### 原因
- Chromium バグ #355266358（macOS ARM での GPU 処理バグ）
- Chrome 146.0.7680.80（最新安定版、2026-03-13 リリース）で発生
- fix-chrome-diskwrite では対処不可。Chrome 側の修正待ち
- **回避策**: Meet は「画面全体」を共有（タブキャプチャを避ける）

### 12. キャッシュ破損による連鎖クラッシュ (3/18)

Meet も Claude Computer Use も使っていないのにクラッシュが発生。

#### ログ分析
- stderr に **2,918件** の `Cannot stat` エラー（キャッシュファイルが存在しない）
- GPU エラー: なし
- WebRTC/タブキャプチャ: なし
- FATAL/シグナル: なし
- 前回のクラッシュでキャッシュが壊れたまま再起動したため、不整合が蓄積してクラッシュ

#### 対策
- cleanup.sh にクラッシュ後自動修復機能を追加
- 1時間ごとの LaunchAgent が `exit_type=Crashed` を検知
- Chrome 起動中でも壊れたキャッシュ（HTTP Cache、Code Cache、Service Worker CacheStorage、DawnWebGPUCache）を自動削除
- 共有キャッシュ（GraphiteDawnCache、BrowserMetrics）も掃除

### 結論の最終更新

Chrome クラッシュの原因は **5 つ**:
1. **Chrome 自体の disk writes** — Gemini Nano、コンポーネント、キャッシュ（対策済み）
2. **Google Drive の大量書き込み** — ストリーミングモードでもメタデータ同期で 8.6GB+（対策済み）
3. **拡張機能の過多** — 不要な拡張機能を削除で解決（対策済み）
4. **macOS ARM GPU パイプラインバグ** — Meet タブ共有、Claude Computer Use で発生（Chrome 側修正待ち）
5. **キャッシュ破損による連鎖クラッシュ** — cleanup.sh のクラッシュ検知で自動修復（対策済み）

## 現在の PC 上の状態 (3/18 時点)

### 常駐プロセス
- `com.fix-chrome-diskwrite.cleanup` LaunchAgent — 1 時間ごとに cleanup.sh を実行
- `~/.local/bin/fix-chrome-diskwrite-cleanup.sh` — クリーンアップスクリプト本体（クラッシュ後自動修復機能付き）
- `~/Library/Logs/fix-chrome-diskwrite-cleanup.log` — ログ

### Chrome Enterprise Policy（15 件）
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
| DiskCacheSize | 52428800 | HTTP キャッシュ 50MB 上限 |
| MediaCacheSize | 33554432 | メディアキャッシュ 32MB 上限 |
| ForceGpuMemAvailableMb | 4096 | GPU メモリ上限拡大 |
| RendererProcessLimit | 20 | Renderer プロセス数制限 |
| TotalMemoryLimitMb | 16384 | Chrome 全体メモリ 16GB 上限 |
| HighEfficiencyModeEnabled | true | メモリセーバー有効 |
| IntensiveWakeUpThrottlingEnabled | true | バックグラウンドタブ制限 |

### 削除済み拡張機能
バックアップは削除済み。以下の拡張機能は再インストールしていない:
- Adobe Acrobat, ChatGPT search, Claude in Chrome, GoFullPage
- React Developer Tools, Google Docs Offline, Application Launcher for Drive
- Send to Kindle, Tag Assistant, 不明な拡張機能 (`ioijepjb...`)
