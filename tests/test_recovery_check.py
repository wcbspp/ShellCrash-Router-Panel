import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RecoveryCheck(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.device = self.root/'device'; self.device.mkdir()
        self.work = self.root/'work'; self.work.mkdir()
        self.dav = self.root/'dav'; self.dav.mkdir()
        self.helper = self.root/'helper'; self.helper.mkdir()
        shutil.copy(ROOT/'shared/lib/backup-manifest.awk', self.helper)
        # Fake only the HTTP transport. Real parser, hashing, path assembly,
        # streaming pipe and request validation run as shipped.
        (self.helper/'remote.sh').write_text('''
remote_transport(){ echo webdav; }
remote_transfer_ready(){ [ "$SC_TEST_GATE" = on ]; }
remote_hash(){ shasum -a 256 | awk '{print $1}'; }
dav_model(){ echo "$SC_TEST_MODEL"; }
dav_base(){ printf '%s' "$SC_TEST_DAV"; }
dav_curl(){
 output='';next_output=0
 for arg in "$@";do
  [ "$next_output" != 1 ] || { output=$arg;next_output=0;continue; }
  [ "$arg" != -o ] || next_output=1
  url=$arg
 done
 printf '%s\\n' "$url" >> "$SC_TEST_CALLS"
 [ -f "$url" ] || return 22
 if [ -n "$output" ];then cat "$url" >&3;wc -c < "$url" | tr -d ' ';else cat "$url";fi
 [ "${SC_TEST_PARTIAL:-0}" != 1 ]
}
''')
        self.env = {**os.environ, 'SC_RECOVERY_FIXTURE': '1', 'SC_RECOVERY_C': str(self.device),
                    'SC_RECOVERY_D': str(self.work), 'SC_RECOVERY_HELPER': str(self.helper),
                    'SC_TEST_GATE':'on', 'SC_TEST_MODEL':'K2P', 'SC_TEST_DAV':str(self.dav),
                    'SC_TEST_CALLS':str(self.root/'calls')}
        self.manifest = self.make_set('backups/application-latest.json', rolling=True)

    def tearDown(self): self.tmp.cleanup()

    def make_set(self, path, rolling=False):
        records=[]
        for name, folder, label in [('application','backups','backup'),('core','objects','core'),('runtime-assets','objects','runtime')]:
            body=(name+' fixture').encode(); digest=hashlib.sha256(body).hexdigest()
            target=(f'{folder}/{label}-{digest}.tar.gz' if rolling else name+'.tar.gz')
            component=self.dav/(target if rolling else str(Path(path).parent/target))
            component.parent.mkdir(parents=True,exist_ok=True);component.write_bytes(body)
            records.append(dict(name=name+'.tar.gz',path=target,size=len(body),sha256=digest))
        identity=hashlib.sha256(''.join(r['sha256']+'\n' for r in records).encode()).hexdigest()
        m=dict(format=2,scope='full-application-baseline' if not rolling else 'full-application',
               model='K2P',created=1700000000,core_kind='singbox',core_version='1.12.13',
               core_sha256=records[1]['sha256'],sha256=identity,files=records,
               tool_version='1.9.4release',panel_version='test-v1')
        self.write(path,m);return m

    def write(self,path,value):
        p=self.dav/path;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(value))

    def run_check(self,request='source=latest\npath=\n'):
        (self.work/'upload-restore').write_text(request)
        (self.work/'upload-id-restore').write_text('0123abcd')
        return subprocess.run(['sh',str(ROOT/'shared/lib/recovery-check.sh'),'k2p','0123abcd'],
                              env=self.env,capture_output=True,text=True,timeout=10)

    def test_complete_set_streamed_without_archive_staging_or_device_changes(self):
        result=self.run_check();self.assertEqual(result.returncode,0,result.stderr)
        plan=json.loads((self.work/'recovery-plan.json').read_text())
        self.assertTrue(plan['verified']);self.assertFalse(plan['executor_ready']);self.assertFalse(plan['archive_checked'])
        self.assertEqual(plan['id'],'0123abcd');self.assertEqual(plan['backup']['model'],'K2P')
        self.assertEqual(list(self.device.iterdir()),[])
        self.assertEqual([p.name for p in self.work.iterdir()],['recovery-plan.json'])

    def test_disabled_unverified_gate_produces_zero_remote_requests_and_no_plan(self):
        self.env['SC_TEST_GATE']='off';r=self.run_check();self.assertNotEqual(r.returncode,0)
        self.assertFalse((self.root/'calls').exists());self.assertFalse((self.work/'recovery-plan.json').exists())

    def test_baseline_pointer_and_manual_relative_directory_use_actual_manifest(self):
        for kind,path in [('baseline','baselines/recovery-test/manifest.json'),('imports','imports/manual-test/manifest.json')]:
            m=self.make_set(path)
            if kind=='baseline': self.write('baselines/baseline-latest.json',{**m,'path':path})
            r=self.run_check('source='+kind+'\npath='+(path if kind=='imports' else '')+'\n')
            self.assertEqual(r.returncode,0,r.stderr)
            self.assertEqual(json.loads((self.work/'recovery-plan.json').read_text())['source'],kind)

    def test_damaged_missing_oversize_wrong_model_and_mixed_set_never_pass(self):
        for case in ['damaged','missing','oversize','wrong_model','mixed','duplicate']:
            with self.subTest(case=case):
                m=self.make_set('backups/application-latest.json',rolling=True)
                p=self.dav/m['files'][0]['path']
                if case=='damaged':p.write_bytes(b'x'*p.stat().st_size)
                if case=='missing':p.unlink()
                if case=='oversize':p.write_bytes(p.read_bytes()+b'extra')
                if case=='wrong_model':m['model']='AX5'
                if case=='mixed':m['sha256']='a'*64
                if case=='duplicate':m['files'].append(m['files'][0])
                self.write('backups/application-latest.json',m)
                r=self.run_check();self.assertNotEqual(r.returncode,0);self.assertFalse((self.work/'recovery-plan.json').exists())

    def test_invalid_paths_and_duplicate_fields_make_no_network_requests(self):
        for request in ['source=imports\npath=imports/../manifest.json\n','source=imports\npath=https://evil/manifest.json\n',
                        'source=latest\npath=etc/passwd\n','source=latest\nsource=baseline\n','source=imports\npath=imports/a/manifest.json\npath=\n']:
            r=self.run_check(request);self.assertNotEqual(r.returncode,0);self.assertFalse((self.root/'calls').exists())

    def test_partial_http_error_cannot_pass_even_if_it_delivered_valid_json(self):
        self.env['SC_TEST_PARTIAL']='1';r=self.run_check();self.assertNotEqual(r.returncode,0)
        self.assertFalse((self.work/'recovery-plan.json').exists())

    def test_legacy_baseline_requires_exact_manifest_hash_not_invented_dates(self):
        path='baselines/working-old/manifest.json';m=self.make_set(path)
        del m['sha256'];del m['created'];self.write(path,m)
        digest=hashlib.sha256((self.dav/path).read_bytes()).hexdigest()
        pointer={**m,'layout':'component-directory','path':path,'sha256':digest}
        pointer.pop('files');self.write('baselines/baseline-latest.json',pointer)
        r=self.run_check('source=baseline\npath=\n');self.assertEqual(r.returncode,0,r.stderr)
        plan=json.loads((self.work/'recovery-plan.json').read_text())
        self.assertEqual(plan['backup']['created'],0)
        self.assertEqual(plan['manifest_sha256'],digest)
        m['tool_version']='changed';self.write(path,m)
        r=self.run_check('source=baseline\npath=\n');self.assertNotEqual(r.returncode,0)
        self.assertFalse((self.work/'recovery-plan.json').exists())

    def test_optional_source_is_not_claimed_as_verified_component(self):
        self.manifest['files'].append(dict(name='source.tar.gz',path='source.tar.gz',size=123,sha256='f'*64))
        self.write('backups/application-latest.json',self.manifest)
        r=self.run_check();self.assertEqual(r.returncode,0,r.stderr)
        self.assertNotIn('source.tar.gz',(self.root/'calls').read_text())

if __name__=='__main__':unittest.main()
