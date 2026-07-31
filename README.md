# TiebaPure-iOS

[![iOS CI](https://github.com/infinityf4p/TiebaPure-iOS/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/infinityf4p/TiebaPure-iOS/actions/workflows/ci.yml?query=branch%3Amain)
[![License](https://img.shields.io/badge/license-GPL--3.0--only-blue)](LICENSE)
[![Release](https://img.shields.io/github/v/release/infinityf4p/TiebaPure-iOS)](https://github.com/infinityf4p/TiebaPure-iOS/releases/latest)

基于 SwiftUI 的第三方百度贴吧客户端，支持 iOS 18.0 及更高版本。

## 截图

<p align="center">
  <img src="docs/images/forum-light.png" width="31%" alt="浅色模式合成首页" />
  <img src="docs/images/thread-light.png" width="31%" alt="浅色模式合成帖子详情" />
  <img src="docs/images/search-dark.png" width="31%" alt="深色模式合成搜索结果" />
</p>

<p align="center"><sub>使用内置测试数据生成，不含真实账号信息</sub></p>

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

## Roadmap

以下方向按优先级逐步推进，不代表固定的交付日期。

**近期：阅读体验**

- 为浏览历史和帖子收藏增加搜索、筛选与批量管理
- 增加字号、正文间距、默认排序和媒体加载等阅读设置
- 支持语音内容播放，并继续改善图片、视频和弱网体验

**中期：互动与链接**

- 支持关注和取消关注贴吧，并完善关注与粉丝列表
- 逐步加入发帖、楼层回复和楼中楼回复，配套草稿、图片、表情与失败重试
- 增加系统分享入口，让贴吧网页链接可直接导入 TiebaPure

**后续：本机与大屏体验**

- 收藏内容离线阅读、缓存管理及本机数据导入导出
- 支持个人资料编辑，并继续丰富用户主页内容
- 改进 iPad 多栏、键盘与指针操作，以及 VoiceOver 和大字体体验

多账号管理不在计划内。

## 隐私

项目不设自建后端，也不包含广告、统计分析或遥测 SDK。登录凭证仅保存在 Keychain；浏览历史、收藏、阅读位置、搜索历史和屏蔽规则仅保存在本机。使用应用时，会直接连接百度贴吧及相关内容资源服务。

## 下载

[Releases](https://github.com/infinityf4p/TiebaPure-iOS/releases/latest) 提供已发布版本的 **未签名** IPA，功能可能落后于 `main`，安装前需要使用自己的证书重新签名。

## 构建

已验证的开发环境为 Xcode 26.6、iOS 26.5 模拟器和 XcodeGen 2.45.x；App 最低支持 iOS 18.0。

```bash
xcodegen generate --spec project.yml
```

```bash
xcodebuild -project TiebaPure.xcodeproj -scheme TiebaPure \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build
```

## 开源许可

TiebaPure-iOS 以 [GPL-3.0-only](LICENSE) 发布，不提供任何担保。项目使用的 [SwiftProtobuf](https://github.com/apple/swift-protobuf) 采用 [Apache-2.0 许可证及 Runtime Library Exception](LICENSES/SwiftProtobuf-Apache-2.0.txt)。

## 声明

本项目与百度公司、百度贴吧官方无隶属、授权或认可关系。

“百度”“贴吧”及相关名称与标识归其各自权利人所有。

## 感谢

感谢 [TiebaLite](https://github.com/HuanCheng65/TiebaLite) 为项目早期开发提供参考，也感谢 [aiotieba](https://github.com/lumina37/aiotieba) 对贴吧协议的整理与开源实现。
