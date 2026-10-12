#!/bin/sh
C=/data/ShellCrash
R=/tmp/ShellCrash
KIND=singbox
VERSION=1.12.13
SOURCE=https://raw.githubusercontent.com/juewuy/ShellCrash/7b1471a33bcf195cf2b7fb8f6f40fe27a9646ba5/bin/singbox/singbox-linux-armv7.tar.gz
HASH=$(awk '{print $1}' "$C/cache/core.sha256")
[ ! -f "$C/cache/core.env" ] || . "$C/cache/core.env"
MIRROR=$(sed -n 's/^base=//p' "$C/configs/mirror.conf" 2>/dev/null | head -1)
case "$MIRROR" in http://*|https://*) :;; *) MIRROR='';; esac

D=$R
. "$C/ax5/remote.sh"
remote_ready || MIRROR=''
[ "$(remote_transport)" != webdav ] || MIRROR=''
