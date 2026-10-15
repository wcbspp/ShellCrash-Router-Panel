#!/bin/sh
set -eu
case "${1:-}" in
 ax5)C=/data/ShellCrash;D=/tmp/ShellCrash;helper="$C/ax5";;
 k2p)C=/etc/storage/ShellCrash;D=/tmp/sc-admin;helper="$C/starts";;
 *)exit 2;;
esac
case "${2:-}" in create|replace) :;;*)exit 2;;esac
export C D
. "$helper/remote.sh"
. "$helper/backup-baseline.sh"
baseline_check_slot "$2"
# Generate from this device now; never silently use the last backup's settings.
sh "$helper/backup-app.sh" remote
baseline_create
