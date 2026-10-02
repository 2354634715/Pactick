# Ubuntu 单机部署计划

状态日期：2026-09-06。

本计划在接受单机数据风险的前提下，将 Go API 和 PostgreSQL 部署到一台 Ubuntu 服务器。默认使用单机 Docker Compose、宿主机 Nginx 和 Let’s Encrypt HTTPS。示例域名 `api.example.com` 必须替换为真实域名。

当前可执行入口见 [自部署手册](SELF_HOSTING.md) 与 `deploy/scripts/install.sh`。本文件保留单机部署架构及历史计划；客户端缺口、部署状态和未完成事项对应上述状态日期。旧商业发行要求不作为源码公开预览版的发行条件。

## 1. 部署范围与里程碑

截至状态日期，服务端可以先部署，跨设备产品验收仍依赖客户端接入：

- Go API、数据库迁移、认证、同步、读模型和 WebSocket 服务端代码已经具备部署基础；
- 当时的 Android 客户端仍为本地工作区原型，`ApiClient` 未被装配，也没有认证、队列消费、增量游标或 WebSocket 客户端；
- 服务器部署后，先通过 OpenAPI 或测试脚本验收后端；必须完成客户端 P0 接入项，才能验收真实的跨设备同步。

建议将部署工作分为三个里程碑：

| 里程碑 | 交付结果 | 上线判定 |
| --- | --- | --- |
| M1：后端服务上线 | HTTPS API、PostgreSQL、本机备份、监控和回滚流程可用 | API、认证、同步、WebSocket 和本机恢复检查通过 |
| M2：客户端同步上线 | Android 客户端接入账户与同步 | 两台设备完成创建、修改、离线恢复和专注同步验收 |
| 1.0：容灾上线 | 加密异地备份、跨主机恢复与正式 RPO/RTO | 异地备份告警和新主机恢复演练通过 |

开发配置 `compose.yaml` 不得直接用于公网生产环境：它发布了 PostgreSQL `5432`，使用固定开发口令，API 也直接发布在所有网卡上，并且没有生产日志轮转、应用重启策略或显式迁移服务。

## 2. 部署前提

### 2.1 适用条件

- Ubuntu 22.04、24.04 或 26.04 LTS，64 位；
- 至少有一个公网 IPv4，能够配置域名 A 记录；有 IPv6 时也正确配置或暂不发布 AAAA；
- 使用 SSH 密钥管理服务器；
- 初期用户量较小，接受 API 与 PostgreSQL 同机带来的单点故障；
- 客户端是 Android 原生网络访问，不需要浏览器 CORS；
- 1.0 之前备份只保存在本机，明确接受服务器或磁盘整体丢失时数据库与备份同时丢失的风险。

本计划依据的 Docker 官方文档列出 Ubuntu 22.04、24.04 和 26.04 LTS，并建议通过官方 apt 仓库安装 Engine 与 Compose 插件；执行前先核对服务器版本和 CPU 架构。[Docker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)

### 2.2 建议的起步规格

个人或小规模封闭测试可从以下规格开始：

| 资源 | 建议起步值 | 说明 |
| --- | --- | --- |
| CPU | 2 vCPU | 同时承担 Go API、PostgreSQL、Nginx 和镜像构建 |
| 内存 | 4 GiB | 2 GiB 也可能运行，但构建和数据库缓存余量较小 |
| 系统盘 | 40 GiB SSD | 需要为镜像、数据库、日志和临时备份留空间 |
| Swap | 2–4 GiB | 只作为突发保护，不能替代内存 |
| 本机备份空间 | 当前可使用同机独立目录 | 至少能容纳 7 个每日、4 个每周、6 个月度和 10 个迁移前逻辑备份；最好使用独立数据盘，但这仍不构成异地容灾 |

上述规格用于初始部署，不代表容量上限。上线后应根据数据库体积、峰值连接数、内存占用和磁盘增长调整资源。

### 2.3 执行前确认信息

1. 服务器 Ubuntu 版本、CPU 架构、内存和磁盘；
2. API 域名及其 DNS 管理权限；
3. SSH 端口、部署账户和公钥登录是否已经可用；
4. 服务是“仅自己使用”还是允许公众注册；
5. 本机备份目录容量，以及是否明确接受 1.0 前没有主机级容灾。

本文适用于个人单用户、1.0 之前的单机部署。如果服务器和备份目录仍可读取，每日逻辑备份对应的目标数据丢失窗口约为 24 小时；如果整台服务器或磁盘丢失，本方案无法承诺 RPO/RTO。若需要公开注册、更低数据丢失窗口或主机级恢复能力，必须提前实施异地备份、PITR 或托管数据库，不得延期到 1.0 再实施。

如果暂时没有域名，内部冒烟阶段可以通过 SSH 隧道或私有 VPN 访问回环地址；不得通过公网明文 HTTP 传输登录信息或刷新令牌。正式客户端切换仍建议使用受信任的 HTTPS 地址。

## 3. 目标架构

```mermaid
flowchart TB
    Internet[Android 客户端 / 管理终端] -->|HTTPS 443 / WSS| Nginx[Nginx + Let’s Encrypt]
    Nginx -->|127.0.0.1:8080| API[Go API 容器]

    subgraph Docker[Docker 双网络]
        API -->|postgres:5432| DB[(PostgreSQL 17)]
        Migrate[一次性 migrate 容器] --> DB
    end

    DB --> Volume[(持久化数据卷)]
    DB -->|pg_dump -Fc| LocalBackup[本机备份目录]
    LocalBackup -. 1.0 容灾升级 .-> Offsite[加密异地存储]
    Monitor[外部监控] -->|GET /readyz| Nginx
```

公网只开放：

- SSH 管理端口，优先只允许固定管理 IP；
- TCP 80，用于 HTTP 跳转和 ACME 验证；
- TCP 443，用于 REST 与 WebSocket。

API 容器同时接入普通 `ingress` bridge 和 `internal: true` 的 `backend` 网络：前者为 Docker 提供宿主机发布路径，但端口只映射为 `127.0.0.1:8080:8080`；后者用于 API、迁移容器与 PostgreSQL 之间的私有通信。PostgreSQL 只接入 `backend` 且不设置任何 `ports`。API 不得仅接入无网关的内部网络，否则部分 Docker 版本虽然在 HostConfig 中保留端口声明，却不会生成宿主机 NAT 规则。Docker 官方提醒，Docker 发布端口可能绕过 ufw 规则；绑定到 `127.0.0.1` 可让 API 仅由宿主机访问，PostgreSQL 不发布端口，避免数据库通过宿主机端口暴露。[Docker 与 Ubuntu 防火墙说明](https://docs.docker.com/engine/install/ubuntu/#firewall-limitations)、[Docker 端口发布](https://docs.docker.com/engine/network/port-publishing/)

## 4. 上线条件

### 4.1 M1 后端上线前

| 检查项 | 状态日期对应结果 | 必须完成的操作 |
| --- | --- | --- |
| Go 测试和静态检查 | 已通过 | 在目标构建环境再次执行 `go test ./...`、`go vet ./...` |
| 独立生产 Compose | 已提供 | 在目标服务器填入生产 env，并验证未发布 5432、API 只绑定回环地址 |
| 显式迁移镜像 | 已提供 | 发布前构建并运行镜像内 `/migrate` |
| 生产密钥 | 缺失 | 生成独立数据库口令和至少 32 字符 JWT 密钥，不提交仓库 |
| HTTPS 与 WebSocket 代理 | 模板已提供 | 替换真实域名、签发证书并通过 Nginx 配置检查 |
| 注册策略 | 应用开关已提供 | 个人部署建号后设置 `REGISTRATION_ENABLED=false` |
| 登录限速 | 模板已提供 | 在真实 Nginx 启用并按流量基线调整 register/login/refresh 限速 |
| 数据备份 | 本机脚本已提供 | 启用 timer、监控备份目录并完成本机备份恢复检查 |
| 外部监控 | 缺失 | 监控 `/readyz`、证书、磁盘、容器重启和备份时间 |

本计划的 M1 验收不要求 rclone 或异地副本，但发布记录必须注明：数据库卷和备份目录都位于同一服务器，整机或磁盘损坏时可能无法恢复。加密异地备份、跨主机恢复及其告警属于 1.0 上线条件。M1 仅提供本机恢复能力，不具备完整容灾能力。

### 4.2 M2 产品上线前

必须完成 [PROJECT_ARCHITECTURE.md](PROJECT_ARCHITECTURE.md) 中列出的客户端 P0 项，至少包括：

- 注册、登录、令牌安全存储、刷新和登出；
- 合法 UUID 操作 ID 与真实设备 UUID；
- task/tag/day_entry/focus pause 契约对齐；
- 待同步队列读取、确认、失败保留、快照应用和游标持久化；
- push 后 pull、`has_more` 分页、WebSocket 触发拉取和周期拉取；
- 断网、重试、冲突和设备撤销的用户状态。

## 5. 生产部署配置

### 5.1 新建独立生产 Compose

生产 Compose 文件应完整定义服务。仅覆盖开发 Compose 可能因合并规则保留 `5432:5432` 或固定口令，不应采用该方式。

目标配置应包含：

- `postgres:17-alpine`，只加入内部网络，不发布端口；
- 独立持久化卷；
- PostgreSQL healthcheck；
- API 同时接入可发布端口的 `ingress` 网络和私有 `backend` 网络，并只绑定 `127.0.0.1:8080`；
- 一次性迁移容器只接入 `backend` 网络；
- `restart: unless-stopped`；
- `stop_grace_period` 大于应用优雅停机时间；
- `json-file` 日志轮转，例如单文件 10 MiB、保留 5 个；
- API `read_only: true`、`cap_drop: [ALL]`、`security_opt: [no-new-privileges:true]`；
- 一次性 `migrate` 服务，与 API 使用相同发布镜像；
- 构建机内存不足 2 GiB 时，在可信管理端交叉编译静态 Linux 二进制，并通过 `Dockerfile.prebuilt` 封装相同的 distroless 非 root 运行镜像；
- 显式镜像版本，例如 `pactick-api:2026.08.30-1`，不得仅使用 `latest`。
- PostgreSQL 和构建基础镜像先固定到经过验证的版本；流程稳定后还应记录镜像 digest，以便复现发布时使用的镜像。

Docker 官方建议为生产环境使用独立 Compose 配置、生产环境变量和重启策略。[Use Compose in production](https://docs.docker.com/compose/how-tos/production/)

### 5.2 镜像与显式迁移

本计划采用的镜像同时包含 `/server`、`/migrate` 与供容器使用的 `/healthcheck`。构建阶段执行：

```text
go build -o /out/server ./cmd/server
go build -o /out/migrate ./cmd/migrate
```

运行阶段同时复制 `/server`、`/migrate` 和 `/healthcheck`。生产发布顺序固定为：先备份、再运行一次 `/migrate`、最后启动新 API。

应用在 `AUTO_MIGRATE=false` 时仍会调用 `VerifyMigrations`；如果迁移没有先执行，API 拒绝启动，用于阻止遗漏迁移的发布。短期内部测试可以使用 `AUTO_MIGRATE=true`，但正式发布应采用显式迁移。

### 5.3 生产环境变量

建议将完整变量放在服务器 `/opt/pactick/config/api.env`，权限设为 `0600`，只允许部署管理员读取。配置示例：

```dotenv
APP_ENV=production
HTTP_ADDRESS=:8080
DATABASE_URL=postgres://pactick:<URL编码后的强口令>@postgres:5432/pactick?sslmode=disable
AUTH_JWT_SECRET=<至少64字节随机密钥>
ACCESS_TOKEN_TTL=15m
REFRESH_TOKEN_TTL=720h
AUTO_MIGRATE=false
DB_MAX_CONNS=10
SHUTDOWN_TIMEOUT=15s
ALLOWED_ORIGINS=
```

原生 Android 客户端不需要 CORS，可保持 `ALLOWED_ORIGINS` 为空。如果以后增加 Web 客户端，只加入精确的 HTTPS Origin，不使用 `*`。

数据库初始化变量放在单独的 `postgres.env`，同样使用 `0600`。生成口令时优先使用纯十六进制随机值，使用其他字符时，必须在写入 `DATABASE_URL` 前完成 URL 编码。

### 5.4 关闭或保护公开注册

`POST /v1/auth/register` 没有邮件验证或邀请码，项目通过 `REGISTRATION_ENABLED` 应用开关控制注册；它在非本地环境默认关闭。个人部署建议：

1. 首次上线时只允许管理 IP 调用注册接口；
2. 创建唯一账户并验证登录；
3. 随后设置 `REGISTRATION_ENABLED=false` 并重新创建 API；应用返回 403；
4. Nginx 保留注册限速作为额外防护，代理路径规则不得作为唯一的注册控制方式。

公开多用户服务不能仅依赖 Nginx 路径限速，还需要邮箱验证、滥用处置、隐私政策、服务条款和容量评估。

## 6. Ubuntu 主机准备

### 6.1 系统预检

记录并核对：

```sh
cat /etc/os-release
uname -m
free -h
df -h
timedatectl status
```

应用大量使用时间戳、令牌过期和跨时区聚合，服务器时间同步必须处于正常状态。

### 6.2 账户与 SSH

- 创建独立部署账户；
- 使用公钥登录，至少保留一个已验证的备用管理会话；
- 确认密钥登录成功后，再考虑关闭密码登录和 root 远程登录；
- 修改 SSH 配置后先执行 `sshd -t`，新会话验证成功前保留现有 SSH 窗口；
- Docker 组等价于高权限管理能力，只把可信管理员加入该组，或直接通过 `sudo docker` 运维。

Ubuntu 官方建议通过 `sshd_config.d` 维护自定义配置，并在重启 SSH 前使用 `sshd -t` 校验，避免远程锁死。[Ubuntu OpenSSH 文档](https://ubuntu.com/server/docs/openssh-server/)

### 6.3 防火墙

按顺序执行：先允许当前 SSH 端口，再启用 ufw，最后开放 80/443。若管理 IP 固定，SSH 只允许该地址或网段。

上线后的端口监听应为：

```text
0.0.0.0:<SSH_PORT>   管理入口
0.0.0.0:80           HTTP / ACME
0.0.0.0:443          HTTPS / WSS
127.0.0.1:8080       Go API，仅本机
无 0.0.0.0:5432      PostgreSQL 不公开
```

ufw 是 Ubuntu 的默认防火墙前端，Docker 发布端口可能不受其规则保护。本方案通过不发布数据库端口限制访问，不依赖 ufw 阻断该端口。[Ubuntu 防火墙文档](https://ubuntu.com/server/docs/security-firewall/)

### 6.4 安装运行环境

- 从 Docker 官方 apt 仓库安装 Docker Engine、Buildx 和 Compose 插件；
- 安装 Nginx；
- 安装 Certbot 及 Nginx 集成组件，或按当时的官方推荐安装方式部署；
- 启用 Docker 与 Nginx 开机启动；
- 不使用 Docker convenience script 作为生产安装方式。

Let’s Encrypt 推荐大多数用户从 Certbot 开始，并强调使用可自动续期的 ACME 客户端。[Let’s Encrypt ACME 客户端说明](https://letsencrypt.org/docs/client-options/)

## 7. 服务器目录规划

```text
/opt/pactick/
├─ app/                         生产 Compose、Dockerfile 和服务端源码或发布清单
├─ config/
│  ├─ api.env                   0600
│  ├─ postgres.env              0600
│  ├─ compose.env               0600
│  └─ backup.env                0600，仅配置本机备份根目录
├─ releases/                    可选：保留最近两个发布版本的元数据
└─ scripts/                     备份、恢复、部署和健康检查脚本

/var/backups/pactick/
├─ daily/                       7 个本机每日逻辑备份
├─ weekly/                      4 个本机每周逻辑备份
├─ monthly/                     6 个本机每月逻辑备份
└─ pre-deploy/                  10 个迁移前备份
```

仓库、备份和密钥分开管理。备份目录不放进 Git；服务器上的 env 文件也不从开发机仓库自动覆盖。将备份保存到同机独立数据盘可以降低系统盘故障导致备份丢失的风险，但仍不能替代 1.0 计划中的异地副本。

## 8. DNS、Nginx 与 HTTPS

### 8.1 DNS

1. 为 `api.example.com` 创建指向服务器公网 IPv4 的 A 记录；
2. 只有服务器 IPv6 和防火墙都正确时才创建 AAAA；
3. 等待公网解析稳定后再申请证书；
4. 先用低 TTL 完成切换，稳定后再提高。

### 8.2 Nginx 代理要求

Nginx 将 `api.example.com` 代理到 `http://127.0.0.1:8080`。配置至少包含：

- 保留 `Host`、`X-Real-IP` 和 `X-Forwarded-For`；
- `proxy_http_version 1.1`；
- 显式转发 `Upgrade` 与 `Connection`，否则 `/v1/ws` 无法升级；
- WebSocket `proxy_read_timeout` 大于服务端 30 秒 ping 周期，建议 90 秒；
- 请求体上限与应用 2 MiB 限制一致；
- HTTP 全部跳转 HTTPS；
- 对认证接口限速，`/v1/ws` 不得按普通短请求限制；
- TLS 稳定后再启用 HSTS，避免证书或域名错误时难以回退。

Nginx 官方说明 WebSocket 的 `Upgrade` 和 `Connection` 是 hop-by-hop 头，反向代理时必须显式转发。[Nginx WebSocket proxying](https://nginx.org/en/docs/http/websocket.html)

### 8.3 证书

- 使用 Certbot 为真实域名申请证书；
- 验证 HTTP 到 HTTPS 跳转；
- 执行续期 dry-run；
- 监控证书到期时间，并检查续期任务的实际结果；
- 私钥只允许 root 和必要服务读取。

## 9. 首次部署运行手册

以下步骤规定部署顺序。执行前须按本节检查所需文件，不能仅依据历史计划判断仓库内容齐全。

### 9.1 发布前

1. 完成第 5 节的 Dockerfile 与生产 Compose 改造；
2. 在开发机执行 Go 测试、vet、镜像构建和容器启动测试；
3. 使用 PostgreSQL 17 空库执行迁移；
4. 运行 OpenAPI 认证与同步冒烟测试；
5. 给镜像或发布目录分配不可变版本号；
6. 记录上一版本号和数据库迁移版本。

### 9.2 上传与配置

1. 将源代码或已构建镜像发布到服务器；
2. 写入 `api.env` 和 `postgres.env`；
3. 检查 env 文件权限，确认文件未进入 Git，且普通用户无法读取；
4. 使用 `docker compose --env-file /opt/pactick/config/compose.env -f compose.production.yaml config --quiet` 校验配置，或直接运行 `deploy/scripts/validate-config.sh`；
5. 确认配置中没有宿主机 `5432` 发布，也没有 `0.0.0.0:8080`。

### 9.3 数据库与迁移

首次部署：

1. 启动 PostgreSQL；
2. 等待 healthcheck 通过；
3. 运行一次 migrate 服务；
4. 确认 `schema_migrations` 已记录当前迁移与校验值；
5. 启动 API。

后续部署：

1. 生成迁移前逻辑备份；
2. 验证备份文件非空且可被 `pg_restore --list` 读取；
3. 运行新版本 migrate；
4. 启动或滚动替换 API；
5. 完成冒烟检查后才清理旧镜像。

### 9.4 Nginx 与证书

1. 在本机先通过 `curl http://127.0.0.1:8080/healthz` 验证 API；
2. 启用仅 HTTP 的 Nginx 站点并验证域名；
3. 申请证书并启用 HTTPS；
4. 验证 REST、错误响应、2 MiB 限制和 WebSocket Upgrade；
5. 确认 8080/5432 从外网无法访问。

## 10. 上线验收清单

### 10.1 基础设施

- [ ] `docker compose ps` 中 PostgreSQL 健康，API 持续运行；
- [ ] 重启 Docker 后服务自动恢复；
- [ ] 重启整台服务器后服务自动恢复；
- [ ] 公网只开放管理端口、80 和 443；
- [ ] 8080 仅绑定回环地址，5432 没有宿主机监听；
- [ ] HTTPS 证书链正确，HTTP 自动跳转；
- [ ] Certbot 续期 dry-run 成功；
- [ ] Docker 日志轮转生效；
- [ ] 系统时间同步正常。

### 10.2 API

- [ ] `/healthz` 返回 200；
- [ ] `/readyz` 在数据库正常时返回 200，数据库不可用时返回非 200；
- [ ] 注册策略符合预期：个人服务在创建账户后禁止公开注册；
- [ ] 注册、登录、刷新、登出、设备撤销通过；
- [ ] 无效、过期或已撤销设备的 Bearer Token 被拒绝；
- [ ] push 幂等重试不重复创建变更；
- [ ] pull 游标分页和 `has_more` 正确；
- [ ] WebSocket 能返回 101，并在写入后收到最新游标提示；
- [ ] 账户导出不包含密码或令牌；
- [ ] 日志不出现密码、JWT、Refresh Token 或完整请求体。

### 10.3 数据与恢复

- [ ] 定时备份成功，文件大小和时间被监控；
- [ ] 每个本机备份都能通过 `pg_restore --list`，且 SHA-256 校验文件存在；
- [ ] 明确记录本阶段没有异地副本，服务器或磁盘丢失可能无法恢复；
- [ ] 在隔离环境执行一次完整恢复；
- [ ] 恢复后能登录、拉取数据并查询今日/日历/统计；
- [ ] 记录本机备份恢复耗时；该时间不代表主机级 RTO。

### 10.4 1.0 容灾验收（本计划中延期）

- [ ] 备份已加密复制到独立账户、机器或区域；
- [ ] 异地备份超过目标时间未成功时能够告警；
- [ ] 能够只依赖异地副本在全新主机恢复服务；
- [ ] 记录并评审实测 RPO、RTO；
- [ ] 恢复凭据、加密密钥和运行手册不只保存在生产服务器上。

### 10.5 客户端同步（M2）

- [ ] Release 构建使用 `https://api.example.com`；
- [ ] 两台设备登录同一账户；
- [ ] 设备 A 创建任务，设备 B 自动拉取；
- [ ] 双方离线修改不同字段后能够自动合并；
- [ ] 同字段冲突有确定结果和用户提示；
- [ ] 设备离线删除后不会被另一设备复活；
- [ ] 专注会话和计划/实际统计能够跨设备收敛；
- [ ] WebSocket 断开时，周期拉取仍能最终同步。

## 11. 备份与恢复计划

### 11.1 备份策略

建议使用 PostgreSQL custom format：

```text
pg_dump -Fc pactick > pactick-YYYYMMDD-HHMM.dump
```

它可由 `pg_restore` 检查和恢复，并支持按对象选择。PostgreSQL 官方说明逻辑备份能跨机器架构恢复，custom format 适合使用 `pg_restore` 管理。[PostgreSQL 17 SQL Dump](https://www.postgresql.org/docs/17/backup-dump.html)

最低策略：

- 每日 1 次全量逻辑备份；
- 每次数据库迁移前额外备份；
- 本机保留 7 个每日、4 个每周、6 个每月版本；
- 本机额外保留最近 10 个迁移前版本；
- 定期执行隔离恢复检查，验证本机备份可实际还原；
- 备份任务失败、备份超过 26 小时未更新或文件异常变小时告警。

Docker volume 仅保存运行数据。复制运行中的 PostgreSQL 数据目录不能替代逻辑备份或一致性快照。本机逻辑备份不提供异地容灾：如果生产数据库卷和 `/var/backups/pactick` 一起丢失，本方案无法恢复数据。

### 11.2 恢复原则

1. 不得在原数据卷上试验恢复；
2. 新建隔离 PostgreSQL 实例或新卷；
3. 创建目标角色与数据库；
4. 使用 `pg_restore` 恢复；
5. 验证迁移账本、用户、实体数量和关键 API；
6. 通过后再决定切换服务指向。

### 11.3 1.0 容灾升级范围

1.0 上线前必须在现有本机备份之外增加：

- 加密异地备份，目标位于独立账户、机器或区域；
- 异地副本完整性、最近成功时间和异常大小监控；
- 仅使用异地副本向全新 PostgreSQL 和新服务器恢复的演练；
- 加密密钥、云端凭据和恢复手册的独立保管；
- 经演练确认的 RPO/RTO；
- 按实际数据价值评估托管数据库自动快照与 PITR。

截至状态日期，上述能力尚未实现，也没有可启用的 rclone 配置；须另行实施并验收。

## 12. 监控与日常运维

### 12.1 最低监控项

| 对象 | 指标/检查 | 建议阈值 |
| --- | --- | --- |
| API | 外部 `/readyz` | 连续 3 次失败告警 |
| TLS | 证书剩余时间 | 小于 21 天告警 |
| 主机磁盘 | `/`、Docker、数据库卷 | 70% 预警，85% 紧急 |
| 内存/Swap | 持续占用与 OOM | 出现 OOM 立即告警 |
| 容器 | restart count、exit code | 非发布导致的重启即检查 |
| PostgreSQL | 连接数、库大小、慢查询 | 接近连接上限或异常增长告警 |
| 本机备份 | 最近成功时间、文件大小、校验结果、备份盘容量 | 超过 26 小时无成功备份或备份盘达到 70% 时告警 |
| 应用 | 5xx、登录失败、同步 rejected | 基线显著上升告警 |

### 12.2 例行维护

- 每周安装 Ubuntu 安全更新，并安排需要重启的维护窗口；
- 每月检查 Docker、Nginx、PostgreSQL 17 小版本和基础镜像更新；
- 更新镜像前先读发布说明、备份并在测试环境验证；
- 每月检查磁盘、日志轮转、证书续期和本机备份可读性；
- 每季度执行本机备份隔离恢复检查和访问权限复核；
- PostgreSQL 大版本升级单独立项，不与普通应用发布合并。

## 13. 发布与回滚

### 13.1 正常发布

```text
构建并标记新镜像
  → 运行测试
  → 生成迁移前备份
  → 执行 migrate
  → 启动新 API
  → health/ready/auth/sync/ws 冒烟
  → 观察 15–30 分钟
  → 标记发布成功
```

保留至少前两个应用镜像版本和对应发布记录。

### 13.2 回滚条件

- 应用代码故障且数据库兼容：切回上一镜像并重新创建 API 容器；
- 迁移仅包含向后兼容的新增内容：通常可先切回应用，但需要验证旧版本是否忽略新字段；
- 迁移破坏旧结构或数据：不得仅切换镜像，必须从迁移前备份恢复到新卷并验证；
- 本计划采用的迁移执行器仅自动应用 `.up.sql`，即使仓库存在 down SQL，也不能据此认定数据库回滚已经验证。

数据库恢复必须先在隔离卷中验证，避免进一步破坏原数据。

## 14. 分阶段工期建议

以下以熟悉 Linux、Docker、Nginx 和 Go 的一名开发者为基准：

| 阶段 | 工作 | 预计时间 | 完成条件 |
| --- | --- | --- | --- |
| A | 服务器信息、域名、注册策略和本机备份风险确认 | 0.5 天 | 五项输入明确 |
| B | 生产 Compose、迁移二进制、限速和配置改造 | 1–2 天 | 本地生产拓扑通过 |
| C | Ubuntu 加固、Docker、Nginx、DNS、TLS | 0.5–1 天 | HTTPS 与端口检查通过 |
| D | 首次部署、迁移、API/WebSocket 冒烟 | 0.5 天 | M1 功能验收通过 |
| E | 本机定时备份、监控和隔离恢复检查 | 0.5–1 天 | 本机备份可恢复、告警可达 |
| F | 客户端认证与同步 P0 接入 | 约 1–3 周 | 两设备端到端验收通过 |
| 1.0 容灾 | 加密异地备份、跨主机恢复、RPO/RTO 演练 | 另行评估 | 1.0 容灾验收项全部通过 |

按本计划估算，M1 需要 3–5 个工作日，包括部署和运行观察。M2 的主要工作是实现当时尚未接入的客户端同步。

## 15. 执行建议

建议先建立一个与生产拓扑相同的临时子域名，例如 `api-staging.example.com`：

1. 在 staging 完成镜像、迁移、Nginx、WebSocket、备份和恢复；
2. 使用 API 测试脚本验收 M1；
3. 客户端在 staging 接通认证与同步；
4. 完成两设备离线冲突测试；
5. 最后复制同一套发布配置到生产域名，只替换密钥、数据库卷和域名。

staging 用于分别检查服务端部署和客户端同步，并在不修改生产数据的情况下演练迁移与恢复。
