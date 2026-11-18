#!/bin/sh
# Download the native database bundle, extract only the referenced CN library.
set -e
C=/data/ShellCrash
export CRASHDIR=/data/ShellCrash-tool
. "$CRASHDIR/configs/ShellCrash.cfg"
. "$CRASHDIR/configs/command.env"
. "$CRASHDIR/libs/web_get_bin.sh"
case "$1" in meta) ext=mrs;; singbox) ext=srs;; *) exit 2;; esac
package="$TMPDIR/domain-package.tar.gz"
trap 'rm -f "$package"' EXIT
. /data/ShellCrash/ax5/rule-source.sh
webget(){ rule_source_fetch "$2" "$1" '' 2000000; }
get_bin "$package" "bin/geodata/$ext.tar.gz"
entry=$(tar -tzf "$package" | awk -v name="cn.$ext" '$0==name||$0=="./"name {print}')
[ "$(printf '%s\n' "$entry" | wc -l)" -eq 1 ] && [ -n "$entry" ] || exit 2
tar -xOzf "$package" "$entry" | head -c 2000001 > "$TMPDIR/domain-candidate.$ext"
size=$(wc -c < "$TMPDIR/domain-candidate.$ext")
[ "$size" -gt 1024 ] && [ "$size" -lt 2000000 ] || exit 2
printf '%s\n' "$bin_url" > "$TMPDIR/domain-source"
