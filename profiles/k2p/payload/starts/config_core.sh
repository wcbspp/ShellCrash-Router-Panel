#!/bin/sh
# Reuse the verified running executable through an open fd, including deleted tmpfs files.
# No resident helper, binary copy or archive download is needed for config-only changes.
configuration_core_prepare(){
 configuration_core_source=''
 core_pid=$(pidof CrashCore | awk '{print $1}')
 core_proc=${SC_PROC_ROOT:-/proc}
 if [ -n "$core_pid" ] && [ -x "$core_proc/$core_pid/exe" ];then
  core_expected=$(sed -n 's/^version=//p' "$C/configs/core-installed.info")
  core_runtime=$("$core_proc/$core_pid/exe" version 2>/dev/null | sed -n 's/^sing-box version //p' | head -1)
  [ -n "$core_expected" ] && [ "$core_runtime" = "$core_expected" ] || { fail core_runtime_mismatch;return 1; }
  exec 3<"$core_proc/$core_pid/exe" || { fail core_runtime_unavailable;return 1; }
  configuration_core_source="$core_proc/$$/fd/3"
  event 'Configuration update reuses running sing-box; no archive staging'
  return 0
 fi
 . "$C/starts/core_release.sh"
 bytes=$(release_get archive_size "$C/configs/core-installed.info")
 case "$bytes" in ''|*[!0-9]*) fail core_download_failed;return 1;;esac
 if [ ! -s /tmp/ShellCrash/CrashCore.tar.gz ];then
  resource_read
  required=$(( (bytes+1023)/1024+rh_protect_mb*1024 ))
  if [ "$rh_available" -lt "$required" ];then
   printf 'Preparing a core archive needs %s KB; available=%s KB; reserve=%s MB\n' "$required" "$rh_available" "$rh_protect_mb" >> "$D/worker.log"
   fail core_staging_memory_insufficient;return 1
  fi
 fi
 "$C/starts/download_core.sh" >> "$D/worker.log" 2>&1 || { fail core_download_failed;return 1; }
}
configuration_core_materialize(){
 if [ -n "$configuration_core_source" ];then
  [ -x "$configuration_core_source" ] || return 1
  ln -sf "$configuration_core_source" /tmp/ShellCrash/CrashCore
 else
  tar -zxf /tmp/ShellCrash/CrashCore.tar.gz -C /tmp/ShellCrash
 fi
}
configuration_core_release(){
 [ -z "$configuration_core_source" ] || { rm -f /tmp/ShellCrash/CrashCore;exec 3<&-;configuration_core_source=''; }
}
