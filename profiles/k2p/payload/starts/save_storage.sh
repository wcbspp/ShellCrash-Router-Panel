#!/bin/sh
# Stream Padavan Storage using a smaller bzip2 block to fit K2P RAM.
# EX_TEMPFAIL distinguishes a live persistence owner from a flash failure.
. "${SC_STORAGE_LOCK_HELPER:-/etc/storage/ShellCrash/starts/storage-lock.sh}"
storage_lock_acquire || exit 75
archive=/tmp/shellcrash-storage-save.tar.bz2
trap 'rm -f "$archive"; storage_lock_release' EXIT
set -o pipefail
cd /etc/storage || exit 1
find * -print0 | xargs -0 touch -c -h -t 201001010000.00
find * ! -type d -print0 | sort -z | xargs -0 tar -cf - | bzip2 -4 > "$archive" || exit 1
size=$(stat -c %s "$archive")
limit=${SC_STORAGE_MAX_BYTES:-524288}
case "$limit" in ''|*[!0-9]*)exit 1;;esac
[ "$limit" -ge 16 ] && [ "$limit" -le 524288 ] || exit 1
[ "$size" -ge 16 ] && [ "$size" -le "$limit" ] || { echo "Storage archive too large: $size"; exit 1; }
mkdir -p /tmp/hashes
hash=$(md5sum "$archive" | awk '{print $1}')
verify_storage(){
 index=$(awk -F: '/"Storage"/{sub(/^mtd/,"",$1);print $1;exit}' /proc/mtd)
 case "$index" in ''|*[!0-9]*)echo 'Storage partition unavailable for verification' >&2;return 1;;esac
 actual=$(head -c "$size" "/dev/mtd$index" | md5sum | awk '{print $1}')
 [ "$actual" = "$hash" ] || { echo 'Storage readback failed' >&2;return 1; }
}
if [ "$hash" = "$(cat /tmp/hashes/shellcrash-storage-md5 2>/dev/null)" ];then
 if verify_storage;then echo 'Storage unchanged; no flash write';exit 0;fi
fi
mtd_write write "$archive" Storage || exit 1
[ "${SC_STORAGE_VERIFY:-0}" != 1 ] || verify_storage || exit 1
echo "$hash" > /tmp/hashes/shellcrash-storage-md5
echo "Storage saved: $size bytes"
