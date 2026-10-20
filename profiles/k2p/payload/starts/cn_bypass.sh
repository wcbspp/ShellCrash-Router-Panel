#!/bin/sh
CB_NAT='shellcrash shellcrash_out';CB_MANGLE='shellcrash_mark shellcrash_mark_out';CB_SET=cn_ip
. "$C/starts/cn-bypass-lib.sh"
. "$C/starts/resource_health.sh";resource_limits
CB_PROTECT=$rh_protect_mb;CB_VALIDATOR="$C/starts/rules_validate.awk"
cb_safe(){
 key=v2$(md5sum "$C/jsons/config.json" "$C/configs/policy.tsv" 2>/dev/null | awk '{printf "%s|",$1}')$(sed -n 's/^dns_mod=/dns:/p' "$C/configs/ShellCrash.cfg")
 if [ "$key" = "$(head -1 "$D/cn-eligible" 2>/dev/null)" ];then sed -n '2p' "$D/cn-eligible";return;fi
 result=ready;warning=ready
 scan_state=$(awk -v report=1 -f "$C/starts/cn_bypass_check.awk" "$C/jsons/config.json") || scan_state=invalid
 case "$scan_state" in ready|rules) :;;*)scan_state=invalid;;esac
 if grep -qx 'dns_mod=fake-ip' "$C/configs/ShellCrash.cfg";then result=fakeip
 elif [ "$scan_state" = invalid ];then result=invalid
 fi
 if ! awk -F '\t' 'NF&&$3!="direct"{bad=1}END{exit bad}' "$C/configs/policy.tsv";then warning=policy
 elif [ "$scan_state" != ready ];then warning=rules
 fi
 printf '%s\n%s\n%s\n' "$key" "$result" "$warning" > "$D/cn-eligible.$$";mv "$D/cn-eligible.$$" "$D/cn-eligible";printf '%s\n' "$result"
}
cb_warning(){ sed -n '3p' "$D/cn-eligible"; }

cb_mode(){
 secret=$(sed -n 's/^secret=//p' "$C/configs/ShellCrash.cfg"|head -1)
 printf 'header = "Authorization: Bearer %s"\n' "$secret" > "$D/cn-auth.$$"
 mode=$(curl --noproxy '*' -fsS --connect-timeout 1 --max-time 2 --config "$D/cn-auth.$$" "http://${PANEL_LAN_IP}:9999/configs" 2>/dev/null|sed -n 's/.*"mode" *: *"\([A-Za-z]*\)".*/\1/p'|tr 'A-Z' 'a-z')
 rm -f "$D/cn-auth.$$";case "$mode" in rule|direct|global)echo "$mode";;*)echo unknown;;esac
}
cb_legacy_remove(){
 for table in nat mangle;do
  case "$table" in nat) chains=$CB_NAT;;mangle)chains=$CB_MANGLE;;esac
  for chain in $chains;do while iptables -t "$table" -D "$chain" -m set --match-set cn_ip dst -j RETURN 2>/dev/null;do :;done;done
 done
}
cb_refresh(){
 [ ! -d "$D/operation.lock" ] || return 0
 if cb_enabled;then
  mode=$(cb_mode);safe=$(cb_safe)
  # A status read can precede ShellCrash's firewall setup during boot.
  # A stopped-chain result must be rechecked after those chains appear.
  if [ "$mode:$safe" != "$(cat "$D/cn-checked" 2>/dev/null)" ] || [ "$(cat "$D/cn-applied" 2>/dev/null)" = 'rule:stopped' ];then cb_rules "$mode";fi
 fi
}
cb_save(){
 value=$1;case "$value" in 0|1) :;;*)return 1;;esac
 if [ "$value" = 1 ];then
  [ "$(cb_safe)" = ready ] || { fail '当前规则或 DNS 与国内 IP 绕过冲突，设置未变';return 1; }
  [ -n "$(pidof CrashCore)" ] || { fail '内核未运行';return 1; }
 fi
 mode=$(cb_mode);[ "$value" = 0 ] || [ "$mode" != unknown ] || { fail '无法确认内核模式，设置未变';return 1; }
 old_cfg=$(sed -n 's/^cn_ip_route=//p' "$C/configs/ShellCrash.cfg"|head -1)
 CRASHDIR=$C;export CRASHDIR
 . "$C/libs/set_config.sh"
 [ "$value" = 1 ] && setting=ON || setting=OFF
 setconfig cn_ip_route "$setting"
 old=$(cat "$C/configs/cn-bypass" 2>/dev/null);printf '%s\n' "$value" > "$C/configs/cn-bypass"
 if cb_rules "$mode" && { [ "$value" = 0 ] || [ "$mode" != rule ] || grep -q '"active":true' "$D/cn-state.json"; };then phase saving '已应用，正在保存到闪存；内核继续运行';if save_safe;then phase done '国内 IP 绕过设置已保存；只影响新连接';return 0;fi;fi
 if [ -n "$old" ];then printf '%s\n' "$old" > "$C/configs/cn-bypass";else rm -f "$C/configs/cn-bypass";fi
 if [ -n "$old_cfg" ];then setconfig cn_ip_route "$old_cfg";else sed -i '/^cn_ip_route=/d' "$C/configs/ShellCrash.cfg";fi
 cb_rules "$mode";save_safe;fail '国内 IP 绕过应用失败，已尝试恢复原设置';return 1
}
