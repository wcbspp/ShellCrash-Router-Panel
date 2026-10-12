#!/bin/sh
# Restore a trusted same-router archive; callers stop service and save Flash.
set -eu
backup=$1
[ -s "$backup" ] || { echo '备份文件不存在'; exit 1; }
tar -tzf "$backup" | awk '
 /^\/|(^|\/)\.\.(\/|$)/{bad=1}
 !/^ShellCrash(\/|$)|^started_script.sh$|^chinadns(\/|$)|^_panel_backup_state$/{bad=1}
 END{exit bad}' || { echo '备份包含不支持的路径'; exit 1; }
tar -tzf "$backup" | grep -qx 'started_script.sh' || { echo '备份中缺少原始开机脚本'; exit 1; }
state=$(tar -xOzf "$backup" _panel_backup_state 2>/dev/null || :)
if printf '%s\n' "$state" | grep -qx 'shellcrash=absent'; then
 restore_core=0
else
 tar -tzf "$backup" | grep -q '^ShellCrash/' || { echo '备份中缺少原始ShellCrash'; exit 1; }
 restore_core=1
fi
rm -rf /etc/storage/ShellCrash
if printf '%s\n' "$state" | grep -qx 'cnroute=absent'; then
 rm -f /etc/storage/chinadns/chnroute.txt
fi
tar -xzf "$backup" -C /etc/storage
rm -f /etc/storage/_panel_backup_state
if printf '%s\n' "$state" | grep -qx 'cndir=absent'; then
 rmdir /etc/storage/chinadns 2>/dev/null || :
fi
[ "$restore_core" = 1 ] || echo '已移除本次新安装的ShellCrash'
