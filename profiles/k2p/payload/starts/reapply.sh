#!/bin/sh
# Padavan panel adaptation; configurable LAN address.
PANEL_HOME=${CRASHDIR:-/etc/storage/ShellCrash}
. "$PANEL_HOME/starts/panel_env.sh" || exit 1
CRASHDIR=/etc/storage/ShellCrash
export CRASHDIR
[ -n "$(pidof CrashCore)" ] || exit 0
. "$CRASHDIR/libs/get_config.sh"
. "$CRASHDIR/libs/check_cmd.sh"
. "$CRASHDIR/libs/logger.sh"
. "$CRASHDIR/libs/web_get_bin.sh"
. "$CRASHDIR/starts/check_geo.sh"
. "$CRASHDIR/starts/check_cnip.sh"
sh "$CRASHDIR/starts/fw_stop.sh"
ck_cn_ipv4
. "$CRASHDIR/starts/fw_start.sh"
