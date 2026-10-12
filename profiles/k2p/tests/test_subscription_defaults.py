import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class SubscriptionDefaultsTests(unittest.TestCase):
    def read(self, config):
        with tempfile.TemporaryDirectory() as temp:
            cfg = Path(temp) / 'ShellCrash.cfg'
            cfg.write_text(config+'\nUrl=https://private.example/token\nsecret=private-secret\n')
            r = subprocess.run(['awk', '-v', 'cfgfile='+str(cfg), '-f', str(ROOT/'payload/padavan/subscription_defaults.awk'), str(ROOT/'vendor/ShellCrash-1.9.4/servers.list')], capture_output=True, text=True, check=True)
            self.assertNotIn('private.example', r.stdout)
            self.assertNotIn('private-secret', r.stdout)
            return json.loads(r.stdout)

    def test_automatic_ua_tracks_tool_version_and_current_choices(self):
        result = self.read('core_v=1.12.14\nuser_agent=auto\nserver_link=2\nrule_link=4')
        d = result['defaults']
        self.assertEqual(d['ua'], 'sing-box/singbox/1.12.14')
        self.assertEqual(d['ua_mode'], 'auto')
        self.assertEqual(d['converter'], {k:result['servers'][1][k] for k in ('name', 'url')})
        self.assertEqual(d['template'], result['templates'][3])
        self.assertGreater(len(result['templates']), 4)
        self.assertEqual(d['target'], 'singbox')

    def test_quotes_custom_ua_filters_and_json_escaping(self):
        d = self.read('core_v=1.12.13\nuser_agent=\'clash-verge/v2.4.5\'\ninclude="香港|台湾"\nexclude=\'a"b\\c\'')['defaults']
        self.assertEqual(d['ua'], 'clash-verge/v2.4.5')
        self.assertEqual(d['include'], '香港|台湾')
        self.assertEqual(d['exclude'], 'a"b\\c')
        self.assertEqual(d['ua_mode'], 'custom')

    def test_none_and_out_of_range_converter(self):
        d = self.read('core_v=1.12.13\nuser_agent=none\nserver_link=99')['defaults']
        self.assertEqual(d['ua'], '')
        self.assertEqual(d['ua_mode'], 'none')
        self.assertEqual(d['server_index'], 1)


if __name__ == '__main__':
    unittest.main()
