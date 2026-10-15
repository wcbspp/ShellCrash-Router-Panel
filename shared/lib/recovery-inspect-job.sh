#!/bin/sh
# AX5 detached inspection job. exec from Lua releases the waiting interpreter.
set -eu
umask 077
profile=$1;id=$2
[ "$profile" = ax5 ] || exit 2
case "$id" in ''|*[!a-f0-9]*)exit 2;;esac
[ "${#id}" = 8 ] || exit 2
C=/data/ShellCrash;D=/tmp/ShellCrash
[ "$(cat "$D/operation.lock/owner" 2>/dev/null)" = "$$" ] || exit 3
finish(){
 code=$?;trap - EXIT
 if [ "$code" = 0 ];then state=done;message='原生预检已完成，尚未执行恢复';else state=error;message=$(head -c 512 "$D/recovery-result.log" 2>/dev/null);message=${message:-恢复预检未完成，当前代理保持运行};fi
 printf '{"id":"%s","phase":"%s","active":false,"message_b64":"%s"}\n' "$id" "$state" "$(printf '%s' "$message"|base64|tr -d '\n')" > "$D/job.json.new"
 mv "$D/job.json.new" "$D/job.json"
 rm -f "$D/operation.lock/owner";rmdir "$D/operation.lock" 2>/dev/null || :
 exit "$code"
}
trap finish EXIT
trap 'exit 1' INT TERM
sh "$C/ax5/recovery-check.sh" ax5 "$id" > "$D/recovery-result.log" 2>&1
