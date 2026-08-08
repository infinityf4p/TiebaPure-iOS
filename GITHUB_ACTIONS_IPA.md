# 用 GitHub Actions 编译 + 巨魔安装

本仓库可在 **没有 Mac** 的情况下，用 GitHub Actions 打出未签名 IPA，再用巨魔 / TrollStore 安装到 iPhone。

## 一次性准备

1. 把本二开工程推到 **你自己的 GitHub 仓库**（不要 force-push 到上游 infinityf4p 除非你是维护者）。
2. 打开仓库 **Settings → Actions → General**：
   - Actions permissions: Allow
   - Workflow permissions: Read and write（若要用 tag 自动发 Release）
3. 确保 `.github/workflows/build-unsigned-ipa.yml` 已提交。

## 编译 IPA

### 方式 A：手动触发（推荐）

1. 打开 GitHub 仓库页面 → **Actions**
2. 左侧选 **Build Unsigned IPA**
3. **Run workflow**
   - `run_unit_tests`: 建议先开；失败时仍会继续打 IPA
   - `configuration`: 一般用 `Release`
4. 等 10–30 分钟（视队列与依赖而定）
5. 进入该次 run → 底部 **Artifacts** → 下载 `TiebaPure-*-unsigned.ipa`

### 方式 B：打 tag 自动发 Release

```bash
git tag ios16-v1.4.4
git push origin ios16-v1.4.4
```

Actions 会构建并把 IPA 挂到 Release 资源上。

## 巨魔安装

1. iPhone 安装 **巨魔** 或 **TrollStore**（按你的系统与设备方式）。
2. 把 IPA 传到手机（AirDrop / iCloud / 浏览器下载 / 电脑拷贝均可）。
3. 用巨魔打开 IPA → 安装。
4. 若提示需重签：用你的证书重签后再装（巨魔多数场景可直接装未签名包）。

### 安装前确认

- 包内 `MinimumOSVersion` 应为 **16.0**（二开目标）
- 手机系统 **≥ 16.0**
- Bundle ID 默认：`dev.infinityf4p.tiebapure`（与官方包冲突时需改 ID 再编）

## 本地脚本对照

上游 `scripts/package-unsigned-ipa.sh` 与 Actions 逻辑一致：`CODE_SIGNING_ALLOWED=NO` 真机包 → 打 zip 成 IPA。  
Actions 会先 `xcodegen generate`，保证 `Core/Compatibility` 等新文件进工程。

## 失败时怎么看

| 现象 | 处理 |
|------|------|
| Xcode / SDK 找不到 | 看 log 里 `Select Xcode`；可改 workflow 里 candidate 列表 |
| Swift 编译错误 | 把错误贴回对话继续改兼容层 |
| 单测红、IPA 仍有 | 正常：SwiftData 相关测试已 skip；主包可装 |
| 巨魔装完闪退 | 看系统版本是否 ≥16；用 mac 控制台或 `os_log` 抓崩溃（可再开 crash 收集 workflow） |
| 与原版同 Bundle ID 冲突 | 改 `project.yml` 的 `PRODUCT_BUNDLE_IDENTIFIER` 后重编 |

## 推送示例（在本机已改好的 source 目录）

```bash
# 新建自己的空仓库后：
git remote rename origin upstream   # 可选：保留上游
git remote add origin https://github.com/<你>/TiebaPure-iOS-ios16.git
git checkout -b ios16
git add -A
git commit -m "feat: lower deployment target to iOS 16 and add IPA workflow"
git push -u origin ios16
```

然后到 GitHub Actions 跑 **Build Unsigned IPA**。
