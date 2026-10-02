# Pactick Android 客户端

客户端使用 Flutter 和 Material 3，提供任务、日历、专注与统计功能。首次使用进入本地工作区，无需连接服务器；需要多设备同步时，在设置中配置自己的 HTTPS 服务端并登录。

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

关于页通过外部浏览器打开构建时配置的 Releases 页面。首次公开前需填写实际官方仓库地址。第三方声明见 [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)，正式发行验收要求见 [RELEASING.md](../docs/RELEASING.md)。

项目采用 Source Available 许可，具体范围见 [LICENSE](../LICENSE) 与 [FAQ](../docs/LICENSE_FAQ.md)。
