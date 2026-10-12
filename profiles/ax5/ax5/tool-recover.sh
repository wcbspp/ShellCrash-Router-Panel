#!/bin/sh
set -e
C=/data/ShellCrash
if [ -f "$C/cache/tool-update-pending" ];then
 [ -s "$C/cache/tool-previous.tar.gz" ] || { echo 'Interrupted tool update: rollback archive missing' >&2;exit 1; }
 tar -xzf "$C/cache/tool-previous.tar.gz" -C /data/ShellCrash-tool
 sync
 rm -f "$C/cache/tool-update-pending" "$C/cache/tool-previous.tar.gz"
 echo 'Interrupted tool update restored; proxy configuration preserved.'
fi
