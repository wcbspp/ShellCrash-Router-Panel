#!/bin/sh
# Restore the private pre-install archive on the same router/firmware.
set -eu
BASE=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
C=/etc/storage/ShellCrash
backup=${1:-/tmp/padavan-panel-before-install.tar.gz}
[ "$(id -u)" = 0 ] && [ -s "$backup" ] || { echo '需要管理员权限和原始安装备份'; exit 1; }
tar -tzf "$backup" | awk '/^\/|(^|\/)\.\.(\/|$)/{bad=1}END{exit bad}' || { echo '归档路径无效'; exit 1; }
CRASHDIR="$C" "$C/start.sh" stop
[ -f "$C/starts/save_storage.sh" ] || { echo '当前安装缺少保存脚本'; exit 1; }
cp "$C/starts/save_storage.sh" /tmp/padavan-panel-restore-save.sh
for target in /www/state.js /sbin/mtd_storage.sh /usr/bin/update_chnroute.sh /usr/bin/update_gfwlist.sh; do
 umount "$target" >/dev/null 2>&1 || :
done
 if crontab -l 2>/dev/null | grep -q '#ShellCrashSaveSelection'; then
  crontab -l | grep -v '#ShellCrashSaveSelection' > /tmp/sc-panel-clean.cron
  crontab /tmp/sc-panel-clean.cron
  rm -f /tmp/sc-panel-clean.cron
 fi
# A reboot removes web/menu/legacy bind overlays; restore files first.
sh "$BASE/restore_storage.sh" "$backup"
/bin/sh /tmp/padavan-panel-restore-save.sh
rm -f /tmp/padavan-panel-restore-save.sh
echo '原始Storage已恢复。请在维护时间手动重启路由器，以移除RAM中的挂载覆盖。'
