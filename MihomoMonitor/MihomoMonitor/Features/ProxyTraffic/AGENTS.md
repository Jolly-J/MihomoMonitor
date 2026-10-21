# ProxyTraffic 代理流量模块规范文档 (AGENTS.md)

本模块负责代理流量监控相关的所有业务逻辑、领域模型和界面交互展示。

---

## 一、模块职责与功能边界

- **实时速率呈现**：展示当前内核的实时上传速度与下载速度（KB/s、MB/s 自适应转换）。
- **活动连接监控**：呈现当前保持活跃的 TCP/UDP 连接清单，包括源进程、目标地址、代理链策略及实时传输量。
- **历史多维报表**：支持按四个时间维度（1小时 / 24小时 / 7天 / 全部历史）异步从 SQLite 聚合统计流量数据，并按不同视图呈现：
  - 应用流量排行（显示应用图标、名称、上下行流量及占比进度条）。
  - 域名流量排行（显示二级域名、请求次数及消耗流量）。
  - 代理节点统计（显示出站节点与直连流量统计）。
  - 连接明细报表（显示历史连接完整日志）。

---

## 二、包含文件及其职能

| 文件名 / 路径 | 架构定位 | 核心职责与关键类型 | 协作对象与依赖 |
| :--- | :--- | :--- | :--- |
| `TrafficModels.swift` | 领域模型 | 定义 `TrafficStatItem`、`ConnectionLogItem`、`ActiveConnItem` 等数据模型及 `TimeRangeOption`、`NavSelection` 枚举。 | `Foundation` |
| `TrafficViewModel.swift` | 业务状态机 | 声明为 `@MainActor`，持有当前时间范围、导航选项与统计数据；负责异步调用 `DatabaseManager` 拉取报表并刷新 UI。 | `DatabaseManager`, `TrafficModels` |
| `Views/TrafficNavigationView.swift` | 业务侧边栏 | 渲染应用、域名、代理节点、连接明细等筛选入口，支持显示当前总流量统计摘要。 | `TrafficViewModel` |
| `Views/TrafficDashboardView.swift` | 业务仪表盘 | 主展示容器，包含实时速率卡片、时间区间分段选择器（Segmented Control）以及动态切换的内容列表。 | `TrafficViewModel`, 各子 Row 视图 |
| `Views/AppTrafficRow.swift` | 列表单行组件 | 渲染单个应用的流量使用情况（图标、名称、用量数据及动态占比进度条）。 | `TrafficStatItem`, `AppIconBadgeView`, `FormatUtils` |
| `Views/DomainTrafficRow.swift` | 列表单行组件 | 渲染目标域名的请求频次与流量消耗。 | `TrafficStatItem`, `FormatUtils` |
| `Views/ProxyTrafficRow.swift` | 列表单行组件 | 渲染代理节点或 Direct 策略的流量消耗排行。 | `TrafficStatItem`, `FormatUtils` |
| `Views/ActiveConnectionRow.swift` | 列表单行组件 | 渲染当前正在活动的网络连接详情（源、目标、链节点、当前流速）。 | `ActiveConnItem`, `FormatUtils` |

---

## 三、代码开发规范

1. **异步数据加载**：
   - 切换时间维度或刷新数据时，必须调用 `TrafficViewModel.shared.refreshStats()`，在内部由后台线程查询 SQLite，查询完成后切回主线程赋值给 `@Published` 属性。
2. **列表动效规范**：
   - 在时间维度切换导致排行顺序改变时，应通过 `withAnimation` 保留列表元素位移平移动效。
3. **注释要求**：
   - 任何新增的统计维度、过滤枚举值或数据计算公式，必须编写标准行间注释说明。
