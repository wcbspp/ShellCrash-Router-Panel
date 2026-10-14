#!/bin/sh
[ -z "$(pidof CrashCore)" ] || rm -f /tmp/ShellCrash/CrashCore.tar.gz
rm -f /tmp/ShellCrash/traffic-mode /tmp/ShellCrash/traffic/base
transport=$(sed -n 's/^redir_mod=//p' /etc/storage/ShellCrash/configs/ShellCrash.cfg | head -1)
if [ "$transport" = '混合模式' ];then
 if ip link show utun >/dev/null 2>&1 && iptables -t mangle -S shellcrash_mark 2>/dev/null | grep -q MARK;then
  echo mixed > /tmp/ShellCrash/transport-runtime
 else
  echo unknown > /tmp/ShellCrash/transport-runtime
  logger -t ShellCrash 'Mixed interception not ready; check TUN and marking chain'
 fi
else echo redir > /tmp/ShellCrash/transport-runtime;fi
C=/etc/storage/ShellCrash
sh "$C/starts/subscription-quota.sh" k2p auto || :
. "$C/starts/policy_capture.sh"
policy_capture_apply || logger -t ShellCrash 'Domain routing capture failed; check owned country-IP bypass'
# Ordinary UDP stays direct; reject UDP to virtual IPs to permit TCP fallback.
while iptables -D FORWARD -p udp -d 198.18.0.0/15 -j REJECT 2>/dev/null; do :; done
[ "$transport" != '混合模式' ] || exit 0
mode=$(sed -n 's/^dns_mod=//p' /etc/storage/ShellCrash/configs/ShellCrash.cfg | head -1)
[ "$mode" = mix ] || [ "$mode" = fake-ip ] || exit 0
iptables -I FORWARD -p udp -d 198.18.0.0/15 -j REJECT
