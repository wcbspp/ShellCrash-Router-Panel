# 2026-10-21 两机跨版本验证（进行中，非最终RC）

用户已授权立即恢复K2P及AX5真机跨版本验证，并允许必要重启；覆盖此前等待AX5问题全部解决的顺序限制。保留现场配置与节点选择，既有冷启动/Wi-Fi证据不重复。上游KSpeeder保持用户关闭状态；实际维护造成的观察中断单独归因，不能拼接连续24小时。

## K2P 实现

普通升级仍保留原路径。内存不足以同时保存新包和候选二进制时，使用原机已有Lua/nixio匿名管道：压缩流有界读取，SHA256与pinned Git blob并行校验，gzip CRC及单成员tar结构、校验和、尺寸、尾块均检查。tar解析器按实际二进制尺寸检查24MiB预留，不执行归档脚本，不降低保护阈值，不安装常驻进程或设备依赖。错误会清除候选；本地旧归档保留供回退。

版本及配置检查完成后，通过已验证可执行文件的父进程 FD 交接启动，避免同时保留旧归档、新归档及新二进制。启动子进程保留 FD3，确保原生 ash 中的已验证核心链接可访问；请求复用但链接失效时直接失败回退，不再下载第二份归档。升级期间沿用已有64MiB tmpfs配额，结束后恢复正常45MiB；完整旧归档保留至就绪和持久化完成，24MiB物理内存预留不变。普通非流式升级仍走原归档路径。

源全局版本索引可能描述另一种构建：实查源索引1.13.14，而当前固定mini归档的Git blob与实际1.12.13原包相同。因此最终记录取自已校验二进制实际报告，并在配置验证、启动、持久化前再次拒绝实际降级；源索引差异另记事件及元数据。不用改版本字符串伪造跨版。

## 已取得证据

- 4项Lua解析器测试覆盖完整内容、24MiB边界、截断/校验和/结束块、路径/链接/多成员；真实1.12.12和1.12.13归档均由同一解析器读取，二进制SHA与既有来源证据一致。
- 3项实际版本门禁测试覆盖真正升级/同版、索引较新也不能放行实际降级，以及其他程序/多行/畸形版本拒绝。
- K2P原生Lua语法通过；首次4个运行文件原子部署后SHA读回，核心PID及用户配置字节不变。
- 受独立恢复守卫保护的v2维护：原生完整流式读取真实1.12.12包；错误Git blob拒绝且候选/回执清理；真实1.12.12启动。正向入口返回失败，其显示消息未可靠绑定新job，不能把旧提示或“版本仍旧”当成本轮已证实回退。控制器最终恢复用户1.12.13及原配置/选择。
- v3维护取得实际job/version/order回执：1.12.12->索引1.13.14，进入新流式升级。实际24MiB预留未满足，解析器安全拒绝，旧包恢复后控制器再次恢复用户1.12.13。**正向升级仍未通过；流式校验成功不能代替整条升级成功。**
- 完成的三个电脑测试控制器残留CA副本已另存私有tar后精确清理；未删除稳定备份或用户资源。后续必要重启/健康现场验证仍待执行，不能靠清理记录假称发布门槛已过。
- 随后最新4个升级文件已原子部署并通过原生Storage保存。用户授权的K2P整机重启已完成：boot ID改变、原1.12.13恢复、配置/安装记录逐字节一致、3组选择保持、4文件SHA落盘一致；不是跨版正向通过。后续须在这一干净现场继续真实原生/网页事务。
- 最终本地根129项、K2P209项Python及29组JS通过，构建/基线检查通过；初轮未更新intentional_changes的基线失败原文保留，修正的是有明确原因的部署审阅记录，未改原始baseline。版本门禁/umask更改后完成了最终回归。无最终RC提交。

## AX5 当前状态

当前完整私有快照已保存并核验摘要。配置源仍报告Mihomo v1.19.28；源码ref改变不代表真实跨版本候选。官方v1.19.27普通armv7包约16.6MB，超出当前闪存预算，不能强行写入。电脑端已从官方校验模块构建真实v1.19.27，使用从现机Go buildinfo核对的no_tailscale/armv7规格；二进制31588536B、归档11854894B，符合当前闪存预算，模块sumdb及构建/归档SHA证据已保存。真机版本及配置兼容、两入口真实事务仍待验证，不能把构建成功或包审计算真机通过。

### 本次新增真机结果

AX5 干净安装已通过。完整保存面板、官方工具、菜单、cron、自启动链接，并完成带认证的独立恢复副本回读后，移除项目部署及其集成，实际执行 `install.sh --install`。固定官方 sing-box 1.12.13 包下载/校验、配置检查、服务启动、默认直连、管理状态、菜单和自启动接入通过，HTTPS 探测返回204（该命令未确认显式代理 CONNECT，补测另列）。随后恢复原 Mihomo v1.19.28，原配置/API凭据/启用状态/内核清单逐字节一致，18组节点选择及 HTTPS204 恢复。没有对固件恢复出厂，也没有复用已有目录冒充首次安装。

此前失败及完整恢复记录分别保留：原16000KB固定空间要求在现场13976KB可用时拒绝；原脚本会把未压缩内核放在闪存检查，现改为按压缩包、应用/工具/规则和1MiB余量计算持久预算，检查二进制仅放RAM且须先满足实际二进制尺寸加24MiB。另修正JSON转义导致的临时规则路径替换失败：解析JSON后改路径，再执行原生兼容检查。安装前菜单准备的匹配错误及校验器对成功PUT空响应的误解析另存为测试工具问题，没有记为产品安装通过。

AX5 原生菜单跨版本正向也已通过：真实 v1.19.27 运行并加载原配置后，通过官方工具菜单 `getcore` 调用现有适配链路升级至 v1.19.28；实际核心 API、持久归档校验、原配置字节、18组选择和 HTTPS204 均通过，独立守卫最终恢复原现场。网页入口及升级失败边界尚未完成，不能据此关闭整个升级门槛。

K2P 在重启后的干净现场完成v4受保护实测，仍因24MiB预留安全拒绝，原1.12.13及配置/3组选择已恢复；正向仍未过。后续仅优化既有散列进程开销：显式exec并使用固件已有sha256sum，保留pinned Git blob与压缩SHA256双重检查，并记录拒绝时实际可用/所需内存。代码已原子部署和Storage保存，但改动后的整条升级尚未通过。没有降低保护、删除旧归档、禁用其他服务或故意触发OOM。

当前已验证本地根129项、AX5 87项Python+27组JS、K2P209项Python+29组JS；构建/审阅基线通过。修改散列实现后的最终回归和真机结果以续接记录为准。前次未更新部署审阅摘要导致的失败保留，原始baseline未改。独立采样曾同时失联，重连核对两机PID/boot/startticks不变，不能归为设备重启；维护中断窗口也不拼接成连续24小时。

私有证据目录：`core-upgrade-stream-20261021.private`、`k2p-cross-version-20261020.private/native-streamed-v2-20261021`、`native-streamed-v3-20261021`、`ax5-cross-version-20261021.private`。状态、失败和恢复记录保留，不公开原配置或覆盖稳定基础点。全RC门槛仍开放。

### 当前启动交接修复（源码已改，真机待验证）

K2P v7 已实际通过认证 WebDAV 缓存流、pinned Git blob/SHA256/gzip/tar、真实新核版本及配置检查，回执记录 `stream_transport=webdav-cache`；随后启动失败并回退旧核，控制器恢复原1.12.13及原配置/3组选择。不是跨版本正向通过。启动入口仍将/tmp改回45MiB，旧包8913722B、新包9025081B和二进制28836019B已共46774822B，仅剩411098B容纳其他临时文件。已取内核日志未见OOM条目，不能将这个新失败归为已证实OOM。

待验证修复复用既有已验证程序FD，去掉启动前第二份新压缩包；启动子进程关闭继承的FD3，通过父进程proc路径访问，避免退休程序被后代长期持有。保留完整本地旧归档至新服务就绪和Storage提交，回退前释放候选FD。启动入口按拥有者的临时64MiB额度交接，正常启动仍45MiB，提交或回退后恢复45MiB；24MiB解压预留及用户保护值不变。上述启动修复及poll EINTR重试目前仅在源码，尚未部署、未过真机，不能标P0已解决。

修复后本地根132项、K209项Python及29组JS通过，AX87项Python+27JS先前通过，构建/原基线审阅通过。三项新传输路由测试仅是单元测试；七项已过原机管道测试仍不代替整条升级。原始失败和恢复证据全部保留。

连通性命令修正：本批较早的AX记录带 `--noproxy '*'` 与 `-x`，204只保留为普通连通性观察，未证明显式代理。后续必须以空noproxy、明确代理，核对HTTP204及CONNECT200。AX干净安装本身已通过，显式代理补项待完成；先前独立Wi-Fi/LAN证据不重新归类。网页首次后台job已done，但事后校验未全确认，仍未关闭网页门槛。没有最终RC3提交。

### 11:40 后续核对

四个启动交接修复文件已原生语法、SHA读回、Storage保存核验部署。v8实际升级暴露coreupdate分支未加载config_core.sh，启动和产品回退均报函数未定义；独立守卫恢复原1.12.13/配置/3选择，不能把本轮称自动回退通过。已把coreupdate纳入helper加载，新增执行真实分支的materialize/release回归，修复后v9正在实测。

另外发现两个新增Lua运行文件未进入构建manifest，已补入并新增构建产物检查；现场已有文件不代表安装包完整。原始baseline未改。全部新源码最终回归和真机结论以私有终态为准，仍非RC3。

AX5随后认证HTTP网页正向补验通过：实际1.19.27->1.19.28、job6ffea6fd、原配置字节与18组选择保持，显式代理204/CONNECT200；最终原现场恢复。新装v5显式代理补验同样204/CONNECT200，恢复原Mihomo/config/18组选择，原生首次安装不再有此探测缺口。仍不是可视浏览器点击测试，也不代表其他失败/负载/24h门槛通过。

### FD交接及ZeroTier中断补充（12:40）

v12首次进入真实新核启动阶段，但原生启动子进程关闭FD3后无法访问候选链接；启动记录reuse=1/executable=0。其后归档回补路径造成额外tmpfs占用，内核日志明确OOM杀掉zerotier-one916，管理通道中断；boot ID未变。用户启动ZeroTier恢复连接。产品已自动回退测试1.12.12，随后独立恢复守卫脚本恢复用户1.12.13，cfg/info/JSON逐字一致、当前3选择、显式HTTPS204/CONNECT200及Storage核对通过。此次未持久保存试验前选择快照，不补造精确选择比较结论。

无服务改动的原机小二进制重现实验证明：关闭继承FD3时链接不可执行，继承时可读可执行。修复保留启动FD，并在已请求复用却链接失效时禁止下载归档回补；根138、K212 Python及29组JS、构建与原基线检查通过，两文件原子部署/原生语法/SHA/Storage且原核心PID配置保持。v13受独立回退保护的真实跨版本验证进行中，辅助验证和部署不算完整升级通过。

### 最新：K2P两个升级入口正向通过（12:50）

原生v13和认证HTTP网页后台本轮均由真实1.12.12升级到1.12.13，实际压缩包/版本/config检查及webdav-cache传输回执齐备。两轮分别核对3组原始选择、配置字节和显式HTTPS204/CONNECT200，最终原现场及Storage恢复；网页后台job e54b97d8，属于认证HTTP后台验证，不冒称可视点击。两轮之后原始内核kill计数与v12后相同，用户启动的ZeroTierPID1425持续运行，未再出现该杀进程事件。

原生v13及网页后台结果原文保存在私有控制器目录。最终根138、K212 Python+29JS、构建及原基线检查通过。当前未提交源码仍不是RC3；AX5替换后错误架构真实失败回退已准备但未执行，剩余失败入口/持续有界负载和内存保护/业务边界、最终连续24h等门槛保持待验。AX观察保持，新K独立只读观察在维护结束后唯一启动；不得拼接旧窗口。

### AX5 extraction and source gates; real rollback

First preparation refused before staging (memory guard). Stopped runtime executable was still in tmpfs; the new controller releases it only after verifying the persistent old archive. Installer now validates actual regular-member size and checks binary plus24MiB reserve plus1MiB helper budget before replacement with exact candidate reclaim credit, then again after moving the archive off tmpfs.

Second preparation exposed rejection of immutable official CDN URLs containing@. The source allowlist now accepts that valid format while rejecting unsafe characters and embedded newlines over the whole value. Five focused tests, root138/AX92Python+27JS/build/baseline pass, native syntax/SHA/persistence and unchanged PID/config verified.

Third actual replacement rejected incompatible MIPS execution, but its observer compared selectors at API availability before formal service-ready. That failed record is retained and does not prove permanent selection loss. Fourth trial waits service-ready and verifies product automatic recovery to1.19.28, exact config/manifest/APIheader/enabled, all18 selectors, explicit HTTPS204 CONNECT200. Independent snapshot recovery also passed and retained patched installer. This proves native post-replacement failure rollback, not HTTP failure entry or every load/memory gate.

Current-source authenticated HTTP positive1.19.27->1.19.28 is in progress; no finalRC.

### Latest current-source AX positive completed

Authenticated HTTP webv3 completed_original_restored: actual1.19.27->1.19.28, exact config bytes and18 raw selectors preserved, formal service-ready plus explicitHTTPS204 CONNECT200; independent restore also checked originalversion/config/18selectors/proxy and exact current patched installer SHA. No new kernel kill observed versus the trial's before log. This confirms the current extraction/CDN URL changes on a valid upgrade, in addition to native wrong-architecture post-replacement rollbackv4. BackendHTTP is not a visual browser click.

Both devices have unique fresh independent read-only observers after completed maintenance. Old interrupted windows are retained and never stitched. Launch is not24h pass. Remaining HTTP failure boundaries, sustained bounded real load/memory protection, business boundaries and full continuous24h/KSpeeder-off gates are still open. No finalRC3 commit or public release.
