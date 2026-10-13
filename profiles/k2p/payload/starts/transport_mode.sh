#!/bin/sh
# Uses the installed ShellCrash setter and start path, under the panel job lock.
transport_configured(){
 case "$(sed -n 's/^redir_mod=//p' "$C/configs/ShellCrash.cfg" | head -1)" in
  '混合模式') echo mixed;; ''|'Redir模式') echo redir;; *) echo unsupported;;
 esac
}
transport_available(){
 [ -c /dev/net/tun ] && grep -qx MARK /proc/net/ip_tables_targets &&
 [ "$(sed -n 's/^firewall_area=//p' "$C/configs/ShellCrash.cfg" | head -1)" = 1 ]
}
transport_ready(){
 if [ "$1" = mixed ];then
  ip link show utun >/dev/null 2>&1 && iptables -t mangle -S shellcrash_mark 2>/dev/null | grep -q 'MARK'
 else ! ip link show utun >/dev/null 2>&1;fi
}
transport_wait_ready(){
 tries=0
 while [ "$tries" -lt 35 ];do
  [ "$(cat /tmp/ShellCrash/transport-runtime 2>/dev/null)" != "$1" ] || { transport_ready "$1" && return 0; }
  sleep 1;tries=$((tries+1))
 done
 return 1
}
transport_apply(){
 CRASHDIR=$C;export CRASHDIR
 requested=$1;case "$requested" in redir|mixed) :;; *) fail '接管方式无效';return 1;;esac
 previous=$(transport_configured)
 [ "$previous" != unsupported ] || { fail '当前工具接管方式尚未适配，请先在 ShellCrash 切回 Redir';return 1; }
 [ "$requested" != mixed ] || transport_available || { fail '混合模式需要 TUN、MARK 和仅局域网接管';return 1; }
 if [ "$requested" = mixed ] && [ "$previous" = redir ];then
  route_table=$(sed -n 's/^table=//p' "$C/configs/ShellCrash.cfg" | head -1);route_table=${route_table:-100}
  case "$route_table" in ''|*[!0-9]*) fail 'ShellCrash 路由表参数无效';return 1;;esac
  if ip link show utun >/dev/null 2>&1 || [ -n "$(ip route list table "$route_table" 2>/dev/null)" ] || ip rule list | grep -Eq "lookup $route_table$";then
   fail 'TUN 或路由表已被占用，未修改现有接管';return 1
  fi
 fi
 if [ "$previous" = "$requested" ] && { [ -z "$(pidof CrashCore)" ] || transport_ready "$requested"; };then phase done '接管方式未变化，无需重启';return 0;fi
 . "$C/starts/resource_health.sh";resource_read
 [ "$rh_pressure" != protect ] || { fail memory_protected;return 1; }
 . "$C/libs/set_config.sh"
 running_before=false;[ -z "$(pidof CrashCore)" ] || running_before=true
 old_traffic=$(cat /tmp/ShellCrash/traffic-mode 2>/dev/null);case "$old_traffic" in rule|direct|global) :;; *) old_traffic=rule;;esac
 if [ "$running_before" = true ];then
  configuration_core_prepare || return 1
  # Capability check never creates a TUN device or changes current routes.
  if [ "$requested" = mixed ];then
   printf '%s\n' '{"inbounds":[{"type":"tun","tag":"tun-check","interface_name":"utun-check","address":["28.0.0.1/30"],"auto_route":false,"stack":"system"}],"outbounds":[{"type":"direct"}]}' > "$D/tun-check.json"
   "$configuration_core_source" check -c "$D/tun-check.json" >> "$D/worker.log" 2>&1 || { rm -f "$D/tun-check.json";fail '当前内核不支持混合接管，原设置保留';return 1; }
   rm -f "$D/tun-check.json"
  fi
  # Save selectors before restart; don't change the user's chosen node.
  . "$C/libs/get_config.sh";. "$C/libs/web_save.sh"
  get_save(){ curl --noproxy '*' -fsS --connect-timeout 1 --max-time 5 -H "Authorization: Bearer ${secret}" "$1"; }
  web_save
 fi
 [ "$requested" != mixed ] && setting='Redir模式' || setting='混合模式'
 setconfig redir_mod "$setting"
 if [ "$(transport_configured)" = "$requested" ] && save_safe;then
  if [ "$running_before" = false ];then phase done '接管方式已保存，下次启动生效';return 0;fi
  if stop_core && start_core && transport_wait_ready "$requested";then
   . "$C/starts/traffic_mode.sh"
   if traffic_mode_apply "$old_traffic";then phase done '接管方式已生效，原流量模式已保留';return 0;fi
  fi
 fi
 [ "$previous" != mixed ] && setting='Redir模式' || setting='混合模式'
 setconfig redir_mod "$setting";save_safe
 if [ "$running_before" = true ];then
  if stop_core && start_core && transport_wait_ready "$previous";then . "$C/starts/traffic_mode.sh";traffic_mode_apply "$old_traffic";fi
 fi
 fail '新接管方式未通过验证，已尝试恢复原设置';return 1
}
