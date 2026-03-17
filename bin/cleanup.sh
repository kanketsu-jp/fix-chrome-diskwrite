#!/bin/bash
# cleanup.sh — Chrome キャッシュの定期クリーンアップ (LaunchAgent から呼び出される)
#
# Chrome が起動していない場合のみキャッシュを削除する。
# Chrome 起動中にキャッシュを削除すると Cannot stat エラーでもっさりする。
# Chrome 起動中は exit_type のリセットのみ行う（クラッシュループ防止）。

CHROME_BASE="$HOME/Library/Application Support/Google/Chrome"
CHROME_CACHE="$HOME/Library/Caches/Google/Chrome"
LOG_FILE="$HOME/Library/Logs/fix-chrome-diskwrite-cleanup.log"

# 閾値 (MB) — これを超えたら削除
THRESHOLD_MB=100

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

# --- プロファイル一覧を取得 ---
PROFILES=("$CHROME_BASE/Default")
for p in "$CHROME_BASE"/Profile\ *; do
  [ -d "$p" ] && PROFILES+=("$p")
done

# --- クラッシュ検知: exit_type のチェック ---
# 戻り値: 0=正常, 1=Crashed検知
check_crash() {
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

  [ "$exit_type" = "Crashed" ] && return 1
  return 0
}

# --- exit_type を Normal にリセット ---
reset_exit_type() {
  local profile_dir="$1"
  local prefs="$profile_dir/Preferences"
  [ -f "$prefs" ] || return

  python3 -c "
import json
path = '$prefs'
d = json.load(open(path))
if d.get('profile', {}).get('exit_type') == 'Crashed':
    d['profile']['exit_type'] = 'Normal'
    d['profile']['exited_cleanly'] = True
    json.dump(d, open(path, 'w'), separators=(',', ':'))
" 2>/dev/null
}

# --- プロファイルのキャッシュを削除 ---
clean_profile_cache() {
  local profile_dir="$1"
  local profile_name
  profile_name=$(basename "$profile_dir")

  # Application Support 内
  rm -rf "$profile_dir/Service Worker/CacheStorage" 2>/dev/null
  rm -rf "$profile_dir/DawnWebGPUCache" 2>/dev/null
  rm -f "$profile_dir/DIPS-wal" 2>/dev/null

  # ~/Library/Caches/ 内
  local cache_profile="$CHROME_CACHE/$profile_name"
  rm -rf "$cache_profile/Cache" 2>/dev/null
  rm -rf "$cache_profile/Code Cache" 2>/dev/null

  log "REPAIRED: $profile_name cache cleaned"
}

# --- メイン処理 ---

CHROME_RUNNING=false
pgrep -qx "Google Chrome" && CHROME_RUNNING=true

# クラッシュ検知
CRASH_DETECTED=false
for profile_dir in "${PROFILES[@]}"; do
  [ -d "$profile_dir" ] || continue
  if ! check_crash "$profile_dir"; then
    CRASH_DETECTED=true
    break
  fi
done

if $CHROME_RUNNING; then
  # --- Chrome 起動中 ---
  if $CRASH_DETECTED; then
    # クラッシュループ防止: exit_type だけリセット
    # キャッシュは削除しない（削除すると Cannot stat エラーで逆効果）
    for profile_dir in "${PROFILES[@]}"; do
      [ -d "$profile_dir" ] || continue
      if ! check_crash "$profile_dir"; then
        profile_name=$(basename "$profile_dir")
        reset_exit_type "$profile_dir"
        log "CRASH LOOP PREVENTION: $profile_name exit_type reset to Normal (cache cleanup deferred to next restart)"
      fi
    done
    log "END cleanup (exit_type reset only, Chrome is running — cache will be cleaned when Chrome is not running)"
  else
    log "SKIP: Chrome is running"
  fi
  exit 0
fi

# --- Chrome 未起動 ---
log "START cleanup"

# クラッシュ後の修復（Chrome 未起動なので安全にキャッシュ削除可能）
if $CRASH_DETECTED; then
  for profile_dir in "${PROFILES[@]}"; do
    [ -d "$profile_dir" ] || continue
    if ! check_crash "$profile_dir"; then
      profile_name=$(basename "$profile_dir")
      log "CRASH DETECTED: $profile_name (exit_type=Crashed)"
      reset_exit_type "$profile_dir"
      clean_profile_cache "$profile_dir"
    fi
  done
  # 共有キャッシュも掃除
  rm -rf "$CHROME_BASE/GraphiteDawnCache" 2>/dev/null
  rm -rf "$CHROME_BASE/BrowserMetrics" 2>/dev/null
  rm -f "$CHROME_BASE/BrowserMetrics-spare.pma" 2>/dev/null
  log "CRASH REPAIR: shared cache also cleaned"
fi

# --- プロファイル共通のキャッシュ（サイズベース） ---
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

# --- プロファイルごとのキャッシュ（サイズベース） ---
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
