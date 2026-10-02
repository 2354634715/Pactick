# 第三方许可审阅与发行通知核查

核查日期：2026-10-02。当前源码版本为 `0.2.0-preview.1+4`。本轮分发范围为公开源码预览和 Android 预览 APK，不分发完整 SDK、构建工具分发包、依赖缓存、设计预览、测试截图或服务器容器镜像。

本轮已完成所列第三方许可正文、分发条件、项目定制许可及通知实现的源码审阅。新的签名候选仍须通过最终 APK 检查；源码审阅结果不能代替制品和真机入口验证。此项为限定范围的许可履约检查，不构成全部权利归属、商标可用性或专利状况的专业法律保证。

## 证据与状态

| 记录 | 作用与限制 |
| --- | --- |
| `THIRD_PARTY_NOTICES.json`、`third_party/licenses/` | 根据 Go/Dart 依赖清单及本地证据记录版本、原始 LICENSE/NOTICE 与 SHA-256；生成器的自动许可分类仅供索引 |
| `artifacts/android-runtime-dependencies.json` | 对本次 `releaseRuntimeClasspath` 解析模块坐标和外部二进制，原始路径属于构建机信息，不随源码分发 |
| `ANDROID_NATIVE_EVIDENCE.json` | 采集实际 AAR/JAR 的哈希与内嵌通知，绑定本次 APK；没有内嵌文本的模块仍须核对上游 |
| [`third_party/metadata/distribution-notices.json`](../third_party/metadata/distribution-notices.json) | 记录已审阅补充通知、依赖声明及通知原文的哈希，当前状态为 `source-reviewed-final-apk-check-required` |
| [`client/assets/licenses/supplemental.json`](../client/assets/licenses/supplemental.json) | 供客户端读取的完整补充通知，包含原生组件、字体、数据、素材归属和必要鸣谢 |
| `DISTRIBUTION_REVIEW.json` | 每次候选的独立发行审阅记录；维护者完成制品检查后绑定最终 APK、源码及依赖证据，明确记录完成范围和未验证事项 |

采集器的 `completed_legal_audit` 固定为 false：它不执行最终分发义务审阅，也不因某次候选通过而自动改变。该字段不代表维护者必须永久保留“未审阅”结论。发行履约状态由独立的 `DISTRIBUTION_REVIEW.json` 记录，只有其所绑定的制品适用；依赖、许可、素材或通知变更后须重新审阅。

本轮维护机上的详细记录保存在 `output/license-review-20261002/`。组件审阅以原候选的 103 条记录为基础，另补充 CLDR 48 数据和官方 timer 素材来源；Android 模块按实际运行时图单独核对。这些过程记录不全部进入公开源码，公开材料以本次 `SOURCE_MANIFEST.json` 为准。

## 条款审阅结论

项目 [LICENSE](../LICENSE) 将 Pactick 原创代码、文档和素材与单独标识的第三方材料区分。第三方组件继续按原有许可使用，Pactick 的商业限制不扩大到这些组件、图标字体和数据。已审阅运行时条款没有要求将整个 Pactick 改用 GPL、LGPL 或 MPL。Apache-2.0 允许整体作品或修改采用其他条款，前提是继续履行原组件的许可、通知和修改说明要求。[Apache-2.0 原文](https://www.apache.org/licenses/LICENSE-2.0)

| 许可或组件 | 本次分发条件和处理 |
| --- | --- |
| MIT、BSD-2-Clause、BSD-3-Clause | 保留适用版权、授权条件与免责；BSD-3-Clause 另禁止未经授权使用权利人或贡献者姓名暗示背书 |
| Apache-2.0 | 保留完整正文、适用版权/专利/归属通知及上游 NOTICE；修改第三方文件时声明变更；不得以项目许可替换原组件许可 |
| Go `gopkg.in/yaml.v3` | 部分从 libyaml 移植的文件适用 MIT，其余适用 Apache-2.0；两类声明及 Canonical NOTICE 同时保留，不是任选一种覆盖全部文件 |
| Flutter MaterialIcons 字体 | SDK 实际附带 CC BY 4.0；保留 Google 署名、字体包来源、全文、免责及 Flutter 删除未用字形的说明 |
| Google Material `timer` SVG | 固定提交的素材采用 Apache-2.0；保留来源、原始 SVG、许可及转换为白色 Android vector 的日期和说明 |
| intl 的 CLDR 48 派生数据 | 单独保留准确的 Unicode-3.0 版权与许可通知，不以 Dart 包根目录 BSD 或引擎中其他年份的 Unicode 声明代替 |
| FreeType、libjpeg-turbo/IJG | 引擎保留原许可；补充通知提供 FreeType Team 和 Independent JPEG Group 的肯定性鸣谢 |
| 原生 jsr305、Kotlin 及相关子材料 | 保留主许可和适用子材料的独立归属、CC BY、BSD、Boost 等原文，不能仅采用 Maven POM 的许可名称 |

CC BY 要求署名、来源、许可和修改说明，并禁止妨碍素材原许可权利的额外限制。当前字体沿用实际 SDK 版本的 CC BY 4.0；官方 timer 的独立 SVG 采用其固定提交中的 Apache-2.0，两者不得混同。[CC BY 4.0 原文](https://creativecommons.org/licenses/by/4.0/legalcode.en)

FreeType 沿用引擎所保留的 FTL 途径，并提供肯定性鸣谢；没有选用其 GPL 替代许可。[FreeType 官方许可说明](https://freetype.org/license.html) IJG 的二进制分发要求在产品文档中明确鸣谢，展示上游“应当鸣谢”的条文本身不能替代产品声明。[libjpeg-turbo 官方说明](https://github.com/libjpeg-turbo/libjpeg-turbo/blob/main/LICENSE.md)

Flutter 引擎完整聚合声明还包含其他平台、测试和开发工具；保留全部 1593 段通知不表示每项均链接进入 Android APK。Go 服务端不进入 APK。Dart 锁文件包含开发依赖和其他平台实现，许可通知的出现也不证明该组件在 Android 上运行。

## Gradle wrapper 与独立工具

仓库内 `gradle-wrapper.jar` 的哈希对应官方 Gradle 2.10 wrapper，JAR 只包含 wrapper 和 CLI 类；`gradle-wrapper.properties` 配置其下载 Gradle 9.4.1。两者版本分别记录在 [`gradle-wrapper.json`](../third_party/metadata/gradle-wrapper.json)，准确的 [LICENSE](../third_party/gradle-wrapper/LICENSE) 和 [NOTICE](../third_party/gradle-wrapper/NOTICE)随源码保留。[Gradle 官方校验表](https://gradle.org/release-checksums/)

完整 Gradle 分发的许可文本包含独立工具的 LGPL、MPL、CDDL、EPL 等条款。这些工具不在已核对的 wrapper/CLI JAR 中，也不作为 Android 客户端分发。首轮不分发完整 Gradle、Flutter、Dart、Go 或 JDK；未来改变此范围时，应单独核对实际工具分发包。容器基础镜像同样不属于本轮发行审阅范围。

## 客户端通知的打包与入口

Flutter 的 `LicenseCollector` 遍历 `package_config.json` 中各包的 LICENSE/NOTICES，包括 `sky_engine`，合并写入 `assets/flutter_assets/NOTICES.Z`。框架随后将这些文本注册到 `LicenseRegistry`。根目录 LICENSE 的客户端副本保存在 `client/LICENSE`，CI 和 APK 检查要求两份正文一致。

应用启动时调用 `registerSupplementalLicenses()`，只注册一次补充许可读取器。打开“设置 → 关于 Pactick”许可页时，`LicenseRegistry` 才加载 `assets/licenses/supplemental.json` 并生成许可条目；主页面启动不读取该资产。资产 schema 不支持、条目为空或组件名/正文无效时，解析器抛出 `FormatException`，不得把资产缺失或格式错误视为完整许可通知。

当前补充资产共 24 条：18 条原生许可及子材料声明覆盖 71 个非 Flutter 引擎模块，另外 6 条提供第三方独立许可提示、Material 字体、CLDR、FreeType、IJG 和 Google timer。4 个 Flutter 引擎模块由完整引擎声明覆盖，合计与 75 个运行时模块坐标对应。该分组会随依赖变化，应以补充通知的审阅元数据和本次解析图为准。

许可页使用 Flutter [`showLicensePage`](https://api.flutter.dev/flutter/material/showLicensePage.html)。三个补充许可测试覆盖真实资产及必要文本、重复注册去重和无效格式拒绝；它们不代替最终签名 APK 的字节核对或手机许可页检查。

原 `0.2.0-preview.1+3` 签名候选包含项目许可和全部 1593 段引擎正文，但缺少本轮补充通知。该历史结果不能证明新的 `+4` 候选已完成检查，也不能用旧 APK 验收新素材。

## 每次签名构建后的检查

前置条件为：从允许列表生成独立源码快照，在该快照完成 `flutter pub get` 和 release APK 构建，并配置有效 Android SDK。以下命令在构建快照的项目根目录执行。Windows 在 `client/android` 目录使用 `gradlew.bat`，其他平台使用 `./gradlew`。

先解析本次 release 运行时图：

```sh
cd client/android
./gradlew -I ../../scripts/android-dependencies.init.gradle :app:writeRuntimeDependencyInventory
cd ../..
```

任务将完整 schema 2 图及外部二进制路径写入 `artifacts/android-runtime-dependencies.json`，不需要正式签名密钥。解析可能下载依赖；遇到未解析依赖时命令失败，不得使用历史图当作本次成功结果。

然后核对依赖、通知源和最终 APK：

```sh
python3 scripts/verify_third_party_notices.py \
  --android-inventory artifacts/android-runtime-dependencies.json

python3 scripts/verify_supplemental_notices.py \
  --android-inventory artifacts/android-runtime-dependencies.json \
  --apk client/build/app/outputs/flutter-apk/app-release.apk

python3 scripts/verify_apk_notices.py \
  client/build/app/outputs/flutter-apk/app-release.apk
```

`verify_third_party_notices.py` 核对 Go/Dart 锁定版本、必需 SDK/字体/wrapper 记录、原文 SHA-256 和 Android 坐标，拒绝缺失原文、未确认或缺失 POM、越出证据目录的路径。它不重新下载上游 POM，POM 哈希和名称也不能代替实际许可正文。

`verify_supplemental_notices.py` 核对补充资产及各条正文的审阅哈希、Go/Dart 依赖声明、runtime graph、全部 71 个原生模块覆盖、必需原文和肯定性鸣谢。指定 `--apk` 时，还要求 APK 内 `assets/flutter_assets/assets/licenses/supplemental.json` 与源码资产逐字节一致。依赖、模块版本、原文或资产改变时命令失败，应更新采集和审阅记录后重建，不能只更新哈希绕过审阅。

`verify_apk_notices.py` 从 APK 解压 NOTICES.Z，核对完整项目许可、当前 SDK 全部引擎正文，并调用补充通知验证器。默认从 PATH 中的 Flutter SDK 找到 `sky_engine/LICENSE`，可用 `--engine-license PATH` 指定。`--root PATH` 指定补充通知核查的项目根目录，默认使用脚本所在项目；`--project-license PATH` 单独指定待核对的项目许可，默认使用该根目录的 LICENSE，不改变补充资产的位置。任一必需文本或资产缺失时命令失败。

最后采集本次实际原生二进制证据：

```sh
python3 scripts/capture_android_notices.py \
  artifacts/android-runtime-dependencies.json \
  client/build/app/outputs/flutter-apk/app-release.apk \
  artifacts/android-native-evidence
```

目标目录必须不存在。采集器只接受完整 schema 2 release 清单，记录 APK 和实际 AAR/JAR 的 SHA-256，保留归档及一层内嵌 JAR 的 LICENSE/NOTICE，输出中不保留构建机绝对路径。单份通知或内嵌 JAR 超过 64 MiB、二进制缺失或归档无法读取时命令失败；失败目录不能作为完整证据。`no-embedded-text-found-review-upstream` 表示需要上游原文和条款证据，不表示模块没有许可要求。

命令通过后，在独立发行记录中保存 APK 哈希、源码 manifest、版本、依赖图与通知证据。手机还须确认“设置 → 关于 Pactick”能打开列表并读取原生、字体、数据及素材条目。文件检查只能确认打包字节，不能确认实际设备上的入口和可读性。

## 变更依赖或来源后的重新采集

在项目根目录执行生成器，将示例路径替换为实际缓存：

```sh
python3 scripts/generate_third_party_notices.py \
  --go-cache /path/to/go/pkg/mod \
  --pub-cache /path/to/pub-cache \
  --flutter-sdk /path/to/flutter \
  --go-sdk /path/to/go \
  --gradle-cache /path/to/gradle/caches/modules-2/files-2.1 \
  --android-inventory artifacts/android-runtime-dependencies.json
```

没有本次运行时图时可省略最后一个参数，但生成的缓存 POM 状态仍为 `cache-POM-only-not-confirmed-in-app`，不能用于最终分发验收。指定清单时只接受完整 schema 2 `releaseRuntimeClasspath` 图，并要求含有已解析二进制。生成器覆盖索引并更新采集文本，不自动删除旧许可文件；移除组件后按当前索引整理不再使用的证据。

Go `require` 的单行和分组声明均受支持。Dart hosted 来源限于 `https://pub.dev`，SDK 组件单独采集。Go `replace`/`exclude`、Dart git/path 或其他 hosted 来源尚无对应采集逻辑，遇到这些声明时命令失败；引入前必须补充来源采集和版本核对。

POM 许可为空时必须核对父 POM 或上游。当前 `com.google.guava:listenablefuture:1.0` 的 Apache-2.0 声明由已验证的 [父 POM](../third_party/metadata/guava-parent-26.0-android.pom)继承。4 个 Flutter 引擎模块的版本提交 ID 与 SDK `engine.stamp` 一致后映射到完整引擎声明，仍保留“没有直接 POM 声明”状态。以上映射仅确定来源，不替代最终通知检查。

新增许可、上游 NOTICE、素材转换或运行时版本变更后，维护者必须重新审阅适用条款，更新补充资产和 `distribution-notices.json` 的证据，然后执行本次候选的全部检查。素材来源、转换记录及当前分发范围见[客户端素材来源](ASSET_SOURCES.md)。
