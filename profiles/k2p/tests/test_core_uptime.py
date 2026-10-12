import pathlib, re, subprocess, tempfile, unittest

class CoreUptime(unittest.TestCase):
    def test_monotonic_process_age_and_missing_process(self):
        source = (pathlib.Path(__file__).resolve().parents[1] / 'payload/starts/manage.sh').read_text()
        program = re.search(r"core_uptime=\$\(awk '([^']+)'", source).group(1)
        with tempfile.TemporaryDirectory() as d:
            up, stat = pathlib.Path(d)/'uptime', pathlib.Path(d)/'stat'
            up.write_text('90061.75 0\n')
            for ticks, expected in [('100', '90060'), ('9006000', '1'), ('9006200', 'null'), ('broken', 'null')]:
                stat.write_text('42 (a tricky ) name) S ' + '0 '*18 + ticks + '\n')
                result = subprocess.check_output(['awk', program, str(up), str(stat)], text=True)
                self.assertEqual(result, expected)
            stat.write_text('')
            self.assertEqual(subprocess.check_output(['awk', program, str(up), str(stat)], text=True), 'null')
