import os, subprocess, tempfile, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SCRIPT=ROOT/'profiles/k2p/payload/starts/oom-store.sh'
class K2PPersistence(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name)
  self.c=self.root/'core';self.d=self.root/'runtime';self.bin=self.root/'bin'
  for p in (self.c/'configs',self.c/'starts',self.d,self.bin):p.mkdir(parents=True,exist_ok=True)
  awk=self.bin/'awk';awk.write_text('#!/bin/sh\ncase "$*" in */proc/meminfo*) echo "${TEST_AVAIL:-30000}";; *) exec /usr/bin/awk "$@";; esac\n');awk.chmod(0o755)
  saver=self.c/'starts/save_storage.sh';saver.write_text('#!/bin/sh\necho attempt >> \"$SC_OOM_RUNTIME/save-attempts\"\n[ "$SC_STORAGE_MAX_BYTES" = 499712 ] && [ "$SC_STORAGE_VERIFY" = 1 ] || exit 9\n[ "${SAVE_FAIL:-0}" = 0 ] || exit 1\ncp "$CRASHDIR/configs/oom-history.b64" "$SC_OOM_RUNTIME/flash-snapshot"\n');saver.chmod(0o755)
  mover=self.bin/'mv';mover.write_text('#!/bin/sh\ncase \"${FAIL_QUEUE:-0}:$2\" in 1:*/oom-queue.b64) exit 1;; esac\nexec /bin/mv \"$@\"\n');mover.chmod(0o755)
  (self.root/'uptime').write_text('12345.67 0\n')
  self.env=dict(os.environ,CRASHDIR=str(self.c),SC_OOM_RUNTIME=str(self.d),SC_OOM_UPTIME_FILE=str(self.root/'uptime'),PATH=str(self.bin)+':'+os.environ['PATH'])
 def run_action(self,action,**kwargs):return subprocess.run(['sh',str(SCRIPT),action],env=dict(self.env,**kwargs),capture_output=True,text=True)
 def add(self,value):
  (self.d/'oom-evidence.log').write_text(value);self.assertEqual(self.run_action('enqueue').returncode,0)
 def test_noncore_oom_scan_is_queued_once(self):
  kernel=self.bin/'dmesg';kernel.write_text('#!/bin/sh\nprintf "%s\\n" "$TEST_KERNEL"\n');kernel.chmod(0o755)
  self.assertEqual(self.run_action('scan',TEST_KERNEL='').returncode,0)
  (self.root/'uptime').write_text('12347.0 0\n')
  message='[12346.0] Killed process 7 (zerotier-one)'
  self.assertEqual(self.run_action('scan',TEST_KERNEL=message).returncode,0)
  self.assertEqual(self.run_action('persist').returncode,0)
  self.assertIn(message,self.run_action('read').stdout)
  self.assertEqual(self.run_action('scan',TEST_KERNEL=message).returncode,0)
  self.assertFalse((self.d/'oom-queue.b64').exists())
 def test_rotation_and_flash_copy(self):
  for value in ('first','second','third'):
   self.add(value);self.assertEqual(self.run_action('persist').returncode,0)
  result=self.run_action('read');self.assertNotIn('second',result.stdout);self.assertIn('third',result.stdout);self.assertNotIn('first',result.stdout)
  self.assertEqual((self.c/'configs/oom-history.b64').read_bytes(),(self.d/'flash-snapshot').read_bytes())
 def test_save_failure_restores_previous_and_retains_pending(self):
  self.add('old');self.assertEqual(self.run_action('persist').returncode,0);before=(self.c/'configs/oom-history.b64').read_bytes()
  self.add('new');self.assertNotEqual(self.run_action('persist',SAVE_FAIL='1').returncode,0)
  self.assertEqual((self.c/'configs/oom-history.b64').read_bytes(),before);self.assertTrue((self.d/'oom-queue.b64').exists())
 def test_low_memory_and_busy_do_not_change_old_records(self):
  self.add('old');self.assertEqual(self.run_action('persist').returncode,0);before=(self.c/'configs/oom-history.b64').read_bytes()
  self.add('new');self.assertNotEqual(self.run_action('persist',TEST_AVAIL='18431').returncode,0);self.assertEqual((self.c/'configs/oom-history.b64').read_bytes(),before)
  (self.d/'operation.lock').mkdir();self.assertNotEqual(self.run_action('persist').returncode,0);self.assertTrue((self.d/'operation.lock').exists())
 def test_corrupt_history_is_not_replaced(self):
  p=self.c/'configs/oom-history.b64';p.write_text('not valid !\n');self.add('new');self.assertNotEqual(self.run_action('persist').returncode,0);self.assertEqual(p.read_text(),'not valid !\n')

 def test_restart_restores_latest_event_from_saved_storage(self):
  self.add('old');self.assertEqual(self.run_action('persist').returncode,0)
  self.add('new');self.assertEqual(self.run_action('persist').returncode,0)
  saved=(self.d/'flash-snapshot').read_bytes()
  (self.c/'configs/oom-history.b64').unlink();(self.c/'configs/oom-history.b64').write_bytes(saved)
  after=self.root/'after-reboot';after.mkdir();self.env['SC_OOM_RUNTIME']=str(after)
  result=self.run_action('read');self.assertEqual(result.returncode,0);self.assertNotIn('old',result.stdout);self.assertIn('new',result.stdout)
 def test_failed_save_retries_and_keeps_latest(self):
  self.add('one');self.assertEqual(self.run_action('persist').returncode,0)
  self.add('two');self.assertNotEqual(self.run_action('persist',SAVE_FAIL='1').returncode,0)
  self.add('three');(self.d/'oom-retry-at').write_text('0\n');self.assertEqual(self.run_action('persist').returncode,0)
  result=self.run_action('read');self.assertNotIn('one',result.stdout);self.assertNotIn('two',result.stdout);self.assertIn('three',result.stdout)

 def test_busy_queue_retries_without_touching_live_lock(self):
  lock=self.d/'oom-store.lock';lock.mkdir();(lock/'owner').write_text(str(os.getpid()))
  (self.d/'oom-evidence.log').write_text('pending event')
  self.assertNotEqual(self.run_action('enqueue').returncode,0)
  self.assertEqual(len(list(self.d.glob('oom-pending.*'))),1);self.assertTrue(lock.exists())
  (lock/'owner').unlink();lock.rmdir()
  pending=next(self.d.glob('oom-pending.*'));self.assertEqual(subprocess.run(['sh',str(SCRIPT),'enqueue',str(pending)],env=self.env).returncode,0)
  self.assertFalse(list(self.d.glob('oom-pending.*')))
  self.assertEqual(self.run_action('persist').returncode,0)
  self.assertIn('pending event',self.run_action('read').stdout)

 def test_queue_publish_failure_preserves_existing_and_retry_marker(self):
  self.add('first');before=(self.d/'oom-queue.b64').read_bytes()
  (self.d/'oom-evidence.log').write_text('second')
  self.assertNotEqual(self.run_action('enqueue',FAIL_QUEUE='1').returncode,0)
  self.assertEqual((self.d/'oom-queue.b64').read_bytes(),before)
  pending=next(self.d.glob('oom-pending.*'));self.assertEqual(subprocess.run(['sh',str(SCRIPT),'enqueue',str(pending)],env=self.env).returncode,0)
  self.assertEqual(self.run_action('persist').returncode,0)
  result=self.run_action('read');self.assertNotIn('first',result.stdout);self.assertIn('second',result.stdout)

 def test_failed_flash_save_is_not_retried_in_tight_loop(self):
  self.add('pending');self.assertNotEqual(self.run_action('persist',SAVE_FAIL='1').returncode,0)
  before=(self.d/'save-attempts').read_text()
  self.assertNotEqual(self.run_action('persist',SAVE_FAIL='1').returncode,0)
  self.assertEqual((self.d/'save-attempts').read_text(),before)
  self.assertTrue((self.d/'oom-queue.b64').exists())

 def test_dead_lock_is_recovered_and_live_reaper_is_respected(self):
  lock=self.d/'oom-store.lock';lock.mkdir();(lock/'owner').write_text('99999999')
  self.add('after stale lock')
  self.assertFalse(lock.exists())
  lock.mkdir();(lock/'owner').write_text('99999999');guard=self.d/'oom-store-reap.lock';guard.mkdir()
  (self.d/'oom-evidence.log').write_text('wait')
  self.assertNotEqual(self.run_action('enqueue').returncode,0)
  self.assertTrue(lock.exists());self.assertTrue(guard.exists())

 def test_symlink_and_directory_history_are_not_replaced(self):
  target=self.c/'configs/oom-history.b64';external=self.root/'external';external.write_text('private')
  self.add('event');target.symlink_to(external)
  self.assertNotEqual(self.run_action('persist').returncode,0);self.assertEqual(external.read_text(),'private')
  target.unlink();target.mkdir()
  self.assertNotEqual(self.run_action('persist').returncode,0);self.assertTrue(target.is_dir())

 def test_invalid_base64_and_capture_failure_are_reported(self):
  (self.d/'oom-save-status').write_text('capture_failed')
  self.assertIn('失败',self.run_action('read').stdout)
  (self.c/'configs/oom-history.b64').write_text('A=\n')
  self.assertNotEqual(self.run_action('read').returncode,0)
 def test_concurrent_events_remain_separate(self):
  import time,base64
  original=self.bin/'head';original.write_text('#!/bin/sh\n/usr/bin/head "$@"\ntouch "$SC_OOM_RUNTIME/waiting"\nwhile [ ! -e "$SC_OOM_RUNTIME/continue" ];do sleep .05;done\n');original.chmod(0o755)
  (self.d/'oom-evidence.log').write_text('first')
  first=subprocess.Popen(['sh',str(SCRIPT),'enqueue'],env=self.env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
  try:
   for _ in range(200):
    if (self.d/'waiting').exists():break
    time.sleep(.01)
   self.assertTrue((self.d/'waiting').exists())
   (self.d/'oom-evidence.log').write_text('second')
   self.assertNotEqual(self.run_action('enqueue').returncode,0)
   (self.d/'continue').touch();self.assertEqual(first.wait(timeout=5),0)
   original.unlink()
   for pending in self.d.glob('oom-pending.*'):
    self.assertEqual(subprocess.run(['sh',str(SCRIPT),'enqueue',str(pending)],env=self.env).returncode,0)
   rows=[base64.b64decode(x).decode() for x in (self.d/'oom-queue.b64').read_text().splitlines()]
   self.assertEqual(len(rows),2);self.assertIn('first',rows[0]);self.assertIn('second',rows[1])
  finally:
   if first.poll() is None:first.kill();first.wait()
 def test_pending_events_are_processed_in_time_order(self):
  import base64
  pending=[]
  for n in (100,102,101):
   p=self.d/('oom-pending.%s.12.fixture'%n);p.write_text('event-%s'%n);pending.append(p)
  result=subprocess.run(['sh',str(SCRIPT),'enqueue',str(pending[0])],env=self.env,capture_output=True)
  self.assertEqual(result.returncode,0,result.stderr)
  rows=[base64.b64decode(x).decode() for x in (self.d/'oom-queue.b64').read_text().splitlines()]
  self.assertEqual(len(rows),2);self.assertIn('event-101',rows[0]);self.assertIn('event-102',rows[1])
