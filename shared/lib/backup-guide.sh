#!/bin/sh
# Generate a small, human-readable companion; never evaluate archive contents.
set -eu
out=$1;model=$2;scope=$3
case "$model:$scope" in AX5:application|K2P:application|AX5:full|K2P:full) :;;*)exit 2;;esac
[ -d "$out" ] || exit 2
cat > "$out/使用说明.txt" <<EOF
ShellCrash 面板备份说明
设备：$model

先看这里
这不是路由器固件包，不能通过刷机页面上传。备份含订阅、节点密码等私人信息，请勿公开。
只恢复同机型、同架构且受支持固件上的本应用，不修改 Wi-Fi、LAN、SSH 或 ZeroTier 身份。
WebDAV 账号密码不在备份里。恢复远端备份前需使用当前设备已验证的连接设置。

文件用途
application.tar.gz：面板与 ShellCrash 程序，以及备份时的订阅、DNS、分流和启动设置。
core.tar.gz：与这份备份匹配的代理内核。不能随便换成其他版本。
runtime-assets.tar.gz：已安装的高级面板、运行所需规则资源；AX5 的持久规则也可能在应用包内。
manifest.json：组件名称、大小、SHA256 和版本；程序据此匹配文件，不需要逐个选择内核或数据库。
source.tar.gz：如有，这是项目开发源码供查阅，不参与设备恢复，也不包含第三方内核开发源码。
RESTORE.txt：此格式的技术恢复说明。使用说明.txt：本说明。

如何选择
完整备份请保持整个目录的组件和 manifest.json 放在一起，或保留完整 ZIP，不要重命名组件。
WebDAV 手动导入目录为 shellcrash-panel/$model/imports/：每份备份单独一个目录，例如 imports/my-backup/。
请放入目录时一次传完，再打开恢复窗口或点击刷新。发现备份不会自动还原。
只有一个 application-backup.tar.gz 是应用与配置导出，缺少内核和运行资源，不能当完整备份。

完整回退流程
1. 保留当前可用备份，在局域网内操作，确保设备供电和远端连接稳定。
2. 选择备份，先检查机型、备份时间、版本、组件完整性和空间预算。
3. 阅读覆盖清单并确认：完整回退会恢复当时的程序及配置，覆盖之后的订阅、DNS、分流等修改。
4. 程序逐项校验和恢复；不要拔电、切断网络或重复提交。恢复需要暂停代理服务。
5. 等待结果，再检查节点、网站、DNS、分流、自启，以及当前管理页面能否重新打开。
6. 失败时保留错误记录，优先按提示恢复操作前的备份，不要反复用不完整文件覆盖。

低内存说明
分块传输能减少传输占用，但解压和内核校验仍需要空间。空间不足应在修改前停止。
请不要直接把整个 ZIP 或应用包解压覆盖到运行中的路由器上。
EOF
if [ "$scope" = application ];then
 cat >> "$out/使用说明.txt" <<'EOF'

本文件所在包是“应用与配置导出”，不是包含所有组件的完整包。
当前版本是否支持自动导入，以恢复页面实际能力和校验结果为准；不要自行运行包里的脚本。
EOF
fi
