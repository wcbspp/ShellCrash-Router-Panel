#!/bin/sh
# One bounded request. No resident collector and no connection payload sent to the browser.
traffic_sample(){
 pid=$(pidof CrashCore | awk '{print $1}')
 [ -n "$pid" ] || { printf '{"running":false}\n';return; }
 mkdir -p /tmp/sc-admin
 sample=/tmp/sc-admin/traffic-$$
 secret=$(sed -n 's/^secret=//p' "$C/configs/ShellCrash.cfg" | head -1)
 if curl --noproxy '*' -fsS --connect-timeout 1 --max-time 2 --max-filesize 1048576 -H "Authorization: Bearer $secret" "http://${PANEL_LAN_IP}:9999/connections" -o "$sample" 2>/dev/null && [ "$pid" = "$(pidof CrashCore | awk '{print $1}')" ];then
  start=$(awk '{sub(/^[0-9]+ \(.*\) /, "");print $20}' "/proc/$pid/stat")
  checked=$(awk '{printf "%.0f",$1*1000}' /proc/uptime)
  awk -v pid="$pid" -v start="$start" -v checked="$checked" '
  {u=$0;d=$0;if(u ~ /"uploadTotal"[ ]*:[ ]*[0-9]+/ && d ~ /"downloadTotal"[ ]*:[ ]*[0-9]+/){
   sub(/^.*"uploadTotal"[ ]*:[ ]*/,"",u);sub(/[^0-9].*$/,"",u);
   sub(/^.*"downloadTotal"[ ]*:[ ]*/,"",d);sub(/[^0-9].*$/,"",d);
   printf "{\"running\":true,\"epoch\":\"%s-%s\",\"checked_ms\":%s,\"upTotal\":%s,\"downTotal\":%s}\n",pid,start,checked,u,d;ok=1
  }} END{if(!ok)print "{\"error\":\"traffic_unavailable\"}"}' "$sample"
 else printf '{"error":"traffic_unavailable"}\n';fi
 rm -f "$sample"
}
