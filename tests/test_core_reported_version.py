"""Run the real version gate; source-wide index labels cannot permit downgrade."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
STARTS = ROOT/'profiles/k2p/payload/starts'


class ReportedCoreVersion(unittest.TestCase):
    def check_version(self, report, installed):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            (home/'starts').mkdir()
            shutil.copyfile(STARTS/'panel_env.sh', home/'starts/panel_env.sh')
            env = dict(os.environ, CRASHDIR=tmp, PANEL_LAN_IP='192.0.2.1')
            return subprocess.run(
                ['sh', '-c', '. "$1";release_core_version "$2" "$3"',
                 'test', str(STARTS/'core_release.sh'), report, installed],
                env=env, capture_output=True, text=True)

    def test_real_reported_upgrade_and_equal_version(self):
        for installed in ['1.12.12', '1.12.13']:
            result = self.check_version('sing-box version 1.12.13', installed)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, '1.12.13\n')

    def test_actual_downgrade_rejected_even_when_index_was_newer(self):
        result = self.check_version('sing-box version 1.10.7', '1.12.13')
        self.assertEqual(result.returncode, 3)
        self.assertEqual(result.stdout, '')

    def test_unparseable_or_other_program_report_is_rejected(self):
        for report in ['Mihomo v1.12.13', 'sing-box version 1.12.13 extra',
                       'sing-box version 1.12', 'sing-box version 2.0.0',
                       'sing-box version 1.12.13\n1.14.0']:
            with self.subTest(report=report):
                self.assertEqual(self.check_version(report, '1.12.13').returncode, 2)


if __name__ == '__main__':
    unittest.main()
