#!/bin/sh
. /data/ShellCrash/ax5/core-env.sh
umask 077
child=''
ending=0
vm_old=$(cat /proc/sys/vm/overcommit_memory)
if [ "$KIND" = meta ]; then
 [ ! -f "$R/vm-original" ] || vm_old=$(cat "$R/vm-original")
 printf '%s\n' "$vm_old" > "$R/vm-original"
 echo $$ > "$R/vm-owner"
 echo 1 > /proc/sys/vm/overcommit_memory
fi
shutdown() { ending=1; touch "$R/manual-stop"; [ -z "$child" ] || kill -TERM "$child" 2>/dev/null; }
trap shutdown TERM INT
mkdir -p "$R"
rm -f "$R/traffic-mode" "$R/transport-runtime" "$R/service-ready"
if [ -f "$R/control-source.pending" ]; then
 mv "$R/control-source.pending" "$R/control-source"
else
 printf 'system\n' > "$R/control-source"
fi
date +%s > "$R/started"
if [ "$KIND" = meta ]; then
 SAFE_PATHS="$C" GOMEMLIMIT=12MiB GOGC=25 "$R/CrashCore" -d "$R" -f "$R/config.yaml" >> "$R/core.log" 2>&1 &
else
 GOMEMLIMIT=12MiB GOGC=25 "$R/CrashCore" run -D "$R" -c "$C/configs/config.json" >> "$R/core.log" 2>&1 &
fi
child=$!
echo "$child" > "$R/core.pid"
for i in 1 2 3 4 5; do
 if curl --noproxy '*' -s -o /dev/null --connect-timeout 1 --max-time 2 http://127.0.0.1:9999/version; then
  if lua -e 'dofile("/data/ShellCrash/ax5/traffic-mode.lua").apply("rule")' && lua "$C/ax5/state.lua" restore; then
   cp "$R/transport-prepared" "$R/transport-runtime"
   printf '1\n' > "$R/service-ready"
   break
  fi
  kill -TERM "$child" 2>/dev/null
  break
 fi
 kill -0 "$child" 2>/dev/null || break
 sleep 1
done
wait "$child"
code=$?
if [ "$ending" = 1 ]; then wait "$child" 2>/dev/null; fi
if [ -f "$R/fakeip.db" ] && [ "$ending" = 1 ]; then
 size=$(wc -c < "$R/fakeip.db")
 if [ "$size" -le 1048576 ]; then cp "$R/fakeip.db" "$C/configs/fakeip.db.new" && mv "$C/configs/fakeip.db.new" "$C/configs/fakeip.db"; fi
fi
if [ "$KIND" = meta ] && [ "$ending" = 1 ] && [ -f "$R/cache.db" ]; then
 size=$(wc -c < "$R/cache.db")
 if [ "$size" -le 524288 ]; then cp "$R/cache.db" "$C/configs/mihomo-cache.db.new" && mv "$C/configs/mihomo-cache.db.new" "$C/configs/mihomo-cache.db"; fi
fi
"$C/ax5/firewall.sh" stop
rm -f "$R/core.pid" "$R/transport-runtime" "$R/service-ready"
if [ "$ending" != 1 ] && [ ! -f "$R/manual-stop" ]; then
 lua "$C/ax5/state.lua" incident "$child" "$code"
fi
if [ "$KIND" = meta ] && [ "$(cat "$R/vm-owner" 2>/dev/null)" = $$ ]; then echo "$vm_old" > /proc/sys/vm/overcommit_memory; rm -f "$R/vm-original" "$R/vm-owner"; fi
exit "$code"
