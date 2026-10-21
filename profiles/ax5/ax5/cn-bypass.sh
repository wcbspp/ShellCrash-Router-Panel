#!/bin/sh
C=/data/ShellCrash;D=/tmp/ShellCrash
CB_NAT='SC_AX5_IN SC_AX5_OUT';CB_MANGLE=SC_AX5_UDP;CB_SET=sc_panel_cn
. "$C/ax5/cn-bypass-lib.sh"
cb_safe(){ lua -e 'local M=dofile("/data/ShellCrash/ax5/common.lua");local i=M.load(M.R.."/config-index.json");print(i.cn_eligible or "unknown")';}
CB_VALIDATOR="$C/ax5/rules_validate.awk"
CB_PROTECT=$(lua -e 'print(dofile("/data/ShellCrash/ax5/common.lua").limits().protect_mb)')
if [ "${1:-}" = apply ];then cb_rules "${SC_CN_FLOW_MODE:-rule}" || exit 1;. "$C/ax5/proxy-access.sh";ac_enforce;fi
