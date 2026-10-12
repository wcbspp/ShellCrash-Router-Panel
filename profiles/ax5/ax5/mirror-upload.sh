#!/bin/sh
set -eu
C=/data/ShellCrash
D=/tmp/ShellCrash
. "$C/ax5/remote.sh"
remote_put "$1" "$2" "$3"
