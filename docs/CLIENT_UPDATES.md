# 客户端更新检查接口

源码公开版通过“关于”页的 Releases 链接查看更新，不自动调用此接口，也不显示全局强制更新页。该 API 保留用于兼容已有客户端；更新检查不得阻断本地工作区的使用。

服务端提供公开的只读更新检查接口：

```http
GET /v1/client-updates/check?platform=android&channel=stable&current_version=0.1.0&build_number=2
```

接口无需登录，不读取数据库，也不代理安装包下载。服务端只返回启动时从可信配置加载的发布元数据；请求方不能指定下载地址，接口不提供开放重定向或任意文件读取功能。

## 1. 请求约束

四个查询参数都必须恰好出现一次，不允许额外参数：

| 参数 | 约束 |
| --- | --- |
| `platform` | `android`、`windows` 或 `linux` |
| `channel` | `stable` 或 `beta` |
| `current_version` | 最长 64 字符、无 build metadata 的 SemVer，例如 `0.2.0` 或 `0.2.0-beta.1` |
| `build_number` | 不带符号或前导零的正十进制整数 |

版本优先按 SemVer 比较；版本相同时才比较 `build_number`。同一个 `0.2.0` 版本可使用更高的构建号重新发布。版本号不接受 `+3` 形式的 build metadata，版本顺序由 SemVer 和独立构建号共同确定。

## 2. 响应状态

配置版本更高时返回：

```json
{
  "status": "update_available",
  "update_available": true,
  "required": false,
  "version": "0.2.0",
  "build_number": 3,
  "download_url": "https://downloads.example.com/pactick-0.2.0+3.apk",
  "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
  "size_bytes": 28765432,
  "release_notes": "修复同步与计时恢复问题。",
  "published_at": "2026-09-19T00:00:00Z"
}
```

客户端版本不低于配置版本时，`status` 为 `up_to_date`，`update_available` 和 `required` 都为 `false`，并返回最新发布元数据，供客户端显示版本和校验信息。

指定平台和渠道未配置发布包时，接口返回以下状态，而非最新版本状态或 404：

```json
{
  "status": "not_configured",
  "update_available": false,
  "required": false,
  "version": null,
  "build_number": null,
  "download_url": null,
  "sha256": null,
  "size_bytes": null,
  "release_notes": null,
  "published_at": null
}
```

`required` 是当前发布项的强制更新开关，但仅在客户端版本低于配置版本时返回 `true`。客户端已经达到或超过配置版本时，即使清单中的发布项设置了 `required: true`，响应中的值仍为 `false`。

## 3. 配置发布清单

环境变量 `CLIENT_UPDATE_MANIFEST_JSON` 保存完整 JSON。空值表示暂未配置任何发布；非空时顶层必须是只有 `releases` 的对象。每个平台与渠道组合最多配置一个最新发布项：

```json
{
  "releases": [
    {
      "platform": "android",
      "channel": "stable",
      "version": "0.2.0",
      "build_number": 3,
      "required": false,
      "download_url": "https://downloads.example.com/pactick-0.2.0+3.apk",
      "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
      "size_bytes": 28765432,
      "release_notes": "修复同步与计时恢复问题。",
      "published_at": "2026-09-19T00:00:00Z"
    }
  ]
}
```

生产 `api.env` 会被部署校验脚本作为 shell 配置读取，因此 JSON 必须压成一行并用单引号包住；JSON 字符串内的换行使用 `\n`。若发布说明含英文单引号，必须在 JSON 中将它编码为 `\u0027`，不得把未转换的 `'` 或 shell 拼接片段放入该行：

```dotenv
CLIENT_UPDATE_MANIFEST_JSON='{"releases":[{"platform":"android","channel":"stable","version":"0.2.0","build_number":3,"required":false,"download_url":"https://downloads.example.com/pactick-0.2.0+3.apk","sha256":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","size_bytes":28765432,"release_notes":"修复同步与计时恢复问题。","published_at":"2026-09-19T00:00:00Z"}]}'
```

清单仅在进程启动时加载，不支持热更新。修改配置后重新创建 API 容器：

```sh
docker compose --project-directory /opt/pactick/app \
  --env-file /opt/pactick/config/compose.env \
  -f /opt/pactick/app/compose.production.yaml \
  up -d --no-deps --force-recreate api
```

启动会拒绝未知 JSON 字段、重复的平台/渠道、非法 SemVer、非正数构建号或文件大小、非 64 位十六进制摘要、无效时间，以及非绝对 HTTPS、含凭据或含 fragment 的下载地址。清单最大 256 KiB、最多 32 项，发布说明最多 20,000 个字符。

## 4. 发布步骤

1. 首次发布前创建专用且长期保存的 Android 生产签名密钥；复制 `client/android/key.properties.example` 为 `client/android/key.properties`，密钥库与密码只通过 CI secret 或受保护的构建机注入。丢失该密钥将无法覆盖安装已发布的客户端。
2. 在可信构建环境生成 release 安装包并计算 `sha256sum` 与准确字节数。构建脚本在 release 任务缺少生产签名配置时会直接失败，不会回退到 debug 签名。
3. 将安装包上传到长期可用的 HTTPS 地址，并确认下载不需要登录或跳转至登录页。
4. 更新清单并重启 API；启动失败时查看日志中的 `CLIENT_UPDATE_MANIFEST_JSON` 校验错误。
5. 用旧版本、新版本和未配置渠道分别调用检查接口，确认 `update_available`、`required` 和 `not_configured`。源码公开版不自动调用此接口，任何更新提示不得阻断本地查看、编辑、专注或导出。协议不兼容只应暂停对应服务器同步。
6. 保存生产签名证书指纹，并执行“安装上一版 release → 覆盖安装待发布 release”的真机验收，确认包名和签名连续。
7. 客户端通过系统浏览器打开 HTTPS 下载地址，`size_bytes` 和 `sha256` 用于界面展示与发布审计；安装完整性依赖 HTTPS 和 Android 包签名。若未来改为应用内下载，下载器必须同时核对文件大小和 SHA-256，校验成功后才能交给系统安装器。

详细字段定义和错误响应结构以 [OpenAPI 契约](../api/openapi.yaml) 为准。
