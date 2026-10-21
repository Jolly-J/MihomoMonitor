# Services 服务层规范文档 (AGENTS.md)

本目录承载所有非 UI 的后台常驻调度器、网络协议通信与操作系统底层数据采集服务。

---

## 一、目录职责与边界

- **纯业务与底层接口**：服务层禁止引入任何 SwiftUI 视图代码，保持纯 Swift 逻辑，便于单元测试与独立生命周期管理。
- **并发与定时采样**：使用独立的后台 GCD 队列或异步 Task 处理数据采集，不阻塞主线程。
- **采集适配与解析**：
  - 与外部内核交互（Mihomo API）。
  - 与操作系统底层交互（Darwin C API 算力与内存采集）。
  - 进程信息解析（PID 转换为应用名与 Bundle ID）。

---

## 二、包含文件及其职能

| 文件名 / 路径 | 核心定位 | 核心职责与关键类型 | 协作对象与依赖 |
| :--- | :--- | :--- | :--- |
| `Services/Mihomo/` | 协议适配 | 负责与 Mihomo/Clash Verge 内核通信（详见子目录 `Mihomo/AGENTS.md`）。 | `URLSession`, `Foundation` |
| `TrafficTracker.swift` | 流量采集编排 | 长驻后台轮询调度器，定期从 `MihomoClient` 获取连接列表，计算闭环连接流量增量并批量写入 `DatabaseManager`。 | `MihomoClient`, `ProcessResolver`, `DatabaseManager`, `TrafficViewModel` |
| `SystemMetricsCollector.swift` | 系统底层指标采集 | 使用 Darwin 原生 C API（`mach_absolute_time`, `host_statistics64`, `libproc`）采集主机与进程级 CPU/内存，按需启停，零子进程开销。 | `Darwin`, `ProcessResolver`, `SystemModels` |
| `ProcessResolver.swift` | 进程解析器 | 负责将 PID 或可执行文件绝对路径解析为 macOS 友好应用名称与 Bundle ID，内置线程安全的并发读写缓存。 | `AppKit`, `Darwin` |

---

## 三、代码开发规范

1. **绝对禁止子进程开销**：
   - 严禁使用 `Process()` / `bash` / `top` / `ps` 采集系统数据，必须使用 Darwin 原生 C 结构体和系统调用，以确保常驻监控下的极低能耗与高稳定性。
2. **生命周期按需管理**：
   - 系统监控采集器（`SystemMetricsCollector`）必须支持 `start()` 和 `stop()` 方法，在无活跃展示时不消耗任何 CPU 时间。
3. **线程安全规范**：
   - `ProcessResolver` 等共享缓存工具必须具备明确的线程安全保护机制（如串行队列或读写锁）。
4. **注释要求**：
   - 任何涉及底层 Darwin C 指针操作（如 `proc_pidinfo`、`mach_timebase_info`）的代码必须提供详尽的行间注释，注明内存布局与数据单位转换。
