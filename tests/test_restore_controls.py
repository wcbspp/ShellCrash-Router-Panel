"""A backup cannot grant or revoke the current device's execution capability."""
from pathlib import Path
import subprocess
import tempfile
import unittest
import shlex

ROOT=Path(__file__).resolve().parents[1]
class LocalRecoveryCapability(unittest.TestCase):
    def test_current_local_gate_wins_over_imported_gate_on_both_workers(self):
        for profile in ['ax5/ax5','k2p/payload/starts']:
            source=(ROOT/'profiles'/profile/'restore-worker.sh').read_text()
            start=source.index('credentials(){');function=source[start:source.index('\n}',start)+2]
            for enabled in [False,True]:
                with self.subTest(profile=profile,enabled=enabled),tempfile.TemporaryDirectory()as tmp:
                    root=Path(tmp);c=root/'app';x=root/'transaction';(c/'configs').mkdir(parents=True);(x/'credentials').mkdir(parents=True)
                    (c/'configs/recovery-enabled').write_text('untrusted imported value')
                    if enabled:(x/'credentials/recovery-enabled').write_text('local capability')
                    script='set -e\nC='+shlex.quote(str(c))+';X='+shlex.quote(str(x))+'\n'+function+'\ncredentials\n'
                    result=subprocess.run(['sh','-c',script],capture_output=True,timeout=5);self.assertEqual(result.returncode,0,result.stderr)
                    gate=c/'configs/recovery-enabled'
                    self.assertEqual(gate.exists(),enabled)
                    if enabled:self.assertEqual(gate.read_text(),'local capability')
if __name__=='__main__':unittest.main()
