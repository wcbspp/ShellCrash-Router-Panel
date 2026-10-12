#!/bin/sh
# Common package entry point. Device installers retain their preflight and rollback.
set -eu
base=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
[ -f "$base/DEVICE" ] || { echo '请先构建或解压对应机型安装包'; exit 1; }
device=$(cat "$base/DEVICE")
case "$device" in
 ax5) if [ "$#" = 0 ];then set -- auto;fi; exec sh "$base/install.sh" "$@" ;;
 k2p) exec sh "$base/install.sh" "$@" ;;
 *) echo '未知机型，未修改设备'; exit 1;;
esac
