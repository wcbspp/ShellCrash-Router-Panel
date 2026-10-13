import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class FallbackTests(unittest.TestCase):
    def run_rules(self, clients, mode='rule', action='https'):
        with tempfile.TemporaryDirectory() as temp:
            temp = Path(temp)
            config = temp / 'config'
            config.mkdir()
            (config / 'configs').mkdir()
            ram = temp / 'ram'
            ram.mkdir()
            (ram / 'core.pid').write_text(str(os.getpid()))
            (ram / 'traffic-mode').write_text(mode)
            if clients is not None:
                (config / 'configs/https-tcp-clients.list').write_text(clients)
            log = temp / 'commands'
            binary = temp / 'iptables'
            binary.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "' + str(log) + '"\ncase " $* " in *" -D "*) exit 1;; esac\nexit 0\n')
            binary.chmod(0o700)
            source = (ROOT / 'ax5/firewall.sh').read_text().replace('C=/data/ShellCrash', 'C=' + str(config)).replace('R=/tmp/ShellCrash', 'R=' + str(ram))
            script = temp / 'firewall.sh'
            script.write_text(source)
            result = subprocess.run(['sh', str(script), action], env=dict(os.environ, PATH=str(temp) + ':' + os.environ['PATH']), capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            return log.read_text().splitlines()

    def test_absent_config_does_not_change_other_clients(self):
        commands = self.run_rules(None)
        self.assertFalse(any(line.startswith('-N ') or line.startswith('-A ') for line in commands))

    def test_only_valid_unique_clients_and_udp443(self):
        commands = self.run_rules('02:00:00:00:00:01\n02:00:00:00:00:01\ninvalid; touch /tmp/should-not-exist\n')
        rules = [line for line in commands if line.startswith('-A SC_AX5_HTTPS')]
        self.assertEqual(len(rules), 1)
        self.assertIn('--mac-source 02:00:00:00:00:01', rules[0])
        self.assertIn('-p udp --dport 443', rules[0])
        self.assertIn('--reject-with icmp-port-unreachable', rules[0])
        self.assertFalse(any('-t nat' in line for line in commands))
        self.assertFalse(any('9993' in line for line in commands))

    def test_rule_activation_after_direct_does_not_use_stale_mode(self):
        commands = self.run_rules('02:00:00:00:00:01\n', 'direct', 'start')
        self.assertTrue(any(line.startswith('-A SC_AX5_HTTPS') for line in commands))

    def test_direct_mode_removes_fallback(self):
        commands = self.run_rules('02:00:00:00:00:01\n', 'direct')
        self.assertTrue(any(line.startswith('-D FORWARD') for line in commands))
        self.assertFalse(any(line.startswith('-N ') or line.startswith('-A ') for line in commands))


if __name__ == '__main__':
    unittest.main()
