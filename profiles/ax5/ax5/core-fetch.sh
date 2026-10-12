#!/bin/sh
set -e
export CRASHDIR=/data/ShellCrash-tool
. "$CRASHDIR/configs/ShellCrash.cfg"
. "$CRASHDIR/configs/command.env"
. "$CRASHDIR/libs/web_get_bin.sh"
. /data/ShellCrash/ax5/core-env.sh
wanted=$1
case "$wanted" in meta) path=bin/meta/clash-linux-armv7.tar.gz;; singbox) path=bin/singbox/singbox-linux-armv7.tar.gz;; *) echo 'AX5 currently supports sing-box and mihomo tar.gz.' >&2;exit 2;; esac
# Save only trusted installed manifests; do not trust a plaintext mirror to choose a new hash.
"$C/ax5/verify-core.sh"
mkdir -p "$C/cache/targets"
cp "$C/cache/core.env" "$C/cache/targets/$KIND.env"
expected=''
target="$C/cache/targets/$wanted.env"
if [ "$wanted" != "$KIND" ] && [ -f "$target" ];then
 targetkind=$(sed -n 's/^KIND=//p' "$target")
 expected=$(sed -n 's/^HASH=//p' "$target")
 pinned=$(sed -n 's/^SOURCE=//p' "$target")
 [ "$targetkind" = "$wanted" ] && printf '%s' "$expected" | grep -Eq '^[a-f0-9]{64}$' || exit 2
 printf '%s' "$pinned" | grep -Eq '^https://(raw.githubusercontent.com/juewuy/ShellCrash/[a-f0-9]{40}/|[a-z.]+jsdelivr.net/gh/juewuy/ShellCrash@[a-f0-9]{40}/)bin/' || exit 2
else
 latest=$("$C/ax5/core-source.sh" version "$wanted") || latest=''
 if [ "$wanted" = "$KIND" ] && [ -n "$latest" ] && [ "${latest#v}" = "${VERSION#v}" ]; then
  echo 'Current core already matches the ShellCrash source.';exit 0
 fi
 pinned=$("$C/ax5/core-source.sh" resolve "$wanted")
 if [ "$wanted" = "$KIND" ] && [ "$pinned" = "$SOURCE" ];then
  echo 'The immutable source is unchanged; version index may refer to another build.';exit 0
 fi
fi
previous=$(lua -e 'local M=dofile("/data/ShellCrash/ax5/common.lua"); print(M.pid()>0 and 1 or 0)')
finish() {
 code=$?
 trap - EXIT INT TERM
 rm -f "$TMPDIR/Coretmp.tar.gz"
 if [ "$previous" = 1 ] && ! lua -e 'local M=dofile("/data/ShellCrash/ax5/common.lua");os.exit(M.pid()>0 and 0 or 1)';then /etc/init.d/shellcrash start || code=1;fi
 exit "$code"
}
trap finish EXIT
trap 'exit 1' INT TERM
# Stop before downloading into tmpfs and free the old executable. The verified local
# package remains available, so a failed download can restart the previous core.
"$C/ax5/verify-core.sh"
if [ "$previous" = 1 ];then
 /etc/init.d/shellcrash stop
 for n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15;do
  if lua -e 'local M=dofile("/data/ShellCrash/ax5/common.lua");os.exit(M.pid()==0 and 0 or 1)';then break;fi
  sleep 1
 done
 lua -e 'local M=dofile("/data/ShellCrash/ax5/common.lua");os.exit(M.pid()==0 and 0 or 1)'
 rm -f "$R/CrashCore"
fi
obtained=0
if [ -n "$expected" ] && remote_fetch core "$expected" tar.gz "$TMPDIR/Coretmp.tar.gz" 18000000;then obtained=1;fi
if [ "$obtained" != 1 ] && [ -n "$expected" ] && [ -n "$MIRROR" ];then
 if curl -4 --noproxy '*' -fsSL --connect-timeout 5 --max-time 60 --max-filesize 18000000 "$MIRROR/core-$expected.tar.gz" -o "$TMPDIR/Coretmp.tar.gz";then
  actual=$(openssl dgst -sha256 "$TMPDIR/Coretmp.tar.gz" | awk '{print $NF}')
  [ "$actual" != "$expected" ] || obtained=1
 fi
 [ "$obtained" = 1 ] || rm -f "$TMPDIR/Coretmp.tar.gz"
fi
if [ "$obtained" != 1 ];then
 SC_PINNED_SOURCE="$pinned" "$C/ax5/core-source.sh" fetch "$wanted" "$TMPDIR/Coretmp.tar.gz"
 if [ -n "$expected" ];then
  actual=$(openssl dgst -sha256 "$TMPDIR/Coretmp.tar.gz" | awk '{print $NF}')
  [ "$actual" = "$expected" ] || { echo 'Cached target hash mismatch; previous core kept.' >&2;exit 1; }
 fi
fi
bin_url=$pinned
SC_PREVIOUSLY_RUNNING="$previous" "$C/ax5/core-install.sh" "$TMPDIR/Coretmp.tar.gz" "$wanted" "$bin_url"
