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
#   --opt-guide  optimization_guide_model_store も削除する
#   --schedule   LaunchAgent を登録し、毎時自動で optimization_guide_model_store を削除する (--opt-guide と併用)
#   --full       コンポーネント更新抑制・ScreenAI・TTS 無効化・内蔵パスワードマネージャー無効化をすべて適用
#   --undo       設定を元に戻す (--opt-guide --schedule と併用で LaunchAgent も削除)
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
LAUNCH_AGENT_LABEL="com.fix-chrome-diskwrite.opt-guide-cleanup"
LAUNCH_AGENT_PLIST="$HOME/Library/LaunchAgents/$LAUNCH_AGENT_LABEL.plist"

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
for arg in "$@"; do
  case "$arg" in
    --undo) UNDO=true ;;
    --opt-guide) OPT_GUIDE=true ;;
    --schedule) SCHEDULE=true ;;
    --full) FULL=true ;;
  esac
done

# --- 元に戻す ---
if $UNDO; then
  echo "元に戻しています..."
  defaults delete com.google.Chrome "$POLICY_KEY" 2>/dev/null && \
    echo "  Policy 削除: $POLICY_KEY" || \
    echo "  Policy: 設定されていません"
  if $FULL; then
    for key in ComponentUpdatesEnabled ScreenAIEnabled TextToSpeechEnabled BackgroundModeEnabled PasswordManagerEnabled AutofillAddressEnabled AutofillCreditCardEnabled; do
      defaults delete com.google.Chrome "$key" 2>/dev/null && \
        echo "  Policy 削除: $key" || true
    done
  fi
  if $OPT_GUIDE && $SCHEDULE; then
    if launchctl bootout "gui/$(id -u)" "$LAUNCH_AGENT_PLIST" 2>/dev/null; then
      echo "  LaunchAgent 停止: $LAUNCH_AGENT_LABEL"
    fi
    if [ -f "$LAUNCH_AGENT_PLIST" ]; then
      rm -f "$LAUNCH_AGENT_PLIST"
      echo "  LaunchAgent 削除: $LAUNCH_AGENT_PLIST"
    else
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

  # 4. (オプション) LaunchAgent で毎時自動削除
  if $SCHEDULE; then
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
    <string>/bin/rm</string>
    <string>-rf</string>
    <string>${OPT_GUIDE_DIR}</string>
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
    echo "  LaunchAgent 登録: 1時間ごとに optimization_guide_model_store を自動削除"
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

  # 5f. 追加コンポーネントのデータ削除
  for dir in "${EXTRA_DIRS[@]}"; do
    if [ -d "$dir" ]; then
      size=$(du -sh "$dir" 2>/dev/null | cut -f1)
      rm -rf "$dir"
      echo "  削除: $(basename "$dir") ($size)"
    fi
  done
  rm -f "$CHROME_BASE/BrowserMetrics-spare.pma"
fi

echo "---"
echo "完了。Chrome を再起動してください。"
echo "chrome://policy で設定を確認できます。"
