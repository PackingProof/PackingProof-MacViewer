# 版权与协议来源

本项目是 [PackingProof-Desktop](https://github.com/PackingProof/PackingProof-Desktop)（AGPL-3.0）的 macOS 查看端移植，仅实现其第四种用途“只连接主机查看”。

- 上游仓库：`https://github.com/PackingProof/PackingProof-Desktop.git`
- 参考提交：`a38e1ce31dbf4668a31bf5e5e0960ab59fcc6ad4`
- 许可证：AGPL-3.0（本仓库 LICENSE 与上游一致）

## 与 Windows 保存主机对接的协议（主机端不改动）

- 主机发现同时使用 UDP 广播和 HTTP 子网扫描：
  - UDP 广播：客户端向 `255.255.255.255:5281` 发送 `discover`，主机返回 `announce`，字段包括 `protocol`、`protocolVersion`、`action`、`nodeId`、`httpPort`；客户端以 UDP 包来源 IP 和 `httpPort` 为候选地址。
  - HTTP 子网扫描：枚举本机活动 IPv4 网段，对每个候选地址并发请求 `GET /api/node-info`，默认端口 `5280`，非回环探测 3 秒超时、每批 32 个。
  - UDP 与 HTTP 得到的候选地址都会再次请求 `GET /api/node-info` 做最终校验。
- `/api/node-info` 响应字段：`protocol`、`protocolVersion`、`nodeId`、`nodeName`、`preset`、`capabilities`、`httpPort`，可选 `accessProtected`。
- 只有 `protocol == "packingproof"`、`protocolVersion == 1`、`nodeId` 为合法非空 UUID、`preset` 为已知值、`capabilities` 含 `host` 且 `httpPort` 合法的节点才被列为可用主机。
- 网页回放地址以实际连接 IP 加 `node-info` 返回的权威 `httpPort` 为准，页面由 Windows 主机提供，本端只负责发现与跳转。

## 受保护主机的查看端授权（随主机端 v0.0.49+）

- `/api/node-info` 可选字段 `accessProtected`：true=开启网页保护，false=明确未保护，缺失=旧主机无法确认。
- 查看端以 `deviceKind=viewer` 复用 `/api/mobile-backup/enroll`（历史命名，实际语义是通用设备注册 + 主机批准）；批准后回包携带 `webAccessUrl`（带 `?key=` 的完整链接，与手机链接同密钥）。
- `backupProtocol=mobile-backup-v2` 是协议栈版本标识，不代表客户端类型；`platform=macos/windows` 仅用于批准弹窗展示。
- 本端只用预检通过的链接拉起浏览器：受保护主机绝不无认证打开；key 失效最多自动申请一次。
- key 默认保存在 `~/Library/Application Support/PackingProofViewer/web-access-keys.json`（0600 权限，与 Windows 端 config.json 的安全级别一致）；当前正式包使用 Developer ID 签名，但密钥存储仍保持文件方案，避免每次重建触发钥匙串 ACL 弹窗，后续可评估是否切换 KeychainWebAccessKeyStore。
