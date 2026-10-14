//
//  Models.swift
//  MihomoMonitor
//
//  Created by Jo lin on 2026/10/14.
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
            return calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now)) ?? now
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

// MARK: - Mihomo JSON API Models
struct MihomoConnectionsSnapshot: Decodable {
    let downloadTotal: Int64
    let uploadTotal: Int64
    let connections: [MihomoRawConnection]
}

struct MihomoRawConnection: Decodable {
    let id: String
    let upload: Int64
    let download: Int64
    let start: String
    let chains: [String]?
    let rule: String?
    let rulePayload: String?
    let metadata: MihomoMetadata
}

struct MihomoMetadata: Decodable {
    let network: String?
    let type: String?
    let sourceIP: String?
    let destinationIP: String?
    let sourcePort: String?
    let destinationPort: String?
    let inboundPort: String?
    let inboundName: String?
    let host: String?
    let process: String?
    let processPath: String?
}

// MARK: - Closed Connection for DB
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

// MARK: - Format Utilities
enum FormatUtils {
    static func formatBytes(_ bytes: Int64) -> String {
        let b = Double(max(0, bytes))
        if b < 1024 {
            return "\(Int(b))\u{00A0}B"
        } else if b < 1024 * 1024 {
            return String(format: "%.1f\u{00A0}KB", b / 1024.0)
        } else if b < 1024 * 1024 * 1024 {
            return String(format: "%.2f\u{00A0}MB", b / (1024.0 * 1024.0))
        } else {
            return String(format: "%.2f\u{00A0}GB", b / (1024.0 * 1024.0 * 1024.0))
        }
    }
    
    static func formatSpeed(_ bytesPerSec: Int64) -> String {
        return "\(formatBytes(bytesPerSec))/s"
    }
    
    static func splitSpeed(_ bytesPerSec: Int64) -> (value: String, unit: String) {
        let b = Double(max(0, bytesPerSec))
        if b < 1024 {
            return ("\(Int(b))", "B/s")
        } else if b < 1024 * 1024 {
            return (String(format: "%.1f", b / 1024.0), "KB/s")
        } else if b < 1024 * 1024 * 1024 {
            return (String(format: "%.1f", b / (1024.0 * 1024.0)), "MB/s")
        } else {
            return (String(format: "%.2f", b / (1024.0 * 1024.0 * 1024.0)), "GB/s")
        }
    }
    
    static func splitBytes(_ bytes: Int64) -> (value: String, unit: String) {
        let b = Double(max(0, bytes))
        if b < 1024 {
            return ("\(Int(b))", "B")
        } else if b < 1024 * 1024 {
            return (String(format: "%.1f", b / 1024.0), "KB")
        } else if b < 1024 * 1024 * 1024 {
            return (String(format: "%.2f", b / (1024.0 * 1024.0)), "MB")
        } else {
            return (String(format: "%.2f", b / (1024.0 * 1024.0 * 1024.0)), "GB")
        }
    }
    
    static func todayDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
