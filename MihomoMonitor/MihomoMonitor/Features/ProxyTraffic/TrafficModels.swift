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
enum TimeRange: String, CaseIterable, Identifiable {
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
enum MonitorTab: String, CaseIterable, Identifiable {
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
struct AppTrafficStat: Identifiable {
    var id: String { appName }
    let appName: String
    let uploadBytes: Int64
    let downloadBytes: Int64
    let totalBytes: Int64
    let percentage: Double
}

// MARK: - Domain Traffic Stat
struct DomainTrafficStat: Identifiable {
    var id: String { host }
    let host: String
    let uploadBytes: Int64
    let downloadBytes: Int64
    let totalBytes: Int64
    let percentage: Double
}

// MARK: - Proxy Traffic Stat
struct ProxyTrafficStat: Identifiable {
    var id: String { nodeName }
    let nodeName: String
    let uploadBytes: Int64
    let downloadBytes: Int64
    let totalBytes: Int64
    let percentage: Double
}

// MARK: - Active Connection Item
struct ActiveConnItem: Identifiable {
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

// MARK: - Closed Connection Record (Persistence)
struct ClosedConnectionRecord {
    let id: String
    let dateStr: String
    let appName: String
    let host: String
    let destinationIP: String
    let proxyNode: String
    let uploadBytes: Int64
    let downloadBytes: Int64
    let startTime: Int64
    let endTime: Int64
}
