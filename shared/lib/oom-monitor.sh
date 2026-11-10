#!/bin/sh
# Called by the existing minute sampler; bounded process/connection evidence.
set -u
C=${CRASHDIR:?};D=${SC_OOM_RUNTIME:?};umask 077
available=$(awk '/^MemAvailable:/{print $2;exit}' /proc/meminfo)
case "$available" in ''|*[!0-9]*)exit 1;;esac
[ "$available" -ge 12288 ] || { echo low_memory > "$D/oom-remote-status";exit 1; }
if ! mkdir "$D/oom-monitor.lock" 2>/dev/null;then
 owner=$(cat "$D/oom-monitor.lock/owner" 2>/dev/null)
 case "$owner" in ''|*[!0-9]*)exit 0;;esac
 kill -0 "$owner" 2>/dev/null && exit 0
 rm -f "$D/oom-monitor.lock/owner";rmdir "$D/oom-monitor.lock" 2>/dev/null || exit 0
 mkdir "$D/oom-monitor.lock" 2>/dev/null || exit 0
fi
trap 'rm -f "$D/oom-monitor.lock/owner";rmdir "$D/oom-monitor.lock" 2>/dev/null' EXIT
# No command lines, credentials or payloads are collected.
echo $$ > "$D/oom-monitor.lock/owner"
case "$C" in /data/ShellCrash) helper="$C/ax5/oom-remote.sh";record="$C/configs/oom-records.json";;*)helper="$C/starts/oom-remote.sh";record="$C/configs/oom-history.b64";;esac
{
 printf 'time=%s uptime=' "$(date +%s)";cat /proc/uptime
 printf 'boot=';cat /proc/sys/kernel/random/boot_id
 echo '=== MEMORY ===';cat /proc/meminfo
 echo '=== LOAD / RECLAIM ===';cat /proc/loadavg;grep -E '^(pgmajfault|allocstall|pgscan|pgsteal|compact|oom_kill)' /proc/vmstat 2>/dev/null
 echo '=== SOCKETS / BUDDY ===';cat /proc/net/sockstat /proc/buddyinfo 2>/dev/null
 echo '=== PROCESSES name pid rss_kb swap_kb ==='
 awk 'function emit(){if(p)print r+0,n,p,w+0} FNR==1{emit();n="";p=0;r=0;w=0}/^Name:/{n=$2}/^Pid:/{p=$2}/^VmRSS:/{r=$2}/^VmSwap:/{w=$2}END{emit()}' /proc/[0-9]*/status 2>/dev/null | sort -nr | head -20 | awk '{print $2,$3,$1,$4}'
 echo '=== CONNTRACK ===';cat /proc/sys/net/netfilter/nf_conntrack_count /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null
 echo '=== CONNECTION SOURCES (first 4096 entries, top 32; distinct destinations) ==='
 ct=/proc/net/nf_conntrack;[ -r "$ct" ] || ct=/proc/net/ip_conntrack
 [ -r "$ct" ] || echo connection_sources_unavailable
 head -4096 "$ct" 2>/dev/null | awk '{s="";d="";for(i=1;i<=NF;i++){if(s==""&&$i~/^src=/)s=$i;if(d==""&&$i~/^dst=/)d=$i}if(s!=""){a[s]++;if(!seen[s,d]++)u[s]++}}END{for(s in a)print a[s],s,"distinct_dst="u[s]}' | sort -nr | head -32
 echo '=== SOURCE / PROTOCOL / DESTINATION PORT / TCP STATE (first 4096 entries, top 32) ==='
 head -4096 "$ct" 2>/dev/null | awk '{s="";p="";for(i=1;i<=NF;i++){if(s==""&&$i~/^src=/)s=$i;if(p==""&&$i~/^dport=/)p=$i}if(s!="")a[s" "$3" "p" "($3=="tcp"?$6:"-")]++}END{for(k in a)print a[k],k}' | sort -nr | head -32
} | head -c 8192 > "$D/oom-monitor-current.new"
mv "$D/oom-monitor-current.new" "$D/oom-monitor-current"
if [ "$C" = /data/ShellCrash ];then
 lua "$C/ax5/state.lua" scan-oom >/dev/null 2>&1 || { echo capture_failed > "$D/oom-remote-status";exit 1; }
else
 CRASHDIR="$C" SC_OOM_RUNTIME="$D" sh "$C/starts/oom-store.sh" scan >/dev/null 2>&1 || { echo capture_failed > "$D/oom-remote-status";exit 1; }
 CRASHDIR="$C" SC_OOM_RUNTIME="$D" sh "$C/starts/oom-store.sh" persist >/dev/null 2>&1 || :
fi
[ -f "$C/configs/oom-remote-enabled" ] || exit 0
if [ -s "$record" ];then
 CRASHDIR="$C" SC_OOM_RUNTIME="$D" sh "$helper" "$record" >/dev/null 2>&1 || { echo incident_upload_pending > "$D/oom-remote-status";exit 1; }
fi
if CRASHDIR="$C" SC_OOM_RUNTIME="$D" sh "$helper" "$D/oom-monitor-current" >/dev/null 2>&1;then echo saved > "$D/oom-remote-status";else echo upload_pending > "$D/oom-remote-status";fi
