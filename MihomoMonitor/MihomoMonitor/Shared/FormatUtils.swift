//
//  FormatUtils.swift
//  MihomoMonitor
//
//  [架构层级] Shared / 通用格式化工具
//  [核心职责] 提供速率（KB/s, MB/s）、存储字节（Bytes, MB, GB）、CPU 绝对百分比、时间戳的格式化与人机工效学文本转换。
//  [关键类型] FormatUtils（枚举无状态命名空间）
//  [依赖关系] 依赖 Foundation
//  [并发安全] 纯静态无状态无副作用函数，完全线程安全。
//

import Foundation

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
    
    // MARK: - System Metrics Formatting
    static func formatCpuPercent(_ percent: Double) -> String {
        if percent < 0.1 {
            return "<0.1%"
        } else {
            return String(format: "%.1f%%", percent)
        }
    }
    
    static func formatMemoryMBorGB(_ bytes: Int64) -> String {
        let b = Double(max(0, bytes))
        let gb = b / (1024.0 * 1024.0 * 1024.0)
        let mb = b / (1024.0 * 1024.0)
        
        if gb >= 1.0 {
            return String(format: "%.2f\u{00A0}GB", gb)
        } else if mb >= 1.0 {
            return String(format: "%.0f\u{00A0}MB", mb)
        } else {
            return String(format: "%.1f\u{00A0}MB", mb)
        }
    }
    
    static func splitMemoryMBorGB(_ bytes: Int64) -> (value: String, unit: String) {
        let b = Double(max(0, bytes))
        let gb = b / (1024.0 * 1024.0 * 1024.0)
        let mb = b / (1024.0 * 1024.0)
        
        if gb >= 1.0 {
            return (String(format: "%.1f", gb), "GB")
        } else if mb >= 1.0 {
            return (String(format: "%.0f", mb), "MB")
        } else {
            return (String(format: "%.1f", mb), "MB")
        }
    }
    
    static func formatBatteryStatus(isACPower: Bool, isCharging: Bool, batteryPercentage: Int, timeRemainingMinutes: Int?) -> String {
        if isACPower {
            if isCharging {
                return "⚡️ 正在充电 · \(batteryPercentage)%"
            } else {
                return "⚡️ 已连接电源 · \(batteryPercentage)%"
            }
        } else {
            if let mins = timeRemainingMinutes, mins > 0 {
                let h = mins / 60
                let m = mins % 60
                let timeStr = h > 0 ? "\(h)小时\(m)分" : "\(m)分钟"
                return "🔋 电池 \(batteryPercentage)% · 预计可用 \(timeStr)"
            } else {
                return "🔋 电池 \(batteryPercentage)%"
            }
        }
    }
}
