# App 模块规范文档 (AGENTS.md)

本目录承载 macOS 应用的生命周期管理、菜单栏常驻交互以及顶层主面板视图容器。

---

## 一、目录职责与边界

- **生命周期调度**：管理应用从启动、菜单栏图标初始化、窗口唤醒/折叠到退出的完整流程。
- **顶层视图宿主**：作为主面板的框架容器，承载顶层模式切换器（代理流量 / 系统监控），并分别容纳两个业务模块的侧边栏与仪表盘。
- **状态聚合与路由**：通过 `AppState` 协调顶层业务模式切换，并触发各 Feature ViewModel 的按需启停。

---

## 二、包含文件及其职能

| 文件名 | 架构定位 | 核心职责与关键类型 | 协作对象与依赖 |
| :--- | :--- | :--- | :--- |
| `MihomoMonitorApp.swift` | App 入口 | SwiftUI `@main` 结构体，声明应用生命周期并绑定 `AppDelegate`。 | `AppDelegate`, `ContentView`, `AppState` |
| `AppDelegate.swift` | 宿主生命周期 | `NSApplicationDelegate` 实现，负责 macOS 菜单栏图标创建、点击呼出悬浮窗口、窗口置顶以及后台服务引导。 | `NSStatusBar`, `TrafficTracker`, `ContentView` |
| `ContentView.swift` | 主窗口容器 | 顶层根视图，渲染顶部模式切换器（`MainModeSwitcher`）、统筹子模块 NavigationView / DashboardView 及底部退出菜单。 | `AppState`, `TrafficNavigationView`, `SystemNavigationView` |

---

## 三、代码开发规范

1. **窗口与交互规范**：
   - 菜单栏弹出窗口应响应点击外部自动关闭（或失焦关闭），点击菜单项与模式切换器应保持流畅响应。
   - 模式切换必须通过 `AppState.shared.mainMode` 进行单向数据流驱动。
2. **生命周期规范**：
   - 严禁在 `AppDelegate` 中直接执行耗时网络请求或数据库写入，初始化时只注册调度与配置项。
   - 应用退出时触发资源保存与连接清理。
3. **注释要求**：
   - 任何涉及窗口样式调整（`NSWindow`、`NSPanel`）、快捷键监听或状态栏事件的代码必须包含清晰的注释说明。
