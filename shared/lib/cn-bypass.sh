#!/bin/sh
# Called on demand/startup; no resident service. cb_safe is a profile callback.
cb_enabled(){ [ "$(cat "$C/configs/cn-bypass" 2>/dev/null)" = 1 ]; }
cb_remove(){
 for table in nat mangle;do
  case "$table" in nat) chains=$CB_NAT;;mangle)chains=$CB_MANGLE;;esac
  for chain in $chains;do
   while iptables -t "$table" -D "$chain" -m set --match-set "$CB_SET" dst -m comment --comment SC_PANEL_CN_BYPASS -j RETURN 2>/dev/null;do :;done
  done
 done
}
cb_rules(){
 if ! mkdir "$D/cn-rule.lock" 2>/dev/null;then
  owner=$(cat "$D/cn-rule.lock/owner" 2>/dev/null)
  [ -n "$owner" ] && kill -0 "$owner" 2>/dev/null && return 1
  rm -f "$D/cn-rule.lock/owner";rmdir "$D/cn-rule.lock" 2>/dev/null || return 1
  mkdir "$D/cn-rule.lock" 2>/dev/null || return 1
 fi
 echo $$ > "$D/cn-rule.lock/owner"
 cb_rules_inner "$1";rc=$?
 rm -f "$D/cn-rule.lock/owner";rmdir "$D/cn-rule.lock";return "$rc"
}
cb_rules_inner(){
 cb_remove
 if type cb_legacy_remove >/dev/null 2>&1;then cb_legacy_remove;fi
 reason=disabled;active=false
 if cb_enabled;then
  reason=$1
  if [ "$1" = rule ];then
   reason=$(cb_safe)
   if [ "$reason" = ready ];then
    if cb_prepare;then
     installed=0
     for table in nat mangle;do
      case "$table" in nat) chains=$CB_NAT;;mangle)chains=$CB_MANGLE;;esac
      for chain in $chains;do
       iptables -t "$table" -S "$chain" > "$D/cn-chain" 2>/dev/null || continue
       slot=$(awk '/^-A /{n++;if($0!~/ --dport 53( |$)/ && $0~/ -j (REDIRECT|MARK|TPROXY)( |$)/){print n;exit}}' "$D/cn-chain")
       [ -n "$slot" ] || continue
       if ! iptables -t "$table" -I "$chain" "$slot" -m set --match-set "$CB_SET" dst -m comment --comment SC_PANEL_CN_BYPASS -j RETURN;then
        cb_remove;active=false;reason=failed;break 2
       fi
       installed=$((installed+1))
      done
     done
     if [ "$reason" = ready ] && [ "$installed" -gt 0 ];then active=true;elif [ "$reason" = ready ];then reason=stopped;fi
    else reason=unavailable;fi
   fi
  fi
 fi
 rm -f "$D/cn-chain"
 printf '%s\n' "$1:$reason" > "$D/cn-applied"
 printf '%s\n' "$1:$(cb_safe)" > "$D/cn-checked"
 date +%s > "$D/cn-check-time"
 printf '{"enabled":%s,"available":%s,"active":%s,"reason":"%s"}\n' "$(cb_enabled && echo true || echo false)" "$( [ "$(cb_safe)" = ready ] && echo true || echo false)" "$active" "$reason" > "$D/cn-state.json"
 if ! cb_enabled && [ "$CB_SET" = sc_panel_cn ];then ipset destroy "$CB_SET" 2>/dev/null;rm -f "$D/cn-set-hash";fi
 [ "$reason" != failed ]
}
cb_prepare(){
 hash=$(md5sum "$C/configs/cn_ip.txt"|awk '{print $1}')
 [ "$hash" = "$(cat "$D/cn-set-hash" 2>/dev/null)" ] && ipset list "$CB_SET" >/dev/null 2>&1 && return 0
 [ "$(wc -c < "$C/configs/cn_ip.txt")" -le 262144 ] || return 1
 awk -f "$CB_VALIDATOR" "$C/configs/cn_ip.txt" > "$D/cn-valid" || { rm -f "$D/cn-valid";return 1; }
 available=$(awk '/^MemAvailable:/{print $2;exit}' /proc/meminfo)
 [ "${available:-0}" -ge "$(((CB_PROTECT+2)*1024))" ] || { rm -f "$D/cn-valid";return 1; }
 ipset destroy sc_cn_stage 2>/dev/null || true
 { echo 'create sc_cn_stage hash:net family inet hashsize 8192 maxelem 10240';awk '{print "add sc_cn_stage " $0}' "$D/cn-valid"; } > "$D/cn-restore"
 if ipset restore < "$D/cn-restore" && ipset create "$CB_SET" hash:net family inet hashsize 8192 maxelem 10240 -exist && ipset swap sc_cn_stage "$CB_SET";then
  ipset destroy sc_cn_stage;printf '%s\n' "$hash" > "$D/cn-set-hash";rc=0
 else ipset destroy sc_cn_stage 2>/dev/null;rc=1;fi
 rm -f "$D/cn-valid" "$D/cn-restore";return "$rc"
}
