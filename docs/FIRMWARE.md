# 固件与环境

面板安装包只部署 ShellCrash 工具和管理适配，不含固件，不执行刷机。

## AX5

实机为 Redmi AX5 / RA67、原厂开发版 1.0.105、ARMv7。安装器读取 `/usr/share/xiaoqiang/xiaoqiang_version` 核对硬件与固件，要求 LuCI、Lua、cjson、nixio、curl、openssl、iptables 等接口。其他小米机型即使有类似后台也不能跳过检查。

需要先开启 SSH，可参考 XMiR-Patcher 官方项目。固件获取与刷机按该设备适用的官方/维护者流程进行；本仓库不把其他来源的固件当作官方固件重新打包。

## K2P

实机为 K2P / MT7621 / 16 MB 闪存，Padavan 4.4.198.9-100_20220804，Linux 4.4.198。Storage 分区为 512 KiB。要求 Padavan httpd、自定义网页入口、nvram、curl、iptables、ipset、bzip2、sha256sum、mtd_write、mount、awk、tar、base64、crontab。

旧项目提供过四份使用者保存的 2022 年历史固件，完整插件版与实机只读 firmware 分区字节一致；其余三份只做静态格式与校验验证，没有刷机验证。确切编译者、源码提交和编译配置尚未核实，因此不作为新项目默认依赖包或随源码重新分发。

参考记录：[旧固件核验说明](https://github.com/wcbspp/K2P-Padavan-shellcrash-panel/blob/main/docs/FIRMWARE.md)。已有兼容固件可直接进行环境预检。32 MB 改版和 USB 改造版需要分别验证，不能用“同为 K2P”保证兼容。
