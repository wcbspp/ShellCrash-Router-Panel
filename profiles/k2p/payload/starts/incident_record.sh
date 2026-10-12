#!/bin/sh
# Padavan panel adaptation; configurable LAN address.
PANEL_HOME=${CRASHDIR:-/etc/storage/ShellCrash}
. "$PANEL_HOME/starts/panel_env.sh" || exit 1
# Called only on a confirmed missing core, never for manual stop/start.
D=/tmp/sc-admin
umask 077
mkdir -p "$D"
act=$1; pid=$2
case "$pid" in ''|*[!0-9]*) pid=0;; esac
if [ "$act" = begin ]; then
 echo "$pid" > "$D/incident-outage-pid"
 detected=$(date '+%Y-%m-%d %H:%M:%S'); when=$detected; reason=unknown; rss=0
 row=$(grep -E "Killed process $pid \\(CrashCore\\)" /tmp/syslog.log 2>/dev/null | tail -1)
 dmesg | tail -130 > "$D/incident-evidence.pending"
 fingerprint=$(grep "Killed process" "$D/incident-evidence.pending" | tail -1 | sha256sum | awk '{print $1}')
 previous=$(cat "$D/incident-last-oom" 2>/dev/null)
 if [ "$fingerprint" != "$previous" ] && { printf '%s\n' "$row" | grep -qE "Killed process $pid \(CrashCore\)" || grep -qE "Killed process $pid \\(CrashCore\\)" "$D/incident-evidence.pending"; }; then
  printf '%s\n' "$fingerprint" > "$D/incident-last-oom"
  reason=oom
  if [ -n "$row" ]; then when="$(date '+%Y')-$(date '+%m-%d') $(printf '%s\n' "$row" | awk '{print $3}')"; else row=$(grep -E "Killed process $pid \\(CrashCore\\)" "$D/incident-evidence.pending" | tail -1); fi
  rss=$(printf '%s\n' "$row" | awk '{a=0;b=0;for(i=1;i<=NF;i++){if($i ~ /^anon-rss:/){v=$i;gsub(/[^0-9]/,"",v);a=v+0}if($i ~ /^file-rss:/){v=$i;gsub(/[^0-9]/,"",v);b=v+0}}print a+b}')
 fi
 free=$(awk -F, -v pid="$pid" '$3==pid {v=$5}END{print v+0}' "$D/memory.csv" 2>/dev/null); [ -n "$free" ] || free=0
 printf '%s|%s|%s|%s|%s|%s|pending\n' "$when" "$detected" "$reason" "$pid" "$rss" "$free" >> "$D/incidents.log"
 tail -100 "$D/incidents.log" > "$D/incidents.next"; mv "$D/incidents.next" "$D/incidents.log"
 count=$(cat "$D/recoveries" 2>/dev/null); case "$count" in ''|*[!0-9]*) count=0;; esac
 { printf '\n=== PRE-EXIT RESOURCE SAMPLES ===\n'; tail -12 "$D/resources.csv" 2>/dev/null; printf '\n=== RECOVERY-TIME SNAPSHOT ===\n'; cat /proc/meminfo; cat /proc/net/sockstat; cat /proc/buddyinfo; } >> "$D/incident-evidence.pending"
 mv "$D/incident-evidence.pending" "$D/incident-evidence-$count.log"
 # Retain 8 bounded kernel snapshots; not written to flash.
 [ "$count" -le 8 ] || rm -f "$D/incident-evidence-$((count-8)).log"
elif [ "$act" = finish ]; then
 result=failed; tries=0
 secret=$(sed -n 's/^secret=//p' /etc/storage/ShellCrash/configs/ShellCrash.cfg | head -1)
 while [ "$tries" -lt 30 ]; do
  if [ -n "$(pidof CrashCore)" ] && curl -fsS --connect-timeout 1 --max-time 2 -H "Authorization: Bearer $secret" http://${PANEL_LAN_IP}:9999/version >/dev/null 2>&1; then result=restored; break; fi
  sleep 1; tries=$((tries+1))
 done
 [ "$result" != restored ] || rm -f "$D/incident-outage-pid" "$D/recovery-due" "$D/recovery-attempts"
 awk -F'|' -v OFS='|' -v pid="$pid" -v result="$result" '{if($4==pid && $7!="restored")$7=result;print}' "$D/incidents.log" > "$D/incidents.next"
 mv "$D/incidents.next" "$D/incidents.log"
fi
