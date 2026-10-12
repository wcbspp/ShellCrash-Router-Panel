#!/usr/bin/env python3
"""Forced SSH command: store public core/rules only, never router configuration.

Set SC_MIRROR_ROOT in the forced command to the directory served by nginx.
Python 3.6+; no daemon, dependencies or extra listening port.
"""
import hashlib
import os
import re
import sys
import tempfile
from pathlib import Path


def receive(root, command, source):
    match = re.fullmatch(r'(core|cn|rules|info) ([a-f0-9]{64})', command)
    if not match:
        raise ValueError('invalid command')
    kind, expected = match.groups()
    suffix, limit = {'core': ('tar.gz', 10485760), 'cn': ('srs', 1048576), 'rules': ('txt', 262144), 'info': ('txt', 2048)}[kind]
    root = Path(root)
    root.mkdir(parents=True, exist_ok=True)
    name = '{}-{}.{}'.format(kind, expected, suffix)
    fd, temp = tempfile.mkstemp(prefix='.incoming-', dir=str(root))
    try:
        digest = hashlib.sha256()
        total = 0
        with os.fdopen(fd, 'wb') as output:
            while True:
                chunk = source.read(65536)
                if not chunk:
                    break
                total += len(chunk)
                if total > limit:
                    raise ValueError('file too large')
                digest.update(chunk)
                output.write(chunk)
            output.flush()
            os.fsync(output.fileno())
        if not total or digest.hexdigest() != expected:
            raise ValueError('hash mismatch')
        if kind == 'info':
            data = Path(temp).read_text()
            version = re.search(r'^version=(1\.[0-9]{1,2}\.[0-9]{1,3})$', data, re.M)
            core = re.search(r'^sha256=([a-f0-9]{64})$', data, re.M)
            if not version or not core or not (root / ('core-' + core.group(1) + '.tar.gz')).is_file():
                raise ValueError('core metadata invalid')
        os.chmod(temp, 0o644)
        os.replace(temp, str(root / name))
        if kind == 'core':
            blob = hashlib.sha1()
            blob.update(('blob {}\0'.format(total)).encode())
            with (root / name).open('rb') as archive:
                for chunk in iter(lambda: archive.read(65536), b''):
                    blob.update(chunk)
            alias = root / ('blob-' + blob.hexdigest() + '.tar.gz')
            if not alias.exists():
                os.link(str(root / name), str(alias))
        if kind == 'info':
            # Atomic pointer to metadata; immutable archives remain available.
            fd2, temp2 = tempfile.mkstemp(prefix='.meta-', dir=str(root))
            try:
                with os.fdopen(fd2, 'wb') as output:
                    output.write((root / name).read_bytes())
                os.chmod(temp2, 0o644)
                os.replace(temp2, str(root / 'core-info.txt'))
            finally:
                if os.path.exists(temp2):
                    os.unlink(temp2)
        return expected
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


if __name__ == '__main__':
    try:
        print(receive(os.environ.get('SC_MIRROR_ROOT', '/srv/shellcrash-mirror'), os.environ.get('SSH_ORIGINAL_COMMAND', ''), sys.stdin.buffer))
    except (ValueError, OSError):
        print('mirror upload rejected', file=sys.stderr)
        sys.exit(1)
