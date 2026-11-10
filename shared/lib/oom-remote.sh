#!/bin/sh
# Upload a bounded, already-persisted record without touching backup indexes.
set -u
C=${CRASHDIR:?}
D=${SC_OOM_RUNTIME:?}
record=${1:?}
[ -f "$C/configs/oom-remote-enabled" ] || exit 0
[ -f "$record" ] && [ ! -L "$record" ] || exit 1
[ "$(wc -c < "$record")" -le 65536 ] || exit 1
available=$(awk '/^MemAvailable:/{print $2;exit}' /proc/meminfo)
case "$available" in ''|*[!0-9]*) exit 1;; esac
case "$C" in
 /data/ShellCrash)
  remote="$C/ax5/remote.sh"
  protect=$(lua -e 'local m=dofile("/data/ShellCrash/ax5/common.lua");print(m.limits().protect_mb)') || exit 1;;
 *)
  remote="$C/starts/remote.sh"
  . "$C/starts/resource_health.sh" || exit 1
  resource_limits
  protect=$rh_protect_mb;;
esac
case "$protect" in ''|*[!0-9]*) exit 1;; esac
[ "$protect" -ge 12 ] && [ "$protect" -le 64 ] || exit 1
[ "$available" -ge "$((protect*1024))" ] || exit 1
. "$remote" || exit 1
[ "$(remote_transport)" = webdav ] && remote_ready || exit 1
marker="$D/oom-remote-last-$(printf %s "$record" | remote_hash)"
snapshot="$D/oom-upload.$$"
umask 077
(set -C; : > "$snapshot") 2>/dev/null || exit 1
trap 'rm -f "$snapshot"' EXIT
cp "$record" "$snapshot" || exit 1
[ "$(wc -c < "$snapshot")" -le 65536 ] || exit 1
hash=$(remote_hash < "$snapshot")
[ "$hash" != "$(cat "$marker" 2>/dev/null)" ] || exit 0
printf '%s' "$hash" | grep -Eq '^[a-f0-9]{64}$' || exit 1
dir="$(dav_base)/oom"
dav_mkdir "$dir" || exit 1
dav_store_file "$snapshot" "$dir/$hash.txt" || exit 1
printf '%s\n' "$hash" > "$marker"
printf '%s\n' "$(date +%s)" > "$D/oom-remote-success"
printf '%s\n' "$hash"
