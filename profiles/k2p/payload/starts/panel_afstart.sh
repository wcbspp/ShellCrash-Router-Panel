#!/bin/sh
[ -z "$(pidof CrashCore)" ] || rm -f /tmp/ShellCrash/CrashCore.tar.gz
rm -f /tmp/ShellCrash/traffic-mode /tmp/ShellCrash/traffic/base
# Ordinary UDP stays direct; reject UDP to virtual IPs to permit TCP fallback.
while iptables -D FORWARD -p udp -d 198.18.0.0/15 -j REJECT 2>/dev/null; do :; done
mode=$(sed -n 's/^dns_mod=//p' /etc/storage/ShellCrash/configs/ShellCrash.cfg | head -1)
[ "$mode" = mix ] || [ "$mode" = fake-ip ] || exit 0
iptables -I FORWARD -p udp -d 198.18.0.0/15 -j REJECT
