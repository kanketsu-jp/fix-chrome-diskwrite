#!/bin/bash
# cleanup.sh — Chrome キャッシュの定期クリーンアップ (LaunchAgent から呼び出される)
#
# Chrome が起動していない場合のみ実行。
# 各キャッシュディレクトリのサイズが閾値を超えていたら削除する。
# Chrome は次回起動時に必要なキャッシュを再生成する (小さいサイズから開始)。

CHROME_BASE="$HOME/Library/Application Support/Google/Chrome"
CHROME_CACHE="$HOME/Library/Caches/Google/Chrome"
LOG_FILE="$HOME/Library/Logs/fix-chrome-diskwrite-cleanup.log"

# 閾値 (MB) — これを超えたら削除
THRESHOLD_MB=100

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

# --- クラッシュ後のキャッシュ修復 ---
# Chrome 起動中でも、前回クラッシュしていたらキャッシュを削除する。
# exit_type が "Crashed" の場合、キャッシュが壊れている可能性が高い。
check_and_repair_crash() {
  local profile_dir="$1"
  local prefs="$profile_dir/Preferences"
  [ -f "$prefs" ] || return 0

  local exit_type
  exit_type=$(python3 -c "
import json, sys
try:
  d = json.load(open('$prefs'))
  print(d.get('profile', {}).get('exit_type', ''))
except: pass
" 2>/dev/null)

  if [ "$exit_type" = "Crashed" ]; then
    local profile_name
    profile_name=$(basename "$profile_dir")
    log "CRASH DETECTED: $profile_name (exit_type=Crashed) — cleaning corrupted cache"

    # Application Support 内のキャッシュ
    rm -rf "$profile_dir/Service Worker/CacheStorage" 2>/dev/null
    rm -rf "$profile_dir/DawnWebGPUCache" 2>/dev/null
    rm -f "$profile_dir/DIPS-wal" 2>/dev/null

    # ~/Library/Caches/ 内のキャッシュ
    local cache_profile="$CHROME_CACHE/$profile_name"
    rm -rf "$cache_profile/Cache" 2>/dev/null
    rm -rf "$cache_profile/Code Cache" 2>/dev/null

    log "REPAIRED: $profile_name cache cleaned after crash"
    return 1
  fi
  return 0
}

CRASH_REPAIRED=0
for profile_dir in "$CHROME_BASE/Default" "$CHROME_BASE"/Profile\ *; do
  [ -d "$profile_dir" ] || continue
  if check_and_repair_crash "$profile_dir"; then :; else
    CRASH_REPAIRED=1
  fi
done

if [ "$CRASH_REPAIRED" -eq 1 ]; then
  # 共有キャッシュも掃除
  rm -rf "$CHROME_BASE/GraphiteDawnCache" 2>/dev/null
  rm -rf "$CHROME_BASE/BrowserMetrics" 2>/dev/null
  rm -f "$CHROME_BASE/BrowserMetrics-spare.pma" 2>/dev/null
  log "CRASH REPAIR: shared cache also cleaned"
fi

# Chrome 起動中はここで終了 (通常クリーンアップはスキップ)
if pgrep -qx "Google Chrome"; then
  if [ "$CRASH_REPAIRED" -eq 1 ]; then
    log "END cleanup (crash repair only, Chrome is running)"
  else
    log "SKIP: Chrome is running"
  fi
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

# --- ~/Library/Caches/Google/Chrome/ (ブラウザキャッシュ本体) ---
# Application Support とは別の場所にあるキャッシュ。
# HTTP キャッシュ (Cache/) と JavaScript コンパイルキャッシュ (Code Cache/) が大部分。
# 削除しても履歴・ブックマーク・パスワード等には影響しない。
CACHE_PROFILES=("$CHROME_CACHE/Default")
for p in "$CHROME_CACHE"/Profile\ *; do
  [ -d "$p" ] && CACHE_PROFILES+=("$p")
done

for cache_dir in "${CACHE_PROFILES[@]}"; do
  profile_name=$(basename "$cache_dir")

  for subdir in "Cache" "Code Cache"; do
    target="$cache_dir/$subdir"
    if [ -d "$target" ]; then
      size_kb=$(du -sk "$target" 2>/dev/null | cut -f1)
      size_mb=$((size_kb / 1024))
      if [ "$size_mb" -ge "$THRESHOLD_MB" ]; then
        rm -rf "$target"
        log "DELETED: Caches/$profile_name/$subdir (${size_mb}MB >= ${THRESHOLD_MB}MB)"
      fi
    fi
  done
done

log "END cleanup"
