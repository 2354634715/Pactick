# 客户端素材来源核对

核对日期：2026-10-02。适用客户端源码：`0.2.0-preview.1+4`。本文记录当前工作目录的素材来源；每次发行仍须核对源码快照和最终签名 APK。来源记录不构成商标可用性结论。

## 核对范围

2026-10-02 的逐项清单保存在维护工作目录 `output/image-sources/{IMAGE_SOURCES.md,image-sources.csv,image-sources.json}`。清单记录了 207 个 PNG 和 79 个 Android 绘制 XML，还单独列出 94 种源码显式引用的 Material 图标、33 种设计预览内联 SVG、截图辅助字体和用户附件。图像与 XML 总数包含历史源码快照及验证附件，不是当前客户端或 APK 的资源数量。

当前客户端使用 13 个 PNG 和 7 个绘制 XML。PNG 均为本次生成前景的派生资源；XML 包括自适应图标配置、启动背景和专注通知图标。设计预览、Flutter 检查截图、生成原图及历史快照不作为客户端资源打包。上述维护工作目录不进入公开源码快照；公开分发的资源范围以本次快照的 `SOURCE_MANIFEST.json` 和最终 APK 为准。

| 用途 | 已确认来源 | 尚需核实的内容 |
| --- | --- | --- |
| Flutter 页面中的操作和导航图标 | Flutter SDK 捆绑的 Google Material Icons，源码显式引用 94 种符号 | 最终 APK 中的字体许可、署名及许可入口 |
| Pactick 主图标及应用内品牌标记 | 维护者确认由 ChatGPT 生成；本轮保留了内置 imagegen 的原图、提示词及派生记录 | 最终分发素材与记录是否一致 |
| Android 原生专注通知和悬浮提醒的小图标 | Google 官方 Material Design Icons 的 `timer`，从固定提交的 SVG 转换为 Android vector | 最终源码与 APK 中的资源及 Apache-2.0 通知是否一致 |

文件哈希用于核对字节变化，作者、使用条件和商标状态仍须依据相应来源及许可。上述逐项清单描述替换通知图标前的库存；其中旧 XML 的待确认标记属于历史记录，当前文件的来源以下节为准。

## Pactick 应用图标

Android 启动图标和应用内品牌标记已替换为本次内置 imagegen 生成的 Pactick 图案，不再使用 Flutter 模板启动图标。生成时没有引用第三方应用图标，也没有使用 Flutter 标识。计划条目和开放折带形成专注窗口；图案保留细微色阶，属于位图素材。

原始透明前景为 1254 × 1254 RGBA。原图、提示词与生成检查记录保存在项目的 `output/pactick-app-icon/` 中；这些工作文件不随客户端或公开源码快照打包。Android 与 Flutter 使用的资源由该图转换尺寸和画布得到。转换没有为图案加入新的绘制元素。生成记录说明来源，不构成独立的授权或商标审查结论。

- `drawable/ic_launcher_foreground.png`：432 × 432 透明前景，对应 108 dp 自适应图标画布。
- `mipmap-anydpi-v26/`：前景和固定 `#F4F5FF` 背景组成 Android 26+ 自适应图标；启动与圆形入口共用图案。
- `drawable/ic_launcher_monochrome.png`：从生成前景 alpha 大于 32 的轮廓转换为单色掩膜，由 `mipmap-anydpi-v33/` 提供给 Android 13+ 主题图标。
- 五档 `mipmap-*/ic_launcher.png` 和 `ic_launcher_round.png`：48、72、96、144、192 像素的兼容资源。
- `assets/branding/pactick_icon.png`：512 × 512 应用内品牌标记，已在 `pubspec.yaml` 声明并加入公开源码的精确允许列表。

图标可辨主体位于 Android 自适应安全区内；原图外围存在极低 alpha 的碎点。资源的尺寸与构建已核验，实际启动器遮罩、主题图标效果和真机显示尚未验证。

| 资源 | 像素尺寸 | SHA-256 |
| --- | --- | --- |
| `client/android/app/src/main/res/mipmap-hdpi/ic_launcher.png` | 72 × 72 | `a9e6dad0ffbd2395328ce27e29c4b26f3076494b1c0b04d0535f5a733d3d3fc6` |
| `client/android/app/src/main/res/mipmap-hdpi/ic_launcher_round.png` | 72 × 72 | `a9e6dad0ffbd2395328ce27e29c4b26f3076494b1c0b04d0535f5a733d3d3fc6` |
| `client/android/app/src/main/res/mipmap-mdpi/ic_launcher.png` | 48 × 48 | `a919c4508be08204369d44c6448e97b73f7fd4c8e2d5d3043043a527d7b592c4` |
| `client/android/app/src/main/res/mipmap-mdpi/ic_launcher_round.png` | 48 × 48 | `a919c4508be08204369d44c6448e97b73f7fd4c8e2d5d3043043a527d7b592c4` |
| `client/android/app/src/main/res/mipmap-xhdpi/ic_launcher.png` | 96 × 96 | `16cad9501090e97ca7d3232c2d1814581ef679016e99f8785e8806ea6fd0a24a` |
| `client/android/app/src/main/res/mipmap-xhdpi/ic_launcher_round.png` | 96 × 96 | `16cad9501090e97ca7d3232c2d1814581ef679016e99f8785e8806ea6fd0a24a` |
| `client/android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png` | 144 × 144 | `a284c3c2c61e146dd2b83ab98f36bab4e572fe29572865e4b822273a113a598c` |
| `client/android/app/src/main/res/mipmap-xxhdpi/ic_launcher_round.png` | 144 × 144 | `a284c3c2c61e146dd2b83ab98f36bab4e572fe29572865e4b822273a113a598c` |
| `client/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png` | 192 × 192 | `3b5b3c21c994288701d7e5dc991dc29940410935fb8d57f0d3a90219e8922e08` |
| `client/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_round.png` | 192 × 192 | `3b5b3c21c994288701d7e5dc991dc29940410935fb8d57f0d3a90219e8922e08` |
| `client/android/app/src/main/res/drawable/ic_launcher_foreground.png` | 432 × 432 | `5dbc26ed5388db79ae2aca82cb4aac18ab717caf1fff8e67ea81dd3d3b65906e` |
| `client/android/app/src/main/res/drawable/ic_launcher_monochrome.png` | 432 × 432 | `9842ea1a3a4d38e91415e5ce262331fadf27be4aaf48b7e261b251e1dbdcaf3d` |
| `client/assets/branding/pactick_icon.png` | 512 × 512 | `472aa862afc3651230394cd3e992dc1532f2fe1423e3bb9b3485c098d4861e0c` |

上述哈希针对当前工作目录字节；后续转换或修改需重新计算。文本配置经过公开快照 LF 规范化后，以快照 `SOURCE_MANIFEST.json` 为准。

## 专注通知图标

`client/android/app/src/main/res/drawable/ic_focus_notification.xml` 使用 Google 官方 Material Design Icons 的 `timer`，上游固定提交为 `737e3324305806514d7909874fa1818ae1808232`。原始 [24px SVG](../third_party/metadata/material-timer/timer.svg)、[来源与哈希记录](../third_party/metadata/material-timer/SOURCE.json)及对应 [Apache-2.0 原文](../third_party/licenses/Asset-Material-timer-Apache-2.0.txt)随公开源码保留。

2026-10-02 的转换将 SVG 的矩形和路径写为白色 Android vector，保留 24 × 24 viewport 和图形几何，并在 XML 注释中声明来源、许可及转换日期。图标继续用于前台计时通知、守护通知和悬浮提醒。当前工作目录文件 SHA-256 为 `c00963d2e0bd8b9e453a4833f3aa19412683a1ad758b87afc25be07892c75c92`；公开快照对文本换行规范化后，以其 `SOURCE_MANIFEST.json` 为准。

当前补充许可资产包含 Google timer 来源、转换说明和完整 Apache-2.0 文本，客户端许可页读取该资产。源码原文和通知已准备；最终 APK 是否包含一致内容由[第三方核查命令](THIRD_PARTY_AUDIT.md#每次签名构建后的检查)验证，实际通知显示仍需手机检查。

旧版专注通知 XML 和历史快照中的圆圈勾形 `ic_launcher_foreground.xml` 缺少原始作者及上游记录，均不用于当前客户端。维护目录中保留历史文件不表示本次候选继续分发它们。

## 框架控件图标与字体

界面继续使用 Flutter `Icons` 与 Material 组件；`uses-material-design` 为 true。客户端没有新增字体依赖或独立产品字体，中文由系统字体回退显示。Flutter 在构建时提供 Material 图标字体，并可删除未使用的字形。原 `0.2.0-preview.1+3` APK 的字体资产只有 `MaterialIcons-Regular.otf`，没有 Roboto、Roboto Condensed 或微软雅黑；新候选须重新核对。

当前 SDK 的 [Material 图标字体许可原文](../third_party/licenses/Asset-Material-icons-fonts-Flutter-bundled-0-materialicons_license.txt)为 Creative Commons Attribution 4.0 International（CC BY 4.0），字体内版权声明为 `Copyright 2019 Google LLC. All Rights Reserved.`。它与上节独立 SVG 的 Apache-2.0 许可不同，不能用上游图标仓库的当前首页说明替换实际字体版本的原文。

`client/assets/licenses/supplemental.json` 保留 Material 字体的 Google 署名、固定字体包来源、CC BY 4.0 全文及字形子集化说明，注册到客户端的 `LicenseRegistry`。字体仍按其独立许可使用，Pactick 的 Source Available 商业限制不适用于该第三方字体。最终 APK 的资产字节与许可入口仍按[第三方核查](THIRD_PARTY_AUDIT.md)验证。

Flutter widget 截图在隔离测试中加载本机微软雅黑和 SDK 的 MaterialIcons，以便读取中文与图标。微软雅黑字体文件没有声明为产品资源或复制到公开源码；截图中的文字是渲染后的像素。截图字体显示不代表 Android 系统字体及真实 TalkBack 验证。
