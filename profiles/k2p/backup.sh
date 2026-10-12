#!/bin/sh
# Capture only the files the installer may change, including absence markers.
set -eu
umask 077
out=${1:--}
D=/tmp/sc-panel-backup.lock
mkdir "$D" || exit 1
marker=/etc/storage/_panel_backup_state
[ ! -e "$marker" ] || { rmdir "$D";echo '已有备份标记，请先检查上次操作' >&2;exit 1; }
trap 'rm -f "$marker"; rmdir "$D" 2>/dev/null || :' EXIT
trap 'exit 1' HUP INT TERM
set -- started_script.sh
{
 if [ -e /etc/storage/ShellCrash ]; then echo shellcrash=present; else echo shellcrash=absent; fi
 if [ -e /etc/storage/chinadns/chnroute.txt ]; then echo cnroute=present; else echo cnroute=absent; fi
 if [ -d /etc/storage/chinadns ]; then echo cndir=present; else echo cndir=absent; fi
} > "$marker"
[ ! -e /etc/storage/ShellCrash ] || set -- "$@" ShellCrash
[ ! -e /etc/storage/chinadns/chnroute.txt ] || set -- "$@" chinadns/chnroute.txt
tar -czf "$out" -C /etc/storage "$@" _panel_backup_state
