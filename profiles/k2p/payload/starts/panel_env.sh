#!/bin/sh
# Root-owned local configuration; never serve this file through the dashboard.
PANEL_HOME=${CRASHDIR:-/etc/storage/ShellCrash}
[ ! -f "$PANEL_HOME/configs/panel.conf" ] || . "$PANEL_HOME/configs/panel.conf"
PANEL_LAN_IP=${PANEL_LAN_IP:-$(/usr/sbin/nvram get lan_ipaddr)}
printf '%s' "$PANEL_LAN_IP" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$' || return 1
PANEL_MAIN_GROUP=${PANEL_MAIN_GROUP:-proxy-main}
printf '%s' "$PANEL_MAIN_GROUP" | grep -Eq '^[A-Za-z0-9._-]{1,64}$' || return 1
export PANEL_LAN_IP PANEL_CN_MIRROR PANEL_MAIN_GROUP
