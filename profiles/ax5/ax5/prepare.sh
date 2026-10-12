#!/bin/sh
set -e
. /data/ShellCrash/ax5/core-env.sh
umask 077
mkdir -p "$R"
cat /etc/hosts /tmp/hosts/dhcp.* > "$R/hosts" 2>/dev/null || true
[ -f "$R/fakeip.db" ] || [ ! -f "$C/configs/fakeip.db" ] || cp "$C/configs/fakeip.db" "$R/fakeip.db"
[ "$KIND" != meta ] || [ -f "$R/cache.db" ] || [ ! -f "$C/configs/mihomo-cache.db" ] || cp "$C/configs/mihomo-cache.db" "$R/cache.db"
if [ ! -x "$R/CrashCore" ]; then
 "$C/ax5/verify-core.sh" || "$C/ax5/recover-core.sh"
 tar -xzf "$C/cache/core-armv7.tar.gz" -C "$R" CrashCore
 chmod 700 "$R/CrashCore"
fi
lua "$C/ax5/config-normalize.lua" migrate
if [ "$KIND" = meta ]; then
 timeout -t 60 "$C/ax5/native-resources.sh" "$C/configs/config.json"
 lua "$C/ax5/mihomo.lua" generate "$C/configs/config.json" "$R/config.yaml"
 "$C/ax5/check-binary.sh" meta "$R/CrashCore" -t -d "$R" -f "$R/config.yaml" >> "$R/service.log" 2>&1
else
 GOMEMLIMIT=12MiB GOGC=25 "$R/CrashCore" check -D "$R" -c "$C/configs/config.json" >> "$R/service.log" 2>&1
fi
"$C/ax5/tool-recover.sh" >> "$R/service.log" 2>&1 || true
"$C/ax5/tool-sync.sh"
[ -e "$R/csrf" ] || head -c 24 /dev/urandom | base64 > "$R/csrf"
chmod 600 "$R/csrf"
