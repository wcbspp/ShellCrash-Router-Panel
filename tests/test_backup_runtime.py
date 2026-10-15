"""A missing cold cache must never replace a previously complete runtime set."""
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
import shlex

ROOT=Path(__file__).resolve().parents[1]

class RuntimeCompleteness(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name);self.c=self.root/'app';self.d=self.root/'ShellCrash'
        for p in [self.c/'ax5',self.c/'starts',self.c/'configs',self.d]:p.mkdir(parents=True,exist_ok=True)
        self.cache=self.root/'ShellCrash-dashboard'
        source=(ROOT/'shared/lib/backup-set.sh').read_text().replace('/tmp/ShellCrash-dashboard',str(self.cache)).replace('/tmp/ShellCrash/ruleset',str(self.d/'ruleset'))
        # Give tar its own temporary root; production has no test environment knob.
        source=source.replace('${D#/tmp/}','${D#'+str(self.root)+'/}').replace('-C /tmp','-C '+shlex.quote(str(self.root)))
        (self.root/'meminfo').write_text('MemAvailable: 100000 kB\n')
        source=source.replace('/proc/meminfo',str(self.root/'meminfo'))
        self.source=self.root/'backup-set.sh';self.source.write_text(source)
        self.old=self.d/'runtime-assets-backup.tar.gz';self.old.write_bytes(b'previous-complete-set')

    def run_pack(self,model='AX5'):
        script='set -eu\nC='+shlex.quote(str(self.c))+';D='+shlex.quote(str(self.d))+';KIND=meta;protect_kb=0\ndav_model(){ echo '+model+'; }\n. '+shlex.quote(str(self.source))+'\nbackup_resources_pack\n'
        return subprocess.run(['sh','-c',script],capture_output=True,timeout=10)

    def installer(self,body):
        for h in ['ax5','starts']:(self.c/h/'dashboard-install.sh').write_text('#!/bin/sh\nset -eu\n'+body+'\n')

    def ready(self):
        self.cache.mkdir()
        for f in ['.ready','index.html','dashboard-bridge.js']:(self.cache/f).write_text('verified-fixture')

    def test_cold_dashboard_is_prepared_before_runtime_is_packed(self):
        self.installer('mkdir -p '+shlex.quote(str(self.cache))+'\nfor f in .ready index.html dashboard-bridge.js;do echo installed > '+shlex.quote(str(self.cache))+'/$f;done')
        r=self.run_pack();self.assertEqual(r.returncode,0,r.stderr)
        with tarfile.open(self.old)as tar:
            self.assertIn('ShellCrash-dashboard/index.html',tar.getnames())
            self.assertIn('ShellCrash/runtime-backup.info',tar.getnames())

    def test_failed_or_incomplete_installer_keeps_previous_archive(self):
        for body in ['exit 1',':']:
            self.installer(body);r=self.run_pack();self.assertNotEqual(r.returncode,0)
            self.assertEqual(self.old.read_bytes(),b'previous-complete-set')

    def test_k2p_missing_domain_or_native_metadata_rejects_complete_claim(self):
        self.ready();self.installer(':')
        (self.c/'starts/domain_asset.sh').write_text('domain_asset_ensure(){ return 1; }\n')
        self.assertNotEqual(self.run_pack('K2P').returncode,0)
        (self.c/'starts/domain_asset.sh').write_text('domain_asset_ensure(){ return 0; }\n')
        (self.c/'configs/native-profile').touch()
        self.assertNotEqual(self.run_pack('K2P').returncode,0)
        self.assertEqual(self.old.read_bytes(),b'previous-complete-set')

    def test_k2p_native_resource_failure_does_not_publish_partial_runtime(self):
        self.ready();self.installer(':')
        (self.c/'starts/domain_asset.sh').write_text('domain_asset_ensure(){ return 0; }\n')
        (self.c/'configs/native-profile').touch();(self.c/'configs/native-resources.tsv').write_text('fixture\n')
        (self.c/'starts/native_profile.sh').write_text('native_resources_prepare(){ return 1; }\n')
        self.assertNotEqual(self.run_pack('K2P').returncode,0)
        self.assertEqual(self.old.read_bytes(),b'previous-complete-set')

if __name__=='__main__':unittest.main()
