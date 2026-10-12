#!/bin/sh
# Sourced under manage.sh's owned operation lock.
. "$C/starts/core_release.sh"
if [ "$act" = corecheck ]; then
 phase checking checking_core_update
 . "$C/starts/mirror_lib.sh"; mirror_probe
 if release_probe; then phase done core_checked; event 'ShellCrash source checked'; else fail "${probe_error:-core_check_failed}"; fi
 exit 0
fi
phase checking checking_core_update
# Re-fetch on apply; an old page cannot install stale metadata.
release_probe || { fail "${probe_error:-core_check_failed}"; exit 1; }
release="$D/core-check/candidate.info"
current="$C/configs/core-installed.info"
release_valid "$current" || { fail core_current_invalid; exit 1; }
next_ver=$(release_get version "$release"); old_ver=$(release_get version "$current")
next_order=$(printf '%s' "$next_ver" | awk -F. '{print $1*1000000+$2*1000+$3}')
old_order=$(printf '%s' "$old_ver" | awk -F. '{print $1*1000000+$2*1000+$3}')
[ "$next_order" -ge "$old_order" ] || { fail core_downgrade_rejected; exit 1; }
if [ "$(release_get git_blob "$release")" = "$(release_get git_blob "$current")" ]; then phase done core_up_to_date; event 'Core already matches ShellCrash configured source; no restart'; exit 0; fi
was_running=0; [ -z "$(pidof CrashCore)" ] || was_running=1
r="$D/core-update"
mkdir -p "$r"
cp "$current" "$r/previous.info"; cp "$C/configs/ShellCrash.cfg" "$r/previous.cfg"
# Verify rollback metadata now; fetch its archive only with the service stopped.
[ -d /tmp/ShellCrash/jsons ] || { fail core_runtime_config_missing; exit 1; }
old_digest=$(release_get sha256 "$current")
rollback(){
 [ -z "$(pidof CrashCore)" ] || stop_core
 rm -f /tmp/ShellCrash/CrashCore /tmp/ShellCrash/CrashCore.tar.gz
 [ ! -f "$r/previous.tgz" ] || mv "$r/previous.tgz" /tmp/ShellCrash/CrashCore.tar.gz
 cp "$r/previous.info" "$current"; cp "$r/previous.cfg" "$C/configs/ShellCrash.cfg"
 rm -f "$r/candidate.tgz"
 save_safe
 restored=true
 if [ "$was_running" = 1 ]; then start_core || restored=false; fi
 mount -t tmpfs -o remount,rw,size=45M tmpfs /tmp
 event "Core update rolled back; service restored=$restored"
}
phase applying preparing_core_update
# Stopping frees the mapped, unlinked executable before staging two archives.
if [ "$was_running" = 1 ]; then stop_core || { fail service_stop_failed; exit 1; }; fi
[ -s /tmp/ShellCrash/CrashCore.tar.gz ] || "$C/starts/download_core.sh" >> "$D/worker.log" 2>&1 || { rollback; fail core_download_failed; exit 1; }
printf '%s  %s\n' "$old_digest" /tmp/ShellCrash/CrashCore.tar.gz | sha256sum -c - >/dev/null 2>&1 || { rollback; fail core_previous_invalid; exit 1; }
mv /tmp/ShellCrash/CrashCore.tar.gz "$r/previous.tgz" || { [ "$was_running" = 0 ] || start_core; fail core_previous_invalid; exit 1; }
mount -t tmpfs -o remount,rw,size=64M tmpfs /tmp || { rollback; fail core_memory_insufficient; exit 1; }
# Both archive and uncompressed file must fit, leaving 24 MiB for validation/reserve.
binary=33554432; packed=$(release_get archive_size "$release")
[ "$packed" -le 10485760 ] || { rollback; fail core_package_too_large; exit 1; }
available=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
[ -n "$available" ] || available=$(awk '/^MemFree:/{print $2}' /proc/meminfo)
need=$(((binary+packed)/1024+24576))
if [ "${available:-0}" -lt "$need" ]; then rollback; fail core_memory_insufficient; exit 1; fi
phase downloading downloading_core_update
if ! release_download "$release" "$r/candidate.tgz"; then rollback; fail core_download_failed_previous_kept; exit 1; fi
# The source archive must contain exactly one regular executable, never paths/symlinks.
listing=$(tar -ztf "$r/candidate.tgz" 2>/dev/null)
entry=$(tar -ztvf "$r/candidate.tgz" 2>/dev/null)
header_size=$(printf '%s\n' "$entry" | awk '{print $3}')
if [ "$listing" != CrashCore ] || [ "${entry#-}" = "$entry" ] || ! printf '%s' "$header_size" | grep -Eq '^[0-9]{7,8}$' || [ "$header_size" -gt "$binary" ]; then rollback; fail core_archive_invalid; exit 1; fi
binary=$header_size
phase validating validating_core_update
if ! tar -zxf "$r/candidate.tgz" -C /tmp/ShellCrash || [ "$(stat -c %s /tmp/ShellCrash/CrashCore)" -ne "$binary" ]; then rollback; fail core_archive_invalid; exit 1; fi
chmod 700 /tmp/ShellCrash/CrashCore
reported=$(/tmp/ShellCrash/CrashCore version 2>/dev/null | head -1)
[ "$reported" = "sing-box version $next_ver" ] || { rollback; fail core_version_mismatch; exit 1; }
# Full compatibility check while the old core is stopped, with a small GC target.
if ! GOMEMLIMIT=8MiB GOGC=10 /tmp/ShellCrash/CrashCore check -D /tmp/ShellCrash -C /tmp/ShellCrash/jsons >> "$D/worker.log" 2>&1; then rollback; fail core_config_incompatible; exit 1; fi
printf 'sha256=%s\nbinary_size=%s\n' "$(sha256sum "$r/candidate.tgz" | awk '{print $1}')" "$binary" >> "$release"
. "$C/starts/mirror_lib.sh"
# A mirror failure does not invalidate the verified pinned public package.
if remote_ready;then
 if mirror_put core "$r/candidate.tgz" && mirror_put info "$release";then rm -f "$C/configs/mirror.pending";else printf '%s\n' "Core $next_ver synchronization pending" > "$C/configs/mirror.pending";event 'New core verified; mirror upload pending';fi
fi
local_archive=$(sed -n 's/^archive=//p' "$C/configs/core-cache.conf" 2>/dev/null | head -1)
if [ -n "$local_archive" ] && printf '%s' "$local_archive" | grep -Eq '^/[A-Za-z0-9/._-]+$' && ! printf '%s' "$local_archive" | grep -q '\.\.';then
 if cp "$r/candidate.tgz" "$local_archive.new" && printf '%s  %s\n' "$(release_get sha256 "$release")" "$local_archive.new" | sha256sum -c - >/dev/null 2>&1;then mv "$local_archive.new" "$local_archive";else rm -f "$local_archive.new";event 'Optional local archive cache write failed';fi
fi
rm -f /tmp/ShellCrash/CrashCore
mv "$r/candidate.tgz" /tmp/ShellCrash/CrashCore.tar.gz
cp "$release" "$current"
sed -i "s/^core_v=.*/core_v=$next_ver/" "$C/configs/ShellCrash.cfg"
phase starting starting_core_update
if [ "$was_running" = 1 ] && ! start_core; then rollback; fail core_start_failed_previous_restored; exit 1; fi
if ! save_safe; then rollback; fail persistent_save_failed_previous_kept; exit 1; fi
rm -f "$r/previous.tgz"
rm -rf "$r"
mount -t tmpfs -o remount,rw,size=45M tmpfs /tmp
phase done core_updated; event "Compatible core updated to $next_ver; configuration preserved"
