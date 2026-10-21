# Features 业务模块总览 (AGENTS.md)

本目录承载 MihomoMonitor 的所有核心业务功能模块。各个业务模块之间物理隔离、保持高内聚，遵循轻量 MVVM 模式进行设计。

---

## 一、模块划分与业务边界

当前包含两个核心独立业务模块：

1. **`ProxyTraffic/`（代理流量监控模块）**：
   - 聚焦代理内核的流量指标采集与呈现。
   - 包含实时上下行网速、活动连接实时列表，以及基于 SQLite 归档的多时间维度（1小时/24小时/7天/全部）报表（应用用量排行、目标域名排行、代理出站节点排行）。
2. **`SystemMonitor/`（系统性能监控模块）**：
   - 聚焦 macOS 本地主机的实时系统指标监控。
   - 包含全核 CPU 负载、物理内存实时占用，以及按绝对算力或内存占用排序的高能耗进程实时排行榜（提供平滑排序动画）。

---

## 二、Feature 设计规范

每个独立的 Feature 必须遵循以下子目录结构：

```
FeatureName/
├── Views/              # 专属于该业务的 SwiftUI 视图组件与单行渲染单元
├── FeatureViewModel.swift  # 驱动该业务的状态机，标记为 @MainActor
└── FeatureModels.swift     # 专属于该业务的领域数据结构与过滤枚举
```

### 协作与约束原则：
- **独立状态机**：每个 Feature 拥有专属的 ViewModel（例如 `TrafficViewModel` 与 `SystemMonitorViewModel`），互不强引用，避免业务逻辑相互污染。
- **状态单向流**：View 层只监听 ViewModel 的 `@Published` 属性，用户操作通过 ViewModel 暴露的方法发起。
- **无状态行组件**：`Views/` 下的列表项视图（如 `AppTrafficRow`、`SystemProcessRow`）保持为纯粹的受控组件，只接收模型和排版参数进行渲染。
- **注释要求**：所有新增业务模型属性、过滤选项枚举值以及 ViewModel 的刷新方法，必须附带规范的文档注释。
