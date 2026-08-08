# TiebaPure-iOS

[![iOS CI](https://github.com/infinityf4p/TiebaPure-iOS/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/infinityf4p/TiebaPure-iOS/actions/workflows/ci.yml?query=branch%3Amain)
[![License](https://img.shields.io/badge/license-GPL--3.0--only-blue)](LICENSE)
[![Release](https://img.shields.io/github/v/release/infinityf4p/TiebaPure-iOS)](https://github.com/infinityf4p/TiebaPure-iOS/releases/latest)

基于 SwiftUI 的第三方百度贴吧客户端，支持 iOS 16.0 及更高版本。

## 截图

<p align="center">
  <img src="docs/images/home-light.png" width="31%" alt="未登录访客首页" />
  <img src="docs/images/thread-guest-light.png" width="31%" alt="未登录访客帖子详情" />
  <img src="docs/images/search-light.png" width="31%" alt="未登录访客搜索结果" />
</p>

<p align="center"><sub>未登录访客模式下的公开内容</sub></p>

## 功能

**浏览**（无需登录）

- 首页推荐、进吧、吧内列表，「最新 / 精华」分类，可按回复时间或发帖时间排序
- 搜索主题与回复，吧内搜索
- 帖子详情、楼中楼、图片缩放与保存、视频播放

**登录后**

- 消息：回复我的、@我的
- 关注或取消关注用户、贴吧，查看关注与粉丝列表
- 收藏帖子，收藏保存在贴吧账号里，与官方客户端同步；收藏列表支持搜索、按阅读进度筛选和批量取消
- 贴吧签到：一键为关注的贴吧签到，也可以设置每天第一次打开时自动签到
- 主贴、楼层、楼中楼点赞
- 发布文字主题，回复帖子、楼层与楼中楼；回复支持最多 9 张图片，编辑器支持贴吧表情和本机草稿
- 编辑本人资料（昵称、简介和性别）

注意！发布、回复和个人资料编辑目前仅为实验性功能，均通过非官方接口完成，可能存在风险，会触发百度官方风控导致删帖等。

**本机功能**

- 关键词 / 用户 / 贴吧屏蔽
- 浏览历史支持搜索、筛选和批量管理，上限 500 条；阅读位置自动恢复，上限 500 条
- iPad 双栏布局，外观可跟随系统或手动选择浅色 / 深色，支持「减弱动态效果」
- 深链接 `tiebapure://thread/...`、`tiebapure://forum/...`，以及 Safari 分享菜单中的「用 TiebaPure 打开」


## 下载

[Releases](https://github.com/infinityf4p/TiebaPure-iOS/releases/latest) 提供已发布版本的 **未签名** IPA，安装前需要使用自己的证书重新签名。

## 构建

已验证的开发环境为 Xcode 26.6、iOS 26.5 模拟器和 XcodeGen 2.45.x；二开分支最低支持 iOS 16.0（SwiftData 已替换为 JSON 文件持久化，部分 iOS 17/18 API 提供兼容层）。

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

感谢[LINUX DO](https://linux.do/) 社区的支持。
