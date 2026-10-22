#!/bin/sh
# Generate bounded LAN chains through the unmodified official functions.
# Never stop the service, destroy ipsets or rebuild policy routes.
set -e
PATH=/usr/sbin:/usr/bin:/sbin:/bin;export PATH
C=${CRASHDIR:-/etc/storage/ShellCrash};D=/tmp/sc-admin
W=$2;[ -n "$W" ] && [ -d "$W" ] || exit 2
umask 077
IPT=$(which iptables);IPTR=$(which iptables-restore)
export CRASHDIR="$C"
. "$C/starts/panel_env.sh"
snapshot(){
 destination=$1
 : > "$destination"
 for table in nat mangle;do
  printf '*%s\n' "$table" >> "$destination"
  case "$table" in nat) chains='shellcrash shellcrash_dns shellcrash_out shellcrash_dns_out';;*)chains='shellcrash_mark shellcrash_mark_out';;esac
  for chain in $chains;do
   "$IPT" -t "$table" -S "$chain" > "$W/current.chain" 2>/dev/null || continue
   printf ':%s - [0:0]\n' "$chain" >> "$destination"
   sed -n '/SC_ACL_/d;/^-A /p' "$W/current.chain" >> "$destination"
  done
  printf 'COMMIT\n' >> "$destination"
 done
}
if [ "$1" = snapshot ];then
 snapshot "$W/native-rules.before"
 if [ -f /tmp/ShellCrash/traffic/base ];then cp /tmp/ShellCrash/traffic/base "$W/traffic-base.before";rm -f "$W/traffic-base.absent";else rm -f "$W/traffic-base.before";: > "$W/traffic-base.absent";fi
 exit 0
fi
if [ "$1" = restore ];then
 [ ! -s "$W/native-rules.before" ] || "$IPTR" --noflush < "$W/native-rules.before"
 if [ -f "$W/traffic-base.absent" ];then rm -f /tmp/ShellCrash/traffic/base;elif [ -f "$W/traffic-base.before" ];then mkdir -p /tmp/ShellCrash/traffic;cp "$W/traffic-base.before" /tmp/ShellCrash/traffic/base;fi
 exit 0
fi
case "$1" in plan|apply) :;;*)exit 2;;esac
[ -n "$(pidof CrashCore)" ] || exit 0
"$IPT" -t nat -S shellcrash >/dev/null
"$IPT" -t nat -S shellcrash_dns >/dev/null
. "$C/libs/get_config.sh" || :
. "$C/libs/check_cmd.sh"
if [ "$macfilter_type" = 白名单 ] && [ ! -s "$C/configs/mac" ] && [ ! -s "$C/configs/ip_filter" ];then exit 2;fi
. "$C/starts/fw_getlanip.sh";getlanip || :
[ -n "$host_ipv4" ] || exit 1
case "$redir_mod" in Redir模式|混合模式) :;;*)echo unsupported_interception_mode >&2;exit 2;;esac
: > "$W/generated.nat.def";: > "$W/generated.nat.rules"
: > "$W/generated.mangle.def";: > "$W/generated.mangle.rules"
rm -f "$W/generator.error"
# Capture official operations, not a shell reconstruction of its policy.
iptables(){
 if [ "${CAPTURING:-0}" != 1 ];then "$IPT" "$@";return $?;fi
 if [ "${1:-}" = -h ];then "$IPT" -h;return;fi
 [ "${1:-}" != -w ] || shift
 [ "${1:-}" = -t ] || { : > "$W/generator.error";return 1; }
 g_table=$2;shift 2;g_op=$1;g_chain=$2;shift 2
 case "$g_op:$g_chain" in -I:PREROUTING) return 0;;esac
 case "$g_table:$g_chain" in nat:shellcrash|nat:shellcrash_dns|mangle:shellcrash_mark) :;;*) : > "$W/generator.error";return 1;;esac
 case "$g_op" in
  -N) printf ':%s - [0:0]\n' "$g_chain" >> "$W/generated.$g_table.def";;
  -A) printf '%s\n' "-A $g_chain $*" >> "$W/generated.$g_table.rules";;
  *) : > "$W/generator.error";return 1;;
 esac
}
CAPTURING=1
. "$C/starts/fw_iptables.sh"
ports='';[ "$common_ports" != ON ] || ports="-m multiport --dports $multiport"
JUMP="REDIRECT --to-ports $redir_port"
# Official functions may end on an intentionally false shell conditional.
start_ipt_route iptables nat PREROUTING shellcrash tcp || :
start_ipt_dns iptables PREROUTING shellcrash_dns || :
if "$IPT" -t mangle -S shellcrash_mark >/dev/null 2>&1;then
 [ "$redir_mod" = 混合模式 ] || exit 2
 JUMP="MARK --set-mark $fwmark"
 start_ipt_route iptables mangle PREROUTING shellcrash_mark udp || :
fi
[ ! -f "$W/generator.error" ] || exit 1
CAPTURING=0
[ -s "$W/generated.nat.rules" ] || exit 1
: > "$W/native-generated"
for table in nat mangle;do
 printf '*%s\n' "$table" >> "$W/native-generated"
 cat "$W/generated.$table.def" "$W/generated.$table.rules" >> "$W/native-generated"
 printf 'COMMIT\n' >> "$W/native-generated"
done
[ "$1" != plan ] || exit 0
. "$C/starts/cn_bypass.sh"
actual_mode=$(cb_mode)
case "$actual_mode" in rule|direct|global) :;;*)exit 1;;esac
# Commit only chain bodies. Existing hooks, routes and ipsets stay intact.
"$IPTR" --noflush < "$W/native-generated"
snapshot "$W/full-new-base"
mkdir -p /tmp/ShellCrash/traffic
if [ -s "$W/traffic-base.before" ];then
 # Replace the three LAN sections of the previous RULE base, retaining the
 # router OUTPUT baseline even while the current mode is direct/global.
 awk '
 FNR==NR {if(/^\*/)t=$0;if($1=="-A"&&($2=="shellcrash"||$2=="shellcrash_dns"||$2=="shellcrash_mark"))r[t]=r[t]$0"\n";next}
 /^\*/{t=$0}
 $1=="-A"&&($2=="shellcrash"||$2=="shellcrash_dns"||$2=="shellcrash_mark"){next}
 /^COMMIT/{printf "%s",r[t]}
 {print}' "$W/native-generated" "$W/traffic-base.before" > /tmp/ShellCrash/traffic/base
else cp "$W/full-new-base" /tmp/ShellCrash/traffic/base;fi
. "$C/starts/traffic_mode.sh"
# Reuse mode/policy handling without recursively taking the access lock.
if SC_ACCESS_REBUILD=1 traffic_mode_apply "$actual_mode";then :;else exit 1;fi
