#!/bin/sh
# One small sample from the existing once-per-minute cron; RAM only.
C=/etc/storage/ShellCrash
D=/tmp/sc-admin
umask 077
mkdir -p "$D"
if ! mkdir "$D/memory-sample.lock" 2>/dev/null; then
 owner=$(cat "$D/memory-sample.lock/owner" 2>/dev/null)
 [ -z "$owner" ] || { kill -0 "$owner" 2>/dev/null && exit 0; }
 rm -f "$D/memory-sample.lock/owner"; rmdir "$D/memory-sample.lock" 2>/dev/null || exit 0
 mkdir "$D/memory-sample.lock" 2>/dev/null || exit 0
fi
echo $$ > "$D/memory-sample.lock/owner"
trap 'rm -f "$D/memory-sample.lock/owner"; rmdir "$D/memory-sample.lock" 2>/dev/null' EXIT
up=$(cut -d. -f1 /proc/uptime)
last=$(tail -1 "$D/memory.csv" 2>/dev/null | cut -d, -f2)
case "$last" in ''|*[!0-9]*) last=0;; esac
[ "$last" -eq 0 ] || [ "$((up-last))" -ge 50 ] || exit 0
. "$C/starts/resource_health.sh"
resource_cleanup
now=$(date +%s)
pid=$(pidof CrashCore | awk '{print $1}')
rss=0
[ -z "$pid" ] || rss=$(awk '/^VmRSS:/{print $2}' "/proc/$pid/status" 2>/dev/null)
free=$(awk '/^MemFree:/{print $2}' /proc/meminfo)
count=$(cat "$D/recoveries" 2>/dev/null)
case "$count" in ''|*[!0-9]*) count=0;; esac
printf '%s,%s,%s,%s,%s,%s\n' "$now" "$up" "${pid:-0}" "${rss:-0}" "${free:-0}" "$count" >> "$D/memory.csv"
# Uptime keeps the window stable during NTP corrections; bounded to 1441 rows.
awk -F, -v min="$((up-86400))" 'NF==6 && $2>=min' "$D/memory.csv" | tail -1441 > "$D/memory.next"
mv "$D/memory.next" "$D/memory.csv"

resource_snapshot
