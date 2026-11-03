#!/bin/sh
# Shared with backup-app; never steal a recently created or live lock.
storage_lock=${SC_STORAGE_LOCK:-/tmp/shellcrash-storage-save.lock}
storage_lock_acquire(){
 if ! mkdir "$storage_lock" 2>/dev/null;then
  # shortcut: interrupted stale-lock cleanup needs a reboot; replace when kernel locks are available.
  mkdir "$storage_lock.reap" 2>/dev/null || return 1
  owner=$(cat "$storage_lock/owner" 2>/dev/null)
  age=$(stat -c %Y "$storage_lock" 2>/dev/null);now=$(date +%s)
  case "$age:$now" in *[!0-9:]*|:*|*:)rmdir "$storage_lock.reap";return 1;;esac
  if [ "$((now-age))" -lt 60 ];then rmdir "$storage_lock.reap";return 1;fi
  case "$owner" in ''|*[!0-9]*) :;; *)kill -0 "$owner" 2>/dev/null && { rmdir "$storage_lock.reap";return 1; };;esac
  # A killed parent may leave its flash-writing child alive.
  if pidof mtd_write >/dev/null 2>&1;then rmdir "$storage_lock.reap";return 1;fi
  rm -f "$storage_lock/owner"
  rmdir "$storage_lock" 2>/dev/null || { rmdir "$storage_lock.reap";return 1; }
  rmdir "$storage_lock.reap" || return 1
  mkdir "$storage_lock" 2>/dev/null || return 1
 fi
 echo $$ > "$storage_lock/owner"
}
storage_lock_release(){ rm -f "$storage_lock/owner";rmdir "$storage_lock" 2>/dev/null || :; }
