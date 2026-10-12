#!/bin/sh
# Padavan panel adaptation; configurable LAN address.
PANEL_HOME=${CRASHDIR:-/etc/storage/ShellCrash}
. "$PANEL_HOME/starts/panel_env.sh" || exit 1
CRASHDIR=/etc/storage/ShellCrash
export CRASHDIR
"$CRASHDIR/starts/memory_sample.sh" >/dev/null 2>&1
"$CRASHDIR/starts/manage.sh" trim >/dev/null 2>&1
admin_owner=$(cat /tmp/sc-admin/operation.lock/owner 2>/dev/null)
[ -z "$admin_owner" ] || { kill -0 "$admin_owner" 2>/dev/null && exit 0; }
[ -n "$(pidof CrashCore)" ] || exit 0
mkdir /tmp/shellcrash-save.lock 2>/dev/null || exit 0
trap 'rmdir /tmp/shellcrash-save.lock 2>/dev/null' EXIT
. "$CRASHDIR/libs/get_config.sh"
. "$CRASHDIR/libs/check_cmd.sh"
. "$CRASHDIR/libs/web_save.sh"
curl -fsS --connect-timeout 3 --max-time 5 -H "Authorization: Bearer $secret" "http://${PANEL_LAN_IP}:${db_port}/proxies" | grep -Fq "\"$PANEL_MAIN_GROUP\"" || exit 0
before=$(sha256sum "$CRASHDIR/configs/web_save" 2>/dev/null | awk '{print $1}')
web_save
after=$(sha256sum "$CRASHDIR/configs/web_save" 2>/dev/null | awk '{print $1}')
[ "$before" = "$after" ] || touch /tmp/ShellCrash/selection-save-pending
if [ -f /tmp/ShellCrash/selection-save-pending ]; then
 "$CRASHDIR/starts/save_storage.sh" >/dev/null 2>&1 && rm -f /tmp/ShellCrash/selection-save-pending
fi
