#!/bin/sh
# Read only the provider's response headers. Never update or convert a subscription.
set -eu
umask 077
model=$1; action=$2
case "$model" in
 ax5) C=/data/ShellCrash; R=/tmp/ShellCrash; proxy=http://127.0.0.1:7890; url=$(head -c 2049 "$C/configs/subscription" 2>/dev/null || :); protect=$(sed -n 's/.*"protect_mb"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$C/configs/memory.json" 2>/dev/null || :);;
 k2p) C=/etc/storage/ShellCrash; R=/tmp/sc-admin; . "$C/starts/panel_env.sh"; proxy=http://$PANEL_LAN_IP:7890; url=$(head -c 2800 "$C/configs/subscription.url.b64" 2>/dev/null | base64 -d || :); protect=$(sed -n 's/^protect_mb=//p' "$C/configs/memory.conf" 2>/dev/null || :);;
 *) exit 2;;
esac
fingerprint(){ md5sum "$C/configs/subscription" "$C/configs/subscription.url.b64" "$C/configs/subscription-state.json" 2>/dev/null | md5sum | cut -d' ' -f1; }
key=$(fingerprint)
cache=$R/subscription-quota.json
if [ "$action" = read ];then
 if [ "$(cat "$R/subscription-quota.key" 2>/dev/null || :)" = "$key" ] && [ -s "$cache" ];then cat "$cache";else printf '{"state":"unknown"}\n';fi
 exit 0
fi
[ "$action" = check ] || exit 2
case "$url" in http://*|https://*) :;; *) printf '{"state":"no_subscription"}\n';exit 0;;esac
[ "${#url}" -le 2048 ] && ! printf '%s' "$url" | LC_ALL=C grep -q '[[:space:][:cntrl:]]' || { printf '{"state":"no_subscription"}\n';exit 0; }
if [ -e "$R/operation.lock" ];then printf '{"state":"busy"}\n';exit 0;fi
if ! mkdir "$R/quota.lock" 2>/dev/null;then
 owner=$(cat "$R/quota.lock/owner" 2>/dev/null || :)
 case "$owner" in ''|*[!0-9]*) printf '{"state":"busy"}\n';exit 0;;esac
 if kill -0 "$owner" 2>/dev/null;then printf '{"state":"busy"}\n';exit 0;fi
 rm -f "$R/quota.lock/owner" "$R/quota.lock/ca" "$R/quota.lock/result";rmdir "$R/quota.lock" 2>/dev/null || :
 mkdir "$R/quota.lock" 2>/dev/null || { printf '{"state":"busy"}\n';exit 0; }
fi
printf '%s' "$$" > "$R/quota.lock/owner"
trap 'rm -f "$R/quota.lock/owner" "$R/quota.lock/ca" "$R/quota.lock/result"; rmdir "$R/quota.lock" 2>/dev/null || :' EXIT
trap 'exit 1' HUP INT TERM
case "$protect" in ''|*[!0-9]*) protect=14;[ "$model" != k2p ] || protect=12;;esac
available=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
# This header-only read uses the configured protection floor, rather than the
# larger reserve needed to import a full configuration or extract an archive.
if [ "${available:-0}" -lt "$((protect*1024))" ];then printf '{"state":"memory"}\n';exit 0;fi
ua=$(sed -n 's/.*"ua_b64"[[:space:]]*:[[:space:]]*"\([A-Za-z0-9+/=]*\)".*/\1/p' "$C/configs/subscription-state.json" 2>/dev/null | base64 -d || :)
[ "${#ua}" -le 128 ] && ! printf '%s' "$ua" | LC_ALL=C grep -q '[[:cntrl:]]' || ua=''
set -- --noproxy '*'
[ -z "$(pidof CrashCore)" ] || set -- --proxy "$proxy" --noproxy ''
if [ "$model" = k2p ];then
 cat /etc/ssl/certs/*.crt "$C/configs/subscription-ca.pem" > "$R/quota.lock/ca" 2>/dev/null || :
 [ ! -s "$R/quota.lock/ca" ] || set -- "$@" --cacert "$R/quota.lock/ca"
fi
curl -4 -sS -I -L --max-redirs 2 --connect-timeout 3 --max-time 6 -A "$ua" "$@" "$url" 2>/dev/null |
 head -c 8192 | awk -v checked="$(date +%s)" '
 /^HTTP\//{status=$2;delete value;seen=0;bad=0}
 {sub(/\r$/,"")}
 tolower($0) ~ /^subscription-userinfo:/ {
  seen++;line=$0;sub(/^[^:]*:/,"",line);n=split(line,fields,";")
  for(i=1;i<=n;i++){gsub(/^[ \t]+|[ \t]+$/,"",fields[i]);if(fields[i]=="")continue;pairs=split(fields[i],pair,"=");k=tolower(pair[1]);gsub(/[ \t]/,"",k);v=pair[2];gsub(/[ \t]/,"",v)
   if(k=="upload"||k=="download"||k=="total"||k=="expire"){if(pairs!=2 || k in value || v !~ /^[0-9]+$/ || v+0>9007199254740991)bad=1;value[k]=v}}
 }
 END{
  for(k in value)count++;if(status !~ /^2[0-9][0-9]$/)state="request_failed";else if(seen!=1||bad||count==0)state="unavailable";else state="ok"
  printf "{\"state\":\"%s\",\"checked\":%.0f",state,checked
  if(state=="ok")for(k in value)printf ",\"%s\":%.0f",k,value[k]
  printf "}\n"
 }' > "$R/quota.lock/result"
# A concurrently completed subscription must not inherit an older provider's quota.
newkey=$(fingerprint)
[ "$newkey" = "$key" ] || { printf '{"state":"unknown"}\n';exit 0; }
cp "$R/quota.lock/result" "$cache.new";mv "$cache.new" "$cache"
printf '%s' "$key" > "$R/subscription-quota.key";cat "$cache"
