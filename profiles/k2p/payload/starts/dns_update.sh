#!/bin/sh
# Sourced under manage.sh's owned operation lock.
R="$D/dns"
mkdir -p "$R" || { fail invalid_upload; return 1; }
phase applying validating_dns
: > "$D/worker.log"
sort "$D/upload.parts" | awk '!seen[$1]++{printf "%s",$2}' > "$R/upload.b64"
base64 -d "$R/upload.b64" > "$R/filter.gz" 2>/dev/null || { fail invalid_upload; return 1; }
if [ "$(head -c 2 "$R/filter.gz" | base64 | tr -d '\n')" = H4s= ]; then gzip -dc "$R/filter.gz" | head -c 16001 > "$R/filter.txt"; else head -c 16001 "$R/filter.gz" > "$R/filter.txt"; fi
[ "$(stat -c %s "$R/filter.txt")" -le 16000 ] && awk -f "$C/starts/filter_compile.awk" "$R/filter.txt" > "$R/filter.json" || { fail invalid_filter_previous_kept; return 1; }
mode=$3; case "$mode" in real) mode=redir_host;; mix) :;; *) fail invalid_upload; return 1;; esac
current_mode=$(sed -n 's/^dns_mod=//p' "$C/configs/ShellCrash.cfg" | head -1)
if [ "$current_mode" = "$mode" ] && ! grep -q '^disoverride=ON' "$C/configs/ShellCrash.cfg" && [ "$(sha256sum "$R/filter.txt" | cut -d ' ' -f1)" = "$(sha256sum "$C/configs/fake_ip_filter.list" | cut -d ' ' -f1)" ];then
 phase done 'DNS 设置未变化，无需重启';return 0
fi
cp "$C/configs/fake_ip_filter.list" "$R/previous.filter"; cp "$C/configs/ShellCrash.cfg" "$R/previous.cfg"
was_running=0; [ -z "$(pidof CrashCore)" ] || was_running=1
configuration_core_prepare || return 1
if [ "$was_running" = 1 ]; then
 CRASHDIR="$C" sh -c '. "$CRASHDIR/libs/get_config.sh"; . "$CRASHDIR/libs/check_cmd.sh"; . "$CRASHDIR/libs/web_save.sh"; web_save' >> "$D/worker.log" 2>&1 || { fail selection_save_failed;return 1; }
fi
[ "$was_running" = 0 ] || stop_core || { fail service_stop_failed; return 1; }
cp "$R/filter.txt" "$C/configs/fake_ip_filter.list"
sed -i "s/^dns_mod=.*/dns_mod=$mode/; s/^disoverride=.*/disoverride=/" "$C/configs/ShellCrash.cfg"
# Generate and validate the actual overwritten profile before writing flash.
if ! configuration_core_materialize || ! "$C/starts/panel_bfstart.sh" >> "$D/worker.log" 2>&1 || ! configuration_core_materialize || ! CRASHDIR="$C" "$C/starts/bfstart.sh" >> "$D/worker.log" 2>&1 || ! /tmp/ShellCrash/CrashCore check -D /tmp/ShellCrash -C /tmp/ShellCrash/jsons >> "$D/worker.log" 2>&1; then
 cp "$R/previous.filter" "$C/configs/fake_ip_filter.list"; cp "$R/previous.cfg" "$C/configs/ShellCrash.cfg"
 rm -f /tmp/ShellCrash/CrashCore; [ "$was_running" = 0 ] || start_core
 fail configuration_check_failed_previous_kept; return 1
fi
if ! save_safe || { [ "$was_running" = 1 ] && ! start_core; }; then
 stop_core
 cp "$R/previous.filter" "$C/configs/fake_ip_filter.list"; cp "$R/previous.cfg" "$C/configs/ShellCrash.cfg"
 save_safe; [ "$was_running" = 0 ] || start_core
 fail start_failed_previous_restored; return 1
fi
[ "$was_running" = 1 ] || rm -f /tmp/ShellCrash/CrashCore
killall -HUP dnsmasq 2>/dev/null
phase done dns_updated; event "DNS mode and Fake IP exceptions saved and applied: $mode"
