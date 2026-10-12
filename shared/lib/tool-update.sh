#!/bin/sh
# Official stable script updates are separate from the running proxy service.
# Adapted upstream files are retained only when their upstream input is unchanged.
set -e
platform=$1
mode=$2
case "$platform" in
 ax5) C=/data/ShellCrash; T=/data/ShellCrash-tool; D=/tmp/ShellCrash; A=$C/ax5; persistent=1;;
 k2p) C=/etc/storage/ShellCrash; T=$C; D=/tmp/sc-admin; A=$C/starts; persistent=0;;
 *) exit 2;;
esac
mkdir -p "$D"
ownlock=0
if [ "$mode" = update ] && [ "${SC_TOOL_JOB:-0}" != 1 ];then
 mkdir "$D/operation.lock" 2>/dev/null || { echo 'Another administration operation is running.' >&2;exit 1; }
 ownlock=1;[ "$platform" != k2p ] || echo $$ > "$D/operation.lock/owner";date +%s > "$D/operation.lock.time"
fi
release_lock(){ [ "$ownlock" = 0 ] || { rm -f "$D/operation.lock/owner";rmdir "$D/operation.lock" 2>/dev/null || true; }; }
work=$D/tool-update
mkdir -p "$work"
export CRASHDIR=$T
. "$T/configs/ShellCrash.cfg"
[ ! -f "$T/configs/command.env" ] || . "$T/configs/command.env"
. "$T/libs/web_get_bin.sh"
# Force upstream stable; never silently follow master/dev or a custom script URL.
release_type=stable
update_url=https://testingcf.jsdelivr.net/gh/juewuy/ShellCrash@stable
url_id=101
# Prefer the native official CDN list, falling back to the same official repository.
[ -f "$T/configs/servers.list" ] || url_id=''
webget(){
 source_url=$2
 case "$source_url" in https://*.jsdelivr.net/gh/juewuy/ShellCrash@stable/*|https://raw.githubusercontent.com/juewuy/ShellCrash/stable/*) :;; *) source_url="$update_url/${source_url##*/}";; esac
 ca='';[ "$platform" != k2p ] || { cat /etc/ssl/certs/*.crt "$C/configs/subscription-ca.pem" > "$work/ca.pem" 2>/dev/null || true; ca="--cacert $work/ca.pem"; }
 for via in direct proxy;do
  if [ "$via" = direct ];then opts="--noproxy *";else
   [ -n "$(pidof CrashCore)" ] || continue
   if [ "$platform" = ax5 ];then proxyhost=127.0.0.1;else proxyhost=$(nvram get lan_ipaddr);fi
   opts="--noproxy '' --proxy http://$proxyhost:7890"
  fi
  # Quotes are intentional: avoid wildcard expansion and keep proxy selection explicit.
  if [ "$via" = direct ];then
   curl -4 $ca --noproxy '*' -fsSL --connect-timeout 4 --max-time 30 --max-filesize 2097152 "$source_url" -o "$1" && return 0
  else
   curl -4 $ca --noproxy '' --proxy "http://$proxyhost:7890" -fsSL --connect-timeout 4 --max-time 30 --max-filesize 2097152 "$source_url" -o "$1" && return 0
  fi
 done
 return 1
}
finish(){ code=$?;trap - EXIT INT TERM;rm -rf "$work";release_lock;exit "$code"; }
trap finish EXIT
trap 'exit 1' INT TERM
get_bin "$work/version" version
latest=$(tr -d '\r\n' < "$work/version")
printf '%s' "$latest" | grep -Eq '^1\.[0-9]{1,2}\.[0-9]{1,3}release$' || { echo 'Only official stable releases are accepted.' >&2;exit 1; }
current=$(tr -d '\r\n' < "$T/version")
printf '{"available":true,"version":"%s","checked":%s}\n' "$latest" "$(date +%s)" > "$D/tool-check.json.new"
mv "$D/tool-check.json.new" "$D/tool-check.json"
[ "$mode" != check ] || exit 0
if [ "$latest" = "$current" ];then echo 'Official stable tool already installed; service unchanged.';exit 0;fi
order(){ printf '%s' "$1" | sed 's/release$//' | awk -F. '{print $1*1000000+$2*1000+$3}'; }
# Reject downgrade; pre-release installations may move to the equal numeric stable release.
printf '%s' "$current" | grep -Eq '^1\.[0-9]{1,2}\.[0-9]{1,3}(release|beta[0-9]+)$' || exit 1
[ "$(order "$latest")" -ge "$(order "$(printf '%s' "$current" | sed 's/beta[0-9]*$//')")" ] || { echo 'Refusing tool downgrade.' >&2;exit 1; }
# Native terminal sessions read multiple files; do not replace underneath an open menu.
if ps | grep '[s]h .*menu.sh' >/dev/null;then echo 'Close the ShellCrash terminal menu before updating.' >&2;exit 1;fi
get_bin "$work/package.tar.gz" ShellCrash.tar.gz
# No links, special files, nested traversal, absolute paths, or unexpectedly large payloads.
tar -ztf "$work/package.tar.gz" > "$work/list"
awk '/^\// || /(^|\/)\.\.(\/|$)/ || /[^A-Za-z0-9_.\/-]/ {bad=1} END {exit bad}' "$work/list"
tar -ztvf "$work/package.tar.gz" > "$work/verbose"
awk 'substr($1,1,1)!="-" && substr($1,1,1)!="d" {bad=1} {sum+=$3} END {exit bad || sum>3145728}' "$work/verbose"
mkdir "$work/upstream"
tar -xzf "$work/package.tar.gz" -C "$work/upstream"
[ "$(tr -d '\r\n' < "$work/upstream/version")" = "$latest" ] || exit 1
for file in menu.sh start.sh init.sh libs/get_config.sh libs/web_get_bin.sh menus/9_upgrade.sh;do [ -s "$work/upstream/$file" ] || exit 1;done
while read -r expected file;do
 actual=$(sha256sum "$work/upstream/$file" | awk '{print $1}')
 [ "$actual" = "$expected" ] || { echo "Adapter compatibility check failed: $file; current tool retained." >&2;exit 1; }
done < "$A/tool-guards.list"
# Only install upstream script files. Configs, panel, hooks, rules and credentials are separate.
(cd "$work/upstream"; find libs menus starts -type f; printf '%s\n' menu.sh start.sh init.sh version) | sort -u > "$work/files"
while read -r file;do
 if grep -q "  $file$" "$A/tool-guards.list";then cp "$T/$file" "$work/upstream/$file";fi
 case "$file" in *.sh) sh -n "$work/upstream/$file";; esac
done < "$work/files"
# Existing scripts are all present in the supported upstream layout; no untracked deletes.
while read -r file;do [ -f "$T/$file" ] || { echo "New upstream file requires an adapter review: $file" >&2;exit 1; };done < "$work/files"
# Persistent compressed rollback is small on AX5; Padavan Storage is only committed at the end.
if [ "$platform" = ax5 ];then
 available=$(df -k "$C" | awk 'END {print $4}');[ "$available" -ge 384 ] || { echo 'Insufficient space for tool rollback; service unchanged.' >&2;exit 1; }
fi
rollback=$D/tool-previous.tar.gz
[ "$persistent" = 0 ] || rollback=$C/cache/tool-previous.tar.gz
(cd "$T"; tar -czf "$rollback" -T "$work/files")
marker=$D/tool-update-pending
[ "$persistent" = 0 ] || marker=$C/cache/tool-update-pending
printf '%s\n' "$current" > "$marker";sync
success=0
restore(){
 code=$?;trap - EXIT INT TERM
 if [ "$success" != 1 ];then tar -xzf "$rollback" -C "$T" || code=1;sync;if [ "$platform" = k2p ];then "$C/starts/save_storage.sh" || code=1;fi;echo 'Tool update rolled back; proxy service was not restarted.' >&2;fi
 rm -f "$marker" "$rollback";rm -rf "$work";release_lock;exit "$code"
}
trap restore EXIT
# Replace every script atomically, publish the version last.
while read -r file;do
 [ "$file" != version ] || continue
 cp "$work/upstream/$file" "$T/$file.tool-new"
 chmod 700 "$T/$file.tool-new"
 mv "$T/$file.tool-new" "$T/$file"
done < "$work/files"
cp "$work/upstream/version" "$T/version.tool-new";mv "$T/version.tool-new" "$T/version"
if [ "$platform" = k2p ];then "$C/starts/save_storage.sh";else "$C/ax5/tool-sync.sh";sync;fi
success=1
printf 'Official stable tool updated to %s; proxy and other services were not restarted.\n' "$latest"
