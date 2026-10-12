#!/bin/sh
# AX5 Mixbox adapter: preserve /opt/var/lib/zerotier-one and existing memberships.
. /etc/mixbox/bin/base
eval "$(mbdb export zerotier)"
ZTO=/opt/bin/zerotier-one
ZTC=/opt/bin/zerotier-cli
HOME_ZT=/opt/var/lib/zerotier-one
LOG=/etc/mixbox/var/log/zerotier-one.log
status() {
 local info nets text
 info=$($ZTC info 2>/dev/null)
 if [ -n "$(pidof zerotier-one)" ] && [ -n "$info" ]; then
  nets=$($ZTC listnetworks 2>/dev/null | awk -v n="$networkid" '$3==n {for(i=4;i<=NF;i++) if($i=="OK"||$i=="ACCESS_DENIED"||$i=="REQUESTING_CONFIGURATION"||$i=="NOT_FOUND"||$i=="PORT_ERROR") {printf "%s · %s",$3,$i;break}}')
  case "$nets" in
   *ACCESS_DENIED*) text="网络未授权 · $networkid（进程在线）|1";;
   *OK*) text="网络已连接 · $networkid|1";;
   *) text="进程在线 · ${nets:-网络正在协商}|1";;
  esac
 else text="未运行（查看 zerotier-one.log）|0"; fi
 mbdb set "zerotier.main.status=$text" >/dev/null
}
stop() {
 local p i
 for p in $(pidof zerotier-one); do kill "$p" 2>/dev/null; done
 i=0
 while [ -n "$(pidof zerotier-one)" ] && [ "$i" -lt 10 ]; do sleep 1; i=$((i+1)); done
 for p in $(pidof zerotier-one); do kill -9 "$p" 2>/dev/null; done
 if [ "$enable" = 0 ]; then cru d zerotier; mbdb del entware.app.zerotier >/dev/null; fi
 status
}
start() {
 local i info result
 if [ -n "$(pidof zerotier-one)" ]; then status; return 0; fi
 if [ ! -x "$ZTO" ]; then logsh "【ZeroTier】" "程序不存在，请先安装 Entware ZeroTier"; return 1; fi
 if [ -z "$networkid" ] || [ "${#networkid}" -ne 16 ] || printf '%s' "$networkid" | grep -q '[^0-9a-fA-F]'; then
  logsh "【ZeroTier】" "网络 ID 无效，未修改现有身份"; return 1
 fi
 mkdir -p /etc/mixbox/var/log
 # Bound the log before opening it; do not truncate while the daemon writes.
 [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 65536 ] && tail -c 32768 "$LOG" > "$LOG.new" && mv "$LOG.new" "$LOG"
 "$ZTO" -d "$HOME_ZT" </dev/null >>"$LOG" 2>&1 || return 1
 i=0; info=''
 while [ "$i" -lt 8 ]; do
  info=$($ZTC info 2>/dev/null); [ -n "$info" ] && break
  sleep 1; i=$((i+1))
 done
 if [ -z "$info" ]; then status; logsh "【ZeroTier】" "启动失败，请查看 zerotier-one.log"; return 1; fi
 i=0
 while ! "$ZTC" join "$networkid" >/dev/null 2>&1; do
  i=$((i+1)); if [ "$i" -ge 10 ]; then status; logsh "【ZeroTier】" "加入网络请求失败"; return 1; fi
  sleep 1
 done
 # The daemon must survive the old startup-crash window before reporting success.
 sleep 15
 if [ -z "$(pidof zerotier-one)" ] || ! "$ZTC" info >/dev/null 2>&1; then
  status; logsh "【ZeroTier】" "启动后进程退出，请查看 zerotier-one.log"; return 1
 fi
 mbdb set 'entware.app.zerotier=1' >/dev/null
 cru a zerotier "0 6 * * * /etc/mixbox/apps/zerotier/scripts/zerotier.sh restart"
 status
 result=$($ZTC listnetworks 2>/dev/null | awk -v n="$networkid" '$3==n {for(i=4;i<=NF;i++) if($i=="OK"||$i=="ACCESS_DENIED"||$i=="REQUESTING_CONFIGURATION"||$i=="NOT_FOUND"||$i=="PORT_ERROR") {print $i;break}}')
 logsh "【ZeroTier】" "进程已运行，目标网络状态：${result:-正在协商}"
}
case "$1" in
 start) start;; stop) stop;; restart|reload) stop; start;; status) status;; *) exit 2;;
esac
