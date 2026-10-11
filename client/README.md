# Pactick Android 客户端

客户端使用 Flutter 和 Material 3，提供任务、日历、专注与统计功能。首次使用进入本地工作区，无需连接服务器；需要多设备同步时，在设置中配置自己的 HTTPS 服务端并登录。

当前源码版本为 `0.3.0-preview.1+6`。通用任务列表默认按“紧急 → 高 → 中 → 低 → 无”排列，同优先级按 `rank` 升序、任务 ID 固定顺序排列；“今日”继续使用当天排期和手动顺序。

Android 任务温馨提醒默认开启。有未完成任务且系统允许通知时，通知栏显示一条静默提醒，只包含待办数量；数量变化更新同一条通知，全部完成或关闭开关后移除。点击通知打开任务页，在“设置 → 任务提醒”管理开关和通知权限。提醒开关保存在本机，不随同步或备份迁移。按截止时间和日历时段的提醒、私密任务箱仍未实现。操作和系统限制见 [入门指南](../docs/GETTING_STARTED.md#任务温馨提醒)，真机检查见 [验收清单](../docs/ANDROID_TASK_REMINDER_CHECKLIST.md)。

## 开发

在仓库的 `client` 目录运行：

```sh
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build apk --debug
```

上述命令按锁文件获取依赖、执行静态检查和测试，并构建 debug APK。输出为 `build/app/outputs/flutter-apk/app-debug.apk`，相对于客户端目录。

工具链、依赖版本与正式签名要求见 [构建说明](../docs/BUILDING.md)。本地开发需要 HTTP 连接时，应使用项目提供的调试选项；正式自部署地址使用 HTTPS。

## 数据与迁移

本地使用不依赖维护者服务器。切换服务器或账号时，工作区、令牌和同步状态按服务器及账号分别管理。退出账号保留本地数据；删除服务器数据与删除本机副本是不同操作。

更换签名或重装前，应导出备份并验证恢复。正式包必须使用稳定的生产证书，签名配置参照 `android/key.properties.example`。密钥、密码、`key.properties` 和 `local.properties` 不得包含在源码发行包中。

## 发布与许可

关于页通过外部浏览器打开构建时配置的 `RELEASES_URL`；未配置时该入口不可用，需查阅分发者说明。仓库地址已确定为 `2354634715/Pactick`，公开前仍需验证入口和构建参数。第三方声明见 [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)，正式发行验收要求见 [RELEASING.md](../docs/RELEASING.md)。

项目采用 Source Available 许可，具体范围见 [LICENSE](../LICENSE) 与 [FAQ](../docs/LICENSE_FAQ.md)。
