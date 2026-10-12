#!/bin/sh
C=/data/ShellCrash
if [ "$1" = start ] || [ "$1" = restart ] || [ "$1" = watchdog ] || [ "$1" = init ]; then
 mkdir -p /tmp/ShellCrash
 printf '%s\n' "${SC_CONTROL_SOURCE:-tool}" > /tmp/ShellCrash/control-source.pending
fi
case "$1" in
 start) printf '1\n' > "$C/configs/enabled"; /etc/init.d/shellcrash "$1";;
 restart) /etc/init.d/shellcrash stop; for n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do lua -e 'local M=dofile("/data/ShellCrash/ax5/common.lua");os.exit(M.pid()==0 and 0 or 1)' && break; sleep 1; done; lua -e 'local M=dofile("/data/ShellCrash/ax5/common.lua");os.exit(M.pid()==0 and 0 or 1)' || exit 1; printf '1\n' > "$C/configs/enabled"; /etc/init.d/shellcrash start;;
 stop) printf '0\n' > "$C/configs/enabled"; /etc/init.d/shellcrash stop;;
 init) [ ! -f /data/ShellCrash-tool/.dis_startup ] || exit 0; printf '1\n' > "$C/configs/enabled"; /etc/init.d/shellcrash start;;
 watchdog) [ "$(cat "$C/configs/enabled" 2>/dev/null)" = 1 ] || exit 0; [ ! -f /tmp/ShellCrash/manual-stop ] || exit 0; /etc/init.d/shellcrash start;;
 cronset) export CRASHDIR=/data/ShellCrash-tool; . "$CRASHDIR/libs/set_cron.sh"; shift; cronset "$@";;
 *) echo 'AX5 使用统一的轻量服务；DNS、订阅、规则和日志请在 ShellCrash 网页管理。';;
esac
