#!/bin/bash
# fix-chrome-diskwrite.sh — macOS 用
# Chrome の過剰なディスク書き込みによるクラッシュを防止する
#
# 対処法:
#   1. Enterprise Policy (GenAILocalFoundationalModelSettings) で Gemini Nano の DL を禁止
#   2. 既存モデルデータを削除 (約4GB解放)
#   3. コンポーネント自動更新・ScreenAI・TTS 等のディスク書き込みを抑制
#   4. Chrome 内蔵パスワードマネージャー・自動入力を無効化 (SafariPlatformSupport.Helper クラッシュ防止)
#
# オプション:
#   --opt-guide        optimization_guide_model_store も削除する
#   --schedule         LaunchAgent を登録し、毎時自動で optimization_guide_model_store を削除する (--opt-guide と併用)
#   --full             コンポーネント更新抑制・ScreenAI・TTS 無効化・内蔵パスワードマネージャー無効化をすべて適用
#   --fix-crash-loop   クラッシュループを修復する (exit_type リセット + セッションファイルのバックアップ・削除)
#   --undo             設定を元に戻す (--opt-guide --schedule と併用で LaunchAgent も削除)
#
# 使い方:
#   curl -fsSL https://raw.githubusercontent.com/kanketsu-jp/fix-chrome-diskwrite/main/bin/fix.sh | bash
#
# 元に戻す:
#   curl -fsSL https://raw.githubusercontent.com/kanketsu-jp/fix-chrome-diskwrite/main/bin/fix.sh | bash -s -- --undo
#
# 参考:
#   https://chromeenterprise.google/policies/#GenAILocalFoundationalModelSettings

set -e

CHROME_BASE="$HOME/Library/Application Support/Google/Chrome"
MODEL_DIR="$CHROME_BASE/OptGuideOnDeviceModel"
OPT_GUIDE_DIR="$CHROME_BASE/optimization_guide_model_store"
POLICY_KEY="GenAILocalFoundationalModelSettings"
LAUNCH_AGENT_LABEL="com.fix-chrome-diskwrite.cleanup"
LAUNCH_AGENT_PLIST="$HOME/Library/LaunchAgents/$LAUNCH_AGENT_LABEL.plist"
CLEANUP_SCRIPT="$HOME/.local/bin/fix-chrome-diskwrite-cleanup.sh"
# --full で削除する追加コンポーネント
EXTRA_DIRS=(
  "$CHROME_BASE/screen_ai"
  "$CHROME_BASE/WasmTtsEngine"
  "$CHROME_BASE/component_crx_cache"
  "$CHROME_BASE/GraphiteDawnCache"
  "$CHROME_BASE/BrowserMetrics"
  "$CHROME_BASE/OnDeviceHeadSuggestModel"
)

# --- 引数パース ---
OPT_GUIDE=false
SCHEDULE=false
UNDO=false
FULL=false
FIX_CRASH_LOOP=false
for arg in "$@"; do
  case "$arg" in
    --undo) UNDO=true ;;
    --opt-guide) OPT_GUIDE=true ;;
    --schedule) SCHEDULE=true ;;
    --full) FULL=true ;;
    --fix-crash-loop) FIX_CRASH_LOOP=true ;;
  esac
done

# --- 元に戻す ---
if $UNDO; then
  echo "元に戻しています..."
  defaults delete com.google.Chrome "$POLICY_KEY" 2>/dev/null && \
    echo "  Policy 削除: $POLICY_KEY" || \
    echo "  Policy: 設定されていません"
  if $FULL; then
    for key in ComponentUpdatesEnabled ScreenAIEnabled TextToSpeechEnabled BackgroundModeEnabled PasswordManagerEnabled AutofillAddressEnabled AutofillCreditCardEnabled DiskCacheSize MediaCacheSize ForceGpuMemAvailableMb RendererProcessLimit TotalMemoryLimitMb HighEfficiencyModeEnabled IntensiveWakeUpThrottlingEnabled TabDiscardingExceptions SitePerProcess; do
      defaults delete com.google.Chrome "$key" 2>/dev/null && \
        echo "  Policy 削除: $key" || true
    done
  fi
  if $OPT_GUIDE && $SCHEDULE; then
    # 新旧どちらの LaunchAgent も削除
    for label in "$LAUNCH_AGENT_LABEL" "com.fix-chrome-diskwrite.opt-guide-cleanup"; do
      plist="$HOME/Library/LaunchAgents/$label.plist"
      if [ -f "$plist" ]; then
        launchctl bootout "gui/$(id -u)" "$plist" 2>/dev/null || true
        rm -f "$plist"
        echo "  LaunchAgent 削除: $label"
      fi
    done
    if [ -f "$CLEANUP_SCRIPT" ]; then
      rm -f "$CLEANUP_SCRIPT"
      echo "  スクリプト削除: $CLEANUP_SCRIPT"
    fi
    if [ ! -f "$LAUNCH_AGENT_PLIST" ] && [ ! -f "$HOME/Library/LaunchAgents/com.fix-chrome-diskwrite.opt-guide-cleanup.plist" ]; then
      echo "  LaunchAgent: 登録されていません"
    fi
  fi
  echo "完了。Chrome を再起動してください。"
  echo "chrome://policy で確認できます。"
  exit 0
fi

# --- Chrome 起動チェック ---
if pgrep -qx "Google Chrome"; then
  echo "Error: Chrome を終了してから再実行してください。"
  exit 1
fi

# --- クラッシュループ修復 (全プロファイル対応) ---
if $FIX_CRASH_LOOP; then
  echo "クラッシュループ修復"
  echo "---"

  # 全プロファイルを自動検出
  profile_dirs=("$CHROME_BASE/Default")
  for p in "$CHROME_BASE"/Profile\ *; do
    [ -d "$p" ] && profile_dirs+=("$p")
  done

  ts=$(date +%Y%m%d%H%M%S)

  for profile_dir in "${profile_dirs[@]}"; do
    profile_name=$(basename "$profile_dir")
    prefs_file="$profile_dir/Preferences"
    sessions_dir="$profile_dir/Sessions"

    # Preferences の exit_type をリセット
    if [ -f "$prefs_file" ]; then
      exit_type=$(python3 -c "
import json
with open('$prefs_file') as f:
    prefs = json.load(f)
print(prefs.get('profile', {}).get('exit_type', 'unknown'))
" 2>/dev/null)

      if [ "$exit_type" = "Crashed" ]; then
        python3 -c "
import json
with open('$prefs_file', 'r') as f:
    prefs = json.load(f)
prefs.setdefault('profile', {})['exit_type'] = 'Normal'
prefs['profile']['exited_cleanly'] = True
with open('$prefs_file', 'w') as f:
    json.dump(prefs, f)
"
        echo "  [$profile_name] 修復: exit_type を Crashed → Normal にリセット"
      else
        echo "  [$profile_name] スキップ: exit_type = $exit_type"
      fi
    fi

    # セッションファイルをバックアップ・削除
    if [ -d "$sessions_dir" ]; then
      session_count=$(find "$sessions_dir" -name "Session_*" -o -name "Tabs_*" 2>/dev/null | wc -l | tr -d ' ')
      if [ "$session_count" -gt 0 ]; then
        backup_dir="${sessions_dir}_backup_${ts}"
        mkdir -p "$backup_dir"
        cp "$sessions_dir"/Session_* "$sessions_dir"/Tabs_* "$backup_dir/" 2>/dev/null
        rm -f "$sessions_dir"/Session_* "$sessions_dir"/Tabs_*
        echo "  [$profile_name] 削除: セッションファイル ${session_count} 件 (バックアップ: Sessions_backup_${ts})"
      fi
    fi
  done

  echo "---"
  echo "完了。Chrome を再起動してください。"
  echo "以前のタブは chrome://history から個別に復元できます。"
  exit 0
fi

echo "Chrome ディスク書き込み制限超過クラッシュ防止"
echo "---"

# 1. Enterprise Policy で Gemini Nano の DL を禁止 (公式サポート, Chrome 124+)
#    値 1 = モデルをダウンロードしない
defaults write com.google.Chrome "$POLICY_KEY" -int 1
echo "  Policy 設定: $POLICY_KEY = 1 (Gemini Nano DL禁止)"

# 2. 既存モデルデータを削除
if [ -d "$MODEL_DIR" ]; then
  size=$(du -sh "$MODEL_DIR" 2>/dev/null | cut -f1)
  rm -rf "$MODEL_DIR"
  echo "  削除: OptGuideOnDeviceModel ($size)"
elif [ -e "$MODEL_DIR" ]; then
  # 前回の immutable ロックファイルが残っている場合
  chflags nouchg "$MODEL_DIR" 2>/dev/null || true
  rm -f "$MODEL_DIR"
  echo "  旧ロックファイル削除: OptGuideOnDeviceModel"
else
  echo "  スキップ: OptGuideOnDeviceModel (存在しない)"
fi

# 3. (オプション) optimization_guide_model_store の削除
#    公式 Enterprise Policy は存在しないため、ディレクトリ削除で対応
if $OPT_GUIDE; then
  if [ -d "$OPT_GUIDE_DIR" ]; then
    size=$(du -sh "$OPT_GUIDE_DIR" 2>/dev/null | cut -f1)
    rm -rf "$OPT_GUIDE_DIR"
    echo "  削除: optimization_guide_model_store ($size)"
  else
    echo "  スキップ: optimization_guide_model_store (存在しない)"
  fi

  # 4. (オプション) LaunchAgent で定期キャッシュクリーンアップ
  #    Chrome 未起動時のみ、閾値 (100MB) を超えたキャッシュを自動削除
  if $SCHEDULE; then
    # cleanup.sh をインストール
    mkdir -p "$(dirname "$CLEANUP_SCRIPT")"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$SCRIPT_DIR/cleanup.sh" ]; then
      cp "$SCRIPT_DIR/cleanup.sh" "$CLEANUP_SCRIPT"
    else
      # curl 経由で実行された場合はダウンロード
      curl -fsSL "https://raw.githubusercontent.com/kanketsu-jp/fix-chrome-diskwrite/main/bin/cleanup.sh" -o "$CLEANUP_SCRIPT"
    fi
    chmod +x "$CLEANUP_SCRIPT"
    echo "  スクリプト配置: $CLEANUP_SCRIPT"

    # 旧 LaunchAgent の削除 (ラベル名が変わった場合)
    OLD_LABEL="com.fix-chrome-diskwrite.opt-guide-cleanup"
    OLD_PLIST="$HOME/Library/LaunchAgents/$OLD_LABEL.plist"
    if [ -f "$OLD_PLIST" ]; then
      launchctl bootout "gui/$(id -u)" "$OLD_PLIST" 2>/dev/null || true
      rm -f "$OLD_PLIST"
    fi

    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$LAUNCH_AGENT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LAUNCH_AGENT_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${CLEANUP_SCRIPT}</string>
  </array>
  <key>StartInterval</key>
  <integer>3600</integer>
  <key>StandardOutPath</key>
  <string>/dev/null</string>
  <key>StandardErrorPath</key>
  <string>/dev/null</string>
</dict>
</plist>
PLIST
    launchctl bootout "gui/$(id -u)" "$LAUNCH_AGENT_PLIST" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT_PLIST"
    echo "  LaunchAgent 登録: 1時間ごとにキャッシュクリーンアップ (閾値: 100MB)"
  fi
fi

# 5. (オプション) --full: コンポーネント更新抑制・追加コンポーネント削除・内蔵パスワードマネージャー無効化
if $FULL; then
  echo ""
  echo "追加対策 (--full)"
  echo "---"

  # 5a. コンポーネント自動更新を無効化
  defaults write com.google.Chrome ComponentUpdatesEnabled -bool false
  echo "  Policy 設定: ComponentUpdatesEnabled = false (コンポーネント自動更新停止)"

  # 5b. ScreenAI (OCR/アクセシビリティAI) を無効化
  defaults write com.google.Chrome ScreenAIEnabled -bool false
  echo "  Policy 設定: ScreenAIEnabled = false"

  # 5c. TTS (テキスト読み上げ) を無効化
  defaults write com.google.Chrome TextToSpeechEnabled -bool false
  echo "  Policy 設定: TextToSpeechEnabled = false"

  # 5d. バックグラウンドモードを無効化
  defaults write com.google.Chrome BackgroundModeEnabled -bool false
  echo "  Policy 設定: BackgroundModeEnabled = false"

  # 5e. Chrome 内蔵パスワードマネージャー・自動入力を無効化
  #     macOS の SafariPlatformSupport.Helper がメモリ上限超過で kill され
  #     Chrome が連鎖クラッシュする問題を防止 (1Password 等の外部マネージャーには影響なし)
  defaults write com.google.Chrome PasswordManagerEnabled -bool false
  defaults write com.google.Chrome AutofillAddressEnabled -bool false
  defaults write com.google.Chrome AutofillCreditCardEnabled -bool false
  echo "  Policy 設定: PasswordManagerEnabled = false (内蔵パスワードマネージャー無効化)"
  echo "  Policy 設定: AutofillAddressEnabled = false"
  echo "  Policy 設定: AutofillCreditCardEnabled = false"
  echo "  ※ 1Password 等の拡張機能には影響しません"

  # 5f. ディスクキャッシュサイズの制限
  #     デフォルトではプロファイルごとに 1-2GB まで膨らむ。
  #     50MB / 32MB に制限することで、キャッシュの肥大化を防止する。
  defaults write com.google.Chrome DiskCacheSize -integer 52428800
  defaults write com.google.Chrome MediaCacheSize -integer 33554432
  echo "  Policy 設定: DiskCacheSize = 50MB (HTTP キャッシュ上限)"
  echo "  Policy 設定: MediaCacheSize = 32MB (メディアキャッシュ上限)"

  # 5f-2. タブの省エネ設定
  #       非アクティブタブを積極的に破棄し、バックグラウンドの JS 実行を制限する。
  #       これにより Service Worker やタイマーによるネットワーク通信が減り、disk writes が削減される。
  defaults write com.google.Chrome HighEfficiencyModeEnabled -bool true
  defaults write com.google.Chrome IntensiveWakeUpThrottlingEnabled -bool true
  echo "  Policy 設定: HighEfficiencyModeEnabled = true (メモリセーバー有効)"
  echo "  Policy 設定: IntensiveWakeUpThrottlingEnabled = true (バックグラウンドタブ制限)"

  # 5g. GPU・メモリ安定化 (Renderer クラッシュ防止)
  #     GPU プロセスのメモリ不足によるクラッシュを防止する。
  #     Chrome はデフォルトで GPU 利用可能メモリを保守的に見積もるため、
  #     Apple Silicon の統合メモリでは不足してクラッシュすることがある。
  defaults write com.google.Chrome ForceGpuMemAvailableMb -integer 4096
  echo "  Policy 設定: ForceGpuMemAvailableMb = 4096MB (GPU メモリ上限)"
  defaults write com.google.Chrome RendererProcessLimit -integer 20
  echo "  Policy 設定: RendererProcessLimit = 20 (Renderer プロセス数上限)"
  defaults write com.google.Chrome TotalMemoryLimitMb -integer 16384
  echo "  Policy 設定: TotalMemoryLimitMb = 16384MB (Chrome 全体メモリ上限)"

  # 5f. 追加コンポーネントのデータ削除
  for dir in "${EXTRA_DIRS[@]}"; do
    if [ -d "$dir" ]; then
      size=$(du -sh "$dir" 2>/dev/null | cut -f1)
      rm -rf "$dir"
      echo "  削除: $(basename "$dir") ($size)"
    fi
  done
  rm -f "$CHROME_BASE/BrowserMetrics-spare.pma"

  # 5g. ブラウザキャッシュの削除 (~/Library/Caches/Google/Chrome/)
  #     Application Support とは別の場所にある HTTP/Code Cache。
  #     これが数 GB に膨らみ、起動時の読み書きで disk writes 制限を超過する主因となる。
  CHROME_CACHE="$HOME/Library/Caches/Google/Chrome"
  if [ -d "$CHROME_CACHE" ]; then
    size=$(du -sh "$CHROME_CACHE" 2>/dev/null | cut -f1)
    rm -rf "$CHROME_CACHE"
    echo "  削除: ~/Library/Caches/Google/Chrome/ ($size)"
  fi
fi

echo "---"
echo "完了。Chrome を再起動してください。"
echo "chrome://policy で設定を確認できます。"
