# 本机服务器管理界面

`cmd/manager` 在 Windows 和 Linux 上启动本机浏览器管理界面。管理器支持配置、初始化数据库、迁移、API 启动、停止、重启、健康检查、日志、数据库备份、隔离恢复检查和创建普通用户账户。

管理界面只监听 `127.0.0.1`，默认使用随机端口；API 默认监听 `127.0.0.1:8080`。关闭管理器时，它启动的本机 API 会停止；Docker API 和 PostgreSQL 容器继续运行。关闭浏览器页签不停止管理器。

## 构建与启动

需要项目 `go.mod` 要求的 Go 版本。在项目根目录使用 PowerShell 运行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build_server_tools.ps1
.\output\server-tools\windows-amd64\bin\manager.exe `
  --bundle-dir . `
  --binary-dir output/server-tools/windows-amd64/bin `
  --data-dir output/server-data
```

脚本将 5 个命令的二进制写入 `output/server-tools/<目标>/bin/`，不启动服务、不修改数据库、不上传文件。可通过 `-Targets windows-amd64` 只构建一个目标。`--bundle-dir` 为包含 `go.mod`、`Dockerfile` 和 `deploy/desktop/compose.yaml` 的完整源码目录。`--binary-dir` 指定本机工具目录，默认是 `--bundle-dir` 下的 `bin`。源码目录可以包含空格。

Linux 启动示例：

```bash
chmod +x output/server-tools/linux-amd64/bin/*
output/server-tools/linux-amd64/bin/manager \
  --bundle-dir . --binary-dir output/server-tools/linux-amd64/bin \
  --data-dir "$HOME/.local/share/pactick-server"
```

`--data-dir` 默认为源码或发行包根目录下的 `data`。`--listen 127.0.0.1:固定端口` 可固定管理端口；其他监听地址会被拒绝。没有可用桌面浏览器时加 `--no-browser`，在该主机浏览器打开终端打印的地址。Linux 远程主机的常规运维可使用[自部署指南](SELF_HOSTING.md)，不应把管理页面暴露到公网。

| 构建目标 | 管理器与 API 运行方式 | 前置条件 |
| --- | --- | --- |
| `windows/amd64` | 本机进程或 Docker | 本机 PostgreSQL，或 Docker Desktop 与 Compose v2 |
| `linux/amd64` | 本机进程或 Docker | 本机 PostgreSQL，或 Docker Engine 与 Compose v2 |
| `windows/386` | 本机进程 | 32 位 Windows 可执行环境、可连接的 PostgreSQL |
| `linux/386` | 本机进程 | 32 位 Linux 可执行环境、可连接的 PostgreSQL |

386 管理器不提供 Docker 模式。交叉编译仅检查目标代码能否构建，不能证明对应操作系统和 CPU 上的运行行为；四种目标需要分别进行运行验收。此功能的实现不表示已经发布对应平台的安装包。

## 选择运行方式

首次打开页面后进入“运行配置”。

1. Docker 模式会构建当前源码的 API 镜像，并启动独立 Compose 项目的 PostgreSQL。首次运行需要能拉取构建和数据库镜像。项目标识、JWT 密钥和数据库密码首次生成后保存在数据目录，后续启动复用。此模式使用 PostgreSQL 17，不发布数据库端口。
2. 本机模式连接已有 PostgreSQL。填写 `postgres://` 或 `postgresql://` 连接地址后保存。连接另一个主机的数据库时，应按实际证书配置使用 `sslmode=verify-full` 等 PostgreSQL TLS 参数。数据库用户须有执行迁移的权限；部署、迁移和本机备份需要 `pg_dump`，隔离恢复检查需要 `pg_restore` 和 `CREATEDB` 权限，这些程序通过 `PATH` 查找。
3. 默认 API 只监听回环地址。选择 `0.0.0.0` 会让明文 API 监听全部接口；只适用于受到防火墙及独立 HTTPS/WSS 反向代理保护的网络。客户端仍要求 HTTPS。公网部署使用[自部署指南](SELF_HOSTING.md)中的反代配置，禁止直接对公网放行该 HTTP 端口。
4. 保存配置后选择“部署并启动”。管理器先初始化或校验数据库，再等待 API `/readyz` 成功。45 秒内未就绪时返回失败，进程或容器可能仍在运行，须查看日志。

API 运行期间不能修改配置。已初始化的数据目录不能切换运行方式或数据库；另一个实例应使用独立数据目录。管理器不会接管不是由它启动的本机 API；端口被占用时，应先停止外部服务或选择其他端口。它不安装 Windows Service、systemd 单元，也不修改防火墙。

## 服务操作与故障处理

“停止 API”保留 PostgreSQL、卷、配置和备份。“重启 API”先停止同一实例再启动，并重新检查就绪状态。Linux 本机进程先接收中断信号，15 秒内未退出时强制终止；Windows 本机进程直接终止，因此应避免在正在写入时频繁执行停止或重启。Docker 停止使用 Compose 的停止宽限时间。

更新源码或程序后，先备份，再选择“执行迁移并启动”。管理器在首次初始化和后续迁移前均另建一份数据库备份；备份失败时不执行迁移。迁移会停止 API，并在数据目录写入 `.migration-pending`。迁移失败后保留该标记，普通启动、重启和重复部署会被拒绝。查看日志及备份后可重试显式迁移；程序不会回滚已提交的数据库变更，也不会自动恢复生产数据库。使用同一数据库的其他写入进程必须由管理员另外停止。

日志页面显示 Docker API/PostgreSQL 最近 100 行，或本机 `server.log` 的最后 64 KiB，并对当前已知配置密钥做替换。日志文件不会自动轮转，本机运行时需另行安排日志保留。不要把应用日志、数据目录或数据库连接地址公开上传。

## 创建账户

“创建账户”直接通过受信任的数据库管理路径写入普通用户，不改变 `REGISTRATION_ENABLED=false`。建号不会创建设备、访问令牌或刷新令牌；用户在客户端首次登录时才登记设备和建立会话。相同邮箱再次创建会返回失败，不更新密码或用户资料。

邮箱必填。显示名称默认取邮箱 `@` 前面的部分，CLI 默认时区为 `UTC`，管理页默认填 `Asia/Shanghai`；语言默认 `zh-CN`，一周默认从周一开始。自定密码为 10–1024 字节，使用与登录相同的 Argon2id 哈希。密码留空时生成 24 字节随机值并编码为 32 字符密码，仅在本次成功结果中返回；服务端不保存明文，刷新页面后不能再次查询。

独立的 `cmd/admin` 不依赖管理器或公开注册。它只接受标准输入中的单个 UTF-8 JSON 对象，最多 32 KiB；数据库结构必须已迁移。密码不得放在命令行参数中。推荐只提供邮箱并让程序生成密码：

```powershell
# DATABASE_URL 通过当前进程环境或受保护的运维配置提供。
'{"email":"member@example.com","time_zone":"Asia/Shanghai"}' |
  .\output\server-tools\windows-amd64\bin\admin.exe create-account
```

Linux/Docker 管理员可以保持公开注册关闭，使用已运行 API 容器中的 `/admin create-account`，操作见[自部署指南](SELF_HOSTING.md#3-创建初始账户并关闭注册)。结果包含生成的密码，终端输出及重定向文件须按凭据保护。错误结果只包含安全的错误码和信息；参数错误退出码为 2，创建失败为 1，成功为 0。

## 备份与恢复检查

“备份数据库”生成 PostgreSQL custom-format 归档及 `.sha256`，写入数据目录的 `backups/`。文件名包含 UTC 时间和随机后缀，不覆盖已有文件。管理器不自动删除历史备份；管理员需要安排保留、磁盘空间监测和离线副本。

“检查备份恢复”只接受管理器生成的文件名、普通文件及匹配的 SHA-256。校验失败时不启动恢复命令。应只对可信来源的备份执行恢复，因为 PostgreSQL 归档可包含会执行的数据库对象定义；哈希用于检查完整性，不用于证明备份来源。

- 本机模式创建随机名称的新数据库，执行 `pg_restore --exit-on-error --no-owner --no-privileges`，检查当前程序的迁移账本和账户表，再删除临时数据库。
- Docker 模式创建无网络的独立 PostgreSQL 17 容器和卷，通过标准输入恢复归档，检查迁移账本和账户表可读取，再删除临时容器和卷。
- 操作失败后仍会尝试清理临时目标；清理失败时返回目标名称，管理员应检查并删除该临时数据库或容器及卷。

恢复检查不覆盖当前数据库，不切换客户端、不恢复上线服务，也不能替代完整灾难恢复验收。实际数据库恢复步骤见[自部署指南](SELF_HOSTING.md#5-备份与恢复)。PostgreSQL 的归档与恢复行为参见[官方 pg_restore 文档](https://www.postgresql.org/docs/current/app-pgrestore.html)。

## 本机访问保护

每次启动管理器生成 32 字节随机会话令牌，通过 URL fragment 交给页面，页面将它保存在该页签的 sessionStorage 并移除地址栏 fragment。API 请求需要该令牌；写操作还需要独立随机 CSRF 令牌及精确匹配的 Origin。Host 必须等于当前回环监听地址，页面使用限制性的 CSP，不接受跨站嵌入。令牌在管理器重启后失效。

数据目录有进程锁，同一目录只允许一个管理器。Linux 配置、备份使用 0600 文件和 0700 目录；Windows 的访问限制还取决于所在目录继承的 ACL，应把数据目录放在当前管理员的私有目录。可信本机进程及能读取管理网址或目录的用户仍可执行管理操作。不要把该管理端口经反向代理、隧道共享或端口转发暴露给其他用户。
