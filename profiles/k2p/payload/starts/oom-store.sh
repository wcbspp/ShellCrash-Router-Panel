#!/bin/sh
# Bounded local queue; persist only while the existing management lock is held.
set -u
set -o pipefail
C=${CRASHDIR:-/etc/storage/ShellCrash}
D=${SC_OOM_RUNTIME:-/tmp/sc-admin}
P="$C/configs/oom-history.b64"
Q="$D/oom-queue.b64"
mkdir -p "$D" || exit 1
umask 077
valid(){
 if [ ! -e "$1" ] && [ ! -L "$1" ];then return 0;fi
 [ -f "$1" ] && [ ! -L "$1" ] || return 1
 awk 'length($0)<1 || length($0)>8192 || $0~/[^A-Za-z0-9+\/=]/ {bad=1} END{exit bad || NR>2}' "$1" || return 1
 while IFS= read -r row;do
  decoded=$(printf '%s' "$row" | base64 -d 2>/dev/null | base64 | tr -d '\n') || return 1
  [ "$decoded" = "$row" ] || return 1
 done < "$1"
}
lock(){
 if ! mkdir "$D/oom-store.lock" 2>/dev/null;then
  # Serialize stale-lock cleanup so a new owner's lock cannot be removed.
  mkdir "$D/oom-store-reap.lock" 2>/dev/null || return 1
  owner=$(cat "$D/oom-store.lock/owner" 2>/dev/null)
  case "$owner" in
   ''|*[!0-9]*)
    age=$(stat -c %Y "$D/oom-store.lock" 2>/dev/null);now=$(date +%s)
    case "$age:$now" in *[!0-9:]*|:*)rmdir "$D/oom-store-reap.lock";return 1;;esac
    [ "$((now-age))" -ge 60 ] || { rmdir "$D/oom-store-reap.lock";return 1; };;
   *) if kill -0 "$owner" 2>/dev/null;then rmdir "$D/oom-store-reap.lock";return 1;fi;;
  esac
  rm -f "$D/oom-store.lock/owner"
  rmdir "$D/oom-store.lock" 2>/dev/null || { rmdir "$D/oom-store-reap.lock";return 1; }
  rmdir "$D/oom-store-reap.lock" || return 1
  mkdir "$D/oom-store.lock" 2>/dev/null || return 1
 fi
 echo $$ > "$D/oom-store.lock/owner"
}
unlock(){ rm -f "$D/oom-store.lock/owner";rmdir "$D/oom-store.lock" 2>/dev/null || :; }
case "${1:-}" in
 enqueue)
  pending=${2:-}
  if [ -z "$pending" ];then
   [ -f "$D/oom-evidence.log" ] || exit 1
   stamp=$(cut -d. -f1 "${SC_OOM_UPTIME_FILE:-/proc/uptime}");case "$stamp" in ''|*[!0-9]*)exit 1;;esac
   event="$D/oom-event.$$";pending=$(printf '%s/oom-pending.%012d.%010d' "$D" "$stamp" "$$")
   (set -C; : > "$event") 2>/dev/null || exit 1
   cp "$D/oom-evidence.log" "$event" && mv "$event" "$pending" || { rm -f "$event";exit 1; }
  else
   case "$pending" in "$D"/oom-pending.*) :;;*)exit 1;;esac
   [ -f "$pending" ] && [ ! -L "$pending" ] || exit 1
  fi
  lock || { echo queue_busy > "$D/oom-save-status";exit 1; }
  trap unlock EXIT
  trap 'exit 1' HUP INT TERM
  valid "$Q" || { echo queue_invalid > "$D/oom-save-status";exit 1; }
  for pending in "$D"/oom-pending.*;do
   [ -f "$pending" ] && [ ! -L "$pending" ] || continue
   { head -c 512 "$pending";printf '\n=== RECENT EVIDENCE ===\n';tail -c 5400 "$pending"; } | base64 | tr -d '\n' > "$D/oom-entry.new" || exit 1
   [ -s "$D/oom-entry.new" ] && [ "$(wc -c < "$D/oom-entry.new")" -le 8192 ] || exit 1
   { [ ! -f "$Q" ] || cat "$Q";cat "$D/oom-entry.new";printf '\n'; } | tail -n 2 > "$D/oom-queue.new"
   mv "$D/oom-queue.new" "$Q" || { echo queue_write_failed > "$D/oom-save-status";exit 1; }
   rm -f "$D/oom-entry.new" "$pending"
  done
  echo pending > "$D/oom-save-status";;
 persist)
  [ -s "$Q" ] || exit 0
  now=$(cut -d. -f1 /proc/uptime);case "$now" in ''|*[!0-9]*)now=0;;esac
  due=$(cat "$D/oom-retry-at" 2>/dev/null);case "$due" in ''|*[!0-9]*)due=0;;esac
  [ "$now" -ge "$due" ] || exit 1
  available=$(awk '/^MemAvailable:/{print $2;exit}' /proc/meminfo)
  case "$available" in ''|*[!0-9]*)available=0;;esac
  [ "$available" -ge 18432 ] || { echo pending_low_memory > "$D/oom-save-status";exit 1; }
  lock || exit 1
  trap 'rm -f "$D/operation.lock/owner";rmdir "$D/operation.lock" 2>/dev/null || :;unlock' EXIT
  trap 'exit 1' HUP INT TERM
  if ! mkdir "$D/operation.lock" 2>/dev/null;then trap unlock EXIT;echo pending_busy > "$D/oom-save-status";exit 1;fi
  echo $$ > "$D/operation.lock/owner"
  available=$(awk '/^MemAvailable:/{print $2;exit}' /proc/meminfo)
  case "$available" in ''|*[!0-9]*)available=0;;esac
  [ "$available" -ge 18432 ] || { echo pending_low_memory > "$D/oom-save-status";exit 1; }
  valid "$P" && valid "$Q" || { echo previous_invalid > "$D/oom-save-status";exit 1; }
  if [ -f "$P" ];then cp "$P" "$D/oom-previous" || exit 1;had=1;else rm -f "$D/oom-previous";had=0;fi
  { [ ! -f "$P" ] || cat "$P";cat "$Q"; } | tail -n 2 > "$D/oom-candidate" || exit 1
  valid "$D/oom-candidate" && [ -s "$D/oom-candidate" ] || exit 1
  cp "$D/oom-candidate" "$P.new" && mv "$P.new" "$P" || { rm -f "$P.new";exit 1; }
  if [ -f "$D/oom-save.log" ] && [ "$(wc -c < "$D/oom-save.log")" -gt 32768 ];then
   tail -c 16384 "$D/oom-save.log" > "$D/oom-save.log.new" && mv "$D/oom-save.log.new" "$D/oom-save.log" || :
  fi
  if SC_STORAGE_MAX_BYTES=499712 SC_STORAGE_VERIFY=1 "$C/starts/save_storage.sh" >> "$D/oom-save.log" 2>&1;then
   rm -f "$Q" "$D/oom-previous" "$D/oom-candidate" "$D/oom-retry-at" "$D/oom-retry-count";echo saved > "$D/oom-save-status"
  else
   save_code=$?
   if [ "$had" = 1 ];then cp "$D/oom-previous" "$P.new" && mv "$P.new" "$P" || { echo rollback_failed > "$D/oom-save-status";exit 1; };else rm -f "$P";fi
   if [ "$save_code" = 75 ];then echo pending_busy > "$D/oom-save-status";exit 1;fi
   attempts=$(cat "$D/oom-retry-count" 2>/dev/null);case "$attempts" in ''|*[!0-9]*)attempts=0;;esac
   [ "$attempts" -ge 5 ] || attempts=$((attempts+1))
   case "$attempts" in 1) delay=60;;2) delay=300;;3) delay=1800;;4) delay=7200;;*)delay=21600;;esac
   printf '%s\n' "$attempts" > "$D/oom-retry-count";printf '%s\n' "$((now+delay))" > "$D/oom-retry-at"
   echo pending_save_failed > "$D/oom-save-status";exit 1
  fi;;
 read)
  valid "$P" || { echo 'OOM 记录损坏，请保留现场';exit 1; }
  if [ -f "$P" ];then while IFS= read -r line;do printf '%s' "$line" | base64 -d;printf '\n\n';done < "$P";fi
  status=$(cat "$D/oom-save-status" 2>/dev/null);case "$status" in
   pending_low_memory)echo '内存不足，新的 OOM 记录等待保存；断电前可能丢失。';;
   pending_busy|queue_busy)echo '其他操作正在进行，新的 OOM 记录等待保存；断电前可能丢失。';;
   capture_failed|queue_write_failed|pending_save_failed|rollback_failed)echo 'OOM 持久保存失败，请保留现场并检查存储。';;
   pending)echo '新的 OOM 记录等待保存；断电前可能丢失。';;
   *invalid)echo '已有 OOM 记录损坏，未覆盖，请保留现场。';;
  esac;;
 *)exit 2;;
esac
