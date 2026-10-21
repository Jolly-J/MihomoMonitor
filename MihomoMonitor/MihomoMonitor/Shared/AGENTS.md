# Shared 共享模块规范文档 (AGENTS.md)

本目录承载跨模块复用的基础组件、格式化工具、图标缓存机制与全局数据类型定义。

---

## 一、目录职责与边界

- **跨模块复用**：为 `App`、`ProxyTraffic`、`SystemMonitor` 等上层业务模块提供通用的基础支撑。
- **无状态与高性能工具**：数据格式化工具只提供纯计算逻辑，不持有可变状态。
- **资源缓存优化**：提取 macOS 原生图标并进行内存双层缓存，避免重复 I/O 与高频主线程图像解码。

---

## 二、包含文件及其职能

| 文件名 / 路径 | 核心定位 | 核心职责与关键类型 | 协作对象与依赖 |
| :--- | :--- | :--- | :--- |
| `FormatUtils.swift` | 格式化工具集 | 静态工具类 `FormatUtils`，负责速率（KB/s、MB/s）、存储容量（Bytes、MB、GB）、百分比及时间的格式化转换。 | `Foundation` |
| `AppIconProvider.swift` | 图标缓存服务 | 负责从 macOS 系统通过 Bundle Identifier 或可执行路径提取原生应用图标，内置 `NSCache` 双层缓存机制。 | `AppKit`, `SwiftUI` |
| `MainViewMode.swift` | 顶层领域枚举 | 定义主面板顶级工作模式 `MainViewMode`（`.proxy` 代理流量 / `.system` 系统监控）。 | `Foundation` |
| `Components/AppIconBadgeView.swift` | 基础 UI 组件 | 代理流量模块专用的进程图标展示视图，带有标准圆角与降级回退占位图。 | `SwiftUI`, `AppIconProvider` |
| `Components/SystemAppIconBadgeView.swift` | 基础 UI 组件 | 系统监控模块专用的进程图标展示视图，结合 PID、路径与名称解析系统应用图标。 | `SwiftUI`, `AppIconProvider` |

---

## 三、代码开发规范

1. **零外部业务耦合**：
   - `Shared` 目录内的代码禁止引用任何业务层 ViewModel 或 Feature 视图，仅依赖基础系统库（Foundation、AppKit、SwiftUI）。
2. **轻量与高响应性**：
   - 图标加载与渲染必须具备内存缓存，缺失图标时应优雅降级为 SF Symbols 占位图标，不得阻塞 UI。
3. **注释要求**：
   - 工具函数必须包含明确的参数说明、返回值单位（如 Bytes 转 GB 逻辑）和极端边界值处理（如 0 值或超大值）的注释说明。
