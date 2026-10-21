# 固件、SSH与依赖

面板负责安装ShellCrash工具和网页适配，不刷固件，也不自动开启SSH。先备好固件、SSH和电脑环境，再运行安装向导。

## 下载与上游

| 项目 | 入口 | 说明 |
| --- | --- | --- |
| ShellCrash | [官方上游仓库](https://github.com/juewuy/ShellCrash) | 本面板适配1.9.4release，安装包带有工具，不必先重复安装 |
| AX5固件 | [小米官方1.0.105文件](https://cdn.cnbj1.fds.api.mi-img.com/xiaoqiang/rom/ra67/miwifi_ra67_firmware_59980_1.0.105.bin) · [官方下载页](https://www.miwifi.com/miwifi_download.html) | Redmi AX5 / RA67，官方标注稳定版 |
| AX5 SSH | [XMiR-Patcher作者仓库](https://github.com/openwrt-xiaomi/xmir-patcher) | 社区维护工具，按其说明操作，不是小米官方解锁服务 |
| K2P配套固件 | [固件与校验文件](https://github.com/wcbspp/ShellCrash-Router-Panel/releases/tag/firmware-k2p-16m-4.4.198.9-100) | 使用者保存的16MB K2P固件，具体文件见下方 |
| Padavan源码参考 | [hanwckf/rt-n56u](https://github.com/hanwckf/rt-n56u) | 不把它直接当作所附二进制的确切构建来源 |

## 电脑

需要Python 3.9+和OpenSSH客户端。macOS / Linux可直接运行，Windows使用WSL。在线安装和离线准备需要访问GitHub与固定内核源，日常用面板只需浏览器，电脑不用一直开着。

普通安装仅使用Python标准库，不需要pip或Node.js。开发测试用的Node.js和lupa与安装依赖分开，路由器不装这些电脑端运行环境。

## AX5

实机环境为Redmi AX5 / RA67、原厂1.0.105、ARMv7。小米[官方下载接口](https://api.miwifi.com/upgrade/log/latest?typeList=RA67STA)将1.0.105标为稳定版，对应上方官方直链；不要把名称相近的小米AX1800固件混用。

安装前按XMiR-Patcher作者说明开启SSH，确认能用root登录。该工具与本面板各自有适用范围，面板不会替它执行解锁步骤。已运行兼容固件、SSH正常的设备不必重刷。

设备需有LuCI、Lua、cjson、nixio、curl、openssl、tar、iptables、stat等接口。安装时检查压缩内核、工具和源码的闪存预算；解压与配置检查还要留出RAM工作余量。源码更新另按待替换文件大小核算，不能用一个固定剩余MB数保证所有安装都能完成。

## K2P

实机环境为K2P / MT7621 / 16MB闪存，Padavan 4.4.198.9-100_20220804、Linux4.4.198，Storage为512KiB。这里的16MB指闪存，不是内存。

[完整插件版固件下载](https://github.com/wcbspp/ShellCrash-Router-Panel/releases/download/firmware-k2p-16m-4.4.198.9-100/K2P-16M-4.4.198.9-100-trojan-v2ray-xray-zerotier.trx)与实机firmware分区对应字节一致，是本面板验证所用版本。另附的精简、纯净和USB版只完成静态格式、CRC与大小检查，未刷机验证；普通K2P不要选K2P-USB文件。

这些文件由使用者保存提供，原编译者、确切源码提交和完整编译配置尚未核实，不标为Padavan官方发行。原文件内容及SHA保持不变，发布页附长度、产品标识、校验清单与具体范围。32MB改版、USB改造和其他Padavan分支需要分别验证。

设备使用原httpd、自定义网页接口、nvram、curl、iptables、ipset、bzip2、sha256sum、mtd_write、mount、stat、awk、tar、base64、crontab等命令，相关管理和升级功能也使用固件的Lua模块。预检遇到缺项或未知启动钩子会停止，不靠删检查文件强行安装。

安装前关闭原“科学上网”运行开关，保留配置，退出其他管理页面。安装助手带有ShellCrash1.9.4工具。保存Storage前检查压缩大小；RAM有空余，不代表512KiB Storage一定装得下。

K2P内核默认在RAM运行，重启后从匹配缓存、已验证WebDAV或配置的同版本源恢复，下载仍要校验SHA。离线首装不等于以后每次离线冷启动都能自动恢复，详见[离线注意事项](DEPLOYMENT.md#离线时要注意什么)。
