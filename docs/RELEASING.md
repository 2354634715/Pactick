# 发布源码与 Android 候选包

首轮发行范围为源码预览和 Android 预览 APK，暂不推荐公网自部署。官方仓库为 [2354634715/Pactick](https://github.com/2354634715/Pactick)，APK 与对应源码使用该仓库的 [Releases](https://github.com/2354634715/Pactick/releases) 分发，安全报告入口见 [SECURITY.md](../SECURITY.md)。2026-10-04 的仓库查询结果仍为私有，维护者访问已核对；本轮没有验收公开入口及邮箱收件。

源码预览、APK 下载和自部署推荐按文末各自的完成条件推进。公开源码时须列明真实数据库、APK、真机和部署的未验证事项；源码公开不代表这些验收已经完成。

2026-10-04 已补做真实 PostgreSQL 集成和合成数据的真实备份／隔离恢复；维护者另行确认覆盖升级、双设备、长期后台、实际通知展示和远端 CI 均通过，公网部署尚未完成。结果来源与本轮检查范围见 [最终检查记录](FINAL_CHECK_20261004.md)。其他组合验收项按其全部完成条件记录，不将本轮没有执行的检查视为维护者尚未完成。

## 1. 审核公开源码

1. 更新 `CHANGELOG.md`、客户端版本与版本号，确认数据库迁移兼容旧版。
2. 更新 [第三方声明](../THIRD_PARTY_NOTICES.md)，处理 [核查清单](THIRD_PARTY_AUDIT.md) 中尚未完成的事项。
3. 运行 `python3 scripts/prepare_public_source.py NEW_DIRECTORY`，人工审阅 `SOURCE_MANIFEST.json` 所列全部内容。
4. 在新目录执行 [完整构建检查](BUILDING.md)，确认构建不依赖原私有工作目录中的文件或配置。
5. 公开前确认项目许可正文与版权归属、官方仓库地址、私下安全报告入口和发布页面。旧部署和商业化历史资料留在原私人目录中。

不得先上传整个旧工作目录，再依赖 `.gitignore` 排除私有资料。新增 ignore 规则不会从 Git 历史中移除已跟踪文件。

## 2. 配置签名环境

首次创建密钥的维护者先按 [Windows 本机签名指南](ANDROID_SIGNING.md)在自己电脑上生成并验证备份，密钥和密码不通过聊天或公开仓库提供。

在实际发行仓库创建 GitHub Environment `android-release`，限制到默认分支、设置所需审核人，并在该环境中设置：

| Secret | 内容 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | 稳定的正式 keystore 文件的 Base64 |
| `ANDROID_STORE_PASSWORD` | keystore 密码 |
| `ANDROID_KEY_ALIAS` | 正式签名 key alias |
| `ANDROID_KEY_PASSWORD` | key 密码 |

维护者须在独立、受保护的位置备份密钥。不得提交到仓库、issue、日志、源码快照或普通 PR 环境。不得随意重建现有应用的正式密钥；重建密钥可能导致签名不一致。

普通 `.github/workflows/checks.yml` 执行 Go 检查和 Flutter analyze/test/debug build；PR 不使用签名密钥。`.github/workflows/android-release.yml` 只能从默认分支手动触发，使用已有版本标签，并在环境审核通过后构建签名候选包。维护者必须先审阅标签所指的源码及构建脚本。GitHub 手动触发规则见 [官方文档](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)。

## 3. 生成候选制品

为已通过检查的提交创建版本标签，例如 `v0.2.0-preview.1`。从默认分支手动运行 **Build signed Android candidate**，输入该标签。

工作流检出标签后生成允许列表快照。`verify_third_party_notices.py` 检查第三方声明与当前 Go／Dart 锁定版本一致，并核对所列本地许可文本、上游证据和内嵌通知的 SHA-256；缺失文本、陈旧版本或未确认的 Android POM 记录会停止构建。该检查不确认素材使用权或许可兼容性。

注入签名密钥前，`verify_release_source.py` 检查标签与 `client/pubspec.yaml` 中的版本一致（标签不包含 `+buildNumber`）、Android 构建号为正整数、根目录与客户端许可证逐字节相同，并核对 manifest 中所有文件的大小和 SHA-256。Flutter 检查结束后再次验证，使用 `--expected-metadata artifacts/RELEASE_SOURCE.json` 与归档前的来源元数据逐项比较。检查失败时停止，签名步骤不会执行。

源码 tar.gz 在依赖工具和签名配置进入构建目录前生成。Flutter 检查、签名构建和 APK 通知检查均在同一快照中执行；构建后再次核对 manifest 文件及归档前的来源元数据，源文件、锁文件或 manifest 被修改时不上传候选制品。keystore 位于快照外，临时 `key.properties` 不进入预先生成的源码包；工作流退出时清理两者。

生成的 Actions artifact 包含 APK、源码 tar.gz、`SOURCE_COMMIT.txt`、`RELEASE_SOURCE.json`、`SHA256SUMS.txt`、签名证书指纹、工具链版本记录、第三方许可证原文和变更说明。`RELEASE_SOURCE.json` 记录提交、标签、客户端版本、构建号及许可证和 manifest 的哈希。工具链记录包含 Flutter、Dart、Java、Go 和 `apksigner` 的实际版本；依赖锁文件随源码分发。工作流仅上传候选 artifact，不创建公开 Release。

签名构建后，工作流重新解析 `releaseRuntimeClasspath`，检查本次模块坐标与第三方声明及已审阅的补充资产一致，再将本次解析的模块、AAR/JAR 哈希和内嵌 LICENSE/NOTICE 采集到 `android-native-evidence/`，并关联最终 APK 的 SHA-256。`verify_apk_notices.py` 检查项目许可、全部 Flutter 引擎正文及补充资产；`verify_supplemental_notices.py --android-inventory ... --apk ...` 进一步要求本次模块与已审阅列表一致。版本变化、原始文本遗漏或 APK 资产不匹配时，检查失败，不上传候选制品。

采集文件中的 `completed_legal_audit: false` 表示采集器只提供证据。完成条款、归属与项目许可排除关系的审阅后，维护者在独立的 `DISTRIBUTION_REVIEW.json` 中记录适用分发范围、源码提交、最终 APK SHA-256、证书、对应运行时二进制和通知检查结果。该记录只适用于所列制品；依赖、素材或分发范围变化后须重新审阅。没有内嵌文本的 AAR/JAR 仍需核对上游，不能据此省略许可。具体条款与证据要求见 [第三方核查](THIRD_PARTY_AUDIT.md)。

发布前使用 Android SDK 的 `apksigner verify --verbose --print-certs` 检查 APK 签名，将 SHA-256 和证书 SHA-256 指纹放在 Releases 描述中。校验值必须针对最终上传的同一文件。客户端使用外部浏览器打开发布页，不自动验证 APK 完整性或签名证书；发布说明必须准确描述这一限制。

## 4. Android 安装与数据迁移

当前应用标识为 `com.example.pactick`。改名前的 `com.example.planfocus` 与新包使用不同的 Android 数据空间，新包独立安装，不能通过覆盖安装自动取得旧包的 SQLite、设置或凭据。

旧包仍可运行时，先在旧包中导出备份并保留原应用，然后在新包中导入。导入创建独立本地工作区，不带服务器地址、凭据、游标或设备登记，不自动上传。检查任务、项目、计划、专注历史及未同步修改与原数据一致，再另行选择是否连接服务器。备份格式与限制见 [本地备份](LOCAL_BACKUPS.md)。如果旧包没有兼容的导出入口或备份格式不受支持，必须保留旧应用和唯一数据副本，先完成迁移工具与恢复验证；不得将安装新包视为迁移完成。

后续 `com.example.pactick` 版本的覆盖更新须保持包名和正式签名证书相同，并增加 Android 构建号。验收应安装上一版同包名制品、创建本地数据和未同步修改，再覆盖安装候选包，核对数据保留。证书不一致时 Android 通常拒绝覆盖；改用备份恢复前须验证备份，卸载会删除原应用数据。

## 5. 分阶段发布验收

### 源码预览

- [x] 项目所有者确认现有许可条款，根目录与客户端正文一致，署名为“王辰昊 Wang Chenhao”。
- [ ] 公开文件、素材来源及相应第三方通知完成审阅；来源待确认的图标不得记为已通过。
- [ ] 在最终干净快照完成 Go、Flutter、Python 与第三方证据检查，核对 manifest 和实际 Git 文件集。
- [ ] 仓库、Issues、Releases 及私下报告邮箱能够使用，人工核对作者信息和隐私内容。
- [ ] 预览说明列出未验证场景、已知限制和 Source Available 条件，不宣称 APK 或公网部署已验收。

### Android 预览 APK

在源码预览条件之外，完成以下检查。APK 可以晚于源码发布；候选 artifact 通过构建不代表已获准公开分发。

- [ ] Go/Flutter 检查与干净源码构建通过。
- [x] PostgreSQL 集成场景实际执行通过，远端 Checks 通过（2026-10-04；真实数据库测试有本轮日志，远端 CI 由维护者确认）；未配置测试连接而跳过不能记为数据库验收通过。
- [ ] 真机首次启动、离线任务/专注/统计、备份导出与恢复正常。
- [ ] 改名前旧包到 `com.example.pactick` 的独立安装、导出与恢复迁移通过；原应用和备份在核验完成前保留。
- [x] 覆盖升级验收通过（2026-10-04，维护者实测确认）。以后同包名、同签名的覆盖更新仍须核对数据与未同步修改保留；包名或证书不一致时按备份恢复流程迁移。
- [ ] 两台自部署服务器中相同用户 ID 不混用数据、令牌、同步队列或游标。
- [ ] 断网、令牌过期、服务故障、同步版本不兼容不阻塞本地功能。
- [x] 双设备验收通过（2026-10-04，维护者实测确认）。
- [x] 长期后台验收通过（2026-10-04，维护者实测确认）。
- [x] 实际通知展示通过（2026-10-04，维护者实测确认）。
- [ ] 删除和冲突场景符合契约；本次补充说明未单列这些场景的结果。
- [ ] APK 的对应源码标签、签名证书指纹、SHA-256 和第三方声明齐备。
- [ ] Android 实际运行时依赖与内嵌许可、字体和图标来源完成审阅。
- [ ] 正式仓库 URL、Releases 入口、私下漏洞报告地址已经配置并验证。
- [ ] 所有公开文件和图片经过人工隐私审阅。

各阶段条件满足后，由维护者公开相应源码或制品。入门操作与当前限制见 [Android 入门指南](GETTING_STARTED.md)，素材证据见 [素材来源核对](ASSET_SOURCES.md)。

### 自部署推荐

首轮不承诺公网部署已经可推荐使用。以后增加该范围前，须在真实 Ubuntu/Debian 环境完成干净安装、带数据升级、失败处理、定时备份、隔离恢复及新主机恢复；HTTPS 模式另需证书签发、续期演练、reload 和公网 HTTPS/WSS 的实际结果。操作与完成条件见 [发布验收计划](RELEASE_AND_PROMOTION_PLAN.md)。客户端双设备及服务器隔离检查仍是上列 APK 验收的一部分。

个人服务器停用另行安排，必须在个人数据迁移完成、恢复验证通过后执行。

