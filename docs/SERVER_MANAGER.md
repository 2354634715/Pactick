# Windows 与 Linux 服务端管理

`v0.3.0-preview.1` 提供 Windows x86-64 ZIP 和 Linux x86-64 tar.gz 服务端包。每个包包含本机 Go API、迁移、健康检查、账户管理和 GUI 管理程序，以及 Docker 用的 Linux x86-64 预编译程序、部署脚本、服务端源码和许可证。Android APK 单独下载。编译产物仅作为 Release 附件分发，不提交到源码仓库。

GUI 由本机 `manager` 程序提供，使用浏览器显示，不需要安装 Node.js 或 Python。它管理运行所在电脑上的服务，不提供远程主机连接功能。Linux 自动打开浏览器需要 `xdg-open`；没有图形环境时可使用原有 [Linux 部署脚本](SELF_HOSTING.md)。

## 启动与配置

1. 将对应系统的服务端包解压到管理员可写的固定目录。保留整个目录结构，不单独复制 `manager`。
2. Windows 双击 `launch-manager.cmd`；Linux 在解压目录运行 `./launch-manager.sh`。程序在 `127.0.0.1` 的随机端口启动 GUI，并打开本机浏览器。浏览器没有打开时，将终端中的本机网址复制到浏览器。
3. 打开“运行配置”，选择运行方式、API 监听接口及端口。默认使用 Docker，API 监听 `127.0.0.1:8080`，公开注册关闭。
4. 保存配置，返回“概览与部署”，点击“部署并启动”。首次部署执行数据库迁移，之后启动 API，并等待 `/readyz` 成功。

管理网址包含本次进程的会话令牌。页面读取令牌后从地址栏移除，并保存在当前标签页的会话存储中，允许刷新页面。管理程序重启后需使用新网址。不要将该网址或配置文件附在公开问题中。程序校验请求的 Host、Origin 和会话令牌；GUI 监听地址只能使用 `127.0.0.1`。

默认数据目录为发行包内的 `data/`。需要更新包或保护配置时，建议指定固定的独立目录：

```powershell
# 在 Windows 发行包根目录运行
./launch-manager.cmd --data-dir D:/PactickData
```

```bash
# 在 Linux 发行包根目录运行
./launch-manager.sh --data-dir /home/operator/.local/share/pactick-server
```

目录中 `manager.json` 保存数据库连接、随机密钥和 Compose 项目标识，`api.env` 与 `docker.env` 供相关程序读取，日志及手工备份也保存在该目录。Linux 新建目录权限为 0700、新建配置和备份文件为 0600，既有目录权限由管理员核对；Windows 使用父目录继承的 ACL，管理员应限制其他用户读取。密钥首次生成后保留，不能用新的配置文件覆盖已有数据库对应的配置。进程锁防止两个管理程序同时使用同一数据目录，进程退出后操作系统释放锁。

已初始化的实例不能在 GUI 中直接切换运行方式或数据库。另一个实例使用不同数据目录。修改监听接口或端口前先停止 API，保存后再启动。

## Docker 部署

Windows 需要已运行的 Docker Desktop，且使用 Linux containers；Linux 需要 Docker Engine 和 Compose v2。Docker 宿主须支持 Linux x86-64 容器。GUI 不安装 Docker、不修改系统防火墙，也不安装 HTTPS 代理。

首次部署会下载 PostgreSQL 17 Alpine 与 distroless 运行时镜像，并用包内 `prebuilt/` 程序构建 API 镜像，不在主机编译 Go。数据库不发布主机端口，其数据保存在独立 Compose 命名卷中。Compose 项目标识保存在 `manager.json`，多个数据目录使用不同项目；删除配置后重新生成标识会连接新的数据卷，不能据此判断旧数据已丢失。

“停止 API”保留数据库容器、数据卷和配置。“启动 API”不会重新执行迁移。“查看日志”显示 API 与 PostgreSQL 最近 100 行日志。“备份数据库”执行 `pg_dump -Fc`，将 custom-format 文件与 `.sha256` 写入 `data/backups/`，不自动轮换或验证恢复。将备份复制到独立介质；隔离恢复及生产恢复步骤见 [自部署备份与恢复](SELF_HOSTING.md#5-备份与恢复)。

关闭 GUI 程序后 Docker 服务继续运行，容器使用 `unless-stopped` 重启策略。

## 本机程序与已有数据库

本机模式直接运行包内 `bin/server`，不需要 Docker，但需要已经启动的 PostgreSQL 及为 Pactick 单独创建的数据库。数据库用户须有迁移所需的建表权限。连接地址使用 `postgres://` 或 `postgresql://`，连接选项由 PostgreSQL 驱动处理。GUI 不创建或安装数据库。

在“运行配置”中选择本机模式并输入连接地址，例如：

```text
postgres://pactick:change-me@127.0.0.1:5432/pactick?sslmode=disable
```

该示例仅适用于可信的本机测试。远程数据库按部署环境配置 TLS 和认证。已有连接地址不回显，输入留空会保留原值。保存后“部署并启动”执行首次迁移并启动 API。

本机 API 的生命周期由管理程序维护。关闭浏览器页面不会关闭管理程序；关闭管理程序会停止其启动的 API。Linux 发送中断信号，最多等待 15 秒后强制结束；Windows 当前直接结束子进程，正在处理的请求可能被中断。需要长期后台运行时，使用 Docker，或由管理员配置 systemd/Windows 服务。GUI 不安装系统服务。

包内 `run-server.cmd` 与 `run-server.sh` 可以读取 GUI 初始化时生成的 `data/api.env`，以前台方式运行 API。自定义配置路径和仅迁移模式：

```powershell
./run-server.cmd -ConfigFile D:/PactickData/api.env
./run-server.cmd -ConfigFile D:/PactickData/api.env -MigrateOnly
```

```bash
./run-server.sh --config-file /home/operator/.local/share/pactick-server/api.env
./run-server.sh --config-file /home/operator/.local/share/pactick-server/api.env --migrate-only
```

Windows 脚本需要 PowerShell；配置按字面 `KEY=value` 解析，不执行 shell 表达式。外部启动的 API 不由 GUI 接管。迁移前必须先停止这些进程以及使用同一数据库的其他写入进程。

## 一键创建账户

数据库迁移完成后，打开“创建账户”，填写邮箱，点击“创建账户”。显示名称默认取邮箱 `@` 前的部分，GUI 默认时区为 `Asia/Shanghai`、语言为 `zh-CN`、每周起始日为周一。密码留空时生成 24 随机字节的 Base64URL 密码（32 字符），仅在创建成功后显示一次；自定密码须满足服务端 10–1024 字节要求。重复邮箱返回错误，不覆盖既有账户。

GUI 在本机模式下直接操作数据库，Docker 模式调用容器内的 `/admin create-account`。两种方式均复用服务端校验和 Argon2id 哈希，不临时开启公开注册，不生成设备登记、刷新令牌或登录会话。安卓客户端随后使用邮箱和密码正常登录，设备登记在登录时完成。

命令行也可创建账户：本机 `bin/admin[.exe] create-account` 从标准输入读取单个 UTF-8 JSON 对象，使用环境变量 `DATABASE_URL` 连接数据库。不要将密码放入命令参数。以下不指定密码的示例生成随机密码：

```bash
printf '%s\n' '{"email":"name@example.com","time_zone":"Asia/Shanghai","locale":"zh-CN"}' | ./bin/admin create-account
```

```powershell
'{"email":"name@example.com","time_zone":"Asia/Shanghai","locale":"zh-CN"}' | ./bin/admin.exe create-account
```

以上命令在包根目录运行，事先在当前进程设置 `DATABASE_URL`。CLI 缺省时区为 UTC、周起始日为周一；成功退出码为 0，输出包含 `ok/user/generated_password`（自定密码时省略后者）。失败退出码非 0，输出稳定的 `error.code` 与不含凭据的消息。输入超过 32 KiB、额外字段、重复 JSON 对象、无效资料、数据库不可用或迁移不完整时失败。GUI 请求上限为 16 KiB。

## 更新与失败处理

更新前停止 API、保存完整配置并备份数据库，将新包解压到新目录，启动时使用原来的 `--data-dir`。数据库版本需要更新时执行“数据库迁移”；该操作先停止 API，再执行迁移，成功后启动 API。不要以新的空数据目录代替原配置。

迁移调用前写入 `.migration-pending`。迁移失败时可能已有部分迁移提交，标记保留，普通启动及已部署实例的“部署并启动”均被阻止；不会自动降低数据库版本或恢复备份。检查日志及数据库后重试“数据库迁移”，或按备份恢复步骤恢复对应版本。迁移成功后删除标记；随后的 API 启动失败不会回滚已完成的迁移。

管理操作串行执行。单个操作最多 5 分钟，API 就绪检查最多 45 秒；Docker 另有容器等待时限。超时不代表外部命令的副作用已经撤销，重试前检查服务和数据库状态。建号超时后先尝试该邮箱登录或核对数据库，避免误认为账户一定未创建。

默认 API 地址仅供本机访问。安卓设备连接需选择 `0.0.0.0`、允许实际需要的来源网络，并填写主机可达地址。公网使用需要 HTTPS/WSS 代理与证书。管理 GUI 不完成证书签发、续期、防火墙或公网可达性验收。此次预览的验证范围见 [2026-10-11 发布验证记录](RELEASE_VALIDATION_20261011.md)。
