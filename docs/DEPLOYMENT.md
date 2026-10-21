# 安装、更新与离线准备

安装助手在电脑运行，通过 SSH 部署到路由器。它不会刷固件，也不负责开启 SSH。先核对[支持固件与依赖](FIRMWARE.md)，保存固件配置，再连接局域网。

## 选哪个文件

下载对应机型的 `shellcrash-router-panel-ax5-1.0.0.tar.gz` 或 `shellcrash-router-panel-k2p-1.0.0.tar.gz`。`source` 是开发源码，不是直接安装包；`SHA256SUMS` 用于核对下载文件。

解压后运行 `python3 start.py`。macOS 可双击 `Install.command`；不能双击时用终端 Python 命令，不必关闭系统安全设置。Windows 使用 WSL。

向导会让你选择安装、更新或只检查，再填地址。密码由 OpenSSH 询问；首次连接请核对主机指纹，不要关闭 SSH 主机检查。

## 在线安装

从 README 下载 `shellcrash-install.py` 后运行，不指定机型会出现选择提示。默认地址 AX5 为 `192.168.31.1`、K2P 为 `192.168.123.1`，改过地址就用实际地址。

```sh
python3 shellcrash-install.py ax5 --router 192.168.31.1 --check-only
python3 shellcrash-install.py k2p --router 192.168.123.1 --user admin --port 22
```

电脑需要能访问 GitHub，路由器首次取内核也要能连接对应内核源。电脑能下载，不代表路由器能下载；遇到这种情况，先准备离线文件夹。

AX5 首装保持真实 DNS 和全直连，随后在面板填订阅。K2P 首装询问兼容订阅，输入不回显；SSR 不能用于 sing-box mini。面板沿用原路由器后台登录，不另设密码。

## 已有面板怎么更新

向导选“更新已有面板”，或在解压后的包里运行：

```sh
python3 start.py --update --router 路由器地址
# 只检查时再加 --check-only
```

AX5 由原安装器识别部署后更新源码，K2P 使用独立更新入口。先保存电脑备份，再更新页面和适配代码，保留配置、内核、节点选择与原有启动钩子。备份默认在 `~/ShellCrash-backups/`，可用 `--backup-dir` 修改。

旧项目迁移也走此入口。已知旧版按校验识别；未知修改和自定义钩子会被拒绝。不要删检查文件强行安装，先保留提示和旧备份。

## 准备离线文件夹

有网电脑运行 `python3 shellcrash-install.py ax5 --prepare-offline`，K2P把 `ax5` 换成 `k2p`。已解压的安装包可运行 `python3 start.py --prepare-offline`。准备只下载和校验，不连接路由器；输出目录已存在就停止，避免覆盖旧文件。

已有同版本内核时加 `--core-file /路径/core.tar.gz`，仍检查机型、版本和 SHA256，不放宽本地文件校验。

带走完整文件夹，在连接路由器的电脑运行 `python3 start.py`。K2P离线首装要另带本地节点文件，也可直接指定：

```sh
python3 start.py --offline --router 192.168.123.1 --nodes-file /路径/nodes.json
```

支持兼容的 sing-box JSON 或 AnyTLS 文本。节点文件可能含密码，放在安装包外，不要提交到 GitHub。AX5 离线首装先用直连配置，不需要节点文件。

## 离线时要注意什么

离线准备下载固定基线内核，让首次安装不必从路由器访问公网；不会自动打包服务商的所有外部规则和高级面板。

K2P 内核运行在 RAM，断电后会消失。长期离线使用，要先准备可访问且已校验的同内核 WebDAV 备份，或单独验证外部持久存储方案。装过一次离线包，不等于以后离线冷启动都能自行恢复。AX5 将压缩内核保存在 `/data`，不把解压后的大文件常驻闪存。

## 没完成时先看这里

- **缺Python或ssh**：补齐电脑依赖，路由器不用安装。
- **SSH失败**：核对地址、用户名、端口和SSH开关。输入密码时没有回显是正常现象。
- **空间不足、缺设备命令**：按预检提示处理，别删备份或降低内存保护绕过检查。
- **首次启动等待较久**：K2P会分阶段准备和检查核心，终端还在等就绪时不要重复安装或断电。
- **菜单没出现**：刷新原后台，K2P安装时退出其他管理页面。
- **更新失败**：保存终端提示和电脑备份，参照[恢复说明](BACKUP.md)。
