#!/bin/sh
# Sourced by manage.sh while holding its operation lock. Never eval UI input.
settings=$(printf '%s\n' "$3" | awk -F'[wpc]' '
 /^w(0|[1-9][0-9]?)p(0|[1-9][0-9]?)c(0|[1-9][0-9]?)$/ && NF==4 {
  w=$2+0; p=$3+0; c=$4+0
  if(p>=12 && p<w && w<=64 && (c==0 || (c>=w && c<=96))) print w,p,c
 }')
[ -n "$settings" ] || { fail memory_settings_invalid; return 1; }
. "$C/starts/resource_health.sh"
resource_read
[ "$rh_available" -ge 12288 ] || { fail memory_settings_low; return 1; }
if [ "$rh_limits_valid" = 1 ] && [ "$settings" = "$rh_warning_mb $rh_protect_mb $rh_cleanup_mb" ]; then
 phase done memory_settings_unchanged
 return 0
fi
set -- $settings
settings_file="$C/configs/memory.conf"
settings_next="$C/configs/memory.conf.next"
printf 'warning_mb=%s\nprotect_mb=%s\ncleanup_mb=%s\n' "$1" "$2" "$3" > "$settings_next" || { fail memory_settings_save_failed; return 1; }
chmod 600 "$settings_next"
if [ -f "$settings_file" ] && [ "$(cat "$settings_file")" = "$(cat "$settings_next")" ]; then
 rm -f "$settings_next"
 phase done memory_settings_unchanged
 return 0
fi
settings_had=0
if [ -f "$settings_file" ]; then
 cp "$settings_file" "$D/memory.previous" || { rm -f "$settings_next"; fail memory_settings_save_failed; return 1; }
 settings_had=1
fi
phase saving memory_settings_saving
if ! mv "$settings_next" "$settings_file"; then
 rm -f "$settings_next" "$D/memory.previous"
 fail memory_settings_save_failed
 return 1
fi
if ! save_safe; then
 if [ "$settings_had" = 1 ]; then mv "$D/memory.previous" "$settings_file"; else rm -f "$settings_file"; fi
 fail memory_settings_save_failed
 return 1
fi
rm -f "$D/memory.previous"
phase done memory_settings_saved
