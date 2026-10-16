#!/bin/sh
# One bounded, authenticated, on-demand ICMP request. No daemon or flash writes.
set -eu
export LC_ALL=C
profile=${1:-};nonce=${2:-};key=${3:-}
[ "$#" = 3 ] || exit 1
[ "${#nonce}" = 8 ] || exit 1;case "$nonce" in *[!a-f0-9]*)exit 1;;esac
[ -n "$key" ] && [ "${#key}" -le 10 ] || exit 1
case "$key" in *[!0-9]*)exit 1;;esac
case "$profile" in
 ax5) C=${C:-/data/ShellCrash};D=${D:-/tmp/ShellCrash};helper=ax5;config=$C/configs/config.json;;
 k2p) C=${C:-/etc/storage/ShellCrash};D=${D:-/tmp/sc-admin};helper=starts;config=$C/jsons/config.json;;
 *)exit 1;;esac
umask 077;mkdir -p "$D"
# This lock is never stolen; bounded commands and the EXIT trap own its lifetime.
mkdir "$D/node-ping.lock" 2>/dev/null || exit 1
W=$D/node-ping.lock
child='';watcher=''
cleanup(){
 [ -z "$child" ] || { kill "$child" 2>/dev/null || :;wait "$child" 2>/dev/null || :; }
 [ -z "$watcher" ] || { kill "$watcher" 2>/dev/null || :;wait "$watcher" 2>/dev/null || :; }
 rm -rf "$W"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
bounded(){
 seconds=$1;shift
 "$@" & child=$!
 ( sleeper='';trap '[ -z "$sleeper" ] || kill "$sleeper" 2>/dev/null;exit 0' HUP INT TERM
   sleep "$seconds" & sleeper=$!;wait "$sleeper";kill "$child" 2>/dev/null || : ) & watcher=$!
 code=0;wait "$child" || code=$?
 kill "$watcher" 2>/dev/null || :;wait "$watcher" 2>/dev/null || :
 child='';watcher='';return "$code"
}
result(){ printf '{"id":"%s","node_key":"%s","state":"%s","delay":%s,"revision":"%s"}\n' "$nonce" "$key" "$1" "${2:-null}" "${revision:-}" > "$W/result";mv "$W/result" "$D/nodepingresult.json"; }
revision='';result working
[ ! -d "$D/operation.lock" ] || { result busy;exit 0; }
pidof CrashCore >/dev/null || { result stopped;exit 0; }
[ -f "$config" ] && [ ! -L "$config" ] || { result unsupported;exit 0; }
if [ "$profile" = ax5 ];then
 limits=$(lua -e "local M=dofile('$C/ax5/common.lua');local m=M.memory();print(m.MemAvailable or m.MemFree or 0,M.limits().protect_mb*1024+2048)")
 set -- $limits;available=$1;floor=$2
else
 . "$C/starts/resource_health.sh";resource_read
 available=$rh_available;floor=$((rh_protect_mb*1024+2048))
fi
[ "$available" -ge "$floor" ] || { result low_memory;exit 0; }
revision=$(md5sum "$config" | awk '{print $1}')
if [ "$profile" = ax5 ];then
 host=$(bounded 3 lua "$C/ax5/node-ping-target.lua" "$key") || { result unsupported;exit 0; }
else
 index=$D/node-ping-index.tsv
 saved=$(cat "$D/node-ping-index.revision" 2>/dev/null || :)
 if [ "$saved" != "$revision" ] || [ ! -f "$index" ] || [ -L "$index" ];then
  export NODE_PING_CATALOG=1
  bounded 8 awk -f "$C/starts/node-ping-target.awk" "$config" > "$W/index" || { result unsupported;exit 0; }
  unset NODE_PING_CATALOG
  [ "$(wc -c < "$W/index")" -le 65536 ] || { result unsupported;exit 0; }
  [ "$(md5sum "$config" | awk '{print $1}')" = "$revision" ] || { result changed;exit 0; }
  mv "$W/index" "$index";printf '%s' "$revision" > "$W/revision";mv "$W/revision" "$D/node-ping-index.revision"
 fi
 host=$(awk -F '\t' -v key="$key" '$1==key{n++;h=$2}END{if(n!=1||h=="-")exit 1;print h}' "$index") || { result unsupported;exit 0; }
fi
# Revalidate ASCII argument independently of the config reader; never eval it.
[ "${#host}" -le 253 ] || { result unsupported;exit 0; }
case "$host" in ''|[-.]*|*[!A-Za-z0-9.-]*)result unsupported;exit 0;;esac
# -W bounds replies; timeout also bounds DNS resolution and process lifetime.
bounded 4 ping -4 -c 1 -W 2 "$host" > "$W/ping" 2>&1 || :
current=$(md5sum "$config" | awk '{print $1}')
[ "$current" = "$revision" ] && [ ! -d "$D/operation.lock" ] || { result changed;exit 0; }
[ -f "$W/ping" ] && [ "$(wc -c < "$W/ping")" -le 2048 ] || { result no_reply;exit 0; }
ms=$(sed -n 's/.*time[=<]\([0-9][0-9.]*\)[[:space:]]*ms.*/\1/p' "$W/ping" | head -1)
if printf '%s' "$ms" | grep -Eq '^[0-9]+(\.[0-9]+)?$';then result done "$ms";else result no_reply;fi
