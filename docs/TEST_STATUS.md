2026-10-21 RC3最终检查：两机完整备份读回校验与现场保持通过；根138/AX92 Python+27JS/K212 Python+29JS、构建与基线通过。AX16路半小时，K23路约6分钟触及测试安全余量停流；均无新增kill，但完整高负载不算通过。用户明确不等待24h，原业务未验项保留。见[最终检查](RC3_FINAL_CHECK.md)与[RC3限制](RELEASE_RC3.md)。

2026-10-21私有RC3收尾：用户明确不再等待满24小时。实际未满24h、AX持续负载仅16路通过、K负载本轮结论与业务边界未全验均如实保留，不宣布全P0通过。两机新装/跨版、恢复及新增HTTP失败边界证据沿用。见[RC3说明](RELEASE_RC3.md)。以下历史状态不覆盖此决定。

2026-10-21 17:35最新：两机原生及认证HTTP真实跨版本正向已通过并恢复现场；AX HTTP下载404/非归档自动回退、K来源预检失败边界、AX桌面/窄屏恢复弹窗只读边界已补齐。AX16路真实代理持续半小时无重启/新增kill，仅部分负载通过，K阶段进行中；完整负载/业务边界/最终连续24h仍开放，非RC3。详见[本批边界记录](LIVE_TEST_2026-10-21_HTTP_BOUNDARIES.md)。以下为保留的历史记录，进行中状态以本段和私有最新status为准。

Latest AX current-source HTTP positive completed: real1.19.27->1.19.28, config bytes/18 selectors/formal readiness/explicitHTTPS204 CONNECT200 and original restore/sourceSHA verified. Native post-replacement incompatible-architecture rollbackv4 also passed. Root138/AX92Python+27JS/build/baseline pass. HTTP failure/load/memory/business/final24h gates remainOPEN; notRC3.

2026-10-21 AX5: extraction memory and pinned CDN URL guards fixed; root138/AX92Python+27JS/build/baseline pass. Genuine incompatible-architecture post-replacement product rollback restored1.19.28, exact configuration and18 selectors with explicitHTTPS204 CONNECT200; independent recovery verified. Current-source HTTP positive is running. Remaining failure/load/business/24h gates OPEN; notRC3.

2026-10-21 12:50最新：K2P原生及认证HTTP网页后台真实1.12.12->1.12.13均通过，3选择/配置字节/显式HTTPS204 CONNECT200及最终Storage原现场恢复核对；FD修复后无新增内核kill。根138/K212 Python+29JS/build/baseline通过。AX已过新装和两入口正向，替换后失败回退、持续负载/内存保护/业务边界和最终24h仍待验，非RC3。

2026-10-21 12:40：K v12启动FD链接失效，后续额外归档路径期间OOM杀ZeroTier；用户恢复通道，原1.12.13/config/Storage与显式HTTPS204 CONNECT200已核对恢复。修复FD继承并禁止复用失败时下载归档回补，根138/K212 Python+29JS/build/baseline通过；真实v13进行中，完整升级仍待验。见[跨版本记录](LIVE_TEST_2026-10-21_CORE_UPGRADE.md)。

# 当前验证状态

2026-10-16 按需节点诊断已接通：列表保留一次内核HTTPS，点击后分别测原生Ping/HTTPS且串行。AX当前mihomo、K当前sing-box真实页面通过，K示例67.772ms/463ms；AX目标无ICMP响应而HTTPS630ms。采样最低可用AX16540/K17764KiB，配置/PID/boot/cron保持。根122/AX87 Python27JS/K198 Python29JS通过；桌面正常及实际未知key拒绝/390布局通过，新增控件表保留部分通过，不冒称全部边界或AX切核实测。见[节点诊断](LIVE_TEST_2026-10-16_NODE_DIAGNOSTIC.md)。原最终RC门槛仍OPEN。

2026-10-16 K2P测速解释纠正（优先）：实机证实sing-box1.12.13忽略HTTP测试URL并回退HTTPS，上一轮“排除测试站TLS”不成立。现明确Gstatic HTTPS请求耗时，包含握手，不等于Ping/已有连接体验；高值原因进一步分解仍OPEN，未声称解决。见[K2P测速根因调查](LIVE_TEST_2026-10-16_K2P_DELAY_CAUSE.md)。

2026-10-16 测速口径修正：对比已安装高级面板资源与两机真实内核delay结果，确认旧Google HTTPS包含测试站TLS成本而非页面排队计时。轻量节点测速改Gstatic HTTP204，数值仍按内核原样显示；K实测HTTP未降低，不冒称全部虚高已解决。根112/AX87 Python26JS/K198 Python28JS通过，详见[测速地址对比](LIVE_TEST_2026-10-16_DELAY_TARGET.md)。其他最终RC门槛仍OPEN。

2026-10-16 节点测速改单次内核请求，直接显示返回延迟；同步两机“切换与保存”说明。实机AX当前页10节点10请求、K当前页1节点1请求；桌面/390px说明无溢出，无control写入。根112、AX87 Python26JS、K198 Python28JS通过。配置/PID/boot/cron保持，不重启；其余最终RC门槛仍待完成。见[单次测速验证](LIVE_TEST_2026-10-16_SINGLE_DELAY.md)。

2026-10-16 电脑助手快照修复：K2P只选最高优先级正规规则表，旧软链接不入包，严格归档检查保留；真机当前表逐字核对通过，现有部署电脑更新check-only通过，首次安装入口保护已有钩子拒绝覆盖。根112/K198 Python27JS通过。见[安装助手快照](LIVE_TEST_2026-10-16_INSTALLER_SNAPSHOT.md)。独立24小时只读采样已启动，尚未完成，不算长期通过。

2026-10-16 分级本地DIRECT并发：两机最终64条受控连接核对通过，预留线以上且配置/PID/boot保持，审计监听已清理；不是高吞吐/完整OOM或长期通过。e3761a0分发包两次构建SHA一致、全清单通过，工件仍未发布。见[并发与包验证](LIVE_TEST_2026-10-16_CONCURRENCY_PACKAGE.md)。

2026-10-16 原生清理/清日志保异常、两机各6项阈值后端拒绝已真测；修复K2P安装器依赖探测不兼容固件shell的问题。现有部署更新预检通过，未安装或重启。见[后端保护与安装预检](LIVE_TEST_2026-10-16_BACKEND_GUARDS.md)，其余发布门槛不变。

2026-10-16 监控/日志与运行查询补充：108项成功子检查，52个原结果位补充真实/浏览器注入证据并保留部分通过。AX5旧窄屏分页失败原轮不算通过，原因未定；本轮单独窄屏13项复测通过，失败记录保留。详见[监控与运行查询](LIVE_TEST_2026-10-16_MONITOR_INSPECTION.md)。无运行源码修改、恢复或重启；其余发布门槛保持待验。

2026-10-16 最新增量：31项展开说明、62个桌面/390px窄屏结果位已按实际条件完成；修复AX5诊断记录pre文本横向溢出。两机21部署路径SHA和配置/PID/boot/cron保护通过，根112、AX87 Python/25 JS、K197 Python/27 JS最终通过。详见[展开控件验收](LIVE_TEST_2026-10-16_READONLY_CONTROLS.md)。这不代替其余控件、不同版本升级冷启动或长期/高连接门槛。

2026-10-16 最新状态（优先于下方历史快照）：两机新增网页正常恢复、写后故障回退、180秒单次票据、二次确认和断线刷新已真实通过，符合条件的同内核恢复按钮已开放。原生CN-IP两入口共用持久事务，冷缓存完整资源备份已修并实测；AX5及K2P核心公网回补新增实际字节边界。最新根112项、K2P197 Python/27 JS通过；AX5源码未再修改，沿用87 Python/25 JS。详见 [网页恢复](LIVE_TEST_2026-10-16_PAGE_RESTORE.md)、[原生CN-IP](LIVE_TEST_2026-10-16_NATIVE_CN_IP.md)、[AX5下载边界](LIVE_TEST_2026-10-16_BOOT_DOWNLOAD_BOUND.md)及[K2P下载边界](LIVE_TEST_2026-10-16_K2P_DOWNLOAD_BOUND.md)。

最终私有RC仍待不同版本未备份升级/冷启动矩阵、全量菜单业务与安装升级、高连接OOM和长期稳定性等原门槛，不把上述通过扩写为全量验收。没有公开发布或替换旧稳定基础点。

2026-10-16 增量：两机同内核维护工具恢复与写入后受控故障回退已有实机证据；K2P 修复菜单/任务遗漏并核对全部 163 个程序文件。根测试 70、K2P 197 Python + 26 JS、AX5 87 Python + 24 JS 通过。页面恢复提交、确认票据及结果重连尚未实现，“确认恢复”不能解禁。详见 [K2P 恢复记录](LIVE_TEST_2026-10-16_K2P_RESTORE.md)。以下旧表保留当时结果，不代表这些待验收项已完成。

2026-10-14：统一仓库候选验证中。按用户最新要求，全量验收通过前也不发布新的私有候选。

| 项目 | 当前状态 |
|---|---|
| 公共代码构建 | 两机共用源代码，生成各自固件目录；差异通过逐文件基线审查 |
| 设备自动回归 | AX5 70 Python + 23 JS；K2P 177 Python + 25 JS，通过 |
| 安装、升级与归档边界 | 40 项测试通过，包含低空间升级、回退、未知文件拒绝和固定内核校验 |
| 当前运行设备 | 两机已使用统一新包升级；升级时保留内核、配置及启动钩子；备份保留在测试电脑 |
| 离线候选包 | 旧 rc2 归档曾通过 SHA256 与清单；本轮源码改动尚未重建发布包 |
| 实际 DNS | 两机核心 DNS 最新查询通过：Google Fake IP，国内域名及例外域名返回实际地址；AX5 TCP DNS 的 SERVFAIL 经增加 HTTPS DNS 后复测通过 |
| 实际代理规则 | 两机新的 TLS 连接核对过 Google 代理、Baidu 直连，已记录内核规则与出口链 |
| 域名分流保存 | 两机临时规则已在页面保存及撤销，并用新连接确认直连；AX5 手机窄屏、K2P 桌面已测 |
| 会话与响应处理 | AX5 上传、后台操作必须有 JSON 确认；登录页、无效响应、缺失回执分别报错，保留草稿；已回归并部署 |
| WebDAV 页面 | K2P 关闭、错误账号、保存拦截、重测及恢复启用已实测；其他边界继续待测 |
| 应用备份 | 两机客户端导出与 WebDAV 回读通过 SHA256、gzip CRC 和 macOS 原生 tar 解压；远端记录实际面板、工具及内核版本；两机内核包回读 SHA256/gzip/tar 通过，每机仅一份应用备份 |
| 模式后端 | 两机 rule/direct/global 往返、核心 API 与防火墙接管检查通过，恢复 rule；AX5 直连 Google 未建立核心连接，未算访问成功；页面及真实 LAN 客户端仍待验收 |
| 控件清单 | 348 项，含桌面和窄屏共 696 个执行位；未逐项完成，不能用自动回归代替实机验收 |
| 干净设备安装 | K2P原生首次安装及现场恢复已通过；AX5于10月21日移除部署后实际首次安装通过，原配置/18组选择/HTTPS204恢复，见当日记录；均不以普通覆盖升级冒充 |
| 重启、恢复、跨核及长期 | 历史一次 K2P 整机重启的资源失败由守护恢复；本轮开机约 134 秒启动，已另列启动资源与缓存问题；AX5 重启、完整应用恢复及长期验收待完成 |
| 公开 Release | 未发布；新仓库暂时私有 |

测试过程会撤销临时规则和恢复用户配置。测试结果表中的未执行项继续保留，不以“全部通过”概括未完成的实机场景。AX5 原生首页返回 HTTP 500；独立管理页面返回 200。隔离自定义菜单和控制器后原生首页仍异常，原因继续排查。

AX5 配置页混合接管已完成一次实际按钮重启、TCP/UDP/DNS 与手机 App/ZeroTier 集中验证；K2P 后续已完成混合应用一次，详见 [流量与 K2P 增量记录](LIVE_TEST_2026-10-14_TRAFFIC_AND_K2P.md)。详见 [混合接管记录](LIVE_TEST_2026-10-14_MIXED_MODE.md)。新私有候选版仍不代表公开上线验收完成。

本轮增量：K2P 两种布局实际高级面板打开/四种比例/返回、本地导出通过；AX5 查询、备份打包和高级面板安装触发各自的内存预留，正常路径未完成。提示现显示实际余量和所需内存，不降低保护阈值。详见增量记录。

最新重启及远端备份验收见 [重启与 WebDAV 记录](LIVE_TEST_2026-10-14_REBOOT_REMOTE.md)。旧增量记录只代表当时版本，本轮成功不替代尚未执行的恢复、安装和长期场景。


2026-10-15：独立基础版本、中文说明与完整包校验进入实机验收；范围、失败记录及剩余恢复工作见 [本批记录](LIVE_TEST_2026-10-15_BACKUP_FOUNDATION.md)。控件清单现为 362 条 / 724 个桌面与手机执行槽。没有以文件校验或隔离 COPY 代替完整恢复验收，发布门槛仍未通过。

## 2026-10-16 原生预检增量

见 [Mac mini 接续与原生预检](LIVE_TEST_2026-10-16_NATIVE_PREFLIGHT.md)。根81（含电脑可选 Lua 5.1 运行时测试）、AX87 Python/24JS、K197 Python/26JS及构建/原基线核对通过；两机原生归档拒绝边界和K隔离配置检查通过，现场指纹不变。新helper仅临时目录验证，页面仍未接通执行，不计网页恢复/新恢复或重启验收。
