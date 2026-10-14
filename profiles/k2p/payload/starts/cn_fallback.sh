#!/bin/sh
# Derive a small runtime-only fallback from ShellCrash's validated domestic table.
# Subscription and user rules keep their order; only the default exit is preceded.
cn_fallback_prepare(){
 cn_input=$1;cn_output=$2;cn_work=${SC_CN_WORK:-/tmp/panel-dns}
 mkdir -p "$cn_work" || return 1
 . "$CRASHDIR/starts/resource_health.sh";resource_limits
 [ "$rh_limits_valid" = 1 ] || return 1
 cn_available=$(awk '/^MemAvailable:/{print $2;exit}' /proc/meminfo)
 [ "${cn_available:-0}" -ge "$(((rh_protect_mb+1)*1024))" ] || { echo '国内 IP 兜底暂存内存不足，未加载新配置' >&2;return 1; }
 cn_table="$CRASHDIR/configs/cn_ip.txt"
 [ -s "$cn_table" ] && [ "$(wc -c < "$cn_table")" -le 262144 ] || return 1
 awk -f "$CRASHDIR/starts/rules_validate.awk" "$cn_table" > "$cn_work/cn-ip.valid" || { rm -f "$cn_work/cn-ip.valid";return 1; }
 { printf '{"version":3,"rules":[{"ip_cidr":['
   awk 'BEGIN{s=""}{printf "%s\"%s\"",s,$0;s=","}' "$cn_work/cn-ip.valid"
   printf ']}]}\n'; } > "$cn_work/cn-ip.json.new" || return 1
 rm -f "$cn_work/cn-ip.valid"
 awk -v asset="$cn_work/cn-ip.json" -f "$CRASHDIR/starts/cn_fallback.awk" "$cn_input" > "$cn_output.new" || { rm -f "$cn_output.new" "$cn_work/cn-ip.json.new";return 1; }
 mv "$cn_work/cn-ip.json.new" "$cn_work/cn-ip.json" && mv "$cn_output.new" "$cn_output"
}
