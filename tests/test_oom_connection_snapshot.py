import unittest,subprocess,tempfile,shlex
from pathlib import Path
class Connections(unittest.TestCase):
 def test_count_unique_destinations_and_tcp_state(self):
  source=(Path(__file__).resolve().parents[1]/'shared/lib/oom-monitor.sh').read_text()
  lines=[x.strip() for x in source.splitlines() if x.strip().startswith('head -4096 "$ct"')]
  with tempfile.TemporaryDirectory()as d:
   p=Path(d)/'conntrack'
   p.write_text('ipv4 2 tcp 6 60 SYN_SENT src=192.0.2.1 dst=198.51.100.1 sport=1 dport=443 src=198.51.100.1 dst=192.0.2.1\nipv4 2 tcp 6 60 SYN_SENT src=192.0.2.1 dst=198.51.100.1 sport=2 dport=443\nipv4 2 udp 17 60 src=192.0.2.1 dst=198.51.100.2 sport=3 dport=9993\n')
   outputs=[subprocess.check_output(['sh','-c',x.replace('"$ct"',shlex.quote(str(p)))],text=True)for x in lines]
   self.assertIn('3 src=192.0.2.1 distinct_dst=2',outputs[0])
   self.assertIn('2 src=192.0.2.1 tcp dport=443 SYN_SENT',outputs[1])
   self.assertIn('1 src=192.0.2.1 udp dport=9993 -',outputs[1])
