"""Memory settings are parsed, persisted, and restored without running Storage writes."""
import json,subprocess,unittest
from pathlib import Path
import test_cleanup
ROOT=Path(__file__).resolve().parents[1]
class MemorySettingsTests(unittest.TestCase):
 def setUp(self):
  f=test_cleanup.CleanupTests();f.setUp();self.addCleanup(f.doCleanups);self.f=f;self.p=f.p
  (self.p/'configs').mkdir();(self.p/'starts').mkdir()
  (self.p/'starts/resource_health.sh').write_text((self.p/'helper.sh').read_text())
 def sh(self,body):
  return subprocess.run(['sh','-c',f'C="{self.p}"; D="$C/job"; . "$C/starts/resource_health.sh"; '+body],capture_output=True,text=True)
 def save(self,code,success=True):
  return self.sh(f'''phase(){{ printf '%s:%s\\n' "$1" "$2"; }}; fail(){{ echo "$1"; }};
 save_safe(){{ echo write >> "$D/writes"; {'return 0' if success else 'return 1'}; }};
 set -- memcfg deadbeef '{code}'; . "{ROOT}/payload/starts/memory_settings.sh"''')
 def config(self,w=20,p=14,c=24):
  (self.p/'configs/memory.conf').write_text(f'warning_mb={w}\nprotect_mb={p}\ncleanup_mb={c}\n')
 def test_save_and_reload_persistent_thresholds(self):
  result=self.save('w20p14c24');self.assertEqual(result.returncode,0,result.stderr)
  self.assertIn('memory_settings_saved',result.stdout)
  self.assertEqual((self.p/'configs/memory.conf').stat().st_mode&0o777,0o600)
  for available,pressure in [(20000,'warning'),(22000,'normal'),(14000,'protect'),(14336,'warning')]:
   (self.p/'proc/meminfo').write_text(f'MemAvailable: {available} kB\n')
   result=self.sh('resource_read; echo "$rh_pressure $rh_warning_mb $rh_protect_mb $rh_cleanup_mb"')
   self.assertEqual(result.stdout.strip(),f'{pressure} 20 14 24')
 def test_invalid_requests_do_not_modify_configuration(self):
  self.config();original=(self.p/'configs/memory.conf').read_bytes()
  for code in ['w16p11c0','w12p16c0','w20p14c19','w65p12c0','w16p12c97','w016p12c0','w16p12c0;bad','w16p12c-1']:
   result=self.save(code);self.assertNotEqual(result.returncode,0,code)
   self.assertEqual((self.p/'configs/memory.conf').read_bytes(),original)
  self.assertFalse((self.p/'job/writes').exists())
 def test_failure_restores_previous_or_absent_file(self):
  self.config();original=(self.p/'configs/memory.conf').read_bytes()
  self.assertNotEqual(self.save('w24p16c28',False).returncode,0)
  self.assertEqual((self.p/'configs/memory.conf').read_bytes(),original)
  (self.p/'configs/memory.conf').unlink()
  self.assertNotEqual(self.save('w24p16c28',False).returncode,0)
  self.assertFalse((self.p/'configs/memory.conf').exists())
 def test_defaults_and_unchanged_do_not_write_flash(self):
  self.assertEqual(self.save('w16p12c0').returncode,0)
  self.assertFalse((self.p/'configs/memory.conf').exists());self.assertFalse((self.p/'job/writes').exists())
  self.config();self.assertEqual(self.save('w20p14c24').returncode,0)
  self.assertFalse((self.p/'job/writes').exists())
 def test_corrupt_file_falls_back_without_execution(self):
  for text in ['warning_mb=20\nprotect_mb=10\ncleanup_mb=24\n','warning_mb=20\nwarning_mb=21\nprotect_mb=14\ncleanup_mb=24\n','warning_mb=$(touch BAD)\nprotect_mb=14\ncleanup_mb=24\n']:
   (self.p/'configs/memory.conf').write_text(text)
   result=self.sh('resource_limits; echo "$rh_warning_mb $rh_protect_mb $rh_cleanup_mb"')
   self.assertEqual(result.stdout.strip(),'16 12 0')
  self.assertFalse((self.p/'BAD').exists())
 def test_cleanup_trigger_and_manual_bypass_logs_always_bounded(self):
  self.config(w=16,p=12,c=18)
  (self.p/'proc/meminfo').write_text('MemAvailable: 20000 kB\n')
  cache=self.p/'tmp/ShellCrash/CrashCore.tar.gz';cache.write_bytes(b'x'*8192)
  log=self.p/'tmp/ShellCrash/core.log';log.write_bytes(b'x'*80000)
  result=self.sh('rh_manual=0; resource_cleanup');self.assertEqual(result.returncode,0,result.stderr)
  self.assertTrue(cache.exists());self.assertEqual(log.stat().st_size,32768)
  self.assertEqual(self.sh('rh_manual=1; resource_cleanup').returncode,0);self.assertFalse(cache.exists())
  cache.write_bytes(b'x'*8192);(self.p/'proc/meminfo').write_text('MemAvailable: 18432 kB\n')
  self.assertEqual(self.sh('rh_manual=0; resource_cleanup').returncode,0);self.assertTrue(cache.exists())
  (self.p/'proc/meminfo').write_text('MemAvailable: 18431 kB\n')
  self.assertEqual(self.sh('rh_manual=0; resource_cleanup').returncode,0);self.assertFalse(cache.exists())
 def test_low_memory_defers_storage_write(self):
  (self.p/'proc/meminfo').write_text('MemAvailable: 11000 kB\n')
  result=self.save('w20p14c24');self.assertIn('memory_settings_low',result.stdout)
  self.assertFalse((self.p/'job/writes').exists())
if __name__=='__main__':unittest.main()
