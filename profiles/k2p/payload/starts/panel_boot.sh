#!/bin/sh
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
trap 'rm -f /tmp/shellcrash-bootstrap.lock/owner; rmdir /tmp/shellcrash-bootstrap.lock 2>/dev/null' EXIT
mkdir -p /tmp/ShellCrash
mount -t tmpfs -o remount,rw,size=45M tmpfs /tmp
# Configuration transactions can supply the already verified executable without an archive.
printf '%s core_reuse=%s executable=%s\n' "$(date '+%m-%d %H:%M:%S')" "${SC_REUSE_RUNNING_CORE:-0}" "$(test -x /tmp/ShellCrash/CrashCore && echo 1 || echo 0)" >> /tmp/sc-admin/events.log
if [ "$SC_REUSE_RUNNING_CORE" != 1 ] || [ ! -x /tmp/ShellCrash/CrashCore ];then
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
"$CRASHDIR/start.sh" start || native_result=$?
# The official start_legacy path backgrounds preparation and start. Its zero
# exit status means dispatched, not ready. Trailing hooks may also return
# nonzero after success. In either case confirm the live authenticated API.
secret=$(sed -n 's/^secret=//p' "$CRASHDIR/configs/ShellCrash.cfg" | head -1)
deadline=$(( $(cut -d. -f1 /proc/uptime) + 90 ))
while [ "$(cut -d. -f1 /proc/uptime)" -lt "$deadline" ]; do
 [ ! -f "$CRASHDIR/configs/panel-disabled" ] && [ ! -f /tmp/ShellCrash/manual-stop ] || exit 0
 if [ -n "$(pidof CrashCore)" ] && curl --noproxy '*' -fsS --connect-timeout 1 --max-time 1 -H "Authorization: Bearer $secret" "http://${PANEL_LAN_IP}:9999/version" >/dev/null 2>&1; then
  # sing-box may restore the temporary API mode from its cache; startup always returns to rules.
  if curl --noproxy '*' -fsS --connect-timeout 1 --max-time 2 -X PATCH -H "Authorization: Bearer $secret" -H 'Content-Type: application/json' -d '{"mode":"rule"}' "http://${PANEL_LAN_IP}:9999/configs" >/dev/null 2>&1;then exit 0;fi
  mkdir -p /tmp/sc-admin
  printf '%s Core started but rule mode reset failed\n' "$(date '+%m-%d %H:%M:%S')" >> /tmp/sc-admin/events.log
  exit 1
 fi
 sleep 1
done
mkdir -p /tmp/sc-admin
printf '%s Boot start did not reach a live authenticated core API within 90s (dispatch exit %s)\n' "$(date '+%m-%d %H:%M:%S')" "$native_result" >> /tmp/sc-admin/events.log
[ "$native_result" != 0 ] || native_result=1
exit "$native_result"
