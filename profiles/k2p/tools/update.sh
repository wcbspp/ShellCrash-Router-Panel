#!/bin/sh
# Update only this project's code. Configuration, core and startup hooks stay in place.
set -eu
base=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
C=/etc/storage/ShellCrash
D=/tmp/sc-admin
mode=${1:---check}
case "$mode" in --check|--apply) ;; *) echo '用法：sh tools/update.sh --check | --apply'; exit 2;; esac
[ "$(id -u)" = 0 ] || { echo '需要管理员权限'; exit 1; }
[ -f "$C/starts/panel_boot.sh" ] && [ -f "$C/configs/panel.conf" ] && [ -f "$C/padavan/manager.js" ] || { echo '不是本项目完整部署，未覆盖'; exit 1; }
[ -f "$C/version" ] && grep -q '^1\.9\.4' "$C/version" || { echo '当前工具版本未经本包验证，未更新'; exit 1; }
grep -qx 'crashcore=singbox' "$C/configs/ShellCrash.cfg" || { echo '仅支持现有 sing-box 部署'; exit 1; }
grep -q '#PadavanShellCrashPanel' /etc/storage/started_script.sh || { echo '启动入口不是本项目，未更新'; exit 1; }
[ ! -d "$D/operation.lock" ] && [ ! -d /tmp/shellcrash-bootstrap.lock ] || { echo '有配置或启动任务，稍后重试'; exit 1; }
available=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
[ "${available:-0}" -ge 14336 ] || { echo '可用内存不足 14 MB，未更新'; exit 1; }
[ "$mode" != --check ] || { echo '现有部署检查通过；未改配置、未重启'; exit 0; }
mkdir -p "$D"
mkdir "$D/operation.lock" 2>/dev/null || { echo '已有管理任务'; exit 1; }
echo $$ > "$D/operation.lock/owner"
work=''
committed=0;modified=0
rollback(){
 [ "$modified" = 1 ] || return 0
 for part in starts libs menus padavan ui;do rm -rf "$C/$part";done
 tar -xzf "$work/code-before.tar.gz" -C "$C" || { echo '源码回退失败，请保留电脑备份'; return 1; }
 "$C/starts/padavan_ui.sh" || return 1
 "$C/starts/save_storage.sh" || return 1
 echo '源码已回退；运行配置未覆盖'
}
finish(){
 rc=$?;trap - EXIT HUP INT TERM
 [ "$committed" = 1 ] || rollback || rc=1
 [ -z "$work" ] || rm -rf "$work";rm -f "$D/operation.lock/owner";rmdir "$D/operation.lock" 2>/dev/null || :
 exit "$rc"
}
trap finish EXIT
trap 'exit 1' HUP INT TERM
work=$(mktemp -d /tmp/sc-upgrade.XXXXXX)
# Small compressed code snapshot; no second full copy of configurations.
tar -czf "$work/code-before.tar.gz" -C "$C" starts libs menus padavan ui
gzip -t "$work/code-before.tar.gz"
modified=1
for part in starts libs menus padavan ui;do cp -R "$base/payload/$part/." "$C/$part/";done
chmod 700 "$C/starts/"*.sh
"$C/starts/padavan_ui.sh"
# A code upgrade must not restart a healthy core or change its configuration.
if pidof CrashCore >/dev/null 2>&1;then
 host=$(nvram get lan_ipaddr);secret=$(sed -n 's/^secret=//p' "$C/configs/ShellCrash.cfg" | head -1)
 curl --noproxy '*' -fsS --max-time 3 -H "Authorization: Bearer $secret" "http://$host:9999/version" >/dev/null || { echo '内核 API 未响应，回退源码'; exit 1; }
fi
"$C/starts/save_storage.sh"
committed=1
echo '源码已更新；节点、规则、DNS、备份设置与内核保持'
