
[ -z "$CRASHDIR" ] && CRASHDIR=$(cd "$(dirname "$0")"/.. && pwd)
if [ "$1" = shellcrash ]; then
 [ ! -f /tmp/ShellCrash/manual-stop ] || exit 0
 # A cron tick before the first boot start is not an unexpected core exit.
 [ -f /tmp/ShellCrash/crash_start_time ] || [ -f /tmp/ShellCrash/shellcrash.pid ] || exit 0
 [ ! -d /tmp/padavan-panel-install.lock ] || exit 0
 [ -f "$CRASHDIR/configs/panel-disabled" ] && exit 0
 admin_owner=$(cat /tmp/sc-admin/operation.lock/owner 2>/dev/null)
 [ -z "$admin_owner" ] || { kill -0 "$admin_owner" 2>/dev/null && exit 0; }
 boot_owner=$(cat /tmp/shellcrash-bootstrap.lock/owner 2>/dev/null)
 [ -z "$boot_owner" ] || { kill -0 "$boot_owner" 2>/dev/null && exit 0; }
fi
PIDFILE="/tmp/ShellCrash/$1.pid"
LOCKDIR="/tmp/ShellCrash/start_$1.lock"

[ -f "$CRASHDIR"/.start_error ] && [ ! -f /tmp/ShellCrash/crash_start_time ] && exit 1 #当启动失败后禁止开机自启动
if ! mkdir "$LOCKDIR" 2>/dev/null; then
 lock_owner=$(cat "$LOCKDIR/owner" 2>/dev/null)
 if [ -n "$lock_owner" ]; then
  kill -0 "$lock_owner" 2>/dev/null && exit 0
 else
  lock_age=$(( $(date +%s) - $(stat -c %Y "$LOCKDIR" 2>/dev/null || date +%s) ))
  [ "$lock_age" -lt 120 ] && exit 0
 fi
 rm -f "$LOCKDIR/owner"
 rmdir "$LOCKDIR" 2>/dev/null || exit 1
 mkdir "$LOCKDIR" 2>/dev/null || exit 1
fi
echo $$ > "$LOCKDIR/owner"
trap 'rm -f "$LOCKDIR/owner"; rmdir "$LOCKDIR" 2>/dev/null' EXIT

# A missing or stale PID file must not restart a healthy core.
if [ "$1" = shellcrash ]; then
 for actual in $(pidof CrashCore); do
  if grep -q 'run' "/proc/$actual/cmdline" 2>/dev/null; then
   [ "$(cat "$PIDFILE" 2>/dev/null)" = "$actual" ] || echo "$actual" > "$PIDFILE"
   [ ! -f /tmp/sc-admin/incident-outage-pid ] || "$CRASHDIR"/starts/incident_record.sh finish "$(cat /tmp/sc-admin/incident-outage-pid)"
   exit 0
  fi
 done
fi

if [ -f "$PIDFILE" ]; then
	PID="$(cat "$PIDFILE")"
	if [ -n "$PID" ] && [ "$PID" -eq "$PID" ] 2>/dev/null; then
		if kill -0 "$PID" 2>/dev/null && { [ "$1" != shellcrash ] || grep -q 'CrashCore' "/proc/$PID/cmdline" 2>/dev/null; }; then
			 : # The EXIT trap releases the owned lock.
			exit 0
		fi
	else
		rm -f "$PIDFILE"
	fi
fi

#如果没有进程则拉起
if [ "$1" = "shellcrash" ]; then
	mkdir -p /tmp/sc-admin
 if [ -f /tmp/sc-admin/incident-outage-pid ]; then
  retry_up=$(cut -d. -f1 /proc/uptime)
  due=$(cat /tmp/sc-admin/recovery-due 2>/dev/null); case "$due" in ''|*[!0-9]*) due=0;; esac
  [ "$retry_up" -ge "$due" ] || exit 0
  attempts=$(cat /tmp/sc-admin/recovery-attempts 2>/dev/null); case "$attempts" in ''|*[!0-9]*) attempts=0;; esac
  attempts=$((attempts+1)); wait_sec=$((attempts*60)); [ "$wait_sec" -le 300 ] || wait_sec=300
  echo "$attempts" > /tmp/sc-admin/recovery-attempts
  echo $((retry_up+wait_sec)) > /tmp/sc-admin/recovery-due
  old_outage=$(cat /tmp/sc-admin/incident-outage-pid)
  SC_CONTROL_SOURCE=watchdog "$CRASHDIR"/starts/panel_boot.sh
  "$CRASHDIR"/starts/incident_record.sh finish "$old_outage"
  exit 0
 fi
	count=$(cat /tmp/sc-admin/recoveries 2>/dev/null); case "$count" in ''|*[!0-9]*) count=0;; esac
	echo $((count+1)) > /tmp/sc-admin/recoveries
	printf '%s Unexpected core exit; watchdog restoring saved configuration\n' "$(date '+%m-%d %H:%M:%S')" >> /tmp/sc-admin/events.log
	if [ -n "$PID" ]; then
	 grep -E "(Kill|Killed) process $PID([ (]|$)" /tmp/syslog.log 2>/dev/null | tail -2 >> /tmp/sc-admin/events.log
	fi
	awk '/^(MemFree|MemAvailable|Shmem|Slab):/' /proc/meminfo >> /tmp/sc-admin/events.log
	"$CRASHDIR"/starts/incident_record.sh begin "${PID:-0}"
	SC_CONTROL_SOURCE=watchdog "$CRASHDIR"/starts/panel_boot.sh
	"$CRASHDIR"/starts/incident_record.sh finish "${PID:-0}"
else
	[ -f "$CRASHDIR/starts/start_legacy.sh" ] && . "$CRASHDIR/starts/start_legacy.sh"
	killall bot_tg.sh 2>/dev/null
	start_legacy "$CRASHDIR/menus/bot_tg.sh" "$1"
fi

 : # The EXIT trap releases the owned lock.
