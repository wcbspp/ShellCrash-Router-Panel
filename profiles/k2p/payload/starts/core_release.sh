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
release_core_version()(
 # The source-wide version index can describe another build (e.g. full vs
 # mini). Use the hash-verified executable's report and enforce anti-downgrade
 # again before compatibility checking, persistence or starting the service.
 actual=${1#sing-box version }
 case "$actual" in ''|*[!0-9.]*)exit 2;;esac
 [ "$actual" != "$1" ] && printf '%s\n' "$actual" | grep -Eq '^1\.[0-9]{1,2}\.[0-9]{1,3}$' || exit 2
 actual_order=$(printf '%s' "$actual" | awk -F. '{print $1*1000000+$2*1000+$3}')
 previous_order=$(printf '%s' "$2" | awk -F. '{print $1*1000000+$2*1000+$3}')
 [ "$actual_order" -ge "$previous_order" ] || exit 3
 printf '%s\n' "$actual"
)
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
release_stream_core(){
 # Low-memory validation path: retain the old rollback archive, never stage a
 # new compressed archive alongside the candidate executable. The parser keeps
 # the same 24 MiB reserve using the bounded tar header's actual size. Compressed
 # integrity must pass before any candidate executable is run.
 scs_info=$1;scs_output=$2;scs_receipt=$3
 mkdir -p "$D/core-check";core_cacerts
 . "$C/starts/mirror_lib.sh"
 scs_size=$(release_get archive_size "$scs_info")
 scs_blob=$(release_get git_blob "$scs_info")
 scs_sha=$(release_get sha256 "$scs_info")
 scs_webdav_stream(){
  scs_dav_url=$1;scs_dav_sha=$2
  # A configured plain-HTTP repository needs no copied TLS bundle in tmpfs.
  # Rebuild it before any HTTPS/public fallback; never disable TLS verification.
  case "$scs_dav_url" in http://*)rm -f "$D/core-check/ca.pem";scs_ca=/dev/null;;*)core_cacerts;scs_ca="$D/core-check/ca.pem";;esac
  lua "$C/starts/core_stream.lua" "$scs_dav_url" "$scs_size" "$scs_blob" "$scs_dav_sha" "$scs_output" "$scs_receipt" "$scs_ca" "$C/starts/core_stream_extract.lua" "$C/configs/webdav.auth"
 }
 # Ordinary downloads already support authenticated WebDAV; the bounded stream
 # must also use it. Cached metadata never authorizes a different program: both
 # the source's immutable Git blob and archive length must match, and the stream
 # still verifies its own SHA256, pinned blob, gzip and tar before execution.
 if [ "$(remote_transport)" = webdav ] && remote_ready;then
  scs_cached="$D/core-check/stream-cached.info"
  scs_remote_sha=$scs_sha
  if [ -z "$scs_remote_sha" ] && remote_manifest core > "$scs_cached" && release_valid "$scs_cached" &&
     [ "$(release_get git_blob "$scs_cached")" = "$scs_blob" ] && [ "$(release_get archive_size "$scs_cached")" = "$scs_size" ];then
   scs_remote_sha=$(release_get sha256 "$scs_cached")
  fi
  rm -f "$scs_cached"
  if [ -n "$scs_remote_sha" ] && scs_remote_url=$(dav_object core "$scs_remote_sha" tar.gz) &&
     scs_webdav_stream "$scs_remote_url" "$scs_remote_sha";then
   printf 'stream_transport=webdav-cache\n' >> "$scs_receipt"
   rm -f "$D/core-check/ca.pem";return 0
  fi
  rm -f "$scs_output" "$scs_receipt"
  # For an uncached source, only materialize its small compressed package while
  # no candidate executable exists. Keep the old local rollback archive intact.
  # Publish no manifest/pointer until the actual executable has been validated.
  scs_available=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
  scs_seed="$D/core-check/stream-preseed.tgz"
  if [ "${scs_available:-0}" -ge "$(( (scs_size+1023)/1024+24576+8192 ))" ] && release_download "$scs_info" "$scs_seed";then
   scs_seed_sha=$(sha256sum "$scs_seed" | awk '{print $1}')
   scs_uploaded=$(remote_put core "$scs_seed" tar.gz) || scs_uploaded=''
   rm -f "$scs_seed"
   if [ "$scs_uploaded" = "$scs_seed_sha" ] && scs_remote_url=$(dav_object core "$scs_seed_sha" tar.gz);then
    if scs_webdav_stream "$scs_remote_url" "$scs_seed_sha";then
     printf 'stream_transport=webdav-preseed\n' >> "$scs_receipt"
     rm -f "$D/core-check/ca.pem";return 0
    fi
   fi
  fi
  rm -f "$scs_seed" "$scs_output" "$scs_receipt"
  core_cacerts
 fi
 scs_mirror=$(mirror_core_url "$scs_info")
 for scs_field in mirror url fallback1 fallback2;do
  if [ "$scs_field" = mirror ];then scs_url=$scs_mirror;else scs_url=$(release_get "$scs_field" "$scs_info");fi
  case "$scs_url" in http://*|https://*) :;;*)continue;;esac
  if lua "$C/starts/core_stream.lua" "$scs_url" "$scs_size" "$scs_blob" "$scs_sha" "$scs_output" "$scs_receipt" "$D/core-check/ca.pem" "$C/starts/core_stream_extract.lua";then
   rm -f "$D/core-check/ca.pem";return 0
  fi
  rm -f "$scs_output" "$scs_receipt"
 done
 rm -f "$D/core-check/ca.pem";return 1
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
