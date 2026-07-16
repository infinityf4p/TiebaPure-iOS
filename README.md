# TiebaPure-iOS

> **本项目借鉴并移植自 [HuanCheng65/TiebaLite](https://github.com/HuanCheng65/TiebaLite/tree/4.0-dev)。** 追溯基线固定为 `4.0-dev@2885b2aabbbf47aba7bf12b1cd7cbc03b1f5ec15`，感谢原作者与所有贡献者。

[![iOS CI](https://github.com/infinityf4p/TiebaPure-iOS/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/infinityf4p/TiebaPure-iOS/actions/workflows/ci.yml?query=branch%3Amain)

本 iOS 实现的项目作者与维护者：[infinityf4p](https://github.com/infinityf4p)。

TiebaPure-iOS 是一个使用 SwiftUI 编写的非官方百度贴吧只读客户端，支持访客浏览、首页推荐、进吧、吧内列表、搜索主题/回复、帖子与楼中楼、图片和视频查看，以及可选的百度手机号验证码登录。它与百度公司、百度贴吧官方及 TiebaLite 原作者均无隶属、授权或认可关系。

## 来源与许可证

本仓库不是“从零原创”的独立实现。下列材料直接来自或可追溯地借鉴了 TiebaLite：

- `Protos/` 中 **302 个 `.proto` 文件为直接复制**，并已逐文件确认与固定来源提交一致。
- `TiebaPure/Resources/Emoticons/` 中 **51 个 WebP 表情资源与固定来源逐字节匹配**。
- 贴吧旧客户端协议请求字段、protobuf 组合、响应映射、内容过滤规则和部分阅读界面行为参考了 TiebaLite。
- iOS/SwiftUI 代码是面向本项目的实现和修改，但可追溯衍生内容仍按 GPL 要求发布。

代码、协议材料和可追溯衍生材料采用 [`GPL-3.0-only`](LICENSE)。修改日期为 **2026-07-15**。本软件不提供任何明示或暗示担保。

另有 **54 个 PNG 表情资源的来源与再分发许可未知，本项目不声明这些文件受 GPL 授权**。保留这些文件是经明确选择后的兼容决定；披露并不能消除版权或再分发风险。逐文件 SHA-256、分类和完整说明见 [ASSET_MANIFEST.sha256](ASSET_MANIFEST.sha256) 与 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 安全与隐私

- 登录凭证只保存在 Keychain，不回退到明文文件；旧版明文账号数据仅用于一次性安全迁移。
- 登录页面和网络请求限制为安全的 HTTPS 地址，并对 Cookie、缓存和响应大小进行约束。
- 帖子浏览历史最多保存 500 条，仅保存在本机 UserDefaults，可在“我的 → 浏览历史”逐条删除或全部清空。
- 帖子收藏和阅读位置各最多保存 500 条，同样只保存在本机；可在“我的 → 帖子收藏”分别管理，互不影响。
- 可在“我的 → 设置 → 外观”选择跟随系统、浅色或深色模式，偏好仅保存在本机。
- 更完整的存储、网络和数据处理说明见 [PRIVACY.md](PRIVACY.md)。

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

DEBUG 构建提供离线 fixture，单元测试和 CI UI 测试不依赖贴吧线上服务，也不使用真实百度账号。

```bash
xcodebuild -project TiebaPure.xcodeproj -scheme TiebaPure \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1' \
  -derivedDataPath /tmp/TiebaPureDerivedData \
  test -only-testing:TiebaPureTests
```

完整测试方式、设备矩阵和验证结果见 [docs/verification.md](docs/verification.md)。

## Roadmap

未来可能根据维护情况逐步加入：

- 浏览历史搜索和批量管理。
- 字号、正文间距和媒体加载等阅读设置。
- 更完善的 iPad、横屏和媒体查看体验。
- 发帖与回复、个人资料编辑。

以上仅为可能的开发方向，不代表具体版本或完成时间。
