# Pactick 发布验收与社交媒体宣发计划

更新日期：2026-10-04。当前检查版本：`0.2.0-preview.1+5`，Android 应用标识：`com.example.pactick`。下文的 `+3`、`+4` 结果属于对应候选的历史记录。

本文汇总首次发布前尚未完成的工作、各项操作步骤和完成条件，以及社交媒体宣发所需的资料、素材、渠道和反馈安排。读者为项目维护者及参与验收的测试人员。

本文中的待办和建议不代表已经执行。验收结果应记录对应源码提交、制品哈希、环境、日期和日志。版本、制品或关键配置改变后，需重新判断哪些结果仍适用。

首轮范围已确定为源码预览和 Android 预览 APK，暂不推荐公网自部署。官方仓库为 [2354634715/Pactick](https://github.com/2354634715/Pactick)，发行入口为其 [Releases](https://github.com/2354634715/Pactick/releases)，私下安全报告邮箱为 `w66610@outlook.com`。链接和邮箱已写入文档，页面可达性与收件仍待实测。源码、APK 和以后自部署推荐分别按 [发行流程](RELEASING.md) 验收。

## 1. 当前结果与执行顺序

2026-10-04 的补充检查已在隔离 PostgreSQL 17 中实际执行六个顶层集成测试及全部子场景，均通过。真实临时数据库的每日备份、迁移前备份、校验、隔离恢复和损坏备份拒绝通过，测试只使用合成数据。维护者另行确认覆盖升级、双设备、长期后台、实际通知展示和远端 CI 均通过；公网部署尚未完成。完整 Linux 安装、带数据应用升级及新主机恢复没有在本轮全部核实，本次补充说明未逐项确认其结果。源码、Git 忽略规则、构建及 Android 检查范围与结果来源见 [最终检查记录](FINAL_CHECK_20261004.md)。

2026-10-01 的修复已处理审查中确认的七项代码问题：同步游标提交顺序、历史应用标识副本清理、升级配置提交时机、保存失败后的界面状态、数据库打开重试、账户导出一致性和敏感配置扫描。专注发起设备限制、原生服务恢复及签名候选与源码的对应检查也已加入实现。

以下是当日已有的本地验证记录，不是本文新增执行的验收结果：

| 检查 | 已记录结果 | 尚不能证明的事项 |
| --- | --- | --- |
| Go | 独立源码快照的依赖校验、全量测试、vet 和命令构建通过 | 真实 PostgreSQL 场景 |
| PostgreSQL | 六个顶层集成测试已编译；因未设置测试连接而跳过 | 事务顺序、迁移和导出在真实数据库中的结果 |
| Flutter | 独立快照 analyze 无问题，104 项测试通过 | 真机行为和完整候选 APK |
| Python 发布脚本 | 14 项回归测试及允许列表扫描通过 | 全部文件的人工隐私审阅 |
| 部署脚本 | 语法、模拟安装和升级失败场景通过 | 真实 Linux 安装、升级和恢复 |
| Kotlin | 原生代码专项编译通过，跳过 Flutter 构建任务 | 完整 APK 构建和安装 |
| Android 原生依赖 | 75 个模块、74 个选中二进制已解析；采集七份内嵌文本 | 最终签名 APK 的完整许可审阅；67 个二进制仍需核查上游 |
| 源码快照 | 当日快照包含 337 个允许列表文件，另附 manifest | 后续修改后的最终文件集和实际 Git 暂存内容 |

原生通知采集演练使用过旧 debug APK，其哈希不能作为当前签名候选的证明。Kotlin 专项编译也不能代替完整 Flutter APK 构建。2026-10-01 的上述记录不包含已经验证的正式签名 APK、公开仓库或公网部署结果。

2026-10-02 签名候选构建前的进度记录：

| 项目 | 结果 | 剩余限制 |
| --- | --- | --- |
| 项目许可 | 所有者确认现有条款及公开署名，两份正文同步，FAQ 状态更新 | 不代表第三方兼容性审阅完成 |
| 发布入口 | 仓库、Releases、Issues 和报告邮箱写入文档；GitHub 连接器已确认仓库可访问，当时为私有空仓库 | 当时尚未上传公开源码或发行制品；未发送测试邮件，未核验收件 |
| 客户端 | 四小时任务滑块问题已修复；新 GUI 的 analyze 无问题、135 项测试通过，debug APK 已构建；本地 GUI 实施记录保存在维护工作目录 | 签名候选检查与真机验收分别记录 |
| 后端 | 独立副本依赖校验、全量测试、vet 和命令构建通过 | 真实 PostgreSQL 的六个顶层测试及数据库子场景均跳过；Docker 启动失败后停止相关操作 |
| 发布工具 | 加入本机交互式签名配置后，26 项 Python 回归通过；此前两份工作流 YAML 及 14 个 Bash 步骤语法检查通过 | 当时尚未执行远端 CI |
| 发行证据 | 新增构建前后固定来源比对、第三方锁定版本及许可文本哈希校验；当前 103 个组件与 75 个 Android 元数据核验通过 | 本机已有 runtime graph 的匹配结果不代表本次签名 APK，法律及通知审阅仍待完成 |
| 用户资料与素材 | 入门指南已按新 GUI 修正；新客户端 13 个 PNG 和 7 个绘制 XML 均有清单，品牌图标生成与转换记录已核对 | 专注通知图标作者和上游仍待确认；素材清单不等于最终许可审阅 |
| 签名准备 | 维护者已创建长期 JKS 密钥，pactick 别名为私钥条目；已提供 [本机签名配置脚本及指南](ANDROID_SIGNING.md) | 独立备份、密码配置和最终签名 APK 校验仍待完成 |

本机日志保存在 `output/release-validation-20261002/`，不随公开源码分发。检查副本生成时间不同，最终发行前需重新生成快照并核对影响运行的文件与测试对象一致。此前源码文件数量是历史范围，不作为最终文件集的固定值。

后续签名候选已构建完成，版本仍为 `0.2.0-preview.1+3`。本轮固定来源为 362 文件的独立源码快照，本地提交 `f40065691bd2c1e9581cf93d3d4acafd8333b9a6`；提交及标签尚未推送。APK 签名证书与维护者长期密钥一致，构建后来源比对、135 项 Flutter 测试、26 项 Python 回归及包内完整项目和引擎许可文本检查通过。

电脑上的隔离 PostgreSQL 17.11 已完成六组真实集成测试，10 个测试节点通过且没有跳过。带数据库的 Go 全量测试有 74 个通过节点，仅 Windows 升级 shell harness 预期跳过；其对应模拟场景已通过 Git Bash 验证。真实回环 API 的 19 个 HTTP 检查覆盖注册登录、两份设备登记的同步、冲突、墓碑、账户隔离和退出。临时 API 与数据库已停止，未处理 Docker 故障或连接个人数据库。这些结果不能代替正式 APK 的手机 HTTPS/WSS 和双设备检查。

候选制品、固定来源和本机证据保存在 `output/signed-candidate-20261002/`；最终 APK 哈希为 `5a74b141e7723dd865f721718e38557a65cb9d2905acebe893682e23ace14f90`。该候选生成时仍需手机验收、独立签名密钥备份、实际客户端同步、专注通知素材来源及最终第三方通知审阅、远端 CI 和公开发布；当前进度以本节开头及交付物清单为准。候选源码归档保持构建时内容，后续维护文档变更不得当作该 APK 已构建的来源。

建议执行顺序：

1. 确认许可、版权和素材来源，确定仓库及反馈入口。
2. 审阅干净源码，执行 PostgreSQL 和远端 CI 检查。
3. 构建签名候选，审阅最终第三方通知。
4. 执行 Android 真机、Linux 部署、升级、备份和恢复验收。
5. 补齐普通用户指南、宣发素材和统一入口，进行小范围试用。
6. 更新验收状态，公开已审阅源码和对应制品，再扩大宣发渠道。

准备账号、演示素材和开发进展内容可以与验收并行。允许先公开满足对应条件的源码预览，APK 下载仍须满足 [发行流程](RELEASING.md) 中的 APK 验收要求。真实 Linux 安装、恢复和公网验证保留为以后推荐自部署前的要求。

## 2. 发布前剩余事项与操作方法

### 2.1 确认正式项目许可

项目所有者已于 2026-10-02 确认保留 [LICENSE](../LICENSE) 的现有条款，署名为“王辰昊 Wang Chenhao”。根目录与 `client/LICENSE` 已同步为正式正文，Source Available 定位不变。

后续修改条款或版权信息时，重新确认有权提供的贡献及授权，并同时修改两份正文和 [许可 FAQ](LICENSE_FAQ.md)。许可正文一致性由发布脚本检查。

项目许可确认与第三方兼容性审阅分别记录。本次确认不代表全部素材使用权、依赖兼容性或专业法律审查已完成；这些事项仍须按下列条目核实。

当前结果：项目许可条款及署名已确认，两份正文一致；第三方与素材审阅另行完成。

### 2.2 确认图标、插画、字体和其他素材来源

现有文件本身不能证明项目拥有分发权。按最终源码和 APK 实际包含的内容建立素材清单，记录文件路径、作者或来源、原始链接、适用许可、署名要求和授权证据。

2026-10-02 的 [素材来源核对](ASSET_SOURCES.md)已确认当前品牌图标来自图片生成工具及后续转换。当前客户端分发 13 个 PNG 和 7 个绘制 XML；专注通知图标仍缺少作者和上游记录。旧启动矢量已从当前客户端移除，历史快照不进入本次发行。

优先核对 Android 各尺寸启动图标，以及实际使用的插画、字体、截图和示例数据。原创素材保留原始工程或作者确认记录；第三方素材保留取得时适用的许可。无法确认来源的素材应替换为权利明确的文件，或从发行范围移除。

截图使用演示账号和演示数据重新制作，检查通知栏、个人任务、服务器地址和图片元数据。必要的署名、版权和许可应进入对应分发材料。

完成条件：每个实际分发素材有可核查来源，适用通知齐备，公开截图不含个人数据。

### 2.3 配置正式仓库和安全报告入口

仓库、邮箱与 Releases 地址已确定，见本文开头及 [SECURITY.md](../SECURITY.md)。未验证其外部可用性，也未执行推送。

1. 核对 `2354634715/Pactick` 的归属、可见性、默认分支和实际提交内容；需要私有验收时使用独立私有仓库。
2. 验证 [Issues](https://github.com/2354634715/Pactick/issues) 和 [Releases](https://github.com/2354634715/Pactick/releases) 可访问，按 [SECURITY.md](../SECURITY.md) 配置安全报告。
3. 人工验证邮箱收件和维护者通知。测试报告只使用演示内容，不提交真实漏洞或敏感数据。
4. 确认发行入口为实际仓库的 `/releases`。签名工作流根据仓库名生成 `RELEASES_URL`，本机构建需要显式填写。
5. 仓库公开后可启用 GitHub Private vulnerability reporting，并配置安全通知。该功能针对公开仓库，不能假定私有验收仓库已经提供该入口。配置方法见 [GitHub 官方说明](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/configure-vulnerability-reporting/configure-for-a-repository)。

完成条件：文档链接正确，私下报告能够送达，最终 APK 的“查看发布版本”打开正确页面。

### 2.4 审阅最终公开源码和 Git 文件集

自动扫描不能代替全部公开文字、图片和 JAR 的人工审阅。修改许可、文档或其他发行内容后，必须重新生成快照；337 文件是此前验证范围，不是后续固定数量。

在原项目根目录执行，要求 Python 3.10+：

```powershell
python scripts/prepare_public_source.py --check
python scripts/prepare_public_source.py output/public-source-release
```

目标目录必须不存在。Linux 使用 `python3` 执行同一脚本。扫描失败时先处理报告中的文件和规则，再重新生成，不应绕过检查。

1. 对照新目录的 `SOURCE_MANIFEST.json` 审阅全部发行文件。
2. 检查配置示例、注释、文档、图片和 Gradle wrapper JAR，确认没有真实密钥、私人部署地址或个人资料。
3. 仅在干净快照目录建立新 Git 仓库；不复制原工作目录的历史归档、缓存、部署配置或其他 Git 历史。
4. 暂存后检查实际提交内容和作者信息：

```bash
# 在新生成的干净源码目录执行
git init -b main
git add .
git diff --cached --name-only
git diff --cached --stat
git diff --cached
```

Git 初始化和暂存用于审阅，此处不执行推送。检查通过后再建立发行提交。包含测试缓存和构建产物的副本不能直接作为发行目录。

完成条件：manifest、人工审阅范围和实际 Git 文件集一致。结果不扩展到未审阅的旧 APK、压缩包、远端或 Git 历史。

### 2.5 真实执行 PostgreSQL 集成测试和远端 CI

需要 Docker 和 Go，以及一个专用于测试、允许创建和删除 schema 的数据库。不得使用生产数据库连接。以下测试密码只用于绑定回环地址的临时实例。

在 Linux 验收机启动 PostgreSQL 17：

```bash
docker run --detach --rm --name pactick-pg-integration \
  --publish 127.0.0.1:15432:5432 \
  --env POSTGRES_DB=pactick_test \
  --env POSTGRES_USER=pactick \
  --env POSTGRES_PASSWORD=pactick \
  postgres:17

docker exec pactick-pg-integration pg_isready \
  -U pactick -d pactick_test
```

首次尚未就绪时等待后重试；报告 accepting connections 后，在待发行源码根目录执行：

```bash
export PACTICK_TEST_DATABASE_URL='postgres://pactick:pactick@127.0.0.1:15432/pactick_test?sslmode=disable'

go test -count=1 -v -run '^TestPostgres' \
  ./internal/database ./internal/sync ./internal/account

go test -count=1 ./...
```

PowerShell 中使用：

```powershell
$env:PACTICK_TEST_DATABASE_URL = 'postgres://pactick:pactick@127.0.0.1:15432/pactick_test?sslmode=disable'
go test -count=1 -v -run '^TestPostgres' ./internal/database ./internal/sync ./internal/account
go test -count=1 ./...
```

六个顶层测试分别验证：

- 历史策略、同步日志、幂等结果和冲突副本中的应用标识清理。
- 同账户游标提交顺序及分页完整性。
- 迁移等待正在执行的同步写事务。
- 用户、设备和实体在导出时使用同一快照。
- 导出不存在的账户返回错误。
- 只有发起设备可以控制专注会话。

测试完成后可删除本次专用容器：

```bash
docker rm --force pactick-pg-integration
```

随后在私有验收仓库运行 `.github/workflows/checks.yml` 的 Checks，确认 Go、部署脚本以及 Flutter analyze、test 和完整 debug APK 构建通过。工作流已有 PostgreSQL 17 服务和测试连接，但配置存在不等于运行成功。

完成条件：六个测试全部 PASS，没有因缺少连接而 SKIP；远端 Checks 成功，保存完整日志、工具版本和对应提交。

### 2.6 构建和核验正式签名候选 APK

需要已审阅的发行提交、Android 工具链和长期使用的正式签名密钥。已有正式密钥时继续使用；首次发行才创建新密钥。密钥放在仓库外，在独立受保护位置备份并验证可读性。证书中的身份信息随 APK 分发，创建时需确认。参见 [Android 签名说明](https://developer.android.com/studio/publish/app-signing)。

在 GitHub Settings → Environments 创建 `android-release`，限制默认分支，并按可用功能设置审核规则。填写四个环境 Secret：

| Secret | 内容 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | 正式 keystore 的 Base64 |
| `ANDROID_STORE_PASSWORD` | keystore 密码 |
| `ANDROID_KEY_ALIAS` | 正式 key alias |
| `ANDROID_KEY_PASSWORD` | key 密码 |

私有仓库的环境和审核功能受 GitHub 套餐限制，不能假定所有账户均可使用。按 [GitHub 环境说明](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments) 核对实际账户能力。无法提供所需环境时，可在受控 Linux 构建机按 [构建文档](BUILDING.md) 生成候选并保留等价证据，不能因此提前公开未审阅源码。

候选工作流操作：

1. 确认 `client/pubspec.yaml` 的版本和正整数构建号。当前为 `0.2.0-preview.1+3`，标签示例为 `v0.2.0-preview.1`，标签不含 `+3`。
2. 为 Checks 通过的提交创建版本标签，不覆盖已发行标签。
3. 从默认分支手动运行 Build signed Android candidate，输入已审阅标签。
4. 下载候选 artifact，核对 APK、源码 tar.gz、提交和版本信息、工具链、第三方证据、签名指纹及校验文件。

工作流在注入签名材料前校验版本、根目录与客户端许可及 manifest，在同一快照中检查和构建，再核对来源文件。源码包在签名配置进入构建目录前生成。私有 keystore 和临时 `key.properties` 不得进入源码包。

本机构建需要参照 `client/android/key.properties.example` 配置签名，构建命令在候选快照的 `client` 目录执行：

```bash
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build apk --release \
  --dart-define=RELEASES_URL=https://github.com/OWNER/REPOSITORY/releases
```

替换 `OWNER/REPOSITORY`。本机也必须使用与分发源码相同的快照，并按工作流保存来源、版本、工具链和签名证据。Windows 路径包含 `&` 等特殊字符时，使用不含这些字符的干净构建目录或 Linux 构建机。

最终 APK 使用 Android SDK 的工具核验：

```bash
apksigner verify --verbose --print-certs pactick.apk
sha256sum pactick.apk
```

`pactick.apk` 为待上传的最终文件；本机构建的默认输出位于 `client/build/app/outputs/flutter-apk/app-release.apk`。核验方法见 [apksigner 官方说明](https://developer.android.com/tools/apksigner)。

完成条件：签名成功，证书对应正式密钥，制品和源码对应，最终 APK 的 SHA-256 与证书指纹有记录。

### 2.7 审阅最终 APK 的第三方许可和 NOTICE

已有采集证据不能替代实际分发组件的条款审阅。应针对最终签名候选重新解析运行时依赖，并采集本次二进制和通知。

完成 Flutter 依赖解析后，在候选源码的 `client/android` 目录执行：

```bash
./gradlew -I ../../scripts/android-dependencies.init.gradle \
  :app:writeRuntimeDependencyInventory
```

回到源码根目录执行，采集目标目录必须不存在：

```bash
python3 scripts/capture_android_notices.py \
  artifacts/android-runtime-dependencies.json \
  client/build/app/outputs/flutter-apk/app-release.apk \
  artifacts/android-native-evidence

python3 scripts/verify_apk_notices.py \
  client/build/app/outputs/flutter-apk/app-release.apk
```

1. 对照实际版本核对许可、版权和 NOTICE，不能只依据 POM 的许可名称。
2. 对 `no-embedded-text-found-review-upstream` 项，从官方源码或发行文件取得适用证据。
3. 确认必要通知已进入 APK 许可页，或按适用条款随包分发。现有 APK 校验脚本检查完整项目许可和 Flutter 引擎文本，不检查全部 Maven 组件义务。
4. 审阅特殊条款与定制项目许可的兼容性；必要时替换组件或取得适当授权。
5. 真机打开“设置 → 关于 Pactick”，确认许可页可访问。当前代码直接调用 `showLicensePage`，没有额外的“查看许可”中间步骤。
6. 对构建工具和容器基础镜像，按实际分发范围单独核对义务。

需要更新声明时，按 [第三方核查文档](THIRD_PARTY_AUDIT.md) 的缓存参数重新生成。生成器和采集器的 `completed_legal_audit` 固定为 false，应另写带日期、审阅范围、APK 哈希和结论的人工记录，不能手改该字段代替审阅。

缺失或不完整证据应补齐后重新采集。补充通知改变源码或 APK 时，重新构建候选和校验全部制品。完成条件：本次依赖、条款、通知分发位置及人工结论均可追溯。

### 2.8 验收真实 Linux 安装和带数据升级

需要独立 Ubuntu/Debian 验收机、Docker Engine、Compose v2、systemd，以及可下载依赖的网络。源码固定放在 `/opt/pactick/app`，配置和备份位于源码目录外。HTTPS 模式还需要 Nginx、Certbot、curl、OpenSSL 和 gettext-base 等前置工具，详见 [自部署指南](SELF_HOSTING.md)。

在 `/opt/pactick/app` 执行：

```bash
sudo bash deploy/scripts/install.sh install --local-only
sudo bash deploy/scripts/install.sh status
sudo systemctl status pactick-backup.timer
sudo bash deploy/scripts/install.sh registration open
```

使用客户端或 API 建立测试账号后关闭注册：

```bash
sudo bash deploy/scripts/install.sh registration close
```

检查关闭后新注册被拒绝、已有账号仍能登录。默认配置目录为 `/opt/pactick/config`，备份目录为 `/var/backups/pactick`，API 监听 `127.0.0.1:8080`，PostgreSQL 不发布主机端口。远端 Android 设备不能直接访问服务器的回环地址，需要 HTTPS 入口。

自定义配置目录时，每次 `install.sh` 命令均加 `--config-dir /实际目录`。`--backup-dir` 和 `--port` 属于安装参数；`backup` 不接受文件或目录位置参数。重复安装复用已有配置、密码、端口和备份路径，源码更新使用 `upgrade`。

带数据升级步骤：

1. 取得真实旧版本源码、镜像或已有部署，在独立环境建立任务、项目、计划及专注历史，记录数量、ID、导出内容和迁移账本。
2. 保留旧源码、镜像、配置和备份。停止管理员另外启动的同库写入进程；升级脚本只负责其 Compose API。
3. 更新同一目录的源码，保留配置和数据库卷，再执行：

```bash
sudo bash deploy/scripts/install.sh upgrade
sudo bash deploy/scripts/install.sh status
```

4. 检查正式镜像配置只在成功后更新，`.release-pending` 已清除，`pre-deploy/` 有本次备份，迁移账本包含新清理迁移。
5. 核对原账号登录、实体数量和内容、双设备同步，以及第二个账号的数据隔离。
6. 在可丢弃环境演练构建失败、备份失败、迁移失败和 API 就绪失败。构建或备份失败应保留旧 API 和正式配置；迁移开始后的失败应保留待处理标记并阻止注册开关重建 API。
7. 修复失败原因后重试升级。不能因正式配置仍指向旧镜像而认定数据库已回滚；旧 API 不兼容新数据库时不得直接启动，恢复迁移前备份会丢弃备份后的写入。

完成条件：干净安装和真实旧数据升级均通过，失败处理符合契约，有实际容器、迁移和业务日志。

### 2.9 验收备份、隔离恢复和新主机恢复

在验收服务器的 `/opt/pactick/app` 执行：

```bash
sudo bash deploy/scripts/install.sh backup

sudo bash deploy/scripts/install.sh restore-check \
  /var/backups/pactick/daily/实际生成的文件.dump

sudo journalctl -u pactick-backup.service --since yesterday
```

选择备份命令实际输出的文件，保存同名 `.dump.sha256` 并核对。脚本默认保留七个每日、四个每周、六个月度和十个迁移前副本。还需等待并核对至少一次正常定时备份。

隔离恢复成功时应输出 `restore check passed`，临时容器和卷被清理，原库不变。校验文件存在时脚本会检查它；本项验收要求同时保留并检查校验文件。脚本只检查恢复成功、迁移账本和 users 表存在，不能替代账号、实体数量和业务内容核对。

需要检查临时数据库时，可使用 `PACTICK_KEEP_RESTORE=true` 保留资源；检查后仅清理本次输出的资源，不清理其他部署卷：

```bash
sudo env PACTICK_KEEP_RESTORE=true \
  bash deploy/scripts/install.sh restore-check \
  /var/backups/pactick/daily/实际生成的文件.dump
```

新主机恢复需要第二台隔离服务器：

1. 安装兼容的 PostgreSQL 主版本和所需应用版本，保持注册关闭，验收前不公开服务。
2. 将 `.dump` 和 `.dump.sha256` 复制到新机私有目录，停止新机 API，确认恢复目标是允许覆盖的验收数据库。
3. 在新机 root shell 中执行以下命令。示例使用默认配置目录，备份文件放在 `/root/pactick-recovery`；目录、文件名和配置路径需与实际一致。

```bash
set -euo pipefail
cd /opt/pactick/app
compose=(docker compose --project-directory /opt/pactick/app \
  --env-file /opt/pactick/config/compose.env \
  -f /opt/pactick/app/compose.production.yaml)

"${compose[@]}" stop api

cd /root/pactick-recovery
sha256sum --check 实际文件.dump.sha256

"${compose[@]}" exec -T postgres sh -eu -c \
  'exec pg_restore --clean --if-exists --no-owner --no-privileges --exit-on-error --username="$POSTGRES_USER" --dbname="$POSTGRES_DB"' \
  < /root/pactick-recovery/实际文件.dump

cd /opt/pactick/app
"${compose[@]}" --profile maintenance run --rm --no-deps migrate
"${compose[@]}" up -d --no-deps --force-recreate \
  --wait --wait-timeout 90 api

bash deploy/scripts/install.sh backup
bash deploy/scripts/install.sh status
```

`pg_restore --clean` 会删除恢复涉及的已有对象，只能用于明确允许覆盖的目标，参数含义见 [PostgreSQL 官方说明](https://www.postgresql.org/docs/17/app-pgrestore.html)。恢复或迁移失败时停止后续启动步骤，查验日志和迁移账本；不得继续对外提供服务。

历史备份恢复后执行当前迁移再对外服务。新迁移不会改写旧备份中的历史应用标识。数据库备份不包含服务器配置和 JWT 密钥，维护者须决定私下迁移配置，或使用新密钥并要求重新登录。

4. 检查 `/readyz`、旧账号登录、实体数量和内容、恢复后双设备同步及新备份。旧客户端游标与恢复后的数据库也需实际验证，不能假定同步自动恢复。
5. 验收后再切换域名或客户端地址，保留原主机供回退。将备份复制到另一台主机或离线介质并实际恢复，才能证明能够应对原主机或磁盘丢失。

完成条件：隔离恢复和新主机恢复均通过，业务内容正确，备份可以脱离原主机使用。

### 2.10 验收真实 HTTPS、证书续期和公网 WSS

需要维护者控制的域名、ACME 联系邮箱，以及接受 ACME 条款的决定。A/AAAA 应指向目标服务器，公网 TCP 80、443 可达；无效 AAAA 应移除。安装器不修改防火墙。

在 `/opt/pactick/app` 执行，将示例域名和邮箱替换为实际值：

```bash
sudo bash deploy/scripts/install.sh install \
  --domain api.example.com \
  --email admin@example.com \
  --accept-acme-terms

sudo env PACTICK_PUBLIC_URL=https://api.example.com \
  bash deploy/scripts/verify-deployment.sh

sudo certbot renew --dry-run
sudo systemctl status certbot.timer
sudo bash /etc/letsencrypt/renewal-hooks/deploy/pactick-nginx.sh
```

自定义配置目录时，安装入口带 `--config-dir`，直接验证脚本使用 `sudo env PACTICK_CONFIG_DIR=/实际目录 PACTICK_PUBLIC_URL=https://实际域名 ...`。

验收内容：

- Certbot 实际签发目标域名证书，域名和可信链正确；签发失败时原 Nginx 站点保留。
- 验证脚本检查容器健康、回环 API、数据库无主机端口、健康接口和备份时效；公网 `/readyz` 成功，HTTP 跳转正常。
- 续期 dry-run 成功，timer 启用，Nginx reload hook 实际执行成功。
- 从另一条网络或另一台设备访问 HTTPS，不只在服务器本机测试。
- 两台 Android 设备经公网 HTTPS 登录和同步，认证后的 `/v1/ws` 建立 WebSocket 连接并传递变更通知。

`renew --dry-run` 默认不执行 deploy hook，需另外验证 reload，或在支持的版本使用 `--run-deploy-hooks`；演练成功不能记录为自然周期续期已经发生。参见 [Certbot 官方说明](https://eff-certbot.readthedocs.io/en/stable/using.html)。

完成条件：签发、续期演练、reload、公网 HTTPS 和 WSS 分别有实际证据。保留日志时隐藏令牌、密码及个人数据。

### 2.11 验收 Android 真机、双设备和数据迁移

至少准备两台设备，安装同一份最终签名候选，覆盖不同 Android 版本和实际权限状态。当前最低 Android SDK 为 26；应根据最终 APK 再核对支持范围。

| 场景 | 操作和通过条件 |
| --- | --- |
| 首次离线使用 | 不配置服务器，创建并修改任务、项目和计划；重启后数据保留 |
| 离线专注和统计 | 开始、暂停、恢复和结束专注，核对任务关联、用时和统计 |
| 本地备份 | 导出后离线导入新工作区，核对业务内容；原工作区保留，不自动上传 |
| 异常备份 | 导入损坏、版本不支持或超过 50 MiB 的文件；报错且不修改原数据，不留下部分恢复 |
| 专注恢复 | 分别在运行和暂停状态下退出、强制停止、重启手机，再打开应用；会话、计时、通知和统计对应 |
| 权限变化 | 拒绝或撤销通知、使用情况访问和悬浮窗权限；限制说明准确，本地任务仍可使用 |
| 双设备专注 | A 开始专注，B 同步后只能查看，不能暂停或结束 A 的会话，不混入 B 的旧计数 |
| 同步和冲突 | 两设备离线修改后联网，同时修改同一记录，测试删除及引用；结果符合接口契约 |
| 网络和服务故障 | 断网、令牌过期、服务不可用、版本不兼容时仍能本地编辑，待同步内容保留 |
| 两台服务器隔离 | 在两个隔离测试库构造相同用户 ID，切换服务器；数据、令牌、队列和游标不混用，复制上传由用户明确选择 |

测试保存失败或初始化重试时，在可丢弃数据环境使用可复现故障，核对输入保留、错误信息和重试；已有 SQLite 故障测试不能替代真机存储异常的使用体验检查。

旧包 `com.example.planfocus` 到新包的迁移：

1. 取得实际旧 APK，建立测试数据，查明真实可用的导出入口和格式。
2. 当前新包支持 `pactick-workspace`、版本 1、最大 50 MiB。旧包兼容性尚未确认，不能假定改文件名或格式标识即可导入。
3. 格式不兼容时，依据实际旧格式开发转换工具，验证字段、引用、删除记录和未同步修改。
4. 独立安装新包，导入并逐项比较任务、项目、计划、历史和未同步内容。新包不自动取得旧包的 SQLite、设置或凭据。
5. 核验完成前保留旧应用和原备份；连接服务器和上传数据另行由用户选择。

后续同包名、同签名覆盖更新：

1. 安装上一版 `com.example.pactick`，建立本地数据和未同步修改。
2. 用相同正式证书、更高 Android 构建号的候选覆盖安装，核对数据、设置和待同步内容保留。
3. 签名不一致时先查证书，不先卸载持有唯一数据的应用；备份恢复方案必须先验证。
4. 没有上一版正式同签名制品时，可做受控模拟更新，并明确记录其性质。保留本次正式制品，作为以后更新测试基线。

完成条件：各场景记录 APK 哈希、设备型号、Android 版本、操作和结果。旧包格式未知或转换未验证时，迁移仍为未完成。备份行为详见 [本地备份与迁移](LOCAL_BACKUPS.md)。

### 2.12 更新验收状态并实际发布

1. 核对资料与实际界面。“设置 → 关于 Pactick”直接打开许可页；第三方文档已按该入口更新。
2. 为本次候选编写验收记录，列明提交、APK 哈希、版本、环境、日期、日志和未验证事项，不把本地测试写成真实环境验收。
3. 如果改变源码预览、APK 和自部署推荐的发布顺序，同步修改 [发行流程](RELEASING.md) 的条件。
4. 最终修改后重新生成快照。影响 APK 的修改重新构建和核验，校验值针对最终上传的同一文件。
5. 公开已审阅的干净仓库，发布 APK、对应源码、SHA-256、证书指纹、第三方声明和变更说明。
6. 从公开页面重新下载制品，核对校验值并测试安装。说明客户端使用外部浏览器打开发布页，不自动校验 APK 完整性或签名证书。
7. 个人旧服务器停用另行安排，仅在个人数据迁移和恢复验证完成后执行。

完成条件：公开制品与验收对象一致，对应源码及反馈入口可访问，发布说明准确反映当前功能和限制。

## 3. 社交媒体宣发准备

宣发工作在上一节的发行要求之外增加普通用户资料、素材和维护安排。首轮建议面向中文 Android 用户，以自然发布和自愿试用为主；付费推广、应用商店上架及海外推广另行评估。当前路线图不包含首版应用商店上架。

### 3.1 明确受众和产品介绍

优先面向两类读者：

- 希望将任务、日历排期和专注记录结合使用的 Android 用户。
- 关心本地数据、源码和自托管同步的开发者及工具爱好者。

面向普通用户说明如何使用，技术社区再介绍实现和部署。各平台统一使用 Pactick 名称，并准确标注 Android 预览版、无需账号的本地使用、可选自托管同步及 Source Available 许可。同步需要用户自己的服务器，维护者不提供公共同步服务；其他客户端平台不在首版范围。

产品内容围绕“创建任务 → 日历排期 → 专注执行 → 查看实际用时”组织。已实现但未完成真机验收的行为需说明状态；不承诺没有验证的兼容性、效果或维护期限。

完成条件：账号简介、视频、图文、下载页和 FAQ 对产品名称、功能范围、版本及许可的描述一致。

### 3.2 补齐普通用户入门和数据说明

已新增 [Android 入门指南](GETTING_STARTED.md)，按当前界面说明首次操作、数据和权限，包含以下内容；公开宣发前仍须用实际候选由测试者验证：

- 官方下载入口、当前版本和制品核对方法。
- APK 安装步骤、Android 提示及常见安装失败处理。
- 首次创建任务、安排时间、开始专注和查看统计的操作。
- 数据保存位置、备份导出、恢复、换手机及卸载前的处理。
- 普通模式和守护模式的区别。
- 使用情况访问、悬浮窗和通知权限的用途，以及拒绝后的限制。
- 本地使用与自托管同步的区别，首次使用是否需要服务器。
- 已知问题、适用范围、维护方式和反馈入口。

当前实现使用使用情况访问识别前台应用，悬浮窗显示守护提醒，专注前台服务显示常驻通知；权限说明应针对最终候选核对。备份是未加密的业务数据文件，不应用真实文件演示公开反馈。

新增公开文档要加入 `scripts/prepare_public_source.py` 的允许列表。完成条件：未参与开发的测试者仅凭指南能够下载安装、完成首次操作并导出备份。

### 3.3 建立统一且可更新的下载入口

各平台指向同一项目入口，至少提供当前版本、发布日期、支持范围、APK、对应源码、SHA-256、证书指纹、入门指南、已知问题、更新记录和反馈方式。

初期可使用正式仓库及 Releases，之后再决定是否增加介绍网站。用国内手机网络实际测试访问、下载和安装。确实需要镜像时，镜像提供相同 APK、对应源码和校验值，并明确版本；更新后核对各入口，避免旧帖子中的不同包长期并存。

完成条件：用户从任一宣发内容进入后，都能识别当前正式入口和版本，下载到可核验的同一制品。

### 3.4 统一账号和视觉资料

准备统一产品名、头像、简介、联系入口，尽量保持各平台名称一致。简介注明作者或维护者身份，区分官方账号和转载账号。注册后启用双重验证，妥善保存恢复方式。

为转载者或评测者准备资料包：图标、产品简介、截图、下载地址、当前限制和素材转载条件。授权条件须由有权处理这些素材的人确认。

完成条件：账号归属清楚，视觉资料来源明确，账号访问和恢复方式由维护者掌握。

### 3.5 制作真实演示素材

首批素材建议如下，数量和时长是制作建议，不是平台硬性要求：

| 素材 | 建议内容 |
| --- | --- |
| 五至六张截图 | 任务、日历、专注、统计、备份，以及亮色和深色界面 |
| 30–60 秒竖屏视频 | 一个具体操作流程及结果 |
| 3–5 分钟横屏视频 | 首次使用、核心功能和当前限制 |
| 图文介绍 | 使用场景、操作步骤和适用人群 |
| FAQ | 安装、权限、备份、同步、许可和反馈 |

每段视频只讲清一个场景，界面文字需在手机上可读。使用演示数据，关闭私人通知；截图和录屏来自实际候选版本，概念设计图标明状态。配乐、字体和其他素材应有适当使用权。

完成条件：素材可追溯到候选版本，画面无私人信息，内容和当前功能一致，横屏及竖屏版本均可阅读。

### 3.6 按平台安排内容

以下为内容分工建议，不代表相关平台保证流量或接受全部外链。发布前仍需核对账号和社区的当前规则。

| 平台 | 建议内容 |
| --- | --- |
| B站 | 完整操作演示、开发过程和版本更新 |
| 小红书 | 每日排期、专注或复盘等具体场景的图文及短视频 |
| 抖音、快手、视频号 | 一次操作及结果的短视频，保持界面文字清晰 |
| 知乎 | 产品解决的问题、本地使用和同步方式，配操作实例 |
| 微博 | 发布通知、更新摘要和短演示，置顶当前入口 |
| 微信公众号 | 入门指南、FAQ 和更新说明，便于反复查阅 |
| 酷安等 Android 社区 | 安装体验、权限说明、设备兼容和测试反馈 |
| 掘金、V2EX 等技术社区 | Flutter/Go 实现、本地存储、同步设计和部署实践 |
| YouTube、X、Reddit 等海外平台 | 具备英文介绍、安装指南和反馈能力后安排 |

首轮建议选择一个演示平台和一个反馈社区，例如 B站加 Android 社区。内容及维护流程稳定后，再扩展平台。不同平台调整篇幅、画面和主题，不机械复制整篇推广内容。

### 3.7 核对平台发布规则

外链、二维码、商业合作、账号认证和内容标注规则会变化，应在发布当天检查平台规则中心和当前账号功能。

- 以作者身份介绍产品，功能和体验以实际演示为依据。小红书当前公约强调真实分享，并建议说明 AI 对内容创作的参与，见 [小红书社区公约](https://pgy.xiaohongshu.com/help/detail?id=1eda0a065dd894063c2e029a49e8f6a1&userType=4)。
- 知乎内容应对问题或主题提供实际帮助，避免重复推广和答非所问，见 [知乎创作者手册](https://www.zhihu.com/knowledge-plan/manual)。
- B站投稿按 [社区公约](https://member.bilibili.com/studio/convention/) 和实际投稿要求处理。
- 海外社区先检查具体社区是否接受作者推广。Reddit 对重复群发和未经请求的批量互动有限制，见 [Reddit Spam 规则](https://support.reddithelp.com/hc/en-us/articles/360043504051-Spam)。

外链受限时使用平台允许的发布方式，不用变形链接或批量私信绕过限制。邀请评测者时保留其独立评价，不要求统一好评；付费或其他合作按平台适用规则披露。

以上规则链接核对日期为 2026-10-01，不能替代发布当天的检查。完成条件：各平台投稿、下载引导和合作标注符合实际账号适用规则。

### 3.8 小范围试用与公开发布节奏

各阶段以完成条件推进，验收未通过时顺延，不提前承诺固定公开日期。

| 阶段 | 操作 | 进入下一阶段的条件 |
| --- | --- | --- |
| 准备 | 完成入口、入门指南、素材和反馈渠道，继续发行验收 | 信息一致，候选和测试范围明确 |
| 小范围试用 | 自愿邀请约 10–20 位测试者，覆盖不同手机和 Android 版本 | 安装、首次使用、备份及重点场景得到反馈 |
| 修正 | 优先处理安装失败、权限困惑、操作困难和数据问题，更新指南 | 关键阻碍修复并复验 |
| 公开发布 | 满足发行要求后发布预览说明和完整演示，再逐步发布不同主题内容 | 公开下载和反馈流程可用 |
| 持续更新 | 汇总常见问题，发布修复、版本变化和新增验证结果 | 能持续处理反馈和维护资料 |

10–20 人是建议试用规模，不是统计可靠性保证。邀请说明版本、预览状态、需测试内容、反馈方式和引用反馈的处理；公开引用用户评价或截图前取得同意。

### 3.9 宣发后的反馈和维护

发布前准备反馈模板，收集应用版本、手机型号、Android 版本、复现步骤、预期与实际结果、必要截图。提醒用户不在公开反馈中提交真实备份、令牌、数据库或私人服务器信息；安全问题通过私下入口报告。

优先观察：

- 用户是否找到入口并成功安装。
- 是否完成首次任务创建和专注。
- 权限、同步方式或说明中哪些内容反复造成困惑。
- 哪些问题重复出现，哪些修复最急迫。
- 测试者是否愿意继续使用，以及其主动反馈的原因。

使用平台自带统计和用户自愿反馈，不为宣发默认加入收集任务内容的追踪功能。没有应用内统计时，不能把反馈估计写成精确留存率。

准备持续更新的已知问题说明，按能投入的时间安排评论和问题处理。数据丢失与安全问题优先，其次核心功能缺陷、易用性和新功能；不承诺没有维护资源支持的固定响应时间。

完成条件：反馈有明确去向，常见问题和已知限制可查，后续版本修复能与公开记录对应。

## 4. 交付物与待办跟踪

### 发布验收

- [x] 正式许可条款与署名已确认，根目录与客户端许可一致（2026-10-02；第三方兼容性另行审阅）。
- [x] 当前源码与 `0.2.0-preview.1+4` APK 的素材来源及许可通知已核对（2026-10-02；主图标为现有生成图案，通知图标为官方 Material timer；历史素材不分发）。
- [ ] 正式仓库、Issues、私下安全报告和 Releases 入口可用。
- [ ] 最终源码 manifest、人工隐私审阅及 Git 文件集一致。
- [x] 六个 PostgreSQL 顶层测试真实 PASS，远端 Checks 通过（2026-10-04；本轮真实数据库日志通过，远端 CI 由维护者确认）。
- [x] 正式签名候选完成构建，源码、版本、哈希和证书对应（2026-10-02；`+4`，手机验收另行记录）。
- [x] 本次 APK 的原生依赖、许可及 NOTICE 完成限定范围的条款和分发通知审阅（2026-10-02；105 条组件、75 个模块、74 个二进制；不构成专业法律意见）。
- [ ] Linux 干净安装、带数据升级和失败处理通过。
- [ ] 真实备份、隔离恢复及新主机恢复通过（2026-10-04 合成数据的真实备份和隔离恢复已通过；新主机完整恢复待验证）。
- [ ] HTTPS 签发、续期演练、reload 和公网 WSS 通过。
- [ ] Android 离线使用、专注恢复和故障场景全部通过；本轮仅记录已执行范围，其余子项未在本次补充说明中逐项确认。
- [x] 双设备验收通过（2026-10-04，维护者实测确认）。
- [x] 长期后台验收通过（2026-10-04，维护者实测确认）。
- [x] 实际通知展示通过（2026-10-04，维护者实测确认）。
- [x] 覆盖升级验收通过（2026-10-04，维护者实测确认）。
- [ ] 改名前旧包迁移得到实际验证；覆盖升级不替代不同包名应用之间的迁移检查。
- [ ] 文档状态、变更说明和最终上传制品重新核对。

### 宣发准备

- [ ] 产品介绍、受众、首轮平台和维护能力明确。
- [ ] 官方入口、入门指南、数据与权限说明、FAQ 可用。
- [ ] 官方账号、头像、简介、双重验证和恢复方式完成配置。
- [ ] 截图、横竖屏视频、图文和可转载资料包完成制作。
- [ ] 发布当天的平台规则、外链和合作标注已核对。
- [ ] 小范围试用、反馈处理和关键问题复验完成。
- [ ] 已知问题、反馈模板和后续维护安排可用。

每项完成时填写日期、责任人、对应提交或 APK 哈希、证据位置和剩余限制。公开文档只保留适合公开的信息；密钥、真实备份、个人日志和私人部署配置保存在受保护位置。

2026-10-02 的 `+4` 候选记录保存在维护目录 `output/license-review-20261002/candidate/`，独立许可履约结果为 `DISTRIBUTION_REVIEW.json`，发行摘要为 `RELEASE_CANDIDATE.md`。对应 APK SHA-256 为 `33f62ce1f93a041ab3ad80befd033c7c40842a4cef9003259dcb323abaef5e40`，本地允许列表来源提交为 `8cbe0d42c94da33d4a260bcc081c3ac5b9e243a7`，未推送远端。该维护状态在制品生成后更新，不改变已封存源码归档和其 manifest；候选包含自身的独立最终记录。
