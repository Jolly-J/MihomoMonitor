# Mihomo 适配层规范文档 (AGENTS.md)

本目录封装与本地代理内核（Mihomo / Clash Verge）的全部网络协议通信逻辑与数据反序列化模型。

---

## 一、目录职责与边界

- **端点自动探测与健康检查**：自动探测 Clash Verge / Mihomo 的默认外部控制器端点（如 `127.0.0.1:9097`、`127.0.0.1:9090`），并在断线时自动执行重连探测。
- **协议适配**：
  - RESTful HTTP API：获取版本信息、当前活跃连接快照 (`/connections`)。
  - WebSocket：订阅实时流量速率流 (`/traffic`)。
- **数据结构契约**：将原始 JSON 报文解码转换为强类型的 Swift 模型，屏蔽底层数据差异。

---

## 二、包含文件及其职能

| 文件名 | 核心定位 | 核心职责与关键类型 | 协作对象与依赖 |
| :--- | :--- | :--- | :--- |
| `MihomoClient.swift` | API 客户端 | 负责 HTTP/WebSocket 通信、端口探测、自动重连与连接数据拉取。核心类 `MihomoClient`（单例）。 | `URLSession`, `Foundation`, `MihomoAPIModels` |
| `MihomoAPIModels.swift` | 数据契约模型 | 遵循 `Codable` 协议，定义原生报文结构（`MihomoConnectionsResponse`, `MihomoConnectionItem`, `MihomoMetadata` 等）。 | `Foundation` |

---

## 三、代码开发规范

1. **容错与静默失败**：
   - 当本地 Mihomo 内核未启动时，客户端应维持重试机制并优雅降级，不得造成应用崩溃或卡顿。
2. **连接泄漏防护**：
   - WebSocket 重新连接或端点切换时，必须主动关闭旧连接并释放监听回调。
3. **注释要求**：
   - 新增 API 接口或解析字段必须在 `MihomoAPIModels.swift` 中标注对应的 Mihomo 官方接口文档字段含义。
