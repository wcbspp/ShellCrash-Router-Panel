#!/bin/sh
# On AX5, --noproxy alone still enters transparent REDIRECT. Resolve the requested
# host independently and bypass only administrator TCP traffic to that IP/port.
# No service stop, global proxy-mode change, or permanent firewall entry.
set -eu
umask 077
output=$1; url=$2; ua=$3
work=/tmp/ShellCrash/direct-download.$$
mkdir "$work"
tag=SC_SUB_$$
cleanup(){
 if [ -f "$work/bypass" ];then
  while read -r ip port;do iptables -t nat -D SC_AX5_OUT -p tcp -d "$ip" --dport "$port" -m owner --uid-owner 0 -m comment --comment "$tag" -j RETURN 2>/dev/null || :;done < "$work/bypass"
 fi
 rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
# A hard-killed parent must not leave even this narrowly scoped bypass installed.
( sleep 55; cleanup ) </dev/null >/dev/null 2>&1 &
watchdog=$!
lua - "$url" > "$work/host" <<'LUA'
local url=arg[1];local scheme,authority=url:match('^(https?)://([^/]+)')
assert(scheme and not authority:find('[%s@?#]'),'invalid download host')
local host,port=authority:match('^([%w%.%-]+):(%d+)$')
host=host or authority;port=tonumber(port)or(scheme=='https'and 443 or 80)
assert(host:match('^[%w%.%-]+$')and #host<=253 and port>0 and port<=65535,'invalid download host')
print(host);print(port)
LUA
host=$(sed -n '1p' "$work/host");port=$(sed -n '2p' "$work/host")
# Public DNS queries contain the host only, never the subscription path or token.
code=0
curl -4 -fsS --noproxy '*' --connect-timeout 3 --max-time 6 --max-filesize 16384 "https://dns.alidns.com/resolve?name=$host&type=A" -o "$work/dns.json" 2>/dev/null || code=$?
if [ "$code" != 0 ];then kill "$watchdog" 2>/dev/null || :;exit "$code";fi
lua - "$work/dns.json" > "$work/ips" <<'LUA'
local f=assert(io.open(arg[1]));local d=require('cjson').decode(f:read('*a'));f:close()
assert(d.Status==0,'DNS lookup failed');local seen={}
for _,r in ipairs(d.Answer or{})do
 if r.type==1 then
  local a,b,c,e=r.data:match('^(%d+)%.(%d+)%.(%d+)%.(%d+)$')
  a,b,c,e=tonumber(a),tonumber(b),tonumber(c),tonumber(e)
  if a and a>0 and a<224 and b<=255 and c<=255 and e<=255 and a~=10 and a~=127 and not(a==169 and b==254)and not(a==172 and b>=16 and b<=31)and not(a==192 and b==168)and not(a==198 and(b==18 or b==19))and not seen[r.data]then
   seen[r.data]=true;print(r.data)
  end
 end
end
LUA
code=6;attempt=0
while read -r ip;do
 attempt=$((attempt+1));[ "$attempt" -le 2 ] || break
 # Append first so cleanup is safe if a signal arrives immediately after insert.
 printf '%s %s\n' "$ip" "$port" >> "$work/bypass"
 if ! iptables -t nat -I SC_AX5_OUT 1 -p tcp -d "$ip" --dport "$port" -m owner --uid-owner 0 -m comment --comment "$tag" -j RETURN;then code=7;break;fi
 code=0
 curl -4 -fsSL -A "$ua" --noproxy '*' --resolve "$host:$port:$ip" --connect-timeout 5 --max-time 18 --max-filesize 1572864 "$url" -o "$output" 2>/dev/null || code=$?
 [ "$code" != 0 ] || break
done < "$work/ips"
kill "$watchdog" 2>/dev/null || :
exit "$code"
