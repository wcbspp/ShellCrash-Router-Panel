# 固件与依赖

面板包部署ShellCrash工具和网页适配，不含固件，不刷机，也不会替你开启SSH。

## 电脑

Python 3.9或更新版本、OpenSSH客户端；在线安装与离线准备还要能访问GitHub和固定内核源。日常打开面板只需浏览器，不需要电脑一直开着。

macOS / Linux可直接运行，Windows使用WSL。安装助手只用Python标准库，普通安装不需要pip、Node.js、Lua或lupa；后几项只用于项目开发测试。

## AX5

验证环境是Redmi AX5 / RA67、ARMv7、小米原厂开发版1.0.105。安装器核对硬件与固件信息，并检查LuCI、Lua、cjson、nixio、curl、openssl、tar、iptables、stat等接口。

请先自行开启SSH，可参考[XMiR-Patcher](https://github.com/openwrt-xiaomi/xmir-patcher)。固件获取和刷写按设备适用的官方或维护者说明进行，不要用别的小米型号说明替代本机步骤。

首次安装同时检查压缩内核、工具、源码和闪存余量；解压及核心配置检查另算RAM预算，保留24MiB工作余量。源码更新按最大待替换文件和剩余空间核算，不用一个固定“剩余多少MB”保证所有安装都能成功。

## K2P

验证环境是K2P / MT7621 / 16MB闪存，Padavan 4.4.198.9-100_20220804、Linux4.4.198，Storage为512KiB。要求原httpd和自定义网页接口，以及nvram、curl、iptables、ipset、bzip2、sha256sum、mtd_write、mount、stat、awk、tar、base64、crontab。

安装助手带有注明来源的ShellCrash1.9.4工具，不用事先单独安装同一套工具。原“科学上网”插件要先停用运行开关，防止重复接管，保留配置即可。未知ShellCrash部署或自定义启动钩子不会被强行覆盖。

程序保存到Storage前检查压缩大小，不能拿RAM余量当持久空间。内核默认在RAM运行，重启后从匹配缓存、已验证WebDAV或配置的下载源恢复，文件仍须通过SHA校验。

旧项目曾提供使用者保存的2022年历史固件：完整插件版与当时实机只读分区字节一致，其余三份只做过静态检查，未刷机验证。编译者、源码提交和编译配置没有全部核实，因此本仓库不重新打包这些固件；旧附件和核验记录已另行备份。

K2P 32MB改版、USB改造和其他Padavan分支需要分别验证。型号看起来相同，也不要跳过预检。
