#!/bin/sh
# ShellCrash supplies the package and source URL; this adapter owns AX5 persistence/rollback.
set -eu
. /data/ShellCrash/ax5/core-env.sh
candidate=$1
nextkind=$2
nextsource=${3:-$SOURCE}
case "$nextkind" in singbox|meta) ;; *) echo 'AX5 currently supports sing-box and mihomo only.' >&2; exit 2;; esac
case "$candidate" in *.tar.gz) ;; *) echo 'Use tar.gz on AX5; UPX failed the hardware test.' >&2; exit 2;; esac
case "$nextsource" in https://*) ;; *) exit 2;; esac
printf '%s' "$nextsource" | grep -q '^[a-zA-Z0-9:/._%+=?-]*$' || exit 2
case "$candidate" in /tmp/ShellCrash/*.tar.gz) ;; *) exit 2;; esac
ownoperation=0
if [ "${SC_CORE_JOB:-0}" != 1 ]; then
 lua -e 'local M=dofile("/data/ShellCrash/ax5/common.lua");os.exit(M.lock("operation.lock",900) and 0 or 1)' || exit 1
 ownoperation=1
fi
mkdir "$R/core-install.lock" || { echo 'Another core operation is running.' >&2; exit 1; }
stopped=0
committed=0
oldkind=$KIND
oldversion=$VERSION
oldsource=$SOURCE
oldhash=$HASH
wasrunning=$(lua -e 'local M=dofile("/data/ShellCrash/ax5/common.lua"); print(M.pid()>0 and 1 or 0)')
[ "${SC_PREVIOUSLY_RUNNING:-0}" = 0 ] || wasrunning=1
enabled=$(cat "$C/configs/enabled")
manifest() { printf 'KIND=%s\nVERSION=%s\nHASH=%s\nSOURCE=%s\n' "$1" "$2" "$3" "$4"; }
finish() {
 code=$?
 trap - EXIT INT TERM
 rm -f "$R/core_new"
 if [ "$code" != 0 ] && [ "$stopped" = 1 ]; then
  /etc/init.d/shellcrash stop || true
  rm -f "$R/CrashCore"
  manifest "$oldkind" "$oldversion" "$oldhash" "$oldsource" > "$C/cache/core.env.new"
  mv "$C/cache/core.env.new" "$C/cache/core.env"
  printf '%s\n' "$oldhash" > "$C/cache/core.sha256"
  if [ "${rollback_local:-0}" = 1 ] && [ -s "$R/core-rollback.tar.gz" ];then mv "$R/core-rollback.tar.gz" "$C/cache/core-armv7.tar.gz";fi
  "$C/ax5/verify-core.sh" || "$C/ax5/recover-core.sh" || { echo 'Rollback download failed; previous manifest retained for recovery.' >&2; code=1; }
  if [ "$wasrunning" = 1 ]; then printf '1\n' > "$C/configs/enabled"; /etc/init.d/shellcrash start || true; fi
 fi
 printf '%s\n' "$enabled" > "$C/configs/enabled"
 "$C/ax5/tool-sync.sh" || true
 rm -f "$candidate" "$R/core-check.yaml" "$R/core-backup.tar.gz" "$R/core-rollback.tar.gz"
 rmdir "$R/core-install.lock"
 [ "$ownoperation" = 0 ] || rmdir "$R/operation.lock"
 exit "$code"
}
trap finish EXIT
trap 'exit 1' INT TERM
"$C/ax5/verify-core.sh" || { echo 'Previous archive failed verification.' >&2; exit 1; }
[ "$(tar -tzf "$candidate")" = CrashCore ] || { echo 'Invalid archive layout.' >&2; exit 2; }
size=$(wc -c < "$candidate")
[ "$size" -lt 18000000 ] || exit 2
available=$(df -k "$C" | awk 'END {print $4}')
oldsize=$(wc -c < "$C/cache/core-armv7.tar.gz")
[ $((available*1024+oldsize-size)) -ge 524288 ] || { echo 'Insufficient persistent space; existing core kept.' >&2; exit 1; }
lua "$C/ax5/state.lua" save-selection
# Never remove the only rollback package without a verified alternative.
rollback_local=0
if remote_ready && "$C/ax5/mirror-upload.sh" core "$C/cache/core-armv7.tar.gz" tar.gz >/dev/null;then :
else
 memory=$(awk '/^MemAvailable:/{print $2;found=1} END {if(!found)print 0}' /proc/meminfo)
 [ "$memory" -ge "$((oldsize/1024+24576))" ] || { echo '远程回退不可用且内存不足以保留旧包；未替换内核' >&2;exit 1; }
 cp "$C/cache/core-armv7.tar.gz" "$R/core-rollback.tar.gz"
 rollback_local=1
fi
newhash=$(openssl dgst -sha256 "$candidate" | awk '{print $NF}')
if [ "$newhash" = "$oldhash" ] && [ "$nextkind" = "$oldkind" ]; then echo 'Already installed.'; exit 0; fi
stopped=1
/etc/init.d/shellcrash stop
for n in 1 2 3 4 5 6 7 8 9 10 11 12; do
 if lua -e 'local M=dofile("/data/ShellCrash/ax5/common.lua");os.exit(M.pid()==0 and 0 or 1)'; then break; fi
 sleep 1
done
lua -e 'local M=dofile("/data/ShellCrash/ax5/common.lua");os.exit(M.pid()==0 and 0 or 1)'
rm -f "$R/CrashCore"
# Compressed archives in tmpfs consume RAM too. Persist first under the old manifest;
# if validation fails or power is lost, that manifest restores the previous hash.
rm "$C/cache/core-armv7.tar.gz"
mv "$candidate" "$C/cache/core-armv7.tar.gz"
sync
tar -xOzf "$C/cache/core-armv7.tar.gz" CrashCore > "$R/core_new"
chmod 700 "$R/core_new"
if [ "$nextkind" = meta ]; then
 v=$("$C/ax5/check-binary.sh" meta "$R/core_new" -v | sed -n '1s/.*Meta \([^ ]*\).*/\1/p')
 lua "$C/ax5/mihomo.lua" generate "$C/configs/config.json" "$R/core-check.yaml"
 "$C/ax5/check-binary.sh" meta "$R/core_new" -t -d "$R" -f "$R/core-check.yaml"
else
 v=$("$R/core_new" version | awk '/sing-box version/ {print $3;exit}')
 GOMEMLIMIT=12MiB GOGC=25 "$R/core_new" check -D "$R" -c "$C/configs/config.json"
fi
[ -n "$v" ] && ! printf '%s' "$v" | grep -q '[^a-zA-Z0-9.+_-]' || exit 2
rm -f "$R/core_new"
# The old manifest remains authoritative until both the new archive and its hash are durable.
sync
manifest "$nextkind" "$v" "$newhash" "$nextsource" > "$C/cache/core.env.new"
mv "$C/cache/core.env.new" "$C/cache/core.env"
printf '%s\n' "$newhash" > "$C/cache/core.sha256"
sync
if [ "$wasrunning" = 1 ]; then
 printf '1\n' > "$C/configs/enabled"
 /etc/init.d/shellcrash start
 ready=0
 for n in 1 2 3 4 5 6 7 8 9 10; do
  if lua -e 'local M=dofile("/data/ShellCrash/ax5/common.lua");os.exit(M.pid()>0 and M.api("/version")~="" and 0 or 1)'; then ready=1; break; fi
  sleep 1
 done
 [ "$ready" = 1 ] || { echo 'New core failed health check.' >&2; exit 1; }
fi
mkdir -p "$C/cache/targets"
cp "$C/cache/core.env" "$C/cache/targets/$nextkind.env"
committed=1
stopped=0
if remote_ready && ! "$C/ax5/mirror-sync.sh";then
 printf 'Core %s %s is local; mirror synchronization pending.\n' "$nextkind" "$v" > "$C/configs/mirror-pending"
 echo 'Core installed locally; mirror synchronization pending.' >&2
fi
echo "Installed $nextkind $v; archive persisted; see mirror synchronization status."
