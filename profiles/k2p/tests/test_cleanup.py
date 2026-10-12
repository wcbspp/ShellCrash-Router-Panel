"""Exercise safe cleanup with isolated paths; never touch router state."""
import json,subprocess,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class CleanupTests(unittest.TestCase):
 def setUp(self):
  self.t=tempfile.TemporaryDirectory();self.addCleanup(self.t.cleanup);self.p=Path(self.t.name)
  for name in ['job','tmp/ShellCrash','tmp/dnsmasq.dom','etc/storage/dnsmasq','proc/net','proc/sys/net/netfilter']:(self.p/name).mkdir(parents=True)
  (self.p/'proc/meminfo').write_text('MemFree: 8000 kB\nMemAvailable: 18000 kB\n')
  (self.p/'proc/net/sockstat').write_text('TCP: alloc 2 mem 3\nUDP: mem 1\n')
  (self.p/'proc/sys/net/netfilter/nf_conntrack_count').write_text('5')
  (self.p/'etc/dnsmasq.conf').write_text('')
  (self.p/'etc/storage/dnsmasq/dnsmasq.conf').write_text('')
  s=(ROOT/'payload/starts/resource_health.sh').read_text()
  for src in ['/proc/','/tmp/','/etc/']:s=s.replace(src,str(self.p)+src)
  s=s.replace('stat -c %s', 'python3 -c \"import os,sys; print(os.stat(sys.argv[1]).st_size)\"')
  s=s.replace('/usr/sbin/nvram get ss_enable','printf 0').replace('pidof CrashCore','printf 77')
  (self.p/'helper.sh').write_text(s)
 def run_cleanup(self,extra=''):
  return subprocess.run(['sh','-c',f'. "{self.p}/helper.sh"; D="{self.p}/job"; rh_manual=1; {extra} resource_cleanup'],capture_output=True,text=True)
 def test_remove_cache_trim_keep_evidence_and_noop(self):
  cache=self.p/'tmp/ShellCrash/CrashCore.tar.gz';cache.write_bytes(b'x'*8192)
  log=self.p/'tmp/ShellCrash/core.log';log.write_bytes(b'a'*70000+b'last-evidence')
  legacy=self.p/'tmp/dnsmasq.dom/gfwlist_list.conf';legacy.write_bytes(b'z'*4096)
  evidence=self.p/'job/incidents.log';evidence.write_text('preserve')
  config=self.p/'etc/storage/config';config.write_text('preserve')
  self.assertEqual(self.run_cleanup().returncode,0)
  result=json.loads((self.p/'job/cleanup.json').read_text());self.assertEqual(result['removed'],2);self.assertEqual(result['trimmed'],1)
  self.assertEqual(log.stat().st_size,32768);self.assertTrue(log.read_bytes().endswith(b'last-evidence'))
  self.assertEqual(evidence.read_text(),'preserve');self.assertEqual(config.read_text(),'preserve')
  self.assertFalse((self.p/'job/operation.lock').exists());self.assertFalse((self.p/'job/cleanup.lock').exists())
  self.assertEqual(self.run_cleanup().returncode,0);self.assertEqual(json.loads((self.p/'job/cleanup.json').read_text())['file_bytes'],0)
 def test_operation_and_bootstrap_busy_keep_files(self):
  cache=self.p/'tmp/ShellCrash/CrashCore.tar.gz';cache.write_text('in-use')
  lock=self.p/'job/operation.lock';lock.mkdir();(lock/'owner').write_text('123')
  self.assertNotEqual(self.run_cleanup().returncode,0);self.assertTrue(cache.exists())
  (lock/'owner').unlink();lock.rmdir();(self.p/'tmp/shellcrash-bootstrap.lock').mkdir()
  self.assertNotEqual(self.run_cleanup().returncode,0);self.assertTrue(cache.exists());self.assertFalse(lock.exists())
 def test_referenced_or_unknown_dns_and_symlinks_preserved(self):
  legacy=self.p/'tmp/dnsmasq.dom/gfwlist_list.conf';legacy.write_text('keep')
  (self.p/'etc/dnsmasq.conf').write_text('conf-file=another.conf\n')
  target=self.p/'private';target.write_bytes(b'x'*80000)
  (self.p/'tmp/ShellCrash/core.log').symlink_to(target)
  self.assertEqual(self.run_cleanup().returncode,0);self.assertTrue(legacy.exists());self.assertEqual(target.stat().st_size,80000)
  (self.p/'etc/dnsmasq.conf').unlink();self.assertEqual(self.run_cleanup().returncode,0);self.assertTrue(legacy.exists())
 def test_stale_cleanup_lock_recovered(self):
  lock=self.p/'job/cleanup.lock';lock.mkdir();(lock/'owner').write_text('99999999')
  self.assertEqual(self.run_cleanup().returncode,0);self.assertFalse(lock.exists())
 def test_automatic_cleanup_records_only_actual_work(self):
  cache=self.p/'tmp/ShellCrash/CrashCore.tar.gz';cache.write_bytes(b'x'*8192)
  self.assertEqual(self.run_cleanup('rh_manual=0;').returncode,0)
  result=json.loads((self.p/'job/cleanup.json').read_text());self.assertEqual(result['manual'],0);self.assertEqual(result['file_bytes'],8192)
  self.assertEqual(self.run_cleanup('rh_manual=0;').returncode,0)
  self.assertEqual(json.loads((self.p/'job/cleanup.json').read_text()),result)
 def test_stopped_core_keeps_program_cache(self):
  helper=self.p/'helper.sh';helper.write_text(helper.read_text().replace('printf 77','printf ""'))
  cache=self.p/'tmp/ShellCrash/CrashCore.tar.gz';cache.write_bytes(b'x'*8192)
  self.assertEqual(self.run_cleanup().returncode,0);self.assertTrue(cache.exists())
if __name__=='__main__':unittest.main()
