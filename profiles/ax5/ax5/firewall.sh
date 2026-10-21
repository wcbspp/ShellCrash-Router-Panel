#!/bin/sh
C=/data/ShellCrash
R=/tmp/ShellCrash
T=/data/ShellCrash-tool
mixed_configured(){ grep -qx 'redir_mod=混合模式' "$T/configs/ShellCrash.cfg" 2>/dev/null; }
# Opt-in per-device HTTPS fallback; no UDP proxy or resident updater.
stop_https_rules(){
 while iptables -D FORWARD -i br-lan -j SC_AX5_HTTPS 2>/dev/null;do :;done
 iptables -F SC_AX5_HTTPS 2>/dev/null || true
 iptables -X SC_AX5_HTTPS 2>/dev/null || true
}
https_rules(){
 stop_https_rules
 if [ "${1:-}" = check ] && [ "$(cat "$R/traffic-mode" 2>/dev/null)" = direct ];then return 0;fi
 mixed_configured && return 0
 [ -s "$R/core.pid" ] && kill -0 "$(cat "$R/core.pid")" 2>/dev/null || return 0
 clients=$(head -n 32 "$C/configs/https-tcp-clients.list" 2>/dev/null | tr -d '\r' | grep -Ei '^[0-9a-f]{2}(:[0-9a-f]{2}){5}$' | sort -u)
 [ -n "$clients" ] || return 0
 iptables -N SC_AX5_HTTPS || return 1
 for client in $clients;do
  if [ "$(head -n 1 "$C/configs/proxy-access" 2>/dev/null)" = 1 ];then
   tail -n +2 "$C/configs/proxy-access" | grep -Fqi -x "$client" || continue
  fi
  iptables -A SC_AX5_HTTPS -m mac --mac-source "$client" -p udp --dport 443 -j REJECT --reject-with icmp-port-unreachable || { stop_https_rules;return 1; }
 done
 iptables -I FORWARD 1 -i br-lan -j SC_AX5_HTTPS || { stop_https_rules;return 1; }
}
if [ "${1:-start}" = https ];then https_rules check;exit $?;fi
# Only this adapter's chains and hooks are modified.
stop_rules() {
 stop_https_rules
 while iptables -t mangle -D PREROUTING -i br-lan -p udp -j SC_AX5_UDP 2>/dev/null;do :;done
 iptables -t mangle -F SC_AX5_UDP 2>/dev/null || true
 iptables -t mangle -X SC_AX5_UDP 2>/dev/null || true
 while iptables -D FORWARD -i br-lan -o utun -p udp -m comment --comment SC_AX5_UDP -j ACCEPT 2>/dev/null;do :;done
 if [ -f "$R/udp-route-owned" ];then
  ip rule del pref 21313 fwmark 21313 table 21313 2>/dev/null || true
  ip route del default dev utun table 21313 2>/dev/null || true
  rm -f "$R/udp-route-owned"
 fi
 rm -f "$R/transport-mode"
 while iptables -t nat -D PREROUTING -i br-lan -p udp --dport 53 -j SC_AX5_LDNS 2>/dev/null;do :;done
 while iptables -t nat -D PREROUTING -i br-lan -p tcp -j SC_AX5_IN 2>/dev/null; do :; done
 while iptables -t nat -D OUTPUT -p tcp -j SC_AX5_OUT 2>/dev/null; do :; done
 while iptables -t nat -D PREROUTING -i br-lan -p udp --dport 53 -j REDIRECT --to-ports 1053 2>/dev/null; do :; done
 while iptables -t nat -D PREROUTING -i br-lan -p tcp --dport 53 -j REDIRECT --to-ports 1053 2>/dev/null; do :; done
 for proto in tcp udp; do while iptables -t nat -D OUTPUT -p "$proto" --dport 53 -j SC_AX5_DNS 2>/dev/null; do :; done; done
 for tablechain in SC_AX5_IN SC_AX5_OUT SC_AX5_DNS SC_AX5_LDNS; do iptables -t nat -F "$tablechain" 2>/dev/null; iptables -t nat -X "$tablechain" 2>/dev/null; done
 for tablechain in 'OUTPUT -o lo' 'PREROUTING -i lo'; do
  iptables -t raw -D $tablechain -m comment --comment SC_AX5_CONNTRACK -j ACCEPT 2>/dev/null
 done
 iptables -D FORWARD -d 198.18.0.0/15 -p udp -m comment --comment SC_AX5_FAKE_UDP -j REJECT 2>/dev/null
}
stop_rules
if [ "${1:-start}" != start ];then
 [ ! -f "$C/configs/cn-bypass" ] || SC_CN_FLOW_MODE=direct "$C/ax5/cn-bypass.sh" apply
 . "$C/ax5/proxy-access.sh";ac_enforce || exit 1
 exit 0
fi
[ -s "$R/core.pid" ] && kill -0 "$(cat "$R/core.pid")" 2>/dev/null || exit 0
trap 'rc=$?; if [ "$rc" -ne 0 ]; then stop_rules; fi' EXIT
set -e
iptables -t raw -I OUTPUT 1 -o lo -m comment --comment SC_AX5_CONNTRACK -j ACCEPT || exit 1
iptables -t raw -I PREROUTING 1 -i lo -m comment --comment SC_AX5_CONNTRACK -j ACCEPT || exit 1
iptables -t nat -N SC_AX5_IN
iptables -t nat -N SC_AX5_OUT
iptables -t nat -N SC_AX5_DNS
iptables -t nat -N SC_AX5_LDNS
iptables -t nat -A SC_AX5_LDNS -j REDIRECT --to-ports 1053
iptables -t nat -A SC_AX5_DNS -m mark --mark 0x5343 -j RETURN
for proto in tcp udp; do iptables -t nat -A SC_AX5_DNS -p "$proto" -j REDIRECT --to-ports 1053; done
iptables -t nat -A SC_AX5_IN -p tcp --dport 53 -j REDIRECT --to-ports 1053
for chain in SC_AX5_IN SC_AX5_OUT; do
 for net in 0.0.0.0/8 10.0.0.0/8 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16 224.0.0.0/4 240.0.0.0/4; do iptables -t nat -A "$chain" -d "$net" -j RETURN; done
done
# Marked core sockets bypass interception, preventing recursive proxy loops.
iptables -t nat -A SC_AX5_OUT -m mark --mark 0x5343 -j RETURN
for chain in SC_AX5_IN SC_AX5_OUT; do iptables -t nat -A "$chain" -p tcp -j REDIRECT --to-ports 7892; done
iptables -t nat -I OUTPUT 1 -p tcp -j SC_AX5_OUT
for proto in tcp udp; do iptables -t nat -I OUTPUT 1 -p "$proto" --dport 53 -j SC_AX5_DNS; done
iptables -t nat -I PREROUTING 1 -i br-lan -p tcp -j SC_AX5_IN
iptables -t nat -I PREROUTING 1 -i br-lan -p udp --dport 53 -j SC_AX5_LDNS
transport=redir
if mixed_configured;then
 # Same system-TUN path as ShellCrash mixed mode. Only LAN UDP enters TUN;
 # router-origin UDP remains native, protecting VPN/ZeroTier underlay sockets.
 ip link show utun >/dev/null 2>&1
 [ -z "$(ip route show table 21313 2>/dev/null)" ]
 [ -z "$(ip rule show | grep -E '^21313:|lookup 21313')" ]
 touch "$R/udp-route-owned"
 ip route add default dev utun table 21313
 ip rule add pref 21313 fwmark 21313 table 21313
 iptables -t mangle -N SC_AX5_UDP
 iptables -t mangle -A SC_AX5_UDP -m mark --mark 0x5343 -j RETURN
 iptables -t mangle -A SC_AX5_UDP -p udp --dport 53 -j RETURN
 for net in 0.0.0.0/8 10.0.0.0/8 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16 224.0.0.0/4 240.0.0.0/4;do
  iptables -t mangle -A SC_AX5_UDP -d "$net" -j RETURN
 done
 iptables -t mangle -A SC_AX5_UDP -j MARK --set-mark 21313
 iptables -t mangle -I PREROUTING 1 -i br-lan -p udp -j SC_AX5_UDP
 iptables -I FORWARD 1 -i br-lan -o utun -p udp -m comment --comment SC_AX5_UDP -j ACCEPT
 transport=mixed
else
 iptables -I FORWARD 1 -d 198.18.0.0/15 -p udp -m comment --comment SC_AX5_FAKE_UDP -j REJECT
fi
https_rules
printf '%s\n' "$transport" > "$R/transport-mode"
[ ! -f "$C/configs/cn-bypass" ] || "$C/ax5/cn-bypass.sh" apply
. "$C/ax5/proxy-access.sh"
ac_enforce || exit 1
# DNS interception is removed on stop. Original dnsmasq configuration stays intact.
exit 0
