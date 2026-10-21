"""Execute the installer's extraction budget gate at actual boundary values."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class CoreInstallMemory(unittest.TestCase):
    def gate(self, available, binary, credit=0):
        source = (ROOT/'ax5/core-install.sh').read_text()
        function = 'core_memory_check() {' + source.split('core_memory_check() {',1)[1].split('manifest() {',1)[0]
        with tempfile.TemporaryDirectory() as td:
            mem = Path(td)/'meminfo'
            mem.write_text('MemAvailable: %s kB\n' % available if available is not None else 'MemFree: 999999 kB\n')
            script = function.replace('/proc/meminfo',str(mem)) + '\nbinary_bytes="$1";core_memory_check "$2"\n'
            return subprocess.run(['sh','-c',script,'test',str(binary),str(credit)],capture_output=True,text=True)
    def test_exact_binary_reserve_and_helper_boundary(self):
        binary=28836019
        required=(binary+1023)//1024+24576+1024
        self.assertEqual(self.gate(required,binary).returncode,0)
        self.assertNotEqual(self.gate(required-1,binary).returncode,0)
    def test_only_exact_removed_archive_bytes_can_be_credited(self):
        binary=28836019;credit=(9025081+1023)//1024
        required=(binary+1023)//1024+24576+1024
        self.assertEqual(self.gate(required-credit,binary,credit).returncode,0)
        self.assertNotEqual(self.gate(required-credit-1,binary,credit).returncode,0)
    def test_post_move_pressure_is_rechecked_without_credit(self):
        binary=28836019
        required=(binary+1023)//1024+24576+1024
        self.assertEqual(self.gate(required-100,binary,101).returncode,0)
        self.assertNotEqual(self.gate(required-100,binary,0).returncode,0)
    def test_missing_available_memory_fails_closed(self):
        self.assertNotEqual(self.gate(None,28836019).returncode,0)

    def test_pinned_cdn_source_and_raw_source_are_accepted(self):
        source = (ROOT/'ax5/core-install.sh').read_text()
        guard = source.split('case "$nextsource" in https://*)',1)[1].split('case "$candidate"',1)[0]
        guard = 'case "$nextsource" in https://*)' + guard
        valid = ['https://testingcf.jsdelivr.net/gh/juewuy/ShellCrash@'+'a'*40+'/bin/core.tar.gz', 'https://raw.githubusercontent.com/juewuy/ShellCrash/'+'a'*40+'/bin/core.tar.gz']
        invalid = ['http://example.org/core', 'https://example.org/core;echo bad', 'https://example.org/core\nINJECT=1', 'https://example.org/a b', 'https://example.org/$(id)']
        for url in valid+invalid:
            result = subprocess.run(['sh','-c','nextsource="$1";'+guard,'test',url],capture_output=True,text=True)
            self.assertEqual(result.returncode==0,url in valid,url)
