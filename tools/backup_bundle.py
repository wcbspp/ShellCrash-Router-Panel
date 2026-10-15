#!/usr/bin/env python3
"""Inspect or assemble a portable backup on a computer, never on a router.

No scripts from a backup are executed. Components are checked before a package
is offered for restoration. This command itself does not change a device.
"""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import struct
import tarfile
import tempfile
import zipfile

REQUIRED = ('application.tar.gz', 'core.tar.gz', 'runtime-assets.tar.gz')
LIMITS = {'application.tar.gz': 4_000_000, 'core.tar.gz': 40_000_000,
          'runtime-assets.tar.gz': 4_000_000, 'source.tar.gz': 20_000_000}
PROTECTED = {'webdav.auth', 'webdav.user', 'mirror-id', 'mirror_key',
             'mirror_known_hosts', 'remote.verified'}


def safe_path(value):
    if not isinstance(value, str) or not value or len(value) > 300:
        raise ValueError('备份文件路径无效')
    parts = value.split('/')
    if value.startswith('/') or any(p in ('', '..') for p in parts) or '\\' in value:
        raise ValueError('备份包含越界路径')
    if any(ord(c) < 32 or ord(c) == 127 for c in value):
        raise ValueError('备份路径包含控制字符')
    return str(PurePosixPath(value))


def no_duplicates(pairs):
    obj = {}
    for key, value in pairs:
        if key in obj:
            raise ValueError('备份清单包含重复字段')
        obj[key] = value
    return obj


def manifest_load(data, model=None):
    if len(data) > 16_384:
        raise ValueError('备份清单过大')
    try:
        m = json.loads(data, object_pairs_hook=no_duplicates)
    except (UnicodeError, json.JSONDecodeError) as e:
        raise ValueError('备份清单不是有效 JSON') from e
    if not isinstance(m, dict) or m.get('format') != 2 or m.get('model') not in ('AX5', 'K2P'):
        raise ValueError('不是受支持的完整备份清单；单独应用包不能完整回退')
    if model and m['model'] != model:
        raise ValueError('备份机型不匹配，不能跨机型恢复')
    if m.get('scope') not in ('full-application', 'full-application-baseline'):
        raise ValueError('此清单不表示完整应用备份')
    if m.get('core_kind') not in (None, 'meta', 'singbox') or (m['model'] == 'K2P' and m.get('core_kind') == 'meta'):
        raise ValueError('此设备不支持备份中的内核类型')
    files = m.get('files')
    if not isinstance(files, list) or not 3 <= len(files) <= 4:
        raise ValueError('完整备份缺少组件或包含未知组件')
    names, paths = set(), set()
    for item in files:
        if not isinstance(item, dict) or item.get('name') not in LIMITS or item['name'] in names:
            raise ValueError('备份组件重复或名称未知')
        name = item['name']
        path = safe_path(item.get('path', name))
        if path in paths:
            raise ValueError('备份多个组件使用了同一路径')
        if type(item.get('size')) is not int or not 0 < item['size'] <= LIMITS[name]:
            raise ValueError('备份组件大小超出限制')
        if not isinstance(item.get('sha256'), str) or not re.fullmatch(r'[a-f0-9]{64}', item['sha256']):
            raise ValueError('备份组件缺少有效 SHA256')
        names.add(name); paths.add(path)
    if not set(REQUIRED) <= names:
        raise ValueError('不是完整备份：缺少应用、内核或运行资源')
    core = next(x for x in files if x['name'] == 'core.tar.gz')
    if m.get('core_sha256') != core['sha256']:
        raise ValueError('清单内核记录与组件不一致')
    return m


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for part in iter(lambda: stream.read(131072), b''):
            h.update(part)
    return h.hexdigest()


def inspect_tar(path, component, model):
    # Read gzip to EOF: tar's end marker alone does not verify gzip CRC/trailer.
    raw_size = 0
    with gzip.open(path, 'rb') as stream:
        for part in iter(lambda: stream.read(131072), b''):
            raw_size += len(part)
            if raw_size > 160_000_000:
                raise ValueError('组件解压体积超出限制')
    roots = {'configs', 'ui', 'ruleset', 'cache', 'ax5', 'ShellCrash-tool'} if model == 'AX5' else {
        'configs', 'ui', 'padavan', 'starts', 'libs', 'tools', 'menus', 'jsons', 'yamls', 'ruleset',
        'start.sh', 'menu.sh', 'init.sh', 'version'}
    roots |= {'backup.info', 'RESTORE.txt', '使用说明.txt'}
    names, sizes, members = set(), {}, 0
    with tarfile.open(path, 'r:gz') as archive:
        for member in archive:
            members += 1
            if members > 8000 or member.size > 80_000_000:
                raise ValueError('组件条目或文件体积超出限制')
            name = member.name
            while name.startswith('./'):
                name = name[2:]
            name = name.rstrip('/')
            if name in ('', '.') and member.isdir():
                continue
            name = safe_path(name)
            if name in names:
                raise ValueError('归档包含重复文件路径')
            if not (member.isdir() or member.isfile()):
                raise ValueError('归档包含链接、设备或其他不支持的文件类型')
            if member.mode & 0o6000:
                raise ValueError('归档包含特殊执行权限')
            if component == 'application.tar.gz':
                if name.split('/')[0] not in roots:
                    raise ValueError('应用包包含本项目以外的目录')
                if name.startswith('configs/') and name.split('/')[-1] in PROTECTED:
                    raise ValueError('可导入应用包不应包含 SSH/WebDAV 凭据')
            elif component == 'core.tar.gz':
                if name != 'CrashCore' or not member.isfile():
                    raise ValueError('内核包必须只包含 CrashCore')
                with archive.extractfile(member) as stream:
                    header = stream.read(20)
                expected = 40 if model == 'AX5' else 8
                if len(header) != 20 or header[:6] != b'\x7fELF\x01\x01' or struct.unpack('<H', header[18:20])[0] != expected:
                    raise ValueError('内核 ELF 架构与机型不匹配')
            elif component == 'runtime-assets.tar.gz':
                allowed = name == 'ShellCrash-dashboard' or name.startswith('ShellCrash-dashboard/')
                allowed |= model == 'K2P' and (name == 'ShellCrash/ruleset' or name.startswith('ShellCrash/ruleset/'))
                allowed |= name in ('ShellCrash/runtime-backup.info', 'sc-admin/runtime-backup.info')
                if not allowed:
                    raise ValueError('运行资源包含预期以外的目录')
            names.add(name)
            if member.isfile():
                sizes[name] = member.size
    if component == 'core.tar.gz' and names != {'CrashCore'}:
        raise ValueError('内核包缺少 CrashCore')
    if component == 'application.tar.gz':
        required = {'backup.info'}
        required |= {'ax5/api.lua', 'configs/config.json', 'ShellCrash-tool/configs/ShellCrash.cfg'} if model == 'AX5' else {'starts/panel_boot.sh', 'jsons/config.json', 'configs/ShellCrash.cfg'}
        if not required <= names:
            raise ValueError('应用包缺少必要的配置或机型适配文件')
    return {'members': members, 'unpacked_size': sum(sizes.values()), 'files': sizes}


class Bundle:
    def __init__(self, source, model=None):
        self.source = Path(source)
        self.model = model
        self.tmp = None

    def __enter__(self):
        if self.source.is_dir():
            self.root = self.source.resolve()
        else:
            self.tmp = tempfile.TemporaryDirectory(prefix='sc-backup-inspect-')
            self.root = Path(self.tmp.name).resolve()
            os.chmod(self.root, 0o700)
            try:
                with zipfile.ZipFile(self.source) as archive:
                    members = archive.infolist()
                    expected = set(LIMITS) | {'manifest.json', 'RESTORE.txt', 'GUIDE.txt', '使用说明.txt', 'index.json'}
                    names = [m.filename for m in members]
                    if len(names) != len(set(names)) or not set(names) <= expected or len(names) > 10:
                        raise ValueError('完整 ZIP 应直接包含清单和组件，不应包含其他路径或重复文件')
                    if 'manifest.json' not in names:
                        raise ValueError('ZIP 缺少 manifest.json')
                    for member in members:
                        limit = LIMITS.get(member.filename, 16_384)
                        if member.file_size > limit or member.flag_bits & 1 or member.external_attr >> 16 & 0o170000 == 0o120000:
                            raise ValueError('ZIP 文件体积、加密或链接类型不受支持')
                        with archive.open(member) as src, (self.root/member.filename).open('xb') as dst:
                            os.chmod(dst.name, 0o600)
                            shutil.copyfileobj(src, dst, length=131072)
            except BaseException:
                self.tmp.cleanup(); raise
        try:
            manifest = self.root/'manifest.json'
            if manifest.is_symlink() or manifest.stat().st_size > 16_384:
                raise ValueError('清单文件无效')
            self.manifest = manifest_load(manifest.read_bytes(), self.model)
            self.paths = {}
            self.details = {}
            for item in self.manifest['files']:
                relative = safe_path(item.get('path', item['name']))
                path = self.root/relative
                if path.is_symlink() or self.root not in path.resolve().parents or path.stat().st_size != item['size']:
                    raise ValueError('组件路径越界、缺失或大小不符')
                if digest(path) != item['sha256']:
                    raise ValueError(item['name']+' 校验失败')
                self.paths[item['name']] = path
                if item['name'] in REQUIRED:
                    self.details[item['name']] = inspect_tar(path, item['name'], self.manifest['model'])
            return self
        except BaseException:
            if self.tmp: self.tmp.cleanup()
            raise

    def __exit__(self, *args):
        if self.tmp: self.tmp.cleanup()

    def report(self):
        return {'model': self.manifest['model'], 'complete': True,
                'core_version': self.manifest.get('core_version', '未记录'),
                'source_commit': self.manifest.get('source_commit'),
                'compressed_size': sum(f['size'] for f in self.manifest['files']),
                'components': {name: {k: v for k, v in detail.items() if k != 'files'} for name, detail in self.details.items()},
                'restore_scope': '完整回退程序、内核、运行资源及备份时的配置；不恢复固件或网络设置',
                'device_changed': False}


def pack(source, output, model=None):
    output = Path(output)
    with Bundle(source, model) as bundle:
        manifest = json.loads(json.dumps(bundle.manifest))
        for item in manifest['files']:
            item['path'] = item['name']
        manifest['default_restore'] = 'full-confirmed'
        # Exclusive creation prevents accidentally replacing a known-good package.
        with output.open('xb') as target:
            os.chmod(target.name, 0o600)
            try:
                with zipfile.ZipFile(target, 'w', compression=zipfile.ZIP_STORED) as archive:
                    archive.writestr('manifest.json', json.dumps(manifest, ensure_ascii=False, indent=2)+'\n')
                    for name, path in bundle.paths.items(): archive.write(path, name)
                    guide = ('ShellCrash 完整应用备份（不是固件）\n'
                             '在恢复窗口选择此完整 ZIP，程序按清单识别组件，不必逐个选择文件。\n'
                             'application.tar.gz：程序与当时的配置；core.tar.gz：匹配内核；\n'
                             'runtime-assets.tar.gz：高级面板与必要规则资源；source.tar.gz（如有）：开发源码，仅供查阅。\n'
                             '完整回退会覆盖后来的订阅、DNS、分流和启动设置，需要明确确认。\n'
                             '手动放入 WebDAV 时，在 shellcrash-panel/'+manifest['model']+'/imports/ 下新建子目录，\n'
                             '把此 ZIP 在电脑解压后整套上传，保留原文件名；上传完成后再刷新恢复列表。\n'
                             '先校验机型、组件 SHA256 和空间，再暂停代理逐项恢复；不要直接解压覆盖运行中的设备。\n'
                             '完成后验证节点、规则、DNS、自启和管理页面；失败保留日志及操作前备份。\n'
                             '此包含订阅与节点密码，请私密保存；不含固件、SSH/WebDAV 凭据、Wi-Fi/LAN 配置或 ZeroTier 身份。\n')
                    archive.writestr('使用说明.txt', guide)
                    archive.writestr('RESTORE.txt', guide)
            except BaseException:
                target.close(); output.unlink(missing_ok=True); raise
    return output


def main():
    parser = argparse.ArgumentParser(description='在电脑检查或组装完整备份，不修改路由器')
    parser.add_argument('action', choices=['inspect', 'pack'])
    parser.add_argument('source', type=Path, help='完整备份目录或 ZIP')
    parser.add_argument('--model', choices=['AX5', 'K2P'])
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if args.action == 'pack':
        if not args.output: parser.error('pack 需要 --output')
        print(pack(args.source, args.output, args.model))
    else:
        with Bundle(args.source, args.model) as bundle:
            print(json.dumps(bundle.report(), ensure_ascii=False, indent=2))


if __name__ == '__main__':
    try: main()
    except (OSError, ValueError, tarfile.TarError, zipfile.BadZipFile, EOFError) as exc:
        raise SystemExit('未通过：'+str(exc))
