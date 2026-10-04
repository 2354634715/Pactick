# 从源码构建

首版支持 Android 客户端和 Go 服务端。本文说明两者的构建方法。

## 1. 检查构建环境

| 工具 | 当前验证基线 |
| --- | --- |
| Go | 1.26.4；最低要求另见 go.mod 及依赖 |
| Flutter | 3.47.4 stable，Dart 3.13.3；pubspec 要求 Dart ≥3.13.2 |
| Java | JDK 21 |
| Android | Android SDK、平台工具和已接受的 SDK 许可；由 Flutter 与 Gradle 配置决定编译 SDK |
| Python | 3.10+，仅使用标准库 |
| PostgreSQL / Docker | 自部署与集成环境参见 [SELF_HOSTING.md](SELF_HOSTING.md) |

运行 `go version`、`flutter doctor -v`、`java -version` 检查已安装的工具版本。首次下载依赖和 Android 工具链需要网络；依赖版本由 `go.sum`、`pubspec.lock` 和 Gradle 配置约束。锁文件不能替代 Android 最终解析依赖清单。

## 2. 构建服务端

在仓库根目录运行：

```sh
go mod download
go mod verify
go test ./...
go vet ./...
go build ./cmd/...
```

PostgreSQL 集成测试读取 `PACTICK_TEST_DATABASE_URL`。未设置时，`TestPostgres` 测试跳过；设置后连接、权限或迁移失败会导致测试失败。测试为每个场景创建独立 schema，结束时删除该 schema，连接用户必须具有创建和删除 schema 的权限。数据库必须专用于测试，不得使用生产连接。

已有临时 PostgreSQL 时，在仓库根目录运行以下命令；示例地址和凭据应与测试实例一致：

```sh
PACTICK_TEST_DATABASE_URL='postgres://pactick:pactick@localhost:5432/pactick_test?sslmode=disable' go test -count=1 ./internal/account ./internal/database ./internal/sync
```

PowerShell 中先执行 `$env:PACTICK_TEST_DATABASE_URL = 'postgres://pactick:pactick@localhost:5432/pactick_test?sslmode=disable'`，再执行相同的 `go test` 命令。测试控制真实事务的执行顺序，验证账户游标提交顺序、迁移与同步写入互斥、历史应用标识清理、导出期间的并发增删改和发起设备控制限制。GitHub Checks 工作流使用 PostgreSQL 17 服务，并设置该变量执行这些测试；本地未设置变量的通过结果不代表数据库场景已经验证。

通过 [自部署文档](SELF_HOSTING.md) 启动服务端并创建自用账号。

## 3. 构建 Android 开发包

```sh
cd client
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build apk --debug
```

输出为 `client/build/app/outputs/flutter-apk/app-debug.apk`。debug 包使用开发证书，仅用于测试。客户端首次启动进入本地工作区；需要同步时，在同步设置中配置自部署服务器。

仓库不包含 `android/local.properties`，Flutter 会在构建前生成本机 SDK 路径。如果 Windows 的路径包含 `&` 等特殊字符导致 Gradle 启动异常，应将源码复制到不含这些字符的干净目录后构建。

## 4. 构建正式包

尚无长期签名密钥时，先按 [Windows 本机创建和备份签名密钥](ANDROID_SIGNING.md)完成生成与独立备份验证，再配置构建。

在本机构建机上，参照 `client/android/key.properties.example` 配置 `key.properties` 和长期使用的正式 keystore，然后运行：

```sh
cd client
flutter build apk --release --dart-define=RELEASES_URL=https://github.com/OWNER/REPOSITORY/releases
python3 ../scripts/verify_apk_notices.py build/app/outputs/flutter-apk/app-release.apk
```

`OWNER/REPOSITORY` 必须替换为实际审核后的发行仓库。缺少签名配置时 release 构建失败。自行签名版本不能直接覆盖使用不同证书的官方版本，迁移前需导出并验证备份。解决签名冲突前必须保留可恢复的数据副本；不得先卸载持有唯一数据副本的客户端。

签名候选 workflow、校验和、证书指纹及真机验收见 [发行说明](RELEASING.md)。Flutter 官方签名文档见 [Build and release an Android app](https://docs.flutter.dev/deployment/android)。

项目默认将 Gradle 堆上限设为 2 GiB、metaspace 上限设为 1 GiB，最多使用两个 worker。实际构建还会启动 Dart、Kotlin 或其他工具，需要额外内存。出现 JVM 原生内存分配失败时，检查电脑可用内存与交换空间；可以在当前构建进程的 `GRADLE_OPTS` 中设置 `-Dorg.gradle.jvmargs="..."` 覆盖参数。参数优先级见 [Gradle 构建环境说明](https://docs.gradle.org/current/userguide/build_environment.html)。

## 5. 生成公开源码快照

```sh
python3 -m unittest discover -s scripts -p 'test_*.py'
python3 scripts/verify_third_party_notices.py
python3 scripts/verify_supplemental_notices.py
python3 scripts/prepare_public_source.py --check
python3 scripts/prepare_public_source.py ../pactick-public
```

目标目录必须不存在。工具按允许列表复制源码、测试、迁移、锁文件、公开文档和模板，不删除或修改原目录。输出 `SOURCE_MANIFEST.json` 记录每个文件的 SHA-256。文本会规范化为 LF；脚本保留可执行权限。

`.gitignore` 用于排除本地环境配置、签名材料、数据库、备份、导出、缓存及构建产物。根目录的 `*.sql` 不进入 Git；`internal/database/migrations/` 中的迁移 SQL 仍可提交。`.env.example`、`*.env.example` 等明确示例和 `key.properties.example` 保持可见。`test_gitignore.py` 在隔离 Git 仓库中验证根目录、客户端和 Android 的规则及这些例外，上述 Python 测试命令会执行它。

本地备份和服务器导出的默认文件名 `pactick-backup*.json`、`pactick-export*.json`、`pactick-server-export*.json` 也被排除。自定义名称的导出应保存在根目录 `exports/` 或 `backups/` 中；任意 JSON 文件不能统一排除，因为项目本身包含必须分发的 JSON 配置和许可材料。

快照工具独立排除源码目录内的实际 `*.env`、本地凭据、`.codex`／`.agents` 配置、数据库伴随文件，以及备份、归档和临时文件；不依赖文件是否已被 Git 忽略。允许提交的示例仍须通过内容扫描。提交前另运行 `git ls-files -ci --exclude-standard`，结果应为空；出现文件时，先检查其内容和历史，再处理已跟踪状态。忽略规则和快照过滤均不会删除 Git 历史中的内容。

Checks 和签名候选工作流也执行上述已跟踪文件检查；命中忽略规则时，检查步骤只打印文件路径并失败。签名候选工作流不会继续生成或上传候选制品。

服务端 Docker 构建上下文只包含 Go 源码、模块文件、预构建命令和许可材料。`.dockerignore` 在重新包含源码目录后再次排除目录内的实际环境配置、凭据、密钥、数据库、备份、归档和临时文件；这些文件不会因为位于 `cmd/` 或 `internal/` 中而进入构建上下文。

`verify_third_party_notices.py` 只读取源码和证据，检查声明中的 Go／Dart 版本、所列本地许可文本的哈希、必需 SDK／字体／Gradle wrapper 记录，以及 Android POM 记录是否完整。检查失败时，按 [第三方核查说明](THIRD_PARTY_AUDIT.md) 重新采集并审阅证据，不修改哈希来跳过差异。该命令不会确认法律兼容性、素材使用权或最终 APK 的全部通知义务；Checks 和签名候选工作流均执行此检查。

`verify_supplemental_notices.py` 核对已审阅的补充资产、组件版本、完整原始通知、必要鸣谢及图标／wrapper 的来源哈希。`verify_apk_notices.py` 同时检查最终 APK 内的项目许可、全部 Flutter 引擎正文和该补充资产的字节。缺失或差异会导致命令失败。依赖或素材发生变化时，重新核对对应版本的条款、更新资产和审阅记录后再构建；仅更新哈希不能替代条款审阅。运行时依赖图的复核参数见 [第三方核查说明](THIRD_PARTY_AUDIT.md)。

工具扫描已知凭据形态、真实公网 IPv4、私人 Windows 用户路径，并从本地历史部署手册提取禁发地址。敏感配置赋值规则覆盖实际使用的 `AUTH_JWT_SECRET`，以及数据库密码、token 哈希密钥和 Android 签名密码／Base64 密钥；识别长度至少 32 字符的值、shell/env 与 YAML 赋值、引号、空白和 LF/CRLF。已声明的开发示例和替换占位值不作为密钥处理，短密码和其他写法仍可能漏检。还可用 `--private-terms /path/to/local-only-terms.txt` 加入每行一个的私密禁发值。扫描错误只报告文件和规则，不回显凭据。该扫描使用启发式规则，不能识别所有凭据。发布前仍须人工审阅图片、Gradle wrapper JAR、可能遗漏的凭据及全部公开文字。

进入新目录，重新执行上述 Go 和 Flutter 检查，核对 manifest 后建立新 Git 仓库。新增源码目录或公开文档时，应同步更新脚本中的允许列表。
