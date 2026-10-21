"""Upgrade startup and rollback need the same executable-FD helper as config edits."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class UpgradeHelperDispatch(unittest.TestCase):
    def test_upgrade_loads_materialize_and_release_before_dispatch(self):
        source = (ROOT / 'payload/starts/manage.sh').read_text()
        dispatch = next(line for line in source.splitlines()
                        if line.startswith('case "$act" in') and
                        '. "$C/starts/config_core.sh"' in line)
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'starts').mkdir()
            ram = root / 'ram'
            ram.mkdir()
            helper = (ROOT / 'payload/starts/config_core.sh').read_text()
            (root / 'starts/config_core.sh').write_text(
                helper.replace('/tmp/ShellCrash', str(ram)))
            exe = root / 'verified-core'
            exe.write_text('#!/bin/sh\nexit 0\n')
            exe.chmod(0o700)
            script = dispatch + '''
configuration_core_source="$C/verified-core"
configuration_core_materialize || exit 1
test -x "$C/ram/CrashCore" || exit 2
configuration_core_release
test ! -L "$C/ram/CrashCore"
'''
            result = subprocess.run(['sh', '-c', 'C="$1";act=coreupdate;\n' + script,
                                     'test', str(root)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(exe.exists(), 'Release must not remove verified source')

    def test_start_keeps_verified_fd_in_boot_child(self):
        source = (ROOT / 'payload/starts/manage.sh').read_text()
        function = 'start_core(){' + source.split('start_core(){', 1)[1].split('save_safe(){', 1)[0]
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'starts').mkdir()
            (root / 'configs').mkdir()
            (root / 'configs/ShellCrash.cfg').write_text('secret=fixture\n')
            boot = root / 'starts/panel_boot.sh'
            boot.write_text('#!/bin/sh\ncat <&3 > "$C/child-read" || exit 1\n')
            boot.chmod(0o700)
            (root / 'verified').write_text('verified inode\n')
            script = function + '\nC="$1";D="$1";export C;configuration_core_source=verified;configuration_core_materialize(){ :; };pidof(){ echo 1; };curl(){ :; };exec 3<"$C/verified";start_core;exec 3<&-\n'
            result = subprocess.run(['sh', '-c', script, 'test', str(root)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((root / 'child-read').read_text(), 'verified inode\n')

    def test_missing_verified_handoff_refuses_download_fallback(self):
        source = (ROOT / 'payload/starts/panel_boot.sh').read_text()
        block = source.split('if [ "$SC_REUSE_RUNNING_CORE" = 1 ];then', 1)[1].split('[ -f "$CRASHDIR/configs/panel-disabled" ]', 1)[0]
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'starts').mkdir()
            download = root / 'starts/download_core.sh'
            download.write_text('#!/bin/sh\ntouch "$CRASHDIR/downloaded"\n')
            download.chmod(0o700)
            script = 'CRASHDIR="$1";export CRASHDIR;SC_REUSE_RUNNING_CORE=1; if [ "$SC_REUSE_RUNNING_CORE" = 1 ];then' + block.replace('/tmp/ShellCrash/CrashCore', str(root / 'missing')).replace('/tmp/sc-admin/events.log', str(root / 'events.log'))
            result = subprocess.run(['sh', '-c', script, 'test', str(root)], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((root / 'downloaded').exists())
            self.assertIn('refusing archive fallback', (root / 'events.log').read_text())
