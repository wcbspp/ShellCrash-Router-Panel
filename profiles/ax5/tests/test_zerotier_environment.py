import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class EnvironmentTests(unittest.TestCase):
    def test_login_does_not_mix_native_and_entware_libraries(self):
        with tempfile.TemporaryDirectory() as temp:
            temp = Path(temp)
            uci = temp / 'uci'
            uci.write_text('#!/bin/sh\ncase "$*" in *mixbox.main.path) echo /etc/mixbox;; *profilepath) echo :/opt/bin:/opt/sbin;; esac\n')
            uci.chmod(0o700)
            profile = temp / 'profile'
            profile.write_text((ROOT / 'ax5/ssh-profile.sh').read_text().replace('/sbin/uci', str(uci)))
            for inherited, expected in [('', 'unset'), ('/usr/lib:/lib:/opt/lib', 'unset'), ('/custom/library', '/custom/library')]:
                env = dict(os.environ, LD_LIBRARY_PATH=inherited)
                result = subprocess.run(['sh', '-c', '. "$1"; printf "%s" "${LD_LIBRARY_PATH-unset}"', 'sh', str(profile)], env=env, capture_output=True, text=True, check=True)
                self.assertEqual(result.stdout, expected)

    def test_daemon_and_network_status_are_separate(self):
        with tempfile.TemporaryDirectory() as temp:
            temp = Path(temp)
            output = temp / 'status'
            base = temp / 'base'
            base.write_text('pidof(){ echo 777; }\nmbdb(){ case "$1" in export) echo networkid=0000000000000000;; set) printf "%s" "$2" > "' + str(output) + '";; esac; }\n')
            cli = temp / 'cli'
            cli.write_text('#!/bin/sh\n[ -z "${LD_LIBRARY_PATH:-}" ] || exit 1\ncase "$1" in info) echo "200 info dummy 1.16.0 $TEST_ONLINE";; listnetworks) echo "200 listnetworks 0000000000000000 test 00:00:00:00:00:00 $TEST_NETWORK PRIVATE zt0 172.22.0.1/16";; esac\n')
            cli.chmod(0o700)
            script = temp / 'zerotier.sh'
            script.write_text((ROOT / 'zerotier/zerotier.sh').read_text().replace('/etc/mixbox/bin/base', str(base)).replace('ZTC=/opt/bin/zerotier-cli', 'ZTC=' + str(cli)))
            for online, network, expected in [('ONLINE', 'OK', '|1'), ('OFFLINE', 'OK', '|0'), ('ONLINE', 'ACCESS_DENIED', '|0'), ('ONLINE', 'REQUESTING_CONFIGURATION', '|0')]:
                env = dict(os.environ, LD_LIBRARY_PATH='/usr/lib:/lib:/opt/lib', TEST_ONLINE=online, TEST_NETWORK=network)
                subprocess.run(['sh', str(script), 'status'], env=env, capture_output=True, text=True, check=True)
                self.assertTrue(output.read_text().endswith(expected), (online, network, output.read_text()))


if __name__ == '__main__':
    unittest.main()
