# TiebaPure Verification

Last updated: 2026-07-15 (Asia/Shanghai)

> 本地构建、模拟器功能、匿名线上冒烟、隐私清单、IPA 与实际暂存树门禁已通过。远端发布状态以[当前 `main` 的 iOS CI](https://github.com/infinityf4p/TiebaPure-iOS/actions/workflows/ci.yml?query=branch%3Amain)为准；工作流未全绿时不得交付。

## 固定环境

- macOS 26.5.2 (`25F84`)
- Xcode 26.1.1 (`17B100`)
- XcodeGen 2.45.4
- iOS Simulator 26.1 (`23B86`)
- SwiftProtobuf 1.38.1
- Deployment target: iOS 16.0

模拟器 XCTest 必须按正常方式签名运行。不要为模拟器测试传入 `CODE_SIGNING_ALLOWED=NO`，否则 Keychain 回归测试会因为缺少 entitlement 而失去验证意义。

## 测试清单与条件跳过

- 单元测试：140 项。
  - 139 项离线确定性测试。
  - 1 项 opt-in 匿名线上冒烟；普通本地测试和 CI 默认跳过。
- fixture UI 测试：38 项。
  - 2 项刷新功能测试覆盖下拉与首页 Tab 重选，不依赖动画状态。
  - 1 项空态下拉刷新测试。
  - 1 项图片页测试覆盖捏合/双击缩放、保存反馈与单击返回来源页。
  - 1 项浏览历史测试覆盖成功浏览后记录、“我的”入口和重新打开帖子。
  - 1 项长文本测试覆盖主贴、评论、楼中楼预览与完整楼中楼页面。
  - 1 项动画抑制测试仅在 Reduce Motion 开启时运行。
  - 2 项仅在 iPad 运行。

UI 测试使用 `UITEST_USE_FIXTURES`，不访问贴吧线上服务。夹具场景为 `success`、`refreshUpdate`、`emptyThenSuccess`、`empty`、`error`、`expired`、`slow`、`paginationFailure`、`longContent`、`subpostReference` 和 `imageGesture`。

为规避 XCUITest 在多次应用重启后偶发的 Accessibility snapshot 查询超时，完整 UI 验收使用四个独立的 `xcodebuild` invocation：

1. 单独运行 `testHomeTabReselectAfterScrollingRefreshesContent`。
2. 运行 UI shard A。
3. 运行 UI shard B。
4. 运行 UI shard C。

每轮聚合必须恰好覆盖全部 38 项，不能把基础设施超时计作通过，也不能遗漏测试。普通 CI 同样只运行确定性 fixture 分片。

## iPhone 17 下拉刷新完整回归

设备：iPhone 17 / iOS 26.1 (`23B86`)

`v1.0.2 (6)` 发布前最终聚合使用正常模拟器签名一次运行完整测试树：**171 通过 / 4 条件跳过 / 0 失败**，共 175 项。其中单元测试 137 通过、1 项匿名线上冒烟按设计跳过；UI 测试 34 通过、3 项设备/辅助功能条件测试按设计跳过。验证码登录兼容、成功回调不渲染、`window.open` 外部 App 拦截和账号保存均包含确定性回归。

| 轮次 | 单元测试 | UI 测试 | 结果 |
| --- | --- | --- | --- |
| 1 | 106 通过 / 1 条件跳过 / 0 失败 | 22 通过 / 3 条件跳过 / 0 失败 | PASS |
| 2 | 106 通过 / 1 条件跳过 / 0 失败 | 22 通过 / 3 条件跳过 / 0 失败 | PASS |

以上完整 UI 轮次覆盖加入图片下载回归前的 25 项测试树。单元测试唯一跳过项是 opt-in 匿名线上冒烟；UI 的三个预期跳过项是 Reduce Motion-only 测试和两个 iPad-only 测试。

随后加入图片页单击返回与保存原图功能，并在同一台 iPhone 17 / iOS 26.1 模拟器完成：

- 图片功能阶段单元测试：109 通过 / 1 条件跳过 / 0 失败。
- 图片页与三条刷新路径定向 UI 回归：4 通过 / 0 跳过 / 0 失败。
- 保存成功反馈与单击返回最终复测：1 通过 / 0 跳过 / 0 失败。

帖子正文截断修复后，在同一模拟器继续完成：

- 最终单元测试：110 通过 / 1 条件跳过 / 0 失败。
- 主贴、评论及两种楼中楼长文本高度回归：1 通过 / 0 跳过 / 0 失败。
- HTTPS 链接 trait 与长图入口回归：2 通过 / 0 跳过 / 0 失败。

随后进行追加安全与健壮性审查，修复持久化 Cookie 值注入、取消保存时恢复不安全旧凭证、媒体初始 URL 绕过、下载图片像素与文件名边界、超范围帖子 ID、定位楼层后的分页推进，以及 FRS/搜索错误码不一致。最终在同一台 iPhone 17 / iOS 26.1 模拟器完成：

- 完整离线单元测试：119 通过 / 0 跳过 / 0 失败。
- 下拉刷新、图片保存/单击返回、长正文/楼中楼和 HTTPS 链接关键 UI 回归：5 通过 / 0 跳过 / 0 失败。
- `xcodebuild analyze`：PASS。
- Release `iphoneos` unsigned build：PASS。

帖子浏览历史加入后，在同一台 iPhone 17 / iOS 26.1 模拟器追加完成：

- 完整单元测试：139 通过 / 1 条件跳过 / 0 失败，共 140 项。
- 新增 CI shard C：11 通过 / 0 跳过 / 0 失败。
- 浏览历史端到端路径连续运行 3 次均通过，覆盖成功打开帖子后记录、“我的”入口、历史列表与重新打开帖子。
- “进吧”及“我的”原有访客入口回归：1 通过 / 0 跳过 / 0 失败。
- Release `iphoneos` unsigned build：PASS。

## 小屏与无障碍矩阵

设备：iPhone SE (3rd generation) / iOS 26.1。runtime 正常可用，未启用 iPhone 13 mini fallback。

完整 fixture UI 聚合使用以下设置：

- 浅色模式
- Accessibility XXXL
- 粗体文本
- 增强对比度
- Reduce Motion

结果：**20 通过 / 4 条件跳过 / 0 失败**。四个预期跳过项是两个仅在正常动画模式运行的刷新动画测试和两个 iPad-only 测试；Reduce Motion 动画抑制测试已通过。

深色模式专项覆盖：

- 竖屏：PASS
- 横屏：PASS
- 合计：2 / 2 PASS

小屏验收覆盖搜索与帖子控制区换行、动态字体、长昵称、44pt 触控区、浅/深色对比度、Reduce Motion 和横竖屏布局；未发现文本或媒体溢出。

## iPad 矩阵

设备：iPad Pro 11-inch (M5) / iOS 26.1 (`23B86`)

- 正常动画模式完整分片：23 项通过；Reduce Motion-only 测试按条件跳过。
- Reduce Motion 专项：1 项通过。
- 去重后的完整功能聚合：**24 通过 / 0 跳过 / 0 失败**。
- 最终源码补充回归：默认字体 5 / 5 PASS；深色 Accessibility Extra Large 3 / 3 PASS。

iPad 验收覆盖横竖屏、默认/大字体、空态、错误态、长昵称、0/1/3/4+ 媒体、超宽/超长图、前后台切换、Tab Bar 空白区，以及帖子标题和摘要的完整点击区域；未发现布局溢出。

## 合成视觉验收

fixture UI 测试生成并检查了首页、搜索、帖子控制区、深色大字体和 iPad 场景。截图只包含合成夹具，不包含真实线上用户内容。截图与 `.xcresult` 仅作为本地验证证据，不提交到仓库。

## 匿名线上冒烟

- 执行时间：2026-07-13 02:46 CST
- 账号：匿名，不使用真实百度账号
- 测试：`AnonymousLiveSmokeTests/testAnonymousHomeForumSearchThreadAndMediaJourney`
- 路径：首页 → 进吧 → 搜索 → 帖子 → 媒体
- 结果：**1 通过 / 0 跳过 / 0 失败**
- 耗时：3.063 秒

此项只有在 test runner 环境显式设置 `RUN_ANONYMOUS_LIVE_SMOKE=1` 时运行；CI 不设置该变量，也不访问贴吧线上服务。

## 生成一致性与来源清单

| 检查项 | 结果 |
| --- | --- |
| XcodeGen 2.45.4 重新生成唯一 `TiebaPure.xcodeproj`，前后 hash 不变 | PASS |
| `scripts/generate-ios-protos.sh` 仅使用仓库内 `Protos/`，生成 151 个 Swift schema，前后 hash 不变 | PASS |
| `scripts/generate-asset-manifest.sh` 重新生成，前后 hash 不变 | PASS |
| `.proto` 来源文件数 | 302 |
| 与固定 TiebaLite 来源逐字节匹配的 WebP | 51 |
| 来源及再分发许可未知的 PNG | 54 |

来源固定为 TiebaLite `4.0-dev@2885b2aabbbf47aba7bf12b1cd7cbc03b1f5ec15`。未知许可 PNG 的披露不消除版权和再分发风险。

## 发布门禁

以下状态必须依据最终命令输出更新，不能以已有测试结果推断：

| 门禁 | 状态 |
| --- | --- |
| `xcodebuild analyze` | PASS |
| Debug simulator build | PASS |
| Release `iphoneos` build | PASS |
| Release app 内含且可解析 `PrivacyInfo.xcprivacy` | PASS |
| unsigned IPA 生成与结构校验 | PASS |
| IPA 内含 `PrivacyInfo.xcprivacy` | PASS |
| IPA 不含 `_CodeSignature` 与 `embedded.mobileprovision` | PASS |
| 实际暂存树无 build、DerivedData、IPA、xcresult、截图和用户数据 | PASS |
| 实际暂存树私钥、令牌、凭证扫描 | PASS |
| 最终仓库文件、LICENSE、署名与来源清单核对 | PASS |
| 当前 `main` 的 GitHub Actions | [实时状态](https://github.com/infinityf4p/TiebaPure-iOS/actions/workflows/ci.yml?query=branch%3Amain) |

本地 unsigned IPA 的预期生成位置为：

```text
build/TiebaPure-unsigned.ipa
```

本轮追加审查后的本地包为 `1.0.2 (6)`，SHA-256：`1aac980cf97a77b57af27b79508e966c71fe3981f52c859a8a3e567bb5237031`。包内 `PrivacyInfo.xcprivacy` 可解析，不含 `_CodeSignature`、`embedded.mobileprovision`、DEBUG 登录夹具或 Release 登录诊断输出。

`build/`、IPA、截图和 `.xcresult` 均被忽略，不属于公开仓库内容。IPA 故意不签名，安装前必须由使用者使用自己的证书和描述文件签名。
