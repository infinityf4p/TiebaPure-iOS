# TiebaPure-iOS

[![iOS CI](https://github.com/infinityf4p/TiebaPure-iOS/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/infinityf4p/TiebaPure-iOS/actions/workflows/ci.yml?query=branch%3Amain)
[![License](https://img.shields.io/badge/license-GPL--3.0--only-blue)](LICENSE)
[![Release](https://img.shields.io/github/v/release/infinityf4p/TiebaPure-iOS)](https://github.com/infinityf4p/TiebaPure-iOS/releases/latest)

> 本项目基于 [HuanCheng65/TiebaLite](https://github.com/HuanCheng65/TiebaLite/tree/4.0-dev) 的 `4.0-dev` 分支移植并重写，感谢原作者及贡献者。追溯基线：`2885b2aabbbf47aba7bf12b1cd7cbc03b1f5ec15`。

基于 SwiftUI 的第三方百度贴吧客户端，支持 iOS 18.0 及更高版本。

## 截图

<p align="center">
  <img src="docs/images/forum-light.png" width="31%" alt="贴吧公开帖子列表" />
  <img src="docs/images/thread-light.png" width="31%" alt="公开帖子详情" />
  <img src="docs/images/search-dark.png" width="31%" alt="深色模式搜索结果" />
</p>

<p align="center"><sub>未登录访客模式下的公开内容</sub></p>

## 功能

**浏览**（无需登录）

- 首页推荐、进吧、吧内列表，「最新 / 精华」分类，可按回复时间或发帖时间排序
- 搜索主题与回复，吧内搜索
- 帖子详情、楼中楼、图片缩放与保存、视频播放

**登录后**

- 消息：回复我的、@我的
- 关注或取消关注用户，查看已关注的用户和贴吧
- 主贴、楼层、楼中楼点赞

**本机功能**

- 关键词 / 用户 / 贴吧屏蔽
- 浏览历史、帖子收藏、阅读位置自动恢复，各上限 500 条
- iPad 双栏布局，外观可跟随系统或手动选择浅色 / 深色，支持「减弱动态效果」
- 深链接 `tiebapure://thread/...`、`tiebapure://forum/...`

暂时不提供发帖、回复和个人资料编辑。

## 隐私

项目不设自建后端，也不包含广告、统计分析或遥测 SDK。登录凭证仅保存在 Keychain；浏览历史、收藏、阅读位置、搜索历史和屏蔽规则仅保存在本机。使用应用时，会直接连接百度贴吧及相关内容资源服务。

## 下载

当前 `main` 源码版本为 `1.2.5`；[Releases](https://github.com/infinityf4p/TiebaPure-iOS/releases/latest) 提供已发布版本的 **未签名** IPA，功能可能落后于 `main`，安装前需要使用自己的证书重新签名。

## 构建

已验证的开发环境为 Xcode 26.6、iOS 26.5 模拟器和 XcodeGen 2.45.x；App 最低支持 iOS 18.0。

```bash
xcodegen generate --spec project.yml
```

```bash
xcodebuild -project TiebaPure.xcodeproj -scheme TiebaPure \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build
```

更多开发信息见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 声明

本项目与百度公司、百度贴吧官方无隶属、授权或认可关系。

项目以 [GPL-3.0-only](LICENSE) 发布，不提供任何担保。协议定义、表情资源等第三方材料的来源与许可说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
