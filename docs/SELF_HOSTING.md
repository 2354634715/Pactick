# 自部署服务端

服务端提供可选的多设备同步，单机本地使用无需部署服务器。本文适用于使用 Ubuntu/Debian、systemd、Docker Engine 和 Compose v2 的单台主机。

## 1. 主机准备

先按 [Docker 官方 Ubuntu 安装说明](https://docs.docker.com/engine/install/ubuntu/) 安装 Docker Engine 与 Compose 插件。安装后执行以下命令，安装其他工具并启用 Docker：

```bash
sudo apt-get update
sudo apt-get install -y curl openssl nginx certbot gettext-base
sudo systemctl enable --now docker
docker compose version
```

`--local-only` 模式不需要 Nginx、Certbot 或 gettext-base。服务器需要能拉取 Go、PostgreSQL 和 distroless 镜像；本机源码编译建议至少配置 2 GiB 内存。小内存主机可按 [部署资产](../deploy/README.md) 使用预编译二进制。

将审阅过的完整源码放到 `/opt/pactick/app`，或另一个固定的无空格绝对路径。后续定时备份会使用此路径。不得直接上传整个开发工作目录；应使用按 [发行流程](RELEASING.md) 生成的干净源码快照。

HTTPS 模式要求域名 A/AAAA 记录指向目标主机，且公网可访问 TCP 80 和 443。移除无效的 AAAA 记录。脚本不更改防火墙或 SSH 配置；管理员须按主机网络策略开放端口。

## 2. 安装

```bash
cd /opt/pactick/app
sudo bash deploy/scripts/install.sh install \
  --domain api.example.com \
  --email admin@example.com \
  --accept-acme-terms
```

`--accept-acme-terms` 表示部署者接受 Let's Encrypt 账户条款。脚本使用 Certbot webroot 验证，并保留证书续期验证路径；安装续期后的 Nginx reload hook，启用 `certbot.timer`。[Certbot webroot 文档](https://eff-certbot.readthedocs.io/en/stable/using.html#webroot)

已有 HTTPS 代理，或准备先通过隧道验收时，使用本机模式：

```bash
sudo bash deploy/scripts/install.sh install --local-only
```

此模式仅监听 `http://127.0.0.1:8080`。远端 Android 客户端无法直接访问服务器的回环地址。配置自己的 HTTPS/WSS 代理后，在客户端填写该代理地址。

可选配置：

```bash
sudo bash deploy/scripts/install.sh install --local-only \
  --config-dir /opt/pactick/config \
  --backup-dir /var/backups/pactick \
  --port 8080
```

仅生成配置文件以便检查：

```bash
bash deploy/scripts/install.sh install --prepare-only --local-only \
  --config-dir /tmp/pactick-config
```

`--prepare-only` 会实际生成包含密钥的 0600 文件，但不修改 Docker、Nginx 或 systemd。按实际部署目录重新生成，或整体迁移配置并修正其中路径。该目录包含密钥，不得提交到仓库或附在公开问题中。

安装顺序为生成独立随机密钥 → 验证配置 → 构建镜像 → 等待 PostgreSQL → 迁移前备份 → 停止已有 API → 显式迁移 → API 健康检查 → 定时备份 → 可选 HTTPS → 验收。重复执行 `install` 时，脚本保留现有密钥、端口和备份路径；若配置文件不齐全，则停止安装。修改源码后的部署使用 `upgrade` 生成新镜像标签。

配置 HTTPS 时，临时域名验证站点与原站点并存，证书成功后才替换正式站点。证书签发、Nginx 配置检查或重载失败时，脚本恢复原站点配置。备份脚本有独立执行锁，文件名含随机后缀，避免定时与手工备份互相覆盖。

API 只发布到 `127.0.0.1`；PostgreSQL 不发布主机端口。配置默认在 `/opt/pactick/config`，数据库由 Compose 命名卷持久化。运维脚本需由可信管理员管理，其 `.env` 配置文件使用兼容 shell 的格式。

## 3. 创建账户

`admin create-account` 通过可信管理员的本机数据库连接创建账户，不依赖公开注册开关，也不生成访问令牌、会话或设备登记。数据库迁移必须已完成。服务器管理界面的“创建账户”执行相同操作；操作见 [服务器管理程序](SERVER_MANAGER.md)。

本节 Linux Compose 部署可在应用目录执行以下命令，使用 API 容器中已经配置的数据库连接：

```bash
sudo docker compose --env-file /opt/pactick/config/compose.env \
  -f compose.production.yaml exec -T api /admin create-account <<'JSON'
{"email":"user@example.com","display_name":"用户","time_zone":"Asia/Shanghai"}
JSON
```

使用自定义配置目录时，将 `--env-file` 改为该目录下的 `compose.env`，并按安装时的路径设置 `PACTICK_CONFIG_DIR`。该命令要求 API 容器正在运行，镜像中包含 `admin`。不使用 Docker 的管理员可给 `bin/admin`（Windows 为 `bin/admin.exe`）设置 `DATABASE_URL`，再通过标准输入提交同样的 UTF-8 JSON。不得将密码放入命令行参数。

`email` 为必填字段。`password` 省略或为空时生成随机密码，并且仅在账户创建成功后的 JSON 中返回一次；显示名称默认取邮箱的 `@` 前部分，时区默认 `UTC`，语言默认 `zh-CN`，每周默认从周一开始。自定密码长度要求为 10–1024 个 UTF-8 字节。命令拒绝未知字段、超过 32 KiB 的输入、无效邮箱或时区及重复邮箱；连接失败、迁移不一致或创建失败时输出不含数据库凭据的错误 JSON，并以非零状态退出。

生成密码显示在终端或管理页面中，应直接保存到密码管理器，不得附在公开问题、截图或发行附件中。账户创建后，客户端在“同步设置”填写 `https://api.example.com`，使用邮箱和密码登录。客户端连接新服务器默认使用独立工作区，上传已有本地数据需单独选择。

需要允许用户自行注册时，可临时开启原客户端注册入口：

```bash
sudo bash deploy/scripts/install.sh registration open
```

在客户端使用注册入口创建账户，或调用 `POST /v1/auth/register`，请求格式见 [OpenAPI](../api/openapi.yaml)。完成后关闭注册：

```bash
sudo bash deploy/scripts/install.sh registration close
```

关闭注册不会阻止已有用户登录或管理员通过 `admin` 建号。不得公开 `.env`、数据库备份或注册接口返回的访问令牌。

所有后续命令都支持 `--config-dir /自定义/目录`；使用自定义目录时每次保持一致。

## 4. 升级

先在管理端检查新版本并保留上一版源码和镜像，然后更新同一服务目录并执行：

```bash
sudo bash deploy/scripts/install.sh upgrade
sudo bash deploy/scripts/install.sh status
```

升级脚本复制当前 `compose.env` 并在私有候选文件中生成新镜像标签，使用该文件完成构建、数据库就绪检查和迁移前备份。备份成功后，脚本先停止已有 API，再记录迁移状态、执行迁移并启动候选 API。API 就绪后才以候选文件替换正式 `compose.env`。这些步骤失败时删除临时候选配置，正式配置仍保留上一次成功发布的镜像标签；数据库卷、备份和已构建镜像不会自动删除。若配置提交或发布标记清理发生文件系统错误，管理员须检查正式配置、运行镜像和发布标记后再重试。

构建、数据库就绪检查或备份失败时，本次发布尚未执行迁移，也未停止或替换 API。此时可以修复失败原因后重试 `upgrade`。此前没有未完成的发布时，注册开关继续使用正式配置中的原镜像；已有 `.release-pending` 时，注册开关仍然受阻止。

停止 API 失败时，脚本不调用迁移。API 已停止但写入迁移状态失败时，本次发布也尚未调用迁移。若此前没有未完成的发布，管理员可按正式 `compose.env` 重新启动原 API 后排查；若已经存在 `.release-pending`，须先核对上一次发布的数据库状态，不能按本次错误判断数据库未迁移。

脚本在调用迁移前写入配置目录的 `.release-pending`，其中记录候选镜像及发布阶段。迁移命令失败时，前面的迁移可能已经提交；API 启动或就绪检查失败时，数据库可能已经升级，正在运行的 API 也可能是失败候选。上述失败会保留 `.release-pending`，并阻止 `registration open|close` 在修改 `api.env` 或重建 API 之前继续执行。`backup`、`restore-check` 和 `status` 仍可用于排查。成功重试 `upgrade` 后，脚本提交镜像配置并删除该标记，注册开关恢复可用。

发布脚本不会自动降级数据库，也不会自动将 API 换回原镜像。正式配置保留原标签不代表数据库或运行中容器已经回退。迁移期间 Compose 项目中的 API 保持停止，候选 API 只在迁移成功后启动；旧版本不遵守当前同步写锁，因此不得绕过脚本在迁移期间启动旧 API。使用同一数据库的其他进程需由管理员另外停止。升级会从停止 API 到候选 API 就绪期间中断服务；迁移失败后原 API 保持停止，须按实际数据库状态决定重试或恢复。

需要回到旧版本时，先查看 `.release-pending`、容器日志和迁移账本，确认当前数据库版本与运行镜像。只有确认旧应用能使用当前数据库时，才可使用正式配置重新启动旧 API。否则按下一节在隔离环境校验迁移前备份，再恢复备份与对应应用版本；恢复备份会丢弃该备份之后的写入。手工恢复完成并通过 API 就绪、登录和同步检查后，管理员才可删除配置目录中的 `.release-pending`。仅删除该文件或仅修改镜像标签不构成恢复。

一个主机默认只有一个 `pactick` Compose 项目、一个 Nginx 站点和一个备份 timer。多实例需要管理员自行隔离 Compose 项目、端口、卷、站点及 systemd 单元。

## 5. 备份与恢复

```bash
sudo bash deploy/scripts/install.sh backup
sudo systemctl status pactick-backup.timer
sudo bash deploy/scripts/install.sh restore-check \
  /var/backups/pactick/daily/pactick-YYYYMMDD-HHMMSS-RANDOM.dump
```

每日备份为 PostgreSQL custom-format，带 SHA-256；保留 7 个每日、4 个每周、6 个月度和 10 个迁移前副本。`restore-check` 创建独立卷及无网络临时容器，恢复并检查迁移账本与用户表后清理临时资源，不覆盖正在使用的数据库。

恢复生产数据库前，必须停止写入、保留故障数据库副本，并完成上述隔离恢复校验。建议将通过校验的备份恢复到新的独立服务器：

1. 用相同或兼容的 PostgreSQL 主版本安装完整服务，保持注册关闭，停止新主机 API。
2. 将 `.dump` 和 `.sha256` 复制到新主机私有目录并校验。
3. 在新主机空库中使用 `pg_restore --clean --if-exists --no-owner --no-privileges --exit-on-error` 恢复；仅对确认可覆盖的目标库执行。
4. 使用与备份对应的应用版本启动，检查 `/readyz`、登录、实体数量和同步。
5. 验证后再切换域名或客户端配置，保留原主机以便回退。

本机备份无法抵御整机或磁盘丢失。需要应对此类故障时，应将备份复制到由管理员控制的其他主机或离线介质，并执行恢复演练。服务端账户导出与客户端离线备份面向数据迁移，不能替代完整数据库运维备份。

## 6. 验收与排查

```bash
sudo bash deploy/scripts/install.sh status
sudo env PACTICK_PUBLIC_URL=https://api.example.com \
  bash deploy/scripts/verify-deployment.sh
sudo certbot renew --dry-run
sudo journalctl -u pactick-backup.service --since yesterday
```

部署后还应从另一台设备测试 HTTPS 登录、双设备同步和 WebSocket。定期检查备份时效、磁盘剩余空间和证书续期。本机健康检查仅验证本机服务状态；公网访问、双设备同步和完整灾难恢复须分别验收。
