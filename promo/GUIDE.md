# Pactick 宣传短片

本目录生成约 60 秒、16:9 的 Pactick 宣传短片。默认输出为 1920×1080、30 帧/秒、Rec.709 色彩标记与有限范围 YUV420P 的 H.264/AAC MP4，配乐为原创程序合成音乐，无旁白。Canvas 绘制全部文字、几何形、图表及功能示意，不读取客户端截图、视频片段或图片生成素材。

## 观看与输出文件

在项目根目录运行 `node promo/server.mjs`，然后打开 <http://127.0.0.1:4173>。预览页提供播放、暂停、进度拖动、声音开关和章节跳转；空格切换播放，左右方向键前后移动五秒。服务仅监听本机回环地址，关闭运行命令的终端或按 Ctrl+C 后停止。

预览页的音频及下载链接读取 `output/pactick-promo-swiss/` 下的文件。尚未生成配乐时可预览画面，尚未生成 MP4 时下载链接返回 404。直接打开 HTML 时可显示动画，但字体、音频及下载路径应通过上述本地服务访问。

| 文件 | 用途 |
| --- | --- |
| `output/pactick-promo-swiss/Pactick-Swiss-60s.mp4` | 带程序合成配乐的成片 |
| `output/pactick-promo-swiss/cover.png` | 1920×1080 封面 |
| `output/pactick-promo-swiss/frame-00.png` 至 `frame-07.png` | 各章节的布局检查图 |
| `output/pactick-promo-swiss/soundtrack.wav` | 48 kHz、双声道、16-bit 原始配乐 |
| `output/pactick-promo-swiss/storyboard.json` | 章节时间、画幅和色值 |
| `output/pactick-promo-swiss/render-manifest.json` | 渲染参数、浏览器版本、源文件及成片 SHA-256 |

## 重新渲染

需要 Node.js、Python、numpy、Playwright、带 H.264/AAC 编码器的 FFmpeg，以及可启动的 Chromium 浏览器。当前实现优先使用本机 Chrome，其次使用 Edge；其他环境使用 Playwright 自带 Chromium。默认中文字体为 `C:/Windows/Fonts/NotoSansSC-VF.ttf`，英文字体使用系统 Arial 或 Helvetica。

已有依赖时，在项目根目录依次运行：

```powershell
python promo/synth_audio.py
node promo/render.mjs
```

缺少依赖时，可将它们安装到项目缓存，不修改客户端和服务端依赖：

```powershell
New-Item -ItemType Directory -Force .cache/promo-tmp | Out-Null
$env:TEMP = (Resolve-Path .cache/promo-tmp).Path
$env:TMP = $env:TEMP
$env:NPM_CONFIG_CACHE = Join-Path (Get-Location) '.cache/promo-npm'
python -m pip install --target .cache/promo-python numpy imageio-ffmpeg==0.6.0
$env:PYTHONPATH = (Resolve-Path .cache/promo-python).Path
npm.cmd install --prefix .cache/promo-node playwright
```

`render.mjs` 优先读取 `PLAYWRIGHT_MODULE_DIR`，其次查找 `.cache/promo-node/node_modules/playwright`，Windows 下还会查找当前用户的 npx 缓存。FFmpeg 优先读取 `FFMPEG_PATH`，其次查找 `.cache/promo-python/imageio_ffmpeg/binaries/`，最后使用 PATH 中的 `ffmpeg`。不能找到依赖或启动浏览器时命令失败；不会自动下载浏览器或修改系统配置。

需要覆盖默认路径时，在当前终端设置环境变量：

```powershell
$env:PACTICK_BROWSER = 'C:/path/to/chrome.exe'
$env:PACTICK_CJK_FONT = 'C:/path/to/NotoSansSC-VF.ttf'
$env:FFMPEG_PATH = 'C:/path/to/ffmpeg.exe'
$env:PLAYWRIGHT_MODULE_DIR = 'C:/path/to/node_modules/playwright'
```

`PACTICK_CJK_FONT` 指向可本地读取的 Noto Sans SC 字体文件。字体文件不随源码复制；自选字体的使用与分发应遵守其许可。预览依赖本机字体，跨机器更换英文字体可能改变字宽，需要重新检查布局。

只输出章节检查图：

```powershell
node promo/render.mjs --stills
```

输出 4K、60 帧/秒的版本：

```powershell
node promo/render.mjs --width 3840 --fps 60 --workers 3
```

`--width` 默认为 1920，接受 640 至 3840 范围内的 32 倍数，高度按 16:9 计算。`--fps` 默认为 30，接受 24、30、60。`--workers` 默认为 3，接受 1 至 8，每个渲染任务顺序绘制一段时间，按原始顺序合并；内存不足时减小并行数。上述 4K 命令描述支持的参数，不表示本轮已验证 4K 输出。

`--output` 可指定其他输出目录，但该目录须预先包含 `soundtrack.wav`，且默认预览页仍读取 `output/pactick-promo-swiss/`。重复运行会覆盖同名输出文件。编码失败时保留已有章节图、音频和分段文件；修复原因后重新运行，不应将未合并的分段作为成片。

默认成片生成后，运行 `node promo/verify.mjs` 检查字体加载、预览播放、进度拖动、声音开关、章节跳转、手机画幅和实际 MP4 的时长与解码。结果写入 `output/pactick-promo-swiss/verification.json`，预览截图写入 `output/playwright/`；断言失败时命令以错误状态退出。

## 修改内容和动画

`film.js` 的 `chapters` 定义章节，`draws` 对应各章绘制函数。画面尺寸以 1920×1080 为基准，导出时统一缩放。所有运动以传入的绝对时间计算；相同时间生成相同画面，不依赖前一帧或浏览器播放速度。

| 时间 | 内容 |
| --- | --- |
| 00:00–00:08 | Pactick 与任务、日历、专注 |
| 00:08–00:16 | 收集任务、项目和标签 |
| 00:16–00:24 | 将任务安排进日历 |
| 00:24–00:34 | 开始专注并记录实际用时 |
| 00:34–00:42 | 对比计划和实际用时 |
| 00:42–00:50 | 无需账号的本地使用 |
| 00:50–00:56 | 离线备份与可选自部署同步 |
| 00:56–01:00 | Android 预览版、Source Available 许可定位与 GitHub 仓库地址 |

片尾显示 `https://github.com/2354634715/Pactick`，地址从 00:56.7 开始进入画面，在影片结束前保持可见。

`synth_audio.py` 使用固定随机种子生成 120 BPM 音序、鼓点及转场音效，默认 60 秒。它的 `--duration` 仅调整音频时长和章节比例；改变成片时长还需同步修改 `film.js`、`render.mjs` 以及预览页的时间显示。

## 设计依据与功能范围

设计参考 [瑞士风格视频](https://www.bilibili.com/video/BV1hWar6SEVP/) 作者公开的完整简介与风格卡。已获取视频简介及章节说明，未获取视频播放内容或字幕。采用十二列布局基准、左对齐、非对称构图、常规与粗体无衬线字、细线分隔和大面积留白；颜色为黑 `#171714`、米白 `#F4F1E9` 和强调红 `#DA291C`，不使用阴影、渐变或纹理。网格与字体原则也见 [瑞士国家图书馆的国际主义风格说明](https://www.nb.admin.ch/en/the-international-style-1950-1970)。

文案核对当前项目的 [README](../README.md)、[发布计划](../docs/RELEASE_AND_PROMOTION_PLAN.md) 与客户端实现。任务创建、日历排期和专注会话来自 `client/lib/core/state/app_controller.dart`；计划与实际用时对比来自统计页；默认本地工作区和离线备份来自数据层。当前版本为 Android `0.2.0-preview.1+3`，片中使用版本名，不显示内部构建号。

任务、日历、计时器、统计和手机形状均为重新绘制的功能示意，使用虚构演示数据，不代表实际客户端界面。自部署同步有实现，但真实环境验收尚未完成，因此片中保留该限制。短片不声明正式发布、全平台支持或已完成公网验收；实际发布状态以发行记录为准。
