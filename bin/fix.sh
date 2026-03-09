#!/bin/bash
# fix-chrome-diskwrite.sh — macOS 用
# Chrome の Gemini Nano オンデバイスAIモデル自動ダウンロードを停止する
#
# 対処法:
#   1. Enterprise Policy (GenAILocalFoundationalModelSettings) で DL を禁止
#   2. 既存モデルデータを削除 (約4GB解放)
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
POLICY_KEY="GenAILocalFoundationalModelSettings"

# --- 元に戻す ---
if [ "${1:-}" = "--undo" ]; then
  echo "元に戻しています..."
  defaults delete com.google.Chrome "$POLICY_KEY" 2>/dev/null && \
    echo "  Policy 削除: $POLICY_KEY" || \
    echo "  Policy: 設定されていません"
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

echo "---"
echo "完了。Chrome を再起動してください。"
echo "chrome://policy で $POLICY_KEY = 1 を確認できます。"
