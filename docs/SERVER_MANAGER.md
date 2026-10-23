# 服务端发行包与命令行入口

当前管理界面的构建、配置、备份、隔离恢复和故障处理见[本机服务器管理界面](SERVER_MANAGEMENT.md)。本文保留已发布服务端包的启动脚本及账户管理命令，适用于包含这些文件的发行包；某个版本是否提供服务端包，以对应 Release 的附件清单为准。

`v0.3.0-preview.1` 已提供 Windows/Linux x86-64 服务端包。包根目录的 `launch-manager.cmd` 或 `launch-manager.sh` 启动本机管理器；`--data-dir` 可指定独立数据目录。不要只复制管理器可执行文件，配置、部署文件和工具目录必须一起保留。

源码中的 Docker 配置默认编译当前 Go 源码。`scripts/package_server.py` 生成的服务端包将包内 Compose 配置派生为 `Dockerfile.prebuilt` 与 `linux/amd64`，使用随包提供的 `prebuilt/` 程序；不会修改输入源码快照。`SOURCE_MANIFEST.json` 标识构建输入，`SERVER_PACKAGE.json` 记录该派生配置，`SERVER_MANIFEST.json` 标识最终包内文件。自行构建或运行前，核对目标系统、架构和 [构建要求](BUILDING.md)。

## 使用发行包运行 API

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
