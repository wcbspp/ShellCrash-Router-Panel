# ShellCrash Router Panel

在路由器原来的管理页里，用网页管理 ShellCrash：选节点、更新订阅、设置分流和 DNS，查看内存与日志，需要时再打开高级面板。

**1.0 正式版**，支持 Redmi AX5 和 K2P / Padavan。两个旧项目合并到这里，以后按机型下载安装包即可。已有设备先看[更新说明](docs/DEPLOYMENT.md#已有面板怎么更新)，不要把另一机型的文件直接覆盖上去。

[下载1.0](https://github.com/wcbspp/ShellCrash-Router-Panel/releases/tag/v1.0.0) · [安装说明](docs/DEPLOYMENT.md) · [备份与恢复](docs/BACKUP.md) · [与旧版相比](docs/COMPARISON.md)

## 先确认设备

| | Redmi AX5 | K2P |
| --- | --- | --- |
| 验证过的硬件 | RA67，ARMv7 | MT7621，16 MB 闪存 |
| 验证过的固件 | 小米原厂开发版 **1.0.105** | Padavan **4.4.198.9-100_20220804** |
| 支持的内核 | sing-box mini 1.12.13、Mihomo 1.19.28 | sing-box mini 1.12.13 |
| 页面入口 | 小米后台顶部 **ShellCrash** | 高级设置 → **ShellCrash** |
| 订阅 | 服务商直取，也保留 ShellCrash 转换方式 | 服务商直取、同源兼容下载 |
| 保存位置 | `/data/ShellCrash` | `/etc/storage/ShellCrash`，保存到 Storage |

**这不是固件，不会替你刷机或开启 SSH。** 其他型号、其他固件、K2P 32 MB 改版没有逐一验证。sing-box mini 不支持 SSR，换面板也不会增加内核没有的协议。

## 安装前准备

- 电脑连接路由器局域网，路由器已开启 SSH。AX5 通常用 `root`，K2P 通常用 `admin`，以你的设置为准。
- 电脑安装 **Python 3.9+ 和 OpenSSH**。macOS / Linux 可直接使用；Windows 请在 WSL 里运行。路由器不用安装 Python、Node.js 或额外网页服务。
- 保存固件配置。助手还会把本次修改前的文件备份到电脑的 `~/ShellCrash-backups/`。
- K2P 先关闭原“科学上网”插件的运行开关，保留其配置，安装时退出其他管理页面。
- 订阅或节点自己准备。K2P 首次安装支持兼容的 sing-box JSON 或 AnyTLS 链接；订阅输入不回显。

设备所需命令和存储要求见[固件与依赖](docs/FIRMWARE.md)。缺依赖、空间不足或检测到未知部署时，安装器会停止，不强行覆盖。

## 在线一键安装

**在电脑终端运行，不是在路由器 SSH 里运行：**

```sh
curl -fL https://raw.githubusercontent.com/wcbspp/ShellCrash-Router-Panel/v1.0.0/bootstrap.py -o shellcrash-install.py
python3 shellcrash-install.py
```

按提示选 AX5 或 K2P，再选安装、更新或只检查。助手核对下载包 SHA256 后才进入设备安装流程。密码由 SSH 自己询问，不必写进命令。

已知地址时也可直接指定；地址改过就填实际地址：

```sh
python3 shellcrash-install.py ax5 --router 192.168.31.1
python3 shellcrash-install.py k2p --router 192.168.123.1
```

自定义用户名和端口加 `--user`、`--port`，只检查加 `--check-only`。GitHub 下载不通时，从 [Releases](https://github.com/wcbspp/ShellCrash-Router-Panel/releases/tag/v1.0.0) 下载对应机型 `.tar.gz`，解压后运行 `python3 start.py`。macOS 也可双击 `Install.command`。

## 离线一键安装

先在**有网络的电脑**上准备，二选一：

```sh
python3 shellcrash-install.py ax5 --prepare-offline
python3 shellcrash-install.py k2p --prepare-offline
```

助手下载并分别校验面板和固定版本内核，生成 `shellcrash-router-panel-机型-offline-1.0.0` 文件夹。在已解压的安装包里，也可运行 `python3 start.py --prepare-offline`。

把**整个文件夹**带到连接路由器的电脑，进入文件夹运行：

```sh
python3 start.py
```

内核会自动从本地文件读取。K2P 离线首次安装还要带上本地节点文件，按提示填写路径，不要填订阅网址。离线安装不会为了获取内核和节点访问公网；高级面板和订阅额外资源另算。K2P 内核运行在 RAM，重启后的离线恢复需要另行准备，见[离线注意事项](docs/DEPLOYMENT.md#离线时要注意什么)。

## 实机页面

以下是统一版在两台设备上的实际页面。节点名、延迟、内存和运行时间是截图当时的状态，不是性能保证。

**AX5 · 小米原厂后台**

![AX5实机轻量面板](docs/assets/ax5-desktop.jpg)

**K2P · 轻量面板**

![K2P实机轻量面板](docs/assets/k2p-desktop.jpg)

<details>
<summary>手机页面</summary>

<img src="docs/assets/ax5-mobile.jpg" width="280" alt="AX5实机手机页面">
<img src="docs/assets/k2p-mobile.jpg" width="280" alt="K2P实机手机页面">

</details>

[更多截图与来源](docs/SCREENSHOTS.md)

## 日常可以做什么

| 页面 | 常用操作 |
| --- | --- |
| 节点 | 按实际策略组切换、搜索，按需分别看 Ping 和 HTTPS 耗时 |
| 检测 | 检查常用网站连接，区分超时、DNS、TLS 等问题 |
| 配置 | 更新订阅，设置 User-Agent、节点过滤和内核来源 |
| 分流与 DNS | 常用网站指定出口，额外域名覆盖，真实 DNS / Mix 与 Fake IP 例外 |
| 备份 | WebDAV 测试和保存，完整备份、独立基础备份，同机型同内核恢复 |
| 监控与日志 | 内存趋势、保护阈值、清理、异常与内核日志 |
| 高级面板 | sing-box 使用 YACD，Mihomo 使用 Yacd-Meta，共用当前内核与选择 |

关掉网页，代理和内核自动择优仍会运行。轻量测速不再连测三次；HTTPS 耗时包含连接和握手，与 Ping、已有连接后的使用体验不是同一个数值。

## 几个容易弄混的地方

- **直连、规则、全局 TCP**只描述本机接管范围。全局 TCP 不等于全协议 VPN，不保证普通 UDP 和 IPv6 一并代理；切模式后用新连接判断。
- **K2P 不提供第三方订阅转换。** AX5 使用转换服务时，对方会收到订阅地址，请自行选择可信服务。
- **应用导出不等于完整恢复。** 完整备份包括程序、配置、匹配内核和运行资源；恢复前检查机型、内核、组件与设备条件，再要求二次确认。
- **小内存设备不适合无限加压。** AX5 实测16路连接半小时；K2P加到23路后触及测试安全余量，主动停流。不能当作64路持续高负载通过。连续24小时和部分业务边界仍未覆盖，见[1.0使用范围](docs/RELEASE_1.0.md)。

## 开发与来源

公共页面和脚本在 `shared/`，固件接口在 `profiles/`。构建后生成各自安装包，路由器不运行模板编译器。开发测试需要 Node.js 和 `lupa==2.8`，这些不是路由器安装依赖。

```sh
python3 -m pip install lupa==2.8
python3 tools/build.py all
python3 tools/check_baseline.py
python3 -m unittest discover -s tests
python3 tools/run_tests.py all
python3 tools/package.py
```

基于 [ShellCrash](https://github.com/juewuy/ShellCrash) 1.9.4release；内核来自 [sing-box](https://github.com/SagerNet/sing-box) / [Mihomo](https://github.com/MetaCubeX/mihomo)，高级面板来自 [YACD](https://github.com/haishanh/yacd) / [Yacd-Meta](https://github.com/MetaCubeX/Yacd-meta)。来源和许可见 [NOTICE](NOTICE.md)、[LICENSE](LICENSE)。发布包不含私人订阅、密码、设备身份、内核二进制或路由器固件。
