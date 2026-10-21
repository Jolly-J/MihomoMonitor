# SystemMonitor 系统性能监控模块规范文档 (AGENTS.md)

本模块负责 macOS 本机系统级与进程级性能指标的呈现与交互逻辑。

---

## 一、模块职责与功能边界

- **全局资源仪表盘**：
  - 实时呈现主机总体 CPU 占用百分比（计算公式基于 Darwin 纯原生 `host_statistics64`）。
  - 实时呈现系统物理内存使用概况（已用内存与总内存的真实物理数值，如 18.2 GB / 36.0 GB）。
- **进程级排行列表**：
  - 支持按 CPU 绝对算力消耗排序（显示全核归一化的真实算力占比百分比）。
  - 支持按物理内存驻留集（RSS）排序（显示实际占用的物理内存量，如 1.4 GB）。
  - 列表行采用平滑动画进行排序重排，配备自适应占比进度条。
- **惰性按需调度**：
  - 仅在用户切换至系统监控视图时才通过 `start()` 启动底层采集服务；离开时通过 `stop()` 挂起，确保零不必要功耗。

---

## 二、包含文件及其职能

| 文件名 / 路径 | 架构定位 | 核心职责与关键类型 | 协作对象与依赖 |
| :--- | :--- | :--- | :--- |
| `SystemModels.swift` | 领域模型 | 定义 `SystemGlobalMetrics`、`SystemProcessMetric`、`SystemTimeRange`、`SystemSortOption` 等数据契约。 | `Foundation`, `ProcessResolver` |
| `SystemMonitorViewModel.swift` | 业务状态机 | 声明为 `@MainActor`，管理当前系统监控状态、排序方式（CPU / 内存），编排 `SystemMetricsCollector` 的按需启停与节流更新。 | `SystemMetricsCollector`, `SystemModels` |
| `Views/SystemNavigationView.swift` | 业务侧边栏 | 渲染 CPU 监控与内存监控两大子维度导航入口，支持点击切换主排序列。 | `SystemMonitorViewModel` |
| `Views/SystemDashboardView.swift` | 业务仪表盘 | 主展示容器，包含全局 CPU/内存实时指标卡片、活跃进程总数提示，以及带有排序动效的进程排行榜。 | `SystemMonitorViewModel`, `SystemProcessRow` |
| `Views/SystemProcessRow.swift` | 列表单行组件 | 渲染单个系统进程资源消耗，支持应用图标、PID、进程名，以及根据当前排序模式显示绝对 CPU 百分比或物理内存量，并带有动态进度条。 | `SystemProcessMetric`, `SystemAppIconBadgeView`, `FormatUtils` |

---

## 三、代码开发规范

1. **绝对算力与内存显示规范**：
   - CPU 算力显示采用整机绝对占比（`0% ~ 100%`），严禁出现多核累加导致超过 100% 的误导性数据。
   - 内存占用统一显示真实物理数值（GB 或 MB），辅助提示当前总可用物理内存。
2. **列表重排平滑动画**：
   - 进程列表更新时必须使用 `withAnimation(.easeInOut(duration: 0.3))`，确保不同采样周期间进程位置调整拥有丝滑自然的视觉位移动效。
3. **注释要求**：
   - 新增系统性能计算公式、排序策略或 UI 样式变更时，必须在代码块顶部标明设计意图与计算边界。
