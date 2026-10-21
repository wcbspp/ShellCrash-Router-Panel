#!/usr/bin/env python3
"""Computer-side guided entry for a verified device package."""
import argparse
import ipaddress
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent

def main(argv=None):
    parser = argparse.ArgumentParser(description='ShellCrash 安装助手（在电脑上运行）')
    parser.add_argument('--router', help='路由器的局域网 IPv4 地址')
    parser.add_argument('--user', help='SSH 用户名')
    parser.add_argument('--port', type=int, default=22)
    parser.add_argument('--update', action='store_true', help='更新已有面板，保留配置')
    parser.add_argument('--check-only', action='store_true', help='只检查环境，不安装或重启')
    parser.add_argument('--offline', action='store_true', help='使用文件夹内的离线内核和本地节点文件')
    parser.add_argument('--prepare-offline', action='store_true', help='在有网电脑上准备可带走的离线文件夹')
    parser.add_argument('--core-file', type=Path)
    parser.add_argument('--nodes-file', type=Path)
    parser.add_argument('--backup-dir', type=Path, default=Path.home()/'ShellCrash-backups')
    args = parser.parse_args(argv)
    if sys.version_info < (3, 9):
        raise ValueError('需要 Python 3.9 或更新版本。Windows 请在 WSL 里运行。')
    from tools.verify_package import verify
    verify(ROOT, [args.core_file, args.nodes_file])
    device = (ROOT/'DEVICE').read_text().strip()
    if device not in ('ax5', 'k2p'):
        raise ValueError('这不是 AX5 或 K2P 安装包，请重新下载对应文件。')
    if args.prepare_offline:
        command = [sys.executable, str(ROOT/'tools/prepare_offline.py'), device]
        if args.core_file: command += ['--core-file', str(args.core_file.expanduser())]
        return subprocess.run(command).returncode
    if not shutil.which('ssh'):
        raise ValueError('电脑缺少 OpenSSH。macOS/Linux 请先安装 ssh；Windows 请使用带 OpenSSH 的 WSL。')
    if not args.router:
        if not sys.stdin.isatty():
            parser.error('请加 --router 指定路由器地址，或在终端直接运行以使用向导。')
        print('\nShellCrash · '+('小米 AX5' if device=='ax5' else 'K2P / Padavan'))
        print('电脑先保存备份，再由设备安装器检查和部署。密码只在 SSH 提示时输入。')
        if not args.update and not args.check_only:
            answer = input('1 安装面板  /  2 更新已有面板  /  3 只检查  /  q 退出：').strip().lower()
            if answer == 'q': return 0
            if answer not in ('1', '2', '3'): raise ValueError('请输入 1、2、3 或 q；还没有连接路由器。')
            args.update = answer == '2'; args.check_only = answer == '3'
        default = '192.168.31.1' if device=='ax5' else '192.168.123.1'
        args.router = input('路由器地址 ['+default+']：').strip() or default
        args.user = args.user or input('SSH 用户名 ['+('root' if device=='ax5' else 'admin')+']：').strip()
    args.router = str(ipaddress.IPv4Address(args.router))
    args.user = args.user or ('root' if device=='ax5' else 'admin')
    if not 1 <= args.port <= 65535: raise ValueError('SSH 端口应为 1–65535。')
    offline_core = ROOT/'core-offline.tar.gz'
    if not args.core_file and offline_core.is_file(): args.core_file = offline_core
    offline = args.offline or bool(args.core_file)
    if offline and not args.update and not args.core_file:
        raise ValueError('离线安装缺少 core-offline.tar.gz。先在有网电脑运行 --prepare-offline，再带走整个文件夹。')
    if offline and device=='k2p' and not args.update and not args.check_only and not args.nodes_file:
        if not sys.stdin.isatty(): parser.error('K2P 离线首次安装请加 --nodes-file 指定 sing-box JSON 或 AnyTLS 文本。')
        filename = input('本地节点文件路径（sing-box JSON 或 AnyTLS 文本，不填订阅网址）：').strip()
        if not filename: raise ValueError('未选择节点文件，尚未安装。')
        args.nodes_file = Path(filename).expanduser()
    for path in (args.core_file, args.nodes_file):
        if path and not path.expanduser().is_file(): raise ValueError('找不到本地文件：'+str(path))
    script = 'update.py' if args.update and device=='k2p' else 'deploy.py'
    command = [sys.executable, str(ROOT/script), '--router', args.router, '--user', args.user,
               '--port', str(args.port), '--backup-dir', str(args.backup_dir.expanduser())]
    if args.check_only: command += ['--check-only']
    if script=='deploy.py':
        for option, value in (('--core-file', args.core_file), ('--nodes-file', args.nodes_file)):
            if value: command += [option, str(value.expanduser())]
    print('\n'+('仅检查环境' if args.check_only else '更新已有面板' if args.update else '开始安装')+'；目标 '+args.router)
    print('安装前备份保存在：'+str(args.backup_dir.expanduser()))
    return subprocess.run(command).returncode

if __name__=='__main__':
    try: sys.exit(main())
    except KeyboardInterrupt: print('\n已取消。若已开始部署，请检查终端最后的恢复提示。');sys.exit(130)
    except (ValueError, OSError) as exc: print('未完成：'+str(exc),file=sys.stderr);sys.exit(1)
