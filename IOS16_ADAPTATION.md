# iOS 16 适配说明（二开）

## 结论
- **可行**，但不是改 deployment target 就能跑：原项目深度依赖 iOS 17/18 API。
- 本分支已将 `IPHONEOS_DEPLOYMENT_TARGET` 降为 **16.0**，并完成主工程关键阻塞改造。
- 当前环境为 Windows，**无法用 Xcode 实机/模拟器编译验证**；请在 macOS + Xcode 上 `xcodegen generate` 后编译。

## 已完成
1. deployment target: 18.0 → 16.0（`project.yml` + `project.pbxproj`）
2. iOS 18 `Tab { }` → 经典 `tabItem` + `tag`
3. iOS 17 `ContentUnavailableView` / 双参数 `onChange` / `navigationDestination(isPresented:)` / `toolbar(removing:)` 兼容层
4. iOS 18 `onScrollGeometryChange` / `onScrollPhaseChange` → UIKit KVO + pan 观察（下拉刷新 / 阅读位置）
5. **SwiftData（iOS 17+）→ JSON 文件持久化**（浏览历史、最近吧、搜索历史、阅读位置、发帖草稿）
6. `Task.sleep(for:)` → nanoseconds 兼容
7. 新增 `TiebaPure/Core/Compatibility/iOS16Compatibility.swift`

## 已知限制 / 待验证
- 单元测试 `ContentDraftTests` / `StateRegressionTests` 仍大量假设 SwiftData `ModelContainer`，需后续重写或在 iOS 17+ 测试配置下运行。
- iOS 16.0–16.3 部分 presentation API 行为与 16.4+ 有差异（已用 availability 降级）。
- 下拉刷新/阅读位置改为 UIKit 观察后，需在真机验证手势与回顶动画。
- PhotosPicker / ShareLink / NavigationStack 均为 iOS 16+，可保留。

## 建议构建
```bash
xcodegen generate --spec project.yml
xcodebuild -project TiebaPure.xcodeproj -scheme TiebaPure \
  -destination 'platform=iOS Simulator,name=iPhone 14,OS=16.4' build
```
