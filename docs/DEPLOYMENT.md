# 部署与回退

在线与离线助手都在电脑执行。安装包按设备分开，不能混用。新版候选尚未完成实机安装验收，暂不用于替换现有运行设备。

## 在线

仓库的 `bootstrap.py` 下载固定 Release、校验 SHA256、拒绝链接和越界归档，之后执行包内 `deploy.py`。部署包还要逐文件检查，下载失败或文件损坏时不开始安装。`--check-only` 会上传临时安装文件并运行固件预检，不改持久配置、不启动内核，结束后清理临时目录。

## 离线

有网络时运行 `python3 tools/prepare_offline.py ax5` 或 `k2p`。它构建源码包，并按固定版本的 URL 和 SHA256 获取内核，生成 `dist/offline-ax5/` 或 `dist/offline-k2p/`。内核不写进 Git。

进入离线目录，运行 README 中的 `deploy.py` 命令。K2P 首次需要 `--nodes-file`。密码由 SSH 询问；不会生成保存 SSH 密码的文件。K2P 安装前会下载 Storage 备份；AX5 会保存受影响文件的备份到电脑，安装脚本自身仍有事务回退。

离线指安装所需文件已准备好。原服务商订阅的远程规则集更新、重启后的 RAM 内核恢复、高级面板首次下载仍可能需要网络；不可把首次离线安装当成永久离线运行保证。

## 手动部署

先在电脑核对安装包：

```sh
python3 tools/verify_package.py /path/to/package
```

然后通过 SCP 或 SFTP 上传安装目录及输入文件。密钥和配置文件权限设为 `600`。

AX5 在路由器安装目录执行：

```sh
sh install.sh --check
# 在线；首次与已有本项目更新由 auto 检测
sh install.sh auto
# 离线；固定版本不匹配时拒绝安装
SC_OFFLINE_CORE=/tmp/core-offline.tar.gz sh install.sh auto
```

K2P 先在电脑准备本地节点与配置：

```sh
python3 tools/prepare_profile.py --input nodes.json --output config.private.json \
  --lan-ip 192.168.123.1 --secret-file panel-secret.private \
  --cn-list examples/cn_ip.default.txt
```

上述初始生成器整理基础节点；完整服务商规则在安装后从面板更新，不会在首次生成器里自动导入。上传配置、密钥、安装目录，路由器端执行：

```sh
sh install.sh --check --profile /tmp/config.private.json
sh install.sh --install --profile /tmp/config.private.json --secret-file /tmp/panel-secret.private
# 离线时，上述两条命令均可加 --core-file /tmp/core-offline.tar.gz
```

K2P 已有自定义启动钩子或运行覆盖时，脚本拒绝覆盖；候选版尚未提供已部署 K2P 的一键升级。不能删除防护标记再运行首次安装器。已运行设备的迁移升级必须单独验收。

## 失败后

安装失败首先读取安装输出，不反复重试。保留电脑上的安装前备份；脚本自动回退失败时不要重启或断电。AX5 与 K2P 的目录、后台文件及存储方式不同，备份不能互相恢复。

电脑备份包含私人配置；不要上传到 Issues 或公共 Release。K2P `restore_storage.sh` 只恢复 Storage，运行挂载和启动钩子还需依照旧设备恢复文档核对；完整恢复演练未完成前不写成“恢复一键可用”。
