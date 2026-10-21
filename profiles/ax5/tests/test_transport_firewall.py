import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class TransportFirewall(unittest.TestCase):
    def fixture(self, mixed=True, failed=False, stop=False, access=None):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in ('config/configs', 'config/ax5', 'ram', 'tool/configs', 'bin'):
                (root / name).mkdir(parents=True)
            (root / 'ram/core.pid').write_text(str(os.getpid()))
            (root / 'tool/configs/ShellCrash.cfg').write_text('redir_mod=' + ('混合模式' if mixed else 'Redir模式') + '\n')
            (root / 'config/configs/https-tcp-clients.list').write_text('02:00:00:00:00:01\n')
            if access is not None:(root/'config/configs/proxy-access').write_text(access)
            if stop:
                (root / 'ram/udp-route-owned').touch()
            (root / 'config/ax5/proxy-access.sh').write_text((ROOT/'ax5/proxy-access.sh').read_text())
            log = root / 'commands'
            (root / 'bin/iptables').write_text('#!/bin/sh\necho "iptables $*" >> "$TEST_LOG"\ncase " $* " in *" -D "*) exit 1;; esac\n')
            (root / 'bin/ip').write_text('#!/bin/sh\necho "ip $*" >> "$TEST_LOG"\ncase "$*" in "route show table 21313"|"rule show") exit 0;; "rule add "*) [ "$TEST_FAIL" != 1 ] || exit 1;; esac\nexit 0\n')
            for binary in (root / 'bin').iterdir():
                binary.chmod(0o700)
            text = (ROOT / 'ax5/firewall.sh').read_text()
            for key, value in [('C=/data/ShellCrash', 'C=' + str(root / 'config')), ('R=/tmp/ShellCrash', 'R=' + str(root / 'ram')), ('T=/data/ShellCrash-tool', 'T=' + str(root / 'tool'))]:
                text = text.replace(key, value)
            script = root / 'firewall.sh'
            script.write_text(text)
            result = subprocess.run(['sh', str(script), 'stop' if stop else 'start'], env=dict(os.environ, PATH=str(root / 'bin') + ':' + os.environ['PATH'], SC_ACCESS_RUNTIME=str(root/'ram/access'), TEST_LOG=str(log), TEST_FAIL='1' if failed else '0'), capture_output=True, text=True)
            return result.returncode, log.read_text().splitlines(), (root / 'ram/udp-route-owned').exists(), (root / 'ram/transport-mode').read_text() if (root / 'ram/transport-mode').exists() else ''

    def test_mixed_routes_lan_udp_and_bypasses_private_dns_and_core(self):
        code, calls, owned, mode = self.fixture()
        self.assertEqual(code, 0)
        self.assertEqual(mode, 'mixed\n')
        self.assertTrue(owned)
        self.assertIn('ip route add default dev utun table 21313', calls)
        self.assertIn('ip rule add pref 21313 fwmark 21313 table 21313', calls)
        mark = calls.index('iptables -t mangle -A SC_AX5_UDP -j MARK --set-mark 21313')
        for fragment in ('--mark 0x5343 -j RETURN', '--dport 53 -j RETURN', '-d 172.16.0.0/12 -j RETURN', '-d 192.168.0.0/16 -j RETURN'):
            self.assertTrue(any(fragment in line for line in calls[:mark]))
        self.assertIn('iptables -t mangle -I PREROUTING 1 -i br-lan -p udp -j SC_AX5_UDP', calls)
        self.assertFalse(any('SC_AX5_HTTPS -m mac' in line for line in calls))
        self.assertFalse(any(' -I FORWARD ' in line and 'SC_AX5_FAKE_UDP -j REJECT' in line for line in calls))
        self.assertFalse(any('-t mangle -I OUTPUT' in line for line in calls))

    def test_redir_keeps_compatibility_and_does_not_touch_foreign_routes(self):
        code, calls, owned, mode = self.fixture(mixed=False)
        self.assertEqual(code, 0)
        self.assertEqual(mode, 'redir\n')
        self.assertFalse(owned)
        self.assertFalse(any(line.startswith('ip ') for line in calls))
        self.assertTrue(any('SC_AX5_FAKE_UDP -j REJECT' in line for line in calls))
        self.assertTrue(any('SC_AX5_HTTPS -m mac' in line for line in calls))

    def test_failed_setup_removes_partial_owned_route(self):
        code, calls, owned, mode = self.fixture(failed=True)
        self.assertNotEqual(code, 0)
        self.assertFalse(owned)
        self.assertFalse(mode)
        self.assertIn('ip route del default dev utun table 21313', calls)
        self.assertFalse(any('route flush' in line for line in calls))

    def test_https_fallback_does_not_block_excluded_device_direct_udp(self):
        code,calls,_,_=self.fixture(mixed=False,access='1\n02:11:22:33:44:55\n')
        self.assertEqual(code,0)
        self.assertFalse(any('SC_AX5_HTTPS -m mac' in line for line in calls))

    def test_stop_removes_only_owned_hooks_and_exact_policy_route(self):
        code, calls, owned, mode = self.fixture(stop=True)
        self.assertEqual(code, 0)
        self.assertFalse(owned)
        self.assertFalse(mode)
        self.assertIn('ip rule del pref 21313 fwmark 21313 table 21313', calls)
        self.assertIn('ip route del default dev utun table 21313', calls)
        self.assertFalse(any('route flush' in line for line in calls))


if __name__ == '__main__':
    unittest.main()
