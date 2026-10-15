#!/bin/sh
# Sourced by manage.sh: shares its operation lock and service/save functions.
rules_source=${SC_RULES_SOURCE_URL:-https://ispip.clang.cn/all_cn.txt}
[ "${#rules_source}" -le 2048 ] && printf '%s' "$rules_source" | grep -Eq '^https://[^/@#[:space:]]+(/[^[:space:]#]*)?$' || { fail rules_invalid_source;return 1; }
. "$C/starts/rules_path.sh"
rules_ensure || { fail rules_invalid_previous_kept; return 1; }
R="$D/rules"
mkdir -p "$R" || return 1
phase fetching downloading_rules
: > "$D/worker.log"
cat /etc/ssl/certs/*.crt "$C/configs/subscription-ca.pem" > "$R/ca.pem"
# Keep the existing domestic IPv4 source; verify HTTPS and limit the feed size.
if ! curl -4 --cacert "$R/ca.pem" --noproxy '*' -fsS --connect-timeout 10 --max-time 40 --max-filesize 262144 "$rules_source" -o "$R/raw" 2>> "$D/worker.log"; then
 fail rules_download_failed; return 1
fi
[ "$(stat -c %s "$R/raw")" -le 262144 ] && awk -f "$C/starts/rules_validate.awk" "$R/raw" > "$R/new.txt" || { fail rules_invalid_previous_kept; return 1; }
rm -f "$R/raw" "$R/ca.pem"
count=$(wc -l < "$R/new.txt" | tr -d ' ')
hash=$(sha256sum "$R/new.txt" | awk '{print $1}')
if [ "$hash" = "$(sha256sum "$RULES_FILE" | awk '{print $1}')" ]; then
 . "$C/starts/mirror_lib.sh"
 if [ -n "$(mirror_get target)" ]; then
  mirror_required_put rules "$R/new.txt" || { fail mirror_sync_failed_previous_kept; return 1; }
  save_safe || { fail persistent_save_failed; return 1; }
 fi
 phase done rules_unchanged; event 'Domestic IP rules already current; no restart'; return 0
fi
# Native templates retain their explicit rules; startup derives the domestic
# fallback from this table too, so its update also reaches the core.
if [ -f "$C/configs/native-profile" ] || ! grep -q '\"ip_cidr\":' "$C/jsons/config.json";then
 cp "$C/jsons/config.json" "$R/candidate.json" || { fail rules_backup_failed;return 1; }
else
# Replace exactly one embedded table, keeping DNS, nodes and other routing intact.
awk 'FNR==NR{a=a sep "\"" $0 "\"";sep=",";next}
 /^"route":/{if(gsub(/"ip_cidr":\[[^]]*\]/,"\"ip_cidr\":[" a "]")!=1)bad=1; found++}
 {print} END{if(bad||found!=1)exit 1}' "$R/new.txt" "$C/jsons/config.json" > "$R/candidate.json" || { fail configuration_template_missing; return 1; }
fi
if ! cp "$C/jsons/config.json" "$R/previous.json" || ! cp "$RULES_FILE" "$R/previous.txt" || ! cp "$C/configs/rules.meta" "$R/previous.meta"; then fail rules_backup_failed; return 1; fi
was_running=0; [ -z "$(pidof CrashCore)" ] || was_running=1
. "$C/starts/mirror_lib.sh"
if ! mirror_required_put rules "$R/new.txt"; then fail mirror_sync_failed_previous_kept; return 1; fi
configuration_core_prepare || return 1
phase applying validating_rules
if [ "$was_running" = 1 ]; then stop_core || { fail service_stop_failed; return 1; }; fi
# Check only the changed table with the same core, after freeing the old process.
{ printf '{"outbounds":[{"type":"direct","tag":"direct"}],"route":{"rules":[{"ip_cidr":['
 awk 'BEGIN{s=""}{printf "%s\"%s\"",s,$0;s=","}' "$R/new.txt"
 printf '],"outbound":"direct"}]}}\n'; } > "$R/check.json"
if ! configuration_core_materialize || ! /tmp/ShellCrash/CrashCore check -c "$R/check.json" >> "$D/worker.log" 2>&1; then
 rm -f /tmp/ShellCrash/CrashCore; [ "$was_running" = 0 ] || start_core
 fail configuration_check_failed_previous_kept; return 1
fi
cp "$R/candidate.json" "$C/jsons/config.json"
cp "$R/new.txt" "$RULES_FILE"
{ echo "$count"; date '+%Y-%m-%d %H:%M:%S'; echo "$hash"; } > "$C/configs/rules.meta"
if ! save_safe; then
 cp "$R/previous.json" "$C/jsons/config.json"; cp "$R/previous.txt" "$RULES_FILE"; cp "$R/previous.meta" "$C/configs/rules.meta"
 rm -f /tmp/ShellCrash/CrashCore; [ "$was_running" = 0 ] || start_core
 fail persistent_save_failed_previous_kept; return 1
fi
if [ "$was_running" = 1 ] && { ! start_core || [ "$(ipset list cn_ip 2>/dev/null | awk '/^Number of entries:/{print $4}')" != "$count" ]; }; then
 stop_core
 cp "$R/previous.json" "$C/jsons/config.json"; cp "$R/previous.txt" "$RULES_FILE"; cp "$R/previous.meta" "$C/configs/rules.meta"
 save_safe; start_core
 fail start_failed_previous_restored; return 1
fi
[ "$was_running" = 1 ] || rm -f /tmp/ShellCrash/CrashCore
phase done rules_updated
 event "Domestic IP rules validated, saved and applied: $count entries"
