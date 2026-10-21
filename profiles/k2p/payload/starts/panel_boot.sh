#!/bin/sh
# Firmware boot/SSH shells may omit the directories holding nvram and iptables.
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
CRASHDIR=/etc/storage/ShellCrash
export CRASHDIR
export GOMEMLIMIT=12MiB
export GOGC=25
"$CRASHDIR/starts/legacy_storage_guard.sh" || exit 1
# 8 MiB reserve starves the small DMA zone during management shell forks.
[ ! -w /proc/sys/vm/min_free_kbytes ] || echo 4096 > /proc/sys/vm/min_free_kbytes
# Old SSR rule updates use mtd_storage.sh save even when SSR is disabled.
if [ "$(/usr/sbin/nvram get ss_enable)" != 1 ] && crontab -l 2>/dev/null | grep -qE '/usr/bin/update_(chnroute|gfwlist)\.sh'; then
 crontab -l | grep -vE '/usr/bin/update_(chnroute|gfwlist)\.sh' > /tmp/sc-clean-cron
 crontab /tmp/sc-clean-cron; rm -f /tmp/sc-clean-cron
fi
sed -i '/^alias crash=/d; /^export CRASHDIR=/d' /etc/profile
echo 'alias crash="sh /etc/storage/ShellCrash/menu.sh"' >> /etc/profile
echo 'export CRASHDIR="/etc/storage/ShellCrash"' >> /etc/profile
"$CRASHDIR/starts/padavan_ui.sh"
# Boot honours the official switch; manual start and recovery remain available.
[ "$1" != boot ] || [ ! -f "$CRASHDIR/.dis_startup" ] || exit 0
[ -f "$CRASHDIR/configs/panel-disabled" ] && exit 0
if ! mkdir /tmp/shellcrash-bootstrap.lock 2>/dev/null; then
 owner=$(cat /tmp/shellcrash-bootstrap.lock/owner 2>/dev/null)
 [ -z "$owner" ] || { kill -0 "$owner" 2>/dev/null && exit 0; }
 rm -f /tmp/shellcrash-bootstrap.lock/owner
 rmdir /tmp/shellcrash-bootstrap.lock 2>/dev/null || exit 1
 mkdir /tmp/shellcrash-bootstrap.lock 2>/dev/null || exit 1
fi
echo $$ > /tmp/shellcrash-bootstrap.lock/owner
trap 'boot_status=$?;rm -f /tmp/shellcrash-bootstrap.lock/owner;rmdir /tmp/shellcrash-bootstrap.lock 2>/dev/null;[ "$boot_status" = 0 ] || printf "%s Boot preparation failed (exit %s)\n" "$(date +%s)" "$boot_status" >> /tmp/sc-admin/events.log' EXIT
mkdir -p /tmp/ShellCrash
# Reuse the existing minute watchdog for a failed first boot, without counting a crash.
[ "$1" != boot ] || : > /tmp/ShellCrash/boot-pending
if [ "$1" = boot ];then
 boot_delay=$(sed -n 's/^start_delay=//p' "$CRASHDIR/configs/ShellCrash.cfg" | head -1)
 case "$boot_delay" in ''|*[!0-9]*) boot_delay=0;;esac
 # Apply the user's delay before any network-dependent downloads, once only.
 if [ "$boot_delay" -gt 0 ] && [ "$boot_delay" -le 3600 ];then
  printf '%s Boot waits %s seconds before resource downloads\n' "$(date '+%m-%d %H:%M:%S')" "$boot_delay" >> /tmp/sc-admin/events.log
  sleep "$boot_delay"
  [ ! -f "$CRASHDIR/configs/panel-disabled" ] && [ ! -f "$CRASHDIR/.dis_startup" ] || exit 0
 fi
 SC_BOOT_DELAY_APPLIED=1;export SC_BOOT_DELAY_APPLIED
fi
# An owned core-update worker retains its rollback archive until commit. Keep
# that worker's existing64M temporary budget through boot; it restores45M after
# commit/rollback. This is a quota ceiling, not a memory-protection reduction.
case "${SC_CORE_UPDATE_TMPFS:-0}" in 1)sc_boot_tmpfs_limit=64M;;*)sc_boot_tmpfs_limit=45M;;esac
unset SC_CORE_UPDATE_TMPFS
mount -t tmpfs -o remount,rw,size="$sc_boot_tmpfs_limit" tmpfs /tmp
# Configuration transactions can supply the already verified executable without an archive.
printf '%s core_reuse=%s executable=%s\n' "$(date '+%m-%d %H:%M:%S')" "${SC_REUSE_RUNNING_CORE:-0}" "$(test -x /tmp/ShellCrash/CrashCore && echo 1 || echo 0)" >> /tmp/sc-admin/events.log
if [ "$SC_REUSE_RUNNING_CORE" = 1 ];then
 # An owned transaction already holds its verified binary. Never stage a
 # second archive if descriptor handoff fails: abort to its rollback instead.
 [ -x /tmp/ShellCrash/CrashCore ] || { printf '%s Verified core handoff unavailable; refusing archive fallback\n' "$(date '+%m-%d %H:%M:%S')" >> /tmp/sc-admin/events.log;exit 1; }
else
 "$CRASHDIR/starts/download_core.sh" || exit 1
fi
[ -f "$CRASHDIR/configs/panel-disabled" ] && exit 0
. "$CRASHDIR/starts/panel_env.sh" || exit 1
if [ "$1" = boot ]; then SC_CONTROL_SOURCE=boot; else SC_CONTROL_SOURCE=${SC_CONTROL_SOURCE:-tool}; fi
export SC_CONTROL_SOURCE
C=$CRASHDIR
. "$C/starts/rules_path.sh"
rules_ensure || exit 1
ln -sf "$RULES_FILE" /tmp/ShellCrash/cn_ip.txt
native_result=0
# This is an authorized start. Clear the old stop marker before dispatching
# delayed background preparation; a new marker still cancels the readiness wait.
rm -f /tmp/ShellCrash/manual-stop
mkdir -p /tmp/sc-admin
SC_PANEL_STARTING=1 "$CRASHDIR/start.sh" start >> /tmp/sc-admin/service.log 2>&1 || native_result=$?
# The official start_legacy path backgrounds preparation and start. Its zero
# exit status means dispatched, not ready. Trailing hooks may also return
# nonzero after success. In either case confirm the live authenticated API.
secret=$(sed -n 's/^secret=//p' "$CRASHDIR/configs/ShellCrash.cfg" | head -1)
# Native legacy start prepares in the background. Two bounded cold-cache
# domain downloads (up to 80s), profile normalization and native checks share
# this deadline; 90s can roll back while preparation is still progressing.
deadline=$(( $(cut -d. -f1 /proc/uptime) + 180 ))
while [ "$(cut -d. -f1 /proc/uptime)" -lt "$deadline" ]; do
 [ ! -f "$CRASHDIR/configs/panel-disabled" ] && [ ! -f /tmp/ShellCrash/manual-stop ] || exit 0
 if [ -n "$(pidof CrashCore)" ] && curl --noproxy '*' -fsS --connect-timeout 1 --max-time 1 -H "Authorization: Bearer $secret" "http://${PANEL_LAN_IP}:9999/version" >/dev/null 2>&1; then
  # sing-box may restore the temporary API mode from its cache; startup always returns to rules.
  if curl --noproxy '*' -fsS --connect-timeout 1 --max-time 2 -X PATCH -H "Authorization: Bearer $secret" -H 'Content-Type: application/json' -d '{"mode":"rule"}' "http://${PANEL_LAN_IP}:9999/configs" >/dev/null 2>&1;then rm -f /tmp/ShellCrash/boot-pending /tmp/sc-admin/boot-retry-due /tmp/sc-admin/boot-retry-attempts;exit 0;fi
  mkdir -p /tmp/sc-admin
  printf '%s Core started but rule mode reset failed\n' "$(date '+%m-%d %H:%M:%S')" >> /tmp/sc-admin/events.log
  exit 1
 fi
 sleep 1
done
mkdir -p /tmp/sc-admin
printf '%s Boot start did not reach a live authenticated core API within 180s (dispatch exit %s)\n' "$(date '+%m-%d %H:%M:%S')" "$native_result" >> /tmp/sc-admin/events.log
[ "$native_result" != 0 ] || native_result=1
exit "$native_result"
