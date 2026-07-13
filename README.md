# TiebaPure-iOS

> **本项目借鉴并移植自 [HuanCheng65/TiebaLite](https://github.com/HuanCheng65/TiebaLite/tree/4.0-dev)。** 追溯基线固定为 `4.0-dev@2885b2aabbbf47aba7bf12b1cd7cbc03b1f5ec15`，感谢原作者与所有贡献者。

[![iOS CI](https://github.com/infinityf4p/TiebaPure-iOS/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/infinityf4p/TiebaPure-iOS/actions/workflows/ci.yml?query=branch%3Amain)

TiebaPure-iOS 是一个使用 SwiftUI 编写的非官方百度贴吧只读客户端，支持访客浏览、首页推荐、进吧、吧内列表、搜索主题/回复、帖子与楼中楼、图片和视频查看，以及可选的百度手机号验证码登录。它与百度公司、百度贴吧官方及 TiebaLite 原作者均无隶属、授权或认可关系。

## 来源与许可证

本仓库不是“从零原创”的独立实现。下列材料直接来自或可追溯地借鉴了 TiebaLite：

- `Protos/` 中 **302 个 `.proto` 文件为直接复制**，并已逐文件确认与固定来源提交一致。
- `TiebaPure/Resources/Emoticons/` 中 **51 个 WebP 表情资源与固定来源逐字节匹配**。
- 贴吧旧客户端协议请求字段、protobuf 组合、响应映射、内容过滤规则和部分阅读界面行为参考了 TiebaLite。
- iOS/SwiftUI 代码是面向本项目的实现和修改，但可追溯衍生内容仍按 GPL 要求发布。

代码、协议材料和可追溯衍生材料采用 [`GPL-3.0-only`](LICENSE)。修改日期为 **2026-07-13**。本软件不提供任何明示或暗示担保。

另有 **54 个 PNG 表情资源的来源与再分发许可未知，本项目不声明这些文件受 GPL 授权**。保留这些文件是经明确选择后的兼容决定；披露并不能消除版权或再分发风险。逐文件 SHA-256、分类和完整说明见 [ASSET_MANIFEST.sha256](ASSET_MANIFEST.sha256) 与 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 安全与隐私

- 生产账号只保存在 Keychain，使用 `WhenUnlockedThisDeviceOnly`；旧版 `account.json` 仅允许一次性迁移，只有 Keychain 写入与明文删除均成功时才恢复账号，任何失败都要求重新登录且绝不回退到明文凭证。
- 只保留经域边界、Secure、有效期和名称白名单验证的 `BDUSS`、`STOKEN`、`BAIDUID`，不保存浏览器完整 Cookie 头。
- 登录 WebView 使用非持久数据仓库，仅允许百度 HTTPS 域，并只在精确的贴吧成功页面完成验证。
- API 使用独立 ephemeral `URLSession`，关闭自动 Cookie、凭证和敏感响应缓存。
- API 响应上限 16 MiB，图片上限 30 MiB；图片同时检查 MIME。
- 媒体和网页 URL 仅允许安全 HTTPS 远程地址，拒绝 userinfo、本机、回环和私有 IP。
- 完整隐私说明见 [PRIVACY.md](PRIVACY.md)。

## 构建

要求：macOS 26、Xcode 26.1.1、iOS 26.1 runtime、XcodeGen 2.45 或更新版本。

```bash
xcodegen generate --spec project.yml
xcodebuild -project TiebaPure.xcodeproj -scheme TiebaPure \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1' build
```

项目只维护由 `project.yml` 生成的唯一 `TiebaPure.xcodeproj`。protobuf 生成脚本只读取仓库内的 `Protos/`，不依赖外部 TiebaLite checkout：

```bash
./scripts/generate-ios-protos.sh
```

## 测试

DEBUG 构建支持完全离线的确定性 UI 夹具。UI 测试使用启动参数 `UITEST_USE_FIXTURES`，场景通过 `TIEBAPURE_FIXTURE_SCENARIO` 选择：

- `success`
- `refreshUpdate`（第二次首页请求返回可识别的新内容）
- `emptyThenSuccess`（吧页首次为空，下拉后返回内容）
- `empty`
- `error`
- `expired`
- `slow`
- `paginationFailure`（同一失败页重试后成功）
- `longContent`

测试清单共 **120 个单元测试**和 **27 个 fixture UI 测试**。普通本地测试与 CI 运行 119 个离线单元测试，并按设计跳过 1 个必须显式启用的匿名线上冒烟测试；CI 不访问贴吧线上服务，也不使用真实百度账号。

UI 测试含 1 个仅在 Reduce Motion 下运行及 2 个仅限 iPad 的条件测试，因此各设备的通过/跳过数量不同。为避免长时间连续重启应用触发 XCUITest Accessibility snapshot 超时，完整 UI 验收与 CI 将首页 Tab 重选测试单独运行，其余测试拆为两个分片，并按 27 项去重聚合结果。

```bash
xcodebuild -project TiebaPure.xcodeproj -scheme TiebaPure \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1' \
  -derivedDataPath /tmp/TiebaPureDerivedData \
  test -only-testing:TiebaPureTests
```

模拟器 XCTest 应保留正常签名配置，不要传入 `CODE_SIGNING_ALLOWED=NO`。完整 UI 分片、三设备矩阵、匿名线上冒烟结果及发布门禁状态见 [docs/verification.md](docs/verification.md)。

## 明确不包含

本项目不包含发帖/回复、多账号、个人资料编辑、帖子阅读历史、真实账号自动化测试、App Store 提交或整体视觉重设计。
