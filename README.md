# Pactick

[English](README.en.md)

Pactick 是一个**个人爱好项目**，提供 Android 本地优先的任务、日历和专注功能。用户可以收集任务、安排时间、开始专注，并查看实际用时。

本项目有 ChatGPT 参与开发。

首版支持 Android。Windows、Linux、iOS、Web 客户端不属于本轮发行范围。

## 安装与使用

项目包含 Android 客户端和 Go 服务端，目前仍处于预览阶段。可从 [Releases](https://github.com/2354634715/Pactick/releases) 下载对应版本，也可自行构建；单机本地使用无需部署服务端，需要多设备同步时再部署自己的服务端。

构建后，在 Android 设备上安装 APK。首次使用进入本地工作区；需要同步时，在设置中填写自己的 HTTPS 服务端地址并登录。问题反馈方式见本文“许可与贡献”部分。

任务列表默认按“紧急 → 高 → 中 → 低 → 无”优先级排列；“今日”保留排期和手动顺序。任务温馨提醒默认开启：系统允许通知且当前工作区有未完成任务时，通知栏显示一条静默提醒，只显示数量；全部完成后移除，可在设置中关闭。操作及限制见 [Android 入门指南](docs/GETTING_STARTED.md)。

当前源码已包含自由专注与结束后首次关联任务、英语支持、私密任务箱、严格模式、专注桌面及系统日历联动。专注桌面和系统日历默认关闭；操作与限制见[入门指南](docs/GETTING_STARTED.md)和[项目状态](docs/PROJECT_STATUS.md)。Windows/Linux 服务器 GUI 和管理员建号已有实现，属于独立运维软件，不代表桌面任务客户端。

## 部署自己的服务端

准备安装了 Docker Engine、Compose v2 和 systemd 的 Ubuntu/Debian 主机。将源码放在固定目录，例如 `/opt/pactick/app`，并在源码根目录运行以下命令。

已有 HTTPS 反向代理时，使用本机模式：

```bash
sudo bash deploy/scripts/install.sh install --local-only
```

此模式仅监听服务器回环地址，远端客户端需通过已配置的 HTTPS 代理访问。

需要脚本配置 Nginx 和 Let's Encrypt 时，先安装 Nginx、Certbot、gettext-base，将域名 DNS 指向服务器，并开放公网 TCP 80 和 443。替换示例域名及邮箱后运行：

```bash
sudo bash deploy/scripts/install.sh install \
  --domain api.example.com \
  --email admin@example.com \
  --accept-acme-terms
```

API 仅绑定宿主机回环地址，PostgreSQL 不发布主机端口。安装脚本生成私有配置、构建镜像、在迁移前备份、显式执行迁移、启动 API、安装每日本机备份并检查就绪状态。注册默认关闭。

建号、注册开关、升级、备份及恢复步骤见 [自部署手册](docs/SELF_HOSTING.md)，各脚本用途见 [部署资产](deploy/README.md)。

## 从源码构建

Android 客户端：从仓库根目录运行以下命令，进入客户端目录后获取依赖、执行检查和测试，再构建 debug APK。

```bash
cd client
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

输出为 `client/build/app/outputs/flutter-apk/app-debug.apk`。debug 包使用开发证书，仅用于测试。

Go 服务端开发：在仓库根目录启动开发环境，并执行测试和静态检查。

```bash
docker compose up --build
go test ./...
go vet ./...
```

`docker compose up --build` 在前台运行；服务启动后，在另一个终端执行后两条命令。开发拓扑监听 `http://localhost:8080`，生产部署使用独立的 `compose.production.yaml`。

工具链和正式签名配置见 [构建说明](docs/BUILDING.md)；源码快照、签名 APK、SHA-256、证书指纹及公开前验收要求见 [发行流程](docs/RELEASING.md)。

## 许可与贡献

项目采用 Source Available（源码公开）许可。当前许可允许个人、研究、自部署及公司内部办公使用；免费分发和外部修改版网络服务需要提供对应源码；售卖软件、收费托管、广告变现及纳入对外商业产品受到限制。

具体条款见 [完整许可](LICENSE)、[中文场景 FAQ](docs/LICENSE_FAQ.md) 和 [第三方声明](THIRD_PARTY_NOTICES.md)。第三方组件继续遵守各自的许可。项目所有者已确认当前许可正文，正式公开前仍须完成相应第三方与分发审查。

提交问题或改进前，阅读 [贡献指南](CONTRIBUTING.md)。问题可通过 GitHub Issues 或邮箱报告，涉及敏感材料时按 [安全说明](SECURITY.md)私下联系。维护优先级依次为数据丢失与安全问题、核心功能缺陷、易用性、新功能；不承诺固定更新频率或响应时间。

## 项目文档

- [当前路线图](PROJECT_PLAN.md)
- [Android 入门指南](docs/GETTING_STARTED.md)
- [Android 排序与任务提醒真机检查](docs/ANDROID_TASK_REMINDER_CHECKLIST.md)
- [本地优先与可选同步架构](docs/PROJECT_ARCHITECTURE.md)
- [实体字段契约](docs/ENTITY_SCHEMAS.md)
- [服务端架构](docs/SERVER_ARCHITECTURE.md)
- [HTTP API](api/openapi.yaml)
- [变更记录](CHANGELOG.md)
