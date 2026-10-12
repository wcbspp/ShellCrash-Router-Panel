#!/bin/sh
# AX5 Linux 4.4's heuristic rejects mihomo's large virtual reservation.
# Temporarily permit virtual reservations; this does not raise real RAM limits.
set -eu
kind=$1
shift
old=$(cat /proc/sys/vm/overcommit_memory)
restore() { [ "$kind" != meta ] || echo "$old" > /proc/sys/vm/overcommit_memory; }
trap restore EXIT
trap 'exit 1' INT TERM
[ "$kind" != meta ] || echo 1 > /proc/sys/vm/overcommit_memory
SAFE_PATHS=/data/ShellCrash GOMEMLIMIT=12MiB GOGC=25 "$@"
