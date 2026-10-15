#!/bin/sh
# Padavan panel adaptation; configurable LAN address.
PANEL_HOME=${CRASHDIR:-/etc/storage/ShellCrash}
. "$PANEL_HOME/starts/panel_env.sh" || exit 1
# Resolve the existing ShellCrash source, type, compression and architecture.
release_get(){ sed -n "s/^$1=//p" "$2"; }
release_valid(){
 f=$1
 [ -s "$f" ] && [ "$(stat -c %s "$f")" -le 2048 ] || return 1
 [ "$(release_get arch "$f")" = mipsle-softfloat ] && [ "$(release_get variant "$f")" = singbox ] || return 1
 release_get version "$f" | grep -Eq '^1\.[0-9]{1,2}\.[0-9]{1,3}$' || return 1
 release_get sha256 "$f" | grep -Eq '^[a-f0-9]{64}$' || return 1
 return 0
}
native_source(){
 . "$C/configs/ShellCrash.cfg"
 [ "$crashcore" = singbox ] && [ "$cpucore" = mipsle-softfloat ] && [ "${zip_type:-tar.gz}" = tar.gz ] || return 1
 if [ -n "$custcorelink" ]; then native_url=$custcorelink; else
  CRASHDIR=$C
  . "$C/libs/web_get_bin.sh"
  # Reuse ShellCrash's URL selection without downloading a program.
  webget(){ printf '%s\n' "$2" > "$D/core-check/source.url"; }
  get_bin "$D/core-check/unused" "bin/$crashcore/singbox-linux-$cpucore.tar.gz" || return 1
  native_url=$(cat "$D/core-check/source.url")
 fi
 case "$native_url" in
  https://*.jsdelivr.net/gh/juewuy/ShellCrash@*)
   rest=${native_url#*/gh/juewuy/ShellCrash@}; ref=${rest%%/*}; path=${rest#*/}; native_kind=cdn;;
  https://raw.githubusercontent.com/juewuy/ShellCrash/*)
   rest=${native_url#https://raw.githubusercontent.com/juewuy/ShellCrash/}; ref=${rest%%/*}; path=${rest#*/}; native_kind=raw;;
  *) return 1;;
 esac
 printf '%s' "$ref" | grep -Eq '^[A-Za-z0-9._-]{1,64}$' || return 1
 [ "$path" = bin/singbox/singbox-linux-mipsle-softfloat.tar.gz ] || return 1
}
core_cacerts(){ cat /etc/ssl/certs/*.crt "$C/configs/subscription-ca.pem" > "$D/core-check/ca.pem" 2>/dev/null; }
# Firmware curl may only enforce --max-filesize for announced lengths. Keep
# metadata and archive bodies bounded even for lengthless/chunked responses.
release_curl_bounded()(
 destination=$1;limit=$2;shift 2
 case "$limit" in ''|*[!0-9]*)return 2;;esac
 [ "${#limit}" -le 8 ] && [ "$limit" -gt 0 ] && [ "$limit" -le 40000000 ] || return 2
 umask 077
 trap 'rm -f "$destination.curl-status"' EXIT
 (status=0;curl "$@" || status=$?;printf '%s\n' "$status" > "$destination.curl-status") |
  head -c "$((limit+1))" > "$destination"
 if [ "$(cat "$destination.curl-status")" = 0 ] && [ "$(wc -c < "$destination")" -le "$limit" ];then return 0;fi
 rm -f "$destination";return 1
)
core_fetch_metadata(){
 # Metadata may use the running proxy when direct access fails, like ShellCrash.
 release_curl_bounded "$2" 8192 -4 --cacert "$D/core-check/ca.pem" --noproxy '*' -fsSL --connect-timeout 4 --max-time 12 --max-filesize 8192 "$1" && return 0
 [ -n "$(pidof CrashCore)" ] || return 1
 release_curl_bounded "$2" 8192 -4 --cacert "$D/core-check/ca.pem" --noproxy '' --proxy http://${PANEL_LAN_IP}:7890 -fsSL --connect-timeout 4 --max-time 15 --max-filesize 8192 "$1"
}
release_probe(){
 mkdir -p "$D/core-check"
 r="$D/core-check"
 core_cacerts
 if ! native_source; then probe_error=core_source_unsupported; else
  fixed=false
  if printf '%s' "$ref" | grep -Eq '^[a-f0-9]{40}$'; then fixed=true; commit=$ref; else
   if core_fetch_metadata "https://api.github.com/repos/juewuy/ShellCrash/git/ref/heads/$ref" "$r/ref.json"; then
    commit=$(sed -n 's/.*"sha": *"\([a-f0-9]\{40\}\)".*/\1/p' "$r/ref.json" | head -1)
   else commit=''; fi
  fi
  if printf '%s' "$commit" | grep -Eq '^[a-f0-9]{40}$' && core_fetch_metadata "https://api.github.com/repos/juewuy/ShellCrash/contents/$path?ref=$commit" "$r/file.json"; then
   blob=$(sed -n 's/.*"sha": *"\([a-f0-9]\{40\}\)".*/\1/p' "$r/file.json" | head -1)
   size=$(sed -n 's/.*"size": *\([0-9]*\),.*/\1/p' "$r/file.json" | head -1)
   current_blob=$(release_get git_blob "$C/configs/core-installed.info")
   ver=$(release_get version "$C/configs/core-installed.info")
   if [ "$blob" != "$current_blob" ]; then
    if core_fetch_metadata "https://raw.githubusercontent.com/juewuy/ShellCrash/$commit/bin/version" "$r/version"; then ver=$(sed -n 's/^singbox_v=//p' "$r/version" | tr -d "'\"\r" | head -1); else ver=''; fi
   fi
   if printf '%s' "$blob" | grep -Eq '^[a-f0-9]{40}$' && printf '%s' "$size" | grep -Eq '^[0-9]{7,8}$' && printf '%s' "$ver" | grep -Eq '^1\.[0-9]{1,2}\.[0-9]{1,3}$'; then
    if [ "$native_kind" = cdn ]; then source=$(printf '%s' "$native_url" | sed "s|@$ref/|@$commit/|"); else source="https://raw.githubusercontent.com/juewuy/ShellCrash/$commit/$path"; fi
    printf 'version=%s\narch=mipsle-softfloat\nvariant=singbox\narchive_size=%s\ngit_blob=%s\nurl=%s\nfallback1=https://testingcf.jsdelivr.net/gh/juewuy/ShellCrash@%s/%s\nfallback2=https://raw.githubusercontent.com/juewuy/ShellCrash/%s/%s\n' "$ver" "$size" "$blob" "$source" "$commit" "$path" "$commit" "$path" > "$r/candidate.info"
    fits=true; [ "$size" -le 10485760 ] || fits=false
    printf '{"available":true,"version":"%s","git_blob":"%s","size":%s,"fits":%s,"fixed":%s,"checked":%s}\n' "$ver" "$blob" "$size" "$fits" "$fixed" "$(date +%s)" > "$D/core-check.next"
    mv "$D/core-check.next" "$D/core-check.json"
    rm -f "$r/ca.pem" "$r/file.json" "$r/ref.json" "$r/version" "$r/source.url"
    return 0
   fi
  fi
  probe_error=core_check_failed
 fi
 rm -f "$r/ca.pem" "$r/file.json" "$r/ref.json" "$r/version" "$r/candidate.info" "$r/source.url"
 printf '{"available":false,"checked":%s}\n' "$(date +%s)" > "$D/core-check.next"; mv "$D/core-check.next" "$D/core-check.json"
 return 1
}
release_download(){
 f=$1; dest=$2
 mkdir -p "$D/core-check"; core_cacerts
 size=$(release_get archive_size "$f"); expected_sha=$(release_get sha256 "$f"); expected_blob=$(release_get git_blob "$f")
 rm -f "$dest"
 . "$C/starts/mirror_lib.sh"
 if [ "${SC_REMOTE_TRIED:-0}" != 1 ] && [ -n "$expected_sha" ] && remote_fetch core "$expected_sha" tar.gz "$dest" "$size";then rm -f "$D/core-check/ca.pem";return 0;fi
 mirror_url=$(mirror_core_url "$f")
 for field in mirror url fallback1 fallback2; do
  if [ "$field" = mirror ]; then u=$mirror_url; else u=$(release_get "$field" "$f"); fi
  case "$u" in http://*|https://*) :;; *) continue;; esac
  if release_curl_bounded "$dest" "$size" -4 --cacert "$D/core-check/ca.pem" --noproxy '*' -fsSL --connect-timeout 8 --max-time 120 --max-filesize "$size" "$u" && [ "$(stat -c %s "$dest")" -eq "$size" ]; then
   actual_blob=$({ printf 'blob %s\000' "$size"; cat "$dest"; } | openssl dgst -sha1 | awk '{print $NF}')
   actual_sha=$(sha256sum "$dest" | awk '{print $1}')
   if { [ -z "$expected_blob" ] || [ "$actual_blob" = "$expected_blob" ]; } && { [ -z "$expected_sha" ] || [ "$actual_sha" = "$expected_sha" ]; }; then rm -f "$D/core-check/ca.pem"; return 0; fi
  fi
  rm -f "$dest"
 done
 rm -f "$D/core-check/ca.pem"
 return 1
}
