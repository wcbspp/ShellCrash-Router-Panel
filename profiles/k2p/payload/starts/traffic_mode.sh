#!/bin/sh
# Called under manage.sh's operation lock; touches only ShellCrash-owned chains.
traffic_mode_apply(){
 requested=$1
 traffic_error=mode_invalid
 case "$requested" in rule|direct|global) :;; *) return 1;;esac
 T=${SC_TRAFFIC_ROOT:-/tmp/ShellCrash/traffic}
 MODE_FILE=${SC_TRAFFIC_MODE_FILE:-/tmp/ShellCrash/traffic-mode}
 mkdir -p "$T" || return 1
 secret=$(sed -n 's/^secret=//p' "$C/configs/ShellCrash.cfg" | head -1)
 printf 'header = "Authorization: Bearer %s"\n' "$secret" > "$T/auth"
 traffic_api(){ curl --noproxy '*' -fsS --connect-timeout 1 --max-time 4 --config "$T/auth" "$@" "http://${PANEL_LAN_IP}:9999/configs" 2>> "$T/events.log"; }
 before=$(traffic_api | sed -n 's/.*"mode"[ ]*:[ ]*"\([A-Za-z]*\)".*/\1/p' | tr 'A-Z' 'a-z')
 case "$before" in rule|direct|global) :;; *) rm -f "$T/auth";return 1;;esac
 traffic_snapshot(){
  printf '*nat\n'
  for chain in shellcrash shellcrash_dns shellcrash_out shellcrash_dns_out;do
   if iptables -t nat -S "$chain" > "$T/chain" 2>/dev/null;then
    printf ':%s - [0:0]\n' "$chain"
    sed -n '/^-A /p' "$T/chain"
   fi
  done
  printf 'COMMIT\n'
  printf '*mangle\n'
  for chain in shellcrash_mark shellcrash_mark_out;do
   if iptables -t mangle -S "$chain" > "$T/chain" 2>/dev/null;then
    printf ':%s - [0:0]\n' "$chain";sed -n '/^-A /p' "$T/chain"
   fi
  done
  printf 'COMMIT\n'
 }
 iptables -t nat -S shellcrash >/dev/null 2>&1 && iptables -t nat -S shellcrash_dns >/dev/null 2>&1 || { rm -f "$T/auth";return 1; }
 traffic_snapshot > "$T/before"
 if [ ! -s "$T/base" ];then cp "$T/before" "$T/base" || return 1;fi
 previous=$(cat "$MODE_FILE" 2>/dev/null);case "$previous" in rule|direct|global) :;; *) previous=rule;;esac
 traffic_unhook(){ while iptables -t nat -D PREROUTING -p tcp -m comment --comment SC_PANEL_GLOBAL -j shellcrash 2>/dev/null;do :;done; }
 traffic_restore(){ sed 's/^-F \([^ ]*\)$/:\1 - [0:0]/' "$1" | iptables-restore --noflush; }
 traffic_fw(){
  traffic_unhook
  traffic_restore "$T/base" || return 1
  if [ "$1" = rule ];then
   . "$C/starts/policy_capture.sh"
   policy_capture_apply || return 1
  elif [ "$1" = direct ];then
   for chain in shellcrash shellcrash_dns shellcrash_out shellcrash_dns_out;do
    iptables -t nat -S "$chain" >/dev/null 2>&1 || continue
    iptables -t nat -I "$chain" 1 -m comment --comment SC_PANEL_DIRECT -j RETURN || return 1
   done
   for chain in shellcrash_mark shellcrash_mark_out;do
    iptables -t mangle -S "$chain" >/dev/null 2>&1 || continue
    iptables -t mangle -I "$chain" 1 -m comment --comment SC_PANEL_DIRECT -j RETURN || return 1
   done
  elif [ "$1" = global ];then
   for chain in shellcrash shellcrash_out;do
    while iptables -t nat -D "$chain" -m set --match-set cn_ip dst -j RETURN 2>/dev/null;do :;done
   done
   for chain in shellcrash_mark shellcrash_mark_out;do
    iptables -t mangle -S "$chain" >/dev/null 2>&1 || continue
    while iptables -t mangle -D "$chain" -m set --match-set cn_ip dst -j RETURN 2>/dev/null;do :;done
   done
   iptables -t nat -I PREROUTING 1 -p tcp -m comment --comment SC_PANEL_GLOBAL -j shellcrash || return 1
  fi
 }
 if traffic_api -X PATCH -H 'Content-Type: application/json' -d "{\"mode\":\"$requested\"}" >/dev/null && traffic_fw "$requested";then
  actual=$(traffic_api | sed -n 's/.*"mode"[ ]*:[ ]*"\([A-Za-z]*\)".*/\1/p' | tr 'A-Z' 'a-z')
  if [ "$actual" != "$requested" ];then
   actual=$(traffic_api | sed -n 's/.*"mode"[ ]*:[ ]*"\([A-Za-z]*\)".*/\1/p' | tr 'A-Z' 'a-z')
  fi
  if [ "$actual" = "$requested" ];then
   printf '%s\n' "$requested" > "$MODE_FILE"
   [ "$requested" != rule ] || rm -f "$T/base"
   # Drop cached DNS answers; clients may still need to reconnect/refresh their own cache.
   dns_pids=$(pidof dnsmasq);[ -z "$dns_pids" ] || kill -HUP $dns_pids
   rm -f "$T/auth" "$T/before" "$T/chain"
   return 0
  fi
 fi
 printf "%s mode=%s before=%s verification failed; reverting\n" "$(date +%s)" "$requested" "$before" >> "$T/events.log"
 traffic_unhook
 traffic_restore "$T/before"
 [ "$previous" != global ] || iptables -t nat -I PREROUTING 1 -p tcp -m comment --comment SC_PANEL_GLOBAL -j shellcrash
 traffic_api -X PATCH -H 'Content-Type: application/json' -d "{\"mode\":\"$before\"}" >/dev/null
 rm -f "$T/auth" "$T/before" "$T/chain"
 return 1
}
