#!/bin/bash
# fix-chrome-diskwrite.sh — macOS 用
# Chrome の Gemini Nano オンデバイスAIモデル自動ダウンロードを停止する
#
# 対処法:
#   1. Enterprise Policy (GenAILocalFoundationalModelSettings) で DL を禁止
#   2. 既存モデルデータを削除 (約4GB解放)
#
# オプション:
#   --opt-guide  optimization_guide_model_store も削除する
#   --schedule   LaunchAgent を登録し、毎日自動で optimization_guide_model_store を削除する (--opt-guide と併用)
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

# --- 引数パース ---
OPT_GUIDE=false
SCHEDULE=false
UNDO=false
for arg in "$@"; do
  case "$arg" in
    --undo) UNDO=true ;;
    --opt-guide) OPT_GUIDE=true ;;
    --schedule) SCHEDULE=true ;;
  esac
done

# --- 元に戻す ---
if $UNDO; then
  echo "元に戻しています..."
  defaults delete com.google.Chrome "$POLICY_KEY" 2>/dev/null && \
    echo "  Policy 削除: $POLICY_KEY" || \
    echo "  Policy: 設定されていません"
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

echo "Chrome オンデバイスAIモデル無効化"
echo "---"

# 1. Enterprise Policy で DL を禁止 (公式サポート, Chrome 124+)
#    値 1 = モデルをダウンロードしない
defaults write com.google.Chrome "$POLICY_KEY" -int 1
echo "  Policy 設定: $POLICY_KEY = 1 (DL禁止)"

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

  # 4. (オプション) LaunchAgent で毎日自動削除
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

echo "---"
echo "完了。Chrome を再起動してください。"
echo "chrome://policy で $POLICY_KEY = 1 を確認できます。"
