#!/bin/sh
# On-demand MAC access control. No daemon and no core/config rewrite.
ac_init(){
 C=${C:-${CRASHDIR:-/data/ShellCrash}}
 case "$C" in /etc/storage/*) AC_LAN=${PANEL_LAN_IF:-br0};;*) AC_LAN=br-lan;;esac
 AC_FILE="$C/configs/proxy-access"
 AC_RUN=${SC_ACCESS_RUNTIME:-/tmp/ShellCrash/proxy-access}
 mkdir -p "$AC_RUN"
}
ac_validate(){
 [ -f "$1" ] && [ "$(wc -c < "$1")" -le 1200 ] || return 1
 awk 'NR==1 {enabled=$0;if($0!="0"&&$0!="1")exit 1;next}
 {v=tolower($0);if(index(v,":")){if(length(v)!=17||split(v,a,":")!=6)exit 1;
 for(i=1;i<=6;i++)if(a[i]!~/^[0-9a-f][0-9a-f]$/)exit 1;
 if(a[1]~/[13579bdf]$/||v=="00:00:00:00:00:00")exit 1
 }else{if(split(v,a,".")!=4)exit 1;for(i=1;i<=4;i++)if(a[i]!~/^[0-9]+$/||length(a[i])>3||a[i]>255||(length(a[i])>1&&substr(a[i],1,1)=="0"))exit 1;
 if(a[1]==0||a[1]==127||a[1]>=224)exit 1}
 if(seen[v]++)exit 1}
 END{if(NR<1||NR>65||(enabled=="1"&&NR<2))exit 1}' "$1"
}
ac_clean_bank(){
 bank=$1
 for cmd in iptables ip6tables;do
  which "$cmd" >/dev/null 2>&1 || continue
  for spec in 'nat N' 'mangle M' 'filter I' 'filter F';do
   set -- $spec;table=$1;chain="SC_ACL_${bank}_$2"
   # Delete only exact jumps to this module's private chains.
   if ! "$cmd" -t "$table" -S > "$AC_RUN/cleanup.rules" 2>/dev/null;then
    [ "$table" != filter ] || return 1
    continue
   fi
   rm -f "$AC_RUN/cleanup.failed"
   awk -v c="$chain" '$1=="-A"&&$(NF-1)=="-j"&&$NF==c {$1="-D";print}' "$AC_RUN/cleanup.rules" |
   while read -r rule;do "$cmd" -t "$table" $rule 2>/dev/null || : > "$AC_RUN/cleanup.failed";done
   [ ! -f "$AC_RUN/cleanup.failed" ] || return 1
   "$cmd" -t "$table" -F "$chain" 2>/dev/null || :
   "$cmd" -t "$table" -X "$chain" 2>/dev/null || :
  done
 done
 return 0
}
ac_make_chain(){
 cmd=$1;table=$2;chain=$3;denial=$4
 "$cmd" -t "$table" -N "$chain" || return 1
 [ "$table" != filter ] || "$cmd" -t "$table" -A "$chain" -i lo -j RETURN || return 1
 while IFS= read -r mac;do
  case "$mac" in
   *:*) "$cmd" -t "$table" -A "$chain" -m mac --mac-source "$mac" -j RETURN || return 1;;
   *) [ "$cmd" != iptables ] || "$cmd" -t "$table" -A "$chain" -s "$mac" -j RETURN || return 1;;
  esac
 done < "$AC_RUN/macs"
 "$cmd" -t "$table" -A "$chain" -j "$denial"
}
ac_apply_family(){
 cmd=$1;bank=$2
 # INPUT covers explicit HTTP/SOCKS and redirected connections, including
 # already-established sockets. The management/API port is not restricted.
 ac_make_chain "$cmd" filter "SC_ACL_${bank}_I" REJECT || return 1
 for proto in tcp udp;do
  "$cmd" -t filter -I INPUT 1 -p "$proto" -m multiport --dports 7890,7892,7893,1053 -j "SC_ACL_${bank}_I" || return 1
 done
 ac_make_chain "$cmd" filter "SC_ACL_${bank}_F" REJECT || return 1
 "$cmd" -t filter -I FORWARD 1 -o utun -j "SC_ACL_${bank}_F" || return 1
 # ACCEPT here ends only nat/mangle processing; ordinary routing continues.
 # Only adapter-owned LAN interception chains call these gates.
 for spec in 'nat N' 'mangle M';do
  set -- $spec;table=$1;chain="SC_ACL_${bank}_$2";created=0
  case "$table" in nat) parents='SC_AX5_IN SC_AX5_LDNS shellcrash shellcrash_dns shellcrashv6 shellcrashv6_dns';;*)parents='SC_AX5_UDP shellcrash_mark shellcrashv6_mark';;esac
  for parent in $parents;do
   "$cmd" -t "$table" -S "$parent" >/dev/null 2>&1 || continue
   if [ "$created" = 0 ];then ac_make_chain "$cmd" "$table" "$chain" ACCEPT || return 1;created=1;fi
   "$cmd" -t "$table" -I "$parent" 1 -j "$chain" || return 1
  done
 done
}
ac_apply_inner(){
 ac_init
 file=${1:-$AC_FILE}
 [ -f "$file" ] || { ac_clean_bank A && ac_clean_bank B && ac_unlock || { ac_lockdown;return 1; };rm -f "$AC_RUN/active";return 0; }
 ac_validate "$file" || return 1
 if [ "$(head -n 1 "$file")" = 0 ];then ac_clean_bank A && ac_clean_bank B && ac_unlock || { ac_lockdown;return 1; };rm -f "$AC_RUN/active";return 0;fi
 previous=$(cat "$AC_RUN/active" 2>/dev/null)
 case "$previous" in A) next=B;;*) next=A;;esac
 ac_clean_bank "$next" || return 1
 tail -n +2 "$file" | tr A-F a-f > "$AC_RUN/macs"
 if ! ac_apply_family iptables "$next";then ac_clean_bank "$next";return 1;fi
 if which ip6tables >/dev/null 2>&1;then
  if ! ac_apply_family ip6tables "$next";then ac_clean_bank "$next";return 1;fi
 elif grep -q . /proc/net/if_inet6 2>/dev/null;then
  ac_clean_bank "$next";return 1
 fi
 # All replacement hooks are installed before removing the old policy.
 case "$previous" in A|B) if ! ac_clean_bank "$previous";then ac_lockdown;return 1;fi;;esac
 printf '%s\n' "$next" > "$AC_RUN/active"
 ac_unlock
}
ac_unlock(){
 for cmd in iptables ip6tables;do
  which "$cmd" >/dev/null 2>&1 || continue
  while "$cmd" -D INPUT -p tcp -m multiport --dports 7890,7892,7893,1053 -j SC_ACL_LOCK 2>/dev/null;do :;done
  while "$cmd" -D INPUT -p udp -m multiport --dports 7890,7892,7893,1053 -j SC_ACL_LOCK 2>/dev/null;do :;done
  while "$cmd" -D FORWARD -o utun -j SC_ACL_LOCK 2>/dev/null;do :;done
  "$cmd" -F SC_ACL_LOCK 2>/dev/null || :;"$cmd" -X SC_ACL_LOCK 2>/dev/null || :
 done
 rm -f "$AC_RUN/error"
}
ac_lockdown(){
 # If a saved enabled policy cannot be recreated after boot, block proxy
 # ingress rather than silently making the proxy available to everyone.
 if [ "$(head -n 1 "$AC_FILE" 2>/dev/null)" = 1 ];then
  for cmd in iptables ip6tables;do
   which "$cmd" >/dev/null 2>&1 || continue
   "$cmd" -N SC_ACL_LOCK 2>/dev/null || :
   "$cmd" -F SC_ACL_LOCK
   "$cmd" -A SC_ACL_LOCK -i lo -j RETURN
   "$cmd" -A SC_ACL_LOCK -j REJECT
   for proto in tcp udp;do "$cmd" -I INPUT 1 -p "$proto" -m multiport --dports 7890,7892,7893,1053 -j SC_ACL_LOCK;done
   "$cmd" -I FORWARD 1 -o utun -j SC_ACL_LOCK
  done
 fi
 printf 'firewall_apply_failed\n' > "$AC_RUN/error"
 return 1
}
ac_native_snapshot(){
 [ -f "$C/starts/reapply.sh" ] || return 0
 mkdir -p "$AC_RUN/native-before" || return 1
 for name in ShellCrash.cfg mac ip_filter;do
  rm -f "$AC_RUN/native-before/$name" "$AC_RUN/native-before/$name.absent"
  if [ -f "$C/configs/$name" ];then cp "$C/configs/$name" "$AC_RUN/native-before/$name" || return 1;else : > "$AC_RUN/native-before/$name.absent";fi
 done
 [ ! -f "$C/starts/proxy-access-native.sh" ] || CRASHDIR="$C" sh "$C/starts/proxy-access-native.sh" snapshot "$AC_RUN"
}
ac_native_restore(){
 [ -f "$C/starts/reapply.sh" ] || return 0
 for name in ShellCrash.cfg mac ip_filter;do
  if [ -f "$AC_RUN/native-before/$name.absent" ];then rm -f "$C/configs/$name";else cp "$AC_RUN/native-before/$name" "$C/configs/$name" || return 1;fi
 done
 CRASHDIR="$C" sh "$C/starts/proxy-access-native.sh" restore "$AC_RUN"
}
ac_native_sync(){
 [ -f "$C/starts/reapply.sh" ] || return 0
 ac_validate "$AC_FILE" || return 1
 : > "$C/configs/mac";: > "$C/configs/ip_filter"
 mode=黑名单
 if [ "$(head -n 1 "$AC_FILE")" = 1 ];then
  mode=白名单
  tail -n +2 "$AC_FILE" | awk 'index($0,":"){print}' > "$C/configs/mac"
  tail -n +2 "$AC_FILE" | awk '!index($0,":"){print}' > "$C/configs/ip_filter"
 fi
 CRASHDIR=$C;. "$C/libs/set_config.sh";setconfig macfilter_type "$mode" || return 1
 # Only official LAN chain bodies are replaced, retaining routing state.
 CRASHDIR="$C" sh "$C/starts/proxy-access-native.sh" apply "$AC_RUN"
}
ac_enforce_inner(){ ac_apply_inner && return 0;ac_lockdown;return 1; }
ac_commit_inner(){
 ac_init
 input=$1
 ac_validate "$input" || return 2
 if [ "$(head -n 1 "$input")" = 1 ] && [ -f "$C/starts/reapply.sh" ] && [ -r /proc/meminfo ];then
  available=$(awk '/^MemAvailable:/{a=$2}/^MemFree:/{f=$2}END{print a?a:f}' /proc/meminfo)
  reserve=16384
  if [ -f "$C/starts/resource_health.sh" ];then . "$C/starts/resource_health.sh";resource_limits;reserve=$(((rh_protect_mb+4)*1024));fi
  [ "$available" -ge "$reserve" ] || { printf 'memory_low\n' > "$AC_RUN/error";return 4; }
 fi
 helper="$C/starts/access-devices.lua";[ -f "$helper" ] || helper="$C/ax5/access-devices.lua"
 if [ -f "$helper" ];then lua "$helper" resolve "$C" "$input" "$AC_RUN/candidate" || return 2;else cp "$input" "$AC_RUN/candidate" || return 1;fi
 ac_validate "$AC_RUN/candidate" || return 2
 ac_native_snapshot || return 1
 if [ -f "$AC_FILE" ];then cp "$AC_FILE" "$AC_RUN/previous" || return 1;else printf '0\n' > "$AC_RUN/previous";fi
 ac_apply_inner "$AC_RUN/candidate" || return 1
 if cp "$AC_RUN/candidate" "$AC_FILE.new" && mv "$AC_FILE.new" "$AC_FILE" && ac_native_sync && ac_apply_inner "$AC_FILE" && { ! type save_safe >/dev/null 2>&1 || save_safe; };then
  rm -f "$AC_RUN/previous" "$AC_RUN/candidate";return 0
 fi
 cp "$AC_RUN/previous" "$AC_FILE" || { ac_enforce_inner;return 3; }
 ac_native_restore || { ac_enforce_inner;return 3; }
 ac_apply_inner "$AC_FILE" || { ac_enforce_inner;return 3; }
 if type save_safe >/dev/null 2>&1;then save_safe || return 3;fi
 return 1
}

# A separate bounded lock also covers boot/firewall hooks outside web jobs.
ac_locked()(
 umask 077
 ac_init
 tries=0
 until mkdir "$AC_RUN/lock" 2>/dev/null;do
  owner=$(cat "$AC_RUN/lock/owner" 2>/dev/null)
  if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null;then
   rm -f "$AC_RUN/lock/owner";rmdir "$AC_RUN/lock" 2>/dev/null || :
  fi
  tries=$((tries+1));[ "$tries" -lt 12 ] || return 1
  sleep 1
 done
 echo $$ > "$AC_RUN/lock/owner"
 trap 'rm -f "$AC_RUN/lock/owner";rmdir "$AC_RUN/lock" 2>/dev/null' EXIT
 "$@"
)
ac_apply(){ ac_locked ac_apply_inner "$@"; }
ac_commit(){ ac_locked ac_commit_inner "$@"; }
ac_enforce(){ ac_locked ac_enforce_inner; }
