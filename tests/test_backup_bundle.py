import hashlib
import io
import json
from pathlib import Path
import struct
import tarfile
import tempfile
import unittest
import zipfile

from tools.backup_bundle import Bundle, manifest_load, pack


class BackupBundle(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.manifest = {'format': 2, 'scope': 'full-application-baseline', 'model': 'K2P',
                         'core_kind': 'singbox', 'core_version': '1.12.13', 'files': []}
        elf = bytearray(128); elf[:6] = b'\x7fELF\x01\x01'; elf[18:20] = struct.pack('<H', 8)
        self.tar('application.tar.gz', {'backup.info': b'format=1', 'configs/ShellCrash.cfg': b'test=1',
                                      'starts/panel_boot.sh': b'#!/bin/sh', 'jsons/config.json': b'{}'})
        self.tar('core.tar.gz', {'CrashCore': bytes(elf)})
        self.tar('runtime-assets.tar.gz', {'ShellCrash/ruleset/cn.srs': b'fixture'})
        self.write_manifest()

    def tearDown(self):
        self.tmp.cleanup()

    def tar(self, name, files, special=None):
        path = self.root/name
        with tarfile.open(path, 'w:gz') as archive:
            for member_name, data in files.items():
                member = tarfile.TarInfo(member_name); member.size = len(data)
                archive.addfile(member, io.BytesIO(data))
            if special: archive.addfile(special)
        record = {'name': name, 'size': path.stat().st_size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
        self.manifest['files'] = [r for r in self.manifest['files'] if r['name'] != name]+[record]
        if name == 'core.tar.gz': self.manifest['core_sha256'] = record['sha256']

    def write_manifest(self):
        (self.root/'manifest.json').write_text(json.dumps(self.manifest))

    def test_verified_pack_roundtrip_has_human_guide_and_no_device_action(self):
        target = self.root/'portable.zip'
        pack(self.root, target, 'K2P')
        with Bundle(target, 'K2P') as bundle:
            self.assertTrue(bundle.report()['complete'])
            self.assertFalse(bundle.report()['device_changed'])
            self.assertEqual(bundle.manifest['default_restore'], 'full-confirmed')
        with zipfile.ZipFile(target) as archive:
            guide = archive.read('使用说明.txt').decode()
            self.assertIn('imports/', guide); self.assertIn('完整回退会覆盖', guide)
            self.assertTrue(all(m.compress_type == zipfile.ZIP_STORED for m in archive.infolist()))
        with self.assertRaises(FileExistsError): pack(self.root, target)

    def test_wrong_model_missing_component_duplicate_fields_and_external_paths_rejected(self):
        with self.assertRaises(ValueError): manifest_load(json.dumps(self.manifest), 'AX5')
        for field in ['../outside', '/etc/passwd', 'https://outside/config', 'objects/../../secret', 'objects\\core.tar.gz']:
            value = json.loads(json.dumps(self.manifest)); value['files'][0]['path'] = field
            with self.assertRaises(ValueError): manifest_load(json.dumps(value))
        value = dict(self.manifest, files=self.manifest['files'][:-1])
        with self.assertRaises(ValueError): manifest_load(json.dumps(value))
        with self.assertRaises(ValueError): manifest_load('{"format":1,"format":2}')

    def test_component_sha_corruption_is_not_a_complete_backup(self):
        with (self.root/'core.tar.gz').open('ab') as stream: stream.write(b'bad')
        with self.assertRaises(ValueError):
            with Bundle(self.root): pass

    def test_archive_paths_links_unknown_roots_and_special_mode_rejected(self):
        for name in ['../../outside', '/etc/passwd', 'firmware.bin']:
            self.tar('application.tar.gz', {name: b'bad'})
            self.write_manifest()
            with self.assertRaises(ValueError):
                with Bundle(self.root): pass
        for kind in [tarfile.SYMTYPE, tarfile.LNKTYPE, tarfile.CHRTYPE]:
            member = tarfile.TarInfo('configs/alias'); member.type = kind; member.linkname = '/etc/passwd'
            self.tar('application.tar.gz', {}, special=member); self.write_manifest()
            with self.assertRaises(ValueError):
                with Bundle(self.root): pass

    def test_kernel_elf_and_runtime_scope_checked_before_any_recovery(self):
        self.tar('core.tar.gz', {'CrashCore': b'not an executable'}); self.write_manifest()
        with self.assertRaises(ValueError):
            with Bundle(self.root): pass
        self.setUp_core()
        self.tar('runtime-assets.tar.gz', {'etc/shadow': b'bad'}); self.write_manifest()
        with self.assertRaises(ValueError):
            with Bundle(self.root): pass

    def setUp_core(self):
        elf = bytearray(128); elf[:6] = b'\x7fELF\x01\x01'; elf[18:20] = struct.pack('<H', 8)
        self.tar('core.tar.gz', {'CrashCore': bytes(elf)}); self.write_manifest()

    def test_old_gzip_and_zip_corruption_do_not_pass_on_tar_end_marker(self):
        data = bytearray((self.root/'core.tar.gz').read_bytes()); data[-8] ^= 1
        (self.root/'core.tar.gz').write_bytes(data)
        core = next(r for r in self.manifest['files'] if r['name'] == 'core.tar.gz')
        core['sha256'] = hashlib.sha256(data).hexdigest(); self.manifest['core_sha256'] = core['sha256']
        self.write_manifest()
        with self.assertRaises(OSError):
            with Bundle(self.root): pass
        malformed = self.root/'malformed.zip'
        with zipfile.ZipFile(malformed, 'w') as archive: archive.writestr('../manifest.json', b'{}')
        with self.assertRaises(ValueError):
            with Bundle(malformed): pass


if __name__ == '__main__': unittest.main()
