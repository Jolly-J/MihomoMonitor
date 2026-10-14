# 更新日志 (Changelog)

本项目遵循 [Semantic Versioning (语义化版本 2.0.0)](https://semver.org/lang/zh-CN/) 与 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 规范。

---

## 规范约定

每个版本的变更记录按以下分类进行归组：

- **Added (新增)**：新功能或新特性。
- **Changed (变更)**：现有功能的修改或调整。
- **Deprecated (弃用)**：不推荐使用并计划在后续版本移除的特性。
- **Removed (移除)**：已移除的功能。
- **Fixed (修复)**：Bug 缺陷修复。
- **Security (安全)**：安全漏洞或隐私保护增强。

Git Commit 提交信息遵循 **Conventional Commits** 规范：
- `feat:` 新增功能
- `fix:` 缺陷修复
- `docs:` 文档变更
- `style:` 代码格式/样式优化（不影响代码运行逻辑）
- `refactor:` 代码重构（既不修复 bug 也不增加新功能）
- `perf:` 性能提升
- `chore:` 构建流程或辅助工具变动

---

## [0.1-beta] - 2026-10-14

### 🚀 首个开源公开测试版 (Initial Open-Source Beta Release)

这是 Mihomo Monitor 的首个正式开源预览版本，专为 macOS 设计，专注于解决代理流量与 AI / Agent 工具流量黑盒痛点。

### ✨ Added (新增)
- **纯代理流量过滤引擎**：自动识别并剔除 Direct（直连）与 Reject（阻断）请求，100% 聚焦走机场代理节点的真实出海流量。
- **进程级应用精准归因**：
  - 支持系统代理模式与 TUN 模式，自动通过底层端口反查连接所属进程。
  - 完美识别主流 AI 辅助工具（Cursor、Claude Code、Aider 等）及后台终端脚本。
  - 自动提取 macOS 原生高清应用图标；对于 CLI 命令行与系统进程，智能匹配专属终端与网络标识。
- **四大核心透视视图**：
  - **应用（Apps）**：统计各软件的上传、下载总量、占比进度条与瞬时速率。
  - **域名（Domains）**：聚合统计大模型 API 及各出海网站流量，支持域名即时搜索与一键复制。
  - **节点（Proxies）**：统计各个机场节点的流量分流比例与负载。
  - **活跃（Active）**：实时追踪当前正在传输的活跃长连接及其上下行速率。
- **轻量本地持久化账本**：
  - 基于 macOS 原生 SQLite3（开启 WAL 极速模式），断电断网不丢账本。
  - 支持查看「今天」、「近 7 天」和「历史全部」三种时间维度。
  - 100% 本地存储，不包含任何外部网络上报，保护用户隐私。
- **原生 macOS 菜单栏体验**：
  - 基于 SwiftUI 开发，常驻菜单栏（`LSUIElement = true`），无需常驻 Dock 栏。
  - 顶部指标大卡片接入苹果官方数字轮盘（Odometer）滑入翻转动效，平滑丝滑。
  - 全局应用 `.monospacedDigit()` 等宽数字排版，杜绝数字跳动时文字左右位移晃动。
  - 完美跟随系统浅色 / 深色模式自适应，实体底色杜绝穿透泛黑。
- **零侵入开箱即用**：自动探测并直连 Clash Verge Rev / Mihomo 核心的 Unix Domain Socket，无需配置端口或安装根证书。
- **品牌视觉与专属打包**：
  - 内置多领国（Duolingo）质感的 3D 萌猫图标，适配 macOS AppIcon 规格。
  - 提供带拖拽指引箭头的标准 macOS `.dmg` 安装镜像与绿色 `.zip` 压缩包。
