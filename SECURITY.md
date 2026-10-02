# 安全问题报告

问题可通过 GitHub Issues 或维护者邮箱报告。公开 issue 可描述问题现象、受影响版本和影响范围。包含可利用漏洞细节、令牌、数据库、个人任务或服务端密钥的材料应通过邮箱私下提交。

## 报告入口

- 一般问题：[GitHub Issues](https://github.com/2354634715/Pactick/issues)。
- 私下安全报告：[w66610@outlook.com](mailto:w66610@outlook.com)。

地址由维护者于 2026-10-02 确定。当前尚未验证 GitHub 入口可达性和测试邮件收件结果；公开分发前须完成验证。无法提交时，联系提供测试包的分发者，不在公开 issue 中提交可利用漏洞详情或敏感数据。

正式仓库也可启用 GitHub Private vulnerability reporting。启用后，报告者可通过 Security → Advisories → Report a vulnerability 私下提交。此功能为可选配置，方法见 [GitHub 官方文档](https://docs.github.com/en/code-security/security-advisories/working-with-repository-security-advisories/configuring-private-vulnerability-reporting-for-a-repository)。

## 建议提供的信息

- 受影响版本、Android 或服务器环境；
- 使用演示账号和最少必要数据的复现步骤；
- 预期行为、实际行为、影响范围；
- 已有修复建议，以及方便私下联系的方式。

目前没有公开稳定版本，也未承诺安全维护期限。维护者根据问题影响和可投入时间处理报告。自部署者负责服务器更新、TLS、备份和密钥管理；发生密钥泄漏时，需先在受影响系统中轮换凭据。
