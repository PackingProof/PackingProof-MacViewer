# PackingProof MacViewer

PackProof（PackingProof）的 macOS 查看端，对应桌面版第四种用途“只连接主机查看”：不录像、不做保存主机，只负责在局域网中发现 Windows 保存主机，并用系统默认浏览器打开主机的网页回放页面。

## 界面截图

![PackingProof MacViewer 主界面](Image/screenshot-main.png)

## 功能

- 自动搜索同一局域网内的 PackingProof 保存主机
- 手动连接：支持 `主机IP:端口` 或带 `?key=` 的完整连接链接
- 记住上次连接的主机，启动时优先验证
- 一键用系统默认浏览器打开网页回放（搜索、播放、剪辑下载都在主机网页里完成）

## 构建与运行

依赖 macOS 13+ 与 Xcode 15+（Swift 5.9+），不需要安装其他工具：

```bash
swift build          # 编译
swift test           # 单元测试
./scripts/build-app.sh   # 生成 dist/PackingProofViewer.app（ad-hoc 签名）
open dist/PackingProofViewer.app
```

也可以用 Xcode 打开 `Package.swift` 直接运行调试。

## 发布与安装（GitHub Release）

```bash
./scripts/package-release.sh 0.0.1
```

- 将生成的 `dist/PackingProofViewer_v0.0.1_macOS.zip` 上传到 GitHub Release，并附上 `.sha256` 校验值。
- 安装：解压后把 `PackingProofViewer.app` 拖入“应用程序”；首次打开如被拦截，请右键 → 打开。
- 当前为方案 A（未做 Apple 公证），其他 Mac 首次打开会有 Gatekeeper 提示；后续切换 Developer ID 签名 + 公证无需改动代码。

## 范围说明

- 不包含录像、保存主机、备份/NAS、订单联动、退款拦截等功能
- 不改动 Windows 主机端；协议契约见 [NOTICE.md](NOTICE.md)
- 仅本机使用，未做公证；如需分发给其他 Mac 需要 Apple Developer 账号并公证

## 许可证

AGPL-3.0，详见 [LICENSE](LICENSE)。本仓库是对 PackingProof-Desktop 的移植，版权与协议来源见 [NOTICE.md](NOTICE.md)。
