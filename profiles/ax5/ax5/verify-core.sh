#!/bin/sh
. /data/ShellCrash/ax5/core-env.sh
actual=$(openssl dgst -sha256 "$C/cache/core-armv7.tar.gz" 2>/dev/null | awk '{print $NF}')
[ "$HASH" = "$actual" ] && [ ${#HASH} = 64 ]
