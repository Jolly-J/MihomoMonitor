# AGENTS.md - MihomoMonitor 项目工程架构与协作开发规范

本项目为 macOS 平台轻量级代理流量与系统监控状态栏应用，使用 Swift + SwiftUI 开发，底层结合 SQLite3 持久化与 Darwin 原生 C 接口采集系统算力。

本规范用于指导开发与多智能体（Agents）协作，确保项目在功能扩展、重构和维护过程中保持高内聚、低耦合、线程安全与强注释规范。

---

## 一、项目架构分层（Architectural Layering）

项目遵循 **按业务功能组织 + 轻量 MVVM** 分层架构，严格禁止跨层逆向调用或在 View 中直接操作底层基础设施：

```
MihomoMonitor/
├── App/                # 应用入口、菜单栏宿主、AppDelegate 生命周期与主窗口容器
├── Features/           # 业务功能模块（按 Feature 独立组织，内聚 View / ViewModel / Model）
│   ├── ProxyTraffic/   # 代理流量监控业务（应用、域名、代理节点统计及连接明细）
│   └── SystemMonitor/  # 系统性能监控业务（全核算力 CPU、物理内存占用及进程排行榜）
├── Services/           # 底层数据采集与后台轮询服务（纯业务逻辑，与 UI 解耦）
│   └── Mihomo/         # Mihomo / Clash Verge 核心 API 通信与数据契约
├── Persistence/        # SQLite3 数据持久化、多维聚合查询与日志滚动清理
└── Shared/             # 共享工具类、图标缓存、基础枚举与可复用基础 UI 组件
```

### 分层依赖规则
1. **View（界面层）**：只负责声明式 UI 渲染与用户交互触发，只从 ViewModel 读取状态，禁止在 View 内直接执行数据库查询或启动后台服务。
2. **ViewModel（状态协调层）**：声明为 `@MainActor`，负责驱动界面响应式更新、持有过滤条件与时间维度，协调 Services 与 Persistence 层获取数据。
3. **Services（服务层）**：纯后台调度，使用内部定时器或 WebSocket 采集数据，计算增量后交付 Persistence 或通过 ViewModel 同步至 UI。
4. **Persistence（持久化层）**：以 `DatabaseManager` 为核心，通过专属串行 `DispatchQueue` 隔离并发，确保 SQLite 读写无死锁、无竞态。
5. **Shared（共享层）**：无状态工具方法（`FormatUtils`）、图标缓存（`AppIconProvider`）和通用视图（`AppIconBadgeView`），供上层各模块复用。

---

## 二、代码与注释规范（Code & Comment Specifications）

为了保证规范化开发，所有代码文件和新增代码块必须严格遵守以下规范：

### 1. 统一文件抬头注释模板（File Header Specification）
每一个 Swift 源文件开头必须包含标准化结构抬头注释，明确层级、职责、核心类型、依赖与并发特性：

```swift
//
//  FileName.swift
//  MihomoMonitor
//
//  [架构层级] Feature / Services / Persistence / Shared / App
//  [核心职责] 简要说明本文件的主要业务边界与实现目标
//  [关键类型] 列出核心 Class / Struct / Enum / Protocol
//  [依赖关系] 上游依赖与下游使用者说明
//  [并发安全] 线程安全模型（如 @MainActor、专属串行队列、线程安全锁等）
//
```

### 2. 函数与核心代码块注释规范（Function & Block Comments）
- **公开/核心 API**：必须使用 Swift 标准文档注释 `///` 说明函数作用、关键入参、返回值或副作用。
- **业务关键算法**：在计算增量、百分比公式、并发调度或内存转换处，必须提供行间注释 `//` 说明底层原理与取舍原因。
- **UI 布局分块**：复杂的 SwiftUI 视图必须使用 `// MARK: - xxx` 清晰分隔：顶部指标、过滤条、核心列表、行渲染、状态处理。
- **新增功能要求**：后续任何新增的代码块、类型、状态字段，严禁裸写无注释代码，必须说明用途。

---

## 三、性能与并发守则（Performance & Concurrency Guidelines）

1. **主线程隔离**：所有 UI 相关的 ViewModel 和 SwiftUI 视图必须标记 `@MainActor`。
2. **严禁主线程同步查询**：涉及 SQLite3 的统计查询（`fetchStats`）必须在后台串行队列异步执行，完成后切回主线程更新 `@Published` 属性。
3. **系统采集惰性调度**：系统监控模块（`SystemMetricsCollector`）在用户切换至系统监控视图时才启动轮询，离开时立即暂停，避免常驻消耗电量。
4. **原生 Darwin C API 采集**：系统指标必须使用 `mach_absolute_time()`、`host_statistics64`、`libproc` 等原生系统调用，严禁通过 `Process` 启动 `ps` / `top` / `lsof` 等子进程。
5. **SQLite 资源管理**：SQLite 文本绑定一律使用 `SQLITE_TRANSIENT`，严禁使用 `nil` 导致悬垂指针；内部私有查询方法严禁嵌套调用 `queue.sync`，避免可重入死锁。

---

## 四、验证标准（Verification Standard）

任何代码修改或重构后，必须通过 Xcode MCP 工具运行 `BuildProject` 验证编译。只有在保证 0 Errors 的前提下才能提交变更。
