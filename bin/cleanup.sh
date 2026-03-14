#!/bin/bash
# cleanup.sh — Chrome キャッシュの定期クリーンアップ (LaunchAgent から呼び出される)
#
# Chrome が起動していない場合のみ実行。
# 各キャッシュディレクトリのサイズが閾値を超えていたら削除する。
# Chrome は次回起動時に必要なキャッシュを再生成する (小さいサイズから開始)。

CHROME_BASE="$HOME/Library/Application Support/Google/Chrome"
LOG_FILE="$HOME/Library/Logs/fix-chrome-diskwrite-cleanup.log"

# 閾値 (MB) — これを超えたら削除
THRESHOLD_MB=100

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

# Chrome 起動中はスキップ (起動中に削除するとタブがクラッシュする)
if pgrep -qx "Google Chrome"; then
  log "SKIP: Chrome is running"
  exit 0
fi

log "START cleanup"

# --- プロファイル共通のキャッシュ ---
SHARED_DIRS=(
  "$CHROME_BASE/optimization_guide_model_store"
  "$CHROME_BASE/GraphiteDawnCache"
  "$CHROME_BASE/BrowserMetrics"
  "$CHROME_BASE/component_crx_cache"
  "$CHROME_BASE/screen_ai"
  "$CHROME_BASE/WasmTtsEngine"
  "$CHROME_BASE/OnDeviceHeadSuggestModel"
)

for dir in "${SHARED_DIRS[@]}"; do
  if [ -d "$dir" ]; then
    size_kb=$(du -sk "$dir" 2>/dev/null | cut -f1)
    size_mb=$((size_kb / 1024))
    if [ "$size_mb" -ge "$THRESHOLD_MB" ]; then
      rm -rf "$dir"
      log "DELETED: $(basename "$dir") (${size_mb}MB >= ${THRESHOLD_MB}MB)"
    fi
  fi
done

# BrowserMetrics-spare.pma (共通)
rm -f "$CHROME_BASE/BrowserMetrics-spare.pma" 2>/dev/null

# --- プロファイルごとのキャッシュ ---
# 全プロファイルを自動検出 (Default, Profile 2, Profile 3, ...)
PROFILES=("$CHROME_BASE/Default")
for p in "$CHROME_BASE"/Profile\ *; do
  [ -d "$p" ] && PROFILES+=("$p")
done

for profile_dir in "${PROFILES[@]}"; do
  profile_name=$(basename "$profile_dir")

  # Service Worker CacheStorage — 最大の書き込み元
  sw_cache="$profile_dir/Service Worker/CacheStorage"
  if [ -d "$sw_cache" ]; then
    size_kb=$(du -sk "$sw_cache" 2>/dev/null | cut -f1)
    size_mb=$((size_kb / 1024))
    if [ "$size_mb" -ge "$THRESHOLD_MB" ]; then
      rm -rf "$sw_cache"
      log "DELETED: $profile_name/Service Worker/CacheStorage (${size_mb}MB >= ${THRESHOLD_MB}MB)"
    fi
  fi

  # DawnWebGPUCache
  dawn_cache="$profile_dir/DawnWebGPUCache"
  if [ -d "$dawn_cache" ]; then
    size_kb=$(du -sk "$dawn_cache" 2>/dev/null | cut -f1)
    size_mb=$((size_kb / 1024))
    if [ "$size_mb" -ge "$THRESHOLD_MB" ]; then
      rm -rf "$dawn_cache"
      log "DELETED: $profile_name/DawnWebGPUCache (${size_mb}MB >= ${THRESHOLD_MB}MB)"
    fi
  fi

  # DIPS-wal (write-ahead log, 常に削除して問題ない)
  rm -f "$profile_dir/DIPS-wal" 2>/dev/null
done

log "END cleanup"
