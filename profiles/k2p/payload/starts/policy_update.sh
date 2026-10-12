#!/bin/sh
# Sourced by manage.sh under its existing operation lock.
R="$D/policy";mkdir -p "$R" || return 1
phase applying '正在合并域名分流规则'
: > "$D/worker.log";: > "$R/new.rules"
if [ "$GROUP_JOB" != 2 ];then
sort "$D/upload.parts" | awk '!seen[$1]++{printf "%s",$2}' > "$R/upload.b64"
base64 -d "$R/upload.b64" > "$R/new.tsv" 2>/dev/null || { fail invalid_upload;return 1; }
[ "$(stat -c %s "$R/new.tsv")" -le 12000 ] || { fail invalid_upload;return 1; }
fi
if [ "$GROUP_JOB" = 2 ];then
 awk -v main="$PANEL_MAIN_GROUP" -f "$C/starts/group_layout.awk" "$C/jsons/config.json" > "$R/candidate.json" || { fail '策略组结构校验失败';return 1; }
 meta=group-layout;compiled=group-layout;printf '1\n' > "$R/new.tsv";cp "$R/new.tsv" "$R/new.rules"
elif [ "$GROUP_JOB" = 1 ];then
 [ "$(wc -l < "$R/new.tsv")" = 1 ] || { fail invalid_upload;return 1; }
 mode=$(cut -f2 "$R/new.tsv");tag=$(cut -f1 "$R/new.tsv")
 case "$mode" in auto|manual) :;;*) fail invalid_upload;return 1;;esac
 { [ ! -f "$C/configs/group_modes.tsv" ] || awk -F '\t' -v tag="$tag" '$2!=tag' "$C/configs/group_modes.tsv";printf '%s\t%s\n' "$mode" "$tag"; } > "$R/modes.tsv"
 awk -v modes="$R/modes.tsv" -f "$C/starts/group_mode.awk" "$C/jsons/config.json" > "$R/candidate.json" || { fail '策略组参数无效';return 1; }
 # Require the requested tag to occur in the existing selector configuration.
 grep -Fq "\"tag\":\"$tag\"" "$C/jsons/config.json" || { fail '策略组不存在';return 1; }
 meta=group_modes.tsv;compiled=group_modes.tsv
 cp "$R/modes.tsv" "$R/new.tsv";cp "$R/modes.tsv" "$R/new.rules"
else
 meta=policy.tsv;compiled=policy.rules
 awk -v input="$R/new.tsv" -v oldfile="$C/configs/$compiled" -v compiled="$R/new.rules" -v metadata="$R/grouped.tsv" -f "$C/starts/policy_merge.awk" "$C/jsons/config.json" > "$R/candidate.json" || { fail '域名或策略组无效，请检查填写内容';return 1; }
 [ ! -f "$R/grouped.tsv" ] || mv "$R/grouped.tsv" "$R/new.tsv"
fi
if [ "$(sha256sum "$R/candidate.json" | cut -d " " -f1)" = "$(sha256sum "$C/jsons/config.json" | cut -d " " -f1)" ];then phase done '规则未变化，无需重启';return 0;fi
rm -f "$R/previous.tsv" "$R/previous.rules"
cp "$C/jsons/config.json" "$R/previous.json" || return 1
[ ! -f "$C/configs/$meta" ] || cp "$C/configs/$meta" "$R/previous.tsv"
[ ! -f "$C/configs/$compiled" ] || cp "$C/configs/$compiled" "$R/previous.rules"
phase applying '规则合并完成，正在准备校验与备份'
was_running=0;[ -z "$(pidof CrashCore)" ] || was_running=1
configuration_core_prepare || return 1
if [ "$was_running" = 1 ];then
 CRASHDIR="$C" sh -c '. "$CRASHDIR/libs/get_config.sh"; . "$CRASHDIR/libs/check_cmd.sh"; . "$CRASHDIR/libs/web_save.sh"; web_save' >> "$D/worker.log" 2>&1 || { fail '当前选择保存失败';return 1; }
fi
phase applying '正在校验候选配置；代理会短暂重启'
[ "$was_running" = 0 ] || stop_core || { fail service_stop_failed;return 1; }
if ! configuration_core_materialize || ! GOMEMLIMIT=12MiB GOGC=25 /tmp/ShellCrash/CrashCore check -D /tmp/ShellCrash -c "$R/candidate.json" >> "$D/worker.log" 2>&1;then
 rm -f /tmp/ShellCrash/CrashCore;[ "$was_running" = 0 ] || start_core
 fail configuration_check_failed_previous_kept;return 1
fi
cp "$R/candidate.json" "$C/jsons/config.json";cp "$R/new.tsv" "$C/configs/$meta";cp "$R/new.rules" "$C/configs/$compiled"
phase applying '校验通过，正在保存并加载规则'
if ! save_safe || { [ "$was_running" = 1 ] && ! start_core; };then
 stop_core;cp "$R/previous.json" "$C/jsons/config.json"
 rm -f "$C/configs/$meta" "$C/configs/$compiled"
 [ ! -f "$R/previous.tsv" ] || cp "$R/previous.tsv" "$C/configs/$meta"
 [ ! -f "$R/previous.rules" ] || cp "$R/previous.rules" "$C/configs/$compiled"
 save_safe;[ "$was_running" = 0 ] || start_core
 fail start_failed_previous_restored;return 1
fi
[ "$was_running" = 1 ] || rm -f /tmp/ShellCrash/CrashCore
phase done '规则或策略组模式已保存并生效';event 'Domain policies validated, saved and applied'
