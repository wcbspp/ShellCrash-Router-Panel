#!/bin/sh
# Runtime aliases are rebuilt by the matching installer/start hooks. Never
# follow arbitrary links into firmware, credentials, or large RAM files.
set -eu
# The target K2P BusyBox has no readlink applet; ls/sed are available.
stage=$1;model=$2
case "$model" in ax5|k2p) :;;*)exit 2;;esac
find "$stage" -type l -print | while IFS= read -r link;do
 relative=${link#"$stage"/};target=$(LC_ALL=C ls -ld "$link" | sed -n 's/^.* -> //p')
 case "$model:$relative:$target" in
  k2p:jsons/dns.json:/tmp/panel-dns/dns.json|k2p:jsons/log.json:/tmp/panel-dns/log.json|k2p:jsons/experimental.json:/tmp/panel-dns/experimental.json|k2p:jsons/route.json:/tmp/panel-dns/route.json|k2p:jsons/dns.json:/tmp/office-dns/dns.json|k2p:jsons/log.json:/tmp/office-dns/log.json|k2p:jsons/experimental.json:/tmp/office-dns/experimental.json|k2p:jsons/route.json:/tmp/office-dns/route.json|ax5:ShellCrash-tool/jsons/config.json:/data/ShellCrash/configs/config.json|ax5:ShellCrash-tool/yamls/config.yaml:/data/ShellCrash/configs/config.yaml)
   rm -f "$link";;
  *)echo '备份包含未知软链接，未生成新备份；请检查应用目录' >&2;exit 1;;
 esac
done
