//
//  SystemMonitorViewModel.swift
//  MihomoMonitor
//
//  [架构层级] Feature / SystemMonitor / 业务状态机
//  [核心职责] 管理系统性能监控界面的响应式状态，包含全局 CPU/内存指标、Top 进程排行榜（CPU 与内存维度），并协调 SystemMetricsCollector 的按需启停。
//  [关键类型] SystemMonitorViewModel（ObservableObject 单例）
//  [依赖关系] 依赖 SystemMetricsCollector、SystemModels；驱动 SystemDashboardView 与 SystemNavigationView。
//  [并发安全] 标记为 @MainActor，所有状态变更由主线程负责，避免数据竞争。
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class SystemMonitorViewModel: ObservableObject {
    static let shared = SystemMonitorViewModel()
    
    @Published var selectedSubTab: SystemSubTab = .cpu
    @Published var systemMetrics = SystemGlobalMetrics()
    @Published var topCpuProcesses: [SystemProcessItem] = []
    @Published var topMemoryProcesses: [SystemProcessItem] = []
    
    var currentList: [SystemProcessItem] {
        selectedSubTab == .cpu ? topCpuProcesses : topMemoryProcesses
    }
    
    private init() {}
    
    func start() {
        SystemMetricsCollector.shared.start()
    }
    
    func stop() {
        SystemMetricsCollector.shared.stop()
    }
    
    func updateMetrics(
        global: SystemGlobalMetrics,
        topCpu: [SystemProcessItem],
        topMemory: [SystemProcessItem]
    ) {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            self.systemMetrics = global
            self.topCpuProcesses = topCpu
            self.topMemoryProcesses = topMemory
        }
    }
}
