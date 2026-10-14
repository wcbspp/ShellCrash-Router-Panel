#!/bin/sh
# Padavan panel adaptation; configurable LAN address.
PANEL_HOME=${CRASHDIR:-/etc/storage/ShellCrash}
. "$PANEL_HOME/starts/panel_env.sh" || exit 1
C=/etc/storage/ShellCrash
D=/tmp/sc-admin
mkdir -p "$D"
rm -f /tmp/ShellCrash/manual-stop "$C/configs/panel-disabled"
printf '%s\n' "${SC_CONTROL_SOURCE:-tool}" > /tmp/ShellCrash/control-source
P=/tmp/panel-dns
mkdir -p "$P" /tmp/ShellCrash/ruleset || exit 1
hash=3b83cff9903602f27c3a6737c775f742253a24a60165ff4d9b9ef28ac22bc140
. "$C/starts/domain_asset.sh"
domain_asset_ensure "$hash" /tmp/ShellCrash/ruleset/cn.srs "$P" || { logger -t ShellCrash 'CN domain rules unavailable; proxy start cancelled';exit 1; }
# Restore only bounded, checksum-pinned native assets after a RAM reset.
if [ -f "$C/configs/native-profile" ] && [ -s "$C/configs/native-resources.tsv" ];then
 D=/tmp/sc-admin;mkdir -p "$D";. "$C/starts/native_profile.sh"
 native_resources_prepare "$C/configs/native-resources.tsv" '' "$D/native-boot.tsv" || exit 1
 rm -f "$D/native-boot.tsv"
fi
# Upgrade older panel profiles before ShellCrash splits the configuration.
if [ ! -f "$C/configs/native-profile" ];then
awk -f "$C/starts/route_normalize.awk" "$C/jsons/config.json" > "$P/normalized.json" || exit 1
if [ "$(sha256sum "$P/normalized.json" | awk '{print $1}')" != "$(sha256sum "$C/jsons/config.json" | awk '{print $1}')" ]; then
 binary=/tmp/ShellCrash/CrashCore
 if [ ! -x "$binary" ]; then pid=$(pidof CrashCore | awk '{print $1}'); binary=/proc/$pid/exe; fi
 if [ ! -x "$binary" ] && [ ! -s /tmp/ShellCrash/CrashCore.tar.gz ];then "$C/starts/download_core.sh" || exit 1;fi
 if [ ! -x "$binary" ] && [ -s /tmp/ShellCrash/CrashCore.tar.gz ]; then
  binary=/tmp/ShellCrash/CrashCore
  tar -xOzf /tmp/ShellCrash/CrashCore.tar.gz CrashCore > "$binary" || exit 1
  chmod 700 "$binary"
 fi
 [ -x "$binary" ] || exit 1
 "$binary" check -D /tmp/ShellCrash -c "$P/normalized.json" > "$P/normalize-check.log" 2>&1 || exit 1
 cp "$C/jsons/config.json" "$P/config-before-route.json" || exit 1
 cp "$P/normalized.json" "$C/jsons/config.json" || exit 1
 if ! /sbin/mtd_storage.sh save > "$P/normalize-save.log" 2>&1; then
  cp "$P/config-before-route.json" "$C/jsons/config.json"; exit 1
 fi
fi
rm -f "$P/normalized.json"
fi
# Old panel hooks duplicated the entire route as an incremental custom module.
case "$(LC_ALL=C ls -ld "$C/jsons/route.json" 2>/dev/null | sed -n 's/^.* -> //p')" in
 /tmp/office-dns/route.json|/tmp/panel-dns/route.json) rm -f "$C/jsons/route.json";;
esac
# This exact legacy module contains only the now-canonical CN declaration.
legacy_cn='{"route":{"rule_set":[{"type":"local","tag":"cn","format":"binary","path":"/tmp/ShellCrash/ruleset/cn.srs"}]}}'
if [ -f "$C/jsons/route.json" ] && [ "$(tr -d ' \t\r\n' < "$C/jsons/route.json")" = "$legacy_cn" ]; then
 rm -f "$C/jsons/route.json"
fi
awk -f "$C/starts/filter_compile.awk" "$C/configs/fake_ip_filter.list" > "$P/filter.json" || exit 1
# Preserve LAN-only administration and warning-level bounded logs.
for key in log experimental; do
 awk -v k="$key" '$0 ~ "^\"" k "\":" {sub(/,$/,"");print "{" $0 "}"}' "$C/jsons/config.json" > "$P/$key.json"
 if [ "$key" = experimental ] && ! grep -q '"cache_file"' "$P/$key.json"; then
  sed 's/"experimental":{/"experimental":{"cache_file":{"enabled":true,"path":"\/tmp\/ShellCrash\/fakeip.db","store_fakeip":true},/' "$P/$key.json" > "$P/experimental.cached.json" || exit 1
  mv "$P/experimental.cached.json" "$P/experimental.json"
 fi
 ln -sf "$P/$key.json" "$C/jsons/$key.json"
done
mode=$(sed -n 's/^dns_mod=//p' "$C/configs/ShellCrash.cfg" | head -1)
case "$mode" in mix|fake-ip|redir_host) :;; *) mode=mix;; esac
{
 printf '{"dns":{"servers":[{"type":"udp","tag":"dns-direct","server":"223.5.5.5"},{"type":"tcp","tag":"dns-proxy","server":"8.8.8.8","detour":"%s"},{"type":"udp","tag":"dns_resolver","server":"223.5.5.5"}' "$PANEL_MAIN_GROUP"
 [ "$mode" = redir_host ] || printf ',{"type":"fakeip","tag":"dns-fake","inet4_range":"198.18.0.0/15"}'
 printf '],"rules":[{"clash_mode":"Direct","server":"dns-direct"},{"domain":["localhost"],"domain_suffix":["lan","local","localdomain","home.arpa"],"server":"dns-direct"},'
 [ "$mode" = fake-ip ] || printf '{"rule_set":["cn"],"server":"dns-direct"},'
 if [ "$mode" != redir_host ]; then
  if [ "$(cat "$P/filter.json")" != '{"domain":[],"domain_suffix":[],"domain_regex":[]}' ]; then sed 's/}$/,"server":"dns-proxy"},/' "$P/filter.json"; fi
  printf '{"query_type":["A"],"server":"dns-fake","rewrite_ttl":1},'
 fi
 printf '{"query_type":["AAAA"],"action":"reject"}],"final":"dns-proxy","strategy":"ipv4_only"}}\n'
} > "$P/dns.json"
ln -sf "$P/dns.json" "$C/jsons/dns.json"
