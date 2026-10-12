#!/bin/sh
# Download the native database bundle, extract only the referenced CN library.
set -e
export CRASHDIR=/data/ShellCrash-tool
. "$CRASHDIR/configs/ShellCrash.cfg"
. "$CRASHDIR/configs/command.env"
. "$CRASHDIR/libs/web_get_bin.sh"
case "$1" in meta) ext=mrs;; singbox) ext=srs;; *) exit 2;; esac
package="$TMPDIR/domain-package.tar.gz"
trap 'rm -f "$package"' EXIT
webget() {
 if [ -f "$TMPDIR/core.pid" ];then
  curl -4 -fsSL --proxy http://127.0.0.1:7890 --noproxy '' --connect-timeout 5 --max-time 40 --max-filesize 2000000 "$2" -o "$1" && return 0
 fi
 alternate=$(printf '%s' "$2" | sed 's#https://raw.githubusercontent.com/juewuy/ShellCrash/#https://testingcf.jsdelivr.net/gh/juewuy/ShellCrash@#')
 curl -4 -fsSL --noproxy '*' --connect-timeout 5 --max-time 40 --max-filesize 2000000 "$alternate" -o "$1" || curl -4 -fsSL --noproxy '*' --connect-timeout 5 --max-time 40 --max-filesize 2000000 "$2" -o "$1"
}
get_bin "$package" "bin/geodata/$ext.tar.gz"
entry=$(tar -tzf "$package" | awk -v name="cn.$ext" '$0==name||$0=="./"name {print}')
[ "$(printf '%s\n' "$entry" | wc -l)" -eq 1 ] && [ -n "$entry" ] || exit 2
tar -xOzf "$package" "$entry" > "$TMPDIR/domain-candidate.$ext"
size=$(wc -c < "$TMPDIR/domain-candidate.$ext")
[ "$size" -gt 1024 ] && [ "$size" -lt 2000000 ] || exit 2
printf '%s\n' "$bin_url" > "$TMPDIR/domain-source"
