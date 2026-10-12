#!/bin/sh
# Stream Padavan Storage using a smaller bzip2 block to fit K2P RAM.
mkdir /tmp/shellcrash-storage-save.lock 2>/dev/null || exit 1
archive=/tmp/shellcrash-storage-save.tar.bz2
trap 'rm -f "$archive"; rmdir /tmp/shellcrash-storage-save.lock 2>/dev/null' EXIT
set -o pipefail
cd /etc/storage || exit 1
find * -print0 | xargs -0 touch -c -h -t 201001010000.00
find * ! -type d -print0 | sort -z | xargs -0 tar -cf - | bzip2 -4 > "$archive" || exit 1
size=$(stat -c %s "$archive")
[ "$size" -ge 16 ] && [ "$size" -le 524288 ] || { echo "Storage archive too large: $size"; exit 1; }
mkdir -p /tmp/hashes
hash=$(md5sum "$archive" | awk '{print $1}')
[ "$hash" = "$(cat /tmp/hashes/shellcrash-storage-md5 2>/dev/null)" ] && { echo 'Storage unchanged; no flash write'; exit 0; }
mtd_write write "$archive" Storage || exit 1
echo "$hash" > /tmp/hashes/shellcrash-storage-md5
echo "Storage saved: $size bytes"
