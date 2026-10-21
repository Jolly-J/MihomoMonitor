//
//  TrafficModels.swift
//  MihomoMonitor
//
//  [架构层级] Feature / ProxyTraffic / 领域模型
//  [核心职责] 定义代理流量监控业务的数据契约，包含时间窗口范围、导航项枚举、聚合统计条目与活动连接展示模型。
//  [关键类型] TimeRange, NavItem, TrafficStatItem, ActiveConnItem, ConnectionLogItem
//  [依赖关系] 依赖 Foundation、AppKit；被 TrafficViewModel、DatabaseManager 及各 Row 视图引用。
//  [并发安全] 纯值类型（Struct / Enum），天然线程安全并符合 Sendable 规范。
//

import Foundation
import AppKit

// MARK: - Time Range
nonisolated enum TimeRange: String, CaseIterable, Identifiable {
    case today = "今天"
    case week = "近7天"
    case all = "全部"
    
    var id: String { rawValue }
    
    var startDate: Date {
        let calendar = Calendar.current
        let now = Date()
        switch self {
        case .today:
            return calendar.startOfDay(for: now)
        case .week:
            // 修正：从今天零点往前推6天，加上今天刚好是完整的7个日历日
            return calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now
        case .all:
            return Date.distantPast
        }
    }
}

// MARK: - Navigation Tabs
nonisolated enum MonitorTab: String, CaseIterable, Identifiable {
    case apps = "应用"
    case domains = "域名"
    case proxies = "节点"
    case active = "活跃"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .apps: return "app.badge"
        case .domains: return "globe"
        case .proxies: return "point.3.connected.trianglepath.dotted"
        case .active: return "bolt.horizontal.fill"
        }
    }
}

// MARK: - App Traffic Stat
nonisolated struct AppTrafficStat: Identifiable {
    var id: String { appName }
    let appName: String
    let uploadBytes: Int64
    let downloadBytes: Int64
    let totalBytes: Int64
    let percentage: Double
}

// MARK: - Domain Traffic Stat
nonisolated struct DomainTrafficStat: Identifiable {
    var id: String { host }
    let host: String
    let uploadBytes: Int64
    let downloadBytes: Int64
    let totalBytes: Int64
    let percentage: Double
}

// MARK: - Proxy Traffic Stat
nonisolated struct ProxyTrafficStat: Identifiable {
    var id: String { nodeName }
    let nodeName: String
    let uploadBytes: Int64
    let downloadBytes: Int64
    let totalBytes: Int64
    let percentage: Double
}

// MARK: - Active Connection Item
nonisolated struct ActiveConnItem: Identifiable {
    let id: String
    let appName: String
    let host: String
    let destinationIP: String
    let proxyNode: String
    let rule: String
    let uploadSpeed: Int64
    let downloadSpeed: Int64
    let uploadTotal: Int64
    let downloadTotal: Int64
    let startTime: Date
}

// MARK: - Durable sampling contract
/// 单个快照的累计计数；以核心连接 ID 和原始 start 字段共同标识，重启后仍可去重。
nonisolated struct TrafficCheckpoint: Sendable {
    let connectionID: String
    let startToken: String
    let appName: String
    let host: String
    let destinationIP: String
    let proxyNode: String
    let upload: Int64
    let download: Int64
    let startedAt: Date
    let observedAt: Date
    let isClosed: Bool

    /// JSON 数组编码避免 ID / 时间串拼接产生分隔符碰撞。
    var identity: String {
        let data = try! JSONEncoder().encode([connectionID, startToken])
        return String(decoding: data, as: UTF8.self)
    }
}

/// 同一次数据库队列读取返回的报表快照，便于 ViewModel 拒绝过时结果及注入临时数据测试。
nonisolated struct DashboardStats {
    var apps: [AppTrafficStat] = []
    var domains: [DomainTrafficStat] = []
    var proxies: [ProxyTrafficStat] = []
    var summary: (upload: Int64, download: Int64) = (0, 0)
    var allTimeSummary: (upload: Int64, download: Int64) = (0, 0)
}
