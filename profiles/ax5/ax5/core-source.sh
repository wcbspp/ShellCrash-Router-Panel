#!/bin/sh
set -e
export CRASHDIR=/data/ShellCrash-tool
. "$CRASHDIR/configs/ShellCrash.cfg"
. "$CRASHDIR/configs/command.env"
. "$CRASHDIR/libs/web_get_bin.sh"
case "$2" in meta) path=bin/meta/clash-linux-armv7.tar.gz;; singbox) path=bin/singbox/singbox-linux-armv7.tar.gz;; *) exit 2;; esac
mode=$1
limit=18000000
[ "$mode" = fetch ] || limit=16384
seconds=80
[ "$mode" = fetch ] || seconds=12
webget() {
 [ -z "${SC_PINNED_SOURCE:-}" ] || [ "$mode" != fetch ] || bin_url=$SC_PINNED_SOURCE
 request_url=$2;[ -z "${SC_PINNED_SOURCE:-}" ] || [ "$mode" != fetch ] || request_url=$SC_PINNED_SOURCE
 alternate=$(printf '%s' "$request_url" | sed 's#https://raw.githubusercontent.com/juewuy/ShellCrash/#https://testingcf.jsdelivr.net/gh/juewuy/ShellCrash@#')
 if [ -f /tmp/ShellCrash/core.pid ];then
  curl -4 -fsSL --proxy http://127.0.0.1:7890 --noproxy '' --connect-timeout 5 --max-time "$seconds" --max-filesize "$limit" "$request_url" -o "$1" && return 0
 fi
 curl -4 -fsSL --noproxy '*' --connect-timeout 5 --max-time "$seconds" --max-filesize "$limit" "$alternate" -o "$1" ||
 curl -4 -fsSL --noproxy '*' --connect-timeout 5 --max-time "$seconds" --max-filesize "$limit" "$request_url" -o "$1"
}
if [ "$mode" = resolve ];then
 # Read the URL selected by ShellCrash, then pin its branch to an immutable commit.
 webget(){ printf '%s\n' "$2" > "$TMPDIR/core-selected-source"; }
 get_bin "$TMPDIR/core-unused" "$path"
 url=$(cat "$TMPDIR/core-selected-source")
 case "$url" in
  https://raw.githubusercontent.com/juewuy/ShellCrash/*) rest=${url#https://raw.githubusercontent.com/juewuy/ShellCrash/};ref=${rest%%/*};file=${rest#*/};style=raw;;
  https://*.jsdelivr.net/gh/juewuy/ShellCrash@*) rest=${url#*/gh/juewuy/ShellCrash@};ref=${rest%%/*};file=${rest#*/};style=cdn;;
  *) echo 'This source cannot provide an immutable recovery URL.' >&2;exit 1;;
 esac
 printf '%s' "$ref" | grep -Eq '^[a-zA-Z0-9._-]{1,64}$' || exit 1
 if printf '%s' "$ref" | grep -Eq '^[a-f0-9]{40}$';then sha=$ref;else
  endpoint="https://api.github.com/repos/juewuy/ShellCrash/git/ref/heads/$ref"
  # Resolve while the old proxy is still running; this downloads only small metadata.
  if ! curl -4 --proxy http://127.0.0.1:7890 --noproxy '' -fsSL --connect-timeout 4 --max-time 12 --max-filesize 16384 "$endpoint" -o "$TMPDIR/core-source-ref.json";then
   curl -4 --noproxy '*' -fsSL --connect-timeout 4 --max-time 12 --max-filesize 16384 "$endpoint" -o "$TMPDIR/core-source-ref.json"
  fi
  sha=$(lua -e 'local j=require("cjson");local f=assert(io.open("/tmp/ShellCrash/core-source-ref.json"));local d=j.decode(f:read("*a"));print(d.object and d.object.sha or "")')
  printf '%s' "$sha" | grep -Eq '^[a-f0-9]{40}$' || exit 1
 fi
 if [ "$style" = raw ];then printf 'https://raw.githubusercontent.com/juewuy/ShellCrash/%s/%s\n' "$sha" "$file";else printf '%s/%s\n' "${url%%@*}@$sha" "$file";fi
 rm -f "$TMPDIR/core-source-ref.json" "$TMPDIR/core-selected-source"
elif [ "$mode" = version ];then
 get_bin "$TMPDIR/native-core-version" bin/version
 # Read a data assignment; never execute the downloaded version file.
 awk -F= -v k="$2" '$1==k"_v" {gsub(/[ '\''\"]/,"",$2);if($2 ~ /^[v0-9][a-zA-Z0-9.+_-]*$/){print $2;exit}}' "$TMPDIR/native-core-version"
else
 get_bin "$3" "$path"
 printf '%s\n' "$bin_url" > "$TMPDIR/core-download-url"
fi
