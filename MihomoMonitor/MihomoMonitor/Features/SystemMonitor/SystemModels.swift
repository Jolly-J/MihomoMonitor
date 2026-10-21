//
//  SystemModels.swift
//  MihomoMonitor
//
//  [架构层级] Feature / SystemMonitor / 领域模型
//  [核心职责] 定义系统监控业务领域的数据模型，包括子标签页（CPU / 内存）、进程聚合指标项及系统全局状态模型。
//  [关键类型] SystemSubTab, SystemProcessItem, SystemGlobalMetrics, SystemProcessMetric
//  [依赖关系] 依赖 Foundation；被 SystemMonitorViewModel、SystemMetricsCollector 及各系统视图引用。
//  [并发安全] 纯值类型，符合 Sendable 规范，可跨线程安全传递。
//

import Foundation

// MARK: - System Sub Tabs
enum SystemSubTab: String, CaseIterable, Identifiable {
    case cpu = "处理器 CPU"
    case memory = "内存占用"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        }
    }
}

// MARK: - System Process Item
struct SystemProcessItem: Identifiable, Sendable {
    var id: String { name }
    let name: String
    let appPath: String?
    let cpuPercent: Double       // 绝对整机占比（0% ~ 100%）
    let memoryBytes: Int64       // 物理常驻内存，字节数
    let processCount: Int        // 聚合子进程数
}

// MARK: - System Global Metrics Snapshot
struct SystemGlobalMetrics: Sendable {
    var totalCpuUsage: Double = 0.0      // 0.0 ~ 100.0%
    var cpuCores: Int = 1
    var usedMemoryBytes: Int64 = 0
    var totalMemoryBytes: Int64 = 0
    var isACPower: Bool = true
    var isCharging: Bool = false
    var batteryPercentage: Int = 100
    var timeRemainingMinutes: Int? = nil
}
