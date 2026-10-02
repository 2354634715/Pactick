# Windows 本机创建和备份 Android 签名密钥

本文用于首次创建 Pactick 预览 APK 的长期签名密钥。维护者在自己的 PowerShell 中执行，密码只在本机输入，不通过聊天或公开日志提供。前置条件为已安装 JDK；Android 构建另需 Flutter 和 Android SDK，版本要求见 [构建文档](BUILDING.md)。

首轮从 Releases 直接分发 APK。这里创建的密钥用于实际 APK 签名，与以后采用 Google Play App Signing 时的上传密钥不同。直接分发的覆盖更新应保留兼容的签名；重新生成同名文件不能恢复旧密钥。原理见 [Android 应用签名说明](https://developer.android.com/studio/publish/app-signing)。

## 1. 创建密钥

在自己的 PowerShell 中执行，运行目录不限：

```powershell
Get-Command keytool.exe
$signingDir = Join-Path $env:LOCALAPPDATA 'Pactick\signing'
$keystorePath = Join-Path $signingDir 'pactick-release.jks'
if (Test-Path -LiteralPath $keystorePath) {
    throw '目标密钥已存在，请先核对已有密钥，不要重新生成。'
}
New-Item -ItemType Directory -Path $signingDir -Force | Out-Null
keytool.exe -genkeypair -v -keystore $keystorePath -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias pactick -dname 'CN=Pactick'
```

`keytool` 随 JDK 提供。找不到命令时，找到正在使用的 JDK 的 `bin/keytool.exe`，用 `& '实际完整路径'` 替换命令开头。若上一条命令失败，应处理错误后再继续。

命令创建 JKS 格式的 RSA 2048 位私钥，自签名证书有效期为 10000 天，别名为 `pactick`。证书名称使用 `Pactick`，不需要身份证号或家庭地址；证书信息会随 APK 公开。参数依据 [Flutter Android 签名文档](https://docs.flutter.dev/deployment/android#sign-the-app)，实际格式由 `-storetype JKS` 指定。

按提示输入并确认 keystore 密码，再处理私钥密码提示。首次配置可按提示回车，让两者相同。使用密码管理器生成并保存随机密码；不要将密码写入命令的 `-storepass` 或 `-keypass` 参数，以免进入命令历史。后续 `key.properties` 必须与实际密码一致。

创建后核对文件和证书：

```powershell
keytool.exe -list -v -keystore $keystorePath -alias pactick
Get-FileHash -LiteralPath $keystorePath -Algorithm SHA256
```

`keytool` 应能用保存的密码打开密钥，条目应为私钥条目。记录别名、证书 SHA-256 指纹和有效期。密钥文件哈希用于核对备份，证书指纹用于核对 APK，两者不同。

## 2. 验证独立备份

至少保存一份独立于开发机磁盘的受保护副本，例如加密移动介质；密码保存在密码管理器中，并确认其恢复方式。只保留在 `%LOCALAPPDATA%` 的文件不能应对电脑重装或磁盘损坏。

复制完成后，对备份执行 `Get-FileHash`，与原文件哈希比较，再用 `keytool -list -v -keystore '备份文件实际路径' -alias pactick` 验证能够打开且证书指纹相同。备份记录保存日期、别名、证书指纹和位置，密码不进入公开发行记录。

不要覆盖已有密钥备份。正式使用后若遗失密钥或密码，直接分发的同签名更新可能无法继续；不能先卸载持有唯一数据副本的应用来解决签名问题。

## 3. 配置源码副本

维护者可在自己的交互式终端中运行本机配置脚本，运行目录不限：

```powershell
python scripts/configure_android_signing.py --keystore $keystorePath --keytool 'JDK的实际目录/bin/keytool.exe'
```

上例假定运行目录为项目根目录；在其他目录运行时，使用脚本的绝对路径。脚本默认向所在项目的 `client/android/key.properties` 写入配置。使用 `--root '已审阅副本的根目录'` 可指定副本。脚本隐藏密码输入，以子进程环境变量传递给 `keytool`，通过生成并丢弃证书请求验证别名和私钥密码，再按 Java properties 规则转义写入配置。私钥密码提示处回车表示使用 keystore 密码。

目标文件已经存在、密钥或密码不匹配、终端不能交互时，脚本失败且不覆盖已有文件。Windows 文件访问权限由目标目录的权限继承；该文件含明文密码，只能保存在受保护的本机目录。将配置复制到构建副本时，先归档源码，并在复制前确认副本没有已有签名配置。

不使用脚本时，可按下面的步骤手动填写。

先按 [发行流程](RELEASING.md)生成并审阅干净源码副本。确认目标没有已有配置后，在该副本根目录执行：

```powershell
if (Test-Path -LiteralPath 'client\android\key.properties') {
    throw '已有签名配置，请先核对，不用模板覆盖。'
}
Copy-Item -LiteralPath 'client\android\key.properties.example' -Destination 'client\android\key.properties'
```

用本机编辑器填写四项：

```properties
storeFile=密钥文件的实际绝对路径
storePassword=实际的keystore密码
keyAlias=pactick
keyPassword=实际的私钥密码
```

`storeFile` 可使用正斜杠，例如 `D:/private-signing/pactick-release.jks`；这里只示例路径写法。环境变量不会在 Java properties 文件中展开，必须填写真实路径。反斜杠写为 `\\`；密码中的反斜杠、开头空格和非 ASCII 字符等也须按 Java properties 规则转义。密码不匹配时检查输入和转义，不能通过生成新密钥处理。

当前 Gradle 已配置 release 签名，不需要修改 `build.gradle.kts`。缺少四项配置中的任一项时 release 任务失败，不会改用 debug 证书。`key.properties` 含明文密码，keystore 和该文件都不得提交或进入普通源码归档；公开源码工具排除这些文件。

Windows 路径包含 `&` 等特殊字符时，使用不含这些字符的独立构建目录。源码归档应在加入私有签名配置和构建文件前生成。

## 4. 构建与核对

在审阅过的副本的 `client` 目录依次执行；每一步通过后再执行下一步：

```powershell
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build apk --release --dart-define=RELEASES_URL=https://github.com/2354634715/Pactick/releases
```

输出为该副本的 `client/build/app/outputs/flutter-apk/app-release.apk`。在 Android SDK 的实际 `build-tools/版本/` 目录找到 `apksigner.bat`，执行：

```powershell
& 'apksigner.bat的实际完整路径' verify --verbose --print-certs 'APK的实际完整路径'
Get-FileHash -LiteralPath 'APK的实际完整路径' -Algorithm SHA256
```

签名校验必须成功，APK 证书 SHA-256 指纹应与 `keytool` 输出一致。APK 哈希、证书指纹、对应源码版本和构建环境进入候选记录。通知、数据库、真机、备份恢复和多设备检查仍分别执行，不能仅凭构建成功公开分发。

GitHub 候选构建需把这把密钥及相应密码配置到受保护的 `android-release` 环境，变量名见 [发行流程](RELEASING.md)。不要在 Issues、普通 PR 或聊天中上传密钥。GUI 修改完成后重新构建最终候选并验收。
