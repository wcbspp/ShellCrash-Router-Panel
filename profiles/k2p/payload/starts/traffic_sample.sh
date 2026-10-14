#!/bin/sh
# One bounded request. No resident collector and no connection payload sent to the browser.
traffic_sample(){
 pid=$(pidof CrashCore | awk '{print $1}')
 [ -n "$pid" ] || { printf '{"running":false}\n';return; }
 . "$C/starts/resource_health.sh";resource_limits
 available=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
 [ "${available:-0}" -ge "$((rh_protect_mb*1024+3072))" ] || { printf '{"error":"memory_protected"}\n';return; }
 mkdir -p /tmp/sc-admin
 sample=/tmp/sc-admin/traffic-$$
 secret=$(sed -n 's/^secret=//p' "$C/configs/ShellCrash.cfg" | head -1)
 # Old curl ignores max-filesize for chunked bodies. Bound the actual pipe,
 # preserve its exit status, and never parse a partial/oversized response.
 { code=0;curl --noproxy '*' -fsS --connect-timeout 1 --max-time 2 -H "Authorization: Bearer $secret" "http://${PANEL_LAN_IP}:9999/connections" 2>/dev/null || code=$?;printf '%s' "$code" > "$sample.status"; } | head -c 1048577 > "$sample"
 if [ "$(cat "$sample.status")" = 0 ] && [ "$(wc -c < "$sample")" -le 1048576 ] && [ "$pid" = "$(pidof CrashCore | awk '{print $1}')" ];then
  start=$(awk '{sub(/^[0-9]+ \(.*\) /, "");print $20}' "/proc/$pid/stat")
  checked=$(awk '{printf "%.0f",$1*1000}' /proc/uptime)
  # Clash counters surround its one large connections array. Parse only the
  # edges, never clone a megabyte JSON line twice in BusyBox awk.
  { head -c 4096 "$sample";printf '\n';tail -c 4096 "$sample"; } | awk -v pid="$pid" -v start="$start" -v checked="$checked" '
  {if(match($0,/"uploadTotal"[ ]*:[ ]*[0-9]+/)){u=substr($0,RSTART,RLENGTH);sub(/^[^:]*:[ ]*/,"",u)}
   if(match($0,/"downloadTotal"[ ]*:[ ]*[0-9]+/)){d=substr($0,RSTART,RLENGTH);sub(/^[^:]*:[ ]*/,"",d)}}
  END{if(u~/^[0-9]+$/ && d~/^[0-9]+$/)printf "{\"running\":true,\"epoch\":\"%s-%s\",\"checked_ms\":%s,\"upTotal\":%s,\"downTotal\":%s}\n",pid,start,checked,u,d;else print "{\"error\":\"traffic_unavailable\"}"}'
 else printf '{"error":"traffic_unavailable"}\n';fi
 rm -f "$sample" "$sample.status"
}
