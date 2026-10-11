# 自部署资产

部署前按 [自部署手册](../docs/SELF_HOSTING.md) 准备主机。在仓库根目录运行以下命令安装服务端；`--local-only` 仅配置回环 API，HTTPS 代理需由管理员另行配置。

```bash
sudo bash deploy/scripts/install.sh install --local-only
```

## 文件与用途

| 文件 | 作用 |
| --- | --- |
| `scripts/install.sh` | 提供配置初始化、安装、升级、注册开关、备份、隔离恢复检查和状态查询命令；升级使用候选镜像配置，未完成迁移后的发布会阻止注册开关 |
| `../compose.production.yaml` | 定义 PostgreSQL 私有网络、回环 API、显式迁移服务和非 root 只读 API 容器 |
| `scripts/validate-config.sh` | 检查文件权限、占位值、凭据一致性和 Compose 配置 |
| `scripts/release.sh` | 依次执行镜像构建、数据库就绪检查、迁移前备份、停止已有 API、迁移和 API 就绪检查；调用方指定配置提交目标时，在就绪后提交候选配置 |
| `scripts/backup.sh` | 创建本机逻辑备份，校验内容目录及 SHA-256，并按分层保留策略清理 |
| `scripts/restore-check.sh` | 在使用独立卷且无网络的临时容器中还原备份 |
| `scripts/verify-deployment.sh` | 检查容器健康、端口绑定、API、备份时效和可选公网 HTTPS |
| `config/*.env.example` | 配置模板；实际文件保存到仓库之外，权限为 0600 |
| `nginx/*.template` | 配置 HTTP ACME 验证与 HTTPS/WSS 反向代理 |
| `systemd/pactick-backup.*` | 配置每日服务器本机备份 |
| `tests/install_test.sh` | 无需 Docker，测试配置初始化、幂等性和错误处理 |
| `tests/release_test.sh` | 使用模拟 Docker 验证备份、迁移、替换顺序及失败时停止 |
| `tests/upgrade_test.sh` | 使用隔离配置与模拟 Docker 验证构建、数据库就绪、备份、停止 API、迁移状态写入、迁移和 API 失败时保留正式镜像配置，以及注册开关与升级重试的处理 |
| `tests/https_test.sh` | 在隔离目录中验证证书签发、配置检查和重载失败后的站点恢复 |
| `desktop/compose.yaml` | 为 Windows/Linux 管理程序提供独立 Compose 项目；使用 Release 包内的 Linux amd64 二进制构建镜像，PostgreSQL 不发布主机端口 |
| `desktop/launch-manager.cmd`、`desktop/launch-manager.sh` | 启动 Release 包中的本机管理程序并打开浏览器界面；操作与数据目录说明见 [服务器管理程序](../docs/SERVER_MANAGER.md) |
| `desktop/run-server.cmd`、`desktop/run-server.ps1`、`desktop/run-server.sh` | 从 `data/api.env` 或指定配置文件读取本机环境变量，前台运行本机服务端；显式迁移参数仅执行迁移，不启动 API |

## 手工配置

不使用入口脚本管理部署时，可复制配置模板到 `/opt/pactick/config`。所有 `.env` 文件必须设为 0600，并且只由可信管理员修改；运维脚本会将这些文件作为 shell 配置读取。

为数据库生成 32 个随机字节的十六进制密码，为 JWT 单独生成 64 个随机字节。数据库密码需在 `postgres.env` 和 `api.env` 的 `DATABASE_URL` 中保持一致。生产环境使用 `AUTO_MIGRATE=false`，注册默认关闭；原生客户端不需要 CORS。

每次发布使用新的镜像标签，不得使用 `latest`。`CLIENT_UPDATE_MANIFEST_JSON` 默认留空；现版本客户端通过 Releases 查看更新，服务器保留旧更新 API，以兼容已有版本。

`install.sh upgrade` 自动创建候选配置并在 API 就绪后提交。直接调用 `release.sh` 时，`PACTICK_COMPOSE_ENV` 默认指向配置目录中的 `compose.env`，脚本不会生成新镜像标签。手工发布应先复制正式文件为私有候选文件并修改候选的 `PACTICK_IMAGE`，将 `PACTICK_COMPOSE_ENV` 指向候选文件，同时将 `PACTICK_RELEASE_CONFIG_TARGET` 设为该配置目录的 `compose.env`；候选与正式文件均须为 0600。发布成功时脚本移动候选文件覆盖目标，失败时保留正式文件，手工候选文件由管理员处置。

迁移开始后，脚本保留 `.release-pending` 直到 API 就绪且配置提交完成。此期间失败不会自动回退数据库或容器。入口脚本阻止注册开关触发未经兼容性确认的 API 重建；重试发布或手工恢复的条件见 [升级与恢复说明](../docs/SELF_HOSTING.md#4-升级)。直接运行 Compose 命令不受该检查保护。

## 小内存主机

在可信管理端交叉编译，将四份静态 Linux 二进制放到目标源码目录的 `prebuilt/`：

```bash
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -o prebuilt/server ./cmd/server
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -o prebuilt/migrate ./cmd/migrate
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -o prebuilt/healthcheck ./cmd/healthcheck
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -o prebuilt/admin ./cmd/admin
```

ARM64 主机使用 `GOARCH=arm64`。先用 `install --prepare-only` 生成实际部署目录的配置，在 `compose.env` 中设置 `PACTICK_DOCKERFILE=Dockerfile.prebuilt`，然后执行正式安装。运行层仍使用 distroless 非 root 镜像。

Windows/Linux x86 的服务器 Release 包同时包含本机程序、管理界面、上述 Linux 部署脚本和 Docker 预编译程序。解压后从包根目录运行 `launch-manager.cmd` 或 `bash launch-manager.sh`。本机模式需提供既有 PostgreSQL；Docker 模式需安装可运行 Linux 容器的 Docker Engine 与 Compose v2。桌面部署的 Compose 项目和数据库卷独立于本节的 Linux systemd 部署，两者的配置、备份和恢复命令不可直接混用。

桌面 Compose 文件不自动执行迁移。管理程序首次安装时先等待 PostgreSQL 就绪，再运行 `migrate`，迁移成功后启动 `api`；使用命令行时须保持相同顺序。升级既有数据库前必须停止 API、完成备份并显式运行迁移。原 `install.sh` 仅适用于自部署手册列出的 Linux 工具与路径要求，不在 Windows 上运行。

## 手工渲染 Nginx

将实际域名与端口赋给 `API_DOMAIN` 和 `PACTICK_HTTP_PORT`。渲染 HTTPS 模板时必须限定替换变量，保留 Nginx 自身的 `$host` 等变量：

```bash
export API_DOMAIN=api.example.com PACTICK_HTTP_PORT=8080
envsubst '${API_DOMAIN} ${PACTICK_HTTP_PORT}' \
  < deploy/nginx/pactick-https.conf.template
```

## 备份限制

默认备份仅保存在服务器本机。还原检查验证备份的逻辑可恢复性；主机损坏时，仍需可用的异地备份及相应恢复流程。
