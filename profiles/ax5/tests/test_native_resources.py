"""Missing template data must not exhaust RAM or publish an incomplete database."""
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class NativeResourcesTests(unittest.TestCase):
    def run_fixture(self, available=65536, free=8192, size=65536, cached=False):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        p = Path(temp.name)
        c, r, tool, commands = (p / n for n in ('config', 'ram', 'tool', 'bin'))
        for folder in (c / 'ruleset/native', r, tool / 'configs', tool / 'libs', commands):
            folder.mkdir(parents=True, exist_ok=True)
        (tool / 'configs/ShellCrash.cfg').write_text('')
        (tool / 'libs/web_get_bin.sh').write_text(
            'get_bin(){ touch "'+str(p/'requested')+'"; head -c '+str(size)+' /dev/zero > "$1"; }\n')
        (commands / 'lua').write_text('#!/bin/sh\ncat >/dev/null\necho GeoSite.dat:geosite.dat:8388608\n')
        (commands / 'df').write_text('#!/bin/sh\nprintf "Filesystem 1K-blocks Used Available Use%% Mounted\\nfixture 16384 0 '+str(free)+' 0%% /fixture\\n"\n')
        for command in commands.iterdir():
            command.chmod(0o700)
        mem = p / 'meminfo'
        mem.write_text('MemAvailable: '+str(available)+' kB\n')
        script = (ROOT / 'ax5/native-resources.sh').read_text()
        script = script.replace('C=/data/ShellCrash', 'C='+str(c)).replace('R=/tmp/ShellCrash', 'R='+str(r))
        script = script.replace('CRASHDIR=/data/ShellCrash-tool', 'CRASHDIR='+str(tool)).replace('/proc/meminfo', str(mem))
        f = p / 'run.sh'
        f.write_text(script)
        if cached:
            (c/'ruleset/native/GeoSite.dat').write_bytes(b'cached-database')
        result = subprocess.run(['sh', str(f)], env=dict(os.environ, PATH=str(commands)+os.pathsep+os.environ['PATH']), capture_output=True, text=True)
        self.assertFalse(list(r.glob('native-geodata.*')), 'RAM staging must be removed on all exits')
        self.assertFalse((c/'ruleset/native/GeoSite.dat.new').exists())
        return p, c, r, result

    def test_low_memory_refuses_before_download(self):
        p, c, r, result = self.run_fixture(available=16000)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('内存预算不足', result.stderr)
        self.assertFalse((p/'requested').exists())
        self.assertFalse((c/'ruleset/native/GeoSite.dat').exists())

    def test_low_flash_does_not_publish_download(self):
        p, c, r, result = self.run_fixture(free=64)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('闪存空间不足', result.stderr)
        self.assertTrue((p/'requested').exists())
        self.assertFalse((c/'ruleset/native/GeoSite.dat').exists())

    def test_invalid_size_is_not_cached(self):
        p, c, r, result = self.run_fixture(size=16)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('大小不符合', result.stderr)
        self.assertFalse((c/'ruleset/native/GeoSite.dat').exists())

    def test_valid_download_is_published_and_copied_to_runtime(self):
        p, c, r, result = self.run_fixture()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((c/'ruleset/native/GeoSite.dat').stat().st_size, 65536)
        self.assertEqual((r/'GeoSite.dat').stat().st_size, 65536)

    def test_cached_database_does_not_need_download_budget(self):
        p, c, r, result = self.run_fixture(available=1000, free=0, cached=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((p/'requested').exists())
        self.assertEqual((r/'GeoSite.dat').read_bytes(), b'cached-database')


if __name__ == '__main__':
    unittest.main()
