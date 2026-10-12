#!/bin/sh
# Sourced by existing sampler/status/actions; no resident monitor.
resource_limits(){
 rh_warning_mb=16; rh_protect_mb=12; rh_cleanup_mb=0; rh_limits_valid=1
 rh_limits_file="${C:-/etc/storage/ShellCrash}/configs/memory.conf"
 if [ -f "$rh_limits_file" ]; then
  rh_limits_valid=0
  rh_limits=$(awk -F= '
   /^[[:space:]]*($|#)/{next}
   $1=="warning_mb" && $2~/^(0|[1-9][0-9]?)$/ && NF==2 {w=$2; nw++; next}
   $1=="protect_mb" && $2~/^(0|[1-9][0-9]?)$/ && NF==2 {p=$2; np++; next}
   $1=="cleanup_mb" && $2~/^(0|[1-9][0-9]?)$/ && NF==2 {c=$2; nc++; next}
   {bad=1}
   END{if(!bad && nw==1 && np==1 && nc==1 && p>=12 && p<w && w<=64 && (c==0 || (c>=w && c<=96)))print w,p,c}' "$rh_limits_file")
  if [ -n "$rh_limits" ]; then set -- $rh_limits; rh_warning_mb=$1; rh_protect_mb=$2; rh_cleanup_mb=$3; rh_limits_valid=1; fi
 fi
}
resource_read(){
 resource_limits
 set -- $(awk '/^MemFree:/{f=$2}/^MemAvailable:/{a=$2}/^AnonPages:/{n=$2}/^Shmem:/{h=$2}/^Slab:/{s=$2}/^SUnreclaim:/{u=$2}END{print f+0,a+0,n+0,h+0,s+0,u+0}' /proc/meminfo)
 rh_free=$1; rh_available=$2; rh_anon=$3; rh_shmem=$4; rh_slab=$5; rh_unreclaim=$6
 rh_pressure=normal
 [ "$rh_available" -ge "$((rh_warning_mb*1024))" ] || rh_pressure=warning
 [ "$rh_available" -ge "$((rh_protect_mb*1024))" ] || rh_pressure=protect
 set -- $(awk '/^TCP:/{for(i=1;i<=NF;i++){if($i=="mem")t=$(i+1)*4;if($i=="alloc")a=$(i+1)}}/^UDP:/{for(i=1;i<=NF;i++)if($i=="mem")u=$(i+1)*4}END{print t+0,u+0,a+0}' /proc/net/sockstat)
 rh_tcp=$1; rh_udp=$2; rh_sockets=$3
 rh_conn=$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null); case "$rh_conn" in ''|*[!0-9]*) rh_conn=0;; esac
}
resource_trim_logs(){
 for rh_file in "$D/events.log" /tmp/ShellCrash/core.log /tmp/ShellCrash/ShellCrash.log "$D/fetch-error" "$D/worker.log"; do
  [ -f "$rh_file" ] && [ ! -L "$rh_file" ] || continue
  rh_size=$(stat -c %s "$rh_file" 2>/dev/null)
  case "$rh_size" in ''|*[!0-9]*) continue;; esac
  if [ "$rh_size" -gt 65536 ]; then
   tail -c 32768 "$rh_file" > "$D/cleanup-tail" || continue
   cat "$D/cleanup-tail" > "$rh_file" && rh_trimmed=$((rh_trimmed+1)) && rh_bytes=$((rh_bytes+rh_size-32768))
   rm -f "$D/cleanup-tail"
  fi
 done
}
resource_remove(){
 [ -f "$1" ] && [ ! -L "$1" ] || return 0
 rh_size=$(stat -c %s "$1" 2>/dev/null)
 case "$rh_size" in ''|*[!0-9]*) return 0;; esac
 if rm -f "$1"; then rh_removed=$((rh_removed+1)); rh_bytes=$((rh_bytes+rh_size)); fi
}
resource_cleanup()(
 rh_acquired=0; rh_cleanup_owned=0
 trap 'if [ "$rh_cleanup_owned" = 1 ]; then rm -f "$D/cleanup.lock/owner" "$D/cleanup-tail"; rmdir "$D/cleanup.lock" 2>/dev/null; fi; if [ "$rh_acquired" = 1 ]; then rm -f "$D/operation.lock/owner"; rmdir "$D/operation.lock" 2>/dev/null; fi' EXIT
 # Own the same lock as updates, so a job cannot start midway through cleanup.
 if mkdir "$D/operation.lock" 2>/dev/null; then
  rh_acquired=1; echo $$ > "$D/operation.lock/owner"
 else
  rh_owner=$(cat "$D/operation.lock/owner" 2>/dev/null)
  [ "$rh_owner" = "$$" ] || return 1
 fi
 [ ! -d /tmp/shellcrash-bootstrap.lock ] || return 1
 # Shared lock prevents the sampler and manual button trimming the same file.
 if ! mkdir "$D/cleanup.lock" 2>/dev/null; then
  rh_lock_owner=$(cat "$D/cleanup.lock/owner" 2>/dev/null)
  [ -z "$rh_lock_owner" ] || { kill -0 "$rh_lock_owner" 2>/dev/null && return 1; }
  rm -f "$D/cleanup.lock/owner"; rmdir "$D/cleanup.lock" 2>/dev/null || return 1
  mkdir "$D/cleanup.lock" 2>/dev/null || return 1
 fi
 rh_cleanup_owned=1; echo $$ > "$D/cleanup.lock/owner"
 resource_read; rh_before=$rh_available
 rh_bytes=0; rh_removed=0; rh_trimmed=0
 # Manual cleanup bypasses the configurable trigger; logs are always bounded.
 if [ "${rh_manual:-0}" = 1 ] || [ "$rh_cleanup_mb" = 0 ] || [ "$rh_available" -lt "$((rh_cleanup_mb*1024))" ]; then
  # Missing DNS configuration is not evidence that the old file is unused.
  if [ -f /etc/dnsmasq.conf ] && [ -f /etc/storage/dnsmasq/dnsmasq.conf ] && [ "$(/usr/sbin/nvram get ss_enable)" = 0 ] && ! grep -qE 'dnsmasq\.dom|gfwlist|conf-dir=|conf-file=' /etc/dnsmasq.conf /etc/storage/dnsmasq/dnsmasq.conf; then
   resource_remove /tmp/dnsmasq.dom/gfwlist_list.conf
  fi
  [ -z "$(pidof CrashCore)" ] || resource_remove /tmp/ShellCrash/CrashCore.tar.gz
 fi
 resource_trim_logs
 resource_read
 if [ "$rh_bytes" -gt 0 ] || [ "${rh_manual:-0}" = 1 ]; then
  printf '{"time":%s,"manual":%s,"before_kb":%s,"after_kb":%s,"file_bytes":%s,"removed":%s,"trimmed":%s}\n' "$(date +%s)" "${rh_manual:-0}" "$rh_before" "$rh_available" "$rh_bytes" "$rh_removed" "$rh_trimmed" > "$D/cleanup.next"
  mv "$D/cleanup.next" "$D/cleanup.json"
 fi
 return 0
)
resource_snapshot(){
 resource_read
 rh_zone=$(awk '/Node 0, zone/{z=$4}/pages free/{if(z=="DMA")d=$3*4;else if(z=="Normal")n=$3*4}END{print d+0 "," n+0}' /proc/zoneinfo)
 printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' "$now" "$up" "${pid:-0}" "${rss:-0}" "$rh_available" "$rh_anon" "$rh_shmem" "$rh_slab" "$rh_unreclaim" "$rh_tcp" "$rh_udp" "$rh_sockets" "$rh_conn" "$rh_zone" >> "$D/resources.csv"
 awk -F, -v min="$((up-86400))" 'NF==15 && $2>=min' "$D/resources.csv" | tail -1441 > "$D/resources.next"; mv "$D/resources.next" "$D/resources.csv"
 old_pressure=$(cat "$D/pressure" 2>/dev/null)
 if [ "$old_pressure" != "$rh_pressure" ]; then
  printf '%s pressure=%s available_kb=%s rss_kb=%s shmem_kb=%s slab_kb=%s tcp_kb=%s conntrack=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$rh_pressure" "$rh_available" "${rss:-0}" "$rh_shmem" "$rh_slab" "$rh_tcp" "$rh_conn" >> "$D/pressure.log"
  tail -100 "$D/pressure.log" > "$D/pressure.next"; mv "$D/pressure.next" "$D/pressure.log"
 fi
 printf '%s\n' "$rh_pressure" > "$D/pressure"
}
