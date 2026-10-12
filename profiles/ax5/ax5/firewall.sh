#!/bin/sh
C=/data/ShellCrash
R=/tmp/ShellCrash
# Only this adapter's chains and hooks are modified.
stop_rules() {
 while iptables -t nat -D PREROUTING -i br-lan -p tcp -j SC_AX5_IN 2>/dev/null; do :; done
 while iptables -t nat -D OUTPUT -p tcp -j SC_AX5_OUT 2>/dev/null; do :; done
 while iptables -t nat -D PREROUTING -i br-lan -p udp --dport 53 -j REDIRECT --to-ports 1053 2>/dev/null; do :; done
 while iptables -t nat -D PREROUTING -i br-lan -p tcp --dport 53 -j REDIRECT --to-ports 1053 2>/dev/null; do :; done
 for proto in tcp udp; do while iptables -t nat -D OUTPUT -p "$proto" --dport 53 -j SC_AX5_DNS 2>/dev/null; do :; done; done
 for tablechain in SC_AX5_IN SC_AX5_OUT SC_AX5_DNS; do iptables -t nat -F "$tablechain" 2>/dev/null; iptables -t nat -X "$tablechain" 2>/dev/null; done
 for tablechain in 'OUTPUT -o lo' 'PREROUTING -i lo'; do
  iptables -t raw -D $tablechain -m comment --comment SC_AX5_CONNTRACK -j ACCEPT 2>/dev/null
 done
 iptables -D FORWARD -d 198.18.0.0/15 -p udp -m comment --comment SC_AX5_FAKE_UDP -j REJECT 2>/dev/null
}
stop_rules
[ "${1:-start}" = start ] || exit 0
[ -s "$R/core.pid" ] && kill -0 "$(cat "$R/core.pid")" 2>/dev/null || exit 0
trap 'rc=$?; if [ "$rc" -ne 0 ]; then stop_rules; fi' EXIT
set -e
iptables -t raw -I OUTPUT 1 -o lo -m comment --comment SC_AX5_CONNTRACK -j ACCEPT || exit 1
iptables -t raw -I PREROUTING 1 -i lo -m comment --comment SC_AX5_CONNTRACK -j ACCEPT || exit 1
iptables -t nat -N SC_AX5_IN
iptables -t nat -N SC_AX5_OUT
iptables -t nat -N SC_AX5_DNS
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
iptables -t nat -I PREROUTING 1 -i br-lan -p udp --dport 53 -j REDIRECT --to-ports 1053
iptables -I FORWARD 1 -d 198.18.0.0/15 -p udp -m comment --comment SC_AX5_FAKE_UDP -j REJECT
# DNS interception is removed on stop. Original dnsmasq configuration stays intact.
exit 0
