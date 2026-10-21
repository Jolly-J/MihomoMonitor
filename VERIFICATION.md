# MihomoMonitor 原项目应用与验证记录

修复已于 2026-10-21 应用到原项目 `/Users/Python/Mihomo monitor`，其中 Xcode 工程为 `MihomoMonitor/MihomoMonitor.xcodeproj`。

应用前再次确认原目录与任务开始时一致，没有用户新增代码改动；先完成冲突检查，再移植此前验证过的修复。应用后逐一校验 16 个源码和测试文件的 SHA-256，全部与隔离副本一致，且检查确认没有混入其他文件改动。以下记录为第 17 个文件。

原隔离目录 `/Users/jolin/Documents/Codex/2026-10-21/task/MihomoMonitor` 保留用于核对。没有提交、上传、合并、发布或创建远程审阅，没有启动、替换或安装应用，也没有安装软件或改变系统安全和网络设置。

## 应用结果

七项修复均已移植：活动连接批量增量检查点及跨日分配、数据库批量原子事务和幂等重试、最新筛选与范围标签、可见性和数据变化驱动展示查询、端点失败退避重探测、数据库先筛选后取前 50 个域名及输入防抖、系统指标单次发布。另包括失败轮询的速率时间修正和缺失图标短时缓存。

采样仍约 1.5 秒；保存约 15 秒一批，跨日和正常退出也保存。提交失败保留待写数据，正常退出若反复保存失败则取消退出并提示原因。保留现有轻量 MVVM 和 Feature 分层。

## 原目录实际验证

执行环境为 Xcode 27.1、Apple Swift 6.4、arm64 macOS。Xcode MCP BuildProject 不可用，使用现有 xcodebuild。以下命令在 `/Users/Python/Mihomo monitor` 执行：

```sh
xcodebuild -project MihomoMonitor/MihomoMonitor.xcodeproj \
  -scheme MihomoMonitor -configuration Debug \
  -derivedDataPath .build/verified-repair-20261021/DerivedData \
  CODE_SIGNING_ALLOWED=NO build

Tests/run-regressions.sh

git diff --check
```

结果：

- 构建 `BUILD SUCCEEDED`，0 Errors，无 Swift 并发警告。保留原有 AppIcon 未分配资源警告，以及无 AppIntents.framework 依赖的元数据提示。
- 回归 **7 组、36 条断言通过**：跨日/夏令时守恒、重开数据库与 Tracker 重启去重、旧数据兼容、连接 ID 复用、写入失败三表整批回滚和幂等重试、第 51 个域名搜索、快速切范围、搜索防抖、隐藏查询暂停/恢复、无变化轮询不查询、离线先启动与端点重连、失败轮询速率分母、活动/关闭连接失败重试、15 秒活动检查点。
- 差异格式检查通过。源码和测试内容与已验证副本逐一一致。
- 测试数据仅在随机临时目录中创建，结束后清理；HTTP 请求由内存 URLProtocol 替身拦截。测试时区仅设置到测试进程。未读写真实流量数据库，未连接真实代理。

原目录日志：`.build/verified-repair-20261021/build.log`、`.build/verified-repair-20261021/regressions.log`。构建产物位于同一独立子目录，未替换既有应用。

## 改动文件

路径相对于原项目根目录。

| 文件 | 改动 |
| --- | --- |
| `MihomoMonitor/MihomoMonitor/Services/TrafficTracker.swift` | actor 采集、批量检查点、成功确认、重试及退出保存 |
| `MihomoMonitor/MihomoMonitor/Persistence/DatabaseManager.swift` | 事务、水位、分日、SQL 搜索、临时数据库注入 |
| `MihomoMonitor/MihomoMonitor/Services/Mihomo/MihomoClient.swift` | 端点失效、退避、重探测及 Socket 错误处理 |
| `MihomoMonitor/MihomoMonitor/Services/Mihomo/MihomoAPIModels.swift` | 非主线程协议模型与 Sendable |
| `MihomoMonitor/MihomoMonitor/Services/ProcessResolver.swift` | 显式 nonisolated，继续由既有锁保护 |
| `MihomoMonitor/MihomoMonitor/Features/ProxyTraffic/TrafficModels.swift` | 检查点和报表快照数据契约 |
| `MihomoMonitor/MihomoMonitor/Features/ProxyTraffic/TrafficViewModel.swift` | 最新筛选、可见性、数据变化驱动及搜索防抖 |
| `MihomoMonitor/MihomoMonitor/Features/ProxyTraffic/Views/TrafficDashboardView.swift` | 范围标签与状态详情 |
| `MihomoMonitor/MihomoMonitor/App/ContentView.swift` | 新状态接线、窗口可见性、估算限制提示 |
| `MihomoMonitor/MihomoMonitor/App/PanelVisibilityObserver.swift`（新增） | 原生窗口可见性适配 |
| `MihomoMonitor/MihomoMonitor/App/AppDelegate.swift` | 异步退出保存协议 |
| `MihomoMonitor/MihomoMonitor/AppState.swift` | 可见性/模式路由及连接错误转发 |
| `MihomoMonitor/MihomoMonitor/Services/SystemMetricsCollector.swift` | 移除重复发布路径 |
| `MihomoMonitor/MihomoMonitor/Shared/AppIconProvider.swift` | 有时限的缺失图标缓存与路径优先 |
| `Tests/RegressionTests.swift`（新增） | 临时数据回归程序 |
| `Tests/run-regressions.sh`（新增） | 使用项目源码编译并运行测试 |
| `VERIFICATION.md`（新增） | 本记录 |

## 验证范围和剩余限制

数据库、采集器、客户端和 ViewModel 已实际执行临时数据回归；界面、原生窗口通知、系统指标单次发布、图标缓存已编译并静态检查，未启动菜单栏应用人工联调，也未验证真实 Unix Socket / 真实代理重启。未进行性能基准，未声称性能提升百分比。

快照间出现又消失的短连接、最后一次快照之后的尾流量不能恢复。首次观察前、断线期间及跨午夜的流量发生时间只能按累计值和时间比例估算；这是快照估算，不是完整网络计量。正常退出会等待保存，强制结束、崩溃或断电仍可能丢失最近一个未保存批次内、之后无法再观察到的流量。

旧日统计保留，旧版本按关闭日累计的数据无法准确追溯重分。幂等水位元数据随连接数增长；持续写入失败时未确认连接也可能继续增长。计量依赖核心稳定 ID + start 和累计计数；相同身份的计数回退保留已有最大水位，不能推断未知重置流量。要求认证的端点在无正确凭据时仍会报错，本次没有读取或修改用户代理配置获取凭据。

当前没有权限、冲突或执行环境阻塞。
