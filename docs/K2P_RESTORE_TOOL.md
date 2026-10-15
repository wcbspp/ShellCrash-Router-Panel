# K2P 恢复工具

这是电脑维护工具，页面的“确认恢复”尚未接入执行流程。当前只接受与正在运行内核的版本、压缩包 SHA256、程序 SHA256 均一致的完整备份；不同版本会在暂停代理前拒绝。完整应用恢复会恢复备份时的程序和配置，不是整机刷机。

电脑需要 Python 3、SSH，以及已经下载齐全的同机型备份目录或 ZIP。先运行只读预检：

```sh
python3 tools/restore_k2p.py K2P-backup --host router.example --user admin
```

返回清单 SHA256 和停止内核后的空间预算。确认来源、版本和覆盖范围后，使用这个完整 SHA256 执行：

```sh
python3 tools/restore_k2p.py K2P-backup --host router.example --user admin \
  --apply --confirm-manifest <预检返回的完整SHA256> \
  --receipt-dir ./private-k2p-restore-receipt
```

默认组件位置对应当前 WebDAV 的最新备份。独立目录需指定 `--remote-prefix baselines/备份名` 或 `imports/备份名`，远端文件必须与电脑检查过的文件一致。SSH 可使用密钥或已有 ControlMaster；不要在命令、脚本或仓库中写密码。

执行前会检查 WebDAV 已开启、连接身份已验证且当前可达、设备空闲、内存预算及程序完整性。电脑保留一份原始 Storage 私有快照；路由器先向独立的 `recoveries/<事务号>/` 保存应用、内核和资源并回读，再暂停代理。WebDAV 服务器必须支持 COPY，否则在暂停前拒绝。大内核只流式提取已验证的指定成员，压缩包不在 K2P 的 RAM 再保存一份。

运行中的恢复器放在应用目录以外。候选配置须通过目标内核检查，Storage 压缩包必须在固件限制内，启动后还会检查带鉴权的 API 版本。恢复保留当前 SSH/WebDAV 身份及 LAN、Wi-Fi、固件和 ZeroTier 身份。失败会尝试还原本次操作前状态，不能把“文件写完”当作恢复成功。

电脑 receipt 包含计划、日志和结果；路由器记录在 `/tmp/sc-restore-<事务号>/`。超时或电脑断线后先查询原任务，不要再次提交。当前没有断电自动续作保证，请保持供电与局域网连接。

旧 K2P 备份曾遗漏原生 `menus` 和 `task`。新检查会拒绝缺少关键程序的旧包，即使长度与 SHA256 正确也不能恢复。不要删除唯一旧备份；从正常运行且程序齐全的设备重新生成，再单独校验。具体结果与限制见 [K2P 实机记录](LIVE_TEST_2026-10-16_K2P_RESTORE.md)。
