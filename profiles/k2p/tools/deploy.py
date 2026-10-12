#!/usr/bin/env python3
"""Interactive installer for an existing Padavan + ShellCrash installation."""
import argparse, base64, getpass, io, ipaddress, json, re, shlex, shutil
import subprocess, sys, tarfile, tempfile, urllib.parse, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAX_INPUT = 524288


def subscription_nodes(raw):
    text = raw.decode('utf-8-sig').strip()
    if not text.startswith(('{', '[')) and 'anytls://' not in text:
        try:
            compact = re.sub(r'\s', '', text)
            text = base64.urlsafe_b64decode(compact + '=' * (-len(compact) % 4)).decode('utf-8').strip()
        except (ValueError, UnicodeError) as exc:
            raise ValueError('订阅不是 AnyTLS 链接或 sing-box JSON') from exc
    if text.startswith(('{', '[')):
        data = json.loads(text)
        nodes = data if isinstance(data, list) else data.get('outbounds')
        if not isinstance(nodes, list):
            raise ValueError('JSON 中没有 outbounds 节点')
        return nodes
    nodes = []
    skipped_ssr = 0
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        u = urllib.parse.urlsplit(line)
        if u.scheme == 'ssr':
            skipped_ssr += 1
            continue
        if u.scheme != 'anytls':
            raise ValueError('链接订阅只支持 AnyTLS；其他协议请使用 sing-box JSON')
        tag = urllib.parse.unquote(u.fragment)
        port = u.port or 443
        if not tag or not u.hostname or not u.username or not 1 <= port <= 65535:
            raise ValueError('AnyTLS 节点缺少名称、地址或密码')
        q = dict(urllib.parse.parse_qsl(u.query))
        tls = {'enabled': True, 'server_name': q.get('sni') or q.get('peer') or u.hostname,
               'insecure': (q.get('insecure') or q.get('allowInsecure') or '').lower() in ('1', 'true')}
        if q.get('alpn'):
            tls['alpn'] = [s for s in q['alpn'].split(',') if s]
        password = urllib.parse.unquote(u.username)
        if u.password:
            password += ':' + urllib.parse.unquote(u.password)
        nodes.append({'type': 'anytls', 'tag': tag, 'server': u.hostname,
                      'server_port': port, 'password': password, 'tls': tls})
    if skipped_ssr:
        print(f'已跳过 {skipped_ssr} 个旧 SSR 条目。', file=sys.stderr)
    if not nodes:
        raise ValueError('订阅中没有节点')
    return nodes


def read_snapshot(raw):
    expected = ['started_script.sh', 'ShellCrash/jsons/config.json', 'chinadns/chnroute.txt', 'ShellCrash/configs/cn_ip.txt', 'ShellCrash/cn_ip.txt']
    if len(raw) > 3 * 1024 * 1024:
        raise ValueError('路由器配置超过大小限制')
    with tarfile.open(fileobj=io.BytesIO(raw), mode='r:gz') as archive:
        result = {}
        for name in expected:
            try:
                member = archive.getmember(name)
            except KeyError:
                continue
            if not member.isfile() or member.size > MAX_INPUT:
                raise ValueError('路由器配置文件不符合要求')
            result[name] = archive.extractfile(member).read()
    if not result:
        raise ValueError('没有取得路由器配置')
    return result


def make_upload(profile, secret, subscription=None, core_file=None):
    stream = io.BytesIO()
    with tarfile.open(fileobj=stream, mode='w:gz') as archive:
        for entry in ['install.sh', 'uninstall.sh', 'backup.sh', 'restore_storage.sh', 'payload', 'examples', 'vendor']:
            path = ROOT / entry
            files = [path] if path.is_file() else sorted(p for p in path.rglob('*') if p.is_file())
            for p in files:
                if p.is_symlink():
                    raise ValueError('安装文件不能是软链接')
                archive.add(p, arcname='package/' + str(p.relative_to(ROOT)), recursive=False)
        inputs = [('config.private.json', profile), ('panel-secret.private', secret)]
        if core_file is not None:
            inputs.append(('core-offline.tar.gz', core_file))
        if subscription is not None:
            inputs.append(('subscription.private', subscription))
        for name, path in inputs:
            data = path.read_bytes()
            info = tarfile.TarInfo(name)
            info.size, info.mode = len(data), 0o600
            archive.addfile(info, io.BytesIO(data))
    return stream.getvalue()


def main():
    p = argparse.ArgumentParser(description='在电脑上运行，安装 Padavan ShellCrash 面板')
    p.add_argument('--router', help='路由器 LAN IPv4 地址')
    p.add_argument('--user', help='SSH 用户名，默认 admin')
    p.add_argument('--port', type=int, help='SSH 端口，默认 22')
    p.add_argument('--backup-dir', type=Path, default=Path.cwd(), help='电脑上的备份目录')
    p.add_argument('--nodes-file', type=Path, help='离线节点文件：sing-box JSON 或 AnyTLS 链接')
    p.add_argument('--core-file', type=Path, help='离线固定版本内核包')
    p.add_argument('--check-only', action='store_true', help='只检查，不安装')
    args = p.parse_args()
    if not shutil.which('ssh'):
        raise ValueError('找不到 ssh；请安装 OpenSSH，Windows 可在 WSL 中运行')
    host = str(ipaddress.IPv4Address(args.router or input('路由器地址：').strip()))
    user = args.user or input('SSH 用户名 [admin]：').strip() or 'admin'
    port = args.port or int(input('SSH 端口 [22]：').strip() or '22')
    if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_-]{0,31}', user) or not 1 <= port <= 65535:
        raise ValueError('用户名或端口不正确')
    args.backup_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='sc-panel-') as td:
        private = Path(td)
        options = ['-p', str(port), '-o', 'ConnectTimeout=10', '-o', 'ControlMaster=auto',
                   '-o', 'ControlPersist=300', '-o', 'ControlPath=' + str(private / 'ssh')]
        target = user + '@' + host
        remote_dir = '/tmp/sc-panel-' + private.name.removeprefix('sc-panel-')
        ssh = ['ssh', *options, target]

        def remote(command, *, data=None, capture=False):
            result = subprocess.run([*ssh, command], input=data,
                                    stdout=subprocess.PIPE if capture else None)
            if result.returncode:
                raise RuntimeError('SSH 操作失败；请检查上方提示')
            return result.stdout

        backup = args.backup_dir / ('shellcrash-before-' + host + '-' + private.name + '.tar.gz')
        changed = False
        connected = False
        try:
            print('\n1/4 连接路由器。SSH 密码由 ssh 自己询问。')
            raw = remote('set -- started_script.sh; for f in ShellCrash/configs/cn_ip.txt ShellCrash/cn_ip.txt; do [ ! -f /etc/storage/$f ] || set -- "$@" "$f"; done; [ ! -f /etc/storage/ShellCrash/jsons/config.json ] || set -- "$@" ShellCrash/jsons/config.json; [ ! -f /etc/storage/chinadns/chnroute.txt ] || set -- "$@" chinadns/chnroute.txt; tar -czf - -C /etc/storage "$@"', capture=True)
            connected = True
            snapshot = read_snapshot(raw)
            source = snapshot.get('ShellCrash/jsons/config.json')
            cn = snapshot.get('ShellCrash/configs/cn_ip.txt') or snapshot.get('chinadns/chnroute.txt') or snapshot.get('ShellCrash/cn_ip.txt') or (ROOT / 'examples/cn_ip.default.txt').read_bytes()
            subscription = None
            if not args.check_only:
                prompt = '订阅链接（不回显；回车沿用现有节点）：' if source else '首次安装，请输入订阅链接（不回显）：'
                url = '' if args.nodes_file else getpass.getpass(prompt).strip()
                if args.nodes_file:
                    source = args.nodes_file.read_bytes()
                    if len(source) > MAX_INPUT:
                        raise ValueError('节点文件超过 512 KiB')
                if url:
                    if urllib.parse.urlsplit(url).scheme != 'https':
                        raise ValueError('安装助手仅接受 HTTPS 订阅链接')
                    if len(url) > 2048 or re.search(r'\s', url):
                        raise ValueError('订阅链接过长或包含空白')
                    subscription = private / 'subscription.b64'
                    subscription.write_bytes(base64.b64encode(url.encode()))
                    print('正在读取订阅…')
                    try:
                        with urllib.request.urlopen(url, timeout=30) as response:
                            source = response.read(MAX_INPUT + 1)
                    except Exception:
                        raise ValueError('订阅下载失败，请检查链接和电脑网络') from None
                    if len(source) > MAX_INPUT:
                        raise ValueError('订阅超过 512 KiB')
            if source is None:
                if not args.check_only:
                    raise ValueError('首次安装需要 AnyTLS 或 sing-box JSON 订阅链接')
                # This profile is used only for preflight and never started.
                source = json.dumps({'outbounds': [{'type': 'anytls', 'tag': '检查占位节点', 'server': 'probe.invalid', 'server_port': 443, 'password': 'check-only'}]}).encode()
            (private / 'nodes.json').write_text(json.dumps({'outbounds': subscription_nodes(source)}, ensure_ascii=False))
            (private / 'cn.txt').write_bytes(cn)
            profile, secret = private / 'config.json', private / 'secret'
            subprocess.run([sys.executable, str(ROOT / 'tools/prepare_profile.py'), '--input', str(private / 'nodes.json'),
                            '--output', str(profile), '--lan-ip', host, '--secret-file', str(secret),
                            '--cn-list', str(private / 'cn.txt')], check=True)
            print('2/4 上传安装文件，检查兼容性。')
            quoted = shlex.quote(remote_dir)
            remote('umask 077; mkdir ' + quoted + ' && tar -xzf - -C ' + quoted,
                   data=make_upload(profile, secret, subscription, args.core_file))
            command = 'cd ' + quoted + '/package && sh install.sh --check --profile ../config.private.json'
            if args.core_file is not None:
                command += ' --core-file ../core-offline.tar.gz'
            remote(command)
            if args.check_only:
                print('检查通过，没有修改 ShellCrash 配置。')
                return
            print('3/4 把安装前配置备份到电脑。')
            with backup.open('xb') as output:
                backup.chmod(0o600)
                result = subprocess.run([*ssh, 'sh ' + quoted + '/package/backup.sh -'], stdout=output)
            if result.returncode:
                raise RuntimeError('备份下载失败，未开始安装')
            with tarfile.open(backup) as archive:
                if not archive.getnames():
                    raise ValueError('备份为空，未开始安装')
            print('备份：' + str(backup.resolve()))
            print('4/4 安装面板并验证启动，可能需要等待几分钟。')
            changed = True
            install = 'cd ' + quoted + '/package && sh install.sh --install --profile ../config.private.json --secret-file ../panel-secret.private'
            if subscription is not None:
                install += ' --subscription-file ../subscription.private'
            if args.core_file is not None:
                install += ' --core-file ../core-offline.tar.gz'
            remote(install)
            print('\n安装完成。打开 http://' + host + '，登录后点击「高级设置 → ShellCrash」。')
            print('以后可在网页更新订阅、切节点和查看日志。')
        except Exception:
            if changed:
                print('安装没有正常完成。备份保存在：' + str(backup.resolve()), file=sys.stderr)
            raise
        finally:
            if connected:
                subprocess.run(['ssh', *options, '-o', 'BatchMode=yes', target, 'rm -rf ' + shlex.quote(remote_dir)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                subprocess.run(['ssh', *options, '-O', 'exit', target], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, RuntimeError, OSError, subprocess.CalledProcessError, tarfile.TarError) as exc:
        print('未完成：' + str(exc), file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print('\n已取消。', file=sys.stderr)
        sys.exit(130)
